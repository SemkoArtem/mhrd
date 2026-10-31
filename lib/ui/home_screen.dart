import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/connection.dart';
import '../models/entities.dart';
import '../sessions/session_manager.dart';
import '../sessions/session_protocol.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import '../util/address.dart';
import '../util/rdp_file.dart';
import '../util/wake_on_lan.dart';
import 'credential_dialog.dart';
import 'dialogs.dart';
import 'edit_connection_screen.dart';
import 'file_actions.dart';
import 'session_screen.dart';
import 'settings_screen.dart';
import 'widgets/pc_card.dart';

/// Фільтр списку: усі, нещодавні, без групи («Збережені ПК») або конкретна група.
const _all = '__all', _recent = '__recent', _saved = '__saved';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = _all;
  String _query = '';
  final _quick = TextEditingController();
  final _quickFocus = FocusNode();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _quick.dispose();
    _quickFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Repository get repo => AppScope.of(context).repo;

  // ── Дії ─────────────────────────────────────────────────────────

  /// Підключення: акаунт ПК (пароль зі сховища) або діалог входу, далі — екран сеансу.
  /// [askPassword] — спитати навіть за збереженого пароля (після «невірний пароль»).
  Future<void> _connect(Connection c, {String? credentialId, bool askPassword = false}) async {
    final l = context.l10n;
    final sessions = AppScope.of(context).sessions;
    // Найсвіжіша версія ПК: після «Довіряти сертифікату» в ній уже є certPin.
    c = repo.connections[c.id] ?? c;
    if (!sessions.engineAvailable) {
      toast(context, l.engineMissing);
      return;
    }
    final running = credentialId == null ? sessions.forConnection(c.id) : null;
    if (running != null) {
      if (sessions.nativeWindows) {
        running.focusWindow();
      } else {
        _openSession(running, c);
      }
      return;
    }
    final creds = await sessions.credentialsFor(c, credentialId: credentialId);
    var user = creds.username, password = creds.password;
    if (askPassword || !creds.complete) {
      if (!mounted) return;
      final r = await askCredentials(context, target: c.displayName, username: user);
      if (r == null) return;
      (user, password) = r;
    }
    if (!mounted) return;
    if (sessions.nativeWindows) {
      final s = await _startWindow(c, user!, password ?? '');
      if (s != null && mounted) _watchWindow(s, c, credentialId: credentialId);
      return;
    }
    // Роздільність = розмір вікна у фізичних пікселях (масштаб Windows 150% → ×1.5), а масштаб
    // ОС передаємо серверу — так картинка чітка, а текст на ПК звичного розміру.
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int even(double v, int min, int max) => (v.floor().clamp(min, max) ~/ 2) * 2;
    final s = await sessions.start(c,
        username: user!,
        password: password ?? '',
        width: even(size.width * dpr, 640, 8192),
        height: even((size.height - 40) * dpr, 480, 8192),
        scale: (dpr * 100).round());
    if (mounted) _openSession(s, c, credentialId: credentialId);
  }

  /// Десктоп: сеанс у власному вікні процесу `mhrd-session`. Роздільність — у фізичних пікселях
  /// монітора: на весь екран — увесь екран, інакше 80% (вікно потім саме підлаштує її під себе).
  Future<RdpSession?> _startWindow(Connection c, String username, String password) async {
    final l = context.l10n;
    final t = context.mhrd;
    final sessions = AppScope.of(context).sessions;
    final display = View.of(context).display;
    final fullscreen = c.display.startFullscreen ?? repo.settings.startFullscreen;
    final k = fullscreen ? 1.0 : 0.8;
    int even(double v, int min, int max) => (v.floor().clamp(min, max) ~/ 2) * 2;
    int rgb(Color color) => color.toARGB32() & 0xFFFFFF;
    final exe = sessions.enginePath!;
    toast(context, l.connectingTo(c.address));
    return sessions.start(
      c,
      username: username,
      password: password,
      width: c.display.width ?? even(display.size.width * k, 640, 8192),
      height: c.display.height ?? even(display.size.height * k, 480, 8192),
      scale: (display.devicePixelRatio * 100).round(),
      window: {
        'title': '${c.displayName} — MHRD',
        // Шрифт плашки — той самий, що в застосунку (лежить поруч у flutter_assets).
        'fontPath': '${File(exe).parent.path}${Platform.pathSeparator}data${Platform.pathSeparator}'
            'flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}fonts'
            '${Platform.pathSeparator}IBMPlexSans-Medium.ttf',
        'labels': {
          'pin': l.barPin,
          'unpin': l.barUnpin,
          'minimize': l.barMinimize,
          'exitFullscreen': l.barWindowed,
          'disconnect': l.disconnectAction,
        },
        'colors': {
          'surface': rgb(t.surface),
          'border': rgb(t.border),
          'text': rgb(t.text),
          'accent': rgb(t.accent),
          'error': rgb(t.error),
        },
        'startFullscreen': fullscreen,
        'keyboardCapture': repo.settings.keyboardCapture.index, // 0 лише на весь екран, 1 завжди, 2 ніколи
        'resizeMode': c.display.resizeMode.index, // 0 змінювати роздільність, 1 масштабувати, 2 ні
        'swapMouse': c.swapMouseButtons,
      },
    );
  }

  /// Вікно сеансу живе саме; головне вікно лише питає про сертифікат і пояснює, чому сеанс
  /// закрився (з «Підключитись знову»).
  void _watchWindow(RdpSession s, Connection c, {String? credentialId}) {
    var asking = false;
    s.addListener(() {
      final cert = s.pendingCertificate;
      if (cert == null || asking || !mounted) return;
      asking = true;
      _askCertificate(s, cert).whenComplete(() => asking = false);
    });
    s.done.then((_) async {
      final ended = s.ended;
      if (!mounted || ended == null || ended.reason == DisconnectReason.userRequest) return;
      await _bringToFront();
      if (!mounted) return;
      final l = context.l10n;
      final t = context.mhrd;
      final retry = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
          icon: Icon(Icons.error_outline, color: t.error),
          title: Text(c.displayName),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l.disconnectReason(ended.reason), textAlign: TextAlign.center),
              if (ended.details.isNotEmpty || ended.code != 0) ...[
                const SizedBox(height: 10),
                SelectableText(
                  l.sessionDetails(ended.details.isEmpty ? '—' : ended.details, '0x${ended.code.toRadixString(16)}'),
                  textAlign: TextAlign.center,
                  style: t.mono,
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(l.close)),
            FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(l.retry)),
          ],
        ),
      );
      if (retry != true || !mounted) return;
      _connect(c,
          credentialId: credentialId,
          askPassword: ended.reason == DisconnectReason.authFailed || ended.reason == DisconnectReason.noCredentials);
    });
  }

  Future<void> _askCertificate(RdpSession s, CertificateEvent cert) async {
    await _bringToFront();
    if (!mounted) return;
    final sessions = AppScope.of(context).sessions;
    final r = await showDialog<(bool, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CertificateDialog(cert: cert, canRemember: repo.connections.containsKey(s.connection.id)),
    );
    final (accept, remember) = r ?? (false, false);
    if (accept && remember) sessions.trustCertificate(s, cert.fingerprint);
    s.answerCertificate(accept);
  }

  /// Діалог про сеанс має бути видно, навіть якщо головне вікно згорнуте чи позаду.
  Future<void> _bringToFront() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  void _openSession(RdpSession s, Connection c, {String? credentialId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (route) => SessionScreen(
        session: s,
        onRetry: () {
          Navigator.of(route).pop();
          final reason = s.ended?.reason;
          _connect(c,
              credentialId: credentialId,
              askPassword: reason == DisconnectReason.authFailed || reason == DisconnectReason.noCredentials);
        },
      ),
    ));
  }

  void _quickConnect() {
    final l = context.l10n;
    final addr = parseAddress(_quick.text);
    if (addr == null) {
      toast(context, l.invalidAddressExamples);
      return;
    }
    final now = DateTime.now();
    final temp = Connection(id: newId(), name: '', host: addr.host, port: addr.port, createdAt: now, updatedAt: now);
    toast(context, l.connectingTo(temp.address),
        action: SnackBarAction(label: l.saveThisPc, onPressed: () => _edit(temp, isNew: true)));
    _connect(temp);
  }

  Future<void> _edit(Connection? c, {bool isNew = false}) async {
    final groupId = (_filter.startsWith('__')) ? null : _filter;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EditConnectionScreen(initial: c, isNew: isNew || c == null, defaultGroupId: groupId),
    ));
  }

  Future<void> _delete(Connection c) async {
    final l = context.l10n;
    if (await confirm(context, title: l.deletePcTitle(c.displayName), ok: l.delete, danger: true)) {
      repo.deleteConnections([c.id]);
    }
  }

  Future<void> _move(Connection c) async {
    final l = context.l10n;
    final groups = repo.groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final i = await pickOne(context, title: l.moveToGroup, options: [l.savedPcs, ...groups.map((g) => g.name)]);
    if (i == null) return;
    repo.saveConnection(c.copyWith(groupId: () => i == 0 ? null : groups[i - 1].id));
  }

  Future<void> _exportRdp(Connection c) async {
    final l = context.l10n;
    final cred = c.credentialIds.isEmpty ? null : repo.credentials[c.credentialIds.first];
    final text = buildRdpFile(c, username: cred?.username, gatewayHost: repo.gateways[c.gatewayId]?.host);
    final safe = c.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await saveBytes(Uint8List.fromList(encodeUtf16Le(text)), '$safe.rdp', rdpTypes(l));
    if (path != null && mounted) toast(context, l.savedTo(path));
  }

  Future<void> _importRdp() async {
    final l = context.l10n;
    final files = await openManyBytes(rdpTypes(l));
    var ok = 0;
    final errors = <String>[];
    for (final (name, bytes) in files) {
      try {
        final r = parseRdpFile(decodeRdpBytes(bytes),
            id: newId(), fallbackName: name.replaceAll(RegExp(r'\.rdp$', caseSensitive: false), ''));
        var conn = r.connection;
        if (r.username != null) {
          final existing = repo.credentials.values.where((c) => c.username == r.username).toList();
          final cred = existing.isNotEmpty
              ? existing.first
              : Credential(id: newId(), name: '', username: r.username!, authMode: AuthMode.askPassword);
          if (existing.isEmpty) await repo.saveCredential(cred);
          conn = conn.copyWith(credentialIds: [cred.id]);
        }
        if (r.gatewayHost != null) {
          final existing = repo.gateways.values.where((g) => g.host == r.gatewayHost).toList();
          final gw = existing.isNotEmpty ? existing.first : Gateway(id: newId(), name: '', host: r.gatewayHost!);
          if (existing.isEmpty) repo.saveGateway(gw);
          conn = conn.copyWith(gatewayId: () => gw.id);
        }
        final groupId = _filter.startsWith('__') ? null : _filter;
        repo.saveConnection(conn.copyWith(groupId: () => groupId));
        ok++;
      } on FormatException {
        // parseRdpFile кидає лише одну помилку: немає коректної адреси.
        errors.add('$name: ${l.rdpNoAddress}');
      }
    }
    if (!mounted || files.isEmpty) return;
    toast(context, errors.isEmpty ? l.importedPcs(ok) : l.importedWithErrors(ok, errors.join('; ')));
  }

  Future<void> _wake(Connection c) async {
    final l = context.l10n;
    final w = c.wakeOnLan;
    if (w == null) return;
    try {
      await sendWakeOnLan(w);
      if (mounted) toast(context, l.wakeSent(w.mac));
    } on WakeOnLanException catch (e) {
      if (mounted) toast(context, l.wakeOnLanError(e));
    } on SocketException catch (e) {
      if (mounted) toast(context, l.wakeFailed(e.message));
    }
  }

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  PcActions get _actions => PcActions(
        connect: _connect,
        edit: (c) => _edit(c),
        duplicate: (c) => repo.duplicateConnection(c, name: context.l10n.copyOf(c.displayName)),
        exportRdp: _exportRdp,
        moveToGroup: _move,
        wake: _wake,
        delete: _delete,
      );

  // ── Дані ────────────────────────────────────────────────────────

  List<Connection> _visible() {
    Iterable<Connection> list = repo.connections.values;
    switch (_filter) {
      case _all:
        break;
      case _recent:
        list = list.where((c) => c.lastUsed != null);
      case _saved:
        list = list.where((c) => c.groupId == null);
      default:
        final ids = _withSubgroups(_filter);
        list = list.where((c) => ids.contains(c.groupId));
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) =>
          c.displayName.toLowerCase().contains(q) ||
          c.host.toLowerCase().contains(q) ||
          c.tags.any((t) => t.toLowerCase().contains(q)) ||
          (repo.groups[c.groupId]?.name.toLowerCase().contains(q) ?? false));
    }
    final out = list.toList();
    if (_filter == _recent) {
      out.sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!));
      return out.take(12).toList();
    }
    out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return out;
  }

  Set<String> _withSubgroups(String id) {
    final out = {id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final g in repo.groups.values) {
        if (g.parentId != null && out.contains(g.parentId) && out.add(g.id)) grew = true;
      }
    }
    return out;
  }

  String _title(AppLocalizations l) => switch (_filter) {
        _all => l.allPcs,
        _recent => l.recent,
        _saved => l.savedPcs,
        _ => repo.groups[_filter]?.name ?? l.allPcs,
      };

  // ── Розмітка ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        if (!_filter.startsWith('__') && !repo.groups.containsKey(_filter)) _filter = _all;
        final wide = MediaQuery.sizeOf(context).width >= 760;
        final mac = Theme.of(context).platform == TargetPlatform.macOS;
        SingleActivator key(LogicalKeyboardKey k) => SingleActivator(k, meta: mac, control: !mac);
        return CallbackShortcuts(
          bindings: {
            key(LogicalKeyboardKey.keyN): () => _edit(null),
            key(LogicalKeyboardKey.keyK): () => _quickFocus.requestFocus(),
            key(LogicalKeyboardKey.keyF): () => _searchFocus.requestFocus(),
            key(LogicalKeyboardKey.comma): _openSettings,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              drawer: wide ? null : Drawer(child: SafeArea(child: _sidebar(context, inDrawer: true))),
              body: SafeArea(
                child: Column(children: [
                  _header(context, wide),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (wide) SizedBox(width: 248, child: _sidebar(context)),
                      Expanded(child: _main(context)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, bool wide) {
    final t = context.mhrd;
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: t.surface, border: Border(bottom: BorderSide(color: t.border))),
      child: Row(children: [
        if (!wide)
          Builder(
              builder: (c) => IconButton(
                    tooltip: l.groups,
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(c).openDrawer(),
                  )),
        Text('MHRD',
            style: TextStyle(
                fontFamily: t.fontMono,
                fontWeight: FontWeight.w500,
                fontSize: 20,
                letterSpacing: 0.8,
                color: t.accent)),
        if (wide) ...[
          const SizedBox(width: 8),
          Text('remote desktop', style: TextStyle(color: t.textMuted, fontSize: 12)),
        ],
        const SizedBox(width: 16),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TextField(
              controller: _quick,
              focusNode: _quickFocus,
              style: TextStyle(fontFamily: t.fontMono, fontSize: 13.5, color: t.text),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.bolt, color: t.textMuted, size: 18),
                hintText: l.quickConnectHint,
                suffixText: wide ? 'Ctrl K' : null,
                suffixStyle: TextStyle(fontFamily: t.fontMono, fontSize: 11, color: t.textMuted),
              ),
              onSubmitted: (_) => _quickConnect(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          tooltip: l.add,
          onSelected: (v) => v == 'pc' ? _edit(null) : _importRdp(),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'pc', child: Text(l.addPc)),
            PopupMenuItem(value: 'rdp', child: Text(l.importRdpFiles)),
          ],
          child: IgnorePointer(
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add, size: 18),
              label: Text(wide ? l.add : ''),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(tooltip: l.settings, onPressed: _openSettings, icon: const Icon(Icons.tune)),
      ]),
    );
  }

  Widget _sidebar(BuildContext context, {bool inDrawer = false}) {
    final t = context.mhrd;
    final l = context.l10n;
    Widget item(String id, String label, int count, {int depth = 0}) {
      final active = _filter == id;
      return Padding(
        padding: EdgeInsets.only(left: depth * 14.0),
        child: Material(
          color: active ? t.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radius * 0.7),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radius * 0.7),
            onTap: () {
              setState(() => _filter = id);
              if (inDrawer) Navigator.pop(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: t.gap + 1),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? t.text : t.textMuted, fontSize: 14)),
                ),
                Text('$count', style: TextStyle(fontFamily: t.fontMono, color: t.textMuted, fontSize: 12)),
              ]),
            ),
          ),
        ),
      );
    }

    List<Widget> tree(String? parent, int depth) {
      final kids = repo.groups.values.where((g) => g.parentId == parent).toList()
        ..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder - b.sortOrder : a.name.compareTo(b.name));
      return [
        for (final g in kids) ...[
          item(g.id, g.name, repo.countInGroup(g.id), depth: depth),
          ...tree(g.id, depth + 1),
        ],
      ];
    }

    Widget caption(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
          child: Text(s.toUpperCase(),
              style: TextStyle(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        );

    return Container(
      decoration: BoxDecoration(color: t.surface, border: Border(right: BorderSide(color: t.border))),
      child: ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 20), children: [
        caption(l.computers),
        item(_all, l.allPcs, repo.connections.length),
        item(_recent, l.recent, repo.connections.values.where((c) => c.lastUsed != null).length),
        item(_saved, l.savedPcs, repo.countInGroup(null)),
        if (repo.groups.isNotEmpty) caption(l.groups),
        ...tree(null, 0),
        caption(l.activeTunnels),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(l.noTunnelsYet, style: TextStyle(color: t.textMuted, fontSize: 12.5)),
        ),
      ]),
    );
  }

  Widget _main(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final items = _visible();
    final tiles = repo.settings.listView == PcListView.tiles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(_title(l), style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w600)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 260,
                child: TextField(
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.searchHint,
                    prefixIcon: Icon(Icons.search, size: 18, color: t.textMuted),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<PcListView>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: PcListView.tiles, icon: const Icon(Icons.grid_view, size: 18), tooltip: l.viewTiles),
                  ButtonSegment(
                      value: PcListView.list, icon: const Icon(Icons.view_list, size: 18), tooltip: l.viewList),
                ],
                selected: {repo.settings.listView},
                onSelectionChanged: (s) => repo.updateSettings(repo.settings.copyWith(listView: s.first)),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: items.isEmpty
              ? _empty(context)
              : tiles
                  ? GridView.builder(
                      padding: const EdgeInsets.only(bottom: 32),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        mainAxisExtent: 236,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => PcTile(connection: items[i], repo: repo, actions: _actions),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => PcRow(connection: items[i], repo: repo, actions: _actions),
                    ),
        ),
      ]),
    );
  }

  Widget _empty(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final searching = _query.trim().isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.desktop_windows_outlined, size: 48, color: t.textMuted),
          const SizedBox(height: 14),
          Text(searching ? l.nothingFound : l.emptyTitle,
              style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            searching ? l.nothingFoundHint : l.emptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMuted),
          ),
          if (!searching) ...[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: Text(l.addPc)),
          ],
        ]),
      ),
    );
  }
}
