import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/clip.dart';
import '../../database/models/export_record.dart';
import '../../database/models/transcript.dart';
import '../../database/repositories/export_repository.dart';
import '../../database/repositories/transcript_repository.dart';
import '../storage/app_paths.dart';
import '../transcription/transcript_formats.dart';
import 'gallery_exporter.dart';

/// Nama file aman untuk galeri: tanpa karakter terlarang, maks 60 huruf,
/// diakhiri id clip agar unik dan mudah dikenali.
String safeExportName(String title, int clipId, String extension) {
  var base = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (base.length > 60) base = base.substring(0, 60).trim();
  if (base.isEmpty) base = 'clip';
  return '$base #$clipId.$extension';
}

/// SRT khusus satu clip: segmen transcript yang beririsan dengan rentang clip,
/// waktunya digeser agar dimulai dari 0 dan dipotong sesuai durasi clip.
String buildClipSrt(List<TranscriptSegment> segments, int startMs, int endMs) {
  final length = endMs - startMs;
  final shifted = <TranscriptSegment>[];
  for (final s in segments) {
    if (s.endMs <= startMs || s.startMs >= endMs) continue;
    final a = (s.startMs - startMs).clamp(0, length);
    final b = (s.endMs - startMs).clamp(0, length);
    if (b <= a) continue;
    shifted.add(TranscriptSegment(
        startMs: a.toInt(), endMs: b.toInt(), text: s.text));
  }
  return toSrt(shifted);
}

class ExportProgress {
  const ExportProgress({
    required this.done,
    required this.total,
    required this.currentTitle,
  });

  final int done;
  final int total;
  final String currentTitle;
}

class ExportFailure {
  const ExportFailure(this.clip, this.message);

  final Clip clip;
  final String message;
}

class ExportSummary {
  const ExportSummary({required this.exported, required this.failures});

  final List<ExportRecord> exported;
  final List<ExportFailure> failures;

  bool get allOk => failures.isEmpty;
}

/// Ekspor clip ke galeri (Movies/AI Video Clipper) dan SRT ke Downloads.
/// File asli di folder aplikasi tidak pernah diubah atau dihapus.
class ExportService {
  ExportService({
    required this.exporter,
    required this.exports,
    required this.transcripts,
    required this.paths,
  });

  final GalleryExporter exporter;
  final ExportRepository exports;
  final TranscriptRepository transcripts;
  final AppPaths paths;

  bool _running = false;
  bool get isRunning => _running;

  Future<List<ExportRecord>> history(int projectId) =>
      exports.getByProject(projectId);

  /// Ekspor video satu clip.
  Future<ExportRecord> exportClipVideo(Clip clip) async {
    final path = clip.filePath;
    if (clip.id == null ||
        clip.status != ClipStatus.completed ||
        path == null ||
        !await File(path).exists()) {
      throw const AppException(
        'File clip belum tersedia. Render clip terlebih dahulu.',
        code: 'file_missing',
      );
    }
    final file = await exporter.exportFile(
      sourcePath: path,
      displayName: safeExportName(clip.title, clip.id!, 'mp4'),
      mimeType: 'video/mp4',
      target: ExportTarget.video,
    );
    final record = ExportRecord(
      clipId: clip.id!,
      kind: ExportKind.video,
      displayName: file.displayName,
      uri: file.uri,
      exportedAt: DateTime.now(),
    );
    final id = await exports.insert(record);
    return ExportRecord(
      id: id,
      clipId: record.clipId,
      kind: record.kind,
      displayName: record.displayName,
      uri: record.uri,
      exportedAt: record.exportedAt,
    );
  }

