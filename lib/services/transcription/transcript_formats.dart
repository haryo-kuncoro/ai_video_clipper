import '../../database/models/transcript.dart';

/// Teks polos: satu segmen per baris.
String toPlainText(List<TranscriptSegment> segments) =>
    segments.map((s) => s.text.trim()).where((t) => t.isNotEmpty).join('\n');

/// Format "HH:MM:SS,mmm" untuk SRT.
String formatSrtTime(int ms) {
  final v = ms < 0 ? 0 : ms;
  final h = v ~/ 3600000;
  final m = (v % 3600000) ~/ 60000;
  final s = (v % 60000) ~/ 1000;
  final milli = v % 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)},${milli.toString().padLeft(3, '0')}';
}

/// Konten file .srt standar.
String toSrt(List<TranscriptSegment> segments) {
  final b = StringBuffer();
  var n = 0;
  for (final s in segments) {
    final text = s.text.trim();
    if (text.isEmpty) continue;
    n++;
    b
      ..writeln(n)
      ..writeln('${formatSrtTime(s.startMs)} --> ${formatSrtTime(s.endMs)}')
      ..writeln(text)
      ..writeln();
  }
  return b.toString();
}

/// Indeks segmen yang mengandung [query] (tanpa membedakan huruf besar/kecil).
/// Query kosong mengembalikan semua indeks.
List<int> searchSegments(List<TranscriptSegment> segments, String query) {
  final q = query.trim().toLowerCase();
  return [
    for (var i = 0; i < segments.length; i++)
      if (q.isEmpty || segments[i].text.toLowerCase().contains(q)) i,
  ];
}

class HighlightPart {
  const HighlightPart(this.text, this.highlighted);

  final String text;
  final bool highlighted;
}

/// Memecah [text] menjadi bagian biasa dan bagian yang cocok dengan [query].
List<HighlightPart> splitHighlights(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [HighlightPart(text, false)];
  final lower = text.toLowerCase();
  // Pencocokan memakai teks huruf kecil; bila panjangnya berubah (karakter
  // khusus), jangan menyorot agar indeks tidak meleset.
  if (lower.length != text.length) return [HighlightPart(text, false)];

  final parts = <HighlightPart>[];
  var pos = 0;
  while (true) {
    final i = lower.indexOf(q, pos);
    if (i < 0) break;
    if (i > pos) parts.add(HighlightPart(text.substring(pos, i), false));
    parts.add(HighlightPart(text.substring(i, i + q.length), true));
    pos = i + q.length;
  }
  if (pos < text.length) parts.add(HighlightPart(text.substring(pos), false));
  return parts;
}
