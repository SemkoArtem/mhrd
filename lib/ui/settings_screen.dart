import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../backup/auto_backup.dart';
import '../backup/backup_service.dart';
import '../l10n/l10n.dart';
import '../models/connection.dart';
import '../models/entities.dart';
import '../platform/portable.dart';
import '../security/app_lock.dart';
import '../sessions/route_health.dart' show probeProxy;
import '../sessions/session_manager.dart' show HealthState, RouteHealth, RouteStatus, TunnelError;
import '../storage/file_secret_store.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import '../util/address.dart';
import '../util/wireguard_conf.dart';
import 'credential_dialog.dart';
import 'edit_connection_screen.dart';
import 'dialogs.dart';
import 'file_actions.dart';
import 'lock_screen.dart';
import 'portable_gate.dart';
import 'theme_editor.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _section = 0; // телефон: вибраний розділ
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _menuShown = false; // телефон: меню розділів відкривається одразу при вході

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final repo = AppScope.of(context).repo;
    final sections = [
      (Icons.tune, l.tabGeneral, () => _GeneralTab(repo: repo)),
      (Icons.palette_outlined, l.tabTheme, () => const ThemeEditor()),
      (Icons.person_outline, l.accounts, () => _AccountsTab(repo: repo)),
      (Icons.alt_route, l.tabRoutes, () => _RoutesTab(repo: repo)),
      (Icons.folder_outlined, l.groups, () => _GroupsTab(repo: repo)),
      (Icons.add_to_queue, l.tabNewPcs, () => _ScreensTab(repo: repo)),
      (Icons.backup_outlined, l.tabBackup, () => _BackupTab(repo: repo)),
    ];
    // Телефон: сім вкладок у рядок не влазять — розділи в меню, що виїжджає зліва по кнопці «☰».
    if (MediaQuery.sizeOf(context).width < 600) {
      final (_, title, page) = sections[_section];
      if (!_menuShown) {
        _menuShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scaffold.currentState?.openDrawer());
      }
      return Scaffold(
        key: _scaffold,
        appBar: AppBar(backgroundColor: t.surface, title: Text(title)),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(children: [
              // Вгорі — на головний екран (список ПК), далі — розділи налаштувань.
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text(l.homeScreen),
                onTap: () {
                  Navigator.pop(context); // закрити меню
                  Navigator.maybePop(context); // вийти з налаштувань
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(l.settings,
                    style: TextStyle(fontFamily: t.fontMono, fontSize: 20, letterSpacing: 0.8, color: t.accent)),
              ),
              for (final (i, (icon, label, _)) in sections.indexed)
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  selected: i == _section,
                  onTap: () {
                    Navigator.pop(context); // закрити меню
                    setState(() => _section = i);
                  },
                ),
            ]),
          ),
        ),
        body: ListenableBuilder(listenable: repo, builder: (context, _) => page()),
      );
    }
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: t.surface,
          title: Text(l.settings),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l.tabGeneral),
              Tab(text: l.tabTheme),
              Tab(text: l.accounts),
              Tab(text: l.tabRoutes),
              Tab(text: l.groups),
              Tab(text: l.tabNewPcs),
              Tab(text: l.tabBackup),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: repo,
          builder: (context, _) => TabBarView(children: [
            _GeneralTab(repo: repo),
            const ThemeEditor(),
            _AccountsTab(repo: repo),
            _RoutesTab(repo: repo),
            _GroupsTab(repo: repo),
            _ScreensTab(repo: repo),
            _BackupTab(repo: repo),
          ]),
        ),
      ),
    );
  }
}

Widget _pane(List<Widget> children) => centeredList(children, maxWidth: 720);

Widget _caption(BuildContext context, String s) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(s, style: TextStyle(color: context.mhrd.textMuted, fontWeight: FontWeight.w600, fontSize: 13)),
    );

Future<void> _guardedDelete(BuildContext context, Future<void> Function(bool force) del) async {
  try {
    await del(false);
  } on InUse catch (e) {
    if (!context.mounted) return;
    final l = context.l10n;
    final ok = await confirm(context,
        title: l.inUseTitle(l.inUseKind(e.kind)), body: l.inUseBody(l.inUseUsers(e)), ok: l.delete, danger: true);
    if (ok) await del(true);
  }
}

// ── Загальні ──────────────────────────────────────────────────────

