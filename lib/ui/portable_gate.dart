import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../platform/portable.dart';
import '../storage/file_secret_store.dart';
import '../theme/mhrd_theme.dart';

/// Портативна версія (і Linux без системного сховища паролів): перед програмою — майстер-пароль
/// файлу секретів. Перший запуск — створити пароль, далі — розблокувати. Поки файл закритий, MHRD
/// не бачить жодного пароля чи ключа.
class PortableGate extends StatefulWidget {
  const PortableGate({super.key, required this.store, required this.child});
  final FileSecretStore store;
  final Widget child;

  @override
  State<PortableGate> createState() => _PortableGateState();
}

class _PortableGateState extends State<PortableGate> {
  final _pw = TextEditingController(), _repeat = TextEditingController();
  final _focus = FocusNode();
  late final bool _creating = !widget.store.exists;
  String? _error;
  bool _busy = false, _broken = false;

  @override
  void dispose() {
    _pw.dispose();
    _repeat.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = context.l10n;
    final pw = _pw.text;
    if (_creating) {
      if (pw.length < FileSecretStore.minPasswordLength) {
        return setState(() => _error = l.masterPasswordTooShort(FileSecretStore.minPasswordLength));
      }
      if (pw != _repeat.text) return setState(() => _error = l.masterPasswordMismatch);
    } else if (pw.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      if (_creating) {
        await widget.store.create(pw);
      } else if (!await widget.store.unlock(pw)) {
        error = l.masterPasswordWrong;
      }
    } on FormatException {
      _broken = true;
      error = l.secretsFileBroken(widget.store.file.path);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error != null) _pw.clear();
    });
    // Поле було вимкнене на час перевірки — повертаємо в нього курсор для наступної спроби.
    if (error != null && !_broken) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.store.unlocked) return widget.child;
    final t = context.mhrd;
    final l = context.l10n;
    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Portable.enabled ? Icons.usb_outlined : Icons.key_outlined, size: 44, color: t.accent),
              const SizedBox(height: 14),
              Text(Portable.enabled ? l.portableTitle : l.keyringFallbackTitle,
                  style: TextStyle(fontFamily: t.fontMono, fontSize: 22, letterSpacing: 0.8, color: t.accent)),
              const SizedBox(height: 8),
              Text(
                  _creating
                      ? (Portable.enabled ? l.portableCreateHint : l.keyringFallbackCreateHint)
                      : l.portableUnlockHint,
                  textAlign: TextAlign.center, style: TextStyle(color: t.textMuted)),
              const SizedBox(height: 22),
              TextField(
                controller: _pw,
                focusNode: _focus,
                autofocus: true,
                obscureText: true,
                enabled: !_busy && !_broken,
                decoration: InputDecoration(labelText: l.masterPassword),
                onChanged: (_) => _error != null && !_broken ? setState(() => _error = null) : null,
                onSubmitted: (_) => _creating ? null : _submit(),
              ),
              if (_creating) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _repeat,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: l.masterPasswordRepeat),
                  onSubmitted: (_) => _submit(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.error)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || _broken ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_creating ? l.portableCreate : l.unlock),
                ),
              ),
              if (_creating) ...[
                const SizedBox(height: 18),
                Text(l.portableImportHint,
                    textAlign: TextAlign.center, style: TextStyle(color: t.textMuted, fontSize: 12.5)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Діалог «новий майстер-пароль двічі». Повертає пароль або null, якщо скасували.
Future<String?> askNewMasterPassword(BuildContext context) {
  final l = context.l10n;
  final a = TextEditingController(), b = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (dc) => StatefulBuilder(
      builder: (dc, setState) {
        void ok() {
          if (a.text.length < FileSecretStore.minPasswordLength) {
            setState(() => error = l.masterPasswordTooShort(FileSecretStore.minPasswordLength));
          } else if (a.text != b.text) {
            setState(() => error = l.masterPasswordMismatch);
          } else {
            Navigator.pop(dc, a.text);
          }
        }

        return AlertDialog(
          title: Text(l.masterPasswordChange),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: a,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(labelText: l.masterPasswordNew)),
            const SizedBox(height: 10),
            TextField(
                controller: b,
                obscureText: true,
                decoration: InputDecoration(labelText: l.masterPasswordRepeat),
                onSubmitted: (_) => ok()),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: context.mhrd.error)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc), child: Text(l.cancel)),
            FilledButton(onPressed: ok, child: Text(l.save)),
          ],
        );
      },
    ),
  );
}

/// Діалог «майстер-пароль» для чутливої дії (портативна версія). true — пароль правильний.
Future<bool> confirmMasterPassword(BuildContext context, FileSecretStore store) async {
  final l = context.l10n;
  final c = TextEditingController();
  final pw = await showDialog<String>(
    context: context,
    builder: (dc) => AlertDialog(
      title: Text(l.masterPassword),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        onSubmitted: (v) => Navigator.pop(dc, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dc), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(dc, c.text), child: Text(l.ok)),
      ],
    ),
  );
  return pw != null && pw.isNotEmpty && await store.checkPassword(pw);
}
