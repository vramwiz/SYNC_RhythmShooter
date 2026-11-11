unit RhythmTrapStyle;
// 共通の準備・保存・プレビュー・ホストへ、独立した罠アクションを登録する。
interface
uses RhythmStyleOps;
function TrapOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAnimation,RhythmAudio,RhythmPlanRef,RhythmStyles,
  RhythmTrapPlan,RhythmTrapBuild,RhythmTrapCodec,RhythmTrapScene;
function CreateScene:TAnimationScene;
begin Result:=TTrapAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TTrapAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TTrapAnimation(Scene).Audio:=Audio;end;
procedure Prepare(const Context:TStylePrepareContext;var Ref:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Plan:TTrapPlan;Restored:TRhythmAudio;
begin
  if not InRange(Context.Variant,1,8) then raise EArgumentException.Create('ステージが不正です');
  Ref.SourceRevision:=Context.Audio.SourceRevision;
  Plan:=BuildTrapPlan(Context.Audio,TTrapStage(Context.Variant-1),Context.Cancel);
  try Context.CheckCancel;Context.SetStage(3);SaveTrapPlan(Plan,Context.Audio,Ref);finally Plan.Free;end;
  Context.CheckCancel;Context.SetStage(4);Restored:=LoadTrapAudio(Ref,Context.Audio.Source,Context.Direction);
  try Plan:=LoadTrapPlan(Ref,Restored,Context.Direction);
    try PreparedEnd:=Plan.Duration;PreparedSummary:=Format('%s / %d動作・%dの罠 / 回避距離検証済み',
      [TrapStageTitles[Plan.Theme],Length(Plan.Moves),Length(Plan.Obstacles)]);finally Plan.Free;end;
  finally Restored.Free;end;
end;
function TrapOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmTrapStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadTrapAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
