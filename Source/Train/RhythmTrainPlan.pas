unit RhythmTrainPlan;
// A saved railway battle score. All attack clocks are fixed source accents.
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef;
type
  TTrainPoint=record
    X,Y:Double;
  end;
  TTrainEvent=record
    Time,Power:Double;
  end;
  TTrainGroup=record
    First,Last,Kind,Boss,Members:Integer;
    Show,Pass,X,Y,Speed:Double;
  end;
  TTrainEnemy=record
    Group,Slot,FirstSource,KillSource:Integer;
  end;
  TTrainHit=record
    Source,Enemy,Car,Mode:Integer;
    Launch:Double;
    A,B:TTrainPoint;
  end;
  TTrainShot=record
    Start,Near,Finish:Double;
    A,B:TTrainPoint;
    Enemy,Outcome,Car,Kind:Integer;
  end;
  TTrainBoss=record
    Show,Kill:Double;
    FirstSource,LastSource,Group:Integer;
    Boundary:Boolean;
  end;
  TTrainSceneKey=record
    Time:Double;
    Kind:Integer;
  end;
  TTrainCameraKey=record
    Time,Zoom:Double;
  end;
  TTrainPlan=class
  private
    FEvents:TArray<TTrainEvent>;
    FGroups:TArray<TTrainGroup>;
    FEnemies:TArray<TTrainEnemy>;
    FHits:TArray<TTrainHit>;
    FShots:TArray<TTrainShot>;
    FBosses:TArray<TTrainBoss>;
    FScenes:TArray<TTrainSceneKey>;
    FCamera:TArray<TTrainCameraKey>;
    FShowOrder:TArray<Integer>;
    FMaxKill:TArray<Double>;
    FDuration,FGoal,FEnd,FIntro:Double;
    FFrequency,FSourceCount,FExcluded:Integer;
    procedure Reindex;
    procedure Verify;
    function GetCount:Integer;
    function GetPulseCount:Integer;
    function GetBossCount:Integer;
    function GetEnemyCount:Integer;
    function GetHitCount:Integer;
    function GetShotCount:Integer;
    function GetEnemy(I:Integer):TTrainEnemy;
    function GetGroup(I:Integer):TTrainGroup;
    function GetHit(I:Integer):TTrainHit;
    function GetShot(I:Integer):TTrainShot;
    function GetBoss(I:Integer):TTrainBoss;
    function GetEvent(I:Integer):TTrainEvent;
  public
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TTrainPlan; static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TTrainPlan; static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio; static;
    function EventBefore(Time:Double):Integer;
    function HitBefore(Time:Double):Integer;
    function ShotBefore(Time:Double):Integer;
    procedure VisibleEnemies(Time:Double;out First,Last:Integer);
    function VisibleEnemy(Ordinal:Integer):Integer;
    function HeroCarAt(Car:Integer;Time:Double):TTrainPoint;
    function EnemyAt(Index:Integer;Time:Double):TTrainPoint;
    function EnemySize(Index:Integer):TTrainPoint;
    function HeroMuzzle(Car:Integer;Time:Double):TTrainPoint;
    function HitAt(Index:Integer;Time:Double;out P:TTrainPoint):Boolean;
    function ShotAt(Index:Integer;Time:Double;out P:TTrainPoint):Boolean;
    function EnemyHP(Index:Integer;Time:Double):Double;
    function BossHP(Index:Integer;Time:Double):Double;
    function SceneAt(Time:Double):Integer;
    function SceneTransition(Time:Double):Double;
    function CameraAt(Time:Double):Double;
    function TravelAt(Time:Double):Double;
    function DamageAt(Car:Integer;Time:Double):Double;
    property Count:Integer read GetCount;
    property PulseCount:Integer read GetPulseCount;
    property BossCount:Integer read GetBossCount;
    property EnemyCount:Integer read GetEnemyCount;
    property HitCount:Integer read GetHitCount;
    property ShotCount:Integer read GetShotCount;
    property Enemy[I:Integer]:TTrainEnemy read GetEnemy;
    property Group[I:Integer]:TTrainGroup read GetGroup;
    property Hit[I:Integer]:TTrainHit read GetHit;
    property Shot[I:Integer]:TTrainShot read GetShot;
    property Boss[I:Integer]:TTrainBoss read GetBoss;
    property Event[I:Integer]:TTrainEvent read GetEvent;
    property EndTime:Double read FEnd;
    property GoalTime:Double read FGoal;
    property IntroTime:Double read FIntro;
    property SourceCount:Integer read FSourceCount;
    property BossFrequency:Integer read FFrequency;
  end;
function TrainPoint(X,Y:Double):TTrainPoint;
implementation
uses System.Math,System.JSON,System.Generics.Collections,System.Generics.Defaults,
RhythmStyles,RhythmPreparedData,RhythmSections;

function TrainPoint(X,Y:Double):TTrainPoint;
begin Result.X:=X;
  Result.Y:=Y;
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function Mix(const A,B:TTrainPoint;U:Double):TTrainPoint;
begin Result:=TrainPoint(A.X+(B.X-A.X)*U,A.Y+(B.Y-A.Y)*U);
end;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

function Curve(const A,B:TTrainPoint;U:Double):TTrainPoint;
var
  C,D:TTrainPoint;
  V:Double;
begin
  U:=EnsureRange(U,0.0,1.0);
  V:=1-U;
  C:=TrainPoint(A.X,A.Y-0.080);
  D:=TrainPoint(B.X,Max(B.Y+0.030,Min(A.Y-0.020,B.Y+0.12)));
  Result:=TrainPoint(A.X*V*V*V+3*C.X*V*V*U+3*D.X*V*U*U+B.X*U*U*U,
  A.Y*V*V*V+3*C.Y*V*V*U+3*D.Y*V*U*U+B.Y*U*U*U);
end;

function TTrainPlan.GetCount:Integer;
begin Result:=Length(FHits);
end;

function TTrainPlan.GetPulseCount:Integer;
begin Result:=Length(FEvents);
end;

function TTrainPlan.GetBossCount:Integer;
begin Result:=Length(FBosses);
end;

