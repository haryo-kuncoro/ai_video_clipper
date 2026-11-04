import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// STEP 15 (clip editor): pengaturan edit per clip. Tabel baru (additive),
/// data lama tidak tersentuh. Baris ikut terhapus bila clip dihapus.
class MigrationV4 extends Migration {
  const MigrationV4();

  @override
  int get version => 4;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE clip_edits (
        clip_id INTEGER PRIMARY KEY
          REFERENCES clips(id) ON DELETE CASCADE,
        crop_mode TEXT NOT NULL DEFAULT 'face',
        focus_x REAL,
        focus_y REAL,
        zoom REAL NOT NULL DEFAULT 1.0,
        burn_subtitles INTEGER NOT NULL DEFAULT 1,
        style_json TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
  }
}
