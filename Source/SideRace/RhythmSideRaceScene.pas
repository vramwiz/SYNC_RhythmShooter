unit RhythmSideRaceScene;
// 横スクロールの道路、車両、時間帯と衝撃を共通描画面に投影する。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmSideRacePlan;

type
  TSideRaceAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio; // 共通レンダラーから借用。
    FRef:TRhythmPlanRef;
    FPlan:TSideRacePlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;

implementation
uses System.SysUtils,System.Math,System.Types,Vcl.Graphics,Winapi.Windows,RhythmSideRaceCodec;

type
  TRoadPalette=record Sky,Horizon,Far,Near,Verge,Asphalt,Light:TColor; end;
  TVehicleShape=record
    Pose:TSidePose;
    SinA,CosA:Double;
    function Point(X,Y:Double):TPointF;
  end;
  TSidePainter=record
    Surface:TAnimationRenderSurface;
    Plan:TSideRacePlan;
    Time,W,H,Scale,Left,Top,Darkness,Velocity:Double;
    Palette:TRoadPalette;
    function Screen(X,Y:Double):TPointF;
    procedure Quad(const A,B,C,D:TPointF;Color:TColor);
    procedure Box(X,Y,Width,Height:Double;Color:TColor);
    procedure Disc(X,Y,Radius:Double;Color:TColor);
    procedure Line(X,Y,X2,Y2,Stroke:Double;Color:TColor);
    procedure Scenery(CameraX,CameraY,Phase,Theme:Double);
    procedure FarTraffic(CameraX:Double);
    procedure Road;
    procedure SpeedLines(CameraX:Double);
    procedure Panel(const Shape:TVehicleShape;L,T,R,B:Double;Color:TColor);
    procedure Headlight(const Shape:TVehicleShape;Nose,Height,Reach:Double);
    procedure Wheel(const Shape:TVehicleShape;X,Radius,Slip:Double;Detached:Boolean=False);
    procedure Car(const Pose:TSidePose;Half:Double;Kind:Integer;Hero:Boolean;Damage:Double);
    procedure Truck(Index:Integer;EntryGap:Double);
    procedure Props;
    procedure Impacts;
    procedure Sparks(const P:TPointF;Age,Power:Double;Color:TColor;Count:Integer);
    procedure FinishGate;
    procedure HUD(Level:Integer);
    procedure Draw(const Frame:TAnimationFrame);
  end;

const
  Ink=$002C2230;
  White=$00F3F9FF;
  Gold=$006CD6FF;
  Repair=$0088FCA4;
  HeroPaint=$00C5C630;
  CarPaint:array[0..5] of TColor=($00706AF0,$00B777E2,$007EBEFB,$0079B360,$00E29865,$00766DDA);
  TruckPaint:array[0..4] of TColor=($005B70DF,$00BD885A,$0093B647,$00AD65A3,$0062A9DD);
  Days:array[0..3] of TRoadPalette=(
    (Sky:$00E3A657;Horizon:$00F0EBC8;Far:$00C99964;Near:$00AC8052;Verge:$00AABA86;Asphalt:$00636263;Light:$00E1F5FA),
    (Sky:$00964C6B;Horizon:$008CC8FD;Far:$00896796;Near:$00725279;Verge:$0079847F;Asphalt:$005A4C61;Light:$00B7EDFF),
    (Sky:$0040241A;Horizon:$00765140;Far:$00614032;Near:$004F3A33;Verge:$00665B49;Asphalt:$00423D48;Light:$0090CEFF),
    (Sky:$00C78B88;Horizon:$00B9DEFC;Far:$00A98E91;Near:$00938183;Verge:$009EAA8E;Asphalt:$005B5660;Light:$00BEF6FF)
  );

function Tint(A,B:TColor;U:Double):TColor;
begin
  Result:=RGB(Round(SideMix(GetRValue(A),GetRValue(B),U)),
    Round(SideMix(GetGValue(A),GetGValue(B),U)),Round(SideMix(GetBValue(A),GetBValue(B),U)));
end;

function BlendDay(const A,B:TRoadPalette;U:Double):TRoadPalette;
begin
  Result.Sky:=Tint(A.Sky,B.Sky,U);
  Result.Horizon:=Tint(A.Horizon,B.Horizon,U);
  Result.Far:=Tint(A.Far,B.Far,U);
  Result.Near:=Tint(A.Near,B.Near,U);
  Result.Verge:=Tint(A.Verge,B.Verge,U);
  Result.Asphalt:=Tint(A.Asphalt,B.Asphalt,U);
  Result.Light:=Tint(A.Light,B.Light,U);
end;

function Wrap(X,Size:Double):Double;
begin
  Result:=X-Floor(X/Size)*Size;
end;

