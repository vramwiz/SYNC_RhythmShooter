program SettingsRttiSmoke;
{$APPTYPE CONSOLE}
// DFMイベントのpublished名を検証する。フォームを作成／表示せずGUI操作もしない。
uses System.SysUtils,SYNC_RhythmShooter_SettingsForm;
begin
  try
    if TFormRhythmShooterSettings.MethodAddress('FormCreate')=nil then
      raise Exception.Create('DFM FormCreate binding missing');
    if TFormRhythmShooterSettings.MethodAddress('FormDestroy')=nil then
      raise Exception.Create('DFM FormDestroy binding missing');
    Writeln('Settings published RTTI PASS; no form creation or GUI');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
end.
