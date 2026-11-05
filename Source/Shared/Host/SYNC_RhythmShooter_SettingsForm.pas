unit SYNC_RhythmShooter_SettingsForm;
// 設定と単体Previewの準備UI。ホスト音源は読取専用とし、描画側では解析しない。
interface
uses System.Classes, System.SysUtils, Winapi.Messages, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
Vcl.Graphics, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Dialogs, RhythmAudio, RhythmPlayback, RhythmScene, RhythmWaveView, RhythmSettings,RhythmDesignFrame,RhythmOverlay,RhythmControls,RhythmStyles,RhythmStyleSelection,RhythmPlanRef,RhythmPrepare;
type
  TFormRhythmShooterSettings = class(TForm)
  private
    FFile:TEdit;
    FEqualizer:TCheckBox;FEqualizerRow:TPanel;
    FDirection,FStyle,FCategory:TComboBox;
    FCategoryPanel:TPanel;FCategoryLabel:TLabel;
    FSelection:TStyleSelection;FPreparing:Boolean;
    FSensitivity,FSeek,FBossFrequency,FGameThreshold:TTrackBar;
    FOptionsHeader,FOptionsBar,FStylePanel,FDirectionPanel,FSensitivityPanel,FBossRow,FGameRow:TPanel;
    FStyleLabel,FSensitivityLabel,FBossLabel,FBossValue,FGameLabel,FGameValue:TLabel;
    FLayoutBusy,FLayoutReady,FDpiChanging:Boolean;
    FNavigation,FMusicRow,FBottom,FTransport,FTransportButtons,FAnimationBody:TPanel;
    FAnimationScroll:TScrollBox;
    FMusicLabel:TLabel;
    FBrowse,FAnalyze,FStop:TButton;
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
    FUpdating,FHostMusicMode:Boolean;
    FReloadAt:UInt64;
    FState:TRhythmSettings;
    FViewWidth,FViewHeight:Integer;
    FDesignEditor:TRhythmDesignFrame;
    procedure DesignChanged(Sender:TObject);
    procedure DesignBusyChanged(Sender:TObject);
    procedure Navigate(Sender:TObject);
    procedure PageChanged(Sender:TObject);
    procedure LayoutOptions(Sender:TObject);
    procedure FitToWorkArea;
    procedure SetBusy(Value:Boolean);
    procedure UpdateStyleControls;
    procedure RefreshSelection;
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
  protected
    procedure DoBeforeMonitorDpiChanged(OldDPI,NewDPI:Integer); override;
    procedure DoAfterMonitorDpiChanged(OldDPI,NewDPI:Integer); override;
    procedure CMFontChanged(var Message:TMessage); message CM_FONTCHANGED;
  public
    procedure ScaleForPPI(NewPPI:Integer); override;
    procedure Configure(const FileName:string;Direction,Sensitivity:Integer);
    procedure ConfigureState(const State:TRhythmSettings;ViewWidth:Integer=1280;ViewHeight:Integer=720;HostMusicMode:Boolean=False);
    function Snapshot:TRhythmSettings;
    function MusicFile:string;
    function ScrollDirection:Integer;
    function DetectionSensitivity:Integer;
  published
    // DFMのイベント名解決を維持し、フィールドはすべてメソッドより前に置く。
    procedure FormCreate(Sender:TObject);
    procedure FormDestroy(Sender:TObject);
  end;
implementation
uses Winapi.Windows, System.Math, System.Types, System.UITypes, System.IniFiles, System.IOUtils, RhythmPaths,RhythmProduct;
{$R *.dfm}

procedure TFormRhythmShooterSettings.FormCreate(Sender:TObject);
var
  Top,MusicRow,Transport,TransportButtons,Bottom,Navigation:TPanel;
  B:TButton;
  Ini:TMemIniFile;
  Pages:TPageControl;
  Animation,Design:TTabSheet;
  WorkArea:TRect;
  PanelIndex:Integer;
  function S(Value:Integer):Integer;
  begin Result:=MulDiv(Value,CurrentPPI,96);
  end;
  function Panel(Parent:TWinControl;AAlign:TAlign;H:Integer):TPanel;
  begin
    Result:=TPanel.Create(Self);
    Result.Parent:=Parent;
    Result.BevelOuter:=bvNone;
    Result.Align:=AAlign;
    Result.Height:=S(H);
    Result.DoubleBuffered:=True;
  end;
  function LabelAt(Parent:TWinControl;const Text:string;AAlign:TAlign;W:Integer):TLabel;
  begin
    Result:=TLabel.Create(Self);
    Result.Parent:=Parent;
    Result.AutoSize:=False;
    Result.Caption:=Text;
    Result.Layout:=tlCenter;
    Result.Align:=AAlign;
    Result.Width:=S(W);
  end;
  procedure Button(Parent:TWinControl;const Text:string;AAlign:TAlign;W:Integer;Click:TNotifyEvent);
  begin
    B:=TRhythmButton.Create(Self);
    B.Parent:=Parent;
    B.Caption:=Text;
    B.Width:=S(W);
    B.AlignWithMargins:=True;
    B.Margins.SetBounds(S(6),S(6),S(6),S(6));
    B.Align:=AAlign;
    B.OnClick:=Click;
  end;
