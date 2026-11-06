unit RhythmCannonArt;
// 世界座標を共通描画面へ投影し、砲台・標的の装飾と戦場の背景を描く。
interface

uses System.Types,Vcl.Graphics,RhythmRenderSurface,RhythmCannonPlan,RhythmCannonTargets;

const
  CannonInk=$00312724;
  CannonIvory=$00CFF9FF;
  CannonGold=$0046C7FF;
  CannonOrange=$002958FB;
  CannonRed=$004940D8;
  CannonCyan=$00F0DE5A;

type
  TCannonArt=record
    Surface:TAnimationRenderSurface; // 借用
    W,H,Scale,Left,Top:Double;
    function Screen(X,Y:Double):TPointF;
    procedure Disk(X,Y,R:Double;Color:TColor;Opacity:Double=1);
    procedure Ring(X,Y,R,Stroke:Double;Color:TColor;Opacity:Double=1);
    procedure Line(X,Y,X2,Y2,Stroke:Double;Color:TColor;Opacity:Double=1);
    procedure Box(X,Y,W,H:Double;Color:TColor;Opacity:Double=1);
    procedure Quad(const A,B,C,D:TPointF;Color:TColor;Opacity:Double=1);
    procedure Background(Kind:TCannonTarget;StageIndex:Integer;Time:Double);
    procedure Part(Kind:TCannonTarget;Shape:TCannonShape;const Pose:TCannonPose;
      Width,Height,Time,Wear,Alpha:Double);
    procedure Cannon(const Base:TPointF;Angle,Recoil,Travel:Double;Support:Boolean);
    procedure Blast(X,Y,Age,Power:Double;Seed:Integer;Color:TColor;Ground:Boolean);
    procedure Smoke(X,Y,Age,Size:Double;Seed:Integer);
    procedure Wreckage(X,Y,Age,Size:Double;Seed:Integer);
  end;

function CannonTint(A,B:TColor;U:Double):TColor;

implementation

uses System.Math,Winapi.Windows;

function CannonTint(A,B:TColor;U:Double):TColor;
begin
  U:=EnsureRange(U,0.0,1.0);
  Result:=RGB(Round(CannonMix(GetRValue(A),GetRValue(B),U)),
    Round(CannonMix(GetGValue(A),GetGValue(B),U)),Round(CannonMix(GetBValue(A),GetBValue(B),U)));
end;

function TCannonArt.Screen(X,Y:Double):TPointF;
begin
  Result:=PointF(Left+X*Scale,Top-(Y+CannonGround)*Scale);
end;

procedure TCannonArt.Disk(X,Y,R:Double;Color:TColor;Opacity:Double);
var P:TPointF;
begin
  if (R<=0) or (Opacity<=0.01) then Exit;
  P:=Screen(X,Y);
  R:=R*Scale;
  if (P.X+R<0) or (P.Y+R<0) or (P.X-R>W) or (P.Y-R>H) then Exit;
  Surface.Circle(P.X,P.Y,R,Color,True,1,Min(1.0,Opacity));
end;

procedure TCannonArt.Ring(X,Y,R,Stroke:Double;Color:TColor;Opacity:Double);
var P:TPointF;
begin
  if (R<=0) or (Opacity<=0.01) then Exit;
  P:=Screen(X,Y);
  Surface.Circle(P.X,P.Y,R*Scale,Color,False,Max(1.0,Stroke*Scale),Min(1.0,Opacity));
end;

procedure TCannonArt.Line(X,Y,X2,Y2,Stroke:Double;Color:TColor;Opacity:Double);
var A,B:TPointF;
begin
  if Opacity<=0.01 then Exit;
  A:=Screen(X,Y);
  B:=Screen(X2,Y2);
  Surface.Line(A.X,A.Y,B.X,B.Y,Color,Max(1.0,Stroke*Scale),Min(1.0,Opacity));
end;

