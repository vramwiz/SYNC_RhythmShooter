unit RhythmMarbleCourse;
// コースの型と、絶対時刻から位置・回転・接触を読むための計算を持つ。
interface

uses RhythmBallGeometry;

const
  RailDrag = 1.14;
  GoalTime = 0.34;
  ArcSteps = 28;
  RollingFactor = 5 / 7;
  TriggerDelay = 0.014;
  ArrivalMargin = 0.016;
  LowerGrade = -0.085;
  DuetBrakeTime = 0.16;
  LiftBrakeTime = 0.09;
  TrayTiltTime = 0.12;
  TrayTilt = 0.43;

  MarbleRadius = 0.155;
  MarbleAuxRadius = 0.088;
  MarbleAuxGateNose = MarbleAuxRadius + 0.037;
  MarbleSlope = -0.19;
  MarbleGravity = 15.5;
  MarbleSeesawExitGrade = -0.30;
  MarbleTrayRear = -0.18;
  MarbleTrayNose = 0.135;
  MarbleJunctionSpan = 0.37;

type
  TMarbleMotion = (mmRail, mmFlight, mmSettle, mmBend, mmCarry, mmSwing, mmSeesaw);
  TMarbleDevice = (mdGate, mdBell, mdSpring, mdCatch, mdTip, mdGoal,
    mdBend, mdLift, mdShuttle, mdSwing, mdChute, mdSharedTap, mdSeesaw, mdTrayRelease, mdJunctionGate);
  TMarbleLinkKind = (mlNone, mlShutter, mlSpringLatch);
  TMarbleBeat = record
    Time: Double; // 音源上の接触時刻［秒］。
    Power: Double; // 描画とEQに渡す接触強度［0..1］。
  end;
  TMarbleLink = record
    Kind: TMarbleLinkKind; // ドライバーが作動させる機構。
    Target: Integer; // 主球側のリンクが参照する接触番号。
    Heading: Integer; // 進行方向。右が+1、左が-1。
    Pull, Ready, Deadline: Double; // 引き始め、可動部の整列、球の到達期限［秒］。
    Driver, Receiver: TBallPoint; // 入力レバーと受け側の機構の取り付け位置。
    function Opening(Time: Double): Double;
  end;
  TMarbleRun = record
    Start: Double; // 区間の始点時刻［秒］。
    Speed, Grade: Double; // 始点の水平速さと、進行方向の水平距離あたりの高低差。
    Origin: TBallPoint; // 転がり始めの球の中心。
    function Position(Time: Double; Heading: Integer): TBallPoint;
    function SpeedAt(Time: Double): Double;
  end;
  TMarbleJunction = record
    Branch: TMarbleRun; // 切り替え後に主球が進む斜面。
    Pull, Ready: Double; // 回転開始とレールがつながる時刻［秒］。
    function Active: Boolean;
    function Pivot(Heading: Integer): TBallPoint;
    function Tip(Time: Double; Heading: Integer): TBallPoint;
    procedure Spur(out A, B: TBallPoint; Heading: Integer);
  end;
  TMarbleLatch = record
    Beat: TMarbleBeat; // 球がレバーに触れる入力。
    Contact, Pivot: TBallPoint; // レバー先端の接触位置と回転軸。
    function SeatedAt: Double;
    function Amount(Time: Double): Double;
  end;
  TMarbleInterlock = record
    Inputs: array[0..1] of TMarbleLatch; // 主球と小球がそれぞれ押すレバー。
    Gate: TMarbleLink; // 両方の入力が揃ってから開くゲート。
    SmallDeadline: Double; // 小球の前縁がゲートへ届く時刻［秒］。
    function Active: Boolean;
    function Opening(Time: Double): Double;
  end;
  TMarbleBoard = record
    Pivot: TBallPoint; // 板を支える回転軸。
    Heading: Integer; // 板の前方が右なら+1、左なら-1。
    Start, Stop: Double; // 主球が板に乗る時刻と板が止まる時刻［秒］。
    BaseAngle, Tilt: Double; // 初期角度と、前端が下がる回転量［rad］。
    Rear, Front, LoadPoint: Double; // 軸を原点とした後端、前端、主球の乗り込み位置。
    function AngleAt(Time: Double): Double;
    function PointAt(Time, Along, Radius: Double): TBallPoint;
    function VelocityAt(Time, Along, Radius, RollSpeed: Double): TBallPoint;
    function MainDistance(Time: Double): Double;
  end;
  TMarbleWeightLift = record
    Load: TBallPoint; // 下段で停止した主球の中心。
    Arrival, Start, Dock: Double; // 主球の乗車、昇降開始、上段への接続時刻［秒］。
    Rise, Ramp: Double; // 垂直の移動量と、上段への渡り板の水平長。
    function Active: Boolean;
    function Progress(Time: Double): Double;
    function Carriage(Time: Double): TBallPoint;
  end;
  TMarbleTrayRelease = record
    Lever: TMarbleLatch; // 主球が受け皿の留め具を外す入力。
    Start: Double; // 受け皿が傾き始める時刻［秒］。
    function Active: Boolean;
    function AngleAt(Time: Double): Double;
    function DistanceAt(Time: Double): Double;
  end;
  TMarbleSeesaw = record
    Board: TMarbleBoard; // 小球を反対側から跳ね上げる板。
    Trigger, Bell: TMarbleBeat; // 空中レバーまたは着地の音と、その先の鐘または分岐レバーの音。
    Seat, SeatSpeed: Double; // 板が動き始める時点の小球の位置と板に沿った速さ。
    Launch, LaunchVelocity: TBallPoint; // 板から離れるときの小球中心と速度。
    LeverContact, Landing: TBallPoint; // 空中レバーの接触位置と受け皿での小球中心。
    WeightLift: TMarbleWeightLift; // 受け皿の下降と連動して主球を上げるリフト。
    TrayRelease: TMarbleTrayRelease; // 主球が押したレバーで受け皿を傾ける仕掛け。
    SwitchLever: TMarbleLatch; // 小球が主球側の分岐を切り替える入力。
    ExitGate: TMarbleLink; // 分岐の先で主球が開ける小球側のゲート。
    ExitBell: TMarbleBeat; // ゲート通過後に小球が鳴らす羽根車の鐘。
    CatchRail, ExitRail: TMarbleRun; // 受け皿の先のレールと、曲線で勾配を緩めた先のレール。
    ExitCurveStart: Double; // 勾配の切り替えが始まる時刻［秒］。
    Gate: TMarbleLink; // 空中レバーで開く主球側のゲート。
    function Pan(Time: Double): TBallPoint;
    function TrayPoint(Time, Along, Radius: Double): TBallPoint;
    function RunPosition(Time: Double): TBallPoint;
    function RunGrade(Time: Double): Double;
    function Active: Boolean;
    function Position(Time, Finish: Double): TBallPoint;
  end;
  TMarbleCounter = record
    DetourBeat: TMarbleBeat; // 主球側の近道または共通ゲートを開ける小球の音。
    Taps: array[0..1] of TMarbleBeat; // 主球が追い越し返した後に小球が鳴らす押し板。
    Rejoin, LastRun: TMarbleRun; // 迂回路からの合流区間と最後の押し板へ続く区間。
    Entry: TBallPoint; // 小球が迂回路へ入るときの中心。
    Start: Double; // 迂回路へ入る時刻［秒］。
    EntrySpeed, Depth: Double; // 入口の水平速さと、入口・出口を結ぶ直線からの落ち幅。
    Gate: TMarbleLink; // 小球が開ける主球側の近道。
    Interlock: TMarbleInterlock; // 2球のレバーで開ける共通ゲート。
    Seesaw: TMarbleSeesaw; // 共通ゲートの先で小球を跳ね上げる仕掛け。
    function Active: Boolean;
    function Guide(U: Double): TBallPoint;
    function GuideSlope(U: Double): Double;
    function Position(Time, Finish: Double; Heading: Integer): TBallPoint;
  end;
  TMarblePass = record
    Fork: TMarbleBeat; // 小球が追い越し用の分岐を押す音。
    Taps: array[0..1] of TMarbleBeat; // 小球が前に出た後に鳴らす押し板。
    Approach, Bypass, Rejoin, LastRun: TMarbleRun; // 分岐への進入、迂回、合流、最後の押し板への区間。
    ExitOrigin, ExitVelocity: TBallPoint; // 後続の仕掛けが無い場合にレールを離れる位置と速度。
    SwitchPull, SwitchReady: Double; // 分岐の可動部が動き始める時刻と整列時刻［秒］。
    Counter: TMarbleCounter; // 主球が追い越し返す区間。
    function Active: Boolean;
    function Position(Time, Finish: Double; Heading: Integer): TBallPoint;
  end;
  TMarbleMerge = record
    Launch: TMarbleBeat; // 小球を上段へ跳ね返すばねの音。
    Taps: array[0..1] of TMarbleBeat; // 合流後に小球が鳴らす押し板。
    Join, JoinSpeed: Double; // 合流の時刻［秒］とそのときの水平速さ。
    Grade, LowerDrag, TapSpeed: Double; // 合流先の勾配、下段の抵抗、第1押し板の直後の水平速さ。
    LaunchPoint, LaunchVelocity: TBallPoint; // ばねから離れる位置と速度。
    JoinPoint, TapPoint: TBallPoint; // 合流点と第1押し板での小球の中心。
    Pass: TMarblePass; // 小球が別レールから主球を追い越す区間。
    function Active: Boolean;
    function Position(Time, Finish: Double; Heading: Integer): TBallPoint;
  end;
  TMarbleAuxiliary = record
    Origin, Receiver: TBallPoint; // 小球の待機位置と最初のレバーを押すときの中心。
    Release, Strike: Double; // 待機位置を出る時刻と最初のレバーを押す時刻［秒］。
    StrikePower, RunSpeed, RunGrade: Double; // 最初の接触強度と、その後の水平速さ・勾配。
    Finish: Double; // 最後に小球が停止する時刻［秒］。
    DropStart, DropEnd: Double; // レールを離れてから下段へ着地するまでの時刻［秒］。
    LandingSpeed: Double; // 下段に着いた直後の水平速さ。
    DropOrigin, DropVelocity: TBallPoint; // 落下開始時の中心と速度。
    Landing: TBallPoint; // 下段レールに着地したときの中心。
    SecondStrike, Bell: TMarbleBeat; // 2本目の橋を開ける入力と、初期の交互区間の鐘。
    AuxGates: array[0..1] of TMarbleLink; // 主球が順に開ける小球側のゲート。
    Merge: TMarbleMerge; // 下段から主球と同じレールへ戻る区間。
    function Active: Boolean;
    function Duet: Boolean;
    function Reciprocal: Boolean;
    function Crossover: Boolean;
    function Position(Time: Double): TBallPoint;
    function RailGrade(Time: Double): Double;
  end;
  TMarbleBridge = record
    Entry, Hinge: TBallPoint; // 橋の入口と回転軸。
    Pull, Ready, Deadline: Double; // 動き始め、接続完了、球の到達期限［秒］。
    Auxiliary: TMarbleAuxiliary; // 橋を動かす小球とその後続区間。
    Sliding, Retracting: Boolean; // 水平に出す橋か、球を落とすために引き込む橋か。
    function Active: Boolean;
    function Tip(Time: Double): TBallPoint;
  end;
  TMarbleLeg = record
    Motion: TMarbleMotion; // この区間で使う運動の種類。
    Heading: Integer; // 進行方向。右が+1、左が-1。
    Start, Finish: Double; // 区間の開始・終了時刻［秒］。
    VX, VY: Double; // 初速。転がりではVXを進行方向の水平速さとして使う。
    Grade, Terminal, Drag: Double; // 勾配、終端の水平速さ、速度に比例する抵抗係数。
    Radius: Double; // 曲がりや振り子で使う半径。
    EntryGap, DropLip: Double; // 固定レールを省く入口・出口側の水平長。
    Dock: Double; // 搬送から転がりへ移る時刻［秒］。
    Spin, FreeSpin: Double; // 区間開始時の回転角［rad］と空中の角速度［rad/s］。
    Origin, Travel: TBallPoint; // 区間開始時の中心と搬送台の変位。
    Board: TMarbleBoard; // シーソーで主球を支える板。
    WeightLift: TMarbleWeightLift; // 板を降りた主球を上段へ運ぶリフト。
    Bridge: TMarbleBridge; // この区間に付く可動橋。
    Junction: TMarbleJunction; // レールの回転で接続先を変える分岐。
    ArcClock: TArray<Double>; // 等角度で区切ったカーブの累積通過時刻。
    function Position(Time: Double): TBallPoint;
    function Velocity(Time: Double): TBallPoint;
    function Carriage(Time: Double): TBallPoint;
    function Rotation(Time: Double): Double;
    function Rollout: Boolean;
    function RailSlope: Double;
    procedure RailSupport(out A, B: TBallPoint);
    function LiftRailSupport(out A, B: TBallPoint): Boolean;
    procedure BranchRailSupport(out A, B: TBallPoint);
    function HasWeightLift: Boolean;
    function ArcPoint(Angle: Double): TBallPoint;
    function ArcPivot: TBallPoint;
  end;
  TMarbleCue = record
    Time, Power: Double; // 主球の接触時刻［秒］と元の音の強度［0..1］。
    Slope: Double; // 接触面のワールド座標における勾配。
    RelayBeat: TMarbleBeat; // 主球のこの接触と次の接触の間に、小球へ渡せる音。
    SharedBeat: TMarbleBeat; // 同じ押し板を小球が押す時刻。譜面から復元する。
    Heading: Integer; // 接触時の進行方向。右が+1、左が-1。
    Device: TMarbleDevice; // 接触に反応する仕掛け。
    Center, Surface: TBallPoint; // 接触時の球の中心と、仕掛けの接触位置。
  end;
  TMarbleSection = record
    First, Last: Integer; // 描画区画に含む先頭と末尾の区間番号。
    Left, Right, Bottom, Top: Double; // 描画の間引きに使うワールド座標の境界。
  end;
  TMarblePlan = class
  public
    Version: Integer; // 復元時に使うコース配置の版。
    Duration, EndTime: Double; // 音源の長さと、終点での停止を含む演出の長さ［秒］。
    Cues: TArray<TMarbleCue>; // 時刻順に並ぶ主球の接触。
    Legs: TArray<TMarbleLeg>; // 0は最初の接触まで、以降は接触番号+1の区間。
    Sections: TArray<TMarbleSection>; // 画面外の仕掛けを省くための区画。
    Links: TArray<TMarbleLink>; // ドライバーの接触番号で引く。
    // 時刻以下の最後の主球接触を返す。開始前は-1。
    function CueAt(Time: Double): Integer;
    // EQ用に2球の接触を時刻順で参照し、接触番号と強度を返す。
    function BeatAt(Time: Double; out Beat: TMarbleBeat): Integer;
    function Position(Time: Double): TBallPoint;
    // 前後の位置を使ってカメラの追従点を平滑化する。
    function CameraTarget(Time: Double): TBallPoint;
    function Rotation(Time: Double): Double;
  end;

