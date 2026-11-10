unit RhythmOrbitTypes;
// 宇宙の世界座標と保存契約。画面座標や再生中の可変状態を持たない。
interface
uses RhythmAudio;
const
  ORBIT_MAX_EVENTS=100000;
  ORBIT_MAX_BODIES=1024;
  ORBIT_EFFECT_LIFE=0.65;
type
  TOrbitPoint=record X,Y:Double;end;
  TOrbitBody=record
    Center:TOrbitPoint;
    Show,Entry,Exit,Clear,Radius,RX,RY,Rotation,Phase,Speed:Double;
    Hue:Integer;
  end;
  TOrbitLeg=record
    Start,Finish:Double;
    // Kind: 0=周回、1=惑星間、2=導入、3=離脱、4=到着停止。同じ曲線を接触と未来線に使う。
    FromBody,ToBody,Kind:Integer;
    A,B,C,D:TOrbitPoint;
  end;
  TOrbitTap=record
    Time,Appear,Strength:Double;
    Source,Leg,Chain:Integer;
    P:TOrbitPoint;
  end;
  TOrbitCamera=record
    Center:TOrbitPoint;
    Span:Double;
  end;
  TOrbitData=record
    Duration,SoundEnd,EndTime:Double;
    Threshold,Weak,Tail,Version:Integer;
    IntroFinish,DepartStart,DepartFinish,ClearTime:Double;
    Events:TArray<TRhythmHit>;
    Bodies:TArray<TOrbitBody>;
    Legs:TArray<TOrbitLeg>;
    Taps:TArray<TOrbitTap>;
  end;
function OrbitPoint(X,Y:Double):TOrbitPoint;
function OrbitFinite(V:Double):Boolean;
function OrbitBodyAt(const Body:TOrbitBody;Angle:Double):TOrbitPoint;
function OrbitTangent(const Body:TOrbitBody;Angle:Double):TOrbitPoint;
function OrbitLegAt(const Data:TOrbitData;Index:Integer;Time:Double):TOrbitPoint;
function OrbitFade(Age:Double):Double;
implementation
uses System.Math;
function OrbitPoint(X,Y:Double):TOrbitPoint;
begin Result.X:=X;Result.Y:=Y;end;
function OrbitFinite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);end;
function OrbitBodyAt(const Body:TOrbitBody;Angle:Double):TOrbitPoint;
var X,Y,C,S:Double;
begin X:=Cos(Angle)*Body.RX;Y:=Sin(Angle)*Body.RY;
  C:=Cos(Body.Rotation);S:=Sin(Body.Rotation);
  Result:=OrbitPoint(Body.Center.X+X*C-Y*S,Body.Center.Y+X*S+Y*C);
end;
function OrbitTangent(const Body:TOrbitBody;Angle:Double):TOrbitPoint;
var X,Y,C,S:Double;
begin X:=-Sin(Angle)*Body.RX*Body.Speed;Y:=Cos(Angle)*Body.RY*Body.Speed;
  C:=Cos(Body.Rotation);S:=Sin(Body.Rotation);
  Result:=OrbitPoint(X*C-Y*S,X*S+Y*C);
end;
function OrbitLegAt(const Data:TOrbitData;Index:Integer;Time:Double):TOrbitPoint;
var L:TOrbitLeg;B:TOrbitBody;U,V:Double;
begin
  L:=Data.Legs[Index];
  if Time<=L.Start then Exit(L.A);
  if Time>=L.Finish then Exit(L.D);
  if L.Kind=4 then Exit(L.D);
  if L.Kind=0 then begin
    B:=Data.Bodies[L.FromBody];Exit(OrbitBodyAt(B,B.Phase+(Time-B.Entry)*B.Speed));
  end;
  U:=(Time-L.Start)/(L.Finish-L.Start);V:=1-U;
  Result:=OrbitPoint(V*V*V*L.A.X+3*V*V*U*L.B.X+3*V*U*U*L.C.X+U*U*U*L.D.X,
    V*V*V*L.A.Y+3*V*V*U*L.B.Y+3*V*U*U*L.C.Y+U*U*U*L.D.Y);
end;
function OrbitFade(Age:Double):Double;
var U:Double;
begin
  if (Age<0) or (Age>=ORBIT_EFFECT_LIFE) then Exit(0);
  U:=EnsureRange((Age-0.018)/(ORBIT_EFFECT_LIFE-0.018),0.0,1.0);
  Result:=1-U*U*(3-2*U);
end;
end.