function TVehicleShape.Point(X,Y:Double):TPointF;
begin
  Result:=PointF(Pose.Root.X+X*CosA-Y*SinA,Pose.Root.Y+X*SinA+Y*CosA);
end;

function TSidePainter.Screen(X,Y:Double):TPointF;
begin
  Result:=PointF((X-Left)*Scale,(Top-Y)*Scale);
end;

procedure TSidePainter.Quad(const A,B,C,D:TPointF;Color:TColor);
begin
  Surface.FillQuad(Screen(A.X,A.Y),Screen(B.X,B.Y),Screen(C.X,C.Y),Screen(D.X,D.Y),Color);
end;

procedure TSidePainter.Box(X,Y,Width,Height:Double;Color:TColor);
var P:TPointF;
begin
  P:=Screen(X,Y);
  Surface.FillRect(P.X,P.Y,P.X+Scale*Width,P.Y+Scale*Height,Color);
end;

procedure TSidePainter.Disc(X,Y,Radius:Double;Color:TColor);
var P:TPointF;
begin
  P:=Screen(X,Y);
  Surface.Circle(P.X,P.Y,Radius*Scale,Color,True);
end;

procedure TSidePainter.Line(X,Y,X2,Y2,Stroke:Double;Color:TColor);
var P,Q:TPointF;
begin
  P:=Screen(X,Y);
  Q:=Screen(X2,Y2);
  Surface.Line(P.X,P.Y,Q.X,Q.Y,Color,Max(1.0,Stroke*Scale));
end;

procedure TSidePainter.Scenery(CameraX,CameraY,Phase,Theme:Double);
var I,K,Layer:Integer; U,X,Y,Radius,Tile,Shift,Base,Peak,Width,Clouds,Stars:Double; C,D:TColor;
  A,B,E,F:TPointF;
begin
  for I:=0 to 19 do
    Surface.FillRect(0,H*I/20,W,H*(I+1)/20+1,Tint(Palette.Sky,Palette.Horizon,I/21));
  X:=W*(0.79-0.14*Sin(Phase*1.13));
  Y:=H*(0.23+0.29*Sqr(Sin(Phase*1.57)))+CameraY*Scale*0.04;
  Radius:=Min(W,H)*(0.092-0.018*Darkness);
  Surface.Circle(X,Y,Radius*1.32,Tint(Palette.Horizon,Palette.Light,0.34),True);
  Surface.Circle(X,Y,Radius,Tint($00BAEFFF,White,Darkness*0.80),True);
  Clouds:=1-SideEase((Darkness-0.08)/0.73);
  Stars:=SideEase((Darkness-0.18)/0.72);
  for I:=0 to 15 do begin
    X:=Wrap(I*157.8-CameraX*Scale*0.027,W+80)-40;
    Y:=Wrap(I*61.34,H*0.49+8);
    if Stars>0 then Surface.Circle(X,Y,1+0.43*(I mod 3),
      Tint(Palette.Sky,White,0.72),True,1,Stars);
    if (Clouds>0) and (I mod 2=0) then begin
      U:=Min(W,H)*(0.074+0.012*(I mod 5));
      C:=Tint(Palette.Horizon,White,0.26);
      Surface.FillRect(X-U*0.59,Y-U*0.10,X+U*1.18,Y+U*0.12,C,Clouds);
      Surface.FillRect(X-U*0.21,Y-U*0.24,X+U*0.59,Y+U*0.12,C,Clouds);
    end;
  end;
  for Layer:=0 to 1 do begin
    Tile:=Scale*(5.1-Layer*1.82);
    Shift:=CameraX*Scale*(0.08+Layer*0.22);
    Base:=H*(0.75+Layer*0.10)+CameraY*Scale*(0.12+Layer*0.13);
    if Layer=0 then C:=Palette.Far else C:=Palette.Near;
    D:=Tint(C,Palette.Light,0.26+0.28*Darkness);
    for I:=-2 to Ceil(W/Tile)+1 do begin
      K:=Floor(Shift/Tile)+I;
      X:=Tile*I-Wrap(Shift,Tile);
      Peak:=Scale*(1.2+0.83*Sin(K*1.86+Theme*0.12)+0.80*Layer);
      Y:=Base-Peak;
      if Layer=0 then begin
        A:=PointF(X-Tile*0.24,H+1); B:=PointF(X+Tile*0.35,Y-Peak*0.28);
        E:=PointF(X+Tile*0.83,Y+Peak*0.41); F:=PointF(X+Tile*1.35,H+1);
        Surface.FillQuad(A,B,E,F,C);
      end else begin
        Width:=Tile*(0.68+0.12*Sin(K*2.8));
        Surface.FillRect(X,Y,X+Width,H,C);
        Surface.FillRect(X+Width*0.61,Y-Scale*0.21,X+Width,Y+2,C);
        if Darkness>0.12 then begin
          Surface.FillRect(X+Width*0.17,Y+Scale*0.30,X+Width*0.24,Y+Scale*0.47,D);
          Surface.FillRect(X+Width*0.39,Y+Scale*0.30,X+Width*0.50,Y+Scale*0.47,D);
          Surface.FillRect(X+Width*0.17,Y+Scale*0.60,X+Width*0.24,Y+Scale*0.77,D);
        end;
      end;
    end;
  end;