// 球中心からレールの法線方向へ半径ぶん戻した接触位置を返す。
function MarbleRailSurface(const Center: TBallPoint; Slope: Double = MarbleSlope): TBallPoint;
// 水平速さが抵抗で終端速度に近づくときの区間内の水平移動量を返す。
function RailDistance(StartSpeed, Terminal, Drag, Age: Double): Double;
// 勾配と抵抗係数から水平成分の終端速度を求める。
function RailTerminalFor(Grade, Drag: Double): Double;
// 受け皿が最後まで傾いたときの接線方向の転がり加速度を返す。
function TrayAcceleration: Double;

implementation

uses System.Math;

const
  GoalTravel = 0.47;
  SwingHalf = 0.80;
  LatchTime = 0.068;
  JunctionSpurAngle = -1.07;
  JunctionSpurLength = 0.32;

function MarbleRailSurface(const Center: TBallPoint; Slope: Double): TBallPoint;
begin
  Result := BallSub(Center, BallScale(BallUnit(BallPoint(-Slope, 1)), MarbleRadius));
end;

function TMarbleLeg.RailSlope: Double;
begin
  Result := Heading * Grade;
end;

procedure TMarbleLeg.RailSupport(out A, B: TBallPoint);
begin
  A := MarbleRailSurface(BallAdd(Origin, BallPoint(Heading * EntryGap, Grade * EntryGap)), RailSlope);
  if Motion = mmSeesaw then A := MarbleRailSurface(Position(Dock), RailSlope);
  if Junction.Active then
  begin
    B := MarbleRailSurface(Junction.Branch.Origin, RailSlope);
    Exit;
  end;
  B := MarbleRailSurface(Position(Finish), RailSlope);
  if HasWeightLift then
    B := MarbleRailSurface(WeightLift.Load, RailSlope)
  else
    B := BallSub(B, BallPoint(Heading * DropLip, Grade * DropLip));
