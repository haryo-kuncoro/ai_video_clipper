import 'dart:io';
import 'dart:typed_data';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/processing_job.dart';
import 'package:ai_video_clipper/database/models/project.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/processing_job_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/transcript_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_models.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_queue.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_runner.dart';
import 'package:ai_video_clipper/services/ffmpeg/ffmpeg_service.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';
import 'package:ai_video_clipper/services/transcription/transcription_engine.dart';
import 'package:ai_video_clipper/services/transcription/transcription_models.dart';
import 'package:ai_video_clipper/services/transcription/transcription_service.dart';
import 'package:ai_video_clipper/services/transcription/wav_reader.dart';
import 'package:ai_video_clipper/services/transcription/whisper_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Runner implements FFmpegRunner {
  FFmpegStatus status = FFmpegStatus.success;

  @override
  Future<FFmpegRunOutcome> run(List<String> args,
      {void Function(int processedMs)? onProgress}) async {
    onProgress?.call(500);
    if (status == FFmpegStatus.success) File(args.last).writeAsStringSync('wav');
    return FFmpegRunOutcome(status: status);
  }

  @override
  Future<void> cancel() async {}
}

class _Engine implements TranscriptionEngine {
  List<RawSegment> result = const [
    RawSegment(startMs: 2000, endMs: 4000, text: ' Halo dunia '),
    RawSegment(startMs: 500, endMs: 1500, text: 'Pembuka'),
    RawSegment(startMs: 5000, endMs: 5000, text: 'terbalik'),
    RawSegment(startMs: 6000, endMs: 7000, text: '   '),
  ];
  Object? error;
  bool cancelDuring = false;
  String? seenLanguage;

  @override
  String get name => 'fake';

