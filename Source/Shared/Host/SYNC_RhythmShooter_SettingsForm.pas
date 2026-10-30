unit SYNC_RhythmShooter_SettingsForm;
interface
uses System.Classes, System.SysUtils, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Dialogs, RhythmAudio, RhythmPlayback, RhythmScene, RhythmWaveView, RhythmSettings,RhythmDesignFrame,RhythmControls,RhythmStyles,RhythmPlanRef,RhythmPrepare;
type
  TFormRhythmShooterSettings = class(TForm)
    procedure FormCreate(Sender:TObject);
    procedure FormDestroy(Sender:TObject);
  private
    FFile:TEdit;
    FDirection,FStyle:TComboBox;
    FSensitivity,FSeek,FFireworksRichness:TTrackBar;
    FOptionsHeader,FOptionsBar,FStylePanel,FDirectionPanel,FSensitivityPanel,FFireworksRow:TPanel;
    FStyleLabel,FSensitivityLabel,FRichnessLabel:TLabel;
    FLayoutBusy:Boolean;
    FRichnessLevel:TLabel;
    FStatus,FClock,FLevel,FDirectionLabel:TLabel;
    FApply,FPlay:TButton;
    FLastPreparationError:string;
    FPrepareStarted:UInt64;
    FPreview:TRhythmPreviewSurface;
    FPages:TPageControl;
    FAnimationTab,FDesignTab:TRhythmButton;
    FWave:TRhythmWaveView;
    FTimer:TTimer;
    FFrame:TBitmap;
    FRenderer:TRhythmRenderer;
    FAudio:TRhythmAudio;
    FWorker:TRhythmPrepareThread;
    FRequestSerial:Cardinal;
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
    procedure UpdateStyleControls;
    procedure CancelLoad;
    function SelectedStyle:TRhythmStyle;
    function SelectedVariant:Integer;
    function Ready:Boolean;
    function CanApplyPrepared:Boolean;
    procedure SetStatus(const Text:string;Persist:Boolean=False);
    procedure BrowseClick(Sender:TObject);
    procedure LoadClick(Sender:TObject);
    procedure PlayClick(Sender:TObject);
    procedure UpdatePlayCaption;
    procedure RefreshTransport;
    procedure SeekTo(Seconds:Double);
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
uses Winapi.Windows, System.Math, System.Types, System.UITypes, System.IniFiles, System.IOUtils, RhythmPaths,RhythmProduct;
{$R *.dfm}

