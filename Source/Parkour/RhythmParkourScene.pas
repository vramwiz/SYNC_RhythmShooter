unit RhythmParkourScene;
// 都市の屋上と主人公を描く。接触・カメラ・ポーズはすべて絶対時刻から復元する。
interface

uses RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmParkourPlan, RhythmRenderSurface, RhythmEqualizer;

type
  TParkourAnimation = class(TAnimationScene)
  private
    FPlan: TParkourPlan;
    FRef: TRhythmPlanRef;
    FAttempt, FError: string;
  public
    Audio: TRhythmAudio; // 借用。保存計画の照合にだけ使う。
    destructor Destroy; override;
    procedure SetReference(const Ref: TRhythmPlanRef);
    procedure Prepare(const Frame: TAnimationFrame); override;
    procedure Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame); override;
    function Notice: string; override;
    function GoalTime: Double; override;
    function Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
  end;

implementation

uses System.Types, System.SysUtils, System.Math, Vcl.Graphics, Winapi.Windows;

type
  TParkourPainter = record
    Surface: TAnimationRenderSurface;
    Plan: TParkourPlan;
    Frame: TAnimationFrame;
    Scale, Left, Top, ViewWidth, Time: Double;
    First, Last: Integer;
    procedure Bar(X1, Y1, X2, Y2: Double; Color: TColor);
    procedure Line(X1, Y1, X2, Y2, Stroke: Double; Color: TColor);
    procedure Dot(X, Y, Radius: Double; Color: TColor);
    procedure Skyline(CameraX, CameraY: Double);
    procedure Roof(A, B, Y: Double);
    procedure City;
    procedure Burst(X, Y, Age: Double; Color: TColor);
    procedure ContactEffects(const Move: TParkourMove);
    procedure Runner(const P: TParkourPoint; Index: Integer);
    procedure Paint;
  end;

const
  Ink = $00272132;
  Jacket = $004178F5;
  JacketLight = $005DBBFF;
  Trousers = $00553E47;
  FarLimb = $00704B57;
  Skin = $0095D5FF;
  Chalk = $00F4F5FF;
  WireLight = $00FFF0A0;
  Impact = $0071D5FF;
  RunLean = 0.12;

procedure TParkourPainter.Bar(X1, Y1, X2, Y2: Double; Color: TColor);
begin
  Surface.FillRect(Max(0.0, (X1 - Left) * Scale), Max(0.0, (Top - Y2) * Scale),
    Min(Frame.Width * 1.0, (X2 - Left) * Scale), Min(Frame.Height * 1.0, (Top - Y1) * Scale), Color);
end;

procedure TParkourPainter.Line(X1, Y1, X2, Y2, Stroke: Double; Color: TColor);
begin
  Surface.Line((X1 - Left) * Scale, (Top - Y1) * Scale, (X2 - Left) * Scale, (Top - Y2) * Scale,
    Color, Max(1.0, Stroke * Scale));
end;

procedure TParkourPainter.Dot(X, Y, Radius: Double; Color: TColor);
begin
  Surface.Circle((X - Left) * Scale, (Top - Y) * Scale, Radius * Scale, Color, True);
end;

procedure TParkourPainter.Skyline(CameraX, CameraY: Double);
const Facades: array[0..2] of TColor = ($00716385, $00565174, $00434563);
var I, Layer, Cell, Row: Integer; U, Size, Scroll, X, Y, Base: Double;
begin
  for I := 0 to 17 do
  begin
    U := I / 17;
    Surface.FillRect(0, Frame.Height * I / 18, Frame.Width, Frame.Height * (I + 1) / 18,
      RGB(Round(69 + 126 * U), Round(54 + 61 * U), Round(102 + 23 * U)));
  end;
  Surface.Circle(Frame.Width * 0.73, Frame.Height * 0.31,
    Min(Frame.Width, Frame.Height) * 0.13, RGB(250, 172, 141), True);
  for Layer := 0 to 2 do
  begin
    Size := 1.55 + Layer * 0.62;
    Scroll := CameraX * (0.12 + Layer * 0.20);
    Base := Top - Frame.Height / Scale * (0.54 + Layer * 0.12) - CameraY * (0.09 + Layer * 0.04);
    for Cell := Floor((Scroll - ViewWidth * 0.5) / Size) - 1 to Ceil((Scroll + ViewWidth * 0.5) / Size) + 1 do
    begin
      X := Left + ViewWidth * 0.5 + Cell * Size - Scroll;
      Y := Base + 0.27 * (6 + (Abs(Cell * 13 + Layer * 7) mod 11));
      Bar(X, Top - Frame.Height / Scale, X + Size * 0.88, Y, Facades[Layer]);
      Bar(X + Size * 0.18, Y, X + Size * 0.55, Y + 0.22, Facades[Layer]);
      if Layer = 2 then
        for Row := 1 to 4 do
          if (Abs(Cell + Row * 7) mod 4) <> 0 then
            Bar(X + Size * 0.20, Y - Row * 0.45, X + Size * 0.35, Y - Row * 0.45 + 0.10, $00857893);
    end;
  end;