end;

procedure TSidePainter.FarTraffic(CameraX:Double);
var I:Integer; X,Y,Body,U,Offset:Double; C:TColor;
begin
  Y:=H*0.605;
  Surface.FillRect(0,Y-Scale*0.075,W,Y+Scale*0.19,Tint(Palette.Near,Palette.Asphalt,0.55));
  Surface.FillRect(0,Y-Scale*0.08,W,Y-Scale*0.055,Palette.Verge);
  for I:=0 to 7 do begin
    Offset:=CameraX*(0.52+0.037*(I mod 3))-Time*(3.1+I mod 3);
    X:=Wrap(I*197.6-Offset*Scale,W+150)-70;
    U:=Scale*(0.46+0.17*(I mod 3));
    Body:=U*(0.22+0.05*(I mod 4));
    C:=Tint(CarPaint[I mod 6],Palette.Far,0.61);
    Surface.FillRect(X,Y-Body,X+U,Y,C);
    Surface.FillRect(X+U*0.14,Y-Body-U*0.16,X+U*0.64,Y-Body,C);
    if Darkness>0.3 then Surface.FillRect(X+U*0.89,Y-Body*0.60,X+U,Y-Body*0.40,Palette.Light);
  end;
end;

procedure TSidePainter.Road;
const Step=0.24;
var I,J:Integer; X0,X1,Y0,Y1,Lo,Hi,M,Y:Double; A,B:TSideDeck; Has0,Has1: Boolean;
  C,Edge:TColor;
begin
  for I:=Floor(Left/4.2) to Ceil((Left+W/Scale)/4.2) do begin
    X0:=I*4.2;
    if Plan.Road(X0,Time,Y0,A) and (A=sdRoad) then begin
      Box(X0-0.32,Y0-1.48,0.64,3.05,Tint(Palette.Near,Palette.Asphalt,0.52));
      Box(X0-0.39,Y0-1.44,0.78,0.22,Tint(Palette.Verge,Palette.Asphalt,0.56));
    end;
  end;
  X0:=Floor((Left-0.5)/Step)*Step;
  Has0:=Plan.Road(X0,Time,Y0,A);
  for I:=1 to Ceil((W/Scale+1.1)/Step)+1 do begin
    X1:=X0+Step;
    Has1:=Plan.Road(X1,Time,Y1,B);
    if Has0 or Has1 then begin
      Lo:=X0;
      Hi:=X1;
      if Has0<>Has1 then begin
        for J:=0 to 6 do begin
          M:=(Lo+Hi)*0.5;
          if Plan.Road(M,Time,Y,B)=Has0 then Lo:=M else Hi:=M;
        end;
        M:=(Lo+Hi)*0.5;
        if Has0 then begin Hi:=M; Lo:=X0; end else begin Lo:=M; Hi:=X1; end;
      end;
      C:=Palette.Asphalt;
      Edge:=Palette.Light;
      case A of
        sdRamp:Edge:=Gold;
        sdBridge:begin C:=Tint(Palette.Asphalt,Ink,0.33); Edge:=Gold; end;
        sdMoving:begin C:=Tint(Palette.Asphalt,$00C1A65A,0.33); Edge:=$00FFD487; end;
      end;
      Quad(PointF(Lo,Y0),PointF(Hi,Y1),PointF(Hi,Y1-0.46),PointF(Lo,Y0-0.46),C);
      Quad(PointF(Lo,Y0-0.46),PointF(Hi,Y1-0.46),PointF(Hi,Y1-1.67),PointF(Lo,Y0-1.67),
        Tint(Palette.Verge,Palette.Asphalt,0.37));
      Quad(PointF(Lo,Y0),PointF(Hi,Y1),PointF(Hi,Y1-0.074),PointF(Lo,Y0-0.074),Edge);
      if (Floor(X0/0.96) mod 4)=0 then
        Quad(PointF(Lo,Y0-0.23),PointF(Hi,Y1-0.23),PointF(Hi,Y1-0.27),PointF(Lo,Y0-0.27),
          Tint(Palette.Asphalt,White,0.54));
      if (A=sdMoving) and (Floor(X0/0.27) mod 2=0) then
        Box(X0,Y0-0.38,Step*0.72,0.083,Edge);
    end;
    X0:=X1;
    Y0:=Y1;
    A:=B;
    Has0:=Has1;
  end;
