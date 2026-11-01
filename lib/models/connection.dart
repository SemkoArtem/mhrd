import 'json_util.dart';

/// Як дістатися до ПК. Див. SPEC.md → «Вбудовані тунелі», «Інші маршрути».
enum RouteKind { direct, tunnel, proxy }

/// Поведінка при зміні розміру вікна сеансу.
enum ResizeMode { changeResolution, scale, none }

/// Де відтворювати звук віддаленого ПК.
enum SoundMode { local, remote, off }

class DisplaySettings {
  const DisplaySettings({
    this.useAllMonitors = false,
    this.startFullscreen,
    this.resizeMode = ResizeMode.changeResolution,
    this.colorDepth = 32,
    this.hiDpi = true,
    this.scalePercent = 100,
    this.width,
    this.height,
    this.screen,
  });

  final bool useAllMonitors;

  /// null = як у загальних налаштуваннях.
  final bool? startFullscreen;
  final ResizeMode resizeMode;

  /// 15, 16, 24 або 32.
  final int colorDepth;
  /// Повна чіткість (фізичні пікселі екрана); вимкнено — логічна роздільність, ~4× менше трафіку.
  final bool hiDpi;

  /// Масштаб елементів на віддаленому ПК, 100–300.
  final int scalePercent;

  /// Старі власні розміри (до шаблонів екрана); діють, лише якщо [screen] не вибрано.
  final int? width;
  final int? height;

  /// Шаблон екрана: null — як у загальних налаштуваннях, `auto` — під розмір вікна, інакше id шаблону.
  final String? screen;

  DisplaySettings copyWith({
    bool? useAllMonitors,
    bool? Function()? startFullscreen,
    ResizeMode? resizeMode,
    int? colorDepth,
    bool? hiDpi,
    int? scalePercent,
    int? Function()? width,
    int? Function()? height,
    String? Function()? screen,
  }) =>
      DisplaySettings(
        screen: screen != null ? screen() : this.screen,
        useAllMonitors: useAllMonitors ?? this.useAllMonitors,
        startFullscreen: startFullscreen != null ? startFullscreen() : this.startFullscreen,
        resizeMode: resizeMode ?? this.resizeMode,
        colorDepth: colorDepth ?? this.colorDepth,
        hiDpi: hiDpi ?? this.hiDpi,
        scalePercent: scalePercent ?? this.scalePercent,
        width: width != null ? width() : this.width,
        height: height != null ? height() : this.height,
      );

  Map<String, dynamic> toJson() => {
        'useAllMonitors': useAllMonitors,
        'startFullscreen': startFullscreen,
        'resizeMode': resizeMode.name,
        'colorDepth': colorDepth,
        'hiDpiOn': hiDpi,
        'scalePercent': scalePercent,
        'width': width,
        'height': height,
        'screen': screen,
      };

  factory DisplaySettings.fromJson(Map<String, dynamic> j) => DisplaySettings(
        useAllMonitors: boolOr(j['useAllMonitors'], false),
        startFullscreen: j['startFullscreen'] is bool ? j['startFullscreen'] as bool : null,
        resizeMode: enumByName(ResizeMode.values, j['resizeMode'], ResizeMode.changeResolution),
        colorDepth: intOr(j['colorDepth'], 32),
        // Старе поле «hiDpi» ніколи нічого не вмикало (сеанс і так ішов у повній чіткості) — не читаємо.
        hiDpi: boolOr(j['hiDpiOn'], true),
        scalePercent: intOr(j['scalePercent'], 100),
        width: j['width'] is int ? j['width'] as int : null,
        height: j['height'] is int ? j['height'] as int : null,
        screen: strOrNull(j['screen']),
      );
}

/// Що віддалений ПК може робити в спільній папці.
enum FolderAccess {
  /// Читати, створювати, змінювати, видаляти.
  full,

  /// Читати все й класти нове; видаляти, перейменовувати й змінювати наявне — ні.
  addOnly,

  /// Лише читати.
  readOnly,
}

class SharedFolder {
  const SharedFolder({required this.name, required this.path, this.access = FolderAccess.addOnly});

  final String name;
  final String path;
  final FolderAccess access;

