import 'dart:io';

import 'package:path/path.dart' as p;

import 'rdp_session.dart';

/// Журнал сеансів (SPEC → «Журнал»): по файлу на день, лишаються останні 7 днів.
/// Запис: час, ПК, причина й код відключення, журнал FreeRDP із stderr процесу.
/// Паролів там немає: пароль іде лише в stdin, а FreeRDP його не журналює.
class SessionLog {
  SessionLog(this.dir, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Directory dir;
  final DateTime Function() _clock;

  static const keepDays = 7;

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _day(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

  File fileFor(DateTime t) => File(p.join(dir.path, 'session-${_day(t)}.log'));

  Future<void> write(RdpSession s) async {
    final now = _clock();
    final c = s.connection;
    final e = s.ended;
    final time = '${_day(now)} ${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
    final reason = e == null ? '-' : '${e.reason.name} 0x${e.code.toRadixString(16)}';
    final log = s.engineLog.trim();
    final text = StringBuffer('=== $time  ${c.displayName} (${c.host}:${c.port})  $reason\n');
    if (e != null && e.details.isNotEmpty && !log.contains(e.details)) text.writeln(e.details);
    if (log.isNotEmpty) text.writeln(log);
    try {
      await dir.create(recursive: true);
      await fileFor(now).writeAsString('$text\n', mode: FileMode.append, flush: true);
      await _prune(now);
    } on FileSystemException {
      // журнал — допомога в діагностиці; без нього сеанс і застосунок працюють так само
    }
  }

  Future<void> _prune(DateTime now) async {
    final oldest = _day(now.subtract(const Duration(days: keepDays - 1)));
    await for (final f in dir.list()) {
      final name = p.basename(f.path);
      final m = RegExp(r'^session-(\d{4}-\d{2}-\d{2})\.log$').firstMatch(name);
      if (f is File && m != null && m.group(1)!.compareTo(oldest) < 0) await f.delete();
    }
  }
}
