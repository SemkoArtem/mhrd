import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import 'dialogs.dart';
import 'file_actions.dart';

/// Вибір теми і редактор власної теми з живим переглядом і перевіркою контрасту.
class ThemeEditor extends StatefulWidget {
  const ThemeEditor({super.key});

  @override
  State<ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<ThemeEditor> {
  MhrdTokens? _draft;

  Repository get repo => AppScope.of(context).repo;

  void _startFrom(MhrdTokens base) => setState(() => _draft = base.copyWith(
        id: 'custom:${newId()}',
        name: '${base.name} (моя)',
      ));

  Future<void> _saveDraft() async {
    final d = _draft!;
    final problems = d.contrastProblems();
    if (problems.isNotEmpty &&
        !await confirm(context,
            title: 'Текст може бути погано видно',
            body: '${problems.join('\n')}\n\nЗберегти все одно?',
            ok: 'Зберегти')) {
      return;
    }
    repo.saveTheme(d);
    repo.updateSettings(repo.settings.copyWith(themeId: d.id));
    setState(() => _draft = null);
  }

  Future<void> _export(MhrdTokens th) async {
    final json = const JsonEncoder.withIndent('  ').convert(th.toJson());
    final safe = th.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await saveBytes(Uint8List.fromList(utf8.encode(json)), '$safe.mhrd-theme', themeTypes);
    if (path != null && mounted) toast(context, 'Тему збережено: $path');
  }

  Future<void> _import() async {
    final f = await openBytes(themeTypes);
    if (f == null) return;
    try {
      final j = jsonDecode(utf8.decode(f.$2));
      if (j is! Map<String, dynamic>) throw const FormatException('Це не файл теми MHRD.');
      // Завжди новий id, щоб чужа тема не перезаписала вашу.
      final th = MhrdTokens.fromJson(j).copyWith(id: 'custom:${newId()}');
      repo.saveTheme(th);
      if (mounted) toast(context, 'Тему «${th.name}» додано.');
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final current = repo.settings.themeId;
    final all = [...MhrdTokens.builtIns, ...repo.customThemes.values];

    Widget themeCard(String id, String name, MhrdTokens? th) {
      final selected = current == id;
      return InkWell(
        borderRadius: BorderRadius.circular(t.radius),
        onTap: () => repo.updateSettings(repo.settings.copyWith(themeId: id)),
        child: AnimatedContainer(
          duration: t.fast,
          width: 190,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.radius),
            border: Border.all(color: selected ? t.accent : t.border, width: selected ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (th != null)
                for (final c in [th.background, th.surface, th.accent, th.text])
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                        color: c, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.border)),
                  )
              else
                Icon(Icons.brightness_auto, color: t.textMuted),
            ]),
            const SizedBox(height: 10),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text)),
          ]),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            themeCard('system', 'Як у системі', null),
            for (final th in all) themeCard(th.id, th.name, th),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              icon: const Icon(Icons.palette_outlined),
              label: const Text('Створити свою тему'),
              onPressed: () => _startFrom(repo.themeFor(MediaQuery.platformBrightnessOf(context))),
            ),
            OutlinedButton.icon(
                icon: const Icon(Icons.file_open_outlined), label: const Text('Імпортувати тему'), onPressed: _import),
            if (repo.customThemes.containsKey(current)) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.ios_share),
                label: const Text('Експортувати поточну'),
                onPressed: () => _export(repo.customThemes[current]!),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Редагувати поточну'),
                onPressed: () => setState(() => _draft = repo.customThemes[current]),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Видалити поточну'),
                onPressed: () => repo.deleteTheme(current),
              ),
            ],
          ]),
          if (_draft != null) ...[
            const SizedBox(height: 24),
            _DraftEditor(
              draft: _draft!,
              onChanged: (d) => setState(() => _draft = d),
              onSave: _saveDraft,
              onCancel: () => setState(() => _draft = null),
            ),
          ],
        ]),
      ),
    );
  }
}

class _DraftEditor extends StatelessWidget {
  const _DraftEditor({required this.draft, required this.onChanged, required this.onSave, required this.onCancel});

  final MhrdTokens draft;
  final ValueChanged<MhrdTokens> onChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final d = draft;
    final problems = d.contrastProblems();

