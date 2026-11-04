import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Melengkapi `subtitle_settings` (STEP 8): huruf tebal, huruf kapital, dan
/// warna teks/outline. Murni additive (ALTER TABLE ADD COLUMN dengan default),
/// jadi data lama aman.
class MigrationV3 extends Migration {
  const MigrationV3();

  @override
  int get version => 3;

  @override
  Future<void> up(Database db) async {
    await db.execute(
        'ALTER TABLE subtitle_settings ADD COLUMN bold INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE subtitle_settings ADD COLUMN uppercase INTEGER NOT NULL DEFAULT 0');
    // ARGB: 4294967295 = 0xFFFFFFFF (putih), 4278190080 = 0xFF000000 (hitam).
    await db.execute(
        'ALTER TABLE subtitle_settings ADD COLUMN text_color INTEGER NOT NULL DEFAULT 4294967295');
    await db.execute(
        'ALTER TABLE subtitle_settings ADD COLUMN outline_color INTEGER NOT NULL DEFAULT 4278190080');
  }
}