end;

procedure TParkourPainter.Roof(A, B, Y: Double);
var Cell, Row: Integer; X, Bottom, WindowY: Double;
begin
  if (B <= A) or (B < Left) or (A > Left + ViewWidth) then Exit;
  Bottom := Top - Frame.Height / Scale;
  Bar(A, Bottom, B, Y, $003B3045);
  Bar(A, Y - 0.25, B, Y, $00828B9C);
  Bar(A, Y - 0.36, B, Y - 0.24, $004E4B65);
  for Cell := Floor(Max(A, Left) / 0.91) to Ceil(Min(B, Left + ViewWidth) / 0.91) do
  begin
    X := Cell * 0.91 + 0.10;
    for Row := Max(0, Floor((Y - Top - 0.70) / 0.74)) to Floor((Y - Bottom - 0.45) / 0.74) do
    begin
      WindowY := Y - 0.90 - Row * 0.74;
      Bar(Max(A, X), WindowY, Min(B, X + 0.50), WindowY + 0.35, $00554B64);
      if (Abs(Cell * 3 + Row * 11) mod 5) < 2 then
        Bar(Max(A, X + 0.07), WindowY + 0.08, Min(B, X + 0.42), WindowY + 0.28, $006D9DB7);
    end;
  end;
end;

procedure TParkourPainter.City;
var I, J: Integer; A, B, Y, X: Double; Move: TParkourMove; Finish, Step, Grip: TParkourPoint;
begin
  for I := First to Min(Last, High(Plan.Moves)) do
  begin
    Move := Plan.Moves[I];
    if Move.Kind <> pkWire then Continue;
    X := Move.Anchor.X;
    Y := Move.Anchor.Y;
    if (X < Left - 1) or (X > Left + ViewWidth + 1) then Continue;
    Bar(X - 0.05, Top - Frame.Height / Scale, X + 0.05, Y + 0.34, $0063647D);
    Line(X - 0.60, Y + 0.32, X + 0.60, Y + 0.32, 0.11, $007B718A);
    Line(X + 0.58, Y + 0.32, X + 0.06, Y - 0.28, 0.06, $007B718A);
    Dot(X, Y, 0.10, WireLight);
  end;
  for I := First to Last do
  begin
    A := -7;
    Y := 0;
    if I > 0 then
    begin
      Move := Plan.Moves[I - 1];
      A := Move.RoofLeft;
      if Move.Kind in [pkVault, pkStride] then A := Move.Landing.X;
      Y := Move.Landing.Y;
    end;
    if I < Length(Plan.Moves) then
    begin
      Move := Plan.Moves[I];
      B := Move.Origin.X;
      if Move.Kind in [pkVault, pkStride] then B := Move.Landing.X;
    end
    else
    begin
      Finish := Plan.Position(Plan.Duration);
      B := Finish.X + 5;
    end;
    Roof(A, B, Y);
  end;
  for I := First to Min(Last, High(Plan.Moves)) do
  begin
    Move := Plan.Moves[I];
    X := Move.Origin.X + 0.45;
    Y := Move.Origin.Y;
    case Move.Kind of
      pkVault:
        begin
          Bar(X - 0.06, Y, X + 0.06, Y + 0.81, $00596B86);
          Bar(X - 0.13, Y + 0.75, X + 0.13, Y + 0.85, Chalk);
        end;
      pkWall:
        begin
          X := Move.RoofLeft;
          Bar(X, Move.Contact.Y - 0.20, X + 0.18, Move.Landing.Y, $00738099);
          Bar(X, Move.Contact.Y - 0.08, X + 0.18, Move.Contact.Y + 0.08, Impact);
        end;
      pkDrop:
        Bar(Move.Origin.X - 0.30, Y - 0.20, Move.Origin.X, Y, Impact);
      pkStride:
        for J := 0 to High(Move.Steps) do
        begin
          Step := Move.StepPoint(J);
          Bar(Step.X - 0.22, Y, Step.X + 0.28, Step.Y, $005D5774);
          Bar(Step.X - 0.22, Step.Y - 0.035, Step.X + 0.28, Step.Y, $00C7BBCF);
        end;
      pkWallRun:
        begin
          X := Move.RoofLeft;
          Bar(X, Move.Contact.Y - 0.23, X + 0.20, Move.Landing.Y, $00738099);
          for J := 0 to High(Move.Steps) do
          begin
            Step := Move.StepPoint(J);
            Bar(X, Step.Y - 0.08, X + 0.16, Step.Y + 0.08, $00C7BBCF);
            if J = High(Move.Steps) then Continue;
            Grip := Move.WallGripPoint(J);
            Bar(Grip.X - 0.06, Grip.Y - 0.09, X + 0.30, Grip.Y, $005D5774);
            Bar(Grip.X - 0.06, Grip.Y - 0.035, X + 0.30, Grip.Y, $00DFBEAC);
          end;
        end;
    end;
  end;
