unit RhythmStepStyle;
// 設定・準備・ホスト描画を4レーン譜面へ接続する。
interface
uses RhythmStyleOps;
function StepOperations:TStyleOperations;

implementation
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmAnimation,RhythmEqualizer,
  RhythmOrbitAudio,RhythmStepPlan,RhythmStepScene;

function CreateScene:TAnimationScene;
begin
  Result:=TStepAnimation.Create;
end;

procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin
  TStepAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin
  TStepAnimation(Scene).Audio:=Audio;
end;

function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin
  Result:=TStepPlan.LoadAudioMetadata(Ref,Source,Direction);
end;

procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Source,Cold:TRhythmAudio;Plan:TStepPlan;Stats:TOrbitAudioStats;Threshold:Integer;
begin
  Threshold:=Context.Variant-101;
  Source:=PrepareOrbitAudio(Context.Audio,Threshold,Stats,Context.Cancel);
  try
    Plan:=TStepPlan.Build(Source,Threshold,Context.Cancel);
    try
      Context.SetStage(3);
      Context.CheckCancel;
      Plan.Save(Prepared,Source);
    finally
      Plan.Free;
    end;
    Context.SetStage(4);
    Context.CheckCancel;
    Cold:=LoadAudio(Prepared,Source.Source,Context.Direction);
    try
      PreparedEnd:=Cold.Duration;
      PreparedSummary:=Format('%d拍 / 4レーン / %.3f秒',[Length(Cold.Hits),PreparedEnd]);
    finally
      Cold.Free;
    end;
  finally
    Source.Free;
  end;
end;

function Activity(Scene:TAnimationScene;Time:Double;out Value:TEqualizerActivity):Boolean;
begin
  Result:=TStepAnimation(Scene).TryActivity(Time,Value);
end;

function StepOperations:TStyleOperations;
begin
  Result:=Default(TStyleOperations);
  Result.UnitName:='RhythmStepStyle';
  Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;
  Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;
  Result.CreateImages:=EmptyStyleImages;
  Result.Activity:=Activity;
end;
end.
