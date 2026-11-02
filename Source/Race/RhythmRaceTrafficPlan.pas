unit RhythmRaceTrafficPlan;
// 一般車の横経路を一度だけ決定する。描画時の自車位置には追従させない。
interface
uses RhythmRaceCrashMotion;
// 接近矩形が重なる全区間の自車包絡から、固定のすり抜け車線を逆算する。
procedure PlanTrafficLane(Plan:TRaceCrashMotion;var V:TCrashTraffic;Ordinal:Integer);
// 出現時のボス重複だけは独立進入車線＋1回の短い操舵へ変更する。
procedure EnsureTrafficTurn(Plan:TRaceCrashMotion;var V:TCrashTraffic);
implementation
uses System.Math;
procedure EnsureTrafficTurn(Plan:TRaceCrashMotion;var V:TCrashTraffic);
var Enter:Double;
begin
  if V.TurnFinish>V.TurnStart then Exit;
  Enter:=V.Pass-(Plan.HeroFront+V.HalfLength)/V.RelativeSpeed;
  V.TurnFinish:=Enter-0.025;V.TurnStart:=V.TurnFinish-0.22;
  if V.TurnStart<V.Spawn then begin V.TurnStart:=V.Spawn;V.TurnFinish:=V.Spawn;end;
end;
procedure PlanTrafficLane(Plan:TRaceCrashMotion;var V:TCrashTraffic;Ordinal:Integer);
var A,B,Low,High,Margin,Span:Double;
begin
  A:=Max(V.Spawn,V.Pass-(Plan.HeroFront+V.HalfLength)/V.RelativeSpeed);
  B:=Min(V.Clear,V.Pass+(Plan.HeroBack+V.HalfLength)/V.RelativeSpeed);
  Plan.LaneBounds(A,B,Low,High);Margin:=Plan.HeroWidth+V.Width+V.Gap;
  if V.Side>0 then V.NearLane:=High+Margin else V.NearLane:=Low-Margin;
  V.TurnStart:=V.Spawn;V.TurnFinish:=V.Spawn;
  if Ordinal mod 5=0 then begin
    EnsureTrafficTurn(Plan,V);Span:=0.18+0.03*(Ordinal mod 4);
    V.TurnStart:=V.TurnFinish-Span;
    if V.TurnStart<V.Spawn then begin V.TurnStart:=V.Spawn;V.TurnFinish:=V.Spawn;end;
  end;
  if V.TurnFinish<=V.TurnStart then V.FarLane:=V.NearLane;
  V.FarLane:=EnsureRange(V.FarLane,-1+V.Width,1-V.Width);
end;
end.
