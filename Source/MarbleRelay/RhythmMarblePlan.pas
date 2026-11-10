unit RhythmMarblePlan;
// 球の衝突時刻からコースを組む。空中は一定の重力、レール上は接線方向に進む。
interface

uses System.SysUtils, RhythmAudio, RhythmPlanRef, RhythmBallGeometry;

const
  MarbleRadius = 0.155;
  MarbleAuxRadius = 0.088;
  MarbleAuxGateNose = MarbleAuxRadius + 0.037;
  MarbleSlope = -0.19;
  MarbleGravity = 15.5;
  MarbleSeesawExitGrade = -0.30;
  MarbleTrayRear = -0.18;
  MarbleTrayNose = 0.135;
  MarbleJunctionSpan = 0.37;

type
  TMarbleMotion = (mmRail, mmFlight, mmSettle, mmBend, mmCarry, mmSwing, mmSeesaw);
  TMarbleDevice = (mdGate, mdBell, mdSpring, mdCatch, mdTip, mdGoal,
    mdBend, mdLift, mdShuttle, mdSwing, mdChute, mdSharedTap, mdSeesaw, mdTrayRelease, mdJunctionGate);
  TMarbleLinkKind = (mlNone, mlShutter, mlSpringLatch);
  TMarbleBeat = record
    Time, Power: Double;
  end;
  TMarbleLink = record
    Kind: TMarbleLinkKind;
    Target: Integer;
    Heading: Integer;
    Pull, Ready, Deadline: Double;
    Driver, Receiver: TBallPoint;
    function Opening(Time: Double): Double;
  end;
  TMarbleRun = record
    Start, Speed, Grade: Double;
    Origin: TBallPoint;
    function Position(Time: Double; Heading: Integer): TBallPoint;
    function SpeedAt(Time: Double): Double;
  end;
  TMarbleJunction = record
    Branch: TMarbleRun;
    Pull, Ready: Double;
    function Active: Boolean;
    function Pivot(Heading: Integer): TBallPoint;
    function Tip(Time: Double; Heading: Integer): TBallPoint;
    procedure Spur(out A, B: TBallPoint; Heading: Integer);
  end;
  TMarbleLatch = record
    Beat: TMarbleBeat;
    Contact, Pivot: TBallPoint;
    function SeatedAt: Double;
    function Amount(Time: Double): Double;
  end;
  TMarbleInterlock = record
    Inputs: array[0..1] of TMarbleLatch;
    Gate: TMarbleLink;
    SmallDeadline: Double;
    function Active: Boolean;
    function Opening(Time: Double): Double;
  end;
  TMarbleBoard = record
    Pivot: TBallPoint;
    Heading: Integer;
    Start, Stop, BaseAngle, Tilt, Rear, Front, LoadPoint: Double;
    function AngleAt(Time: Double): Double;
    function PointAt(Time, Along, Radius: Double): TBallPoint;
    function VelocityAt(Time, Along, Radius, RollSpeed: Double): TBallPoint;
    function MainDistance(Time: Double): Double;
  end;
  TMarbleWeightLift = record
    Load: TBallPoint;
    Arrival, Start, Dock, Rise, Ramp: Double;
    function Active: Boolean;
    function Progress(Time: Double): Double;
    function Carriage(Time: Double): TBallPoint;
  end;
  TMarbleTrayRelease = record
    Lever: TMarbleLatch;
    Start: Double;
    function Active: Boolean;
    function AngleAt(Time: Double): Double;
    function DistanceAt(Time: Double): Double;
  end;
  TMarbleSeesaw = record
    Board: TMarbleBoard;
    Trigger, Bell: TMarbleBeat;
    Seat, SeatSpeed: Double;
    Launch, LaunchVelocity, LeverContact, Landing: TBallPoint;
    WeightLift: TMarbleWeightLift;
    TrayRelease: TMarbleTrayRelease;
    SwitchLever: TMarbleLatch;
    ExitGate: TMarbleLink;
    ExitBell: TMarbleBeat;
    CatchRail, ExitRail: TMarbleRun;
    ExitCurveStart: Double;
    Gate: TMarbleLink;
    function Pan(Time: Double): TBallPoint;
    function TrayPoint(Time, Along, Radius: Double): TBallPoint;
    function RunPosition(Time: Double): TBallPoint;
    function RunGrade(Time: Double): Double;
    function Active: Boolean;
    function Position(Time, Finish: Double): TBallPoint;
  end;
  TMarbleCounter = record
    DetourBeat: TMarbleBeat;
    Taps: array[0..1] of TMarbleBeat;
    Rejoin, LastRun: TMarbleRun;
    Entry: TBallPoint;
    Start, EntrySpeed, Depth: Double;
    Gate: TMarbleLink;
    Interlock: TMarbleInterlock;
    Seesaw: TMarbleSeesaw;
    function Active: Boolean;
    function Guide(U: Double): TBallPoint;
    function GuideSlope(U: Double): Double;
    function Position(Time, Finish: Double; Heading: Integer): TBallPoint;
  end;
  TMarblePass = record
    Fork: TMarbleBeat;
    Taps: array[0..1] of TMarbleBeat;
    Approach, Bypass, Rejoin, LastRun: TMarbleRun;
    ExitOrigin, ExitVelocity: TBallPoint;
    SwitchPull, SwitchReady: Double;
    Counter: TMarbleCounter;
    function Active: Boolean;
    function Position(Time, Finish: Double; Heading: Integer): TBallPoint;
  end;
  TMarbleMerge = record
    Launch: TMarbleBeat;
    Taps: array[0..1] of TMarbleBeat;
    Join, JoinSpeed, Grade, LowerDrag, TapSpeed: Double;
    LaunchPoint, LaunchVelocity, JoinPoint, TapPoint: TBallPoint;
    Pass: TMarblePass;
    function Active: Boolean;
    function Position(Time, Finish: Double; Heading: Integer): TBallPoint;
  end;
  TMarbleAuxiliary = record
    Origin, Receiver: TBallPoint;
    Release, Strike: Double;
    StrikePower, RunSpeed, RunGrade, Finish: Double;
    DropStart, DropEnd, LandingSpeed: Double;
    DropOrigin, DropVelocity, Landing: TBallPoint;
    SecondStrike, Bell: TMarbleBeat;
    AuxGates: array[0..1] of TMarbleLink;
    Merge: TMarbleMerge;
    function Active: Boolean;
    function Duet: Boolean;
    function Reciprocal: Boolean;
    function Crossover: Boolean;
    function Position(Time: Double): TBallPoint;
    function RailGrade(Time: Double): Double;
  end;
  TMarbleBridge = record
    Entry, Hinge: TBallPoint;
    Pull, Ready, Deadline: Double;
    Auxiliary: TMarbleAuxiliary;
    Sliding, Retracting: Boolean;
    function Active: Boolean;
    function Tip(Time: Double): TBallPoint;
  end;
  TMarbleLeg = record
    Motion: TMarbleMotion;
    Heading: Integer;
    Start, Finish, VX, VY, Grade, Terminal, Drag, Radius, EntryGap, DropLip, Dock, Spin, FreeSpin: Double;
    Origin, Travel: TBallPoint;
    Board: TMarbleBoard;
    WeightLift: TMarbleWeightLift;
    Bridge: TMarbleBridge;
    Junction: TMarbleJunction;
    ArcClock: TArray<Double>;
    function Position(Time: Double): TBallPoint;
    function Velocity(Time: Double): TBallPoint;
    function Carriage(Time: Double): TBallPoint;
    function Rotation(Time: Double): Double;
    function Rollout: Boolean;
    function RailSlope: Double;
    procedure RailSupport(out A, B: TBallPoint);
    function LiftRailSupport(out A, B: TBallPoint): Boolean;
    procedure BranchRailSupport(out A, B: TBallPoint);
    function HasWeightLift: Boolean;
    function ArcPoint(Angle: Double): TBallPoint;
    function ArcPivot: TBallPoint;
  end;
  TMarbleCue = record
    Time, Power, Slope: Double;
    RelayBeat: TMarbleBeat; // 主球のこの接触と次の接触の間に、小球へ渡せる音。
    SharedBeat: TMarbleBeat; // 同じ押し板を小球が押す時刻。譜面から復元する。
    Heading: Integer;
    Device: TMarbleDevice;
    Center, Surface: TBallPoint;
  end;
  TMarbleSection = record
    First, Last: Integer;
    Left, Right, Bottom, Top: Double;
  end;
  TMarblePlan = class
  public
    Version: Integer;
    Duration, EndTime: Double;
    Cues: TArray<TMarbleCue>;
    Legs: TArray<TMarbleLeg>;
    Sections: TArray<TMarbleSection>;
    Links: TArray<TMarbleLink>; // ドライバーの接触番号で引く。
    function CueAt(Time: Double): Integer;
    function BeatAt(Time: Double; out Beat: TMarbleBeat): Integer;
    function Position(Time: Double): TBallPoint;
    function CameraTarget(Time: Double): TBallPoint;
    function Rotation(Time: Double): Double;
  end;

function MarbleRailSurface(const Center: TBallPoint; Slope: Double = MarbleSlope): TBallPoint;
function BuildMarblePlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TMarblePlan;
procedure SaveMarblePlan(Plan: TMarblePlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
function LoadMarblePlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TMarblePlan;
function LoadMarbleAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;

implementation

uses System.Math, System.JSON, System.Generics.Collections, RhythmPreparedData, RhythmStyles;

type
  TMarbleDuetLayout = (dlShort, dlReciprocal, dlCrossover, dlMerge, dlPass, dlCounter, dlInterlock, dlSeesaw, dlWeightLift);

const
  MinContactGap = 0.15;
  MaxCues = 22000;
  LegacyTerminal = 3.9;
  LegacyDrag = 0.64;
  RailDrag = 1.14;
  GoalTravel = 0.47;
  GoalTime = 0.34;
  ArcSteps = 28;
  SwingHalf = 0.80;
  RollingFactor = 5 / 7;
  TriggerDelay = 0.014;
  ArrivalMargin = 0.016;
  LatchTime = 0.068;
  DuetGrade = -0.23;
  LowerGrade = -0.085;
  DuetBrakeTime = 0.16;
  LiftBrakeTime = 0.09;
  TrayTiltTime = 0.12;
  TrayTilt = 0.43;
  JunctionSpurAngle = -1.07;
  JunctionSpurLength = 0.32;
  DuetSecondGap = 0.53;
  ReciprocalGap = 0.72;

function MarbleRailSurface(const Center: TBallPoint; Slope: Double): TBallPoint;
begin
  Result := BallSub(Center, BallScale(BallUnit(BallPoint(-Slope, 1)), MarbleRadius));
end;

function TMarbleLeg.RailSlope: Double;
begin
  Result := Heading * Grade;
end;

procedure TMarbleLeg.RailSupport(out A, B: TBallPoint);
begin
  A := MarbleRailSurface(BallAdd(Origin, BallPoint(Heading * EntryGap, Grade * EntryGap)), RailSlope);
  if Motion = mmSeesaw then A := MarbleRailSurface(Position(Dock), RailSlope);
  if Junction.Active then
  begin
    B := MarbleRailSurface(Junction.Branch.Origin, RailSlope);
    Exit;
  end;
  B := MarbleRailSurface(Position(Finish), RailSlope);
  if HasWeightLift then
    B := MarbleRailSurface(WeightLift.Load, RailSlope)
  else
    B := BallSub(B, BallPoint(Heading * DropLip, Grade * DropLip));
end;

function TMarbleLeg.LiftRailSupport(out A, B: TBallPoint): Boolean;
var DockPoint: TBallPoint;
begin
  DockPoint := WeightLift.Carriage(WeightLift.Dock);
  A := MarbleRailSurface(BallAdd(DockPoint, BallPoint(Heading * WeightLift.Ramp, Grade * WeightLift.Ramp)), RailSlope);
  B := MarbleRailSurface(Position(Finish), RailSlope);
  Result := Heading * (B.X - A.X) > 0;
end;

procedure TMarbleLeg.BranchRailSupport(out A, B: TBallPoint);
var BranchGrade: Double;
begin
  BranchGrade := Junction.Branch.Grade;
  A := Junction.Pivot(Heading);
  B := MarbleRailSurface(Position(Finish), Heading * BranchGrade);
  B := BallSub(B, BallPoint(Heading * DropLip, BranchGrade * DropLip));
end;

function TMarbleLeg.HasWeightLift: Boolean;
begin
  Result := (Motion = mmSeesaw) and WeightLift.Active;
end;

function Smooth(U: Double): Double;
begin
  Result := Sqr(U) * (3 - 2 * U);
end;

function TMarbleJunction.Active: Boolean;
begin
  Result := Ready > Pull;
end;

function TMarbleJunction.Pivot(Heading: Integer): TBallPoint;
begin
  Result := MarbleRailSurface(Branch.Origin, Heading * Branch.Grade);
end;

function TMarbleJunction.Tip(Time: Double; Heading: Integer): TBallPoint;
var Angle, U: Double;
begin
  U := Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0));
  Angle := JunctionSpurAngle + (ArcTan(Branch.Grade) - JunctionSpurAngle) * U;
  Result := BallAdd(Pivot(Heading), BallPoint(Heading * MarbleJunctionSpan * Cos(Angle), MarbleJunctionSpan * Sin(Angle)));
end;

procedure TMarbleJunction.Spur(out A, B: TBallPoint; Heading: Integer);
begin
  A := Tip(Pull, Heading);
  B := BallAdd(A, BallPoint(Heading * JunctionSpurLength * Cos(JunctionSpurAngle),
    JunctionSpurLength * Sin(JunctionSpurAngle)));
end;

function TMarbleLink.Opening(Time: Double): Double;
begin
  Result := 0;
  if Kind <> mlNone then Result := Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0));
end;

function TMarbleLatch.SeatedAt: Double;
begin
  Result := Beat.Time + LatchTime;
end;

function TMarbleLatch.Amount(Time: Double): Double;
begin
  Result := Smooth(EnsureRange((Time - Beat.Time) / LatchTime, 0.0, 1.0));
end;

function TMarbleInterlock.Active: Boolean;
begin
  Result := Gate.Kind = mlShutter;
end;

function TMarbleInterlock.Opening(Time: Double): Double;
begin
  if not Active or (Time < Inputs[0].SeatedAt) or (Time < Inputs[1].SeatedAt) then Exit(0);
  Result := Gate.Opening(Time);
end;

function TMarbleBoard.AngleAt(Time: Double): Double;
var U: Double;
begin
  U := EnsureRange((Time - Start) / (Stop - Start), 0.0, 1.0);
  Result := BaseAngle - Tilt * Sqr(U) * U;
end;

function TMarbleBoard.PointAt(Time, Along, Radius: Double): TBallPoint;
var A: Double;
begin
  A := AngleAt(Time);
  Result := BallAdd(Pivot, BallPoint(Heading * (Along * Cos(A) - Radius * Sin(A)), Along * Sin(A) + Radius * Cos(A)));
end;

function TMarbleBoard.VelocityAt(Time, Along, Radius, RollSpeed: Double): TBallPoint;
var A, U, W, Tangent, Normal: Double;
begin
  A := AngleAt(Time);
  U := EnsureRange((Time - Start) / (Stop - Start), 0.0, 1.0);
  W := -3 * Tilt * Sqr(U) / (Stop - Start);
  Tangent := RollSpeed - Radius * W;
  Normal := Along * W;
  Result := BallPoint(Heading * (Tangent * Cos(A) - Normal * Sin(A)), Tangent * Sin(A) + Normal * Cos(A));
end;

function TMarbleBoard.MainDistance(Time: Double): Double;
begin
  Result := LoadPoint + (Front - LoadPoint) * EnsureRange((Time - Start) / (Stop - Start), 0.0, 1.0);
end;

function TMarbleAuxiliary.Active: Boolean;
begin
  Result := Strike > Release;
end;

function TMarbleAuxiliary.Duet: Boolean;
begin
  Result := Finish > Strike;
end;

function TMarbleAuxiliary.Reciprocal: Boolean;
begin
  Result := SecondStrike.Time > 0;
end;

function TMarbleAuxiliary.Crossover: Boolean;
begin
  Result := DropEnd > DropStart;
end;

function TMarbleAuxiliary.RailGrade(Time: Double): Double;
begin
  if Merge.Active and (Time >= Merge.Join) then Exit(Merge.Grade);
  if Crossover and (Time >= DropEnd) then Exit(LowerGrade);
  Result := RunGrade;
end;

function RailDistance(StartSpeed, Terminal, Drag, Age: Double): Double; forward;
function RailTerminalFor(Grade, Drag: Double): Double; forward;

function TMarbleRun.Position(Time: Double; Heading: Integer): TBallPoint;
var D: Double;
begin
  D := RailDistance(Speed, RailTerminalFor(Grade, RailDrag), RailDrag, Time - Start);
  Result := BallAdd(Origin, BallPoint(Heading * D, Grade * D));
end;

function TMarbleRun.SpeedAt(Time: Double): Double;
var Terminal: Double;
begin
  Terminal := RailTerminalFor(Grade, RailDrag);
  Result := Terminal + (Speed - Terminal) * Exp(-RailDrag * (Time - Start));
end;

function TMarbleWeightLift.Active: Boolean;
begin
  Result := Dock > Start;
end;

function TMarbleWeightLift.Progress(Time: Double): Double;
begin
  Result := Smooth(EnsureRange((Time - Start) / (Dock - Start), 0.0, 1.0));
end;

function TMarbleWeightLift.Carriage(Time: Double): TBallPoint;
begin
  Result := BallAdd(Load, BallPoint(0, Rise * Progress(Time)));
end;

function TMarbleTrayRelease.Active: Boolean;
begin
  Result := Start > 0;
end;

function TMarbleTrayRelease.AngleAt(Time: Double): Double;
begin
  Result := -TrayTilt * Smooth(EnsureRange((Time - Start) / TrayTiltTime, 0.0, 1.0));
end;

function TrayAcceleration: Double;
begin
  Result := RollingFactor * MarbleGravity * Sin(TrayTilt);
end;

function TMarbleTrayRelease.DistanceAt(Time: Double): Double;
var U, Roll: Double;
begin
  U := EnsureRange((Time - Start) / TrayTiltTime, 0.0, 1.0);
  Roll := Max(0.0, Time - Start - TrayTiltTime);
  // 傾く間は加速度を滑らかに増やし、その後は一定の斜面として転がす。
  Result := TrayAcceleration * (Sqr(TrayTiltTime) * Sqr(Sqr(U)) * (0.25 - U * 0.1) +
    Roll * (TrayTiltTime + Roll) / 2);
end;

function TMarbleSeesaw.Pan(Time: Double): TBallPoint;
begin
  Result := BallSub(Landing, BallPoint(0, WeightLift.Rise * WeightLift.Progress(Time)));
end;

