# MHRD — MacroHard Remote Desktop

A lightweight, free and open-source RDP client: all your PCs and accounts in one place, several
accounts per PC, every remote desktop in its own window, an encrypted backup and custom themes.
Protocol core — [FreeRDP 3](https://github.com/FreeRDP/FreeRDP), UI — Flutter.

> **Status:** Windows — stable releases; Linux — alpha; Android — stable releases.

**[Українською ↓](#українською)**

## Download and install

All files are in [**Releases**](https://github.com/SemkoArtem/mhrd/releases). No admin rights needed.

**Windows 10/11 (x64)** — in PowerShell (installs or updates to the latest version, verifies the checksum):

```powershell
irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex
```

Or manually: the installer `mhrd-setup-…-x64.exe` or the portable `mhrd-…-x64-portable.zip`. The app is not
code-signed yet, so SmartScreen may warn you: "More info" → "Run anyway".

**Linux (x64)** — Debian 12+, Ubuntu 22.04+, Mint 21+, Fedora, openSUSE, Arch, Manjaro — in a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
```

The same command updates; to remove: `… | bash -s -- --uninstall`. Or manually: `.deb`, `.rpm`, AppImage or
the portable `tar.gz` from the [Linux release](https://github.com/SemkoArtem/mhrd/releases?q=linux).

**Android 7+ (64-bit)** — the `.apk` file from the [Android release](https://github.com/SemkoArtem/mhrd/releases?q=android):
download it on the phone and open it.

**Portable Windows version** (can live on a USB stick): unzip anywhere. All data is in the `mhrd-data`
folder next to `mhrd.exe`; passwords and keys are in a file encrypted with a master password
(Argon2id + AES-256-GCM) instead of the Windows credential store. To move PCs from an installed MHRD:
make a full backup there, then "Restore" here. Without the `portable.txt` file next to `mhrd.exe` the app
works as a regular one, with data in the Windows profile.

## What it can do (Windows)

**Connections and session windows**
- Every session is a separate process and a separate window: a crash of one does not affect the others,
  and closing the main window does not drop connections.
- Pixel-exact picture that respects Windows scaling (HiDPI); the remote resolution follows the window size.
  On a slow connection full sharpness can be turned off: 2–4× less traffic on 150–200 % displays.
- "All monitors": the remote desktop on all monitors at once, with the same layout.
- "Keep the screen on": while a session window is open, Windows does not turn off the screen or sleep.
- Full screen (Ctrl+Alt+Enter or a button) with a hideable bar: pin, on-screen keyboard, minimize,
  windowed, disconnect. The bar can be dragged to any edge and shortened to icons only — MHRD remembers it.
- Server certificate check with remembered trust; clear disconnect reasons and "Connect again".
- Automatic reconnect when the link drops: "attempt 2 of 5", "Cancel".
- On the bar: latency to the PC across the whole route, and Ctrl+Alt+Del.
- Touch screen: tap — click, long press and two-finger tap — right click, two fingers — scroll,
  pinch — zoom.
- Screen templates: standard resolutions (including portrait) and your own.
- H.264 (AVC444) through the decoder built into Windows — less traffic and smoother video.

**Routes to the PC**
- Built-in **WireGuard** (import a `.conf`): no admin rights or driver, does not interfere with
  another VPN.
- **Proxy** SOCKS5 and HTTP, **RD Gateway**.
- Tunnel and proxy status in the left panel: tunnels are checked at startup, when a profile changes and
  by a button; proxies also every 5 minutes.
- Tailscale and other VPNs: turn them on in the system and choose the "Direct" route.

**Devices**
- Clipboard both ways: text, images and **files**.
- Shared folders with access modes: full, "add without deleting", read-only.
- Sound (here, on the remote PC or off) and microphone.
  The microphone does not work in an administrative session (`/admin`) — that is how Windows itself behaves.

**PC list and data**
- PCs, accounts (one account — in several PCs), groups, gateways; search and quick connect.
- `.rdp` import and export, Wake-on-LAN.
- Thumbnails of the last session or your own PC picture; select several PCs, drag them into groups.
- "Test connection" in PC settings; "Recent" on the taskbar icon; a PC shortcut on the desktop
  (connects right away).
- Lock MHRD with a PIN and fingerprint / Windows Hello.
- Passwords — only in the system store (Windows DPAPI), never in the database or logs.
- Encrypted backup (Argon2id + AES-256-GCM) and auto-backup into a chosen folder.
- Themes and a theme editor, Ukrainian and English UI.
- Session log without passwords (last 7 days) — for diagnostics.

## Roadmap

- Linux — from alpha to stable releases; later macOS.

The full list and readiness criteria are in [`docs/SPEC.md`](docs/SPEC.md) → "Етапи робіт" (Ukrainian).

## How to build (Windows)

You need:
- [Flutter](https://docs.flutter.dev/get-started/install) stable (3.35 or newer);
- Visual Studio 2022 Build Tools with "Desktop development with C++" and the **ATL** component;
- [vcpkg](https://github.com/microsoft/vcpkg) (a full clone) — in `C:\src\vcpkg` or in `VCPKG_ROOT`;
- [Go](https://go.dev/dl/) — for the tunnel module.

```powershell
# 1. Session module mhrd-session (FreeRDP, OpenSSL, SDL3 — static; ~30 min the first time)
powershell -ExecutionPolicy Bypass -File native\session\build.ps1

# 2. Tunnel module mhrd-tunnel (WireGuard)
powershell -ExecutionPolicy Bypass -File native\tunnels\build.ps1

# 3. The app (puts mhrd-session.exe and mhrd-tunnel.exe next to mhrd.exe)
flutter pub get
flutter build windows --release
```

The finished app is in `build\windows\x64\runner\Release\`.

Without building on your PC: **Actions** → **build** → **Run workflow** — builds for Windows,
Linux, macOS and Android appear in that run → **Artifacts**. On every push GitHub Actions
only runs code analysis and tests.

**Release:** tag `vX.Y.Z` (the same version in `pubspec.yaml`) and notes in `docs/releases/vX.Y.Z.md` →
the **release** workflow builds the installer (`windows/installer/mhrd.iss`, Inno Setup) and the zip and
creates a GitHub Release.

## Security: good to know

- **Verify the download:** every release has `SHA256SUMS.txt`. In PowerShell:
  `Get-FileHash .\mhrd-setup-…-x64.exe -Algorithm SHA256` — it must match the line in the file.
- **Clipboard with files:** while a session is open and the clipboard is on for that PC, the remote PC
  can read files you copied here, even if you did not paste them there (the Microsoft client behaves
  the same way). For a PC you do not trust, turn the clipboard off in the PC settings.
- **Shared folders** in the "add without changes" and "read-only" modes let the server into neither
  NTFS alternate streams (`file:stream`) nor through links or junction folders inside the folder.
- **The MHRD PIN** protects against a person at the screen: after 3 mistakes — a growing pause. It does not
  protect against someone already signed in to your Windows account — passwords are in the Windows store.
- **Isolation:** every session is a separate process with Windows restrictions: it cannot start other
  programs, load a library from a network folder or a font not from the system. This narrows the risk
  but does not remove it: a FreeRDP bug exploited by a malicious server would still have access to your
  files. Connect to servers you trust; a full sandbox (AppContainer) is planned.
- **Portable version:** the master password is not stored or recoverable anywhere — if you forget it,
  passwords and keys have to be entered again (PCs, groups and settings stay).

Found a vulnerability? Write in [Issues](https://github.com/SemkoArtem/mhrd/issues) or to the
repository owner directly if the details should not be public.

## How it works

```
lib/               Flutter: PC list, settings, backup, themes, session management
native/session/    mhrd-session (C): FreeRDP 3 + its own SDL3 window, clipboard, folders
native/tunnels/    mhrd-tunnel (Go): WireGuard (netstack)
docs/SPEC.md       specification: features, architecture, data model, test plan, stages
```

The app starts an `mhrd-session` process for every connection and talks to it with short binary
messages over stdin/stdout. The password goes only through this channel — never into process
arguments or environment variables.

## License

[GNU AGPLv3](LICENSE). MHRD is not affiliated with Microsoft; the Remote Desktop Protocol is described in
Microsoft's open documentation. Bar icons — Material Icons (Apache 2.0), fonts — SIL OFL
(see `assets/fonts/licenses/`).

---

## Українською

Легкий безкоштовний RDP-клієнт з відкритим кодом: усі ПК і облікові записи в одному місці,
кілька акаунтів на один ПК, кожен віддалений робочий стіл — в окремому вікні, зашифрований
бекап і власні теми. Ядро протоколу — [FreeRDP 3](https://github.com/FreeRDP/FreeRDP),
інтерфейс — Flutter.

> **Статус:** Windows — стабільні випуски; Linux — альфа; Android — стабільні випуски.

### Завантажити й встановити

Усі файли — у [**Releases**](https://github.com/SemkoArtem/mhrd/releases). Права адміністратора не потрібні.

**Windows 10/11 (x64)** — у PowerShell (встановлює або оновлює до останньої версії, перевіряє контрольну суму):

```powershell
irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex
```

Або вручну: інсталятор `mhrd-setup-…-x64.exe` чи портативна `mhrd-…-x64-portable.zip`. Програма ще не
підписана сертифікатом, тож SmartScreen може попередити: «Докладніше» → «Однаково запустити».

**Linux (x64)** — Debian 12+, Ubuntu 22.04+, Mint 21+, Fedora, openSUSE, Arch, Manjaro — у терміналі:

```bash
curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
```

Та сама команда — оновлення; видалити: `… | bash -s -- --uninstall`. Або вручну: `.deb`, `.rpm`, AppImage чи
портативний `tar.gz` з [випуску для Linux](https://github.com/SemkoArtem/mhrd/releases?q=linux).

**Android 7+ (64-біт)** — файл `.apk` з [випуску для Android](https://github.com/SemkoArtem/mhrd/releases?q=android):
завантажте на телефоні й відкрийте.

**Портативна версія Windows** (можна носити на флешці): розпакуйте zip куди завгодно. Усі дані — у теці
`mhrd-data` поруч із `mhrd.exe`, паролі й ключі — у зашифрованому файлі під майстер-паролем
(Argon2id + AES-256-GCM), а не в сховищі Windows. Перенести ПК з установленої MHRD: там —
повний бекап, тут — «Відновити». Без файлу `portable.txt` поруч із `mhrd.exe` програма працює як
звичайна, з даними в профілі Windows.

### Що вже вміє (Windows)

**Підключення й вікна сеансів**
- Кожен сеанс — окремий процес і окреме вікно: збій одного не зачіпає інші, а закриття
  головного вікна не обриває підключень.
- Картинка піксель у піксель з урахуванням масштабу Windows (HiDPI), роздільність віддаленого
  екрана підлаштовується під розмір вікна. На повільному з'єднанні повну чіткість можна вимкнути:
  на екранах 150–200 % трафіку в 2–4 рази менше.
- «Усі монітори»: віддалений робочий стіл на всіх моніторах одразу, з тією ж розкладкою.
- «Не вимикати екран»: поки відкрите вікно сеансу, Windows не гасить екран і не засинає.
- Повний екран (Ctrl+Alt+Enter або кнопка) з плашкою, що ховається: закріпити, екранна
  клавіатура, згорнути, у вікно, відключитись. Плашку можна перетягнути до будь-якого краю
  і вкоротити до самих піктограм — MHRD запам'ятає.
- Перевірка сертифіката сервера з запам'ятовуванням довіри; зрозумілі причини відключення
  й «Підключитись знову».
- Автоматичне перепідключення, якщо зв'язок обірвався: «спроба 2 з 5», «Скасувати».
- На плашці — затримка до ПК через увесь маршрут і Ctrl+Alt+Del.
- Сенсорний екран: дотик — клік, довге натискання і дотик двома пальцями — правий клік,
  два пальці — гортати, щипок — збільшити.
- Шаблони екрана: стандартні роздільності (зокрема вертикальні) і свої.
- H.264 (AVC444) через вбудований у Windows декодер — менше трафіку й плавніше відео.

**Маршрути до ПК**
- Вбудований **WireGuard** (імпорт `.conf`): без прав адміністратора й драйвера, не заважає
  іншому VPN.
- **Проксі** SOCKS5 і HTTP, **RD Gateway**.
- Стан тунелів і проксі в лівій панелі: тунелі перевіряються при запуску, при зміні профілю й
  кнопкою, проксі — ще й кожні 5 хв.
- Tailscale та інші VPN: увімкніть їх у системі й виберіть маршрут «Напряму».

**Пристрої**
- Буфер обміну в обидва боки: текст, зображення і **файли**.
- Спільні папки з режимами доступу: повний, «додавати без видалення», лише читання.
- Звук (тут, на віддаленому ПК або вимкнено) і мікрофон.
  Мікрофон не працює в адміністративному сеансі (`/admin`) — так поводиться сама Windows.

**Список ПК і дані**
- ПК, облікові записи (один акаунт — у кількох ПК), групи, шлюзи; пошук і швидке підключення.
- Імпорт і експорт `.rdp`, Wake-on-LAN.
- Мініатюри останнього сеансу або своя картинка ПК; виділення кількох ПК, перетягування в групи.
- «Перевірити з'єднання» в налаштуваннях ПК; «Недавні» на значку в панелі завдань; ярлик ПК
  на робочому столі (підключає одразу).
- Блокування MHRD PIN-кодом і відбитком / Windows Hello.
- Паролі — лише в системному сховищі (Windows DPAPI), ніколи в базі чи журналах.
- Зашифрований бекап (Argon2id + AES-256-GCM) і автобекап у вибрану теку.
- Теми й редактор тем, українська та англійська мови.
- Журнал сеансів без паролів (останні 7 днів) — для діагностики.

### У планах

- Linux — зі статусу альфи до стабільних випусків; згодом macOS.

Повний перелік і критерії готовності — у [`docs/SPEC.md`](docs/SPEC.md) → «Етапи робіт».

### Як зібрати (Windows)

Потрібно:
- [Flutter](https://docs.flutter.dev/get-started/install) stable (3.35 або новіший);
- Visual Studio 2022 Build Tools з «Desktop development with C++» і компонентом **ATL**;
- [vcpkg](https://github.com/microsoft/vcpkg) (повний клон) — у `C:\src\vcpkg` або в `VCPKG_ROOT`;
- [Go](https://go.dev/dl/) — для модуля тунелів.

```powershell
# 1. Модуль сеансу mhrd-session (FreeRDP, OpenSSL, SDL3 — статично; перший раз ~30 хв)
powershell -ExecutionPolicy Bypass -File native\session\build.ps1

# 2. Модуль тунелів mhrd-tunnel (WireGuard)
powershell -ExecutionPolicy Bypass -File native\tunnels\build.ps1

# 3. Застосунок (кладе mhrd-session.exe і mhrd-tunnel.exe поруч із mhrd.exe)
flutter pub get
flutter build windows --release
```

Готова програма — у `build\windows\x64\runner\Release\`.

Без збирання на своєму ПК: **Actions** → **build** → **Run workflow** — збірки для Windows,
Linux, macOS і Android з'являться в цьому запуску → **Artifacts**. На кожен push GitHub Actions
лише проганяє аналіз коду й тести.

**Випуск:** тег `vX.Y.Z` (та сама версія в `pubspec.yaml`) і нотатки в `docs/releases/vX.Y.Z.md` →
workflow **release** збирає інсталятор (`windows/installer/mhrd.iss`, Inno Setup) і zip та
створює GitHub Release.

### Безпека: що варто знати

- **Перевірити завантажене:** до кожного релізу додано `SHA256SUMS.txt`. У PowerShell:
  `Get-FileHash .\mhrd-setup-…-x64.exe -Algorithm SHA256` — має збігтися з рядком у файлі.
- **Буфер обміну з файлами:** поки сеанс відкритий і буфер обміну для ПК увімкнено, віддалений ПК
  може прочитати файли, які ви скопіювали тут, навіть якщо ви їх там не вставляли (клієнт Microsoft
  поводиться так само). Для ПК, якому не довіряєте, вимкніть буфер обміну в налаштуваннях ПК.
- **Спільні папки** в режимах «додавати без змін» і «лише читання» не пускають сервер ні в
  альтернативні потоки NTFS (`файл:потік`), ні крізь посилання чи junction-теки всередині папки.
- **PIN-код MHRD** захищає від людини біля екрана: після 3 помилок — зростаюча пауза. Від того, хто
  вже увійшов у ваш обліковий запис Windows, він не захищає — паролі лежать у сховищі Windows.
- **Ізоляція:** кожен сеанс — окремий процес з обмеженнями Windows: він не може запускати інші
  програми, завантажити бібліотеку з мережевої теки чи шрифт не із системи. Це звужує, але не
  прибирає ризик: помилка у FreeRDP, якою скористався зловмисний сервер, усе ще мала б доступ до
  ваших файлів. Підключайтесь до серверів, яким довіряєте; повна пісочниця (AppContainer) — у
  планах.
- **Портативна версія:** майстер-пароль ніде не зберігається і не відновлюється — забули його,
  тоді паролі й ключі доведеться ввести заново (ПК, групи й налаштування лишаються).

Знайшли вразливість — напишіть у [Issues](https://github.com/SemkoArtem/mhrd/issues) або
власнику репозиторію напряму, якщо деталі не варто публікувати.

### Як влаштовано

```
lib/               Flutter: список ПК, налаштування, бекап, теми, керування сеансами
native/session/    mhrd-session (C): FreeRDP 3 + власне вікно на SDL3, буфер обміну, папки
native/tunnels/    mhrd-tunnel (Go): WireGuard (netstack)
docs/SPEC.md       специфікація: функції, архітектура, модель даних, тест-план, етапи
```

Застосунок запускає для кожного підключення процес `mhrd-session` і спілкується з ним
короткими двійковими повідомленнями через stdin/stdout. Пароль іде лише цим каналом —
ніколи в аргументи процесу чи змінні середовища.

### Ліцензія

[GNU AGPLv3](LICENSE). MHRD не пов'язаний з Microsoft; Remote Desktop Protocol описаний у
відкритій документації Microsoft. Піктограми плашки — Material Icons (Apache 2.0), шрифти —
SIL OFL (див. `assets/fonts/licenses/`).
