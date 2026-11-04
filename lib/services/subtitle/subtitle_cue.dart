import 'dart:math' as math;

import '../../database/models/transcript.dart';

/// Satu tampilan subtitle: 1-2 baris teks pada rentang waktu tertentu.
/// Waktu RELATIF terhadap awal clip.
class SubtitleCue {
  const SubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.lines,
  });

  final int startMs;
  final int endMs;
  final List<String> lines;

  String get text => lines.join('\n');

  SubtitleCue copyWith({int? startMs, int? endMs, List<String>? lines}) =>
      SubtitleCue(
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        lines: lines ?? this.lines,
      );
}

/// Memecah [text] menjadi baris-baris maksimal [maxChars] karakter, memecah
/// di batas kata. Kata yang lebih panjang dari [maxChars] dipotong paksa.
List<String> wrapText(String text, int maxChars) {
  if (maxChars < 1) throw ArgumentError('maxChars harus >= 1');

  final lines = <String>[];
  var current = '';

  for (var word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;

    while (word.length > maxChars) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(word.substring(0, maxChars));
      word = word.substring(maxChars);
    }

    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= maxChars) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

/// Mengubah segmen transcript menjadi cue untuk clip [clipStartMs]..[clipEndMs]
/// (waktu absolut pada video sumber).
///
/// - Hanya segmen yang beririsan dengan clip yang dipakai; waktunya dipotong
///   ke batas clip lalu digeser agar relatif terhadap awal clip.
/// - Teks dibungkus per [maxCharsPerLine]; bila lebih dari [maxLines] baris,
///   dipecah menjadi beberapa cue berurutan dengan waktu dibagi sebanding
///   jumlah karakter.
/// - Cue dipastikan tidak saling tumpang tindih.
List<SubtitleCue> buildCues({
  required List<TranscriptSegment> segments,
  required int clipStartMs,
  required int clipEndMs,
  int maxCharsPerLine = 28,
  int maxLines = 2,
}) {
  if (clipEndMs <= clipStartMs) return const [];
  final perPage = math.max(1, maxLines);

  final sorted = List<TranscriptSegment>.of(segments)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));

  final cues = <SubtitleCue>[];

  for (final s in sorted) {
    if (s.endMs <= clipStartMs || s.startMs >= clipEndMs) continue;

    final text = s.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;

    final start = math.max(s.startMs, clipStartMs) - clipStartMs;
    final end = math.min(s.endMs, clipEndMs) - clipStartMs;
    if (end <= start) continue;

    final lines = wrapText(text, maxCharsPerLine);
    final pages = <List<String>>[
      for (var i = 0; i < lines.length; i += perPage)
        lines.sublist(i, math.min(i + perPage, lines.length)),
    ];
    final totalChars =
        pages.fold<int>(0, (sum, page) => sum + page.join(' ').length);

    var cursor = start;
    for (var i = 0; i < pages.length; i++) {
      final isLast = i == pages.length - 1;
      final pageChars = pages[i].join(' ').length;
      final pageEnd = isLast
          ? end
          : cursor + ((end - start) * pageChars / totalChars).round();
      cues.add(SubtitleCue(startMs: cursor, endMs: pageEnd, lines: pages[i]));
      cursor = pageEnd;
    }
  }

  // Hilangkan tumpang tindih antar cue.
  for (var i = 0; i < cues.length - 1; i++) {
    if (cues[i].endMs > cues[i + 1].startMs) {
      cues[i] = cues[i].copyWith(endMs: cues[i + 1].startMs);
    }
  }

  // Cue yang terlalu singkat (< 100 ms) tidak terlihat.
  return cues.where((c) => c.endMs - c.startMs >= 100).toList();
}
