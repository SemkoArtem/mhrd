import 'package:flutter/material.dart';

import '../models/entities.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';

/// Створення або редагування облікового запису. Повертає збережений запис або null.
Future<Credential?> editCredential(BuildContext context, Repository repo, {Credential? existing}) async {
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
        title: Text(existing == null ? 'Новий обліковий запис' : 'Обліковий запис'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Назва (необов\'язково)')),
            const SizedBox(height: 12),
            TextField(
              controller: user,
              autofocus: existing == null,
              decoration: InputDecoration(
                labelText: 'Користувач',
                helperText: 'user, DOMAIN\\user або user@domain',
                errorText: err,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<AuthMode>(
              segments: const [
                ButtonSegment(value: AuthMode.savedPassword, label: Text('Зберегти пароль')),
                ButtonSegment(value: AuthMode.askPassword, label: Text('Питати щоразу')),
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
                  labelText: existing == null ? 'Пароль' : 'Новий пароль (порожньо = не змінювати)',
                  suffixIcon: IconButton(
                    tooltip: show ? 'Сховати пароль' : 'Показати пароль',
                    icon: Icon(show ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => set(() => show = !show),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text('Пароль зберігається в системному сховищі цього пристрою.',
                style: TextStyle(color: t.textMuted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Скасувати')),
          FilledButton(
            onPressed: () {
              if (user.text.trim().isEmpty) {
                set(() => err = 'Вкажіть користувача');
                return;
              }
              Navigator.pop(c, true);
            },
            child: const Text('Зберегти'),
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
