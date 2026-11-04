import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/utils/app_logger.dart';
import '../../database/repositories/clip_repository.dart';
import '../../database/repositories/project_repository.dart';
import '../../database/repositories/video_repository.dart';
import '../../services/storage/app_paths.dart';

class ProjectDeletionResult {
  const ProjectDeletionResult({
    this.filesDeleted = 0,
    this.filesFailed = 0,
    this.filesKept = 0,
  });

  final int filesDeleted;

  /// File yang gagal dihapus (baris database tetap dihapus; sisa file akan
  /// terdeteksi sebagai orphan oleh StorageManager nanti).
  final int filesFailed;

  /// File yang sengaja TIDAK dihapus (video asli milik pengguna, atau path
  /// di luar folder aplikasi).
  final int filesKept;
}

enum _Outcome { deleted, missing, kept, failed }

/// Menghapus project beserta file-nya dengan aman.
///
/// Urutan: clip -> thumbnail -> salinan video terkelola -> folder project
/// (temp, dll) -> baris database (transcript, kandidat, job ikut terhapus via
/// ON DELETE CASCADE).
///
/// PENGAMAN: file hanya dihapus bila berada DI DALAM folder aplikasi, dan
/// video bertipe `reference` (file asli milik pengguna) TIDAK pernah dihapus.
class ProjectDeletionService {
  ProjectDeletionService(Database db, this._paths)
      : _projects = ProjectRepository(db),
        _videos = VideoRepository(db),
        _clips = ClipRepository(db);

  final AppPaths _paths;
  final ProjectRepository _projects;
  final VideoRepository _videos;
  final ClipRepository _clips;

  Future<ProjectDeletionResult> delete(int projectId) async {
    final videos = await _videos.getByProject(projectId);
    final clips = await _clips.getByProject(projectId);

    final targets = <String>{};
    var keptOriginals = 0;

    for (final c in clips) {
      if (c.filePath != null) targets.add(c.filePath!);
      if (c.thumbnailPath != null) targets.add(c.thumbnailPath!);
    }
    for (final v in videos) {
      if (v.thumbnailPath != null) targets.add(v.thumbnailPath!);
      if (v.isManagedCopy) {
        targets.add(v.filePath);
      } else {
        keptOriginals++; // file asli pengguna: jangan disentuh
      }
    }

    var deleted = 0;
    var failed = 0;
    var kept = keptOriginals;

    for (final path in targets) {
      switch (await _deleteFile(path)) {
        case _Outcome.deleted:
          deleted++;
        case _Outcome.kept:
          kept++;
        case _Outcome.failed:
          failed++;
        case _Outcome.missing:
          break;
      }
    }

    // Folder project (clips/, temp/, sisa file sementara).
    try {
      final dir = _paths.projectDir(projectId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      AppLogger.e('Gagal menghapus folder project $projectId', e);
      failed++;
    }

    await _projects.delete(projectId);

    return ProjectDeletionResult(
      filesDeleted: deleted,
      filesFailed: failed,
      filesKept: kept,
    );
  }

  Future<_Outcome> _deleteFile(String path) async {
    if (!p.isWithin(_paths.root.path, path)) {
      AppLogger.i('Dilewati (di luar folder aplikasi): $path');
      return _Outcome.kept;
    }
    try {
      final file = File(path);
      if (!await file.exists()) return _Outcome.missing;
      await file.delete();
      return _Outcome.deleted;
    } on FileSystemException catch (e) {
      AppLogger.e('Gagal menghapus file $path', e);
      return _Outcome.failed;
    }
  }
}
