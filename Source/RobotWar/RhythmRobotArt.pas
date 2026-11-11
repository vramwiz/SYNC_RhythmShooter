unit RhythmRobotArt;
// 都市・装甲・武装・衝撃を共通Surfaceで描く。画像資産やフレーム間の状態を使わない。
interface

uses RhythmRobotPlan, RhythmRobotPose, RhythmRenderSurface, RhythmAnimation;

procedure DrawRobotWar(Surface: TAnimationRenderSurface; Plan: TRobotPlan; const Frame: TAnimationFrame);

implementation

uses System.Types, System.Math, Vcl.Graphics, Winapi.Windows;

type
  TRobotPainter = record
    Surface: TAnimationRenderSurface;
    Plan: TRobotPlan;
    Frame: TAnimationFrame;
    View: TRobotView;
    Scale, Left, Top, Time: Double;
    function Project(X, Y: Double): TPointF;
    function Local(const P: TRobotPart; X, Y: Double): TPointF;
    procedure Quad(const A, B, C, D: TPointF; Color: TColor);
    procedure Bar(X1, Y1, X2, Y2: Double; Color: TColor);
    procedure Line(X1, Y1, X2, Y2, Width: Double; Color: TColor);
    procedure Dot(X, Y, Radius: Double; Color: TColor; Filled: Boolean = True);
    procedure Plate(const P: TRobotPart; Color: TColor);
    procedure Detail(const P: TRobotPart; Kind: TRobotPartKind; Color, Light: TColor; Facing, Glow: Double);
    procedure City;
    procedure Robot(const Body: TRobotBody);
    procedure Burst(X, Y, Age, Power: Double; Color: TColor);
    procedure Smoke(X, Y, Age, Power: Double);
    procedure BattleEffects;
    procedure MechanismEffects;
    procedure Paint;
  end;

const
  Ink = $00281D17;
  Metal = $007C7465;
  Silver = $00E3DED1;
  Gold = $008ED7FF;
  AllyColors: array[0..3] of TColor = ($00E98C32, $003BCFED, $005252E8, $00ECE6DD);
  EnemyAccents: array[0..2] of TColor = ($00EC70C3, $007BDE78, $005F9FF6);
  DrawOrder: array[0..24] of TRobotPartKind =
    (rpWingL, rpWingR, rpEngineL, rpEngineR, rpThighL, rpShinL, rpFootL,
     rpArmL, rpForearmL, rpHandL, rpWheelL, rpThighR, rpShinR, rpFootR, rpWheelR,
     rpHip, rpTorso, rpShoulderL, rpShoulderR, rpChest, rpHead, rpArmR, rpForearmR, rpHandR, rpWeapon);

function Shade(Color, Target: TColor; Weight: Double): TColor;
begin
  Result := RGB(Round(GetRValue(Color) + (GetRValue(Target) - GetRValue(Color)) * Weight),
    Round(GetGValue(Color) + (GetGValue(Target) - GetGValue(Color)) * Weight),
    Round(GetBValue(Color) + (GetBValue(Target) - GetBValue(Color)) * Weight));
end;

function TRobotPainter.Project(X, Y: Double): TPointF;
begin
  Result := TPointF.Create((X - Left) * Scale, (Top - Y) * Scale);
end;

function TRobotPainter.Local(const P: TRobotPart; X, Y: Double): TPointF;
begin
  Result := Project(P.X + X * P.W * Cos(P.Angle) - Y * P.H * Sin(P.Angle),
    P.Y + X * P.W * Sin(P.Angle) + Y * P.H * Cos(P.Angle));
end;

procedure TRobotPainter.Quad(const A, B, C, D: TPointF; Color: TColor);
begin
  Surface.FillQuad(A, B, C, D, Color);
end;

procedure TRobotPainter.Bar(X1, Y1, X2, Y2: Double; Color: TColor);
var A, B: TPointF;
begin
  A := Project(X1, Y2);
  B := Project(X2, Y1);
  Surface.FillRect(A.X, A.Y, B.X, B.Y, Color);
end;

procedure TRobotPainter.Line(X1, Y1, X2, Y2, Width: Double; Color: TColor);
var A, B: TPointF;
begin
  A := Project(X1, Y1);
  B := Project(X2, Y2);
  Surface.Line(A.X, A.Y, B.X, B.Y, Color, Max(0.7, Width * Scale));
end;

