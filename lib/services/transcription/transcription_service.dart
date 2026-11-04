import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/processing_job.dart';
import '../../database/models/project.dart';
import '../../database/models/transcript.dart';
import '../../database/models/video_record.dart';
import '../../database/repositories/processing_job_repository.dart';
import '../../database/repositories/project_repository.dart';
import '../../database/repositories/transcript_repository.dart';
import '../ffmpeg/ffmpeg_service.dart';
import '../storage/app_paths.dart';
import 'transcription_engine.dart';
import 'transcription_models.dart';
import 'whisper_model_manager.dart';

/// Pipeline STEP 9: video -> audio WAV 16 kHz mono (FFmpeg) -> STT lokal ->
/// segmen {start, end, text} -> SQLite.
///
/// Berjalan SEQUENTIAL (satu transkripsi pada satu waktu) agar RAM/CPU
/// ponsel kelas bawah tidak kewalahan. File audio sementara selalu dihapus.
class TranscriptionService {
  TranscriptionService({
    required FFmpegService ffmpeg,
    required TranscriptionEngine engine,
    required this.models,
    required this.transcripts,
    required ProjectRepository projects,
    required ProcessingJobRepository jobs,
    required AppPaths paths,
  })  : _ffmpeg = ffmpeg,
        _engine = engine,
        _projects = projects,
        _jobs = jobs,
        _paths = paths;

  final FFmpegService _ffmpeg;
  final TranscriptionEngine _engine;
  final ProjectRepository _projects;
  final ProcessingJobRepository _jobs;
  final AppPaths _paths;

  final WhisperModelManager models;
  final TranscriptRepository transcripts;

  bool _running = false;
  bool get isRunning => _running;

  static const _extractShare = 0.15;
  static const _transcribeShare = 0.82;