procedure TCannonArt.Box(X,Y,W,H:Double;Color:TColor;Opacity:Double);
var A,B:TPointF;
begin
  A:=Screen(X,Y+H);
  B:=Screen(X+W,Y);
  Surface.FillRect(A.X,A.Y,B.X,B.Y,Color,Opacity);
end;

procedure TCannonArt.Quad(const A,B,C,D:TPointF;Color:TColor;Opacity:Double);
begin
  Surface.FillQuad(Screen(A.X,A.Y),Screen(B.X,B.Y),Screen(C.X,C.Y),Screen(D.X,D.Y),Color,Opacity);
end;

procedure TCannonArt.Background(Kind:TCannonTarget;StageIndex:Integer;Time:Double);
const Sky:array[0..4] of TColor=($00D0B873,$00D9B77E,$00D3A488,$00C2A7AB,$00D1C690);
  Haze:array[0..4] of TColor=($00CFEDFF,$00BFEAFF,$00CFE3FF,$00C1D7FF,$00D6F6EE);
  Ground:array[0..4] of TColor=($00689CB2,$007CA58D,$007689AA,$008181AA,$007F9C99);
var I,J,Palette:Integer; X,Y,U,Rise,GroundY,SunX,Shift,Cloud:Double; A,B:TColor; P:TPointF;
begin
  Palette:=(StageIndex+Ord(Kind)) mod 5;
  A:=Sky[Palette];
  B:=Haze[Palette];
  for I:=0 to 63 do
    Surface.FillRect(0,I*H/64,W,(I+1)*H/64+1,CannonTint(A,B,I/63));
  SunX:=9.6+Palette*1.64;
  Disk(SunX,7.85,1.77,CannonIvory,0.18);
  Disk(SunX,7.85,1.37,CannonIvory,0.35);
  Disk(SunX,7.85,1.07,$00D5F5FF);
  for I:=-2 to 7 do begin
    X:=I*6.4+1.04*Sin(I*7.7)+Time*0.025;
    Y:=6.1+CannonNoise(I+81)*4.7;
    Cloud:=0.60+0.85*CannonNoise(I*3+52);
    A:=CannonTint(Sky[Palette],CannonIvory,0.34);
    Line(X-0.81*Cloud,Y-0.12*Cloud,X+1.40*Cloud,Y-0.10*Cloud,0.20*Cloud,A);
    Disk(X-0.42*Cloud,Y-0.04*Cloud,0.27*Cloud,A);
    Disk(X+0.03*Cloud,Y+0.11*Cloud,0.39*Cloud,A);
    Disk(X+0.58*Cloud,Y+0.07*Cloud,0.31*Cloud,A);
    Disk(X+0.91*Cloud,Y,0.22*Cloud,A);
    Line(X-0.48*Cloud,Y-0.33*Cloud,X+0.72*Cloud,Y-0.31*Cloud,
      0.066*Cloud,A,0.61);
  end;
  for I:=-8 to 16 do begin
    X:=I*3.1;
    Rise:=1.12+CannonNoise(I+54)*2.3;
    Quad(PointF(X-3,0.30),PointF(X,Rise),PointF(X+1.48,Rise*0.88),
      PointF(X+4.10,0.30),CannonTint(Sky[Palette],B,0.43));
  end;
  Shift:=0.50*(1-CannonEase(Time*2.0));
  for I:=-6 to 22 do begin
    X:=I*1.92+Shift;
    U:=CannonNoise(I+120+StageIndex mod 16);
    Y:=0.87+U*1.12;
    A:=CannonTint(Ground[Palette],B,0.35+U*0.10);
    Box(X-0.18,0,1.32,Y,A);
    Box(X-0.23,Y-0.06,1.44,0.12,CannonTint(A,B,0.43));
    if (Kind=ctFort) or (Kind=ctBridge) then begin
      for J:=0 to 2 do Box(X+0.08+J*0.37,Y,0.18,0.22,A);
    end else begin
      Box(X+0.75,Y,0.20,0.28+U*0.56,A);
      Line(X+0.85,Y+0.28,X+0.85,Y+0.73+U*0.56,0.045,A);
    end;
    for J:=0 to 2 do Box(X+J*0.36,Y*0.65,0.16,0.11,CannonTint(A,B,0.56));
  end;
  P:=Screen(0,0);
  GroundY:=P.Y;
  Surface.FillRect(0,GroundY,W,H,Ground[Palette]);
  Surface.FillRect(0,GroundY-3,W,GroundY+3,CannonTint(Ground[Palette],CannonIvory,0.56));
  Surface.FillRect(0,GroundY+5,W,GroundY+9,CannonTint(Ground[Palette],CannonInk,0.30));
  for I:=-16 to 33 do begin
    X:=I*1.18;
    Line(X,-0.32,X-0.85,-3.2,0.034,CannonTint(Ground[Palette],CannonInk,0.20));
    if Odd(I) then Box(X,-0.49,0.62,0.11,CannonTint(Ground[Palette],CannonIvory,0.35));
  end;
  if Kind=ctTrain then begin
    Line(11,0.09,26,0.09,0.13,CannonInk);
    Line(11,0.03,26,0.03,0.045,CannonIvory);
    for I:=0 to 16 do Box(11+I*0.82,-0.14,0.27,0.12,CannonInk);
  end;
