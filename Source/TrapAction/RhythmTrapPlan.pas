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
  // 保存IDの数値を保持する。現行は左右の歩行・ジャンプ・立ち止まりを採用する。
  TTrapMotion = (tmRun, tmJump, tmDoubleJump, tmSlide, tmStop, tmFall,
    tmWallKick, tmHang, tmClimb, tmRide, tmSkate, tmLaunch);
  TTrapKind = (tkSpikes, tkHiddenSpikes, tkCrumble, tkVanish, tkSink, tkMoving,
    tkFlip, tkFalseFloor, tkPit, tkCeiling, tkWall, tkBlade, tkDoor, tkWallBlock,
    tkTunnelCollapse, tkBoulder, tkRock, tkFlyingBlade, tkArrow, tkHunter,
    tkRain, tkFlame, tkLaser, tkLava, tkIce, tkTilt, tkBridge, tkCollapse, tkBackground);
  TTrapAvoidance = (taRetreatJump, taWaitPass, taDropStopJump, taBaitDrop,
    taRunUnderDrops, taBetweenDrops, taLowHop, taLongJump, taStepUp, taStepDown,
    taGapUp, taGapDown, taCrumbleUp, taVanishDown, taBackHop, taTripleHop, taTravel);
  TTrapMove = record
    Start, Cue, Finish: Double; // Cueは接地ならFinish、停止ならStart。同期時刻は元の音を使う。
    Origin, Target: TTrapPoint;
    Arc: Double;
    Kind: TTrapMotion;
    Section, Pattern: Integer;
    Landing, CueSynced, LandSynced: Boolean;
    Avoidance: TTrapAvoidance;
    function Position(Time: Double): TTrapPoint;
    function HeightAt(Time: Double): Double;
    function Progress(Time: Double): Double;
    function FootLift(Time: Double; Side: Integer): Double;
    function StepPhase(Time: Double): Double;
  end;
  TTrapObstacle = record
    Kind: TTrapKind;
    Reveal, Fire, Cue, Finish: Double;
    X, Y, W, H, Travel, Power: Double;
    Move: Integer;
    Synced: Boolean;
    function BoundsAt(Time: Double): TTrapBox;
    function RetractionStart: Double;
    function Dangerous(Time: Double): Boolean;
  end;
  TTrapPlatform = record
    Left, Right, Y, EndY: Double;
    Start, Finish: Double; // Finishで崩れる床。曲末まで残す床はDurationを指定する。
    Move: Integer; // 現行は-1（固定床）のみ。旧版のレコード配置は保持する。
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
    Ceilings: TArray<TTrapPlatform>; // Yは天井の下面。床と同じ水平区間で段差を表す。
    function MoveAt(Time: Double): Integer;
    function Position(Time: Double): TTrapPoint;
    function ForwardX(Time: Double): Double;
    function Facing(Time: Double): Double;
    function PlayerBounds(Time: Double): TTrapBox;
    function FloorSupports(Left, Right, Y, Time: Double): Boolean;
    function CeilingSupports(Left, Right, Y: Double): Boolean;
    function TerrainClearance(Time: Double): Double;
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
      TrapWalkSpeed = 6.8;

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
var U: Double;
begin
  U := Progress(Time);
  // 左右移動と停止を同じ絶対時刻で復元する。ジャンプは踏切から着地まで一つの放物線。
  Result := TrapPoint(Origin.X + (Target.X - Origin.X) * U,
    Origin.Y + (Target.Y - Origin.Y) * U + Arc * 4 * U * (1 - U));
end;

function TTrapMove.HeightAt(Time: Double): Double;
begin
  Result := TrapStandingHeight;
end;

function TTrapMove.FootLift(Time: Double; Side: Integer): Double;
var U: Double;
begin
  U := Progress(Time);
  if Kind = tmStop then Exit(0);
  if (U <= 0) or (U >= 1) then Exit(0);
  if Kind = tmJump then Exit(Sin(U * Pi) * 0.13);
  // 音の間にも細かい足運びを入れる。区間終点の接地は必ず元の音に一致させる。
  Result := Max(0.0, Sin(StepPhase(Time) + Side * Pi)) * 0.18;
end;

