unit RhythmRushScene;
// 絶対時刻の戦闘計画を描画。カメラ・姿勢・弾・衝撃はシーク順に依存しない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmRushPlan;

type
  TRushAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio; // 共通レンダラーが所有。
    FRef:TRhythmPlanRef;
    FPlan:TRushPlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    function GoalTime:Double; override;
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;

implementation
uses System.SysUtils,System.Math,System.Types,Vcl.Graphics,Winapi.Windows,RhythmRushCodec;

type
  TRushPalette=record Sky,Fog,Far,Wall,Deck,Trim,Light:TColor; end;
  TFighterPose=record
    Root,Tip:TPointF;
    Size,Face,Stride,Blend,Duck,Tilt:Double;
    Kind:Integer;
    Mob,Boss,HitArm,HitLeg,Guard,Grab:Boolean;
  end;
  TRushPainter=record
    Surface:TAnimationRenderSurface;
    Plan:TRushPlan;
    Time,W,H,Scale,Left,Top:Double;
    Palette:TRushPalette;
    Rotated:Boolean;
    Pivot:TPointF;
    TurnSin,TurnCos,Drop:Double;
    function Screen(X,Y:Double):TPointF;
    procedure Rect(X,Y,Width,Height:Double;Color:TColor);
    procedure Disc(X,Y,R:Double;Color:TColor);
    procedure Line(X,Y,X2,Y2,Width:Double;Color:TColor);
    procedure Poly(const A,B,C,D:TPointF;Color:TColor);
    procedure City(CameraX,CameraY,BossMix:Double);
    procedure Platform;
    procedure Limb(const A,B:TPointF;Bend,Size:Double;Color:TColor;Foot:Boolean);
    procedure Fighter(const Pose:TFighterPose;Fall:Double=0);
    procedure DrawHero(const Root:TPointF;Action:Integer);
    procedure DrawEnemy(Index,Action:Integer);
    procedure Spark(const P:TPointF;Age,Power,Face:Double;Color:TColor;Wide:Boolean);
    procedure DrawCrowd;
    procedure DrawCues;
    procedure DrawRecovery;
    procedure DrawHUD(Stage,Boss:Integer);
    procedure Draw(const Frame:TAnimationFrame);
  end;

const
  Ink=$00231B27;
  Ivory=$00D9F3FF;
  OrbBlue=$00FFCC70;
  ImpactGold=$006FCEFF;
  HeroCoat=$00957C5A;
  MobCoat=$008C3DEA;
  RecoveryGreen=$008DF2A7;
  HeartRed=$008756F7;
  Themes:array[0..4] of TRushPalette=(
    (Sky:$0040212B;Fog:$00765B92;Far:$00574767;Wall:$00583D52;Deck:$00413741;Trim:$00797191;Light:$0075C9FF),
    (Sky:$004E2B18;Fog:$008D643A;Far:$00705235;Wall:$0054442C;Deck:$00463831;Trim:$00927854;Light:$00FAC977),
    (Sky:$00382725;Fog:$006B8471;Far:$00536454;Wall:$00465041;Deck:$0042443A;Trim:$008CA477;Light:$008AF2C4),
    (Sky:$00311B36;Fog:$00704685;Far:$00573865;Wall:$00483257;Deck:$003D2B47;Trim:$007F6591;Light:$00BFABFA),
    (Sky:$003A2020;Fog:$00775763;Far:$00554C6A;Wall:$0040405D;Deck:$00403E52;Trim:$008882B9;Light:$0068A6F8));
  BossCoats:array[0..5] of TColor=($005D61BE,$00D38DCE,$008A628B,$004E9ED5,$00C1D275,$00B27153);

function Tint(A,B:TColor;U:Double):TColor;
begin
  Result:=RGB(Round(RushMix(GetRValue(A),GetRValue(B),U)),
    Round(RushMix(GetGValue(A),GetGValue(B),U)),Round(RushMix(GetBValue(A),GetBValue(B),U)));
end;

function BlendPalette(const A,B:TRushPalette;U:Double):TRushPalette;
begin
  Result.Sky:=Tint(A.Sky,B.Sky,U);
  Result.Fog:=Tint(A.Fog,B.Fog,U);
  Result.Far:=Tint(A.Far,B.Far,U);
  Result.Wall:=Tint(A.Wall,B.Wall,U);
  Result.Deck:=Tint(A.Deck,B.Deck,U);
  Result.Trim:=Tint(A.Trim,B.Trim,U);
  Result.Light:=Tint(A.Light,B.Light,U);
