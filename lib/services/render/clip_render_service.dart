import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/clip.dart';
import '../../database/models/clip_candidate.dart';
import '../../database/models/clip_edit.dart';
import '../../database/models/processing_job.dart';
import '../../database/models/project.dart';
import '../../database/models/video_record.dart';
import '../../database/repositories/clip_candidate_repository.dart';
import '../../database/repositories/clip_edit_repository.dart';
import '../../database/repositories/clip_repository.dart';
import '../../database/repositories/processing_job_repository.dart';
import '../../database/repositories/project_repository.dart';
import '../../database/repositories/subtitle_settings_repository.dart';
import '../../database/repositories/transcript_repository.dart';
import '../../features/clips/clip_range.dart';
import '../../features/video/media_probe.dart';
import '../ffmpeg/ffmpeg_models.dart';
import '../ffmpeg/ffmpeg_service.dart';
import '../ffmpeg/portrait_plan.dart';
import '../face/face_detector.dart';
import '../face/face_models.dart';
import '../face/focus_planner.dart';
import '../ffmpeg/subtitle_overlay.dart';
import '../storage/app_paths.dart';
import '../subtitle/subtitle_cue.dart';
import '../settings/app_settings.dart';
import '../subtitle/subtitle_renderer.dart';
import '../subtitle/subtitle_style.dart';
import '../transcription/transcription_models.dart';

/// Pembuat gambar subtitle. Default memakai [SubtitleRenderer]; dapat
/// diganti saat testing karena renderer asli membutuhkan mesin Flutter.
typedef SubtitleOverlayBuilder = Future<List<SubtitleOverlay>> Function({
  required List<SubtitleCue> cues,
  required SubtitleStyle style,
  required int outWidth,
  required int outHeight,
  required Directory outDir,
});

Future<List<SubtitleOverlay>> _defaultOverlayBuilder({
  required List<SubtitleCue> cues,
  required SubtitleStyle style,
  required int outWidth,
  required int outHeight,
  required Directory outDir,
}) =>
    SubtitleRenderer().render(
      cues: cues,
      style: style,
      outWidth: outWidth,
      outHeight: outHeight,
      outDir: outDir,
    );

class RenderProgress {
  const RenderProgress({
    required this.index,
    required this.total,
    required this.title,
    required this.clipFraction,
  });

  /// Urutan clip yang sedang dirender (mulai 1).
  final int index;
  final int total;
  final String title;

  /// Progres clip saat ini, 0.0 - 1.0.
  final double clipFraction;

  double get overall => ((index - 1) + clipFraction) / total;
}

class RerenderOutcome {
  const RerenderOutcome({
    this.ok = false,
    this.cancelled = false,
    this.message,
    this.note,
    this.warning,
  });

  final bool ok;
  final bool cancelled;

  /// Pesan ramah bila gagal.
  final String? message;
  final String? note;
  final String? warning;
}

class RenderFailure {
  const RenderFailure(this.title, this.message);

  final String title;
  final String message;
}

class RenderSummary {
  const RenderSummary({
    this.succeeded = 0,
    this.failures = const [],
    this.warnings = const [],
    this.notes = const [],
    this.cancelled = false,
  });

  final int succeeded;
  final List<RenderFailure> failures;
  final List<String> warnings;

  /// Info non-masalah, mis. posisi crop wajah per clip.
  final List<String> notes;
  final bool cancelled;
}

/// STEP 13: kandidat yang DITERIMA -> clip portrait 9:16 (+ subtitle) di
/// storage lokal. Dirender SATU PER SATU lewat antrean FFmpeg (aman untuk
/// RAM/CPU ponsel kelas bawah). Video asli tidak pernah diubah.
class ClipRenderService {
  ClipRenderService({
    required FFmpegService ffmpeg,
    required MediaProbe probe,
    required AppPaths paths,
    required this.clips,
    required this.candidates,
    required this.edits,
    required TranscriptRepository transcripts,
    required SubtitleSettingsRepository subtitleSettings,
    required ProjectRepository projects,
    required ProcessingJobRepository jobs,
    VideoFaceDetector? faceDetector,
    SubtitleOverlayBuilder overlayBuilder = _defaultOverlayBuilder,
    AppSettings Function()? settings,
  })  : _settings = settings,
        _ffmpeg = ffmpeg,
        _probe = probe,
        _paths = paths,
        _transcripts = transcripts,
        _subtitleSettings = subtitleSettings,
        _projects = projects,
        _jobs = jobs,
        _faceDetector = faceDetector,
        _overlayBuilder = overlayBuilder;

