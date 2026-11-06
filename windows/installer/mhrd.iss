; Інсталятор MHRD для Windows (Inno Setup 6).
;   ISCC.exe windows\installer\mhrd.iss            — версія з pubspec.yaml не підтягується сама:
;   ISCC.exe /DAppVersion=0.1.0 windows\installer\mhrd.iss
; Бере готову збірку build\windows\x64\runner\Release (flutter build windows --release разом із
; mhrd-session.exe, mhrd-tunnel.exe і бібліотеками Visual C++). Результат: build\installer\.
;
; Ставиться без прав адміністратора (у профіль користувача), а за бажанням — для всіх (діалог).
; Дані користувача (%APPDATA%\ua.mhrd: ПК, налаштування) і паролі в сховищі Windows при видаленні
; програми лишаються — повторне встановлення бачить усе як було.

#ifndef AppVersion
  #define AppVersion "0.3.0"
#endif
#define AppName "MHRD"
#define Release "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{3FE831EA-3F35-43AE-BC3D-DF24734B6A85}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=MHRD contributors
AppPublisherURL=https://github.com/SemkoArtem/mhrd
AppSupportURL=https://github.com/SemkoArtem/mhrd/issues
AppUpdatesURL=https://github.com/SemkoArtem/mhrd/releases
DefaultDirName={autopf}\MHRD
DefaultGroupName=MHRD
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile=..\..\LICENSE
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mhrd.exe
UninstallDisplayName={#AppName}
OutputDir=..\..\build\installer
OutputBaseFilename=mhrd-setup-{#AppVersion}-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Відкриті вікна MHRD і сеанси закриваються перед оновленням (інакше файли зайняті).
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; AppUserModelID — той самий, що в windows/runner/shell_integration.h: інакше «Недавні» на значку
; закріпленого ярлика не з'являться.
Name: "{autoprograms}\MHRD"; Filename: "{app}\mhrd.exe"; AppUserModelID: "mhrd.desktop"
Name: "{autodesktop}\MHRD"; Filename: "{app}\mhrd.exe"; AppUserModelID: "mhrd.desktop"; Tasks: desktopicon

[Run]
Filename: "{app}\mhrd.exe"; Description: "{cm:LaunchProgram,MHRD}"; Flags: nowait postinstall skipifsilent