end;

procedure TCannonArt.Part(Kind:TCannonTarget;Shape:TCannonShape;const Pose:TCannonPose;
  Width,Height,Time,Wear,Alpha:Double);
const Theme:array[TCannonTarget] of TColor=($006397C1,$009DAA50,$0076BBCE,$008EABBB,
  $007F9A52,$00A4B769,$008C65B4,$00B9876F,$008483D2);
var A,B,Dark,Light,Panel:TColor; C,S,R,X,Y:Double; I,J:Integer;

  function At(U,V:Double):TPointF;
  begin
    U:=U*Width;
    V:=V*Height;
    Result:=PointF(Pose.X+U*C-V*S,Pose.Y+U*S+V*C);
  end;

  procedure Face(U,V,W,H:Double;Color:TColor);
  begin
    Quad(At(U,V),At(U+W,V),At(U+W,V+H),At(U,V+H),Color,Alpha);
  end;

  procedure Edge(U,V,U2,V2,Stroke:Double;Color:TColor);
  var P,Q:TPointF;
  begin
    P:=At(U,V);
    Q:=At(U2,V2);
    Line(P.X,P.Y,Q.X,Q.Y,Stroke*Min(Width,Height),Color,Alpha);
  end;

  procedure Dot(U,V,R:Double;Color:TColor);
  var P:TPointF;
  begin
    P:=At(U,V);
    Disk(P.X,P.Y,R*Min(Width,Height),Color,Alpha);
  end;

  procedure Rivets;
  var Bolt:Integer; U:Double;
  begin
    for Bolt:=0 to 3 do begin
      U:=-0.39+Bolt*0.26;
      Dot(U,0.30,0.039,Dark);
      Dot(U,-0.32,0.039,Dark);
      Dot(U,0.32,0.022,Light);
    end;
  end;

  procedure Plating;
  begin
    Quad(At(-0.5,-0.26),At(-0.27,-0.5),At(0.37,-0.5),At(0.5,-0.31),CannonInk,Alpha);
    Quad(At(-0.5,-0.26),At(0.5,-0.31),At(0.5,0.34),At(-0.5,0.36),CannonInk,Alpha);
    Quad(At(-0.5,0.36),At(0.5,0.34),At(0.32,0.5),At(-0.30,0.5),Light,Alpha);
    Quad(At(-0.46,-0.25),At(0.45,-0.32),At(0.45,0.32),At(-0.46,0.34),A,Alpha);
    Face(-0.35,-0.16,0.70,0.33,Panel);
    Edge(-0.44,0.33,0.42,0.31,0.044,Light);
    Rivets;
  end;

