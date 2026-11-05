unit RhythmJumpPlan;
// 音と足の接触を結ぶワールド座標（右・上が正）。全評価は秒単位の絶対時刻から行う。
interface
uses System.Types;

const
  JumpMinBeatGap=0.48;
  JumpEnemyRadius=0.28;
  JumpRollRadius=0.32;
  JumpRollSpeed=7.4;

type
  TJumpLanding=(jlGround,jlStomp,jlSpring,jlBoss,jlRoll);
  TJumpEnemy=(jeFixed,jeGround,jeFlying); // jeFixed は旧計画の踏みつけと敵のいない地点。
  TJumpStage=record
    StartTime:Double;
    Vertical:Boolean;
    Level,Theme,Boss:Integer; // Boss=-1 は通常区間。
  end;
  TJumpNode=record
    Time,X,Y,Width,MoveX,MoveY:Double;
    SolidFrom,SolidUntil:Double; // 一方向足場の接地が有効な時間。
    Landing:TJumpLanding;
    Variant:Integer; // 敵の種類またはボスの弱点番号。
    Enemy:TJumpEnemy;
  end;
  TJumpLeg=record
    Takeoff,Height:Double; // Height=0 は接地したまま走る。
    Attack:Integer; // 0は攻撃なし。1から3は攻撃の描画形状。
  end;
  TJumpBeat=record
    Time,Strength:Double;
    Node:Integer; // -1 は足の接触を割り当てなかったアクセント。
  end;
  TJumpBoss=record
    FirstNode,LastNode,Variant:Integer;
  end;
  TJumpRoll=record
    FirstNode,LastNode:Integer;
    Hits:TArray<Double>;
  end;
  TJumpHazard=record
    StartTime,EndTime,X,Y,Height:Double;
    Kind:Integer;
  end;

  TJumpPlan=class
  public
    Duration:Double;
    Stages:TArray<TJumpStage>;
    Nodes:TArray<TJumpNode>;
    Legs:TArray<TJumpLeg>;
    Beats:TArray<TJumpBeat>;
    Bosses:TArray<TJumpBoss>;
    Rolls:TArray<TJumpRoll>;
    function StageAt(Time:Double):Integer;
    function NodeAt(Time:Double):Integer;
    function BeatFrom(Time:Double):Integer;
    function Foot(Time:Double):TPointF;
    function Platform(Index:Integer;Time:Double):TPointF;
    function EnemyTop(Index:Integer;Time:Double):TPointF;
    function RollAtNode(Index:Integer):Integer;
    function RollCenter(Index:Integer;Time:Double):TPointF;
    function RollEnemyTop(Index:Integer;HitTime:Double):TPointF;
    function BossAt(Time:Double):Integer;
    function BossCore(Index:Integer;Time:Double):TPointF;
    function Hazard(Index:Integer):TJumpHazard;
    function EarlierLanding(LegIndex,DeckIndex:Integer;out Time,Side:Double):Boolean;
  end;

function JumpBlend(A,B,U:Double):Double;
function JumpWeakPoint(Variant,Spot:Integer):TPointF;

implementation
uses System.Math;

function JumpBlend(A,B,U:Double):Double;
begin
  Result:=A+(B-A)*U;
end;

function JumpWeakPoint(Variant,Spot:Integer):TPointF;
begin
  case Spot of
    0:Result:=PointF(0.62,1.17);
    1:Result:=PointF(-0.06,1.31);
    else Result:=PointF(-0.74,1.11);
  end;
  Result.X:=Result.X*(1+Variant*0.15);
  Result.Y:=Result.Y+Variant*0.11;
end;

function TJumpPlan.StageAt(Time:Double):Integer;
var Lo,Hi,Mid:Integer;
begin
  Lo:=0;
  Hi:=High(Stages);
  while Lo<Hi do begin
    Mid:=(Lo+Hi+1) div 2;
    if Stages[Mid].StartTime<=Time then Lo:=Mid else Hi:=Mid-1;
  end;
  Result:=Lo;
end;

function TJumpPlan.NodeAt(Time:Double):Integer;
var Lo,Hi,Mid:Integer;
begin
  Lo:=0;
  Hi:=High(Nodes);
  while Lo<Hi do begin
    Mid:=(Lo+Hi+1) div 2;
    if Nodes[Mid].Time<=Time then Lo:=Mid else Hi:=Mid-1;
  end;
  Result:=Lo;
end;

