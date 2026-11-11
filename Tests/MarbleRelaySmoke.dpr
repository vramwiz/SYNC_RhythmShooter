program MarbleRelaySmoke;
{$APPTYPE CONSOLE}
// 接触の時刻、重力、レールからの離脱を検証し、指定WAVの試写も出力する。
uses System.SysUtils, System.Math, System.IOUtils, System.Hash, System.Types, Winapi.Windows, Vcl.Graphics, Vcl.Imaging.pngimage,
  RhythmAudio, RhythmAudioCache, RhythmPrepare, RhythmStyles, RhythmPlanRef, RhythmBallGeometry,
  RhythmMarblePlan, RhythmScene, RhythmSettings;

const FrameRate = 30;

procedure Need(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

function Fixture(const Path: string): TRhythmAudio;
const Gaps: array[0..7] of Double = (0.27, 0.48, 0.41, 0.22, 0.56, 0.34, 0.36, 0.62);
var I: Integer; T: Double;
begin
  TFile.WriteAllText(Path, 'Synthetic events for marble relay.', TEncoding.UTF8);
  Result := TRhythmAudio.Create;
  try
    Result.Source := Path;
    Result.Key := THashSHA2.GetHashStringFromFile(Path);
    Result.SourceRevision := AudioSourceStamp(Path);
    Result.Sensitivity := 50;
    SetLength(Result.Hits, 64);
    T := 0.25;
    for I := 0 to High(Result.Hits) do
    begin
      Result.Hits[I].Time := T;
      Result.Hits[I].Strength := 0.3 + 0.12 * (I mod 6);
      T := T + Gaps[I mod Length(Gaps)];
    end;
    Result.SoundEnd := T;
    Result.Duration := T + 0.18;
  except
    Result.Free;
    raise;
  end;
end;

procedure VerifyPhysics(Plan: TMarblePlan; Audio: TRhythmAudio; Demo: Boolean);
var I, J, K, Flights, Drops, Reversals, Lifts, Shuttles, Swings, Chutes, Rollouts, RollingJoins: Integer;
  Seen: set of TMarbleDevice; Cue: TMarbleCue; Leg, Previous: TMarbleLeg;
  A, B, C, Pivot: TBallPoint; T, DT, Gentle, Steep: Double;
begin
  J := 0;
  Flights := 0;
  Drops := 0;
  Reversals := 0;
  Lifts := 0;
  Shuttles := 0;
  Swings := 0;
  Chutes := 0;
  Rollouts := 0;
  RollingJoins := 0;
  Gentle := 0;
  Steep := 0;
  Seen := [];
  Need(Length(Plan.Legs) = Length(Plan.Cues) + 1, 'Course is disconnected');
  for I := 0 to High(Plan.Cues) do
  begin
    Cue := Plan.Cues[I];
    Include(Seen, Cue.Device);
    while (J < Length(Audio.Hits)) and (Audio.Hits[J].Time < Cue.Time) do Inc(J);
    Need((J < Length(Audio.Hits)) and (Audio.Hits[J].Time = Cue.Time), 'Contact does not use the original onset');
    Need(Plan.CueAt(Cue.Time - 1E-8) = I - 1, 'Device reacts before its contact');
    Need(Plan.CueAt(Cue.Time) = I, 'Device is late');
    Need(Abs(BallLength(BallSub(Cue.Center, Cue.Surface)) - MarbleRadius) < 1E-9, 'Ball misses the surface');
    Previous := Plan.Legs[I];
    Leg := Plan.Legs[I + 1];
    if Leg.Bridge.Auxiliary.Duet then Include(Seen, mdBell);
    Need(BallLength(BallSub(Previous.Position(Cue.Time), Leg.Position(Cue.Time))) < 1E-9, 'Ball jumps at a contact');
    Need(Abs(Previous.Rotation(Cue.Time) - Leg.Rotation(Cue.Time)) < 1E-9, 'Rotation jumps at handoff');
    if Cue.Device = mdTip then
    begin
      Inc(Drops);
      Need(BallLength(BallSub(Previous.Velocity(Cue.Time), Leg.Velocity(Cue.Time))) < 1E-9,
        'Rail edge changes velocity');
    end;
    if Leg.Motion = mmFlight then
    begin
      Inc(Flights);
      DT := (Leg.Finish - Leg.Start) * 0.25;
      T := Leg.Start + 2 * DT;
      A := Plan.Position(T - DT);
      B := Plan.Position(T);
      C := Plan.Position(T + DT);
      Need(Abs(A.X - 2 * B.X + C.X) < 1E-9, 'Ball accelerates sideways in air');
      Need(Abs(A.Y - 2 * B.Y + C.Y + MarbleGravity * Sqr(DT)) < 1E-9, 'Flight departs from constant gravity');
    end;
    if Leg.Motion = mmRail then
    begin
      A := Leg.Velocity((Leg.Start + Leg.Finish) * 0.5);
      Need((Leg.Heading * A.X > 0) and (Abs(A.Y - Leg.RailSlope * A.X) < 1E-9), 'Ball leaves its rail');
      Need(Abs(Leg.Terminal * Leg.Drag + (5 / 7) * MarbleGravity * Leg.Grade / (1 + Sqr(Leg.Grade))) < 1E-9,
        'Rail acceleration is not tied to its slope');
      if Abs(Leg.Grade) < 0.22 then Gentle := Leg.Terminal;
      if Abs(Leg.Grade) > 0.55 then Steep := Leg.Terminal;
      if Previous.Rollout and (Previous.Grade = Leg.Grade) then
      begin
        Inc(RollingJoins);
        Need(BallLength(BallSub(Previous.Velocity(Cue.Time), Leg.Velocity(Cue.Time))) < 1E-9,
          'Ball stalls when reaching the connecting rail');
      end;
    end;
    A := Leg.Origin;
    B := Leg.Position(Leg.Finish);
    C := Leg.Position((Leg.Start + Leg.Finish) * 0.5);
    if Leg.Rollout then
    begin
      Inc(Rollouts);
      T := (Leg.Start + Leg.Dock) * 0.5;
      Need(BallLength(Leg.Velocity(Leg.Dock)) < 1E-9, 'Cradle stops abruptly');
      Need(BallLength(BallSub(Leg.Position(Leg.Dock), Leg.Carriage(Leg.Dock))) < 1E-9, 'Ball jumps when leaving cradle');
      Need((Leg.Heading * (B.X - Leg.Carriage(Leg.Dock).X) > 0) and (B.Y < Leg.Carriage(Leg.Dock).Y),
        'Ball does not roll off the cradle');
      Need(Abs(Leg.Rotation(Leg.Finish) - Leg.Rotation(Leg.Dock)) > 1E-4, 'Rollout does not turn the ball');
      B := Leg.Carriage(Leg.Finish);
      C := Leg.Carriage(T);
    end;
    case Cue.Device of
      mdBend:
        begin
          Inc(Reversals);
          Pivot := Leg.ArcPivot;
          for K := 0 to 30 do
          begin
            T := Leg.Start + (Leg.Finish - Leg.Start) * K / 30;
            Need(Abs(BallLength(BallSub(Leg.Position(T), Pivot)) - Leg.Radius) < 1E-9, 'Ball cuts through guide');
          end;
          Need((Leg.Heading * Leg.Velocity(Leg.Start).X > 0) and (Leg.Heading * Leg.Velocity(Leg.Finish).X < 0) and
            (B.Y < A.Y) and (BallLength(Leg.Velocity(Leg.Finish)) > BallLength(Leg.Velocity(Leg.Start))),
            'Switchback does not reverse and accelerate downhill');
        end;
      mdLift:
        begin
          Inc(Lifts);
          Need((A.X = B.X) and (A.X = C.X) and (B.Y > C.Y) and (C.Y > A.Y), 'Lift is not vertical');
        end;
      mdShuttle:
        begin
          Inc(Shuttles);
          if Leg.Travel.Y < 0 then
            Need((A.Y > C.Y) and (C.Y > B.Y) and (Leg.Heading * (B.X - A.X) > 0.25), 'Bypass cradle does not lower the main ball')
          else Need((A.Y = B.Y) and (A.Y = C.Y) and (Leg.Heading * (B.X - A.X) > 0.50), 'Shuttle does not carry horizontally');
        end;
      mdSwing:
        begin
          Inc(Swings);
          Need((Abs(A.Y - B.Y) < 1E-9) and (C.Y < A.Y - 0.15) and (Abs(B.X - A.X) > 0.70), 'Lever does not swing across');
        end;
      mdChute:
        begin
          Inc(Chutes);
          Need((A.X = B.X) and (A.X = C.X) and (B.Y < C.Y) and (C.Y < A.Y), 'Chute does not drop vertically');
        end;
    end;
  end;
  if Demo then Need([mdBell, mdSharedTap] <= Seen, 'Demo misses the two-ball contacts on the shared rail')
  else Need((Gentle > 0) and (Steep > 2 * Gentle), 'Steeper slope does not produce more speed');
  Need([mdGate, mdSpring, mdCatch, mdGoal] <= Seen, 'Fixture misses core motion');
  if not Demo then Need(mdBend in Seen, 'Fixture misses the switchback');
  if Demo then Need((Rollouts >= 1) and (RollingJoins >= 1), 'The overtaking cradle does not roll onto its rail')
  else
  begin
    Need(Rollouts >= 2, 'Powered devices have no rolling exits');
    Need(RollingJoins >= 2, 'Powered devices have no continuous rail handoffs');
  end;
  Need(BallLength(BallSub(Plan.Position(Plan.EndTime), Plan.Position(Plan.EndTime + 1))) < 1E-9, 'Goal does not settle');
  WriteLn('Main-ball contacts: ', Length(Plan.Cues), '/', Length(Audio.Hits), ' original hits; ', Flights,
    ' gravity flights, ', Drops, ' rail-edge drops.');
  WriteLn('Mechanisms: ', Reversals, ' switchbacks, ', Lifts, ' lifts, ', Shuttles, ' shuttles, ',
    Swings, ' swings, ', Chutes, ' chutes, ', Rollouts, ' rolling exits, ', RollingJoins, ' rolling joins.');
end;

procedure VerifyAuxiliary(Plan: TMarblePlan; const Link: TMarbleLink; const Leg: TMarbleLeg);
var Bridge: TMarbleBridge; Aux: TMarbleAuxiliary; Delta, P, Camera: TBallPoint; I: Integer; T: Double;
begin
  Bridge := Leg.Bridge;
  Aux := Bridge.Auxiliary;
  Delta := BallSub(Aux.Receiver, Aux.Origin);
  Need((Link.Ready <= Aux.Release) and (Aux.Release < Aux.Strike) and (Aux.Strike < Bridge.Pull),
    'The second ball or the bridge moves before its trigger');
  Need((Link.Opening(Aux.Release) = 1) and (Delta.Y < 0) and (Leg.Heading * Delta.X > 0),
    'The second ball does not have a downhill route after the gate opens');
  Need(BallLength(BallSub(Aux.Position(Link.Pull), Aux.Origin)) < 1E-9,
    'The second ball moves before release');
  Need(BallLength(BallSub(Aux.Position((Aux.Release + Aux.Strike) * 0.5),
    BallMix(Aux.Origin, Aux.Receiver, 0.25))) < 1E-9, 'The second ball does not accelerate downhill');
  Need(BallLength(BallSub(Aux.Position(Aux.Strike), Aux.Receiver)) < 1E-9, 'The second ball misses the lever');
  Need(BallLength(BallSub(Bridge.Tip(Aux.Strike), Bridge.Tip(Link.Ready))) < 1E-9,
    'The bridge moves before the second ball reaches its lever');
  for I := 0 to 16 do
  begin
    T := Aux.Release + (Bridge.Deadline - Aux.Release) * I / 16;
    P := Aux.Position(T);
    Camera := Plan.CameraTarget(T);
    Need((Leg.Heading * Leg.Velocity(T).X > 0) and
      (Abs(Camera.X - P.X) < 2.9 - MarbleAuxRadius) and
      InRange(Camera.Y + 3.75 * 0.54 - P.Y, MarbleAuxRadius, 3.75 - MarbleAuxRadius),
      'The main ball stops or the second ball leaves the camera during the chain');
  end;
end;

procedure VerifyBridge(const Leg: TMarbleLeg; Trigger: Double);
var Bridge: TMarbleBridge; A, B, P: TBallPoint;
begin
  Bridge := Leg.Bridge;
  Need((Trigger < Bridge.Pull) and (Bridge.Pull < Bridge.Ready) and (Bridge.Ready < Bridge.Deadline),
    'Bridge moves before its lever, or the ball reaches the gap too soon');
  Need(BallLength(BallSub(Bridge.Tip(Trigger), Bridge.Entry)) > 0.14, 'Bridge is already in place before its trigger');
  Need(BallLength(BallSub(Bridge.Tip(Bridge.Deadline), Bridge.Entry)) < 1E-9, 'Bridge does not reach the rail');
  Leg.RailSupport(A, B);
  Need((Leg.Heading * (Bridge.Entry.X - A.X) > 0) and (Leg.Heading * (B.X - Bridge.Hinge.X) > 0) and
    (Abs(Bridge.Entry.Y - A.Y - Leg.RailSlope * (Bridge.Entry.X - A.X)) < 1E-9) and
    (Abs(Bridge.Hinge.Y - B.Y - Leg.RailSlope * (Bridge.Hinge.X - B.X)) < 1E-9), 'Bridge does not align with both rail ends');
  P := Leg.Position(Bridge.Deadline);
  Need((Abs(Leg.Heading * (Bridge.Entry.X - P.X) - MarbleRadius - 0.026) < 1E-5) and
    (Leg.Heading * Leg.Velocity(Bridge.Deadline).X > 0), 'Main ball waits or jumps at the completed route');
end;

procedure VerifyCrossover(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary);
var Leg: TMarbleLeg; Bridge: TMarbleBridge; P, M, A, B, C: TBallPoint;
  T, Gap, RelativeY, DT: Double; I, Crossed: Integer;
begin
  Leg := Plan.Legs[Index + 2];
  Bridge := Leg.Bridge;
  Need(Bridge.Sliding and (Aux.DropEnd = Aux.SecondStrike.Time) and (Aux.DropEnd < Bridge.Pull),
    'The sliding bridge moves before the blue ball has landed');
  Need((Aux.Position(Aux.Strike).Y > Plan.Position(Aux.Strike).Y + 0.3) and
    (Plan.Position(Aux.DropEnd).Y > Aux.Landing.Y + 0.3), 'The two balls do not swap vertical order');
  DT := (Aux.DropEnd - Aux.DropStart) / 4;
  A := Aux.Position(Aux.DropStart + DT);
  B := Aux.Position(Aux.DropStart + 2 * DT);
  C := Aux.Position(Aux.DropStart + 3 * DT);
  Need((Abs(A.X - 2 * B.X + C.X) < 1E-9) and
    (Abs(A.Y - 2 * B.Y + C.Y + MarbleGravity * Sqr(DT)) < 1E-9), 'Crossover is not a gravity-driven drop');
  Crossed := 0;
  Gap := Leg.Heading * (Bridge.Hinge.X - Bridge.Entry.X);
  for I := 0 to 100 do
  begin
    T := Aux.DropStart + (Aux.DropEnd - Aux.DropStart) * I / 100;
    P := Aux.Position(T);
    RelativeY := P.Y - (Bridge.Entry.Y + Leg.RailSlope * (P.X - Bridge.Entry.X));
    if not InRange(RelativeY, -0.18 - MarbleAuxRadius, MarbleAuxRadius) then Continue;
    Inc(Crossed);
    Need(InRange(Leg.Heading * (P.X - Bridge.Entry.X), MarbleAuxRadius, Gap - MarbleAuxRadius) and
      (BallLength(BallSub(Bridge.Tip(T), Bridge.Hinge)) < 1E-9), 'Blue ball hits the rail or its sliding bridge');
  end;
  Need(Crossed > 0, 'The blue ball never goes through the open rail gap');
  for I := 0 to 60 do
  begin
    T := Aux.DropEnd + (Plan.Cues[Index + 3].Time - Aux.DropEnd) * I / 60;
    P := Aux.Position(T);
    M := Plan.Position(T);
    Need(M.Y > P.Y + 0.28, 'Blue ball does not stay below the main ball after the swap');
  end;
  WriteLn(Format('Crossover drop: %.3f to %.3f.', [Aux.DropStart, Aux.DropEnd]));
end;

procedure VerifyMerge(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary);
var Merge: TMarbleMerge; Hatch: TMarbleBridge; Rail: TMarbleLeg; Cue: TMarbleCue;
  P, A, B, C, Normal: TBallPoint; T, DT, H, Gap: Double; I, Crossed: Integer;
begin
  Merge := Aux.Merge;
  Rail := Plan.Legs[Index + 3];
  Hatch := Rail.Bridge;
  Need(Hatch.Retracting and (Hatch.Pull > Rail.Finish) and (Hatch.Ready < Merge.Launch.Time) and
    (Rail.Heading * (Rail.Position(Rail.Finish).X - Hatch.Hinge.X) > MarbleRadius),
    'Hatch opens before the main ball clears it or after the launch');
  Need(BallLength(BallSub(Hatch.Tip(Rail.Finish), Hatch.Entry)) < 1E-9, 'Main ball crosses an open return hatch');
  DT := (Merge.Join - Merge.Launch.Time) / 4;
  A := Aux.Position(Merge.Launch.Time + DT);
  B := Aux.Position(Merge.Launch.Time + DT * 2);
  C := Aux.Position(Merge.Launch.Time + DT * 3);
  Need((B.Y > Merge.LaunchPoint.Y + 0.2) and (Abs(A.X - 2 * B.X + C.X) < 1E-9) and
    (Abs(A.Y - 2 * B.Y + C.Y + MarbleGravity * Sqr(DT)) < 1E-9), 'Spring launch does not follow a ballistic arc');
  Crossed := 0;
  Gap := Rail.Heading * (Hatch.Hinge.X - Hatch.Entry.X);
  for I := 0 to 100 do
  begin
    T := Merge.Launch.Time + DT * 2 * I / 100;
    P := Aux.Position(T);
    H := P.Y - Hatch.Entry.Y - Rail.RailSlope * (P.X - Hatch.Entry.X);
    if not InRange(H, -0.18 - MarbleAuxRadius, MarbleAuxRadius) then Continue;
    Inc(Crossed);
    Need(InRange(Rail.Heading * (P.X - Hatch.Entry.X), MarbleAuxRadius, Gap - MarbleAuxRadius) and
      (BallLength(BallSub(Hatch.Tip(T), Hatch.Hinge)) < 1E-9), 'Blue ball hits the return hatch');
  end;
  Need(Crossed > 0, 'Blue ball does not pass upward through the hatch');
  Normal := BallUnit(BallPoint(-Rail.RailSlope, 1));
  Need(Abs(BallDot(BallSub(Merge.JoinPoint, Hatch.Hinge), Normal) - MarbleAuxRadius) < 1E-8,
    'Blue ball lands on a different rail');
  for I := 0 to High(Merge.Taps) do
  begin
    Cue := Plan.Cues[Index + 4 + I];
    P := BallSub(Aux.Position(Merge.Taps[I].Time), BallScale(Normal, MarbleAuxRadius));
    Need((Cue.Device = mdSharedTap) and (Cue.Time < Merge.Taps[I].Time) and
      (BallLength(BallSub(P, Cue.Surface)) < 1E-8), 'Two balls do not strike the same rail pad in sequence');
  end;
  for I := 0 to 100 do
  begin
    T := Merge.Join + (Plan.Cues[Index + 6].Time - Merge.Join) * I / 100;
    P := Aux.Position(T);
    Need((Rail.Heading * (Plan.Position(T).X - P.X) > MarbleRadius + MarbleAuxRadius) and
      (Abs(BallDot(BallSub(P, Hatch.Hinge), Normal) - MarbleAuxRadius) < 1E-8), 'Blue ball leaves the shared rail or overtakes');
  end;
  WriteLn(Format('Merge: %.3f launch, %.3f landing, shared pads %.3f/%.3f and %.3f/%.3f.',
    [Merge.Launch.Time, Merge.Join, Plan.Cues[Index + 4].Time, Merge.Taps[0].Time, Plan.Cues[Index + 5].Time, Merge.Taps[1].Time]));
end;

procedure VerifyPass(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary);
var Pass: TMarblePass; Rail, Carrier: TMarbleLeg; Cue: TMarbleCue; P, Main, Normal: TBallPoint;
  T, Gap, PreviousGap, PassAt: Double; I: Integer;
begin
  Pass := Aux.Merge.Pass;
  Carrier := Plan.Legs[Index + 7];
  Rail := Plan.Legs[Index + 8];
  Need(Carrier.Rollout and (Carrier.Travel.Y < 0) and (Carrier.Start < Pass.SwitchPull) and
    (Pass.SwitchReady < Pass.Fork.Time), 'The blue turnout is not set after the main ball takes its route');
  PreviousGap := Carrier.Heading * (Aux.Position(Pass.Fork.Time).X - Plan.Position(Pass.Fork.Time).X);
  Need(PreviousGap < -0.20, 'Blue ball is already ahead at the fork');
  PassAt := 0;
  for I := 1 to 100 do
  begin
    T := Pass.Fork.Time + (Pass.Rejoin.Start - Pass.Fork.Time) * I / 100;
    P := Aux.Position(T);
    Main := Plan.Position(T);
    Gap := Carrier.Heading * (P.X - Main.X);
    if (PreviousGap < 0) and (Gap >= 0) then
    begin
      Need(P.Y - Main.Y > MarbleRadius + MarbleAuxRadius, 'The overtaking balls are not on separate tracks');
      PassAt := T;
    end;
    PreviousGap := Gap;
  end;
  Need(PassAt > Pass.Fork.Time, 'Blue ball does not pass the main ball on the bypass');
  Need(Carrier.Heading * (Pass.Rejoin.Origin.X - Plan.Position(Pass.Rejoin.Start).X) > 0.33,
    'The second merge does not put the blue ball in front');
  Need(BallLength(BallSub(Pass.Bypass.Position(Pass.Rejoin.Start, Carrier.Heading), Pass.Rejoin.Origin)) < 1E-8,
    'Blue ball jumps between the bypass and the shared rail');
  Normal := BallUnit(BallPoint(-Rail.RailSlope, 1));
  for I := 0 to High(Pass.Taps) do
  begin
    Cue := Plan.Cues[Index + 8 + I];
    P := BallSub(Aux.Position(Pass.Taps[I].Time), BallScale(Normal, MarbleAuxRadius));
    Need((Cue.Device = mdSharedTap) and (Cue.SharedBeat.Time = Pass.Taps[I].Time) and (Cue.SharedBeat.Time < Cue.Time) and
      (BallLength(BallSub(P, Cue.Surface)) < 1E-8), 'Shared pad does not receive the blue ball before the main ball');
  end;
  for I := 0 to 100 do
  begin
    T := Pass.Rejoin.Start + (Pass.Taps[1].Time - Pass.Rejoin.Start) * I / 100;
    P := Aux.Position(T);
    Need((Rail.Heading * (P.X - Plan.Position(T).X) > MarbleRadius + MarbleAuxRadius) and
      (Abs(BallDot(BallSub(P, Pass.Rejoin.Origin), Normal)) < 1E-8), 'Blue ball falls behind or leaves the shared rail too early');
  end;
  WriteLn(Format('Pass: %.3f fork, %.3f order change, %.3f rejoin, shared pads %.3f/%.3f and %.3f/%.3f.',
    [Pass.Fork.Time, PassAt, Pass.Rejoin.Start, Pass.Taps[0].Time, Plan.Cues[Index + 8].Time,
     Pass.Taps[1].Time, Plan.Cues[Index + 9].Time]));
end;

procedure VerifyInterlock(const Rail: TMarbleLeg; const Aux: TMarbleAuxiliary);
var Counter: TMarbleCounter; Interlock, Single: TMarbleInterlock; Link: TMarbleLink;
  H, I: Integer; T, Between: Double; P: TBallPoint;
begin
  Counter := Aux.Merge.Pass.Counter;
  Interlock := Counter.Interlock;
  Link := Interlock.Gate;
  H := Rail.Heading;
  Need((Interlock.Inputs[0].Beat.Time = Rail.Start) and
    (Interlock.Inputs[1].Beat.Time = Counter.DetourBeat.Time), 'Interlock input does not use the two original beats');
  Between := (Interlock.Inputs[0].SeatedAt + Interlock.Inputs[1].Beat.Time) * 0.5;
  Need((Interlock.Inputs[0].Amount(Between) = 1) and (Interlock.Inputs[1].Amount(Between) = 0) and
    (Interlock.Opening(Between) = 0), 'The first latch opens the gate on its own');
  Need((Interlock.Inputs[0].Amount(Link.Pull) = 1) and (Interlock.Inputs[1].Amount(Link.Pull) = 1) and
    (Interlock.Opening(Interlock.Inputs[1].SeatedAt) = 0) and (Interlock.Opening(Link.Ready) = 1),
    'The gate moves before both latches are seated');
  for I := 0 to High(Interlock.Inputs) do
  begin
    Single := Interlock;
    Single.Inputs[I].Beat.Time := Link.Ready + 1;
    Need(Single.Opening(Link.Ready + 0.1) = 0, 'Either missing latch must keep the shutter closed');
  end;
  Need((Link.Ready < Link.Deadline) and (Link.Deadline < Interlock.SmallDeadline) and
    (Interlock.SmallDeadline < Counter.Taps[0].Time), 'The common gate is not clear ahead of both balls');
  Need(Abs(H * (Link.Receiver.X - Rail.Position(Link.Deadline).X) - MarbleRadius - 0.052) < 1E-6,
    'The main ball does not reach the common shutter on the rail');
  P := Aux.Position(Interlock.SmallDeadline);
  Need(Abs(H * (Link.Receiver.X - P.X) - MarbleAuxRadius - 0.052) < 1E-6,
    'The blue ball does not reach the same shutter');
  P := Aux.Position(Interlock.Inputs[1].Beat.Time);
  Need(Abs(BallLength(BallSub(P, Interlock.Inputs[1].Contact)) - MarbleAuxRadius) < 0.005,
    'The lower lever is out of reach');
  for I := 0 to 64 do
  begin
    T := Counter.Start + (Rail.Start - Counter.Start) * I / 64;
    Need(BallLength(BallSub(Aux.Position(T), Interlock.Inputs[0].Contact)) > MarbleAuxRadius,
      'Blue ball hits the upper lever before the main ball');
  end;
  Need((H * (Rail.Position(Rail.Finish).X - Link.Receiver.X) > MarbleRadius) and
    (H * (Aux.Position(Counter.Taps[0].Time).X - Link.Receiver.X) > MarbleAuxRadius),
    'The alternating pads are not beyond the common shutter');
  WriteLn(Format('Interlock: %.3f main lever, %.3f blue lever, %.3f fully open, %.3f main arrival, %.3f blue arrival.',
    [Interlock.Inputs[0].Beat.Time, Interlock.Inputs[1].Beat.Time, Link.Ready, Link.Deadline, Interlock.SmallDeadline]));
end;

procedure VerifyCounter(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary);
var Counter: TMarbleCounter; Rail: TMarbleLeg; Cue: TMarbleCue; P, Main, Normal: TBallPoint;
  T, Gap, PreviousGap, PassedAt: Double; H, I: Integer;
begin
  Counter := Aux.Merge.Pass.Counter;
  Rail := Plan.Legs[Index + 10];
  if Counter.Interlock.Active then VerifyInterlock(Rail, Aux);
  H := Rail.Heading;
  Need((Counter.Start = Aux.Merge.Pass.Taps[1].Time) and (Counter.Gate.Kind = mlShutter) and
    (Counter.Gate.Opening(Counter.Start) = 0) and (Counter.Gate.Pull > Counter.Start) and
    (Counter.Gate.Ready < Rail.Start) and (Rail.Start < Counter.Gate.Deadline) and
    (Counter.Gate.Opening(Counter.Gate.Deadline) = 1), 'Blue lever does not open the main shortcut in time');
  Need(Abs(H * (Counter.Gate.Receiver.X - Rail.Position(Counter.Gate.Deadline).X) - MarbleRadius - 0.052) < 1E-6,
    'Shortcut shutter is not on the main ball path');
  Need(BallLength(BallSub(Counter.Entry, Aux.Merge.Pass.ExitOrigin)) < 1E-9, 'Blue ball jumps at the detour entrance');
  PreviousGap := H * (Plan.Position(Counter.Start).X - Counter.Entry.X);
  Need(PreviousGap < -0.33, 'Main ball is already ahead at the blue lever');
  PassedAt := 0;
  for I := 1 to 160 do
  begin
    T := Counter.Start + (Counter.Rejoin.Start - Counter.Start) * I / 160;
    P := Aux.Position(T);
    Main := Plan.Position(T);
    Gap := H * (Main.X - P.X);
    if (PreviousGap < 0) and (Gap >= 0) then
    begin
      Need(Main.Y - P.Y > MarbleRadius + MarbleAuxRadius + 0.06, 'Main ball passes without vertical clearance');
      PassedAt := T;
    end;
    PreviousGap := Gap;
  end;
  Need((PassedAt > Rail.Start) and (PassedAt < Counter.DetourBeat.Time) and (PreviousGap > 0.33),
    'The main ball does not regain the lead before the next blue beat');
  Normal := BallUnit(BallPoint(-Rail.RailSlope, 1));
  Need(Abs(BallDot(BallSub(Counter.Rejoin.Origin, Rail.Origin), Normal) - MarbleAuxRadius + MarbleRadius) < 1E-8,
    'Blue ball does not return to the same rail');
  for I := 0 to High(Counter.Taps) do
  begin
    Cue := Plan.Cues[Index + 10 + I];
    P := BallSub(Aux.Position(Counter.Taps[I].Time), BallScale(Normal, MarbleAuxRadius));
    Need((Cue.Device = mdSharedTap) and (Cue.SharedBeat.Time = Counter.Taps[I].Time) and
      (Cue.Time < Cue.SharedBeat.Time) and (BallLength(BallSub(P, Cue.Surface)) < 1E-8),
      'Shared pads do not return to main-then-blue order');
  end;
  for I := 0 to 100 do
  begin
    T := Counter.Rejoin.Start + (Plan.Cues[Index + 12].Time - Counter.Rejoin.Start) * I / 100;
    Need(H * (Plan.Position(T).X - Aux.Position(T).X) > MarbleRadius + MarbleAuxRadius,
      'Main ball loses its lead after the counter-pass');
  end;
  WriteLn(Format('Counter-pass: %.3f blue lever, %.3f gate open, %.3f order change, %.3f rejoin, shared pads %.3f/%.3f and %.3f/%.3f.',
    [Counter.Start, Counter.Gate.Ready, PassedAt, Counter.Rejoin.Start,
     Plan.Cues[Index + 10].Time, Counter.Taps[0].Time, Plan.Cues[Index + 11].Time, Counter.Taps[1].Time]));
end;

procedure VerifySeesaw(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary);
var Saw: TMarbleSeesaw; Board: TMarbleBoard; Leg: TMarbleLeg; A, B, C, P: TBallPoint; D, DT, FlightEnd, Mid: Double; Lift: TMarbleWeightLift;
begin
  Saw := Aux.Merge.Pass.Counter.Seesaw;
  Board := Saw.Board;
  Leg := Plan.Legs[Index + 13];
  Need((Leg.Motion = mmSeesaw) and (Plan.Cues[Index + 12].Device = mdSeesaw) and
    (Board.Start = Plan.Cues[Index + 12].Time) and (Board.Stop = Leg.Dock), 'Main contact is not on the seesaw');
  Need((Board.LoadPoint > 0) and (Saw.Seat < 0) and
    (BallLength(BallSub(Leg.Position(Board.Start), Board.PointAt(Board.Start, Board.LoadPoint, MarbleRadius))) < 1E-9) and
    (BallLength(BallSub(Aux.Position(Board.Start), Board.PointAt(Board.Start, Saw.Seat, MarbleAuxRadius))) < 1E-9),
    'The two balls are not supported by opposite sides');
  A := Board.PointAt(Board.Start, Board.Front, 0);
  B := Board.PointAt(Board.Stop, Board.Front, 0);
  C := Board.PointAt(Board.Stop, Board.Rear, 0);
  Need((A.Y - B.Y > 0.20) and (C.Y - Board.PointAt(Board.Start, Board.Rear, 0).Y > 0.20),
    'The main side does not lower and lift the blue side');
  D := Saw.Seat + Saw.SeatSpeed * (Board.Stop - Board.Start);
  Need((BallLength(BallSub(Saw.Launch, Board.PointAt(Board.Stop, D, MarbleAuxRadius))) < 1E-9) and
    (BallLength(BallSub(Saw.LaunchVelocity, Board.VelocityAt(Board.Stop, D, MarbleAuxRadius, Saw.SeatSpeed))) < 1E-9) and
    (Saw.LaunchVelocity.Y > 1.5), 'Launch is disconnected from the moving board');
  Lift := Saw.WeightLift;
  FlightEnd := Saw.CatchRail.Start;
  if Lift.Active then FlightEnd := Saw.Trigger.Time;
  DT := (FlightEnd - Board.Stop) / 4;
  A := Aux.Position(Board.Stop + DT);
  B := Aux.Position(Board.Stop + 2 * DT);
  C := Aux.Position(Board.Stop + 3 * DT);
  Need((Abs(A.X - 2 * B.X + C.X) < 1E-9) and (Abs(A.Y - 2 * B.Y + C.Y + MarbleGravity * Sqr(DT)) < 1E-9),
    'Blue launch does not follow a ballistic arc');
  if Lift.Active then
  begin
    P := Aux.Position(Saw.Trigger.Time);
    Need(Leg.HasWeightLift and (Lift.Arrival < Saw.Trigger.Time) and
      (Saw.Trigger.Time < Lift.Start) and (Lift.Start < Lift.Dock) and
      (Lift.Dock <= Saw.CatchRail.Start), 'Landing does not trigger the occupied lift');
    Need((BallLength(BallSub(P, Saw.Landing)) < 1E-9) and
      (BallLength(BallSub(P, Aux.Position(Saw.Trigger.Time - 1E-5))) < 1E-4) and
      (P.Y < Aux.Position(Saw.Trigger.Time - 0.01).Y), 'The descending ball misses the tray');
    Need((BallLength(BallSub(Leg.Position(Saw.Trigger.Time), Lift.Load)) < 1E-9) and
      (BallLength(BallSub(Leg.Position(Lift.Arrival - 1E-5), Lift.Load)) < 1E-6) and
      (BallLength(Leg.Velocity(Saw.Trigger.Time)) < 1E-9) and
      (BallLength(BallSub(Saw.Pan(Saw.Trigger.Time), Saw.Landing)) < 1E-9),
      'The platforms move before contact or the main ball misses the lift');
    Mid := (Lift.Start + Lift.Dock) / 2;
    A := Leg.Position(Mid);
    B := Aux.Position(Mid);
    Need((Abs(A.X - Lift.Load.X) < 1E-9) and (Abs(B.X - Saw.Landing.X) < 1E-9) and
      (Abs(A.Y - Lift.Load.Y - Lift.Rise / 2) < 1E-9) and
      (Abs(B.Y - Saw.Landing.Y + Lift.Rise / 2) < 1E-9) and
      (Abs(Leg.Rotation(Mid) - Leg.Rotation(Lift.Arrival)) < 1E-9),
      'The two platforms do not carry the balls in opposite directions');
    Need((BallLength(BallSub(Aux.Position(Lift.Dock), Saw.Pan(Lift.Dock))) < 1E-9) and
      (BallLength(BallSub(Leg.Position(Lift.Dock), Lift.Carriage(Lift.Dock))) < 1E-9) and
      (Leg.Heading * (Leg.Position(Leg.Finish).X - A.X) > 0.035) and
      (Leg.Heading * (Aux.Position(Saw.Bell.Time).X - B.X) > 0.19) and
      (Saw.Bell.Time < Plan.Cues[Index + 14].Time), 'The balls do not roll out to their next contacts');
    if Saw.TrayRelease.Active then
    begin
      Need((Plan.Cues[Index + 13].Device = mdTrayRelease) and
        (Saw.TrayRelease.Lever.Beat.Time = Leg.Finish) and
        (BallLength(BallSub(Saw.TrayRelease.Lever.Contact, BallAdd(Leg.Position(Leg.Finish),
          BallPoint(Leg.Heading * MarbleRadius, 0)))) < 1E-9), 'The main ball misses the release lever');
      Need((Lift.Dock < Saw.TrayRelease.Lever.Beat.Time) and
        (Saw.TrayRelease.Start >= Saw.TrayRelease.Lever.SeatedAt) and
        (Saw.TrayRelease.Start < Saw.CatchRail.Start) and (Saw.CatchRail.Start < Saw.Bell.Time) and
        (Saw.TrayRelease.AngleAt(Saw.TrayRelease.Lever.Beat.Time) = 0) and
        (BallLength(BallSub(Aux.Position(Saw.TrayRelease.Start), Saw.Pan(Lift.Dock))) < 1E-9),
        'The tray tilts or loses the small ball before the lever is pressed');
      Mid := (Saw.TrayRelease.Start + Saw.CatchRail.Start) / 2;
      A := Aux.Position(Mid);
      Need((Saw.TrayRelease.AngleAt(Mid) < -0.40) and (Leg.Heading * (A.X - B.X) > 0.035) and
        (BallLength(BallSub(A, Saw.TrayPoint(Mid, Saw.TrayRelease.DistanceAt(Mid), MarbleAuxRadius))) < 1E-9),
        'The small ball does not roll while supported by the tipped tray');
      DT := 1E-5;
      A := Aux.Position(Saw.CatchRail.Start - DT);
      B := Aux.Position(Saw.CatchRail.Start);
      C := Aux.Position(Saw.CatchRail.Start + DT);
      Need((BallLength(BallSub(B, Saw.TrayPoint(Saw.CatchRail.Start, MarbleTrayNose, MarbleAuxRadius))) < 1E-9) and
        (BallLength(BallSub(BallSub(C, B), BallSub(B, A))) < 1E-8) and
        (BallLength(BallSub(Aux.Position(Saw.Bell.Time), B)) > 0.12), 'The tray and the next rail are disconnected');
      WriteLn(Format('Receiving tray: %.3f main lever, %.3f tray tips, %.3f blue rolls onto next rail, %.3f bell, %.3f main.',
        [Leg.Finish, Saw.TrayRelease.Start, Saw.CatchRail.Start, Saw.Bell.Time, Plan.Cues[Index + 14].Time]));
    end
    else Need(Lift.Dock = Saw.CatchRail.Start, 'Original lift has a delayed release');
    if Saw.SwitchLever.Beat.Time > 0 then
      WriteLn(Format('Receiving tray: blue leaves at %.3f and reaches the branch lever at %.3f.',
        [Saw.CatchRail.Start, Saw.Bell.Time]));
    WriteLn(Format('Weight lift: %.3f launch, %.3f main boards, %.3f blue lands, %.3f dock, %.3f main, %.3f blue bell.',
      [Board.Stop, Lift.Arrival, Saw.Trigger.Time, Lift.Dock, Leg.Finish, Saw.Bell.Time]));
    Exit;
  end;
  P := Aux.Position(Saw.Trigger.Time);
  Need((Board.Stop < Saw.Trigger.Time) and (Saw.Trigger.Time < Saw.CatchRail.Start) and
    (P.Y > Saw.Launch.Y) and (Abs(BallLength(BallSub(P, Saw.LeverContact)) - MarbleAuxRadius) < 0.005),
    'Blue ball does not touch the lever in flight');
  P := Leg.Position(Saw.Gate.Deadline);
  Need((Saw.Trigger.Time < Saw.Gate.Pull) and (Saw.Gate.Ready < Saw.Gate.Deadline) and
    (Abs(Leg.Heading * (Saw.Gate.Receiver.X - P.X) - MarbleRadius - 0.052) < 1E-6),
    'The airborne lever does not clear the main route in time');
  Need((Saw.CatchRail.Start < Saw.Bell.Time) and (Saw.Bell.Time < Plan.Cues[Index + 14].Time),
    'Blue ball does not roll to its next contact');
  WriteLn(Format('Seesaw: %.3f main loads, %.3f blue launches, %.3f air lever, %.3f landing, %.3f bell.',
    [Board.Start, Board.Stop, Saw.Trigger.Time, Saw.CatchRail.Start, Saw.Bell.Time]));
end;

procedure VerifyJunction(Plan: TMarblePlan; Index: Integer; const Aux: TMarbleAuxiliary);
var Saw: TMarbleSeesaw; Leg: TMarbleLeg; J: TMarbleJunction; H, I: Integer; A, B, P: TBallPoint; T: Double;
begin
  Saw := Aux.Merge.Pass.Counter.Seesaw;
  Leg := Plan.Legs[Index + 14];
  J := Leg.Junction;
  H := Leg.Heading;
  P := Aux.Position(Saw.SwitchLever.Beat.Time);
  Need(J.Active and (Saw.SwitchLever.Beat.Time = Saw.Bell.Time) and
    (BallLength(BallSub(Saw.SwitchLever.Contact, BallAdd(P, BallPoint(H * MarbleAuxRadius, 0)))) < 1E-9),
    'The small ball misses the branch lever');
  Need((J.Pull > Saw.SwitchLever.Beat.Time) and (J.Ready < J.Branch.Start) and (J.Branch.Start < Leg.Finish) and
    (H * (J.Branch.Origin.X - Leg.Position(J.Ready).X) > MarbleRadius),
    'The branch rail has not turned before the main ball enters');
  A := J.Tip(Saw.Bell.Time - 0.01, H);
  B := J.Tip(J.Pull, H);
  Need((BallLength(BallSub(A, B)) < 1E-9) and
    (BallLength(BallSub(B, J.Tip(J.Ready, H))) > 0.19), 'The rail does not rotate from one exit to the other');
  P := Leg.Position(J.Branch.Start - 0.00001);
  A := Leg.Position(J.Branch.Start);
  B := Leg.Position(Leg.Finish);
  Need((BallLength(BallSub(P, A)) < 0.00008) and
    (BallLength(BallSub(B, A)) > MarbleJunctionSpan) and
    (Abs((B.Y - A.Y) / (H * (B.X - A.X)) - J.Branch.Grade) < 1E-9) and
    (Abs(J.Branch.Grade - Leg.Grade) > 0.15), 'The main ball does not enter and follow the selected rail');
  Leg.RailSupport(A, B);
  Need(H * (A.X - Saw.WeightLift.Load.X) > MarbleRadius, 'A fixed rail intrudes into the moving lift');
  WriteLn(Format('Rotating branch: %.3f blue lever, %.3f rail aligned, %.3f main enters.',
    [Saw.Bell.Time, J.Ready, J.Branch.Start]));
  if Saw.ExitBell.Time = 0 then Exit;
  P := Aux.Position(Saw.ExitGate.Deadline);
  Need((Plan.Cues[Index + 14].Device = mdJunctionGate) and (Saw.ExitGate.Kind = mlShutter) and
    (Leg.Finish < Saw.ExitGate.Pull) and (Saw.ExitGate.Ready < Saw.ExitGate.Deadline) and
    (Saw.ExitGate.Deadline < Saw.ExitBell.Time) and
    (Abs(H * (Saw.ExitGate.Receiver.X - P.X) - MarbleAuxGateNose) < 1E-6) and
    (H * (Aux.Position(Saw.ExitBell.Time).X - P.X) > 0.20), 'Main ball does not open the gate before the small ball reaches the wheel');
  for I := 0 to 1 do
  begin
    T := Saw.ExitCurveStart;
    if I = 1 then T := Saw.ExitRail.Start;
    A := Aux.Position(T - 0.0001);
    P := Aux.Position(T);
    B := Aux.Position(T + 0.0001);
    Need(BallLength(BallSub(BallSub(B, P), BallSub(P, A))) < 1E-7, 'The blue ball snaps between rail slopes');
  end;
  WriteLn(Format('After the branch: %.3f main lever, %.3f gate open, %.3f blue wheel bell, %.3f main.',
    [Leg.Finish, Saw.ExitGate.Ready, Saw.ExitBell.Time, Plan.Cues[Index + 15].Time]));
end;

procedure VerifyDuet(Plan: TMarblePlan; Audio: TRhythmAudio; Index: Integer; const Aux: TMarbleAuxiliary);
var Times: array[0..30] of Double; Hit, I, Last: Integer; Beat: TMarbleBeat; T: Double;
  Camera, Main, P, Previous: TBallPoint;
  Gate: TMarbleLink; Counter: TMarbleCounter; Saw: TMarbleSeesaw;
begin
  Times[0] := Plan.Cues[Index].Time;
  Times[1] := Aux.Strike;
  Times[2] := Plan.Cues[Index + 1].Time;
  Times[3] := Aux.Bell.Time;
  Times[4] := Plan.Cues[Index + 2].Time;
  Last := 4;
  if Aux.Reciprocal then
  begin
    Last := 6;
    Times[3] := Aux.SecondStrike.Time;
    Times[5] := Aux.Bell.Time;
    Times[6] := Plan.Cues[Index + 3].Time;
    for I := 0 to High(Aux.AuxGates) do
    begin
      Gate := Aux.AuxGates[I];
      T := Times[2 + I * 2];
      P := Aux.Position(Gate.Deadline);
      Need((Gate.Kind = mlShutter) and (Gate.Opening(T) = 0) and (Gate.Pull > T) and
        (Gate.Ready < Gate.Deadline) and (Gate.Deadline < Times[3 + I * 2]) and (Gate.Opening(Gate.Deadline) = 1),
        'Upper gate does not open between the main trigger and the blue ball');
      Need(Abs(Gate.Heading * (Gate.Receiver.X - P.X) - MarbleAuxGateNose) < 1E-8,
        'Upper gate is not in the path of the blue ball');
      Need(Plan.Links[Index + I + 1].Kind = mlNone, 'Main trigger also operates an unrelated shutter');
    end;
    VerifyBridge(Plan.Legs[Index + 2], Aux.SecondStrike.Time);
    if Aux.Crossover then VerifyCrossover(Plan, Index, Aux);
    WriteLn(Format('Reply bridge: %.3f lever, %.3f ready, %.3f main ball at gap.',
      [Aux.SecondStrike.Time, Plan.Legs[Index + 2].Bridge.Ready, Plan.Legs[Index + 2].Bridge.Deadline]));
  end;
  if Aux.Merge.Active then
  begin
    VerifyMerge(Plan, Index, Aux);
    Last := 12;
    Times[7] := Aux.Merge.Launch.Time;
    Times[8] := Plan.Cues[Index + 4].Time;
    Times[9] := Aux.Merge.Taps[0].Time;
    Times[10] := Plan.Cues[Index + 5].Time;
    Times[11] := Aux.Merge.Taps[1].Time;
    Times[12] := Plan.Cues[Index + 6].Time;
  end;
  if Aux.Merge.Pass.Active then
  begin
    VerifyPass(Plan, Index, Aux);
    Last := 18;
    Times[13] := Aux.Merge.Pass.Fork.Time;
    Times[14] := Plan.Cues[Index + 7].Time;
    Times[15] := Aux.Merge.Pass.Taps[0].Time;
    Times[16] := Plan.Cues[Index + 8].Time;
    Times[17] := Aux.Merge.Pass.Taps[1].Time;
    Times[18] := Plan.Cues[Index + 9].Time;
  end;
  Counter := Aux.Merge.Pass.Counter;
  if Counter.Active then
  begin
    VerifyCounter(Plan, Index, Aux);
    Last := 24;
    Times[19] := Counter.DetourBeat.Time;
    Times[20] := Plan.Cues[Index + 10].Time;
    Times[21] := Counter.Taps[0].Time;
    Times[22] := Plan.Cues[Index + 11].Time;
    Times[23] := Counter.Taps[1].Time;
    Times[24] := Plan.Cues[Index + 12].Time;
  end;
  Saw := Counter.Seesaw;
  if Saw.Active then
  begin
    VerifySeesaw(Plan, Index, Aux);
    Last := 28;
    Times[25] := Saw.Trigger.Time;
    Times[26] := Plan.Cues[Index + 13].Time;
    Times[27] := Saw.Bell.Time;
    Times[28] := Plan.Cues[Index + 14].Time;
    if Saw.SwitchLever.Beat.Time > 0 then VerifyJunction(Plan, Index, Aux);
    if Saw.ExitBell.Time > 0 then
    begin
      Last := 30;
      Times[29] := Saw.ExitBell.Time;
      Times[30] := Plan.Cues[Index + 15].Time;
    end;
  end;
  Hit := 0;
  for I := 0 to Last do
  begin
    if I > 0 then Need(Times[I] > Times[I - 1], 'Duet does not alternate');
    while (Hit < Length(Audio.Hits)) and (Audio.Hits[Hit].Time < Times[I]) do Inc(Hit);
    Need((Hit < Length(Audio.Hits)) and (Audio.Hits[Hit].Time = Times[I]), 'Duet moves an original onset');
    Need((Plan.BeatAt(Times[I], Beat) = Index * 2 + I) and (Beat.Time = Times[I]),
      'An alternating hit is missing from the activity track');
  end;
  Need(BallLength(BallSub(Aux.Position(Aux.Strike + 0.04), Aux.Receiver)) > 0.035,
    'The second ball stops at the bridge lever');
  Need((Aux.Finish > Aux.Bell.Time + 0.15) and
    (BallLength(BallSub(Aux.Position(Aux.Finish), Aux.Position(Aux.Bell.Time))) > 0.16),
    'The second ball does not keep rolling after the bell');
  for I := 0 to 360 do
  begin
    T := Times[0] + (Times[Last] - Times[0]) * I / 360;
    Camera := Plan.CameraTarget(T);
    Main := Plan.Position(T);
    P := Aux.Position(T);
    Need((Abs(Camera.X - P.X) < 2.9 - MarbleAuxRadius) and (Abs(Camera.X - Main.X) < 2.9 - MarbleRadius) and
      InRange(Camera.Y + 3.75 * 0.54 - P.Y, MarbleAuxRadius, 3.75 - MarbleAuxRadius) and
      InRange(Camera.Y + 3.75 * 0.54 - Main.Y, MarbleRadius, 3.75 - MarbleRadius) and
      (BallLength(BallSub(P, Main)) > MarbleRadius + MarbleAuxRadius),
      'The two balls do not fit together in the camera');
  end;
  Previous := Aux.Receiver;
  for I := 1 to 50 do
  begin
    T := Aux.Strike + (Aux.Finish - Aux.Strike) * I / 50;
    P := Aux.Position(T);
    if Saw.WeightLift.Active and InRange(T, Saw.Trigger.Time,
      Max(Saw.WeightLift.Dock, Saw.TrayRelease.Start)) then
      Need((P.X - Previous.X) * (Aux.Receiver.X - Aux.Origin.X) >= -1E-9, 'The second ball reverses on the tray')
    else
      Need((P.X - Previous.X) * (Aux.Receiver.X - Aux.Origin.X) > 0, 'The second ball stops or reverses on the upper rail');
    Previous := P;
  end;
  if Saw.SwitchLever.Beat.Time > 0 then
    WriteLn(Format('Branch relay (%d contacts): %.3f to %.3f.', [Last + 1, Times[0], Times[Last]]))
  else if Saw.WeightLift.Active then
    WriteLn(Format('Weight lift relay (29 contacts): %.3f to %.3f.', [Times[0], Times[Last]]))
  else if Saw.Active then
    WriteLn(Format('Seesaw relay (29 contacts): %.3f to %.3f.', [Times[0], Times[Last]]))
  else if Counter.Active then
    WriteLn(Format('Counter relay (25 contacts): %.3f to %.3f.', [Times[0], Times[Last]]))
  else if Aux.Merge.Pass.Active then
    WriteLn(Format('Passing relay (19 contacts): %.3f to %.3f.', [Times[0], Times[Last]]))
  else if Aux.Merge.Active then
    WriteLn(Format('Merge relay (13 contacts): %.3f to %.3f.', [Times[0], Times[Last]]))
  else if Aux.Reciprocal then
    WriteLn(Format('Reciprocal (7 contacts): %.3f / %.3f / %.3f / %.3f / %.3f / %.3f / %.3f',
      [Times[0], Times[1], Times[2], Times[3], Times[4], Times[5], Times[6]]))
  else WriteLn(Format('Duet (5 contacts): %.3f / %.3f / %.3f / %.3f / %.3f',
    [Times[0], Times[1], Times[2], Times[3], Times[4]]));
end;

procedure VerifyLinks(Plan: TMarblePlan; Audio: TRhythmAudio; RequireSpring: Boolean);
var I, Shutters, Latches, Bridges, Auxiliary, Duets, Reciprocal, Crossovers, Merges, Passes, Counters, Interlocks, Seesaws, WeightLifts, TrayReleases, Junctions, WheelBells: Integer;
  Link: TMarbleLink; Leg: TMarbleLeg;
  Bridge: TMarbleBridge;
begin
  Shutters := 0;
  Latches := 0;
  Bridges := 0;
  Auxiliary := 0;
  Duets := 0;
  Reciprocal := 0;
  Crossovers := 0;
  Merges := 0;
  Passes := 0;
  Counters := 0;
  Interlocks := 0;
  Seesaws := 0;
  WeightLifts := 0;
  TrayReleases := 0;
  Junctions := 0;
  WheelBells := 0;
  Need(Length(Plan.Links) = Length(Plan.Cues), 'Link source index missing');
  for I := 0 to High(Plan.Links) do
  begin
    Link := Plan.Links[I];
    if Link.Kind = mlNone then Continue;
    Need((Link.Target >= I) and (Link.Target <= I + 1) and (Link.Target <= High(Plan.Cues)), 'Invalid link target');
    Need((Link.Pull >= Plan.Cues[I].Time) and (Link.Opening(Plan.Cues[I].Time - 1E-7) = 0),
      'Receiver opens before the ball hits its driver');
    Need((Link.Pull < Link.Ready) and (Link.Ready < Link.Deadline) and (Link.Opening(Link.Deadline) = 1),
      'Ball reaches a closed receiver');
    Need(InRange(Link.Opening((Link.Pull + Link.Ready) * 0.5), 0.49, 0.51), 'Link does not travel between its endpoints');
    if Link.Kind = mlShutter then
    begin
      Inc(Shutters);
      Leg := Plan.Legs[Link.Target + 1];
      Need((Leg.Motion = mmRail) and InRange(Link.Deadline, Leg.Start, Leg.Finish) and
        (Abs(Leg.Heading * (Link.Receiver.X - Leg.Position(Link.Deadline).X) - MarbleRadius - 0.052) < 1E-5),
        'Receiver is not over the running rail');
      Bridge := Leg.Bridge;
      if Bridge.Active then
      begin
        if Bridge.Auxiliary.Active then
        begin
          VerifyAuxiliary(Plan, Link, Leg);
          if Auxiliary = 0 then WriteLn(Format('First auxiliary chain: %.3f lever, %.3f gate up, %.3f release, %.3f strike, %.3f bridge ready, %.3f main ball at gap.',
            [Plan.Cues[I].Time, Link.Ready, Bridge.Auxiliary.Release, Bridge.Auxiliary.Strike, Bridge.Ready, Bridge.Deadline]));
          Inc(Auxiliary);
          if Bridge.Auxiliary.Duet then
          begin
            VerifyDuet(Plan, Audio, I, Bridge.Auxiliary);
            Inc(Duets);
            if Bridge.Auxiliary.Reciprocal then Inc(Reciprocal);
            if Bridge.Auxiliary.Crossover then Inc(Crossovers);
            if Bridge.Auxiliary.Merge.Active then Inc(Merges);
            if Bridge.Auxiliary.Merge.Pass.Active then Inc(Passes);
            if Bridge.Auxiliary.Merge.Pass.Counter.Active then Inc(Counters);
            if Bridge.Auxiliary.Merge.Pass.Counter.Interlock.Active then Inc(Interlocks);
            if Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.Active then Inc(Seesaws);
            if Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.WeightLift.Active then Inc(WeightLifts);
            if Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.TrayRelease.Active then Inc(TrayReleases);
            if Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.SwitchLever.Beat.Time > 0 then Inc(Junctions);
            if Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.ExitBell.Time > 0 then Inc(WheelBells);
          end;
        end
        else
        begin
          if Bridges = 0 then WriteLn(Format('First three-stage chain: %.3f lever, %.3f gate up, %.3f bridge ready, %.3f ball at gap.',
            [Plan.Cues[I].Time, Link.Ready, Bridge.Ready, Bridge.Deadline]));
          Inc(Bridges);
        end;
        VerifyBridge(Leg, Link.Ready);
      end;
    end
    else
    begin
      Inc(Latches);
      Need((Plan.Cues[I].Device = mdChute) and (Plan.Cues[Link.Target].Device = mdSpring) and
        (Link.Deadline = Plan.Cues[Link.Target].Time), 'Latch does not release the landing spring');
    end;
  end;
  Need(Shutters >= 2, 'No repeated shutter chain');
  Need(Bridges >= 1, 'No three-stage chain');
  Need(Auxiliary >= 1, 'No auxiliary ball makes a bridge');
  if RequireSpring then
  begin
    Need(Latches >= 1, 'No spring-latch chain in demo');
    Need(Reciprocal >= 1, 'No reciprocal chain in demo');
    Need(Crossovers >= 1, 'No vertical swap in demo');
    Need(Merges >= 1, 'No spring return to the main rail in demo');
    Need(Passes >= 1, 'No overtaking bypass in demo');
    Need(Counters >= 1, 'No counter-pass in demo');
    Need(Interlocks >= 1, 'No two-lever shutter in demo');
    Need(Seesaws >= 1, 'No seesaw launch in demo');
    Need(WeightLifts >= 1, 'No weight lift in demo');
    Need(TrayReleases >= 1, 'No lever-driven receiving tray in demo');
    Need(Junctions >= 1, 'No rotating junction in demo');
    Need(WheelBells >= 1, 'No alternating gate and wheel bell after the branch');
  end;
  WriteLn('Causal mechanisms: ', Shutters, ' shutters, ', Latches, ' spring latches, ', Bridges,
    ' three-stage chains, ', Auxiliary, ' auxiliary-ball bridges, ', Duets - Reciprocal,
    ' short duets, ', Reciprocal - Crossovers, ' reciprocal chains, ', Crossovers - Merges, ' crossovers, ',
    Merges - Passes, ' merges, ', Passes - Counters, ' passes, ', Counters - Interlocks,
    ' counter-passes, ', Interlocks - Seesaws, ' interlocks, ', Seesaws - WeightLifts, ' seesaws, ', WeightLifts, ' weight lifts, ', TrayReleases, ' lever-driven trays, ',
    Junctions, ' rotating junctions, ', WheelBells, ' wheel bells.');
  WriteLn('Synchronized contacts across both balls: ', Length(Plan.Cues) + (Duets + Seesaws) * 2 + Reciprocal + (Merges + Passes + Counters) * 3 + WheelBells,
    '/', Length(Audio.Hits));
end;

procedure VerifyEdges;
var Audio: TRhythmAudio; Plan: TMarblePlan; I: Integer;
begin
  Audio := TRhythmAudio.Create;
  try
    Audio.Duration := 0.15;
    Plan := BuildMarblePlan(Audio, nil);
    try
      Need((Length(Plan.Legs) = 0) and (Plan.Position(10).X = 0), 'Silent input moves');
    finally
      Plan.Free;
    end;
    Audio.Duration := 3000;
    SetLength(Audio.Hits, 4);
    Audio.Hits[0].Time := 0;
    Audio.Hits[1].Time := 0.015;
    Audio.Hits[2].Time := 0.050;
    Audio.Hits[3].Time := 2999.99;
    Plan := BuildMarblePlan(Audio, nil);
    try
      Need(Length(Plan.Cues) = 2, 'Close sounds stack solid objects');
      Need(Plan.Legs[1].Motion = mmRail, 'Long gap creates long free fall');
      for I := 0 to 3000 do Need(Plan.Position(I).X >= 0, 'Invalid long-gap position');
      Need(Plan.EndTime > Audio.Duration, 'Goal is clipped at the last sound');
    finally
      Plan.Free;
    end;
  finally
    Audio.Free;
  end;
end;

function RailGap(const P, A, B: TBallPoint): Double;
var D, Q: TBallPoint; U: Double;
begin
  D := BallSub(B, A);
  Q := BallSub(P, A);
  U := EnsureRange(BallDot(Q, D) / Max(1E-12, BallDot(D, D)), 0.0, 1.0);
  Result := BallLength(BallSub(Q, BallScale(D, U)));
end;

procedure VerifyCourseView(Plan: TMarblePlan);
var I, J, K: Integer; T: Double; Leg, Rail: TMarbleLeg; P, Camera, A, B: TBallPoint; Aux: TMarbleAuxiliary;
begin
  for I := 0 to High(Plan.Legs) do
  begin
    Leg := Plan.Legs[I];
    for J := 0 to 30 do
    begin
      T := Leg.Start + (Leg.Finish - Leg.Start) * J / 30;
      P := Plan.Position(T);
      Camera := Plan.CameraTarget(T);
      // 最も狭い縦の画角（世界座標3.75）で、球全体が画面内に収まる。
      Need(InRange(Camera.Y + 3.75 * 0.54 - P.Y, MarbleRadius, 3.75 - MarbleRadius),
        Format('Ball out of camera at %.3f', [T]));
      Need(Abs(P.X - Camera.X) < 0.35, 'Horizontal camera falls behind');
      for K := Max(0, I - 24) to Min(High(Plan.Legs), I + 24) do
      begin
        Rail := Plan.Legs[K];
        Aux := Rail.Bridge.Auxiliary;
        if Aux.Active then
          Need(RailGap(P, Aux.Origin, Aux.Receiver) >= MarbleRadius + MarbleAuxRadius,
            Format('Main ball crosses an auxiliary route at %.3f (leg %d near %d)', [T, I, K]));
        if Aux.Crossover then
        begin
          B := Aux.Position(Aux.Finish);
          if Aux.Merge.Active then B := Aux.Merge.LaunchPoint;
          Need((RailGap(P, Aux.Receiver, Aux.DropOrigin) >= MarbleRadius + MarbleAuxRadius) and
            (RailGap(P, Aux.Landing, B) >= MarbleRadius + MarbleAuxRadius),
            Format('Main ball crosses a crossover rail at %.3f (leg %d near %d)', [T, I, K]));
        end
        else if Aux.Duet then
          Need(RailGap(P, Aux.Receiver, Aux.Position(Aux.Finish)) >= MarbleRadius + MarbleAuxRadius,
            Format('Main ball crosses the auxiliary continuation at %.3f (leg %d near %d)', [T, I, K]));
        if Abs(K - I) <= 1 then Continue;
        if Rail.Motion <> mmRail then Continue;
        Rail.RailSupport(A, B);
        Need(RailGap(P, A, B) >= MarbleRadius - 0.008,
          Format('Leg %d/%d (%.3f–%.3f) crosses rail %d (%.3f–%.3f) at %.3f, clearance %.3f',
            [I, Ord(Leg.Motion), Leg.Start, Leg.Finish, K, Rail.Start, Rail.Finish, T, RailGap(P, A, B)]));
      end;
    end;
  end;
end;

procedure VerifyVariedTempo;
const Gaps: array[0..8] of Double = (0.15, 0.19, 0.27, 0.33, 0.45, 0.56, 0.72, 0.82, 1.21);
var Audio: TRhythmAudio; Plan: TMarblePlan; Cue: TMarbleCue; Leg: TMarbleLeg; Seed, I, Bridges, Auxiliary, Duets: Integer; Time: Double;
  Seen: set of TMarbleDevice;
begin
  Audio := TRhythmAudio.Create;
  try
    SetLength(Audio.Hits, 81);
    for Seed := 0 to 12 do
    begin
      Time := 0.25;
      for I := 0 to High(Audio.Hits) do
      begin
        Audio.Hits[I].Time := Time;
        if Seed = 0 then Time := Time + 0.18
        else Time := Time + Gaps[(I * 11 + Seed * 7 + I * I * Seed) mod Length(Gaps)];
      end;
      Audio.Duration := Time + 0.3;
      Plan := BuildMarblePlan(Audio, nil);
      try
        try
          VerifyCourseView(Plan);
        except
          on E: Exception do raise Exception.CreateFmt('Tempo fixture %d: %s', [Seed, E.Message]);
        end;
        if Seed = 0 then
        begin
          Seen := [];
          for Cue in Plan.Cues do Include(Seen, Cue.Device);
          Need([mdBend, mdLift, mdShuttle, mdSwing, mdChute] <= Seen, 'Dense input loses the new mechanisms');
          Bridges := 0;
          Auxiliary := 0;
          Duets := 0;
          for Leg in Plan.Legs do
          begin
            if Leg.Bridge.Auxiliary.Active then Inc(Auxiliary)
            else if Leg.Bridge.Active then Inc(Bridges);
            if Leg.Bridge.Auxiliary.Duet then Inc(Duets);
          end;
          Need(Length(Plan.Cues) + 2 * Duets >= 57, 'Dense input skips too many original sounds');
          Need(Bridges > 0, 'Dense input never makes time for a third mechanism');
          Need(Auxiliary > 0, 'Dense input never makes time for the second ball');
          Need(Duets > 0, 'Dense input never makes time for an alternating chain');
        end;
      finally
        Plan.Free;
      end;
    end;
  finally
    Audio.Free;
  end;
end;

procedure VerifyLegacy(Audio: TRhythmAudio);
var Ref: TRhythmPlanRef; OldPlan, Restored: TMarblePlan; Cue: TMarbleCue; Leg: TMarbleLeg; Version, Fixture: Integer;
  Auxiliary, Duet, Reciprocal, Crossover, Merge, Pass, Counter, Interlock, Seesaw, WeightLift, TrayRelease: Boolean;
begin
  OldPlan := TMarblePlan.Create;
  try
    OldPlan.Duration := Audio.Duration;
    SetLength(OldPlan.Cues, 16);
    for var I := 0 to High(OldPlan.Cues) do
    begin
      OldPlan.Cues[I].Time := 0.25 + I * 0.5;
      if I >= 2 then OldPlan.Cues[I].Time := OldPlan.Cues[I].Time + 0.5;
    end;
    for Fixture := 1 to 17 do
    begin
      Version := Min(Fixture, 16);
      if Version = 6 then
      begin
        OldPlan.Cues[1].RelayBeat.Time := 1.25;
        OldPlan.Cues[2].RelayBeat.Time := 2.25;
        for var I := 3 to High(OldPlan.Cues) do OldPlan.Cues[I].Time := OldPlan.Cues[I].Time + 0.5;
      end;
      if Version = 7 then
      begin
        OldPlan.Cues[3].RelayBeat.Time := 3.25;
        for var I := 4 to High(OldPlan.Cues) do OldPlan.Cues[I].Time := OldPlan.Cues[I].Time + 0.5;
      end;
      if Version = 9 then
      begin
        OldPlan.Cues[4].RelayBeat.Time := 4.25;
        OldPlan.Cues[5].RelayBeat.Time := 5.25;
        OldPlan.Cues[6].RelayBeat.Time := 6.25;
        for var I := 5 to High(OldPlan.Cues) do OldPlan.Cues[I].Time := OldPlan.Cues[I].Time + 0.5 * Min(I - 4, 3);
      end;
      if Version = 10 then
      begin
        OldPlan.Cues[7].RelayBeat.Time := 7.25;
        OldPlan.Cues[8].RelayBeat.Time := 8.25;
        OldPlan.Cues[9].RelayBeat.Time := 9.25;
        for var I := 8 to High(OldPlan.Cues) do OldPlan.Cues[I].Time := OldPlan.Cues[I].Time + 0.5 * Min(I - 7, 3);
      end;
      if Version = 11 then
      begin
        OldPlan.Cues[10].RelayBeat.Time := 10.25;
        OldPlan.Cues[11].RelayBeat.Time := 11.25;
        OldPlan.Cues[12].RelayBeat.Time := 12.25;
        for var I := 11 to High(OldPlan.Cues) do OldPlan.Cues[I].Time := OldPlan.Cues[I].Time + 0.5 * Min(I - 10, 3);
      end;
      if Version = 13 then
      begin
        OldPlan.Cues[13].RelayBeat.Time := 13.25;
        OldPlan.Cues[14].RelayBeat.Time := 14.25;
        for var I := 14 to High(OldPlan.Cues) do OldPlan.Cues[I].Time := OldPlan.Cues[I].Time + 0.5 * Min(I - 13, 2);
      end;
      // This shorter interval leaves time for the lift but not for the lever and tray rollout.
      if Fixture = 16 then OldPlan.Cues[14].RelayBeat.Time := 14.05;
      // An earlier beat fits the airborne lever, but not a descending landing.
      if Fixture = 17 then
      begin
        OldPlan.Cues[13].RelayBeat.Time := 13.15;
        OldPlan.Cues[14].RelayBeat.Time := 14.25;
      end;
      Ref := NewPlanRef(Audio.Key, Audio.Sensitivity, 0, rsMarbleRelay);
      Ref.Version := Version;
      // Keep the synthetic compatibility plans separate from the live prepare/render fixture.
      Ref.AudioDensity := AudioDensityKey(rsMarbleRelay, Fixture);
      Ref.Key := THashSHA2.GetHashString('marble-relay-v' + IntToStr(Version) + '|' + Audio.Key + '|' +
        IntToStr(Audio.Sensitivity) + '|0|density=' + IntToStr(Ref.AudioDensity));
      Ref.SourceRevision := Audio.SourceRevision;
      SaveMarblePlan(OldPlan, Audio, Ref);
      Restored := LoadMarblePlan(Ref, Audio, 0);
      try
        Need(Restored.Version = Version, 'Wrong legacy plan version');
        Auxiliary := False;
        Duet := False;
        Reciprocal := False;
        Crossover := False;
        Merge := False;
        Pass := False;
        Counter := False;
        Interlock := False;
        Seesaw := False;
        WeightLift := False;
        TrayRelease := False;
        for Leg in Restored.Legs do
        begin
          if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.Active then Seesaw := True;
          if Leg.HasWeightLift then WeightLift := True;
          if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.TrayRelease.Active then TrayRelease := True;
          Need(not Leg.Junction.Active, 'A branch remains without a small ball at its lever');
          if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Interlock.Active then Interlock := True;
          if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Active then Counter := True;
          if Leg.Bridge.Auxiliary.Merge.Pass.Active then Pass := True;
          if Leg.Bridge.Auxiliary.Merge.Active then Merge := True;
          if Leg.Bridge.Auxiliary.Crossover then Crossover := True;
          if Leg.Bridge.Auxiliary.Reciprocal then Reciprocal := True;
          if Leg.Bridge.Auxiliary.Duet then Duet := True;
          if Version < 5 then Need(not Leg.Bridge.Auxiliary.Active, 'Older plan gained a second ball');
          if Leg.Bridge.Auxiliary.Active then Auxiliary := True;
          if Version < 4 then Need(not Leg.Bridge.Active, 'Older plan gained a tilting tray');
        end;
        if Version = 5 then Need(Auxiliary, 'Version 5 loses its original second-ball bridge');
        Need(Duet = (Version >= 6), 'Legacy plan changes its duet');
        Need(Reciprocal = (Version >= 7), 'Legacy plan changes its reciprocal chain');
        Need(Crossover = (Version >= 8), 'Legacy plan changes its crossover');
        Need(Merge = (Version >= 9), 'Legacy plan changes its merge');
        Need(Pass = (Version >= 10), 'Legacy plan changes its overtaking bypass');
        Need(Counter = (Version >= 11), 'Legacy plan changes its counter-pass');
        Need(Interlock = (Version >= 12), 'Legacy plan changes its two-lever shutter');
        Need(Seesaw = (Version >= 13), 'Seesaw recipe changed');
        Need(WeightLift = (Fixture in [14, 15, 16]), 'The original lift recipe changed');
        Need(TrayRelease = (Fixture = 15), 'The original tray recipe changed');
        if Version < 3 then
        begin
          Need(Length(Restored.Links) = 0, 'Older plan gained new links');
          for Leg in Restored.Legs do Need(not Leg.Rollout, 'Older plan gained a rolling exit');
        end;
        if Version = 1 then
        begin
          Need(Abs(Restored.Legs[0].Terminal - 3.9) < 1E-9, 'Old rail recipe changed');
          for Cue in Restored.Cues do
            Need((Cue.Heading = 1) and (Cue.Device <= mdGoal), 'Old plan uses a new mechanism');
        end;
      finally
        Restored.Free;
      end;
    end;
  finally
    OldPlan.Free;
  end;
end;

procedure VerifyAppearance(const Folder: string; const Ref: TRhythmPlanRef; Plan: TMarblePlan;
  Audio: TRhythmAudio; Renderer: TRhythmRenderer; Image: TBitmap; PNG: TPngImage);
var State, Saved: TRhythmSettings; Base, Crop: TBitmap; Ball: TMarbleBallStyle; Stage: TMarbleStageStyle;
  StageHashes: array[TMarbleStageStyle] of string; Other: TMarbleStageStyle;
  BallHashes: array[TMarbleBallStyle] of string; OtherBall: TMarbleBallStyle;
  P, Camera: TBallPoint; T, Scale: Double; CX, CY, Half, X, Y, Changes: Integer;
  Row, BaseRow: PCardinal; Path: string;

  function PixelsHash: string;
  var Digest: THashSHA2; Y: Integer;
  begin
    Digest := THashSHA2.Create;
    for Y := 0 to Image.Height - 1 do Digest.Update(Image.ScanLine[Y]^, Image.Width * 4);
    Result := Digest.HashAsString;
  end;

begin
  State := TRhythmSettings.Defaults;
  Need((State.MarbleBall = mbSteel) and (State.MarbleStage = msWoodWorkshop), 'Marble default appearance');
  Need(TRhythmSettings.TryJSON('{"schema":1,"style":"marble-relay","marbleBall":-8,"marbleStage":"unknown"}', Saved) and
    (Saved.MarbleBall = mbSteel) and (Saved.MarbleStage = msWoodWorkshop), 'Invalid appearance must fall back to defaults');
  Need(TRhythmSettings.TryJSON('{"schema":1,"style":"marble-relay","marbleStage":3}', Saved) and
    (Saved.MarbleStage = msStoneRuins), 'Old stone setting must survive the new menu order');
  Need(TRhythmSettings.TryJSON('{"schema":1,"style":"marble-relay","marbleStage":4}', Saved) and
    (Saved.MarbleStage = msClearAcrylic), 'Old ice setting must migrate to acrylic');
  Need(TRhythmSettings.TryJSON('{"schema":1,"style":"marble-relay","marbleStage":5}', Saved) and
    (Saved.MarbleStage = msNeonArcade), 'Old neon setting must survive the new menu order');
  State.Style := rsMarbleRelay;
  State.Plan := Ref;
  State.MarbleBall := mbPorcelain;
  State.MarbleStage := msClearAcrylic;
  Need(TRhythmSettings.TryJSON(State.ToJSON, Saved) and (Saved.MarbleBall = State.MarbleBall) and
    (Saved.MarbleStage = State.MarbleStage) and (Saved.Plan.Key = Ref.Key) and (Saved.Plan.Digest = Ref.Digest),
    'Appearance save changes the plan');

  T := Min(14.50, Plan.Duration * 0.86);
  P := Plan.Position(T);
  Camera := Plan.CameraTarget(T);
  Scale := Min(Image.Height / 3.75, Image.Width / 5.8);
  CX := Round(Image.Width * 0.5 + (P.X - Camera.X) * Scale);
  CY := Round(Image.Height * 0.54 + (Camera.Y - P.Y) * Scale);
  Half := Round(MarbleRadius * Scale / 0.98) + 3;
  Path := '';
  if SameText(ParamStr(2), 'demo') then
  begin
    Path := TPath.Combine(Folder, 'Appearance');
    ForceDirectories(Path);
  end;
  Base := TBitmap.Create;
  Crop := TBitmap.Create;
  try
    for Stage := Low(TMarbleStageStyle) to High(TMarbleStageStyle) do
    begin
      State.MarbleStage := Stage;
      Need(TRhythmSettings.TryJSON(State.ToJSON, Saved) and (Saved.MarbleStage = Stage) and
        (Saved.Plan.Key = Ref.Key) and (Saved.Plan.Digest = Ref.Digest), 'Theme restore changes the prepared plan');
      Renderer.ConfigureStyle(rsMarbleRelay, Ref, 0, 0, mbSteel, Stage);
      Renderer.Render(Image, Audio, T, 0);
      StageHashes[Stage] := PixelsHash;
      for Other := Low(TMarbleStageStyle) to High(TMarbleStageStyle) do
        if Other < Stage then Need(StageHashes[Stage] <> StageHashes[Other], 'Duplicate stage theme');
      if Stage = msWoodWorkshop then Base.Assign(Image);
      if Path <> '' then
      begin
        PNG.Assign(Image);
        PNG.SaveToFile(TPath.Combine(Path, Format('stage-%d.png', [Ord(Stage)])));
      end;
    end;

    Crop.SetSize(72, 72);
    for Ball := Low(TMarbleBallStyle) to High(TMarbleBallStyle) do
    begin
      Renderer.ConfigureStyle(rsMarbleRelay, Ref, 0, 0, Ball, msWoodWorkshop);
      Renderer.Render(Image, Audio, T, 0);
      Changes := 0;
      for Y := 0 to Image.Height - 1 do
      begin
        Row := Image.ScanLine[Y];
        BaseRow := Base.ScanLine[Y];
        for X := 0 to Image.Width - 1 do
        begin
          if (Row^ and $FFFFFF) <> (BaseRow^ and $FFFFFF) then
          begin
            Need((Abs(X - CX) <= Half) and (Abs(Y - CY) <= Half), 'Changing the ball affects pixels outside the main sphere');
            Inc(Changes);
          end;
          Inc(Row);
          Inc(BaseRow);
        end;
      end;
      Need((Changes > 0) = (Ball <> mbSteel), 'Ball change did not update the same position');
      BallHashes[Ball] := PixelsHash;
      for OtherBall := Low(TMarbleBallStyle) to High(TMarbleBallStyle) do
        if OtherBall < Ball then Need(BallHashes[Ball] <> BallHashes[OtherBall], 'Duplicate ball appearance');
      if Path <> '' then
      begin
        Crop.Canvas.CopyRect(Rect(0, 0, 72, 72), Image.Canvas, Rect(CX - 36, CY - 36, CX + 36, CY + 36));
        PNG.Assign(Crop);
        PNG.SaveToFile(TPath.Combine(Path, Format('ball-%d.png', [Ord(Ball)])));
      end;
    end;
    Renderer.ConfigureStyle(rsMarbleRelay, Ref, 0, 0);
    Renderer.Render(Image, Audio, T, 0);
    Need(PixelsHash = StageHashes[msWoodWorkshop], 'Appearance reset changes the original frame');
    WriteLn('Marble appearance PASS: four materials, seven themes, same prepared plan.');
  finally
    Crop.Free;
    Base.Free;
  end;
end;

// 同じ絶対時刻で描画した7種類を横に並べ、球とカメラの動きを比較する。
procedure RenderThemeComparison(const Folder: string; const Ref: TRhythmPlanRef; Plan: TMarblePlan;
  Audio: TRhythmAudio; Renderer: TRhythmRenderer; PNG: TPngImage);
const
  TileWidth = 464;
  TileHeight = 261;
  Gutter = 12;
  Captions: array[0..3] of string = ('小球が受け皿に着地', '主球のリフトが上昇', '小球が分岐を切り替え', '羽根車の鐘が鳴る');
var
  Stage: TMarbleStageStyle;
  Tile, Sheet: TBitmap;
  Leg: TMarbleLeg;
  Saw: TMarbleSeesaw;
  Found: Boolean;
  ContactTimes: array[0..3] of Double;
  FirstFrame, LastFrame, FrameIndex, I, X, Y: Integer;
  T: Double;
  Path: string;
begin
  Found := False;
  for Leg in Plan.Legs do
  begin
    Saw := Leg.Bridge.Auxiliary.Merge.Pass.Counter.Seesaw;
    if (Saw.SwitchLever.Beat.Time > 0) and (Saw.ExitBell.Time > 0) then
    begin
      Found := True;
      Break;
    end;
  end;
  Need(Found, 'Comparison requires a tray, lift, junction and bell in the same chain');
  FirstFrame := Floor(Max(0.0, Saw.Board.Start - 0.5) * FrameRate);
  LastFrame := Ceil(Min(Plan.Duration, Saw.ExitBell.Time + 0.70) * FrameRate);
  ContactTimes[0] := Saw.Trigger.Time;
  ContactTimes[1] := Saw.WeightLift.Start;
  ContactTimes[2] := Saw.SwitchLever.Beat.Time;
  ContactTimes[3] := Saw.ExitBell.Time;
  Path := TPath.Combine(Folder, 'ThemeComparisonFrames');
  ForceDirectories(Path);
  Tile := TBitmap.Create;
  Sheet := TBitmap.Create;
  try
    Tile.PixelFormat := pf32bit;
    Tile.SetSize(TileWidth, TileHeight);
    Sheet.PixelFormat := pf32bit;
    Sheet.SetSize(1920, 682);
    Sheet.Canvas.Font.Name := 'Yu Gothic UI';
    for FrameIndex := FirstFrame to LastFrame - 1 do
    begin
      T := FrameIndex / FrameRate;
      Sheet.Canvas.Brush.Style := bsSolid;
      Sheet.Canvas.Brush.Color := RGB(16, 23, 34);
      Sheet.Canvas.FillRect(Rect(0, 0, Sheet.Width, Sheet.Height));
      Sheet.Canvas.Font.Color := RGB(235, 241, 249);
      Sheet.Canvas.Font.Height := -25;
      Sheet.Canvas.Font.Style := [fsBold];
      Sheet.Canvas.Brush.Style := bsClear;
      Sheet.Canvas.TextOut(14, 9, 'からくりリレー   7つのステージ');
      Sheet.Canvas.Font.Height := -17;
      Sheet.Canvas.Font.Style := [];
      Sheet.Canvas.TextOut(555, 16, '同じコース・同じ時刻');
      for Stage := Low(TMarbleStageStyle) to High(TMarbleStageStyle) do
      begin
        X := 14 + (Ord(Stage) mod 4) * (TileWidth + Gutter);
        Y := 48 + (Ord(Stage) div 4) * 310;
        Renderer.ConfigureStyle(rsMarbleRelay, Ref, 0, 0, mbSteel, Stage);
        Renderer.Render(Tile, Audio, T, 0);
        Sheet.Canvas.Font.Height := -20;
        Sheet.Canvas.Font.Style := [fsBold];
        Sheet.Canvas.TextOut(X + 2, Y, MarbleStageTitles[Stage]);
        Sheet.Canvas.Draw(X, Y + 28, Tile);
      end;

      X := 14 + 3 * (TileWidth + Gutter);
      Y := 358;
      Sheet.Canvas.Font.Height := -20;
      Sheet.Canvas.Font.Style := [fsBold];
      Sheet.Canvas.TextOut(X + 2, Y, '仕掛けの進行');
      Sheet.Canvas.Brush.Style := bsSolid;
      Sheet.Canvas.Brush.Color := RGB(28, 40, 56);
      Sheet.Canvas.FillRect(Rect(X, Y + 28, X + TileWidth, Y + 289));
      Sheet.Canvas.Brush.Style := bsClear;
      Sheet.Canvas.Font.Style := [];
      for I := Low(ContactTimes) to High(ContactTimes) do
      begin
        Sheet.Canvas.Font.Color := RGB(153, 178, 202);
        if T >= ContactTimes[I] then Sheet.Canvas.Font.Color := RGB(142, 243, 219);
        Sheet.Canvas.TextOut(X + 24, Y + 57 + I * 44, Captions[I]);
      end;
      Sheet.Canvas.Font.Color := RGB(194, 212, 230);
      Sheet.Canvas.Font.Height := -16;
      Sheet.Canvas.TextOut(X + 24, Y + 242, Format('試聴音源  %.2f 秒', [T], TFormatSettings.Invariant));
      PNG.Assign(Sheet);
      PNG.SaveToFile(TPath.Combine(Path, Format('frame%.4d.png', [FrameIndex - FirstFrame])));
    end;
    WriteLn(Format('Theme comparison: start=%.9f duration=%.9f frames=%d',
      [FirstFrame / FrameRate, (LastFrame - FirstFrame) / FrameRate, LastFrame - FirstFrame],
      TFormatSettings.Invariant));
  finally
    Sheet.Free;
    Tile.Free;
  end;
end;

procedure RenderEvidence(const Folder: string; const Ref: TRhythmPlanRef; Plan: TMarblePlan; Audio: TRhythmAudio);
var Renderer: TRhythmRenderer; Image: TBitmap; PNG: TPngImage; Cue: TMarbleCue;
  Seen: set of TMarbleDevice; Frames: string; I: Integer;
begin
  Renderer := TRhythmRenderer.Create;
  Image := TBitmap.Create;
  PNG := TPngImage.Create;
  try
    Renderer.ConfigureStyle(rsMarbleRelay, Ref, 0, 0);
    Image.PixelFormat := pf32bit;
    Image.SetSize(960, 540);
    VerifyAppearance(Folder, Ref, Plan, Audio, Renderer, Image, PNG);
    if SameText(ParamStr(2), 'themes') then
    begin
      RenderThemeComparison(Folder, Ref, Plan, Audio, Renderer, PNG);
      Exit;
    end;
    Seen := [];
    for Cue in Plan.Cues do
    begin
      if Cue.Device in Seen then Continue;
      Include(Seen, Cue.Device);
      Renderer.Render(Image, Audio, Cue.Time, 0);
      PNG.Assign(Image);
      PNG.SaveToFile(TPath.Combine(Folder, Format('marble-%d.png', [Ord(Cue.Device)])));
    end;
    if SameText(ParamStr(2), 'demo') then
    begin
      Frames := TPath.Combine(Folder, 'RotatingJunctionFrames');
      ForceDirectories(Frames);
      for I := 0 to Ceil(Plan.EndTime * FrameRate) - 1 do
      begin
        Renderer.Render(Image, Audio, I / FrameRate, 0);
        PNG.Assign(Image);
        PNG.SaveToFile(TPath.Combine(Frames, Format('frame%.4d.png', [I])));
      end;
      WriteLn('Frames: ', Ceil(Plan.EndTime * FrameRate));
    end;
  finally
    PNG.Free;
    Image.Free;
    Renderer.Free;
  end;
end;

var Folder, Source: string; Existing, Audio, Cold: TRhythmAudio;
  Worker: TRhythmPrepareThread; Ref: TRhythmPlanRef; Plan: TMarblePlan;
begin
  Existing := nil;
  Worker := nil;
  Audio := nil;
  Cold := nil;
  Plan := nil;
  try
    VerifyEdges;
    VerifyVariedTempo;
    Folder := TPath.Combine(ExtractFileDir(ParamStr(0)), 'Evidence');
    ForceDirectories(Folder);
    if ParamCount = 0 then
    begin
      Source := TPath.Combine(Folder, 'marble.identity');
      Existing := Fixture(Source);
    end
    else Source := ExpandFileName(ParamStr(1));
    Worker := TRhythmPrepareThread.Create(Source, 50, 0, rsMarbleRelay, False, Existing, 1);
    Existing := nil;
    Worker.Start;
    Worker.WaitFor;
    Need(Worker.Error = '', Worker.Error);
    Ref := Worker.Plan;
    Audio := Worker.TakeAudio;
    Cold := LoadMarbleAudio(Ref, Source, 0);
    Need(Length(Cold.PCM) = 0, 'Cold audio has PCM');
    Plan := LoadMarblePlan(Ref, Cold, 0);
    VerifyPhysics(Plan, Audio, SameText(ParamStr(2), 'demo') or SameText(ParamStr(2), 'themes'));
    VerifyLinks(Plan, Audio, SameText(ParamStr(2), 'demo') or SameText(ParamStr(2), 'themes'));
    VerifyCourseView(Plan);
    if ParamCount = 0 then VerifyLegacy(Audio);
    RenderEvidence(Folder, Ref, Plan, Cold);
    WriteLn('Marble relay PASS.');
  except
    on E: Exception do
    begin
      WriteLn(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
  Plan.Free;
  Cold.Free;
  Audio.Free;
  Worker.Free;
  Existing.Free;
end.