function TMarbleSeesaw.TrayPoint(Time, Along, Radius: Double): TBallPoint;
var Angle: Double; Pivot: TBallPoint;
begin
  Pivot := Pan(Time);
  Pivot.Y := Pivot.Y - MarbleAuxRadius;
  Angle := TrayRelease.AngleAt(Time);
  Result := BallAdd(Pivot, BallPoint(Board.Heading * (Along * Cos(Angle) - Radius * Sin(Angle)),
    Along * Sin(Angle) + Radius * Cos(Angle)));
end;

function TMarbleSeesaw.RunPosition(Time: Double): TBallPoint;
var Entry: TBallPoint; Distance, Span: Double;
begin
  if (ExitRail.Start > 0) and (Time >= ExitRail.Start) then Exit(ExitRail.Position(Time, Board.Heading));
  Result := CatchRail.Position(Time, Board.Heading);
  if (ExitRail.Start = 0) or (Time <= ExitCurveStart) then Exit;
  Entry := CatchRail.Position(ExitCurveStart, Board.Heading);
  Distance := Board.Heading * (Result.X - Entry.X);
  Span := Board.Heading * (ExitRail.Origin.X - Entry.X);
  Result.Y := Result.Y + (ExitRail.Grade - CatchRail.Grade) * Sqr(Distance) / (2 * Span);
end;

function TMarbleSeesaw.RunGrade(Time: Double): Double;
var Entry, P: TBallPoint; U: Double;
begin
  Result := CatchRail.Grade;
  if (ExitRail.Start = 0) or (Time <= ExitCurveStart) then Exit;
  if Time >= ExitRail.Start then Exit(ExitRail.Grade);
  Entry := CatchRail.Position(ExitCurveStart, Board.Heading);
  P := CatchRail.Position(Time, Board.Heading);
  U := (P.X - Entry.X) / (ExitRail.Origin.X - Entry.X);
  Result := Result + (ExitRail.Grade - Result) * U;
end;

function TMarbleSeesaw.Active: Boolean;
begin
  Result := (Board.Stop > Board.Start) and (Trigger.Time > Board.Stop) and (CatchRail.Start > Trigger.Time);
end;

function TMarbleSeesaw.Position(Time, Finish: Double): TBallPoint;
var Age, T, BrakeAge: Double;
begin
  if Time < Board.Stop then
    Exit(Board.PointAt(Time, Seat + SeatSpeed * (Time - Board.Start), MarbleAuxRadius));
  if Time < CatchRail.Start then
  begin
    if WeightLift.Active and (Time >= Trigger.Time) then
    begin
      if TrayRelease.Active then Exit(TrayPoint(Time, TrayRelease.DistanceAt(Time), MarbleAuxRadius));
      Exit(Pan(Time));
    end;
    Age := Time - Board.Stop;
    Exit(BallAdd(Launch, BallPoint(LaunchVelocity.X * Age, LaunchVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age))));
  end;
  T := Min(Time, Finish);
  BrakeAge := Max(0.0, T - (Finish - DuetBrakeTime));
  Result := RunPosition(T - Sqr(BrakeAge) / (2 * DuetBrakeTime));
end;

function TMarbleCounter.Active: Boolean;
begin
  Result := (Start > 0) and (Rejoin.Start > Start);
end;

function TMarbleCounter.Guide(U: Double): TBallPoint;
begin
  Result := BallMix(Entry, Rejoin.Origin, U);
  Result.Y := Result.Y - Depth * Sqr(Sin(Pi * U));
end;

function TMarbleCounter.GuideSlope(U: Double): Double;
begin
  Result := (Rejoin.Origin.Y - Entry.Y - Pi * Depth * Sin(2 * Pi * U)) / (Rejoin.Origin.X - Entry.X);
end;

function TMarbleCounter.Position(Time, Finish: Double; Heading: Integer): TBallPoint;
var U, Duration, Distance, T, BrakeAge: Double;
begin
  if Seesaw.Active and (Time >= Seesaw.Board.Start) then Exit(Seesaw.Position(Time, Finish));
  if Time < Rejoin.Start then
  begin
    Duration := Rejoin.Start - Start;
    Distance := Abs(Rejoin.Origin.X - Entry.X);
    U := (Time - Start) / Duration;
    Exit(Guide(Smooth(U) + U * (1 - U) * ((1 - U) * EntrySpeed - U * Rejoin.Speed) * Duration / Distance));
  end;
  if Time < Taps[0].Time then Exit(Rejoin.Position(Time, Heading));
  T := Min(Time, Finish);
  BrakeAge := Max(0.0, T - (Finish - DuetBrakeTime));
  Result := LastRun.Position(T - Sqr(BrakeAge) / (2 * DuetBrakeTime), Heading);
end;

function TMarblePass.Active: Boolean;
begin
  Result := (Fork.Time > 0) and (Rejoin.Start > Fork.Time);
end;

function TMarblePass.Position(Time, Finish: Double; Heading: Integer): TBallPoint;
var Age: Double;
begin
  if Time < Fork.Time then Exit(Approach.Position(Time, Heading));
  if Time < Rejoin.Start then Exit(Bypass.Position(Time, Heading));
  if Time < Taps[0].Time then Exit(Rejoin.Position(Time, Heading));
  if Time < Taps[1].Time then Exit(LastRun.Position(Time, Heading));
  if Counter.Active then Exit(Counter.Position(Time, Finish, Heading));
  Age := Min(Time, Finish) - Taps[1].Time;
  Result := BallAdd(ExitOrigin, BallPoint(ExitVelocity.X * Age, ExitVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age)));
end;

function TMarbleMerge.Active: Boolean;
begin
  Result := (Launch.Time > 0) and (Join > Launch.Time);
end;

function TMarbleMerge.Position(Time, Finish: Double; Heading: Integer): TBallPoint;
var Age, BrakeAge, Start, Speed, Distance: Double; P: TBallPoint;
begin
  if Pass.Active and (Time >= Taps[1].Time) then Exit(Pass.Position(Time, Finish, Heading));
  if Time < Join then
  begin
    Age := Time - Launch.Time;
    Exit(BallAdd(LaunchPoint, BallPoint(LaunchVelocity.X * Age, LaunchVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age))));
  end;
  Start := Join;
  Speed := JoinSpeed;
  P := JoinPoint;
  if Time >= Taps[0].Time then
  begin
    Start := Taps[0].Time;
    Speed := TapSpeed;
    P := TapPoint;
  end;
  Age := Min(Time, Finish) - Start;
  BrakeAge := Max(0.0, Age - (Finish - Start - DuetBrakeTime));
  Distance := RailDistance(Speed, RailTerminalFor(Grade, RailDrag), RailDrag, Age - Sqr(BrakeAge) / (2 * DuetBrakeTime));
  Result := BallAdd(P, BallPoint(Heading * Distance, Grade * Distance));
end;

function TMarbleAuxiliary.Position(Time: Double): TBallPoint;
var Age, BrakeAge, Distance, StartTime, Speed, Grade, Drag: Double; StartPoint: TBallPoint;
begin
  if not Active then Exit(Origin);
  if Duet and (Time > Strike) then
  begin
    if Merge.Active and (Time >= Merge.Launch.Time) then
      Exit(Merge.Position(Time, Finish, Sign(Receiver.X - Origin.X)));
    if Crossover and (Time >= DropStart) and (Time < DropEnd) then
    begin
      Age := Time - DropStart;
      Exit(BallAdd(DropOrigin, BallPoint(DropVelocity.X * Age, DropVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age))));
    end;
    StartTime := Strike;
    StartPoint := Receiver;
    Speed := RunSpeed;
    Grade := RailGrade(Time);
    Drag := RailDrag;
    if Crossover and (Time >= DropEnd) then
    begin
      StartTime := DropEnd;
      StartPoint := Landing;
      Speed := LandingSpeed;
      if Merge.LowerDrag > 0 then Drag := Merge.LowerDrag;
    end;
    Age := Min(Time, Finish) - StartTime;
    BrakeAge := Max(0.0, Age - (Finish - StartTime - DuetBrakeTime));
    Distance := RailDistance(Speed, RailTerminalFor(Grade, Drag), Drag,
      Age - Sqr(BrakeAge) / (2 * DuetBrakeTime));
    Exit(BallAdd(StartPoint, BallPoint(Sign(Receiver.X - Origin.X) * Distance, Grade * Distance)));
  end;
  Result := BallMix(Origin, Receiver, Sqr(EnsureRange((Time - Release) / (Strike - Release), 0.0, 1.0)));
end;

function TMarbleBridge.Active: Boolean;
begin
  Result := Ready > Pull;
end;

function TMarbleBridge.Tip(Time: Double): TBallPoint;
var Span, Angle, U: Double;
begin
  if Retracting and Active then
    Exit(BallMix(Entry, Hinge, Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0))));
  if not Active or (Time >= Ready) then Exit(Entry);
  Span := BallLength(BallSub(Hinge, Entry));
  U := Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0));
  if Sliding then Exit(BallMix(Hinge, Entry, U));
  Angle := ArcTan2(Hinge.Y - Entry.Y, Abs(Hinge.X - Entry.X)) + 1.23 * (1 - U);
  Result := BallPoint(Hinge.X - Sign(Hinge.X - Entry.X) * Span * Cos(Angle), Hinge.Y - Span * Sin(Angle));
end;

function TMarbleLeg.Rollout: Boolean;
begin
  Result := (Motion in [mmCarry, mmSwing]) and (Dock > Start) and (Dock < Finish);
end;

function TMarbleLeg.ArcPivot: TBallPoint;
begin
  if Motion = mmBend then Exit(BallPoint(Origin.X, Origin.Y - Radius));
  Result := BallPoint(Origin.X + Heading * Radius * Sin(SwingHalf), Origin.Y + Radius * Cos(SwingHalf));
end;

function TMarbleLeg.ArcPoint(Angle: Double): TBallPoint;
var Pivot: TBallPoint;
begin
  Pivot := ArcPivot;
  if Motion = mmBend then
    Exit(BallPoint(Pivot.X + Heading * Radius * Sin(Angle), Pivot.Y + Radius * Cos(Angle)));
  Result := BallPoint(Pivot.X + Heading * Radius * Sin(Angle), Pivot.Y - Radius * Cos(Angle));
end;

function BendSpeed(const Leg: TMarbleLeg; Angle: Double): Double;
begin
  Result := Sqrt(Sqr(Leg.VX) + 2 * RollingFactor * MarbleGravity * Leg.Radius * (1 - Cos(Angle)));
end;

function BendAngle(const Leg: TMarbleLeg; Age: Double): Double;
var L, R, M: Integer; U, A, B, Span, TangentA, TangentB: Double;
begin
  if Age <= 0 then Exit(0);
  if Age >= Leg.Finish - Leg.Start then Exit(Pi);
  L := 0;
  R := High(Leg.ArcClock);
  while R - L > 1 do
  begin
    M := (L + R) div 2;
    if Leg.ArcClock[M] <= Age then L := M else R := M;
  end;
  Span := Leg.ArcClock[R] - Leg.ArcClock[L];
  U := (Age - Leg.ArcClock[L]) / Span;
  A := L * Pi / ArcSteps;
  B := R * Pi / ArcSteps;
  TangentA := Span * BendSpeed(Leg, A) / Leg.Radius;
  TangentB := Span * BendSpeed(Leg, B) / Leg.Radius;
  // 区間境界でも角速度が連続するよう、通過時刻表を接線付きで補間する。
  Result := A + (B - A) * Smooth(U) + U * (1 - U) * ((1 - U) * TangentA - U * TangentB);
end;

function RailDistance(StartSpeed, Terminal, Drag, Age: Double): Double;
begin
  Result := Terminal * Age + (StartSpeed - Terminal) * (1 - Exp(-Drag * Age)) / Drag;
end;

function TMarbleLeg.Carriage(Time: Double): TBallPoint;
var EndTime, U: Double;
begin
  EndTime := Finish;
  if Rollout then EndTime := Dock;
  U := Smooth((EnsureRange(Time, Start, EndTime) - Start) / (EndTime - Start));
  if Motion = mmSwing then Exit(ArcPoint(SwingHalf * (2 * U - 1)));
  if Travel.Y < 0 then Exit(BallAdd(Origin, BallPoint(Travel.X * U, Travel.Y * Sqr(U))));
  Result := BallAdd(Origin, BallScale(Travel, U));
end;

function TMarbleLeg.Position(Time: Double): TBallPoint;
var Age, DX, U: Double;
begin
  Age := EnsureRange(Time, Start, Finish) - Start;
  if Rollout and (Time > Dock) then
  begin
    DX := RailDistance(0, Terminal, Drag, Age - (Dock - Start));
    Exit(BallAdd(Carriage(Dock), BallPoint(Heading * DX, Grade * DX)));
  end;
  case Motion of
    mmRail:
      begin
        if Junction.Active and (Time >= Junction.Branch.Start) then
          Exit(Junction.Branch.Position(Min(Time, Finish), Heading));
        DX := RailDistance(VX, Terminal, Drag, Age);
        Result := BallPoint(Origin.X + Heading * DX, Origin.Y + Grade * DX);
      end;
    mmFlight:
      Result := BallPoint(Origin.X + VX * Age, Origin.Y + VY * Age - 0.5 * MarbleGravity * Sqr(Age));
    mmSettle:
      begin
        U := Age / GoalTime;
        Result := BallPoint(Origin.X + Heading * GoalTravel * U * (2 - U), Origin.Y);
      end;
    mmBend: Result := ArcPoint(BendAngle(Self, Age));
    mmCarry, mmSwing: Result := Carriage(Time);
    mmSeesaw:
      begin
        if Time <= Dock then Exit(Board.PointAt(Time, Board.MainDistance(Time), MarbleRadius));
        if HasWeightLift then
        begin
          if Time >= WeightLift.Dock then
          begin
            DX := RailDistance(0, Terminal, Drag, Age - (WeightLift.Dock - Start));
            Exit(BallAdd(WeightLift.Carriage(WeightLift.Dock), BallPoint(Heading * DX, Grade * DX)));
          end;
          if Time >= WeightLift.Arrival then Exit(WeightLift.Carriage(Time));
          U := Max(0.0, Time - (WeightLift.Arrival - LiftBrakeTime));
          Age := Age - Sqr(U) / (2 * LiftBrakeTime);
        end;
        DX := RailDistance(VX, Terminal, Drag, Age - (Dock - Start));
        Result := BallAdd(Board.PointAt(Dock, Board.Front, MarbleRadius), BallPoint(Heading * DX, Grade * DX));
      end;
  end;
end;

function TMarbleLeg.Velocity(Time: Double): TBallPoint;
var Age, Speed, Angle, U, ActiveTime: Double;
begin
  Age := EnsureRange(Time, Start, Finish) - Start;
  ActiveTime := Finish - Start;
  if Rollout then
  begin
    ActiveTime := Dock - Start;
    if Time > Dock then
    begin
      Speed := Terminal * (1 - Exp(-Drag * (Age - ActiveTime)));
      Exit(BallPoint(Heading * Speed, Grade * Speed));
    end;
  end;
  case Motion of
    mmRail:
      begin
        if Junction.Active and (Time >= Junction.Branch.Start) then
        begin
          Speed := Junction.Branch.SpeedAt(Min(Time, Finish));
          Exit(BallPoint(Heading * Speed, Junction.Branch.Grade * Speed));
        end;
        Speed := Terminal + (VX - Terminal) * Exp(-Drag * Age);
        Result := BallPoint(Heading * Speed, Grade * Speed);
      end;
    mmFlight: Result := BallPoint(VX, VY - MarbleGravity * Age);
    mmSettle: Result := BallPoint(Heading * 2 * GoalTravel / GoalTime * (1 - Age / GoalTime), 0);
    mmBend:
      begin
        Angle := BendAngle(Self, Age);
        Speed := BendSpeed(Self, Angle);
        Result := BallPoint(Heading * Speed * Cos(Angle), -Speed * Sin(Angle));
      end;
    mmCarry:
      begin
        U := Age / ActiveTime;
        Result := BallScale(Travel, 6 * U * (1 - U) / ActiveTime);
        if Travel.Y < 0 then Result.Y := Result.Y * 2 * Smooth(U);
      end;
    mmSwing:
      begin
        U := Age / ActiveTime;
        Angle := SwingHalf * (2 * Smooth(U) - 1);
        Speed := Radius * 2 * SwingHalf * 6 * U * (1 - U) / ActiveTime;
        Result := BallPoint(Heading * Speed * Cos(Angle), Speed * Sin(Angle));
      end;
    mmSeesaw:
      begin
        if Time < Dock then Exit(Board.VelocityAt(Time, Board.MainDistance(Time), MarbleRadius,
          (Board.Front - Board.LoadPoint) / (Dock - Start)));
        Age := Age - (Dock - Start);
        if HasWeightLift then
        begin
          if Time >= WeightLift.Dock then
          begin
            Speed := Terminal * (1 - Exp(-Drag * (Age - (WeightLift.Dock - Dock))));
            Exit(BallPoint(Heading * Speed, Grade * Speed));
          end;
          if Time >= WeightLift.Arrival then
          begin
            ActiveTime := WeightLift.Dock - WeightLift.Start;
            U := EnsureRange((Time - WeightLift.Start) / ActiveTime, 0.0, 1.0);
            Exit(BallPoint(0, WeightLift.Rise * 6 * U * (1 - U) / ActiveTime));
          end;
          U := Max(0.0, Time - (WeightLift.Arrival - LiftBrakeTime));
          Age := Age - Sqr(U) / (2 * LiftBrakeTime);
          Speed := (Terminal + (VX - Terminal) * Exp(-Drag * Age)) * (1 - U / LiftBrakeTime);
        end
        else Speed := Terminal + (VX - Terminal) * Exp(-Drag * Age);
        Result := BallPoint(Heading * Speed, Grade * Speed);
      end;
  end;
end;

function TMarbleLeg.Rotation(Time: Double): Double;
var Distance, Age: Double;
begin
  Result := Spin;
  Age := EnsureRange(Time, Start, Finish) - Start;
  case Motion of
    mmFlight: Exit(Spin + FreeSpin * Age);
    mmBend: Distance := Radius * BendAngle(Self, Age);
    mmRail, mmSettle:
      begin
        Distance := BallLength(BallSub(Position(Time), Origin));
        if Junction.Active and (Time > Junction.Branch.Start) then
          Distance := BallLength(BallSub(Junction.Branch.Origin, Origin)) +
            BallLength(BallSub(Position(Time), Junction.Branch.Origin));
      end;
    mmSeesaw:
      begin
        Distance := Board.MainDistance(Time) - Board.LoadPoint;
        if HasWeightLift and (Time >= WeightLift.Arrival) then
        begin
          Distance := Distance + BallLength(BallSub(WeightLift.Load, Position(Dock)));
          if Time > WeightLift.Dock then
            Distance := Distance + BallLength(BallSub(Position(Time), WeightLift.Carriage(WeightLift.Dock)));
        end
        else if Time > Dock then Distance := Distance + BallLength(BallSub(Position(Time), Position(Dock)));
      end;
    else
      begin
        if not Rollout or (Time <= Dock) then Exit;
        Distance := BallLength(BallSub(Position(Time), Carriage(Dock)));
      end;
  end;
  Result := Spin - Heading * Distance / MarbleRadius;
