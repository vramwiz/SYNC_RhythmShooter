unit RhythmOrbitGuide;
// 保存済み軌道の未来線と音への反応を絶対時刻で読む。計画・採用音・カメラを変更しない。
interface
uses RhythmOrbitPlan,RhythmOrbitTypes;
const
  ORBIT_GUIDE_STEPS=288;
  ORBIT_MARKER_LIMIT=128;
type
  TOrbitVisualState=record
    Horizon,Density,Energy,Pulse:Double;
  end;
  TOrbitGuideSample=record
    Time,Ahead,Opacity:Double;
    P:TOrbitPoint;
    Leg:Integer;
  end;
function OrbitVisualState(Plan:TOrbitPlan;Time:Double):TOrbitVisualState;
// 同じCursorAtを使うため、表示した未来位置を後の自機がそのまま通る。
function OrbitGuideAt(Plan:TOrbitPlan;Time,Horizon,Fraction:Double):TOrbitGuideSample;
function OrbitMarkerOpacity(Ahead,Horizon:Double):Double;
implementation
uses System.Math;
function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);Result:=U*U*(3-2*U);end;
function OrbitVisualState(Plan:TOrbitPlan;Time:Double):TOrbitVisualState;
var Hit,I:Integer;N:TOrbitTap;Delta,Weight,Count,Power:Double;
begin
  Result:=Default(TOrbitVisualState);
  if (Plan=nil) or (Plan.Count=0) then Exit;
  Hit:=Plan.Before(Time);Count:=0;Power:=0;
  for I:=Max(0,Hit-32) to Min(Plan.Count-1,Hit+32) do begin
    N:=Plan.Taps[I];Delta:=N.Time-Time;
    if Abs(Delta)<2 then begin Weight:=(1+Cos(Pi*Delta/2))*0.5;Count:=Count+Weight;Power:=Power+Weight*N.Strength;end;
  end;
  Result.Density:=EnsureRange(Count/12,0.0,1.0);
  if Count>0 then Result.Energy:=EnsureRange(Power/Count,0.0,1.0);
  for I:=Hit downto Max(0,Hit-12) do begin
    Delta:=Time-Plan.Taps[I].Time;if Delta>0.8 then Break;
    // 反応光は実際の採用音の後だけ。先読みの密度は装飾の構図にのみ使う。
    if Delta>=0 then Result.Pulse:=Result.Pulse+Exp(-Delta*9)*(0.25+Plan.Taps[I].Strength*0.75);
  end;
  Result.Pulse:=EnsureRange(Result.Pulse,0.0,1.4);
  Result.Horizon:=Min(Max(0.0,Plan.SoundEnd-Time),5.6+1.2*(1-Result.Density));
end;
function OrbitGuideAt(Plan:TOrbitPlan;Time,Horizon,Fraction:Double):TOrbitGuideSample;
var U:Double;
begin
  U:=EnsureRange(Fraction,0.0,1.0);Result.Ahead:=Max(0.0,Horizon)*U;Result.Time:=Time+Result.Ahead;
  Result.P:=Plan.CursorAt(Result.Time);Result.Leg:=Plan.LegAt(Result.Time);
  Result.Opacity:=0.065+0.80*Power(1-U,1.5);
end;
function OrbitMarkerOpacity(Ahead,Horizon:Double):Double;
begin
  if (Ahead<0) or (Horizon<=0) or (Ahead>Horizon) then Exit(0);
  Result:=Smooth(1-Ahead/Horizon);
end;
end.
