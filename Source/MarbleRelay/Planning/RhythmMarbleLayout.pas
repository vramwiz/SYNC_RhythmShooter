unit RhythmMarbleLayout;
// 譜面の主球接触列からレールを配置し、描画に使う回転と区画を索引化する。
interface

uses System.SysUtils, RhythmBallGeometry, RhythmMarbleCourse;

// 譜面版と0始まりの主球接触番号から、その位置に配置できる仕掛けを調べる。
function CoursePart(Version, Index: Integer): Integer;
function PassSlot(Version, Index: Integer): Boolean;
function CounterSlot(Version, Index: Integer): Boolean;
function SeesawSlot(Version, Index: Integer): Boolean;
function JunctionTailSlot(Version, Index: Integer): Boolean;
// 画角とレール干渉の絞り込みに使う区間の境界を返す。
function MotionBounds(const Leg: TMarbleLeg): TMarbleSection;
// 軌道上の等間隔の時刻で、球中心と線分ABの距離を調べる。
function PathClearsSegment(const Path: TMarbleLeg; const A, B: TBallPoint; Clearance: Double): Boolean;
// Cuesから主球の区間と接触面を組む。除外する仕掛けは接触番号で指定する。
procedure LayCourse(Plan: TMarblePlan; const DisabledLifts, DisabledJunctions: TArray<Boolean>;
  const Cancel: TFunc<Boolean>);
// 水平位置が進行方向に単調に動くレール上で、Xへ達する時刻を返す。
function RailTimeAtX(const Leg: TMarbleLeg; X: Double): Double;
// 区間の境界で回転が連続するように、直前の姿勢と角速度を引き継ぐ。
procedure IndexRotation(Plan: TMarblePlan);
// 完成した主球と小球のコースを、描画対象の絞り込みに使う区画にまとめる。
procedure IndexCourse(Plan: TMarblePlan);

implementation

uses System.Math;

const
  LegacyTerminal = 3.9;
  LegacyDrag = 0.64;

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

end.