end;

procedure TParkourPainter.Burst(X, Y, Age: Double; Color: TColor);
var I: Integer; Angle, Inner, Outer, DX, DY: Double;
begin
  if (Age < 0) or (Age > 0.22) then Exit;
  if Age < 0.06 then Dot(X, Y, 0.09 - Age, Chalk);
  for I := 0 to 6 do
  begin
    Angle := I * 2.39996;
    Inner := 0.13 + Age * (1.8 + (I mod 3) * 0.6);
    Outer := Inner + 0.22 * (1 - Age / 0.23);
    DX := Cos(Angle);
    DY := Sin(Angle);
    Line(X + Inner * DX, Y + Inner * DY, X + Outer * DX, Y + Outer * DY,
      0.038 * (1 - Age / 0.23), Color);
  end;
end;

procedure TParkourPainter.ContactEffects(const Move: TParkourMove);
var Detach, Step: TParkourPoint; I: Integer; Age, Span: Double;
begin
  case Move.Kind of
    pkVault: Burst(Move.Origin.X + 0.45, Move.Origin.Y + 0.80, Time - Move.Cue, Impact);
    pkWall: Burst(Move.RoofLeft, Move.Contact.Y, Time - Move.Cue, Impact);
    pkWire:
      begin
        Burst(Move.Anchor.X, Move.Anchor.Y, Time - Move.Cue, WireLight);
        Detach := Move.Position(Move.Release);
        Burst(Detach.X + ParkourHandOffset, Detach.Y + ParkourHandHeight, Time - Move.Release, WireLight);
      end;
    pkDrop: Burst(Move.Origin.X, Move.Origin.Y, Time - Move.Cue, Impact);
    pkStride, pkWallRun:
      for I := 0 to High(Move.Steps) do
      begin
        Age := Time - Move.Steps[I];
        if (Age < 0) or (Age > 0.11) then Continue;
        Step := Move.StepPoint(I);
        if Move.Kind = pkWallRun then Step.X := Move.RoofLeft;
        if (Move.Kind = pkWallRun) and (I = High(Move.Steps)) then
          Burst(Step.X, Step.Y, Age, Impact)
        else
        begin
          Span := 0.08 + Age * 1.4;
          Dot(Step.X, Step.Y, 0.065 * (1 - Age / 0.12), Chalk);
          Line(Step.X - Span, Step.Y + Span * 0.5, Step.X - Span - 0.12,
            Step.Y + Span * 0.85, 0.026, Impact);
          Line(Step.X + Span * 0.56, Step.Y + Span * 0.8, Step.X + Span,
            Step.Y + Span + 0.07, 0.026, Impact);
        end;
      end;
  end;
  if Move.LandSynced then Burst(Move.Landing.X, Move.Landing.Y, Time - Move.Finish, Impact);
end;

