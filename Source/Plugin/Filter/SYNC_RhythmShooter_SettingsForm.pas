unit SYNC_RhythmShooter_SettingsForm;
interface
uses System.Classes, System.SysUtils, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Dialogs, RhythmAudio, RhythmPlayback, RhythmScene, RhythmWaveView, RhythmSettings,RhythmDesignFrame;
type
  TFormRhythmShooterSettings = class(TForm)
    procedure FormCreate(Sender:TObject);
    procedure FormDestroy(Sender:TObject);
  private
    FFile:TEdit;
    FDirection:TComboBox;
    FSensitivity,FSeek:TTrackBar;
    FStatus,FClock:TLabel;
    FPreview:TPaintBox;
    FWave:TRhythmWaveView;
    FTimer:TTimer;
    FFrame:TBitmap;
    FRenderer:TRhythmRenderer;
    FAudio:TRhythmAudio;
    FWorker:TRhythmLoadThread;
    FPlayer:TRhythmPlayback;
    FTime:Double;
    FUpdating:Boolean;
    FReloadAt:UInt64;
    FState:TRhythmSettings;
    FViewWidth,FViewHeight:Integer;
    FDesignEditor:TRhythmDesignFrame;
    procedure DesignChanged(Sender:TObject);
    procedure DesignBusyChanged(Sender:TObject);
    procedure SetBusy(Value:Boolean);
    procedure BrowseClick(Sender:TObject);
    procedure LoadClick(Sender:TObject);
    procedure PlayClick(Sender:TObject);
    procedure PauseClick(Sender:TObject);
    procedure StopClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    procedure SeekChange(Sender:TObject);
    procedure SettingChange(Sender:TObject);
    procedure TimerTick(Sender:TObject);
    procedure PreviewPaint(Sender:TObject);
    procedure WaveMouseDown(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
    procedure BeginLoad(Force:Boolean=False);
    procedure SaveSettings;
  public
    procedure Configure(const FileName:string;Direction,Sensitivity:Integer);
    procedure ConfigureState(const State:TRhythmSettings;ViewWidth:Integer=1280;ViewHeight:Integer=720);
    function Snapshot:TRhythmSettings;
    function MusicFile:string;
    function ScrollDirection:Integer;
    function DetectionSensitivity:Integer;
  end;
implementation
uses Winapi.Windows, System.Math, System.Types, System.IniFiles, System.IOUtils, RhythmPaths;
{$R *.dfm}

procedure TFormRhythmShooterSettings.FormCreate(Sender:TObject);
var Top,Transport,Bottom:TPanel;L:TLabel;B:TButton;Ini:TMemIniFile;Pages:TPageControl;Animation,Design:TTabSheet;
  procedure Button(Parent:TWinControl;const Text:string;X,Y,W:Integer;Click:TNotifyEvent);
  begin B:=TButton.Create(Self);B.Parent:=Parent;B.SetBounds(X,Y,W,29);B.Caption:=Text;B.OnClick:=Click;end;
begin
  Caption:='リズムシューティング 設定 / Revision 4';
  DoubleBuffered:=True;ClientWidth:=1100;ClientHeight:=760;
  Constraints.MinWidth:=850;Constraints.MinHeight:=620;FUpdating:=True;
  FPlayer:=TRhythmPlayback.Create;FRenderer:=TRhythmRenderer.Create;FFrame:=Vcl.Graphics.TBitmap.Create;FFrame.PixelFormat:=pf32bit;
  Pages:=TPageControl.Create(Self);Pages.Parent:=Self;Pages.Align:=alClient;Pages.DoubleBuffered:=True;
  Animation:=TTabSheet.Create(Self);Animation.PageControl:=Pages;Animation.Caption:='アニメーション';Animation.DoubleBuffered:=True;
  Design:=TTabSheet.Create(Self);Design.PageControl:=Pages;Design.Caption:='カスタムデザイン';Design.DoubleBuffered:=True;
  FDesignEditor:=TRhythmDesignFrame.Create(Self);FDesignEditor.Parent:=Design;FDesignEditor.Align:=alClient;
  FDesignEditor.OnChange:=DesignChanged;FDesignEditor.OnBusyChange:=DesignBusyChanged;
  Top:=TPanel.Create(Self);Top.Parent:=Animation;Top.Align:=alTop;Top.Height:=94;Top.BevelOuter:=bvNone;
  L:=TLabel.Create(Self);L.Parent:=Top;L.SetBounds(14,12,70,20);L.Caption:='音楽ファイル';
  FFile:=TEdit.Create(Self);FFile.Parent:=Top;FFile.Name:='MusicFile';FFile.SetBounds(94,8,750,25);FFile.Anchors:=[akLeft,akTop,akRight];
  Button(Top,'参照...',854,6,100,BrowseClick);B.Anchors:=[akTop,akRight];
  Button(Top,'解析',966,6,112,LoadClick);B.Anchors:=[akTop,akRight];
  L:=TLabel.Create(Self);L.Parent:=Top;L.SetBounds(14,52,70,20);L.Caption:='スクロール';
  FDirection:=TComboBox.Create(Self);FDirection.Parent:=Top;FDirection.Name:='ScrollDirection';FDirection.SetBounds(94,46,140,25);FDirection.Style:=csDropDownList;
  FDirection.Items.Add('縦スクロール');FDirection.Items.Add('横スクロール');FDirection.ItemIndex:=0;FDirection.OnChange:=SettingChange;
  L:=TLabel.Create(Self);L.Parent:=Top;L.SetBounds(258,52,75,20);L.Caption:='解析感度';
  FSensitivity:=TTrackBar.Create(Self);FSensitivity.Parent:=Top;FSensitivity.Name:='Sensitivity';FSensitivity.SetBounds(334,42,260,42);FSensitivity.Min:=1;FSensitivity.Max:=100;FSensitivity.Position:=50;FSensitivity.Frequency:=10;FSensitivity.OnChange:=SettingChange;
  L:=TLabel.Create(Self);L.Parent:=Top;L.SetBounds(620,52,450,30);L.Caption:='音量の立ち上がり → 命中・爆発 / 標準素材';
  Bottom:=TPanel.Create(Self);Bottom.Parent:=Self;Bottom.Align:=alBottom;Bottom.Height:=76;Bottom.BevelOuter:=bvNone;
  Button(Bottom,'適用して閉じる',916,6,160,SaveClick);B.Anchors:=[akTop,akRight];
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Bottom;FStatus.Align:=alBottom;FStatus.Height:=28;FStatus.Layout:=tlCenter;FStatus.AlignWithMargins:=True;FStatus.Caption:='WAV / MP3 を選択してください。';
  Transport:=TPanel.Create(Self);Transport.Parent:=Animation;Transport.Align:=alBottom;Transport.Height:=128;Transport.BevelOuter:=bvNone;
  FWave:=TRhythmWaveView.Create(Self);FWave.Parent:=Transport;FWave.Align:=alTop;FWave.Height:=42;FWave.OnMouseDown:=WaveMouseDown;
  FSeek:=TTrackBar.Create(Self);FSeek.Parent:=Transport;FSeek.Name:='Timeline';FSeek.SetBounds(8,43,1080,34);FSeek.Anchors:=[akLeft,akTop,akRight];FSeek.Min:=0;FSeek.Max:=100000;FSeek.TickStyle:=tsNone;FSeek.OnChange:=SeekChange;
  Button(Transport,'再生',16,88,90,PlayClick);B.Name:='PreviewPlay';Button(Transport,'一時停止',116,88,90,PauseClick);B.Name:='PreviewPause';Button(Transport,'停止',216,88,90,StopClick);B.Name:='PreviewStop';
  FClock:=TLabel.Create(Self);FClock.Parent:=Transport;FClock.SetBounds(326,94,520,25);FClock.Caption:='00:00.000';
  FPreview:=TPaintBox.Create(Self);FPreview.Parent:=Animation;FPreview.Align:=alClient;FPreview.OnPaint:=PreviewPaint;
  FTimer:=TTimer.Create(Self);FTimer.Interval:=16;FTimer.OnTimer:=TimerTick;
  Ini:=TMemIniFile.Create(SettingsPath,TEncoding.UTF8);
  try
    FFile.Text:=Ini.ReadString('Preview','Music','');FDirection.ItemIndex:=EnsureRange(Ini.ReadInteger('Preview','Direction',0),0,1);
    FSensitivity.Position:=EnsureRange(Ini.ReadInteger('Preview','Sensitivity',50),1,100);
  finally Ini.Free;end;
  FUpdating:=False;
  FState:=TRhythmSettings.Defaults;FViewWidth:=1280;FViewHeight:=720;
  if FileExists(ChangeFileExt(SettingsPath,'.json')) then
    if TRhythmSettings.TryJSON(TFile.ReadAllText(ChangeFileExt(SettingsPath,'.json'),TEncoding.UTF8),FState) then
    begin FUpdating:=True;FFile.Text:=FState.Music;FDirection.ItemIndex:=FState.Direction;FSensitivity.Position:=FState.Sensitivity;FUpdating:=False;end;
  if (FFile.Text<>'') and FileExists(FFile.Text) then FReloadAt:=GetTickCount64+100;
  FDesignEditor.Designs:=FState.Designs;Pages.ActivePage:=Animation;
end;

procedure TFormRhythmShooterSettings.Configure(const FileName:string;Direction,Sensitivity:Integer);
var State:TRhythmSettings;
begin State:=TRhythmSettings.Defaults;State.Music:=FileName;State.Direction:=Direction;State.Sensitivity:=Sensitivity;ConfigureState(State);end;
procedure TFormRhythmShooterSettings.ConfigureState(const State:TRhythmSettings;ViewWidth,ViewHeight:Integer);
begin
  FState:=State;FViewWidth:=Max(1,ViewWidth);FViewHeight:=Max(1,ViewHeight);
  FDesignEditor.Designs:=State.Designs;
  FUpdating:=True;
  try FFile.Text:=State.Music;FDirection.ItemIndex:=EnsureRange(State.Direction,0,1);FSensitivity.Position:=EnsureRange(State.Sensitivity,1,100);
  finally FUpdating:=False;end;
  FReloadAt:=0;if (State.Music<>'') and FileExists(State.Music) then FReloadAt:=GetTickCount64+100;
end;
function TFormRhythmShooterSettings.Snapshot:TRhythmSettings;
begin Result:=FState;Result.Music:=MusicFile;Result.Direction:=ScrollDirection;Result.Sensitivity:=DetectionSensitivity;Result.Designs:=FDesignEditor.Designs;end;
procedure TFormRhythmShooterSettings.SetBusy(Value:Boolean);
var I:Integer;
begin
  for I:=0 to ComponentCount-1 do
    if (Components[I] is TButton) or (Components[I] is TEdit) or (Components[I] is TComboBox) or (Components[I] is TTrackBar) then
      TControl(Components[I]).Enabled:=not Value;
  if FDesignEditor<>nil then FDesignEditor.Enabled:=not Value;
  if Value then begin FStatus.Caption:='解析中...';FStatus.Update;end;
end;
procedure TFormRhythmShooterSettings.DesignChanged(Sender:TObject);
begin FState.Designs:=FDesignEditor.Designs;FRenderer.ApplyDesigns(FState.Designs,True);FPreview.Invalidate;end;
procedure TFormRhythmShooterSettings.DesignBusyChanged(Sender:TObject);
var I:Integer;
begin
  for I:=0 to ComponentCount-1 do
    if (Components[I] is TButton) or (Components[I] is TEdit) or (Components[I] is TComboBox) or (Components[I] is TTrackBar) then begin
      TControl(Components[I]).Enabled:=not FDesignEditor.Busy;
      if (Components[I].Name='PreviewPlay') or (Components[I].Name='PreviewPause') or (Components[I].Name='PreviewStop') or (Components[I].Name='Timeline') then TControl(Components[I]).Enabled:=True;
    end;
  if FDesignEditor.Busy then FStatus.Caption:='AI作成中... カスタムデザインの「取消」で中止できます。'
  else FStatus.Caption:='画像は候補を採用した後、この画面の「適用して閉じる」で保存します。';
end;
function TFormRhythmShooterSettings.MusicFile:string;
begin Result:=Trim(FFile.Text);end;
function TFormRhythmShooterSettings.ScrollDirection:Integer;
begin Result:=FDirection.ItemIndex;end;
function TFormRhythmShooterSettings.DetectionSensitivity:Integer;
begin Result:=FSensitivity.Position;end;

procedure TFormRhythmShooterSettings.BeginLoad(Force:Boolean);
begin
  if (FDesignEditor<>nil) and FDesignEditor.Busy then Exit;
  FReloadAt:=0;
  if FWorker<>nil then Exit;
  FPlayer.SetAudio(nil);FWave.SetAudio(nil);FreeAndNil(FAudio);FTime:=0;FPreview.Invalidate;
  if not FileExists(MusicFile) then begin FStatus.Caption:='音楽ファイルが見つかりません。';Exit;end;
  FStatus.Caption:='全曲を解析中...（毎フレーム解析は行いません）';
  SetBusy(True);FTimer.Enabled:=True;
  FWorker:=TRhythmLoadThread.Create(MusicFile,DetectionSensitivity,Force);FWorker.Start;
end;
procedure TFormRhythmShooterSettings.BrowseClick(Sender:TObject);
var Dialog:TOpenDialog;
begin
  Dialog:=TOpenDialog.Create(Self);
  try Dialog.Filter:='音楽ファイル (*.wav;*.mp3)|*.wav;*.mp3';Dialog.Options:=[ofFileMustExist,ofPathMustExist,ofEnableSizing];
    if Dialog.Execute then begin FFile.Text:=Dialog.FileName;BeginLoad;end;
  finally Dialog.Free;end;
end;
procedure TFormRhythmShooterSettings.LoadClick(Sender:TObject);
begin BeginLoad(True);end;
procedure TFormRhythmShooterSettings.PlayClick(Sender:TObject);
begin try if FAudio<>nil then FPlayer.Play;except on E:Exception do FStatus.Caption:=E.Message;end;end;
procedure TFormRhythmShooterSettings.PauseClick(Sender:TObject);
begin try FPlayer.Pause;except on E:Exception do FStatus.Caption:=E.Message;end;end;
procedure TFormRhythmShooterSettings.StopClick(Sender:TObject);
begin try FPlayer.Stop;FTime:=0;FWave.SetTime(0);FPreview.Invalidate;except on E:Exception do FStatus.Caption:=E.Message;end;end;
procedure TFormRhythmShooterSettings.SaveSettings;
begin TFile.WriteAllText(ChangeFileExt(SettingsPath,'.json'),Snapshot.ToJSON,TEncoding.UTF8);end;
procedure TFormRhythmShooterSettings.SaveClick(Sender:TObject);
begin
  if (FWorker<>nil) or FDesignEditor.Busy then Exit;
  try FPlayer.Stop;SaveSettings;if Application.MainForm=Self then Close else ModalResult:=mrOk;
  except on E:Exception do FStatus.Caption:=E.Message;end;
end;
procedure TFormRhythmShooterSettings.SeekChange(Sender:TObject);
begin
  if FUpdating or (FAudio=nil) then Exit;
  try FPlayer.Seek(FAudio.Duration*FSeek.Position/FSeek.Max);FTime:=FPlayer.Position;FWave.SetTime(FTime);FPreview.Invalidate;
  except on E:Exception do FStatus.Caption:=E.Message;end;
end;
procedure TFormRhythmShooterSettings.SettingChange(Sender:TObject);
begin
  if FUpdating then Exit;
  if Sender=FSensitivity then FReloadAt:=GetTickCount64+500;
  if Sender=FDirection then begin FPlayer.Pause;SetBusy(True);try FPreview.Repaint;finally SetBusy(False);end;FStatus.Caption:='方向の動作計画を更新しました（音声PCMは再利用）。';end;
  FPreview.Invalidate;
end;
procedure TFormRhythmShooterSettings.TimerTick(Sender:TObject);
var ErrorText,StateText:string;OldTime:Double;Changed:Boolean;
begin
  try
    OldTime:=FTime;Changed:=False;
    if (FReloadAt<>0) and (GetTickCount64>=FReloadAt) then BeginLoad;
    if (FWorker<>nil) and FWorker.Finished then
    begin
      FWorker.WaitFor;ErrorText:=FWorker.Error;FAudio:=FWorker.TakeAudio;FreeAndNil(FWorker);
      FWave.SetAudio(FAudio);Changed:=True;
      SetBusy(False);
      if ErrorText<>'' then FStatus.Caption:=ErrorText else begin FPlayer.SetAudio(FAudio);
        FStatus.Caption:=Format('解析完了: %.3f 秒 / %d 命中イベント / 素材 %d / PCMキャッシュ再利用 %s',
          [FAudio.Duration,Length(FAudio.Hits),FRenderer.AssetCount,BoolToStr(FAudio.CacheReused,True)]);end;
    end;
    if FAudio<>nil then
    begin
      FTime:=FPlayer.Position;
      if FPlayer.Paused then StateText:='一時停止' else if FPlayer.Playing then StateText:='再生中' else StateText:='停止';
      FClock.Caption:=Format('%s %.3f / %.3f 秒 | 音声デバイス時計',[StateText,FTime,FAudio.Duration]);
      FUpdating:=True;try FSeek.Position:=Round(FTime/Max(0.001,FAudio.Duration)*FSeek.Max);finally FUpdating:=False;end;
    end;
    if Changed or (Abs(FTime-OldTime)>0.00001) then FPreview.Invalidate;
    FWave.SetTime(FTime);
  except on E:Exception do begin SetBusy(False);FStatus.Caption:=E.Message;FTimer.Enabled:=False;end;end;
end;
procedure TFormRhythmShooterSettings.PreviewPaint(Sender:TObject);
var Scale:Double;W,H,X,Y:Integer;
begin
  FFrame.SetSize(FViewWidth,FViewHeight);
  FRenderer.ApplyDesigns(FDesignEditor.Designs);
  FRenderer.Render(FFrame,FAudio,FTime,ScrollDirection,'WAV / MP3 を選択してプレビュー',FState.Zoom/100,FState.X,FState.Y);
  Scale:=Min(FPreview.Width/FViewWidth,FPreview.Height/FViewHeight);W:=Round(FViewWidth*Scale);H:=Round(FViewHeight*Scale);X:=(FPreview.Width-W) div 2;Y:=(FPreview.Height-H) div 2;
  FPreview.Canvas.Brush.Color:=clBlack;FPreview.Canvas.FillRect(FPreview.ClientRect);FPreview.Canvas.StretchDraw(Rect(X,Y,X+W,Y+H),FFrame);
end;
procedure TFormRhythmShooterSettings.WaveMouseDown(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
begin
  if (Button=mbLeft) and (FAudio<>nil) then try FPlayer.Seek(EnsureRange(X/Max(1,FWave.Width),0.0,1.0)*FAudio.Duration);
    except on E:Exception do FStatus.Caption:=E.Message;end;
end;
procedure TFormRhythmShooterSettings.FormDestroy(Sender:TObject);
begin
  if FTimer<>nil then FTimer.Enabled:=False;
  if FWorker<>nil then begin FWorker.Terminate;FWorker.WaitFor;FreeAndNil(FWorker);end;
  FPlayer.Free;FAudio.Free;FRenderer.Free;FFrame.Free;
end;
end.
