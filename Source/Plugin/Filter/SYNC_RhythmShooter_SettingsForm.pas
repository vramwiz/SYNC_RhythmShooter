unit SYNC_RhythmShooter_SettingsForm;
interface
uses System.Classes, System.SysUtils, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Dialogs, RhythmAudio, RhythmPlayback, RhythmScene, RhythmWaveView, RhythmSettings,RhythmDesignFrame,RhythmControls;
type
  TFormRhythmShooterSettings = class(TForm)
    procedure FormCreate(Sender:TObject);
    procedure FormDestroy(Sender:TObject);
  private
    FFile:TEdit;
    FDirection:TComboBox;
    FSensitivity,FSeek:TTrackBar;
    FStatus,FClock,FLevel:TLabel;
    FPreview:TRhythmPreviewSurface;
    FPages:TPageControl;
    FAnimationTab,FDesignTab:TRhythmButton;
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
    procedure Navigate(Sender:TObject);
    procedure PageChanged(Sender:TObject);
    procedure LayoutOptions(Sender:TObject);
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
var Top,MusicRow,OptionsRow,Transport,TransportButtons,Bottom,Navigation:TPanel;
  L:TLabel;B:TButton;Ini:TMemIniFile;Pages:TPageControl;Animation,Design:TTabSheet;WorkArea:TRect;
  function S(Value:Integer):Integer;
  begin Result:=MulDiv(Value,CurrentPPI,96);end;
  function Panel(Parent:TWinControl;AAlign:TAlign;H:Integer):TPanel;
  begin
    Result:=TPanel.Create(Self);Result.Parent:=Parent;Result.BevelOuter:=bvNone;
    Result.Align:=AAlign;Result.Height:=S(H);Result.DoubleBuffered:=True;
  end;
  function LabelAt(Parent:TWinControl;const Text:string;AAlign:TAlign;W:Integer):TLabel;
  begin
    Result:=TLabel.Create(Self);Result.Parent:=Parent;Result.AutoSize:=False;
    Result.Caption:=Text;Result.Layout:=tlCenter;Result.Align:=AAlign;Result.Width:=S(W);
  end;
  procedure Button(Parent:TWinControl;const Text:string;AAlign:TAlign;W:Integer;Click:TNotifyEvent);
  begin
    B:=TRhythmButton.Create(Self);B.Parent:=Parent;B.Caption:=Text;B.Width:=S(W);
    B.AlignWithMargins:=True;B.Margins.SetBounds(S(6),S(6),S(6),S(6));B.Align:=AAlign;B.OnClick:=Click;
  end;
