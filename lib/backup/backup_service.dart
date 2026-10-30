import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/connection.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';

/// Два види експорту (SPEC.md → «Безпека, бекап і відновлення»):
///  * повний бекап `.rdpbackup` — усе, з паролями й ключами, зашифровано паролем бекапу;
///  * експорт для передачі `.json` — вибрані ПК без жодного секрету.
///
/// Формат `.rdpbackup` v2:
///   "RDPB2" | memKiB (u32 BE) | iterations (u8) | parallelism (u8) | salt (16) | nonce (12) | tag (16) | шифротекст
/// Ключ — Argon2id(пароль, salt); шифр — AES-256-GCM; AAD — усі байти до tag.
/// Також читається формат v1 ("RDPB1", PBKDF2-SHA256 600 000) з першої Windows-версії.
class BackupService {
  BackupService(this.repo, {this.memKiB = 65536, this.iterations = 3, this.parallelism = 1});

  final Repository repo;

  /// Параметри Argon2id. Типово 64 МБ, 3 ітерації, 1 потік. Тести можуть зменшити.
  final int memKiB;
  final int iterations;
  final int parallelism;

  static final _magic2 = ascii.encode('RDPB2');
  static final _magic1 = ascii.encode('RDPB1');
  static const _saltLen = 16, _nonceLen = 12, _tagLen = 16;

  // ── Повний бекап ────────────────────────────────────────────────

  /// Збирає всі дані разом із секретами (лише в пам'яті, лише для шифрування).
  Future<Map<String, dynamic>> collect() async {
    Future<String?> sec(String key) => repo.secrets.read(key);
    return {
      'schemaVersion': 1,
      'kind': 'mhrd-backup',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'connections': repo.connections.values.map((c) => c.toJson()).toList(),
      'credentials': [
        for (final c in repo.credentials.values) {...c.toJson(), 'password': await sec(c.secretKey)},
      ],
      'groups': repo.groups.values.map((g) => g.toJson()).toList(),
      'gateways': repo.gateways.values.map((g) => g.toJson()).toList(),
      'tunnels': [
        for (final t in repo.tunnels.values)
          {
            ...t.toJson(),
            'secrets': {for (final f in t.secretFields) f: await sec(t.secretKey(f))},
          },
      ],
      'proxies': [
        for (final p in repo.proxies.values) {...p.toJson(), 'password': await sec(p.secretKey)},
      ],
      'ssh': [
        for (final s in repo.ssh.values) {...s.toJson(), 'secret': await sec(s.secretKey)},
      ],
      'themes': repo.customThemes.values.map((t) => t.toJson()).toList(),
      'settings': repo.settings.toJson(),
    };
  }

  Future<Uint8List> exportEncrypted(String password) async {
    if (password.isEmpty) throw ArgumentError('Порожній пароль бекапу');
    final plain = utf8.encode(jsonEncode(await collect()));
    final rnd = Random.secure();
    final salt = List<int>.generate(_saltLen, (_) => rnd.nextInt(256));
    final nonce = List<int>.generate(_nonceLen, (_) => rnd.nextInt(256));

    final header = BytesBuilder()
      ..add(_magic2)
      ..add((ByteData(4)..setUint32(0, memKiB)).buffer.asUint8List())
      ..addByte(iterations)
      ..addByte(parallelism)
      ..add(salt)
      ..add(nonce);
    final aad = header.toBytes();

    final key = await _argon2(password, salt, memKiB, iterations, parallelism);
    final box = await AesGcm.with256bits().encrypt(plain, secretKey: key, nonce: nonce, aad: aad);

    return (BytesBuilder()
          ..add(aad)
          ..add(box.mac.bytes)
          ..add(box.cipherText))
        .toBytes();
  }

  /// Розшифровує бекап v2 або v1. Кидає [FormatException] з людським текстом.
  Future<Map<String, dynamic>> decrypt(Uint8List file, String password) async {
    if (_startsWith(file, _magic2)) return _decryptV2(file, password);
    if (_startsWith(file, _magic1)) return _convertV1(await _decryptV1(file, password));
    throw const FormatException('Це не файл бекапу MHRD.');
  }

