unit RhythmTrapPlan;
// 初見殺しアクションの保存契約と絶対時刻の幾何。足元を基準に軌道・当たり判定を共有する。
// 世界座標は右が+X、上が+Y。時刻は原音声の先頭からの秒、長さは同じワールド単位を使う。
// 生成・保存・描画は各専用ユニットへ委ね、このユニットではI/Oや再生状態の積算を行わない。
interface

uses System.SysUtils, RhythmStyles;

type
  TTrapPoint = record
    X, Y: Double;
  end;
  TTrapCorners = array[0..3] of TTrapPoint;
  TTrapBox = record
    Left, Bottom, Right, Top: Double;
  end;
  // 保存IDを保持する。歩行・ジャンプ・停止に、頭上接触と足場への追従を追加する。
  TTrapMotion = (tmRun, tmJump, tmDoubleJump, tmSlide, tmStop, tmFall,
    tmWallKick, tmHang, tmClimb, tmRide, tmSkate, tmLaunch, tmHeadBump, tmVault);
  TTrapKind = (tkSpikes, tkHiddenSpikes, tkCrumble, tkVanish, tkSink, tkMoving,
    tkFlip, tkFalseFloor, tkPit, tkCeiling, tkWall, tkBlade, tkDoor, tkWallBlock,
    tkTunnelCollapse, tkBoulder, tkRock, tkFlyingBlade, tkArrow, tkHunter,
    tkRain, tkFlame, tkLaser, tkLava, tkIce, tkTilt, tkBridge, tkCollapse, tkBackground,
    tkSideSpear,tkPress,tkCeilingNeedles,tkClosingDoor,tkFireJet,tkSpearMount);
  // Run/Sprintという旧名の保存IDも、現行の動作は歩行速度を超えない。
  TTrapAvoidance = (taRetreatJump, taWaitPass, taDropStopJump, taBaitDrop,
    taRunUnderDrops, taBetweenDrops, taLowHop, taLongJump, taStepUp, taStepDown,
    taGapUp, taGapDown, taCrumbleUp, taVanishDown, taBackHop, taTripleHop, taTravel,
    taSawHop, taTwinSaws, taSawGap, taSawStair, taRockRun, taRockStopJump,
    taRockBait, taRockGap, taDoubleGap, taTripleGap, taRisingGaps, taFallingGaps,
    taCrumbleChain, taVanishChain, taCrumbleNeedles, taVanishDrop, taNeedleRelay,
    taAlternatingHops, taLowHighHop, taDropStair, taDropSprintHop,
    taDelayedLanding, taCrossTrap, taFinalGauntlet, taFeintFloor, taFeintDrop,
    taCrushSlot, taCrushReverse, taHiddenStairs, taHiddenSwitchback,
    taMovingDescentX, taMovingDescentY, taCrushHop, taCrushFeint,
    taRoofShelters, taRoofNarrow, taRoofLastGap,
    taSideSpears,taAlternatingPresses,taFlipPit,taCeilingLift,taClosingDoors,taFireChase);
  TTrapPlatformMotion = (pmStatic, pmDrop, pmFeint, pmHorizontal, pmVertical, pmReveal, pmRoofDrop, pmGrate,pmHinge,pmLift,pmRoofRise,pmNeedleLift,pmGoalLift,pmGoalWall);
  TTrapMove = record
    Start, Cue, Finish: Double; // Cueは接地ならFinish、停止ならStart。同期時刻は元の音を使う。
    Origin, Target: TTrapPoint;
    Arc: Double; // 両端を結ぶ基準線からの跳躍量。Origin/TargetのYは足元の高さ。
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
    Reveal, Fire, Cue, Finish: Double; // 表示開始・作動開始・音に同期する結果・動作終端の秒。
    X, Y, W, H, Travel, Power, Embed: Double; // Embedは天井へ埋まる高さの比率。
    Move: Integer;
    Synced: Boolean;
    function BoundsAt(Time: Double): TTrapBox;
    function RetractionStart: Double;
    function PulseAt(Time:Double):Double; // 伸長・保持・復帰を保存時刻から直接求める。
    function Dangerous(Time: Double): Boolean;
  end;
  TTrapPlatform = record
    Left, Right, Y, EndY: Double;
    Start, Finish: Double; // 実体の有効期間。pmNeedleLiftは連続する上下行程ごとに実体を切り替える。
    Move: Integer; // 実タイルは-1。移動はMotionと保存時刻から復元する。
    Kind: TTrapKind;
    Motion:TTrapPlatformMotion;
    Reveal,Trigger,Settle,DX,DY:Double; // Revealは出現、Trigger/Settleは移動開始/到達の秒。
    // DX/DYはMotionごとの保存値。pmNeedleLiftのDXは最終保持指定、pmGoalWallのDYは壁の絶対上面。
    Release,Recover:Double; // 保持終了・復帰完了。ゴール床では地上到達・花火を含む演出終端。
    function OffsetAt(Time:Double):TTrapPoint;
    function BoundsAt(Time:Double):TTrapBox;
    function CeilingBoundsAt(Time:Double):TTrapBox;
    // Finish=原音声長の床は、その後のゴール演出でも支持を失わない。
    function Solid(Time,Duration:Double):Boolean;
    function TopAt(X: Double;Time:Double=0): Double;
    function RotationAt(Time:Double):Double;
    function CornersAt(Time:Double):TTrapCorners;
    function Intersects(const Box:TTrapBox;Time:Double):Boolean;
  end;
  TTrapPlan = class
  public
    // Durationは原音声長。GoalTime/GoalXは音同期コースの終点で、地上へ出る追加演出は含めない。
    Duration, GoalTime, GoalX: Double;
    Theme: TTrapStage;
    Moves: TArray<TTrapMove>;
    Obstacles: TArray<TTrapObstacle>;
    Platforms: TArray<TTrapPlatform>;
    Ceilings: TArray<TTrapPlatform>; // Yは天井の下面。床と同じ水平区間で段差を表す。
    // Build/Codecが検証した非空のMovesを読む。配列・保存時刻は評価中に書き換えない。
    function MoveAt(Time: Double): Integer;
    function Position(Time: Double): TTrapPoint;
    function ForwardX(Time: Double): Double;
    // ViewWidthと戻り値は世界座標。画面倍率は描画側が決め、末尾の横追従だけを減速する。
    function CameraLeft(Time,ViewWidth:Double):Double;
    function Facing(Time: Double): Double;
    function PlayerBounds(Time: Double): TTrapBox;
    // 一点の接地でなく、指定した足幅全体を同じ時刻・高さの実体が支えるかを調べる。
    function FloorSupports(Left, Right, Y, Time: Double): Boolean;
    function CeilingSupports(Left, Right, Y: Double;Time:Double=0): Boolean;
    function TerrainClearance(Time: Double): Double;
    function ObstacleAt(Time: Double): Integer;
    function Clearance(const Trap: TTrapObstacle; Time: Double): Double;
    function GoalLift(out Lift:TTrapPlatform):Boolean;
    // 保存済みゴール床から復元する表示時刻。床がなければSurfaceTime=0、EndTime=Duration。
    function SurfaceTime:Double;
    function EndTime:Double;
  end;

