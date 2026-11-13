unit RhythmGTimeline;
// Type.Gの波形内編集UI。計画を所有し、音声を借用する。成功した編集だけ新しい参照として通知する。
interface
uses System.Classes, System.Generics.Collections, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls,
  RhythmAudio, RhythmPlanRef, RhythmGPlan, RhythmGWave;
type
  TGTimeline = class(TCustomControl)
  private
    FAudio: TRhythmAudio;
    FPlan: TGPlan;
    FRef: TRhythmPlanRef;
    FWave: TGWave;
    FScroll: TScrollBar;
    FTempo,FStart,FFinish: TEdit;
    FGame: TComboBox;
    FTransitions: TCheckBox;
    FStatus: TLabel;
    FTools: TList<TControl>;
    FWidths: TList<Integer>;
    FUpdating,FLayoutBusy: Boolean;
    FTime,FViewStart,FViewSpan: Double;
    FOnChanged,FOnBeginEdit: TNotifyEvent;
    FOnSeek: TGTimeEvent;
    procedure BuildControls;
    procedure Layout;
    procedure Selection(Sender: TObject);
    procedure Seek(Sender: TObject; Time: Double);
    procedure Boundary(Sender: TObject; Index: Integer; Time: Double);
    procedure Command(Sender: TObject);
    procedure Scroll(Sender: TObject);
    procedure SyncControls;
    procedure Commit(Backup: TGPlan);
    procedure Changed(Notify: Boolean=True);
    function Index: Integer;
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
    procedure Paint; override;
  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;
    procedure Bind(Audio: TRhythmAudio; const Ref: TRhythmPlanRef);
    procedure SetTime(Value: Double);
    property Reference: TRhythmPlanRef read FRef;
    property Plan: TGPlan read FPlan; // 表示・検証用の借用。編集はUIのトランザクションを通す。
    property Wave: TGWave read FWave;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnBeginEdit: TNotifyEvent read FOnBeginEdit write FOnBeginEdit;
    property OnSeek: TGTimeEvent read FOnSeek write FOnSeek;
  end;
implementation
uses System.SysUtils, System.Math, System.Types, Vcl.Forms, Vcl.Graphics, Winapi.Windows,
  RhythmControls, RhythmGCodec;

function Number(const Text: string): Double;
begin
  if not TryStrToFloat(Trim(Text),Result,TFormatSettings.Invariant) and not TryStrToFloat(Trim(Text),Result) then
    raise EConvertError.Create('BPM・時刻は数値で入力してください');
  if IsNan(Result) or IsInfinite(Result) then raise EConvertError.Create('有限の数値で入力してください');
end;

constructor TGTimeline.Create(Owner: TComponent);
begin
  inherited; DoubleBuffered:=True; ControlStyle:=ControlStyle+[csOpaque];
  FTools:=TList<TControl>.Create; FWidths:=TList<Integer>.Create; Height:=210;
end;
procedure TGTimeline.SetParent(AParent: TWinControl);
begin
  inherited;
  if (AParent<>nil) and (FWave=nil) then BuildControls;
end;
procedure TGTimeline.BuildControls;
var I: Integer; L: TLabel;
  procedure Tool(C: TControl; W: Integer; const Name: string);
  begin C.Parent:=Self; C.Name:=Name; FTools.Add(C); FWidths.Add(W); end;
  procedure Button(const Text,Name: string; W,TagValue: Integer);
  var B: TButton;
  begin
    B:=TRhythmButton.Create(Self); Tool(B,W,Name); B.Caption:=Text; B.Tag:=TagValue; B.OnClick:=Command;
  end;
