import 'package:sqflite/sqflite.dart';

/// Satu langkah perubahan skema database.
///
/// Aturan:
/// - `version` harus berurutan (1, 2, 3, ...).
/// - Migrasi yang sudah dirilis TIDAK boleh diubah; tambahkan migrasi baru.
/// - Gunakan `ALTER TABLE` / tabel baru, jangan `DROP TABLE` data project.
abstract class Migration {
  const Migration();

  int get version;

  Future<void> up(Database db);
}
