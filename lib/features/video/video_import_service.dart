import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/project.dart';
import '../../database/models/video_record.dart';
import '../../database/repositories/project_repository.dart';
import '../../database/repositories/video_repository.dart';
import '../../services/storage/app_paths.dart';
import 'media_probe.dart';
import 'video_picker.dart';

class VideoImportResult {
  const VideoImportResult({required this.video, required this.hasAudio});

  final VideoRecord video;
  final bool hasAudio;
}

/// Alur import video ke sebuah project (semuanya lokal, tanpa upload):
///
/// pilih video -> pindah/salin ke `projects/<id>/source.<ext>` -> baca metadata
/// -> buat thumbnail -> simpan record SQLite -> status project `videoAdded`.
///
/// Video disimpan sebagai SALINAN terkelola (`VideoSourceType.copied`) karena
/// FFmpeg membutuhkan path file biasa, bukan content:// URI.
class VideoImportService {
  VideoImportService({
    required Database db,
    required AppPaths paths,
    required VideoPicker picker,
    required MediaProbe probe,
    required Directory pickerCacheDir,
  })  : _paths = paths,
        _picker = picker,
        _probe = probe,
        _pickerCacheDir = pickerCacheDir,
        _videos = VideoRepository(db),
        _projects = ProjectRepository(db);

  final AppPaths _paths;
  final VideoPicker _picker;
  final MediaProbe _probe;
  final Directory _pickerCacheDir;
  final VideoRepository _videos;
  final ProjectRepository _projects;

  /// Sisa ruang minimal setelah menyalin video.
  static const _safetyMarginBytes = 200 * 1024 * 1024;

  /// Null bila pengguna membatalkan pemilihan.
  Future<VideoImportResult?> importInto(int projectId) async {
    final picked = await _picker.pick();
    if (picked == null) return null;

    final source = File(picked.path);
    if (!await source.exists() || await source.length() == 0) {
      throw const AppException(
        'File video kosong atau tidak dapat dibaca.',
        code: 'invalid_video',
      );
    }

    await _paths.ensureProjectDir(projectId);
    final dest = File(p.join(
      _paths.projectDir(projectId).path,
      'source${_safeExtension(picked.name)}',
    ));
    File? thumbnail;
    int? savedVideoId;

    try {
      await _placeFile(source, dest);

      final meta = await _probe.probe(dest.path);

      final thumbFile = File(p.join(
        _paths.thumbnails.path,
        '${projectId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ));
      final positionMs =
          meta.durationMs < 2000 ? meta.durationMs ~/ 2 : 1000;
      final thumbOk = await _probe.generateThumbnail(
        videoPath: dest.path,
        outputPath: thumbFile.path,
        positionMs: positionMs,
      );
      if (thumbOk && await thumbFile.exists()) {
        thumbnail = thumbFile;
      } else {
        AppLogger.i('Thumbnail tidak dibuat untuk project $projectId');
      }

      final saved = await _videos.insert(VideoRecord(
        projectId: projectId,
        filePath: dest.path,
        fileName: picked.name,
        sourceType: VideoSourceType.copied,
        durationMs: meta.durationMs,
        width: meta.width,
        height: meta.height,
        fileSize: await dest.length(),
        thumbnailPath: thumbnail?.path,
        createdAt: DateTime.now(),
      ));
      savedVideoId = saved.id;

      await _projects.setSourceVideo(projectId, saved.id!);
      await _projects.updateStatus(projectId, ProjectStatus.videoAdded);

      return VideoImportResult(video: saved, hasAudio: meta.hasAudio);
    } catch (_) {
      // Jangan tinggalkan file atau baris setengah jadi.
      await _safeDelete(dest);
      await _safeDelete(thumbnail);
      if (savedVideoId != null) {
        await _videos.delete(savedVideoId);
      }
      rethrow;
    }
  }

  /// Menaruh video di [dest].
  ///
  /// - Sumber di cache aplikasi (hasil picker): dipindah (cepat), bila beda
  ///   partisi disalin lalu salinan cache dihapus.
  /// - Sumber di tempat lain (file asli pengguna): hanya DISALIN, sumber
  ///   TIDAK PERNAH dipindah atau dihapus.
  Future<void> _placeFile(File source, File dest) async {
    if (await dest.exists()) await dest.delete();

    final inCache = p.isWithin(_pickerCacheDir.path, source.path);
    if (inCache) {
      try {
        await source.rename(dest.path);
        return;
      } on FileSystemException {
        // Beda partisi; lanjut ke salin.
      }
    }

    final free = await _probe.freeSpaceBytes(dest.parent.path);
    final size = await source.length();
    if (free < size + _safetyMarginBytes) {
      throw const InsufficientStorageException(
          'Storage tidak cukup untuk menyimpan video.');
    }

    await source.copy(dest.path);

    if (inCache) {
      try {
        await source.delete();
      } on FileSystemException catch (e) {
        AppLogger.e('Gagal menghapus salinan cache picker', e);
      }
    }
  }

  String _safeExtension(String name) {
    final ext = p.extension(name).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{2,4}$').hasMatch(ext) ? ext : '.mp4';
  }

  Future<void> _safeDelete(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      AppLogger.e('Gagal membersihkan ${file.path}', e);
    }
  }
}
