unit RhythmRunnerPixels;
// v6の低解像度描画。計画の姿勢・接触時計を読み、状態は進めない。
interface
uses RhythmRunnerAction,RhythmRenderSurface;
type
  TRunnerSwordArm=record
    Shoulder,Elbow,Grip,Tip:TRunPoint;
    Phase:Integer;
  end;
// Drawing-only joints keep the score's impact point and fixed limb lengths.
function RunnerSwordArmAt(Plan:TRunnerActionPlan;Time:Double;out Arm:TRunnerSwordArm):Boolean;
// 任意フレームを同じ型付き計画／描画面から復元する。
procedure RenderRunnerPixels(Plan:TRunnerActionPlan;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer);
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;

function RunnerSwordArmAt(Plan:TRunnerActionPlan;Time:Double;out Arm:TRunnerSwordArm):Boolean;
const Limb=0.032;
var
  Hero:TRunPose;
  OldGrip,Impact:TRunPoint;
  I:Integer;
  Age,DX,DY,Distance,Bend:Double;
begin
  Arm:=Default(TRunnerSwordArm);
  Result:=False;
  if not Plan.BladeAt(Time,OldGrip,Impact) then Exit;
  I:=Plan.ActionBefore(Time);
  if (I<0) or (Abs(Plan.Hits[I].Time-Time)>1E-8) then I:=Plan.ActionBefore(Time+0.055);
  if I<0 then Exit;
  if not (Plan.Hits[I].Kind in [rhSword,rhBossCut,rhFinish]) then Exit;
  Hero:=Plan.HeroAt(Time);
  Age:=Time-Plan.Hits[I].Time;
  Arm.Shoulder.X:=Hero.X+0.018;
  Arm.Shoulder.Y:=Hero.Y-0.054;
  // Four held poses match the sprite's short wind-up, cut and recovery.
  if Age<0 then begin
    Arm.Phase:=0;
    Arm.Grip.X:=Hero.X-0.014;Arm.Grip.Y:=Hero.Y-0.095;
    Arm.Tip.X:=Arm.Grip.X-0.052;Arm.Tip.Y:=Arm.Grip.Y-0.085;
  end else if Age<=0.025 then begin
    Arm.Phase:=1;
    Arm.Grip.X:=Hero.X+0.065;Arm.Grip.Y:=Hero.Y-0.055;
    Arm.Tip:=Impact;
  end else if Age<=0.095 then begin
    Arm.Phase:=2;
    Arm.Grip.X:=Hero.X+0.046;Arm.Grip.Y:=Hero.Y-0.028;
    Arm.Tip.X:=Arm.Grip.X+0.097;Arm.Tip.Y:=Arm.Grip.Y+0.023;
  end else begin
    Arm.Phase:=3;
    Arm.Grip.X:=Hero.X+0.047;Arm.Grip.Y:=Hero.Y-0.045;
    Arm.Tip.X:=Arm.Grip.X+0.042;Arm.Tip.Y:=Arm.Grip.Y-0.091;
  end;
  DX:=Arm.Grip.X-Arm.Shoulder.X;DY:=Arm.Grip.Y-Arm.Shoulder.Y;
  Distance:=Hypot(DX,DY);
  // Same two rigid segments in every pose; one bend side prevents elbow flips.
  Bend:=Sqrt(Max(0.0,Sqr(Limb)-Sqr(Distance/2)))/Distance;
  Arm.Elbow.X:=(Arm.Shoulder.X+Arm.Grip.X)/2-DY*Bend;
  Arm.Elbow.Y:=(Arm.Shoulder.Y+Arm.Grip.Y)/2+DX*Bend;
  Result:=True;
end;

procedure RenderRunnerPixels(Plan:TRunnerActionPlan;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer);
const
  CameraEase=0.24;
  Skin=$00B8DFFF;
  Hair=$003D426B;
  Ink=$00513A2B;
  Mint=$009BCC75;
  Boot=$00645340;
