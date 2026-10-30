import 'package:flutter/material.dart';

import '../../models/connection.dart';
import '../../models/entities.dart';
import '../../storage/repository.dart';
import '../../theme/mhrd_theme.dart';

/// Дії над ПК, які передає головний екран.
class PcActions {
  const PcActions({
    required this.connect,
    required this.edit,
    required this.duplicate,
    required this.exportRdp,
    required this.moveToGroup,
    required this.delete,
  });

  final void Function(Connection c, {String? credentialId}) connect;
  final void Function(Connection c) edit;
  final void Function(Connection c) duplicate;
  final void Function(Connection c) exportRdp;
  final void Function(Connection c) moveToGroup;
  final void Function(Connection c) delete;
}

String routeLabel(Repository repo, Connection c) {
  final base = switch (c.route) {
    RouteKind.direct => 'Напряму',
    RouteKind.tunnel => repo.tunnels[c.routeRefId]?.name ?? 'Тунель (не знайдено)',
    RouteKind.proxy => repo.proxies[c.routeRefId]?.name ?? 'Проксі (не знайдено)',
    RouteKind.ssh => repo.ssh[c.routeRefId]?.name ?? 'SSH (не знайдено)',
  };
  final gw = repo.gateways[c.gatewayId];
  return gw == null ? base : (c.route == RouteKind.direct ? 'RD Gateway · ${gw.label}' : '$base + шлюз');
}

String accountLabel(Repository repo, Connection c) {
  final creds = c.credentialIds.map((id) => repo.credentials[id]).whereType<Credential>().toList();
  if (creds.isEmpty) return 'Питати щоразу';
  if (creds.length == 1) return creds.first.username;
  return '${creds.length} акаунти';
}

/// Плитка ПК (вигляд «Плитки»).
class PcTile extends StatefulWidget {
  const PcTile({super.key, required this.connection, required this.repo, required this.actions});

  final Connection connection;
  final Repository repo;
  final PcActions actions;

  @override
  State<PcTile> createState() => _PcTileState();
}

class _PcTileState extends State<PcTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final c = widget.connection;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: t.fast,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.radius + 2),
          border: Border.all(color: _hover ? t.accent : t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.actions.connect(c),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 116,
                color: t.surfaceRaised.withValues(alpha: 0.6),
                child: Stack(children: [
                  Center(child: Icon(Icons.desktop_windows_outlined, size: 40, color: t.textMuted)),
                  Positioned(left: 10, top: 10, child: _StatusChip(label: 'Не підключено', color: t.textMuted)),
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
                  Tag(text: routeLabel(widget.repo, c)),
                  Tag(text: accountLabel(widget.repo, c)),
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
  const PcRow({super.key, required this.connection, required this.repo, required this.actions});

  final Connection connection;
  final Repository repo;
  final PcActions actions;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final c = connection;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius),
        onTap: () => actions.connect(c),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: t.gap * 1.25),
          child: Row(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: t.textMuted, shape: BoxShape.circle)),
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
            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Tag(text: routeLabel(repo, c)))),
            Expanded(
              flex: 2,
              child: Text(accountLabel(repo, c),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textMuted, fontSize: 13)),
            ),
            PcMenu(connection: c, repo: repo, actions: actions),
          ]),
        ),
      ),
    );
  }
}

/// Меню «⋯» ПК: підключитись як…, редагувати, дублювати, експорт .rdp, перемістити, видалити.
class PcMenu extends StatelessWidget {
  const PcMenu({super.key, required this.connection, required this.repo, required this.actions});

  final Connection connection;
  final Repository repo;
  final PcActions actions;

  @override
  Widget build(BuildContext context) {
    final c = connection;
    final creds = c.credentialIds.map((id) => repo.credentials[id]).whereType<Credential>().toList();
    return PopupMenuButton<String>(
      tooltip: 'Більше дій',
      icon: Icon(Icons.more_horiz, color: context.mhrd.textMuted),
      onSelected: (v) {
        if (v.startsWith('as:')) {
          actions.connect(c, credentialId: v.substring(3));
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
            case 'delete':
              actions.delete(c);
          }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'connect', child: Text('Підключитись')),
        for (final cr in creds.length > 1 ? creds : const <Credential>[])
          PopupMenuItem(value: 'as:${cr.id}', child: Text('Підключитись як ${cr.label}')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'edit', child: Text('Редагувати')),
        const PopupMenuItem(value: 'dup', child: Text('Дублювати')),
        const PopupMenuItem(value: 'rdp', child: Text('Експортувати .rdp')),
        const PopupMenuItem(value: 'move', child: Text('Перемістити в групу')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Видалити')),
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