end;

procedure TSidePainter.SpeedLines(CameraX:Double);
var I:Integer; X,Y,L,U:Double; C:TColor;
begin
  U:=EnsureRange((Velocity-14)/13,0.0,1.0);
  for I:=0 to 10 do begin
    X:=Wrap(I*219.8-CameraX*Scale*(0.22+0.037*(I mod 5)),W+150)-75;
    Y:=H*(0.13+0.045*(I mod 6));
    L:=Scale*(0.31+U*(0.69+0.19*(I mod 4)));
    C:=Tint(Palette.Sky,Palette.Light,0.24+U*0.27);
    Surface.Line(X-L,Y,X+L*0.22,Y,C,1+U*0.9);
  end;
end;

procedure TSidePainter.Panel(const Shape:TVehicleShape;L,T,R,B:Double;Color:TColor);
begin
  Quad(Shape.Point(L,T),Shape.Point(R,T),Shape.Point(R,B),Shape.Point(L,B),Color);
end;

procedure TSidePainter.Headlight(const Shape:TVehicleShape;Nose,Height,Reach:Double);
const LightColor=$00C9EEFF;
var I:Integer; U,X,Y,Spread,Opacity:Double; A,B,C,D,P:TPointF;
begin
  Opacity:=SideEase((Darkness-0.13)/0.55);
  if Opacity<=0 then Exit;
  A:=Shape.Point(Nose,Height+0.036);
  B:=Shape.Point(Nose,Height-0.043);
  A:=Screen(A.X,A.Y);
  B:=Screen(B.X,B.Y);
  // 広く薄い光から、光源に近い明るい部分を重ねる。
  for I:=0 to 5 do begin
    U:=I/5;
    X:=Nose+Reach*(1-0.76*U);
    Y:=Height-0.25*(1-0.76*U);
    Spread:=0.30-0.235*U;
    C:=Shape.Point(X,Y-Spread);
    D:=Shape.Point(X,Y+Spread);
    Surface.FillQuad(A,B,Screen(C.X,C.Y),Screen(D.X,D.Y),LightColor,Opacity*(0.065+0.033*U));
  end;
  P:=Shape.Point(Nose,Height);
  P:=Screen(P.X,P.Y);
  Surface.Circle(P.X,P.Y,Max(2.0,Scale*0.17),LightColor,True,1,Opacity*0.28);
  Surface.Circle(P.X,P.Y,Max(1.0,Scale*0.075),White,True,1,Opacity*0.74);
end;

procedure TSidePainter.Wheel(const Shape:TVehicleShape;X,Radius,Slip:Double;Detached:Boolean);
var P:TPointF; U,A,R,Lift:Double; I:Integer;
begin
  Lift:=0;
  if Detached then Lift:=0.32+0.32*Sin(Time*9+X);
  P:=Shape.Point(X,Radius+Lift);
  R:=Radius;
  Disc(P.X,P.Y,R,Ink);
  Disc(P.X,P.Y,R*0.76,$005D586B);
  Disc(P.X,P.Y,R*0.50,$009995AD);
  U:=Plan.Distance(Time)/Max(0.20,R)+Slip;
  for I:=0 to 3 do begin
    A:=U+I*Pi*0.5;
    Line(P.X+Cos(A)*R*0.17,P.Y+Sin(A)*R*0.17,
      P.X+Cos(A)*R*0.56,P.Y+Sin(A)*R*0.56,R*0.12,White);
  end;
  Disc(P.X,P.Y,R*0.13,Ink);
end;