class _GeneralTab extends StatelessWidget {
  const _GeneralTab({required this.repo});
  final Repository repo;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = repo.settings;
    final mobile = Platform.isAndroid || Platform.isIOS;
    void set(AppSettings x) => repo.updateSettings(x);
    return _pane([
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<String>(
          initialValue: s.language,
          decoration: InputDecoration(labelText: l.language),
          // Назви мов — кожна своєю мовою, щоб знайти свою навіть у чужому інтерфейсі.
          items: [
            DropdownMenuItem(value: 'system', child: Text(l.languageSystem)),
            const DropdownMenuItem(value: 'uk', child: Text('Українська')),
            const DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (v) => set(s.copyWith(language: v)),
        ),
      ),
      const SizedBox(height: 12),
      // Телефон: сеанс і так на весь екран, мініатюр і перехоплення Win/Alt+Tab там немає.
      if (!mobile)
        SwitchListTile(
          value: s.startFullscreen,
          title: Text(l.startSessionsFullscreen),
          onChanged: (v) => set(s.copyWith(startFullscreen: v)),
        ),
      SwitchListTile(
        value: s.keepScreenAwake,
        title: Text(l.keepScreenAwake),
        onChanged: (v) => set(s.copyWith(keepScreenAwake: v)),
      ),
      if (Platform.isAndroid)
        SwitchListTile(
          value: s.backgroundSessions,
          title: Text(l.backgroundSessions),
          subtitle: Text(l.backgroundSessionsHint),
          onChanged: (v) => set(s.copyWith(backgroundSessions: v)),
        ),
      if (mobile)
        SwitchListTile(
          value: s.keyboardShiftsScreen,
          title: Text(l.keyboardShiftsScreen),
          onChanged: (v) => set(s.copyWith(keyboardShiftsScreen: v)),
        ),
      if (!mobile)
        SwitchListTile(
          value: s.showPreviews,
          title: Text(l.showPreviews),
          onChanged: (v) => set(s.copyWith(showPreviews: v)),
        ),
      if (!mobile) ...[
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<KeyboardCapture>(
            initialValue: s.keyboardCapture,
            decoration: InputDecoration(labelText: l.keyboardCapture),
            items: [
              DropdownMenuItem(value: KeyboardCapture.fullscreenOnly, child: Text(l.captureFullscreenOnly)),
              DropdownMenuItem(value: KeyboardCapture.always, child: Text(l.always)),
              DropdownMenuItem(value: KeyboardCapture.never, child: Text(l.never)),
            ],
            onChanged: (v) => set(s.copyWith(keyboardCapture: v)),
          ),
        ),
      ],
      if (repo.secrets case final FileSecretStore store) ...[
        // Портативна версія чи Linux без сховища паролів: замок — майстер-пароль файлу секретів,
        // PIN і Windows Hello не потрібні.
        _caption(context, Portable.enabled ? l.portableSection : l.keyringFallbackSection),
        ListTile(
          leading: Icon(Portable.enabled ? Icons.usb_outlined : Icons.key_outlined),
          title: Text(Portable.enabled ? l.portableSectionHint : l.keyringFallbackSectionHint),
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(l.masterPasswordChange),
          onTap: () async {
            if (!await confirmMasterPassword(context, store)) {
              if (context.mounted) toast(context, l.masterPasswordWrong);
              return;
            }
            if (!context.mounted) return;
            final pw = await askNewMasterPassword(context);
            if (pw == null) return;
            await store.changePassword(pw);
            if (context.mounted) toast(context, l.masterPasswordChanged);
          },
        ),
      ] else ...[
        _caption(context, l.lockSection),
        SwitchListTile(
          value: s.lockEnabled,
          title: Text(l.lockEnable),
          subtitle: Text(l.lockEnableHint),
          onChanged: (v) async {
            final lock = AppLock(repo);
            if (v) {
              final pin = await askNewPin(context);
              if (pin != null) await lock.setPin(pin);
            } else if (await confirmPin(context, lock)) {
              await lock.disable();
            } else if (context.mounted) {
              toast(context, l.pinWrong);
            }
          },
        ),
        if (s.lockEnabled)
          FutureBuilder<bool>(
            future: AppLock(repo).biometricAvailable(),
            builder: (context, snap) => snap.data != true
                ? const SizedBox.shrink()
                : SwitchListTile(
                    value: s.lockBiometric,
                    title: Text(Platform.isAndroid || Platform.isIOS ? l.lockBiometricPhone : l.lockBiometric),
                    onChanged: (v) async {
                      // Вмикаємо, лише якщо відбиток / Windows Hello справді спрацював.
                      if (v && !await AppLock(repo).unlockWithBiometric(l.lockReason)) return;
                      set(repo.settings.copyWith(lockBiometric: v));
                    },
                  ),
          ),
      ],
    ]);
  }
}

// ── Облікові записи ───────────────────────────────────────────────

class _AccountsTab extends StatelessWidget {
  const _AccountsTab({required this.repo});
  final Repository repo;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final list = repo.credentials.values.toList()..sort((a, b) => a.label.compareTo(b.label));
    return _pane([
      Text(l.accountsHint, style: TextStyle(color: t.textMuted)),
      const SizedBox(height: 12),
      for (final c in list)
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(c.label),
          subtitle: Text(
            '${c.authMode == AuthMode.askPassword ? l.askPassword : l.passwordSaved} · '
            '${l.pcCount(repo.connections.values.where((x) => x.credentialIds.contains(c.id)).length)}',
            style: TextStyle(color: t.textMuted, fontSize: 12.5),
          ),
          onTap: () => editCredential(context, repo, existing: c),
          trailing: IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) => repo.deleteCredential(c.id, force: force)),
          ),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          icon: const Icon(Icons.add),
          label: Text(l.addAccount),
          onPressed: () => editCredential(context, repo),
        ),
      ),
    ]);
  }
}

// ── Маршрути ──────────────────────────────────────────────────────

class _RoutesTab extends StatelessWidget {
  const _RoutesTab({required this.repo});
  final Repository repo;

