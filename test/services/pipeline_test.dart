import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/processing_job.dart';
import 'package:ai_video_clipper/database/models/project.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/processing_job_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/services/ai/clip_detector.dart';
import 'package:ai_video_clipper/services/background/keep_alive.dart';
import 'package:ai_video_clipper/services/pipeline/pipeline_backend.dart';
import 'package:ai_video_clipper/services/pipeline/processing_pipeline.dart';
import 'package:ai_video_clipper/services/pipeline/startup_recovery.dart';
import 'package:ai_video_clipper/services/render/clip_render_service.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';
import 'package:ai_video_clipper/services/transcription/transcription_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Backend implements PipelineBackend {
  final List<String> log = [];
  bool hasTranscriptValue = false;
  int found = 6;
  int accepted = 5;
  int rendered = 5;
  int renderFailed = 0;
  Object? transcribeError;
  Object? detectError;
  bool transcribeCancelled = false;
  void Function()? onTranscribe;
  void Function()? onRender;
  bool renderCancelled = false;
  Set<int> excluded = {};
  List<String> exportProblems = const [];

  @override
  Future<bool> hasTranscript(int projectId) async => hasTranscriptValue;

  @override
  Future<TranscriptionOutcome> transcribe({
    required VideoRecord video,
    required WhisperModelInfo model,
    required String language,
    required CancelToken cancel,
    required void Function(double fraction) onProgress,
  }) async {
    log.add('transcribe:${model.id}:$language');
    if (transcribeError != null) throw transcribeError!;
    onProgress(0.5);
    onTranscribe?.call();
    onProgress(1);
    return TranscriptionOutcome(
        segmentCount: 10, cancelled: transcribeCancelled || cancel.isCancelled);
  }

  bool needsTranslationValue = false;

  @override
  Future<bool> needsTranslation(int projectId, String target) async =>
      needsTranslationValue;

  @override
  Future<void> translate({
    required int projectId,
    required String source,
    required String target,
    required CancelToken cancel,
    required void Function(double fraction, String status) onProgress,
  }) async {
    log.add('translate:$source>$target');
    onProgress(0.5, 'Menerjemahkan');
  }

  @override
  Future<({int found, int accepted})> detect({
    required VideoRecord video,
    required DetectionOptions options,
    required int acceptTop,
  }) async {
    log.add('detect:$acceptTop');
    if (detectError != null) throw detectError!;
    return (found: found, accepted: accepted);
  }

  @override
  Future<RenderSummary> render({
    required VideoRecord video,
    required bool burnSubtitles,
    required bool faceAware,
    required CancelToken cancel,
    required void Function(double fraction) onProgress,
  }) async {
    log.add('render:$burnSubtitles:$faceAware');
    onProgress(0.5);
    onRender?.call();
    onProgress(1);
    return RenderSummary(
      succeeded: rendered,
      failures: [
        for (var i = 0; i < renderFailed; i++) RenderFailure('c$i', 'gagal'),
      ],
      cancelled: renderCancelled || cancel.isCancelled,
    );
  }

  @override
  Future<Set<int>> clipIds(int projectId) async {
    log.add('clipIds');
    return {1, 2};
  }

  @override
  Future<({int exported, List<String> problems})> exportNew({
    required int projectId,
    required Set<int> excludeIds,
  }) async {
    log.add('export');
    excluded = excludeIds;
    return (exported: rendered, problems: exportProblems);
  }
}

class _KeepAlive implements BackgroundKeepAlive {
  final List<String> events = [];
  final List<int?> progress = [];

  @override
  Future<void> start({required String title, required String text}) async =>
      events.add('start');

  @override
  Future<void> update(
      {required String title, required String text, int? progress}) async {
    events.add('update');
    this.progress.add(progress);
  }

  @override
  Future<void> stop() async => events.add('stop');
}

