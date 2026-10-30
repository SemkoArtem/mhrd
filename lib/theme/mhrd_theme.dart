import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/json_util.dart';

enum Density { compact, normal, spacious }

enum MotionLevel { full, essential, off }

/// Пари «текст на фоні», які перевіряє [MhrdTokens.contrastProblems].
enum ContrastPair { textOnBackground, textOnSurface, mutedOnSurface, onAccent, statusConnected, statusError }

class ContrastIssue {
  const ContrastIssue(this.pair, this.ratio);
  final ContrastPair pair;
  final double ratio;
}

/// Токени теми MHRD. Усі кольори й розміри інтерфейсу беруться ЛИШЕ звідси
/// (через `context.mhrd`), ніколи не вписуються в екрани напряму.
/// Див. SPEC.md → «Теми й оформлення».
@immutable
class MhrdTokens extends ThemeExtension<MhrdTokens> {
  const MhrdTokens({
    required this.id,
    required this.name,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.error,
    this.fontSans = 'IBM Plex Sans',
    this.fontMono = 'IBM Plex Mono',
    this.textScale = 1.0,
    this.radius = 12,
    this.density = Density.normal,
    this.motion = MotionLevel.full,
  });

  final String id;
  final String name;
  final Brightness brightness;

  final Color background; // фон вікна
  final Color surface; // панелі, картки
  final Color surfaceRaised; // поля, чипи, кнопки другого рівня
  final Color border;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color ok; // підключено
  final Color warn; // перепідключення
  final Color error; // помилка

  final String fontSans;
  final String fontMono;
  final double textScale; // 0.9–1.3
  final double radius; // 0–20
  final Density density;
  final MotionLevel motion;

  /// Відступ-одиниця з урахуванням щільності.
  double get gap => switch (density) {
        Density.compact => 6,
        Density.normal => 8,
        Density.spacious => 10,
      };

  Duration get fast => motion == MotionLevel.full ? const Duration(milliseconds: 180) : Duration.zero;

  TextStyle get mono => TextStyle(fontFamily: fontMono, color: textMuted, fontSize: 12.5);

  // ── Вбудовані теми ──────────────────────────────────────────────

  static const graphite = MhrdTokens(
    id: 'graphite',
    name: 'Графіт',
    brightness: Brightness.dark,
    background: Color(0xFF0C0D0F),
    surface: Color(0xFF141619),
    surfaceRaised: Color(0xFF1E2125),
    border: Color(0xFF2C3036),
    text: Color(0xFFE8EAED),
    textMuted: Color(0xFF9AA0A6),
    accent: Color(0xFFC6F432),
    onAccent: Color(0xFF0C0D0F),
    ok: Color(0xFFC6F432),
    warn: Color(0xFFF2B33D),
    error: Color(0xFFFF8A7A),
    radius: 12,
  );

