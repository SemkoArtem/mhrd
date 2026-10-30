import 'package:flutter/foundation.dart';

import '../models/connection.dart';
import '../storage/repository.dart';

/// Стани сеансу (SPEC.md → «Підключення й сеанс» → «Стани сесії»).
enum SessionState {
  resolving,
  tunneling,
  connecting,
  negotiating,
  authenticating,
  connected,
  reconnecting,
  disconnected,
  failed,
}

class Session {
  Session({required this.id, required this.connectionId, required this.title});
  final String id;
  final String connectionId;
  final String title;
  SessionState state = SessionState.resolving;
  String? message;
}

/// Керує активними сеансами. Етап 1: каркас без RDP-ядра.
/// Етап 2 підключить сюди нативний міст до FreeRDP (native/rdp_bridge, dart:ffi):
/// connect → routes.open → native.start; події native → зміна [Session.state].
class SessionManager extends ChangeNotifier {
  SessionManager(this.repo);

  final Repository repo;
  final List<Session> sessions = [];

  /// Чи вже є RDP-ядро. Поки false — UI показує пояснення замість підключення.
  bool get engineAvailable => false;

  Session? forConnection(String connectionId) {
    for (final s in sessions) {
      if (s.connectionId == connectionId) return s;
    }
    return null;
  }

  /// Повертає текст для користувача, якщо підключення поки неможливе.
  String? connect(Connection c, {String? credentialId}) {
    repo.markUsed(c.id);
    if (!engineAvailable) {
      return 'RDP-ядро ще не підключене — це етап 2. '
          'Профіль «${c.displayName}» збережено, усе інше вже працює.';
    }
    // TODO(етап 2): створити Session, відкрити маршрут, запустити FreeRDP.
    return null;
  }

  void close(String sessionId) {
    sessions.removeWhere((s) => s.id == sessionId);
    notifyListeners();
  }
}
