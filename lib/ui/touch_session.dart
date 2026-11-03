import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sessions/session_manager.dart';
import '../sessions/session_protocol.dart';
import '../theme/mhrd_theme.dart';

/// Сенсорний екран (телефон, планшет), два режими, як у клієнта Microsoft:
/// - «Дотик» ([direct]): пальці — справжніми дотиками у Windows (прокрутку, щипок, утримання для
///   правого кліку роблять самі програми ПК);
/// - «Миша»: екран — як тачпад ноутбука, курсор видно. Палець рухає курсор, торкання = клік
///   (двічі — подвійний), утримати й повести = перетягування, двома пальцями: торкання = правий клік,
///   рух = прокрутка, щипок = збільшити картинку.
/// Миша (Bluetooth, USB) в обох режимах — звичайна миша.
class TouchSurface extends StatefulWidget {
  const TouchSurface({super.key, required this.session, required this.image, this.direct = true, this.onTouch});

  final RdpSession session;
  final ui.Image image;
  final bool direct;

  /// Торкнулись картинки (наприклад, щоб згорнути плашку).
  final VoidCallback? onTouch;

  @override
  State<TouchSurface> createState() => _TouchSurfaceState();
}

class _TouchSurfaceState extends State<TouchSurface> {
  static const _slop = 8.0; // логічних точок — далі це вже рух, а не торкання
  static const _hold = Duration(milliseconds: 450); // утримати — почати перетягування
  static const _tapMax = Duration(milliseconds: 300);
  static const _maxZoom = 5.0;

  double _zoom = 1;
  Offset _pan = Offset.zero; // зсув збільшеної картинки, логічні точки
  Size _view = Size.zero;

  final _touches = <int, Offset>{};

  // Тачпад: курсор у пікселях віддаленого ПК.
  Offset? _cursor;
  Offset _last = Offset.zero;
  DateTime _downAt = DateTime.now();
  Timer? _holdTimer;
  bool _moved = false, _dragging = false, _consumed = false;

  // Два пальці: початкова відстань і центр, режим — масштаб чи прокрутка.
  double _pinchDist = 0, _pinchZoom = 1;
  Offset _pinchFocus = Offset.zero, _pinchPan = Offset.zero, _lastFocus = Offset.zero;
  bool _pinching = false, _twoMoved = false;
  double _wheelRest = 0;

  // Миша на телефоні — як на ПК.
  int _mouseButtons = 0;

  // Режим «Дотик»: вказівник Flutter → номер пальця для Windows (0..9).
  final _fingers = <int, int>{};

  RdpSession get s => widget.session;

