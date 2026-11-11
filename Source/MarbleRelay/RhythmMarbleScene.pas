unit RhythmMarbleScene;
// 球の経路と仕掛けを横から描き、接触した仕掛けだけを反応させる。
interface

uses RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmMarblePlan, RhythmRenderSurface, RhythmEqualizer,
  RhythmImageBank, RhythmStyles;

type
  TMarbleAnimation = class(TAnimationScene)
  private
    FPlan: TMarblePlan; // 復元したコースを描画器が所有する。
    FRef: TRhythmPlanRef;
    FAttempt, FError: string; // 復元を試した計画・音源の組み合わせと、そのエラー。
  public
    Audio: TRhythmAudio; // 借用。描画は保存した接触列から復元する。
    BallStyle: TMarbleBallStyle;
    StageStyle: TMarbleStageStyle;
    destructor Destroy; override;
    // 次のPrepareが復元に使う計画参照を設定する。
    procedure SetReference(const Ref: TRhythmPlanRef);
    procedure Prepare(const Frame: TAnimationFrame); override;
    procedure Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame); override;
    function Notice: string; override;
    function GoalTime: Double; override;
    function Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
  end;

// 描画器が所有する球の画像バンクを作る。
function CreateMarbleImages: TAnimationImageBank;

implementation

uses System.Types, System.SysUtils, System.Math, Vcl.Graphics, RhythmBallGeometry, RhythmMarbleImages, RhythmMarbleStage, RhythmMarbleBackdrop;

type
  TMarblePainter = record
    Surface: TAnimationRenderSurface;
    Plan: TMarblePlan;
    BallStyle: TMarbleBallStyle;
    StageStyle: TMarbleStageStyle;
    Colors: TMarblePalette;
    Art: TMarbleStagePainter;
    Frame: TAnimationFrame;
    Time, Left, Top, Scale, Width, Height: Double;
    function Screen(X, Y: Double): TPointF;
    procedure Rect(X1, Y1, X2, Y2: Double; Color: TColor);
    procedure Line(X1, Y1, X2, Y2, Stroke: Double; Color: TColor);
    procedure Dot(X, Y, Radius: Double; Color: TColor; Filled: Boolean = True);
    procedure Rail(const A, B: TBallPoint);
    procedure Plate(X, Y, HalfWidth, Slope: Double; Color: TColor);
    procedure Gate(const Cue: TMarbleCue; Age: Double);
    procedure Bell(X, Y, Age: Double);
    procedure Spring(X, Y, Age, Slope: Double);
    procedure CatchTray(X, Y, Slope: Double; Heading: Integer);
    procedure Tip(const Cue: TMarbleCue; Age: Double);
    procedure Goal(const Cue: TMarbleCue; Age: Double);
    procedure TurnGuide(const Leg: TMarbleLeg);
    procedure Carrier(const Leg: TMarbleLeg; DeviceKind: TMarbleDevice; Parked: Double = 0);
    procedure SwingArm(const Leg: TMarbleLeg);
    procedure Chute(const Leg, Previous: TMarbleLeg);
    procedure Cradle(const Leg: TMarbleLeg; const P: TBallPoint; Color: TColor);
    procedure TiltingTray(const Bridge: TMarbleBridge; const Trigger: TBallPoint);
    procedure AuxiliaryTrack(const A, B: TBallPoint);
    procedure AuxiliaryBell(const P: TBallPoint; const Beat: TMarbleBeat; Heading: Integer);
    procedure AuxiliaryRocker(const Bridge: TMarbleBridge; const Contact, Along: TBallPoint; Age, Throw: Double);
    procedure AuxiliaryShutter(const Link: TMarbleLink);
    procedure Shutter(const Link: TMarbleLink; const Arm: TBallPoint; Size, Opening: Double);
    procedure AuxiliaryBridge(const Bridge, Reply: TMarbleBridge; const GateArm: TBallPoint; Opening: Double);
    procedure PassingTrack(const Aux: TMarbleAuxiliary; const CarrierLeg: TMarbleLeg);
    procedure CounterTrack(const Aux: TMarbleAuxiliary);
    procedure InterlockDevice(const Interlock: TMarbleInterlock);
    procedure SeesawBoard(const Board: TMarbleBoard);
    procedure ReceivingTray(const Saw: TMarbleSeesaw);
    procedure WeightedLift(const Saw: TMarbleSeesaw);
    procedure JunctionDevice(const Saw: TMarbleSeesaw; const Leg: TMarbleLeg);
    procedure WheelBell(const P: TBallPoint; const Beat: TMarbleBeat; H: Integer);
    procedure SeesawTrack(const Aux: TMarbleAuxiliary; const JunctionLeg: TMarbleLeg);
    procedure SharedTap(const Cue: TMarbleCue);
    procedure Linkage(const Link: TMarbleLink);
    procedure ContactPulse(X, Y, Age, Power: Double);
    procedure Device(Index: Integer);
    procedure Sphere(const P: TBallPoint; Radius: Double; Asset: Integer);
    procedure Ball(const P: TBallPoint);
    procedure NeonTrail;
    procedure Course(const P: TBallPoint);
    function SectionVisible(const Section: TMarbleSection): Boolean;
    procedure Paint;
  end;

function CreateMarbleImages: TAnimationImageBank;
begin
  Result := RhythmMarbleImages.CreateMarbleImages;
end;

function TMarblePainter.Screen(X, Y: Double): TPointF;
begin
  Result := PointF((X - Left) * Scale, (Top - Y) * Scale);
end;

procedure TMarblePainter.Rect(X1, Y1, X2, Y2: Double; Color: TColor);
var A, B: TPointF;
begin
  A := Screen(Min(X1, X2), Y2);
  B := Screen(Max(X1, X2), Y1);
  Surface.FillRect(A.X, A.Y, B.X, B.Y, Color);
end;

procedure TMarblePainter.Line(X1, Y1, X2, Y2, Stroke: Double; Color: TColor);
var A, B: TPointF;
begin
  A := Screen(X1, Y1);
  B := Screen(X2, Y2);
  Surface.Line(A.X, A.Y, B.X, B.Y, Color, Max(1.0, Stroke * Scale));
end;

procedure TMarblePainter.Dot(X, Y, Radius: Double; Color: TColor; Filled: Boolean);
var A: TPointF;
begin
  A := Screen(X, Y);
  Surface.Circle(A.X, A.Y, Radius * Scale, Color, Filled, Max(1.0, 0.016 * Scale));
end;

procedure TMarblePainter.Rail(const A, B: TBallPoint);
const SupportSpacing: array[TMarbleStageStyle] of Double = (0.84, 0.71, 0.92, 1.03, 0.92, 0.71, 0.98);
var I: Integer; X, Y, X1, X2, Y1, Y2, Spacing, Depth: Double; Start, Finish: TBallPoint;
begin
  if A.X > B.X then
  begin
    Rail(B, A);
    Exit;
  end;
  X1 := Max(A.X, Left - 0.5);
  X2 := Min(B.X, Left + Width + 0.5);
  if X2 - X1 < 1E-6 then Exit;
  Y1 := A.Y + (B.Y - A.Y) * (X1 - A.X) / (B.X - A.X);
  Y2 := A.Y + (B.Y - A.Y) * (X2 - A.X) / (B.X - A.X);
  Start := BallPoint(X1, Y1);
  Finish := BallPoint(X2, Y2);
  Depth := 0.18;
  if StageStyle in [msColorToys, msStoneRuins] then Depth := 0.225;
  Spacing := SupportSpacing[StageStyle];
  for I := Ceil((X1 + 0.16) / Spacing) to Floor((X2 - 0.16) / Spacing) do
  begin
    X := I * Spacing;
    Y := Y1 + (Y2 - Y1) * (X - X1) / (X2 - X1);
    Art.Column(X, Y - Depth * 0.56, Y - 0.47, 0.073);
  end;
  Art.Beam(Start, Finish, Depth, False);
  for I := Ceil((X1 + 0.16) / Spacing) to Floor((X2 - 0.16) / Spacing) do
  begin
    X := I * Spacing;
    Y := Y1 + (Y2 - Y1) * (X - X1) / (X2 - X1);
    Art.Joint(BallPoint(X, Y - Depth * 0.64), 0.045, I * 0.8);
  end;
end;

procedure TMarblePainter.Plate(X, Y, HalfWidth, Slope: Double; Color: TColor);
var A, B: TBallPoint;
begin
  A := BallPoint(X - HalfWidth, Y - Slope * HalfWidth);
  B := BallPoint(X + HalfWidth, Y + Slope * HalfWidth);
  Art.Beam(A, B, 0.108, True);
  A := BallMix(A, B, 0.20);
  B := BallMix(A, B, 0.76);
  A.Y := A.Y - 0.014;
  B.Y := B.Y - 0.014;
  Art.Line(A, B, 0.013, Color);
end;

