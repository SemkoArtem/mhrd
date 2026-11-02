#!/usr/bin/env bash
# Збирає mhrd-tunnel для Linux (x64, статично, без cgo) — вбудований тунель WireGuard (netstack).
#   bash native/tunnels/build.sh
# Потрібен Go. Результат: native/tunnels/out/mhrd-tunnel — його забирає linux/CMakeLists.txt.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export GOTELEMETRY=off CGO_ENABLED=0
mkdir -p "$here/out"
(cd "$here" && go build -trimpath -ldflags '-s -w' -o "$here/out/mhrd-tunnel" .)
echo "OK: $here/out/mhrd-tunnel"