procedure TFormRhythmShooterSettings.FormCreate(Sender:TObject);
var Top,MusicRow,Transport,TransportButtons,Bottom,Navigation:TPanel;
  B:TButton;Ini:TMemIniFile;Pages:TPageControl;Animation,Design:TTabSheet;WorkArea:TRect;
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
  Caption:=ProductTitle+' 設定';DoubleBuffered:=True;FUpdating:=True;
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
  Top:=Panel(Animation,alTop,96);FOptionsHeader:=Top;Top.Padding.SetBounds(S(8),S(4),S(8),S(4));
  MusicRow:=Panel(Top,alTop,44);
  LabelAt(MusicRow,'音楽ファイル',alLeft,96);
  Button(MusicRow,'参照...',alRight,88,BrowseClick);B.Name:='MusicBrowse';
  Button(MusicRow,'解析',alRight,88,LoadClick);B.Name:='MusicAnalyze';TRhythmButton(B).Primary:=True;
  FFile:=TEdit.Create(Self);FFile.Parent:=MusicRow;FFile.Name:='MusicFile';FFile.AutoSize:=False;
  FFile.AlignWithMargins:=True;FFile.Margins.SetBounds(S(6),S(6),S(6),S(6));FFile.Align:=alClient;
  FOptionsBar:=Panel(Top,alTop,44);FOptionsBar.Name:='AnimationOptions';FOptionsBar.Top:=S(44);
  FStylePanel:=Panel(FOptionsBar,alNone,44);FStylePanel.Name:='StyleOptions';
  FStyleLabel:=LabelAt(FStylePanel,'スタイル',alNone,56);FStyleLabel.Name:='StyleCaption';
  FStyle:=TRhythmComboBox.Create(Self);FStyle.Parent:=FStylePanel;FStyle.Name:='AnimationStyle';
  FStyle.Width:=S(160);FStyle.ShowHint:=True;
  FStyle.Hint:='スタイル変更時は動作計画を再準備します。音声キャッシュは再利用します。';
  FStyle.Items.Add(StyleTitle(rsShooting));FStyle.Items.Add(StyleTitle(rsBall));FStyle.Items.Add(StyleTitle(rsFireworks));FStyle.Items.Add(StyleTitle(rsRunner));
  FStyle.ItemIndex:=Ord(FState.Style);FStyle.OnChange:=SettingChange;FStyleLabel.FocusControl:=FStyle;
  FDirectionPanel:=Panel(FOptionsBar,alNone,44);FDirectionPanel.Name:='DirectionOptions';
  FDirectionLabel:=LabelAt(FDirectionPanel,'方向',alNone,40);FDirectionLabel.Name:='DirectionCaption';
  FDirection:=TRhythmComboBox.Create(Self);FDirection.Parent:=FDirectionPanel;FDirection.Name:='ScrollDirection';
  FDirection.Width:=S(130);FDirection.Items.Add('縦スクロール');FDirection.Items.Add('横スクロール');
  FDirection.ItemIndex:=0;FDirection.OnChange:=SettingChange;FDirectionLabel.FocusControl:=FDirection;
  FSensitivityPanel:=Panel(FOptionsBar,alNone,44);FSensitivityPanel.Name:='SensitivityOptions';
  FSensitivityLabel:=LabelAt(FSensitivityPanel,'解析感度',alNone,56);FSensitivityLabel.Name:='SensitivityCaption';
  FSensitivity:=TRhythmTrackBar.Create(Self);FSensitivity.Parent:=FSensitivityPanel;FSensitivity.Name:='Sensitivity';
  FSensitivity.TickStyle:=tsNone;FSensitivity.Min:=1;FSensitivity.Max:=100;FSensitivity.Position:=50;
  FSensitivity.Frequency:=10;FSensitivity.OnChange:=SettingChange;FSensitivityLabel.FocusControl:=FSensitivity;
  FLevel:=LabelAt(FSensitivityPanel,'50',alNone,32);FLevel.Alignment:=taRightJustify;
  FFireworksRow:=Panel(FOptionsBar,alNone,44);FFireworksRow.Name:='FireworksOptions';
  FRichnessLabel:=LabelAt(FFireworksRow,'華やかさ',alNone,56);FRichnessLabel.Name:='RichnessCaption';
  FFireworksRichness:=TRhythmTrackBar.Create(Self);FFireworksRichness.Parent:=FFireworksRow;FFireworksRichness.Name:='FireworksRichness';
  FFireworksRichness.Min:=0;FFireworksRichness.Max:=100;FFireworksRichness.Position:=FIREWORKS_DEFAULT_RICHNESS;
  FFireworksRichness.TickStyle:=tsNone;FFireworksRichness.Frequency:=10;
  FFireworksRichness.ShowHint:=True;FFireworksRichness.Hint:='同時打ち上げ数・広がり・火花量。変更後は花火計画を再準備します（音声キャッシュは再利用）。';
  FFireworksRichness.OnChange:=SettingChange;FRichnessLabel.FocusControl:=FFireworksRichness;
  FRichnessLevel:=LabelAt(FFireworksRow,'50',alNone,32);FRichnessLevel.Alignment:=taRightJustify;FRichnessLevel.ShowHint:=True;
  FOptionsBar.OnResize:=LayoutOptions;
  Bottom:=Panel(Self,alBottom,52);Bottom.Padding.SetBounds(S(12),0,S(12),0);
  Button(Bottom,'適用して閉じる',alRight,170,SaveClick);B.Name:='ApplySettings';TRhythmButton(B).Primary:=True;FApply:=B;
  FStatus:=LabelAt(Bottom,'WAV / MP3 を選択してください。',alClient,400);
  FStatus.ShowHint:=True;FStatus.WordWrap:=True;FStatus.AlignWithMargins:=True;FStatus.Margins.SetBounds(S(6),S(6),S(12),S(6));
  Transport:=Panel(Animation,alBottom,128);Transport.Padding.SetBounds(S(8),S(4),S(8),S(4));
  FWave:=TRhythmWaveView.Create(Self);FWave.Name:='MusicWaveform';FWave.Parent:=Transport;FWave.Align:=alTop;FWave.Height:=S(42);FWave.OnMouseDown:=WaveMouseDown;
  FSeek:=TRhythmTrackBar.Create(Self);FSeek.Parent:=Transport;FSeek.Name:='Timeline';FSeek.Height:=S(32);FSeek.Align:=alTop;
  FSeek.Min:=0;FSeek.Max:=100000;FSeek.TickStyle:=tsNone;FSeek.OnChange:=SeekChange;
  TransportButtons:=Panel(Transport,alBottom,44);
  Button(TransportButtons,'再生',alLeft,100,PlayClick);B.Name:='PreviewPlay';FPlay:=B;
  Button(TransportButtons,'停止',alLeft,90,StopClick);B.Name:='PreviewStop';B.Left:=S(120);
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
  FStyle.ItemIndex:=Ord(FState.Style);FFireworksRichness.Position:=FState.FireworksRichness;FFile.OnChange:=SettingChange;
  if (FFile.Text<>'') and FileExists(FFile.Text) then FReloadAt:=GetTickCount64+100;
  FDesignEditor.Designs:=FState.Designs;Pages.ActivePage:=Animation;FUpdating:=False;FTimer.Enabled:=True;
  ApplyRhythmColors(Self);Color:=RhythmBackground;Navigation.Color:=RhythmBackground;Bottom.Color:=RhythmBackground;
  FStatus.Font.Color:=RhythmMuted;FLevel.Font.Color:=RhythmAccent;FRichnessLevel.Font.Color:=RhythmAccent;PageChanged(Self);LayoutOptions(Self);UpdateStyleControls;ApplyRhythmTitleBar(Self);