end;

function TMarblePlan.CueAt(Time: Double): Integer;
var L, R, M: Integer;
begin
  L := 0;
  R := Length(Cues);
  while L < R do
  begin
    M := (L + R) div 2;
    if Cues[M].Time <= Time then L := M + 1 else R := M;
  end;
  Result := L - 1;
end;

function TMarblePlan.BeatAt(Time: Double; out Beat: TMarbleBeat): Integer;
var Index, Offset: Integer; Aux: TMarbleAuxiliary; Reply: TMarbleBeat;
begin
  Index := CueAt(Time);
  Beat := Default(TMarbleBeat);
  if Index < 0 then Exit(-1);
  Beat.Time := Cues[Index].Time;
  Beat.Power := Cues[Index].Power;
  if Version < 6 then Exit(Index);
  Result := Index * 2;
  for Offset := 0 to Min(Index, 14) do
  begin
    Aux := Legs[Index + 1 - Offset].Bridge.Auxiliary;
    if not Aux.Duet then Continue;
    case Offset of
      0:
        begin
          Reply.Time := Aux.Strike;
          Reply.Power := Aux.StrikePower;
        end;
      1:
        if Aux.Reciprocal then Reply := Aux.SecondStrike else Reply := Aux.Bell;
      2:
        if Aux.Reciprocal then Reply := Aux.Bell else Continue;
      3:
        if Aux.Merge.Active then Reply := Aux.Merge.Launch else Continue;
      4, 5:
        if Aux.Merge.Active then Reply := Aux.Merge.Taps[Offset - 4] else Continue;
      6:
        if Aux.Merge.Pass.Active then Reply := Aux.Merge.Pass.Fork else Continue;
      7, 8:
        if Aux.Merge.Pass.Active then Reply := Aux.Merge.Pass.Taps[Offset - 7] else Continue;
      9:
        if Aux.Merge.Pass.Counter.Active then Reply := Aux.Merge.Pass.Counter.DetourBeat else Continue;
      10, 11:
        if Aux.Merge.Pass.Counter.Active then Reply := Aux.Merge.Pass.Counter.Taps[Offset - 10] else Continue;
      12:
        if Aux.Merge.Pass.Counter.Seesaw.Active then Reply := Aux.Merge.Pass.Counter.Seesaw.Trigger else Continue;
      13:
        if Aux.Merge.Pass.Counter.Seesaw.Active then Reply := Aux.Merge.Pass.Counter.Seesaw.Bell else Continue;
      14:
        if Aux.Merge.Pass.Counter.Seesaw.ExitBell.Time > 0 then Reply := Aux.Merge.Pass.Counter.Seesaw.ExitBell else Continue;
    end;
    if Reply.Time > Time then Continue;
    Beat := Reply;
    Exit(Result + 1);
  end;
end;

function TMarblePlan.Position(Time: Double): TBallPoint;
begin
  if Length(Legs) = 0 then Exit(BallPoint(0, 0.4));
  Result := Legs[CueAt(Time) + 1].Position(Time);
end;

function TMarblePlan.Rotation(Time: Double): Double;
begin
  if Length(Legs) = 0 then Exit(0);
  Result := Legs[CueAt(Time) + 1].Rotation(Time);
end;

function TMarblePlan.CameraTarget(Time: Double): TBallPoint;
const FollowSamples = 10;
      FollowStep = 0.075;
var I, J: Integer; BallY, Offset, Lift, EndOfBoard, Fade, Height: Double;
begin
  Result := Position(Time);
  BallY := Result.Y;
  if Version >= 2 then
  begin
    // 折り返しと受け渡しの急な速度変化を、少しだけ前後の位置でならす。
    Result.X := 0;
    for I := -2 to 2 do Result.X := Result.X + Position(Time + I * 0.065).X * (3 - Abs(I));
    Result.X := Result.X / 9;
  end;
  Result.Y := 0;
  for I := -FollowSamples to FollowSamples do
    Result.Y := Result.Y + Position(Time + I * FollowStep).Y * (FollowSamples + 1 - Abs(I));
  Result.Y := Result.Y / Sqr(FollowSamples + 1);
  if Version >= 2 then
  begin
    // 大きな落下だけ追従を強める。制限に入る点でも速度が急に変わらないようにする。
    Offset := Result.Y - BallY;
    if Abs(Offset) > 0.90 then
      Result.Y := BallY + Sign(Offset) * (0.90 + 0.50 * (1 - Exp((0.90 - Abs(Offset)) / 0.50)));
  end;
  if Version >= 13 then
  begin
    // 発射に先行して少しだけ見上げ、下段の主球も画面に残す。
    J := CueAt(Time + 0.14);
    for I := Min(High(Legs), J + 1) downto Max(0, J - 7) do
      if Legs[I].Motion = mmSeesaw then
      begin
        EndOfBoard := Legs[Min(High(Legs), I + 1)].Finish;
        Fade := 0.60;
        Height := 0.42;
        if (I + 2 <= High(Legs)) and Legs[I + 1].Junction.Active then
        begin
          // 分岐の先で小球が上に残る間も、滑らかに両方を収める。
          EndOfBoard := Legs[I + 2].Finish;
          Fade := 0.85;
          Height := Height + 0.55 * Smooth(EnsureRange((Time - Legs[I + 1].Junction.Branch.Start) / 1.10, 0.0, 1.0));
        end;
        if Time >= EndOfBoard + Fade then Continue;
        Lift := Height * Smooth(EnsureRange((Time - Legs[I].Start + 0.14) / 0.40, 0.0, 1.0)) *
          (1 - Smooth(EnsureRange((Time - EndOfBoard) / Fade, 0.0, 1.0)));
        Result.Y := Result.Y + Min(Lift, Max(0.0, 1.48 - (Result.Y - BallY)));
        Break;
      end;
  end;
end;

procedure LayLegacyCourse(Plan: TMarblePlan);
// レールと弾道を並べ、姿勢や速度の変化は仕掛けとの接触点だけで起こす。
const Rolls: set of Byte = [0, 1, 5, 8];
var I, Part: Integer; Next: TMarbleLeg; P, Incoming: TBallPoint; Gap: Double; Device: TMarbleDevice;
begin
  Plan.EndTime := Plan.Duration;
  if Length(Plan.Cues) = 0 then Exit;
  SetLength(Plan.Legs, Length(Plan.Cues) + 1);
  Plan.Legs[0].Start := Max(0.0, Plan.Cues[0].Time - 0.65);
  Plan.Legs[0].Finish := Plan.Cues[0].Time;
  Plan.Legs[0].Origin := BallPoint(0, 0.4);
  Plan.Legs[0].VX := 2.9;
  Plan.Legs[0].Heading := 1;
  Plan.Legs[0].Grade := MarbleSlope;
  Plan.Legs[0].Terminal := LegacyTerminal;
  Plan.Legs[0].Drag := LegacyDrag;
  for I := 0 to High(Plan.Cues) do
  begin
    Next := Default(TMarbleLeg);
    Next.Start := Plan.Cues[I].Time;
    P := Plan.Legs[I].Position(Next.Start);
    Incoming := Plan.Legs[I].Velocity(Next.Start);
    Next.Origin := P;
    Next.VX := Incoming.X;
    Next.Heading := 1;
    Next.Grade := MarbleSlope;
    Next.Terminal := LegacyTerminal;
    Next.Drag := LegacyDrag;
    if I = High(Plan.Cues) then
    begin
      Device := mdGoal;
      Next.Motion := mmSettle;
      Next.Finish := Next.Start + GoalTime;
      Plan.EndTime := Max(Plan.Duration, Next.Finish);
    end
    else
    begin
      Next.Finish := Plan.Cues[I + 1].Time;
      Gap := Next.Finish - Next.Start;
      Part := I mod 9;
      if (Part in Rolls) or (Gap > 0.82) then
      begin
        Next.Motion := mmRail;
        if Plan.Legs[I].Motion = mmRail then Device := mdGate else Device := mdCatch;
      end
      else
      begin
        Next.Motion := mmFlight;
        if (Part = 6) and (Plan.Legs[I].Motion = mmRail) and InRange(Gap, 0.22, 0.64) then
        begin
          Device := mdTip;
          Next.VY := Incoming.Y; // レールの端から接線速度のまま落ち始める。
        end
        else
        begin
          // 同じ高さの次の受け皿へ、定重力の放物線で到達する初速。
          Next.VY := 0.5 * MarbleGravity * Gap;
          Device := mdBell;
          if (Plan.Legs[I].Motion = mmRail) or (Next.VY > -Incoming.Y + 0.05) then Device := mdSpring;
        end;
      end;
    end;
    Plan.Legs[I + 1] := Next;
    Plan.Cues[I].Device := Device;
    Plan.Cues[I].Center := P;
    Plan.Cues[I].Heading := 1;
    if (Next.Motion = mmRail) or (Plan.Legs[I].Motion = mmRail) then Plan.Cues[I].Slope := MarbleSlope;
    if Device = mdGate then Plan.Cues[I].Surface := BallPoint(P.X + MarbleRadius, P.Y)
    else if (Next.Motion = mmRail) or (Plan.Legs[I].Motion = mmRail) then
      Plan.Cues[I].Surface := MarbleRailSurface(P)
    else Plan.Cues[I].Surface := BallPoint(P.X, P.Y - MarbleRadius);
  end;
end;

function RailTerminalFor(Grade, Drag: Double): Double;
begin
  Result := -RollingFactor * MarbleGravity * Grade / (1 + Sqr(Grade)) / Drag;
end;

procedure SetRail(var Leg: TMarbleLeg; Grade, StartSpeed: Double);
begin
  Leg.Motion := mmRail;
  Leg.Junction := Default(TMarbleJunction);
  Leg.Grade := Grade;
  Leg.VX := StartSpeed;
  Leg.Drag := RailDrag;
  // 球の転がり加速度を水平方向に射影する。抵抗は速度に比例する。
  Leg.Terminal := RailTerminalFor(Grade, Leg.Drag);
end;

procedure AddRollout(var Leg: TMarbleLeg);
begin
  if not (Leg.Motion in [mmCarry, mmSwing]) then Exit;
  Leg.Dock := Leg.Start + (Leg.Finish - Leg.Start) * 0.68;
  Leg.Grade := -0.43;
  Leg.Drag := RailDrag;
  Leg.Terminal := RailTerminalFor(Leg.Grade, Leg.Drag);
end;

function BendInterval(Radius, Speed, A, B: Double): Double;
var Energy: Double;
  function InverseSpeed(Angle: Double): Double;
  begin
    Result := Radius / Sqrt(Sqr(Speed) + Energy * (1 - Cos(Angle)));
  end;
begin
  Energy := 2 * RollingFactor * MarbleGravity * Radius;
  Result := (B - A) / 6 * (InverseSpeed(A) + 4 * InverseSpeed((A + B) * 0.5) + InverseSpeed(B));
end;

function FitBend(var Leg: TMarbleLeg; Speed, Gap: Double): Boolean;
const AngleStep = Pi / ArcSteps;
var L, R, Radius, Duration: Double; I, J: Integer;
begin
  // 重力で転がる半円の通過時間が次の音に一致する半径を求める。
  L := 0;
  R := (Speed + 10) * Gap;
  for I := 0 to 23 do
  begin
    Radius := (L + R) * 0.5;
    Duration := 0;
    for J := 0 to ArcSteps - 1 do
      Duration := Duration + BendInterval(Radius, Speed, J * AngleStep, (J + 1) * AngleStep);
    if Duration < Gap then L := Radius else R := Radius;
  end;
  Radius := (L + R) * 0.5;
  Result := Radius >= MarbleRadius + 0.15;
  if not Result then Exit;
  Leg.Motion := mmBend;
  Leg.Radius := Radius;
  Leg.VX := Speed;
  SetLength(Leg.ArcClock, ArcSteps + 1);
  for J := 1 to ArcSteps do
    Leg.ArcClock[J] := Leg.ArcClock[J - 1] + BendInterval(Radius, Speed, (J - 1) * AngleStep, J * AngleStep);
  Duration := Leg.ArcClock[ArcSteps];
  for J := 1 to ArcSteps do Leg.ArcClock[J] := Leg.ArcClock[J] * Gap / Duration;
end;

function PrepareLeg(var Leg: TMarbleLeg; const Previous: TMarbleLeg; const Incoming: TBallPoint;
  Part: Integer): TMarbleDevice;
var Gap, Grade, Rise, Speed: Double; Room: Boolean;
begin
  Gap := Leg.Finish - Leg.Start;
  Room := InRange(Gap, 0.30, 0.84);
  Speed := Abs(Incoming.X);
  if Room then
    case Part of
      5, 12:
        if (Speed > 0.7) and FitBend(Leg, BallLength(Incoming), Gap) then Exit(mdBend);
      8:
        begin
          Leg.Motion := mmCarry;
          Leg.Travel := BallPoint(0, EnsureRange(Gap * 1.64, 0.48, 1.16));
          Exit(mdLift);
        end;
      9:
        begin
          Leg.Motion := mmCarry;
          Leg.Travel := BallPoint(Leg.Heading * EnsureRange(Gap * 3.1, 0.76, 1.85), 0);
          Exit(mdShuttle);
        end;
      10:
        begin
          Leg.Motion := mmSwing;
          Leg.Radius := EnsureRange(Gap * 1.76, 0.54, 1.16);
          Exit(mdSwing);
        end;
      14:
        if (Gap <= 0.65) and (Previous.Motion = mmRail) then
        begin
          Leg.Motion := mmFlight;
          Leg.VY := Min(0.0, Incoming.Y);
          Exit(mdChute);
        end;
    end;
  if (Part in [0, 1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 18, 19]) or (Gap > 0.84) then
  begin
    Grade := -0.19;
    if Part in [1, 7, 13] then Grade := -0.62;
    if Part in [6, 11] then Grade := -0.42;
    if Part in [18, 19] then Grade := -0.35;
    if Previous.Rollout then Grade := Previous.Grade;
    if Gap > 1.20 then Grade := -0.14;
    // 斜面の切り替えでは入射速度の接線成分だけを引き継ぐ。
    SetRail(Leg, Grade, Max(0.0, (Leg.Heading * Incoming.X + Grade * Incoming.Y) / (1 + Sqr(Grade))));
    if Previous.Motion = mmRail then Exit(mdGate);
    Exit(mdCatch);
  end;
  Leg.Motion := mmFlight;
  if (Part = 17) and (Previous.Motion = mmRail) and InRange(Gap, 0.22, 0.58) then
  begin
    Leg.VX := Incoming.X;
    Leg.VY := Incoming.Y;
    Exit(mdTip);
  end;
  Rise := 0;
  if Part in [2, 15] then Rise := Min(0.36, 0.27 * MarbleGravity * Sqr(Gap));
  Leg.VX := Leg.Heading * Max(Speed, 2.35);
  Leg.VY := 0.5 * MarbleGravity * Gap + Rise / Gap;
  if (Part = 3) and (Previous.Motion = mmFlight) then
    Leg.VY := Min(Leg.VY, Max(0.0, -Incoming.Y * 0.92));
  if (Previous.Motion = mmFlight) and (Speed >= 2.35) and (Leg.VY <= -Incoming.Y + 0.05) then Exit(mdBell);
  Result := mdSpring;
end;

function CoursePart(Version, Index: Integer): Integer;
const Layouts: array[0..1, 0..17] of Integer = (
  (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17),
  (0, 1, 2, 3, 4, 5, 6, 7, 10, 8, 9, 11, 12, 13, 14, 15, 16, 17));
  ChainLayouts: array[0..1, 0..19] of Integer = (
    (0, 1, 2, 3, 4, 5, 6, 7, 8, 18, 9, 19, 10, 11, 12, 13, 14, 15, 16, 17),
    (0, 1, 2, 3, 4, 5, 6, 7, 10, 18, 8, 19, 9, 11, 12, 13, 14, 15, 16, 17));
begin
  if Version >= 3 then Exit(ChainLayouts[(Index div 20) mod 2, Index mod 20]);
  Result := Layouts[(Index div 18) mod 2, Index mod 18];
end;

function PassSlot(Version, Index: Integer): Boolean;
begin
  Result := (Version >= 10) and (Index mod 20 in [7, 8, 9]);
end;

function CounterSlot(Version, Index: Integer): Boolean;
begin
  Result := (Version >= 11) and (Index mod 20 in [10, 11, 12]);
end;

function SeesawSlot(Version, Index: Integer): Boolean;
begin
  Result := (Version >= 13) and (Index mod 20 in [13, 14]);
end;

function JunctionTailSlot(Version, Index: Integer): Boolean;
begin
  Result := (Version >= 16) and (Index mod 20 = 15);
end;

function FitMainBoard(var Leg: TMarbleLeg; const Previous: TMarbleLeg; const Incoming: TBallPoint): Boolean;
var Board: TMarbleBoard; A, B: TBallPoint;
begin
  Result := False;
  if (Previous.Motion <> mmRail) or (Previous.DropLip > 0) or (Leg.Finish - Leg.Start < 0.72) then Exit;
  Board := Default(TMarbleBoard);
  Board.Start := Leg.Start;
  Board.Stop := Leg.Start + 0.128;
  Board.Heading := Leg.Heading;
  Board.BaseAngle := ArcTan(Previous.Grade);
  Board.Tilt := 0.275;
  Board.LoadPoint := 0.88;
  Board.Front := 1.28;
  Board.Rear := -1.24;
  Previous.RailSupport(A, B);
  if Abs(B.X - A.X) < (Board.LoadPoint - Board.Rear) * Cos(Board.BaseAngle) + 0.20 then Exit;
  Board.Pivot := BallSub(B, BallPoint(Leg.Heading * Board.LoadPoint * Cos(Board.BaseAngle), Board.LoadPoint * Sin(Board.BaseAngle)));
  SetRail(Leg, MarbleSeesawExitGrade, Max(1.45, Abs(Incoming.X) * 0.79));
  Leg.Board := Board;
  Leg.Dock := Board.Stop;
  Leg.Motion := mmSeesaw;
  Result := True;
end;

procedure FitMainWeightLift(var Leg: TMarbleLeg; Touch: Double; ExtendRamp: Boolean);
var Lift: TMarbleWeightLift;
begin
  Lift := Default(TMarbleWeightLift);
  Lift.Arrival := Touch - 0.105;
  Lift.Start := Touch + TriggerDelay;
  Lift.Dock := Min(Touch + 0.27, Leg.Finish - 0.21);
  if (Lift.Arrival - Leg.Dock < 0.16) or (Lift.Dock - Lift.Start < 0.19) then Exit;
  Lift.Rise := 0.53;
  if ExtendRamp then Lift.Ramp := 0.27;
  Lift.Load := Leg.Position(Lift.Arrival - LiftBrakeTime / 2);
  Leg.WeightLift := Lift;
end;

function RailTimeAtX(const Leg: TMarbleLeg; X: Double): Double; forward;

