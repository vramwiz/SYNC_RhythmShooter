unit RhythmRushPlan;
// 音に固定した接触・反撃・弾道を絶対時刻で評価する。ワールドの右・上が正。
interface
uses System.Types;

const
  RushMaxHealth=5;
  RushRecoveryHalfSpan=0.29;

type
  TRushMode=(rmStreet,rmCrowd,rmAir,rmChase);
  TRushMove=(raPunch,raKick,raLaunch,raAirPunch,raAirKick,raOrb,raGuard,
    raDodge,raCounter,raThrow,raSlam,raSpecial,raCrash,raHurt);
  TRushThreat=(rtFist,rtKick,rtWeapon,rtLeap,rtOrb,rtRush,rtSweep,rtGrab);
  TRushStage=record
    StartTime,X,Speed:Double;
    Mode:TRushMode;
    Level,Theme,Boss:Integer;
  end;
  TRushCue=record
    Time,Power,Flight:Double;
    Move:TRushMove;
    Foe,Cause:Integer; // Cause は集団戦で飛ばされた敵の番号。それ以外は -1。
    // 以下は読み込み時に再現する演出情報。保存形式には追加しない。
    Health:Integer;
    Recovery,RecoveryHop:Boolean;
  end;
  TRushFoe=record
    First,Last,Kind,Side:Integer;
    Boss:Boolean;
  end;
  TRushArc=record
    First,Last:Integer;
    Height:Double;
  end;

  TRushPlan=class
  public
    Duration,Finish:Double;
    Stages:TArray<TRushStage>;
    Cues:TArray<TRushCue>;
    Foes:TArray<TRushFoe>;
    Arcs:TArray<TRushArc>;
  private
    function CanRecover(Index:Integer;out Hop:Boolean):Boolean;
    procedure FitProjectiles;
  public
    procedure ArrangeHealth;
    function StageAt(Time:Double):Integer;
    function CueFrom(Time:Double):Integer;
    function ArcAt(Time:Double):Integer;
    function FoeFromCue(Index:Integer):Integer;
    function Hero(Time:Double):TPointF;
    function Health(Time:Double):Integer;
    function Enemy(Index:Integer;Time:Double):TPointF;
    function Contact(Index:Integer):TPointF;
    function Impact(Index:Integer):TPointF;
    function Incoming(Index:Integer):TPointF;
    function Projectile(Index:Integer;Time:Double):TPointF;
    function Threat(Index:Integer):TRushThreat;
    function Entry(Index:Integer):Double;
    function BodySize(Index:Integer):Double;
    function MoveAt(Time:Double):Integer;
    function CrowdExtras(Index:Integer):Integer;
    function CrowdEnemy(Index,Slot:Integer;Time:Double):TPointF;
  end;

function RushMix(A,B,U:Double):Double;
function RushEase(U:Double):Double;
function RushBreadth(Kind:Integer):Double;
function Defensive(Move:TRushMove):Boolean;
function Kicking(Move:TRushMove):Boolean;
function Windup(Move:TRushMove):Double;

implementation
uses System.Math;

function RushMix(A,B,U:Double):Double;
begin
  Result:=A+(B-A)*U;
end;

function RushEase(U:Double):Double;
begin
  U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function RushBreadth(Kind:Integer):Double;
const Builds:array[0..5] of Double=(1.0,0.76,1.30,0.94,0.82,1.19);
begin
  Result:=Builds[Kind];
end;

function Defensive(Move:TRushMove):Boolean;
begin
  Result:=Move in [raGuard,raDodge,raHurt];
end;

function Kicking(Move:TRushMove):Boolean;
begin
  Result:=Move in [raKick,raAirKick,raSlam];
end;

function Windup(Move:TRushMove):Double;
begin
  case Move of
    raThrow,raSpecial:Result:=0.26;
    raGuard,raDodge,raHurt:Result:=0.21;
    raOrb:Result:=0.11;
    else Result:=0.16;
  end;
end;

function TRushPlan.StageAt(Time:Double):Integer;
var Hi,M:Integer;
begin
  Result:=0;
  Hi:=High(Stages);
  while Result<Hi do begin
    M:=(Result+Hi+1) div 2;
    if Stages[M].StartTime<=Time then Result:=M else Hi:=M-1;
  end;
