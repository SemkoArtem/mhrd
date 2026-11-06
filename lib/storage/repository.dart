import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/connection.dart';
import '../models/entities.dart';
import '../theme/mhrd_theme.dart';
import 'database.dart';
import 'secret_store.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

enum InUseKind { credential, gateway, tunnel, proxy }

/// Що саме посилається на об'єкт, який збираються видалити. Текст складає UI (переклади).
class InUse implements Exception {
  InUse(this.kind, {this.pcs = const [], this.gateways = const []});
  final InUseKind kind;

  /// Назви ПК і шлюзів, що використовують об'єкт.
  final List<String> pcs;
  final List<String> gateways;

  @override
  String toString() => 'InUse(${kind.name}): ${[...pcs, ...gateways].join(', ')}';
}

/// Спроба вкласти групу саму в себе (напряму чи через інші групи).
class GroupCycleError extends StateError {
  GroupCycleError() : super('group cycle');
}

/// Єдине джерело правди для UI. Тримає все в пам'яті, пише в SQLite одразу.
class Repository extends ChangeNotifier {
  Repository(this.db, this.secrets) {
    _load();
    orphansCleaned = _deleteOrphanSecrets();
  }

  /// Завершується, коли видалено секрети, що лишились після міграції бази (див. [MhrdDatabase]).
  late final Future<void> orphansCleaned;

  Future<void> _deleteOrphanSecrets() async {
    final raw = db.getMeta(MhrdDatabase.orphanSecretsKey);
    if (raw == null) return;
    for (final key in (jsonDecode(raw) as List).whereType<String>()) {
      await secrets.delete(key);
    }
    db.deleteMeta(MhrdDatabase.orphanSecretsKey);
  }

  final MhrdDatabase db;
  final SecretStore secrets;

  static const kConnection = 'connection';
  static const kCredential = 'credential';
  static const kGroup = 'group';
  static const kGateway = 'gateway';
  static const kTunnel = 'tunnel';
  static const kProxy = 'proxy';
  static const kTheme = 'theme';

  final Map<String, Connection> connections = {};
  final Map<String, Credential> credentials = {};
  final Map<String, Group> groups = {};
  final Map<String, Gateway> gateways = {};
  final Map<String, TunnelProfile> tunnels = {};
  final Map<String, ProxyProfile> proxies = {};
  final Map<String, MhrdTokens> customThemes = {};
  AppSettings settings = const AppSettings();

