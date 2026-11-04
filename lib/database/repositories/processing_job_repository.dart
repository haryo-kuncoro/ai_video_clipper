import 'package:sqflite/sqflite.dart';

import '../models/model_utils.dart';
import '../models/processing_job.dart';

class ProcessingJobRepository {
  const ProcessingJobRepository(this._db);

  final Database _db;

  Future<ProcessingJob> enqueue({
    required int projectId,
    required JobType type,
    String? payload,
  }) async {
    final now = DateTime.now();
    final job = ProcessingJob(
      projectId: projectId,
      type: type,
      payload: payload,
      createdAt: now,
      updatedAt: now,
    );
    final id = await _db.insert('processing_jobs', job.toMap());
    return ProcessingJob(
      id: id,
      projectId: projectId,
      type: type,
      payload: payload,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<ProcessingJob?> getById(int id) async {
    final rows = await _db.query('processing_jobs',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProcessingJob.fromMap(rows.first);
  }

  Future<List<ProcessingJob>> getByProject(int projectId) async {
    final rows = await _db.query(
      'processing_jobs',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(ProcessingJob.fromMap).toList();
  }

  /// Job berikutnya dalam antrean (FIFO), untuk sequential queue.
  Future<ProcessingJob?> nextQueued() async {
    final rows = await _db.query(
      'processing_jobs',
      where: 'status = ?',
      whereArgs: [JobStatus.queued.name],
      orderBy: 'created_at ASC, id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : ProcessingJob.fromMap(rows.first);
  }

  Future<void> updateProgress(int id, double progress) => _patch(id, {
        'progress': progress.clamp(0.0, 1.0),
      });

  Future<void> updateStatus(
    int id,
    JobStatus status, {
    String? errorMessage,
  }) =>
      _patch(id, {
        'status': status.name,
        'error_message': errorMessage,
        if (status == JobStatus.completed) 'progress': 1.0,
      });

  /// Dipanggil saat aplikasi dibuka: job yang masih `running` berarti proses
  /// terputus (app ditutup/crash), kembalikan ke `queued` agar bisa dilanjutkan.
  Future<int> resetInterrupted() => _db.update(
        'processing_jobs',
        {
          'status': JobStatus.queued.name,
          'progress': 0.0,
          'updated_at': toEpochMs(DateTime.now()),
        },
        where: 'status = ?',
        whereArgs: [JobStatus.running.name],
      );

  /// Dipanggil saat aplikasi dibuka: job `running`/`queued` yang tertinggal
  /// berarti prosesnya terputus (app ditutup/crash). Tandai gagal dengan
  /// pesan yang jelas agar pengguna dapat menjalankan ulang. Mengembalikan
  /// jumlah job yang ditandai.
  Future<int> failInterrupted(
      [String message = 'Terhenti karena aplikasi ditutup. Jalankan ulang.']) =>
      _db.update(
        'processing_jobs',
        {
          'status': JobStatus.failed.name,
          'error_message': message,
          'updated_at': toEpochMs(DateTime.now()),
        },
        where: 'status IN (?, ?)',
        whereArgs: [JobStatus.running.name, JobStatus.queued.name],
      );

  Future<void> _patch(int id, Map<String, Object?> values) async {
    await _db.update(
      'processing_jobs',
      {...values, 'updated_at': toEpochMs(DateTime.now())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
