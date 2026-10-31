# Збирає mhrd-tunnel.exe (Windows x64) — вбудований тунель WireGuard (netstack).
#   powershell -ExecutionPolicy Bypass -File native\tunnels\build.ps1
# Потрібен Go (go.dev; портативний — у C:\src\go). Результат: native\tunnels\out\mhrd-tunnel.exe —
# його забирає windows\CMakeLists.txt.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$go = if (Get-Command go -ErrorAction SilentlyContinue) { 'go' } else { 'C:\src\go\bin\go.exe' }
$env:GOTELEMETRY = 'off'
$env:CGO_ENABLED = '0'

Push-Location $here
try {
  New-Item -ItemType Directory -Force "$here\out" | Out-Null
  & $go build -trimpath -ldflags '-s -w' -o "$here\out\mhrd-tunnel.exe" .
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}
Write-Host "OK: $here\out\mhrd-tunnel.exe"