function TrapPoint(X, Y: Double): TTrapPoint;
function TrapEase(Value: Double): Double;
function TrapRange(Time, First, Last: Double): Double;
function TrapOverlap(const A, B: TTrapBox): Boolean;
function TrapHarmless(Kind: TTrapKind): Boolean;
function TrapFloorSpikes(Kind:TTrapKind):Boolean;
function TrapPatternEnabled(Kind:TTrapAvoidance):Boolean;
function TrapPatternTier(Kind: TTrapAvoidance): Integer;
function TrapPatternFamily(Kind: TTrapAvoidance): Integer;
function TrapPatternSteps(Kind: TTrapAvoidance): Integer;
function TrapPatternTitle(Kind: TTrapAvoidance): string;

const TrapHalfWidth = 0.32;
      TrapStandingHeight = 1.12;
      TrapWalkSpeed = 6.8; // 歩行・ジャンプ・後退に共通の水平速度上限。音の密度で引き上げない。
      TrapBackHopArc = 0.55; // 短い後退で落下針の下降経路へ上半身を入れない。
      TrapPatternCount = 57;
      TrapPlatformThickness = 0.20;
      TrapSpikeLowering = 0.20; // 伸縮針が作動したときの到達高さはv14と同じに保つ。
      TrapSpikeTipDrop = 0.50; // 固定針・針束・待機中の伸縮針の先端と、歩く床面との落差。
      TrapSpikePitDepth = 1.0 + TrapSpikeTipDrop; // 下げた先端から1ブロックの刃を穴底まで見せる。
      TrapRoofBedLowering = 0.90; // 落下天井の下を出口より低いくぼみにする。
      TrapRoofBedRise = 2.40; // 退避後、天井の復帰と一緒に床を持ち上げる。
      TrapRoofExitHeight = 2.20; // 作動前は最大の跳躍高2.1でも登れない固定の出口。
      TrapNeedleLiftHeight = 1.55;
      TrapNeedleLiftExit = 2.60; // 床が低い間は登れず、最後の上昇を使う出口。
      TrapGoalAhead = 2.40;
      TrapGoalRise = 8.00;
      TrapGoalLaunchSeconds = 0.85;
      TrapGoalCelebration = 2.00; // 共通花火1.48秒が消えた後も地上の姿を少し残す。
      TrapGroundDepth = 12.0; // 崩落・沈下も通常の地面と同じ地層の塊。薄い板にしない。

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
  Result := Kind in [tkCrumble, tkVanish, tkSink, tkMoving, tkFlip, tkPit,tkFalseFloor,
    tkTunnelCollapse, tkIce, tkTilt, tkBridge, tkCollapse];
