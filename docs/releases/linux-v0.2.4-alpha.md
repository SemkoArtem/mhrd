**MHRD 0.2.4 для Linux (альфа).** Debian 12+, Ubuntu 22.04+ (і Mint 21+), Fedora, openSUSE, Arch/Manjaro; 64-бітні Intel/AMD.

**Встановити або оновити одною командою** — у терміналі:

```
curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
```

Команда поставить потрібні системні бібліотеки (apt, dnf, zypper чи pacman — попросить пароль для sudo), завантажить найновішу версію, перевірить контрольну суму й додасть MHRD у меню програм. Повторний запуск — оновлення: ПК, налаштування й паролі лишаються. Видалити: та сама команда з `bash -s -- --uninstall` у кінці.

**Або пакетом**
- `mhrd-0.2.4-alpha-amd64.deb` — Debian, Ubuntu, Mint: відкрити файл (або `sudo apt install ./mhrd-0.2.4-alpha-amd64.deb`).
- `mhrd-0.2.4-alpha.x86_64.rpm` — Fedora (`sudo dnf install ./mhrd-0.2.4-alpha.x86_64.rpm`), openSUSE (`sudo zypper install ./mhrd-0.2.4-alpha.x86_64.rpm`).
- `MHRD-0.2.4-alpha-x86_64.AppImage` — один файл для будь-якого дистрибутива: `chmod +x`, потім запустити.
- `mhrd-0.2.4-alpha-linux-x64.tar.gz` — портативна: розпакувати й запустити `./mhrd`; дані — у теці `mhrd-data` поруч.

**Виправлено**
- **Тунелі WireGuard більше не «падають», коли їх кілька.** Кожен сеанс і кожна перевірка тунелю запускали окремий процес з тим самим ключем, і сервер WireGuard перемикався між ними: відкритий сеанс до двох хвилин втрачав зв'язок, а тунелі показувались непрацюючими. Тепер один тунель на профіль для всіх його сеансів, перевірки не заважають сеансам і йдуть по черзі.
- **Затримка тунелю** показувалась завжди близько 100 мс — тепер справжня.

**Нове**
- Чотири нові теми: «Північне сяйво», «Папір», «Неон», «Термінал» (Налаштування → Тема).

Усе з [0.2.3](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.3-alpha) — H.264, файли через буфер обміну, налаштування нових ПК, пакети .deb і .rpm — на місці.

**Перевірка завантаженого:** `sha256sum -c SHA256SUMS-linux.txt --ignore-missing` у теці із завантаженими файлами.

**Інші платформи**
- Windows: [MHRD 0.3.1](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.1) — `irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex` (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Android (бета): [MHRD 0.3.1 для Android](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.3.1-beta) (гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android))
- Код Linux-версії — гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux).

---

**MHRD 0.2.4 for Linux — alpha.** Install or update: `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash`, or use the .deb / .rpm / AppImage / portable tar.gz.
**Fixed:** WireGuard tunnels no longer drop when there are several (one tunnel per profile serves all its sessions; checks don't disturb sessions); the tunnel latency is real instead of always ~100 ms.
**New:** four themes — Aurora, Paper, Neon, Terminal. Everything from 0.2.3 is included.
Other platforms: [Windows 0.3.1](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.1), [Android 0.3.1 beta](https://github.com/SemkoArtem/mhrd/releases/tag/android-v0.3.1-beta).
