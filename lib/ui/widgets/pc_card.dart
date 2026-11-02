import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../models/connection.dart';
import '../../models/entities.dart';
import '../../platform/shell_bridge.dart';
import '../../storage/repository.dart';
import '../../theme/mhrd_theme.dart';
import '../dialogs.dart';

/// Дії над ПК, які передає головний екран.
class PcActions {
  const PcActions({
    required this.connect,
    required this.edit,
    required this.duplicate,
    required this.exportRdp,
    required this.moveToGroup,
    required this.wake,
    required this.delete,
    required this.select,
  });

  final void Function(Connection c, {String? credentialId}) connect;
  final void Function(Connection c) edit;
  final void Function(Connection c) duplicate;
  final void Function(Connection c) exportRdp;
  final void Function(Connection c) moveToGroup;
  final void Function(Connection c) wake;
  final void Function(Connection c) delete;

  /// Позначити / зняти позначку (Ctrl+клік, довге натискання, клік у режимі виділення).
  final void Function(Connection c) select;
}

/// Стан картки в списку: виділена, чи йде виділення, чи відкритий сеанс, що показати замість
/// піктограми (своя картинка або мініатюра останнього сеансу).
class PcCardState {
  const PcCardState({this.selected = false, this.selecting = false, this.connected = false, this.preview});
  final bool selected, selecting, connected;
  final File? preview;
}

/// Клік по картці: у режимі виділення або з Ctrl — позначити, інакше — підключитись.
void _tap(PcActions a, PcCardState s, Connection c) {
  final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
  s.selecting || ctrl ? a.select(c) : a.connect(c);
}

String routeLabel(AppLocalizations l, Repository repo, Connection c) {
  final base = switch (c.route) {
    RouteKind.direct => l.routeDirect,
    RouteKind.tunnel => repo.tunnels[c.routeRefId]?.label ?? l.routeTunnelMissing,
    RouteKind.proxy => repo.proxies[c.routeRefId]?.label ?? l.routeProxyMissing,
  };
  final gw = repo.gateways[c.gatewayId];
  return gw == null ? base : (c.route == RouteKind.direct ? l.routeGateway(gw.label) : l.routeWithGateway(base));
}

String accountLabel(AppLocalizations l, Repository repo, Connection c) {
  final creds = c.credentialIds.map((id) => repo.credentials[id]).whereType<Credential>().toList();
  if (creds.isEmpty) return l.credAskEveryTime;
  if (creds.length == 1) return creds.first.username;
  return l.accountsCount(creds.length);
}

/// Плитка ПК (вигляд «Плитки»).
class PcTile extends StatefulWidget {
  const PcTile(
      {super.key, required this.connection, required this.repo, required this.actions, this.state = const PcCardState()});

  final Connection connection;
  final Repository repo;
  final PcActions actions;
  final PcCardState state;

  @override
  State<PcTile> createState() => _PcTileState();
}

class _PcTileState extends State<PcTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final c = widget.connection;
    final s = widget.state;
    final preview = s.preview;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: t.fast,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: s.selected ? t.accent.withValues(alpha: 0.12) : t.surface,
          borderRadius: BorderRadius.circular(t.radius + 2),
          border: Border.all(color: s.selected || _hover ? t.accent : t.border, width: s.selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _tap(widget.actions, s, c),
          onLongPress: () => widget.actions.select(c),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 116,
                color: t.surfaceRaised.withValues(alpha: 0.6),
                child: Stack(fit: StackFit.expand, children: [
                  if (preview != null)
                    Image.file(preview,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) =>
                            Center(child: Icon(Icons.desktop_windows_outlined, size: 40, color: t.textMuted)))
                  else
                    Center(child: Icon(Icons.desktop_windows_outlined, size: 40, color: t.textMuted)),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: s.connected
                        ? _StatusChip(label: l.statusConnected, color: t.ok)
                        : _StatusChip(label: l.statusNotConnected, color: t.textMuted),
                  ),
                  if (s.selecting || _hover)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Checkbox(value: s.selected, onChanged: (_) => widget.actions.select(c)),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.text, fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(c.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.mono),
                    ]),
                  ),
                  PcMenu(connection: c, repo: widget.repo, actions: widget.actions),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  Tag(text: routeLabel(l, widget.repo, c)),
                  Tag(text: accountLabel(l, widget.repo, c)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Рядок ПК (вигляд «Список»).
class PcRow extends StatelessWidget {
  const PcRow(
      {super.key, required this.connection, required this.repo, required this.actions, this.state = const PcCardState()});

  final Connection connection;
  final Repository repo;
  final PcActions actions;
  final PcCardState state;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final c = connection;
    final s = state;
    return Material(
      color: s.selected ? t.accent.withValues(alpha: 0.12) : t.surface,
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius),
        onTap: () => _tap(actions, s, c),
        onLongPress: () => actions.select(c),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: t.gap * 1.25),
          child: Row(children: [
            if (s.selecting)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Checkbox(value: s.selected, onChanged: (_) => actions.select(c)),
              )
            else
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: s.connected ? t.ok : t.textMuted, shape: BoxShape.circle)),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
                Text(c.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.mono),
              ]),
            ),
            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Tag(text: routeLabel(l, repo, c)))),
            Expanded(
              flex: 2,
              child: Text(accountLabel(l, repo, c),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textMuted, fontSize: 13)),
            ),
            PcMenu(connection: c, repo: repo, actions: actions),
          ]),
        ),
      ),
    );
  }
}

