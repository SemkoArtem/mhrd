// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Так';

  @override
  String get no => 'Ні';

  @override
  String get cancel => 'Скасувати';

  @override
  String get save => 'Зберегти';

  @override
  String get add => 'Додати';

  @override
  String get delete => 'Видалити';

  @override
  String get open => 'Відкрити';

  @override
  String get edit => 'Редагувати';

  @override
  String get export => 'Експортувати';

  @override
  String get import => 'Імпортувати';

  @override
  String get always => 'Завжди';

  @override
  String get never => 'Ніколи';

  @override
  String get disabled => 'Вимкнено.';

  @override
  String get name => 'Назва';

  @override
  String get nameOptional => 'Назва (необов\'язково)';

  @override
  String get password => 'Пароль';

  @override
  String get showPassword => 'Показати пароль';

  @override
  String get hidePassword => 'Сховати пароль';

  @override
  String get settings => 'Налаштування';

  @override
  String get groups => 'Групи';

  @override
  String get accounts => 'Облікові записи';

  @override
  String get savedPcs => 'Збережені ПК';

  @override
  String get invalidAddress => 'Некоректна адреса';

  @override
  String savedTo(String path) {
    return 'Збережено: $path';
  }

  @override
  String pcCount(int count) {
    return 'ПК: $count';
  }

  @override
  String get language => 'Мова';

  @override
  String get languageSystem => 'Як у системі';

  @override
  String get backupPasswordLabel => 'Пароль бекапу';

  @override
  String get repeatPassword => 'Повторіть пароль';

  @override
  String get backupPasswordWarning =>
      'Без цього пароля бекап не відкрити. Його неможливо відновити.';

  @override
  String get passwordTooShort => 'Щонайменше 8 символів';

  @override
  String get passwordsDontMatch => 'Паролі не збігаються';

  @override
  String get credNewTitle => 'Новий обліковий запис';

  @override
  String get credTitle => 'Обліковий запис';

  @override
  String get credUser => 'Користувач';

  @override
  String get credUserHelper => 'user, DOMAIN\\user або user@domain';

  @override
  String get credUserRequired => 'Вкажіть користувача';

  @override
  String get credSavePassword => 'Зберегти пароль';

  @override
  String get credAskEveryTime => 'Питати щоразу';

  @override
  String get credNewPassword => 'Новий пароль (порожньо = не змінювати)';

  @override
  String get credStoredNote =>
      'Пароль зберігається в системному сховищі цього пристрою.';

  @override
  String get routeDirect => 'Напряму';

  @override
  String get routeTunnelMissing => 'Тунель (не знайдено)';

  @override
  String get routeProxyMissing => 'Проксі (не знайдено)';

  @override
  String get routeSshMissing => 'SSH (не знайдено)';

  @override
  String routeGateway(String name) {
    return 'RD Gateway · $name';
  }

  @override
  String routeWithGateway(String route) {
    return '$route + шлюз';
  }

  @override
  String accountsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count акаунта',
      many: '$count акаунтів',
      few: '$count акаунти',
      one: '$count акаунт',
    );
    return '$_temp0';
  }

  @override
  String get statusNotConnected => 'Не підключено';

  @override
  String get moreActions => 'Більше дій';

  @override
  String get connect => 'Підключитись';

  @override
  String connectAs(String name) {
    return 'Підключитись як $name';
  }

  @override
  String get duplicate => 'Дублювати';

  @override
  String get exportRdp => 'Експортувати .rdp';

  @override
  String get moveToGroup => 'Перемістити в групу';

  @override
  String get wakeOnLan => 'Розбудити (Wake-on-LAN)';

  @override
  String copyOf(String name) {
    return '$name (копія)';
  }

  @override
  String get invalidAddressExamples =>
      'Некоректна адреса. Приклади: 10.0.0.5, srv.local:3390, [fd00::5]:3389';

  @override
  String connectingTo(String address) {
    return 'Підключення до $address…';
  }

  @override
  String get saveThisPc => 'Зберегти цей ПК';

  @override
  String deletePcTitle(String name) {
    return 'Видалити «$name»?';
  }

  @override
  String importedPcs(int count) {
    return 'Імпортовано ПК: $count';
  }

  @override
  String importedWithErrors(int count, String errors) {
    return 'Імпортовано: $count. Помилки: $errors';
  }

  @override
  String get rdpNoAddress => 'у файлі немає коректної адреси (full address)';

  @override
  String wakeSent(String mac) {
    return 'Сигнал пробудження надіслано на $mac. ПК зазвичай вмикається за 10–60 с.';
  }

  @override
  String wakeFailed(String error) {
    return 'Не вдалося надіслати сигнал: $error';
  }

  @override
  String invalidMac(String value) {
    return 'Некоректна MAC-адреса: $value';
  }

  @override
  String invalidBroadcast(String value) {
    return 'Некоректна широкомовна адреса: $value';
  }

  @override
  String get engineMissing =>
      'Не знайдено модуль підключення mhrd-session. Перевстановіть MHRD.';

  @override
  String sessionConnecting(String name) {
    return 'З\'єднання з $name…';
  }

  @override
  String get sessionNegotiating => 'Перевірка сертифіката…';

  @override
  String get disconnectAction => 'Відключитись';

  @override
  String get fullscreen => 'На весь екран (Ctrl+Alt+Enter)';

  @override
  String get exitFullscreen => 'Вийти з повного екрана (Ctrl+Alt+Enter)';

  @override
  String get pinBar => 'Закріпити панель';

  @override
  String get unpinBar => 'Відкріпити панель';

  @override
  String get barPin => 'Закріпити';

  @override
  String get barUnpin => 'Відкріпити';

  @override
  String get barMinimize => 'Згорнути';

  @override
  String get barWindowed => 'У вікно';

  @override
  String get barFullscreen => 'На весь екран';

  @override
  String get barKeyboard => 'Клавіатура';

  @override
  String get onScreenKeyboard => 'Екранна клавіатура';

  @override
  String get close => 'Закрити';

  @override
  String get retry => 'Підключитись знову';

  @override
  String sessionDetails(String details, String code) {
    return 'Деталі: $details (код $code)';
  }

  @override
  String get reasonUserRequest => 'Відключено.';

  @override
  String get reasonNetwork =>
      'ПК недоступний. Перевірте адресу, мережу і чи ввімкнено на ПК віддалений робочий стіл.';

  @override
  String get reasonAuthFailed => 'Невірний логін або пароль.';

  @override
  String get reasonNoCredentials => 'Для входу потрібні логін і пароль.';

  @override
  String get reasonAccountLocked =>
      'Обліковий запис заблоковано, вимкнено або йому заборонено вхід.';

  @override
  String get reasonPasswordExpired =>
      'Термін дії пароля минув. Змініть пароль на ПК або в домені.';

  @override
  String get reasonCertRejected =>
      'Підключення скасовано: сертифікату ПК не довірили.';

  @override
  String get reasonTls => 'Не вдалося встановити захищене з\'єднання (TLS).';

  @override
  String get reasonServerLogoff => 'Сеанс завершено на віддаленому ПК.';

  @override
  String get reasonOtherConnection =>
      'Сеанс перехопило інше підключення до цього ПК.';

  @override
  String get reasonServerDenied => 'ПК відхилив підключення.';

  @override
  String get reasonOther => 'З\'єднання розірвано.';

  @override
  String get reasonCrashed =>
      'Модуль сеансу несподівано завершився. MHRD працює далі — спробуйте підключитись знову.';

  @override
  String get certTitle => 'Довіряти сертифікату ПК?';

  @override
  String get certChangedTitle => 'Сертифікат ПК змінився!';

  @override
  String certIntro(String host) {
    return 'Перевірте, що підключаєтесь саме до $host. Якщо відбиток збігається з тим, що повідомив адміністратор ПК, — довіряйте.';
  }

  @override
  String get certChangedWarning =>
      'Раніше цей ПК мав інший сертифікат. Так буває після перевстановлення системи, але це може бути й атака. Не довіряйте, якщо не впевнені.';

  @override
  String get certSubject => 'Кому видано';

  @override
  String get certIssuer => 'Ким видано';

  @override
  String get certFingerprint => 'Відбиток';

  @override
  String get certReject => 'Не довіряти';

  @override
  String get certAccept => 'Довіряти й підключитись';

  @override
  String get certRemember => 'Запам\'ятати для цього ПК і більше не питати';

  @override
  String credPromptTitle(String name) {
    return 'Вхід на $name';
  }

  @override
  String get credPromptHint =>
      'Дані використовуються лише для цього підключення.';

  @override
  String get allPcs => 'Усі ПК';

  @override
  String get recent => 'Нещодавні';

  @override
  String get quickConnectHint => 'Швидке підключення: адреса ПК';

  @override
  String get addPc => 'Додати ПК';

  @override
  String get importRdpFiles => 'Імпортувати .rdp-файли';

  @override
  String get computers => 'Комп\'ютери';

  @override
  String get activeTunnels => 'Активні тунелі';

  @override
  String get noTunnelsYet => 'Немає. Тунелі запрацюють на етапі 4.';

  @override
  String get searchHint => 'Назва, адреса, тег';

  @override
  String get viewTiles => 'Плитки';

  @override
  String get viewList => 'Список';

  @override
  String get nothingFound => 'Нічого не знайдено';

  @override
  String get nothingFoundHint => 'Спробуйте іншу назву, адресу або тег.';

  @override
  String get emptyTitle => 'Тут поки порожньо';

  @override
  String get emptyHint =>
      'Додайте перший ПК, імпортуйте .rdp-файли або відновіть бекап у налаштуваннях.';

  @override
  String get editPcTitle => 'Редагувати ПК';

  @override
  String get addressRequired =>
      'Вкажіть адресу: 10.0.0.5, srv.local:3390 або [fd00::5]:3389';

  @override
  String get macFormat => 'MAC-адреса має вигляд AA:BB:CC:DD:EE:FF';

  @override
  String get broadcastFormat =>
      'Широкомовна адреса — це IPv4, наприклад 192.168.1.255';

  @override
  String get tabGeneral => 'Загальні';

  @override
  String get tabDisplay => 'Екран';

  @override
  String get tabDevices => 'Пристрої';

  @override
  String get tabAdvanced => 'Додатково';

  @override
  String get tabTheme => 'Тема';

  @override
  String get tabRoutes => 'Маршрути';

  @override
  String get tabBackup => 'Бекап';

  @override
  String get pcAddress => 'Адреса ПК';

  @override
  String get pcAddressHint => 'Ім\'я, IP або ім\'я:порт';

  @override
  String get nameHelper => 'Якщо порожньо — показується адреса';

  @override
  String get group => 'Група';

  @override
  String get noAccountsHint => 'Питати логін і пароль при кожному підключенні.';

  @override
  String get defaultAccount => 'За замовчуванням';

  @override
  String get availableInConnectAs => 'Доступний у «Підключитись як…»';

  @override
  String get removeFromPc => 'Прибрати з цього ПК';

  @override
  String get addSavedAccount => 'Додати збережений';

  @override
  String get route => 'Маршрут';

  @override
  String get routeHow => 'Як підключатися';

  @override
  String get routeViaTunnel => 'Через вбудований тунель (WireGuard, OpenVPN…)';

  @override
  String get routeViaProxy => 'Через проксі';

  @override
  String get routeViaSsh => 'Через SSH-тунель';

  @override
  String get noRouteProfiles =>
      'Ще немає жодного профілю. Додайте його в Налаштування → Маршрути.';

  @override
  String get profile => 'Профіль';

  @override
  String get noGateway => 'Без шлюзу';

  @override
  String get bypassGatewayLocal => 'Обходити шлюз для локальних адрес';

  @override
  String get sectionConnection => 'Підключення';

  @override
  String get reconnectOnDrop => 'Перепідключатися при обриві';

  @override
  String get adminSession => 'Адміністративний сеанс';

  @override
  String get adminSessionHint => 'Підключення до консольного сеансу сервера';

  @override
  String get swapMouse => 'Поміняти кнопки миші місцями';

  @override
  String get useAllMonitors => 'Використовувати всі монітори';

  @override
  String get startFullscreen => 'Запуск на весь екран';

  @override
  String get asInGeneralSettings => 'Як у загальних налаштуваннях';

  @override
  String get onWindowResize => 'Коли змінюється розмір вікна';

  @override
  String get resizeChangeResolution => 'Змінювати роздільність';

  @override
  String get resizeScale => 'Масштабувати';

  @override
  String get resizeNone => 'Без змін';

  @override
  String get colorDepth => 'Глибина кольору';

  @override
  String get color32 => 'Найвища (32 біти)';

  @override
  String get color24 => 'Висока (24 біти)';

  @override
  String get color16 => 'Середня (16 біт) — менше трафіку';

  @override
  String get color15 => 'Низька (15 біт)';

  @override
  String get remoteScale => 'Масштаб елементів на віддаленому ПК';

  @override
  String get hiDpi => 'Повна чіткість на Retina / HiDPI';

  @override
  String get hiDpiWarning => 'Приблизно вчетверо більше трафіку';

  @override
  String get clipboard => 'Буфер обміну';

  @override
  String get clipboardHint => 'Текст і зображення в обидва боки';

  @override
  String get microphone => 'Мікрофон';

  @override
  String get sound => 'Звук';

  @override
  String get soundLocal => 'На цьому пристрої';

  @override
  String get soundRemote => 'На віддаленому ПК';

  @override
  String get soundOff => 'Не відтворювати';

  @override
  String get folders => 'Папки';

  @override
  String get noFolders => 'Жодна папка не доступна віддаленому ПК.';

  @override
  String get readOnly => 'Лише читання';

  @override
  String get foldersHint =>
      'Кожна папка з\'явиться на віддаленому ПК як диск у «Цей ПК». «Додавати без видалення»: можна читати все й класти нове, але не видаляти, не перейменовувати й не змінювати те, що вже є.';

  @override
  String get folderAddOnly => 'Додавати без видалення';

  @override
  String get folderFull => 'Повний доступ';

  @override
  String get removeFolder => 'Прибрати папку';

  @override
  String get addFolder => 'Додати папку';

  @override
  String get tags => 'Теги';

  @override
  String get tagsHelper => 'Через кому: офіс, 1с, бухгалтерія';

  @override
  String get wolMac => 'MAC-адреса для Wake-on-LAN';

  @override
  String get wolMacHelper => 'Щоб будити ПК із меню «Розбудити»';

  @override
  String get wolBroadcast =>
      'Широкомовна адреса для Wake-on-LAN (необов\'язково)';

  @override
  String get wolBroadcastHelper =>
      'Якщо ПК в іншій підмережі — її broadcast, наприклад 192.168.1.255';

  @override
  String get serverCertificate => 'Сертифікат сервера';

  @override
  String trustedFingerprint(String fingerprint) {
    return 'Довірений відбиток: $fingerprint';
  }

  @override
  String get forgetCertificate =>
      'Забути сертифікат (спитати знову при підключенні)';

  @override
  String inUseTitle(String what) {
    return '$what використовується';
  }

  @override
  String inUseBody(String users) {
    return 'Його використовують: $users.\nПрибрати його звідти й видалити?';
  }

  @override
  String get inUseCredential => 'Обліковий запис';

  @override
  String get inUseGateway => 'Шлюз';

  @override
  String get inUseTunnel => 'Тунель';

  @override
  String get inUseProxy => 'Проксі';

  @override
  String get inUseSsh => 'SSH-профіль';

  @override
  String gatewayUser(String name) {
    return 'шлюз $name';
  }

  @override
  String get startSessionsFullscreen => 'Запускати сеанси на весь екран';

  @override
  String get sessionPerWindow => 'Кожен сеанс в окремому вікні';

  @override
  String get sessionPerWindowHint => 'Інакше — вкладки в головному вікні';

  @override
  String get keepScreenAwake => 'Не вимикати екран під час сеансу';

  @override
  String get showPreviews => 'Мініатюри ПК у списку';

  @override
  String get keyboardCapture =>
      'Клавіші Win, Alt+Tab тощо надсилати на віддалений ПК';

  @override
  String get captureFullscreenOnly => 'Лише на весь екран';

  @override
  String get accountsHint =>
      'Один обліковий запис можна призначити багатьом ПК. Зміна пароля діє одразу для всіх.';

  @override
  String get askPassword => 'Питати пароль';

  @override
  String get passwordSaved => 'Пароль збережено';

  @override
  String get addAccount => 'Додати обліковий запис';

  @override
  String get gatewayNew => 'Новий шлюз';

  @override
  String get gatewayTitle => 'Шлюз';

  @override
  String get gatewayAddress => 'Адреса шлюзу';

  @override
  String get gatewayAccount => 'Обліковий запис для шлюзу';

  @override
  String get gatewaySameAsPc => 'Той самий, що й для ПК';

  @override
  String get addGateway => 'Додати шлюз';

  @override
  String wgImported(String name) {
    return 'Тунель «$name» імпортовано. Ключі збережено в системному сховищі.';
  }

  @override
  String get wgImportedExtraPeers =>
      'Імпортовано. У файлі кілька [Peer] — поки використовується перший.';

  @override
  String get wgNoPrivateKey => 'У файлі немає PrivateKey у секції [Interface].';

  @override
  String get wgNoPeer => 'У файлі немає секції [Peer] з PublicKey і Endpoint.';

  @override
  String get builtInTunnels => 'Вбудовані тунелі';

  @override
  String get tunnelsHint =>
      'Тунель працює всередині MHRD: без прав адміністратора і не заважає іншому VPN. Підключення через тунелі запрацює на етапі 4.';

  @override
  String get importWireGuard => 'Імпортувати WireGuard .conf';

  @override
  String get proxyAndSsh => 'Проксі й SSH';

  @override
  String get comingInStage6 => 'З\'являться на етапі 6.';

  @override
  String get groupNew => 'Нова група';

  @override
  String get groupRename => 'Перейменувати групу';

  @override
  String groupNestInto(String name) {
    return 'Вкласти «$name» у…';
  }

  @override
  String get topLevel => 'Верхній рівень';

  @override
  String groupMoveContentsTo(String name) {
    return 'Куди перенести вміст групи «$name»?';
  }

  @override
  String groupDeleteTitle(String name) {
    return 'Видалити групу «$name»?';
  }

  @override
  String defaultGroupInfo(int count) {
    return 'Стандартна група · ПК: $count';
  }

  @override
  String get nestIntoOther => 'Вкласти в іншу групу';

  @override
  String get groupCycle => 'Група не може бути вкладена сама в себе.';

  @override
  String get backupPasswordTitle => 'Пароль для бекапу';

  @override
  String get encryptingBackup => 'Шифрую бекап…';

  @override
  String backupSaved(String path) {
    return 'Бекап збережено: $path';
  }

  @override
  String get decrypting => 'Розшифровую…';

  @override
  String get restoreHow => 'Як відновити?';

  @override
  String get restoreMerge => 'Об\'єднати з поточними даними';

  @override
  String get restoreReplace =>
      'Замінити все (поточні дані спершу збережуться в страхувальну копію)';

  @override
  String get restoreConfirmTitle => 'Відновити бекап?';

  @override
  String restorePreview(int added, int updated, int removed) {
    return 'Буде додано ПК: $added, оновлено: $updated, видалено: $removed.';
  }

  @override
  String get restore => 'Відновити';

  @override
  String get restored => 'Бекап відновлено.';

  @override
  String savedWithoutPasswords(String path) {
    return 'Збережено без паролів: $path';
  }

  @override
  String get shareImported =>
      'Імпортовано. Паролі введіть при першому підключенні.';

  @override
  String get fullBackup => 'Повний бекап';

  @override
  String get fullBackupHint =>
      'Усі ПК, облікові записи з паролями, шлюзи, тунелі з ключами, групи, теми й налаштування. Файл шифрується вашим паролем (Argon2id + AES-256-GCM) і відкривається на будь-якій ОС.';

  @override
  String get backupNever => 'Бекап ще не робили.';

  @override
  String backupLast(String date) {
    return 'Останній бекап: $date';
  }

  @override
  String get saveBackup => 'Зберегти бекап';

  @override
  String get restoreFromBackup => 'Відновити з бекапу';

  @override
  String get sharePcList => 'Поділитися списком ПК';

  @override
  String get sharePcListHint =>
      'Файл без жодного пароля чи ключа — щоб передати список колезі.';

  @override
  String get backupNotMhrdFile => 'Це не файл бекапу MHRD.';

  @override
  String get backupCorrupted => 'Файл бекапу пошкоджено.';

  @override
  String get backupWrongPassword => 'Невірний пароль або файл пошкоджено.';

  @override
  String get backupFromNewer =>
      'Бекап створено новішою версією MHRD. Оновіть застосунок.';

  @override
  String get notShareFile => 'Це не файл експорту MHRD.';

  @override
  String get autoBackup => 'Автобекап';

  @override
  String get autoBackupHint =>
      'Після змін, не частіше разу на годину — у вибрану теку, наприклад синхронізовану з хмарою. Зберігаються останні 10 копій. Пароль автобекапу лежить у системному сховищі цього пристрою.';

  @override
  String get autoBackupPasswordTitle => 'Пароль автобекапу';

  @override
  String get autoBackupFirstCopy => 'Роблю першу копію…';

  @override
  String autoBackupEnabled(String path) {
    return 'Автобекап увімкнено. Перша копія: $path';
  }

  @override
  String get autoBackupMaking => 'Роблю копію…';

  @override
  String autoBackupSaved(String path) {
    return 'Копію збережено: $path';
  }

  @override
  String get autoBackupBusy => 'Копія вже робиться.';

  @override
  String get autoBackupNone => 'Копій ще не було.';

  @override
  String autoBackupLast(String date) {
    return 'Остання копія: $date';
  }

  @override
  String get enableEllipsis => 'Увімкнути…';

  @override
  String get autoBackupNow => 'Зробити копію зараз';

  @override
  String get autoBackupChange => 'Змінити теку й пароль';

  @override
  String get disable => 'Вимкнути';

  @override
  String autoBackupWriteFailed(String path, String reason) {
    return 'Не вдалося записати копію в $path: $reason';
  }

  @override
  String get autoBackupNoPassword =>
      'Пароль автобекапу не знайдено в системному сховищі. Увімкніть автобекап заново.';

  @override
  String autoBackupFailed(String error) {
    return 'Автобекап не вдався: $error';
  }

  @override
  String get themeGraphite => 'Графіт';

  @override
  String get themeLight => 'Світлий інструмент';

  @override
  String get themeAmber => 'Нічний бурштин';

  @override
  String themeMine(String name) {
    return '$name (моя)';
  }

  @override
  String get contrastWarnTitle => 'Текст може бути погано видно';

  @override
  String contrastWarnBody(String problems) {
    return '$problems\n\nЗберегти все одно?';
  }

  @override
  String themeSaved(String path) {
    return 'Тему збережено: $path';
  }

  @override
  String get notThemeFile => 'Це не файл теми MHRD.';

  @override
  String themeAdded(String name) {
    return 'Тему «$name» додано.';
  }

  @override
  String get createTheme => 'Створити свою тему';

  @override
  String get importTheme => 'Імпортувати тему';

  @override
  String get exportCurrentTheme => 'Експортувати поточну';

  @override
  String get editCurrentTheme => 'Редагувати поточну';

  @override
  String get deleteCurrentTheme => 'Видалити поточну';

  @override
  String get themeNameLabel => 'Назва теми';

  @override
  String get themeDark => 'Темна';

  @override
  String get themeLightMode => 'Світла';

  @override
  String get colorBackground => 'Фон';

  @override
  String get colorSurface => 'Панелі';

  @override
  String get colorSurfaceRaised => 'Поля й чипи';

  @override
  String get colorBorder => 'Рамки';

  @override
  String get colorText => 'Текст';

  @override
  String get colorTextMuted => 'Другорядний текст';

  @override
  String get colorAccent => 'Акцент';

  @override
  String get colorOnAccent => 'Текст на акценті';

  @override
  String get statusConnected => 'Підключено';

  @override
  String get statusReconnecting => 'Перепідключення';

  @override
  String get statusError => 'Помилка';

  @override
  String get radius => 'Заокруглення';

  @override
  String get textSize => 'Розмір тексту';

  @override
  String get densityCompact => 'Компактно';

  @override
  String get densityNormal => 'Звичайно';

  @override
  String get densitySpacious => 'Просторо';

  @override
  String get motionFull => 'Анімації';

  @override
  String get motionEssential => 'Мінімум';

  @override
  String get motionOff => 'Вимкнено';

  @override
  String contrastBad(String problems) {
    return 'Погано читається:\n$problems';
  }

  @override
  String get contrastFine => 'Контраст тексту в нормі.';

  @override
  String get saveAndApply => 'Зберегти й застосувати';

  @override
  String get previewPcName => 'Офіс — Бухгалтерія';

  @override
  String get contrastTextOnBackground => 'Текст на фоні';

  @override
  String get contrastTextOnSurface => 'Текст на панелі';

  @override
  String get contrastMutedOnSurface => 'Другорядний текст на панелі';

  @override
  String get contrastOnAccent => 'Текст на кнопці акценту';

  @override
  String get contrastStatusConnected => 'Статус «підключено»';

  @override
  String get contrastStatusError => 'Статус «помилка»';

  @override
  String contrastIssue(String label, String ratio) {
    return '$label: $ratio : 1 (треба 4.5)';
  }

  @override
  String get fileTypeBackup => 'Бекап MHRD';

  @override
  String get fileTypeShare => 'Експорт MHRD';

  @override
  String get fileTypeRdp => 'Файли RDP';

  @override
  String get fileTypeWireGuard => 'Конфігурація WireGuard';

  @override
  String get fileTypeTheme => 'Тема MHRD';
}