end;

function Wrap(X,Span:Double):Double;
begin
  Result:=X-Floor(X/Span)*Span;
end;

function PoseBlend(const A:TRushCue;Time:Double):Double;
begin
  if Time<=A.Time then Result:=RushEase(1-(A.Time-Time)/Windup(A.Move))
  else Result:=1-RushEase((Time-A.Time)/0.115);
end;

function TRushPainter.Screen(X,Y:Double):TPointF;
var DX,DY:Double;
begin
  if Rotated then begin
    DX:=X-Pivot.X;
    DY:=Y-Pivot.Y;
    X:=Pivot.X+DX*TurnCos-DY*TurnSin;
    Y:=Pivot.Y+DX*TurnSin+DY*TurnCos-Drop;
  end;
  Result:=PointF((X-Left)*Scale,(Top-Y)*Scale);
end;

procedure TRushPainter.Rect(X,Y,Width,Height:Double;Color:TColor);
var P:TPointF;
begin
  if Rotated then begin
    Poly(PointF(X,Y),PointF(X+Width,Y),PointF(X+Width,Y-Height),PointF(X,Y-Height),Color);
    Exit;
  end;
  P:=Screen(X,Y);
  Surface.FillRect(P.X,P.Y,P.X+Width*Scale,P.Y+Height*Scale,Color);
end;

procedure TRushPainter.Disc(X,Y,R:Double;Color:TColor);
var P:TPointF;
begin
  P:=Screen(X,Y);
  Surface.Circle(P.X,P.Y,R*Scale,Color,True);
end;

procedure TRushPainter.Line(X,Y,X2,Y2,Width:Double;Color:TColor);
var P,Q:TPointF;
begin
  P:=Screen(X,Y);
  Q:=Screen(X2,Y2);
  Surface.Line(P.X,P.Y,Q.X,Q.Y,Color,Max(1.0,Scale*Width));
end;

procedure TRushPainter.Poly(const A,B,C,D:TPointF;Color:TColor);
begin
  Surface.FillQuad(Screen(A.X,A.Y),Screen(B.X,B.Y),Screen(C.X,C.Y),Screen(D.X,D.Y),Color);
end;

procedure TRushPainter.City(CameraX,CameraY,BossMix:Double);
var I,J,Layer,ID,Cols:Integer; X,Y,R,Tile,Shift,Base,Width,Lift:Double; C,WindowColor:TColor;
begin
  for I:=0 to 16 do
    Surface.FillRect(0,H*I/17,W,H*(I+1)/17+1,Tint(Palette.Sky,Palette.Fog,I/19));
  X:=W*0.77+Sin(CameraX*0.019)*W*0.10;
  Y:=H*0.25+CameraY*Scale*0.09;
  R:=Min(W,H)*0.09;
  Surface.Circle(X,Y,R*1.33,Tint(Palette.Sky,Palette.Fog,0.42),True);
  Surface.Circle(X,Y,R,Tint(Palette.Fog,Palette.Light,0.62),True);
  for Layer:=0 to 1 do begin
    Tile:=Scale*(2.10+Layer*0.90);
    Shift:=CameraX*Scale*(0.18+0.17*Layer);
    Lift:=CameraY*Scale*(0.13+Layer*0.12);
    if Layer=0 then C:=Palette.Far else C:=Palette.Wall;
    WindowColor:=Tint(C,Palette.Light,0.28+BossMix*0.19);
    for I:=-1 to Ceil(W/Tile)+1 do begin
      ID:=Floor(Shift/Tile)+I;
      X:=Tile*I-Wrap(Shift,Tile);
      Base:=H*(0.75+Layer*0.08)+Lift;
      Width:=Tile*(0.62+0.13*Cos(ID*2.29+Layer));
      R:=Scale*(0.8+1.55*(0.5+0.5*Sin(ID*1.91+Layer)));
      Y:=Base-R;
      Surface.FillRect(X,Y,X+Width,H,C);
      Surface.FillRect(X+Width*0.69,Y-Scale*0.19,X+Width,Y+Scale*0.08,C);
      if (ID mod 3)=0 then Surface.Line(X+Width*0.88,Y-Scale*0.54,X+Width*0.88,Y,WindowColor,1.3);
      Cols:=2+Layer;
      for J:=0 to Cols-1 do
        Surface.FillRect(X+Width*(J+0.6)/(Cols+0.5),Y+R*0.29,
          X+Width*(J+0.82)/(Cols+0.5),Y+R*0.52,WindowColor);
    end;
  end;
