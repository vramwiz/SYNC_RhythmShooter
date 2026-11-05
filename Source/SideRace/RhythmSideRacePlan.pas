unit RhythmSideRacePlan;
// 車の位置、道路、接触点を絶対時刻で評価する。距離の単位は車体基準のワールド座標。
interface
uses System.Types;

const
  SideHeroHalf=0.96;
  SideFrontEntryGap=16.0;
  SideTruckHeightScale=1.50;

type
  TSideAction=(saFront,saRear,saBump,saRock,saLaunch,saLand,saRepair,
    saBossRam,saBossTire,saBossRoof,saBossDrop,saBossEscort,saBossClear);
  TSideDeck=(sdRoad,sdRamp,sdBridge,sdMoving);
  TSideStage=record
    Time,X,Speed:Double;
    Level,Theme:Integer;
  end;
  TSideCue=record
    Time,Power,Health:Double;
    Action:TSideAction;
    Car,Boss:Integer;
    Musical:Boolean;
  end;
  TSideCar=record
    First,Last,Stride,Side,Kind:Integer;
  end;
  TSideBoss=record
    First,Last,Kind:Integer;
  end;
  TSideJump=record
    First,Last,Roof:Integer;
    Height,Ramp,Gap,Lift:Double;
    X0,X1:Double; // 準備／読込時に時刻と走行距離から再計算する。
  end;
  TSidePose=record
    Root:TPointF;
    Angle:Double;
  end;
  TSideRig=record
    Half,Roof,Rear:Double;
    Wheels,Finish:Integer;
  end;
  TSideRacePlan=class
  public
    Duration,Goal:Double;
    Stages:TArray<TSideStage>;
    Cues:TArray<TSideCue>;
    Cars:TArray<TSideCar>;
    Bosses:TArray<TSideBoss>;
    Jumps:TArray<TSideJump>;
    procedure IndexTrack;
    function StageAt(Time:Double):Integer;
    function CueFrom(Time:Double):Integer;
    function JumpAt(Time:Double):Integer;
    function BossAt(Time:Double):Integer;
    function Distance(Time:Double):Double;
    function Speed(Time:Double):Double;
    function Phase(Time:Double):Double;
    function BaseRoad(X:Double):Double;
    function Road(X,Time:Double;out Y:Double;out Deck:TSideDeck):Boolean;
    function Hero(Time:Double):TPointF;
    function HeroAngle(Time:Double):Double;
    function Health(Time:Double):Double;
    function CarCue(Index:Integer;Time:Double):Integer;
    function CarHalf(Index:Integer):Double;
    function CarPose(Index:Integer;Time:Double;EntryGap:Double=SideFrontEntryGap):TSidePose;
    function ChainCue(Index:Integer):Integer;
    function ChainCar(Index,Hit:Integer;Time:Double;EntryGap:Double=SideFrontEntryGap):TSidePose;
    function BossRig(Index:Integer):TSideRig;
    function BossPose(Index:Integer;Time:Double;EntryGap:Double=SideFrontEntryGap):TSidePose;
    function Contact(Index:Integer):TPointF;
  end;

function SideMix(A,B,U:Double):Double;
function SideEase(U:Double):Double;
function SideFrontEntryLead(EntryGap:Double):Double;
function SideBodyHit(Action:TSideAction):Boolean;

implementation
uses System.Math;

function SideMix(A,B,U:Double):Double;
begin
  Result:=A+(B-A)*U;
end;

function SideEase(U:Double):Double;
begin
  U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function SideFrontEntryLead(EntryGap:Double):Double;
begin
  // 接近区間を距離とともに伸ばして、広い画面でも前方車の速度を逆転させない。
  Result:=EntryGap/8.8;
end;

function SideBodyHit(Action:TSideAction):Boolean;
begin
  Result:=Action in [saBossRam,saBossTire,saBossClear];
end;

function TSideRacePlan.StageAt(Time:Double):Integer;
var Hi,M:Integer;
begin
  Result:=0;
  Hi:=High(Stages);
  while Result<Hi do begin
    M:=(Result+Hi+1) div 2;
    if Stages[M].Time<=Time then Result:=M else Hi:=M-1;
  end;
end;

function TSideRacePlan.CueFrom(Time:Double):Integer;
var Hi,M:Integer;
begin
  Result:=0;
  Hi:=Length(Cues);
  while Result<Hi do begin
    M:=(Result+Hi) div 2;
    if Cues[M].Time<Time then Result:=M+1 else Hi:=M;
  end;
end;

