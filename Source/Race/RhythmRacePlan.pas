unit RhythmRacePlan;
// Prepared race geometry. Pick-up clocks are copied from the shared accents.
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmRaceCrash;
const
  RACE_FOCUS=40.0;
  RACE_HORIZON=0.28;
  RACE_CONTACT_Y=0.80;
  RACE_COIN_HEIGHT=0.04;
  RACE_MIN_COIN_GAP=0.045;
  RACE_MAX_SECONDS=512.0*1024*1024/4/RHYTHM_RATE;
type
  TRaceKey=record
    Position,Value:Double;
  end;
  TRaceEvent=record
    Time,Strength:Double;
  end;
  TRaceCoin=record
    Time,Distance,Lane,Strength:Double;
    Source,Points:Integer;
  end;
  // All hazards are authored against a prepared lane-change opportunity.
  TRaceTraffic=record
    First,Last,Pass,Distance,Lane,Speed:Double;
    Graze:Boolean;
    Motion:Integer;
    ContactGap:Double;
  end;
  TRaceTrailer=record
    First,Last,Pass,Lane:Double;
  end;
  TRaceBomb=record
    Drop,Land,Pass,Burst,Clear,Distance,Lane:Double;
    Boss:Integer;
  end;
  TRacePose=record
    Curvature,Steer,Load,Offset:Double;
  end;
  TRaceProjection=record
    X,Y,Scale:Double;
    Visible:Boolean;
  end;
  TRacePlan=class
  private
    FCrash:TRaceCrashPlan;
    FEvents:TArray<TRaceEvent>;
    FCoins:TArray<TRaceCoin>;
    FLanes,FRoad:TArray<TRaceKey>;
    FDuration,FEnd,FSoundEnd,FLaunch,FAccel,FGoal,FTopSpeed:Double;
    FExcluded:Integer;
    FTraffic:TArray<TRaceTraffic>;
    FTrailers:TArray<TRaceTrailer>;
    FBombs:TArray<TRaceBomb>;
    FVersion,FBossFrequency:Integer;
    FFocus:Double;
    FScores:TArray<Integer>;
    class function BuildLegacy(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRacePlan; static;
    procedure BuildScores;
    procedure BuildTraffic(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
    procedure BuildConvoys(const Cancel:TFunc<Boolean>);
    function CarDistance(const V:TRaceTraffic;Time:Double):Double;
    function CarLane(const V:TRaceTraffic;Time:Double):Double;
    function FenderGap(Time,Side:Double):Double;
    function CarsApart(const A,B:TRaceTraffic):Boolean;
    function ConvoySafe(const Car:TRaceTraffic):Boolean;
    procedure ValidateTraffic(const Cancel:TFunc<Boolean>);
    function GetTrafficCount:Integer;
    function GetTrailerCount:Integer;
    function GetBombCount:Integer;
    function GetTraffic(Index:Integer):TRaceTraffic;
    function GetTrailer(Index:Integer):TRaceTrailer;
    function GetBomb(Index:Integer):TRaceBomb;
    procedure Validate(const Cancel:TFunc<Boolean> = nil);
    function GetCount:Integer;
    function GetCoin(Index:Integer):TRaceCoin;
    function GetLaneCount:Integer;
    function GetRoadCount:Integer;
  public
    destructor Destroy; override;
    property Crash:TRaceCrashPlan read FCrash;
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TRacePlan; static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRacePlan; static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio; static;
    function DistanceAt(Time:Double):Double;
    function SpeedAt(Time:Double):Double;
    function NearClip:Double;
    function PoseAt(Time:Double):TRacePose;
    function LaneAt(Time:Double):Double;
    function LaneVelocity(Time:Double):Double;
    function BendAt(Distance:Double):Double;
    function Project(Distance,Lane,Time,Height:Double):TRaceProjection;
    class function CoinMetal(Strength:Double):Integer; static;
    class function CoinPoints(Strength:Double):Integer; static;
    function ScoreAt(Time:Double):Integer;
    function MaxScore:Integer;
    procedure ImpactAt(Time:Double;out Roll,Heave,Power,Side:Double);
    property Focus:Double read FFocus;
    function TrafficDistance(Index:Integer;Time:Double):Double;
    function TrafficLaneAt(Index:Integer;Time:Double):Double;
    function TrafficTilt(Index:Integer;Time:Double):Double;
    function TrailerDistance(Index:Integer;Time:Double):Double;
    procedure BombPosition(Index:Integer;Time:Double;out Distance,Lane,Height:Double);
    property TrafficCount:Integer read GetTrafficCount;
    property TrailerCount:Integer read GetTrailerCount;
    property BombCount:Integer read GetBombCount;
    property Traffic[Index:Integer]:TRaceTraffic read GetTraffic;
    property Trailer[Index:Integer]:TRaceTrailer read GetTrailer;
    property Bomb[Index:Integer]:TRaceBomb read GetBomb;
    property BossFrequency:Integer read FBossFrequency;
    property Version:Integer read FVersion;
    function TrafficBefore(Time:Double):Integer;
    function BombDropBefore(Time:Double):Integer;
    function CoinBefore(Time:Double):Integer;
    function CoinAtDistance(Distance:Double):Integer;
    property Count:Integer read GetCount;
    property Coin[Index:Integer]:TRaceCoin read GetCoin;
    property LaneCount:Integer read GetLaneCount;
    property RoadCount:Integer read GetRoadCount;
    property Excluded:Integer read FExcluded;
    property EndTime:Double read FEnd;
    property LaunchTime:Double read FLaunch;
    property AccelerationTime:Double read FAccel;
    property GoalTime:Double read FGoal;
    property TopSpeed:Double read FTopSpeed;
  end;
implementation
uses System.Math,System.JSON,System.Generics.Collections,System.Generics.Defaults,RhythmStyles,RhythmPreparedData,RhythmSections;

destructor TRacePlan.Destroy;
begin FCrash.Free;
  inherited;
end;

class function TRacePlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRacePlan;
begin Result:=TRacePlan.Create;
  try Result.FCrash:=TRaceCrashPlan.Build(Audio,Cancel);
    Result.FVersion:=10;
    Result.FFocus:=RACE_FOCUS;
    Result.FDuration:=Result.FCrash.Duration;
    Result.FSoundEnd:=Result.FCrash.SoundEnd;
    Result.FEnd:=Result.FCrash.EndTime;
    Result.FLaunch:=Result.FCrash.Launch;
    Result.FAccel:=Result.FCrash.Acceleration;
    Result.FGoal:=Result.FCrash.Goal;
    Result.FTopSpeed:=Result.FCrash.TopSpeed;
    Result.FBossFrequency:=Result.FCrash.Frequency;
    Result.FExcluded:=Result.FCrash.Excluded;
  except Result.Free;
    raise;
  end;
end;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function KeyAt(const Keys:TArray<TRaceKey>;P:Double;Derivative:Boolean=False):Double;
var
  A,B,M:Integer;
  U,D:Double;
begin
  Result:=0;
  if Length(Keys)=0 then Exit;
  A:=0;
  B:=Length(Keys);
  while A<B do begin M:=(A+B) div 2;
    if Keys[M].Position<=P then A:=M+1 else B:=M;
  end;
  A:=Max(0,A-1);
  if A=High(Keys) then begin if not Derivative then Result:=Keys[A].Value;
    Exit;
  end;
  D:=Keys[A+1].Position-Keys[A].Position;
  U:=EnsureRange((P-Keys[A].Position)/D,0.0,1.0);
  if Derivative then Result:=(Keys[A+1].Value-Keys[A].Value)*6*U*(1-U)/D
  else Result:=Keys[A].Value+(Keys[A+1].Value-Keys[A].Value)*Smooth(U);
end;

function TRacePlan.DistanceAt(Time:Double):Double;
var
  T,U,A,Tail:Double;
begin
  if FCrash<>nil then Exit(FCrash.DistanceAt(Time));
  T:=EnsureRange(Time,0.0,FEnd);
  Result:=0;
  if T<=FLaunch then Exit;
  A:=FLaunch+FAccel;
  if T<A then begin U:=(T-FLaunch)/FAccel;
    Exit(FTopSpeed*FAccel*(U*U*U-0.5*U*U*U*U));
  end;
  Result:=0.5*FTopSpeed*FAccel+FTopSpeed*(Min(T,FGoal)-A);
  if T>FGoal then begin Tail:=FEnd-FGoal;
    U:=(T-FGoal)/Tail;
    Result:=Result+FTopSpeed*Tail*(U-U*U*U+0.5*U*U*U*U);
  end;
end;

function TRacePlan.SpeedAt(Time:Double):Double;
begin
  if FCrash<>nil then Exit(FCrash.SpeedAt(Time));
  if (Time<=FLaunch) or (Time>=FEnd) then Exit(0);
  if Time<FLaunch+FAccel then Exit(FTopSpeed*Smooth((Time-FLaunch)/FAccel));
  Result:=FTopSpeed;
  if Time>FGoal then Result:=FTopSpeed*(1-Smooth((Time-FGoal)/(FEnd-FGoal)));
end;

function TRacePlan.NearClip:Double;
begin Result:=FFocus*0.75;
  if FVersion>=3 then Result:=FFocus*0.85;
end;

function TRacePlan.PoseAt(Time:Double):TRacePose;
var
  Drive:Double;
  function Turn(T:Double):Double;
  begin Result:=EnsureRange(KeyAt(FRoad,DistanceAt(T),True)*1600*Sqr(SpeedAt(T)/FTopSpeed),-1.0,1.0);
  end;
begin
  if FCrash<>nil then begin Result:=Default(TRacePose);
    Result.Curvature:=FCrash.BendVelocity(FCrash.DistanceAt(Time));
    Result.Steer:=EnsureRange(Result.Curvature*1200+FCrash.LaneVelocity(Time)*0.7,-1.0,1.0);
    Result.Load:=-Result.Steer*0.6;
    Exit;
  end;
  Result:=Default(TRacePose);
  if FVersion<4 then Exit;
  Time:=EnsureRange(Time,0.0,FEnd);
  Drive:=Sqr(SpeedAt(Time)/FTopSpeed);
  Result.Curvature:=KeyAt(FRoad,DistanceAt(Time),True);
  Result.Steer:=EnsureRange((Turn(Time-0.08)+KeyAt(FLanes,Time,True)*0.65)*Drive,-1.0,1.0);
  Result.Load:=-(0.55*Turn(Time-0.22)+0.30*Turn(Time-0.40)+0.15*Turn(Time-0.62))*Drive;
  Result.Offset:=0.04*Result.Load;
end;

function TRacePlan.LaneAt(Time:Double):Double;
var
  P:TRacePose;
begin if FCrash<>nil then Exit(FCrash.LaneAt(Time));
  Result:=KeyAt(FLanes,Time);
  if FVersion>=4 then begin P:=PoseAt(Time);
    Result:=Result+P.Offset;
  end;
end;

function TRacePlan.LaneVelocity(Time:Double):Double;
var
  A,B:TRacePose;
begin if FCrash<>nil then Exit(FCrash.LaneVelocity(Time));
  Result:=KeyAt(FLanes,Time,True);
  if FVersion>=4 then begin A:=PoseAt(Time-0.01);
    B:=PoseAt(Time+0.01);
    Result:=Result+(B.Offset-A.Offset)/0.02;
  end;
end;

function TRacePlan.BendAt(Distance:Double):Double;
begin if FCrash<>nil then Exit(FCrash.BendAt(Distance));
  Result:=KeyAt(FRoad,Max(0.0,Distance));
end;

function TRacePlan.Project(Distance,Lane,Time,Height:Double):TRaceProjection;
var
  Camera,Z,Current:Double;
  CP:TCrashProjection;
begin
  if FCrash<>nil then begin CP:=FCrash.Project(Distance,Lane,Time,Height);
    Result.X:=CP.X;
    Result.Y:=CP.Y;
    Result.Scale:=CP.Scale;
    Result.Visible:=CP.Visible;
    Exit;
  end;
  Result:=Default(TRaceProjection);
  Camera:=DistanceAt(Time);
  Z:=Distance-Camera;
  if Z<=-NearClip then Exit;
  Result.Scale:=FFocus/(FFocus+Z);
  Current:=BendAt(Camera);
  Result.X:=0.8+0.12*Current+0.55*(BendAt(Max(0.0,Distance))-Current)*(1-Result.Scale)+0.58*Lane*Result.Scale;
  Result.Y:=RACE_HORIZON+(RACE_CONTACT_Y-RACE_HORIZON-Height)*Result.Scale;
  Result.Visible:=Z<=1400;
end;

function TRacePlan.CoinBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Count;
  while A<B do begin M:=(A+B) div 2;
    if FCoins[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TRacePlan.CoinAtDistance(Distance:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Count;
  while A<B do begin M:=(A+B) div 2;
    if FCoins[M].Distance<=Distance then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TRacePlan.GetCount:Integer;
begin Result:=Length(FCoins);
end;

function TRacePlan.GetCoin(Index:Integer):TRaceCoin;
begin Result:=FCoins[Index];
end;

function TRacePlan.GetLaneCount:Integer;
begin if FCrash<>nil then Exit(Length(FCrash.Keys));
  Result:=Length(FLanes);
end;

function TRacePlan.GetRoadCount:Integer;
begin if FCrash<>nil then Exit(Length(FCrash.Road));
  Result:=Length(FRoad);
end;

// Inverse smoothstep for 180 -> -42m, fixing the overtaking instant at Pass.

function ExitFraction(Version:Integer):Double;
var
  A,B,M:Double;
  I:Integer;
begin A:=0;
  B:=1;
  for I:=0 to 39 do begin M:=(A+B)/2;
    if ((Version<3) and (Smooth(M)<180/222)) or ((Version>=3) and (Smooth(M)<110/144)) then A:=M else B:=M;
  end;
  Result:=(A+B)/2;
end;

class function TRacePlan.CoinMetal(Strength:Double):Integer;
begin Result:=0;
  if Strength>=0.70 then Result:=2 else if Strength>=0.40 then Result:=1;
end;

class function TRacePlan.CoinPoints(Strength:Double):Integer;
begin case CoinMetal(Strength) of 2:Result:=100;
    1:Result:=50;
    else Result:=10;
  end;
end;

procedure TRacePlan.BuildScores;
var
  I:Integer;
begin SetLength(FScores,Count+1);
  FScores[0]:=0;
  for I:=0 to Count-1 do FScores[I+1]:=FScores[I]+FCoins[I].Points;
end;

function TRacePlan.ScoreAt(Time:Double):Integer;
begin if FCrash<>nil then Exit(FCrash.HitBefore(Time)+1);
  Result:=FScores[CoinBefore(Time)+1];
end;

function TRacePlan.MaxScore:Integer;
begin if FCrash<>nil then Exit(Length(FCrash.Hits));
  Result:=FScores[Count];
end;

procedure TRacePlan.ImpactAt(Time:Double;out Roll,Heave,Power,Side:Double);
var
  I:Integer;
  Age,U,Envelope:Double;
  V:TRaceTraffic;
begin
  Roll:=0;
  Heave:=0;
  Power:=0;
  Side:=0;
  if FVersion<3 then Exit;
  for I:=Max(0,TrafficBefore(Time-0.50)+1) to TrafficBefore(Time) do begin V:=FTraffic[I];
    if not V.Graze then Continue;
    Age:=Time-V.Pass;
    if (Age<0) or (Age>=0.42) then Continue;
    U:=Age/0.42;
    Envelope:=Smooth(U/0.18)*(1-Smooth(U));
    // Fast onset, then damped rebound. The path and coin socket do not move.
    Side:=Sign(V.Lane-LaneAt(V.Pass));
    Power:=Envelope;
    Roll:=-Side*0.035*Envelope*Cos(U*Pi*2);
    Heave:=0.006*Envelope;
    if FVersion>=6 then begin Roll:=Roll*(0.055/0.035);
      Heave:=0.012*Envelope;
    end;
  end;
end;

function TRacePlan.GetTrafficCount:Integer;
begin Result:=Length(FTraffic);
end;

function TRacePlan.GetTrailerCount:Integer;
begin Result:=Length(FTrailers);
end;

function TRacePlan.GetBombCount:Integer;
begin Result:=Length(FBombs);
end;

function TRacePlan.GetTraffic(Index:Integer):TRaceTraffic;
begin Result:=FTraffic[Index];
end;

function TRacePlan.GetTrailer(Index:Integer):TRaceTrailer;
begin Result:=FTrailers[Index];
end;

function TRacePlan.GetBomb(Index:Integer):TRaceBomb;
begin Result:=FBombs[Index];
end;

function TRacePlan.CarDistance(const V:TRaceTraffic;Time:Double):Double;
var
  A,Phase:Double;
begin A:=Time-V.Pass;
  Result:=V.Distance+V.Speed*A;
  if FVersion>=6 then begin Phase:=V.Motion*0.8;
    Result:=Result+V.Speed*0.12*(Cos(Phase)-Cos(Phase+A*2.2));
  end;
end;

function TRacePlan.CarLane(const V:TRaceTraffic;Time:Double):Double;
var
  A,Side,Base,Blend,Gap,Contact:Double;
begin
  A:=Time-V.Pass;
  Result:=V.Lane;
  Side:=Sign(V.Lane-LaneAt(V.Pass));
  if FVersion<6 then begin if (FVersion>=3) and V.Graze and (A>=0) and (A<0.42) then Result:=Result+Side*0.03*Smooth(A/0.08)*(1-Smooth(A/0.42));
    Exit;
  end;
  Base:=V.Lane;
  if V.Motion<>0 then Base:=EnsureRange(Base+Side*0.20*(1-Smooth((A+1.4)/1.1)),-0.84,0.84);
  if V.Graze then begin
    Base:=Base+Side*0.16*Smooth(A/0.12);
    Blend:=Smooth((A+1.0)/0.65)*(1-Smooth((A-0.65)/0.35));
    Contact:=0.34;
    if FVersion>=7 then Contact:=V.ContactGap;
    Gap:=Contact+0.24*Smooth(-A/0.12)+0.18*Smooth(A/0.12);
    Base:=Base*(1-Blend)+(LaneAt(Time)+Side*Gap)*Blend;
  end;
  Result:=EnsureRange(Base,-0.84,0.84);
end;

function TRacePlan.TrafficDistance(Index:Integer;Time:Double):Double;
begin Result:=CarDistance(FTraffic[Index],Time);
end;

function TRacePlan.TrafficLaneAt(Index:Integer;Time:Double):Double;
begin Result:=CarLane(FTraffic[Index],Time);
end;

function TRacePlan.TrafficTilt(Index:Integer;Time:Double):Double;
var
  V:TRaceTraffic;
  A:Double;
begin Result:=0;
  if FVersion<6 then Exit;
  V:=FTraffic[Index];
  A:=Time-V.Pass;
  Result:=(CarLane(V,Time+0.02)-CarLane(V,Time-0.02))/0.04*0.045;
  if V.Graze and (A>=0) and (A<0.50) then Result:=Result+Sign(V.Lane-LaneAt(V.Pass))*0.055*Sin(Pi*A/0.50);
  Result:=EnsureRange(Result,-0.075,0.075);
end;

function TRacePlan.FenderGap(Time,Side:Double):Double;
var
  P:TRacePose;
  BaseY,Compression,Extent,V,W,Depth,Offset,Factor,A0,A1,X0,Y0,X1,Y1,U:Double;
  I:Integer;
  procedure TirePoint(X,Y:Double;out PX,PY:Double);
  var
    D:Double;
  begin D:=Y/0.20;
    PX:=X*(1+P.Steer*D*0.12)-P.Steer*D*0.055+P.Load*(0.6-D)*0.007;
    PY:=BaseY+Y*Compression;
  end;
begin
  P:=PoseAt(Time);
  BaseY:=0.845+0.0015*Sin(Time*63);
  Compression:=1-Abs(P.Load)*0.015;
  Extent:=0;
  // Same 24 body strips and two steered front tyres as DrawSteeringVehicle.
  for I:=0 to 23 do begin V:=-0.112+I*0.0085;
    W:=0.057+0.037*EnsureRange((V+0.112)/0.14,0.0,1.0);
    Depth:=(V+0.0045)/0.20;
    Offset:=-P.Steer*Depth*0.055+P.Load*(0.6-Depth)*0.007;
    Factor:=1+P.Steer*Depth*0.12;
    if (0.792>=BaseY+V*Compression) and (0.792<=BaseY+(V+0.009)*Compression) then Extent:=Max(Extent,W*Factor+Side*Offset);
  end;
  for I:=-1 to 1 do if I<>0 then begin TirePoint(I*0.074+P.Steer*0.011,-0.078,X0,Y0);
    TirePoint(I*0.074-P.Steer*0.011,-0.032,X1,Y1);
    if (0.792>=Y0) and (0.792<=Y1) then begin U:=(0.792-Y0)/(Y1-Y0);
      Extent:=Max(Extent,Side*(X0+(X1-X0)*U)+0.0095);
    end;
  end;
  A0:=Extent+0.075*1.13;
  A1:=0.012;
  Result:=EnsureRange((A0-A1)/0.58,0.20,0.32);
end;

function TRacePlan.CarsApart(const A,B:TRaceTraffic):Boolean;
var
  First,Last,T:Double;
  I,N:Integer;
begin Result:=True;
  First:=Max(A.First,B.First);
  Last:=Min(A.Last,B.Last);
  if Last<=First then Exit;
  N:=Ceil((Last-First)/0.02);
  for I:=0 to N do begin T:=First+(Last-First)*I/N;
    if (Abs(CarDistance(A,T)-CarDistance(B,T))<36) and (Abs(CarLane(A,T)-CarLane(B,T))<0.42) then Exit(False);
  end;
end;

function TRacePlan.TrailerDistance(Index:Integer;Time:Double):Double;
var
  V:TRaceTrailer;
  Z,ExitStart,Span:Double;
begin
  V:=FTrailers[Index];
  Span:=7.5;
  if FVersion>=3 then Span:=4.6;
  ExitStart:=V.Pass-Span*ExitFraction(FVersion);
  if FVersion>=3 then begin Z:=110;
    if Time<V.First+3 then Z:=220-110*Smooth((Time-V.First)/3)
    else if Time>ExitStart then Z:=110-144*Smooth((Time-ExitStart)/Span);
  end
  else begin Z:=180;
    if Time<V.First+3 then Z:=280-100*Smooth((Time-V.First)/3)
    else if Time>ExitStart then Z:=180-222*Smooth((Time-ExitStart)/Span);
  end;
  Result:=DistanceAt(Time)+Z;
end;

procedure TRacePlan.BombPosition(Index:Integer;Time:Double;out Distance,Lane,Height:Double);
var
  B:TRaceBomb;
  U:Double;
begin
  B:=FBombs[Index];
  Distance:=B.Distance;
  Lane:=B.Lane;
  Height:=0.015;
  if Time<B.Land then begin U:=EnsureRange((Time-B.Drop)/(B.Land-B.Drop),0.0,1.0);
    Distance:=TrailerDistance(B.Boss,B.Drop)*(1-U)+B.Distance*U;
    Lane:=FTrailers[B.Boss].Lane*(1-Smooth(U))+B.Lane*Smooth(U);
    Height:=0.18*(1-U)+0.12*4*U*(1-U)+0.015*U;
  end;
end;

procedure TRacePlan.BuildTraffic(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
var
  Cars:TList<TRaceTraffic>;
  Bosses:TList<TRaceTrailer>;
  Bombs:TList<TRaceBomb>;
  I,J,K,Shot,ExitKey:Integer;
  Pass,BeginAt,EndAt,Previous,ExitStart,Side,BasePass:Double;
  Pose:TRacePose;
  Cue:TRhythmBossCue;
  V:TRaceTraffic;
  Boss:TRaceTrailer;
  Bomb:TRaceBomb;
  Inside:Boolean;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
  function Maneuver(Index:Integer):Boolean;
  begin Result:=(Index>0) and (Abs(FLanes[Index].Value-FLanes[Index-1].Value)>=0.50) and
    (FLanes[Index].Position-FLanes[Index-1].Position>=2.1) and (FLanes[Index].Position+1.5<FGoal);
  end;
begin
  FBossFrequency:=Audio.BossFrequency;
  Cars:=TList<TRaceTraffic>.Create;
  Bosses:=TList<TRaceTrailer>.Create;
  Bombs:=TList<TRaceBomb>.Create;
  try
    Previous:=-8;
    for I:=0 to Audio.BossCount-1 do begin Check;
      Cue:=Audio.BossCue(I);
      BeginAt:=Max(Max(Cue.StartTime,FLaunch+FAccel+3),Previous+8);
      EndAt:=Min(Cue.KillTime,FGoal-2);
      ExitKey:=-1;
      for J:=1 to High(FLanes) do if Maneuver(J) then begin Pass:=FLanes[J].Position+0.50;
        if (Pass>=BeginAt+13) and (Pass+4.6*(1-ExitFraction(3))<=EndAt) then ExitKey:=J;
      end;
      if (ExitKey<0) or (Bosses.Count>=256) then Continue;
      Boss.First:=BeginAt;
      Boss.Pass:=FLanes[ExitKey].Position+0.50;
      Boss.Last:=Boss.Pass+4.6*(1-ExitFraction(3));
      Side:=Sign(FLanes[ExitKey-1].Value-FLanes[ExitKey].Value);
      Boss.Lane:=LaneAt(Boss.Pass)+Side*0.63;
      Bosses.Add(Boss);
      Previous:=Boss.Last;
    end;
    FTrailers:=Bosses.ToArray;
    for I:=0 to TrailerCount-1 do begin Check;
      Boss:=FTrailers[I];
      ExitStart:=Boss.Pass-4.6*ExitFraction(3);
      for J:=1 to High(FLanes) do if Maneuver(J) then begin BasePass:=FLanes[J].Position+0.50;
        for Shot:=0 to 3 do begin Pass:=BasePass+Shot*0.45;
          Bomb.Drop:=Pass-0.60;
          Bomb.Land:=Pass-0.22;
          if (Bomb.Drop<Boss.First+3.2) or (Bomb.Drop>ExitStart-0.15) then Continue;
          Bomb.Pass:=Pass;
          Bomb.Distance:=DistanceAt(Pass);
          Pose:=PoseAt(Pass);
          Bomb.Lane:=FLanes[J-1].Value+Pose.Offset;
          if Shot mod 2=1 then begin
            if Abs(FLanes[J].Value)>0.30 then Bomb.Lane:=-Sign(FLanes[J].Value)*0.58+Pose.Offset
            else Bomb.Lane:=-Sign(FLanes[J-1].Value)*0.58+Pose.Offset;
          end;
          Bomb.Burst:=Pass-0.04;
          Bomb.Clear:=Pass+0.40;
          Bomb.Boss:=I;
          if Bomb.Distance>TrailerDistance(I,Bomb.Drop)-5 then Continue;
          if FVersion>=5 then begin Inside:=False;
            for K:=0 to 40 do begin Pass:=Bomb.Drop+(Bomb.Clear-Bomb.Drop)*K/40;
              if (Abs(Bomb.Distance-DistanceAt(Pass))<=18+FTopSpeed*0.025) and (Abs(Bomb.Lane-LaneAt(Pass))<=0.435) then Inside:=True;
            end;
            if Inside then Continue;
          end;
          Bombs.Add(Bomb);
        end;
      end;
    end;
    FBombs:=Bombs.ToArray;
    // A cue without a visible attack is a normal stretch, never an empty boss.
    // The 13s minimum above guarantees an intervening 3.6s maneuver in normal plans.
    Previous:=-8;
    for I:=1 to High(FLanes) do if Maneuver(I) then begin Check;
      Pass:=FLanes[I].Position+0.50;
      if (Pass-Previous<3.4) or (Pass+2.2>=FGoal) or (Pass-2.9<FLaunch+FAccel+1) then Continue;
      Inside:=False;
      for K:=0 to TrailerCount-1 do if (Pass+0.9>FTrailers[K].First-1) and (Pass-2.9<FTrailers[K].Last+2) then Inside:=True;
      if Inside then Continue;
      V.First:=Pass-2.9;
      V.Last:=Pass+0.9;
      V.Pass:=Pass;
      V.Distance:=DistanceAt(Pass);
      V.Speed:=FTopSpeed*0.38;
      V.Graze:=Cars.Count mod 3=1;
      Side:=Sign(FLanes[I-1].Value-FLanes[I].Value);
      V.Lane:=LaneAt(Pass)+Side*0.44;
      if V.Graze then V.Lane:=LaneAt(Pass)+Side*0.34;
      V.Motion:=Cars.Count mod 3;
      if V.Graze then V.Motion:=3;
      V.Speed:=FTopSpeed*(0.34+0.13*V.Motion);
      V.Last:=Pass+2.2;
      V.ContactGap:=0;
      if V.Graze then V.ContactGap:=FenderGap(V.Pass,Sign(V.Lane-LaneAt(V.Pass)));
      Cars.Add(V);
      Previous:=Pass;
      if Cars.Count>=1024 then Break;
    end;
    FTraffic:=Cars.ToArray;
    BuildConvoys(Cancel);
  finally Bombs.Free;
    Bosses.Free;
    Cars.Free;
  end;
end;

function TRacePlan.TrafficBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=TrafficCount;
  while A<B do begin M:=(A+B) div 2;
    if FTraffic[M].Pass<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TRacePlan.BombDropBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=BombCount;
  while A<B do begin M:=(A+B) div 2;
    if FBombs[M].Drop<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TRacePlan.ConvoySafe(const Car:TRaceTraffic):Boolean;
var
  I,J,N:Integer;
  T,D,Separation:Double;
  Boss:TRaceTrailer;
begin Result:=False;
  N:=Ceil((Car.Last-Car.First)/0.025);
  for I:=0 to N do begin T:=Car.First+(Car.Last-Car.First)*I/N;
    D:=CarDistance(Car,T);
    if Abs(D-DistanceAt(T))<=16+FTopSpeed*0.025 then begin Separation:=Abs(CarLane(Car,T)-LaneAt(T));
      if Car.Graze then begin if ((FVersion>=7) and (Separation<0.19)) or ((FVersion<7) and (Separation<0.32)) or (Separation>0.76) then Exit;
      end else if ((FVersion>=6) and (Separation<=0.45)) or ((FVersion<6) and (Separation<=0.41)) then Exit;
    end;
    for J:=0 to TrailerCount-1 do begin Boss:=FTrailers[J];
      if (T<Boss.First) or (T>Boss.Last) then Continue;
      if (Abs(D-TrailerDistance(J,T))<38) and (Abs(CarLane(Car,T)-Boss.Lane)<0.53+0.02*Ord(FVersion>=6)) then Exit;
    end;
  end;
  Result:=True;
end;

procedure TRacePlan.BuildConvoys(const Cancel:TFunc<Boolean>);
var
  Cars:TList<TRaceTraffic>;
  I,J,K,Slot,Slots,SideIndex,Column:Integer;
  Base,Offset:Double;
  Busy,Good:Boolean;
  V:TRaceTraffic;
begin Cars:=TList<TRaceTraffic>.Create;
  try for V in FTraffic do if ConvoySafe(V) then begin Good:=True;
      for K:=0 to Cars.Count-1 do if not CarsApart(V,Cars[K]) then Good:=False;
      if Good then Cars.Add(V);
    end;
    for I:=1 to High(FLanes) do begin if Assigned(Cancel) and Cancel() then Abort;
      if (Abs(FLanes[I].Value-FLanes[I-1].Value)<0.50) or (FLanes[I].Position-FLanes[I-1].Position<2.1) then Continue;
      Base:=FLanes[I].Position+0.50;
      Busy:=(I div 2) mod 4=2;
      for J:=0 to TrailerCount-1 do if (Base>FTrailers[J].First+2) and (Base<FTrailers[J].Pass-1) then Busy:=True;
      Slots:=1;
      if Busy then Slots:=5;
      for Slot:=0 to Slots-1 do for SideIndex:=-1 to 1 do if SideIndex<>0 then for Column:=0 to 1 do begin
        V.Motion:=((I div 2)+Column+Ord(SideIndex>0)) mod 3;
        if (Column=0) and (Slot=(Slots-1) div 2) and ((I div 2) mod 3=1) then V.Motion:=3;
        V.Pass:=Base+(Slot-(Slots-1)/2)*(0.42+V.Motion*0.29);
        V.First:=V.Pass-2.9;
        V.Last:=V.Pass+2.2;
        V.Distance:=DistanceAt(V.Pass);
        V.Speed:=FTopSpeed*(0.34+0.13*V.Motion);
        V.Graze:=V.Motion=3;
        Offset:=0.48+Column*0.36;
        if V.Graze then Offset:=0.34;
        V.Lane:=LaneAt(V.Pass)+SideIndex*Offset;
        V.ContactGap:=0;
        if V.Graze then V.ContactGap:=FenderGap(V.Pass,SideIndex);
        if (V.First<FLaunch+FAccel+1) or (V.Last>=FGoal) or (Abs(V.Lane)>0.84) or (Cars.Count>=8192) then Continue;
        Good:=True;
        for K:=0 to Cars.Count-1 do if not CarsApart(V,Cars[K]) then begin Good:=False;
          Break;
        end;
        if Good and ConvoySafe(V) then Cars.Add(V);
      end;
    end;
    Cars.Sort(TComparer<TRaceTraffic>.Construct(function(const A,B:TRaceTraffic):Integer
    begin Result:=0;if A.Pass<B.Pass then Exit(-1);if A.Pass>B.Pass then Exit(1);if A.Lane<B.Lane then Exit(-1);if A.Lane>B.Lane then Exit(1);end));
    FTraffic:=Cars.ToArray;
  finally Cars.Free;
  end;
end;

procedure TRacePlan.ValidateTraffic(const Cancel:TFunc<Boolean>);
var
  I,J,K,Steps:Integer;
  T,D,L,H,Previous,ExitStart,StartD,Span,FirstGap,LastGap,SpeedRatio,DropGap,LandGap,BurstGap,ClearGap,MainHalf,PassGap,LaneLimit,BombGap,GrazeGap,NearGap,CarLaneLimit,CarWidth:Double;
  V:TRaceTraffic;
  B:TRaceBomb;
  Boss:TRaceTrailer;
  procedure Need(Value:Boolean;const Why:string);
  begin if not Value then raise Exception.Create('Race traffic: '+Why);
  end;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
  procedure ClearAt(Time,Distance,Lane,LengthRadius,WidthRadius:Double;Graze:Boolean=False);
  begin
    // 25ms sweep + conservative motion margins: checks body and blast widths,
    // not merely the authored central passing instant.
    if Abs(Distance-DistanceAt(Time))<=LengthRadius+FTopSpeed*0.025 then begin
      if Graze then begin
        if FVersion>=7 then Need((Abs(Lane-LaneAt(Time))>=0.18) and (Abs(Lane-LaneAt(Time))<=0.78),'excessive impact')
        else if FVersion>=6 then Need((Abs(Lane-LaneAt(Time))>=0.30) and (Abs(Lane-LaneAt(Time))<=0.78),'excessive impact')
        else if FVersion>=4 then Need((Abs(Lane-LaneAt(Time))>=0.32) and (Abs(Lane-LaneAt(Time))<=0.40),'excessive impact')
        else Need((Abs(Lane-LaneAt(Time))>=0.30) and (Abs(Lane-LaneAt(Time))<=0.37),'excessive impact');
      end else Need(Abs(Lane-LaneAt(Time))>MainHalf+WidthRadius+0.02,'collision');
    end;
  end;
begin
  Need((FVersion in [1,2,3,4,5,6,7]) and (FBossFrequency>=0) and (FBossFrequency<=100),'version/frequency');
  Need((TrafficCount<=8192) and (TrailerCount<=256) and (BombCount<=4096),'counts');
  if FVersion=1 then begin Need((TrafficCount+TrailerCount+BombCount=0),'legacy hazards');
    Exit;
  end;
  Span:=7.5;
  FirstGap:=3.4;
  LastGap:=1.2;
  SpeedRatio:=0.55;
  DropGap:=1.6;
  LandGap:=0.75;
  BurstGap:=0.10;
  ClearGap:=0.55;
  if FVersion>=3 then begin Span:=4.6;
    FirstGap:=2.9;
    LastGap:=0.9;
    SpeedRatio:=0.38;
    DropGap:=0.60;
    LandGap:=0.22;
    BurstGap:=0.04;
    ClearGap:=0.40;
  end;
  MainHalf:=0.20;
  PassGap:=7;
  LaneLimit:=0.62;
  BombGap:=2;
  GrazeGap:=0.32;
  NearGap:=0.42;
  if FVersion>=4 then begin MainHalf:=0.22;
    PassGap:=3.4;
    LaneLimit:=0.68;
    BombGap:=0.75;
    GrazeGap:=0.34;
    NearGap:=0.44;
  end;
  CarLaneLimit:=LaneLimit;
  if FVersion>=5 then begin CarLaneLimit:=0.84;
    BombGap:=0.35;
  end;
  CarWidth:=0.15;
  if FVersion>=6 then begin CarWidth:=0.17;
    LastGap:=2.2;
  end;
  if FBossFrequency=0 then Need(TrailerCount=0,'boss disabled');
  Previous:=-8;
  for I:=0 to TrailerCount-1 do begin Check;
    Boss:=FTrailers[I];
    Need(Finite(Boss.First) and Finite(Boss.Last) and Finite(Boss.Pass) and Finite(Boss.Lane),'boss finite');
    ExitStart:=Boss.Pass-Span*ExitFraction(FVersion);
    Need((Boss.First>=FLaunch+FAccel+3) and (Boss.First>=Previous+8-1E-7) and (ExitStart>Boss.First+3) and
    (Abs(Boss.Last-(Boss.Pass+Span*(1-ExitFraction(FVersion))))<1E-7) and (Boss.Last<=FGoal-2+1E-7) and (Abs(Boss.Lane)<=LaneLimit),'boss phase');
    Need(Abs(TrailerDistance(I,Boss.Pass)-DistanceAt(Boss.Pass))<1E-6,'boss overtake');
    J:=0;
    for B in FBombs do if B.Boss=I then Inc(J);
    Need(J>0,'boss without attack');
    Steps:=Ceil((Boss.Last-Boss.First)/0.025);
    StartD:=TrailerDistance(I,Boss.First);
    for J:=0 to Steps do begin Check;
      T:=Boss.First+(Boss.Last-Boss.First)*J/Steps;
      D:=TrailerDistance(I,T);
      if FVersion>=3 then ClearAt(T,D,Boss.Lane,18,0.33) else ClearAt(T,D,Boss.Lane,28,0.26);
      if J>0 then Need(D>StartD,'reversing trailer');
      StartD:=D;
    end;
    Previous:=Boss.Last;
  end;
  Previous:=-8;
  for I:=0 to TrafficCount-1 do begin Check;
    V:=FTraffic[I];
    Need(Finite(V.First) and Finite(V.Last) and Finite(V.Pass) and Finite(V.Distance) and Finite(V.Lane) and Finite(V.Speed),'car finite');
    Need((V.First>=FLaunch+FAccel+1) and (Abs(V.First-(V.Pass-FirstGap))<1E-7) and (Abs(V.Last-(V.Pass+LastGap))<1E-7) and
    (V.Last<FGoal) and ((FVersion>=5) or (V.Pass-Previous>=PassGap-1E-7)) and ((FVersion>=6) or (Abs(V.Speed-FTopSpeed*SpeedRatio)<1E-7)) and (Abs(V.Lane)<=CarLaneLimit+1E-8) and
    (Abs(V.Distance-DistanceAt(V.Pass))<1E-6),'car phase');
    if FVersion>=6 then Need((V.Motion in [0,1,2,3]) and (V.Graze=(V.Motion=3)) and (Abs(V.Speed-FTopSpeed*(0.34+0.13*V.Motion))<1E-7),'car motion');
    if FVersion>=7 then begin Need(Finite(V.ContactGap),'contact gap');
      if V.Graze then Need((V.ContactGap>=0.20) and (V.ContactGap<=0.32) and (Abs(V.ContactGap-FenderGap(V.Pass,Sign(V.Lane-LaneAt(V.Pass))))<1E-7),'fender contact recipe') else Need(V.ContactGap=0,'non-contact gap');
    end;
    if FVersion>=5 then Need(ConvoySafe(V),'convoy trajectory')
    else if FVersion<3 then Need(not V.Graze,'legacy impact')
    else if V.Graze then Need((I mod 3=1) and (Abs(Abs(V.Lane-LaneAt(V.Pass))-GrazeGap)<1E-7),'impact recipe')
    else Need(Abs(Abs(V.Lane-LaneAt(V.Pass))-NearGap)<1E-7,'near pass recipe');
    if FVersion<5 then for Boss in FTrailers do Need((V.Last<=Boss.First-1) or (V.First>=Boss.Last+2),'car/boss overlap');
    Steps:=Ceil((V.Last-V.First)/0.025);
    for J:=0 to Steps do begin Check;
      T:=V.First+(V.Last-V.First)*J/Steps;
      ClearAt(T,TrafficDistance(I,T),TrafficLaneAt(I,T),16,CarWidth,(FVersion>=3) and V.Graze);
    end;
    if FVersion>=5 then begin
      if I>0 then Need(V.Pass>=FTraffic[I-1].Pass,'convoy order');
      if FVersion>=6 then Need(TrafficBefore(V.Pass+5.1)-I<128,'active convoy cap');
      for K:=Max(0,TrafficBefore(V.Pass-5.1)+1) to I-1 do if FVersion>=6 then Need(CarsApart(V,FTraffic[K]),'convoy pair contact') else if Abs(FTraffic[K].Pass-V.Pass)<0.40 then Need(Abs(FTraffic[K].Lane-V.Lane)>=0.34,'stacked convoy cars');
    end;
    Previous:=V.Pass;
  end;
  for I:=0 to BombCount-1 do begin Check;
    B:=FBombs[I];
    Need(Finite(B.Drop) and Finite(B.Land) and Finite(B.Pass) and Finite(B.Burst) and Finite(B.Clear) and Finite(B.Distance) and Finite(B.Lane),'bomb finite');
    Need((B.Boss>=0) and (B.Boss<TrailerCount),'bomb owner');
    Boss:=FTrailers[B.Boss];
    ExitStart:=Boss.Pass-Span*ExitFraction(FVersion);
    Need((B.Drop>=Boss.First+3.2) and (B.Drop<=ExitStart-0.15) and (Abs(B.Drop-(B.Pass-DropGap))<1E-7) and
    (Abs(B.Land-(B.Pass-LandGap))<1E-7) and (Abs(B.Burst-(B.Pass-BurstGap))<1E-7) and (Abs(B.Clear-(B.Pass+ClearGap))<1E-7) and
    (B.Clear<Boss.Last) and (Abs(B.Lane)<=LaneLimit) and (Abs(B.Distance-DistanceAt(B.Pass))<1E-6) and
    (B.Distance<=TrailerDistance(B.Boss,B.Drop)-5+1E-6),'bomb phase');
    BombPosition(I,B.Drop,D,L,H);
    Need((Abs(D-TrailerDistance(B.Boss,B.Drop))<1E-7) and (Abs(L-Boss.Lane)<1E-7),'bomb origin');
    BombPosition(I,B.Land,D,L,H);
    Need((Abs(D-B.Distance)<1E-7) and (Abs(L-B.Lane)<1E-7) and (Abs(H-0.015)<1E-7),'bomb landing');
    Steps:=Ceil((B.Clear-B.Drop)/0.025);
    for J:=0 to Steps do begin Check;
      T:=B.Drop+(B.Clear-B.Drop)*J/Steps;
      BombPosition(I,T,D,L,H);
      ClearAt(T,D,L,18,0.17);
    end;
    for J:=0 to I-1 do if FBombs[J].Boss=B.Boss then Need(Abs(FBombs[J].Pass-B.Pass)>=BombGap,'bomb overlap');
  end;
end;

class function TRacePlan.BuildLegacy(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRacePlan;
var
  Lanes,Road:TList<TRaceKey>;
  Coins:TList<TRaceCoin>;
  K:TRaceKey;
  C:TRaceCoin;
  I,N,Best:Integer;
  T,Target,Mean,Start,Stop,Gap,WindowEnd,Last,Previous:Double;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
  procedure AddLane(P,V:Double);
  begin K.Position:=P;
    K.Value:=V;
    Lanes.Add(K);
  end;
  procedure Commit;
  begin
    if Best<0 then Exit;
    C.Source:=Best;
    C.Time:=Result.FEvents[Best].Time;
    C.Strength:=Result.FEvents[Best].Strength;
    C.Points:=CoinPoints(C.Strength);
    C.Distance:=Result.DistanceAt(C.Time);
    C.Lane:=Result.LaneAt(C.Time);
    Coins.Add(C);
    Last:=C.Time;
    Best:=-1;
  end;
begin
  Result:=nil;
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.Duration>RACE_MAX_SECONDS) or
  (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then raise Exception.Create('Invalid race audio');
  Lanes:=TList<TRaceKey>.Create;
  Road:=TList<TRaceKey>.Create;
  Coins:=TList<TRaceCoin>.Create;
  try
    Result:=TRacePlan.Create;
    Result.FVersion:=7;
    Result.FFocus:=RACE_FOCUS;
    try
      Result.FDuration:=Audio.Duration;
      Result.FSoundEnd:=Audio.SoundEnd;
      Result.FEnd:=Audio.Duration;
      if Audio.SoundEnd>0 then Result.FEnd:=Audio.SoundEnd;
      Result.FLaunch:=Min(1.25,Result.FEnd*0.10);
      Result.FGoal:=Result.FEnd-Min(1.35,Result.FEnd*0.15);
      Result.FAccel:=Min(1.8,(Result.FGoal-Result.FLaunch)*0.25);
      SetLength(Result.FEvents,Length(Audio.Hits));
      Previous:=-1;
      Mean:=0;
      for I:=0 to High(Audio.Hits) do begin Check;
        if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or (Audio.Hits[I].Time<Previous) or
        (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('Invalid race accents');
        Result.FEvents[I].Time:=Audio.Hits[I].Time;
        Result.FEvents[I].Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);
        Previous:=Audio.Hits[I].Time;
        Mean:=Mean+Result.FEvents[I].Strength;
      end;
      Mean:=Mean/Max(1,Length(Audio.Hits));
      Result.FTopSpeed:=(82+20*Mean)*1.65;
      AddLane(0,0);
      T:=Min(Result.FGoal,Result.FLaunch+Result.FAccel+0.6);
      if T>0 then AddLane(T,0);
      N:=1;
      Target:=0;
      while T+2.2<Result.FGoal-0.4 do begin Check;
        T:=T+2.2;
        Target:=0.58*Sin(N*Pi/2);
        AddLane(T,Target);
        Inc(N);
        if T+1.4<Result.FGoal-0.4 then begin T:=T+1.4;
          AddLane(T,Target);
        end;
      end;
      if Lanes[Lanes.Count-1].Position<Result.FGoal then AddLane(Result.FGoal,Target);
      AddLane(Result.FEnd,Target);
      Result.FLanes:=Lanes.ToArray;
      N:=Ceil((Result.DistanceAt(Result.FEnd)+1500)/720);
      for I:=0 to N do begin Check;
        K.Position:=I*720;
        K.Value:=EnsureRange(0.22*Sin(I*1.13)+0.08*Sin(I*0.43),-0.28,0.28);
        Road.Add(K);
      end;
      Result.FRoad:=Road.ToArray;
      Start:=Result.FLaunch+Result.FAccel*0.60;
      Stop:=Result.FGoal-Min(0.20,(Result.FGoal-Result.FLaunch)*0.08);
      Gap:=RACE_MIN_COIN_GAP;
      Best:=-1;
      Last:=-1;
      WindowEnd:=0;
      for I:=0 to High(Result.FEvents) do begin Check;
        T:=Result.FEvents[I].Time;
        if (T<Start) or (T>Stop) or (T>Audio.SoundEnd) then Continue;
        if (Best>=0) and (T>=WindowEnd) then Commit;
        if Best<0 then begin if (Last>=0) and (T-Last<Gap) then Continue;
          Best:=I;
          WindowEnd:=T+Gap;
        end
        else if Result.FEvents[I].Strength>Result.FEvents[Best].Strength then Best:=I;
      end;
      Commit;
      Result.FCoins:=Coins.ToArray;
      Result.FExcluded:=Length(Result.FEvents)-Result.Count;
      Result.BuildScores;
      Result.BuildTraffic(Audio,Cancel);
      Result.Validate(Cancel);
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally Coins.Free;
    Road.Free;
    Lanes.Free;
  end;
end;

procedure TRacePlan.Validate(const Cancel:TFunc<Boolean>);
var
  I:Integer;
  C:TRaceCoin;
  P:TRaceProjection;
  Gap,DT:Double;
  procedure Need(V:Boolean;const Msg:string);
  begin if not V then raise Exception.Create('Race plan: '+Msg);
  end;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
begin
  Need(Finite(FDuration) and (FDuration>0) and (FDuration<=RACE_MAX_SECONDS) and Finite(FSoundEnd) and (FSoundEnd>=0) and (FSoundEnd<=FDuration),'audio');
  Need(Finite(FEnd) and (FEnd>0) and (FEnd<=FDuration),'end');
  if FSoundEnd>0 then Need(Abs(FEnd-FSoundEnd)<1E-7,'audible end') else Need(FEnd=FDuration,'silent end');
  Need(Finite(FLaunch) and Finite(FAccel) and Finite(FGoal) and Finite(FTopSpeed) and
  (FLaunch>=0) and (FAccel>0) and (FLaunch+FAccel<FGoal) and (FGoal<FEnd) and (((FVersion<3) and (FTopSpeed>=80) and (FTopSpeed<=105)) or ((FVersion>=3) and (FTopSpeed>=132) and (FTopSpeed<=174))),'timeline');
  Need(Finite(FFocus) and (((FVersion<3) and (FFocus=48)) or ((FVersion>=3) and (FFocus=40))),'projection');
  Need((Length(FScores)=Count+1) and (FScores[0]=0),'score prefix');
  Need((Length(FEvents)<=100000) and (Count<=100000) and (FExcluded>=0) and (Count+FExcluded=Length(FEvents)),'counts');
  Need((Length(FLanes)>=2) and (Length(FLanes)<=10000) and (Length(FRoad)>=2) and (Length(FRoad)<=2000),'key counts');
  Need((FLanes[0].Position=0) and (FLanes[0].Value=0) and (FLanes[High(FLanes)].Position=FEnd) and (FRoad[0].Position=0) and (FRoad[High(FRoad)].Position>=DistanceAt(FEnd)+1200),'coverage');
  for I:=0 to High(FLanes) do begin Check;
    Need(Finite(FLanes[I].Position) and Finite(FLanes[I].Value) and (Abs(FLanes[I].Value)<=0.62) and (FLanes[I].Position>=0) and (FLanes[I].Position<=FEnd),'lane key');
    if I>0 then begin DT:=FLanes[I].Position-FLanes[I-1].Position;
      Need(DT>0,'lane order');
      Need(1.5*Abs(FLanes[I].Value-FLanes[I-1].Value)/DT<=0.65,'lane speed');
    end;
  end;
  for I:=0 to High(FRoad) do begin Check;
    Need(Finite(FRoad[I].Position) and Finite(FRoad[I].Value) and (FRoad[I].Position>=0) and (Abs(FRoad[I].Value)<=0.30),'road key');
    if I>0 then begin DT:=FRoad[I].Position-FRoad[I-1].Position;
      Need(DT>0,'road order');
      Need(1.5*Abs(FRoad[I].Value-FRoad[I-1].Value)/DT<=0.002,'road bend');
    end;
  end;
  for I:=0 to High(FEvents) do begin Check;
    Need(Finite(FEvents[I].Time) and Finite(FEvents[I].Strength) and (FEvents[I].Time>=0) and (FEvents[I].Time<=FDuration+0.011) and (FEvents[I].Strength>=0) and (FEvents[I].Strength<=1),'source');
    if I>0 then Need(FEvents[I].Time>=FEvents[I-1].Time,'source order');
  end;
  ValidateTraffic(Cancel);
  Gap:=RACE_MIN_COIN_GAP;
  for I:=0 to Count-1 do begin Check;
    C:=FCoins[I];
    Need(Finite(C.Time) and Finite(C.Distance) and Finite(C.Lane) and Finite(C.Strength) and (C.Source>=0) and (C.Source<Length(FEvents)),'coin');
    Need((C.Points=CoinPoints(C.Strength)) and (FScores[I+1]=FScores[I]+C.Points),'score');
    Need((C.Time=FEvents[C.Source].Time) and (C.Strength=FEvents[C.Source].Strength),'changed accent');
    Need((C.Time>=FLaunch+FAccel*0.60) and (C.Time<=FGoal-Min(0.20,(FGoal-FLaunch)*0.08)) and (C.Time<=FSoundEnd),'coin phase');
    if I>0 then Need((C.Source>FCoins[I-1].Source) and (C.Time-FCoins[I-1].Time>=Gap-1E-8) and (C.Distance>FCoins[I-1].Distance),'coin order');
    Need((Abs(C.Distance-DistanceAt(C.Time))<1E-6) and (Abs(C.Lane-LaneAt(C.Time))<1E-7),'inverse placement');
    P:=Project(C.Distance,C.Lane,C.Time,RACE_COIN_HEIGHT);
    Need(P.Visible and (Abs(P.Scale-1)<1E-7) and (Abs(P.Y-(RACE_CONTACT_Y-RACE_COIN_HEIGHT))<1E-7),'pickup projection');
  end;
end;

procedure TRacePlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var
  Root,J:TJSONObject;
  A:TJSONArray;
  E:TRaceEvent;
  C:TRaceCoin;
  V:TRaceTraffic;
  B:TRaceBomb;
  Boss:TRaceTrailer;
  procedure Keys(const Name:string;const Values:TArray<TRaceKey>);
  var
    V:TRaceKey;
    N:TJSONObject;
  begin A:=TJSONArray.Create;
    Root.AddPair(Name,A);
    for V in Values do begin N:=TJSONObject.Create;
      A.AddElement(N);
      N.AddPair('position',TJSONNumber.Create(V.Position));
      N.AddPair('value',TJSONNumber.Create(V.Value));
    end;
  end;
begin
  if FCrash<>nil then begin
    if (Ref.Version<>FCrash.Version) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsRace,Ref.Variant) or (BossFrequencyFromVariant(Ref.Variant)<>FCrash.Frequency) then raise Exception.Create('Race v8 save identity');
    Root:=TJSONObject.Create;
    try Root.AddPair('schema',TJSONNumber.Create(1));
      Root.AddPair('style','race');
      Root.AddPair('version',TJSONNumber.Create(FCrash.Version));
      Root.AddPair('layout','crash-highway-v'+IntToStr(FCrash.Version));
      Root.AddPair('key',Ref.Key);
      Root.AddPair('source',Ref.SourceKey);
      Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
      Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
      AddPreparedAudio(Root,Audio);
      Root.AddPair('crash',FCrash.ToJSON);
      WritePreparedData(Root,Ref);
    finally Root.Free;
    end;
    Exit;
  end;
  if (Ref.Version<>7) or (FVersion<>7) or (BossFrequencyFromVariant(Ref.Variant)<>FBossFrequency) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsRace,Ref.Variant) then raise Exception.Create('Invalid race reference');
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style','race');
    Root.AddPair('version',TJSONNumber.Create(7));
    Root.AddPair('layout','rear-road-v7');
    Root.AddPair('posePolicy','curvature-lag-v1');
    Root.AddPair('trafficPolicy','fender-contact-v4');
    Root.AddPair('focus',TJSONNumber.Create(FFocus));
    Root.AddPair('scoring','metal-100-50-10-v1');
    Root.AddPair('totalScore',TJSONNumber.Create(MaxScore));
    Root.AddPair('bossFrequency',TJSONNumber.Create(FBossFrequency));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root,Audio);
    Root.AddPair('launch',TJSONNumber.Create(FLaunch));
    Root.AddPair('acceleration',TJSONNumber.Create(FAccel));
    Root.AddPair('goal',TJSONNumber.Create(FGoal));
    Root.AddPair('end',TJSONNumber.Create(FEnd));
    Root.AddPair('topSpeed',TJSONNumber.Create(FTopSpeed));
    Root.AddPair('excluded',TJSONNumber.Create(FExcluded));
    Root.AddPair('distance',TJSONNumber.Create(DistanceAt(FEnd)));
    A:=TJSONArray.Create;
    Root.AddPair('events',A);
    for E in FEvents do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('time',TJSONNumber.Create(E.Time));
      J.AddPair('strength',TJSONNumber.Create(E.Strength));
    end;
    A:=TJSONArray.Create;
    Root.AddPair('coins',A);
    for C in FCoins do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('time',TJSONNumber.Create(C.Time));
      J.AddPair('distance',TJSONNumber.Create(C.Distance));
      J.AddPair('lane',TJSONNumber.Create(C.Lane));
      J.AddPair('strength',TJSONNumber.Create(C.Strength));
      J.AddPair('source',TJSONNumber.Create(C.Source));
      J.AddPair('points',TJSONNumber.Create(C.Points));
    end;
    A:=TJSONArray.Create;
    Root.AddPair('traffic',A);
    for V in FTraffic do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('first',TJSONNumber.Create(V.First));
      J.AddPair('last',TJSONNumber.Create(V.Last));
      J.AddPair('pass',TJSONNumber.Create(V.Pass));
      J.AddPair('distance',TJSONNumber.Create(V.Distance));
      J.AddPair('lane',TJSONNumber.Create(V.Lane));
      J.AddPair('speed',TJSONNumber.Create(V.Speed));
      J.AddPair('graze',TJSONBool.Create(V.Graze));
      J.AddPair('motion',TJSONNumber.Create(V.Motion));
      J.AddPair('contactGap',TJSONNumber.Create(V.ContactGap));
    end;
    A:=TJSONArray.Create;
    Root.AddPair('trailers',A);
    for Boss in FTrailers do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('first',TJSONNumber.Create(Boss.First));
      J.AddPair('last',TJSONNumber.Create(Boss.Last));
      J.AddPair('pass',TJSONNumber.Create(Boss.Pass));
      J.AddPair('lane',TJSONNumber.Create(Boss.Lane));
    end;
    A:=TJSONArray.Create;
    Root.AddPair('bombs',A);
    for B in FBombs do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('drop',TJSONNumber.Create(B.Drop));
      J.AddPair('land',TJSONNumber.Create(B.Land));
      J.AddPair('pass',TJSONNumber.Create(B.Pass));
      J.AddPair('burst',TJSONNumber.Create(B.Burst));
      J.AddPair('clear',TJSONNumber.Create(B.Clear));
      J.AddPair('distance',TJSONNumber.Create(B.Distance));
      J.AddPair('lane',TJSONNumber.Create(B.Lane));
      J.AddPair('boss',TJSONNumber.Create(B.Boss));
    end;
    Keys('lanes',FLanes);
    Keys('road',FRoad);
    WritePreparedData(Root,Ref);
  finally Root.Free;
  end;
end;

class function TRacePlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var
  Root:TJSONObject;
  D:TRaceCrashPlan;
  I:Integer;
begin Root:=ReadPreparedData(Ref,rsRace,Direction);
  Result:=nil;
  try Result:=PreparedAudio(Root,Ref,Source);
    try if Ref.Version>=8 then begin D:=TRaceCrashPlan.FromJSON(Root.GetValue<TJSONObject>('crash'),Result);
        try if D.Frequency<>BossFrequencyFromVariant(Ref.Variant) then raise Exception.Create('Race v8 metadata frequency');
          for I:=0 to High(D.Events) do Result.Hits[I]:=D.Events[I];
          Result.SetBossFrequency(D.Frequency);
        finally D.Free;
        end;
      end;
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally Root.Free;
  end;
end;

class function TRacePlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRacePlan;
var
  Root,J,Info:TJSONObject;
  A:TJSONArray;
  I:Integer;
  function Items(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);
    if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Invalid race '+Name);
  end;
  function ObjectAt(Index:Integer):TJSONObject;
  begin if not (A.Items[Index] is TJSONObject) then raise Exception.Create('Invalid race item');
    Result:=TJSONObject(A.Items[Index]);
  end;
  function Keys(const Name:string;Limit:Integer):TArray<TRaceKey>;
  var
    N:Integer;
    V:TJSONObject;
  begin A:=Items(Name,Limit);
    SetLength(Result,A.Count);
    for N:=0 to A.Count-1 do begin V:=ObjectAt(N);
      Result[N].Position:=V.GetValue<Double>('position');
      Result[N].Value:=V.GetValue<Double>('value');
    end;
  end;
begin
  Result:=nil;
  if (Audio=nil) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsRace,Ref.Variant) then raise Exception.Create('Race metadata mismatch');
  Root:=ReadPreparedData(Ref,rsRace,Direction);
  try
    if Ref.Version>=8 then begin
      if Root.GetValue<string>('layout','')<>'crash-highway-v'+IntToStr(Ref.Version) then raise Exception.Create('Race v8 layout');
      Result:=TRacePlan.Create;
      try Result.FCrash:=TRaceCrashPlan.FromJSON(Root.GetValue<TJSONObject>('crash'),Audio);
        if Result.FCrash.Version<>Ref.Version then raise Exception.Create('Race crash version');
        Result.FVersion:=Ref.Version;
        Result.FFocus:=RACE_FOCUS;
        Result.FDuration:=Result.FCrash.Duration;
        Result.FSoundEnd:=Result.FCrash.SoundEnd;
        Result.FEnd:=Result.FCrash.EndTime;
        Result.FLaunch:=Result.FCrash.Launch;
        Result.FAccel:=Result.FCrash.Acceleration;
        Result.FGoal:=Result.FCrash.Goal;
        Result.FTopSpeed:=Result.FCrash.TopSpeed;
        Result.FBossFrequency:=Result.FCrash.Frequency;
        Result.FExcluded:=Result.FCrash.Excluded;
        if Result.FBossFrequency<>BossFrequencyFromVariant(Ref.Variant) then raise Exception.Create('Race v8 frequency');
      except Result.Free;
        Result:=nil;
        raise;
      end;
      Exit;
    end;
    if ((Ref.Version=1) and (Root.GetValue<string>('layout','')<>'rear-road-v1')) or ((Ref.Version=2) and (Root.GetValue<string>('layout','')<>'rear-road-v2')) or ((Ref.Version=3) and (Root.GetValue<string>('layout','')<>'rear-road-v3')) or ((Ref.Version=4) and (Root.GetValue<string>('layout','')<>'rear-road-v4')) or ((Ref.Version=5) and (Root.GetValue<string>('layout','')<>'rear-road-v5')) or ((Ref.Version=6) and (Root.GetValue<string>('layout','')<>'rear-road-v6')) or ((Ref.Version=7) and (Root.GetValue<string>('layout','')<>'rear-road-v7')) then raise Exception.Create('Invalid race layout');
    Info:=Root.GetValue<TJSONObject>('audio');
    if (Info=nil) or not Finite(Info.GetValue<Double>('duration')) or not Finite(Info.GetValue<Double>('soundEnd')) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-7) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-7) then raise Exception.Create('Race audio identity');
    Result:=TRacePlan.Create;
    try
      if (Ref.Version>=4) and ((Root.GetValue<string>('posePolicy','')<>'curvature-lag-v1') or ((Ref.Version=4) and (Root.GetValue<string>('trafficPolicy','')<>'dense-overtake-v1')) or ((Ref.Version=5) and (Root.GetValue<string>('trafficPolicy','')<>'convoy-overtake-v2')) or ((Ref.Version=6) and (Root.GetValue<string>('trafficPolicy','')<>'dynamic-contact-v3')) or ((Ref.Version>=7) and (Root.GetValue<string>('trafficPolicy','')<>'fender-contact-v4'))) then raise Exception.Create('Race pose/traffic policy');
      Result.FVersion:=Ref.Version;
      Result.FFocus:=48;
      if Ref.Version>=3 then begin Result.FFocus:=Root.GetValue<Double>('focus');
        if Root.GetValue<string>('scoring','')<>'metal-100-50-10-v1' then raise Exception.Create('Race score policy');
      end;
      Result.FBossFrequency:=100;
      if Ref.Version>=2 then begin Result.FBossFrequency:=Root.GetValue<Integer>('bossFrequency',-1);
        if Result.FBossFrequency<>BossFrequencyFromVariant(Ref.Variant) then raise Exception.Create('Race frequency mismatch');
      end;
      Result.FDuration:=Audio.Duration;
      Result.FEnd:=Root.GetValue<Double>('end');
      Result.FSoundEnd:=Audio.SoundEnd;
      Result.FLaunch:=Root.GetValue<Double>('launch');
      Result.FAccel:=Root.GetValue<Double>('acceleration');
      Result.FGoal:=Root.GetValue<Double>('goal');
      Result.FTopSpeed:=Root.GetValue<Double>('topSpeed');
      Result.FExcluded:=Root.GetValue<Integer>('excluded',-1);
      if not Finite(Result.FEnd) or (Result.FEnd>Audio.Duration) then raise Exception.Create('Race duration mismatch');
      A:=Items('events',100000);
      if A.Count<>Length(Audio.Hits) then raise Exception.Create('Race source count');
      SetLength(Result.FEvents,A.Count);
      for I:=0 to A.Count-1 do begin J:=ObjectAt(I);
        Result.FEvents[I].Time:=J.GetValue<Double>('time');
        Result.FEvents[I].Strength:=J.GetValue<Double>('strength');
      end;
      A:=Items('coins',100000);
      SetLength(Result.FCoins,A.Count);
      for I:=0 to A.Count-1 do begin J:=ObjectAt(I);
        Result.FCoins[I].Time:=J.GetValue<Double>('time');
        Result.FCoins[I].Distance:=J.GetValue<Double>('distance');
        Result.FCoins[I].Lane:=J.GetValue<Double>('lane');
        Result.FCoins[I].Strength:=J.GetValue<Double>('strength');
        Result.FCoins[I].Source:=J.GetValue<Integer>('source',-1);
        if Ref.Version>=3 then Result.FCoins[I].Points:=J.GetValue<Integer>('points') else Result.FCoins[I].Points:=CoinPoints(Result.FCoins[I].Strength);
      end;
      Result.BuildScores;
      if Ref.Version>=2 then begin
        A:=Items('traffic',8192);
        SetLength(Result.FTraffic,A.Count);
        for I:=0 to A.Count-1 do begin J:=ObjectAt(I);
          Result.FTraffic[I].First:=J.GetValue<Double>('first');
          Result.FTraffic[I].Last:=J.GetValue<Double>('last');
          Result.FTraffic[I].Pass:=J.GetValue<Double>('pass');
          Result.FTraffic[I].Distance:=J.GetValue<Double>('distance');
          Result.FTraffic[I].Lane:=J.GetValue<Double>('lane');
          Result.FTraffic[I].Speed:=J.GetValue<Double>('speed');
          if Ref.Version>=3 then Result.FTraffic[I].Graze:=J.GetValue<Boolean>('graze');
          if Ref.Version>=6 then Result.FTraffic[I].Motion:=J.GetValue<Integer>('motion');
          if Ref.Version>=7 then Result.FTraffic[I].ContactGap:=J.GetValue<Double>('contactGap');
        end;
        A:=Items('trailers',256);
        SetLength(Result.FTrailers,A.Count);
        for I:=0 to A.Count-1 do begin J:=ObjectAt(I);
          Result.FTrailers[I].First:=J.GetValue<Double>('first');
          Result.FTrailers[I].Last:=J.GetValue<Double>('last');
          Result.FTrailers[I].Pass:=J.GetValue<Double>('pass');
          Result.FTrailers[I].Lane:=J.GetValue<Double>('lane');
        end;
        A:=Items('bombs',4096);
        SetLength(Result.FBombs,A.Count);
        for I:=0 to A.Count-1 do begin J:=ObjectAt(I);
          Result.FBombs[I].Drop:=J.GetValue<Double>('drop');
          Result.FBombs[I].Land:=J.GetValue<Double>('land');
          Result.FBombs[I].Pass:=J.GetValue<Double>('pass');
          Result.FBombs[I].Burst:=J.GetValue<Double>('burst');
          Result.FBombs[I].Clear:=J.GetValue<Double>('clear');
          Result.FBombs[I].Distance:=J.GetValue<Double>('distance');
          Result.FBombs[I].Lane:=J.GetValue<Double>('lane');
          Result.FBombs[I].Boss:=J.GetValue<Integer>('boss',-1);
        end;
      end;
      Result.FLanes:=Keys('lanes',10000);
      Result.FRoad:=Keys('road',2000);
      Result.Validate;
      if (Ref.Version>=3) and (Root.GetValue<Integer>('totalScore',-1)<>Result.MaxScore) then raise Exception.Create('Race total score');
      if not Finite(Root.GetValue<Double>('distance')) or (Abs(Result.DistanceAt(Result.FEnd)-Root.GetValue<Double>('distance'))>1E-6) then raise Exception.Create('Race final distance mismatch');
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally Root.Free;
  end;
end;
end.
