import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/project_summary.dart';
import 'projects_controller.dart';
import 'widgets/project_dialogs.dart';

/// Alur hapus: konfirmasi -> hapus -> snackbar. True bila project terhapus.
Future<bool> deleteProjectFlow(
  BuildContext context,
  ProjectsController controller,
  ProjectSummary summary,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await confirmDeleteProject(context, summary.project.name);
  if (!confirmed) return false;

  try {
    await controller.delete(summary.project.id!);
    messenger.showSnackBar(const SnackBar(content: Text('Project dihapus.')));
    return true;
  } on AppException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (e, st) {
    AppLogger.e('Hapus project gagal', e, st);
    messenger
        .showSnackBar(const SnackBar(content: Text('Project gagal dihapus.')));
    return false;
  }
}

/// Alur ganti nama. True bila nama berubah.
Future<bool> renameProjectFlow(
  BuildContext context,
  ProjectsController controller,
  ProjectSummary summary,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final newName = await promptRenameProject(context, summary.project.name);
  if (newName == null || newName == summary.project.name) return false;

  try {
    await controller.rename(summary.project.id!, newName);
    return true;
  } on AppException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (e, st) {
    AppLogger.e('Ganti nama gagal', e, st);
    messenger.showSnackBar(
        const SnackBar(content: Text('Nama project gagal diubah.')));
    return false;
  }
}