  Future<void> _editGateway(BuildContext context, [Gateway? g]) async {
    final l = context.l10n;
    final name = TextEditingController(text: g?.name ?? '');
    final addr = TextEditingController(text: g == null ? '' : (g.port == 443 ? g.host : '${g.host}:${g.port}'));
    var mode = g?.credentialMode ?? GatewayCredentialMode.sameAsPc;
    var credId = g?.credentialId;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(g == null ? l.gatewayNew : l.gatewayTitle),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: addr,
                autofocus: g == null,
                decoration: InputDecoration(labelText: l.gatewayAddress, hintText: 'rdgw.example.com', errorText: err),
              ),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: InputDecoration(labelText: l.nameOptional)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode == GatewayCredentialMode.sameAsPc ? '' : (credId ?? ''),
                decoration: InputDecoration(labelText: l.gatewayAccount),
                items: [
                  DropdownMenuItem(value: '', child: Text(l.gatewaySameAsPc)),
                  for (final cr in repo.credentials.values) DropdownMenuItem(value: cr.id, child: Text(cr.label)),
                ],
                onChanged: (v) => set(() {
                  mode = (v == null || v.isEmpty) ? GatewayCredentialMode.sameAsPc : GatewayCredentialMode.own;
                  credId = (v == null || v.isEmpty) ? null : v;
                }),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
            FilledButton(
              onPressed: () {
                if (parseAddress(addr.text, defaultPort: 443) == null) {
                  set(() => err = l.invalidAddress);
                } else {
                  Navigator.pop(c, true);
                }
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final a = parseAddress(addr.text, defaultPort: 443)!;
    repo.saveGateway(Gateway(
      id: g?.id ?? newId(),
      name: name.text.trim(),
      host: a.host,
      port: a.port,
      credentialMode: mode,
      credentialId: credId,
    ));
  }

  /// Проксі SOCKS5 або HTTP. Пароль — лише в системному сховищі. Наявний проксі редагується лише
  /// після PIN-коду MHRD чи Windows Hello — тоді видно й збережений пароль (прибрали логін — пароль видаляємо).
  Future<void> _editProxy(BuildContext context, [ProxyProfile? p]) async {
    final l = context.l10n;
    if (p != null && !await authorizeSensitive(context, repo)) return;
    final saved = p == null || p.username.isEmpty ? '' : (await repo.secrets.read(p.secretKey) ?? '');
    if (!context.mounted) return;
    final name = TextEditingController(text: p?.name ?? '');
    final addr = TextEditingController(text: p == null ? '' : '${p.host}:${p.port}');
    final user = TextEditingController(text: p?.username ?? '');
    final pass = TextEditingController(text: saved);
    var type = p?.type ?? ProxyType.socks5;
    var showPass = false;
    String? err;
    int defaultPort() => type == ProxyType.http ? 8080 : 1080;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(p == null ? l.proxyNew : l.proxyTitle),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<ProxyType>(
                initialValue: type,
                decoration: InputDecoration(labelText: l.proxyType),
                items: const [
                  DropdownMenuItem(value: ProxyType.socks5, child: Text('SOCKS5')),
                  DropdownMenuItem(value: ProxyType.http, child: Text('HTTP')),
                ],
                onChanged: (v) => set(() => type = v ?? ProxyType.socks5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addr,
                autofocus: p == null,
                decoration: InputDecoration(
                    labelText: l.proxyAddress, hintText: 'proxy.example.com:${defaultPort()}', errorText: err),
              ),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: InputDecoration(labelText: l.nameOptional)),
              const SizedBox(height: 12),
              TextField(
                controller: user,
                decoration: InputDecoration(labelText: l.credUser, helperText: l.proxyLoginHint),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pass,
                obscureText: !showPass,
                decoration: InputDecoration(
                  labelText: l.password,
                  suffixIcon: IconButton(
                    tooltip: l.showKeys,
                    icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => set(() => showPass = !showPass),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
            FilledButton(
              onPressed: () {
                if (parseAddress(addr.text, defaultPort: defaultPort()) == null) {
                  set(() => err = l.invalidAddress);
                } else {
                  Navigator.pop(c, true);
                }
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final a = parseAddress(addr.text, defaultPort: defaultPort())!;
    final username = user.text.trim();
    final profile = ProxyProfile(
        id: p?.id ?? newId(), name: name.text.trim(), type: type, host: a.host, port: a.port, username: username);
    // Спершу перевіряємо проксі (і ПК за ним, якщо через нього вже ходить ПК), потім зберігаємо.
    // Поле пароля вже містить збережений: що в ньому — те й буде (порожнє — пароль видаляється).
    final password = username.isEmpty ? '' : pass.text;
    final target =
        repo.connections.values.where((c) => c.route == RouteKind.proxy && c.routeRefId == p?.id).firstOrNull;
    if (!context.mounted) return;
    final save = await checkBeforeSave(
      context,
      title: profile.name.isEmpty ? '${a.host}:${a.port}' : profile.name,
      check: () => probeProxy(profile, password: password, targetHost: target?.host, targetPort: target?.port ?? 3389),
      okText: (ms) => target == null ? l.proxyCheckOk(ms) : l.proxyCheckOkPc(ms, target.displayName),
    );
    if (!save || !context.mounted) return;
    final health = AppScope.of(context).sessions.health;
    await repo.saveProxy(profile, password: password);
    health.check(profile.id); // стан у лівій панелі — з новим паролем теж
  }

  /// Рядок проксі: адреса й логін, стан і затримка; перевірити, редагувати (після PIN), видалити.
  Widget _proxyTile(BuildContext context, ProxyProfile p) {
    final t = context.mhrd;
    final l = context.l10n;
    final health = AppScope.of(context).sessions.health;
    return ListenableBuilder(
      listenable: health,
      builder: (context, _) {
        final s = health.statusOf(p.id);
        final (status, color) = _statusLine(context, s);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.swap_horiz, color: s.state == HealthState.ok ? t.ok : null),
          title: Text(p.label),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${p.type == ProxyType.http ? 'HTTP' : 'SOCKS5'} · ${p.host}:${p.port}'
                '${p.username.isEmpty ? '' : ' · ${p.username}'} · ${l.pcCount(repo.usersOfTunnel(p.id))}',
                style: t.mono),
            Text(status, style: TextStyle(color: color, fontSize: 12.5)),
          ]),
          isThreeLine: true,
          trailing: Wrap(children: [
            _checkButton(context, health, p.id, s),
            IconButton(tooltip: l.edit, icon: const Icon(Icons.edit_outlined), onPressed: () => _editProxy(context, p)),
            IconButton(
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _guardedDelete(context, (force) => repo.deleteProxy(p.id, force: force)),
            ),
          ]),
        );
      },
    );
  }

  /// Стан маршруту текстом і кольором: «Працює · 34 мс», причина помилки, «Перевіряю…».
  (String, Color) _statusLine(BuildContext context, RouteStatus s) {
    final t = context.mhrd;
    final l = context.l10n;
    return switch (s.state) {
      HealthState.ok => (l.healthOk(s.latencyMs ?? 0), t.ok),
      HealthState.failed => (l.healthError(s.error ?? TunnelError.failed), t.error),
      HealthState.checking => (l.healthChecking, t.textMuted),
      HealthState.unknown => (l.healthUnknown, t.textMuted),
    };
  }

  Widget _checkButton(BuildContext context, RouteHealth health, String id, RouteStatus s) {
    final checking = s.state == HealthState.checking;
    return IconButton(
      tooltip: context.l10n.checkNow,
      icon: checking
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.network_check),
      onPressed: checking ? null : () => health.check(id),
    );
  }

