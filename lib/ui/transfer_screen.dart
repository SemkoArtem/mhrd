import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/l10n.dart';
import '../platform/android_paths.dart';
import '../theme/mhrd_theme.dart';
import 'dialogs.dart';

/// Android: тека обміну файлами з ПК. Під час сеансу вона — диск «Phone» на віддаленому ПК: що
/// скопіювали туди на ПК — з'являється тут; що додали тут (кнопкою чи «Поділитися → MHRD») — є на ПК.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key, required this.dir});

  final String dir;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  List<File> _files = const [];
  StreamSubscription<FileSystemEvent>? _watch;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
    // ПК пише на диск «Phone» під час сеансу — список оновлюється сам.
    try {
      _watch = Directory(widget.dir).watch(recursive: true).listen((_) => _load());
    } on FileSystemException {
      // без стеження — оновиться при наступному відкритті
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  void _load() {
    final dir = Directory(widget.dir);
    final files = <File>[];
    try {
      if (dir.existsSync()) {
        files.addAll(dir.listSync(recursive: true, followLinks: false).whereType<File>());
      }
    } on FileSystemException {
      // тека зайнята чи зникла — покажемо, що вдалося прочитати
    }
    DateTime modified(File f) {
      try {
        return f.lastModifiedSync();
      } on FileSystemException {
        return DateTime(0);
      }
    }

    files.sort((a, b) => modified(b).compareTo(modified(a)));
    if (mounted) setState(() => _files = files);
  }

  String _size(int bytes) {
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    var v = bytes.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return u == 0 ? '$bytes ${units[0]}' : '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[u]}';
  }

  IconData _icon(String name) => switch (p.extension(name).toLowerCase()) {
        '.jpg' || '.jpeg' || '.png' || '.gif' || '.webp' || '.heic' || '.bmp' => Icons.image_outlined,
        '.mp4' || '.mov' || '.mkv' || '.avi' || '.webm' => Icons.movie_outlined,
        '.mp3' || '.wav' || '.ogg' || '.m4a' || '.flac' => Icons.audiotrack_outlined,
        '.pdf' => Icons.picture_as_pdf_outlined,
        '.zip' || '.rar' || '.7z' || '.tar' || '.gz' => Icons.folder_zip_outlined,
        '.doc' || '.docx' || '.odt' || '.txt' || '.rtf' => Icons.description_outlined,
        '.xls' || '.xlsx' || '.ods' || '.csv' => Icons.table_chart_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  Future<void> _import() async {
    final l = context.l10n;
    setState(() => _importing = true);
    final n = await AndroidPaths.transferImport();
    if (!mounted) return;
    setState(() => _importing = false);
    _load();
    if (n > 0) toast(context, l.transferAdded(n));
  }

  Future<void> _action(String action, File f) async {
    final l = context.l10n;
    final name = p.basename(f.path);
    switch (action) {
      case 'open':
        if (!await AndroidPaths.transferOpen(f.path) && mounted) toast(context, l.transferNoApp);
      case 'share':
        await AndroidPaths.transferShare(f.path);
      case 'save':
        final saved = await AndroidPaths.transferSave(f.path);
        if (saved != null && mounted) toast(context, l.savedTo(saved));
      case 'delete':
        if (await confirm(context, title: l.transferDeleteTitle(name), ok: l.delete, danger: true)) {
          try {
            f.deleteSync();
          } on FileSystemException {
            // уже немає
          }
          _load();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mhrd;
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: t.surface,
        title: Text(l.transferTitle),
        actions: [
          IconButton(
            tooltip: l.transferAdd,
            icon: _importing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            onPressed: _importing ? null : _import,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Text(l.transferHint, style: TextStyle(color: t.textMuted)),
          const SizedBox(height: 12),
          if (_files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text(l.transferEmpty, style: TextStyle(color: t.textMuted))),
            ),
          for (final f in _files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icon(f.path), color: t.textMuted),
              title: Text(p.relative(f.path, from: widget.dir), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(_size(f.existsSync() ? f.lengthSync() : 0), style: TextStyle(color: t.textMuted)),
              onTap: () => _action('open', f),
              trailing: PopupMenuButton<String>(
                onSelected: (a) => _action(a, f),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'open', child: Text(l.transferOpen)),
                  PopupMenuItem(value: 'share', child: Text(l.transferShare)),
                  PopupMenuItem(value: 'save', child: Text(l.transferSave)),
                  PopupMenuItem(value: 'delete', child: Text(l.delete)),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