procedure TParkourPainter.Runner(const P: TParkourPoint; Index: Integer);
var Move: TParkourMove; Kind: TParkourKind; InMove, Attached, Climbing, NearWall, FarWall: Boolean;
  U, Phase, S, Lean, Hip, Shoulder, NearFoot, FarFoot, NearLift, FarLift, HandX, HandY, Aim: Double;
  LandingAge, Bend, Weight, RunNear, RunFar, LiftNear, LiftFar: Double;
  FarHandX, FarHandY: Double;
  StepIndex, GripIndex: Integer;
  Grip: TParkourPoint;

  procedure Step(Cycle: Double; out Foot, Lift: Double);
  var Swing: Double;
  begin
    if Cycle < 0.60 then
    begin
      Foot := 0.36 - 1.20 * Cycle;
      Lift := 0;
    end
    else
    begin
      Swing := (Cycle - 0.60) / 0.40;
      Foot := -0.36 + 0.72 * Swing;
      Lift := 0.29 * Sin(Pi * Swing);
    end;
  end;

  procedure Limb(X1, Y1, X2, Y2, Stroke: Double; Color: TColor);
  begin
    Line(P.X + X1, P.Y + Y1, P.X + X2, P.Y + Y2, Stroke, Ink);
    Line(P.X + X1, P.Y + Y1, P.X + X2, P.Y + Y2, Stroke * 0.70, Color);
  end;

  procedure BlendTouchdown(Amount: Double);
  begin
    Lean := Lean * (1 - Amount) + 0.19 * Amount;
    Hip := Hip * (1 - Amount) + 0.52 * Amount;
    NearFoot := NearFoot * (1 - Amount);
    FarFoot := FarFoot * (1 - Amount) - 0.23 * Amount;
    NearLift := NearLift * (1 - Amount);
    FarLift := FarLift * (1 - Amount);
    HandX := HandX * (1 - Amount) + 0.22 * Amount;
    HandY := HandY * (1 - Amount) + 0.66 * Amount;
  end;

  procedure ReachStep(AtIndex: Integer);
  var Target: TParkourPoint; Amount: Double;
  begin
    Amount := Max(0.0, 1 - Abs(Time - Move.Steps[AtIndex]) / 0.13);
    if Amount = 0 then Exit;
    Target := Move.StepPoint(AtIndex);
    if Kind = pkWallRun then Target.X := Move.RoofLeft;
    Amount := Sqr(Amount) * (3 - 2 * Amount);
    if Odd(AtIndex) then
    begin
      FarFoot := FarFoot * (1 - Amount) + (Target.X - P.X) * Amount;
      FarLift := FarLift * (1 - Amount) + (Target.Y - P.Y) * Amount;
      FarWall := (Kind = pkWallRun) and (Amount > 0.6);
    end
    else
    begin
      NearFoot := NearFoot * (1 - Amount) + (Target.X - P.X) * Amount;
      NearLift := NearLift * (1 - Amount) + (Target.Y - P.Y) * Amount;
      NearWall := (Kind = pkWallRun) and (Amount > 0.6);
    end;
  end;

  procedure Shoe(Foot, Lift: Double; OnWall: Boolean; Color: TColor);
  begin
    if OnWall then Limb(Foot - 0.11, Lift + 0.04, Foot, Lift, 0.10, Color)
    else Limb(Foot, Lift + 0.04, Foot + 0.14, Lift + 0.04, 0.10, Color);
  end;

  procedure BraceHand(const Target: TParkourPoint; Amount: Double; Far: Boolean);
  begin
    if Far then
    begin
      FarHandX := FarHandX * (1 - Amount) + (Target.X - P.X) * Amount;
      FarHandY := FarHandY * (1 - Amount) + (Target.Y - P.Y) * Amount;
    end
    else
    begin
      HandX := HandX * (1 - Amount) + (Target.X - P.X) * Amount;
      HandY := HandY * (1 - Amount) + (Target.Y - P.Y) * Amount;
    end;
  end;

  procedure ClimbingArm(X, Y, BendX: Double; Sleeve, Hand: TColor);
  var ElbowX, ElbowY: Double;
  begin
    ElbowX := (Lean + X) * 0.5 + BendX;
    ElbowY := (Shoulder + Y) * 0.5 - 0.08;
    Limb(Lean, Shoulder, ElbowX, ElbowY, 0.15, Sleeve);
    Limb(ElbowX, ElbowY, X, Y, 0.10, Hand);
    Dot(P.X + X, P.Y + Y, 0.048, Hand);
  end;

