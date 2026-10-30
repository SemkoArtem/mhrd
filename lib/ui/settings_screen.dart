import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../backup/backup_service.dart';
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
    final repo = AppScope.of(context).repo;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: t.surface,
          title: const Text('Налаштування'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Загальні'),
              Tab(text: 'Тема'),
              Tab(text: 'Облікові записи'),
              Tab(text: 'Маршрути'),
              Tab(text: 'Групи'),
              Tab(text: 'Бекап'),
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
    final ok = await confirm(context,
        title: '${e.what} використовується',
        body: 'Його використовують: ${e.users.join(', ')}.\nПрибрати його звідти й видалити?',
        ok: 'Видалити',
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
    final s = repo.settings;
    void set(AppSettings x) => repo.updateSettings(x);
    return _pane([
      SwitchListTile(
        value: s.startFullscreen,
        title: const Text('Запускати сеанси на весь екран'),
        onChanged: (v) => set(s.copyWith(startFullscreen: v)),
      ),
      SwitchListTile(
        value: s.newWindowPerSession,
        title: const Text('Кожен сеанс в окремому вікні'),
        subtitle: const Text('Інакше — вкладки в головному вікні'),
        onChanged: (v) => set(s.copyWith(newWindowPerSession: v)),
      ),
      SwitchListTile(
        value: s.keepScreenAwake,
        title: const Text('Не вимикати екран під час сеансу'),
        onChanged: (v) => set(s.copyWith(keepScreenAwake: v)),
      ),
      SwitchListTile(
        value: s.showPreviews,
        title: const Text('Мініатюри ПК у списку'),
        onChanged: (v) => set(s.copyWith(showPreviews: v)),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<KeyboardCapture>(
          initialValue: s.keyboardCapture,
          decoration: const InputDecoration(labelText: 'Клавіші Win, Alt+Tab тощо надсилати на віддалений ПК'),
          items: const [
            DropdownMenuItem(value: KeyboardCapture.fullscreenOnly, child: Text('Лише на весь екран')),
            DropdownMenuItem(value: KeyboardCapture.always, child: Text('Завжди')),
            DropdownMenuItem(value: KeyboardCapture.never, child: Text('Ніколи')),
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
    final list = repo.credentials.values.toList()..sort((a, b) => a.label.compareTo(b.label));
    return _pane([
      Text('Один обліковий запис можна призначити багатьом ПК. Зміна пароля діє одразу для всіх.',
          style: TextStyle(color: t.textMuted)),
      const SizedBox(height: 12),
      for (final c in list)
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(c.label),
          subtitle: Text(
            '${c.authMode == AuthMode.askPassword ? 'Питати пароль' : 'Пароль збережено'} · '
            'ПК: ${repo.connections.values.where((x) => x.credentialIds.contains(c.id)).length}',
            style: TextStyle(color: t.textMuted, fontSize: 12.5),
          ),
          onTap: () => editCredential(context, repo, existing: c),
          trailing: IconButton(
            tooltip: 'Видалити',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) => repo.deleteCredential(c.id, force: force)),
          ),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Додати обліковий запис'),
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
    final name = TextEditingController(text: g?.name ?? '');
    final addr = TextEditingController(text: g == null ? '' : (g.port == 443 ? g.host : '${g.host}:${g.port}'));
    var mode = g?.credentialMode ?? GatewayCredentialMode.sameAsPc;
    var credId = g?.credentialId;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(g == null ? 'Новий шлюз' : 'Шлюз'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: addr,
                autofocus: g == null,
                decoration: InputDecoration(labelText: 'Адреса шлюзу', hintText: 'rdgw.example.com', errorText: err),
              ),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Назва (необов\'язково)')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode == GatewayCredentialMode.sameAsPc ? '' : (credId ?? ''),
                decoration: const InputDecoration(labelText: 'Обліковий запис для шлюзу'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Той самий, що й для ПК')),
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
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Скасувати')),
            FilledButton(
              onPressed: () {
                if (parseAddress(addr.text, defaultPort: 443) == null) {
                  set(() => err = 'Некоректна адреса');
                } else {
                  Navigator.pop(c, true);
                }
              },
              child: const Text('Зберегти'),
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

  Future<void> _importWireGuard(BuildContext context) async {
    final f = await openBytes(wgTypes);
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
        toast(context,
            conf.config['extraPeersIgnored'] == true
                ? 'Імпортовано. У файлі кілька [Peer] — поки використовується перший.'
                : 'Тунель «$name» імпортовано. Ключі збережено в системному сховищі.');
      }
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    return _pane([
      _caption(context, 'RD Gateway'),
      for (final g in repo.gateways.values)
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(g.label),
          subtitle: Text(g.port == 443 ? g.host : '${g.host}:${g.port}', style: t.mono),
          onTap: () => _editGateway(context, g),
          trailing: IconButton(
            tooltip: 'Видалити',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) async => repo.deleteGateway(g.id, force: force)),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
            icon: const Icon(Icons.add), label: const Text('Додати шлюз'), onPressed: () => _editGateway(context)),
      ),
      _caption(context, 'Вбудовані тунелі'),
      Text('Тунель працює всередині MHRD: без прав адміністратора і не заважає іншому VPN. '
          'Підключення через тунелі запрацює на етапі 4.',
          style: TextStyle(color: t.textMuted, fontSize: 13)),
      const SizedBox(height: 8),
      for (final tu in repo.tunnels.values)
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(tu.name),
          subtitle: Text('${tu.config['endpoint'] ?? ''} · ПК: ${repo.usersOfTunnel(tu.id)}', style: t.mono),
          trailing: IconButton(
            tooltip: 'Видалити',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _guardedDelete(context, (force) => repo.deleteTunnel(tu.id, force: force)),
          ),
        ),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Імпортувати WireGuard .conf'),
          onPressed: () => _importWireGuard(context),
        ),
      ]),
      _caption(context, 'Проксі й SSH'),
      Text('З\'являться на етапі 6.', style: TextStyle(color: t.textMuted, fontSize: 13)),
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
    final name = await promptText(context,
        title: g == null ? 'Нова група' : 'Перейменувати групу', label: 'Назва', initial: g?.name ?? '');
    if (name == null || name.trim().isEmpty) return;
    repo.saveGroup(g == null ? Group(id: newId(), name: name.trim()) : g.copyWith(name: name.trim()));
  }

  Future<void> _setParent(BuildContext context, Group g) async {
    final others = repo.groups.values.where((x) => x.id != g.id).toList()
      ..sort((a, b) => _path(a).compareTo(_path(b)));
    final i = await pickOne(context, title: 'Вкласти «${g.name}» у…', options: ['Верхній рівень', ...others.map(_path)]);
    if (i == null) return;
    try {
      repo.saveGroup(g.copyWith(parentId: () => i == 0 ? null : others[i - 1].id));
    } on StateError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  Future<void> _delete(BuildContext context, Group g) async {
    final others = repo.groups.values.where((x) => x.id != g.id).toList();
    final hasContent = repo.countInGroup(g.id) > 0 || repo.groups.values.any((x) => x.parentId == g.id);
    String? moveTo;
    if (hasContent) {
      final i = await pickOne(context,
          title: 'Куди перенести вміст групи «${g.name}»?', options: ['Збережені ПК', ...others.map(_path)]);
      if (i == null) return;
      moveTo = i == 0 ? null : others[i - 1].id;
    } else if (!await confirm(context, title: 'Видалити групу «${g.name}»?', ok: 'Видалити', danger: true)) {
      return;
    }
    repo.deleteGroup(g.id, moveTo: moveTo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final list = repo.groups.values.toList()..sort((a, b) => _path(a).compareTo(_path(b)));
    return _pane([
      ListTile(
        leading: const Icon(Icons.folder_special_outlined),
        title: const Text('Збережені ПК'),
        subtitle: Text('Стандартна група · ПК: ${repo.countInGroup(null)}', style: TextStyle(color: t.textMuted)),
      ),
      for (final g in list)
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(_path(g)),
          subtitle: Text('ПК: ${repo.countInGroup(g.id)}', style: TextStyle(color: t.textMuted)),
          onTap: () => _edit(context, g),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: 'Вкласти в іншу групу',
                icon: const Icon(Icons.drive_file_move_outline),
                onPressed: () => _setParent(context, g)),
            IconButton(
                tooltip: 'Видалити', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, g)),
          ]),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
            icon: const Icon(Icons.add), label: const Text('Нова група'), onPressed: () => _edit(context)),
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
    final pw = await promptNewPassword(context, title: 'Пароль для бекапу');
    if (pw == null || !context.mounted) return;
    toast(context, 'Шифрую бекап…');
    final bytes = await BackupService(repo).exportEncrypted(pw);
    final path = await saveBytes(bytes, 'mhrd-backup-$_stamp.rdpbackup', backupTypes);
    if (path == null) return;
    repo.updateSettings(repo.settings.copyWith(lastBackupAt: DateTime.now()));
    if (context.mounted) toast(context, 'Бекап збережено: $path');
  }

  Future<void> _import(BuildContext context) async {
    final f = await openBytes(backupTypes);
    if (f == null || !context.mounted) return;
    final pw = await promptText(context, title: 'Пароль бекапу', label: 'Пароль', obscure: true, ok: 'Відкрити');
    if (pw == null || !context.mounted) return;
    final svc = BackupService(repo);
    final Map<String, dynamic> data;
    try {
      toast(context, 'Розшифровую…');
      data = await svc.decrypt(f.$2, pw);
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
      return;
    }
    if (!context.mounted) return;
    final mode = await pickOne(context, title: 'Як відновити?', options: const [
      'Об\'єднати з поточними даними',
      'Замінити все (поточні дані спершу збережуться в автобекап)',
    ]);
    if (mode == null || !context.mounted) return;
    final replace = mode == 1;
    final pv = svc.preview(data, replaceAll: replace);
    final ok = await confirm(context,
        title: 'Відновити бекап?',
        body: 'Буде додано ПК: ${pv.added}, оновлено: ${pv.updated}, видалено: ${pv.removed}.',
        ok: 'Відновити',
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
      if (context.mounted) toast(context, 'Бекап відновлено.');
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  Future<void> _exportShare(BuildContext context) async {
    final json = const JsonEncoder.withIndent('  ').convert(BackupService(repo).exportShare(repo.connections.values));
    final path = await saveBytes(Uint8List.fromList(utf8.encode(json)), 'mhrd-pcs-$_stamp.json', shareTypes);
    if (path != null && context.mounted) toast(context, 'Збережено без паролів: $path');
  }

  Future<void> _importShare(BuildContext context) async {
    final f = await openBytes(shareTypes);
    if (f == null) return;
    try {
      final data = jsonDecode(utf8.decode(f.$2));
      if (data is! Map<String, dynamic>) throw const FormatException('Це не файл експорту MHRD.');
      await BackupService(repo).importShare(data);
      if (context.mounted) toast(context, 'Імпортовано. Паролі введіть при першому підключенні.');
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final last = repo.settings.lastBackupAt;
    return _pane([
      _caption(context, 'Повний бекап'),
      Text('Усі ПК, облікові записи з паролями, шлюзи, тунелі з ключами, групи, теми й налаштування. '
          'Файл шифрується вашим паролем (Argon2id + AES-256-GCM) і відкривається на будь-якій ОС.',
          style: TextStyle(color: t.textMuted)),
      const SizedBox(height: 6),
      Text(last == null ? 'Бекап ще не робили.' : 'Останній бекап: ${last.toLocal()}',
          style: TextStyle(color: last == null ? t.warn : t.textMuted, fontSize: 13)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
            icon: const Icon(Icons.lock_outline), label: const Text('Зберегти бекап'), onPressed: () => _export(context)),
        OutlinedButton.icon(
            icon: const Icon(Icons.restore), label: const Text('Відновити з бекапу'), onPressed: () => _import(context)),
      ]),
      _caption(context, 'Поділитися списком ПК'),
      Text('Файл без жодного пароля чи ключа — щоб передати список колезі.', style: TextStyle(color: t.textMuted)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(
            icon: const Icon(Icons.ios_share), label: const Text('Експортувати'), onPressed: () => _exportShare(context)),
        OutlinedButton.icon(
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Імпортувати'),
            onPressed: () => _importShare(context)),
      ]),
    ]);
  }
}
