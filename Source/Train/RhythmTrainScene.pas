unit RhythmTrainScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmTrainPlan;
type
  TTrainAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TTrainPlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;

destructor TTrainAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TTrainAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TTrainAnimation.Notice:string;
begin Result:=FError;
end;

procedure TTrainAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TTrainPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TTrainAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
const
  Width=16/9;
var
  Scale,Left,Top,Time,Travel,Zoom,Age,U,X,Y,Angle,R,Power,Transition:Double;
  I,J,A,B,Index,Drawn,Kind,HitIndex:Integer;
  P,Q,V,Muzzle:TTrainPoint;
  Hit:TTrainHit;
  Shot:TTrainShot;
  Boss:TTrainBoss;
  Tint,Accent,Back,High:TColor;
  function MixColor(A,B:TColor;U:Double):TColor;
  begin U:=EnsureRange(U,0.0,1.0);
    Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
  end;
  function PointMix(const A,B:TTrainPoint;U:Double):TTrainPoint;
  begin Result:=TrainPoint(A.X+(B.X-A.X)*U,A.Y+(B.Y-A.Y)*U);
  end;
  procedure Map(X,Y:Double;out PX,PY:Double);
  begin PX:=Left+(0.90+(X-0.90)*Zoom)*Scale;
    PY:=Top+(0.55+(Y-0.55)*Zoom)*Scale;
  end;
  procedure Line(X1,Y1,X2,Y2:Double;Tint:TColor;Stroke:Double);
  var
    AX,AY,BX,BY:Double;
  begin Map(X1,Y1,AX,AY);
    Map(X2,Y2,BX,BY);
    Surface.Line(AX,AY,BX,BY,Tint,Max(1.0,Stroke*Scale*Zoom));
  end;
  procedure Box(X1,Y1,X2,Y2:Double;Tint:TColor);
  var
    AX,AY,BX,BY:Double;
  begin Map(X1,Y1,AX,AY);
    Map(X2,Y2,BX,BY);
    Surface.FillRect(AX,AY,BX,BY,Tint);
  end;
  procedure Circle(X,Y,R:Double;Tint:TColor;Filled:Boolean=True);
  var
    AX,AY:Double;
  begin Map(X,Y,AX,AY);
    Surface.Circle(AX,AY,R*Scale*Zoom,Tint,Filled,Max(1.0,0.002*Scale*Zoom));
  end;
  function RailY(X:Double):Double;
  var
    D:Double;
  begin D:=Travel+X-1.12;
    Result:=0.705+0.040*Sin(D*0.65)+0.014*Sin(D*0.23);
  end;
  procedure Wheel(X,Y,R,Phase:Double;Tint:TColor);
  var
    N:Integer;
    A:Double;
  begin Circle(X,Y,R,RGB(13,23,33));
    Circle(X,Y,R*0.70,Tint,False);
    for N:=0 to 2 do begin A:=Phase+N*Pi*2/3;
      Line(X,Y,X+Cos(A)*R*0.65,Y+Sin(A)*R*0.65,RGB(167,198,204),0.0013);
    end;
  end;
  procedure Hero(Car:Integer);
  var
    P,Q:TTrainPoint;
    C,D:TColor;
    Damage,A,X,Y:Double;
    N:Integer;
  begin
    P:=FPlan.HeroCarAt(Car,Time);
    if (P.X< -0.12) or (P.X>Width+0.12) then Exit;
    Damage:=FPlan.DamageAt(Car,Time);
    C:=RGB(53,137,183);
    D:=RGB(93,187,207);
    if Car=0 then begin C:=RGB(42,111,162);
      D:=RGB(121,207,220);
    end;
    if Car<7 then begin Q:=FPlan.HeroCarAt(Car+1,Time);
      Line(P.X-0.055,P.Y+0.015,Q.X+0.055,Q.Y+0.015,RGB(54,67,78),0.006);
    end;
    Box(P.X-0.052,P.Y-0.027,P.X+0.052,P.Y+0.020,RGB(23,49,66));
    Box(P.X-0.047,P.Y-0.025,P.X+0.047,P.Y+0.014,MixColor(C,RGB(172,106,75),Damage*0.35));
    Line(P.X-0.046,P.Y-0.023,P.X+0.046,P.Y-0.023,D,0.005);
    Line(P.X-0.046,P.Y+0.009,P.X+0.047,P.Y+0.009,RGB(212,181,100),0.004);
    if Car=0 then begin
      Box(P.X+0.020,P.Y-0.041,P.X+0.051,P.Y-0.013,D);
      Box(P.X+0.028,P.Y-0.036,P.X+0.047,P.Y-0.025,RGB(20,45,65));
      Box(P.X+0.047,P.Y-0.015,P.X+0.062,P.Y+0.011,RGB(207,176,95));
      Box(P.X-0.028,P.Y-0.043,P.X-0.015,P.Y-0.023,RGB(23,43,56));
      for N:=0 to 3 do begin U:=Frac(Time*2.3+N*0.25);
        Circle(P.X-0.022-U*0.085,P.Y-0.048-U*0.045,0.008+0.012*U,MixColor(RGB(166,190,193),Back,U));
      end;
    end else for N:=-1 to 1 do begin
      Box(P.X+N*0.025-0.009,P.Y-0.017,P.X+N*0.025+0.009,P.Y-0.002,RGB(30,65,84));
      Line(P.X+N*0.025-0.007,P.Y-0.014,P.X+N*0.025+0.006,P.Y-0.014,RGB(153,218,224),0.002);
    end;
    Muzzle:=FPlan.HeroMuzzle(Car,Time);
    Line(P.X,P.Y-0.027,Muzzle.X,Muzzle.Y,RGB(39,73,91),0.009);
    Line(P.X,P.Y-0.029,Muzzle.X,Muzzle.Y,RGB(172,208,205),0.003);
    Circle(P.X,P.Y-0.029,0.012,RGB(52,91,112));
    Wheel(P.X-0.031,P.Y+0.025,0.014,Time*31+Car,RGB(121,163,177));
    Wheel(P.X+0.031,P.Y+0.025,0.014,Time*31+Car,RGB(121,163,177));
    if Damage>0 then for N:=0 to 2 do begin A:=Frac(Time*6+N*0.27);
      X:=P.X+0.027+N*0.008;
      Y:=P.Y-0.042-A*0.036;
      Line(X,Y+0.015*Damage,X+Sin(Time*17+N)*0.004,Y-0.009*Damage,RGB(255,145+N*25,71),0.006*Damage);
    end;
  end;
  procedure EnemyBody(EnemyIndex:Integer);
  var
    E:TTrainEnemy;
    G:TTrainGroup;
    P,S:TTrainPoint;
    Age,U,X,Y,Turn,HP:Double;
    C,Edge:TColor;
    N:Integer;
  begin
    E:=FPlan.Enemy[EnemyIndex];
    G:=FPlan.Group[E.Group];
    Age:=Time-FPlan.Event[E.KillSource].Time;
    if (Time<G.Show) or (Age>=0.70) then Exit;
    P:=FPlan.EnemyAt(EnemyIndex,Min(Time,FPlan.Event[E.KillSource].Time));
    S:=FPlan.EnemySize(EnemyIndex);
    if (P.X< -0.25) or (P.X>Width+0.25) then Exit;
    C:=RGB(183,73,69);
    Edge:=RGB(244,174,106);
    if G.Kind=1 then begin C:=RGB(198,99,75);
      Edge:=RGB(247,203,117);
    end;
    if G.Kind=2 then begin C:=RGB(137,111,87);
      Edge:=RGB(239,161,80);
    end;
    if G.Kind=4 then begin C:=RGB(85,72,124);
      Edge:=RGB(214,170,240);
    end;
    if G.Kind=3 then begin C:=RGB(131,115,93);
      Edge:=RGB(219,177,100);
    end;
    if Age>=0 then begin U:=Age/0.70;
      X:=P.X-Age*(0.80+0.08*(E.Slot mod 3));
      Y:=P.Y-0.28*Age+1.10*Age*Age;
      Turn:=(EnemyIndex mod 2*2-1)*Age*5.5;
      Line(X-Cos(Turn)*S.X*(1-U*U),Y-Sin(Turn)*S.X*(1-U*U),X+Cos(Turn)*S.X*(1-U*U),Y+Sin(Turn)*S.X*(1-U*U),MixColor(C,Back,U),S.Y*1.70*(1-U*U));
      for N:=0 to 3 do begin X:=P.X+Cos(N*1.7+EnemyIndex)*Age*0.25;
        Y:=P.Y+Sin(N*1.7+EnemyIndex)*Age*0.19+Age*Age*0.45;
        Line(X-0.005*(1-U),Y,X+0.005*(1-U),Y,Edge,0.005*(1-U));
      end;
      Exit;
    end;
    HP:=FPlan.EnemyHP(EnemyIndex,Time);
    Box(P.X-S.X,P.Y-S.Y,P.X+S.X,P.Y+S.Y,RGB(30,35,48));
    Box(P.X-S.X+0.003,P.Y-S.Y+0.003,P.X+S.X-0.003,P.Y+S.Y-0.003,MixColor(C,RGB(93,63,61),(1-HP)*0.55));
    Line(P.X-S.X+0.004,P.Y-S.Y+0.005,P.X+S.X-0.004,P.Y-S.Y+0.005,Edge,0.003);
    Line(P.X,P.Y+S.Y-0.014,P.X,P.Y+S.Y,Edge,0.006);
    if G.Kind=0 then begin
      Box(P.X-S.X*0.60,P.Y-S.Y*0.62,P.X+S.X*0.60,P.Y-S.Y*0.08,RGB(34,48,62));
      Wheel(P.X-S.X*0.60,P.Y+S.Y*0.65,S.Y*0.29,Time*24,RGB(120,140,153));
      Wheel(P.X+S.X*0.60,P.Y+S.Y*0.65,S.Y*0.29,Time*24,RGB(120,140,153));
      if E.Slot<G.Members-1 then begin Q:=FPlan.EnemyAt(EnemyIndex+1,Time);
        if Time<FPlan.Event[FPlan.Enemy[EnemyIndex+1].KillSource].Time then Line(P.X-S.X,P.Y+0.01,Q.X+S.X,Q.Y+0.01,Edge,0.004);
      end;
    end else if G.Kind=1 then begin
      Line(P.X-S.X*0.75,P.Y-S.Y*0.55,P.X+S.X*0.75,P.Y+S.Y*0.40,Edge,0.005);
      Line(P.X-S.X*0.75,P.Y+S.Y*0.40,P.X+S.X*0.75,P.Y-S.Y*0.55,Edge,0.005);
      Circle(P.X,P.Y,0.007,RGB(248,222,149));
    end else if G.Kind=4 then begin
      Box(P.X-S.X*0.8,P.Y-S.Y*0.68,P.X+S.X*0.8,P.Y+S.Y*0.50,RGB(114,94,158));
      Circle(P.X,P.Y,0.024,RGB(47,47,72));
      Circle(P.X,P.Y,0.014,RGB(238,176,111));
      for N:=-1 to 1 do Line(P.X+N*0.018,P.Y-0.006,P.X+N*0.018,P.Y+S.Y,RGB(34,40,58),0.009);
      Wheel(P.X-S.X*0.63,P.Y+S.Y*0.77,S.Y*0.19,Time*20,RGB(161,142,178));
      Wheel(P.X+S.X*0.63,P.Y+S.Y*0.77,S.Y*0.19,Time*20,RGB(161,142,178));
      if E.Slot<G.Members-1 then begin Q:=FPlan.EnemyAt(EnemyIndex+1,Time);
        if Time<FPlan.Event[FPlan.Enemy[EnemyIndex+1].KillSource].Time then Line(P.X-S.X,P.Y+0.02,Q.X+S.X,Q.Y+0.02,RGB(120,111,155),0.008);
      end;
    end else if G.Kind=2 then begin
      Circle(P.X,P.Y-0.008,0.017,RGB(73,69,72));
      Line(P.X,P.Y-0.005,P.X+0.024,P.Y+0.026,Edge,0.008);
    end else for N:=-1 to 1 do Line(P.X-S.X+0.008,P.Y+N*0.030,P.X+S.X-0.008,P.Y+N*0.030,Edge,0.008);
  end;