end;
procedure TFormRhythmShooterSettings.Navigate(Sender:TObject);
begin FPages.ActivePageIndex:=TControl(Sender).Tag;PageChanged(Self);end;
procedure TFormRhythmShooterSettings.PageChanged(Sender:TObject);
begin
  if FPages=nil then Exit;
  FAnimationTab.Selected:=FPages.ActivePageIndex=0;FDesignTab.Selected:=FPages.ActivePageIndex=1;
end;
procedure TFormRhythmShooterSettings.LayoutOptions(Sender:TObject);
var Groups:array[0..3] of TPanel;Widths:array[0..3] of Integer;
  I,W,H,X,Y,Gap,Total,Extra,Numbers,BarHeight:Integer;
  function S(Value:Integer):Integer;
  begin Result:=MulDiv(Value,CurrentPPI,96);end;
  procedure Combo(LabelControl:TLabel;Control:TComboBox;LabelWidth:Integer);
  begin
    LabelControl.SetBounds(0,0,S(LabelWidth),H);
    Control.SetBounds(S(LabelWidth+6),Max(0,(H-Control.Height) div 2),
      Max(1,Control.Parent.ClientWidth-S(LabelWidth+6)),Control.Height);
  end;
  procedure Slider(LabelControl,ValueControl:TLabel;Control:TTrackBar);
  var CW:Integer;
  begin
    CW:=Control.Parent.ClientWidth;LabelControl.SetBounds(0,0,S(56),H);
    ValueControl.SetBounds(CW-S(32),0,S(32),H);
    Control.SetBounds(S(60),S(6),Max(1,CW-S(96)),Max(1,H-S(12)));
  end;
begin
  if FLayoutBusy or (FRichnessLevel=nil) or (FOptionsBar=nil) then Exit;
  FLayoutBusy:=True;
  try
    Groups[0]:=FStylePanel;Groups[1]:=FDirectionPanel;Groups[2]:=FSensitivityPanel;Groups[3]:=FFireworksRow;
    Widths[0]:=S(222);Widths[1]:=S(176);Widths[2]:=S(170);Widths[3]:=S(170);
    W:=Max(1,FOptionsBar.ClientWidth);H:=S(44);Gap:=S(8);Total:=0;Numbers:=1;
    if FFireworksRow.Visible then Inc(Numbers);
    for I:=0 to 3 do if Groups[I].Visible then begin if Total>0 then Inc(Total,Gap);Inc(Total,Widths[I]);end;
    if W>Total then begin Extra:=(W-Total) div Numbers;Inc(Widths[2],Extra);if FFireworksRow.Visible then Inc(Widths[3],Extra);end;
    X:=0;Y:=0;
    for I:=0 to 3 do if Groups[I].Visible then begin
      if (X>0) and (X+Widths[I]>W) then begin X:=0;Inc(Y,H);end;
      Groups[I].SetBounds(X,Y,Min(W,Widths[I]),H);Inc(X,Widths[I]+Gap);
    end;
    BarHeight:=Y+H;
    if FOptionsBar.Height<>BarHeight then FOptionsBar.Height:=BarHeight;
    if FOptionsHeader.Height<>S(52)+BarHeight then FOptionsHeader.Height:=S(52)+BarHeight;
    Combo(FStyleLabel,FStyle,56);Combo(FDirectionLabel,FDirection,40);
    Slider(FSensitivityLabel,FLevel,FSensitivity);Slider(FRichnessLabel,FRichnessLevel,FFireworksRichness);
  finally FLayoutBusy:=False;end;