function TJumpPlan.BeatFrom(Time:Double):Integer;
var Lo,Hi,Mid:Integer;
begin
  Lo:=0;
  Hi:=Length(Beats);
  while Lo<Hi do begin
    Mid:=(Lo+Hi) div 2;
    if Beats[Mid].Time<Time then Lo:=Mid+1 else Hi:=Mid;
  end;
  Result:=Lo;
end;

function DeckHeight(const N:TJumpNode):Double;
begin
  Result:=N.Y;
  case N.Landing of
    jlStomp:
      case N.Enemy of
        jeFixed:Result:=Result-0.32;
        jeGround:Result:=Result-2*JumpEnemyRadius;
      end;
    jlBoss:Result:=Result-0.56;
    jlRoll:Result:=Result-2*JumpRollRadius;
  end;
end;

function TJumpPlan.Platform(Index:Integer;Time:Double):TPointF;
var N:TJumpNode; Wave,Top:Double;
begin
  N:=Nodes[Index];
  Wave:=Sin((Time-N.Time)*2.6);
  Top:=DeckHeight(N);
  Result:=PointF(N.X+N.MoveX*Wave,Top+N.MoveY*Wave);
end;

function TJumpPlan.EnemyTop(Index:Integer;Time:Double):TPointF;
var N:TJumpNode; Wave:Double;
begin
  N:=Nodes[Index];
  if N.Enemy=jeFixed then begin
    Result:=Platform(Index,Time);
    Result.Y:=Result.Y+0.32;
    Exit;
  end;
  Result:=PointF(N.X,N.Y);
  if N.Enemy=jeFlying then begin
    // 踏む時刻を波の原点に置き、足と敵の上端を同じ座標に合わせる。
    Wave:=Sin((Time-N.Time)*3.4);
    if Odd(N.Variant) then Result.Y:=Result.Y+0.18*Wave
    else Result.X:=Result.X+0.30*Wave;
  end;
end;

function TJumpPlan.RollAtNode(Index:Integer):Integer;
var Lo,Hi,Mid:Integer;
begin
  Lo:=0;
  Hi:=Length(Rolls);
  while Lo<Hi do begin
    Mid:=(Lo+Hi) div 2;
    if Rolls[Mid].LastNode<Index then Lo:=Mid+1 else Hi:=Mid;
  end;
  if (Lo<Length(Rolls)) and (Rolls[Lo].FirstNode<=Index) then Exit(Lo);
  Result:=-1;
end;

function TJumpPlan.RollCenter(Index:Integer;Time:Double):TPointF;
var N:TJumpNode;
begin
  N:=Nodes[Rolls[Index].FirstNode];
  Result:=PointF(N.X+JumpRollSpeed*Max(0.0,Time-N.Time),N.Y-JumpRollRadius);
end;

function TJumpPlan.RollEnemyTop(Index:Integer;HitTime:Double):TPointF;
begin
  Result:=RollCenter(Index,HitTime);
  Result.X:=Result.X+JumpRollRadius+JumpEnemyRadius;
  Result.Y:=Result.Y-JumpRollRadius+2*JumpEnemyRadius;
end;

function TJumpPlan.Foot(Time:Double):TPointF;
var I:Integer; A,B:TJumpNode; Leg:TJumpLeg; P:TPointF; U:Double;
begin
  I:=NodeAt(Time);
  A:=Nodes[I];
  if (I=High(Nodes)) or (Time<=A.Time) then Exit(PointF(A.X,A.Y));
  B:=Nodes[I+1];
  Leg:=Legs[I];
  P:=Platform(I,Leg.Takeoff);
  if A.Landing in [jlStomp,jlBoss,jlRoll] then P:=PointF(A.X,A.Y);
  if Time<Leg.Takeoff then Exit(Platform(I,Time));
  U:=(Time-Leg.Takeoff)/(B.Time-Leg.Takeoff);
  Result:=PointF(JumpBlend(P.X,B.X,U),
    JumpBlend(P.Y,B.Y,U)+4*Leg.Height*U*(1-U));
end;

function TJumpPlan.BossAt(Time:Double):Integer;
var B:TJumpBoss;
begin
  Result:=Stages[StageAt(Time)].Boss;
  if Result<0 then Exit;
  B:=Bosses[Result];
  if (Time<Nodes[B.FirstNode].Time) or (Time>Nodes[B.LastNode].Time) then Result:=-1;
end;

