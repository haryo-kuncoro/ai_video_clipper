import 'migration.dart';
import 'migration_v1.dart';
import 'migration_v2.dart';
import 'migration_v3.dart';
import 'migration_v4.dart';
import 'migration_v5.dart';

/// Daftar semua migrasi, berurutan. Tambahkan migrasi baru di akhir.
const List<Migration> allMigrations = [
  MigrationV1(),
  MigrationV2(),
  MigrationV3(),
  MigrationV4(),
  MigrationV5(),
];
