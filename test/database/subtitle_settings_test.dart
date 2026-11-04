import 'dart:io';

import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/repositories/project_repository.dart';
import 'package:ai_video_clipper/database/repositories/subtitle_settings_repository.dart';
import 'package:ai_video_clipper/services/subtitle/subtitle_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late SubtitleSettingsRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('avc_subdb_');
    db = await AppDatabase.openAt(
      p.join(tmp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
    repo = SubtitleSettingsRepository(db.db);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<int> rowCount() async {
    final r = await db.db.rawQuery('SELECT COUNT(*) AS c FROM subtitle_settings');
    return r.first['c'] as int;
  }

  test('migrasi v3 menambah kolom subtitle baru', () async {
    final cols = await db.db.rawQuery('PRAGMA table_info(subtitle_settings)');
    final names = cols.map((c) => c['name']).toList();
    expect(names, containsAll(['bold', 'uppercase', 'text_color', 'outline_color']));
  });

  test('tanpa data: preset Classic', () async {
    final project = await ProjectRepository(db.db).create('P');
    final s = await repo.getForProject(project.id!);
    expect(s.preset, SubtitlePreset.classic);
    expect(await rowCount(), 0);
  });

  test('simpan dan baca kembali gaya project', () async {
    final project = await ProjectRepository(db.db).create('P');
    final style = SubtitlePresets.style(SubtitlePreset.social)
        .copyWith(background: true, maxCharsPerLine: 20);

    await repo.saveForProject(project.id!, style);
    final loaded = await repo.getForProject(project.id!);

    expect(loaded.preset, SubtitlePreset.social);
    expect(loaded.background, isTrue);
    expect(loaded.maxCharsPerLine, 20);
    expect(loaded.uppercase, isTrue);
    expect(loaded.textColor, 0xFFFFE600);
  });

  test('menyimpan ulang memperbarui baris yang sama (tidak menggandakan)',
      () async {
    final project = await ProjectRepository(db.db).create('P');
    await repo.saveForProject(project.id!, SubtitlePresets.style(SubtitlePreset.bold));
    await repo.saveForProject(project.id!, SubtitlePresets.style(SubtitlePreset.minimal));

    expect(await rowCount(), 1);
    expect((await repo.getForProject(project.id!)).preset, SubtitlePreset.minimal);
  });

  test('project tanpa pengaturan memakai default global', () async {
    final a = await ProjectRepository(db.db).create('A');
    final b = await ProjectRepository(db.db).create('B');

    await repo.saveDefault(SubtitlePresets.style(SubtitlePreset.bold));
    await repo.saveForProject(a.id!, SubtitlePresets.style(SubtitlePreset.social));

    expect((await repo.getForProject(a.id!)).preset, SubtitlePreset.social);
    expect((await repo.getForProject(b.id!)).preset, SubtitlePreset.bold);

    // Simpan default dua kali tetap satu baris global.
    await repo.saveDefault(SubtitlePresets.style(SubtitlePreset.minimal));
    expect(await rowCount(), 2);
  });

  test('menghapus project menghapus pengaturan subtitle-nya', () async {
    final project = await ProjectRepository(db.db).create('P');
    await repo.saveForProject(project.id!, SubtitlePresets.style(SubtitlePreset.bold));
    await ProjectRepository(db.db).delete(project.id!);
    expect(await rowCount(), 0);
  });
}