var
  P:TRunnerActionPlan;
  R:TAnimationRenderSurface;
  Scale,L,Top,Camera,T,X,Y,A,U,Turn,Size,DX,DY,HP,EntryOffset:Double;
  I,J,K,First,Last,Current,Drawn,BossLast:Integer;
  S,Arena:TRunSection;
  Pad:TRunPad;
  H,E:TRunHit;
  Hero:TRunPose;
  Boss:TRunBossPose;
  Feet:TRunFeet;
  G,Tip:TRunPoint;
  Blade:Boolean;
  procedure Box(X1,Y1,X2,Y2:Double;Color:TColor);
  begin R.FillRect(L+(X1-Camera)*Scale,Top+Y1*Scale,L+(X2-Camera)*Scale,Top+Y2*Scale,Color);
  end;
  procedure Line(X1,Y1,X2,Y2:Double;Color:TColor;W:Double);
  begin R.Line(L+(X1-Camera)*Scale,Top+Y1*Scale,L+(X2-Camera)*Scale,Top+Y2*Scale,Color,Max(1,W*Scale));
  end;
  procedure Burst(CX,CY,Age:Double;Color:TColor;Count:Integer=12);
  var
    N:Integer;
    Angle,Radius:Double;
  begin if (Age<0) or (Age>0.26) then Exit;
    for N:=0 to Count-1 do begin Angle:=N*2.39996;
      Radius:=0.012+Age*(0.32+0.03*(N mod 4));
      Line(CX+Cos(Angle)*Radius,CY+Sin(Angle)*Radius,CX+Cos(Angle)*(Radius+0.015),CY+Sin(Angle)*(Radius+0.015),Color,0.004);
    end;
  end;
  procedure GlyphText(const Text:string;PX,PY:Double;Color:TColor);
  var
    C:Char;
    Bits:string;
    Row,Col,N:Integer;
    CX:Double;
  begin CX:=PX;
    for C in Text do begin
      case C of
        'A':Bits:='01110100011000111111100011000110001';
        'B':Bits:='11110100011000111110100011000111110';
        'C':Bits:='01111100001000010000100001000001111';
        'J':Bits:='00111000100001000010000101001001100';
        'U':Bits:='10001100011000110001100011000101110';
        'M':Bits:='10001110111010110101100011000110001';
        'P':Bits:='11110100011000111110100001000010000';
        'S':Bits:='01111100001000001110000010000111110';
        'W':Bits:='10001100011000110101101011101110001';
        'O':Bits:='01110100011000110001100011000101110';
        'R':Bits:='11110100011000111110101001001010001';
        'D':Bits:='11110100011000110001100011000111110';
        'H':Bits:='10001100011000111111100011000110001';
        'I':Bits:='11111001000010000100001000010011111';
        'T':Bits:='11111001000010000100001000010000100';
        'F':Bits:='11111100001000011110100001000010000';
        'N':Bits:='10001110011010110011100011000110001';
        'L':Bits:='10000100001000010000100001000011111';
        'E':Bits:='11111100001000011110100001000011111';
        'Y':Bits:='10001100010101000100001000010000100';
        else Bits:=StringOfChar('0',35);
      end;
      N:=1;
      for Row:=0 to 6 do for Col:=0 to 4 do begin if Bits[N]='1' then Box(CX+Col*0.004,PY+Row*0.004,CX+(Col+1)*0.004,PY+(Row+1)*0.004,Color);
        Inc(N);
      end;
      CX:=CX+0.025;
    end;
  end;
  procedure PixelHero;
  const
    Head:array[0..11] of string=(
    '0001111111100000','0012222222210000','0122222222221000','1222266666222100',
    '1222222222222100','1222333333332100','1223333133133100','0123333133133100',
    '0123333333333100','0012333333331000','0001233333310000','0000111111100000');
  var
    Row,Col,Pose:Integer;
    C:TColor;
    PX,PY,VX,VY,Length:Double;
    Walk:TRunFeet;
    Arm:TRunnerSwordArm;
    Swing:Boolean;
    procedure Tile(X1,Y1,X2,Y2:Integer;Color:TColor);
    begin Box(Hero.X+X1*0.006,Hero.Y+Y1*0.006,Hero.X+X2*0.006,Hero.Y+Y2*0.006,Color);
    end;
  begin
    Pose:=Hero.Pose;
    Walk:=P.FeetAt(T);
    Swing:=RunnerSwordArmAt(P,T,Arm);
    // 12 px head + 10 px body: under two heads. No interpolated skeleton.
    for Row:=0 to 11 do for Col:=1 to 16 do if Head[Row][Col]<>'0' then begin
      case Head[Row][Col] of '1':C:=Ink;
        '2':C:=Hair;
        '3':C:=Skin;
        else C:=RGB(233,143,128);
      end;
      PX:=Hero.X+(Col-9)*0.006;
      PY:=Hero.Y-0.132+Row*0.006;
      Box(PX,PY,PX+0.006,PY+0.006,C);
    end;
    Tile(-8,-16,-6,-11,Hair);
    Tile(-9,-15,-7,-12,Hair);
    // short ponytail
    Tile(-4,-10,4,-3,Ink);
    Tile(-3,-10,3,-4,Mint);
    Tile(-4,-6,4,-3,Mint);
    Tile(-3,-4,3,-3,RGB(233,196,104));
    Tile(-1,-10,1,-8,RGB(229,240,210));
    if Pose=2 then begin Tile(-5,-4,-2,-2,Boot);
      Tile(2,-5,5,-3,Boot);
    end
    else begin
      Line(Hero.X-0.012,Hero.Y-0.024,Walk.LeftFoot.X,Walk.LeftFoot.Y-0.006,Ink,0.012);
      Line(Hero.X+0.012,Hero.Y-0.024,Walk.RightFoot.X,Walk.RightFoot.Y-0.006,Boot,0.012);
      Box(Walk.LeftFoot.X-0.009,Walk.LeftFoot.Y-0.006,Walk.LeftFoot.X+0.014,Walk.LeftFoot.Y,Ink);
      Box(Walk.RightFoot.X-0.009,Walk.RightFoot.Y-0.006,Walk.RightFoot.X+0.014,Walk.RightFoot.Y,Boot);
    end;
    Tile(-5,-9,-3,-5,Ink);
    Tile(-5,-8,-3,-6,Skin);
    if Pose=7 then begin Tile(3,-9,6,-7,Skin);
      Tile(-6,-9,-4,-7,Skin);
    end
    else if not Swing then begin Tile(3,-9,6,-6,Ink);
      Tile(4,-9,6,-7,Skin);
    end;
    Blade:=P.BladeAt(T,G,Tip);
    if Swing then begin
      Line(Arm.Shoulder.X,Arm.Shoulder.Y,Arm.Elbow.X,Arm.Elbow.Y,Ink,0.016);
      Line(Arm.Shoulder.X,Arm.Shoulder.Y,Arm.Elbow.X,Arm.Elbow.Y,Mint,0.010);
      Line(Arm.Elbow.X,Arm.Elbow.Y,Arm.Grip.X,Arm.Grip.Y,Ink,0.014);
      Line(Arm.Elbow.X,Arm.Elbow.Y,Arm.Grip.X,Arm.Grip.Y,Skin,0.009);
      G:=Arm.Grip;Tip:=Arm.Tip;
      VX:=Tip.X-G.X;VY:=Tip.Y-G.Y;Length:=Hypot(VX,VY);
      VX:=VX/Length;VY:=VY/Length;
      // Handle and guard use the blade's axis so the hand never detaches.
      Line(G.X-VX*0.012,G.Y-VY*0.012,G.X,G.Y,RGB(116,77,53),0.009);
      Line(G.X,G.Y,Tip.X,Tip.Y,Ink,0.010);
      Line(G.X,G.Y,Tip.X,Tip.Y,RGB(244,250,221),0.005);
      Line(G.X-VY*0.012,G.Y+VX*0.012,G.X+VY*0.012,G.Y-VX*0.012,RGB(236,182,72),0.006);
      Box(G.X-0.004,G.Y-0.004,G.X+0.004,G.Y+0.004,Skin);
    end else if Blade or (Pose<>7) then begin
      Line(Hero.X+0.024,Hero.Y-0.048,G.X,G.Y,Skin,0.012);
      Line(G.X-0.007,G.Y+0.009,G.X,G.Y,RGB(116,77,53),0.009);
      Line(G.X,G.Y,Tip.X,Tip.Y,Ink,0.010);
      Line(G.X,G.Y,Tip.X,Tip.Y,RGB(244,250,221),0.005);
      Line(G.X-0.011,G.Y+0.006,G.X+0.011,G.Y-0.006,RGB(236,182,72),0.006);
    end;
    if Pose=7 then begin Burst(Hero.X+0.01,Hero.Y-0.08,0.04,RGB(225,79,72),8);
    end;
  end;
  procedure Enemy(CX,CY,Angle,Factor:Double;Kind:Integer;Damage:Boolean);
  var
    N:Integer;
    C:TColor;
    procedure Stroke(AX,AY,BX,BY,Width:Double;Color:TColor);
    var
      Co,Si:Double;
    begin Co:=Cos(Angle);
      Si:=Sin(Angle);
      Line(CX+(AX*Co-AY*Si)*Factor,CY+(AX*Si+AY*Co)*Factor,CX+(BX*Co-BY*Si)*Factor,CY+(BX*Si+BY*Co)*Factor,Color,Width*Factor);
    end;
  begin C:=RGB(103,80,134);
    if Kind mod 3=1 then C:=RGB(166,88,91) else if Kind mod 3=2 then C:=RGB(58,119,129);
    if Damage then C:=RGB(249,202,105);
    Stroke(-0.021,0.021,0.021,0.021,0.014,Ink);
    Stroke(-0.027,0.006,0.027,0.006,0.046,Ink);
    Stroke(-0.022,0.003,0.022,0.003,0.037,C);
    Stroke(-0.025,-0.015,0.025,-0.015,0.012,RGB(225,174,101));
    Stroke(-0.012,-0.005,0.010,-0.005,0.006,RGB(244,242,209));
    Stroke(-0.008,-0.006,-0.008,-0.003,0.004,Ink);
    Stroke(0.007,-0.006,0.007,-0.003,0.004,Ink);
    for N:=0 to Kind mod 3 do Stroke(-0.018+N*0.015,-0.027,-0.023+N*0.015,-0.040,0.007,C);
  end;