procedure TMarblePainter.Gate(const Cue: TMarbleCue; Age: Double);
var X, Y, Swing: Double; Pivot, Arm, Tail: TBallPoint; Dir: Integer;
begin
  Dir := Cue.Heading;
  X := Cue.Surface.X + Dir * 0.025;
  Y := Cue.Center.Y + 0.48;
  Swing := 1.57 * (1 - Exp(-Max(0.0, Age) * 34));
  Pivot := BallPoint(X, Y);
  Arm := BallPoint(X + Dir * 0.48 * Sin(Swing), Y - 0.48 * Cos(Swing));
  Tail := BallAdd(Pivot, BallScale(BallSub(Pivot, Arm), 0.22));
  Art.Column(X + Dir * 0.38, Y + 0.21, Y - 0.035, 0.055);
  Art.Beam(BallPoint(X - Dir * 0.09, Y + 0.06), BallPoint(X + Dir * 0.41, Y + 0.06), 0.079, False);
  Art.Lever(Pivot, Arm, Tail, Dir * Swing);
end;

procedure TMarblePainter.Bell(X, Y, Age: Double);
var Swing: Double;
begin
  Swing := 0;
  if Age >= 0 then Swing := 0.10 * Sin(Age * 48) * Exp(-Age * 6);
  Plate(X, Y, 0.22, 0, Colors.Brass);
  Art.Chime(BallPoint(X, Y - 0.095), Swing, 0.36, Age);
end;

procedure TMarblePainter.Spring(X, Y, Age, Slope: Double);
var I: Integer; PreviousX, PreviousY, PX, PY, Press: Double;
begin
  Press := 0;
  if Age > 0 then Press := 0.068 * (1 - Exp(-Age * 42)) * Exp(-Age * 12);
  Rect(X - 0.23, Y - 0.46, X + 0.23, Y - 0.39, Colors.TimberEdge);
  Dot(X - 0.17, Y - 0.428, 0.019, Colors.Ink);
  Dot(X + 0.17, Y - 0.428, 0.019, Colors.Ink);
  PreviousX := X;
  PreviousY := Y - 0.40;
  for I := 1 to 7 do
  begin
    PX := X + 0.12 * (1 - 2 * (I mod 2));
    PY := Y - 0.40 + (0.31 - Press) * I / 7;
    Line(PreviousX, PreviousY, PX, PY, 0.042, Colors.Aqua);
    PreviousX := PX;
    PreviousY := PY;
  end;
  Plate(X, Y - Press, 0.21, Slope, Colors.Aqua);
end;

procedure TMarblePainter.CatchTray(X, Y, Slope: Double; Heading: Integer);
begin
  Line(X - Heading * 0.25, Y - 0.37, X + Heading * 0.15, Y - 0.14, 0.084, Colors.Timber);
  Line(X - Heading * 0.21, Y - 0.13, X - Heading * 0.21, Y - 0.40, 0.082, Colors.Timber);
  Plate(X, Y, 0.26, Slope, Colors.Orange);
  Dot(X - Heading * 0.17, Y - 0.19, 0.035, Colors.Brass);
end;

procedure TMarblePainter.Tip(const Cue: TMarbleCue; Age: Double);
var Angle, X, Y: Double;
begin
  X := Cue.Surface.X;
  Y := Cue.Surface.Y;
  Angle := ArcTan(Cue.Slope * Cue.Heading) - 1.03 * (1 - Exp(-Max(0.0, Age) * 29));
  Line(X, Y - 0.024, X + Cue.Heading * 0.33 * Cos(Angle), Y - 0.024 + 0.33 * Sin(Angle), 0.048, Colors.Orange);
  Dot(X, Y - 0.084, 0.058, Colors.TimberEdge);
  Dot(X, Y - 0.084, 0.027, Colors.Ink);
end;

procedure TMarblePainter.Goal(const Cue: TMarbleCue; Age: Double);
var X, Y, Lift: Double; Dir: Integer;
begin
  X := Cue.Center.X;
  Y := Cue.Center.Y - MarbleRadius;
  Dir := Cue.Heading;
  Rect(X - Dir * 0.20, Y - 0.28, X + Dir * 0.86, Y, Colors.Timber);
  Rect(X + Dir * 0.75, Y, X + Dir * 0.86, Y + 0.18, Colors.Brass);
  Line(X - Dir * 0.20, Y - 0.02, X + Dir * 0.86, Y - 0.02, 0.036, Colors.TimberEdge);
  Dot(X + Dir * 0.58, Y - 0.14, 0.048, Colors.Brass);
  Lift := 0.52 * (1 - Exp(-Max(0.0, Age) * 9));
  Line(X + Dir * 0.79, Y + 0.12, X + Dir * 0.79, Y + 0.30 + Lift, 0.040, Colors.Alloy);
  Surface.FillQuad(Screen(X + Dir * 0.81, Y + 0.30 + Lift), Screen(X + Dir * 1.15, Y + 0.27 + Lift),
    Screen(X + Dir * 1.15, Y + 0.12 + Lift), Screen(X + Dir * 0.81, Y + 0.12 + Lift), Colors.Orange);
end;

procedure TMarblePainter.TurnGuide(const Leg: TMarbleLeg);
const Segments = 30;
var I: Integer; Pivot, P, N, Outer, Inner, LastOuter, LastInner: TBallPoint;
begin
  Pivot := Leg.ArcPivot;
  LastOuter := BallPoint(Pivot.X, Pivot.Y + Leg.Radius + MarbleRadius + 0.04);
  LastInner := BallPoint(Pivot.X, Pivot.Y + Leg.Radius - MarbleRadius - 0.04);
  for I := 1 to Segments do
  begin
    P := Leg.ArcPoint(Pi * I / Segments);
    N := BallScale(BallUnit(BallSub(P, Pivot)), MarbleRadius + 0.04);
    Outer := BallAdd(P, N);
    Inner := BallSub(P, N);
    Line(LastOuter.X, LastOuter.Y, Outer.X, Outer.Y, 0.075, Colors.TimberEdge);
    Line(LastInner.X, LastInner.Y, Inner.X, Inner.Y, 0.062, Colors.Alloy);
    if I mod 6 = 0 then
    begin
      P := BallAdd(Outer, BallScale(N, 0.56));
      Line(Outer.X, Outer.Y, P.X, P.Y, 0.053, Colors.Timber);
      Dot(P.X, P.Y, 0.041, Colors.Ink);
      Dot(P.X, P.Y, 0.023, Colors.Brass);
    end;
    LastOuter := Outer;
    LastInner := Inner;
  end;
end;

procedure TMarblePainter.Cradle(const Leg: TMarbleLeg; const P: TBallPoint; Color: TColor);
var Q: TBallPoint; X, Y, Slope, Release: Double; Side: Integer;
begin
  Release := 0;
  if Leg.Rollout then Release := EnsureRange((Time - Leg.Dock + 0.065) / 0.065, 0.0, 1.0);
  Slope := Leg.RailSlope * Release;
  Q := MarbleRailSurface(P, Slope);
  Plate(Q.X, Q.Y, 0.25, Slope, Color);
  for Side := -1 to 1 do
  begin
    if Side = 0 then Continue;
    X := Side * 0.25;
    Y := Q.Y + Slope * X;
    if (Side = Leg.Heading) and (Release > 0) then
      Line(Q.X + X, Y - 0.03, Q.X + X + Side * (0.04 + 0.046 * Release), Y + 0.046 * (1 - Release), 0.043, Color)
    else Line(Q.X + X, Y - 0.03, Q.X + X + Side * 0.04, Y + 0.046, 0.043, Color);
  end;
  Dot(Q.X, Q.Y - 0.068, 0.027, Colors.Ink);
end;

