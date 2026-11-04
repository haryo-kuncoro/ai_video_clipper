import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../transcription/transcription_models.dart';
import '../transcription/whisper_model_manager.dart';
import '../translation/text_translator.dart';

/// Status & pengelolaan semua model offline (STT Whisper + terjemahan).
/// Dimiliki satu instance global agar unduhan tetap berjalan saat pengguna
/// berpindah halaman, dan kartu di halaman project cukup mendengarkan.
class ModelCatalog extends ChangeNotifier {
  ModelCatalog({required this.whisper, required this.translator});

  final WhisperModelManager whisper;
  final TextTranslator translator;

  final Map<String, int> _whisperSizes = {}; // id -> byte (ada = terpasang)
  final Set<String> _translationReady = {};
  bool _loaded = false;

  String? _busyKey;
  String _busyLabel = '';
  double? _fraction;
  String? _message;
  CancelToken? _cancel;

  bool get loaded => _loaded;
  bool get busy => _busyKey != null;
  String? get busyKey => _busyKey;
  String get busyLabel => _busyLabel;

  /// Progres unduhan 0..1 (null = tidak diketahui).
  double? get fraction => _fraction;
  String? get message => _message;

  static String whisperKey(WhisperModelInfo m) => 'stt:${m.id}';
  static String translationKey(String code) => 'tr:$code';

  bool whisperInstalled(WhisperModelInfo m) => _whisperSizes.containsKey(m.id);
  int whisperSize(WhisperModelInfo m) => _whisperSizes[m.id] ?? 0;
  bool translationReady(String code) => _translationReady.contains(code);

  List<WhisperModelInfo> get installedWhisper =>
      [for (final m in WhisperModels.all) if (whisperInstalled(m)) m];

  /// Pesan untuk pengguna bila ada model yang kurang; null bila semua siap.
  String? missingMessage({
    WhisperModelInfo? stt,
    String? sourceLang,
    String? targetLang,
  }) {
    if (!_loaded) return 'Memeriksa model yang tersedia…';
    final missing = <String>[];
    if (stt != null && !whisperInstalled(stt)) {
      missing.add('model transcript ${stt.label}');
    }
    if (sourceLang != null && targetLang != null) {
      for (final c in {sourceLang, targetLang}) {
        if (!translationReady(c)) {
          missing.add('model terjemahan ${TranslationLanguages.names[c] ?? c}');
        }
      }
    }
    if (missing.isEmpty) return null;
    return 'Unduh ${missing.join(' dan ')} terlebih dahulu di '
        'Pengaturan > Model AI.';
  }

  Future<void> refresh() async {
    for (final m in WhisperModels.all) {
      try {
        if (await whisper.isInstalled(m)) {
          _whisperSizes[m.id] = await whisper.installedSize(m);
        } else {
          _whisperSizes.remove(m.id);
        }
      } catch (e) {
        AppLogger.e('Cek model ${m.id} gagal', e);
        _whisperSizes.remove(m.id);
      }
    }
    for (final c in TranslationLanguages.supported) {
      try {
        if (await translator.isModelDownloaded(c)) {
          _translationReady.add(c);
        } else {
          _translationReady.remove(c);
        }
      } catch (_) {
        _translationReady.remove(c);
      }
    }
    _loaded = true;
    notifyListeners();
  }

  void cancel() => _cancel?.cancel();

  void clearMessage() {
    _message = null;
    notifyListeners();
  }

  Future<void> downloadWhisper(WhisperModelInfo m) async {
    if (busy) return;
    final c = CancelToken();
    _begin(whisperKey(m), 'Mengunduh model ${m.label}', c);
    try {
      await whisper.download(
        m,
        cancel: c,
        onProgress: (d) {
          // Progres kasar lintas file: file ke-i + pecahan file saat ini.
          final f = d.fileFraction;
          _fraction = f == null ? null : (d.fileIndex + f) / d.fileCount;
          notifyListeners();
        },
      );
      _message = 'Model ${m.label} siap dipakai.';
    } on TranscriptionCancelled {
      _message = 'Unduhan dibatalkan.';
    } on AppException catch (e) {
      _message = e.message;
    } catch (e, st) {
      AppLogger.e('Unduh model gagal', e, st);
      _message = 'Unduhan model gagal. Coba lagi.';
    } finally {
      await _end();
    }
  }

  Future<void> deleteWhisper(WhisperModelInfo m) async {
    if (busy) return;
    try {
      await whisper.delete(m);
      _message = 'Model ${m.label} dihapus.';
    } on AppException catch (e) {
      _message = e.message;
    }
    await refresh();
  }

  Future<void> downloadTranslation(String code) async {
    if (busy) return;
    final name = TranslationLanguages.names[code] ?? code;
    _begin(translationKey(code), 'Mengunduh model terjemahan $name', null);
    try {
      await translator.downloadModel(code);
      _message = 'Model terjemahan $name siap dipakai.';
    } on AppException catch (e) {
      _message = e.message;
    } catch (e, st) {
      AppLogger.e('Unduh model terjemahan gagal', e, st);
      _message = 'Unduhan model terjemahan gagal. Coba lagi.';
    } finally {
      await _end();
    }
  }

  Future<void> deleteTranslation(String code) async {
    if (busy) return;
    try {
      await translator.deleteModel(code);
      _message = 'Model terjemahan dihapus.';
    } on AppException catch (e) {
      _message = e.message;
    }
    await refresh();
  }

  void _begin(String key, String label, CancelToken? c) {
    _busyKey = key;
    _busyLabel = label;
    _fraction = null;
    _message = null;
    _cancel = c;
    notifyListeners();
  }

  Future<void> _end() async {
    _busyKey = null;
    _busyLabel = '';
    _fraction = null;
    _cancel = null;
    await refresh();
  }
}