end;

function TrapFloorSpikes(Kind:TTrapKind):Boolean;
begin Result:=Kind in [tkSpikes,tkHiddenSpikes,tkBlade];end;

function TrapPatternEnabled(Kind:TTrapAvoidance):Boolean;
begin Result:=not (Kind in [taTravel,taFeintFloor,taFeintDrop]);end;

function TrapPatternTier(Kind: TTrapAvoidance): Integer;
begin
  case Kind of
    taLowHop,taLongJump,taStepUp,taStepDown,taGapUp,taGapDown,taRoofShelters:Result:=0;
    taDropStopJump,taRunUnderDrops,taCrumbleUp,taVanishDown,taWaitPass,
      taSawHop,taRockRun,taDoubleGap,taLowHighHop,taSideSpears,taAlternatingPresses,taFlipPit:Result:=1;
    taTripleGap,taCrumbleNeedles,taVanishDrop,taDropStair,taDropSprintHop,
    taDelayedLanding,taCrossTrap,taFinalGauntlet,taCrushReverse,
      taHiddenSwitchback,taMovingDescentY,taRoofLastGap:Result:=3;
    taFeintFloor,taCrushFeint:Result:=1;
    else Result:=2;
  end;
end;

function TrapPatternFamily(Kind: TTrapAvoidance): Integer;
begin
  case Kind of
    taSideSpears:Result:=8;
    taAlternatingPresses:Result:=9;
    taFlipPit:Result:=10;
    taCeilingLift:Result:=11;
    taClosingDoors:Result:=12;
    taFireChase:Result:=13;
    taRoofShelters,taRoofNarrow,taRoofLastGap:Result:=7;
    taRetreatJump,taBaitDrop,taBackHop,taRockBait:Result:=5;
    taStepUp,taStepDown,taGapUp,taGapDown,taDoubleGap,taTripleGap,
      taRisingGaps,taFallingGaps:Result:=1;
    taCrumbleUp,taVanishDown,taCrumbleChain,taVanishChain,taCrumbleNeedles,
      taVanishDrop,taDelayedLanding:Result:=2;
    taDropStopJump,taRunUnderDrops,taBetweenDrops,taRockRun,taRockStopJump,
      taRockGap,taDropStair,taDropSprintHop:Result:=3;
    taSawHop,taTwinSaws,taSawGap,taSawStair:Result:=4;
    taCrossTrap,taFinalGauntlet,taCrushSlot,taCrushReverse,taHiddenStairs,
      taHiddenSwitchback,taMovingDescentX,taMovingDescentY,taCrushHop,taCrushFeint:Result:=6;
    taFeintFloor,taFeintDrop:Result:=2;
    else Result:=0;
  end;
