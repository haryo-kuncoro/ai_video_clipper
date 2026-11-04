import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/video_record.dart';
import '../ai/clip_detector.dart';
import '../background/keep_alive.dart';
import '../transcription/transcription_models.dart';
import 'pipeline_backend.dart';

enum PipelineStage {
  idle,
  transcribing,
  detecting,
  rendering,
  exporting,
  done,
  failed,
  cancelled,
}

class PipelineOptions {
  const PipelineOptions({
    this.model = WhisperModels.base,
    this.language = 'id',
    this.reuseTranscript = true,
    this.detection = const DetectionOptions(),
    this.acceptTop = 5,
    this.burnSubtitles = true,
    this.faceAware = true,
    this.exportToGallery = false,
    this.translateTo,
  });

  final WhisperModelInfo model;
  final String language;

  /// Lewati transkripsi bila project sudah punya transcript.
  final bool reuseTranscript;
  final DetectionOptions detection;

  /// Jumlah kandidat skor tertinggi yang langsung diterima untuk dirender.
  final int acceptTop;
  final bool burnSubtitles;
  final bool faceAware;
  final bool exportToGallery;

  /// Kode bahasa tujuan terjemahan (mis. 'id'); null = tanpa terjemahan.
  final String? translateTo;

  /// Terjemahan berlaku hanya bila bahasa sumber jelas dan berbeda dari tujuan.
  bool get translates =>
      translateTo != null && language.isNotEmpty && language != translateTo;
}

class PipelineState {
  const PipelineState({
    this.stage = PipelineStage.idle,
    this.projectId,
    this.fraction = 0,
    this.label = '',
    this.error,
    this.result,
  });

  final PipelineStage stage;
  final int? projectId;

  /// Progres keseluruhan 0.0 - 1.0.
  final double fraction;
  final String label;
  final String? error;
  final PipelineResult? result;

  bool get isActive =>
      stage == PipelineStage.transcribing ||
      stage == PipelineStage.detecting ||
      stage == PipelineStage.rendering ||
      stage == PipelineStage.exporting;
}

class PipelineResult {
  const PipelineResult({
    this.transcribed = false,
    this.reusedTranscript = false,
    this.candidates = 0,
    this.accepted = 0,
    this.rendered = 0,
    this.renderFailed = 0,
    this.exported = 0,
    this.warnings = const [],
  });

  final bool transcribed;
  final bool reusedTranscript;
  final int candidates;
  final int accepted;
  final int rendered;
  final int renderFailed;
  final int exported;
  final List<String> warnings;

  String get summary {
    final parts = <String>[
      if (reusedTranscript) 'transcript lama dipakai',
      '$candidates kandidat',
      '$rendered clip dirender',
      if (renderFailed > 0) '$renderFailed gagal',
      if (exported > 0) '$exported diekspor ke galeri',
    ];
    return parts.join(' · ');
  }
}

/// STEP 17: menjalankan Transkripsi -> Deteksi -> Render (-> Ekspor) secara
/// BERURUTAN untuk satu project, dibungkus foreground service agar tetap
/// berjalan saat aplikasi di latar belakang. Hanya satu pipeline aktif pada
/// satu waktu (hemat RAM/CPU). State dimiliki objek ini (bukan widget),
/// sehingga berpindah halaman tidak menghentikan proses.
class ProcessingPipeline extends ChangeNotifier {
  ProcessingPipeline({
    required PipelineBackend backend,
    BackgroundKeepAlive keepAlive = const NoopKeepAlive(),
  })  : _backend = backend,
        _keepAlive = keepAlive;

  final PipelineBackend _backend;
  final BackgroundKeepAlive _keepAlive;

  PipelineState _state = const PipelineState();
  PipelineState get state => _state;
  bool get isRunning => _running;

  bool _running = false;
  CancelToken? _cancel;
  int _lastNotified = -1;
  String _lastLabel = '';

  static const _title = 'AI CLIPPER';

  /// Meminta pembatalan; proses berhenti di titik aman berikutnya.
  void cancel() => _cancel?.cancel();

  /// Kembali ke keadaan awal setelah hasil akhir dibaca.
  void reset() {
    if (_running) return;
    _state = const PipelineState();
    notifyListeners();
  }