begin
  Move := Default(TParkourMove);
  if Index >= 0 then Move := Plan.Moves[Index];
  InMove := (Index >= 0) and (Time < Move.Finish);
  if not InMove and (Index < High(Plan.Moves)) and (Plan.Moves[Index + 1].Start - Time <= 0.14) then
  begin
    Move := Plan.Moves[Index + 1];
    InMove := True;
  end;
  Kind := Move.Kind;
  Climbing := InMove and (Kind = pkWallRun);
  Attached := InMove and (Kind = pkWire) and (Time >= Move.Cue) and (Time <= Move.Release);
  Phase := Frac(P.X / 1.20);
  Step(Phase, RunNear, LiftNear);
  Step(Frac(Phase + 0.50), RunFar, LiftFar);
  S := Sin(2 * Pi * Phase);
  if (Time >= Plan.RunEnd) or (Length(Plan.Moves) = 0) then
  begin
    S := 0;
    RunNear := 0.13;
    RunFar := -0.13;
    LiftNear := 0;
    LiftFar := 0;
  end;
  Lean := RunLean;
  NearWall := False;
  FarWall := False;
  Hip := 0.69 + 0.055 * Abs(S);
  NearFoot := RunNear;
  FarFoot := RunFar;
  NearLift := LiftNear;
  FarLift := LiftFar;
  HandX := 0.02 - 0.27 * S;
  HandY := 0.74;
  LandingAge := Time - Move.Finish;
  if InMove then
  begin
    U := EnsureRange((Time - Move.Cue) / (Move.Finish - Move.Cue), 0.0, 1.0);
    case Kind of
      pkVault:
        begin
          Bend := Sin(Pi * U);
          Hip := 0.64 - 0.26 * Bend;
          Lean := 0.23 - 0.11 * U;
          HandX := 0.45 - 0.31 * Bend;
          HandY := 0.80 + 0.28 * Bend;
          NearFoot := 0.31 * Bend;
          FarFoot := -0.34 * Bend;
          NearLift := 0.26 * Bend;
          FarLift := 0.19 * Bend;
        end;
      pkWall:
        begin
          Bend := Sin(Pi * U);
          Lean := -0.20 * (1 - U) + 0.11 * U;
          NearWall := Time <= Move.Cue + 0.10;
          NearFoot := ParkourWallFoot * (1 - U) + 0.25 * Bend;
          FarFoot := -0.36 * Bend - 0.16 * (1 - U);
          NearLift := 0.29 * Bend;
          FarLift := 0.20 + 0.18 * Bend;
          HandX := 0.16 + 0.31 * Bend;
          HandY := 0.88 + 0.28 * Bend;
        end;
      pkWire:
        begin
          Lean := -0.06;
          NearFoot := -0.20;
          FarFoot := -0.34;
          NearLift := 0.09;
          FarLift := 0.23;
          HandX := ParkourHandOffset;
          HandY := ParkourHandHeight;
          if Time > Move.Release then
          begin
            U := (Time - Move.Release) / (Move.Finish - Move.Release);
            NearFoot := -0.20 + 0.55 * Sin(Pi * U);
            HandX := ParkourHandOffset * (1 - U) + 0.35 * Sin(Pi * U);
            HandY := ParkourHandHeight - 0.42 * U;
          end;
        end;
      pkDrop:
        begin
          Lean := 0.10 - 0.18 * U;
          Hip := 0.67 - 0.18 * Sqr(U);
          NearFoot := 0.39 * Sin(Pi * U);
          FarFoot := -0.32 * Sin(Pi * U);
          NearLift := 0.15 * Sin(Pi * U);
          FarLift := 0.36 * Sin(Pi * U);
          HandX := 0.46 * Sin(Pi * U);
          HandY := 0.85 + 0.32 * Sin(Pi * U);
        end;
      pkWallRun:
        begin
          Lean := -0.06;
          NearFoot := 0.09;
          FarFoot := -0.13;
          NearLift := 0.22;
          FarLift := 0.23;
          HandX := 0.22 + 0.08 * S;
          HandY := 0.96;
          if Time > Move.Release then
          begin
            U := (Time - Move.Release) / (Move.Finish - Move.Release);
            Bend := Sin(Pi * U);
            Hip := Hip - 0.34 * Bend;
            Lean := Lean + 0.22 * Bend;
            NearFoot := NearFoot + 0.23 * Bend;
            FarFoot := FarFoot - 0.19 * Bend;
            NearLift := NearLift + 0.13 * Bend;
            FarLift := FarLift + 0.19 * Bend;
          end;
        end;
    end;
    if Time < Move.Cue then
    begin
      Weight := (Time - Move.Start + 0.14) / (Move.Cue - Move.Start + 0.14);
      Weight := Sqr(Weight) * (3 - 2 * Weight);
      Lean := RunLean * (1 - Weight) + Lean * Weight;
      Hip := (0.69 + 0.055 * Abs(S)) * (1 - Weight) + Hip * Weight;
      NearFoot := RunNear * (1 - Weight) + NearFoot * Weight;
      FarFoot := RunFar * (1 - Weight) + FarFoot * Weight;
      NearLift := LiftNear * (1 - Weight) + NearLift * Weight;
      FarLift := LiftFar * (1 - Weight) + FarLift * Weight;
      HandX := (0.02 - 0.27 * S) * (1 - Weight) + HandX * Weight;
      HandY := 0.74 * (1 - Weight) + HandY * Weight;
    end;
    if (Kind <> pkStride) and (Move.Finish - Time < 0.14) then
      BlendTouchdown(1 - (Move.Finish - Time) / 0.14);
  end
  else if (Index >= 0) and (Kind <> pkStride) and (LandingAge < 0.18) then
    BlendTouchdown(1 - LandingAge / 0.18);
  if InMove and (Kind in [pkStride, pkWallRun]) then
  begin
    StepIndex := Move.StepAt(Time);
    if StepIndex >= 0 then ReachStep(StepIndex);
    if StepIndex < High(Move.Steps) then ReachStep(StepIndex + 1);
  end;
  Shoulder := Hip + 0.37;
  if Climbing then
  begin
    FarHandX := Lean - 0.36;
    FarHandY := Shoulder - 0.37;
    for GripIndex := 0 to High(Move.Steps) do
      BraceHand(Move.WallGripPoint(GripIndex), Move.WallGripWeight(GripIndex, Time), not Odd(GripIndex));
    if Time > Move.Release then
    begin
      GripIndex := High(Move.Steps);
      Grip := Move.WallGripPoint(GripIndex);
      Grip.X := Grip.X + 0.13;
      U := (Time - Move.Release) / (Move.Finish - Move.Release);
      Weight := Min(1.0, U / 0.19);
      BraceHand(Grip, Weight * Move.WallGripWeight(GripIndex, Time), Odd(GripIndex));
    end;
  end;
  if Attached then
    Line(P.X + HandX, P.Y + HandY, Move.Anchor.X, Move.Anchor.Y, 0.038, WireLight)
  else if InMove and (Kind = pkWire) and (Time < Move.Cue) then
  begin
    Aim := EnsureRange(1 - (Move.Cue - Time) / 0.15, 0.0, 1.0);
    if Aim > 0 then
      Line(P.X + HandX, P.Y + HandY, P.X + HandX + (Move.Anchor.X - P.X - HandX) * Aim,
        P.Y + HandY + (Move.Anchor.Y - P.Y - HandY) * Aim, 0.029, WireLight);
  end;
  Limb(0, Hip, FarFoot * 0.70 + 0.09, (Hip + FarLift) * 0.48, 0.15, FarLimb);
  Limb(FarFoot * 0.70 + 0.09, (Hip + FarLift) * 0.48, FarFoot, FarLift + 0.04, 0.13, FarLimb);
  Shoe(FarFoot, FarLift, FarWall, $00C7BBCF);
  if Climbing then ClimbingArm(FarHandX, FarHandY, 0.08, $005781CB, $0083B9E7)
  else
  begin
    Limb(Lean, Shoulder, Lean - 0.30, Shoulder - 0.14, 0.15, FarLimb);
    Limb(Lean - 0.30, Shoulder - 0.14, Lean - 0.36, Shoulder - 0.37, 0.12, FarLimb);
  end;
  Limb(0, Hip, NearFoot * 0.75 + 0.11, (Hip + NearLift) * 0.53, 0.19, Trousers);
  Limb(NearFoot * 0.75 + 0.11, (Hip + NearLift) * 0.53, NearFoot, NearLift + 0.05, 0.14, Trousers);
  Shoe(NearFoot, NearLift, NearWall, Chalk);
  Limb(0, Hip + 0.03, Lean, Shoulder, 0.34, Jacket);
  Limb(Lean - 0.03, Shoulder - 0.13, Lean - 0.30, Shoulder - 0.18 + 0.05 * Sin(P.X * 3), 0.08, JacketLight);
  if Climbing then ClimbingArm(HandX, HandY, -0.13, JacketLight, Skin)
  else
  begin
    Limb(Lean, Shoulder, (Lean + HandX) * 0.50 - 0.09, (Shoulder + HandY) * 0.50 - 0.11, 0.15, JacketLight);
    Limb((Lean + HandX) * 0.50 - 0.09, (Shoulder + HandY) * 0.50 - 0.11, HandX, HandY, 0.10, Skin);
  end;
  Dot(P.X + Lean + 0.04, P.Y + Shoulder + 0.19, 0.17, Ink);
  Dot(P.X + Lean + 0.075, P.Y + Shoulder + 0.17, 0.132, Skin);
  Line(P.X + Lean - 0.06, P.Y + Shoulder + 0.26, P.X + Lean + 0.19, P.Y + Shoulder + 0.24, 0.075, JacketLight);
