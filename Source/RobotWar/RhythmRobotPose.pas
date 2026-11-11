unit RhythmRobotPose;
// 独立した25パーツを同じ座標系で変形・合体・関節駆動する。敵味方で計算を共有する。
interface

uses RhythmRobotPlan;

type
  TRobotPartKind = (rpHead, rpTorso, rpChest, rpHip,
    rpShoulderL, rpArmL, rpForearmL, rpHandL, rpShoulderR, rpArmR, rpForearmR, rpHandR,
    rpThighL, rpShinL, rpFootL, rpThighR, rpShinR, rpFootR,
    rpWingL, rpWingR, rpWheelL, rpWheelR, rpWeapon, rpEngineL, rpEngineR);
  TRobotPart = record
    X, Y, W, H, Angle: Double; // 床Y=0、上向き正、角度はrad。中心位置と全幅・全高。
  end;
  TRobotParts = array[TRobotPartKind] of TRobotPart;
  TRobotMotion = record
    Punch, Kick, Slash, Shot, Missile, Beam, Guard, Dodge, Damage, Down, Special, Victory: Double;
    Advance: Double;
  end;
  TRobotBody = record
    Team: TRobotTeam;
    Member, Assembly: Integer;
    Form: TRobotForm;
    Facing, RootX, RootY, Size, Transform, Glow, Damage, Guard: Double;
    Parts: TRobotParts;
  end;
  TRobotView = record
    Bodies: array[0..5] of TRobotBody;
    Count, StageIndex: Integer;
    CenterX, CenterY, Width, Height, Shake: Double;
  end;

function RobotNeutralPart(Kind: TRobotPartKind): TRobotPart;
function RobotVehiclePart(Form: TRobotForm; Kind: TRobotPartKind): TRobotPart;
function RobotAssemblyPart(Member, Count: Integer; Kind: TRobotPartKind;
  const Motion: TRobotMotion): TRobotPart;
function RobotCueWeight(const Cue: TRobotCue; Time: Double): Double;
function EvaluateRobotView(Plan: TRobotPlan; Time, Aspect: Double): TRobotView;

implementation

uses System.Math;

function Part(X, Y, W, H: Double; Angle: Double = 0): TRobotPart;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
  Result.Angle := Angle;
end;

function MixPart(const A, B: TRobotPart; Weight: Double): TRobotPart;
begin
  Result.X := A.X + (B.X - A.X) * Weight;
  Result.Y := A.Y + (B.Y - A.Y) * Weight;
  Result.W := A.W + (B.W - A.W) * Weight;
  Result.H := A.H + (B.H - A.H) * Weight;
  Result.Angle := A.Angle + (B.Angle - A.Angle) * Weight;
end;

