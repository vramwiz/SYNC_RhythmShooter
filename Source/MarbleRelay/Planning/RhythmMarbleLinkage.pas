unit RhythmMarbleLinkage;
// 主球・小球と仕掛けの受け渡しを組み、通過時刻と画角に収まる連鎖を選ぶ。
interface

uses System.SysUtils, RhythmMarbleCourse;

// CuesをもとにLegsとLinksを作る。小球の到達条件に合わない仕掛けは外して再配置する。
procedure LayLinkedCourse(Plan: TMarblePlan; const Cancel: TFunc<Boolean> = nil);

implementation

uses System.Math, RhythmBallGeometry, RhythmMarbleLayout;

type
  TMarbleDuetLayout = (dlShort, dlReciprocal, dlCrossover, dlMerge, dlPass, dlCounter, dlInterlock, dlSeesaw, dlWeightLift);

const
  DuetGrade = -0.23;

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

procedure LayLinkedCourse(Plan: TMarblePlan; const Cancel: TFunc<Boolean>);
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

end.