procedure TRobotPainter.Dot(X, Y, Radius: Double; Color: TColor; Filled: Boolean);
var P: TPointF;
begin
  P := Project(X, Y);
  Surface.Circle(P.X, P.Y, Radius * Scale, Color, Filled, Max(0.8, 0.025 * Scale));
end;

procedure TRobotPainter.Plate(const P: TRobotPart; Color: TColor);
var Points: array[0..7] of TPointF; I: Integer;
begin
  Points[0] := Local(P, -0.32, 0.5);
  Points[1] := Local(P, 0.32, 0.5);
  Points[2] := Local(P, 0.5, 0.30);
  Points[3] := Local(P, 0.5, -0.30);
  Points[4] := Local(P, 0.32, -0.5);
  Points[5] := Local(P, -0.32, -0.5);
  Points[6] := Local(P, -0.5, -0.30);
  Points[7] := Local(P, -0.5, 0.30);
  Quad(Points[0], Points[1], Points[4], Points[5], Color);
  Quad(Points[1], Points[2], Points[3], Points[4], Shade(Color, Ink, 0.31));
  Quad(Points[5], Points[6], Points[7], Points[0], Shade(Color, Silver, 0.20));
  Quad(Points[0], Points[1], Local(P, 0.30, 0.29), Local(P, -0.28, 0.29), Shade(Color, Silver, 0.43));
  Quad(Points[5], Points[4], Local(P, 0.29, -0.26), Local(P, -0.29, -0.26), Shade(Color, Ink, 0.25));
  for I := 0 to 7 do
    Surface.Line(Points[I].X, Points[I].Y, Points[(I + 1) mod 8].X, Points[(I + 1) mod 8].Y,
      Ink, Max(0.8, Scale * 0.025));
end;

procedure TRobotPainter.Detail(const P: TRobotPart; Kind: TRobotPartKind;
  Color, Light: TColor; Facing, Glow: Double);
var A, B, C: TPointF; J: Integer; X, Y, R: Double;
begin
  if Kind in [rpWheelL, rpWheelR] then
  begin
    R := Min(P.W, P.H) * 0.5;
    Dot(P.X, P.Y, R, Ink);
    Dot(P.X, P.Y, R * 0.69, Metal);
    Dot(P.X, P.Y, R * 0.37, Color);
    for J := 0 to 3 do
    begin
      X := Cos(Time * 2 + J * Pi / 2) * R * 0.63;
      Y := Sin(Time * 2 + J * Pi / 2) * R * 0.63;
      Line(P.X, P.Y, P.X + X, P.Y + Y, 0.018, Silver);
    end;
    Exit;
  end;
  if Kind in [rpEngineL, rpEngineR] then
  begin
    Plate(P, Shade(Color, Ink, 0.40));
    for J := -1 to 1 do
    begin
      A := Local(P, -0.25, J * 0.20);
      B := Local(P, 0.25, J * 0.20);
      Surface.Line(A.X, A.Y, B.X, B.Y, Light, Max(0.8, Scale * 0.025));
    end;
    Exit;
  end;
  Plate(P, Color);
  case Kind of
    rpHead:
      begin
        Quad(Local(P, -0.37, 0.16), Local(P, 0.41, 0.10), Local(P, 0.27, -0.19),
          Local(P, -0.29, -0.15), Ink);
        A := Local(P, -0.27, 0.02);
        B := Local(P, 0.32, -0.02);
        Surface.Line(A.X, A.Y, B.X, B.Y, Light, Max(1.0, P.H * Scale * 0.11));
        Quad(Local(P, -0.24, 0.28), Local(P, -0.65 * Facing, 0.97),
          Local(P, -0.10, 0.46), Local(P, -0.10, 0.46), Gold);
        Quad(Local(P, 0.20, 0.31), Local(P, 0.65 * Facing, 0.97),
          Local(P, 0.10, 0.46), Local(P, 0.10, 0.46), Gold);
        Quad(Local(P, 0.04, -0.11), Local(P, 0.19, -0.19), Local(P, 0.10, -0.43),
          Local(P, -0.12, -0.37), Silver);
      end;
    rpChest:
      begin
        Quad(Local(P, -0.42, 0.29), Local(P, 0.05, -0.37), Local(P, 0.42, 0.29),
          Local(P, 0.05, -0.13), Shade(Light, Silver, 0.25));
        A := Local(P, 0.04, -0.10);
        Surface.Circle(A.X, A.Y, P.H * Scale * 0.19, Light, True);
      end;
    rpArmL, rpArmR, rpThighL, rpThighR:
      begin
        A := Local(P, 0, 0.37);
        Surface.Circle(A.X, A.Y, Min(P.W, P.H) * Scale * 0.27, Ink, True);
        Surface.Circle(A.X, A.Y, Min(P.W, P.H) * Scale * 0.13, Metal, True);
      end;
    rpForearmL, rpForearmR, rpShinL, rpShinR:
      begin
        A := Local(P, -0.21, 0.27);
        B := Local(P, -0.21, -0.27);
        C := Local(P, 0.21, -0.20);
        Surface.Line(A.X, A.Y, B.X, B.Y, Shade(Color, Silver, 0.63), Max(0.8, Scale * 0.022));
        Surface.Line(B.X, B.Y, C.X, C.Y, Ink, Max(0.8, Scale * 0.02));
      end;
    rpShoulderL, rpShoulderR:
      begin
        for J := -1 to 1 do
        begin
          A := Local(P, -0.22 + J * 0.16, 0.10);
          B := Local(P, -0.22 + J * 0.16, -0.16);
          Surface.Line(A.X, A.Y, B.X, B.Y, Ink, Max(0.8, Scale * 0.024));
        end;
      end;
    rpWeapon:
      begin
        Quad(Local(P, -0.12, -0.33), Local(P, -0.18, 0.92), Local(P, 0.06, 1.30),
          Local(P, 0.14, -0.30), Shade(Silver, Light, 0.30));
        A := Local(P, 0, -0.37);
        B := Local(P, 0, 0.79);
        Surface.Line(A.X, A.Y, B.X, B.Y, Light, Max(0.9, Scale * 0.025));
      end;
  end;
  if Glow > 0.03 then
  begin
    A := Local(P, -0.29, 0.29);
    B := Local(P, 0.29, 0.29);
    Surface.Line(A.X, A.Y, B.X, B.Y, Shade(Color, Silver, Glow), Max(0.7, Scale * 0.018));
  end;
