import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'backup/auto_backup.dart';
import 'platform/android_paths.dart';
import 'platform/portable.dart';
import 'platform/shell_bridge.dart';
import 'sessions/rdp_session.dart' show ProcessChannel;
import 'sessions/session_manager.dart';
import 'storage/database.dart';
import 'storage/file_secret_store.dart';
import 'storage/repository.dart';
import 'storage/secret_store.dart';
import 'util/app_files.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  ShellBridge.instance.handleArgs(args); // запуск зі списку «Недавні» на значку: --connect <id>
  // Керування вікном (повний екран сеансу) — лише на десктопах.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) await windowManager.ensureInitialized();
  LicenseRegistry.addLicense(_fontLicenses);
  // Портативна версія — усе поруч із програмою, паролі — у файлі під майстер-паролем (PortableGate).
  final portable = Portable.dataDir;
  final dir = portable ?? await getApplicationSupportDirectory();
  if (portable != null) await portable.create(recursive: true);
  final db = MhrdDatabase.open(dir);
  final repo = Repository(db, await _secretStore(dir, portable: portable != null));
  // Android: модуль сеансу — з теки бібліотек застосунку, зі своїм HOME (android_paths.dart).
  final android = await AndroidPaths.load();
  final sessions = SessionManager(repo,
      enginePath: android?.engine,
      tunnelPath: android?.tunnel,
      channelFactory:
          android == null ? null : (exe) => ProcessChannel.start(exe, environment: android.environment),
      log: SessionLog(Directory('${dir.path}${Platform.pathSeparator}logs')),
      files: AppFiles(dir),
      phoneFolder: android?.transferDir);
  sessions.health.start(); // тунелі й проксі — перевірка зараз і кожні 5 хв
  runApp(MhrdApp(repo: repo, sessions: sessions, autoBackup: AutoBackup(repo)));
}

/// Де лежать паролі: портативна версія — файл під майстер-паролем; Linux без Secret Service — теж
/// (SPEC → «Сховище секретів»), і раз створений файл лишається основним, навіть якщо сховище потім
/// з'явилось (інакше паролі «зникли» б). Решта — системне сховище.
Future<SecretStore> _secretStore(Directory dir, {required bool portable}) async {
  final file = File(p.join(dir.path, Portable.secretsFileName));
  if (portable || (Platform.isLinux && file.existsSync())) return FileSecretStore(file);
  final system = SystemSecretStore();
  if (Platform.isLinux && !await system.available()) return FileSecretStore(file);
  return system;
}

/// Ліцензії OFL вбудованих шрифтів — щоб вони були разом зі шрифтами, як вимагає OFL.
Stream<LicenseEntry> _fontLicenses() async* {
  const files = {
    'IBM Plex Sans': 'IBMPlexSans-OFL.txt',
    'IBM Plex Mono': 'IBMPlexMono-OFL.txt',
    'Manrope': 'Manrope-OFL.txt',
    'Exo 2': 'Exo2-OFL.txt',
    'JetBrains Mono': 'JetBrainsMono-OFL.txt',
  };
  for (final e in files.entries) {
    yield LicenseEntryWithLineBreaks([e.key], await rootBundle.loadString('assets/fonts/licenses/${e.value}'));
  }
}
