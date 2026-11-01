import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../security/app_lock.dart';
import '../theme/mhrd_theme.dart';

/// Показує [child] лише після PIN-коду чи відбитка / Windows Hello, якщо блокування ввімкнено.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  bool? _locked; // null — ще перевіряємо

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_locked != null) return;
    AppLock(AppScope.of(context).repo).isRequired().then((r) {
      if (mounted) setState(() => _locked = r);
    });
  }

  @override
  Widget build(BuildContext context) => switch (_locked) {
        null => Scaffold(backgroundColor: context.mhrd.background),
        true => LockScreen(onUnlocked: () => setState(() => _locked = false)),
        false => widget.child,
      };
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  late final AppLock _lock = AppLock(AppScope.of(context).repo);
  bool _wrong = false, _checking = false;

  @override
  void initState() {
    super.initState();
    // Відбиток / Windows Hello — одразу, без зайвого кліку.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AppScope.of(context).repo.settings.lockBiometric) _biometric();
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking || _pin.text.isEmpty) return;
    setState(() => _checking = true);
    final ok = await _lock.checkPin(_pin.text);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _checking = false;
        _wrong = true;
        _pin.clear();
      });
    }
  }

  Future<void> _biometric() async {
    if (await _lock.unlockWithBiometric(context.l10n.lockReason) && mounted) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    final biometric = AppScope.of(context).repo.settings.lockBiometric;
    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 44, color: t.accent),
            const SizedBox(height: 14),
            Text('MHRD',
                style: TextStyle(fontFamily: t.fontMono, fontSize: 22, letterSpacing: 0.8, color: t.accent)),
            const SizedBox(height: 6),
            Text(l.lockTitle, style: TextStyle(color: t.textMuted)),
            const SizedBox(height: 22),
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
              style: TextStyle(fontFamily: t.fontMono, fontSize: 22, letterSpacing: 8, color: t.text),
              decoration: InputDecoration(hintText: l.pinHint, errorText: _wrong ? l.pinWrong : null),
              onChanged: (_) => _wrong ? setState(() => _wrong = false) : null,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _checking ? null : _submit, child: Text(l.unlock)),
            ),
            if (biometric) ...[
              const SizedBox(height: 8),
              TextButton.icon(icon: const Icon(Icons.fingerprint), label: Text(l.unlockBiometric), onPressed: _biometric),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Діалог «новий PIN двічі». Повертає PIN або null, якщо скасували.
Future<String?> askNewPin(BuildContext context) {
  final l = context.l10n;
  final a = TextEditingController(), b = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (dc) => StatefulBuilder(
      builder: (dc, setState) {
        void ok() {
          if (a.text.length < 4) {
            setState(() => error = l.pinTooShort);
          } else if (a.text != b.text) {
            setState(() => error = l.pinMismatch);
          } else {
            Navigator.pop(dc, a.text);
          }
        }

        InputDecoration deco(String label) => InputDecoration(labelText: label);
        final fmt = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)];
        return AlertDialog(
          title: Text(l.lockSetPin),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: a,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: fmt,
                decoration: deco(l.pinNew)),
            const SizedBox(height: 10),
            TextField(
                controller: b,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: fmt,
                decoration: deco(l.pinRepeat),
                onSubmitted: (_) => ok()),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: context.mhrd.error)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc), child: Text(l.cancel)),
            FilledButton(onPressed: ok, child: Text(l.save)),
          ],
        );
      },
    ),
  );
}

/// Діалог «поточний PIN» (щоб вимкнути блокування). true — PIN правильний.
Future<bool> confirmPin(BuildContext context, AppLock lock) async {
  final l = context.l10n;
  final c = TextEditingController();
  final pin = await showDialog<String>(
    context: context,
    builder: (dc) => AlertDialog(
      title: Text(l.pinCurrent),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (v) => Navigator.pop(dc, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dc), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(dc, c.text), child: Text(l.ok)),
      ],
    ),
  );
  return pin != null && await lock.checkPin(pin);
}
