program SettingsCheckboxPreview;
// 実画面の限定検証用。本人設定は読まず保存しない。通常のnative試験では起動しない。
uses Winapi.Windows,System.SysUtils,System.IOUtils,Vcl.Forms,Vcl.StdCtrls,
  RhythmProduct,RhythmStyles,RhythmSettings,SYNC_RhythmShooter_SettingsForm;
var Form:TFormRhythmShooterSettings;Settings:TRhythmSettings;
begin
  SetEnvironmentVariable('LOCALAPPDATA',PChar(TPath.Combine(ExtractFileDir(ParamStr(0)),'GuiUserData')));
  ConfigureRhythmProduct('SYNC_RhythmGame','チェックボックス表示検証',rsShooting);
  Application.Initialize;Application.MainFormOnTaskbar:=True;
  Application.CreateForm(TFormRhythmShooterSettings,Form);
  Settings:=TRhythmSettings.Defaults;Form.ConfigureState(Settings,320,180);
  TCheckBox(Form.FindComponent('EqualizerVisible')).Enabled:=False;
  Application.Run;
end.