  @override
  void didUpdateWidget(TouchSurface old) {
    super.didUpdateWidget(old);
    // Перейшли на «Дотик» — картинка знову ціла: збільшує вже сама Windows.
    if (widget.direct && !old.direct) {
      _zoom = 1;
      _pan = Offset.zero;
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  /// Прямокутник картинки на екрані (вписана, потім масштаб і зсув).
  Rect get _imageRect {
    final w = s.width.toDouble(), h = s.height.toDouble();
    if (w <= 0 || h <= 0 || _view.isEmpty) return Rect.zero;
    final fit = math.min(_view.width / w, _view.height / h);
    final base = Size(w * fit, h * fit);
    final origin = Offset((_view.width - base.width) / 2, (_view.height - base.height) / 2);
    final center = _view.center(Offset.zero);
    final topLeft = center + (origin - center) * _zoom + _pan;
    return topLeft & base * _zoom;
  }

  /// Точка на екрані → піксель віддаленого ПК.
  (int, int) _remote(Offset p) {
    final r = _imageRect;
    if (r.isEmpty) return (0, 0);
    final x = ((p.dx - r.left) / r.width * s.width).floor().clamp(0, math.max(0, s.width - 1)).toInt();
    final y = ((p.dy - r.top) / r.height * s.height).floor().clamp(0, math.max(0, s.height - 1)).toInt();
    return (x, y);
  }

  /// Піксель віддаленого ПК → точка на екрані.
  Offset _screen(Offset remote) {
    final r = _imageRect;
    return Offset(r.left + remote.dx / s.width * r.width, r.top + remote.dy / s.height * r.height);
  }

  /// Зсув не дає картинці виїхати за край більше, ніж на її збільшену частину.
  Offset _clampPan(Offset pan, double zoom) {
    final mx = _view.width * (zoom - 1) / 2, my = _view.height * (zoom - 1) / 2;
    return Offset(pan.dx.clamp(-mx, mx), pan.dy.clamp(-my, my));
  }

  // ── Режим «Дотик» ─────────────────────────────────────────────

  void _touch(PointerEvent e, int flags) {
    var finger = _fingers[e.pointer];
    if (flags == TouchFlags.down) {
      finger = List.generate(10, (i) => i).firstWhere((i) => !_fingers.containsValue(i), orElse: () => -1);
      if (finger < 0) return; // більше 10 пальців
      _fingers[e.pointer] = finger;
    }
    if (finger == null) return;
    final (x, y) = _remote(e.localPosition);
    s.sendTouch(flags, finger, x, y);
    if (flags == TouchFlags.up) _fingers.remove(e.pointer);
  }

  // ── Режим «Миша»: тачпад ──────────────────────────────────────

  Offset get _cursorOrCenter => _cursor ??= Offset(s.width / 2, s.height / 2);

  (int, int) get _cursorPx {
    final c = _cursorOrCenter;
    return (c.dx.round().clamp(0, math.max(0, s.width - 1)), c.dy.round().clamp(0, math.max(0, s.height - 1)));
  }

  void _button(RemoteButton b, bool down) {
    final (x, y) = _cursorPx;
    s.sendMouseButton(b, down, x, y);
  }

  void _click(RemoteButton b) {
    _button(b, true);
    _button(b, false);
  }

  /// Палець зсунувся на [delta] логічних точок — курсор слідом (пришвидшено на швидкому русі).
  void _moveCursor(Offset delta) {
    final r = _imageRect;
    if (r.isEmpty) return;
    final speed = delta.distance > 12 ? 2.2 : 1.4;
    final k = s.width / r.width * speed;
    final c = _cursorOrCenter + delta * k;
    _cursor = Offset(c.dx.clamp(0, s.width - 1.0), c.dy.clamp(0, s.height - 1.0));
    final (x, y) = _cursorPx;
    s.sendMouseMove(x, y);
    // Збільшено — картинка їде за курсором, щоб він не зник за краєм.
    if (_zoom > 1) {
      final p = _screen(_cursor!);
      const m = 40.0;
      var shift = Offset.zero;
      if (p.dx < m) shift += Offset(m - p.dx, 0);
      if (p.dx > _view.width - m) shift += Offset(_view.width - m - p.dx, 0);
      if (p.dy < m) shift += Offset(0, m - p.dy);
      if (p.dy > _view.height - m) shift += Offset(0, _view.height - m - p.dy);
      if (shift != Offset.zero) _pan = _clampPan(_pan + shift, _zoom);
    }
    setState(() {});
  }

  void _down(PointerDownEvent e) {
    widget.onTouch?.call();
    if (e.kind == PointerDeviceKind.mouse) return _mouse(e);
    if (widget.direct) return _touch(e, TouchFlags.down);
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 1) {
      _last = e.localPosition;
      _downAt = DateTime.now();
      _moved = _dragging = _consumed = false;
      _holdTimer?.cancel();
      _holdTimer = Timer(_hold, () {
        if (_moved || _touches.length != 1) return;
        // Утримали — перетягування: кнопка натиснута, поки палець на екрані.
        _dragging = true;
        HapticFeedback.mediumImpact();
        _button(RemoteButton.left, true);
      });
    } else if (_touches.length == 2) {
      _holdTimer?.cancel();
      if (_dragging) {
        _button(RemoteButton.left, false);
        _dragging = false;
      }
      _consumed = true;
      final pts = _touches.values.toList();
      _pinchDist = (pts[0] - pts[1]).distance;
      _pinchFocus = _lastFocus = (pts[0] + pts[1]) / 2;
      _pinchZoom = _zoom;
      _pinchPan = _pan;
      _pinching = _twoMoved = false;
      _downAt = DateTime.now();
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.mouse) return _mouse(e);
    if (widget.direct) return _touch(e, TouchFlags.motion);
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 1 && !_consumed) {
      final delta = e.localPosition - _last;
      if (!_moved && (e.localPosition - _last).distance < _slop && !_dragging) return;
      if (!_moved) {
        _moved = true;
        if (!_dragging) _holdTimer?.cancel();
      }
      _last = e.localPosition;
      _moveCursor(delta);
    } else if (_touches.length == 2) {
      final pts = _touches.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final focus = (pts[0] + pts[1]) / 2;
      if ((focus - _pinchFocus).distance > _slop || (dist - _pinchDist).abs() > _slop) _twoMoved = true;
      if (!_pinching && _pinchDist > 0 && (dist / _pinchDist - 1).abs() > 0.12) _pinching = true;
      if (_pinching) {
        final zoom = (_pinchZoom * dist / _pinchDist).clamp(1.0, _maxZoom);
        // Точка під пальцями лишається під пальцями.
        final center = _view.center(Offset.zero);
        final anchor = (_pinchFocus - center - _pinchPan) / _pinchZoom;
        setState(() {
          _zoom = zoom;
          _pan = _clampPan(focus - center - anchor * zoom, zoom);
        });
      } else {
        // Прокрутка під курсором: ~25 точок руху — один крок коліщатка (120).
        final dy = focus.dy - _lastFocus.dy, dx = focus.dx - _lastFocus.dx;
        final (x, y) = _cursorPx;
        _wheelRest += dy * 4.8;
        final step = _wheelRest.truncate().clamp(-255, 255);
        if (step != 0) {
          _wheelRest -= step;
          s.sendWheel(step, x: x, y: y);
        }
        if (dx.abs() > dy.abs() && dx.abs() > 2) {
          s.sendWheel((-dx * 4.8).round().clamp(-255, 255), horizontal: true, x: x, y: y);
        }
      }
      _lastFocus = focus;
    }
  }