procedure TMarblePainter.Carrier(const Leg: TMarbleLeg; DeviceKind: TMarbleDevice; Parked: Double);
var A, B, P, Q, Previous: TBallPoint; X, Y, Phase, EntrySide, ExitSide: Double; I: Integer;
begin
  A := Leg.Origin;
  B := Leg.Carriage(Leg.Finish);
  P := Leg.Carriage(Time);
  P.Y := P.Y - Parked;
  if DeviceKind = mdLift then
  begin
    EntrySide := A.X - Leg.Heading * 0.34;
    ExitSide := A.X + Leg.Heading * 0.34;
    Art.Column(EntrySide, B.Y + 0.22, A.Y + 0.19, 0.040);
    Art.Column(ExitSide, B.Y - 0.19, A.Y - 0.40, 0.040);
    Art.Beam(BallPoint(A.X - 0.42, B.Y + 0.26), BallPoint(A.X + 0.42, B.Y + 0.26), 0.10, False);
    Art.LinkRod(BallPoint(EntrySide, P.Y - 0.28), BallPoint(EntrySide, B.Y + 0.21), Time < Leg.Dock);
    X := EntrySide;
    Y := B.Y + 0.21;
    Phase := (P.Y - A.Y) * 5.8;
    Art.Wheel(BallPoint(X, Y), Leg.Heading, Phase, 0.115);
    Art.Beam(BallPoint(P.X - 0.34, P.Y - 0.19), BallPoint(P.X + 0.34, P.Y - 0.19), 0.09, True);
  end
  else if Leg.Travel.Y < 0 then
  begin
    Previous := A;
    for I := 1 to 12 do
    begin
      Q := Leg.Carriage(Leg.Start + (Leg.Dock - Leg.Start) * I / 12);
      Line(Previous.X - Leg.Heading * 0.18, Previous.Y - 0.35, Q.X - Leg.Heading * 0.18, Q.Y - 0.35, 0.069, Colors.TimberEdge);
      Line(Previous.X - Leg.Heading * 0.32, Previous.Y - 0.47, Q.X - Leg.Heading * 0.32, Q.Y - 0.47, 0.036, Colors.Alloy);
      Previous := Q;
    end;
    Line(P.X - Leg.Heading * 0.18, P.Y - 0.35, P.X, P.Y - 0.17, 0.051, Colors.Brass);
    Dot(P.X - Leg.Heading * 0.18, P.Y - 0.35, 0.055, Colors.Ink);
  end
  else
  begin
    Y := A.Y - MarbleRadius - 0.22;
    Line(A.X - Leg.Heading * 0.27, Y, B.X + Leg.Heading * 0.27, Y, 0.072, Colors.TimberEdge);
    Line(A.X, Y - 0.14, B.X, Y - 0.14, 0.048, Colors.Timber);
    Dot(A.X, Y, 0.056, Colors.Ink);
    Dot(B.X, Y, 0.056, Colors.Ink);
    Dot(P.X - 0.17, Y + 0.038, 0.062, Colors.Alloy);
    Dot(P.X + 0.17, Y + 0.038, 0.062, Colors.Alloy);
    Rect(P.X - 0.25, Y + 0.075, P.X + 0.25, P.Y - MarbleRadius - 0.06, Colors.Timber);
  end;
  Cradle(Leg, P, Colors.Aqua);
end;

procedure TMarblePainter.SwingArm(const Leg: TMarbleLeg);
var Pivot, P, Counter: TBallPoint;
begin
  Pivot := Leg.ArcPivot;
  P := Leg.Carriage(Time);
  Counter := BallAdd(Pivot, BallScale(BallSub(Pivot, P), 0.30));
  Art.Beam(BallPoint(Pivot.X - 0.17, Pivot.Y + 0.10), BallPoint(Pivot.X + 0.17, Pivot.Y + 0.10), 0.20, False);
  Art.LinkRod(Counter, BallPoint(P.X, P.Y - MarbleRadius - 0.035), Time >= Leg.Start);
  Art.Weight(Counter);
  Art.Joint(Pivot, 0.10, ArcTan2(P.Y - Pivot.Y, P.X - Pivot.X));
  Cradle(Leg, P, Colors.Brass);
end;

procedure TMarblePainter.Chute(const Leg, Previous: TMarbleLeg);
var X, Inlet, Outlet, GuideEnd, NearSide, FarSide, Angle, FlapLength: Double; A, Hinge: TBallPoint;
begin
  X := Leg.Origin.X;
  Inlet := Leg.Origin.Y;
  Outlet := Leg.Position(Leg.Finish).Y;
  GuideEnd := Outlet + Min(0.82, (Inlet - Outlet) * 0.72);
  NearSide := X - Leg.Heading * (MarbleRadius + 0.043);
  FarSide := X + Leg.Heading * (MarbleRadius + 0.043);
  Line(FarSide, Inlet + 0.17, FarSide, GuideEnd, 0.065, Colors.TimberEdge);
  if GuideEnd < Inlet - 0.24 then Line(NearSide, Inlet - 0.24, NearSide, GuideEnd, 0.060, Colors.Alloy);
  Rect(FarSide, Inlet - 0.08, FarSide + Leg.Heading * 0.19, Inlet + 0.13, Colors.Orange);
  Dot(FarSide + Leg.Heading * 0.125, Inlet + 0.022, 0.036, Colors.Ink);
  Line(FarSide, (Inlet + Outlet) * 0.5, FarSide + Leg.Heading * 0.28, (Inlet + Outlet) * 0.5, 0.066, Colors.Timber);
  Dot(FarSide + Leg.Heading * 0.28, (Inlet + Outlet) * 0.5, 0.043, Colors.Ink);
  Previous.RailSupport(A, Hinge);
  FlapLength := Previous.DropLip * Hypot(1, Previous.Grade);
  Angle := ArcTan(Previous.Grade) - 1.42 * (1 - Exp(-Max(0.0, Time - Leg.Start) * 48));
  Line(Hinge.X, Hinge.Y - 0.024, Hinge.X + Leg.Heading * FlapLength * Cos(Angle),
    Hinge.Y - 0.024 + FlapLength * Sin(Angle), 0.048, Colors.Orange);
  Dot(Hinge.X, Hinge.Y - 0.047, 0.036, Colors.Brass);
end;

procedure TMarblePainter.SharedTap(const Cue: TMarbleCue);
var Age, X, Y, Press, Power: Double;
begin
  Age := Time - Cue.Time;
  Power := Cue.Power;
  if (Time >= Cue.SharedBeat.Time) and ((Time < Cue.Time) or (Cue.SharedBeat.Time > Cue.Time)) then
  begin
    Age := Time - Cue.SharedBeat.Time;
    Power := Cue.SharedBeat.Power;
  end;
  X := Cue.Surface.X;
  Y := Cue.Surface.Y;
  Press := 0.058 * (1 - Exp(-Max(0.0, Age) * 60)) * Exp(-Max(0.0, Age) * 11);
  Rect(X - 0.14, Y - 0.25, X + 0.14, Y - 0.18, Colors.Ink);
  Line(X, Y - 0.21, X, Y - Press, 0.050, Colors.Alloy);
  Plate(X, Y + 0.035 - Press, 0.19, Cue.Slope, Colors.Brass);
  Dot(X, Y - 0.16 - Press * 0.45, 0.042, Colors.Orange);
  ContactPulse(X, Y, Age, Power);
end;

procedure TMarblePainter.Device(Index: Integer);
var Cue: TMarbleCue; Age, X, Y, U: Double;
begin
  Cue := Plan.Cues[Index];
  X := Cue.Surface.X;
  Y := Cue.Surface.Y;
  Age := Time - Cue.Time;
  case Cue.Device of
    mdGate, mdJunctionGate: Gate(Cue, Age);
    mdBell: Bell(X, Y, Age);
    mdSpring: Spring(X, Y, Age, Cue.Slope);
    mdCatch: CatchTray(X, Y, Cue.Slope, Cue.Heading);
    mdTip: Tip(Cue, Age);
    mdGoal: Goal(Cue, Age);
    mdBend: TurnGuide(Plan.Legs[Index + 1]);
    mdLift, mdShuttle: Carrier(Plan.Legs[Index + 1], Cue.Device);
    mdSwing: SwingArm(Plan.Legs[Index + 1]);
    mdChute: Chute(Plan.Legs[Index + 1], Plan.Legs[Index]);
    mdSeesaw: SeesawBoard(Plan.Legs[Index + 1].Board);
    mdSharedTap:
      begin
        if Plan.Legs[Index + 1].Motion = mmCarry then
        begin
          U := EnsureRange((Time - Cue.SharedBeat.Time - 0.19) / Max(0.05, Cue.Time - Cue.SharedBeat.Time - 0.19), 0.0, 1.0);
          Carrier(Plan.Legs[Index + 1], mdLift, 0.34 * (1 - U * U * (3 - 2 * U)));
        end;
        SharedTap(Cue);
        Exit;
      end;
  end;
  ContactPulse(X, Y, Age, Cue.Power);
end;

procedure TMarblePainter.ContactPulse(X, Y, Age, Power: Double);
begin
  if not Frame.BackgroundOnly then Art.Impact(BallPoint(X, Y), Age, Power);
end;

procedure TMarblePainter.TiltingTray(const Bridge: TMarbleBridge; const Trigger: TBallPoint);
var Tip, Hinge, Along, Weight, Guide: TBallPoint; StopX: Double;
begin
  Hinge := Bridge.Hinge;
  Tip := Bridge.Tip(Time);
  Along := BallUnit(BallSub(Hinge, Tip));
  StopX := Bridge.Entry.X;
  if Bridge.Sliding then
  begin
    Along := BallUnit(BallSub(Hinge, Bridge.Entry));
    StopX := StopX - Sign(Along.X) * 0.075;
  end;
  Weight := BallAdd(Hinge, BallScale(Along, 0.16));
  if Bridge.Sliding then
  begin
    Guide := BallAdd(Hinge, BallScale(Along, 0.19));
    Line(Hinge.X, Hinge.Y - 0.095, Guide.X, Guide.Y - 0.095, 0.062, Colors.Alloy);
    Weight := BallAdd(Tip, BallScale(Along, 0.09));
  end;
  Rect(StopX - 0.075, Bridge.Entry.Y - 0.15, StopX + 0.075, Bridge.Entry.Y - 0.056, Colors.Timber);
  Dot(StopX, Bridge.Entry.Y - 0.105, 0.022, Colors.Ink);
  Art.LinkRod(Trigger, Weight, (Time >= Bridge.Pull) and (Time < Bridge.Ready));
  Art.LinkRod(BallPoint(Hinge.X, Hinge.Y - 0.036), Weight, Time >= Bridge.Pull);
  if not Bridge.Sliding or (Abs(Tip.X - Hinge.X) > 1E-6) then Art.Beam(Tip, Hinge, 0.092, True);
  Art.Joint(Weight, 0.048, Pi / 4);
  Art.Joint(BallPoint(Hinge.X, Hinge.Y - 0.045), 0.056, ArcTan2(Tip.Y - Hinge.Y, Tip.X - Hinge.X));
