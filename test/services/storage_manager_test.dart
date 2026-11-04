import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/clip.dart';
import 'package:ai_video_clipper/database/repositories/clip_repository.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/features/video/media_probe.dart';
import 'package:ai_video_clipper/services/settings/app_settings.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';
import 'package:ai_video_clipper/services/storage/storage_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Probe implements MediaProbe {
  int free = 10 * 1024 * 1024 * 1024;

  @override
  Future<VideoMetadata> probe(String path) => throw UnimplementedError();

  @override
  Future<bool> generateThumbnail({
    required String videoPath,
    required String outputPath,
    required int positionMs,
    int maxWidth = 480,
  }) async =>
      false;

  @override
  Future<int> freeSpaceBytes(String path) async => free;
}

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late AppPaths paths;
  late AppDatabase db;
  late _Probe probe;
  late StorageManager mgr;
  late int projectId;
  var busy = false;

  File write(String path, int bytes) {
    final f = File(path)..createSync(recursive: true);
    f.writeAsBytesSync(List.filled(bytes, 1));
    return f;
  }

  setUp(() async {
    busy = false;
    tmp = Directory.systemTemp.createTempSync('avc_storage_');
    paths = await AppPaths.fromBase(await Directory(p.join(tmp.path, 'app')).create());
    db = await AppDatabase.openAt(p.join(tmp.path, 't.db'), factory: databaseFactoryFfi);
    projectId = (await ProjectRepository(db.db).create('P')).id!;
    probe = _Probe();
    mgr = StorageManager(
      paths: paths,
      db: db.db,
      probe: probe,
      isBusy: () => busy,
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> addClip(String file, {String? thumb}) async {
    await ClipRepository(db.db).insert(Clip(
      projectId: projectId,
      filePath: file,
      thumbnailPath: thumb,
      startMs: 0,
      endMs: 30000,
      durationMs: 30000,
      width: 720,
      height: 1280,
      title: 'c',
      status: ClipStatus.completed,
      createdAt: DateTime.now(),
    ));
  }

  test('usage menghitung per kategori tanpa menghitung ganda', () async {
    write(p.join(paths.videos.path, 'a.mp4'), 1000);
    write(p.join(paths.projectClipsDir(projectId).path, 'clip_1.mp4'), 400);
    write(p.join(paths.projectTempDir(projectId).path, 't.tmp'), 50);
    write(p.join(paths.temp.path, 'x.tmp'), 30);
    write(p.join(paths.thumbnails.path, 'clip_1.jpg'), 20);
    write(p.join(mgr.modelsDir.path, 'm.onnx'), 700);

    final u = await mgr.usage();
    expect(u.videos, 1000);
    expect(u.clips, 400);
    expect(u.temp, 80);
    expect(u.thumbnails, 20);
    expect(u.models, 700);
    expect(u.total, 2200);
    expect(u.freeBytes, probe.free);
    expect(u.lowSpace, isFalse);
  });

  test('lowSpace mengikuti min_free_storage_mb', () async {
    probe.free = 100 * 1024 * 1024;
    final low = StorageManager(
      paths: paths,
      db: db.db,
      probe: probe,
      settings: () => const AppSettings(minFreeStorageMb: 500),
    );
    expect((await low.usage()).lowSpace, isTrue);
    probe.free = 2 * 1024 * 1024 * 1024;
    expect((await low.usage()).lowSpace, isFalse);
  });

  test('cleanTemp hanya mengosongkan folder sementara', () async {
    final video = write(p.join(paths.videos.path, 'a.mp4'), 10);
    final clip = write(p.join(paths.projectClipsDir(projectId).path, 'clip_1.mp4'), 10);
    final t1 = write(p.join(paths.temp.path, 'x.tmp'), 30);
    final t2 = write(p.join(paths.projectTempDir(projectId).path, 'sub', 'y.tmp'), 50);

    final freed = await mgr.cleanTemp();
    expect(freed, 80);
    expect(t1.existsSync(), isFalse);
    expect(t2.existsSync(), isFalse);
    expect(video.existsSync(), isTrue);
    expect(clip.existsSync(), isTrue);
    expect(paths.temp.existsSync(), isTrue);
  });

  test('orphan: hanya file clip/thumbnail yang tidak dirujuk DB', () async {
    final dir = paths.projectClipsDir(projectId).path;
    final keep = write(p.join(dir, 'clip_1.mp4'), 10);
    final orphan = write(p.join(dir, 'clip_2.mp4'), 20);
    final edit = write(p.join(dir, 'clip_1_edit.mp4'), 5);
    final other = write(p.join(dir, 'catatan.txt'), 5); // bukan buatan app
    final keepThumb = write(p.join(paths.thumbnails.path, 'clip_1.jpg'), 3);
    final orphanThumb = write(p.join(paths.thumbnails.path, 'clip_9.jpg'), 4);
    final ghost = write(p.join(paths.projectClipsDir(999).path, 'clip_7.mp4'), 6);
    final video = write(p.join(paths.videos.path, 'sumber.mp4'), 99);
    await addClip(keep.path, thumb: keepThumb.path);

    final report = await mgr.findOrphans();
    // normalize: Windows mencampur '/' dan '\\' pada path.
    expect(report.paths.map(p.normalize).toSet(),
        {orphan.path, edit.path, orphanThumb.path, ghost.path}.map(p.normalize).toSet());
    expect(report.bytes, 20 + 5 + 4 + 6);

    final freed = await mgr.deleteOrphans();
    expect(freed, 35);
    expect(keep.existsSync(), isTrue);
    expect(keepThumb.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
    expect(video.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
    expect((await mgr.findOrphans()).count, 0);
  });

  test('pembersihan ditolak saat pemrosesan berjalan', () async {
    busy = true;
    expect(mgr.cleanTemp(), throwsA(isA<AppException>()));
    expect(mgr.deleteOrphans(), throwsA(isA<AppException>()));
  });

  test('folder kosong / belum ada tidak error', () async {
    final u = await mgr.usage();
    expect(u.total, 0);
    expect((await mgr.findOrphans()).count, 0);
    expect(await mgr.cleanTemp(), 0);
  });
}
