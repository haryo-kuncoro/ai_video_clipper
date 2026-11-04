import '../../core/errors/app_exception.dart';
import '../../database/models/clip.dart';
import '../../database/models/clip_candidate.dart';
import '../../database/models/video_record.dart';
import '../ai/clip_detection_service.dart';
import '../ai/clip_detector.dart';
import '../export/export_service.dart';
import '../render/clip_render_service.dart';
import '../transcription/transcription_models.dart';
import '../transcription/transcription_service.dart';
import '../translation/translation_service.dart';

/// Langkah-langkah pipeline. Diabstraksikan agar urutan, pembatalan, dan
/// penanganan error pipeline bisa diuji tanpa FFmpeg/STT sungguhan.
abstract class PipelineBackend {
  Future<bool> hasTranscript(int projectId);

  Future<TranscriptionOutcome> transcribe({
    required VideoRecord video,
    required WhisperModelInfo model,
    required String language,
    required CancelToken cancel,
    required void Function(double fraction) onProgress,
  });

  /// True bila transcript project perlu diterjemahkan ke [target].
  Future<bool> needsTranslation(int projectId, String target);

  /// Menerjemahkan transcript project. Berhenti diam-diam bila dibatalkan.
  Future<void> translate({
    required int projectId,
    required String source,
    required String target,
    required CancelToken cancel,
    required void Function(double fraction, String status) onProgress,
  });

  /// Mendeteksi kandidat lalu menerima [acceptTop] skor tertinggi.
  Future<({int found, int accepted})> detect({
    required VideoRecord video,
    required DetectionOptions options,
    required int acceptTop,
  });

  Future<RenderSummary> render({
    required VideoRecord video,
    required bool burnSubtitles,
    required bool faceAware,
    required CancelToken cancel,
    required void Function(double fraction) onProgress,
  });

  Future<Set<int>> clipIds(int projectId);

  /// Ekspor ke galeri clip yang idnya BUKAN di [excludeIds].
  Future<({int exported, List<String> problems})> exportNew({
    required int projectId,
    required Set<int> excludeIds,
  });
}

/// Implementasi nyata di atas service STEP 9-16.
class ServicePipelineBackend implements PipelineBackend {
  ServicePipelineBackend({
    required this.transcription,
    required this.detection,
    required ClipRenderService render,
    this.export,
    this.translation,
  }) : _render = render;

  final TranscriptionService transcription;
  final ClipDetectionService detection;
  final ClipRenderService _render;
  final ExportService? export;
  final TranslationService? translation;

  @override
  Future<bool> hasTranscript(int projectId) async {
    final t = await transcription.transcripts.getByProject(projectId);
    if (t == null) return false;
    return (await transcription.transcripts.getSegments(t.id!)).isNotEmpty;
  }

  @override
  Future<TranscriptionOutcome> transcribe({
    required VideoRecord video,
    required WhisperModelInfo model,
    required String language,
    required CancelToken cancel,
    required void Function(double fraction) onProgress,
  }) =>
      transcription.transcribe(
        video: video,
        model: model,
        language: language,
        cancel: cancel,
        onProgress: (p) => onProgress(p.fraction),
      );

  @override
  Future<bool> needsTranslation(int projectId, String target) async =>
      await translation?.needsTranslation(projectId, target) ?? false;

  @override
  Future<void> translate({
    required int projectId,
    required String source,
    required String target,
    required CancelToken cancel,
    required void Function(double fraction, String status) onProgress,
  }) async {
    final svc = translation;
    if (svc == null) {
      throw const AppException('Fitur terjemahan belum tersedia.',
          code: 'translate_missing');
    }
    try {
      await svc.translateProject(
        projectId: projectId,
        source: source,
        target: target,
        cancel: cancel,
        onProgress: onProgress,
      );
    } on TranscriptionCancelled {
      // Pembatalan ditangani pipeline lewat cancel.isCancelled.
    }
  }

  @override
  Future<({int found, int accepted})> detect({
    required VideoRecord video,
    required DetectionOptions options,
    required int acceptTop,
  }) async {
    final found = await detection.detect(
      projectId: video.projectId,
      videoDurationMs: video.durationMs,
      options: options,
    );
    // Hasil sudah terurut skor tertinggi.
    var accepted = 0;
    for (final c in found) {
      if (accepted >= acceptTop) break;
      if (c.id == null) continue;
      await detection.candidates.updateStatus(c.id!, CandidateStatus.accepted);
      accepted++;
    }
    return (found: found.length, accepted: accepted);
  }

  @override
  Future<RenderSummary> render({
    required VideoRecord video,
    required bool burnSubtitles,
    required bool faceAware,
    required CancelToken cancel,
    required void Function(double fraction) onProgress,
  }) =>
      _render.renderAccepted(
            video: video,
            burnSubtitles: burnSubtitles,
            faceAware: faceAware,
            cancel: cancel,
            onProgress: (p) {
              if (p.total <= 0) return;
              onProgress(((p.index - 1) + p.clipFraction) / p.total);
            },
          );

  @override
  Future<Set<int>> clipIds(int projectId) async => {
        for (final c in await _render.clips.getByProject(projectId))
          if (c.id != null) c.id!,
      };

  @override
  Future<({int exported, List<String> problems})> exportNew({
    required int projectId,
    required Set<int> excludeIds,
  }) async {
    final svc = export;
    if (svc == null) return (exported: 0, problems: <String>[]);
    final fresh = <Clip>[
      for (final c in await _render.clips.getByProject(projectId))
        if (c.id != null && !excludeIds.contains(c.id!)) c,
    ];
    if (fresh.isEmpty) return (exported: 0, problems: <String>[]);
    final s = await svc.exportClips(fresh);
    return (
      exported: s.exported.length,
      problems: [for (final f in s.failures) '${f.clip.title}: ${f.message}'],
    );
  }
}