end;

function TMarbleLeg.LiftRailSupport(out A, B: TBallPoint): Boolean;
var DockPoint: TBallPoint;
begin
  DockPoint := WeightLift.Carriage(WeightLift.Dock);
  A := MarbleRailSurface(BallAdd(DockPoint, BallPoint(Heading * WeightLift.Ramp, Grade * WeightLift.Ramp)), RailSlope);
  B := MarbleRailSurface(Position(Finish), RailSlope);
  Result := Heading * (B.X - A.X) > 0;
end;

procedure TMarbleLeg.BranchRailSupport(out A, B: TBallPoint);
var BranchGrade: Double;
begin
  BranchGrade := Junction.Branch.Grade;
  A := Junction.Pivot(Heading);
  B := MarbleRailSurface(Position(Finish), Heading * BranchGrade);
  B := BallSub(B, BallPoint(Heading * DropLip, BranchGrade * DropLip));
end;

function TMarbleLeg.HasWeightLift: Boolean;
begin
  Result := (Motion = mmSeesaw) and WeightLift.Active;
end;

function Smooth(U: Double): Double;
begin
  Result := Sqr(U) * (3 - 2 * U);
end;

function TMarbleJunction.Active: Boolean;
begin
  Result := Ready > Pull;
end;

function TMarbleJunction.Pivot(Heading: Integer): TBallPoint;
begin
  Result := MarbleRailSurface(Branch.Origin, Heading * Branch.Grade);
end;

function TMarbleJunction.Tip(Time: Double; Heading: Integer): TBallPoint;
var Angle, U: Double;
begin
  U := Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0));
  Angle := JunctionSpurAngle + (ArcTan(Branch.Grade) - JunctionSpurAngle) * U;
  Result := BallAdd(Pivot(Heading), BallPoint(Heading * MarbleJunctionSpan * Cos(Angle), MarbleJunctionSpan * Sin(Angle)));
