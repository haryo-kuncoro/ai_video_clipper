import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/repositories/app_settings_repository.dart';
import 'api_client.dart';
import 'remote_config.dart';

enum RemoteStatus {
  /// Backend tidak dikonfigurasi (API_BASE_URL kosong): sepenuhnya lokal.
  disabled,
  idle,
  loading,
  online,
  offlineCached,
  offlineNoData,
}

/// Mengambil konfigurasi global dari server CI4 secara OFFLINE-FIRST:
/// cache terakhir selalu tersedia, kegagalan jaringan tidak pernah
/// melempar error ke UI, dan aplikasi tetap berjalan dengan nilai lokal.
class RemoteConfigService extends ChangeNotifier {
  RemoteConfigService({
    required ApiClient? api,
    required AppSettingsRepository store,
    required this.appBuild,
    this.minInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _api = api,
        _store = store,
        _clock = clock ?? DateTime.now,
        _status = api == null ? RemoteStatus.disabled : RemoteStatus.idle;

  static const cacheKey = 'remote_config_json';
  static const etagKey = 'remote_config_etag';

  final ApiClient? _api;
  final AppSettingsRepository _store;
  final DateTime Function() _clock;
  final int appBuild;
  final Duration minInterval;

  RemoteConfig _config = RemoteConfig.empty;
  RemoteStatus _status;
  String? _lastError;
  Future<void>? _cacheFuture;
  bool _refreshing = false;

  RemoteConfig get config => _config;
  RemoteStatus get status => _status;

  /// Pesan ramah dari kegagalan terakhir (null bila tidak ada).
  String? get lastError => _lastError;

  bool get enabled => _api != null;

  /// Membaca cache lokal. Dipanggil otomatis oleh [refresh].
  Future<void> loadCache() => _cacheFuture ??= _readCache();

  Future<void> _readCache() async {
    try {
      _config = RemoteConfig.decode(await _store.get(cacheKey));
    } catch (e, st) {
      AppLogger.e('Membaca cache konfigurasi gagal', e, st);
      _config = RemoteConfig.empty;
    }
    notifyListeners();
  }

  /// Mengambil konfigurasi terbaru. Tidak pernah melempar error.
  /// [force] mengabaikan batas interval minimum.
  Future<void> refresh({bool force = false}) async {
    final api = _api;
    if (api == null) return;
    await loadCache();
    if (_refreshing) return;

    final last = _config.fetchedAt;
    if (!force &&
        last != null &&
        _status != RemoteStatus.offlineCached &&
        _clock().difference(last) < minInterval) {
      _status = RemoteStatus.online;
      notifyListeners();
      return;
    }

    _refreshing = true;
    _status = RemoteStatus.loading;
    _lastError = null;
    notifyListeners();

    try {
      final etag = _config.fetchedAt == null ? null : await _store.get(etagKey);
      final res = await api.get(
        'api/v1/app/config',
        query: {'version_code': '$appBuild'},
        ifNoneMatch: etag,
      );
      final now = _clock();
      if (res.notModified) {
        _config = _config.copyWith(fetchedAt: now);
      } else {
        final data = res.json?['data'];
        if (data is! Map) {
          throw const ApiException('Balasan server tidak dikenali.',
              code: 'bad_response');
        }
        _config = RemoteConfig.fromData(data, fetchedAt: now);
      }
      await _persist(res.etag);
      _status = RemoteStatus.online;
    } on AppException catch (e) {
      _lastError = e.message;
      _status = _hasCache ? RemoteStatus.offlineCached : RemoteStatus.offlineNoData;
    } catch (e, st) {
      AppLogger.e('Refresh konfigurasi gagal', e, st);
      _lastError = 'Konfigurasi server tidak dapat dimuat.';
      _status = _hasCache ? RemoteStatus.offlineCached : RemoteStatus.offlineNoData;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  bool get _hasCache => _config.fetchedAt != null;

  Future<void> _persist(String? etag) async {
    try {
      await _store.set(cacheKey, _config.encode());
      if (etag != null) await _store.set(etagKey, etag);
    } catch (e, st) {
      // Gagal menyimpan cache tidak boleh mengganggu aplikasi.
      AppLogger.e('Menyimpan cache konfigurasi gagal', e, st);
    }
  }
}
