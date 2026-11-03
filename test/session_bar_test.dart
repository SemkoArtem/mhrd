import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/entities.dart';
import 'package:mhrd/theme/mhrd_theme.dart';
import 'package:mhrd/ui/session_bar.dart';

/// Плашка сеансу телефона не падає, коли місця менше, ніж її довжина (горизонтально з відкритою
/// клавіатурою) — раніше clamp кидав помилку, і замість плашки ставав сірий екран.
void main() {
  for (final edge in BarEdge.values) {
    for (final open in [true, false]) {
      testWidgets('край ${edge.name}, ${open ? 'відкрита' : 'згорнута'}, тісно', (tester) async {
        final expanded = ValueNotifier(open);
        addTearDown(expanded.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: MhrdTokens.graphite.toThemeData(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 90,
                child: FloatingSessionBar(
                  expanded: expanded,
                  placement: BarPlacement(edge: edge, pos: 9000),
                  onPlacement: (_) {},
                  actions: [
                    for (final i in [Icons.mouse, Icons.keyboard, Icons.power_settings_new, Icons.close])
                      (icon: i, tooltip: '', onTap: () {}),
                  ],
                  statusColor: Colors.green,
                  collapseTooltip: '',
                  bottomInset: 60, // клавіатура з'їла більшу частину висоти
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
