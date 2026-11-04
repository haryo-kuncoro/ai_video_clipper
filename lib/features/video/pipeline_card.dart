import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/video_record.dart';
import '../../services/settings/app_settings.dart';
import '../../services/pipeline/processing_pipeline.dart';
import '../../database/repositories/subtitle_settings_repository.dart';
import '../../services/models/model_catalog.dart';
import '../../services/subtitle/subtitle_style.dart';
import '../../services/transcription/transcription_models.dart';
import '../settings/models_page.dart';
import 'subtitle_style_controls.dart';

/// STEP 17: "Proses otomatis" — transkripsi, deteksi, render (dan ekspor)
/// berurutan di latar belakang. Proses terus berjalan walau halaman ditutup
/// atau aplikasi dikirim ke latar belakang (notifikasi progres tampil).
class PipelineCard extends StatefulWidget {
  const PipelineCard({
    super.key,
    required this.pipeline,
    required this.video,
    required this.catalog,
    this.subtitleSettings,
    this.settings = AppSettings.defaults,
  });

  final ModelCatalog catalog;
  final SubtitleSettingsRepository? subtitleSettings;

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

  SubtitleStyle _style = SubtitlePresets.style(SubtitlePreset.classic);
  bool _styleDirty = false;
  bool _styleOwn = false; // project punya gaya sendiri

  @override
  void initState() {
    super.initState();
    widget.catalog.refresh().then((_) {
      if (!mounted) return;
      final have = widget.catalog.installedWhisper;
      if (!widget.catalog.whisperInstalled(_model) && have.isNotEmpty) {
        setState(() => _model = have.first);
      }
    });
    _loadStyle();
  }

  Future<void> _loadStyle() async {
    final repo = widget.subtitleSettings;
    if (repo == null) return;
    try {
      final id = widget.video.projectId;
      final s = await repo.getForProject(id);
      final own = await repo.hasProjectStyle(id);
      if (mounted) {
        setState(() {
          _style = s;
          _styleOwn = own;
        });
      }
    } catch (e, st) {
      AppLogger.e('Gagal memuat gaya subtitle', e, st);
    }
  }

  Future<void> _makeDefault() async {
    final repo = widget.subtitleSettings;
    if (repo == null) return;
    try {
      await repo.saveDefault(_style);
      await repo.clearForProject(widget.video.projectId);
      if (mounted) {
        setState(() {
          _styleDirty = false;
          _styleOwn = false;
          _message = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Gaya subtitle disimpan sebagai default.')));
      }
    } catch (e, st) {
      AppLogger.e('Gagal menyimpan gaya default', e, st);
      if (mounted) setState(() => _message = 'Gaya subtitle gagal disimpan.');
    }
  }

  String? get _missing => widget.catalog.missingMessage(
        stt: _model,
        sourceLang: _canTranslate && _translate ? _language.code : null,
        targetLang: _canTranslate && _translate ? 'id' : null,
      );

  Future<void> _openModels() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ModelsPage(catalog: widget.catalog),
    ));
  }

  bool get _canTranslate =>
      _language.code.isNotEmpty && _language.code != 'id';

  Future<void> _start() async {
    setState(() => _message = null);
    try {
      final repo = widget.subtitleSettings;
      if (repo != null && _styleDirty) {
        await repo.saveForProject(widget.video.projectId, _style);
        _styleDirty = false;
        _styleOwn = true;
      }
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
      listenable: Listenable.merge([widget.pipeline, widget.catalog]),
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
                  if (_missing != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_missing!,
                              style: theme.textTheme.bodySmall),
                        ),
                        TextButton(
                          onPressed: _openModels,
                          child: const Text('Buka'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _missing == null ? _start : null,
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
                label: Text(widget.catalog.whisperInstalled(m)
                    ? '${m.label} ✓'
                    : m.label),
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
        if (_burn && widget.subtitleSettings != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Gaya subtitle'),
            subtitle: Text(
              '${_style.preset.label}'
              '${_styleOwn ? ' · khusus project ini' : ' · default'}',
            ),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SubtitleStyleControls(
                style: _style,
                onChanged: (v) => setState(() {
                  _style = v;
                  _styleDirty = true;
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _makeDefault,
                    child: const Text('Jadikan default'),
                  ),
                  if (_styleOwn && !_styleDirty)
                    TextButton(
                      onPressed: () async {
                        final repo = widget.subtitleSettings!;
                        await repo.clearForProject(widget.video.projectId);
                        await _loadStyle();
                      },
                      child: const Text('Pakai default'),
                    ),
                ],
              ),
              Text(
                'Perubahan berlaku untuk project ini saat proses dimulai. '
                '"Jadikan default" membuat semua render berikutnya memakai '
                'gaya ini. Pratinjau ada di Alat uji teknis.',
                style: theme.textTheme.bodySmall,
              ),
            ],
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