  /// Імпорт .conf: новий тунель або, з [into], оновлення наявного (те саме id — ПК лишаються на ньому,
  /// назва не змінюється). Спершу перевірка рукостискання, потім збереження.
  Future<void> _importWireGuard(BuildContext context, {TunnelProfile? into}) async {
    final l = context.l10n;
    final f = await openBytes(wgTypes(l));
    if (f == null) return;
    try {
      final conf = parseWireGuardConf(utf8.decode(f.$2, allowMalformed: true));
      final file = f.$1.replaceAll(RegExp(r'\.conf$', caseSensitive: false), '');
      final name = into?.name ?? 'WireGuard · $file';
      if (!context.mounted) return;
      if (!await _saveTunnelChecked(context, id: into?.id, name: name, config: conf.config, secrets: conf.secrets)) {
        return;
      }
      if (context.mounted) {
        toast(context, conf.config['extraPeersIgnored'] == true ? l.wgImportedExtraPeers : l.wgImported(file));
      }
    } on WireGuardConfException catch (e) {
      if (context.mounted) toast(context, l.wireGuardError(e.error));
    }
  }

  /// Перевіряє налаштування WireGuard (рукостискання з сервером) і, якщо людина погодилась, зберігає.
  /// Зайві старі секрети (наприклад, прибраний PSK) видаляє зі сховища.
  Future<bool> _saveTunnelChecked(BuildContext context,
      {String? id,
      required String name,
      required Map<String, dynamic> config,
      required Map<String, String> secrets}) async {
    final l = context.l10n;
    final health = AppScope.of(context).sessions.health;
    final save = await checkBeforeSave(
      context,
      title: name,
      check: () => health.checkWireGuard({...config, ...secrets}),
      okText: (ms) => l.wgCheckOk(ms, tunnelAddress(config) ?? '—'),
    );
    if (!save) return false;
    final profile = TunnelProfile(
      id: id ?? newId(),
      name: name,
      type: TunnelType.wireguard,
      config: config,
      secretFields: secrets.keys.toList(),
    );
    final old = id == null ? null : repo.tunnels[id];
    for (final f in old?.secretFields ?? const <String>[]) {
      if (!secrets.containsKey(f)) await repo.secrets.delete(profile.secretKey(f));
    }
    await repo.saveTunnel(profile, secretValues: secrets);
    if (id != null) health.check(profile.id); // стан у лівій панелі — за новими даними
    return true;
  }