procedure TSidePainter.Car(const Pose:TSidePose;Half:Double;Kind:Integer;Hero:Boolean;Damage:Double);
var Shape,Body:TVehicleShape; C,D,Glass:TColor; A,B,E,F:TPointF; Roof,WheelR,Wobble,Age:Double; I:Integer;
begin
  Shape.Pose:=Pose;
  Shape.SinA:=Sin(Pose.Angle);
  Shape.CosA:=Cos(Pose.Angle);
  Body:=Shape;
  WheelR:=0.30+0.041*(Kind mod 3);
  Roof:=0.94+0.085*(Kind mod 4);
  Wobble:=0.041*Sin(Time*(23+Velocity*0.41)+Kind);
  if Hero then begin
    I:=Plan.CueFrom(Time+1E-8)-1;
    if (I>=0) and (Plan.Cues[I].Action=saLand) then begin
      Age:=Time-Plan.Cues[I].Time;
      if (Age>=0) and (Age<0.16) then Wobble:=Wobble-0.125*Sin(Age*Pi/0.16);
    end;
  end;
  Body.Pose.Root.Y:=Body.Pose.Root.Y+Wobble;
  C:=CarPaint[Kind];
  if Hero then begin
    C:=HeroPaint;
    Roof:=0.94;
    WheelR:=0.31;
  end;
  D:=Tint(C,Ink,0.30+0.20*Damage);
  Glass:=Tint($00BE9873,White,0.28);
  if Darkness>0.45 then Glass:=Tint(Glass,Ink,0.31);
  if Hero or (Damage<1) then Headlight(Body,Half*0.98,0.53,2.42);
  Panel(Body,-Half,0.61,Half,0.29,Ink);
  Panel(Body,-Half,0.57,Half,0.36,C);
  Panel(Body,-Half*0.95,0.39,Half*0.95,0.29,D);
  A:=Body.Point(-Half*0.78,0.60);
  B:=Body.Point(-Half*(0.48+0.20*Ord(Kind=3)),Roof);
  E:=Body.Point(Half*(0.19+0.18*Ord(Kind=3)),Roof);
  F:=Body.Point(Half*0.60,0.60);
  Quad(A,B,E,F,D);
  A:=Body.Point(-Half*0.58,0.65);
  B:=Body.Point(-Half*(0.40+0.16*Ord(Kind=3)),Roof-0.08);
  E:=Body.Point(Half*(0.16+0.14*Ord(Kind=3)),Roof-0.08);
  F:=Body.Point(Half*0.45,0.65);
  Quad(A,B,E,F,Glass);
  Panel(Body,-Half*0.14,Roof-0.08,-Half*0.06,0.63,Ink);
  Panel(Body,Half*0.77,0.58,Half,0.48,White);
  Panel(Body,-Half,0.59,-Half*0.82,0.48,$005A53F8);
  Panel(Body,-Half*0.60,0.54,Half*0.59,0.47,Tint(C,White,0.43));
  if Hero then Panel(Body,-Half*0.60,0.467,Half*0.47,0.421,White);
  if Hero and (Damage>0.36) then begin
    A:=Body.Point(Half*0.42,0.63);
    B:=Body.Point(Half*0.65,0.45);
    Line(A.X,A.Y,B.X,B.Y,0.048,Ink);
  end;
  Wheel(Shape,-Half*0.61,WheelR,Kind*0.39);
  Wheel(Shape,Half*0.63,WheelR,Kind*0.73);
end;

procedure TSidePainter.Truck(Index:Integer;EntryGap:Double);
var B:TSideBoss; Rig:TSideRig; P,Q:TSidePose; Main,Cargo:TVehicleShape;
  I,K:Integer; Age,U,X,H,CabTop:Double; C,D,E:TColor; A,V:TPointF;

  function CargoY(Y:Double):Double;
  begin
    Result:=0.58+(Y-0.58)*(Rig.Roof-0.58)/(Rig.Roof/SideTruckHeightScale-0.58);
  end;
