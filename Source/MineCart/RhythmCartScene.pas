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
    procedure CartBody(X,Y,Angle,Size:Double;Color:TColor;Armored:Boolean;Facing:Integer=1;Crouch:Double=0);
    procedure WingEnemy(X,TopY,Age:Double);
    procedure Sparks(X,Y,Age,Size:Double;Color:TColor);
    procedure Background(const Hero:TCartPosition;Theme:Integer);
    procedure Rails;
    procedure Moves;
    procedure Rival(const Move:TCartMove);
    procedure Convoy(Index:Integer);
    procedure Coins;
    procedure Gate;
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

procedure TCartPainter.CartBody(X,Y,Angle,Size:Double;Color:TColor;Armored:Boolean;Facing:Integer;Crouch:Double);
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
  Disc(-0.24,0.56,0.117,Shadow);
  Disc(0.28,0.58,0.10,Copper);
  Disc(0.05,0.72-Crouch,0.16,Ink);
  Disc(0.074,0.735-Crouch,0.125,$0097C8E9);
  Bar(-0.095,0.787-Crouch,0.217,0.787-Crouch,0.079,Edge);
  Disc(0.113,0.744-Crouch,0.023,Ink);
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

procedure TCartPainter.Background(const Hero:TCartPosition;Theme:Integer);
var I,Layer,Tile:Integer; U,Cell,Shift,X,Y,R,Horizon,CX,CY:Double; Color:TColor;
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
        if Layer=1 then
          Surface.Line(X+Cell*0.47,Y+R*0.35,X+Cell*0.55,Y+R*0.12,
            Tint(Color,Palette.Accent,0.65),Max(1.0,Scale*0.043));
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
      Surface.Line(X,H*(0.86+0.011*(I mod 7)),X+Scale*(0.5+0.15*(I mod 4)),
        H*(0.86+0.011*(I mod 7)),Tint(Palette.Accent,Palette.Horizon,0.30),Scale*0.035);
    end;
end;

procedure TCartPainter.Rails;
const Step=0.052;
var I,J,K:Integer; T,T2,Drop,Age:Double; A,B,D:TCartPosition; M:TCartMove; Color:TColor;
begin
  for I:=Floor(FirstTime/Step) to Ceil(LastTime/Step) do begin
    T:=I*Step;
    T2:=T+Step;
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
        Dot(A.X,A.Y-0.13,0.070,Gold);
        Dot(B.X,B.Y-0.13,0.070,Gold);
        if Age<0.55 then
          for J:=0 to 3 do begin
            D:=J*0.17;
            Dot(X-0.20+D,Y-1.26+0.13*Sin(Time*7+J),0.066,Tint(Palette.Accent,Gold,0.45));
          end;
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
      cmFlame:begin
        Dot(X,Y-0.19,0.22,Ink);
        U:=1-CartEase(Abs(Age)/0.34);
        for J:=-2 to 2 do
          Line(X+J*0.091,Y-0.04,X+J*0.050,Y+U*(0.48-0.065*Abs(J)),0.077,
            Tint($00406CF5,Gold,(2-Abs(J))/2));
        Sparks(X,Y+0.27,Age,0.65,Gold);
      end;
      cmRival,cmRam:Rival(M);
    end;
    Inc(I);
  end;
end;

procedure TCartPainter.Rival(const Move:TCartMove);
var P:TCartPosition; Rock:TPointF; Age,X,Lead:Double;
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
    Dot(P.X,P.Y+0.83,0.143,Copper);
  end
  else if Age<=0.30 then begin
    Rock:=Plan.ThrowRock(Move,Time);
    Dot(Rock.X,Rock.Y,0.175,Ink);
    Dot(Rock.X,Rock.Y,0.142,Copper);
    Dot(Rock.X+0.065*Cos(Age*22),Rock.Y+0.065*Sin(Age*22),0.052,Gold);
  end;
end;

procedure TCartPainter.Convoy(Index:Integer);
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
var P:TCartPosition; X,Y:Double; I:Integer;
begin
  if Plan.Goal>LastTime+0.20 then Exit;
  P:=Plan.Track(Plan.Goal);
  X:=P.X;
  Y:=P.Y;
  Line(X,Y-0.40,X,Y+1.80,0.105,Ink);
  Line(X,Y-0.20,X,Y+1.80,0.056,Gold);
  for I:=0 to 4 do
    Line(X,Y+1.67-I*0.13,X+0.89-I*0.04,Y+1.60-I*0.13,0.125,
      Tint(White,Gold,Ord(Odd(I))));
  Dot(X,Y+1.82,0.088,Gold);
  Sparks(X+0.40,Y+1.48,Time-Plan.Goal,1.25,Gold);
end;

procedure TCartPainter.Draw(const Frame:TAnimationFrame);
var Hero,A,B:TCartPosition; I,Theme,Tile,Knot,NextTheme,Action:Integer; U,Angle,Shift,Y,RouteTime,Crouch:Double;
begin
  W:=Frame.Width;
  H:=Frame.Height;
  Scale:=Min(W/13.4,H/7.55);
  Time:=EnsureRange(Frame.Time,0.0,Plan.Goal+1.6);
  RouteTime:=Min(Time,Plan.Goal);
  Hero:=Plan.Cart(Time);
  Left:=Hero.X-W/Scale*0.29;
  Top:=Hero.Y+H/Scale*0.62;
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
  CartBody(Hero.X,Hero.Y,EnsureRange(Angle,-0.56,0.56),1.08,HeroBlue,False,1,Crouch);
  Coins;
  // レール外の短い残像で下り坂の加速を見せる。
  U:=EnsureRange((Hero.Speed-7.3)/6.0,0.0,1.0)*(1-CartEase((Time-Plan.Goal)/0.35));
  if U>0.12 then
    for I:=0 to 8 do begin
      Shift:=I*0.27-Hero.X*0.22;
      Shift:=Shift-Floor(Shift);
      Tile:=I mod 3;
      Y:=H*(0.72+0.067*Tile);
      Surface.Line(W*Shift,Y,W*Shift+Scale*(0.15+0.41*U),Y,Palette.Accent,Max(1.0,Scale*0.023),U*0.44);
    end;
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
  if FPlan<>nil then Result:=FPlan.Goal;
end;
end.
