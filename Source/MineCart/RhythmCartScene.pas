unit RhythmCartScene;
// 左下寄りにトロッコを置き、地形と危険の世界座標を同じカメラで流す。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmCartPlan;

type
  TCartAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TCartPlan;
    FAttempt,FError:string;
  public
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    function GoalTime:Double;override;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;

implementation
uses System.SysUtils,System.Math,System.Types,Vcl.Graphics,Winapi.Windows,RhythmCartCodec;

type
  TCartPalette=record
    Sky,Horizon,Far,Near,Beam,Metal,Accent:TColor;
  end;
  TCartPainter=record
    Surface:TAnimationRenderSurface;
    Plan:TCartPlan;
    Time,W,H,Scale,Left,Top,FirstTime,LastTime:Double;
    Palette:TCartPalette;
    function Screen(X,Y:Double):TPointF;
    procedure Line(X,Y,X2,Y2,Width:Double;Color:TColor);
    procedure Dot(X,Y,Radius:Double;Color:TColor);
    procedure Quad(const A,B,C,D:TPointF;Color:TColor);
    procedure CartBody(X,Y,Angle,Size:Double;Color:TColor;Armored:Boolean;Facing:Integer=1;
      Crouch:Double=0;Boss:Boolean=False;Rider:Boolean=True);
    procedure WingEnemy(X,TopY,Age:Double);
    procedure Sparks(X,Y,Age,Size:Double;Color:TColor);
    procedure Bomb(const P:TPointF;Age:Double);
    procedure Blast(const P:TPointF;Age:Double);
    procedure Background(const Hero:TCartPosition;Theme:Integer);
    procedure SpeedLines(const Hero:TCartPosition);
    procedure Rails;
    procedure Moves;
    procedure FallingRocks;
    procedure Hazard(const Move:TCartMove;const Base:TCartPosition);
    procedure Rival(const Move:TCartMove);
    procedure Convoy(Index:Integer);
    procedure LegacyConvoy(Index:Integer);
    procedure BossVolley(Index,Car:Integer;const P:TCartPosition);
    procedure BossCrash(const P:TCartPosition;Age,Size:Double;Color:TColor;FinalCar:Boolean);
    procedure Coins;
    procedure Gate;
    procedure Finish;
    procedure Draw(const Frame:TAnimationFrame);
  end;

const
  Ink=$00231C18;
  White=$00DFFFFF;
  Gold=$0041CBFF;
  Copper=$004B88B9;
  HeroBlue=$00DAB264;
  Palettes:array[0..4] of TCartPalette=(
    (Sky:$00251D18;Horizon:$004D3228;Far:$00423126;Near:$00392D24;Beam:$00515375;Metal:$00AAC7CA;Accent:$0063B5F9),
    (Sky:$008D5742;Horizon:$00C9AC83;Far:$008C7365;Near:$006E4D43;Beam:$00495269;Metal:$00CBD8DB;Accent:$0084F4F9),
    (Sky:$00371D20;Horizon:$00664239;Far:$00552F3E;Near:$00422A36;Beam:$00534974;Metal:$00C7B6D5;Accent:$00E795F3),
    (Sky:$00271C2B;Horizon:$005846A5;Far:$004D326A;Near:$003A2650;Beam:$00524776;Metal:$009BBAD2;Accent:$004C83FF),
    (Sky:$00422316;Horizon:$007A6240;Far:$00564532;Near:$004A3828;Beam:$00586D71;Metal:$00ADDAD7;Accent:$00F0E373));

function Tint(A,B:TColor;U:Double):TColor;
begin
  Result:=RGB(Round(GetRValue(A)+(GetRValue(B)-GetRValue(A))*U),
    Round(GetGValue(A)+(GetGValue(B)-GetGValue(A))*U),
    Round(GetBValue(A)+(GetBValue(B)-GetBValue(A))*U));
end;

function FadePalette(const A,B:TCartPalette;U:Double):TCartPalette;
begin
  Result.Sky:=Tint(A.Sky,B.Sky,U);
  Result.Horizon:=Tint(A.Horizon,B.Horizon,U);
  Result.Far:=Tint(A.Far,B.Far,U);
  Result.Near:=Tint(A.Near,B.Near,U);
  Result.Beam:=Tint(A.Beam,B.Beam,U);
  Result.Metal:=Tint(A.Metal,B.Metal,U);
  Result.Accent:=Tint(A.Accent,B.Accent,U);
end;

function TCartPainter.Screen(X,Y:Double):TPointF;
begin
  Result:=PointF((X-Left)*Scale,(Top-Y)*Scale);
end;

procedure TCartPainter.Line(X,Y,X2,Y2,Width:Double;Color:TColor);
var A,B:TPointF;
begin
  A:=Screen(X,Y);
  B:=Screen(X2,Y2);
  Surface.Line(A.X,A.Y,B.X,B.Y,Color,Max(1.0,Width*Scale));
end;

procedure TCartPainter.Dot(X,Y,Radius:Double;Color:TColor);
var A:TPointF;
begin
  A:=Screen(X,Y);
  Surface.Circle(A.X,A.Y,Radius*Scale,Color,True);
end;

procedure TCartPainter.Quad(const A,B,C,D:TPointF;Color:TColor);
begin
  Surface.FillQuad(Screen(A.X,A.Y),Screen(B.X,B.Y),Screen(C.X,C.Y),Screen(D.X,D.Y),Color);
end;

procedure TCartPainter.CartBody(X,Y,Angle,Size:Double;Color:TColor;Armored:Boolean;Facing:Integer;
  Crouch:Double;Boss,Rider:Boolean);