begin
  B:=Plan.Bosses[Index];
  Age:=Time-Plan.Cues[B.Last].Time;
  if (Time<Plan.Cues[B.First].Time-SideFrontEntryLead(EntryGap)) or (Age>0.99) then Exit;
  Rig:=Plan.BossRig(Index);
  P:=Plan.BossPose(Index,Time,EntryGap);
  if P.Root.X-Rig.Half>Left+W/Scale+1.0 then Exit;
  K:=EnsureRange(Plan.CueFrom(Time),B.First,B.Last);
  U:=(K-B.First)/Max(1,B.Last-B.First);
  C:=TruckPaint[B.Kind];
  D:=Tint(C,Ink,0.37);
  E:=Tint(C,White,0.44);
  H:=Rig.Half;
  Main.Pose:=P;
  Main.SinA:=Sin(P.Angle);
  Main.CosA:=Cos(P.Angle);
  Cargo:=Main;
  if (Age>0) and (Rig.Finish in [1,4]) then begin
    Q:=P;
    Q.Root.X:=Q.Root.X-1.4*Age;
    Q.Root.Y:=Q.Root.Y+Max(0.0,Age*3.4-1.9*Sqr(Age));
    Q.Angle:=Q.Angle+Age*0.59;
    Cargo.Pose:=Q;
    Cargo.SinA:=Sin(Q.Angle);
    Cargo.CosA:=Cos(Q.Angle);
  end;
  if Age<0 then Headlight(Main,H,0.65,2.85);
  Panel(Main,-H,0.60,H,0.32,Ink);
  Panel(Cargo,-H,Rig.Roof,H*0.37,0.58,Ink);
  Panel(Cargo,-H+0.10,Rig.Roof-0.09,H*0.37-0.075,0.67,C);
  Panel(Cargo,-H+0.14,Rig.Roof-0.24,H*0.34,CargoY(1.13),D);
  case B.Kind of
    0,2:for I:=0 to 4 do
      Panel(Cargo,-H+0.28+I*H*0.247,Rig.Roof-0.18,-H+0.36+I*H*0.247,CargoY(0.72),E);
    1:for I:=0 to 2 do
      Panel(Cargo,-H+0.14,Rig.Roof-0.34-I*0.19,H*0.35,Rig.Roof-0.40-I*0.19,E);
    else for I:=0 to 3 do
      Quad(Cargo.Point(-H+0.31+I*H*0.31,CargoY(1.18)),Cargo.Point(-H+0.57+I*H*0.31,Rig.Roof-0.14),
        Cargo.Point(-H+0.71+I*H*0.31,Rig.Roof-0.14),Cargo.Point(-H+0.45+I*H*0.31,1.18),E);
  end;
  CabTop:=(1.46+0.065*(B.Kind mod 3))*SideTruckHeightScale;
  Panel(Main,H*0.40,CabTop,H*0.91,0.57,C);
  Panel(Main,H*0.52,CabTop-0.15,H*0.90,1.11,$009C866D);
  Panel(Main,H*0.78,0.94,H,0.42,D);
  Panel(Main,H*0.88,0.73,H,0.57,White);
  Panel(Main,-H,0.69,-H+0.19,0.55,$00636CFD);
  if U>0.29 then begin
    A:=Cargo.Point(-H*0.44,Rig.Roof-0.11);
    V:=Cargo.Point(-H*0.61,Rig.Roof-0.55);
    Line(A.X,A.Y,V.X,V.Y,0.068,Ink);
  end;
  if U>0.62 then begin
    A:=Cargo.Point(-H*0.29,1.10);
    V:=Cargo.Point(-H*0.06,Rig.Roof-0.10);
    Line(A.X,A.Y,V.X,V.Y,0.082,Ink);
    Disc(A.X,A.Y+0.30+0.10*Sin(Time*15),0.115,Palette.Far);
  end;
  for I:=0 to Rig.Wheels-2 do begin
    X:=SideMix(-H*0.76,H*0.33,I/Max(1,Rig.Wheels-2));
    Wheel(Cargo,X,0.38,I*0.45,(Rig.Finish=3) and (Age>0.04+I*0.08));
  end;
  Wheel(Main,H*0.76,0.40,0);
  if Age>=0 then begin
    A:=Cargo.Point(-H*0.52,1.15);
    V:=Main.Point(H*0.43,0.75);
    Sparks(A,Age,1.3,Gold,15);
    Sparks(V,Age-0.10,1.0,CarPaint[B.Kind],12);
  end;
end;

procedure TSidePainter.Sparks(const P:TPointF;Age,Power:Double;Color:TColor;Count:Integer);
var I:Integer; U,V,DX,DY,A:Double; C:TColor;
begin
  U:=Age/(0.20+Power*0.15);
  if (U<0) or (U>=1) then Exit;
  C:=Tint(Color,White,0.28*(1-U));
  if U<0.27 then Disc(P.X,P.Y,(0.18+Power*0.12)*(1-U),C);
  for I:=0 to Count-1 do begin
    A:=I*2.399+0.43;
    V:=0.12+U*(0.72+Power*0.48)*(0.78+0.22*Sin(I*3.15));
    DX:=Cos(A)*V;
    DY:=Sin(A)*V-U*U*0.43;
    Line(P.X+DX*0.69,P.Y+DY*0.69,P.X+DX,P.Y+DY,0.067*(1-U),C);
  end;
end;

procedure TSidePainter.Props;
var I,J,Limit:Integer; A:TSideCue; P,Q,R,S:TPointF; Age,U,Y:Double;
begin
  I:=Plan.CueFrom(Time-0.04);
  Limit:=Plan.CueFrom(Time+1.05);
  while I<Limit do begin
    A:=Plan.Cues[I];
    Age:=Time-A.Time;
    P:=Plan.Contact(I);
    if Age<0 then case A.Action of
      saRock,saBossDrop:begin
        U:=0;
        if A.Action=saBossDrop then U:=Min(1.0,-Age/0.72);
        P.X:=P.X+0.29+U*2.75;
        P.Y:=P.Y-0.13+U*1.16;
        if A.Action=saRock then begin
          Q:=PointF(P.X-0.30,P.Y-0.26); R:=PointF(P.X-0.15,P.Y+0.22);
          S:=PointF(P.X+0.24,P.Y+0.18);
          Quad(Q,R,S,PointF(P.X+0.31,P.Y-0.27),$006E6583);
        end else begin
          Disc(P.X,P.Y,0.30,Ink);
          Disc(P.X,P.Y,0.16,Palette.Far);
        end;
      end;
      saBump:begin
        Y:=Plan.BaseRoad(P.X);
        Quad(PointF(P.X-0.48,Y),PointF(P.X-0.20,Y+0.13),PointF(P.X+0.20,Y+0.13),
          PointF(P.X+0.46,Y),Palette.Asphalt);
      end;
      saRepair:begin
        Disc(P.X,P.Y,0.27,Tint(Repair,Ink,0.28));
        Disc(P.X,P.Y,0.20,Repair);
        Box(P.X-0.12,P.Y+0.032,0.24,0.065,Ink);
        Box(P.X-0.032,P.Y+0.12,0.065,0.24,Ink);
      end;
    end;
    Inc(I);
  end;
  // デッキの昇降レールは道路とは別に見せ、接地面は Road と共用する。
  for J:=0 to High(Plan.Jumps) do
    if (Plan.Jumps[J].Lift>0) and (Plan.Jumps[J].X1>Left-0.5) and (Plan.Jumps[J].X1<Left+W/Scale+0.5) then begin
      Y:=Plan.BaseRoad(Plan.Jumps[J].X1);
      Line(Plan.Jumps[J].X1+1.55,Y-0.13,Plan.Jumps[J].X1+1.55,Y-1.10,0.07,$009DBFA9);
    end;