function RobotNeutralPart(Kind: TRobotPartKind): TRobotPart;
begin
  Result := Default(TRobotPart);
  case Kind of
    rpHead: Result := Part(0.03, 3.18, 0.46, 0.45);
    rpTorso: Result := Part(0, 2.55, 0.96, 0.80);
    rpChest: Result := Part(0.05, 2.70, 1.03, 0.36);
    rpHip: Result := Part(0, 1.95, 0.67, 0.32);
    rpShoulderL: Result := Part(-0.67, 2.79, 0.56, 0.48, 0.12);
    rpArmL: Result := Part(-0.72, 2.40, 0.31, 0.57, -0.12);
    rpForearmL: Result := Part(-0.78, 1.98, 0.43, 0.55, -0.09);
    rpHandL: Result := Part(-0.72, 1.65, 0.29, 0.26);
    rpShoulderR: Result := Part(0.65, 2.78, 0.59, 0.46, -0.12);
    rpArmR: Result := Part(0.70, 2.40, 0.31, 0.57, 0.14);
    rpForearmR: Result := Part(0.83, 2.02, 0.44, 0.57, -0.20);
    rpHandR: Result := Part(0.92, 1.70, 0.30, 0.25);
    rpThighL: Result := Part(-0.28, 1.48, 0.37, 0.65, -0.06);
    rpShinL: Result := Part(-0.32, 0.82, 0.45, 0.72, -0.04);
    rpFootL: Result := Part(-0.25, 0.30, 0.61, 0.29);
    rpThighR: Result := Part(0.30, 1.48, 0.38, 0.65, 0.10);
    rpShinR: Result := Part(0.40, 0.82, 0.45, 0.72, 0.06);
    rpFootR: Result := Part(0.49, 0.30, 0.65, 0.29);
    rpWingL: Result := Part(-0.53, 2.78, 0.34, 1.12, -0.48);
    rpWingR: Result := Part(0.49, 2.78, 0.34, 1.12, 0.48);
    rpWheelL: Result := Part(-0.57, 0.88, 0.22, 0.32);
    rpWheelR: Result := Part(0.64, 0.88, 0.22, 0.32);
    rpWeapon: Result := Part(1.08, 1.75, 0.26, 1.03, -0.14);
    rpEngineL: Result := Part(-0.30, 2.44, 0.26, 0.65);
    rpEngineR: Result := Part(0.30, 2.44, 0.26, 0.65);
  end;
end;

function RobotVehiclePart(Form: TRobotForm; Kind: TRobotPartKind): TRobotPart;
var Side: Double;
begin
  Result := RobotNeutralPart(Kind);
  Side := 1;
  if Kind in [rpShoulderL, rpArmL, rpForearmL, rpHandL, rpThighL, rpShinL,
    rpFootL, rpWingL, rpWheelL, rpEngineL] then Side := -1;
  case Kind of
    rpHead: Result := Part(0.64, 0.84, 0.46, 0.27, -0.14);
    rpTorso: Result := Part(0, 0.65, 1.55, 0.57);
    rpChest: Result := Part(0.26, 1.03, 0.89, 0.34, -0.10);
    rpHip: Result := Part(-0.80, 0.65, 0.50, 0.49);
    rpShoulderL, rpShoulderR: Result := Part(Side * 0.81, 0.62, 0.67, 0.43);
    rpArmL, rpArmR: Result := Part(Side * 0.42, 0.40, 0.72, 0.20);
    rpForearmL, rpForearmR: Result := Part(Side * 1.02, 0.46, 0.66, 0.29);
    rpHandL, rpHandR: Result := Part(Side * 1.30, 0.47, 0.22, 0.22);
    rpThighL, rpThighR: Result := Part(-0.51 + Side * 0.12, 0.75, 0.56, 0.26);
    rpShinL, rpShinR: Result := Part(-0.91 + Side * 0.12, 0.73, 0.58, 0.34);
    rpFootL, rpFootR: Result := Part(-1.25 + Side * 0.10, 0.67, 0.24, 0.38);
    rpWingL, rpWingR: Result := Part(Side * 0.61, 0.99, 0.36, 0.25);
    rpWheelL, rpWheelR: Result := Part(Side * 0.86, 0.31, 0.48, 0.48);
    rpWeapon: Result := Part(1.00, 0.76, 0.65, 0.22);
    rpEngineL, rpEngineR: Result := Part(-1.08, 0.62 + Side * 0.17, 0.30, 0.23);
  end;
  case Form of
    rfJet:
      case Kind of
        rpTorso: Result := Part(0.14, 0.86, 2.38, 0.44);
        rpHead: Result := Part(1.32, 0.87, 0.76, 0.25);
        rpChest: Result := Part(0.52, 1.08, 0.67, 0.27);
        rpWingL: Result := Part(-0.13, 1.18, 1.80, 0.40, -0.65);
        rpWingR: Result := Part(-0.23, 0.60, 1.95, 0.40, 0.63);
        rpShinL, rpShinR: Result := Part(-0.85, 0.82 + Side * 0.20, 0.95, 0.29);
        rpFootL, rpFootR: Result := Part(-1.36, 1.05 + Side * 0.15, 0.62, 0.24, -0.58 * Side);
        rpWheelL, rpWheelR: Result := Part(0.3 + Side * 0.45, 0.68, 0.17, 0.17);
      end;
    rfTrain:
      begin
        Result.X := Result.X * 1.34;
        if Kind = rpChest then Result := Part(0.15, 1.05, 1.52, 0.50);
        if Kind = rpHead then Result := Part(1.27, 0.90, 0.36, 0.57);
        if Kind in [rpWingL, rpWingR] then Result := Part(Side * 1.10, 1.25, 0.65, 0.12);
      end;
    rfBeast:
      case Kind of
        rpHead: Result := Part(1.16, 1.20, 0.74, 0.52, -0.12);
        rpTorso: Result := Part(-0.02, 1.19, 1.53, 0.63);
        rpChest: Result := Part(0.58, 1.28, 0.62, 0.73, -0.08);
        rpShoulderL, rpShoulderR: Result := Part(0.64 + Side * 0.13, 0.95, 0.46, 0.46);
        rpArmL, rpArmR: Result := Part(0.79 + Side * 0.15, 0.65, 0.26, 0.56, -0.15 * Side);
        rpForearmL, rpForearmR: Result := Part(0.90 + Side * 0.15, 0.31, 0.27, 0.37);
        rpHandL, rpHandR: Result := Part(1.04 + Side * 0.15, 0.14, 0.38, 0.18);
        rpHip: Result := Part(-0.82, 1.06, 0.52, 0.49);
        rpThighL, rpThighR: Result := Part(-0.83 + Side * 0.14, 0.77, 0.36, 0.55, 0.36);
        rpShinL, rpShinR: Result := Part(-0.97 + Side * 0.14, 0.37, 0.24, 0.42, -0.24);
        rpFootL, rpFootR: Result := Part(-0.76 + Side * 0.14, 0.14, 0.43, 0.18);
        rpWingL, rpWingR: Result := Part(-0.24 + Side * 0.32, 1.60, 0.65, 0.22, -0.2 * Side);
        rpWeapon: Result := Part(-1.25, 1.29, 0.89, 0.19, -0.30);
        rpWheelL, rpWheelR: Result := Part(-0.52 + Side * 0.16, 0.90, 0.24, 0.24);
      end;
  end;
