import 'package:sqflite/sqflite.dart';

import '../models/video_record.dart';

class VideoRepository {
  const VideoRepository(this._db);

  final Database _db;

  Future<VideoRecord> insert(VideoRecord video) async {
    final id = await _db.insert('videos', video.toMap());
    return VideoRecord(
      id: id,
      projectId: video.projectId,
      filePath: video.filePath,
      fileName: video.fileName,
      sourceType: video.sourceType,
      contentUri: video.contentUri,
      durationMs: video.durationMs,
      width: video.width,
      height: video.height,
      fileSize: video.fileSize,
      thumbnailPath: video.thumbnailPath,
      createdAt: video.createdAt,
    );
  }

  Future<VideoRecord?> getById(int id) async {
    final rows =
        await _db.query('videos', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : VideoRecord.fromMap(rows.first);
  }

  Future<List<VideoRecord>> getByProject(int projectId) async {
    final rows = await _db.query('videos',
        where: 'project_id = ?', whereArgs: [projectId], orderBy: 'id ASC');
    return rows.map(VideoRecord.fromMap).toList();
  }

  Future<void> delete(int id) =>
      _db.delete('videos', where: 'id = ?', whereArgs: [id]);

  Future<void> updateThumbnail(int id, String thumbnailPath) => _db.update(
        'videos',
        {'thumbnail_path': thumbnailPath},
        where: 'id = ?',
        whereArgs: [id],
      );
}
