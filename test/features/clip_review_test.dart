import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/clip_candidate.dart';
import 'package:ai_video_clipper/database/repositories/clip_candidate_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/features/clips/clip_range.dart';
import 'package:ai_video_clipper/features/clips/clip_review_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('normalizeRange & formatPreciseMs', () {
    test('menjaga rentang dalam durasi video', () {
      final r = normalizeRange(startMs: -500, endMs: 99999, videoDurationMs: 40000);
      expect(r.startMs, 0);
      expect(r.endMs, 40000);
    });

    test('menolak terlalu pendek dan terlalu panjang', () {
      expect(
        () => normalizeRange(startMs: 0, endMs: 2999, videoDurationMs: 100000),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'clip_too_short')),
      );
      expect(
        () => normalizeRange(startMs: 0, endMs: 180001, videoDurationMs: 500000),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'clip_too_long')),
      );
      expect(normalizeRange(startMs: 0, endMs: 3000, videoDurationMs: 0).endMs, 3000);
    });

    test('formatPreciseMs', () {
      expect(formatPreciseMs(0), '00:00.0');
      expect(formatPreciseMs(65400), '01:05.4');
      expect(formatPreciseMs(3661900), '1:01:01.9');
    });
  });

  group('ClipReviewController', () {
    late Directory tmp;
    late AppDatabase db;
    late ClipCandidateRepository repo;
    late ClipReviewController controller;
    late int projectId;

    setUpAll(() {
      sqfliteFfiInit();
    });

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('avc_review_');
      db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
          factory: databaseFactoryFfi);
      projectId = (await ProjectRepository(db.db).create('P')).id!;
      repo = ClipCandidateRepository(db.db);
      final now = DateTime.now();
      await repo.insertAll([
        for (var i = 0; i < 3; i++)
          ClipCandidate(
            projectId: projectId,
            startMs: i * 60000,
            endMs: i * 60000 + 30000,
            title: 'Clip $i',
            score: 0.9 - i * 0.1,
            createdAt: now,
          ),
      ]);
      controller = ClipReviewController(
        repository: repo,
        projectId: projectId,
        videoDurationMs: 200000,
      );
      await controller.load();
    });

    tearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('daftar urut skor tertinggi, semua pending', () {
      expect(controller.items.map((c) => c.title), ['Clip 0', 'Clip 1', 'Clip 2']);
      expect(controller.pendingCount, 3);
    });

    test('terima, tolak, dan toggle kembali ke pending', () async {
      final c = controller.items[0];
      await controller.setStatus(c, CandidateStatus.accepted);
      expect(controller.acceptedCount, 1);

      await controller.setStatus(controller.items[0], CandidateStatus.accepted);
      expect(controller.acceptedCount, 0);
      expect(controller.pendingCount, 3);

      await controller.setStatus(controller.items[1], CandidateStatus.rejected);
      expect(controller.rejectedCount, 1);
    });

    test('setAll tidak mengubah kandidat generated', () async {
      await repo.updateStatus(controller.items[2].id!, CandidateStatus.generated);
      await controller.load();
      await controller.setAll(CandidateStatus.accepted);
      expect(controller.acceptedCount, 2);
      expect(
        controller.items.where((c) => c.status == CandidateStatus.generated).length,
        1,
      );

      final gen = controller.items
          .firstWhere((c) => c.status == CandidateStatus.generated);
      await controller.setStatus(gen, CandidateStatus.rejected);
      expect(controller.rejectedCount, 0);
    });

    test('saveEdit menyimpan judul dan waktu', () async {
      final c = controller.items[0];
      await controller.saveEdit(c,
          startMs: 1000, endMs: 41000, title: '  Judul Baru  ');
      final after = controller.items.firstWhere((x) => x.id == c.id);
      expect(after.title, 'Judul Baru');
      expect(after.startMs, 1000);
      expect(after.endMs, 41000);
    });

    test('saveEdit menolak input tidak valid dan data tetap utuh', () async {
      final c = controller.items[0];
      await expectLater(
        controller.saveEdit(c, startMs: 0, endMs: 1000, title: 'x'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        controller.saveEdit(c, startMs: 0, endMs: 30000, title: '   '),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'empty_title')),
      );
      final same = controller.items.firstWhere((x) => x.id == c.id);
      expect(same.title, 'Clip 0');
      expect(same.endMs, 30000);
    });
  });
}
