import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/clip.dart';
import '../../database/models/video_record.dart';
import '../../services/settings/app_settings.dart';
import '../../services/render/clip_render_service.dart';
import '../../services/transcription/transcription_models.dart';
import '../../database/repositories/transcript_repository.dart';
import '../clips/clip_editor_page.dart';
import 'player/video_player_panel.dart';

/// Kartu SEMENTARA untuk STEP 13: render semua kandidat yang diterima dan
/// lihat hasilnya. Ekspor ke galeri ada di kartu "Ekspor Clip" (STEP 16).
class ClipRenderTestCard extends StatefulWidget {
  const ClipRenderTestCard({
    super.key,
    required this.service,
    required this.video,
    this.transcripts,
    this.settings = AppSettings.defaults,
  });

  final AppSettings settings;
  final ClipRenderService service;
  final VideoRecord video;
  final TranscriptRepository? transcripts;

  @override
  State<ClipRenderTestCard> createState() => _ClipRenderTestCardState();
}

class _ClipRenderTestCardState extends State<ClipRenderTestCard> {
  int _accepted = 0;
  List<Clip> _clips = const [];
  bool _burnSubtitles = true;
  late bool _faceAware = widget.settings.faceAwareCropEnabled;

  bool _busy = false;
  RenderProgress? _progress;
  CancelToken? _cancel;
  String? _message;
  List<String> _details = const [];

  int get _projectId => widget.video.projectId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final accepted = await widget.service.acceptedCount(_projectId);
      final clips = await widget.service.clips.getByProject(_projectId);
      if (!mounted) return;
      setState(() {
        _accepted = accepted;
        _clips = clips.where((c) => c.status == ClipStatus.completed).toList();
      });
    } catch (e, st) {
      AppLogger.e('Gagal memuat clip', e, st);
    }
  }

  Future<void> _render() async {
    if (_busy) return;
    final cancel = CancelToken();
    setState(() {
      _busy = true;
      _cancel = cancel;
      _progress = null;
      _message = null;
      _details = const [];
    });
    try {
      final s = await widget.service.renderAccepted(
        video: widget.video,
        burnSubtitles: _burnSubtitles,
        faceAware: _faceAware,
        cancel: cancel,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _message = s.cancelled
            ? 'Dibatalkan. ${s.succeeded} clip sudah selesai.'
            : '${s.succeeded} clip selesai'
                '${s.failures.isEmpty ? '.' : ', ${s.failures.length} gagal.'}';
        _details = [
          for (final f in s.failures) '${f.title}: ${f.message}',
          ...s.warnings,
          ...s.notes,
        ];
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Render clip gagal', e, st);
      if (mounted) setState(() => _message = 'Render clip gagal.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancel = null;
          _progress = null;
        });
        await _refresh();
      }
    }
  }

  Future<void> _delete(Clip c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus clip?'),
        content: Text(
            '"${c.title}" akan dihapus dari perangkat. Kandidatnya bisa '
            'dirender ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.deleteClip(c);
    } catch (e, st) {
      AppLogger.e('Hapus clip gagal', e, st);
      if (mounted) setState(() => _message = 'Clip gagal dihapus.');
    }
    await _refresh();
  }

  Future<void> _editClip(Clip c) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => ClipEditorPage(
        service: widget.service,
        clip: c,
        video: widget.video,
        transcripts: widget.transcripts,
      ),
    ));
    if (changed == true) await _refresh();
  }

  void _play(Clip c) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ClipPlayerPage(clip: c),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _progress;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Render Clip', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Merender kandidat yang DITERIMA di layar Review menjadi video '
              'portrait 9:16, satu per satu. Alat uji sementara.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Render subtitle dari transcript'),
              value: _burnSubtitles,
              onChanged: _busy ? null : (v) => setState(() => _burnSubtitles = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Crop mengikuti wajah'),
              subtitle: const Text('Bila wajah tidak terdeteksi: crop tengah'),
              value: _faceAware,
              onChanged: _busy ? null : (v) => setState(() => _faceAware = v),
            ),
            FilledButton(
              onPressed: (_busy || _accepted == 0) ? null : _render,
              child: Text(_accepted == 0
                  ? 'Belum ada kandidat diterima'
                  : 'Render $_accepted clip'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: p?.overall),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p == null
                          ? 'Menyiapkan...'
                          : 'Clip ${p.index}/${p.total}: ${p.title} '
                              '(${(p.clipFraction * 100).round()}%)',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _cancel?.cancel(),
                    child: const Text('Batalkan'),
                  ),
                ],
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: theme.textTheme.bodyMedium),
            ],
            for (final d in _details)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(d, style: theme.textTheme.bodySmall),
              ),
            if (_clips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Hasil clip (${_clips.length})',
                  style: theme.textTheme.labelLarge),
              for (final c in _clips)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Thumb(path: c.thumbnailPath),
                  title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${formatClockDuration(c.durationMs)} - ${c.width}x${c.height}',
                  ),
                  onTap: _busy ? null : () => _play(c),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit clip',
                        icon: const Icon(Icons.tune),
                        onPressed: _busy ? null : () => _editClip(c),
                      ),
                      IconButton(
                        tooltip: 'Hapus clip',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : () => _delete(c),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final box = SizedBox(
      width: 40,
      height: 56,
      child: (p != null && File(p).existsSync())
          ? Image.file(File(p), fit: BoxFit.cover)
          : const Icon(Icons.movie_outlined),
    );
    return ClipRRect(borderRadius: BorderRadius.circular(6), child: box);
  }
}

class _ClipPlayerPage extends StatelessWidget {
  const _ClipPlayerPage({required this.clip});

  final Clip clip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(clip.title, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: VideoPlayerPanel(
              video: VideoRecord(
                projectId: clip.projectId,
                filePath: clip.filePath ?? '',
                fileName: 'clip_${clip.id}.mp4',
                width: clip.width,
                height: clip.height,
                durationMs: clip.durationMs,
                createdAt: clip.createdAt,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
