unit RhythmPaths;

interface

function ModuleFolder: string;
function AssetFolder: string;
function CacheFolder: string;
function SettingsPath: string;

implementation

uses Winapi.Windows, System.SysUtils, System.IOUtils;

function ModuleFolder: string;
var Buffer: array[0..32767] of Char;
begin
  if GetModuleFileName(HInstance, Buffer, Length(Buffer)) = 0 then RaiseLastOSError;
  Result := ExtractFilePath(string(Buffer));
end;

function AssetFolder: string;
begin Result := TPath.Combine(ModuleFolder, 'Assets'); end;

function CacheFolder: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'SYNC_RhythmShooter\Cache');
  ForceDirectories(Result);
end;

function SettingsPath: string;
var Folder:string;
begin
  Folder:=TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'SYNC_RhythmShooter');
  ForceDirectories(Folder);Result:=TPath.Combine(Folder,'Preview.ini');
end;

end.
