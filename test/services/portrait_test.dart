import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_commands.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_models.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_queue.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_runner.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_service.dart';
import 'package:ai_video_clipper/services/ffmpeg/portrait_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _OkRunner implements FFmpegRunner {
  List<String>? lastArgs;

  @override
  Future<FFmpegRunOutcome> run(
    List<String> args, {
    void Function(int processedMs)? onProgress,
  }) async {
    lastArgs = args;
    File(args.last).writeAsStringSync('data');
    return const FFmpegRunOutcome(status: FFmpegStatus.success);
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  group('planPortrait', () {
    test('landscape 1920x1080 di-crop di tengah, tanpa stretch', () {
      final plan = planPortrait(sourceWidth: 1920, sourceHeight: 1080);
      final c = plan.crop;

      expect(c.height, 1080);
      expect(c.width, 606);
      expect(c.width % 2, 0);
      expect(c.x % 2, 0);
      expect(c.x + c.width, lessThanOrEqualTo(1920));
      // Tengah (toleransi pembulatan genap).
      expect((c.x + c.width / 2 - 960).abs(), lessThanOrEqualTo(2));
      // Rasio crop sangat dekat 9:16.
      expect((c.width / c.height - 9 / 16).abs(), lessThan(0.002));
      // Lebar crop < 1080 -> otomatis 720x1280 (hindari upscale besar).
      expect(plan.outputWidth, 720);
      expect(plan.outputHeight, 1280);
    });

    test('4K landscape cukup tajam: otomatis 1080x1920', () {
      final plan = planPortrait(sourceWidth: 3840, sourceHeight: 2160);
      expect(plan.crop.width, 1214);
      expect(plan.crop.height, 2160);
      expect(plan.outputWidth, 1080);
      expect(plan.outputHeight, 1920);
    });

    test('sumber sudah portrait 9:16 dipakai penuh', () {
      final plan = planPortrait(sourceWidth: 1080, sourceHeight: 1920);
      expect(plan.crop, const CropRect(x: 0, y: 0, width: 1080, height: 1920));
      expect(plan.outputWidth, 1080);
    });

    test('sumber lebih sempit dari 9:16: yang dipotong tingginya', () {
      final plan = planPortrait(sourceWidth: 720, sourceHeight: 1600);
      expect(plan.crop.width, 720);
      expect(plan.crop.height, 1280);
      expect(plan.crop.y, 160);
    });

    test('pilihan resolusi manual menimpa otomatis', () {
      final a = planPortrait(
          sourceWidth: 1920,
          sourceHeight: 1080,
          resolution: PortraitResolution.p1080);
      expect(a.outputWidth, 1080);
      expect(a.upscaleFactor, greaterThan(1.5));

      final b = planPortrait(
          sourceWidth: 3840,
          sourceHeight: 2160,
          resolution: PortraitResolution.p720);
      expect(b.outputWidth, 720);
    });

    test('manual: posisi di tepi tetap di dalam frame', () {
      final left = planPortrait(
        sourceWidth: 1920,
        sourceHeight: 1080,
        mode: PortraitCropMode.manualCrop,
        focusX: 0,
      );
      expect(left.crop.x, 0);

      final right = planPortrait(
        sourceWidth: 1920,
        sourceHeight: 1080,
        mode: PortraitCropMode.manualCrop,
        focusX: 1,
      );
      expect(right.crop.x + right.crop.width, 1920);
      expect(right.crop.x % 2, 0);
    });

    test('manual: zoom memperkecil area crop dan dibatasi 4x', () {
      final z2 = planPortrait(
        sourceWidth: 1920,
        sourceHeight: 1080,
        mode: PortraitCropMode.manualCrop,
        zoom: 2,
      );
      expect(z2.crop.height, 540);
      expect(z2.crop.width, 302);

      final zBig = planPortrait(
        sourceWidth: 1920,
        sourceHeight: 1080,
        mode: PortraitCropMode.manualCrop,
        zoom: 10,
      );
      expect(zBig.crop.height, 270);
    });

    test('center crop mengabaikan fokus dan zoom', () {
      final plan = planPortrait(
        sourceWidth: 1920,
        sourceHeight: 1080,
        focusX: 0,
        zoom: 3,
      );
      expect(plan.crop, planPortrait(sourceWidth: 1920, sourceHeight: 1080).crop);
    });

    test('face-aware tanpa titik fokus jatuh ke center crop', () {
      final center = planPortrait(sourceWidth: 1920, sourceHeight: 1080);
      final face = planPortrait(
        sourceWidth: 1920,
        sourceHeight: 1080,
        mode: PortraitCropMode.faceAwareCrop,
      );
      expect(face.usedFallback, isTrue);
      expect(face.crop, center.crop);
    });

    test('face-aware dengan titik fokus menggeser area crop', () {
      final face = planPortrait(
        sourceWidth: 1920,
        sourceHeight: 1080,
        mode: PortraitCropMode.faceAwareCrop,
        focusX: 0.25,
      );
      expect(face.usedFallback, isFalse);
      expect((face.crop.x + face.crop.width / 2 - 480).abs(), lessThanOrEqualTo(2));
    });

    test('sumber terlalu kecil ditolak', () {
      expect(
        () => planPortrait(sourceWidth: 8, sourceHeight: 8),
        throwsArgumentError,
      );
    });
  });

  group('FFmpegCommands.portrait', () {
    test('filter crop lalu scale lalu setsar', () {
      final plan = planPortrait(sourceWidth: 1920, sourceHeight: 1080);
      final args = FFmpegCommands.portrait(
        input: 'in.mp4',
        output: 'out.mp4',
        cropX: plan.crop.x,
        cropY: plan.crop.y,
        cropWidth: plan.crop.width,
        cropHeight: plan.crop.height,
        outWidth: plan.outputWidth,
        outHeight: plan.outputHeight,
      );
      final vf = args[args.indexOf('-vf') + 1];
      expect(vf, startsWith('crop=606:1080:'));
      expect(vf, contains('scale=720:1280:flags=lanczos'));
      expect(vf, endsWith('setsar=1'));
      expect(args.contains('-ss'), isFalse);
      expect(args.last, 'out.mp4');
    });

    test('dengan rentang: -ss sebelum -i dan -t sesudahnya', () {
      final args = FFmpegCommands.portrait(
        input: 'in.mp4',
        output: 'out.mp4',
        cropX: 0,
        cropY: 0,
        cropWidth: 606,
        cropHeight: 1080,
        outWidth: 720,
        outHeight: 1280,
        startMs: 12000,
        endMs: 27000,
      );
      final i = args.indexOf('-i');
      expect(args.indexOf('-ss'), lessThan(i));
      expect(args[args.indexOf('-ss') + 1], '12.000');
      expect(args[args.indexOf('-t') + 1], '15.000');
    });

    test('argumen tidak valid ditolak', () {
      expect(
        () => FFmpegCommands.portrait(
          input: 'a',
          output: 'b',
          cropX: 0,
          cropY: 0,
          cropWidth: 0,
          cropHeight: 10,
          outWidth: 720,
          outHeight: 1280,
        ),
        throwsArgumentError,
      );
      expect(
        () => FFmpegCommands.portrait(
          input: 'a',
          output: 'b',
          cropX: 0,
          cropY: 0,
          cropWidth: 606,
          cropHeight: 1080,
          outWidth: 720,
          outHeight: 1280,
          startMs: 1000,
        ),
        throwsArgumentError,
      );
    });
  });

  group('FFmpegService.cropPortrait', () {
    late Directory tmp;
    late _OkRunner runner;
    late FFmpegService service;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('avc_portrait_');
      runner = _OkRunner();
      service = FFmpegService(FFmpegQueue(runner));
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('menghasilkan file dan memakai ukuran dari plan', () async {
      final plan = planPortrait(sourceWidth: 1920, sourceHeight: 1080);
      final out = p.join(tmp.path, 'sub', 'portrait.mp4');

      final r = await service.cropPortrait(
        inputPath: 'in.mp4',
        outputPath: out,
        plan: plan,
        startMs: 0,
        endMs: 15000,
      );

      expect(r.ok, isTrue);
      expect(File(out).existsSync(), isTrue);
      final vf = runner.lastArgs![runner.lastArgs!.indexOf('-vf') + 1];
      expect(vf, contains('scale=720:1280'));
    });

    test('rentang waktu tidak valid melempar AppException', () {
      final plan = planPortrait(sourceWidth: 1920, sourceHeight: 1080);
      expect(
        () => service.cropPortrait(
          inputPath: 'a',
          outputPath: 'b',
          plan: plan,
          startMs: 9000,
          endMs: 3000,
        ),
        throwsA(isA<AppException>()),
      );
      expect(
        () => service.cropPortrait(
          inputPath: 'a',
          outputPath: 'b',
          plan: plan,
          startMs: 1000,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
