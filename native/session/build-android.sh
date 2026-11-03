#!/usr/bin/env bash
# Збирає mhrd-session для Android (FreeRDP/OpenSSL статично) — у вигляді libmhrd_session.so, який
# застосунок запускає з теки бібліотек (android/app/src/main/jniLibs/<abi>/).
#   bash native/session/build-android.sh [arm64-v8a|x86_64] [Release|Debug]
# Потрібні: vcpkg у ~/vcpkg (або $VCPKG_ROOT), Android NDK у $ANDROID_NDK_HOME (r28), cmake, ninja.
set -euo pipefail

abi="${1:-arm64-v8a}"
config="${2:-Release}"
here="$(cd "$(dirname "$0")" && pwd)"
vcpkg="${VCPKG_ROOT:-$HOME/vcpkg}"
: "${ANDROID_NDK_HOME:?вкажіть ANDROID_NDK_HOME — теку Android NDK}"
case "$abi" in
  arm64-v8a) triplet=arm64-android ;;
  x86_64) triplet=x64-android ;;
  *) echo "невідомий ABI: $abi" >&2; exit 2 ;;
esac

cmake -S "$here" -B "$here/build-android-$abi" -G Ninja \
  "-DCMAKE_BUILD_TYPE=$config" \
  "-DCMAKE_TOOLCHAIN_FILE=$vcpkg/scripts/buildsystems/vcpkg.cmake" \
  "-DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  "-DVCPKG_TARGET_TRIPLET=$triplet" \
  "-DVCPKG_INSTALLED_DIR=$here/vcpkg_installed_android" \
  "-DANDROID_ABI=$abi" \
  -DANDROID_PLATFORM=android-24
cmake --build "$here/build-android-$abi"

out="$here/../../android/app/src/main/jniLibs/$abi"
mkdir -p "$out"
cp "$here/build-android-$abi/libmhrd_session.so" "$out/libmhrd_session.so"
"$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" "$out/libmhrd_session.so"
echo "OK: $out/libmhrd_session.so"