  /// Тунель вручну: новий ([tu] == null) або редагування наявного — лише після PIN-коду MHRD чи
  /// відбитка / Windows Hello, бо тут видно ключі. Для нового можна згенерувати пару ключів: публічний
  /// показується, щоб додати його на сервері.
  Future<void> _editTunnel(BuildContext context, [TunnelProfile? tu]) async {
    final l = context.l10n;
    if (tu != null && !await authorizeSensitive(context, repo)) return;
    final Map<String, dynamic> cfg = tu == null ? const {'mtu': 1420, 'keepalive': 25} : await repo.wireGuardConfig(tu);
    if (!context.mounted) return;
    String list(Object? v) => v is List ? v.join(', ') : '${v ?? ''}';
    final c = {
      'name': TextEditingController(text: tu?.name ?? ''),
      'addresses': TextEditingController(text: list(cfg['addresses'])),
      'dns': TextEditingController(text: list(cfg['dns'])),
      'mtu': TextEditingController(text: cfg['mtu'] == null ? '' : '${cfg['mtu']}'),
      'privateKey': TextEditingController(text: '${cfg['privateKey'] ?? ''}'),
      'peerPublicKey': TextEditingController(text: '${cfg['peerPublicKey'] ?? ''}'),
      'presharedKey': TextEditingController(text: '${cfg['presharedKey'] ?? ''}'),
      'endpoint': TextEditingController(text: '${cfg['endpoint'] ?? ''}'),
      'allowedIps': TextEditingController(text: list(cfg['allowedIps'])),
      'keepalive': TextEditingController(text: cfg['keepalive'] == null ? '' : '${cfg['keepalive']}'),
    };
    // Публічний ключ цього пристрою — з приватного, щойно той схожий на ключ WireGuard.
    final ownPublic = ValueNotifier<String?>(null);
    void derive() => wireGuardPublicKey(c['privateKey']!.text).then((k) => ownPublic.value = k);
    c['privateKey']!.addListener(derive);
    derive();
    var showKeys = false;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, set) {
          final t = dc.mhrd;
          Widget field(String key, String label, {bool secret = false, bool mono = true, String? hint}) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: c[key],
                  obscureText: secret && !showKeys,
                  style: mono ? TextStyle(fontFamily: t.fontMono, fontSize: 13) : null,
                  decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
                ),
              );
          return AlertDialog(
            title: Text(tu == null ? l.wgNewTitle : l.wgEditTitle),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  field('name', l.name, mono: false),
                  _caption(dc, '[Interface]'),
                  field('privateKey', 'PrivateKey', secret: true),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.vpn_key_outlined),
                      label: Text(l.wgGenerateKeys),
                      onPressed: () => set(() {
                        c['privateKey']!.text = generateWireGuardPrivateKey();
                        error = null;
                      }),
                    ),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: ownPublic,
                    builder: (_, pub, child) => pub == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InputDecorator(
                              decoration: InputDecoration(labelText: l.wgYourPublicKey, isDense: true),
                              child: Row(children: [
                                Expanded(
                                    child: SelectableText(pub, style: TextStyle(fontFamily: t.fontMono, fontSize: 13))),
                                IconButton(
                                  tooltip: l.copy,
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: pub));
                                    if (dc.mounted) toast(dc, l.copied);
                                  },
                                ),
                              ]),
                            ),
                          ),
                  ),
                  field('addresses', 'Address', hint: '10.8.0.2/32'),
                  field('dns', 'DNS', hint: '1.1.1.1'),
                  field('mtu', 'MTU', hint: '1420'),
                  _caption(dc, '[Peer]'),
                  field('peerPublicKey', 'PublicKey'),
                  field('presharedKey', 'PresharedKey', secret: true),
                  field('endpoint', 'Endpoint', hint: 'vpn.example.com:51820'),
                  field('allowedIps', 'AllowedIPs', hint: '10.8.0.0/24'),
                  field('keepalive', 'PersistentKeepalive', hint: '25'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showKeys,
                    title: Text(l.showKeys),
                    onChanged: (v) => set(() => showKeys = v ?? false),
                  ),
                  if (error != null) Text(error!, style: TextStyle(color: t.error)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(l.cancel)),
              FilledButton(
                onPressed: () {
                  final psk = c['presharedKey']!.text.trim();
                  if (c['privateKey']!.text.trim().isEmpty || c['peerPublicKey']!.text.trim().isEmpty) {
                    set(() => error = l.wgKeysRequired);
                  } else if (!isWireGuardKey(c['privateKey']!.text) ||
                      !isWireGuardKey(c['peerPublicKey']!.text) ||
                      (psk.isNotEmpty && !isWireGuardKey(psk))) {
                    set(() => error = l.wgKeyInvalid);
                  } else if (c['addresses']!.text.trim().isEmpty) {
                    set(() => error = l.wgAddressRequired);
                  } else if (parseAddress(c['endpoint']!.text, defaultPort: 51820) == null) {
                    set(() => error = l.invalidAddress);
                  } else {
                    Navigator.pop(dc, true);
                  }
                },
                child: Text(l.save),
              ),
            ],
          );
        },
      ),
    );
    final values = {for (final e in c.entries) e.key: e.value.text.trim()};
    c['privateKey']!.removeListener(derive);
    for (final x in c.values) {
      x.dispose();
    }
    ownPublic.dispose();
    if (ok != true || !context.mounted) return;
    List<String> split(String s) => s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final config = <String, dynamic>{
      ...?tu?.config,
      'addresses': split(values['addresses']!),
      'dns': split(values['dns']!),
      'mtu': int.tryParse(values['mtu']!),
      'peerPublicKey': values['peerPublicKey'],
      'endpoint': values['endpoint'],
      'allowedIps': split(values['allowedIps']!),
      'keepalive': int.tryParse(values['keepalive']!),
    }..removeWhere((_, v) => v == null);
    final secrets = {
      'privateKey': values['privateKey']!,
      if (values['presharedKey']!.isNotEmpty) 'presharedKey': values['presharedKey']!,
    };
    final host = parseAddress(values['endpoint']!, defaultPort: 51820)?.host ?? values['endpoint']!;
    final name = values['name']!.isNotEmpty ? values['name']! : (tu?.name ?? 'WireGuard · $host');
    await _saveTunnelChecked(context, id: tu?.id, name: name, config: config, secrets: secrets);
  }

  /// Рядок тунелю: адреса → сервер, стан і затримка; перевірити, оновити з .conf, редагувати, видалити.
  Widget _tunnelTile(BuildContext context, TunnelProfile tu) {
    final t = context.mhrd;
    final l = context.l10n;
    final health = AppScope.of(context).sessions.health;
    return ListenableBuilder(
      listenable: health,
      builder: (context, _) {
        final s = health.statusOf(tu.id);
        final (status, color) = _statusLine(context, s);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.shield_outlined, color: s.state == HealthState.ok ? t.ok : null),
          title: Text(tu.name),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${tunnelAddress(tu.config) ?? ''} → ${tu.config['endpoint'] ?? ''} · ${l.pcCount(repo.usersOfTunnel(tu.id))}',
                style: t.mono),
            Text(status, style: TextStyle(color: color, fontSize: 12.5)),
          ]),
          isThreeLine: true,
          trailing: Wrap(children: [
            _checkButton(context, health, tu.id, s),
            IconButton(
              tooltip: l.wgUpdateFromConf,
              icon: const Icon(Icons.sync),
              onPressed: () => _importWireGuard(context, into: tu),
            ),
            IconButton(
                tooltip: l.edit, icon: const Icon(Icons.edit_outlined), onPressed: () => _editTunnel(context, tu)),
            IconButton(
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _guardedDelete(context, (force) => repo.deleteTunnel(tu.id, force: force)),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    return _pane([
      _caption(context, 'RD Gateway'),
      for (final g in repo.gateways.values)
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(g.label),
          subtitle: Text(g.port == 443 ? g.host : '${g.host}:${g.port}', style: t.mono),
          onTap: () => _editGateway(context, g),
          trailing: IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) async => repo.deleteGateway(g.id, force: force)),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
            icon: const Icon(Icons.add), label: Text(l.addGateway), onPressed: () => _editGateway(context)),
      ),
      _caption(context, l.builtInTunnels),
      Text(l.tunnelsHint, style: TextStyle(color: t.textMuted, fontSize: 13)),
      const SizedBox(height: 8),
      for (final tu in repo.tunnels.values) _tunnelTile(context, tu),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          icon: const Icon(Icons.file_open_outlined),
          label: Text(l.importWireGuard),
          onPressed: () => _importWireGuard(context),
        ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(l.wgCreateManual),
          onPressed: () => _editTunnel(context),
        ),
      ]),
      _caption(context, l.proxies),
      for (final p in repo.proxies.values) _proxyTile(context, p),
      Wrap(spacing: 8, children: [
        TextButton.icon(icon: const Icon(Icons.add), label: Text(l.addProxy), onPressed: () => _editProxy(context)),
      ]),
    ]);
  }
}

