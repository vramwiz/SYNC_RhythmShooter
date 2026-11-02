unit RhythmRaceCrashMotion;
// Race v8/v9の保存データ型と絶対時刻の位置・姿勢。生成とJSON処理を持たない。
interface
uses System.SysUtils,RhythmAudio;
const
  CRASH_FOCUS=40.0;
  CRASH_HERO_WIDTH=0.23;
  CRASH_HERO_FRONT=6.0;
  CRASH_HERO_BACK=9.0;
  CRASH_MAX_SECONDS=512.0*1024*1024/4/RHYTHM_RATE;
type
  TCrashKey=record
    Time,Value:Double;
  end;
  TCrashHit=record
    Time,Strength,Distance,Lane:Double;
    Source,Enemy,HP:Integer;
  end;
  TCrashEnemy=record
    Spawn,Ready,Kill,Clear,Width,HalfLength,Speed,ApproachLane:Double;
    First,Last,Kind,Boss,Side:Integer;
  end;
  TCrashTraffic=record
    Spawn,Clear,Pass,RelativeSpeed,Width,HalfLength,Gap,FarLane:Double;
    TurnStart,TurnFinish,NearLane:Double;
    Side,Kind,Shunt:Integer;
  end;
  TCrashShunt=record
    Time,Distance,Lane:Double;
    Traffic,Enemy,Side:Integer;
  end;
  TCrashBoss=record
    Spawn,Ready,Kill:Double;
    Source,Enemy:Integer;
  end;
  TCrashProjection=record
    X,Y,Scale:Double;
    Visible:Boolean;
  end;
  TCrashPose=record
    Distance,Lane,Width,Front,Back,Turn,Lift,Damage:Double;
    Kind,Role,Index:Integer;
    Alive:Boolean;
  end;
  TRaceCrashMotion=class
  public
    Events:TArray<TRhythmHit>;
    Hits:TArray<TCrashHit>;
    Enemies:TArray<TCrashEnemy>;
    Traffic:TArray<TCrashTraffic>;
    Keys,Road:TArray<TCrashKey>;
    Bosses:TArray<TCrashBoss>;
    Shunts:TArray<TCrashShunt>;
    Version:Integer;
    Duration,SoundEnd,EndTime,Launch,Acceleration,Goal,TopSpeed:Double;
    Frequency:Integer;
  private
    function EnemyBaseLaneAt(Index:Integer;Time:Double):Double;
  public
    // v8/v9は元寸法、v10は全軸90%。旧保存の接触点を勝手に変えない。
    function HeroScale:Double;
    function HeroWidth:Double;
    function HeroFront:Double;
    function HeroBack:Double;
    function TrafficLaneAt(Index:Integer;Time:Double):Double;
    function TrafficLaneVelocity(Index:Integer;Time:Double):Double;
    procedure TrafficLaneBounds(Index:Integer;A,B:Double;out Low,High:Double);
    procedure EnemyLaneBounds(Index:Integer;A,B:Double;out Low,High:Double);
    function DistanceAt(Time:Double):Double;
    function SpeedAt(Time:Double):Double;
    function LaneAt(Time:Double):Double;
    function LaneVelocity(Time:Double):Double;
    procedure LaneBounds(A,B:Double;out Low,High:Double);
    function BendAt(Distance:Double):Double;
    function BendVelocity(Distance:Double):Double;
    function Project(Distance,Lane,Time,Height:Double):TCrashProjection;
    function HitBefore(Time:Double):Integer;
    function EnemyBefore(Time:Double):Integer;
    function TrafficBefore(Time:Double):Integer;
    function BossOf(Time:Double):Integer;
    function HeroAt(Time:Double):TCrashPose;
    function EnemyAt(Index:Integer;Time:Double):TCrashPose;
    // RoadAtは接触前の認証済み経路。TrafficAtは保存された吹飛びを含む。
    function TrafficRoadAt(Index:Integer;Time:Double):TCrashPose;
    function TrafficAt(Index:Integer;Time:Double):TCrashPose;
    function ShuntBefore(Time:Double):Integer;
    function TrafficClearance(Index:Integer;Time:Double):Double;
    function TrafficCertified(Index:Integer):Boolean;
    function DefeatedAt(Time:Double):Integer;
    function BossHealth(Time:Double):Double;
    function Excluded:Integer;
  end;
