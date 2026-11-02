unit RhythmBombPlan;
// このスタイルの全曲事前計画と保存互換を担当し、描画からの再解析を行わない。
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef;
const
  BA_HERO_RADIUS=0.18;
  BA_BOMB_RADIUS=0.085;
  BA_BLAST_PAD=0.05;
  BA_FUSE=0.78;
  BA_DODGE_RESERVE=0.11;
type
  TBAPoint=record
    X,Y:Double;
  end;
  TBAEvent=record
    Time,Strength:Double;
  end;
  TBABomb=record
    Time,Place,Radius,Life,Strength,Angle,WaveSpeed:Double;
    Position:TBAPoint;
    Source,Pattern,Parent,Child,Boss,Target:Integer;
  end;
  TBATarget=record
    Position:TBAPoint;
    Show,Kill,Radius:Double;
    Kind,Bomb:Integer;
  end;
  TBABoss=record
    Show,Kill,Radius:Double;
    FirstBomb,LastBomb:Integer;
  end;
  TBAShot=record
    Start,Finish,Radius:Double;
    Position,Velocity:TBAPoint;
    Boss:Integer;
  end;
  TBACharge=record
    Time,Place,Radius,Life:Double;
    Position:TBAPoint;
    Bomb,Pattern:Integer;
  end;
  TBACrowdEnemy=record
    Show,Kill,Radius:Double;
    Position,Entry:TBAPoint;
    Bomb,Charge,Kind:Integer;
  end;
  TBAEnemyShot=record
    Start,Finish:Double;
    Position,Velocity:TBAPoint;
    Foe:Integer;
  end;
  TBombActionPlan=class
  private
    FEvents:TArray<TBAEvent>;
    FBombs:TArray<TBABomb>;
    FTargets:TArray<TBATarget>;
    FBosses:TArray<TBABoss>;
    FShots:TArray<TBAShot>;
    FDuration,FSoundEnd,FEnd,FLaunch,FAccel,FGoal:Double;
    FFrequency,FExcluded:Integer;
    FSeed:Cardinal;
    FCharges:TArray<TBACharge>;
    FCrowd:TArray<TBACrowdEnemy>;
    FRaids:TArray<TBAEnemyShot>;
    FCrowdKills:TArray<Integer>;
    FVersion:Integer;
    procedure MakeCrowd(const Cancel:TFunc<Boolean>);
    procedure ValidateCrowd(const Cancel:TFunc<Boolean>);
    function CrowdSafe(const Enemy:TBACrowdEnemy):Boolean;
    function RaidSafe(const Shot:TBAEnemyShot):Boolean;
    function GetChargeCount:Integer;
    function GetCrowdCount:Integer;
    function GetRaidCount:Integer;
    function GetCharge(Index:Integer):TBACharge;
    function GetCrowd(Index:Integer):TBACrowdEnemy;
    function GetRaid(Index:Integer):TBAEnemyShot;
    function Travel(Time:Double):Double;
    procedure Validate(const Cancel:TFunc<Boolean> = nil);
    procedure MakeBosses(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
    procedure MakeTargets(const Cancel:TFunc<Boolean>);
    procedure MakeShots(const Cancel:TFunc<Boolean>);
    function ClearShot(const Shot:TBAShot):Boolean;
    function GetCount:Integer;
    function GetTargetCount:Integer;
    function GetBossCount:Integer;
    function GetShotCount:Integer;
    function GetBomb(Index:Integer):TBABomb;
    function GetTarget(Index:Integer):TBATarget;
    function GetBoss(Index:Integer):TBABoss;
    function GetShot(Index:Integer):TBAShot;
  public
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TBombActionPlan; static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TBombActionPlan; static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio; static;
    function HeroAt(Time:Double):TBAPoint;
    function HeroVelocity(Time:Double):TBAPoint;
    function BossAt(Index:Integer;Time:Double):TBAPoint;
    function BossHP(Index:Integer;Time:Double):Integer;
    function BombBefore(Time:Double):Integer;
    function TargetBefore(Time:Double):Integer;
    function ShotBefore(Time:Double):Integer;
    function BlastRadius(Index:Integer;Time:Double):Double;
    function BlastHits(Index:Integer;const Point:TBAPoint;Radius:Double;Time:Double):Boolean;
    function ChainCount:Integer;
    function ChargeBefore(Time:Double):Integer;
    function CrowdBefore(Time:Double):Integer;
    function RaidBefore(Time:Double):Integer;
    function CrowdAt(Index:Integer;Time:Double):TBAPoint;
    function CrowdDestroyed(Time:Double):Integer;
    property ChargeCount:Integer read GetChargeCount;
    property Charges[Index:Integer]:TBACharge read GetCharge;
    property CrowdCount:Integer read GetCrowdCount;
    property Crowd[Index:Integer]:TBACrowdEnemy read GetCrowd;
    property RaidCount:Integer read GetRaidCount;
    property Raids[Index:Integer]:TBAEnemyShot read GetRaid;
    property Count:Integer read GetCount;
    property Bomb[Index:Integer]:TBABomb read GetBomb;
    property TargetCount:Integer read GetTargetCount;
    property Target[Index:Integer]:TBATarget read GetTarget;
    property BossCount:Integer read GetBossCount;
    property Boss[Index:Integer]:TBABoss read GetBoss;
    property ShotCount:Integer read GetShotCount;
    property Shot[Index:Integer]:TBAShot read GetShot;
    property EndTime:Double read FEnd;
    property LaunchTime:Double read FLaunch;
    property GoalTime:Double read FGoal;
    property Version:Integer read FVersion;
    property Excluded:Integer read FExcluded;
    property Frequency:Integer read FFrequency;
    property Seed:Cardinal read FSeed;
  end;
function BAV(X,Y:Double):TBAPoint;
function BAAdd(const A,B:TBAPoint):TBAPoint;
function BASub(const A,B:TBAPoint):TBAPoint;
function BAScale(const A:TBAPoint;Scale:Double):TBAPoint;
function BALength(const A:TBAPoint):Double;
function BAUnit(const A:TBAPoint):TBAPoint;
function BANormal(const A:TBAPoint):TBAPoint;
implementation
uses System.Math,System.JSON,System.Generics.Collections,System.Generics.Defaults,RhythmStyles,RhythmPreparedData;

function BAV(X,Y:Double):TBAPoint;
begin Result.X:=X;
  Result.Y:=Y;
end;

function BAAdd(const A,B:TBAPoint):TBAPoint;
begin Result:=BAV(A.X+B.X,A.Y+B.Y);
end;

function BASub(const A,B:TBAPoint):TBAPoint;
begin Result:=BAV(A.X-B.X,A.Y-B.Y);
end;

function BAScale(const A:TBAPoint;Scale:Double):TBAPoint;
begin Result:=BAV(A.X*Scale,A.Y*Scale);
end;

function BALength(const A:TBAPoint):Double;
begin Result:=Hypot(A.X,A.Y);
end;

function BAUnit(const A:TBAPoint):TBAPoint;
var
  L:Double;
begin L:=BALength(A);
  if L<1E-9 then Exit(BAV(1,0));
  Result:=BAScale(A,1/L);
end;

function BANormal(const A:TBAPoint):TBAPoint;
begin Result:=BAV(-A.Y,A.X);
end;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

function FinitePoint(const P:TBAPoint):Boolean;
begin Result:=Finite(P.X) and Finite(P.Y);
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function AngleDifference(A,B:Double):Double;
begin Result:=ArcTan2(Sin(A-B),Cos(A-B));
end;

function SegmentDistance(const P,A,B:TBAPoint):Double;
var
  D,Q:TBAPoint;
  U,L:Double;
begin D:=BASub(B,A);
  Q:=BASub(P,A);
  L:=Sqr(D.X)+Sqr(D.Y);
  U:=0;
  if L>1E-12 then U:=EnsureRange((Q.X*D.X+Q.Y*D.Y)/L,0.0,1.0);
  Result:=BALength(BASub(Q,BAScale(D,U)));
end;

function SourceSeed(const Key:string):Cardinal;
begin Result:=Cardinal(StrToInt64Def('$'+Copy(Key,1,8),0));
end;

function TBombActionPlan.Travel(Time:Double):Double;
var
  T,U,A,Tail:Double;
begin T:=EnsureRange(Time,0.0,FEnd);
  Result:=0;
  if T<=FLaunch then Exit;
  A:=FLaunch+FAccel;
  if T<A then begin U:=(T-FLaunch)/FAccel;
    Exit(FAccel*(U*U*U-0.5*U*U*U*U));
  end;
  Result:=0.5*FAccel+Min(T,FGoal)-A;
  if T>FGoal then begin Tail:=FEnd-FGoal;
    U:=(T-FGoal)/Tail;
    Result:=Result+Tail*(U-U*U*U+0.5*U*U*U*U);
  end;
end;

function TBombActionPlan.HeroAt(Time:Double):TBAPoint;
var
  A:Double;
begin A:=Travel(Time);
  Result:=BAV(2.8*A+0.10*Sin(3*A)+0.05*Sin(7*A),1.10*(Sin(0.65*A+0.35)-Sin(0.35))+0.22*Sin(1.8*A));
end;

function TBombActionPlan.HeroVelocity(Time:Double):TBAPoint;
begin Result:=BAScale(BASub(HeroAt(Time+0.002),HeroAt(Time-0.002)),250);
end;

function TBombActionPlan.BossAt(Index:Integer;Time:Double):TBAPoint;
var
  T:Double;
  D:TBAPoint;
begin T:=EnsureRange(Time,FBosses[Index].Show,FBosses[Index].Kill)-BA_FUSE;
  D:=BANormal(BAUnit(HeroVelocity(T)));
  Result:=BAAdd(HeroAt(T),BAScale(D,0.82));
end;

function TBombActionPlan.BossHP(Index:Integer;Time:Double):Integer;
var
  B:TBABoss;
  Hits:Integer;
begin B:=FBosses[Index];
  Hits:=EnsureRange(BombBefore(Time)-B.FirstBomb+1,0,B.LastBomb-B.FirstBomb+1);
  Result:=B.LastBomb-B.FirstBomb+1-Hits;
end;

function TBombActionPlan.BombBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Count;
  while A<B do begin M:=(A+B) div 2;
    if FBombs[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBombActionPlan.ShotBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=ShotCount;
  while A<B do begin M:=(A+B) div 2;
    if FShots[M].Start<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBombActionPlan.TargetBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=TargetCount;
  while A<B do begin M:=(A+B) div 2;
    if FTargets[M].Kill<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBombActionPlan.BlastRadius(Index:Integer;Time:Double):Double;
var
  B:TBABomb;
  Age:Double;
begin B:=FBombs[Index];
  Age:=Time-B.Time;
  Result:=0;
  if (Age<0) or (Age>B.Life+0.22) then Exit;
  Result:=B.Radius;
  if B.Child>=0 then Result:=Min(Result,Max(0.0,Age*B.WaveSpeed));
end;

function TBombActionPlan.BlastHits(Index:Integer;const Point:TBAPoint;Radius:Double;Time:Double):Boolean;
var
  B:TBABomb;
  Q,A,C:TBAPoint;
  R,D,Theta,U,LastR:Double;
  I:Integer;
begin
  B:=FBombs[Index];
  R:=BlastRadius(Index,Time);
  Q:=BASub(Point,B.Position);
  D:=BALength(Q);
  Result:=False;
  if (R<=0) or (Time>B.Time+B.Life) or (D>R+Radius) then Exit;
  Theta:=ArcTan2(Q.Y,Q.X);
  case B.Pattern of
    0:Result:=True;
    1:Result:=(D<=0.20+Radius) or (Abs(AngleDifference(Theta,B.Angle))<=0.65+ArcSin(Min(1.0,Radius/Max(D,0.001))));
    2:begin LastR:=R*0.68;
      if B.Child>=0 then LastR:=Max(0.0,R-0.10);
      Result:=D+Radius>=LastR;
    end;
    3:begin
      if D<=0.20+Radius then Exit(True);
      for I:=-1 to 1 do begin U:=B.Angle+I*0.35;
        A:=BAV(0,0);
        C:=BAV(Cos(U)*(R-0.04),Sin(U)*(R-0.04));
        if SegmentDistance(Q,A,C)<=Radius+0.045 then Exit(True);
      end;
    end;
    4:begin
      A:=BAV(0,0);
      for I:=1 to 40 do begin LastR:=(R-0.04)*I/40;
        U:=B.Angle+2*Pi*I/40;
        C:=BAV(Cos(U)*LastR,Sin(U)*LastR);
        if SegmentDistance(Q,A,C)<=Radius+0.03 then Exit(True);
        A:=C;
      end;
    end;
  end;
end;

function TBombActionPlan.GetCount:Integer;
begin Result:=Length(FBombs);
end;

function TBombActionPlan.GetTargetCount:Integer;
begin Result:=Length(FTargets);
end;

function TBombActionPlan.GetBossCount:Integer;
begin Result:=Length(FBosses);
end;

function TBombActionPlan.GetShotCount:Integer;
begin Result:=Length(FShots);
end;

function TBombActionPlan.GetBomb(Index:Integer):TBABomb;
begin Result:=FBombs[Index];
end;

function TBombActionPlan.GetTarget(Index:Integer):TBATarget;
begin Result:=FTargets[Index];
end;

function TBombActionPlan.GetBoss(Index:Integer):TBABoss;
begin Result:=FBosses[Index];
end;

function TBombActionPlan.GetShot(Index:Integer):TBAShot;
begin Result:=FShots[Index];
end;

function TBombActionPlan.ChainCount:Integer;
var
  B:TBABomb;
begin Result:=0;
  for B in FBombs do if B.Parent>=0 then Inc(Result);
end;

procedure TBombActionPlan.MakeBosses(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
var
  List:TList<TBABoss>;
  I,J,First,Last:Integer;
  Start,Stop,Previous:Double;
  B:TBABoss;
  D:TBAPoint;
begin
  List:=TList<TBABoss>.Create;
  try Previous:=-5;
    for I:=0 to Audio.BossCount-1 do begin if Assigned(Cancel) and Cancel() then Abort;
      Start:=Max(Max(Audio.BossCue(I).StartTime,FLaunch+FAccel+1),Previous+4);
      Stop:=Min(Audio.BossCue(I).KillTime,FEnd-0.65);
      First:=BombBefore(Start+0.60)+1;
      Last:=BombBefore(Stop);
      if (First>=Count) or (Last-First<2) then Continue;
      B.FirstBomb:=First;
      B.LastBomb:=Last;
      B.Show:=Max(Start,FBombs[First].Time-1.2);
      B.Kill:=FBombs[Last].Time;
      B.Radius:=0.50;
      if (B.Kill-B.Show<2.0) or (List.Count>=256) then Continue;
      while (First>0) and (FBombs[First-1].Time>=B.Show) do Dec(First);
      B.FirstBomb:=First;
      List.Add(B);
      Previous:=B.Kill;
      for J:=First to Last do FBombs[J].Boss:=List.Count-1;
    end;
    FBosses:=List.ToArray;
    for I:=0 to Count-1 do if FBombs[I].Boss>=0 then begin
      D:=BASub(BossAt(FBombs[I].Boss,FBombs[I].Time),FBombs[I].Position);
      FBombs[I].Pattern:=(I mod 3);
      if FBombs[I].Pattern=2 then FBombs[I].Pattern:=3;
      FBombs[I].Angle:=ArcTan2(D.Y,D.X);
    end;
  finally List.Free;
  end;
end;

procedure TBombActionPlan.MakeTargets(const Cancel:TFunc<Boolean>);
var
  List:TList<TBATarget>;
  I,J,K,Step,Steps:Integer;
  B:TBABomb;
  T:TBATarget;
  Direction:TBAPoint;
  Angle,Dist,Clock:Double;
  Good:Boolean;
begin
  List:=TList<TBATarget>.Create;
  try
    for I:=0 to Count-1 do begin if Assigned(Cancel) and Cancel() then Abort;
      B:=FBombs[I];
      if (B.Child>=0) or (B.Boss>=0) then Continue;
      T.Bomb:=I;
      T.Kill:=B.Time;
      T.Show:=Max(0.0,B.Time-0.50);
      T.Kind:=(I+Round(B.Strength*3)) mod 3;
      T.Radius:=0.12;
      if T.Kind=2 then T.Radius:=0.20;
      Direction:=BAUnit(HeroVelocity(B.Place));
      Good:=False;
      for K:=0 to 11 do begin Angle:=ArcTan2(Direction.Y,Direction.X)+(0.25+0.10*(K div 2))*(1-2*(K mod 2));
        Dist:=B.Radius+T.Radius*0.40;
        T.Position:=BAAdd(B.Position,BAV(Cos(Angle)*Dist,Sin(Angle)*Dist));
        Good:=True;
        for J:=Max(0,I-12) to I-1 do if FBombs[J].Time+FBombs[J].Life+0.22>=T.Show then
        if BALength(BASub(T.Position,FBombs[J].Position))<=FBombs[J].Radius+BA_BLAST_PAD+T.Radius then Good:=False;
        if not Good then Continue;
        Steps:=Ceil((T.Kill+0.30-T.Show)/0.015);
        for Step:=0 to Steps do begin Clock:=T.Show+(T.Kill+0.30-T.Show)*Step/Steps;
          if BALength(BASub(T.Position,HeroAt(Clock)))<BA_HERO_RADIUS+T.Radius+0.09 then begin Good:=False;
            Break;
          end;
        end;
        if Good then Break;
      end;
      if not Good then Continue;
      FBombs[I].Angle:=ArcTan2(T.Position.Y-B.Position.Y,T.Position.X-B.Position.X);
      if B.Pattern=4 then FBombs[I].Angle:=FBombs[I].Angle-2*Pi*Min(Dist,B.Radius-0.04)/(B.Radius-0.04);
      FBombs[I].Target:=List.Count;
      List.Add(T);
    end;
    FTargets:=List.ToArray;
  finally List.Free;
  end;
end;

function TBombActionPlan.ClearShot(const Shot:TBAShot):Boolean;
var
  I,N:Integer;
  T:Double;
  P:TBAPoint;
begin Result:=False;
  if BALength(Shot.Velocity)>12 then Exit;
  N:=Ceil((Shot.Finish-Shot.Start)/0.01);
  for I:=0 to N do begin T:=Shot.Start+(Shot.Finish-Shot.Start)*I/N;
    P:=BAAdd(Shot.Position,BAScale(Shot.Velocity,T-Shot.Start));
    if BALength(BASub(P,HeroAt(T)))<0.42 then Exit;
  end;
  Result:=True;
end;

procedure TBombActionPlan.MakeShots(const Cancel:TFunc<Boolean>);
var
  List:TList<TBAShot>;
  I,J,Lane,TryNo:Integer;
  S:TBAShot;
  P,N:TBAPoint;
  Side,Offset:Double;
begin
  List:=TList<TBAShot>.Create;
  try
    for I:=0 to BossCount-1 do for J:=FBosses[I].FirstBomb to FBosses[I].LastBomb-1 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      if (J-FBosses[I].FirstBomb) mod 3<>0 then Continue;
      for Lane:=0 to 2 do begin S.Start:=FBombs[J].Time;
        S.Finish:=Min(S.Start+0.70,FBosses[I].Kill+0.12);
        S.Radius:=0.12;
        S.Boss:=I;
        if S.Finish-S.Start<0.15 then Continue;
        S.Position:=BossAt(I,S.Start);
        P:=HeroAt(S.Start+0.42);
        N:=BANormal(BAUnit(HeroVelocity(S.Start+0.42)));
        Side:=1;
        if (J+Lane) mod 2=0 then Side:=-1;
        for TryNo:=0 to 7 do begin Offset:=Side*(0.39+Lane*0.23+TryNo*0.12);
          S.Velocity:=BAScale(BASub(BAAdd(P,BAScale(N,Offset)),S.Position),1/0.42);
          if ClearShot(S) then begin List.Add(S);
            Break;
          end;
        end;
      end;
    end;
    FShots:=List.ToArray;
  finally List.Free;
  end;
end;

class function TBombActionPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TBombActionPlan;
var
  List:TList<TBABomb>;
  B:TBABomb;
  I,Best:Integer;
  T,WindowEnd,Last,Previous,Gap,Dist:Double;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
  procedure Commit;
  begin
    if Best<0 then Exit;
    B:=Default(TBABomb);
    B.Source:=Best;
    B.Time:=Result.FEvents[Best].Time;
    B.Strength:=Result.FEvents[Best].Strength;
    B.Place:=B.Time-BA_FUSE;
    B.Position:=Result.HeroAt(B.Place);
    Dist:=BALength(BASub(Result.HeroAt(B.Time),B.Position));
    B.Radius:=Min(2.45,Dist-BA_HERO_RADIUS-BA_DODGE_RESERVE-0.10*(1-B.Strength));
    B.Life:=0.24+0.12*B.Strength;
    B.Pattern:=(List.Count+Round(B.Strength*4)) mod 5;
    B.Angle:=List.Count*0.73;
    B.Parent:=-1;
    B.Child:=-1;
    B.Target:=-1;
    B.Boss:=-1;
    if B.Radius>=0.60 then begin List.Add(B);
      Last:=B.Time;
    end;
    Best:=-1;
  end;
begin
  Result:=nil;
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.Duration>512.0*1024*1024/4/RHYTHM_RATE) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then raise Exception.Create('Invalid bomb-action audio');
  List:=TList<TBABomb>.Create;
  try Result:=TBombActionPlan.Create;
    try
      Result.FVersion:=2;
      Result.FDuration:=Audio.Duration;
      Result.FSoundEnd:=Audio.SoundEnd;
      Result.FEnd:=Audio.Duration;
      if Audio.SoundEnd>0 then Result.FEnd:=Audio.SoundEnd;
      Result.FLaunch:=Min(0.55,Result.FEnd*0.08);
      Result.FGoal:=Result.FEnd-Min(0.80,Result.FEnd*0.12);
      Result.FAccel:=Min(0.75,(Result.FGoal-Result.FLaunch)*0.20);
      Result.FFrequency:=Audio.BossFrequency;
      Result.FSeed:=SourceSeed(Audio.Key);
      SetLength(Result.FEvents,Length(Audio.Hits));
      Previous:=-1;
      for I:=0 to High(Audio.Hits) do begin Check;
        if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or (Audio.Hits[I].Time<Previous) or (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('Invalid bomb-action accents');
        Result.FEvents[I].Time:=Audio.Hits[I].Time;
        Result.FEvents[I].Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);
        Previous:=Audio.Hits[I].Time;
      end;
      Best:=-1;
      WindowEnd:=0;
      Last:=-1;
      for I:=0 to High(Result.FEvents) do begin Check;
        T:=Result.FEvents[I].Time;
        if (T<Result.FLaunch+Result.FAccel+0.82) or (T>Result.FEnd-0.65) or (T>Audio.SoundEnd) then Continue;
        if (Best>=0) and (T>=WindowEnd) then Commit;
        if Best<0 then begin if (Last>=0) and (T-Last<0.18) then Continue;
          Best:=I;
          WindowEnd:=T+0.18;
        end
        else if Result.FEvents[I].Strength>Result.FEvents[Best].Strength then Best:=I;
      end;
      Commit;
      Result.FBombs:=List.ToArray;
      Result.FExcluded:=Length(Result.FEvents)-Result.Count;
      Result.MakeBosses(Audio,Cancel);
      for I:=1 to Result.Count-1 do begin Check;
        Gap:=Result.FBombs[I].Time-Result.FBombs[I-1].Time;
        Dist:=BALength(BASub(Result.FBombs[I].Position,Result.FBombs[I-1].Position));
        if (I mod 4<>0) and (Result.FBombs[I].Boss<0) and (Result.FBombs[I-1].Boss<0) and (Gap<=0.44) and (Dist>=0.30) and (Dist-BA_BOMB_RADIUS<=Result.FBombs[I-1].Radius) and (Result.FBombs[I].Place<=Result.FBombs[I-1].Time) then begin
          Result.FBombs[I].Parent:=I-1;
          Result.FBombs[I-1].Child:=I;
          Result.FBombs[I-1].Pattern:=2;
          Result.FBombs[I-1].WaveSpeed:=(Dist-BA_BOMB_RADIUS)/Gap;
          Result.FBombs[I-1].Life:=Max(Result.FBombs[I-1].Life,Gap+0.03);
        end;
      end;
      Result.MakeTargets(Cancel);
      Result.MakeShots(Cancel);
      Result.MakeCrowd(Cancel);
      Result.Validate(Cancel);
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally List.Free;
  end;
end;

procedure TBombActionPlan.Validate(const Cancel:TFunc<Boolean>);
var
  I,J,K,N:Integer;
  T,D,Gap:Double;
  B,C:TBABomb;
  Target:TBATarget;
  Boss:TBABoss;
  Shot:TBAShot;
  P:TBAPoint;
  procedure Need(Value:Boolean;const Why:string);
  begin if not Value then raise Exception.Create('Bomb action: '+Why);
  end;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
begin
  Need(Finite(FDuration) and (FDuration>0) and (FDuration<=512.0*1024*1024/4/RHYTHM_RATE) and Finite(FSoundEnd) and (FSoundEnd>=0) and (FSoundEnd<=FDuration),'audio');
  Need(Finite(FEnd) and (FEnd>0) and (FEnd<=FDuration) and Finite(FLaunch) and Finite(FAccel) and Finite(FGoal) and (FLaunch>=0) and (FAccel>0) and (FLaunch+FAccel<FGoal) and (FGoal<FEnd),'timeline');
  if FSoundEnd>0 then Need(FEnd=FSoundEnd,'audible end') else Need(FEnd=FDuration,'silent end');
  Need((Length(FEvents)<=100000) and (Count<=20000) and (TargetCount<=20000) and (BossCount<=256) and (ShotCount<=12000) and (FExcluded>=0) and (Count+FExcluded=Length(FEvents)) and (FFrequency>=0) and (FFrequency<=100),'counts');
  if FFrequency=0 then Need(BossCount=0,'boss disabled');
  for I:=0 to High(FEvents) do begin Check;
    Need(Finite(FEvents[I].Time) and Finite(FEvents[I].Strength) and (FEvents[I].Time>=0) and (FEvents[I].Time<=FDuration+0.011) and (FEvents[I].Strength>=0) and (FEvents[I].Strength<=1),'source');
    if I>0 then Need(FEvents[I].Time>=FEvents[I-1].Time,'source order');
  end;
  for I:=0 to Count-1 do begin Check;
    B:=FBombs[I];
    Need(Finite(B.Time) and Finite(B.Place) and Finite(B.Radius) and Finite(B.Life) and Finite(B.Strength) and Finite(B.Angle) and Finite(B.WaveSpeed) and FinitePoint(B.Position),'bomb finite');
    Need((B.Source>=0) and (B.Source<Length(FEvents)) and (B.Parent>=-1) and (B.Child>=-1) and (B.Boss>=-1) and (B.Target>=-1),'bomb index');
    Need((B.Time=FEvents[B.Source].Time) and (B.Strength=FEvents[B.Source].Strength) and (Abs(B.Place-(B.Time-BA_FUSE))<1E-8) and (B.Time>=FLaunch+FAccel+0.82) and (B.Time<=FEnd-0.65) and (B.Time<=FSoundEnd),'changed accent');
    Need((B.Pattern>=0) and (B.Pattern<=4) and (B.Radius>=0.60) and (B.Radius<=2.45) and (B.Life>=0.24) and (B.Life<=0.48) and (Abs(B.Angle)<1E8),'blast geometry');
    Need(B.Time+B.Life+0.22<=FEnd+1E-7,'unfinished blast');
    Need(BALength(BASub(B.Position,HeroAt(B.Place)))<1E-7,'planting position');
    if I>0 then Need((B.Source>FBombs[I-1].Source) and (B.Time-FBombs[I-1].Time>=0.18-1E-8),'bomb order');
    if B.Child>=0 then begin Need((B.Child=I+1) and (B.Child<Count) and (B.Pattern=2) and (B.Boss<0),'chain child');
      C:=FBombs[B.Child];
      Gap:=C.Time-B.Time;
      D:=BALength(BASub(C.Position,B.Position));
      Need((C.Parent=I) and (C.Place<=B.Time) and (Gap<=0.44) and (Gap>0) and (D>=0.30) and (B.Life>=Gap+0.03-1E-8) and (Abs(B.WaveSpeed-(D-BA_BOMB_RADIUS)/Gap)<1E-7),'chain propagation');
      Need(Abs(BlastRadius(I,C.Time)-(D-BA_BOMB_RADIUS))<1E-7,'chain clock');
    end else Need(B.WaveSpeed=0,'unlinked wave');
    if B.Parent>=0 then Need((B.Parent=I-1) and (FBombs[B.Parent].Child=I),'chain parent');
    N:=Ceil((B.Life+0.22)/0.012);
    for J:=0 to N do begin T:=B.Time+(B.Life+0.22)*J/N;
      Need(BALength(BASub(HeroAt(T),B.Position))>B.Radius+BA_BLAST_PAD+BA_HERO_RADIUS+0.03,'visible blast hits hero');
    end;
    if B.Boss>=0 then begin Need((B.Boss<BossCount) and (B.Child<0),'boss reference');
      P:=BossAt(B.Boss,B.Time);
      Need(BlastHits(I,P,FBosses[B.Boss].Radius,B.Time),'missed boss hit');
    end;
    if B.Target>=0 then Need((B.Target<TargetCount) and (FTargets[B.Target].Bomb=I),'target reference');
  end;
  for I:=0 to TargetCount-1 do begin Check;
    Target:=FTargets[I];
    Need(FinitePoint(Target.Position) and Finite(Target.Show) and Finite(Target.Kill) and Finite(Target.Radius) and (Target.Bomb>=0) and (Target.Bomb<Count) and (Target.Kind in [0,1,2]) and (Target.Radius>=0.12) and (Target.Radius<=0.20),'target');
    B:=FBombs[Target.Bomb];
    Need((B.Target=I) and (Target.Kill=B.Time) and (Target.Show>=0) and (Abs(Target.Show-Max(0.0,Target.Kill-0.50))<1E-7) and BlastHits(Target.Bomb,Target.Position,Target.Radius,Target.Kill),'target destruction');
    if I>0 then Need(Target.Kill>FTargets[I-1].Kill,'target order');
    for K:=Max(0,Target.Bomb-12) to Target.Bomb-1 do if FBombs[K].Time+FBombs[K].Life+0.22>=Target.Show then Need(BALength(BASub(Target.Position,FBombs[K].Position))>FBombs[K].Radius+BA_BLAST_PAD+Target.Radius,'prior target hit');
    N:=Ceil((Target.Kill+0.30-Target.Show)/0.012);
    for J:=0 to N do begin T:=Target.Show+(Target.Kill+0.30-Target.Show)*J/N;
      Need(BALength(BASub(Target.Position,HeroAt(T)))>BA_HERO_RADIUS+Target.Radius+0.06,'target contact');
    end;
  end;
  for I:=0 to BossCount-1 do begin Check;
    Boss:=FBosses[I];
    Need(Finite(Boss.Show) and Finite(Boss.Kill) and Finite(Boss.Radius) and (Boss.Show>=FLaunch+FAccel+1) and (Boss.Kill<=FEnd-0.65) and (Boss.Kill-Boss.Show>=2) and (Boss.Radius=0.50) and (Boss.FirstBomb>=0) and (Boss.LastBomb<Count) and (Boss.LastBomb-Boss.FirstBomb>=2),'boss');
    Need((Boss.Kill=FBombs[Boss.LastBomb].Time) and (FBombs[Boss.FirstBomb].Time>=Boss.Show) and (BossHP(I,Boss.Kill)=0),'boss defeat');
    if I>0 then Need(Boss.Show>=FBosses[I-1].Kill+4,'boss overlap');
    if Boss.FirstBomb>0 then Need(FBombs[Boss.FirstBomb-1].Time<Boss.Show,'missed boss hit');
    for J:=Boss.FirstBomb to Boss.LastBomb do Need(FBombs[J].Boss=I,'boss hit list');
    N:=Ceil((Boss.Kill+0.50-Boss.Show)/0.015);
    for J:=0 to N do begin T:=Boss.Show+(Boss.Kill+0.50-Boss.Show)*J/N;
      D:=Boss.Radius;
      if T>=Boss.Kill then D:=1.30;
      Need(BALength(BASub(BossAt(I,T),HeroAt(T)))>BA_HERO_RADIUS+D+0.06,'boss body or defeat contact');
    end;
  end;
  for I:=0 to ShotCount-1 do begin Check;
    Shot:=FShots[I];
    Need(Finite(Shot.Start) and Finite(Shot.Finish) and Finite(Shot.Radius) and FinitePoint(Shot.Position) and FinitePoint(Shot.Velocity) and (Shot.Boss>=0) and (Shot.Boss<BossCount) and (Abs(Shot.Radius-0.12)<1E-12) and (Shot.Finish>Shot.Start) and (Shot.Finish-Shot.Start<=0.70+1E-7) and (Shot.Finish<=FBosses[Shot.Boss].Kill+0.12+1E-9),'shot');
    Need((Shot.Start>=FBosses[Shot.Boss].Show) and (Shot.Start<FBosses[Shot.Boss].Kill),'shot phase');
    J:=BombBefore(Shot.Start);
    Need((J>=0) and (FBombs[J].Time=Shot.Start) and (FBombs[J].Boss=Shot.Boss),'shot accent');
    if I>0 then Need(Shot.Start>=FShots[I-1].Start,'shot order');
    Need(ClearShot(Shot),'boss shot contact');
    Need(BALength(BASub(Shot.Position,BossAt(Shot.Boss,Shot.Start)))<1E-7,'shot origin');
  end;
  ValidateCrowd(Cancel);
end;

function TBombActionPlan.CrowdDestroyed(Time:Double):Integer;
var
  I:Integer;
begin I:=CrowdBefore(Time);
  Result:=0;
  if I>=0 then Result:=FCrowdKills[I];
end;

function TBombActionPlan.GetChargeCount:Integer;
begin Result:=Length(FCharges);
end;

function TBombActionPlan.GetCrowdCount:Integer;
begin Result:=Length(FCrowd);
end;

function TBombActionPlan.GetRaidCount:Integer;
begin Result:=Length(FRaids);
end;

function TBombActionPlan.GetCharge(Index:Integer):TBACharge;
begin Result:=FCharges[Index];
end;

function TBombActionPlan.GetCrowd(Index:Integer):TBACrowdEnemy;
begin Result:=FCrowd[Index];
end;

function TBombActionPlan.GetRaid(Index:Integer):TBAEnemyShot;
begin Result:=FRaids[Index];
end;

function TBombActionPlan.ChargeBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=ChargeCount;
  while A<B do begin M:=(A+B) div 2;
    if FCharges[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBombActionPlan.CrowdBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=CrowdCount;
  while A<B do begin M:=(A+B) div 2;
    if FCrowd[M].Kill<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBombActionPlan.RaidBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=RaidCount;
  while A<B do begin M:=(A+B) div 2;
    if FRaids[M].Start<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function BACompare(A,B:Double):Integer;
begin if A<B then Exit(-1);
  if A>B then Exit(1);
  Result:=0;
end;

function CrowdPosition(const Enemy:TBACrowdEnemy;Time:Double):TBAPoint;
begin Result:=BAAdd(Enemy.Position,BAScale(Enemy.Entry,1-Smooth((Time-Enemy.Show)/(Enemy.Kill-Enemy.Show))));
end;

function TBombActionPlan.CrowdAt(Index:Integer;Time:Double):TBAPoint;
begin Result:=CrowdPosition(FCrowd[Index],Time);
end;

function TBombActionPlan.CrowdSafe(const Enemy:TBACrowdEnemy):Boolean;
var
  I,J,N:Integer;
  T:Double;
  P:TBAPoint;
  B:TBABomb;
  C:TBACharge;
begin Result:=False;
  N:=Ceil((Enemy.Kill-Enemy.Show+0.22)/0.025);
  for I:=0 to N do begin T:=Enemy.Show+(Enemy.Kill-Enemy.Show+0.22)*I/N;
    P:=CrowdPosition(Enemy,Min(T,Enemy.Kill));
    if BALength(BASub(P,HeroAt(T)))<BA_HERO_RADIUS+Enemy.Radius+0.07 then Exit;
    if T>=Enemy.Kill then Continue;
    for J:=Max(0,BombBefore(T-0.72)) to BombBefore(T) do begin B:=FBombs[J];
      if (B.Time>=Enemy.Kill) or (T>B.Time+B.Life+0.22) then Continue;
      if BALength(BASub(P,B.Position))<B.Radius+0.10+Enemy.Radius then Exit;
    end;
    for J:=Max(0,ChargeBefore(T-0.48)) to ChargeBefore(T) do begin C:=FCharges[J];
      if (C.Time>=Enemy.Kill) or (T>C.Time+C.Life+0.14) then Continue;
      if BALength(BASub(P,C.Position))<C.Radius+0.085+Enemy.Radius then Exit;
    end;
  end;
  Result:=True;
end;

function TBombActionPlan.RaidSafe(const Shot:TBAEnemyShot):Boolean;
var
  I,N:Integer;
  T:Double;
  P:TBAPoint;
begin Result:=False;
  N:=Ceil((Shot.Finish-Shot.Start)/0.012);
  if N<1 then Exit;
  for I:=0 to N do begin T:=Shot.Start+(Shot.Finish-Shot.Start)*I/N;
    P:=BAAdd(Shot.Position,BAScale(Shot.Velocity,T-Shot.Start));
    if BALength(BASub(P,HeroAt(T)))<0.30 then Exit;
  end;
  Result:=True;
end;

procedure TBombActionPlan.MakeCrowd(const Cancel:TFunc<Boolean>);
var
  Charges:TList<TBACharge>;
  Foes:TList<TBACrowdEnemy>;
  Raids:TList<TBAEnemyShot>;
  Selected:TList<Integer>;
  Targets:TList<TBATarget>;
  Target:TBATarget;
  I,J,K,Lane,Slot,Attempt,First,Last,Volley,FanCount,VolleyCount:Integer;
  B:TBABomb;
  C:TBACharge;
  E:TBACrowdEnemy;
  S:TBAEnemyShot;
  Next,Angle,Dist,Side,Speed,Clock:Double;
  Good:Boolean;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
begin
  Charges:=TList<TBACharge>.Create;
  Foes:=TList<TBACrowdEnemy>.Create;
  Raids:=TList<TBAEnemyShot>.Create;
  Selected:=TList<Integer>.Create;
  Targets:=TList<TBATarget>.Create;
  try Next:=-1;
    for I:=0 to Count-1 do begin Check;
      B:=FBombs[I];
      if (B.Time<Next) or (B.Place<FLaunch+FAccel+1) then Continue;
      Next:=B.Time+Max(0.45,FEnd/1100);
      Selected.Add(I);
      for Lane:=0 to 2 do begin C.Time:=B.Time;
        C.Place:=B.Time-(1.04+0.23*Lane);
        if C.Place<FLaunch+FAccel then Continue;
        C.Position:=HeroAt(C.Place);
        C.Radius:=Min(3.3,BALength(BASub(HeroAt(C.Time),C.Position))-0.40);
        C.Life:=0.22+0.08*B.Strength;
        C.Bomb:=I;
        C.Pattern:=Lane mod 3;
        Charges.Add(C);
      end;
    end;
    FCharges:=Charges.ToArray;
    // A new salvo must never leave an earlier-destroyed legacy target visible.
    for Target in FTargets do begin Check;
      Good:=True;
      for J:=Max(0,ChargeBefore(Target.Show-0.44)) to ChargeBefore(Target.Kill-1E-8) do begin C:=FCharges[J];
        if (C.Time+C.Life+0.14>=Target.Show) and (BALength(BASub(Target.Position,C.Position))<=C.Radius+0.035+Target.Radius) then begin Good:=False;
          Break;
        end;
      end;
      FBombs[Target.Bomb].Target:=-1;
      if Good then begin FBombs[Target.Bomb].Target:=Targets.Count;
        Targets.Add(Target);
      end;
    end;
    FTargets:=Targets.ToArray;
    for I in Selected do begin Check;
      B:=FBombs[I];
      First:=ChargeBefore(B.Time-1E-8)+1;
      Last:=ChargeBefore(B.Time);
      if First>Last then Continue;
      for Slot:=0 to 7 do begin E.Kill:=B.Time;
        E.Show:=Max(FLaunch+0.1,B.Time-2.1-(Slot mod 3)*0.18);
        E.Radius:=0.12+(Slot mod 2)*0.015;
        E.Bomb:=I;
        E.Charge:=First+Slot mod (Last-First+1);
        E.Kind:=Slot mod 3;
        C:=FCharges[E.Charge];
        Good:=False;
        for Attempt:=0 to 23 do begin Side:=1;
          if Slot mod 2=0 then Side:=-1;
          Angle:=Side*(0.50+(Attempt mod 12)*0.15);
          Dist:=C.Radius+E.Radius*0.3;
          E.Position:=BAAdd(C.Position,BAV(Cos(Angle)*Dist,Sin(Angle)*Dist));
          E.Entry:=BAV(1.0+(Slot mod 3)*0.22,Side*1.4);
          if Attempt>=12 then E.Entry.Y:=Side*2.4;
          Good:=True;
          for K:=Max(0,Foes.Count-24) to Foes.Count-1 do if (Foes[K].Kill=E.Kill) and (BALength(BASub(Foes[K].Position,E.Position))<Foes[K].Radius+E.Radius+0.06) then Good:=False;
          if not Good then Continue;
          Good:=CrowdSafe(E);
          if Good then Break;
        end;
        if Good then Foes.Add(E);
      end;
    end;
    // During sparse music, unbroken flyby formations cross the screen and fire.
    Clock:=FLaunch+1;
    while Clock+2.8<FEnd-0.75 do begin Check;
      if BombBefore(Clock+3.2)=BombBefore(Clock-0.6) then for Lane:=0 to 1 do begin
        E.Show:=Clock+Lane*0.14;
        E.Kill:=E.Show+2.6;
        Side:=1;
        if Lane=0 then Side:=-1;
        E.Position:=BAAdd(HeroAt(E.Kill),BAV(-5.5,Side*1.8));
        E.Entry:=BASub(BAAdd(HeroAt(E.Show),BAV(5.5,Side*1.8)),E.Position);
        E.Radius:=0.135;
        E.Bomb:=-1;
        E.Charge:=-1;
        E.Kind:=Lane;
        if CrowdSafe(E) then Foes.Add(E);
      end;
      Clock:=Clock+Max(1.8,FEnd/600);
    end;
    Foes.Sort(TComparer<TBACrowdEnemy>.Construct(function(const A,B:TBACrowdEnemy):Integer
    begin Result:=BACompare(A.Kill,B.Kill);if Result=0 then Result:=BACompare(A.Charge,B.Charge);if Result=0 then Result:=BACompare(A.Kind,B.Kind);if Result=0 then Result:=BACompare(A.Position.X,B.Position.X);if Result=0 then Result:=BACompare(A.Position.Y,B.Position.Y);end));
    FCrowd:=Foes.ToArray;
    FanCount:=7;
    VolleyCount:=2;
    if CrowdCount*14>48000 then FanCount:=5;
    if CrowdCount*10>48000 then FanCount:=3;
    if CrowdCount*6>48000 then VolleyCount:=1;
    for I:=0 to CrowdCount-1 do begin Check;
      E:=FCrowd[I];
      for Volley:=0 to VolleyCount-1 do begin
        S.Start:=Max(E.Show+0.18,E.Kill-1.2+Volley*0.5);
        if S.Start>=E.Kill-0.12 then Continue;
        for Lane:=0 to FanCount-1 do begin Side:=1;
          if I mod 2=0 then Side:=-1;
          Angle:=Side*Pi/2+(Lane-(FanCount-1)/2)*0.27+Volley*0.18;
          Speed:=2.1+(Lane mod 3)*0.25;
          S.Finish:=Min(S.Start+1.5,FEnd-0.04);
          S.Position:=CrowdPosition(E,S.Start);
          S.Velocity:=BAV(Cos(Angle)*Speed,Sin(Angle)*Speed);
          S.Foe:=I;
          if (S.Finish>S.Start) and RaidSafe(S) then Raids.Add(S);
        end;
      end;
    end;
    Raids.Sort(TComparer<TBAEnemyShot>.Construct(function(const A,B:TBAEnemyShot):Integer
    begin Result:=BACompare(A.Start,B.Start);if Result=0 then Result:=BACompare(A.Foe,B.Foe);if Result=0 then Result:=BACompare(A.Velocity.X,B.Velocity.X);if Result=0 then Result:=BACompare(A.Velocity.Y,B.Velocity.Y);end));
    FRaids:=Raids.ToArray;
  finally Targets.Free;
    Selected.Free;
    Raids.Free;
    Foes.Free;
    Charges.Free;
  end;
end;

procedure TBombActionPlan.ValidateCrowd(const Cancel:TFunc<Boolean>);
var
  I,J,N,Kills:Integer;
  C:TBACharge;
  E:TBACrowdEnemy;
  S:TBAEnemyShot;
  T:Double;
  Target:TBATarget;
  procedure Need(Value:Boolean;const Why:string);
  begin if not Value then raise Exception.Create('Bomb crowd: '+Why);
  end;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
begin
  Need((FVersion in [1,2]) and (ChargeCount<=3600) and (CrowdCount<=12000) and (RaidCount<=48000),'counts');
  if FVersion=1 then begin Need((ChargeCount=0) and (CrowdCount=0) and (RaidCount=0),'legacy arrays');
    Exit;
  end;
  for I:=0 to ChargeCount-1 do begin Check;
    C:=FCharges[I];
    Need(Finite(C.Time) and Finite(C.Place) and Finite(C.Radius) and Finite(C.Life) and FinitePoint(C.Position) and (C.Bomb>=0) and (C.Bomb<Count) and (C.Pattern in [0,1,2]),'charge');
    Need((C.Time=FBombs[C.Bomb].Time) and (C.Place>=FLaunch+FAccel) and (C.Time-C.Place>=1.04-1E-7) and (C.Time-C.Place<=1.50+1E-7) and (C.Radius>0) and (C.Radius<=3.3) and (C.Life>=0.22) and (C.Life<=0.30+1E-7) and (C.Time+C.Life+0.14<=FEnd),'charge clock');
    Need(BALength(BASub(C.Position,HeroAt(C.Place)))<1E-7,'planting');
    if I>0 then Need(C.Time>=FCharges[I-1].Time,'charge order');
    N:=Ceil((C.Life+0.14)/0.012);
    for J:=0 to N do begin T:=C.Time+(C.Life+0.14)*J/N;
      Need(BALength(BASub(C.Position,HeroAt(T)))>C.Radius+0.035+BA_HERO_RADIUS+0.05,'blast contact');
    end;
  end;
  for I:=0 to CrowdCount-1 do begin Check;
    E:=FCrowd[I];
    Need(Finite(E.Show) and Finite(E.Kill) and Finite(E.Radius) and FinitePoint(E.Position) and FinitePoint(E.Entry) and (E.Bomb>=-1) and (E.Bomb<Count) and (E.Charge>=-1) and (E.Charge<ChargeCount) and (E.Kind in [0,1,2]),'enemy');
    if E.Bomb<0 then Need((E.Charge=-1) and (E.Show>=FLaunch) and (E.Kill-E.Show>0) and (E.Kill-E.Show<=2.6+1E-7) and (E.Kill+0.22<FEnd) and (E.Radius=0.135) and (BALength(E.Entry)<14),'flyby')
    else begin Need(E.Charge>=0,'enemy charge');
      C:=FCharges[E.Charge];
      Need((E.Kill=FBombs[E.Bomb].Time) and (E.Kill=C.Time) and (E.Show>=FLaunch) and (E.Kill-E.Show>0) and (E.Kill-E.Show<=2.46+1E-7) and (E.Radius>=0.12) and (E.Radius<=0.135+1E-7) and (BALength(E.Entry)<=3) and (BALength(BASub(E.Position,C.Position))<=C.Radius+E.Radius),'destruction');
    end;
    if I>0 then Need(E.Kill>=FCrowd[I-1].Kill,'enemy order');
    Need(CrowdSafe(E),'enemy path');
  end;
  SetLength(FCrowdKills,CrowdCount);
  Kills:=0;
  for I:=0 to CrowdCount-1 do begin if FCrowd[I].Bomb>=0 then Inc(Kills);
    FCrowdKills[I]:=Kills;
  end;
  for Target in FTargets do begin Check;
    for J:=Max(0,ChargeBefore(Target.Show-0.44)) to ChargeBefore(Target.Kill-1E-8) do begin C:=FCharges[J];
      if C.Time+C.Life+0.14>=Target.Show then Need(BALength(BASub(Target.Position,C.Position))>C.Radius+0.035+Target.Radius,'prior salvo target hit');
    end;
  end;
  for I:=0 to RaidCount-1 do begin Check;
    S:=FRaids[I];
    Need(Finite(S.Start) and Finite(S.Finish) and FinitePoint(S.Position) and FinitePoint(S.Velocity) and (S.Foe>=0) and (S.Foe<CrowdCount) and (S.Start>=0) and (S.Finish>S.Start) and (S.Finish-S.Start<=1.5+1E-7) and (S.Finish<FEnd) and (BALength(S.Velocity)<=2.61),'shot');
    E:=FCrowd[S.Foe];
    Need((S.Start>=E.Show) and (S.Start<E.Kill) and (BALength(BASub(S.Position,CrowdPosition(E,S.Start)))<1E-7) and RaidSafe(S),'shot origin/contact');
    if I>0 then Need(S.Start>=FRaids[I-1].Start,'shot order');
  end;
end;

procedure TBombActionPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var
  Root,J:TJSONObject;
  A:TJSONArray;
  E:TBAEvent;
  B:TBABomb;
  T:TBATarget;
  Boss:TBABoss;
  Shot:TBAShot;
  Charge:TBACharge;
  Foe:TBACrowdEnemy;
  Raid:TBAEnemyShot;
  procedure Num(const Name:string;V:Double);
  begin J.AddPair(Name,TJSONNumber.Create(V));
  end;
  procedure Int(const Name:string;V:Integer);
  begin J.AddPair(Name,TJSONNumber.Create(V));
  end;
  procedure Point(const Name:string;const P:TBAPoint);
  var
    V:TJSONArray;
  begin V:=TJSONArray.Create;
    V.Add(P.X);
    V.Add(P.Y);
    J.AddPair(Name,V);
  end;
begin
  if (Ref.Version<>2) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsBombAction,Ref.Variant) or (BossFrequencyFromVariant(Ref.Variant)<>FFrequency) then raise Exception.Create('Invalid bomb-action reference');
  Root:=TJSONObject.Create;
  try
    J:=Root;
    Int('schema',1);
    Root.AddPair('style','bomb-action');
    Int('version',2);
    Root.AddPair('layout','free-chain-v2');
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Int('sensitivity',Ref.Sensitivity);
    Int('direction',Ref.Direction);
    AddPreparedAudio(Root,Audio);
    Num('end',FEnd);
    Num('launch',FLaunch);
    Num('acceleration',FAccel);
    Num('goal',FGoal);
    Int('frequency',FFrequency);
    Int('excluded',FExcluded);
    Root.AddPair('seed',TJSONNumber.Create(Int64(FSeed)));
    A:=TJSONArray.Create;
    Root.AddPair('events',A);
    for E in FEvents do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Num('time',E.Time);
      Num('strength',E.Strength);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('bombs',A);
    for B in FBombs do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Num('time',B.Time);
      Num('place',B.Place);
      Num('radius',B.Radius);
      Num('life',B.Life);
      Num('strength',B.Strength);
      Num('angle',B.Angle);
      Num('waveSpeed',B.WaveSpeed);
      Point('position',B.Position);
      Int('source',B.Source);
      Int('pattern',B.Pattern);
      Int('parent',B.Parent);
      Int('child',B.Child);
      Int('boss',B.Boss);
      Int('target',B.Target);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('targets',A);
    for T in FTargets do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Point('position',T.Position);
      Num('show',T.Show);
      Num('kill',T.Kill);
      Num('radius',T.Radius);
      Int('kind',T.Kind);
      Int('bomb',T.Bomb);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('bosses',A);
    for Boss in FBosses do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Num('show',Boss.Show);
      Num('kill',Boss.Kill);
      Num('radius',Boss.Radius);
      Int('first',Boss.FirstBomb);
      Int('last',Boss.LastBomb);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('shots',A);
    for Shot in FShots do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Num('start',Shot.Start);
      Num('finish',Shot.Finish);
      Num('radius',Shot.Radius);
      Point('position',Shot.Position);
      Point('velocity',Shot.Velocity);
      Int('boss',Shot.Boss);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('charges',A);
    for Charge in FCharges do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Num('time',Charge.Time);
      Num('place',Charge.Place);
      Num('radius',Charge.Radius);
      Num('life',Charge.Life);
      Point('position',Charge.Position);
      Int('bomb',Charge.Bomb);
      Int('pattern',Charge.Pattern);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('crowd',A);
    for Foe in FCrowd do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Num('show',Foe.Show);
      Num('kill',Foe.Kill);
      Num('radius',Foe.Radius);
      Point('position',Foe.Position);
      Point('entry',Foe.Entry);
      Int('bomb',Foe.Bomb);
      Int('charge',Foe.Charge);
      Int('kind',Foe.Kind);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('raids',A);
    for Raid in FRaids do begin J:=TJSONObject.Create;
      A.AddElement(J);
      Num('start',Raid.Start);
      Num('finish',Raid.Finish);
      Point('position',Raid.Position);
      Point('velocity',Raid.Velocity);
      Int('foe',Raid.Foe);
    end;
    WritePreparedData(Root,Ref);
  finally Root.Free;
  end;
end;

class function TBombActionPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var
  Root:TJSONObject;
begin Root:=ReadPreparedData(Ref,rsBombAction,Direction);
  try Result:=PreparedAudio(Root,Ref,Source);
  finally Root.Free;
  end;
end;

class function TBombActionPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TBombActionPlan;
var
  Root,J,Info:TJSONObject;
  A:TJSONArray;
  I:Integer;
  Seed:Int64;
  function Items(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);
    if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Invalid bomb-action '+Name);
  end;
  procedure At(Index:Integer);
  begin if not (A.Items[Index] is TJSONObject) then raise Exception.Create('Invalid bomb-action record');
    J:=TJSONObject(A.Items[Index]);
  end;
  function Num(const Name:string):Double;
  begin Result:=J.GetValue<Double>(Name);
  end;
  function Int(const Name:string):Integer;
  begin Result:=J.GetValue<Integer>(Name);
  end;
  function Point(const Name:string):TBAPoint;
  var
    V:TJSONArray;
  begin V:=J.GetValue<TJSONArray>(Name);
    if (V=nil) or (V.Count<>2) then raise Exception.Create('Invalid bomb-action point');
    Result:=BAV(V.Items[0].GetValue<Double>,V.Items[1].GetValue<Double>);
  end;
begin
  Result:=nil;
  if (Audio=nil) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsBombAction,Ref.Variant) then raise Exception.Create('Bomb-action audio mismatch');
  Root:=ReadPreparedData(Ref,rsBombAction,Direction);
  try
    if Root.GetValue<string>('layout','')<>'free-chain-v'+IntToStr(Ref.Version) then raise Exception.Create('Invalid bomb-action layout');
    Info:=Root.GetValue<TJSONObject>('audio');
    if (Info=nil) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or not Finite(Info.GetValue<Double>('duration')) or not Finite(Info.GetValue<Double>('soundEnd')) or (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-7) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-7) then raise Exception.Create('Bomb-action metadata identity');
    Result:=TBombActionPlan.Create;
    try
      J:=Root;
      Result.FVersion:=Ref.Version;
      Result.FDuration:=Audio.Duration;
      Result.FSoundEnd:=Audio.SoundEnd;
      Result.FEnd:=Num('end');
      Result.FLaunch:=Num('launch');
      Result.FAccel:=Num('acceleration');
      Result.FGoal:=Num('goal');
      Result.FFrequency:=Int('frequency');
      Result.FExcluded:=Int('excluded');
      Seed:=Root.GetValue<Int64>('seed',-1);
      if (Seed<0) or (Seed>High(Cardinal)) or (Cardinal(Seed)<>SourceSeed(Ref.SourceKey)) or (Result.FFrequency<>BossFrequencyFromVariant(Ref.Variant)) then raise Exception.Create('Bomb-action policy mismatch');
      Result.FSeed:=Cardinal(Seed);
      A:=Items('events',100000);
      if A.Count<>Length(Audio.Hits) then raise Exception.Create('Bomb-action event count');
      SetLength(Result.FEvents,A.Count);
      for I:=0 to A.Count-1 do begin At(I);
        Result.FEvents[I].Time:=Num('time');
        Result.FEvents[I].Strength:=Num('strength');
      end;
      A:=Items('bombs',20000);
      SetLength(Result.FBombs,A.Count);
      for I:=0 to A.Count-1 do begin At(I);
        Result.FBombs[I].Time:=Num('time');
        Result.FBombs[I].Place:=Num('place');
        Result.FBombs[I].Radius:=Num('radius');
        Result.FBombs[I].Life:=Num('life');
        Result.FBombs[I].Strength:=Num('strength');
        Result.FBombs[I].Angle:=Num('angle');
        Result.FBombs[I].WaveSpeed:=Num('waveSpeed');
        Result.FBombs[I].Position:=Point('position');
        Result.FBombs[I].Source:=Int('source');
        Result.FBombs[I].Pattern:=Int('pattern');
        Result.FBombs[I].Parent:=Int('parent');
        Result.FBombs[I].Child:=Int('child');
        Result.FBombs[I].Boss:=Int('boss');
        Result.FBombs[I].Target:=Int('target');
      end;
      A:=Items('targets',20000);
      SetLength(Result.FTargets,A.Count);
      for I:=0 to A.Count-1 do begin At(I);
        Result.FTargets[I].Position:=Point('position');
        Result.FTargets[I].Show:=Num('show');
        Result.FTargets[I].Kill:=Num('kill');
        Result.FTargets[I].Radius:=Num('radius');
        Result.FTargets[I].Kind:=Int('kind');
        Result.FTargets[I].Bomb:=Int('bomb');
      end;
      A:=Items('bosses',256);
      SetLength(Result.FBosses,A.Count);
      for I:=0 to A.Count-1 do begin At(I);
        Result.FBosses[I].Show:=Num('show');
        Result.FBosses[I].Kill:=Num('kill');
        Result.FBosses[I].Radius:=Num('radius');
        Result.FBosses[I].FirstBomb:=Int('first');
        Result.FBosses[I].LastBomb:=Int('last');
      end;
      A:=Items('shots',12000);
      SetLength(Result.FShots,A.Count);
      for I:=0 to A.Count-1 do begin At(I);
        Result.FShots[I].Start:=Num('start');
        Result.FShots[I].Finish:=Num('finish');
        Result.FShots[I].Radius:=Num('radius');
        Result.FShots[I].Position:=Point('position');
        Result.FShots[I].Velocity:=Point('velocity');
        Result.FShots[I].Boss:=Int('boss');
      end;
      if Ref.Version>=2 then begin
        A:=Items('charges',3600);
        SetLength(Result.FCharges,A.Count);
        for I:=0 to A.Count-1 do begin At(I);
          Result.FCharges[I].Time:=Num('time');
          Result.FCharges[I].Place:=Num('place');
          Result.FCharges[I].Radius:=Num('radius');
          Result.FCharges[I].Life:=Num('life');
          Result.FCharges[I].Position:=Point('position');
          Result.FCharges[I].Bomb:=Int('bomb');
          Result.FCharges[I].Pattern:=Int('pattern');
        end;
        A:=Items('crowd',12000);
        SetLength(Result.FCrowd,A.Count);
        for I:=0 to A.Count-1 do begin At(I);
          Result.FCrowd[I].Show:=Num('show');
          Result.FCrowd[I].Kill:=Num('kill');
          Result.FCrowd[I].Radius:=Num('radius');
          Result.FCrowd[I].Position:=Point('position');
          Result.FCrowd[I].Entry:=Point('entry');
          Result.FCrowd[I].Bomb:=Int('bomb');
          Result.FCrowd[I].Charge:=Int('charge');
          Result.FCrowd[I].Kind:=Int('kind');
        end;
        A:=Items('raids',48000);
        SetLength(Result.FRaids,A.Count);
        for I:=0 to A.Count-1 do begin At(I);
          Result.FRaids[I].Start:=Num('start');
          Result.FRaids[I].Finish:=Num('finish');
          Result.FRaids[I].Position:=Point('position');
          Result.FRaids[I].Velocity:=Point('velocity');
          Result.FRaids[I].Foe:=Int('foe');
        end;
      end;
      Result.Validate;
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally Root.Free;
  end;
end;
end.