  SharedFolder copyWith({FolderAccess? access}) => SharedFolder(name: name, path: path, access: access ?? this.access);

  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'access': access.name};

  factory SharedFolder.fromJson(Map<String, dynamic> j) => SharedFolder(
        name: strOr(j['name'], ''),
        path: strOr(j['path'], ''),
        // Старі записи мали лише прапорець readOnly.
        access: j['access'] is String
            ? enumByName(FolderAccess.values, j['access'], FolderAccess.addOnly)
            : (boolOr(j['readOnly'], false) ? FolderAccess.readOnly : FolderAccess.full),
      );
}

class DeviceSettings {
  const DeviceSettings({
    this.clipboard = true,
    this.sound = SoundMode.local,
    this.microphone = false,
    this.folders = const [],
  });

  final bool clipboard;
  final SoundMode sound;
  final bool microphone;
  final List<SharedFolder> folders;

  DeviceSettings copyWith({
    bool? clipboard,
    SoundMode? sound,
    bool? microphone,
    List<SharedFolder>? folders,
  }) =>
      DeviceSettings(
        clipboard: clipboard ?? this.clipboard,
        sound: sound ?? this.sound,
        microphone: microphone ?? this.microphone,
        folders: folders ?? this.folders,
      );

  Map<String, dynamic> toJson() => {
        'clipboard': clipboard,
        'sound': sound.name,
        'microphone': microphone,
        'folders': folders.map((f) => f.toJson()).toList(),
      };

  factory DeviceSettings.fromJson(Map<String, dynamic> j) => DeviceSettings(
        clipboard: boolOr(j['clipboard'], true),
        sound: enumByName(SoundMode.values, j['sound'], SoundMode.local),
        microphone: boolOr(j['microphone'], false),
        folders: (j['folders'] is List)
            ? (j['folders'] as List).map((e) => SharedFolder.fromJson(mapOr(e))).toList()
            : const [],
      );
}

class WakeOnLan {
  const WakeOnLan({required this.mac, this.broadcast = '255.255.255.255', this.port = 9});

  final String mac;
  final String broadcast;
  final int port;

  Map<String, dynamic> toJson() => {'mac': mac, 'broadcast': broadcast, 'port': port};

  factory WakeOnLan.fromJson(Map<String, dynamic> j) => WakeOnLan(
        mac: strOr(j['mac'], ''),
        broadcast: strOr(j['broadcast'], '255.255.255.255'),
        port: intOr(j['port'], 9),
      );
}

/// Збережений ПК. Секретів тут немає: лише посилання (id) на акаунти й маршрути.
class Connection {
  const Connection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 3389,
    this.groupId,
    this.tags = const [],
    this.credentialIds = const [],
    this.route = RouteKind.direct,
    this.routeRefId,
    this.gatewayId,
    this.gatewayBypassLocal = false,
    this.adminSession = false,
    this.swapMouseButtons = false,
    this.reconnectOnDrop = true,
    this.display = const DisplaySettings(),
    this.devices = const DeviceSettings(),
    this.certPin,
    this.wakeOnLan,
    this.lastUsed,
    this.image,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Порожня назва → в інтерфейсі показується адреса.
  final String name;
  final String host;
  final int port;
  final String? groupId;
  final List<String> tags;

  /// Порожній список = «Питати щоразу». Перший = за замовчуванням.
  final List<String> credentialIds;
  final RouteKind route;

  /// id профілю тунелю або проксі — залежно від [route].
  final String? routeRefId;
  final String? gatewayId;
  final bool gatewayBypassLocal;
  final bool adminSession;
  final bool swapMouseButtons;
  final bool reconnectOnDrop;
  final DisplaySettings display;
  final DeviceSettings devices;

  /// Відбиток сертифіката сервера, який користувач підтвердив.
  final String? certPin;
  final WakeOnLan? wakeOnLan;
  final DateTime? lastUsed;

  /// Своя картинка замість мініатюри (ім'я файлу в теці даних, див. AppFiles).
  final String? image;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName => name.trim().isEmpty ? address : name.trim();

  /// «Назва · адреса», а без назви — лише адреса (підпис на плашці вікна сеансу).
  String get nameWithAddress => name.trim().isEmpty ? address : '${name.trim()} · $address';

