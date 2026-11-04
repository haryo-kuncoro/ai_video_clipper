import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/clip.dart';
import 'package:ai_video_clipper/database/models/export_record.dart';
import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/clip_repository.dart';
import 'package:ai_video_clipper/database/repositories/export_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/transcript_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:ai_video_clipper/services/export/export_service.dart';
import 'package:ai_video_clipper/services/export/gallery_exporter.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeExporter implements GalleryExporter {
  final List<Map<String, Object?>> calls = [];
  final List<String> shared = [];
  final Map<String, String> contents = {};
  Object? failWith;
  bool Function(String name)? failFor;

  @override
  Future<ExportedFile> exportFile({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    required ExportTarget target,
  }) async {
    if (failFor?.call(displayName) ?? false) {
      throw const AppException('Clip gagal disimpan ke galeri.',
          code: 'export_failed');
    }
    if (failWith != null) throw failWith!;
    calls.add({'name': displayName, 'mime': mimeType, 'target': target});
    contents[displayName] = File(sourcePath).readAsStringSync();
    return ExportedFile(uri: 'content://media/$displayName', displayName: displayName);
  }

  @override
  Future<void> share({required String uri, required String mimeType}) async {
    shared.add(uri);
  }
}

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late AppPaths paths;
  late AppDatabase db;
  late _FakeExporter fake;
  late ExportService service;
  late ClipRepository clipRepo;
  late int projectId;

  Future<Clip> addClip(String title,
      {int start = 10000,
      int end = 40000,
      ClipStatus status = ClipStatus.completed,
      bool withFile = true}) async {
    final file = File(p.join(tmp.path, '${title.hashCode}.mp4'));
    if (withFile) file.writeAsStringSync('mp4-$title');
    final id = await clipRepo.insert(Clip(
      projectId: projectId,
      filePath: withFile ? file.path : null,
      startMs: start,
      endMs: end,
      durationMs: end - start,
      width: 720,
      height: 1280,
      title: title,
      status: status,
      createdAt: DateTime.now(),
    ));
    return (await clipRepo.getById(id))!;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('avc_export_');
    final root = await Directory(p.join(tmp.path, 'app')).create();
    paths = await AppPaths.fromBase(root);
    db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
        factory: databaseFactoryFfi);
    projectId = (await ProjectRepository(db.db).create('P')).id!;
    await VideoRepository(db.db).insert(VideoRecord(
      projectId: projectId,
      filePath: '/x.mp4',
      fileName: 'x.mp4',
      width: 1920,
      height: 1080,
      durationMs: 100000,
      createdAt: DateTime.now(),
    ));
    clipRepo = ClipRepository(db.db);
    fake = _FakeExporter();
    service = ExportService(
      exporter: fake,
      exports: ExportRepository(db.db),
      transcripts: TranscriptRepository(db.db),
      paths: paths,
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('nama file', () {
    test('karakter terlarang dibersihkan, id ditambahkan', () {
      expect(safeExportName('Bisnis: "Rahasia"/Sukses?', 7, 'mp4'),
          'Bisnis Rahasia Sukses #7.mp4');
      expect(safeExportName('   ', 3, 'srt'), 'clip #3.srt');
      expect(safeExportName('a' * 100, 1, 'mp4').length, lessThanOrEqualTo(60 + 7));
    });
  });

  group('buildClipSrt', () {
    const segs = [
      TranscriptSegment(startMs: 0, endMs: 9000, text: 'sebelum clip'),
      TranscriptSegment(startMs: 8000, endMs: 14000, text: 'memotong awal'),
      TranscriptSegment(startMs: 20000, endMs: 25000, text: 'di dalam'),
      TranscriptSegment(startMs: 38000, endMs: 45000, text: 'memotong akhir'),
      TranscriptSegment(startMs: 50000, endMs: 55000, text: 'sesudah'),
    ];

    test('waktu relatif terhadap awal clip dan dipotong', () {
      final srt = buildClipSrt(segs, 10000, 40000);
      expect(srt, contains('1\n00:00:00,000 --> 00:00:04,000\nmemotong awal'));
      expect(srt, contains('2\n00:00:10,000 --> 00:00:15,000\ndi dalam'));
      expect(srt, contains('3\n00:00:28,000 --> 00:00:30,000\nmemotong akhir'));
      expect(srt, isNot(contains('sebelum clip')));
      expect(srt, isNot(contains('sesudah')));
    });

    test('tanpa segmen -> kosong', () {
      expect(buildClipSrt(const [], 0, 1000), isEmpty);
    });
  });

  group('exportClipVideo', () {
    test('menyalin file dan mencatat riwayat', () async {
      final c = await addClip('Judul Satu');
      final r = await service.exportClipVideo(c);
      expect(fake.calls.single['name'], 'Judul Satu #${c.id}.mp4');
      expect(fake.calls.single['mime'], 'video/mp4');
      expect(fake.calls.single['target'], ExportTarget.video);
      expect(r.id, isNotNull);
      final hist = await service.history(projectId);
      expect(hist.single.kind, ExportKind.video);
      expect(hist.single.uri, startsWith('content://'));
      expect(File(c.filePath!).existsSync(), isTrue); // file asli utuh
    });

    test('clip belum selesai / file hilang ditolak', () async {
      final pending = await addClip('Belum', status: ClipStatus.pending);
      await expectLater(service.exportClipVideo(pending),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'file_missing')));
      final noFile = await addClip('Hilang', withFile: false);
      await expectLater(service.exportClipVideo(noFile), throwsA(isA<AppException>()));
      final c = await addClip('Dihapus');
      File(c.filePath!).deleteSync();
      await expectLater(service.exportClipVideo(c), throwsA(isA<AppException>()));
      expect(fake.calls, isEmpty);
      expect(await service.history(projectId), isEmpty);
    });

    test('kegagalan exporter tidak mencatat riwayat', () async {
      final c = await addClip('Gagal');
      fake.failWith = const AppException('x', code: 'export_failed');
      await expectLater(service.exportClipVideo(c), throwsA(isA<AppException>()));
      expect(await service.history(projectId), isEmpty);
    });
  });

  group('exportClips', () {
    test('semua sukses dengan progres berurutan', () async {
      final a = await addClip('A');
      final b = await addClip('B');
      final progress = <int>[];
      final s = await service.exportClips([a, b],
          onProgress: (p) => progress.add(p.done));
      expect(s.allOk, isTrue);
      expect(s.exported.length, 2);
      expect(progress.first, 0);
      expect(progress.last, 2);
      expect(service.isRunning, isFalse);
    });

    test('satu gagal tidak menghentikan yang lain', () async {
      final a = await addClip('A');
      final b = await addClip('B');
      final c = await addClip('C');
      fake.failFor = (n) => n.startsWith('B ');
      final s = await service.exportClips([a, b, c]);
      expect(s.exported.length, 2);
      expect(s.failures.single.clip.title, 'B');
      expect(s.failures.single.message, isNotEmpty);
    });

    test('izin ditolak menghentikan batch lebih awal', () async {
      final a = await addClip('A');
      final b = await addClip('B');
      fake.failWith = const AppException('izin', code: 'permission_denied');
      final s = await service.exportClips([a, b]);
      expect(s.failures.length, 1);
      expect(s.exported, isEmpty);
    });

    test('dibatalkan sebelum mulai -> tidak ada yang diekspor', () async {
      final a = await addClip('A');
      final flag = CancelFlag()..cancel();
      final s = await service.exportClips([a], cancel: flag);
      expect(s.exported, isEmpty);
      expect(fake.calls, isEmpty);
    });

    test('dibatalkan di tengah batch', () async {
      final a = await addClip('A');
      final b = await addClip('B');
      final flag = CancelFlag();
      final s = await service.exportClips([a, b], cancel: flag, onProgress: (p) {
        if (p.done == 1) flag.cancel();
      });
      expect(s.exported.length, 1);
    });

    test('ekspor bersamaan ditolak (busy)', () async {
      final a = await addClip('A');
      final first = service.exportClips([a]);
      await expectLater(service.exportClips([a]),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'busy')));
      await first;
      expect(service.isRunning, isFalse);
    });
  });

  group('exportClipSrt', () {
    Future<void> addTranscript(List<TranscriptSegment> segs) async {
      final videos = await VideoRepository(db.db).getByProject(projectId);
      await TranscriptRepository(db.db).replaceForProject(
        Transcript(
            projectId: projectId,
            videoId: videos.first.id!,
            createdAt: DateTime.now()),
        segs,
      );
    }

    test('membuat SRT relatif dan membersihkan file sementara', () async {
      final c = await addClip('Clip SRT');
      await addTranscript(const [
        TranscriptSegment(startMs: 12000, endMs: 16000, text: 'Halo dunia'),
      ]);
      final r = await service.exportClipSrt(c);
      expect(r.kind, ExportKind.srt);
      expect(fake.calls.single['mime'], 'application/x-subrip');
      expect(fake.calls.single['target'], ExportTarget.download);
      expect(fake.contents.values.single,
          contains('00:00:02,000 --> 00:00:06,000\nHalo dunia'));
      expect(paths.temp.listSync(), isEmpty);
    });

    test('tanpa transcript -> pesan jelas, tidak ada ekspor', () async {
      final c = await addClip('Tanpa');
      await expectLater(service.exportClipSrt(c),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'no_transcript')));
      expect(fake.calls, isEmpty);
    });

    test('exporter gagal -> file sementara tetap dibersihkan', () async {
      final c = await addClip('Gagal SRT');
      await addTranscript(const [
        TranscriptSegment(startMs: 12000, endMs: 16000, text: 'x'),
      ]);
      fake.failWith = const AppException('x', code: 'export_failed');
      await expectLater(service.exportClipSrt(c), throwsA(isA<AppException>()));
      expect(paths.temp.listSync(), isEmpty);
    });
  });

  group('shareClip', () {
    test('belum pernah diekspor -> ekspor dulu lalu bagikan', () async {
      final c = await addClip('Share');
      await service.shareClip(c);
      expect(fake.calls.length, 1);
      expect(fake.shared.single, contains('Share #${c.id}.mp4'));
    });

    test('sudah diekspor dan clip tidak berubah -> tidak ekspor ulang', () async {
      final c = await addClip('Share2');
      await service.exportClipVideo(c);
      File(c.filePath!)
          .setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      await service.shareClip(c);
      expect(fake.calls.length, 1);
      expect(fake.shared.length, 1);
    });

    test('clip diedit setelah ekspor -> ekspor ulang', () async {
      final c = await addClip('Share3');
      await service.exportClipVideo(c);
      File(c.filePath!)
          .setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
      await service.shareClip(c);
      expect(fake.calls.length, 2);
    });
  });

  test('riwayat ekspor ikut terhapus saat clip dihapus (cascade)', () async {
    final c = await addClip('Cascade');
    await service.exportClipVideo(c);
    await clipRepo.delete(c.id!);
    expect(await service.history(projectId), isEmpty);
  });

  test('ExportRecord round-trip', () {
    final r = ExportRecord(
      id: 1,
      clipId: 2,
      kind: ExportKind.srt,
      displayName: 'a.srt',
      uri: 'content://x',
      exportedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final back = ExportRecord.fromMap(r.toMap());
    expect(back.kind, ExportKind.srt);
    expect(back.uri, 'content://x');
    expect(back.exportedAt.millisecondsSinceEpoch, 1000);
    expect(
        ExportRecord.fromMap({...r.toMap(), 'kind': 'aneh'}).kind, ExportKind.video);
  });
}
