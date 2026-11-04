import 'model_utils.dart';

enum CandidateStatus { pending, accepted, rejected, generated }

class ClipCandidate {
  const ClipCandidate({
    this.id,
    required this.projectId,
    required this.startMs,
    required this.endMs,
    required this.title,
    this.hook,
    this.score = 0,
    this.reason,
    this.status = CandidateStatus.pending,
    required this.createdAt,
  });

  final int? id;
  final int projectId;
  final int startMs;
  final int endMs;
  final String title;
  final String? hook;
  final double score;
  final String? reason;
  final CandidateStatus status;
  final DateTime createdAt;

  Duration get duration => Duration(milliseconds: endMs - startMs);

  factory ClipCandidate.fromMap(Map<String, Object?> m) => ClipCandidate(
        id: m['id'] as int,
        projectId: m['project_id'] as int,
        startMs: m['start_ms'] as int,
        endMs: m['end_ms'] as int,
        title: m['title'] as String,
        hook: m['hook'] as String?,
        score: (m['score'] as num).toDouble(),
        reason: m['reason'] as String?,
        status: enumByName(CandidateStatus.values, m['status'] as String?,
            CandidateStatus.pending),
        createdAt: fromEpochMs(m['created_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'start_ms': startMs,
        'end_ms': endMs,
        'title': title,
        'hook': hook,
        'score': score,
        'reason': reason,
        'status': status.name,
        'created_at': toEpochMs(createdAt),
      };
}
