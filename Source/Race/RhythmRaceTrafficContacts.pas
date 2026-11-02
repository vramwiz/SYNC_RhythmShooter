unit RhythmRaceTrafficContacts;
// ボスと一般車の接触だけを事前計算する。音同期の自車攻撃時刻は変更しない。
interface
uses System.SysUtils,RhythmRaceCrashMotion;
// 各一般車の最初の接触を保存し、フレーム順序に依存しない撃破索引を作る。
procedure BuildTrafficContacts(Plan:TRaceCrashMotion;const Cancel:TFunc<Boolean>);
procedure ValidateTrafficContacts(Plan:TRaceCrashMotion;const Cancel:TFunc<Boolean>);
implementation
uses System.Math,System.Generics.Collections,System.Generics.Defaults,RhythmRaceTrafficPlan;
const
  CONTACT_EPS=1E-7;
type
  TBounds=record
    Lo,Hi:Double;
  end;

function Bounds(A,B:Double):TBounds;
begin Result.Lo:=Min(A,B);
  Result.Hi:=Max(A,B);
end;

function Product(const A,B:TBounds):TBounds;
begin Result.Lo:=Min(Min(A.Lo*B.Lo,A.Lo*B.Hi),Min(A.Hi*B.Lo,A.Hi*B.Hi));
  Result.Hi:=Max(Max(A.Lo*B.Lo,A.Lo*B.Hi),Max(A.Hi*B.Lo,A.Hi*B.Hi));
end;

function AbsBounds(const A:TBounds):TBounds;
begin Result:=Bounds(Abs(A.Lo),Abs(A.Hi));
  if A.Lo*A.Hi<=0 then Result.Lo:=0;
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function SinSquaredBounds(A,B:Double):TBounds;
begin
  Result:=Bounds(Sqr(Sin(A)),Sqr(Sin(B)));
  if Ceil(A/Pi)<=Floor(B/Pi) then Result.Lo:=0;
  if Ceil((A-Pi/2)/Pi)<=Floor((B-Pi/2)/Pi) then Result.Hi:=1;
end;

function Separation(const A,B:TCrashPose):Double;
begin Result:=Max(Abs(A.Lane-B.Lane)-A.Width-B.Width,
  Max(A.Distance-A.Back-B.Distance-B.Front,B.Distance-B.Back-A.Distance-A.Front));
end;

// 区間を包む範囲で離れている組だけを除外する。固定刻みの点検査で
// 短い接触を取りこぼさず、候補区間を左から細分化して最初の接触を求める。

function FirstContact(P:TRaceCrashMotion;Car,Boss:Integer;Start,Stop:Double;
  const Cancel:TFunc<Boolean>;out Contact:Double):Boolean;
