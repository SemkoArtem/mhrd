import 'package:flutter/gestures.dart'
    show DelayedMultiDragGestureRecognizer, GestureMultiDragStartCallback, ImmediateMultiDragGestureRecognizer,
        MultiDragGestureRecognizer, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/mhrd_theme.dart';

/// Картку ПК можна перетягнути на групу. Мишею (і пером) — одразу, пальцем — після утримання
/// (інакше палець не міг би гортати список); утримання ще й позначає ПК.
/// Два окремі обробники, кожен лише для своїх пристроїв, — без перемикання «миша/палець» під час
/// дотику: перебудова картки посеред дотику губила його (перетягування спрацьовувало через раз).
class DragPc extends StatelessWidget {
  const DragPc({super.key, required this.ids, required this.label, required this.onTouchDrag, required this.child});

  final List<String> ids;
  final String label;
  final VoidCallback onTouchDrag;
  final Widget child;

  static const _pointer = {PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus};
  static const _finger = {PointerDeviceKind.touch};

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final feedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(color: t.accent, width: 2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.desktop_windows_outlined, size: 18, color: t.accent),
          const SizedBox(width: 8),
          Text(ids.length == 1 ? label : l.pcCount(ids.length),
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
    final faded = Opacity(opacity: 0.4, child: child);
    return DeviceDraggable<List<String>>(
      devices: _pointer,
      data: ids,
      feedback: feedback,
      childWhenDragging: faded,
      child: DeviceDraggable<List<String>>(
        devices: _finger,
        // Трохи раніше, ніж утримання самої картки (500 мс, «позначити»): інакше обидва спрацьовували
        // одночасно й вигравав то один, то інший. Позначає ПК тепер саме цей (onTouchDrag).
        delay: const Duration(milliseconds: 400),
        data: ids,
        feedback: feedback,
        childWhenDragging: faded,
        onDragStarted: onTouchDrag,
        child: child,
      ),
    );
  }
}

/// Draggable лише для [devices]: без [delay] — одразу (миша), з ним — після утримання (палець).
class DeviceDraggable<T extends Object> extends Draggable<T> {
  const DeviceDraggable({
    super.key,
    required this.devices,
    this.delay,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.onDragStarted,
  });

  final Set<PointerDeviceKind> devices;
  final Duration? delay;

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) {
    final wait = delay;
    final recognizer = wait == null
        ? ImmediateMultiDragGestureRecognizer(supportedDevices: devices)
        : DelayedMultiDragGestureRecognizer(delay: wait, supportedDevices: devices);
    return recognizer
      ..onStart = (position) {
        final drag = onStart(position);
        if (drag != null && wait != null) HapticFeedback.selectionClick();
        return drag;
      };
  }
}
