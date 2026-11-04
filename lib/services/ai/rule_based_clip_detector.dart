import 'dart:math' as math;

import '../../database/models/transcript.dart';
import 'clip_detector.dart';
import 'clip_keywords.dart';

final _tokenSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _hasDigit = RegExp(r'\d');
final _endsClean = RegExp(r'[.?!]["”)]?\s*$');

/// Penilaian satu segmen: skor 0-1 dan alasan yang mudah dibaca.
class UnitScore {
  const UnitScore(this.score, this.reasons);

  final double score;
  final List<String> reasons;
}

List<String> tokenize(String text) => text
    .toLowerCase()
    .split(_tokenSplit)
    .where((t) => t.isNotEmpty)
    .toList();

/// Menilai satu segmen transcript dengan aturan sederhana dan transparan.
UnitScore scoreUnit(TranscriptSegment s) {
  final tokens = tokenize(s.text);
  final seconds = math.max((s.endMs - s.startMs) / 1000.0, 0.1);
  final reasons = <String>[];
  var score = 0.2;

  if (tokens.length < 4) {
    return UnitScore(0.05, const []);
  }

  final isQuestion = s.text.contains('?') ||
      ClipKeywords.questionWords.contains(tokens.first);
  if (isQuestion) {
    score += 0.25;
    reasons.add('pertanyaan');
  }

  final attention =
      tokens.where(ClipKeywords.attention.contains).length.clamp(0, 2);
  if (attention > 0) {
    score += 0.15 * attention;
    reasons.add('kata kunci menarik');
  }

  final emotion = tokens.where(ClipKeywords.emotion.contains).length.clamp(0, 2);
  if (emotion > 0) {
    score += 0.10 * emotion;
    reasons.add('bahasa beremosi');
  }

  if (_hasDigit.hasMatch(s.text)) {
    score += 0.10;
    reasons.add('angka/data');
  }
  if (s.text.contains('!')) score += 0.10;

  final wps = tokens.length / seconds;
  if (wps >= 1.5 && wps <= 4.5) {
    score += 0.15;
  } else if (wps < 0.8) {
    score -= 0.20;
  }

  return UnitScore(score.clamp(0.0, 1.0).toDouble(), reasons);
}

/// Pendeteksi clip offline berbasis aturan (tanpa model, tanpa internet).
///
/// 1. Tiap segmen dinilai ([scoreUnit]).
/// 2. Untuk setiap segmen awal, dicari rentang segmen berurutan (tanpa jeda
///    hening panjang, durasi min-max) dengan skor terbaik.
/// 3. Kandidat dipilih dari skor tertinggi tanpa saling tumpang tindih.
/// Batas clip selalu jatuh pada batas segmen sehingga tidak memotong kalimat.
class RuleBasedClipDetector implements ClipDetector {
  const RuleBasedClipDetector();

  @override
  String get name => 'rule-based';

  @override
  Future<List<DetectedClip>> detect({
    required List<TranscriptSegment> segments,
    required int videoDurationMs,
    DetectionOptions options = const DetectionOptions(),
  }) async {
    final segs = segments.where((s) => s.endMs > s.startMs).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (segs.isEmpty) return const [];

    final units = [for (final s in segs) scoreUnit(s)];
    final n = segs.length;

    // Jumlah (skor x durasi) kumulatif untuk rata-rata berbobot durasi.
    final weighted = List<double>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      final d = (segs[i].endMs - segs[i].startMs).toDouble();
      weighted[i + 1] = weighted[i] + units[i].score * d;
    }

