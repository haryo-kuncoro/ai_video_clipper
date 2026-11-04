import 'model_utils.dart';

enum ExportKind { video, srt }

class ExportRecord {
  const ExportRecord({
    this.id,
    required this.clipId,
    required this.kind,
    required this.displayName,
    required this.uri,
    required this.exportedAt,
  });

  final int? id;
  final int clipId;
  final ExportKind kind;
  final String displayName;
  final String uri;
  final DateTime exportedAt;

  factory ExportRecord.fromMap(Map<String, Object?> m) => ExportRecord(
        id: m['id'] as int,
        clipId: m['clip_id'] as int,
        kind: enumByName(ExportKind.values, m['kind'] as String?, ExportKind.video),
        displayName: m['display_name'] as String,
        uri: m['uri'] as String,
        exportedAt: fromEpochMs(m['exported_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'clip_id': clipId,
        'kind': kind.name,
        'display_name': displayName,
        'uri': uri,
        'exported_at': toEpochMs(exportedAt),
      };
}