end;

procedure TMarbleJunction.Spur(out A, B: TBallPoint; Heading: Integer);
begin
  A := Tip(Pull, Heading);
  B := BallAdd(A, BallPoint(Heading * JunctionSpurLength * Cos(JunctionSpurAngle),
    JunctionSpurLength * Sin(JunctionSpurAngle)));
end;

function TMarbleLink.Opening(Time: Double): Double;
begin
  Result := 0;
  if Kind <> mlNone then Result := Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0));
end;

function TMarbleLatch.SeatedAt: Double;
begin
  Result := Beat.Time + LatchTime;
end;

function TMarbleLatch.Amount(Time: Double): Double;
begin
  Result := Smooth(EnsureRange((Time - Beat.Time) / LatchTime, 0.0, 1.0));
end;

function TMarbleInterlock.Active: Boolean;
begin
  Result := Gate.Kind = mlShutter;
end;

function TMarbleInterlock.Opening(Time: Double): Double;
begin
  if not Active or (Time < Inputs[0].SeatedAt) or (Time < Inputs[1].SeatedAt) then Exit(0);
  Result := Gate.Opening(Time);
end;

function TMarbleBoard.AngleAt(Time: Double): Double;
var U: Double;
begin
  U := EnsureRange((Time - Start) / (Stop - Start), 0.0, 1.0);
  Result := BaseAngle - Tilt * Sqr(U) * U;
end;

function TMarbleBoard.PointAt(Time, Along, Radius: Double): TBallPoint;
var A: Double;
begin
  A := AngleAt(Time);
  Result := BallAdd(Pivot, BallPoint(Heading * (Along * Cos(A) - Radius * Sin(A)), Along * Sin(A) + Radius * Cos(A)));
end;

function TMarbleBoard.VelocityAt(Time, Along, Radius, RollSpeed: Double): TBallPoint;
var A, U, W, Tangent, Normal: Double;
begin
  A := AngleAt(Time);
  U := EnsureRange((Time - Start) / (Stop - Start), 0.0, 1.0);
  W := -3 * Tilt * Sqr(U) / (Stop - Start);
  Tangent := RollSpeed - Radius * W;
  Normal := Along * W;
  Result := BallPoint(Heading * (Tangent * Cos(A) - Normal * Sin(A)), Tangent * Sin(A) + Normal * Cos(A));
end;

function TMarbleBoard.MainDistance(Time: Double): Double;
begin
  Result := LoadPoint + (Front - LoadPoint) * EnsureRange((Time - Start) / (Stop - Start), 0.0, 1.0);
end;

function TMarbleAuxiliary.Active: Boolean;
begin
  Result := Strike > Release;
end;

function TMarbleAuxiliary.Duet: Boolean;
begin
  Result := Finish > Strike;
end;

function TMarbleAuxiliary.Reciprocal: Boolean;
begin
  Result := SecondStrike.Time > 0;
end;

function TMarbleAuxiliary.Crossover: Boolean;
begin
  Result := DropEnd > DropStart;
end;

function TMarbleAuxiliary.RailGrade(Time: Double): Double;
begin
  if Merge.Active and (Time >= Merge.Join) then Exit(Merge.Grade);
  if Crossover and (Time >= DropEnd) then Exit(LowerGrade);
  Result := RunGrade;
end;

function TMarbleRun.Position(Time: Double; Heading: Integer): TBallPoint;
var D: Double;
begin
  D := RailDistance(Speed, RailTerminalFor(Grade, RailDrag), RailDrag, Time - Start);
  Result := BallAdd(Origin, BallPoint(Heading * D, Grade * D));
end;

function TMarbleRun.SpeedAt(Time: Double): Double;
var Terminal: Double;
begin
  Terminal := RailTerminalFor(Grade, RailDrag);
  Result := Terminal + (Speed - Terminal) * Exp(-RailDrag * (Time - Start));
end;

function TMarbleWeightLift.Active: Boolean;
begin
  Result := Dock > Start;
end;

function TMarbleWeightLift.Progress(Time: Double): Double;
begin
  Result := Smooth(EnsureRange((Time - Start) / (Dock - Start), 0.0, 1.0));
end;

function TMarbleWeightLift.Carriage(Time: Double): TBallPoint;
begin
  Result := BallAdd(Load, BallPoint(0, Rise * Progress(Time)));
end;

function TMarbleTrayRelease.Active: Boolean;
begin
  Result := Start > 0;
end;

function TMarbleTrayRelease.AngleAt(Time: Double): Double;
begin
  Result := -TrayTilt * Smooth(EnsureRange((Time - Start) / TrayTiltTime, 0.0, 1.0));
end;

function TrayAcceleration: Double;
begin
  Result := RollingFactor * MarbleGravity * Sin(TrayTilt);
end;

function TMarbleTrayRelease.DistanceAt(Time: Double): Double;
var U, Roll: Double;
begin
  U := EnsureRange((Time - Start) / TrayTiltTime, 0.0, 1.0);
  Roll := Max(0.0, Time - Start - TrayTiltTime);
  // 傾く間は加速度を滑らかに増やし、その後は一定の斜面として転がす。
  Result := TrayAcceleration * (Sqr(TrayTiltTime) * Sqr(Sqr(U)) * (0.25 - U * 0.1) +
    Roll * (TrayTiltTime + Roll) / 2);
end;

function TMarbleSeesaw.Pan(Time: Double): TBallPoint;
begin
  Result := BallSub(Landing, BallPoint(0, WeightLift.Rise * WeightLift.Progress(Time)));
end;

function TMarbleSeesaw.TrayPoint(Time, Along, Radius: Double): TBallPoint;
var Angle: Double; Pivot: TBallPoint;
begin
  Pivot := Pan(Time);
  Pivot.Y := Pivot.Y - MarbleAuxRadius;
  Angle := TrayRelease.AngleAt(Time);
  Result := BallAdd(Pivot, BallPoint(Board.Heading * (Along * Cos(Angle) - Radius * Sin(Angle)),
    Along * Sin(Angle) + Radius * Cos(Angle)));
end;

