import 'package:sqflite/sqflite.dart';

import '../models/export_record.dart';

class ExportRepository {
  const ExportRepository(this._db);

  final Database _db;

  Future<int> insert(ExportRecord r) => _db.insert('exports', r.toMap());

  Future<List<ExportRecord>> getByClip(int clipId) async {
    final rows = await _db.query('exports',
        where: 'clip_id = ?', whereArgs: [clipId], orderBy: 'id DESC');
    return rows.map(ExportRecord.fromMap).toList();
  }

  /// Ekspor terakhir tiap jenis untuk semua clip milik [projectId].
  Future<List<ExportRecord>> getByProject(int projectId) async {
    final rows = await _db.rawQuery('''
      SELECT e.* FROM exports e
      JOIN clips c ON c.id = e.clip_id
      WHERE c.project_id = ?
      ORDER BY e.id DESC
    ''', [projectId]);
    return rows.map(ExportRecord.fromMap).toList();
  }
}
