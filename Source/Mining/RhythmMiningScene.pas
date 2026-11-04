unit RhythmMiningScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmMiningPlan;
type
  TMiningAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TMiningPlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function Mix(A,B:TColor;U:Double):TColor;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
end;

destructor TMiningAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TMiningAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TMiningAnimation.Notice:string;
begin Result:=FError;
end;

procedure TMiningAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity);
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TMiningPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TMiningAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var
  Scale,Left,Top,Clock,Camera,Zoom,CX,Age,U,X,Y,Angle,Health,Hurt,Depth,Width,Gap:Double;
  I,J,A,B,N,Theme,Drawn:Integer;
  Hero,Point,Past:TMiningPoint;
  Hit:TMiningHit;
  Enemy:TMiningEnemy;
  Shot:TMiningShot;
  Boss:TMiningBoss;
  Rock,Edge,Ore,Shadow,Color:TColor;
  function SX(X:Double):Double;
  begin Result:=Left+(0.8+(X-CX-0.8)*Zoom)*Scale;
  end;
  function SY(Y:Double):Double;
  begin Result:=Top+(0.5+(Y-Camera-0.5)*Zoom)*Scale;
  end;
  procedure Box(L,T,R,B:Double;C:TColor);
  begin Surface.FillRect(SX(L),SY(T),SX(R),SY(B),C);
  end;
  procedure Line(X1,Y1,X2,Y2:Double;C:TColor;Stroke:Double);
  begin Surface.Line(SX(X1),SY(Y1),SX(X2),SY(Y2),C,Max(1,Stroke*Scale*Zoom));
  end;
  procedure Circle(X,Y,R:Double;C:TColor;Filled:Boolean=True);
  begin Surface.Circle(SX(X),SY(Y),R*Scale*Zoom,C,Filled,Max(1,0.002*Scale*Zoom));
  end;
  procedure ScreenBox(L,T,R,B:Double;C:TColor);
  begin Surface.FillRect(Left+L*Scale,Top+T*Scale,Left+R*Scale,Top+B*Scale,C);
  end;
  procedure Plate(X,Y,W,H,Turn:Double;C:TColor);
  begin Line(X-Cos(Turn)*W,Y-Sin(Turn)*W,X+Cos(Turn)*W,Y+Sin(Turn)*W,C,H*2);
  end;
  procedure Fracture(X,Y,Age,Power:Double;C:TColor;Count:Integer);
  var
    Part:Integer;
    A,D,U:Double;
  begin
    if (Age<0) or (Age>=0.48) then Exit;
    U:=Age/0.48;
    for Part:=0 to Count-1 do begin A:=Part*2.39996+X*7;
      D:=Age*(0.24+0.30*Power)*(0.6+0.17*(Part mod 4));
      Plate(X+Cos(A)*D,Y+Sin(A)*D+Age*Age*0.40,0.012*(1-U),0.007*(1-U),A+Age*9,Mix(C,Shadow,U));
    end;
    if Age<0.065 then begin Line(X-0.035,Y,X+0.035,Y,RGB(255,241,184),0.008*(1-Age/0.065));
      Line(X,Y-0.025,X,Y+0.025,RGB(255,209,133),0.005*(1-Age/0.065));
    end;
    // Short outward cuts read as material flying off; overlapping small blast
    // circles looked like floating targeting markers behind the drill.
    if Age<0.19 then for Part:=0 to 3 do begin
      A:=Part*Pi/2+X*7;
      D:=0.018+Age*(0.23+Power*0.16);
      Line(X+Cos(A)*D,Y+Sin(A)*D,X+Cos(A)*(D+0.017*(1-U)),Y+Sin(A)*(D+0.017*(1-U)),Mix(C,Shadow,U),0.002);
    end;
  end;
  procedure RockCell(X,Y,W,H:Double;C:TColor;Variant:Integer);
  begin
    Box(X-W,Y,X+W,Y+H,Shadow);
    Box(X-W+0.003,Y+0.003,X+W-0.003,Y+H-0.004,C);
    Line(X-W+0.005,Y+0.005,X+W-0.005,Y+0.005,Mix(C,clWhite,0.38),0.003);
    if Variant mod 3=0 then begin Line(X-W*0.4,Y+H*0.25,X+W*0.2,Y+H*0.7,Ore,0.006);
      Line(X+W*0.2,Y+H*0.7,X+W*0.65,Y+H*0.45,Ore,0.004);
    end;
  end;
  procedure DrawMachine;
  var
    K,J:Integer;
    X,Y,Shift,Offset:Double;
    Armor:TColor;
  begin
    X:=Hero.X;
    Y:=Hero.Y;
    Armor:=Mix(RGB(64,182,185),RGB(244,155,94),Hurt*0.42);
    // Exact collision rectangles: tracks/body +/- .112 and broad bit +/- .135.
    Box(X-0.112,Y-0.076,X-0.077,Y+0.075,RGB(28,43,55));
    Box(X+0.077,Y-0.076,X+0.112,Y+0.075,RGB(28,43,55));
    for K:=0 to 8 do begin Shift:=Frac(Clock*5+K/9);
      Offset:=-0.069+Shift*0.135;
      Line(X-0.110,Y+Offset,X-0.080,Y+Offset,RGB(125,139,143),0.007);
      Line(X+0.080,Y+Offset,X+0.110,Y+Offset,RGB(125,139,143),0.007);
    end;
    Box(X-0.084,Y-0.074,X+0.084,Y+0.067,RGB(31,76,92));
    Box(X-0.077,Y-0.068-Hurt*0.010,X+0.077,Y+0.050-Hurt*0.010,Armor);
    Box(X-0.050,Y-0.053,X+0.050,Y-0.005,RGB(17,49,68));
    Line(X-0.043,Y-0.045,X+0.038,Y-0.045,RGB(172,239,229),0.006);
    Box(X-0.061,Y+0.009,X+0.061,Y+0.049,RGB(40,111,132));
    for K:=-1 to 1 do begin Circle(X+K*0.042,Y+0.028,0.010,RGB(236,204,111));
      Line(X+K*0.042-0.005,Y+0.028,X+K*0.042+0.005,Y+0.028,RGB(255,245,184),0.003);
    end;
    Box(X-MINING_HALF,Y+0.065,X+MINING_HALF,Y+MINING_TIP,RGB(68,89,103));
    for K:=-2 to 2 do begin
      Box(X+K*0.052-0.022,Y+0.069,X+K*0.052+0.022,Y+MINING_TIP-0.003,RGB(176,190,182));
      for J:=0 to 3 do begin Shift:=Frac(Clock*7+J/4+K*0.13);
        Offset:=0.071+Shift*0.073;
        Line(X+K*0.052-0.020,Y+Offset,X+K*0.052+0.020,Y+Offset+0.012,RGB(89,117,126),0.005);
      end;
    end;
    Line(X-MINING_HALF,Y+MINING_TIP,X+MINING_HALF,Y+MINING_TIP,RGB(245,211,131),0.004);
    // Exhaust is a real rear nozzle, not a floating warning marker.
    if (Floor(Clock/9) mod 3=1) then for K:=-1 to 1 do if K<>0 then begin
      Line(X+K*0.053,Y-0.072,X+K*0.060,Y-0.13-0.035*Sqr(Sin(Clock*29)),RGB(234,156,76),0.012);
      Line(X+K*0.053,Y-0.072,X+K*0.056,Y-0.105,RGB(255,239,172),0.006);
    end;
  end;
  procedure EnemyBody(const P:TMiningPoint;E:TMiningEnemy;Time:Double);
  var
    Age,Fade,Turn:Double;
    C:TColor;
    J:Integer;
  begin
    C:=RGB(198,89,97);
    case E.Kind mod 3 of 1:C:=RGB(218,138,81);
      2:C:=RGB(158,104,184);
    end;
    Age:=Time-E.Hit;
    if not E.Ambient and (Age>=0) then begin Fade:=1-Age/0.46;
      Turn:=E.Side*Age*10;
      Plate(P.X,P.Y,0.026*Fade,0.021*Fade,Turn,C);
      Fracture(E.X,E.Y,Age,0.7,C,4);
      Exit;
    end;
    Box(P.X-0.024,P.Y-0.025,P.X+0.024,P.Y+0.025,RGB(48,41,64));
    Box(P.X-0.020,P.Y-0.022,P.X+0.020,P.Y+0.022,C);
    Line(P.X-0.014,P.Y-0.005,P.X+0.014,P.Y-0.005,RGB(255,218,121),0.006);
    for J:=-1 to 1 do if J<>0 then begin Line(P.X+J*0.020,P.Y-0.010,P.X+J*0.034,P.Y+0.006,C,0.010);
      Circle(P.X+J*0.027,P.Y+0.019,0.008,RGB(41,47,65));
    end;
    if E.Kind=2 then Line(P.X-0.031,P.Y+0.027,P.X+0.031,P.Y+0.027,RGB(255,165,101),0.006);
  end;
