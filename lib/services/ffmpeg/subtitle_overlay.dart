/// Batas jumlah gambar subtitle dalam satu proses FFmpeg (satu clip).
const int maxSubtitleOverlays = 120;

/// Satu gambar subtitle (PNG transparan) yang ditempel pada rentang waktu
/// tertentu. Waktu RELATIF terhadap awal clip (0 = frame pertama clip).
///
/// Subtitle dibakar lewat filter `overlay` (filter inti FFmpeg), bukan
/// `subtitles`/libass, sehingga tidak bergantung pada library font atau
/// libass di build FFmpeg perangkat.
class SubtitleOverlay {
  const SubtitleOverlay({
    required this.imagePath,
    required this.startMs,
    required this.endMs,
    required this.y,
  });

  final String imagePath;
  final int startMs;
  final int endMs;

  /// Posisi vertikal (piksel dari atas) pada frame output.
  final int y;
}
