import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Skema awal: tabel inti project, video, transcript, clip, dan antrian job.
/// SQLite hanya menyimpan METADATA dan PATH file, tidak pernah BLOB video.
class MigrationV1 extends Migration {
  const MigrationV1();

  @override
  int get version => 1;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        source_video_id INTEGER,
        status TEXT NOT NULL DEFAULT 'created',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE videos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL
          REFERENCES projects(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'copied',
        content_uri TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        width INTEGER NOT NULL DEFAULT 0,
        height INTEGER NOT NULL DEFAULT 0,
        file_size INTEGER NOT NULL DEFAULT 0,
        thumbnail_path TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_videos_project ON videos(project_id)');

    await db.execute('''
      CREATE TABLE transcripts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL
          REFERENCES projects(id) ON DELETE CASCADE,
        video_id INTEGER NOT NULL
          REFERENCES videos(id) ON DELETE CASCADE,
        language TEXT,
        engine TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_transcripts_project ON transcripts(project_id)');

    await db.execute('''
      CREATE TABLE transcript_segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transcript_id INTEGER NOT NULL
          REFERENCES transcripts(id) ON DELETE CASCADE,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        text TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_segments_transcript_start
      ON transcript_segments(transcript_id, start_ms)
    ''');

    await db.execute('''
      CREATE TABLE clip_candidates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL
          REFERENCES projects(id) ON DELETE CASCADE,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        title TEXT NOT NULL,
        hook TEXT,
        score REAL NOT NULL DEFAULT 0,
        reason TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_candidates_project ON clip_candidates(project_id)');

    await db.execute('''
      CREATE TABLE clips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL
          REFERENCES projects(id) ON DELETE CASCADE,
        candidate_id INTEGER
          REFERENCES clip_candidates(id) ON DELETE SET NULL,
        file_path TEXT,
        thumbnail_path TEXT,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        width INTEGER NOT NULL DEFAULT 0,
        height INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL,
        score REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_clips_project ON clips(project_id)');

    await db.execute('''
      CREATE TABLE processing_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL
          REFERENCES projects(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'queued',
        progress REAL NOT NULL DEFAULT 0,
        payload TEXT,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_jobs_status_created
      ON processing_jobs(status, created_at)
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY NOT NULL,
        setting_value TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
  }
}