  @override
  Future<List<RawSegment>> transcribe({
    required String wavPath,
    required WhisperModelFiles files,
    required String language,
    int threads = 2,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    seenLanguage = language;
    onProgress?.call(0.5);
    if (cancelDuring) throw const TranscriptionCancelled();
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

Uint8List _wav(List<int> samples, {int rate = 16000, int channels = 1}) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  final h = ByteData(44);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + data.lengthInBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * channels * 2, Endian.little);
  h.setUint16(32, channels * 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, data.lengthInBytes, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...data.buffer.asUint8List()]);
}

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('avc_stt_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('wav_reader', () {
    test('membaca header dan mengonversi sampel', () async {
      final f = File(p.join(tmp.path, 'a.wav'))
        ..writeAsBytesSync(_wav([0, 16384, -32768, 32767]));
      final raf = await f.open();
      final info = await readWavInfo(raf);
      await raf.setPosition(info.dataOffset);
      final bytes = await raf.read(info.dataLength);
      await raf.close();

      expect(info.sampleRate, 16000);
      expect(info.sampleCount, 4);
      final floats = pcm16ToFloat32(bytes);
      expect(floats[0], 0.0);
      expect(floats[1], closeTo(0.5, 1e-6));
      expect(floats[2], -1.0);
      expect(floats[3], closeTo(0.99997, 1e-4));
    });

    test('menolak stereo dan file non-WAV', () async {
      final stereo = File(p.join(tmp.path, 's.wav'))
        ..writeAsBytesSync(_wav([1, 2], channels: 2));
      var raf = await stereo.open();
      await expectLater(readWavInfo(raf), throwsA(isA<WavFormatException>()));
      await raf.close();

      final junk = File(p.join(tmp.path, 'j.wav'))
        ..writeAsBytesSync(List.filled(64, 7));
      raf = await junk.open();
      await expectLater(readWavInfo(raf), throwsA(isA<WavFormatException>()));
      await raf.close();
    });

    test('ukuran data 0 (streaming) memakai sisa file', () async {
      final bytes = _wav([1, 2, 3]);
      ByteData.sublistView(bytes).setUint32(40, 0, Endian.little);
      final f = File(p.join(tmp.path, 'z.wav'))..writeAsBytesSync(bytes);
      final raf = await f.open();
      final info = await readWavInfo(raf);
      await raf.close();
      expect(info.sampleCount, 3);
    });
  });

  group('WhisperModelManager', () {
    late HttpServer server;
    late WhisperModelInfo model;
    late WhisperModelManager manager;
    var hits = 0;

    setUp(() async {
      hits = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hits++;
        if (req.uri.path.contains('missing')) {
          req.response.statusCode = 404;
        } else {
          req.response.add(List.filled(1000, 1));
        }
        await req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      model = WhisperModelInfo(
          id: 'tiny', label: 'Tiny', description: '', baseUrl: base);
      manager = WhisperModelManager(
        Directory(p.join(tmp.path, 'models')),
        vadUrl: '$base/silero_vad.onnx',
        validateContent: false,
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('download memasang semua file; ulangi tidak mengunduh lagi', () async {
      expect(await manager.isInstalled(model), isFalse);
      await expectLater(manager.resolve(model), throwsA(isA<AppException>()));

      await manager.download(model);
      expect(await manager.isInstalled(model), isTrue);
      expect(hits, 4);

      final files = await manager.resolve(model);
      expect(File(files.encoder).existsSync(), isTrue);
      expect(File(files.vad).existsSync(), isTrue);

      await manager.download(model);
      expect(hits, 4);
      expect(await manager.installedSize(model), 3000);
    });

    test('status 404 -> pesan ramah dan tanpa file .part', () async {
      final bad = WhisperModelInfo(
        id: 'tiny',
        label: 'Tiny',
        description: '',
        baseUrl: 'http://127.0.0.1:${server.port}/missing',
      );
      await expectLater(
        manager.download(bad),
        throwsA(isA<AppException>()
            .having((e) => e.code, 'code', 'model_http_404')),
      );
      final leftovers = manager
          .modelDir(bad)
          .listSync()
          .where((e) => e.path.endsWith('.part'));
      expect(leftovers, isEmpty);
    });

    test('file gzip/HTML dianggap rusak, dihapus, tidak dipakai', () async {
      final strict = WhisperModelManager(
        Directory(p.join(tmp.path, 'strict')),
        vadUrl: 'http://127.0.0.1:${server.port}/v.onnx',
      );
      final dir = strict.modelDir(model)..createSync(recursive: true);
      File(p.join(dir.path, model.tokensName))
          .writeAsBytesSync([0x1f, 0x8b, 8, 0, 1, 2, 3]);
      expect(await strict.isInstalled(model), isFalse);
      await expectLater(strict.resolve(model), throwsA(isA<AppException>()));
      await strict.purgeInvalid(model);
      expect(File(p.join(dir.path, model.tokensName)).existsSync(), isFalse);
    });

    test('dibatalkan sebelum mulai', () async {
      final token = CancelToken()..cancel();
      await expectLater(manager.download(model, cancel: token),
          throwsA(isA<TranscriptionCancelled>()));
      expect(await manager.isInstalled(model), isFalse);
    });

    test('hapus model menghapus foldernya', () async {
      await manager.download(model);
      await manager.delete(model);
      expect(await manager.isInstalled(model), isFalse);
    });

    test('server mati -> pesan jaringan', () async {
      await server.close(force: true);
      await expectLater(
        manager.download(model),
        throwsA(isA<AppException>()
            .having((e) => e.code, 'code', 'model_network')),
      );
    });
  });

  group('TranscriptionService', () {
    late AppDatabase db;
    late AppPaths paths;
    late _Runner runner;
    late _Engine engine;
    late WhisperModelManager manager;
    late TranscriptionService service;
    late VideoRecord video;
    late int projectId;
    const model = WhisperModels.tiny;

    setUp(() async {
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
        durationMs: 10000,
        createdAt: DateTime.now(),
      ));

      runner = _Runner();
      engine = _Engine();
      manager = WhisperModelManager(Directory(p.join(tmp.path, 'models')),
          validateContent: false);
      // Pasang model palsu langsung ke disk.
      final dir = manager.modelDir(model)..createSync(recursive: true);
      for (final n in [model.encoderName, model.decoderName, model.tokensName]) {
        File(p.join(dir.path, n)).writeAsStringSync('x');
      }
      File(p.join(manager.modelsDir.path, WhisperModelManager.vadFileName))
          .writeAsStringSync('x');

      service = TranscriptionService(
        ffmpeg: FFmpegService(FFmpegQueue(runner)),
        engine: engine,
        models: manager,
        transcripts: TranscriptRepository(db.db),
        projects: ProjectRepository(db.db),
        jobs: ProcessingJobRepository(db.db),
        paths: paths,
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<ProjectStatus> status() async =>
        (await ProjectRepository(db.db).getById(projectId))!.status;

    test('sukses: segmen dirapikan, tersimpan, status transcribed', () async {
      final phases = <TranscriptionPhase>[];
      final r = await service.transcribe(
        video: video,
        model: model,
        onProgress: (p) => phases.add(p.phase),
      );

      expect(r.segmentCount, 2);
      expect(engine.seenLanguage, 'id');
      final segs = await service.transcripts.getSegments(r.transcriptId!);
      expect(segs.map((s) => s.text), ['Pembuka', 'Halo dunia']);
      expect(segs.first.startMs, 500);
      expect(await status(), ProjectStatus.transcribed);

      final jobs = await ProcessingJobRepository(db.db).getByProject(projectId);
      expect(jobs.single.type, JobType.transcribe);
      expect(jobs.single.status, JobStatus.completed);
      expect(phases, contains(TranscriptionPhase.extractingAudio));
      expect(phases.last, TranscriptionPhase.saving);

      // Audio sementara dibersihkan.
      expect(File(p.join(paths.projectTempDir(projectId).path, 'stt_audio.wav'))
          .existsSync(), isFalse);
    });

    test('transcribe ulang mengganti transcript lama (tidak menggandakan)',
        () async {
      await service.transcribe(video: video, model: model);
      engine.result = const [
        RawSegment(startMs: 0, endMs: 1000, text: 'Baru'),
      ];
      final r = await service.transcribe(video: video, model: model);

      final t = await service.transcripts.getByProject(projectId);
      expect(t!.id, r.transcriptId);
      expect((await service.transcripts.getSegments(t.id!)).single.text, 'Baru');
      final all = await db.db.query('transcripts');
      expect(all.length, 1);
    });

    test('model belum diunduh -> error model_missing, tanpa job', () async {
      await manager.delete(model);
      await expectLater(
        service.transcribe(video: video, model: model),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'model_missing')),
      );
      expect(await ProcessingJobRepository(db.db).getByProject(projectId), isEmpty);
    });

    test('file video hilang -> pesan ramah', () async {
      File(video.filePath).deleteSync();
      await expectLater(
        service.transcribe(video: video, model: model),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'video_missing')),
      );
    });

    test('ekstrak audio gagal -> job failed, status dikembalikan', () async {
      runner.status = FFmpegStatus.failed;
      await expectLater(
        service.transcribe(video: video, model: model),
        throwsA(isA<AppException>()),
      );
      expect(await status(), ProjectStatus.videoAdded);
      final job =
          (await ProcessingJobRepository(db.db).getByProject(projectId)).single;
      expect(job.status, JobStatus.failed);
      expect(job.errorMessage, isNotEmpty);
      expect(service.isRunning, isFalse);
    });

    test('tidak ada ucapan -> error no_speech dan tidak menyimpan', () async {
      engine.result = const [];
      await expectLater(
        service.transcribe(video: video, model: model),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'no_speech')),
      );
      expect(await service.transcripts.getByProject(projectId), isNull);
      expect(await status(), ProjectStatus.videoAdded);
    });

    test('error mesin tak dikenal -> pesan umum tanpa stack trace', () async {
      engine.error = StateError('boom');
      await expectLater(
        service.transcribe(video: video, model: model),
        throwsA(isA<AppException>().having(
            (e) => e.message, 'message', isNot(contains('boom')))),
      );
      expect(service.isRunning, isFalse);
    });

    test('dibatalkan -> outcome cancelled, job cancelled, transcript lama utuh',
        () async {
      await service.transcribe(video: video, model: model);
      engine.cancelDuring = true;
      final r = await service.transcribe(video: video, model: model);

      expect(r.cancelled, isTrue);
      expect(await status(), ProjectStatus.transcribed);
      expect((await service.transcripts
              .getSegments((await service.transcripts.getByProject(projectId))!.id!))
          .length, 2);
      final jobs = await ProcessingJobRepository(db.db).getByProject(projectId);
      expect(jobs.last.status, JobStatus.cancelled);
    });

    test('bahasa otomatis disimpan sebagai auto', () async {
      await service.transcribe(video: video, model: model, language: '');
      expect((await service.transcripts.getByProject(projectId))!.language, 'auto');
    });
  });
}