end;
procedure TFormRhythmShooterSettings.Configure(const FileName:string;Direction,Sensitivity:Integer);
var State:TRhythmSettings;
begin State:=TRhythmSettings.Defaults;State.Music:=FileName;State.Direction:=Direction;State.Sensitivity:=Sensitivity;ConfigureState(State);end;
procedure TFormRhythmShooterSettings.ConfigureState(const State:TRhythmSettings;ViewWidth,ViewHeight:Integer);
begin
  CancelLoad;FLastPreparationError:='';FPlayer.SetAudio(nil);FWave.SetAudio(nil);FreeAndNil(FAudio);
  FState:=State;FViewWidth:=Max(1,ViewWidth);FViewHeight:=Max(1,ViewHeight);
  FDesignEditor.Designs:=State.Designs;
  FUpdating:=True;
  try FStyle.ItemIndex:=Ord(State.Style);FFile.Text:=State.Music;FDirection.ItemIndex:=EnsureRange(State.Direction,0,1);FSensitivity.Position:=EnsureRange(State.Sensitivity,1,100);FFireworksRichness.Position:=EnsureRange(State.FireworksRichness,0,100);
  finally FUpdating:=False;end;
  UpdateStyleControls;FPreview.Invalidate;
  if (State.Style<>rsShooting) and (State.Plan.Version<>StylePlanVersion(State.Style)) then
    FStatus.Caption:='軌道・花火計画を更新しました。音声キャッシュを再利用して再準備します。';
  FReloadAt:=0;if (State.Music<>'') and FileExists(State.Music) then FReloadAt:=GetTickCount64+100;
end;
function TFormRhythmShooterSettings.Snapshot:TRhythmSettings;
begin
  Result:=FState;Result.Style:=SelectedStyle;Result.Music:=MusicFile;Result.Direction:=ScrollDirection;Result.Sensitivity:=DetectionSensitivity;Result.FireworksRichness:=FFireworksRichness.Position;Result.Designs:=FDesignEditor.Designs;
  if not CanApplyPrepared then Result.Plan:=Default(TRhythmPlanRef);
end;
procedure TFormRhythmShooterSettings.SetBusy(Value:Boolean);
var I:Integer;
begin
  for I:=0 to ComponentCount-1 do
    if (Components[I] is TButton) or (Components[I] is TEdit) or (Components[I] is TComboBox) or (Components[I] is TTrackBar) then
      TControl(Components[I]).Enabled:=not Value;
  if FDesignEditor<>nil then FDesignEditor.Enabled:=not Value and (SelectedStyle=rsShooting);
  UpdateStyleControls;
  if Value then begin SetStatus('解析・動作計画を準備中...');FStatus.Update;end;
end;
function TFormRhythmShooterSettings.SelectedStyle:TRhythmStyle;
begin Result:=ProductDefaultStyle;if (FStyle<>nil) and (FStyle.ItemIndex>=Ord(Low(TRhythmStyle))) and (FStyle.ItemIndex<=Ord(High(TRhythmStyle))) then Result:=TRhythmStyle(FStyle.ItemIndex);end;
function TFormRhythmShooterSettings.SelectedVariant:Integer;
begin Result:=StyleVariant(SelectedStyle,FFireworksRichness.Position);end;
function TFormRhythmShooterSettings.Ready:Boolean;
begin
  Result:=(FAudio<>nil) and (FWorker=nil) and (FReloadAt=0);
  if Result then Result:=SameFileName(FAudio.Source,ExpandFileName(MusicFile)) and FState.Plan.Matches(FAudio.Key,DetectionSensitivity,ScrollDirection,SelectedStyle,SelectedVariant);
  if Result and (SelectedStyle<>rsShooting) then Result:=ValidDigest(FState.Plan.Digest);