end;

function AnimatedPart(Kind: TRobotPartKind; const Motion: TRobotMotion): TRobotPart;
var Aim, Melee: Double;
begin
  Result := RobotNeutralPart(Kind);
  Aim := Max(Max(Motion.Shot, Motion.Missile), Max(Motion.Beam, Motion.Special));
  Melee := Motion.Punch;
  case Kind of
    rpHead: Result.Angle := 0.12 * Motion.Damage - 0.08 * Aim;
    rpTorso, rpChest, rpHip:
      begin
        Result.X := Result.X + 0.18 * Melee - 0.20 * Motion.Damage;
        Result.Angle := -0.10 * Melee + 0.18 * Motion.Damage;
      end;
    rpShoulderR: Result.X := Result.X + 0.12 * Melee;
    rpArmR:
      Result := MixPart(Result, Part(0.98, 2.65, 0.31, 0.64, -1.2), Max(Aim, Melee));
    rpForearmR:
      Result := MixPart(Result, Part(1.46, 2.60, 0.45, 0.68, -1.48), Max(Aim, Melee));
    rpHandR:
      Result := MixPart(Result, Part(1.86, 2.57, 0.35, 0.29), Max(Aim, Melee));
    rpArmL: Result.Angle := Result.Angle - 0.9 * Motion.Guard + 0.4 * Motion.Slash;
    rpForearmL:
      begin
        Result.X := Result.X + 0.95 * Motion.Guard;
        Result.Y := Result.Y + 0.6 * Motion.Guard;
        Result.Angle := Result.Angle - 1.2 * Motion.Guard;
      end;
    rpHandL:
      begin
        Result.X := Result.X + 1.2 * Motion.Guard;
        Result.Y := Result.Y + 0.8 * Motion.Guard;
      end;
    rpThighR: Result := MixPart(Result, Part(0.77, 1.67, 0.38, 0.66, -1.0), Motion.Kick);
    rpShinR: Result := MixPart(Result, Part(1.32, 1.78, 0.45, 0.73, -1.7), Motion.Kick);
    rpFootR: Result := MixPart(Result, Part(1.85, 1.90, 0.62, 0.30, 0.15), Motion.Kick);
    rpWeapon:
      begin
        Result := MixPart(Result, Part(1.73, 2.54, 0.28, 1.48, -Pi / 2), Aim);
        Result.X := Result.X + 0.48 * Motion.Slash;
        Result.Y := Result.Y + 1.18 * Motion.Slash;
        Result.Angle := Result.Angle - 2.4 * Motion.Slash;
      end;
  end;
  if Motion.Slash > 0 then
    if Kind in [rpArmR, rpForearmR, rpHandR] then
    begin
      Result.Y := Result.Y + Motion.Slash * 0.85;
      Result.X := Result.X + Motion.Slash * 0.55;
      Result.Angle := Result.Angle - Motion.Slash * 0.85;
    end;
  if Motion.Victory > 0 then
    case Kind of
      rpArmR, rpForearmR, rpHandR, rpWeapon:
        begin
          Result.X := Result.X + (0.75 - Result.X) * Motion.Victory;
          Result.Y := Result.Y + (5.0 - Result.Y) * Motion.Victory * 0.52;
          Result.Angle := Result.Angle - Motion.Victory * 0.25;
        end;
    end;
