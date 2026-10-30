# MHRD — MacroHard Remote Desktop

Легкий безкоштовний RDP-клієнт з відкритим кодом для Windows, Linux, macOS і Android:
усі ПК і облікові записи в одному місці, кілька акаунтів на один ПК, вбудовані тунелі
(WireGuard, OpenVPN та інші) без прав адміністратора, зашифрований бекап і власні теми.

> Статус: **етап 1 — каркас.** Список ПК, облікові записи, групи, шлюзи, імпорт `.rdp`
> і WireGuard `.conf`, бекап, теми. Самого RDP-підключення ще немає (етап 2).

## Як зібрати

1. Встановіть [Flutter](https://docs.flutter.dev/get-started/install) (stable, 3.35 або новіший).
2. У теці проєкту:
   ```
   flutter create --project-name mhrd --org ua.mhrd --platforms=windows,linux,macos,android .
   flutter pub get
   flutter run
   ```
3. Linux: потрібні пакети `libgtk-3-dev libsecret-1-dev` для збірки і `libsecret-1-0` для роботи.

Без встановлення нічого на ПК: завантажте код у репозиторій GitHub — збірки для всіх
чотирьох ОС з'являться у вкладці **Actions** → останній запуск → **Artifacts**.

## Документи

- [`docs/SPEC.md`](docs/SPEC.md) — специфікація: функції, архітектура, модель даних, тест-план, етапи.
- [`CLAUDE.md`](CLAUDE.md) — інструкції для Claude Code.

## Ліцензія

GNU AGPLv3. MHRD не пов'язаний з Microsoft; «Remote Desktop Protocol» — протокол, описаний
у відкритій документації Microsoft.