// ── Групи ─────────────────────────────────────────────────────────

/// Шаблони екрана: типова роздільність для всіх ПК і свої шаблони (стандартні вже є).
class _ScreensTab extends StatelessWidget {
  const _ScreensTab({required this.repo});
  final Repository repo;

  Future<void> _add(BuildContext context) async {
    final l = context.l10n;
    final name = TextEditingController(), w = TextEditingController(), h = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setState) => AlertDialog(
          title: Text(l.addScreen),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: l.screenName)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: w,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l.screenWidth))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('×')),
              Expanded(
                  child: TextField(
                      controller: h,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l.screenHeight))),
            ]),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: context.mhrd.error)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(l.cancel)),
            FilledButton(
              onPressed: () {
                final wi = int.tryParse(w.text.trim()), hi = int.tryParse(h.text.trim());
                if (wi == null || hi == null || wi < 200 || hi < 200 || wi > 8192 || hi > 8192) {
                  setState(() => error = l.screenSizeInvalid);
                  return;
                }
                Navigator.pop(dc, true);
              },
              child: Text(l.add),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final s = repo.settings;
      // Парна роздільність — так її приймає RDP.
      final t = ScreenTemplate(
          id: newId(),
          name: name.text.trim(),
          width: int.parse(w.text.trim()) ~/ 2 * 2,
          height: int.parse(h.text.trim()) ~/ 2 * 2);
      repo.updateSettings(s.copyWith(screenTemplates: [...s.screenTemplates, t]));
    }
    name.dispose();
    w.dispose();
    h.dispose();
  }

  void _delete(ScreenTemplate t) {
    final s = repo.settings;
    repo.updateSettings(s.copyWith(
      screenTemplates: s.screenTemplates.where((x) => x.id != t.id).toList(),
      defaultScreen: s.defaultScreen == t.id ? ScreenTemplate.auto : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final s = repo.settings;
    final ids = {ScreenTemplate.auto, ...s.allScreenTemplates.map((x) => x.id)};
    return _pane([
      Text(l.newPcDefaultsHint, style: TextStyle(color: t.textMuted)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          icon: const Icon(Icons.tune),
          label: Text(l.newPcDefaultsEdit),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const EditConnectionScreen(template: true),
          )),
        ),
        if (s.newPc != null)
          TextButton(
            onPressed: () => repo.updateSettings(s.copyWith(newPc: () => null)),
            child: Text(l.newPcDefaultsReset),
          ),
      ]),
      // Шаблони роздільності — лише на ПК: на телефоні сеанс завжди за розміром екрана.
      if (!(Platform.isAndroid || Platform.isIOS)) ...[
        _caption(context, l.screenTemplates),
        DropdownButtonFormField<String>(
          initialValue: ids.contains(s.defaultScreen) ? s.defaultScreen : ScreenTemplate.auto,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.defaultScreen, helperText: l.resolutionHint, helperMaxLines: 2),
          items: [
            DropdownMenuItem(value: ScreenTemplate.auto, child: Text(l.screenAuto)),
            for (final x in s.allScreenTemplates) DropdownMenuItem(value: x.id, child: Text(l.screenTemplateName(x))),
          ],
          onChanged: (v) => repo.updateSettings(s.copyWith(defaultScreen: v)),
        ),
        _caption(context, l.customScreens),
        if (s.screenTemplates.isEmpty) Text(l.noCustomScreens, style: TextStyle(color: t.textMuted)),
        for (final x in s.screenTemplates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(x.portrait ? Icons.stay_current_portrait : Icons.desktop_windows_outlined),
            title: Text(l.screenTemplateName(x)),
            trailing:
                IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: () => _delete(x)),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child:
              FilledButton.icon(icon: const Icon(Icons.add), label: Text(l.addScreen), onPressed: () => _add(context)),
        ),
      ],
    ]);
  }
}

class _GroupsTab extends StatelessWidget {
  const _GroupsTab({required this.repo});
  final Repository repo;

  String _path(Group g) {
    final parts = <String>[g.name];
    var p = g.parentId;
    var guard = 0;
    while (p != null && guard++ < 32) {
      final parent = repo.groups[p];
      if (parent == null) break;
      parts.insert(0, parent.name);
      p = parent.parentId;
    }
    return parts.join(' / ');
  }