const Axles:array[0..1] of Double=(-0.29,0.29);
var C,S,DX,Rim:Double; A:TPointF; Shadow,Edge:TColor;
  function Part(DX,DY:Double):TPointF;
  begin
    DX:=DX*Facing;
    Result:=PointF(X+Size*(DX*C-DY*S),Y+Size*(DX*S+DY*C));
  end;
  procedure Disc(DX,DY,R:Double;Fill:TColor);
  var P:TPointF;
  begin
    P:=Part(DX,DY);
    Dot(P.X,P.Y,R*Size,Fill);
  end;
  procedure Bar(X1,Y1,X2,Y2,Width:Double;Fill:TColor);
  var P,Q:TPointF;
  begin
    P:=Part(X1,Y1);
    Q:=Part(X2,Y2);
    Line(P.X,P.Y,Q.X,Q.Y,Width*Size,Fill);
  end;
begin
  SinCos(Angle,S,C);
  Shadow:=Tint(Color,Ink,0.52);
  Edge:=Tint(Color,White,0.39);
  for DX in Axles do begin
    Disc(DX,0.135,0.137,Ink);
    Disc(DX,0.135,0.096,$008DA5A9);
    Rim:=X*8+DX*2;
    A:=Part(DX,0.135);
    Line(A.X-Size*0.07*Cos(Rim),A.Y-Size*0.07*Sin(Rim),
      A.X+Size*0.07*Cos(Rim),A.Y+Size*0.07*Sin(Rim),0.033*Size,Shadow);
    Disc(DX,0.135,0.033,White);
  end;
  // トロッコの開いた荷台に、鉱石とヘルメットが見える。
  if Rider then begin
    Disc(-0.24,0.56,0.117,Shadow);
    Disc(0.28,0.58,0.10,Copper);
    Disc(0.05,0.72-Crouch,0.16,Ink);
    Disc(0.074,0.735-Crouch,0.125,$0097C8E9);
    Bar(-0.095,0.787-Crouch,0.217,0.787-Crouch,0.079,Edge);
    if Boss then begin
      Disc(0.006,0.744-Crouch,0.028,Ink);
      Bar(-0.09,0.82-Crouch,0.20,0.82-Crouch,0.085,Gold);
      Bar(0.05,0.82-Crouch,0.05,0.94-Crouch,0.073,Gold);
    end else Disc(0.113,0.744-Crouch,0.023,Ink);
  end;
  Quad(Part(-0.50,0.59),Part(0.50,0.59),Part(0.37,0.19),Part(-0.36,0.19),Ink);
  Quad(Part(-0.43,0.53),Part(0.44,0.53),Part(0.32,0.24),Part(-0.31,0.24),Color);
  Quad(Part(-0.37,0.39),Part(0.38,0.39),Part(0.32,0.24),Part(-0.31,0.24),Shadow);
  Bar(-0.45,0.555,0.44,0.555,0.046,Edge);
  Bar(-0.27,0.47,-0.22,0.29,0.041,Shadow);
  Bar(0.26,0.47,0.22,0.29,0.041,Shadow);
  Disc(-0.27,0.465,0.022,White);
  Disc(0.26,0.465,0.022,White);
  if Armored then begin
    Bar(-0.28,0.34,0.28,0.34,0.11,Ink);
    Bar(-0.20,0.34,0.20,0.34,0.047,Gold);
    Quad(Part(0.37,0.44),Part(0.60,0.32),Part(0.62,0.21),Part(0.34,0.22),Ink);
    Bar(0.46,0.37,0.57,0.28,0.057,Edge);
    if Boss then begin
      Bar(-0.44,0.50,0.43,0.50,0.057,Gold);
      Disc(-0.28,0.40,0.04,Edge);
      Disc(0.27,0.40,0.04,Edge);
    end;
  end else Disc(0.405,0.51,0.057,Gold);
end;

procedure TCartPainter.WingEnemy(X,TopY,Age:Double);
const Body=$00C486DA; Wing=$00B8D9FB; WingEdge=$007371B7;
var Y,Flap:Double;
begin
  if Age>=0.52 then Exit;
  if Age>=0 then begin
    X:=X-1.70*Age;
    TopY:=TopY+0.18*Age-4.6*Sqr(Age);
  end;
  Y:=TopY-0.32;
  Flap:=0.18*Sin(Age*27);
  Quad(PointF(X-0.22,Y+0.03),PointF(X-0.47,Y+0.24+Flap),
    PointF(X-0.70,Y+0.31+Flap),PointF(X-0.47,Y-0.18+Flap*0.6),WingEdge);
  Quad(PointF(X+0.22,Y+0.03),PointF(X+0.47,Y+0.24+Flap),
    PointF(X+0.70,Y+0.31+Flap),PointF(X+0.47,Y-0.18+Flap*0.6),WingEdge);
  Line(X-0.27,Y+0.00,X-0.57,Y+0.21+Flap,0.079,Wing);
  Line(X+0.27,Y+0.00,X+0.57,Y+0.21+Flap,0.079,Wing);
  Dot(X,Y,0.32,Ink);
  Dot(X,Y+0.01,0.274,Body);
  Dot(X-0.124,Y+0.05,0.060,White);
  Dot(X+0.032,Y+0.07,0.054,White);
  Dot(X-0.142,Y+0.049,0.028,Ink);
  Dot(X+0.015,Y+0.069,0.025,Ink);
  Line(X-0.122,Y-0.117,X+0.056,Y-0.101,0.039,Ink);
end;

procedure TCartPainter.Sparks(X,Y,Age,Size:Double;Color:TColor);
var I:Integer; U,A,R:Double;
begin
  U:=Age/(0.21+Size*0.10);
  if (U<0) or (U>=1) then Exit;
  for I:=0 to 5 do begin
    A:=I*2.399+X*0.42;
    R:=Size*(0.09+0.55*U);
    Dot(X+R*Cos(A),Y+R*Sin(A)+U*0.14,Size*0.062*(1-U),Color);
  end;
end;