begin
  if Alpha<=0.01 then Exit;
  SinCos(Pose.Angle,S,C);
  A:=CannonTint(Theme[Kind],CannonInk,Wear*0.61);
  B:=CannonTint(A,CannonGold,0.53);
  Dark:=CannonTint(A,CannonInk,0.65);
  Light:=CannonTint(A,CannonIvory,0.66);
  Panel:=CannonTint(A,CannonInk,0.38);
  case Shape of
    cpCrate:begin
      Face(-0.5,-0.5,1,1,CannonInk);
      Face(-0.45,-0.45,0.90,0.90,A);
      for I:=0 to 3 do begin
        Y:=-0.37+I*0.23;
        Edge(-0.44,Y,0.44,Y,0.025,Dark);
      end;
      Edge(-0.40,-0.36,0.40,0.36,0.14,Light);
      Edge(-0.42,0.41,0.42,0.41,0.066,B);
      Rivets;
    end;
    cpBarrel,cpTank:begin
      Face(-0.50,-0.36,1.0,0.72,CannonInk);
      Quad(At(-0.50,0.35),At(-0.35,0.49),At(0.35,0.49),At(0.50,0.35),Light,Alpha);
      Quad(At(-0.50,-0.35),At(-0.36,-0.49),At(0.36,-0.49),At(0.50,-0.35),Dark,Alpha);
      if Shape=cpBarrel then A:=CannonTint(CannonRed,CannonInk,Wear*0.55);
      Face(-0.44,-0.33,0.88,0.67,A);
      Face(-0.35,-0.32,0.13,0.64,CannonTint(A,CannonIvory,0.45));
      Face(0.25,-0.33,0.19,0.66,CannonTint(A,CannonInk,0.30));
      Edge(-0.46,-0.27,0.46,-0.27,0.07,Dark);
      Edge(-0.46,0.28,0.46,0.28,0.07,Dark);
      Quad(At(-0.17,0),At(0,-0.13),At(0.17,0),At(0,0.14),CannonGold,Alpha);
      Dot(0,0,0.047,CannonInk);
    end;
    cpGirder,cpDeck:begin
      Face(-0.5,-0.5,1,1,CannonInk);
      Face(-0.44,-0.38,0.88,0.76,Panel);
      Edge(-0.42,-0.38,-0.42,0.39,0.11,A);
      Edge(0.42,-0.38,0.42,0.39,0.11,Light);
      for I:=0 to 2 do begin
        Y:=-0.39+I*0.26;
        Edge(-0.43,Y,0.43,Y+0.26,0.078,A);
        Edge(0.43,Y,-0.43,Y+0.26,0.062,Dark);
      end;
      Edge(-0.49,0.46,0.49,0.46,0.12,Light);
      Edge(-0.49,-0.45,0.49,-0.45,0.10,A);
      if Shape=cpDeck then
        for I:=0 to 4 do Face(-0.43+I*0.18,0.26,0.088,0.11,B);
    end;
    cpPipe:begin
      Face(-0.49,-0.36,0.98,0.72,CannonInk);
      Face(-0.45,-0.23,0.90,0.46,A);
      Face(-0.45,0.06,0.90,0.13,Light);
      for I:=0 to 3 do begin
        Face(-0.45+I*0.27,-0.49,0.085,0.98,Dark);
        Face(-0.42+I*0.27,-0.42,0.043,0.85,B);
      end;
    end;
    cpGear,cpWheel:begin
      R:=Time*0.64;
      if Wear>0.25 then R:=0;
      Dot(0,0,0.46,CannonInk);
      Dot(0,0,0.39,A);
      Dot(0,0,0.32,Dark);
      if Shape=cpGear then
        for I:=0 to 11 do begin
          X:=Cos(I*Pi/6+R);
          Y:=Sin(I*Pi/6+R);
          Edge(X*0.36,Y*0.36,X*0.50,Y*0.50,0.10,A);
        end;
      for I:=0 to 5 do begin
        X:=Cos(I*Pi/3+R);
        Y:=Sin(I*Pi/3+R);
        Edge(X*0.14,Y*0.14,X*0.33,Y*0.33,0.073,Light);
      end;
      Dot(0,0,0.14,A);
      Dot(0,0,0.074,B);
    end;
    cpBrick:begin
      Face(-0.5,-0.5,1,1,Dark);
      for I:=0 to 4 do for J:=0 to 2 do begin
        X:=-0.485+J*0.32;
        Y:=-0.48+I*0.19;
        Face(X,Y,0.30,0.176,CannonTint(A,Light,0.11+0.36*CannonNoise(I*7+J+Ord(Kind)*23)));
        Face(X,Y+0.14,0.30,0.034,Light);
      end;
      if Height>3.7 then begin
        Face(-0.11,0.01,0.20,0.30,CannonInk);
        Edge(-0.13,0.33,0.11,0.33,0.038,Light);
      end;
    end;
    cpGate:begin
      Face(-0.48,-0.49,0.96,0.82,Dark);
      Quad(At(-0.47,0.25),At(-0.28,0.50),At(0.28,0.50),At(0.47,0.25),A,Alpha);
      for I:=0 to 4 do Face(-0.42+I*0.17,-0.46,0.15,0.75,A);
      Edge(-0.42,-0.20,0.42,0.25,0.095,B);
      Edge(-0.42,0.25,0.42,-0.20,0.095,B);
      Dot(0,0,0.090,CannonInk);
      Dot(0,0,0.057,CannonGold);
    end;
    cpFlag:begin
      Edge(-0.43,-0.49,-0.43,0.45,0.046,Dark);
      R:=0.045*Sin(Time*7);
      Quad(At(-0.41,0.40),At(0.41,0.34+R),At(0.23,0.15+R),At(-0.41,0.19),CannonRed,Alpha);
      Edge(-0.41,0.40,0.41,0.34+R,0.038,CannonGold);
      Dot(-0.43,0.44,0.066,CannonGold);
    end;
    cpHelmet:begin
      Quad(At(-0.46,-0.24),At(-0.29,-0.48),At(0.32,-0.46),At(0.49,-0.24),CannonInk,Alpha);
      Quad(At(-0.47,-0.26),At(0.49,-0.25),At(0.38,0.44),At(-0.37,0.46),CannonInk,Alpha);
      Quad(At(-0.41,-0.21),At(0.43,-0.22),At(0.34,0.39),At(-0.34,0.40),A,Alpha);
      Edge(-0.33,0.37,0.33,0.36,0.059,Light);
      Face(-0.32,0.05,0.64,0.20,Dark);
      Edge(-0.27,0.19,-0.07,0.13,0.070,CannonOrange);
      Edge(0.07,0.13,0.27,0.19,0.070,CannonOrange);
      for I:=0 to 3 do Edge(-0.20+I*0.13,-0.24,-0.20+I*0.13,-0.10,0.05,Dark);
    end;
    cpCore:begin
      Dot(0,0,0.50,CannonInk);
      Dot(0,0,0.44,B);
      Dot(0,0,0.38,Dark);
      for I:=0 to 7 do begin
        X:=Cos(I*Pi/4);
        Y:=Sin(I*Pi/4);
        Dot(X*0.40,Y*0.40,0.054,Light);
      end;
      R:=0.81+0.15*Sin(Time*13);
      Dot(0,0,0.30,CannonRed);
      Dot(0,0,0.26*R,CannonOrange);
      Dot(0,0,0.18*R,CannonGold);
      Dot(0,0,0.10*R,CannonIvory);
    end;
    else begin
      Plating;
      case Shape of
        cpCar,cpEngine:begin
          for I:=0 to 3 do begin
            X:=-0.37+I*0.19;
            Face(X,-0.15,0.10,0.29,Dark);
            Edge(X,0.14,X+0.085,0.14,0.045,Light);
          end;
          if Shape=cpEngine then begin
            Face(-0.32,0.36,0.18,0.15,CannonInk);
            Dot(-0.28,0.06,0.13,CannonGold);
            if Kind=ctTrain then begin
              Face(0.17,0.21,0.26,0.29,Dark);
              Face(0.21,0.27,0.14,0.14,CannonCyan);
              Edge(-0.57,-0.44,-0.22,-0.24,0.12,CannonGold);
              Face(-0.40,0.37,0.10,0.31,Dark);
            end;
          end;
        end;
        cpTurret:begin
          Edge(-0.62,0.01,0.15,0.01,0.20,CannonInk);
          Edge(-0.61,0.047,0.13,0.047,0.095,Light);
          Dot(0.12,0.02,0.15,B);
        end;
        cpArmor:begin
          for I:=0 to 2 do Face(-0.24+I*0.18,0.02,0.10,0.11,B);
          Edge(-0.22,-0.10,0.30,-0.10,0.056,Dark);
        end;
      end;
    end;
  end;
  if Wear>0.05 then begin
    Edge(-0.43,0.25,-0.22,0.02,0.027,CannonInk);
    Edge(-0.22,0.02,-0.05,0.08,0.027,CannonInk);
    Edge(-0.05,0.08,0.11,-0.22,0.027,CannonInk);
    Edge(-0.09,0.05,-0.13,-0.22,0.019,CannonOrange);
  end;
