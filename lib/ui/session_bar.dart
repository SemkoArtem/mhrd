import 'package:flutter/material.dart';

import '../models/entities.dart';
import '../theme/mhrd_theme.dart';

/// Кнопка плашки сеансу.
typedef BarAction = ({IconData icon, String tooltip, VoidCallback onTap});

/// Плашка сеансу на телефоні: живе біля будь-якого краю екрана й має відповідну орієнтацію (рядок
/// біля верху й низу, стовпчик біля боків). Згорнута — маленька ручка: торкнутись чи провести від
/// краю — відкрити, потягнути — перенести до іншого краю. Відкриту переносять за хват, ховають
/// кнопкою «згорнути» (або сама, коли торкнулись картинки — [expanded] керує екран сеансу).
/// Місце запам'ятовується ([placement] / [onPlacement]), як і плашка вікна сеансу на ПК.
class FloatingSessionBar extends StatefulWidget {
  const FloatingSessionBar({
    super.key,
    required this.expanded,
    required this.placement,
    required this.onPlacement,
    required this.actions,
    required this.statusColor,
    required this.collapseTooltip,
  });

  final ValueNotifier<bool> expanded;
  final BarPlacement placement;
  final ValueChanged<BarPlacement> onPlacement;
  final List<BarAction> actions;
  final Color statusColor;
  final String collapseTooltip;

  @override
  State<FloatingSessionBar> createState() => _FloatingSessionBarState();
}

class _FloatingSessionBarState extends State<FloatingSessionBar> {
  static const _button = 44.0, _gap = 6.0, _handleLong = 56.0, _handleShort = 14.0;

