// Цей файл існує, щоб `flutter create .` не підкладав свій шаблонний тест.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/theme/mhrd_theme.dart';

void main() {
  for (final t in MhrdTokens.builtIns) {
    testWidgets('тема «${t.name}» будується і дає токени через context', (tester) async {
      late MhrdTokens seen;
      await tester.pumpWidget(MaterialApp(
        theme: t.toThemeData(),
        home: Builder(builder: (context) {
          seen = context.mhrd;
          return const Scaffold(body: Text('MHRD'));
        }),
      ));
      expect(find.text('MHRD'), findsOneWidget);
      expect(seen.id, t.id);
    });
  }
}