end;
function TFormRhythmShooterSettings.CanApplyPrepared:Boolean;
begin Result:=Ready;if Result then Result:=AudioSourceUnchanged(FAudio);end;
procedure TFormRhythmShooterSettings.SetStatus(const Text:string;Persist:Boolean);
var Path,Line:string;
begin
  if FStatus.Caption<>Text then FStatus.Caption:=Text;FStatus.Hint:=Text;
  if not Persist then Exit;
  try
    Path:=TPath.Combine(ExtractFileDir(SettingsPath),'Preparation.log');
    Line:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)+' | '+ProductId+' | '+StyleId(SelectedStyle)+
      ' v'+IntToStr(StylePlanVersion(SelectedStyle))+' | sensitivity '+IntToStr(DetectionSensitivity)+' | variant '+IntToStr(SelectedVariant)+' | direction '+IntToStr(ScrollDirection)+' | request '+IntToStr(FRequestSerial)+' | '+Text+sLineBreak;
    TFile.AppendAllText(Path,Line,TEncoding.UTF8);
  except
    // A diagnostic write must never prevent settings from being saved.
  end;
end;
procedure TFormRhythmShooterSettings.UpdateStyleControls;
var I,DirectionIndex:Integer;IsReady,WasUpdating:Boolean;Control:TControl;VerticalText,HorizontalText:string;
begin
  FState.Style:=SelectedStyle;FState.FireworksRichness:=FFireworksRichness.Position;
  FFireworksRow.Visible:=SelectedStyle=rsFireworks;FDirectionPanel.Visible:=SelectedStyle<>rsRunner;
  FRichnessLevel.Caption:=IntToStr(FFireworksRichness.Position);
  if FFireworksRichness.Position<35 then FRichnessLevel.Hint:='控えめ' else if FFireworksRichness.Position<70 then FRichnessLevel.Hint:='標準' else FRichnessLevel.Hint:='華やか';
  LayoutOptions(Self);UpdatePlayCaption;
  if SelectedStyle=rsFireworks then begin VerticalText:='縦構図';HorizontalText:='横構図';end
  else begin VerticalText:='縦スクロール';HorizontalText:='横スクロール';end;
  if (FDirection<>nil) and (FDirection.Items.Count=2) and (FDirection.Items[0]<>VerticalText) then begin
    WasUpdating:=FUpdating;DirectionIndex:=FDirection.ItemIndex;FUpdating:=True;
    try FDirection.Items[0]:=VerticalText;FDirection.Items[1]:=HorizontalText;FDirection.ItemIndex:=DirectionIndex;
    finally FUpdating:=WasUpdating;end;
  end;
  if FDirectionLabel<>nil then begin if SelectedStyle=rsFireworks then FDirectionLabel.Caption:='構図' else FDirectionLabel.Caption:='方向';end;
  if FDesignTab<>nil then FDesignTab.Enabled:=(SelectedStyle=rsShooting) and (FWorker=nil);
  if FDesignEditor<>nil then FDesignEditor.Enabled:=(SelectedStyle=rsShooting) and (FWorker=nil);
  if (SelectedStyle<>rsShooting) and (FPages<>nil) then begin FPages.ActivePageIndex:=0;PageChanged(Self);end;
  IsReady:=Ready;
  if FApply<>nil then begin
    FApply.Enabled:=not FDesignEditor.Busy;
    if IsReady or (MusicFile='') then FApply.Caption:='適用して閉じる' else FApply.Caption:='設定のみ保存して閉じる';
  end;
  for I:=0 to ComponentCount-1 do if Components[I] is TControl then begin
    Control:=TControl(Components[I]);
    if (Control.Name='PreviewPlay') or (Control.Name='PreviewStop') or (Control.Name='Timeline') then Control.Enabled:=IsReady;
    if (Control.Name='MusicAnalyze') and (Control is TButton) then begin
      if SelectedStyle<>rsShooting then begin TButton(Control).Caption:='準備/再試行';Control.Width:=MulDiv(112,CurrentPPI,96);end
      else begin TButton(Control).Caption:='解析';Control.Width:=MulDiv(88,CurrentPPI,96);end;
    end;
  end;
end;
procedure TFormRhythmShooterSettings.CancelLoad;
begin
  Inc(FRequestSerial);if FWorker<>nil then begin FWorker.Terminate;FWorker.WaitFor;FreeAndNil(FWorker);end;
