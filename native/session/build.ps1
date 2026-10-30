# Збирає mhrd-session.exe (Windows x64, статично).
#   powershell -ExecutionPolicy Bypass -File native\session\build.ps1 [-Config Release]
# Потрібні: vcpkg у C:\src\vcpkg (або $env:VCPKG_ROOT), VS Build Tools 2022 з C++.
# Результат: native\session\out\mhrd-session.exe — його забирає windows\CMakeLists.txt.
param([ValidateSet('Debug', 'Release')][string]$Config = 'Release')

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$vcpkg = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { 'C:\src\vcpkg' }
$cmake = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (-not (Test-Path $cmake)) { $cmake = 'cmake' }

& $cmake -S $here -B "$here\build" -G 'Visual Studio 17 2022' -A x64 `
  "-DCMAKE_TOOLCHAIN_FILE=$vcpkg\scripts\buildsystems\vcpkg.cmake" `
  '-DVCPKG_TARGET_TRIPLET=x64-windows-static' `
  "-DVCPKG_INSTALLED_DIR=$here\vcpkg_installed"
if ($LASTEXITCODE) { exit $LASTEXITCODE }

& $cmake --build "$here\build" --config $Config
if ($LASTEXITCODE) { exit $LASTEXITCODE }

New-Item -ItemType Directory -Force "$here\out" | Out-Null
Copy-Item "$here\build\$Config\mhrd-session.exe" "$here\out\mhrd-session.exe" -Force
Write-Host "OK: $here\out\mhrd-session.exe"
