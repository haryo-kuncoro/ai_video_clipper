import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/video_record.dart';
import '../../services/settings/app_settings.dart';
import '../../services/pipeline/processing_pipeline.dart';
import '../../services/transcription/transcription_models.dart';

/// STEP 17: "Proses otomatis" — transkripsi, deteksi, render (dan ekspor)
/// berurutan di latar belakang. Proses terus berjalan walau halaman ditutup
/// atau aplikasi dikirim ke latar belakang (notifikasi progres tampil).
class PipelineCard extends StatefulWidget {
  const PipelineCard({
    super.key,
    required this.pipeline,
    required this.video,
    this.settings = AppSettings.defaults,
  });

  final AppSettings settings;
  final ProcessingPipeline pipeline;
  final VideoRecord video;

  @override
  State<PipelineCard> createState() => _PipelineCardState();
}

class _PipelineCardState extends State<PipelineCard> {
  WhisperModelInfo _model = WhisperModels.defaultModel;
  TranscriptionLanguage _language = TranscriptionLanguage.indonesian;
  bool _reuse = true;
  bool _burn = true;
  late bool _face = widget.settings.faceAwareCropEnabled;
  bool _export = false;
  bool _translate = false;
  double _top = 5;
  String? _message;

  bool get _canTranslate =>
      _language.code.isNotEmpty && _language.code != 'id';

  Future<void> _start() async {
    setState(() => _message = null);
    try {
      await widget.pipeline.run(
        video: widget.video,
        options: PipelineOptions(
          model: _model,
          language: _language.code,
          reuseTranscript: _reuse,
          detection: widget.settings.detection,
          acceptTop: _top.round(),
          burnSubtitles: _burn,
          faceAware: _face,
          exportToGallery: _export,
          translateTo: _canTranslate && _translate ? 'id' : null,
        ),
      );
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Pipeline tidak dapat dimulai', e, st);
      if (mounted) setState(() => _message = 'Pemrosesan tidak dapat dimulai.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pipeline,
      builder: (context, _) {
        final theme = Theme.of(context);
        final st = widget.pipeline.state;
        final mine = st.projectId == widget.video.projectId;
        final running = widget.pipeline.isRunning;
        final otherRunning = running && !mine;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proses Otomatis', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Transkripsi → deteksi momen → render clip, berurutan. '
                  'Tetap berjalan saat aplikasi di latar belakang. Semua proses '
                  'di perangkat ini.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (otherRunning)
                  const Text('Project lain sedang diproses. Tunggu sampai selesai.')
                else if (running)
                  _progress(theme, st)
                else ...[
                  _options(theme),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Mulai proses otomatis'),
                  ),
                  if (mine) _result(theme, st),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _progress(ThemeData theme, PipelineState st) {
    final pct = (st.fraction * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: st.fraction <= 0 ? null : st.fraction),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('${st.label} · $pct%')),
            TextButton(
              onPressed: widget.pipeline.cancel,
              child: const Text('Batal'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _result(ThemeData theme, PipelineState st) {
    switch (st.stage) {
      case PipelineStage.done:
        final r = st.result;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selesai: ${r?.summary ?? ''}'),
              for (final w in r?.warnings ?? const <String>[])
                Text(w, style: theme.textTheme.bodySmall),
            ],
          ),
        );
      case PipelineStage.cancelled:
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Dibatalkan. Hasil yang sudah selesai tetap tersimpan.'),
        );
      case PipelineStage.failed:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(st.error ?? 'Pemrosesan gagal.',
              style: TextStyle(color: theme.colorScheme.error)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _options(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final m in WhisperModels.all)
              ChoiceChip(
                label: Text(m.label),
                selected: m.id == _model.id,
                onSelected: (_) => setState(() => _model = m),
              ),
          ],
        ),
        Text('Model harus sudah diunduh di kartu Transkripsi.',
            style: theme.textTheme.bodySmall),
        Row(
          children: [
            const Text('Bahasa: '),
            DropdownButton<TranscriptionLanguage>(
              value: _language,
              items: [
                for (final l in TranscriptionLanguage.all)
                  DropdownMenuItem(value: l, child: Text(l.label)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _language = v);
              },
            ),
          ],
        ),
        if (_canTranslate)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Terjemahkan ke Indonesia'),
            subtitle: const Text(
                'Subtitle dan deteksi clip memakai terjemahan. Berjalan offline '
                'di HP; model terjemahan diunduh sekali (±30 MB per bahasa).'),
            value: _translate,
            onChanged: (v) => setState(() => _translate = v),
          ),
        Text('Jumlah clip yang dirender: ${_top.round()}'),
        Slider(
          value: _top,
          min: 1,
          max: 10,
          divisions: 9,
          label: '${_top.round()}',
          onChanged: (v) => setState(() => _top = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pakai transcript yang sudah ada'),
          subtitle: const Text('Lebih cepat; matikan untuk transkripsi ulang'),
          value: _reuse,
          onChanged: (v) => setState(() => _reuse = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Render subtitle'),
          value: _burn,
          onChanged: (v) => setState(() => _burn = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Crop mengikuti wajah'),
          value: _face,
          onChanged: (v) => setState(() => _face = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Langsung simpan ke galeri'),
          value: _export,
          onChanged: (v) => setState(() => _export = v),
        ),
      ],
    );
  }
}