  Future<PipelineResult?> run({
    required VideoRecord video,
    PipelineOptions options = const PipelineOptions(),
  }) async {
    if (_running) {
      throw const AppException(
        'Pemrosesan lain sedang berjalan. Tunggu sampai selesai.',
        code: 'busy',
      );
    }
    _running = true;
    final cancel = CancelToken();
    _cancel = cancel;
    _lastNotified = -1;
    _lastLabel = '';
    final projectId = video.projectId;

    var transcribed = false;
    var reused = false;
    var found = 0;
    var accepted = 0;
    var rendered = 0;
    var renderFailed = 0;
    var exported = 0;
    final warnings = <String>[];

    PipelineResult result() => PipelineResult(
          transcribed: transcribed,
          reusedTranscript: reused,
          candidates: found,
          accepted: accepted,
          rendered: rendered,
          renderFailed: renderFailed,
          exported: exported,
          warnings: warnings,
        );

    try {
      await _keepAlive.start(title: _title, text: 'Menyiapkan…');

      final needTranscript = !(options.reuseTranscript &&
          await _backend.hasTranscript(projectId));
      final doExport = options.exportToGallery;

      // Bobot tiap tahap; dinormalisasi terhadap tahap yang benar-benar jalan.
      final wTranscribe = needTranscript ? 0.55 : 0.0;
      final wTranslate = options.translates ? 0.08 : 0.0;
      const wDetect = 0.05;
      const wRender = 0.35;
      final wExport = doExport ? 0.05 : 0.0;
      final total = wTranscribe + wTranslate + wDetect + wRender + wExport;
      double overall(double before, double weight, double f) =>
          ((before + weight * f.clamp(0.0, 1.0)) / total).clamp(0.0, 1.0);

      // 1. Transkripsi
      if (needTranscript) {
        _set(PipelineStage.transcribing, projectId, 0, 'Mengenali ucapan');
        final out = await _backend.transcribe(
          video: video,
          model: options.model,
          language: options.language,
          cancel: cancel,
          onProgress: (f) => _set(PipelineStage.transcribing, projectId,
              overall(0, wTranscribe, f), 'Mengenali ucapan'),
        );
        if (out.cancelled || cancel.isCancelled) {
          return await _finishCancelled(projectId, result());
        }
        transcribed = true;
      } else {
        reused = true;
      }

      // 1b. Terjemahan (opsional) — offline di perangkat
      if (options.translates &&
          await _backend.needsTranslation(projectId, options.translateTo!)) {
        _set(PipelineStage.transcribing, projectId,
            overall(wTranscribe, 0, 0), 'Menerjemahkan');
        await _backend.translate(
          projectId: projectId,
          source: options.language,
          target: options.translateTo!,
          cancel: cancel,
          onProgress: (f, status) => _set(PipelineStage.transcribing,
              projectId, overall(wTranscribe, wTranslate, f), status),
        );
        if (cancel.isCancelled) {
          return await _finishCancelled(projectId, result());
        }
      }

      // 2. Deteksi + terima kandidat teratas
      _set(PipelineStage.detecting, projectId,
          overall(wTranscribe, wTranslate, 0),
          'Mencari momen terbaik');
      final det = await _backend.detect(
        video: video,
        options: options.detection,
        acceptTop: options.acceptTop,
      );
      found = det.found;
      accepted = det.accepted;
      if (cancel.isCancelled) return await _finishCancelled(projectId, result());
      if (accepted == 0) {
        throw const AppException(
          'Tidak ada momen yang cukup menarik ditemukan. Coba transcript yang '
          'lebih panjang atau ubah durasi clip.',
          code: 'no_candidates',
        );
      }

      // 3. Render
      final before = doExport ? await _backend.clipIds(projectId) : <int>{};
      final renderStart = wTranscribe + wTranslate + wDetect;
      _set(PipelineStage.rendering, projectId, overall(renderStart, 0, 0),
          'Merender clip');
      final summary = await _backend.render(
        video: video,
        burnSubtitles: options.burnSubtitles,
        faceAware: options.faceAware,
        cancel: cancel,
        onProgress: (f) => _set(PipelineStage.rendering, projectId,
            overall(renderStart, wRender, f), 'Merender clip'),
      );
      rendered = summary.succeeded;
      renderFailed = summary.failures.length;
      warnings.addAll(summary.warnings);
      if (summary.cancelled || cancel.isCancelled) {
        return await _finishCancelled(projectId, result());
      }
      if (rendered == 0) {
        throw const AppException(
          'Tidak ada clip yang berhasil dirender. Buka kartu Render Clip untuk '
          'melihat detail kegagalan.',
          code: 'render_failed',
        );
      }

      // 4. Ekspor (opsional)
      if (doExport) {
        final exportStart = renderStart + wRender;
        _set(PipelineStage.exporting, projectId, overall(exportStart, 0, 0),
            'Menyimpan ke galeri');
        final ex = await _backend.exportNew(
            projectId: projectId, excludeIds: before);
        exported = ex.exported;
        warnings.addAll(ex.problems);
      }

      final r = result();
      _state = PipelineState(
        stage: PipelineStage.done,
        projectId: projectId,
        fraction: 1,
        label: 'Selesai',
        result: r,
      );
      await _keepAlive.update(
          title: _title, text: 'Selesai: ${r.summary}', progress: 100);
      notifyListeners();
      return r;
    } on AppException catch (e) {
      return _fail(projectId, e.message, result());
    } catch (e, st) {
      AppLogger.e('Pipeline gagal', e, st);
      return _fail(projectId, 'Pemrosesan gagal. Coba lagi.', result());
    } finally {
      _running = false;
      _cancel = null;
      await _keepAlive.stop();
      notifyListeners();
    }
  }

  Future<PipelineResult?> _finishCancelled(
      int projectId, PipelineResult partial) async {
    _state = PipelineState(
      stage: PipelineStage.cancelled,
      projectId: projectId,
      fraction: _state.fraction,
      label: 'Dibatalkan',
      result: partial,
    );
    notifyListeners();
    return partial;
  }

  PipelineResult? _fail(int projectId, String message, PipelineResult partial) {
    _state = PipelineState(
      stage: PipelineStage.failed,
      projectId: projectId,
      fraction: _state.fraction,
      label: 'Gagal',
      error: message,
      result: partial,
    );
    return null;
  }

  void _set(PipelineStage stage, int projectId, double fraction, String label) {
    _state = PipelineState(
      stage: stage,
      projectId: projectId,
      fraction: fraction,
      label: label,
    );
    notifyListeners();
    // Notifikasi dibatasi: hanya saat persen berubah atau tahap berganti.
    final pct = (fraction * 100).floor();
    if (pct != _lastNotified || label != _lastLabel) {
      _lastNotified = pct;
      _lastLabel = label;
      _keepAlive.update(title: _title, text: label, progress: pct);
    }
  }
}
