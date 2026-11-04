import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/transcript.dart';
import '../../database/repositories/transcript_repository.dart';
import '../../services/transcription/transcript_formats.dart';

enum _SegmentAction { edit, mergeNext, delete }

/// Melihat dan merapikan transcript satu project (semua dari SQLite lokal).
class TranscriptPage extends StatefulWidget {
  const TranscriptPage({
    super.key,
    required this.repository,
    required this.projectId,
  });

  final TranscriptRepository repository;
  final int projectId;

  @override
  State<TranscriptPage> createState() => _TranscriptPageState();
}

class _TranscriptPageState extends State<TranscriptPage> {
  final _searchController = TextEditingController();
  List<TranscriptSegment> _segments = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await widget.repository.getByProject(widget.projectId);
      final segs = t == null
          ? <TranscriptSegment>[]
          : await widget.repository.getSegments(t.id!);
      if (!mounted) return;
      setState(() {
        _segments = segs;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      AppLogger.e('Gagal memuat transcript', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Transcript tidak dapat dimuat.';
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast(done);
  }

  Future<void> _edit(TranscriptSegment s) async {
    final controller = TextEditingController(text: s.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit [${formatClockDuration(s.startMs)}]'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (text == null) return;
    if (text.isEmpty) {
      _toast('Teks tidak boleh kosong. Gunakan Hapus untuk membuang segmen.');
      return;
    }
    if (text == s.text) return;
    await _run(() => widget.repository.updateSegmentText(s.id!, text));
  }

  Future<void> _delete(TranscriptSegment s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus segmen?'),
        content: Text(s.text, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => widget.repository.deleteSegment(s.id!));
  }

  Future<void> _merge(TranscriptSegment s) async {
    var merged = false;
    await _run(() async {
      merged = await widget.repository.mergeWithNext(s.id!);
    });
    if (!merged && mounted) _toast('Tidak ada segmen berikutnya.');
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e, st) {
      AppLogger.e('Perubahan transcript gagal', e, st);
      if (mounted) _toast('Perubahan gagal disimpan.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = searchSegments(_segments, _query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcript'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Salin',
            icon: const Icon(Icons.copy_outlined),
            enabled: _segments.isNotEmpty,
            onSelected: (v) {
              if (v == 'text') {
                _copy(toPlainText(_segments), 'Teks transcript disalin.');
              } else {
                _copy(toSrt(_segments), 'Format SRT disalin.');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'text', child: Text('Salin teks')),
              PopupMenuItem(value: 'srt', child: Text('Salin sebagai SRT')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _body(visible)),
    );
  }

  Widget _body(List<int> visible) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_segments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Belum ada transcript. Buat dulu dari kartu Transcript di detail project.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Cari kata di transcript',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _query.trim().isEmpty
                  ? '${_segments.length} segmen'
                  : '${visible.length} dari ${_segments.length} segmen cocok',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('Tidak ada yang cocok.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _SegmentTile(
                        segment: _segments[visible[i]],
                        query: _query,
                        onEdit: _edit,
                        onMerge: _merge,
                        onDelete: _delete,
                      ),
                ),
        ),
      ],
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.segment,
    required this.query,
    required this.onEdit,
    required this.onMerge,
    required this.onDelete,
  });

  final TranscriptSegment segment;
  final String query;
  final void Function(TranscriptSegment) onEdit;
  final void Function(TranscriptSegment) onMerge;
  final void Function(TranscriptSegment) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = theme.colorScheme.tertiaryContainer;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onEdit(segment),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatClockDuration(segment.startMs),
                      style: theme.textTheme.labelLarge),
                  Text(formatClockDuration(segment.endMs),
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        for (final part
                            in splitHighlights(segment.text, query))
                          TextSpan(
                            text: part.text,
                            style: part.highlighted
                                ? TextStyle(backgroundColor: highlight)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              PopupMenuButton<_SegmentAction>(
                tooltip: 'Aksi segmen',
                onSelected: (a) {
                  switch (a) {
                    case _SegmentAction.edit:
                      onEdit(segment);
                    case _SegmentAction.mergeNext:
                      onMerge(segment);
                    case _SegmentAction.delete:
                      onDelete(segment);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _SegmentAction.edit, child: Text('Edit teks')),
                  PopupMenuItem(
                      value: _SegmentAction.mergeNext,
                      child: Text('Gabung dengan berikutnya')),
                  PopupMenuItem(value: _SegmentAction.delete, child: Text('Hapus')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