end;
procedure TFormRhythmShooterSettings.DesignChanged(Sender:TObject);
begin FState.Designs:=FDesignEditor.Designs;if FUpdating then Exit;FRenderer.ApplyDesigns(FState.Designs,True);FPreview.Invalidate;end;
procedure TFormRhythmShooterSettings.DesignBusyChanged(Sender:TObject);
var I:Integer;
begin
  for I:=0 to ComponentCount-1 do
    if (Components[I] is TButton) or (Components[I] is TEdit) or (Components[I] is TComboBox) or (Components[I] is TTrackBar) then begin
      TControl(Components[I]).Enabled:=not FDesignEditor.Busy;
      if (Components[I].Name='PreviewPlay') or (Components[I].Name='PreviewStop') or (Components[I].Name='Timeline') then TControl(Components[I]).Enabled:=True;
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
var Existing:TRhythmAudio;
begin
  if ((FDesignEditor<>nil) and FDesignEditor.Busy) or (FWorker<>nil) then Exit;
  FReloadAt:=0;FState.Plan:=Default(TRhythmPlanRef);Inc(FRequestSerial);FLastPreparationError:='';FPrepareStarted:=GetTickCount64;
  FPlayer.SetAudio(nil);FWave.SetAudio(nil);Existing:=FAudio;FAudio:=nil;FTime:=0;FPreview.Invalidate;
  if not FileExists(MusicFile) then begin
    Existing.Free;FLastPreparationError:='音楽ファイルが見つかりません。参照から選び直してください。設定のみの保存は可能です。';
    SetStatus(FLastPreparationError,True);SetBusy(False);Exit;
  end;
  SetBusy(True);FTimer.Enabled:=True;
  try
    FWorker:=TRhythmPrepareThread.Create(MusicFile,DetectionSensitivity,ScrollDirection,SelectedStyle,Force,Existing,FRequestSerial,SelectedVariant);
    SetStatus('準備開始: '+MusicFile,True);FWorker.Start;
  except
    on E:Exception do begin
      if FWorker<>nil then begin FWorker.Terminate;FreeAndNil(FWorker);end else Existing.Free;
      FLastPreparationError:='準備を開始できません: '+E.ClassName+': '+E.Message;SetStatus(FLastPreparationError,True);SetBusy(False);
    end;
  end;
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
begin BeginLoad(SelectedStyle=rsShooting);end;
procedure TFormRhythmShooterSettings.UpdatePlayCaption;
var Text:string;
begin
  if FPlay=nil then Exit;
  if (FPlayer<>nil) and FPlayer.Playing and not FPlayer.Paused then Text:='一時停止'
  else Text:='再生';
  if FPlay.Caption<>Text then FPlay.Caption:=Text;
end;
procedure TFormRhythmShooterSettings.RefreshTransport;
var StateText,ClockText:string;WasUpdating:Boolean;
begin
  FTime:=FPlayer.Position;UpdatePlayCaption;
  if FPlayer.Paused then StateText:='一時停止' else if FPlayer.Playing then StateText:='再生中' else StateText:='停止';
  ClockText:=Format('%s %.3f / %.3f 秒 | 音声デバイス時計',[StateText,FTime,FPlayer.Duration]);
  if FClock.Caption<>ClockText then FClock.Caption:=ClockText;
  WasUpdating:=FUpdating;FUpdating:=True;
  try FSeek.Position:=EnsureRange(Round(FTime/Max(0.001,FPlayer.Duration)*FSeek.Max),0,FSeek.Max);
  finally FUpdating:=WasUpdating;end;
  if FAudio<>nil then FWave.SetTime(Min(FTime,FAudio.Duration)) else FWave.SetTime(0);
end;
procedure TFormRhythmShooterSettings.SeekTo(Seconds:Double);
begin
  if not Ready then Exit;
  try
    // Latch end-of-buffer state before preserving playing/paused flags in Seek.
    FPlayer.Position;FPlayer.Seek(EnsureRange(Seconds,0.0,FPlayer.Duration));
    RefreshTransport;FPreview.Invalidate;
  except on E:Exception do begin UpdatePlayCaption;SetStatus('再生位置を変更できません: '+E.Message,True);end;end;
end;
procedure TFormRhythmShooterSettings.PlayClick(Sender:TObject);
begin
  if not Ready then begin
    if FLastPreparationError<>'' then SetStatus(FLastPreparationError+' 準備ボタンで再試行してください。')
    else SetStatus('まだ再生できません。音楽を選択し、準備完了を待ってください。設定だけの保存は可能です。');Exit;
  end;
  try
    FPlayer.Position;
    if FPlayer.Playing and not FPlayer.Paused then FPlayer.Pause else FPlayer.Play;
    RefreshTransport;FPreview.Invalidate;
  except on E:Exception do begin UpdatePlayCaption;FLastPreparationError:='音声再生を変更できません: '+E.Message;SetStatus(FLastPreparationError,True);end;end;
end;
procedure TFormRhythmShooterSettings.StopClick(Sender:TObject);
begin
  try FPlayer.Stop;RefreshTransport;FPreview.Invalidate;
  except on E:Exception do begin UpdatePlayCaption;SetStatus(E.Message);end;end;
