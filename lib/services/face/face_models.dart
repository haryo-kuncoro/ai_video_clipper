/// Satu wajah pada satu frame. Semua nilai ternormalisasi 0.0 - 1.0
/// terhadap ukuran frame.
class FaceBox {
  const FaceBox({required this.x, required this.y, required this.size});

  /// Titik tengah wajah.
  final double x;
  final double y;

  /// Perkiraan lebar wajah relatif terhadap lebar frame.
  final double size;
}

/// Hasil deteksi pada satu waktu video.
class FaceSample {
  const FaceSample({required this.timeMs, this.faces = const []});

  final int timeMs;
  final List<FaceBox> faces;
}

/// Titik fokus crop hasil agregasi beberapa frame.
class FocusResult {
  const FocusResult({
    required this.x,
    required this.y,
    required this.hits,
    required this.samples,
  });

  final double x;
  final double y;

  /// Jumlah frame yang berisi wajah dari total [samples] frame.
  final int hits;
  final int samples;
}