end;

function RobotAssemblyPart(Member, Count: Integer; Kind: TRobotPartKind;
  const Motion: TRobotMotion): TRobotPart;
var Side: Double;
begin
  Result := AnimatedPart(Kind, Motion);
  if Count = 1 then Exit;
  Side := 1;
  if Kind in [rpShoulderL, rpArmL, rpForearmL, rpHandL, rpThighL, rpShinL,
    rpFootL, rpWingL, rpWheelL, rpEngineL] then Side := -1;
  if Member = 0 then
  begin
    Result.Y := Result.Y + 0.58;
    if Kind in [rpThighL, rpThighR, rpShinL, rpShinR, rpFootL, rpFootR,
      rpWheelL, rpWheelR] then
    begin
      // 主機の下半身は背面フィン・推進器へ折り畳む。脚は第二機の脚へ役割を渡す。
      Result := Part(Side * (0.67 + (Ord(Kind) mod 3) * 0.18),
        2.70 + (Ord(Kind) mod 3) * 0.32, 0.24, 0.55, Side * 0.65);
    end;
    Exit;
  end;
  if Member = 1 then
  begin
    if Kind in [rpThighL, rpThighR, rpShinL, rpShinR, rpFootL, rpFootR,
      rpWheelL, rpWheelR] then
    begin
      Result.X := Result.X * 1.28;
      Result.Y := Result.Y * 1.26;
      Result.W := Result.W * 1.25;
      Result.H := Result.H * 1.26;
      Exit;
    end;
    case Kind of
      rpHead: Result := Part(0, 2.40, 0.28, 0.24);
      rpTorso: Result := Part(0, 2.18, 0.85, 0.43);
      rpChest: Result := Part(0, 2.36, 1.06, 0.23);
      rpHip: Result := Part(0, 1.97, 0.72, 0.20);
      rpShoulderL, rpShoulderR: Result := Part(Side * 0.55, 2.14, 0.45, 0.45, Side * 0.28);
      rpArmL, rpArmR: Result := Part(Side * 0.52, 2.63, 0.19, 0.55, Side * 0.3);
      rpForearmL, rpForearmR: Result := Part(Side * 0.61, 2.92, 0.29, 0.39);
      rpHandL, rpHandR: Result := Part(Side * 0.62, 3.16, 0.21, 0.18);
      rpWingL, rpWingR: Result := Part(Side * 0.68, 2.16, 0.30, 0.60, Side * 0.3);
      rpWeapon: Result := Part(-0.90, 2.82, 0.20, 1.30, -0.32);
      rpEngineL, rpEngineR: Result := Part(Side * 0.40, 1.30, 0.22, 0.53);
    end;
    Exit;
  end;
  // 第三機は両肩・胸の外装と背部武装へ再構成。パーツを隠さず同じIDを運ぶ。
  case Kind of
    rpHead: Result := Part(0.08, 3.18, 0.34, 0.25);
    rpTorso: Result := Part(0, 3.10, 1.18, 0.36);
    rpChest: Result := Part(0, 3.20, 0.74, 0.31);
    rpHip: Result := Part(0, 2.84, 0.48, 0.21);
    rpShoulderL, rpShoulderR: Result := Part(Side * 0.93, 3.39, 0.70, 0.45, -Side * 0.18);
    rpArmL, rpArmR: Result := Part(Side * 1.06, 3.10, 0.26, 0.45, -Side * 0.16);
    rpForearmL, rpForearmR: Result := Part(Side * 1.13, 2.83, 0.36, 0.44, -Side * 0.12);
    rpHandL, rpHandR: Result := Part(Side * 1.17, 2.57, 0.25, 0.17);
    rpThighL, rpThighR: Result := Part(Side * 0.70, 3.74, 0.26, 0.56, Side * 0.45);
    rpShinL, rpShinR: Result := Part(Side * 1.01, 3.91, 0.30, 0.70, Side * 0.78);
    rpFootL, rpFootR: Result := Part(Side * 1.40, 4.12, 0.65, 0.24, -Side * 0.27);
    rpWingL, rpWingR: Result := Part(Side * 1.39, 3.59, 0.44, 1.55, -Side * 0.85);
    rpWheelL, rpWheelR: Result := Part(Side * 0.80, 3.58, 0.30, 0.30);
    rpWeapon:
      begin
        Result := Part(1.38, 3.05, 0.40, 1.65, -0.35);
        Result := MixPart(Result, Part(2.02, 3.13, 0.42, 2.1, -Pi / 2),
          Max(Motion.Beam, Motion.Special));
        Result.Y := Result.Y + Motion.Victory * 0.70;
      end;
    rpEngineL, rpEngineR: Result := Part(Side * 0.51, 3.57, 0.33, 0.74);
  end;
