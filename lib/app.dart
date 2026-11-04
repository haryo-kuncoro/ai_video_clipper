import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'database/app_database.dart';
import 'features/home/home_page.dart';
import 'features/projects/new_project_page.dart';
import 'features/projects/project_detail_page.dart';
import 'features/projects/projects_controller.dart';
import 'features/settings/settings_page.dart';
import 'features/account/account_page.dart';
import 'services/models/model_catalog.dart';
import 'services/storage/storage_manager.dart';
import 'services/auth/auth_service.dart';
import 'services/remote/remote_config_service.dart';
import 'services/storage/app_paths.dart';

class AiVideoClipperApp extends StatelessWidget {
  const AiVideoClipperApp({
    super.key,
    required this.themeController,
    required this.paths,
    this.storageError,
    this.database,
    this.databaseError,
    this.projects,
    this.remoteConfig,
    this.storage,
    this.auth,
    this.models,
  });

  final ThemeController themeController;
  final AppPaths? paths;
  final String? storageError;
  final AppDatabase? database;
  final String? databaseError;
  final ProjectsController? projects;
  final RemoteConfigService? remoteConfig;
  final StorageManager? storage;
  final AuthService? auth;
  final ModelCatalog? models;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.mode,
          initialRoute: AppRoutes.home,
          routes: {
            AppRoutes.home: (_) => HomePage(
                  paths: paths,
                  storageError: storageError,
                  database: database,
                  databaseError: databaseError,
                  projects: projects,
                  remoteConfig: remoteConfig,
                ),
            AppRoutes.settings: (_) => SettingsPage(
                  themeController: themeController,
                  paths: paths,
                  auth: auth,
                  storage: storage,
                  models: models,
                ),
            AppRoutes.account: (_) => AccountPage(
                  auth: auth!,
                  remoteConfig: remoteConfig,
                ),
            AppRoutes.newProject: (_) => NewProjectPage(controller: projects!),
          },
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.projectDetail &&
                projects != null &&
                settings.arguments is int) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => ProjectDetailPage(
                  controller: projects!,
                  projectId: settings.arguments as int,
                ),
              );
            }
            return null;
          },
        );
      },
    );
  }
}

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const settings = '/settings';
  static const account = '/account';
  static const newProject = '/new-project';
  static const projectDetail = '/project';
}
