class AppConstants {
  AppConstants._();

  static const appName = 'AI CLIPPER';
  static const appVersion = '0.20.0';

  /// Nomor build (angka setelah + di pubspec.yaml); dikirim ke server.
  static const appBuild = 20;

  // Nama folder lokal (di dalam app-specific storage).
  static const dirVideos = 'videos';
  static const dirProjects = 'projects';
  static const dirClips = 'clips';
  static const dirThumbnails = 'thumbnails';
  static const dirTemp = 'temp';

  // Kunci SharedPreferences.
  static const prefThemeMode = 'theme_mode';
}