begin
  Scale:=Min(Frame.Width/Width,Frame.Height);
  Left:=(Frame.Width-Width*Scale)/2;
  Top:=(Frame.Height-Scale)/2;
  Time:=Max(0.0,Frame.Time);
  Travel:=Time*2.25;
  Zoom:=1;
  Kind:=0;
  Transition:=1;
  if FPlan<>nil then begin Time:=Min(Time,FPlan.EndTime);
    Travel:=FPlan.TravelAt(Time);
    Zoom:=FPlan.CameraAt(Time);
    Kind:=FPlan.SceneAt(Time);
    Transition:=FPlan.SceneTransition(Time);
  end;
  case Kind of
    1:begin Back:=RGB(46,48,71);
      High:=RGB(169,119,104);
      Accent:=RGB(128,153,165);
    end;
    2:begin Back:=RGB(11,17,30);
      High:=RGB(29,39,55);
      Accent:=RGB(84,105,125);
    end;
    else begin Back:=RGB(55,99,111);
      High:=RGB(130,170,166);
      Accent:=RGB(121,162,145);
    end;
  end;
  Back:=MixColor(RGB(18,31,47),Back,0.55+0.45*Transition);
  for I:=0 to 31 do Surface.FillRect(0,I*Frame.Height/32,Frame.Width,(I+1)*Frame.Height/32+1,MixColor(High,Back,I/31));
  if Kind<>2 then begin
    Circle(1.48,0.14,0.065,RGB(235,214,159));
    for I:=-2 to 12 do begin X:=I*0.20-Frac(Travel*0.06)*0.20;
      Y:=0.43+0.035*Sin((I+Floor(Travel*0.06))*1.7);
      Line(X,Y,X,0.68,MixColor(Back,RGB(48,85,94),0.55),0.24);
    end;
  end;
  for I:=-2 to 22 do begin X:=I*0.10-Frac(Travel/0.10)*0.10;
    Y:=RailY(X);
    if Kind=1 then begin
      Age:=0;
      if FPlan<>nil then Age:=Max(0.0,(FPlan.HeroCarAt(7,Time).X-0.12-X)/2.25);
      if Age>0 then begin Angle:=Age*6;
        Line(X-Cos(Angle)*0.038,Y+0.05+Age*Age*0.8,X+Cos(Angle)*0.038,Y+0.05+Age*Age*0.8+Sin(Angle)*0.08,RGB(99,107,127),0.020);
      end
      else begin Line(X,Y+0.07,X,1.05,RGB(72,86,108),0.018);
        Line(X-0.05,Y+0.10,X+0.05,0.95,RGB(112,129,147),0.007);
      end;
    end else if Kind=2 then begin
      Line(X-0.04,0.10,X-0.04,0.92,RGB(39,53,69),0.016);
      Line(X-0.04,0.10,X+0.06,0.08,RGB(57,71,83),0.016);
      Box(X-0.015,0.105,X+0.025,0.119,RGB(194,183,122));
    end else begin
      Line(X+0.045,Y-0.06,X+0.045,Y+0.22,RGB(67,98,94),0.011);
      Line(X+0.045,Y-0.06,X+0.09,Y-0.06,RGB(146,164,137),0.004);
    end;
    Line(X-0.035,Y+0.005,X+0.035,Y+0.032,RGB(79,81,81),0.012);
  end;
  for I:=0 to 79 do begin X:=-0.08+I*0.025;
    Y:=RailY(X);
    Line(X,Y,X+0.025,RailY(X+0.025),RGB(180,190,185),0.006);
    Line(X,Y+0.043,X+0.025,RailY(X+0.025)+0.043,RGB(116,132,140),0.006);
  end;
  if FPlan=nil then Exit;
  for I:=-1 to 18 do begin X:=I*0.11-Frac(Travel/0.11)*0.11;
    Line(X-0.032,0.326,X+0.032,0.347,MixColor(Back,RGB(98,108,111),0.65),0.006);
  end;
  Line(-0.10,0.326,1.90,0.326,MixColor(Back,RGB(142,153,154),0.70),0.003);
  Line(-0.10,0.348,1.90,0.348,MixColor(Back,RGB(98,115,127),0.65),0.003);
  // The armored formation runs on an elevated parallel railway; its carriage
  // wheels and connecting rods remain visible instead of floating above the action.
  for I:=0 to FPlan.BossCount-1 do begin Boss:=FPlan.Boss[I];
    if (Time>=Boss.Show) and (Time<Boss.Kill+0.70) then begin
      for J:=-1 to 16 do begin X:=J*0.12-Frac(Travel/0.12)*0.12;
        Line(X-0.035,0.292,X+0.035,0.313,RGB(65,68,91),0.007);
      end;
      Line(-0.10,0.291,1.90,0.291,RGB(113,111,138),0.003);
      Line(-0.10,0.315,1.90,0.315,RGB(74,78,104),0.003);
    end;
  end;
  FPlan.VisibleEnemies(Time,A,B);
  Drawn:=0;
  for I:=A to B do begin Index:=FPlan.VisibleEnemy(I);
    EnemyBody(Index);
    Inc(Drawn);
    if Drawn>=180 then Break;
  end;
  // Incoming shells and missiles are real moving attacks, not generic spark dust.
  A:=Max(0,FPlan.ShotBefore(Time-1.60)+1);
  B:=FPlan.ShotBefore(Time);
  A:=Max(A,B-319);
  for I:=A to B do begin Shot:=FPlan.Shot[I];
    if FPlan.ShotAt(I,Time,P) then begin
      Age:=Time-Shot.Start;
      U:=Age/(Shot.Near-Shot.Start);
      Q:=PointMix(Shot.A,Shot.B,Max(0.0,U-0.035));
      Tint:=RGB(252,152,92);
      if Shot.Kind=1 then Tint:=RGB(238,104,153) else if Shot.Kind=2 then Tint:=RGB(188,139,245);
      Line(Q.X,Q.Y,P.X,P.Y,Tint,0.004);
      Circle(P.X,P.Y,0.0055,Tint);
      Circle(P.X,P.Y,0.002,RGB(255,235,185));
    end;
    if (Shot.Outcome=1) and (Time>=Shot.Near-0.18) and (Time<Shot.Near) then begin
      Q:=FPlan.HeroMuzzle(Shot.Car,Max(0.0,Shot.Near-0.18));
      U:=(Time-Shot.Near+0.18)/0.18;
      P:=PointMix(Q,Shot.B,U);
      V:=PointMix(Q,Shot.B,Max(0.0,U-0.12));
      Line(V.X,V.Y,P.X,P.Y,RGB(100,203,211),0.003);
      Circle(P.X,P.Y,0.004,RGB(195,246,227));
    end;
    Age:=Time-Shot.Near;
    if (Age>=0) and (Age<0.15) and (Shot.Outcome<>0) then begin
      U:=Age/0.15;
      Circle(Shot.B.X,Shot.B.Y,0.009+0.026*U,MixColor(RGB(255,210,128),Back,U),False);

    end;
  end;
  // Eight separate cars follow the same saved route, with individual couplers.
  if (FPlan.GoalTime>0) and (Frame.Time<FPlan.EndTime) then for I:=7 downto 0 do Hero(I);
  HitIndex:=FPlan.HitBefore(Time);
  A:=Max(FPlan.HitBefore(Time-0.23)+1,HitIndex-127);
  A:=Max(0,A);
  B:=Min(FPlan.HitBefore(Time+0.42),A+255);
  for I:=A to B do begin Hit:=FPlan.Hit[I];
    Age:=Time-FPlan.Event[Hit.Source].Time;
    if FPlan.HitAt(I,Time,P) then begin
      if Time-Hit.Launch>0.025 then begin FPlan.HitAt(I,Time-0.025,Q);
        Line(Q.X,Q.Y,P.X,P.Y,RGB(73,170,194),0.004);
      end;
      Circle(P.X,P.Y,0.006,RGB(158,238,235));
      Circle(P.X,P.Y,0.0025,RGB(246,253,218));
      if Time-Hit.Launch<0.045 then Circle(Hit.A.X,Hit.A.Y,0.014*(1-(Time-Hit.Launch)/0.045),RGB(255,223,148));
    end;
    if (Age>=0) and (Age<0.23) then begin
      Power:=FPlan.Event[Hit.Source].Power;
      U:=Age/0.23;
      Circle(Hit.B.X,Hit.B.Y,0.012+Age*(0.25+Power*0.12),MixColor(RGB(255,213,127),Back,U),False);
      if Age<0.055 then Circle(Hit.B.X,Hit.B.Y,0.018*(1-Age/0.055),RGB(255,238,177));
      for J:=0 to 4 do begin Angle:=J*2.39996+Hit.Enemy*0.7;
        R:=Age*(0.18+Power*0.22);
        Line(Hit.B.X+Cos(Angle)*R*0.65,Hit.B.Y+Sin(Angle)*R*0.65,Hit.B.X+Cos(Angle)*R,Hit.B.Y+Sin(Angle)*R,RGB(247,166,83),0.003*(1-U));
      end;
    end;
  end;
  for I:=0 to FPlan.BossCount-1 do begin Boss:=FPlan.Boss[I];
    if (Time>=Boss.Show) and (Time<Boss.Kill) then begin
      Box(0.53,0.045,1.25,0.082,RGB(18,22,35));
      Box(0.537,0.051,1.243,0.074,RGB(56,46,76));
      Box(0.537,0.051,0.537+0.706*FPlan.BossHP(I,Time),0.074,RGB(211,153,225));
      Line(0.537,0.051,1.243,0.051,RGB(246,216,232),0.002);
    end;
    Age:=Time-Boss.Kill;
    if (Age>=0) and (Age<0.85) then begin U:=Age/0.85;
      for J:=0 to 3 do begin X:=0.78+J*0.18;
        Y:=0.22+0.03*Sin(J*2);
        R:=0.025+Age*0.23;
        Circle(X,Y,R,MixColor(RGB(242,185,114),Back,U),False);
      end;
    end;
  end;
  if Left>0 then begin Surface.FillRect(0,0,Left,Frame.Height,RGB(10,18,29));
    Surface.FillRect(Frame.Width-Left,0,Frame.Width,Frame.Height,RGB(10,18,29));
  end;
  if Top>0 then begin Surface.FillRect(0,0,Frame.Width,Top,RGB(10,18,29));
    Surface.FillRect(0,Frame.Height-Top,Frame.Width,Frame.Height,RGB(10,18,29));
  end;
end;
end.
