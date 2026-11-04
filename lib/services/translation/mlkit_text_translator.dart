import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import 'text_translator.dart';

/// Satu-satunya file yang memakai `google_mlkit_translation`.
class MlKitTextTranslator implements TextTranslator {
  final _manager = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};

  static TranslateLanguage _lang(String code) {
    switch (code) {
      case 'id':
        return TranslateLanguage.indonesian;
      case 'en':
        return TranslateLanguage.english;
      case 'ko':
        return TranslateLanguage.korean;
      case 'ja':
        return TranslateLanguage.japanese;
      case 'zh':
        return TranslateLanguage.chinese;
    }
    throw AppException('Terjemahan untuk bahasa "$code" belum didukung.',
        code: 'translate_unsupported');
  }

  @override
  Future<void> ensureModels(
    String source,
    String target, {
    void Function(String status)? onStatus,
  }) async {
    for (final code in {source, target}) {
      final bcp = _lang(code).bcpCode;
      try {
        if (await _manager.isModelDownloaded(bcp)) continue;
        onStatus?.call('Mengunduh model terjemahan ($code), sekali saja');
        final ok = await _manager.downloadModel(bcp, isWifiRequired: false);
        if (!ok) throw StateError('download false');
      } on AppException {
        rethrow;
      } catch (e, st) {
        AppLogger.e('Unduh model terjemahan gagal', e, st);
        throw const AppException(
          'Model terjemahan belum bisa diunduh. Periksa koneksi internet '
          'lalu coba lagi (cukup sekali).',
          code: 'translate_model',
        );
      }
    }
  }

  @override
  Future<String> translate(String source, String target, String text) async {
    final key = '$source>$target';
    final t = _translators.putIfAbsent(
      key,
      () => OnDeviceTranslator(
          sourceLanguage: _lang(source), targetLanguage: _lang(target)),
    );
    return t.translateText(text);
  }

  @override
  Future<void> close() async {
    for (final t in _translators.values) {
      await t.close();
    }
    _translators.clear();
  }
}
