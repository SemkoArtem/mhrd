**MHRD 0.3.4 для Android — перша стабільна версія.** Android 7.0 і новіші, 64-бітні пристрої. Встановлюйте поверх попередньої (бета): ПК, налаштування й паролі лишаються.

**Встановити:** завантажте `MHRD-0.3.4-android.apk` нижче на телефоні й відкрийте.

**Виправлено**
- **ПК бачить телефон під його назвою** (моделлю), а не як «localhost»: тека телефона на ПК тепер називається, наприклад, «Phone на Pixel 8», а не «Phone на localhost», і в списку сеансів на ПК видно, звідки підключення.
- Перетягування ПК у групу перевірено й закріплено тестами: утримайте картку й ведіть — спрацьовує щоразу.

**Перевірка завантаженого**
- SHA-256 файлу — у `SHA256SUMS-android.txt`.
- Сертифікат підпису (SHA-256): `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`.

**Інші платформи**
- Windows: [MHRD 0.3.4](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.4) — `irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex`
- Linux (альфа): [MHRD 0.2.6 для Linux](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.6-alpha) — `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash`
- Код Android-версії — гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android).

---

**MHRD 0.3.4 for Android — the first stable release.** Installs over the previous (beta) version.
**Fixed:** the PC sees the phone by its model name instead of "localhost" (the phone folder on the PC is now e.g. "Phone on Pixel 8"). Dragging a PC into a group is verified and covered by tests — hold the card and drag.
Signing certificate SHA-256: `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`. Other platforms: [Windows 0.3.4](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.4), [Linux 0.2.6 alpha](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.6-alpha).
