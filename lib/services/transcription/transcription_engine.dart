import 'transcription_models.dart';

/// Kontrak mesin speech-to-text. Implementasi nyata ada di SATU file
/// (`sherpa_whisper_engine.dart`) sehingga mesin dapat diganti tanpa
/// menyentuh pipeline, database, atau UI.
abstract class TranscriptionEngine {
  /// Mentranskripsi file WAV 16 kHz mono PCM16.
  ///
  /// - [language]: kode ISO ('id', 'en') atau '' untuk deteksi otomatis.
  /// - [onProgress]: 0.0 - 1.0.
  /// - Melempar [TranscriptionCancelled] bila dibatalkan, atau AppException
  ///   dengan pesan ramah pengguna untuk kegagalan lain.
  Future<List<RawSegment>> transcribe({
    required String wavPath,
    required WhisperModelFiles files,
    required String language,
    int threads = 2,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  });

  /// Nama mesin untuk disimpan di tabel transcripts.
  String get name;
}
