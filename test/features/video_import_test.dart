import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/models/project.dart';
import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/video_repository.dart';
import 'package:ai_video_clipper/features/projects/projects_controller.dart';
import 'package:ai_video_clipper/features/video/media_probe.dart';
import 'package:ai_video_clipper/features/video/video_import_service.dart';
import 'package:ai_video_clipper/features/video/video_picker.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakePicker implements VideoPicker {
  FakePicker(this.result);

  PickedVideo? result;

  @override
  Future<PickedVideo?> pick() async => result;
}

class FakeProbe implements MediaProbe {
  FakeProbe({this.free = 1 << 40, this.failProbe = false});

  int free;
  bool failProbe;

  @override
  Future<VideoMetadata> probe(String path) async {
    if (failProbe) {
      throw const AppException(
        'Video tidak valid atau format tidak didukung.',
        code: 'invalid_video',
      );
    }
    return const VideoMetadata(
      durationMs: 1380000,
      width: 1920,
      height: 1080,
      hasAudio: true,
    );
  }

  @override
  Future<bool> generateThumbnail({
    required String videoPath,
    required String outputPath,
    required int positionMs,
    int maxWidth = 480,
  }) async {
    File(outputPath).writeAsBytesSync([1, 2, 3]);
    return true;
  }

  @override
  Future<int> freeSpaceBytes(String path) async => free;
}

void main() {
  late Directory tmp;
  late Directory cacheDir;
  late AppPaths paths;
  late AppDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('avc_import_');
    final root = await Directory(p.join(tmp.path, 'app')).create();
    cacheDir = await Directory(p.join(tmp.path, 'cache')).create();
    paths = await AppPaths.fromBase(root);
    db = await AppDatabase.openAt(
      p.join(tmp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProjectsController build(FakePicker picker, FakeProbe probe) {
    return ProjectsController(
      db.db,
      paths,
      importService: VideoImportService(
        db: db.db,
        paths: paths,
        picker: picker,
        probe: probe,
        pickerCacheDir: cacheDir,
      ),
    );
  }

  File makeFile(String dir, String name, [int size = 1000]) {
    final f = File(p.join(dir, name));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(size, 7));
    return f;
  }

  test('import dari cache picker: file dipindah, metadata & thumbnail tersimpan',
      () async {
    final cached = makeFile(p.join(cacheDir.path, 'file_picker'), 'clip.MP4');
    final controller = build(
      FakePicker(PickedVideo(path: cached.path, name: 'Podcast.MP4', sizeBytes: 1000)),
      FakeProbe(),
    );
    final project = await controller.create('P');

    final result = await controller.importVideo(project.id!);

    expect(result, isNotNull);
    expect(result!.hasAudio, isTrue);
    expect(cached.existsSync(), isFalse);

    final video = result.video;
    expect(video.sourceType, VideoSourceType.copied);
    expect(video.isManagedCopy, isTrue);
    expect(video.fileName, 'Podcast.MP4');
    expect(video.filePath.endsWith('source.mp4'), isTrue);
    expect(p.isWithin(paths.projectDir(project.id!).path, video.filePath), isTrue);
    expect(File(video.filePath).existsSync(), isTrue);
    expect(video.durationMs, 1380000);
    expect(video.width, 1920);
    expect(video.height, 1080);
    expect(video.fileSize, 1000);
    expect(File(video.thumbnailPath!).existsSync(), isTrue);

    final saved = await ProjectRepository(db.db).getById(project.id!);
    expect(saved!.status, ProjectStatus.videoAdded);
    expect(saved.sourceVideoId, video.id);
    expect(controller.items.single.sourceDurationMs, 1380000);
  });

  test('sumber di luar cache (file asli pengguna) hanya disalin, tidak dihapus',
      () async {
    final original = makeFile(tmp.path, 'asli.mp4');
    final controller = build(
      FakePicker(PickedVideo(path: original.path, name: 'asli.mp4', sizeBytes: 1000)),
      FakeProbe(),
    );
    final project = await controller.create('P');

    final result = await controller.importVideo(project.id!);

    expect(original.existsSync(), isTrue);
    expect(File(result!.video.filePath).existsSync(), isTrue);
    expect(result.video.filePath == original.path, isFalse);
  });

  test('video tidak valid: file & baris dibersihkan, status project tetap',
      () async {
    final cached = makeFile(cacheDir.path, 'bad.mp4');
    final controller = build(
      FakePicker(PickedVideo(path: cached.path, name: 'bad.mp4', sizeBytes: 1000)),
      FakeProbe(failProbe: true),
    );
    final project = await controller.create('P');

    await expectLater(
      controller.importVideo(project.id!),
      throwsA(isA<AppException>()),
    );

    final dest = File(p.join(paths.projectDir(project.id!).path, 'source.mp4'));
    expect(dest.existsSync(), isFalse);
    expect(await VideoRepository(db.db).getByProject(project.id!), isEmpty);
    final saved = await ProjectRepository(db.db).getById(project.id!);
    expect(saved!.status, ProjectStatus.created);
    expect(saved.sourceVideoId, isNull);
  });

  test('storage tidak cukup: ditolak, tidak ada salinan, sumber utuh',
      () async {
    final original = makeFile(tmp.path, 'besar.mp4');
    final controller = build(
      FakePicker(PickedVideo(path: original.path, name: 'besar.mp4', sizeBytes: 1000)),
      FakeProbe(free: 10),
    );
    final project = await controller.create('P');

    await expectLater(
      controller.importVideo(project.id!),
      throwsA(isA<InsufficientStorageException>()),
    );

    final dest = File(p.join(paths.projectDir(project.id!).path, 'source.mp4'));
    expect(dest.existsSync(), isFalse);
    expect(original.existsSync(), isTrue);
  });

  test('pengguna membatalkan: tidak ada perubahan', () async {
    final controller = build(FakePicker(null), FakeProbe());
    final project = await controller.create('P');

    final result = await controller.importVideo(project.id!);

    expect(result, isNull);
    final saved = await ProjectRepository(db.db).getById(project.id!);
    expect(saved!.status, ProjectStatus.created);
    expect(await VideoRepository(db.db).getByProject(project.id!), isEmpty);
  });
}
