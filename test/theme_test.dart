import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/theme/mhrd_theme.dart';

void main() {
  test('усі вбудовані теми проходять перевірку контрасту', () {
    for (final t in MhrdTokens.builtIns) {
      expect(t.contrastProblems(), isEmpty, reason: t.name);
    }
  });

  test('погана тема ловиться', () {
    final bad = MhrdTokens.graphite.copyWith(text: const Color(0xFF222222));
    expect(bad.contrastProblems(), isNotEmpty);
  });

  test('JSON теми туди й назад', () {
    final t = MhrdTokens.light.copyWith(id: 'custom:1', name: 'Моя', radius: 4);
    final back = MhrdTokens.fromJson(t.toJson());
    expect(back.toJson(), t.toJson());
  });

  test('чужі шрифти й некоректні значення відкидаються', () {
    final j = MhrdTokens.graphite.toJson()
      ..['fontSans'] = 'http://evil.example/font.ttf'
      ..['radius'] = 999
      ..['colors'] = {'accent': 'red', 'text': '#FFFFFF'};
    final t = MhrdTokens.fromJson(j);
    expect(t.fontSans, MhrdTokens.graphite.fontSans);
    expect(t.radius, 20);
    expect(t.accent, MhrdTokens.graphite.accent);
    expect(t.text, const Color(0xFFFFFFFF));
  });

  test('не тема — помилка', () {
    expect(() => MhrdTokens.fromJson(const {'kind': 'other'}), throwsFormatException);
  });
}
