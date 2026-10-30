import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/connection.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import '../util/address.dart';
import '../util/rdp_file.dart';
import 'dialogs.dart';
import 'edit_connection_screen.dart';
import 'file_actions.dart';
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

  void _connect(Connection c, {String? credentialId}) {
    final msg = AppScope.of(context).sessions.connect(c, credentialId: credentialId);
    if (msg != null) toast(context, msg);
  }

  void _quickConnect() {
    final addr = parseAddress(_quick.text);
    if (addr == null) {
      toast(context, 'Некоректна адреса. Приклади: 10.0.0.5, srv.local:3390, [fd00::5]:3389');
      return;
    }
    final now = DateTime.now();
    final temp = Connection(id: newId(), name: '', host: addr.host, port: addr.port, createdAt: now, updatedAt: now);
    final msg = AppScope.of(context).sessions.connect(temp);
    toast(
      context,
      msg ?? 'Підключення до ${temp.address}…',
      action: SnackBarAction(label: 'Зберегти цей ПК', onPressed: () => _edit(temp, isNew: true)),
    );
  }

  Future<void> _edit(Connection? c, {bool isNew = false}) async {
    final groupId = (_filter.startsWith('__')) ? null : _filter;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EditConnectionScreen(initial: c, isNew: isNew || c == null, defaultGroupId: groupId),
    ));
  }

  Future<void> _delete(Connection c) async {
    if (await confirm(context, title: 'Видалити «${c.displayName}»?', ok: 'Видалити', danger: true)) {
      repo.deleteConnections([c.id]);
    }
  }

  Future<void> _move(Connection c) async {
    final groups = repo.groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final i = await pickOne(context,
        title: 'Перемістити в групу', options: ['Збережені ПК', ...groups.map((g) => g.name)]);
    if (i == null) return;
    repo.saveConnection(c.copyWith(groupId: () => i == 0 ? null : groups[i - 1].id));
  }

  Future<void> _exportRdp(Connection c) async {
    final cred = c.credentialIds.isEmpty ? null : repo.credentials[c.credentialIds.first];
    final text = buildRdpFile(c, username: cred?.username, gatewayHost: repo.gateways[c.gatewayId]?.host);
    final safe = c.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await saveBytes(Uint8List.fromList(encodeUtf16Le(text)), '$safe.rdp', rdpTypes);
    if (path != null && mounted) toast(context, 'Збережено: $path');
  }

  Future<void> _importRdp() async {
    final files = await openManyBytes(rdpTypes);
    var ok = 0;
    final errors = <String>[];
    for (final (name, bytes) in files) {
      try {
        final r = parseRdpFile(decodeRdpBytes(bytes), id: newId(), fallbackName: name.replaceAll(RegExp(r'\.rdp$', caseSensitive: false), ''));
        var conn = r.connection;
        if (r.username != null) {
          final existing = repo.credentials.values.where((c) => c.username == r.username).toList();
          final cred = existing.isNotEmpty ? existing.first : Credential(id: newId(), name: '', username: r.username!, authMode: AuthMode.askPassword);
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
      } on FormatException catch (e) {
        errors.add('$name: ${e.message}');
      }
    }
    if (!mounted || files.isEmpty) return;
    toast(context, errors.isEmpty ? 'Імпортовано ПК: $ok' : 'Імпортовано: $ok. Помилки: ${errors.join('; ')}');
  }

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  PcActions get _actions => PcActions(
        connect: _connect,
        edit: (c) => _edit(c),
        duplicate: (c) => repo.duplicateConnection(c),
        exportRdp: _exportRdp,
        moveToGroup: _move,
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

  String get _title => switch (_filter) {
        _all => 'Усі ПК',
        _recent => 'Нещодавні',
        _saved => 'Збережені ПК',
        _ => repo.groups[_filter]?.name ?? 'Усі ПК',
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: t.surface, border: Border(bottom: BorderSide(color: t.border))),
      child: Row(children: [
        if (!wide)
          Builder(builder: (c) => IconButton(
                tooltip: 'Групи',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(c).openDrawer(),
              )),
        Text('MHRD',
            style: TextStyle(
                fontFamily: t.fontMono, fontWeight: FontWeight.w500, fontSize: 20, letterSpacing: 0.8, color: t.accent)),
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
                hintText: 'Швидке підключення: адреса ПК',
                suffixText: wide ? 'Ctrl K' : null,
                suffixStyle: TextStyle(fontFamily: t.fontMono, fontSize: 11, color: t.textMuted),
              ),
              onSubmitted: (_) => _quickConnect(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          tooltip: 'Додати',
          onSelected: (v) => v == 'pc' ? _edit(null) : _importRdp(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'pc', child: Text('Додати ПК')),
            PopupMenuItem(value: 'rdp', child: Text('Імпортувати .rdp-файли')),
          ],
          child: IgnorePointer(
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add, size: 18),
              label: Text(wide ? 'Додати' : ''),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(tooltip: 'Налаштування', onPressed: _openSettings, icon: const Icon(Icons.tune)),
      ]),
    );
  }

  Widget _sidebar(BuildContext context, {bool inDrawer = false}) {
    final t = context.mhrd;
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
        caption("Комп'ютери"),
        item(_all, 'Усі ПК', repo.connections.length),
        item(_recent, 'Нещодавні', repo.connections.values.where((c) => c.lastUsed != null).length),
        item(_saved, 'Збережені ПК', repo.countInGroup(null)),
        if (repo.groups.isNotEmpty) caption('Групи'),
        ...tree(null, 0),
        caption('Активні тунелі'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('Немає. Тунелі запрацюють на етапі 4.',
              style: TextStyle(color: t.textMuted, fontSize: 12.5)),
        ),
      ]),
    );
  }

  Widget _main(BuildContext context) {
    final t = context.mhrd;
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
            Text(_title, style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w600)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 260,
                child: TextField(
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Назва, адреса, тег',
                    prefixIcon: Icon(Icons.search, size: 18, color: t.textMuted),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<PcListView>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PcListView.tiles, icon: Icon(Icons.grid_view, size: 18), tooltip: 'Плитки'),
                  ButtonSegment(value: PcListView.list, icon: Icon(Icons.view_list, size: 18), tooltip: 'Список'),
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
    final searching = _query.trim().isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.desktop_windows_outlined, size: 48, color: t.textMuted),
          const SizedBox(height: 14),
          Text(searching ? 'Нічого не знайдено' : 'Тут поки порожньо',
              style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            searching
                ? 'Спробуйте іншу назву, адресу або тег.'
                : 'Додайте перший ПК, імпортуйте .rdp-файли або відновіть бекап у налаштуваннях.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMuted),
          ),
          if (!searching) ...[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Додати ПК')),
          ],
        ]),
      ),
    );
  }
}