end;

procedure TMarblePainter.AuxiliaryTrack(const A, B: TBallPoint);
begin
  Art.Beam(A, B, 0.112, False);
end;

procedure TMarblePainter.AuxiliaryBell(const P: TBallPoint; const Beat: TMarbleBeat; Heading: Integer);
var X, Y, Age, Swing: Double;
begin
  X := P.X + Heading * (MarbleAuxRadius + 0.045);
  Y := P.Y + 0.32;
  Age := Time - Beat.Time;
  Swing := Heading * 0.17 * Sin(Max(0.0, Age) * 21) * Exp(-Max(0.0, Age) * 5);
  Art.Beam(BallPoint(X - 0.13, Y + 0.06), BallPoint(X + 0.13, Y + 0.06), 0.065, False);
  Art.Chime(BallPoint(X, Y), Swing, 0.29, Age);
  ContactPulse(P.X, P.Y, Age, Beat.Power);
end;

procedure TMarblePainter.AuxiliaryRocker(const Bridge: TMarbleBridge; const Contact, Along: TBallPoint;
  Age, Throw: Double);
var Sensor, Pivot, Arm, Tail: TBallPoint; H: Integer; Angle: Double;
begin
  H := Sign(Along.X);
  Sensor := BallAdd(Contact, BallScale(Along, MarbleAuxRadius));
  Pivot := BallAdd(Sensor, BallPoint(H * 0.105, 0.18));
  Angle := H * Throw * EnsureRange(Age / 0.095, 0.0, 1.0);
  Arm := BallPoint(-H * 0.105 * Cos(Angle) + 0.18 * Sin(Angle), -H * 0.105 * Sin(Angle) - 0.18 * Cos(Angle));
  Sensor := BallAdd(Pivot, Arm);
  Tail := BallSub(Pivot, BallScale(Arm, 0.42));
  TiltingTray(Bridge, Tail);
  Art.Lever(Pivot, Sensor, Tail, Angle);
end;

procedure TMarblePainter.AuxiliaryShutter(const Link: TMarbleLink);
var U: Double; Arm: TBallPoint;
begin
  U := Link.Opening(Time);
  Arm := BallAdd(Link.Driver, BallPoint(Link.Heading * 0.10 * U, -0.10 * U));
  Shutter(Link, Arm, 1, U);
  Line(Link.Driver.X, Link.Driver.Y, Arm.X, Arm.Y, 0.043, Colors.Orange);
  Dot(Arm.X, Arm.Y, 0.032, Colors.Brass);
end;

procedure TMarblePainter.Shutter(const Link: TMarbleLink; const Arm: TBallPoint; Size, Opening: Double);
var X, Y, Z, RodX, RodY: Double;
begin
  X := Link.Receiver.X;
  Y := Link.Receiver.Y;
  Z := Y + 0.28 * Size * Opening;
  RodX := X + Link.Heading * 0.09 * Size;
  RodY := Z + 0.23 * Size;
  Art.LinkRod(Arm, BallPoint(RodX, RodY), (Opening > 0) and (Opening < 1));
  Art.Beam(BallPoint(X - 0.13 * Size, Y + 0.58 * Size),
    BallPoint(X + 0.13 * Size, Y + 0.58 * Size), 0.068 * Size, False);
  Art.Column(X - 0.056 * Size, Y + 0.54 * Size, Y + 0.24 * Size, 0.020 * Size);
  Art.Column(X + 0.056 * Size, Y + 0.54 * Size, Y + 0.24 * Size, 0.020 * Size);
  Art.ShutterBlade(X, Z, 0.23 * Size, 0.053 * Size, Opening);
  Art.LinkRod(BallPoint(X, RodY), BallPoint(RodX, RodY), Opening > 0);
  Art.Joint(BallPoint(RodX, RodY), 0.031 * Size, Opening * Pi);
end;

procedure TMarblePainter.AuxiliaryBridge(const Bridge, Reply: TMarbleBridge; const GateArm: TBallPoint; Opening: Double);
var Aux: TMarbleAuxiliary; Along, Above, A, B, C, D, Latch, Run, Contact, Tail, Rim, Join: TBallPoint;
  H: Integer; Throw: Double;
begin
  Aux := Bridge.Auxiliary;
  Along := BallUnit(BallSub(Aux.Receiver, Aux.Origin));
  H := Sign(Along.X);
  Above := BallPoint(-H * Along.Y, Abs(Along.X));
  A := BallSub(Aux.Origin, BallAdd(BallScale(Above, MarbleAuxRadius), BallScale(Along, 0.13)));
  B := BallSub(Aux.Receiver, BallScale(Above, MarbleAuxRadius));
  if Aux.Duet then
  begin
    Tail := Aux.Position(Aux.Finish);
    if Aux.Merge.Active then Tail := Aux.Merge.LaunchPoint;
    D := Tail;
    if Aux.Crossover then D := Aux.DropOrigin;
    Run := BallUnit(BallSub(D, Aux.Receiver));
    Above := BallScale(BallPoint(-H * Run.Y, Abs(Run.X)), MarbleAuxRadius);
    C := BallSub(Aux.Receiver, Above);
    D := BallSub(D, Above);
    AuxiliaryTrack(B, C);
    if Aux.Crossover then
    begin
      AuxiliaryTrack(C, D);
      Dot(D.X, D.Y - 0.047, 0.030, Colors.Alloy);
      Run := BallUnit(BallSub(Tail, Aux.Landing));
      Above := BallScale(BallPoint(-H * Run.Y, Abs(Run.X)), MarbleAuxRadius);
      C := BallSub(Aux.Landing, Above);
      D := BallSub(Tail, Above);
      Rim := BallSub(C, BallScale(Run, 0.12));
      Line(Rim.X, Rim.Y - 0.045, C.X + H * 0.16, C.Y - 0.057, 0.085, Colors.Alloy);
      Line(Rim.X, Rim.Y - 0.013, C.X + H * 0.16, C.Y - 0.022, 0.024, Colors.Aqua);
    end;
    if Aux.Merge.Active then
    begin
      AuxiliaryTrack(C, D);
      Spring(D.X, D.Y, Time - Aux.Merge.Launch.Time, Run.Y / Run.X);
      ContactPulse(Aux.Merge.LaunchPoint.X, Aux.Merge.LaunchPoint.Y, Time - Aux.Merge.Launch.Time, Aux.Merge.Launch.Power);
      Join := BallSub(Aux.Merge.JoinPoint, BallScale(BallUnit(BallPoint(-H * Aux.Merge.Grade, 1)), MarbleAuxRadius));
      Plate(Join.X, Join.Y, 0.16, H * Aux.Merge.Grade, Colors.Aqua);
    end
    else
    begin
      AuxiliaryTrack(C, BallAdd(D, BallPoint(H * 0.16, 0)));
      Line(D.X + H * 0.115, D.Y, D.X + H * 0.12, D.Y + 0.17, 0.063, Colors.Alloy);
    end;
    AuxiliaryBell(Aux.Position(Aux.Bell.Time), Aux.Bell, H);
  end
  else
  begin
    B := BallAdd(B, BallScale(Along, 0.11));
    Line(B.X, B.Y, B.X + H * 0.035, B.Y + 0.15, 0.050, Colors.Alloy);
  end;
  AuxiliaryTrack(A, B);
  Line(A.X, A.Y, A.X, A.Y + 0.10, 0.044, Colors.Alloy);

  // ゲートが上がると上段の留め金も引き上がる。
  Latch := BallAdd(Aux.Origin, BallScale(Along, MarbleAuxRadius + 0.028));
  Latch.Y := Latch.Y + 0.22 * Opening;
  Line(GateArm.X, GateArm.Y, Latch.X, Latch.Y + 0.13, 0.022, Colors.Brass);
  Line(Latch.X, Latch.Y - 0.035, Latch.X, Latch.Y + 0.13, 0.045, Colors.Orange);
  Dot(Latch.X, Latch.Y + 0.13, 0.030, Colors.PaleBrass);

  // 小球が下端のレバーを押し、反対側の腕が橋を引き上げる。
  Throw := 0.46;
  if Aux.Duet then Throw := 1.57;
  AuxiliaryRocker(Bridge, Aux.Receiver, Along, Time - Aux.Strike, Throw);
  if Aux.Duet then ContactPulse(Aux.Receiver.X, Aux.Receiver.Y, Time - Aux.Strike, Aux.StrikePower);
  if Aux.Reciprocal then
  begin
    AuxiliaryShutter(Aux.AuxGates[0]);
    AuxiliaryShutter(Aux.AuxGates[1]);
    Contact := Aux.Position(Aux.SecondStrike.Time);
    AuxiliaryRocker(Reply, Contact, Run, Time - Aux.SecondStrike.Time, 1.57);
    ContactPulse(Contact.X, Contact.Y, Time - Aux.SecondStrike.Time, Aux.SecondStrike.Power);
  end;
  if not Frame.BackgroundOnly then Sphere(Aux.Position(Time), MarbleAuxRadius, AuxiliaryGlassAsset);
