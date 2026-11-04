import '../ai/clip_detector.dart';
import '../ffmpeg/portrait_plan.dart';
import '../remote/remote_config.dart';

/// Pengaturan efektif aplikasi, diturunkan dari konfigurasi global server
/// (STEP 18-20) dengan fallback lokal. Nilai dari server TIDAK dipercaya:
/// semuanya dibatasi (clamp) ke rentang aman, sehingga salah ketik di panel
/// admin tidak dapat merusak aplikasi. Tanpa server, [defaults] dipakai.
class AppSettings {
  const AppSettings({
    this.clipDurationSeconds = 45,
    this.maxClipCount = 10,
    this.outputWidth = 1080,
    this.outputHeight = 1920,
    this.minFreeStorageMb = 500,
    this.autoPipelineEnabled = true,
    this.faceAwareCropEnabled = true,
    this.exportSrtEnabled = true,
  });

  static const defaults = AppSettings();

  static const minClipSeconds = 15;
  static const maxClipSeconds = 180;
  static const minClipCount = 1;
  static const maxClipCountLimit = 20;
  static const minFreeFloorMb = 100;
  static const minFreeCeilingMb = 10000;

  final int clipDurationSeconds;
  final int maxClipCount;
  final int outputWidth;
  final int outputHeight;
  final int minFreeStorageMb;
  final bool autoPipelineEnabled;
  final bool faceAwareCropEnabled;
  final bool exportSrtEnabled;

  int get minFreeStorageBytes => minFreeStorageMb * 1024 * 1024;

  /// Opsi deteksi turunan dari durasi target + jumlah clip maksimal.
  DetectionOptions get detection {
    final target = clipDurationSeconds * 1000;
    final min = (target * 0.65).round();
    final max = (target * 1.35).round();
    return DetectionOptions(
      minMs: min,
      targetMs: target,
      maxMs: max,
      maxClips: maxClipCount,
    );
  }

  /// Lebar <= 720 berarti 720x1280; selain itu mengikuti mode otomatis
  /// (1080x1920 bila sumber cukup tajam).
  PortraitResolution get resolution =>
      outputWidth <= 720 ? PortraitResolution.p720 : PortraitResolution.auto;

  static int _int(Object? v, int fallback, int lo, int hi) {
    final n = v is num && v.isFinite ? v.toInt() : fallback;
    return n < lo ? lo : (n > hi ? hi : n);
  }

  static int _even(int v) => v.isEven ? v : v - 1;

  /// Membangun pengaturan dari [config]. Aman terhadap nilai null, bertipe
  /// salah, NaN, atau di luar rentang.
  static AppSettings resolve(RemoteConfig? config) {
    if (config == null) return defaults;
    final s = config.settings;
    return AppSettings(
      clipDurationSeconds: _int(
        s['default_clip_duration_seconds'],
        defaults.clipDurationSeconds,
        minClipSeconds,
        maxClipSeconds,
      ),
      maxClipCount: _int(
        s['max_clip_count'],
        defaults.maxClipCount,
        minClipCount,
        maxClipCountLimit,
      ),
      outputWidth: _even(_int(s['default_output_width'], defaults.outputWidth, 360, 2160)),
      outputHeight: _even(_int(s['default_output_height'], defaults.outputHeight, 640, 3840)),
      minFreeStorageMb: _int(
        s['min_free_storage_mb'],
        defaults.minFreeStorageMb,
        minFreeFloorMb,
        minFreeCeilingMb,
      ),
      autoPipelineEnabled: config.feature('auto_pipeline'),
      // Flag yang tidak dikenal server dianggap aktif (perilaku STEP 1-19);
      // admin dapat mematikannya dari panel.
      faceAwareCropEnabled: config.feature('face_aware_crop', fallback: true),
      exportSrtEnabled: config.feature('export_srt'),
    );
  }
}
