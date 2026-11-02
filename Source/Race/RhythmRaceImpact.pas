unit RhythmRaceImpact;
// 接触時計の演出だけを描く。音同期・ボス交通接触ともピーク後は実アルファで消える。
interface
uses RhythmRaceCrash,RhythmRenderSurface;
// Ageは接触からの秒。ピーク保持後をsmoothstepで1→0へ減衰する。
function RaceImpactOpacity(Age,Lifetime,Hold:Double):Double;
procedure DrawRaceContactEffects(Plan:TRaceCrashPlan;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer);
implementation
uses System.Math,Winapi.Windows,Vcl.Graphics;
function Mix(A,B:TColor;U:Double):TColor;
begin U:=EnsureRange(U,0.0,1.0);Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));end;
function RaceImpactOpacity(Age,Lifetime,Hold:Double):Double;
var U:Double;
begin
  Result:=0;if (Age<0) or (Lifetime<=0) or (Age>=Lifetime) then Exit;
  Hold:=EnsureRange(Hold,0.0,Lifetime*0.5);if Age<=Hold then Exit(1);
  U:=EnsureRange((Age-Hold)/(Lifetime-Hold),0.0,1.0);Result:=1-U*U*(3-2*U);
end;
procedure DrawRaceContactEffects(Plan:TRaceCrashPlan;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer);
var Clock,Scale,Left,Top,Age,U,A,R,X,Y,Power,Opacity:Double;
  I,J,First,Last,Parts:Integer;P:TCrashProjection;H:TCrashHit;E:TCrashEnemy;Shunt:TCrashShunt;Tint:TColor;
  procedure Line(X1,Y1,X2,Y2:Double;C:TColor;W:Double);
  begin Surface.Line(Left+X1*Scale,Top+Y1*Scale,Left+X2*Scale,Top+Y2*Scale,C,Max(1,W*Scale),Opacity);end;
  procedure Box(X1,Y1,X2,Y2:Double;C:TColor);
  begin Surface.FillRect(Left+X1*Scale,Top+Y1*Scale,Left+X2*Scale,Top+Y2*Scale,C,Opacity);end;
  procedure Dot(X,Y,R:Double;C:TColor;Filled:Boolean=True);
  begin Surface.Circle(Left+X*Scale,Top+Y*Scale,R*Scale,C,Filled,Max(1,0.002*Scale),Opacity);end;
begin
  Clock:=EnsureRange(Time,0.0,Plan.EndTime);Scale:=Min(Width/1.6,Height);
  Left:=(Width-1.6*Scale)/2;Top:=(Height-Scale)/2;Opacity:=1;
  // The road/audio keep absolute time; only a defeated car holds its impact pose for 18ms.
  Last:=Plan.HitBefore(Clock);
  First:=Max(0,Last-63);
  for I:=Last downto First do begin H:=Plan.Hits[I];
    Age:=Clock-H.Time;
    if Age>0.65 then Break;
    E:=Plan.Enemies[H.Enemy];
    U:=Age/0.65;
    P:=Plan.Project(H.Distance+Plan.SpeedAt(H.Time)*Age*0.85,H.Lane,Clock,0.015);
    if not P.Visible then Continue;
    Power:=0.5+0.5*H.Strength;
    Parts:=16;
    if E.Kind>0 then Parts:=40;
    if E.Boss>=0 then Parts:=56;
    Opacity:=RaceImpactOpacity(Age,0.10,0.012);
    if Age<0.10 then Dot(P.X,P.Y,(0.042-0.025*Age/0.10)*P.Scale*Power,RGB(255,240,181));
    Opacity:=RaceImpactOpacity(Age,0.65,0.018);
    for J:=0 to 2 do begin R:=(0.025+Age*(0.38+0.12*J))*P.Scale;
      Dot(P.X,P.Y,R,Mix(RGB(255,210,114),RGB(77,93,101),U),False);
    end;
    for J:=0 to Parts-1 do begin A:=J*2.39996+H.Source*0.17;
      R:=(0.01+Age*(0.3+0.06*(J mod 7)))*P.Scale;
      X:=P.X+Cos(A)*R;
      Y:=P.Y+Sin(A)*R*0.55+Age*Age*0.20*P.Scale;
      Tint:=Mix(RGB(255,198,112),RGB(80,99,107),U);
      if J mod 3=0 then Tint:=Mix(RGB(199,214,221),RGB(65,79,91),U);
      Line(X,Y,X+Cos(A)*0.02*(1-U)*P.Scale,Y+Sin(A)*0.02*(1-U)*P.Scale,Tint,(0.003+0.002*Ord(E.Kind>0))*(1-U)*P.Scale);
    end;
    if (E.Kind>0) and (H.HP=0) then begin
      for J:=0 to 11 do begin A:=J*2.39996;
        X:=P.X+Cos(A)*Age*0.52*P.Scale;
        Y:=P.Y-Sin(A)*Age*0.30*P.Scale+Age*Age*0.2;
        Box(X-0.008*P.Scale,Y-0.006*P.Scale,X+0.008*P.Scale,Y+0.006*P.Scale,Mix(RGB(172,138,93),RGB(71,91,105),U));
      end;
      for J:=0 to 3 do Dot(P.X+(J-1.5)*Age*0.10,P.Y-Age*0.13,(0.012+Age*0.045)*P.Scale,Mix(RGB(121,122,124),RGB(102,132,139),U));
    end;
  end;
  // 一般車の排除は接触時計で発生する。音楽イベントやボスHPには加算しない。
  Last:=Plan.ShuntBefore(Clock);
  First:=Max(0,Last-31);
  for I:=Last downto First do begin
    Shunt:=Plan.Shunts[I];
    Age:=Clock-Shunt.Time;
    if Age>0.55 then Break;
    P:=Plan.Project(Shunt.Distance+Plan.DistanceAt(Clock)-Plan.DistanceAt(Shunt.Time),Shunt.Lane,Clock,0.035);
    if not P.Visible then Continue;
    U:=Age/0.55;
    Opacity:=RaceImpactOpacity(Age,0.07,0.012);
    if Age<0.07 then Dot(P.X,P.Y,(0.025-0.018*Age/0.07)*P.Scale,RGB(255,235,164));
    Opacity:=RaceImpactOpacity(Age,0.55,0.018);
    for J:=0 to 17 do begin
      A:=J*2.39996+Shunt.Traffic;
      R:=(0.01+Age*(0.35+0.04*(J mod 5)))*P.Scale;
      X:=P.X+Cos(A)*R;
      Y:=P.Y+Sin(A)*R*0.45+Age*Age*0.15;
      Line(X,Y,X+Cos(A)*0.015*(1-U)*P.Scale,Y+Sin(A)*0.015*(1-U)*P.Scale,
      Mix(RGB(255,204,123),RGB(77,94,103),U),0.003*(1-U)*P.Scale);
    end;
  end;
end;
end.
