import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_commands.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_failure.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_models.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_queue.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_runner.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runner tiruan: tidak memakai FFmpeg sungguhan.
class FakeRunner implements FFmpegRunner {
  final List<List<String>> calls = [];
  int running = 0;
  int maxRunning = 0;

  FFmpegStatus nextStatus = FFmpegStatus.success;
  String logs = '';
  bool writeOutput = true;

  /// Bila true, run() menggantung sampai cancel() dipanggil.
  bool holdUntilCancel = false;
  Completer<void>? _cancelGate;

  bool _isOutput(String s) => !s.startsWith('-');

  @override
  Future<FFmpegRunOutcome> run(
    List<String> args, {
    void Function(int processedMs)? onProgress,
  }) async {
    calls.add(args);
    running++;
    maxRunning = math.max(maxRunning, running);
    try {
      if (holdUntilCancel) {
        _cancelGate = Completer<void>();
        await _cancelGate!.future;
        if (_isOutput(args.last)) File(args.last).writeAsStringSync('partial');
        return const FFmpegRunOutcome(status: FFmpegStatus.cancelled);
      }

      await Future<void>.delayed(const Duration(milliseconds: 5));
      onProgress?.call(500);

      if (_isOutput(args.last)) {
        if (nextStatus == FFmpegStatus.success && writeOutput) {
          File(args.last).writeAsStringSync('data');
        } else if (nextStatus == FFmpegStatus.failed) {
          File(args.last).writeAsStringSync('partial');
        }
      }
      return FFmpegRunOutcome(status: nextStatus, logs: logs);
    } finally {
      running--;
    }
  }

