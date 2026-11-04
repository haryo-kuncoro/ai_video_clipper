import 'face_models.dart';

/// Waktu sampel frame yang tersebar merata di dalam rentang clip:
/// satu frame tiap ~[intervalMs], minimal 3 dan maksimal [maxSamples].
List<int> sampleTimes(
  int startMs,
  int endMs, {
  int intervalMs = 2000,
  int maxSamples = 15,
}) {
  final duration = endMs - startMs;
  if (duration <= 0) return const [];
  final n = (duration ~/ intervalMs).clamp(3, maxSamples).toInt();
  return [
    for (var i = 0; i < n; i++) startMs + (duration * (i + 0.5) / n).round(),
  ];
}

double _median(List<double> values) {
  final v = [...values]..sort();
  final mid = v.length ~/ 2;
  return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

/// Menentukan titik fokus crop dari hasil deteksi.
///
/// - Per frame dipilih wajah terbesar (subjek utama); wajah yang terlalu
///   kecil ([minFaceSize]) dianggap derau.
/// - Posisi akhir adalah MEDIAN antar-frame sehingga tahan terhadap satu-dua
///   deteksi keliru.
/// - Bila wajah muncul di kurang dari [minHitRatio] frame, hasilnya null
///   dan pemanggil memakai center crop.
FocusResult? planFocus(
  List<FaceSample> samples, {
  double minHitRatio = 0.3,
  double minFaceSize = 0.03,
}) {
  if (samples.isEmpty) return null;

  final xs = <double>[];
  final ys = <double>[];
  for (final s in samples) {
    FaceBox? best;
    for (final f in s.faces) {
      if (f.size < minFaceSize) continue;
      if (best == null || f.size > best.size) best = f;
    }
    if (best != null) {
      xs.add(best.x);
      ys.add(best.y);
    }
  }

  if (xs.isEmpty || xs.length / samples.length < minHitRatio) return null;
  return FocusResult(
    x: _median(xs),
    y: _median(ys),
    hits: xs.length,
    samples: samples.length,
  );
}