  void _up(PointerEvent e) {
    if (e.kind == PointerDeviceKind.mouse) return _mouse(e);
    if (widget.direct) return _touch(e, TouchFlags.up);
    final was = _touches.length;
    if (_touches.remove(e.pointer) == null) return;
    final quick = DateTime.now().difference(_downAt) < _tapMax;
    if (was == 2 && !_twoMoved && !_pinching && quick && e is PointerUpEvent) {
      _click(RemoteButton.right); // дотик двома пальцями
      _twoMoved = true; // другий палець, що відпуститься, нічого не робить
      return;
    }
    if (was != 1) return;
    _holdTimer?.cancel();
    if (_dragging) {
      _button(RemoteButton.left, false);
    } else if (!_moved && !_consumed && quick && e is PointerUpEvent) {
      _click(RemoteButton.left);
    }
    _dragging = false;
  }

  /// Миша (Bluetooth / USB) на телефоні: як на ПК — рух, кнопки, коліщатко.
  void _mouse(PointerEvent e) {
    final (x, y) = _remote(e.localPosition);
    _cursor = Offset(x.toDouble(), y.toDouble());
    final changed = e.buttons ^ _mouseButtons;
    if (changed == 0) {
      if (e is PointerHoverEvent || e is PointerMoveEvent) s.sendMouseMove(x, y);
      if (!widget.direct) setState(() {});
      return;
    }
    for (final (bit, b) in const [
      (kPrimaryMouseButton, RemoteButton.left),
      (kSecondaryMouseButton, RemoteButton.right),
      (kMiddleMouseButton, RemoteButton.middle),
    ]) {
      if (changed & bit != 0) s.sendMouseButton(b, e.buttons & bit != 0, x, y);
    }
    _mouseButtons = e.buttons;
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final (x, y) = _remote(e.localPosition);
    s.sendWheel((-e.scrollDelta.dy * 2.4).round().clamp(-255, 255), x: x, y: y);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _view = box.biggest;
      final r = _imageRect;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        onPointerHover: _mouse,
        onPointerSignal: _signal,
        child: Stack(children: [
          Positioned.fromRect(
            rect: r,
            child: RawImage(image: widget.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
          // Тачпад: курсор ПК малюємо самі (сервер його в картинку не кладе).
          if (!widget.direct && !r.isEmpty)
            Positioned(
              left: _screen(_cursorOrCenter).dx,
              top: _screen(_cursorOrCenter).dy,
              child: const IgnorePointer(child: CustomPaint(size: Size(18, 26), painter: _ArrowCursor())),
            ),
        ]),
      );
    });
  }
}

/// Стрілка курсора: біла з чорним обідком, вістря — у точці (0, 0).
class _ArrowCursor extends CustomPainter {
  const _ArrowCursor();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 22)
      ..lineTo(5.5, 16.5)
      ..lineTo(9.5, 25)
      ..lineTo(13, 23.5)
      ..lineTo(9, 15.5)
      ..lineTo(16.5, 15.5)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ArrowCursor oldDelegate) => false;
}

/// Клавіатура телефона для сеансу: невидиме поле приймає текст з екранної клавіатури ОС і шле
/// його символами (кирилиця, емодзі — без розкладки на ПК), а над клавіатурою — рядок клавіш,
/// яких на ній немає: Esc, Tab, Ctrl, Alt, Win (залипають до наступної клавіші), стрілки, Del.
class RemoteKeyboard extends StatefulWidget {
  const RemoteKeyboard({super.key, required this.session, required this.focusNode});

  final RdpSession session;

  /// Фокус невидимого поля: requestFocus() відкриває екранну клавіатуру.
  final FocusNode focusNode;

  @override
  State<RemoteKeyboard> createState() => _RemoteKeyboardState();
}