end;

procedure TMarblePainter.PassingTrack(const Aux: TMarbleAuxiliary; const CarrierLeg: TMarbleLeg);
const TongueLength = 0.28;
var Pass: TMarblePass; H: Integer; A, B, Join, Along, Normal, Hinge, Tip, Driver, Cup: TBallPoint;
  U, Angle: Double;
begin
  Pass := Aux.Merge.Pass;
  H := CarrierLeg.Heading;
  Along := BallUnit(BallPoint(H, Pass.Bypass.Grade));
  Normal := BallUnit(BallPoint(-H * Pass.Bypass.Grade, 1));
  A := BallSub(Pass.Bypass.Origin, BallScale(Normal, MarbleAuxRadius));
  B := BallSub(Pass.Rejoin.Origin, BallScale(Normal, MarbleAuxRadius));
  Hinge := BallAdd(A, BallScale(Along, TongueLength));
  Join := BallSub(Pass.Rejoin.Origin, BallScale(BallUnit(BallPoint(-H * Pass.Rejoin.Grade, 1)), MarbleAuxRadius));
  AuxiliaryTrack(Hinge, B);
  Line(B.X, B.Y - 0.015, Join.X, Join.Y - 0.015, 0.045, Colors.PaleBrass);
  Plate(Join.X, Join.Y, 0.12, H * Pass.Rejoin.Grade, Colors.Aqua);

  U := EnsureRange((Time - Pass.SwitchPull) / (Pass.SwitchReady - Pass.SwitchPull), 0.0, 1.0);
  Angle := -1.48 + (ArcTan(Pass.Bypass.Grade) + 1.48) * U * U * (3 - 2 * U);
  Tip := BallSub(Hinge, BallPoint(H * TongueLength * Cos(Angle), TongueLength * Sin(Angle)));
  Driver := CarrierLeg.Carriage(Time);
  Line(Driver.X - H * 0.12, Driver.Y - 0.22, Hinge.X, Hinge.Y - 0.04, 0.018, Colors.Brass);
  Line(Tip.X, Tip.Y - 0.023, Hinge.X, Hinge.Y - 0.023, 0.064, Colors.Aqua);
  Dot(Hinge.X, Hinge.Y - 0.03, 0.037, Colors.Brass);
  ContactPulse(Pass.Bypass.Origin.X, Pass.Bypass.Origin.Y, Time - Pass.Fork.Time, Pass.Fork.Power);

  if not Pass.Counter.Active then
  begin
    Cup := Aux.Position(Aux.Finish);
    CatchTray(Cup.X, Cup.Y - MarbleAuxRadius, 0, H);
  end;
end;

procedure TMarblePainter.InterlockDevice(const Interlock: TMarbleInterlock);
var Latch: TMarbleLatch; Link: TMarbleLink; Arm, Tip, Tail, Pin: TBallPoint;
  X, Y, U, Angle: Double; I: Integer; Color: TColor;
begin
  Link := Interlock.Gate;
  X := Link.Receiver.X;
  Y := Link.Receiver.Y + 1.04;
  Shutter(Link, BallPoint(X, Y - 0.09), 1.65, Interlock.Opening(Time));
  Rect(X - 0.29, Y - 0.09, X + 0.29, Y + 0.12, Colors.Ink);
  Line(X - 0.28, Y - 0.072, X + 0.28, Y - 0.072, 0.038, Colors.TimberEdge);
  for I := 0 to High(Interlock.Inputs) do
  begin
    Latch := Interlock.Inputs[I];
    U := Latch.Amount(Time);
    Angle := Link.Heading * 1.38 * U;
    Arm := BallSub(Latch.Contact, Latch.Pivot);
    Tip := BallAdd(Latch.Pivot, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle),
      Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
    Tail := BallAdd(Latch.Pivot, BallScale(BallSub(Latch.Pivot, Tip), 0.40));
    Pin := BallPoint(X + Link.Heading * (2 * I - 1) * 0.15, Y + 0.18 - 0.125 * U);
    Color := Colors.Orange;
    if I = 1 then Color := Colors.Aqua;
    Line(Tail.X, Tail.Y, Pin.X, Pin.Y + 0.03, 0.018, Color);
    Art.Lever(Latch.Pivot, Tip, Tail, Angle);
    Line(Pin.X, Y + 0.106, Pin.X, Y - 0.04, 0.060, Colors.Alloy);
    Line(Pin.X, Pin.Y - 0.031, Pin.X, Pin.Y + 0.043, 0.045, Color);
    Dot(Pin.X, Pin.Y - 0.025, 0.024, Color);
    if I = 1 then ContactPulse(Latch.Contact.X, Latch.Contact.Y, Time - Latch.Beat.Time, Latch.Beat.Power);
  end;
end;

procedure TMarblePainter.CounterTrack(const Aux: TMarbleAuxiliary);
const Samples = 28;
var Counter: TMarbleCounter; A, B, Pivot, Tip, Tail: TBallPoint; Angle: Double; H, I: Integer;
  function SurfaceAt(U: Double): TBallPoint;
  begin
    Result := BallSub(Counter.Guide(U), BallScale(BallUnit(BallPoint(-Counter.GuideSlope(U), 1)), MarbleAuxRadius));
  end;
begin
  Counter := Aux.Merge.Pass.Counter;
  H := Counter.Gate.Heading;
  A := SurfaceAt(0);
  for I := 1 to Samples do
  begin
    B := SurfaceAt(I / Samples);
    AuxiliaryTrack(A, B);
    A := B;
  end;
  Plate(A.X, A.Y, 0.13, H * Counter.Rejoin.Grade, Colors.Aqua);
  if Counter.Interlock.Active then InterlockDevice(Counter.Interlock)
  else AuxiliaryBell(Aux.Position(Counter.DetourBeat.Time), Counter.DetourBeat, H);

  // 小球の進路に出たレバーが、直線側のシャッターを引き上げる。
  Pivot := Counter.Gate.Driver;
  Angle := H * 1.38 * EnsureRange((Time - Counter.Start) / 0.13, 0.0, 1.0);
  Tip := BallAdd(Pivot, BallPoint(-H * 0.083 * Cos(Angle) + 0.23 * Sin(Angle),
    -H * 0.083 * Sin(Angle) - 0.23 * Cos(Angle)));
  Tail := BallAdd(Pivot, BallScale(BallSub(Pivot, Tip), 0.38));
  Shutter(Counter.Gate, Tail, 1.65, Counter.Gate.Opening(Time));
  Art.Lever(Pivot, Tip, Tail, Angle);
end;

procedure TMarblePainter.SeesawBoard(const Board: TMarbleBoard);
var A, B, PadA, PadB: TBallPoint; X, Y: Double;
begin
  X := Board.Pivot.X;
  Y := Board.Pivot.Y;
  Art.Column(X, Y - 0.053, Y - 0.60, 0.115);
  A := Board.PointAt(Time, Board.Rear, 0);
  B := Board.PointAt(Time, Board.Front, 0);
  Art.Beam(A, B, 0.126, True);
  PadA := Board.PointAt(Time, Board.LoadPoint - 0.09, 0.019);
  PadB := Board.PointAt(Time, Board.Front - 0.05, 0.019);
  Art.Line(PadA, PadB, 0.034, Colors.Orange);
  Art.Joint(BallPoint(X, Y - 0.063), 0.118, Board.Heading * Board.AngleAt(Time));
end;

procedure TMarblePainter.ReceivingTray(const Saw: TMarbleSeesaw);
var Latch: TMarbleLatch; Arm, Tip, Tail, Socket, Pin, Rear, Nose, BackRim, FrontRim, Axle: TBallPoint;
  Push, Angle, Stop, RimHeight: Double; H: Integer;
