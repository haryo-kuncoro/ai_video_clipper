import 'package:flutter/material.dart';

import '../storage/storage_page.dart';
import '../../services/storage/storage_manager.dart';

import '../../app.dart';
import '../../core/theme/theme_controller.dart';
import '../../services/auth/auth_service.dart';
import '../../services/storage/app_paths.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeController,
    required this.paths,
    this.auth,
    this.storage,
  });

  final ThemeController themeController;
  final AppPaths? paths;
  final AuthService? auth;
  final StorageManager? storage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Tema', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: themeController,
              builder: (context, _) {
                return SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('Sistem'),
                      icon: Icon(Icons.phone_android),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Terang'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Gelap'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {themeController.mode},
                  onSelectionChanged: (s) => themeController.setMode(s.first),
                );
              },
            ),
            if (storage != null) ...[
              const SizedBox(height: 28),
              Text('Penyimpanan', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Pemakaian & pembersihan'),
                  subtitle: const Text('Lihat ruang terpakai, hapus file sementara'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => StoragePage(manager: storage!),
                  )),
                ),
              ),
            ],
            if (auth != null) ...[
              const SizedBox(height: 28),
              Text('Akun', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: auth!,
                builder: (context, _) => Card(
                  child: ListTile(
                    leading: Icon(auth!.isSignedIn
                        ? Icons.account_circle_outlined
                        : Icons.login),
                    title: Text(auth!.isSignedIn
                        ? (auth!.user?.name ?? 'Akun')
                        : 'Masuk atau daftar (opsional)'),
                    subtitle: Text(auth!.isSignedIn
                        ? (auth!.user?.email ?? '')
                        : 'Tidak diperlukan untuk memakai aplikasi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.account),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text('Penyimpanan Lokal', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (paths == null)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.error_outline),
                  title: Text('Penyimpanan belum siap'),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    _PathTile('Root', paths!.root.path),
                    _PathTile('videos/', paths!.videos.path),
                    _PathTile('projects/', paths!.projects.path),
                    _PathTile('clips/', paths!.clips.path),
                    _PathTile('thumbnails/', paths!.thumbnails.path),
                    _PathTile('temp/', paths!.temp.path),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PathTile extends StatelessWidget {
  const _PathTile(this.label, this.path);

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(path),
    );
  }
}
