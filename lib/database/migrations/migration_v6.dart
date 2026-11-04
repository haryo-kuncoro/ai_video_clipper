import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Terjemahan transcript: teks asli disimpan di `source_text`, sedangkan
/// `text` berisi teks yang dipakai subtitle dan deteksi clip (terjemahan).
class MigrationV6 extends Migration {
  const MigrationV6();

  @override
  int get version => 6;

  @override
  Future<void> up(Database db) async {
    await db.execute('ALTER TABLE transcript_segments ADD COLUMN source_text TEXT');
    await db.execute('ALTER TABLE transcripts ADD COLUMN translated_lang TEXT');
  }
}
