import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Menambah tabel yang sudah direncanakan: `subtitle_settings` (STEP 8)
/// dan `users_local` (STEP 19). Murni additive; data project lama aman.
///
/// Catatan keamanan: token login TIDAK disimpan di tabel ini
/// (akan memakai secure storage Android).
class MigrationV2 extends Migration {
  const MigrationV2();

  @override
  int get version => 2;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE subtitle_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER
          REFERENCES projects(id) ON DELETE CASCADE,
        preset TEXT NOT NULL DEFAULT 'classic',
        font_family TEXT,
        font_size INTEGER NOT NULL DEFAULT 48,
        position TEXT NOT NULL DEFAULT 'bottom',
        outline_width REAL NOT NULL DEFAULT 2,
        shadow INTEGER NOT NULL DEFAULT 0,
        background INTEGER NOT NULL DEFAULT 0,
        max_chars_per_line INTEGER NOT NULL DEFAULT 28,
        enabled INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_subtitle_project ON subtitle_settings(project_id)
    ''');

    await db.execute('''
      CREATE TABLE users_local (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_user_id INTEGER,
        email TEXT,
        display_name TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
  }
}