procedure FitMainJunction(var Leg: TMarbleLeg; Contact: Double);
var Junction: TMarbleJunction; Velocity, EndPoint: TBallPoint; NoseTime: Double;
begin
  Junction := Default(TMarbleJunction);
  Junction.Branch.Start := Max(Contact + 0.24, Leg.Start + (Leg.Finish - Leg.Start) * 0.66);
  if Junction.Branch.Start >= Leg.Finish - 0.15 then Exit;
  Junction.Branch.Origin := Leg.Position(Junction.Branch.Start);
  // レールを回し終えてから主球の前縁が軸へ届くようにする。
  NoseTime := RailTimeAtX(Leg, Junction.Branch.Origin.X - Leg.Heading * (MarbleRadius + 0.018));
  Junction.Pull := Contact + TriggerDelay;
  Junction.Ready := Min(Contact + 0.22, NoseTime - ArrivalMargin);
  if Junction.Ready - Junction.Pull < 0.072 then Exit;
  Junction.Branch.Grade := -0.52;
  Velocity := Leg.Velocity(Junction.Branch.Start);
  Junction.Branch.Speed := (Leg.Heading * Velocity.X + Junction.Branch.Grade * Velocity.Y) /
    (1 + Sqr(Junction.Branch.Grade));
  EndPoint := Junction.Branch.Position(Leg.Finish, Leg.Heading);
  if BallLength(BallSub(EndPoint, Junction.Branch.Origin)) < MarbleJunctionSpan + 0.08 then Exit;
  Leg.Junction := Junction;
end;

function MotionBounds(const Leg: TMarbleLeg): TMarbleSection;
var A, B, Pivot: TBallPoint;
begin
  Result := Default(TMarbleSection);
  A := Leg.Origin;
  B := Leg.Position(Leg.Finish);
  Result.Left := Min(A.X, B.X);
  Result.Right := Max(A.X, B.X);
  Result.Bottom := Min(A.Y, B.Y);
  Result.Top := Max(A.Y, B.Y);
  if Leg.Junction.Active then
  begin
    Leg.Junction.Spur(A, B, Leg.Heading);
    Result.Left := Min(Result.Left, B.X);
    Result.Right := Max(Result.Right, B.X);
    Result.Bottom := Min(Result.Bottom, B.Y);
  end;
  if Leg.HasWeightLift then
  begin
    Result.Bottom := Min(Result.Bottom, Leg.WeightLift.Load.Y);
    Result.Top := Max(Result.Top, Leg.WeightLift.Carriage(Leg.WeightLift.Dock).Y);
  end;
  case Leg.Motion of
    mmFlight: Result.Top := Result.Top + MarbleGravity * Sqr(Leg.Finish - Leg.Start) / 8;
    mmBend, mmSwing:
      begin
        Pivot := Leg.ArcPivot;
        Result.Left := Min(Result.Left, Pivot.X - Leg.Radius);
        Result.Right := Max(Result.Right, Pivot.X + Leg.Radius);
        Result.Bottom := Min(Result.Bottom, Pivot.Y - Leg.Radius);
        Result.Top := Max(Result.Top, Pivot.Y + Leg.Radius);
      end;
  end;
end;

function PathClearsSegment(const Path: TMarbleLeg; const A, B: TBallPoint; Clearance: Double): Boolean;
const Samples = 32;
var Segment, Offset, P: TBallPoint; Length2, U: Double; I: Integer;
begin
  Segment := BallSub(B, A);
  Length2 := Max(1E-12, BallDot(Segment, Segment));
  for I := 0 to Samples do
  begin
    P := Path.Position(Path.Start + (Path.Finish - Path.Start) * I / Samples);
    Offset := BallSub(P, A);
    U := EnsureRange(BallDot(Offset, Segment) / Length2, 0.0, 1.0);
    if BallLength(BallSub(Offset, BallScale(Segment, U))) < Clearance then Exit(False);
  end;
  Result := True;
end;

function PathClearsRail(const Path, Rail: TMarbleLeg): Boolean;
var A, B: TBallPoint;
begin
  Rail.RailSupport(A, B);
  if not PathClearsSegment(Path, A, B, MarbleRadius - 0.006) then Exit(False);
  if Rail.Junction.Active then
  begin
    Rail.Junction.Spur(A, B, Rail.Heading);
    if not PathClearsSegment(Path, A, B, MarbleRadius - 0.006) then Exit(False);
    Rail.BranchRailSupport(A, B);
  end
  else if not Rail.HasWeightLift or not Rail.LiftRailSupport(A, B) then Exit(True);
  Result := PathClearsSegment(Path, A, B, MarbleRadius - 0.006);
end;

function CourseClear(const Leg: TMarbleLeg; Plan: TMarblePlan;
  const Bounds: TArray<TMarbleSection>; Index: Integer): Boolean;
const SearchWindow = 32;
var Box, Other: TMarbleSection; I: Integer;
begin
  Box := MotionBounds(Leg);
  for I := Max(0, Index - SearchWindow) to Index - 1 do
  begin
    Other := Bounds[I];
    if (Box.Left > Other.Right + 0.36) or (Box.Right < Other.Left - 0.36) or
      (Box.Bottom > Other.Top + 0.36) or (Box.Top < Other.Bottom - 0.36) then Continue;
    if (Plan.Legs[I].Motion in [mmRail, mmSeesaw]) and not PathClearsRail(Leg, Plan.Legs[I]) then Exit(False);
    if (Leg.Motion in [mmRail, mmSeesaw]) and not PathClearsRail(Plan.Legs[I], Leg) then Exit(False);
  end;
  Result := True;
end;

procedure ClearNearbyRails(var Leg: TMarbleLeg; var Device: TMarbleDevice; Plan: TMarblePlan;
  const Bounds: TArray<TMarbleSection>; Index: Integer; const Incoming: TBallPoint);
const Grades: array[0..4] of Double = (-0.34, -0.61, -0.12, -0.83, -0.04);
var Candidate, Previous: TMarbleLeg; Grade: Double; A, B: TBallPoint;
begin
  if Leg.Motion = mmSeesaw then
  begin
    Previous := Plan.Legs[Index - 1];
    Previous.RailSupport(A, B);
    Plan.Legs[Index - 1].DropLip := Previous.DropLip +
      Leg.Heading * (B.X - Leg.Board.PointAt(Leg.Start, Leg.Board.Rear, 0).X);
    if CourseClear(Leg, Plan, Bounds, Index) then Exit;
    Plan.Legs[Index - 1] := Previous;
  end
  else if Device = mdChute then
  begin
    // 最後の短いレールは開く底板。静止したレールの端を残して球を落とさない。
    Previous := Plan.Legs[Index - 1];
    Plan.Legs[Index - 1].DropLip := Min(0.29, Abs(Previous.Position(Previous.Finish).X - Previous.Origin.X));
    if CourseClear(Leg, Plan, Bounds, Index) then Exit;
    Plan.Legs[Index - 1] := Previous;
  end
  else if CourseClear(Leg, Plan, Bounds, Index) then Exit;
  if Leg.Junction.Active then
  begin
    Leg.Junction := Default(TMarbleJunction);
    if CourseClear(Leg, Plan, Bounds, Index) then Exit;
  end;
  Candidate := Leg;
  if Candidate.Motion in [mmCarry, mmSwing] then
  begin
    Candidate.Travel := BallScale(Candidate.Travel, 0.65);
    Candidate.Radius := Candidate.Radius * 0.72;
    if CourseClear(Candidate, Plan, Bounds, Index) then
    begin
      Leg := Candidate;
      Exit;
    end;
  end;
  // 高さの足りない場所では隣の装置を貫くコースを避け、通れる勾配に切り替える。
  for Grade in Grades do
  begin
    SetRail(Candidate, Grade, Max(0.0, (Candidate.Heading * Incoming.X + Grade * Incoming.Y) / (1 + Sqr(Grade))));
    if not CourseClear(Candidate, Plan, Bounds, Index) then Continue;
    Candidate.ArcClock := nil;
    Leg := Candidate;
    Device := mdCatch;
    if Plan.Legs[Index - 1].Motion = mmRail then Device := mdGate;
    Exit;
  end;
end;

procedure LayCourse(Plan: TMarblePlan; const DisabledLifts, DisabledJunctions: TArray<Boolean>;
  const Cancel: TFunc<Boolean>);
var I, Heading, Part: Integer; Next, Previous: TMarbleLeg; P, Incoming: TBallPoint; Cue: TMarbleCue;
  Bounds: TArray<TMarbleSection>;
begin
  if Plan.Version = 1 then
  begin
    LayLegacyCourse(Plan);
    Exit;
  end;
  Plan.EndTime := Plan.Duration;
  if Length(Plan.Cues) = 0 then Exit;
  SetLength(Plan.Legs, Length(Plan.Cues) + 1);
  SetLength(Bounds, Length(Plan.Legs));
  Plan.Legs[0].Start := Max(0.0, Plan.Cues[0].Time - 0.65);
  Plan.Legs[0].Finish := Plan.Cues[0].Time;
  Plan.Legs[0].Origin := BallPoint(0, 0.4);
  Plan.Legs[0].Heading := 1;
  SetRail(Plan.Legs[0], -0.19, 2.65);
  Bounds[0] := MotionBounds(Plan.Legs[0]);
  Heading := 1;
  for I := 0 to High(Plan.Cues) do
  begin
    if Assigned(Cancel) and Cancel() then Abort;
    Next := Default(TMarbleLeg);
    Cue := Plan.Cues[I];
    Cue.SharedBeat := Default(TMarbleBeat);
    Cue.Slope := 0;
    Previous := Plan.Legs[I];
    Next.Start := Cue.Time;
    P := Previous.Position(Cue.Time);
    Incoming := Previous.Velocity(Cue.Time);
    Next.Origin := P;
    Next.Heading := Heading;
    if I = High(Plan.Cues) then
    begin
      Cue.Device := mdGoal;
      Next.Motion := mmSettle;
      Next.Finish := Next.Start + GoalTime;
      Plan.EndTime := Max(Plan.Duration, Next.Finish);
    end
    else
    begin
      Next.Finish := Plan.Cues[I + 1].Time;
      Part := CoursePart(Plan.Version, I);
      if (Plan.Version >= 8) and (Part = 2) and (Cue.RelayBeat.Time > 0) and
        (Plan.Cues[I + 1].RelayBeat.Time > 0) and (Previous.Motion = mmRail) then
      begin
        // 落下口と、主球が渡り終えるまでのレールを置く余裕を取る。
        SetRail(Next, -0.34, Max(0.0, (Heading * Incoming.X - 0.34 * Incoming.Y) / (1 + Sqr(0.34))));
        Cue.Device := mdGate;
      end
      else if (Plan.Version >= 9) and (Part in [4, 5, 6]) and (Cue.RelayBeat.Time > 0) and
        (Previous.Motion = mmRail) then
      begin
        SetRail(Next, Previous.Grade, Heading * Incoming.X);
        Cue.Device := mdGate;
      end
      else if PassSlot(Plan.Version, I) and (Cue.RelayBeat.Time > 0) then
      begin
        if I mod 20 = 7 then
        begin
          Next.Motion := mmCarry;
          Next.Travel := BallPoint(Heading * 0.42, -0.86);
          Cue.Device := mdShuttle;
        end
        else
        begin
          SetRail(Next, Previous.Grade, Max(0.0, Heading * Incoming.X));
          Cue.Device := mdGate;
          if Previous.Rollout then Cue.Device := mdCatch;
        end;
      end
      else if (Plan.Version >= 10) and (I mod 20 = 10) and (Plan.Cues[I - 1].RelayBeat.Time > 0) then
      begin
        if CounterSlot(Plan.Version, I) and (Cue.RelayBeat.Time > 0) then
        begin
          SetRail(Next, -0.42, Max(0.0, (Heading * Incoming.X - 0.42 * Incoming.Y) / (1 + Sqr(0.42))));
          Cue.Device := mdGate;
        end
        else
        begin
          Next.Motion := mmCarry;
          Next.Travel := BallPoint(0, 0.65);
          Cue.Device := mdLift;
        end;
      end
      else if CounterSlot(Plan.Version, I) and (Cue.RelayBeat.Time > 0) and (Previous.Motion = mmRail) then
      begin
        SetRail(Next, Previous.Grade, Max(0.0, Heading * Incoming.X));
        Cue.Device := mdGate;
      end
      else if SeesawSlot(Plan.Version, I) and (I mod 20 = 13) and (Cue.RelayBeat.Time > 0) and
        (Plan.Cues[I + 1].RelayBeat.Time > 0) and FitMainBoard(Next, Previous, Incoming) then
      begin
        Cue.Device := mdSeesaw;
        if (Plan.Version >= 14) and not DisabledLifts[I] then
          FitMainWeightLift(Next, Cue.RelayBeat.Time, Plan.Version >= 16);
      end
      else if SeesawSlot(Plan.Version, I) and (Cue.RelayBeat.Time > 0) and (Previous.Motion = mmSeesaw) then
      begin
        SetRail(Next, Previous.Grade, Max(0.0, Heading * Incoming.X));
        Cue.Device := mdGate;
        if Previous.HasWeightLift then
        begin
          // リフトが上がる間、固定レールは球の外側に離しておく。
          Next.EntryGap := Max(0.0, Previous.WeightLift.Ramp - Heading * (Next.Origin.X - Previous.WeightLift.Load.X));
          if (Plan.Version >= 16) and not DisabledJunctions[I] then FitMainJunction(Next, Cue.RelayBeat.Time);
        end;
      end
      else
      begin
        if (Part in [2, 3]) and (Cue.RelayBeat.Time > 0) then Part := 4;
        Cue.Device := PrepareLeg(Next, Previous, Incoming, Part);
      end;
      if Plan.Version >= 3 then AddRollout(Next);
      if (Cue.Device = mdShuttle) and (Next.Travel.Y < 0) then
      begin
        Next.Grade := -0.30;
        Next.Terminal := RailTerminalFor(Next.Grade, Next.Drag);
      end;
      ClearNearbyRails(Next, Cue.Device, Plan, Bounds, I + 1, Incoming);
    end;
    Cue.Center := P;
    Cue.Heading := Heading;
    if Cue.Device in [mdGate, mdChute] then
      Cue.Surface := BallPoint(P.X + Heading * MarbleRadius, P.Y)
    else
    begin
      if Next.Motion = mmRail then Cue.Slope := Next.RailSlope
      else if Previous.Motion = mmRail then Cue.Slope := Previous.RailSlope;
      Cue.Surface := MarbleRailSurface(P, Cue.Slope);
    end;
    Plan.Cues[I] := Cue;
    Plan.Legs[I + 1] := Next;
    Bounds[I + 1] := MotionBounds(Next);
    if Next.Motion = mmBend then Heading := -Heading;
  end;
end;

function RailTimeAtX(const Leg: TMarbleLeg; X: Double): Double;
var L, R, M: Double; I: Integer;
begin
  L := Leg.Start;
  R := Leg.Finish;
  for I := 0 to 23 do
  begin
    M := (L + R) * 0.5;
    if Leg.Heading * (Leg.Position(M).X - X) < 0 then L := M else R := M;
  end;
  Result := (L + R) * 0.5;
end;

procedure PlaceShutter(var Link: TMarbleLink; const Leg: TMarbleLeg; Offset: Double);
var X, CenterY: Double;
begin
  X := Leg.Origin.X + Leg.Heading * Offset;
  CenterY := Leg.Origin.Y + Leg.RailSlope * (X - Leg.Origin.X);
  Link.Kind := mlShutter;
  Link.Receiver := BallPoint(X, CenterY - MarbleRadius * Hypot(1, Leg.RailSlope));
  Link.Deadline := RailTimeAtX(Leg, X - Leg.Heading * (MarbleRadius + 0.052));
end;

function ScheduleLink(var Link: TMarbleLink; Contact: Double): Boolean;
var Available: Double;
begin
  Available := Link.Deadline - Contact;
  Link.Pull := Contact + Min(0.045, Available * 0.24);
  Link.Ready := Contact + Min(0.22, Available - ArrivalMargin);
  Result := Link.Ready - Link.Pull >= 0.055;
end;

function FitAuxiliary(var Bridge: TMarbleBridge; Heading: Integer; GateReady, StrikeAt: Double): Boolean;
var Aux: TMarbleAuxiliary; Direction: TBallPoint; TravelTime, Distance: Double;
begin
  Aux := Default(TMarbleAuxiliary);
  Aux.Release := GateReady + TriggerDelay;
  TravelTime := Min(0.43, Bridge.Deadline - Aux.Release - (TriggerDelay + 0.082 + ArrivalMargin));
  Result := TravelTime >= 0.265;
  if StrikeAt > 0 then
  begin
    TravelTime := StrikeAt - Aux.Release;
    Result := InRange(TravelTime, 0.23, 0.55) and
      (StrikeAt + TriggerDelay + 0.082 + ArrivalMargin <= Bridge.Deadline);
  end;
  if not Result then Exit;
  Aux.Strike := Aux.Release + TravelTime;
  if StrikeAt > 0 then Aux.Strike := StrikeAt;
  Direction := BallUnit(BallPoint(Heading, -0.95));
  // 小球も傾斜に沿って静止から加速し、受け側のレバーまで転がる。
  Distance := 0.5 * RollingFactor * MarbleGravity * Abs(Direction.Y) * Sqr(TravelTime);
  Aux.Receiver := BallAdd(Bridge.Hinge, BallPoint(-Heading * 0.08, 0.92));
  if StrikeAt > 0 then Aux.Receiver.Y := Aux.Receiver.Y + 0.23;
  Aux.Origin := BallSub(Aux.Receiver, BallScale(Direction, Distance));
  Bridge.Auxiliary := Aux;
  Bridge.Pull := Aux.Strike + TriggerDelay;
end;

function FitBridge(var Leg: TMarbleLeg; var Link: TMarbleLink; Contact: Double;
  AuxiliaryRunout: Double = 0; StrikeAt: Double = 0): Boolean;
var A, B: TBallPoint; NewLink: TMarbleLink; Bridge: TMarbleBridge;
  Span, GateOffset, EntryOffset, Gap: Double;
