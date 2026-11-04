import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/clip_candidate.dart';
import '../../database/models/video_record.dart';
import 'clip_range.dart';
import 'clip_review_controller.dart';
import 'range_preview_player.dart';
import 'time_nudge_row.dart';

enum _BulkAction { acceptAll, rejectAll, resetAll }

/// Review kandidat clip: terima/tolak, pratinjau, ubah waktu dan judul.
/// Clip yang diterima dirender di STEP 13.
class ClipReviewPage extends StatefulWidget {
  const ClipReviewPage({
    super.key,
    required this.controller,
    required this.video,
  });

  final ClipReviewController controller;
  final VideoRecord video;

  @override
  State<ClipReviewPage> createState() => _ClipReviewPageState();
}

class _ClipReviewPageState extends State<ClipReviewPage> {
  int? _previewId;

  ClipReviewController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AppException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e, st) {
      AppLogger.e('Aksi review gagal', e, st);
      if (mounted) _toast('Perubahan gagal disimpan.');
    }
  }

  Future<void> _edit(ClipCandidate c) async {
    setState(() => _previewId = null);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditSheet(
        candidate: c,
        video: widget.video,
        controller: _c,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Clip'),
        actions: [
          PopupMenuButton<_BulkAction>(
            tooltip: 'Aksi massal',
            onSelected: (a) => _guard(() {
              switch (a) {
                case _BulkAction.acceptAll:
                  return _c.setAll(CandidateStatus.accepted);
                case _BulkAction.rejectAll:
                  return _c.setAll(CandidateStatus.rejected);
                case _BulkAction.resetAll:
                  return _c.setAll(CandidateStatus.pending);
              }
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _BulkAction.acceptAll, child: Text('Terima semua')),
              PopupMenuItem(value: _BulkAction.rejectAll, child: Text('Tolak semua')),
              PopupMenuItem(
                  value: _BulkAction.resetAll, child: Text('Reset ke belum direview')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) {
            if (_c.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_c.error != null) return Center(child: Text(_c.error!));
            if (_c.items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Belum ada kandidat. Jalankan "Deteksi Clip" dulu.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Column(
              children: [
                _Summary(controller: _c),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _c.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final c = _c.items[i];
                      return _CandidateCard(
                        key: ValueKey(c.id),
                        candidate: c,
                        video: widget.video,
                        previewing: _previewId == c.id,
                        onTogglePreview: () => setState(
                            () => _previewId = _previewId == c.id ? null : c.id),
                        onAccept: () =>
                            _guard(() => _c.setStatus(c, CandidateStatus.accepted)),
                        onReject: () =>
                            _guard(() => _c.setStatus(c, CandidateStatus.rejected)),
                        onEdit: () => _edit(c),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final ClipReviewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        children: [
          Chip(label: Text('${controller.acceptedCount} diterima')),
          Chip(label: Text('${controller.rejectedCount} ditolak')),
          Chip(
            label: Text('${controller.pendingCount} belum direview'),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    super.key,
    required this.candidate,
    required this.video,
    required this.previewing,
    required this.onTogglePreview,
    required this.onAccept,
    required this.onReject,
    required this.onEdit,
  });

  final ClipCandidate candidate;
  final VideoRecord video;
  final bool previewing;
  final VoidCallback onTogglePreview;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = candidate;
    final accepted = c.status == CandidateStatus.accepted;
    final rejected = c.status == CandidateStatus.rejected;
    final generated = c.status == CandidateStatus.generated;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: accepted
              ? Colors.green
              : rejected
                  ? theme.colorScheme.outlineVariant
                  : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Opacity(
        opacity: rejected ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(c.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text('${(c.score * 100).round()}%',
                      style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${formatPreciseMs(c.startMs)} - ${formatPreciseMs(c.endMs)} '
                '(${(c.duration.inMilliseconds / 1000).round()} dtk)',
                style: theme.textTheme.bodySmall,
              ),
              if (c.reason != null && c.reason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(c.reason!, style: theme.textTheme.bodySmall),
              ],
              if (previewing) ...[
                const SizedBox(height: 8),
                RangePreviewPlayer(
                  key: ValueKey('preview-${c.id}'),
                  filePath: video.filePath,
                  startMs: c.startMs,
                  endMs: c.endMs,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (generated)
                    const Chip(label: Text('Sudah dirender'))
                  else ...[
                    FilterChip(
                      avatar: const Icon(Icons.check, size: 18),
                      label: const Text('Terima'),
                      selected: accepted,
                      onSelected: (_) => onAccept(),
                    ),
                    FilterChip(
                      avatar: const Icon(Icons.close, size: 18),
                      label: const Text('Tolak'),
                      selected: rejected,
                      onSelected: (_) => onReject(),
                    ),
                  ],
                  ActionChip(
                    avatar: Icon(previewing ? Icons.stop : Icons.play_arrow, size: 18),
                    label: Text(previewing ? 'Tutup' : 'Pratinjau'),
                    onPressed: onTogglePreview,
                  ),
                  if (!generated)
                    ActionChip(
                      avatar: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                      onPressed: onEdit,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({
    required this.candidate,
    required this.video,
    required this.controller,
  });

  final ClipCandidate candidate;
  final VideoRecord video;
  final ClipReviewController controller;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late int _start = widget.candidate.startMs;
  late int _end = widget.candidate.endMs;
  late final _title = TextEditingController(text: widget.candidate.title);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  int get _max => widget.video.durationMs;

  void _nudgeStart(int delta) => setState(() {
        _error = null;
        var v = _start + delta;
        if (v < 0) v = 0;
        if (v > _end - minClipMs) v = _end - minClipMs;
        _start = v < 0 ? 0 : v;
      });

  void _nudgeEnd(int delta) => setState(() {
        _error = null;
        var v = _end + delta;
        if (_max > 0 && v > _max) v = _max;
        if (v < _start + minClipMs) v = _start + minClipMs;
        _end = v;
      });

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveEdit(
        widget.candidate,
        startMs: _start,
        endMs: _end,
        title: _title.text,
      );
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      AppLogger.e('Simpan edit clip gagal', e, st);
      if (mounted) setState(() => _error = 'Perubahan gagal disimpan.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit clip', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Judul',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            RangePreviewPlayer(
              key: const ValueKey('edit-preview'),
              filePath: widget.video.filePath,
              startMs: _start,
              endMs: _end,
            ),
            const SizedBox(height: 8),
            TimeNudgeRow(
              label: 'Mulai',
              valueMs: _start,
              enabled: !_saving,
              onNudge: _nudgeStart,
            ),
            const SizedBox(height: 12),
            TimeNudgeRow(
              label: 'Selesai',
              valueMs: _end,
              enabled: !_saving,
              onNudge: _nudgeEnd,
            ),
            const SizedBox(height: 8),
            Text(
              'Durasi: ${((_end - _start) / 1000).toStringAsFixed(1)} dtk '
              '(min 3 dtk, maks 3 menit)',
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Simpan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
