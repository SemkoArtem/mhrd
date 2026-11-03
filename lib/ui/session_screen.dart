import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/connection.dart';
import '../sessions/scancodes.dart';
import '../sessions/session_manager.dart';
import '../sessions/session_protocol.dart';
import '../theme/mhrd_theme.dart';
import 'session_bar.dart';
import 'touch_session.dart';

/// Екран одного сеансу: картинка віддаленого ПК (піксель у піксель з урахуванням масштабу ОС),
/// клавіатура й миша, повний екран із плашкою, що ховається, діалог сертифіката, пояснення
/// причини відключення. Вкладки — етап 3.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.session, this.onRetry});

  final RdpSession session;

  /// «Підключитись знову» — головний екран заново проходить підключення (з паролем, якщо треба).
  final VoidCallback? onRetry;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _focus = FocusNode(debugLabel: 'rdp-session');
  final _pressed = <int>{};
  int _buttons = 0;
  double _wheelRest = 0;
  bool _certDialogOpen = false;
  Timer? _resizeTimer;
  Size? _viewSize;

  /// Фізичних пікселів на логічну точку (масштаб Windows 150% → 1.5). Віддалений екран
  /// просимо у фізичних пікселях — інакше ОС розтягує картинку і вона розмита.
  double _dpr = 1;

  bool _fullscreen = false;
  bool _wasMaximized = false;
  bool _barShown = false;
  bool _barPinned = false;

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Телефон, планшет: дотики як миша (touch_session.dart), картинка на весь екран.
  static bool get _touch => Platform.isAndroid || Platform.isIOS;

  /// Екранна клавіатура телефона для сеансу (невидиме поле RemoteKeyboard).
  final _keyboardFocus = FocusNode(debugLabel: 'rdp-keyboard');

  /// Телефон: «Дотик» — пальці справжніми дотиками у Windows (як у клієнта Microsoft), інакше «Миша».
  late bool _directTouch = !_manager.repo.settings.touchAsMouse;

  /// Телефон: плашка відкрита (типово згорнута в ручку біля краю).
  final _barOpen = ValueNotifier(false);

  /// Розмір вікна змінився: через 300 мс після останньої зміни просимо сервер про нову
  /// роздільність (SPEC → «Зміна розміру вікна»). Поки тягнуть — картинка масштабується.
  /// На весь екран — завжди заповнюємо екран, незалежно від режиму ПК.
  void _onViewSize(Size size) {
    // Телефон: виїхала екранна клавіатура — роздільність ПК не чіпаємо (лише поворот екрана).
    if (_touch && MediaQuery.viewInsetsOf(context).bottom > 0) return;
    if (!_followsWindow || size == _viewSize) return;
    _viewSize = size;
    _scheduleResize(size);
  }

  bool get _followsWindow =>
      _touch || _fullscreen || s.connection.display.resizeMode == ResizeMode.changeResolution;

  /// Сервер надіслав картинку іншого розміру, ніж вікно (наприклад, проігнорував ранній запит) —
  /// просимо ще раз. RdpSession не повторює той самий запит, тож циклу немає.
  int _lastSurface = 0;
  void _checkSurface() {
    final surface = s.width * 100000 + s.height;
    if (surface == _lastSurface) return;
    _lastSurface = surface;
    final v = _viewSize;
    if (v != null && _followsWindow) _scheduleResize(v);
  }

  void _scheduleResize(Size size) {
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) s.requestResize((size.width * _dpr).floor(), (size.height * _dpr).floor());
    });
  }

  /// Повний екран: вікно на весь монітор, робочий стіл ПК заповнює його (після зміни
  /// роздільності), зверху — плашка з панеллю, що ховається.
  Future<void> _setFullscreen(bool on) async {
    if (!_desktop || on == _fullscreen) return;
    if (on) {
      // window_manager для розгорнутого вікна не прибирає заголовок (лишається рамка «mhrd»
      // і смуги) — тож спершу відновлюємо звичайний розмір, а після виходу розгортаємо знову.
      _wasMaximized = await windowManager.isMaximized();
      if (_wasMaximized) await windowManager.unmaximize();
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      if (_wasMaximized) await windowManager.maximize();
    }
    if (!mounted) return;
    setState(() {
      _fullscreen = on;
      _barShown = false;
    });
    _focus.requestFocus();
  }

  late final SessionManager _manager = AppScope.of(context).sessions;

  RdpSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    // Телефон: сеанс на весь екран, системні панелі — лише свайпом від краю.
    if (_touch) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // «Запуск на весь екран»: налаштування ПК, інакше загальне.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (s.connection.display.startFullscreen ?? _manager.repo.settings.startFullscreen) _setFullscreen(true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manager; // запам'ятати, поки контекст живий: у dispose звертатись до AppScope не можна
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    _resizeTimer?.cancel();
    if (_fullscreen) {
      windowManager.setFullScreen(false).then((_) {
        if (_wasMaximized) windowManager.maximize();
      });
    }
    _releaseKeys();
    _manager.close(s);
    _focus.dispose();
    _keyboardFocus.dispose();
    _barOpen.dispose();
    if (_touch) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    _checkSurface();
    final cert = s.pendingCertificate;
    if (cert != null && !_certDialogOpen) _askCertificate(cert);
  }

  Future<void> _askCertificate(CertificateEvent cert) async {
    _certDialogOpen = true;
    final r = await showDialog<(bool, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          CertificateDialog(cert: cert, canRemember: _manager.repo.connections.containsKey(s.connection.id)),
    );
    _certDialogOpen = false;
    if (!mounted) return;
    final (accept, remember) = r ?? (false, false);
    if (accept && remember) _manager.trustCertificate(s, cert.fingerprint);
    s.answerCertificate(accept);
    _focus.requestFocus();
  }

  // ── Клавіатура ────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // Ctrl+Alt+Enter — повний екран і назад (не йде на віддалений ПК).
    final hw = HardwareKeyboard.instance;
    if (e is KeyDownEvent &&
        (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        hw.isControlPressed &&
        hw.isAltPressed) {
      _releaseKeys();
      _setFullscreen(!_fullscreen);
      return KeyEventResult.handled;
    }
    final code = rdpScancode(e.physicalKey.usbHidUsage);
    if (code == null) return KeyEventResult.ignored;
    final down = e is! KeyUpEvent;
    if (down) {
      _pressed.add(code);
    } else {
      _pressed.remove(code);
    }
    s.sendKey(code, down);
    return KeyEventResult.handled;
  }

  /// Вікно втратило фокус — відпускаємо все, що натиснуто, щоб на ПК не «залип» Ctrl чи Alt.
  void _releaseKeys() {
    for (final code in _pressed) {
      s.sendKey(code, false);
    }
    _pressed.clear();
  }

  // ── Миша ──────────────────────────────────────────────────────

  /// Логічна точка в картинці → піксель віддаленого екрана.
  (int, int) _pos(Offset p) => (
        (p.dx * _dpr).floor().clamp(0, s.width > 0 ? s.width - 1 : 0),
        (p.dy * _dpr).floor().clamp(0, s.height > 0 ? s.height - 1 : 0),
      );

  void _onPointer(PointerEvent e) {
    final (x, y) = _pos(e.localPosition);
    if (e is PointerDownEvent) _focus.requestFocus();
    final changed = e.buttons ^ _buttons;
    if (changed == 0) {
      if (e is PointerHoverEvent || e is PointerMoveEvent) s.sendMouseMove(x, y);
      return;
    }
    for (final (bit, b) in const [
      (kPrimaryMouseButton, RemoteButton.left),
      (kSecondaryMouseButton, RemoteButton.right),
      (kMiddleMouseButton, RemoteButton.middle),
    ]) {
      if (changed & bit != 0) s.sendMouseButton(b, e.buttons & bit != 0, x, y);
    }
    _buttons = e.buttons;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final (x, y) = _pos(e.localPosition);
    // Flutter дає пікселі (≈50 на крок коліщатка), RDP — 120 на крок; знак протилежний.
    _wheelRest += -e.scrollDelta.dy * 2.4;
    final delta = _wheelRest.truncate().clamp(-255, 255);
    _wheelRest -= delta;
    s.sendWheel(delta, x: x, y: y);
    if (e.scrollDelta.dx != 0) {
      s.sendWheel((e.scrollDelta.dx * 2.4).round().clamp(-255, 255), horizontal: true, x: x, y: y);
    }
  }

  // ── Розмітка ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    _dpr = MediaQuery.devicePixelRatioOf(context);
    if (_touch) {
      final live = s.image != null && s.state == SessionState.connected;
      final settings = _manager.repo.settings;
      return Scaffold(
        backgroundColor: Colors.black,
        // Клавіатура телефона — поверх картинки (типово) або зсуває її (налаштування).
        resizeToAvoidBottomInset: settings.keyboardShiftsScreen,
        body: Stack(children: [
          Positioned.fill(child: _body(context)),
          // Рядок спецклавіш — над екранною клавіатурою.
          if (live)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.viewInsetsOf(context).bottom,
              child: RemoteKeyboard(session: s, focusNode: _keyboardFocus),
            ),
          Positioned.fill(
            child: FloatingSessionBar(
              expanded: _barOpen,
              placement: settings.bar,
              onPlacement: (p) => _manager.repo.updateSettings(_manager.repo.settings.copyWith(bar: p)),
              actions: _touchActions(context),
              statusColor: switch (s.state) {
                SessionState.connected => t.ok,
                SessionState.failed => t.error,
                _ => t.warn,
              },
              collapseTooltip: context.l10n.barCollapse,
            ),
          ),
        ]),
      );
    }
    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: _body(context)),
          Positioned(top: 0, left: 0, right: 0, child: _fullscreenBar(context)),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: t.surface, border: Border(bottom: BorderSide(color: t.border))),
            child: _barRow(context),
          ),
          Expanded(child: _body(context)),
        ]),
      ),
    );
  }

  /// Телефон: дії плашки — дотик/миша, клавіатура, відключитись, закрити. Після дії плашка ховається.
  List<BarAction> _touchActions(BuildContext context) {
    final l = context.l10n;
    final live = s.isActive && s.image != null;
    final kbOpen = _keyboardFocus.hasFocus;
    void then(VoidCallback f) {
      f();
      _barOpen.value = false;
    }

    return [
      if (live)
        (
          icon: _directTouch ? Icons.touch_app_outlined : Icons.mouse_outlined,
          tooltip: _directTouch ? l.touchModeMouse : l.touchModeDirect,
          onTap: () => then(() {
            setState(() => _directTouch = !_directTouch);
            _manager.repo.updateSettings(_manager.repo.settings.copyWith(touchAsMouse: !_directTouch));
          }),
        ),
      if (live)
        (
          icon: kbOpen ? Icons.keyboard_hide_outlined : Icons.keyboard_outlined,
          tooltip: l.onScreenKeyboard,
          onTap: () => then(() {
            if (kbOpen) {
              _keyboardFocus.unfocus();
            } else {
              _keyboardFocus.requestFocus();
              SystemChannels.textInput.invokeMethod('TextInput.show');
            }
            setState(() {});
          }),
        ),
      if (s.isActive) (icon: Icons.power_settings_new, tooltip: l.disconnectAction, onTap: () => then(s.disconnect)),
      (
        icon: Icons.close,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onTap: () => Navigator.maybePop(context),
      ),
    ];
  }

  /// Вміст панелі сеансу (і звичайної, і повноекранної).
  Widget _barRow(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    return Row(children: [
      if (!_fullscreen)
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
      if (_fullscreen)
        IconButton(
          tooltip: _barPinned ? l.unpinBar : l.pinBar,
          icon: Icon(_barPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
          onPressed: () => setState(() => _barPinned = !_barPinned),
        ),
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: switch (s.state) {
            SessionState.connected => t.ok,
            SessionState.failed => t.error,
            _ => t.warn,
          },
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(s.connection.displayName,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
      ),
      if (_desktop)
        IconButton(
          tooltip: _fullscreen ? l.exitFullscreen : l.fullscreen,
          icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 20),
          onPressed: () => _setFullscreen(!_fullscreen),
        ),
      if (s.isActive)
        TextButton.icon(
          icon: const Icon(Icons.power_settings_new, size: 18),
          label: Text(l.disconnectAction),
          onPressed: s.disconnect,
        ),
    ]);
  }

  /// Повний екран: зверху по центру — тонка плашка. Навели мишу — з'являється панель;
  /// відвели — ховається (якщо не закріплена).
  Widget _fullscreenBar(BuildContext context) {
    final t = context.mhrd;
    final open = _barShown || _barPinned;
    return Align(
      alignment: Alignment.topCenter,
      child: MouseRegion(
        onEnter: (_) => setState(() => _barShown = true),
        onExit: (_) {
          if (!_barPinned) setState(() => _barShown = false);
        },
        child: AnimatedSize(
          duration: t.fast,
          child: open
              ? Container(
                  width: 560,
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(t.radius)),
                  ),
                  child: _barRow(context),
                )
              : GestureDetector(
                  onTap: () => setState(() => _barShown = true),
                  child: Container(
                    width: 120,
                    height: 8,
                    decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(t.radius)),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final ended = s.ended;
    if (ended != null && ended.reason != DisconnectReason.userRequest) {
      return _Message(
        icon: Icons.error_outline,
        color: t.error,
        title: l.disconnectReason(ended.reason),
        details: ended.details.isEmpty && ended.code == 0
            ? null
            : l.sessionDetails(ended.details.isEmpty ? '—' : ended.details, '0x${ended.code.toRadixString(16)}'),
        actions: [
          if (widget.onRetry != null) FilledButton(onPressed: widget.onRetry, child: Text(l.retry)),
          OutlinedButton(onPressed: () => Navigator.maybePop(context), child: Text(l.close)),
        ],
      );
    }
    if (ended != null) {
      return _Message(
        icon: Icons.link_off,
        color: t.textMuted,
        title: l.reasonUserRequest,
        actions: [
          if (widget.onRetry != null) FilledButton(onPressed: widget.onRetry, child: Text(l.retry)),
          OutlinedButton(onPressed: () => Navigator.maybePop(context), child: Text(l.close)),
        ],
      );
    }
    final img = s.image;
    if (img == null || s.state != SessionState.connected) {
      return _Message(
        progress: true,
        color: t.textMuted,
        title:
            s.state == SessionState.negotiating ? l.sessionNegotiating : l.sessionConnecting(s.connection.displayName),
      );
    }
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      onFocusChange: (has) {
        if (!has) _releaseKeys();
      },
      child: LayoutBuilder(builder: (context, box) {
        _onViewSize(box.biggest);
        if (_touch) {
          return TouchSurface(
              session: s, image: img, direct: _directTouch, onTouch: () => _barOpen.value = false);
        }
        // Розмір картинки в логічних точках: 1 піксель ПК = 1 фізичний піксель екрана.
        final w = s.width / _dpr, h = s.height / _dpr;
        final exact = (box.maxWidth - w).abs() < 1 && (box.maxHeight - h).abs() < 1;
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: Listener(
                onPointerHover: _onPointer,
                onPointerMove: _onPointer,
                onPointerDown: _onPointer,
                onPointerUp: _onPointer,
                onPointerSignal: _onSignal,
                child: SizedBox(
                  width: w,
                  height: h,
                  // Піксель у піксель — без згладжування (воно й розмиває); масштаб — зі згладжуванням.
                  child: RawImage(image: img, filterQuality: exact ? FilterQuality.none : FilterQuality.medium),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    this.icon,
    this.progress = false,
    required this.color,
    required this.title,
    this.details,
    this.actions = const [],
  });

  final IconData? icon;
  final bool progress;
  final Color color;
  final String title;
  final String? details;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    return ColoredBox(
      color: t.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (progress)
              const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3))
            else if (icon != null)
              Icon(icon, size: 44, color: color),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: t.text, fontSize: 16)),
            if (details != null) ...[
              const SizedBox(height: 10),
              SelectableText(details!, textAlign: TextAlign.center, style: t.mono),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: actions),
            ],
          ]),
        ),
      ),
    );
  }
}

