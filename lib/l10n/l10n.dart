import 'package:flutter/widgets.dart';

import '../backup/auto_backup.dart';
import '../backup/backup_service.dart';
import '../sessions/session_manager.dart' show ProxyError, RouteError, TunnelError;
import '../sessions/session_protocol.dart';
import '../storage/repository.dart';
import '../theme/mhrd_theme.dart';
import '../util/wake_on_lan.dart';
import '../util/wireguard_conf.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// Мови інтерфейсу. Порядок важливий: якщо мова ОС не підтримується, береться перша — англійська.
const supportedLocales = [Locale('en'), Locale('uk')];

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Тексти для кодів помилок і назв, що приходять з логіки (там немає BuildContext).
extension L10nMessages on AppLocalizations {
  String backupError(BackupError e) => switch (e) {
        BackupError.notBackupFile => backupNotMhrdFile,
        BackupError.corrupted => backupCorrupted,
        BackupError.wrongPassword => backupWrongPassword,
        BackupError.newerVersion => backupFromNewer,
        BackupError.notShareFile => notShareFile,
      };

  String wireGuardError(WireGuardConfError e) => switch (e) {
        WireGuardConfError.noPrivateKey => wgNoPrivateKey,
        WireGuardConfError.noPeer => wgNoPeer,
      };

  String wakeOnLanError(WakeOnLanException e) => switch (e.error) {
        WakeOnLanError.invalidMac => invalidMac(e.value),
        WakeOnLanError.invalidBroadcast => invalidBroadcast(e.value),
      };

  String autoBackupFailure(AutoBackupFailure f) => switch (f.kind) {
        AutoBackupFailureKind.writeFailed => autoBackupWriteFailed(f.path, f.detail),
        AutoBackupFailureKind.noPassword => autoBackupNoPassword,
        AutoBackupFailureKind.other => autoBackupFailed(f.detail),
      };

  String routeError(RouteError e) => switch (e) {
        RouteError.proxyMissing => routeErrProxyMissing,
        RouteError.gatewayMissing => routeErrGatewayMissing,
        RouteError.tunnelMissing => routeErrTunnelMissing,
        RouteError.tunnelUnsupported => routeErrTunnel,
        RouteError.tunnelEngineMissing => routeErrTunnelEngine,
        RouteError.gatewayWithTunnel => routeErrGatewayTunnel,
      };

  String tunnelError(TunnelError e) => switch (e) {
        TunnelError.config => tunnelErrConfig,
        TunnelError.endpointDns => tunnelErrEndpointDns,
        TunnelError.start => tunnelErrStart,
        TunnelError.unreachable => tunnelErrUnreachable,
        TunnelError.connect => tunnelErrConnect,
        TunnelError.listen => tunnelErrListen,
        TunnelError.handshake => tunnelErrHandshake,
        TunnelError.failed => tunnelErrFailed,
      };

  String proxyError(ProxyError e) => switch (e) {
        ProxyError.unreachable => proxyErrUnreachable,
        ProxyError.protocol => proxyErrProtocol,
        ProxyError.auth => proxyErrAuth,
        ProxyError.refused => proxyErrRefused,
      };

  /// Чому маршрут не пройшов перевірку.
  String healthError(Object e) => switch (e) {
        final TunnelError t => tunnelError(t),
        final ProxyError p => proxyError(p),
        final RouteError r => routeError(r),
        _ => tunnelErrFailed,
      };

  String inUseKind(InUseKind k) => switch (k) {
        InUseKind.credential => inUseCredential,
        InUseKind.gateway => inUseGateway,
        InUseKind.tunnel => inUseTunnel,
        InUseKind.proxy => inUseProxy,
      };

  /// «ПК 1, ПК 2, шлюз gw.example.com».
  String inUseUsers(InUse e) => [...e.pcs, ...e.gateways.map(gatewayUser)].join(', ');

  String disconnectReason(DisconnectReason r) => switch (r) {
        DisconnectReason.userRequest => reasonUserRequest,
        DisconnectReason.network => reasonNetwork,
        DisconnectReason.authFailed => reasonAuthFailed,
        DisconnectReason.noCredentials => reasonNoCredentials,
        DisconnectReason.accountLocked => reasonAccountLocked,
        DisconnectReason.passwordExpired => reasonPasswordExpired,
        DisconnectReason.certRejected => reasonCertRejected,
        DisconnectReason.tls => reasonTls,
        DisconnectReason.serverLogoff => reasonServerLogoff,
        DisconnectReason.otherConnection => reasonOtherConnection,
        DisconnectReason.serverDenied => reasonServerDenied,
        DisconnectReason.other => reasonOther,
        DisconnectReason.crashed => reasonCrashed,
      };

  /// Назва теми: вбудовані — перекладені, власні — як назвав користувач.
  String themeName(MhrdTokens t) => switch (t.id) {
        'graphite' => themeGraphite,
        'light' => themeLight,
        'amber' => themeAmber,
        _ => t.name,
      };

  String contrastIssueText(ContrastIssue i) => contrastIssue(
        switch (i.pair) {
          ContrastPair.textOnBackground => contrastTextOnBackground,
          ContrastPair.textOnSurface => contrastTextOnSurface,
          ContrastPair.mutedOnSurface => contrastMutedOnSurface,
          ContrastPair.onAccent => contrastOnAccent,
          ContrastPair.statusConnected => contrastStatusConnected,
          ContrastPair.statusError => contrastStatusError,
        },
        i.ratio.toStringAsFixed(1),
      );
}
