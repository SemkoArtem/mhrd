# Встановлення або оновлення MHRD для Windows однією командою (PowerShell, права адміністратора
# не потрібні):
#   irm https://raw.githubusercontent.com/SemkoArtem/mhrd/main/windows/install.ps1 | iex
# Бере інсталятор останнього випуску з GitHub, перевіряє контрольну суму (SHA256SUMS.txt) і
# встановлює для поточного користувача. Відкритий MHRD закривається; ПК, налаштування й паролі
# лишаються.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # без смуги прогресу Invoke-WebRequest завантажує в рази швидше
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host '==> Шукаю останню версію MHRD'
$release = Invoke-RestMethod 'https://api.github.com/repos/SemkoArtem/mhrd/releases/latest'
$setup = $release.assets | Where-Object name -like 'mhrd-setup-*-x64.exe' | Select-Object -First 1
$sums = $release.assets | Where-Object name -eq 'SHA256SUMS.txt' | Select-Object -First 1
if (-not $setup -or -not $sums) { throw 'У випуску немає інсталятора чи контрольних сум.' }

$dir = Join-Path $env:TEMP ('mhrd-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $dir | Out-Null
try {
  $exe = Join-Path $dir $setup.name
  Write-Host "==> Завантажую $($setup.name)"
  Invoke-WebRequest $setup.browser_download_url -OutFile $exe -UseBasicParsing
  $sumsFile = Join-Path $dir 'SHA256SUMS.txt'
  Invoke-WebRequest $sums.browser_download_url -OutFile $sumsFile -UseBasicParsing
  $expected = Get-Content $sumsFile |
    Where-Object { $_ -match "^\s*([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($setup.name))\s*$" } |
    ForEach-Object { $Matches[1].ToLower() } | Select-Object -First 1
  $actual = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
  if (-not $expected -or $expected -ne $actual) { throw 'Контрольна сума не збіглась — файл пошкоджено.' }

  if ($env:MHRD_INSTALL_DRYRUN) { Write-Host "==> Перевірено: $exe (без встановлення)"; return }
  Write-Host '==> Встановлюю'
  $p = Start-Process $exe -ArgumentList '/SILENT', '/SUPPRESSMSGBOXES', '/CLOSEAPPLICATIONS', '/NORESTART' -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Інсталятор завершився з кодом $($p.ExitCode)." }
  Write-Host "==> Готово: MHRD $($release.tag_name.TrimStart('v')) — у меню «Пуск»."
} finally {
  Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
}
