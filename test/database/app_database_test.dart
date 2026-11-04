import 'dart:io';

import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/migrations/migration_v1.dart';
import 'package:ai_video_clipper/database/models/clip.dart';
import 'package:ai_video_clipper/database/models/clip_candidate.dart';
import 'package:ai_video_clipper/database/models/processing_job.dart';
import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/app_settings_repository.dart';
import 'package:ai_video_clipper/database/repositories/clip_candidate_repository.dart';
import 'package:ai_video_clipper/database/repositories/clip_repository.dart';
import 'package:ai_video_clipper/database/repositories/processing_job_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/transcript_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('avc_db_');
    dbPath = p.join(tmp.path, 'test.db');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<AppDatabase> openDb() =>
      AppDatabase.openAt(dbPath, factory: databaseFactoryFfi);

  Future<int> count(AppDatabase d, String table) async {
    final r = await d.db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return r.first['c'] as int;
  }

  test('database baru membuat semua tabel (versi 6)', () async {
    final d = await openDb();
    final info = await d.info();
    expect(info.version, 6);
    expect(
      info.tables,
      containsAll([
        'projects',
        'videos',
        'transcripts',
        'transcript_segments',
        'clip_candidates',
        'clips',
        'processing_jobs',
        'app_settings',
        'subtitle_settings',
        'users_local',
        'clip_edits',
        'exports',
      ]),
    );
    await d.close();
  });

  test('menghapus project menghapus semua data turunan (cascade)', () async {
    final d = await openDb();
    final projects = ProjectRepository(d.db);
    final videos = VideoRepository(d.db);
    final transcripts = TranscriptRepository(d.db);
    final candidates = ClipCandidateRepository(d.db);
    final clips = ClipRepository(d.db);
    final jobs = ProcessingJobRepository(d.db);
    final now = DateTime.now();

    final project = await projects.create('Podcast Episode 01');
    final video = await videos.insert(VideoRecord(
      projectId: project.id!,
      filePath: '/x/source.mp4',
      fileName: 'source.mp4',
      durationMs: 1800000,
      width: 1920,
      height: 1080,
      fileSize: 1234,
      createdAt: now,
    ));
    await transcripts.save(
      Transcript(projectId: project.id!, videoId: video.id!, createdAt: now),
      const [TranscriptSegment(startMs: 0, endMs: 1000, text: 'halo')],
    );
    await candidates.insertAll([
      ClipCandidate(
        projectId: project.id!,
        startMs: 0,
        endMs: 5000,
        title: 'A',
        createdAt: now,
      ),
    ]);
    await clips.insert(Clip(
      projectId: project.id!,
      startMs: 0,
      endMs: 5000,
      title: 'A',
      createdAt: now,
    ));
    await jobs.enqueue(projectId: project.id!, type: JobType.transcribe);

    await projects.delete(project.id!);

    for (final t in [
      'videos',
      'transcripts',
      'transcript_segments',
      'clip_candidates',
      'clips',
      'processing_jobs',
    ]) {
      expect(await count(d, t), 0, reason: t);
    }
    await d.close();
  });

  test('upgrade v1 -> versi terbaru mempertahankan data project lama', () async {
    final v1 = await AppDatabase.openAt(
      dbPath,
      factory: databaseFactoryFfi,
      migrations: const [MigrationV1()],
    );
    await ProjectRepository(v1.db).create('Project lama');
    expect((await v1.info()).version, 1);
    await v1.close();

    final v2 = await openDb();
    final info = await v2.info();
    expect(info.version, 6);
    expect(info.tables, contains('subtitle_settings'));
    final all = await ProjectRepository(v2.db).getAll();
    expect(all.map((e) => e.name), ['Project lama']);
    await v2.close();
  });

  test('segmen transcript tersimpan dan bisa diambil per rentang', () async {
    final d = await openDb();
    final project = await ProjectRepository(d.db).create('P');
    final video = await VideoRepository(d.db).insert(VideoRecord(
      projectId: project.id!,
      filePath: '/x.mp4',
      fileName: 'x.mp4',
      createdAt: DateTime.now(),
    ));
    final repo = TranscriptRepository(d.db);
    final id = await repo.save(
      Transcript(
        projectId: project.id!,
        videoId: video.id!,
        language: 'id',
        createdAt: DateTime.now(),
      ),
      const [
        TranscriptSegment(startMs: 4000, endMs: 13000, text: 'satu'),
        TranscriptSegment(startMs: 13000, endMs: 27000, text: 'dua'),
        TranscriptSegment(startMs: 27000, endMs: 40000, text: 'tiga'),
      ],
    );
    expect((await repo.getSegments(id)).length, 3);
    final inRange = await repo.getSegmentsInRange(id, 10000, 20000);
    expect(inRange.map((s) => s.text), ['satu', 'dua']);
    await d.close();
  });

  test('job running dikembalikan ke queued saat restart', () async {
    final d = await openDb();
    final project = await ProjectRepository(d.db).create('P');
    final jobs = ProcessingJobRepository(d.db);
    final job =
        await jobs.enqueue(projectId: project.id!, type: JobType.renderClip);
    await jobs.updateStatus(job.id!, JobStatus.running);

    expect(await jobs.resetInterrupted(), 1);
    final after = await jobs.getById(job.id!);
    expect(after!.status, JobStatus.queued);
    expect((await jobs.nextQueued())!.id, job.id);
    await d.close();
  });

  test('app settings: set, get, timpa nilai, hapus', () async {
    final d = await openDb();
    final s = AppSettingsRepository(d.db);
    expect(await s.get('max_clip_count'), isNull);
    await s.set('max_clip_count', '5');
    await s.set('max_clip_count', '8');
    expect(await s.getInt('max_clip_count'), 8);
    await s.remove('max_clip_count');
    expect(await s.get('max_clip_count'), isNull);
    await d.close();
  });
}
