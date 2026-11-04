import 'model_utils.dart';

/// Asal file video.
/// - [copied]: salinan yang dikelola aplikasi -> boleh dihapus bersama project.
/// - [reference]: file asli milik pengguna (URI) -> JANGAN PERNAH dihapus.
enum VideoSourceType { copied, reference }

class VideoRecord {
  const VideoRecord({
    this.id,
    required this.projectId,
    required this.filePath,
    required this.fileName,
    this.sourceType = VideoSourceType.copied,
    this.contentUri,
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
    this.fileSize = 0,
    this.thumbnailPath,
    required this.createdAt,
  });

  final int? id;
  final int projectId;
  final String filePath;
  final String fileName;
  final VideoSourceType sourceType;
  final String? contentUri;
  final int durationMs;
  final int width;
  final int height;
  final int fileSize;
  final String? thumbnailPath;
  final DateTime createdAt;

  Duration get duration => Duration(milliseconds: durationMs);

  /// True bila aman dihapus oleh aplikasi saat project dihapus.
  bool get isManagedCopy => sourceType == VideoSourceType.copied;

  factory VideoRecord.fromMap(Map<String, Object?> m) => VideoRecord(
        id: m['id'] as int,
        projectId: m['project_id'] as int,
        filePath: m['file_path'] as String,
        fileName: m['file_name'] as String,
        sourceType: enumByName(VideoSourceType.values,
            m['source_type'] as String?, VideoSourceType.reference),
        contentUri: m['content_uri'] as String?,
        durationMs: m['duration_ms'] as int,
        width: m['width'] as int,
        height: m['height'] as int,
        fileSize: m['file_size'] as int,
        thumbnailPath: m['thumbnail_path'] as String?,
        createdAt: fromEpochMs(m['created_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'file_path': filePath,
        'file_name': fileName,
        'source_type': sourceType.name,
        'content_uri': contentUri,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
        'file_size': fileSize,
        'thumbnail_path': thumbnailPath,
        'created_at': toEpochMs(createdAt),
      };
}