  static const light = MhrdTokens(
    id: 'light',
    name: 'Світлий інструмент',
    brightness: Brightness.light,
    background: Color(0xFFEEF1F5),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF2F4F7),
    border: Color(0xFFD0D5DD),
    text: Color(0xFF101828),
    textMuted: Color(0xFF475467),
    accent: Color(0xFF2453D6),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF1F7A45),
    warn: Color(0xFF9A5A00),
    error: Color(0xFFB42318),
    fontSans: 'Manrope',
    fontMono: 'JetBrains Mono',
    radius: 14,
  );

  static const amber = MhrdTokens(
    id: 'amber',
    name: 'Нічний бурштин',
    brightness: Brightness.dark,
    background: Color(0xFF0B1220),
    surface: Color(0xFF111A2D),
    surfaceRaised: Color(0xFF18243C),
    border: Color(0xFF24324F),
    text: Color(0xFFE6EAF2),
    textMuted: Color(0xFFA9B4C8),
    accent: Color(0xFFF5A524),
    onAccent: Color(0xFF0B1220),
    ok: Color(0xFF7BD88F),
    warn: Color(0xFFF5A524),
    error: Color(0xFFFF8F80),
    fontSans: 'Exo 2',
    fontMono: 'JetBrains Mono',
    radius: 12,
  );

  static const builtIns = [graphite, light, amber];

  // ── Перевірка контрасту (WCAG) ──────────────────────────────────

  static double _lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  static double contrast(Color a, Color b) {
    final la = _lum(a), lb = _lum(b);
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Пари «текст на фоні», що мають бути читабельними (≥ 4.5 : 1).
  /// Порожній список = усе гаразд; текст проблем складає UI.
  List<ContrastIssue> contrastProblems() {
    final pairs = <ContrastPair, (Color, Color)>{
      ContrastPair.textOnBackground: (text, background),
      ContrastPair.textOnSurface: (text, surface),
      ContrastPair.mutedOnSurface: (textMuted, surface),
      ContrastPair.onAccent: (onAccent, accent),
      ContrastPair.statusConnected: (ok, surface),
      ContrastPair.statusError: (error, surface),
    };
    return [
      for (final e in pairs.entries)
        if (contrast(e.value.$1, e.value.$2) < 4.5) ContrastIssue(e.key, contrast(e.value.$1, e.value.$2)),
    ];
  }

  // ── Серіалізація (.mhrd-theme) ──────────────────────────────────

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color? _parseHex(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
    return m == null ? null : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }

  /// Шрифти, які можна задати в темі (лише з вбудованого набору — без шляхів і посилань).
  static const allowedFonts = [
    'IBM Plex Sans', 'IBM Plex Mono', 'Manrope', 'Exo 2', 'JetBrains Mono', 'system',
  ];

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'kind': 'mhrd-theme',
        'id': id,
        'name': name,
        'brightness': brightness.name,
        'colors': {
          'background': _hex(background),
          'surface': _hex(surface),
          'surfaceRaised': _hex(surfaceRaised),
          'border': _hex(border),
          'text': _hex(text),
          'textMuted': _hex(textMuted),
          'accent': _hex(accent),
          'onAccent': _hex(onAccent),
          'ok': _hex(ok),
          'warn': _hex(warn),
          'error': _hex(error),
        },
        'fontSans': fontSans,
        'fontMono': fontMono,
        'textScale': textScale,
        'radius': radius,
        'density': density.name,
        'motion': motion.name,
      };

  /// Читає тему з JSON. Невідомі або некоректні значення беруться з [base].
  /// Будь-що, крім кольорів, чисел і назв шрифтів із [allowedFonts], ігнорується.
  factory MhrdTokens.fromJson(Map<String, dynamic> j, {MhrdTokens base = graphite}) {
    if (j['kind'] != 'mhrd-theme') {
      throw const FormatException('Це не файл теми MHRD.');
    }
    final c = mapOr(j['colors']);
    String font(Object? v, String fb) => (v is String && allowedFonts.contains(v)) ? v : fb;
    double clampD(Object? v, double lo, double hi, double fb) =>
        v is num ? v.toDouble().clamp(lo, hi).toDouble() : fb;
    return MhrdTokens(
      id: strOr(j['id'], base.id),
      name: strOr(j['name'], base.name),
      brightness: j['brightness'] == 'light' ? Brightness.light : Brightness.dark,
      background: _parseHex(c['background']) ?? base.background,
      surface: _parseHex(c['surface']) ?? base.surface,
      surfaceRaised: _parseHex(c['surfaceRaised']) ?? base.surfaceRaised,
      border: _parseHex(c['border']) ?? base.border,
      text: _parseHex(c['text']) ?? base.text,
      textMuted: _parseHex(c['textMuted']) ?? base.textMuted,
      accent: _parseHex(c['accent']) ?? base.accent,
      onAccent: _parseHex(c['onAccent']) ?? base.onAccent,
      ok: _parseHex(c['ok']) ?? base.ok,
      warn: _parseHex(c['warn']) ?? base.warn,
      error: _parseHex(c['error']) ?? base.error,
      fontSans: font(j['fontSans'], base.fontSans),
      fontMono: font(j['fontMono'], base.fontMono),
      textScale: clampD(j['textScale'], 0.9, 1.3, base.textScale),
      radius: clampD(j['radius'], 0, 20, base.radius),
      density: enumByName(Density.values, j['density'], base.density),
      motion: enumByName(MotionLevel.values, j['motion'], base.motion),
    );
  }

  // ── ThemeExtension ──────────────────────────────────────────────

  @override
  MhrdTokens copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? ok,
    Color? warn,
    Color? error,
    String? fontSans,
    String? fontMono,
    double? textScale,
    double? radius,
    Density? density,
    MotionLevel? motion,
  }) =>
      MhrdTokens(
        id: id ?? this.id,
        name: name ?? this.name,
        brightness: brightness ?? this.brightness,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        border: border ?? this.border,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        error: error ?? this.error,
        fontSans: fontSans ?? this.fontSans,
        fontMono: fontMono ?? this.fontMono,
        textScale: textScale ?? this.textScale,
        radius: radius ?? this.radius,
        density: density ?? this.density,
        motion: motion ?? this.motion,
      );

  @override
  MhrdTokens lerp(ThemeExtension<MhrdTokens>? other, double t) {
    if (other is! MhrdTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return t < 0.5
        ? copyWith(
            background: l(background, other.background),
            surface: l(surface, other.surface),
            text: l(text, other.text),
          )
        : other;
  }

  /// Повна ThemeData для MaterialApp на основі токенів.
  ThemeData toThemeData() {
    final family = fontSans == 'system' ? null : fontSans;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: error,
      onError: background,
      surface: surface,
      onSurface: text,
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius * 0.75));
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: family,
      dividerColor: border,
      extensions: [this],
      visualDensity: switch (density) {
        Density.compact => VisualDensity.compact,
        Density.normal => VisualDensity.standard,
        Density.spacious => VisualDensity.comfortable,
      },
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: shape,
          minimumSize: const Size(44, 44),
          textStyle: TextStyle(fontFamily: family, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          shape: shape,
          minimumSize: const Size(44, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius * 0.75),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius * 0.75),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius * 0.75),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: textMuted),
        hintStyle: TextStyle(color: textMuted),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: TextStyle(color: text, fontFamily: family),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: textMuted,
        indicatorColor: accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? onAccent : textMuted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : surfaceRaised),
      ),
    );
  }
}

extension MhrdContext on BuildContext {
  MhrdTokens get mhrd => Theme.of(this).extension<MhrdTokens>() ?? MhrdTokens.graphite;
}
