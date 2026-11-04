import 'package:sqflite/sqflite.dart';

import '../models/clip.dart';

class ClipRepository {
  const ClipRepository(this._db);

  final Database _db;

  Future<int> insert(Clip clip) => _db.insert('clips', clip.toMap());

  Future<List<Clip>> getByProject(int projectId) async {
    final rows = await _db.query(
      'clips',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(Clip.fromMap).toList();
  }

  Future<Clip?> getById(int id) async {
    final rows =
        await _db.query('clips', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Clip.fromMap(rows.first);
  }

  Future<void> updateStatus(int id, ClipStatus status) => _patch(id, {
        'status': status.name,
      });

  /// Dipanggil setelah render selesai.
  Future<void> markCompleted(
    int id, {
    required String filePath,
    String? thumbnailPath,
    required int durationMs,
    required int width,
    required int height,
  }) =>
      _patch(id, {
        'status': ClipStatus.completed.name,
        'file_path': filePath,
        'thumbnail_path': thumbnailPath,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
      });

  /// Dipanggil setelah clip diedit dan dirender ulang.
  Future<void> markEdited(
    int id, {
    required String title,
    required int startMs,
    required int endMs,
    String? thumbnailPath,
    required int width,
    required int height,
  }) =>
      _patch(id, {
        'title': title,
        'start_ms': startMs,
        'end_ms': endMs,
        'duration_ms': endMs - startMs,
        'width': width,
        'height': height,
        if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      });

  Future<void> delete(int id) =>
      _db.delete('clips', where: 'id = ?', whereArgs: [id]);

  Future<void> _patch(int id, Map<String, Object?> values) async {
    await _db.update('clips', values, where: 'id = ?', whereArgs: [id]);
  }
}
