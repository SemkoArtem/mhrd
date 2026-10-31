# MHRD — MacroHard Remote Desktop

Легкий безкоштовний RDP-клієнт з відкритим кодом: усі ПК і облікові записи в одному місці,
кілька акаунтів на один ПК, кожен віддалений робочий стіл — в окремому вікні, зашифрований
бекап і власні теми. Ядро протоколу — [FreeRDP 3](https://github.com/FreeRDP/FreeRDP),
інтерфейс — Flutter.

> **Статус: робочий прототип для Windows.** Підключення, буфер обміну, звук, мікрофон і
> спільні папки працюють і перевірені на реальному сервері. Далі — доробка решти пунктів,
> потім Android і Linux.

## Що вже вміє (Windows)

**Підключення й вікна сеансів**
- Кожен сеанс — окремий процес і окреме вікно: збій одного не зачіпає інші, а закриття
  головного вікна не обриває підключень.
- Картинка піксель у піксель з урахуванням масштабу Windows (HiDPI), роздільність віддаленого
  екрана підлаштовується під розмір вікна.
- Повний екран (Ctrl+Alt+Enter або кнопка) з плашкою, що ховається: закріпити, екранна
  клавіатура, згорнути, у вікно, відключитись.
- Перевірка сертифіката сервера з запам'ятовуванням довіри; зрозумілі причини відключення
  й «Підключитись знову».

**Пристрої**
- Буфер обміну в обидва боки: текст, зображення і **файли**.
- Спільні папки з режимами доступу: повний, «додавати без видалення», лише читання.
- Звук (тут, на віддаленому ПК або вимкнено) і мікрофон.
  Мікрофон не працює в адміністративному сеансі (`/admin`) — так поводиться сама Windows.

**Список ПК і дані**
- ПК, облікові записи (один акаунт — у кількох ПК), групи, шлюзи; пошук і швидке підключення.
- Імпорт і експорт `.rdp`, Wake-on-LAN.
- Паролі — лише в системному сховищі (Windows DPAPI), ніколи в базі чи журналах.
- Зашифрований бекап (Argon2id + AES-256-GCM) і автобекап у вибрану теку.
- Теми й редактор тем, українська та англійська мови.
- Журнал сеансів без паролів (останні 7 днів) — для діагностики.

## У планах

- Автоматичне перепідключення після обриву мережі, H.264.
- Вбудовані тунелі без прав адміністратора: WireGuard, далі OpenVPN, Tailscale/Headscale.
- Проксі, SSH-тунель, RD Gateway.
- **Android і Linux**, згодом macOS.

Повний перелік і критерії готовності — у [`docs/SPEC.md`](docs/SPEC.md) → «Етапи робіт».

## Як зібрати (Windows)

Потрібно:
- [Flutter](https://docs.flutter.dev/get-started/install) stable (3.35 або новіший);
- Visual Studio 2022 Build Tools з «Desktop development with C++» і компонентом **ATL**;
- [vcpkg](https://github.com/microsoft/vcpkg) (повний клон) — у `C:\src\vcpkg` або в `VCPKG_ROOT`.

```powershell
# 1. Модуль сеансу mhrd-session (FreeRDP, OpenSSL, SDL3 — статично; перший раз ~30 хв)
powershell -ExecutionPolicy Bypass -File native\session\build.ps1

# 2. Застосунок (кладе mhrd-session.exe поруч із mhrd.exe)
flutter pub get
flutter build windows --release
```

Готова програма — у `build\windows\x64\runner\Release\`.

Без збирання на своєму ПК: **Actions** → **build** → **Run workflow** — збірки для Windows,
Linux, macOS і Android з'являться в цьому запуску → **Artifacts**. На кожен push GitHub Actions
лише проганяє аналіз коду й тести.

## Як влаштовано

```
lib/               Flutter: список ПК, налаштування, бекап, теми, керування сеансами
native/session/    mhrd-session (C): FreeRDP 3 + власне вікно на SDL3, буфер обміну, папки
docs/SPEC.md       специфікація: функції, архітектура, модель даних, тест-план, етапи
```

Застосунок запускає для кожного підключення процес `mhrd-session` і спілкується з ним
короткими двійковими повідомленнями через stdin/stdout. Пароль іде лише цим каналом —
ніколи в аргументи процесу чи змінні середовища.

## Ліцензія

[GNU AGPLv3](LICENSE). MHRD не пов'язаний з Microsoft; Remote Desktop Protocol описаний у
відкритій документації Microsoft. Піктограми плашки — Material Icons (Apache 2.0), шрифти —
SIL OFL (див. `assets/fonts/licenses/`).

---

## English

**MHRD** is a free, open-source RDP client built on FreeRDP 3 and Flutter. Every remote desktop
opens in its own window and process. Already working on Windows: connections with certificate
pinning, HiDPI-exact rendering with dynamic resolution, full screen with a hideable bar,
clipboard (text, images, files) both ways, shared folders with access modes (full /
add-only / read-only), sound and microphone, an encrypted backup, themes, Ukrainian and
English UI. Android and Linux ports come next. License: AGPLv3.
