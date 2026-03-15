#define MyAppName "Spovies"
#define MyAppVersion "0.1.2"
#define MyAppPublisher "Kiritex"
#define MyAppURL "https://github.com/kiritexs"
#define MyAppExeName "spovies.exe"
#define BuildPath "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{C6F4A8B9-A92D-4C6E-B762-D0B0038314B4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes

; --- BEST PRACTICES IMPORTED FROM LUNEX ---
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UsePreviousAppDir=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
; ------------------------------------------

; --- IMAGE & ICON SETTINGS ---
SetupIconFile=..\..\assets\logo.ico
WizardImageFile=..\..\assets\logo.png
; ------------------------------

OutputDir=..\..\build\windows\installer
OutputBaseFilename=Spovies-Setup-New
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildPath}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildPath}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildPath}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Added WorkingDir for safer shortcut execution
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
Filename: "{#MyAppURL}"; Description: "Open {#MyAppURL} website"; Flags: shellexec postinstall skipifsilent

[Code]
procedure InitializeWizard;
begin
  { Keeping WizardImage scaling if needed, otherwise this can be empty }
end;