end;

procedure TCannonArt.Cannon(const Base:TPointF;Angle,Recoil,Travel:Double;Support:Boolean);
var X,Y,U,S,C,Size:Double; I,J:Integer; Metal,Light:TColor;
begin
  X:=Base.X;
  Y:=Base.Y;
  Size:=1;
  Metal:=$00A78D3E;
  Light:=$00DBC565;
  if Support then begin
    Size:=0.58;
    Metal:=$009A8357;
    Light:=$00C9B798;
    Line(X-0.52,Y-0.29,X-0.88,Y-1.35,0.09,CannonInk);
    Line(X+0.52,Y-0.29,X+0.88,Y-1.35,0.09,CannonInk);
  end;
  Line(X-0.98*Size,Y-0.57*Size,X+0.90*Size,Y-0.57*Size,0.70*Size,CannonInk);
  for I:=0 to 3 do begin
    U:=X+(-0.78+I*0.50)*Size;
    Disk(U,Y-0.59*Size,0.24*Size,Metal);
    Disk(U,Y-0.59*Size,0.15*Size,CannonInk);
    for J:=0 to 2 do begin
      S:=Travel+J*2*Pi/3;
      Line(U,Y-0.59*Size,U+Cos(S)*0.13*Size,Y+(-0.59+Sin(S)*0.13)*Size,0.037*Size,Light);
    end;
  end;
  Quad(PointF(X-1.02*Size,Y-0.43*Size),PointF(X+1.01*Size,Y-0.42*Size),
    PointF(X+0.76*Size,Y-0.05*Size),PointF(X-0.76*Size,Y+0.07*Size),Metal);
  Line(X-0.64*Size,Y-0.04*Size,X+0.71*Size,Y-0.12*Size,0.09*Size,Light);
  SinCos(Angle,S,C);
  U:=1.20*Size-Recoil;
  Line(X-(0.36+Recoil)*C,Y-(0.36+Recoil)*S,X+U*C,Y+U*S,0.46*Size,CannonInk);
  Line(X-Recoil*C,Y-Recoil*S,X+U*C,Y+U*S,0.32*Size,Metal);
  Line(X+0.18*C-Recoil*C,Y+0.18*S-Recoil*S+0.08*Size,X+U*C,Y+U*S+0.08*Size,0.08*Size,Light);
  Line(X+(U-0.20*Size)*C,Y+(U-0.20*Size)*S,X+U*C,Y+U*S,0.52*Size,CannonInk);
  Line(X+(U-0.10*Size)*C,Y+(U-0.10*Size)*S,X+U*C,Y+U*S,0.39*Size,Metal);
  Disk(X-0.21*Size,Y,0.37*Size,CannonInk);
  Disk(X-0.21*Size,Y,0.27*Size,Metal);
  Disk(X-0.22*Size,Y+0.06*Size,0.12*Size,CannonCyan);
  Line(X-0.74*Size,Y+0.03*Size,X-0.91*Size,Y+0.45*Size,0.044*Size,CannonInk);
  Disk(X-0.91*Size,Y+0.45*Size,0.056*Size,CannonGold);
