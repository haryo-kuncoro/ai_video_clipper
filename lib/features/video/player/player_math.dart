/// Logika murni untuk player (mudah dites tanpa platform video).

/// Membatasi posisi seek ke rentang [0, durationMs].
int clampSeekMs(int targetMs, int durationMs) {
  if (durationMs <= 0) return 0;
  if (targetMs < 0) return 0;
  if (targetMs > durationMs) return durationMs;
  return targetMs;
}

/// Posisi setelah lompat [deltaMs] (negatif = mundur), tetap dalam rentang.
int skipMs(int currentMs, int deltaMs, int durationMs) =>
    clampSeekMs(currentMs + deltaMs, durationMs);

/// Nilai 0.0 - 1.0 untuk slider; aman bila durasi 0.
double progressFraction(int positionMs, int durationMs) {
  if (durationMs <= 0) return 0;
  return (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
}

/// Kecepatan putar yang tersedia.
const List<double> playbackSpeeds = [0.5, 1.0, 1.5, 2.0];

/// Kecepatan berikutnya (berputar kembali ke awal).
double nextPlaybackSpeed(double current) {
  final i = playbackSpeeds.indexOf(current);
  if (i < 0) return 1.0;
  return playbackSpeeds[(i + 1) % playbackSpeeds.length];
}

String speedLabel(double speed) =>
    speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';