begin
  H := Saw.Board.Heading;
  Latch := Saw.TrayRelease.Lever;
  Push := Latch.Amount(Time);
  Angle := H * 1.44 * Push;
  Arm := BallSub(Latch.Contact, Latch.Pivot);
  Tip := BallAdd(Latch.Pivot, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle),
    Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
  Tail := BallAdd(Latch.Pivot, BallScale(BallSub(Latch.Pivot, Tip), 0.48));

  // 皿の軸はコース計画に従う。留め具を引く連結部だけを材質別に描く。
  Socket := Saw.TrayPoint(Saw.WeightLift.Dock, MarbleTrayRear, 0);
  Socket := BallAdd(Socket, BallPoint(-H * 0.05, -0.115));
  Pin := BallAdd(Socket, BallPoint(0, 0.115 - 0.090 * Push));
  Art.LinkRod(Tail, BallAdd(Pin, BallPoint(0, -0.030)), (Push > 0) and (Push < 1));
  Art.LinkRod(Socket, Pin, Push > 0);
  Art.Joint(Socket, 0.035, Angle);
  Art.Beam(Latch.Pivot, BallAdd(Latch.Pivot, BallPoint(H * 0.20, 0.12)), 0.057, False);
  Art.Lever(Latch.Pivot, Tip, Tail, Angle);

  Rear := Saw.TrayPoint(Time, MarbleTrayRear, 0);
  Nose := Saw.TrayPoint(Time, MarbleTrayNose, 0);
  Axle := Saw.TrayPoint(Time, 0, -0.040);
  BackRim := Saw.TrayPoint(Time, MarbleTrayRear - 0.025, 0.066);
  Stop := EnsureRange((Time - Saw.TrayRelease.Start) / 0.10, 0.0, 1.0);
  RimHeight := 0.15 - 0.16 * Stop;
  FrontRim := Saw.TrayPoint(Time, MarbleTrayNose + 0.075 * Stop, RimHeight);
  Art.Tray(Rear, Nose, BackRim, FrontRim, Axle);
end;

procedure TMarblePainter.WeightedLift(const Saw: TMarbleSeesaw);
var Lift: TMarbleWeightLift; Deck, Pan, MainFloor, SmallFloor: TBallPoint;
  DeckCable, PanCable, Beam, PanBottom, Release, Ramp, U, Turn, Progress: Double;
  H: Integer; Moving: Boolean;
begin
  Lift := Saw.WeightLift;
  H := Saw.Board.Heading;
  Deck := Lift.Carriage(Time);
  Pan := Saw.Pan(Time);
  MainFloor := MarbleRailSurface(Deck, H * MarbleSeesawExitGrade);
  if Saw.TrayRelease.Active then SmallFloor := Saw.TrayPoint(Time, 0, 0)
  else SmallFloor := BallSub(Pan, BallScale(BallUnit(BallPoint(-H * Saw.CatchRail.Grade, 1)), MarbleAuxRadius));
  DeckCable := MainFloor.X + H * 0.23;
  PanCable := SmallFloor.X - H * 0.23;
  Beam := Saw.Landing.Y + 0.25;
  PanBottom := Saw.Landing.Y - Lift.Rise - 0.36;
  Moving := (Time >= Lift.Start) and (Time < Lift.Dock);
  Progress := Lift.Progress(Time);
  Turn := Lift.Rise * Progress / 0.073;

  // 昇降台の位置とロープの端点は、小球が沈める受け皿の計画から取る。
  Art.Column(PanCable, Beam, PanBottom, 0.048);
  Art.Column(DeckCable, Beam, Lift.Load.Y - 0.31, 0.052);
  Art.Beam(BallPoint(PanCable, Beam + 0.098), BallPoint(DeckCable, Beam + 0.098), 0.117, False);
  Art.LinkRod(BallPoint(PanCable, SmallFloor.Y - 0.06), BallPoint(PanCable, Beam), Moving);
  Art.LinkRod(BallPoint(DeckCable, MainFloor.Y - 0.06), BallPoint(DeckCable, Beam), Moving);
  Art.LinkRod(BallPoint(PanCable, Beam + 0.053), BallPoint(DeckCable, Beam + 0.053), Moving);
  Art.Joint(BallPoint(PanCable, Beam), 0.084, Turn);
  Art.Joint(BallPoint(DeckCable, Beam), 0.084, -Turn);
  if StageStyle = msSteampunk then
  begin
    Art.LinkRod(BallPoint(DeckCable, Beam - 0.28), BallPoint(DeckCable - H * 0.25, Beam - 0.28), Moving);
    Art.PressureDial(BallPoint(DeckCable - H * 0.25, Beam - 0.17), Progress);
  end;

  Release := EnsureRange((Lift.Dock - Time) / 0.055, 0.0, 1.0);
  Art.Weight(BallPoint(PanCable, SmallFloor.Y - 0.156));
  Art.Beam(BallPoint(MainFloor.X, MainFloor.Y - 0.04), BallPoint(DeckCable, MainFloor.Y - 0.04), 0.08, True);
  Plate(MainFloor.X, MainFloor.Y, 0.16, H * MarbleSeesawExitGrade, Colors.Brass);
  if Lift.Ramp > 0 then
  begin
    U := EnsureRange((Time - Lift.Dock + 0.10) / 0.10, 0.0, 1.0);
    Ramp := 0.09 + (Lift.Ramp - 0.09) * Sqr(U) * (3 - 2 * U);
    Art.Beam(BallPoint(MainFloor.X + H * 0.055, MainFloor.Y + MarbleSeesawExitGrade * 0.055),
      BallPoint(MainFloor.X + H * Ramp, MainFloor.Y + MarbleSeesawExitGrade * Ramp), 0.064, True);
  end;
  Line(MainFloor.X + H * 0.10, MainFloor.Y - 0.03,
    MainFloor.X + H * (0.19 - 0.036 * Release), MainFloor.Y - 0.058 + 0.15 * Release, 0.038, Colors.Orange);
  Art.Joint(BallPoint(DeckCable, MainFloor.Y - 0.064), 0.046, Turn);

  Art.Beam(BallPoint(PanCable, SmallFloor.Y - 0.034), BallPoint(SmallFloor.X, SmallFloor.Y - 0.034), 0.071, True);
  if Saw.TrayRelease.Active then ReceivingTray(Saw)
  else
  begin
    Plate(SmallFloor.X, SmallFloor.Y, 0.155, H * Saw.CatchRail.Grade, Colors.Aqua);
    Line(SmallFloor.X - H * 0.14, SmallFloor.Y, SmallFloor.X - H * 0.19, SmallFloor.Y + 0.065, 0.037, Colors.Aqua);
    Line(SmallFloor.X + H * 0.10, SmallFloor.Y - 0.025, SmallFloor.X + H * (0.17 - 0.038 * Release),
      SmallFloor.Y - 0.023 + 0.16 * Release, 0.046, Colors.Aqua);
  end;
  Dot(PanCable, SmallFloor.Y - 0.055, 0.035, Colors.Brass);
  ContactPulse(SmallFloor.X, SmallFloor.Y, Time - Saw.Trigger.Time, Saw.Trigger.Power);
end;

procedure TMarblePainter.JunctionDevice(const Saw: TMarbleSeesaw; const Leg: TMarbleLeg);
var Latch: TMarbleLatch; Joint, RailTip, Pin, Arm, LeverTip, Tail: TBallPoint; Angle: Double; H: Integer;
begin
  H := Leg.Heading;
  Latch := Saw.SwitchLever;
  Joint := Leg.Junction.Pivot(H);
  RailTip := Leg.Junction.Tip(Time, H);
  Pin := BallAdd(Joint, BallScale(BallSub(RailTip, Joint), 0.50));
  Pin.Y := Pin.Y - 0.055;
  Angle := H * 1.45 * Latch.Amount(Time);
  Arm := BallSub(Latch.Contact, Latch.Pivot);
  LeverTip := BallAdd(Latch.Pivot, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle),
    Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
  Tail := BallAdd(Latch.Pivot, BallScale(BallSub(Latch.Pivot, LeverTip), 0.43));

  Art.LinkRod(Tail, Pin, (Time >= Latch.Beat.Time) and (Time < Leg.Junction.Ready));
  Art.Beam(Joint, RailTip, 0.112, True);
  Art.Joint(Pin, 0.032, Angle);
  Art.Joint(BallPoint(Joint.X, Joint.Y - 0.049), 0.076, ArcTan2(RailTip.Y - Joint.Y, RailTip.X - Joint.X));
  Art.Beam(Latch.Pivot, BallAdd(Latch.Pivot, BallPoint(H * 0.14, 0.10)), 0.063, False);
  Art.Lever(Latch.Pivot, LeverTip, Tail, Angle);
  ContactPulse(Latch.Contact.X, Latch.Contact.Y, Time - Latch.Beat.Time, Latch.Beat.Power);
end;