/// «Довіряти сертифікату?» — для зміненого сертифіката червоне попередження й без тихої згоди.
/// Повертає (довіряти, запам'ятати).
class CertificateDialog extends StatefulWidget {
  const CertificateDialog({super.key, required this.cert, required this.canRemember});
  final CertificateEvent cert;

  /// ПК збережено в списку — є де запам'ятати відбиток.
  final bool canRemember;

  @override
  State<CertificateDialog> createState() => _CertificateDialogState();
}

class _CertificateDialogState extends State<CertificateDialog> {
  bool _remember = true;

  @override
  Widget build(BuildContext context) {
    final cert = widget.cert;
    final t = context.mhrd;
    final l = context.l10n;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: t.textMuted, fontSize: 12)),
            SelectableText(value.isEmpty ? '—' : value, style: t.mono.copyWith(color: t.text)),
          ]),
        );
    final host = cert.port == 3389 || cert.port == 0 ? cert.host : '${cert.host}:${cert.port}';
    return AlertDialog(
      icon: Icon(cert.changed ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
          color: cert.changed ? t.error : t.accent),
      title: Text(cert.changed ? l.certChangedTitle : l.certTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cert.changed)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: t.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(t.radius * 0.6),
                  border: Border.all(color: t.error),
                ),
                child: Text(l.certChangedWarning, style: TextStyle(color: t.error)),
              ),
            Text(l.certIntro(host)),
            row(l.certSubject, cert.subject),
            row(l.certIssuer, cert.issuer),
            row(l.certFingerprint, cert.fingerprint),
            if (widget.canRemember)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _remember,
                  title: Text(l.certRemember),
                  onChanged: (v) => setState(() => _remember = v ?? false),
                ),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, (false, false)), child: Text(l.certReject)),
        FilledButton(
          style: cert.changed ? FilledButton.styleFrom(backgroundColor: t.error, foregroundColor: t.background) : null,
          onPressed: () => Navigator.pop(context, (true, widget.canRemember && _remember)),
          child: Text(l.certAccept),
        ),
      ],
    );
  }
}
