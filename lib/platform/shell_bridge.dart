import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/connection.dart';
import '../models/entities.dart';
import 'linux_desktop.dart';
import 'portable.dart';

/// Зв'язок з оболонкою Windows (windows/runner/shell_integration.cpp) і Linux (linux/runner): список
/// «Недавні» на значку MHRD у панелі завдань (Windows), ярлики ПК і «підключитись до ПК» від ярлика
/// чи списку.
class ShellBridge {
  ShellBridge._() {
    if (Platform.isWindows || Platform.isLinux) _channel.setMethodCallHandler(_onCall);
  }

  static final instance = ShellBridge._();
  static const _channel = MethodChannel('mhrd/shell');

  /// id ПК, до якого просять підключитись (з аргументів запуску чи від другої копії MHRD).
  /// Ярлик окремого акаунта додає його id: `<ПК>/<акаунт>` — див. [parseConnectTarget].
  final pendingConnect = ValueNotifier<String?>(null);

  static const accountSeparator = '/';

  /// `<ПК>` або `<ПК>/<акаунт>` → (id ПК, id акаунта або null).
  static (String, String?) parseConnectTarget(String target) {
    final i = target.indexOf(accountSeparator);
    if (i < 0) return (target, null);
    final account = target.substring(i + 1);
    return (target.substring(0, i), account.isEmpty ? null : account);
  }

  String? _lastRecent;

  /// `mhrd.exe --connect <id>` — запуск зі списку «Недавні», коли MHRD ще не був відкритий.
  void handleArgs(List<String> args) {
    final i = args.indexOf('--connect');
    if (i >= 0 && i + 1 < args.length) pendingConnect.value = args[i + 1];
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'connect' && call.arguments is String) {
      pendingConnect.value = null; // той самий id вдруге — теж має спрацювати
      pendingConnect.value = call.arguments as String;
    }
  }

  /// Нещодавні ПК, найновіший перший — не більше [limit].
  static List<Connection> recent(Iterable<Connection> all, {int limit = 8}) =>
      (all.where((c) => c.lastUsed != null).toList()..sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!)))
          .take(limit)
          .toList();

  /// Екранна клавіатура Windows — на прохання вікна сеансу (йому запускати програми заборонено).
  Future<void> openKeyboard() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('openKeyboard');
    } on MissingPluginException {
      // не Windows-раннер MHRD
    } on PlatformException {
      // не відкрилась — нічого не вдієш
    }
  }

  /// Ярлик на робочому столі, що одразу підключає до ПК — акаунтом ПК за замовчуванням або [as]
  /// (тоді `--connect <ПК>/<акаунт>`). false — не вдалося.
  Future<bool> createShortcut(Connection c, {Credential? as}) async {
    final id = as == null ? c.id : '${c.id}$accountSeparator${as.id}';
    final name = as == null ? c.displayName : '${c.displayName} — ${as.label}';
    if (Platform.isLinux) return LinuxDesktop.createShortcut(target: id, name: name);
    if (!Platform.isWindows) return false;
    try {
      await _channel.invokeMethod('createShortcut', {'id': id, 'name': name});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Оновлює «Недавні» на значку, лише якщо список змінився. Портативна версія списку не веде:
  /// він лежав би в профілі Windows, а не поруч із програмою.
  Future<void> setRecent(String category, List<Connection> pcs) async {
    if (!Platform.isWindows || Portable.enabled) return;
    final items = [
      for (final c in pcs) {'id': c.id, 'title': c.displayName},
    ];
    final key = '$category|${items.map((e) => '${e['id']}=${e['title']}').join(';')}';
    if (key == _lastRecent) return;
    _lastRecent = key;
    try {
      await _channel.invokeMethod('setRecent', {'category': category, 'items': items});
    } on MissingPluginException {
      // не Windows-раннер MHRD (наприклад, тести)
    } on PlatformException {
      // список не оновився — не біда
    }
  }
}