end;

function TrapPatternSteps(Kind: TTrapAvoidance): Integer;
begin
  case Kind of
    taSideSpears:Result:=4;
    taCeilingLift:Result:=8;
    taAlternatingPresses,taFireChase:Result:=6;
    taFlipPit:Result:=2;
    taClosingDoors:Result:=3;
    taTripleHop,taTripleGap,taRisingGaps,taFallingGaps,taVanishChain,
      taNeedleRelay,taAlternatingHops,taDropStair:Result:=3;
    taFinalGauntlet,taHiddenStairs,taHiddenSwitchback,taRoofShelters,taRoofNarrow,taRoofLastGap:Result:=5;
    taCrushSlot,taCrushReverse,taMovingDescentX,taMovingDescentY,taCrushHop,taCrushFeint:Result:=4;
    taTwinSaws,taSawGap,taSawStair,taDoubleGap,taCrumbleChain,taCrumbleNeedles,
      taVanishDrop,taLowHighHop,taDropSprintHop,taDelayedLanding,taCrossTrap,
      taFeintFloor,taFeintDrop:Result:=2;
    else Result:=1;
  end;
end;

function TrapPatternTitle(Kind: TTrapAvoidance): string;
const Names:array[TTrapAvoidance] of string=(
  '後退して跳ぶ','引き込みを待って進む','落下針を止まって越す','落下を誘い後退',
  '連続落下の間を歩く','落下の間で待つ','低い天井で小跳び','二列の針越え',
  '段差上り','段差下り','高い足場へ穴越え','低い足場へ穴越え',
  '崩れる床から上る','消える床から下る','後方ジャンプで誘う','三連小跳び','移動',
  '往復する針束越え','二連の針束','針束から穴へ','段違いの針束',
  '連続落石の間を歩く','落石を止まって越す','落石を誘い後退','落石と穴',
  '二連の穴','三連の穴','上りの連続穴','下りの連続穴',
  '崩落の連鎖','消失の連鎖','崩落から隠し針','消失から落下針',
  '隠し針の三連鎖','高低交互の小跳び','小跳びから大跳び','段差と交互落下',
  '落下の間を歩いて跳ぶ','着地後に崩れる地面','穴と針束と落石','終盤の五連仕掛け',
  '落ちそうで落ちない床','フェイントから本当の崩落','U字のくぼみで右の隙間へ',
  'U字のくぼみで左の隙間へ','頭突きで現れる足場の階段','頭突きから反対側へ登る',
  '横揺れする足場で降りる','上下する足場で降りる','迫る片壁を跳び越す',
  'くぼみで迫る壁のフェイント','段違いの天井と三つの隙間',
  'かみ合う天井と二つの隙間','落ちる天井と最後の隙間',
  '左右の横槍を抜ける','交互に落ちる大型プレス','跳ね上がる床と針穴',
  '天井針へせり上がる地面','背後から閉じる連続扉','火柱を追い最後に戻る');
begin Result:=Names[Kind];end;

function TTrapMove.Progress(Time: Double): Double;
begin
  Result := EnsureRange((Time - Start) / (Finish - Start), 0.0, 1.0);
end;