function TSideRacePlan.JumpAt(Time:Double):Integer;
var Lo,Hi,M:Integer;
begin
  Lo:=0;
  Hi:=Length(Jumps);
  while Lo<Hi do begin
    M:=(Lo+Hi) div 2;
    if Cues[Jumps[M].First].Time<=Time then Lo:=M+1 else Hi:=M;
  end;
  Result:=Lo-1;
  if (Result>=0) and (Time>Cues[Jumps[Result].Last].Time) then Result:=-1;
end;

function TSideRacePlan.BossAt(Time:Double):Integer;
var Lo,Hi,M:Integer;
begin
  Lo:=0;
  Hi:=Length(Bosses);
  while Lo<Hi do begin
    M:=(Lo+Hi) div 2;
    if Cues[Bosses[M].First].Time<=Time then Lo:=M+1 else Hi:=M;
  end;
  Result:=Lo-1;
  if (Result>=0) and (Time>Cues[Bosses[Result].Last].Time) then Result:=-1;
end;

function TSideRacePlan.Distance(Time:Double):Double;
var I:Integer; D,Span:Double;
begin
  Time:=EnsureRange(Time,0.0,Duration);
  I:=StageAt(Time);
  D:=Time-Stages[I].Time;
  Result:=Stages[I].X+Stages[I].Speed*D;
  if I<High(Stages) then begin
    Span:=Stages[I+1].Time-Stages[I].Time;
    Result:=Result+(Stages[I+1].Speed-Stages[I].Speed)*Sqr(D)/(2*Span);
  end;
end;

function TSideRacePlan.Speed(Time:Double):Double;
var I:Integer;
begin
  I:=StageAt(Time);
  Result:=Stages[I].Speed;
  if I<High(Stages) then
    Result:=SideMix(Result,Stages[I+1].Speed,
      EnsureRange((Time-Stages[I].Time)/(Stages[I+1].Time-Stages[I].Time),0.0,1.0));
end;

function TSideRacePlan.Phase(Time:Double):Double;
var U:Double;
begin
  U:=EnsureRange(Time/Goal,0.0,1.0);
  if U<0.23 then Exit(0);
  if U<0.47 then Exit(SideEase((U-0.23)/0.17));
  if U<0.75 then Exit(1+SideEase((U-0.47)/0.16));
  Result:=2+SideEase((U-0.75)/0.22);
end;

function TSideRacePlan.BaseRoad(X:Double):Double;
var Gain:Double;
begin
  Gain:=SideMix(0.46,1.0,EnsureRange(X/Max(1.0,Distance(Goal)),0.0,1.0));
  Result:=Gain*(0.65*Sin(X*0.062)+0.21*Sin(X*0.181));
end;

procedure TSideRacePlan.IndexTrack;
var I:Integer;
begin
  for I:=0 to High(Jumps) do begin
    Jumps[I].X0:=Distance(Cues[Jumps[I].First].Time);
    Jumps[I].X1:=Distance(Cues[Jumps[I].Last].Time);
  end;
end;

function TSideRacePlan.Road(X,Time:Double;out Y:Double;out Deck:TSideDeck):Boolean;
var Lo,Hi,M:Integer; J:TSideJump; Start,Finish,GapStart,GapEnd,DeckEnd,U:Double;
begin
  Y:=BaseRoad(X);
  Deck:=sdRoad;
  Result:=True;
  Lo:=0;
  Hi:=Length(Jumps);
  while Lo<Hi do begin
    M:=(Lo+Hi) div 2;
    if Jumps[M].X0-4.6<=X then Lo:=M+1 else Hi:=M;
  end;
  if Lo=0 then Exit;
  J:=Jumps[Lo-1];
  Start:=J.X0;
  Finish:=J.X1;
  if X<=Start then begin
    Y:=Y+J.Ramp*SideEase((X-Start+4.6)/4.6);
    Deck:=sdRamp;
    Exit;
  end;
  if J.Gap>0 then begin
    GapStart:=SideMix(Start,Finish,0.13+(1-J.Gap)*0.25);
    GapEnd:=SideMix(Start,Finish,0.67+0.23*J.Gap);
    if X<GapStart then begin
      Y:=Y+J.Ramp*(1-SideEase((X-Start)/(GapStart-Start)));
      Deck:=sdRamp;
      Exit;
    end;
    if X<GapEnd then Exit(False);
    DeckEnd:=Finish+SideMix(3.75,1.65,J.Gap);
    if X<DeckEnd then begin
      Deck:=sdBridge;
      if J.Lift>0 then begin
        U:=1-SideEase((X-Finish)/Max(0.1,DeckEnd-Finish));
        Y:=Y+U*J.Lift*Sin((Time-Cues[J.Last].Time)*4.6);
        Deck:=sdMoving;
      end;
    end;
  end else if X<Start+3.4 then
    Y:=Y+J.Ramp*(1-SideEase((X-Start)/3.4));
