import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/clip_candidate.dart';
import '../../database/models/processing_job.dart';
import '../../database/models/project.dart';
import '../../database/repositories/clip_candidate_repository.dart';
import '../../database/repositories/processing_job_repository.dart';
import '../../database/repositories/project_repository.dart';
import '../../database/repositories/transcript_repository.dart';
import 'clip_detector.dart';

/// STEP 11: transcript tersimpan -> kandidat clip di SQLite.
/// Seluruhnya offline; tidak ada layanan AI berbayar/cloud.
class ClipDetectionService {
  ClipDetectionService({
    required ClipDetector detector,
    required TranscriptRepository transcripts,
    required this.candidates,
    required ProjectRepository projects,
    required ProcessingJobRepository jobs,
  })  : _detector = detector,
        _transcripts = transcripts,
        _projects = projects,
        _jobs = jobs;

  final ClipDetector _detector;
  final TranscriptRepository _transcripts;
  final ProjectRepository _projects;
  final ProcessingJobRepository _jobs;
  final ClipCandidateRepository candidates;

  bool _running = false;

  /// Mengembalikan kandidat yang tersimpan (urut skor tertinggi).
  ///
  /// Menjalankan ulang MENGGANTI kandidat lama, termasuk status
  /// accepted/rejected dari review sebelumnya.
  Future<List<ClipCandidate>> detect({
    required int projectId,
    required int videoDurationMs,
    DetectionOptions options = const DetectionOptions(),
  }) async {
    if (_running) {
      throw const AppException('Deteksi clip sedang berjalan.', code: 'busy');
    }
    final transcript = await _transcripts.getByProject(projectId);
    if (transcript == null) {
      throw const AppException(
        'Buat transcript dulu sebelum mendeteksi clip.',
        code: 'no_transcript',
      );
    }
    final segments = await _transcripts.getSegments(transcript.id!);
    if (segments.isEmpty) {
      throw const AppException(
        'Transcript kosong. Buat ulang transcript.',
        code: 'empty_transcript',
      );
    }

    _running = true;
    final previous = (await _projects.getById(projectId))?.status;
    final job = await _jobs.enqueue(
      projectId: projectId,
      type: JobType.analyze,
      payload: jsonEncode({
        'detector': _detector.name,
        'minMs': options.minMs,
        'maxMs': options.maxMs,
        'maxClips': options.maxClips,
      }),
    );
    final jobId = job.id!;

    try {
      await _jobs.updateStatus(jobId, JobStatus.running);
      await _projects.updateStatus(projectId, ProjectStatus.analyzing);

      final found = await _detector.detect(
        segments: segments,
        videoDurationMs: videoDurationMs,
        options: options,
      );
      if (found.isEmpty) {
        throw const AppException(
          'Tidak ditemukan bagian yang layak dijadikan clip. Coba durasi '
          'yang lebih pendek atau periksa transcript.',
          code: 'no_candidates',
        );
      }

      final now = DateTime.now();
      await candidates.replaceForProject(projectId, [
        for (final c in found)
          ClipCandidate(
            projectId: projectId,
            startMs: c.startMs,
            endMs: c.endMs,
            title: c.title,
            hook: c.hook,
            score: c.score,
            reason: c.reason,
            createdAt: now,
          ),
      ]);

      await _jobs.updateStatus(jobId, JobStatus.completed);
      await _projects.updateStatus(projectId, ProjectStatus.analyzed);
      return await candidates.getByProject(projectId);
    } on AppException catch (e) {
      await _fail(jobId, projectId, previous, e.message);
      rethrow;
    } catch (e, st) {
      AppLogger.e('Deteksi clip gagal', e, st);
      const msg = 'Deteksi clip gagal. Coba lagi.';
      await _fail(jobId, projectId, previous, msg);
      throw const AppException(msg, code: 'detect_failed');
    } finally {
      _running = false;
    }
  }

  Future<void> _fail(
    int jobId,
    int projectId,
    ProjectStatus? previous,
    String message,
  ) async {
    try {
      await _jobs.updateStatus(jobId, JobStatus.failed, errorMessage: message);
      await _projects.updateStatus(
          projectId, previous ?? ProjectStatus.transcribed);
    } catch (e) {
      AppLogger.e('Gagal memperbarui status setelah error', e);
    }
  }
}
