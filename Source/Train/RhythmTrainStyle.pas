unit RhythmTrainStyle;
// 列車アクションの準備・保存・復元を設定画面と共通レンダラーへ接続する。
interface
uses RhythmStyleOps;
function TrainOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmPlanRef,RhythmAnimation,RhythmImageBank,
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
          PreparedSummary:=Format('列車アクション: %d動作 / 音同期%d / 終了 %.2f秒',[RestoredTrain.Count,RestoredTrain.Synced,RestoredTrain.EndTime]);
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