void main() {
  sqfliteFfiInit();

  final video = VideoRecord(
    id: 1,
    projectId: 7,
    filePath: '/v.mp4',
    fileName: 'v.mp4',
    width: 1920,
    height: 1080,
    durationMs: 300000,
    createdAt: DateTime(2026),
  );

  late _Backend backend;
  late _KeepAlive keep;
  late ProcessingPipeline pipeline;

  setUp(() {
    backend = _Backend();
    keep = _KeepAlive();
    pipeline = ProcessingPipeline(backend: backend, keepAlive: keep);
  });

  group('ProcessingPipeline', () {
    test('urutan lengkap: transkripsi -> deteksi -> render', () async {
      final r = await pipeline.run(video: video);
      expect(backend.log, ['transcribe:base:id', 'detect:5', 'render:true:true']);
      expect(r, isNotNull);
      expect(r!.transcribed, isTrue);
      expect(r.rendered, 5);
      expect(pipeline.state.stage, PipelineStage.done);
      expect(pipeline.state.fraction, 1);
      expect(pipeline.isRunning, isFalse);
    });

    test('terjemahan ko -> id dijalankan setelah transkripsi', () async {
      backend.needsTranslationValue = true;
      final r = await pipeline.run(
        video: video,
        options: const PipelineOptions(language: 'ko', translateTo: 'id'),
      );
      expect(backend.log, [
        'transcribe:base:ko',
        'translate:ko>id',
        'detect:5',
        'render:true:true',
      ]);
      expect(r, isNotNull);
      expect(pipeline.state.fraction, 1);
    });

    test('terjemahan dilewati bila sudah diterjemahkan / bahasa sama / auto',
        () async {
      await pipeline.run(
        video: video,
        options: const PipelineOptions(language: 'ko', translateTo: 'id'),
      );
      expect(backend.log.any((e) => e.startsWith('translate')), isFalse);

      backend.log.clear();
      backend.needsTranslationValue = true;
      await pipeline.run(
        video: video,
        options: const PipelineOptions(language: 'id', translateTo: 'id'),
      );
      await pipeline.run(
        video: video,
        options: const PipelineOptions(language: '', translateTo: 'id'),
      );
      expect(backend.log.any((e) => e.startsWith('translate')), isFalse);
    });

    test('keep-alive: start di awal, stop di akhir, progres naik', () async {
      await pipeline.run(video: video);
      expect(keep.events.first, 'start');
      expect(keep.events.last, 'stop');
      final nums = keep.progress.whereType<int>().toList();
      expect(nums.isNotEmpty, isTrue);
      expect(nums, orderedEquals([...nums]..sort()));
      expect(nums.last, 100);
    });

    test('transcript lama dipakai -> transkripsi dilewati', () async {
      backend.hasTranscriptValue = true;
      final r = await pipeline.run(video: video);
      expect(backend.log.first, 'detect:5');
      expect(r!.reusedTranscript, isTrue);
      expect(r.transcribed, isFalse);
    });

    test('reuseTranscript=false memaksa transkripsi ulang', () async {
      backend.hasTranscriptValue = true;
      await pipeline.run(
          video: video, options: const PipelineOptions(reuseTranscript: false));
      expect(backend.log.first, startsWith('transcribe'));
    });

    test('opsi diteruskan: model, bahasa, jumlah, subtitle, wajah', () async {
      await pipeline.run(
        video: video,
        options: const PipelineOptions(
          model: WhisperModels.tiny,
          language: 'en',
          acceptTop: 3,
          burnSubtitles: false,
          faceAware: false,
        ),
      );
      expect(backend.log, ['transcribe:tiny:en', 'detect:3', 'render:false:false']);
    });

    test('ekspor opsional: hanya clip baru', () async {
      final r = await pipeline.run(
          video: video, options: const PipelineOptions(exportToGallery: true));
      expect(backend.log, contains('export'));
      expect(backend.excluded, {1, 2});
      expect(r!.exported, 5);
    });

    test('tanpa ekspor -> tidak memanggil export', () async {
      await pipeline.run(video: video);
      expect(backend.log, isNot(contains('export')));
    });

    test('progres keseluruhan monoton naik dan di antara 0..1', () async {
      final seen = <double>[];
      pipeline.addListener(() => seen.add(pipeline.state.fraction));
      await pipeline.run(video: video);
      expect(seen.every((f) => f >= 0 && f <= 1), isTrue);
      expect(seen, orderedEquals([...seen]..sort()));
    });

    test('error AppException -> failed dengan pesan jelas, keep-alive berhenti',
        () async {
      backend.transcribeError =
          const AppException('Model Base belum diunduh.', code: 'model_missing');
      final r = await pipeline.run(video: video);
      expect(r, isNull);
      expect(pipeline.state.stage, PipelineStage.failed);
      expect(pipeline.state.error, 'Model Base belum diunduh.');
      expect(keep.events.last, 'stop');
      expect(pipeline.isRunning, isFalse);
      expect(backend.log, ['transcribe:base:id']);
    });

    test('error tak terduga -> pesan ramah tanpa stack trace', () async {
      backend.detectError = StateError('boom');
      backend.hasTranscriptValue = true;
      await pipeline.run(video: video);
      expect(pipeline.state.stage, PipelineStage.failed);
      expect(pipeline.state.error, 'Pemrosesan gagal. Coba lagi.');
      expect(pipeline.state.error, isNot(contains('boom')));
    });

    test('tidak ada kandidat -> gagal dengan saran', () async {
      backend.hasTranscriptValue = true;
      backend.accepted = 0;
      await pipeline.run(video: video);
      expect(pipeline.state.stage, PipelineStage.failed);
      expect(pipeline.state.error, contains('momen'));
      expect(backend.log, ['detect:5']); // render tidak dijalankan
    });

    test('semua render gagal -> failed', () async {
      backend.hasTranscriptValue = true;
      backend.rendered = 0;
      backend.renderFailed = 5;
      await pipeline.run(video: video);
      expect(pipeline.state.stage, PipelineStage.failed);
      expect(pipeline.state.result!.renderFailed, 5);
    });

    test('sebagian render gagal -> tetap selesai dengan ringkasan', () async {
      backend.hasTranscriptValue = true;
      backend.rendered = 4;
      backend.renderFailed = 1;
      final r = await pipeline.run(video: video);
      expect(r!.rendered, 4);
      expect(r.summary, contains('1 gagal'));
    });

    test('batal saat transkripsi -> tidak lanjut ke tahap berikutnya', () async {
      backend.onTranscribe = pipeline.cancel;
      await pipeline.run(video: video);
      expect(pipeline.state.stage, PipelineStage.cancelled);
      expect(backend.log, ['transcribe:base:id']);
      expect(keep.events.last, 'stop');
    });

    test('batal saat render -> cancelled dan hasil parsial dipertahankan',
        () async {
      backend.hasTranscriptValue = true;
      backend.onRender = pipeline.cancel;
      await pipeline.run(video: video);
      expect(pipeline.state.stage, PipelineStage.cancelled);
      expect(pipeline.state.result!.accepted, 5);
    });

    test('menjalankan dua pipeline bersamaan ditolak', () async {
      backend.onTranscribe = () {};
      final first = pipeline.run(video: video);
      await expectLater(pipeline.run(video: video),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'busy')));
      await first;
      expect(pipeline.isRunning, isFalse);
      // Sesudah selesai bisa dijalankan lagi.
      expect(await pipeline.run(video: video), isNotNull);
    });

    test('reset mengembalikan state ke idle', () async {
      await pipeline.run(video: video);
      pipeline.reset();
      expect(pipeline.state.stage, PipelineStage.idle);
    });
  });

  group('StartupRecovery', () {
    late Directory tmp;
    late AppPaths paths;
    late AppDatabase db;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('avc_recovery_');
      final root = await Directory(p.join(tmp.path, 'app')).create();
      paths = await AppPaths.fromBase(root);
      db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
          factory: databaseFactoryFfi);
    });

    tearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('job terputus ditandai gagal, project direset, temp dibersihkan',
        () async {
      final projects = ProjectRepository(db.db);
      final jobs = ProcessingJobRepository(db.db);
      final pa = await projects.create('A');
      final pb = await projects.create('B');
      final pc = await projects.create('C');
      final pd = await projects.create('D');
      await projects.updateStatus(pa.id!, ProjectStatus.transcribing);
      await projects.updateStatus(pb.id!, ProjectStatus.analyzing);
      await projects.updateStatus(pc.id!, ProjectStatus.rendering);
      await projects.updateStatus(pd.id!, ProjectStatus.completed);

      final running =
          await jobs.enqueue(projectId: pa.id!, type: JobType.transcribe);
      await jobs.updateStatus(running.id!, JobStatus.running);
      final queued =
          await jobs.enqueue(projectId: pc.id!, type: JobType.renderClip);
      final done =
          await jobs.enqueue(projectId: pd.id!, type: JobType.renderClip);
      await jobs.updateStatus(done.id!, JobStatus.completed);

      // File sementara + hasil yang HARUS tetap ada.
      await paths.ensureProjectDir(pc.id!);
      final tempFile = File(p.join(paths.projectTempDir(pc.id!).path, 'x.wav'))
        ..writeAsStringSync('t');
      final staleEdit =
          File(p.join(paths.projectClipsDir(pc.id!).path, 'clip_9_edit.mp4'))
            ..writeAsStringSync('e');
      final keepClip =
          File(p.join(paths.projectClipsDir(pc.id!).path, 'clip_9.mp4'))
            ..writeAsStringSync('c');
      final globalTemp = File(p.join(paths.temp.path, 'edit_frame_1.jpg'))
        ..writeAsStringSync('j');
      final modelFile = File(p.join(paths.root.path, 'models', 'tiny.onnx'))
        ..createSync(recursive: true);

      final report = await StartupRecovery(
              jobs: jobs, projects: projects, paths: paths)
          .run();

      expect(report.interruptedJobs, 2);
      expect(report.resetProjects, 3);
      expect((await jobs.getById(running.id!))!.status, JobStatus.failed);
      expect((await jobs.getById(running.id!))!.errorMessage, contains('Terhenti'));
      expect((await jobs.getById(queued.id!))!.status, JobStatus.failed);
      expect((await jobs.getById(done.id!))!.status, JobStatus.completed);
      expect(await jobs.nextQueued(), isNull);

      expect((await projects.getById(pa.id!))!.status, ProjectStatus.videoAdded);
      expect((await projects.getById(pb.id!))!.status, ProjectStatus.transcribed);
      expect((await projects.getById(pc.id!))!.status, ProjectStatus.analyzed);
      expect((await projects.getById(pd.id!))!.status, ProjectStatus.completed);

      expect(tempFile.existsSync(), isFalse);
      expect(staleEdit.existsSync(), isFalse);
      expect(globalTemp.existsSync(), isFalse);
      expect(keepClip.existsSync(), isTrue);
      expect(modelFile.existsSync(), isTrue);
    });

    test('tidak ada yang perlu dipulihkan -> laporan kosong', () async {
      final report = await StartupRecovery(
              jobs: ProcessingJobRepository(db.db),
              projects: ProjectRepository(db.db),
              paths: paths)
          .run();
      expect(report.didAnything, isFalse);
    });

    test('tanpa paths tetap memulihkan database', () async {
      final projects = ProjectRepository(db.db);
      final pa = await projects.create('A');
      await projects.updateStatus(pa.id!, ProjectStatus.rendering);
      final report = await StartupRecovery(
              jobs: ProcessingJobRepository(db.db), projects: projects)
          .run();
      expect(report.resetProjects, 1);
    });
  });
}