end;

procedure TRobotPainter.City;
var I, Layer, J, Row: Integer; U, X, Y, W, H, Base, Damage, Fall, Land: Double;
  Wall, Window: TColor;
begin
  for I := 0 to 31 do
  begin
    U := I / 31;
    Surface.FillRect(0, Frame.Height * I / 32, Frame.Width, Frame.Height * (I + 1) / 32 + 1,
      Shade(RGB(28, 48, 78), RGB(239, 157, 115), U));
  end;
  Dot(7.3, 5.25, 0.83, RGB(255, 220, 170));
  Land := Plan.Stages[0].Locks[4];
  for Layer := 0 to 2 do
  begin
    Base := 0.05 + (2 - Layer) * 0.40;
    for I := -14 to 14 do
    begin
      W := 0.62 + (Abs(I * 19 + Layer * 11) mod 7) * 0.14;
      X := I * 1.14 - Layer * 0.35;
      H := 1.1 + (Abs(I * 17 + Layer * 7) mod 11) * 0.28;
      if Layer = 0 then H := H + 1.6;
      Wall := Shade(RGB(77, 100, 128), RGB(27, 43, 62), Layer / 2);
      Window := Shade(RGB(234, 192, 130), Wall, Layer * 0.14);
      Damage := 0;
      if (Layer = 2) and (I in [2, 3, 4, 5]) then
        Damage := RobotRange(Time, Land, Land + 0.9) * (0.45 + (I mod 3) * 0.16);
      if (Layer = 2) and InRange(I, -2, 0) then
        Damage := RobotRange(Time, Plan.Stages[13].Start, Plan.Stages[13].Finish) * 0.48;
      Fall := H * Damage;
      Bar(X, Base, X + W, Base + H - Fall, Wall);
      Bar(X + W * 0.77, Base, X + W, Base + H - Fall, Shade(Wall, Ink, 0.33));
      Bar(X - 0.035, Base + H - Fall, X + W + 0.035, Base + H - Fall + 0.065,
        Shade(Wall, Silver, 0.16));
      if (I mod 4 = 0) and (Damage < 0.1) then
        Line(X + W * 0.5, Base + H, X + W * 0.5, Base + H + 0.40, 0.018, Wall);
      for J := 0 to 2 do
        for Row := 0 to Floor((H - Fall) / 0.30) - 1 do
        begin
          Y := Base + 0.16 + Row * 0.30;
          if (Abs(I + J + Row) mod 5) <> 0 then
            Bar(X + 0.12 + J * W * 0.24, Y, X + 0.19 + J * W * 0.24, Y + 0.10, Window);
        end;
      if Damage > 0 then
      begin
        Line(X + W * 0.2, Base + H - Fall, X + W * 0.53, Base + 0.1, 0.035, Ink);
        for J := 0 to 3 do
        begin
          Y := Base + H - Fall;
          Line(X + J * W / 4, Y, X + J * W / 4 + 0.13, Y + 0.14, 0.06, Wall);
        end;
      end;
    end;
  end;
  Bar(-40, -7, 40, 0.12, RGB(37, 43, 53));
  Bar(-40, 0.03, 40, 0.12, RGB(107, 111, 116));
  for I := -18 to 18 do
  begin
    Line(I * 1.6, 0.04, I * 2.6, -5, 0.012, RGB(63, 68, 77));
    Bar(I * 1.9, -0.58, I * 1.9 + 0.70, -0.53, RGB(176, 154, 106));
  end;
  if Time >= Land then
    for I := 0 to 10 do
    begin
      U := (I - 5) * 0.28;
      Line(3.65, 0.04, 3.65 + U * 1.5, -0.12 - Abs(U) * 0.13, 0.029, Ink);
      Line(3.65 + U * 1.5, -0.12 - Abs(U) * 0.13,
        3.65 + U * 1.75, -0.28 - Abs(U) * 0.13, 0.02, Ink);
    end;
