import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import 'ffmpeg_models.dart';
import 'ffmpeg_runner.dart';

/// Satu-satunya file yang memakai paket `ffmpeg_kit_flutter_new`.
///
/// Jika paket mengubah API-nya (atau Anda berpindah ke fork lain), cukup
/// sesuaikan file ini; queue dan service tidak ikut berubah.
class FFmpegKitRunner implements FFmpegRunner {
  @override
  Future<FFmpegRunOutcome> run(
    List<String> args, {
    void Function(int processedMs)? onProgress,
  }) async {
    final done = Completer<FFmpegSession>();

    try {
      await FFmpegKit.executeWithArgumentsAsync(
        args,
        (FFmpegSession session) {
          if (!done.isCompleted) done.complete(session);
        },
        null,
        (Statistics stats) {
          final ms = stats.getTime().toInt();
          if (ms > 0) onProgress?.call(ms);
        },
      );
    } on MissingPluginException {
      throw const AppException(
        'Komponen FFmpeg belum terpasang. Jalankan ulang aplikasi setelah '
        'flutter pub get.',
        code: 'ffmpeg_missing',
      );
    }

    final session = await done.future;
    final code = await session.getReturnCode();
    final logs = await session.getAllLogsAsString() ?? '';

    if (ReturnCode.isSuccess(code)) {
      return FFmpegRunOutcome(status: FFmpegStatus.success, logs: logs);
    }
    if (ReturnCode.isCancel(code)) {
      return FFmpegRunOutcome(status: FFmpegStatus.cancelled, logs: logs);
    }
    return FFmpegRunOutcome(status: FFmpegStatus.failed, logs: logs);
  }

  @override
  Future<void> cancel() => FFmpegKit.cancel();
}