  Future<void> _edit(BuildContext context, [Group? g]) async {
    final l = context.l10n;
    final name =
        await promptText(context, title: g == null ? l.groupNew : l.groupRename, label: l.name, initial: g?.name ?? '');
    if (name == null || name.trim().isEmpty) return;
    repo.saveGroup(g == null ? Group(id: newId(), name: name.trim()) : g.copyWith(name: name.trim()));
  }

  Future<void> _setParent(BuildContext context, Group g) async {
    final l = context.l10n;
    final others = repo.groups.values.where((x) => x.id != g.id).toList()..sort((a, b) => _path(a).compareTo(_path(b)));
    final i = await pickOne(context, title: l.groupNestInto(g.name), options: [l.topLevel, ...others.map(_path)]);
    if (i == null) return;
    try {
      repo.saveGroup(g.copyWith(parentId: () => i == 0 ? null : others[i - 1].id));
    } on GroupCycleError {
      if (context.mounted) toast(context, l.groupCycle);
    }
  }

  Future<void> _delete(BuildContext context, Group g) async {
    final l = context.l10n;
    final others = repo.groups.values.where((x) => x.id != g.id).toList();
    final hasContent = repo.countInGroup(g.id) > 0 || repo.groups.values.any((x) => x.parentId == g.id);
    String? moveTo;
    if (hasContent) {
      final i =
          await pickOne(context, title: l.groupMoveContentsTo(g.name), options: [l.savedPcs, ...others.map(_path)]);
      if (i == null) return;
      moveTo = i == 0 ? null : others[i - 1].id;
    } else if (!await confirm(context, title: l.groupDeleteTitle(g.name), ok: l.delete, danger: true)) {
      return;
    }
    repo.deleteGroup(g.id, moveTo: moveTo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final list = repo.groups.values.toList()..sort((a, b) => _path(a).compareTo(_path(b)));
    return _pane([
      ListTile(
        leading: const Icon(Icons.folder_special_outlined),
        title: Text(l.savedPcs),
        subtitle: Text(l.defaultGroupInfo(repo.countInGroup(null)), style: TextStyle(color: t.textMuted)),
      ),
      for (final g in list)
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(_path(g)),
          subtitle: Text(l.pcCount(repo.countInGroup(g.id)), style: TextStyle(color: t.textMuted)),
          onTap: () => _edit(context, g),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: l.nestIntoOther,
                icon: const Icon(Icons.drive_file_move_outline),
                onPressed: () => _setParent(context, g)),
            IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, g)),
          ]),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(icon: const Icon(Icons.add), label: Text(l.groupNew), onPressed: () => _edit(context)),
      ),
    ]);
  }
}

// ── Бекап ─────────────────────────────────────────────────────────

class _BackupTab extends StatelessWidget {
  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  const _BackupTab({required this.repo});
  final Repository repo;

  String get _stamp {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  Future<void> _export(BuildContext context) async {
    final l = context.l10n;
    final pw = await promptNewPassword(context, title: l.backupPasswordTitle);
    if (pw == null || !context.mounted) return;
    toast(context, l.encryptingBackup);
    final bytes = await BackupService(repo).exportEncrypted(pw);
    final path = await saveBytes(bytes, 'mhrd-backup-$_stamp.rdpbackup', backupTypes(l));
    if (path == null) return;
    repo.updateSettings(repo.settings.copyWith(lastBackupAt: DateTime.now()));
    if (context.mounted) toast(context, l.backupSaved(path));
  }

  Future<void> _import(BuildContext context) async {
    final l = context.l10n;
    final f = await _pickBackup(context);
    if (f == null || !context.mounted) return;
    final pw = await promptText(context, title: l.backupPasswordLabel, label: l.password, obscure: true, ok: l.open);
    if (pw == null || !context.mounted) return;
    final svc = BackupService(repo);
    final Map<String, dynamic> data;
    try {
      toast(context, l.decrypting);
      data = await svc.decrypt(f.$2, pw);
    } on BackupException catch (e) {
      if (context.mounted) toast(context, l.backupError(e.error));
      return;
    } on FormatException {
      if (context.mounted) toast(context, l.backupCorrupted);
      return;
    }
    if (!context.mounted) return;
    final mode = await pickOne(context, title: l.restoreHow, options: [l.restoreMerge, l.restoreReplace]);
    if (mode == null || !context.mounted) return;
    final replace = mode == 1;
    final pv = svc.preview(data, replaceAll: replace);
    final ok = await confirm(context,
        title: l.restoreConfirmTitle,
        body: l.restorePreview(pv.added, pv.updated, pv.removed),
        ok: l.restore,
        danger: replace);
    if (!ok) return;
    if (replace) {
      // Страховка: поточний стан шифруємо тим самим паролем і кладемо поруч з базою.
      final dir = Portable.dataDir ?? await getApplicationSupportDirectory();
      final safety = File(p.join(dir.path, 'auto-before-restore-${DateTime.now().millisecondsSinceEpoch}.rdpbackup'));
      await safety.writeAsBytes(await svc.exportEncrypted(pw), flush: true);
    }
    try {
      await svc.apply(data, replaceAll: replace);
      if (context.mounted) toast(context, l.restored);
    } on BackupException catch (e) {
      if (context.mounted) toast(context, l.backupError(e.error));
    }
  }

  /// Телефон: автобекап — у пам'яті застосунку (Android не дає застосунку теки на диску, лише
  /// посилання на документ); назовні файл потрапляє лише через «Зберегти бекап».
  static Future<String> _inAppBackupDir() async =>
      p.join((Portable.dataDir ?? await getApplicationSupportDirectory()).path, 'backups');

  /// Бекап для відновлення: на телефоні з увімкненим автобекапом — на вибір копія з пам'яті MHRD
  /// чи файл, інакше — файл.
  Future<(String, Uint8List)?> _pickBackup(BuildContext context) async {
    final l = context.l10n;
    final auto = AppScope.of(context).autoBackup;
    if (_mobile && auto.enabled) {
      final dir = Directory(auto.dir!);
      final copies = dir.existsSync()
          ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.rdpbackup')).toList()
            ..sort((a, b) => b.path.compareTo(a.path)))
          : <File>[];
      if (copies.isNotEmpty) {
        final names = [for (final f in copies) p.basename(f.path)];
        final i = await pickOne(context, title: l.restoreFromBackup, options: [...names, l.restoreFromFile]);
        if (i == null) return null;
        if (i < copies.length) return (names[i], await copies[i].readAsBytes());
      }
    }
    return openBytes(backupTypes(l));
  }

