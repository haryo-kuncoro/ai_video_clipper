import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/clip.dart';
import 'package:ai_video_clipper/database/models/clip_candidate.dart';
import 'package:ai_video_clipper/database/models/clip_edit.dart';
import 'package:ai_video_clipper/database/repositories/clip_edit_repository.dart';
import 'package:ai_video_clipper/services/subtitle/subtitle_style.dart';
import 'package:ai_video_clipper/database/models/processing_job.dart';
import 'package:ai_video_clipper/database/models/project.dart';
import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/clip_candidate_repository.dart';
import 'package:ai_video_clipper/database/repositories/clip_repository.dart';
import 'package:ai_video_clipper/database/repositories/processing_job_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/subtitle_settings_repository.dart';
import 'package:ai_video_clipper/database/repositories/transcript_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:ai_video_clipper/features/video/media_probe.dart';
import 'package:ai_video_clipper/services/face/face_detector.dart';
import 'package:ai_video_clipper/services/face/face_models.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_models.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_queue.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_runner.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_service.dart';
import 'package:ai_video_clipper/services/ffmpeg/subtitle_overlay.dart';
import 'package:ai_video_clipper/services/render/clip_render_service.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';
import 'package:ai_video_clipper/services/transcription/transcription_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Runner implements FFmpegRunner {
  final List<List<String>> calls = [];
  FFmpegStatus status = FFmpegStatus.success;

  /// Dipanggil pada tiap run (mis. untuk membatalkan di tengah batch).
  void Function(int callNumber)? onRun;

  @override
  Future<FFmpegRunOutcome> run(List<String> args,
      {void Function(int processedMs)? onProgress}) async {
    calls.add(args);
    onRun?.call(calls.length);
    onProgress?.call(500);
    if (status == FFmpegStatus.success) {
      File(args.last).writeAsStringSync('mp4');
    } else if (status == FFmpegStatus.failed) {
      File(args.last).writeAsStringSync('partial');
    }
    return FFmpegRunOutcome(status: status);
  }

  @override
  Future<void> cancel() async {}
}

class _Probe implements MediaProbe {
  int free = 1 << 40;
  bool thumbOk = true;

  @override
  Future<VideoMetadata> probe(String path) =>
      throw UnimplementedError('tidak dipakai');

  @override
  Future<bool> generateThumbnail({
    required String videoPath,
    required String outputPath,
    required int positionMs,
    int maxWidth = 480,
  }) async {
    if (thumbOk) File(outputPath).writeAsStringSync('jpg');
    return thumbOk;
  }

  @override
  Future<int> freeSpaceBytes(String path) async => free;
}

class _Faces implements VideoFaceDetector {
  List<FaceSample> Function(List<int> times) respond = (_) => const [];
  Object? error;
  int calls = 0;
  List<int> lastTimes = const [];

  @override
  Future<List<FaceSample>> detect({
    required String videoPath,
    required List<int> timesMs,
  }) async {
    calls++;
    lastTimes = timesMs;
    final e = error;
    if (e != null) throw e;
    return respond(timesMs);
  }
}