end;

procedure TCannonArt.Smoke(X,Y,Age,Size:Double;Seed:Integer);
var I:Integer; R,U,DX,DY:Double;
begin
  if (Age<0) or (Age>1.30) then Exit;
  U:=Age/1.30;
  for I:=0 to 3 do begin
    DX:=(CannonNoise(Seed+I*41)-0.46)*(0.7+U*1.75);
    DY:=CannonNoise(Seed+I*53+8)*(0.4+U*1.8)+U*0.93;
    R:=Size*(0.20+CannonNoise(Seed+I*31)*0.31+U*0.23);
    Disk(X+DX*Size,Y+DY*Size,R,$007A7278,(1-U)*0.19*Min(1.0,Age*12));
    Disk(X+(DX-0.10)*Size,Y+(DY+0.16)*Size,R*0.66,$00C4BBC0,(1-U)*0.17*Min(1.0,Age*12));
  end;
end;

procedure TCannonArt.Wreckage(X,Y,Age,Size:Double;Seed:Integer);
var I,Count:Integer; U,Flight,Scatter,Spin,R,PX,PY,DX,DY,Glow:Double; Fill:TColor;
begin
  Count:=4+Round(EnsureRange(Size*1.5,0.0,5.0));
  Line(X-Size*0.61,0.02,X+Size*0.71,0.02,0.085,CannonInk,0.34);
  for I:=0 to Count-1 do begin
    Flight:=0.13+0.24*CannonNoise(Seed+I*19+6);
    U:=EnsureRange(Age/Flight,0.0,1.0);
    Scatter:=(CannonNoise(Seed+I*53+8)-0.46)*(1.6+Size*0.66);
    R:=0.075+Min(0.33,Size*0.11)*(0.28+0.72*CannonNoise(Seed+I*31));
    PX:=X+Scatter*(0.17+U*(2-U));
    PY:=CannonMix(Min(0.78,Y*0.53),R*0.50,U)+4*U*(1-U)*(0.18+R*2.4);
    Spin:=2*Pi*CannonNoise(Seed+I*11)+U*Scatter*2.4;
    DX:=R*Cos(Spin);
    DY:=R*Sin(Spin);
    Fill:=CannonTint(CannonInk,$009AA8B9,0.14+0.55*CannonNoise(Seed+I*71));
    Quad(PointF(PX-DX+DY*0.55,PY-DY-DX*0.55),PointF(PX-DX-DY*0.32,PY-DY+DX*0.32),
      PointF(PX+DX-DY*0.53,PY+DY+DX*0.53),PointF(PX+DX*0.51+DY*0.59,PY+DY*0.51-DX*0.59),Fill);
    Glow:=Max(0.0,1-Age/(0.75+CannonNoise(Seed+I*13)*1.8));
    Line(PX-DX,PY-DY,PX+DX*0.65,PY+DY*0.65,0.044,
      CannonTint(CannonOrange,CannonGold,Glow),Glow);
  end;
