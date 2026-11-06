import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/connection.dart';
import '../models/entities.dart';
import '../platform/mstsc_import.dart';
import '../platform/shell_bridge.dart';
import '../sessions/session_manager.dart';
import '../sessions/session_protocol.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import '../util/address.dart';
import '../util/rdp_file.dart';
import '../util/wireguard_conf.dart' show tunnelAddress;
import '../util/wake_on_lan.dart';
import 'credential_dialog.dart';
import 'dialogs.dart';
import 'edit_connection_screen.dart';
import 'file_actions.dart';
import 'session_screen.dart';
import 'settings_screen.dart';
import 'widgets/pc_card.dart';

/// Фільтр списку: усі, нещодавні, без групи («Збережені ПК») або конкретна група.
const _all = '__all', _recent = '__recent', _saved = '__saved';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = _all;
  String _query = '';
  final _quick = TextEditingController();
  final _quickFocus = FocusNode();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    ShellBridge.instance.pendingConnect.addListener(_onShellConnect);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recentSource = repo..addListener(_syncRecent);
      _syncRecent();
      _onShellConnect(); // запустили зі списку «Недавні» — підключаємось одразу
    });
  }

  /// ПК вибрали в «Недавніх» на значку MHRD у панелі завдань.
  void _onShellConnect() {
    final target = ShellBridge.instance.pendingConnect.value;
    if (target == null || !mounted) return;
    final (id, account) = ShellBridge.parseConnectTarget(target);
    final c = repo.connections[id];
    if (c == null) return;
    ShellBridge.instance.pendingConnect.value = null;
    // Акаунт ярлика відв'язали від ПК — підключаємось акаунтом за замовчуванням.
    _connect(c, credentialId: c.credentialIds.contains(account) ? account : null);
  }

  Repository? _recentSource; // за ним стежимо для «Недавніх» (у dispose контексту вже не можна)

  void _syncRecent() {
    if (mounted) ShellBridge.instance.setRecent(context.l10n.recent, ShellBridge.recent(repo.connections.values));
  }

  @override
  void dispose() {
    ShellBridge.instance.pendingConnect.removeListener(_onShellConnect);
    _recentSource?.removeListener(_syncRecent);
    _quick.dispose();
    _quickFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Repository get repo => AppScope.of(context).repo;

  // ── Дії ─────────────────────────────────────────────────────────

  /// Підключення: акаунт ПК (пароль зі сховища) або діалог входу, далі — екран сеансу.
  /// [askPassword] — спитати навіть за збереженого пароля (після «невірний пароль»).
  Future<void> _connect(Connection c, {String? credentialId, bool askPassword = false}) async {
    final l = context.l10n;
    final sessions = AppScope.of(context).sessions;
    // Найсвіжіша версія ПК: після «Довіряти сертифікату» в ній уже є certPin.
    c = repo.connections[c.id] ?? c;
    if (!sessions.engineAvailable) {
      toast(context, l.engineMissing);
      return;
    }
    final running = credentialId == null ? sessions.forConnection(c.id) : null;
    if (running != null) {
      if (sessions.nativeWindows) {
        running.focusWindow();
      } else {
        _openSession(running, c);
      }
      return;
    }
    final creds = await sessions.credentialsFor(c, credentialId: credentialId);
    var user = creds.username, password = creds.password;
    if (askPassword || !creds.complete) {
      if (!mounted) return;
      final r = await askCredentials(context, target: c.displayName, username: user);
      if (r == null) return;
      (user, password) = r;
    }
    // RD Gateway зі своїм акаунтом без збереженого пароля — питаємо й для нього.
    String? gatewayPassword;
    final gwAccount = sessions.gatewayAccountToAsk(c);
    if (gwAccount != null) {
      if (!mounted) return;
      final g = repo.gateways[c.gatewayId]!;
      final r = await askCredentials(context, target: l.gatewayUser(g.label), username: gwAccount.username);
      if (r == null) return;
      gatewayPassword = r.$2;
    }
    if (!mounted) return;
    try {
      if (sessions.nativeWindows) {
        final s = await _startWindow(c, user!, password ?? '', gatewayPassword: gatewayPassword);
        if (s != null && mounted) _watchWindow(s, c, credentialId: credentialId);
        return;
      }
      await _startInApp(c, user!, password ?? '', credentialId: credentialId, gatewayPassword: gatewayPassword);
    } on RouteException catch (e) {
      if (mounted) toast(context, l.routeError(e.error));
    } on TunnelException catch (e) {
      if (mounted) _showTunnelError(c, e);
    } catch (e) {
      // Не запустився процес сеансу чи тунелю (заблокував антивірус, файл пошкоджено…) — кажемо,
      // а не мовчки нічого не робимо.
      if (mounted) toast(context, l.sessionStartFailed('$e'));
    }
  }

  /// Тунель не відкрився: що сталося — словами, подробиці — для діагностики.
  Future<void> _showTunnelError(Connection c, TunnelException e) async {
    final l = context.l10n;
    final t = context.mhrd;
    await showDialog<void>(
      context: context,
      builder: (dc) => AlertDialog(
        icon: Icon(Icons.shield_outlined, color: t.error),
        title: Text(c.displayName),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(l.tunnelError(e.error), textAlign: TextAlign.center),
            if (e.detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(e.detail, textAlign: TextAlign.center, style: t.mono),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dc), child: Text(l.close))],
      ),
    );
  }

  /// Мобільні: сеанс на екрані всередині застосунку.
  Future<void> _startInApp(Connection c, String user, String password,
      {String? credentialId, String? gatewayPassword}) async {
    final sessions = AppScope.of(context).sessions;
    // Роздільність = розмір вікна у фізичних пікселях (масштаб Windows 150% → ×1.5), а масштаб
    // ОС передаємо серверу — так картинка чітка, а текст на ПК звичного розміру.
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int even(double v, int min, int max) => (v.floor().clamp(min, max) ~/ 2) * 2;
    final s = await sessions.start(c,
        username: user,
        password: password,
        width: even(size.width * dpr, 640, 8192),
        height: even((size.height - 40) * dpr, 480, 8192),
        scale: (dpr * 100).round(),
        gatewayPassword: gatewayPassword);
    if (mounted) _openSession(s, c, credentialId: credentialId);
  }

  /// Десктоп: сеанс у власному вікні процесу `mhrd-session`. Роздільність — у фізичних пікселях
  /// монітора: на весь екран — увесь екран, інакше 80% (вікно потім саме підлаштує її під себе).
  Future<RdpSession?> _startWindow(Connection c, String username, String password, {String? gatewayPassword}) async {
    final l = context.l10n;
    final t = context.mhrd;
    final sessions = AppScope.of(context).sessions;
    final display = View.of(context).display;
    final fullscreen = c.display.startFullscreen ?? repo.settings.startFullscreen;
    final k = fullscreen ? 1.0 : 0.8;
    int even(double v, int min, int max) => (v.floor().clamp(min, max) ~/ 2) * 2;
    int rgb(Color color) => color.toARGB32() & 0xFFFFFF;
    final assets = p.join(p.dirname(sessions.enginePath!), 'data', 'flutter_assets');
    // Шаблон екрана (фіксована роздільність) або під розмір вікна.
    final fixed = repo.settings.resolutionFor(screen: c.display.screen, width: c.display.width, height: c.display.height);
    // Повна чіткість — фізичні пікселі й масштаб ОС на сервері; без неї — логічна роздільність при
    // 100 % (картинку збільшує вікно): приблизно вчетверо менше трафіку на екранах 200 %.
    final dpr = c.display.hiDpi ? 1.0 : display.devicePixelRatio;
    toast(context, l.connectingTo(c.address));
    return sessions.start(
      c,
      username: username,
      password: password,
      width: fixed?.$1 ?? even(display.size.width * k / dpr, 640, 8192),
      height: fixed?.$2 ?? even(display.size.height * k / dpr, 480, 8192),
      scale: c.display.hiDpi ? (display.devicePixelRatio * 100).round() : 100,
      gatewayPassword: gatewayPassword,
      window: {
        'title': '${c.displayName} — MHRD',
        // Підпис на плашці: «Назва · адреса», а без назви — лише адреса.
        'barTitle': c.nameWithAddress,
        // Шрифт плашки — той самий, що в застосунку (лежить поруч у flutter_assets).
        'fontPath': p.join(assets, 'assets', 'fonts', 'IBMPlexSans-Medium.ttf'),
        // Підказки кнопок плашки (через пів секунди наведення) і пункти системного меню вікна.
        'labels': {
          'pin': l.pinBar,
          'unpin': l.unpinBar,
          'minimize': l.barMinimize,
          'exitFullscreen': l.exitFullscreen,
          'fullscreen': l.fullscreen,
          'keyboard': l.onScreenKeyboard,
          'disconnect': l.disconnectAction,
          'menuFullscreen': l.fullscreen,
          'menuKeyboard': l.onScreenKeyboard,
          'reconnecting': '${l.statusReconnecting}…',
          'reconnectAttempt': l.reconnectAttempt('{n}', '{max}'), // числа підставляє вікно
          'cancel': l.cancel,
          'ctrlAltDel': 'Ctrl+Alt+Del',
          'latency': l.latencyMs('{n}'),
        },
        // Піктограми кнопок — зі шрифту Material Icons, який Flutter кладе поруч. Посилання на
        // Icons.* тут потрібні ще й тому, що збірка лишає у шрифті лише використані піктограми.
        'iconFontPath': p.join(assets, 'fonts', 'MaterialIcons-Regular.otf'),
        'icons': {
          'pin': Icons.push_pin_outlined.codePoint,
          'unpin': Icons.push_pin.codePoint,
          'keyboard': Icons.keyboard.codePoint,
          'minimize': Icons.minimize.codePoint,
          'fullscreen': Icons.fullscreen.codePoint,
          'exitFullscreen': Icons.fullscreen_exit.codePoint,
          'disconnect': Icons.power_settings_new.codePoint,
          // Замок — Ctrl+Alt+Del відкриває екран безпеки. Лише піктограми з основного діапазону
          // (до U+FFFF): вищі, як lock_reset, вікно сеансу не малює.
          'ctrlAltDel': Icons.lock_outline.codePoint,
        },
        'colors': {
          'surface': rgb(t.surface),
          'border': rgb(t.border),
          'text': rgb(t.text),
          'accent': rgb(t.accent),
          'error': rgb(t.error),
          'ok': rgb(t.ok),
          'warn': rgb(t.warn),
        },
        'radius': t.radius.round(), // кути плашки — як в усьому інтерфейсі
        'startFullscreen': fullscreen,
        'keyboardCapture': repo.settings.keyboardCapture.index, // 0 лише на весь екран, 1 завжди, 2 ніколи
        // 0 змінювати роздільність, 1 масштабувати, 2 ні. Фіксована роздільність шаблону не змінюється
        // під вікно — тоді картинку лише масштабуємо.
        'resizeMode': fixed != null && c.display.resizeMode == ResizeMode.changeResolution
            ? ResizeMode.scale.index
            : c.display.resizeMode.index,
        'swapMouse': c.swapMouseButtons,
        'logicalResolution': !c.display.hiDpi, // нова роздільність під вікно — теж у логічних пікселях
        'keepAwake': repo.settings.keepScreenAwake, // екран і сон Windows — поки відкрите вікно сеансу
        'allMonitors': c.display.useAllMonitors,
      },
    );
  }

  /// Вікно сеансу живе саме; головне вікно лише питає про сертифікат і пояснює, чому сеанс
  /// закрився (з «Підключитись знову»).
  void _watchWindow(RdpSession s, Connection c, {String? credentialId}) {
    final thumb = AppScope.of(context).sessions.files?.thumbnail(c.id);
    var asking = false;
    s.addListener(() {
      final cert = s.pendingCertificate;
      if (cert == null || asking || !mounted) return;
      asking = true;
      _askCertificate(s, cert).whenComplete(() => asking = false);
    });
    s.done.then((_) async {
      // Вікно сеансу щойно записало свіжу мініатюру — стару з кешу картинок прибираємо.
      if (thumb != null) await FileImage(thumb).evict();
      if (mounted) setState(() {});
      final ended = s.ended;
      if (!mounted || ended == null || ended.reason == DisconnectReason.userRequest) return;
      await _bringToFront();
      if (!mounted) return;
      if (ended.reason == DisconnectReason.passwordExpired) {
        await _passwordExpired(c, credentialId);
        return;
      }
      final l = context.l10n;
      final t = context.mhrd;
      final retry = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
          icon: Icon(Icons.error_outline, color: t.error),
          title: Text(c.displayName),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l.disconnectReason(ended.reason), textAlign: TextAlign.center),
              if (ended.details.isNotEmpty || ended.code != 0) ...[
                const SizedBox(height: 10),
                SelectableText(
                  l.sessionDetails(ended.details.isEmpty ? '—' : ended.details, '0x${ended.code.toRadixString(16)}'),
                  textAlign: TextAlign.center,
                  style: t.mono,
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(l.close)),
            FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(l.retry)),
          ],
        ),
      );
      if (retry != true || !mounted) return;
      _connect(c,
          credentialId: credentialId,
          askPassword: ended.reason == DisconnectReason.authFailed || ended.reason == DisconnectReason.noCredentials);
    });
  }

  /// Пароль прострочений: людина міняє його на ПК чи в домені, а тут вводить новий — він
  /// зберігається в акаунті (для всіх ПК з цим акаунтом), і MHRD підключається знову.
  Future<void> _passwordExpired(Connection c, String? credentialId) async {
    final l = context.l10n;
    final t = context.mhrd;
    final id = credentialId ?? (c.credentialIds.isEmpty ? null : c.credentialIds.first);
    final cred = id == null ? null : repo.credentials[id];
    final saved = cred != null && cred.authMode == AuthMode.savedPassword;
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        icon: Icon(Icons.password, color: t.warn),
        title: Text(c.displayName),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.reasonPasswordExpired),
            const SizedBox(height: 8),
            Text(saved ? l.passwordExpiredSaved(cred.label) : l.passwordExpiredAsk,
                style: TextStyle(color: t.textMuted, fontSize: 13)),
            if (saved) ...[
              const SizedBox(height: 14),
              TextField(
                controller: pass,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(labelText: l.newPassword),
                onSubmitted: (_) => Navigator.pop(dc, true),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(l.close)),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(l.saveAndConnect)),
        ],
      ),
    );
    final newPassword = pass.text;
    pass.dispose();
    if (ok != true || !mounted) return;
    if (saved && newPassword.isNotEmpty) {
      await repo.saveCredential(cred, password: newPassword);
      if (mounted) _connect(c, credentialId: credentialId);
    } else {
      _connect(c, credentialId: credentialId, askPassword: true);
    }
  }

  Future<void> _askCertificate(RdpSession s, CertificateEvent cert) async {
    await _bringToFront();
    if (!mounted) return;
    final sessions = AppScope.of(context).sessions;
    final r = await showDialog<(bool, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CertificateDialog(cert: cert, canRemember: repo.connections.containsKey(s.connection.id)),
    );
    final (accept, remember) = r ?? (false, false);
    if (accept && remember) sessions.trustCertificate(s, cert.fingerprint);
    s.answerCertificate(accept);
  }

  /// Діалог про сеанс має бути видно, навіть якщо головне вікно згорнуте чи позаду.
  Future<void> _bringToFront() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  void _openSession(RdpSession s, Connection c, {String? credentialId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (route) => SessionScreen(
        session: s,
        onRetry: () {
          Navigator.of(route).pop();
          final reason = s.ended?.reason;
          _connect(c,
              credentialId: credentialId,
              askPassword: reason == DisconnectReason.authFailed || reason == DisconnectReason.noCredentials);
        },
      ),
    ));
  }

  void _quickConnect() {
    final l = context.l10n;
    final addr = parseAddress(_quick.text);
    if (addr == null) {
      toast(context, l.invalidAddressExamples);
      return;
    }
    final temp = repo.newConnection(host: addr.host, port: addr.port);
    toast(context, l.connectingTo(temp.address),
        action: SnackBarAction(label: l.saveThisPc, onPressed: () => _edit(temp, isNew: true)));
    _connect(temp);
  }

  Future<void> _edit(Connection? c, {bool isNew = false}) async {
    final groupId = (_filter.startsWith('__')) ? null : _filter;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EditConnectionScreen(initial: c, isNew: isNew || c == null, defaultGroupId: groupId),
    ));
  }

  Future<void> _delete(Connection c) async {
    final l = context.l10n;
    if (await confirm(context, title: l.deletePcTitle(c.displayName), ok: l.delete, danger: true)) {
      _deleteIds([c.id]);
    }
  }

  /// Видаляє ПК разом із їхніми мініатюрами й картинками (якщо картинку не ділить інший ПК).
  void _deleteIds(List<String> ids) {
    final files = AppScope.of(context).sessions.files;
    final gone = [for (final id in ids) repo.connections[id]].whereType<Connection>().toList();
    repo.deleteConnections(ids);
    setState(() => _selected.removeAll(ids));
    for (final c in gone) {
      final shared = repo.connections.values.any((x) => x.image == c.image);
      files?.forget(c.id, image: shared ? null : c.image);
    }
  }

  // ── Виділення ───────────────────────────────────────────────────

  final _selected = <String>{};
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(Connection c) => setState(() => _selected.contains(c.id) ? _selected.remove(c.id) : _selected.add(c.id));

  void _clearSelection() => setState(_selected.clear);

  Future<void> _deleteSelected() async {
    final l = context.l10n;
    if (await confirm(context, title: l.deletePcsTitle(_selected.length), ok: l.delete, danger: true)) {
      _deleteIds(_selected.toList());
    }
  }

  Future<void> _moveSelected() async {
    final l = context.l10n;
    final groups = repo.groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final i = await pickOne(context, title: l.moveToGroup, options: [l.savedPcs, ...groups.map((g) => g.name)]);
    if (i == null) return;
    repo.moveConnections(_selected, i == 0 ? null : groups[i - 1].id);
    _clearSelection();
  }

  /// Перетягнуті ПК відпустили на групі ([groupId] null — «Без групи»).
  void _dropOn(List<String> ids, String? groupId) {
    repo.moveConnections(ids, groupId);
    if (ids.any(_selected.contains)) _clearSelection();
  }

  /// Що показати на картці: виділення, відкритий сеанс, своя картинка чи мініатюра.
  PcCardState _cardState(Connection c) {
    final sessions = AppScope.of(context).sessions;
    final files = sessions.files;
    File? preview;
    if (files != null) {
      final image = c.image == null ? null : files.image(c.image!);
      final thumb = files.thumbnail(c.id);
      if (image != null && image.existsSync()) {
        preview = image;
      } else if (repo.settings.showPreviews && thumb.existsSync()) {
        preview = thumb;
      }
    }
    return PcCardState(
      selected: _selected.contains(c.id),
      selecting: _selecting,
      connected: sessions.forConnection(c.id) != null,
      preview: preview,
    );
  }

  Widget _tile(Connection c) => _DragPc(
        ids: _selected.contains(c.id) ? _selected.toList() : [c.id],
        label: c.displayName,
        onTouchDrag: () => _selected.contains(c.id) ? null : _toggleSelect(c),
        child: PcTile(connection: c, repo: repo, actions: _actions, state: _cardState(c)),
      );

  Widget _row(Connection c) => _DragPc(
        ids: _selected.contains(c.id) ? _selected.toList() : [c.id],
        label: c.displayName,
        onTouchDrag: () => _selected.contains(c.id) ? null : _toggleSelect(c),
        child: PcRow(connection: c, repo: repo, actions: _actions, state: _cardState(c)),
      );

  /// Куди можна відпустити перетягнуті ПК: група в боковій панелі чи заголовок розділу.
  Widget _dropTarget(String? groupId, Widget Function(bool hovering) builder) => DragTarget<List<String>>(
        onAcceptWithDetails: (d) => _dropOn(d.data, groupId),
        builder: (context, candidates, _) => builder(candidates.isNotEmpty),
      );

  Widget _selectionBar(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final visible = _visible();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: t.accent),
      ),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(l.selectedCount(_selected.length), style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => setState(() => _selected.addAll(visible.map((c) => c.id))),
          child: Text(l.selectAll),
        ),
        TextButton.icon(
            icon: const Icon(Icons.drive_file_move_outlined, size: 18),
            label: Text(l.moveToGroup),
            onPressed: _moveSelected),
        TextButton.icon(
          icon: Icon(Icons.delete_outline, size: 18, color: t.error),
          label: Text(l.delete, style: TextStyle(color: t.error)),
          onPressed: _deleteSelected,
        ),
        TextButton(onPressed: _clearSelection, child: Text(l.cancel)),
        Text(l.dragHint, style: TextStyle(color: t.textMuted, fontSize: 12)),
      ]),
    );
  }

  Future<void> _move(Connection c) async {
    final l = context.l10n;
    final groups = repo.groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final i = await pickOne(context, title: l.moveToGroup, options: [l.savedPcs, ...groups.map((g) => g.name)]);
    if (i == null) return;
    repo.saveConnection(c.copyWith(groupId: () => i == 0 ? null : groups[i - 1].id));
  }

  Future<void> _exportRdp(Connection c) async {
    final l = context.l10n;
    final cred = c.credentialIds.isEmpty ? null : repo.credentials[c.credentialIds.first];
    final text = buildRdpFile(c, username: cred?.username, gatewayHost: repo.gateways[c.gatewayId]?.host);
    final safe = c.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await saveBytes(Uint8List.fromList(encodeUtf16Le(text)), '$safe.rdp', rdpTypes(l));
    if (path != null && mounted) toast(context, l.savedTo(path));
  }

  Future<void> _importRdp() async {
    final l = context.l10n;
    final files = await openManyBytes(rdpTypes(l));
    var ok = 0;
    final errors = <String>[];
    for (final (name, bytes) in files) {
      try {
        final r = parseRdpFile(decodeRdpBytes(bytes),
            id: newId(), fallbackName: name.replaceAll(RegExp(r'\.rdp$', caseSensitive: false), ''));
        var conn = r.connection;
        if (r.username != null) {
          final existing = repo.credentials.values.where((c) => c.username == r.username).toList();
          final cred = existing.isNotEmpty
              ? existing.first
              : Credential(id: newId(), name: '', username: r.username!, authMode: AuthMode.askPassword);
          if (existing.isEmpty) await repo.saveCredential(cred);
          conn = conn.copyWith(credentialIds: [cred.id]);
        }
        if (r.gatewayHost != null) {
          final existing = repo.gateways.values.where((g) => g.host == r.gatewayHost).toList();
          final gw = existing.isNotEmpty ? existing.first : Gateway(id: newId(), name: '', host: r.gatewayHost!);
          if (existing.isEmpty) repo.saveGateway(gw);
          conn = conn.copyWith(gatewayId: () => gw.id);
        }
        final groupId = _filter.startsWith('__') ? null : _filter;
        repo.saveConnection(conn.copyWith(groupId: () => groupId));
        ok++;
      } on FormatException {
        // parseRdpFile кидає лише одну помилку: немає коректної адреси.
        errors.add('$name: ${l.rdpNoAddress}');
      }
    }
    if (!mounted || files.isEmpty) return;
    toast(context, errors.isEmpty ? l.importedPcs(ok) : l.importedWithErrors(ok, errors.join('; ')));
  }

  /// Імпорт ПК, які пам'ятає стандартний клієнт Windows: список із галочками — що додавати.
  Future<void> _importMstsc() async {
    final l = context.l10n;
    final t = context.mhrd;
    final found = readMstscHistory();
    if (found.isEmpty) {
      toast(context, l.mstscNothing);
      return;
    }
    bool exists(MstscEntry e) =>
        repo.connections.values.any((c) => c.host.toLowerCase() == e.host.toLowerCase() && c.port == e.port);
    final picked = {for (var i = 0; i < found.length; i++) if (!exists(found[i])) i};
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setState) => AlertDialog(
          title: Text(l.mstscTitle),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.mstscHint, style: TextStyle(color: t.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (var i = 0; i < found.length; i++)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: picked.contains(i),
                      onChanged: exists(found[i])
                          ? null
                          : (v) => setState(() => v == true ? picked.add(i) : picked.remove(i)),
                      title: Text(found[i].address, style: TextStyle(fontFamily: t.fontMono)),
                      subtitle: Text(
                        [if (found[i].username != null) found[i].username!, if (exists(found[i])) l.mstscAlready]
                            .join(' · '),
                        style: TextStyle(color: t.textMuted, fontSize: 12),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(l.cancel)),
            FilledButton(
              onPressed: picked.isEmpty ? null : () => Navigator.pop(dc, true),
              child: Text(l.mstscAdd(picked.length)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final groupId = _filter.startsWith('__') ? null : _filter;
    for (final i in picked) {
      final e = found[i];
      var conn = repo.newConnection(host: e.host, port: e.port, groupId: groupId);
      if (e.username != null) {
        // Як і в імпорті .rdp: наявний акаунт з тим самим ім'ям, інакше новий «питати пароль».
        final existing = repo.credentials.values.where((c) => c.username == e.username).toList();
        final cred = existing.isNotEmpty
            ? existing.first
            : Credential(id: newId(), name: '', username: e.username!, authMode: AuthMode.askPassword);
        if (existing.isEmpty) await repo.saveCredential(cred);
        conn = conn.copyWith(credentialIds: [cred.id, ...conn.credentialIds.where((x) => x != cred.id)]);
      }
      repo.saveConnection(conn);
    }
    if (mounted) toast(context, l.importedPcs(picked.length));
  }

  Future<void> _wake(Connection c) async {
    final l = context.l10n;
    final w = c.wakeOnLan;
    if (w == null) return;
    try {
      await sendWakeOnLan(w);
      if (mounted) toast(context, l.wakeSent(w.mac));
    } on WakeOnLanException catch (e) {
      if (mounted) toast(context, l.wakeOnLanError(e));
    } on SocketException catch (e) {
      if (mounted) toast(context, l.wakeFailed(e.message));
    }
  }

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  PcActions get _actions => PcActions(
        connect: _connect,
        edit: (c) => _edit(c),
        duplicate: (c) => repo.duplicateConnection(c, name: context.l10n.copyOf(c.displayName)),
        exportRdp: _exportRdp,
        moveToGroup: _move,
        wake: _wake,
        delete: _delete,
        select: _toggleSelect,
      );

  // ── Дані ────────────────────────────────────────────────────────

  List<Connection> _visible() {
    Iterable<Connection> list = repo.connections.values;
    switch (_filter) {
      case _all:
        break;
      case _recent:
        list = list.where((c) => c.lastUsed != null);
      case _saved:
        list = list.where((c) => c.groupId == null);
      default:
        final ids = _withSubgroups(_filter);
        list = list.where((c) => ids.contains(c.groupId));
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) =>
          c.displayName.toLowerCase().contains(q) ||
          c.host.toLowerCase().contains(q) ||
          c.tags.any((t) => t.toLowerCase().contains(q)) ||
          (repo.groups[c.groupId]?.name.toLowerCase().contains(q) ?? false));
    }
    final out = list.toList();
    if (_filter == _recent) {
      out.sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!));
      return out.take(12).toList();
    }
    out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return out;
  }

  Set<String> _withSubgroups(String id) {
    final out = {id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final g in repo.groups.values) {
        if (g.parentId != null && out.contains(g.parentId) && out.add(g.id)) grew = true;
      }
    }
    return out;
  }

  String _title(AppLocalizations l) => switch (_filter) {
        _all => l.allPcs,
        _recent => l.recent,
        _saved => l.savedPcs,
        _ => repo.groups[_filter]?.name ?? l.allPcs,
      };

  // ── Розмітка ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repo, AppScope.of(context).sessions]),
      builder: (context, _) {
        if (!_filter.startsWith('__') && !repo.groups.containsKey(_filter)) _filter = _all;
        _selected.removeWhere((id) => !repo.connections.containsKey(id));
        final wide = MediaQuery.sizeOf(context).width >= 760;
        final mac = Theme.of(context).platform == TargetPlatform.macOS;
        SingleActivator key(LogicalKeyboardKey k) => SingleActivator(k, meta: mac, control: !mac);
        return CallbackShortcuts(
          bindings: {
            key(LogicalKeyboardKey.keyN): () => _edit(null),
            key(LogicalKeyboardKey.keyK): () => _quickFocus.requestFocus(),
            key(LogicalKeyboardKey.keyF): () => _searchFocus.requestFocus(),
            key(LogicalKeyboardKey.comma): _openSettings,
            const SingleActivator(LogicalKeyboardKey.escape): _clearSelection,
            const SingleActivator(LogicalKeyboardKey.delete): () => _selecting ? _deleteSelected() : null,
            key(LogicalKeyboardKey.keyA): () => setState(() => _selected.addAll(_visible().map((c) => c.id))),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              drawer: wide ? null : Drawer(child: SafeArea(child: _sidebar(context, inDrawer: true))),
              body: SafeArea(
                child: Column(children: [
                  _header(context, wide),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (wide && repo.settings.sidebarShown) SizedBox(width: 248, child: _sidebar(context)),
                      Expanded(child: _main(context)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, bool wide) {
    final t = context.mhrd;
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: t.surface, border: Border(bottom: BorderSide(color: t.border))),
      child: Row(children: [
        // Бічна панель: на широкому екрані закріпити / сховати, на вузькому — відкрити поверх.
        Builder(
            builder: (c) => IconButton(
                  tooltip: l.sidebarToggle,
                  icon: Icon(wide && repo.settings.sidebarShown ? Icons.menu_open : Icons.menu),
                  onPressed: () => wide
                      ? repo.updateSettings(repo.settings.copyWith(sidebarShown: !repo.settings.sidebarShown))
                      : Scaffold.of(c).openDrawer(),
                )),
        const SizedBox(width: 4),
        Text('MHRD',
            style: TextStyle(
                fontFamily: t.fontMono,
                fontWeight: FontWeight.w500,
                fontSize: 20,
                letterSpacing: 0.8,
                color: t.accent)),
        if (wide) ...[
          const SizedBox(width: 8),
          Text('remote desktop', style: TextStyle(color: t.textMuted, fontSize: 12)),
        ],
        const SizedBox(width: 16),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TextField(
              controller: _quick,
              focusNode: _quickFocus,
              style: TextStyle(fontFamily: t.fontMono, fontSize: 13.5, color: t.text),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.bolt, color: t.textMuted, size: 18),
                hintText: l.quickConnectHint,
                suffixText: wide ? 'Ctrl K' : null,
                suffixStyle: TextStyle(fontFamily: t.fontMono, fontSize: 11, color: t.textMuted),
              ),
              onSubmitted: (_) => _quickConnect(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          tooltip: l.add,
          onSelected: (v) => switch (v) {
            'pc' => _edit(null),
            'mstsc' => _importMstsc(),
            _ => _importRdp(),
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'pc', child: Text(l.addPc)),
            PopupMenuItem(value: 'rdp', child: Text(l.importRdpFiles)),
            if (Platform.isWindows) PopupMenuItem(value: 'mstsc', child: Text(l.importMstsc)),
          ],
          child: IgnorePointer(
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add, size: 18),
              label: Text(wide ? l.add : ''),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(tooltip: l.settings, onPressed: _openSettings, icon: const Icon(Icons.tune)),
      ]),
    );
  }

  Widget _sidebar(BuildContext context, {bool inDrawer = false}) {
    final t = context.mhrd;
    final l = context.l10n;
    Widget item(String id, String label, int count, {int depth = 0}) {
      final active = _filter == id;
      // На групу й «Без групи» можна перетягнути ПК.
      final droppable = id == _saved || repo.groups.containsKey(id);
      Widget box(bool hovering) => Material(
          color: hovering
              ? t.accent.withValues(alpha: 0.25)
              : active
                  ? t.surfaceRaised
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radius * 0.7),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radius * 0.7),
            onTap: () {
              setState(() => _filter = id);
              if (inDrawer) Navigator.pop(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: t.gap + 1),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? t.text : t.textMuted, fontSize: 14)),
                ),
                Text('$count', style: TextStyle(fontFamily: t.fontMono, color: t.textMuted, fontSize: 12)),
              ]),
            ),
          ),
        );
      return Padding(
        padding: EdgeInsets.only(left: depth * 14.0),
        child: droppable ? _dropTarget(id == _saved ? null : id, box) : box(false),
      );
    }

    List<Widget> tree(String? parent, int depth) {
      final kids = repo.groups.values.where((g) => g.parentId == parent).toList()
        ..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder - b.sortOrder : a.name.compareTo(b.name));
      return [
        for (final g in kids) ...[
          item(g.id, g.name, repo.countInGroup(g.id), depth: depth),
          ...tree(g.id, depth + 1),
        ],
      ];
    }

    Widget caption(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
          child: Text(s.toUpperCase(),
              style: TextStyle(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        );

    return Container(
      decoration: BoxDecoration(color: t.surface, border: Border(right: BorderSide(color: t.border))),
      child: ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 20), children: [
        caption(l.computers),
        item(_all, l.allPcs, repo.connections.length),
        item(_recent, l.recent, repo.connections.values.where((c) => c.lastUsed != null).length),
        item(_saved, l.savedPcs, repo.countInGroup(null)),
        if (repo.groups.isNotEmpty) caption(l.groups),
        ...tree(null, 0),
        caption(l.activeTunnels),
        if (repo.tunnels.isEmpty && repo.proxies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(l.noTunnelsYet, style: TextStyle(color: t.textMuted, fontSize: 12.5)),
          )
        else
          _routes(context),
      ]),
    );
  }

  /// Тунелі й проксі зі станом: зелена — працює, червона — варто глянути. Стан оновлюється при
  /// запуску, кожні 5 хв і кнопкою поруч.
  Widget _routes(BuildContext context) {
    final health = AppScope.of(context).sessions.health;
    int byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    final tunnels = repo.tunnels.values.toList()..sort((a, b) => byName(a.name, b.name));
    final proxies = repo.proxies.values.toList()..sort((a, b) => byName(a.name, b.name));
    return ListenableBuilder(
      listenable: health,
      builder: (context, _) => Column(children: [
        for (final x in tunnels)
          _routeItem(context, health, x.id, x.label,
              Icons.shield_outlined,
              // Адреса цього ПК у тунелі — видно, що WireGuard піднявся і з якою IP ви в мережі.
              address: tunnelAddress(x.config)),
        for (final x in proxies)
          _routeItem(context, health, x.id, x.label, Icons.alt_route,
              address: '${x.host}:${x.port}'),
      ]),
    );
  }

  Widget _routeItem(BuildContext context, RouteHealth health, String id, String name, IconData icon,
      {String? address}) {
    final t = context.mhrd;
    final l = context.l10n;
    final s = health.statusOf(id);
    final checking = s.state == HealthState.checking;
    final color = switch (s.state) {
      HealthState.ok => t.ok,
      HealthState.failed => t.error,
      _ => t.textMuted,
    };
    return Tooltip(
      message: _healthText(context, s),
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius * 0.7),
        onTap: () => _showHealth(context, name, s),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(children: [
            SizedBox.square(
              dimension: 10,
              child: checking
                  ? CircularProgressIndicator(strokeWidth: 1.6, color: t.textMuted)
                  : DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 15, color: t.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: s.state == HealthState.failed ? t.error : t.text, fontSize: 13.5)),
                // «10.8.0.2 · 34 мс» — адреса й затримка, коли працює.
                if (address != null)
                  Text(
                    // мс — першими: довга адреса проксі обрізається, а затримку має бути видно
                    s.state == HealthState.ok && s.latencyMs != null ? '${l.latencyMs('${s.latencyMs}')} · $address' : address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: t.fontMono, color: t.textMuted, fontSize: 11.5),
                  ),
              ]),
            ),
            IconButton(
              tooltip: l.checkNow,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: t.textMuted,
              onPressed: checking ? null : () => health.check(id),
              icon: const Icon(Icons.refresh),
            ),
          ]),
        ),
      ),
    );
  }

  String _healthText(BuildContext context, RouteStatus s) {
    final l = context.l10n;
    final text = switch (s.state) {
      HealthState.ok => l.healthOk(s.latencyMs ?? 0),
      HealthState.failed => l.healthError(s.error ?? TunnelError.failed),
      HealthState.checking => l.healthChecking,
      HealthState.unknown => l.healthUnknown,
    };
    final at = s.checkedAt;
    if (at == null) return text;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: true);
    return '$text\n${l.healthCheckedAt(time)}';
  }

  /// Подробиці — щоб скопіювати технічну причину, якщо щось не так.
  Future<void> _showHealth(BuildContext context, String name, RouteStatus s) async {
    final l = context.l10n;
    final t = context.mhrd;
    await showDialog<void>(
      context: context,
      builder: (dc) => AlertDialog(
        icon: Icon(s.state == HealthState.failed ? Icons.error_outline : Icons.check_circle_outline,
            color: s.state == HealthState.failed ? t.error : t.ok),
        title: Text(name),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_healthText(context, s), textAlign: TextAlign.center),
            if (s.detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(s.detail, textAlign: TextAlign.center, style: t.mono),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dc), child: Text(l.close))],
      ),
    );
  }

  Widget _main(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final items = _visible();
    final tiles = repo.settings.listView == PcListView.tiles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(_title(l), style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w600)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 260,
                child: TextField(
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.searchHint,
                    prefixIcon: Icon(Icons.search, size: 18, color: t.textMuted),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<PcListView>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: PcListView.tiles, icon: const Icon(Icons.grid_view, size: 18), tooltip: l.viewTiles),
                  ButtonSegment(
                      value: PcListView.list, icon: const Icon(Icons.view_list, size: 18), tooltip: l.viewList),
                ],
                selected: {repo.settings.listView},
                onSelectionChanged: (s) => repo.updateSettings(repo.settings.copyWith(listView: s.first)),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 18),
        if (_selecting) _selectionBar(context),
        Expanded(
          child: items.isEmpty
              ? _empty(context)
              : _filter == _all && _query.trim().isEmpty && repo.groups.isNotEmpty
                  ? _grouped(context, items, tiles)
                  : tiles
                  ? GridView.builder(
                      padding: const EdgeInsets.only(bottom: 32),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        mainAxisExtent: 236,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _tile(items[i]),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _row(items[i]),
                    ),
        ),
      ]),
    );
  }

  /// «Усі ПК» розділами за групами; кожен розділ згортається, «Без групи» — останнім
  /// (типово згорнутий). Згорнуте запам'ятовується.
  Widget _grouped(BuildContext context, List<Connection> items, bool tiles) {
    final t = context.mhrd;
    final l = context.l10n;
    String path(Group g) {
      final names = [g.name];
      var p = g.parentId;
      final seen = <String>{};
      while (p != null && seen.add(p)) {
        final parent = repo.groups[p];
        if (parent == null) break;
        names.insert(0, parent.name);
        p = parent.parentId;
      }
      return names.join(' / ');
    }

    final groups = repo.groups.values.toList()..sort((a, b) => path(a).compareTo(path(b)));
    final sections = <(String, String, List<Connection>)>[
      for (final g in groups) (g.id, path(g), items.where((c) => c.groupId == g.id).toList()),
      (AppSettings.noGroupSection, l.savedPcs, items.where((c) => !repo.groups.containsKey(c.groupId)).toList()),
    ].where((s) => s.$3.isNotEmpty);
    final collapsed = repo.settings.collapsedGroups.toSet();

    void toggle(String id) {
      final next = {...collapsed};
      if (!next.remove(id)) next.add(id);
      repo.updateSettings(repo.settings.copyWith(collapsedGroups: next.toList()));
    }

    return CustomScrollView(slivers: [
      for (final (id, name, pcs) in sections) ...[
        SliverToBoxAdapter(
          // На заголовок розділу теж можна перетягнути ПК — перенесуться в цю групу.
          child: _dropTarget(
            id == AppSettings.noGroupSection ? null : id,
            (hovering) => Material(
              color: hovering ? t.accent.withValues(alpha: 0.25) : Colors.transparent,
              borderRadius: BorderRadius.circular(t.radius * 0.7),
              child: InkWell(
                borderRadius: BorderRadius.circular(t.radius * 0.7),
                onTap: () => toggle(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(collapsed.contains(id) ? Icons.chevron_right : Icons.expand_more,
                        size: 20, color: t.textMuted),
                    const SizedBox(width: 6),
                    Text(name, style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text('${pcs.length}',
                        style: TextStyle(fontFamily: t.fontMono, color: t.textMuted, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ),
        ),
        if (!collapsed.contains(id))
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: tiles
                ? SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 300,
                      mainAxisExtent: 236,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: pcs.length,
                    itemBuilder: (_, i) => _tile(pcs[i]),
                  )
                : SliverList.separated(
                    itemCount: pcs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _row(pcs[i]),
                  ),
          ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
  }

  Widget _empty(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final searching = _query.trim().isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.desktop_windows_outlined, size: 48, color: t.textMuted),
          const SizedBox(height: 14),
          Text(searching ? l.nothingFound : l.emptyTitle,
              style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            searching ? l.nothingFoundHint : l.emptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMuted),
          ),
          if (!searching) ...[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: Text(l.addPc)),
          ],
        ]),
      ),
    );
  }
}

