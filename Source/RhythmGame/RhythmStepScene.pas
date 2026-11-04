unit RhythmStepScene;
// 4レーンの譜面を絶対時刻で描画。横長では独立した左右の譜面を表示する。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmStepPlan,RhythmEqualizer;

type
  TStepAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TStepPlan;
    FAttempt,FError:string;
  public
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    function TryActivity(Time:Double;out Activity:TEqualizerActivity):Boolean;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;

function StepPlayerCount(Width,Height:Integer):Integer;
function StepNoteY(SecondsUntilHit,JudgeY,SpawnY:Double):Double;

implementation
uses System.SysUtils,System.Math,System.Types,Vcl.Graphics,Winapi.Windows;

const
  // 彩度だけに頼らず、1～4本の斜めの刻みでレーンを見分ける。
  LaneColors:array[0..1,0..3] of TColor=(
    ($00F4DE53,$00E69D7A,$00D588CA,$00C482F4),
    ($00D688EE,$007E88FF,$007AC6FF,$009CE9F7));
  Ink=$00211A12;
  Pale=$00F8F0E9;
  Quiet=$00B69D88;
  Guide=$00524436;

function StepPlayerCount(Width,Height:Integer):Integer;
begin
  Result:=1+Ord((Width>=280) and (Width>=Height*1.42));
end;

function StepNoteY(SecondsUntilHit,JudgeY,SpawnY:Double):Double;
begin
  Result:=JudgeY+(SpawnY-JudgeY)*(SecondsUntilHit/STEP_LOOKAHEAD);
end;

function Tone(Color:TColor;Amount:Double):TColor;
begin
  Result:=RGB(Round(GetRValue(Color)*Amount),Round(GetGValue(Color)*Amount),Round(GetBValue(Color)*Amount));
end;

function Glyph(C:Char):UInt64;
begin
  case C of
    '0':Result:=$3A33AE62E;
    '1':Result:=$11842108E;
    '2':Result:=$3A211111F;
    '3':Result:=$78217043E;
    '4':Result:=$08CA97C42;
    '5':Result:=$7E10F043E;
    '6':Result:=$3A10F462E;
    '7':Result:=$7C2222108;
    '8':Result:=$3A317462E;
    '9':Result:=$3A317842E;
    'A':Result:=$3A31FC631;
    'C':Result:=$3E108420F;
    'D':Result:=$7A318C63E;
    'E':Result:=$7E10F421F;
    'H':Result:=$4631FC631;
    'I':Result:=$38842108E;
    'L':Result:=$42108421F;
    'M':Result:=$4775AC631;
    'N':Result:=$47359C631;
    'O':Result:=$3A318C62E;
    'P':Result:=$7A31F4210;
    'R':Result:=$7A31F5251;
    'S':Result:=$3E107043E;
    'T':Result:=$7C8421084;
    'U':Result:=$46318C62E;
    'Y':Result:=$462A21084;
    ':':Result:=$008401080;
    '/':Result:=$042222210;
  else
    Result:=0;
  end;
end;

procedure LabelAt(Surface:TAnimationRenderSurface;const Caption:string;X,Y,Cell,Align:Double;Color:TColor);
var I,Row,Col:Integer;Bits:UInt64;L,T:Double;
begin
  // 描画面の矩形だけで文字を組み、GDIとD2Dで同じレイアウトを使う。
  X:=X-(Length(Caption)*6-1)*Cell*Align;
  for I:=1 to Length(Caption) do begin
    Bits:=Glyph(Caption[I]);
    for Row:=0 to 6 do for Col:=0 to 4 do
      if Bits and (UInt64(1) shl (34-Row*5-Col))<>0 then begin
        L:=X+((I-1)*6+Col)*Cell;
        T:=Y+Row*Cell;
        Surface.FillRect(L,T,L+Cell*0.96,T+Cell*0.96,Color);
      end;
  end;
end;

function TimeCode(Seconds:Double):string;
var S:Integer;
begin
  S:=Trunc(Seconds+STEP_TIME_EPSILON);
  Result:=Format('%.2d:%.2d',[S div 60,S mod 60]);
end;

