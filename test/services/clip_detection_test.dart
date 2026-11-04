import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/clip_candidate.dart';
import 'package:ai_video_clipper/database/models/processing_job.dart';
import 'package:ai_video_clipper/database/models/project.dart';
import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/clip_candidate_repository.dart';
import 'package:ai_video_clipper/database/repositories/processing_job_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/transcript_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:ai_video_clipper/services/ai/clip_detection_service.dart';
import 'package:ai_video_clipper/services/ai/clip_detector.dart';
import 'package:ai_video_clipper/services/ai/rule_based_clip_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _boring = 'Ini adalah kalimat biasa saja tanpa isi khusus.';
const _hook = 'Kenapa kebanyakan orang gagal memulai bisnis? '
    'Ternyata kesalahan terbesarnya ada 3 hal.';

TranscriptSegment seg(num startSec, num endSec, String text) =>
    TranscriptSegment(
      startMs: (startSec * 1000).round(),
      endMs: (endSec * 1000).round(),
      text: text,
    );

/// 20 segmen x 8 dtk berurutan; segmen ke-10 (mulai 80 dtk) adalah hook.
List<TranscriptSegment> _longTalk() => [
      for (var i = 0; i < 20; i++)
        seg(i * 8, i * 8 + 8, i == 10 ? _hook : _boring),
    ];

