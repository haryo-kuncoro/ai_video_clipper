import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/format_utils.dart';
import '../../services/storage/storage_manager.dart';

/// Halaman "Penyimpanan": pemakaian per kategori, ruang kosong, dan
/// pembersihan aman (file sementara + file yatim buatan aplikasi).
/// Video asli pengguna dan hasil ekspor di galeri tidak pernah disentuh.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key, required this.manager});

  final StorageManager manager;

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  StorageUsage? _usage;
  OrphanReport _orphans = OrphanReport.none;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final usage = await widget.manager.usage();
      final orphans = await widget.manager.findOrphans();
      if (!mounted) return;
      setState(() {
        _usage = usage;
        _orphans = orphans;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.e('Gagal membaca penyimpanan', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Penyimpanan tidak dapat dibaca.';
        });
      }
    }
  }

  Future<void> _run(Future<int> Function() action, String done) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final freed = await action();
      if (mounted) setState(() => _message = '$done ${formatFileSize(freed)} dibebaskan.');
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e, st) {
      AppLogger.e('Pembersihan gagal', e, st);
      if (mounted) setState(() => _message = 'Pembersihan tidak dapat diselesaikan.');
    }
    if (mounted) setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _confirmOrphans() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus file yatim?'),
        content: Text(
          '${_orphans.count} file (${formatFileSize(_orphans.bytes)}) sisa clip/thumbnail '
          'yang tidak lagi terdaftar akan dihapus. Video asli Anda dan hasil ekspor '
          'di galeri tidak tersentuh.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await _run(widget.manager.deleteOrphans, 'File yatim dihapus,');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = _usage;
    return Scaffold(
      appBar: AppBar(title: const Text('Penyimpanan')),
      body: _loading && u == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (u != null) ...[
                    if (u.lowSpace)
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: ListTile(
                          leading: Icon(Icons.warning_amber_rounded,
                              color: theme.colorScheme.onErrorContainer),
                          title: Text('Ruang kosong menipis',
                              style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                          subtitle: Text(
                            'Sisa ${formatFileSize(u.freeBytes ?? 0)}. Render clip bisa gagal; '
                            'bersihkan file di bawah atau hapus project lama.',
                            style: TextStyle(color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                    Card(
                      child: Column(
                        children: [
                          _tile('Video sumber (salinan)', u.videos),
                          _tile('Clip hasil render', u.clips),
                          _tile('Thumbnail', u.thumbnails),
                          _tile('File sementara', u.temp),
                          _tile('Model suara (offline)', u.models),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            title: const Text('Total aplikasi'),
                            trailing: Text(formatFileSize(u.total),
                                style: theme.textTheme.titleSmall),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('Ruang kosong perangkat'),
                            trailing: Text(u.freeBytes == null
                                ? 'tidak diketahui'
                                : formatFileSize(u.freeBytes!)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.cleaning_services_outlined),
                            title: const Text('Bersihkan file sementara'),
                            subtitle: Text(formatFileSize(u.temp)),
                            enabled: !_busy && u.temp > 0,
                            onTap: () => _run(widget.manager.cleanTemp, 'File sementara dibersihkan,'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.delete_sweep_outlined),
                            title: const Text('Hapus file yatim'),
                            subtitle: Text(_orphans.count == 0
                                ? 'Tidak ada'
                                : '${_orphans.count} file · ${formatFileSize(_orphans.bytes)}'),
                            enabled: !_busy && _orphans.count > 0,
                            onTap: _confirmOrphans,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_message!, style: theme.textTheme.bodyMedium),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Hanya file buatan aplikasi di folder privat yang dapat dihapus. '
                    'Video asli dan hasil ekspor di galeri/Downloads tidak pernah dihapus dari sini.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tile(String label, int bytes) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(formatFileSize(bytes)),
      );
}
