unit RhythmRunnerStyle;
// ランナー専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function RunnerOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmRunnerScene,RhythmRunnerPlan,RhythmRunnerAction;
function CreateScene:TAnimationScene;
begin Result:=TRunnerAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TRunnerAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TRunnerAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TRunnerPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Runner,RestoredRunner:TRunnerPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Runner:=TRunnerPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Runner.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TRunnerPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredRunner:=TRunnerPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try
          PreparedEnd:=Max(Context.Audio.Duration,RestoredRunner.EndTime);
          PreparedSummary:=Format('A jump %d / B sword %d / C boss %d / %d accents / %.3fs',[RestoredRunner.Action.ModeCount(rmJump),RestoredRunner.Action.ModeCount(rmSword),RestoredRunner.Action.ModeCount(rmBoss),RestoredRunner.PulseCount,RestoredRunner.GoalTime]);
        finally RestoredRunner.Free;
        end;
      finally Runner.Free;
      end;
end;
function RunnerOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmRunnerStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
