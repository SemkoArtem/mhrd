**MHRD 0.3.2 для Android (бета).** Android 7.0 і новіші, 64-бітні пристрої. Встановлюйте поверх 0.3.1 чи 0.2.2: ПК, налаштування й паролі лишаються.

**Встановити:** завантажте `MHRD-0.3.2-beta-android.apk` нижче на телефоні й відкрийте (якщо Android попросить — дозвольте встановлення з цього джерела).

**Виправлено**
- **Тунелі WireGuard більше не перебивають власні сеанси**, коли два ПК через один тунель запускаються майже одночасно, коли перевірка тунелю збігається в часі з підключенням і коли два профілі тунелю мають той самий ключ — усі вони тепер ідуть через один тунель на ключ.
- **Перевірка тунелів більше не обриває сеанси на інших пристроях** з тим самим ключем (наприклад, той самий .conf на ПК): тунелі перевіряються при запуску, при зміні профілю й за кнопкою, а не кожні 5 хвилин. У редакторі тунелю — підказка: один ключ WireGuard — на одному пристрої.
- Затримку до ПК міряємо раз на 30 с (менше трафіку й записів у журналі ПК).

**Перевірка завантаженого**
- SHA-256 файлу — у `SHA256SUMS-android.txt`.
- Сертифікат підпису (SHA-256): `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`.

**Інші платформи**
- Windows: [MHRD 0.3.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.2) — `irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex` (гілка [`main`](https://github.com/SemkoArtem/mhrd))
- Linux (альфа): [MHRD 0.2.5 для Linux](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.5-alpha) — `curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash` (гілка [`linux`](https://github.com/SemkoArtem/mhrd/tree/linux))
- Код Android-версії — гілка [`android`](https://github.com/SemkoArtem/mhrd/tree/android).

---

**MHRD 0.3.2 for Android — beta.** Android 7.0+, 64-bit. Installs over 0.3.1 or 0.2.2; your PCs, settings and passwords are kept.
**Fixed:** WireGuard tunnels no longer disturb their own sessions when two PCs start at once, when a tunnel check coincides with connecting, or when two profiles share a key (one tunnel per key); tunnel checks no longer drop sessions on other devices with the same key (checked at start, on change and on demand); latency is measured every 30 s.
Signing certificate SHA-256: `F3:38:85:DC:AE:7F:13:9A:28:5F:20:0B:ED:54:3B:41:91:19:D2:64:24:8B:99:E3:A2:16:1C:46:66:69:BE:64`. Other platforms: [Windows 0.3.2](https://github.com/SemkoArtem/mhrd/releases/tag/v0.3.2), [Linux 0.2.5 alpha](https://github.com/SemkoArtem/mhrd/releases/tag/linux-v0.2.5-alpha).
