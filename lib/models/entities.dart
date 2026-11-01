import 'json_util.dart';

/// Обліковий запис. Пароль лежить у системному сховищі під ключем [secretKey].
enum AuthMode { savedPassword, askPassword }

class Credential {
  const Credential({
    required this.id,
    required this.name,
    required this.username,
    this.authMode = AuthMode.savedPassword,
  });

  final String id;

  /// Зрозуміла назва, наприклад «Робочий адмін». Може бути порожньою.
  final String name;

  /// user, DOMAIN\user або user@domain.
  final String username;
  final AuthMode authMode;

  String get secretKey => 'mhrd.cred.$id';
  String get label => name.trim().isEmpty ? username : '${name.trim()} ($username)';

  Credential copyWith({String? name, String? username, AuthMode? authMode}) => Credential(
        id: id,
        name: name ?? this.name,
        username: username ?? this.username,
        authMode: authMode ?? this.authMode,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'username': username, 'authMode': authMode.name};

  factory Credential.fromJson(Map<String, dynamic> j) => Credential(
        id: strOr(j['id'], ''),
        name: strOr(j['name'], ''),
        username: strOr(j['username'], ''),
        authMode: enumByName(AuthMode.values, j['authMode'], AuthMode.savedPassword),
      );
}

class Group {
  const Group({required this.id, required this.name, this.parentId, this.sortOrder = 0});

  final String id;
  final String name;

  /// Вкладені групи. Цикли блокує репозиторій.
  final String? parentId;
  final int sortOrder;

  Group copyWith({String? name, String? Function()? parentId, int? sortOrder}) => Group(
        id: id,
        name: name ?? this.name,
        parentId: parentId != null ? parentId() : this.parentId,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'parentId': parentId, 'sortOrder': sortOrder};

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: strOr(j['id'], ''),
        name: strOr(j['name'], ''),
        parentId: strOrNull(j['parentId']),
        sortOrder: intOr(j['sortOrder'], 0),
      );
}

/// Облікові дані для RD Gateway: такі самі, як для ПК, або окремий акаунт.
enum GatewayCredentialMode { sameAsPc, own }

class Gateway {
  const Gateway({
    required this.id,
    required this.name,
    required this.host,
    this.port = 443,
    this.credentialMode = GatewayCredentialMode.sameAsPc,
    this.credentialId,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final GatewayCredentialMode credentialMode;
  final String? credentialId;

  String get label => name.trim().isEmpty ? host : name.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'credentialMode': credentialMode.name,
        'credentialId': credentialId,
      };

  factory Gateway.fromJson(Map<String, dynamic> j) => Gateway(
        id: strOr(j['id'], ''),
        name: strOr(j['name'], ''),
        host: strOr(j['host'], ''),
        port: intOr(j['port'], 443),
        credentialMode: enumByName(
            GatewayCredentialMode.values, j['credentialMode'], GatewayCredentialMode.sameAsPc),
        credentialId: strOrNull(j['credentialId']),
      );
}

enum TunnelType { wireguard }

/// Профіль вбудованого тунелю. [config] — лише несекретні поля;
/// секрети (приватний ключ, PSK, паролі) — у сховищі під [secretKey].
class TunnelProfile {
  const TunnelProfile({
    required this.id,
    required this.name,
    required this.type,
    this.config = const {},
    this.secretFields = const [],
  });

  final String id;
  final String name;
  final TunnelType type;

  /// WireGuard: addresses, dns, mtu, peerPublicKey, endpoint, allowedIps, keepalive.
  final Map<String, dynamic> config;

  /// Назви секретних полів, що лежать у сховищі (наприклад privateKey, presharedKey).
  final List<String> secretFields;

  String secretKey(String field) => 'mhrd.tunnel.$id.$field';

  /// Назва для людей: своя або «WireGuard · сервер», якщо назви немає.
  String get label => name.trim().isNotEmpty ? name.trim() : 'WireGuard · ${config['endpoint'] ?? ''}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'config': config,
        'secretFields': secretFields,
      };

  factory TunnelProfile.fromJson(Map<String, dynamic> j) => TunnelProfile(
        id: strOr(j['id'], ''),
        name: strOr(j['name'], ''),
        type: enumByName(TunnelType.values, j['type'], TunnelType.wireguard),
        config: mapOr(j['config']),
        secretFields: stringList(j['secretFields']),
      );
}

enum ProxyType { socks5, http }

class ProxyProfile {
  const ProxyProfile({
    required this.id,
    required this.name,
    this.type = ProxyType.socks5,
    required this.host,
    required this.port,
    this.username = '',
  });

  final String id;
  final String name;
  final ProxyType type;
  final String host;
  final int port;
  final String username;

  String get secretKey => 'mhrd.proxy.$id';