procedure TCartPainter.Bomb(const P:TPointF;Age:Double);
var Glow:Double;
begin
  Glow:=0.5+0.5*Sin(43*Age);
  Dot(P.X,P.Y,0.175,Ink);
  Dot(P.X,P.Y,0.142,$005A3B54);
  Line(P.X-0.092,P.Y-0.038,P.X+0.083,P.Y-0.038,0.055,$00545DEA);
  Line(P.X+0.05,P.Y+0.10,P.X+0.12,P.Y+0.19,0.045,Copper);
  Dot(P.X+0.13,P.Y+0.19,0.033+0.017*Glow,$00496DFA);
end;

procedure TCartPainter.Blast(const P:TPointF;Age:Double);
var I:Integer; U,A,R,X,Y:Double; C:TPointF;
begin
  if (Age<0) or (Age>=0.36) then Exit;
  U:=Age/0.36;
  if U<0.54 then begin
    C:=Screen(P.X,P.Y);
    Surface.Circle(C.X,C.Y,Scale*(0.16+0.72*U),$00516BFF,False,Max(1.0,Scale*0.061*(1-U)),1-U);
    Dot(P.X,P.Y,0.25*(1-U/0.54),Gold);
  end;
  for I:=0 to 4 do begin
    A:=I*2.399;
    R:=0.10+0.49*U;
    X:=P.X+R*Cos(A);
    Y:=P.Y+R*Sin(A)+U*0.22;
    Dot(X,Y,0.18*(1-U),Tint($00576EED,Palette.Near,U));
  end;
end;

procedure TCartPainter.Background(const Hero:TCartPosition;Theme:Integer);
var I,Layer,Tile:Integer; U,Cell,Shift,X,Y,R,Horizon,CX,CY,Span:Double; Color:TColor;
  Rail:TCartPosition;
begin
  for I:=0 to 15 do
    Surface.FillRect(0,H*I/16,W,H*(I+1)/16+1,Tint(Palette.Sky,Palette.Horizon,I/15));
  for Layer:=0 to 2 do begin
    Cell:=Scale*(4.9-Layer*0.76);
    Shift:=Hero.X*Scale*(0.13+Layer*0.12);
    Tile:=Floor(Shift/Cell);
    Horizon:=H*(0.68+Layer*0.11)+Hero.Y*Scale*(0.05+Layer*0.065);
    Color:=Tint(Palette.Far,Palette.Near,Layer/2);
    for I:=-1 to Ceil(W/Cell) do begin
      X:=I*Cell-(Shift-Tile*Cell);
      R:=(0.14+0.115*Sin((I+Tile)*1.64+Layer*2))*H;
      Y:=Horizon-R;
      Surface.FillQuad(PointF(X,H+1),PointF(X+Cell*0.32,Y+R*0.15),
        PointF(X+Cell*0.57,Y),PointF(X+Cell*1.28,H+1),Color);
      if (Theme<>1) and (Layer<>0) then begin
        U:=H*(0.045+0.06*Abs(Sin((Tile+I)*2.45)));
        Surface.FillQuad(PointF(X-Cell*0.35,0),PointF(X+Cell*0.95,0),
          PointF(X+Cell*0.65,U),PointF(X+Cell*0.19,U*1.53),Color);
        if (Layer=2) and ((I+Tile) mod 2=0) then begin
          CX:=X+Cell*0.54;
          CY:=U+Scale*(0.72+0.17*Sin((I+Tile)*1.75));
          Surface.Line(CX,U*0.48,CX,CY,Palette.Beam,Max(1.0,Scale*0.027));
          Surface.Circle(CX,CY,Scale*0.17,Palette.Accent,True,1,0.18);
          Surface.FillRect(CX-Scale*0.08,CY-Scale*0.10,CX+Scale*0.08,CY+Scale*0.08,Palette.Beam);
          Surface.FillRect(CX-Scale*0.05,CY-Scale*0.066,CX+Scale*0.05,CY+Scale*0.057,Palette.Accent);
        end;
      end;
    end;
  end;
  if Theme=3 then
    for I:=0 to 13 do begin
      U:=Frac(I*0.618+0.70)-Frac(Hero.X*0.014);
      X:=W*(U-Floor(U));
      Span:=Scale*(0.5+0.15*(I mod 4));
      Rail:=Plan.RailAtX(Left+(X+Span*0.5)/Scale,Time);
      Y:=Max(H*(0.90+0.011*(I mod 7)),Screen(Rail.X,Rail.Y).Y+Scale*0.80);
      if Y<H then Surface.Line(X,Y,X+Span,Y,Tint(Palette.Accent,Palette.Horizon,0.60),Scale*0.027);
    end;
end;

procedure TCartPainter.SpeedLines(const Hero:TCartPosition);
var I:Integer; U,Shift,X,Y,Span:Double; Rail:TCartPosition;
begin
  U:=EnsureRange((Hero.Speed-7.3)/6.0,0.0,1.0)*(1-CartEase((Time-Plan.Goal)/0.35));
  if U<=0.12 then Exit;
  Span:=Scale*(0.15+0.41*U);
  for I:=0 to 8 do begin
    Shift:=I*0.27-Hero.X*0.22;
    X:=W*(Shift-Floor(Shift));
    Rail:=Plan.RailAtX(Left+(X+Span*0.5)/Scale,Time);
    Y:=Max(H*(0.83+0.044*(I mod 3)),Screen(Rail.X,Rail.Y).Y+Scale*0.62);
    if Y<H then Surface.Line(X,Y,X+Span,Y,Palette.Metal,Max(1.0,Scale*0.023),U*0.31);
  end;
end;

