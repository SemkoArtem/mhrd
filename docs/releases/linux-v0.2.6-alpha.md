**MHRD 0.2.6 для Linux (альфа).** Debian 12+, Ubuntu 22.04+ (і Mint 21+), Fedora, openSUSE, Arch/Manjaro; 64-бітні Intel/AMD.

**Встановити або оновити одною командою** — у терміналі:

```
curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
```

Команда поставить потрібні системні бібліотеки (apt, dnf, zypper чи pacman — попросить пароль для sudo), завантажить найновішу версію, перевірить контрольну суму й додасть MHRD у меню програм. Повторний запуск — оновлення: ПК, налаштування й паролі лишаються. Видалити: та сама команда з `bash -s -- --uninstall` у кінці.

**Або пакетом**
- `mhrd-0.2.6-alpha-amd64.deb` — Debian, Ubuntu, Mint: відкрити файл (або `sudo apt install ./mhrd-0.2.6-alpha-amd64.deb`).
- `mhrd-0.2.6-alpha.x86_64.rpm` — Fedora (`sudo dnf install ./mhrd-0.2.6-alpha.x86_64.rpm`), openSUSE (`sudo zypper install ./mhrd-0.2.6-alpha.x86_64.rpm`).
- `MHRD-0.2.6-alpha-x86_64.AppImage` — один файл для будь-якого дистрибутива: `chmod +x`, потім запустити.
- `mhrd-0.2.6-alpha-linux-x64.tar.gz` — портативна: розпакувати й запустити `./mhrd`; дані — у теці `mhrd-data` поруч.

**Виправлено**
- **Перетягування ПК у групу на ноутбуках із сенсорним екраном** спрацьовує щоразу: мишею чи тачпадом — одразу, пальцем — після короткого утримання картки. Раніше, коли чергувались миша й палець, перетягування могло спрацьовувати через раз.

**Перевірка завантаженого:** `sha256sum -c SHA256SUMS-linux.txt --ignore-missing` у теці із завантаженими файлами.

**Інші платформи**
- Windows: [MHRD 0.3.4](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.4) — `irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex` (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Android: [MHRD 0.3.4 для Android](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.3.4) — тепер стабільна версія (гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android))
- Код Linux-версії — гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux).

---

**MHRD 0.2.6 for Linux — alpha.** Install or update: `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash`, or use the .deb / .rpm / AppImage / portable tar.gz.
**Fixed:** dragging a PC into a group on touchscreen laptops works every time — immediately with a mouse or touchpad, after a short hold with a finger.
Other platforms: [Windows 0.3.4](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.4), [Android 0.3.4](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.3.4) — now a stable release.
