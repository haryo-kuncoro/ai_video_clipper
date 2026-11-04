import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/clip.dart';
import '../../database/models/export_record.dart';
import '../../database/repositories/clip_repository.dart';
import '../../services/export/export_service.dart';

/// Ekspor clip hasil render ke galeri (Movies/AI Video Clipper), SRT ke
/// Downloads, atau bagikan. File asli di folder aplikasi tidak diubah.
class ClipExportCard extends StatefulWidget {
  const ClipExportCard({
    super.key,
    required this.service,
    required this.clips,
    required this.projectId,
    this.exportSrtEnabled = true,
  });

  /// Dikendalikan flag server `export_srt`.
  final bool exportSrtEnabled;

  final ExportService service;
  final ClipRepository clips;
  final int projectId;

  @override
  State<ClipExportCard> createState() => _ClipExportCardState();
}

class _ClipExportCardState extends State<ClipExportCard> {
  List<Clip> _clips = const [];
  Map<int, List<ExportRecord>> _history = const {};
  bool _loading = true;
  bool _busy = false;
  ExportProgress? _progress;
  CancelFlag? _cancel;
  String? _message;
  List<String> _problems = const [];

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
      final all = await widget.clips.getByProject(widget.projectId);
      final done = all
          .where((c) => c.status == ClipStatus.completed && c.filePath != null)
          .toList();
      final records = await widget.service.history(widget.projectId);
      final byClip = <int, List<ExportRecord>>{};
      for (final r in records) {
        byClip.putIfAbsent(r.clipId, () => []).add(r);
      }
      if (!mounted) return;
      setState(() {
        _clips = done;
        _history = byClip;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.e('Muat daftar ekspor gagal', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Daftar clip tidak dapat dimuat.';
        });
      }
    }
  }

  Future<void> _exportAll() async {
    final cancel = CancelFlag();
    setState(() {
      _busy = true;
      _cancel = cancel;
      _message = null;
      _problems = const [];
      _progress = null;
    });
    try {
      final s = await widget.service.exportClips(
        _clips,
        cancel: cancel,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _message = s.allOk
            ? '${s.exported.length} clip tersimpan di galeri '
                '(Movies/AI Video Clipper).'
            : '${s.exported.length} clip tersimpan, ${s.failures.length} gagal.';
        _problems = [for (final f in s.failures) '${f.clip.title}: ${f.message}'];
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Ekspor massal gagal', e, st);
      if (mounted) setState(() => _message = 'Ekspor gagal. Coba lagi.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancel = null;
          _progress = null;
        });
      }
      await _refresh();
    }
  }

  Future<void> _single(Future<ExportRecord> Function() job, String ok) async {
    setState(() {
      _busy = true;
      _message = null;
      _problems = const [];
    });
    try {
      final r = await job();
      if (mounted) setState(() => _message = '$ok: ${r.displayName}');
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Ekspor gagal', e, st);
      if (mounted) setState(() => _message = 'Ekspor gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _share(Clip c) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.shareClip(c);
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Bagikan gagal', e, st);
      if (mounted) setState(() => _message = 'Clip tidak dapat dibagikan.');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
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
            Row(
              children: [
                Expanded(
                  child: Text('Ekspor Clip', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Muat ulang',
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              'Menyalin clip ke galeri (Movies/AI Video Clipper). File asli di '
              'aplikasi tetap ada. SRT disimpan di Downloads/AI Video Clipper.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else if (_clips.isEmpty)
              const Text('Belum ada clip yang selesai dirender.')
            else ...[
              FilledButton.icon(
                onPressed: _busy ? null : _exportAll,
                icon: const Icon(Icons.save_alt),
                label: Text('Ekspor semua (${_clips.length}) ke galeri'),
              ),
              if (_busy && _cancel != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (p == null || p.total == 0) ? null : p.done / p.total,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p == null
                            ? 'Menyiapkan…'
                            : 'Mengekspor ${p.done + 1 > p.total ? p.total : p.done + 1}'
                                '/${p.total}  ${p.currentTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _cancel?.cancel(),
                      child: const Text('Batal'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              for (final c in _clips) _row(theme, c),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!),
            ],
            for (final line in _problems)
              Text(line,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, Clip c) {
    final records = _history[c.id] ?? const <ExportRecord>[];
    final videoCount = records.where((r) => r.kind == ExportKind.video).length;
    final srtCount = records.where((r) => r.kind == ExportKind.srt).length;
    final notes = [
      if (videoCount > 0) 'Video diekspor${videoCount > 1 ? ' ×$videoCount' : ''}',
      if (srtCount > 0) 'SRT diekspor',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        formatClockDuration(c.durationMs),
        if (notes.isNotEmpty) notes,
      ].join(' · ')),
      trailing: PopupMenuButton<String>(
        enabled: !_busy,
        tooltip: 'Aksi ekspor',
        onSelected: (v) {
          switch (v) {
            case 'video':
              _single(() => widget.service.exportClipVideo(c),
                  'Tersimpan di galeri');
              break;
            case 'srt':
              _single(() => widget.service.exportClipSrt(c),
                  'SRT tersimpan di Downloads');
              break;
            case 'share':
              _share(c);
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'video', child: Text('Simpan ke galeri')),
          if (widget.exportSrtEnabled)
            const PopupMenuItem(value: 'srt', child: Text('Ekspor SRT')),
          const PopupMenuItem(value: 'share', child: Text('Bagikan…')),
        ],
      ),
    );
  }
}
