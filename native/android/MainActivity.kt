package com.haryo.ai_video_clipper

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.PointF
import android.media.FaceDetector
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Jembatan native untuk AI Video Clipper (STEP 4).
 *
 * Channel "com.haryo.ai_video_clipper/media":
 *  - probe(path)                      -> durasi, resolusi, rotasi, ada-audio
 *  - thumbnail(path, output, ms, w)   -> JPEG thumbnail
 *  - freeSpace(path)                  -> byte kosong pada partisi path
 *  - detectFaces(path, timesMs, w)    -> wajah per frame (STEP 14)
 *  - exportFile(source, name, mime, target) -> salin ke MediaStore (STEP 16)
 *  - shareUri(uri, mime)              -> bagikan lewat share sheet (STEP 16)
 *  - keepAliveStart/Update/Stop       -> foreground service + notifikasi (STEP 17)
 *
 * Semua pekerjaan berjalan di thread latar (bukan UI thread) dan hanya
 * membaca file lewat path; video tidak pernah dimuat utuh ke RAM.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.haryo.ai_video_clipper/media"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private class InvalidVideoException(message: String) : Exception(message)

    private class ExportException(val code: String, message: String) : Exception(message)

    private val storagePermissionRequest = 4216
    private var permissionLatch: CountDownLatch? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "probe" -> {
                        val path = call.argument<String>("path")
                        runAsync(result) { probe(path) }
                    }
                    "thumbnail" -> {
                        val path = call.argument<String>("path")
                        val output = call.argument<String>("output")
                        val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                        val maxWidth = call.argument<Number>("maxWidth")?.toInt() ?: 480
                        runAsync(result) { thumbnail(path, output, positionMs, maxWidth) }
                    }
                    "freeSpace" -> {
                        val path = call.argument<String>("path")
                        runAsync(result) { freeSpace(path) }
                    }
                    "detectFaces" -> {
                        val path = call.argument<String>("path")
                        val times = call.argument<List<Number>>("timesMs")
                        val maxWidth = call.argument<Number>("maxWidth")?.toInt() ?: 480
                        runAsync(result) { detectFaces(path, times, maxWidth) }
                    }
                    "exportFile" -> {
                        val source = call.argument<String>("source")
                        val name = call.argument<String>("displayName")
                        val mime = call.argument<String>("mimeType")
                        val target = call.argument<String>("target")
                        runAsync(result) { exportFile(source, name, mime, target) }
                    }
                    "shareUri" -> {
                        val uri = call.argument<String>("uri")
                        val mime = call.argument<String>("mimeType")
                        shareUri(uri, mime, result)
                    }
                    "keepAliveStart" -> {
                        val title = call.argument<String>("title") ?: "AI Video Clipper"
                        val text = call.argument<String>("text") ?: "Memproses…"
                        keepAliveStart(title, text, result)
                    }
                    "keepAliveUpdate" -> {
                        val title = call.argument<String>("title") ?: "AI Video Clipper"
                        val text = call.argument<String>("text") ?: ""
                        val progress = call.argument<Number>("progress")?.toInt() ?: -1
                        try {
                            KeepAliveService.update(this, title, text, progress)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "keepAliveStop" -> {
                        try {
                            val stop = Intent(this, KeepAliveService::class.java)
                                .setAction(KeepAliveService.ACTION_STOP)
                            startService(stop)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: InvalidVideoException) {
                mainHandler.post { result.error("invalid_video", e.message, null) }
            } catch (e: ExportException) {
                mainHandler.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("native_error", e.message, null) }
            }
        }
    }

    private fun probe(path: String?): Map<String, Any> {
        if (path.isNullOrEmpty()) throw InvalidVideoException("path kosong")
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)

            val hasVideo =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val duration = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
            var width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            var height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val hasAudio =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"

            if (!hasVideo || duration == null || duration <= 0 || width <= 0 || height <= 0) {
                throw InvalidVideoException("metadata video tidak lengkap")
            }

            // Video ponsel sering disimpan landscape dengan rotasi 90/270.
            if (rotation == 90 || rotation == 270) {
                val tmp = width
                width = height
                height = tmp
            }

            return mapOf(
                "durationMs" to duration,
                "width" to width,
                "height" to height,
                "rotation" to rotation,
                "hasAudio" to hasAudio
            )
        } catch (e: InvalidVideoException) {
            throw e
        } catch (e: RuntimeException) {
            throw InvalidVideoException(e.message ?: "video tidak dapat dibaca")
        } finally {
            retriever.release()
        }
    }

    private fun thumbnail(path: String?, output: String?, positionMs: Long, maxWidth: Int): Boolean {
        if (path.isNullOrEmpty() || output.isNullOrEmpty()) return false
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            var frame: Bitmap? = retriever.getFrameAtTime(
                positionMs * 1000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            ) ?: retriever.getFrameAtTime(0L)
            if (frame == null) return false

            if (maxWidth > 0 && frame.width > maxWidth) {
                val scaledHeight = (frame.height.toLong() * maxWidth / frame.width).toInt()
                val scaled = Bitmap.createScaledBitmap(frame, maxWidth, scaledHeight, true)
                if (scaled !== frame) frame.recycle()
                frame = scaled
            }

            val outFile = File(output)
            outFile.parentFile?.mkdirs()
            FileOutputStream(outFile).use { stream ->
                frame.compress(Bitmap.CompressFormat.JPEG, 85, stream)
            }
            frame.recycle()
            return true
        } catch (e: Exception) {
            return false
        } finally {
            retriever.release()
        }
    }

    private val maxFaces = 4

    /**
     * Mendeteksi wajah pada frame di [times] (ms). Memakai
     * android.media.FaceDetector (AOSP, offline). Nilai dikembalikan
     * ternormalisasi 0..1. Frame bermasalah dilewati (daftar wajah kosong).
     */
    private fun detectFaces(
        path: String?,
        times: List<Number>?,
        maxWidth: Int
    ): List<Map<String, Any>> {
        if (path.isNullOrEmpty() || times == null) return emptyList()
        val retriever = MediaMetadataRetriever()
        val out = ArrayList<Map<String, Any>>()
        try {
            retriever.setDataSource(path)
            for (t in times) {
                val ms = t.toLong()
                val faces = ArrayList<Map<String, Double>>()
                var frame: Bitmap? = null
                try {
                    frame = retriever.getFrameAtTime(
                        ms * 1000L,
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                    )
                    if (frame != null) faces.addAll(findFaces(frame, maxWidth))
                } catch (e: Exception) {
                    // Frame bermasalah diabaikan.
                } finally {
                    frame?.recycle()
                }
                out.add(mapOf("timeMs" to ms, "faces" to faces))
            }
            return out
        } finally {
            retriever.release()
        }
    }

    private fun findFaces(source: Bitmap, maxWidth: Int): List<Map<String, Double>> {
        var w = if (maxWidth > 0 && source.width > maxWidth) maxWidth else source.width
        if (w % 2 != 0) w -= 1 // FaceDetector mensyaratkan lebar genap
        if (w < 32) return emptyList()
        val h = (source.height.toLong() * w / source.width).toInt()
        if (h < 32) return emptyList()

        val scaled = Bitmap.createScaledBitmap(source, w, h, true)
        val rgb565 = scaled.copy(Bitmap.Config.RGB_565, false)
        if (scaled !== source) scaled.recycle()
        if (rgb565 == null) return emptyList()

        try {
            val detector = FaceDetector(rgb565.width, rgb565.height, maxFaces)
            val found = arrayOfNulls<FaceDetector.Face>(maxFaces)
            val count = detector.findFaces(rgb565, found)
            val res = ArrayList<Map<String, Double>>()
            for (i in 0 until count) {
                val face = found[i] ?: continue
                if (face.confidence() < 0.4f) continue
                val mid = PointF()
                face.getMidPoint(mid)
                res.add(
                    mapOf(
                        "x" to (mid.x / rgb565.width).toDouble(),
                        "y" to (mid.y / rgb565.height).toDouble(),
                        "size" to (face.eyesDistance() * 2.2 / rgb565.width)
                    )
                )
            }
            return res
        } finally {
            rgb565.recycle()
        }
    }

    private fun freeSpace(path: String?): Long {
        if (path.isNullOrEmpty()) return 0L
        var dir = File(path)
        while (!dir.exists()) {
            dir = dir.parentFile ?: return 0L
        }
        return StatFs(dir.absolutePath).availableBytes
    }
    // ---------------------------------------------------------------
    // STEP 16: ekspor ke galeri (MediaStore / Scoped Storage)
    // ---------------------------------------------------------------

    private val exportFolder = "AI Video Clipper"

    /**
     * Menyalin file hasil render ke galeri (Movies/AI Video Clipper) atau
     * Downloads/AI Video Clipper (target "download", mis. untuk .srt).
     * File asli TIDAK diubah/dihapus. Mengembalikan URI hasil ekspor.
     *
     * Android 10+ memakai MediaStore (tanpa izin). Android 9 ke bawah
     * memerlukan izin WRITE_EXTERNAL_STORAGE (diminta saat ekspor pertama).
     */
    private fun exportFile(source: String?, name: String?, mime: String?, target: String?): String {
        if (source.isNullOrEmpty() || name.isNullOrEmpty()) {
            throw ExportException("export_failed", "data ekspor tidak lengkap")
        }
        val src = File(source)
        if (!src.exists() || !src.isFile) {
            throw ExportException("file_missing", "file sumber tidak ditemukan")
        }
        val mimeType = if (mime.isNullOrEmpty()) "application/octet-stream" else mime
        val isVideo = target != "download"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            exportScoped(src, name, mimeType, isVideo)
        } else {
            exportLegacy(src, name, mimeType, isVideo)
        }
    }

    private fun exportScoped(src: File, name: String, mime: String, isVideo: Boolean): String {
        val collection: Uri = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val base = if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_DOWNLOADS
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$base/$exportFolder")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw ExportException("export_failed", "MediaStore menolak entri baru")
        try {
            val out = resolver.openOutputStream(uri)
                ?: throw ExportException("export_failed", "tidak dapat membuka tujuan")
            out.use { o -> src.inputStream().use { i -> i.copyTo(o, 64 * 1024) } }
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
            return uri.toString()
        } catch (e: Exception) {
            // Jangan tinggalkan entri setengah jadi di galeri.
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            if (e is ExportException) throw e
            throw ExportException("export_failed", e.message ?: "gagal menyalin")
        }
    }

    @Suppress("DEPRECATION")
    private fun exportLegacy(src: File, name: String, mime: String, isVideo: Boolean): String {
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            val latch = CountDownLatch(1)
            permissionLatch = latch
            mainHandler.post {
                requestPermissions(
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    storagePermissionRequest
                )
            }
            latch.await(120, TimeUnit.SECONDS)
            if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED
            ) {
                throw ExportException("permission_denied", "izin penyimpanan ditolak")
            }
        }
        val baseDir = Environment.getExternalStoragePublicDirectory(
            if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_DOWNLOADS
        )
        val dir = File(baseDir, exportFolder)
        if (!dir.exists() && !dir.mkdirs()) {
            throw ExportException("export_failed", "folder tujuan tidak dapat dibuat")
        }
        var target = File(dir, name)
        var n = 1
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        while (target.exists()) {
            target = File(dir, "$stem ($n)$ext")
            n++
        }
        try {
            src.inputStream().use { i -> FileOutputStream(target).use { o -> i.copyTo(o, 64 * 1024) } }
        } catch (e: Exception) {
            target.delete()
            throw ExportException("export_failed", e.message ?: "gagal menyalin")
        }
        val latch = CountDownLatch(1)
        var scanned: Uri? = null
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime)) { _, uri ->
            scanned = uri
            latch.countDown()
        }
        latch.await(5, TimeUnit.SECONDS)
        return (scanned ?: Uri.fromFile(target)).toString()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == storagePermissionRequest) {
            permissionLatch?.countDown()
            permissionLatch = null
        }
    }

    private fun shareUri(uri: String?, mime: String?, result: MethodChannel.Result) {
        try {
            if (uri.isNullOrEmpty() || uri.startsWith("file:")) {
                result.error("share_failed", "URI tidak dapat dibagikan", null)
                return
            }
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = if (mime.isNullOrEmpty()) "*/*" else mime
                putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Bagikan clip"))
            result.success(true)
        } catch (e: Exception) {
            result.error("share_failed", e.message, null)
        }
    }
    // ---------------------------------------------------------------
    // STEP 17: foreground service
    // ---------------------------------------------------------------

    private val notificationPermissionRequest = 4217

    /**
     * Memulai foreground service. Pada Android 13+ izin notifikasi diminta
     * (bila ditolak, service tetap berjalan; hanya notifikasinya tidak tampil).
     * Mengembalikan false bila sistem menolak (mis. dipanggil dari latar
     * belakang); proses tetap berjalan seperti biasa tanpa penahan.
     */
    private fun keepAliveStart(title: String, text: String, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    notificationPermissionRequest
                )
            }
            val intent = Intent(this, KeepAliveService::class.java)
                .putExtra(KeepAliveService.EXTRA_TITLE, title)
                .putExtra(KeepAliveService.EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