end;

procedure TRushPainter.Platform;
var I,J:Integer; X,Span:Double;
begin
  Span:=W/Scale;
  Rect(Left,0,Span,2.45,Palette.Deck);
  Rect(Left,0,Span,0.075,Palette.Trim);
  Rect(Left,-0.38,Span,0.040,Tint(Palette.Deck,Palette.Trim,0.40));
  for I:=Floor(Left/1.45)-1 to Ceil((Left+Span)/1.45) do begin
    X:=I*1.45;
    Line(X,-0.08,X-0.28,-0.74,0.028,Tint(Palette.Deck,Ink,0.32));
    if I mod 4=0 then for J:=0 to 3 do
      Rect(X+J*0.17,-0.19,0.085,0.035,Tint(Palette.Deck,Palette.Light,0.48));
  end;
end;

procedure TRushPainter.Limb(const A,B:TPointF;Bend,Size:Double;Color:TColor;Foot:Boolean);
var X,Y:Double;
begin
  X:=RushMix(A.X,B.X,0.48)+Size*Bend;
  Y:=RushMix(A.Y,B.Y,0.48)-Size*Abs(Bend)*0.32;
  Line(A.X,A.Y,X,Y,Size*0.195,Ink);
  Line(X,Y,B.X,B.Y,Size*0.165,Ink);
  Line(A.X,A.Y,X,Y,Size*0.136,Color);
  Line(X,Y,B.X,B.Y,Size*0.105,Color);
  if Foot then Rect(B.X-Size*0.12,B.Y+Size*0.055,Size*0.24,Size*0.085,Ink)
  else begin
    Disc(B.X,B.Y,Size*0.086,Ink);
    Disc(B.X,B.Y,Size*0.059,Tint(Color,Ivory,0.57));
  end;
end;

procedure TRushPainter.Fighter(const Pose:TFighterPose;Fall:Double);
var
  X,Y,S,F,Breadth,Head,Lean,Step,Duck,FootY:Double;
  Coat,Dark,Skin,Hair:TColor;
  A,B,C,D,Hand,Toe:TPointF;
