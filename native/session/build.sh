#!/usr/bin/env bash
# Збирає mhrd-session для Linux (x64, FreeRDP/OpenSSL/SDL3 статично).
#   bash native/session/build.sh [Release|Debug]
# Потрібні: vcpkg у ~/vcpkg (або $VCPKG_ROOT), cmake, ninja, компілятор C, а також заголовки
# системних бібліотек, з якими SDL3 і FreeRDP працюють під час роботи (див. README → «Як зібрати»).
# Результат: native/session/out/mhrd-session — його забирає linux/CMakeLists.txt.
set -euo pipefail

config="${1:-Release}"
here="$(cd "$(dirname "$0")" && pwd)"
vcpkg="${VCPKG_ROOT:-$HOME/vcpkg}"

cmake -S "$here" -B "$here/build-linux" -G Ninja \
  "-DCMAKE_BUILD_TYPE=$config" \
  "-DCMAKE_TOOLCHAIN_FILE=$vcpkg/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET=x64-linux \
  "-DVCPKG_INSTALLED_DIR=$here/vcpkg_installed_linux"
cmake --build "$here/build-linux"

mkdir -p "$here/out"
cp "$here/build-linux/mhrd-session" "$here/out/mhrd-session"
echo "OK: $here/out/mhrd-session"