begin
  FUpdating:=True;
  L:=TLabel.Create(Self); Tool(L,32,'GTempoCaption'); L.Caption:='BPM'; L.Layout:=tlCenter;
  FTempo:=TEdit.Create(Self); Tool(FTempo,62,'GTempo');
  FTempo.ShowHint:=True; FTempo.Hint:='4拍子の推定BPMです。手動入力して「4小節に整列」で全シーンを合わせ直せます。';
  Button('4小節に整列','GRegrid',116,7); Button('自動構成','GAuto',84,6);
  FGame:=TRhythmComboBox.Create(Self); Tool(FGame,212,'GGame');
  for I:=0 to 31 do FGame.Items.Add(Format('%.2d %s',[I+1,GNames[I]]));
  FGame.Tag:=8; FGame.OnChange:=Command;
  Button('分割','GSplit',52,2); Button('結合','GMerge',52,3);
  Button('追加','GAdd',52,4); Button('削除','GDelete',52,5);
  L:=TLabel.Create(Self); Tool(L,30,'GStartCaption'); L.Caption:='開始'; L.Layout:=tlCenter;
  FStart:=TEdit.Create(Self); Tool(FStart,72,'GStart');
  L:=TLabel.Create(Self); Tool(L,30,'GFinishCaption'); L.Caption:='終了'; L.Layout:=tlCenter;
  FFinish:=TEdit.Create(Self); Tool(FFinish,72,'GFinish');
  Button('区間を変更','GBounds',96,1);
  FTransitions:=TRhythmCheckBox.Create(Self); Tool(FTransitions,104,'GTransitions');
  FTransitions.Caption:='切替演出'; FTransitions.Tag:=9; FTransitions.OnClick:=Command;
  Button('＋','GZoomIn',30,10); Button('－','GZoomOut',30,11);
  FWave:=TGWave.Create(Self); FWave.Parent:=Self; FWave.Name:='GSceneWave';
  FWave.OnSelect:=Selection; FWave.OnSeek:=Seek; FWave.OnBoundary:=Boundary;
  FScroll:=TScrollBar.Create(Self); FScroll.Parent:=Self; FScroll.Name:='GWaveScroll';
  FScroll.Kind:=sbHorizontal; FScroll.Min:=0; FScroll.Max:=10000; FScroll.OnChange:=Scroll;
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self; FStatus.Name:='GTimelineStatus'; FStatus.AutoSize:=False;
  FStatus.Layout:=tlCenter; FStatus.EllipsisPosition:=epEndEllipsis;
  ApplyRhythmColors(Self); FStatus.Font.Color:=RhythmMuted;
  FUpdating:=False; Height:=210; Layout; SyncControls;
end;
destructor TGTimeline.Destroy;
begin if FWave<>nil then FWave.Bind(nil,nil); FreeAndNil(FPlan); FreeAndNil(FTools); FreeAndNil(FWidths); inherited; end;
procedure TGTimeline.Paint;
begin Canvas.Brush.Color:=RhythmSurface; Canvas.FillRect(ClientRect); end;
procedure TGTimeline.Layout;
var X,Y,H,Gap,I,W,WrapWidth,WaveH,ScrollH,StatusH: Integer;
begin
  if FLayoutBusy or (FTools=nil) or (FWave=nil) or (csDestroying in ComponentState) then Exit; FLayoutBusy:=True;
  try
    H:=MulDiv(28,CurrentPPI,96); Gap:=MulDiv(4,CurrentPPI,96); X:=Gap; Y:=Gap;
    for I:=0 to FTools.Count-1 do begin
      W:=MulDiv(FWidths[I],CurrentPPI,96);
      WrapWidth:=W;
      if (FTools[I] is TLabel) and (I+1<FTools.Count) and (FTools[I+1] is TEdit) then
        WrapWidth:=WrapWidth+Gap+MulDiv(FWidths[I+1],CurrentPPI,96);
      if (X>Gap) and (X+WrapWidth>ClientWidth-Gap) then begin X:=Gap; Inc(Y,H+Gap); end;
      FTools[I].SetBounds(X,Y,Min(W,Max(1,ClientWidth-2*Gap)),H); Inc(X,W+Gap);
    end;
    Inc(Y,H+Gap); WaveH:=MulDiv(94,CurrentPPI,96); ScrollH:=MulDiv(16,CurrentPPI,96); StatusH:=MulDiv(23,CurrentPPI,96);
    FWave.SetBounds(Gap,Y,Max(1,ClientWidth-2*Gap),WaveH);
    FScroll.SetBounds(Gap,Y+WaveH,FWave.Width,ScrollH);
    FStatus.SetBounds(Gap,Y+WaveH+ScrollH,FWave.Width,StatusH);
    Height:=Y+WaveH+ScrollH+StatusH+Gap;
  finally FLayoutBusy:=False; end;
