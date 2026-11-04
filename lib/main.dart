import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'database/repositories/app_settings_repository.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/secure_store.dart';
import 'services/settings/app_settings.dart';
import 'services/storage/storage_manager.dart';
import 'services/remote/api_client.dart';
import 'services/remote/remote_config_service.dart';
import 'services/background/keep_alive.dart';
import 'services/pipeline/pipeline_backend.dart';
import 'services/pipeline/processing_pipeline.dart';
import 'services/pipeline/startup_recovery.dart';
import 'database/repositories/export_repository.dart';
import 'services/export/export_service.dart';
import 'services/export/gallery_exporter.dart';
import 'core/errors/app_exception.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/app_logger.dart';
import 'database/app_database.dart';
import 'database/repositories/clip_candidate_repository.dart';
import 'database/repositories/clip_edit_repository.dart';
import 'database/repositories/clip_repository.dart';
import 'database/repositories/processing_job_repository.dart';
import 'database/repositories/project_repository.dart';
import 'database/repositories/subtitle_settings_repository.dart';
import 'database/repositories/transcript_repository.dart';
import 'features/projects/projects_controller.dart';
import 'features/video/media_probe.dart';
import 'services/ai/clip_detection_service.dart';
import 'services/ai/rule_based_clip_detector.dart';
import 'services/face/native_face_detector.dart';
import 'services/ffmpeg/ffmpeg_kit_runner.dart';
import 'services/ffmpeg/ffmpeg_queue.dart';
import 'services/ffmpeg/ffmpeg_service.dart';
import 'features/video/video_import_service.dart';
import 'features/video/video_picker.dart';
import 'services/render/clip_render_service.dart';
import 'services/storage/app_paths.dart';
import 'services/transcription/sherpa_whisper_engine.dart';
import 'services/transcription/transcription_service.dart';
import 'services/transcription/whisper_model_manager.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      AppLogger.e('FlutterError', details.exception, details.stack);
    };

    final themeController = ThemeController();
    await themeController.load();

    AppPaths? paths;
    String? storageError;
    try {
      paths = await AppPaths.init();
    } on AppException catch (e) {
      storageError = e.message;
    } catch (e, st) {
      AppLogger.e('Inisialisasi storage gagal', e, st);
      storageError = 'Penyimpanan lokal tidak dapat disiapkan.';
    }

    AppDatabase? database;
    String? databaseError;
    try {
      database = await AppDatabase.open();
      // Pekerjaan yang terputus (app ditutup/crash) ditandai gagal, status
      // project dipulihkan, file sementara dibersihkan (STEP 17).
      await StartupRecovery(
        jobs: ProcessingJobRepository(database.db),
        projects: ProjectRepository(database.db),
        paths: paths,
      ).run();
    } on AppException catch (e) {
      databaseError = e.message;
    } catch (e, st) {
      AppLogger.e('Inisialisasi database gagal', e, st);
      databaseError = 'Database lokal tidak dapat dibuka.';
    }

    // Konfigurasi server (opsional, offline-first): tidak pernah menahan startup.
    final RemoteConfigService? remoteConfig = database == null
        ? null
        : RemoteConfigService(
        api: AppConfig.apiBaseUrl.isEmpty
            ? null
            : HttpApiClient(baseUrl: AppConfig.apiBaseUrl),
        store: AppSettingsRepository(database.db),
        appBuild: AppConstants.appBuild,
      );
    AppSettings currentSettings() => AppSettings.resolve(remoteConfig?.config);


    ProjectsController? projects;
    if (database != null && paths != null) {
      try {
        final cacheDir = await getTemporaryDirectory();
        final ffmpeg = FFmpegService(FFmpegQueue(FFmpegKitRunner()));
        final candidateRepo = ClipCandidateRepository(database.db);
        final transcriptRepo = TranscriptRepository(database.db);
        final projectRepo = ProjectRepository(database.db);
        final jobRepo = ProcessingJobRepository(database.db);
        final transcriptionService = TranscriptionService(
          ffmpeg: ffmpeg,
          engine: const SherpaWhisperEngine(),
          models: WhisperModelManager(
            Directory(p.join(paths.root.path, 'models')),
          ),
          transcripts: transcriptRepo,
          projects: projectRepo,
          jobs: jobRepo,
          paths: paths,
        );
        final detectionService = ClipDetectionService(
          detector: const RuleBasedClipDetector(),
          transcripts: transcriptRepo,
          candidates: candidateRepo,
          projects: projectRepo,
          jobs: jobRepo,
        );
        final renderService = ClipRenderService(
          ffmpeg: ffmpeg,
          probe: NativeMediaProbe(),
          faceDetector: NativeFaceDetector(),
          paths: paths,
          clips: ClipRepository(database.db),
          candidates: candidateRepo,
          edits: ClipEditRepository(database.db),
          transcripts: transcriptRepo,
          subtitleSettings: SubtitleSettingsRepository(database.db),
          projects: projectRepo,
          jobs: jobRepo,
          settings: currentSettings,
        );
        final exportSvc = ExportService(
          exporter: NativeGalleryExporter(),
          exports: ExportRepository(database.db),
          transcripts: transcriptRepo,
          paths: paths,
        );
        projects = ProjectsController(
          database.db,
          paths,
          ffmpeg: ffmpeg,
          transcription: transcriptionService,
          clipDetection: detectionService,
          clipRender: renderService,
          exportService: exportSvc,
          settings: currentSettings,
          pipeline: ProcessingPipeline(
            backend: ServicePipelineBackend(
              transcription: transcriptionService,
              detection: detectionService,
              render: renderService,
              export: exportSvc,
            ),
            keepAlive: NativeKeepAlive(),
          ),
          subtitleSettings: SubtitleSettingsRepository(database.db),
          importService: VideoImportService(
            db: database.db,
            paths: paths,
            picker: FilePickerVideoPicker(),
            probe: NativeMediaProbe(),
            pickerCacheDir: cacheDir,
          ),
        );
        await projects.load();
      } catch (e, st) {
        AppLogger.e('Inisialisasi project gagal', e, st);
        databaseError ??= 'Project tidak dapat disiapkan.';
        projects = null;
      }
    }

    final storage = (database != null && paths != null)
        ? StorageManager(
            paths: paths,
            db: database.db,
            probe: NativeMediaProbe(),
            settings: currentSettings,
            isBusy: () =>
                projects?.pipeline?.isRunning == true ||
                projects?.clipRender?.isRunning == true,
          )
        : null;

    final auth = AuthService(
      api: AppConfig.apiBaseUrl.isEmpty
          ? null
          : HttpApiClient(baseUrl: AppConfig.apiBaseUrl),
      store: FlutterSecureStore(),
    );
    await auth.restore();

    runApp(
      AiVideoClipperApp(
        themeController: themeController,
        paths: paths,
        storageError: storageError,
        database: database,
        databaseError: databaseError,
        projects: projects,
        remoteConfig: remoteConfig,
        storage: storage,
        auth: auth,
      ),
    );
    if (remoteConfig != null) unawaited(remoteConfig.refresh());
  }, (error, stack) {
    AppLogger.e('Uncaught error', error, stack);
  });
}
