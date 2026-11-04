import 'package:sqflite/sqflite.dart';

import '../models/model_utils.dart';

/// Key-value pengaturan lokal. Jangan simpan token/password di sini.
class AppSettingsRepository {
  const AppSettingsRepository(this._db);

  final Database _db;

  Future<String?> get(String key) async {
    final rows = await _db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value'] as String?;
  }

  Future<int?> getInt(String key) async {
    final v = await get(key);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> set(String key, String value) async {
    await _db.insert(
      'app_settings',
      {
        'setting_key': key,
        'setting_value': value,
        'updated_at': toEpochMs(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String?>> getAll() async {
    final rows = await _db.query('app_settings');
    return {
      for (final r in rows)
        r['setting_key'] as String: r['setting_value'] as String?,
    };
  }

  Future<void> remove(String key) => _db
      .delete('app_settings', where: 'setting_key = ?', whereArgs: [key]);
}