begin
  Caption:='リズムシューティング 設定 / Revision 4';DoubleBuffered:=True;FUpdating:=True;
  // DFM読込後の現在DPIを使い、動的に生成する寸法もフォントとそろえる。
  WorkArea:=Screen.MonitorFromWindow(Handle).WorkareaRect;
  ClientWidth:=Min(S(1100),Max(S(500),WorkArea.Width-S(24)));
  ClientHeight:=Min(S(760),Max(S(400),WorkArea.Height-S(60)));
  Constraints.MinWidth:=Min(S(850),Width);Constraints.MinHeight:=Min(S(620),Height);
  FState:=TRhythmSettings.Defaults;FViewWidth:=1280;FViewHeight:=720;
  FPlayer:=TRhythmPlayback.Create;FRenderer:=TRhythmRenderer.Create;FFrame:=Vcl.Graphics.TBitmap.Create;FFrame.PixelFormat:=pf32bit;
  Navigation:=Panel(Self,alTop,48);Navigation.Padding.SetBounds(S(12),0,S(12),0);
  Button(Navigation,'アニメーション',alLeft,160,Navigate);FAnimationTab:=TRhythmButton(B);B.Name:='AnimationTab';B.Tag:=0;
  Button(Navigation,'カスタムデザイン',alLeft,160,Navigate);FDesignTab:=TRhythmButton(B);B.Name:='DesignTab';B.Tag:=1;B.Left:=S(180);
  Pages:=TPageControl.Create(Self);Pages.Parent:=Self;Pages.Align:=alClient;Pages.DoubleBuffered:=True;Pages.Style:=tsFlatButtons;
  Pages.AlignWithMargins:=True;Pages.Margins.SetBounds(S(12),0,S(12),S(8));FPages:=Pages;Pages.OnChange:=PageChanged;
  Animation:=TTabSheet.Create(Self);Animation.PageControl:=Pages;Animation.Caption:='アニメーション';Animation.DoubleBuffered:=True;Animation.TabVisible:=False;
  Design:=TTabSheet.Create(Self);Design.PageControl:=Pages;Design.Caption:='カスタムデザイン';Design.DoubleBuffered:=True;Design.TabVisible:=False;
  FDesignEditor:=TRhythmDesignFrame.Create(Self);FDesignEditor.Parent:=Design;FDesignEditor.Align:=alClient;
  FDesignEditor.OnChange:=DesignChanged;FDesignEditor.OnBusyChange:=DesignBusyChanged;
  Top:=Panel(Animation,alTop,104);Top.Padding.SetBounds(S(8),S(4),S(8),S(4));
  MusicRow:=Panel(Top,alTop,44);
  LabelAt(MusicRow,'音楽ファイル',alLeft,96);
  Button(MusicRow,'参照...',alRight,88,BrowseClick);B.Name:='MusicBrowse';
  Button(MusicRow,'解析',alRight,88,LoadClick);B.Name:='MusicAnalyze';TRhythmButton(B).Primary:=True;
  FFile:=TEdit.Create(Self);FFile.Parent:=MusicRow;FFile.Name:='MusicFile';FFile.AutoSize:=False;
  FFile.AlignWithMargins:=True;FFile.Margins.SetBounds(S(6),S(6),S(6),S(6));FFile.Align:=alClient;
  OptionsRow:=Panel(Top,alBottom,44);OptionsRow.OnResize:=LayoutOptions;
  LabelAt(OptionsRow,'スクロール',alLeft,96);
  FDirection:=TRhythmComboBox.Create(Self);FDirection.Parent:=OptionsRow;FDirection.Name:='ScrollDirection';
  FDirection.AlignWithMargins:=True;FDirection.Margins.SetBounds(S(6),0,S(12),0);
  FDirection.Left:=S(100);FDirection.Width:=S(152);FDirection.Align:=alLeft;
  FDirection.Items.Add('縦スクロール');FDirection.Items.Add('横スクロール');FDirection.ItemIndex:=0;FDirection.OnChange:=SettingChange;
  L:=LabelAt(OptionsRow,'解析感度',alLeft,80);L.Left:=S(280);
  FSensitivity:=TRhythmTrackBar.Create(Self);FSensitivity.Parent:=OptionsRow;FSensitivity.Name:='Sensitivity';
  FSensitivity.Left:=S(360);FSensitivity.Width:=S(220);FSensitivity.Align:=alLeft;FSensitivity.TickStyle:=tsNone;
  FSensitivity.AlignWithMargins:=True;FSensitivity.Margins.SetBounds(S(4),S(6),S(4),S(6));
  FSensitivity.Min:=1;FSensitivity.Max:=100;FSensitivity.Position:=50;FSensitivity.Frequency:=10;FSensitivity.OnChange:=SettingChange;
  FLevel:=LabelAt(OptionsRow,'50',alLeft,40);FLevel.Left:=S(600);
  Bottom:=Panel(Self,alBottom,52);Bottom.Padding.SetBounds(S(12),0,S(12),0);
  Button(Bottom,'適用して閉じる',alRight,170,SaveClick);B.Name:='ApplySettings';TRhythmButton(B).Primary:=True;
  FStatus:=LabelAt(Bottom,'WAV / MP3 を選択してください。',alClient,400);
  FStatus.WordWrap:=True;FStatus.AlignWithMargins:=True;FStatus.Margins.SetBounds(S(6),S(6),S(12),S(6));
  Transport:=Panel(Animation,alBottom,128);Transport.Padding.SetBounds(S(8),S(4),S(8),S(4));
  FWave:=TRhythmWaveView.Create(Self);FWave.Parent:=Transport;FWave.Align:=alTop;FWave.Height:=S(42);FWave.OnMouseDown:=WaveMouseDown;
  FSeek:=TRhythmTrackBar.Create(Self);FSeek.Parent:=Transport;FSeek.Name:='Timeline';FSeek.Height:=S(32);FSeek.Align:=alTop;
  FSeek.Min:=0;FSeek.Max:=100000;FSeek.TickStyle:=tsNone;FSeek.OnChange:=SeekChange;
  TransportButtons:=Panel(Transport,alBottom,44);
  Button(TransportButtons,'再生',alLeft,90,PlayClick);B.Name:='PreviewPlay';
  Button(TransportButtons,'一時停止',alLeft,90,PauseClick);B.Name:='PreviewPause';B.Left:=S(110);
  Button(TransportButtons,'停止',alLeft,90,StopClick);B.Name:='PreviewStop';B.Left:=S(220);
  FClock:=LabelAt(TransportButtons,'00:00.000',alRight,240);FClock.Name:='PreviewClock';FClock.Alignment:=taRightJustify;
  FClock.AlignWithMargins:=True;FClock.Margins.SetBounds(S(12),S(6),S(6),S(6));
  FPreview:=TRhythmPreviewSurface.Create(Self);FPreview.Name:='ScenePreview';FPreview.Parent:=Animation;FPreview.Align:=alClient;FPreview.OnPaint:=PreviewPaint;
  FTimer:=TTimer.Create(Self);FTimer.Enabled:=False;FTimer.Interval:=16;FTimer.OnTimer:=TimerTick;
  Ini:=TMemIniFile.Create(SettingsPath,TEncoding.UTF8);
  try
    FFile.Text:=Ini.ReadString('Preview','Music','');FDirection.ItemIndex:=EnsureRange(Ini.ReadInteger('Preview','Direction',0),0,1);
    FSensitivity.Position:=EnsureRange(Ini.ReadInteger('Preview','Sensitivity',50),1,100);
  finally Ini.Free;end;
  if FileExists(ChangeFileExt(SettingsPath,'.json')) then
    if TRhythmSettings.TryJSON(TFile.ReadAllText(ChangeFileExt(SettingsPath,'.json'),TEncoding.UTF8),FState) then
    begin FFile.Text:=FState.Music;FDirection.ItemIndex:=FState.Direction;FSensitivity.Position:=FState.Sensitivity;end;
  if (FFile.Text<>'') and FileExists(FFile.Text) then FReloadAt:=GetTickCount64+100;
  FDesignEditor.Designs:=FState.Designs;Pages.ActivePage:=Animation;FUpdating:=False;FTimer.Enabled:=True;
  ApplyRhythmColors(Self);Color:=RhythmBackground;Navigation.Color:=RhythmBackground;Bottom.Color:=RhythmBackground;
  FStatus.Font.Color:=RhythmMuted;FLevel.Font.Color:=RhythmAccent;PageChanged(Self);LayoutOptions(Self);ApplyRhythmTitleBar(Self);
end;
procedure TFormRhythmShooterSettings.Navigate(Sender:TObject);
begin FPages.ActivePageIndex:=TControl(Sender).Tag;PageChanged(Self);end;
procedure TFormRhythmShooterSettings.PageChanged(Sender:TObject);
begin
  if FPages=nil then Exit;
  FAnimationTab.Selected:=FPages.ActivePageIndex=0;FDesignTab.Selected:=FPages.ActivePageIndex=1;
end;
procedure TFormRhythmShooterSettings.LayoutOptions(Sender:TObject);
begin
  if (FDirection<>nil) and (FDirection.Parent<>nil) then
    FDirection.Margins.Top:=Max(0,(FDirection.Parent.ClientHeight-FDirection.Height) div 2);
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
  if (Sender=FSensitivity) and (FLevel<>nil) then FLevel.Caption:=IntToStr(FSensitivity.Position);
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
