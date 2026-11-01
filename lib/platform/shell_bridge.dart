import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/connection.dart';

/// Зв'язок з оболонкою Windows (windows/runner/shell_integration.cpp): список «Недавні» на
/// значку MHRD у панелі завдань і «підключитись до ПК», коли його вибрали в цьому списку.
class ShellBridge {
  ShellBridge._() {
    if (Platform.isWindows) _channel.setMethodCallHandler(_onCall);
  }

  static final instance = ShellBridge._();
  static const _channel = MethodChannel('mhrd/shell');

  /// id ПК, до якого просять підключитись (з аргументів запуску чи від другої копії MHRD).
  final pendingConnect = ValueNotifier<String?>(null);

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

  /// Оновлює «Недавні» на значку, лише якщо список змінився.
  Future<void> setRecent(String category, List<Connection> pcs) async {
    if (!Platform.isWindows) return;
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
