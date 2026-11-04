import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/transcript.dart';
import '../../database/models/video_record.dart';
import '../../services/transcription/transcription_models.dart';
import '../transcript/transcript_page.dart';
import '../../services/transcription/transcription_service.dart';
import '../../services/transcription/whisper_model_manager.dart';

/// Kartu uji SEMENTARA untuk STEP 9: unduh model, jalankan transkripsi lokal,
/// lihat hasilnya. Tampilan transcript lengkap dibuat di STEP 10.
class TranscriptionTestCard extends StatefulWidget {
  const TranscriptionTestCard({
    super.key,
    required this.service,
    required this.video,
  });

  final TranscriptionService service;
  final VideoRecord video;

  @override
  State<TranscriptionTestCard> createState() => _TranscriptionTestCardState();
}

class _TranscriptionTestCardState extends State<TranscriptionTestCard> {
  WhisperModelInfo _model = WhisperModels.defaultModel;
  TranscriptionLanguage _language = TranscriptionLanguage.indonesian;

  bool _installed = false;
  int _installedSize = 0;

  bool _downloading = false;
  DownloadProgress? _download;
  CancelToken? _downloadCancel;

  bool _transcribing = false;
  TranscriptionProgress? _progress;
  CancelToken? _transcribeCancel;

  String? _message;
  int _segmentCount = 0;
  List<TranscriptSegment> _preview = const [];

  WhisperModelManager get _models => widget.service.models;

  @override
  void initState() {
    super.initState();
    _refreshModel();
    _loadExisting();
  }

  @override
  void dispose() {
    _downloadCancel?.cancel();
    _transcribeCancel?.cancel();
    super.dispose();
  }

  Future<void> _refreshModel() async {
    final installed = await _models.isInstalled(_model);
    final size = installed ? await _models.installedSize(_model) : 0;
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _installedSize = size;
    });
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

  Future<void> _downloadModel() async {
    if (_downloading) return;
    final cancel = CancelToken();
    setState(() {
      _downloading = true;
      _downloadCancel = cancel;
      _download = null;
      _message = null;
    });
    try {
      await _models.download(
        _model,
        cancel: cancel,
        onProgress: (d) {
          if (mounted) setState(() => _download = d);
        },
      );
      if (mounted) setState(() => _message = 'Model ${_model.label} siap.');
    } on TranscriptionCancelled {
      if (mounted) setState(() => _message = 'Unduhan dibatalkan.');
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Unduh model gagal', e, st);
      if (mounted) setState(() => _message = 'Unduhan model gagal.');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadCancel = null;
          _download = null;
        });
        await _refreshModel();
      }
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

  Future<void> _deleteModel() async {
    try {
      await _models.delete(_model);
      if (mounted) setState(() => _message = 'Model dihapus.');
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
    await _refreshModel();
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
    final busy = _downloading || _transcribing;
    final d = _download;
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
              'Alat uji sementara. Model diunduh sekali; setelah itu seluruh '
              'proses offline dan tidak ada data dikirim ke server.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final m in WhisperModels.all)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: m.id == _model.id,
                    onSelected: busy
                        ? null
                        : (_) {
                            setState(() => _model = m);
                            _refreshModel();
                          },
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
            if (_installed)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Model terpasang (${formatFileSize(_installedSize)})',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : _deleteModel,
                    child: const Text('Hapus model'),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Unduh model'),
                onPressed: busy ? null : _downloadModel,
              ),
            if (_downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: d?.fileFraction),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d == null
                          ? 'Menghubungi server...'
                          : 'File ${d.fileIndex + 1}/${d.fileCount}: '
                              '${formatFileSize(d.received)}'
                              '${d.total != null ? ' / ${formatFileSize(d.total!)}' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _downloadCancel?.cancel(),
                    child: const Text('Batalkan'),
                  ),
                ],
              ),
            ],
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