var
  V:TCrashTraffic;
  E:TCrashEnemy;
  Calls:Integer;
  function IndependentDisjoint(A,B:Double):Boolean;
  var TL,TH,BL,BH,ZL,ZH,BZL,BZH,CZ,U0,U1,S0,S1:Double;J,K:Integer;H0,H1:TCrashHit;
  begin
    P.TrafficLaneBounds(Car,A,B,TL,TH);P.EnemyLaneBounds(Boss,A,B,BL,BH);
    if (TL>BH+V.Width+E.Width+CONTACT_EPS) or (BL>TH+V.Width+E.Width+CONTACT_EPS) then Exit(True);
    ZL:=V.RelativeSpeed*(V.Pass-B);ZH:=V.RelativeSpeed*(V.Pass-A);CZ:=P.HeroFront+E.HalfLength;
    if B<=E.Ready then begin
      BZL:=P.DistanceAt(E.Ready)+CZ-E.Speed*(E.Ready-A)-P.DistanceAt(B);
      BZH:=P.DistanceAt(E.Ready)+CZ-E.Speed*(E.Ready-B)-P.DistanceAt(A);
    end else begin
      J:=EnsureRange(P.HitBefore(A),E.First,E.Last);K:=EnsureRange(P.HitBefore(B),E.First,E.Last);
      S0:=0;S1:=1;
      if J=K then begin H0:=P.Hits[J];H1:=P.Hits[Min(J+1,E.Last)];
        if H1.Time>H0.Time then begin
          U0:=EnsureRange((A-H0.Time)/(H1.Time-H0.Time),0.0,1.0);U1:=EnsureRange((B-H0.Time)/(H1.Time-H0.Time),0.0,1.0);
          S0:=Min(Sin(Pi*U0),Sin(Pi*U1));S1:=Max(Sin(Pi*U0),Sin(Pi*U1));
          if (U0<=0.5) and (U1>=0.5) then S1:=1;
        end else begin S0:=0;S1:=0;end;
      end;
      BZL:=CZ+24*Sqr(S0);BZH:=CZ+24*Sqr(S1);
    end;
    Result:=(ZL>BZH+V.HalfLength+E.HalfLength+CONTACT_EPS) or (BZL>ZH+V.HalfLength+E.HalfLength+CONTACT_EPS);
  end;
  function Disjoint(A,B:Double):Boolean;
  var
    Hero,Raw,Blend,Target,Lane,Diff,Q,Z,BZ,BL,SinRange,Wave:TBounds;
    LowLane,HighLane,Bound,CZ,U1,U2,S1,S2:Double;
    J,K,Side:Integer;
    H1,H2:TCrashHit;
  begin
    if P.Version>=10 then Exit(IndependentDisjoint(A,B));
    P.LaneBounds(A,B,LowLane,HighLane);
    Hero:=Bounds(LowLane,HighLane);
    Raw:=Bounds(V.RelativeSpeed*(V.Pass-B),V.RelativeSpeed*(V.Pass-A));
    Diff:=AbsBounds(Raw);
    Blend:=Bounds(Smooth((130-Diff.Hi)/100),Smooth((130-Diff.Lo)/100));
    Bound:=P.HeroWidth+V.Width+V.Gap;
    Wave:=SinSquaredBounds((A-V.Pass)*1.7,(B-V.Pass)*1.7);
    Target:=Bounds(V.Side*(Bound+0.04*Wave.Lo),V.Side*(Bound+0.04*Wave.Hi));
    Target.Lo:=Target.Lo+Hero.Lo;
    Target.Hi:=Target.Hi+Hero.Hi;
    Diff:=Bounds(Target.Lo-V.FarLane,Target.Hi-V.FarLane);
    Lane:=Product(Diff,Blend);
    Lane.Lo:=EnsureRange(V.FarLane+Lane.Lo,-1+V.Width,1-V.Width);
    Lane.Hi:=EnsureRange(V.FarLane+Lane.Hi,-1+V.Width,1-V.Width);
    Diff:=AbsBounds(Bounds(Lane.Lo-Hero.Hi,Lane.Hi-Hero.Lo));
    Diff.Lo:=Diff.Lo-P.HeroWidth-V.Width;
    Diff.Hi:=Diff.Hi-P.HeroWidth-V.Width;
    Q:=Bounds(Smooth((V.Gap-Diff.Hi)/V.Gap),Smooth((V.Gap-Diff.Lo)/V.Gap));
    Bound:=Max(P.HeroFront,P.HeroBack)+V.HalfLength+2;
    if Raw.Lo>=0 then Z:=Bounds(Raw.Lo+Bound*Q.Lo,Raw.Hi+Bound*Q.Hi)
    else if Raw.Hi<=0 then Z:=Bounds(Raw.Lo-Bound*Q.Hi,Raw.Hi-Bound*Q.Lo)
    else Z:=Bounds(Raw.Lo-Bound*Q.Hi,Raw.Hi+Bound*Q.Hi);
    CZ:=P.HeroFront+E.HalfLength;
    if B<=E.Ready then begin
      BZ:=Bounds(P.DistanceAt(E.Ready)+CZ-E.Speed*(E.Ready-A)-P.DistanceAt(B),
      P.DistanceAt(E.Ready)+CZ-E.Speed*(E.Ready-B)-P.DistanceAt(A));
      BL:=Bounds(0.10*Sin(Boss*1.3)*Smooth((E.Ready-A)/0.7),
      0.10*Sin(Boss*1.3)*Smooth((E.Ready-B)/0.7));
    end else begin
      J:=EnsureRange(P.HitBefore(A),E.First,E.Last);
      K:=EnsureRange(P.HitBefore(B),E.First,E.Last);
      SinRange:=Bounds(0,1);
      if J=K then begin H1:=P.Hits[J];
        H2:=P.Hits[Min(J+1,E.Last)];
        if H2.Time>H1.Time then begin
          U1:=EnsureRange((A-H1.Time)/(H2.Time-H1.Time),0.0,1.0);
          U2:=EnsureRange((B-H1.Time)/(H2.Time-H1.Time),0.0,1.0);
          S1:=Sin(Pi*U1);
          S2:=Sin(Pi*U2);
          SinRange:=Bounds(S1,S2);
          if (U1<=0.5) and (U2>=0.5) then SinRange.Hi:=1;
        end else SinRange:=Bounds(0,0);
      end;
      BZ:=Bounds(CZ+24*Sqr(SinRange.Lo),CZ+24*Sqr(SinRange.Hi));
      if J=K then begin Side:=-1;
        if J mod 2=0 then Side:=1;
        BL:=Bounds(Side*0.12*SinRange.Lo,Side*0.12*SinRange.Hi);
      end else BL:=Bounds(-0.12,0.12);
    end;
    BL.Lo:=EnsureRange(Hero.Lo+BL.Lo,-1+E.Width,1-E.Width);
    BL.Hi:=EnsureRange(Hero.Hi+BL.Hi,-1+E.Width,1-E.Width);
    Result:=(Lane.Lo>BL.Hi+V.Width+E.Width+CONTACT_EPS) or
    (BL.Lo>Lane.Hi+V.Width+E.Width+CONTACT_EPS) or
    (Z.Lo>BZ.Hi+V.HalfLength+E.HalfLength+CONTACT_EPS) or
    (BZ.Lo>Z.Hi+V.HalfLength+E.HalfLength+CONTACT_EPS);
  end;
  function Search(A,B:Double;Depth:Integer):Boolean;
  var
    Mid:Double;
  begin
    Inc(Calls);
    if (Calls mod 256=0) and Assigned(Cancel) and Cancel() then Abort;
    Result:=False;
    if B<A then Exit;
    if (A<E.Ready) and (B>E.Ready) then begin
      if Search(A,E.Ready,Depth+1) then Exit(True);
      Exit(Search(E.Ready,B,Depth+1));
    end;
    if Disjoint(A,B) then Exit;
    if Separation(P.TrafficRoadAt(Car,A),P.EnemyAt(Boss,A))<=CONTACT_EPS then begin Contact:=A;
      Exit(True);
    end;
    Mid:=(A+B)*0.5;
    if (Depth>=40) or (B-A<1E-11) then begin
      if Separation(P.TrafficRoadAt(Car,Mid),P.EnemyAt(Boss,Mid))<=CONTACT_EPS then begin Contact:=Mid;
        Exit(True);
      end;
      if Separation(P.TrafficRoadAt(Car,B),P.EnemyAt(Boss,B))<=CONTACT_EPS then begin Contact:=B;
        Exit(True);
      end;
      Exit;
    end;
    if Search(A,Mid,Depth+1) then Exit(True);
    Result:=Search(Mid,B,Depth+1);
  end;
