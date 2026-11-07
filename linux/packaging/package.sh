#!/usr/bin/env bash
# Пакує зібраний MHRD для Linux (flutter build linux --release): AppImage, tar.gz, .deb і .rpm.
#   bash linux/packaging/package.sh <версія> [шлях до appimagetool]
# Потрібні: patchelf, appimagetool; для .deb — dpkg-deb, для .rpm — rpmbuild (без них ці пакети
# пропускаються). Результат — build/dist:
#   MHRD-<версія>-x86_64.AppImage   один файл, дані — у профілі користувача (~/.local/share)
#   mhrd-<версія>-linux-x64.tar.gz  портативна: portable.txt → дані в mhrd-data поруч із програмою
#   mhrd-<версія>-amd64.deb, mhrd-<версія>.x86_64.rpm  — встановлення в /opt/mhrd (Debian/Ubuntu,
#                                    Fedora/openSUSE)
set -euo pipefail

ver="$1"
tool="${2:-appimagetool}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"
out="$root/build/dist"
rm -rf "$out"
mkdir -p "$out"

# Бібліотеки плагінів шукають залежності за шляхом з машини збирання — замінюємо на теку поруч.
for so in "$bundle"/lib/*.so; do
  if readelf -d "$so" | grep -qE 'RUNPATH|RPATH'; then patchelf --set-rpath '$ORIGIN' "$so"; fi
done
# libsecret (сховище паролів) — поруч, якщо в системі її немає; є — однаково підійде будь-яка.
secret="$(ldconfig -p | awk '/libsecret-1\.so\.0 \(.*x86-64/ {print $NF; exit}')"
cp -L "$secret" "$bundle/lib/libsecret-1.so.0"

# tar.gz — портативна, як zip на Windows.
stage="$out/mhrd-$ver"
cp -a "$bundle" "$stage"
cat > "$stage/portable.txt" <<'EOF'
MHRD portable: data is kept in the mhrd-data folder next to mhrd;
passwords and keys are encrypted with your master password.
Delete this file to make MHRD use the normal per-user data folder instead.
EOF
tar -C "$out" -czf "$out/mhrd-$ver-linux-x64.tar.gz" "mhrd-$ver"
rm -rf "$stage"

# AppImage: програма в usr/lib/mhrd (Flutter шукає data/ і lib/ поруч із собою).
app="$out/AppDir"
mkdir -p "$app/usr/lib/mhrd"
cp -a "$bundle/." "$app/usr/lib/mhrd/"
cat > "$app/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/mhrd/mhrd" "$@"
EOF
chmod +x "$app/AppRun"
cat > "$app/ua.mhrd.mhrd.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MHRD
GenericName=Remote Desktop
Comment=Remote desktop (RDP) client
Exec=mhrd %U
Icon=ua.mhrd.mhrd
Terminal=false
Categories=Network;RemoteAccess;
StartupWMClass=ua.mhrd.mhrd
EOF
cp "$bundle/mhrd.png" "$app/ua.mhrd.mhrd.png"
ln -sf ua.mhrd.mhrd.png "$app/.DirIcon"
# Без FUSE на машині збирання (контейнери CI) — appimagetool розпаковує сам себе.
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 "$tool" --no-appstream "$app" "$out/MHRD-$ver-x86_64.AppImage"
rm -rf "$app"

# .deb і .rpm: програма в /opt/mhrd, команда /usr/bin/mhrd, пункт меню й піктограма — системні.
# Версія пакета: «0.2.3-alpha» → «0.2.3~alpha» (тильда — «раніше за 0.2.3», як і має бути).
pkgver="${ver//-/\~}"
pkgroot="$out/pkgroot"
mkdir -p "$pkgroot/opt/mhrd" "$pkgroot/usr/bin" "$pkgroot/usr/share/applications" "$pkgroot/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$pkgroot/opt/mhrd/"
ln -s /opt/mhrd/mhrd "$pkgroot/usr/bin/mhrd"
cat > "$pkgroot/usr/share/applications/ua.mhrd.mhrd.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MHRD
GenericName=Remote Desktop
Comment=Remote desktop (RDP) client
Exec=/opt/mhrd/mhrd %U
Icon=ua.mhrd.mhrd
Terminal=false
Categories=Network;RemoteAccess;
StartupWMClass=ua.mhrd.mhrd
EOF
cp "$bundle/mhrd.png" "$pkgroot/usr/share/icons/hicolor/256x256/apps/ua.mhrd.mhrd.png"

if command -v dpkg-deb >/dev/null; then
  deb="$out/debroot"
  cp -a "$pkgroot" "$deb"
  mkdir -p "$deb/DEBIAN"
  cat > "$deb/DEBIAN/control" <<EOF
Package: mhrd
Version: $pkgver
Architecture: amd64
Maintainer: SemkoArtem <32680670+SemkoArtem@users.noreply.github.com>
Depends: libgtk-3-0 | libgtk-3-0t64, libpulse0, libegl1, libgl1, libxkbcommon0, libc6 (>= 2.35)
Section: net
Priority: optional
Homepage: https://github.com/SemkoArtem/mhrd
Description: MHRD — remote desktop (RDP) client
 RDP client with many PCs and accounts, built-in WireGuard, proxy and RD Gateway,
 encrypted backups. FreeRDP 3, H.264.
EOF
  dpkg-deb --root-owner-group --build "$deb" "$out/mhrd-$ver-amd64.deb" >/dev/null
  rm -rf "$deb"
fi

if command -v rpmbuild >/dev/null; then
  rpmtop="$out/rpmbuild"
  mkdir -p "$rpmtop/SPECS"
  # Залежності — вручну й «або» для назв Fedora та openSUSE; автоматичні вимкнено: програма несе свої
  # бібліотеки в /opt/mhrd/lib, а rpm вимагав би їх від системи.
  cat > "$rpmtop/SPECS/mhrd.spec" <<EOF
Name: mhrd
Version: $pkgver
Release: 1
Summary: MHRD — remote desktop (RDP) client
License: AGPL-3.0-only
URL: https://github.com/SemkoArtem/mhrd
BuildArch: x86_64
AutoReqProv: no
Requires: (gtk3 or libgtk-3-0)
Requires: (pulseaudio-libs or libpulse0)
Requires: (mesa-libEGL or Mesa-libEGL1)
Requires: (mesa-libGL or Mesa-libGL1)
Requires: (libxkbcommon or libxkbcommon0)
Requires: glibc >= 2.35
%global debug_package %{nil}
%global __os_install_post %{nil}
%define _build_id_links none

%description
RDP client with many PCs and accounts, built-in WireGuard, proxy and RD Gateway,
encrypted backups. FreeRDP 3, H.264.

%install
cp -a "$pkgroot/." %{buildroot}/

%files
/opt/mhrd
/usr/bin/mhrd
/usr/share/applications/ua.mhrd.mhrd.desktop
/usr/share/icons/hicolor/256x256/apps/ua.mhrd.mhrd.png
EOF
  rpmbuild -bb --quiet --define "_topdir $rpmtop" "$rpmtop/SPECS/mhrd.spec"
  cp "$rpmtop"/RPMS/x86_64/mhrd-*.rpm "$out/mhrd-$ver.x86_64.rpm"
  rm -rf "$rpmtop"
fi
rm -rf "$pkgroot"

(cd "$out" && sha256sum MHRD-*.AppImage mhrd-*.tar.gz mhrd-*.deb mhrd-*.rpm 2>/dev/null > SHA256SUMS-linux.txt; cat SHA256SUMS-linux.txt)
ls -la "$out"
