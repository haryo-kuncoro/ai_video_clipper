import '../../core/errors/app_exception.dart';

const minClipMs = 3000;
const maxClipMs = 180000;

/// Merapikan rentang waktu clip hasil edit pengguna: dijaga dalam durasi
/// video lalu divalidasi batas durasi. Melempar [AppException] ramah.
({int startMs, int endMs}) normalizeRange({
  required int startMs,
  required int endMs,
  required int videoDurationMs,
}) {
  var s = startMs < 0 ? 0 : startMs;
  var e = endMs;
  if (videoDurationMs > 0 && e > videoDurationMs) e = videoDurationMs;
  if (videoDurationMs > 0 && s > videoDurationMs) s = videoDurationMs;

  if (e - s < minClipMs) {
    throw const AppException(
      'Durasi clip minimal 3 detik.',
      code: 'clip_too_short',
    );
  }
  if (e - s > maxClipMs) {
    throw const AppException(
      'Durasi clip maksimal 3 menit.',
      code: 'clip_too_long',
    );
  }
  return (startMs: s, endMs: e);
}

/// "mm:ss.d" atau "h:mm:ss.d" untuk menampilkan posisi dengan 1 desimal.
String formatPreciseMs(int ms) {
  final v = ms < 0 ? 0 : ms;
  final tenth = (v % 1000) ~/ 100;
  final total = v ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  final base = h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  return '$base.$tenth';
}
