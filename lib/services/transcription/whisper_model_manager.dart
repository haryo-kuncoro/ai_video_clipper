import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import 'transcription_models.dart';

class DownloadProgress {
  const DownloadProgress({
    required this.fileName,
    required this.fileIndex,
    required this.fileCount,
    required this.received,
    this.total,
  });

  final String fileName;
  final int fileIndex;
  final int fileCount;
  final int received;

  /// Null bila server tidak memberi ukuran.
  final int? total;

  double? get fileFraction =>
      (total == null || total == 0) ? null : received / total!;
}

class _Item {
  const _Item(this.name, this.url, this.file);

  final String name;
  final String url;
  final File file;
}

/// Mengelola model Whisper + Silero VAD di storage lokal aplikasi.
///
/// Ini SATU-SATUNYA bagian STEP 9 yang memakai internet, dan hanya untuk
/// mengunduh file model (sekali). Tidak ada video/audio/transcript yang
/// dikirim ke mana pun. Setelah model ada, transkripsi berjalan offline.
class WhisperModelManager {
  WhisperModelManager(
    this.modelsDir, {
    this.vadUrl = WhisperModels.vadUrl,
  });

  final Directory modelsDir;
  final String vadUrl;

  static const vadFileName = 'silero_vad.onnx';

  Directory modelDir(WhisperModelInfo m) =>
      Directory(p.join(modelsDir.path, m.dirName));

  File get _vadFile => File(p.join(modelsDir.path, vadFileName));

  List<_Item> _items(WhisperModelInfo m) {
    final dir = modelDir(m).path;
    return [
      _Item(m.encoderName, m.urlFor(m.encoderName),
          File(p.join(dir, m.encoderName))),
      _Item(m.decoderName, m.urlFor(m.decoderName),
          File(p.join(dir, m.decoderName))),
      _Item(m.tokensName, m.urlFor(m.tokensName),
          File(p.join(dir, m.tokensName))),
      _Item(vadFileName, vadUrl, _vadFile),
    ];
  }

  Future<bool> _ready(File f) async => await f.exists() && await f.length() > 0;

  Future<bool> isInstalled(WhisperModelInfo m) async {
    for (final i in _items(m)) {
      if (!await _ready(i.file)) return false;
    }
    return true;
  }

  Future<WhisperModelFiles> resolve(WhisperModelInfo m) async {
    if (!await isInstalled(m)) throw modelMissing(m);
    final items = _items(m);
    return WhisperModelFiles(
      encoder: items[0].file.path,
      decoder: items[1].file.path,
      tokens: items[2].file.path,
      vad: items[3].file.path,
    );
  }

  /// Ukuran model terpasang (tanpa VAD), untuk ditampilkan di UI.
  Future<int> installedSize(WhisperModelInfo m) async {
    var total = 0;
    final dir = modelDir(m);
    if (!await dir.exists()) return 0;
    await for (final e in dir.list()) {
      if (e is File && !e.path.endsWith('.part')) total += await e.length();
    }
    return total;
  }

  Future<void> delete(WhisperModelInfo m) async {
    try {
      final dir = modelDir(m);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      AppLogger.e('Gagal menghapus model', e);
      throw const StorageException('Model tidak dapat dihapus.');
    }
  }

  /// Mengunduh file yang belum ada. File yang sudah lengkap dilewati,
  /// sehingga unduhan yang terputus dapat dilanjutkan per file.
  Future<void> download(
    WhisperModelInfo m, {
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    final items = _items(m);
    try {
      await modelsDir.create(recursive: true);
      await modelDir(m).create(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Folder model tidak dapat dibuat.', cause: e);
    }

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (await _ready(item.file)) continue;
      await _downloadFile(
        item,
        index: i,
        count: items.length,
        onProgress: onProgress,
        cancel: cancel,
      );
    }
  }

  Future<void> _downloadFile(
    _Item item, {
    required int index,
    required int count,
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    final part = File('${item.file.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..autoUncompress = false;
    IOSink? sink;
    var finished = false;

    try {
      final request = await client.getUrl(Uri.parse(item.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw AppException(
          'Server model tidak dapat diakses (kode ${response.statusCode}).',
          code: 'model_http_${response.statusCode}',
        );
      }

      final total = response.contentLength >= 0 ? response.contentLength : null;
      sink = part.openWrite();
      var received = 0;
      final watch = Stopwatch()..start();
      var lastReport = -1000;

      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (cancel?.isCancelled ?? false) throw const TranscriptionCancelled();
        sink.add(chunk);
        received += chunk.length;
        final now = watch.elapsedMilliseconds;
        if (now - lastReport >= 150) {
          lastReport = now;
          onProgress?.call(DownloadProgress(
            fileName: item.name,
            fileIndex: index,
            fileCount: count,
            received: received,
            total: total,
          ));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (total != null && received != total) {
        throw const AppException(
          'Unduhan tidak lengkap. Coba lagi.',
          code: 'model_incomplete',
        );
      }
      if (received == 0) {
        throw const AppException('File model kosong.', code: 'model_empty');
      }

      if (await item.file.exists()) await item.file.delete();
      await part.rename(item.file.path);
      finished = true;
      onProgress?.call(DownloadProgress(
        fileName: item.name,
        fileIndex: index,
        fileCount: count,
        received: received,
        total: total ?? received,
      ));
    } on AppException {
      rethrow;
    } on TranscriptionCancelled {
      rethrow;
    } on SocketException catch (e) {
      AppLogger.e('Unduh model: jaringan', e);
      throw const AppException(
        'Tidak dapat mengunduh model. Periksa koneksi internet.',
        code: 'model_network',
      );
    } on TimeoutException {
      throw const AppException(
        'Koneksi terputus saat mengunduh model. Coba lagi.',
        code: 'model_timeout',
      );
    } on HandshakeException catch (e) {
      AppLogger.e('Unduh model: TLS', e);
      throw const AppException(
        'Koneksi aman ke server model gagal.',
        code: 'model_tls',
      );
    } on HttpException catch (e) {
      AppLogger.e('Unduh model: HTTP', e);
      throw const AppException(
        'Unduhan model gagal. Coba lagi.',
        code: 'model_http',
      );
    } on FileSystemException catch (e) {
      AppLogger.e('Unduh model: file', e);
      throw StorageException(
        'Model tidak dapat disimpan. Ruang penyimpanan mungkin penuh.',
        code: 'insufficient_storage',
        cause: e,
      );
    } finally {
      client.close(force: true);
      if (!finished) {
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
      }
    }
  }
}
