import 'model_utils.dart';

enum ClipStatus { pending, rendering, completed, failed }

class Clip {
  const Clip({
    this.id,
    required this.projectId,
    this.candidateId,
    this.filePath,
    this.thumbnailPath,
    required this.startMs,
    required this.endMs,
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
    required this.title,
    this.score = 0,
    this.status = ClipStatus.pending,
    required this.createdAt,
  });

  final int? id;
  final int projectId;
  final int? candidateId;
  final String? filePath;
  final String? thumbnailPath;
  final int startMs;
  final int endMs;
  final int durationMs;
  final int width;
  final int height;
  final String title;
  final double score;
  final ClipStatus status;
  final DateTime createdAt;

  factory Clip.fromMap(Map<String, Object?> m) => Clip(
        id: m['id'] as int,
        projectId: m['project_id'] as int,
        candidateId: m['candidate_id'] as int?,
        filePath: m['file_path'] as String?,
        thumbnailPath: m['thumbnail_path'] as String?,
        startMs: m['start_ms'] as int,
        endMs: m['end_ms'] as int,
        durationMs: m['duration_ms'] as int,
        width: m['width'] as int,
        height: m['height'] as int,
        title: m['title'] as String,
        score: (m['score'] as num).toDouble(),
        status: enumByName(
            ClipStatus.values, m['status'] as String?, ClipStatus.pending),
        createdAt: fromEpochMs(m['created_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'candidate_id': candidateId,
        'file_path': filePath,
        'thumbnail_path': thumbnailPath,
        'start_ms': startMs,
        'end_ms': endMs,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
        'title': title,
        'score': score,
        'status': status.name,
        'created_at': toEpochMs(createdAt),
      };
}
