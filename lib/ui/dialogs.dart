import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/mhrd_theme.dart';

/// Дата й час для людей: 30.10.2026 20:45 (місцевий час).
String formatDateTime(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Сторінка налаштувань: вміст завширшки до [maxWidth] посередині, але сам список — на всю
/// ширину, щоб гортати коліщатком можна було з будь-якого місця, а не лише над текстом.
Widget centeredList(List<Widget> children, {required double maxWidth}) => LayoutBuilder(
      builder: (context, box) {
        final side = ((box.maxWidth - maxWidth) / 2).clamp(20.0, double.infinity);
        return ListView(padding: EdgeInsets.fromLTRB(side, 20, side, 20), children: children);
      },
    );

void toast(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action, behavior: SnackBarBehavior.floating));
}

/// [ok] за замовчуванням — «Так».
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? body,
  String? ok,
  bool danger = false,
}) async {
  final t = context.mhrd;
  final l = context.l10n;
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: t.error, foregroundColor: t.background) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok ?? l.yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Одне текстове поле. Повертає null, якщо скасовано. [ok] за замовчуванням — «OK».
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  bool obscure = false,
  String? ok,
}) {
  final l = context.l10n;
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
        TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(ok ?? l.ok)),
      ],
    ),
  );
}

/// Новий пароль двічі (для бекапу). Повертає null, якщо скасовано.
Future<String?> promptNewPassword(BuildContext context, {required String title}) {
  final l = context.l10n;
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
                decoration: InputDecoration(labelText: l.backupPasswordLabel)),
            const SizedBox(height: 12),
            TextField(controller: b, obscureText: true,
                decoration: InputDecoration(labelText: l.repeatPassword, errorText: err)),
            const SizedBox(height: 12),
            Text(l.backupPasswordWarning, style: TextStyle(color: c.mhrd.textMuted, fontSize: 12.5)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
          FilledButton(
            onPressed: () {
              if (a.text.length < 8) {
                set(() => err = l.passwordTooShort);
              } else if (a.text != b.text) {
                set(() => err = l.passwordsDontMatch);
              } else {
                Navigator.pop(c, a.text);
              }
            },
            child: Text(l.save),
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
