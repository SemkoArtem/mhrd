**MHRD 0.3.3 для Android (бета).** Android 7.0 і новіші, 64-бітні пристрої. Встановлюйте поверх попередньої: ПК, налаштування й паролі лишаються.

**Встановити:** завантажте `MHRD-0.3.3-beta-android.apk` нижче на телефоні й відкрийте.

**Виправлено**
- **Робочий стіл ПК більше не «роздутий».** Телефон передавав ПК масштаб свого екрана (×2.5–3), і Windows збільшувала весь інтерфейс утричі. Тепер — 100 %, як у клієнтах Microsoft і Remote Desktop Manager; роздільність, як і раніше, — повна роздільність екрана телефона, тож картинка чітка. Більший текст — у налаштуваннях ПК: «Масштаб елементів на віддаленому ПК».
- Роздільність сеансу одразу — на весь екран телефона: перші секунди після підключення картинка більше не розтягнута.
- **Курсор у режимі «Миша»** — розміром, як у Windows, у пропорції до картинки ПК (зі збільшенням щипком росте разом з нею), а не втричі більший.
- **Перетягування ПК у групу** спрацьовує щоразу, а не через раз: утримайте картку й ведіть.
- У налаштуваннях телефона прибрано розділ «Нові ПК» — ПК додають прямо з головного екрана.

**Перевірка завантаженого**
- SHA-256 файлу — у `SHA256SUMS-android.txt`.
- Сертифікат підпису (SHA-256): `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`.

**Інші платформи**
- Windows: [MHRD 0.3.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.2) — `irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex`
- Linux (альфа): [MHRD 0.2.5 для Linux](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.5-alpha) — `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash`
- Код Android-версії — гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android).

---

**MHRD 0.3.3 for Android — beta.** Installs over the previous version.
**Fixed:** the PC desktop is no longer blown up — the phone used to send its own display scale (×2.5–3) to the PC; now 100 %, like the Microsoft and Remote Desktop Manager clients (resolution stays the phone's full resolution; bigger text — per PC, "Remote PC scale"). The session starts at the full-screen resolution right away. The mouse-mode cursor is Windows-sized, in proportion to the picture. Dragging a PC to a group works every time. The "New PCs" settings section is removed on phones.
Signing certificate SHA-256: `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`. Other platforms: [Windows 0.3.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.2), [Linux 0.2.5 alpha](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.5-alpha).
