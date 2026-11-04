import 'project.dart';

/// Project + ringkasan untuk daftar Home (jumlah clip, durasi video sumber).
class ProjectSummary {
  const ProjectSummary({
    required this.project,
    this.clipCount = 0,
    this.sourceDurationMs,
  });

  final Project project;
  final int clipCount;

  /// Null bila project belum punya video.
  final int? sourceDurationMs;

  factory ProjectSummary.fromMap(Map<String, Object?> m) => ProjectSummary(
        project: Project.fromMap(m),
        clipCount: (m['clip_count'] as int?) ?? 0,
        sourceDurationMs: m['duration_ms'] as int?,
      );
}
