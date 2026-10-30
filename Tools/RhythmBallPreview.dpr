program RhythmBallPreview;
uses Vcl.Forms,
  RhythmPreparedData in '..\Source\Shared\Settings\RhythmPreparedData.pas',
  RhythmRunnerPlan in '..\Source\Runner\RhythmRunnerPlan.pas',
  RhythmRunnerScene in '..\Source\Runner\RhythmRunnerScene.pas',
  RhythmStyles in '..\Source\Shared\Settings\RhythmStyles.pas',
  RhythmProduct in '..\Source\Shared\Settings\RhythmProduct.pas',
  RhythmPlanRef in '..\Source\Shared\Settings\RhythmPlanRef.pas',
  RhythmPrepare in '..\Source\Composition\RhythmPrepare.pas',
  RhythmBallGeometry in '..\Source\Ball\RhythmBallGeometry.pas',
  RhythmBallPlan in '..\Source\Ball\RhythmBallPlan.pas',
  RhythmFireworksPlan in '..\Source\Fireworks\RhythmFireworksPlan.pas',
  RhythmFireworksScene in '..\Source\Fireworks\RhythmFireworksScene.pas',
  RhythmBallScene in '..\Source\Ball\RhythmBallScene.pas',
  SYNC_RhythmShooter_SettingsForm in '..\Source\Shared\Host\SYNC_RhythmShooter_SettingsForm.pas',
  RhythmAudio in '..\Source\Composition\RhythmAudio.pas',
  RhythmPlayback in '..\Source\Shared\Audio\RhythmPlayback.pas',
  RhythmImageBank in '..\Source\Shared\Render\RhythmImageBank.pas',
  RhythmShootingAssets in '..\Source\Shooting\RhythmShootingAssets.pas',
  RhythmRenderSurface in '..\Source\Shared\Render\RhythmRenderSurface.pas',
  RhythmParallax in '..\Source\Shared\Render\RhythmParallax.pas',
  RhythmAnimation in '..\Source\Shared\Render\RhythmAnimation.pas',
  RhythmShootingScene in '..\Source\Shooting\RhythmShootingScene.pas',
  RhythmAudioAnalysis in '..\Source\Shared\Audio\RhythmAudioAnalysis.pas',
  RhythmScene in '..\Source\Composition\RhythmScene.pas',
  RhythmPaths in '..\Source\Shared\Common\RhythmPaths.pas',
  MimiChildProcess in '..\Source\Lib\Process\MimiChildProcess.pas';
var Preview:TFormRhythmShooterSettings;
begin
  ConfigureRhythmProduct('SYNC_RhythmBall','リズムボール',rsBall);
  Application.Initialize;Application.MainFormOnTaskbar:=True;
  Application.CreateForm(TFormRhythmShooterSettings,Preview);
  if ParamCount>0 then Preview.Configure(ParamStr(1),0,50);
  Application.Run;
end.
