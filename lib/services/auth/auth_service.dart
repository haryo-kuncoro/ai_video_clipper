import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../remote/api_client.dart';
import 'auth_models.dart';
import 'secure_store.dart';

enum AuthStatus {
  /// Belum dibaca dari penyimpanan.
  unknown,
  signedOut,
  signedIn,
}

/// Akun bersifat OPSIONAL: semua fitur lokal berjalan tanpa login. Layanan ini
/// hanya mengelola sesi akun (token disimpan di Android Keystore), tidak
/// mengirim video/project/clip/transcript.
class AuthService extends ChangeNotifier {
  AuthService({
    required ApiClient? api,
    required SecureStore store,
    DateTime Function()? clock,
    this.refreshMargin = const Duration(seconds: 60),
    this.deviceName = 'Android',
  })  : _api = api,
        _store = store,
        _clock = clock ?? DateTime.now;

  static const sessionKey = 'auth_session';

  final ApiClient? _api;
  final SecureStore _store;
  final DateTime Function() _clock;
  final Duration refreshMargin;
  final String deviceName;

  AuthStatus _status = AuthStatus.unknown;
  AuthSession? _session;
  bool _busy = false;
  Future<String>? _refreshing;

  AuthStatus get status => _status;
  AuthUser? get user => _session?.user;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get busy => _busy;

  /// false bila backend tidak dikonfigurasi (API_BASE_URL kosong).
  bool get available => _api != null;

  /// Membaca sesi tersimpan. Offline tetap dianggap masuk; sesi yang sudah
  /// kedaluwarsa dibersihkan. Tidak pernah melempar error.
  Future<void> restore() async {
    AuthSession? s;
    try {
      s = AuthSession.decode(await _store.read(sessionKey));
    } catch (e, st) {
      AppLogger.e('Membaca sesi gagal', e, st);
    }
    if (s != null && !s.refreshExpiresAt.isAfter(_clock())) {
      s = null;
      await _safeDelete();
    }
    _session = s;
    _status = s == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    notifyListeners();

    if (s != null && _api != null) {
      unawaited(_validate());
    }
  }

  /// Memastikan akun masih valid di server (token dicabut/akun dihapus).
  /// Kegagalan jaringan diabaikan: sesi lokal dipertahankan.
  Future<void> _validate() async {
    try {
      final token = await accessToken();
      final res = await _api!.get('api/v1/auth/me', bearer: token);
      final u = AuthUser.fromJson((res.json?['data'] as Map?)?['user']);
      if (u != null && _session != null) {
        _session = _session!.copyWith(user: u);
        await _persist();
        notifyListeners();
      }
    } on ApiException catch (e) {
      if (e.isAuthRejection && _session != null) await _clear();
    } catch (e, st) {
      AppLogger.e('Validasi sesi gagal', e, st);
    }
  }

