import 'package:sqflite/sqflite.dart';

import '../../services/subtitle/subtitle_style.dart';
import '../models/model_utils.dart';

/// Pengaturan subtitle di SQLite.
///
/// - Baris dengan `project_id` = id project: pengaturan project itu.
/// - Baris dengan `project_id` NULL: default global (dipakai project yang
///   belum punya pengaturan sendiri).
/// - Tidak ada baris sama sekali: preset Classic.
class SubtitleSettingsRepository {
  const SubtitleSettingsRepository(this._db);

  final Database _db;

  Future<SubtitleStyle> getForProject(int projectId) async {
    final rows = await _db.query(
      'subtitle_settings',
      where: 'project_id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isNotEmpty) return SubtitleStyle.fromMap(rows.first);
    return getDefault();
  }

  Future<SubtitleStyle> getDefault() async {
    final rows = await _db.query(
      'subtitle_settings',
      where: 'project_id IS NULL',
      limit: 1,
    );
    if (rows.isNotEmpty) return SubtitleStyle.fromMap(rows.first);
    return SubtitlePresets.style(SubtitlePreset.classic);
  }

  Future<void> saveForProject(int projectId, SubtitleStyle style) =>
      _upsert(projectId, style);

  Future<void> saveDefault(SubtitleStyle style) => _upsert(null, style);

  Future<void> _upsert(int? projectId, SubtitleStyle style) {
    final values = <String, Object?>{
      ...style.toMap(),
      'project_id': projectId,
      'updated_at': toEpochMs(DateTime.now()),
    };

    return _db.transaction((txn) async {
      final updated = projectId == null
          ? await txn.update('subtitle_settings', values,
              where: 'project_id IS NULL')
          : await txn.update('subtitle_settings', values,
              where: 'project_id = ?', whereArgs: [projectId]);
      if (updated == 0) {
        await txn.insert('subtitle_settings', values);
      }
    });
  }
}