end;

function RobotCueWeight(const Cue: TRobotCue; Time: Double): Double;
begin
  if Time <= Cue.Time then Result := RobotRange(Time, Cue.Time - Cue.Lead, Cue.Time)
  else Result := 1 - RobotRange(Time, Cue.Time, Cue.Time + Cue.Recover);
end;

function MotionAt(Plan: TRobotPlan; StageIndex: Integer; Time: Double;
  Team: TRobotTeam; Member: Integer): TRobotMotion;
var I, First, Last: Integer; Cue: TRobotCue; Weight: Double;
begin
  Result := Default(TRobotMotion);
  First := Max(0, Plan.CueAt(Time - 0.9));
  Last := Min(High(Plan.Cues), Plan.CueAt(Time + 0.9));
  for I := First to Last do
  begin
    Cue := Plan.Cues[I];
    if Cue.Stage <> StageIndex then Continue;
    Weight := RobotCueWeight(Cue, Time);
    if (Cue.Team = Team) and (Cue.Member = Member) then
    begin
      case Cue.Attack of
        raPunch: Result.Punch := Max(Result.Punch, Weight);
        raKick: Result.Kick := Max(Result.Kick, Weight);
        raSlash: Result.Slash := Max(Result.Slash, Weight);
        raShot: Result.Shot := Max(Result.Shot, Weight);
        raMissile: Result.Missile := Max(Result.Missile, Weight);
        raBeam: Result.Beam := Max(Result.Beam, Weight);
        raSpecial: Result.Special := Max(Result.Special, Weight);
      end;
      if Cue.Attack in [raPunch, raKick, raSlash] then Result.Advance := Max(Result.Advance, Weight);
    end;
    if (Cue.Team <> Team) and (Member = 0) then
    begin
      case Cue.Reaction of
        rrGuard: Result.Guard := Max(Result.Guard, Weight);
        rrDodge: Result.Dodge := Max(Result.Dodge, Weight);
        rrDown: Result.Down := Max(Result.Down, Weight * RobotRange(Time, Cue.Time, Cue.Time + Cue.Recover * 0.28));
        rrHit: Result.Damage := Max(Result.Damage, Weight * RobotRange(Time, Cue.Time, Cue.Time + Cue.Recover * 0.15));
      end;
    end;
  end;
