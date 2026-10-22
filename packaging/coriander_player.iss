#define MyAppName "Coriander Player"
#define MyAppExeName "coriander_player.exe"

[Setup]
AppId={{8F3E2C4A-9B1D-4E5F-A6C7-2D8B9E1F3A55}
AppName={#MyAppName}
AppVersion=1.5.7
AppVerName={#MyAppName} 1.5.7
VersionInfoVersion=1.5.7.1025
VersionInfoDescription=Coriander Player 1.5.7 installer
DefaultDirName={autopf}\Coriander Player
DefaultGroupName=Coriander Player
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\dist
OutputBaseFilename=CorianderPlayer-Setup-1.5.7
SetupIconFile=..\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=..\LICENSE
InfoBeforeFile=1.5.7更新说明.txt
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
CloseApplicationsFilter=coriander_player.exe,desktop_lyric.exe,*.dll
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "bundle\*"; DestDir: "{app}"; Excludes: "SHA256SUMS.txt,验证记录.txt"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\coriander_player.ico"; IconIndex: 0
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\coriander_player.ico"; IconIndex: 0; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
// The existing close button hides to tray. Request its actual tray Exit action
// before replacing files. Only windows running from the chosen install path
// are targeted; portable copies and other applications are left alone.
function FindWindowExW(Parent, Previous: HWND; ClassName: string; WindowName: LongWord): HWND;
  external 'FindWindowExW@user32.dll stdcall';
function GetWindowThreadProcessId(Window: HWND; var ProcessId: LongWord): LongWord;
  external 'GetWindowThreadProcessId@user32.dll stdcall';
function OpenProcess(Access: LongWord; Inherit: Boolean; ProcessId: LongWord): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function QueryFullProcessImageNameW(Process: THandle; Flags: LongWord; Name: string; var Size: LongWord): Boolean;
  external 'QueryFullProcessImageNameW@kernel32.dll stdcall';
function PostMessageW(Window: HWND; Msg: LongWord; WParam, LParam: LongWord): Boolean;
  external 'PostMessageW@user32.dll stdcall';
function WaitForSingleObject(Handle: THandle; Milliseconds: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function PrepareToInstall(var NeedsRestart: Boolean): string;
var
  Window: HWND;
  ProcessId, Size, Attempt: LongWord;
  Process: THandle;
  ImageName, Target: string;
begin
  Result := '';
  Target := ExpandConstant('{app}\{#MyAppExeName}');
  Window := FindWindowExW(0, 0, 'FLUTTER_RUNNER_WIN32_WINDOW', 0);
  while Window <> 0 do begin
    GetWindowThreadProcessId(Window, ProcessId);
    Process := OpenProcess($00101000, False, ProcessId);
    if Process <> 0 then begin
      try
        Size := 32768;
        SetLength(ImageName, Size);
        if QueryFullProcessImageNameW(Process, 0, ImageName, Size) then begin
          SetLength(ImageName, Size);
          if CompareText(ImageName, Target) = 0 then begin
            Log('Requesting a graceful exit before upgrade: ' + ImageName);
            PostMessageW(Window, $0111, 1029, 0);
            Attempt := 0;
            while (WaitForSingleObject(Process, 0) = $00000102) and (Attempt < 100) do begin
              Sleep(100);
              Attempt := Attempt + 1;
            end;
            if WaitForSingleObject(Process, 0) = $00000102 then begin
              Result := '播放器尚未退出。请在托盘菜单中选择“退出”，然后重试安装。无需卸载旧版本。';
              Exit;
            end;
          end;
        end;
      finally
        CloseHandle(Process);
      end;
    end;
    Window := FindWindowExW(0, Window, 'FLUTTER_RUNNER_WIN32_WINDOW', 0);
  end;
end;