begin
  X:=Pose.Root.X;
  Y:=Pose.Root.Y;
  S:=Pose.Size;
  F:=Pose.Face;
  Breadth:=RushBreadth(Pose.Kind);
  Coat:=HeroCoat;
  if Pose.Boss then Coat:=BossCoats[Pose.Kind];
  if Pose.Mob then Coat:=MobCoat;
  Dark:=Tint(Coat,Ink,0.47);
  Skin:=Tint($0099BBF0,Coat,0.14+0.06*Pose.Kind);
  Hair:=Tint(Ink,Coat,0.43);
  Lean:=F*S*Pose.Tilt;
  Duck:=Pose.Duck*S;
  Rotated:=Fall>0;
  if Rotated then begin
    // 全パーツを腰の周りに回転させ、寝た姿が地面付近に収まるよう下ろす。
    Pivot:=PointF(X,Y+0.56*S);
    SinCos(F*Fall*Pi/2,TurnSin,TurnCos);
    Drop:=S*(0.56*(1-TurnCos)-0.33*Abs(TurnSin));
  end;
  Head:=Y+S*(1.05+0.012*Pose.Kind)-Duck;
  Step:=Pose.Stride*S;
  FootY:=Y+0.065*S;
  A:=PointF(X-S*0.095,Y+S*0.51-Duck*0.43);
  B:=PointF(X-F*S*0.10+Step,FootY+S*0.65*Max(0.0,Pose.Stride));
  Limb(A,B,-F*0.11,S,Dark,True);
  A:=PointF(X+Lean-F*S*0.14,Y+S*0.82-Duck);
  Hand:=PointF(A.X-F*S*(0.12+Pose.Stride*0.41),A.Y-S*0.28);
  if Pose.Grab then
    Hand:=PointF(RushMix(Hand.X,Pose.Tip.X-F*S*0.07,Pose.Blend),RushMix(Hand.Y,Pose.Tip.Y+S*0.13,Pose.Blend));
  Limb(A,Hand,F*0.07,S,Dark,False);
  A:=PointF(X+Lean-S*0.23*Breadth,Y+S*0.94-Duck);
  B:=PointF(X+Lean+S*0.22*Breadth,Y+S*0.91-Duck);
  C:=PointF(X+S*0.16*Breadth,Y+S*0.45-Duck*0.55);
  D:=PointF(X-S*0.17*Breadth,Y+S*0.47-Duck*0.55);
  Poly(A,B,C,D,Ink);
  A.X:=A.X+S*0.039; A.Y:=A.Y-S*0.046;
  B.X:=B.X-S*0.042; B.Y:=B.Y-S*0.040;
  C.X:=C.X-S*0.032; C.Y:=C.Y+S*0.036;
  D.X:=D.X+S*0.029; D.Y:=D.Y+S*0.039;
  Poly(A,B,C,D,Coat);
  Line(A.X+S*0.03,A.Y-S*0.07,C.X,C.Y+S*0.10,S*0.052,Tint(Coat,Ivory,0.37));
  Line(X-S*0.15*Breadth,Y+S*0.52-Duck*0.61,X+S*0.16*Breadth,Y+S*0.52-Duck*0.61,S*0.055,Dark);

  A:=PointF(X+F*S*0.096,Y+S*0.51-Duck*0.43);
  Toe:=PointF(X+F*S*0.15-Step,FootY+S*0.65*Max(0.0,-Pose.Stride));
  if Pose.HitLeg then Toe:=PointF(RushMix(Toe.X,Pose.Tip.X,Pose.Blend),RushMix(Toe.Y,Pose.Tip.Y,Pose.Blend));
  Limb(A,Toe,F*0.10,S,Coat,True);

  Disc(X+Lean,Head,S*0.204,Ink);
  Disc(X+Lean+F*S*0.025,Head-S*0.013,S*0.169,Skin);
  if Pose.Mob or (Pose.Kind in [1,4]) then begin
    Rect(X+Lean-S*0.182,Head+S*0.092,S*0.364,S*0.076,Coat);
    Line(X+Lean-F*S*0.14,Head+S*0.068,X+Lean-F*S*0.30,Head+S*0.025,S*0.044,Coat);
  end else
    Rect(X+Lean-S*0.176,Head+S*0.159,S*0.352,S*0.117,Hair);
  Rect(X+Lean+F*S*0.077-S*0.032,Head+S*0.026,S*0.064,S*0.036,Ink);
  if Pose.Kind in [2,5] then Line(X+Lean-F*S*0.11,Head-S*0.10,X+Lean+F*S*0.08,Head-S*0.115,S*0.052,Hair);
  if Pose.Boss and (Pose.Kind in [0,5]) then begin
    Disc(X+Lean-S*0.27*Breadth,Y+S*0.84-Duck,S*0.126,Dark);
    Disc(X+Lean+S*0.26*Breadth,Y+S*0.84-Duck,S*0.118,Dark);
  end;
  A:=PointF(X+Lean+F*S*0.135,Y+S*0.83-Duck);
  Hand:=PointF(A.X+F*S*(0.15+Pose.Stride*0.54),A.Y-S*0.24);
  if Pose.HitArm or Pose.Guard then
    Hand:=PointF(RushMix(Hand.X,Pose.Tip.X,Pose.Blend),RushMix(Hand.Y,Pose.Tip.Y,Pose.Blend));
  Limb(A,Hand,-F*0.085,S,Coat,False);
  if (Pose.Boss and (Pose.Kind=2)) or (Pose.Mob and (Pose.Kind=3)) then begin
    // 武器を振る時は手元を内側へ引き、先端が同じ接触点に届く。
    if Pose.HitArm then begin
      C:=PointF(Hand.X+F*S*0.33,Hand.Y+S*0.10);
      Line(Hand.X,Hand.Y,C.X,C.Y,S*0.096,Ink);
      Line(Hand.X,Hand.Y,C.X,C.Y,S*0.047,Ivory);
    end else begin
      Line(Hand.X-F*S*0.10,Hand.Y-S*0.12,Hand.X+F*S*0.29,Hand.Y+S*0.53,S*0.085,Ink);
      Line(Hand.X,Hand.Y+S*0.05,Hand.X+F*S*0.29,Hand.Y+S*0.53,S*0.042,Ivory);
    end;
  end;
  Rotated:=False;
end;

