; tools/windows_installer.iss
;
; Inno Setup script that packages a flutter-built Down4More.exe + its DLLs +
; the bundled yt-dlp.exe / ffmpeg.exe / data/ folder into a single
; Down4More-Setup-<version>.exe.
;
; Build flow on a Windows machine (after a one-time install of Inno Setup
; from https://jrsoftware.org/isdl.php):
;
;   1.  pwsh -File tools\fetch_windows_binaries.ps1
;   2.  flutter build windows --release
;   3.  iscc tools\windows_installer.iss
;
; The resulting installer lives at tools\Output\Down4More-Setup-<version>.exe.
;
; Notes
; -----
; * AppId is a fixed GUID — never change it after release or Windows will
;   treat the next installer as a different application and orphan the old
;   uninstall entry. Generate a new one with `[guid]::NewGuid()` only when
;   forking the project.
; * #define MyAppVersion is pulled from MyAppVersionFallback when the user
;   doesn't pass /DMyAppVersion=x.y.z on the iscc command line. CI should
;   pass the real version derived from the git tag.
; * We deliberately do NOT register a yt-dlp / ffmpeg PATH entry. The
;   bundled .exes sit next to down4more.exe and ExternalBinary picks them
;   up from there, so we don't leak our build of yt-dlp into the user's
;   global PATH and shadow whatever they might already have installed.

#define MyAppName          "Down4More"
#define MyAppExeName       "down4more.exe"
#define MyAppPublisher     "Ziad Younis"
#define MyAppURL           "https://github.com/ZiadYounis29/classes-projects"
#ifndef MyAppVersion
  #define MyAppVersion     "0.1.0"
#endif

[Setup]
; Fixed GUID — generated once for this app. Never change.
AppId={{D0E64F4E-7E0C-46FE-9C9B-7C8B5B0F1D4B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
; Bake the installer into a single .exe under tools\Output\.
OutputDir=Output
OutputBaseFilename=Down4More-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Down4More is a 64-bit app — limit installation to 64-bit Windows so the
; Flutter runtime + the bundled yt-dlp.exe (also 64-bit) work.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; By default install per-user so we don't require an admin elevation just
; to drop a Flutter app into Program Files. Users who want a system-wide
; install can pass `/ALLUSERS` on the iscc command line.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Window-icon for the installer wizard itself.
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The Flutter Windows release build writes everything we need into
; build\windows\x64\runner\Release\. That tree already includes the
; bundled yt-dlp.exe / ffmpeg.exe — windows\CMakeLists.txt copied them
; there during `flutter build windows`.
Source: "..\build\windows\x64\runner\Release\*"; \
  DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; \
  Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; \
  Flags: nowait postinstall skipifsilent
