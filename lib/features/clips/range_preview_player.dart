import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/app_logger.dart';
import 'clip_range.dart';

/// Pratinjau satu rentang video lokal: memutar dari [startMs] dan berhenti
/// otomatis di [endMs]. Streaming dari disk, video tidak dimuat ke RAM.
class RangePreviewPlayer extends StatefulWidget {
  const RangePreviewPlayer({
    super.key,
    required this.filePath,
    required this.startMs,
    required this.endMs,
  });

  final String filePath;
  final int startMs;
  final int endMs;

  @override
  State<RangePreviewPlayer> createState() => _RangePreviewPlayerState();
}

class _RangePreviewPlayerState extends State<RangePreviewPlayer> {
  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      _error = 'File video tidak ditemukan di perangkat.';
      return;
    }
    _init(file);
  }

  Future<void> _init(File file) async {
    final c = VideoPlayerController.file(file);
    _controller = c;
    try {
      await c.initialize();
      await c.seekTo(Duration(milliseconds: widget.startMs));
      c.addListener(_onTick);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e, st) {
      AppLogger.e('Pratinjau gagal diinisialisasi', e, st);
      if (!mounted) return;
      setState(() => _error = 'Pratinjau tidak dapat diputar.');
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying &&
        c.value.position.inMilliseconds >= widget.endMs) {
      unawaited(c.pause());
      unawaited(c.seekTo(Duration(milliseconds: widget.startMs)));
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(RangePreviewPlayer old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c != null &&
        c.value.isInitialized &&
        (old.startMs != widget.startMs || old.endMs != widget.endMs)) {
      unawaited(c.pause());
      unawaited(c.seekTo(Duration(milliseconds: widget.startMs)));
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
      return;
    }
    final pos = c.value.position.inMilliseconds;
    if (pos < widget.startMs || pos >= widget.endMs - 100) {
      await c.seekTo(Duration(milliseconds: widget.startMs));
    }
    await c.play();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      );
    }
    final c = _controller;
    if (!_ready || c == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final posMs = c.value.position.inMilliseconds;
    final span = (widget.endMs - widget.startMs).clamp(1, 1 << 30).toInt();
    final frac = ((posMs - widget.startMs) / span).clamp(0.0, 1.0).toDouble();

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: c.value.isPlaying ? 'Jeda' : 'Putar',
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: _toggle,
            ),
            Expanded(child: LinearProgressIndicator(value: frac)),
            const SizedBox(width: 8),
            Text(
              '${formatPreciseMs(posMs < widget.startMs ? 0 : posMs - widget.startMs)}'
              ' / ${formatPreciseMs(span)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}
