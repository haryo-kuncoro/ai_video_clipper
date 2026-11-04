import 'face_models.dart';

/// Kontrak detektor wajah lokal. Implementasi bawaan: [NativeFaceDetector]
/// (android.media.FaceDetector milik Android, offline, tanpa dependency).
/// Dapat diganti dengan detektor lain (mis. MediaPipe) tanpa mengubah
/// perencana fokus maupun service render.
abstract class VideoFaceDetector {
  /// Mendeteksi wajah pada frame di [timesMs] (ms dari awal video).
  /// Mengembalikan satu [FaceSample] per waktu, urut sesuai input.
  Future<List<FaceSample>> detect({
    required String videoPath,
    required List<int> timesMs,
  });
}