begin
  Result := False;
  if Leg.Bridge.Active then Exit;
  Leg.RailSupport(A, B);
  Span := Abs(B.X - A.X);
  GateOffset := Min(0.79, Span * 0.44);
  EntryOffset := Min(1.28, Span * 0.70);
  Gap := Min(0.44, Span - EntryOffset - 0.035);
  if AuxiliaryRunout > 0 then
  begin
    GateOffset := Min(GateOffset, Max(0.46,
      Leg.Heading * (Leg.Position(Contact + 0.095).X - Leg.Origin.X) + MarbleRadius + 0.052));
    Gap := Min(0.44, 0.29 + AuxiliaryRunout);
    EntryOffset := Min(2.65, Span - Gap - AuxiliaryRunout);
  end;
  if (GateOffset < 0.44) or (Gap < 0.265) then Exit;

  NewLink := Link;
  Bridge := Default(TMarbleBridge);
  PlaceShutter(NewLink, Leg, GateOffset);
  Bridge.Entry := BallAdd(A, BallPoint(Leg.Heading * EntryOffset, Leg.Grade * EntryOffset));
  Bridge.Hinge := BallAdd(Bridge.Entry, BallPoint(Leg.Heading * Gap, Leg.Grade * Gap));
  if Leg.Heading * (Bridge.Entry.X - NewLink.Receiver.X) < 0.17 then Exit;
  if not ScheduleLink(NewLink, Contact) then Exit;

  // シャッターが上端の留め金を外してから、受け皿が次のレールにそろう。
  Bridge.Pull := NewLink.Ready + TriggerDelay;
  Bridge.Deadline := RailTimeAtX(Leg, Bridge.Entry.X - Leg.Heading * (MarbleRadius + 0.026));
  if (AuxiliaryRunout > 0) and not FitAuxiliary(Bridge, Leg.Heading, NewLink.Ready, StrikeAt) then Exit;
  Bridge.Ready := Min(Bridge.Pull + 0.19, Bridge.Deadline - ArrivalMargin);
  if Bridge.Ready - Bridge.Pull < 0.065 then Exit;
  Leg.Bridge := Bridge;
  Link := NewLink;
  Result := True;
end;

function FlightClearsRail(const Aux: TMarbleAuxiliary; const Rail: TMarbleLeg; Start, Finish: Double): Boolean;
var A, B: TBallPoint;

  function ClearsSegment(A, B: TBallPoint): Boolean;
  const Samples = 24;
  var I: Integer; Segment, Offset: TBallPoint; U, Length2: Double;
  begin
    A.Y := A.Y - 0.09;
    B.Y := B.Y - 0.09;
    Segment := BallSub(B, A);
    Length2 := Max(1E-12, BallDot(Segment, Segment));
    for I := 0 to Samples do
    begin
      Offset := BallSub(Aux.Position(Start + (Finish - Start) * I / Samples), A);
      U := EnsureRange(BallDot(Offset, Segment) / Length2, 0.0, 1.0);
      if BallLength(BallSub(Offset, BallScale(Segment, U))) < MarbleAuxRadius + 0.09 then Exit(False);
    end;
    Result := True;
  end;

begin
  Rail.RailSupport(A, B);
  if not ClearsSegment(A, B) then Exit(False);
  if Rail.Junction.Active then
  begin
    Rail.Junction.Spur(A, B, Rail.Heading);
    if not ClearsSegment(A, B) then Exit(False);
    Rail.BranchRailSupport(A, B);
  end
  else if not Rail.HasWeightLift or not Rail.LiftRailSupport(A, B) then Exit(True);
  Result := ClearsSegment(A, B);
end;

function DuetClearsCourse(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary;
  const Tail: TBallPoint): Boolean;
const Clearance = MarbleRadius + MarbleAuxRadius + 0.06;
var I: Integer; Box: TMarbleSection; Left, Right: Double; UpperEnd, LowerEnd: TBallPoint;
begin
  Left := Min(Aux.Origin.X, Tail.X) - Clearance;
  Right := Max(Aux.Origin.X, Tail.X) + Clearance;
  UpperEnd := Tail;
  LowerEnd := Tail;
  if Aux.Crossover then UpperEnd := Aux.DropOrigin;
  if Aux.Merge.Active then LowerEnd := Aux.Merge.LaunchPoint;
  for I := Max(0, Index - 32) to Min(High(Plan.Legs), Index + 32) do
  begin
    Box := MotionBounds(Plan.Legs[I]);
    if (Box.Right < Left) or (Box.Left > Right) or (Box.Bottom > Aux.Origin.Y + Clearance) or
      (Box.Top < Min(Tail.Y, LowerEnd.Y) - Clearance) then Continue;
    if not PathClearsSegment(Plan.Legs[I], Aux.Origin, Aux.Receiver, Clearance) or
      not PathClearsSegment(Plan.Legs[I], Aux.Receiver, UpperEnd, Clearance) then Exit(False);
    if Aux.Crossover then
    begin
      if not PathClearsSegment(Plan.Legs[I], Aux.Landing, LowerEnd, Clearance) then Exit(False);
      // 次の主球レールは、落下口の両端を別途検査している。
      if (I <> Index + 1) and (Plan.Legs[I].Motion = mmRail) and
        not FlightClearsRail(Aux, Plan.Legs[I], Aux.DropStart, Aux.DropEnd) then Exit(False);
    end;
  end;
  Result := True;
end;

function GateDriver(const Cue: TMarbleCue): TBallPoint;
begin
  Result := BallPoint(Cue.Surface.X + Cue.Heading * 0.025, Cue.Center.Y + 0.48);
end;

function FitAuxiliaryGate(const Aux: TMarbleAuxiliary; const Cue: TMarbleCue;
  NextStrike: Double; out Link: TMarbleLink; BeforeDrop: Boolean = False): Boolean;
var P: TBallPoint; Grade: Double;
begin
  Result := False;
  if (Cue.Device <> mdGate) or (Cue.Time <= Aux.Strike) then Exit;
  Link := Default(TMarbleLink);
  Link.Kind := mlShutter;
  Link.Heading := Cue.Heading;
  Link.Driver := GateDriver(Cue);
  // 小球の前縁がゲートに届く時刻から、レール上での位置を決める。
  Link.Deadline := Cue.Time + Min(0.23, (NextStrike - Cue.Time) * 0.56);
  if BeforeDrop then Link.Deadline := Cue.Time + Min(0.105, (NextStrike - Cue.Time) * 0.40);
  P := Aux.Position(Link.Deadline);
  Grade := Aux.RailGrade(Link.Deadline);
  Link.Receiver := BallPoint(P.X + Cue.Heading * MarbleAuxGateNose,
    P.Y + Grade * MarbleAuxGateNose - MarbleAuxRadius * Hypot(1, Grade));
  Result := ScheduleLink(Link, Cue.Time);
  if BeforeDrop then Result := Result and
    (Cue.Heading * (Aux.DropOrigin.X - Link.Receiver.X) > MarbleAuxRadius + 0.035);
end;

function FitReplyBridge(const Leg: TMarbleLeg; Strike: Double; out Bridge: TMarbleBridge): Boolean;
const Span = 0.42;
var A, B: TBallPoint; Offset: Double;
begin
  Result := False;
  if Leg.Bridge.Active or (Strike <= Leg.Start) or (Strike >= Leg.Finish) then Exit;
  Leg.RailSupport(A, B);
  Offset := Min(Abs(B.X - A.X) - Span - 0.16,
    Leg.Heading * (Leg.Position(Strike + 0.23).X - A.X) + MarbleRadius + 0.026);
  if Offset < 0.40 then Exit;
  Bridge := Default(TMarbleBridge);
  Bridge.Entry := BallAdd(A, BallPoint(Leg.Heading * Offset, Leg.Grade * Offset));
  Bridge.Hinge := BallAdd(Bridge.Entry, BallPoint(Leg.Heading * Span, Leg.Grade * Span));
  Bridge.Pull := Strike + TriggerDelay;
  Bridge.Deadline := RailTimeAtX(Leg, Bridge.Entry.X - Leg.Heading * (MarbleRadius + 0.026));
  Bridge.Ready := Min(Bridge.Pull + 0.19, Bridge.Deadline - ArrivalMargin);
  Result := Bridge.Ready - Bridge.Pull >= 0.082;
end;

function DuetInView(Plan: TMarblePlan; const Aux: TMarbleAuxiliary; Start, Last: Double; Heading: Integer): Boolean;
var I, Samples: Integer; T, X: Double; P, Main, Camera, Tail: TBallPoint;
begin
  Tail := Aux.Position(Aux.Finish);
  Samples := 24;
  if Aux.Crossover then Samples := 48;
  if Aux.Merge.Pass.Active then Samples := Ceil((Last - Start) * 36);
  for I := 0 to Samples do
  begin
    T := Start + (Last - Start) * I / Samples;
    Camera := Plan.CameraTarget(T);
    P := Aux.Position(T);
    if (Abs(P.X - Camera.X) > 2.66) or not InRange(Camera.Y + 3.75 * 0.54 - P.Y, 0.21, 3.54) then Exit(False);
    Main := Plan.Position(T);
    if Aux.Crossover then
    begin
      if BallLength(BallSub(P, Main)) < MarbleRadius + MarbleAuxRadius + 0.06 then Exit(False);
      if Aux.Merge.Active then
      begin
        if (T >= Aux.DropEnd) and (T < Aux.Merge.Launch.Time) and (Main.Y - P.Y < 0.09) then Exit(False);
        if Aux.Merge.Pass.Counter.Active and (T >= Aux.Merge.Pass.Counter.Start) then
        begin
          if (T >= Aux.Merge.Pass.Counter.Rejoin.Start) and
            (not Aux.Merge.Pass.Counter.Seesaw.Active or (T < Aux.Merge.Pass.Counter.Seesaw.Board.Start)) and
            (Heading * (Main.X - P.X) < 0.33) then Exit(False);
        end
        else if Aux.Merge.Pass.Active and (T >= Aux.Merge.Pass.Fork.Time) then
        begin
          if (T >= Aux.Merge.Pass.Rejoin.Start) and (Heading * (P.X - Main.X) < 0.33) then Exit(False);
        end
        else if (T >= Aux.Merge.Join) and (Heading * (Main.X - P.X) < 0.36) then Exit(False);
      end
      else if (T >= Aux.DropEnd) and (Main.Y - P.Y < 0.32) then Exit(False);
    end
    else
    begin
      X := Heading * (Main.X - Aux.Receiver.X);
      if InRange(X, 0.0, Abs(Tail.X - Aux.Receiver.X)) and
        (Aux.Receiver.Y + Aux.RunGrade * X - Main.Y < 0.40) then Exit(False);
    end;
  end;
  Result := True;
end;

function FitDropGap(const Leg: TMarbleLeg; const Aux: TMarbleAuxiliary; out Bridge: TMarbleBridge): Boolean;
const EdgeClearance = MarbleAuxRadius + 0.045;
      AboveRail = MarbleAuxRadius + 0.05;
      BelowRail = -0.18 - MarbleAuxRadius - 0.045;
var A, B: TBallPoint; Height, FallSpeed, Offset, GapEnd: Double;
  function OffsetAtHeight(Y: Double): Double;
  var Age: Double;
  begin
    Age := (FallSpeed + Sqrt(Sqr(FallSpeed) + 2 * MarbleGravity * (Height - Y))) / MarbleGravity;
    Result := Leg.Heading * (Aux.DropOrigin.X + Aux.DropVelocity.X * Age - A.X);
  end;
begin
  Result := False;
  if Leg.Bridge.Active then Exit;
  Leg.RailSupport(A, B);
  Height := Aux.DropOrigin.Y - A.Y - Leg.RailSlope * (Aux.DropOrigin.X - A.X);
  FallSpeed := Aux.DropVelocity.Y - Leg.RailSlope * Aux.DropVelocity.X;
  if (Height < AboveRail) or (FallSpeed >= 0) or
    (Aux.Landing.Y - A.Y - Leg.RailSlope * (Aux.Landing.X - A.X) > -0.46) then Exit;
  // 落下がレールの厚みを通り抜ける範囲に、前後の球半径分を加えて切れ目を置く。
  Offset := OffsetAtHeight(AboveRail) - EdgeClearance;
  GapEnd := Max(Offset + 0.42, OffsetAtHeight(BelowRail) + EdgeClearance);
  if (Offset < 0.40) or (GapEnd > Abs(B.X - A.X) - 0.14) then Exit;
  Bridge := Default(TMarbleBridge);
  Bridge.Sliding := True;
  Bridge.Entry := BallAdd(A, BallPoint(Leg.Heading * Offset, Leg.Grade * Offset));
  Bridge.Hinge := BallAdd(A, BallPoint(Leg.Heading * GapEnd, Leg.Grade * GapEnd));
  Bridge.Pull := Aux.DropEnd + TriggerDelay;
  Bridge.Deadline := RailTimeAtX(Leg, Bridge.Entry.X - Leg.Heading * (MarbleRadius + 0.026));
  Bridge.Ready := Min(Bridge.Pull + 0.19, Bridge.Deadline - ArrivalMargin);
  Result := Bridge.Ready - Bridge.Pull >= 0.082;
end;

function FitCrossover(Plan: TMarblePlan; Index: Integer; const Leg: TMarbleLeg;
  var Aux: TMarbleAuxiliary; Last: Double; out Reply: TMarbleBridge): Boolean;
const Grades: array[0..2] of Double = (-0.78, -0.84, -0.70);
      Leads: array[0..3] of Double = (-0.24, -0.10, 0.10, -0.36);
      Raises: array[0..3] of Double = (0.68, 0.56, 0.80, 0.44);
var Trial: TMarbleAuxiliary; Incoming, Shift: TBallPoint;
  Grade, Lead, RaiseY, DropAt, Age, Speed, DownSpeed: Double; I: Integer;
begin
  Result := False;
  if Aux.SecondStrike.Time - Leg.Start < 0.42 then Exit;
  Incoming := BallScale(BallSub(Aux.Receiver, Aux.Origin), 2 / (Aux.Strike - Aux.Release));
  for Grade in Grades do
    for Lead in Leads do
      for RaiseY in Raises do
        for I := 0 to 10 do
        begin
          DropAt := Leg.Start + 0.188 + I * 0.012;
          Age := Aux.SecondStrike.Time - DropAt;
          if not InRange(Age, 0.24, 0.46) then Continue;
          Trial := Aux;
          Shift := BallPoint(Leg.Heading * Lead, RaiseY);
          Trial.Origin := BallAdd(Trial.Origin, Shift);
          Trial.Receiver := BallAdd(Trial.Receiver, Shift);
          Trial.RunGrade := Grade;
          Trial.RunSpeed := (Leg.Heading * Incoming.X + Grade * Incoming.Y) / (1 + Sqr(Grade));
          Trial.DropOrigin := Trial.Position(DropAt);
          Speed := RailTerminalFor(Grade, RailDrag);
          Speed := Speed + (Trial.RunSpeed - Speed) * Exp(-RailDrag * (DropAt - Aux.Strike));
          Trial.DropVelocity := BallPoint(Leg.Heading * Speed, Grade * Speed);
          Trial.DropStart := DropAt;
          Trial.DropEnd := Aux.SecondStrike.Time;
          Trial.Landing := BallAdd(Trial.DropOrigin, BallPoint(Trial.DropVelocity.X * Age,
            Trial.DropVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age)));
          DownSpeed := Trial.DropVelocity.Y - MarbleGravity * Age;
          Trial.LandingSpeed := (Speed + LowerGrade * DownSpeed) / (1 + Sqr(LowerGrade));
          if not FitDropGap(Leg, Trial, Reply) or
            not FitAuxiliaryGate(Trial, Plan.Cues[Index + 1], Trial.SecondStrike.Time, Trial.AuxGates[0], True) or
            not FitAuxiliaryGate(Trial, Plan.Cues[Index + 2], Trial.Bell.Time, Trial.AuxGates[1]) or
            not DuetClearsCourse(Plan, Index + 1, Trial, Trial.Position(Trial.Finish)) or
            not DuetInView(Plan, Trial, Plan.Cues[Index].Time, Last, Leg.Heading) then Continue;
          Aux := Trial;
          Exit(True);
        end;
end;

function FitReturnHatch(const Leg: TMarbleLeg; const Merge: TMarbleMerge; out Hatch: TMarbleBridge): Boolean;
const Below = -0.18 - MarbleAuxRadius - 0.025;
      Above = MarbleAuxRadius + 0.03;
      Edge = MarbleAuxRadius + 0.024;
var A, B: TBallPoint; Height, Rise, StartAge, EndAge, StartOffset, EndOffset: Double;
  function AgeAtHeight(Y: Double): Double;
  begin
    Result := (Rise - Sqrt(Sqr(Rise) - 2 * MarbleGravity * (Y - Height))) / MarbleGravity;
  end;
begin
  Result := False;
  if Leg.Bridge.Active then Exit;
  Leg.RailSupport(A, B);
  Height := Merge.LaunchPoint.Y - A.Y - Leg.RailSlope * (Merge.LaunchPoint.X - A.X);
  Rise := Merge.LaunchVelocity.Y - Leg.RailSlope * Merge.LaunchVelocity.X;
  if (Height >= Below) or (Rise <= 0) or (Sqr(Rise) <= 2 * MarbleGravity * (Above - Height)) then Exit;
  StartAge := AgeAtHeight(Below);
  EndAge := AgeAtHeight(Above);
  StartOffset := Leg.Heading * (Merge.LaunchPoint.X + Merge.LaunchVelocity.X * StartAge - A.X) - Edge;
  EndOffset := Leg.Heading * (Merge.LaunchPoint.X + Merge.LaunchVelocity.X * EndAge - A.X) + Edge;
  // 主球の後端が切れ目を抜けてから、戻り口の板を引く。
  if (StartOffset < 0.23) or
    (EndOffset > Leg.Heading * (Leg.Position(Leg.Finish).X - A.X) - MarbleRadius - 0.025) then Exit;
  Hatch := Default(TMarbleBridge);
  Hatch.Sliding := True;
  Hatch.Retracting := True;
  Hatch.Entry := BallAdd(A, BallPoint(Leg.Heading * StartOffset, Leg.Grade * StartOffset));
  Hatch.Hinge := BallAdd(A, BallPoint(Leg.Heading * EndOffset, Leg.Grade * EndOffset));
  Hatch.Pull := Leg.Finish + TriggerDelay;
  Hatch.Ready := Hatch.Pull + 0.16;
  Hatch.Deadline := Merge.Launch.Time + StartAge;
  Result := Hatch.Ready + ArrivalMargin < Hatch.Deadline;
end;

function ReturnFlightClearsCourse(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary): Boolean;
var I: Integer; Box: TMarbleSection; A, B: TBallPoint;
begin
  A := Aux.Merge.LaunchPoint;
  B := Aux.Merge.JoinPoint;
  for I := Max(0, Index - 24) to Min(High(Plan.Legs), Index + 32) do
  begin
    if (I >= Index + 3) and (I <= Index + 6) then Continue; // 戻り口と同じ直線は個別に検査済み。
    if Plan.Legs[I].Motion <> mmRail then Continue;
    Box := MotionBounds(Plan.Legs[I]);
    if (Box.Right < Min(A.X, B.X) - 0.2) or (Box.Left > Max(A.X, B.X) + 0.2) then Continue;
    if not FlightClearsRail(Aux, Plan.Legs[I], Aux.Merge.Launch.Time, Aux.Merge.Join) then Exit(False);
  end;
  Result := True;
end;

