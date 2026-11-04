import 'subtitle_overlay.dart';

/// Pembuat argumen FFmpeg (fungsi murni, mudah dites tanpa FFmpeg).
///
/// Semua method mengembalikan LIST argumen, tanpa kata "ffmpeg" di depan.
/// `-y` menimpa output yang sudah ada; `-hide_banner` mengurangi log.
class FFmpegCommands {
  FFmpegCommands._();

  static const List<String> _base = ['-hide_banner', '-y'];

  static String _sec(int ms) => (ms / 1000).toStringAsFixed(3);

  static const List<String> _h264 = [
    '-c:v', 'libx264',
    '-preset', 'veryfast',
    '-crf', '23',
    '-pix_fmt', 'yuv420p',
  ];

  static const List<String> _aac = ['-c:a', 'aac', '-b:a', '128k'];

  /// Memotong [startMs]..[endMs].
  ///
  /// - `fast: false` (default): re-encode, potongan TEPAT pada frame yang diminta.
  /// - `fast: true`: stream copy, sangat cepat tetapi titik potong menyesuaikan
  ///   keyframe terdekat (kurang presisi).
  static List<String> cut({
    required String input,
    required String output,
    required int startMs,
    required int endMs,
    bool fast = false,
  }) {
    if (startMs < 0 || endMs <= startMs) {
      throw ArgumentError('Rentang waktu tidak valid: $startMs..$endMs');
    }
    return [
      ..._base,
      '-ss', _sec(startMs),
      '-i', input,
      '-t', _sec(endMs - startMs),
      if (fast) ...['-c', 'copy', '-avoid_negative_ts', 'make_zero']
      else ...[..._h264, ..._aac],
      '-movflags', '+faststart',
      output,
    ];
  }

  /// Audio mono 16 kHz PCM WAV: format yang dipakai Whisper (STEP 9).
  static List<String> extractAudio({
    required String input,
    required String output,
  }) {
    return [
      ..._base,
      '-i', input,
      '-vn',
      '-ac', '1',
      '-ar', '16000',
      '-c:a', 'pcm_s16le',
      output,
    ];
  }

  /// Satu frame JPEG pada [positionMs], lebar [width] (tinggi menyesuaikan).
  static List<String> thumbnail({
    required String input,
    required String output,
    required int positionMs,
    int width = 480,
  }) {
    return [
      ..._base,
      '-ss', _sec(positionMs < 0 ? 0 : positionMs),
      '-i', input,
      '-frames:v', '1',
      '-vf', 'scale=$width:-2',
      '-q:v', '3',
      output,
    ];
  }

  /// Mengubah ukuran tanpa stretch: isi salah satu atau keduanya.
  /// Sisi yang kosong dihitung otomatis mengikuti rasio (dibulatkan genap).
  static List<String> resize({
    required String input,
    required String output,
    int? width,
    int? height,
  }) {
    if (width == null && height == null) {
      throw ArgumentError('width atau height harus diisi');
    }
    return [
      ..._base,
      '-i', input,
      '-vf', 'scale=${width ?? -2}:${height ?? -2}',
      ..._h264,
      '-c:a', 'copy',
      '-movflags', '+faststart',
      output,
    ];
  }

  /// Crop area persegi panjang [width]x[height] mulai dari ([x],[y]).
  static List<String> crop({
    required String input,
    required String output,
    required int width,
    required int height,
    required int x,
    required int y,
  }) {
    if (width <= 0 || height <= 0 || x < 0 || y < 0) {
      throw ArgumentError('Area crop tidak valid');
    }
    return [
      ..._base,
      '-i', input,
      '-vf', 'crop=$width:$height:$x:$y',
      ..._h264,
      '-c:a', 'copy',
      '-movflags', '+faststart',
      output,
    ];
  }

