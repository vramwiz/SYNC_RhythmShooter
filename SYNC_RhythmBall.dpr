library SYNC_RhythmBall;

{$ALIGN 8}

// Shared form units include their DFM resources.

uses
  RhythmBallCircuitPlan in 'Source\Ball\RhythmBallCircuitPlan.pas',
RhythmBallCircuitScene in 'Source\Ball\RhythmBallCircuitScene.pas',
RhythmBreakoutAction in 'Source\Breakout\RhythmBreakoutAction.pas',
RhythmFightingPlan in 'Source\Fighting\RhythmFightingPlan.pas',
RhythmFightingScene in 'Source\Fighting\RhythmFightingScene.pas',
RhythmMiningPlan in 'Source\Mining\RhythmMiningPlan.pas',
RhythmMiningScene in 'Source\Mining\RhythmMiningScene.pas',
RhythmTrainPlan in 'Source\Train\RhythmTrainPlan.pas',
RhythmTrainScene in 'Source\Train\RhythmTrainScene.pas',
RhythmNavalPlan in 'Source\Naval\RhythmNavalPlan.pas',
RhythmNavalScene in 'Source\Naval\RhythmNavalScene.pas',
  Winapi.Windows,
  RhythmBombPlan in 'Source\BombAction\RhythmBombPlan.pas',
  RhythmBombScene in 'Source\BombAction\RhythmBombScene.pas',
  RhythmRacePlan in 'Source\Race\RhythmRacePlan.pas',
  RhythmRaceScene in 'Source\Race\RhythmRaceScene.pas',
  RhythmPreparedData in 'Source\Shared\Settings\RhythmPreparedData.pas',
  RhythmBreakoutCampaign in 'Source\Breakout\RhythmBreakoutCampaign.pas',
  RhythmBreakoutScore in 'Source\Breakout\RhythmBreakoutScore.pas',
  RhythmBreakoutGeometry in 'Source\Breakout\RhythmBreakoutGeometry.pas',
  RhythmBreakoutPlan in 'Source\Breakout\RhythmBreakoutPlan.pas',
  RhythmBreakoutScene in 'Source\Breakout\RhythmBreakoutScene.pas',
  RhythmRunnerPlan in 'Source\Runner\RhythmRunnerPlan.pas',
  RhythmRunnerScene in 'Source\Runner\RhythmRunnerScene.pas',
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
  ConfigureRhythmProduct('SYNC_RhythmBall','リズムボール',rsBall);
end.
