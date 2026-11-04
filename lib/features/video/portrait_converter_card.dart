import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/video_record.dart';
import '../../services/ffmpeg/ffmpeg_service.dart';
import '../../services/ffmpeg/portrait_plan.dart';
import 'player/video_player_panel.dart';

/// Konverter landscape -> portrait 9:16 (STEP 7).
///
/// Menampilkan pratinjau area crop di atas thumbnail, lalu mengonversi
/// potongan pendek (10/15/30 detik) ke `temp/portrait_test.mp4` agar hasil
/// bisa dicek langsung. Pada STEP 13 logika yang sama dipakai untuk
/// merender clip kandidat secara otomatis.
class PortraitConverterCard extends StatefulWidget {
  const PortraitConverterCard({
    super.key,
    required this.service,
    required this.video,
    required this.workDir,
  });

  final FFmpegService service;
  final VideoRecord video;
  final Directory workDir;

  @override
  State<PortraitConverterCard> createState() => _PortraitConverterCardState();
}

class _PortraitConverterCardState extends State<PortraitConverterCard> {
  static const _taskId = 'ui-portrait';
  static const _lengths = [10, 15, 30];

  PortraitCropMode _mode = PortraitCropMode.centerCrop;
  double _focusX = 0.5;
  double _focusY = 0.5;
  double _zoom = 1.0;
  PortraitResolution _resolution = PortraitResolution.auto;
  int _lengthSec = 15;
  double _startSec = 0;

  bool _busy = false;
  double? _progress;
  String? _message;
  String? _outPath;
  int _run = 0;

  int get _durationSec => widget.video.durationMs ~/ 1000;

  double get _maxStartSec =>
      math.max(0, (_durationSec - _lengthSec).toDouble());

  PortraitPlan? _plan() {
    try {
      return planPortrait(
        sourceWidth: widget.video.width,
        sourceHeight: widget.video.height,
        mode: _mode,
        focusX: _focusX,
        focusY: _focusY,
        zoom: _zoom,
        resolution: _resolution,
      );
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _convert(PortraitPlan plan) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
      _message = null;
      _outPath = null;
    });

    try {
      final out = p.join(widget.workDir.path, 'portrait_test.mp4');
      final startMs = (math.min(_startSec, _maxStartSec) * 1000).round();
      final endMs =
          math.min(widget.video.durationMs, startMs + _lengthSec * 1000);

      final r = await widget.service.cropPortrait(
        inputPath: widget.video.filePath,
        outputPath: out,
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
        _message = 'Selesai: ${plan.outputWidth}x${plan.outputHeight} '
            '(${formatFileSize(size)}).';
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Konversi portrait gagal', e, st);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan();
    final out = _outPath;

    if (plan == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.error_outline),
          title: Text('Resolusi video terlalu kecil untuk dikonversi.'),
        ),
      );
    }

    final canMoveX = plan.crop.width < plan.sourceWidth;
    final canMoveY = plan.crop.height < plan.sourceHeight;
    final manual = _mode == PortraitCropMode.manualCrop;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Konversi Portrait 9:16', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Video di-crop (tidak di-stretch). Area terang pada pratinjau '
              'adalah bagian yang dipakai.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _CropPreview(
              thumbnailPath: widget.video.thumbnailPath,
              plan: plan,
            ),
            const SizedBox(height: 8),
            Text(
              'Crop ${plan.crop.width}x${plan.crop.height} '
              '-> output ${plan.outputWidth}x${plan.outputHeight}'
              '${plan.upscaleFactor > 1.05 ? ' (diperbesar ${plan.upscaleFactor.toStringAsFixed(2)}x)' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<PortraitCropMode>(
              segments: const [
                ButtonSegment(
                  value: PortraitCropMode.centerCrop,
                  label: Text('Tengah'),
                ),
                ButtonSegment(
                  value: PortraitCropMode.manualCrop,
                  label: Text('Manual'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() {
                        _mode = s.first;
                        if (_mode == PortraitCropMode.centerCrop) {
                          _focusX = 0.5;
                          _focusY = 0.5;
                          _zoom = 1.0;
                        }
                      }),
            ),
            const SizedBox(height: 4),
            Text(
              'Mode "Ikuti wajah" tersedia di STEP 14.',
              style: theme.textTheme.bodySmall,
            ),
            if (manual) ...[
              _LabeledSlider(
                label: 'Posisi horizontal',
                value: _focusX,
                min: 0,
                max: 1,
                onChanged:
                    (!canMoveX || _busy) ? null : (v) => setState(() => _focusX = v),
              ),
              _LabeledSlider(
                label: 'Posisi vertikal',
                value: _focusY,
                min: 0,
                max: 1,
                onChanged:
                    (!canMoveY || _busy) ? null : (v) => setState(() => _focusY = v),
              ),
              _LabeledSlider(
                label: 'Zoom ${_zoom.toStringAsFixed(1)}x',
                value: _zoom,
                min: 1,
                max: 3,
                onChanged: _busy ? null : (v) => setState(() => _zoom = v),
              ),
            ],
            const SizedBox(height: 12),
            Text('Resolusi output', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<PortraitResolution>(
              segments: [
                for (final r in PortraitResolution.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_resolution},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _resolution = s.first),
            ),
            const SizedBox(height: 12),
            Text('Bagian yang diuji', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: [
                for (final s in _lengths)
                  ButtonSegment(value: s, label: Text('$s dtk')),
              ],
              selected: {_lengthSec},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() {
                        _lengthSec = s.first;
                        _startSec = math.min(_startSec, _maxStartSec);
                      }),
            ),
            if (_maxStartSec > 0)
              _LabeledSlider(
                label: 'Mulai dari ${formatClockDuration((_startSec * 1000).round())}',
                value: math.min(_startSec, _maxStartSec),
                min: 0,
                max: _maxStartSec,
                onChanged: _busy ? null : (v) => setState(() => _startSec = v),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Video lebih pendek dari bagian uji; seluruh video dikonversi.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _convert(plan),
              child: const Text('Konversi ke Portrait'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
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
            if (out != null) ...[
              const SizedBox(height: 12),
              VideoPlayerPanel(
                key: ValueKey('portrait-$_run'),
                video: VideoRecord(
                  projectId: widget.video.projectId,
                  filePath: out,
                  fileName: 'portrait_test.mp4',
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

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Thumbnail sumber dengan area crop yang disorot (bagian luar digelapkan).
class _CropPreview extends StatelessWidget {
  const _CropPreview({required this.thumbnailPath, required this.plan});

  final String? thumbnailPath;
  final PortraitPlan plan;

  @override
  Widget build(BuildContext context) {
    final thumb = thumbnailPath;
    final aspect = plan.sourceWidth / plan.sourceHeight;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: AspectRatio(
          aspectRatio: aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null)
                  Image.file(
                    File(thumb),
                    fit: BoxFit.fill,
                    errorBuilder: (context, error, stack) =>
                        const ColoredBox(color: Colors.black26),
                  )
                else
                  const ColoredBox(color: Colors.black26),
                CustomPaint(
                  painter: _CropPainter(
                    left: plan.crop.x / plan.sourceWidth,
                    top: plan.crop.y / plan.sourceHeight,
                    width: plan.crop.width / plan.sourceWidth,
                    height: plan.crop.height / plan.sourceHeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      left * size.width,
      top * size.height,
      width * size.width,
      height * size.height,
    );
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(rect),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black54);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.left != left ||
      old.top != top ||
      old.width != width ||
      old.height != height;
}