/// Картку ПК можна перетягнути на групу. Мишею — одразу, пальцем — після довгого натискання
/// (інакше палець не міг би гортати список); довге натискання ще й позначає ПК.
class _DragPc extends StatefulWidget {
  const _DragPc({required this.ids, required this.label, required this.onTouchDrag, required this.child});

  final List<String> ids;
  final String label;
  final VoidCallback onTouchDrag;
  final Widget child;

  @override
  State<_DragPc> createState() => _DragPcState();
}

class _DragPcState extends State<_DragPc> {
  static bool _touch = false; // останній пристрій — палець (спільне для всіх карток)

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
          Text(widget.ids.length == 1 ? widget.label : l.pcCount(widget.ids.length),
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
    final faded = Opacity(opacity: 0.4, child: widget.child);
    return Listener(
      onPointerHover: (_) => _touch ? setState(() => _touch = false) : null,
      onPointerDown: (e) {
        final touch = e.kind == PointerDeviceKind.touch;
        if (touch != _touch) setState(() => _touch = touch);
      },
      child: _touch
          ? LongPressDraggable<List<String>>(
              data: widget.ids,
              feedback: feedback,
              childWhenDragging: faded,
              onDragStarted: widget.onTouchDrag,
              child: widget.child,
            )
          : Draggable<List<String>>(
              data: widget.ids,
              feedback: feedback,
              childWhenDragging: faded,
              child: widget.child,
            ),
    );
  }
}