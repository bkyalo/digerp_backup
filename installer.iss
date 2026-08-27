; Digerp Backup Fetch installer.
; Installs backup_fetch.exe, asks for the site's config values on a custom
; wizard page, writes them to config.json, and registers a Scheduled Task
; that runs the exe daily at 03:30 as SYSTEM.
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
    'These values are written to config.json. Basic auth fields can be left blank if the backup URL needs no login.');
  ConfigPage.Add('Site URL (e.g. https://kiambaa.digerp.com):', False);
  ConfigPage.Add('Database name (e.g. kiambaa):', False);
  ConfigPage.Add('Company ID (usually 0):', False);
  ConfigPage.Add('Basic auth username (optional):', False);
  ConfigPage.Add('Basic auth password (optional):', True);

  ConfigPage.Values[2] := '0';
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
  Result :=
    '$action = New-ScheduledTaskAction -Execute ''' + ExpandConstant('{app}\{#MyAppExeName}') + ''';' +
    '$trigger = New-ScheduledTaskTrigger -Daily -At 3:30AM;' +
    '$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries;' +
    'Register-ScheduledTask -TaskName ''{#MyTaskName}'' -Action $action -Trigger $trigger ' +
    '-Settings $settings -User ''SYSTEM'' -RunLevel Highest -Force';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ConfigPath, Cmd: String;
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    { Only seed config.json from the wizard answers on first install; never overwrite an existing one. }
    ConfigPath := ExpandConstant('{app}\config.json');
    if not FileExists(ConfigPath) then
      SaveStringToFile(ConfigPath, BuildConfigJson(), False);

    Cmd := '-NoProfile -ExecutionPolicy Bypass -Command "' + RegisterTaskCommand() + '"';
    if not Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      MsgBox('Could not register the scheduled task automatically. You can create it manually with schtasks or Task Scheduler (daily at 03:30).', mbError, MB_OK);
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