begin
  Scale:=Min(Frame.Width/MINING_WIDTH,Frame.Height);
  Left:=(Frame.Width-MINING_WIDTH*Scale)/2;
  Top:=(Frame.Height-Scale)/2;
  Clock:=0;
  Camera:=0;
  Zoom:=1;
  CX:=0;
  Hero:=MiningPoint(0.8,0.42);
  Theme:=0;
  Hurt:=0;
  if FPlan<>nil then begin Clock:=EnsureRange(Frame.Time,0.0,FPlan.EndTime);
    Camera:=FPlan.DepthAt(Clock);
    Hero:=FPlan.ActorAt(Clock);
    Zoom:=FPlan.ZoomAt(Clock);
    Theme:=FPlan.ThemeAt(Clock);
    CX:=(Hero.X-0.8)*0.20;
    Hurt:=FPlan.HurtAt(Clock);
  end;
  case Theme mod 4 of
    0:begin Rock:=RGB(87,78,91);
      Edge:=RGB(147,116,115);
      Ore:=RGB(94,213,193);
      Shadow:=RGB(23,30,48);
    end;
    1:begin Rock:=RGB(91,83,62);
      Edge:=RGB(159,132,81);
      Ore:=RGB(242,185,94);
      Shadow:=RGB(30,32,37);
    end;
    2:begin Rock:=RGB(61,74,105);
      Edge:=RGB(105,139,164);
      Ore:=RGB(136,180,244);
      Shadow:=RGB(19,29,50);
    end;
    else begin Rock:=RGB(83,61,87);
      Edge:=RGB(149,96,121);
      Ore:=RGB(218,137,211);
      Shadow:=RGB(32,24,46);
    end;
  end;
  for I:=0 to 31 do Surface.FillRect(0,I*Frame.Height/32,Frame.Width,(I+1)*Frame.Height/32+1,Mix(Shadow,RGB(53,64,74),I/90));
  // World-space strata flow past at distinct parallax depths.
  N:=Floor(Camera/0.16);
  for I:=-3 to 10 do begin Y:=(N+I)*0.16;
    Width:=0.17+0.045*Sin((N+I)*2.7);
    Box(-0.5,Y,Width,Y+0.155,Rock);
    Box(1.6-Width,Y,2.1,Y+0.155,Rock);
    Line(Width-0.025,Y+0.012,Width,Y+0.012,Edge,0.012);
    Line(1.6-Width,Y+0.012,1.6-Width+0.025,Y+0.012,Edge,0.012);
    // Visible geology belongs to the solid tunnel sides, away from the actor
    // and projectile corridor. Distinct veins make the downward flow legible.
    for J:=0 to 2 do begin
      X:=0.023+J*0.044;
      U:=0.032+0.026*Sin((N+I)*1.7+J);
      Line(X,Y+0.025,X+0.025,Y+U+0.044,Mix(Edge,Shadow,0.35),0.003);
      Line(1.6-X,Y+0.025,1.6-X-0.025,Y+U+0.044,Mix(Edge,Shadow,0.35),0.003);
      if (N+I+J) mod 4=0 then begin
        Plate(X+0.011,Y+0.067,0.010,0.005,-0.8,Ore);
        Plate(1.6-X-0.011,Y+0.067,0.010,0.005,0.8,Ore);
      end;
    end;
    for J:=0 to 2 do begin X:=0.21+J*0.58+0.08*Sin((N+I)*1.6+J);
      Circle(X,Y+0.06,0.007,Mix(Ore,Shadow,0.55));
    end;
  end;
  for I:=0 to 14 do begin Y:=Camera+Frac(Camera*0.17+I*0.618)*1.3-0.1;
    X:=0.29+Frac(I*0.381)*1.04;
    Line(X,Y,X+0.025,Y+0.018,Mix(Edge,Shadow,0.75),0.002);
  end;
  if Frame.BackgroundOnly then begin Surface.DrawViewportMatte(Left,Top,Frame.Width,Frame.Height,Shadow);Exit;end;
  if (FPlan=nil) or (FPlan.EndTime<=0) then Exit;
  // Ahead: connected rock faces are consumed by the broad, visible cutting edge.
  A:=Max(0,FPlan.HitBefore(Clock-0.50));
  B:=Min(FPlan.HitBefore(Clock+1.45)+1,FPlan.Count-1);
  Drawn:=0;
  for I:=B downto A do begin if Drawn>=64 then Break;
    Hit:=FPlan.Hit[I];
    Age:=Clock-Hit.Time;
    if (Age>=0.48) or (Hit.Boss>=0) then Continue;
    if Hit.Top-Camera>1.1 then Continue;
    Inc(Drawn);
    N:=5;
    if Hit.Strength>=0.75 then N:=7;
    Width:=0.27/N;
    if Age<0 then begin Y:=Hit.Top;
      if Clock>=Hit.First then Y:=Max(Y,Hero.Y+MINING_TIP);
      for J:=0 to N-1 do begin X:=Hit.X+(J-(N-1)/2)*Width;
        RockCell(X,Y,Width/2-0.001,Max(0.006,Hit.Bottom-Y),Mix(Rock,Edge,0.2+0.3*Hit.Strength),(I+J));
      end;
      if Hit.Kind=3 then begin U:=Smooth((Clock-Hit.First+0.55)/0.55);
        Gap:=0.72-0.43*U;
        Box(0.16,Hit.Top-0.025,Hit.X-Gap/2,Hit.Bottom+0.035,Edge);
        Box(Hit.X+Gap/2,Hit.Top-0.025,1.44,Hit.Bottom+0.035,Edge);
        Line(Hit.X-Gap/2,Hit.Top-0.025,Hit.X-Gap/2,Hit.Bottom+0.035,Ore,0.006);
        Line(Hit.X+Gap/2,Hit.Top-0.025,Hit.X+Gap/2,Hit.Bottom+0.035,Ore,0.006);
      end;
    end else begin
      for J:=0 to N-1 do begin X:=Hit.X+(J-(N-1)/2)*Width;
        Fracture(X,Hit.Bottom-0.021,Age,Hit.Strength,Edge,4);
      end;
      if Hit.Kind=3 then for J:=-1 to 1 do if J<>0 then Plate(Hit.X+J*(0.20+Age*0.50),Hit.Top+Age*0.23,0.14*(1-Age/0.48),0.032*(1-Age/0.48),J*Age*6,Edge);
    end;
  end;
  // Huge hostile mining rigs occupy the tunnel; their armor is audio-hit driven.
  for I:=0 to FPlan.BossCount-1 do begin Boss:=FPlan.Boss[I];
    if (Clock<Boss.Start) or (Clock>Boss.Finish) then Continue;
    Point:=FPlan.ActorAt(Min(Clock,Boss.Kill));
    X:=0.8+(Point.X-0.8)*0.65;
    Y:=FPlan.BossTop(I,Min(Clock,Boss.Kill));
    Age:=Clock-Boss.Kill;
    if Age<0 then begin
      Box(X-0.31,Y+0.005,X+0.31,Y+0.30,RGB(31,38,64));
      Box(X-0.22,Y+0.03,X+0.22,Y+0.27,RGB(79,74,124));
      for J:=0 to 5 do begin U:=Clock-Boss.Purge[J];
        Gap:=(J mod 3-1)*0.19;
        Depth:=(J div 3)*0.12;
        if U<0 then begin RockCell(X+Gap,Y+0.035+Depth,0.085,0.10,RGB(170,103,147),J);
          Line(X+Gap-0.05,Y+0.055+Depth,X+Gap+0.05,Y+0.055+Depth,RGB(255,204,113),0.007);
        end
        else if U<0.55 then Plate(X+Gap+Sign(Gap+0.001)*U*0.5,Y+0.035+Depth+U*0.22,0.085*(1-U/0.55),0.048*(1-U/0.55),(J-2.5)*U*5,RGB(170,103,147));
      end;
      Circle(X,Y+0.14,0.055,RGB(36,43,70));
      Circle(X,Y+0.14,0.032,RGB(229,174,103));
      Line(X-0.29,Y,X+0.29,Y,RGB(240,180,115),0.008);
      Health:=FPlan.HealthAt(I,Clock);
      ScreenBox(0.44,0.030,1.16,0.076,RGB(8,15,28));
      ScreenBox(0.45,0.040,1.15,0.066,RGB(54,64,85));
      ScreenBox(0.45,0.040,0.45+0.70*Health,0.066,RGB(225,141,166));
    end else begin
      for J:=0 to 5 do begin Angle:=J*Pi/3;
        Plate(X+Cos(Angle)*Age*0.75,Y+0.14+Sin(Angle)*Age*0.55,0.08*(1-Age/0.75),0.045*(1-Age/0.75),Angle+Age*7,RGB(170,103,147));
      end;
      Fracture(X,Y+0.14,Age,1.8,RGB(249,190,105),18);
      Circle(X,Y+0.14,0.045+Age*0.52,Mix(RGB(255,223,150),Shadow,Age/0.75),False);
    end;
  end;
  A:=Max(0,FPlan.EnemyBefore(Clock-3.1));
  B:=Min(FPlan.EnemyBefore(Clock),A+159);
  for I:=A to B do begin Enemy:=FPlan.Enemy[I];
    if (Clock<Enemy.First) or (Clock>=Enemy.Last) then Continue;
    Point:=FPlan.EnemyAt(I,Clock);
    if (Point.Y-Camera<-0.15) or (Point.Y-Camera>1.15) then Continue;
    EnemyBody(Point,Enemy,Clock);
  end;
  if Frame.Time<FPlan.SoundEnd+1.18 then DrawMachine;
  // Enemy rock rounds/energy lances are physically moving saved attacks.
  A:=Max(0,FPlan.ShotBefore(Clock-1.55));
  B:=Min(FPlan.ShotBefore(Clock),A+639);
  for I:=A to B do begin Shot:=FPlan.Shot[I];
    if Clock>=Shot.Finish then Continue;
    Age:=Clock-Shot.Impact;
    case Shot.Kind mod 3 of 0:Color:=RGB(237,162,106);
      1:Color:=RGB(234,118,177);
      else Color:=RGB(186,153,242);
    end;
    if Age<0 then begin Point:=FPlan.ShotAt(I,Clock);
      Past:=FPlan.ShotAt(I,Max(Shot.Launch,Clock-0.045));
      Line(Past.X,Past.Y,Point.X,Point.Y,Mix(Color,Shadow,0.4),Shot.Radius*0.9);
      if Shot.Kind=1 then Line(Past.X,Past.Y,Point.X,Point.Y,Color,0.006)
      else begin Circle(Point.X,Point.Y,Shot.Radius,Color);
        Circle(Point.X-0.002,Point.Y-0.003,Shot.Radius*0.35,RGB(255,235,185));
      end;
    end else begin
      U:=Age/0.18;
      for J:=0 to 2 do begin Angle:=J*Pi*2/3+Clock*8;
        Line(Shot.B.X,Shot.B.Y,Shot.B.X+Cos(Angle)*(0.015+Age*0.16),Shot.B.Y+Sin(Angle)*(0.015+Age*0.16),Mix(Color,Shadow,U),0.003*(1-U));
      end;
    end;
  end;
  A:=Max(0,FPlan.PulseBefore(Clock-0.10)+1);
  B:=FPlan.PulseBefore(Clock);
  A:=Max(A,B-63);
  for I:=A to B do begin Point:=FPlan.ActorAt(FPlan.Pulse[I].Time);
    Age:=Clock-FPlan.Pulse[I].Time;
    U:=1-Age/0.10;
    for J:=-1 to 1 do begin X:=Point.X+J*0.085;
      Line(X,Point.Y+MINING_TIP,X+J*Age*0.8,Point.Y+MINING_TIP+Age*0.3,RGB(255,221,143),0.003*U);
    end;
  end;
  // Closing rubble stays behind the rear armor, conveying pursuit during void drops.
  if (Clock<FPlan.SoundEnd) and (Floor(Clock/9) mod 3=1) then for I:=0 to 9 do begin
    U:=Frac(Clock*0.7+I*0.618);
    X:=Hero.X+(I-4.5)*0.038;
    Y:=Camera+0.08+U*0.20;
    Plate(X,Y,0.022,0.015,Clock+I,Edge);
  end;
  if Left>0 then begin Surface.FillRect(0,0,Left,Frame.Height,Shadow);
    Surface.FillRect(Frame.Width-Left,0,Frame.Width,Frame.Height,Shadow);
  end;
  if Top>0 then begin Surface.FillRect(0,0,Frame.Width,Top,Shadow);
    Surface.FillRect(0,Frame.Height-Top,Frame.Width,Frame.Height,Shadow);
  end;
end;
end.