function TMarbleSeesaw.RunPosition(Time: Double): TBallPoint;
var Entry: TBallPoint; Distance, Span: Double;
begin
  if (ExitRail.Start > 0) and (Time >= ExitRail.Start) then Exit(ExitRail.Position(Time, Board.Heading));
  Result := CatchRail.Position(Time, Board.Heading);
  if (ExitRail.Start = 0) or (Time <= ExitCurveStart) then Exit;
  Entry := CatchRail.Position(ExitCurveStart, Board.Heading);
  Distance := Board.Heading * (Result.X - Entry.X);
  Span := Board.Heading * (ExitRail.Origin.X - Entry.X);
  Result.Y := Result.Y + (ExitRail.Grade - CatchRail.Grade) * Sqr(Distance) / (2 * Span);
end;

function TMarbleSeesaw.RunGrade(Time: Double): Double;
var Entry, P: TBallPoint; U: Double;
begin
  Result := CatchRail.Grade;
  if (ExitRail.Start = 0) or (Time <= ExitCurveStart) then Exit;
  if Time >= ExitRail.Start then Exit(ExitRail.Grade);
  Entry := CatchRail.Position(ExitCurveStart, Board.Heading);
  P := CatchRail.Position(Time, Board.Heading);
  U := (P.X - Entry.X) / (ExitRail.Origin.X - Entry.X);
  Result := Result + (ExitRail.Grade - Result) * U;
end;

function TMarbleSeesaw.Active: Boolean;
begin
  Result := (Board.Stop > Board.Start) and (Trigger.Time > Board.Stop) and (CatchRail.Start > Trigger.Time);
end;

function TMarbleSeesaw.Position(Time, Finish: Double): TBallPoint;
var Age, T, BrakeAge: Double;
begin
  if Time < Board.Stop then
    Exit(Board.PointAt(Time, Seat + SeatSpeed * (Time - Board.Start), MarbleAuxRadius));
  if Time < CatchRail.Start then
  begin
    if WeightLift.Active and (Time >= Trigger.Time) then
    begin
      if TrayRelease.Active then Exit(TrayPoint(Time, TrayRelease.DistanceAt(Time), MarbleAuxRadius));
      Exit(Pan(Time));
    end;
    Age := Time - Board.Stop;
    Exit(BallAdd(Launch, BallPoint(LaunchVelocity.X * Age, LaunchVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age))));
  end;
  T := Min(Time, Finish);
  BrakeAge := Max(0.0, T - (Finish - DuetBrakeTime));
  Result := RunPosition(T - Sqr(BrakeAge) / (2 * DuetBrakeTime));
end;

function TMarbleCounter.Active: Boolean;
begin
  Result := (Start > 0) and (Rejoin.Start > Start);
end;

function TMarbleCounter.Guide(U: Double): TBallPoint;
begin
  Result := BallMix(Entry, Rejoin.Origin, U);
  Result.Y := Result.Y - Depth * Sqr(Sin(Pi * U));
end;

function TMarbleCounter.GuideSlope(U: Double): Double;
begin
  Result := (Rejoin.Origin.Y - Entry.Y - Pi * Depth * Sin(2 * Pi * U)) / (Rejoin.Origin.X - Entry.X);
end;

function TMarbleCounter.Position(Time, Finish: Double; Heading: Integer): TBallPoint;
var U, Duration, Distance, T, BrakeAge: Double;
begin
  if Seesaw.Active and (Time >= Seesaw.Board.Start) then Exit(Seesaw.Position(Time, Finish));
  if Time < Rejoin.Start then
  begin
    Duration := Rejoin.Start - Start;
    Distance := Abs(Rejoin.Origin.X - Entry.X);
    U := (Time - Start) / Duration;
    Exit(Guide(Smooth(U) + U * (1 - U) * ((1 - U) * EntrySpeed - U * Rejoin.Speed) * Duration / Distance));
  end;
  if Time < Taps[0].Time then Exit(Rejoin.Position(Time, Heading));
  T := Min(Time, Finish);
  BrakeAge := Max(0.0, T - (Finish - DuetBrakeTime));
  Result := LastRun.Position(T - Sqr(BrakeAge) / (2 * DuetBrakeTime), Heading);
end;

function TMarblePass.Active: Boolean;
begin
  Result := (Fork.Time > 0) and (Rejoin.Start > Fork.Time);
end;

function TMarblePass.Position(Time, Finish: Double; Heading: Integer): TBallPoint;
var Age: Double;
begin
  if Time < Fork.Time then Exit(Approach.Position(Time, Heading));
  if Time < Rejoin.Start then Exit(Bypass.Position(Time, Heading));
  if Time < Taps[0].Time then Exit(Rejoin.Position(Time, Heading));
  if Time < Taps[1].Time then Exit(LastRun.Position(Time, Heading));
  if Counter.Active then Exit(Counter.Position(Time, Finish, Heading));
  Age := Min(Time, Finish) - Taps[1].Time;
  Result := BallAdd(ExitOrigin, BallPoint(ExitVelocity.X * Age, ExitVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age)));
end;

function TMarbleMerge.Active: Boolean;
begin
  Result := (Launch.Time > 0) and (Join > Launch.Time);
end;

function TMarbleMerge.Position(Time, Finish: Double; Heading: Integer): TBallPoint;
var Age, BrakeAge, Start, Speed, Distance: Double; P: TBallPoint;
begin
  if Pass.Active and (Time >= Taps[1].Time) then Exit(Pass.Position(Time, Finish, Heading));
  if Time < Join then
  begin
    Age := Time - Launch.Time;
    Exit(BallAdd(LaunchPoint, BallPoint(LaunchVelocity.X * Age, LaunchVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age))));
  end;
  Start := Join;
  Speed := JoinSpeed;
  P := JoinPoint;
  if Time >= Taps[0].Time then
  begin
    Start := Taps[0].Time;
    Speed := TapSpeed;
    P := TapPoint;
  end;
  Age := Min(Time, Finish) - Start;
  BrakeAge := Max(0.0, Age - (Finish - Start - DuetBrakeTime));
  Distance := RailDistance(Speed, RailTerminalFor(Grade, RailDrag), RailDrag, Age - Sqr(BrakeAge) / (2 * DuetBrakeTime));
  Result := BallAdd(P, BallPoint(Heading * Distance, Grade * Distance));
end;