begin
  P:=Plan;
  R:=Surface;
  T:=EnsureRange(Time,0.0,P.Goal+1.6);
  Current:=P.SectionAt(T);
  S:=P.Sections[Current];
  Scale:=Min(Width/1.8,Height/1.0);
  L:=(Width-1.8*Scale)/2;
  Top:=(Height-Scale)/2;
  Camera:=P.WorldAt(Min(T,P.Goal))-0.42;
  // Round off changes in scroll velocity without moving the saved world.
  if P.Version>=7 then
    for I:=Max(1,P.SectionAt(T-CameraEase)+1) to P.SectionAt(T+CameraEase) do begin
      A:=CameraEase-Abs(T-P.Sections[I].Start);
      U:=Ord(P.Sections[I].Mode<>rmBoss)-Ord(P.Sections[I-1].Mode<>rmBoss);
      Camera:=Camera+U*RA_SPEED*Sqr(Max(0.0,A))/(4*CameraEase);
    end;
  Hero:=P.HeroAt(T);
  R.FillRect(0,0,Width,Height,RGB(207,231,232));
  Box(Camera,0,Camera+1.8,1,RGB(185,225,235));
  // Bright, stepped landscape with slow world-anchored parallax.
  for I:=-1 to 10 do begin K:=Floor(Camera*0.20/0.34)+I;
    X:=K*0.34-Camera*0.20+Camera;
    Y:=0.48+0.05*Sin(K*2.1);
    Box(X,Y,X+0.26,0.90,RGB(136,190,157));
    Box(X+0.05,Y-0.05,X+0.20,Y,RGB(136,190,157));
  end;
  for I:=0 to 6 do begin X:=Camera+Frac(I*0.273-Camera*0.04)*2.0;
    Box(X,0.17+(I mod 3)*0.065,X+0.16,0.19+(I mod 3)*0.065,RGB(240,248,230));
  end;
  // Anchor the arena floor in world space so it scrolls through the section boundary.
  if P.Version>=7 then begin
    for I:=P.SectionAt(T-5) to P.SectionAt(T+5) do begin
      Arena:=P.Sections[I];
      if Arena.Mode<>rmBoss then Continue;
      X:=Max(Camera,Arena.X-0.50);
      Y:=Min(Camera+1.8,Arena.X+1.50);
      if X>=Y then Continue;
      Box(X,RA_GROUND,Y,RA_GROUND+0.048,RGB(89,104,114));
      Box(X,RA_GROUND,Y,RA_GROUND+0.010,RGB(70,134,90));
      Box(X,RA_GROUND+0.014,Y,RA_GROUND+0.021,RGB(211,218,151));
    end;
  end else if S.Mode=rmBoss then begin
    Box(Camera,RA_GROUND,Camera+1.8,RA_GROUND+0.048,RGB(89,104,114));
    Box(Camera,RA_GROUND,Camera+1.8,RA_GROUND+0.010,RGB(70,134,90));
    Box(Camera,RA_GROUND+0.014,Camera+1.8,RA_GROUND+0.021,RGB(211,218,151));
  end;
  First:=Max(0,P.PadBefore(T-7)-1);
  Last:=Min(High(P.Pads),P.PadBefore(T+7)+2);
  Drawn:=0;
  for I:=First to Last do begin if (P.Version<7) and (S.Mode=rmBoss) then Break;
    if Drawn>=64 then Break;
    Pad:=P.PadAt(I,T);
    if (Pad.Right<Camera-0.05) or (Pad.Left>Camera+1.85) or (Pad.Y>1.10) then Continue;
    Inc(Drawn);
    X:=Max(Camera,Pad.Left);
    Y:=Min(Camera+1.8,Pad.Right);
    Box(X,Pad.Y,Y,Pad.Y+0.048,RGB(89,104,114));
    Box(X,Pad.Y,Y,Pad.Y+0.010,RGB(70,134,90));
    Box(X,Pad.Y+0.014,Y,Pad.Y+0.021,RGB(211,218,151));
    if (Pad.AX<>0) or (Pad.AY<>0) then begin Line(Max(X,Pad.Left+0.01),Pad.Y+0.055,Min(Y,Pad.Right-0.01),Pad.Y+0.055,RGB(89,118,131),0.003);
      Box((X+Y)/2-0.012,Pad.Y+0.026,(X+Y)/2+0.012,Pad.Y+0.039,RGB(232,183,91));
    end;
    if (Pad.Fall>=0) and (T>Pad.Leave-0.12) then begin Line(X+0.025,Pad.Y+0.009,X+0.043,Pad.Y+0.027,Ink,0.004);
      Line(X+0.043,Pad.Y+0.027,X+0.032,Pad.Y+0.045,Ink,0.003);
    end;
    if (Pad.Fall>=0) and (T>Pad.Fall) then for J:=0 to 3 do begin A:=T-Pad.Fall;
      X:=Pad.Left+(Pad.Right-Pad.Left)*(J+0.5)/4;
      Y:=Pad.Y+0.07+A*0.12*(J+1);
      Line(X,Y,X+0.014,Y+0.01,RGB(103,105,112),0.012);
    end;
  end;
  First:=Max(0,P.EnemyBefore(T-0.72));
  Last:=Min(P.EnemyCount-1,P.EnemyBefore(T+2.0));
  // v7の敵は右端外から来る。旧2秒窓は可視入場より遅れて途中出現させていた。
  if P.Version>=7 then Last:=Min(P.EnemyCount-1,P.EnemyBefore(T+4.8));
  Drawn:=0;
  for I:=First to Min(Last,First+191) do begin H:=P.Hits[P.EnemyIndex(I)];
    if H.Kind=rhSword then begin
      if (T<H.Show) or (T>H.Kill+0.56) then Continue;
      X:=H.X+0.026;
      Y:=H.Y;
      Turn:=0;
      Size:=1;
      if T>=H.Kill then begin U:=T-H.Kill;
        X:=X+0.95*U;
        Y:=Y-0.62*U+0.95*U*U;
        Turn:=U*(9+H.Target mod 4);
        Size:=Max(0.0,1-U/0.56);
      end;
      if P.Version>=7 then begin
        if (X+0.06<Camera) or (X-0.06>Camera+1.8) then Continue;
        if Drawn>=64 then Break;Inc(Drawn);
      end;
      Enemy(X,Y,Turn,Size,H.Target,(T>=H.Time) and (T<H.Time+0.055));
    end;
  end;
  // Every visible impact is local. No full-screen constant glow.
  Last:=P.HitBefore(T);
  for I:=Last downto Max(0,Last-95) do begin H:=P.Hits[I];
    A:=T-H.Time;
    if A>0.26 then Break;
    if H.Kind in [rhSword,rhBossCut,rhParry,rhFinish] then Burst(H.X,H.Y,A,RGB(255,205,77),12)
    else if H.Kind=rhLand then begin for J:=0 to 5 do begin X:=H.X+(J-2.5)*A*0.19;
        Y:=H.Y-A*0.22+0.60*A*A;
        Box(X-0.003,Y-0.003,X+0.003,Y+0.003,RGB(236,226,169));
      end;
    end
    else if H.Kind=rhDodge then begin for J:=0 to 5 do begin X:=H.X+(J-2.5)*A*0.60;
        Y:=H.Y-0.015*Sin(A*20);
        Box(X-0.016,Y-0.006,X+0.016,Y,RGB(215,117,76));
      end;
    end;
  end;
  if S.Mode=rmBoss then begin
    BossLast:=P.HitBefore(T);
    BossLast:=EnsureRange(BossLast,S.First,S.Last);
    E:=P.Hits[BossLast];
    HP:=1;
    if E.Target>0 then HP:=E.BossHP/E.Target;
    Boss:=P.BossAt(T);
    EntryOffset:=0;
    if P.Version>=7 then begin
      A:=EnsureRange((T-S.Start)/0.60,0.0,1.0);
      EntryOffset:=0.50*Sqr(1-A);
    end;
    X:=Boss.X+EntryOffset;
    Y:=Boss.Y;
    Size:=Boss.Size;
    Turn:=Boss.Turn;
    Enemy(X,Y,Turn,Size,2+Trunc((1-HP)*3),(E.Kind in [rhBossCut,rhFinish]) and (T-E.Time<0.065));
    if not Boss.Airborne then begin Feet:=P.BossFeetAt(T);
      Box(Feet.LeftFoot.X+EntryOffset-0.018,Feet.LeftFoot.Y-0.014,Feet.LeftFoot.X+EntryOffset+0.012,Feet.LeftFoot.Y,RGB(116,104,86));
      Box(Feet.RightFoot.X+EntryOffset-0.018,Feet.RightFoot.Y-0.014,Feet.RightFoot.X+EntryOffset+0.012,Feet.RightFoot.Y,Ink);
    end;
    // The projectile meets the guard or floor on the saved contact beat.
    K:=P.ActionBefore(T+0.28);
    if (K>=S.First) and (K<=S.Last) then begin H:=P.Hits[K];
      U:=T-H.Time;
      if (H.Kind in [rhParry,rhDodge,rhHurt]) and (U>=-0.28) and (U<=0.18) then begin
        if P.EnemyBladeAt(T,G,Tip) then begin
          Line(Boss.X+EntryOffset,RA_GROUND-0.08,G.X+EntryOffset,G.Y,Ink,0.020);
          if U<=0 then begin
            // The contact point travels as a compact projectile. The arm stays at the grip.
            X:=Tip.X+EntryOffset*EnsureRange(-U/0.28,0.0,1.0);
            Y:=Tip.Y;
            Box(X-0.019,Y-0.010,X+0.019,Y+0.010,Ink);
            Box(X-0.014,Y-0.006,X+0.014,Y+0.006,RGB(240,143,91));
            Box(X-0.010,Y-0.003,X+0.004,Y+0.003,RGB(255,223,137));
          end;
        end;
        for J:=0 to 8 do begin A:=J*Pi/4;
          DX:=H.X+Cos(A)*(-U)*0.65;
          DY:=H.Y+Sin(A)*(-U)*0.65;
          Box(DX-0.004,DY-0.004,DX+0.004,DY+0.004,RGB(210,108,89));
        end;
        if U<0 then Line(H.X-0.03,H.Y+0.013,H.X+0.03,H.Y+0.013,RGB(209,99,85),0.004);
        if (H.Kind=rhHurt) and (U>=0) then Burst(H.X,H.Y,U,RGB(239,102,76),10);
      end;
    end;
    Box(Camera+1.12,0.125,Camera+1.70,0.15,Ink);
    Box(Camera+1.125,0.130,Camera+1.125+0.57*HP,0.145,RGB(221,108,92));
    GlyphText('HP',Camera+1.12,0.08,Ink);
    for J:=0 to 3 do begin X:=Camera+0.04+J*0.036;
      Box(X,0.13,X+0.026,0.146,Ink);
      if J<E.HeroHP then Box(X+0.004,0.134,X+0.022,0.142,RGB(218,122,118));
    end;
  end;
  if (P.Goal>0) and (Time<P.Goal+1.6) then PixelHero;
  if P.Goal>0 then begin X:=P.WorldAt(P.Goal);
    Line(X,RA_GROUND,X,RA_GROUND-0.23,Ink,0.006);
    Box(X,RA_GROUND-0.23,X+0.075,RA_GROUND-0.18,RGB(243,181,94));
  end;
  // Explicit A / B / C readout and whole-score strip, drawn in pixel glyphs.
  for I:=0 to 2 do begin X:=Camera+0.04+I*0.37;
    if I=Ord(S.Mode) then Box(X-0.008,0.032,X+0.33,0.078,RGB(249,236,181));
    case I of 0:GlyphText('A JUMP',X,0.041,Ink);
      1:GlyphText('B SWORD',X,0.041,Ink);
      2:GlyphText('C BOSS',X,0.041,Ink);
    end;
  end;
  for I:=0 to 127 do begin J:=P.SectionAt(P.Goal*I/128);
    X:=Camera+0.04+1.70*I/128;
    Y:=Camera+0.04+1.70*(I+1)/128;
    case P.Sections[J].Mode of rmJump:K:=RGB(70,137,111);
      rmSword:K:=RGB(213,153,68);
      else K:=RGB(184,100,119);
    end;
    Box(X,0.094,Y,0.103,K);
  end;
  X:=Camera+0.04+1.70*Min(T,P.Goal)/Max(0.001,P.Goal);
  Box(X-0.003,0.089,X+0.003,0.108,Ink);
  if L>0 then begin R.FillRect(0,0,L,Height,RGB(207,231,232));
    R.FillRect(Width-L,0,Width,Height,RGB(207,231,232));
  end;
  if Top>0 then begin R.FillRect(0,0,Width,Top,RGB(207,231,232));
    R.FillRect(0,Height-Top,Width,Height,RGB(207,231,232));
  end;
end;
end.