end;

procedure TParkourPainter.Paint;
var P, Ahead, Behind: TParkourPoint; CX, CY, Window: Double; Index, I: Integer;
begin
  Time := EnsureRange(Frame.Time, 0.0, Plan.Duration);
  P := Plan.Position(Time);
  Ahead := Plan.Position(Time + 0.23);
  Behind := Plan.Position(Time - 0.23);
  Scale := Max(1.0, Min(Frame.Width / 12.0, Frame.Height / 8.6));
  ViewWidth := Frame.Width / Scale;
  CX := 0.60 * P.X + 0.22 * Ahead.X + 0.18 * Behind.X + Min(1.35, ViewWidth * 0.11);
  CY := 0.52 * P.Y + 0.24 * (Ahead.Y + Behind.Y) + 1.30;
  Left := CX - ViewWidth * 0.5;
  Top := CY + Frame.Height / Scale * 0.5;
  Window := 3 + ViewWidth / 4.6;
  First := Max(0, Plan.MoveAt(Time - Window));
  Last := Min(Length(Plan.Moves), Plan.MoveAt(Time + Window) + 1);
  Skyline(CX, CY);
  City;
  if Frame.BackgroundOnly then Exit;
  Index := Plan.MoveAt(Time);
  Runner(P, Index);
  for I := Max(0, Index - 1) to Index do ContactEffects(Plan.Moves[I]);