  Offset? _drag; // де зараз палець, поки плашку чи ручку тягнуть
  Offset _dragStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.expanded.addListener(_changed);
  }

  @override
  void didUpdateWidget(FloatingSessionBar old) {
    super.didUpdateWidget(old);
    if (old.expanded != widget.expanded) {
      old.expanded.removeListener(_changed);
      widget.expanded.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.expanded.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  static bool _horizontal(BarEdge e) => e == BarEdge.top || e == BarEdge.bottom;

  /// Найближчий край до точки [p] і місце вздовж нього (0..1).
  static (BarEdge, double) _nearest(Offset p, Size size) {
    final d = {
      BarEdge.top: p.dy,
      BarEdge.bottom: size.height - p.dy,
      BarEdge.left: p.dx,
      BarEdge.right: size.width - p.dx,
    };
    final edge = d.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
    final along = _horizontal(edge) ? p.dx / size.width : p.dy / size.height;
    return (edge, along.clamp(0.0, 1.0));
  }

  /// Куди «всередину екрана» від краю — для свайпу, що відкриває плашку.
  static Offset _inward(BarEdge e) => switch (e) {
        BarEdge.top => const Offset(0, 1),
        BarEdge.bottom => const Offset(0, -1),
        BarEdge.left => const Offset(1, 0),
        BarEdge.right => const Offset(-1, 0),
      };

  // Плашка лежить поверх усього екрана сеансу, тож координати екрана = координати шару.
  void _start(DragStartDetails d) => setState(() => _dragStart = _drag = d.globalPosition);

  void _update(DragUpdateDetails d) => setState(() => _drag = d.globalPosition);

  void _end(Size size, BarEdge edge, {required bool handle}) {
    final end = _drag;
    setState(() => _drag = null);
    if (end == null) return;
    final moved = end - _dragStart;
    if (handle) {
      // Ручка: провели від краю всередину — відкрити.
      final inward = moved.dx * _inward(edge).dx + moved.dy * _inward(edge).dy;
      final along = (moved.dx * _inward(edge).dy).abs() + (moved.dy * _inward(edge).dx).abs();
      if (inward > 24 && inward > along) {
        widget.expanded.value = true;
        return;
      }
    }
    if (moved.distance < 12) return;
    final (e, pos) = _nearest(end, size);
    widget.onPlacement(BarPlacement(edge: e, pos: (pos * 10000).round(), length: widget.placement.length));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      // Поки тягнуть — край і місце за пальцем (орієнтація змінюється на льоту).
      final (edge, pos) =
          _drag != null ? _nearest(_drag!, size) : (widget.placement.edge, widget.placement.pos / 10000);
      final horizontal = _horizontal(edge);
      final expanded = widget.expanded.value;

      final Widget body;
      final Size extent;
      if (expanded) {
        final n = widget.actions.length + 2; // хват + дії + згорнути
        final long = n * _button + 18; // + точка стану
        extent = horizontal ? Size(long, _button) : Size(_button, long);
        final children = <Widget>[
          GestureDetector(
            onPanStart: _start,
            onPanUpdate: _update,
            onPanEnd: (_) => _end(size, edge, handle: false),
            child: SizedBox.square(
                dimension: _button, child: Icon(Icons.drag_indicator, size: 20, color: t.textMuted)),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.statusColor),
          ),
          for (final a in widget.actions)
            IconButton(tooltip: a.tooltip, icon: Icon(a.icon, size: 20), onPressed: a.onTap),
          IconButton(
            tooltip: widget.collapseTooltip,
            icon: Icon(
                switch (edge) {
                  BarEdge.top => Icons.keyboard_arrow_up,
                  BarEdge.bottom => Icons.keyboard_arrow_down,
                  BarEdge.left => Icons.keyboard_arrow_left,
                  BarEdge.right => Icons.keyboard_arrow_right,
                },
                size: 22),
            onPressed: () => widget.expanded.value = false,
          ),
        ];
        body = Container(
          decoration: BoxDecoration(
            color: t.surface.withValues(alpha: 0.92),
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(_button / 2),
          ),
          child: horizontal
              ? Row(mainAxisSize: MainAxisSize.min, children: children)
              : Column(mainAxisSize: MainAxisSize.min, children: children),
        );
      } else {
        // Ручка: смужка біля самого краю; більша невидима зона, щоб легко влучити пальцем.
        final grip = horizontal ? const Size(_handleLong, _handleShort) : const Size(_handleShort, _handleLong);
        extent = Size(grip.width + (horizontal ? 24 : 12), grip.height + (horizontal ? 12 : 24));
        const radius = Radius.circular(_handleShort / 2);
        body = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.expanded.value = true,
          onPanStart: _start,
          onPanUpdate: _update,
          onPanEnd: (_) => _end(size, edge, handle: true),
          child: Center(
            child: Container(
              width: grip.width,
              height: grip.height,
              decoration: BoxDecoration(
                color: t.surface.withValues(alpha: 0.85),
                border: Border.all(color: t.border),
                borderRadius: switch (edge) {
                  BarEdge.top => const BorderRadius.vertical(bottom: radius),
                  BarEdge.bottom => const BorderRadius.vertical(top: radius),
                  BarEdge.left => const BorderRadius.horizontal(right: radius),
                  BarEdge.right => const BorderRadius.horizontal(left: radius),
                },
              ),
              child: Icon(horizontal ? Icons.more_horiz : Icons.more_vert, size: 12, color: t.textMuted),
            ),
          ),
        );
      }

      // Відкрита плашка — з відступом від краю й системних смуг; ручка — впритул до краю.
      final inset = expanded ? _gap : 0.0;
      final w = extent.width, h = extent.height;
      double clampX(double x) => x.clamp(pad.left, size.width - pad.right - w).toDouble();
      double clampY(double y) => y.clamp(pad.top, size.height - pad.bottom - h).toDouble();
      final (left, top) = switch (edge) {
        BarEdge.top => (clampX(pos * size.width - w / 2), pad.top + inset),
        BarEdge.bottom => (clampX(pos * size.width - w / 2), size.height - pad.bottom - inset - h),
        BarEdge.left => (pad.left + inset, clampY(pos * size.height - h / 2)),
        BarEdge.right => (size.width - pad.right - inset - w, clampY(pos * size.height - h / 2)),
      };
      return Stack(children: [
        Positioned(left: left, top: top, width: w, height: h, child: body),
      ]);
    });
  }
}
