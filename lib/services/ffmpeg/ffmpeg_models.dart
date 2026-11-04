enum FFmpegStatus { success, failed, cancelled }

/// Hasil satu pekerjaan FFmpeg.
class FFmpegResult {
  const FFmpegResult({
    required this.status,
    this.outputPath,
    this.message,
    this.logs = '',
  });

  final FFmpegStatus status;

  /// File hasil (null untuk pekerjaan tanpa output, mis. diagnostik).
  final String? outputPath;

  /// Pesan ramah pengguna bila gagal/dibatalkan. Bukan stack trace.
  final String? message;

  /// Log mentah FFmpeg (untuk debug/diagnostik, jangan tampilkan ke pengguna).
  final String logs;

  bool get ok => status == FFmpegStatus.success;
  bool get cancelled => status == FFmpegStatus.cancelled;
}

/// Satu pekerjaan dalam antrean FFmpeg.
class FFmpegTask {
  const FFmpegTask({
    required this.id,
    required this.label,
    required this.args,
    this.outputPath,
    this.expectedDurationMs,
    this.onProgress,
  });

  final String id;
  final String label;

  /// Argumen FFmpeg sebagai LIST (bukan string shell) sehingga path dengan
  /// spasi atau karakter khusus aman.
  final List<String> args;

  /// File output yang diharapkan ada setelah sukses; dihapus bila gagal atau
  /// dibatalkan agar tidak meninggalkan file setengah jadi.
  final String? outputPath;

  /// Durasi output yang diharapkan, untuk menghitung progres 0.0 - 1.0.
  final int? expectedDurationMs;

  final void Function(double fraction)? onProgress;
}