begin
  if ProductDefaultStyle in [rsRhythmGame,rsStepGame] then
    Caption:=StyleTitle(ProductDefaultStyle)+' 設定'
  else Caption:=ProductTitle+' 設定';
  DoubleBuffered:=True;
  FUpdating:=True;
  // DFM読込後の現在DPIを使い、動的に生成する寸法もフォントとそろえる。
  WorkArea:=Screen.MonitorFromWindow(Handle).WorkareaRect;
  ClientWidth:=Min(S(1100),Max(1,WorkArea.Width-S(24)-(Width-ClientWidth)));
  ClientHeight:=Min(S(760),Max(1,WorkArea.Height-S(24)-(Height-ClientHeight)));
  Constraints.MinWidth:=Min(S(520),Width);
  Constraints.MinHeight:=Min(S(360),Height);
  FState:=TRhythmSettings.Defaults;FSelection:=TStyleSelection.FromSaved(FState.Style,FState.Direction);
  FViewWidth:=1280;
  FViewHeight:=720;
  FPlayer:=TRhythmPlayback.Create;
  FRenderer:=TRhythmRenderer.Create;
  FFrame:=Vcl.Graphics.TBitmap.Create;
  FFrame.PixelFormat:=pf32bit;
  Navigation:=Panel(Self,alTop,48);
  FNavigation:=Navigation;
  Navigation.Padding.SetBounds(S(12),0,S(12),0);
  Button(Navigation,'アニメーション',alLeft,160,Navigate);
  FAnimationTab:=TRhythmButton(B);
  B.Name:='AnimationTab';
  B.Tag:=0;
  Button(Navigation,'カスタムデザイン',alLeft,160,Navigate);
  FDesignTab:=TRhythmButton(B);
  B.Name:='DesignTab';
  B.Tag:=1;
  B.Left:=S(180);
  Pages:=TPageControl.Create(Self);
  Pages.Parent:=Self;
  Pages.Align:=alClient;
  Pages.DoubleBuffered:=True;
  Pages.Style:=tsFlatButtons;
  Pages.AlignWithMargins:=True;
  Pages.Margins.SetBounds(S(12),0,S(12),S(8));
  FPages:=Pages;
  Pages.OnChange:=PageChanged;
  Animation:=TTabSheet.Create(Self);
  Animation.PageControl:=Pages;
  Animation.Caption:='アニメーション';
  Animation.DoubleBuffered:=True;
  Animation.TabVisible:=False;
  Design:=TTabSheet.Create(Self);
  Design.PageControl:=Pages;
  Design.Caption:='カスタムデザイン';
  Design.DoubleBuffered:=True;
  Design.TabVisible:=False;
  FDesignEditor:=TRhythmDesignFrame.Create(Self);
  FDesignEditor.Parent:=Design;
  FDesignEditor.Align:=alClient;
  FDesignEditor.OnChange:=DesignChanged;
  FDesignEditor.OnBusyChange:=DesignBusyChanged;
  FAnimationScroll:=TScrollBox.Create(Self);
  FAnimationScroll.Parent:=Animation;
  FAnimationScroll.Align:=alClient;
  FAnimationScroll.BorderStyle:=bsNone;
  FAnimationScroll.HorzScrollBar.Visible:=False;
  FAnimationScroll.VertScrollBar.Tracking:=True;
  FAnimationBody:=Panel(FAnimationScroll,alTop,500);
  FAnimationBody.Name:='AnimationBody';
  Top:=Panel(FAnimationBody,alTop,96);
  FOptionsHeader:=Top;
  Top.Padding.SetBounds(S(8),S(4),S(8),S(4));
  MusicRow:=Panel(Top,alTop,44);
  FMusicRow:=MusicRow;
  FMusicLabel:=LabelAt(MusicRow,'音楽ファイル',alLeft,96);
  Button(MusicRow,'参照...',alRight,88,BrowseClick);
  B.Name:='MusicBrowse';
  FBrowse:=B;
  Button(MusicRow,'解析',alRight,88,LoadClick);
  B.Name:='MusicAnalyze';
  FAnalyze:=B;
  TRhythmButton(B).Primary:=True;
  FFile:=TEdit.Create(Self);
  FFile.Parent:=MusicRow;
  FFile.Name:='MusicFile';
  FFile.AutoSize:=False;
  FFile.AlignWithMargins:=True;
  FFile.Margins.SetBounds(S(6),S(6),S(6),S(6));
  FFile.Align:=alClient;
  FOptionsBar:=Panel(Top,alTop,44);
  FOptionsBar.Name:='AnimationOptions';
  FOptionsBar.Top:=S(44);
  FCategoryPanel:=Panel(FOptionsBar,alNone,44);FCategoryPanel.Name:='CategoryOptions';
  FCategoryLabel:=LabelAt(FCategoryPanel,'大分類',alNone,56);FCategoryLabel.Name:='CategoryCaption';
  FCategory:=TRhythmComboBox.Create(Self);FCategory.Parent:=FCategoryPanel;FCategory.Name:='AnimationCategory';
  for PanelIndex:=Ord(Low(TRhythmStyleGroup)) to Ord(High(TRhythmStyleGroup)) do FCategory.Items.Add(StyleGroupTitle(TRhythmStyleGroup(PanelIndex)));
  FCategory.ItemIndex:=Ord(FSelection.Group);FCategory.OnChange:=SettingChange;FCategoryLabel.FocusControl:=FCategory;
  FStylePanel:=Panel(FOptionsBar,alNone,44);
  FStylePanel.Name:='StyleOptions';
  FStyleLabel:=LabelAt(FStylePanel,'中分類',alNone,56);
  FStyleLabel.Name:='StyleCaption';
  FStyle:=TRhythmComboBox.Create(Self);
  FStyle.Parent:=FStylePanel;
  FStyle.Name:='AnimationStyle';
  FStyle.Width:=S(160);
  FStyle.ShowHint:=True;
  FStyle.Hint:='種類変更時は計画を再準備します。'+TYPE_V_TITLE+'はMVに重ねる透明映像として出力します。';
  FStyle.OnChange:=SettingChange;
  FStyleLabel.FocusControl:=FStyle;
  FDirectionPanel:=Panel(FOptionsBar,alNone,44);
  FDirectionPanel.Name:='DirectionOptions';
  FDirectionLabel:=LabelAt(FDirectionPanel,'小分類',alNone,40);
  FDirectionLabel.Name:='DirectionCaption';
  FDirection:=TRhythmComboBox.Create(Self);
  FDirection.Parent:=FDirectionPanel;
  FDirection.Name:='ScrollDirection';
  FDirection.Width:=S(130);
  FDirection.Items.Add('縦スクロール');
  FDirection.Items.Add('横スクロール');
  FDirection.ItemIndex:=0;
  FDirection.OnChange:=SettingChange;
  FDirectionLabel.FocusControl:=FDirection;
  FSensitivityPanel:=Panel(FOptionsBar,alNone,44);
  FSensitivityPanel.Name:='SensitivityOptions';
  FSensitivityLabel:=LabelAt(FSensitivityPanel,'解析感度',alNone,56);
  FSensitivityLabel.Name:='SensitivityCaption';
  FSensitivity:=TRhythmTrackBar.Create(Self);
  FSensitivity.Parent:=FSensitivityPanel;
  FSensitivity.Name:='Sensitivity';
  FSensitivity.TickStyle:=tsNone;
  FSensitivity.Min:=1;
  FSensitivity.Max:=100;
  FSensitivity.Position:=50;
  FSensitivity.Frequency:=10;
  FSensitivity.OnChange:=SettingChange;
  FSensitivityLabel.FocusControl:=FSensitivity;
  FLevel:=LabelAt(FSensitivityPanel,'50',alNone,32);
  FLevel.Alignment:=taRightJustify;
  FBossRow:=Panel(FOptionsBar,alNone,44);
  FBossRow.Name:='BossFrequencyOptions';
  FBossLabel:=LabelAt(FBossRow,'ボス出現頻度',alNone,110);
  FBossFrequency:=TRhythmTrackBar.Create(Self);
  FBossFrequency.Parent:=FBossRow;
  FBossFrequency.Name:='BossFrequency';
  FBossFrequency.Min:=0;
  FBossFrequency.Max:=100;
  FBossFrequency.Position:=BOSS_DEFAULT_FREQUENCY;
  FBossFrequency.TickStyle:=tsNone;
  FBossFrequency.Frequency:=10;
  FBossFrequency.ShowHint:=True;
  FBossFrequency.Hint:='ボスが登場するバリエーション共通。0:出現なし / 50:約90秒 / 100:約45秒。低←→高。変更後は計画を再準備します。';
  FBossFrequency.OnChange:=SettingChange;
  FBossLabel.FocusControl:=FBossFrequency;
  FBossValue:=LabelAt(FBossRow,BossFrequencyText(BOSS_DEFAULT_FREQUENCY),alNone,144);
  FBossValue.Alignment:=taRightJustify;
  FGameRow:=Panel(FOptionsBar,alNone,44);
  FGameRow.Name:='GameThresholdOptions';
  FGameLabel:=LabelAt(FGameRow,'音要素の感度',alNone,110);
  FGameLabel.Name:='GameThresholdCaption';
  FGameThreshold:=TRhythmTrackBar.Create(Self);
  FGameThreshold.Parent:=FGameRow;FGameThreshold.Name:='GameThreshold';
  FGameThreshold.Min:=-100;FGameThreshold.Max:=100;FGameThreshold.Position:=20;
  FGameThreshold.TickStyle:=tsNone;FGameThreshold.Frequency:=10;
  FGameThreshold.ShowHint:=True;
  FGameThreshold.Hint:='左ほど採用する音が増え、右ほど強い音に絞ります。'+TYPE_V_TITLE+'では−35以下で持続音の連打も追加します。変更後は再準備して適用してください。';
  FGameThreshold.OnChange:=SettingChange;FGameLabel.FocusControl:=FGameThreshold;
  FGameValue:=LabelAt(FGameRow,'20',alNone,32);FGameValue.Alignment:=taRightJustify;
  FEqualizerRow:=Panel(FOptionsBar,alNone,44);FEqualizerRow.Name:='EqualizerOptions';
  FEqualizer:=TRhythmCheckBox.Create(Self);FEqualizer.Parent:=FEqualizerRow;FEqualizer.Name:='EqualizerVisible';
  FEqualizer.Caption:='イコライザーを表示';FEqualizer.ShowHint:=True;
  FEqualizer.Hint:='音に反応するバーを表示します。全スタイル対応。再準備は不要です。';FEqualizer.OnClick:=SettingChange;
  FOptionsBar.OnResize:=LayoutOptions;
  Bottom:=Panel(Self,alBottom,52);
  FBottom:=Bottom;
  Bottom.Padding.SetBounds(S(12),0,S(12),0);
  Button(Bottom,'適用して閉じる',alRight,170,SaveClick);
  B.Name:='ApplySettings';
  TRhythmButton(B).Primary:=True;
  FApply:=B;
  FStatus:=LabelAt(Bottom,'WAV / MP3 を選択してください。',alClient,400);
  FStatus.ShowHint:=True;
  FStatus.WordWrap:=True;
  FStatus.AlignWithMargins:=True;
  FStatus.Margins.SetBounds(S(6),S(6),S(12),S(6));
  Transport:=Panel(FAnimationBody,alBottom,128);
  FTransport:=Transport;
  Transport.Padding.SetBounds(S(8),S(4),S(8),S(4));
  FWave:=TRhythmWaveView.Create(Self);
  FWave.Name:='MusicWaveform';
  FWave.Parent:=Transport;
  FWave.Align:=alTop;
  FWave.Height:=S(42);
  FWave.OnMouseDown:=WaveMouseDown;
  FSeek:=TRhythmTrackBar.Create(Self);
  FSeek.Parent:=Transport;
  FSeek.Name:='Timeline';
  FSeek.Height:=S(32);
  FSeek.Align:=alTop;
  FSeek.Min:=0;
  FSeek.Max:=100000;
  FSeek.TickStyle:=tsNone;
  FSeek.OnChange:=SeekChange;
  TransportButtons:=Panel(Transport,alBottom,44);
  FTransportButtons:=TransportButtons;
  Button(TransportButtons,'再生',alLeft,100,PlayClick);
  B.Name:='PreviewPlay';
  FPlay:=B;
  Button(TransportButtons,'停止',alLeft,90,StopClick);
  B.Name:='PreviewStop';
  B.Left:=S(120);
  FStop:=B;
  FClock:=LabelAt(TransportButtons,'00:00.000',alRight,240);
  FClock.Name:='PreviewClock';
  FClock.Alignment:=taRightJustify;
  FClock.AlignWithMargins:=True;
  FClock.Margins.SetBounds(S(12),S(6),S(6),S(6));
  FPreview:=TRhythmPreviewSurface.Create(Self);
  FPreview.Name:='ScenePreview';
  FPreview.Parent:=FAnimationBody;
  FPreview.Align:=alClient;
  FPreview.OnPaint:=PreviewPaint;
  FTimer:=TTimer.Create(Self);
  FTimer.Enabled:=False;
  FTimer.Interval:=16;
  FTimer.OnTimer:=TimerTick;
  Ini:=TMemIniFile.Create(SettingsPath,TEncoding.UTF8);
  try
    FFile.Text:=Ini.ReadString('Preview','Music','');
    FDirection.ItemIndex:=EnsureRange(Ini.ReadInteger('Preview','Direction',0),0,1);
    FSensitivity.Position:=EnsureRange(Ini.ReadInteger('Preview','Sensitivity',50),1,100);
  finally Ini.Free;
  end;
  if FileExists(ChangeFileExt(SettingsPath,'.json')) then
  if TRhythmSettings.TryJSON(TFile.ReadAllText(ChangeFileExt(SettingsPath,'.json'),TEncoding.UTF8),FState) then
  begin FFile.Text:=FState.Music;
    FDirection.ItemIndex:=FState.Direction;
    FSensitivity.Position:=FState.Sensitivity;
  end;
  FState.HostMusic:=False;
  // Standalone Preview always owns its file picker.
  FSelection:=TStyleSelection.FromSaved(FState.Style,FDirection.ItemIndex);RefreshSelection;
  FBossFrequency.Position:=FState.BossFrequency;
  FGameThreshold.Position:=FState.GameThreshold;
  FFile.OnChange:=SettingChange;
  if (FFile.Text<>'') and FileExists(FFile.Text) then FReloadAt:=GetTickCount64+100;
  FDesignEditor.Designs:=FState.Designs;
  Pages.ActivePage:=Animation;
  FUpdating:=False;
  FTimer.Enabled:=True;
  ApplyRhythmColors(Self);
  Color:=RhythmBackground;
  Navigation.Color:=RhythmBackground;
  Bottom.Color:=RhythmBackground;
  // Naming a VCL panel also sets its caption; internal component names are not UI text.
  for PanelIndex:=0 to ComponentCount-1 do if Components[PanelIndex] is TPanel then TPanel(Components[PanelIndex]).Caption:='';
  FLayoutReady:=True;
  OnResize:=LayoutOptions;
  FAnimationScroll.OnResize:=LayoutOptions;
  FStatus.Font.Color:=RhythmMuted;
  FLevel.Font.Color:=RhythmAccent;
  FGameValue.Font.Color:=RhythmAccent;
  FBossValue.Font.Color:=RhythmAccent;
  PageChanged(Self);
  UpdateStyleControls;
  ApplyRhythmTitleBar(Self);
