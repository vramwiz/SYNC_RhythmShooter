library SYNC_RhythmShooter;

{$ALIGN 8}

{$R *.res}

uses
  Winapi.Windows,
  RhythmDesignTypes in 'Source\Common\RhythmDesignTypes.pas',
  RhythmDesignImages in 'Source\Common\RhythmDesignImages.pas',
  RhythmDesignRequest in 'Source\Integrations\RhythmDesignRequest.pas',
  RhythmCodexClient in 'Source\Integrations\RhythmCodexClient.pas',
  RhythmDesignFrame in 'Source\UI\RhythmDesignFrame.pas',
  RhythmPaths in 'Source\Common\RhythmPaths.pas',
  RhythmMotion in 'Source\Common\RhythmMotion.pas',
  RhythmSettings in 'Source\Common\RhythmSettings.pas',
  MimiChildProcess in 'Source\Lib\Process\MimiChildProcess.pas',
  RhythmAudio in 'Source\Audio\RhythmAudio.pas',
  RhythmPlayback in 'Source\Audio\RhythmPlayback.pas',
  RhythmScene in 'Source\Engine\RhythmScene.pas',
  RhythmD2D in 'Source\Engine\RhythmD2D.pas',
  RhythmBarrage in 'Source\Engine\RhythmBarrage.pas',
  RhythmStage in 'Source\Engine\RhythmStage.pas',
  RhythmWaveView in 'Source\UI\RhythmWaveView.pas',
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\PluginFilterTable.pas',
  SYNC_RhythmShooter_LastFrameCapture in 'Source\Common\Render\SYNC_RhythmShooter_LastFrameCapture.pas',
  SYNC_RhythmShooter_SettingsForm in 'Source\Plugin\Filter\SYNC_RhythmShooter_SettingsForm.pas' {FormRhythmShooterSettings},
  SYNC_RhythmShooter_FilterPlugin in 'Source\Plugin\Filter\SYNC_RhythmShooter_FilterPlugin.pas';

function InitializePlugin(Version: DWORD): Byte; cdecl;
begin
  Result := InitializeRhythmShooterPlugin(Version);
end;

procedure UninitializePlugin; cdecl;
begin
  FinalizeRhythmShooterPlugin;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := GetRhythmShooterFilterTable;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
