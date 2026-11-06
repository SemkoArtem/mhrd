import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk')
  ];

  /// No description provided for @ok.
  ///
  /// In uk, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @yes.
  ///
  /// In uk, this message translates to:
  /// **'Так'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In uk, this message translates to:
  /// **'Ні'**
  String get no;

  /// No description provided for @cancel.
  ///
  /// In uk, this message translates to:
  /// **'Скасувати'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти'**
  String get save;

  /// No description provided for @add.
  ///
  /// In uk, this message translates to:
  /// **'Додати'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In uk, this message translates to:
  /// **'Видалити'**
  String get delete;

  /// No description provided for @open.
  ///
  /// In uk, this message translates to:
  /// **'Відкрити'**
  String get open;

  /// No description provided for @edit.
  ///
  /// In uk, this message translates to:
  /// **'Редагувати'**
  String get edit;

  /// No description provided for @export.
  ///
  /// In uk, this message translates to:
  /// **'Експортувати'**
  String get export;

  /// No description provided for @import.
  ///
  /// In uk, this message translates to:
  /// **'Імпортувати'**
  String get import;

  /// No description provided for @always.
  ///
  /// In uk, this message translates to:
  /// **'Завжди'**
  String get always;

  /// No description provided for @never.
  ///
  /// In uk, this message translates to:
  /// **'Ніколи'**
  String get never;

  /// No description provided for @disabled.
  ///
  /// In uk, this message translates to:
  /// **'Вимкнено.'**
  String get disabled;

  /// No description provided for @name.
  ///
  /// In uk, this message translates to:
  /// **'Назва'**
  String get name;

  /// No description provided for @nameOptional.
  ///
  /// In uk, this message translates to:
  /// **'Назва (необов\'язково)'**
  String get nameOptional;

  /// No description provided for @password.
  ///
  /// In uk, this message translates to:
  /// **'Пароль'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In uk, this message translates to:
  /// **'Показати пароль'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In uk, this message translates to:
  /// **'Сховати пароль'**
  String get hidePassword;

  /// No description provided for @settings.
  ///
  /// In uk, this message translates to:
  /// **'Налаштування'**
  String get settings;

  /// No description provided for @groups.
  ///
  /// In uk, this message translates to:
  /// **'Групи'**
  String get groups;

  /// No description provided for @accounts.
  ///
  /// In uk, this message translates to:
  /// **'Облікові записи'**
  String get accounts;

  /// No description provided for @savedPcs.
  ///
  /// In uk, this message translates to:
  /// **'Без групи'**
  String get savedPcs;

  /// No description provided for @invalidAddress.
  ///
  /// In uk, this message translates to:
  /// **'Некоректна адреса'**
  String get invalidAddress;

  /// No description provided for @savedTo.
  ///
  /// In uk, this message translates to:
  /// **'Збережено: {path}'**
  String savedTo(String path);

  /// No description provided for @pcCount.
  ///
  /// In uk, this message translates to:
  /// **'ПК: {count}'**
  String pcCount(int count);

  /// No description provided for @language.
  ///
  /// In uk, this message translates to:
  /// **'Мова'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In uk, this message translates to:
  /// **'Як у системі'**
  String get languageSystem;

  /// No description provided for @backupPasswordLabel.
  ///
  /// In uk, this message translates to:
  /// **'Пароль бекапу'**
  String get backupPasswordLabel;

  /// No description provided for @repeatPassword.
  ///
  /// In uk, this message translates to:
  /// **'Повторіть пароль'**
  String get repeatPassword;

  /// No description provided for @backupPasswordWarning.
  ///
  /// In uk, this message translates to:
  /// **'Без цього пароля бекап не відкрити. Його неможливо відновити.'**
  String get backupPasswordWarning;

  /// No description provided for @passwordTooShort.
  ///
  /// In uk, this message translates to:
  /// **'Щонайменше 8 символів'**
  String get passwordTooShort;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In uk, this message translates to:
  /// **'Паролі не збігаються'**
  String get passwordsDontMatch;

  /// No description provided for @credNewTitle.
  ///
  /// In uk, this message translates to:
  /// **'Новий обліковий запис'**
  String get credNewTitle;

  /// No description provided for @credTitle.
  ///
  /// In uk, this message translates to:
  /// **'Обліковий запис'**
  String get credTitle;

  /// No description provided for @credUser.
  ///
  /// In uk, this message translates to:
  /// **'Користувач'**
  String get credUser;

  /// No description provided for @credUserHelper.
  ///
  /// In uk, this message translates to:
  /// **'user, DOMAIN\\user або user@domain'**
  String get credUserHelper;

  /// No description provided for @credUserRequired.
  ///
  /// In uk, this message translates to:
  /// **'Вкажіть користувача'**
  String get credUserRequired;

  /// No description provided for @credSavePassword.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти пароль'**
  String get credSavePassword;

  /// No description provided for @credAskEveryTime.
  ///
  /// In uk, this message translates to:
  /// **'Питати щоразу'**
  String get credAskEveryTime;

  /// No description provided for @credNewPassword.
  ///
  /// In uk, this message translates to:
  /// **'Новий пароль (порожньо = не змінювати)'**
  String get credNewPassword;

  /// No description provided for @credStoredNote.
  ///
  /// In uk, this message translates to:
  /// **'Пароль зберігається в системному сховищі цього пристрою.'**
  String get credStoredNote;

  /// No description provided for @routeDirect.
  ///
  /// In uk, this message translates to:
  /// **'Напряму'**
  String get routeDirect;

  /// No description provided for @routeTunnelMissing.
  ///
  /// In uk, this message translates to:
  /// **'Тунель (не знайдено)'**
  String get routeTunnelMissing;

  /// No description provided for @routeProxyMissing.
  ///
  /// In uk, this message translates to:
  /// **'Проксі (не знайдено)'**
  String get routeProxyMissing;

  /// No description provided for @routeGateway.
  ///
  /// In uk, this message translates to:
  /// **'RD Gateway · {name}'**
  String routeGateway(String name);

  /// No description provided for @routeWithGateway.
  ///
  /// In uk, this message translates to:
  /// **'{route} + шлюз'**
  String routeWithGateway(String route);

  /// No description provided for @accountsCount.
  ///
  /// In uk, this message translates to:
  /// **'{count, plural, one{{count} акаунт} few{{count} акаунти} many{{count} акаунтів} other{{count} акаунта}}'**
  String accountsCount(int count);

  /// No description provided for @statusNotConnected.
  ///
  /// In uk, this message translates to:
  /// **'Не підключено'**
  String get statusNotConnected;

  /// No description provided for @moreActions.
  ///
  /// In uk, this message translates to:
  /// **'Більше дій'**
  String get moreActions;

  /// No description provided for @connect.
  ///
  /// In uk, this message translates to:
  /// **'Підключитись'**
  String get connect;

  /// No description provided for @connectAs.
  ///
  /// In uk, this message translates to:
  /// **'Підключитись як {name}'**
  String connectAs(String name);

  /// No description provided for @duplicate.
  ///
  /// In uk, this message translates to:
  /// **'Дублювати'**
  String get duplicate;

  /// No description provided for @exportRdp.
  ///
  /// In uk, this message translates to:
  /// **'Експортувати .rdp'**
  String get exportRdp;

  /// No description provided for @moveToGroup.
  ///
  /// In uk, this message translates to:
  /// **'Перемістити в групу'**
  String get moveToGroup;

  /// No description provided for @wakeOnLan.
  ///
  /// In uk, this message translates to:
  /// **'Розбудити (Wake-on-LAN)'**
  String get wakeOnLan;

  /// No description provided for @copyOf.
  ///
  /// In uk, this message translates to:
  /// **'{name} (копія)'**
  String copyOf(String name);

  /// No description provided for @invalidAddressExamples.
  ///
  /// In uk, this message translates to:
  /// **'Некоректна адреса. Приклади: 10.0.0.5, srv.local:3390, [fd00::5]:3389'**
  String get invalidAddressExamples;

  /// No description provided for @connectingTo.
  ///
  /// In uk, this message translates to:
  /// **'Підключення до {address}…'**
  String connectingTo(String address);

  /// No description provided for @saveThisPc.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти цей ПК'**
  String get saveThisPc;

  /// No description provided for @deletePcTitle.
  ///
  /// In uk, this message translates to:
  /// **'Видалити «{name}»?'**
  String deletePcTitle(String name);

  /// No description provided for @importedPcs.
  ///
  /// In uk, this message translates to:
  /// **'Імпортовано ПК: {count}'**
  String importedPcs(int count);

  /// No description provided for @importedWithErrors.
  ///
  /// In uk, this message translates to:
  /// **'Імпортовано: {count}. Помилки: {errors}'**
  String importedWithErrors(int count, String errors);

  /// No description provided for @rdpNoAddress.
  ///
  /// In uk, this message translates to:
  /// **'у файлі немає коректної адреси (full address)'**
  String get rdpNoAddress;

  /// No description provided for @wakeSent.
  ///
  /// In uk, this message translates to:
  /// **'Сигнал пробудження надіслано на {mac}. ПК зазвичай вмикається за 10–60 с.'**
  String wakeSent(String mac);

  /// No description provided for @wakeFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося надіслати сигнал: {error}'**
  String wakeFailed(String error);

  /// No description provided for @invalidMac.
  ///
  /// In uk, this message translates to:
  /// **'Некоректна MAC-адреса: {value}'**
  String invalidMac(String value);

  /// No description provided for @invalidBroadcast.
  ///
  /// In uk, this message translates to:
  /// **'Некоректна широкомовна адреса: {value}'**
  String invalidBroadcast(String value);

  /// No description provided for @engineMissing.
  ///
  /// In uk, this message translates to:
  /// **'Не знайдено модуль підключення mhrd-session. Перевстановіть MHRD.'**
  String get engineMissing;

  /// No description provided for @sessionConnecting.
  ///
  /// In uk, this message translates to:
  /// **'З\'єднання з {name}…'**
  String sessionConnecting(String name);

  /// No description provided for @sessionNegotiating.
  ///
  /// In uk, this message translates to:
  /// **'Перевірка сертифіката…'**
  String get sessionNegotiating;

  /// No description provided for @disconnectAction.
  ///
  /// In uk, this message translates to:
  /// **'Відключитись'**
  String get disconnectAction;

  /// No description provided for @fullscreen.
  ///
  /// In uk, this message translates to:
  /// **'На весь екран (Ctrl+Alt+Enter)'**
  String get fullscreen;

  /// No description provided for @exitFullscreen.
  ///
  /// In uk, this message translates to:
  /// **'Вийти з повного екрана (Ctrl+Alt+Enter)'**
  String get exitFullscreen;

  /// No description provided for @pinBar.
  ///
  /// In uk, this message translates to:
  /// **'Закріпити панель'**
  String get pinBar;

  /// No description provided for @unpinBar.
  ///
  /// In uk, this message translates to:
  /// **'Відкріпити панель'**
  String get unpinBar;

  /// No description provided for @barMinimize.
  ///
  /// In uk, this message translates to:
  /// **'Згорнути'**
  String get barMinimize;

  /// No description provided for @onScreenKeyboard.
  ///
  /// In uk, this message translates to:
  /// **'Екранна клавіатура'**
  String get onScreenKeyboard;

  /// No description provided for @close.
  ///
  /// In uk, this message translates to:
  /// **'Закрити'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In uk, this message translates to:
  /// **'Підключитись знову'**
  String get retry;

  /// No description provided for @sessionDetails.
  ///
  /// In uk, this message translates to:
  /// **'Деталі: {details} (код {code})'**
  String sessionDetails(String details, String code);

  /// No description provided for @reasonUserRequest.
  ///
  /// In uk, this message translates to:
  /// **'Відключено.'**
  String get reasonUserRequest;

  /// No description provided for @reasonNetwork.
  ///
  /// In uk, this message translates to:
  /// **'ПК недоступний. Перевірте адресу, мережу і чи ввімкнено на ПК віддалений робочий стіл.'**
  String get reasonNetwork;

  /// No description provided for @reasonAuthFailed.
  ///
  /// In uk, this message translates to:
  /// **'Невірний логін або пароль.'**
  String get reasonAuthFailed;

  /// No description provided for @reasonNoCredentials.
  ///
  /// In uk, this message translates to:
  /// **'Для входу потрібні логін і пароль.'**
  String get reasonNoCredentials;

  /// No description provided for @reasonAccountLocked.
  ///
  /// In uk, this message translates to:
  /// **'Обліковий запис заблоковано, вимкнено або йому заборонено вхід.'**
  String get reasonAccountLocked;

  /// No description provided for @reasonPasswordExpired.
  ///
  /// In uk, this message translates to:
  /// **'Термін дії пароля минув. Змініть пароль на ПК або в домені.'**
  String get reasonPasswordExpired;

  /// No description provided for @reasonCertRejected.
  ///
  /// In uk, this message translates to:
  /// **'Підключення скасовано: сертифікату ПК не довірили.'**
  String get reasonCertRejected;

  /// No description provided for @reasonTls.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося встановити захищене з\'єднання (TLS).'**
  String get reasonTls;

  /// No description provided for @reasonServerLogoff.
  ///
  /// In uk, this message translates to:
  /// **'Сеанс завершено на віддаленому ПК.'**
  String get reasonServerLogoff;

  /// No description provided for @reasonOtherConnection.
  ///
  /// In uk, this message translates to:
  /// **'Сеанс перехопило інше підключення до цього ПК.'**
  String get reasonOtherConnection;

  /// No description provided for @reasonServerDenied.
  ///
  /// In uk, this message translates to:
  /// **'ПК відхилив підключення.'**
  String get reasonServerDenied;

  /// No description provided for @reasonOther.
  ///
  /// In uk, this message translates to:
  /// **'З\'єднання розірвано.'**
  String get reasonOther;

  /// No description provided for @reasonCrashed.
  ///
  /// In uk, this message translates to:
  /// **'Модуль сеансу несподівано завершився. MHRD працює далі — спробуйте підключитись знову.'**
  String get reasonCrashed;

  /// No description provided for @certTitle.
  ///
  /// In uk, this message translates to:
  /// **'Довіряти сертифікату ПК?'**
  String get certTitle;

  /// No description provided for @certChangedTitle.
  ///
  /// In uk, this message translates to:
  /// **'Сертифікат ПК змінився!'**
  String get certChangedTitle;

  /// No description provided for @certIntro.
  ///
  /// In uk, this message translates to:
  /// **'Перевірте, що підключаєтесь саме до {host}. Якщо відбиток збігається з тим, що повідомив адміністратор ПК, — довіряйте.'**
  String certIntro(String host);

  /// No description provided for @certChangedWarning.
  ///
  /// In uk, this message translates to:
  /// **'Раніше цей ПК мав інший сертифікат. Так буває після перевстановлення системи, але це може бути й атака. Не довіряйте, якщо не впевнені.'**
  String get certChangedWarning;

  /// No description provided for @certSubject.
  ///
  /// In uk, this message translates to:
  /// **'Кому видано'**
  String get certSubject;

  /// No description provided for @certIssuer.
  ///
  /// In uk, this message translates to:
  /// **'Ким видано'**
  String get certIssuer;

  /// No description provided for @certFingerprint.
  ///
  /// In uk, this message translates to:
  /// **'Відбиток'**
  String get certFingerprint;

  /// No description provided for @certReject.
  ///
  /// In uk, this message translates to:
  /// **'Не довіряти'**
  String get certReject;

  /// No description provided for @certAccept.
  ///
  /// In uk, this message translates to:
  /// **'Довіряти й підключитись'**
  String get certAccept;

  /// No description provided for @certRemember.
  ///
  /// In uk, this message translates to:
  /// **'Запам\'ятати для цього ПК і більше не питати'**
  String get certRemember;

  /// No description provided for @credPromptTitle.
  ///
  /// In uk, this message translates to:
  /// **'Вхід на {name}'**
  String credPromptTitle(String name);

  /// No description provided for @credPromptHint.
  ///
  /// In uk, this message translates to:
  /// **'Дані використовуються лише для цього підключення.'**
  String get credPromptHint;

  /// No description provided for @allPcs.
  ///
  /// In uk, this message translates to:
  /// **'Усі ПК'**
  String get allPcs;

  /// No description provided for @recent.
  ///
  /// In uk, this message translates to:
  /// **'Нещодавні'**
  String get recent;

  /// No description provided for @quickConnectHint.
  ///
  /// In uk, this message translates to:
  /// **'Швидке підключення: адреса ПК'**
  String get quickConnectHint;

  /// No description provided for @addPc.
  ///
  /// In uk, this message translates to:
  /// **'Додати ПК'**
  String get addPc;

  /// No description provided for @importRdpFiles.
  ///
  /// In uk, this message translates to:
  /// **'Імпортувати .rdp-файли'**
  String get importRdpFiles;

  /// No description provided for @computers.
  ///
  /// In uk, this message translates to:
  /// **'Комп\'ютери'**
  String get computers;

  /// No description provided for @sidebarToggle.
  ///
  /// In uk, this message translates to:
  /// **'Бічна панель: закріпити або сховати'**
  String get sidebarToggle;

  /// No description provided for @activeTunnels.
  ///
  /// In uk, this message translates to:
  /// **'Тунелі й проксі'**
  String get activeTunnels;

  /// No description provided for @noTunnelsYet.
  ///
  /// In uk, this message translates to:
  /// **'Ще немає. Додайте в Налаштуваннях → Маршрути.'**
  String get noTunnelsYet;

  /// No description provided for @healthOk.
  ///
  /// In uk, this message translates to:
  /// **'Працює · відповідь за {ms} мс'**
  String healthOk(int ms);

  /// No description provided for @healthChecking.
  ///
  /// In uk, this message translates to:
  /// **'Перевіряю…'**
  String get healthChecking;

  /// No description provided for @healthUnknown.
  ///
  /// In uk, this message translates to:
  /// **'Ще не перевірено'**
  String get healthUnknown;

  /// No description provided for @healthCheckedAt.
  ///
  /// In uk, this message translates to:
  /// **'Перевірено о {time}'**
  String healthCheckedAt(String time);

  /// No description provided for @checkNow.
  ///
  /// In uk, this message translates to:
  /// **'Перевірити зараз'**
  String get checkNow;

  /// No description provided for @searchHint.
  ///
  /// In uk, this message translates to:
  /// **'Назва, адреса, тег'**
  String get searchHint;

  /// No description provided for @viewTiles.
  ///
  /// In uk, this message translates to:
  /// **'Плитки'**
  String get viewTiles;

  /// No description provided for @viewList.
  ///
  /// In uk, this message translates to:
  /// **'Список'**
  String get viewList;

  /// No description provided for @nothingFound.
  ///
  /// In uk, this message translates to:
  /// **'Нічого не знайдено'**
  String get nothingFound;

  /// No description provided for @nothingFoundHint.
  ///
  /// In uk, this message translates to:
  /// **'Спробуйте іншу назву, адресу або тег.'**
  String get nothingFoundHint;

  /// No description provided for @emptyTitle.
  ///
  /// In uk, this message translates to:
  /// **'Тут поки порожньо'**
  String get emptyTitle;

  /// No description provided for @emptyHint.
  ///
  /// In uk, this message translates to:
  /// **'Додайте перший ПК, імпортуйте .rdp-файли або відновіть бекап у налаштуваннях.'**
  String get emptyHint;

  /// No description provided for @editPcTitle.
  ///
  /// In uk, this message translates to:
  /// **'Редагувати ПК'**
  String get editPcTitle;

  /// No description provided for @addressRequired.
  ///
  /// In uk, this message translates to:
  /// **'Вкажіть адресу: 10.0.0.5, srv.local:3390 або [fd00::5]:3389'**
  String get addressRequired;

  /// No description provided for @macFormat.
  ///
  /// In uk, this message translates to:
  /// **'MAC-адреса має вигляд AA:BB:CC:DD:EE:FF'**
  String get macFormat;

  /// No description provided for @broadcastFormat.
  ///
  /// In uk, this message translates to:
  /// **'Широкомовна адреса — це IPv4, наприклад 192.168.1.255'**
  String get broadcastFormat;

  /// No description provided for @tabGeneral.
  ///
  /// In uk, this message translates to:
  /// **'Загальні'**
  String get tabGeneral;

  /// No description provided for @tabDisplay.
  ///
  /// In uk, this message translates to:
  /// **'Екран'**
  String get tabDisplay;

  /// No description provided for @tabDevices.
  ///
  /// In uk, this message translates to:
  /// **'Пристрої'**
  String get tabDevices;

  /// No description provided for @tabAdvanced.
  ///
  /// In uk, this message translates to:
  /// **'Додатково'**
  String get tabAdvanced;

  /// No description provided for @tabTheme.
  ///
  /// In uk, this message translates to:
  /// **'Тема'**
  String get tabTheme;

  /// No description provided for @tabRoutes.
  ///
  /// In uk, this message translates to:
  /// **'Маршрути'**
  String get tabRoutes;

  /// No description provided for @tabBackup.
  ///
  /// In uk, this message translates to:
  /// **'Бекап'**
  String get tabBackup;

  /// No description provided for @pcAddress.
  ///
  /// In uk, this message translates to:
  /// **'Адреса ПК'**
  String get pcAddress;

  /// No description provided for @pcAddressHint.
  ///
  /// In uk, this message translates to:
  /// **'Ім\'я, IP або ім\'я:порт'**
  String get pcAddressHint;

  /// No description provided for @nameHelper.
  ///
  /// In uk, this message translates to:
  /// **'Якщо порожньо — показується адреса'**
  String get nameHelper;

  /// No description provided for @group.
  ///
  /// In uk, this message translates to:
  /// **'Група'**
  String get group;

  /// No description provided for @noAccountsHint.
  ///
  /// In uk, this message translates to:
  /// **'Питати логін і пароль при кожному підключенні.'**
  String get noAccountsHint;

  /// No description provided for @defaultAccount.
  ///
  /// In uk, this message translates to:
  /// **'За замовчуванням'**
  String get defaultAccount;

  /// No description provided for @availableInConnectAs.
  ///
  /// In uk, this message translates to:
  /// **'Доступний у «Підключитись як…»'**
  String get availableInConnectAs;

  /// No description provided for @removeFromPc.
  ///
  /// In uk, this message translates to:
  /// **'Прибрати з цього ПК'**
  String get removeFromPc;

  /// No description provided for @addSavedAccount.
  ///
  /// In uk, this message translates to:
  /// **'Додати збережений'**
  String get addSavedAccount;

  /// No description provided for @route.
  ///
  /// In uk, this message translates to:
  /// **'Маршрут'**
  String get route;

  /// No description provided for @routeHow.
  ///
  /// In uk, this message translates to:
  /// **'Як підключатися'**
  String get routeHow;

  /// No description provided for @routeViaTunnel.
  ///
  /// In uk, this message translates to:
  /// **'Через вбудований тунель (WireGuard)'**
  String get routeViaTunnel;

  /// No description provided for @routeViaProxy.
  ///
  /// In uk, this message translates to:
  /// **'Через проксі'**
  String get routeViaProxy;

  /// No description provided for @noRouteProfiles.
  ///
  /// In uk, this message translates to:
  /// **'Ще немає жодного профілю. Додайте його в Налаштування → Маршрути.'**
  String get noRouteProfiles;

  /// No description provided for @profile.
  ///
  /// In uk, this message translates to:
  /// **'Профіль'**
  String get profile;

  /// No description provided for @noGateway.
  ///
  /// In uk, this message translates to:
  /// **'Без шлюзу'**
  String get noGateway;

  /// No description provided for @bypassGatewayLocal.
  ///
  /// In uk, this message translates to:
  /// **'Обходити шлюз для локальних адрес'**
  String get bypassGatewayLocal;

  /// No description provided for @sectionConnection.
  ///
  /// In uk, this message translates to:
  /// **'Підключення'**
  String get sectionConnection;

  /// No description provided for @reconnectOnDrop.
  ///
  /// In uk, this message translates to:
  /// **'Перепідключатися при обриві'**
  String get reconnectOnDrop;

  /// No description provided for @adminSession.
  ///
  /// In uk, this message translates to:
  /// **'Адміністративний сеанс'**
  String get adminSession;

  /// No description provided for @adminSessionHint.
  ///
  /// In uk, this message translates to:
  /// **'Підключення до консольного сеансу сервера. У такому сеансі Windows не передає мікрофон.'**
  String get adminSessionHint;

  /// No description provided for @swapMouse.
  ///
  /// In uk, this message translates to:
  /// **'Поміняти кнопки миші місцями'**
  String get swapMouse;

  /// No description provided for @useAllMonitors.
  ///
  /// In uk, this message translates to:
  /// **'Використовувати всі монітори'**
  String get useAllMonitors;

  /// No description provided for @startFullscreen.
  ///
  /// In uk, this message translates to:
  /// **'Запуск на весь екран'**
  String get startFullscreen;

  /// No description provided for @asInGeneralSettings.
  ///
  /// In uk, this message translates to:
  /// **'Як у загальних налаштуваннях'**
  String get asInGeneralSettings;

  /// No description provided for @onWindowResize.
  ///
  /// In uk, this message translates to:
  /// **'Коли змінюється розмір вікна'**
  String get onWindowResize;

  /// No description provided for @resizeChangeResolution.
  ///
  /// In uk, this message translates to:
  /// **'Змінювати роздільність'**
  String get resizeChangeResolution;

  /// No description provided for @resizeScale.
  ///
  /// In uk, this message translates to:
  /// **'Масштабувати'**
  String get resizeScale;

  /// No description provided for @resizeNone.
  ///
  /// In uk, this message translates to:
  /// **'Без змін'**
  String get resizeNone;

  /// No description provided for @colorDepth.
  ///
  /// In uk, this message translates to:
  /// **'Глибина кольору'**
  String get colorDepth;

  /// No description provided for @color32.
  ///
  /// In uk, this message translates to:
  /// **'Найвища (32 біти)'**
  String get color32;

  /// No description provided for @color24.
  ///
  /// In uk, this message translates to:
  /// **'Висока (24 біти)'**
  String get color24;

  /// No description provided for @color16.
  ///
  /// In uk, this message translates to:
  /// **'Середня (16 біт) — менше трафіку'**
  String get color16;

  /// No description provided for @color15.
  ///
  /// In uk, this message translates to:
  /// **'Низька (15 біт)'**
  String get color15;

  /// No description provided for @remoteScale.
  ///
  /// In uk, this message translates to:
  /// **'Масштаб елементів на віддаленому ПК'**
  String get remoteScale;

  /// No description provided for @hiDpi.
  ///
  /// In uk, this message translates to:
  /// **'Повна чіткість (HiDPI)'**
  String get hiDpi;

  /// No description provided for @hiDpiWarning.
  ///
  /// In uk, this message translates to:
  /// **'Вимкніть на повільному з\'єднанні: на екранах 150–200 % трафіку стане в 2–4 рази менше, а картинка — трохи м\'якшою.'**
  String get hiDpiWarning;

  /// No description provided for @clipboard.
  ///
  /// In uk, this message translates to:
  /// **'Буфер обміну'**
  String get clipboard;

  /// No description provided for @clipboardHint.
  ///
  /// In uk, this message translates to:
  /// **'Текст, зображення й файли в обидва боки'**
  String get clipboardHint;

  /// No description provided for @microphone.
  ///
  /// In uk, this message translates to:
  /// **'Мікрофон цього пристрою — на віддалений ПК'**
  String get microphone;

  /// No description provided for @microphoneHint.
  ///
  /// In uk, this message translates to:
  /// **'Програми на віддаленому ПК чутимуть ваш мікрофон. Не працює в адміністративному сеансі; на деяких серверах його ще має дозволити адміністратор.'**
  String get microphoneHint;

  /// No description provided for @sound.
  ///
  /// In uk, this message translates to:
  /// **'Звук віддаленого ПК'**
  String get sound;

  /// No description provided for @soundLocal.
  ///
  /// In uk, this message translates to:
  /// **'Транслювати на цей ПК'**
  String get soundLocal;

  /// No description provided for @soundRemote.
  ///
  /// In uk, this message translates to:
  /// **'Залишити на віддаленому пристрої'**
  String get soundRemote;

  /// No description provided for @soundOff.
  ///
  /// In uk, this message translates to:
  /// **'Вимкнути зовсім'**
  String get soundOff;

  /// No description provided for @soundRemoteHint.
  ///
  /// In uk, this message translates to:
  /// **'Звук гратиме з колонок самого віддаленого ПК. Якщо колонок у нього немає (сервер, VPS), звуку не буде ніде.'**
  String get soundRemoteHint;

  /// No description provided for @folders.
  ///
  /// In uk, this message translates to:
  /// **'Папки'**
  String get folders;

  /// No description provided for @noFolders.
  ///
  /// In uk, this message translates to:
  /// **'Жодна папка не доступна віддаленому ПК.'**
  String get noFolders;

  /// No description provided for @readOnly.
  ///
  /// In uk, this message translates to:
  /// **'Лише читання'**
  String get readOnly;

  /// No description provided for @foldersHint.
  ///
  /// In uk, this message translates to:
  /// **'Кожна папка з\'явиться на віддаленому ПК як диск у «Цей ПК». «Додавати без видалення»: можна читати все й класти нове, але не видаляти, не перейменовувати й не змінювати те, що вже є.'**
  String get foldersHint;

  /// No description provided for @folderAddOnly.
  ///
  /// In uk, this message translates to:
  /// **'Додавати без видалення'**
  String get folderAddOnly;

  /// No description provided for @folderFull.
  ///
  /// In uk, this message translates to:
  /// **'Повний доступ'**
  String get folderFull;

  /// No description provided for @removeFolder.
  ///
  /// In uk, this message translates to:
  /// **'Прибрати папку'**
  String get removeFolder;

  /// No description provided for @addFolder.
  ///
  /// In uk, this message translates to:
  /// **'Додати папку'**
  String get addFolder;

  /// No description provided for @tags.
  ///
  /// In uk, this message translates to:
  /// **'Теги'**
  String get tags;

  /// No description provided for @tagsHelper.
  ///
  /// In uk, this message translates to:
  /// **'Через кому: офіс, 1с, бухгалтерія'**
  String get tagsHelper;

  /// No description provided for @wolMac.
  ///
  /// In uk, this message translates to:
  /// **'MAC-адреса для Wake-on-LAN'**
  String get wolMac;

  /// No description provided for @wolMacHelper.
  ///
  /// In uk, this message translates to:
  /// **'Щоб будити ПК із меню «Розбудити»'**
  String get wolMacHelper;

  /// No description provided for @wolBroadcast.
  ///
  /// In uk, this message translates to:
  /// **'Широкомовна адреса для Wake-on-LAN (необов\'язково)'**
  String get wolBroadcast;

  /// No description provided for @wolBroadcastHelper.
  ///
  /// In uk, this message translates to:
  /// **'Якщо ПК в іншій підмережі — її broadcast, наприклад 192.168.1.255'**
  String get wolBroadcastHelper;

  /// No description provided for @serverCertificate.
  ///
  /// In uk, this message translates to:
  /// **'Сертифікат сервера'**
  String get serverCertificate;

  /// No description provided for @trustedFingerprint.
  ///
  /// In uk, this message translates to:
  /// **'Довірений відбиток: {fingerprint}'**
  String trustedFingerprint(String fingerprint);

  /// No description provided for @forgetCertificate.
  ///
  /// In uk, this message translates to:
  /// **'Забути сертифікат (спитати знову при підключенні)'**
  String get forgetCertificate;

  /// No description provided for @inUseTitle.
  ///
  /// In uk, this message translates to:
  /// **'{what} використовується'**
  String inUseTitle(String what);

  /// No description provided for @inUseBody.
  ///
  /// In uk, this message translates to:
  /// **'Його використовують: {users}.\nПрибрати його звідти й видалити?'**
  String inUseBody(String users);

  /// No description provided for @inUseCredential.
  ///
  /// In uk, this message translates to:
  /// **'Обліковий запис'**
  String get inUseCredential;

  /// No description provided for @inUseGateway.
  ///
  /// In uk, this message translates to:
  /// **'Шлюз'**
  String get inUseGateway;

  /// No description provided for @inUseTunnel.
  ///
  /// In uk, this message translates to:
  /// **'Тунель'**
  String get inUseTunnel;

  /// No description provided for @inUseProxy.
  ///
  /// In uk, this message translates to:
  /// **'Проксі'**
  String get inUseProxy;

  /// No description provided for @gatewayUser.
  ///
  /// In uk, this message translates to:
  /// **'шлюз {name}'**
  String gatewayUser(String name);

  /// No description provided for @startSessionsFullscreen.
  ///
  /// In uk, this message translates to:
  /// **'Запускати сеанси на весь екран'**
  String get startSessionsFullscreen;

  /// No description provided for @keepScreenAwake.
  ///
  /// In uk, this message translates to:
  /// **'Не вимикати екран під час сеансу'**
  String get keepScreenAwake;

  /// No description provided for @showPreviews.
  ///
  /// In uk, this message translates to:
  /// **'Мініатюри ПК у списку'**
  String get showPreviews;

  /// No description provided for @keyboardCapture.
  ///
  /// In uk, this message translates to:
  /// **'Клавіші Win, Alt+Tab тощо надсилати на віддалений ПК'**
  String get keyboardCapture;

  /// No description provided for @captureFullscreenOnly.
  ///
  /// In uk, this message translates to:
  /// **'Лише на весь екран'**
  String get captureFullscreenOnly;

  /// No description provided for @accountsHint.
  ///
  /// In uk, this message translates to:
  /// **'Один обліковий запис можна призначити багатьом ПК. Зміна пароля діє одразу для всіх.'**
  String get accountsHint;

  /// No description provided for @askPassword.
  ///
  /// In uk, this message translates to:
  /// **'Питати пароль'**
  String get askPassword;

  /// No description provided for @passwordSaved.
  ///
  /// In uk, this message translates to:
  /// **'Пароль збережено'**
  String get passwordSaved;

  /// No description provided for @addAccount.
  ///
  /// In uk, this message translates to:
  /// **'Додати обліковий запис'**
  String get addAccount;

  /// No description provided for @gatewayNew.
  ///
  /// In uk, this message translates to:
  /// **'Новий шлюз'**
  String get gatewayNew;

  /// No description provided for @gatewayTitle.
  ///
  /// In uk, this message translates to:
  /// **'Шлюз'**
  String get gatewayTitle;

  /// No description provided for @gatewayAddress.
  ///
  /// In uk, this message translates to:
  /// **'Адреса шлюзу'**
  String get gatewayAddress;

  /// No description provided for @gatewayAccount.
  ///
  /// In uk, this message translates to:
  /// **'Обліковий запис для шлюзу'**
  String get gatewayAccount;

  /// No description provided for @gatewaySameAsPc.
  ///
  /// In uk, this message translates to:
  /// **'Той самий, що й для ПК'**
  String get gatewaySameAsPc;

  /// No description provided for @addGateway.
  ///
  /// In uk, this message translates to:
  /// **'Додати шлюз'**
  String get addGateway;

  /// No description provided for @wgImported.
  ///
  /// In uk, this message translates to:
  /// **'Тунель «{name}» імпортовано. Ключі збережено в системному сховищі.'**
  String wgImported(String name);

  /// No description provided for @wgImportedExtraPeers.
  ///
  /// In uk, this message translates to:
  /// **'Імпортовано. У файлі кілька [Peer] — поки використовується перший.'**
  String get wgImportedExtraPeers;

  /// No description provided for @wgNoPrivateKey.
  ///
  /// In uk, this message translates to:
  /// **'У файлі немає PrivateKey у секції [Interface].'**
  String get wgNoPrivateKey;

  /// No description provided for @wgNoPeer.
  ///
  /// In uk, this message translates to:
  /// **'У файлі немає секції [Peer] з PublicKey і Endpoint.'**
  String get wgNoPeer;

  /// No description provided for @builtInTunnels.
  ///
  /// In uk, this message translates to:
  /// **'Вбудовані тунелі'**
  String get builtInTunnels;

  /// No description provided for @tunnelsHint.
  ///
  /// In uk, this message translates to:
  /// **'Тунель працює всередині MHRD: без прав адміністратора і не заважає іншому VPN. Підтримується WireGuard. Для Tailscale та інших VPN увімкніть їх у системі й виберіть «Напряму».'**
  String get tunnelsHint;

  /// No description provided for @importWireGuard.
  ///
  /// In uk, this message translates to:
  /// **'Імпортувати WireGuard .conf'**
  String get importWireGuard;

  /// No description provided for @proxies.
  ///
  /// In uk, this message translates to:
  /// **'Проксі'**
  String get proxies;

  /// No description provided for @comingInStage6.
  ///
  /// In uk, this message translates to:
  /// **'З\'являться на етапі 6.'**
  String get comingInStage6;

  /// No description provided for @routeErrProxyMissing.
  ///
  /// In uk, this message translates to:
  /// **'Проксі цього ПК видалено. Виберіть маршрут у налаштуваннях ПК.'**
  String get routeErrProxyMissing;

  /// No description provided for @routeErrGatewayMissing.
  ///
  /// In uk, this message translates to:
  /// **'Шлюз цього ПК видалено. Виберіть інший у налаштуваннях ПК.'**
  String get routeErrGatewayMissing;

  /// No description provided for @routeErrTunnel.
  ///
  /// In uk, this message translates to:
  /// **'Цей тип тунелю ще не підтримується — поки працює WireGuard.'**
  String get routeErrTunnel;

  /// No description provided for @routeErrTunnelMissing.
  ///
  /// In uk, this message translates to:
  /// **'Тунель цього ПК видалено. Виберіть маршрут у налаштуваннях ПК.'**
  String get routeErrTunnelMissing;

  /// No description provided for @routeErrTunnelEngine.
  ///
  /// In uk, this message translates to:
  /// **'Не знайдено модуль тунелів (mhrd-tunnel) поруч із програмою. Перевстановіть MHRD.'**
  String get routeErrTunnelEngine;

  /// No description provided for @routeErrGatewayTunnel.
  ///
  /// In uk, this message translates to:
  /// **'RD Gateway разом із тунелем поки не підтримується — приберіть шлюз або тунель у налаштуваннях ПК.'**
  String get routeErrGatewayTunnel;

  /// No description provided for @tunnelErrConfig.
  ///
  /// In uk, this message translates to:
  /// **'Налаштування тунелю некоректні. Перевірте їх або імпортуйте .conf знову.'**
  String get tunnelErrConfig;

  /// No description provided for @tunnelErrEndpointDns.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося знайти сервер тунелю за іменем.'**
  String get tunnelErrEndpointDns;

  /// No description provided for @tunnelErrStart.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося запустити тунель.'**
  String get tunnelErrStart;

  /// No description provided for @tunnelErrUnreachable.
  ///
  /// In uk, this message translates to:
  /// **'Тунель піднявся, але ПК не відповідає. Перевірте, чи працює сервер тунелю і чи ПК у його мережі.'**
  String get tunnelErrUnreachable;

  /// No description provided for @tunnelErrConnect.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося підключитися до сервера тунелю.'**
  String get tunnelErrConnect;

  /// No description provided for @tunnelErrListen.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося відкрити локальний порт для тунелю.'**
  String get tunnelErrListen;

  /// No description provided for @tunnelErrFailed.
  ///
  /// In uk, this message translates to:
  /// **'Тунель несподівано завершився.'**
  String get tunnelErrFailed;

  /// No description provided for @tunnelErrHandshake.
  ///
  /// In uk, this message translates to:
  /// **'Сервер WireGuard не відповідає. Перевірте адресу сервера, ключі й чи не блокує мережа UDP.'**
  String get tunnelErrHandshake;

  /// No description provided for @proxyErrUnreachable.
  ///
  /// In uk, this message translates to:
  /// **'Проксі недоступний: не вдалося з\'єднатися. Перевірте адресу й порт.'**
  String get proxyErrUnreachable;

  /// No description provided for @proxyErrProtocol.
  ///
  /// In uk, this message translates to:
  /// **'За цією адресою не проксі вибраного типу. Перевірте тип (SOCKS5 чи HTTP) і порт.'**
  String get proxyErrProtocol;

  /// No description provided for @proxyErrAuth.
  ///
  /// In uk, this message translates to:
  /// **'Проксі відхилив логін або пароль.'**
  String get proxyErrAuth;

  /// No description provided for @proxyErrRefused.
  ///
  /// In uk, this message translates to:
  /// **'Проксі працює, але не пускає до ПК. Часто такі проксі дозволяють лише вебсайти (порт 443), а RDP (3389) блокують.'**
  String get proxyErrRefused;

  /// No description provided for @resolution.
  ///
  /// In uk, this message translates to:
  /// **'Роздільність віддаленого екрана'**
  String get resolution;

  /// No description provided for @resolutionHint.
  ///
  /// In uk, this message translates to:
  /// **'Під розмір вікна — підлаштовується, коли тягнете вікно. Шаблон — завжди та сама роздільність, картинка масштабується.'**
  String get resolutionHint;

  /// No description provided for @screenAuto.
  ///
  /// In uk, this message translates to:
  /// **'Під розмір вікна'**
  String get screenAuto;

  /// No description provided for @screenPortrait.
  ///
  /// In uk, this message translates to:
  /// **'вертикальний'**
  String get screenPortrait;

  /// No description provided for @asInGeneralSettingsWith.
  ///
  /// In uk, this message translates to:
  /// **'Як у загальних налаштуваннях ({name})'**
  String asInGeneralSettingsWith(String name);

  /// No description provided for @screenTemplates.
  ///
  /// In uk, this message translates to:
  /// **'Шаблони екрана'**
  String get screenTemplates;

  /// No description provided for @tabNewPcs.
  ///
  /// In uk, this message translates to:
  /// **'Нові ПК'**
  String get tabNewPcs;

  /// No description provided for @newPcDefaults.
  ///
  /// In uk, this message translates to:
  /// **'Налаштування нових ПК'**
  String get newPcDefaults;

  /// No description provided for @newPcDefaultsHint.
  ///
  /// In uk, this message translates to:
  /// **'З цими налаштуваннями створюється кожен новий ПК: «Додати ПК», швидке підключення, імпорт з mstsc. Маршрут, акаунти, екран, звук, буфер обміну — один раз тут, а не для кожного ПК. Уже додані ПК не змінюються.'**
  String get newPcDefaultsHint;

  /// No description provided for @newPcDefaultsEdit.
  ///
  /// In uk, this message translates to:
  /// **'Налаштувати нові ПК'**
  String get newPcDefaultsEdit;

  /// No description provided for @newPcDefaultsReset.
  ///
  /// In uk, this message translates to:
  /// **'Скинути до типових'**
  String get newPcDefaultsReset;

  /// No description provided for @importMstsc.
  ///
  /// In uk, this message translates to:
  /// **'Імпорт з «Підключення до віддаленого робочого стола»'**
  String get importMstsc;

  /// No description provided for @mstscTitle.
  ///
  /// In uk, this message translates to:
  /// **'ПК зі стандартного клієнта Windows'**
  String get mstscTitle;

  /// No description provided for @mstscHint.
  ///
  /// In uk, this message translates to:
  /// **'Windows пам\'ятає ці адреси й імена користувачів. Паролі не переносяться — MHRD спитає під час першого підключення.'**
  String get mstscHint;

  /// No description provided for @mstscNothing.
  ///
  /// In uk, this message translates to:
  /// **'Стандартний клієнт Windows не має збережених ПК.'**
  String get mstscNothing;

  /// No description provided for @mstscAlready.
  ///
  /// In uk, this message translates to:
  /// **'уже є'**
  String get mstscAlready;

  /// No description provided for @mstscAdd.
  ///
  /// In uk, this message translates to:
  /// **'Додати: {count}'**
  String mstscAdd(int count);

  /// No description provided for @defaultScreen.
  ///
  /// In uk, this message translates to:
  /// **'Роздільність за замовчуванням для всіх ПК'**
  String get defaultScreen;

  /// No description provided for @customScreens.
  ///
  /// In uk, this message translates to:
  /// **'Свої шаблони'**
  String get customScreens;

  /// No description provided for @noCustomScreens.
  ///
  /// In uk, this message translates to:
  /// **'Поки немає. Стандартні — HD, Full HD, QHD, 4K, вертикальні — уже в списку.'**
  String get noCustomScreens;

  /// No description provided for @addScreen.
  ///
  /// In uk, this message translates to:
  /// **'Додати шаблон'**
  String get addScreen;

  /// No description provided for @screenName.
  ///
  /// In uk, this message translates to:
  /// **'Назва'**
  String get screenName;

  /// No description provided for @screenWidth.
  ///
  /// In uk, this message translates to:
  /// **'Ширина'**
  String get screenWidth;

  /// No description provided for @screenHeight.
  ///
  /// In uk, this message translates to:
  /// **'Висота'**
  String get screenHeight;

  /// No description provided for @screenSizeInvalid.
  ///
  /// In uk, this message translates to:
  /// **'Ширина й висота — від 200 до 8192 пікселів.'**
  String get screenSizeInvalid;

  /// No description provided for @passwordExpiredSaved.
  ///
  /// In uk, this message translates to:
  /// **'Змініть пароль на самому ПК (або в домені) і введіть тут новий — він збережеться в акаунті «{account}» для всіх ПК, що ним користуються.'**
  String passwordExpiredSaved(String account);

  /// No description provided for @passwordExpiredAsk.
  ///
  /// In uk, this message translates to:
  /// **'Змініть пароль на самому ПК (або в домені), а потім підключіться з новим.'**
  String get passwordExpiredAsk;

  /// No description provided for @newPassword.
  ///
  /// In uk, this message translates to:
  /// **'Новий пароль'**
  String get newPassword;

  /// No description provided for @saveAndConnect.
  ///
  /// In uk, this message translates to:
  /// **'Підключитись'**
  String get saveAndConnect;

  /// No description provided for @selectedCount.
  ///
  /// In uk, this message translates to:
  /// **'Вибрано: {count}'**
  String selectedCount(int count);

  /// No description provided for @selectAll.
  ///
  /// In uk, this message translates to:
  /// **'Вибрати всі'**
  String get selectAll;

  /// No description provided for @deletePcsTitle.
  ///
  /// In uk, this message translates to:
  /// **'Видалити вибрані ПК ({count})?'**
  String deletePcsTitle(int count);

  /// No description provided for @dragHint.
  ///
  /// In uk, this message translates to:
  /// **'або перетягніть на групу зліва'**
  String get dragHint;

  /// No description provided for @pcImage.
  ///
  /// In uk, this message translates to:
  /// **'Картинка на плитці'**
  String get pcImage;

  /// No description provided for @pcImageHint.
  ///
  /// In uk, this message translates to:
  /// **'Своя картинка замість мініатюри останнього сеансу.'**
  String get pcImageHint;

  /// No description provided for @pcImagePick.
  ///
  /// In uk, this message translates to:
  /// **'Вибрати картинку'**
  String get pcImagePick;

  /// No description provided for @pcImageRemove.
  ///
  /// In uk, this message translates to:
  /// **'Прибрати'**
  String get pcImageRemove;

  /// No description provided for @imageFiles.
  ///
  /// In uk, this message translates to:
  /// **'Зображення'**
  String get imageFiles;

  /// No description provided for @lockSection.
  ///
  /// In uk, this message translates to:
  /// **'Блокування'**
  String get lockSection;

  /// No description provided for @lockEnable.
  ///
  /// In uk, this message translates to:
  /// **'Блокувати MHRD PIN-кодом'**
  String get lockEnable;

  /// No description provided for @lockEnableHint.
  ///
  /// In uk, this message translates to:
  /// **'PIN питається при кожному запуску. Відкриті сеанси працюють далі.'**
  String get lockEnableHint;

  /// No description provided for @lockBiometric.
  ///
  /// In uk, this message translates to:
  /// **'Відкривати відбитком / Windows Hello'**
  String get lockBiometric;

  /// No description provided for @lockReason.
  ///
  /// In uk, this message translates to:
  /// **'Розблокувати MHRD'**
  String get lockReason;

  /// No description provided for @lockTitle.
  ///
  /// In uk, this message translates to:
  /// **'Введіть PIN-код'**
  String get lockTitle;

  /// No description provided for @lockSetPin.
  ///
  /// In uk, this message translates to:
  /// **'Новий PIN-код'**
  String get lockSetPin;

  /// No description provided for @pinHint.
  ///
  /// In uk, this message translates to:
  /// **'PIN'**
  String get pinHint;

  /// No description provided for @pinNew.
  ///
  /// In uk, this message translates to:
  /// **'PIN-код (від 4 цифр)'**
  String get pinNew;

  /// No description provided for @pinRepeat.
  ///
  /// In uk, this message translates to:
  /// **'Ще раз'**
  String get pinRepeat;

  /// No description provided for @pinCurrent.
  ///
  /// In uk, this message translates to:
  /// **'Поточний PIN-код'**
  String get pinCurrent;

  /// No description provided for @pinWrong.
  ///
  /// In uk, this message translates to:
  /// **'Неправильний PIN-код.'**
  String get pinWrong;

  /// No description provided for @pinWait.
  ///
  /// In uk, this message translates to:
  /// **'Забагато невдалих спроб. Наступна — через {seconds} с.'**
  String pinWait(int seconds);

  /// No description provided for @pinTooShort.
  ///
  /// In uk, this message translates to:
  /// **'PIN-код — щонайменше 4 цифри.'**
  String get pinTooShort;

  /// No description provided for @pinMismatch.
  ///
  /// In uk, this message translates to:
  /// **'PIN-коди не збігаються.'**
  String get pinMismatch;

  /// No description provided for @unlock.
  ///
  /// In uk, this message translates to:
  /// **'Розблокувати'**
  String get unlock;

  /// No description provided for @unlockBiometric.
  ///
  /// In uk, this message translates to:
  /// **'Відбиток / Windows Hello'**
  String get unlockBiometric;

  /// No description provided for @wgEditTitle.
  ///
  /// In uk, this message translates to:
  /// **'Налаштування WireGuard'**
  String get wgEditTitle;

  /// No description provided for @wgUpdateFromConf.
  ///
  /// In uk, this message translates to:
  /// **'Оновити з .conf (ПК лишаються на цьому тунелі)'**
  String get wgUpdateFromConf;

  /// No description provided for @wgKeysRequired.
  ///
  /// In uk, this message translates to:
  /// **'Потрібні PrivateKey і PublicKey сервера.'**
  String get wgKeysRequired;

  /// No description provided for @showKeys.
  ///
  /// In uk, this message translates to:
  /// **'Показати ключі'**
  String get showKeys;

  /// No description provided for @wgCreateManual.
  ///
  /// In uk, this message translates to:
  /// **'Створити вручну'**
  String get wgCreateManual;

  /// No description provided for @wgNewTitle.
  ///
  /// In uk, this message translates to:
  /// **'Новий тунель WireGuard'**
  String get wgNewTitle;

  /// No description provided for @wgGenerateKeys.
  ///
  /// In uk, this message translates to:
  /// **'Згенерувати ключі'**
  String get wgGenerateKeys;

  /// No description provided for @wgYourPublicKey.
  ///
  /// In uk, this message translates to:
  /// **'Ваш публічний ключ — додайте його на сервері WireGuard як [Peer] цього пристрою'**
  String get wgYourPublicKey;

  /// No description provided for @wgKeyInvalid.
  ///
  /// In uk, this message translates to:
  /// **'Ключ має бути 32 байти в Base64: 44 символи з «=» у кінці.'**
  String get wgKeyInvalid;

  /// No description provided for @wgAddressRequired.
  ///
  /// In uk, this message translates to:
  /// **'Вкажіть Address — адресу цього пристрою в тунелі, наприклад 10.8.0.2/32.'**
  String get wgAddressRequired;

  /// No description provided for @copy.
  ///
  /// In uk, this message translates to:
  /// **'Копіювати'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In uk, this message translates to:
  /// **'Скопійовано.'**
  String get copied;

  /// No description provided for @activeSessions.
  ///
  /// In uk, this message translates to:
  /// **'Активних сеансів: {count}'**
  String activeSessions(int count);

  /// No description provided for @touchModeDirect.
  ///
  /// In uk, this message translates to:
  /// **'Перейти на дотик: пальці — як сенсорний екран ПК'**
  String get touchModeDirect;

  /// No description provided for @touchModeMouse.
  ///
  /// In uk, this message translates to:
  /// **'Перейти на мишу: курсор, як тачпад'**
  String get touchModeMouse;

  /// No description provided for @barCollapse.
  ///
  /// In uk, this message translates to:
  /// **'Згорнути плашку'**
  String get barCollapse;

  /// No description provided for @homeScreen.
  ///
  /// In uk, this message translates to:
  /// **'Головна'**
  String get homeScreen;

  /// No description provided for @lockBiometricPhone.
  ///
  /// In uk, this message translates to:
  /// **'Відкривати відбитком пальця'**
  String get lockBiometricPhone;

  /// No description provided for @autoBackupInApp.
  ///
  /// In uk, this message translates to:
  /// **'Копії — у пам\'яті MHRD на цьому телефоні. Файл назовні — кнопкою «Зберегти бекап».'**
  String get autoBackupInApp;

  /// No description provided for @restoreFromFile.
  ///
  /// In uk, this message translates to:
  /// **'З файлу…'**
  String get restoreFromFile;

  /// No description provided for @clipboardHintPhone.
  ///
  /// In uk, this message translates to:
  /// **'Текст в обидва боки: скопійоване на ПК одразу в буфері телефона, а скопійоване на телефоні — на ПК, щойно повернетесь у MHRD.'**
  String get clipboardHintPhone;

  /// No description provided for @unlockBiometricPhone.
  ///
  /// In uk, this message translates to:
  /// **'Відбиток пальця'**
  String get unlockBiometricPhone;

  /// No description provided for @authNeedPinPhone.
  ///
  /// In uk, this message translates to:
  /// **'Щоб редагувати ключі, увімкніть блокування PIN-кодом (Налаштування → Загальні).'**
  String get authNeedPinPhone;

  /// No description provided for @keyboardShiftsScreen.
  ///
  /// In uk, this message translates to:
  /// **'Екранна клавіатура зсуває картинку сеансу (інакше — поверх неї)'**
  String get keyboardShiftsScreen;

  /// No description provided for @authEditReason.
  ///
  /// In uk, this message translates to:
  /// **'Редагування ключів тунелю MHRD'**
  String get authEditReason;

  /// No description provided for @authNeedPin.
  ///
  /// In uk, this message translates to:
  /// **'Щоб редагувати ключі, увімкніть блокування PIN-кодом (Налаштування → Загальні) або Windows Hello.'**
  String get authNeedPin;

  /// No description provided for @sessionStartFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося запустити сеанс: {detail}'**
  String sessionStartFailed(String detail);

  /// No description provided for @checkingRoute.
  ///
  /// In uk, this message translates to:
  /// **'Перевіряю з\'єднання…'**
  String get checkingRoute;

  /// No description provided for @saveAnyway.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти все одно'**
  String get saveAnyway;

  /// No description provided for @wgCheckOk.
  ///
  /// In uk, this message translates to:
  /// **'Тунель працює: сервер відповів за {ms} мс. Ваша адреса в тунелі — {address}.'**
  String wgCheckOk(int ms, String address);

  /// No description provided for @proxyCheckOk.
  ///
  /// In uk, this message translates to:
  /// **'Проксі працює, відповів за {ms} мс.'**
  String proxyCheckOk(int ms);

  /// No description provided for @proxyCheckOkPc.
  ///
  /// In uk, this message translates to:
  /// **'Проксі працює і пускає до «{pc}» — {ms} мс.'**
  String proxyCheckOkPc(int ms, String pc);

  /// No description provided for @checkConnection.
  ///
  /// In uk, this message translates to:
  /// **'Перевірити з\'єднання'**
  String get checkConnection;

  /// No description provided for @pcResponds.
  ///
  /// In uk, this message translates to:
  /// **'ПК відповідає · {ms} мс через увесь маршрут'**
  String pcResponds(int ms);

  /// No description provided for @probeErrPc.
  ///
  /// In uk, this message translates to:
  /// **'ПК не відповідає на порт RDP: вимкнений, блокує брандмауер або неправильна адреса чи порт.'**
  String get probeErrPc;

  /// No description provided for @probeErrGateway.
  ///
  /// In uk, this message translates to:
  /// **'RD Gateway не відповідає. Перевірте адресу й порт шлюзу.'**
  String get probeErrGateway;

  /// No description provided for @addProxy.
  ///
  /// In uk, this message translates to:
  /// **'Додати проксі'**
  String get addProxy;

  /// No description provided for @proxyNew.
  ///
  /// In uk, this message translates to:
  /// **'Новий проксі'**
  String get proxyNew;

  /// No description provided for @proxyTitle.
  ///
  /// In uk, this message translates to:
  /// **'Проксі'**
  String get proxyTitle;

  /// No description provided for @proxyType.
  ///
  /// In uk, this message translates to:
  /// **'Тип'**
  String get proxyType;

  /// No description provided for @proxyAddress.
  ///
  /// In uk, this message translates to:
  /// **'Адреса проксі'**
  String get proxyAddress;

  /// No description provided for @proxyLoginHint.
  ///
  /// In uk, this message translates to:
  /// **'Логін і пароль — лише якщо проксі їх вимагає'**
  String get proxyLoginHint;

  /// No description provided for @groupNew.
  ///
  /// In uk, this message translates to:
  /// **'Нова група'**
  String get groupNew;

  /// No description provided for @groupRename.
  ///
  /// In uk, this message translates to:
  /// **'Перейменувати групу'**
  String get groupRename;

  /// No description provided for @groupNestInto.
  ///
  /// In uk, this message translates to:
  /// **'Вкласти «{name}» у…'**
  String groupNestInto(String name);

  /// No description provided for @topLevel.
  ///
  /// In uk, this message translates to:
  /// **'Верхній рівень'**
  String get topLevel;

  /// No description provided for @groupMoveContentsTo.
  ///
  /// In uk, this message translates to:
  /// **'Куди перенести вміст групи «{name}»?'**
  String groupMoveContentsTo(String name);

  /// No description provided for @groupDeleteTitle.
  ///
  /// In uk, this message translates to:
  /// **'Видалити групу «{name}»?'**
  String groupDeleteTitle(String name);

  /// No description provided for @defaultGroupInfo.
  ///
  /// In uk, this message translates to:
  /// **'Стандартна група · ПК: {count}'**
  String defaultGroupInfo(int count);

  /// No description provided for @nestIntoOther.
  ///
  /// In uk, this message translates to:
  /// **'Вкласти в іншу групу'**
  String get nestIntoOther;

  /// No description provided for @groupCycle.
  ///
  /// In uk, this message translates to:
  /// **'Група не може бути вкладена сама в себе.'**
  String get groupCycle;

  /// No description provided for @backupPasswordTitle.
  ///
  /// In uk, this message translates to:
  /// **'Пароль для бекапу'**
  String get backupPasswordTitle;

  /// No description provided for @encryptingBackup.
  ///
  /// In uk, this message translates to:
  /// **'Шифрую бекап…'**
  String get encryptingBackup;

  /// No description provided for @backupSaved.
  ///
  /// In uk, this message translates to:
  /// **'Бекап збережено: {path}'**
  String backupSaved(String path);

  /// No description provided for @decrypting.
  ///
  /// In uk, this message translates to:
  /// **'Розшифровую…'**
  String get decrypting;

  /// No description provided for @restoreHow.
  ///
  /// In uk, this message translates to:
  /// **'Як відновити?'**
  String get restoreHow;

  /// No description provided for @restoreMerge.
  ///
  /// In uk, this message translates to:
  /// **'Об\'єднати з поточними даними'**
  String get restoreMerge;

  /// No description provided for @restoreReplace.
  ///
  /// In uk, this message translates to:
  /// **'Замінити все (поточні дані спершу збережуться в страхувальну копію)'**
  String get restoreReplace;

  /// No description provided for @restoreConfirmTitle.
  ///
  /// In uk, this message translates to:
  /// **'Відновити бекап?'**
  String get restoreConfirmTitle;

  /// No description provided for @restorePreview.
  ///
  /// In uk, this message translates to:
  /// **'Буде додано ПК: {added}, оновлено: {updated}, видалено: {removed}.'**
  String restorePreview(int added, int updated, int removed);

  /// No description provided for @restore.
  ///
  /// In uk, this message translates to:
  /// **'Відновити'**
  String get restore;

  /// No description provided for @restored.
  ///
  /// In uk, this message translates to:
  /// **'Бекап відновлено.'**
  String get restored;

  /// No description provided for @savedWithoutPasswords.
  ///
  /// In uk, this message translates to:
  /// **'Збережено без паролів: {path}'**
  String savedWithoutPasswords(String path);

  /// No description provided for @shareImported.
  ///
  /// In uk, this message translates to:
  /// **'Імпортовано. Паролі введіть при першому підключенні.'**
  String get shareImported;

  /// No description provided for @fullBackup.
  ///
  /// In uk, this message translates to:
  /// **'Повний бекап'**
  String get fullBackup;

  /// No description provided for @fullBackupHint.
  ///
  /// In uk, this message translates to:
  /// **'Усі ПК, облікові записи з паролями, шлюзи, тунелі з ключами, групи, теми й налаштування. Файл шифрується вашим паролем (Argon2id + AES-256-GCM) і відкривається на будь-якій ОС.'**
  String get fullBackupHint;

  /// No description provided for @backupNever.
  ///
  /// In uk, this message translates to:
  /// **'Бекап ще не робили.'**
  String get backupNever;

  /// No description provided for @backupLast.
  ///
  /// In uk, this message translates to:
  /// **'Останній бекап: {date}'**
  String backupLast(String date);

  /// No description provided for @saveBackup.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти бекап'**
  String get saveBackup;

  /// No description provided for @restoreFromBackup.
  ///
  /// In uk, this message translates to:
  /// **'Відновити з бекапу'**
  String get restoreFromBackup;

  /// No description provided for @sharePcList.
  ///
  /// In uk, this message translates to:
  /// **'Поділитися списком ПК'**
  String get sharePcList;

  /// No description provided for @sharePcListHint.
  ///
  /// In uk, this message translates to:
  /// **'Файл без жодного пароля чи ключа — щоб передати список колезі.'**
  String get sharePcListHint;

  /// No description provided for @backupNotMhrdFile.
  ///
  /// In uk, this message translates to:
  /// **'Це не файл бекапу MHRD.'**
  String get backupNotMhrdFile;

  /// No description provided for @backupCorrupted.
  ///
  /// In uk, this message translates to:
  /// **'Файл бекапу пошкоджено.'**
  String get backupCorrupted;

  /// No description provided for @backupWrongPassword.
  ///
  /// In uk, this message translates to:
  /// **'Невірний пароль або файл пошкоджено.'**
  String get backupWrongPassword;

  /// No description provided for @backupFromNewer.
  ///
  /// In uk, this message translates to:
  /// **'Бекап створено новішою версією MHRD. Оновіть застосунок.'**
  String get backupFromNewer;

  /// No description provided for @notShareFile.
  ///
  /// In uk, this message translates to:
  /// **'Це не файл експорту MHRD.'**
  String get notShareFile;

  /// No description provided for @autoBackup.
  ///
  /// In uk, this message translates to:
  /// **'Автобекап'**
  String get autoBackup;

  /// No description provided for @autoBackupHint.
  ///
  /// In uk, this message translates to:
  /// **'Після змін, не частіше разу на годину — у вибрану теку, наприклад синхронізовану з хмарою. Зберігаються останні 10 копій. Пароль автобекапу лежить у системному сховищі цього пристрою.'**
  String get autoBackupHint;

  /// No description provided for @autoBackupPasswordTitle.
  ///
  /// In uk, this message translates to:
  /// **'Пароль автобекапу'**
  String get autoBackupPasswordTitle;

  /// No description provided for @autoBackupFirstCopy.
  ///
  /// In uk, this message translates to:
  /// **'Роблю першу копію…'**
  String get autoBackupFirstCopy;

  /// No description provided for @autoBackupEnabled.
  ///
  /// In uk, this message translates to:
  /// **'Автобекап увімкнено. Перша копія: {path}'**
  String autoBackupEnabled(String path);

  /// No description provided for @autoBackupMaking.
  ///
  /// In uk, this message translates to:
  /// **'Роблю копію…'**
  String get autoBackupMaking;

  /// No description provided for @autoBackupSaved.
  ///
  /// In uk, this message translates to:
  /// **'Копію збережено: {path}'**
  String autoBackupSaved(String path);

  /// No description provided for @autoBackupBusy.
  ///
  /// In uk, this message translates to:
  /// **'Копія вже робиться.'**
  String get autoBackupBusy;

  /// No description provided for @autoBackupNone.
  ///
  /// In uk, this message translates to:
  /// **'Копій ще не було.'**
  String get autoBackupNone;

  /// No description provided for @autoBackupLast.
  ///
  /// In uk, this message translates to:
  /// **'Остання копія: {date}'**
  String autoBackupLast(String date);

  /// No description provided for @enableEllipsis.
  ///
  /// In uk, this message translates to:
  /// **'Увімкнути…'**
  String get enableEllipsis;

  /// No description provided for @autoBackupNow.
  ///
  /// In uk, this message translates to:
  /// **'Зробити копію зараз'**
  String get autoBackupNow;

  /// No description provided for @autoBackupChange.
  ///
  /// In uk, this message translates to:
  /// **'Змінити теку й пароль'**
  String get autoBackupChange;

  /// No description provided for @disable.
  ///
  /// In uk, this message translates to:
  /// **'Вимкнути'**
  String get disable;

  /// No description provided for @autoBackupWriteFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося записати копію в {path}: {reason}'**
  String autoBackupWriteFailed(String path, String reason);

  /// No description provided for @autoBackupNoPassword.
  ///
  /// In uk, this message translates to:
  /// **'Пароль автобекапу не знайдено в системному сховищі. Увімкніть автобекап заново.'**
  String get autoBackupNoPassword;

  /// No description provided for @autoBackupFailed.
  ///
  /// In uk, this message translates to:
  /// **'Автобекап не вдався: {error}'**
  String autoBackupFailed(String error);

  /// No description provided for @themeGraphite.
  ///
  /// In uk, this message translates to:
  /// **'Графіт'**
  String get themeGraphite;

  /// No description provided for @themeLight.
  ///
  /// In uk, this message translates to:
  /// **'Світлий інструмент'**
  String get themeLight;

  /// No description provided for @themeAmber.
  ///
  /// In uk, this message translates to:
  /// **'Нічний бурштин'**
  String get themeAmber;

  /// No description provided for @themeMine.
  ///
  /// In uk, this message translates to:
  /// **'{name} (моя)'**
  String themeMine(String name);

  /// No description provided for @contrastWarnTitle.
  ///
  /// In uk, this message translates to:
  /// **'Текст може бути погано видно'**
  String get contrastWarnTitle;

  /// No description provided for @contrastWarnBody.
  ///
  /// In uk, this message translates to:
  /// **'{problems}\n\nЗберегти все одно?'**
  String contrastWarnBody(String problems);

  /// No description provided for @themeSaved.
  ///
  /// In uk, this message translates to:
  /// **'Тему збережено: {path}'**
  String themeSaved(String path);

  /// No description provided for @notThemeFile.
  ///
  /// In uk, this message translates to:
  /// **'Це не файл теми MHRD.'**
  String get notThemeFile;

  /// No description provided for @themeAdded.
  ///
  /// In uk, this message translates to:
  /// **'Тему «{name}» додано.'**
  String themeAdded(String name);

  /// No description provided for @createTheme.
  ///
  /// In uk, this message translates to:
  /// **'Створити свою тему'**
  String get createTheme;

  /// No description provided for @importTheme.
  ///
  /// In uk, this message translates to:
  /// **'Імпортувати тему'**
  String get importTheme;

  /// No description provided for @exportCurrentTheme.
  ///
  /// In uk, this message translates to:
  /// **'Експортувати поточну'**
  String get exportCurrentTheme;

  /// No description provided for @editCurrentTheme.
  ///
  /// In uk, this message translates to:
  /// **'Редагувати поточну'**
  String get editCurrentTheme;

  /// No description provided for @deleteCurrentTheme.
  ///
  /// In uk, this message translates to:
  /// **'Видалити поточну'**
  String get deleteCurrentTheme;

  /// No description provided for @themeNameLabel.
  ///
  /// In uk, this message translates to:
  /// **'Назва теми'**
  String get themeNameLabel;

  /// No description provided for @themeDark.
  ///
  /// In uk, this message translates to:
  /// **'Темна'**
  String get themeDark;

  /// No description provided for @themeLightMode.
  ///
  /// In uk, this message translates to:
  /// **'Світла'**
  String get themeLightMode;

  /// No description provided for @colorBackground.
  ///
  /// In uk, this message translates to:
  /// **'Фон'**
  String get colorBackground;

  /// No description provided for @colorSurface.
  ///
  /// In uk, this message translates to:
  /// **'Панелі'**
  String get colorSurface;

  /// No description provided for @colorSurfaceRaised.
  ///
  /// In uk, this message translates to:
  /// **'Поля й чипи'**
  String get colorSurfaceRaised;

  /// No description provided for @colorBorder.
  ///
  /// In uk, this message translates to:
  /// **'Рамки'**
  String get colorBorder;

  /// No description provided for @colorText.
  ///
  /// In uk, this message translates to:
  /// **'Текст'**
  String get colorText;

  /// No description provided for @colorTextMuted.
  ///
  /// In uk, this message translates to:
  /// **'Другорядний текст'**
  String get colorTextMuted;

  /// No description provided for @colorAccent.
  ///
  /// In uk, this message translates to:
  /// **'Акцент'**
  String get colorAccent;

  /// No description provided for @colorOnAccent.
  ///
  /// In uk, this message translates to:
  /// **'Текст на акценті'**
  String get colorOnAccent;

  /// No description provided for @statusConnected.
  ///
  /// In uk, this message translates to:
  /// **'Підключено'**
  String get statusConnected;

  /// No description provided for @statusReconnecting.
  ///
  /// In uk, this message translates to:
  /// **'Перепідключення'**
  String get statusReconnecting;

  /// No description provided for @reconnectAttempt.
  ///
  /// In uk, this message translates to:
  /// **'спроба {n} з {max}'**
  String reconnectAttempt(String n, String max);

  /// No description provided for @latencyMs.
  ///
  /// In uk, this message translates to:
  /// **'{n} мс'**
  String latencyMs(String n);

  /// No description provided for @statusError.
  ///
  /// In uk, this message translates to:
  /// **'Помилка'**
  String get statusError;

  /// No description provided for @radius.
  ///
  /// In uk, this message translates to:
  /// **'Заокруглення'**
  String get radius;

  /// No description provided for @textSize.
  ///
  /// In uk, this message translates to:
  /// **'Розмір тексту'**
  String get textSize;

  /// No description provided for @densityCompact.
  ///
  /// In uk, this message translates to:
  /// **'Компактно'**
  String get densityCompact;

  /// No description provided for @densityNormal.
  ///
  /// In uk, this message translates to:
  /// **'Звичайно'**
  String get densityNormal;

  /// No description provided for @densitySpacious.
  ///
  /// In uk, this message translates to:
  /// **'Просторо'**
  String get densitySpacious;

  /// No description provided for @motionFull.
  ///
  /// In uk, this message translates to:
  /// **'Анімації'**
  String get motionFull;

  /// No description provided for @motionEssential.
  ///
  /// In uk, this message translates to:
  /// **'Мінімум'**
  String get motionEssential;

  /// No description provided for @motionOff.
  ///
  /// In uk, this message translates to:
  /// **'Вимкнено'**
  String get motionOff;

  /// No description provided for @contrastBad.
  ///
  /// In uk, this message translates to:
  /// **'Погано читається:\n{problems}'**
  String contrastBad(String problems);

  /// No description provided for @contrastFine.
  ///
  /// In uk, this message translates to:
  /// **'Контраст тексту в нормі.'**
  String get contrastFine;

  /// No description provided for @saveAndApply.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти й застосувати'**
  String get saveAndApply;

  /// No description provided for @previewPcName.
  ///
  /// In uk, this message translates to:
  /// **'Офіс — Бухгалтерія'**
  String get previewPcName;

  /// No description provided for @contrastTextOnBackground.
  ///
  /// In uk, this message translates to:
  /// **'Текст на фоні'**
  String get contrastTextOnBackground;

  /// No description provided for @contrastTextOnSurface.
  ///
  /// In uk, this message translates to:
  /// **'Текст на панелі'**
  String get contrastTextOnSurface;

  /// No description provided for @contrastMutedOnSurface.
  ///
  /// In uk, this message translates to:
  /// **'Другорядний текст на панелі'**
  String get contrastMutedOnSurface;

  /// No description provided for @contrastOnAccent.
  ///
  /// In uk, this message translates to:
  /// **'Текст на кнопці акценту'**
  String get contrastOnAccent;

  /// No description provided for @contrastStatusConnected.
  ///
  /// In uk, this message translates to:
  /// **'Статус «підключено»'**
  String get contrastStatusConnected;

  /// No description provided for @contrastStatusError.
  ///
  /// In uk, this message translates to:
  /// **'Статус «помилка»'**
  String get contrastStatusError;

  /// No description provided for @contrastIssue.
  ///
  /// In uk, this message translates to:
  /// **'{label}: {ratio} : 1 (треба 4.5)'**
  String contrastIssue(String label, String ratio);

  /// No description provided for @fileTypeBackup.
  ///
  /// In uk, this message translates to:
  /// **'Бекап MHRD'**
  String get fileTypeBackup;

  /// No description provided for @fileTypeShare.
  ///
  /// In uk, this message translates to:
  /// **'Експорт MHRD'**
  String get fileTypeShare;

  /// No description provided for @fileTypeRdp.
  ///
  /// In uk, this message translates to:
  /// **'Файли RDP'**
  String get fileTypeRdp;

  /// No description provided for @fileTypeWireGuard.
  ///
  /// In uk, this message translates to:
  /// **'Конфігурація WireGuard'**
  String get fileTypeWireGuard;

  /// No description provided for @fileTypeTheme.
  ///
  /// In uk, this message translates to:
  /// **'Тема MHRD'**
  String get fileTypeTheme;

  /// No description provided for @portableTitle.
  ///
  /// In uk, this message translates to:
  /// **'Портативна MHRD'**
  String get portableTitle;

  /// No description provided for @portableCreateHint.
  ///
  /// In uk, this message translates to:
  /// **'Паролі й ключі зберігатимуться в зашифрованому файлі поруч із програмою. Придумайте майстер-пароль: без нього їх не відкрити й не відновити.'**
  String get portableCreateHint;

  /// No description provided for @portableUnlockHint.
  ///
  /// In uk, this message translates to:
  /// **'Введіть майстер-пароль.'**
  String get portableUnlockHint;

  /// No description provided for @portableImportHint.
  ///
  /// In uk, this message translates to:
  /// **'Щоб перенести ПК з іншої MHRD, зробіть там повний бекап, а тут відновіть його: Налаштування → Бекап.'**
  String get portableImportHint;

  /// No description provided for @portableCreate.
  ///
  /// In uk, this message translates to:
  /// **'Створити'**
  String get portableCreate;

  /// No description provided for @secretsFileBroken.
  ///
  /// In uk, this message translates to:
  /// **'Файл паролів пошкоджений або не від MHRD. Щоб почати з нуля, перейменуйте {path} (паролі доведеться ввести знову).'**
  String secretsFileBroken(String path);

  /// No description provided for @keyringFallbackTitle.
  ///
  /// In uk, this message translates to:
  /// **'Паролі MHRD'**
  String get keyringFallbackTitle;

  /// No description provided for @keyringFallbackCreateHint.
  ///
  /// In uk, this message translates to:
  /// **'Системного сховища паролів (GNOME Keyring, KWallet) немає, тож MHRD шифрує паролі й ключі сам — у файлі поруч зі своїми даними. Придумайте майстер-пароль: без нього їх не відкрити й не відновити.'**
  String get keyringFallbackCreateHint;

  /// No description provided for @keyringFallbackSection.
  ///
  /// In uk, this message translates to:
  /// **'Паролі'**
  String get keyringFallbackSection;

  /// No description provided for @keyringFallbackSectionHint.
  ///
  /// In uk, this message translates to:
  /// **'Системного сховища паролів немає: паролі й ключі зашифровані майстер-паролем, він же замінює PIN-код.'**
  String get keyringFallbackSectionHint;

  /// No description provided for @portableSection.
  ///
  /// In uk, this message translates to:
  /// **'Портативна версія'**
  String get portableSection;

  /// No description provided for @portableSectionHint.
  ///
  /// In uk, this message translates to:
  /// **'Дані — у теці mhrd-data поруч із програмою. Замість PIN-коду — майстер-пароль.'**
  String get portableSectionHint;

  /// No description provided for @masterPassword.
  ///
  /// In uk, this message translates to:
  /// **'Майстер-пароль'**
  String get masterPassword;

  /// No description provided for @masterPasswordRepeat.
  ///
  /// In uk, this message translates to:
  /// **'Повторіть майстер-пароль'**
  String get masterPasswordRepeat;

  /// No description provided for @masterPasswordNew.
  ///
  /// In uk, this message translates to:
  /// **'Новий майстер-пароль'**
  String get masterPasswordNew;

  /// No description provided for @masterPasswordTooShort.
  ///
  /// In uk, this message translates to:
  /// **'Щонайменше {min} символів.'**
  String masterPasswordTooShort(int min);

  /// No description provided for @masterPasswordMismatch.
  ///
  /// In uk, this message translates to:
  /// **'Паролі не збігаються.'**
  String get masterPasswordMismatch;

  /// No description provided for @masterPasswordWrong.
  ///
  /// In uk, this message translates to:
  /// **'Неправильний майстер-пароль.'**
  String get masterPasswordWrong;

  /// No description provided for @masterPasswordChange.
  ///
  /// In uk, this message translates to:
  /// **'Змінити майстер-пароль'**
  String get masterPasswordChange;

  /// No description provided for @masterPasswordChanged.
  ///
  /// In uk, this message translates to:
  /// **'Майстер-пароль змінено.'**
  String get masterPasswordChanged;

  /// No description provided for @createShortcut.
  ///
  /// In uk, this message translates to:
  /// **'Ярлик на робочому столі'**
  String get createShortcut;

  /// No description provided for @createShortcutAs.
  ///
  /// In uk, this message translates to:
  /// **'Ярлик: {name}'**
  String createShortcutAs(String name);

  /// No description provided for @shortcutCreated.
  ///
  /// In uk, this message translates to:
  /// **'Ярлик «{name}» — на робочому столі.'**
  String shortcutCreated(String name);

  /// No description provided for @shortcutFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося створити ярлик.'**
  String get shortcutFailed;

  /// No description provided for @useAllMonitorsHint.
  ///
  /// In uk, this message translates to:
  /// **'Вікно сеансу — на всіх моніторах одразу, розкладка — як на цьому ПК. Плашка — на основному моніторі.'**
  String get useAllMonitorsHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