procedure TRushPainter.DrawHero(const Root:TPointF;Action:Integer);
var Pose:TFighterPose; A:TRushCue; T,L:Double; I:Integer;
begin
  Pose:=Default(TFighterPose);
  Pose.Root:=Root;
  Pose.Size:=1;
  Pose.Face:=1;
  Pose.Tilt:=0.07;
  T:=(Root.X-Plan.Hero(Time-0.05).X)*20;
  Pose.Stride:=Sin(Time*14+Root.X*2.2)*EnsureRange(T*0.085,0.0,0.34);
  if Root.Y>0 then Pose.Stride:=0.09;
  if Time>=Plan.Finish then Pose.Stride:=0;
  if Action>=0 then begin
    A:=Plan.Cues[Action];
    Pose.Face:=Plan.Foes[A.Foe].Side;
    Pose.Blend:=PoseBlend(A,Time);
    Pose.Stride:=Pose.Stride*(1-Pose.Blend);
    Pose.Tilt:=0.07+Pose.Blend*0.09;
    if Defensive(A.Move) then begin
      Pose.Tip:=Plan.Incoming(Action);
      Pose.Guard:=A.Move=raGuard;
      if A.Move=raDodge then begin
        if Plan.Threat(Action)=rtSweep then
          Pose.Root.Y:=Pose.Root.Y+0.49*Pose.Blend
        else Pose.Duck:=0.32*Pose.Blend;
        Pose.Tilt:=-0.21*Pose.Blend;
      end;
      if A.Move=raHurt then begin
        // 被弾した拍で上体を反らせ、次の反撃に向けて戻す。
        Pose.Tilt:=-0.44*Pose.Blend;
        Pose.Duck:=0.18*Pose.Blend;
      end;
    end else if not (A.Move in [raOrb,raCrash]) then begin
      Pose.Tip:=Plan.Impact(Action);
      Pose.HitLeg:=Kicking(A.Move);
      Pose.HitArm:=not Pose.HitLeg;
      Pose.Grab:=A.Move=raThrow;
    end;
  end;
  // 弾を出すフレームでは手が発射点まで伸びる。密集音でも同じ構えから撃てる。
  if not (Pose.HitArm or Pose.HitLeg or Pose.Guard or (Pose.Duck>0.10)) then begin
    I:=Plan.CueFrom(Time-0.10);
    while (I<Length(Plan.Cues)) and (Plan.Cues[I].Time<Time+0.52) do begin
      A:=Plan.Cues[I];
      L:=Time-(A.Time-A.Flight);
      if (A.Move=raOrb) and (Abs(L)<0.095) then begin
        Pose.Face:=Plan.Foes[A.Foe].Side;
        Pose.HitArm:=True;
        Pose.Blend:=1-RushEase(Abs(L)/0.095);
        Pose.Tip:=Plan.Projectile(I,A.Time-A.Flight);
        Break;
      end;
      Inc(I);
    end;
  end;
  Fighter(Pose);
end;

procedure TRushPainter.DrawEnemy(Index,Action:Integer);
var F:TRushFoe; Pose:TFighterPose; A:TRushCue; P:TPointF; Age,Start,Recoil:Double; Threat:TRushThreat;
begin
  F:=Plan.Foes[Index];
  Start:=Plan.Entry(Index);
  Age:=Time-Plan.Cues[F.Last].Time;
  if (Time<Start) or (Age>0.93) then Exit;
  Pose:=Default(TFighterPose);
  Pose.Root:=Plan.Enemy(Index,Time);
  if (Pose.Root.X<Left-2) or (Pose.Root.X>Left+W/Scale+2) then Exit;
  Pose.Size:=Plan.BodySize(Index);
  Pose.Kind:=F.Kind;
  Pose.Boss:=F.Boss;
  Pose.Mob:=not F.Boss;
  Pose.Face:=-F.Side;
  Pose.Tilt:=0.04;
  Pose.Stride:=Sin((Time-Max(0.0,Age)-Start)*19+Index)*0.18;
  if Time>Plan.Cues[F.First].Time then Pose.Stride:=Pose.Stride*0.41;
  if Age>=0 then Action:=F.Last;
  if (Action>=F.First) and (Action<=F.Last) then begin
    A:=Plan.Cues[Action];
    Pose.Blend:=PoseBlend(A,Time);
    if Defensive(A.Move) then begin
      Pose.Tip:=Plan.Incoming(Action);
      Threat:=Plan.Threat(Action);
      Pose.HitLeg:=Threat in [rtKick,rtSweep];
      Pose.HitArm:=not Pose.HitLeg;
      case Threat of
        rtRush:Pose.Tilt:=0.31*Pose.Blend;
        rtGrab:begin Pose.Tilt:=0.18*Pose.Blend; Pose.Grab:=True; end;
        rtSweep:Pose.Duck:=0.19*Pose.Blend;
      end;
      if Threat=rtWeapon then begin
        Pose.Tip.X:=Pose.Tip.X-Pose.Face*Pose.Size*0.33;
        Pose.Tip.Y:=Pose.Tip.Y-Pose.Size*0.10;
      end;
      if (Threat=rtOrb) and (A.Flight>0) then begin
        P:=Plan.Projectile(Action,A.Time-A.Flight);
        Pose.Tip:=PointF(P.X,P.Y);
      end;
    end else if Time>A.Time then begin
      Recoil:=Pose.Blend*RushEase((Time-A.Time)/0.042);
      Pose.Tilt:=-0.29*Recoil;
      Pose.Duck:=0.12*Recoil;
    end;
  end;
  Fighter(Pose,RushEase(Age/0.28));