procedure TCartPainter.Rails;
const Step=0.052;
var I,J,K:Integer; T,T2,Drop,Age:Double; A,B,D:TCartPosition; M:TCartMove; Color:TColor;
begin
  for I:=Floor(FirstTime/Step) to Ceil(LastTime/Step) do begin
    T:=I*Step;
    if T>=Plan.Goal then Break;
    T2:=Min(Plan.Goal,T+Step);
    if Plan.GapAt((T+T2)*0.5) then Continue;
    A:=Plan.Rail(T,Time);
    B:=Plan.Rail(T2,Time);
    J:=Plan.MoveAt(T);
    Drop:=0;
    if J>=0 then begin
      M:=Plan.Moves[J];
      if M.Kind=cmCollapse then begin
        Age:=Time-T-0.17;
        if Age>0 then Drop:=3.2*Sqr(Age);
      end;
    end;
    if Drop>4.5 then Continue;
    A.Y:=A.Y-Drop;
    B.Y:=B.Y-Drop;
    Line(A.X,A.Y-0.18,B.X,B.Y-0.18,0.16,Palette.Beam);
    Line(A.X,A.Y-0.058,B.X,B.Y-0.058,0.099,Ink);
    Line(A.X,A.Y,B.X,B.Y,0.046,Palette.Metal);
    if I mod 2=0 then begin
      Color:=Tint(Palette.Beam,Palette.Metal,0.30);
      Line(A.X-0.09,A.Y-0.16,A.X+0.09,A.Y-0.055,0.055,Color);
    end;
    if (I mod 7=0) and (Drop=0) then begin
      Line(A.X,A.Y-0.23,A.X-0.18,A.Y-2.65,0.09,Palette.Beam);
      Line(A.X,A.Y-0.31,A.X+0.82,A.Y-1.37,0.051,Palette.Beam);
    end;
    if (J>=0) and (Plan.Moves[J].Kind=cmFork) then begin
      A:=Plan.Track(T);
      B:=Plan.Track(T2);
      Line(A.X,A.Y-0.12,B.X,B.Y-0.12,0.085,Palette.Beam);
      Line(A.X,A.Y,B.X,B.Y,0.033,Tint(Palette.Metal,Palette.Beam,0.50));
    end;
  end;
  K:=Plan.MoveFrom(FirstTime-1.0);
  while (K<Length(Plan.Moves)) and (Plan.Moves[K].Start<LastTime) do begin
    M:=Plan.Moves[K];
    if M.Kind=cmLift then begin
      D:=Plan.Rail(M.Finish,Time);
      Line(D.X-0.28,D.Y-0.19,D.X+0.43,D.Y-0.19,0.15,Gold);
      Line(D.X-0.28,D.Y-0.24,D.X-0.28,D.Y-0.91,0.08,Palette.Metal);
      Line(D.X+0.43,D.Y-0.24,D.X+0.43,D.Y-0.91,0.08,Palette.Metal);
    end;
    Inc(K);
  end;
end;

procedure TCartPainter.Hazard(const Move:TCartMove;const Base:TCartPosition);
var X,Y,HazardHeight,Width,Age,Bend:Double;
begin
  X:=Base.X;
  Y:=Base.Y;
  Age:=Time-Move.Hit;
  HazardHeight:=Plan.ObstacleHeight(Move,Time);
  Width:=CartObstacleHalfWidth(Move.Kind);
  case Move.Kind of
    cmFlame,cmFireJet:begin
      if Move.Kind=cmFlame then begin
        HazardHeight:=0.46*(1-CartEase(Abs(Age)/0.34));
        Width:=0.21;
      end;
      Line(X-Width,Y-0.10,X+Width,Y-0.10,0.18,Ink);
      Line(X-Width,Y-0.04,X+Width,Y-0.04,0.055,Palette.Metal);
      if HazardHeight<0.07 then Exit;
      Bend:=Width*0.32*Sin(19*Age);
      Quad(PointF(X-Width,Y),PointF(X-Width*0.47,Y+HazardHeight*0.65),
        PointF(X+Bend,Y+HazardHeight),PointF(X+Width*0.34,Y+HazardHeight*0.43),$00415EEF);
      Quad(PointF(X-Width*0.42,Y),PointF(X+Bend,Y+HazardHeight*0.84),
        PointF(X+Width*0.72,Y+HazardHeight*0.54),PointF(X+Width,Y),$00487DFF);
      Quad(PointF(X-Width*0.36,Y),PointF(X+Bend*0.75,Y+HazardHeight*0.57),
        PointF(X+Width*0.34,Y+HazardHeight*0.26),PointF(X+Width*0.46,Y),Gold);
    end;
    cmBlocker:begin
      Quad(PointF(X-Width,Y),PointF(X-Width*0.48,Y+CartBlockHeight),
        PointF(X+Width*0.48,Y+CartBlockHeight),PointF(X+Width,Y),Ink);
      Quad(PointF(X-Width+0.06,Y+0.06),PointF(X-Width*0.40,Y+CartBlockHeight-0.05),
        PointF(X+Width*0.40,Y+CartBlockHeight-0.05),PointF(X+Width-0.06,Y+0.06),$004650AC);
      Line(X-0.27,Y+0.30,X+0.21,Y+0.43,0.12,White);
      Line(X-0.21,Y+0.59,X+0.18,Y+0.70,0.12,White);
      Line(X-Width,Y-0.075,X+Width,Y-0.075,0.12,Ink);
    end;
    cmRockfall:begin
      if Age< -CartRockLandLead-CartRockFallTime then Exit;
      Y:=Y+HazardHeight-CartRockRadius;
      Quad(PointF(X-0.59,Y+0.02),PointF(X-0.27,Y+0.49),PointF(X+0.31,Y+0.59),PointF(X+0.59,Y+0.04),Ink);
      Quad(PointF(X-0.59,Y+0.02),PointF(X+0.59,Y+0.04),PointF(X+0.37,Y-0.47),PointF(X-0.36,Y-0.59),Ink);
      Quad(PointF(X-0.52,Y+0.02),PointF(X-0.23,Y+0.43),PointF(X+0.27,Y+0.51),PointF(X+0.52,Y+0.04),$008A8590);
      Quad(PointF(X-0.52,Y+0.02),PointF(X+0.52,Y+0.04),PointF(X+0.32,Y-0.40),PointF(X-0.31,Y-0.52),$00564D5A);
      Line(X+0.26,Y+0.44,X-0.14,Y+0.23,0.06,$00AAA2A9);
      Line(X-0.14,Y+0.23,X-0.01,Y+0.02,0.06,$00AAA2A9);
      Sparks(X,Base.Y-0.09,Age+CartRockLandLead,1.12,Palette.Beam);
    end;
  end;
