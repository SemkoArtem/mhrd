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
  через тонку обгортку `native/rdp_bridge` і `dart:ffi`; тунелі — wireguard-go у режимі
  netstack (MIT), пізніше tsnet, OpenVPN 3 Core (AGPLv3), libopenconnect.
- **Вбудовані тунелі без прав адміністратора:** FreeRDP завжди йде на `127.0.0.1:<порт>`,
  а менеджер тунелів пересилає трафік через тунель. Системний VPN не чіпаємо.
- **Ні iOS, ні власного сервера синхронізації.** Між пристроями — лише файл бекапу.
- **Секрети** (паролі, ключі) — тільки в системному сховищі (`SecretStore`), у бекапі
  (зашифрованому паролем) і ніде більше: не в SQLite, не в журналах, не в експорті для передачі.
- **Теми:** жодних кольорів чи розмірів у віджетах напряму — лише `context.mhrd.*`
  (`lib/theme/mhrd_theme.dart`). Типова тема «Графіт»; є «Світлий інструмент», «Нічний бурштин»,
  «Як у системі» і власні теми (`.mhrd-theme`).
- **Тексти інтерфейсу** — українською (пізніше винесемо в ARB і додамо англійську).

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

## Відкриті задачі етапу 1

- [x] `LICENSE` — повний текст GNU AGPLv3 (https://www.gnu.org/licenses/agpl-3.0.txt).
- [x] Шрифти IBM Plex Sans/Mono, Manrope, JetBrains Mono (OFL, статичні 400/500/600) у
      `assets/fonts/`, ліцензії в `assets/fonts/licenses/` і в `LicenseRegistry` (`main.dart`).
- [ ] Space Grotesk (тема «Нічний бурштин») **не має кирилиці** — потрібна заміна, вирішує власник.
- [ ] macOS: у `macos/Runner/*.entitlements` додати `com.apple.security.network.client`
      (вихідні з'єднання) і доступ до Keychain для `flutter_secure_storage`.
- [ ] Android: `minSdk` не нижче 23, дозвіл `INTERNET`; збереження файлів через SAF
      (зараз на Android файли падають у теку документів застосунку).
- [ ] Linux: у README згадати залежність `libsecret-1-0` (сховище паролів).
- [ ] Іконка застосунку (своя, без символіки Microsoft).
- [ ] Автобекап у вибрану теку (SPEC → «Безпека, бекап і відновлення»).
- [ ] Wake-on-LAN: надсилання magic packet із меню ПК.
- [ ] Винести тексти в ARB (`flutter gen-l10n`), додати англійську.

## Етапи далі (деталі й критерії готовності — SPEC → «Етапи робіт»)

2. `native/rdp_bridge` над FreeRDP + перше підключення на десктопах.
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