  /// Crop lalu skala ke portrait ([outWidth]x[outHeight]) dalam SATU kali
  /// encode. Opsional memotong sekaligus [startMs]..[endMs] (keduanya atau
  /// tidak sama sekali). Rasio crop sudah 9:16, jadi tidak ada stretch.
  static List<String> portrait({
    required String input,
    required String output,
    required int cropX,
    required int cropY,
    required int cropWidth,
    required int cropHeight,
    required int outWidth,
    required int outHeight,
    int? startMs,
    int? endMs,
  }) {
    if (cropWidth <= 0 || cropHeight <= 0 || cropX < 0 || cropY < 0) {
      throw ArgumentError('Area crop tidak valid');
    }
    if (outWidth <= 0 || outHeight <= 0) {
      throw ArgumentError('Ukuran output tidak valid');
    }
    if ((startMs == null) != (endMs == null)) {
      throw ArgumentError('startMs dan endMs harus diisi bersamaan');
    }
    if (startMs != null && endMs != null && (startMs < 0 || endMs <= startMs)) {
      throw ArgumentError('Rentang waktu tidak valid: $startMs..$endMs');
    }

    final filter = 'crop=$cropWidth:$cropHeight:$cropX:$cropY,'
        'scale=$outWidth:$outHeight:flags=lanczos,setsar=1';

    return [
      ..._base,
      if (startMs != null && endMs != null) ...['-ss', _sec(startMs)],
      '-i', input,
      if (startMs != null && endMs != null) ...['-t', _sec(endMs - startMs)],
      '-vf', filter,
      ..._h264,
      ..._aac,
      '-movflags', '+faststart',
      output,
    ];
  }

  /// Membakar subtitle (gambar PNG dari SubtitleRenderer) ke video dalam SATU
  /// kali encode, opsional sekaligus crop+scale portrait dan memotong rentang
  /// [startMs]..[endMs]. Waktu pada [overlays] relatif terhadap awal rentang.
  ///
  /// Memakai filter inti `overlay` (bukan libass), jadi tidak butuh font.
  static List<String> burnSubtitles({
    required String input,
    required String output,
    required List<SubtitleOverlay> overlays,
    int? cropX,
    int? cropY,
    int? cropWidth,
    int? cropHeight,
    int? outWidth,
    int? outHeight,
    int? startMs,
    int? endMs,
  }) {
    if (overlays.isEmpty) {
      throw ArgumentError('Daftar subtitle kosong');
    }
    if ((startMs == null) != (endMs == null)) {
      throw ArgumentError('startMs dan endMs harus diisi bersamaan');
    }
    if (startMs != null && endMs != null && (startMs < 0 || endMs <= startMs)) {
      throw ArgumentError('Rentang waktu tidak valid: $startMs..$endMs');
    }

    final String base;
    if (cropX == null &&
        cropY == null &&
        cropWidth == null &&
        cropHeight == null &&
        outWidth == null &&
        outHeight == null) {
      base = 'null';
    } else if (cropX == null ||
        cropY == null ||
        cropWidth == null ||
        cropHeight == null ||
        outWidth == null ||
        outHeight == null) {
      throw ArgumentError('Parameter crop harus lengkap');
    } else {
      if (cropWidth <= 0 ||
          cropHeight <= 0 ||
          cropX < 0 ||
          cropY < 0 ||
          outWidth <= 0 ||
          outHeight <= 0) {
        throw ArgumentError('Area crop atau ukuran output tidak valid');
      }
      base = 'crop=$cropWidth:$cropHeight:$cropX:$cropY,'
          'scale=$outWidth:$outHeight:flags=lanczos,setsar=1';
    }

    final graph = StringBuffer('[0:v]$base[b0]');
    for (var i = 0; i < overlays.length; i++) {
      final o = overlays[i];
      graph.write(';[b$i][${i + 1}:v]overlay=x=0:y=${o.y}:'
          "enable='between(t,${_sec(o.startMs)},${_sec(o.endMs)})'[b${i + 1}]");
    }

    return [
      ..._base,
      if (startMs != null && endMs != null) ...['-ss', _sec(startMs)],
      '-i', input,
      for (final o in overlays) ...['-i', o.imagePath],
      if (startMs != null && endMs != null) ...['-t', _sec(endMs - startMs)],
      '-filter_complex', graph.toString(),
      '-map', '[b${overlays.length}]',
      '-map', '0:a?',
      ..._h264,
      ..._aac,
      '-movflags', '+faststart',
      output,
    ];
  }

  /// Konversi ke MP4 (H.264 + AAC).
  static List<String> convertToMp4({
    required String input,
    required String output,
  }) {
    return [
      ..._base,
      '-i', input,
      ..._h264,
      ..._aac,
      '-movflags', '+faststart',
      output,
    ];
  }

  /// Daftar encoder yang tersedia (untuk diagnostik).
  static List<String> listEncoders() => ['-hide_banner', '-encoders'];

  /// Daftar filter yang tersedia (untuk diagnostik).
  static List<String> listFilters() => ['-hide_banner', '-filters'];
}
