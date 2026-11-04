import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../services/auth/auth_service.dart';
import '../../services/remote/remote_config_service.dart';

/// Akun OPSIONAL. Semua fitur lokal tetap berjalan tanpa masuk.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.auth, this.remoteConfig});

  final AuthService auth;
  final RemoteConfigService? remoteConfig;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  bool get _registrationOpen =>
      widget.remoteConfig?.config.feature('registration_open') ?? true;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (!mounted) return;
      _password.clear();
      if (success != null) setState(() => _info = success);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      AppLogger.e('Aksi akun gagal', e, st);
      if (mounted) setState(() => _error = 'Terjadi kesalahan. Coba lagi.');
    }
  }

  Future<void> _submit() => _run(() => _register
      ? widget.auth.register(
          email: _email.text, name: _name.text, password: _password.text)
      : widget.auth.login(email: _email.text, password: _password.text));

  Future<String?> _askPassword(String title, String confirm) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(title: title, confirmLabel: confirm),
    );
  }

  Future<void> _changePassword() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (result == null) return;
    await _run(
      () => widget.auth.changePassword(
          currentPassword: result.$1, newPassword: result.$2),
      success: 'Kata sandi diubah. Perangkat lain perlu masuk lagi.',
    );
  }

  Future<void> _deleteAccount() async {
    final pass = await _askPassword(
      'Hapus akun?',
      'Hapus akun',
    );
    if (pass == null) return;
    await _run(
      () => widget.auth.deleteAccount(password: pass),
      success: 'Akun dihapus. Data di perangkat ini tidak berubah.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.auth,
            if (widget.remoteConfig != null) widget.remoteConfig!,
          ]),
          builder: (context, _) {
            final theme = Theme.of(context);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Akun bersifat opsional'),
                    subtitle: const Text(
                      'Semua fitur berjalan di perangkat ini tanpa masuk. '
                      'Video, project, clip, dan transcript tidak pernah dikirim ke server.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!widget.auth.available)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text('Server belum dikonfigurasi'),
                      subtitle: Text('Aplikasi dibuat tanpa API_BASE_URL.'),
                    ),
                  )
                else if (widget.auth.isSignedIn)
                  ..._signedIn(theme)
                else
                  ..._form(theme),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Text(_info!),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _signedIn(ThemeData theme) {
    final u = widget.auth.user;
    final busy = widget.auth.busy;
    return [
      Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(u?.name ?? ''),
          subtitle: Text(u?.email ?? ''),
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: busy ? null : _changePassword,
        icon: const Icon(Icons.key_outlined),
        label: const Text('Ganti kata sandi'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: busy ? null : () => _run(widget.auth.logout),
        icon: const Icon(Icons.logout),
        label: const Text('Keluar'),
      ),
      const SizedBox(height: 24),
      TextButton.icon(
        onPressed: busy ? null : _deleteAccount,
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Hapus akun'),
      ),
    ];
  }

  List<Widget> _form(ThemeData theme) {
    final busy = widget.auth.busy;
    final canRegister = _registrationOpen;
    final registering = _register && canRegister;
    return [
      if (canRegister)
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Masuk')),
            ButtonSegment(value: true, label: Text('Daftar')),
          ],
          selected: {registering},
          onSelectionChanged: busy
              ? null
              : (s) => setState(() {
                    _register = s.first;
                    _error = null;
                  }),
        )
      else
        const Text('Pendaftaran akun baru sedang ditutup.'),
      const SizedBox(height: 16),
      TextField(
        controller: _email,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
      ),
      if (registering) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          enabled: !busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder()),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        enabled: !busy,
        obscureText: !_showPassword,
        autofillHints: [registering ? AutofillHints.newPassword : AutofillHints.password],
        onSubmitted: (_) => busy ? null : _submit(),
        decoration: InputDecoration(
          labelText: 'Kata sandi',
          helperText: registering ? 'Minimal 8 karakter' : null,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _showPassword ? 'Sembunyikan' : 'Tampilkan',
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy ? null : _submit,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(registering ? 'Daftar' : 'Masuk'),
      ),
    ];
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Akun di server akan dihapus permanen. Data di perangkat ini tidak berubah. Masukkan kata sandi untuk konfirmasi.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Kata sandi'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ganti kata sandi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Kata sandi saat ini'),
          ),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Kata sandi baru',
              helperText: 'Minimal 8 karakter',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_current.text, _next.text)),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