implementation
uses System.Math;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function KeyBefore(const A:TArray<TCrashKey>;Time:Double):Integer;
var
  L,R,M:Integer;
begin L:=0;
  R:=Length(A);
  while L<R do begin M:=(L+R) div 2;
    if A[M].Time<=Time then L:=M+1 else R:=M;
  end;
  Result:=Max(0,L-1);
end;

function KeyAt(const A:TArray<TCrashKey>;Time:Double;Velocity:Boolean=False):Double;
var
  I:Integer;
  U,Span:Double;
begin Result:=0;
  if Length(A)=0 then Exit;
  I:=KeyBefore(A,Time);
  if I=High(A) then begin if not Velocity then Result:=A[I].Value;
    Exit;
  end;
  Span:=A[I+1].Time-A[I].Time;
  U:=EnsureRange((Time-A[I].Time)/Span,0.0,1.0);
  if Velocity then Result:=(A[I+1].Value-A[I].Value)*6*U*(1-U)/Span else Result:=A[I].Value+(A[I+1].Value-A[I].Value)*Smooth(U);
end;

function TRaceCrashMotion.DistanceAt(Time:Double):Double;
var
  T,A,U,Tail:Double;
begin T:=EnsureRange(Time,0.0,EndTime);
  Result:=0;
  if (SoundEnd<=0) or (T<=Launch) then Exit;
  A:=Launch+Acceleration;
  if T<A then begin U:=(T-Launch)/Acceleration;
    Exit(TopSpeed*Acceleration*(U*U*U-0.5*U*U*U*U));
  end;
  Result:=0.5*TopSpeed*Acceleration+TopSpeed*(Min(T,Goal)-A);
  if T>Goal then begin Tail:=EndTime-Goal;
    U:=(T-Goal)/Tail;
    Result:=Result+TopSpeed*Tail*(U-U*U*U+0.5*U*U*U*U);
  end;
end;

function TRaceCrashMotion.SpeedAt(Time:Double):Double;
begin Result:=0;
  if (SoundEnd<=0) or (Time<=Launch) or (Time>=EndTime) then Exit;
  if Time<Launch+Acceleration then Exit(TopSpeed*Smooth((Time-Launch)/Acceleration));
  Result:=TopSpeed;
  if Time>Goal then Result:=Result*(1-Smooth((Time-Goal)/(EndTime-Goal)));
end;

function TRaceCrashMotion.LaneAt(Time:Double):Double;
begin Result:=KeyAt(Keys,EnsureRange(Time,0.0,EndTime));
end;

function TRaceCrashMotion.LaneVelocity(Time:Double):Double;
begin Result:=KeyAt(Keys,EnsureRange(Time,0.0,EndTime),True);
end;

procedure TRaceCrashMotion.LaneBounds(A,B:Double;out Low,High:Double);
var
  I:Integer;
begin Low:=Min(LaneAt(A),LaneAt(B));
  High:=Max(LaneAt(A),LaneAt(B));
  I:=KeyBefore(Keys,A);
  while I<Length(Keys) do begin if Keys[I].Time>B then Break;
    if Keys[I].Time>=A then begin Low:=Min(Low,Keys[I].Value);
      High:=Max(High,Keys[I].Value);
    end;
    Inc(I);
  end;
end;

function TRaceCrashMotion.BendAt(Distance:Double):Double;
begin Result:=KeyAt(Road,Max(0.0,Distance));
end;

