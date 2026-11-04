import 'model_utils.dart';

class Transcript {
  const Transcript({
    this.id,
    required this.projectId,
    required this.videoId,
    this.language,
    this.engine,
    this.translatedLang,
    required this.createdAt,
  });

  final int? id;
  final int projectId;
  final int videoId;
  final String? language;
  final String? engine;

  /// Kode bahasa hasil terjemahan (null = belum diterjemahkan).
  final String? translatedLang;
  final DateTime createdAt;

  factory Transcript.fromMap(Map<String, Object?> m) => Transcript(
        id: m['id'] as int,
        projectId: m['project_id'] as int,
        videoId: m['video_id'] as int,
        language: m['language'] as String?,
        engine: m['engine'] as String?,
        translatedLang: m['translated_lang'] as String?,
        createdAt: fromEpochMs(m['created_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'video_id': videoId,
        'language': language,
        'engine': engine,
        'created_at': toEpochMs(createdAt),
      };
}

class TranscriptSegment {
  const TranscriptSegment({
    this.id,
    this.transcriptId,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.sourceText,
  });

  final int? id;
  final int? transcriptId;
  final int startMs;
  final int endMs;
  final String text;

  /// Teks asli sebelum diterjemahkan (null bila tidak diterjemahkan).
  final String? sourceText;

  Duration get start => Duration(milliseconds: startMs);
  Duration get end => Duration(milliseconds: endMs);

  factory TranscriptSegment.fromMap(Map<String, Object?> m) =>
      TranscriptSegment(
        id: m['id'] as int,
        transcriptId: m['transcript_id'] as int,
        startMs: m['start_ms'] as int,
        endMs: m['end_ms'] as int,
        text: m['text'] as String,
        sourceText: m['source_text'] as String?,
      );
}
