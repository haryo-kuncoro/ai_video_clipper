import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/clip.dart' as models;
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/clip_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:ai_video_clipper/features/projects/projects_controller.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late AppPaths paths;
  late AppDatabase db;
  late ProjectsController controller;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('avc_proj_');
    final root = await Directory(p.join(tmp.path, 'app')).create();
    paths = await AppPaths.fromBase(root);
    db = await AppDatabase.openAt(
      p.join(tmp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
    controller = ProjectsController(db.db, paths);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('create: nama di-trim, folder project dibuat, muncul di daftar',
      () async {
    final project = await controller.create('  Podcast 01  ');
    expect(project.name, 'Podcast 01');
    expect(paths.projectClipsDir(project.id!).existsSync(), isTrue);
    expect(paths.projectTempDir(project.id!).existsSync(), isTrue);
    expect(controller.items.map((s) => s.project.name), ['Podcast 01']);
  });

  test('create: nama kosong ditolak', () async {
    expect(() => controller.create('   '), throwsA(isA<AppException>()));
  });

  test('rename mengubah nama dan memindahkan project ke paling atas',
      () async {
    final a = await controller.create('A');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller.create('B');
    expect(controller.items.first.project.name, 'B');

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller.rename(a.id!, 'A baru');
    expect(controller.items.first.project.name, 'A baru');
  });

  test('summary memuat jumlah clip dan durasi video sumber', () async {
    final project = await controller.create('P');
    final now = DateTime.now();
    await VideoRepository(db.db).insert(VideoRecord(
      projectId: project.id!,
      filePath: p.join(paths.videos.path, 'a.mp4'),
      fileName: 'a.mp4',
      durationMs: 23 * 60 * 1000,
      createdAt: now,
    ));
    final clips = ClipRepository(db.db);
    for (var i = 0; i < 2; i++) {
      await clips.insert(models.Clip(
        projectId: project.id!,
        startMs: 0,
        endMs: 1000,
        title: 'c$i',
        createdAt: now,
      ));
    }

    await controller.load();
    final s = controller.items.single;
    expect(s.clipCount, 2);
    expect(s.sourceDurationMs, 23 * 60 * 1000);
  });

  test('hapus project: salinan & clip & temp terhapus, video asli aman',
      () async {
    final project = await controller.create('P');
    final pid = project.id!;
    final now = DateTime.now();

    final copied = File(p.join(paths.projectDir(pid).path, 'source.mp4'))
      ..writeAsStringSync('x');
    final clipFile = File(p.join(paths.projectClipsDir(pid).path, 'c1.mp4'))
      ..writeAsStringSync('x');
    final tempFile = File(p.join(paths.projectTempDir(pid).path, 'a.tmp'))
      ..writeAsStringSync('x');
    // Video asli milik pengguna (di luar folder aplikasi).
    final original = File(p.join(tmp.path, 'DCIM_asli.mp4'))
      ..writeAsStringSync('x');
    // Data salah catat: ditandai "copied" tetapi berada di luar folder app.
    final misplaced = File(p.join(tmp.path, 'luar.mp4'))
      ..writeAsStringSync('x');

    final videos = VideoRepository(db.db);
    await videos.insert(VideoRecord(
      projectId: pid,
      filePath: copied.path,
      fileName: 'source.mp4',
      createdAt: now,
    ));
    await videos.insert(VideoRecord(
      projectId: pid,
      filePath: original.path,
      fileName: 'DCIM_asli.mp4',
      sourceType: VideoSourceType.reference,
      createdAt: now,
    ));
    await videos.insert(VideoRecord(
      projectId: pid,
      filePath: misplaced.path,
      fileName: 'luar.mp4',
      createdAt: now,
    ));
    await ClipRepository(db.db).insert(models.Clip(
      projectId: pid,
      filePath: clipFile.path,
      startMs: 0,
      endMs: 1000,
      title: 'c1',
      createdAt: now,
    ));

    final result = await controller.delete(pid);

    expect(copied.existsSync(), isFalse);
    expect(clipFile.existsSync(), isFalse);
    expect(tempFile.existsSync(), isFalse);
    expect(paths.projectDir(pid).existsSync(), isFalse);
    expect(original.existsSync(), isTrue);
    expect(misplaced.existsSync(), isTrue);
    expect(controller.items, isEmpty);
    expect(result.filesKept, 2);
    expect(result.filesFailed, 0);
  });
}