function TMarbleAuxiliary.Position(Time: Double): TBallPoint;
var Age, BrakeAge, Distance, StartTime, Speed, Grade, Drag: Double; StartPoint: TBallPoint;
begin
  if not Active then Exit(Origin);
  if Duet and (Time > Strike) then
  begin
    if Merge.Active and (Time >= Merge.Launch.Time) then
      Exit(Merge.Position(Time, Finish, Sign(Receiver.X - Origin.X)));
    if Crossover and (Time >= DropStart) and (Time < DropEnd) then
    begin
      Age := Time - DropStart;
      Exit(BallAdd(DropOrigin, BallPoint(DropVelocity.X * Age, DropVelocity.Y * Age - 0.5 * MarbleGravity * Sqr(Age))));
    end;
    StartTime := Strike;
    StartPoint := Receiver;
    Speed := RunSpeed;
    Grade := RailGrade(Time);
    Drag := RailDrag;
    if Crossover and (Time >= DropEnd) then
    begin
      StartTime := DropEnd;
      StartPoint := Landing;
      Speed := LandingSpeed;
      if Merge.LowerDrag > 0 then Drag := Merge.LowerDrag;
    end;
    Age := Min(Time, Finish) - StartTime;
    BrakeAge := Max(0.0, Age - (Finish - StartTime - DuetBrakeTime));
    Distance := RailDistance(Speed, RailTerminalFor(Grade, Drag), Drag,
      Age - Sqr(BrakeAge) / (2 * DuetBrakeTime));
    Exit(BallAdd(StartPoint, BallPoint(Sign(Receiver.X - Origin.X) * Distance, Grade * Distance)));
  end;
  Result := BallMix(Origin, Receiver, Sqr(EnsureRange((Time - Release) / (Strike - Release), 0.0, 1.0)));
end;

function TMarbleBridge.Active: Boolean;
begin
  Result := Ready > Pull;
end;

function TMarbleBridge.Tip(Time: Double): TBallPoint;
var Span, Angle, U: Double;
begin
  if Retracting and Active then
    Exit(BallMix(Entry, Hinge, Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0))));
  if not Active or (Time >= Ready) then Exit(Entry);
  Span := BallLength(BallSub(Hinge, Entry));
  U := Smooth(EnsureRange((Time - Pull) / (Ready - Pull), 0.0, 1.0));
  if Sliding then Exit(BallMix(Hinge, Entry, U));
  Angle := ArcTan2(Hinge.Y - Entry.Y, Abs(Hinge.X - Entry.X)) + 1.23 * (1 - U);
  Result := BallPoint(Hinge.X - Sign(Hinge.X - Entry.X) * Span * Cos(Angle), Hinge.Y - Span * Sin(Angle));
end;

function TMarbleLeg.Rollout: Boolean;
begin
  Result := (Motion in [mmCarry, mmSwing]) and (Dock > Start) and (Dock < Finish);
end;

function TMarbleLeg.ArcPivot: TBallPoint;
begin
  if Motion = mmBend then Exit(BallPoint(Origin.X, Origin.Y - Radius));
  Result := BallPoint(Origin.X + Heading * Radius * Sin(SwingHalf), Origin.Y + Radius * Cos(SwingHalf));
end;

function TMarbleLeg.ArcPoint(Angle: Double): TBallPoint;
var Pivot: TBallPoint;
begin
  Pivot := ArcPivot;
  if Motion = mmBend then
    Exit(BallPoint(Pivot.X + Heading * Radius * Sin(Angle), Pivot.Y + Radius * Cos(Angle)));
  Result := BallPoint(Pivot.X + Heading * Radius * Sin(Angle), Pivot.Y - Radius * Cos(Angle));
end;

function BendSpeed(const Leg: TMarbleLeg; Angle: Double): Double;
begin
  Result := Sqrt(Sqr(Leg.VX) + 2 * RollingFactor * MarbleGravity * Leg.Radius * (1 - Cos(Angle)));
end;

function BendAngle(const Leg: TMarbleLeg; Age: Double): Double;
var L, R, M: Integer; U, A, B, Span, TangentA, TangentB: Double;
begin
  if Age <= 0 then Exit(0);
  if Age >= Leg.Finish - Leg.Start then Exit(Pi);
  L := 0;
  R := High(Leg.ArcClock);
  while R - L > 1 do
  begin
    M := (L + R) div 2;
    if Leg.ArcClock[M] <= Age then L := M else R := M;
  end;
  Span := Leg.ArcClock[R] - Leg.ArcClock[L];
  U := (Age - Leg.ArcClock[L]) / Span;
  A := L * Pi / ArcSteps;
  B := R * Pi / ArcSteps;
  TangentA := Span * BendSpeed(Leg, A) / Leg.Radius;
  TangentB := Span * BendSpeed(Leg, B) / Leg.Radius;
  // 区間境界でも角速度が連続するよう、通過時刻表を接線付きで補間する。
  Result := A + (B - A) * Smooth(U) + U * (1 - U) * ((1 - U) * TangentA - U * TangentB);
end;

function RailDistance(StartSpeed, Terminal, Drag, Age: Double): Double;
begin
  Result := Terminal * Age + (StartSpeed - Terminal) * (1 - Exp(-Drag * Age)) / Drag;
end;

function TMarbleLeg.Carriage(Time: Double): TBallPoint;
var EndTime, U: Double;
begin
  EndTime := Finish;
  if Rollout then EndTime := Dock;
  U := Smooth((EnsureRange(Time, Start, EndTime) - Start) / (EndTime - Start));
  if Motion = mmSwing then Exit(ArcPoint(SwingHalf * (2 * U - 1)));
  if Travel.Y < 0 then Exit(BallAdd(Origin, BallPoint(Travel.X * U, Travel.Y * Sqr(U))));
  Result := BallAdd(Origin, BallScale(Travel, U));
end;

