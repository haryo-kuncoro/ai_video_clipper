import 'package:ai_video_clipper/database/models/transcript.dart';
import 'package:ai_video_clipper/services/transcription/transcript_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const segs = [
    TranscriptSegment(startMs: 0, endMs: 1500, text: 'Halo semuanya'),
    TranscriptSegment(startMs: 3661001, endMs: 3665000, text: '  Kita mulai  '),
    TranscriptSegment(startMs: 4000000, endMs: 4001000, text: '   '),
  ];

  test('formatSrtTime', () {
    expect(formatSrtTime(0), '00:00:00,000');
    expect(formatSrtTime(3661001), '01:01:01,001');
    expect(formatSrtTime(-5), '00:00:00,000');
  });

  test('toSrt: nomor berurutan, segmen kosong dilewati', () {
    expect(
      toSrt(segs),
      '1\n00:00:00,000 --> 00:00:01,500\nHalo semuanya\n\n'
      '2\n01:01:01,001 --> 01:01:05,000\nKita mulai\n\n',
    );
  });

  test('toPlainText', () {
    expect(toPlainText(segs), 'Halo semuanya\nKita mulai');
  });

  test('searchSegments: tanpa membedakan huruf besar/kecil', () {
    expect(searchSegments(segs, 'HALO'), [0]);
    expect(searchSegments(segs, ''), [0, 1, 2]);
    expect(searchSegments(segs, 'zzz'), isEmpty);
  });

  test('splitHighlights', () {
    final parts = splitHighlights('Halo halo dunia', 'halo');
    expect(parts.map((p) => p.text), ['Halo', ' ', 'halo', ' dunia']);
    expect(parts.map((p) => p.highlighted), [true, false, true, false]);
    expect(splitHighlights('abc', '').single.highlighted, isFalse);
    expect(splitHighlights('abc', 'x').single.text, 'abc');
  });
}
