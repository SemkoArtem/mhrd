import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Обгортки над діалогами файлів. На платформах без діалогу збереження (Android)
/// файл кладеться в теку документів застосунку, а шлях повертається для показу.

const backupTypes = [XTypeGroup(label: 'Бекап MHRD', extensions: ['rdpbackup'])];
const shareTypes = [XTypeGroup(label: 'Експорт MHRD', extensions: ['json'])];
const rdpTypes = [XTypeGroup(label: 'Файли RDP', extensions: ['rdp'])];
const wgTypes = [XTypeGroup(label: 'Конфігурація WireGuard', extensions: ['conf'])];
const themeTypes = [XTypeGroup(label: 'Тема MHRD', extensions: ['mhrd-theme', 'json'])];

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
