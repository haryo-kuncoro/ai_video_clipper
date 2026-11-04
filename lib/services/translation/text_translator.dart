import '../../core/errors/app_exception.dart';

/// Penerjemah teks. Diabstraksikan agar mudah di-fake saat testing.
///
/// Implementasi nyata (ML Kit) berjalan ON-DEVICE: setelah model bahasa
/// diunduh sekali, teks tidak pernah dikirim ke server mana pun.
abstract class TextTranslator {
  /// Memastikan model bahasa [source] dan [target] sudah ada (mengunduh bila
  /// belum). [onStatus] menerima teks status untuk ditampilkan.
  Future<void> ensureModels(
    String source,
    String target, {
    void Function(String status)? onStatus,
  });

  Future<String> translate(String source, String target, String text);

  Future<void> close();
}

/// Bahasa yang didukung untuk terjemahan.
abstract final class TranslationLanguages {
  static const supported = {'id', 'en', 'ko', 'ja', 'zh'};

  static void require(String code) {
    if (!supported.contains(code)) {
      throw AppException(
        'Terjemahan untuk bahasa "$code" belum didukung.',
        code: 'translate_unsupported',
      );
    }
  }
}