end;

function TRushPlan.CueFrom(Time:Double):Integer;
var Hi,M:Integer;
begin
  Result:=0;
  Hi:=Length(Cues);
  while Result<Hi do begin
    M:=(Result+Hi) div 2;
    if Cues[M].Time<Time then Result:=M+1 else Hi:=M;
  end;
end;

function TRushPlan.FoeFromCue(Index:Integer):Integer;
var Hi,M:Integer;
begin
  Result:=0;
  Hi:=Length(Foes);
  while Result<Hi do begin
    M:=(Result+Hi) div 2;
    if Foes[M].Last<Index then Result:=M+1 else Hi:=M;
  end;
end;

function TRushPlan.ArcAt(Time:Double):Integer;
var Lo,Hi,M:Integer;
begin
  Lo:=0;
  Hi:=Length(Arcs);
  while Lo<Hi do begin
    M:=(Lo+Hi) div 2;
    if Cues[Arcs[M].First].Time<=Time then Lo:=M+1 else Hi:=M;
  end;
  Result:=Lo-1;
  if (Result>=0) and (Time>Cues[Arcs[Result].Last].Time) then Result:=-1;
end;

function TRushPlan.Hero(Time:Double):TPointF;
var I,J:Integer; A:TRushStage; Limit,Span,U,V0,V1,Start,Age:Double;
begin
  Time:=EnsureRange(Time,0.0,Finish);
  I:=StageAt(Time);
  A:=Stages[I];
  Limit:=Finish;
  V1:=0;
  if I<High(Stages) then begin
    Limit:=Stages[I+1].StartTime;
    V1:=Min(A.Speed,Stages[I+1].Speed);
  end;
  V0:=A.Speed;
  if I>0 then V0:=Min(A.Speed,Stages[I-1].Speed);
  Span:=Limit-A.StartTime;
  U:=(Time-A.StartTime)/Span;
  // 隣の区間と位置・境界速度を共有し、足を止める乱戦から追撃へ連続する。
  Result:=PointF(A.X+Span*(A.Speed*RushEase(U)+V0*U*Sqr(1-U)-V1*Sqr(U)*(1-U)),0);
  if A.Mode=rmChase then Result.X:=Result.X+Min(0.62,Span*0.073)*Sin(8*Pi*U)*Sqr(Sin(Pi*U));
  // 保存した区間座標から描画用の走行距離を求める。旧計画にも同じ速度を適用する。
  Result.X:=Result.X*2;
  J:=ArcAt(Time);
  if J>=0 then begin
    Start:=Cues[Arcs[J].First].Time;
    U:=(Time-Start)/(Cues[Arcs[J].Last].Time-Start);
    Result.Y:=4*Arcs[J].Height*U*(1-U);
    Exit;
  end;
  J:=CueFrom(Time-RushRecoveryHalfSpan);
  while (J<Length(Cues)) and (Cues[J].Time<=Time+RushRecoveryHalfSpan) do begin
    if Cues[J].RecoveryHop then begin
      Age:=(Time-Cues[J].Time)/RushRecoveryHalfSpan;
      Result.Y:=0.94*Max(0.0,1-Sqr(Age));
      Exit;
    end;
    Inc(J);
  end;
end;

function TRushPlan.Health(Time:Double):Integer;
var I:Integer;
begin
  I:=CueFrom(Time);
  if (I<Length(Cues)) and (Cues[I].Time=Time) then Exit(Cues[I].Health);
  if I>0 then Exit(Cues[I-1].Health);
  Result:=RushMaxHealth;
end;

function TRushPlan.CanRecover(Index:Integer;out Hop:Boolean):Boolean;
var T:Double; I:Integer;
begin
  T:=Cues[Index].Time;
  Hop:=False;
  if (T+RushRecoveryHalfSpan>Finish) or (Cues[Index].Move in [raGuard,raDodge,raHurt,raSlam,raCrash]) then
    Exit(False);
  if ArcAt(T)>=0 then Exit(Hero(T).Y>=0.72);
  // 既存の空中コンボと回復用のジャンプを重ねない。
  if (ArcAt(T-RushRecoveryHalfSpan)>=0) or (ArcAt(T+RushRecoveryHalfSpan)>=0) then Exit(False);
  I:=CueFrom(T-RushRecoveryHalfSpan);
  while (I<Length(Cues)) and (Cues[I].Time<=T+RushRecoveryHalfSpan) do begin
    if (Cues[I].Move in [raSlam,raCrash,raGuard,raDodge,raHurt]) or (ArcAt(Cues[I].Time)>=0) then Exit(False);
    Inc(I);
  end;
  Hop:=True;
  Result:=True;