procedure TMarblePainter.WheelBell(const P: TBallPoint; const Beat: TMarbleBeat; H: Integer);
var Pivot, BellPivot, Cam, Clapper: TBallPoint; Age, U, Turn, Swing: Double;
begin
  Age := Time - Beat.Time;
  U := EnsureRange(Age / 0.28, 0.0, 1.0);
  Turn := 1.76 * (1 - Sqr(1 - U));
  Pivot := BallAdd(P, BallPoint(H * MarbleAuxRadius, 0.18));
  BellPivot := BallAdd(Pivot, BallPoint(H * 0.20, 0.27));
  Art.Column(Pivot.X, Pivot.Y + 0.22, Pivot.Y, 0.042);
  Art.Beam(BallPoint(Pivot.X - H * 0.11, Pivot.Y + 0.25),
    BallPoint(BellPivot.X + H * 0.10, Pivot.Y + 0.25), 0.061, False);
  Art.Wheel(Pivot, H, Turn, 0.18);
  Swing := H * 0.074 * Sin(Max(0.0, Age) * 26) * Exp(-Max(0.0, Age) * 5);
  Cam := BallAdd(Pivot, BallPoint(H * 0.052 * Sin(Turn), 0.052 * Cos(Turn)));
  Clapper := BallAdd(BellPivot, BallPoint(Swing - H * 0.040, -0.205));
  Art.LinkRod(Cam, Clapper, (Age >= 0) and (Age < 0.28));
  Art.Disc(Cam, 0.024, Colors.PaleBrass);
  Art.Chime(BellPivot, Swing, 0.215, Age);
  ContactPulse(P.X + H * MarbleAuxRadius, P.Y, Age, Beat.Power);
end;

procedure TMarblePainter.SeesawTrack(const Aux: TMarbleAuxiliary; const JunctionLeg: TMarbleLeg);
const CurveSamples = 9;
var Saw: TMarbleSeesaw; A, B, PointOnRail, Normal, CupA, CupB, Arm, Tip, Tail: TBallPoint;
  H, I: Integer; Distance, Angle, Opening, T, Grade: Double;

  function RunSurface(AtTime: Double): TBallPoint;
  var N: TBallPoint;
  begin
    N := BallScale(BallUnit(BallPoint(-H * Saw.RunGrade(AtTime), 1)), MarbleAuxRadius);
    Result := BallSub(Saw.RunPosition(AtTime), N);
  end;

begin
  Saw := Aux.Merge.Pass.Counter.Seesaw;
  H := Saw.Board.Heading;
  Distance := Saw.Seat + Saw.SeatSpeed * (EnsureRange(Time, Saw.Board.Start, Saw.Board.Stop) - Saw.Board.Start);
  CupA := Saw.Board.PointAt(Time, Distance - 0.115, 0.025);
  CupB := Saw.Board.PointAt(Time, Distance + 0.115, 0.025);
  Line(CupA.X, CupA.Y, CupB.X, CupB.Y, 0.048, Colors.PaleBrass);
  Dot(CupA.X, CupA.Y + 0.035, 0.028, Colors.Brass);
  Dot(CupB.X, CupB.Y + 0.035, 0.028, Colors.Brass);

  Normal := BallScale(BallUnit(BallPoint(-H * Saw.CatchRail.Grade, 1)), MarbleAuxRadius);
  A := BallSub(Saw.CatchRail.Origin, Normal);
  if Saw.ExitRail.Start > 0 then
  begin
    PointOnRail := A;
    for I := 0 to CurveSamples do
    begin
      T := Saw.ExitCurveStart + (Saw.ExitRail.Start - Saw.ExitCurveStart) * I / CurveSamples;
      B := RunSurface(T);
      AuxiliaryTrack(PointOnRail, B);
      PointOnRail := B;
    end;
  end
  else PointOnRail := A;
  Grade := Saw.RunGrade(Aux.Finish);
  Normal := BallScale(BallUnit(BallPoint(-H * Grade, 1)), MarbleAuxRadius);
  B := BallSub(Aux.Position(Aux.Finish), Normal);
  if Saw.TrayRelease.Active then AuxiliaryTrack(PointOnRail, BallAdd(B, BallPoint(H * 0.13, Grade * 0.13)))
  else AuxiliaryTrack(PointOnRail, BallAdd(B, BallPoint(H * 0.13, 0)));
  if not Saw.WeightLift.Active then Plate(A.X, A.Y, 0.14, H * Saw.CatchRail.Grade, Colors.Aqua);
  Line(B.X + H * 0.095, B.Y, B.X + H * 0.095, B.Y + 0.13, 0.041, Colors.Alloy);
  if JunctionLeg.Junction.Active and (Saw.SwitchLever.Beat.Time > 0) then JunctionDevice(Saw, JunctionLeg)
  else AuxiliaryBell(Aux.Position(Saw.Bell.Time), Saw.Bell, H);
  if Saw.ExitGate.Kind <> mlNone then
  begin
    Opening := Saw.ExitGate.Opening(Time);
    Arm := BallAdd(Saw.ExitGate.Driver, BallPoint(H * 0.10 * Opening, -0.10 * Opening));
    Shutter(Saw.ExitGate, Arm, 1.22, Opening);
    Line(Saw.ExitGate.Driver.X, Saw.ExitGate.Driver.Y, Arm.X, Arm.Y, 0.042, Colors.Orange);
    WheelBell(Aux.Position(Saw.ExitBell.Time), Saw.ExitBell, H);
  end;

  if Saw.WeightLift.Active then
  begin
    WeightedLift(Saw);
    Exit;
  end;
  Arm := BallSub(Saw.LeverContact, Saw.Gate.Driver);
  Angle := H * 1.43 * EnsureRange((Time - Saw.Trigger.Time) / 0.12, 0.0, 1.0);
  Tip := BallAdd(Saw.Gate.Driver, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle), Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
  Tail := BallAdd(Saw.Gate.Driver, BallScale(BallSub(Saw.Gate.Driver, Tip), 0.42));
  Shutter(Saw.Gate, Tail, 1.60, Saw.Gate.Opening(Time));
  Line(Tip.X, Tip.Y, Tail.X, Tail.Y, 0.047, Colors.Orange);
  Dot(Saw.Gate.Driver.X, Saw.Gate.Driver.Y, 0.045, Colors.Alloy);
  Dot(Tip.X, Tip.Y, 0.029, Colors.Brass);
  ContactPulse(Saw.LeverContact.X, Saw.LeverContact.Y, Time - Saw.Trigger.Time, Saw.Trigger.Power);
end;

procedure TMarblePainter.Linkage(const Link: TMarbleLink);
var U, X, Y, Z, DriverX, DriverY, RodY, HatchU: Double; H: Integer;
  Bridge, Reply, Hatch: TMarbleBridge; GateArm: TBallPoint; Cue: TMarbleCue;
begin
  if Link.Kind = mlNone then Exit;
  U := Link.Opening(Time);
  H := Link.Heading;
  X := Link.Receiver.X;
  Y := Link.Receiver.Y;
  DriverX := Link.Driver.X + H * 0.10 * U;
  DriverY := Link.Driver.Y - 0.10 * U;
  if Link.Kind = mlShutter then
  begin
    Z := Y + 0.47 * U;
    RodY := Z + 0.42;
    Art.LinkRod(BallPoint(DriverX, DriverY), BallPoint(X + H * 0.13, RodY), (U > 0) and (U < 1));
    Art.Beam(BallPoint(X - 0.19, Y + 0.97), BallPoint(X + 0.19, Y + 0.97), 0.082, False);
    Art.Column(X - 0.076, Y + 0.91, Y + 0.42, 0.024);
    Art.Column(X + 0.076, Y + 0.91, Y + 0.42, 0.024);
    Art.ShutterBlade(X, Z - 0.01, 0.43, 0.069, U);
    Art.LinkRod(BallPoint(X, RodY), BallPoint(X + H * 0.13, RodY), U > 0);
    Art.Joint(BallPoint(X + H * 0.13, RodY), 0.038, U * Pi);
    Bridge := Plan.Legs[Link.Target + 1].Bridge;
    GateArm := BallPoint(X + H * 0.13, RodY);
    if Bridge.Auxiliary.Active then
    begin
      Reply := Default(TMarbleBridge);
      if Bridge.Auxiliary.Reciprocal then Reply := Plan.Legs[Link.Target + 2].Bridge;
      if Bridge.Auxiliary.Merge.Pass.Active then PassingTrack(Bridge.Auxiliary, Plan.Legs[Link.Target + 7]);
      if Bridge.Auxiliary.Merge.Pass.Counter.Active then CounterTrack(Bridge.Auxiliary);
      if Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.Active then
        SeesawTrack(Bridge.Auxiliary, Plan.Legs[Link.Target + 14]);
      AuxiliaryBridge(Bridge, Reply, GateArm, U);
      if Bridge.Auxiliary.Merge.Active then
      begin
        Hatch := Plan.Legs[Link.Target + 3].Bridge;
        Cue := Plan.Cues[Link.Target + 3];
        HatchU := EnsureRange((Time - Hatch.Pull) / (Hatch.Ready - Hatch.Pull), 0.0, 1.0);
        TiltingTray(Hatch, BallPoint(Cue.Surface.X + H * (0.025 + 0.10 * HatchU), Cue.Center.Y + 0.48 - 0.10 * HatchU));
      end;
    end
    else if Bridge.Active then TiltingTray(Bridge, GateArm);
  end
  else
  begin
    X := X + H * 0.15 * U;
    Line(DriverX, DriverY, X, Y, 0.025, Colors.Brass);
    Line(X + H * 0.12, Y + 0.03, X - H * 0.10, Y + 0.03, 0.065, Colors.Orange);
    Line(X - H * 0.10, Y + 0.03, X - H * 0.10, Y - 0.085, 0.045, Colors.Orange);
    Dot(X + H * 0.10, Y + 0.03, 0.034, Colors.Brass);
  end;
  Line(Link.Driver.X, Link.Driver.Y, DriverX, DriverY, 0.043, Colors.Orange);
  Dot(Link.Driver.X, Link.Driver.Y, 0.028, Colors.Alloy);
  Dot(DriverX, DriverY, 0.036, Colors.Brass);
