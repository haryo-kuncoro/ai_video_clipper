import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/video_record.dart';
import '../../services/ffmpeg/ffmpeg_models.dart';
import '../../services/ffmpeg/ffmpeg_service.dart';
import 'player/video_player_panel.dart';

/// Kartu uji SEMENTARA untuk memverifikasi FFmpeg lokal berjalan di perangkat
/// (STEP 6). Hasil ditulis ke folder `temp/` project, tidak mengubah data.
/// Dihapus/diganti pada STEP 13 (rendering otomatis).
class FFmpegTestCard extends StatefulWidget {
  const FFmpegTestCard({
    super.key,
    required this.service,
    required this.video,
    required this.workDir,
  });

  final FFmpegService service;
  final VideoRecord video;
  final Directory workDir;

  @override
  State<FFmpegTestCard> createState() => _FFmpegTestCardState();
}

class _FFmpegTestCardState extends State<FFmpegTestCard> {
  static const _taskId = 'ui-test';

  bool _busy = false;
  double? _progress;
  String? _message;
  String? _cutPath;
  int _cutRun = 0;
  String? _thumbPath;

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
      _message = null;
    });
    try {
      await body();
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Uji FFmpeg gagal', e, st);
      if (mounted) setState(() => _message = 'Proses gagal.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _onProgress(double f) {
    if (mounted) setState(() => _progress = f);
  }

  String _failText(FFmpegResult r) =>
      r.cancelled ? 'Dibatalkan.' : (r.message ?? 'Proses gagal.');

  Future<void> _diagnose() => _guard(() async {
        final d = await widget.service.diagnostics();
        String yn(bool v) => v ? 'ya' : 'TIDAK ADA';
        if (!mounted) return;
        setState(() {
          _message = 'libx264 (H.264): ${yn(d.hasLibx264)}\n'
              'aac: ${yn(d.hasAac)}\n'
              'subtitles/libass: ${yn(d.hasSubtitlesFilter)}\n'
              'drawtext: ${yn(d.hasDrawtextFilter)}';
        });
      });

  Future<void> _cut() => _guard(() async {
        setState(() => _cutPath = null);
        final out = p.join(widget.workDir.path, 'test_cut.mp4');
        final endMs =
            widget.video.durationMs < 10000 ? widget.video.durationMs : 10000;
        final r = await widget.service.cutVideo(
          inputPath: widget.video.filePath,
          outputPath: out,
          startMs: 0,
          endMs: endMs,
          onProgress: _onProgress,
          taskId: _taskId,
        );
        if (!mounted) return;
        if (!r.ok) {
          setState(() => _message = _failText(r));
          return;
        }
        final size = await File(out).length();
        if (!mounted) return;
        setState(() {
          _cutRun++;
          _cutPath = out;
          _message = 'Potongan selesai (${formatFileSize(size)}).';
        });
      });

  Future<void> _audio() => _guard(() async {
        final out = p.join(widget.workDir.path, 'test_audio.wav');
        final r = await widget.service.extractAudio(
          inputPath: widget.video.filePath,
          outputPath: out,
          durationMs: widget.video.durationMs,
          onProgress: _onProgress,
          taskId: _taskId,
        );
        if (!mounted) return;
        if (!r.ok) {
          setState(() => _message = _failText(r));
          return;
        }
        final size = await File(out).length();
        if (!mounted) return;
        setState(() => _message =
            'Audio WAV 16 kHz mono selesai (${formatFileSize(size)}).');
      });

  Future<void> _thumb() => _guard(() async {
        final out = p.join(widget.workDir.path, 'test_thumb.jpg');
        final pos = widget.video.durationMs > 5000 ? 5000 : 0;
        final r = await widget.service.generateThumbnail(
          inputPath: widget.video.filePath,
          outputPath: out,
          positionMs: pos,
          taskId: _taskId,
        );
        if (!mounted) return;
        if (!r.ok) {
          setState(() => _message = _failText(r));
          return;
        }
        await FileImage(File(out)).evict();
        if (!mounted) return;
        setState(() {
          _thumbPath = out;
          _message = 'Thumbnail selesai.';
        });
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cut = _cutPath;
    final thumb = _thumbPath;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Uji FFmpeg lokal', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Alat uji sementara untuk STEP 6. Hasil disimpan di folder '
              'temp project.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _diagnose,
                  child: const Text('Info FFmpeg'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _cut,
                  child: const Text('Potong 10 detik'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _audio,
                  child: const Text('Ekstrak audio'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _thumb,
                  child: const Text('Thumbnail'),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _progress == null
                          ? 'Memproses...'
                          : 'Memproses ${(_progress! * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.service.cancel(_taskId),
                    child: const Text('Batalkan'),
                  ),
                ],
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: theme.textTheme.bodyMedium),
            ],
            if (thumb != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(thumb),
                  height: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
            ],
            if (cut != null) ...[
              const SizedBox(height: 12),
              VideoPlayerPanel(
                key: ValueKey('cut-$_cutRun'),
                video: VideoRecord(
                  projectId: widget.video.projectId,
                  filePath: cut,
                  fileName: 'test_cut.mp4',
                  createdAt: DateTime.now(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
