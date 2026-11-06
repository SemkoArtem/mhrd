#!/usr/bin/env bash
# Встановлення MHRD для Linux (Debian 12+, Ubuntu 22.04+/Mint 21+, Arch/Manjaro, Fedora 39+,
# openSUSE Tumbleweed і Leap 16) одною командою:
#   curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash
# Бере найновіший реліз Linux із GitHub (tar.gz), перевіряє контрольну суму, ставить системні
# бібліотеки (apt, pacman, dnf чи zypper — через sudo) і саму програму — для поточного користувача:
#   ~/.local/opt/mhrd              програма
#   ~/.local/bin/mhrd              команда запуску
#   ~/.local/share/applications    пункт у меню програм
# Повторний запуск — оновлення (ПК, налаштування й паролі лишаються). Видалити програму:
#   curl -fsSL https://raw.githubusercontent.com/SemkoArtem/mhrd/linux/linux/install.sh | bash -s -- --uninstall
set -euo pipefail

repo="SemkoArtem/mhrd"
dest="$HOME/.local/opt/mhrd"
bin="$HOME/.local/bin"
apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor/256x256/apps"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf 'Помилка: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$dest" "$bin/mhrd" "$apps/ua.mhrd.mhrd.desktop" "$icons/ua.mhrd.mhrd.png"
  say "MHRD видалено. Дані (ПК, налаштування) лишились у ~/.local/share/ua.mhrd.mhrd — видаліть теку, якщо вони не потрібні."
  exit 0
fi

[ "$(uname -m)" = "x86_64" ] || die "поки є лише збірка для x86_64 (64-бітні Intel/AMD)."
[ "$(id -u)" -ne 0 ] || die "запускайте від свого користувача, не від root (sudo попросять лише для системних пакетів)."
# Збірка — з Ubuntu 22.04: потрібна glibc 2.35 чи новіша (старіші системи програму не запустять).
glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
if [ -n "$glibc" ] && [ "$(printf '%s\n2.35\n' "$glibc" | sort -V | head -n1)" != "2.35" ]; then
  die "система застара (glibc $glibc, потрібна 2.35+): Debian 12+, Ubuntu 22.04+, Fedora 36+, openSUSE Leap 16."
fi

# Системні бібліотеки: GTK 3 (вікно), libsecret (сховище паролів), PulseAudio/PipeWire (звук),
# OpenGL/EGL, xkbcommon (клавіатура).
. /etc/os-release 2>/dev/null || true
family=" ${ID:-} ${ID_LIKE:-} "
sudo=""
[ "$(id -u)" -eq 0 ] || sudo="sudo"
case "$family" in
  *" arch "*|*" manjaro "*|*" endeavouros "*)
    say "Системні пакети (pacman)"
    $sudo pacman -S --needed --noconfirm gtk3 libsecret libpulse libglvnd libxkbcommon curl ca-certificates
    ;;
  *" debian "*|*" ubuntu "*)
    say "Системні пакети (apt)"
    $sudo apt-get update
    $sudo apt-get install -y libgtk-3-0 libsecret-1-0 libpulse0 libegl1 libgl1 libxkbcommon0 curl ca-certificates
    ;;
  *" fedora "*|*" rhel "*)
    say "Системні пакети (dnf)"
    $sudo dnf install -y gtk3 libsecret pulseaudio-libs mesa-libEGL mesa-libGL libxkbcommon curl ca-certificates
    ;;
  *" suse "*|*" opensuse "*)
    say "Системні пакети (zypper)"
    $sudo zypper --non-interactive install libgtk-3-0 libsecret-1-0 libpulse0 Mesa-libEGL1 Mesa-libGL1 libxkbcommon0 curl ca-certificates
    ;;
  *)
    say "Невідомий дистрибутив (${ID:-?}): пропускаю системні пакети — потрібні GTK 3, libsecret, libpulse, OpenGL."
    ;;
esac

say "Шукаю найновішу версію для Linux"
api="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=30")" ||
  die "не вдалося звернутися до GitHub."
url="$(printf '%s' "$api" | grep -o "https://github.com/$repo/releases/download/[^\"]*-linux-x64\.tar\.gz" | head -n1)"
[ -n "$url" ] || die "не знайдено релізу для Linux на github.com/$repo/releases."
sums="${url%/*}/SHA256SUMS-linux.txt"
file="${url##*/}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
say "Завантажую $file"
curl -fL --progress-bar -o "$tmp/$file" "$url"
curl -fsSL -o "$tmp/SHA256SUMS-linux.txt" "$sums"
(cd "$tmp" && grep " $file\$" SHA256SUMS-linux.txt | sha256sum -c -) || die "контрольна сума не збіглась — файл пошкоджено."

say "Встановлюю в $dest"
mkdir -p "$tmp/x" "$(dirname "$dest")" "$bin" "$apps" "$icons"
tar -C "$tmp/x" -xzf "$tmp/$file"
src="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)"
# Встановлена програма тримає дані в профілі користувача, а не поруч (як портативна з tar.gz).
rm -f "$src/portable.txt"
rm -rf "$dest.new"
mv "$src" "$dest.new"
rm -rf "$dest"
mv "$dest.new" "$dest"

ln -sf "$dest/mhrd" "$bin/mhrd"
cp "$dest/mhrd.png" "$icons/ua.mhrd.mhrd.png"
cat > "$apps/ua.mhrd.mhrd.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MHRD
GenericName=Remote Desktop
Comment=Remote desktop (RDP) client
Exec=$dest/mhrd %U
Icon=ua.mhrd.mhrd
Terminal=false
Categories=Network;RemoteAccess;
StartupWMClass=ua.mhrd.mhrd
EOF
command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

say "Готово: MHRD є в меню програм; з термінала — команда mhrd."
case ":$PATH:" in *":$bin:"*) ;; *) echo "(Щоб команда mhrd працювала в терміналі, додайте $bin у PATH або перезайдіть у систему.)" ;; esac