function TTrapMove.StepPhase(Time: Double): Double;
var Steps: Integer;
begin
  Steps := Max(2, Round(Abs(Target.X - Origin.X) / 0.85));
  Result := Progress(Time) * Steps * Pi;
end;

function TTrapObstacle.Dangerous(Time: Double): Boolean;
begin
  Result := not TrapHarmless(Kind) and (Time >= Fire) and (Time <= Finish);
end;

function TTrapObstacle.BoundsAt(Time: Double): TTrapBox;
var Height, Bottom, U: Double;
begin
  Height := H; Bottom := Y;
  if Kind = tkHiddenSpikes then
    Height := H * TrapRange(Time, Fire, Cue) * (1 - TrapRange(Time, RetractionStart, Finish));
  if Kind = tkCeiling then begin
    U := EnsureRange((Time - Fire) / (Cue - Fire), 0.0, 1.0);
    // 自由落下して音時刻に床へ刺さる。その後は床を突き抜けない。
    Bottom := Y + Travel * (1 - U * U);
  end;
  Result.Left := X - W * 0.5;
  Result.Right := X + W * 0.5;
  Result.Bottom := Bottom;
  Result.Top := Bottom + Height;
end;

function TTrapObstacle.RetractionStart: Double;
begin
  // 待機後に通る針は床へ引っ込む。下降区間も描画・衝突検査で同じ時刻を使う。
  Result := Finish - Min(0.06, (Finish - Cue) * 0.5);
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

function TTrapPlan.ForwardX(Time: Double): Double;
var I, Current: Integer;
begin
  // 再生履歴を使わず到達済みの右端を読む。停止・後退中はカメラを動かさない。
  Result := 0; Current := MoveAt(Time);
  for I := 0 to Current - 1 do
    Result := Max(Result, Max(Moves[I].Origin.X, Moves[I].Target.X));
  Result := Max(Result, Position(Time).X);
end;

function TTrapPlan.Facing(Time: Double): Double;
var M: TTrapMove;
begin
  M := Moves[MoveAt(Time)];
  if M.Target.X < M.Origin.X then Result := -1 else Result := 1;
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

function TTrapPlan.FloorSupports(Left, Right, Y, Time: Double): Boolean;
var Tile: TTrapPlatform; Covered, EndX: Double;
begin
  // 床は左から順に保存する。隣接タイルをつなぎ、足幅全体の支持を調べる。
  Covered := Left;
  for Tile in Platforms do
  begin
    if (Tile.Move >= 0) or (Time < Tile.Start) or
      ((Time >= Tile.Finish) and (Tile.Finish < Duration)) or
      (Tile.Right < Covered) or (Tile.Left > Covered + 1E-8) then Continue;
    EndX := Min(Right, Tile.Right);
    if (Abs(Tile.TopAt(Covered) - Y) > 1E-8) or
      (Abs(Tile.TopAt(EndX) - Y) > 1E-8) then Continue;
    Covered := Max(Covered, EndX);
    if Covered >= Right - 1E-8 then Exit(True);
  end;
  Result := False;
end;

function TTrapPlan.CeilingSupports(Left, Right, Y: Double): Boolean;
var Tile: TTrapPlatform; Covered: Double;
begin
  Covered:=Left;
  for Tile in Ceilings do if (Tile.Left<=Covered+1E-8) and
    (Tile.Right>=Covered) and (Abs(Y-Tile.Y)<1E-8) then begin
    Covered:=Max(Covered,Min(Right,Tile.Right));
    if Covered>=Right-1E-8 then Exit(True);
  end;
  Result := False;
end;

function TTrapPlan.TerrainClearance(Time: Double): Double;
var Tile: TTrapPlatform; Box: TTrapBox;
begin
  Box := PlayerBounds(Time); Result := 1000;
  for Tile in Platforms do begin
    if Tile.Left >= Box.Right then Break;
    if (Tile.Right <= Box.Left) or (Time < Tile.Start) or
      ((Time >= Tile.Finish) and (Tile.Finish < Duration)) then Continue;
    Result := Min(Result, Box.Bottom - Tile.Y);
  end;
  for Tile in Ceilings do begin
    if Tile.Left >= Box.Right then Break;
    if Tile.Right <= Box.Left then Continue;
    Result := Min(Result, Tile.Y - Box.Top);
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