end;

procedure TFormRhythmShooterSettings.Navigate(Sender:TObject);
begin FPages.ActivePageIndex:=TControl(Sender).Tag;
  PageChanged(Self);
end;

procedure TFormRhythmShooterSettings.PageChanged(Sender:TObject);
begin
  if FPages=nil then Exit;
  FAnimationTab.Selected:=FPages.ActivePageIndex=0;
  FDesignTab.Selected:=FPages.ActivePageIndex=1;
  if FPages.ActivePageIndex=0 then LayoutOptions(Self);
end;

procedure TFormRhythmShooterSettings.LayoutOptions(Sender:TObject);
var
  Groups:array[0..6] of TPanel;
  Widths,CaptionWidths:array[0..6] of Integer;
  I,Pass,W,H,X,Y,Gap,Total,Extra,Numbers,BarHeight,TextHeight,ButtonHeight,ButtonTop,SavedScrollY:Integer;
  MusicCaptionWidth,BrowseWidth,AnalyzeWidth,MusicActionsWidth,FileHeight,EqualizerHeight:Integer;
  PlayWidth,StopWidth,ClockWidth,ValueWidth,BossValueWidth,CategoryWidth,RowWidth:Integer;
  SeparateAudio:Boolean;
  function S(Value:Integer):Integer;
  begin Result:=MulDiv(Value,CurrentPPI,96);
  end;
  function TextWidth(const Text:string;AFont:TFont):Integer;
  begin Canvas.Font.PixelsPerInch:=AFont.PixelsPerInch;Canvas.Font.Assign(AFont);
    Result:=Canvas.TextWidth(Text);
  end;
  function LabelWidth(Control:TLabel;Minimum:Integer):Integer;
  begin Result:=Max(S(Minimum),TextWidth(Control.Caption,Control.Font)+S(4));
  end;
  function ButtonWidth(Control:TButton;Minimum:Integer):Integer;
  begin Result:=Max(S(Minimum),TextWidth(Control.Caption,Control.Font)+S(24));
  end;
  function ComboWidth(Control:TComboBox;Minimum:Integer):Integer;
  var
    N:Integer;
  begin
    Result:=S(Minimum);
    for N:=0 to Control.Items.Count-1 do
    Result:=Max(Result,TextWidth(Control.Items[N],Control.Font)+S(32));
  end;
  procedure Place(Control:TControl;AX,AY,AW,AH:Integer);
  begin
    Control.Align:=alNone;
    Control.AlignWithMargins:=False;
    Control.SetBounds(AX,AY,Max(1,AW),Max(1,AH));
  end;
  procedure Combo(LabelControl:TLabel;Control:TComboBox;CaptionWidth:Integer);
  begin
    LabelControl.SetBounds(0,0,CaptionWidth,H);
    Control.SetBounds(CaptionWidth+S(6),Max(0,(H-Control.Height) div 2),
    Max(1,Control.Parent.ClientWidth-CaptionWidth-S(6)),Control.Height);
  end;
  procedure Slider(LabelControl,ValueControl:TLabel;Control:TTrackBar;CaptionWidth,NumericWidth:Integer);
  var
    CW:Integer;
  begin
    CW:=Control.Parent.ClientWidth;
    LabelControl.SetBounds(0,0,CaptionWidth,H);
    ValueControl.SetBounds(CW-NumericWidth,0,NumericWidth,H);
    Control.SetBounds(CaptionWidth+S(4),Max(0,(H-S(24)) div 2),
    Max(1,CW-CaptionWidth-NumericWidth-S(8)),S(24));
  end;