end;

procedure TRushPlan.ArrangeHealth;
var I,Hp:Integer; T,NextHit,RecoverAfter:Double; Hop,CanHit:Boolean;
begin
  // 保存済みの譜面の音時刻と敵の順番から、被弾と回復を再現する。
  for I:=0 to High(Cues) do begin
    Cues[I].Recovery:=False;
    Cues[I].RecoveryHop:=False;
  end;
  Hp:=RushMaxHealth;
  NextHit:=1.6;
  RecoverAfter:=0;
  for I:=0 to High(Cues) do begin
    T:=Cues[I].Time;
    if (Hp<=RushMaxHealth-2) and (T>=RecoverAfter) and CanRecover(I,Hop) then begin
      Cues[I].Recovery:=True;
      Cues[I].RecoveryHop:=Hop;
      Inc(Hp,2);
      NextHit:=Max(NextHit,T+1.0);
    end;
    CanHit:=(Hp>1) and (T>=NextHit) and (ArcAt(T)<0) and
      (I<Foes[Cues[I].Foe].Last) and (Cues[I+1].Time-T>=0.17) and
      (not Defensive(Cues[I+1].Move)) and
      (Cues[I].Move in [raPunch,raKick,raGuard,raDodge,raHurt]);
    if CanHit and (I>0) then CanHit:=(T-Cues[I-1].Time>=0.15) and not Defensive(Cues[I-1].Move);
    if CanHit then begin
      Cues[I].Move:=raHurt;
      Cues[I].Flight:=0;
      Dec(Hp);
      NextHit:=T+4.0;
      RecoverAfter:=T+1.15;
    end else if Cues[I].Move=raHurt then
      Cues[I].Move:=raGuard;
    Cues[I].Health:=Hp;
  end;
  FitProjectiles;
end;

function TRushPlan.BodySize(Index:Integer):Double;
const Sizes:array[0..5] of Double=(1.00,0.86,1.23,0.99,0.92,1.06);
  BossSizes:array[0..5] of Double=(1.68,1.22,1.43,1.28,1.35,1.95);
var F:TRushFoe;
begin
  F:=Foes[Index];
  if F.Boss then Result:=BossSizes[F.Kind] else Result:=Sizes[F.Kind];
end;

function TRushPlan.Entry(Index:Integer):Double;
var F:TRushFoe; A:TRushCue; Lead:Double;
begin
  F:=Foes[Index];
  A:=Cues[F.First];
  Lead:=1.12+F.Kind*0.095;
  if F.Boss then Lead:=2.15;
  Result:=Max(0.0,A.Time-Max(Lead,A.Flight+0.37));
end;

function TRushPlan.Threat(Index:Integer):TRushThreat;
const Mob:array[0..5] of TRushThreat=(rtFist,rtRush,rtKick,rtWeapon,rtLeap,rtOrb);
  Boss:array[0..5] of TRushThreat=(rtSweep,rtKick,rtWeapon,rtGrab,rtLeap,rtOrb);
var F:TRushFoe;
begin
  F:=Foes[Cues[Index].Foe];
  if F.Boss then Result:=Boss[F.Kind] else Result:=Mob[F.Kind];
  if (Result=rtOrb) and Defensive(Cues[Index].Move) and (Cues[Index].Flight=0) then Result:=rtFist;
end;

