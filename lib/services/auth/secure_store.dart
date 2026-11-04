import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/app_logger.dart';

/// Penyimpanan rahasia (token). Di Android memakai Android Keystore lewat
/// flutter_secure_storage; satu-satunya file yang mengimpor package itu.
/// Diabstraksikan agar mudah di-fake saat testing.
abstract class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, st) {
      // Data tidak dapat didekripsi (mis. kunci Keystore berubah setelah
      // restore perangkat): anggap kosong, pengguna cukup masuk lagi.
      AppLogger.e('Membaca secure storage gagal', e, st);
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Hanya untuk test.
class MemorySecureStore implements SecureStore {
  final Map<String, String> data = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('write gagal');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}
