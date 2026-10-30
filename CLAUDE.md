# MHRD — інструкції для Claude Code

MHRD (MacroHard Remote Desktop, робоча назва) — безкоштовний RDP-клієнт з відкритим кодом
(AGPLv3) для **Windows, Linux, macOS і Android**. Повна специфікація: [`docs/SPEC.md`](docs/SPEC.md).
Читай її перед будь-якою роботою над новою функцією.

Власник проєкту пише здебільшого на Python і не знає Dart/Flutter глибоко:
**пояснюй кроки детально, українською**, з готовими командами.

## Незмінні рішення

- **Чиста кімната.** Функції описуємо за поведінкою оригінального Microsoft Remote Desktop
  і відкритою документацією (MS-RDP*, формат `.rdp`). Ніколи не декомпілюй і не копіюй код,
  ресурси, іконки чи назви Microsoft. Назва в коді й пакетах — лише `mhrd`.
- **Стек:** Flutter (Dart) для всього UI й логіки; FreeRDP 3.x (C, Apache 2.0) як RDP-ядро
  (не Rust/IronRDP — рішення власника); тунелі — wireguard-go у режимі netstack (MIT),
  пізніше tsnet, OpenVPN 3 Core (AGPLv3), libopenconnect.
- **Кожен сеанс — окремий процес `mhrd-session`** (`native/session`), а не потік: збій FreeRDP
  не валить застосунок. Зв'язок — локальний канал + спільна пам'ять для кадрів; паролі лише
  через канал, ніколи в аргументах чи змінних середовища. Деталі — SPEC → «Архітектура».
- **Вбудовані тунелі без прав адміністратора:** FreeRDP завжди йде на `127.0.0.1:<порт>`,
  а менеджер тунелів пересилає трафік через тунель. Системний VPN не чіпаємо.
- **Ні iOS, ні власного сервера синхронізації.** Між пристроями — лише файл бекапу.
- **Секрети** (паролі, ключі) — тільки в системному сховищі (`SecretStore`), у бекапі
  (зашифрованому паролем) і ніде більше: не в SQLite, не в журналах, не в експорті для передачі.
- **Теми:** жодних кольорів чи розмірів у віджетах напряму — лише `context.mhrd.*`
  (`lib/theme/mhrd_theme.dart`). Типова тема «Графіт»; є «Світлий інструмент», «Нічний бурштин» (шрифт Exo 2),
  «Як у системі» і власні теми (`.mhrd-theme`).
- **Тексти інтерфейсу** — лише через переклади: `lib/l10n/app_uk.arb` (шаблон) і `app_en.arb`,
  у коді `context.l10n.ключ`. Новий текст = ключ в обох файлах (`test/l10n_test.dart` це перевіряє
  і ловить українські рядки в `lib/ui`). Логіка (`backup`, `storage`, `util`) не повертає текстів —
  лише коди помилок (`BackupError`, `InUseKind`, …); переклад кодів — `lib/l10n/l10n.dart`.

## Структура

```
lib/
  main.dart, app.dart          запуск, AppScope (repo + sessions), тема
  models/                      Connection, Credential, Group, Gateway, TunnelProfile, ProxyProfile, SshProfile, AppSettings
  storage/                     MhrdDatabase (SQLite, JSON-сутності), SecretStore, Repository (ChangeNotifier)
  backup/backup_service.dart   .rdpbackup v2 (Argon2id + AES-256-GCM), читання v1, експорт без секретів
  theme/mhrd_theme.dart        токени тем, вбудовані теми, контраст, (де)серіалізація
  util/                        розбір адрес, .rdp імпорт/експорт, WireGuard .conf
  sessions/session_manager.dart  каркас сеансів (RDP-ядро — етап 2)
  ui/                          головний екран, «Додати ПК», налаштування, редактор теми
test/                          юніт-тести логіки
docs/SPEC.md                   специфікація (джерело правди)
.github/workflows/build.yml    тести + збірка під 4 ОС у GitHub Actions
```

## Стан і пріоритети

- Етап 1 компілюється: `flutter analyze` чистий, `flutter test` проходить, збірки
  `flutter build windows` і `flutter build apk` працюють, вручну перевірено на Windows.
- **Порядок платформ:** спершу все робимо й перевіряємо на **Windows**, потім переносимо на
  **Android**. Mac у власника немає: Linux і macOS збирає лише GitHub Actions
  (теки `linux/`, `macos/` у репозиторії не тримаємо — CI створює їх сам).