end;

procedure TRobotPainter.Robot(const Body: TRobotBody);
var Kind: TRobotPartKind; Color, Light, Paint: TColor; I: Integer; P: TRobotPart;
begin
  if Body.Team = rtAlly then
  begin
    Color := AllyColors[(Body.Member + Plan.Palette) mod Length(AllyColors)];
    Light := RGB(142, 245, 255);
  end
  else
  begin
    Color := Shade(RGB(55, 57, 72), EnemyAccents[Body.Member], 0.17);
    Light := EnemyAccents[Body.Member];
  end;
  if (Body.Member = 0) or (Body.Member >= Body.Assembly) then
    for I := 0 to 4 do
      Line(Body.RootX - Body.Size * (0.9 - I * 0.12), -0.03 - I * 0.018,
        Body.RootX + Body.Size * (1.0 - I * 0.12), -0.03 - I * 0.018,
        0.05, RGB(23 + I * 2, 28 + I * 2, 37 + I * 2));
  // 組立中も同じパーツを描く。中心の骨格は機構色で、装甲間に可動部を残す。
  for Kind in DrawOrder do
  begin
    P := Body.Parts[Kind];
    if (P.Y < -1.0) or (P.X < Left - 3) or (P.X > Left + View.Width + 3) then Continue;
    Paint := Color;
    if Kind in [rpArmL, rpArmR, rpThighL, rpThighR, rpHandL, rpHandR] then
      Paint := Shade(Color, Ink, 0.28);
    if Kind = rpHip then Paint := Shade(Color, Metal, 0.45);
    if (Body.Team = rtEnemy) and (Kind in [rpChest, rpShoulderL, rpShoulderR, rpWingL, rpWingR]) then
      Paint := Shade(Color, Light, 0.42);
    Paint := Shade(Paint, Silver, Body.Damage * 0.38);
    Detail(P, Kind, Paint, Light, Body.Facing, Body.Glow);
  end;
  if Body.Guard > 0.04 then
    Dot(Body.RootX + Body.Facing * 1.08 * Body.Size, Body.RootY + 2.55 * Body.Size,
      Body.Guard * Body.Size * 0.83, Light, False);
end;

procedure TRobotPainter.Burst(X, Y, Age, Power: Double; Color: TColor);
var I: Integer; A, R, L: Double;
begin
  if (Age < 0) or (Age > 0.7) then Exit;
  R := (0.12 + Age * 3.8) * Power;
  Dot(X, Y, R, Shade(Color, RGB(50, 58, 70), Age / 0.7), False);
  if Age < 0.22 then
  begin
    Dot(X, Y, Power * (0.22 - Age) * 1.4, Color);
    Dot(X, Y, Power * (0.22 - Age) * 0.65, Silver);
  end;
  for I := 0 to 13 do
  begin
    A := I * 2.39996;
    L := Power * (0.14 + (I mod 3) * 0.10) * (1 - Age / 0.7);
    Line(X + Cos(A) * R, Y + Sin(A) * R - Age * Age,
      X + Cos(A) * (R + L), Y + Sin(A) * (R + L) - Age * Age, 0.025, Color);
  end;
