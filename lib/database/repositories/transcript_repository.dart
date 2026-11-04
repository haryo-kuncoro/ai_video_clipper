import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../models/transcript.dart';

class TranscriptRepository {
  const TranscriptRepository(this._db);

  final Database _db;

  /// Menyimpan transcript beserta seluruh segmennya dalam SATU transaksi
  /// (semua tersimpan atau tidak sama sekali). Mengembalikan id transcript.
  Future<int> save(
    Transcript transcript,
    List<TranscriptSegment> segments,
  ) {
    return _db.transaction((txn) async {
      final id = await txn.insert('transcripts', transcript.toMap());
      final batch = txn.batch();
      for (final s in segments) {
        batch.insert('transcript_segments', {
          'transcript_id': id,
          'start_ms': s.startMs,
          'end_ms': s.endMs,
          'text': s.text,
        });
      }
      await batch.commit(noResult: true);
      return id;
    });
  }

  /// Mengganti transcript lama project dengan yang baru dalam SATU transaksi:
  /// bila gagal di tengah jalan, transcript lama tetap utuh.
  Future<int> replaceForProject(
    Transcript transcript,
    List<TranscriptSegment> segments,
  ) {
    return _db.transaction((txn) async {
      await txn.delete(
        'transcripts',
        where: 'project_id = ?',
        whereArgs: [transcript.projectId],
      );
      final id = await txn.insert('transcripts', transcript.toMap());
      final batch = txn.batch();
      for (final s in segments) {
        batch.insert('transcript_segments', {
          'transcript_id': id,
          'start_ms': s.startMs,
          'end_ms': s.endMs,
          'text': s.text,
        });
      }
      await batch.commit(noResult: true);
      return id;
    });
  }

  /// Menyimpan hasil terjemahan SECARA ATOMIK: `text` diganti terjemahan,
  /// teks asli dipindah ke `source_text` (hanya bila belum terisi).
  Future<void> applyTranslation(
    int transcriptId,
    Map<int, String> translated,
    String lang,
  ) {
    return _db.transaction((txn) async {
      final batch = txn.batch();
      translated.forEach((segmentId, text) {
        batch.rawUpdate(
          'UPDATE transcript_segments '
          'SET source_text = COALESCE(source_text, text), text = ? '
          'WHERE id = ? AND transcript_id = ?',
          [text, segmentId, transcriptId],
        );
      });
      batch.update(
        'transcripts',
        {'translated_lang': lang},
        where: 'id = ?',
        whereArgs: [transcriptId],
      );
      await batch.commit(noResult: true);
    });
  }

  Future<Transcript?> getByProject(int projectId) async {
    final rows = await _db.query(
      'transcripts',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Transcript.fromMap(rows.first);
  }

  Future<List<TranscriptSegment>> getSegments(int transcriptId) async {
    final rows = await _db.query(
      'transcript_segments',
      where: 'transcript_id = ?',
      whereArgs: [transcriptId],
      orderBy: 'start_ms ASC',
    );
    return rows.map(TranscriptSegment.fromMap).toList();
  }

  /// Segmen yang beririsan dengan rentang [startMs, endMs] (untuk subtitle).
  Future<List<TranscriptSegment>> getSegmentsInRange(
    int transcriptId,
    int startMs,
    int endMs,
  ) async {
    final rows = await _db.query(
      'transcript_segments',
      where: 'transcript_id = ? AND end_ms > ? AND start_ms < ?',
      whereArgs: [transcriptId, startMs, endMs],
      orderBy: 'start_ms ASC',
    );
    return rows.map(TranscriptSegment.fromMap).toList();
  }

  Future<void> updateSegmentText(int segmentId, String text) => _db.update(
        'transcript_segments',
        {'text': text},
        where: 'id = ?',
        whereArgs: [segmentId],
      );

  Future<void> deleteSegment(int segmentId) => _db.delete(
        'transcript_segments',
        where: 'id = ?',
        whereArgs: [segmentId],
      );

  /// Menggabungkan segmen dengan segmen berikutnya (teks disambung, waktu
  /// akhir mengikuti yang terakhir). Mengembalikan false bila tidak ada
  /// segmen berikutnya. Atomik.
  Future<bool> mergeWithNext(int segmentId) {
    return _db.transaction((txn) async {
      final cur = await txn.query('transcript_segments',
          where: 'id = ?', whereArgs: [segmentId], limit: 1);
      if (cur.isEmpty) return false;
      final c = TranscriptSegment.fromMap(cur.first);

      final nxt = await txn.query(
        'transcript_segments',
        where: 'transcript_id = ? AND id <> ? AND '
            '(start_ms > ? OR (start_ms = ? AND id > ?))',
        whereArgs: [c.transcriptId, c.id, c.startMs, c.startMs, c.id],
        orderBy: 'start_ms ASC, id ASC',
        limit: 1,
      );
      if (nxt.isEmpty) return false;
      final n = TranscriptSegment.fromMap(nxt.first);

      await txn.update(
        'transcript_segments',
        {
          'text': '${c.text} ${n.text}',
          'end_ms': math.max(c.endMs, n.endMs),
        },
        where: 'id = ?',
        whereArgs: [c.id],
      );
      await txn.delete('transcript_segments',
          where: 'id = ?', whereArgs: [n.id]);
      return true;
    });
  }

  Future<void> deleteByProject(int projectId) => _db.delete(
        'transcripts',
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
}
