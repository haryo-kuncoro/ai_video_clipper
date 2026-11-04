import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import 'projects_controller.dart';

class NewProjectPage extends StatefulWidget {
  const NewProjectPage({super.key, required this.controller});

  final ProjectsController controller;

  @override
  State<NewProjectPage> createState() => _NewProjectPageState();
}

class _NewProjectPageState extends State<NewProjectPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final project = await widget.controller.create(_nameController.text);
      if (!mounted) return;
      navigator.pushReplacementNamed(
        AppRoutes.projectDetail,
        arguments: project.id,
      );
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    } catch (e, st) {
      AppLogger.e('Buat project gagal', e, st);
      messenger.showSnackBar(
          const SnackBar(content: Text('Project gagal dibuat.')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Project Baru')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _nameController,
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Nama project',
                  hintText: 'mis. Podcast Episode 01',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama project tidak boleh kosong.'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Video dipilih pada langkah berikutnya (STEP 4). '
              'Semua data project disimpan di perangkat ini.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Buat Project'),
            ),
          ],
        ),
      ),
    );
  }
}
