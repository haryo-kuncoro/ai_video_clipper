import 'package:flutter/material.dart';

import '../../services/remote/remote_config_service.dart';

/// Pemberitahuan dari server: pemeliharaan, update tersedia/wajib, dan status
/// koneksi. Tidak tampil sama sekali bila backend tidak dikonfigurasi.
class ServerStatusCard extends StatelessWidget {
  const ServerStatusCard({super.key, required this.service});

  final RemoteConfigService service;

  @override
  Widget build(BuildContext context) {
    if (!service.enabled) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cfg = service.config;
        final v = cfg.version;
        final cards = <Widget>[];

        if (cfg.maintenanceEnabled) {
          cards.add(_tile(
            theme,
            Icons.construction_outlined,
            'Pemeliharaan server',
            cfg.maintenanceMessage.isEmpty
                ? 'Sebagian fitur online mungkin terbatas. Fitur lokal tetap berjalan.'
                : cfg.maintenanceMessage,
            theme.colorScheme.tertiary,
          ));
        }
        if (v != null && (v.forceUpdate || v.updateAvailable)) {
          cards.add(_tile(
            theme,
            Icons.system_update_outlined,
            v.forceUpdate ? 'Update wajib: ${v.latestVersion}' : 'Update tersedia: ${v.latestVersion}',
            [
              if (v.releaseNotes != null && v.releaseNotes!.isNotEmpty) v.releaseNotes!,
              if (v.downloadUrl != null) 'Unduh: ${v.downloadUrl}',
            ].join('\n'),
            v.forceUpdate ? theme.colorScheme.error : theme.colorScheme.primary,
          ));
        }

        final status = switch (service.status) {
          RemoteStatus.online => 'Terhubung ke server',
          RemoteStatus.loading => 'Menghubungi server…',
          RemoteStatus.offlineCached => 'Offline, memakai pengaturan tersimpan',
          RemoteStatus.offlineNoData => 'Offline, memakai pengaturan bawaan',
          _ => '',
        };
        if (status.isNotEmpty) {
          cards.add(Card(
            child: ListTile(
              dense: true,
              leading: Icon(
                service.status == RemoteStatus.online
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
              ),
              title: Text(status),
              subtitle: service.lastError == null ? null : Text(service.lastError!),
              trailing: service.status == RemoteStatus.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Muat ulang',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => service.refresh(force: true),
                    ),
            ),
          ));
        }
        if (cards.isEmpty) return const SizedBox.shrink();
        return Column(children: [
          for (final c in cards) ...[c, const SizedBox(height: 12)],
        ]);
      },
    );
  }

  Widget _tile(ThemeData theme, IconData icon, String title, String body, Color color) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: body.isEmpty ? null : Text(body),
      ),
    );
  }
}