end;

procedure TCartPainter.Moves;
var I,J:Integer; M:TCartMove; P,A,B:TCartPosition; Foe:TPointF; X,Y,Age,U,D:Double;
begin
  I:=Plan.MoveFrom(FirstTime-2.0);
  while (I<Length(Plan.Moves)) and (Plan.Moves[I].Start<LastTime+0.85) do begin
    M:=Plan.Moves[I];
    P:=Plan.Track(M.Hit);
    X:=P.X;
    Y:=P.Y;
    Age:=Time-M.Hit;
    case M.Kind of
      cmGap,cmLift:begin
        A:=Plan.Rail(M.Start+0.11,Time);
        B:=Plan.Rail(M.Finish-0.11,Time);
        Line(A.X-0.13,A.Y-0.10,A.X+0.10,A.Y-0.10,0.075,Palette.Metal);
        Line(B.X-0.10,B.Y-0.10,B.X+0.13,B.Y-0.10,0.075,Palette.Metal);
      end;
      cmStomp:begin
        Foe:=Plan.WingTop(M,Time);
        WingEnemy(Foe.X,Foe.Y,Age);
        Sparks(Foe.X,Foe.Y,Age,1.0,Gold);
      end;
      cmFork:begin
        A:=Plan.Track(M.Start);
        Line(A.X,A.Y,A.X,A.Y+0.62,0.066,Palette.Beam);
        U:=CartEase((Time-M.Start+0.14)/0.20);
        Line(A.X-0.16+0.31*U,A.Y+0.61,A.X,A.Y+0.35,0.06,Gold);
        Dot(A.X-0.16+0.31*U,A.Y+0.61,0.074,Palette.Accent);
      end;
      cmCollapse:begin
        for J:=0 to 4 do begin
          D:=0.28*J;
          U:=EnsureRange((Age-0.16-D*0.20)*1.25,0.0,1.35);
          Dot(X-0.80+D*1.22,Y+2.70+D-3.1*U*U,0.14+J*0.024,Palette.Beam);
        end;
        Sparks(X-0.45,Y-0.14,Age-0.29,0.85,Copper);
      end;
      cmFlame,cmFireJet,cmBlocker:Hazard(M,P);
      cmRockfall:if Age>=-CartRockLandLead then Hazard(M,P);
      cmRival,cmRam:Rival(M);
    end;
    Inc(I);
  end;
end;

procedure TCartPainter.FallingRocks;
var I:Integer; M:TCartMove;
begin
  I:=Plan.MoveFrom(Time+CartRockLandLead);
  while (I<Length(Plan.Moves)) and (Plan.Moves[I].Hit<=Time+CartRockLandLead+CartRockFallTime) do begin
    M:=Plan.Moves[I];
    // 落下中は手前を横切り、奥のコインを自然に隠す。
    if (M.Kind=cmRockfall) and (Time-M.Hit< -CartRockLandLead) then Hazard(M,Plan.Track(M.Hit));
    Inc(I);
  end;
end;

procedure TCartPainter.Rival(const Move:TCartMove);
var P:TCartPosition; Age,X,Lead:Double;
begin
  Age:=Time-Move.Hit;
  if Move.Kind=cmRam then begin
    Lead:=(W/Scale*0.71+1.7)/6.9;
    if (Age< -Lead) or (Age>(W/Scale*0.29+1.7)/6.9) then Exit;
    P:=Plan.RamPosition(Move,Time);
    CartBody(P.X,P.Y,EnsureRange(ArcTan(P.Slope),-0.26,0.26),1.26,$005C7EEB,True,-1);
    if Abs(Age)<0.24 then Sparks(P.X,P.Y+0.09,Age,0.80,Gold);
    Exit;
  end;
  if (Age< -1.48) or (Age>1.16) then Exit;
  X:=Plan.Track(Time).X-CartThrowDistance-5.4*Max(0.0,-Age-CartThrowLead)-3.5*Max(0.0,Age+0.10);
  P:=Plan.RailAtX(X,Time);
  CartBody(P.X,P.Y,EnsureRange(ArcTan(P.Slope),-0.26,0.26),1.18,$006EA88E,False);
  if Age< -CartThrowLead then begin
    Line(P.X+0.05,P.Y+0.71,P.X,P.Y+0.83,0.065,Gold);
    Bomb(PointF(P.X,P.Y+0.83),Age);
  end
  else if Age<0.36 then Bomb(Plan.ThrowBomb(Move,Time),Age)
  else if Age<0.72 then Blast(Plan.ThrowBomb(Move,Move.Hit+0.36),Age-0.36);
end;

procedure TCartPainter.LegacyConvoy(Index:Integer);
var B:TCartBoss; M:TCartMove; Hero,P,Q:TCartPosition; I:Integer;
  Age,LastAge,Progress,X,Lead:Double;
