#!/usr/bin/env bash
# Пакує зібраний MHRD для Linux (flutter build linux --release) у AppImage і tar.gz.
#   bash linux/packaging/package.sh <версія> [шлях до appimagetool]
# Потрібні: patchelf, appimagetool. Результат — build/dist:
#   MHRD-<версія>-x86_64.AppImage   один файл, дані — у профілі користувача (~/.local/share)
#   mhrd-<версія>-linux-x64.tar.gz  портативна: portable.txt → дані в mhrd-data поруч із програмою
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

(cd "$out" && sha256sum MHRD-*.AppImage mhrd-*.tar.gz > SHA256SUMS-linux.txt && cat SHA256SUMS-linux.txt)
ls -la "$out"
