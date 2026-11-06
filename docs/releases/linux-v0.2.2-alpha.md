**Альфа-версія MHRD для Linux** — перша збірка для Linux. Debian 12+, Ubuntu 22.04+ (і Mint 21+), Arch/Manjaro; 64-бітні Intel/AMD.

**Встановити одною командою** (Debian, Ubuntu, Mint, Arch, Manjaro) — у терміналі:

```
curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
```

Команда сама поставить потрібні системні бібліотеки (попросить пароль для sudo), завантажить найновішу версію, перевірить контрольну суму й додасть MHRD у меню програм; з термінала — команда `mhrd`. Повторний запуск тієї ж команди — оновлення: ПК, налаштування й паролі лишаються. Видалити: та сама команда з `bash -s -- --uninstall` у кінці.

**Або вручну**
- `MHRD-0.2.2-alpha-x86_64.AppImage` — один файл: `chmod +x MHRD-*.AppImage`, потім запустити. Дані — у профілі користувача.
- `mhrd-0.2.2-alpha-linux-x64.tar.gz` — портативна: розпакувати й запустити `./mhrd`; дані й паролі (під майстер-паролем) — у теці `mhrd-data` поруч.

**Що вміє**
- Ті самі ПК, групи, акаунти, маршрути (WireGuard, проксі, RD Gateway), бекапи й PIN-блокування, що й у версії для Windows; бекап із Windows відновлюється тут.
- Сеанс у власному вікні (X11 і Wayland), «Усі монітори», звук і мікрофон (PulseAudio/PipeWire).
- Буфер обміну в обидва боки — текст і картинки.
- Паролі — у системному сховищі (GNOME Keyring, KWallet); де його немає — у зашифрованому файлі під майстер-паролем.
- Ярлик ПК (і окремого акаунта) на робочому столі — файл `.desktop`.
- Процес сеансу ізольовано: заборонено запуск інших програм (seccomp), його пам'ять недоступна іншим процесам.
- FreeRDP 3.33.0.

**Перевірка завантаженого:** `sha256sum -c SHA256SUMS-linux.txt` у теці із завантаженими файлами.

**Інші платформи**
- Windows: [MHRD 0.2.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.2.2) (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Android (бета): [MHRD 0.2.2 для Android](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.2.2-beta) (гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android))
- Код Linux-версії — гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux).

---

**MHRD for Linux — alpha.** Debian 12+, Ubuntu 22.04+/Mint 21+, Arch/Manjaro, x86_64.
Install or update with one command: `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash` (uninstall: append `-s -- --uninstall` after `bash`). Or download the AppImage (`chmod +x`, run) or the portable tar.gz.
Same PCs, groups, accounts, routes, backups and PIN lock as on Windows; a session window for X11 and Wayland, sound and microphone, two-way clipboard (text and images), system keyring with an encrypted fallback, desktop shortcuts, and a sandboxed session process. Other platforms: [Windows 0.2.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.2.2), [Android 0.2.2 beta](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.2.2-beta).
