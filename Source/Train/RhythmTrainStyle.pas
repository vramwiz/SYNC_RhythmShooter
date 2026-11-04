unit RhythmTrainStyle;
// 列車専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function TrainOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmTrainScene,RhythmTrainPlan;
function CreateScene:TAnimationScene;
begin Result:=TTrainAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TTrainAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TTrainAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TTrainPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Train,RestoredTrain:TTrainPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Train:=TTrainPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Train.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TTrainPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredTrain:=TTrainPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try PreparedEnd:=Max(Context.Audio.Duration,RestoredTrain.EndTime);
          PreparedSummary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredTrain.PulseCount,RestoredTrain.Count,RestoredTrain.BossCount,RestoredTrain.EndTime]);
        finally RestoredTrain.Free;
        end;
      finally Train.Free;
      end;
end;
function TrainOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmTrainStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
