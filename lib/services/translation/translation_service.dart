import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/repositories/transcript_repository.dart';
import '../transcription/transcription_models.dart';
import 'text_translator.dart';

/// Menerjemahkan transcript project (mis. Korea -> Indonesia). Teks asli
/// disimpan di `source_text`; `text` menjadi terjemahan sehingga subtitle,
/// editor, dan deteksi clip otomatis memakai bahasa target.
class TranslationService {
  TranslationService({required this.translator, required this.transcripts});

  final TextTranslator translator;
  final TranscriptRepository transcripts;

  /// True bila transcript project ada dan belum diterjemahkan ke [target].
  Future<bool> needsTranslation(int projectId, String target) async {
    final t = await transcripts.getByProject(projectId);
    return t != null && t.translatedLang != target;
  }

  /// Mengembalikan jumlah segmen yang berhasil diterjemahkan.
  Future<int> translateProject({
    required int projectId,
    required String source,
    required String target,
    CancelToken? cancel,
    void Function(double fraction, String status)? onProgress,
  }) async {
    TranslationLanguages.require(source);
    TranslationLanguages.require(target);
    if (source == target) return 0;

    final t = await transcripts.getByProject(projectId);
    if (t == null) {
      throw const AppException('Transcript belum ada.', code: 'no_transcript');
    }
    final segs = await transcripts.getSegments(t.id!);
    if (segs.isEmpty) return 0;

    await translator.ensureModels(source, target,
        onStatus: (s) => onProgress?.call(0, s));

    final out = <int, String>{};
    try {
      for (var i = 0; i < segs.length; i++) {
        if (cancel?.isCancelled ?? false) throw const TranscriptionCancelled();
        final s = segs[i];
        // Selalu terjemahkan dari teks asli bila sudah pernah diterjemahkan.
        final original = s.sourceText ?? s.text;
        String r;
        try {
          r = (await translator.translate(source, target, original)).trim();
        } catch (e) {
          AppLogger.e('Segmen gagal diterjemahkan', e);
          r = '';
        }
        out[s.id!] = r.isEmpty ? original : r;
        onProgress?.call((i + 1) / segs.length, 'Menerjemahkan');
      }
    } on AppException {
      rethrow;
    } finally {
      await translator.close();
    }

    await transcripts.applyTranslation(t.id!, out, target);
    return out.length;
  }
}
