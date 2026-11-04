import '../../database/models/transcript.dart';

/// Pengaturan deteksi clip (durasi dalam milidetik).
class DetectionOptions {
  const DetectionOptions({
    this.minMs = 30000,
    this.targetMs = 45000,
    this.maxMs = 60000,
    this.maxClips = 10,
    this.maxGapMs = 4000,
    this.minScore = 0.30,
  });

  final int minMs;
  final int targetMs;
  final int maxMs;
  final int maxClips;

  /// Jeda hening terpanjang antar-segmen dalam satu clip.
  final int maxGapMs;

  /// Skor minimum (0-1) agar sebuah kandidat dipertahankan.
  final double minScore;

  static const short = DetectionOptions(minMs: 15000, targetMs: 25000, maxMs: 40000);
  static const standard = DetectionOptions();
  static const long = DetectionOptions(minMs: 45000, targetMs: 70000, maxMs: 90000);

  DetectionOptions copyWith({int? maxClips}) => DetectionOptions(
        minMs: minMs,
        targetMs: targetMs,
        maxMs: maxMs,
        maxClips: maxClips ?? this.maxClips,
        maxGapMs: maxGapMs,
        minScore: minScore,
      );
}

/// Satu kandidat clip hasil deteksi.
class DetectedClip {
  const DetectedClip({
    required this.startMs,
    required this.endMs,
    required this.score,
    required this.title,
    required this.hook,
    required this.reason,
  });

  final int startMs;
  final int endMs;

  /// 0.0 - 1.0
  final double score;
  final String title;
  final String hook;
  final String reason;

  int get durationMs => endMs - startMs;
}

/// Kontrak pendeteksi clip. Implementasi bawaan: [RuleBasedClipDetector]
/// (offline, tanpa model). Pendeteksi berbasis model lokal dapat ditambahkan
/// kemudian dengan kontrak yang sama tanpa mengubah service/UI.
abstract class ClipDetector {
  String get name;

  Future<List<DetectedClip>> detect({
    required List<TranscriptSegment> segments,
    required int videoDurationMs,
    DetectionOptions options = const DetectionOptions(),
  });
}