end;
procedure TGTimeline.Resize;
begin inherited; Layout; end;
procedure TGTimeline.Bind(Audio: TRhythmAudio; const Ref: TRhythmPlanRef);
var KeySame: Boolean; P: TGPlan;
begin
  KeySame:=(FAudio=Audio) and (FRef.Key=Ref.Key) and (FRef.Digest=Ref.Digest);
  if KeySame then Exit;
  P:=nil;
  if Audio<>nil then P:=LoadGPlan(Ref,Audio,Ref.Direction);
  FWave.Bind(nil,nil); FPlan.Free; FPlan:=P; FAudio:=Audio; FRef:=Ref;
  FViewStart:=0; FViewSpan:=1;
  if FPlan<>nil then FViewSpan:=Min(FPlan.Duration,16*FPlan.Beat*8);
  FWave.Bind(Audio,FPlan); FWave.View(FViewStart,FViewSpan);
  if FPlan<>nil then FWave.Selected:=FPlan.SceneAt(FTime) else FWave.Selected:=-1;
  SyncControls;
end;
function TGTimeline.Index: Integer;
begin Result:=FWave.Selected; if FPlan<>nil then Result:=EnsureRange(Result,0,High(FPlan.Scenes)); end;
procedure TGTimeline.SyncControls;
var S: TGScene; I: Integer; Have: Boolean;
begin
  FUpdating:=True;
  try
    Have:=FPlan<>nil; for I:=0 to FTools.Count-1 do FTools[I].Enabled:=Have;
    FWave.Enabled:=Have; FScroll.Enabled:=Have;
    if not Have then begin FStatus.Caption:='解析後、波形上でシーンを配置できます。'; Exit; end;
    S:=FPlan.Scenes[Index]; FGame.ItemIndex:=S.Game;
    FTempo.Text:=FloatToStrF(60/FPlan.Beat,ffFixed,8,2,TFormatSettings.Invariant);
    FStart.Text:=FloatToStrF(S.Start,ffFixed,12,3,TFormatSettings.Invariant);
    FFinish.Text:=FloatToStrF(S.Finish,ffFixed,12,3,TFormatSettings.Invariant);
    FTransitions.Checked:=FPlan.Transitions;
    FScroll.Position:=Round(FViewStart/Max(0.001,FPlan.Duration-FViewSpan)*FScroll.Max);
    FStatus.Caption:=Format('%d/%d  %s ｜4小節 %.2f秒｜上段:シーク 下段:選択 境界ドラッグ:1小節（Shift:自由）',
      [Index+1,Length(FPlan.Scenes),GNames[S.Game],16*FPlan.Beat]);
  finally FUpdating:=False; end;
end;
procedure TGTimeline.SetTime(Value: Double);
begin FTime:=Value; FWave.SetTime(Value); end;
procedure TGTimeline.Selection(Sender: TObject);
begin SyncControls; end;
procedure TGTimeline.Seek(Sender: TObject; Time: Double);
begin FTime:=Time; if Assigned(FOnSeek) then FOnSeek(Self,Time); end;
procedure TGTimeline.Scroll(Sender: TObject);
begin
  if FUpdating or (FPlan=nil) then Exit;
  FViewStart:=Max(0.0,FPlan.Duration-FViewSpan)*FScroll.Position/FScroll.Max;
  FWave.View(FViewStart,FViewSpan);
end;
procedure TGTimeline.Changed(Notify: Boolean);
begin
  FWave.Bind(FAudio,FPlan); FWave.View(FViewStart,FViewSpan); SyncControls;
  if Notify and Assigned(FOnChanged) then FOnChanged(Self);