function FitMerge(Plan: TMarblePlan; Index: Integer; var Aux: TMarbleAuxiliary; out Hatch: TMarbleBridge): Boolean;
const Drags: array[0..5] of Double = (2.80, 2.90, 3.00, 2.70, 3.15, 2.55);
var Trial: TMarbleAuxiliary; Shared: TMarbleLeg; RailOffset, Delta, SecondPoint: TBallPoint;
  Drag, Flight, Delay, Last, MainTime, DT, Terminal, Prior, Projected: Double; I, J: Integer;
begin
  Result := False;
  if Index + 6 > High(Plan.Cues) then Exit;
  Shared := Plan.Legs[Index + 4];
  for I := Index + 3 to Index + 6 do
    if (Plan.Legs[I].Motion <> mmRail) or (Plan.Legs[I].Heading <> Shared.Heading) or
      (Abs(Plan.Legs[I].Grade - Shared.Grade) > 1E-9) then Exit;
  if (Plan.Cues[Index + 3].RelayBeat.Time = 0) or (Plan.Cues[Index + 4].RelayBeat.Time = 0) or
    (Plan.Cues[Index + 5].RelayBeat.Time = 0) then Exit;
  Last := Plan.Cues[Index + 6].Time;
  RailOffset := BallScale(BallUnit(BallPoint(-Shared.RailSlope, 1)), MarbleAuxRadius - MarbleRadius);
  Terminal := RailTerminalFor(Shared.Grade, RailDrag);
  for J := 0 to 9 do
    for Drag in Drags do
    begin
      Trial := Aux;
      Trial.Merge.Launch := Plan.Cues[Index + 3].RelayBeat;
      Trial.Merge.Taps[0] := Plan.Cues[Index + 4].RelayBeat;
      Trial.Merge.Taps[1] := Plan.Cues[Index + 5].RelayBeat;
      Trial.Merge.Grade := Shared.Grade;
      Trial.Merge.LowerDrag := Drag;
      Trial.Finish := Min(Last, Trial.Merge.Taps[1].Time + 0.34);
      if Trial.Finish - Trial.Merge.Taps[1].Time < DuetBrakeTime then Exit;
      Trial.Merge.LaunchPoint := Trial.Position(Trial.Merge.Launch.Time);
      Flight := 0.48 + 0.02 * J;
      Trial.Merge.Join := Trial.Merge.Launch.Time + Flight;
      Delay := Trial.Merge.Taps[0].Time - Shared.Finish;
      MainTime := Trial.Merge.Join - Delay;
      if not InRange(MainTime, Shared.Start + 0.18, Shared.Finish - 0.06) then Continue;
      Trial.Merge.JoinPoint := BallAdd(Shared.Position(MainTime), RailOffset);
      Trial.Merge.JoinSpeed := Shared.Heading * Shared.Velocity(MainTime).X;
      Delta := BallSub(Trial.Merge.JoinPoint, Trial.Merge.LaunchPoint);
      Trial.Merge.LaunchVelocity := BallPoint(Delta.X / Flight, Delta.Y / Flight + 0.5 * MarbleGravity * Flight);
      if (Shared.Heading * Trial.Merge.LaunchVelocity.X < 0.65) or (Trial.Merge.LaunchVelocity.Y <= 0) then Continue;
      Projected := (Shared.Heading * Trial.Merge.LaunchVelocity.X + Shared.Grade *
        (Trial.Merge.LaunchVelocity.Y - MarbleGravity * Flight)) / (1 + Sqr(Shared.Grade));
      // 合流の受けが跳ね返りを吸収する。接線方向には勢いを残す。
      if not InRange(Trial.Merge.JoinSpeed, Projected * 0.45, Projected) then Continue;
      Trial.Merge.TapPoint := BallAdd(Plan.Cues[Index + 4].Center, RailOffset);
      SecondPoint := BallAdd(Plan.Cues[Index + 5].Center, RailOffset);
      DT := Trial.Merge.Taps[1].Time - Trial.Merge.Taps[0].Time;
      Trial.Merge.TapSpeed := Terminal + (Shared.Heading * (SecondPoint.X - Trial.Merge.TapPoint.X) - Terminal * DT) *
        RailDrag / (1 - Exp(-RailDrag * DT));
      Prior := Shared.Heading * Shared.Velocity(Shared.Finish).X;
      if not InRange(Trial.Merge.TapSpeed, Prior * 0.80, Prior * 1.20) then Continue;
      if not FitReturnHatch(Plan.Legs[Index + 3], Trial.Merge, Hatch) or
        not FitAuxiliaryGate(Trial, Plan.Cues[Index + 2], Trial.Bell.Time, Trial.AuxGates[1]) or
        not DuetClearsCourse(Plan, Index + 1, Trial, Trial.Position(Trial.Finish)) or
        not ReturnFlightClearsCourse(Plan, Index, Trial) or
        not DuetInView(Plan, Trial, Plan.Cues[Index].Time, Last, Shared.Heading) then Continue;
      Aux := Trial;
      Exit(True);
    end;
end;

function RollingSpeedFor(Grade, Distance, Age: Double): Double;
var Terminal: Double;
begin
  Terminal := RailTerminalFor(Grade, RailDrag);
  Result := Terminal + (Distance - Terminal * Age) * RailDrag / (1 - Exp(-RailDrag * Age));
end;

function RollingSpeedAt(Speed, Grade, Age: Double): Double;
var Terminal: Double;
begin
  Terminal := RailTerminalFor(Grade, RailDrag);
  Result := Terminal + (Speed - Terminal) * Exp(-RailDrag * Age);
end;

function FitBypass(const Shared: TMarbleLeg; Lead, EntrySpeed: Double; const Offset: TBallPoint;
  var Pass: TMarblePass): Boolean;
var L, R, T, Residual, Projected: Double; I: Integer;
  function DistanceError(Time: Double): Double;
  var Delta: TBallPoint; D: Double;
  begin
    Pass.Rejoin.Origin := BallAdd(Shared.Position(Time + Lead), Offset);
    Delta := BallSub(Pass.Rejoin.Origin, Pass.Bypass.Origin);
    D := Shared.Heading * Delta.X;
    Pass.Bypass.Grade := Delta.Y / D;
    Pass.Bypass.Speed := EntrySpeed * (1 + Pass.Approach.Grade * Pass.Bypass.Grade) / (1 + Sqr(Pass.Bypass.Grade));
    Result := RailDistance(Pass.Bypass.Speed, RailTerminalFor(Pass.Bypass.Grade, RailDrag), RailDrag, Time - Pass.Fork.Time) - D;
  end;
begin
  Result := False;
  L := Max(Pass.Fork.Time + 0.26, Shared.Start + 0.10 - Lead);
  R := Min(Pass.Fork.Time + 0.92, Pass.Taps[0].Time - 0.12);
  if R <= L then Exit;
  if Shared.Heading * (BallAdd(Shared.Position(L + Lead), Offset).X - Pass.Bypass.Origin.X) < 0.48 then Exit;
  if (DistanceError(L) >= 0) or (DistanceError(R) <= 0) then Exit;
  for I := 0 to 34 do
  begin
    T := (L + R) * 0.5;
    if DistanceError(T) < 0 then L := T else R := T;
  end;
  Pass.Rejoin.Start := (L + R) * 0.5;
  Residual := DistanceError(Pass.Rejoin.Start);
  if (Abs(Residual) > 1E-8) or not InRange(Pass.Bypass.Grade, -1.15, -0.36) then Exit;
  Pass.Rejoin.Grade := Shared.Grade;
  Pass.Rejoin.Speed := Shared.Heading * Shared.Velocity(Pass.Rejoin.Start + Lead).X;
  Projected := RollingSpeedAt(Pass.Bypass.Speed, Pass.Bypass.Grade, Pass.Rejoin.Start - Pass.Fork.Time) *
    (1 + Pass.Bypass.Grade * Shared.Grade) / (1 + Sqr(Shared.Grade));
  Result := InRange(Pass.Rejoin.Speed, Projected * 0.40, Projected);
end;

function FitPass(Plan: TMarblePlan; Index: Integer; var Aux: TMarbleAuxiliary; ContinueWithCounter: Boolean = False): Boolean;
var Trial: TMarbleAuxiliary; Shared, Carrier: TMarbleLeg; P: TMarblePass; Offset, Main, Small: TBallPoint;
  Lead, Prior, Speed, Last, T: Double; H, I: Integer;
begin
  Result := False;
  if Index + 9 > High(Plan.Cues) then Exit;
  Carrier := Plan.Legs[Index + 7];
  Shared := Plan.Legs[Index + 8];
  H := Shared.Heading;
  if not Carrier.Rollout or (Carrier.Travel.Y >= -0.45) or (Shared.Motion <> mmRail) or
    (Plan.Legs[Index + 9].Motion <> mmRail) or (Plan.Legs[Index + 9].Heading <> H) or
    (Plan.Legs[Index + 9].Grade <> Shared.Grade) then Exit;
  P := Default(TMarblePass);
  P.Fork := Plan.Cues[Index + 6].RelayBeat;
  P.Taps[0] := Plan.Cues[Index + 7].RelayBeat;
  P.Taps[1] := Plan.Cues[Index + 8].RelayBeat;
  if (P.Fork.Time <= Carrier.Start + 0.32) or (P.Taps[0].Time = 0) or (P.Taps[1].Time = 0) then Exit;
  P.SwitchPull := Carrier.Start + 0.15;
  P.SwitchReady := Carrier.Start + 0.30;
  P.Approach.Start := Aux.Merge.Taps[1].Time;
  P.Approach.Grade := Aux.Merge.Grade;
  P.Approach.Origin := Aux.Position(P.Approach.Start);
  P.Bypass.Start := P.Fork.Time;
  Offset := BallScale(BallUnit(BallPoint(-H * P.Approach.Grade, 1)), MarbleAuxRadius - MarbleRadius);
  P.Bypass.Origin := BallAdd(Carrier.Origin, Offset);
  Prior := RollingSpeedAt(Aux.Merge.TapSpeed, P.Approach.Grade, P.Approach.Start - Aux.Merge.Taps[0].Time);
  P.Approach.Speed := RollingSpeedFor(P.Approach.Grade, H * (P.Bypass.Origin.X - P.Approach.Origin.X), P.Fork.Time - P.Approach.Start);
  if not InRange(P.Approach.Speed, 0.80 * Prior, 1.20 * Prior) then Exit;
  Speed := RollingSpeedAt(P.Approach.Speed, P.Approach.Grade, P.Fork.Time - P.Approach.Start);
  Lead := Shared.Finish - P.Taps[0].Time;
  Offset := BallScale(BallUnit(BallPoint(-Shared.RailSlope, 1)), MarbleAuxRadius - MarbleRadius);
  if not FitBypass(Shared, Lead, Speed, Offset, P) then Exit;

  P.LastRun.Start := P.Taps[0].Time;
  P.LastRun.Grade := Shared.Grade;
  P.LastRun.Origin := BallAdd(Plan.Cues[Index + 8].Center, Offset);
  P.ExitOrigin := BallAdd(Plan.Cues[Index + 9].Center, Offset);
  Prior := H * Shared.Velocity(Shared.Finish).X;
  P.LastRun.Speed := RollingSpeedFor(Shared.Grade, H * (P.ExitOrigin.X - P.LastRun.Origin.X), P.Taps[1].Time - P.Taps[0].Time);
  if not InRange(P.LastRun.Speed, 0.80 * Prior, 1.20 * Prior) then Exit;
  Speed := RollingSpeedAt(P.LastRun.Speed, Shared.Grade, P.Taps[1].Time - P.Taps[0].Time);
  P.ExitVelocity := BallPoint(H * Speed, Shared.Grade * Speed);
  Trial := Aux;
  Trial.Merge.Pass := P;
  Last := Plan.Cues[Index + 9].Time;
  Trial.Finish := Min(Last, P.Taps[1].Time + 0.31);
  if ContinueWithCounter then Last := P.Taps[1].Time;
  if (Trial.Finish - P.Taps[1].Time < 0.20) or
    not DuetInView(Plan, Trial, Plan.Cues[Index].Time, Last, H) then Exit;
  for I := Max(0, Index - 24) to Min(High(Plan.Legs), Index + 32) do
    if ((I < Index + 6) or (I > Index + 9)) and
      not PathClearsSegment(Plan.Legs[I], P.Bypass.Origin, P.Rejoin.Origin, MarbleRadius + MarbleAuxRadius + 0.04) then Exit;
  if not ContinueWithCounter then
    for I := 0 to 24 do
    begin
      T := P.Taps[1].Time + (Last + 0.75 - P.Taps[1].Time) * I / 24;
      Main := Plan.Position(T);
      Small := Trial.Position(T);
      if BallLength(BallSub(Main, Small)) < MarbleRadius + MarbleAuxRadius + 0.08 then Exit;
    end;
  Aux := Trial;
  Result := True;
end;

function CounterRouteClear(Plan: TMarblePlan; Index: Integer; const Counter: TMarbleCounter;
  Finish: Double; Heading: Integer): Boolean;
const Samples = 72;
var I, J: Integer; T, Gap, PreviousGap, Progress: Double; Small, Main, A, B: TBallPoint; Passed: Boolean;
begin
  Passed := False;
  Small := Counter.Entry;
  PreviousGap := Heading * (Plan.Position(Counter.Start).X - Small.X);
  if PreviousGap > -0.33 then Exit(False);
  for I := 1 to Samples do
  begin
    T := Counter.Start + (Counter.Rejoin.Start - Counter.Start) * I / Samples;
    A := Counter.Position(T, Finish, Heading);
    Main := Plan.Position(T);
    Progress := Heading * (A.X - Small.X);
    if Progress < 0.10 * (Counter.Rejoin.Start - Counter.Start) / Samples then Exit(False);
    Gap := Heading * (Main.X - A.X);
    if (PreviousGap < 0) and (Gap >= 0) then
    begin
      if (T >= Counter.DetourBeat.Time) or (Main.Y - A.Y < MarbleRadius + MarbleAuxRadius + 0.09) then Exit(False);
      Passed := True;
    end;
    PreviousGap := Gap;
    Small := A;
  end;
  if not Passed or (PreviousGap < 0.36) then Exit(False);
  A := Counter.Entry;
  for J := 1 to 12 do
  begin
    B := Counter.Guide(J / 12);
    for I := Max(0, Index - 20) to Min(High(Plan.Legs), Index + 32) do
      if ((I < Index + 9) or (I > Index + 12)) and
        not PathClearsSegment(Plan.Legs[I], A, B, MarbleRadius + MarbleAuxRadius + 0.04) then Exit(False);
    A := B;
  end;
  Result := True;
end;

function FitInterlock(const Cue: TMarbleCue; const Rail: TMarbleLeg; const Counter: TMarbleCounter;
  Finish: Double; out Interlock: TMarbleInterlock): Boolean;
const SmallNose = MarbleAuxRadius + 0.052;
var Offset, H, L, R, M, X: Double; P: TBallPoint; I: Integer;
begin
  Result := False;
  Interlock := Default(TMarbleInterlock);
  H := Rail.Heading;
  // 上段は主球の前縁だけが届く高さ、下段は小球が通るカーブにレバーを置く。
  Interlock.Inputs[0].Beat.Time := Cue.Time;
  Interlock.Inputs[0].Beat.Power := Cue.Power;
  Interlock.Inputs[0].Contact := BallAdd(Cue.Center, BallPoint(H * 0.143, 0.056));
  Interlock.Inputs[0].Pivot := BallAdd(Interlock.Inputs[0].Contact, BallPoint(H * 0.10, 0.20));
  Interlock.Inputs[1].Beat := Counter.DetourBeat;
  P := Counter.Position(Counter.DetourBeat.Time, Finish, Rail.Heading);
  Interlock.Inputs[1].Contact := BallAdd(P, BallPoint(H * 0.070, 0.051));
  Interlock.Inputs[1].Pivot := BallAdd(Interlock.Inputs[1].Contact, BallPoint(H * 0.10, 0.18));
  for I := 0 to 16 do
  begin
    P := Counter.Position(Counter.Start + (Cue.Time - Counter.Start) * I / 16, Finish, Rail.Heading);
    if BallLength(BallSub(P, Interlock.Inputs[0].Contact)) < MarbleAuxRadius + 0.015 then Exit;
  end;
  if not PathClearsSegment(Rail, Interlock.Inputs[1].Contact, Interlock.Inputs[1].Pivot, MarbleRadius + 0.015) then Exit;

  Offset := Min(H * (Rail.Position(Rail.Finish).X - Rail.Origin.X) - 0.34,
    H * (Rail.Position(Counter.DetourBeat.Time + 0.29).X - Rail.Origin.X) + MarbleRadius + 0.052);
  Interlock.Gate.Heading := Rail.Heading;
  PlaceShutter(Interlock.Gate, Rail, Offset);
  X := Interlock.Gate.Receiver.X - H * SmallNose;
  if (H * (X - Counter.Rejoin.Origin.X) < 0.20) or
    (H * (Interlock.Gate.Receiver.X - Counter.Gate.Receiver.X) < 0.70) or
    (H * (Counter.LastRun.Origin.X - X) <= 0) then Exit;

  L := Counter.Rejoin.Start;
  R := Counter.Taps[0].Time;
  for I := 0 to 23 do
  begin
    M := (L + R) * 0.5;
    if H * (Counter.Position(M, Finish, Rail.Heading).X - X) < 0 then L := M else R := M;
  end;
  Interlock.SmallDeadline := (L + R) * 0.5;
  Interlock.Gate.Pull := Max(Interlock.Inputs[0].SeatedAt, Interlock.Inputs[1].SeatedAt) + TriggerDelay;
  Interlock.Gate.Ready := Min(Interlock.Gate.Pull + 0.18,
    Min(Interlock.Gate.Deadline, Interlock.SmallDeadline) - ArrivalMargin);
  Result := Interlock.Gate.Ready - Interlock.Gate.Pull >= 0.080;
end;

function FitCounter(Plan: TMarblePlan; Index: Integer; var Aux: TMarbleAuxiliary;
  RequireInterlock: Boolean = False; ContinueToSeesaw: Boolean = False): Boolean;
const Depths: array[0..2] of Double = (0.62, 0.74, 0.53);
      EntryFactors: array[0..2] of Double = (0.50, 0.60, 0.42);
var Trial: TMarbleAuxiliary; Shared, Following: TMarbleLeg; C: TMarbleCounter; Interlock: TMarbleInterlock; Offset, Target: TBallPoint;
  Delay, MainTime, Last, Prior, Depth, EntryFactor: Double; H, I: Integer; StopBeforeBoard: Boolean;