begin
  B:=Plan.Bosses[Index];
  LastAge:=Time-Plan.Moves[B.LastMove].Hit;
  Lead:=(W/Scale*0.71+1.7)/(CartBossApproach*CartBossSpacing);
  if (Time<Plan.Moves[B.FirstMove].Hit-Lead) or (LastAge>0.96) then Exit;
  Progress:=Plan.BossProgress(Index,Time);
  Hero:=Plan.Cart(Time);
  for I:=B.FirstMove to B.LastMove do begin
    M:=Plan.Moves[I];
    Age:=Time-M.Hit;
    X:=Hero.X+(I-B.FirstMove-Progress)*CartBossSpacing;
    if Age<0 then begin
      P:=Plan.RailAtX(X,Time);
      if I<B.LastMove then begin
        Q:=Plan.RailAtX(X+CartBossSpacing,Time);
        Line(P.X+0.51,P.Y+0.34,Q.X-0.50,Q.Y+0.34,0.11,Palette.Metal);
      end;
      CartBody(P.X,P.Y,EnsureRange(ArcTan(P.Slope),-0.26,0.26),
        1.28+Ord(I=B.LastMove)*0.11,$007F86D4,True,-1,0.14);
    end else if Age<0.57 then begin
      P:=Plan.Track(M.Hit);
      CartBody(P.X-3.40*Age,P.Y+0.45*Age-4.2*Sqr(Age),Age*2.5,
        1.28+Ord(I=B.LastMove)*0.11,$007F86D4,True,-1,0.14);
      Sparks(P.X,P.Y+0.93,Age,1.40,Gold);
    end;
  end;
  if LastAge>=0 then begin
    P:=Plan.Track(Plan.Moves[B.LastMove].Hit);
    for I:=0 to 5 do
      Sparks(P.X-LastAge*3.1+I*0.21,P.Y+0.73+0.25*Sin(I*2.4),
        LastAge-I*0.072,2.1,Palette.Accent);
  end;
end;

procedure TCartPainter.BossVolley(Index,Car:Integer;const P:TCartPosition);
const BurstDelay=0.10;
var Shot:TCartBossShot; Puck:TPointF; Ground:TCartPosition; J:Integer; D,Arm,Burst:Double;
begin
  for J:=0 to Plan.ChaseShotCount(Index,Car)-1 do begin
    Shot:=Plan.ChaseShot(Index,Car,J);
    D:=Time-Shot.ReleaseTime;
    if (D>=-0.17) and (D<=0.13) then begin
      Arm:=1-CartEase(Abs(D)/0.17);
      Line(P.X+0.03,P.Y+1.01,P.X-0.17-0.27*Arm,P.Y+0.98+0.14*Arm,0.11,Gold);
      if D<0 then Bomb(PointF(P.X-0.17-0.27*Arm,P.Y+1.07+0.14*Arm),D);
    end;
    Burst:=Shot.CrossTime+BurstDelay;
    if (D<0) or (Time>=Burst+0.36) then Continue;
    Puck:=Shot.Position(Min(Time,Burst));
    Ground:=Plan.RailAtX(Puck.X,Min(Time,Burst));
    Puck.Y:=Max(Puck.Y,Ground.Y+0.10);
    if Time<Burst then Bomb(Puck,D)
    else Blast(Puck,Time-Burst);
  end;
end;

procedure TCartPainter.BossCrash(const P:TCartPosition;Age,Size:Double;Color:TColor;FinalCar:Boolean);
var X,Y,Angle,U,Travel:Double; C:TPointF; J:Integer;
begin
  Travel:=1.04+0.74*Ord(FinalCar);
  X:=P.X+Travel*(1-Exp(-5.0*Age));
  Y:=P.Y+Age*(5.4+0.8*Ord(FinalCar)-8.0*Age);
  Angle:=EnsureRange(ArcTan(P.Slope),-0.26,0.26)-Age*4.8;
  CartBody(X,Y,Angle,Size,Color,True,1,0.03,True);
  Sparks(P.X-0.62,P.Y+0.43,Age,1.54,Gold);
  if Age<0.19 then begin
    C:=Screen(P.X-0.65,P.Y+0.44);
    U:=Age/0.19;
    Surface.Circle(C.X,C.Y,Scale*(0.13+0.61*U),White,False,Max(1.0,Scale*0.049*(1-U)),1-U);
    Dot(P.X-0.65,P.Y+0.44,0.18*Sqr(1-U),White);
  end;
  if FinalCar then
    for J:=0 to 5 do
      Sparks(P.X+0.30*J,P.Y+0.49+0.34*Sin(J*2.4),Age-J*0.076,2.45,Palette.Accent);
end;

procedure TCartPainter.Convoy(Index:Integer);
const Armor:array[0..2] of TColor=($004A55CF,$006D48A4,$003076BB);
var B:TCartBoss; M:TCartMove; P,Q:TCartPosition; I:Integer; Age,LastAge,Size,Angle,MarkX:Double;
  Color:TColor;