function TRushPlan.Contact(Index:Integer):TPointF;
var A:TRushCue; F:TRushFoe; HeroPoint:TPointF; Range,Size:Double;
begin
  A:=Cues[Index];
  F:=Foes[A.Foe];
  if A.Move=raCrash then begin
    Result:=Enemy(A.Cause,A.Time);
    Result.X:=Result.X+F.Side*0.25;
    Exit;
  end;
  HeroPoint:=Hero(A.Time);
  Size:=BodySize(A.Foe);
  Range:=0.90+Size*0.13;
  if Kicking(A.Move) then Range:=Range+0.20;
  if A.Move in [raThrow,raCounter] then Range:=Range-0.18;
  if A.Move=raOrb then begin
    if (not F.Boss) and (ArcAt(A.Time)<0) and (Cues[F.First].Move=raOrb) and
      (Cues[F.Last].Move=raOrb) then Range:=2.45+F.Kind*0.14
    else Range:=Range+0.12;
  end;
  if Defensive(A.Move) and (Threat(Index)=rtGrab) then Range:=Range-0.24;
  Result:=PointF(HeroPoint.X+F.Side*Range,HeroPoint.Y);
  if A.Move=raSlam then Result.Y:=0;
end;

function TRushPlan.Enemy(Index:Integer;Time:Double):TPointF;
var F:TRushFoe; A,B:TRushCue; P,Q:TPointF; I:Integer; U,T,Distance:Double;
begin
  F:=Foes[Index];
  A:=Cues[F.First];
  B:=Cues[F.Last];
  if Time<A.Time then begin
    Result:=Contact(F.First);
    T:=Entry(Index);
    U:=RushEase((Time-T)/Max(1E-6,A.Time-T));
    Distance:=2.65+F.Kind*0.17;
    if F.Boss then Distance:=4.35;
    Result.X:=Result.X+F.Side*Distance*(1-U);
    if (F.Side<0) and (A.Move<>raCrash) then
      Result.X:=Result.X+Hero(Time).X-Hero(A.Time).X;
    Result.Y:=Result.Y*U;
    if F.Kind=4 then Result.Y:=Result.Y+0.92*4*U*(1-U);
    Exit;
  end;
  if Time>=B.Time then begin
    Result:=Contact(F.Last);
    T:=Time-B.Time;
    Distance:=2.90+B.Power*1.7;
    if B.Move in [raSlam,raThrow] then Distance:=Distance*0.49;
    if B.Move=raSpecial then Distance:=Distance*1.25;
    Result.X:=Result.X+F.Side*Distance*(1-Exp(-2.7*T));
    if B.Move=raSlam then Exit;
    Distance:=1.15+B.Power;
    if B.Move=raThrow then Distance:=Distance+1.65;
    Result.Y:=Max(0.0,Result.Y+Distance*T-7.8*Sqr(T));
    Exit;
  end;
  I:=EnsureRange(CueFrom(Time),F.First+1,F.Last);
  A:=Cues[I-1];
  B:=Cues[I];
  P:=Contact(I-1);
  Q:=Contact(I);
  U:=(Time-A.Time)/(B.Time-A.Time);
  T:=Sin(Pi*U)*Min(1.0,(B.Time-A.Time)*2.2);
  Distance:=0.18;
  if Stages[StageAt(A.Time)].Mode=rmChase then Distance:=0.98;
  if Defensive(A.Move) then Distance:=0.09;
  Result:=PointF(RushMix(P.X,Q.X,U)+F.Side*Distance*T,RushMix(P.Y,Q.Y,U));
  if ArcAt(Time)>=0 then Result.Y:=Result.Y+0.28*T
  else if Defensive(B.Move) and (Threat(I)=rtLeap) then Result.Y:=Result.Y+0.77*T;
end;

function TRushPlan.Impact(Index:Integer):TPointF;
var A:TRushCue; Size,Height:Double;
begin
  A:=Cues[Index];
  Size:=BodySize(A.Foe);
  Height:=0.72;
  if A.Move in [raLaunch,raAirPunch] then Height:=0.84;
  if A.Move in [raKick,raAirKick,raSlam] then Height:=0.53;
  if A.Move=raThrow then Height:=0.63;
  Result:=Contact(Index);
  Result.X:=Result.X-Foes[A.Foe].Side*Size*0.195*RushBreadth(Foes[A.Foe].Kind);
  Result.Y:=Result.Y+Size*Height;
end;