begin
  Result := False;
  if Index + 12 > High(Plan.Cues) then Exit;
  Shared := Plan.Legs[Index + 10];
  H := Shared.Heading;
  for I := Index + 10 to Index + 12 do
    if (Plan.Legs[I].Motion <> mmRail) or (Plan.Legs[I].Heading <> H) or
      (Plan.Legs[I].Grade <> Shared.Grade) then Exit;
  C := Default(TMarbleCounter);
  C.Start := Aux.Merge.Pass.Taps[1].Time;
  C.Entry := Aux.Merge.Pass.ExitOrigin;
  C.DetourBeat := Plan.Cues[Index + 9].RelayBeat;
  C.Taps[0] := Plan.Cues[Index + 10].RelayBeat;
  C.Taps[1] := Plan.Cues[Index + 11].RelayBeat;
  Last := Plan.Cues[Index + 12].Time;
  if (C.Start >= Shared.Start) or (C.DetourBeat.Time <= Shared.Start) or
    (C.Taps[0].Time <= Shared.Finish) or (C.Taps[1].Time <= Plan.Cues[Index + 11].Time) or
    (Last - C.Taps[1].Time < DuetBrakeTime) then Exit;
  C.Gate.Heading := H;
  C.Gate.Driver := BallAdd(C.Entry, BallPoint(H * 0.17, 0.23));
  PlaceShutter(C.Gate, Shared, 0.56);
  if not ScheduleLink(C.Gate, C.Start) or (C.Gate.Ready >= Shared.Start) then Exit;
  Offset := BallScale(BallUnit(BallPoint(-Shared.RailSlope, 1)), MarbleAuxRadius - MarbleRadius);
  Delay := C.Taps[0].Time - Shared.Finish;
  C.LastRun.Start := C.Taps[0].Time;
  C.LastRun.Grade := Shared.Grade;
  C.LastRun.Origin := BallAdd(Plan.Cues[Index + 10].Center, Offset);
  Target := BallAdd(Plan.Cues[Index + 11].Center, Offset);
  C.LastRun.Speed := RollingSpeedFor(Shared.Grade, H * (Target.X - C.LastRun.Origin.X), C.Taps[1].Time - C.Taps[0].Time);
  Prior := H * Shared.Velocity(Shared.Finish).X;
  if not InRange(C.LastRun.Speed, 0.80 * Prior, 1.20 * Prior) then Exit;
  Trial := Aux;
  Trial.Finish := Min(Last, C.Taps[1].Time + 0.55);
  Following := Plan.Legs[Index + 13];
  StopBeforeBoard := (Following.Motion = mmSeesaw) and not ContinueToSeesaw;
  if StopBeforeBoard then Trial.Finish := Min(Trial.Finish, C.Taps[1].Time + 0.22);
  for I := 0 to 10 do
  begin
    C.Rejoin.Start := Max(C.DetourBeat.Time + 0.12, Shared.Finish + 0.075) + I * 0.025;
    MainTime := C.Rejoin.Start - Delay;
    if (C.Rejoin.Start > C.Taps[0].Time - 0.12) or not InRange(MainTime, Shared.Start + 0.24, Shared.Finish - 0.12) then Continue;
    C.Rejoin.Origin := BallAdd(Shared.Position(MainTime), Offset);
    C.Rejoin.Grade := Shared.Grade;
    C.Rejoin.Speed := H * Shared.Velocity(MainTime).X;
    if H * (C.Rejoin.Origin.X - C.Entry.X) < 0.86 then Continue;
    for Depth in Depths do
      for EntryFactor in EntryFactors do
      begin
        C.Depth := Depth;
        // 小球は分岐の減速板を通り、谷のガイドに沿って転がる。
        C.EntrySpeed := Abs(Aux.Merge.Pass.ExitVelocity.X) * EntryFactor;
        if RequireInterlock then
        begin
          if not FitInterlock(Plan.Cues[Index + 9], Shared, C, Trial.Finish, Interlock) then Continue;
          C.Interlock := Interlock;
        end;
        Trial.Merge.Pass.Counter := C;
        if StopBeforeBoard and (H * (Trial.Position(Trial.Finish).X -
          Following.Board.PointAt(Following.Start, Following.Board.Rear, 0).X) >= -MarbleAuxRadius) then Continue;
        if not CounterRouteClear(Plan, Index, C, Trial.Finish, H) or
          not DuetInView(Plan, Trial, Plan.Cues[Index].Time, Last, H) then Continue;
        Aux := Trial;
        Exit(True);
      end;
  end;
end;

function SeesawCourseClear(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary): Boolean;
const CurveSamples = 6;
var I, J, Last: Integer; Saw: TMarbleSeesaw; Run: array[0..CurveSamples + 2] of TBallPoint;
begin
  Saw := Aux.Merge.Pass.Counter.Seesaw;
  Run[0] := Saw.CatchRail.Origin;
  Last := 1;
  if Saw.ExitRail.Start > 0 then
  begin
    for J := 0 to CurveSamples do
      Run[J + 1] := Saw.RunPosition(Saw.ExitCurveStart + (Saw.ExitRail.Start - Saw.ExitCurveStart) * J / CurveSamples);
    Last := High(Run);
  end;
  Run[Last] := Aux.Position(Aux.Finish);
  for I := Max(0, Index - 20) to Min(High(Plan.Legs), Index + 34) do
  begin
    if (Plan.Legs[I].Motion in [mmRail, mmSeesaw]) and
      not FlightClearsRail(Aux, Plan.Legs[I], Saw.Board.Stop, Saw.CatchRail.Start) then Exit(False);
    for J := 1 to Last do
      if not PathClearsSegment(Plan.Legs[I], Run[J - 1], Run[J], MarbleRadius + MarbleAuxRadius + 0.035) then Exit(False);
  end;
  Result := True;
end;

function FitTrayRelease(var Saw: TMarbleSeesaw; const Cue: TMarbleCue): Boolean;
var Release: TMarbleTrayRelease; Acceleration, TiltSpeed, ExitSpeed, Remaining: Double;
begin
  Result := False;
  if (Cue.Device <> mdGate) or (Cue.Time < Saw.WeightLift.Dock + 0.095) then Exit;
  Release.Lever.Beat.Time := Cue.Time;
  Release.Lever.Beat.Power := Cue.Power;
  Release.Lever.Contact := Cue.Surface;
  Release.Lever.Pivot := BallAdd(Cue.Surface, BallPoint(Cue.Heading * 0.12, 0.29));
  Release.Start := Release.Lever.SeatedAt + TriggerDelay;
  Acceleration := TrayAcceleration;
  Remaining := MarbleTrayNose - Release.DistanceAt(Release.Start + TrayTiltTime);
  TiltSpeed := TrayTiltTime * Acceleration / 2;
  ExitSpeed := Sqrt(Sqr(TiltSpeed) + 2 * Acceleration * Remaining);
  // 皿の先端へ達する時刻と速度から、同じ傾きのレールへつなぐ。
  Saw.CatchRail.Start := Release.Start + TrayTiltTime +
    (ExitSpeed - TiltSpeed) / Acceleration;
  if Saw.Bell.Time - Saw.CatchRail.Start < 0.11 then Exit;
  Saw.TrayRelease := Release;
  Saw.CatchRail.Origin := Saw.TrayPoint(Saw.CatchRail.Start, MarbleTrayNose, MarbleAuxRadius);
  Saw.CatchRail.Grade := -Tan(TrayTilt);
  Saw.CatchRail.Speed := ExitSpeed * Cos(TrayTilt);
  Result := True;
end;

function FitJunctionTail(Plan: TMarblePlan; Index: Integer; var Saw: TMarbleSeesaw): Boolean;
var Cue: TMarbleCue; Link: TMarbleLink; P, Entry: TBallPoint; Grade, Ahead: Double;
begin
  Result := False;
  if Index + 15 > High(Plan.Cues) then Exit;
  Cue := Plan.Cues[Index + 14];
  if (Cue.Device <> mdGate) or (Cue.RelayBeat.Time - Cue.Time < 0.35) or
    (Plan.Cues[Index + 15].Time - Cue.RelayBeat.Time < DuetBrakeTime) then Exit;
  Link := Default(TMarbleLink);
  Link.Kind := mlShutter;
  Link.Heading := Cue.Heading;
  Link.Driver := GateDriver(Cue);
  Link.Deadline := Cue.Time + Min(0.28, (Cue.RelayBeat.Time - Cue.Time) * 0.57);
  if not ScheduleLink(Link, Cue.Time) then Exit;
  // 小球側は主球の分岐をまたぐので、曲線を挟んで浅い勾配へ移す。
  Saw.ExitCurveStart := Saw.Bell.Time + 0.030;
  Saw.ExitRail.Start := Saw.ExitCurveStart + 0.20;
  Saw.ExitRail.Grade := -0.23;
  Entry := Saw.CatchRail.Position(Saw.ExitCurveStart, Link.Heading);
  P := Saw.CatchRail.Position(Saw.ExitRail.Start, Link.Heading);
  Saw.ExitRail.Origin := BallPoint(P.X,
    Entry.Y + Link.Heading * (P.X - Entry.X) * (Saw.CatchRail.Grade + Saw.ExitRail.Grade) / 2);
  Saw.ExitRail.Speed := Saw.CatchRail.SpeedAt(Saw.ExitRail.Start);
  P := Saw.RunPosition(Link.Deadline);
  Grade := Saw.RunGrade(Link.Deadline);
  Ahead := MarbleAuxGateNose;
  Link.Receiver := BallPoint(P.X + Link.Heading * Ahead, P.Y + Grade * Ahead - MarbleAuxRadius * Hypot(1, Grade));
  Saw.ExitGate := Link;
  Saw.ExitBell := Cue.RelayBeat;
  Result := True;
end;

function FitSeesaw(Plan: TMarblePlan; Index: Integer; var Aux: TMarbleAuxiliary; Weighted: Boolean): Boolean;
var Trial: TMarbleAuxiliary; Leg: TMarbleLeg; Saw, Tilted: TMarbleSeesaw; P, Along: TBallPoint;
  Age, Last, Deadline, D, CenterY, TailEnd: Double; I, H: Integer;
  Extended: TMarbleSeesaw;

  function Accept(const Candidate: TMarbleSeesaw; LastBeat, Finish: Double): Boolean;
  begin
    Trial.Finish := Finish;
    Trial.Merge.Pass.Counter.Seesaw := Candidate;
    Result := SeesawCourseClear(Plan, Index, Trial) and
      DuetInView(Plan, Trial, Plan.Cues[Index].Time, LastBeat, H);
    if Result then Aux := Trial;
  end;

begin
  Result := False;
  if Index + 14 > High(Plan.Cues) then Exit;
  Leg := Plan.Legs[Index + 13];
  if (Leg.Motion <> mmSeesaw) or (Leg.HasWeightLift <> Weighted) then Exit;
  H := Leg.Heading;
  Saw := Default(TMarbleSeesaw);
  Saw.Board := Leg.Board;
  Saw.Trigger := Plan.Cues[Index + 12].RelayBeat;
  Saw.Bell := Plan.Cues[Index + 13].RelayBeat;
  Last := Plan.Cues[Index + 14].Time;
  if (Saw.Trigger.Time <= Saw.Board.Stop + 0.19) or (Saw.Bell.Time <= Leg.Finish) or
    (Last - Saw.Bell.Time < DuetBrakeTime) then Exit;
  Trial := Aux;
  Trial.Finish := Min(Last, Saw.Bell.Time + 0.50);
  P := Trial.Position(Saw.Board.Start);
  Along := BallPoint(H * Cos(Saw.Board.BaseAngle), Sin(Saw.Board.BaseAngle));
  Saw.Seat := BallDot(BallSub(P, Saw.Board.Pivot), Along);
  if not InRange(Saw.Seat, Saw.Board.Rear + 0.095, -0.53) or
    (BallLength(BallSub(P, Saw.Board.PointAt(Saw.Board.Start, Saw.Seat, MarbleAuxRadius))) > 1E-6) then Exit;
  Saw.SeatSpeed := 0.65;
  D := Saw.Seat + Saw.SeatSpeed * (Saw.Board.Stop - Saw.Board.Start);
  Saw.Launch := Saw.Board.PointAt(Saw.Board.Stop, D, MarbleAuxRadius);
  Saw.LaunchVelocity := Saw.Board.VelocityAt(Saw.Board.Stop, D, MarbleAuxRadius, Saw.SeatSpeed);
  if (Saw.LaunchVelocity.Y < 1.5) or (H * Saw.LaunchVelocity.X < 0.75) then Exit;

  Age := Saw.Trigger.Time - Saw.Board.Stop;
  P := BallAdd(Saw.Launch, BallPoint(Saw.LaunchVelocity.X * Age, Saw.LaunchVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age)));
  if (P.Y < Saw.Launch.Y + 0.06) or (P.Y - Plan.Position(Saw.Trigger.Time).Y < 0.40) then Exit;
  if Weighted then
  begin
    if (Saw.LaunchVelocity.Y - MarbleGravity * Age > -0.6) or
      (Saw.Bell.Time - Leg.WeightLift.Dock < 0.28) then Exit;
    if (Leg.WeightLift.Ramp > 0) and ((Plan.Legs[Index + 14].Motion <> mmRail) or
      (Abs(Plan.Legs[Index + 14].Grade - Leg.Grade) > 1E-9)) then Exit;
    Saw.WeightLift := Leg.WeightLift;
    Saw.Landing := P;
    Saw.CatchRail.Start := Saw.WeightLift.Dock;
    Saw.CatchRail.Origin := Saw.Pan(Saw.WeightLift.Dock);
    Saw.CatchRail.Grade := -0.32;
    Tilted := Saw;
    if (Plan.Version >= 15) and FitTrayRelease(Tilted, Plan.Cues[Index + 13]) then
    begin
      if Plan.Legs[Index + 14].Junction.Active then
      begin
        P := Tilted.CatchRail.Position(Tilted.Bell.Time, H);
        Tilted.SwitchLever.Beat := Tilted.Bell;
        Tilted.SwitchLever.Contact := BallAdd(P, BallPoint(H * MarbleAuxRadius, 0));
        Tilted.SwitchLever.Pivot := BallAdd(Tilted.SwitchLever.Contact, BallPoint(H * 0.095, 0.215));
        Extended := Tilted;
        if FitJunctionTail(Plan, Index, Extended) then
        begin
          TailEnd := Plan.Cues[Index + 15].Time;
          if Accept(Extended, TailEnd, Min(TailEnd, Extended.ExitBell.Time + 0.50)) then Exit(True);
        end;
      end;
      if Accept(Tilted, Last, Min(Last, Tilted.Bell.Time + 0.50)) then Exit(True);
    end;
    Exit(Accept(Saw, Last, Min(Last, Saw.Bell.Time + 0.50)));
  end;
  Saw.LeverContact := BallAdd(P, BallPoint(H * 0.080, 0.035));
  Saw.Gate.Driver := BallAdd(Saw.LeverContact, BallPoint(H * 0.10, 0.20));
  Saw.Gate.Kind := mlShutter;
  Saw.Gate.Heading := H;
  Deadline := Min(Saw.Trigger.Time + 0.24, Leg.Finish - 0.09);
  P := Leg.Position(Deadline);
  CenterY := P.Y + Leg.Grade * (MarbleRadius + 0.052);
  Saw.Gate.Receiver := BallPoint(P.X + H * (MarbleRadius + 0.052), CenterY - MarbleRadius * Hypot(1, Leg.RailSlope));
  Saw.Gate.Deadline := Deadline;
  if not ScheduleLink(Saw.Gate, Saw.Trigger.Time) then Exit;

  for I := 0 to 6 do
  begin
    Saw.CatchRail.Start := Saw.Trigger.Time + 0.095 + I * 0.022;
    Age := Saw.CatchRail.Start - Saw.Board.Stop;
    if (Saw.CatchRail.Start >= Saw.Bell.Time - 0.28) or (Saw.LaunchVelocity.Y - MarbleGravity * Age > -0.6) then Continue;
    Saw.CatchRail.Origin := BallAdd(Saw.Launch, BallPoint(Saw.LaunchVelocity.X * Age,
      Saw.LaunchVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age)));
    Saw.CatchRail.Grade := -0.20;
    D := (H * Saw.LaunchVelocity.X + Saw.CatchRail.Grade * (Saw.LaunchVelocity.Y - MarbleGravity * Age)) /
      (1 + Sqr(Saw.CatchRail.Grade));
    Saw.CatchRail.Speed := Min(3.55, D * 0.65);
    if Saw.CatchRail.Speed < 1.25 then Continue;
    Trial.Merge.Pass.Counter.Seesaw := Saw;
    if not SeesawCourseClear(Plan, Index, Trial) or not DuetInView(Plan, Trial, Plan.Cues[Index].Time, Last, H) then Continue;
    Aux := Trial;
    Exit(True);
  end;
end;

procedure SetSharedTap(Plan: TMarblePlan; Index: Integer; const SmallBeat: TMarbleBeat);
begin
  Plan.Cues[Index].Device := mdSharedTap;
  Plan.Cues[Index].Slope := Plan.Legs[Index].RailSlope;
  Plan.Cues[Index].Surface := MarbleRailSurface(Plan.Cues[Index].Center, Plan.Cues[Index].Slope);
  Plan.Cues[Index].SharedBeat := SmallBeat;
end;

function FitDuet(Plan: TMarblePlan; Index: Integer; var Leg: TMarbleLeg;
  var Link: TMarbleLink; Runout: Double; Layout: TMarbleDuetLayout = dlShort): Boolean;
var Candidate, Next: TMarbleLeg; NewLink: TMarbleLink; Aux: TMarbleAuxiliary; Reply, Hatch: TMarbleBridge;
  Strike, Bell: TMarbleBeat; Incoming: TBallPoint; Last: Double; LastCue: Integer; Reciprocal: Boolean;