function TTrapMove.Position(Time: Double): TTrapPoint;
var U,V: Double;
begin
  if Time<=Start then Exit(Origin);
  if Time>=Finish then Exit(Target);
  U := Progress(Time);
  if Kind=tmHeadBump then begin
    Result:=Origin;
    if Time<=Cue then begin
      U:=EnsureRange((Time-Start)/Max(1E-8,Cue-Start),0.0,1.0);
      Result.Y:=Origin.Y+Arc*(4*U-U*U)/3;
    end else begin
      U:=EnsureRange((Time-Cue)/Max(1E-8,Finish-Cue),0.0,1.0);
      Result.Y:=Origin.Y+Arc-(Origin.Y+Arc-Target.Y)*Sqr(U);
    end;
    Exit;
  end;
  if Kind=tmRide then begin
    if Arc>0 then begin
      Result:=Origin;Result.Y:=Origin.Y-Arc*Sin(U*Pi);
    end else begin
      U:=Sin(U*Pi*0.5);
      Result:=TrapPoint(Origin.X+(Target.X-Origin.X)*U,Origin.Y+(Target.Y-Origin.Y)*U);
    end;
    Exit;
  end;
  // 左右移動と停止を同じ絶対時刻で復元する。ジャンプは踏切から着地まで一つの放物線。
  V:=U;if Kind=tmVault then V:=Sqr(U); // 狭間では先に上へ跳び、縁を越えてから前へ進む。
  Result := TrapPoint(Origin.X + (Target.X - Origin.X) * V,
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
  if Kind in [tmStop,tmRide] then Exit(0);
  if (U <= 0) or (U >= 1) then Exit(0);
  if Kind in [tmJump,tmHeadBump,tmVault] then Exit(Sin(U * Pi) * 0.13);
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
  if Kind in [tkSideSpear,tkFireJet] then Exit((Time>=Fire) and (Time<=Finish) and (PulseAt(Time)>1E-6));
  Result := not TrapHarmless(Kind) and
    (((Kind in [tkWall,tkBlade,tkPress,tkClosingDoor,tkCeilingNeedles,tkSpearMount]) and (Time>=0)) or ((Time>=Fire) and (Time<=Finish)));
end;

function TTrapObstacle.BoundsAt(Time: Double): TTrapBox;
var Height, Bottom, Top, U, Center,Hold: Double;
begin
  Height := H; Bottom := Y; Center := X;
  if Kind = tkHiddenSpikes then
    Height := (H+TrapSpikeTipDrop-TrapSpikeLowering) * TrapRange(Time, Fire, Cue) *
      (1 - TrapRange(Time, RetractionStart, Finish));
  if Kind in [tkCeiling,tkRock] then begin
    U := EnsureRange((Time - Fire) / (Cue - Fire), 0.0, 1.0);
    // 自由落下して音時刻に床へ刺さる。その後は床を突き抜けない。
    Bottom := Y + Travel * (1 - U * U);
  end;
  if Kind=tkBlade then Center:=X+Travel*Sin(EnsureRange(Time-Fire,0.0,Finish-Fire)*2*Pi/Max(0.2,Power));
  if Kind=tkWall then begin
    U:=EnsureRange((Time-Fire)/Max(1E-8,Cue-Fire),0.0,1.0);
    if Time>Cue then begin
      Hold:=Min(0.12,(Finish-Cue)*0.25);
      U:=1-EnsureRange((Time-Cue-Hold)/Max(1E-8,Finish-Cue-Hold),0.0,1.0);
    end;
    Center:=X+Power*Travel*U;
  end;
  if Kind=tkPress then Bottom:=Y+Travel*(1-PulseAt(Time));
  if Kind=tkClosingDoor then Bottom:=Y+Travel*(1-TrapRange(Time,Fire,Cue));
  if Kind=tkFireJet then Height:=H*PulseAt(Time);
  // 先端の実座標を床下へ固定する。元の突出量との相殺で床面へ戻さない。
  Top:=Bottom+Height;
  if TrapFloorSpikes(Kind) then begin
    Top:=Y-TrapSpikeTipDrop;
    if Kind=tkHiddenSpikes then Top:=Top+Height;
    Bottom:=Y-TrapSpikePitDepth;
  end;
  Result.Left := Center - W * 0.5;
  Result.Right := Center + W * 0.5;
  Result.Bottom := Bottom;
  Result.Top := Top;
  if Kind=tkSideSpear then begin
    U:=Power*W*PulseAt(Time);Result.Left:=X+Min(0.0,U);Result.Right:=X+Max(0.0,U);
  end;
end;

function TTrapObstacle.RetractionStart: Double;
begin
  if Kind in [tkSideSpear,tkPress,tkFireJet] then Exit(Finish-Min(0.24,(Finish-Cue)*0.75));
  // 待機後に通る針は床へ引っ込む。下降区間も描画・衝突検査で同じ時刻を使う。
  Result := Finish - Min(0.06, (Finish - Cue) * 0.5);
end;

function TTrapObstacle.PulseAt(Time:Double):Double;
var U:Double;
begin
  U:=TrapRange(Time,Fire,Cue);
  if Kind=tkPress then U:=Sqr(EnsureRange((Time-Fire)/Max(1E-8,Cue-Fire),0.0,1.0));
  Result:=U*(1-TrapRange(Time,RetractionStart,Finish));
end;

function TTrapPlatform.OffsetAt(Time:Double):TTrapPoint;
var U:Double;
begin
  Result:=TrapPoint(0,0);
  case Motion of
    pmDrop:if Time>Trigger then Result.Y:=-Min(8.0,48*Sqr(Time-Trigger));
    pmFeint:begin
      U:=EnsureRange((Time-Trigger)/Max(1E-8,Settle-Trigger),0.0,1.0);
      Result.Y:=-DY*Sin(U*Pi);
    end;
    pmHorizontal,pmVertical:begin
      U:=(Time-Trigger)/Max(1E-8,Settle-Trigger);
      Result:=TrapPoint(DX*Sin(U*Pi*0.5),DY*Sin(U*Pi*0.5));
    end;
    pmRoofDrop:begin
      if Time<=Trigger then U:=0
      else if Time<Settle then U:=Sqr((Time-Trigger)/(Settle-Trigger))
      else if Time<=Release then U:=1
      else U:=1-TrapRange(Time,Release,Recover);
      Result.Y:=-DY*U;
      if (DX>0) and (Time>Release) then
        Result.Y:=Result.Y+DX*Sin(EnsureRange((Time-Release)/(Recover-Release),0.0,1.0)*Pi*0.5);
    end;
    pmRoofRise:if Time>Trigger then
      Result.Y:=DY*Sin(EnsureRange((Time-Trigger)/(Settle-Trigger),0.0,1.0)*Pi*0.5);
    pmNeedleLift:begin
      if Time<=Trigger then Exit;
      if Time<Settle then Result.Y:=DY*Sin(EnsureRange((Time-Trigger)/(Settle-Trigger),0.0,1.0)*Pi*0.5)
      else if (DX>0) or (Time<=Release) then Result.Y:=DY
      else Result.Y:=DY*(1-Sin(EnsureRange((Time-Release)/(Recover-Release),0.0,1.0)*Pi*0.5));
    end;
    pmGoalLift:Result.Y:=DY*TrapRange(Time,Trigger,Settle);
    pmLift:begin
      if Time<=Trigger then Exit;
      if Time<=Settle then Result.Y:=DY*Sin(EnsureRange((Time-Trigger)/(Settle-Trigger),0.0,1.0)*Pi*0.5)
      else if Time<=Release then Result.Y:=DY+DX*TrapRange(Time,Settle,Release)
      else Result.Y:=(DY+DX)*(1-TrapRange(Time,Release,Recover));
    end;
  end;
end;

function TTrapPlatform.CeilingBoundsAt(Time:Double):TTrapBox;
var D:TTrapPoint;
begin
  D:=OffsetAt(Time);Result.Left:=Left+D.X;Result.Right:=Right+D.X;
  Result.Bottom:=Y+D.Y;Result.Top:=Result.Bottom+TrapGroundDepth;
  if Motion=pmGoalWall then Result.Top:=DY;
end;

function TTrapPlatform.BoundsAt(Time:Double):TTrapBox;
var D:TTrapPoint;C:TTrapCorners;I:Integer;
begin
  if Motion=pmHinge then begin
    C:=CornersAt(Time);Result.Left:=C[0].X;Result.Right:=C[0].X;Result.Bottom:=C[0].Y;Result.Top:=C[0].Y;
    for I:=1 to 3 do begin Result.Left:=Min(Result.Left,C[I].X);Result.Right:=Max(Result.Right,C[I].X);
      Result.Bottom:=Min(Result.Bottom,C[I].Y);Result.Top:=Max(Result.Top,C[I].Y);end;
    Exit;
  end;
  D:=OffsetAt(Time);Result.Left:=Left+D.X;Result.Right:=Right+D.X;
  Result.Top:=Y+D.Y;
  if Motion=pmStatic then Result.Bottom:=-1000
  else if Motion in [pmDrop,pmFeint,pmLift,pmRoofRise,pmNeedleLift] then Result.Bottom:=Result.Top-TrapGroundDepth
  else if Motion=pmGrate then Result.Bottom:=Result.Top-0.10
  else Result.Bottom:=Result.Top-TrapPlatformThickness;
end;

function TTrapPlatform.RotationAt(Time:Double):Double;
begin
  Result:=0;if Motion=pmHinge then Result:=TrapRange(Time,Trigger,Settle)*Pi*0.5;
end;

function TTrapPlatform.CornersAt(Time:Double):TTrapCorners;
var A,C,S,U,V:Double;I:Integer;
begin
  A:=RotationAt(Time);C:=Cos(A);S:=Sin(A);
  for I:=0 to 3 do begin
    U:=0;if I in [1,2] then U:=Right-Left;
    V:=0;if I in [2,3] then V:=-TrapPlatformThickness;
    Result[I]:=TrapPoint(Left+U*C-V*S,Y+U*S+V*C);
  end;
end;

function TTrapPlatform.Intersects(const Box:TTrapBox;Time:Double):Boolean;
var C:TTrapCorners;I,J:Integer;AX,AY,V,Lo,Hi,BLo,BHi:Double;
begin
  if Motion<>pmHinge then Exit(TrapOverlap(Box,BoundsAt(Time)));
  C:=CornersAt(Time);
  // 板の辺と身体の辺の分離軸。回転板の空いた矩形領域で誤接触にしない。
  for I:=0 to 3 do begin
    AX:=1;AY:=0;
    if I=1 then begin AX:=0;AY:=1;end;
    if I>=2 then begin AX:=-(C[I-1].Y-C[I-2].Y);AY:=C[I-1].X-C[I-2].X;end;
    Lo:=1E30;Hi:=-1E30;
    for J:=0 to 3 do begin V:=C[J].X*AX+C[J].Y*AY;Lo:=Min(Lo,V);Hi:=Max(Hi,V);end;
    BLo:=Min(Box.Left*AX,Box.Right*AX)+Min(Box.Bottom*AY,Box.Top*AY);
    BHi:=Max(Box.Left*AX,Box.Right*AX)+Max(Box.Bottom*AY,Box.Top*AY);
    if (BHi<=Lo+1E-9) or (BLo>=Hi-1E-9) then Exit(False);
  end;
  Result:=True;
end;

function TTrapPlatform.Solid(Time,Duration:Double):Boolean;
begin
  Result:=(Time>=Start) and ((Time<Finish) or (Finish=Duration));
  if Motion=pmReveal then Result:=Result and (Time>=Reveal);
end;

function TTrapPlatform.TopAt(X: Double;Time:Double): Double;
var D:TTrapPoint;
begin
  if (Motion=pmHinge) and (Time>Trigger) then Exit(BoundsAt(Time).Top);
  D:=OffsetAt(Time);
  Result := Y+D.Y+(EndY-Y)*EnsureRange((X-D.X-Left)/Max(0.001,Right-Left),0.0,1.0);
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
var Lift:TTrapPlatform;U:Double;
begin
  if Length(Moves) = 0 then Exit(TrapPoint(0, 0));
  if (Time>GoalTime) and GoalLift(Lift) then begin
    U:=EnsureRange((Time-GoalTime)/Max(1E-8,Lift.Trigger-GoalTime),0.0,1.0);
    Result:=TrapPoint(GoalX+((Lift.Left+Lift.Right)*0.5-GoalX)*U,Lift.BoundsAt(Time).Top);Exit;
  end;
  Result := Moves[MoveAt(Time)].Position(Time);
end;

function TTrapPlan.GoalLift(out Lift:TTrapPlatform):Boolean;
var Tile:TTrapPlatform;
begin
  for Tile in Platforms do if Tile.Motion=pmGoalLift then begin Lift:=Tile;Exit(True);end;
  Lift:=Default(TTrapPlatform);Result:=False;
end;

function TTrapPlan.SurfaceTime:Double;
var Lift:TTrapPlatform;
begin Result:=0;if GoalLift(Lift) then Result:=Lift.Settle;end;

function TTrapPlan.EndTime:Double;
var Lift:TTrapPlatform;
begin Result:=Duration;if GoalLift(Lift) then Result:=Max(Result,Lift.Recover);end;

function TTrapPlan.ForwardX(Time: Double): Double;
var I, Current: Integer;
begin
  // 再生履歴を使わず到達済みの右端を読む。停止・後退中はカメラを動かさない。
  Result := 0; Current := MoveAt(Time);
  for I := 0 to Current - 1 do
    Result := Max(Result, Max(Moves[I].Origin.X, Moves[I].Target.X));
  Result := Max(Result, Position(Time).X);
end;

function TTrapPlan.CameraLeft(Time,ViewWidth:Double):Double;
const SlowDistance=1.20;
var Lift:TTrapPlatform;StopLeft,U:Double;
begin
  Result:=ForwardX(Time)-ViewWidth*0.32;
  if not GoalLift(Lift) then Exit;
  StopLeft:=(Lift.Left+Lift.Right)*0.5-ViewWidth*0.5;
  if Result<=StopLeft-SlowDistance then Exit;
  // 前進量から減速する。中央へ寄せるために横パンを引くと、乗り込み中に逆走してしまう。
  // 傾き1から0へ滑らかに落とし、板へ足が掛かる前に縦穴中央の構図へ固定する。
  U:=EnsureRange((Result-StopLeft+SlowDistance)/(2*SlowDistance),0.0,1.0);
  Result:=StopLeft-SlowDistance*Sqr(1-U);
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
var Tile: TTrapPlatform; Covered, Previous, EndX: Double;B:TTrapBox;Pass:Integer;
begin
  // 同じ絶対時刻のタイルをつなぐ。往復する足場でも足幅全体の支持を調べる。
  Covered := Left;
  for Pass:=0 to High(Platforms) do begin
    Previous:=Covered;
    for Tile in Platforms do begin
      B:=Tile.BoundsAt(Time);
      if not Tile.Solid(Time,Duration) or (B.Right<Covered) or (B.Left>Covered+1E-8) then Continue;
      EndX:=Min(Right,B.Right);
      if (Abs(Tile.TopAt(Covered,Time)-Y)>1E-8) or (Abs(Tile.TopAt(EndX,Time)-Y)>1E-8) then Continue;
      Covered:=Max(Covered,EndX);if Covered>=Right-1E-8 then Exit(True);
    end;
    if Covered<=Previous+1E-10 then Break;
  end;
  Result := False;
end;

function TTrapPlan.CeilingSupports(Left, Right, Y: Double;Time:Double): Boolean;
var Tile: TTrapPlatform; Covered: Double;
begin
  Covered:=Left;
  for Tile in Ceilings do if (Tile.Left<=Covered+1E-8) and
    (Tile.Right>=Covered) and (Abs(Y-Tile.CeilingBoundsAt(Time).Bottom)<1E-8) then begin
    Covered:=Max(Covered,Min(Right,Tile.Right));
    if Covered>=Right-1E-8 then Exit(True);
  end;
  Result := False;
end;

function TTrapPlan.TerrainClearance(Time: Double): Double;
var Tile: TTrapPlatform; Box,B: TTrapBox;
begin
  Box := PlayerBounds(Time); Result := 1000;
  for Tile in Platforms do begin
    if not Tile.Solid(Time,Duration) then Continue;
    if (Tile.Motion=pmHinge) and not Tile.Intersects(Box,Time) then Continue;
    B:=Tile.BoundsAt(Time);if (B.Left>=Box.Right) or (B.Right<=Box.Left) then Continue;
    if B.Bottom>=Box.Top then Result:=Min(Result,B.Bottom-Box.Top)
    else Result := Min(Result, Box.Bottom-B.Top);
  end;
  for Tile in Ceilings do begin
    if Tile.Left >= Box.Right then Break;
    if Tile.Right <= Box.Left then Continue;
    B:=Tile.CeilingBoundsAt(Time);
    if (Tile.Motion=pmGoalWall) and (Box.Bottom>=B.Top) then Continue;
    Result := Min(Result, B.Bottom - Box.Top);
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
