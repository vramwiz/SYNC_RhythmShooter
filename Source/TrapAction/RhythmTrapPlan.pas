unit RhythmTrapPlan;
// 初見殺しアクションの保存契約と絶対時刻の幾何。足元を基準に軌道・当たり判定を共有する。
interface

uses System.SysUtils, RhythmStyles;

type
  TTrapPoint = record
    X, Y: Double;
  end;
  TTrapBox = record
    Left, Bottom, Right, Top: Double;
  end;
  TTrapMotion = (tmRun, tmJump, tmDoubleJump, tmSlide, tmStop, tmFall,
    tmWallKick, tmHang, tmClimb, tmRide, tmSkate, tmLaunch);
  TTrapKind = (tkSpikes, tkHiddenSpikes, tkCrumble, tkVanish, tkSink, tkMoving,
    tkFlip, tkFalseFloor, tkPit, tkCeiling, tkWall, tkBlade, tkDoor, tkWallBlock,
    tkTunnelCollapse, tkBoulder, tkRock, tkFlyingBlade, tkArrow, tkHunter,
    tkRain, tkFlame, tkLaser, tkLava, tkIce, tkTilt, tkBridge, tkCollapse, tkBackground);
  TTrapMove = record
    Start, Cue, Finish: Double; // CueとFinishは採用した元の音時刻。
    Origin, Target: TTrapPoint;
    Arc: Double;
    Kind: TTrapMotion;
    Section, Pattern: Integer;
    Landing, CueSynced, LandSynced: Boolean;
    function Position(Time: Double): TTrapPoint;
    function HeightAt(Time: Double): Double;
    function Progress(Time: Double): Double;
  end;
  TTrapObstacle = record
    Kind: TTrapKind;
    Reveal, Fire, Cue, Finish: Double;
    X, Y, W, H, Travel, Power: Double;
    Move: Integer;
    Synced: Boolean;
    function BoundsAt(Time: Double): TTrapBox;
    function Dangerous(Time: Double): Boolean;
  end;
  TTrapPlatform = record
    Left, Right, Y, EndY: Double;
    Start, Finish: Double; // 固定床はFinishの音時刻から崩壊。移動床はMoveの軌道に従う。
    Move: Integer; // -1は固定、0以上は乗っている台を同じ軌道で動かす。
    Kind: TTrapKind;
    function TopAt(X: Double): Double;
  end;
  TTrapPlan = class
  public
    Duration, GoalTime, GoalX: Double;
    Theme: TTrapStage;
    Moves: TArray<TTrapMove>;
    Obstacles: TArray<TTrapObstacle>;
    Platforms: TArray<TTrapPlatform>;
    function MoveAt(Time: Double): Integer;
    function Position(Time: Double): TTrapPoint;
    function PlayerBounds(Time: Double): TTrapBox;
    function ObstacleAt(Time: Double): Integer;
    function Clearance(const Trap: TTrapObstacle; Time: Double): Double;
  end;

function TrapPoint(X, Y: Double): TTrapPoint;
function TrapEase(Value: Double): Double;
function TrapRange(Time, First, Last: Double): Double;
function TrapOverlap(const A, B: TTrapBox): Boolean;
function TrapHarmless(Kind: TTrapKind): Boolean;

const TrapHalfWidth = 0.32;
      TrapStandingHeight = 1.12;

implementation

uses System.Math;

function TrapPoint(X, Y: Double): TTrapPoint;
begin
  Result.X := X; Result.Y := Y;
end;

function TrapEase(Value: Double): Double;
begin
  Value := EnsureRange(Value, 0.0, 1.0);
  Result := Sqr(Value) * (3 - 2 * Value);
end;

function TrapRange(Time, First, Last: Double): Double;
begin
  if Last <= First then Exit(Ord(Time >= Last));
  Result := TrapEase((Time - First) / (Last - First));
end;

function TrapOverlap(const A, B: TTrapBox): Boolean;
begin
  Result := (A.Left < B.Right) and (A.Right > B.Left) and
    (A.Bottom < B.Top) and (A.Top > B.Bottom);
end;

function TrapHarmless(Kind: TTrapKind): Boolean;
begin
  Result := Kind in [tkCrumble, tkVanish, tkSink, tkMoving, tkFlip, tkPit,
    tkTunnelCollapse, tkIce, tkTilt, tkBridge, tkCollapse];
end;

function TTrapMove.Progress(Time: Double): Double;
begin
  Result := EnsureRange((Time - Start) / (Finish - Start), 0.0, 1.0);
