import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/clip_candidate.dart';
import '../../database/models/video_record.dart';
import '../../services/settings/app_settings.dart';
import '../../services/ai/clip_detection_service.dart';
import '../../services/ai/clip_detector.dart';
import '../clips/clip_review_controller.dart';
import '../clips/clip_review_page.dart';

/// Kartu uji SEMENTARA untuk STEP 11. Layar review kandidat yang lengkap
/// (terima/tolak/ubah) dibuat di STEP 12.
class ClipDetectionTestCard extends StatefulWidget {
  const ClipDetectionTestCard({
    super.key,
    required this.service,
    required this.video,
    this.settings = AppSettings.defaults,
  });

  final AppSettings settings;
  final ClipDetectionService service;
  final VideoRecord video;

  @override
  State<ClipDetectionTestCard> createState() => _ClipDetectionTestCardState();
}

class _ClipDetectionTestCardState extends State<ClipDetectionTestCard> {
  static const _presets = {
    'Pendek (15-40 dtk)': DetectionOptions.short,
    'Standar (30-60 dtk)': DetectionOptions.standard,
    'Panjang (45-90 dtk)': DetectionOptions.long,
  };

  String _preset = 'Standar (30-60 dtk)';
  late int _maxClips = widget.settings.maxClipCount;
  bool _busy = false;
  String? _message;
  List<ClipCandidate> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final list =
          await widget.service.candidates.getByProject(widget.video.projectId);
      if (mounted) setState(() => _items = list);
    } catch (e, st) {
      AppLogger.e('Gagal memuat kandidat', e, st);
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final list = await widget.service.detect(
        projectId: widget.video.projectId,
        videoDurationMs: widget.video.durationMs,
        options: _presets[_preset]!.copyWith(maxClips: _maxClips),
      );
      if (mounted) {
        setState(() {
          _items = list;
          _message = '${list.length} kandidat clip ditemukan.';
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Deteksi clip gagal', e, st);
      if (mounted) setState(() => _message = 'Deteksi clip gagal.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReview() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ClipReviewPage(
        controller: ClipReviewController(
          repository: widget.service.candidates,
          projectId: widget.video.projectId,
          videoDurationMs: widget.video.durationMs,
        ),
        video: widget.video,
      ),
    ));
    if (mounted) await _loadExisting();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deteksi Clip (AI lokal)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Menilai transcript dengan aturan offline (pertanyaan, kata '
              'kunci, angka, kepadatan bicara, durasi). Alat uji sementara.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final name in _presets.keys)
                  ChoiceChip(
                    label: Text(name),
                    selected: _preset == name,
                    onSelected: _busy ? null : (_) => setState(() => _preset = name),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Maksimal clip: $_maxClips', style: theme.textTheme.bodySmall),
            Slider(
              value: _maxClips.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              onChanged: _busy ? null : (v) => setState(() => _maxClips = v.round()),
            ),
            FilledButton(
              onPressed: _busy ? null : _run,
              child: const Text('Cari bagian terbaik'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: theme.textTheme.bodyMedium),
            ],
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text('Review kandidat (${_items.length})'),
                onPressed: _busy ? null : _openReview,
              ),
              const SizedBox(height: 4),
              for (final c in _items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${formatClockDuration(c.startMs)} - ${formatClockDuration(c.endMs)} '
                    '(${c.duration.inSeconds} dtk)\n${c.reason ?? ''}',
                  ),
                  isThreeLine: true,
                  trailing: Text('${(c.score * 100).round()}%',
                      style: theme.textTheme.titleSmall),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