end;

function TSideRacePlan.Hero(Time:Double):TPointF;
var I,K:Integer; J:TSideJump; T0,T1,Roof,Y0,Y1,H,U,A:Double; D:TSideDeck;
begin
  Time:=EnsureRange(Time,0.0,Duration);
  Result:=PointF(Distance(Time),0);
  I:=JumpAt(Time);
  if I>=0 then begin
    J:=Jumps[I];
    T0:=Cues[J.First].Time;
    T1:=Cues[J.Last].Time;
    Y0:=BaseRoad(J.X0)+J.Ramp;
    Y1:=BaseRoad(J.X1);
    H:=J.Height;
    if J.Roof>=0 then begin
      Roof:=Cues[J.Roof].Time;
      A:=BaseRoad(Distance(Roof))+BossRig(Cues[J.Roof].Boss).Roof;
      // 保存済みの時刻を使い、高い荷台への進入と離脱に必要な余裕を確保する。
      H:=Max(H,Max(Abs(A-Y0),Abs(A-Y1))*0.56+0.16);
      if Time<=Roof then begin T1:=Roof; Y1:=A; end
      else begin T0:=Roof; Y0:=A; end;
    end;
    U:=(Time-T0)/(T1-T0);
    Result.Y:=SideMix(Y0,Y1,U)+4*H*U*(1-U);
    Exit;
  end;
  Road(Result.X,Time,A,D);
  Result.Y:=A;
  K:=CueFrom(Time-0.085);
  if (K<Length(Cues)) and (Cues[K].Action=saBump) then begin
    A:=Abs(Cues[K].Time-Time);
    if A<0.085 then Result.Y:=Result.Y+0.19*Sqr(Cos(Pi*A/0.17));
  end;
end;

function TSideRacePlan.HeroAngle(Time:Double):Double;
var I,K:Integer; V,Air:Double; P,Q:TPointF;
begin
  P:=Hero(Time-0.043);
  Q:=Hero(Time+0.043);
  Result:=EnsureRange(ArcTan2(Q.Y-P.Y,Max(0.001,Q.X-P.X)),-0.34,0.34);
  Air:=0;
  I:=JumpAt(Time);
  if I>=0 then Air:=1;
  K:=CueFrom(Time-0.075);
  while (K<Length(Cues)) and (Cues[K].Time<=Time+0.075) do begin
    if (Cues[K].Car>=0) or SideBodyHit(Cues[K].Action) or (Cues[K].Action=saBossRoof) then begin
      V:=SideEase(Abs(Time-Cues[K].Time)/0.075);
      Result:=Result*V;
    end;
    Inc(K);
  end;
  if Air=0 then Result:=Result+0.005*Sin(Time*49);
end;

function TSideRacePlan.Health(Time:Double):Double;
var I:Integer;
begin
  I:=CueFrom(Time);
  if (I<Length(Cues)) and (Cues[I].Time=Time) then Exit(Cues[I].Health);
  if I>0 then Exit(Cues[I-1].Health);
  Result:=1;
end;

function TSideRacePlan.CarCue(Index:Integer;Time:Double):Integer;
var F:TSideCar; K:Integer;
begin
  F:=Cars[Index];
  K:=CueFrom(Time);
  Result:=EnsureRange(F.First+((K-F.First+F.Stride-1) div F.Stride)*F.Stride,F.First,F.Last);
end;

function TSideRacePlan.CarHalf(Index:Integer):Double;
const Sizes:array[0..5] of Double=(0.85,0.92,1.13,1.45,1.05,1.25);
begin
  Result:=Sizes[Cars[Index].Kind];
end;

function TSideRacePlan.CarPose(Index:Integer;Time,EntryGap:Double):TSidePose;
var F:TSideCar; H,Lead:TPointF; I,Nearest:Integer;
  First,Finish,Gap,U,Age,Span,X,Y,ContactTime,Follow,ImpactAngle:Double; D:TSideDeck;