end;

procedure RootFor(Team: TRobotTeam; Member, Assembly: Integer; out X, Y, Size: Double);
var Facing: Double;
begin
  Facing := 1 - 2 * Ord(Team);
  X := -Facing * 3.65;
  Y := 0;
  Size := 1 + (Assembly - 1) * 0.09;
  if Member >= Assembly then
  begin
    X := X - Facing * 2.7;
    Size := 0.86;
    Y := 0.08;
  end;
end;

function BodyAt(Plan: TRobotPlan; StageIndex: Integer; Time: Double;
  Team: TRobotTeam; Member: Integer): TRobotBody;
var
  Stage: TRobotStage; Kind: TRobotPartKind; A, B: TRobotPart;
  Motion: TRobotMotion; Count, Assembly, I: Integer;
  P, U, Weight, Travel, Angle, X, Y, Size, FinalX, FinalY, FinalSize, Delay: Double;
begin
  Stage := Plan.Stages[StageIndex];
  Count := Stage.Members(Team);
  Assembly := Stage.Assembly(Team);
  Result := Default(TRobotBody);
  Result.Team := Team;
  Result.Member := Member;
  Result.Assembly := Assembly;
  Result.Facing := 1 - 2 * Ord(Team);
  Result.Form := RobotForm(Team, Member);
  Result.Transform := 1;
  RootFor(Team, Member, Assembly, X, Y, Size);
  Motion := MotionAt(Plan, StageIndex, Time, Team, 0);
  if Member >= Assembly then Motion := MotionAt(Plan, StageIndex, Time, Team, Member);
  P := Stage.Progress(Time);
  U := Stage.Mechanism(Time);
  if (Stage.Kind = rkVictory) and (Team = rtAlly) then Motion.Victory := RobotRange(P, 0, 0.58);
  X := X + Result.Facing * ((3.65 - Result.Facing * X - 1.86 * Size) * Motion.Advance -
    0.8 * Motion.Damage - 1.0 * Motion.Dodge);
  Y := Y + 0.40 * Sin(Pi * Motion.Advance) + 0.75 * Motion.Dodge;
  Angle := Motion.Damage * 0.13 - Motion.Down * 1.32;
  Y := Y - Motion.Down * 0.45;
  Result.Guard := Motion.Guard;
  Result.Damage := Motion.Damage;
  if (Stage.Kind = rkLanding) and (Team = rtEnemy) then
    Y := Y + 9 * Sqr(1 - RobotRange(Time, Stage.Start, Stage.Locks[4]));
  if (Stage.Kind in [rkArrival, rkTransform]) and (Stage.Team = Team) and (Member = Count - 1) then
  begin
    if Stage.Kind = rkArrival then
    begin
      Travel := 1 - RobotRange(P, 0.02, 0.96);
      X := X - Result.Facing * 14 * Travel;
      if Result.Form = rfJet then Y := Y + 5 * Travel;
      if Result.Form = rfBeast then Y := Y + Abs(Sin(P * Pi * 4)) * Travel * 0.6;
      Result.Transform := 0;
    end
    else Result.Transform := U;
  end;
  if (Stage.Kind = rkCollapse) and (Team = rtEnemy) then
  begin
    Y := Y - RobotRange(P, 0.2, 1) * 7;
    Angle := -RobotRange(P, 0, 1) * 1.1;
  end;
  Result.RootX := X;
  Result.RootY := Y;
  Result.Size := Size;
  Result.Glow := Max(Motion.Beam, Motion.Special);
  for I := 0 to High(Stage.Locks) do
    if (Stage.Kind in [rkTransform, rkCombine]) and (Team = Stage.Team) and Stage.Synced[I] and
      (Time >= Stage.Locks[I]) then
      Result.Glow := Max(Result.Glow, Exp(-(Time - Stage.Locks[I]) * 18) * 0.65);
  for Kind := Low(TRobotPartKind) to High(TRobotPartKind) do
  begin
    if Member < Assembly then A := RobotAssemblyPart(Member, Assembly, Kind, Motion)
    else A := AnimatedPart(Kind, Motion);
    if Result.Transform < 1 then
    begin
      B := RobotVehiclePart(Result.Form, Kind);
      // 胴体→脚→腕→頭→固定の順を保ち、同じ部品の位置・角度・寸法を補間する。
      Delay := 0;
      case Kind of
        rpHead: Delay := 0.47;
        rpArmL, rpArmR, rpForearmL, rpForearmR, rpHandL, rpHandR: Delay := 0.22;
        rpThighL, rpThighR, rpShinL, rpShinR, rpFootL, rpFootR: Delay := 0.11;
        rpWingL, rpWingR, rpWheelL, rpWheelR: Delay := 0.05;
      end;
      Weight := RobotRange(Result.Transform, Delay, Min(1.0, Delay + 0.52));
      A := MixPart(B, A, Weight);
      A.Y := A.Y + Sin(Pi * Weight) * (0.18 + Ord(Kind) mod 3 * 0.08);
    end;
    A.X := X + A.X * Size * Result.Facing;
    A.Y := Y + A.Y * Size;
    A.Angle := A.Angle * Result.Facing;
    A.W := A.W * Size;
    A.H := A.H * Size;
    if (Stage.Kind = rkCombine) and (Stage.Team = Team) then
    begin
      RootFor(Team, 0, Count, FinalX, FinalY, FinalSize);
      B := RobotAssemblyPart(Member, Count, Kind, Default(TRobotMotion));
      B.X := FinalX + B.X * FinalSize * Result.Facing;
      B.Y := FinalY + B.Y * FinalSize;
      B.W := B.W * FinalSize;
      B.H := B.H * FinalSize;
      B.Angle := B.Angle * Result.Facing;
      Delay := 0.14 + (Ord(Kind) mod 5) * 0.025;
      if Member < Assembly then Delay := 0.24 + (Ord(Kind) mod 4) * 0.025;
      Weight := RobotRange(U, Delay, Min(0.91, Delay + 0.46));
      A := MixPart(A, B, Weight);
      A.Y := A.Y + Sin(Pi * Weight) * (0.75 + Member * 0.35);
      A.X := A.X + Result.Facing * Sin(Pi * Weight) * (Member - 0.6) * 0.65;
      A.Angle := A.Angle + Sin(Pi * Weight) * (Ord(Kind) mod 3 - 1) * 0.65;
    end;
    Travel := A.X - X;
    A.X := X + Travel * Cos(Angle) - (A.Y - Y - 0.25) * Sin(Angle);
    A.Y := Y + 0.25 + Travel * Sin(Angle) + (A.Y - Y - 0.25) * Cos(Angle);
    A.Angle := A.Angle + Angle;
    if (Stage.Kind = rkCollapse) and (Team = rtEnemy) then
    begin
      Weight := RobotRange(P, 0.05, 0.95);
      A.X := A.X + Sin(Ord(Kind) * 2.4 + Member) * Weight * 1.7;
      A.Y := A.Y + Sin(Pi * Weight) * (Ord(Kind) mod 4) * 0.25;
      A.Angle := A.Angle + Weight * (Ord(Kind) mod 3 - 1) * 1.8;
    end;
    Result.Parts[Kind] := A;
  end;
  if (Stage.Kind = rkCombine) and (Stage.Team = Team) then
  begin
    RootFor(Team, 0, Count, FinalX, FinalY, FinalSize);
    Weight := RobotRange(U, 0.16, 0.90);
    Result.RootX := X + (FinalX - X) * Weight;
    Result.RootY := Y + (FinalY - Y) * Weight;
    Result.Size := Size + (FinalSize - Size) * Weight;
  end;
