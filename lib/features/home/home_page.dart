import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/constants/app_constants.dart';
import '../../database/app_database.dart';
import '../../services/storage/app_paths.dart';
import '../../services/remote/remote_config_service.dart';
import '../projects/project_actions.dart';
import 'server_status_card.dart';
import '../projects/projects_controller.dart';
import '../projects/widgets/project_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.paths,
    this.storageError,
    this.database,
    this.databaseError,
    this.projects,
    this.remoteConfig,
  });

  final AppPaths? paths;
  final String? storageError;
  final AppDatabase? database;
  final String? databaseError;
  final ProjectsController? projects;
  final RemoteConfigService? remoteConfig;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI VIDEO CLIPPER'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (remoteConfig != null) ServerStatusCard(service: remoteConfig!),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('PROJECT BARU'),
              onPressed: projects == null
                  ? null
                  : () => Navigator.of(context).pushNamed(AppRoutes.newProject),
            ),
            const SizedBox(height: 28),
            Text('Recent Projects', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _ProjectList(
              controller: projects,
              unavailableMessage: databaseError ??
                  storageError ??
                  'Project belum dapat dimuat.',
            ),
            const SizedBox(height: 28),
            Text('Status Sistem', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  paths != null
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color:
                      paths != null ? Colors.green : theme.colorScheme.error,
                ),
                title: Text(paths != null
                    ? 'Folder lokal siap'
                    : (storageError ?? 'Penyimpanan belum siap')),
                subtitle: paths != null ? Text(paths!.root.path) : null,
              ),
            ),
            const SizedBox(height: 12),
            _DatabaseStatusCard(
              database: database,
              databaseError: databaseError,
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'v${AppConstants.appVersion} - STEP 20 Pengaturan',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList({
    required this.controller,
    required this.unavailableMessage,
  });

  final ProjectsController? controller;
  final String unavailableMessage;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error),
          title: Text(unavailableMessage),
        ),
      );
    }

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.loading && c.items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (c.error != null) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text(c.error!),
              trailing: TextButton(
                onPressed: c.load,
                child: const Text('Coba lagi'),
              ),
            ),
          );
        }
        if (c.items.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.movie_creation_outlined,
                      size: 40, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('Belum ada project'),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final s in c.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ProjectCard(
                  key: ValueKey(s.project.id),
                  summary: s,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.projectDetail,
                    arguments: s.project.id,
                  ),
                  onRename: () => renameProjectFlow(context, c, s),
                  onDelete: () => deleteProjectFlow(context, c, s),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DatabaseStatusCard extends StatefulWidget {
  const _DatabaseStatusCard({this.database, this.databaseError});

  final AppDatabase? database;
  final String? databaseError;

  @override
  State<_DatabaseStatusCard> createState() => _DatabaseStatusCardState();
}

class _DatabaseStatusCardState extends State<_DatabaseStatusCard> {
  Future<DatabaseInfo>? _info;

  @override
  void initState() {
    super.initState();
    _info = widget.database?.info();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_info == null) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
          title: Text(widget.databaseError ?? 'Database belum siap'),
        ),
      );
    }

    return FutureBuilder<DatabaseInfo>(
      future: _info,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading:
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
              title: const Text('Database tidak dapat dibaca'),
            ),
          );
        }
        final info = snapshot.data;
        return Card(
          child: ListTile(
            leading: Icon(
              info == null ? Icons.hourglass_empty : Icons.check_circle_outline,
              color: info == null ? null : Colors.green,
            ),
            title: Text(info == null
                ? 'Membuka database...'
                : 'Database SQLite siap (v${info.version})'),
            subtitle: info == null
                ? null
                : Text(
                    '${info.tables.length} tabel: ${info.tables.join(', ')}'),
          ),
        );
      },
    );
  }
}
