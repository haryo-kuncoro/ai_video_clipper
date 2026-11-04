import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../models/model_utils.dart';
import '../models/project.dart';
import '../models/project_summary.dart';

class ProjectRepository {
  const ProjectRepository(this._db);

  final Database _db;

  Future<Project> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AppException('Nama project tidak boleh kosong.');
    }
    final now = DateTime.now();
    final id = await _db.insert(
      'projects',
      Project(name: trimmed, createdAt: now, updatedAt: now).toMap(),
    );
    return Project(id: id, name: trimmed, createdAt: now, updatedAt: now);
  }

  Future<List<Project>> getAll() async {
    final rows = await _db.query('projects', orderBy: 'updated_at DESC, id DESC');
    return rows.map(Project.fromMap).toList();
  }

  static const _summarySelect = '''
    SELECT p.*,
      (SELECT COUNT(*) FROM clips c WHERE c.project_id = p.id) AS clip_count,
      (SELECT v.duration_ms FROM videos v
        WHERE v.project_id = p.id ORDER BY v.id ASC LIMIT 1) AS duration_ms
    FROM projects p
  ''';

  /// Daftar project untuk Home, terbaru di atas.
  Future<List<ProjectSummary>> getSummaries() async {
    final rows = await _db
        .rawQuery('$_summarySelect ORDER BY p.updated_at DESC, p.id DESC');
    return rows.map(ProjectSummary.fromMap).toList();
  }

  Future<ProjectSummary?> getSummaryById(int id) async {
    final rows = await _db.rawQuery('$_summarySelect WHERE p.id = ?', [id]);
    return rows.isEmpty ? null : ProjectSummary.fromMap(rows.first);
  }

  Future<Project?> getById(int id) async {
    final rows =
        await _db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Project.fromMap(rows.first);
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AppException('Nama project tidak boleh kosong.');
    }
    await _update(id, {'name': trimmed});
  }

  Future<void> updateStatus(int id, ProjectStatus status) =>
      _update(id, {'status': status.name});

  /// Status sementara (sedang memproses) yang tertinggal setelah app ditutup
  /// dikembalikan ke status stabil sebelumnya. Mengembalikan jumlah project.
  Future<int> resetTransientStatuses() async {
    const map = {
      'transcribing': 'videoAdded',
      'analyzing': 'transcribed',
      'rendering': 'analyzed',
    };
    var n = 0;
    for (final e in map.entries) {
      n += await _db.update(
        'projects',
        {'status': e.value, 'updated_at': toEpochMs(DateTime.now())},
        where: 'status = ?',
        whereArgs: [e.key],
      );
    }
    return n;
  }

  Future<void> setSourceVideo(int id, int videoId) =>
      _update(id, {'source_video_id': videoId});

  /// Menghapus baris project. Baris turunan (video, transcript, clip, job)
  /// ikut terhapus lewat ON DELETE CASCADE. Penghapusan FILE di disk
  /// ditangani di STEP 3 (jangan hapus file asli milik pengguna).
  Future<void> delete(int id) =>
      _db.delete('projects', where: 'id = ?', whereArgs: [id]);

  Future<void> _update(int id, Map<String, Object?> values) async {
    await _db.update(
      'projects',
      {...values, 'updated_at': toEpochMs(DateTime.now())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