class _RemoteKeyboardState extends State<RemoteKeyboard> {
  // Поле завжди містить один «якірний» символ: так видно і нові символи, і Backspace.
  static const _anchor = '​';
  final _text = TextEditingController(text: _anchor);
  final _held = <int>{}; // залиплі модифікатори (скан-коди)

  static const _esc = 0x01, _tab = 0x0F, _ctrl = 0x1D, _alt = 0x38, _win = 0x15B;
  static const _enter = 0x1C, _backspace = 0x0E, _del = 0x153;
  static const _left = 0x14B, _up = 0x148, _down = 0x150, _right = 0x14D;
  static const _home = 0x147, _end = 0x14F, _pgUp = 0x149, _pgDn = 0x151;

  RdpSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _text.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  void _reset() {
    _text.value = const TextEditingValue(text: _anchor, selection: TextSelection.collapsed(offset: 1));
  }

  void _tap(int code) {
    s.sendKey(code, true);
    s.sendKey(code, false);
  }

  /// Клавіша з урахуванням залиплих модифікаторів: натиснути їх, клавішу, відпустити все.
  void _key(int code) {
    final mods = _held.toList();
    for (final m in mods) {
      s.sendKey(m, true);
    }
    _tap(code);
    for (final m in mods.reversed) {
      s.sendKey(m, false);
    }
    if (mods.isNotEmpty) setState(_held.clear);
  }

  void _toggle(int mod) => setState(() => _held.contains(mod) ? _held.remove(mod) : _held.add(mod));

  void _changed(String value) {
    if (!value.startsWith(_anchor) || value.isEmpty) {
      // Якір стерли — це Backspace.
      _key(_backspace);
    } else {
      final typed = value.substring(_anchor.length);
      for (final ch in typed.runes) {
        final c = String.fromCharCode(ch);
        if (c == '\n') {
          _key(_enter);
        } else if (_held.isNotEmpty && c.length == 1 && RegExp(r'[a-zA-Z]').hasMatch(c)) {
          // Ctrl+C тощо: з модифікатором — клавіша, а не символ.
          _key(_letterScancode(c.toLowerCase()));
        } else {
          s.sendText(c);
        }
      }
    }
    _reset();
  }

  static int _letterScancode(String c) => const {
        'a': 0x1E,
        'b': 0x30,
        'c': 0x2E,
        'd': 0x20,
        'e': 0x12,
        'f': 0x21,
        'g': 0x22,
        'h': 0x23,
        'i': 0x17,
        'j': 0x24,
        'k': 0x25,
        'l': 0x26,
        'm': 0x32,
        'n': 0x31,
        'o': 0x18,
        'p': 0x19,
        'q': 0x10,
        'r': 0x13,
        's': 0x1F,
        't': 0x14,
        'u': 0x16,
        'v': 0x2F,
        'w': 0x11,
        'x': 0x2D,
        'y': 0x15,
        'z': 0x2C,
      }[c]!;

  void _ctrlAltDel() {
    for (final c in [_ctrl, _alt]) {
      s.sendKey(c, true);
    }
    _tap(_del);
    for (final c in [_alt, _ctrl]) {
      s.sendKey(c, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    Widget key(String label, VoidCallback onTap, {bool on = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: on ? t.accent : t.surfaceRaised,
            borderRadius: BorderRadius.circular(t.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(t.radius),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Text(label,
                    style: TextStyle(
                        fontFamily: t.fontMono,
                        fontSize: 13,
                        color: on ? t.onAccent : t.text,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        );
    final open = widget.focusNode.hasFocus;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Невидиме поле: лише щоб отримувати текст з екранної клавіатури.
      SizedBox(
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0,
          child: TextField(
            controller: _text,
            focusNode: widget.focusNode,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.newline,
            maxLines: null,
            onChanged: _changed,
          ),
        ),
      ),
      if (open)
        Container(
          color: t.surface,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              key('Esc', () => _key(_esc)),
              key('Tab', () => _key(_tab)),
              key('Ctrl', () => _toggle(_ctrl), on: _held.contains(_ctrl)),
              key('Alt', () => _toggle(_alt), on: _held.contains(_alt)),
              key('Win', () => _held.isEmpty ? _key(_win) : _toggle(_win), on: _held.contains(_win)),
              key('←', () => _key(_left)),
              key('↑', () => _key(_up)),
              key('↓', () => _key(_down)),
              key('→', () => _key(_right)),
              key('Del', () => _key(_del)),
              key('Home', () => _key(_home)),
              key('End', () => _key(_end)),
              key('PgUp', () => _key(_pgUp)),
              key('PgDn', () => _key(_pgDn)),
              key('Ctrl+Alt+Del', _ctrlAltDel),
            ]),
          ),
        ),
    ]);
  }
}
