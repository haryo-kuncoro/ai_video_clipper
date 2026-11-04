import 'model_utils.dart';

enum JobType { extractAudio, transcribe, analyze, renderClip, exportClip }

enum JobStatus { queued, running, completed, failed, cancelled }

class ProcessingJob {
  const ProcessingJob({
    this.id,
    required this.projectId,
    required this.type,
    this.status = JobStatus.queued,
    this.progress = 0,
    this.payload,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int projectId;
  final JobType type;
  final JobStatus status;

  /// 0.0 - 1.0
  final double progress;

  /// Parameter job dalam JSON (mis. id clip yang dirender).
  final String? payload;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProcessingJob.fromMap(Map<String, Object?> m) => ProcessingJob(
        id: m['id'] as int,
        projectId: m['project_id'] as int,
        type: enumByName(
            JobType.values, m['type'] as String?, JobType.renderClip),
        status: enumByName(
            JobStatus.values, m['status'] as String?, JobStatus.failed),
        progress: (m['progress'] as num).toDouble(),
        payload: m['payload'] as String?,
        errorMessage: m['error_message'] as String?,
        createdAt: fromEpochMs(m['created_at'] as int),
        updatedAt: fromEpochMs(m['updated_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'type': type.name,
        'status': status.name,
        'progress': progress,
        'payload': payload,
        'error_message': errorMessage,
        'created_at': toEpochMs(createdAt),
        'updated_at': toEpochMs(updatedAt),
      };
}