  Future<void> register({
    required String email,
    required String name,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    final cleanName = name.trim();
    _validateEmail(cleanEmail);
    if (cleanName.isEmpty) {
      throw const AppException('Nama wajib diisi.', code: 'invalid_name');
    }
    _validatePassword(password);
    await _authenticate('api/v1/auth/register', {
      'email': cleanEmail,
      'name': cleanName,
      'password': password,
      'device_name': deviceName,
    });
  }

  Future<void> login({required String email, required String password}) async {
    final cleanEmail = email.trim();
    _validateEmail(cleanEmail);
    if (password.isEmpty) {
      throw const AppException('Kata sandi wajib diisi.', code: 'invalid_password');
    }
    await _authenticate('api/v1/auth/login', {
      'email': cleanEmail,
      'password': password,
      'device_name': deviceName,
    });
  }

  /// Keluar. Sesi lokal SELALU dihapus walau server tidak terjangkau.
  Future<void> logout() async {
    final api = _api;
    final s = _session;
    if (api != null && s != null) {
      try {
        await api.post('api/v1/auth/logout', bearer: s.accessToken);
      } catch (_) {
        // Server tidak terjangkau/token sudah mati: tidak masalah.
      }
    }
    await _clear();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword.isEmpty) {
      throw const AppException('Kata sandi saat ini wajib diisi.', code: 'invalid_password');
    }
    _validatePassword(newPassword);
    await _guarded(() async {
      final token = await accessToken();
      await _requireApi().post('api/v1/auth/change-password', body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      }, bearer: token);
    });
  }

  /// Menghapus akun di server lalu membersihkan sesi lokal. Data lokal
  /// (video, project, clip) TIDAK disentuh.
  Future<void> deleteAccount({required String password}) async {
    if (password.isEmpty) {
      throw const AppException('Kata sandi wajib diisi.', code: 'invalid_password');
    }
    await _guarded(() async {
      final token = await accessToken();
      await _requireApi().post('api/v1/auth/delete-account',
          body: {'password': password}, bearer: token);
    });
    await _clear();
  }

  /// Access token yang pasti masih berlaku. Memperbarui lewat refresh token
  /// bila hampir habis; beberapa pemanggil bersamaan berbagi satu refresh.
  Future<String> accessToken() {
    final s = _session;
    if (s == null) {
      return Future.error(const AppException(
          'Silakan masuk terlebih dahulu.', code: 'not_signed_in'));
    }
    if (s.accessExpiresAt.isAfter(_clock().add(refreshMargin))) {
      return Future.value(s.accessToken);
    }
    return _refreshing ??= _refresh(s).whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh(AuthSession old) async {
    if (!old.refreshExpiresAt.isAfter(_clock())) {
      await _clear();
      throw const AppException('Sesi berakhir. Silakan masuk lagi.', code: 'session_expired');
    }
    try {
      final res = await _requireApi()
          .post('api/v1/auth/refresh', body: {'refresh_token': old.refreshToken});
      final fresh = AuthSession.fromJson(res.json?['data']);
      if (fresh == null) {
        throw const ApiException('Balasan server tidak dikenali.', code: 'bad_response');
      }
      _session = fresh;
      await _persist();
      notifyListeners();
      return fresh.accessToken;
    } on ApiException catch (e) {
      if (e.isAuthRejection) {
        await _clear();
        throw const AppException('Sesi berakhir. Silakan masuk lagi.', code: 'session_expired');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------

  Future<void> _authenticate(String path, Map<String, Object?> body) async {
    await _guarded(() async {
      final res = await _requireApi().post(path, body: body);
      final s = AuthSession.fromJson(res.json?['data']);
      if (s == null) {
        throw const ApiException('Balasan server tidak dikenali.', code: 'bad_response');
      }
      _session = s;
      _status = AuthStatus.signedIn;
      await _persist(throwOnFail: true);
    });
    notifyListeners();
  }

  /// Menandai sibuk dan memastikan error tak terduga menjadi pesan ramah.
  Future<void> _guarded(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } on AppException {
      rethrow;
    } catch (e, st) {
      AppLogger.e('Operasi akun gagal', e, st);
      throw const AppException('Terjadi kesalahan. Coba lagi.', code: 'unexpected');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  ApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const AppException('Server belum dikonfigurasi pada aplikasi ini.',
          code: 'backend_disabled');
    }
    return api;
  }

  Future<void> _persist({bool throwOnFail = false}) async {
    final s = _session;
    if (s == null) return;
    try {
      await _store.write(sessionKey, s.encode());
    } catch (e, st) {
      AppLogger.e('Menyimpan sesi gagal', e, st);
      if (throwOnFail) {
        // Tanpa penyimpanan aman, sesi tidak boleh dipakai (token tidak disimpan di tempat tak aman).
        _session = null;
        _status = AuthStatus.signedOut;
        throw const AppException(
          'Sesi tidak dapat disimpan dengan aman di perangkat ini.',
          code: 'secure_storage_failed',
        );
      }
    }
  }

  Future<void> _clear() async {
    _session = null;
    _status = AuthStatus.signedOut;
    await _safeDelete();
    notifyListeners();
  }

  Future<void> _safeDelete() async {
    try {
      await _store.delete(sessionKey);
    } catch (e, st) {
      AppLogger.e('Menghapus sesi gagal', e, st);
    }
  }

  static void _validateEmail(String email) {
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) && email.length <= 190;
    if (!ok) throw const AppException('Format email tidak valid.', code: 'invalid_email');
  }

  static void _validatePassword(String password) {
    if (password.length < 8) {
      throw const AppException('Kata sandi minimal 8 karakter.', code: 'weak_password');
    }
    // Server menolak > 72 byte; cek di sini agar pesannya langsung jelas.
    if (utf8.encode(password).length > 72) {
      throw const AppException('Kata sandi maksimal 72 karakter.', code: 'weak_password');
    }
  }
}
