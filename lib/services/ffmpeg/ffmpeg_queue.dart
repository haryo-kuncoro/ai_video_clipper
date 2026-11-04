import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/utils/app_logger.dart';
import 'ffmpeg_failure.dart';
import 'ffmpeg_models.dart';
import 'ffmpeg_runner.dart';

class _Entry {
  _Entry(this.task);

  final FFmpegTask task;
  final Completer<FFmpegResult> completer = Completer<FFmpegResult>();
  bool cancelRequested = false;
}

/// Antrean FIFO: HANYA satu proses FFmpeg berjalan pada satu waktu, agar RAM
/// dan CPU perangkat tidak terbebani oleh beberapa render sekaligus.
class FFmpegQueue extends ChangeNotifier {
  FFmpegQueue(this._runner);

  final FFmpegRunner _runner;
  final List<_Entry> _pending = [];
  _Entry? _running;
  bool _draining = false;

  int get pendingCount => _pending.length;
  String? get runningId => _running?.task.id;
  String? get runningLabel => _running?.task.label;
  bool get isBusy => _running != null || _pending.isNotEmpty;

  /// Menambah pekerjaan; Future selesai saat pekerjaan itu selesai/dibatalkan.
  Future<FFmpegResult> enqueue(FFmpegTask task) {
    final entry = _Entry(task);
    _pending.add(entry);
    notifyListeners();
    unawaited(_drain());
    return entry.completer.future;
  }

  /// Membatalkan pekerjaan menunggu (langsung) atau yang sedang berjalan.
  /// True bila pekerjaan dengan [id] ditemukan.
  Future<bool> cancel(String id) async {
    final idx = _pending.indexWhere((e) => e.task.id == id);
    if (idx >= 0) {
      final entry = _pending.removeAt(idx);
      entry.completer.complete(_cancelledResult());
      notifyListeners();
      return true;
    }
    final running = _running;
    if (running != null && running.task.id == id) {
      running.cancelRequested = true;
      await _runner.cancel();
      return true;
    }
    return false;
  }

  Future<void> cancelAll() async {
    final waiting = List<_Entry>.of(_pending);
    _pending.clear();
    for (final e in waiting) {
      e.completer.complete(_cancelledResult());
    }
    final running = _running;
    if (running != null) {
      running.cancelRequested = true;
      await _runner.cancel();
    }
    notifyListeners();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final entry = _pending.removeAt(0);
        _running = entry;
        notifyListeners();

        final result = await _execute(entry);

        _running = null;
        entry.completer.complete(result);
        notifyListeners();
      }
    } finally {
      _draining = false;
    }
  }

  Future<FFmpegResult> _execute(_Entry entry) async {
    final task = entry.task;
    final output = task.outputPath;

    try {
      if (output != null) {
        await File(output).parent.create(recursive: true);
      }

      final expected = task.expectedDurationMs;
      final progressCb = task.onProgress;
      void Function(int)? onProgress;
      if (progressCb != null && expected != null && expected > 0) {
        onProgress = (ms) => progressCb((ms / expected).clamp(0.0, 1.0).toDouble());
      }

      AppLogger.i('FFmpeg [${task.label}] mulai');
      final outcome = await _runner.run(task.args, onProgress: onProgress);

      if (outcome.status == FFmpegStatus.success && !entry.cancelRequested) {
        if (output == null || await _hasContent(output)) {
          progressCb?.call(1.0);
          return FFmpegResult(
            status: FFmpegStatus.success,
            outputPath: output,
            logs: outcome.logs,
          );
        }
        await _deleteQuietly(output);
        return FFmpegResult(
          status: FFmpegStatus.failed,
          message: 'Proses selesai tetapi file hasil tidak terbentuk.',
          logs: outcome.logs,
        );
      }

      await _deleteQuietly(output);

      if (outcome.status == FFmpegStatus.cancelled || entry.cancelRequested) {
        return _cancelledResult(logs: outcome.logs);
      }
      AppLogger.e('FFmpeg [${task.label}] gagal');
      return FFmpegResult(
        status: FFmpegStatus.failed,
        message: mapFFmpegFailure(outcome.logs),
        logs: outcome.logs,
      );
    } catch (e, st) {
      AppLogger.e('FFmpeg [${task.label}] error', e, st);
      await _deleteQuietly(output);
      if (entry.cancelRequested) return _cancelledResult();
      return FFmpegResult(
        status: FFmpegStatus.failed,
        message: 'Proses video gagal. Silakan coba lagi.',
      );
    }
  }

  FFmpegResult _cancelledResult({String logs = ''}) => FFmpegResult(
        status: FFmpegStatus.cancelled,
        message: 'Proses dibatalkan.',
        logs: logs,
      );

  Future<bool> _hasContent(String path) async {
    final f = File(path);
    return await f.exists() && await f.length() > 0;
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      AppLogger.e('Gagal menghapus file sementara $path', e);
    }
  }
}
