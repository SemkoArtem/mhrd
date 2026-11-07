import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/l10n/app_localizations.dart';
import 'package:mhrd/theme/mhrd_theme.dart';
import 'package:mhrd/ui/widgets/drag_pc.dart';

/// Картка ПК і ціль: мишею перетягується одразу, пальцем — після утримання (і позначається), швидкий
/// рух пальцем — не перетягування (список гортається). Без перемикання «миша/палець» між дотиками.
void main() {
  late List<List<String>> dropped;
  late int marked;

  Future<void> pump(WidgetTester tester) async {
    dropped = [];
    marked = 0;
    await tester.pumpWidget(MaterialApp(
      theme: MhrdTokens.graphite.toThemeData(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(children: [
          DragPc(
            ids: const ['pc1'],
            label: 'ПК',
            onTouchDrag: () => marked++,
            child: const SizedBox(width: 200, height: 80, child: Text('картка')),
          ),
          const SizedBox(height: 100),
          DragTarget<List<String>>(
            onAcceptWithDetails: (d) => dropped.add(d.data),
            builder: (_, __, ___) => const SizedBox(width: 200, height: 80, child: Text('група')),
          ),
        ]),
      ),
    ));
  }

  Future<void> drag(WidgetTester tester, PointerDeviceKind kind, {Duration hold = Duration.zero}) async {
    final g = await tester.startGesture(tester.getCenter(find.text('картка')), kind: kind);
    if (hold > Duration.zero) await tester.pump(hold);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.moveTo(tester.getCenter(find.text('група')));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('мишею — одразу', (tester) async {
    await pump(tester);
    await drag(tester, PointerDeviceKind.mouse);
    expect(dropped, [
      ['pc1']
    ]);
    expect(marked, 0);
  });

  testWidgets('пальцем — після утримання, і ПК позначено; щоразу, а не через раз', (tester) async {
    await pump(tester);
    for (var i = 0; i < 3; i++) {
      await drag(tester, PointerDeviceKind.touch, hold: const Duration(milliseconds: 450));
    }
    expect(dropped.length, 3);
    expect(marked, 3);
  });

  testWidgets('пальцем без утримання — не перетягування', (tester) async {
    await pump(tester);
    await drag(tester, PointerDeviceKind.touch);
    expect(dropped, isEmpty);
  });

  testWidgets('миша після пальця й навпаки — перший же жест працює', (tester) async {
    await pump(tester);
    await drag(tester, PointerDeviceKind.touch, hold: const Duration(milliseconds: 450));
    await drag(tester, PointerDeviceKind.mouse);
    await drag(tester, PointerDeviceKind.touch, hold: const Duration(milliseconds: 450));
    expect(dropped.length, 3);
  });
}