  /// Адреса так, як її показують і вводять: host або host:port, IPv6 у дужках.
  String get address {
    final h = host.contains(':') ? '[$host]' : host;
    return port == 3389 ? h : '$h:$port';
  }

  Connection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? Function()? groupId,
    List<String>? tags,
    List<String>? credentialIds,
    RouteKind? route,
    String? Function()? routeRefId,
    String? Function()? gatewayId,
    bool? gatewayBypassLocal,
    bool? adminSession,
    bool? swapMouseButtons,
    bool? reconnectOnDrop,
    DisplaySettings? display,
    DeviceSettings? devices,
    String? Function()? certPin,
    WakeOnLan? Function()? wakeOnLan,
    DateTime? Function()? lastUsed,
    String? Function()? image,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Connection(
        id: id ?? this.id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        groupId: groupId != null ? groupId() : this.groupId,
        tags: tags ?? this.tags,
        credentialIds: credentialIds ?? this.credentialIds,
        route: route ?? this.route,
        routeRefId: routeRefId != null ? routeRefId() : this.routeRefId,
        gatewayId: gatewayId != null ? gatewayId() : this.gatewayId,
        gatewayBypassLocal: gatewayBypassLocal ?? this.gatewayBypassLocal,
        adminSession: adminSession ?? this.adminSession,
        swapMouseButtons: swapMouseButtons ?? this.swapMouseButtons,
        reconnectOnDrop: reconnectOnDrop ?? this.reconnectOnDrop,
        display: display ?? this.display,
        devices: devices ?? this.devices,
        certPin: certPin != null ? certPin() : this.certPin,
        wakeOnLan: wakeOnLan != null ? wakeOnLan() : this.wakeOnLan,
        lastUsed: lastUsed != null ? lastUsed() : this.lastUsed,
        image: image != null ? image() : this.image,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'groupId': groupId,
        'tags': tags,
        'credentialIds': credentialIds,
        'route': route.name,
        'routeRefId': routeRefId,
        'gatewayId': gatewayId,
        'gatewayBypassLocal': gatewayBypassLocal,
        'adminSession': adminSession,
        'swapMouseButtons': swapMouseButtons,
        'reconnectOnDrop': reconnectOnDrop,
        'display': display.toJson(),
        'devices': devices.toJson(),
        'certPin': certPin,
        'wakeOnLan': wakeOnLan?.toJson(),
        'lastUsed': lastUsed?.toIso8601String(),
        'image': image,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Connection.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    // SSH-тунель прибрано (рішення власника, 2026-10-31). Такий ПК (старий бекап чи база)
    // отримує «тунель без профілю»: підключення дасть зрозумілу помилку, а не піде напряму.
    final legacySsh = j['route'] == 'ssh';
    return Connection(
      id: strOr(j['id'], ''),
      name: strOr(j['name'], ''),
      host: strOr(j['host'], ''),
      port: intOr(j['port'], 3389),
      groupId: strOrNull(j['groupId']),
      tags: stringList(j['tags']),
      credentialIds: stringList(j['credentialIds']),
      route: legacySsh ? RouteKind.tunnel : enumByName(RouteKind.values, j['route'], RouteKind.direct),
      routeRefId: legacySsh ? null : strOrNull(j['routeRefId']),
      gatewayId: strOrNull(j['gatewayId']),
      gatewayBypassLocal: boolOr(j['gatewayBypassLocal'], false),
      adminSession: boolOr(j['adminSession'], false),
      swapMouseButtons: boolOr(j['swapMouseButtons'], false),
      reconnectOnDrop: boolOr(j['reconnectOnDrop'], true),
      display: DisplaySettings.fromJson(mapOr(j['display'])),
      devices: DeviceSettings.fromJson(mapOr(j['devices'])),
      certPin: strOrNull(j['certPin']),
      wakeOnLan: j['wakeOnLan'] is Map ? WakeOnLan.fromJson(mapOr(j['wakeOnLan'])) : null,
      lastUsed: dateOrNull(j['lastUsed']),
      image: strOrNull(j['image']),
      createdAt: dateOrNull(j['createdAt']) ?? now,
      updatedAt: dateOrNull(j['updatedAt']) ?? now,
    );
  }
}