begin
  // VCL raises child resize events while the form still has its old PPI.
  // Reflow only after that scaling pass has completed, from 96-DPI constants.
  if not FLayoutReady or FLayoutBusy or FDpiChanging or (csDestroying in ComponentState) then Exit;
  FLayoutBusy:=True;
  SavedScrollY:=FAnimationScroll.VertScrollBar.Position;
  try
    Gap:=S(8);
    Canvas.Font.PixelsPerInch:=Font.PixelsPerInch;
    Canvas.Font.Assign(Font);
    TextHeight:=Canvas.TextHeight('Agあ');
    ButtonHeight:=Max(S(32),TextHeight+S(12));
    H:=Max(ButtonHeight,Max(FCategory.Height,Max(FStyle.Height,FDirection.Height)))+S(8);
    ButtonTop:=(H-ButtonHeight) div 2;
    FileHeight:=TextHeight+S(4);
    EqualizerHeight:=Max(S(24),TextHeight+S(6));
    FNavigation.Height:=Max(S(48),ButtonHeight+S(12));
    FAnimationTab.Width:=ButtonWidth(FAnimationTab,160);
    FDesignTab.Width:=ButtonWidth(FDesignTab,160);
    FApply.Width:=ButtonWidth(FApply,170);
    FBottom.Height:=Max(S(52),Max(ButtonHeight+S(12),TextHeight*2+S(12)));
    FNavigation.Padding.SetBounds(S(12),0,S(12),0);
    FBottom.Padding.SetBounds(S(12),0,S(12),0);
    FPages.Margins.SetBounds(S(12),0,S(12),S(8));
    FOptionsHeader.Padding.SetBounds(S(8),S(4),S(8),S(4));
    FTransport.Padding.SetBounds(S(8),S(4),S(8),S(4));
    FAnimationTab.Margins.SetBounds(S(6),S(6),S(6),S(6));
    FDesignTab.Margins.SetBounds(S(6),S(6),S(6),S(6));
    FApply.Margins.SetBounds(S(6),S(6),S(6),S(6));
    FStatus.Margins.SetBounds(S(6),S(6),S(12),S(6));
    MusicCaptionWidth:=LabelWidth(FMusicLabel,96);
    BrowseWidth:=0;
    if FBrowse.Visible then BrowseWidth:=ButtonWidth(FBrowse,88);
    AnalyzeWidth:=ButtonWidth(FAnalyze,88);
    MusicActionsWidth:=AnalyzeWidth;
    if BrowseWidth>0 then Inc(MusicActionsWidth,BrowseWidth+Gap);
    PlayWidth:=ButtonWidth(FPlay,100);
    StopWidth:=ButtonWidth(FStop,90);
    ClockWidth:=Max(S(240),TextWidth(FClock.Caption,FClock.Font)+S(8));
    ValueWidth:=Max(S(32),TextWidth('-100',FLevel.Font)+S(4));
    BossValueWidth:=Max(S(144),TextWidth('100 / 約135秒',FBossValue.Font)+S(4));
    Groups[0]:=FCategoryPanel;Groups[1]:=FStylePanel;Groups[2]:=FDirectionPanel;
    Groups[3]:=FSensitivityPanel;Groups[4]:=FGameRow;Groups[5]:=FEqualizerRow;Groups[6]:=FBossRow;
    CaptionWidths[0]:=LabelWidth(FCategoryLabel,44);
    CaptionWidths[1]:=LabelWidth(FStyleLabel,44);
    CaptionWidths[2]:=LabelWidth(FDirectionLabel,40);
    CaptionWidths[3]:=LabelWidth(FSensitivityLabel,56);
    CaptionWidths[4]:=LabelWidth(FGameLabel,82);
    CaptionWidths[6]:=LabelWidth(FBossLabel,86);
    // Re-evaluate from full width so a previous wrap cannot retain a needless
    // scrollbar. Restore the user's scroll position once the final range exists.
    FAnimationBody.Height:=FAnimationScroll.ClientHeight;
    FAnimationScroll.Realign;
    // The second pass accounts for the vertical scrollbar appearing/disappearing.
    for Pass:=0 to 1 do begin
      W:=Max(1,FMusicRow.ClientWidth);
      Place(FMusicLabel,0,0,MusicCaptionWidth,H);
      if W>=MusicCaptionWidth+S(180)+MusicActionsWidth+2*Gap then begin
        Place(FAnalyze,W-AnalyzeWidth,ButtonTop,AnalyzeWidth,ButtonHeight);
        if FBrowse.Visible then Place(FBrowse,W-MusicActionsWidth,ButtonTop,BrowseWidth,ButtonHeight);
        Place(FFile,MusicCaptionWidth+Gap,(H-FileHeight) div 2,
          W-MusicCaptionWidth-MusicActionsWidth-2*Gap,FileHeight);
        FMusicRow.Height:=H;
      end else begin
        Place(FFile,MusicCaptionWidth+Gap,(H-FileHeight) div 2,W-MusicCaptionWidth-Gap,FileHeight);
        Place(FAnalyze,W-AnalyzeWidth,H+ButtonTop,AnalyzeWidth,ButtonHeight);
        if FBrowse.Visible then Place(FBrowse,W-MusicActionsWidth,H+ButtonTop,BrowseWidth,ButtonHeight);
        FMusicRow.Height:=2*H;
      end;
      Widths[0]:=CaptionWidths[0]+S(6)+ComboWidth(FCategory,128);
      Widths[1]:=CaptionWidths[1]+S(6)+ComboWidth(FStyle,136);
      Widths[2]:=CaptionWidths[2]+S(6)+ComboWidth(FDirection,112);
      Widths[3]:=Max(S(170),CaptionWidths[3]+ValueWidth+S(80));
      Widths[4]:=Max(S(170),CaptionWidths[4]+ValueWidth+S(80));
      Widths[5]:=TextWidth(FEqualizer.Caption,FEqualizer.Font)+S(32);
      Widths[6]:=CaptionWidths[6]+BossValueWidth+S(88);
      W:=Max(1,FOptionsBar.ClientWidth);
      Total:=0;
      Numbers:=2;
      if FBossRow.Visible then Inc(Numbers);
      for I:=0 to 6 do if Groups[I].Visible then begin if Total>0 then Inc(Total,Gap);
        Inc(Total,Widths[I]);
      end;
      // 分類が一行に収まる場合、折り返しは音の設定から始める。
      CategoryWidth:=Widths[0]+Widths[1]+Widths[2]+2*Gap;
      SeparateAudio:=(W<Total) and (CategoryWidth<=W);
      RowWidth:=Total;
      if SeparateAudio then Dec(RowWidth,CategoryWidth+Gap);
      if W>RowWidth then begin Extra:=Min(S(48),(W-RowWidth) div Numbers);
        Inc(Widths[3],Extra);
        Inc(Widths[4],Extra);
        if FBossRow.Visible then Inc(Widths[6],Extra);
      end;
      X:=0;
      Y:=0;
      for I:=0 to 6 do if Groups[I].Visible then begin
        if (X>0) and ((X+Widths[I]>W) or ((I=3) and SeparateAudio)) then begin X:=0;
          Inc(Y,H);
        end;
        Groups[I].SetBounds(X,Y,Min(W,Widths[I]),H);
        Inc(X,Widths[I]+Gap);
      end;
      BarHeight:=Y+H;
      FOptionsBar.Height:=BarHeight;
      FOptionsBar.Top:=FMusicRow.Top+FMusicRow.Height;
      FOptionsHeader.Height:=FMusicRow.Height+BarHeight+S(8);
      Combo(FCategoryLabel,FCategory,CaptionWidths[0]);
      Combo(FStyleLabel,FStyle,CaptionWidths[1]);
      Combo(FDirectionLabel,FDirection,CaptionWidths[2]);
      Slider(FSensitivityLabel,FLevel,FSensitivity,CaptionWidths[3],ValueWidth);
      Slider(FGameLabel,FGameValue,FGameThreshold,CaptionWidths[4],ValueWidth);
      Slider(FBossLabel,FBossValue,FBossFrequency,CaptionWidths[6],BossValueWidth);
      Place(FEqualizer,0,(H-EqualizerHeight) div 2,FEqualizerRow.ClientWidth,EqualizerHeight);
      W:=Max(1,FTransportButtons.ClientWidth);
      Place(FPlay,0,ButtonTop,PlayWidth,ButtonHeight);
      Place(FStop,PlayWidth+Gap,ButtonTop,StopWidth,ButtonHeight);
      if W>=PlayWidth+StopWidth+ClockWidth+2*Gap then begin
        Place(FClock,W-ClockWidth,0,ClockWidth,H);
        FTransportButtons.Height:=H;
      end else begin
        Place(FClock,0,H,W,H);
        FTransportButtons.Height:=2*H;
      end;
      FWave.Height:=S(42);
      FSeek.Height:=S(32);
      FWave.Top:=S(4);
      FSeek.Top:=FWave.Top+FWave.Height;
      FTransport.Height:=Max(S(128),FWave.Height+FSeek.Height+FTransportButtons.Height+S(8));
      FAnimationBody.Height:=Max(FAnimationScroll.ClientHeight,FOptionsHeader.Height+FTransport.Height+S(100));
      FAnimationScroll.Realign;
    end;
  finally
    FAnimationScroll.VertScrollBar.Position:=Min(SavedScrollY,Max(0,FAnimationBody.Height-FAnimationScroll.ClientHeight));
    FLayoutBusy:=False;
  end;
