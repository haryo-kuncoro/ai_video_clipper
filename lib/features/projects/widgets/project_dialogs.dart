import 'package:flutter/material.dart';

Future<bool> confirmDeleteProject(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Hapus project?'),
        content: Text(
          'Project "$name" akan dihapus permanen beserta semua clip, '
          'thumbnail, transcript, dan file sementara.\n\n'
          'Salinan video yang dikelola aplikasi ikut dihapus. '
          'Video asli milik Anda di perangkat tidak akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Mengembalikan nama baru (sudah di-trim) atau null bila dibatalkan.
Future<String?> promptRenameProject(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: current),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Nama project tidak boleh kosong.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ganti nama project'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Nama project',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _submit,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
