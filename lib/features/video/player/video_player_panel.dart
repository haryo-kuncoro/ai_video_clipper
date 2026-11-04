import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/format_utils.dart';
import '../../../database/models/video_record.dart';
import 'player_math.dart';

/// Player video lokal (memutar langsung dari path file, tanpa jaringan).
///
/// Streaming dari disk oleh ExoPlayer: video tidak dimuat ke RAM.
class VideoPlayerPanel extends StatefulWidget {
  const VideoPlayerPanel({super.key, required this.video});

  final VideoRecord video;

  @override
  State<VideoPlayerPanel> createState() => _VideoPlayerPanelState();
}

class _VideoPlayerPanelState extends State<VideoPlayerPanel>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;

  /// Nilai slider saat digeser pengguna (agar tidak "melawan" update posisi).
  double? _dragFraction;

  static const _skipMs = 10000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final file = File(widget.video.filePath);
    if (!file.existsSync()) {
      _error = 'File video tidak ditemukan di perangkat.';
      return;
    }
    _init(file);
  }

  Future<void> _init(File file) async {
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e, st) {
      AppLogger.e('Player gagal diinisialisasi', e, st);
      if (!mounted) return;
      setState(() {
        _error = 'Video tidak dapat diputar. Format atau codec mungkin '
            'tidak didukung.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Jeda saat aplikasi ke latar belakang / layar terkunci.
    if (state != AppLifecycleState.resumed) {
      final c = _controller;
      if (c != null && _ready && c.value.isPlaying) unawaited(c.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(VideoPlayerController c) async {
    if (c.value.isPlaying) {
      await c.pause();
      return;
    }
    // Sudah di akhir: mulai dari awal.
    final v = c.value;
    if (v.duration > Duration.zero && v.position >= v.duration) {
      await c.seekTo(Duration.zero);
    }
    await c.play();
  }

  Future<void> _skip(VideoPlayerController c, int deltaMs) {
    final v = c.value;
    final target = skipMs(
      v.position.inMilliseconds,
      deltaMs,
      v.duration.inMilliseconds,
    );
    return c.seekTo(Duration(milliseconds: target));
  }

  Future<void> _cycleSpeed(VideoPlayerController c) =>
      c.setPlaybackSpeed(nextPlaybackSpeed(c.value.playbackSpeed));

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorBox(message: _error!);

    final c = _controller;
    if (c == null || !_ready) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Card(
          child: Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : const SizedBox.shrink(),
          ),
        ),
      );
    }

    final screenHeight = MediaQuery.sizeOf(context).height;

    return Column(
      children: [
        ConstrainedBox(
          // Video portrait tidak boleh memenuhi seluruh layar.
          constraints: BoxConstraints(maxHeight: screenHeight * 0.55),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _togglePlay(c),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    VideoPlayer(c),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (context, v, _) {
                        if (v.isPlaying) return const SizedBox.shrink();
                        return const Center(
                          child: Icon(Icons.play_circle_fill,
                              size: 64, color: Colors.white70),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, v, _) => _Controls(
            value: v,
            dragFraction: _dragFraction,
            onTogglePlay: () => _togglePlay(c),
            onBack: () => _skip(c, -_skipMs),
            onForward: () => _skip(c, _skipMs),
            onSpeed: () => _cycleSpeed(c),
            onDragStart: (f) => setState(() => _dragFraction = f),
            onDragUpdate: (f) => setState(() => _dragFraction = f),
            onDragEnd: (f) async {
              final target = clampSeekMs(
                (f * v.duration.inMilliseconds).round(),
                v.duration.inMilliseconds,
              );
              await c.seekTo(Duration(milliseconds: target));
              if (mounted) setState(() => _dragFraction = null);
            },
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.value,
    required this.dragFraction,
    required this.onTogglePlay,
    required this.onBack,
    required this.onForward,
    required this.onSpeed,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final VideoPlayerValue value;
  final double? dragFraction;
  final VoidCallback onTogglePlay;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onSpeed;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final durationMs = value.duration.inMilliseconds;
    final fraction = dragFraction ??
        progressFraction(value.position.inMilliseconds, durationMs);
    final shownMs = dragFraction != null
        ? (dragFraction! * durationMs).round()
        : value.position.inMilliseconds;
    final theme = Theme.of(context);

    return Column(
      children: [
        Slider(
          value: fraction,
          onChangeStart: onDragStart,
          onChanged: durationMs > 0 ? onDragUpdate : null,
          onChangeEnd: onDragEnd,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatClockDuration(shownMs),
                  style: theme.textTheme.bodySmall),
              Text(formatClockDuration(durationMs),
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Mundur 10 detik',
              icon: const Icon(Icons.replay_10),
              onPressed: onBack,
            ),
            IconButton.filled(
              tooltip: value.isPlaying ? 'Jeda' : 'Putar',
              iconSize: 32,
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: onTogglePlay,
            ),
            IconButton(
              tooltip: 'Maju 10 detik',
              icon: const Icon(Icons.forward_10),
              onPressed: onForward,
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onSpeed,
              child: Text(speedLabel(value.playbackSpeed)),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 40, color: theme.colorScheme.error),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
