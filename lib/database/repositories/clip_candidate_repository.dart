import 'package:sqflite/sqflite.dart';

import '../models/clip_candidate.dart';

class ClipCandidateRepository {
  const ClipCandidateRepository(this._db);

  final Database _db;

  Future<void> insertAll(List<ClipCandidate> candidates) async {
    final batch = _db.batch();
    for (final c in candidates) {
      batch.insert('clip_candidates', c.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Mengganti seluruh kandidat project dalam SATU transaksi (kandidat lama
  /// tetap utuh bila penyimpanan gagal).
  Future<void> replaceForProject(
    int projectId,
    List<ClipCandidate> candidates,
  ) {
    return _db.transaction((txn) async {
      await txn.delete('clip_candidates',
          where: 'project_id = ?', whereArgs: [projectId]);
      final batch = txn.batch();
      for (final c in candidates) {
        batch.insert('clip_candidates', c.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<ClipCandidate>> getByProject(int projectId) async {
    final rows = await _db.query(
      'clip_candidates',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'score DESC, start_ms ASC',
    );
    return rows.map(ClipCandidate.fromMap).toList();
  }

  Future<ClipCandidate?> getById(int id) async {
    final rows = await _db.query('clip_candidates',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ClipCandidate.fromMap(rows.first);
  }

  /// Mengubah status semua kandidat project (kecuali yang sudah `generated`,
  /// karena clip-nya sudah dirender).
  Future<void> setStatusForProject(int projectId, CandidateStatus status) =>
      _db.update(
        'clip_candidates',
        {'status': status.name},
        where: 'project_id = ? AND status <> ?',
        whereArgs: [projectId, CandidateStatus.generated.name],
      );

  Future<void> updateStatus(int id, CandidateStatus status) =>
      _patch(id, {'status': status.name});

  /// Dipakai pada review: ubah start/end/judul oleh pengguna.
  Future<void> updateDetails(
    int id, {
    int? startMs,
    int? endMs,
    String? title,
  }) {
    final values = <String, Object?>{
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      if (title != null) 'title': title,
    };
    if (values.isEmpty) return Future.value();
    return _patch(id, values);
  }

  Future<void> deleteByProject(int projectId) => _db.delete(
        'clip_candidates',
        where: 'project_id = ?',
        whereArgs: [projectId],
      );

  Future<void> _patch(int id, Map<String, Object?> values) async {
    await _db.update('clip_candidates', values,
        where: 'id = ?', whereArgs: [id]);
  }
}
