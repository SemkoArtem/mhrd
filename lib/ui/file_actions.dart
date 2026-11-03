import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../platform/android_paths.dart';

/// Обгортки над діалогами файлів. Android зберігає системним вікном «Зберегти як»; на інших
/// платформах без діалогу збереження файл кладеться в теку документів застосунку.

List<XTypeGroup> backupTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeBackup, extensions: const ['rdpbackup'])];
List<XTypeGroup> shareTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeShare, extensions: const ['json'])];
List<XTypeGroup> rdpTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeRdp, extensions: const ['rdp'])];
List<XTypeGroup> wgTypes(AppLocalizations l) => [XTypeGroup(label: l.fileTypeWireGuard, extensions: const ['conf'])];

List<XTypeGroup> imageTypes(AppLocalizations l) =>
    [XTypeGroup(label: l.imageFiles, extensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'])];

List<XTypeGroup> themeTypes(AppLocalizations l) =>
    [XTypeGroup(label: l.fileTypeTheme, extensions: const ['mhrd-theme', 'json'])];

/// Зберігає байти у файл, який обере користувач. Повертає шлях або null, якщо скасовано.
Future<String?> saveBytes(Uint8List bytes, String suggestedName, List<XTypeGroup> types) async {
  // Android: системне вікно «Зберегти як» — файл туди, де людина його знайде.
  if (Platform.isAndroid) return AndroidPaths.saveFile(suggestedName, bytes);
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

/// Android: власне вікно вибору (android_paths.dart) — з одразу видимою пам'яттю телефона. Фільтр
/// за типом (MIME) лише для картинок: розширень .rdpbackup, .conf, .rdp, .mhrd-theme Android не знає
/// й сховав би такі файли (вміст однаково перевіряється при читанні).
String _androidMime(List<XTypeGroup> types) {
  const images = {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'};
  return types.every((t) => (t.extensions ?? const []).every(images.contains)) ? 'image/*' : '*/*';
}

/// Відкриває один файл. Повертає (ім'я, байти) або null.
Future<(String, Uint8List)?> openBytes(List<XTypeGroup> types) async {
  if (Platform.isAndroid) {
    final picked = await AndroidPaths.openFiles(mime: _androidMime(types));
    return picked.isEmpty ? null : picked.first;
  }
  final f = await openFile(acceptedTypeGroups: types);
  if (f == null) return null;
  return (f.name, await f.readAsBytes());
}

Future<List<(String, Uint8List)>> openManyBytes(List<XTypeGroup> types) async {
  if (Platform.isAndroid) return AndroidPaths.openFiles(multiple: true, mime: _androidMime(types));
  final files = await openFiles(acceptedTypeGroups: types);
  return [for (final f in files) (f.name, await f.readAsBytes())];
}

Future<String?> pickFolder() => getDirectoryPath();