  Future<Map<String, dynamic>> _decryptV2(Uint8List f, String password) async {
    final headerLen = _magic2.length + 4 + 1 + 1 + _saltLen + _nonceLen;
    if (f.length < headerLen + _tagLen) throw const FormatException('Файл бекапу пошкоджено.');
    var o = _magic2.length;
    final mem = ByteData.sublistView(f, o, o + 4).getUint32(0);
    o += 4;
    final it = f[o++];
    final par = f[o++];
    if (mem < 8 || mem > 1048576 || it < 1 || par < 1) {
      throw const FormatException('Файл бекапу пошкоджено.');
    }
    final salt = f.sublist(o, o + _saltLen);
    o += _saltLen;
    final nonce = f.sublist(o, o + _nonceLen);
    o += _nonceLen;
    final aad = f.sublist(0, headerLen);
    final tag = f.sublist(headerLen, headerLen + _tagLen);
    final cipher = f.sublist(headerLen + _tagLen);

    final key = await _argon2(password, salt, mem, it, par);
    return _open(cipher, nonce, tag, key, aad);
  }

  Future<Map<String, dynamic>> _decryptV1(Uint8List f, String password) async {
    final headerLen = _magic1.length + _saltLen + _nonceLen + _tagLen;
    if (f.length < headerLen) throw const FormatException('Файл бекапу пошкоджено.');
    var o = _magic1.length;
    final salt = f.sublist(o, o + _saltLen);
    o += _saltLen;
    final nonce = f.sublist(o, o + _nonceLen);
    o += _nonceLen;
    final tag = f.sublist(o, o + _tagLen);
    final cipher = f.sublist(headerLen);
    final key = await _pbkdf2(password, salt);
    return _open(cipher, nonce, tag, key, _magic1);
  }