    final windows = <_Window>[];
    for (var i = 0; i < n; i++) {
      _Window? best;
      for (var j = i; j < n; j++) {
        if (j > i && segs[j].startMs - segs[j - 1].endMs > options.maxGapMs) {
          break;
        }
        final span = segs[j].endMs - segs[i].startMs;
        if (span > options.maxMs) break;

        final shortVideo = videoDurationMs > 0 && videoDurationMs < options.minMs;
        final isLast = j == n - 1;
        // Video lebih pendek dari batas minimum: terima rentang apa pun.
        if (span < options.minMs && !(shortVideo && isLast)) continue;

        final cover = (segs[j].endMs - segs[i].startMs).toDouble();
        final mean = (weighted[j + 1] - weighted[i]) / cover;
        final fit = (1 -
                (span - options.targetMs).abs() / options.targetMs)
            .clamp(0.0, 1.0)
            .toDouble();
        final clean = _endsClean.hasMatch(segs[j].text);
        final score = (0.55 * mean +
                0.25 * units[i].score +
                0.12 * fit +
                (clean ? 0.08 : 0))
            .clamp(0.0, 1.0)
            .toDouble();

        if (best == null || score > best.score) {
          best = _Window(i, j, score, clean);
        }
      }
      if (best != null) windows.add(best);
    }

    windows.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.first.compareTo(b.first);
    });

    final chosen = <_Window>[];
    for (final w in windows) {
      if (chosen.length >= options.maxClips) break;
      if (w.score < options.minScore) break;
      final ws = segs[w.first].startMs;
      final we = segs[w.last].endMs;
      final overlaps = chosen.any((c) =>
          ws < segs[c.last].endMs && we > segs[c.first].startMs);
      if (!overlaps) chosen.add(w);
    }

    final clips = [
      for (final w in chosen) _toClip(w, segs, units, videoDurationMs),
    ];

    // Bantalan waktu bisa membuat dua clip bertetangga saling menyentuh/
    // tumpang tindih; pisahkan di titik tengah antara batas segmennya.
    final order = List<int>.generate(chosen.length, (i) => i)
      ..sort((a, b) => clips[a].startMs.compareTo(clips[b].startMs));
    final starts = [for (final c in clips) c.startMs];
    final ends = [for (final c in clips) c.endMs];
    for (var k = 1; k < order.length; k++) {
      final prev = order[k - 1];
      final cur = order[k];
      if (ends[prev] > starts[cur]) {
        final b = ((segs[chosen[prev].last].endMs + segs[chosen[cur].first].startMs) / 2)
            .round();
        ends[prev] = b;
        starts[cur] = b;
      }
    }

    return [
      for (var i = 0; i < clips.length; i++)
        DetectedClip(
          startMs: starts[i],
          endMs: ends[i],
          score: clips[i].score,
          title: clips[i].title,
          hook: clips[i].hook,
          reason: clips[i].reason,
        ),
    ];
  }

  DetectedClip _toClip(
    _Window w,
    List<TranscriptSegment> segs,
    List<UnitScore> units,
    int videoDurationMs,
  ) {
    final first = segs[w.first];
    final last = segs[w.last];

    // Sedikit bantalan agar suara tidak terpotong; tetap dalam batas video.
    var start = math.max(0, first.startMs - 200);
    var end = last.endMs + 300;
    if (videoDurationMs > 0) end = math.min(end, videoDurationMs);
    if (start >= end) start = first.startMs;

    final reasons = <String>[
      ...units[w.first].reasons.map((r) => 'Pembuka: $r'),
      if (w.clean) 'berakhir di kalimat utuh',
      'durasi ${((end - start) / 1000).round()} dtk',
    ];

    return DetectedClip(
      startMs: start,
      endMs: end,
      score: w.score,
      title: makeTitle(first.text),
      hook: _truncate(first.text.trim(), 120),
      reason: reasons.join('; '),
    );
  }
}

class _Window {
  const _Window(this.first, this.last, this.score, this.clean);

  final int first;
  final int last;
  final double score;
  final bool clean;
}

/// Judul singkat (maks. 8 kata) dari kalimat pembuka; kata pembuka kosong
/// ("jadi", "nah", ...) dibuang.
String makeTitle(String text) {
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  var i = 0;
  while (i < words.length - 1) {
    final bare = words[i].toLowerCase().replaceAll(_tokenSplit, '');
    if (ClipKeywords.leadingFillers.contains(bare)) {
      i++;
    } else {
      break;
    }
  }
  var title = words.skip(i).take(8).join(' ');
  title = title.replaceAll(RegExp(r'[\s,;:\-]+$'), '');
  if (title.isEmpty) return 'Clip';
  return title[0].toUpperCase() + title.substring(1);
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';