begin
  F:=Cars[Index];
  H:=Hero(Time);
  First:=Cues[F.First].Time;
  Finish:=Cues[F.Last].Time;
  Result.Angle:=HeroAngle(Time)*0.70;
  if Time<First then begin
    if F.Side=1 then begin
      Span:=SideFrontEntryLead(EntryGap)+F.Kind*0.038;
      Gap:=EntryGap*SideEase((First-Time)/Span);
    end else begin
      Span:=0.79+F.Kind*0.075;
      if F.Stride=2 then Span:=Span+0.23;
      Gap:=(5.9+F.Kind*0.58)*SideEase((First-Time)/Span);
    end;
  end else if Time>Finish then begin
    Age:=Time-Finish;
    ImpactAngle:=HeroAngle(Finish)*0.70;
    if F.Side=1 then begin
      // 上向きの蹴り出しの後、横方向の速度を一定に近づける。
      Gap:=EntryGap*(Age-0.10*(1-Exp(-10*Age)))/0.68;
      Result.Angle:=ImpactAngle-(7.75+F.Kind*0.26)*(Age-0.05*(1-Exp(-20*Age)));
    end else begin
      Gap:=(4.65+F.Kind*0.50)*(1-Exp(-3.9*Age));
      Result.Angle:=ImpactAngle-Age*(2.0+F.Kind*0.61);
    end;
  end else begin
    I:=CarCue(Index,Time);
    Gap:=0;
    if I>F.First then begin
      Span:=Cues[I].Time-Cues[I-F.Stride].Time;
      U:=(Time-Cues[I-F.Stride].Time)/Span;
      Gap:=Min(1.25,Span*4.7)*Sqr(Sin(Pi*U));
    end;
  end;
  X:=H.X+F.Side*(SideHeroHalf+CarHalf(Index)+Gap);
  Road(X,Time,Y,D);
  if Time>Finish then begin
    Age:=Time-Finish;
    Lead:=Hero(Finish);
    if F.Side=1 then begin
      // 放物線で上昇と下降をつなぎ、タイヤの接地基準から車体中央の回転へ補正する。
      if Age<0.22 then U:=(Age-0.22)/0.22 else U:=(Age-0.22)/0.80;
      Y:=Max(Y,Lead.Y+(3.68+F.Kind*0.07)*(1-Sqr(U)));
      ImpactAngle:=HeroAngle(Finish)*0.70;
      X:=X+0.53*(Sin(Result.Angle)-Sin(ImpactAngle));
      Y:=Y+0.53*(Cos(ImpactAngle)-Cos(Result.Angle));
    end else Y:=Max(Y,Lead.Y+Age*(4.8+F.Kind*0.43)-7.9*Sqr(Age));
  end else begin
    Nearest:=CarCue(Index,Time);
    if (Nearest>F.First) and (Abs(Time-Cues[Nearest-F.Stride].Time)<Abs(Time-Cues[Nearest].Time)) then
      Dec(Nearest,F.Stride);
    ContactTime:=Cues[Nearest].Time;
    if JumpAt(ContactTime)>=0 then begin
      Lead:=Hero(Time+F.Side*(0.084+F.Kind*0.023));
      Y:=Y+Max(0.0,Lead.Y-BaseRoad(Lead.X));
    end;
    Follow:=1-SideEase(Abs(Time-ContactTime)/0.30);
    Y:=SideMix(Y,H.Y,Follow);
  end;
  Result.Root:=PointF(X,Y);
end;

function TSideRacePlan.ChainCue(Index:Integer):Integer;
var F:TSideCar; I:Integer; T,Gap:Double;
begin
  F:=Cars[Index];
  I:=F.Last+1;
  if (F.Side<0) or (I>=Length(Cues)) or ((F.Last+F.Kind) mod 4<>0) then Exit(-1);
  T:=Cues[F.Last].Time;
  Gap:=Cues[I].Time-T;
  if (Gap<0.14) or (Gap>0.38) or (Stages[StageAt(T)].Level<3) or
    (BossAt(T)>=0) or (JumpAt(T)>=0) then Exit(-1);
  Result:=I;
end;

function TSideRacePlan.ChainCar(Index,Hit:Integer;Time,EntryGap:Double):TSidePose;
var Source:TSidePose; HitTime,Age,Shift,X,Y,Join:Double; Deck:TSideDeck;
begin
  HitTime:=Cues[Hit].Time;
  Age:=Time-HitTime;
  Source:=CarPose(Index,HitTime,EntryGap);
  X:=Source.Root.X+CarHalf(Index)+0.92+Distance(Time)-Distance(HitTime);
  Result.Angle:=Source.Angle*0.52;
  if Age<0 then begin
    X:=X+EntryGap*SideEase(-Age/SideFrontEntryLead(EntryGap));
    Road(X,Time,Y,Deck);
    Join:=1-SideEase(-Age/0.32);
    Y:=SideMix(Y,Source.Root.Y,Join);
    Result.Angle:=Result.Angle*Join;
  end else begin
    Shift:=3.5*(1-Exp(-4.2*Age));
    X:=X+Shift;
    Y:=Source.Root.Y+3.8*Age-6.3*Sqr(Age);
    Y:=Y+Max(0.0,BaseRoad(X)-Y)*SideEase(Age/0.12);
    Result.Angle:=Result.Angle+2.55*Age;
  end;
  Result.Root:=PointF(X,Y);
