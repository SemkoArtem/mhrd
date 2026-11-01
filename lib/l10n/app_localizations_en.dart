// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get open => 'Open';

  @override
  String get edit => 'Edit';

  @override
  String get export => 'Export';

  @override
  String get import => 'Import';

  @override
  String get always => 'Always';

  @override
  String get never => 'Never';

  @override
  String get disabled => 'Off.';

  @override
  String get name => 'Name';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get settings => 'Settings';

  @override
  String get groups => 'Groups';

  @override
  String get accounts => 'Accounts';

  @override
  String get savedPcs => 'No group';

  @override
  String get invalidAddress => 'Invalid address';

  @override
  String savedTo(String path) {
    return 'Saved: $path';
  }

  @override
  String pcCount(int count) {
    return 'PCs: $count';
  }

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get backupPasswordLabel => 'Backup password';

  @override
  String get repeatPassword => 'Repeat password';

  @override
  String get backupPasswordWarning =>
      'The backup cannot be opened without this password. It cannot be recovered.';

  @override
  String get passwordTooShort => 'At least 8 characters';

  @override
  String get passwordsDontMatch => 'Passwords don\'t match';

  @override
  String get credNewTitle => 'New account';

  @override
  String get credTitle => 'Account';

  @override
  String get credUser => 'User name';

  @override
  String get credUserHelper => 'user, DOMAIN\\user or user@domain';

  @override
  String get credUserRequired => 'Enter a user name';

  @override
  String get credSavePassword => 'Save password';

  @override
  String get credAskEveryTime => 'Ask every time';

  @override
  String get credNewPassword => 'New password (empty = keep current)';

  @override
  String get credStoredNote =>
      'The password is kept in this device\'s system credential store.';

  @override
  String get routeDirect => 'Direct';

  @override
  String get routeTunnelMissing => 'Tunnel (not found)';

  @override
  String get routeProxyMissing => 'Proxy (not found)';

  @override
  String routeGateway(String name) {
    return 'RD Gateway · $name';
  }

  @override
  String routeWithGateway(String route) {
    return '$route + gateway';
  }

  @override
  String accountsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '$count account',
    );
    return '$_temp0';
  }

  @override
  String get statusNotConnected => 'Not connected';

  @override
  String get moreActions => 'More actions';

  @override
  String get connect => 'Connect';

  @override
  String connectAs(String name) {
    return 'Connect as $name';
  }

  @override
  String get duplicate => 'Duplicate';

  @override
  String get exportRdp => 'Export .rdp';

  @override
  String get moveToGroup => 'Move to group';

  @override
  String get wakeOnLan => 'Wake up (Wake-on-LAN)';

  @override
  String copyOf(String name) {
    return '$name (copy)';
  }

  @override
  String get invalidAddressExamples =>
      'Invalid address. Examples: 10.0.0.5, srv.local:3390, [fd00::5]:3389';

  @override
  String connectingTo(String address) {
    return 'Connecting to $address…';
  }

  @override
  String get saveThisPc => 'Save this PC';

  @override
  String deletePcTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String importedPcs(int count) {
    return 'PCs imported: $count';
  }

  @override
  String importedWithErrors(int count, String errors) {
    return 'Imported: $count. Errors: $errors';
  }

  @override
  String get rdpNoAddress => 'the file has no valid address (full address)';

  @override
  String wakeSent(String mac) {
    return 'Wake-up signal sent to $mac. A PC usually starts within 10–60 s.';
  }

  @override
  String wakeFailed(String error) {
    return 'Could not send the signal: $error';
  }

  @override
  String invalidMac(String value) {
    return 'Invalid MAC address: $value';
  }

  @override
  String invalidBroadcast(String value) {
    return 'Invalid broadcast address: $value';
  }

  @override
  String get engineMissing =>
      'The mhrd-session connection module was not found. Please reinstall MHRD.';

  @override
  String sessionConnecting(String name) {
    return 'Connecting to $name…';
  }

  @override
  String get sessionNegotiating => 'Checking the certificate…';

  @override
  String get disconnectAction => 'Disconnect';

  @override
  String get fullscreen => 'Full screen (Ctrl+Alt+Enter)';

  @override
  String get exitFullscreen => 'Exit full screen (Ctrl+Alt+Enter)';

  @override
  String get pinBar => 'Pin the bar';

  @override
  String get unpinBar => 'Unpin the bar';

  @override
  String get barMinimize => 'Minimize';

  @override
  String get onScreenKeyboard => 'On-screen keyboard';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Connect again';

  @override
  String sessionDetails(String details, String code) {
    return 'Details: $details (code $code)';
  }

  @override
  String get reasonUserRequest => 'Disconnected.';

  @override
  String get reasonNetwork =>
      'The PC can\'t be reached. Check the address, the network and whether Remote Desktop is enabled on the PC.';

  @override
  String get reasonAuthFailed => 'Wrong user name or password.';

  @override
  String get reasonNoCredentials =>
      'A user name and password are required to sign in.';

  @override
  String get reasonAccountLocked =>
      'The account is locked, disabled or not allowed to sign in.';

  @override
  String get reasonPasswordExpired =>
      'The password has expired. Change it on the PC or in the domain.';

  @override
  String get reasonCertRejected =>
      'Connection cancelled: the PC certificate was not trusted.';

  @override
  String get reasonTls => 'Could not establish a secure (TLS) connection.';

  @override
  String get reasonServerLogoff => 'The session was ended on the remote PC.';

  @override
  String get reasonOtherConnection =>
      'Another connection to this PC took over the session.';

  @override
  String get reasonServerDenied => 'The PC refused the connection.';

  @override
  String get reasonOther => 'The connection was lost.';

  @override
  String get reasonCrashed =>
      'The session module stopped unexpectedly. MHRD keeps running — try connecting again.';

  @override
  String get certTitle => 'Trust the PC certificate?';

  @override
  String get certChangedTitle => 'The PC certificate has changed!';

  @override
  String certIntro(String host) {
    return 'Make sure you are connecting to $host. If the fingerprint matches the one the PC administrator gave you, trust it.';
  }

  @override
  String get certChangedWarning =>
      'This PC used to have a different certificate. That happens after a system reinstall, but it may also be an attack. Don\'t trust it unless you are sure.';

  @override
  String get certSubject => 'Issued to';

  @override
  String get certIssuer => 'Issued by';

  @override
  String get certFingerprint => 'Fingerprint';

  @override
  String get certReject => 'Don\'t trust';

  @override
  String get certAccept => 'Trust and connect';

  @override
  String get certRemember => 'Remember for this PC and don\'t ask again';

  @override
  String credPromptTitle(String name) {
    return 'Sign in to $name';
  }

  @override
  String get credPromptHint =>
      'These details are used for this connection only.';

  @override
  String get allPcs => 'All PCs';

  @override
  String get recent => 'Recent';

  @override
  String get quickConnectHint => 'Quick connect: PC address';

  @override
  String get addPc => 'Add PC';

  @override
  String get importRdpFiles => 'Import .rdp files';

  @override
  String get computers => 'Computers';

  @override
  String get sidebarToggle => 'Side panel: pin or hide';

  @override
  String get activeTunnels => 'Tunnels & proxies';

  @override
  String get noTunnelsYet => 'None yet. Add them in Settings → Routes.';

  @override
  String healthOk(int ms) {
    return 'Working · replied in $ms ms';
  }

  @override
  String get healthChecking => 'Checking…';

  @override
  String get healthUnknown => 'Not checked yet';

  @override
  String healthCheckedAt(String time) {
    return 'Checked at $time';
  }

  @override
  String get checkNow => 'Check now';

  @override
  String get searchHint => 'Name, address, tag';

  @override
  String get viewTiles => 'Tiles';

  @override
  String get viewList => 'List';

  @override
  String get nothingFound => 'Nothing found';

  @override
  String get nothingFoundHint => 'Try a different name, address or tag.';

  @override
  String get emptyTitle => 'Nothing here yet';

  @override
  String get emptyHint =>
      'Add your first PC, import .rdp files or restore a backup in Settings.';

  @override
  String get editPcTitle => 'Edit PC';

  @override
  String get addressRequired =>
      'Enter an address: 10.0.0.5, srv.local:3390 or [fd00::5]:3389';

  @override
  String get macFormat => 'A MAC address looks like AA:BB:CC:DD:EE:FF';

  @override
  String get broadcastFormat =>
      'The broadcast address must be IPv4, e.g. 192.168.1.255';

  @override
  String get tabGeneral => 'General';

  @override
  String get tabDisplay => 'Display';

  @override
  String get tabDevices => 'Devices';

  @override
  String get tabAdvanced => 'Advanced';

  @override
  String get tabTheme => 'Theme';

  @override
  String get tabRoutes => 'Routes';

  @override
  String get tabBackup => 'Backup';

  @override
  String get pcAddress => 'PC address';

  @override
  String get pcAddressHint => 'Name, IP or name:port';

  @override
  String get nameHelper => 'If empty, the address is shown';

  @override
  String get group => 'Group';

  @override
  String get noAccountsHint =>
      'Ask for user name and password on every connection.';

  @override
  String get defaultAccount => 'Default';

  @override
  String get availableInConnectAs => 'Available in “Connect as…”';

  @override
  String get removeFromPc => 'Remove from this PC';

  @override
  String get addSavedAccount => 'Add saved account';

  @override
  String get route => 'Route';

  @override
  String get routeHow => 'How to connect';

  @override
  String get routeViaTunnel => 'Through a built-in tunnel (WireGuard)';

  @override
  String get routeViaProxy => 'Through a proxy';

  @override
  String get noRouteProfiles =>
      'No profiles yet. Add one in Settings → Routes.';

  @override
  String get profile => 'Profile';

  @override
  String get noGateway => 'No gateway';

  @override
  String get bypassGatewayLocal => 'Bypass the gateway for local addresses';

  @override
  String get sectionConnection => 'Connection';

  @override
  String get reconnectOnDrop => 'Reconnect if the connection drops';

  @override
  String get adminSession => 'Administrative session';

  @override
  String get adminSessionHint =>
      'Connect to the server\'s console session. Windows doesn\'t pass the microphone into this session.';

  @override
  String get swapMouse => 'Swap mouse buttons';

  @override
  String get useAllMonitors => 'Use all monitors';

  @override
  String get startFullscreen => 'Start in full screen';

  @override
  String get asInGeneralSettings => 'As in general settings';

  @override
  String get onWindowResize => 'When the window is resized';

  @override
  String get resizeChangeResolution => 'Change resolution';

  @override
  String get resizeScale => 'Scale';

  @override
  String get resizeNone => 'Keep as is';

  @override
  String get colorDepth => 'Color depth';

  @override
  String get color32 => 'Highest (32 bit)';

  @override
  String get color24 => 'High (24 bit)';

  @override
  String get color16 => 'Medium (16 bit) — less traffic';

  @override
  String get color15 => 'Low (15 bit)';

  @override
  String get remoteScale => 'Scale of items on the remote PC';

  @override
  String get hiDpi => 'Full sharpness on Retina / HiDPI';

  @override
  String get hiDpiWarning => 'About four times more traffic';

  @override
  String get clipboard => 'Clipboard';

  @override
  String get clipboardHint => 'Text, images and files both ways';

  @override
  String get microphone => 'Use this device\'s microphone on the remote PC';

  @override
  String get microphoneHint =>
      'Apps on the remote PC will hear your microphone. Doesn\'t work in an admin session; some servers also need the admin to allow it.';

  @override
  String get sound => 'Remote PC sound';

  @override
  String get soundLocal => 'Play on this PC';

  @override
  String get soundRemote => 'Leave on the remote device';

  @override
  String get soundOff => 'Turn off completely';

  @override
  String get soundRemoteHint =>
      'Sound plays from the remote PC\'s own speakers. If it has none (a server or VPS), you won\'t hear anything anywhere.';

  @override
  String get folders => 'Folders';

  @override
  String get noFolders => 'No folders are shared with the remote PC.';

  @override
  String get readOnly => 'Read-only';

  @override
  String get foldersHint =>
      'Each folder appears on the remote PC as a drive in “This PC”. “Add without deleting”: the PC can read everything and put new files there, but can\'t delete, rename or change what\'s already there.';

  @override
  String get folderAddOnly => 'Add without deleting';

  @override
  String get folderFull => 'Full access';

  @override
  String get removeFolder => 'Remove folder';

  @override
  String get addFolder => 'Add folder';

  @override
  String get tags => 'Tags';

  @override
  String get tagsHelper => 'Comma-separated: office, accounting, servers';

  @override
  String get wolMac => 'MAC address for Wake-on-LAN';

  @override
  String get wolMacHelper => 'To wake the PC from the “Wake up” menu item';

  @override
  String get wolBroadcast => 'Broadcast address for Wake-on-LAN (optional)';

  @override
  String get wolBroadcastHelper =>
      'If the PC is on another subnet — its broadcast, e.g. 192.168.1.255';

  @override
  String get serverCertificate => 'Server certificate';

  @override
  String trustedFingerprint(String fingerprint) {
    return 'Trusted fingerprint: $fingerprint';
  }

  @override
  String get forgetCertificate => 'Forget certificate (ask again on connect)';

  @override
  String inUseTitle(String what) {
    return '$what is in use';
  }

  @override
  String inUseBody(String users) {
    return 'Used by: $users.\nRemove it from there and delete?';
  }

  @override
  String get inUseCredential => 'Account';

  @override
  String get inUseGateway => 'Gateway';

  @override
  String get inUseTunnel => 'Tunnel';

  @override
  String get inUseProxy => 'Proxy';

  @override
  String gatewayUser(String name) {
    return 'gateway $name';
  }

  @override
  String get startSessionsFullscreen => 'Start sessions in full screen';

  @override
  String get keepScreenAwake => 'Keep the screen on during a session';

  @override
  String get showPreviews => 'PC thumbnails in the list';

  @override
  String get keyboardCapture =>
      'Send Win, Alt+Tab and similar keys to the remote PC';

  @override
  String get captureFullscreenOnly => 'Only in full screen';

  @override
  String get accountsHint =>
      'One account can be assigned to many PCs. A password change applies to all of them at once.';

  @override
  String get askPassword => 'Ask for password';

  @override
  String get passwordSaved => 'Password saved';

  @override
  String get addAccount => 'Add account';

  @override
  String get gatewayNew => 'New gateway';

  @override
  String get gatewayTitle => 'Gateway';

  @override
  String get gatewayAddress => 'Gateway address';

  @override
  String get gatewayAccount => 'Account for the gateway';

  @override
  String get gatewaySameAsPc => 'Same as for the PC';

  @override
  String get addGateway => 'Add gateway';

  @override
  String wgImported(String name) {
    return 'Tunnel “$name” imported. Keys are saved in the system credential store.';
  }

  @override
  String get wgImportedExtraPeers =>
      'Imported. The file has several [Peer] sections — only the first is used for now.';

  @override
  String get wgNoPrivateKey =>
      'The file has no PrivateKey in the [Interface] section.';

  @override
  String get wgNoPeer =>
      'The file has no [Peer] section with PublicKey and Endpoint.';

  @override
  String get builtInTunnels => 'Built-in tunnels';

  @override
  String get tunnelsHint =>
      'The tunnel runs inside MHRD: no administrator rights, and it doesn\'t interfere with another VPN. WireGuard is supported. For Tailscale and other VPNs, turn them on in the system and choose \"Direct\".';

  @override
  String get importWireGuard => 'Import WireGuard .conf';

  @override
  String get proxies => 'Proxy';

  @override
  String get comingInStage6 => 'Coming in stage 6.';

  @override
  String get routeErrProxyMissing =>
      'This PC\'s proxy was deleted. Pick a route in the PC settings.';

  @override
  String get routeErrGatewayMissing =>
      'This PC\'s gateway was deleted. Pick another one in the PC settings.';

  @override
  String get routeErrTunnel =>
      'This tunnel type isn\'t supported yet — WireGuard works for now.';

  @override
  String get routeErrTunnelMissing =>
      'This PC\'s tunnel was deleted. Pick a route in the PC settings.';

  @override
  String get routeErrTunnelEngine =>
      'The tunnel module (mhrd-tunnel) wasn\'t found next to the app. Reinstall MHRD.';

  @override
  String get routeErrGatewayTunnel =>
      'RD Gateway together with a tunnel isn\'t supported yet — remove the gateway or the tunnel in the PC settings.';

  @override
  String get tunnelErrConfig =>
      'The tunnel settings are invalid. Check them or import the .conf again.';

  @override
  String get tunnelErrEndpointDns =>
      'Couldn\'t find the tunnel server by name.';

  @override
  String get tunnelErrStart => 'Couldn\'t start the tunnel.';

  @override
  String get tunnelErrUnreachable =>
      'The tunnel is up, but the PC doesn\'t respond. Check that the tunnel server works and the PC is in its network.';

  @override
  String get tunnelErrConnect => 'Couldn\'t connect to the tunnel server.';

  @override
  String get tunnelErrListen => 'Couldn\'t open a local port for the tunnel.';

  @override
  String get tunnelErrFailed => 'The tunnel stopped unexpectedly.';

  @override
  String get tunnelErrHandshake =>
      'The WireGuard server doesn\'t respond. Check the server address, the keys and whether the network blocks UDP.';

  @override
  String get proxyErrUnreachable =>
      'The proxy is unreachable: couldn\'t connect. Check the address and port.';

  @override
  String get proxyErrProtocol =>
      'This address isn\'t a proxy of the selected type. Check the type (SOCKS5 or HTTP) and the port.';

  @override
  String get proxyErrAuth => 'The proxy rejected the username or password.';

  @override
  String get proxyErrRefused =>
      'The proxy works but won\'t let you through to the PC. Such proxies often allow only websites (port 443) and block RDP (3389).';

  @override
  String get resolution => 'Remote screen resolution';

  @override
  String get resolutionHint =>
      'Fit to window follows the window as you resize it. A template always keeps the same resolution and scales the picture.';

  @override
  String get screenAuto => 'Fit to window';

  @override
  String get screenPortrait => 'portrait';

  @override
  String asInGeneralSettingsWith(String name) {
    return 'As in general settings ($name)';
  }

  @override
  String get screenTemplates => 'Screen templates';

  @override
  String get defaultScreen => 'Default resolution for all PCs';

  @override
  String get customScreens => 'Your templates';

  @override
  String get noCustomScreens =>
      'None yet. The standard ones — HD, Full HD, QHD, 4K, portrait — are already in the list.';

  @override
  String get addScreen => 'Add template';

  @override
  String get screenName => 'Name';

  @override
  String get screenWidth => 'Width';

  @override
  String get screenHeight => 'Height';

  @override
  String get screenSizeInvalid =>
      'Width and height must be 200 to 8192 pixels.';

  @override
  String get checkConnection => 'Check connection';

  @override
  String pcResponds(int ms) {
    return 'The PC responds · $ms ms over the whole route';
  }

  @override
  String get probeErrPc =>
      'The PC doesn\'t answer on the RDP port: it\'s off, a firewall blocks it, or the address or port is wrong.';

  @override
  String get probeErrGateway =>
      'The RD Gateway doesn\'t answer. Check the gateway address and port.';

  @override
  String get addProxy => 'Add proxy';

  @override
  String get proxyNew => 'New proxy';

  @override
  String get proxyTitle => 'Proxy';

  @override
  String get proxyType => 'Type';

  @override
  String get proxyAddress => 'Proxy address';

  @override
  String get proxyLoginHint =>
      'Login and password — only if the proxy requires them';

  @override
  String get groupNew => 'New group';

  @override
  String get groupRename => 'Rename group';

  @override
  String groupNestInto(String name) {
    return 'Put “$name” into…';
  }

  @override
  String get topLevel => 'Top level';

  @override
  String groupMoveContentsTo(String name) {
    return 'Where should the contents of “$name” go?';
  }

  @override
  String groupDeleteTitle(String name) {
    return 'Delete group “$name”?';
  }

  @override
  String defaultGroupInfo(int count) {
    return 'Default group · PCs: $count';
  }

  @override
  String get nestIntoOther => 'Put into another group';

  @override
  String get groupCycle => 'A group cannot be nested inside itself.';

  @override
  String get backupPasswordTitle => 'Backup password';

  @override
  String get encryptingBackup => 'Encrypting backup…';

  @override
  String backupSaved(String path) {
    return 'Backup saved: $path';
  }

  @override
  String get decrypting => 'Decrypting…';

  @override
  String get restoreHow => 'How to restore?';

  @override
  String get restoreMerge => 'Merge with current data';

  @override
  String get restoreReplace =>
      'Replace everything (current data is saved to a safety copy first)';

  @override
  String get restoreConfirmTitle => 'Restore backup?';

  @override
  String restorePreview(int added, int updated, int removed) {
    return 'PCs to add: $added, update: $updated, delete: $removed.';
  }

  @override
  String get restore => 'Restore';

  @override
  String get restored => 'Backup restored.';

  @override
  String savedWithoutPasswords(String path) {
    return 'Saved without passwords: $path';
  }

  @override
  String get shareImported => 'Imported. Enter passwords on first connection.';

  @override
  String get fullBackup => 'Full backup';

  @override
  String get fullBackupHint =>
      'All PCs, accounts with passwords, gateways, tunnels with keys, groups, themes and settings. The file is encrypted with your password (Argon2id + AES-256-GCM) and opens on any OS.';

  @override
  String get backupNever => 'No backup has been made yet.';

  @override
  String backupLast(String date) {
    return 'Last backup: $date';
  }

  @override
  String get saveBackup => 'Save backup';

  @override
  String get restoreFromBackup => 'Restore from backup';

  @override
  String get sharePcList => 'Share PC list';

  @override
  String get sharePcListHint =>
      'A file without any passwords or keys — to give the list to a colleague.';

  @override
  String get backupNotMhrdFile => 'This is not an MHRD backup file.';

  @override
  String get backupCorrupted => 'The backup file is damaged.';

  @override
  String get backupWrongPassword => 'Wrong password or the file is damaged.';

  @override
  String get backupFromNewer =>
      'The backup was made by a newer MHRD version. Please update the app.';

  @override
  String get notShareFile => 'This is not an MHRD export file.';

  @override
  String get autoBackup => 'Automatic backup';

  @override
  String get autoBackupHint =>
      'After changes, at most once an hour — to a folder of your choice, e.g. one synced to the cloud. The last 10 copies are kept. The automatic backup password is kept in this device\'s system credential store.';

  @override
  String get autoBackupPasswordTitle => 'Automatic backup password';

  @override
  String get autoBackupFirstCopy => 'Making the first copy…';

  @override
  String autoBackupEnabled(String path) {
    return 'Automatic backup is on. First copy: $path';
  }

  @override
  String get autoBackupMaking => 'Making a copy…';

  @override
  String autoBackupSaved(String path) {
    return 'Copy saved: $path';
  }

  @override
  String get autoBackupBusy => 'A copy is already being made.';

  @override
  String get autoBackupNone => 'No copies yet.';

  @override
  String autoBackupLast(String date) {
    return 'Last copy: $date';
  }

  @override
  String get enableEllipsis => 'Turn on…';

  @override
  String get autoBackupNow => 'Make a copy now';

  @override
  String get autoBackupChange => 'Change folder and password';

  @override
  String get disable => 'Turn off';

  @override
  String autoBackupWriteFailed(String path, String reason) {
    return 'Could not write a copy to $path: $reason';
  }

  @override
  String get autoBackupNoPassword =>
      'The automatic backup password was not found in the system credential store. Turn automatic backup on again.';

  @override
  String autoBackupFailed(String error) {
    return 'Automatic backup failed: $error';
  }

  @override
  String get themeGraphite => 'Graphite';

  @override
  String get themeLight => 'Light Tool';

  @override
  String get themeAmber => 'Night Amber';

  @override
  String themeMine(String name) {
    return '$name (mine)';
  }

  @override
  String get contrastWarnTitle => 'Text may be hard to read';

  @override
  String contrastWarnBody(String problems) {
    return '$problems\n\nSave anyway?';
  }

  @override
  String themeSaved(String path) {
    return 'Theme saved: $path';
  }

  @override
  String get notThemeFile => 'This is not an MHRD theme file.';

  @override
  String themeAdded(String name) {
    return 'Theme “$name” added.';
  }

  @override
  String get createTheme => 'Create your own theme';

  @override
  String get importTheme => 'Import theme';

  @override
  String get exportCurrentTheme => 'Export current';

  @override
  String get editCurrentTheme => 'Edit current';

  @override
  String get deleteCurrentTheme => 'Delete current';

  @override
  String get themeNameLabel => 'Theme name';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLightMode => 'Light';

  @override
  String get colorBackground => 'Background';

  @override
  String get colorSurface => 'Panels';

  @override
  String get colorSurfaceRaised => 'Fields and chips';

  @override
  String get colorBorder => 'Borders';

  @override
  String get colorText => 'Text';

  @override
  String get colorTextMuted => 'Secondary text';

  @override
  String get colorAccent => 'Accent';

  @override
  String get colorOnAccent => 'Text on accent';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusReconnecting => 'Reconnecting';

  @override
  String reconnectAttempt(String n, String max) {
    return 'attempt $n of $max';
  }

  @override
  String latencyMs(String n) {
    return '$n ms';
  }

  @override
  String get statusError => 'Error';

  @override
  String get radius => 'Corner radius';

  @override
  String get textSize => 'Text size';

  @override
  String get densityCompact => 'Compact';

  @override
  String get densityNormal => 'Normal';

  @override
  String get densitySpacious => 'Spacious';

  @override
  String get motionFull => 'Animations';

  @override
  String get motionEssential => 'Minimal';

  @override
  String get motionOff => 'Off';

  @override
  String contrastBad(String problems) {
    return 'Hard to read:\n$problems';
  }

  @override
  String get contrastFine => 'Text contrast is fine.';

  @override
  String get saveAndApply => 'Save and apply';

  @override
  String get previewPcName => 'Office — Accounting';

  @override
  String get contrastTextOnBackground => 'Text on background';

  @override
  String get contrastTextOnSurface => 'Text on panel';

  @override
  String get contrastMutedOnSurface => 'Secondary text on panel';

  @override
  String get contrastOnAccent => 'Text on accent button';

  @override
  String get contrastStatusConnected => '“Connected” status';

  @override
  String get contrastStatusError => '“Error” status';

  @override
  String contrastIssue(String label, String ratio) {
    return '$label: $ratio : 1 (needs 4.5)';
  }

  @override
  String get fileTypeBackup => 'MHRD backup';

  @override
  String get fileTypeShare => 'MHRD export';

  @override
  String get fileTypeRdp => 'RDP files';

  @override
  String get fileTypeWireGuard => 'WireGuard configuration';

  @override
  String get fileTypeTheme => 'MHRD theme';
}
