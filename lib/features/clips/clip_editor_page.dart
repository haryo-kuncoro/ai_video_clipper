import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/clip.dart';
import '../../database/models/clip_edit.dart';
import '../../database/models/video_record.dart';
import '../../database/repositories/transcript_repository.dart';
import '../../services/face/face_models.dart';
import '../../services/ffmpeg/portrait_plan.dart';
import '../../services/render/clip_render_service.dart';
import '../../services/subtitle/subtitle_style.dart';
import '../../services/transcription/transcription_models.dart';
import '../transcript/transcript_page.dart';
import '../video/subtitle_style_controls.dart';
import 'clip_range.dart';
import 'time_nudge_row.dart';

/// Editor clip: ubah waktu, posisi crop (tengah/wajah/manual), subtitle, lalu
/// render ulang. Hasil lama baru diganti bila render ulang sukses.
class ClipEditorPage extends StatefulWidget {
  const ClipEditorPage({
    super.key,
    required this.service,
    required this.clip,
    required this.video,
    this.transcripts,
  });

  final ClipRenderService service;
  final Clip clip;
  final VideoRecord video;
  final TranscriptRepository? transcripts;

  @override
  State<ClipEditorPage> createState() => _ClipEditorPageState();
}

class _ClipEditorPageState extends State<ClipEditorPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.clip.title);
  late int _start = widget.clip.startMs;
  late int _end = widget.clip.endMs;

  bool _loading = true;
  late ClipEdit _edit = ClipEdit(clipId: widget.clip.id!);
  SubtitleStyle _projectStyle = const SubtitleStyle();
  bool _customStyle = false;
  SubtitleStyle _style = const SubtitleStyle();

  String? _frame;
  Timer? _frameTimer;
  FocusResult? _faceFocus;
  bool _detecting = false;
  String? _faceNote;

  bool _busy = false;
  double? _progress;
  CancelToken? _cancel;
  String? _message;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _cancel?.cancel();
    _title.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final saved = await widget.service.edits.get(widget.clip.id!);
      final project =
          await widget.service.projectSubtitleStyle(widget.video.projectId);
      if (!mounted) return;
      setState(() {
        if (saved != null) _edit = saved;
        _projectStyle = project;
        _customStyle = saved?.style != null;
        _style = saved?.style ?? project;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.e('Gagal memuat pengaturan edit', e, st);
      if (mounted) setState(() => _loading = false);
    }
    unawaited(_loadFrame());
  }

  Future<void> _loadFrame() async {
    final mid = ((_start + _end) / 2).round();
    final path = await widget.service.previewFrame(widget.video, mid);
    if (mounted) setState(() => _frame = path);
  }

  void _scheduleFrame() {
    _frameTimer?.cancel();
    _frameTimer = Timer(const Duration(milliseconds: 500), _loadFrame);
  }

  void _nudgeStart(int d) {
    setState(() {
      _message = null;
      var v = _start + d;
      if (v < 0) v = 0;
      if (v > _end - minClipMs) v = _end - minClipMs;
      _start = v < 0 ? 0 : v;
      _faceFocus = null;
    });
    _scheduleFrame();
  }

  void _nudgeEnd(int d) {
    final max = widget.video.durationMs;
    setState(() {
      _message = null;
      var v = _end + d;
      if (max > 0 && v > max) v = max;
      if (v < _start + minClipMs) v = _start + minClipMs;
      _end = v;
      _faceFocus = null;
    });
    _scheduleFrame();
  }

  Future<void> _detectFace() async {
    if (_detecting) return;
    setState(() {
      _detecting = true;
      _faceNote = null;
    });
    final focus = await widget.service.detectFocus(widget.video, _start, _end);
    if (!mounted) return;
    setState(() {
      _detecting = false;
      _faceFocus = focus;
      _faceNote = focus == null
          ? 'Wajah tidak terdeteksi. Render akan memakai crop tengah.'
          : 'Wajah terdeteksi di ${focus.hits}/${focus.samples} frame.';
    });
  }

  PortraitPlan? _previewPlan() {
    try {
      switch (_edit.cropMode) {
        case EditCropMode.center:
          return planPortrait(
              sourceWidth: widget.video.width, sourceHeight: widget.video.height);
        case EditCropMode.face:
          final f = _faceFocus;
          return planPortrait(
            sourceWidth: widget.video.width,
            sourceHeight: widget.video.height,
            mode: f == null
                ? PortraitCropMode.centerCrop
                : PortraitCropMode.faceAwareCrop,
            focusX: f?.x,
            focusY: f?.y,
          );
        case EditCropMode.manual:
          return planPortrait(
            sourceWidth: widget.video.width,
            sourceHeight: widget.video.height,
            mode: PortraitCropMode.manualCrop,
            focusX: _edit.focusX ?? 0.5,
            focusY: _edit.focusY ?? 0.5,
            zoom: _edit.zoom,
          );
      }
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final cancel = CancelToken();
    setState(() {
      _busy = true;
      _cancel = cancel;
      _progress = null;
      _message = null;
    });
    try {
      final edit = _edit.copyWith(
        burnSubtitles: _edit.burnSubtitles,
        style: _customStyle ? _style : null,
        clearStyle: !_customStyle,
      );
      final r = await widget.service.rerenderClip(
        video: widget.video,
        clip: widget.clip,
        edit: edit,
        startMs: _start,
        endMs: _end,
        title: _title.text,
        cancel: cancel,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      if (!mounted) return;
      if (r.ok) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Clip diperbarui.')));
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _message = r.cancelled
            ? 'Dibatalkan. Clip lama tidak berubah.'
            : (r.message ?? 'Render ulang gagal.');
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Render ulang gagal', e, st);
      if (mounted) setState(() => _message = 'Render ulang gagal.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancel = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _openTranscript() async {
    final repo = widget.transcripts;
    if (repo == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TranscriptPage(
        repository: repo,
        projectId: widget.video.projectId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Clip')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _title,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Judul',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Waktu', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TimeNudgeRow(
                    label: 'Mulai',
                    valueMs: _start,
                    enabled: !_busy,
                    onNudge: _nudgeStart,
                  ),
                  const SizedBox(height: 12),
                  TimeNudgeRow(
                    label: 'Selesai',
                    valueMs: _end,
                    enabled: !_busy,
                    onNudge: _nudgeEnd,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Durasi: ${((_end - _start) / 1000).toStringAsFixed(1)} dtk '
                    '(min 3 dtk, maks 3 menit)',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Divider(height: 32),
                  Text('Crop 9:16', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _CropPreview(
                    video: widget.video,
                    framePath: _frame,
                    plan: _previewPlan(),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<EditCropMode>(
                    segments: [
                      for (final m in EditCropMode.values)
                        ButtonSegment(value: m, label: Text(m.label)),
                    ],
                    selected: {_edit.cropMode},
                    onSelectionChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _edit = _edit.copyWith(cropMode: v.first)),
                  ),
                  if (_edit.cropMode == EditCropMode.face) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.face_outlined),
                      label: Text(_detecting ? 'Mendeteksi...' : 'Deteksi wajah'),
                      onPressed: (_busy || _detecting) ? null : _detectFace,
                    ),
                    if (_faceNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_faceNote!, style: theme.textTheme.bodySmall),
                      ),
                  ],
                  if (_edit.cropMode == EditCropMode.manual) ...[
                    _labeledSlider(
                      'Posisi horizontal ${(((_edit.focusX ?? 0.5)) * 100).round()}%',
                      _edit.focusX ?? 0.5,
                      0,
                      1,
                      (v) => setState(() => _edit = _edit.copyWith(focusX: v)),
                    ),
                    _labeledSlider(
                      'Posisi vertikal ${(((_edit.focusY ?? 0.5)) * 100).round()}%',
                      _edit.focusY ?? 0.5,
                      0,
                      1,
                      (v) => setState(() => _edit = _edit.copyWith(focusY: v)),
                    ),
                    _labeledSlider(
                      'Zoom ${_edit.zoom.toStringAsFixed(1)}x',
                      _edit.zoom,
                      1,
                      4,
                      (v) => setState(() => _edit = _edit.copyWith(zoom: v)),
                    ),
                  ],
                  const Divider(height: 32),
                  Text('Subtitle', style: theme.textTheme.titleSmall),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bakar subtitle dari transcript'),
                    value: _edit.burnSubtitles,
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _edit = _edit.copyWith(burnSubtitles: v)),
                  ),
                  if (_edit.burnSubtitles) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Gaya khusus clip ini'),
                      subtitle: const Text('Mati: ikut gaya project'),
                      value: _customStyle,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _customStyle = v;
                                if (v) _style = _projectStyle;
                              }),
                    ),
                    if (_customStyle)
                      SubtitleStyleControls(
                        style: _style,
                        enabled: !_busy,
                        onChanged: (s) => setState(() => _style = s),
                      ),
                    if (widget.transcripts != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.article_outlined),
                          label: const Text('Edit teks transcript'),
                          onPressed: _busy ? null : _openTranscript,
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Simpan & render ulang'),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _progress),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _progress == null
                                ? 'Menyiapkan...'
                                : 'Merender ${(_progress! * 100).round()}%',
                            style: theme.textTheme.bodySmall,
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
                    Text(_message!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _labeledSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: _busy ? null : onChanged,
        ),
      ],
    );
  }
}

