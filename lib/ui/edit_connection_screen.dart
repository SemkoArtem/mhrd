import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/connection.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import '../util/address.dart';
import '../util/wake_on_lan.dart';
import 'credential_dialog.dart';
import 'dialogs.dart';
import 'file_actions.dart';

/// Вікно «Додати ПК» / «Редагувати ПК». Вкладки як у старого клієнта:
/// Загальні · Екран · Пристрої · Додатково.
class EditConnectionScreen extends StatefulWidget {
  const EditConnectionScreen({super.key, this.initial, this.isNew = false, this.defaultGroupId});

  final Connection? initial;
  final bool isNew;
  final String? defaultGroupId;

  @override
  State<EditConnectionScreen> createState() => _EditConnectionScreenState();
}

class _EditConnectionScreenState extends State<EditConnectionScreen> {
  late Connection _c;
  late final TextEditingController _address;
  late final TextEditingController _name;
  late final TextEditingController _tags;
  late final TextEditingController _mac;
  late final TextEditingController _broadcast;
  String? _addressError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _c = widget.initial ??
        Connection(id: newId(), name: '', host: '', groupId: widget.defaultGroupId, createdAt: now, updatedAt: now);
    _address = TextEditingController(text: _c.host.isEmpty ? '' : _c.address);
    _name = TextEditingController(text: _c.name);
    _tags = TextEditingController(text: _c.tags.join(', '));
    _mac = TextEditingController(text: _c.wakeOnLan?.mac ?? '');
    final bc = _c.wakeOnLan?.broadcast;
    _broadcast = TextEditingController(text: bc == null || bc == _defaultBroadcast ? '' : bc);
  }

  static const _defaultBroadcast = '255.255.255.255';

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    _tags.dispose();
    _mac.dispose();
    _broadcast.dispose();
    super.dispose();
  }

  Repository get repo => AppScope.of(context).repo;

  void _set(Connection c) => setState(() => _c = c);

  void _save() {
    final addr = parseAddress(_address.text);
    if (addr == null) {
      setState(() => _addressError = 'Вкажіть адресу: 10.0.0.5, srv.local:3390 або [fd00::5]:3389');
      return;
    }
    final macText = _mac.text.trim();
    final mac = macText.isEmpty ? null : parseMac(macText);
    if (macText.isNotEmpty && mac == null) {
      toast(context, 'MAC-адреса має вигляд AA:BB:CC:DD:EE:FF');
      return;
    }
    final bcText = _broadcast.text.trim();
    final bc = bcText.isEmpty ? _defaultBroadcast : bcText;
    if (mac != null && InternetAddress.tryParse(bc)?.type != InternetAddressType.IPv4) {
      toast(context, 'Широкомовна адреса — це IPv4, наприклад 192.168.1.255');
      return;
    }
    repo.saveConnection(_c.copyWith(
      host: addr.host,
      port: addr.port,
      name: _name.text.trim(),
      tags: _tags.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      wakeOnLan: () => mac == null
          ? null
          : WakeOnLan(mac: formatMac(mac), broadcast: bc, port: _c.wakeOnLan?.port ?? 9),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: t.surface,
          title: Text(widget.isNew ? 'Додати ПК' : 'Редагувати ПК'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(onPressed: _save, child: Text(widget.isNew ? 'Додати' : 'Зберегти')),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Загальні'), Tab(text: 'Екран'), Tab(text: 'Пристрої'), Tab(text: 'Додатково')],
          ),
        ),
        body: ListenableBuilder(
          listenable: repo,
          builder: (context, _) => TabBarView(children: [
            _page([..._general(context)]),
            _page(_display(context)),
            _page(_devices(context)),
            _page(_advanced(context)),
          ]),
        ),
      ),
    );
  }

  Widget _page(List<Widget> children) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: children),
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(title, style: TextStyle(color: context.mhrd.textMuted, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  // ── Загальні ────────────────────────────────────────────────────

  List<Widget> _general(BuildContext context) {
    final t = context.mhrd;
    final groups = repo.groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final gateways = repo.gateways.values.toList();
    final creds = _c.credentialIds.map((id) => repo.credentials[id]).whereType<Credential>().toList();
    final routeOptions = <RouteKind, List<(String, String)>>{
      RouteKind.tunnel: repo.tunnels.values.map((x) => (x.id, x.name)).toList(),
      RouteKind.proxy: repo.proxies.values.map((x) => (x.id, x.name)).toList(),
      RouteKind.ssh: repo.ssh.values.map((x) => (x.id, x.name)).toList(),
    };

    return [
      TextField(
        controller: _address,
        autofocus: widget.isNew && _c.host.isEmpty,
        style: TextStyle(fontFamily: t.fontMono),
        decoration: InputDecoration(
          labelText: 'Адреса ПК',
          hintText: 'Ім\'я, IP або ім\'я:порт',
          errorText: _addressError,
        ),
        onChanged: (_) => setState(() => _addressError = null),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Назва (необов\'язково)', helperText: 'Якщо порожньо — показується адреса'),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String?>(
        initialValue: repo.groups.containsKey(_c.groupId) ? _c.groupId : null,
        decoration: const InputDecoration(labelText: 'Група'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Збережені ПК')),
          for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
        ],
        onChanged: (v) => _set(_c.copyWith(groupId: () => v)),
      ),

      _section('Облікові записи'),
      if (creds.isEmpty)
        Text('Питати логін і пароль при кожному підключенні.', style: TextStyle(color: t.textMuted)),
      if (creds.isNotEmpty)
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            final ids = [..._c.credentialIds];
            ids.insert(b, ids.removeAt(a));
            _set(_c.copyWith(credentialIds: ids));
          },
          children: [
            for (var i = 0; i < creds.length; i++)
              ListTile(
                key: ValueKey(creds[i].id),
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                title: Text(creds[i].label),
                subtitle: Text(i == 0 ? 'За замовчуванням' : 'Доступний у «Підключитись як…»',
                    style: TextStyle(color: t.textMuted, fontSize: 12)),
                trailing: IconButton(
                  tooltip: 'Прибрати з цього ПК',
                  icon: const Icon(Icons.close),
                  onPressed: () => _set(_c.copyWith(
                      credentialIds: _c.credentialIds.where((x) => x != creds[i].id).toList())),
                ),
              ),
          ],
        ),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Новий обліковий запис'),
          onPressed: () async {
            final cr = await editCredential(context, repo);
            if (cr != null) _set(_c.copyWith(credentialIds: [..._c.credentialIds, cr.id]));
          },
        ),
        if (repo.credentials.values.any((x) => !_c.credentialIds.contains(x.id)))
          TextButton.icon(
            icon: const Icon(Icons.playlist_add),
            label: const Text('Додати збережений'),
            onPressed: () async {
              final avail = repo.credentials.values.where((x) => !_c.credentialIds.contains(x.id)).toList();
              final i = await pickOne(context, title: 'Обліковий запис', options: avail.map((x) => x.label).toList());
              if (i != null) _set(_c.copyWith(credentialIds: [..._c.credentialIds, avail[i].id]));
            },
          ),
      ]),

      _section('Маршрут'),
      DropdownButtonFormField<RouteKind>(
        initialValue: _c.route,
        decoration: const InputDecoration(labelText: 'Як підключатися'),
        items: const [
          DropdownMenuItem(value: RouteKind.direct, child: Text('Напряму')),
          DropdownMenuItem(value: RouteKind.tunnel, child: Text('Через вбудований тунель (WireGuard, OpenVPN…)')),
          DropdownMenuItem(value: RouteKind.proxy, child: Text('Через проксі')),
          DropdownMenuItem(value: RouteKind.ssh, child: Text('Через SSH-тунель')),
        ],
        onChanged: (v) => _set(_c.copyWith(route: v, routeRefId: () => null)),
      ),
      if (_c.route != RouteKind.direct) ...[
        const SizedBox(height: 12),
        if ((routeOptions[_c.route] ?? const []).isEmpty)
          Text('Ще немає жодного профілю. Додайте його в Налаштування → Маршрути.',
              style: TextStyle(color: t.warn))
        else
          DropdownButtonFormField<String>(
            key: ValueKey('route-${_c.route.name}'),
            initialValue: (routeOptions[_c.route]!.any((o) => o.$1 == _c.routeRefId)) ? _c.routeRefId : null,
            decoration: const InputDecoration(labelText: 'Профіль'),
            items: [
              for (final o in routeOptions[_c.route]!) DropdownMenuItem(value: o.$1, child: Text(o.$2)),
            ],
            onChanged: (v) => _set(_c.copyWith(routeRefId: () => v)),
          ),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(
        initialValue: repo.gateways.containsKey(_c.gatewayId) ? _c.gatewayId : null,
        decoration: const InputDecoration(labelText: 'RD Gateway'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Без шлюзу')),
          for (final g in gateways) DropdownMenuItem(value: g.id, child: Text(g.label)),
        ],
        onChanged: (v) => _set(_c.copyWith(gatewayId: () => v)),
      ),
      if (_c.gatewayId != null)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _c.gatewayBypassLocal,
          title: const Text('Обходити шлюз для локальних адрес'),
          onChanged: (v) => _set(_c.copyWith(gatewayBypassLocal: v)),
        ),

      _section('Підключення'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _c.reconnectOnDrop,
        title: const Text('Перепідключатися при обриві'),
        onChanged: (v) => _set(_c.copyWith(reconnectOnDrop: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _c.adminSession,
        title: const Text('Адміністративний сеанс'),
        subtitle: const Text('Підключення до консольного сеансу сервера'),
        onChanged: (v) => _set(_c.copyWith(adminSession: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _c.swapMouseButtons,
        title: const Text('Поміняти кнопки миші місцями'),
        onChanged: (v) => _set(_c.copyWith(swapMouseButtons: v)),
      ),
    ];
  }

  // ── Екран ───────────────────────────────────────────────────────

  List<Widget> _display(BuildContext context) {
    final d = _c.display;
    final t = context.mhrd;
    void setD(DisplaySettings x) => _set(_c.copyWith(display: x));
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.useAllMonitors,
        title: const Text('Використовувати всі монітори'),
        onChanged: (v) => setD(d.copyWith(useAllMonitors: v)),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<int>(
        initialValue: d.startFullscreen == null ? 0 : (d.startFullscreen! ? 1 : 2),
        decoration: const InputDecoration(labelText: 'Запуск на весь екран'),
        items: const [
          DropdownMenuItem(value: 0, child: Text('Як у загальних налаштуваннях')),
          DropdownMenuItem(value: 1, child: Text('Так')),
          DropdownMenuItem(value: 2, child: Text('Ні')),
        ],
        onChanged: (v) => setD(d.copyWith(startFullscreen: () => v == 0 ? null : v == 1)),
      ),
      _section('Коли змінюється розмір вікна'),
      SegmentedButton<ResizeMode>(
        segments: const [
          ButtonSegment(value: ResizeMode.changeResolution, label: Text('Змінювати роздільність')),
          ButtonSegment(value: ResizeMode.scale, label: Text('Масштабувати')),
          ButtonSegment(value: ResizeMode.none, label: Text('Без змін')),
        ],
        selected: {d.resizeMode},
        onSelectionChanged: (s) => setD(d.copyWith(resizeMode: s.first)),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: d.colorDepth,
        decoration: const InputDecoration(labelText: 'Глибина кольору'),
        items: const [
          DropdownMenuItem(value: 32, child: Text('Найвища (32 біти)')),
          DropdownMenuItem(value: 24, child: Text('Висока (24 біти)')),
          DropdownMenuItem(value: 16, child: Text('Середня (16 біт) — менше трафіку')),
          DropdownMenuItem(value: 15, child: Text('Низька (15 біт)')),
        ],
        onChanged: (v) => setD(d.copyWith(colorDepth: v)),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<int>(
        initialValue: const [100, 125, 150, 175, 200, 250, 300].contains(d.scalePercent) ? d.scalePercent : 100,
        decoration: const InputDecoration(labelText: 'Масштаб елементів на віддаленому ПК'),
        items: [
          for (final p in const [100, 125, 150, 175, 200, 250, 300]) DropdownMenuItem(value: p, child: Text('$p %')),
        ],
        onChanged: (v) => setD(d.copyWith(scalePercent: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.hiDpi,
        title: const Text('Повна чіткість на Retina / HiDPI'),
        subtitle: Text('Приблизно вчетверо більше трафіку', style: TextStyle(color: t.warn, fontSize: 12.5)),
        onChanged: (v) => setD(d.copyWith(hiDpi: v)),
      ),
    ];
  }

  // ── Пристрої ────────────────────────────────────────────────────

  List<Widget> _devices(BuildContext context) {
    final d = _c.devices;
    final t = context.mhrd;
    void setD(DeviceSettings x) => _set(_c.copyWith(devices: x));
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.clipboard,
        title: const Text('Буфер обміну'),
        subtitle: const Text('Текст і зображення в обидва боки'),
        onChanged: (v) => setD(d.copyWith(clipboard: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.microphone,
        title: const Text('Мікрофон'),
        onChanged: (v) => setD(d.copyWith(microphone: v)),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<SoundMode>(
        initialValue: d.sound,
        decoration: const InputDecoration(labelText: 'Звук'),
        items: const [
          DropdownMenuItem(value: SoundMode.local, child: Text('На цьому пристрої')),
          DropdownMenuItem(value: SoundMode.remote, child: Text('На віддаленому ПК')),
          DropdownMenuItem(value: SoundMode.off, child: Text('Не відтворювати')),
        ],
        onChanged: (v) => setD(d.copyWith(sound: v)),
      ),
      _section('Папки'),
      if (d.folders.isEmpty)
        Text('Жодна папка не доступна віддаленому ПК.', style: TextStyle(color: t.textMuted)),
      for (var i = 0; i < d.folders.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text(d.folders[i].name),
          subtitle: Text(d.folders[i].path, style: t.mono),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            FilterChip(
              label: const Text('Лише читання'),
              selected: d.folders[i].readOnly,
              onSelected: (v) {
                final f = [...d.folders];
                f[i] = SharedFolder(name: f[i].name, path: f[i].path, readOnly: v);
                setD(d.copyWith(folders: f));
              },
            ),
            IconButton(
              tooltip: 'Прибрати папку',
              icon: const Icon(Icons.close),
              onPressed: () => setD(d.copyWith(folders: [...d.folders]..removeAt(i))),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Додати папку'),
          onPressed: () async {
            final path = await pickFolder();
            if (path == null) return;
            final name = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNullSafe ?? path;
            setD(d.copyWith(folders: [...d.folders, SharedFolder(name: name, path: path)]));
          },
        ),
      ),
    ];
  }

  // ── Додатково ───────────────────────────────────────────────────

  List<Widget> _advanced(BuildContext context) {
    final t = context.mhrd;
    return [
      TextField(
        controller: _tags,
        decoration: const InputDecoration(labelText: 'Теги', helperText: 'Через кому: офіс, 1с, бухгалтерія'),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _mac,
        style: TextStyle(fontFamily: t.fontMono),
        decoration: const InputDecoration(
          labelText: 'MAC-адреса для Wake-on-LAN',
          hintText: 'AA:BB:CC:DD:EE:FF',
          helperText: 'Щоб будити ПК із меню «Розбудити»',
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _broadcast,
        style: TextStyle(fontFamily: t.fontMono),
        decoration: const InputDecoration(
          labelText: 'Широкомовна адреса для Wake-on-LAN (необов\'язково)',
          hintText: _defaultBroadcast,
          helperText: 'Якщо ПК в іншій підмережі — її broadcast, наприклад 192.168.1.255',
        ),
      ),
      if (_c.certPin != null) ...[
        _section('Сертифікат сервера'),
        Text('Довірений відбиток: ${_c.certPin}', style: t.mono),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _set(_c.copyWith(certPin: () => null)),
            child: const Text('Забути сертифікат (спитати знову при підключенні)'),
          ),
        ),
      ],
    ];
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNullSafe => isEmpty ? null : last;
}