end;

procedure TRushPainter.Spark(const P:TPointF;Age,Power,Face:Double;Color:TColor;Wide:Boolean);
var I:Integer; U,Angle,R,DX,DY:Double; C:TColor;
begin
  U:=Age/(0.14+Power*0.095);
  if (U<0) or (U>=1) then Exit;
  R:=0.16+U*(0.49+Power*0.23+0.26*Ord(Wide));
  C:=Tint(Color,Ivory,0.42*(1-U));
  if U<0.40 then Disc(P.X,P.Y,0.17*(1-U),C);
  for I:=0 to 4+3*Ord(Wide) do begin
    Angle:=I*2.399+0.33;
    DX:=Face*Cos(Angle)*R;
    DY:=Sin(Angle)*R*0.68;
    Line(P.X+DX*0.52,P.Y+DY*0.52,P.X+DX,P.Y+DY,(0.057+Power*0.02)*(1-U),C);
  end;
end;

procedure TRushPainter.DrawCrowd;
var I,J,EndIndex:Integer; A:TRushCue; Age:Double; Pose:TFighterPose;
begin
  I:=Plan.CueFrom(Time-0.64);
  EndIndex:=Plan.CueFrom(Time+0.65);
  while I<EndIndex do begin
    A:=Plan.Cues[I];
    Age:=Time-A.Time;
    for J:=0 to Plan.CrowdExtras(I)-1 do begin
      Pose:=Default(TFighterPose);
      Pose.Root:=Plan.CrowdEnemy(I,J,Time);
      Pose.Face:=-Plan.Foes[A.Foe].Side;
      Pose.Kind:=(Plan.Foes[A.Foe].Kind+J+1) mod 6;
      Pose.Size:=0.86+J*0.12;
      Pose.Mob:=True;
      Pose.Stride:=Sin((Time-Max(0.0,Age))*20+J)*0.16;
      Fighter(Pose,RushEase(Age/0.28));
      if Age>=0 then Spark(PointF(Pose.Root.X,Pose.Root.Y+0.62),Age,A.Power,-Pose.Face,ImpactGold,False);
    end;
    Inc(I);
  end;
end;

procedure TRushPainter.DrawCues;
var I,EndIndex,Drawn:Integer; A:TRushCue; F:TRushFoe; P,Q:TPointF; Age,U:Double; C:TColor;
begin
  I:=Plan.CueFrom(Time-0.23);
  EndIndex:=Plan.CueFrom(Time+0.47);
  Drawn:=0;
  while I<EndIndex do begin
    A:=Plan.Cues[I];
    F:=Plan.Foes[A.Foe];
    Age:=Time-A.Time;
    C:=OrbBlue;
    if Defensive(A.Move) then C:=$007FB5FF;
    if (A.Flight>0) and (Age<0) and (Age>=-A.Flight) and (Drawn<16) then begin
      P:=Plan.Projectile(I,Time);
      Q:=Plan.Projectile(I,Max(A.Time-A.Flight,Time-0.042));
      Line(Q.X,Q.Y,P.X,P.Y,0.10,Tint(C,Palette.Fog,0.28));
      Disc(P.X,P.Y,0.125,C);
      Disc(P.X,P.Y,0.065,Ivory);
      Inc(Drawn);
    end;
    if Age>=0 then begin
      if Defensive(A.Move) then begin
        P:=Plan.Incoming(I);
        case A.Move of
          raGuard:Spark(P,Age,0.45,F.Side,$00EBE19D,False);
          raDodge:if Age<0.095 then Line(P.X-F.Side*0.38,P.Y,P.X+F.Side*0.43,P.Y+0.095,
            0.045*(1-Age/0.10),Tint(OrbBlue,Ivory,0.43));
          raHurt:Spark(P,Age,0.75,-F.Side,HeartRed,True);
        end;
      end else begin
        P:=Plan.Impact(I);
        C:=ImpactGold;
        if A.Move=raOrb then C:=OrbBlue;
        Spark(P,Age,A.Power,F.Side,C,A.Move in [raSpecial,raSlam,raCrash]);
        if (Age<0.082) and (A.Move in [raPunch,raKick,raAirPunch,raAirKick,raLaunch,raCounter]) then
          Line(P.X-F.Side*0.42,P.Y-0.13,P.X-F.Side*0.09,P.Y-0.026,
            0.039*(1-Age/0.09),Tint(Palette.Light,Ivory,0.51));
        if A.Move=raSlam then Spark(PointF(P.X,0.04),Age,A.Power,F.Side,Palette.Trim,True);
        if (A.Move=raSpecial) and (Age<0.23) then begin
          U:=Age/0.23;
          Q:=Screen(P.X,P.Y);
          Surface.Circle(Q.X,Q.Y,Scale*(0.19+1.20*U),C,False,Scale*0.083*(1-U));
          Disc(P.X,P.Y,0.38*Sqr(1-U),Tint(C,Ivory,0.53));
        end;
      end;
    end;
    Inc(I);
  end;
