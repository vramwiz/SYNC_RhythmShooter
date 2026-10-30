program RhythmPreview;
uses Vcl.Forms,
  SYNC_RhythmShooter_SettingsForm in '..\Source\Plugin\Filter\SYNC_RhythmShooter_SettingsForm.pas',
  RhythmAudio in '..\Source\Audio\RhythmAudio.pas',
  RhythmPlayback in '..\Source\Audio\RhythmPlayback.pas',
  RhythmImageBank in '..\Source\Engine\RhythmImageBank.pas',
  RhythmShootingAssets in '..\Source\Engine\RhythmShootingAssets.pas',
  RhythmRenderSurface in '..\Source\Engine\RhythmRenderSurface.pas',
  RhythmParallax in '..\Source\Engine\RhythmParallax.pas',
  RhythmAnimation in '..\Source\Engine\RhythmAnimation.pas',
  RhythmShootingScene in '..\Source\Engine\RhythmShootingScene.pas',
  RhythmAudioAnalysis in '..\Source\Audio\RhythmAudioAnalysis.pas',
  RhythmScene in '..\Source\Engine\RhythmScene.pas',
  RhythmPaths in '..\Source\Common\RhythmPaths.pas',
  MimiChildProcess in '..\Source\Lib\Process\MimiChildProcess.pas';
var Preview:TFormRhythmShooterSettings;
begin
  Application.Initialize;Application.MainFormOnTaskbar:=True;
  Application.CreateForm(TFormRhythmShooterSettings,Preview);
  if ParamCount>0 then Preview.Configure(ParamStr(1),0,50);
  Application.Run;
end.
