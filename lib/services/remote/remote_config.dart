import 'dart:convert';

int? _int(Object? v) => v is num && v.isFinite ? v.toInt() : null;

/// Info rilis dari server.
class RemoteVersionInfo {
  const RemoteVersionInfo({
    required this.latestVersion,
    required this.latestVersionCode,
    this.minSupportedCode = 0,
    this.updateAvailable = false,
    this.forceUpdate = false,
    this.downloadUrl,
    this.releaseNotes,
  });

  final String latestVersion;
  final int latestVersionCode;
  final int minSupportedCode;
  final bool updateAvailable;
  final bool forceUpdate;
  final String? downloadUrl;
  final String? releaseNotes;

  static RemoteVersionInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['latest_version'];
    final code = _int(raw['latest_version_code']);
    if (name is! String || code == null) return null;
    return RemoteVersionInfo(
      latestVersion: name,
      latestVersionCode: code,
      minSupportedCode: _int(raw['min_supported_code']) ?? 0,
      updateAvailable: raw['update_available'] == true,
      forceUpdate: raw['force_update'] == true,
      downloadUrl: raw['download_url'] is String ? raw['download_url'] as String : null,
      releaseNotes: raw['release_notes'] is String ? raw['release_notes'] as String : null,
    );
  }

  Map<String, Object?> toJson() => {
        'latest_version': latestVersion,
        'latest_version_code': latestVersionCode,
        'min_supported_code': minSupportedCode,
        'update_available': updateAvailable,
        'force_update': forceUpdate,
        'download_url': downloadUrl,
        'release_notes': releaseNotes,
      };
}

/// Konfigurasi global dari server. Hanya TAMBAHAN: setiap getter menerima
/// nilai fallback lokal sehingga aplikasi tetap berjalan tanpa server.
class RemoteConfig {
  const RemoteConfig({
    this.settings = const {},
    this.features = const {},
    this.version,
    this.maintenanceEnabled = false,
    this.maintenanceMessage = '',
    this.fetchedAt,
  });

  static const empty = RemoteConfig();

  final Map<String, Object?> settings;
  final Map<String, bool> features;
  final RemoteVersionInfo? version;
  final bool maintenanceEnabled;
  final String maintenanceMessage;
  final DateTime? fetchedAt;

  int intSetting(String key, int fallback) {
    final v = settings[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  double doubleSetting(String key, double fallback) {
    final v = settings[key];
    return v is num ? v.toDouble() : fallback;
  }

  bool boolSetting(String key, bool fallback) {
    final v = settings[key];
    return v is bool ? v : fallback;
  }

  String stringSetting(String key, String fallback) {
    final v = settings[key];
    return v is String ? v : fallback;
  }

  /// Flag tidak dikenal server -> pakai [fallback] (default: aktif).
  bool feature(String name, {bool fallback = true}) => features[name] ?? fallback;

  RemoteConfig copyWith({DateTime? fetchedAt}) => RemoteConfig(
        settings: settings,
        features: features,
        version: version,
        maintenanceEnabled: maintenanceEnabled,
        maintenanceMessage: maintenanceMessage,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );

  /// Membaca bagian `data` dari respons server. Toleran terhadap field
  /// yang hilang atau bertipe salah.
  static RemoteConfig fromData(Object? data, {DateTime? fetchedAt}) {
    if (data is! Map) return RemoteConfig(fetchedAt: fetchedAt);
    final settings = <String, Object?>{};
    final rawSettings = data['settings'];
    if (rawSettings is Map) {
      rawSettings.forEach((k, v) {
        if (k is String) settings[k] = v;
      });
    }
    final features = <String, bool>{};
    final rawFeatures = data['features'];
    if (rawFeatures is Map) {
      rawFeatures.forEach((k, v) {
        if (k is String && v is bool) features[k] = v;
      });
    }
    var maintenanceEnabled = false;
    var maintenanceMessage = '';
    final m = data['maintenance'];
    if (m is Map) {
      maintenanceEnabled = m['enabled'] == true;
      maintenanceMessage = m['message'] is String ? m['message'] as String : '';
    }
    return RemoteConfig(
      settings: settings,
      features: features,
      version: RemoteVersionInfo.fromJson(data['version']),
      maintenanceEnabled: maintenanceEnabled,
      maintenanceMessage: maintenanceMessage,
      fetchedAt: fetchedAt,
    );
  }

  String encode() => jsonEncode({
        'settings': settings,
        'features': features,
        'version': version?.toJson(),
        'maintenance': {
          'enabled': maintenanceEnabled,
          'message': maintenanceMessage,
        },
        'fetched_at': fetchedAt?.millisecondsSinceEpoch,
      });

  /// Kebalikan [encode]; data cache rusak -> [empty].
  static RemoteConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return empty;
      final at = j['fetched_at'];
      return fromData(
        j,
        fetchedAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      );
    } on FormatException {
      return empty;
    }
  }
}