end;
procedure TFormRhythmShooterSettings.SaveSettings;
var Path,Temp:string;Id:TGUID;
begin
  Path:=ChangeFileExt(SettingsPath,'.json');CreateGUID(Id);Temp:=Path+'.'+GUIDToString(Id)+'.tmp';
  try
    TFile.WriteAllText(Temp,Snapshot.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(Temp),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally if FileExists(Temp) then TFile.Delete(Temp);end;
end;
procedure TFormRhythmShooterSettings.SaveClick(Sender:TObject);
var Pending:Boolean;Notice:string;
begin
  if FDesignEditor.Busy then begin SetStatus('AI作成中です。素材画面で採用または取消を終えてから保存してください。');Exit;end;
  Pending:=(MusicFile<>'') and not CanApplyPrepared;
  if Pending then begin
    CancelLoad;FReloadAt:=0;FState.Plan:=Default(TRhythmPlanRef);SetBusy(False);
  end;
  try
    try FPlayer.Stop;except on E:Exception do SetStatus('音声停止: '+E.Message+' 設定保存は続行します。',True);end;
    SaveSettings;
    if Pending then begin
      Notice:='音楽・スタイル・感度などの設定は保存しました。動作計画は未準備なので映像はまだ適用されません。設定画面を再度開き、準備ボタンで準備完了後に適用してください。';
      if FLastPreparationError<>'' then Notice:=Notice+sLineBreak+sLineBreak+'直前の原因: '+FLastPreparationError;
      SetStatus(Notice,True);MessageDlg(Notice,mtInformation,[mbOK],0);
    end else SetStatus('準備済みの設定を保存しました。',True);
    if Application.MainForm=Self then Close else ModalResult:=mrOk;
  except on E:Exception do begin
    FLastPreparationError:='設定を保存できません: '+E.ClassName+': '+E.Message;
    SetStatus(FLastPreparationError,True);SetBusy(False);
  end;end;
end;
procedure TFormRhythmShooterSettings.SeekChange(Sender:TObject);
begin
  if FUpdating or not Ready then Exit;
  SeekTo(FPlayer.Duration*FSeek.Position/Max(1,FSeek.Max));
end;
procedure TFormRhythmShooterSettings.SettingChange(Sender:TObject);
begin
  if (Sender=FSensitivity) and (FLevel<>nil) then FLevel.Caption:=IntToStr(FSensitivity.Position);
  if FUpdating then Exit;
  FState.FireworksRichness:=FFireworksRichness.Position;
  FState.Plan:=Default(TRhythmPlanRef);UpdateStyleControls;FWave.SetAudio(nil);FStatus.Caption:='設定を変更しました。解析・計画を準備します。';
  try FPlayer.Pause;except on E:Exception do FStatus.Caption:=E.Message;end;UpdatePlayCaption;
  if FWorker<>nil then begin Inc(FRequestSerial);FWorker.Terminate;FReloadAt:=GetTickCount64+100;end
  else if (Sender=FStyle) or (Sender=FDirection) then BeginLoad(False)
  else FReloadAt:=GetTickCount64+500;
  FPreview.Invalidate;
end;
procedure TFormRhythmShooterSettings.TimerTick(Sender:TObject);
var ErrorText,ProgressText,Summary:string;OldTime,PreviewEnd:Double;Changed,CurrentRequest:Boolean;Seconds:UInt64;
begin
  try
    OldTime:=FTime;Changed:=False;
    if (FReloadAt<>0) and (GetTickCount64>=FReloadAt) then BeginLoad;
    if (FWorker<>nil) and not FWorker.Finished then begin
      Seconds:=(GetTickCount64-FPrepareStarted) div 1000;
      case FWorker.Stage of
        2:begin
          if SelectedStyle=rsFireworks then ProgressText:='打ち上げと開花を準備中'
          else if SelectedStyle=rsRunner then ProgressText:='足場とジャンプ軌道を準備中'
          else if SelectedStyle=rsBall then ProgressText:='障害物と軌道を準備中'
          else ProgressText:='動作計画を準備中';
        end;
        3:ProgressText:='動作計画を保存中';
        4:ProgressText:='動作計画を再読込して確認中';
      else ProgressText:='音声解析・キャッシュ読込中';end;
      SetStatus(ProgressText+'... '+UIntToStr(Seconds)+' 秒（設定のみの保存は可能です）');
    end;
    if (FWorker<>nil) and FWorker.Finished then begin
      FWorker.WaitFor;ErrorText:=FWorker.Error;Summary:=FWorker.Summary;PreviewEnd:=FWorker.PreviewEnd;CurrentRequest:=FWorker.RequestId=FRequestSerial;
      if CurrentRequest then begin
        FAudio:=FWorker.TakeAudio;FState.Plan:=FWorker.Plan;
        if ErrorText='' then begin
          if FAudio=nil then ErrorText:='音声準備結果がありません。'
          else if not FState.Plan.Matches(FAudio.Key,DetectionSensitivity,ScrollDirection,SelectedStyle,SelectedVariant) then
            ErrorText:='準備結果と現在の設定が一致しません。準備ボタンで再試行してください。';
        end;
        if ErrorText<>'' then FState.Plan:=Default(TRhythmPlanRef);
      end;
      FreeAndNil(FWorker);FWave.SetAudio(FAudio);Changed:=True;SetBusy(False);
      if not CurrentRequest then SetStatus('古い準備結果を破棄しました。変更後の設定を準備します。',True)
      else if ErrorText<>'' then begin FLastPreparationError:=ErrorText;SetStatus(ErrorText+' 準備ボタンで再試行するか、設定のみ保存できます。',True);end
      else if Ready then begin
        FLastPreparationError:='';FPlayer.SetAudio(FAudio,Max(0.0,PreviewEnd-FAudio.Duration));
        SetStatus(Format('準備完了: %s / %.3f 秒 / %s / PCM再利用 %s',[StyleTitle(SelectedStyle),FAudio.Duration,Summary,BoolToStr(FAudio.CacheReused,True)]),True);
      end;
    end;
    if Ready then RefreshTransport
    else begin FClock.Caption:='動作計画が未準備';UpdatePlayCaption;end;
    if Changed or (Abs(FTime-OldTime)>0.00001) then FPreview.Invalidate;
    if FAudio<>nil then FWave.SetTime(Min(FTime,FAudio.Duration)) else FWave.SetTime(0);
  except on E:Exception do begin
    CancelLoad;FReloadAt:=0;FState.Plan:=Default(TRhythmPlanRef);
    try FPlayer.SetAudio(nil);except end;
    FLastPreparationError:='設定画面の準備処理: '+E.ClassName+': '+E.Message;
    SetBusy(False);SetStatus(FLastPreparationError,True);FPreview.Invalidate;
    // Keep the timer alive so an explicit retry can complete normally.
  end;end;
end;
procedure TFormRhythmShooterSettings.PreviewPaint(Sender:TObject);
var Scale:Double;W,H,X,Y:Integer;HintText:string;
begin
  FFrame.SetSize(FViewWidth,FViewHeight);
  FRenderer.ConfigureStyle(SelectedStyle,FState.Plan);FRenderer.ApplyDesigns(FDesignEditor.Designs);
  if Ready then FRenderer.Render(FFrame,FAudio,FTime,ScrollDirection,'WAV / MP3 を選択してプレビュー',FState.Zoom/100,FState.X,FState.Y)
  else begin
    HintText:='設定画面で動作計画を準備してください。設定のみの保存は可能です。';
    if FLastPreparationError<>'' then HintText:=FLastPreparationError;
    FRenderer.Render(FFrame,nil,0,ScrollDirection,HintText,FState.Zoom/100,FState.X,FState.Y);
  end;
  Scale:=Min(FPreview.Width/FViewWidth,FPreview.Height/FViewHeight);W:=Round(FViewWidth*Scale);H:=Round(FViewHeight*Scale);X:=(FPreview.Width-W) div 2;Y:=(FPreview.Height-H) div 2;
  FPreview.Canvas.Brush.Color:=clBlack;FPreview.Canvas.FillRect(FPreview.ClientRect);FPreview.Canvas.StretchDraw(Rect(X,Y,X+W,Y+H),FFrame);
end;
procedure TFormRhythmShooterSettings.WaveMouseDown(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
begin
  if (Button<>mbLeft) or not Ready or (FAudio=nil) or (FAudio.Duration<=0) or (FWave.ClientWidth<2) then Exit;
  SeekTo(FWave.TimeAt(X));
end;
procedure TFormRhythmShooterSettings.FormDestroy(Sender:TObject);
begin
  if FTimer<>nil then FTimer.Enabled:=False;
  CancelLoad;
  FPlayer.Free;FAudio.Free;FRenderer.Free;FFrame.Free;
end;
end.
