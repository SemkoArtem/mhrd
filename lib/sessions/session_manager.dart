import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/connection.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import 'rdp_session.dart';

export 'rdp_session.dart' show RdpSession, SessionState;

/// Облікові дані для одного підключення. password == null — UI має спитати.
class ConnectCredentials {
  const ConnectCredentials({this.username, this.password});
  final String? username;
  final String? password;

  bool get complete => (username ?? '').isNotEmpty && (password ?? '').isNotEmpty;
}

typedef ChannelFactory = Future<SessionChannel> Function(String executable);

/// Керує активними сеансами. Кожен сеанс — окремий процес `mhrd-session` (SPEC → «Архітектура»).
class SessionManager extends ChangeNotifier {
  SessionManager(this.repo, {String? enginePath, ChannelFactory? channelFactory})
      : enginePath = enginePath ?? _defaultEnginePath(),
        _channelFactory = channelFactory ?? ProcessChannel.start;

  final Repository repo;

  /// Шлях до `mhrd-session`; null — модуля підключення немає (наприклад, ще не зібрано).
  final String? enginePath;
  final ChannelFactory _channelFactory;
  final List<RdpSession> sessions = [];

  bool get engineAvailable => enginePath != null;

  /// `mhrd-session.exe` лежить поруч із головною програмою (його кладе туди збірка Windows).
  static String? _defaultEnginePath() {
    if (!Platform.isWindows) return null;
    final path = p.join(p.dirname(Platform.resolvedExecutable), 'mhrd-session.exe');
    return File(path).existsSync() ? path : null;
  }

  /// Акаунт для підключення: вибраний у «Підключитись як…» або перший у ПК.
  /// Пароль читається із системного сховища, якщо акаунт його зберігає.
  Future<ConnectCredentials> credentialsFor(Connection c, {String? credentialId}) async {
    final id = credentialId ?? (c.credentialIds.isEmpty ? null : c.credentialIds.first);
    final cred = id == null ? null : repo.credentials[id];
    if (cred == null) return const ConnectCredentials();
    final pw = cred.authMode == AuthMode.savedPassword ? await repo.secrets.read(cred.secretKey) : null;
    return ConnectCredentials(username: cred.username, password: pw);
  }

  /// Запускає сеанс. [width]/[height] — бажана роздільність віддаленого екрана.
  Future<RdpSession> start(
    Connection c, {
    required String username,
    required String password,
    required int width,
    required int height,
  }) async {
    final exe = enginePath;
    if (exe == null) throw StateError('mhrd-session not found');
    if (repo.connections.containsKey(c.id)) repo.markUsed(c.id);
    final channel = await _channelFactory(exe);
    final s = RdpSession(
      id: '${c.id}#${DateTime.now().microsecondsSinceEpoch}',
      connection: c,
      channel: channel,
      swapMouseButtons: c.swapMouseButtons,
    );
    sessions.add(s);
    s.start({
      'host': c.host,
      'port': c.port,
      'username': username,
      'password': password,
      'width': width,
      'height': height,
      'colorDepth': c.display.colorDepth,
      'adminSession': c.adminSession,
      'reconnect': c.reconnectOnDrop,
      'certPin': c.certPin,
      // Пристрої (SPEC → «Перенаправлення пристроїв»)
      'clipboard': c.devices.clipboard,
      'sound': c.devices.sound.name, // local | remote | off
      'microphone': c.devices.microphone,
      // «Лише читання» FreeRDP не вміє — такі папки не підключаємо зовсім, а не тихо з записом.
      'folders': [
        for (final f in c.devices.folders)
          if (!f.readOnly) {'name': f.name, 'path': f.path},
      ],
    });
    notifyListeners();
    return s;
  }

  /// Користувач довіряє сертифікату: запам'ятовуємо відбиток у ПК (для швидкого
  /// підключення, якого немає в списку, просто продовжуємо).
  void trustCertificate(RdpSession s, String fingerprint) {
    final c = repo.connections[s.connection.id];
    if (c != null) repo.saveConnection(c.copyWith(certPin: () => fingerprint));
  }

  RdpSession? forConnection(String connectionId) {
    for (final s in sessions) {
      if (s.connection.id == connectionId && s.isActive) return s;
    }
    return null;
  }

  /// Прибирає сеанс зі списку (після відключення чи закриття екрана). Звільняє його,
  /// лише коли процес справді завершився — інакше не спрацює примусове закриття за 5 с.
  void close(RdpSession s) {
    if (!sessions.remove(s)) return;
    s.disconnect();
    s.done.then((_) => s.dispose());
    notifyListeners();
  }
}
