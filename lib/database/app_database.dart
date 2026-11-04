import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/app_logger.dart';
import 'migrations/migration.dart';
import 'migrations/migrations.dart';

class DatabaseInfo {
  const DatabaseInfo({required this.version, required this.tables});

  final int version;
  final List<String> tables;
}

/// Pembungkus database SQLite lokal (satu koneksi untuk seluruh aplikasi).
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;
  final String path;

  static const fileName = 'ai_video_clipper.db';

  /// Membuka database di lokasi default (penyimpanan internal privat aplikasi).
  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    return openAt(p.join(dir, fileName));
  }

  /// Membuka database di [path]. [factory] dan [migrations] dapat diganti
  /// untuk testing (mis. sqflite_common_ffi).
  static Future<AppDatabase> openAt(
    String path, {
    DatabaseFactory? factory,
    List<Migration>? migrations,
  }) async {
    final list = List<Migration>.of(migrations ?? allMigrations)
      ..sort((a, b) => a.version.compareTo(b.version));
    if (list.isEmpty) {
      throw const StorageException('Tidak ada migrasi database.');
    }
    final targetVersion = list.last.version;
    final f = factory ?? databaseFactory;

    try {
      final db = await f.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: targetVersion,
          onConfigure: (db) async {
            // Wajib agar ON DELETE CASCADE berfungsi.
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            for (final m in list.where((m) => m.version <= version)) {
              AppLogger.i('DB create: migrasi v${m.version}');
              await m.up(db);
            }
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            for (final m in list.where(
                (m) => m.version > oldVersion && m.version <= newVersion)) {
              AppLogger.i('DB upgrade: migrasi v${m.version}');
              await m.up(db);
            }
          },
          onDowngrade: (db, oldVersion, newVersion) async {
            throw StorageException(
              'Database dibuat oleh versi aplikasi yang lebih baru.',
              code: 'db_downgrade',
              cause: 'v$oldVersion -> v$newVersion',
            );
          },
        ),
      );
      return AppDatabase._(db, path);
    } on AppException {
      rethrow;
    } catch (e, st) {
      AppLogger.e('Gagal membuka database', e, st);
      throw StorageException(
        'Database lokal tidak dapat dibuka.',
        code: 'db_open_failed',
        cause: e,
      );
    }
  }

  Future<DatabaseInfo> info() async {
    final version = await db.getVersion();
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name <> 'android_metadata' "
      'ORDER BY name',
    );
    return DatabaseInfo(
      version: version,
      tables: rows.map((r) => r['name'] as String).toList(),
    );
  }

  Future<void> close() => db.close();
}
