import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_commands.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_models.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_queue.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_runner.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_service.dart';
import 'package:ai_video_clipper/services/ffmpeg/portrait_plan.dart';
import 'package:ai_video_clipper/services/ffmpeg/subtitle_overlay.dart';
import 'package:ai_video_clipper/services/subtitle/subtitle_cue.dart';
import 'package:ai_video_clipper/services/subtitle/subtitle_renderer.dart';
import 'package:ai_video_clipper/services/subtitle/subtitle_style.dart';
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

TranscriptSegment seg(int s, int e, String t) =>
    TranscriptSegment(startMs: s, endMs: e, text: t);

void main() {
  group('wrapText', () {
    test('membungkus di batas kata', () {
      expect(
        wrapText('Hari ini saya akan membahas kesalahan terbesar', 20),
        ['Hari ini saya akan', 'membahas kesalahan', 'terbesar'],
      );
    });

    test('kata yang lebih panjang dari batas dipotong paksa', () {
      expect(wrapText('abcdefghij', 4), ['abcd', 'efgh', 'ij']);
    });

    test('spasi berlebih dan teks kosong', () {
      expect(wrapText('  a   b  ', 10), ['a b']);
      expect(wrapText('   ', 10), isEmpty);
      expect(() => wrapText('a', 0), throwsArgumentError);
    });
  });

  group('buildCues', () {
    test('waktu digeser relatif terhadap awal clip', () {
      final cues = buildCues(
        segments: [seg(12000, 15000, 'Halo dunia')],
        clipStartMs: 10000,
        clipEndMs: 20000,
      );
      expect(cues.length, 1);
      expect(cues.first.startMs, 2000);
      expect(cues.first.endMs, 5000);
      expect(cues.first.lines, ['Halo dunia']);
    });

    test('segmen di luar clip diabaikan, yang beririsan dipotong', () {
      final cues = buildCues(
        segments: [
          seg(0, 4000, 'sebelum'),
          seg(9000, 12000, 'beririsan awal'),
          seg(14000, 25000, 'beririsan akhir'),
          seg(30000, 31000, 'sesudah'),
        ],
        clipStartMs: 10000,
        clipEndMs: 20000,
      );
      expect(cues.map((c) => c.text), ['beririsan awal', 'beririsan akhir']);
      expect(cues[0].startMs, 0);
      expect(cues[0].endMs, 2000);
      expect(cues[1].startMs, 4000);
      expect(cues[1].endMs, 10000);
    });

    test('teks panjang dipecah per 2 baris dengan waktu sebanding', () {
      final cues = buildCues(
        segments: [
          seg(0, 8000,
              'satu dua tiga empat lima enam tujuh delapan sembilan sepuluh'),
        ],
        clipStartMs: 0,
        clipEndMs: 10000,
        maxCharsPerLine: 10,
        maxLines: 2,
      );
      expect(cues.length, greaterThan(1));
      expect(cues.every((c) => c.lines.length <= 2), isTrue);
      expect(cues.first.startMs, 0);
      expect(cues.last.endMs, 8000);
      for (var i = 0; i < cues.length - 1; i++) {
        expect(cues[i].endMs, cues[i + 1].startMs);
      }
    });

    test('cue yang tumpang tindih dirapikan', () {
      final cues = buildCues(
        segments: [seg(0, 5000, 'pertama'), seg(3000, 8000, 'kedua')],
        clipStartMs: 0,
        clipEndMs: 10000,
      );
      expect(cues[0].endMs, 3000);
      expect(cues[1].startMs, 3000);
    });

    test('urutan input tidak berpengaruh dan teks kosong dibuang', () {
      final cues = buildCues(
        segments: [seg(5000, 6000, 'b'), seg(0, 1000, 'a'), seg(2000, 3000, '  ')],
        clipStartMs: 0,
        clipEndMs: 10000,
      );
      expect(cues.map((c) => c.text), ['a', 'b']);
    });

    test('rentang clip tidak valid menghasilkan daftar kosong', () {
      expect(
        buildCues(segments: [seg(0, 1000, 'a')], clipStartMs: 5, clipEndMs: 5),
        isEmpty,
      );
    });
  });

  group('SubtitleStyle', () {
    test('preset sesuai spesifikasi', () {
      final social = SubtitlePresets.style(SubtitlePreset.social);
      expect(social.uppercase, isTrue);
      expect(social.bold, isTrue);
      expect(social.position, SubtitlePosition.lower);
      expect(social.textColor, 0xFFFFE600);

      final minimal = SubtitlePresets.style(SubtitlePreset.minimal);
      expect(minimal.outlineWidth, 0);
      expect(minimal.shadow, isTrue);
    });

    test('toMap -> fromMap bolak-balik tanpa kehilangan nilai', () {
      final original = SubtitlePresets.style(SubtitlePreset.social)
          .copyWith(background: true, maxCharsPerLine: 22);
      final restored = SubtitleStyle.fromMap(original.toMap());
      expect(restored.preset, SubtitlePreset.social);
      expect(restored.background, isTrue);
      expect(restored.maxCharsPerLine, 22);
      expect(restored.textColor, 0xFFFFE600);
      expect(restored.position, SubtitlePosition.lower);
    });

    test('nilai di luar rentang dibatasi', () {
      final s = const SubtitleStyle(
        fontSize: 500,
        outlineWidth: 99,
        maxCharsPerLine: 1,
        fontFamily: 'tidak-ada',
      ).normalized();
      expect(s.fontSize, 140);
      expect(s.outlineWidth, 12);
      expect(s.maxCharsPerLine, 8);
      expect(s.fontFamily, 'sans-serif');
    });

    test('subtitleY: tiap posisi pada frame 1920', () {
      int y(SubtitlePosition p) =>
          subtitleY(position: p, outHeight: 1920, bandHeight: 200);
      expect(y(SubtitlePosition.top), 192);
      expect(y(SubtitlePosition.center), 860);
      expect(y(SubtitlePosition.lower), 1221);
      expect(y(SubtitlePosition.bottom), 1451);
    });

    test('subtitleY tidak keluar frame', () {
      expect(
        subtitleY(
            position: SubtitlePosition.bottom, outHeight: 300, bandHeight: 400),
        0,
      );
    });
  });

  group('FFmpegCommands.burnSubtitles', () {
    const overlays = [
      SubtitleOverlay(imagePath: '/t/c0.png', startMs: 500, endMs: 2500, y: 1451),
      SubtitleOverlay(imagePath: '/t/c1.png', startMs: 3000, endMs: 5000, y: 1451),
    ];

    test('graf filter: crop+scale lalu overlay berantai dengan enable', () {
      final args = FFmpegCommands.burnSubtitles(
        input: 'in.mp4',
        output: 'out.mp4',
        overlays: overlays,
        cropX: 656,
        cropY: 0,
        cropWidth: 606,
        cropHeight: 1080,
        outWidth: 720,
        outHeight: 1280,
        startMs: 0,
        endMs: 15000,
      );
      final graph = args[args.indexOf('-filter_complex') + 1];
      expect(graph, startsWith('[0:v]crop=606:1080:656:0,scale=720:1280'));
      expect(graph, contains('[b0][1:v]overlay=x=0:y=1451'));
      expect(graph, contains("enable='between(t,0.500,2.500)'"));
      expect(graph, contains('[b1][2:v]overlay=x=0:y=1451'));
      expect(graph, endsWith('[b2]'));

      expect(args[args.indexOf('-map') + 1], '[b2]');
      expect(args, contains('0:a?'));
      // 3 input: video + 2 PNG, dan -ss sebelum input pertama.
      expect(args.where((a) => a == '-i').length, 3);
      expect(args.indexOf('-ss'), lessThan(args.indexOf('-i')));
      expect(args[args.indexOf('-t') + 1], '15.000');
      expect(args.last, 'out.mp4');
    });

    test('tanpa crop memakai filter null', () {
      final args = FFmpegCommands.burnSubtitles(
        input: 'in.mp4',
        output: 'out.mp4',
        overlays: overlays,
      );
      final graph = args[args.indexOf('-filter_complex') + 1];
      expect(graph, startsWith('[0:v]null[b0]'));
      expect(args.contains('-ss'), isFalse);
    });

    test('argumen tidak valid ditolak', () {
      expect(
        () => FFmpegCommands.burnSubtitles(
            input: 'a', output: 'b', overlays: const []),
        throwsArgumentError,
      );
      expect(
        () => FFmpegCommands.burnSubtitles(
            input: 'a', output: 'b', overlays: overlays, cropX: 0),
        throwsArgumentError,
      );
      expect(
        () => FFmpegCommands.burnSubtitles(
            input: 'a', output: 'b', overlays: overlays, startMs: 5),
        throwsArgumentError,
      );
    });
  });

  group('FFmpegService.burnSubtitle', () {
    late Directory tmp;
    late _OkRunner runner;
    late FFmpegService service;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('avc_sub_svc_');
      runner = _OkRunner();
      service = FFmpegService(FFmpegQueue(runner));
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    const one = [
      SubtitleOverlay(imagePath: 'a.png', startMs: 0, endMs: 1000, y: 10),
    ];

    test('menghasilkan file dan memakai plan portrait', () async {
      final plan = planPortrait(sourceWidth: 1920, sourceHeight: 1080);
      final out = p.join(tmp.path, 'o.mp4');
      final r = await service.burnSubtitle(
        inputPath: 'in.mp4',
        outputPath: out,
        overlays: one,
        plan: plan,
        startMs: 0,
        endMs: 10000,
      );
      expect(r.ok, isTrue);
      final graph =
          runner.lastArgs![runner.lastArgs!.indexOf('-filter_complex') + 1];
      expect(graph, contains('scale=720:1280'));
    });

    test('tanpa subtitle atau terlalu banyak ditolak', () {
      expect(
        () => service.burnSubtitle(
            inputPath: 'a', outputPath: 'b', overlays: const []),
        throwsA(isA<AppException>()),
      );
      final many = List.generate(
        maxSubtitleOverlays + 1,
        (i) => SubtitleOverlay(
            imagePath: '$i.png', startMs: 0, endMs: 100, y: 0),
      );
      expect(
        () => service.burnSubtitle(
            inputPath: 'a', outputPath: 'b', overlays: many),
        throwsA(isA<AppException>()),
      );
    });

    test('rentang tidak valid ditolak', () {
      expect(
        () => service.burnSubtitle(
          inputPath: 'a',
          outputPath: 'b',
          overlays: one,
          startMs: 9000,
          endMs: 3000,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  testWidgets('renderer menghasilkan PNG per cue dengan posisi di dalam frame',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('avc_sub_png_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final overlays = await tester.runAsync(
      () => SubtitleRenderer().render(
        cues: const [
          SubtitleCue(startMs: 0, endMs: 2000, lines: ['Halo dunia', 'baris dua']),
          SubtitleCue(startMs: 2000, endMs: 4000, lines: ['Kedua']),
        ],
        style: SubtitlePresets.style(SubtitlePreset.social)
            .copyWith(background: true),
        outWidth: 720,
        outHeight: 1280,
        outDir: Directory(p.join(dir.path, 'subs')),
      ),
    );

    expect(overlays, isNotNull);
    expect(overlays!.length, 2);
    for (final o in overlays) {
      final bytes = File(o.imagePath).readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // tanda PNG
      expect(o.y, inInclusiveRange(0, 1280));
    }
    expect(overlays[0].startMs, 0);
    expect(overlays[1].endMs, 4000);
  });
}
