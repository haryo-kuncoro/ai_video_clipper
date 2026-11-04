import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';

class VideoMetadata {
  const VideoMetadata({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
  });

  final int durationMs;

  /// Sudah memperhitungkan rotasi (mis. video ponsel portrait = tinggi > lebar).
  final int width;
  final int height;
  final bool hasAudio;

  bool get isPortrait => height > width;
}

/// Membaca metadata video dan membuat thumbnail. Diabstraksikan agar mudah
/// diganti/di-fake saat testing.
abstract class MediaProbe {
  Future<VideoMetadata> probe(String path);

  Future<bool> generateThumbnail({
    required String videoPath,
    required String outputPath,
    required int positionMs,
    int maxWidth = 480,
  });

  /// Byte kosong pada partisi tempat [path] berada.
  Future<int> freeSpaceBytes(String path);
}

/// Implementasi native Android (MediaMetadataRetriever) lewat MethodChannel.
/// Kodenya ada di `native/android/MainActivity.kt`.
class NativeMediaProbe implements MediaProbe {
  static const _channel = MethodChannel('com.haryo.ai_video_clipper/media');

  static const _invalidVideo = AppException(
    'Video tidak valid atau format tidak didukung.',
    code: 'invalid_video',
  );

  static const _nativeMissing = AppException(
    'Komponen native belum terpasang. Salin MainActivity.kt sesuai README.',
    code: 'native_missing',
  );

  @override
  Future<VideoMetadata> probe(String path) async {
    try {
      final map = await _channel
          .invokeMapMethod<String, Object?>('probe', {'path': path});
      if (map == null) throw _invalidVideo;

      final duration = (map['durationMs'] as num?)?.toInt() ?? 0;
      final width = (map['width'] as num?)?.toInt() ?? 0;
      final height = (map['height'] as num?)?.toInt() ?? 0;
      if (duration <= 0 || width <= 0 || height <= 0) throw _invalidVideo;

      return VideoMetadata(
        durationMs: duration,
        width: width,
        height: height,
        hasAudio: map['hasAudio'] == true,
      );
    } on PlatformException catch (e) {
      if (e.code == 'invalid_video') {
        // Alasan teknis dari sisi Android, hanya untuk log (bukan untuk pengguna).
        AppLogger.e('Probe video ditolak: ${e.message} | path=$path', e);
        throw _invalidVideo;
      }
      throw AppException('Video tidak dapat dibaca.', code: e.code, cause: e);
    } on MissingPluginException {
      throw _nativeMissing;
    }
  }

  @override
  Future<bool> generateThumbnail({
    required String videoPath,
    required String outputPath,
    required int positionMs,
    int maxWidth = 480,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('thumbnail', {
        'path': videoPath,
        'output': outputPath,
        'positionMs': positionMs,
        'maxWidth': maxWidth,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<int> freeSpaceBytes(String path) async {
    try {
      final free =
          await _channel.invokeMethod<num>('freeSpace', {'path': path});
      return free?.toInt() ?? 0;
    } on MissingPluginException {
      throw _nativeMissing;
    } on PlatformException catch (e) {
      throw AppException('Ruang penyimpanan tidak dapat diperiksa.',
          code: e.code, cause: e);
    }
  }
}
