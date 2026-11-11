unit RhythmStyleRegistry;
// 実装への分岐はここだけで登録。UI/Renderer/準備/ホスト復元は同じOpsを参照する。
interface
uses RhythmStyles,RhythmStyleOps,RhythmAudio,RhythmPlanRef;
function StyleOperations(Style:TRhythmStyle):TStyleOperations;
function LoadStyleAudio(Style:TRhythmStyle;const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
implementation
uses System.SysUtils,RhythmShootingStyle,RhythmBallStyle,RhythmBreakoutStyle,RhythmBombActionStyle,RhythmMiningStyle,RhythmTrainStyle,RhythmGameStyle,RhythmStepStyle,RhythmJumpStyle,RhythmRushStyle,RhythmSideRaceStyle,RhythmCartStyle,RhythmCannonStyle,RhythmParkourStyle,RhythmMarbleStyle,RhythmRobotStyle;
type TOperationsFactory=function:TStyleOperations;
const Factories:array[TRhythmStyle] of TOperationsFactory=(
  ShootingOperations,
  BallOperations,
  JumpOperations,
  BreakoutOperations,
  SideRaceOperations,
  BombActionOperations,
  RushOperations,
  MiningOperations,
  TrainOperations,
  GameOperations,
  StepOperations,
  CartOperations,
  CannonOperations,
  ParkourOperations,
  MarbleOperations,
  RobotOperations
);
function StyleOperations(Style:TRhythmStyle):TStyleOperations;
begin Result:=Factories[Style]();
  if not Assigned(Result.CreateScene) or not Assigned(Result.SetReference) or not Assigned(Result.SetAudio) or
    not Assigned(Result.Prepare) or not Assigned(Result.LoadAudio) or not Assigned(Result.CreateImages) then
    raise EArgumentException.Create('Incomplete style registration: '+StyleId(Style));
end;
function LoadStyleAudio(Style:TRhythmStyle;const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Ops:TStyleOperations;
begin Ops:=StyleOperations(Style);Result:=Ops.LoadAudio(Ref,Source,Direction);end;
end.