end;

procedure TCannonArt.Blast(X,Y,Age,Power:Double;Seed:Integer;Color:TColor;Ground:Boolean);
var I,Count:Integer; Angle,DX,DY,R,V,F,Size,U,ParticleAge,Flare,Side:Double; Tint:TColor;
begin
  if (Age<0) or (Age>=1.25) then Exit;
  Size:=0.40+Power*1.12;
  U:=Age/1.25;
  if Age<0.39 then begin
    F:=Age/0.39;
    Ring(X,Y,Size*(0.40+F*2.95),0.15*(1-F)+0.025,Color,(1-F)*0.88);
    Ring(X,Y,Size*(0.22+F*1.8),0.05,CannonIvory,(1-F)*0.74);
    if Age<0.23 then Disk(X,Y,Size*(0.35+F*1.4),CannonIvory,1-F*1.52);
    for I:=0 to 8 do begin
      Angle:=(I+CannonNoise(Seed+I*27)*0.48)*Pi*2/9;
      DX:=Cos(Angle);
      DY:=Sin(Angle);
      if Ground then DY:=Abs(DY);
      Flare:=Size*(0.46+F*1.35)*(0.65+CannonNoise(Seed+I*37)*0.65);
      Side:=Size*(1-F)*0.17;
      Quad(PointF(X+DX*0.18-DY*Side,Y+DY*0.18+DX*Side),
        PointF(X+DX*Flare,Y+DY*Flare),
        PointF(X+DX*0.31+DY*Side,Y+DY*0.31-DX*Side),PointF(X,Y),
        CannonTint(Color,CannonIvory,0.44),Sqr(1-F)*0.92);
    end;
  end;
  for I:=0 to 7 do begin
    ParticleAge:=Age-I*0.019;
    if (ParticleAge<0) or (ParticleAge>0.55) then Continue;
    F:=ParticleAge/0.55;
    Angle:=I*Pi/4+CannonNoise(Seed+I)*0.65;
    R:=Size*(0.29+F*0.72)*(0.72+0.48*CannonNoise(Seed+I*73));
    DX:=R*Cos(Angle);
    DY:=R*Sin(Angle)+F*Size*0.52;
    if Ground then DY:=Abs(DY)*0.68;
    V:=Size*(0.16+Sin(Pi*F*0.87)*0.51);
    Tint:=CannonTint(Color,CannonRed,0.35+F*0.60);
    Disk(X+DX,Y+DY,V,Tint,(1-F)*0.98);
    Disk(X+DX*0.89,Y+DY*0.89,V*0.84,CannonOrange,(1-F)*0.97);
    Disk(X+DX*0.81,Y+DY*0.82,V*0.66,CannonGold,(1-F)*0.96);
    Disk(X+DX*0.72,Y+DY*0.75,V*0.37,CannonIvory,(1-F)*0.95);
  end;
  Count:=9+Round(EnsureRange(Power,0.0,2.4)*12);
  for I:=0 to Count-1 do begin
    Angle:=Pi*(I*0.618+CannonNoise(Seed+I*16));
    DX:=Cos(Angle);
    DY:=Sin(Angle);
    if Ground then DY:=Abs(DY)*0.62+0.17;
    V:=(1.9+CannonNoise(Seed+I*37+2)*4.4)*Size;
    R:=Min(1.0,Age/0.85);
    F:=V*Age;
    Line(X+DX*F,Y+DY*F-3.1*Sqr(Age),X+DX*(F-V*0.073),Y+DY*(F-V*0.073)-3.1*Sqr(Age),
      0.039+0.083*(1-R),CannonTint(CannonGold,CannonIvory,CannonNoise(Seed+I*79)),1-R);
    if (I mod 3=0) and (U<0.67) then begin
      DX:=X+DX*F*0.58;
      DY:=Max(0.06,Y+DY*F*0.62-3.5*Sqr(Age));
      V:=Size*(0.06+CannonNoise(Seed+I)*0.12);
      Quad(PointF(DX-V,DY),PointF(DX,DY-V),PointF(DX+V,DY+V*0.24),
        PointF(DX+V*0.3,DY+V),CannonTint(CannonInk,Color,0.34),1-U);
    end;
  end;
end;
end.