  /// Назва для людей: своя або «SOCKS5 · host:port», якщо назви немає.
  String get label =>
      name.trim().isNotEmpty ? name.trim() : '${type == ProxyType.http ? 'HTTP' : 'SOCKS5'} · $host:$port';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
      };

  factory ProxyProfile.fromJson(Map<String, dynamic> j) => ProxyProfile(
        id: strOr(j['id'], ''),
        name: strOr(j['name'], ''),
        type: enumByName(ProxyType.values, j['type'], ProxyType.socks5),
        host: strOr(j['host'], ''),
        port: intOr(j['port'], 1080),
        username: strOr(j['username'], ''),
      );
}

enum PcListView { tiles, list }

/// Куди йдуть Win, Alt+Tab тощо.
enum KeyboardCapture { fullscreenOnly, always, never }

/// Шаблон екрана: роздільність віддаленого ПК. Стандартні — [builtins], свої — у налаштуваннях.
class ScreenTemplate {
  const ScreenTemplate({required this.id, required this.name, required this.width, required this.height});

  final String id;

  /// Для стандартних — порожня: назву показують самі розміри (і «вертикальний» з орієнтації).
  final String name;
  final int width, height;

  bool get portrait => height > width;
  bool get builtin => id.startsWith('builtin:');

  /// «Під розмір вікна» — роздільність підлаштовується під вікно сеансу (типово).
  static const auto = 'auto';

  static const builtins = [
    ScreenTemplate(id: 'builtin:hd', name: 'HD', width: 1280, height: 720),
    ScreenTemplate(id: 'builtin:hdplus', name: 'HD+', width: 1600, height: 900),
    ScreenTemplate(id: 'builtin:fhd', name: 'Full HD', width: 1920, height: 1080),
    ScreenTemplate(id: 'builtin:wuxga', name: 'WUXGA', width: 1920, height: 1200),
    ScreenTemplate(id: 'builtin:qhd', name: 'QHD', width: 2560, height: 1440),
    ScreenTemplate(id: 'builtin:uwqhd', name: 'UltraWide', width: 3440, height: 1440),
    ScreenTemplate(id: 'builtin:4k', name: '4K', width: 3840, height: 2160),
    ScreenTemplate(id: 'builtin:fhd-portrait', name: 'Full HD', width: 1080, height: 1920),
    ScreenTemplate(id: 'builtin:hd-portrait', name: 'HD', width: 720, height: 1280),
  ];

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'width': width, 'height': height};

  factory ScreenTemplate.fromJson(Map<String, dynamic> j) => ScreenTemplate(
        id: strOr(j['id'], ''),
        name: strOr(j['name'], ''),
        width: intOr(j['width'], 1920).clamp(200, 8192),
        height: intOr(j['height'], 1080).clamp(200, 8192),
      );
}

/// Край вікна сеансу, до якого притулена плашка. Порядок = номери в native/session (barEdge).
enum BarEdge { top, bottom, left, right }

/// Де плашка у вікні сеансу: користувач перетягує її сам, MHRD запам'ятовує для всіх сеансів.
class BarPlacement {
  const BarPlacement({this.edge = BarEdge.top, this.pos = 5000, this.length = 0});

  final BarEdge edge;

  /// Центр уздовж краю: 0..10000 (5000 — посередині).
  final int pos;

  /// Довжина в одиницях інтерфейсу; 0 — типова.
  final int length;

  Map<String, dynamic> toJson() => {'edge': edge.index, 'pos': pos, 'length': length};

  factory BarPlacement.fromJson(Map<String, dynamic> j) => BarPlacement(
        edge: BarEdge.values[intOr(j['edge'], 0).clamp(0, BarEdge.values.length - 1)],
        pos: intOr(j['pos'], 5000).clamp(0, 10000),
        length: intOr(j['length'], 0).clamp(0, 10000),
      );
}

class AppSettings {
  const AppSettings({
    this.language = 'system',
    this.themeId = 'graphite',
    this.listView = PcListView.tiles,
    this.showPreviews = true,
    this.startFullscreen = false,
    this.keepScreenAwake = true,
    this.keyboardCapture = KeyboardCapture.fullscreenOnly,
    this.bar = const BarPlacement(),
    this.sidebarShown = true,
    this.collapsedGroups = const [noGroupSection],
    this.screenTemplates = const [],
    this.defaultScreen = ScreenTemplate.auto,
    this.lockEnabled = false,
    this.lockBiometric = false,
    this.lastBackupAt,
  });

  /// Розділ «Без групи» у списку «Усі ПК» (у [collapsedGroups] поруч з id груп).
  static const noGroupSection = '__nogroup';

  /// Мова інтерфейсу: 'system' (як в ОС, інакше англійська), 'uk' або 'en'.
  final String language;

  /// id вбудованої теми або власної (`custom:<uuid>`), або 'system'.
  final String themeId;
  final PcListView listView;
  final bool showPreviews;
  final bool startFullscreen;
  final bool keepScreenAwake;
  final KeyboardCapture keyboardCapture;
  final BarPlacement bar;

