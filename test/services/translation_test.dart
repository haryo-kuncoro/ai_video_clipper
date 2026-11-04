import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/transcript_repository.dart';
import 'package:ai_video_clipper/services/transcription/transcription_models.dart';
import 'package:ai_video_clipper/services/translation/text_translator.dart';
import 'package:ai_video_clipper/services/translation/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Translator implements TextTranslator {
  int ensured = 0;
  bool closed = false;
  Object? failEnsure;

  @override
  Future<void> ensureModels(String source, String target,
      {void Function(String status)? onStatus}) async {
    if (failEnsure != null) throw failEnsure!;
    ensured++;
  }

  @override
  Future<String> translate(String source, String target, String text) async =>
      text == 'kosong' ? '' : '[$target] $text';

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late TranscriptRepository repo;
  late _Translator tr;
  late TranslationService svc;
  late int projectId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('avc_tr_');
    db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
        factory: databaseFactoryFfi);
    projectId = (await ProjectRepository(db.db).create('P')).id!;
    final video = await VideoRepository(db.db).insert(VideoRecord(
      projectId: projectId,
      filePath: '/v.mp4',
      fileName: 'v.mp4',
      durationMs: 10000,
      createdAt: DateTime(2026),
    ));
    repo = TranscriptRepository(db.db);
    await repo.save(
      Transcript(
          projectId: projectId, videoId: video.id!, language: 'ko', createdAt: DateTime(2026)),
      const [
        TranscriptSegment(startMs: 0, endMs: 1000, text: '안녕하세요'),
        TranscriptSegment(startMs: 1000, endMs: 2000, text: 'kosong'),
      ],
    );
    tr = _Translator();
    svc = TranslationService(translator: tr, transcripts: repo);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('menerjemahkan: text = terjemahan, source_text = asli', () async {
    expect(await svc.needsTranslation(projectId, 'id'), isTrue);
    final n = await svc.translateProject(
        projectId: projectId, source: 'ko', target: 'id');
    expect(n, 2);
    expect(tr.closed, isTrue);

    final t = (await repo.getByProject(projectId))!;
    expect(t.translatedLang, 'id');
    final segs = await repo.getSegments(t.id!);
    expect(segs[0].text, '[id] 안녕하세요');
    expect(segs[0].sourceText, '안녕하세요');
    // hasil kosong -> teks asli dipertahankan
    expect(segs[1].text, 'kosong');
    expect(await svc.needsTranslation(projectId, 'id'), isFalse);
  });

  test('diterjemahkan ulang selalu dari teks asli (tidak bertumpuk)', () async {
    await svc.translateProject(projectId: projectId, source: 'ko', target: 'id');
    await svc.translateProject(projectId: projectId, source: 'ko', target: 'en');
    final t = (await repo.getByProject(projectId))!;
    final segs = await repo.getSegments(t.id!);
    expect(segs[0].text, '[en] 안녕하세요');
    expect(segs[0].sourceText, '안녕하세요');
  });

  test('gagal unduh model -> transcript tidak berubah', () async {
    tr.failEnsure =
        const AppException('Model terjemahan belum bisa diunduh.', code: 'x');
    await expectLater(
      svc.translateProject(projectId: projectId, source: 'ko', target: 'id'),
      throwsA(isA<AppException>()),
    );
    final t = (await repo.getByProject(projectId))!;
    expect(t.translatedLang, isNull);
    expect((await repo.getSegments(t.id!))[0].text, '안녕하세요');
  });

  test('dibatalkan -> tidak ada yang disimpan', () async {
    final c = CancelToken()..cancel();
    await expectLater(
      svc.translateProject(
          projectId: projectId, source: 'ko', target: 'id', cancel: c),
      throwsA(isA<TranscriptionCancelled>()),
    );
    expect((await repo.getByProject(projectId))!.translatedLang, isNull);
  });

  test('bahasa tidak didukung ditolak dengan pesan ramah', () async {
    await expectLater(
      svc.translateProject(projectId: projectId, source: 'xx', target: 'id'),
      throwsA(isA<AppException>()),
    );
  });
}
