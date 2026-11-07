**MHRD 0.2.3 для Linux (альфа).** Debian 12+, Ubuntu 22.04+ (і Mint 21+), Fedora, openSUSE, Arch/Manjaro; 64-бітні Intel/AMD.

**Встановити або оновити одною командою** — у терміналі:

```
curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
```

Команда поставить потрібні системні бібліотеки (apt, dnf, zypper чи pacman — попросить пароль для sudo), завантажить найновішу версію, перевірить контрольну суму й додасть MHRD у меню програм. Повторний запуск — оновлення: ПК, налаштування й паролі лишаються. Видалити: та сама команда з `bash -s -- --uninstall` у кінці.

**Або пакетом**
- `mhrd-0.2.3-alpha-amd64.deb` — Debian, Ubuntu, Mint: відкрити файл (або `sudo apt install ./mhrd-0.2.3-alpha-amd64.deb`).
- `mhrd-0.2.3-alpha.x86_64.rpm` — Fedora (`sudo dnf install ./mhrd-0.2.3-alpha.x86_64.rpm`), openSUSE (`sudo zypper install ./mhrd-0.2.3-alpha.x86_64.rpm`).
- `MHRD-0.2.3-alpha-x86_64.AppImage` — один файл для будь-якого дистрибутива: `chmod +x`, потім запустити.
- `mhrd-0.2.3-alpha-linux-x64.tar.gz` — портативна: розпакувати й запустити `./mhrd`; дані — у теці `mhrd-data` поруч.

**Нове**
- **H.264.** Сеанс іде відеокодеком H.264 (AVC420/AVC444), як на Windows: менше трафіку й затримок, особливо через WireGuard чи мобільний інтернет.
- **Файли через буфер обміну в обидва боки.** Скопіювали файли чи теки у файловому менеджері — «Вставити» на ПК; скопіювали на ПК — «Вставити» у файловому менеджері (файли завантажуються, щойно ви перейшли з вікна сеансу в іншу програму; великі — можна вставити ще раз, коли завантажаться).
- **Налаштування нових ПК** (Налаштування → «Нові ПК»): маршрут, акаунти, екран, звук, буфер обміну — один раз для всіх нових ПК.
- **Пакети .deb і .rpm**, а команда встановлення тепер працює й на Fedora та openSUSE.

**Покращено**
- Буфер обміну оновлюється одразу, а не лише тоді, коли повертаєтесь у вікно сеансу.
- «Усі монітори» на X11 бачать кожен монітор окремо.
- Вікно сеансу на Wayland у GNOME — з рамкою й заголовком.
- Команда встановлення на застарілій системі пояснює, чому не ставить, замість незрозумілої помилки під час запуску.

**Перевірка завантаженого:** `sha256sum -c SHA256SUMS-linux.txt --ignore-missing` у теці із завантаженими файлами.

**Інші платформи**
- Windows: [MHRD 0.3.0](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.0) (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Android (бета): [MHRD 0.2.2 для Android](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.2.2-beta) (гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android))
- Код Linux-версії — гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux).

---

**MHRD 0.2.3 for Linux — alpha.** Debian 12+, Ubuntu 22.04+/Mint 21+, Fedora, openSUSE, Arch/Manjaro, x86_64.
Install or update: `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash`, or use the .deb / .rpm / AppImage / portable tar.gz.
**New:** H.264 video (AVC420/AVC444); files and folders through the clipboard both ways; settings for new PCs; .deb and .rpm packages; the installer supports Fedora and openSUSE.
**Improved:** the clipboard updates immediately; "All monitors" sees each monitor on X11; the session window has a frame on GNOME Wayland; the installer explains when the system is too old.
Other platforms: [Windows 0.3.0](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.0), [Android 0.2.2 beta](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.2.2-beta).