  /// Ліва панель на широкому екрані: закріплена (true) чи схована — тоді відкривається кнопкою.
  final bool sidebarShown;

  /// Згорнуті розділи списку «Усі ПК»: id груп і [noGroupSection].
  final List<String> collapsedGroups;

  /// Свої шаблони екрана (стандартні — [ScreenTemplate.builtins]).
  final List<ScreenTemplate> screenTemplates;

  /// Типовий шаблон для ПК, у яких «як у загальних»: id шаблону або [ScreenTemplate.auto].
  final String defaultScreen;

  /// Блокування MHRD при запуску PIN-кодом (сам PIN — лише хеш у сховищі, див. AppLock).
  final bool lockEnabled;

  /// Відкривати також відбитком / Windows Hello.
  final bool lockBiometric;
  final DateTime? lastBackupAt;

  /// Усі шаблони: стандартні, потім свої.
  List<ScreenTemplate> get allScreenTemplates => [...ScreenTemplate.builtins, ...screenTemplates];

  ScreenTemplate? screenTemplate(String? id) => allScreenTemplates.where((t) => t.id == id).firstOrNull;

  /// Фіксована роздільність для ПК або null — під розмір вікна. [screen], [width], [height] — з
  /// налаштувань екрана ПК: вибраний шаблон, інакше старі власні розміри, інакше типовий шаблон.
  (int, int)? resolutionFor({String? screen, int? width, int? height}) {
    if (screen == null && width != null && height != null) return (width, height);
    final t = screenTemplate(screen ?? defaultScreen); // зниклий шаблон — під вікно
    return t == null ? null : (t.width, t.height);
  }

  AppSettings copyWith({
    String? language,
    String? themeId,
    PcListView? listView,
    bool? showPreviews,
    bool? startFullscreen,
    bool? keepScreenAwake,
    KeyboardCapture? keyboardCapture,
    BarPlacement? bar,
    bool? sidebarShown,
    List<String>? collapsedGroups,
    List<ScreenTemplate>? screenTemplates,
    String? defaultScreen,
    bool? lockEnabled,
    bool? lockBiometric,
    DateTime? lastBackupAt,
  }) =>
      AppSettings(
        language: language ?? this.language,
        themeId: themeId ?? this.themeId,
        listView: listView ?? this.listView,
        showPreviews: showPreviews ?? this.showPreviews,
        startFullscreen: startFullscreen ?? this.startFullscreen,
        keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
        keyboardCapture: keyboardCapture ?? this.keyboardCapture,
        bar: bar ?? this.bar,
        sidebarShown: sidebarShown ?? this.sidebarShown,
        collapsedGroups: collapsedGroups ?? this.collapsedGroups,
        screenTemplates: screenTemplates ?? this.screenTemplates,
        defaultScreen: defaultScreen ?? this.defaultScreen,
        lockEnabled: lockEnabled ?? this.lockEnabled,
        lockBiometric: lockBiometric ?? this.lockBiometric,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      );

  Map<String, dynamic> toJson() => {
        'language': language,
        'themeId': themeId,
        'listView': listView.name,
        'showPreviews': showPreviews,
        'startFullscreen': startFullscreen,
        'keepScreenAwake': keepScreenAwake,
        'keyboardCapture': keyboardCapture.name,
        'bar': bar.toJson(),
        'sidebarShown': sidebarShown,
        'collapsedGroups': collapsedGroups,
        'screenTemplates': [for (final t in screenTemplates) t.toJson()],
        'defaultScreen': defaultScreen,
        'lockEnabled': lockEnabled,
        'lockBiometric': lockBiometric,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        language: const ['system', 'uk', 'en'].contains(j['language']) ? j['language'] as String : 'system',
        themeId: strOr(j['themeId'], 'graphite'),
        listView: enumByName(PcListView.values, j['listView'], PcListView.tiles),
        showPreviews: boolOr(j['showPreviews'], true),
        startFullscreen: boolOr(j['startFullscreen'], false),
        keepScreenAwake: boolOr(j['keepScreenAwake'], true),
        keyboardCapture:
            enumByName(KeyboardCapture.values, j['keyboardCapture'], KeyboardCapture.fullscreenOnly),
        bar: BarPlacement.fromJson(mapOr(j['bar'])),
        sidebarShown: boolOr(j['sidebarShown'], true),
        collapsedGroups: j.containsKey('collapsedGroups') ? stringList(j['collapsedGroups']) : const [noGroupSection],
        screenTemplates: [
          if (j['screenTemplates'] is List)
            for (final x in j['screenTemplates'] as List)
              if (x is Map) ScreenTemplate.fromJson(x.cast<String, dynamic>()),
        ],
        defaultScreen: strOr(j['defaultScreen'], ScreenTemplate.auto),
        lockEnabled: boolOr(j['lockEnabled'], false),
        lockBiometric: boolOr(j['lockBiometric'], false),
        lastBackupAt: dateOrNull(j['lastBackupAt']),
      );
}