void main() {
  late Directory tmp;
  late _Faces faces;
  late AppPaths paths;
  late AppDatabase db;
  late _Runner runner;
  late _Probe probe;
  late ClipRenderService service;
  late VideoRecord video;
  late int projectId;
  late ClipCandidateRepository candRepo;
  late ClipRepository clipRepo;
  var overlayCount = 0;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('avc_render_');
    final root = await Directory(p.join(tmp.path, 'app')).create();
    paths = await AppPaths.fromBase(root);
    db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
        factory: databaseFactoryFfi);

    projectId = (await ProjectRepository(db.db).create('P')).id!;
    final src = File(p.join(tmp.path, 'v.mp4'))..writeAsStringSync('video');
    video = await VideoRepository(db.db).insert(VideoRecord(
      projectId: projectId,
      filePath: src.path,
      fileName: 'v.mp4',
      width: 1920,
      height: 1080,
      durationMs: 300000,
      createdAt: DateTime.now(),
    ));

    candRepo = ClipCandidateRepository(db.db);
    clipRepo = ClipRepository(db.db);
    runner = _Runner();
    probe = _Probe();
    faces = _Faces();
    overlayCount = 0;

    service = ClipRenderService(
      ffmpeg: FFmpegService(FFmpegQueue(runner)),
      probe: probe,
      faceDetector: faces,
      paths: paths,
      clips: clipRepo,
      candidates: candRepo,
      edits: ClipEditRepository(db.db),
      transcripts: TranscriptRepository(db.db),
      subtitleSettings: SubtitleSettingsRepository(db.db),
      projects: ProjectRepository(db.db),
      jobs: ProcessingJobRepository(db.db),
      overlayBuilder: ({
        required cues,
        required style,
        required outWidth,
        required outHeight,
        required outDir,
      }) async {
        await outDir.create(recursive: true);
        final list = <SubtitleOverlay>[];
        for (var i = 0; i < cues.length; i++) {
          final f = File(p.join(outDir.path, 'cue_$i.png'))..writeAsStringSync('png');
          list.add(SubtitleOverlay(
            imagePath: f.path,
            startMs: cues[i].startMs,
            endMs: cues[i].endMs,
            y: 100,
          ));
        }
        overlayCount = list.length;
        return list;
      },
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<List<ClipCandidate>> addCandidates(
      List<(int, CandidateStatus)> specs) async {
    final now = DateTime.now();
    await candRepo.insertAll([
      for (var i = 0; i < specs.length; i++)
        ClipCandidate(
          projectId: projectId,
          startMs: specs[i].$1,
          endMs: specs[i].$1 + 30000,
          title: 'Clip $i',
          score: 0.8,
          status: specs[i].$2,
          createdAt: now,
        ),
    ]);
    return candRepo.getByProject(projectId);
  }

  Future<void> addTranscript(List<TranscriptSegment> segs) async {
    await TranscriptRepository(db.db).replaceForProject(
      Transcript(
          projectId: projectId, videoId: video.id!, createdAt: DateTime.now()),
      segs,
    );
  }

  Future<ProjectStatus> status() async =>
      (await ProjectRepository(db.db).getById(projectId))!.status;

  test('tanpa kandidat diterima -> pesan ramah', () async {
    await addCandidates([(0, CandidateStatus.pending)]);
    await expectLater(
      service.renderAccepted(video: video),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'no_accepted')),
    );
  });

  test('hanya kandidat diterima yang dirender, berurutan waktu', () async {
    await addCandidates([
      (120000, CandidateStatus.accepted),
      (0, CandidateStatus.accepted),
      (60000, CandidateStatus.rejected),
      (200000, CandidateStatus.pending),
    ]);
    final events = <int>[];
    final s = await service.renderAccepted(
      video: video,
      onProgress: (p) => events.add(p.index),
    );

    expect(s.succeeded, 2);
    expect(s.failures, isEmpty);
    expect(runner.calls.length, 2);
    expect(events.toSet(), {1, 2});

    final done = await clipRepo.getByProject(projectId);
    expect(done.length, 2);
    for (final c in done) {
      expect(c.status, ClipStatus.completed);
      expect(File(c.filePath!).existsSync(), isTrue);
      expect(File(c.thumbnailPath!).existsSync(), isTrue);
      // Sumber 1920x1080: lebar crop 606 < 1080, jadi output 720x1280.
      expect(c.width, 720);
      expect(c.height, 1280);
      expect(c.durationMs, 30000);
    }
    expect(done.map((c) => c.startMs), [0, 120000]);

    final cands = await candRepo.getByProject(projectId);
    expect(cands.where((c) => c.status == CandidateStatus.generated).length, 2);
    expect(cands.where((c) => c.status == CandidateStatus.rejected).length, 1);
    expect(await status(), ProjectStatus.completed);

    final jobs = await ProcessingJobRepository(db.db).getByProject(projectId);
    expect(jobs.every((j) => j.type == JobType.renderClip), isTrue);
    expect(jobs.every((j) => j.status == JobStatus.completed), isTrue);
  });

  test('transcript tersedia -> subtitle dirender (overlay PNG), folder dibersihkan',
      () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    await addTranscript([
      TranscriptSegment(
          startMs: 1000,
          endMs: 6000,
          text: 'Kenapa banyak orang gagal memulai bisnis mereka sendiri?'),
    ]);
    final s = await service.renderAccepted(video: video);

    expect(s.succeeded, 1);
    expect(overlayCount, greaterThan(0));
    expect(runner.calls.single.where((a) => a.endsWith('.png')), isNotEmpty);
    final tempDir = paths.projectTempDir(projectId);
    expect(tempDir.listSync().where((e) => p.basename(e.path).startsWith('subs_')),
        isEmpty);
  });

  test('tanpa transcript atau subtitle dimatikan -> portrait tanpa overlay',
      () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    await service.renderAccepted(video: video);
    expect(runner.calls.single.where((a) => a.endsWith('.png')), isEmpty);

    await db.db.update('clip_candidates', {'status': 'accepted'});
    await addTranscript([
      TranscriptSegment(
          startMs: 1000, endMs: 6000, text: 'Ada transcript tetapi subtitle mati'),
    ]);
    runner.calls.clear();
    await service.renderAccepted(video: video, burnSubtitles: false);
    expect(runner.calls.single.where((a) => a.endsWith('.png')), isEmpty);
  });

  test('render gagal -> tidak ada clip, kandidat tetap accepted, pesan ramah',
      () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    await ProjectRepository(db.db).updateStatus(projectId, ProjectStatus.analyzed);
    runner.status = FFmpegStatus.failed;
    final s = await service.renderAccepted(video: video);

    expect(s.succeeded, 0);
    expect(s.failures.single.title, 'Clip 0');
    expect(s.failures.single.message, isNotEmpty);
    expect(await clipRepo.getByProject(projectId), isEmpty);
    expect(paths.projectClipsDir(projectId).listSync(), isEmpty);
    expect((await candRepo.getByProject(projectId)).single.status,
        CandidateStatus.accepted);
    expect(await status(), ProjectStatus.analyzed);
    final job = (await ProcessingJobRepository(db.db).getByProject(projectId)).single;
    expect(job.status, JobStatus.failed);
    expect(service.isRunning, isFalse);
  });

  test('satu gagal tidak menghentikan batch', () async {
    await addCandidates([
      (0, CandidateStatus.accepted),
      (60000, CandidateStatus.accepted),
    ]);
    runner.onRun = (n) {
      runner.status = n == 1 ? FFmpegStatus.failed : FFmpegStatus.success;
    };
    final s = await service.renderAccepted(video: video);
    expect(s.succeeded, 1);
    expect(s.failures.length, 1);
  });

  test('dibatalkan sebelum mulai -> tidak merender apa pun', () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    final token = CancelToken()..cancel();
    final s = await service.renderAccepted(video: video, cancel: token);
    expect(s.cancelled, isTrue);
    expect(runner.calls, isEmpty);
    expect(await clipRepo.getByProject(projectId), isEmpty);
  });

  test('dibatalkan saat clip ke-2 -> clip ke-1 tetap ada, clip ke-2 dibersihkan',
      () async {
    await addCandidates([
      (0, CandidateStatus.accepted),
      (60000, CandidateStatus.accepted),
      (120000, CandidateStatus.accepted),
    ]);
    final token = CancelToken();
    runner.onRun = (n) {
      if (n == 2) token.cancel();
    };
    final s = await service.renderAccepted(video: video, cancel: token);
    expect(s.cancelled, isTrue);
    expect(s.succeeded, 1);
    expect(runner.calls.length, 2); // clip ke-3 tidak pernah dimulai
    expect((await clipRepo.getByProject(projectId)).length, 1);
    expect(paths.projectClipsDir(projectId).listSync().length, 1);
    final cands = await candRepo.getByProject(projectId);
    expect(cands.where((c) => c.status == CandidateStatus.accepted).length, 2);
  });

  test('ruang penyimpanan kurang -> InsufficientStorageException', () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    probe.free = 1024;
    await expectLater(
      service.renderAccepted(video: video),
      throwsA(isA<InsufficientStorageException>()),
    );
    expect(runner.calls, isEmpty);
  });

  test('file video hilang -> pesan ramah', () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    File(video.filePath).deleteSync();
    await expectLater(
      service.renderAccepted(video: video),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'video_missing')),
    );
  });

  test('thumbnail gagal tidak menggagalkan clip', () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    probe.thumbOk = false;
    final s = await service.renderAccepted(video: video);
    expect(s.succeeded, 1);
    expect((await clipRepo.getByProject(projectId)).single.thumbnailPath, isNull);
  });

  test('deleteClip menghapus file dan mengembalikan kandidat ke accepted',
      () async {
    await addCandidates([(0, CandidateStatus.accepted)]);
    await service.renderAccepted(video: video);
    final clip = (await clipRepo.getByProject(projectId)).single;
    final file = File(clip.filePath!);
    expect(file.existsSync(), isTrue);

    await service.deleteClip(clip);
    expect(file.existsSync(), isFalse);
    expect(await clipRepo.getByProject(projectId), isEmpty);
    expect((await candRepo.getByProject(projectId)).single.status,
        CandidateStatus.accepted);
  });

  test('deleteClip tidak menghapus file di luar folder aplikasi', () async {
    final outside = File(p.join(tmp.path, 'milik_pengguna.mp4'))
      ..writeAsStringSync('x');
    final id = await clipRepo.insert(Clip(
      projectId: projectId,
      startMs: 0,
      endMs: 5000,
      title: 'X',
      filePath: outside.path,
      createdAt: DateTime.now(),
    ));
    await service.deleteClip((await clipRepo.getById(id))!);
    expect(outside.existsSync(), isTrue);
  });

  group('crop mengikuti wajah', () {
    int cropX() {
      final joined = runner.calls.last.join(' ');
      final m = RegExp(r'crop=(\d+):(\d+):(\d+):(\d+)').firstMatch(joined)!;
      return int.parse(m.group(3)!);
    }

    List<FaceSample> faceAt(List<int> times, double x) => [
          for (final t in times)
            FaceSample(timeMs: t, faces: [FaceBox(x: x, y: 0.4, size: 0.12)]),
        ];

    test('wajah di kanan -> crop bergeser ke kanan dari tengah', () async {
      await addCandidates([(0, CandidateStatus.accepted)]);
      await service.renderAccepted(video: video, faceAware: false);
      final center = cropX(); // 1920x1080 -> (1920-606)/2 = 657 -> 656
      expect(center, 656);

      await db.db.update('clip_candidates', {'status': 'accepted'});
      faces.respond = (t) => faceAt(t, 0.8);
      final s = await service.renderAccepted(video: video);
      expect(cropX(), greaterThan(center + 300));
      expect(cropX() % 2, 0);
      expect(s.notes.single, contains('mengikuti wajah'));
      expect(faces.lastTimes.length, inInclusiveRange(3, 15));
      expect(faces.lastTimes.first, greaterThanOrEqualTo(0));
      expect(faces.lastTimes.last, lessThanOrEqualTo(30000));
    });

    test('tanpa wajah -> crop tengah dan catatan', () async {
      await addCandidates([(0, CandidateStatus.accepted)]);
      final s = await service.renderAccepted(video: video);
      expect(cropX(), 656);
      expect(s.succeeded, 1);
      expect(s.notes.single, contains('tidak terdeteksi'));
    });

    test('detektor error -> render tetap sukses dengan crop tengah', () async {
      await addCandidates([(0, CandidateStatus.accepted)]);
      faces.error = const AppException('native_missing', code: 'native_missing');
      final s = await service.renderAccepted(video: video);
      expect(s.succeeded, 1);
      expect(s.failures, isEmpty);
      expect(cropX(), 656);
      expect(s.notes.single, contains('gagal'));
    });

    test('faceAware=false -> detektor tidak dipanggil', () async {
      await addCandidates([(0, CandidateStatus.accepted)]);
      final s = await service.renderAccepted(video: video, faceAware: false);
      expect(faces.calls, 0);
      expect(s.notes, isEmpty);
    });
  });

  group('editor: rerenderClip', () {
    Future<Clip> renderOne() async {
      await addCandidates([(0, CandidateStatus.accepted)]);
      await service.renderAccepted(video: video, faceAware: false);
      runner.calls.clear();
      return (await clipRepo.getByProject(projectId)).single;
    }

    int cropX() {
      final m = RegExp(r'crop=(\d+):(\d+):(\d+):(\d+)')
          .firstMatch(runner.calls.last.join(' '))!;
      return int.parse(m.group(3)!);
    }

    test('sukses: file diganti, data clip dan pengaturan edit tersimpan', () async {
      final clip = await renderOne();
      final oldPath = clip.filePath!;
      File(oldPath).writeAsStringSync('LAMA');

      final r = await service.rerenderClip(
        video: video,
        clip: clip,
        edit: ClipEdit(
          clipId: clip.id!,
          cropMode: EditCropMode.manual,
          focusX: 0.9,
          focusY: 0.5,
          zoom: 1.0,
        ),
        startMs: 5000,
        endMs: 50000,
        title: '  Judul Baru ',
      );

      expect(r.ok, isTrue);
      final after = (await clipRepo.getById(clip.id!))!;
      expect(after.title, 'Judul Baru');
      expect(after.startMs, 5000);
      expect(after.endMs, 50000);
      expect(after.durationMs, 45000);
      expect(after.filePath, oldPath);
      expect(File(oldPath).readAsStringSync(), 'mp4'); // diganti hasil baru
      expect(File('${paths.projectClipsDir(projectId).path}/clip_${clip.id}_edit.mp4')
          .existsSync(), isFalse);
      expect(cropX(), greaterThan(900)); // manual, fokus 90% ke kanan
      expect(faces.calls, 0); // mode manual tidak memanggil detektor

      final saved = (await ClipEditRepository(db.db).get(clip.id!))!;
      expect(saved.cropMode, EditCropMode.manual);
      expect(saved.focusX, 0.9);
    });

    test('mode tengah dan subtitle mati', () async {
      final clip = await renderOne();
      await addTranscript([
        TranscriptSegment(startMs: 1000, endMs: 6000, text: 'Ada transcript tapi mati'),
      ]);
      await service.rerenderClip(
        video: video,
        clip: clip,
        edit: ClipEdit(
            clipId: clip.id!, cropMode: EditCropMode.center, burnSubtitles: false),
        startMs: 0,
        endMs: 30000,
        title: 'X',
      );
      expect(cropX(), 656);
      expect(runner.calls.last.where((a) => a.endsWith('.png')), isEmpty);
    });

    test('gaya subtitle khusus clip tersimpan dan dipakai', () async {
      final clip = await renderOne();
      await addTranscript([
        TranscriptSegment(
            startMs: 1000,
            endMs: 6000,
            text: 'Kenapa banyak orang gagal memulai bisnis mereka sendiri?'),
      ]);
      final style = SubtitlePresets.style(SubtitlePreset.social);
      final r = await service.rerenderClip(
        video: video,
        clip: clip,
        edit: ClipEdit(clipId: clip.id!, cropMode: EditCropMode.center, style: style),
        startMs: 0,
        endMs: 30000,
        title: 'X',
      );
      expect(r.ok, isTrue);
      expect(overlayCount, greaterThan(0));
      final saved = (await ClipEditRepository(db.db).get(clip.id!))!;
      expect(saved.style?.preset, SubtitlePreset.social);
      expect(saved.style?.textColor, 0xFFFFE600);
    });

    test('gagal -> clip lama utuh, tanpa file sementara', () async {
      final clip = await renderOne();
      final oldPath = clip.filePath!;
      File(oldPath).writeAsStringSync('LAMA');
      runner.status = FFmpegStatus.failed;

      final r = await service.rerenderClip(
        video: video,
        clip: clip,
        edit: ClipEdit(clipId: clip.id!, cropMode: EditCropMode.center),
        startMs: 5000,
        endMs: 50000,
        title: 'Baru',
      );

      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
      expect(File(oldPath).readAsStringSync(), 'LAMA');
      final same = (await clipRepo.getById(clip.id!))!;
      expect(same.title, 'Clip 0');
      expect(same.startMs, 0);
      expect(await ClipEditRepository(db.db).get(clip.id!), isNull);
      expect(paths.projectClipsDir(projectId).listSync().length, 1);
      expect(service.isRunning, isFalse);
    });

    test('dibatalkan -> clip lama utuh', () async {
      final clip = await renderOne();
      final oldPath = clip.filePath!;
      File(oldPath).writeAsStringSync('LAMA');
      final token = CancelToken()..cancel();

      final r = await service.rerenderClip(
        video: video,
        clip: clip,
        edit: ClipEdit(clipId: clip.id!, cropMode: EditCropMode.center),
        startMs: 5000,
        endMs: 50000,
        title: 'Baru',
        cancel: token,
      );
      expect(r.cancelled, isTrue);
      expect(File(oldPath).readAsStringSync(), 'LAMA');
      expect(runner.calls, isEmpty);
    });

    test('input tidak valid ditolak sebelum render', () async {
      final clip = await renderOne();
      Future<void> run(int s, int e, String t) => service.rerenderClip(
            video: video,
            clip: clip,
            edit: ClipEdit(clipId: clip.id!),
            startMs: s,
            endMs: e,
            title: t,
          );
      await expectLater(run(0, 1000, 'X'), throwsA(isA<AppException>()));
      await expectLater(run(0, 30000, '  '),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'empty_title')));
      expect(runner.calls, isEmpty);
    });

    test('ruang kurang -> InsufficientStorageException', () async {
      final clip = await renderOne();
      probe.free = 10;
      await expectLater(
        service.rerenderClip(
          video: video,
          clip: clip,
          edit: ClipEdit(clipId: clip.id!),
          startMs: 0,
          endMs: 30000,
          title: 'X',
        ),
        throwsA(isA<InsufficientStorageException>()),
      );
    });

    test('mode wajah memakai hasil deteksi', () async {
      final clip = await renderOne();
      faces.respond = (t) => [
            for (final x in t)
              FaceSample(timeMs: x, faces: const [FaceBox(x: 0.8, y: 0.4, size: 0.12)]),
          ];
      final r = await service.rerenderClip(
        video: video,
        clip: clip,
        edit: ClipEdit(clipId: clip.id!, cropMode: EditCropMode.face),
        startMs: 0,
        endMs: 30000,
        title: 'X',
      );
      expect(r.ok, isTrue);
      expect(r.note, contains('mengikuti wajah'));
      expect(cropX(), greaterThan(900));
    });

    test('hapus clip ikut menghapus pengaturan edit (cascade)', () async {
      final clip = await renderOne();
      await service.rerenderClip(
        video: video,
        clip: clip,
        edit: ClipEdit(clipId: clip.id!, cropMode: EditCropMode.center),
        startMs: 0,
        endMs: 30000,
        title: 'X',
      );
      expect(await ClipEditRepository(db.db).get(clip.id!), isNotNull);
      await service.deleteClip(clip);
      expect(await ClipEditRepository(db.db).get(clip.id!), isNull);
    });
  });
}