end;

function TSideRacePlan.BossRig(Index:Integer):TSideRig;
const Body:array[0..4] of Double=(2.63,3.08,2.86,3.35,2.67);
  Cargo:array[0..4] of Double=(1.66,1.53,2.06,1.82,1.94);
var K,L:Integer;
begin
  K:=Bosses[Index].Kind;
  L:=Stages[StageAt(Cues[Bosses[Index].Last].Time)].Level;
  Result.Half:=Body[K]+0.14*L;
  Result.Roof:=(Cargo[K]+0.065*L)*SideTruckHeightScale;
  Result.Rear:=Result.Half-0.84;
  Result.Wheels:=3+(K mod 3);
  Result.Finish:=K;
end;

function TSideRacePlan.BossPose(Index:Integer;Time,EntryGap:Double):TSidePose;
var B:TSideBoss; Rig:TSideRig; I,J,K:Integer; D,Gap,Age,Shift,Roof,FromTime,EndTime,Approach,X:Double;
begin
  B:=Bosses[Index];
  Rig:=BossRig(Index);
  X:=Distance(Time);
  Result.Root:=PointF(X,BaseRoad(X));
  J:=JumpAt(Time);
  if J<0 then Result.Root.Y:=Hero(Time).Y;
  Result.Angle:=0;
  Age:=Time-Cues[B.Last].Time;
  if Age>=0 then begin
    Gap:=3.7*(1-Exp(-3.2*Age));
    Result.Root.X:=X+SideHeroHalf+Rig.Half+Gap;
    Result.Root.Y:=Result.Root.Y+Max(0.0,Age*(3.2+0.48*B.Kind)-3.6*Sqr(Age));
    if B.Kind in [0,2,4] then Result.Angle:=Age*(0.40+B.Kind*0.42);
    Exit;
  end;
  D:=0.51;
  K:=CueFrom(Time);
  for I:=Max(B.First,K-8) to Min(B.Last,K+8) do
    if SideBodyHit(Cues[I].Action) then D:=Min(D,Abs(Time-Cues[I].Time));
  Gap:=2.25*SideEase(D/0.45);
  if Time<Cues[B.First].Time then
    Gap:=SideMix(Gap,EntryGap,SideEase((Cues[B.First].Time-Time)/SideFrontEntryLead(EntryGap)));
  Result.Root.X:=X+SideHeroHalf+Rig.Half+Gap;
  if J<0 then J:=JumpAt(Time+0.39);
  if (J<0) or (Jumps[J].Roof<0) or (Cues[Jumps[J].Roof].Boss<>Index) then Exit;
  Roof:=Cues[Jumps[J].Roof].Time;
  FromTime:=Cues[Jumps[J].First].Time;
  EndTime:=Cues[Jumps[J].Last].Time;
  Approach:=SideEase((Time-FromTime+0.39)/0.45)*(1-SideEase((Time-Roof)/(EndTime-Roof)));
  Result.Root.X:=X+SideHeroHalf+Rig.Half+Gap*(1-0.91*Approach);
  if Time<=Roof then Shift:=SideEase(((Time-FromTime)/(Roof-FromTime)-0.43)/0.57)
  else Shift:=1-SideEase((Time-Roof)/(EndTime-Roof)/0.45);
  Result.Root.X:=SideMix(Result.Root.X,X+Rig.Rear,Shift);
end;

function TSideRacePlan.Contact(Index:Integer):TPointF;
var A:TSideCue; P:TPointF; S:Integer;
begin
  A:=Cues[Index];
  P:=Hero(A.Time);
  Result:=P;
  case A.Action of
    saFront,saBossRam,saBossTire,saBossClear,saRock,saBossDrop,saBossEscort:
      Result:=PointF(P.X+SideHeroHalf,P.Y+0.46);
    saRear:Result:=PointF(P.X-SideHeroHalf,P.Y+0.46);
    saRepair:Result.Y:=P.Y+0.65;
    saBossRoof:Result.Y:=P.Y;
  end;
  if A.Car>=0 then begin
    S:=Cars[A.Car].Side;
    Result:=PointF(P.X+S*SideHeroHalf,P.Y+0.46);
  end;
end;
end.
