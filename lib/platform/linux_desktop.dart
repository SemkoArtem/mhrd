import 'dart:io';

import 'package:path/path.dart' as p;

/// Linux: ярлик ПК на робочому столі — файл `.desktop` (специфікація freedesktop.org), що запускає
/// `mhrd --connect <id>`. Якщо MHRD уже відкритий, раннер передає підключення йому
/// (linux/runner/my_application.cc).
abstract final class LinuxDesktop {
  /// Програма для ярлика: сам файл AppImage (програма всередині нього змонтована лише на час
  /// роботи) або mhrd з розпакованого архіву.
  static String get executable => Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;

  /// Вміст `.desktop` для ярлика: назва [name], `--connect` [target], піктограма [icon].
  static String entry({required String exe, required String target, required String name, String? icon}) {
    final title = name.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return [
      '[Desktop Entry]',
      'Type=Application',
      'Version=1.0',
      'Name=$title (MHRD)',
      'Comment=MHRD',
      'Exec=${quoteExec(exe)} --connect ${quoteExec(target)}',
      if (icon != null) 'Icon=$icon',
      'Terminal=false',
      'StartupWMClass=ua.mhrd.mhrd',
      '',
    ].join('\n');
  }

  /// Аргумент рядка Exec: у лапках, з екрануванням `"`, `` ` ``, `$`, `\`; `%` → `%%` (інакше це код поля).
  static String quoteExec(String arg) {
    final escaped = arg.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}').replaceAll('%', '%%');
    return '"$escaped"';
  }

  /// Тека робочого столу: `xdg-user-dir DESKTOP`, інакше `~/Desktop`; null — її немає.
  static Future<Directory?> desktopDir() async {
    final home = Platform.environment['HOME'];
    String? path;
    try {
      final r = await Process.run('xdg-user-dir', ['DESKTOP']);
      if (r.exitCode == 0) path = (r.stdout as String).trim();
    } on ProcessException {
      // xdg-user-dirs не встановлено
    }
    if ((path == null || path.isEmpty || path == home) && home != null) path = p.join(home, 'Desktop');
    if (path == null) return null;
    final dir = Directory(path);
    return dir.existsSync() ? dir : null;
  }

  /// Пише ярлик на робочий стіл. false — не вдалося (немає теки робочого столу чи не записалось).
  static Future<bool> createShortcut({required String target, required String name}) async {
    final dir = await desktopDir();
    if (dir == null) return false;
    final file = File(p.join(dir.path, 'mhrd-${_safe(name)}.desktop'));
    try {
      await file.writeAsString(entry(exe: executable, target: target, name: name, icon: await _installIcon()));
      // Стільниці запускають лише виконувані ярлики; GNOME ще й питає «довіряти?», доки немає позначки.
      await Process.run('chmod', ['+x', file.path]);
      try {
        await Process.run('gio', ['set', file.path, 'metadata::trusted', 'true']);
      } on ProcessException {
        // не GNOME — позначка не потрібна
      }
      return true;
    } on FileSystemException {
      return false;
    } on ProcessException {
      return true; // файл є; chmod недоступний — стільниця спитає сама
    }
  }

  static const iconName = 'ua.mhrd.mhrd';

  /// Копіює піктограму в теку піктограм користувача (файл усередині AppImage зникає разом із ним):
  /// ярлик посилається на неї за назвою. null — піктограми немає.
  static Future<String?> _installIcon() async {
    final src = File(p.join(p.dirname(Platform.resolvedExecutable), 'mhrd.png'));
    final data = Platform.environment['XDG_DATA_HOME'] ??
        (Platform.environment['HOME'] == null ? null : p.join(Platform.environment['HOME']!, '.local', 'share'));
    if (!src.existsSync() || data == null) return null;
    try {
      final dst = File(p.join(data, 'icons', 'hicolor', '256x256', 'apps', '$iconName.png'));
      await dst.parent.create(recursive: true);
      await src.copy(dst.path);
      return iconName;
    } on FileSystemException {
      return null;
    }
  }

  static String _safe(String name) {
    final s = name.replaceAll(RegExp(r'[^\p{L}\p{N}._-]+', unicode: true), '-').replaceAll(RegExp(r'-+'), '-');
    final t = s.replaceAll(RegExp(r'^[-.]+|-+$'), '');
    return t.isEmpty ? 'pc' : (t.length > 60 ? t.substring(0, 60) : t);
  }
}
