import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'sessions/session_manager.dart';
import 'storage/database.dart';
import 'storage/repository.dart';
import 'storage/secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final db = MhrdDatabase.open(dir);
  final repo = Repository(db, SystemSecretStore());
  runApp(MhrdApp(repo: repo, sessions: SessionManager(repo)));
}
