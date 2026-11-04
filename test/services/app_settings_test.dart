import 'package:ai_video_clipper/services/ffmpeg/portrait_plan.dart';
import 'package:ai_video_clipper/services/remote/remote_config.dart';
import 'package:ai_video_clipper/services/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteConfig cfg(Map<String, Object?> s, [Map<String, bool> f = const {}]) =>
    RemoteConfig(settings: s, features: f);

void main() {
  group('AppSettings.resolve', () {
    test('tanpa konfigurasi memakai bawaan lokal', () {
      final s = AppSettings.resolve(null);
      expect(s.clipDurationSeconds, 45);
      expect(s.maxClipCount, 10);
      expect(s.autoPipelineEnabled, isTrue);
      expect(s.resolution, PortraitResolution.auto);
      expect(AppSettings.resolve(RemoteConfig.empty).minFreeStorageMb, 500);
    });

    test('nilai valid dari server dipakai', () {
      final s = AppSettings.resolve(cfg({
        'default_clip_duration_seconds': 30,
        'max_clip_count': 6,
        'default_output_width': 720,
        'default_output_height': 1280,
        'min_free_storage_mb': 800,
      }));
      expect(s.clipDurationSeconds, 30);
      expect(s.maxClipCount, 6);
      expect(s.resolution, PortraitResolution.p720);
      expect(s.minFreeStorageBytes, 800 * 1024 * 1024);
    });

    test('nilai di luar rentang dibatasi (clamp)', () {
      final s = AppSettings.resolve(cfg({
        'default_clip_duration_seconds': 5,
        'max_clip_count': 9999,
        'min_free_storage_mb': 0,
        'default_output_width': 99999,
      }));
      expect(s.clipDurationSeconds, AppSettings.minClipSeconds);
      expect(s.maxClipCount, AppSettings.maxClipCountLimit);
      expect(s.minFreeStorageMb, AppSettings.minFreeFloorMb);
      expect(s.outputWidth, 2160);
    });

    test('tipe salah, NaN, dan infinity memakai bawaan/batas aman', () {
      final s = AppSettings.resolve(cfg({
        'default_clip_duration_seconds': 'banyak',
        'max_clip_count': double.nan,
        'min_free_storage_mb': double.infinity,
        'default_output_width': null,
      }));
      expect(s.clipDurationSeconds, 45);
      expect(s.maxClipCount, 10);
      expect(s.minFreeStorageMb, 500);
      expect(s.outputWidth, 1080);
    });

    test('ukuran output selalu genap', () {
      final s = AppSettings.resolve(cfg({
        'default_output_width': 721,
        'default_output_height': 1281,
      }));
      expect(s.outputWidth.isEven, isTrue);
      expect(s.outputHeight.isEven, isTrue);
    });

    test('flag mengendalikan fitur; flag tak dikenal = aktif', () {
      final s = AppSettings.resolve(cfg({}, {
        'auto_pipeline': false,
        'export_srt': false,
      }));
      expect(s.autoPipelineEnabled, isFalse);
      expect(s.exportSrtEnabled, isFalse);
      expect(s.faceAwareCropEnabled, isTrue);
    });

    test('DetectionOptions turunan konsisten', () {
      final d = AppSettings.resolve(cfg({
        'default_clip_duration_seconds': 60,
        'max_clip_count': 4,
      })).detection;
      expect(d.targetMs, 60000);
      expect(d.minMs, lessThan(d.targetMs));
      expect(d.maxMs, greaterThan(d.targetMs));
      expect(d.maxClips, 4);
      final ext = AppSettings.resolve(cfg({'default_clip_duration_seconds': 180})).detection;
      expect(ext.minMs, lessThan(ext.targetMs));
    });
  });
}