function TTrainPlan.GetEnemyCount:Integer;
begin Result:=Length(FEnemies);
end;

function TTrainPlan.GetHitCount:Integer;
begin Result:=Length(FHits);
end;

function TTrainPlan.GetShotCount:Integer;
begin Result:=Length(FShots);
end;

function TTrainPlan.GetEnemy(I:Integer):TTrainEnemy;
begin Result:=FEnemies[I];
end;

function TTrainPlan.GetGroup(I:Integer):TTrainGroup;
begin Result:=FGroups[I];
end;

function TTrainPlan.GetHit(I:Integer):TTrainHit;
begin Result:=FHits[I];
end;

function TTrainPlan.GetShot(I:Integer):TTrainShot;
begin Result:=FShots[I];
end;

function TTrainPlan.GetBoss(I:Integer):TTrainBoss;
begin Result:=FBosses[I];
end;

function TTrainPlan.GetEvent(I:Integer):TTrainEvent;
begin Result:=FEvents[I];
end;

function TTrainPlan.EventBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=PulseCount;
  while A<B do begin M:=(A+B) div 2;
    if FEvents[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TTrainPlan.HitBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=HitCount;
  while A<B do begin M:=(A+B) div 2;
    if FEvents[FHits[M].Source].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TTrainPlan.ShotBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=ShotCount;
  while A<B do begin M:=(A+B) div 2;
    if FShots[M].Start<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TTrainPlan.TravelAt(Time:Double):Double;
begin Result:=2.25*EnsureRange(Time,0.0,FEnd);
end;

function TTrainPlan.HeroCarAt(Car:Integer;Time:Double):TTrainPoint;
var
  D,Offset:Double;
begin
  Time:=EnsureRange(Time,0.0,FEnd);
  Car:=EnsureRange(Car,0,7);
  D:=TravelAt(Time)-Car*0.110;
  Offset:=0;
  if FIntro>1E-9 then Offset:=-1.45*(1-Smooth(Time/FIntro));
  if Time>FGoal then Offset:=Offset+2.4*Smooth((Time-FGoal)/1.0);
  Result:=TrainPoint(1.12-Car*0.110+Offset,0.665+0.040*Sin((D+Offset)*0.65)+0.014*Sin((D+Offset)*0.23));
end;

function TTrainPlan.HeroMuzzle(Car:Integer;Time:Double):TTrainPoint;
begin Result:=HeroCarAt(Car,Time);
  Result.Y:=Result.Y-0.066;
end;

function TTrainPlan.EnemySize(Index:Integer):TTrainPoint;
var
  K:Integer;
begin K:=FGroups[FEnemies[Index].Group].Kind;
  case K of 0:Result:=TrainPoint(0.049,0.030);
    1:Result:=TrainPoint(0.032,0.023);
    2:Result:=TrainPoint(0.040,0.033);
    3:Result:=TrainPoint(0.050,0.060);
    else Result:=TrainPoint(0.067,0.054);
  end;
end;

function TTrainPlan.EnemyAt(Index:Integer;Time:Double):TTrainPoint;
var
  E:TTrainEnemy;
  G:TTrainGroup;
  D:Double;
  P:TTrainPoint;
begin
  E:=FEnemies[Index];
  G:=FGroups[E.Group];
  Time:=EnsureRange(Time,0.0,FEnd);
  if G.Kind=4 then begin
    Result:=TrainPoint(G.X-E.Slot*0.142-0.85*(1-Smooth((Time-G.Show)/1.0))+0.022*Sin((Time-G.Show)*0.85),G.Y+0.009*Sin(TravelAt(Time)*0.30-E.Slot*0.22));
    Exit;
  end;
  Result.X:=G.X+G.Speed*(G.Pass-Time);
  case G.Kind of
    0:begin Result.X:=Result.X-E.Slot*0.110;
      Result.Y:=G.Y+0.010*Sin(TravelAt(Time)*0.65-E.Slot*0.3);
    end;
    1:begin Result.X:=Result.X-(E.Slot-1)*0.072;
      Result.Y:=G.Y+0.024*Sin((Time-G.Show)*3.8+E.Slot*1.6);
    end;
    2:begin Result.X:=Result.X-E.Slot*0.118;
      Result.Y:=G.Y;
    end;
    else begin P:=HeroCarAt(0,Time);
      D:=TravelAt(Time)+Result.X-P.X;
      Result.Y:=0.665+0.040*Sin(D*0.65)+0.014*Sin(D*0.23);
    end;
  end;
end;

function TTrainPlan.EnemyHP(Index:Integer;Time:Double):Double;
var
  E:TTrainEnemy;
  Taken,Total:Integer;
begin E:=FEnemies[Index];
  Total:=E.KillSource-E.FirstSource+1;
  Taken:=EnsureRange(EventBefore(Time)-E.FirstSource+1,0,Total);
  Result:=1-Taken/Max(1,Total);
end;

function TTrainPlan.BossHP(Index:Integer;Time:Double):Double;
var
  B:TTrainBoss;
  Total,Taken:Integer;
begin B:=FBosses[Index];
  Total:=B.LastSource-B.FirstSource+1;
  Taken:=EnsureRange(EventBefore(Time)-B.FirstSource+1,0,Total);
  Result:=1-Taken/Max(1,Total);
end;

function TTrainPlan.HitAt(Index:Integer;Time:Double;out P:TTrainPoint):Boolean;
var
  H:TTrainHit;
  AtTime:Double;
begin H:=FHits[Index];
  AtTime:=FEvents[H.Source].Time;
  Result:=(H.Mode=0) and (Time>=H.Launch) and (Time<=AtTime);
  P:=H.B;
  if Result then P:=Curve(H.A,H.B,(Time-H.Launch)/Max(1E-9,AtTime-H.Launch));
end;

function TTrainPlan.ShotAt(Index:Integer;Time:Double;out P:TTrainPoint):Boolean;
var
  S:TTrainShot;
  U:Double;
begin S:=FShots[Index];
  Result:=(Time>=S.Start) and (Time<S.Finish);
  P:=S.B;
  if Result then begin U:=(Time-S.Start)/Max(1E-9,S.Near-S.Start);
    P:=Mix(S.A,S.B,U);
  end;
end;

function TTrainPlan.DamageAt(Car:Integer;Time:Double):Double;
var
  I:Integer;
  S:TTrainShot;
  Age:Double;
begin Result:=0;
  for I:=Max(0,ShotBefore(Time-1.70)+1) to ShotBefore(Time) do begin S:=FShots[I];
    if (S.Outcome<>2) or (S.Car<>Car) then Continue;
    Age:=Time-S.Near;
    if (Age>=0) and (Age<0.75) then Result:=Max(Result,1-Age/0.75);
  end;
end;

function TTrainPlan.SceneAt(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(FScenes);
  while A<B do begin M:=(A+B) div 2;
    if FScenes[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=0;
  if A>0 then Result:=FScenes[A-1].Kind;
end;

function TTrainPlan.SceneTransition(Time:Double):Double;
var
  I:Integer;
begin Result:=1;
  for I:=High(FScenes) downto 1 do if Time>=FScenes[I].Time then begin Result:=Smooth((Time-FScenes[I].Time)/0.65);
    Exit;
  end;
end;

function TTrainPlan.CameraAt(Time:Double):Double;
var
  A,B,M:Integer;
  U:Double;
begin Result:=1;
  A:=0;
  B:=Length(FCamera);
  while A<B do begin M:=(A+B) div 2;
    if FCamera[M].Time<=Time then A:=M+1 else B:=M;
  end;
  if A=0 then Exit;
  Dec(A);
  Result:=FCamera[A].Zoom;
  if A=High(FCamera) then Exit;
  U:=Smooth((Time-FCamera[A].Time)/(FCamera[A+1].Time-FCamera[A].Time));
  Result:=Result+(FCamera[A+1].Zoom-Result)*U;
end;

procedure TTrainPlan.Reindex;
var
  I:Integer;
  MaxKill:Double;
begin
  SetLength(FShowOrder,EnemyCount);
  for I:=0 to EnemyCount-1 do FShowOrder[I]:=I;
  TArray.Sort<Integer>(FShowOrder,TComparer<Integer>.Construct(function(const A,B:Integer):Integer
  begin Result:=0;if FGroups[FEnemies[A].Group].Show<FGroups[FEnemies[B].Group].Show then Exit(-1);if FGroups[FEnemies[A].Group].Show>FGroups[FEnemies[B].Group].Show then Exit(1);if A<B then Result:=-1 else if A>B then Result:=1;end));
  SetLength(FMaxKill,EnemyCount);
  MaxKill:=-1;
  for I:=0 to EnemyCount-1 do begin MaxKill:=Max(MaxKill,FEvents[FEnemies[FShowOrder[I]].KillSource].Time+0.70);
    FMaxKill[I]:=MaxKill;
  end;
end;

procedure TTrainPlan.VisibleEnemies(Time:Double;out First,Last:Integer);
var
  A,B,M:Integer;
begin A:=0;
  B:=EnemyCount;
  while A<B do begin M:=(A+B) div 2;
    if FMaxKill[M]<Time then A:=M+1 else B:=M;
  end;
  First:=A;
  A:=0;
  B:=EnemyCount;
  while A<B do begin M:=(A+B) div 2;
    if FGroups[FEnemies[FShowOrder[M]].Group].Show<=Time then A:=M+1 else B:=M;
  end;
  Last:=A-1;
end;

function TTrainPlan.VisibleEnemy(Ordinal:Integer):Integer;
begin Result:=FShowOrder[Ordinal];
end;

class function TTrainPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TTrainPlan;
var
  Events:TList<TTrainEvent>;
  Groups:TList<TTrainGroup>;
  Enemies:TList<TTrainEnemy>;
  Hits:TList<TTrainHit>;
  Shots:TList<TTrainShot>;
  Bosses,Candidates:TList<TTrainBoss>;
  Scenes:TList<TTrainSceneKey>;
  Cameras:TList<TTrainCameraKey>;
  I,J,K,L,N,Cursor,FirstEnemy,Target,Primary,BossIndex,Part,Source,Wave,Fan,Budget,Waves,EnemyIndex,Kind:Integer;
  E:TTrainEvent;
  G:TTrainGroup;
  Enemy:TTrainEnemy;
  H:TTrainHit;
  Shot:TTrainShot;
  Boss:TTrainBoss;
  Cue:TRhythmBossCue;
  Scene:TTrainSceneKey;
  Cam:TTrainCameraKey;
  Time,Span,LastScene,LastCamera,Age,T:Double;
  P,Q,Size:TTrainPoint;
  Safe:Boolean;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
  procedure AddHit(EventIndex,EnemyIndex,Car:Integer;Ram:Boolean=False);
  var
    C,R:TTrainPoint;
    AtTime:Double;
  begin
    AtTime:=Result.FEvents[EventIndex].Time;
    H:=Default(TTrainHit);
    H.Source:=EventIndex;
    H.Enemy:=EnemyIndex;
    H.Car:=Car;
    H.Launch:=AtTime-(0.28+0.10*Result.FEvents[EventIndex].Power);
    C:=Result.EnemyAt(EnemyIndex,AtTime);
    R:=Result.EnemySize(EnemyIndex);
    H.B:=TrainPoint(C.X,C.Y+R.Y+0.006);
    H.A:=Result.HeroMuzzle(Car,H.Launch);
    if Ram then begin H.Mode:=1;
      H.Launch:=AtTime;
      P:=Result.HeroCarAt(0,AtTime);
      H.B:=TrainPoint(P.X+0.062,P.Y);
      H.A:=H.B;
    end;
    Hits.Add(H);
  end;
  procedure AddGroup(First,Last,GroupKind,BossId,Members:Integer;Show:Double);
  var
    S,PartFirst,PartLast:Integer;
  begin
    G:=Default(TTrainGroup);
    G.First:=First;
    G.Last:=Last;
    G.Kind:=GroupKind;
    G.Boss:=BossId;
    G.Members:=Members;
    G.Show:=Max(0.0,Show);
    G.Pass:=Result.FEvents[First].Time;
    case GroupKind of
      0:begin G.X:=1.30;
        G.Y:=0.29;
        G.Speed:=0.42;
      end;
      1:begin G.X:=1.22;
        G.Y:=0.435;
        if Groups.Count mod 4=3 then G.Y:=0.16;
        G.Speed:=0.65;
      end;
      2:begin G.X:=1.27;
        G.Y:=0.43;
        G.Speed:=2.25;
      end;
      3:begin P:=Result.HeroCarAt(0,Result.FEvents[Last].Time);
        G.Pass:=Result.FEvents[Last].Time;
        G.X:=P.X+0.062+0.050;
        G.Y:=P.Y;
        G.Speed:=1.45;
      end;
      4:begin G.X:=1.51;
        G.Y:=0.23;
        G.Speed:=0;
      end;
    end;
    if (Groups.Count>=30000) or (Enemies.Count+Members>60000) then raise Exception.Create('Train actor budget');
    Groups.Add(G);
    Result.FGroups[Groups.Count-1]:=G;
    FirstEnemy:=Enemies.Count;
    for S:=0 to Members-1 do begin Enemy:=Default(TTrainEnemy);
      Enemy.Group:=Groups.Count-1;
      Enemy.Slot:=S;
      if GroupKind=4 then begin PartFirst:=First+(Last-First+1)*S div Members;
        PartLast:=First+(Last-First+1)*(S+1) div Members-1;
        Enemy.FirstSource:=PartFirst;
        Enemy.KillSource:=PartLast;
      end
      else begin Enemy.FirstSource:=Last;
        Enemy.KillSource:=Last;
        if S=Members-1 then Enemy.FirstSource:=First;
      end;
      Enemies.Add(Enemy);
      Result.FEnemies[Enemies.Count-1]:=Enemy;
    end;
    // Only immutable completed arrays are used by all kinematic helpers.
    // Arrays are allocated once while staging, then compacted after generation.
  end;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  Check;
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then raise Exception.Create('Train audio bounds');
  Result:=TTrainPlan.Create;
  Events:=nil;
  Groups:=nil;
  Enemies:=nil;
  Hits:=nil;
  Shots:=nil;
  Bosses:=nil;
  Candidates:=nil;
  Scenes:=nil;
  Cameras:=nil;
  try
    try
      SetLength(Result.FGroups,30000);
      SetLength(Result.FEnemies,60000);
      Events:=TList<TTrainEvent>.Create;
      Groups:=TList<TTrainGroup>.Create;
      Enemies:=TList<TTrainEnemy>.Create;
      Hits:=TList<TTrainHit>.Create;
      Shots:=TList<TTrainShot>.Create;
      Bosses:=TList<TTrainBoss>.Create;
      Candidates:=TList<TTrainBoss>.Create;
      Scenes:=TList<TTrainSceneKey>.Create;
      Cameras:=TList<TTrainCameraKey>.Create;
      Result.FDuration:=Audio.Duration;
      Result.FGoal:=Audio.SoundEnd;
      Result.FFrequency:=Audio.BossFrequency;
      Result.FSourceCount:=Length(Audio.Hits);
      Result.FEnd:=0;
      if Audio.SoundEnd>0 then Result.FEnd:=Max(Audio.Duration,Audio.SoundEnd+1.1);
      Time:=-1;
      for I:=0 to High(Audio.Hits) do begin Check;
        E.Time:=Audio.Hits[I].Time;
        E.Power:=Audio.Hits[I].Strength;
        if not Finite(E.Time) or not Finite(E.Power) or (E.Time<0) or (E.Time<Time) or (E.Time>Audio.Duration+0.011) then raise Exception.Create('Train accent order');
        Time:=E.Time;
        if (Audio.SoundEnd<=0) or (E.Time>Audio.SoundEnd+1E-6) then begin Inc(Result.FExcluded);
          Continue;
        end;
        E.Power:=EnsureRange(E.Power,0.0,1.0);
        Events.Add(E);
      end;
      Result.FEvents:=Events.ToArray;
      Result.FIntro:=0;
      // Immediate accents begin with a ready train; do not squeeze a full entrance
      // into a few milliseconds or fire the first shot from outside the frame.
      if (Events.Count>0) and (Result.FEvents[0].Time>0.55) then Result.FIntro:=Min(0.65,Result.FEvents[0].Time-0.35);
      if Result.FFrequency>0 then for I:=0 to Min(63,Audio.BossCount-1) do begin Check;
        Cue:=Audio.BossCue(I);
        Boss:=Default(TTrainBoss);
        Boss.LastSource:=Result.EventBefore(Cue.KillTime+1E-8);
        if Boss.LastSource<0 then Continue;
        Boss.Kill:=Result.FEvents[Boss.LastSource].Time;
        Boss.Show:=Max(Cue.StartTime,Boss.Kill-31);
        Boss.Boundary:=Cue.QuietBoundary;
        Boss.FirstSource:=Result.EventBefore(Boss.Show+1.1)+1;
        if (Boss.Kill-Boss.Show<5) or (Boss.LastSource-Boss.FirstSource<5) then Continue;
        if Candidates.Count>0 then if Boss.FirstSource<=Candidates[Candidates.Count-1].LastSource then Continue;
        Candidates.Add(Boss);
      end;
      Cursor:=0;
      BossIndex:=0;
      while Cursor<Events.Count do begin Check;
        if (BossIndex<Candidates.Count) and (Cursor>=Candidates[BossIndex].FirstSource) then begin
          Boss:=Candidates[BossIndex];
          Boss.Group:=Groups.Count;
          Part:=Min(6,Boss.LastSource-Boss.FirstSource+1);
          AddGroup(Boss.FirstSource,Boss.LastSource,4,Bosses.Count,Part,Boss.Show);
          Bosses.Add(Boss);
          for I:=Boss.FirstSource to Boss.LastSource do begin Part:=Min(G.Members-1,((I-Boss.FirstSource+1)*G.Members-1) div (Boss.LastSource-Boss.FirstSource+1));
            AddHit(I,FirstEnemy+Part,(I div 2) mod 8);
          end;
          // Supporting aircraft keep the sides alive during the long boss duel.
          Time:=Boss.Show+2.0;
          while Time<Boss.Kill-0.5 do begin I:=Result.EventBefore(Time);
            if I>=Boss.FirstSource then begin AddGroup(I,I,1,-1,3,Max(Boss.Show,Result.FEvents[I].Time-1.25));
              for J:=0 to 2 do AddHit(I,FirstEnemy+J,(I+J) mod 8);
            end;
            Time:=Time+2.6;
          end;
          Cursor:=Boss.LastSource+1;
          Inc(BossIndex);
          Continue;
        end;
        I:=Cursor;
        J:=I;
        while J<Events.Count-1 do begin if (BossIndex<Candidates.Count) and (J+1>=Candidates[BossIndex].FirstSource) then Break;
          if Result.FEvents[J+1].Time-Result.FEvents[I].Time>0.22+1E-9 then Break;
          Inc(J);
        end;
        Kind:=Groups.Count mod 4;
        if Kind=3 then Kind:=1;
        if (Groups.Count mod 11=7) and (Result.FEvents[J].Power>0.60) then Kind:=3;
        N:=3;
        if Kind=3 then N:=1;
        AddGroup(I,J,Kind,-1,N,Result.FEvents[I].Time-1.45);
        Primary:=FirstEnemy+N-1;
        for K:=I to J do AddHit(K,Primary,K mod 8,(Kind=3) and (K=J));
        for K:=0 to N-2 do AddHit(J,FirstEnemy+K,(J+K+2) mod 8);
        Cursor:=J+1;
      end;
      Result.FGroups:=Groups.ToArray;
      Result.FEnemies:=Enemies.ToArray;
      Result.FBosses:=Bosses.ToArray;
      Result.FHits:=Hits.ToArray;
      TArray.Sort<TTrainHit>(Result.FHits,TComparer<TTrainHit>.Construct(function(const A,B:TTrainHit):Integer
      begin Result:=0;if A.Source<B.Source then Exit(-1);if A.Source>B.Source then Exit(1);if A.Enemy<B.Enemy then Result:=-1 else if A.Enemy>B.Enemy then Result:=1;end));
      // Planned incoming barrages. A strict total budget is spread across the song.
      FirstEnemy:=0;
      for I:=0 to Groups.Count-1 do begin Check;
        if Shots.Count>=80000 then Break;
        G:=Result.FGroups[I];
        Target:=FirstEnemy;
        Inc(FirstEnemy,G.Members);
        Span:=Result.FEvents[G.Last].Time-G.Show;
        if Span<0.20 then Continue;
        if G.Kind=3 then Continue;
        Budget:=Max(4,Min(48,60000 div Max(1,Groups.Count)));
        if G.Boss>=0 then Budget:=Min(10000,20000 div Max(1,Bosses.Count));
        Fan:=Min(10,Budget);
        if G.Boss>=0 then Fan:=Min(18,Budget);
        Waves:=Max(1,Min(Budget div Max(1,Fan),Ceil(Span/0.18)));
        for Wave:=0 to Waves-1 do begin Check;
          Time:=G.Show+0.16+(Span-0.23)*(Wave+0.15)/Max(1,Waves);
          if Time>=Result.FEvents[G.Last].Time-0.03 then Continue;
          EnemyIndex:=-1;
          for J:=Target to FirstEnemy-1 do if Result.FEvents[Result.FEnemies[J].KillSource].Time>Time then begin EnemyIndex:=J;
            Break;
          end;
          if EnemyIndex<0 then Continue;
          for J:=0 to Fan-1 do begin Shot:=Default(TTrainShot);
            Shot.Start:=Time;
            Shot.Enemy:=EnemyIndex;
            Shot.Car:=(J+Wave) mod 8;
            Shot.Kind:=(I+Wave) mod 4;
            Source:=Result.EventBefore(Time+0.85);
            Shot.Near:=Time+0.78+0.035*(J mod 3);
            if (Source>=0) and (Result.FEvents[Source].Time>Time+0.35) and (Result.FEvents[Source].Time<Time+1.15) then Shot.Near:=Result.FEvents[Source].Time;
            Shot.Near:=Min(Shot.Near,Result.FGoal+0.10);
            if Shot.Near<=Shot.Start+0.08 then Continue;
            Shot.Finish:=Min(Result.FGoal+0.45,Shot.Near+0.23);
            Shot.A:=Result.EnemyAt(EnemyIndex,Time);
            Size:=Result.EnemySize(EnemyIndex);
            Shot.A.Y:=Shot.A.Y+Size.Y;
            Shot.B:=Result.HeroCarAt(Shot.Car,Shot.Near);
            Shot.B.Y:=Shot.B.Y-0.070-0.018*(J mod 4);
            if J mod 5=0 then begin Shot.Outcome:=1;
              Shot.B.Y:=Shot.B.Y-0.020;
              Shot.Finish:=Shot.Near;
            end;
            if (J=1) and (Wave mod 6=2) then begin Shot.Outcome:=2;
              Shot.Car:=0;
              Shot.B:=Result.HeroCarAt(0,Shot.Near);
              Shot.B.X:=Shot.B.X+0.037;
              Shot.B.Y:=Shot.B.Y-0.041-0.006;
              Shot.Finish:=Shot.Near;
            end;
            // All non-contacting shots are checked against the entire moving consist.
            if Shot.Outcome<>2 then begin
              for L:=0 to 8 do begin Safe:=True;
                for N:=0 to 64 do begin T:=Shot.Start+(Shot.Finish-Shot.Start)*N/64;
                  Age:=(T-Shot.Start)/(Shot.Near-Shot.Start);
                  P:=Mix(Shot.A,Shot.B,Age);
                  for K:=0 to 7 do begin Q:=Result.HeroCarAt(K,T);
                    // Conservative swept envelope includes hull, gun and locomotive cab.
                    if (Abs(P.X-Q.X)<0.068) and (P.Y>Q.Y-0.076) and (P.Y<Q.Y+0.040) then Safe:=False;
                  end;
                end;
                if Safe then Break;
                Shot.B.Y:=Shot.B.Y-0.018;
              end;
              if not Safe then Continue;
            end;
            Shots.Add(Shot);
            if Shots.Count>=80000 then Break;
          end;
          if Shots.Count>=80000 then Break;
        end;
      end;
      Result.FShots:=Shots.ToArray;
      TArray.Sort<TTrainShot>(Result.FShots,TComparer<TTrainShot>.Construct(function(const A,B:TTrainShot):Integer
      begin Result:=0;if A.Start<B.Start then Exit(-1);if A.Start>B.Start then Exit(1);if A.Enemy<B.Enemy then Result:=-1 else if A.Enemy>B.Enemy then Result:=1;end));
      Scene.Time:=0;
      Scene.Kind:=0;
      Scenes.Add(Scene);
      LastScene:=-8;
      for I:=1 to Ceil(Result.FGoal*4) do begin Check;
        Time:=I*0.25;
        if Time-LastScene<9 then Continue;
        if (Audio.LevelAt(Time-0.35)>0.55) and (Audio.LevelAt(Time+0.45)<0.20) then begin Source:=Result.EventBefore(Time);
          if Source<0 then Continue;
          Scene.Time:=Result.FEvents[Source].Time+0.05;
          Scene.Kind:=(Scenes.Count mod 3);
          Scenes.Add(Scene);
          LastScene:=Time;
        end;
      end;
      for I:=0 to Bosses.Count-1 do if Bosses[I].Boundary then begin Scene.Time:=Bosses[I].Kill+0.05;
        Scene.Kind:=(I+1) mod 3;
        Scenes.Add(Scene);
      end;
      Result.FScenes:=Scenes.ToArray;
      TArray.Sort<TTrainSceneKey>(Result.FScenes,TComparer<TTrainSceneKey>.Construct(function(const A,B:TTrainSceneKey):Integer begin Result:=0;if A.Time<B.Time then Result:=-1 else if A.Time>B.Time then Result:=1;end));
      // Remove near-identical musical boundaries; this is not a per-beat camera cut.
      Scenes.Clear;
      for I:=0 to High(Result.FScenes) do if (Scenes.Count=0) or (Result.FScenes[I].Time-Scenes[Scenes.Count-1].Time>=2.0) then Scenes.Add(Result.FScenes[I]);
      Result.FScenes:=Scenes.ToArray;
      Cam.Time:=0;
      Cam.Zoom:=1;
      Cameras.Add(Cam);
      LastCamera:=-3;
      for I:=0 to Groups.Count-1 do begin G:=Result.FGroups[I];
        Time:=Result.FEvents[G.First].Time;
        if Time-LastCamera<3.5 then Continue;
        Cam.Time:=Max(0.0,Time-0.40);
        Cam.Zoom:=1;
        if (Cameras.Count=0) or (Cam.Time>Cameras[Cameras.Count-1].Time+1E-6) then Cameras.Add(Cam);
        Cam.Time:=Time+0.10;
        Cam.Zoom:=1.06;
        if G.Kind=4 then Cam.Zoom:=1.02 else if G.Last-G.First>=2 then Cam.Zoom:=1.10;
        Cameras.Add(Cam);
        Cam.Time:=Min(Result.FEnd,Time+2.1);
        Cam.Zoom:=1;
        Cameras.Add(Cam);
        LastCamera:=Time;
      end;
      Result.FCamera:=Cameras.ToArray;
      Result.Reindex;
      Result.Verify;
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally Events.Free;
    Groups.Free;
    Enemies.Free;
    Hits.Free;
    Shots.Free;
    Bosses.Free;
    Candidates.Free;
    Scenes.Free;
    Cameras.Free;
  end;
end;

procedure TTrainPlan.Verify;
var
  I:Integer;
  H:TTrainHit;
  S:TTrainShot;
  E:TTrainEnemy;
  G:TTrainGroup;
  P,Q,R:TTrainPoint;
  T:Double;
  procedure Need(V:Boolean;const Why:string);
  begin if not V then raise Exception.Create('Train plan: '+Why);
  end;
begin
  Need(Finite(FDuration) and Finite(FGoal) and Finite(FEnd) and (FDuration>0) and (FGoal>=0) and (FGoal<=FDuration),'bounds');
  Need((PulseCount<=100000) and (EnemyCount<=60000) and (HitCount<=180000) and (ShotCount<=80000) and (BossCount<=64),'limits');
  Need((FFrequency>=0) and (FFrequency<=100) and ((FFrequency<>0) or (BossCount=0)),'frequency');
  Need(PulseCount+FExcluded=FSourceCount,'source counts');
  for I:=0 to High(FGroups) do begin G:=FGroups[I];
    Need((G.First>=0) and (G.Last>=G.First) and (G.Last<PulseCount) and (G.Members>=1) and (G.Members<=6) and (G.Kind>=0) and (G.Kind<=4),'group bounds');
    Need(Finite(G.Show) and Finite(G.Pass) and Finite(G.X) and Finite(G.Y) and Finite(G.Speed),'group finite');
  end;
  for I:=0 to PulseCount-1 do begin Need(Finite(FEvents[I].Time) and Finite(FEvents[I].Power) and (FEvents[I].Time>=0) and (FEvents[I].Time<=FGoal+1E-6) and (FEvents[I].Power>=0) and (FEvents[I].Power<=1),'event');
    if I>0 then Need(FEvents[I].Time>=FEvents[I-1].Time,'event order');
  end;
  for I:=0 to EnemyCount-1 do begin E:=FEnemies[I];
    Need((E.Group>=0) and (E.Group<Length(FGroups)) and (E.FirstSource>=0) and (E.KillSource>=E.FirstSource) and (E.KillSource<PulseCount),'enemy links');
    G:=FGroups[E.Group];
    Need((G.Kind>=0) and (G.Kind<=4) and (E.Slot>=0) and (E.Slot<G.Members) and (G.Show>=0) and (G.Show<=FEvents[E.FirstSource].Time),'group');
  end;
  for I:=0 to HitCount-1 do begin H:=FHits[I];
    Need((H.Source>=0) and (H.Source<PulseCount) and (H.Enemy>=0) and (H.Enemy<EnemyCount) and (H.Car>=0) and (H.Car<=7),'hit link');
    E:=FEnemies[H.Enemy];
    T:=FEvents[H.Source].Time;
    Need((T<=FEvents[E.KillSource].Time+1E-8) and (T>=FGroups[E.Group].Show) and (H.Launch>=-0.38-1E-8) and (H.Launch<=T),'hit clock');
    P:=EnemyAt(H.Enemy,T);
    R:=EnemySize(H.Enemy);
    if H.Mode=0 then begin Need((Abs(H.B.X-P.X)<1E-8) and (Abs(H.B.Y-(P.Y+R.Y+0.006))<1E-8),'opaque hull contact');
      Q:=HeroMuzzle(H.Car,H.Launch);
      Need(Hypot(Q.X-H.A.X,Q.Y-H.A.Y)<1E-8,'muzzle');
      Need(HitAt(I,T,Q) and (Hypot(Q.X-H.B.X,Q.Y-H.B.Y)<1E-8),'impact endpoint');
    end
    else begin Q:=HeroCarAt(0,T);
      Need((Abs(H.B.X-(Q.X+0.062))<1E-8) and (Abs(H.B.X-(P.X-R.X))<1E-8),'ram contact');
    end;
    if I>0 then Need(FEvents[FHits[I-1].Source].Time<=T,'hit order');
  end;
  for I:=0 to ShotCount-1 do begin S:=FShots[I];
    Need(Finite(S.Start) and Finite(S.Near) and Finite(S.Finish) and (S.Start>=0) and (S.Near>S.Start) and (S.Finish>=S.Near) and (S.Finish<=FGoal+0.45+1E-7),'shot time');
    Need((S.Car>=0) and (S.Car<=7) and (S.Enemy>=0) and (S.Enemy<EnemyCount),'shot links');
    if I>0 then Need(S.Start>=FShots[I-1].Start,'shot order');
    if S.Outcome=2 then begin Q:=HeroCarAt(S.Car,S.Near);
      Need((Abs(S.B.X-(Q.X+0.037))<1E-8) and (Abs(S.B.Y-(Q.Y-0.047))<1E-8),'visible graze contact');
    end;
  end;
  for I:=1 to High(FCamera) do Need(FCamera[I].Time>FCamera[I-1].Time,'camera keys');
  for I:=1 to High(FScenes) do Need(FScenes[I].Time>FScenes[I-1].Time,'scene keys');
  for I:=0 to BossCount-1 do begin Need((FBosses[I].FirstSource>=0) and (FBosses[I].LastSource<PulseCount) and (FBosses[I].LastSource>FBosses[I].FirstSource) and (FBosses[I].Kill=FEvents[FBosses[I].LastSource].Time),'boss clock');
    Need(BossHP(I,FBosses[I].Kill)=0,'boss all parts');
  end;
end;

procedure AddRow(A:TJSONArray;const Values:array of Double);
var
  Row:TJSONArray;
  V:Double;
begin Row:=TJSONArray.Create;
  A.AddElement(Row);
  for V in Values do Row.AddElement(TJSONNumber.Create(V));
end;

function RowAt(A:TJSONArray;I,Count:Integer):TJSONArray;
begin if not (A.Items[I] is TJSONArray) then raise Exception.Create('Train row');
  Result:=TJSONArray(A.Items[I]);
  if Result.Count<>Count then raise Exception.Create('Train row size');
end;

function V(A:TJSONArray;I:Integer):Double;
begin Result:=A.Items[I].GetValue<Double>;
  if not Finite(Result) then raise Exception.Create('Train finite value');
end;

procedure TTrainPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var
  Root:TJSONObject;
  A:TJSONArray;
  E:TTrainEvent;
  G:TTrainGroup;
  N:TTrainEnemy;
  H:TTrainHit;
  S:TTrainShot;
  B:TTrainBoss;
  Scene:TTrainSceneKey;
  Cam:TTrainCameraKey;
begin
  if (Ref.Style<>rsTrain) or (Ref.Version<>1) or (BossFrequencyFromVariant(Ref.Variant)<>FFrequency) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsTrain,Ref.Variant) then raise Exception.Create('Train reference');
  Root:=TJSONObject.Create;
  try Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style','train');
    Root.AddPair('version',TJSONNumber.Create(1));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('variant',TJSONNumber.Create(Ref.Variant));
    Root.AddPair('policy','rail-battle-v1');
    AddPreparedAudio(Root,Audio);
    Root.AddPair('goal',TJSONNumber.Create(FGoal));
    Root.AddPair('end',TJSONNumber.Create(FEnd));
    Root.AddPair('intro',TJSONNumber.Create(FIntro));
    Root.AddPair('frequency',TJSONNumber.Create(FFrequency));
    Root.AddPair('excluded',TJSONNumber.Create(FExcluded));
    A:=TJSONArray.Create;
    Root.AddPair('events',A);
    for E in FEvents do AddRow(A,[E.Time,E.Power]);
    A:=TJSONArray.Create;
    Root.AddPair('groups',A);
    for G in FGroups do AddRow(A,[G.First,G.Last,G.Kind,G.Boss,G.Members,G.Show,G.Pass,G.X,G.Y,G.Speed]);
    A:=TJSONArray.Create;
    Root.AddPair('enemies',A);
    for N in FEnemies do AddRow(A,[N.Group,N.Slot,N.FirstSource,N.KillSource]);
    A:=TJSONArray.Create;
    Root.AddPair('hits',A);
    for H in FHits do AddRow(A,[H.Source,H.Enemy,H.Car,H.Mode,H.Launch,H.A.X,H.A.Y,H.B.X,H.B.Y]);
    A:=TJSONArray.Create;
    Root.AddPair('shots',A);
    for S in FShots do AddRow(A,[S.Start,S.Near,S.Finish,S.A.X,S.A.Y,S.B.X,S.B.Y,S.Enemy,S.Outcome,S.Car,S.Kind]);
    A:=TJSONArray.Create;
    Root.AddPair('bosses',A);
    for B in FBosses do AddRow(A,[B.Show,B.Kill,B.FirstSource,B.LastSource,B.Group,Ord(B.Boundary)]);
    A:=TJSONArray.Create;
    Root.AddPair('scenes',A);
    for Scene in FScenes do AddRow(A,[Scene.Time,Scene.Kind]);
    A:=TJSONArray.Create;
    Root.AddPair('camera',A);
    for Cam in FCamera do AddRow(A,[Cam.Time,Cam.Zoom]);
    if Length(Root.ToJSON)>30*1024*1024 then raise Exception.Create('Train prepared budget');
    WritePreparedData(Root,Ref);
  finally Root.Free;
  end;
end;

class function TTrainPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var
  Root:TJSONObject;
  A,Row:TJSONArray;
  I:Integer;
begin Root:=ReadPreparedData(Ref,rsTrain,Direction);
  try Result:=PreparedAudio(Root,Ref,Source);
    try A:=Root.GetValue<TJSONArray>('events');
      if (A=nil) or (A.Count>Length(Result.Hits)) then raise Exception.Create('Train metadata events');
      for I:=0 to A.Count-1 do begin Row:=RowAt(A,I,2);
        Result.Hits[I].Time:=V(Row,0);
        Result.Hits[I].Strength:=V(Row,1);
      end;
      Result.SetBossFrequency(BossFrequencyFromVariant(Ref.Variant));
    except Result.Free;
      raise;
    end;
  finally Root.Free;
  end;
end;

class function TTrainPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TTrainPlan;
var
  Root,Info:TJSONObject;
  A,R:TJSONArray;
  I:Integer;
  E:TTrainEvent;
  G:TTrainGroup;
  N:TTrainEnemy;
  H:TTrainHit;
  S:TTrainShot;
  B:TTrainBoss;
  Scene:TTrainSceneKey;
  Cam:TTrainCameraKey;
  function Items(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);
    if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Train array '+Name);
  end;
begin
  if Audio=nil then raise Exception.Create('Train audio metadata missing');
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsTrain,Ref.Variant) then raise Exception.Create('Train settings mismatch');
  Root:=ReadPreparedData(Ref,rsTrain,Direction);
  try
    if Root.GetValue<string>('policy','')<>'rail-battle-v1' then raise Exception.Create('Train policy');
    Info:=Root.GetValue<TJSONObject>('audio');
    if (Info=nil) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-7) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-7) then raise Exception.Create('Train metadata identity');
    Result:=TTrainPlan.Create;
    try Result.FDuration:=Audio.Duration;
      Result.FGoal:=Root.GetValue<Double>('goal');
      Result.FEnd:=Root.GetValue<Double>('end');
      Result.FIntro:=Root.GetValue<Double>('intro');
      Result.FFrequency:=Root.GetValue<Integer>('frequency');
      Result.FExcluded:=Root.GetValue<Integer>('excluded');
      Result.FSourceCount:=Length(Audio.Hits);
      if Result.FFrequency<>BossFrequencyFromVariant(Ref.Variant) then raise Exception.Create('Train frequency');
      A:=Items('events',100000);
      SetLength(Result.FEvents,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,2);
        E.Time:=V(R,0);
        E.Power:=V(R,1);
        Result.FEvents[I]:=E;
      end;
      A:=Items('groups',30000);
      SetLength(Result.FGroups,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,10);
        G.First:=Round(V(R,0));
        G.Last:=Round(V(R,1));
        G.Kind:=Round(V(R,2));
        G.Boss:=Round(V(R,3));
        G.Members:=Round(V(R,4));
        G.Show:=V(R,5);
        G.Pass:=V(R,6);
        G.X:=V(R,7);
        G.Y:=V(R,8);
        G.Speed:=V(R,9);
        Result.FGroups[I]:=G;
      end;
      A:=Items('enemies',60000);
      SetLength(Result.FEnemies,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,4);
        N.Group:=Round(V(R,0));
        N.Slot:=Round(V(R,1));
        N.FirstSource:=Round(V(R,2));
        N.KillSource:=Round(V(R,3));
        Result.FEnemies[I]:=N;
      end;
      A:=Items('hits',180000);
      SetLength(Result.FHits,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,9);
        H.Source:=Round(V(R,0));
        H.Enemy:=Round(V(R,1));
        H.Car:=Round(V(R,2));
        H.Mode:=Round(V(R,3));
        H.Launch:=V(R,4);
        H.A:=TrainPoint(V(R,5),V(R,6));
        H.B:=TrainPoint(V(R,7),V(R,8));
        Result.FHits[I]:=H;
      end;
      A:=Items('shots',80000);
      SetLength(Result.FShots,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,11);
        S.Start:=V(R,0);
        S.Near:=V(R,1);
        S.Finish:=V(R,2);
        S.A:=TrainPoint(V(R,3),V(R,4));
        S.B:=TrainPoint(V(R,5),V(R,6));
        S.Enemy:=Round(V(R,7));
        S.Outcome:=Round(V(R,8));
        S.Car:=Round(V(R,9));
        S.Kind:=Round(V(R,10));
        Result.FShots[I]:=S;
      end;
      A:=Items('bosses',64);
      SetLength(Result.FBosses,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,6);
        B.Show:=V(R,0);
        B.Kill:=V(R,1);
        B.FirstSource:=Round(V(R,2));
        B.LastSource:=Round(V(R,3));
        B.Group:=Round(V(R,4));
        B.Boundary:=V(R,5)<>0;
        Result.FBosses[I]:=B;
      end;
      A:=Items('scenes',2000);
      SetLength(Result.FScenes,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,2);
        Scene.Time:=V(R,0);
        Scene.Kind:=Round(V(R,1));
        Result.FScenes[I]:=Scene;
      end;
      A:=Items('camera',5000);
      SetLength(Result.FCamera,A.Count);
      for I:=0 to A.Count-1 do begin R:=RowAt(A,I,2);
        Cam.Time:=V(R,0);
        Cam.Zoom:=V(R,1);
        Result.FCamera[I]:=Cam;
      end;
      Result.Verify;
      Result.Reindex;
    except Result.Free;
      raise;
    end;
  finally Root.Free;
  end;
end;
end.