end;

procedure CameraTarget(const Stage: TRobotStage; out X, Width: Double);
begin
  X := 0;
  Width := 17.6;
  case Stage.Kind of
    rkTransform: begin X := (1 - 2 * Ord(Stage.Team)) * -0.7; Width := 15.4; end;
    rkCombine: Width := 17.0;
    rkBattle, rkFinisher: Width := 15.0;
    rkCollapse: begin X := -1.8; Width := 14; end;
    rkVictory: begin X := -3.65; Width := 9.8; end;
  end;
end;

function EvaluateRobotView(Plan: TRobotPlan; Time, Aspect: Double): TRobotView;
var Stage: TRobotStage; Team: TRobotTeam; Member, I: Integer; PreviousX, PreviousWidth, Weight: Double;
begin
  Result := Default(TRobotView);
  if (Plan = nil) or (Length(Plan.Stages) = 0) then Exit;
  Result.StageIndex := Plan.StageAt(Time);
  Stage := Plan.Stages[Result.StageIndex];
  for Team := Low(TRobotTeam) to High(TRobotTeam) do
    for Member := 0 to Stage.Members(Team) - 1 do
    begin
      if (Team = rtEnemy) and (Stage.Kind = rkVictory) then Continue;
      Result.Bodies[Result.Count] := BodyAt(Plan, Result.StageIndex, Time, Team, Member);
      Inc(Result.Count);
    end;
  CameraTarget(Stage, Result.CenterX, Result.Width);
  PreviousX := Result.CenterX;
  PreviousWidth := Result.Width;
  if Result.StageIndex > 0 then CameraTarget(Plan.Stages[Result.StageIndex - 1], PreviousX, PreviousWidth);
  Weight := RobotRange(Stage.Progress(Time), 0, 0.45);
  Result.CenterX := PreviousX + (Result.CenterX - PreviousX) * Weight;
  Result.Width := PreviousWidth + (Result.Width - PreviousWidth) * Weight;
  Result.Height := Max(7.1, Result.Width / Max(0.1, Aspect));
  Result.Width := Result.Height * Max(0.1, Aspect);
  Result.CenterY := 2.55;
  I := Plan.CueAt(Time);
  if (I >= 0) and (Time - Plan.Cues[I].Time < 0.32) and
    (Plan.Cues[I].Reaction <> rrDodge) then
    Result.Shake := 0.06 * Plan.Cues[I].Power * RobotRange(Time - Plan.Cues[I].Time, 0, 0.028) *
      Exp(-(Time - Plan.Cues[I].Time) * 13);
  if (Stage.Kind = rkLanding) and (Time >= Stage.Locks[4]) then
    Result.Shake := Result.Shake + 0.12 * RobotRange(Time - Stage.Locks[4], 0, 0.03) *
      Exp(-(Time - Stage.Locks[4]) * 10);
  Result.CenterX := Result.CenterX + Result.Shake * Sin(Time * 93);
  Result.CenterY := Result.CenterY + Result.Shake * Sin(Time * 127);
end;

end.
