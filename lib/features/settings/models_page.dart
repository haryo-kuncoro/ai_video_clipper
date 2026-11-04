import 'package:flutter/material.dart';

import '../../core/utils/format_utils.dart';
import '../../services/models/model_catalog.dart';
import '../../services/transcription/transcription_models.dart';
import '../../services/translation/text_translator.dart';

/// Pengaturan > Model AI: unduh/hapus model Speech-to-Text dan model
/// terjemahan. Dilakukan sekali; setelah itu seluruh proses offline.
class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key, required this.catalog});

  final ModelCatalog catalog;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  @override
  void initState() {
    super.initState();
    widget.catalog.refresh();
  }

  Future<void> _confirmDelete(String name, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus model?'),
        content: Text('Model $name akan dihapus dari HP. Anda bisa '
            'mengunduhnya lagi kapan saja.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) await action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = widget.catalog;

    return Scaffold(
      appBar: AppBar(title: const Text('Model AI (offline)')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: cat,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Model diunduh sekali dari internet. Setelah itu seluruh '
                  'proses berjalan offline di HP; video dan teks tidak dikirim '
                  'ke server mana pun.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (cat.busy) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat.busyLabel,
                              style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: cat.fraction),
                          if (cat.busyKey?.startsWith('stt:') ?? false)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: cat.cancel,
                                child: const Text('Batalkan'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (cat.message != null) ...[
                  const SizedBox(height: 12),
                  Text(cat.message!, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 24),
                Text('Transcript (Speech-to-Text)',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Untuk bahasa Korea/Jepang/Mandarin, pilih Small bila HP '
                  'kuat (akurasi jauh lebih baik).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final m in WhisperModels.all)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        cat.whisperInstalled(m)
                            ? Icons.check_circle
                            : Icons.cloud_download_outlined,
                        color: cat.whisperInstalled(m) ? Colors.green : null,
                      ),
                      title: Text(m.label),
                      subtitle: Text(cat.whisperInstalled(m)
                          ? 'Terpasang (${formatFileSize(cat.whisperSize(m))})'
                          : m.description),
                      trailing: _action(
                        installed: cat.whisperInstalled(m),
                        busyHere: cat.busyKey == ModelCatalog.whisperKey(m),
                        disabled: cat.busy,
                        onDownload: () => cat.downloadWhisper(m),
                        onDelete: () => _confirmDelete(
                            m.label, () => cat.deleteWhisper(m)),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text('Terjemahan', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Untuk menerjemahkan, unduh model bahasa asal DAN Indonesia '
                  '(±30 MB per bahasa). Contoh Korea → Indonesia: unduh Korea '
                  'dan Indonesia.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final code in TranslationLanguages.names.keys)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        cat.translationReady(code)
                            ? Icons.check_circle
                            : Icons.translate,
                        color: cat.translationReady(code) ? Colors.green : null,
                      ),
                      title: Text(TranslationLanguages.names[code]!),
                      subtitle: Text(cat.translationReady(code)
                          ? 'Terpasang'
                          : 'Belum diunduh'),
                      trailing: _action(
                        installed: cat.translationReady(code),
                        busyHere:
                            cat.busyKey == ModelCatalog.translationKey(code),
                        disabled: cat.busy,
                        onDownload: () => cat.downloadTranslation(code),
                        onDelete: () => _confirmDelete(
                            TranslationLanguages.names[code]!,
                            () => cat.deleteTranslation(code)),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _action({
    required bool installed,
    required bool busyHere,
    required bool disabled,
    required VoidCallback onDownload,
    required VoidCallback onDelete,
  }) {
    if (busyHere) {
      return const SizedBox(
          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (installed) {
      return IconButton(
        tooltip: 'Hapus',
        icon: const Icon(Icons.delete_outline),
        onPressed: disabled ? null : onDelete,
      );
    }
    return FilledButton.tonal(
      onPressed: disabled ? null : onDownload,
      child: const Text('Unduh'),
    );
  }
}