function TJumpPlan.BossCore(Index:Integer;Time:Double):TPointF;
var B:TJumpBoss; A,C:TJumpNode; P,Q:TPointF; I:Integer; U:Double;
begin
  B:=Bosses[Index];
  I:=EnsureRange(NodeAt(Time),B.FirstNode,B.LastNode);
  A:=Nodes[I];
  P:=JumpWeakPoint(B.Variant,A.Variant);
  Result:=PointF(A.X-P.X,A.Y-P.Y);
  if I=B.LastNode then Exit;
  C:=Nodes[I+1];
  Q:=JumpWeakPoint(B.Variant,C.Variant);
  U:=EnsureRange((Time-A.Time)/(C.Time-A.Time),0.0,1.0);
  Result:=PointF(JumpBlend(Result.X,C.X-Q.X,U),JumpBlend(Result.Y,C.Y-Q.Y,U));
end;

function TJumpPlan.Hazard(Index:Integer):TJumpHazard;
var Leg:TJumpLeg; Span:Double; A,B,P:TPointF;
begin
  Result:=Default(TJumpHazard);
  Leg:=Legs[Index];
  if Leg.Attack=0 then Exit;
  Span:=Nodes[Index+1].Time-Leg.Takeoff;
  Result.StartTime:=Leg.Takeoff+Span*0.32;
  Result.EndTime:=Leg.Takeoff+Span*0.68;
  A:=Foot(Result.StartTime);
  B:=Foot(Result.EndTime);
  P:=Foot((Result.StartTime+Result.EndTime)*0.5);
  Result.X:=P.X;
  Result.Height:=Min(0.54,Leg.Height*0.76);
  // 放物線はこの区間で凹。両端の足より下なら発動中も足を横切らない。
  Result.Y:=Min(A.Y,B.Y)-0.18-Result.Height;
  Result.Kind:=Leg.Attack;
end;
function TJumpPlan.EarlierLanding(LegIndex,DeckIndex:Integer;out Time,Side:Double):Boolean;
var
  L:TJumpLeg;
  A,B,D:TJumpNode;
  Span,StartX,StartY,DeckY,Lo,Hi,U,Center:Double;
  I:Integer;
  P:TPointF;

  function Relative(Fraction:Double):Double;
  begin
    Result:=JumpBlend(StartY,B.Y,Fraction)+4*L.Height*Fraction*(1-Fraction)-
      DeckY-D.MoveY*Sin((L.Takeoff+Span*Fraction-D.Time)*2.6);
  end;

begin
  Result:=False;
  L:=Legs[LegIndex];
  if (L.Height=0) or (DeckIndex=LegIndex+1) then Exit;
  A:=Nodes[LegIndex];
  B:=Nodes[LegIndex+1];
  D:=Nodes[DeckIndex];
  if D.Enemy=jeFlying then Exit;
  P:=Platform(LegIndex,L.Takeoff);
  StartX:=P.X;
  StartY:=P.Y;
  if A.Landing in [jlStomp,jlBoss,jlRoll] then StartY:=A.Y;
  if (D.X+Abs(D.MoveX)+D.Width/2<Min(StartX,B.X)-0.10) or
    (D.X-Abs(D.MoveX)-D.Width/2>Max(StartX,B.X)+0.10) then Exit;
  Span:=B.Time-L.Takeoff;
  DeckY:=DeckHeight(D);
  if DeckY-Abs(D.MoveY)>Max(StartY,B.Y)+L.Height then Exit;
  if Relative(1)>=-1E-6 then Exit;
  // 高さ差は凹。頂点を求めてから、下降側だけの交点を二分探索する。
  Lo:=0;
  Hi:=1;
  for I:=1 to 18 do begin
    U:=(Lo+Hi)*0.5;
    if B.Y-StartY+4*L.Height*(1-2*U)-
      D.MoveY*2.6*Span*Cos((L.Takeoff+Span*U-D.Time)*2.6)>0 then Lo:=U
    else Hi:=U;
  end;
  Lo:=(Lo+Hi)*0.5;
  if Relative(Lo)<=1E-6 then Exit;
  Hi:=1;
  for I:=1 to 18 do begin
    U:=(Lo+Hi)*0.5;
    if Relative(U)>0 then Lo:=U else Hi:=U;
  end;
  U:=(Lo+Hi)*0.5;
  Time:=L.Takeoff+U*Span;
  if (Time<D.SolidFrom) or (Time>D.SolidUntil) then Exit;
  Center:=D.X+D.MoveX*Sin((Time-D.Time)*2.6);
  Side:=Abs(JumpBlend(StartX,B.X,U)-Center);
  Result:=Side<D.Width*0.5+0.10;
end;
end.
