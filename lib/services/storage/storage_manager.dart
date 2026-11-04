import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../features/video/media_probe.dart';
import '../settings/app_settings.dart';
import 'app_paths.dart';

/// Rincian pemakaian penyimpanan aplikasi (byte).
class StorageUsage {
  const StorageUsage({
    this.videos = 0,
    this.clips = 0,
    this.thumbnails = 0,
    this.temp = 0,
    this.models = 0,
    this.freeBytes,
    this.lowSpace = false,
  });

  final int videos;
  final int clips;
  final int thumbnails;
  final int temp;
  final int models;

  /// Ruang kosong perangkat; null bila tidak dapat dibaca.
  final int? freeBytes;

  /// True bila ruang kosong di bawah batas `min_free_storage_mb`.
  final bool lowSpace;

  int get total => videos + clips + thumbnails + temp + models;
}

/// File milik aplikasi yang tidak lagi dirujuk database.
class OrphanReport {
  const OrphanReport(this.paths, this.bytes);

  static const none = OrphanReport([], 0);

  final List<String> paths;
  final int bytes;

  int get count => paths.length;
}

/// Mengelola penyimpanan LOKAL aplikasi. Aturan keselamatan:
///  - hanya menyentuh folder app (`AppPaths.root`), tidak pernah file video
///    asli milik pengguna atau berkas hasil ekspor di galeri/Downloads;
///  - folder `videos/` (salinan sumber) hanya dihitung, tidak pernah dihapus;
///  - symlink tidak diikuti; path di luar root dilewati;
///  - pembersihan ditolak saat pipeline/render sedang berjalan.
class StorageManager {
  StorageManager({
    required this.paths,
    required Database db,
    required MediaProbe probe,
    AppSettings Function()? settings,
    bool Function()? isBusy,
  })  : _db = db,
        _probe = probe,
        _settings = settings ?? (() => AppSettings.defaults),
        _isBusy = isBusy ?? (() => false);

  final AppPaths paths;
  final Database _db;
  final MediaProbe _probe;
  final AppSettings Function() _settings;
  final bool Function() _isBusy;

  static final _clipFile = RegExp(r'^clip_\d+(_edit)?\.mp4$');

  Directory get modelsDir => Directory(p.join(paths.root.path, 'models'));

  Future<StorageUsage> usage() async {
    final projectTemp = await _projectTempSize();
    final results = await Future.wait([
      _dirSize(paths.videos),
      _dirSize(paths.projects).then((v) async => v + await _dirSize(paths.clips)),
      _dirSize(paths.thumbnails),
      _dirSize(paths.temp),
      _dirSize(modelsDir),
    ]);
    int? free;
    try {
      free = await _probe.freeSpaceBytes(paths.root.path);
      if (free < 0) free = null;
    } catch (e) {
      AppLogger.d('Ruang kosong tidak terbaca: $e');
    }
    return StorageUsage(
      videos: results[0],
      clips: results[1] - projectTemp, // temp project ada di dalam projects/
      thumbnails: results[2],
      temp: results[3] + projectTemp,
      models: results[4],
      freeBytes: free,
      lowSpace: free != null && free < _settings().minFreeStorageBytes,
    );
  }

  /// Total byte `projects/<id>/temp`.
  Future<int> _projectTempSize() async {
    var sum = 0;
    for (final d in await _projectDirs()) {
      sum += await _dirSize(Directory(p.join(d.path, 'temp')));
    }
    return sum;
  }

  /// Menghapus isi folder sementara. Mengembalikan jumlah byte dibebaskan.
  Future<int> cleanTemp() async {
    _ensureIdle();
    var freed = 0;

    Future<void> clear(Directory dir) async {
      if (!await dir.exists()) return;
      await for (final e in dir.list(followLinks: false)) {
        if (!_inRoot(e.path)) continue;
        final size = e is File ? await _fileSize(e) : await _dirSize(e as Directory);
        try {
          await e.delete(recursive: true);
          freed += size;
        } on FileSystemException {
          // Dilewati; dicoba lagi lain kali.
        }
      }
    }

    await clear(paths.temp);
    for (final d in await _projectDirs()) {
      await clear(Directory(p.join(d.path, 'temp')));
    }
    return freed;
  }

  /// Mencari file clip/thumbnail buatan aplikasi yang tidak dirujuk database.
  Future<OrphanReport> findOrphans() async {
    final clipRows = await _db.rawQuery('SELECT file_path, thumbnail_path FROM clips');
    final videoRows = await _db.rawQuery('SELECT thumbnail_path FROM videos');
    final projectRows = await _db.rawQuery('SELECT id FROM projects');

    final keepFiles = <String>{};
    final keepThumbs = <String>{};
    for (final r in clipRows) {
      final f = r['file_path'];
      final t = r['thumbnail_path'];
      if (f is String && f.isNotEmpty) keepFiles.add(p.normalize(f));
      if (t is String && t.isNotEmpty) keepThumbs.add(p.normalize(t));
    }
    for (final r in videoRows) {
      final t = r['thumbnail_path'];
      if (t is String && t.isNotEmpty) keepThumbs.add(p.normalize(t));
    }
    final projectIds = {
      for (final r in projectRows)
        if (r['id'] is int) '${r['id']}',
    };

    final orphans = <String>[];
    var bytes = 0;

    Future<void> add(File f) async {
      if (!_inRoot(f.path)) return;
      orphans.add(f.path);
      bytes += await _fileSize(f);
    }

    for (final d in await _projectDirs()) {
      final name = p.basename(d.path);
      if (!RegExp(r'^\d+$').hasMatch(name)) continue;
      final clipsDir = Directory(p.join(d.path, 'clips'));
      if (!await clipsDir.exists()) continue;
      final projectGone = !projectIds.contains(name);
      await for (final f in clipsDir.list(followLinks: false)) {
        if (f is! File) continue;
        if (!_clipFile.hasMatch(p.basename(f.path))) continue;
        if (projectGone || !keepFiles.contains(p.normalize(f.path))) await add(f);
      }
    }

    if (await paths.thumbnails.exists()) {
      await for (final f in paths.thumbnails.list(followLinks: false)) {
        if (f is! File) continue;
        if (!keepThumbs.contains(p.normalize(f.path))) await add(f);
      }
    }
    return OrphanReport(orphans, bytes);
  }

  /// Menghapus file yatim hasil [findOrphans]. Mengembalikan byte dibebaskan.
  Future<int> deleteOrphans() async {
    _ensureIdle();
    final report = await findOrphans();
    var freed = 0;
    for (final path in report.paths) {
      final f = File(path);
      final size = await _fileSize(f);
      try {
        await f.delete();
        freed += size;
      } on FileSystemException {
        // Dilewati.
      }
    }
    return freed;
  }

  // ---- util ---------------------------------------------------------

  void _ensureIdle() {
    if (_isBusy()) {
      throw const AppException(
        'Pemrosesan sedang berjalan. Tunggu selesai sebelum membersihkan penyimpanan.',
        code: 'storage_busy',
      );
    }
  }

  bool _inRoot(String path) => p.isWithin(paths.root.path, path);

  Future<List<Directory>> _projectDirs() async {
    if (!await paths.projects.exists()) return const [];
    final out = <Directory>[];
    await for (final e in paths.projects.list(followLinks: false)) {
      if (e is Directory) out.add(e);
    }
    return out;
  }

  Future<int> _fileSize(File f) async {
    try {
      return await f.length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var sum = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) sum += await _fileSize(e);
      }
    } on FileSystemException {
      // Sebagian terbaca sudah cukup untuk perkiraan.
    }
    return sum;
  }
}