function TRaceCrashMotion.BendVelocity(Distance:Double):Double;
begin Result:=KeyAt(Road,Max(0.0,Distance),True);
end;

function TRaceCrashMotion.Project(Distance,Lane,Time,Height:Double):TCrashProjection;
var
  Camera,Z,Current,Age:Double;
  I:Integer;
begin Result:=Default(TCrashProjection);
  Camera:=DistanceAt(Time);
  Z:=Distance-Camera;
  if Z<=-34 then Exit;
  Result.Scale:=CRASH_FOCUS/(CRASH_FOCUS+Z);
  Current:=BendAt(Camera);
  Result.X:=0.8+0.12*Current+0.55*(BendAt(Max(0.0,Distance))-Current)*(1-Result.Scale)+0.58*Lane*Result.Scale;
  Result.Y:=0.28+(0.52-Height)*Result.Scale;
  Result.Visible:=Z<=1400;
  I:=HitBefore(Time);
  if I>=0 then begin Age:=Time-Hits[I].Time;
    if (Age>=0) and (Age<0.11) then Result.X:=Result.X+0.008*Hits[I].Strength*(1-Age/0.11)*Sin(Age*160);
  end;
end;

function TRaceCrashMotion.HitBefore(Time:Double):Integer;
var
  L,R,M:Integer;
begin L:=0;
  R:=Length(Hits);
  while L<R do begin M:=(L+R) div 2;
    if Hits[M].Time<=Time then L:=M+1 else R:=M;
  end;
  Result:=L-1;
end;

function TRaceCrashMotion.EnemyBefore(Time:Double):Integer;
var
  L,R,M:Integer;
begin L:=0;
  R:=Length(Enemies);
  while L<R do begin M:=(L+R) div 2;
    if Enemies[M].Ready<=Time then L:=M+1 else R:=M;
  end;
  Result:=L-1;
end;

function TRaceCrashMotion.TrafficBefore(Time:Double):Integer;
var
  L,R,M:Integer;
begin L:=0;
  R:=Length(Traffic);
  while L<R do begin M:=(L+R) div 2;
    if Traffic[M].Pass<=Time then L:=M+1 else R:=M;
  end;
  Result:=L-1;
end;

function TRaceCrashMotion.BossOf(Time:Double):Integer;
var
  L,R,M:Integer;
begin L:=0;
  R:=Length(Bosses);
  while L<R do begin M:=(L+R) div 2;
    if Bosses[M].Ready<=Time then L:=M+1 else R:=M;
  end;
  Result:=L-1;
  if Result>=0 then if Time>Bosses[Result].Kill then Result:=-1;
end;

function TRaceCrashMotion.HeroAt(Time:Double):TCrashPose;
begin Result:=Default(TCrashPose);
  Result.Distance:=DistanceAt(Time);
  Result.Lane:=LaneAt(Time);
  Result.Width:=HeroWidth;
  Result.Front:=HeroFront;
  Result.Back:=HeroBack;
  Result.Kind:=0;
  Result.Role:=2;
  Result.Index:=-1;
  Result.Alive:=True;
end;

function TRaceCrashMotion.HeroScale:Double;
begin Result:=1;if Version>=10 then Result:=0.90;end;
function TRaceCrashMotion.HeroWidth:Double;
begin Result:=CRASH_HERO_WIDTH*HeroScale;end;
function TRaceCrashMotion.HeroFront:Double;
begin Result:=CRASH_HERO_FRONT*HeroScale;end;
function TRaceCrashMotion.HeroBack:Double;
begin Result:=CRASH_HERO_BACK*HeroScale;end;

function TRaceCrashMotion.TrafficLaneAt(Index:Integer;Time:Double):Double;
var V:TCrashTraffic;U:Double;
begin
  V:=Traffic[Index];
  if V.TurnFinish<=V.TurnStart then Exit(V.NearLane);
  U:=Smooth((Time-V.TurnStart)/(V.TurnFinish-V.TurnStart));
  Result:=V.FarLane+(V.NearLane-V.FarLane)*U;
