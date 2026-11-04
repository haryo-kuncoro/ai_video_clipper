import 'model_utils.dart';

enum ProjectStatus {
  created,
  videoAdded,
  transcribing,
  transcribed,
  analyzing,
  analyzed,
  rendering,
  completed,
  failed,
}

class Project {
  const Project({
    this.id,
    required this.name,
    this.sourceVideoId,
    this.status = ProjectStatus.created,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final int? sourceVideoId;
  final ProjectStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Project.fromMap(Map<String, Object?> m) => Project(
        id: m['id'] as int,
        name: m['name'] as String,
        sourceVideoId: m['source_video_id'] as int?,
        status: enumByName(
            ProjectStatus.values, m['status'] as String?, ProjectStatus.created),
        createdAt: fromEpochMs(m['created_at'] as int),
        updatedAt: fromEpochMs(m['updated_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'source_video_id': sourceVideoId,
        'status': status.name,
        'created_at': toEpochMs(createdAt),
        'updated_at': toEpochMs(updatedAt),
      };
}