begin
  Result := False;
  Reciprocal := Layout <> dlShort;
  LastCue := Index + 2;
  if Reciprocal then Inc(LastCue);
  if LastCue > High(Plan.Cues) then Exit;
  Strike := Plan.Cues[Index].RelayBeat;
  Bell := Plan.Cues[LastCue - 1].RelayBeat;
  Last := Plan.Cues[LastCue].Time;
  Next := Plan.Legs[Index + 2];
  if (Strike.Time = 0) or (Bell.Time = 0) or (Last - Bell.Time < DuetBrakeTime) or
    (Next.Motion <> mmRail) or (Next.Heading <> Leg.Heading) then Exit;
  Candidate := Leg;
  NewLink := Link;
  if not FitBridge(Candidate, NewLink, Leg.Start, Runout, Strike.Time) then Exit;
  Aux := Candidate.Bridge.Auxiliary;
  Aux.StrikePower := Strike.Power;
  Aux.Bell := Bell;
  Aux.RunGrade := DuetGrade;
  Aux.Finish := Min(Last, Bell.Time + 0.30);
  if Reciprocal then Aux.Finish := Min(Last, Bell.Time + 0.50);
  // 先のレールの接線方向に速度を引き継ぐ。終端の受けで減速するまで転がり続ける。
  Incoming := BallScale(BallSub(Aux.Receiver, Aux.Origin), 2 / (Aux.Strike - Aux.Release));
  Aux.RunSpeed := (Leg.Heading * Incoming.X + DuetGrade * Incoming.Y) / (1 + Sqr(DuetGrade));
  if Reciprocal then
  begin
    Aux.SecondStrike := Plan.Cues[Index + 1].RelayBeat;
    if (Plan.Legs[Index + 3].Motion <> mmRail) or (Plan.Legs[Index + 3].Heading <> Leg.Heading) then Exit;
    if Layout in [dlCrossover, dlMerge, dlPass, dlCounter, dlInterlock, dlSeesaw, dlWeightLift] then
    begin
      if not FitCrossover(Plan, Index, Next, Aux, Last, Reply) then Exit;
      if (Layout in [dlMerge, dlPass, dlCounter, dlInterlock, dlSeesaw, dlWeightLift]) and not FitMerge(Plan, Index, Aux, Hatch) then Exit;
      if (Layout in [dlPass, dlCounter, dlInterlock, dlSeesaw, dlWeightLift]) and
        not FitPass(Plan, Index, Aux, Layout in [dlCounter, dlInterlock, dlSeesaw, dlWeightLift]) then Exit;
      if (Layout in [dlCounter, dlInterlock, dlSeesaw, dlWeightLift]) and
        not FitCounter(Plan, Index, Aux, Layout in [dlInterlock, dlSeesaw, dlWeightLift], Layout in [dlSeesaw, dlWeightLift]) then Exit;
      if (Layout in [dlSeesaw, dlWeightLift]) and not FitSeesaw(Plan, Index, Aux, Layout = dlWeightLift) then Exit;
    end
    else if not FitReplyBridge(Next, Aux.SecondStrike.Time, Reply) or
      not FitAuxiliaryGate(Aux, Plan.Cues[Index + 1], Aux.SecondStrike.Time, Aux.AuxGates[0]) or
      not FitAuxiliaryGate(Aux, Plan.Cues[Index + 2], Bell.Time, Aux.AuxGates[1]) then Exit;
  end;
  if (Layout in [dlShort, dlReciprocal]) and (not DuetClearsCourse(Plan, Index + 1, Aux, Aux.Position(Aux.Finish)) or
    not DuetInView(Plan, Aux, Leg.Start, Last, Leg.Heading)) then Exit;
  Candidate.Bridge.Auxiliary := Aux;
  if Reciprocal then Plan.Legs[Index + 2].Bridge := Reply;
  if Layout in [dlMerge, dlPass, dlCounter, dlInterlock, dlSeesaw, dlWeightLift] then
  begin
    Plan.Legs[Index + 3].Bridge := Hatch;
    for LastCue := Index + 4 to Index + 5 do
      SetSharedTap(Plan, LastCue, Plan.Cues[LastCue].RelayBeat);
  end;
  if Layout in [dlPass, dlCounter, dlInterlock, dlSeesaw, dlWeightLift] then
    for LastCue := Index + 8 to Index + 9 do
      SetSharedTap(Plan, LastCue, Aux.Merge.Pass.Taps[LastCue - Index - 8]);
  if Layout in [dlCounter, dlInterlock, dlSeesaw, dlWeightLift] then
    for LastCue := Index + 10 to Index + 11 do
      SetSharedTap(Plan, LastCue, Aux.Merge.Pass.Counter.Taps[LastCue - Index - 10]);
  if Aux.Merge.Pass.Counter.Seesaw.TrayRelease.Active then
    Plan.Cues[Index + 13].Device := mdTrayRelease;
  if Aux.Merge.Pass.Counter.Seesaw.ExitGate.Kind <> mlNone then
    Plan.Cues[Index + 14].Device := mdJunctionGate;
  Leg := Candidate;
  Link := NewLink;
  Result := True;
end;

procedure BuildLinks(Plan: TMarblePlan);
var I, Target, ResumeAt: Integer; Cue, Destination: TMarbleCue; Leg: TMarbleLeg; Link: TMarbleLink; Fitted: Boolean;
  Travel: Double;
begin
  if Plan.Version < 3 then Exit;
  SetLength(Plan.Links, Length(Plan.Cues));
  ResumeAt := 0;
  for I := 0 to High(Plan.Cues) - 1 do
  begin
    if I < ResumeAt then Continue; // この二つのレバーは小球側のゲートにつながっている。
    Cue := Plan.Cues[I];
    Link := Default(TMarbleLink);
    Link.Driver := BallPoint(Cue.Surface.X, Cue.Surface.Y - 0.13);
    Target := I;
    case Cue.Device of
      mdGate: Link.Driver := GateDriver(Cue);
      mdBell: Inc(Target);
      mdCatch: if not Plan.Legs[I].Rollout then Continue;
      mdChute: if Plan.Cues[I + 1].Device <> mdSpring then Continue else Inc(Target);
      else Continue;
    end;
    Leg := Plan.Legs[Target + 1];
    Destination := Plan.Cues[Target];
    Link.Target := Target;
    Link.Heading := Destination.Heading;
    if Cue.Device = mdChute then
    begin
      Link.Kind := mlSpringLatch;
      Link.Driver := BallPoint(Cue.Surface.X + Cue.Heading * 0.12, Cue.Center.Y + 0.02);
      Link.Receiver := BallPoint(Destination.Surface.X + Destination.Heading * 0.22, Destination.Surface.Y - 0.17);
      Link.Deadline := Destination.Time;
    end
    else
    begin
      if (Leg.Motion <> mmRail) or Leg.Junction.Active then Continue;
      Travel := Abs(Leg.Position(Leg.Finish).X - Leg.Origin.X);
      if Travel < 0.74 then Continue;
      Fitted := False;
      if (Plan.Version >= 5) and (Cue.Device = mdGate) and (CoursePart(Plan.Version, I) = 1) then
      begin
        if Plan.Version >= 7 then
        begin
          if Plan.Version >= 14 then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlWeightLift);
          if (Plan.Version >= 13) and not Fitted then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlSeesaw);
          if (Plan.Version >= 12) and not Fitted then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlInterlock);
          if (Plan.Version >= 11) and not Fitted then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlCounter);
          if (Plan.Version >= 10) and not Fitted then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlPass);
          if (Plan.Version >= 9) and not Fitted then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlMerge);
          if (Plan.Version >= 8) and not Fitted then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlCrossover);
          if not Fitted then Fitted := FitDuet(Plan, I, Leg, Link, 0.28, dlReciprocal) or
            FitDuet(Plan, I, Leg, Link, 0.035, dlReciprocal);
          if Fitted then ResumeAt := I + 3;
          if Leg.Bridge.Auxiliary.Merge.Active then ResumeAt := I + 6;
          if Leg.Bridge.Auxiliary.Merge.Pass.Active then ResumeAt := I + 10;
          if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Active then ResumeAt := I + 12;
        end;
        if (Plan.Version >= 6) and not Fitted then
          Fitted := FitDuet(Plan, I, Leg, Link, 0.28) or FitDuet(Plan, I, Leg, Link, 0.035);
        // 橋の先にレールを残して、次の仕掛けまでの境目を見せる。
        if not Fitted then Fitted := FitBridge(Leg, Link, Cue.Time, 0.28);
        if not Fitted then Fitted := FitBridge(Leg, Link, Cue.Time, 0.035);
      end;
      if (Plan.Version >= 4) and not Fitted then Fitted := FitBridge(Leg, Link, Cue.Time);
      if Fitted then
      begin
        Plan.Legs[Target + 1] := Leg;
        Plan.Links[I] := Link;
        Continue;
      end;
      PlaceShutter(Link, Leg, Min(1.02, Travel * 0.64));
    end;
    if ScheduleLink(Link, Cue.Time) then Plan.Links[I] := Link;
  end;
end;

procedure LayLinkedCourse(Plan: TMarblePlan; const Cancel: TFunc<Boolean> = nil);
var DisabledLifts, DisabledJunctions: TArray<Boolean>; Retry: Boolean; I: Integer;
begin
  if Plan.Version >= 14 then SetLength(DisabledLifts, Length(Plan.Cues));
  if Plan.Version >= 16 then SetLength(DisabledJunctions, Length(Plan.Cues));
  repeat
    Plan.Legs := nil;
    Plan.Links := nil;
    LayCourse(Plan, DisabledLifts, DisabledJunctions, Cancel);
    BuildLinks(Plan);
    Retry := False;
    // 小球が届かない仕掛けを外し、分岐の影響を除いてからリフトも再判定する。
    for I := 13 to High(Plan.Legs) do
    begin
      if Plan.Legs[I].Junction.Active and
        (Plan.Legs[I - 13].Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.SwitchLever.Beat.Time = 0) then
      begin
        DisabledJunctions[I - 1] := True;
        Retry := True;
      end;
      if (I < High(Plan.Legs)) and Plan.Legs[I].HasWeightLift and not Plan.Legs[I + 1].Junction.Active and
        not Plan.Legs[I - 12].Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.WeightLift.Active then
      begin
        DisabledLifts[I - 1] := True;
        Retry := True;
      end;
    end;
  until not Retry;
end;

procedure IndexRotation(Plan: TMarblePlan);
var I: Integer; Previous: TMarbleLeg; Speed: TBallPoint;
begin
  for I := 1 to High(Plan.Legs) do
  begin
    Previous := Plan.Legs[I - 1];
    Plan.Legs[I].Spin := Previous.Rotation(Previous.Finish);
    if Previous.Motion = mmFlight then Plan.Legs[I].FreeSpin := Previous.FreeSpin
    else
    begin
      Speed := Previous.Velocity(Previous.Finish);
      Plan.Legs[I].FreeSpin := -Sign(Speed.X) * BallLength(Speed) / MarbleRadius;
    end;
  end;
end;

procedure IndexCourse(Plan: TMarblePlan);
const SectionSize = 24;
var I, J: Integer; Box: TMarbleSection; Aux: TMarbleAuxiliary; Tail: TBallPoint;
begin
  SetLength(Plan.Sections, (Length(Plan.Legs) + SectionSize - 1) div SectionSize);
  for I := 0 to High(Plan.Sections) do
    with Plan.Sections[I] do
    begin
      First := I * SectionSize;
      Last := Min(First + SectionSize - 1, High(Plan.Legs));
      Left := Infinity;
      Right := -Infinity;
      Bottom := Infinity;
      Top := -Infinity;
      for J := First to Last do
      begin
        Box := MotionBounds(Plan.Legs[J]);
        Left := Min(Left, Box.Left);
        Right := Max(Right, Box.Right);
        Bottom := Min(Bottom, Box.Bottom);
        Top := Max(Top, Box.Top);
        Aux := Plan.Legs[J].Bridge.Auxiliary;
        if Aux.Active then Top := Max(Top, Aux.Origin.Y);
        if Aux.Duet then
        begin
          Tail := Aux.Position(Aux.Finish);
          Left := Min(Left, Tail.X);
          Right := Max(Right, Tail.X);
          Bottom := Min(Bottom, Tail.Y);
        end;
      end;
    end;
end;

function BuildMarblePlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TMarblePlan;
var Selected: TList<TMarbleCue>; Hit: TRhythmHit; Cue: TMarbleCue; Last, Gap, BeatDelay: Double;
  I, Part, Previous, Version: Integer;
begin
  Selected := TList<TMarbleCue>.Create;
  try
    Version := StylePlanVersion(rsMarbleRelay);
    Last := -1;
    for I := 0 to High(Audio.Hits) do
    begin
      if Assigned(Cancel) and Cancel() then Abort;
      Hit := Audio.Hits[I];
      if (Hit.Time < 0) or (Hit.Time > Audio.Duration) then Continue;
      Gap := MinContactGap;
      Part := -1;
      Previous := Selected.Count - 1;
      // 密集時も大きな機構を通す余白を取る。採用した音は元の時刻をそのまま使う。
      if (Previous >= 0) and (I < High(Audio.Hits)) then
      begin
        Part := CoursePart(Version, Previous);
        if Part in [5, 8, 9, 10, 12, 14] then Gap := 0.30;
        // 連打が続く曲では、小球用に広く取る区画を絞って接触を残す。
        if Part = 1 then
        begin
          Gap := 0.46;
          if ((Previous div 20) mod 3 = 0) or
            (Last - Selected[Previous - 1].Time >= 0.30) then Gap := 0.72;
        end;
        if (Version >= 6) and (Part = 2) and (Selected[Previous - 1].RelayBeat.Time > 0) then Gap := DuetSecondGap;
        // 通常の交互区間と長い区間を混ぜ、速い連打では短い区間を使う。
        if (Version >= 7) and (Part = 3) and ((Previous div 20) mod 2 = 0) and
          (Selected[Previous - 1].RelayBeat.Time > 0) and (Selected[Previous - 2].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if (Version >= 9) and (Part in [4, 5, 6]) and (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if PassSlot(Version, Previous) and (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if CounterSlot(Version, Previous) and (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if (SeesawSlot(Version, Previous) or JunctionTailSlot(Version, Previous)) and
          (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
      end;
      if Hit.Time < Last + Gap - 1E-10 then
      begin
        // 主球用に空けた間隔の音を、小球の橋レバーとベルの候補にする。
        BeatDelay := Hit.Time - Last;
        if (Version >= 6) and
          (((Part = 1) and (Gap >= 0.72) and InRange(BeatDelay, 0.34, 0.56)) or
           ((Part = 2) and (Gap = DuetSecondGap) and (BeatDelay >= 0.18 - 1E-10)) or
           ((Part = 3) and (Gap = ReciprocalGap) and InRange(BeatDelay, 0.22, 0.59)) or
           ((Version >= 9) and (Part in [4, 5, 6]) and (Gap = ReciprocalGap) and InRange(BeatDelay, 0.30, 0.60)) or
           ((PassSlot(Version, Previous) or CounterSlot(Version, Previous) or SeesawSlot(Version, Previous) or
             JunctionTailSlot(Version, Previous)) and
            (Gap = ReciprocalGap) and InRange(BeatDelay, 0.30, 0.60))) then
        begin
          Cue := Selected[Previous];
          if Cue.RelayBeat.Time = 0 then
          begin
            Cue.RelayBeat.Time := Hit.Time;
            Cue.RelayBeat.Power := EnsureRange(Hit.Strength, 0.0, 1.0);
            Selected[Previous] := Cue;
          end;
        end;
        Continue;
      end;
      Cue := Default(TMarbleCue);
      Cue.Time := Hit.Time;
      Cue.Power := EnsureRange(Hit.Strength, 0.0, 1.0);
      Selected.Add(Cue);
      Last := Cue.Time;
    end;
    Result := TMarblePlan.Create;
    try
      Result.Version := Version;
      Result.Duration := Audio.Duration;
      Result.Cues := Selected.ToArray;
      if Length(Result.Cues) > 0 then Result.Cues[High(Result.Cues)].RelayBeat := Default(TMarbleBeat);
      LayLinkedCourse(Result, Cancel);
      IndexRotation(Result);
      IndexCourse(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Selected.Free;
  end;
end;

procedure SaveMarblePlan(Plan: TMarblePlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
var Root: TJSONObject; Rows, Row: TJSONArray; Cue: TMarbleCue;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(1));
    Root.AddPair('style', StyleId(rsMarbleRelay));
    Root.AddPair('version', TJSONNumber.Create(Ref.Version));
    Root.AddPair('key', Ref.Key);
    Root.AddPair('source', Ref.SourceKey);
    Root.AddPair('sensitivity', TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction', TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root, Audio);
    Root.AddPair('duration', PreparedExact(Plan.Duration));
    Rows := TJSONArray.Create;
    Root.AddPair('cues', Rows);
    for Cue in Plan.Cues do
    begin
      Row := TJSONArray.Create;
      Rows.AddElement(Row);
      Row.AddElement(PreparedExact(Cue.Time));
      Row.AddElement(PreparedExact(Cue.Power));
      if Ref.Version >= 6 then
      begin
        Row.AddElement(PreparedExact(Cue.RelayBeat.Time));
        Row.AddElement(PreparedExact(Cue.RelayBeat.Power));
      end;
    end;
    WritePreparedData(Root, Ref);
  finally
    Root.Free;
  end;
end;

function LoadMarbleAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
var Root: TJSONObject;
begin
  Root := ReadPreparedData(Ref, rsMarbleRelay, Direction);
  try
    Result := PreparedAudio(Root, Ref, Source);
    Result.Hits := nil; // 冷復元時のEQは保存した接触列を使う。
  finally
    Root.Free;
  end;
end;

procedure RequirePlan(Valid: Boolean);
begin
  if not Valid then raise EConvertError.Create('からくりリレーの保存計画が不正です。再準備してください。');
end;

function LoadMarblePlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TMarblePlan;
var Root: TJSONObject; Value: TJSONValue; Rows, Row: TJSONArray;
  I, Columns: Integer; Last: Double; Cue: TMarbleCue;
begin
  RequirePlan(Ref.Matches(Audio.Key, Audio.Sensitivity, Direction, rsMarbleRelay));
  Root := ReadPreparedData(Ref, rsMarbleRelay, Direction);
  try
    Result := TMarblePlan.Create;
    try
      Result.Version := Ref.Version;
      Result.Duration := ReadPreparedExact(Root.GetValue('duration'));
      RequirePlan((Result.Duration > 0) and (Abs(Result.Duration - Audio.Duration) < 1E-8));
      Value := Root.GetValue('cues');
      RequirePlan(Value is TJSONArray);
      Rows := TJSONArray(Value);
      RequirePlan(Rows.Count <= MaxCues);
      SetLength(Result.Cues, Rows.Count);
      Columns := 2;
      if Ref.Version >= 6 then Columns := 4;
      Last := -1;
      for I := 0 to Rows.Count - 1 do
      begin
        RequirePlan(Rows.Items[I] is TJSONArray);
        Row := TJSONArray(Rows.Items[I]);
        RequirePlan(Row.Count = Columns);
        Cue := Default(TMarbleCue);
        Cue.Time := ReadPreparedExact(Row.Items[0]);
        Cue.Power := ReadPreparedExact(Row.Items[1]);
        RequirePlan(InRange(Cue.Time, 0.0, Result.Duration) and (Cue.Time >= Last + MinContactGap - 1E-10) and
          InRange(Cue.Power, 0.0, 1.0));
        if Columns = 4 then
        begin
          Cue.RelayBeat.Time := ReadPreparedExact(Row.Items[2]);
          Cue.RelayBeat.Power := ReadPreparedExact(Row.Items[3]);
          if Cue.RelayBeat.Time <> 0 then
            RequirePlan((I < Rows.Count - 1) and
              ((CoursePart(Ref.Version, I) in [1, 2]) or ((Ref.Version >= 7) and (CoursePart(Ref.Version, I) = 3)) or
               ((Ref.Version >= 9) and (CoursePart(Ref.Version, I) in [4, 5, 6])) or
               PassSlot(Ref.Version, I) or CounterSlot(Ref.Version, I) or SeesawSlot(Ref.Version, I) or
               JunctionTailSlot(Ref.Version, I)) and
              (Cue.Time < Cue.RelayBeat.Time) and InRange(Cue.RelayBeat.Power, 0.0, 1.0));
          if I > 0 then RequirePlan(Result.Cues[I - 1].RelayBeat.Time < Cue.Time);
        end;
        Result.Cues[I] := Cue;
        Last := Cue.Time;
      end;
      LayLinkedCourse(Result);
      IndexRotation(Result);
      IndexCourse(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;

end.
