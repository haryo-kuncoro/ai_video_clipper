import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/transcript.dart';
import '../../database/models/video_record.dart';
import '../../database/repositories/subtitle_settings_repository.dart';
import '../../services/ffmpeg/ffmpeg_service.dart';
import '../../services/ffmpeg/portrait_plan.dart';
import '../../services/subtitle/subtitle_cue.dart';
import '../../services/subtitle/subtitle_renderer.dart';
import '../../services/subtitle/subtitle_style.dart';
import 'player/video_player_panel.dart';
import 'subtitle_style_controls.dart';

/// Kartu uji SEMENTARA untuk subtitle (STEP 8): memakai teks contoh karena
/// transcript baru ada setelah STEP 9-10. Menyimpan gaya ke SQLite, merender
/// 15 detik pertama menjadi portrait + subtitle, lalu memutarnya.
/// Pada STEP 15 (editor) gaya ini dipakai pada clip sungguhan.
class SubtitleTestCard extends StatefulWidget {
  const SubtitleTestCard({
    super.key,
    required this.service,
    required this.settings,
    required this.video,
    required this.workDir,
  });

  final FFmpegService service;
  final SubtitleSettingsRepository settings;
  final VideoRecord video;
  final Directory workDir;

  @override
  State<SubtitleTestCard> createState() => _SubtitleTestCardState();
}

class _SubtitleTestCardState extends State<SubtitleTestCard> {
  static const _taskId = 'ui-subtitle';

  static const _sampleLines = [
    'Hari ini saya akan membahas kesalahan terbesar saat memulai bisnis.',
    'Dan ternyata banyak orang melakukan hal yang sama.',
    'Kuncinya adalah mulai dari masalah pelanggan, bukan dari produk.',
    'Jadi sebelum membuat apa pun, tanyakan dulu kepada mereka.',
  ];

  SubtitleStyle _style = SubtitlePresets.style(SubtitlePreset.classic);
  bool _loaded = false;
  bool _projectOwn = false;

  bool _busy = false;
  String _phase = '';
  double? _progress;
  String? _message;
  String? _outPath;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  Future<void> _loadStyle() async {
    try {
      final s = await widget.settings.getDefault();
      final own = await widget.settings.hasProjectStyle(widget.video.projectId);
      if (!mounted) return;
      setState(() {
        _style = s;
        _projectOwn = own;
        _loaded = true;
      });
    } catch (e, st) {
      AppLogger.e('Gagal memuat gaya subtitle', e, st);
      if (mounted) setState(() => _loaded = true);
    }
  }

  List<TranscriptSegment> _sampleSegments(int startMs, int endMs) {
    final step = (endMs - startMs) ~/ _sampleLines.length;
    return [
      for (var i = 0; i < _sampleLines.length; i++)
        TranscriptSegment(
          startMs: startMs + i * step,
          endMs: startMs + (i + 1) * step,
          text: _sampleLines[i],
        ),
    ];
  }

  Future<void> _saveDefault() async {
    try {
      await widget.settings.saveDefault(_style);
      if (!mounted) return;
      setState(() => _message =
          'Disimpan sebagai gaya default. Semua render berikutnya '
          '(proses otomatis, clip) memakai gaya ini.');
    } catch (e, st) {
      AppLogger.e('Gagal menyimpan gaya default', e, st);
      if (mounted) setState(() => _message = 'Gaya default gagal disimpan.');
    }
  }

  Future<void> _useDefaultForProject() async {
    try {
      await widget.settings.clearForProject(widget.video.projectId);
      if (!mounted) return;
      setState(() {
        _projectOwn = false;
        _message = 'Project ini kini mengikuti gaya default.';
      });
    } catch (e, st) {
      AppLogger.e('Gagal menghapus gaya project', e, st);
    }
  }

  Future<void> _burn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _phase = 'Menyiapkan subtitle...';
      _progress = null;
      _message = null;
      _outPath = null;
    });

    final subsDir = Directory(p.join(widget.workDir.path, 'subs'));
    try {
      final video = widget.video;

      final plan = planPortrait(
        sourceWidth: video.width,
        sourceHeight: video.height,
      );
      const startMs = 0;
      final endMs = math.min(video.durationMs, 15000);

      final cues = buildCues(
        segments: _sampleSegments(startMs, endMs),
        clipStartMs: startMs,
        clipEndMs: endMs,
        maxCharsPerLine: _style.maxCharsPerLine,
      );
      if (cues.isEmpty) {
        setState(() => _message = 'Tidak ada subtitle pada rentang ini.');
        return;
      }

      final overlays = await SubtitleRenderer().render(
        cues: cues,
        style: _style,
        outWidth: plan.outputWidth,
        outHeight: plan.outputHeight,
        outDir: subsDir,
      );
      if (!mounted) return;
      setState(() => _phase = 'Merender video...');

      final out = p.join(widget.workDir.path, 'subtitle_test.mp4');
      final r = await widget.service.burnSubtitle(
        inputPath: video.filePath,
        outputPath: out,
        overlays: overlays,
        plan: plan,
        startMs: startMs,
        endMs: endMs,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
        taskId: _taskId,
      );
      if (!mounted) return;

      if (!r.ok) {
        setState(() => _message =
            r.cancelled ? 'Dibatalkan.' : (r.message ?? 'Proses gagal.'));
        return;
      }
      final size = await File(out).length();
      if (!mounted) return;
      setState(() {
        _run++;
        _outPath = out;
        _message = 'Selesai: ${cues.length} subtitle, '
            '${plan.outputWidth}x${plan.outputHeight} '
            '(${formatFileSize(size)}).';
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Render subtitle gagal', e, st);
      if (mounted) setState(() => _message = 'Proses gagal.');
    } finally {
      try {
        if (await subsDir.exists()) await subsDir.delete(recursive: true);
      } on FileSystemException catch (e) {
        AppLogger.e('Gagal membersihkan gambar subtitle', e);
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _style;
    final out = _outPath;

    if (!_loaded) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Subtitle', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Atur gaya subtitle, lihat pratinjau dengan teks contoh, lalu '
              'simpan sebagai GAYA DEFAULT yang dipakai semua render.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SubtitleStyleControls(
              style: s,
              enabled: !_busy,
              onChanged: (v) => setState(() => _style = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _burn,
              child: const Text('Pratinjau (render 15 detik pertama)'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _saveDefault,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Simpan sebagai default'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() =>
                          _style = SubtitlePresets.style(SubtitlePreset.classic)),
                  child: const Text('Reset ke Classic'),
                ),
              ],
            ),
            if (_projectOwn) ...[
              const SizedBox(height: 4),
              Text(
                'Project ini memakai gaya sendiri yang menimpa default.',
                style: theme.textTheme.bodySmall,
              ),
              TextButton(
                onPressed: _busy ? null : _useDefaultForProject,
                child: const Text('Pakai gaya default untuk project ini'),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _progress == null
                          ? _phase
                          : 'Merender ${(_progress! * 100).round()}%',
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
            if (out != null) ...[
              const SizedBox(height: 12),
              VideoPlayerPanel(
                key: ValueKey('subtitle-$_run'),
                video: VideoRecord(
                  projectId: widget.video.projectId,
                  filePath: out,
                  fileName: 'subtitle_test.mp4',
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
