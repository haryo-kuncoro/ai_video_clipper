import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import 'face_detector.dart';
import 'face_models.dart';

/// Memakai `android.media.FaceDetector` lewat MethodChannel (kode native di
/// `native/android/MainActivity.kt`). Berjalan offline di thread latar;
/// hanya beberapa frame kecil yang dibaca, bukan seluruh video.
class NativeFaceDetector implements VideoFaceDetector {
  static const _channel = MethodChannel('com.haryo.ai_video_clipper/media');

  @override
  Future<List<FaceSample>> detect({
    required String videoPath,
    required List<int> timesMs,
  }) async {
    if (timesMs.isEmpty) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('detectFaces', {
        'path': videoPath,
        'timesMs': timesMs,
        'maxWidth': 480,
      });
      return parseFaceSamples(raw ?? const []);
    } on MissingPluginException {
      throw const AppException(
        'Komponen native belum terpasang. Salin MainActivity.kt sesuai README.',
        code: 'native_missing',
      );
    } on PlatformException catch (e) {
      throw AppException('Deteksi wajah gagal.', code: e.code, cause: e);
    }
  }
}

/// Mengubah balasan native menjadi [FaceSample]. Entri yang rusak dilewati.
List<FaceSample> parseFaceSamples(List<Object?> raw) {
  final out = <FaceSample>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final timeRaw = item['timeMs'];
    if (timeRaw is! num) continue;
    final time = timeRaw.toInt();

    final faces = <FaceBox>[];
    final list = item['faces'];
    if (list is List) {
      for (final f in list) {
        if (f is! Map) continue;
        final xr = f['x'];
        final yr = f['y'];
        final sr = f['size'];
        if (xr is! num || yr is! num || sr is! num) continue;
        final x = xr.toDouble();
        final y = yr.toDouble();
        final size = sr.toDouble();
        faces.add(FaceBox(
          x: x.clamp(0.0, 1.0).toDouble(),
          y: y.clamp(0.0, 1.0).toDouble(),
          size: size,
        ));
      }
    }
    out.add(FaceSample(timeMs: time, faces: faces));
  }
  return out;
}