end;

procedure TRobotPainter.Smoke(X, Y, Age, Power: Double);
var I: Integer; T, R: Double;
begin
  if (Age < 0) or (Age > 2.6) then Exit;
  T := Age / 2.6;
  for I := 0 to 6 do
  begin
    R := Power * (0.13 + T * 0.38) * (1 - T * T);
    Dot(X + Sin(I * 2.4) * Age * 0.40, Y + Age * 0.6 + (I mod 3) * 0.15,
      R, Shade(RGB(57, 58, 68), RGB(138, 128, 126), T));
  end;
end;

procedure TRobotPainter.BattleEffects;
var I, J, First, Last, Actor, Target: Integer; Cue: TRobotCue; AtHit: TRobotView;
  A, B, P: TRobotPart; X1, Y1, X2, Y2, U, Age, Launch, Power, X, Y: Double; Color: TColor;
begin
  First := Max(0, Plan.CueAt(Time - 1.4));
  Last := Min(High(Plan.Cues), Plan.CueAt(Time + 0.9));
  for I := First to Last do
  begin
    Cue := Plan.Cues[I];
    Age := Time - Cue.Time;
    if (Time < Cue.Time - Cue.Lead) or (Age > 1.25) then Continue;
    AtHit := EvaluateRobotView(Plan, Cue.Time, Frame.Width / Max(1, Frame.Height));
    Actor := -1;
    Target := -1;
    for J := 0 to AtHit.Count - 1 do
    begin
      if (AtHit.Bodies[J].Team = Cue.Team) and (AtHit.Bodies[J].Member = Cue.Member) then Actor := J;
      if (AtHit.Bodies[J].Team <> Cue.Team) and (AtHit.Bodies[J].Member = 0) then Target := J;
    end;
    if (Actor < 0) or (Target < 0) then Continue;
    A := AtHit.Bodies[Actor].Parts[rpWeapon];
    for J := 0 to View.Count - 1 do
      if (View.Bodies[J].Team = Cue.Team) and (View.Bodies[J].Member = Cue.Member) then
        A := View.Bodies[J].Parts[rpWeapon];
    B := AtHit.Bodies[Target].Parts[rpChest];
    X1 := A.X - Sin(A.Angle) * A.H * 1.3;
    Y1 := A.Y + Cos(A.Angle) * A.H * 1.3;
    X2 := B.X;
    Y2 := B.Y;
    if Cue.Reaction = rrGuard then X2 := X2 - AtHit.Bodies[Actor].Facing * 0.75;
    if Cue.Reaction = rrDodge then Y2 := Y2 - 0.7;
    Color := Gold;
    if Cue.Team = rtEnemy then Color := EnemyAccents[0];
    Power := 0.55 + Cue.Power * 0.45;
    if Cue.Attack in [raShot, raMissile, raBeam, raSpecial] then
    begin
      Launch := Cue.Time - Cue.Lead * 0.42;
      U := EnsureRange((Time - Launch) / Max(0.001, Cue.Time - Launch), 0.0, 1.0);
      if (Time >= Launch) and (Age < 0.16) then
      begin
        if Cue.Attack in [raBeam, raSpecial] then
        begin
          Power := Power * (1 - RobotRange(Age, 0, 0.16));
          Line(X1, Y1, X1 + (X2 - X1) * U, Y1 + (Y2 - Y1) * U,
            (0.15 + Ord(Cue.Attack = raSpecial) * 0.35) * Power, Color);
          Line(X1, Y1, X1 + (X2 - X1) * U, Y1 + (Y2 - Y1) * U, 0.055 * Power, Silver);
        end
        else if Age < 0 then
        begin
          for J := 0 to Ord(Cue.Attack = raMissile) * 2 do
          begin
            X := X1 + (X2 - X1) * U;
            Y := Y1 + (Y2 - Y1) * U + Sin(U * Pi) * (J - 1) * 0.65 * Ord(Cue.Attack = raMissile);
            Line(X - AtHit.Bodies[Actor].Facing * 0.52, Y, X, Y, 0.06, Color);
            Dot(X, Y, 0.075, Silver);
          end;
        end;
        Burst(X1, Y1, Time - Launch, 0.25, Color);
      end;
      if (Time < Launch) and (Cue.Attack = raSpecial) then
        Dot(X1, Y1, RobotRange(Time, Cue.Time - Cue.Lead, Launch) * 0.55, Color, False);
    end;
    if (Cue.Attack = raSlash) and (Age < 0.10) then
    begin
      U := RobotRange(Time, Cue.Time - Cue.Lead, Cue.Time);
      for J := 0 to 11 do
      begin
        X := -1.0 + U * 2.5 - J * 0.055;
        P := AtHit.Bodies[Actor].Parts[rpHandR];
        Line(P.X + Cos(X) * 1.05, P.Y + Sin(X) * 1.05,
          P.X + Cos(X + 0.06) * 1.05, P.Y + Sin(X + 0.06) * 1.05,
          0.04 + J * 0.003, Shade(Color, Silver, J / 14));
      end;
    end;
    if Cue.Reaction <> rrDodge then
    begin
      Burst(X2, Y2, Age, 0.6 + Ord(Cue.Attack = raSpecial) * 0.9, Color);
      if Cue.Attack in [raMissile, raSpecial] then Smoke(X2, Y2, Age, 0.65);
    end;
  end;