begin
  B:=Plan.Bosses[Index];
  if Plan.Moves[B.FirstMove].Kind=cmBoss then begin
    LegacyConvoy(Index);
    Exit;
  end;
  LastAge:=Time-Plan.Moves[B.LastMove].Hit;
  if (Time<Plan.Moves[B.FirstMove].Hit-5.5) or (LastAge>1.08) then Exit;
  if Time<Plan.Moves[B.FirstMove].Hit then begin
    P:=Plan.ChaseCar(Index,B.FirstMove,Time);
    if P.X>Left+W/Scale+1.0 then Exit;
  end;
  Color:=Armor[Index mod Length(Armor)];
  for I:=B.LastMove downto B.FirstMove do begin
    M:=Plan.Moves[I];
    Age:=Time-M.Hit;
    Size:=1.41+0.21*Ord(I=B.LastMove);
    if Age<0 then begin
      P:=Plan.ChaseCar(Index,I,Time);
      if I<B.LastMove then begin
        Q:=Plan.ChaseCar(Index,I+1,Time);
        Line(P.X+0.54,P.Y+0.31,Q.X-0.60,Q.Y+0.31,0.14,Ink);
        Line(P.X+0.54,P.Y+0.34,Q.X-0.60,Q.Y+0.34,0.066,Palette.Metal);
      end;
      Angle:=EnsureRange(ArcTan(P.Slope),-0.26,0.26);
      CartBody(P.X,P.Y,Angle,Size,Color,True,1,0.03,True);
      if (Time>=M.Start-0.27) and (Time<=M.Start+1.09) then
        BossVolley(Index,I,P);
    end else if Age<0.99 then begin
      P:=Plan.ChaseCar(Index,I,M.Hit);
      BossCrash(P,Age,Size,Color,I=B.LastMove);
    end;
  end;
  // 残り車両を、右上の装甲色のゲージと車両マークで示す。
  if LastAge<0.52 then begin
    MarkX:=W*0.94;
    for I:=B.LastMove downto B.FirstMove do begin
      Surface.FillRect(MarkX-Scale*0.39,H*0.073,MarkX+Scale*0.07,H*0.106,Ink);
      if Time<Plan.Moves[I].Hit then begin
        Surface.FillRect(MarkX-Scale*0.33,H*0.080,MarkX,H*0.096,Color);
        Surface.FillRect(MarkX-Scale*0.31,H*0.079,MarkX-Scale*0.04,H*0.083,Gold);
      end;
      MarkX:=MarkX-Scale*0.55;
    end;
    Surface.Line(MarkX-Scale*0.30,H*0.091,MarkX,H*0.091,Gold,Scale*0.05);
    Surface.Line(MarkX-Scale*0.30,H*0.091,MarkX-Scale*0.34,H*0.073,Gold,Scale*0.042);
    Surface.Line(MarkX-Scale*0.15,H*0.091,MarkX-Scale*0.15,H*0.063,Gold,Scale*0.048);
    Surface.Line(MarkX,H*0.091,MarkX+Scale*0.04,H*0.073,Gold,Scale*0.042);
  end;
end;

procedure TCartPainter.Coins;
var I:Integer; C:TCartCoin; R,Age,Gap,Y:Double;
begin
  I:=Plan.CoinFrom(Min(Time-0.28,FirstTime-0.10));
  while (I<Length(Plan.Coins)) and (Plan.Coins[I].Time<LastTime+0.16) do begin
    C:=Plan.Coins[I];
    Age:=Time-C.Time;
    if Age>=0 then Sparks(C.X,C.Y,Age,0.52+C.Strength*0.23,Gold)
    else begin
      Gap:=1;
      if I>0 then Gap:=Min(Gap,C.X-Plan.Coins[I-1].X);
      if I<High(Plan.Coins) then Gap:=Min(Gap,Plan.Coins[I+1].X-C.X);
      R:=Min(0.184+C.Strength*0.045,Max(0.105,Gap*0.58));
      Y:=C.Y;
      if Gap<0.24 then Y:=Y+(2*Ord(Odd(I))-1)*0.094*CartEase(-Age/0.16);
      Dot(C.X,Y,R,Ink);
      Dot(C.X,Y,R*0.82,Gold);
      Dot(C.X+0.16*R,Y+0.14*R,R*0.49,$0081EEFF);
      Line(C.X,Y-R*0.37,C.X,Y+R*0.40,0.026,Copper);
    end;
    Inc(I);
  end;
end;

procedure TCartPainter.Gate;
var P:TCartPosition; X,Y,FloorY,A,B,Tip,Right:Double; I,J:Integer; Color:TColor;
begin
  if Plan.Goal>LastTime+0.20 then Exit;
  P:=Plan.Track(Plan.Goal);
  X:=P.X;
  Y:=P.Y;
  // レールは旗の位置で終わる。隙間の向こうに人が着地する地面を置く。
  FloorY:=Y-CartFinishDrop;
  Right:=Left+W/Scale+0.25;
  if Right>X+CartFinishLedge then begin
    Quad(PointF(X+CartFinishLedge,FloorY),PointF(Right,FloorY),
      PointF(Right,FloorY-4),PointF(X+CartFinishLedge+0.36,FloorY-4),Palette.Beam);
    Line(X+CartFinishLedge,FloorY,Right,FloorY,0.077,Tint(Palette.Beam,Gold,0.35));
    Line(X+CartFinishLedge+0.10,FloorY-0.23,Right,FloorY-0.23,0.11,Tint(Palette.Near,Palette.Beam,0.54));
    for I:=0 to Ceil(Right-X-CartFinishLedge) do begin
      A:=X+CartFinishLedge+0.20+I*0.92;
      B:=FloorY-0.50-0.17*Sin(1.7*I);
      Line(A,B,A+0.34,B-0.10,0.058,Tint(Palette.Beam,Palette.Metal,0.31));
    end;
  end;
  Line(X-0.03,Y-0.43,X-0.03,Y+0.04,0.14,Palette.Beam);
  Line(X-0.14,Y-0.31,X-0.14,Y+1.78,0.105,Ink);
  Line(X-0.14,Y-0.15,X-0.14,Y+1.78,0.056,Gold);
  for I:=0 to 4 do begin
    A:=X-0.11+I*0.204;
    B:=A+0.205;
    Tip:=Y+1.68-0.025*I+0.042*Sin(Time*8-I*0.84);
    for J:=0 to 2 do begin
      Color:=Tint(Ink,White,Ord(Odd(I+J)));
      Quad(PointF(A,Tip-J*0.15),PointF(B,Tip-J*0.15-0.023),
        PointF(B,Tip-(J+1)*0.15-0.023),PointF(A,Tip-(J+1)*0.15),Color);
    end;
  end;
  Dot(X-0.14,Y+1.82,0.083,Gold);
end;

