**MHRD 0.2.5 для Linux (альфа).** Debian 12+, Ubuntu 22.04+ (і Mint 21+), Fedora, openSUSE, Arch/Manjaro; 64-бітні Intel/AMD.

**Встановити або оновити одною командою** — у терміналі:

```
curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
```

Команда поставить потрібні системні бібліотеки (apt, dnf, zypper чи pacman — попросить пароль для sudo), завантажить найновішу версію, перевірить контрольну суму й додасть MHRD у меню програм. Повторний запуск — оновлення: ПК, налаштування й паролі лишаються. Видалити: та сама команда з `bash -s -- --uninstall` у кінці.

**Або пакетом**
- `mhrd-0.2.5-alpha-amd64.deb` — Debian, Ubuntu, Mint: відкрити файл (або `sudo apt install ./mhrd-0.2.5-alpha-amd64.deb`).
- `mhrd-0.2.5-alpha.x86_64.rpm` — Fedora (`sudo dnf install ./mhrd-0.2.5-alpha.x86_64.rpm`), openSUSE (`sudo zypper install ./mhrd-0.2.5-alpha.x86_64.rpm`).
- `MHRD-0.2.5-alpha-x86_64.AppImage` — один файл для будь-якого дистрибутива: `chmod +x`, потім запустити.
- `mhrd-0.2.5-alpha-linux-x64.tar.gz` — портативна: розпакувати й запустити `./mhrd`; дані — у теці `mhrd-data` поруч.

**Виправлено**
- **Тунелі WireGuard більше не перебивають власні сеанси** і в рідших випадках: два ПК через один тунель запускаються майже одночасно; MHRD відкривають ярликом ПК; MHRD перезапустили, поки вікна сеансів відкриті; два профілі тунелю мають той самий ключ. Усі вони тепер ідуть через один тунель на ключ.
- **Перевірка тунелів більше не обриває сеанси на інших пристроях** з тим самим ключем: тунелі перевіряються при запуску, при зміні профілю й за кнопкою, а не кожні 5 хвилин. У редакторі тунелю — підказка: один ключ WireGuard — на одному пристрої.
- **Автобекап у спільну (хмарну) теку** з кількох пристроїв: пристрої більше не видаляють бекапи один одного.
- **Буфер обміну:** відповідь сервера, що прийшла запізно, більше не підміняє наступне вставлене.
- **Мініатюра ПК** не псується, коли до одного ПК відкрито два сеанси різними акаунтами.
- Локальний порт сеансу в тунелі закривається разом із сеансом; затримку до ПК міряємо раз на 30 с.

**Перевірка завантаженого:** `sha256sum -c SHA256SUMS-linux.txt --ignore-missing` у теці із завантаженими файлами.

**Інші платформи**
- Windows: [MHRD 0.3.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.2) — `irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex` (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Android (бета): [MHRD 0.3.2 для Android](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.3.2-beta) (гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android))
- Код Linux-версії — гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux).

---

**MHRD 0.2.5 for Linux — alpha.** Install or update: `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash`, or use the .deb / .rpm / AppImage / portable tar.gz.
**Fixed:** WireGuard tunnels no longer disturb their own sessions in rarer cases (two PCs started at once, MHRD opened from a PC shortcut, MHRD restarted while session windows are open, two profiles with the same key); tunnel checks no longer drop sessions on other devices with the same key; devices sharing a cloud auto-backup folder no longer delete each other's backups; a late clipboard response no longer replaces the next paste; the PC thumbnail is no longer corrupted by two sessions to one PC; session ports close with their session; latency is measured every 30 s.
Other platforms: [Windows 0.3.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.2), [Android 0.3.2 beta](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.3.2-beta).
