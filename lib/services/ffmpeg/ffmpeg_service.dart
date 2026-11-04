import '../../core/errors/app_exception.dart';
import 'ffmpeg_commands.dart';
import 'ffmpeg_models.dart';
import 'ffmpeg_queue.dart';
import 'portrait_plan.dart';
import 'subtitle_overlay.dart';

/// Kemampuan build FFmpeg yang terpasang (hasil [FFmpegService.diagnostics]).
class FFmpegDiagnostics {
  const FFmpegDiagnostics({
    required this.hasLibx264,
    required this.hasAac,
    required this.hasSubtitlesFilter,
    required this.hasDrawtextFilter,
  });

  final bool hasLibx264;
  final bool hasAac;

  /// Filter `subtitles` (libass), dipakai untuk merender subtitle (STEP 8).
  final bool hasSubtitlesFilter;
  final bool hasDrawtextFilter;
}

/// API tingkat tinggi FFmpeg lokal. Semua pekerjaan melewati antrean
/// sequential, jadi aman dipanggil dari mana saja.
///
/// `cropPortrait` (STEP 7) dan `burnSubtitle` (STEP 8) sudah tersedia.
class FFmpegService {
  FFmpegService(this._queue);

  final FFmpegQueue _queue;
  int _seq = 0;

  FFmpegQueue get queue => _queue;

  String _nextId(String prefix) => '$prefix-${++_seq}';

