import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// STEP 16 (ekspor): riwayat file yang sudah disalin ke galeri/Downloads.
/// Hanya metadata (nama + URI); file asli tidak pernah dihapus oleh ekspor.
class MigrationV5 extends Migration {
  const MigrationV5();

  @override
  int get version => 5;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE exports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        display_name TEXT NOT NULL,
        uri TEXT NOT NULL,
        exported_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_exports_clip ON exports(clip_id)');
  }
}