procedure Chamfer(Surface:TAnimationRenderSurface;X,Y,W,H:Double;Color:TColor);
var L,R,C:Double;
begin
  L:=X-W*0.5;
  R:=X+W*0.5;
  C:=Min(H*0.64,W*0.22);
  Surface.FillQuad(PointF(L,Y),PointF(L+C,Y-H*0.5),PointF(R-C,Y-H*0.5),PointF(R,Y),Color);
  Surface.FillQuad(PointF(L,Y),PointF(R,Y),PointF(R-C,Y+H*0.5),PointF(L+C,Y+H*0.5),Color);
end;

procedure Marks(Surface:TAnimationRenderSurface;X,Y,H:Double;Lane:Integer;Color:TColor);
var I:Integer;CX:Double;
begin
  for I:=0 to Lane do begin
    CX:=X+(I-Lane*0.5)*H*0.54;
    Surface.FillQuad(PointF(CX-H*0.20,Y+H*0.25),PointF(CX+H*0.05,Y-H*0.25),
      PointF(CX+H*0.22,Y-H*0.25),PointF(CX-H*0.03,Y+H*0.25),Color);
  end;
end;

procedure Tile(Surface:TAnimationRenderSurface;X,Y,W,H,Light:Double;Lane:Integer;Color:TColor;Receptor:Boolean);
begin
  Chamfer(Surface,X,Y,W,H,Tone(Color,Light));
  if Receptor then Chamfer(Surface,X,Y,W-H*0.32,H*0.79,Ink)
  else Chamfer(Surface,X,Y,W-H*0.32,H*0.68,Tone(Color,Light*0.44));
  Marks(Surface,X,Y,H,Lane,Tone(Pale,Min(1.0,Light+0.13)));
end;

destructor TStepAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TStepAnimation.SetReference(const Ref:TRhythmPlanRef);
begin
  FRef:=Ref;
end;

procedure TStepAnimation.Prepare(const Frame:TAnimationFrame);
var Attempt:string;
begin
  Attempt:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio=nil then Attempt:=Attempt+'|none'
  else Attempt:=Attempt+'|'+FAudio.Key+'|'+FAudio.SourceRevision;
  if Attempt=FAttempt then Exit;
  FAttempt:=Attempt;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try
    FPlan:=TStepPlan.Load(FRef,FAudio,Frame.Direction);
  except
    on E:Exception do FError:=E.Message;
  end;
end;

function TStepAnimation.Notice:string;
begin
  Result:=FError;
end;

function TStepAnimation.TryActivity(Time:Double;out Activity:TEqualizerActivity):Boolean;
var I:Integer;Age,Strength:Double;Note:TStepNote;
begin
  Activity:=Default(TEqualizerActivity);
  Result:=FPlan<>nil;
  if not Result or (FPlan.Count=0) or (Time<0) or (Time>FPlan.Duration) then Exit;
  Activity.Valid:=True;
  Activity.Hit:=FPlan.CountThrough(Time)-1;
  for I:=Activity.Hit downto Max(0,Activity.Hit-12) do begin
    Note:=FPlan.Notes[I];
    Age:=Max(0.0,Time-Note.Time);
    if Age>=0.8 then Break;
    Strength:=EnsureRange(Note.Strength,0.0,1.0);
    Activity.Pulse:=Activity.Pulse+(0.25+Strength*0.75)*Exp(-Age*9);
    Activity.Energy:=Max(Activity.Energy,Strength*Exp(-Age*3));
  end;
  Activity.Pulse:=Min(1.4,Activity.Pulse);
end;

