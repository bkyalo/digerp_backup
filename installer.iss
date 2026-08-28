; Digerp Backup Fetch installer.
; Installs backup_fetch.exe, asks for the site's config values on a custom
; wizard page, writes them to config.json in %ProgramData%\DigerpBackup (the
; exe reads/writes config, downloaded backups, and its log there rather than
; next to itself in Program Files, which is admin-write-only), and registers
; a Scheduled Task that runs the exe daily at 03:30 as SYSTEM.
;
; Built by CI (see .github/workflows/build-installer.yml) with:
;   iscc installer.iss
; Expects dist\backup_fetch.exe to already exist (built by PyInstaller).

#define MyAppName "Digerp Backup Fetch"
#define MyAppVersion "1.0"
#define MyAppExeName "backup_fetch.exe"
#define MyTaskName "Digerp Backup Fetch"

[Setup]
AppId={{A7F3E2B4-9C1D-4E5F-8A6B-DIGERPBK0001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\DigerpBackup
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=DigerpBackupInstaller
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "config.example.json"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Code]
var
  ConfigPage: TInputQueryWizardPage;

procedure InitializeWizard;
begin
  ConfigPage := CreateInputQueryPage(wpSelectDir,
    'Digerp Backup Settings', 'Enter the site details for this company',
    'These values are written to config.json in %ProgramData%\DigerpBackup (not the install folder, so the exe can run without elevation). If one already exists there, its current values are shown below -- leave them as-is to keep them, or edit to update. Basic auth fields can be left blank if the backup URL needs no login.');
  ConfigPage.Add('Site URL (e.g. https://kiambaa.digerp.com):', False);
  ConfigPage.Add('Database name (e.g. kiambaa):', False);
  ConfigPage.Add('Company ID (usually 0):', False);
  ConfigPage.Add('Basic auth username (optional):', False);
  ConfigPage.Add('Basic auth password (optional):', True);

  ConfigPage.Values[2] := '0';
end;

function JsonUnescape(S: String): String;
begin
  { Reverse order from JsonEscape: undo the quote-escape before the
    backslash-escape, or a real backslash immediately before an escaped
    quote would be mishandled. }
  StringChangeEx(S, '\"', '"', True);
  StringChangeEx(S, '\\', '\', True);
  Result := S;
end;

function GetJsonLineValue(const Json, Key: String): String;
var
  Lines: TStringList;
  I, ColonPos: Integer;
  Line, SearchKey, RawValue: String;
begin
  Result := '';
  SearchKey := '"' + Key + '"';
  Lines := TStringList.Create;
  try
    Lines.Text := Json;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Pos(SearchKey, Line) = 1 then
      begin
        ColonPos := Pos(':', Line);
        if ColonPos > 0 then
        begin
          RawValue := Trim(Copy(Line, ColonPos + 1, Length(Line) - ColonPos));
          if (RawValue <> '') and (RawValue[Length(RawValue)] = ',') then
            RawValue := Copy(RawValue, 1, Length(RawValue) - 1);
          if (Length(RawValue) >= 2) and (RawValue[1] = '"') and (RawValue[Length(RawValue)] = '"') then
            RawValue := Copy(RawValue, 2, Length(RawValue) - 2);
          Result := JsonUnescape(RawValue);
        end;
        break;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  ConfigPath: String;
  ExistingJson: AnsiString;
begin
  { Pre-fill from an existing config.json (a prior install) so a reinstall
    shows current values to review/edit instead of forcing blind re-entry
    of data that, previously, would have been silently discarded anyway. }
  if CurPageID = ConfigPage.ID then
  begin
    ConfigPath := ExpandConstant('{commonappdata}\DigerpBackup\config.json');
    if FileExists(ConfigPath) and LoadStringFromFile(ConfigPath, ExistingJson) then
    begin
      ConfigPage.Values[0] := GetJsonLineValue(ExistingJson, 'site_url');
      ConfigPage.Values[1] := GetJsonLineValue(ExistingJson, 'db_name');
      ConfigPage.Values[2] := GetJsonLineValue(ExistingJson, 'company_id');
      ConfigPage.Values[3] := GetJsonLineValue(ExistingJson, 'basic_auth_user');
      ConfigPage.Values[4] := GetJsonLineValue(ExistingJson, 'basic_auth_password');
    end;
  end;
end;

function IsAllDigits(S: String): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
  begin
    if (S[I] < '0') or (S[I] > '9') then
    begin
      Result := False;
      break;
    end;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ConfigPage.ID then
  begin
    if Trim(ConfigPage.Values[0]) = '' then
    begin
      MsgBox('Site URL is required.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(ConfigPage.Values[1]) = '' then
    begin
      MsgBox('Database name is required.', mbError, MB_OK);
      Result := False;
    end
    else if not IsAllDigits(Trim(ConfigPage.Values[2])) then
    begin
      MsgBox('Company ID must be a number.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function JsonEscape(S: String): String;
begin
  StringChangeEx(S, '\', '\\', True);
  StringChangeEx(S, '"', '\"', True);
  Result := S;
end;

function BuildConfigJson(): String;
var
  SiteUrl, DbName, CompanyId, AuthUser, AuthPass: String;
begin
  SiteUrl := JsonEscape(Trim(ConfigPage.Values[0]));
  DbName := JsonEscape(Trim(ConfigPage.Values[1]));
  CompanyId := Trim(ConfigPage.Values[2]);
  AuthUser := JsonEscape(Trim(ConfigPage.Values[3]));
  AuthPass := JsonEscape(Trim(ConfigPage.Values[4]));

  Result :=
    '{' + #13#10 +
    '  "site_url": "' + SiteUrl + '",' + #13#10 +
    '  "company_id": ' + CompanyId + ',' + #13#10 +
    '  "db_name": "' + DbName + '",' + #13#10 +
    '  "backup_prefix": "oytqnijs",' + #13#10 +
    '  "backup_hhmm": "0300",' + #13#10 +
    '  "download_dir": "backups",' + #13#10 +
    '  "poll_duration_minutes": 5,' + #13#10 +
    '  "poll_interval_seconds": 20,' + #13#10 +
    '  "basic_auth_user": "' + AuthUser + '",' + #13#10 +
    '  "basic_auth_password": "' + AuthPass + '"' + #13#10 +
    '}' + #13#10;
end;

function RegisterTaskCommand(): String;
begin
  { -At takes a DateTime; building it with Get-Date -Hour/-Minute instead of
    the bare string '3:30AM' avoids relying on the server's locale to parse
    AM/PM, which can silently fail parameter binding on non-US locales. }
  Result :=
    '$ErrorActionPreference = ''Stop'';' +
    'try {' +
    '$action = New-ScheduledTaskAction -Execute ''' + ExpandConstant('{app}\{#MyAppExeName}') + ''';' +
    '$at = Get-Date -Hour 3 -Minute 30 -Second 0;' +
    '$trigger = New-ScheduledTaskTrigger -Daily -At $at;' +
    '$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries;' +
    'Register-ScheduledTask -TaskName ''{#MyTaskName}'' -Action $action -Trigger $trigger ' +
    '-Settings $settings -User ''NT AUTHORITY\SYSTEM'' -RunLevel Highest -Force | Out-Null;' +
    'Write-Output ''Task registered successfully.''' +
    '} catch {' +
    'Write-Error $_.Exception.Message;' +
    'exit 1' +
    '}';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ConfigPath, TaskLogPath, Cmd: String;
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    { config.json lives in %ProgramData%\DigerpBackup, not the install
      directory, so the exe can read/write its config, downloaded backups,
      and log without needing elevation when run manually -- Program Files
      is admin-write-only. The wizard page was pre-filled from any existing
      config.json (see CurPageChanged), so what's here now is either the
      prior values unchanged or deliberately edited -- always write it,
      rather than silently discarding whatever the user just entered on a
      reinstall. }
    ForceDirectories(ExpandConstant('{commonappdata}\DigerpBackup'));
    ConfigPath := ExpandConstant('{commonappdata}\DigerpBackup\config.json');
    SaveStringToFile(ConfigPath, BuildConfigJson(), False);

    { Run via cmd.exe so stdout/stderr can be redirected to a log file --
      Exec() alone can't capture powershell.exe's output, and a silent
      non-terminating PowerShell error can otherwise exit 0 unnoticed. }
    TaskLogPath := ExpandConstant('{app}\task_register.log');
    Cmd := '/c powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' +
      RegisterTaskCommand() + '" > "' + TaskLogPath + '" 2>&1';
    if not Exec('cmd.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      MsgBox('Could not register the scheduled task automatically. See ' + TaskLogPath +
        ' for details, or create it manually with schtasks (daily at 03:30).', mbError, MB_OK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -Command "Unregister-ScheduledTask -TaskName ''{#MyTaskName}'' -Confirm:$false -ErrorAction SilentlyContinue"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