end;

procedure TSidePainter.Impacts;
var I,Limit:Integer; A:TSideCue; Age:Double; P:TPointF; C:TColor;
begin
  I:=Plan.CueFrom(Time-0.43);
  Limit:=Plan.CueFrom(Time+1E-8);
  while I<Limit do begin
    A:=Plan.Cues[I];
    Age:=Time-A.Time;
    P:=Plan.Contact(I);
    C:=Gold;
    if A.Action in [saLaunch,saLand,saBump] then C:=Palette.Light;
    if A.Action=saRepair then C:=Repair;
    Sparks(P,Age,0.48+A.Power*0.58,C,6+4*Ord(A.Action in [saBossClear,saBossRoof,saRock,saBossDrop]));
    Inc(I);
  end;
end;

procedure TSidePainter.FinishGate;
var X,Y:Double; I,J:Integer; C:TColor;
begin
  X:=Plan.Distance(Plan.Goal);
  if (X<Left-1) or (X>Left+W/Scale+1) then Exit;
  Y:=Plan.BaseRoad(X);
  Box(X-0.09,Y+2.35,0.18,2.35,Ink);
  Box(X-0.057,Y+2.35,0.11,2.35,White);
  Box(X-1.04,Y+2.74,2.08,0.55,Ink);
  for I:=0 to 10 do for J:=0 to 2 do begin
    C:=Ink;
    if (I+J) mod 2=0 then C:=White;
    Box(X-0.99+I*0.18,Y+2.69-J*0.15,0.18,0.15,C);
  end;
  if Time>=Plan.Goal then Sparks(PointF(X,Y+2.4),Time-Plan.Goal,1.2,Gold,14);
end;

procedure TSidePainter.HUD(Level:Integer);
var X,Y,U,HP:Double; I:Integer; C:TColor;
begin
  U:=Max(2.0,Scale*0.10);
  X:=W*0.065;
  Y:=H*0.07;
  HP:=Plan.Health(Time);
  C:=Repair;
  if HP<0.48 then C:=$006B8FFD;
  Surface.FillRect(X-U*2,Y-U*1.45,X+W*0.23,Y+U*1.45,Ink);
  Surface.FillRect(X-U*1.23,Y-U*0.24,X+U*0.18,Y+U*0.24,White);
  Surface.FillRect(X-U*0.76,Y-U*0.72,X-U*0.29,Y+U*0.72,White);
  Surface.FillRect(X+U,Y-U*0.52,X+W*0.217,Y+U*0.52,Palette.Far);
  Surface.FillRect(X+U,Y-U*0.52,X+U+(W*0.217-U)*HP,Y+U*0.52,C);
  X:=W*0.81;
  Surface.FillRect(X-U,Y-U*1.37,X+U*10,Y+U*1.37,Ink);
  for I:=0 to 4 do begin
    C:=Tint(Palette.Asphalt,Palette.Light,0.23);
    if I<Level then C:=Gold;
    Surface.FillRect(X+U*I*1.9,Y+U*(0.31-I*0.29),X+U*(I*1.9+1.31),Y+U*0.63,C);
  end;
end;

procedure TSidePainter.Draw(const Frame:TAnimationFrame);
var Root,Before,After:TPointF; Hero,Other:TSidePose; A:TSideCue; F:TSideCar;
  CamX,CamY,Phase,U,Shake,Zoom,Age,Theme,EntryGap,EntryLead:Double; Stage,I,J,K,Limit,Chain:Integer;