function TMarbleLeg.Position(Time: Double): TBallPoint;
var Age, DX, U: Double;
begin
  Age := EnsureRange(Time, Start, Finish) - Start;
  if Rollout and (Time > Dock) then
  begin
    DX := RailDistance(0, Terminal, Drag, Age - (Dock - Start));
    Exit(BallAdd(Carriage(Dock), BallPoint(Heading * DX, Grade * DX)));
  end;
  case Motion of
    mmRail:
      begin
        if Junction.Active and (Time >= Junction.Branch.Start) then
          Exit(Junction.Branch.Position(Min(Time, Finish), Heading));
        DX := RailDistance(VX, Terminal, Drag, Age);
        Result := BallPoint(Origin.X + Heading * DX, Origin.Y + Grade * DX);
      end;
    mmFlight:
      Result := BallPoint(Origin.X + VX * Age, Origin.Y + VY * Age - 0.5 * MarbleGravity * Sqr(Age));
    mmSettle:
      begin
        U := Age / GoalTime;
        Result := BallPoint(Origin.X + Heading * GoalTravel * U * (2 - U), Origin.Y);
      end;
    mmBend: Result := ArcPoint(BendAngle(Self, Age));
    mmCarry, mmSwing: Result := Carriage(Time);
    mmSeesaw:
      begin
        if Time <= Dock then Exit(Board.PointAt(Time, Board.MainDistance(Time), MarbleRadius));
        if HasWeightLift then
        begin
          if Time >= WeightLift.Dock then
          begin
            DX := RailDistance(0, Terminal, Drag, Age - (WeightLift.Dock - Start));
            Exit(BallAdd(WeightLift.Carriage(WeightLift.Dock), BallPoint(Heading * DX, Grade * DX)));
          end;
          if Time >= WeightLift.Arrival then Exit(WeightLift.Carriage(Time));
          U := Max(0.0, Time - (WeightLift.Arrival - LiftBrakeTime));
          Age := Age - Sqr(U) / (2 * LiftBrakeTime);
        end;
        DX := RailDistance(VX, Terminal, Drag, Age - (Dock - Start));
        Result := BallAdd(Board.PointAt(Dock, Board.Front, MarbleRadius), BallPoint(Heading * DX, Grade * DX));
      end;
  end;
end;

function TMarbleLeg.Velocity(Time: Double): TBallPoint;
var Age, Speed, Angle, U, ActiveTime: Double;
begin
  Age := EnsureRange(Time, Start, Finish) - Start;
  ActiveTime := Finish - Start;
  if Rollout then
  begin
    ActiveTime := Dock - Start;
    if Time > Dock then
    begin
      Speed := Terminal * (1 - Exp(-Drag * (Age - ActiveTime)));
      Exit(BallPoint(Heading * Speed, Grade * Speed));
    end;
  end;
  case Motion of
    mmRail:
      begin
        if Junction.Active and (Time >= Junction.Branch.Start) then
        begin
          Speed := Junction.Branch.SpeedAt(Min(Time, Finish));
          Exit(BallPoint(Heading * Speed, Junction.Branch.Grade * Speed));
        end;
        Speed := Terminal + (VX - Terminal) * Exp(-Drag * Age);
        Result := BallPoint(Heading * Speed, Grade * Speed);
      end;
    mmFlight: Result := BallPoint(VX, VY - MarbleGravity * Age);
    mmSettle: Result := BallPoint(Heading * 2 * GoalTravel / GoalTime * (1 - Age / GoalTime), 0);
    mmBend:
      begin
        Angle := BendAngle(Self, Age);
        Speed := BendSpeed(Self, Angle);
        Result := BallPoint(Heading * Speed * Cos(Angle), -Speed * Sin(Angle));
      end;
    mmCarry:
      begin
        U := Age / ActiveTime;
        Result := BallScale(Travel, 6 * U * (1 - U) / ActiveTime);
        if Travel.Y < 0 then Result.Y := Result.Y * 2 * Smooth(U);
      end;
    mmSwing:
      begin
        U := Age / ActiveTime;
        Angle := SwingHalf * (2 * Smooth(U) - 1);
        Speed := Radius * 2 * SwingHalf * 6 * U * (1 - U) / ActiveTime;
        Result := BallPoint(Heading * Speed * Cos(Angle), Speed * Sin(Angle));
      end;
    mmSeesaw:
      begin
        if Time < Dock then Exit(Board.VelocityAt(Time, Board.MainDistance(Time), MarbleRadius,
          (Board.Front - Board.LoadPoint) / (Dock - Start)));
        Age := Age - (Dock - Start);
        if HasWeightLift then
        begin
          if Time >= WeightLift.Dock then
          begin
            Speed := Terminal * (1 - Exp(-Drag * (Age - (WeightLift.Dock - Dock))));
            Exit(BallPoint(Heading * Speed, Grade * Speed));
          end;
          if Time >= WeightLift.Arrival then
          begin
            ActiveTime := WeightLift.Dock - WeightLift.Start;
            U := EnsureRange((Time - WeightLift.Start) / ActiveTime, 0.0, 1.0);
            Exit(BallPoint(0, WeightLift.Rise * 6 * U * (1 - U) / ActiveTime));
          end;
          U := Max(0.0, Time - (WeightLift.Arrival - LiftBrakeTime));
          Age := Age - Sqr(U) / (2 * LiftBrakeTime);
          Speed := (Terminal + (VX - Terminal) * Exp(-Drag * Age)) * (1 - U / LiftBrakeTime);
        end
        else Speed := Terminal + (VX - Terminal) * Exp(-Drag * Age);
        Result := BallPoint(Heading * Speed, Grade * Speed);
      end;
  end;
end;

function TMarbleLeg.Rotation(Time: Double): Double;
var Distance, Age: Double;
begin
  Result := Spin;
  Age := EnsureRange(Time, Start, Finish) - Start;
  case Motion of
    mmFlight: Exit(Spin + FreeSpin * Age);
    mmBend: Distance := Radius * BendAngle(Self, Age);
    mmRail, mmSettle:
      begin
        Distance := BallLength(BallSub(Position(Time), Origin));
        if Junction.Active and (Time > Junction.Branch.Start) then
          Distance := BallLength(BallSub(Junction.Branch.Origin, Origin)) +
            BallLength(BallSub(Position(Time), Junction.Branch.Origin));
      end;
    mmSeesaw:
      begin
        Distance := Board.MainDistance(Time) - Board.LoadPoint;
        if HasWeightLift and (Time >= WeightLift.Arrival) then
        begin
          Distance := Distance + BallLength(BallSub(WeightLift.Load, Position(Dock)));
          if Time > WeightLift.Dock then
            Distance := Distance + BallLength(BallSub(Position(Time), WeightLift.Carriage(WeightLift.Dock)));
        end
        else if Time > Dock then Distance := Distance + BallLength(BallSub(Position(Time), Position(Dock)));
      end;
    else
      begin
        if not Rollout or (Time <= Dock) then Exit;
        Distance := BallLength(BallSub(Position(Time), Carriage(Dock)));
      end;
  end;
  Result := Spin - Heading * Distance / MarbleRadius;
