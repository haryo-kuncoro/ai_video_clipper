import '../../core/errors/app_exception.dart';

/// Pembatalan kooperatif untuk pekerjaan panjang (unduh model, transkripsi).
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// Mendaftarkan callback pembatalan. Bila sudah dibatalkan, callback
  /// langsung dipanggil. Mengembalikan fungsi untuk melepas pendaftaran.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Dilempar mesin/unduhan ketika pengguna membatalkan.
class TranscriptionCancelled implements Exception {
  const TranscriptionCancelled();

  @override
  String toString() => 'TranscriptionCancelled';
}

/// Satu segmen hasil mesin STT (waktu dalam milidetik dari awal video).
class RawSegment {
  const RawSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int startMs;
  final int endMs;
  final String text;
}

enum TranscriptionPhase { extractingAudio, transcribing, saving }

class TranscriptionProgress {
  const TranscriptionProgress(this.phase, this.fraction);

  final TranscriptionPhase phase;

  /// Progres keseluruhan 0.0 - 1.0.
  final double fraction;

  String get label {
    switch (phase) {
      case TranscriptionPhase.extractingAudio:
        return 'Mengekstrak audio';
      case TranscriptionPhase.transcribing:
        return 'Mengenali ucapan';
      case TranscriptionPhase.saving:
        return 'Menyimpan transcript';
    }
  }
}

class TranscriptionOutcome {
  const TranscriptionOutcome({
    this.transcriptId,
    this.segmentCount = 0,
    this.cancelled = false,
  });

  final int? transcriptId;
  final int segmentCount;
  final bool cancelled;
}

/// Model Whisper (ONNX int8) yang diunduh sekali lalu dipakai offline.
///
/// Nama file mengikuti konvensi repo `sherpa-onnx-whisper-<id>`:
/// `<id>-encoder.int8.onnx`, `<id>-decoder.int8.onnx`, `<id>-tokens.txt`.
class WhisperModelInfo {
  const WhisperModelInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.baseUrl,
  });

  final String id;
  final String label;
  final String description;

  /// URL folder tempat 3 file model berada (tanpa garis miring di akhir).
  final String baseUrl;

  String get dirName => 'whisper-$id';
  String get encoderName => '$id-encoder.int8.onnx';
  String get decoderName => '$id-decoder.int8.onnx';
  String get tokensName => '$id-tokens.txt';

  String urlFor(String fileName) => '$baseUrl/$fileName';
}

/// Path file model yang sudah siap dipakai mesin.
class WhisperModelFiles {
  const WhisperModelFiles({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
  });

  final String encoder;
  final String decoder;
  final String tokens;
  final String vad;
}

abstract final class WhisperModels {
  static const _hf = 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-';

  static const tiny = WhisperModelInfo(
    id: 'tiny',
    label: 'Tiny',
    description: 'Paling cepat dan ringan, akurasi terendah.',
    baseUrl: '${_hf}tiny/resolve/main',
  );

  static const base = WhisperModelInfo(
    id: 'base',
    label: 'Base',
    description: 'Seimbang untuk HP biasa. Disarankan sebagai awal.',
    baseUrl: '${_hf}base/resolve/main',
  );

  static const small = WhisperModelInfo(
    id: 'small',
    label: 'Small',
    description: 'Lebih akurat untuk bahasa Indonesia, lebih lambat dan berat.',
    baseUrl: '${_hf}small/resolve/main',
  );

  static const all = [tiny, base, small];
  static const defaultModel = base;

  static WhisperModelInfo byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => defaultModel);

  /// Model deteksi suara (Silero VAD) untuk memotong audio per ucapan.
  static const vadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx';
}

/// Bahasa yang ditawarkan. Kode kosong = deteksi otomatis oleh Whisper.
class TranscriptionLanguage {
  const TranscriptionLanguage(this.code, this.label);

  final String code;
  final String label;

  static const indonesian = TranscriptionLanguage('id', 'Indonesia');
  static const english = TranscriptionLanguage('en', 'Inggris');
  static const auto = TranscriptionLanguage('', 'Otomatis');

  static const all = [indonesian, english, auto];
}

AppException modelMissing(WhisperModelInfo model) => AppException(
      'Model ${model.label} belum diunduh.',
      code: 'model_missing',
    );