end;

procedure TMarblePainter.Sphere(const P: TBallPoint; Radius: Double; Asset: Integer);
var Center: TPointF; Size: Integer;
begin
  Center := Screen(P.X, P.Y);
  Size := 2 * Max(1, Round(Radius * Scale / 0.98));
  Surface.DrawAsset(Asset, Point(Round(Center.X), Round(Center.Y)), Size, Size, 1, True);
end;

procedure TMarblePainter.Ball(const P: TBallPoint);
var Asset: Integer;
begin
  Asset := Ord(BallStyle) * BallPhases +
    (Round(Frac(Plan.Rotation(Time) / (2 * Pi)) * BallPhases) + BallPhases) mod BallPhases;
  Sphere(P, MarbleRadius, Asset);
end;

function TMarblePainter.SectionVisible(const Section: TMarbleSection): Boolean;
begin
  Result := (Section.Left <= Left + Width + 1.25) and (Section.Right >= Left - 1.25) and
    (Section.Top >= Top - Height - 1.25) and (Section.Bottom <= Top + 1.25);
end;

procedure TMarblePainter.Course(const P: TBallPoint);
var Section: TMarbleSection; I: Integer; Leg, Previous: TMarbleLeg; A, B, JoinA, JoinB: TBallPoint;
begin
  if Length(Plan.Legs) = 0 then
  begin
    Rail(BallPoint(P.X - 1.2, P.Y - MarbleRadius), BallPoint(P.X + 0.3, P.Y - MarbleRadius));
    Exit;
  end;
  // 折り返した先の仕掛けも、画面内にあれば先に見せる。
  for Section in Plan.Sections do
    if SectionVisible(Section) then
      for I := Section.First to Section.Last do
      begin
        Leg := Plan.Legs[I];
        if Leg.Motion = mmSeesaw then
        begin
          Leg.RailSupport(A, B);
          JoinA := Leg.Board.PointAt(Leg.Dock, Leg.Board.Front, 0);
          Line(JoinA.X, JoinA.Y - 0.021, A.X, A.Y - 0.021, 0.037, Colors.TimberEdge);
          Rail(A, B);
          if Leg.HasWeightLift and Leg.LiftRailSupport(A, B) then Rail(A, B);
          Continue;
        end;
        if Leg.Motion <> mmRail then Continue;
        Leg.RailSupport(A, B);
        if I = 0 then A := BallAdd(A, BallPoint(-0.65, -0.65 * Leg.RailSlope));
        if (Plan.Version >= 3) and (I > 0) then
        begin
          Previous := Plan.Legs[I - 1];
          if Previous.Rollout then
            Rail(MarbleRailSurface(Previous.Carriage(Previous.Dock), Previous.RailSlope), A)
          else if (Previous.Motion in [mmRail, mmSeesaw]) and (Previous.DropLip = 0) and (Leg.EntryGap = 0) then
          begin
            if Previous.Junction.Active then Previous.BranchRailSupport(JoinA, JoinB)
            else if Previous.HasWeightLift then Previous.LiftRailSupport(JoinA, JoinB)
            else Previous.RailSupport(JoinA, JoinB);
            Line(JoinB.X, JoinB.Y - 0.02, A.X, A.Y - 0.02, 0.042, Colors.TimberEdge);
          end;
        end;
        if Leg.Junction.Active then
        begin
          Rail(A, B);
          Leg.BranchRailSupport(JoinA, JoinB);
          Line(B.X, B.Y - 0.022, JoinA.X, JoinA.Y - 0.022, 0.052, Colors.TimberEdge);
          Rail(Leg.Junction.Tip(Leg.Junction.Ready, Leg.Heading), JoinB);
          Leg.Junction.Spur(A, B, Leg.Heading);
          Rail(A, B);
          Dot(B.X, B.Y, 0.056, Colors.Alloy);
          Continue;
        end;
        if Leg.Bridge.Active then
        begin
          Rail(A, Leg.Bridge.Entry);
          Rail(Leg.Bridge.Hinge, B);
        end
        else Rail(A, B);
      end;
  for Section in Plan.Sections do
    if SectionVisible(Section) then
      for I := Max(1, Section.First) to Section.Last do Device(I - 1);
  if Length(Plan.Links) > 0 then
    for Section in Plan.Sections do
      if SectionVisible(Section) then
        for I := Max(1, Section.First) to Section.Last do Linkage(Plan.Links[I - 1]);
end;

procedure TMarblePainter.NeonTrail;
var Leg: TMarbleLeg; A, B: TBallPoint; Start, Slope: Double;
begin
  if Length(Plan.Legs) = 0 then Exit;
  Leg := Plan.Legs[Plan.CueAt(Time) + 1];
  if Leg.Motion <> mmRail then Exit;
  Start := Max(Leg.Start, Time - 0.13);
  Slope := Leg.RailSlope;
  if Leg.Junction.Active and (Time >= Leg.Junction.Branch.Start) then
  begin
    Start := Max(Start, Leg.Junction.Branch.Start);
    Slope := Leg.Heading * Leg.Junction.Branch.Grade;
  end;
  A := MarbleRailSurface(Leg.Position(Start), Slope);
  B := MarbleRailSurface(Leg.Position(Time), Slope);
  Art.Line(A, B, 0.107, Colors.Aqua, 0.28);
  Art.Line(A, B, 0.024, Colors.Pearl, 0.89);
end;

procedure TMarblePainter.Paint;
var P, Camera: TBallPoint; CenterX: Double;
begin
  Time := EnsureRange(Frame.Time, 0.0, Plan.EndTime);
  Scale := Max(1.0, Min(Frame.Height / 3.75, Frame.Width / 5.8));
  Width := Frame.Width / Scale;
  Height := Frame.Height / Scale;
  P := Plan.Position(Time);
  Camera := Plan.CameraTarget(Time);
  CenterX := 0.40;
  if Plan.Version >= 2 then CenterX := 0.50;
  Left := Camera.X - Width * CenterX;
  Top := Camera.Y + Height * 0.54;
  Colors := MarblePalette(StageStyle);
  Art.Surface := Surface;
  Art.Style := StageStyle;
  Art.Colors := Colors;
  Art.Left := Left;
  Art.Top := Top;
  Art.Scale := Scale;
  DrawMarbleBackdrop(Art, Width, Height);
  Course(P);
  if not Frame.BackgroundOnly then
  begin
    if StageStyle = msNeonArcade then NeonTrail;
    Ball(P);
  end;
end;

destructor TMarbleAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TMarbleAnimation.SetReference(const Ref: TRhythmPlanRef);
begin
  FRef := Ref;
end;

procedure TMarbleAnimation.Prepare(const Frame: TAnimationFrame);
var Key: string;
begin
  Key := FRef.Key + '|' + FRef.Digest + '|' + IntToStr(Frame.Direction);
  if Audio <> nil then Key := Key + '|' + Audio.Key else Key := Key + '|none';
  if Key = FAttempt then Exit;
  FAttempt := Key;
  FreeAndNil(FPlan);
  FError := '';
  if Audio = nil then Exit;
  try
    FPlan := LoadMarblePlan(FRef, Audio, Frame.Direction);
  except
    on E: Exception do FError := E.Message;
  end;
end;

procedure TMarbleAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
var Painter: TMarblePainter;
begin
  if FPlan = nil then Exit;
  Painter.Surface := Surface;
  Painter.Frame := Frame;
  Painter.Plan := FPlan;
  Painter.BallStyle := BallStyle;
  Painter.StageStyle := StageStyle;
  Painter.Paint;
end;

function TMarbleAnimation.Notice: string;
begin
  Result := FError;
end;

function TMarbleAnimation.GoalTime: Double;
begin
  Result := 0; // 最後の球受けがこの演出の終点。
end;

function TMarbleAnimation.Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
var I: Integer; Age: Double; Beat: TMarbleBeat;
begin
  Result := True;
  Value := Default(TEqualizerActivity);
  if FPlan = nil then Exit;
  I := FPlan.BeatAt(Time, Beat);
  if I < 0 then Exit;
  Age := Time - Beat.Time;
  if Age > 0.65 then Exit;
  Value.Valid := True;
  Value.Hit := I;
  Value.Pulse := (0.6 + 0.4 * Beat.Power) * Exp(-Age * 10);
  Value.Energy := (0.35 + 0.65 * Beat.Power) * Exp(-Age * 4);
end;

end.