- Середовище розробки (Windows): Flutter у `C:\src\flutter`, JDK 17 (Temurin), Android SDK у
  `%LOCALAPPDATA%\Android\Sdk`, VS Build Tools 2022 з C++ і **ATL** (без ATL не збирається
  `flutter_secure_storage_windows`). `sdkmanager` у новому SDK замінено утилітою `android`:
  пакети ставимо `android --no-metrics sdk install ndk/<версія>` (через `/`, не `;`).

## Модуль сеансу `mhrd-session` (етап 2)

- Код: `native/session/src` (C, FreeRDP 3 через vcpkg, статично — один .exe ~8 МБ).
  Залежності — `native/session/vcpkg.json` (з `builtin-baseline`).
- Збірка: `powershell -ExecutionPolicy Bypass -File native\session\build.ps1` → `native/session/out/mhrd-session.exe`.
  vcpkg — у `C:\src\vcpkg` (або `$env:VCPKG_ROOT`); перша збірка FreeRDP+OpenSSL ~30 хв, далі з кешу.
  `windows/CMakeLists.txt` кладе exe поруч із `mhrd.exe`; без нього «Підключитись» пояснює, що модуля немає.
- Після зміни C-коду: build.ps1, потім `flutter build windows` (закрийте запущений MHRD — інакше файли зайняті).
- Протокол змінюється одночасно в `proto.h` і `lib/sessions/session_protocol.dart` + тест у `test/session_test.dart`.
- `test/engine_smoke_test.dart` запускає справжній exe (без сервера RDP); пропускається, якщо exe немає.

## Відкриті задачі етапу 1

- [x] `LICENSE` — повний текст GNU AGPLv3 (https://www.gnu.org/licenses/agpl-3.0.txt).
- [x] Шрифти IBM Plex Sans/Mono, Manrope, Exo 2, JetBrains Mono (OFL, статичні 400/500/600) у
      `assets/fonts/`, ліцензії в `assets/fonts/licenses/` і в `LicenseRegistry` (`main.dart`).
      Будь-який новий шрифт — лише з кирилицею (Space Grotesk замінено на Exo 2 саме через це).
- [ ] macOS: у `macos/Runner/*.entitlements` додати `com.apple.security.network.client`
      (вихідні з'єднання) і доступ до Keychain для `flutter_secure_storage`.
- [ ] Android: збереження файлів через SAF (зараз на Android файли падають у теку документів
      застосунку). Уже зроблено: `INTERNET` у основному маніфесті, системний бекап вимкнено;
      `minSdk` = 24 (вимога Flutter і flutter_secure_storage 11).
- [ ] Linux: у README згадати залежність `libsecret-1-0` (сховище паролів).
- [ ] Іконка застосунку (своя, без символіки Microsoft).
- [x] Автобекап у вибрану теку (`lib/backup/auto_backup.dart`). Налаштування — у meta `autoBackup`
      (лише для цього пристрою, не в бекапі), пароль — `SecretStore`. На Android запис у теку
      запрацює разом із задачею SAF (нижче).
- [x] Wake-on-LAN: надсилання magic packet із меню ПК (`lib/util/wake_on_lan.dart`).
      Пропозиція «Розбудити?», коли ПК не відповідає, — разом із підключенням на етапі 2.
- [x] Тексти в ARB (`flutter gen-l10n`), українська й англійська, вибір мови в налаштуваннях.

## Етапи далі (деталі й критерії готовності — SPEC → «Етапи робіт»)

2. Процес `mhrd-session` над FreeRDP + плагін `native/host` + перше підключення (спершу Windows).
3. Екран сеансу: вкладки, повний екран, зміна розміру, перепідключення.
4. Вбудований WireGuard (wireguard-go netstack) + менеджер тунелів і переадресація портів.
5. Android: збірка FreeRDP і Go-модулів через NDK, сенсорне керування, фонова служба.
6. Проксі, SSH, RD Gateway, буфер обміну, папки, звук, мікрофон.
7. Tailscale/Headscale, OpenVPN, OpenConnect.

## Правила роботи

- Нова логіка → тест у `test/`. `flutter analyze` і `flutter test` мають бути чистими перед комітом.
- Не логувати секрети. Не зберігати секрети поза `SecretStore`.
- Зміни формату бази → крок міграції в `MhrdDatabase._migrate` і підвищення `schemaVersion`.
- Зміни формату бекапу → підвищити `schemaVersion` у бекапі й лишити читання старих версій.
- Спершу питай власника, якщо рішення суперечить SPEC.md або цьому файлу.