end;
function TRaceCrashMotion.TrafficLaneVelocity(Index:Integer;Time:Double):Double;
var V:TCrashTraffic;U,Span:Double;
begin
  Result:=0;V:=Traffic[Index];Span:=V.TurnFinish-V.TurnStart;
  if (Span<=0) or (Time<=V.TurnStart) or (Time>=V.TurnFinish) then Exit;
  U:=(Time-V.TurnStart)/Span;
  Result:=(V.NearLane-V.FarLane)*6*U*(1-U)/Span;
end;
procedure TRaceCrashMotion.TrafficLaneBounds(Index:Integer;A,B:Double;out Low,High:Double);
begin
  // 1回だけの単調操舵なので、両端が区間全体の厳密な包絡になる。
  Low:=Min(TrafficLaneAt(Index,A),TrafficLaneAt(Index,B));
  High:=Max(TrafficLaneAt(Index,A),TrafficLaneAt(Index,B));
end;
function TRaceCrashMotion.EnemyBaseLaneAt(Index:Integer;Time:Double):Double;
var E:TCrashEnemy;A,B:TCrashHit;J:Integer;Span,U,Target:Double;
begin
  E:=Enemies[Index];A:=Hits[E.First];Target:=A.Lane+E.Side*E.Width;
  if Time<E.Ready then begin
    Span:=Min(0.30,E.Ready-E.Spawn);
    U:=Smooth((Time-(E.Ready-Span))/Max(1E-8,Span));
    Exit(E.ApproachLane+(Target-E.ApproachLane)*U);
  end;
  J:=EnsureRange(HitBefore(Time),E.First,E.Last);A:=Hits[J];B:=Hits[Min(J+1,E.Last)];
  Result:=A.Lane+E.Side*E.Width;
  if B.Time<=A.Time then Exit;
  Span:=Min(0.22,(B.Time-A.Time)*0.45);
  U:=Smooth((Time-(B.Time-Span))/Max(1E-8,Span));
  Result:=Result+(B.Lane-A.Lane)*U;
end;
procedure TRaceCrashMotion.EnemyLaneBounds(Index:Integer;A,B:Double;out Low,High:Double);
var E:TCrashEnemy;T,Stop,L0,L1,U0,U1,S0,S1,R0,R1,Peak:Double;J,Side:Integer;H0,H1:TCrashHit;
  procedure Include(L,H:Double);
  begin Low:=Min(Low,EnsureRange(L,-1+E.Width,1-E.Width));High:=Max(High,EnsureRange(H,-1+E.Width,1-E.Width));end;