  /// Pengaturan server (null = perilaku bawaan: margin 100 MB, resolusi otomatis).
  final AppSettings Function()? _settings;
  final FFmpegService _ffmpeg;
  final MediaProbe _probe;
  final AppPaths _paths;
  final TranscriptRepository _transcripts;
  final SubtitleSettingsRepository _subtitleSettings;
  final ProjectRepository _projects;
  final ProcessingJobRepository _jobs;
  final VideoFaceDetector? _faceDetector;
  final SubtitleOverlayBuilder _overlayBuilder;

  final ClipRepository clips;
  final ClipCandidateRepository candidates;
  final ClipEditRepository edits;

  bool _running = false;
  bool get isRunning => _running;

  /// Perkiraan kebutuhan ruang per detik clip (bitrate tinggi, margin aman).
  static const _bytesPerSecond = 1200 * 1024;
  static const _safetyMarginBytes = 100 * 1024 * 1024;

  int get _safetyMargin => _settings?.call().minFreeStorageBytes ?? _safetyMarginBytes;

  Future<int> acceptedCount(int projectId) async =>
      (await candidates.getByProject(projectId))
          .where((c) => c.status == CandidateStatus.accepted)
          .length;

  Future<RenderSummary> renderAccepted({
    required VideoRecord video,
    bool burnSubtitles = true,
    bool faceAware = true,
    CancelToken? cancel,
    void Function(RenderProgress progress)? onProgress,
  }) async {
    if (_running) {
      throw const AppException('Render lain sedang berjalan.', code: 'busy');
    }
    final projectId = video.projectId;

    final accepted = (await candidates.getByProject(projectId))
        .where((c) => c.status == CandidateStatus.accepted)
        .toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (accepted.isEmpty) {
      throw const AppException(
        'Belum ada clip yang diterima. Terima kandidat di layar Review dulu.',
        code: 'no_accepted',
      );
    }
    if (!await File(video.filePath).exists()) {
      throw const AppException(
        'File video tidak ditemukan. Pilih ulang video untuk project ini.',
        code: 'video_missing',
      );
    }

    await _paths.ensureProjectDir(projectId);
    final needed = accepted.fold<int>(
            0, (sum, c) => sum + ((c.endMs - c.startMs) ~/ 1000) * _bytesPerSecond) +
        _safetyMargin;
    final free = await _probe.freeSpaceBytes(_paths.projectClipsDir(projectId).path);
    if (free < needed) {
      throw const InsufficientStorageException();
    }

    final previous = (await _projects.getById(projectId))?.status;
    _running = true;
    var succeeded = 0;
    var cancelled = false;
    final failures = <RenderFailure>[];
    final warnings = <String>[];
    final notes = <String>[];

    try {
      await _projects.updateStatus(projectId, ProjectStatus.rendering);

      for (var i = 0; i < accepted.length; i++) {
        if (cancel?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        final cand = accepted[i];
        final outcome = await _renderOne(
          video: video,
          candidate: cand,
          index: i + 1,
          total: accepted.length,
          burnSubtitles: burnSubtitles,
          faceAware: faceAware,
          cancel: cancel,
          onProgress: onProgress,
        );
        if (outcome.warning != null) {
          warnings.add('${cand.title}: ${outcome.warning}');
        }
        if (outcome.note != null) notes.add('${cand.title}: ${outcome.note}');
        switch (outcome.status) {
          case _Status.success:
            succeeded++;
          case _Status.failed:
            failures.add(RenderFailure(cand.title, outcome.message!));
          case _Status.cancelled:
            cancelled = true;
        }
        if (cancelled) break;
      }
    } finally {
      _running = false;
      try {
        final existing = await clips.getByProject(projectId);
        final hasDone = existing.any((c) => c.status == ClipStatus.completed);
        await _projects.updateStatus(
          projectId,
          hasDone ? ProjectStatus.completed : (previous ?? ProjectStatus.analyzed),
        );
      } catch (e) {
        AppLogger.e('Gagal memperbarui status project', e);
      }
    }

    return RenderSummary(
      succeeded: succeeded,
      failures: failures,
      warnings: warnings,
      notes: notes,
      cancelled: cancelled,
    );
  }

  Future<_Outcome> _renderOne({
    required VideoRecord video,
    required ClipCandidate candidate,
    required int index,
    required int total,
    required bool burnSubtitles,
    required bool faceAware,
    CancelToken? cancel,
    void Function(RenderProgress progress)? onProgress,
  }) async {
    final projectId = video.projectId;
    final durationMs = candidate.endMs - candidate.startMs;

    void report(double f) => onProgress?.call(RenderProgress(
          index: index,
          total: total,
          title: candidate.title,
          clipFraction: f.clamp(0.0, 1.0).toDouble(),
        ));

    final job = await _jobs.enqueue(
      projectId: projectId,
      type: JobType.renderClip,
      payload: jsonEncode({'candidateId': candidate.id}),
    );
    final jobId = job.id!;

    final clipId = await clips.insert(Clip(
      projectId: projectId,
      candidateId: candidate.id,
      startMs: candidate.startMs,
      endMs: candidate.endMs,
      durationMs: durationMs,
      title: candidate.title,
      score: candidate.score,
      status: ClipStatus.rendering,
      createdAt: DateTime.now(),
    ));

    final out = File(p.join(_paths.projectClipsDir(projectId).path, 'clip_$clipId.mp4'));
    final subsDir = Directory(
        p.join(_paths.projectTempDir(projectId).path, 'subs_$clipId'));
    String? warning;
    String? note;

    Future<_Outcome> abort(_Status status, String? message) async {
      try {
        await clips.delete(clipId);
        if (await out.exists()) await out.delete();
        await _jobs.updateStatus(
          jobId,
          status == _Status.cancelled ? JobStatus.cancelled : JobStatus.failed,
          errorMessage: message,
        );
      } catch (e) {
        AppLogger.e('Pembersihan setelah render gagal', e);
      }
      return _Outcome(status, message: message, warning: warning, note: note);
    }

    try {
      await _jobs.updateStatus(jobId, JobStatus.running);
      report(0);

      var mode = PortraitCropMode.centerCrop;
      double? focusX;
      double? focusY;
      if (faceAware) {
        final r = await _faceFocus(video, candidate.startMs, candidate.endMs);
        note = r.note;
        if (r.focus != null) {
          mode = PortraitCropMode.faceAwareCrop;
          focusX = r.focus!.x;
          focusY = r.focus!.y;
        }
      }

      final taskId = 'render-$clipId';
      final enc = await _encode(
        video: video,
        startMs: candidate.startMs,
        endMs: candidate.endMs,
        outPath: out.path,
        taskId: taskId,
        subsDir: subsDir,
        mode: mode,
        focusX: focusX,
        focusY: focusY,
        burnSubtitles: burnSubtitles,
        cancel: cancel,
        onFraction: report,
      );
      final result = enc.result;
      final plan = enc.plan;
      warning = enc.warning;

      if (result.cancelled) return await abort(_Status.cancelled, null);
      if (!result.ok) {
        return await abort(_Status.failed, result.message ?? 'Render clip gagal.');
      }
      if (!await out.exists() || await out.length() == 0) {
        return await abort(_Status.failed, 'Hasil render kosong. Coba lagi.');
      }

      String? thumb;
      try {
        await _paths.thumbnails.create(recursive: true);
        final thumbPath = p.join(_paths.thumbnails.path, 'clip_$clipId.jpg');
        final ok = await _probe.generateThumbnail(
          videoPath: out.path,
          outputPath: thumbPath,
          positionMs: math.min(1000, durationMs ~/ 2),
        );
        if (ok && await File(thumbPath).exists()) thumb = thumbPath;
      } catch (e) {
        AppLogger.e('Thumbnail clip gagal (diabaikan)', e);
      }

      await clips.markCompleted(
        clipId,
        filePath: out.path,
        thumbnailPath: thumb,
        durationMs: durationMs,
        width: plan.outputWidth,
        height: plan.outputHeight,
      );
      await candidates.updateStatus(candidate.id!, CandidateStatus.generated);
      await _jobs.updateStatus(jobId, JobStatus.completed);
      report(1);
      return _Outcome(_Status.success, warning: warning, note: note);
    } on AppException catch (e) {
      return await abort(_Status.failed, e.message);
    } catch (e, st) {
      AppLogger.e('Render clip gagal', e, st);
      return await abort(_Status.failed, 'Render clip gagal. Coba lagi.');
    } finally {
      try {
        if (await subsDir.exists()) await subsDir.delete(recursive: true);
      } on FileSystemException catch (e) {
        AppLogger.e('Gagal membersihkan gambar subtitle', e);
      }
    }
  }

  /// Mendeteksi titik fokus wajah untuk rentang clip. Kegagalan APA PUN
  /// menghasilkan fokus null (pemanggil memakai crop tengah) dan catatan.
  Future<({FocusResult? focus, String note})> _faceFocus(
    VideoRecord video,
    int startMs,
    int endMs,
  ) async {
    final detector = _faceDetector;
    if (detector == null) {
      return (focus: null, note: 'detektor wajah tidak tersedia, memakai crop tengah');
    }
    try {
      final samples = await detector.detect(
        videoPath: video.filePath,
        timesMs: sampleTimes(startMs, endMs),
      );
      final focus = planFocus(samples);
      if (focus == null) {
        return (focus: null, note: 'wajah tidak terdeteksi, memakai crop tengah');
      }
      return (
        focus: focus,
        note: 'crop mengikuti wajah (posisi ${(focus.x * 100).round()}%, '
            'terdeteksi di ${focus.hits}/${focus.samples} frame)',
      );
    } catch (e, st) {
      AppLogger.e('Deteksi wajah gagal (memakai crop tengah)', e, st);
      return (focus: null, note: 'deteksi wajah gagal, memakai crop tengah');
    }
  }

  /// Untuk editor: titik fokus wajah pada rentang clip (null bila tidak ada).
  Future<FocusResult?> detectFocus(VideoRecord video, int startMs, int endMs) async =>
      (await _faceFocus(video, startMs, endMs)).focus;

  /// Untuk editor: satu frame diam dari video sumber (path JPEG) atau null.
  Future<String?> previewFrame(VideoRecord video, int positionMs) async {
    try {
      final dir = _paths.projectTempDir(video.projectId);
      await dir.create(recursive: true);
      final path = p.join(dir.path, 'edit_frame_$positionMs.jpg');
      final ok = await _probe.generateThumbnail(
        videoPath: video.filePath,
        outputPath: path,
        positionMs: positionMs,
        maxWidth: 720,
      );
      return (ok && await File(path).exists()) ? path : null;
    } catch (e) {
      AppLogger.e('Frame pratinjau gagal', e);
      return null;
    }
  }

  Future<SubtitleStyle> projectSubtitleStyle(int projectId) =>
      _subtitleSettings.getForProject(projectId);

  /// Encode satu clip: rencana crop, gambar subtitle, lalu FFmpeg.
  /// Dipakai render awal maupun render ulang dari editor.
  Future<({FFmpegResult result, PortraitPlan plan, String? warning})> _encode({
    required VideoRecord video,
    required int startMs,
    required int endMs,
    required String outPath,
    required String taskId,
    required Directory subsDir,
    required PortraitCropMode mode,
    double? focusX,
    double? focusY,
    double zoom = 1.0,
    required bool burnSubtitles,
    SubtitleStyle? style,
    CancelToken? cancel,
    required void Function(double fraction) onFraction,
  }) async {
    final plan = planPortrait(
      sourceWidth: video.width,
      sourceHeight: video.height,
      mode: mode,
      focusX: focusX,
      focusY: focusY,
      zoom: zoom,
      resolution: _settings?.call().resolution ?? PortraitResolution.auto,
    );

    String? warning;
    var overlays = <SubtitleOverlay>[];
    if (burnSubtitles) {
      final transcript = await _transcripts.getByProject(video.projectId);
      if (transcript != null) {
        final segs = await _transcripts.getSegmentsInRange(
            transcript.id!, startMs, endMs);
        final st = style ?? await _subtitleSettings.getForProject(video.projectId);
        final cues = buildCues(
          segments: segs,
          clipStartMs: startMs,
          clipEndMs: endMs,
          maxCharsPerLine: st.maxCharsPerLine,
        );
        if (cues.length > maxSubtitleOverlays) {
          warning = 'subtitle terlalu banyak, dirender tanpa subtitle';
        } else if (cues.isNotEmpty) {
          overlays = await _overlayBuilder(
            cues: cues,
            style: st,
            outWidth: plan.outputWidth,
            outHeight: plan.outputHeight,
            outDir: subsDir,
          );
        }
      }
    }

    if (cancel?.isCancelled ?? false) {
      return (
        result: const FFmpegResult(status: FFmpegStatus.cancelled),
        plan: plan,
        warning: warning,
      );
    }

    final stop = cancel?.onCancel(() => _ffmpeg.cancel(taskId));
    try {
      final result = overlays.isNotEmpty
          ? await _ffmpeg.burnSubtitle(
              inputPath: video.filePath,
              outputPath: outPath,
              overlays: overlays,
              plan: plan,
              startMs: startMs,
              endMs: endMs,
              onProgress: onFraction,
              taskId: taskId,
            )
          : await _ffmpeg.cropPortrait(
              inputPath: video.filePath,
              outputPath: outPath,
              plan: plan,
              startMs: startMs,
              endMs: endMs,
              onProgress: onFraction,
              taskId: taskId,
            );
      return (result: result, plan: plan, warning: warning);
    } finally {
      stop?.call();
    }
  }

  /// STEP 15: render ulang satu clip dengan pengaturan hasil edit.
  ///
  /// Hasil baru ditulis ke file sementara lalu MENGGANTIKAN file lama hanya
  /// bila sukses; bila gagal/dibatalkan, clip lama tetap utuh.
  Future<RerenderOutcome> rerenderClip({
    required VideoRecord video,
    required Clip clip,
    required ClipEdit edit,
    required int startMs,
    required int endMs,
    required String title,
    CancelToken? cancel,
    void Function(double fraction)? onProgress,
  }) async {
    if (_running) {
      throw const AppException('Render lain sedang berjalan.', code: 'busy');
    }
    final t = title.trim();
    if (t.isEmpty) {
      throw const AppException('Judul tidak boleh kosong.', code: 'empty_title');
    }
    final range = normalizeRange(
      startMs: startMs,
      endMs: endMs,
      videoDurationMs: video.durationMs,
    );
    if (!await File(video.filePath).exists()) {
      throw const AppException(
        'File video tidak ditemukan. Pilih ulang video untuk project ini.',
        code: 'video_missing',
      );
    }

    final projectId = video.projectId;
    await _paths.ensureProjectDir(projectId);
    final needed = ((range.endMs - range.startMs) ~/ 1000) * _bytesPerSecond +
        _safetyMargin;
    final free = await _probe.freeSpaceBytes(_paths.projectClipsDir(projectId).path);
    if (free < needed) throw const InsufficientStorageException();

    final clipsDir = _paths.projectClipsDir(projectId).path;
    final finalPath = clip.filePath ?? p.join(clipsDir, 'clip_${clip.id}.mp4');
    final tmp = File(p.join(clipsDir, 'clip_${clip.id}_edit.mp4'));
    final subsDir =
        Directory(p.join(_paths.projectTempDir(projectId).path, 'subs_edit_${clip.id}'));

    final job = await _jobs.enqueue(
      projectId: projectId,
      type: JobType.renderClip,
      payload: jsonEncode({'clipId': clip.id, 'edit': true}),
    );
    final jobId = job.id!;
    _running = true;

    Future<RerenderOutcome> finish(JobStatus st, RerenderOutcome o) async {
      try {
        if (await tmp.exists()) await tmp.delete();
        await _jobs.updateStatus(jobId, st, errorMessage: o.message);
      } catch (e) {
        AppLogger.e('Pembersihan setelah render ulang gagal', e);
      }
      return o;
    }

    try {
      await _jobs.updateStatus(jobId, JobStatus.running);
      onProgress?.call(0);

      var mode = PortraitCropMode.centerCrop;
      double? fx;
      double? fy;
      var zoom = 1.0;
      String? note;
      switch (edit.cropMode) {
        case EditCropMode.center:
          break;
        case EditCropMode.face:
          final r = await _faceFocus(video, range.startMs, range.endMs);
          note = r.note;
          if (r.focus != null) {
            mode = PortraitCropMode.faceAwareCrop;
            fx = r.focus!.x;
            fy = r.focus!.y;
          }
        case EditCropMode.manual:
          mode = PortraitCropMode.manualCrop;
          fx = edit.focusX ?? 0.5;
          fy = edit.focusY ?? 0.5;
          zoom = edit.zoom;
      }

      final enc = await _encode(
        video: video,
        startMs: range.startMs,
        endMs: range.endMs,
        outPath: tmp.path,
        taskId: 'edit-${clip.id}',
        subsDir: subsDir,
        mode: mode,
        focusX: fx,
        focusY: fy,
        zoom: zoom,
        burnSubtitles: edit.burnSubtitles,
        style: edit.style,
        cancel: cancel,
        onFraction: (f) => onProgress?.call(f.clamp(0.0, 1.0).toDouble()),
      );

      if (enc.result.cancelled) {
        return await finish(JobStatus.cancelled, const RerenderOutcome(cancelled: true));
      }
      if (!enc.result.ok) {
        return await finish(
          JobStatus.failed,
          RerenderOutcome(message: enc.result.message ?? 'Render ulang gagal.'),
        );
      }
      if (!await tmp.exists() || await tmp.length() == 0) {
        return await finish(
          JobStatus.failed,
          const RerenderOutcome(message: 'Hasil render kosong. Coba lagi.'),
        );
      }

      // Ganti file lama dengan yang baru (rename di partisi yang sama).
      try {
        await tmp.rename(finalPath);
      } on FileSystemException catch (e) {
        AppLogger.e('Gagal mengganti file clip', e);
        return await finish(
          JobStatus.failed,
          const RerenderOutcome(message: 'Hasil edit tidak dapat disimpan.'),
        );
      }

      String? thumb;
      try {
        await _paths.thumbnails.create(recursive: true);
        final thumbPath = p.join(_paths.thumbnails.path, 'clip_${clip.id}.jpg');
        final ok = await _probe.generateThumbnail(
          videoPath: finalPath,
          outputPath: thumbPath,
          positionMs: math.min(1000, (range.endMs - range.startMs) ~/ 2),
        );
        if (ok && await File(thumbPath).exists()) thumb = thumbPath;
      } catch (e) {
        AppLogger.e('Thumbnail clip gagal (diabaikan)', e);
      }

      await clips.markEdited(
        clip.id!,
        title: t,
        startMs: range.startMs,
        endMs: range.endMs,
        thumbnailPath: thumb,
        width: enc.plan.outputWidth,
        height: enc.plan.outputHeight,
      );
      await edits.save(edit);
      onProgress?.call(1);
      return await finish(
        JobStatus.completed,
        RerenderOutcome(ok: true, note: note, warning: enc.warning),
      );
    } on AppException catch (e) {
      return await finish(JobStatus.failed, RerenderOutcome(message: e.message));
    } catch (e, st) {
      AppLogger.e('Render ulang gagal', e, st);
      return await finish(
        JobStatus.failed,
        const RerenderOutcome(message: 'Render ulang gagal. Coba lagi.'),
      );
    } finally {
      _running = false;
      try {
        if (await subsDir.exists()) await subsDir.delete(recursive: true);
      } on FileSystemException catch (e) {
        AppLogger.e('Gagal membersihkan gambar subtitle', e);
      }
    }
  }

  /// Menghapus clip hasil render (file, thumbnail, baris DB). Kandidatnya
  /// kembali berstatus `accepted` agar dapat dirender ulang.
  /// File hanya dihapus bila berada di dalam folder aplikasi.
  Future<void> deleteClip(Clip clip) async {
    for (final path in [clip.filePath, clip.thumbnailPath]) {
      if (path == null) continue;
      if (!p.isWithin(_paths.root.path, path)) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } on FileSystemException catch (e) {
        AppLogger.e('Gagal menghapus file clip', e);
      }
    }
    await clips.delete(clip.id!);
    final cid = clip.candidateId;
    if (cid != null) {
      final cand = await candidates.getById(cid);
      if (cand != null && cand.status == CandidateStatus.generated) {
        await candidates.updateStatus(cid, CandidateStatus.accepted);
      }
    }
  }
}

enum _Status { success, failed, cancelled }

class _Outcome {
  const _Outcome(this.status, {this.message, this.warning, this.note});

  final _Status status;
  final String? message;
  final String? warning;
  final String? note;
}