  Future<TranscriptionOutcome> transcribe({
    required VideoRecord video,
    required WhisperModelInfo model,
    String language = 'id',
    int threads = 2,
    CancelToken? cancel,
    void Function(TranscriptionProgress progress)? onProgress,
  }) async {
    if (_running) {
      throw const AppException(
        'Transkripsi lain sedang berjalan. Tunggu sampai selesai.',
        code: 'busy',
      );
    }
    if (!await File(video.filePath).exists()) {
      throw const AppException(
        'File video tidak ditemukan. Pilih ulang video untuk project ini.',
        code: 'video_missing',
      );
    }
    if (!await models.isInstalled(model)) throw modelMissing(model);
    final files = await models.resolve(model);

    _running = true;
    final projectId = video.projectId;
    final previous = await transcripts.getByProject(projectId);
    final restoreStatus =
        previous != null ? ProjectStatus.transcribed : ProjectStatus.videoAdded;

    final job = await _jobs.enqueue(
      projectId: projectId,
      type: JobType.transcribe,
      payload: jsonEncode({'model': model.id, 'language': language}),
    );
    final jobId = job.id!;
    var lastSavedProgress = 0.0;

    void report(TranscriptionPhase phase, double fraction) {
      final f = fraction.clamp(0.0, 1.0).toDouble();
      onProgress?.call(TranscriptionProgress(phase, f));
      if (f - lastSavedProgress >= 0.05) {
        lastSavedProgress = f;
        _jobs.updateProgress(jobId, f).catchError((Object e) {
          AppLogger.e('Gagal menyimpan progres job', e);
        });
      }
    }

    String? wavPath;
    try {
      await _jobs.updateStatus(jobId, JobStatus.running);
      await _projects.updateStatus(projectId, ProjectStatus.transcribing);

      await _paths.ensureProjectDir(projectId);
      wavPath = p.join(_paths.projectTempDir(projectId).path, 'stt_audio.wav');

      // 1) Ekstrak audio.
      final taskId = 'stt-audio-$projectId';
      final stopListening = cancel?.onCancel(() => _ffmpeg.cancel(taskId));
      report(TranscriptionPhase.extractingAudio, 0);
      final extracted = await _ffmpeg.extractAudio(
        inputPath: video.filePath,
        outputPath: wavPath,
        durationMs: video.durationMs > 0 ? video.durationMs : null,
        onProgress: (f) =>
            report(TranscriptionPhase.extractingAudio, f * _extractShare),
        taskId: taskId,
      );
      stopListening?.call();

      if (extracted.cancelled || (cancel?.isCancelled ?? false)) {
        return await _finishCancelled(jobId, projectId, restoreStatus);
      }
      if (!extracted.ok) {
        throw AppException(
          extracted.message ??
              'Audio tidak dapat diekstrak. Video mungkin tidak memiliki suara.',
          code: 'audio_extract_failed',
        );
      }

      // 2) Speech-to-text lokal.
      report(TranscriptionPhase.transcribing, _extractShare);
      final List<RawSegment> raw;
      try {
        raw = await _engine.transcribe(
          wavPath: wavPath,
          files: files,
          language: language,
          threads: threads,
          cancel: cancel,
          onProgress: (f) => report(
            TranscriptionPhase.transcribing,
            _extractShare + f * _transcribeShare,
          ),
        );
      } on TranscriptionCancelled {
        return await _finishCancelled(jobId, projectId, restoreStatus);
      }

      final segments = _normalize(raw, video.durationMs);
      if (segments.isEmpty) {
        throw const AppException(
          'Tidak ada ucapan yang terdeteksi pada video ini.',
          code: 'no_speech',
        );
      }

      // 3) Simpan (atomik; transcript lama diganti hanya bila ini sukses).
      report(TranscriptionPhase.saving, 0.98);
      final transcriptId = await transcripts.replaceForProject(
        Transcript(
          projectId: projectId,
          videoId: video.id ?? 0,
          language: language.isEmpty ? 'auto' : language,
          engine: '${_engine.name}-${model.id}',
          createdAt: DateTime.now(),
        ),
        segments,
      );

      await _jobs.updateStatus(jobId, JobStatus.completed);
      await _projects.updateStatus(projectId, ProjectStatus.transcribed);
      onProgress?.call(const TranscriptionProgress(
          TranscriptionPhase.saving, 1.0));
      return TranscriptionOutcome(
        transcriptId: transcriptId,
        segmentCount: segments.length,
      );
    } on AppException catch (e) {
      await _markFailed(jobId, projectId, restoreStatus, e.message);
      rethrow;
    } catch (e, st) {
      AppLogger.e('Transkripsi gagal', e, st);
      const msg = 'Transkripsi gagal. Coba lagi atau pilih model lain.';
      await _markFailed(jobId, projectId, restoreStatus, msg);
      throw const AppException(msg, code: 'transcribe_failed');
    } finally {
      _running = false;
      if (wavPath != null) {
        try {
          final f = File(wavPath);
          if (await f.exists()) await f.delete();
        } on FileSystemException catch (e) {
          AppLogger.e('Gagal menghapus audio sementara', e);
        }
      }
    }
  }

  Future<TranscriptionOutcome> _finishCancelled(
    int jobId,
    int projectId,
    ProjectStatus restoreStatus,
  ) async {
    await _jobs.updateStatus(jobId, JobStatus.cancelled);
    await _projects.updateStatus(projectId, restoreStatus);
    return const TranscriptionOutcome(cancelled: true);
  }

  Future<void> _markFailed(
    int jobId,
    int projectId,
    ProjectStatus restoreStatus,
    String message,
  ) async {
    try {
      await _jobs.updateStatus(jobId, JobStatus.failed, errorMessage: message);
      await _projects.updateStatus(projectId, restoreStatus);
    } catch (e) {
      AppLogger.e('Gagal memperbarui status setelah error', e);
    }
  }

  /// Merapikan hasil mesin: teks di-trim, waktu dijaga dalam rentang video
  /// dan berurutan, segmen kosong/terbalik dibuang.
  List<TranscriptSegment> _normalize(List<RawSegment> raw, int durationMs) {
    final sorted = [...raw]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final out = <TranscriptSegment>[];
    for (final r in sorted) {
      final text = r.text.trim();
      if (text.isEmpty) continue;
      final start = r.startMs < 0 ? 0 : r.startMs;
      var end = r.endMs;
      if (durationMs > 0 && end > durationMs) end = durationMs;
      if (end <= start) continue;
      out.add(TranscriptSegment(startMs: start, endMs: end, text: text));
    }
    return out;
  }
}
