import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/backup/backup_service.dart';
import 'package:mhrd/l10n/l10n.dart';
import 'package:mhrd/theme/mhrd_theme.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

Set<String> _keys(Map<String, dynamic> arb) => arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  test('в обох мовах однаковий набір ключів', () {
    final uk = _keys(_arb('uk')), en = _keys(_arb('en'));
    expect(uk.difference(en), isEmpty, reason: 'є в uk, немає в en');
    expect(en.difference(uk), isEmpty, reason: 'є в en, немає в uk');
  });

  test('в екранах не лишилося українських рядків у коді', () {
    final cyrillicLiteral = RegExp(r"""(['"])[^'"\n]*[А-Яа-яІіЇїЄєҐґ][^'"\n]*\1""");
    // Назва мови «Українська» навмисно пишеться своєю мовою в будь-якому інтерфейсі.
    const allowed = {"'Українська'"};
    final problems = <String>[];
    for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        for (final m in cyrillicLiteral.allMatches(line)) {
          if (!allowed.contains(m.group(0))) problems.add('${f.path}:${i + 1}: ${m.group(0)}');
        }
      }
    }
    expect(problems, isEmpty);
  });

  testWidgets('коди помилок і назви тем перекладаються обома мовами', (tester) async {
    for (final locale in supportedLocales) {
      late AppLocalizations l;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
        home: Builder(builder: (context) {
          l = context.l10n;
          return const SizedBox();
        }),
      ));
      for (final e in BackupError.values) {
        expect(l.backupError(e), isNotEmpty);
      }
      for (final t in MhrdTokens.builtIns) {
        expect(l.themeName(t), isNotEmpty);
      }
      final bad = MhrdTokens.graphite.copyWith(text: const Color(0xFF222222)).contrastProblems();
      expect(bad.map(l.contrastIssueText).first, contains(': '));
    }
  });

  testWidgets('невідома мова системи → англійська', (tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      home: Builder(builder: (context) {
        l = context.l10n;
        return const SizedBox();
      }),
    ));
    expect(l.localeName, 'en');
  });
}
