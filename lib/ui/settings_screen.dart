import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../backup/auto_backup.dart';
import '../backup/backup_service.dart';
import '../l10n/l10n.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import '../util/address.dart';
import '../util/wireguard_conf.dart';
import 'credential_dialog.dart';
import 'dialogs.dart';
import 'file_actions.dart';
import 'theme_editor.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final repo = AppScope.of(context).repo;
    return DefaultTabController(
      length: 6,
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
            _BackupTab(repo: repo),
          ]),
        ),
      ),
    );
  }
}

Widget _pane(List<Widget> children) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(20), children: children),
      ),
    );

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
        title: l.inUseTitle(l.inUseKind(e.kind)),
        body: l.inUseBody(l.inUseUsers(e)),
        ok: l.delete,
        danger: true);
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
      SwitchListTile(
        value: s.startFullscreen,
        title: Text(l.startSessionsFullscreen),
        onChanged: (v) => set(s.copyWith(startFullscreen: v)),
      ),
      SwitchListTile(
        value: s.newWindowPerSession,
        title: Text(l.sessionPerWindow),
        subtitle: Text(l.sessionPerWindowHint),
        onChanged: (v) => set(s.copyWith(newWindowPerSession: v)),
      ),
      SwitchListTile(
        value: s.keepScreenAwake,
        title: Text(l.keepScreenAwake),
        onChanged: (v) => set(s.copyWith(keepScreenAwake: v)),
      ),
      SwitchListTile(
        value: s.showPreviews,
        title: Text(l.showPreviews),
        onChanged: (v) => set(s.copyWith(showPreviews: v)),
      ),
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

  /// Проксі SOCKS5 або HTTP. Пароль — лише в системному сховищі; під час редагування порожнє
  /// поле пароля лишає збережений (прибрали логін — пароль видаляємо).
  Future<void> _editProxy(BuildContext context, [ProxyProfile? p]) async {
    final l = context.l10n;
    final name = TextEditingController(text: p?.name ?? '');
    final addr = TextEditingController(text: p == null ? '' : '${p.host}:${p.port}');
    final user = TextEditingController(text: p?.username ?? '');
    final pass = TextEditingController();
    var type = p?.type ?? ProxyType.socks5;
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
              TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: l.password)),
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
    await repo.saveProxy(
      ProxyProfile(id: p?.id ?? newId(), name: name.text.trim(), type: type, host: a.host, port: a.port, username: username),
      password: username.isEmpty ? '' : (pass.text.isEmpty ? null : pass.text),
    );
  }

  /// SSH-тунель. Секрет (пароль або текст приватного ключа) — лише в системному сховищі.
  /// Під час редагування порожній пароль / невибраний ключ лишає збережений секрет.
  Future<void> _editSsh(BuildContext context, [SshProfile? s]) async {
    final l = context.l10n;
    final name = TextEditingController(text: s?.name ?? '');
    final addr = TextEditingController(text: s == null ? '' : (s.port == 22 ? s.host : '${s.host}:${s.port}'));
    final user = TextEditingController(text: s?.username ?? '');
    final pass = TextEditingController();
    var kind = s?.authKind ?? SshAuthKind.privateKey;
    String? keyText, keyName;
    String? addrErr, userErr, keyErr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(s == null ? l.sshNew : l.sshTitle),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: addr,
                  autofocus: s == null,
                  decoration:
                      InputDecoration(labelText: l.sshAddress, hintText: 'jump.example.com:22', errorText: addrErr),
                ),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: InputDecoration(labelText: l.nameOptional)),
                const SizedBox(height: 12),
                TextField(controller: user, decoration: InputDecoration(labelText: l.credUser, errorText: userErr)),
                const SizedBox(height: 12),
                DropdownButtonFormField<SshAuthKind>(
                  initialValue: kind,
                  decoration: InputDecoration(labelText: l.sshAuth),
                  items: [
                    DropdownMenuItem(value: SshAuthKind.privateKey, child: Text(l.sshAuthKey)),
                    DropdownMenuItem(value: SshAuthKind.password, child: Text(l.sshAuthPassword)),
                  ],
                  onChanged: (v) => set(() => kind = v ?? SshAuthKind.privateKey),
                ),
                const SizedBox(height: 12),
                if (kind == SshAuthKind.password)
                  TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: l.password))
                else ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.key_outlined),
                    label: Text(l.sshPickKey),
                    onPressed: () async {
                      final f = await openBytes(sshKeyTypes(l));
                      if (f == null) return;
                      set(() {
                        keyName = f.$1;
                        keyText = utf8.decode(f.$2, allowMalformed: true);
                        keyErr = null;
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    keyErr ??
                        (keyName != null
                            ? l.sshKeyLoaded(keyName!)
                            : (s?.authKind == SshAuthKind.privateKey ? l.sshKeyKept : '')),
                    style: TextStyle(
                        fontSize: 12, color: keyErr != null ? context.mhrd.error : context.mhrd.textMuted),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
            FilledButton(
              onPressed: () {
                final needKey =
                    kind == SshAuthKind.privateKey && keyText == null && s?.authKind != SshAuthKind.privateKey;
                set(() {
                  addrErr = parseAddress(addr.text, defaultPort: 22) == null ? l.invalidAddress : null;
                  userErr = user.text.trim().isEmpty ? l.credUserRequired : null;
                  keyErr = needKey ? l.sshKeyRequired : null;
                });
                if (addrErr == null && userErr == null && keyErr == null) Navigator.pop(c, true);
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final a = parseAddress(addr.text, defaultPort: 22)!;
    // Інший сервер — довіра до ключа старого не переноситься.
    final samePlace = s != null && s.host == a.host && s.port == a.port;
    final secret = kind == SshAuthKind.password ? (pass.text.isEmpty ? null : pass.text) : keyText;
    await repo.saveSsh(
      SshProfile(
        id: s?.id ?? newId(),
        name: name.text.trim(),
        host: a.host,
        port: a.port,
        username: user.text.trim(),
        authKind: kind,
        hostKeyPin: samePlace ? s.hostKeyPin : null,
      ),
      secret: secret,
    );
  }

  Future<void> _importWireGuard(BuildContext context) async {
    final l = context.l10n;
    final f = await openBytes(wgTypes(l));
    if (f == null) return;
    try {
      final conf = parseWireGuardConf(utf8.decode(f.$2, allowMalformed: true));
      final name = f.$1.replaceAll(RegExp(r'\.conf$', caseSensitive: false), '');
      await repo.saveTunnel(
        TunnelProfile(
          id: newId(),
          name: 'WireGuard · $name',
          type: TunnelType.wireguard,
          config: conf.config,
          secretFields: conf.secrets.keys.toList(),
        ),
        secretValues: conf.secrets,
      );
      if (context.mounted) {
        toast(context, conf.config['extraPeersIgnored'] == true ? l.wgImportedExtraPeers : l.wgImported(name));
      }
    } on WireGuardConfException catch (e) {
      if (context.mounted) toast(context, l.wireGuardError(e.error));
    }
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
      for (final tu in repo.tunnels.values)
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(tu.name),
          subtitle: Text('${tu.config['endpoint'] ?? ''} · ${l.pcCount(repo.usersOfTunnel(tu.id))}', style: t.mono),
          trailing: IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) => repo.deleteTunnel(tu.id, force: force)),
          ),
        ),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          icon: const Icon(Icons.file_open_outlined),
          label: Text(l.importWireGuard),
          onPressed: () => _importWireGuard(context),
        ),
      ]),
      _caption(context, l.proxyAndSsh),
      for (final p in repo.proxies.values)
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: Text(p.name.trim().isEmpty ? '${p.type == ProxyType.http ? 'HTTP' : 'SOCKS5'} · ${p.host}' : p.name),
          subtitle: Text('${p.host}:${p.port}${p.username.isEmpty ? '' : ' · ${p.username}'}', style: t.mono),
          onTap: () => _editProxy(context, p),
          trailing: IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) => repo.deleteProxy(p.id, force: force)),
          ),
        ),
      for (final s in repo.ssh.values)
        ListTile(
          leading: const Icon(Icons.terminal),
          title: Text(s.name.trim().isEmpty ? 'SSH · ${s.host}' : s.name),
          subtitle: Text('${s.username}@${s.host}${s.port == 22 ? '' : ':${s.port}'}', style: t.mono),
          onTap: () => _editSsh(context, s),
          trailing: IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) => repo.deleteSsh(s.id, force: force)),
          ),
        ),
      Wrap(spacing: 8, children: [
        TextButton.icon(icon: const Icon(Icons.add), label: Text(l.addProxy), onPressed: () => _editProxy(context)),
        TextButton.icon(icon: const Icon(Icons.add), label: Text(l.addSsh), onPressed: () => _editSsh(context)),
      ]),
      Text(l.sshHint, style: TextStyle(color: t.textMuted, fontSize: 13)),
    ]);
  }
}

// ── Групи ─────────────────────────────────────────────────────────

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
    final name = await promptText(context,
        title: g == null ? l.groupNew : l.groupRename, label: l.name, initial: g?.name ?? '');
    if (name == null || name.trim().isEmpty) return;
    repo.saveGroup(g == null ? Group(id: newId(), name: name.trim()) : g.copyWith(name: name.trim()));
  }

  Future<void> _setParent(BuildContext context, Group g) async {
    final l = context.l10n;
    final others = repo.groups.values.where((x) => x.id != g.id).toList()
      ..sort((a, b) => _path(a).compareTo(_path(b)));
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
      final i = await pickOne(context,
          title: l.groupMoveContentsTo(g.name), options: [l.savedPcs, ...others.map(_path)]);
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
    final f = await openBytes(backupTypes(l));
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
      final dir = await getApplicationSupportDirectory();
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

  Future<void> _enableAuto(BuildContext context, AutoBackup auto) async {
    final l = context.l10n;
    final dir = await pickFolder();
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
    toast(context, path != null ? l.autoBackupSaved(path) : (err != null ? l.autoBackupFailure(err) : l.autoBackupBusy));
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
            Text(auto.dir!, style: t.mono),
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
