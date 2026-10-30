import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Локальна база MHRD: одна таблиця сутностей у JSON + таблиця метаданих.
/// Простий формат без кодогенерації; міграції — за `schemaVersion` у `meta`.
/// Кожен запис іде в транзакції, тож вимкнення живлення не псує базу (WAL).
class MhrdDatabase {
  MhrdDatabase._(this._db);

  static const schemaVersion = 1;

  final Database _db;

  /// Відкриває (або створює) базу у вказаній теці.
  static MhrdDatabase open(Directory dir) {
    dir.createSync(recursive: true);
    final db = sqlite3.open(p.join(dir.path, 'mhrd.sqlite3'));
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    final m = MhrdDatabase._(db);
    m._migrate();
    return m;
  }

  /// База в пам'яті — для тестів.
  static MhrdDatabase inMemory() {
    final m = MhrdDatabase._(sqlite3.openInMemory());
    m._migrate();
    return m;
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS entities (
        kind TEXT NOT NULL,
        id TEXT NOT NULL,
        json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (kind, id)
      );
    ''');
    final current = int.tryParse(getMeta('schemaVersion') ?? '') ?? 0;
    if (current > schemaVersion) {
      throw StateError(
          'База створена новішою версією MHRD (схема $current). Оновіть застосунок.');
    }
    // Тут з'являтимуться кроки міграції: if (current < 2) {...}
    setMeta('schemaVersion', '$schemaVersion');
  }

  String? getMeta(String key) {
    final r = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setMeta(String key, String value) {
    _db.execute(
        'INSERT INTO meta(key, value) VALUES(?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value]);
  }

  List<Map<String, dynamic>> all(String kind) {
    final rows = _db.select('SELECT json FROM entities WHERE kind = ?', [kind]);
    return rows
        .map((r) => jsonDecode(r['json'] as String))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  void put(String kind, String id, Map<String, dynamic> json) {
    _db.execute(
        'INSERT INTO entities(kind, id, json, updated_at) VALUES(?, ?, ?, ?) '
        'ON CONFLICT(kind, id) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at',
        [kind, id, jsonEncode(json), DateTime.now().toUtc().toIso8601String()]);
  }

  void delete(String kind, String id) {
    _db.execute('DELETE FROM entities WHERE kind = ? AND id = ?', [kind, id]);
  }

  /// Виконує кілька змін атомарно: або всі, або жодної.
  void transaction(void Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.dispose();
}