end;

procedure TFormRhythmShooterSettings.ScaleForPPI(NewPPI:Integer);
var
  WasChanging:Boolean;
begin
  WasChanging:=FDpiChanging;
  FDpiChanging:=True;
  try inherited ScaleForPPI(NewPPI);
  finally FDpiChanging:=WasChanging;
  end;
  if not FDpiChanging then LayoutOptions(Self);
end;

procedure TFormRhythmShooterSettings.DoBeforeMonitorDpiChanged(OldDPI,NewDPI:Integer);
begin
  FDpiChanging:=True;
  inherited;
end;

procedure TFormRhythmShooterSettings.DoAfterMonitorDpiChanged(OldDPI,NewDPI:Integer);
begin
  try inherited;
  finally FDpiChanging:=False;
  end;
  if FLayoutReady then begin FitToWorkArea;
    LayoutOptions(Self);
  end;
end;

procedure TFormRhythmShooterSettings.CMFontChanged(var Message:TMessage);
begin
  inherited;
  LayoutOptions(Self);
end;

procedure TFormRhythmShooterSettings.FitToWorkArea;
var
  Area:TRect;
  Margin:Integer;
begin
  Area:=Screen.MonitorFromWindow(Handle).WorkareaRect;
  Margin:=MulDiv(12,CurrentPPI,96);
  Constraints.MinWidth:=Min(MulDiv(520,CurrentPPI,96),Max(1,Area.Width-2*Margin));
  Constraints.MinHeight:=Min(MulDiv(360,CurrentPPI,96),Max(1,Area.Height-2*Margin));
  if WindowState=wsNormal then begin
    Width:=Min(Width,Max(1,Area.Width-2*Margin));
    Height:=Min(Height,Max(1,Area.Height-2*Margin));
    Left:=EnsureRange(Left,Area.Left,Max(Area.Left,Area.Right-Width));
    Top:=EnsureRange(Top,Area.Top,Max(Area.Top,Area.Bottom-Height));
  end;
end;

procedure TFormRhythmShooterSettings.Configure(const FileName:string;Direction,Sensitivity:Integer);
var
  State:TRhythmSettings;
begin State:=TRhythmSettings.Defaults;
  State.Music:=FileName;
  State.Direction:=Direction;
  State.Sensitivity:=Sensitivity;
  ConfigureState(State);
end;

procedure TFormRhythmShooterSettings.ConfigureState(const State:TRhythmSettings;ViewWidth,ViewHeight:Integer;HostMusicMode:Boolean);
begin
  CancelLoad;
  FLastPreparationError:='';
  FPlayer.SetAudio(nil);
  FWave.SetAudio(nil);
  FreeAndNil(FAudio);
  FState:=State;FPreparing:=False;FSelection:=TStyleSelection.FromSaved(State.Style,State.Direction);
  FHostMusicMode:=HostMusicMode;
  FState.HostMusic:=HostMusicMode;
  FFile.ReadOnly:=HostMusicMode;
  FBrowse.Visible:=not HostMusicMode;
  FFile.ShowHint:=HostMusicMode;
  if HostMusicMode then FFile.Hint:='AviUtl2側の「音楽ファイル」で指定します。この画面で準備・解析してください。';
  FViewWidth:=Max(1,ViewWidth);
  FViewHeight:=Max(1,ViewHeight);
  FDesignEditor.Designs:=State.Designs;
  FUpdating:=True;
  try RefreshSelection;
    FFile.Text:=State.Music;
    FSensitivity.Position:=EnsureRange(State.Sensitivity,1,100);
    FBossFrequency.Position:=EnsureRange(State.BossFrequency,0,100);
    FGameThreshold.Position:=EnsureRange(State.GameThreshold,-100,100);
  finally FUpdating:=False;
  end;
  UpdateStyleControls;
  FPreview.Invalidate;
  if HostMusicMode then begin
    if State.Music='' then SetStatus('AviUtl2側の「音楽ファイル」を指定してから設定を開いてください。')
    else if State.Plan.Key='' then SetStatus('未解析です。この画面で準備・解析してから適用してください。')
    else SetStatus('指定ファイルの解析済みデータを読み込みます。');
  end;
  if StyleHas(State.Style,sfPrepared) and (State.Plan.Version<>StylePlanVersion(State.Style)) then
  FStatus.Caption:='このスタイルの計画を更新します。解析キャッシュを再利用して再準備します。';
  FReloadAt:=0;
  if (State.Music<>'') and FileExists(State.Music) then FReloadAt:=GetTickCount64+100;
end;