procedure TCartPainter.Finish;
var RailEnd:TCartPosition; Feet:TPointF; Age,Land,Tuck,Head,Arm,X,Y:Double;
begin
  Age:=Time-Plan.Goal;
  RailEnd:=Plan.Track(Plan.Goal);
  if Age<0.91 then
    CartBody(RailEnd.X+1.39*(1-Exp(-4.7*Age)),RailEnd.Y-5.9*Sqr(Age),-Min(1.48,Age*2.7),
      1.08,HeroBlue,False,1,0,False,False);
  Feet:=Plan.FinishRider(Time);
  X:=Feet.X;
  Y:=Feet.Y;
  Land:=Age-CartFinishLanding;
  Tuck:=0.15*Sin(Pi*EnsureRange(Age/CartFinishLanding,0.0,1.0));
  Head:=0.25+0.52*CartEase(Age/0.16)-Tuck-0.11*(1-CartEase(Abs(Land-0.06)/0.14));
  Arm:=0.38*CartEase((Land-0.13)/0.23);
  Line(X-0.04,Y+Head-0.34,X-0.14-Tuck,Y+0.055+Tuck,0.12,Ink);
  Line(X+0.04,Y+Head-0.34,X+0.15,Y+0.055,0.12,Ink);
  Line(X-0.15-Tuck,Y+0.045+Tuck,X-0.04-Tuck,Y+0.045+Tuck,0.093,Ink);
  Line(X+0.12,Y+0.045,X+0.25,Y+0.045,0.093,Ink);
  Line(X-0.02,Y+Head-0.14,X,Y+Head-0.36,0.24,Ink);
  Line(X-0.02,Y+Head-0.14,X,Y+Head-0.34,0.178,HeroBlue);
  Line(X+0.02,Y+Head-0.19,X+0.21,Y+Head-0.22+Arm+Tuck,0.094,Ink);
  Dot(X+0.22,Y+Head-0.21+Arm+Tuck,0.056,$0097C8E9);
  Dot(X,Y+Head,0.165,Ink);
  Dot(X+0.025,Y+Head,0.126,$0097C8E9);
  Line(X-0.15,Y+Head+0.066,X+0.17,Y+Head+0.066,0.084,Tint(HeroBlue,White,0.40));
  Dot(X+0.069,Y+Head+0.004,0.024,Ink);
  Sparks(X,Y+0.045,Land,0.88,Tint(Palette.Beam,Gold,0.62));
end;

procedure TCartPainter.Draw(const Frame:TAnimationFrame);
var Hero,A,B:TCartPosition; I,Theme,Knot,NextTheme,Action:Integer; U,Angle,RouteTime,Crouch:Double;
begin
  W:=Frame.Width;
  H:=Frame.Height;
  Scale:=Min(W/13.4,H/7.55);
  Time:=EnsureRange(Frame.Time,0.0,Plan.Goal+2.5);
  RouteTime:=Min(Time,Plan.Goal);
  Hero:=Plan.Cart(Time);
  Left:=Hero.X-W/Scale*0.29;
  Top:=Hero.Y+H/Scale*0.62;
  if Time>=Plan.Goal then begin
    U:=CartEase((Time-Plan.Goal)/CartFinishLanding);
    Left:=Left+2.14*U;
    Top:=Top-0.71*U;
  end;
  FirstTime:=Max(-1.8,RouteTime-W/Scale*0.29/2.7-0.4);
  LastTime:=Min(Plan.Goal+2.2,RouteTime+W/Scale*0.71/2.7+0.5);
  Knot:=Plan.KnotAt(Time);
  Theme:=Plan.Knots[Knot].Theme;
  Palette:=Palettes[Theme];
  if Knot<High(Plan.Knots) then begin
    NextTheme:=Plan.Knots[Knot+1].Theme;
    U:=CartEase((Time-Plan.Knots[Knot+1].Time+0.74)/0.74);
    if (NextTheme<>Theme) and (U>0) then Palette:=FadePalette(Palette,Palettes[NextTheme],U);
  end;
  Background(Hero,Theme);
  if Frame.BackgroundOnly then Exit;
  SpeedLines(Hero);
  Rails;
  Moves;
  for I:=0 to High(Plan.Bosses) do Convoy(I);
  Gate;
  A:=Plan.Cart(Time-0.020);
  B:=Plan.Cart(Time+0.020);
  Angle:=ArcTan2(B.Y-A.Y,Max(0.01,B.X-A.X));
  Crouch:=0;
  Action:=Plan.MoveAt(Time);
  if (Action>=0) and (Plan.Moves[Action].Kind=cmRival) then
    Crouch:=0.15*(1-CartEase(Abs(Time-Plan.Moves[Action].Hit)/0.23));
  if Time<Plan.Goal then begin
    if (Action>=0) and (Plan.Moves[Action].Kind=cmBossBump) then
      Angle:=Angle+0.17*Sin(Pi*EnsureRange((Time-Plan.Moves[Action].Hit)/0.14,0.0,1.0));
    CartBody(Hero.X,Hero.Y,EnsureRange(Angle,-0.56,0.56),1.08,HeroBlue,False,1,Crouch);
  end else Finish;
  Coins;
  FallingRocks;
  Surface.FillRect(W*0.04,H*0.066,W*0.28,H*0.078,Ink);
  Surface.FillRect(W*0.04,H*0.068,W*(0.04+0.24*Min(1.0,Time/Plan.Goal)),H*0.076,Gold);
end;

destructor TCartAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TCartAnimation.SetReference(const Ref:TRhythmPlanRef);
begin
  FRef:=Ref;
end;

procedure TCartAnimation.Prepare(const Frame:TAnimationFrame);
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
    FPlan:=LoadCartPlan(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;end;
end;

procedure TCartAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Painter:TCartPainter;
begin
  if FPlan=nil then Exit;
  Painter.Surface:=Surface;
  Painter.Plan:=FPlan;
  Painter.Draw(Frame);
end;

function TCartAnimation.Notice:string;
begin
  Result:=FError;
end;

function TCartAnimation.GoalTime:Double;
begin
  Result:=inherited GoalTime;
  if FPlan<>nil then Result:=FPlan.Goal+CartFinishLanding;
end;
end.