begin
  E:=Enemies[Index];Low:=1E30;High:=-1E30;T:=A;
  if T<E.Ready then begin Stop:=Min(B,E.Ready);
    L0:=EnemyBaseLaneAt(Index,T);L1:=EnemyBaseLaneAt(Index,Stop);
    Include(Min(L0,L1),Max(L0,L1));T:=Stop;
  end;
  while T<=B do begin
    J:=EnsureRange(HitBefore(T),E.First,E.Last);H0:=Hits[J];H1:=Hits[Min(J+1,E.Last)];
    if H1.Time<=H0.Time then begin Include(EnemyBaseLaneAt(Index,T),EnemyBaseLaneAt(Index,T));Break;end;
    Stop:=Min(B,H1.Time);L0:=EnemyBaseLaneAt(Index,T);L1:=EnemyBaseLaneAt(Index,Stop);
    U0:=EnsureRange((T-H0.Time)/(H1.Time-H0.Time),0.0,1.0);
    U1:=EnsureRange((Stop-H0.Time)/(H1.Time-H0.Time),0.0,1.0);
    S0:=0;S1:=0;
    if E.Boss>=0 then begin
      S0:=Min(Sin(Pi*U0),Sin(Pi*U1));S1:=Max(Sin(Pi*U0),Sin(Pi*U1));
      if (U0<=0.5) and (U1>=0.5) then S1:=1;
      Side:=-1;if J mod 2=0 then Side:=1;
      R0:=Min(Side*0.12*S0,Side*0.12*S1);R1:=Max(Side*0.12*S0,Side*0.12*S1);S0:=R0;S1:=R1;
    end else if E.Side<>0 then begin
      R0:=EnsureRange(Min(T-H0.Time,H1.Time-T)/0.04,0.0,1.0);
      R1:=EnsureRange(Min(Stop-H0.Time,H1.Time-Stop)/0.04,0.0,1.0);
      Peak:=Max(R0,R1);if (T<=(H0.Time+H1.Time)*0.5) and (Stop>=(H0.Time+H1.Time)*0.5) then Peak:=Min(1,(H1.Time-H0.Time)/0.08);
      S0:=Min(E.Side*0.04*Min(R0,R1),E.Side*0.04*Peak);
      S1:=Max(E.Side*0.04*Min(R0,R1),E.Side*0.04*Peak);
    end;
    Include(Min(L0,L1)+S0,Max(L0,L1)+S1);
    if Stop>=B then Break;T:=Stop;
  end;
end;

function TRaceCrashMotion.EnemyAt(Index:Integer;Time:Double):TCrashPose;
var
  E:TCrashEnemy;
  J,N,Side:Integer;
  CZ,U,Wave,Age:Double;
  A,B:TCrashHit;
begin E:=Enemies[Index];
  Result:=Default(TCrashPose);
  Result.Width:=E.Width;
  Result.Front:=E.HalfLength;
  Result.Back:=E.HalfLength;
  Result.Kind:=E.Kind;
  Result.Role:=1;
  Result.Index:=Index;
  Result.Alive:=Time<E.Kill;
  CZ:=3;
  if E.Side=0 then CZ:=HeroFront+E.HalfLength;
  if Time<E.Ready then begin Result.Distance:=DistanceAt(E.Ready)+CZ-E.Speed*(E.Ready-Time);
    if E.Side=0 then Result.Lane:=LaneAt(Time)+0.10*Sin(Index*1.3)*Smooth((E.Ready-Time)/0.7) else Result.Lane:=LaneAt(Time)+E.Side*(HeroWidth+E.Width+0.04*EnsureRange((E.Ready-Time)/0.055,0.0,1.0));
  end
  else if Time<=E.Kill then begin J:=EnsureRange(HitBefore(Time),E.First,E.Last);
    A:=Hits[J];
    B:=Hits[Min(J+1,E.Last)];
    U:=0;
    if B.Time>A.Time then U:=EnsureRange((Time-A.Time)/(B.Time-A.Time),0.0,1.0);
    Wave:=Sqr(Sin(Pi*U));
    Result.Distance:=DistanceAt(Time)+CZ;
    if E.Side=0 then begin if E.Boss>=0 then Result.Distance:=Result.Distance+Wave*24 else Result.Distance:=Result.Distance+Wave*5;
      Result.Lane:=LaneAt(Time);
      if E.Boss>=0 then begin Side:=-1;
        if J mod 2=0 then Side:=1;
        Result.Lane:=Result.Lane+0.12*Sin(Pi*U)*Side;
      end;
    end else Result.Lane:=LaneAt(Time)+E.Side*(HeroWidth+E.Width+0.04*EnsureRange(Min(Time-A.Time,B.Time-Time)/0.04,0.0,1.0));
  end
  else begin Age:=Time-E.Kill;
    U:=Max(0.0,Age-0.018);
    Side:=E.Side;
    if Side=0 then Side:=(Index mod 2)*2-1;
    Result.Distance:=DistanceAt(Time)+CZ-28*U;
    Result.Lane:=LaneAt(E.Kill)+Side*(U*3.8+U*U*2);
    if E.Side<>0 then Result.Lane:=Result.Lane+E.Side*(HeroWidth+E.Width);
    Result.Turn:=Side*U*9;
    Result.Lift:=Max(0.0,U*1.2-U*U*1.5);
  end;
  if (Version>=10) and (Time<=E.Kill) then begin
    Result.Lane:=EnemyBaseLaneAt(Index,Time);
    if (Time<E.Ready) and (E.Side<>0) then
      Result.Lane:=Result.Lane+E.Side*0.04*EnsureRange((E.Ready-Time)/0.055,0.0,1.0);
    if Time>=E.Ready then begin
      if E.Boss>=0 then begin Side:=-1;if J mod 2=0 then Side:=1;
        Result.Lane:=Result.Lane+0.12*Sin(Pi*U)*Side;
      end else if E.Side<>0 then Result.Lane:=Result.Lane+E.Side*0.04*EnsureRange(Min(Time-A.Time,B.Time-Time)/0.04,0.0,1.0);
    end;
  end;
  if Time<=E.Kill then Result.Lane:=EnsureRange(Result.Lane,-1+E.Width,1-E.Width);
  N:=EnsureRange(HitBefore(Time)-E.First+1,0,E.Last-E.First+1);
  Result.Damage:=N/(E.Last-E.First+1);