function TRushPlan.Incoming(Index:Integer):TPointF;
var H:TPointF; A:TRushCue; F:TRushFoe;
begin
  A:=Cues[Index];
  F:=Foes[A.Foe];
  H:=Hero(A.Time);
  Result:=PointF(H.X+F.Side*0.27,H.Y+0.81);
  if A.Move=raDodge then Result.Y:=H.Y+1.41;
  if Threat(Index)=rtSweep then Result.Y:=H.Y+0.43;
  if A.Move=raHurt then begin
    Result.X:=H.X-F.Side*0.13;
    if Threat(Index)<>rtSweep then Result.Y:=H.Y+0.69;
  end;
end;

function TRushPlan.Projectile(Index:Integer;Time:Double):TPointF;
var A:TRushCue; F:TRushFoe; Start,Finish:TPointF; U,Launch:Double;
begin
  A:=Cues[Index];
  F:=Foes[A.Foe];
  Launch:=A.Time-A.Flight;
  if Defensive(A.Move) then begin
    Start:=Enemy(A.Foe,Launch);
    Start:=PointF(Start.X-F.Side*0.43,Start.Y+BodySize(A.Foe)*0.74);
    Finish:=Incoming(Index);
  end else begin
    Start:=Hero(Launch);
    Start:=PointF(Start.X+F.Side*0.41,Start.Y+0.76);
    Finish:=Impact(Index);
  end;
  U:=EnsureRange((Time-Launch)/Max(A.Flight,1E-6),0.0,1.0);
  Result:=PointF(RushMix(Start.X,Finish.X,U),RushMix(Start.Y,Finish.Y,U));
end;

procedure TRushPlan.FitProjectiles;
var I,J,Side:Integer; A:TRushCue; Source,Dest:TPointF;
begin
  for I:=0 to High(Cues) do begin
    A:=Cues[I];
    if A.Flight=0 then Continue;
    Side:=Foes[A.Foe].Side;
    if Defensive(A.Move) then begin
      Dest:=Incoming(I);
      Side:=-Side;
    end else Dest:=Impact(I);
    // 走行速度を上げても、弾が手元から相手側へ向かうようにする。
    for J:=0 to 7 do begin
      Source:=Projectile(I,A.Time-Cues[I].Flight);
      if (Dest.X-Source.X)*Side>0.22 then Break;
      Cues[I].Flight:=Cues[I].Flight*0.68;
    end;
    Source:=Projectile(I,A.Time-Cues[I].Flight);
    if (Dest.X-Source.X)*Side<=0.22 then Cues[I].Flight:=0;
    if (Cues[I].Flight=0) and (A.Move=raOrb) then Cues[I].Move:=raPunch;
  end;
end;

function TRushPlan.CrowdExtras(Index:Integer):Integer;
var S:TRushStage; A:TRushCue;
begin
  A:=Cues[Index];
  if (A.Move<>raSpecial) or Foes[A.Foe].Boss then Exit(0);
  S:=Stages[StageAt(A.Time)];
  if S.Mode<>rmCrowd then Exit(0);
  Result:=1+Ord(S.Level>=4);
end;

function TRushPlan.CrowdEnemy(Index,Slot:Integer;Time:Double):TPointF;
var A:TRushCue; Age,Offset:Double;
begin
  A:=Cues[Index];
  Result:=Contact(Index);
  Age:=Time-A.Time;
  Offset:=0.55+Slot*0.51;
  if Age<0 then begin
    Offset:=Offset+1.32*RushEase(-Age/0.66);
    if Foes[A.Foe].Side<0 then Result.X:=Result.X+Hero(Time).X-Hero(A.Time).X;
  end
  else begin
    Offset:=Offset+(1.8+Slot*0.52)*(1-Exp(-3.1*Age));
    Result.Y:=Max(0.0,Result.Y+(2.0+Slot*0.68)*Age-6.2*Sqr(Age));
  end;
  Result.X:=Result.X+Foes[A.Foe].Side*Offset;
end;

function TRushPlan.MoveAt(Time:Double):Integer;
var I:Integer;
begin
  I:=CueFrom(Time);
  if (I<Length(Cues)) and (Time=Cues[I].Time) then Exit(I);
  if (I>0) and (Time-Cues[I-1].Time<0.115) and
    ((I=Length(Cues)) or (Time-Cues[I-1].Time<Cues[I].Time-Time)) then Exit(I-1);
  Result:=-1;
  if (I<Length(Cues)) and (Cues[I].Time-Time<=Windup(Cues[I].Move)) then Result:=I;
end;
end.