function TFormRhythmShooterSettings.Snapshot:TRhythmSettings;
begin
  Result:=FState;
  Result.Style:=SelectedStyle;
  Result.Music:=MusicFile;
  Result.Direction:=ScrollDirection;
  Result.Sensitivity:=DetectionSensitivity;
  Result.BossFrequency:=FBossFrequency.Position;
  Result.GameThreshold:=FGameThreshold.Position;
  Result.Designs:=FDesignEditor.Designs;
  if not CanApplyPrepared then begin Result.Plan:=Default(TRhythmPlanRef);end;
end;

procedure TFormRhythmShooterSettings.SetBusy(Value:Boolean);
var
  I:Integer;
begin
  FPreparing:=Value;
  for I:=0 to ComponentCount-1 do
  if (Components[I] is TButton) or (Components[I] is TEdit) or (Components[I] is TComboBox) or (Components[I] is TTrackBar) then
  TControl(Components[I]).Enabled:=not Value;
  if FDesignEditor<>nil then FDesignEditor.Enabled:=not Value and StyleHas(SelectedStyle,sfDesigns);
  UpdateStyleControls;
  if Value then begin SetStatus('解析・動作計画を準備中...');
    FStatus.Update;
  end;
end;

procedure TFormRhythmShooterSettings.RefreshSelection;
var I:Integer;WasUpdating,Available:Boolean;Style:TRhythmStyle;
begin
  if (FCategory=nil) or (FStyle=nil) or (FDirection=nil) then Exit;
  WasUpdating:=FUpdating;FUpdating:=True;
  try
    FCategory.ItemIndex:=Ord(FSelection.Group);FStyle.Items.BeginUpdate;
    try FStyle.Items.Clear;
      for I:=0 to GroupStyleCount(FSelection.Group)-1 do begin Style:=GroupStyleAt(FSelection.Group,I);FStyle.Items.Add(StyleInfo(Style).MiddleTitle);end;
      FStyle.ItemIndex:=FSelection.MiddleIndex;
    finally FStyle.Items.EndUpdate;end;
    FDirection.Items.BeginUpdate;
    try FDirection.Items.Clear;for I:=0 to StyleSmallCount(FSelection.Style)-1 do FDirection.Items.Add(StyleSmallTitle(FSelection.Style,I));
      FDirection.ItemIndex:=FSelection.SmallIndex;
    finally FDirection.Items.EndUpdate;end;
    Available:=not FPreparing and not ((FDesignEditor<>nil) and FDesignEditor.Busy);
    FCategory.Enabled:=Available;FStyle.Enabled:=Available and (GroupStyleCount(FSelection.Group)>1);
    FDirection.Enabled:=Available and (StyleSmallCount(FSelection.Style)>1);
  finally FUpdating:=WasUpdating;end;
end;
function TFormRhythmShooterSettings.SelectedStyle:TRhythmStyle;
begin Result:=FSelection.Style;end;

function TFormRhythmShooterSettings.SelectedVariant:Integer;
begin Result:=StyleVariant(SelectedStyle,FState.FireworksRichness,FBossFrequency.Position,FGameThreshold.Position);
end;

function TFormRhythmShooterSettings.Ready:Boolean;
begin
  Result:=(FAudio<>nil) and (FWorker=nil) and (FReloadAt=0);
  if Result then Result:=SameFileName(FAudio.Source,ExpandFileName(MusicFile)) and
    (FState.Plan.AudioDensity=AudioDensityKey(SelectedStyle,FGameThreshold.Position)) and
    FState.Plan.Matches(FAudio.Key,DetectionSensitivity,ScrollDirection,SelectedStyle,SelectedVariant);
  if Result and (StyleHas(SelectedStyle,sfPrepared) or (FState.Plan.AudioDensity<>0)) then Result:=ValidDigest(FState.Plan.Digest);
end;

function TFormRhythmShooterSettings.CanApplyPrepared:Boolean;
begin Result:=Ready;
  if Result then Result:=AudioSourceUnchanged(FAudio);
end;

procedure TFormRhythmShooterSettings.SetStatus(const Text:string;Persist:Boolean);
var
  Path,Line:string;
begin
  if FStatus.Caption<>Text then FStatus.Caption:=Text;
  FStatus.Hint:=Text;
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
var
  I:Integer;
  IsReady,WasUpdating:Boolean;
  Control:TControl;
begin
  RefreshSelection;
  FState.Style:=SelectedStyle;FState.Sensitivity:=DetectionSensitivity;FState.Direction:=ScrollDirection;
  WasUpdating:=FUpdating;FUpdating:=True;
  try FEqualizer.Checked:=EqualizerEnabled(FState.EqualizerMode,SelectedStyle,FState.Plan.Version);
  finally FUpdating:=WasUpdating;end;
  FState.GameThreshold:=FGameThreshold.Position;
  FState.BossFrequency:=FBossFrequency.Position;
  FBossRow.Visible:=StyleHas(SelectedStyle,sfBoss);
  FBossValue.Caption:=BossFrequencyText(FBossFrequency.Position);
  FGameValue.Caption:=IntToStr(FGameThreshold.Position);
  FDirectionPanel.Visible:=True;
  UpdatePlayCaption;
  if FDesignTab<>nil then FDesignTab.Enabled:=(StyleHas(SelectedStyle,sfDesigns)) and (FWorker=nil);
  if FDesignEditor<>nil then FDesignEditor.Enabled:=(StyleHas(SelectedStyle,sfDesigns)) and (FWorker=nil);
  if (not StyleHas(SelectedStyle,sfDesigns)) and (FPages<>nil) then begin FPages.ActivePageIndex:=0;
    PageChanged(Self);
  end;
  IsReady:=Ready;
  if FApply<>nil then begin
    FApply.Enabled:=not FDesignEditor.Busy;
    if IsReady or (MusicFile='') then FApply.Caption:='適用して閉じる' else FApply.Caption:='設定のみ保存して閉じる';
  end;
  for I:=0 to ComponentCount-1 do if Components[I] is TControl then begin
    Control:=TControl(Components[I]);
    if (Control.Name='PreviewPlay') or (Control.Name='PreviewStop') or (Control.Name='Timeline') then Control.Enabled:=IsReady;
    if (Control.Name='MusicAnalyze') and (Control is TButton) then begin
      if StyleHas(SelectedStyle,sfPrepared) then TButton(Control).Caption:='準備/再試行'
      else TButton(Control).Caption:='解析';
    end;
  end;
  LayoutOptions(Self);
end;

procedure TFormRhythmShooterSettings.CancelLoad;
begin
  Inc(FRequestSerial);
  if FWorker<>nil then begin FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
end;

procedure TFormRhythmShooterSettings.DesignChanged(Sender:TObject);
begin FState.Designs:=FDesignEditor.Designs;
  if FUpdating then Exit;
  FRenderer.ApplyDesigns(FState.Designs,True);
  FPreview.Invalidate;
end;

procedure TFormRhythmShooterSettings.DesignBusyChanged(Sender:TObject);
var
  I:Integer;
begin
  for I:=0 to ComponentCount-1 do
  if (Components[I] is TButton) or (Components[I] is TEdit) or (Components[I] is TComboBox) or (Components[I] is TTrackBar) then begin
    TControl(Components[I]).Enabled:=not FDesignEditor.Busy;
    if (Components[I].Name='PreviewPlay') or (Components[I].Name='PreviewStop') or (Components[I].Name='Timeline') then TControl(Components[I]).Enabled:=True;
  end;
  if FDesignEditor.Busy then FStatus.Caption:='AI作成中... カスタムデザインの「取消」で中止できます。'
  else FStatus.Caption:='画像は候補を採用した後、この画面の「適用して閉じる」で保存します。';
  RefreshSelection;
end;

function TFormRhythmShooterSettings.MusicFile:string;
begin Result:=Trim(FFile.Text);
end;

function TFormRhythmShooterSettings.ScrollDirection:Integer;
begin Result:=FSelection.Direction;
end;

