import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';

/// Lokasi folder lokal aplikasi (app-specific storage).
///
/// Di Android, `getExternalStorageDirectory()` mengarah ke
/// `/Android/data/<package>/files` yang kompatibel dengan Scoped Storage
/// dan tidak memerlukan izin storage. Bila tidak tersedia, dipakai
/// application documents directory.
///
/// File video TIDAK pernah disimpan di SQLite; database hanya menyimpan path.
class AppPaths {
  const AppPaths({
    required this.root,
    required this.videos,
    required this.projects,
    required this.clips,
    required this.thumbnails,
    required this.temp,
  });

  final Directory root;
  final Directory videos;
  final Directory projects;
  final Directory clips;
  final Directory thumbnails;
  final Directory temp;

  /// Membuat struktur folder di bawah [baseDir] (dipakai juga oleh test).
  static Future<AppPaths> fromBase(Directory baseDir) async {
    try {
      Future<Directory> make(String name) =>
          Directory('${baseDir.path}/$name').create(recursive: true);

      final results = await Future.wait([
        make(AppConstants.dirVideos),
        make(AppConstants.dirProjects),
        make(AppConstants.dirClips),
        make(AppConstants.dirThumbnails),
        make(AppConstants.dirTemp),
      ]);
      return AppPaths(
        root: baseDir,
        videos: results[0],
        projects: results[1],
        clips: results[2],
        thumbnails: results[3],
        temp: results[4],
      );
    } on FileSystemException catch (e) {
      throw StorageException(
        'Penyimpanan lokal tidak dapat disiapkan.',
        code: 'storage_init_failed',
        cause: e,
      );
    }
  }

  static Future<AppPaths> init() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (e) {
      AppLogger.d('External storage tidak tersedia: $e');
    }
    base ??= await getApplicationDocumentsDirectory();
    AppLogger.i('Root storage: ${base.path}');
    return fromBase(base);
  }

  /// Folder khusus satu project: `<root>/projects/<id>`.
  Directory projectDir(int projectId) =>
      Directory('${projects.path}/$projectId');

  /// Folder clip hasil render satu project.
  Directory projectClipsDir(int projectId) =>
      Directory('${projectDir(projectId).path}/clips');

  /// Folder file sementara khusus satu project.
  Directory projectTempDir(int projectId) =>
      Directory('${projectDir(projectId).path}/temp');

  /// Membuat folder project (beserta clips/ dan temp/) bila belum ada.
  Future<Directory> ensureProjectDir(int projectId) async {
    await projectClipsDir(projectId).create(recursive: true);
    await projectTempDir(projectId).create(recursive: true);
    return projectDir(projectId);
  }
}
