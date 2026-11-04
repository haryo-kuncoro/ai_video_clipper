import 'package:flutter/services.dart';

import '../../core/utils/app_logger.dart';

/// Menahan proses aplikasi tetap hidup selama pekerjaan panjang berjalan
/// (foreground service + notifikasi progres di Android). Tidak pernah
/// melempar error: bila gagal, pekerjaan tetap berjalan normal.
abstract class BackgroundKeepAlive {
  Future<void> start({required String title, required String text});

  /// [progress] 0-100, atau null untuk indikator tak tentu.
  Future<void> update({
    required String title,
    required String text,
    int? progress,
  });

  Future<void> stop();
}

class NativeKeepAlive implements BackgroundKeepAlive {
  static const _channel = MethodChannel('com.haryo.ai_video_clipper/media');

  Future<void> _call(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<bool>(method, args);
    } on MissingPluginException {
      // Komponen native belum terpasang: abaikan.
    } on PlatformException catch (e) {
      AppLogger.i('Keep-alive $method gagal: ${e.message}');
    }
  }

  @override
  Future<void> start({required String title, required String text}) =>
      _call('keepAliveStart', {'title': title, 'text': text});

  @override
  Future<void> update({
    required String title,
    required String text,
    int? progress,
  }) =>
      _call('keepAliveUpdate',
          {'title': title, 'text': text, 'progress': progress ?? -1});

  @override
  Future<void> stop() => _call('keepAliveStop', const {});
}

/// Tidak melakukan apa-apa (test, platform non-Android).
class NoopKeepAlive implements BackgroundKeepAlive {
  const NoopKeepAlive();

  @override
  Future<void> start({required String title, required String text}) async {}

  @override
  Future<void> update(
      {required String title, required String text, int? progress}) async {}

  @override
  Future<void> stop() async {}
}