end;
procedure TGTimeline.Commit(Backup: TGPlan);
var NewRef: TRhythmPlanRef;
begin
  try
    FPlan.RebuildCues(FAudio); NewRef:=FRef; SaveGEdit(FPlan,FAudio,NewRef); FRef:=NewRef;
  except
    FWave.Bind(nil,nil); FPlan.Free; FPlan:=Backup; Changed(False); raise;
  end;
  Backup.Free; Changed;
end;
procedure TGTimeline.Boundary(Sender: TObject; Index: Integer; Time: Double);
var Backup: TGPlan;
begin
  if FPlan=nil then Exit;
  if Assigned(FOnBeginEdit) then FOnBeginEdit(Self);
  Backup:=FPlan.Clone;
  try
    FPlan.Bounds(Index,Time,FPlan.Scenes[Index].Finish); FWave.Selected:=Index;
  except on E:Exception do begin Backup.Free; FStatus.Caption:=E.Message; Exit; end; end;
  try Commit(Backup); except on E: Exception do FStatus.Caption:=E.Message; end;
end;
procedure TGTimeline.Command(Sender: TObject);
var Backup,NewPlan: TGPlan; I,TagValue: Integer; A,B,T: Double;
begin
  if FUpdating or (FPlan=nil) then Exit; TagValue:=TControl(Sender).Tag;
  if TagValue in [10,11] then begin
    if TagValue=10 then FViewSpan:=Max(16*FPlan.Beat,FViewSpan/2) else FViewSpan:=Min(FPlan.Duration,FViewSpan*2);
    FViewSpan:=Min(FViewSpan,FPlan.Duration); FViewStart:=EnsureRange(FTime-FViewSpan/2,0.0,Max(0.0,FPlan.Duration-FViewSpan));
    FWave.View(FViewStart,FViewSpan); SyncControls; Exit;
  end;
  if Assigned(FOnBeginEdit) then FOnBeginEdit(Self);
  I:=Index; Backup:=FPlan.Clone;
  try
    try
      case TagValue of
        1:begin
          A:=Number(FStart.Text); B:=Number(FFinish.Text);
          if Abs(A-FPlan.Scenes[I].Start)<0.00051 then A:=FPlan.Scenes[I].Start;
          if Abs(B-FPlan.Scenes[I].Finish)<0.00051 then B:=FPlan.Scenes[I].Finish;
          if I=0 then A:=0; if I=High(FPlan.Scenes) then B:=FPlan.Duration;
          FPlan.Bounds(I,A,B);
        end;
        2,4:begin
          T:=FTime;
          if (T<FPlan.Scenes[I].Start+0.25) or (T>FPlan.Scenes[I].Finish-0.25) then
            T:=(FPlan.Scenes[I].Start+FPlan.Scenes[I].Finish)/2;
          FPlan.Split(I,T); Inc(I);
        end;
        3:FPlan.Merge(I);
        5:begin FPlan.Delete(I); I:=Max(0,I-1); end;
        6:begin NewPlan:=BuildGPlan(FAudio); NewPlan.Transitions:=FPlan.Transitions;
          FWave.Bind(nil,nil); FPlan.Free; FPlan:=NewPlan; I:=0; end;
        7: FPlan.Regrid(Number(FTempo.Text),FAudio);
        8: if FGame.ItemIndex>=0 then FPlan.Scenes[I].Game:=FGame.ItemIndex;
        9: FPlan.Transitions:=FTransitions.Checked;
      end;
      FWave.Selected:=Min(I,High(FPlan.Scenes));
      FViewSpan:=Min(FViewSpan,FPlan.Duration); FViewStart:=Min(FViewStart,Max(0.0,FPlan.Duration-FViewSpan));
    except
      on E: Exception do begin FWave.Bind(nil,nil); FPlan.Free; FPlan:=Backup; Backup:=nil;
        Changed(False); FStatus.Caption:=E.Message; Exit; end;
    end;
    try Commit(Backup); Backup:=nil;
    except on E: Exception do begin Backup:=nil; FStatus.Caption:=E.Message; end; end;
  finally Backup.Free; end;
end;
end.