  void _load() {
    for (final j in db.all(kConnection)) {
      final c = Connection.fromJson(j);
      connections[c.id] = c;
    }
    for (final j in db.all(kCredential)) {
      final c = Credential.fromJson(j);
      credentials[c.id] = c;
    }
    for (final j in db.all(kGroup)) {
      final g = Group.fromJson(j);
      groups[g.id] = g;
    }
    for (final j in db.all(kGateway)) {
      final g = Gateway.fromJson(j);
      gateways[g.id] = g;
    }
    for (final j in db.all(kTunnel)) {
      final t = TunnelProfile.fromJson(j);
      tunnels[t.id] = t;
    }
    for (final j in db.all(kProxy)) {
      final p = ProxyProfile.fromJson(j);
      proxies[p.id] = p;
    }
    for (final j in db.all(kTheme)) {
      try {
        final t = MhrdTokens.fromJson(j);
        customThemes[t.id] = t;
      } on FormatException {
        // пошкоджена тема — пропускаємо, решта працює
      }
    }
    final s = db.getMeta('settings');
    if (s != null) settings = AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  // ── Тема ────────────────────────────────────────────────────────

  MhrdTokens themeFor(Brightness platform) {
    if (settings.themeId == 'system') {
      return platform == Brightness.light ? MhrdTokens.light : MhrdTokens.graphite;
    }
    for (final t in MhrdTokens.builtIns) {
      if (t.id == settings.themeId) return t;
    }
    return customThemes[settings.themeId] ?? MhrdTokens.graphite;
  }

  void saveTheme(MhrdTokens t) {
    db.put(kTheme, t.id, t.toJson());
    customThemes[t.id] = t;
    notifyListeners();
  }

  void deleteTheme(String id) {
    db.delete(kTheme, id);
    customThemes.remove(id);
    if (settings.themeId == id) updateSettings(settings.copyWith(themeId: 'graphite'));
    notifyListeners();
  }

  // ── Налаштування ────────────────────────────────────────────────

  void updateSettings(AppSettings s) {
    settings = s;
    db.setMeta('settings', jsonEncode(s.toJson()));
    notifyListeners();
  }

  // ── ПК ──────────────────────────────────────────────────────────

  void saveConnection(Connection c) {
    final saved = c.copyWith(updatedAt: DateTime.now());
    db.put(kConnection, saved.id, saved.toJson());
    connections[saved.id] = saved;
    notifyListeners();
  }

  /// Новий (ще не збережений) ПК із «Налаштуваннями нових ПК» ([AppSettings.newPc]): маршрут, акаунти,
  /// екран, пристрої. Акаунти й профілі, яких уже немає, не переносяться.
  Connection newConnection({String host = '', int port = 3389, String name = '', String? groupId}) {
    final now = DateTime.now();
    final base = Connection(id: newId(), name: name, host: host, port: port, groupId: groupId, createdAt: now, updatedAt: now);
    final t = settings.newPc;
    if (t == null) return base;
    final routeOk = switch (t.route) {
      RouteKind.direct => true,
      RouteKind.tunnel => tunnels.containsKey(t.routeRefId),
      RouteKind.proxy => proxies.containsKey(t.routeRefId),
    };
    return base.copyWith(
      tags: t.tags,
      credentialIds: t.credentialIds.where(credentials.containsKey).toList(),
      route: routeOk ? t.route : RouteKind.direct,
      routeRefId: () => routeOk ? t.routeRefId : null,
      gatewayId: () => gateways.containsKey(t.gatewayId) ? t.gatewayId : null,
      gatewayBypassLocal: t.gatewayBypassLocal,
      adminSession: t.adminSession,
      swapMouseButtons: t.swapMouseButtons,
      reconnectOnDrop: t.reconnectOnDrop,
      display: t.display,
      devices: t.devices,
    );
  }

  /// [name] — назва копії (UI передає перекладене «… (копія)»).
  Connection duplicateConnection(Connection c, {required String name}) {
    final now = DateTime.now();
    final copy = c.copyWith(
      id: newId(),
      name: name,
      certPin: () => null,
      lastUsed: () => null,
      createdAt: now,
      updatedAt: now,
    );
    saveConnection(copy);
    return copy;
  }

  /// Переносить ПК у групу ([groupId] null — «Без групи») одним записом у базу.
  void moveConnections(Iterable<String> ids, String? groupId) {
    final now = DateTime.now();
    final moved = [
      for (final id in ids)
        if (connections[id] case final c? when c.groupId != groupId) c.copyWith(groupId: () => groupId, updatedAt: now),
    ];
    if (moved.isEmpty) return;
    db.transaction(() {
      for (final c in moved) {
        db.put(kConnection, c.id, c.toJson());
      }
    });
    for (final c in moved) {
      connections[c.id] = c;
    }
    notifyListeners();
  }

  void deleteConnections(Iterable<String> ids) {
    final list = ids.toList();
    db.transaction(() {
      for (final id in list) {
        db.delete(kConnection, id);
      }
    });
    for (final id in list) {
      connections.remove(id);
    }
    notifyListeners();
  }

  void markUsed(String id) {
    final c = connections[id];
    if (c == null) return;
    saveConnection(c.copyWith(lastUsed: () => DateTime.now()));
  }

  // ── Облікові записи ─────────────────────────────────────────────

  Future<void> saveCredential(Credential c, {String? password}) async {
    await _writeSecret(c.secretKey, password);
    db.put(kCredential, c.id, c.toJson());
    credentials[c.id] = c;
    notifyListeners();
  }

  /// Видаляє акаунт. Якщо його використовують ПК чи шлюзи і [force] = false,
  /// кидає [InUse] зі списком, щоб UI спитав підтвердження.
  Future<void> deleteCredential(String id, {bool force = false}) async {
    final pcs = connections.values.where((c) => c.credentialIds.contains(id)).map((c) => c.displayName).toList();
    final gws = gateways.values.where((g) => g.credentialId == id).map((g) => g.label).toList();
    if ((pcs.isNotEmpty || gws.isNotEmpty) && !force) throw InUse(InUseKind.credential, pcs: pcs, gateways: gws);
    final cred = credentials[id];
    db.transaction(() {
      for (final c in connections.values.where((c) => c.credentialIds.contains(id)).toList()) {
        final upd = c.copyWith(credentialIds: c.credentialIds.where((x) => x != id).toList());
        db.put(kConnection, upd.id, upd.toJson());
        connections[upd.id] = upd;
      }
      db.delete(kCredential, id);
    });
    credentials.remove(id);
    if (cred != null) await secrets.delete(cred.secretKey);
    notifyListeners();
  }

  // ── Групи ───────────────────────────────────────────────────────

  /// Зберігає групу; не дає зробити цикл у вкладеності.
  void saveGroup(Group g) {
    var p = g.parentId;
    final seen = <String>{g.id};
    while (p != null) {
      if (!seen.add(p)) throw GroupCycleError();
      p = groups[p]?.parentId;
    }
    db.put(kGroup, g.id, g.toJson());
    groups[g.id] = g;
    notifyListeners();
  }

  /// Видаляє групу; її ПК і підгрупи переходять у [moveTo] (null = «Збережені ПК»).
  void deleteGroup(String id, {String? moveTo}) {
    db.transaction(() {
      for (final c in connections.values.where((c) => c.groupId == id).toList()) {
        final upd = c.copyWith(groupId: () => moveTo);
        db.put(kConnection, upd.id, upd.toJson());
        connections[upd.id] = upd;
      }
      for (final g in groups.values.where((g) => g.parentId == id).toList()) {
        final upd = g.copyWith(parentId: () => moveTo);
        db.put(kGroup, upd.id, upd.toJson());
        groups[upd.id] = upd;
      }
      db.delete(kGroup, id);
    });
    groups.remove(id);
    notifyListeners();
  }

  // ── Маршрути ────────────────────────────────────────────────────

  void saveGateway(Gateway g) {
    db.put(kGateway, g.id, g.toJson());
    gateways[g.id] = g;
    notifyListeners();
  }

  void deleteGateway(String id, {bool force = false}) {
    final users = connections.values.where((c) => c.gatewayId == id).map((c) => c.displayName).toList();
    if (users.isNotEmpty && !force) throw InUse(InUseKind.gateway, pcs: users);
    db.transaction(() {
      for (final c in connections.values.where((c) => c.gatewayId == id).toList()) {
        final upd = c.copyWith(gatewayId: () => null);
        db.put(kConnection, upd.id, upd.toJson());
        connections[upd.id] = upd;
      }
      db.delete(kGateway, id);
    });
    gateways.remove(id);
    notifyListeners();
  }

  Future<void> saveTunnel(TunnelProfile t, {Map<String, String> secretValues = const {}}) async {
    for (final e in secretValues.entries) {
      await secrets.write(t.secretKey(e.key), e.value);
    }
    db.put(kTunnel, t.id, t.toJson());
    tunnels[t.id] = t;
    notifyListeners();
  }

  /// Налаштування WireGuard для mhrd-tunnel разом із ключами зі сховища — лише для stdin тунелю.
  Future<Map<String, Object?>> wireGuardConfig(TunnelProfile t) async {
    final wg = <String, Object?>{...t.config}..remove('extraPeersIgnored');
    for (final f in t.secretFields) {
      wg[f] = await secrets.read(t.secretKey(f)) ?? '';
    }
    return wg;
  }

  Future<void> deleteTunnel(String id, {bool force = false}) async {
    final t = tunnels[id];
    _deleteRoute(InUseKind.tunnel, RouteKind.tunnel, kTunnel, id, force);
    tunnels.remove(id);
    if (t != null) {
      for (final f in t.secretFields) {
        await secrets.delete(t.secretKey(f));
      }
    }
    notifyListeners();
  }

  Future<void> saveProxy(ProxyProfile p, {String? password}) async {
    await _writeSecret(p.secretKey, password);
    db.put(kProxy, p.id, p.toJson());
    proxies[p.id] = p;
    notifyListeners();
  }

  Future<void> deleteProxy(String id, {bool force = false}) async {
    final p = proxies[id];
    _deleteRoute(InUseKind.proxy, RouteKind.proxy, kProxy, id, force);
    proxies.remove(id);
    if (p != null) await secrets.delete(p.secretKey);
    notifyListeners();
  }

  /// null = не змінювати, порожній рядок = видалити, інакше записати.
  Future<void> _writeSecret(String key, String? value) async {
    if (value == null) return;
    if (value.isEmpty) {
      await secrets.delete(key);
    } else {
      await secrets.write(key, value);
    }
  }

  /// Спільне для тунелів і проксі: якщо профіль використовують ПК і [force] = false,
  /// кидає [InUse]; інакше переводить ці ПК на «Напряму» і видаляє запис — атомарно.
  void _deleteRoute(InUseKind what, RouteKind kind, String dbKind, String id, bool force) {
    final users = connections.values.where((c) => c.route == kind && c.routeRefId == id).toList();
    if (users.isNotEmpty && !force) throw InUse(what, pcs: users.map((c) => c.displayName).toList());
    db.transaction(() {
      for (final c in users) {
        final upd = c.copyWith(route: RouteKind.direct, routeRefId: () => null);
        db.put(kConnection, upd.id, upd.toJson());
        connections[upd.id] = upd;
      }
      db.delete(dbKind, id);
    });
  }

  // ── Підрахунки для UI ───────────────────────────────────────────

  /// Скільки ПК у групі (без підгруп). null = «Збережені ПК» (без групи).
  int countInGroup(String? groupId) => connections.values.where((c) => c.groupId == groupId).length;

  /// Скільки ПК використовують маршрут/тунель.
  int usersOfTunnel(String id) => connections.values.where((c) => c.routeRefId == id).length;
}