end;

destructor TParkourAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TParkourAnimation.SetReference(const Ref: TRhythmPlanRef);
begin
  FRef := Ref;
end;

procedure TParkourAnimation.Prepare(const Frame: TAnimationFrame);
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
    FPlan := LoadParkourPlan(FRef, Audio, Frame.Direction);
  except
    on E: Exception do FError := E.Message;
  end;
end;

procedure TParkourAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
var Painter: TParkourPainter;
begin
  if FPlan = nil then Exit;
  Painter.Surface := Surface;
  Painter.Frame := Frame;
  Painter.Plan := FPlan;
  Painter.Paint;
end;

function TParkourAnimation.Notice: string;
begin
  Result := FError;
end;

function TParkourAnimation.GoalTime: Double;
begin
  Result := 0; // 試作の締めは最後の屋上への着地と減速。
end;

function TParkourAnimation.Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
var I, StepIndex: Integer; Move: TParkourMove;
  procedure Pulse(Cue: Double);
  var Age: Double;
  begin
    Age := Time - Cue;
    if (Age < 0) or (Age > 0.6) then Exit;
    Value.Valid := True;
    Value.Hit := I;
    Value.Pulse := Max(Value.Pulse, Exp(-Age * 9));
    Value.Energy := Max(Value.Energy, 0.75 * Exp(-Age * 4));
  end;
begin
  Result := True;
  Value := Default(TEqualizerActivity);
  if FPlan = nil then Exit;
  I := FPlan.MoveAt(Time);
  if I < 0 then Exit;
  Move := FPlan.Moves[I];
  StepIndex := Move.StepAt(Time);
  if StepIndex >= 0 then Pulse(Move.Steps[StepIndex]) else Pulse(Move.Cue);
  if Move.Kind = pkWire then Pulse(Move.Release);
  if Move.LandSynced then Pulse(Move.Finish);
end;

end.