void main() {
  const detector = RuleBasedClipDetector();

  group('scoreUnit & makeTitle', () {
    test('segmen sangat pendek dinilai rendah', () {
      expect(scoreUnit(seg(0, 2, 'Ya oke')).score, lessThan(0.1));
    });

    test('pertanyaan + kata kunci + angka dinilai lebih tinggi', () {
      final plain = scoreUnit(seg(0, 8, _boring));
      final hook = scoreUnit(seg(0, 8, _hook));
      expect(hook.score, greaterThan(plain.score));
      expect(hook.reasons, containsAll(['pertanyaan', 'angka/data']));
    });

    test('makeTitle membuang pembuka kosong dan membatasi 8 kata', () {
      expect(
        makeTitle('Jadi, nah kita mulai dari masalah pelanggan yang paling besar sekali'),
        'Kita mulai dari masalah pelanggan yang paling besar',
      );
      expect(makeTitle('   '), 'Clip');
    });
  });

  group('RuleBasedClipDetector', () {
    test('memilih bagian dengan hook sebagai awal clip terbaik', () async {
      final clips = await detector.detect(
        segments: _longTalk(),
        videoDurationMs: 160000,
      );
      expect(clips, isNotEmpty);
      expect(clips.first.startMs, 79800); // 80 dtk dikurangi bantalan 200 ms
      expect(clips.first.title, startsWith('Kenapa kebanyakan orang'));
      expect(clips.first.reason, contains('Pembuka: pertanyaan'));
    });

    test('hasil tidak saling tumpang tindih dan sesuai batas durasi', () async {
      final clips = await detector.detect(
        segments: _longTalk(),
        videoDurationMs: 160000,
        options: const DetectionOptions(minScore: 0.0),
      );
      for (final c in clips) {
        expect(c.durationMs, greaterThanOrEqualTo(30000));
        expect(c.durationMs, lessThanOrEqualTo(60000 + 500));
        expect(c.startMs, greaterThanOrEqualTo(0));
        expect(c.endMs, lessThanOrEqualTo(160000));
        expect(c.score, inInclusiveRange(0.0, 1.0));
      }
      final sorted = [...clips]..sort((a, b) => a.startMs.compareTo(b.startMs));
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i].startMs, greaterThanOrEqualTo(sorted[i - 1].endMs));
      }
    });

    test('maxClips dihormati dan urut skor menurun', () async {
      final clips = await detector.detect(
        segments: _longTalk(),
        videoDurationMs: 160000,
        options: const DetectionOptions(maxClips: 2, minScore: 0.0),
      );
      expect(clips.length, 2);
      expect(clips[0].score, greaterThanOrEqualTo(clips[1].score));
    });

    test('jeda hening panjang memutus clip', () async {
      final segs = [
        for (var i = 0; i < 3; i++) seg(i * 8, i * 8 + 8, _hook),
        for (var i = 0; i < 3; i++) seg(100 + i * 8, 108 + i * 8, _hook),
      ];
      final clips = await detector.detect(
        segments: segs,
        videoDurationMs: 200000,
        options: const DetectionOptions(minScore: 0.0),
      );
      // Tiap kelompok hanya 24 dtk (< 30 dtk) dan tidak boleh digabung.
      expect(clips, isEmpty);
    });

    test('video lebih pendek dari batas minimum tetap menghasilkan 1 clip',
        () async {
      final clips = await detector.detect(
        segments: [seg(0, 6, _hook), seg(6, 12, _boring)],
        videoDurationMs: 12000,
      );
      expect(clips.length, 1);
      expect(clips.first.startMs, 0);
      expect(clips.first.endMs, 12000);
    });

    test('transcript kosong -> daftar kosong', () async {
      expect(await detector.detect(segments: const [], videoDurationMs: 1000),
          isEmpty);
    });

    test('hasil deterministik', () async {
      final a = await detector.detect(segments: _longTalk(), videoDurationMs: 160000);
      final b = await detector.detect(segments: _longTalk(), videoDurationMs: 160000);
      expect(a.map((c) => [c.startMs, c.endMs, c.score]).toList(),
          b.map((c) => [c.startMs, c.endMs, c.score]).toList());
    });
  });

  group('ClipDetectionService', () {
    late Directory tmp;
    late AppDatabase db;
    late int projectId;
    late ClipDetectionService service;

    setUpAll(() {
      sqfliteFfiInit();
    });

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('avc_detect_');
      db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
          factory: databaseFactoryFfi);
      projectId = (await ProjectRepository(db.db).create('P')).id!;
      service = ClipDetectionService(
        detector: detector,
        transcripts: TranscriptRepository(db.db),
        candidates: ClipCandidateRepository(db.db),
        projects: ProjectRepository(db.db),
        jobs: ProcessingJobRepository(db.db),
      );
    });

    tearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<void> saveTranscript(List<TranscriptSegment> segs) async {
      final video = await VideoRepository(db.db).insert(VideoRecord(
        projectId: projectId,
        filePath: '/x.mp4',
        fileName: 'x.mp4',
        createdAt: DateTime.now(),
      ));
      await TranscriptRepository(db.db).replaceForProject(
        Transcript(
            projectId: projectId, videoId: video.id!, createdAt: DateTime.now()),
        segs,
      );
    }

    Future<ProjectStatus> status() async =>
        (await ProjectRepository(db.db).getById(projectId))!.status;

    test('tanpa transcript -> pesan ramah', () async {
      await expectLater(
        service.detect(projectId: projectId, videoDurationMs: 1000),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'no_transcript')),
      );
    });

    test('sukses: kandidat tersimpan pending, status analyzed, job completed',
        () async {
      await saveTranscript(_longTalk());
      final list =
          await service.detect(projectId: projectId, videoDurationMs: 160000);

      expect(list, isNotEmpty);
      expect(list.first.status, CandidateStatus.pending);
      expect(list.first.title, startsWith('Kenapa'));
      expect(await status(), ProjectStatus.analyzed);
      final job =
          (await ProcessingJobRepository(db.db).getByProject(projectId)).single;
      expect(job.type, JobType.analyze);
      expect(job.status, JobStatus.completed);
    });

    test('dijalankan ulang mengganti kandidat (tidak menggandakan)', () async {
      await saveTranscript(_longTalk());
      await service.detect(projectId: projectId, videoDurationMs: 160000);
      final first = (await db.db.query('clip_candidates')).length;
      await service.detect(projectId: projectId, videoDurationMs: 160000);
      expect((await db.db.query('clip_candidates')).length, first);
    });

    test('tidak ada kandidat -> error, status dikembalikan, kandidat lama utuh',
        () async {
      await saveTranscript(_longTalk());
      await service.detect(projectId: projectId, videoDurationMs: 160000);
      final before = (await db.db.query('clip_candidates')).length;

      // Ganti transcript dengan yang terlalu pendek untuk menjadi clip.
      await saveTranscript([seg(0, 3, 'Halo.')]);
      await expectLater(
        service.detect(projectId: projectId, videoDurationMs: 160000),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'no_candidates')),
      );
      expect((await db.db.query('clip_candidates')).length, before);
      expect(await status(), ProjectStatus.analyzed);
      final jobs = await ProcessingJobRepository(db.db).getByProject(projectId);
      expect(jobs.last.status, JobStatus.failed);
    });
  });
}