end;

function TRaceCrashMotion.TrafficRoadAt(Index:Integer;Time:Double):TCrashPose;
var
  E:TCrashTraffic;
  Raw,Blend,Target,Clearance,Q,Bound:Double;
begin E:=Traffic[Index];
  Result:=Default(TCrashPose);
  Raw:=E.RelativeSpeed*(E.Pass-Time);
  if Version>=10 then begin
    Result.Lane:=TrafficLaneAt(Index,Time);
    Result.Distance:=DistanceAt(Time)+Raw;
  end else begin
  Blend:=Smooth((130-Abs(Raw))/100);
  Target:=LaneAt(Time)+E.Side*(HeroWidth+E.Width+E.Gap+0.04*Sqr(Sin((Time-E.Pass)*1.7)));
  Result.Lane:=EnsureRange(E.FarLane+(Target-E.FarLane)*Blend,-1+E.Width,1-E.Width);
  // Whole-interval certificate: if lateral clearance<=0 then Q=1, so |Z|>=Bound.
  // At Pass the exact lane envelope guarantees Q=0, making the signed guard continuous.
  Clearance:=Abs(Result.Lane-LaneAt(Time))-HeroWidth-E.Width;
  Q:=Smooth((E.Gap-Clearance)/E.Gap);
  Bound:=Max(HeroFront,HeroBack)+E.HalfLength+2;
  Result.Distance:=DistanceAt(Time)+Raw+Sign(Raw)*Bound*Q;
  end;
  Result.Width:=E.Width;
  Result.Front:=E.HalfLength;
  Result.Back:=E.HalfLength;
  Result.Kind:=E.Kind;
  Result.Role:=0;
  Result.Index:=Index;
  Result.Alive:=True;
end;

function TRaceCrashMotion.TrafficAt(Index:Integer;Time:Double):TCrashPose;
var
  V:TCrashTraffic;
  S:TCrashShunt;
  Start:TCrashPose;
  Age,Z,Offset:Double;
begin
  Result:=TrafficRoadAt(Index,Time);
  V:=Traffic[Index];
  if V.Shunt<0 then Exit;
  S:=Shunts[V.Shunt];
  if Time<S.Time then Exit;
  Start:=TrafficRoadAt(Index,S.Time);
  Age:=Time-S.Time;
  Z:=Start.Distance-DistanceAt(S.Time);
  Offset:=Abs(Start.Lane-LaneAt(S.Time));
  Result.Distance:=DistanceAt(Time)+Z+Sign(Z)*38*Age;
  if Version>=10 then Result.Lane:=Start.Lane+S.Side*(3.8*Age+2*Sqr(Age))
  else Result.Lane:=LaneAt(Time)+S.Side*(Offset+3.8*Age+2*Sqr(Age));
  Result.Turn:=S.Side*Age*9;
  Result.Lift:=Max(0.0,1.25*Age-1.5*Sqr(Age));
  Result.Alive:=False;
  Result.Damage:=1;