procedure TStepAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var W,H,DeckWidth,Center,JudgeY,SpawnY,PanelBottom,Scale,Cell,T,Duration,Pulse:Double;
  Players,Player,Past,LastVisible,Stripe:Integer;
  Mode,Status,Counter:string;Activity:TEqualizerActivity;

  procedure DrawDeck;
  var L,R,LaneW,X,Y,U,NoteH,Depth,Age,Glow,Reach,FirstX,LastX:Double;
    Lane,I,J,Mask:Integer;
    Ages:array[0..STEP_LANE_COUNT-1] of Double;
    C,Accent:TColor;
    Note:TStepNote;
    function LaneX(Index:Integer):Double;
    begin
      Result:=L+(Index+0.5)*LaneW;
    end;
  begin
    L:=Center-DeckWidth*0.5;
    R:=Center+DeckWidth*0.5;
    LaneW:=DeckWidth/STEP_LANE_COUNT;
    NoteH:=Min(LaneW*0.30,H*0.036);
    Accent:=LaneColors[Player,0];
    Surface.FillRect(L-3*Scale,H*0.169,R+3*Scale,PanelBottom+3*Scale,Guide);
    Surface.FillRect(L-2*Scale,H*0.172,R+2*Scale,PanelBottom+2*Scale,Ink);
    for Lane:=0 to STEP_LANE_COUNT-1 do begin
      X:=L+Lane*LaneW;
      C:=LaneColors[Player,Lane];
      Surface.FillRect(X+Scale,H*0.217,X+LaneW-Scale,PanelBottom,Tone(C,0.075));
      Surface.FillRect(X+Scale,H*0.217,X+LaneW-Scale,JudgeY,Tone(C,0.13));
      Surface.FillRect(X+Scale,PanelBottom-2*Scale,X+LaneW-Scale,PanelBottom,Tone(C,0.50));
    end;
    // 水平ガイドは飾り。時刻や拍の量子化には使わない。
    for I:=1 to 7 do begin
      Y:=JudgeY+(PanelBottom-JudgeY)*I/8;
      Surface.Line(L,Y,R,Y,RGB(36,38,55),Scale);
    end;
    if Frame.BackgroundOnly then Exit;

    LabelAt(Surface,'P'+IntToStr(Player+1),L+9*Scale,H*0.185,Cell*0.86,0,Accent);
    LabelAt(Surface,'HITS '+Counter,R-9*Scale,H*0.185,Cell*0.77,1,Pale);
    for Lane:=0 to STEP_LANE_COUNT-1 do Ages[Lane]:=STEP_FLASH_TIME;
    for I:=Past-1 downto Max(0,Past-32) do begin
      Note:=FPlan.Notes[I];
      Age:=Max(0.0,T-Note.Time);
      if Age>=STEP_FLASH_TIME then Break;
      for Lane:=0 to STEP_LANE_COUNT-1 do
        if Note.Lanes[Player] and (1 shl Lane)<>0 then Ages[Lane]:=Min(Ages[Lane],Age);
    end;

    for I:=LastVisible-1 downto Past do begin
      Note:=FPlan.Notes[I];
      U:=(Note.Time-T)/STEP_LOOKAHEAD;
      Y:=StepNoteY(Note.Time-T,JudgeY,SpawnY);
      Depth:=1-0.46*Sqr(U);
      Mask:=Note.Lanes[Player];
      FirstX:=R;
      LastX:=L;
      for Lane:=0 to STEP_LANE_COUNT-1 do if Mask and (1 shl Lane)<>0 then begin
        FirstX:=Min(FirstX,LaneX(Lane));
        LastX:=Max(LastX,LaneX(Lane));
      end;
      if LastX>FirstX then Surface.Line(FirstX,Y,LastX,Y,Tone(Pale,0.32+0.43*Depth),Max(1.0,Scale*1.5));
      for Lane:=0 to STEP_LANE_COUNT-1 do if Mask and (1 shl Lane)<>0 then begin
        X:=LaneX(Lane);
        C:=LaneColors[Player,Lane];
        if FPlan.IsRoll(I) then
          Surface.Line(X-LaneW*0.19,Y+NoteH*0.55,X+LaneW*0.19,Y+NoteH*0.55,Tone(C,Depth),Max(1.0,Scale*1.5))
        else if Note.Strength>=0.78 then
          Surface.Line(X,Y+NoteH*0.45,X,Min(PanelBottom,Y+NoteH*1.48),Tone(C,Depth*0.34),Max(1.0,Scale*2));
        Tile(Surface,X,Y,LaneW*0.75,NoteH*Depth,Depth,Lane,C,False);
      end;
    end;

    Surface.FillRect(L,JudgeY-1.5*Scale,R,JudgeY+1.5*Scale,Tone(Accent,0.58+Pulse*0.26));
    for Lane:=0 to STEP_LANE_COUNT-1 do begin
      X:=LaneX(Lane);
      C:=LaneColors[Player,Lane];
      Glow:=Sqr(1-Ages[Lane]/STEP_FLASH_TIME);
      if Glow>0 then begin
        Reach:=NoteH*(0.64+0.86*(1-Glow));
        Chamfer(Surface,X,JudgeY,LaneW*(0.82+0.12*(1-Glow)),Reach,Tone(C,0.14+0.19*Glow));
        for J:=0 to 5 do begin
          U:=(J-2.5)/2.5;
          Y:=JudgeY-(0.55+0.16*(J mod 3))*Reach;
          Surface.Line(X+U*LaneW*0.35,Y,X+U*LaneW*0.39,Y-Reach*0.27,Tone(C,0.28+0.72*Glow),Max(1.0,Scale*Glow));
        end;
      end;
      Tile(Surface,X,JudgeY,LaneW*0.83,NoteH*1.07,0.65+0.35*Glow,Lane,C,Glow<0.32);
      if Glow>=0.66 then Surface.FillRect(X-LaneW*0.14,JudgeY+NoteH*0.46,X+LaneW*0.14,JudgeY+NoteH*0.57,Pale);
    end;
  end;

