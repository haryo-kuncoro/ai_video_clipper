import 'dart:io';

import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/transcript_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late TranscriptRepository repo;
  late int transcriptId;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('avc_tedit_');
    db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
        factory: databaseFactoryFfi);
    repo = TranscriptRepository(db.db);

    final project = await ProjectRepository(db.db).create('P');
    final video = await VideoRepository(db.db).insert(VideoRecord(
      projectId: project.id!,
      filePath: '/x.mp4',
      fileName: 'x.mp4',
      createdAt: DateTime.now(),
    ));
    transcriptId = await repo.save(
      Transcript(
        projectId: project.id!,
        videoId: video.id!,
        createdAt: DateTime.now(),
      ),
      const [
        TranscriptSegment(startMs: 0, endMs: 1000, text: 'satu'),
        TranscriptSegment(startMs: 1000, endMs: 2500, text: 'dua'),
        TranscriptSegment(startMs: 3000, endMs: 4000, text: 'tiga'),
      ],
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('updateSegmentText mengubah teks saja', () async {
    final segs = await repo.getSegments(transcriptId);
    await repo.updateSegmentText(segs[1].id!, 'DUA');
    final after = await repo.getSegments(transcriptId);
    expect(after.map((s) => s.text), ['satu', 'DUA', 'tiga']);
    expect(after[1].startMs, 1000);
    expect(after[1].endMs, 2500);
  });

  test('deleteSegment', () async {
    final segs = await repo.getSegments(transcriptId);
    await repo.deleteSegment(segs[0].id!);
    expect((await repo.getSegments(transcriptId)).map((s) => s.text),
        ['dua', 'tiga']);
  });

  test('mergeWithNext menyambung teks dan memperpanjang waktu', () async {
    final segs = await repo.getSegments(transcriptId);
    expect(await repo.mergeWithNext(segs[0].id!), isTrue);

    final after = await repo.getSegments(transcriptId);
    expect(after.map((s) => s.text), ['satu dua', 'tiga']);
    expect(after[0].startMs, 0);
    expect(after[0].endMs, 2500);
  });

  test('mergeWithNext pada segmen terakhir mengembalikan false', () async {
    final segs = await repo.getSegments(transcriptId);
    expect(await repo.mergeWithNext(segs.last.id!), isFalse);
    expect((await repo.getSegments(transcriptId)).length, 3);
  });

  test('mergeWithNext pada id yang tidak ada mengembalikan false', () async {
    expect(await repo.mergeWithNext(99999), isFalse);
  });
}