begin V:=P.Traffic[Car];
  E:=P.Enemies[Boss];
  Calls:=0;
  Result:=Search(Start,Stop,0);
end;

procedure BuildTrafficContacts(Plan:TRaceCrashMotion;const Cancel:TFunc<Boolean>);
var
  List:TList<TCrashShunt>;
  I,J,K,BestBoss:Integer;
  Start,Stop,Time,Best,OldLane,LeftGap,RightGap:Double;
  S:TCrashShunt;
  Car,Boss:TCrashPose;
  V:TCrashTraffic;
  E:TCrashEnemy;
begin
  List:=TList<TCrashShunt>.Create;
  try
    for I:=0 to High(Plan.Traffic) do begin
      if Assigned(Cancel) and Cancel() then Abort;
      // 新しい一般車が既に見えているボスの内部へ出現する場合は、
      // 遠方の進入車線を空いている側へ逆算する。近接時の認証経路と台数は保つ。
      for J:=0 to High(Plan.Bosses) do begin
        K:=Plan.Bosses[J].Enemy;
        if K<0 then Continue;
        E:=Plan.Enemies[K];
        V:=Plan.Traffic[I];
        Start:=Max(V.Spawn,E.Spawn);
        Stop:=Min(V.Clear,E.Kill);
        if Start>=Stop then Continue;
        if Separation(Plan.TrafficRoadAt(I,Start),Plan.EnemyAt(K,Start))>=0 then Continue;
        if Plan.Version>=10 then begin
          EnsureTrafficTurn(Plan,V);Plan.Traffic[I]:=V;
        end;
        OldLane:=V.FarLane;
        Plan.Traffic[I].FarLane:=-1+V.Width;
        LeftGap:=Separation(Plan.TrafficRoadAt(I,Start),Plan.EnemyAt(K,Start));
        Plan.Traffic[I].FarLane:=1-V.Width;
        RightGap:=Separation(Plan.TrafficRoadAt(I,Start),Plan.EnemyAt(K,Start));
        if LeftGap>RightGap then Plan.Traffic[I].FarLane:=-1+V.Width;
        if Max(LeftGap,RightGap)<=0 then begin Plan.Traffic[I].FarLane:=OldLane;
          raise Exception.Create('Race traffic entrance has no free lane');
        end;
      end;
      V:=Plan.Traffic[I];
      Plan.Traffic[I].Shunt:=-1;
      Best:=Plan.EndTime+1;
      BestBoss:=-1;
      for J:=0 to High(Plan.Bosses) do begin
        K:=Plan.Bosses[J].Enemy;
        if K<0 then Continue;
        E:=Plan.Enemies[K];
        Start:=Max(V.Spawn,E.Spawn);
        Stop:=Min(Min(V.Clear,E.Kill-1E-8),Best);
        if Start>=Stop then Continue;
        if FirstContact(Plan,I,K,Start,Stop,Cancel,Time) then begin Best:=Time;
          BestBoss:=K;
        end;
      end;
      if BestBoss<0 then Continue;
      S:=Default(TCrashShunt);
      S.Time:=Best;
      S.Traffic:=I;
      S.Enemy:=BestBoss;
      Car:=Plan.TrafficRoadAt(I,Best);
      Boss:=Plan.EnemyAt(BestBoss,Best);
      S.Distance:=(Max(Car.Distance-Car.Back,Boss.Distance-Boss.Back)+
      Min(Car.Distance+Car.Front,Boss.Distance+Boss.Front))*0.5;
      S.Lane:=(Max(Car.Lane-Car.Width,Boss.Lane-Boss.Width)+
      Min(Car.Lane+Car.Width,Boss.Lane+Boss.Width))*0.5;
      S.Side:=1;
      if Car.Lane<Plan.LaneAt(Best) then S.Side:=-1;
      List.Add(S);
    end;
    List.Sort(TComparer<TCrashShunt>.Construct(function(const A,B:TCrashShunt):Integer
    begin Result:=CompareValue(A.Time,B.Time,0);if Result=0 then Result:=A.Traffic-B.Traffic;end));
    Plan.Shunts:=List.ToArray;
    for I:=0 to High(Plan.Shunts) do Plan.Traffic[Plan.Shunts[I].Traffic].Shunt:=I;
  finally List.Free;
  end;
