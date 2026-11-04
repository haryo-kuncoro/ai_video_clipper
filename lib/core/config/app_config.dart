/// Konfigurasi aplikasi yang bersifat lokal (fallback default).
///
/// Nilai ini nanti dapat ditimpa oleh global settings dari server CI4
/// (STEP 20), tetapi aplikasi HARUS tetap berjalan memakai nilai lokal ini
/// bila server tidak dapat diakses.
class AppConfig {
  AppConfig._();

  /// Aplikasi bekerja local-first: tidak ada upload video/project/clip.
  static const bool localFirst = true;

  static const int defaultClipDurationSeconds = 45;
  static const int maxClipCount = 10;
  static const int defaultOutputWidth = 1080;
  static const int defaultOutputHeight = 1920;
  static const int fallbackOutputWidth = 720;
  static const int fallbackOutputHeight = 1280;

  /// Base URL backend CI4. Kosong = backend nonaktif dan aplikasi memakai
  /// nilai lokal di atas sepenuhnya. Diisi saat build:
  ///   flutter run --dart-define=API_BASE_URL=https://api.domain-anda.com
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
}
