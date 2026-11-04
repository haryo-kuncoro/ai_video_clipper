import 'ffmpeg_models.dart';

class FFmpegRunOutcome {
  const FFmpegRunOutcome({required this.status, this.logs = ''});

  final FFmpegStatus status;
  final String logs;
}

/// Pelaksana FFmpeg. Diabstraksikan agar paket FFmpeg hanya disentuh di SATU
/// file (`ffmpeg_kit_runner.dart`) dan queue/service bisa dites dengan fake.
abstract class FFmpegRunner {
  /// Menjalankan FFmpeg dan menunggu selesai. [onProgress] menerima durasi
  /// output yang sudah diproses (ms).
  Future<FFmpegRunOutcome> run(
    List<String> args, {
    void Function(int processedMs)? onProgress,
  });

  /// Membatalkan proses yang sedang berjalan.
  Future<void> cancel();
}
