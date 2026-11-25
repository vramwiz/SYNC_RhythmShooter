unit RhythmTrainPlan;
// 曲から選んだ接触時刻と屋根上の動きを保存する。走行、衝突、カメラも任意の時刻から復元できる。
{$POINTERMATH ON}
interface

uses
  System.SysUtils, RhythmAudio, RhythmPlanRef;

const
  TrainPitch = 12.8;
  TrainCarWidth = 11.86;
  TrainGap = TrainPitch-TrainCarWidth;
  TrainReach = 0.76;
  TrainShotReach = 2.14;
  TrainPlatformY = 2.15;
  TrainBoardX = -2.0;
  TrainRoofViewWidth = 11.7;

type
  TTrainMove = (tmBoard, tmHit, tmVaultHit, tmDuckHit, tmShot, tmJump, tmLeftImpact,
    tmRightImpact, tmCouple, tmTransfer, tmBossJump, tmBossDuck, tmBossFinish, tmStation,
    tmHurdle, tmHurdleHit, tmSlide, tmRoofGap, tmLever, tmGateRun);
  TTrainCue = record
    Kind: TTrainMove;
    Start, Time, Finish, FromX, ToX: Double;
    Source: Integer;
  end;
  TTrainObstacle = record
    Left, Right, Height: Double;
    Variant: Integer;
  end;
  // 描画用の動作。保存ファイルには書き込まず、キューから毎回導出する。
  TTrainGesture = (tgNone, tgJab, tgCross, tgUpper, tgKick, tgAirKick,
    tgPulse, tgFinisher, tgLever, tgSweep);
  TTrainPose = record
    X, Y, Run, Crouch, Reach, Land, Kick, Slide: Double;
    Windup, FollowThrough, FlightPhase, ArtGesturePhase: Double;
    Gesture: TTrainGesture;
    Airborne: Boolean;
  end;
  TTrainExchange = record
    StartIndex, LeftIndex, RightIndex, CoupleIndex, TransferIndex, LeadCar: Integer;
  end;
  TTrainPlan = class
  private
    FCues: TArray<TTrainCue>;
    FCarCue: TArray<Integer>;
    FExchanges: TArray<TTrainExchange>;
    FCarFormation: TArray<Integer>;
    FDuration, FEndTime: Double;
    FCars, FSynced, FEnemies, FObstacles: Integer;
    function GetCount: Integer;
    function GetCue(Index: Integer): TTrainCue;
    function GetLength: Double;
    function GetArrival: Double;
    procedure Verify(Audio: TRhythmAudio);
    procedure IndexCars;
    function CueAt(Time: Double): Integer;
    function GetExchange(Index: Integer): TTrainExchange;
    function GetExchangeCount: Integer;
    function ExchangeStart(const Exchange: TTrainExchange): Double;
    function ExchangeEnd(const Exchange: TTrainExchange): Double;
  public
    class function Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean> = nil): TTrainPlan; static;
    class function Load(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TTrainPlan; static;
    class function LoadAudioMetadata(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio; static;
    procedure Save(var Ref: TRhythmPlanRef; Audio: TRhythmAudio);
    function PoseAt(Time: Double): TTrainPose;
    function ScarfMotionAt(Time, CurrentX: Double): Double;
    function RoofY(X: Double): Double;
    function RoofCameraX(Time: Double): Double;
    procedure CarCues(FirstCar, LastCar: Integer; out First, Last: Integer);
    function NextRoofObstacle(Car: Integer; X: Double; out Block: TTrainObstacle): Boolean;
    function ExchangeAt(Time: Double): Integer;
    function FormationOf(Car: Integer): Integer;
    function CarPosition(Car, ExchangeIndex: Integer; Time: Double; out Offset: Double): Boolean;
    procedure CollisionCamera(Index: Integer; Time: Double; out X, Width, Blend: Double);
    function LeftNoseAt(Index: Integer; Time: Double): Double;
    function RightRearAt(Index: Integer; Time: Double): Double;
    function TravelAt(Time: Double): Double;
    property Count: Integer read GetCount;
    property Cue[Index: Integer]: TTrainCue read GetCue;
    property Cars: Integer read FCars;
    property ExchangeCount: Integer read GetExchangeCount;
    property Exchange[Index: Integer]: TTrainExchange read GetExchange;
    property Synced: Integer read FSynced;
    property Enemies: Integer read FEnemies;
    property Obstacles: Integer read FObstacles;
    property Arrival: Double read GetArrival;
    property TrainLength: Double read GetLength;
    property EndTime: Double read FEndTime;
  end;

function TrainEase(T: Double): Double;
function TrainThreatTime(const Cue: TTrainCue): Double;
function TrainObstacle(const Cue: TTrainCue; out Block: TTrainObstacle): Boolean;
function TrainRouteHazard(const Cue: TTrainCue; out Hazard: TTrainObstacle): Boolean;
function TrainGateOpening(const Lever, Passage: TTrainCue; Time: Double): Double;
function TrainRegularEnemy(Kind: TTrainMove): Boolean;

implementation

uses
  System.Math, System.JSON, System.Generics.Collections, RhythmStyles, RhythmPreparedData;

const
  TrainPolicy = 'roof-action-v10';
  HurdleArc = 1.46;
  EarlyBoardSource = -2;
  MaxCars = 1150;
  MaxCues = MaxCars*8+8;
  Epsilon = 1E-8;
  CruiseSpeed = 14.8;
  CouplerCompression = 0.037;

function TrainEase(T: Double): Double;
begin
  T := EnsureRange(T, 0.0, 1.0);
  Result := T*T*(3-2*T);
end;

function Ramp(Time, Start, Finish: Double): Double;
begin
  Result := EnsureRange((Time-Start)/Max(Epsilon,Finish-Start),0.0,1.0);
end;

function TrainThreatTime(const Cue: TTrainCue): Double;
begin
  Result := Cue.Start+(Cue.Time-Cue.Start)*0.52;
end;

function TrainRegularEnemy(Kind: TTrainMove): Boolean;
begin
  Result := Kind in [tmHit,tmVaultHit,tmDuckHit,tmShot,tmHurdleHit];
end;

function TrainObstacle(const Cue: TTrainCue; out Block: TTrainObstacle): Boolean;
var Span: Double; Car: Integer;
begin
  Block := Default(TTrainObstacle);
  Result := Cue.Kind in [tmHurdle,tmHurdleHit];
  if not Result then Exit;
  Span := Cue.ToX-Cue.FromX;
  Block.Left := Cue.FromX+Span*0.29;
  Block.Right := Cue.FromX+Span*0.62;
  Car := Floor(Cue.FromX/TrainPitch);
  Block.Variant := (Car+Floor((Cue.FromX-Car*TrainPitch)/4)) mod 3;
  case Block.Variant of
    0: Block.Height := 0.79;
    1: Block.Height := 1.02;
    2: Block.Height := 0.89;
  end;
end;

function TrainRouteHazard(const Cue: TTrainCue; out Hazard: TTrainObstacle): Boolean;
var Span: Double;
begin
  Hazard := Default(TTrainObstacle);
  Span := Cue.ToX-Cue.FromX;
  Result := True;
  case Cue.Kind of
    tmSlide: begin
      Hazard.Left := Cue.FromX+Span*0.34;
      Hazard.Right := Cue.FromX+Span*0.62;
      Hazard.Height := 0.76;
    end;
    tmRoofGap: begin
      Hazard.Left := Cue.FromX+Span*0.30;
      Hazard.Right := Cue.FromX+Span*0.67;
    end;
    tmGateRun: begin
      Hazard.Left := Cue.FromX+Span*0.43;
      Hazard.Right := Hazard.Left+0.24;
      Hazard.Height := 1.68;
    end;
  else
    Result := False;
  end;
end;

function TrainGateOpening(const Lever, Passage: TTrainCue; Time: Double): Double;
begin
  Result := TrainEase(Ramp(Time,Lever.Time,Min(Lever.Time+0.19,Passage.Start)));
end;

procedure TTrainPlan.IndexCars;
var Car, I, Formation: Integer;
begin
  SetLength(FCarCue,FCars+1);
  SetLength(FCarFormation,FCars);
  I := 0;
  for Car := 1 to High(FCarCue) do begin
    while (I<Count) and (FCues[I].FromX<Car*TrainPitch) do Inc(I);
    FCarCue[Car] := I;
  end;
  Formation := 0;
  for Car := 0 to FCars-1 do begin
    if (Formation<ExchangeCount) and (Car>FExchanges[Formation].LeadCar) then Inc(Formation);
    FCarFormation[Car] := Formation;
  end;
end;

procedure TTrainPlan.CarCues(FirstCar, LastCar: Integer; out First, Last: Integer);
begin
  First := FCarCue[EnsureRange(FirstCar,0,High(FCarCue))];
  Last := FCarCue[EnsureRange(LastCar+1,0,High(FCarCue))]-1;
end;

function TTrainPlan.NextRoofObstacle(Car: Integer; X: Double; out Block: TTrainObstacle): Boolean;
var I, First, Last: Integer;
begin
  CarCues(Car,Car,First,Last);
  for I := First to Last do
    if TrainObstacle(FCues[I],Block) and (Block.Right>=X) then Exit(True);
  Block := Default(TTrainObstacle);
  Result := False;
end;

function TTrainPlan.RoofCameraX(Time: Double): Double;
var
  I: Integer;
  C: TTrainCue;
  CurrentX, NextX: Double;
begin
  Result := 5.91;
  for I := CueAt(Time+0.11) downto 0 do begin
    C := FCues[I];
    if C.Kind in [tmJump,tmTransfer,tmBossJump] then begin
      NextX := Floor(C.ToX/TrainPitch)*TrainPitch+5.91;
      CurrentX := Floor(C.FromX/TrainPitch)*TrainPitch+5.91;
      Exit(CurrentX+(NextX-CurrentX)*TrainEase(Ramp(Time,C.Start-0.11,C.Time+0.11)));
    end;
  end;
end;

function TTrainPlan.GetCount: Integer;
begin
  Result := Length(FCues);
end;

function TTrainPlan.GetCue(Index: Integer): TTrainCue;
begin
  Result := FCues[Index];
end;

function TTrainPlan.GetLength: Double;
begin
  Result := FCars*TrainPitch-TrainGap;
end;

function TTrainPlan.GetArrival: Double;
begin
  Result := FEndTime;
  if Count>0 then
    Result := FCues[High(FCues)].Time;
end;

function TTrainPlan.RoofY(X: Double): Double;
var
  Car: Integer;
begin
  Car := Floor(X/TrainPitch);
  Result := 0;
  if FormationOf(Car)>0 then
    case Car mod 3 of
      0: Result := 0.36;
      1: Result := 0.10;
      2: Result := 0.47;
    end;
end;

function TTrainPlan.TravelAt(Time: Double): Double;
var
  Departure, Brake, Accel, T: Double;
begin
  Departure := 0;
  if Count>0 then Departure := FCues[0].Time;
  Brake := Max(Departure,Arrival-2.1);
  Accel := Min(0.95,Brake-Departure);
  T := EnsureRange(Time-Departure,0.0,Brake-Departure);
  if T<Accel then Result := 0.5*T*T/Accel
  else Result := T-Accel*0.5;
  T := EnsureRange(Time-Brake,0.0,Arrival-Brake);
  Result := CruiseSpeed*(Result+T*(1-0.5*T/Max(Epsilon,Arrival-Brake)));
end;

function TTrainPlan.GetExchange(Index: Integer): TTrainExchange;
begin
  Result := FExchanges[Index];
end;

function TTrainPlan.GetExchangeCount: Integer;
begin
  Result := Length(FExchanges);
end;

function TTrainPlan.ExchangeStart(const Exchange: TTrainExchange): Double;
begin
  Result := FCues[Exchange.StartIndex-1].Finish;
end;

function TTrainPlan.ExchangeEnd(const Exchange: TTrainExchange): Double;
begin
  Result := FCues[Exchange.TransferIndex].Time+0.12;
end;

function TTrainPlan.ExchangeAt(Time: Double): Integer;
var LowIndex, HighIndex, Middle: Integer;
begin
  LowIndex := 0;
  HighIndex := ExchangeCount;
  while LowIndex<HighIndex do begin
    Middle := (LowIndex+HighIndex) div 2;
    if Time>=ExchangeEnd(FExchanges[Middle]) then LowIndex := Middle+1
    else HighIndex := Middle;
  end;
  Result := LowIndex;
end;

function TTrainPlan.FormationOf(Car: Integer): Integer;
begin
  if (Car<0) or (Car>=FCars) then Exit(-1);
  Result := FCarFormation[Car];
end;

function TTrainPlan.CarPosition(Car, ExchangeIndex: Integer; Time: Double; out Offset: Double): Boolean;
var Formation: Integer; E: TTrainExchange; ExitTime: Double;
begin
  Offset := 0;
  Formation := FormationOf(Car);
  Result := False;
  if (Formation<0) or (Formation<ExchangeIndex-1) or (Formation>ExchangeIndex+1) then Exit;
  if Formation<ExchangeIndex then begin
    E := FExchanges[Formation];
    ExitTime := ExchangeEnd(E);
    if Time>=ExitTime+1.05 then Exit;
    Offset := -23*TrainEase(Ramp(Time,ExitTime,ExitTime+1.05));
    if Car<E.LeadCar then
      Offset := Offset+LeftNoseAt(Formation,Time)-(E.LeadCar*TrainPitch-TrainGap);
  end
  else if ExchangeIndex<ExchangeCount then begin
    E := FExchanges[ExchangeIndex];
    if Formation>ExchangeIndex then begin
      if Time<ExchangeStart(E) then Exit;
      Offset := RightRearAt(ExchangeIndex,Time)-(E.LeadCar+1)*TrainPitch;
    end
    else if Car<E.LeadCar then
      Offset := LeftNoseAt(ExchangeIndex,Time)-(E.LeadCar*TrainPitch-TrainGap);
  end;
  Result := True;
end;

function TTrainPlan.LeftNoseAt(Index: Integer; Time: Double): Double;
var
  E: TTrainExchange;
  Joint, Detach, Contact, SeparationEnd, Approach, U: Double;
begin
  E := FExchanges[Index];
  Joint := E.LeadCar*TrainPitch-TrainGap;
  if E.LeftIndex<0 then Exit(Joint);
  Detach := ExchangeStart(E);
  Contact := FCues[E.LeftIndex].Time;
  SeparationEnd := Detach+(Contact-Detach)*0.43;
  if Time<=SeparationEnd then
    Exit(Joint-6.4*TrainEase(Ramp(Time,Detach,SeparationEnd)));
  if Time<=Contact then begin
    Approach := Max(SeparationEnd,Contact-1.07);
    U := Ramp(Time,Approach,Contact);
    Exit(Joint-6.4*(1-Sqr(U)));
  end;
  U := Ramp(Time,Contact+CouplerCompression,Contact+0.40);
  Result := Joint-5.4*(1-Sqr(1-U))-
    3.8*TrainEase(Ramp(Time,Contact+0.27,FCues[E.CoupleIndex].Time+0.19));
end;

function TTrainPlan.RightRearAt(Index: Integer; Time: Double): Double;
var
  E: TTrainExchange;
  Contact, Dock, U, Approach: Double;
begin
  E := FExchanges[Index];
  Dock := (E.LeadCar+1)*TrainPitch;
  if E.RightIndex<0 then begin
    Contact := FCues[E.CoupleIndex].Time;
    U := Ramp(Time,Max(FCues[E.LeftIndex].Time+0.16,Contact-1.03),Contact);
    Exit(Dock+10*(1-Sqr(U)));
  end;
  Contact := FCues[E.RightIndex].Time;
  if Time<=Contact then begin
    Approach := ExchangeStart(E);
    if E.LeftIndex>=0 then Approach := FCues[E.LeftIndex].Time+0.16;
    U := Ramp(Time,Max(Approach,Contact-1.10),Contact);
    Exit(Dock+10*(1-Sqr(U)));
  end;
  U := Ramp(Time,Contact+CouplerCompression,FCues[E.CoupleIndex].Time);
  Result := Dock+Sin(Pi*U)*(1.35+1.78*(1-U));
end;

procedure TTrainPlan.CollisionCamera(Index: Integer; Time: Double; out X, Width, Blend: Double);
var
  E: TTrainExchange;
  LeftTime, RightTime, Gap, Detach, LeftJoint, RightJoint, LeftHero, Pan, LeftWidth: Double;
begin
  X := 0;
  Width := TrainRoofViewWidth;
  Blend := 0;
  if (Index<0) or (Index>=ExchangeCount) then Exit;
  E := FExchanges[Index];
  Detach := ExchangeStart(E);
  Blend := TrainEase(Ramp(Time,Detach-0.10,Max(Detach+0.015,FCues[E.StartIndex].Time-0.29)))*
    (1-TrainEase(Ramp(Time,FCues[E.CoupleIndex].Time+0.05,ExchangeEnd(E))));
  if Blend<=0 then Exit;

  RightJoint := (E.LeadCar+1)*TrainPitch-TrainGap*0.5;
  X := RightJoint+0.78;
  Width := 17.8;
  if E.LeftIndex<0 then Exit;
  LeftJoint := E.LeadCar*TrainPitch-TrainGap*0.5;
  LeftHero := FCues[E.LeftIndex].ToX;
  LeftTime := FCues[E.LeftIndex].Time;
  RightTime := FCues[E.CoupleIndex].Time;
  if E.RightIndex>=0 then RightTime := FCues[E.RightIndex].Time;
  Gap := RightTime-LeftTime;
  Pan := TrainEase(Ramp(Time,LeftTime+Min(0.29,Gap*0.35),RightTime-Min(0.26,Gap*0.32)));
  LeftWidth := Max(20.4,LeftHero-LeftJoint+10.0);
  X := ((LeftJoint+LeftHero)*0.5-1.86)*(1-Pan)+X*Pan;
  Width := LeftWidth*(1-Pan)+Width*Pan;
end;

procedure RunBetween(var Pose: TTrainPose; Time, Start, Finish, FromX, ToX: Double);
const
  Blend = 0.18;
var U, Progress, Speed: Double;
begin
  Pose.X := FromX;
  if Time>=Finish then begin
    Pose.X := ToX;
    Exit;
  end;
  if (Time<=Start) or (FromX=ToX) then Exit;
  U := Ramp(Time,Start,Finish);
  if U<Blend then Progress := Sqr(U)/(2*Blend)
  else if U>1-Blend then Progress := 1-Blend-Sqr(1-U)/(2*Blend)
  else Progress := U-Blend*0.5;
  Pose.X := FromX+(ToX-FromX)*Progress/(1-Blend);
  Speed := (ToX-FromX)/((Finish-Start)*(1-Blend))*Min(1.0,Min(U,1-U)/Blend);
  Pose.Run := EnsureRange(Speed/7.5,0.0,1.0);
end;

function TTrainPlan.CueAt(Time: Double): Integer;
var
  LowIndex, HighIndex, Middle: Integer;
begin
  LowIndex := 0;
  HighIndex := Count;
  while LowIndex<HighIndex do begin
    Middle := (LowIndex+HighIndex) div 2;
    if FCues[Middle].Start<=Time then LowIndex := Middle+1
    else HighIndex := Middle;
  end;
  Result := LowIndex-1;
end;

function TTrainPlan.PoseAt(Time: Double): TTrainPose;
var
  I: Integer;
  C, Next: TTrainCue;
  U, Height, Y0, Y1, AttackSpan, PrepStart, HitStart, Progress: Double;
begin
  Result := Default(TTrainPose);
  Result.X := TrainBoardX;
  Result.Y := TrainPlatformY;
  if Count=0 then Exit;
  I := CueAt(Time);
  if I<0 then begin
    U := Ramp(Time,FCues[0].Start-0.19,FCues[0].Start);
    Result.X := TrainBoardX-1.6*(1-TrainEase(U));
    Result.Run := Sin(Pi*U);
    Exit;
  end;
  C := FCues[I];
  Y0 := RoofY(C.FromX);
  Y1 := RoofY(C.ToX);
  if C.Kind=tmBoard then Y0 := TrainPlatformY;
  if C.Kind=tmStation then Y1 := TrainPlatformY;
  if Time>C.Finish then begin
    Result.X := C.ToX;
    Result.Y := Y1;
    if I<High(FCues) then begin
      Next := FCues[I+1];
      RunBetween(Result,Time,C.Finish,Next.Start,C.ToX,Next.FromX);
      Result.Y := RoofY(Result.X);
    end;
    Exit;
  end;
  U := Ramp(Time,C.Start,C.Time);
  Height := 0;
  case C.Kind of
    tmBoard: Height := 1.48;
    tmVaultHit: Height := 1.02;
    tmHurdle,tmHurdleHit: Height := HurdleArc;
    tmRoofGap: Height := 1.24;
    tmJump: Height := 0.94;
    tmTransfer: Height := 1.19;
    tmBossJump: Height := 1.45;
    tmStation: Height := 0.76;
    tmRightImpact: Height := 0.73;
  end;
  if Height>0 then begin
    Result.X := C.FromX+(C.ToX-C.FromX)*U;
    Result.Y := Y0+(Y1-Y0)*U-4*Height*U*(1-U);
    Result.Airborne := (U>0) and (U<1);
    Result.FlightPhase := U;
    if Time>=C.Time then
      Result.Land := 1-Ramp(Time,C.Time,C.Finish);
    Result.Crouch := 0.72*Result.Land;
  end
  else if C.Kind=tmSlide then begin
    Result.X := C.FromX+(C.ToX-C.FromX)*U;
    Result.Y := Y1;
    Result.Slide := TrainEase(U/0.08)*(1-TrainEase((U-0.89)/0.11));
  end
  else begin
    RunBetween(Result,Time,C.Start,C.Time,C.FromX,C.ToX);
    Result.Y := Y1;
  end;
  if C.Kind in [tmLeftImpact,tmRightImpact,tmCouple] then begin
    if Time<C.Time then
      Result.Crouch := 0.47*TrainEase(Ramp(Time,Max(C.Start,C.Time-0.22),C.Time))
    else Result.Crouch := 0.88*(1-Ramp(Time,C.Time,C.Finish));
  end;
  if C.Kind in [tmDuckHit,tmBossDuck] then begin
    // 低姿勢の頂点を見た目だけでなく、敵の通過時刻に合わせる。
    PrepStart := TrainThreatTime(C);
    if Time<PrepStart then Progress := TrainEase(Ramp(Time,C.Start,PrepStart))
    else Progress := 1-TrainEase(Ramp(Time,PrepStart,C.Time));
    Result.Crouch := Progress*0.88;
  end;
  if TrainRegularEnemy(C.Kind) or (C.Kind in [tmBossDuck,tmBossFinish,tmLever]) then begin
    // 接触点は従来の音ピーク。予備動作・打ち出し・戻りだけを描画上で補間する。
    case C.Kind of
      tmHit: case I mod 4 of
        0: Result.Gesture := tgJab;
        1: Result.Gesture := tgCross;
        2: Result.Gesture := tgKick;
      else Result.Gesture := tgUpper;
      end;
      tmVaultHit,tmHurdleHit: Result.Gesture := tgAirKick;
      tmDuckHit: Result.Gesture := tgUpper;
      tmShot: Result.Gesture := tgPulse;
      tmBossDuck: Result.Gesture := tgCross;
      tmBossFinish: Result.Gesture := tgFinisher;
      tmLever: Result.Gesture := tgLever;
    end;
    AttackSpan := Min(0.105,(C.Time-C.Start)*0.54);
    if Result.Gesture in [tgPulse,tgFinisher] then
      AttackSpan := Min(0.17,(C.Time-C.Start)*0.73);
    HitStart := C.Time-AttackSpan;
    PrepStart := Max(C.Start,HitStart-AttackSpan*1.6);
    if Time<C.Time then begin
      if Time<HitStart then
        Result.ArtGesturePhase := 0.3*Ramp(Time,PrepStart,HitStart)
      else
        Result.ArtGesturePhase := 0.3+0.2*Ramp(Time,HitStart,C.Time);
      Result.Windup := TrainEase(Ramp(Time,PrepStart,HitStart))*
        (1-TrainEase(Ramp(Time,HitStart,C.Time)));
      Result.Reach := TrainEase(Ramp(Time,HitStart,C.Time));
    end else begin
      Progress := Ramp(Time,C.Time,C.Finish);
      Result.ArtGesturePhase := 0.5+0.5*Progress;
      Result.Reach := 1-TrainEase(Progress);
      Result.FollowThrough := Sin(Pi*Progress);
    end;
    if Result.Gesture in [tgKick,tgAirKick] then Result.Kick := Result.Reach;
  end;
end;

function TTrainPlan.ScarfMotionAt(Time, CurrentX: Double): Double;
var NearPose, FarPose: TTrainPose; Speed: Double;
begin
  // Normalize the runner's motion relative to the roof, not train or camera speed.
  // A trailing finite window supplies the cloth's settling lag on random seeks too.
  NearPose := PoseAt(Max(0.0,Time-0.06));
  FarPose := PoseAt(Max(0.0,Time-0.24));
  Speed := 0.53*Abs(CurrentX-NearPose.X)/0.06+
    0.47*Abs(CurrentX-FarPose.X)/0.24;
  Result := EnsureRange((Speed-0.06)/3.20,0.0,1.0);
end;

procedure TTrainPlan.Verify(Audio: TRhythmAudio);
var
  I, LastSource, ExchangeCount, PreviousLead, J: Integer;
  Previous, Span, Edge, Clearance: Double;
  C: TTrainCue;
  Block: TTrainObstacle;
  E: TTrainExchange;
begin
  if IsNan(FDuration) or IsInfinite(FDuration) or (FDuration<=0) or
     IsNan(FEndTime) or IsInfinite(FEndTime) or (FEndTime<0) or
     (FEndTime>Max(10.0,FDuration+1.4)) or (FCars<4) or (FCars>MaxCars) or (Count>MaxCues) then
    raise EConvertError.Create('Train plan bounds');
  FSynced := 0;
  FEnemies := 0;
  FObstacles := 0;
  FExchanges := nil;
  if Count=0 then Exit;
  Previous := -1;
  LastSource := -1;
  for I := 0 to High(FCues) do begin
    C := FCues[I];
    if (C.Start<=Previous) or (C.Start<0) or (C.Time<=C.Start) or (C.Finish<=C.Time) or
       (C.Finish>FEndTime) or (C.FromX<TrainBoardX) or (C.ToX<C.FromX) or
       (C.ToX>TrainLength+1.3) or ((I>0) and (C.FromX+Epsilon<FCues[I-1].ToX)) then
      raise EConvertError.Create('Train move bounds');
    if TrainRegularEnemy(C.Kind) then Inc(FEnemies);
    if TrainObstacle(C,Block) then begin
      Inc(FObstacles);
      Span := C.ToX-C.FromX;
      if (Span<2.2) or (Floor(C.FromX/TrainPitch)<>Floor(C.ToX/TrainPitch)) or
         (C.ToX-Floor(C.ToX/TrainPitch)*TrainPitch>=TrainCarWidth) then
        raise EConvertError.Create('Train obstacle course');
      Edge := (Block.Left-C.FromX)/Span;
      Clearance := 4*HurdleArc*Edge*(1-Edge);
      Edge := (Block.Right-C.FromX)/Span;
      Clearance := Min(Clearance,4*HurdleArc*Edge*(1-Edge));
      if Clearance<Block.Height+0.12 then
        raise EConvertError.Create('Train obstacle clearance');
    end;
    if TrainRouteHazard(C,Block) then begin
      Inc(FObstacles);
      if (C.FromX>=Block.Left) or (Block.Right>=C.ToX) or
         (Floor(C.FromX/TrainPitch)<>Floor(C.ToX/TrainPitch)) then
        raise EConvertError.Create('Train route hazard geometry');
      if (C.Kind=tmGateRun) and ((I=0) or (FCues[I-1].Kind<>tmLever) or
         (FCues[I-1].ToX+TrainReach>=Block.Left)) then
        raise EConvertError.Create('Train gate missing control');
    end;
    if (C.Kind=tmLever) and ((I=High(FCues)) or (FCues[I+1].Kind<>tmGateRun)) then
      raise EConvertError.Create('Train lever missing gate');
    Previous := C.Finish;
    if C.Source=EarlyBoardSource then begin
      if (I<>0) or (C.Kind<>tmBoard) or (C.Time<0.45) or (C.Time>0.76) then
        raise EConvertError.Create('Train departure onset');
      Inc(FSynced);
    end
    else if C.Source<>-1 then begin
      if (C.Source<=LastSource) or (C.Source>=Length(Audio.Hits)) or
         (Abs(C.Time-Audio.Hits[C.Source].Time)>0.065) then
        raise EConvertError.Create('Train accent reference');
      LastSource := C.Source;
      Inc(FSynced);
    end;
  end;
  if (Count<8) or (FCues[0].Kind<>tmBoard) or (FCues[0].Time>0.82) or
     (FCues[High(FCues)-1].Kind<>tmBossFinish) or
     (FCues[High(FCues)].Kind<>tmStation) then
    raise EConvertError.Create('Train phase order');
  SetLength(FExchanges,Count div 3);
  PreviousLead := -1;
  ExchangeCount := 0;
  I := 0;
  while I<Count do begin
    if not (FCues[I].Kind in [tmLeftImpact,tmRightImpact]) then begin
      if FCues[I].Kind in [tmCouple,tmTransfer] then raise EConvertError.Create('Train exchange order');
      Inc(I);
      Continue;
    end;
    E.StartIndex := I;
    E.LeftIndex := -1;
    E.RightIndex := -1;
    if FCues[I].Kind=tmLeftImpact then begin
      E.LeftIndex := I;
      Inc(I);
    end;
    if (I<Count) and (FCues[I].Kind=tmRightImpact) then begin
      E.RightIndex := I;
      Inc(I);
    end;
    if (E.StartIndex<2) or (I+4>=Count) or (FCues[I].Kind<>tmCouple) or
       (FCues[I+1].Kind<>tmTransfer) then raise EConvertError.Create('Train exchange order');
    E.CoupleIndex := I;
    E.TransferIndex := I+1;
    E.LeadCar := Floor(FCues[I].FromX/TrainPitch);
    if (E.LeadCar<PreviousLead+2) or (E.LeadCar>=FCars-2) or
       (Floor(FCues[I+1].FromX/TrainPitch)<>E.LeadCar) or
       (Floor(FCues[I+1].ToX/TrainPitch)<>E.LeadCar+1) then
      raise EConvertError.Create('Train exchange cars');
    for J := E.StartIndex to E.CoupleIndex do
      if (Floor(FCues[J].FromX/TrainPitch)<>E.LeadCar) or (Floor(FCues[J].ToX/TrainPitch)<>E.LeadCar) then
        raise EConvertError.Create('Train exchange contact car');
    if (ExchangeCount=0) and ((E.LeftIndex<0) or (E.RightIndex<0) or (FCues[E.StartIndex].Time>=10.02)) then
      raise EConvertError.Create('Train opening exchange');
    PreviousLead := E.LeadCar;
    FExchanges[ExchangeCount] := E;
    Inc(ExchangeCount);
    Inc(I,2);
  end;
  if ExchangeCount=0 then raise EConvertError.Create('Train exchange missing');
  SetLength(FExchanges,ExchangeCount);
end;

type
  TTrainTimingChoice = record
    Time, Merit, Total: Double;
    Source, Previous: Integer;
  end;

function FindTrainOnset(Audio: TRhythmAudio; Start, MinimumRise: Double; Windows: Integer): Double;
const
  Hop = 176; // 約4 ms
var
  Frames, FirstFrame, I, J, Addr: Integer;
  Samples: PSmallInt;
  Energy: TArray<Double>;
  L, R, Rise, Best: Double;
begin
  Result := -1;
  Frames := Length(Audio.PCM) div 4;
  FirstFrame := Round(Start*RHYTHM_RATE)-3*Hop;
  if (FirstFrame<0) or (FirstFrame+(Windows+3)*Hop>Frames) then Exit;
  SetLength(Energy,Windows+3);
  Samples := Pointer(Audio.PCM);
  for I := 0 to High(Energy) do begin
    Energy[I] := 0;
    for J := 0 to Hop-1 do begin
      Addr := (FirstFrame+I*Hop+J)*4;
      L := PSmallInt(PByte(Samples)+Addr)^/32768.0;
      R := PSmallInt(PByte(Samples)+Addr+2)^/32768.0;
      Energy[I] := Energy[I]+Sqr(L)+Sqr(R);
    end;
    Energy[I] := Sqrt(Energy[I]/(2*Hop));
  end;
  Best := MinimumRise;
  for I := 3 to High(Energy) do begin
    Rise := Energy[I]-(Energy[I-1]+Energy[I-2]+Energy[I-3])/3;
    if Rise>Best then begin
      Best := Rise;
      Result := (FirstFrame+I*Hop+Hop*0.35)/RHYTHM_RATE;
    end;
  end;
end;

procedure ScheduleTrainCues(Cues: TList<TTrainCue>; Audio: TRhythmAudio; EndTarget: Double;
  const Cancel: TFunc<Boolean>);
const
  CandidateLimit = 32;
  Unreachable = -1E20;
var
  Targets: TArray<Double>;
  Choices: TArray<TArray<TTrainTimingChoice>>;
  Options: TList<TTrainTimingChoice>;
  Entry, Prior: TTrainTimingChoice;
  Move: TTrainCue;
  I,J,K,Cursor,Worst,Winner,FirstExchange: Integer;
  Sum,TimeScale,Clock,Target,Window,RangeStart,RangeEnd,Spacing,Time,Strength,Emphasis,Total,
    StepTime, Gap, RouteMinimum, LongestGap, FirstWeight, FirstTarget: Double;
begin
  Sum := 0;
  FirstExchange := -1;
  FirstWeight := 0;
  for I := 0 to Cues.Count-1 do begin
    Move := Cues[I];
    Sum := Sum+Move.Time;
    if (FirstExchange<0) and (Move.Kind in [tmLeftImpact,tmRightImpact]) then begin
      FirstExchange := I;
      FirstWeight := Sum;
    end;
  end;
  FirstTarget := Min(8.35,EndTarget*FirstWeight/Sum);
  TimeScale := FirstTarget/FirstWeight;
  SetLength(Targets,Cues.Count);
  SetLength(Choices,Cues.Count);
  Clock := 0;
  Options := TList<TTrainTimingChoice>.Create;
  try
    for I := 0 to Cues.Count-1 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      Move := Cues[I];
      if I=FirstExchange+1 then TimeScale := (EndTarget-FirstTarget)/(Sum-FirstWeight);
      Clock := Clock+Move.Time*TimeScale;
      Target := Clock;
      if Move.Kind=tmBoard then Target := 0.56;
      Targets[I] := Target;
      Emphasis := 1.15;
      Window := Min(2.45,Max(0.68,1.55*Move.Time*TimeScale));
      case Move.Kind of
        tmBoard,tmLeftImpact,tmRightImpact,tmCouple,tmBossFinish:
          begin Emphasis := 2.2; Window := Min(3.2,Window+0.72); end;
        tmHurdleHit,tmVaultHit,tmBossDuck,tmLever,tmRoofGap: Emphasis := 1.86;
        tmHit,tmDuckHit,tmShot: Emphasis := 1.62;
      end;
      RangeStart := Max(0.32,Target-Window);
      RangeEnd := Min(Audio.Duration,Target+Window);
      if I=FirstExchange then RangeEnd := Min(RangeEnd,9.95);
      if Move.Kind=tmBoard then begin
        RangeStart := 0.40;
        RangeEnd := Min(0.75,RangeEnd);
      end;
      Options.Clear;
      Entry := Default(TTrainTimingChoice);
      Entry.Time := Target;
      Entry.Source := -1;
      Entry.Merit := -0.62*Emphasis;
      Options.Add(Entry);
      if Move.Kind=tmBoard then begin
        Time := FindTrainOnset(Audio,0.45,0.004,75);
        if Time>=0.45 then begin
          Entry.Time := Time;
          Entry.Source := EarlyBoardSource;
          Entry.Merit := 0.48;
          Options.Add(Entry);
        end;
      end;
      Cursor := Audio.NearestHit(RangeStart);
      while (Cursor>=0) and (Cursor<Length(Audio.Hits)) and (Audio.Hits[Cursor].Time<=RangeEnd) do begin
        if ((Cursor and 511)=0) and Assigned(Cancel) and Cancel() then Abort;
        Time := Audio.Hits[Cursor].Time;
        if Time>=RangeStart then begin
          Strength := Audio.Hits[Cursor].Strength;
          Entry.Time := Time;
          Entry.Source := Cursor;
          Entry.Merit := 0.46+Emphasis*Strength-0.83*Abs(Time-Target)/Window;
          if Options.Count<=CandidateLimit then Options.Add(Entry)
          else begin
            Worst := 1;
            for K := 2 to Options.Count-1 do
              if Options[K].Merit<Options[Worst].Merit then Worst := K;
            if Entry.Merit>Options[Worst].Merit then Options[Worst] := Entry;
          end;
        end;
        Inc(Cursor);
      end;
      Choices[I] := Options.ToArray;
      Spacing := 0.0;
      StepTime := 0.0;
      LongestGap := 0.0;
      if I>0 then begin
        StepTime := Targets[I]-Targets[I-1];
        RouteMinimum := 0.135+(Move.ToX-Cues[I-1].ToX)/19;
        case Move.Kind of
          tmJump,tmTransfer,tmBossJump: RouteMinimum := Max(0.44,RouteMinimum);
          tmLeftImpact: RouteMinimum := 0.99;
          tmRightImpact: RouteMinimum := 0.87;
          tmCouple: RouteMinimum := 0.64;
        end;
        Spacing := Min(RouteMinimum,StepTime*0.86);
        LongestGap := Max(1.28,StepTime*1.82+0.10);
      end;
      for J := 0 to High(Choices[I]) do begin
        Entry := Choices[I][J];
        Entry.Previous := -1;
        Entry.Total := Entry.Merit;
        if I>0 then begin
          Entry.Total := Unreachable;
          for K := 0 to High(Choices[I-1]) do begin
            Prior := Choices[I-1][K];
            Gap := Entry.Time-Prior.Time;
            if (Prior.Previous<0) and (I>1) then Continue;
            if (Gap<Spacing) or (Gap>LongestGap) then Continue;
            // 前後の間隔も評価し、音が密集した直後に長い空白ができるのを抑える。
            Total := Prior.Total+Entry.Merit-0.66*Sqr((Gap-StepTime)/Max(0.55,StepTime));
            if Total>Entry.Total then begin
              Entry.Previous := K;
              Entry.Total := Total;
            end;
          end;
        end;
        Choices[I][J] := Entry;
      end;
    end;
  finally
    Options.Free;
  end;

  I := Cues.Count-1;
  Winner := 0;
  for J := 1 to High(Choices[I]) do
    if Choices[I][J].Total>Choices[I][Winner].Total then Winner := J;
  while I>=0 do begin
    Entry := Choices[I][Winner];
    Move := Cues[I];
    Move.Time := Entry.Time;
    Move.Source := Entry.Source;
    Cues[I] := Move;
    Winner := Entry.Previous;
    Dec(I);
  end;

  // 共通解析の候補を選んだ後、使用するPCMで直近の立ち上がりへ寄せる。
  // PCMがない合成音テストや復元では参照・保存した時刻をそのまま使う。
  for I := 0 to Cues.Count-1 do begin
    Move := Cues[I];
    if Move.Source<0 then Continue;
    Time := FindTrainOnset(Audio,Audio.Hits[Move.Source].Time-0.052,0.0012,17);
    RangeEnd := Audio.Duration;
    if I=0 then begin
      RangeStart := 0.37;
      RangeEnd := Min(0.81,RangeEnd);
    end
    else RangeStart := Cues[I-1].Time+0.16;
    if I<Cues.Count-1 then RangeEnd := Min(RangeEnd,Cues[I+1].Time-0.16);
    if (Time>=RangeStart) and (Time<=RangeEnd) then Move.Time := Time;
    Cues[I] := Move;
  end;
end;

procedure AlignRemainingBossHits(Cues: TList<TTrainCue>; Audio: TRhythmAudio);
var I,J,K,BeforeSource,AfterSource,Best: Integer;
    C: TTrainCue; BeforeTime,AfterTime,Lo,Hi,BestCost,Cost: Double;
begin
  // Only unsynchronized boss contacts can move. Preserve every ordinary cue and
  // both adjacent phase lengths; lack of a real suitable accent keeps the fallback.
  for I := Cues.Count-3 to Cues.Count-2 do begin
    C := Cues[I];
    if (C.Source>=0) or not (C.Kind in [tmBossDuck,tmBossFinish]) then Continue;
    BeforeTime := Cues[I-1].Time;
    AfterTime := Cues[I+1].Time;
    Lo := Max(BeforeTime+0.78*(C.Time-BeforeTime),C.Time-0.32);
    Hi := Min(AfterTime-0.82*(AfterTime-C.Time),Min(Audio.SoundEnd,C.Time+0.32));
    if (Hi<Lo) or (Length(Audio.Hits)=0) then Continue;
    BeforeSource := -1;
    AfterSource := Length(Audio.Hits);
    for J := I-1 downto 0 do
      if Cues[J].Source>=0 then begin BeforeSource := Cues[J].Source; Break; end;
    for J := I+1 to Cues.Count-1 do
      if Cues[J].Source>=0 then begin AfterSource := Cues[J].Source; Break; end;
    K := Max(BeforeSource+1,Audio.NearestHit(Lo));
    Best := -1; BestCost := 1E20;
    while (K>=0) and (K<AfterSource) and (Audio.Hits[K].Time<=Hi) do begin
      if Audio.Hits[K].Time>=Lo then begin
        Cost := Abs(Audio.Hits[K].Time-C.Time)-0.055*Audio.Hits[K].Strength;
        if Cost<BestCost then begin Best := K; BestCost := Cost; end;
      end;
      Inc(K);
    end;
    if Best>=0 then begin
      C.Time := Audio.Hits[Best].Time;
      C.Source := Best;
      Cues[I] := C;
    end;
  end;
end;

function UsableTrainAccents(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): Integer;
var I: Integer; Time, Previous: Double;
begin
  Result := 0;
  Previous := 0.23;
  for I := 0 to High(Audio.Hits) do begin
    if ((I and 511)=0) and Assigned(Cancel) and Cancel() then Abort;
    Time := Audio.Hits[I].Time;
    if Time>Audio.SoundEnd then Break;
    if Time-Previous<0.30 then Continue;
    Previous := Time;
    Inc(Result);
  end;
end;

class function TTrainPlan.Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TTrainPlan;
var
  Cues: TList<TTrainCue>;
  Plan: TTrainPlan;
  C: TTrainCue;
  I, Car, TotalCars, Accents, NextLead, PreviousLead, Exchanges, CarsPerExchange,
    NextCourse, Courses: Integer;
  Clock, Gap, EndTarget, Lead, Tail, SecondsPerCar, AccentsPerCar: Double;
  FullRoof, ExtraEnemies: Boolean;

  procedure CheckCancel;
  begin
    if Assigned(Cancel) and Cancel() then Abort;
  end;

  procedure Add(Kind: TTrainMove; Weight, FromX, ToX: Double);
  var
    Move: TTrainCue;
  begin
    Move := Default(TTrainCue);
    Move.Kind := Kind;
    Move.Time := Weight;
    Move.FromX := FromX;
    Move.ToX := ToX;
    Move.Source := -1;
    if Cues.Count>0 then Move.Time := Max(Weight,0.30+(ToX-Cues.Last.ToX)/8.5);
    Cues.Add(Move);
  end;

  procedure Jump(Kind: TTrainMove; CarIndex: Integer; Weight, Land: Double);
  var
    X: Double;
  begin
    X := CarIndex*TrainPitch;
    Add(Kind,Weight,X-TrainGap-0.57,X+Land);
  end;

  procedure Fight(Kind: TTrainMove; CarIndex: Integer; X: Double; Weight: Double=0.98);
  const
    Travel: array[tmHit..tmShot] of Double = (0.94,1.97,1.65,0.92);
  begin
    X := CarIndex*TrainPitch+X;
    Add(Kind,Weight,X-Travel[Kind],X);
  end;

  procedure RoofEncounter(CarIndex: Integer; Lead: Boolean);
  var X: Double;
  begin
    X := CarIndex*TrainPitch;
    if Lead then begin
      Fight(tmHit,CarIndex,2.65);
      if ExtraEnemies then Fight(tmHit,CarIndex,3.64,0.72);
      Add(tmHurdleHit,1.02,X+3.73,X+7.04);
      Exit;
    end;
    if not FullRoof or (TotalCars<=4) then begin
      case CarIndex mod 3 of
        0: begin
             Fight(tmHit,CarIndex,2.85,1.14);
             Fight(tmShot,CarIndex,7.52,1.02);
           end;
        1: begin
             Fight(tmHit,CarIndex,2.85);
             Add(tmHurdleHit,1.02,X+5.83,X+9.40);
           end;
      else
        begin
          Add(tmHurdle,1.02,X+0.91,X+3.89);
          Fight(tmHit,CarIndex,5.13,0.70);
          Fight(tmDuckHit,CarIndex,8.65,0.80);
        end;
      end;
      Exit;
    end;
    case CarIndex mod 8 of
      0: begin
           Fight(tmHit,CarIndex,2.65);
           if ExtraEnemies then Fight(tmHit,CarIndex,3.64,0.72);
           Add(tmHurdleHit,1.02,X+3.73,X+7.04);
           Fight(tmDuckHit,CarIndex,9.32);
         end;
      1: begin
           Fight(tmHit,CarIndex,2.20);
           Add(tmHurdle,0.90,X+2.54,X+5.13);
           Add(tmHurdleHit,0.95,X+5.62,X+8.29);
           if ExtraEnemies then begin
             Fight(tmHit,CarIndex,9.38,0.77);
             Fight(tmHit,CarIndex,10.43,0.73);
           end else Fight(tmDuckHit,CarIndex,10.31);
         end;
      2: begin
           Fight(tmShot,CarIndex,1.98);
           if ExtraEnemies then begin
             Add(tmHurdle,0.90,X+3.60,X+6.21);
             Fight(tmDuckHit,CarIndex,8.09,0.86);
             Fight(tmVaultHit,CarIndex,10.18);
           end else begin
             Add(tmHurdle,0.90,X+3.94,X+7.23);
             Fight(tmVaultHit,CarIndex,9.64);
           end;
         end;
      3: begin
           Fight(tmHit,CarIndex,2.45);
           Fight(tmDuckHit,CarIndex,4.36);
           Fight(tmShot,CarIndex,7.68,0.94);
           if ExtraEnemies then begin
             Fight(tmHit,CarIndex,8.97,0.77);
             Fight(tmHit,CarIndex,10.10,0.73);
           end else Fight(tmHit,CarIndex,9.82);
         end;
      // 先制の光弾、上段をかわす反撃、隣車から来る敵への空中打撃。
      4: begin
           Fight(tmShot,CarIndex,2.19,0.80);
           Fight(tmDuckHit,CarIndex,5.12,1.11);
           Add(tmHurdleHit,1.02,X+6.04,X+9.55);
         end;
      // 機器を先に飛び越え、近い二体を連続で打ってから奥の敵を迎える。
      5: begin
           Add(tmHurdle,1.02,X+0.91,X+3.89);
           Fight(tmHit,CarIndex,5.13,0.70);
           Fight(tmHit,CarIndex,6.28,0.70);
           if ExtraEnemies then Fight(tmDuckHit,CarIndex,9.66,0.93)
           else Fight(tmShot,CarIndex,9.66,0.92);
         end;
      6: begin // 重装護衛
           Fight(tmDuckHit,CarIndex,2.88,1.11);
           Fight(tmHit,CarIndex,6.47,1.05);
           Fight(tmHit,CarIndex,7.66,0.91);
           Fight(tmShot,CarIndex,9.52,0.98);
         end;
      7: begin // 連続飛び込み
           Fight(tmHit,CarIndex,2.40,0.78);
           Fight(tmVaultHit,CarIndex,5.02,0.87);
           Add(tmHurdleHit,1.06,X+5.52,X+9.22);
           if ExtraEnemies then Fight(tmHit,CarIndex,10.52,0.87);
         end;
    end;
  end;

  procedure AddExchange(LeadCar, Number: Integer);
  var X: Double;
  begin
    X := LeadCar*TrainPitch;
    case Number mod 3 of
      0: begin
           Add(tmLeftImpact,2.08,X+7.29,X+8.30);
           Add(tmRightImpact,2.06,X+8.71,X+9.76);
         end;
      1: Add(tmRightImpact,2.08,X+7.54,X+9.76);
      2: Add(tmLeftImpact,2.08,X+7.29,X+8.92);
    end;
    Add(tmCouple,1.64,X+10.16,X+10.89);
    Jump(tmTransfer,LeadCar+1,0.92,0.70);
  end;

  procedure RoofCourse(CarIndex, Course: Integer);
  var X: Double;
  begin
    X := CarIndex*TrainPitch;
    case Course mod 3 of
      0: begin
           Add(tmSlide,0.98,X+1.14,X+3.86);
           Add(tmHurdle,0.91,X+4.11,X+6.64);
           Add(tmSlide,1.04,X+7.02,X+10.40);
         end;
      1: begin
           Add(tmRoofGap,0.90,X+1.18,X+4.00);
           Add(tmRoofGap,0.90,X+4.67,X+7.25);
           Add(tmRoofGap,0.94,X+7.88,X+10.67);
         end;
      2: begin
           Add(tmLever,0.76,X+1.25,X+2.32);
           Add(tmGateRun,0.67,X+3.70,X+5.18);
           Add(tmLever,0.81,X+6.12,X+7.22);
           Add(tmGateRun,0.78,X+8.60,X+10.40);
         end;
    end;
  end;

begin
  CheckCancel;
  if (Audio=nil) or (Audio.Duration<=0) or IsNan(Audio.Duration) or IsInfinite(Audio.Duration) or
     (Length(Audio.Hits)>100000) then
    raise EArgumentException.Create('Train audio bounds');
  Plan := TTrainPlan.Create;
  Cues := nil;
  try
    Plan.FDuration := Audio.Duration;
    Accents := UsableTrainAccents(Audio,Cancel);
    FullRoof := Audio.SoundEnd>=14;
    ExtraEnemies := FullRoof and (Accents>=Audio.SoundEnd*1.7);
    SecondsPerCar := 2.9;
    AccentsPerCar := 4.4;
    if ExtraEnemies then begin
      SecondsPerCar := 2.42;
      AccentsPerCar := 5.11;
    end;
    TotalCars := EnsureRange(Min(1+Floor(Min(MaxCars,Audio.SoundEnd/SecondsPerCar)),
      1+Floor(Accents/AccentsPerCar)),4,MaxCars);
    Plan.FCars := TotalCars;
    Plan.FEndTime := Audio.Duration;
    if (Audio.SoundEnd>0) and (Audio.Duration>=0.8) then begin
      Cues := TList<TTrainCue>.Create;
      NextLead := Min(2,TotalCars-3);
      PreviousLead := -2;
      Exchanges := 0;
      Courses := 0;
      NextCourse := 1;
      if Audio.SoundEnd<8 then NextCourse := TotalCars;
      CarsPerExchange := EnsureRange(Round((TotalCars-1)*19/Max(1.0,Audio.SoundEnd)),2,11);
      Add(tmBoard,0.72,TrainBoardX,0.73);
      for Car := 0 to TotalCars-2 do begin
        CheckCancel;
        if (Car>0) and (Car<>PreviousLead+1) then Jump(tmJump,Car,0.83,0.60);
        if (Car=NextCourse) and (Car=NextLead) then Inc(NextCourse);
        if Car=NextCourse then begin
          RoofCourse(Car,Courses);
          Inc(Courses);
          NextCourse := Car+4+((Courses div 2) mod 2);
        end else RoofEncounter(Car,Car=NextLead);
        if Car=NextLead then begin
          AddExchange(Car,Exchanges);
          PreviousLead := Car;
          Inc(Exchanges);
          NextLead := Car+Max(2,CarsPerExchange+((Exchanges-1) mod 3)-1);
          if NextLead>TotalCars-4 then NextLead := -1;
        end;
      end;
      Car := TotalCars-1;
      Jump(tmBossJump,Car,1.04,0.44);
      Add(tmBossDuck,1.10,Car*TrainPitch+2.45,Car*TrainPitch+4.30);
      Add(tmBossFinish,1.26,Car*TrainPitch+6.35,Car*TrainPitch+8.64);
      Add(tmStation,2.00,Plan.TrainLength-0.45,Plan.TrainLength+1.10);

      EndTarget := Max(8.50,Audio.SoundEnd+0.13);
      ScheduleTrainCues(Cues,Audio,EndTarget,Cancel);
      AlignRemainingBossHits(Cues,Audio);
      for I := 0 to Cues.Count-1 do begin
        C := Cues[I];
        Clock := 0;
        if I>0 then Clock := Cues[I-1].Time;
        Gap := C.Time-Clock;
        case C.Kind of
          tmBoard: Lead := 0.36;
          tmJump,tmTransfer,tmBossJump: Lead := 0.34;
          tmHit: Lead := 0.16;
          tmVaultHit,tmDuckHit,tmBossDuck: Lead := 0.31;
          tmHurdle,tmHurdleHit,tmRoofGap: Lead := 0.37;
          tmSlide: Lead := 0.49;
          tmLever: Lead := 0.19;
          tmGateRun: Lead := 0.31;
          tmShot,tmBossFinish: Lead := 0.23;
          tmLeftImpact: Lead := 0.45;
          tmRightImpact,tmCouple: Lead := 0.36;
          tmStation: Lead := 0.65;
        else
          Lead := 0.50;
        end;
        C.Start := C.Time-Min(Lead,Gap*0.62);
        Tail := 0.085;
        if C.Kind in [tmLeftImpact,tmRightImpact,tmCouple,tmStation] then Tail := 0.12;
        if I<Cues.Count-1 then Tail := Min(Tail,(Cues[I+1].Time-C.Time)*0.18);
        C.Finish := C.Time+Tail;
        Cues[I] := C;
      end;
      Plan.FCues := Cues.ToArray;
      Plan.FEndTime := Plan.FCues[High(Plan.FCues)].Time+0.83;
    end;
    Plan.Verify(Audio);
    Plan.IndexCars;
    Result := Plan;
    Plan := nil;
  finally
    Cues.Free;
    Plan.Free;
  end;
end;

procedure TTrainPlan.Save(var Ref: TRhythmPlanRef; Audio: TRhythmAudio);
var
  Root: TJSONObject;
  Rows, Row: TJSONArray;
  C: TTrainCue;
begin
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsTrain,0) then
    raise EArgumentException.Create('Train reference');
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsTrain));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('policy',TrainPolicy);
    Root.AddPair('end',PreparedExact(FEndTime));
    Root.AddPair('cars',TJSONNumber.Create(FCars));
    AddPreparedAudio(Root,Audio);
    Rows := TJSONArray.Create;
    Root.AddPair('cues',Rows);
    for C in FCues do begin
      Row := TJSONArray.Create;
      Rows.AddElement(Row);
      Row.Add(Ord(C.Kind));
      Row.Add(C.Source);
      Row.AddElement(PreparedExact(C.Start));
      Row.AddElement(PreparedExact(C.Time));
      Row.AddElement(PreparedExact(C.Finish));
      Row.AddElement(PreparedExact(C.FromX));
      Row.AddElement(PreparedExact(C.ToX));
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