  Future<void> _enableAuto(BuildContext context, AutoBackup auto) async {
    final l = context.l10n;
    final dir = _mobile ? await _inAppBackupDir() : await pickFolder();
    if (dir == null || !context.mounted) return;
    final pw = await promptNewPassword(context, title: l.autoBackupPasswordTitle);
    if (pw == null || !context.mounted) return;
    toast(context, l.autoBackupFirstCopy);
    final path = await auto.enable(dir, pw);
    if (context.mounted) {
      toast(context, path != null ? l.autoBackupEnabled(path) : l.autoBackupFailure(auto.lastError!));
    }
  }

  Future<void> _autoNow(BuildContext context, AutoBackup auto) async {
    final l = context.l10n;
    toast(context, l.autoBackupMaking);
    final path = await auto.runNow();
    if (!context.mounted) return;
    final err = auto.lastError;
    toast(
        context, path != null ? l.autoBackupSaved(path) : (err != null ? l.autoBackupFailure(err) : l.autoBackupBusy));
  }

  Future<void> _exportShare(BuildContext context) async {
    final l = context.l10n;
    final json = const JsonEncoder.withIndent('  ').convert(BackupService(repo).exportShare(repo.connections.values));
    final path = await saveBytes(Uint8List.fromList(utf8.encode(json)), 'mhrd-pcs-$_stamp.json', shareTypes(l));
    if (path != null && context.mounted) toast(context, l.savedWithoutPasswords(path));
  }

  Future<void> _importShare(BuildContext context) async {
    final l = context.l10n;
    final f = await openBytes(shareTypes(l));
    if (f == null) return;
    try {
      final data = jsonDecode(utf8.decode(f.$2));
      if (data is! Map<String, dynamic>) throw BackupException(BackupError.notShareFile);
      await BackupService(repo).importShare(data);
      if (context.mounted) toast(context, l.shareImported);
    } on BackupException catch (e) {
      if (context.mounted) toast(context, l.backupError(e.error));
    } on FormatException {
      // зламаний JSON або не UTF-8
      if (context.mounted) toast(context, l.notShareFile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final last = repo.settings.lastBackupAt;
    final auto = AppScope.of(context).autoBackup;
    return _pane([
      _caption(context, l.fullBackup),
      Text(l.fullBackupHint, style: TextStyle(color: t.textMuted)),
      const SizedBox(height: 6),
      Text(last == null ? l.backupNever : l.backupLast(formatDateTime(last)),
          style: TextStyle(color: last == null ? t.warn : t.textMuted, fontSize: 13)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
            icon: const Icon(Icons.lock_outline), label: Text(l.saveBackup), onPressed: () => _export(context)),
        OutlinedButton.icon(
            icon: const Icon(Icons.restore), label: Text(l.restoreFromBackup), onPressed: () => _import(context)),
      ]),
      _caption(context, l.autoBackup),
      ListenableBuilder(
        listenable: auto,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.autoBackupHint, style: TextStyle(color: t.textMuted)),
          const SizedBox(height: 6),
          if (!auto.enabled)
            Text(l.disabled, style: TextStyle(color: t.textMuted, fontSize: 13))
          else ...[
            // Телефон: копії — у пам'яті MHRD (шлях усередині застосунку нічого не скаже).
            if (_mobile) Text(l.autoBackupInApp) else Text(auto.dir!, style: t.mono),
            const SizedBox(height: 2),
            Text(
              auto.lastAt == null ? l.autoBackupNone : l.autoBackupLast(formatDateTime(auto.lastAt!)),
              style: TextStyle(color: t.textMuted, fontSize: 13),
            ),
            if (auto.lastError != null)
              Text(l.autoBackupFailure(auto.lastError!), style: TextStyle(color: t.error, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (!auto.enabled)
              OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(l.enableEllipsis),
                  onPressed: () => _enableAuto(context, auto))
            else ...[
              OutlinedButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l.autoBackupNow),
                  onPressed: () => _autoNow(context, auto)),
              if (!_mobile)
                OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(l.autoBackupChange),
                    onPressed: () => _enableAuto(context, auto)),
              TextButton.icon(icon: const Icon(Icons.close), label: Text(l.disable), onPressed: auto.disable),
            ],
          ]),
        ]),
      ),
      _caption(context, l.sharePcList),
      Text(l.sharePcListHint, style: TextStyle(color: t.textMuted)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(
            icon: const Icon(Icons.ios_share), label: Text(l.export), onPressed: () => _exportShare(context)),
        OutlinedButton.icon(
            icon: const Icon(Icons.file_download_outlined),
            label: Text(l.import),
            onPressed: () => _importShare(context)),
      ]),
    ]);
  }
}