end;

procedure ValidateTrafficContacts(Plan:TRaceCrashMotion;const Cancel:TFunc<Boolean>);
var
  I:Integer;
  S:TCrashShunt;
  A,B:TCrashPose;
  Z,L:Double;
begin
  if Length(Plan.Shunts)>Length(Plan.Traffic) then raise Exception.Create('Race traffic contact limit');
  for I:=0 to High(Plan.Shunts) do begin
    if Assigned(Cancel) and Cancel() then Abort;
    S:=Plan.Shunts[I];
    if (S.Traffic<0) or (S.Traffic>=Length(Plan.Traffic)) or (S.Enemy<0) or
    (S.Enemy>=Length(Plan.Enemies)) then raise Exception.Create('Race traffic contact link');
    if (Plan.Traffic[S.Traffic].Shunt<>I) or (Plan.Enemies[S.Enemy].Boss<0) or
    IsNan(S.Time) or IsInfinite(S.Time) or IsNan(S.Distance) or IsInfinite(S.Distance) or
    IsNan(S.Lane) or IsInfinite(S.Lane) or ((S.Side<>-1) and (S.Side<>1)) or
    (S.Time<Max(Plan.Traffic[S.Traffic].Spawn,Plan.Enemies[S.Enemy].Spawn)) or
    (S.Time>=Min(Plan.Traffic[S.Traffic].Clear,Plan.Enemies[S.Enemy].Kill)) then
    raise Exception.Create('Race traffic contact clock/index');
    if I>0 then if S.Time<Plan.Shunts[I-1].Time then raise Exception.Create('Race traffic contact order');
    A:=Plan.TrafficRoadAt(S.Traffic,S.Time);
    B:=Plan.EnemyAt(S.Enemy,S.Time);
    if Abs(Separation(A,B))>2E-6 then raise Exception.CreateFmt('Race traffic contact misses body gap=%.9f t=%.9f car=%d boss=%d spawn=%.9f/%.9f',[Separation(A,B),S.Time,S.Traffic,S.Enemy,Plan.Traffic[S.Traffic].Spawn,Plan.Enemies[S.Enemy].Spawn]);
    Z:=A.Distance-Plan.DistanceAt(S.Time);
    L:=Abs(A.Lane-Plan.LaneAt(S.Time));
    // v10は固定接触点から外へ3.8車線/秒以上。自車の最大0.975より速く隙間が広がる。
    if not ((Z-A.Back>=Plan.HeroFront) or (Z+A.Front<=-Plan.HeroBack) or
    (L>A.Width+Plan.HeroWidth)) then raise Exception.Create('Race shunt overlaps hero');
  end;
end;
end.
