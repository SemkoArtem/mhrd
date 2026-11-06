**Бета-версія MHRD для Android** — перша збірка для телефонів і планшетів. Android 7.0 і новіші, 64-бітні пристрої (arm64; x86_64 — емулятори).

**Встановити**
1. Завантажте `MHRD-0.2.2-beta-android.apk` нижче (з телефона).
2. Відкрийте файл; якщо Android попросить — дозвольте встановлення з цього джерела (браузера чи файлового менеджера).
3. Якщо раніше ставили тестову збірку MHRD — спершу зробіть бекап (Налаштування → «Зберегти бекап») і видаліть її: цей випуск підписано іншим, постійним ключем. Наступні версії встановлюватимуться поверх цієї.

**Що вміє**
- Ті самі ПК, групи, акаунти, маршрути (WireGuard, проксі, RD Gateway), бекапи й PIN-блокування, що й у версії для Windows; бекап із ПК відновлюється на телефоні.
- Два режими керування на панелі сеансу:
  - **«Дотик»** — як у клієнта Microsoft: пальці йдуть у Windows справжніми дотиками (прокрутка, щипок, утримання — роблять самі програми ПК);
  - **«Миша»** — екран як тачпад: курсор видно, торкання — клік, утримання — правий клік, торкнутись і одразу провести — виділення чи перетягування, два пальці — прокрутка, щипок — збільшення.
- Плашка сеансу ховається в ручку біля будь-якого краю екрана, її можна перетягувати; кнопка «Назад» спершу ховає клавіатуру, потім плашку.
- Клавіатура телефона: текст будь-якою мовою, Enter, рядок клавіш Esc, Tab, Ctrl/Alt/Win, стрілки, Del, Home/End, PgUp/PgDn, Ctrl+Alt+Del. Клавіатура відкривається поверх картинки (у налаштуваннях можна «зсувати картинку»).
- Буфер обміну (текст) в обидва боки.
- Звук і мікрофон; роздільність підлаштовується під екран і поворот.
- Вхід за PIN і відбитком пальця; автобекап — усередині застосунку, файл назовні — лише за кнопкою «Зберегти бекап».
- Сповіщення показує, скільки сеансів відкрито.
- FreeRDP 3.33.0.

**Перевірка завантаженого**
- SHA-256 файлу — у `SHA256SUMS-android.txt`.
- Сертифікат підпису (SHA-256): `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`.

**Інші платформи**
- Windows: [MHRD 0.2.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.2.2) (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Linux (альфа): [MHRD 0.2.2 для Linux](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.2-alpha) (гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux)) — встановлення одною командою:
  `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash`
- Код Android-версії — гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android).

---

**MHRD for Android — beta.** Android 7.0+, 64-bit devices. Download the APK and open it (allow installing from that source if asked). If you installed an earlier test build, back up and uninstall it first: this release is signed with a new permanent key.
Same PCs, groups, accounts, routes, backups and PIN lock as on Windows; two control modes (real touch like Microsoft's client, or a trackpad with a visible cursor), a movable session bar that hides at any screen edge, phone keyboard with special keys, two-way text clipboard, sound and microphone, fingerprint unlock, in-app auto-backup, FreeRDP 3.33.0.
Signing certificate SHA-256: `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`. Other platforms: [Windows 0.2.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.2.2), [Linux 0.2.2 alpha](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.2-alpha).