  Future<FFmpegResult> cutVideo({
    required String inputPath,
    required String outputPath,
    required int startMs,
    required int endMs,
    bool fast = false,
    void Function(double fraction)? onProgress,
    String? taskId,
  }) {
    if (startMs < 0 || endMs <= startMs) {
      throw const AppException('Rentang waktu clip tidak valid.',
          code: 'invalid_range');
    }
    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('cut'),
      label: 'Potong video',
      args: FFmpegCommands.cut(
        input: inputPath,
        output: outputPath,
        startMs: startMs,
        endMs: endMs,
        fast: fast,
      ),
      outputPath: outputPath,
      expectedDurationMs: endMs - startMs,
      onProgress: onProgress,
    ));
  }

  /// [durationMs] (durasi video) dipakai untuk menghitung progres.
  Future<FFmpegResult> extractAudio({
    required String inputPath,
    required String outputPath,
    int? durationMs,
    void Function(double fraction)? onProgress,
    String? taskId,
  }) {
    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('audio'),
      label: 'Ekstrak audio',
      args: FFmpegCommands.extractAudio(input: inputPath, output: outputPath),
      outputPath: outputPath,
      expectedDurationMs: durationMs,
      onProgress: onProgress,
    ));
  }

  Future<FFmpegResult> generateThumbnail({
    required String inputPath,
    required String outputPath,
    int positionMs = 1000,
    int width = 480,
    String? taskId,
  }) {
    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('thumb'),
      label: 'Buat thumbnail',
      args: FFmpegCommands.thumbnail(
        input: inputPath,
        output: outputPath,
        positionMs: positionMs,
        width: width,
      ),
      outputPath: outputPath,
    ));
  }

  Future<FFmpegResult> resizeVideo({
    required String inputPath,
    required String outputPath,
    int? width,
    int? height,
    int? durationMs,
    void Function(double fraction)? onProgress,
    String? taskId,
  }) {
    if (width == null && height == null) {
      throw const AppException('Ukuran output belum ditentukan.',
          code: 'invalid_size');
    }
    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('resize'),
      label: 'Ubah ukuran video',
      args: FFmpegCommands.resize(
        input: inputPath,
        output: outputPath,
        width: width,
        height: height,
      ),
      outputPath: outputPath,
      expectedDurationMs: durationMs,
      onProgress: onProgress,
    ));
  }

  Future<FFmpegResult> cropVideo({
    required String inputPath,
    required String outputPath,
    required int width,
    required int height,
    required int x,
    required int y,
    int? durationMs,
    void Function(double fraction)? onProgress,
    String? taskId,
  }) {
    if (width <= 0 || height <= 0 || x < 0 || y < 0) {
      throw const AppException('Area crop tidak valid.', code: 'invalid_crop');
    }
    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('crop'),
      label: 'Crop video',
      args: FFmpegCommands.crop(
        input: inputPath,
        output: outputPath,
        width: width,
        height: height,
        x: x,
        y: y,
      ),
      outputPath: outputPath,
      expectedDurationMs: durationMs,
      onProgress: onProgress,
    ));
  }

  /// Mengubah video menjadi portrait 9:16 sesuai [plan] (lihat [planPortrait]).
  ///
  /// Bila [startMs] dan [endMs] diisi, hanya rentang itu yang diproses
  /// (cut + crop + scale dalam satu encode). Bila tidak, seluruh video.
  Future<FFmpegResult> cropPortrait({
    required String inputPath,
    required String outputPath,
    required PortraitPlan plan,
    int? startMs,
    int? endMs,
    int? durationMs,
    void Function(double fraction)? onProgress,
    String? taskId,
  }) {
    if ((startMs == null) != (endMs == null) ||
        (startMs != null && (startMs < 0 || endMs! <= startMs))) {
      throw const AppException('Rentang waktu clip tidak valid.',
          code: 'invalid_range');
    }
    final expected =
        startMs != null ? endMs! - startMs : durationMs;

    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('portrait'),
      label: 'Konversi portrait 9:16',
      args: FFmpegCommands.portrait(
        input: inputPath,
        output: outputPath,
        cropX: plan.crop.x,
        cropY: plan.crop.y,
        cropWidth: plan.crop.width,
        cropHeight: plan.crop.height,
        outWidth: plan.outputWidth,
        outHeight: plan.outputHeight,
        startMs: startMs,
        endMs: endMs,
      ),
      outputPath: outputPath,
      expectedDurationMs: expected,
      onProgress: onProgress,
    ));
  }

  /// Merender subtitle ke video. [overlays] berasal dari SubtitleRenderer dan
  /// berwaktu relatif terhadap awal rentang. Bila [plan] diisi, crop+scale
  /// portrait dilakukan dalam encode yang sama; bila [startMs]/[endMs] diisi,
  /// hanya rentang itu yang diproses.
  Future<FFmpegResult> burnSubtitle({
    required String inputPath,
    required String outputPath,
    required List<SubtitleOverlay> overlays,
    PortraitPlan? plan,
    int? startMs,
    int? endMs,
    int? durationMs,
    void Function(double fraction)? onProgress,
    String? taskId,
  }) {
    if (overlays.isEmpty) {
      throw const AppException('Tidak ada subtitle pada rentang ini.',
          code: 'no_subtitles');
    }
    if (overlays.length > maxSubtitleOverlays) {
      throw const AppException(
        'Subtitle terlalu banyak untuk satu clip. Pendekkan durasi clip.',
        code: 'too_many_subtitles',
      );
    }
    if ((startMs == null) != (endMs == null) ||
        (startMs != null && (startMs < 0 || endMs! <= startMs))) {
      throw const AppException('Rentang waktu clip tidak valid.',
          code: 'invalid_range');
    }
    final expected = startMs != null ? endMs! - startMs : durationMs;

    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('subtitle'),
      label: 'Render subtitle',
      args: FFmpegCommands.burnSubtitles(
        input: inputPath,
        output: outputPath,
        overlays: overlays,
        cropX: plan?.crop.x,
        cropY: plan?.crop.y,
        cropWidth: plan?.crop.width,
        cropHeight: plan?.crop.height,
        outWidth: plan?.outputWidth,
        outHeight: plan?.outputHeight,
        startMs: startMs,
        endMs: endMs,
      ),
      outputPath: outputPath,
      expectedDurationMs: expected,
      onProgress: onProgress,
    ));
  }

  Future<FFmpegResult> convertToMp4({
    required String inputPath,
    required String outputPath,
    int? durationMs,
    void Function(double fraction)? onProgress,
    String? taskId,
  }) {
    return _queue.enqueue(FFmpegTask(
      id: taskId ?? _nextId('convert'),
      label: 'Konversi ke MP4',
      args: FFmpegCommands.convertToMp4(input: inputPath, output: outputPath),
      outputPath: outputPath,
      expectedDurationMs: durationMs,
      onProgress: onProgress,
    ));
  }

  /// Memeriksa encoder dan filter yang ada di build FFmpeg terpasang.
  Future<FFmpegDiagnostics> diagnostics() async {
    final encoders = await _queue.enqueue(FFmpegTask(
      id: _nextId('diag-enc'),
      label: 'Diagnostik encoder',
      args: FFmpegCommands.listEncoders(),
    ));
    final filters = await _queue.enqueue(FFmpegTask(
      id: _nextId('diag-flt'),
      label: 'Diagnostik filter',
      args: FFmpegCommands.listFilters(),
    ));

    if (!encoders.ok || !filters.ok) {
      throw const AppException(
        'FFmpeg tidak dapat dijalankan di perangkat ini.',
        code: 'ffmpeg_unavailable',
      );
    }

    final enc = encoders.logs.toLowerCase();
    final flt = filters.logs.toLowerCase();
    return FFmpegDiagnostics(
      hasLibx264: enc.contains('libx264'),
      hasAac: RegExp(r'\baac\b').hasMatch(enc),
      hasSubtitlesFilter: RegExp(r'\bsubtitles\b').hasMatch(flt),
      hasDrawtextFilter: RegExp(r'\bdrawtext\b').hasMatch(flt),
    );
  }

  Future<bool> cancel(String taskId) => _queue.cancel(taskId);

  Future<void> cancelAll() => _queue.cancelAll();
}