/// Frame sumber dengan area crop 9:16 disorot (di luar area digelapkan).
class _CropPreview extends StatelessWidget {
  const _CropPreview({
    required this.video,
    required this.framePath,
    required this.plan,
  });

  final VideoRecord video;
  final String? framePath;
  final PortraitPlan? plan;

  @override
  Widget build(BuildContext context) {
    final w = video.width > 0 ? video.width : 16;
    final h = video.height > 0 ? video.height : 9;
    final path = framePath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: w / h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null && File(path).existsSync())
              Image.file(File(path), fit: BoxFit.fill, key: ValueKey(path))
            else
              const ColoredBox(
                color: Colors.black12,
                child: Center(child: Icon(Icons.image_outlined)),
              ),
            if (plan != null)
              CustomPaint(
                painter: _CropPainter(
                  left: plan!.crop.x / plan!.sourceWidth,
                  top: plan!.crop.y / plan!.sourceHeight,
                  width: plan!.crop.width / plan!.sourceWidth,
                  height: plan!.crop.height / plan!.sourceHeight,
                ),
              ),
          ],
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
    final full = Offset.zero & size;
    final crop = Rect.fromLTWH(
      left * size.width,
      top * size.height,
      width * size.width,
      height * size.height,
    );
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRect(crop),
    );
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      crop,
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
