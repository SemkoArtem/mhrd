import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/connection.dart';
import '../models/entities.dart';
import '../sessions/session_manager.dart';
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

  static const _defaultBroadcast = '255.255.255.255';

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

  bool _checking = false, _checkOk = false;
  String? _checkText;

  /// «Перевірити з'єднання»: чи відповідає ПК через вибраний маршрут і з якою затримкою —
  /// з тим, що зараз у формі, навіть ще не збереженим.
  Future<void> _check() async {
    final l = context.l10n;
    final addr = parseAddress(_address.text);
    if (addr == null) {
      setState(() => _addressError = l.addressRequired);
      return;
    }
    final health = AppScope.of(context).sessions.health;
    setState(() {
      _checking = true;
      _checkText = null;
    });
    String text;
    var ok = false;
    try {
      final ms = await health.measure(_c.copyWith(host: addr.host, port: addr.port));
      text = l.pcResponds(ms);
      ok = true;
    } on TunnelException catch (e) {
      text = l.tunnelError(e.error);
    } on ProxyException catch (e) {
      text = l.proxyError(e.error);
    } on ProbeException catch (e) {
      text = l.healthError(e.error);
    } on RouteException catch (e) {
      text = l.routeError(e.error);
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkOk = ok;
      _checkText = text;
    });
  }

  void _save() {
    final l = context.l10n;
    final addr = parseAddress(_address.text);
    if (addr == null) {
      setState(() => _addressError = l.addressRequired);
      return;
    }
    final macText = _mac.text.trim();
    final mac = macText.isEmpty ? null : parseMac(macText);
    if (macText.isNotEmpty && mac == null) {
      toast(context, l.macFormat);
      return;
    }
    final bcText = _broadcast.text.trim();
    final bc = bcText.isEmpty ? _defaultBroadcast : bcText;
    if (mac != null && InternetAddress.tryParse(bc)?.type != InternetAddressType.IPv4) {
      toast(context, l.broadcastFormat);
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
    final l = context.l10n;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: t.surface,
          title: Text(widget.isNew ? l.addPc : l.editPcTitle),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(onPressed: _save, child: Text(widget.isNew ? l.add : l.save)),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: l.tabGeneral), Tab(text: l.tabDisplay), Tab(text: l.tabDevices), Tab(text: l.tabAdvanced)],
          ),
        ),
        body: ListenableBuilder(
          listenable: repo,
          builder: (context, _) => TabBarView(children: [
            _page(_general(context)),
            _page(_display(context)),
            _page(_devices(context)),
            _page(_advanced(context)),
          ]),
        ),
      ),
    );
  }

  Widget _page(List<Widget> children) => centeredList(children, maxWidth: 640);

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(title, style: TextStyle(color: context.mhrd.textMuted, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  // ── Загальні ────────────────────────────────────────────────────

  List<Widget> _general(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final groups = repo.groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final gateways = repo.gateways.values.toList();
    final creds = _c.credentialIds.map((id) => repo.credentials[id]).whereType<Credential>().toList();
    final routeOptions = <RouteKind, List<(String, String)>>{
      RouteKind.tunnel: repo.tunnels.values.map((x) => (x.id, x.name)).toList(),
      RouteKind.proxy: repo.proxies.values.map((x) => (x.id, x.name)).toList(),
    };

    return [
      TextField(
        controller: _address,
        autofocus: widget.isNew && _c.host.isEmpty,
        style: TextStyle(fontFamily: t.fontMono),
        decoration: InputDecoration(
          labelText: l.pcAddress,
          hintText: l.pcAddressHint,
          errorText: _addressError,
        ),
        onChanged: (_) => setState(() => _addressError = null),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _name,
        decoration: InputDecoration(labelText: l.nameOptional, helperText: l.nameHelper),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String?>(
        initialValue: repo.groups.containsKey(_c.groupId) ? _c.groupId : null,
        decoration: InputDecoration(labelText: l.group),
        items: [
          DropdownMenuItem(value: null, child: Text(l.savedPcs)),
          for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
        ],
        onChanged: (v) => _set(_c.copyWith(groupId: () => v)),
      ),

      _section(l.pcImage),
      _imagePicker(context),

      _section(l.accounts),
      if (creds.isEmpty) Text(l.noAccountsHint, style: TextStyle(color: t.textMuted)),
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
                subtitle: Text(i == 0 ? l.defaultAccount : l.availableInConnectAs,
                    style: TextStyle(color: t.textMuted, fontSize: 12)),
                trailing: IconButton(
                  tooltip: l.removeFromPc,
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
          label: Text(l.credNewTitle),
          onPressed: () async {
            final cr = await editCredential(context, repo);
            if (cr != null) _set(_c.copyWith(credentialIds: [..._c.credentialIds, cr.id]));
          },
        ),
        if (repo.credentials.values.any((x) => !_c.credentialIds.contains(x.id)))
          TextButton.icon(
            icon: const Icon(Icons.playlist_add),
            label: Text(l.addSavedAccount),
            onPressed: () async {
              final avail = repo.credentials.values.where((x) => !_c.credentialIds.contains(x.id)).toList();
              final i = await pickOne(context, title: l.credTitle, options: avail.map((x) => x.label).toList());
              if (i != null) _set(_c.copyWith(credentialIds: [..._c.credentialIds, avail[i].id]));
            },
          ),
      ]),

      _section(l.route),
      DropdownButtonFormField<RouteKind>(
        initialValue: _c.route,
        decoration: InputDecoration(labelText: l.routeHow),
        items: [
          DropdownMenuItem(value: RouteKind.direct, child: Text(l.routeDirect)),
          DropdownMenuItem(value: RouteKind.tunnel, child: Text(l.routeViaTunnel)),
          DropdownMenuItem(value: RouteKind.proxy, child: Text(l.routeViaProxy)),
        ],
        onChanged: (v) => _set(_c.copyWith(route: v, routeRefId: () => null)),
      ),
      if (_c.route != RouteKind.direct) ...[
        const SizedBox(height: 12),
        if ((routeOptions[_c.route] ?? const []).isEmpty)
          Text(l.noRouteProfiles, style: TextStyle(color: t.warn))
        else
          DropdownButtonFormField<String>(
            key: ValueKey('route-${_c.route.name}'),
            initialValue: (routeOptions[_c.route]!.any((o) => o.$1 == _c.routeRefId)) ? _c.routeRefId : null,
            decoration: InputDecoration(labelText: l.profile),
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
          DropdownMenuItem(value: null, child: Text(l.noGateway)),
          for (final g in gateways) DropdownMenuItem(value: g.id, child: Text(g.label)),
        ],
        onChanged: (v) => _set(_c.copyWith(gatewayId: () => v)),
      ),
      if (_c.gatewayId != null)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _c.gatewayBypassLocal,
          title: Text(l.bypassGatewayLocal),
          onChanged: (v) => _set(_c.copyWith(gatewayBypassLocal: v)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        OutlinedButton.icon(
          icon: _checking
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check),
          label: Text(l.checkConnection),
          onPressed: _checking ? null : _check,
        ),
        const SizedBox(width: 12),
        if (_checkText != null)
          Expanded(
            child: Text(_checkText!, style: TextStyle(color: _checkOk ? t.ok : t.error, fontSize: 13)),
          ),
      ]),

      _section(l.sectionConnection),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _c.reconnectOnDrop,
        title: Text(l.reconnectOnDrop),
        onChanged: (v) => _set(_c.copyWith(reconnectOnDrop: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _c.adminSession,
        title: Text(l.adminSession),
        subtitle: Text(l.adminSessionHint),
        onChanged: (v) => _set(_c.copyWith(adminSession: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _c.swapMouseButtons,
        title: Text(l.swapMouse),
        onChanged: (v) => _set(_c.copyWith(swapMouseButtons: v)),
      ),
    ];
  }

  /// Своя картинка на плитці ПК замість мініатюри останнього сеансу.
  Widget _imagePicker(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final files = AppScope.of(context).sessions.files;
    final file = _c.image == null || files == null ? null : files.image(_c.image!);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 128,
        height: 72,
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: BorderRadius.circular(t.radius * 0.7),
          border: Border.all(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Icon(Icons.desktop_windows_outlined, color: t.textMuted),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.pcImageHint, style: TextStyle(color: t.textMuted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(l.pcImagePick),
              onPressed: files == null
                  ? null
                  : () async {
                      final picked = await openBytes(imageTypes(l));
                      if (picked == null) return;
                      final ext = p.extension(picked.$1).replaceFirst('.', '').toLowerCase();
                      final name = await files.saveImage(_c.id, picked.$2, ext.isEmpty ? 'png' : ext);
                      _set(_c.copyWith(image: () => name));
                    },
            ),
            if (_c.image != null)
              TextButton(onPressed: () => _set(_c.copyWith(image: () => null)), child: Text(l.pcImageRemove)),
          ]),
        ]),
      ),
    ]);
  }

  // ── Екран ───────────────────────────────────────────────────────

  List<Widget> _display(BuildContext context) {
    final d = _c.display;
    final t = context.mhrd;
    final l = context.l10n;
    void setD(DisplaySettings x) => _set(_c.copyWith(display: x));
    final s = repo.settings;
    final screenIds = {null, ScreenTemplate.auto, ...s.allScreenTemplates.map((x) => x.id)};
    final defaultName = s.screenTemplate(s.defaultScreen) == null
        ? l.screenAuto
        : l.screenTemplateName(s.screenTemplate(s.defaultScreen)!);
    return [
      DropdownButtonFormField<String?>(
        initialValue: screenIds.contains(d.screen) ? d.screen : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.resolution, helperText: l.resolutionHint, helperMaxLines: 2),
        items: [
          DropdownMenuItem(value: null, child: Text(l.asInGeneralSettingsWith(defaultName))),
          DropdownMenuItem(value: ScreenTemplate.auto, child: Text(l.screenAuto)),
          for (final x in s.allScreenTemplates) DropdownMenuItem(value: x.id, child: Text(l.screenTemplateName(x))),
        ],
        onChanged: (v) => setD(d.copyWith(screen: () => v, width: () => null, height: () => null)),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.useAllMonitors,
        title: Text(l.useAllMonitors),
        onChanged: (v) => setD(d.copyWith(useAllMonitors: v)),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<int>(
        initialValue: d.startFullscreen == null ? 0 : (d.startFullscreen! ? 1 : 2),
        decoration: InputDecoration(labelText: l.startFullscreen),
        items: [
          DropdownMenuItem(value: 0, child: Text(l.asInGeneralSettings)),
          DropdownMenuItem(value: 1, child: Text(l.yes)),
          DropdownMenuItem(value: 2, child: Text(l.no)),
        ],
        onChanged: (v) => setD(d.copyWith(startFullscreen: () => v == 0 ? null : v == 1)),
      ),
      _section(l.onWindowResize),
      SegmentedButton<ResizeMode>(
        segments: [
          ButtonSegment(value: ResizeMode.changeResolution, label: Text(l.resizeChangeResolution)),
          ButtonSegment(value: ResizeMode.scale, label: Text(l.resizeScale)),
          ButtonSegment(value: ResizeMode.none, label: Text(l.resizeNone)),
        ],
        selected: {d.resizeMode},
        onSelectionChanged: (s) => setD(d.copyWith(resizeMode: s.first)),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: d.colorDepth,
        decoration: InputDecoration(labelText: l.colorDepth),
        items: [
          DropdownMenuItem(value: 32, child: Text(l.color32)),
          DropdownMenuItem(value: 24, child: Text(l.color24)),
          DropdownMenuItem(value: 16, child: Text(l.color16)),
          DropdownMenuItem(value: 15, child: Text(l.color15)),
        ],
        onChanged: (v) => setD(d.copyWith(colorDepth: v)),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<int>(
        initialValue: const [100, 125, 150, 175, 200, 250, 300].contains(d.scalePercent) ? d.scalePercent : 100,
        decoration: InputDecoration(labelText: l.remoteScale),
        items: [
          for (final p in const [100, 125, 150, 175, 200, 250, 300]) DropdownMenuItem(value: p, child: Text('$p %')),
        ],
        onChanged: (v) => setD(d.copyWith(scalePercent: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.hiDpi,
        title: Text(l.hiDpi),
        subtitle: Text(l.hiDpiWarning, style: TextStyle(color: t.warn, fontSize: 12.5)),
        onChanged: (v) => setD(d.copyWith(hiDpi: v)),
      ),
    ];
  }

  // ── Пристрої ────────────────────────────────────────────────────

  List<Widget> _devices(BuildContext context) {
    final d = _c.devices;
    final t = context.mhrd;
    final l = context.l10n;
    void setD(DeviceSettings x) => _set(_c.copyWith(devices: x));
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.clipboard,
        title: Text(l.clipboard),
        subtitle: Text(l.clipboardHint),
        onChanged: (v) => setD(d.copyWith(clipboard: v)),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<SoundMode>(
        initialValue: d.sound,
        decoration: InputDecoration(
          labelText: l.sound,
          helperText: d.sound == SoundMode.remote ? l.soundRemoteHint : null,
          helperMaxLines: 3,
        ),
        items: [
          DropdownMenuItem(value: SoundMode.local, child: Text(l.soundLocal)),
          DropdownMenuItem(value: SoundMode.remote, child: Text(l.soundRemote)),
          DropdownMenuItem(value: SoundMode.off, child: Text(l.soundOff)),
        ],
        onChanged: (v) => setD(d.copyWith(sound: v)),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.microphone,
        title: Text(l.microphone),
        subtitle: Text(l.microphoneHint),
        onChanged: (v) => setD(d.copyWith(microphone: v)),
      ),
      _section(l.folders),
      Text(l.foldersHint, style: TextStyle(color: t.textMuted, fontSize: 13)),
      const SizedBox(height: 6),
      if (d.folders.isEmpty) Text(l.noFolders, style: TextStyle(color: t.textMuted)),
      for (var i = 0; i < d.folders.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text(d.folders[i].name),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.folders[i].path, style: t.mono),
            DropdownButton<FolderAccess>(
              value: d.folders[i].access,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(value: FolderAccess.addOnly, child: Text(l.folderAddOnly)),
                DropdownMenuItem(value: FolderAccess.full, child: Text(l.folderFull)),
                DropdownMenuItem(value: FolderAccess.readOnly, child: Text(l.readOnly)),
              ],
              onChanged: (v) {
                if (v == null) return;
                final f = [...d.folders];
                f[i] = f[i].copyWith(access: v);
                setD(d.copyWith(folders: f));
              },
            ),
          ]),
          trailing: IconButton(
            tooltip: l.removeFolder,
            icon: const Icon(Icons.close),
            onPressed: () => setD(d.copyWith(folders: [...d.folders]..removeAt(i))),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(l.addFolder),
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
    final l = context.l10n;
    return [
      TextField(
        controller: _tags,
        decoration: InputDecoration(labelText: l.tags, helperText: l.tagsHelper),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _mac,
        style: TextStyle(fontFamily: t.fontMono),
        decoration: InputDecoration(
          labelText: l.wolMac,
          hintText: 'AA:BB:CC:DD:EE:FF',
          helperText: l.wolMacHelper,
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _broadcast,
        style: TextStyle(fontFamily: t.fontMono),
        decoration: InputDecoration(
          labelText: l.wolBroadcast,
          hintText: _defaultBroadcast,
          helperText: l.wolBroadcastHelper,
        ),
      ),
      if (_c.certPin != null) ...[
        _section(l.serverCertificate),
        Text(l.trustedFingerprint(_c.certPin!), style: t.mono),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _set(_c.copyWith(certPin: () => null)),
            child: Text(l.forgetCertificate),
          ),
        ),
      ],
    ];
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNullSafe => isEmpty ? null : last;
}
