import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../database/models/project_summary.dart';
import '../../database/models/video_record.dart';
import '../clips/clip_export_card.dart';
import '../video/clip_detection_test_card.dart';
import '../video/clip_render_test_card.dart';
import '../video/ffmpeg_test_card.dart';
import '../video/pipeline_card.dart';
import '../video/portrait_converter_card.dart';
import '../video/subtitle_test_card.dart';
import '../video/transcription_test_card.dart';
import '../video/player/video_player_panel.dart';
import 'project_actions.dart';
import 'project_status_label.dart';
import 'projects_controller.dart';

enum _DetailAction { rename, delete }

class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({
    super.key,
    required this.controller,
    required this.projectId,
  });

  final ProjectsController controller;
  final int projectId;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  ProjectSummary? _summary;
  VideoRecord? _video;
  bool _loading = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.controller.getSummary(widget.projectId);
      final v = await widget.controller.getSourceVideo(widget.projectId);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _video = v;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      AppLogger.e('Gagal memuat detail project', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Project tidak dapat dimuat.';
      });
    }
  }

  Future<void> _rename(ProjectSummary s) async {
    final changed = await renameProjectFlow(context, widget.controller, s);
    if (changed) await _load();
  }

  Future<void> _delete(ProjectSummary s) async {
    final navigator = Navigator.of(context);
    final deleted = await deleteProjectFlow(context, widget.controller, s);
    if (deleted) navigator.pop();
  }

  Future<void> _pickVideo() async {
    if (_importing) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      final result = await widget.controller.importVideo(widget.projectId);
      if (result != null) {
        await _load();
        if (!result.hasAudio) {
          messenger.showSnackBar(const SnackBar(
            content: Text(
                'Video ini tidak memiliki audio, transcript tidak dapat dibuat.'),
          ));
        }
      }
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, st) {
      AppLogger.e('Import video gagal', e, st);
      messenger.showSnackBar(
          const SnackBar(content: Text('Video gagal diproses.')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Project'),
        actions: [
          if (s != null)
            PopupMenuButton<_DetailAction>(
              tooltip: 'Menu project',
              onSelected: (a) {
                switch (a) {
                  case _DetailAction.rename:
                    _rename(s);
                  case _DetailAction.delete:
                    _delete(s);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _DetailAction.rename,
                  child: Text('Ganti nama'),
                ),
                PopupMenuItem(
                  value: _DetailAction.delete,
                  child: Text('Hapus project'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(child: _body(context, s)),
    );
  }

  Widget _body(BuildContext context, ProjectSummary? s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (s == null) return const Center(child: Text('Project tidak ditemukan.'));

    final theme = Theme.of(context);
    final project = s.project;
    final video = _video;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (video != null)
          VideoPlayerPanel(key: ValueKey(video.id), video: video)
        else
          const _EmptyVideoBox(),
        const SizedBox(height: 16),
        Text(project.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(label: Text(projectStatusLabel(project.status))),
        ),
        const SizedBox(height: 12),
        if (video == null)
          FilledButton.icon(
            icon: const Icon(Icons.video_library_outlined),
            label: const Text('Pilih Video'),
            onPressed: _importing ? null : _pickVideo,
          ),
        if (_importing) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            'Menyalin dan membaca video... Jangan tutup aplikasi.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              if (video != null) ...[
                _InfoTile('Nama file', video.fileName),
                _InfoTile('Durasi', formatClockDuration(video.durationMs)),
                _InfoTile(
                  'Resolusi',
                  '${video.width}x${video.height} '
                      '(${video.height > video.width ? 'portrait' : 'landscape'})',
                ),
                _InfoTile('Ukuran file', formatFileSize(video.fileSize)),
              ] else
                const _InfoTile('Video sumber', 'Belum ada video'),
              _InfoTile('Jumlah clip', '${s.clipCount}'),
              _InfoTile('Dibuat', formatRelativeDate(project.createdAt)),
              _InfoTile('Diperbarui', formatRelativeDate(project.updatedAt)),
            ],
          ),
        ),
        if (video != null && widget.controller.ffmpeg != null) ...[
          const SizedBox(height: 12),
          if (widget.controller.pipeline != null &&
              widget.controller.settings.autoPipelineEnabled) ...[
            PipelineCard(
              key: ValueKey('pipeline-${video.id}'),
              pipeline: widget.controller.pipeline!,
              video: video,
              settings: widget.controller.settings,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.controller.transcription != null) ...[
            TranscriptionTestCard(
              key: ValueKey('stt-${video.id}'),
              service: widget.controller.transcription!,
              video: video,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.controller.clipDetection != null) ...[
            ClipDetectionTestCard(
              key: ValueKey('detect-${video.id}'),
              service: widget.controller.clipDetection!,
              video: video,
              settings: widget.controller.settings,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.controller.clipRender != null) ...[
            ClipRenderTestCard(
              key: ValueKey('render-${video.id}'),
              service: widget.controller.clipRender!,
              video: video,
              transcripts: widget.controller.transcription?.transcripts,
              settings: widget.controller.settings,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.controller.exportService != null &&
              widget.controller.clipRender != null) ...[
            ClipExportCard(
              key: ValueKey('export-${video.id}'),
              service: widget.controller.exportService!,
              clips: widget.controller.clipRender!.clips,
              projectId: project.id!,
              exportSrtEnabled: widget.controller.settings.exportSrtEnabled,
            ),
            const SizedBox(height: 12),
          ],
          // Alat uji teknis STEP 6-8: fungsinya kini tercakup di editor clip,
          // dipertahankan (terlipat) untuk pengujian langkah-langkah awal.
          Card(
            child: ExpansionTile(
              title: const Text('Alat uji teknis (STEP 6-8)'),
              subtitle: const Text('FFmpeg, portrait, dan subtitle'),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                PortraitConverterCard(
                  key: ValueKey('portrait-${video.id}'),
                  service: widget.controller.ffmpeg!,
                  video: video,
                  workDir: widget.controller.paths.projectTempDir(project.id!),
                ),
                const SizedBox(height: 8),
                if (widget.controller.subtitleSettings != null) ...[
                  SubtitleTestCard(
                    key: ValueKey('subtitle-${video.id}'),
                    service: widget.controller.ffmpeg!,
                    settings: widget.controller.subtitleSettings!,
                    video: video,
                    workDir: widget.controller.paths.projectTempDir(project.id!),
                  ),
                  const SizedBox(height: 8),
                ],
                FFmpegTestCard(
                  service: widget.controller.ffmpeg!,
                  video: video,
                  workDir: widget.controller.paths.projectTempDir(project.id!),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyVideoBox extends StatelessWidget {
  const _EmptyVideoBox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Card(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_outlined,
                  size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 8),
              Text('Belum ada video', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
        ),
      ),
    );
  }
}