end;

function TTrapMove.Position(Time: Double): TTrapPoint;
var U, Travel: Double;
begin
  U := Progress(Time);
  Travel := TrapEase(U);
  Result := TrapPoint(Origin.X + (Target.X - Origin.X) * Travel,
    Origin.Y + (Target.Y - Origin.Y) * Travel + Arc * 4 * U * (1 - U));
end;

function TTrapMove.HeightAt(Time: Double): Double;
var Weight: Double;
begin
  Weight := 0;
  if Kind = tmSlide then
    Weight := TrapRange(Time, Start, Cue) * (1 - TrapRange(Time, Cue, Finish));
  Result := TrapStandingHeight - Weight * 0.73;
end;

function TTrapObstacle.Dangerous(Time: Double): Boolean;
begin
  Result := not TrapHarmless(Kind) and (Time >= Fire) and (Time <= Finish);
end;

function TTrapObstacle.BoundsAt(Time: Double): TTrapBox;
var U, After, CX, CY, Width, Height: Double;
begin
  U := TrapRange(Time, Fire, Cue);
  After := TrapRange(Time, Cue, Finish);
  CX := X; CY := Y; Width := W; Height := H;
  case Kind of
    tkSpikes, tkHiddenSpikes, tkFalseFloor, tkFlame:
      Height := H * U * (1 - After);
    tkCeiling, tkRock, tkRain, tkBackground:
      CY := Y + Travel * (1 - U) - Travel * After;
    tkWall, tkWallBlock:
      CX := X - Travel * (1 - U) - Travel * After;
    tkBlade: CY := Y + Sin((Time - Cue) * 4) * Travel;
    tkBoulder:
      begin CX := X - Travel * (1 - U); CY := Y - 5 * After; end;
    tkFlyingBlade, tkArrow, tkHunter:
      CX := X + Travel * (1 - U) - Travel * After;
    tkDoor: CY := Y + Travel * (1 - U) + Travel * After;
    tkLaser: Height := H * U * (1 - After);
    tkLava: Height := H * U * (1 - After);
  end;
  Result.Left := CX - Width * 0.5;
  Result.Right := CX + Width * 0.5;
  Result.Bottom := CY;
  Result.Top := CY + Height;
end;

function TTrapPlatform.TopAt(X: Double): Double;
begin
  Result := Y + (EndY - Y) * EnsureRange((X - Left) / Max(0.001, Right - Left), 0.0, 1.0);
end;

function TTrapPlan.MoveAt(Time: Double): Integer;
var L, R, M: Integer;
begin
  L := 0; R := High(Moves); Result := 0;
  while L <= R do
  begin
    M := (L + R) div 2;
    if Moves[M].Start <= Time then begin Result := M; L := M + 1; end else R := M - 1;
  end;
end;

function TTrapPlan.Position(Time: Double): TTrapPoint;
begin
  if Length(Moves) = 0 then Exit(TrapPoint(0, 0));
  Result := Moves[MoveAt(Time)].Position(Time);
end;

function TTrapPlan.PlayerBounds(Time: Double): TTrapBox;
var P: TTrapPoint;
begin
  P := Position(Time);
  Result.Left := P.X - TrapHalfWidth;
  Result.Right := P.X + TrapHalfWidth;
  Result.Bottom := P.Y + 0.035;
  Result.Top := P.Y + Moves[MoveAt(Time)].HeightAt(Time);
end;

function TTrapPlan.ObstacleAt(Time: Double): Integer;
var L, R, M: Integer;
begin
  L := 0; R := High(Obstacles); Result := -1;
  while L <= R do
  begin
    M := (L + R) div 2;
    if Obstacles[M].Cue <= Time then begin Result := M; L := M + 1; end else R := M - 1;
  end;
end;

function TTrapPlan.Clearance(const Trap: TTrapObstacle; Time: Double): Double;
var A, B: TTrapBox; DX, DY: Double;
begin
  if not Trap.Dangerous(Time) then Exit(1000);
  A := PlayerBounds(Time); B := Trap.BoundsAt(Time);
  DX := Max(B.Left - A.Right, A.Left - B.Right);
  DY := Max(B.Bottom - A.Top, A.Bottom - B.Top);
  if (DX < 0) and (DY < 0) then Exit(Max(DX, DY));
  Result := Hypot(Max(0.0, DX), Max(0.0, DY));
end;

end.