function TFormRhythmShooterSettings.DetectionSensitivity:Integer;
begin Result:=FSensitivity.Position;
end;

procedure TFormRhythmShooterSettings.BeginLoad(Force:Boolean);
var
  Existing:TRhythmAudio;
begin
  if ((FDesignEditor<>nil) and FDesignEditor.Busy) or (FWorker<>nil) then Exit;
  FReloadAt:=0;
  FState.Plan:=Default(TRhythmPlanRef);
  Inc(FRequestSerial);
  FLastPreparationError:='';
  FPrepareStarted:=GetTickCount64;
  FPlayer.SetAudio(nil);
  FWave.SetAudio(nil);
  Existing:=FAudio;
  FAudio:=nil;
  FTime:=0;
  FPreview.Invalidate;
  if not FileExists(MusicFile) then begin
    Existing.Free;
    if FHostMusicMode then FLastPreparationError:='音楽ファイルが見つかりません。AviUtl2側の「音楽ファイル」を指定し直してください。'
    else FLastPreparationError:='音楽ファイルが見つかりません。参照から選び直してください。設定のみの保存は可能です。';
    SetStatus(FLastPreparationError,True);
    SetBusy(False);
    Exit;
  end;
  SetBusy(True);
  FTimer.Enabled:=True;
  try
    FWorker:=TRhythmPrepareThread.Create(MusicFile,DetectionSensitivity,ScrollDirection,SelectedStyle,Force,Existing,FRequestSerial,SelectedVariant,FGameThreshold.Position);
    SetStatus('準備開始: '+MusicFile,True);
    FWorker.Start;
  except
    on E:Exception do begin
      if FWorker<>nil then begin FWorker.Terminate;
        FreeAndNil(FWorker);
      end else Existing.Free;
      FLastPreparationError:='準備を開始できません: '+E.ClassName+': '+E.Message;
      SetStatus(FLastPreparationError,True);
      SetBusy(False);
    end;
  end;
end;

procedure TFormRhythmShooterSettings.BrowseClick(Sender:TObject);
var
  Dialog:TOpenDialog;
begin
  if FHostMusicMode then Exit;
  Dialog:=TOpenDialog.Create(Self);
  try Dialog.Filter:='音楽ファイル (*.wav;*.mp3)|*.wav;*.mp3';
    Dialog.Options:=[ofFileMustExist,ofPathMustExist,ofEnableSizing];
    if Dialog.Execute then begin FFile.Text:=Dialog.FileName;
      BeginLoad;
    end;
  finally Dialog.Free;
  end;
end;

procedure TFormRhythmShooterSettings.LoadClick(Sender:TObject);
begin BeginLoad(not StyleHas(SelectedStyle,sfPrepared));
end;

procedure TFormRhythmShooterSettings.UpdatePlayCaption;
var
  Text:string;
begin
  if FPlay=nil then Exit;
  if (FPlayer<>nil) and FPlayer.Playing and not FPlayer.Paused then Text:='一時停止'
  else Text:='再生';
  if FPlay.Caption<>Text then FPlay.Caption:=Text;
end;

procedure TFormRhythmShooterSettings.RefreshTransport;
var
  StateText,ClockText:string;
  WasUpdating:Boolean;
begin
  FTime:=FPlayer.Position;
  UpdatePlayCaption;
  if FPlayer.Paused then StateText:='一時停止' else if FPlayer.Playing then StateText:='再生中' else StateText:='停止';
  ClockText:=Format('%s %.3f / %.3f 秒 | 音声デバイス時計',[StateText,FTime,FPlayer.Duration]);
  if FClock.Caption<>ClockText then FClock.Caption:=ClockText;
  WasUpdating:=FUpdating;
  FUpdating:=True;
  try FSeek.Position:=EnsureRange(Round(FTime/Max(0.001,FPlayer.Duration)*FSeek.Max),0,FSeek.Max);
  finally FUpdating:=WasUpdating;
  end;
  if FAudio<>nil then FWave.SetTime(Min(FTime,FAudio.Duration)) else FWave.SetTime(0);
end;

procedure TFormRhythmShooterSettings.SeekTo(Seconds:Double);
begin
  if not Ready then Exit;
  try
    // Latch end-of-buffer state before preserving playing/paused flags in Seek.
    FPlayer.Position;
    FPlayer.Seek(EnsureRange(Seconds,0.0,FPlayer.Duration));
    RefreshTransport;
    FPreview.Invalidate;
  except on E:Exception do begin UpdatePlayCaption;
      SetStatus('再生位置を変更できません: '+E.Message,True);
    end;
  end;
end;

procedure TFormRhythmShooterSettings.PlayClick(Sender:TObject);
begin
  if not Ready then begin
    if FLastPreparationError<>'' then SetStatus(FLastPreparationError+' 準備ボタンで再試行してください。')
    else SetStatus('まだ再生できません。音楽を選択し、準備完了を待ってください。設定だけの保存は可能です。');
    Exit;
  end;
  try
    FPlayer.Position;
    if FPlayer.Playing and not FPlayer.Paused then FPlayer.Pause else FPlayer.Play;
    RefreshTransport;
    FPreview.Invalidate;
  except on E:Exception do begin UpdatePlayCaption;
      FLastPreparationError:='音声再生を変更できません: '+E.Message;
      SetStatus(FLastPreparationError,True);
    end;
  end;
end;

procedure TFormRhythmShooterSettings.StopClick(Sender:TObject);
begin
  try FPlayer.Stop;
    RefreshTransport;
    FPreview.Invalidate;
  except on E:Exception do begin UpdatePlayCaption;
      SetStatus(E.Message);
    end;
  end;
end;

procedure TFormRhythmShooterSettings.SaveSettings;
var
  Path,Temp:string;
  Id:TGUID;
