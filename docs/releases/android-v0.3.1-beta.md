**MHRD 0.3.1 для Android (бета).** Android 7.0 і новіші, 64-бітні пристрої. Встановлюйте поверх 0.2.2: ПК, налаштування й паролі лишаються.

**Встановити:** завантажте `MHRD-0.3.1-beta-android.apk` нижче на телефоні й відкрийте (якщо Android попросить — дозвольте встановлення з цього джерела).

**Нове**
- **Плавніша картинка й менше нагрівання.** Оновлюються лише змінені ділянки екрана, а не весь кадр щоразу.
- **H.264.** Сеанс іде відеокодеком — помітно менше мобільного трафіку.
- **Файли між телефоном і ПК.** Під час сеансу на ПК у «Цей ПК» з'являється диск «Phone»: скопіюйте туди файл на ПК — він на телефоні, і навпаки. Головний екран → «Файли обміну» (кнопка з текою): відкрити, поділитися, зберегти, видалити, додати з пам'яті телефона. А з будь-якої програми — «Поділитися → MHRD».
- **Налаштування нових ПК** (Налаштування → «Нові ПК»): маршрут, акаунти, звук, буфер обміну — один раз для всіх нових ПК.
- **Чотири нові теми:** «Північне сяйво», «Папір», «Неон», «Термінал»; вибір теми — по дві в ряд.
- **«Сеанси у фоні»** (Налаштування → Загальні): сповіщення, що не дає Android розірвати сеанс, поки MHRD не на екрані; типово увімкнено, можна вимкнути.

**Виправлено**
- Тунелі WireGuard більше не «падають», коли їх кілька: один тунель на профіль для всіх його сеансів, перевірки не заважають сеансам.
- Затримка тунелю тепер справжня, а не завжди близько 100 мс.

**Перевірка завантаженого**
- SHA-256 файлу — у `SHA256SUMS-android.txt`.
- Сертифікат підпису (SHA-256): `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`.

**Інші платформи**
- Windows: [MHRD 0.3.1](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.1) — `irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex` (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Linux (альфа): [MHRD 0.2.4 для Linux](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.4-alpha) — `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash` (гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux))
- Код Android-версії — гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android).

---

**MHRD 0.3.1 for Android — beta.** Android 7.0+, 64-bit. Installs over 0.2.2; your PCs, settings and passwords are kept.
**New:** smoother picture (only changed areas are updated), H.264 video, files between phone and PC (a "Phone" drive on the PC during a session, a Shared files screen, Share → MHRD), settings for new PCs, four new themes, a "Sessions in the background" switch.
**Fixed:** WireGuard tunnels no longer drop when there are several; the tunnel latency is real instead of always ~100 ms.
Signing certificate SHA-256: `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`. Other platforms: [Windows 0.3.1](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.1), [Linux 0.2.4 alpha](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.4-alpha).
