import 'package:flutter/material.dart';

import '../theme/mhrd_theme.dart';

void toast(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action, behavior: SnackBarBehavior.floating));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? body,
  String ok = 'Так',
  bool danger = false,
}) async {
  final t = context.mhrd;
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Скасувати')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: t.error, foregroundColor: t.background) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Одне текстове поле. Повертає null, якщо скасовано.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  bool obscure = false,
  String ok = 'OK',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Скасувати')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(ok)),
      ],
    ),
  );
}

/// Новий пароль двічі (для бекапу). Повертає null, якщо скасовано.
Future<String?> promptNewPassword(BuildContext context, {required String title}) {
  final a = TextEditingController(), b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: a, obscureText: true, autofocus: true,
                decoration: const InputDecoration(labelText: 'Пароль бекапу')),
            const SizedBox(height: 12),
            TextField(controller: b, obscureText: true,
                decoration: InputDecoration(labelText: 'Повторіть пароль', errorText: err)),
            const SizedBox(height: 12),
            Text('Без цього пароля бекап не відкрити. Його неможливо відновити.',
                style: TextStyle(color: c.mhrd.textMuted, fontSize: 12.5)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Скасувати')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 8) {
                set(() => err = 'Щонайменше 8 символів');
              } else if (a.text != b.text) {
                set(() => err = 'Паролі не збігаються');
              } else {
                Navigator.pop(c, a.text);
              }
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    ),
  );
}

/// Вибір одного варіанта зі списку. Повертає індекс або null.
Future<int?> pickOne(BuildContext context, {required String title, required List<String> options}) {
  return showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(title),
      children: [
        for (var i = 0; i < options.length; i++)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, i), child: Text(options[i])),
      ],
    ),
  );
}