  @override
  Future<void> cancel() async {
    final gate = _cancelGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

void main() {
  group('FFmpegCommands', () {
    test('cut re-encode: -ss sebelum -i, durasi dengan -t', () {
      final args = FFmpegCommands.cut(
        input: '/in/video.mp4',
        output: '/out/clip.mp4',
        startMs: 10000,
        endMs: 15500,
      );
      final ss = args.indexOf('-ss');
      expect(args[ss + 1], '10.000');
      expect(ss, lessThan(args.indexOf('-i')));
      expect(args[args.indexOf('-t') + 1], '5.500');
      expect(args, containsAll(['libx264', 'aac']));
      expect(args.last, '/out/clip.mp4');
    });

    test('cut fast memakai stream copy', () {
      final args = FFmpegCommands.cut(
        input: 'a',
        output: 'b',
        startMs: 0,
        endMs: 1000,
        fast: true,
      );
      expect(args, containsAllInOrder(['-c', 'copy']));
      expect(args.contains('libx264'), isFalse);
    });

    test('cut dengan rentang tidak valid melempar ArgumentError', () {
      expect(
        () => FFmpegCommands.cut(
            input: 'a', output: 'b', startMs: 5000, endMs: 5000),
        throwsArgumentError,
      );
      expect(
        () => FFmpegCommands.cut(
            input: 'a', output: 'b', startMs: -1, endMs: 5000),
        throwsArgumentError,
      );
    });

    test('path dengan spasi tetap satu argumen utuh', () {
      final args = FFmpegCommands.cut(
        input: '/sdcard/My Videos/a b.mp4',
        output: '/out/c d.mp4',
        startMs: 0,
        endMs: 1000,
      );
      expect(args, contains('/sdcard/My Videos/a b.mp4'));
      expect(args.last, '/out/c d.mp4');
    });

    test('extractAudio: WAV 16 kHz mono tanpa video', () {
      final args = FFmpegCommands.extractAudio(input: 'a', output: 'b.wav');
      expect(args, containsAll(['-vn', '-ac', '1', '-ar', '16000']));
      expect(args, contains('pcm_s16le'));
    });

    test('thumbnail: satu frame', () {
      final args = FFmpegCommands.thumbnail(
          input: 'a', output: 'b.jpg', positionMs: 2500, width: 320);
      expect(args[args.indexOf('-ss') + 1], '2.500');
      expect(args, containsAllInOrder(['-frames:v', '1']));
      expect(args, contains('scale=320:-2'));
    });

    test('resize: sisi kosong dihitung otomatis (-2)', () {
      final args =
          FFmpegCommands.resize(input: 'a', output: 'b', height: 1280);
      expect(args, contains('scale=-2:1280'));
      expect(
        () => FFmpegCommands.resize(input: 'a', output: 'b'),
        throwsArgumentError,
      );
    });

    test('crop', () {
      final args = FFmpegCommands.crop(
          input: 'a', output: 'b', width: 720, height: 1280, x: 100, y: 0);
      expect(args, contains('crop=720:1280:100:0'));
    });
  });

  group('mapFFmpegFailure', () {
    test('memetakan penyebab umum ke pesan ramah', () {
      expect(mapFFmpegFailure('write error: No space left on device'),
          'Storage tidak cukup untuk memproses video.');
      expect(mapFFmpegFailure('Output file #0 does not contain any stream'),
          'Video tidak memiliki audio atau stream yang dibutuhkan.');
      expect(mapFFmpegFailure('moov atom not found'),
          'File video rusak atau tidak lengkap.');
      expect(mapFFmpegFailure('Invalid data found when processing input'),
          'Format atau codec video tidak didukung.');
      expect(mapFFmpegFailure('sesuatu yang aneh'),
          'Proses video gagal. Silakan coba lagi.');
    });
  });

  group('FFmpegQueue', () {
    late Directory tmp;
    late FakeRunner runner;
    late FFmpegQueue queue;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('avc_ffq_');
      runner = FakeRunner();
      queue = FFmpegQueue(runner);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    FFmpegTask task(String id, {void Function(double)? onProgress}) {
      final out = p.join(tmp.path, '$id.mp4');
      return FFmpegTask(
        id: id,
        label: id,
        args: ['-y', '-i', 'in', out],
        outputPath: out,
        expectedDurationMs: 1000,
        onProgress: onProgress,
      );
    }

    test('pekerjaan berjalan satu per satu sesuai urutan', () async {
      final results = await Future.wait([
        queue.enqueue(task('a')),
        queue.enqueue(task('b')),
        queue.enqueue(task('c')),
      ]);

      expect(results.every((r) => r.ok), isTrue);
      expect(runner.maxRunning, 1);
      expect(runner.calls.map((c) => p.basename(c.last)),
          ['a.mp4', 'b.mp4', 'c.mp4']);
      expect(queue.isBusy, isFalse);
    });

    test('progres dilaporkan sebagai pecahan 0..1 dan berakhir di 1.0',
        () async {
      final seen = <double>[];
      await queue.enqueue(task('p', onProgress: seen.add));
      expect(seen.first, 0.5);
      expect(seen.last, 1.0);
    });

    test('gagal: file setengah jadi dihapus, pesan ramah dikembalikan',
        () async {
      runner.nextStatus = FFmpegStatus.failed;
      runner.logs = 'No space left on device';

      final t = task('gagal');
      final r = await queue.enqueue(t);

      expect(r.status, FFmpegStatus.failed);
      expect(r.message, 'Storage tidak cukup untuk memproses video.');
      expect(File(t.outputPath!).existsSync(), isFalse);
    });

    test('sukses tetapi output tidak ada dianggap gagal', () async {
      runner.writeOutput = false;
      final r = await queue.enqueue(task('kosong'));
      expect(r.status, FFmpegStatus.failed);
    });

    test('membatalkan pekerjaan yang masih menunggu', () async {
      runner.holdUntilCancel = true;
      final first = queue.enqueue(task('a'));
      final second = queue.enqueue(task('b'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(await queue.cancel('b'), isTrue);
      expect((await second).cancelled, isTrue);

      await queue.cancel('a');
      expect((await first).cancelled, isTrue);
      // 'b' tidak pernah dijalankan.
      expect(runner.calls.length, 1);
    });

    test('membatalkan pekerjaan berjalan menghapus output sebagian', () async {
      runner.holdUntilCancel = true;
      final t = task('a');
      final future = queue.enqueue(t);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(queue.runningId, 'a');

      await queue.cancel('a');
      final r = await future;

      expect(r.cancelled, isTrue);
      expect(File(t.outputPath!).existsSync(), isFalse);
      expect(queue.isBusy, isFalse);
    });

    test('cancel id tidak dikenal mengembalikan false', () async {
      expect(await queue.cancel('tidak-ada'), isFalse);
    });
  });

  group('FFmpegService', () {
    late FakeRunner runner;
    late FFmpegService service;

    setUp(() {
      runner = FakeRunner();
      service = FFmpegService(FFmpegQueue(runner));
    });

    test('cutVideo menolak rentang tidak valid', () {
      expect(
        () => service.cutVideo(
            inputPath: 'a', outputPath: 'b', startMs: 9000, endMs: 3000),
        throwsA(isA<AppException>()),
      );
    });

    test('diagnostics membaca kemampuan dari log', () async {
      runner.logs = ' V....D libx264  libx264 H.264\n'
          ' A....D aac  AAC\n'
          ' ... subtitles  V->V  Render text subtitles\n'
          ' ... drawtext  V->V  Draw text';
      final d = await service.diagnostics();
      expect(d.hasLibx264, isTrue);
      expect(d.hasAac, isTrue);
      expect(d.hasSubtitlesFilter, isTrue);
      expect(d.hasDrawtextFilter, isTrue);
    });

    test('diagnostics: fitur yang tidak ada terdeteksi false', () async {
      runner.logs = ' A....D aac  AAC';
      final d = await service.diagnostics();
      expect(d.hasAac, isTrue);
      expect(d.hasLibx264, isFalse);
      expect(d.hasSubtitlesFilter, isFalse);
    });
  });
}
