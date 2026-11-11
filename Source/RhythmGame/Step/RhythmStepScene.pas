unit RhythmStepScene;
// 4レーンの譜面を絶対時刻で描画。横長では独立した左右の譜面を表示する。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmStepPlan,RhythmEqualizer,RhythmImageBank;

type
  TStepAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TStepPlan;
    FAttempt,FError:string;
    FCounter,FClock,FLength:string;
    FCounterValue,FClockSecond,FLengthSecond:Integer;
    procedure DrawLegacy(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
    procedure DrawPatterns(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
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
function StepImages:TAnimationImageBank;

implementation
uses System.SysUtils,System.Math,System.Types,Vcl.Graphics,Winapi.Windows,RhythmStyles;

const
  // 彩度だけに頼らず、1～4本の斜めの刻みでレーンを見分ける。
  LaneColors:array[0..1,0..3] of TColor=(
    ($00F4DE53,$00E69D7A,$00D588CA,$00C482F4),
    ($00D688EE,$007E88FF,$007AC6FF,$009CE9F7));
  Ink=$00211A12;
  Pale=$00F8F0E9;
  Quiet=$00B69D88;
  Guide=$00524436;
  StepSpriteCount=16;

type
  TStepImages=class(TAnimationImageBank)
  protected
    procedure PrepareImages;override;
  end;

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

procedure TStepImages.PrepareImages;
const W=144;H=40;
var Index,Player,Lane,X,Y,I:Integer;DX,DY,MarkX:Double;Inner,Idle:Boolean;
  Pixel:PCardinal;Color,C:TColor;Image:Vcl.Graphics.TBitmap;
begin
  for Index:=0 to High(FImages) do begin
    Player:=(Index div STEP_LANE_COUNT) mod 2;
    Lane:=Index mod STEP_LANE_COUNT;
    Idle:=Index>=StepSpriteCount div 2;
    Color:=LaneColors[Player,Lane];
    Image:=FImages[Index];
    Image.PixelFormat:=pf32bit;Image.SetSize(W,H);Image.AlphaFormat:=afPremultiplied;
    for Y:=0 to H-1 do begin
      Pixel:=Image.ScanLine[Y];
      DY:=Y+0.5-H*0.5;
      for X:=0 to W-1 do begin
        DX:=X+0.5-W*0.5;
        Pixel^:=0;
        if Abs(DX)+Abs(DY)*1.24<W*0.5 then begin
          Inner:=(Abs(DY)<H*0.34) and (Abs(DX)+Abs(DY)*1.24<W*0.5-H*0.14);
          C:=Color;
          if Idle then begin
            C:=Tone(Color,0.65);
            if Inner then C:=Ink;
          end else if Inner then C:=Tone(Color,0.44);
          if Abs(DY)<H*0.25 then
            for I:=0 to Lane do begin
              MarkX:=(I-Lane*0.5)*H*0.54+DY*0.5;
              if Abs(DX-MarkX)<H*0.09 then C:=Pale;
            end;
          Pixel^:=$FF000000 or Cardinal(((C and $FF) shl 16) or (C and $FF00) or ((C shr 16) and $FF));
        end;
        Inc(Pixel);
      end;
    end;
  end;
end;

function StepImages:TAnimationImageBank;
begin
  Result:=TStepImages.Create(StepSpriteCount);
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
    'e':Result:=$1D1FC1E0;
    'p':Result:=$3D18FA10;
    'y':Result:=$2318BC2E;
    '.':Result:=$C6;
    ':':Result:=$008401080;
    '/':Result:=$042222210;
  else
    Result:=0;
  end;
end;

procedure LabelAt(Surface:TAnimationRenderSurface;const Caption:string;X,Y,Cell,Align:Double;Color:TColor;
  JoinPixels:Boolean=False);
var I,Row,Col,Last:Integer;Bits:UInt64;L,T:Double;
begin
  // 描画面の矩形だけで文字を組み、GDIとD2Dで同じレイアウトを使う。
  X:=X-(Length(Caption)*6-1)*Cell*Align;
  for I:=1 to Length(Caption) do begin
    Bits:=Glyph(Caption[I]);
    for Row:=0 to 6 do begin
      Col:=0;
      while Col<5 do begin
        if Bits and (UInt64(1) shl (34-Row*5-Col))<>0 then begin
          Last:=Col;
          if JoinPixels then
            while (Last<4) and (Bits and (UInt64(1) shl (33-Row*5-Last))<>0) do Inc(Last);
          L:=X+((I-1)*6+Col)*Cell;
          T:=Y+Row*Cell;
          Surface.FillRect(L,T,L+Cell*(Last-Col+0.96),T+Cell*0.96,Color);
          Col:=Last;
        end;
        Inc(Col);
      end;
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

procedure TStepAnimation.DrawLegacy(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
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

  LabelAt(Surface,TYPE_D_TITLE,W*0.054,H*0.054,Cell*1.35,0,Pale);
  LabelAt(Surface,Mode,W*0.946,H*0.075,Cell*0.70,1,Quiet);
  Surface.FillRect(W*0.054,H*0.924,W*0.946,H*0.931,Guide);
  if Duration>0 then Surface.FillRect(W*0.054,H*0.924,W*(0.054+0.892*Min(1.0,T/Duration)),H*0.931,LaneColors[0,0]);
  LabelAt(Surface,TimeCode(Min(T,Duration)),W*0.054,H*0.951,Cell*0.80,0,Quiet);
  LabelAt(Surface,Status,W*0.5,H*0.950,Cell*0.89,0.5,Pale);
  LabelAt(Surface,TimeCode(Duration),W*0.946,H*0.951,Cell*0.80,1,Quiet);
end;

procedure TStepAnimation.DrawPatterns(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
const PlayerLabel:array[0..1] of string=('P1','P2');
type TFlash=record
  Age,Power:Double;
end;
var W,H,Scale,Cell,T,Duration,JudgeY,SpawnY,Bottom,DeckWidth,Center,Finish:Double;
  Players,Player,Past,FirstFlash,LastVisible,Stripe,Seconds:Integer;
  Mode,Status:string;
  Latest:TStepNote;

  procedure Text(const Caption:string;X,Y,Size,Align:Double;Color:TColor);
  begin
    LabelAt(Surface,Caption,X,Y,Cell*Size,Align,Color,True);
  end;

  procedure Deck;
  var L,R,LaneW,NoteH,Speed,X,Y,U,Height,EndY,ToX,Power,Age,Radius,Fade,Glow,Distance:Double;
    Lane,I,Mask,NextLane,FirstLane,LastLane:Integer;
    C,Accent:TColor;
    Note,Next:TStepNote;
    Flashes:array[0..STEP_LANE_COUNT-1] of TFlash;

    function LaneX(Index:Integer):Double;
    begin
      Result:=L+(Index+0.5)*LaneW;
    end;

    function YAt(Time:Double):Double;
    begin
      Result:=EnsureRange(JudgeY+(Time-T)*Speed,JudgeY,SpawnY);
    end;

    procedure Sprite(AtX,AtY,Width,TileHeight,Opacity:Double;Index:Integer;Idle:Boolean=False);
    begin
      Surface.DrawAsset(Player*STEP_LANE_COUNT+Index+Ord(Idle)*(StepSpriteCount div 2),
        Point(Round(AtX),Round(AtY)),Max(2,Round(Width*0.5)*2),Max(2,Round(TileHeight*0.5)*2),Opacity,True);
    end;

    procedure Tail(AtX,HeadY,TailY:Double;Color:TColor);
    begin
      Surface.FillRect(AtX-LaneW*0.12,HeadY,AtX+LaneW*0.12,TailY,Tone(Color,0.30));
      Surface.FillRect(AtX-LaneW*0.035,HeadY,AtX+LaneW*0.035,TailY,Color);
      Surface.FillRect(AtX-LaneW*0.15,TailY-Scale,AtX+LaneW*0.15,TailY+Scale,Color);
    end;

    procedure RegisterFlash(Time,Strength:Double;Lanes:Integer);
    var Index:Integer;Elapsed:Double;
    begin
      Elapsed:=Max(0.0,T-Time);
      if (Time>T+STEP_TIME_EPSILON) or (Elapsed>=STEP_FLASH_TIME) then Exit;
      for Index:=0 to STEP_LANE_COUNT-1 do
        if (Lanes and (1 shl Index)<>0) and (Elapsed<Flashes[Index].Age) then begin
          Flashes[Index].Age:=Elapsed;
          Flashes[Index].Power:=EnsureRange(Strength,0.0,1.0);
        end;
    end;

  begin
    L:=Center-DeckWidth*0.5;R:=Center+DeckWidth*0.5;LaneW:=DeckWidth/STEP_LANE_COUNT;
    NoteH:=Min(LaneW*0.30,H*0.036);Speed:=(SpawnY-JudgeY)/STEP_LOOKAHEAD;
    Accent:=LaneColors[Player,0];
    Surface.FillRect(L-2*Scale,H*0.172,R+2*Scale,H*0.217,Ink,0.72);
    for Lane:=0 to STEP_LANE_COUNT-1 do begin
      X:=L+Lane*LaneW;C:=LaneColors[Player,Lane];
      Surface.FillRect(X+Scale,H*0.217,X+LaneW-Scale,Bottom,Ink,0.53);
      Surface.FillRect(X+Scale,Bottom-2*Scale,X+LaneW-Scale,Bottom,Tone(C,0.50));
      Flashes[Lane].Age:=STEP_FLASH_TIME;
      Flashes[Lane].Power:=0;
    end;
    for I:=1 to 7 do begin
      Y:=JudgeY+(Bottom-JudgeY)*I/8;
      Surface.FillRect(L,Y,R,Y+Scale,Guide,0.24);
    end;
    for Lane:=0 to STEP_LANE_COUNT do begin
      X:=Round(L+Lane*LaneW);
      Surface.FillRect(X,H*0.217,X+Max(2,Round(Scale*1.8)),Bottom,Pale,0.85);
    end;
    Text(PlayerLabel[Player],L+9*Scale,H*0.185,0.86,0,Accent);
    Text(FCounter,R-9*Scale,H*0.185,0.77,1,Pale);

    for I:=Past-1 downto Max(0,FirstFlash-1) do begin
      Note:=FPlan.Notes[I];
      Power:=Note.Strength;
      if Note.Kind in [stChord,stRollEnd,stSweepEnd,stSlideEnd] then Power:=Power+0.24;
      if Note.Kind=stHold then RegisterFlash(Note.EndTime,Power+0.20,Note.Lanes[Player]);
      RegisterFlash(Note.Time,Power,Note.Lanes[Player]);
    end;

    // ロングの頭が判定済みでも、離すまでは判定位置と尾を接続する。
    if (Past>0) and (Latest.Kind=stHold) and (T+STEP_TIME_EPSILON<Latest.EndTime) then begin
      Lane:=StepLane(Latest.Lanes[Player]);X:=LaneX(Lane);
      Tail(X,JudgeY,YAt(Latest.EndTime),LaneColors[Player,Lane]);
    end;

    for I:=LastVisible-1 downto Past do begin
      Note:=FPlan.Notes[I];Y:=YAt(Note.Time);
      U:=EnsureRange((Note.Time-T)/STEP_LOOKAHEAD,0.0,1.0);
      Height:=NoteH*(1-0.32*Sqr(U));
      Mask:=Note.Lanes[Player];
      if Note.Kind in [stRoll,stRollEnd] then begin
        // 同じ列の前後間隔に合わせて厚さを抑え、密な連打でも輪郭を分離する。
        if (I>0) and (FPlan.Notes[I-1].Kind=stRoll) then
          Height:=Min(Height,(Note.Time-FPlan.Notes[I-1].Time)*Speed*0.72);
        if Note.Kind=stRoll then Height:=Min(Height,(FPlan.Notes[I+1].Time-Note.Time)*Speed*0.72);
      end;
      if Note.Kind=stSlide then begin
        Next:=FPlan.Notes[I+1];
        if Next.Time<=T+STEP_LOOKAHEAD then begin
          Lane:=StepLane(Mask);NextLane:=StepLane(Next.Lanes[Player]);
          X:=LaneX(Lane);ToX:=LaneX(NextLane);EndY:=YAt(Next.Time);
          Surface.Line(X,Y,ToX,EndY,Tone(LaneColors[Player,Lane],0.42),Max(1.0,Scale*4));
          Surface.Line(X,Y,ToX,EndY,Pale,Max(1.0,Scale));
        end;
      end;
      if Note.Kind=stChord then begin
        FirstLane:=0;LastLane:=STEP_LANE_COUNT-1;
        while Mask and (1 shl FirstLane)=0 do Inc(FirstLane);
        while Mask and (1 shl LastLane)=0 do Dec(LastLane);
        Surface.Line(LaneX(FirstLane),Y,LaneX(LastLane),Y,Tone(Pale,0.68),Max(1.0,Scale*1.5));
      end;
      for Lane:=0 to STEP_LANE_COUNT-1 do if Mask and (1 shl Lane)<>0 then begin
        X:=LaneX(Lane);C:=LaneColors[Player,Lane];
        if Note.Kind=stHold then Tail(X,Y,YAt(Note.EndTime),C);
        Sprite(X,Y,LaneW*0.75,Height,1-0.28*Sqr(U),Lane);
      end;
    end;

    Surface.FillRect(L,JudgeY-Scale,R,JudgeY+Scale,Tone(Accent,0.78));
    if (Past>0) and (Latest.Kind=stSlide) then begin
      // スライド中は判定線上で始点と終点を結ぶ。
      Next:=FPlan.Notes[Past];
      Lane:=StepLane(Latest.Lanes[Player]);NextLane:=StepLane(Next.Lanes[Player]);
      X:=LaneX(Lane);ToX:=LaneX(NextLane);
      U:=EnsureRange((T-Latest.Time)/(Next.Time-Latest.Time),0.0,1.0);
      Surface.Line(X,JudgeY,ToX,JudgeY,LaneColors[Player,Lane],Max(1.0,Scale*3),0.65*(1-U));
    end;

    for Lane:=0 to STEP_LANE_COUNT-1 do begin
      X:=LaneX(Lane);C:=LaneColors[Player,Lane];
      Age:=Flashes[Lane].Age;
      Fade:=1-Age/STEP_FLASH_TIME;
      Glow:=Sqr(Fade);
      Power:=Flashes[Lane].Power;
      if Fade>0 then begin
        U:=1-Fade;
        // 白い閃光と色の残光を判定位置に重ねる。衝撃波もここを中心に広がる。
        Surface.FillRect(X-LaneW*0.48,JudgeY-NoteH*0.90,X+LaneW*0.48,JudgeY+NoteH*0.90,C,Glow*(0.20+0.35*Power));
        Radius:=NoteH*(1.00+0.20*Power+(0.38+0.72*Power)*U);
        Surface.Circle(X,JudgeY,Radius,C,False,Max(1.0,Scale*(1.5+Power*1.5)),Fade*(0.48+Power*0.50));
        if (Power>=0.78) and (Fade>0.48) then
          Surface.Circle(X,JudgeY,Radius*0.82,Pale,False,Max(1.0,Scale*1.35),Glow*0.88);
      end;
      Sprite(X,JudgeY,LaneW*0.83,NoteH*(1.07+Glow*Power*0.20),1,Lane,Fade<0.56);
      if Fade>0.80 then begin
        Surface.FillRect(X-LaneW*0.37,JudgeY-Scale,X+LaneW*0.37,JudgeY+Scale,Pale,Glow*(0.35+0.36*Power));
        Distance:=LaneW*(0.08+Power*0.06);
        Surface.FillRect(X-Distance,JudgeY+NoteH*0.45,X+Distance,JudgeY+NoteH*0.61,Pale);
      end;
    end;
    if (Past>0) and (Latest.Kind=stChord) and (T-Latest.Time<0.13) then begin
      Mask:=Latest.Lanes[Player];FirstLane:=0;LastLane:=STEP_LANE_COUNT-1;
      while Mask and (1 shl FirstLane)=0 do Inc(FirstLane);
      while Mask and (1 shl LastLane)=0 do Dec(LastLane);
      Y:=JudgeY-NoteH*0.82;
      Surface.Line(LaneX(FirstLane),Y,LaneX(LastLane),Y,Tone(Pale,0.45+0.55*(1-(T-Latest.Time)/0.13)),Max(1.0,Scale*2));
    end;
  end;

begin
  W:=Frame.Width;H:=Frame.Height;
  if (W<4) or (H<4) then Exit;
  Scale:=Max(0.30,Min(W,H)/540);
  Cell:=Max(0.50,Min(W*0.0031,H*0.0052));
  T:=Frame.Time;Players:=StepPlayerCount(Frame.Width,Frame.Height);
  JudgeY:=H*0.266;SpawnY:=H*0.86;Bottom:=H*0.889;
  if Players=2 then begin DeckWidth:=Min(H*0.666,W*0.386);Mode:='DUO / AUTO';end
  else begin DeckWidth:=Min(H*0.76,W*0.86);Mode:='SOLO / AUTO';end;
  Duration:=0;Past:=0;FirstFlash:=0;LastVisible:=0;Status:='READY';
  Latest:=Default(TStepNote);
  if FPlan<>nil then begin
    Duration:=FPlan.Duration;
    Past:=FPlan.CountThrough(T);
    FirstFlash:=FPlan.CountThrough(T-STEP_FLASH_TIME);
    LastVisible:=FPlan.CountThrough(T+STEP_LOOKAHEAD);
    Status:='SYNC';
    if FPlan.Count=0 then Status:='NO NOTES'
    else if Past>0 then begin
      Latest:=FPlan.Notes[Past-1];
      if (Latest.Kind in [stRoll,stRollEnd]) and (T-Latest.Time<0.17) then Status:='ROLL';
      Finish:=Max(Latest.Time,Latest.EndTime);
      if (Past=FPlan.Count) and (T+STEP_TIME_EPSILON>=Min(Duration,Finish+STEP_FLASH_TIME)) then Status:='CLEAR';
    end;
  end;
  if (FCounter='') or (FCounterValue<>Past) then begin FCounter:='HITS '+IntToStr(Past);FCounterValue:=Past;end;
  Seconds:=Trunc(Min(T,Duration)+STEP_TIME_EPSILON);
  if (FClock='') or (FClockSecond<>Seconds) then begin FClock:=TimeCode(Seconds);FClockSecond:=Seconds;end;
  Seconds:=Trunc(Duration+STEP_TIME_EPSILON);
  if (FLength='') or (FLengthSecond<>Seconds) then begin FLength:=TimeCode(Seconds);FLengthSecond:=Seconds;end;

  if W/H>1.05 then for Stripe:=0 to 12 do begin
    Surface.Line(W*(0.025+Stripe*0.022),H*0.149,W*(0.048+Stripe*0.009),H*0.904,Tone(LaneColors[0,0],0.22),Scale);
    Surface.Line(W*(0.975-Stripe*0.022),H*0.149,W*(0.952-Stripe*0.009),H*0.904,Tone(LaneColors[1,1],0.22),Scale);
  end;
  Surface.FillRect(W*0.054,H*0.131,W*0.946,H*0.135,Guide);
  Surface.FillRect(W*0.054,H*0.131,W*0.164,H*0.135,LaneColors[0,0]);
  for Player:=0 to Players-1 do begin
    Center:=W*0.5;
    if Players=2 then Center:=W*(0.266+Player*0.468);
    Deck;
  end;
  Text(TYPE_D_TITLE,W*0.054,H*0.054,1.35,0,Pale);
  Text(Mode,W*0.946,H*0.075,0.70,1,Quiet);
  Surface.FillRect(W*0.054,H*0.924,W*0.946,H*0.931,Guide);
  if Duration>0 then Surface.FillRect(W*0.054,H*0.924,W*(0.054+0.892*Min(1.0,T/Duration)),H*0.931,LaneColors[0,0]);
  Text(FClock,W*0.054,H*0.951,0.80,0,Quiet);
  Text(Status,W*0.5,H*0.950,0.89,0.5,Pale);
  Text(FLength,W*0.946,H*0.951,0.80,1,Quiet);
end;

procedure TStepAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
begin
  if FRef.Version>=STEP_PATTERN_VERSION then DrawPatterns(Surface,Frame)
  else DrawLegacy(Surface,Frame);
end;
end.
