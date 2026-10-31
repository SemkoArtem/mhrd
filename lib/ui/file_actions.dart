import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';

/// Обгортки над діалогами файлів. На платформах без діалогу збереження (Android)
/// файл кладеться в теку документів застосунку, а шлях повертається для показу.

List<XTypeGroup> backupTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeBackup, extensions: const ['rdpbackup'])];
List<XTypeGroup> shareTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeShare, extensions: const ['json'])];
List<XTypeGroup> rdpTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeRdp, extensions: const ['rdp'])];
List<XTypeGroup> wgTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeWireGuard, extensions: const ['conf'])];

/// Ключ SSH — будь-який файл (id_ed25519, *.pem, *.key…).
List<XTypeGroup> sshKeyTypes(AppLocalizations l) => [XTypeGroup(label: l.sshAuthKey)];
List<XTypeGroup> themeTypes(AppLocalizations l) =>
    [XTypeGroup(label: l.fileTypeTheme, extensions: const ['mhrd-theme', 'json'])];

/// Зберігає байти у файл, який обере користувач. Повертає шлях або null, якщо скасовано.
Future<String?> saveBytes(Uint8List bytes, String suggestedName, List<XTypeGroup> types) async {
  String? path;
  try {
    path = (await getSaveLocation(suggestedName: suggestedName, acceptedTypeGroups: types))?.path;
    if (path == null) return null;
  } on UnimplementedError {
    final dir = await getApplicationDocumentsDirectory();
    path = p.join(dir.path, suggestedName);
  }
  final tmp = File('$path.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(path);
  return path;
}

/// Відкриває один файл. Повертає (ім'я, байти) або null.
Future<(String, Uint8List)?> openBytes(List<XTypeGroup> types) async {
  final f = await openFile(acceptedTypeGroups: types);
  if (f == null) return null;
  return (f.name, await f.readAsBytes());
}

Future<List<(String, Uint8List)>> openManyBytes(List<XTypeGroup> types) async {
  final files = await openFiles(acceptedTypeGroups: types);
  return [for (final f in files) (f.name, await f.readAsBytes())];
}

Future<String?> pickFolder() => getDirectoryPath();