begin
  Path:=ChangeFileExt(SettingsPath,'.json');
  CreateGUID(Id);
  Temp:=Path+'.'+GUIDToString(Id)+'.tmp';
  try
    TFile.WriteAllText(Temp,Snapshot.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(Temp),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally if FileExists(Temp) then TFile.Delete(Temp);
  end;
end;

procedure TFormRhythmShooterSettings.SaveClick(Sender:TObject);
var
  Pending:Boolean;
  Notice:string;
begin
  if FDesignEditor.Busy then begin SetStatus('AI作成中です。素材画面で採用または取消を終えてから保存してください。');
    Exit;
  end;
  Pending:=(MusicFile<>'') and not CanApplyPrepared;
  if Pending then begin
    CancelLoad;
    FReloadAt:=0;
    FState.Plan:=Default(TRhythmPlanRef);
    SetBusy(False);
  end;
  try
    try FPlayer.Stop;
    except on E:Exception do SetStatus('音声停止: '+E.Message+' 設定保存は続行します。',True);
    end;
    SaveSettings;
    if Pending then begin
      Notice:='音楽・スタイル・感度などの設定は保存しました。動作計画は未準備なので映像はまだ適用されません。設定画面を再度開き、準備ボタンで準備完了後に適用してください。';
      if FLastPreparationError<>'' then Notice:=Notice+sLineBreak+sLineBreak+'直前の原因: '+FLastPreparationError;
      SetStatus(Notice,True);
      MessageDlg(Notice,mtInformation,[mbOK],0);
    end else SetStatus('準備済みの設定を保存しました。',True);
    if Application.MainForm=Self then Close else ModalResult:=mrOk;
  except on E:Exception do begin
      FLastPreparationError:='設定を保存できません: '+E.ClassName+': '+E.Message;
      SetStatus(FLastPreparationError,True);
      SetBusy(False);
    end;
  end;
end;

procedure TFormRhythmShooterSettings.SeekChange(Sender:TObject);
begin
  if FUpdating or not Ready then Exit;
  SeekTo(FPlayer.Duration*FSeek.Position/Max(1,FSeek.Max));
end;

procedure TFormRhythmShooterSettings.SettingChange(Sender:TObject);
begin
  // 表示だけの変更なので解析・再準備・停止・保存計画の無効化を起こさない。
  if Sender=FEqualizer then begin if FUpdating then Exit;FState.EqualizerMode:=Ord(FEqualizer.Checked);FPreview.Invalidate;Exit;end;
  if FUpdating then Exit;
  if Sender=FCategory then begin FSelection.ChooseGroup(TRhythmStyleGroup(FCategory.ItemIndex));RefreshSelection;end
  else if Sender=FStyle then begin FSelection.ChooseMiddle(FStyle.ItemIndex);RefreshSelection;end
  else if Sender=FDirection then FSelection.ChooseSmall(FDirection.ItemIndex);
  if (Sender=FGameThreshold) and (FGameValue<>nil) then FGameValue.Caption:=IntToStr(FGameThreshold.Position);
  if (Sender=FSensitivity) and (FLevel<>nil) then FLevel.Caption:=IntToStr(FSensitivity.Position);
  if (Sender=FBossFrequency) and (FBossValue<>nil) then FBossValue.Caption:=BossFrequencyText(FBossFrequency.Position);
  if FUpdating then Exit;
  FState.BossFrequency:=FBossFrequency.Position;
  FState.GameThreshold:=FGameThreshold.Position;
  FState.Plan:=Default(TRhythmPlanRef);
  UpdateStyleControls;
  FWave.SetAudio(nil);
  FStatus.Caption:='設定を変更しました。解析・計画を準備します。';
  try FPlayer.Pause;
  except on E:Exception do FStatus.Caption:=E.Message;
  end;
  UpdatePlayCaption;
  if FWorker<>nil then begin Inc(FRequestSerial);
    FWorker.Terminate;
    FReloadAt:=GetTickCount64+100;
  end
  else FReloadAt:=GetTickCount64+500;
  FPreview.Invalidate;
end;

procedure TFormRhythmShooterSettings.TimerTick(Sender:TObject);
var
  ErrorText,ProgressText,Summary:string;
  OldTime,PreviewEnd:Double;
  Changed,CurrentRequest:Boolean;
  Seconds:UInt64;
begin
  try
    OldTime:=FTime;
    Changed:=False;
    // 大→中→小の操作中に中間値を準備して選択を塞がない。閉じた最後の選択で一度だけ準備する。
    if (FReloadAt<>0) and (GetTickCount64>=FReloadAt) then begin
      if FCategory.DroppedDown or FStyle.DroppedDown or FDirection.DroppedDown then FReloadAt:=GetTickCount64+200 else BeginLoad;
    end;
    if (FWorker<>nil) and not FWorker.Finished then begin
      Seconds:=(GetTickCount64-FPrepareStarted) div 1000;
      case FWorker.Stage of
        2:begin
          ProgressText:=StyleInfo(SelectedStyle).ProgressText;
        end;
        3:ProgressText:='動作計画を保存中';
        4:ProgressText:='動作計画を再読込して確認中';
        else ProgressText:='音声解析・キャッシュ読込中';
      end;
      SetStatus(ProgressText+'... '+UIntToStr(Seconds)+' 秒（設定のみの保存は可能です）');
    end;
    if (FWorker<>nil) and FWorker.Finished then begin
      FWorker.WaitFor;
      ErrorText:=FWorker.Error;
      Summary:=FWorker.Summary;
      PreviewEnd:=FWorker.PreviewEnd;
      CurrentRequest:=FWorker.RequestId=FRequestSerial;
      if CurrentRequest then begin
        FAudio:=FWorker.TakeAudio;
        FState.Plan:=FWorker.Plan;
        if ErrorText='' then begin
          if FAudio=nil then ErrorText:='音声準備結果がありません。'
          else if (FState.Plan.AudioDensity<>AudioDensityKey(SelectedStyle,FGameThreshold.Position)) or
            not FState.Plan.Matches(FAudio.Key,DetectionSensitivity,ScrollDirection,SelectedStyle,SelectedVariant) then
          ErrorText:='準備結果と現在の設定が一致しません。準備ボタンで再試行してください。';
        end;
        if ErrorText<>'' then FState.Plan:=Default(TRhythmPlanRef);
      end;
      FreeAndNil(FWorker);
      FWave.SetAudio(FAudio);
      Changed:=True;
      SetBusy(False);
      if not CurrentRequest then SetStatus('古い準備結果を破棄しました。変更後の設定を準備します。',True)
      else if ErrorText<>'' then begin FLastPreparationError:=ErrorText;
        SetStatus(ErrorText+' 準備ボタンで再試行するか、設定のみ保存できます。',True);
      end
      else if Ready then begin
        FLastPreparationError:='';
        FPlayer.SetAudio(FAudio,Max(0.0,PreviewEnd-FAudio.Duration));
        SetStatus(Format('準備完了: %s / %.3f 秒 / %s / PCM再利用 %s',[StyleTitle(SelectedStyle),FAudio.Duration,Summary,BoolToStr(FAudio.CacheReused,True)]),True);
      end;
    end;
    if Ready then RefreshTransport
    else begin FClock.Caption:='動作計画が未準備';
      UpdatePlayCaption;
    end;
    if Changed or (Abs(FTime-OldTime)>0.00001) then FPreview.Invalidate;
    if FAudio<>nil then FWave.SetTime(Min(FTime,FAudio.Duration)) else FWave.SetTime(0);
  except on E:Exception do begin
      CancelLoad;
      FReloadAt:=0;
      FState.Plan:=Default(TRhythmPlanRef);
      try FPlayer.SetAudio(nil);
      except end;
      FLastPreparationError:='設定画面の準備処理: '+E.ClassName+': '+E.Message;
      SetBusy(False);
      SetStatus(FLastPreparationError,True);
      FPreview.Invalidate;
      // Keep the timer alive so an explicit retry can complete normally.
    end;
  end;
end;

procedure TFormRhythmShooterSettings.PreviewPaint(Sender:TObject);
var
  Scale:Double;
  W,H,X,Y:Integer;
  HintText:string;
begin
  FFrame.SetSize(FViewWidth,FViewHeight);
  FRenderer.ConfigureStyle(SelectedStyle,FState.Plan,FBossFrequency.Position,FState.EqualizerMode);
  FRenderer.ApplyDesigns(FDesignEditor.Designs);
  if Ready then begin
    FRenderer.Render(FFrame,FAudio,FTime,ScrollDirection,'WAV / MP3 を選択してプレビュー',FState.Zoom/100,FState.X,FState.Y,FState.OffsetSeconds);
    if FRenderer.OutputHasAlpha then OverlayPreview(FFrame);
  end
  else begin
    HintText:='設定画面で動作計画を準備してください。設定のみの保存は可能です。';
    if FLastPreparationError<>'' then HintText:=FLastPreparationError;
    FRenderer.Render(FFrame,nil,0,ScrollDirection,HintText,FState.Zoom/100,FState.X,FState.Y);
  end;
  Scale:=Min(FPreview.Width/FViewWidth,FPreview.Height/FViewHeight);
  W:=Round(FViewWidth*Scale);
  H:=Round(FViewHeight*Scale);
  X:=(FPreview.Width-W) div 2;
  Y:=(FPreview.Height-H) div 2;
  FPreview.Canvas.Brush.Color:=clBlack;
  FPreview.Canvas.FillRect(FPreview.ClientRect);
  FPreview.Canvas.StretchDraw(Rect(X,Y,X+W,Y+H),FFrame);
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
  FPlayer.Free;
  FAudio.Free;
  FRenderer.Free;
  FFrame.Free;
end;
end.
