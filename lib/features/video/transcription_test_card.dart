import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/transcript.dart';
import '../../database/models/video_record.dart';
import '../../services/transcription/transcription_models.dart';
import '../transcript/transcript_page.dart';
import '../../services/transcription/transcription_service.dart';
import '../../services/models/model_catalog.dart';
import '../settings/models_page.dart';

/// Kartu uji SEMENTARA untuk STEP 9: unduh model, jalankan transkripsi lokal,
/// lihat hasilnya. Tampilan transcript lengkap dibuat di STEP 10.
class TranscriptionTestCard extends StatefulWidget {
  const TranscriptionTestCard({
    super.key,
    required this.service,
    required this.video,
    required this.catalog,
  });

  final TranscriptionService service;
  final VideoRecord video;
  final ModelCatalog catalog;

  @override
  State<TranscriptionTestCard> createState() => _TranscriptionTestCardState();
}

class _TranscriptionTestCardState extends State<TranscriptionTestCard> {
  WhisperModelInfo _model = WhisperModels.defaultModel;
  TranscriptionLanguage _language = TranscriptionLanguage.indonesian;

  bool _transcribing = false;
  TranscriptionProgress? _progress;
  CancelToken? _transcribeCancel;

  String? _message;
  int _segmentCount = 0;
  List<TranscriptSegment> _preview = const [];

  bool get _installed => widget.catalog.whisperInstalled(_model);

  @override
  void initState() {
    super.initState();
    widget.catalog.addListener(_onCatalog);
    widget.catalog.refresh().then((_) => _pickInstalledModel());
    _loadExisting();
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_onCatalog);
    _transcribeCancel?.cancel();
    super.dispose();
  }

  void _onCatalog() {
    if (mounted) setState(() {});
  }

  /// Bila model default belum ada tetapi model lain sudah ada, pakai itu.
  void _pickInstalledModel() {
    if (!mounted || _installed) return;
    final have = widget.catalog.installedWhisper;
    if (have.isNotEmpty) setState(() => _model = have.first);
  }

  Future<void> _loadExisting() async {
    try {
      final t =
          await widget.service.transcripts.getByProject(widget.video.projectId);
      if (t == null) return;
      final segs = await widget.service.transcripts.getSegments(t.id!);
      if (!mounted) return;
      setState(() {
        _segmentCount = segs.length;
        _preview = segs.take(12).toList();
      });
    } catch (e, st) {
      AppLogger.e('Gagal memuat transcript', e, st);
    }
  }

  Future<void> _openTranscript() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TranscriptPage(
        repository: widget.service.transcripts,
        projectId: widget.video.projectId,
      ),
    ));
    if (mounted) await _loadExisting();
  }

  Future<void> _openModels() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ModelsPage(catalog: widget.catalog),
    ));
    if (mounted) _pickInstalledModel();
  }

  Future<void> _transcribe() async {
    if (_transcribing) return;
    final cancel = CancelToken();
    setState(() {
      _transcribing = true;
      _transcribeCancel = cancel;
      _progress = null;
      _message = null;
    });
    try {
      final r = await widget.service.transcribe(
        video: widget.video,
        model: _model,
        language: _language.code,
        cancel: cancel,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (r.cancelled) {
        setState(() => _message = 'Transkripsi dibatalkan.');
      } else {
        final segs =
            await widget.service.transcripts.getSegments(r.transcriptId!);
        if (!mounted) return;
        setState(() {
          _segmentCount = segs.length;
          _preview = segs.take(12).toList();
          _message = 'Selesai: ${segs.length} segmen tersimpan di SQLite.';
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Transkripsi gagal', e, st);
      if (mounted) setState(() => _message = 'Transkripsi gagal.');
    } finally {
      if (mounted) {
        setState(() {
          _transcribing = false;
          _transcribeCancel = null;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _transcribing;
    final pr = _progress;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transcript (Speech-to-Text)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Seluruh proses offline; tidak ada data dikirim ke server. '
              'Model diunduh di Pengaturan > Model AI.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final m in WhisperModels.all)
                  ChoiceChip(
                    label: Text(widget.catalog.whisperInstalled(m)
                        ? '${m.label} ✓'
                        : m.label),
                    selected: m.id == _model.id,
                    onSelected: busy ? null : (_) => setState(() => _model = m),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_model.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Bahasa'),
                const SizedBox(width: 12),
                DropdownButton<TranscriptionLanguage>(
                  value: _language,
                  items: [
                    for (final l in TranscriptionLanguage.all)
                      DropdownMenuItem(value: l, child: Text(l.label)),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          if (v != null) setState(() => _language = v);
                        },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_installed)
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Model ${_model.label} belum diunduh. Unduh dulu di '
                      'Pengaturan > Model AI.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _openModels,
                    child: const Text('Buka'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (!_installed || busy) ? null : _transcribe,
              child: const Text('Buat transcript'),
            ),
            if (_transcribing) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: pr?.fraction),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pr == null
                          ? 'Menyiapkan...'
                          : '${pr.label} ${(pr.fraction * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _transcribeCancel?.cancel(),
                    child: const Text('Batalkan'),
                  ),
                ],
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: theme.textTheme.bodyMedium),
            ],
            if (_preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Transcript tersimpan: $_segmentCount segmen',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final s in _preview)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '[${formatClockDuration(s.startMs)}] ${s.text}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (_segmentCount > _preview.length)
                Text('... dan ${_segmentCount - _preview.length} segmen lain',
                    style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.article_outlined),
                label: const Text('Buka & edit transcript'),
                onPressed: busy ? null : _openTranscript,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
