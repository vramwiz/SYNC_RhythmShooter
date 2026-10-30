library SYNC_RhythmFireworks;

{$ALIGN 8}

// Shared form units include their DFM resources.

uses
  Winapi.Windows,
  RhythmStyles in 'Source\Shared\Settings\RhythmStyles.pas',
  RhythmProduct in 'Source\Shared\Settings\RhythmProduct.pas',
  RhythmPlanRef in 'Source\Shared\Settings\RhythmPlanRef.pas',
  RhythmPrepare in 'Source\Composition\RhythmPrepare.pas',
  RhythmBallGeometry in 'Source\Ball\RhythmBallGeometry.pas',
  RhythmBallPlan in 'Source\Ball\RhythmBallPlan.pas',
  RhythmFireworksPlan in 'Source\Fireworks\RhythmFireworksPlan.pas',
  RhythmFireworksScene in 'Source\Fireworks\RhythmFireworksScene.pas',
  RhythmBallScene in 'Source\Ball\RhythmBallScene.pas',
  RhythmControls in 'Source\Shared\UI\RhythmControls.pas',
  RhythmSections in 'Source\Shooting\RhythmSections.pas',
  RhythmDesignTypes in 'Source\Composition\RhythmDesignTypes.pas',
  RhythmDesignImages in 'Source\Shared\Assets\RhythmDesignImages.pas',
  RhythmDesignRequest in 'Source\Shared\Integrations\RhythmDesignRequest.pas',
  RhythmCodexClient in 'Source\Shared\Integrations\RhythmCodexClient.pas',
  RhythmDesignFrame in 'Source\Shared\UI\RhythmDesignFrame.pas',
  RhythmPaths in 'Source\Shared\Common\RhythmPaths.pas',
  RhythmMotion in 'Source\Shooting\RhythmMotion.pas',
  RhythmSettings in 'Source\Shared\Settings\RhythmSettings.pas',
  MimiChildProcess in 'Source\Lib\Process\MimiChildProcess.pas',
  RhythmAudio in 'Source\Composition\RhythmAudio.pas',
  RhythmPlayback in 'Source\Shared\Audio\RhythmPlayback.pas',
  RhythmImageBank in 'Source\Shared\Render\RhythmImageBank.pas',
  RhythmShootingAssets in 'Source\Shooting\RhythmShootingAssets.pas',
  RhythmRenderSurface in 'Source\Shared\Render\RhythmRenderSurface.pas',
  RhythmParallax in 'Source\Shared\Render\RhythmParallax.pas',
  RhythmAnimation in 'Source\Shared\Render\RhythmAnimation.pas',
  RhythmShootingScene in 'Source\Shooting\RhythmShootingScene.pas',
  RhythmAudioAnalysis in 'Source\Shared\Audio\RhythmAudioAnalysis.pas',
  RhythmScene in 'Source\Composition\RhythmScene.pas',
  RhythmD2D in 'Source\Shared\Render\RhythmD2D.pas',
  RhythmBarrage in 'Source\Shooting\RhythmBarrage.pas',
  RhythmStage in 'Source\Shooting\RhythmStage.pas',
  RhythmWaveView in 'Source\Shared\UI\RhythmWaveView.pas',
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\PluginFilterTable.pas',
  SYNC_RhythmShooter_LastFrameCapture in 'Source\Shared\Host\SYNC_RhythmShooter_LastFrameCapture.pas',
  SYNC_RhythmShooter_SettingsForm in 'Source\Shared\Host\SYNC_RhythmShooter_SettingsForm.pas' {FormRhythmShooterSettings},
  SYNC_RhythmShooter_FilterPlugin in 'Source\Shared\Host\SYNC_RhythmShooter_FilterPlugin.pas';

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
  ConfigureRhythmProduct('SYNC_RhythmFireworks','リズム花火',rsFireworks);
end.
