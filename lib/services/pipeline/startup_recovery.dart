import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/app_logger.dart';
import '../../database/repositories/processing_job_repository.dart';
import '../../database/repositories/project_repository.dart';
import '../storage/app_paths.dart';

class RecoveryReport {
  const RecoveryReport({
    this.interruptedJobs = 0,
    this.resetProjects = 0,
    this.removedTempFiles = 0,
  });

  final int interruptedJobs;
  final int resetProjects;
  final int removedTempFiles;

  bool get didAnything =>
      interruptedJobs > 0 || resetProjects > 0 || removedTempFiles > 0;
}

/// STEP 17: dijalankan sekali saat aplikasi dibuka. Pekerjaan yang terputus
/// (app ditutup/crash/dimatikan sistem) ditandai gagal dengan pesan jelas,
/// status project dikembalikan ke status stabil, dan file sementara sisa
/// proses dibersihkan. File video asli dan clip hasil render TIDAK disentuh.
class StartupRecovery {
  StartupRecovery({
    required this.jobs,
    required this.projects,
    this.paths,
  });

  final ProcessingJobRepository jobs;
  final ProjectRepository projects;
  final AppPaths? paths;

  Future<RecoveryReport> run() async {
    var interrupted = 0;
    var reset = 0;
    var removed = 0;
    try {
      interrupted = await jobs.failInterrupted();
      reset = await projects.resetTransientStatuses();
    } catch (e, st) {
      AppLogger.e('Pemulihan database gagal', e, st);
    }
    final ap = paths;
    if (ap != null) {
      try {
        removed = await _cleanTemp(ap);
      } catch (e, st) {
        AppLogger.e('Pembersihan file sementara gagal', e, st);
      }
    }
    final report = RecoveryReport(
      interruptedJobs: interrupted,
      resetProjects: reset,
      removedTempFiles: removed,
    );
    if (report.didAnything) {
      AppLogger.i('Pemulihan: $interrupted job terputus, $reset project '
          'direset, $removed file sementara dihapus');
    }
    return report;
  }

  Future<int> _cleanTemp(AppPaths ap) async {
    var count = 0;

    Future<void> clearDir(Directory dir) async {
      if (!await dir.exists()) return;
      await for (final e in dir.list(followLinks: false)) {
        if (!p.isWithin(ap.root.path, e.path)) continue;
        try {
          await e.delete(recursive: true);
          count++;
        } on FileSystemException {
          // Diabaikan; dicoba lagi pada peluncuran berikutnya.
        }
      }
    }

    await clearDir(ap.temp);

    if (await ap.projects.exists()) {
      await for (final project in ap.projects.list(followLinks: false)) {
        if (project is! Directory) continue;
        await clearDir(Directory(p.join(project.path, 'temp')));
        // Sisa render ulang yang belum sempat menggantikan clip lama.
        final clipsDir = Directory(p.join(project.path, 'clips'));
        if (!await clipsDir.exists()) continue;
        await for (final f in clipsDir.list(followLinks: false)) {
          if (f is File && RegExp(r'^clip_\d+_edit\.mp4$').hasMatch(p.basename(f.path))) {
            try {
              await f.delete();
              count++;
            } on FileSystemException {
              // Diabaikan.
            }
          }
        }
      }
    }
    return count;
  }
}