end;

procedure TRushPainter.DrawRecovery;
var I,Limit:Integer; P:TPointF; Age,S,Glow:Double;

  procedure Heart(Size:Double;Color:TColor);
  begin
    Disc(P.X-Size*0.46,P.Y+Size*0.19,Size*0.55,Color);
    Disc(P.X+Size*0.46,P.Y+Size*0.19,Size*0.55,Color);
    Poly(PointF(P.X-Size,P.Y+Size*0.12),PointF(P.X+Size,P.Y+Size*0.12),
      PointF(P.X+Size*0.04,P.Y-Size),PointF(P.X-Size*0.04,P.Y-Size),Color);
  end;

begin
  I:=Plan.CueFrom(Time-0.44);
  Limit:=Plan.CueFrom(Time+1.65);
  while I<Limit do begin
    if Plan.Cues[I].Recovery then begin
      Age:=Time-Plan.Cues[I].Time;
      P:=Plan.Hero(Plan.Cues[I].Time);
      P.Y:=P.Y+0.86;
      if Age<0 then begin
        P.Y:=P.Y+Sin(Age*9)*0.09*Min(1.0,-Age*4);
        S:=0.24+0.018*Sin(Age*9);
        Heart(S+0.039,Ink);
        Heart(S,HeartRed);
        Disc(P.X-S*0.50,P.Y+S*0.37,S*0.16,Ivory);
      end else begin
        Spark(P,Age,0.60,1,RecoveryGreen,True);
        Glow:=1-Age/0.44;
        P.Y:=P.Y+Age*1.3;
        S:=0.16;
        Line(P.X-S,P.Y,P.X+S,P.Y,0.065*Glow,RecoveryGreen);
        Line(P.X,P.Y-S,P.X,P.Y+S,0.065*Glow,RecoveryGreen);
      end;
    end;
    Inc(I);
  end;
end;

procedure TRushPainter.DrawHUD(Stage,Boss:Integer);
var I,Hp:Integer; U,X,Y:Double; C:TColor;
begin
  U:=Max(2.0,Scale*0.075);
  X:=W*0.06;
  Y:=H*0.066;
  Surface.FillRect(X-U*2,Y-U*2,X+U*12,Y+U*2,Ink);
  for I:=1 to 5 do begin
    C:=Tint(Palette.Sky,Palette.Light,0.35);
    if I<=Plan.Stages[Stage].Level then C:=Palette.Light;
    Surface.FillRect(X+U*(I*2-2),Y-U*0.60,X+U*(I*2-0.6),Y+U*0.60,C);
  end;
  Hp:=Plan.Health(Time);
  X:=W*0.06;
  Y:=Y+U*2.7;
  Surface.FillRect(X-U*2,Y-U*0.82,X+U*12,Y+U*0.82,Ink);
  for I:=1 to RushMaxHealth do begin
    C:=Tint(Palette.Sky,HeartRed,0.22);
    if I<=Hp then C:=RecoveryGreen;
    if (I<=Hp) and (Hp<=2) then C:=HeartRed;
    Surface.FillRect(X+U*(I*2-2),Y-U*0.41,X+U*(I*2-0.25),Y+U*0.41,C);
  end;
  if Boss>=0 then begin
    X:=W*0.35;
    U:=W*0.30;
    Surface.FillRect(X-3,Y-5,X+U+3,Y+5,Ink);
    Surface.FillRect(X,Y-2,X+U,Y+2,Tint(Palette.Sky,Palette.Trim,0.47));
    U:=U*(Plan.Foes[Boss].Last-EnsureRange(Plan.CueFrom(Time),Plan.Foes[Boss].First,
      Plan.Foes[Boss].Last))/(Plan.Foes[Boss].Last-Plan.Foes[Boss].First);
    Surface.FillRect(X,Y-2,X+U,Y+2,ImpactGold);
  end;