end;

function TRaceCrashMotion.ShuntBefore(Time:Double):Integer;
var
  L,R,M:Integer;
begin L:=0;
  R:=Length(Shunts);
  while L<R do begin M:=(L+R) div 2;
    if Shunts[M].Time<=Time then L:=M+1 else R:=M;
  end;
  Result:=L-1;
end;

function TRaceCrashMotion.TrafficClearance(Index:Integer;Time:Double):Double;
var
  P:TCrashPose;
begin P:=TrafficAt(Index,Time);
  Result:=Abs(P.Lane-LaneAt(Time))-HeroWidth-P.Width;
end;

function TRaceCrashMotion.TrafficCertified(Index:Integer):Boolean;
var
  E:TCrashTraffic;
  Low,High,Near,Extra:Double;
begin E:=Traffic[Index];
  if Version>=10 then begin
    Near:=E.Pass-(HeroFront+E.HalfLength)/E.RelativeSpeed;
    LaneBounds(Max(E.Spawn,Near),Min(E.Clear,E.Pass+(HeroBack+E.HalfLength)/E.RelativeSpeed),Low,High);
    Result:=(E.Side=-1) or (E.Side=1);
    Result:=Result and (E.FarLane-E.Width>=-1-1E-9) and (E.FarLane+E.Width<=1+1E-9) and
      (E.NearLane-E.Width>=-1-1E-9) and (E.NearLane+E.Width<=1+1E-9) and
      (E.TurnStart>=E.Spawn) and (E.TurnFinish>=E.TurnStart) and ((E.TurnFinish=E.TurnStart) or (E.TurnFinish<=Near));
    if E.Side>0 then Result:=Result and (E.NearLane-High>=HeroWidth+E.Width+E.Gap-1E-9)
    else Result:=Result and (Low-E.NearLane>=HeroWidth+E.Width+E.Gap-1E-9);
    Exit;
  end;
  Near:=30/E.RelativeSpeed+0.10;
  LaneBounds(Max(Launch,E.Pass-Near),Min(EndTime,E.Pass+Near),Low,High);
  Extra:=HeroWidth+2*E.Width+E.Gap+0.04;
  Result:=(E.Side=-1) or (E.Side=1);
  Result:=Result and (E.Gap>=0.018) and (E.RelativeSpeed>0) and (E.Width>0) and (E.HalfLength>0);
  if E.Side>0 then Result:=Result and (High+Extra<=0.999+1E-9) else Result:=Result and (Low-Extra>=-0.999-1E-9);
end;

function TRaceCrashMotion.DefeatedAt(Time:Double):Integer;
var
  L,R,M:Integer;
begin L:=0;
  R:=Length(Enemies);
  while L<R do begin M:=(L+R) div 2;
    if Enemies[M].Kill<=Time then L:=M+1 else R:=M;
  end;
  Result:=L;
end;

function TRaceCrashMotion.BossHealth(Time:Double):Double;
var
  I,J:Integer;
  E:TCrashEnemy;
begin Result:=-1;
  for I:=0 to High(Bosses) do begin if Bosses[I].Enemy<0 then Continue;
    E:=Enemies[Bosses[I].Enemy];
    if (Time<E.Spawn) or (Time>E.Clear) then Continue;
    J:=EnsureRange(HitBefore(Time)-E.First+1,0,E.Last-E.First+1);
    Exit(1-J/(E.Last-E.First+1));
  end;
end;

function TRaceCrashMotion.Excluded:Integer;
begin Result:=Length(Events)-Length(Hits);
end;
end.
