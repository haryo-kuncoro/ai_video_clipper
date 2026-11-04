import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/project.dart';
import '../../database/models/project_summary.dart';
import '../../database/models/video_record.dart';
import '../../database/repositories/project_repository.dart';
import '../../database/repositories/subtitle_settings_repository.dart';
import '../../database/repositories/video_repository.dart';
import '../../services/ai/clip_detection_service.dart';
import '../../services/ffmpeg/ffmpeg_service.dart';
import '../../services/export/export_service.dart';
import '../../services/pipeline/processing_pipeline.dart';
import '../../services/settings/app_settings.dart';
import '../../services/render/clip_render_service.dart';
import '../../services/storage/app_paths.dart';
import '../../services/transcription/transcription_service.dart';
import '../video/video_import_service.dart';
import 'project_deletion_service.dart';

/// State daftar project untuk UI. Semua data berasal dari SQLite lokal.
class ProjectsController extends ChangeNotifier {
  ProjectsController(
    Database db,
    this.paths, {
    VideoImportService? importService,
    this.ffmpeg,
    this.subtitleSettings,
    this.transcription,
    this.clipDetection,
    this.clipRender,
    this.exportService,
    this.pipeline,
    AppSettings Function()? settings,
  })  : _projects = ProjectRepository(db),
        _videos = VideoRepository(db),
        _deletion = ProjectDeletionService(db, paths),
        _importService = importService,
        _settings = settings ?? (() => AppSettings.defaults);

  final AppPaths paths;

  /// FFmpeg lokal (null bila tidak tersedia, mis. di test).
  final FFmpegService? ffmpeg;

  /// Pengaturan subtitle di SQLite (null bila tidak tersedia).
  final SubtitleSettingsRepository? subtitleSettings;

  /// Speech-to-text lokal (null bila tidak tersedia, mis. di test).
  final TranscriptionService? transcription;

  /// Deteksi clip offline (null bila tidak tersedia, mis. di test).
  final ClipDetectionService? clipDetection;

  /// Render clip (null bila tidak tersedia, mis. di test).
  final ClipRenderService? clipRender;

  /// Ekspor ke galeri/MediaStore (null bila tidak tersedia, mis. di test).
  final ExportService? exportService;

  /// Pipeline otomatis di latar belakang (null bila tidak tersedia).
  final ProcessingPipeline? pipeline;
  final AppSettings Function() _settings;

  /// Pengaturan efektif saat ini (server + fallback lokal).
  AppSettings get settings => _settings();
  final ProjectRepository _projects;
  final VideoRepository _videos;
  final ProjectDeletionService _deletion;
  final VideoImportService? _importService;

  List<ProjectSummary> _items = const [];
  bool _loading = false;
  String? _error;

  List<ProjectSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _projects.getSummaries();
    } catch (e, st) {
      AppLogger.e('Gagal memuat project', e, st);
      _error = 'Daftar project tidak dapat dimuat.';
    }
    _loading = false;
    notifyListeners();
  }

  Future<Project> create(String name) async {
    final project = await _projects.create(name);
    try {
      await paths.ensureProjectDir(project.id!);
    } catch (e, st) {
      // Folder akan dibuat ulang saat dibutuhkan; jangan gagalkan project.
      AppLogger.e('Gagal membuat folder project', e, st);
    }
    await load();
    return project;
  }

  Future<void> rename(int id, String name) async {
    await _projects.rename(id, name);
    await load();
  }

  Future<ProjectDeletionResult> delete(int id) async {
    final result = await _deletion.delete(id);
    await load();
    return result;
  }

  Future<ProjectSummary?> getSummary(int id) => _projects.getSummaryById(id);

  /// Video sumber project (null bila belum dipilih).
  Future<VideoRecord?> getSourceVideo(int projectId) async {
    final list = await _videos.getByProject(projectId);
    return list.isEmpty ? null : list.first;
  }

  /// Memilih dan mengimpor video ke project. Null bila pengguna membatalkan.
  Future<VideoImportResult?> importVideo(int projectId) async {
    final service = _importService;
    if (service == null) {
      throw const AppException('Pemilih video belum siap.');
    }
    final result = await service.importInto(projectId);
    if (result != null) await load();
    return result;
  }
}