begin
  W:=Frame.Width;
  H:=Frame.Height;
  if (W<4) or (H<4) then Exit;
  Scale:=Max(0.30,Min(W,H)/540);
  Cell:=Max(0.50,Min(W*0.0031,H*0.0052));
  T:=Frame.Time;
  Players:=StepPlayerCount(Frame.Width,Frame.Height);
  JudgeY:=H*0.266;
  SpawnY:=H*0.86;
  PanelBottom:=H*0.889;
  if Players=2 then DeckWidth:=Min(H*0.666,W*0.386)
  else DeckWidth:=Min(H*0.76,W*0.86);
  Duration:=0;
  Past:=0;
  LastVisible:=0;
  Pulse:=0;
  Status:='READY';
  if Players=2 then Mode:='DUO / AUTO' else Mode:='SOLO / AUTO';
  if FPlan<>nil then begin
    Duration:=FPlan.Duration;
    Past:=FPlan.CountThrough(T);
    LastVisible:=Min(Past+96,FPlan.CountThrough(T+STEP_LOOKAHEAD));
    TryActivity(T,Activity);
    Pulse:=Min(1.0,Activity.Pulse);
    Status:='SYNC';
    if (Past>0) and FPlan.IsRoll(Past-1) and (T-FPlan.Notes[Past-1].Time<0.17) then Status:='ROLL';
    if FPlan.Count=0 then Status:='NO NOTES'
    else if (Past=FPlan.Count) and (T+STEP_TIME_EPSILON>=Min(Duration,FPlan.Notes[Past-1].Time+STEP_FLASH_TIME)) then Status:='CLEAR';
  end;
  Counter:=IntToStr(Past);

  // 中央は暗く保ち、レーンの外へだけ帯と反射を置く。
  for Stripe:=0 to 19 do
    Surface.FillRect(0,H*Stripe/20,W,H*(Stripe+1)/20,RGB(9+Stripe div 4,12+Stripe div 3,24+Stripe div 2));
  if W/H>1.05 then for Stripe:=0 to 12 do begin
    Surface.Line(W*(0.025+Stripe*0.022),H*0.149,W*(0.048+Stripe*0.009),H*0.904,Tone(LaneColors[0,0],0.12+Pulse*0.09),Scale);
    Surface.Line(W*(0.975-Stripe*0.022),H*0.149,W*(0.952-Stripe*0.009),H*0.904,Tone(LaneColors[1,1],0.12+Pulse*0.09),Scale);
  end;
  Surface.FillRect(W*0.054,H*0.131,W*0.946,H*0.135,Guide);
  Surface.FillRect(W*0.054,H*0.131,W*0.164,H*0.135,LaneColors[0,0]);
  for Player:=0 to Players-1 do begin
    Center:=W*0.5;
    if Players=2 then Center:=W*(0.266+Player*0.468);
    DrawDeck;
  end;
  if Frame.BackgroundOnly then Exit;

  LabelAt(Surface,'PRISM STEP',W*0.054,H*0.054,Cell*1.35,0,Pale);
  LabelAt(Surface,Mode,W*0.946,H*0.075,Cell*0.70,1,Quiet);
  Surface.FillRect(W*0.054,H*0.924,W*0.946,H*0.931,Guide);
  if Duration>0 then Surface.FillRect(W*0.054,H*0.924,W*(0.054+0.892*Min(1.0,T/Duration)),H*0.931,LaneColors[0,0]);
  LabelAt(Surface,TimeCode(Min(T,Duration)),W*0.054,H*0.951,Cell*0.80,0,Quiet);
  LabelAt(Surface,Status,W*0.5,H*0.950,Cell*0.89,0.5,Pale);
  LabelAt(Surface,TimeCode(Duration),W*0.946,H*0.951,Cell*0.80,1,Quiet);
end;
end.
