import 'package:sqflite/sqflite.dart';

import '../models/clip_edit.dart';

class ClipEditRepository {
  const ClipEditRepository(this._db);

  final Database _db;

  Future<ClipEdit?> get(int clipId) async {
    final rows = await _db.query('clip_edits',
        where: 'clip_id = ?', whereArgs: [clipId], limit: 1);
    return rows.isEmpty ? null : ClipEdit.fromMap(rows.first);
  }

  Future<void> save(ClipEdit edit) => _db.insert(
        'clip_edits',
        edit.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