/// Меню «⋯» ПК: підключитись як…, редагувати, дублювати, експорт .rdp, перемістити, розбудити, видалити.
class PcMenu extends StatelessWidget {
  const PcMenu({super.key, required this.connection, required this.repo, required this.actions});

  final Connection connection;
  final Repository repo;
  final PcActions actions;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = connection;
    final creds = c.credentialIds.map((id) => repo.credentials[id]).whereType<Credential>().toList();
    return PopupMenuButton<String>(
      tooltip: l.moreActions,
      icon: Icon(Icons.more_horiz, color: context.mhrd.textMuted),
      onSelected: (v) {
        if (v.startsWith('as:')) {
          actions.connect(c, credentialId: v.substring(3));
        } else if (v.startsWith('lnk:')) {
          final cr = repo.credentials[v.substring(4)];
          final name = cr == null ? c.displayName : '${c.displayName} — ${cr.label}';
          ShellBridge.instance.createShortcut(c, as: cr).then((ok) {
            if (context.mounted) toast(context, ok ? l.shortcutCreated(name) : l.shortcutFailed);
          });
        } else {
          switch (v) {
            case 'connect':
              actions.connect(c);
            case 'edit':
              actions.edit(c);
            case 'dup':
              actions.duplicate(c);
            case 'rdp':
              actions.exportRdp(c);
            case 'move':
              actions.moveToGroup(c);
            case 'wake':
              actions.wake(c);
            case 'shortcut':
              ShellBridge.instance.createShortcut(c).then((ok) {
                if (context.mounted) toast(context, ok ? l.shortcutCreated(c.displayName) : l.shortcutFailed);
              });
            case 'delete':
              actions.delete(c);
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'connect', child: Text(l.connect)),
        for (final cr in creds.length > 1 ? creds : const <Credential>[])
          PopupMenuItem(value: 'as:${cr.id}', child: Text(l.connectAs(cr.label))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'edit', child: Text(l.edit)),
        PopupMenuItem(value: 'dup', child: Text(l.duplicate)),
        PopupMenuItem(value: 'rdp', child: Text(l.exportRdp)),
        PopupMenuItem(value: 'move', child: Text(l.moveToGroup)),
        if (c.wakeOnLan != null) PopupMenuItem(value: 'wake', child: Text(l.wakeOnLan)),
        // Лише збережений ПК: ярлик запускає `mhrd.exe --connect <id>`; кілька акаунтів — ярлик
        // і для кожного з них (`--connect <id>/<акаунт>`).
        if ((Platform.isWindows || Platform.isLinux) && repo.connections.containsKey(c.id)) ...[
          PopupMenuItem(value: 'shortcut', child: Text(l.createShortcut)),
          for (final cr in creds.length > 1 ? creds : const <Credential>[])
            PopupMenuItem(value: 'lnk:${cr.id}', child: Text(l.createShortcutAs(cr.label))),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text(l.delete)),
      ],
    );
  }
}

class Tag extends StatelessWidget {
  const Tag({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: t.surfaceRaised, borderRadius: BorderRadius.circular(t.radius / 2)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 11.5)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: t.background, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ]),
    );
  }
}
