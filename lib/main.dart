import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'backup/auto_backup.dart';
import 'sessions/session_manager.dart';
import 'storage/database.dart';
import 'storage/repository.dart';
import 'storage/secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Керування вікном (повний екран сеансу) — лише на десктопах.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) await windowManager.ensureInitialized();
  LicenseRegistry.addLicense(_fontLicenses);
  final dir = await getApplicationSupportDirectory();
  final db = MhrdDatabase.open(dir);
  final repo = Repository(db, SystemSecretStore());
  final sessions = SessionManager(repo, log: SessionLog(Directory('${dir.path}${Platform.pathSeparator}logs')));
  runApp(MhrdApp(repo: repo, sessions: sessions, autoBackup: AutoBackup(repo)));
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