end;

function TMarblePlan.CueAt(Time: Double): Integer;
var L, R, M: Integer;
begin
  L := 0;
  R := Length(Cues);
  while L < R do
  begin
    M := (L + R) div 2;
    if Cues[M].Time <= Time then L := M + 1 else R := M;
  end;
  Result := L - 1;
end;

function TMarblePlan.BeatAt(Time: Double; out Beat: TMarbleBeat): Integer;
var Index, Offset: Integer; Aux: TMarbleAuxiliary; Reply: TMarbleBeat;
begin
  Index := CueAt(Time);
  Beat := Default(TMarbleBeat);
  if Index < 0 then Exit(-1);
  Beat.Time := Cues[Index].Time;
  Beat.Power := Cues[Index].Power;
  if Version < 6 then Exit(Index);
  Result := Index * 2;
  for Offset := 0 to Min(Index, 14) do
  begin
    Aux := Legs[Index + 1 - Offset].Bridge.Auxiliary;
    if not Aux.Duet then Continue;
    case Offset of
      0:
        begin
          Reply.Time := Aux.Strike;
          Reply.Power := Aux.StrikePower;
        end;
      1:
        if Aux.Reciprocal then Reply := Aux.SecondStrike else Reply := Aux.Bell;
      2:
        if Aux.Reciprocal then Reply := Aux.Bell else Continue;
      3:
        if Aux.Merge.Active then Reply := Aux.Merge.Launch else Continue;
      4, 5:
        if Aux.Merge.Active then Reply := Aux.Merge.Taps[Offset - 4] else Continue;
      6:
        if Aux.Merge.Pass.Active then Reply := Aux.Merge.Pass.Fork else Continue;
      7, 8:
        if Aux.Merge.Pass.Active then Reply := Aux.Merge.Pass.Taps[Offset - 7] else Continue;
      9:
        if Aux.Merge.Pass.Counter.Active then Reply := Aux.Merge.Pass.Counter.DetourBeat else Continue;
      10, 11:
        if Aux.Merge.Pass.Counter.Active then Reply := Aux.Merge.Pass.Counter.Taps[Offset - 10] else Continue;
      12:
        if Aux.Merge.Pass.Counter.Seesaw.Active then Reply := Aux.Merge.Pass.Counter.Seesaw.Trigger else Continue;
      13:
        if Aux.Merge.Pass.Counter.Seesaw.Active then Reply := Aux.Merge.Pass.Counter.Seesaw.Bell else Continue;
      14:
        if Aux.Merge.Pass.Counter.Seesaw.ExitBell.Time > 0 then Reply := Aux.Merge.Pass.Counter.Seesaw.ExitBell else Continue;
    end;
    if Reply.Time > Time then Continue;
    Beat := Reply;
    Exit(Result + 1);
  end;
end;

function TMarblePlan.Position(Time: Double): TBallPoint;
begin
  if Length(Legs) = 0 then Exit(BallPoint(0, 0.4));
  Result := Legs[CueAt(Time) + 1].Position(Time);
end;

function TMarblePlan.Rotation(Time: Double): Double;
begin
  if Length(Legs) = 0 then Exit(0);
  Result := Legs[CueAt(Time) + 1].Rotation(Time);
end;

function TMarblePlan.CameraTarget(Time: Double): TBallPoint;
const FollowSamples = 10;
      FollowStep = 0.075;
var I, J: Integer; BallY, Offset, Lift, EndOfBoard, Fade, Height: Double;
begin
  Result := Position(Time);
  BallY := Result.Y;
  if Version >= 2 then
  begin
    // 折り返しと受け渡しの急な速度変化を、少しだけ前後の位置でならす。
    Result.X := 0;
    for I := -2 to 2 do Result.X := Result.X + Position(Time + I * 0.065).X * (3 - Abs(I));
    Result.X := Result.X / 9;
  end;
  Result.Y := 0;
  for I := -FollowSamples to FollowSamples do
    Result.Y := Result.Y + Position(Time + I * FollowStep).Y * (FollowSamples + 1 - Abs(I));
  Result.Y := Result.Y / Sqr(FollowSamples + 1);
  if Version >= 2 then
  begin
    // 大きな落下だけ追従を強める。制限に入る点でも速度が急に変わらないようにする。
    Offset := Result.Y - BallY;
    if Abs(Offset) > 0.90 then
      Result.Y := BallY + Sign(Offset) * (0.90 + 0.50 * (1 - Exp((0.90 - Abs(Offset)) / 0.50)));
  end;
  if Version >= 13 then
  begin
    // 発射に先行して少しだけ見上げ、下段の主球も画面に残す。
    J := CueAt(Time + 0.14);
    for I := Min(High(Legs), J + 1) downto Max(0, J - 7) do
      if Legs[I].Motion = mmSeesaw then
      begin
        EndOfBoard := Legs[Min(High(Legs), I + 1)].Finish;
        Fade := 0.60;
        Height := 0.42;
        if (I + 2 <= High(Legs)) and Legs[I + 1].Junction.Active then
        begin
          // 分岐の先で小球が上に残る間も、滑らかに両方を収める。
          EndOfBoard := Legs[I + 2].Finish;
          Fade := 0.85;
          Height := Height + 0.55 * Smooth(EnsureRange((Time - Legs[I + 1].Junction.Branch.Start) / 1.10, 0.0, 1.0));
        end;
        if Time >= EndOfBoard + Fade then Continue;
        Lift := Height * Smooth(EnsureRange((Time - Legs[I].Start + 0.14) / 0.40, 0.0, 1.0)) *
          (1 - Smooth(EnsureRange((Time - EndOfBoard) / Fade, 0.0, 1.0)));
        Result.Y := Result.Y + Min(Lift, Max(0.0, 1.48 - (Result.Y - BallY)));
        Break;
      end;
  end;
end;

function RailTerminalFor(Grade, Drag: Double): Double;
begin
  Result := -RollingFactor * MarbleGravity * Grade / (1 + Sqr(Grade)) / Drag;
end;

end.