class function TTrainPlan.LoadAudioMetadata(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
var
  Root: TJSONObject;
begin
  Root := ReadPreparedData(Ref,rsTrain,Direction);
  try
    if Root.GetValue<string>('policy','')<>TrainPolicy then raise EConvertError.Create('Train plan policy');
    Result := PreparedAudio(Root,Ref,Source);
  finally
    Root.Free;
  end;
end;

class function TTrainPlan.Load(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TTrainPlan;
var
  Root, Info: TJSONObject;
  Rows, Row: TJSONArray;
  I, Kind: Integer;
  Plan: TTrainPlan;
begin
  if (Audio=nil) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsTrain,0) then
    raise EArgumentException.Create('屋上アクションを準備して適用してください。');
  Root := ReadPreparedData(Ref,rsTrain,Direction);
  Plan := nil;
  try
    if Root.GetValue<string>('policy','')<>TrainPolicy then raise EConvertError.Create('Train plan policy');
    Info := Root.GetValue<TJSONObject>('audio');
    Rows := Root.GetValue<TJSONArray>('cues');
    if (Info=nil) or (Info.GetValue<Integer>('events')<>Length(Audio.Hits)) or
       (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>Epsilon) or
       (Rows=nil) or (Rows.Count>MaxCues) then
      raise EConvertError.Create('Train audio identity');
    Plan := TTrainPlan.Create;
    Plan.FDuration := Audio.Duration;
    Plan.FEndTime := ReadPreparedExact(Root.GetValue('end'));
    Plan.FCars := Root.GetValue<Integer>('cars');
    SetLength(Plan.FCues,Rows.Count);
    for I := 0 to Rows.Count-1 do begin
      if not (Rows.Items[I] is TJSONArray) then raise EConvertError.Create('Train cue row');
      Row := TJSONArray(Rows.Items[I]);
      if Row.Count<>7 then raise EConvertError.Create('Train cue columns');
      Kind := Row.Items[0].GetValue<Integer>;
      if (Kind<Ord(Low(TTrainMove))) or (Kind>Ord(High(TTrainMove))) then
        raise EConvertError.Create('Train cue kind');
      Plan.FCues[I].Kind := TTrainMove(Kind);
      Plan.FCues[I].Source := Row.Items[1].GetValue<Integer>;
      Plan.FCues[I].Start := ReadPreparedExact(Row.Items[2]);
      Plan.FCues[I].Time := ReadPreparedExact(Row.Items[3]);
      Plan.FCues[I].Finish := ReadPreparedExact(Row.Items[4]);
      Plan.FCues[I].FromX := ReadPreparedExact(Row.Items[5]);
      Plan.FCues[I].ToX := ReadPreparedExact(Row.Items[6]);
    end;
    Plan.Verify(Audio);
    Plan.IndexCars;
    Result := Plan;
    Plan := nil;
  finally
    Plan.Free;
    Root.Free;
  end;
end;

end.
