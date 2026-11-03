#!/usr/bin/env bash
# Збирає mhrd-tunnel для Android (Go + cgo через NDK: DNS — системним резолвером Android) як
# libmhrd_tunnel.so у android/app/src/main/jniLibs/<abi>/ — застосунок запускає його звідти.
#   bash native/tunnels/build-android.sh [arm64-v8a|x86_64]
# Потрібні: Go, Android NDK у $ANDROID_NDK_HOME (r28).
set -euo pipefail

abi="${1:-arm64-v8a}"
here="$(cd "$(dirname "$0")" && pwd)"
: "${ANDROID_NDK_HOME:?вкажіть ANDROID_NDK_HOME — теку Android NDK}"
case "$abi" in
  arm64-v8a) goarch=arm64; cc=aarch64-linux-android24-clang ;;
  x86_64) goarch=amd64; cc=x86_64-linux-android24-clang ;;
  *) echo "невідомий ABI: $abi" >&2; exit 2 ;;
esac

out="$here/../../android/app/src/main/jniLibs/$abi"
mkdir -p "$out"
export GOTELEMETRY=off GOOS=android GOARCH=$goarch CGO_ENABLED=1
export CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/$cc"
(cd "$here" && go build -trimpath -buildmode=pie -ldflags '-s -w' -o "$out/libmhrd_tunnel.so" .)
echo "OK: $out/libmhrd_tunnel.so"