begin
  W:=Frame.Width;
  H:=Frame.Height;
  Time:=EnsureRange(Frame.Time,0.0,Plan.Duration);
  Stage:=Plan.StageAt(Time);
  Velocity:=Plan.Speed(Time);
  Phase:=Plan.Phase(Time);
  J:=Min(2,Floor(Phase));
  Palette:=BlendDay(Days[J],Days[J+1],Phase-J);
  Darkness:=EnsureRange(1-Abs(2-Phase),0.0,1.0);
  Root:=Plan.Hero(Time);
  Before:=Plan.Hero(Time-0.18);
  After:=Plan.Hero(Time+0.23);
  CamX:=Root.X;
  CamY:=Root.Y*0.50+Before.Y*0.21+After.Y*0.29;
  Shake:=0;
  Zoom:=1;
  I:=Plan.CueFrom(Time+1E-8)-1;
  if I>=0 then begin
    A:=Plan.Cues[I];
    Age:=Time-A.Time;
    if (Age>=0) and (Age<0.23) then begin
      U:=(1-SideEase(Age/0.23))*A.Power;
      if A.Action in [saBossClear,saBossRam,saBossRoof,saRear] then begin
        Shake:=U*Sin(Age*103)*0.14;
        Zoom:=1+0.043*U;
      end;
      if A.Action=saLand then CamY:=CamY+0.11*U*Sin(Age*53);
    end;
  end;
  Scale:=Min(W/20.4,H/8.8);
  // ズーム前の右端を基準にし、振動や画面比が変わっても出現境界を画面外に置く。
  EntryGap:=Max(SideFrontEntryGap,W/Scale*0.64+2);
  EntryLead:=SideFrontEntryLead(EntryGap);
  Scale:=Scale*Zoom;
  J:=Plan.JumpAt(Time);
  if (J>=0) and (Plan.Jumps[J].Roof>=0) then
    CamY:=Min(CamY,Plan.BaseRoad(CamX)+H/Scale*0.31-0.45);
  Left:=CamX-W/Scale*0.36+Shake;
  Top:=CamY+H/Scale*0.69;
  Theme:=Plan.Stages[Stage].Theme;
  if (Stage>0) and (Time<Plan.Stages[Stage].Time+0.9) then
    Theme:=SideMix(Plan.Stages[Stage-1].Theme,Theme,SideEase((Time-Plan.Stages[Stage].Time)/0.9));
  Scenery(CamX,CamY,Phase,Theme);
  FarTraffic(CamX);
  SpeedLines(CamX);
  Road;
  if Frame.BackgroundOnly then Exit;
  Props;
  FinishGate;
  for J:=0 to High(Plan.Bosses) do Truck(J,EntryGap);
  I:=Plan.CueFrom(Time-0.85);
  Limit:=Plan.CueFrom(Time+Max(1.36,EntryLead+0.25));
  while I<Limit do begin
    K:=Plan.Cues[I].Car;
    if (K>=0) and (Plan.CarCue(K,Time)=I) then begin
      F:=Plan.Cars[K];
      Other:=Plan.CarPose(K,Time,EntryGap);
      if (Other.Root.X>=Left-2.0) and (Other.Root.X<=Left+W/Scale+2.0) then
        Car(Other,Plan.CarHalf(K),F.Kind,False,Ord(Time>Plan.Cues[F.Last].Time));
      Chain:=Plan.ChainCue(K);
      if Chain>=0 then begin
        Age:=Time-Plan.Cues[Chain].Time;
        if (Age>=-EntryLead) and (Age<0.46) then begin
          Other:=Plan.ChainCar(K,Chain,Time,EntryGap);
          if (Other.Root.X>=Left-2.0) and (Other.Root.X<=Left+W/Scale+2.0) then
            Car(Other,0.92,(F.Kind+2) mod 6,False,Ord(Age>=0));
          if Age>=0 then begin
            Before:=Plan.ChainCar(K,Chain,Plan.Cues[Chain].Time).Root;
            Sparks(PointF(Before.X-0.92,Before.Y+0.43),Age,0.8,Gold,8);
          end;
        end;
      end;
    end;
    Inc(I);
  end;
  Hero.Root:=Root;
  Hero.Angle:=Plan.HeroAngle(Time);
  Car(Hero,SideHeroHalf,1,True,1-Plan.Health(Time));
  Impacts;
  HUD(Plan.Stages[Stage].Level);
end;

destructor TSideRaceAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TSideRaceAnimation.SetReference(const Ref:TRhythmPlanRef);
begin
  FRef:=Ref;
end;

procedure TSideRaceAnimation.Prepare(const Frame:TAnimationFrame);
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
    FPlan:=LoadSideRace(FRef,FAudio,Frame.Direction);
  except
    on E:Exception do FError:=E.Message;
  end;
end;

procedure TSideRaceAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Painter:TSidePainter;
begin
  if FPlan=nil then Exit;
  Painter.Surface:=Surface;
  Painter.Plan:=FPlan;
  Painter.Draw(Frame);
end;

function TSideRaceAnimation.Notice:string;
begin
  Result:=FError;
end;
end.