end;

procedure TRushPainter.Draw(const Frame:TAnimationFrame);
var
  S,J,I,First,Last,Act,Boss,Candidate,Previous:Integer;
  Root,Before,After:TPointF;
  CamX,CamY,U,BossMix,Zoom,Age,T:Double;
begin
  W:=Frame.Width;
  H:=Frame.Height;
  Time:=EnsureRange(Frame.Time,0.0,Plan.Duration);
  S:=Plan.StageAt(Time);
  J:=S;
  U:=0;
  if (S>0) and (Time<Plan.Stages[S].StartTime+0.63) then begin
    J:=S-1;
    U:=1-RushEase((Time-Plan.Stages[S].StartTime+0.63)/1.26);
  end else if (S<High(Plan.Stages)) and (Time>Plan.Stages[S+1].StartTime-0.63) then begin
    J:=S+1;
    U:=RushEase((Time-Plan.Stages[J].StartTime+0.63)/1.26);
  end;
  Palette:=BlendPalette(Themes[Plan.Stages[S].Theme],Themes[Plan.Stages[J].Theme],U);
  Root:=Plan.Hero(Time);
  Before:=Plan.Hero(Time-0.24);
  After:=Plan.Hero(Time+0.30);
  CamX:=Root.X*0.60+Before.X*0.22+After.X*0.18;
  CamY:=Root.Y*0.55+Before.Y*0.19+After.Y*0.26;
  Boss:=-1;
  BossMix:=0;
  for I:=Max(0,S-1) to Min(High(Plan.Stages),S+1) do begin
    Candidate:=Plan.Stages[I].Boss;
    if Candidate<0 then Continue;
    U:=RushEase((Time-Plan.Entry(Candidate))/0.52)*(1-RushEase(
      (Time-Plan.Cues[Plan.Foes[Candidate].Last].Time)/0.63));
    if U>BossMix then begin
      Boss:=Candidate;
      BossMix:=U;
    end;
  end;
  Zoom:=1-0.086*BossMix+0.084*Min(1.0,CamY);
  Previous:=Plan.CueFrom(Time+1E-8)-1;
  if Previous>=0 then begin
    T:=Plan.Cues[Previous].Time;
    Age:=Time-T;
    if (Age>=0) and (Age<0.23) and (Plan.Cues[Previous].Move in [raSpecial,raSlam,raCrash]) then begin
      U:=1-RushEase(Age/0.23);
      Zoom:=Zoom+0.035*U;
      CamX:=CamX+Sin(Age*91)*0.10*U;
    end;
  end;
  Scale:=Min(W/11.5,H/6.7)*Zoom;
  Left:=CamX-W/Scale*0.42;
  Top:=CamY+H/Scale*0.66;
  Rotated:=False;
  City(CamX,CamY,BossMix);
  Platform;
  if Frame.BackgroundOnly then Exit;
  Act:=Plan.MoveAt(Time);
  First:=Plan.FoeFromCue(Plan.CueFrom(Time-0.93));
  Last:=Min(High(Plan.Foes),Plan.FoeFromCue(Plan.CueFrom(Time+2.21)));
  DrawCrowd;
  for I:=Last downto First do DrawEnemy(I,Act);
  DrawHero(Root,Act);
  DrawRecovery;
  DrawCues;
  DrawHUD(S,Boss);
end;

destructor TRushAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TRushAnimation.SetReference(const Ref:TRhythmPlanRef);
begin
  FRef:=Ref;
end;

procedure TRushAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try
    FPlan:=LoadRushPlan(FRef,FAudio,Frame.Direction);
  except
    on E:Exception do FError:=E.Message;
  end;
end;

procedure TRushAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Painter:TRushPainter;
begin
  if FPlan=nil then Exit;
  Painter.Surface:=Surface;
  Painter.Plan:=FPlan;
  Painter.Draw(Frame);
end;

function TRushAnimation.Notice:string;
begin
  Result:=FError;
end;

function TRushAnimation.GoalTime:Double;
begin
  Result:=inherited GoalTime;
  if FPlan<>nil then Result:=FPlan.Finish;
end;
end.