    Widget color(String label, Color value, MhrdTokens Function(Color) apply) =>
        _ColorField(label: label, value: value, onChanged: (c) => onChanged(apply(c)));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextFormField(
          key: ValueKey('name-${d.id}'),
          initialValue: d.name,
          decoration: const InputDecoration(labelText: 'Назва теми'),
          onChanged: (v) => onChanged(d.copyWith(name: v)),
        ),
        const SizedBox(height: 14),
        SegmentedButton<Brightness>(
          segments: const [
            ButtonSegment(value: Brightness.dark, label: Text('Темна')),
            ButtonSegment(value: Brightness.light, label: Text('Світла')),
          ],
          selected: {d.brightness},
          onSelectionChanged: (s) => onChanged(d.copyWith(brightness: s.first)),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          color('Фон', d.background, (c) => d.copyWith(background: c)),
          color('Панелі', d.surface, (c) => d.copyWith(surface: c)),
          color('Поля й чипи', d.surfaceRaised, (c) => d.copyWith(surfaceRaised: c)),
          color('Рамки', d.border, (c) => d.copyWith(border: c)),
          color('Текст', d.text, (c) => d.copyWith(text: c)),
          color('Другорядний текст', d.textMuted, (c) => d.copyWith(textMuted: c)),
          color('Акцент', d.accent, (c) => d.copyWith(accent: c)),
          color('Текст на акценті', d.onAccent, (c) => d.copyWith(onAccent: c)),
          color('Підключено', d.ok, (c) => d.copyWith(ok: c)),
          color('Перепідключення', d.warn, (c) => d.copyWith(warn: c)),
          color('Помилка', d.error, (c) => d.copyWith(error: c)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          const SizedBox(width: 160, child: Text('Заокруглення')),
          Expanded(
            child: Slider(
              value: d.radius,
              min: 0,
              max: 20,
              divisions: 20,
              label: '${d.radius.round()} px',
              onChanged: (v) => onChanged(d.copyWith(radius: v)),
            ),
          ),
        ]),
        Row(children: [
          const SizedBox(width: 160, child: Text('Розмір тексту')),
          Expanded(
            child: Slider(
              value: d.textScale,
              min: 0.9,
              max: 1.3,
              divisions: 8,
              label: '${(d.textScale * 100).round()} %',
              onChanged: (v) => onChanged(d.copyWith(textScale: v)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 12, children: [
          SegmentedButton<Density>(
            segments: const [
              ButtonSegment(value: Density.compact, label: Text('Компактно')),
              ButtonSegment(value: Density.normal, label: Text('Звичайно')),
              ButtonSegment(value: Density.spacious, label: Text('Просторо')),
            ],
            selected: {d.density},
            onSelectionChanged: (s) => onChanged(d.copyWith(density: s.first)),
          ),
          SegmentedButton<MotionLevel>(
            segments: const [
              ButtonSegment(value: MotionLevel.full, label: Text('Анімації')),
              ButtonSegment(value: MotionLevel.essential, label: Text('Мінімум')),
              ButtonSegment(value: MotionLevel.off, label: Text('Вимкнено')),
            ],
            selected: {d.motion},
            onSelectionChanged: (s) => onChanged(d.copyWith(motion: s.first)),
          ),
        ]),
        const SizedBox(height: 18),
        _Preview(tokens: d),
        const SizedBox(height: 12),
        if (problems.isNotEmpty)
          Text('Погано читається:\n${problems.join('\n')}', style: TextStyle(color: t.warn, fontSize: 13))
        else
          Text('Контраст тексту в нормі.', style: TextStyle(color: t.textMuted, fontSize: 13)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, children: [
          FilledButton(onPressed: onSave, child: const Text('Зберегти й застосувати')),
          TextButton(onPressed: onCancel, child: const Text('Скасувати')),
        ]),
      ]),
    );
  }
}

/// Мініатюра плитки ПК у кольорах чернетки.
class _Preview extends StatelessWidget {
  const _Preview({required this.tokens});
  final MhrdTokens tokens;

  @override
  Widget build(BuildContext context) {
    final d = tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: d.background, borderRadius: BorderRadius.circular(d.radius)),
      child: Row(children: [
        Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: d.surface,
            borderRadius: BorderRadius.circular(d.radius),
            border: Border.all(color: d.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Офіс — Бухгалтерія', style: TextStyle(color: d.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('10.20.0.15', style: TextStyle(color: d.textMuted, fontFamily: d.fontMono, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: d.ok, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Підключено', style: TextStyle(color: d.ok, fontSize: 12)),
            ]),
          ]),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: d.accent, borderRadius: BorderRadius.circular(d.radius * 0.75)),
          child: Text('Додати', style: TextStyle(color: d.onAccent, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// Поле кольору: квадратик + HEX.
class _ColorField extends StatefulWidget {
  const _ColorField({required this.label, required this.value, required this.onChanged});
  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _ctrl = TextEditingController(text: _hex(widget.value));

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void didUpdateWidget(_ColorField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text.toUpperCase() != _hex(widget.value)) {
      _ctrl.text = _hex(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    return SizedBox(
      width: 200,
      child: TextField(
        controller: _ctrl,
        style: TextStyle(fontFamily: t.fontMono, fontSize: 13),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: widget.value,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.border),
              ),
            ),
          ),
        ),
        onChanged: (v) {
          final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
          if (m != null) widget.onChanged(Color(0xFF000000 | int.parse(m.group(1)!, radix: 16)));
        },
      ),
    );
  }
}