end;

procedure TRobotPainter.MechanismEffects;
var Stage: TRobotStage; I, J: Integer; X, Age, Land, U: Double; Color: TColor;
begin
  Stage := Plan.Stages[View.StageIndex];
  if Stage.Kind in [rkTransform, rkCombine] then
  begin
    X := -(1 - 2 * Ord(Stage.Team)) * 3.65;
    if Stage.Members(Stage.Team) > Stage.Assembly(Stage.Team) then X := X - (1 - 2 * Ord(Stage.Team)) * 2.7;
    if Stage.Kind = rkCombine then X := -(1 - 2 * Ord(Stage.Team)) * 3.65;
    Color := RGB(130, 235, 255);
    if Stage.Team = rtEnemy then Color := EnemyAccents[0];
    for I := 0 to High(Stage.Locks) do
      if Stage.Synced[I] then
      begin
        Age := Time - Stage.Locks[I];
        Burst(X + (I mod 3 - 1) * 0.40, 1.2 + I * 0.35, Age, 0.30, Color);
        if I = High(Stage.Locks) then Burst(X, 2.3, Age, 1.1, Color);
      end;
  end;
  Land := Plan.Stages[0].Locks[4];
  Burst(3.65, 0.2, Time - Land, 1.55, Gold);
  Smoke(3.65, 0.15, Time - Land, 1.3);
  for J := 0 to 10 do
  begin
    Age := Time - Land;
    if (Age >= 0) and (Age < 1.1) then
    begin
      U := (J - 5) * 0.37;
      Dot(3.65 + U * Age * 2.1, 0.15 + (1.0 + J mod 3 * 0.45) * Age - 2.8 * Sqr(Age),
        0.055 + J mod 3 * 0.018, RGB(106, 104, 108));
    end;
  end;
  if Stage.Kind = rkCollapse then
    for I := 0 to 9 do
    begin
      Age := Time - Stage.Start - (Stage.Finish - Stage.Start) * I / 13;
      X := 3.65 + Sin(I * 2.4) * 1.1;
      Burst(X, 1.0 + (I mod 4) * 0.85, Age, 1.0, Gold);
      Smoke(X, 1.0 + (I mod 4) * 0.85, Age, 1.1);
    end;
end;

procedure TRobotPainter.Paint;
var I: Integer;
begin
  Time := EnsureRange(Frame.Time, 0.0, Plan.Duration);
  View := EvaluateRobotView(Plan, Time, Frame.Width / Max(1, Frame.Height));
  Scale := Frame.Width / View.Width;
  Left := View.CenterX - View.Width * 0.5;
  Top := View.CenterY + View.Height * 0.5;
  City;
  if Frame.BackgroundOnly then Exit;
  for I := View.Count - 1 downto 0 do Robot(View.Bodies[I]);
  BattleEffects;
  MechanismEffects;
end;

procedure DrawRobotWar(Surface: TAnimationRenderSurface; Plan: TRobotPlan; const Frame: TAnimationFrame);
var Painter: TRobotPainter;
begin
  Painter.Surface := Surface;
  Painter.Plan := Plan;
  Painter.Frame := Frame;
  Painter.Paint;
end;

end.
