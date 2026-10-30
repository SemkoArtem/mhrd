import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';

/// Створення або редагування облікового запису. Повертає збережений запис або null.
Future<Credential?> editCredential(BuildContext context, Repository repo, {Credential? existing}) async {
  final l = context.l10n;
  final name = TextEditingController(text: existing?.name ?? '');
  final user = TextEditingController(text: existing?.username ?? '');
  final pass = TextEditingController();
  var mode = existing?.authMode ?? AuthMode.savedPassword;
  var show = false;
  String? err;

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final t = c.mhrd;
      return AlertDialog(
        title: Text(existing == null ? l.credNewTitle : l.credTitle),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: l.nameOptional)),
            const SizedBox(height: 12),
            TextField(
              controller: user,
              autofocus: existing == null,
              decoration: InputDecoration(
                labelText: l.credUser,
                helperText: l.credUserHelper,
                errorText: err,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<AuthMode>(
              segments: [
                ButtonSegment(value: AuthMode.savedPassword, label: Text(l.credSavePassword)),
                ButtonSegment(value: AuthMode.askPassword, label: Text(l.credAskEveryTime)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => set(() => mode = s.first),
            ),
            if (mode == AuthMode.savedPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: pass,
                obscureText: !show,
                decoration: InputDecoration(
                  labelText: existing == null ? l.password : l.credNewPassword,
                  suffixIcon: IconButton(
                    tooltip: show ? l.hidePassword : l.showPassword,
                    icon: Icon(show ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => set(() => show = !show),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(l.credStoredNote, style: TextStyle(color: t.textMuted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          FilledButton(
            onPressed: () {
              if (user.text.trim().isEmpty) {
                set(() => err = l.credUserRequired);
                return;
              }
              Navigator.pop(c, true);
            },
            child: Text(l.save),
          ),
        ],
      );
    }),
  );
  if (ok != true) return null;

  final cred = Credential(
    id: existing?.id ?? newId(),
    name: name.text.trim(),
    username: user.text.trim(),
    authMode: mode,
  );
  // askPassword → видаляємо збережений пароль; saved + порожнє поле при редагуванні → не чіпаємо.
  final String? pw = mode == AuthMode.askPassword
      ? ''
      : (pass.text.isEmpty && existing != null ? null : pass.text);
  await repo.saveCredential(cred, password: pw);
  return cred;
}