  Future<Map<String, dynamic>> _open(
      List<int> cipher, List<int> nonce, List<int> tag, SecretKey key, List<int> aad) async {
    final List<int> plain;
    try {
      plain = await AesGcm.with256bits()
          .decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(tag)), secretKey: key, aad: aad);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Невірний пароль або файл пошкоджено.');
    }
    final obj = jsonDecode(utf8.decode(plain));
    if (obj is! Map<String, dynamic>) throw const FormatException('Файл бекапу пошкоджено.');
    return obj;
  }

  // Виведення ключа займає секунди, тому йде в окремому ізоляті: інтерфейс не замерзає.
  // Методи статичні, щоб замикання не захопило `this` (репозиторій з базою не передати в ізолят).
  static Future<SecretKey> _argon2(String pw, List<int> salt, int mem, int it, int par) async =>
      SecretKey(await Isolate.run(() async {
        final k = await Argon2id(parallelism: par, memory: mem, iterations: it, hashLength: 32)
            .deriveKey(secretKey: SecretKey(utf8.encode(pw)), nonce: salt);
        return k.extractBytes();
      }));

  static Future<SecretKey> _pbkdf2(String pw, List<int> salt) async =>
      SecretKey(await Isolate.run(() async {
        final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256)
            .deriveKey(secretKey: SecretKey(utf8.encode(pw)), nonce: salt);
        return k.extractBytes();
      }));

  static bool _startsWith(List<int> b, List<int> prefix) {
    if (b.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[i] != prefix[i]) return false;
    }
    return true;
  }

  /// Перетворює дані першої Windows-версії (C#) у формат v2.
  Map<String, dynamic> _convertV1(Map<String, dynamic> v1) {
    final groups = <String, Map<String, dynamic>>{};
    final gateways = <String, Map<String, dynamic>>{};
    final creds = <Map<String, dynamic>>[];
    final conns = <Map<String, dynamic>>[];
    final now = DateTime.now().toIso8601String();
    for (final raw in (v1['Connections'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final c = raw.map((k, v) => MapEntry('$k', v));
      final groupName = (c['Group'] as String? ?? '').trim();
      String? groupId;
      if (groupName.isNotEmpty) {
        groupId = groups.putIfAbsent(groupName, () => {'id': newId(), 'name': groupName})['id'] as String;
      }
      final gwHost = (c['Gateway'] as String? ?? '').trim();
      String? gwId;
      if (gwHost.isNotEmpty) {
        gwId = gateways.putIfAbsent(gwHost, () => {'id': newId(), 'name': '', 'host': gwHost, 'port': 443})['id']
            as String;
      }
      final ids = <String>[];
      final accounts = (c['Accounts'] as List? ?? const []).whereType<Map>().toList();
      final def = (c['DefaultAccount'] as int? ?? 0).clamp(0, accounts.isEmpty ? 0 : accounts.length - 1);
      for (var i = 0; i < accounts.length; i++) {
        final a = accounts[i];
        final id = newId();
        creds.add({
          'id': id,
          'name': a['Name'] ?? '',
          'username': a['UserName'] ?? '',
          'authMode': 'savedPassword',
          'password': a['Secret'] ?? '',
        });
        if (i == def) {
          ids.insert(0, id);
        } else {
          ids.add(id);
        }
      }
      conns.add({
        'id': (c['Id'] as String?) ?? newId(),
        'name': c['Name'] ?? '',
        'host': c['Host'] ?? '',
        'port': c['Port'] ?? 3389,
        'groupId': groupId,
        'credentialIds': ids,
        'gatewayId': gwId,
        'display': {
          'startFullscreen': c['FullScreen'] == true,
          'useAllMonitors': c['MultiMonitor'] == true,
        },
        'devices': {
          'clipboard': c['RedirectClipboard'] != false,
          'folders': c['RedirectDrives'] == true
              ? [
                  {'name': 'Усі диски', 'path': '*', 'readOnly': false}
                ]
              : [],
        },
        'createdAt': now,
        'updatedAt': now,
      });
    }
    return {
      'schemaVersion': 1,
      'kind': 'mhrd-backup',
      'connections': conns,
      'credentials': creds,
      'groups': groups.values.toList(),
      'gateways': gateways.values.toList(),
    };
  }

  // ── Відновлення ─────────────────────────────────────────────────

  /// Що станеться при імпорті — для екрана попереднього перегляду.
  ImportPreview preview(Map<String, dynamic> data, {required bool replaceAll}) {
    final incoming = (data['connections'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m['id'])
        .whereType<String>()
        .toSet();
    final existing = repo.connections.keys.toSet();
    return ImportPreview(
      added: incoming.difference(existing).length,
      updated: incoming.intersection(existing).length,
      removed: replaceAll ? existing.difference(incoming).length : 0,
    );
  }

  /// Застосовує дані бекапу. replaceAll = спершу видалити все поточне.
  /// UI має зробити автоматичний бекап поточного стану ПЕРЕД викликом з replaceAll.
  Future<void> apply(Map<String, dynamic> data, {required bool replaceAll}) async {
    final v = data['schemaVersion'];
    if (data['kind'] != 'mhrd-backup' || v is! int) {
      throw const FormatException('Це не бекап MHRD.');
    }
    if (v > 1) {
      throw const FormatException('Бекап створено новішою версією MHRD. Оновіть застосунок.');
    }
    List<Map<String, dynamic>> list(String k) => (data[k] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.map((key, val) => MapEntry('$key', val)))
        .toList();

    if (replaceAll) {
      repo.deleteConnections(repo.connections.keys.toList());
      for (final id in repo.credentials.keys.toList()) {
        await repo.deleteCredential(id, force: true);
      }
      for (final id in repo.gateways.keys.toList()) {
        repo.deleteGateway(id, force: true);
      }
      for (final id in repo.tunnels.keys.toList()) {
        await repo.deleteTunnel(id, force: true);
      }
      for (final id in repo.proxies.keys.toList()) {
        await repo.deleteProxy(id, force: true);
      }
      for (final id in repo.ssh.keys.toList()) {
        await repo.deleteSsh(id, force: true);
      }
      for (final id in repo.customThemes.keys.toList()) {
        repo.deleteTheme(id);
      }
      for (final id in repo.groups.keys.toList()) {
        repo.deleteGroup(id);
      }
    }

    for (final j in list('groups')) {
      repo.saveGroup(Group.fromJson(j).copyWith(parentId: () => null));
    }
    // Друге коло: відновлюємо вкладеність, коли всі групи вже існують.
    for (final j in list('groups')) {
      final g = Group.fromJson(j);
      if (g.parentId != null && repo.groups.containsKey(g.parentId)) {
        try {
          repo.saveGroup(g);
        } on StateError {
          // цикл у файлі — залишаємо групу на верхньому рівні
        }
      }
    }
    for (final j in list('credentials')) {
      final pw = j['password'];
      await repo.saveCredential(Credential.fromJson(j), password: pw is String ? pw : null);
    }
    for (final j in list('gateways')) {
      repo.saveGateway(Gateway.fromJson(j));
    }
    for (final j in list('tunnels')) {
      final secrets = (j['secrets'] is Map)
          ? (j['secrets'] as Map).map((k, val) => MapEntry('$k', '${val ?? ''}'))
          : <String, String>{};
      secrets.removeWhere((_, val) => val.isEmpty);
      await repo.saveTunnel(TunnelProfile.fromJson(j), secretValues: secrets);
    }
    for (final j in list('proxies')) {
      final pw = j['password'];
      await repo.saveProxy(ProxyProfile.fromJson(j), password: pw is String ? pw : null);
    }
    for (final j in list('ssh')) {
      final sec = j['secret'];
      await repo.saveSsh(SshProfile.fromJson(j), secret: sec is String ? sec : null);
    }
    for (final j in list('themes')) {
      try {
        repo.saveTheme(MhrdTokens.fromJson(j));
      } on FormatException {
        // пропускаємо пошкоджену тему
      }
    }
    for (final j in list('connections')) {
      final c = Connection.fromJson(j);
      if (c.id.isEmpty || c.host.isEmpty) continue;
      // Посилання на те, чого немає, прибираємо, щоб ПК не «ламався» при запуску.
      repo.saveConnection(c.copyWith(
        credentialIds: c.credentialIds.where(repo.credentials.containsKey).toList(),
        groupId: () => repo.groups.containsKey(c.groupId) ? c.groupId : null,
        gatewayId: () => repo.gateways.containsKey(c.gatewayId) ? c.gatewayId : null,
      ));
    }
    if (data['settings'] is Map && replaceAll) {
      repo.updateSettings(AppSettings.fromJson(
          (data['settings'] as Map).map((k, val) => MapEntry('$k', val))));
    }
  }

  // ── Експорт для передачі (без секретів) ─────────────────────────

  Map<String, dynamic> exportShare(Iterable<Connection> selection) {
    final conns = selection.toList();
    final credIds = conns.expand((c) => c.credentialIds).toSet();
    final groupIds = conns.map((c) => c.groupId).whereType<String>().toSet();
    final gwIds = conns.map((c) => c.gatewayId).whereType<String>().toSet();
    return {
      'schemaVersion': 1,
      'kind': 'mhrd-share',
      'secretIncluded': false,
      'connections': conns.map((c) => c.copyWith(certPin: () => null).toJson()).toList(),
      'credentials': repo.credentials.values
          .where((c) => credIds.contains(c.id))
          .map((c) => {...c.toJson(), 'authMode': AuthMode.askPassword.name})
          .toList(),
      'groups': repo.groups.values.where((g) => groupIds.contains(g.id)).map((g) => g.toJson()).toList(),
      'gateways': repo.gateways.values.where((g) => gwIds.contains(g.id)).map((g) => g.toJson()).toList(),
    };
  }

  /// Імпорт файлу «для передачі»: те саме, що apply у режимі об'єднання, але без секретів.
  Future<void> importShare(Map<String, dynamic> data) async {
    if (data['kind'] != 'mhrd-share') throw const FormatException('Це не файл експорту MHRD.');
    await apply({...data, 'kind': 'mhrd-backup'}, replaceAll: false);
  }
}

class ImportPreview {
  const ImportPreview({required this.added, required this.updated, required this.removed});
  final int added;
  final int updated;
  final int removed;
}