  /// Ekspor banyak clip berurutan (satu per satu, hemat RAM). Kegagalan satu
  /// clip tidak menghentikan clip lain.
  Future<ExportSummary> exportClips(
    List<Clip> clips, {
    CancelFlag? cancel,
    void Function(ExportProgress)? onProgress,
  }) async {
    if (_running) {
      throw const AppException('Ekspor sedang berjalan.', code: 'busy');
    }
    _running = true;
    final done = <ExportRecord>[];
    final failed = <ExportFailure>[];
    try {
      for (var i = 0; i < clips.length; i++) {
        final clip = clips[i];
        onProgress?.call(ExportProgress(
            done: i, total: clips.length, currentTitle: clip.title));
        if (cancel?.isCancelled ?? false) break;
        try {
          done.add(await exportClipVideo(clip));
        } on AppException catch (e) {
          failed.add(ExportFailure(clip, e.message));
          // Izin ditolak berlaku untuk semua clip: hentikan lebih awal.
          if (e.code == 'permission_denied') break;
        } catch (e, st) {
          AppLogger.e('Ekspor clip gagal', e, st);
          failed.add(ExportFailure(clip, 'Clip gagal disimpan ke galeri.'));
        }
      }
      onProgress?.call(ExportProgress(
          done: clips.length, total: clips.length, currentTitle: ''));
      return ExportSummary(exported: done, failures: failed);
    } finally {
      _running = false;
    }
  }

  /// Ekspor subtitle (.srt) satu clip ke Downloads/AI Video Clipper.
  Future<ExportRecord> exportClipSrt(Clip clip) async {
    final id = clip.id;
    if (id == null) {
      throw const AppException('Clip tidak valid.', code: 'invalid_clip');
    }
    final transcript = await transcripts.getByProject(clip.projectId);
    final segments = transcript == null
        ? const <TranscriptSegment>[]
        : await transcripts.getSegmentsInRange(
            transcript.id!, clip.startMs, clip.endMs);
    final srt = buildClipSrt(segments, clip.startMs, clip.endMs);
    if (srt.trim().isEmpty) {
      throw const AppException(
        'Tidak ada transcript pada rentang clip ini, jadi SRT tidak dibuat.',
        code: 'no_transcript',
      );
    }
    final name = safeExportName(clip.title, id, 'srt');
    final tmp = File(p.join(paths.temp.path, 'export_$id.srt'));
    try {
      await tmp.writeAsString(srt);
      final file = await exporter.exportFile(
        sourcePath: tmp.path,
        displayName: name,
        mimeType: 'application/x-subrip',
        target: ExportTarget.download,
      );
      final record = ExportRecord(
        clipId: id,
        kind: ExportKind.srt,
        displayName: file.displayName,
        uri: file.uri,
        exportedAt: DateTime.now(),
      );
      final rid = await exports.insert(record);
      return ExportRecord(
        id: rid,
        clipId: id,
        kind: ExportKind.srt,
        displayName: record.displayName,
        uri: record.uri,
        exportedAt: record.exportedAt,
      );
    } on FileSystemException catch (e) {
      throw StorageException('SRT tidak dapat dibuat.',
          code: 'srt_write_failed', cause: e);
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Bagikan clip lewat share sheet. Bila belum pernah diekspor, diekspor
  /// dulu (agar punya URI MediaStore yang aman dibagikan).
  Future<void> shareClip(Clip clip) async {
    final existing = clip.id == null
        ? <ExportRecord>[]
        : await exports.getByClip(clip.id!);
    // Pakai ekspor lama hanya bila lebih baru dari file clip (belum diedit).
    DateTime? fileTime;
    final path = clip.filePath;
    if (path != null) {
      try {
        fileTime = await File(path).lastModified();
      } on FileSystemException {
        fileTime = null;
      }
    }
    final video = existing.where((e) =>
        e.kind == ExportKind.video &&
        (fileTime == null || !e.exportedAt.isBefore(fileTime)));
    final record = video.isNotEmpty ? video.first : await exportClipVideo(clip);
    await exporter.share(uri: record.uri, mimeType: 'video/mp4');
  }
}

/// Penanda pembatalan sederhana untuk ekspor massal.
class CancelFlag {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
