import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/json_util.dart';
import '../storage/repository.dart';
import 'backup_service.dart';

enum AutoBackupFailureKind { writeFailed, noPassword, other }

/// Чому остання спроба не вдалася; текст для людей складає UI (переклади).
class AutoBackupFailure {
  const AutoBackupFailure(this.kind, {this.path = '', this.detail = ''});
  final AutoBackupFailureKind kind;
  final String path;
  final String detail;
}

/// Автобекап (SPEC → «Безпека, бекап і відновлення»): після змін, не частіше разу на годину,
/// у вибрану теку (наприклад, синхронізовану з хмарою); зберігаються останні [keep] копій.
///
/// Налаштування лише для цього пристрою (meta `autoBackup`), тому не потрапляють у бекап:
/// шлях з Windows на Android не має сенсу. Пароль — у системному сховищі.
class AutoBackup extends ChangeNotifier {
  AutoBackup(
    this.repo, {
    BackupService? service,
    this.minInterval = const Duration(hours: 1),
    this.debounce = const Duration(seconds: 10),
    this.keep = 10,
  }) : _service = service ?? BackupService(repo) {
    _load();
    repo.addListener(_onRepoChanged);
    // Зміни, які не встигли потрапити в копію до закриття програми.
    if (enabled && _pending) _schedule();
  }

  static const _metaKey = 'autoBackup';
  static const passwordKey = 'mhrd.autobackup.password';

  /// Копії автобекапу: `mhrd-auto-<пристрій>-ДАТА-ЧАС.rdpbackup` (старі версії — без пристрою).
  static final fileNamePattern = RegExp(r'^mhrd-auto-(?:[a-z0-9-]+-)?\d{8}-\d{6}\.rdpbackup$');

  /// Цей пристрій і ця копія MHRD у назві файлу: ім'я комп'ютера + короткий код (встановлена й
  /// портативна на одному ПК — різні). У спільній (хмарній) теці кожен прибирає лише свої копії —
  /// інакше частіший пристрій видаляв би бекапи іншого.
  @visibleForTesting
  late final String deviceTag = () {
    var id = repo.db.getMeta(_deviceKey);
    if (id == null || !RegExp(r'^[0-9a-f]{4}$').hasMatch(id)) {
      final r = Random.secure();
      id = List.generate(4, (_) => r.nextInt(16).toRadixString(16)).join();
      repo.db.setMeta(_deviceKey, id);
    }
    var host = '';
    try {
      host = Platform.localHostname.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    } catch (_) {
      // без імені — лише код
    }
    host = host.replaceAll(RegExp(r'^-+|-+$'), '');
    if (host.length > 24) host = host.substring(0, 24).replaceAll(RegExp(r'-+$'), '');
    return host.isEmpty ? id : '$host-$id';
  }();

  static const _deviceKey = 'autoBackupDevice';

  final Repository repo;
  final BackupService _service;
  final Duration minInterval;
  final Duration debounce;
  final int keep;

  String? _dir;
  DateTime? _lastAt;
  DateTime? _lastAttemptAt;
  bool _pending = false;
  AutoBackupFailure? _lastError;
  Timer? _timer;
  bool _running = false;

  /// Тека для копій; null = автобекап вимкнено.
  String? get dir => _dir;
  bool get enabled => _dir != null;
  DateTime? get lastAt => _lastAt;
  AutoBackupFailure? get lastError => _lastError;

  /// Є зміни, яких ще немає в жодній копії.
  bool get pending => _pending;

  void _load() {
    final raw = repo.db.getMeta(_metaKey);
    if (raw == null) return;
    final j = mapOr(jsonDecode(raw));
    _dir = strOrNull(j['dir']);
    _lastAt = dateOrNull(j['lastAt']);
    _pending = boolOr(j['pending'], false);
  }

  void _save() => repo.db.setMeta(
      _metaKey, jsonEncode({'dir': _dir, 'lastAt': _lastAt?.toIso8601String(), 'pending': _pending}));

  /// Вмикає (або змінює теку й пароль) і одразу робить першу копію.
  /// Повертає шлях до копії або null — тоді причина в [lastError].
  Future<String?> enable(String dir, String password) async {
    await repo.secrets.write(passwordKey, password);
    _dir = dir;
    _pending = true;
    _lastAttemptAt = null;
    _save();
    notifyListeners();
    return runNow();
  }

  /// Вимикає й стирає пароль. Уже зроблені копії лишаються в теці.
  Future<void> disable() async {
    _timer?.cancel();
    _dir = null;
    _pending = false;
    _lastError = null;
    _save();
    await repo.secrets.delete(passwordKey);
    notifyListeners();
  }

  void _onRepoChanged() {
    if (!enabled) return;
    if (!_pending) {
      _pending = true;
      _save();
    }
    _schedule();
  }

  /// Скільки чекати до наступної копії: щонайменше [debounce] (щоб зібрати серію змін в одну
  /// копію) і не раніше ніж через [minInterval] після попередньої спроби — вдалої чи ні.
  @visibleForTesting
  Duration delayFrom(DateTime now) {
    final last = [_lastAt, _lastAttemptAt].whereType<DateTime>().fold<DateTime?>(
        null, (a, b) => a == null || b.isAfter(a) ? b : a);
    if (last == null) return debounce;
    final left = last.add(minInterval).difference(now);
    return left > debounce ? left : debounce;
  }

  void _schedule() {
    if (_timer?.isActive ?? false) return;
    _timer = Timer(delayFrom(DateTime.now()), () {
      if (_pending) runNow();
    });
  }

  /// Робить копію зараз. Повертає шлях до файлу або null, якщо не вдалося (текст у [lastError]).
  Future<String?> runNow() async {
    final dir = _dir;
    if (dir == null || _running) return null;
    _running = true;
    _timer?.cancel();
    _pending = false; // зміни під час запису знову виставлять прапорець
    final now = DateTime.now();
    _lastAttemptAt = now;
    try {
      final pw = await repo.secrets.read(passwordKey);
      if (pw == null || pw.isEmpty) throw const _NoPassword();
      final bytes = await _service.exportEncrypted(pw);
      final file = File(p.join(dir, 'mhrd-auto-$deviceTag-${_stamp(now)}.rdpbackup'));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      _lastAt = now;
      _lastError = null;
      _prune(dir);
      return file.path;
    } catch (e) {
      _pending = true;
      _lastError = switch (e) {
        FileSystemException(:final path, :final osError, :final message) => AutoBackupFailure(
            AutoBackupFailureKind.writeFailed,
            path: path ?? dir,
            detail: osError?.message ?? message),
        _NoPassword() => const AutoBackupFailure(AutoBackupFailureKind.noPassword),
        _ => AutoBackupFailure(AutoBackupFailureKind.other, detail: '$e'),
      };
      return null;
    } finally {
      _running = false;
      _save();
      notifyListeners();
      if (_pending && enabled) _schedule();
    }
  }

  /// Лишає [keep] найновіших копій цього пристрою (чужі й старі, без пристрою в назві, не чіпає).
  /// Імена містять дату, тож сортування за іменем = за часом.
  void _prune(String dir) {
    final own = 'mhrd-auto-$deviceTag-';
    final files = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = p.basename(f.path);
          return name.startsWith(own) && fileNamePattern.hasMatch(name);
        })
        .toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final f in files.skip(keep)) {
      try {
        f.deleteSync();
      } on FileSystemException {
        // файл міг заблокувати клієнт хмари — спробуємо наступного разу
      }
    }
  }

  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    repo.removeListener(_onRepoChanged);
    super.dispose();
  }
}

class _NoPassword implements Exception {
  const _NoPassword();
}
