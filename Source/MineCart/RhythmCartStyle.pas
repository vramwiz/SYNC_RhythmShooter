unit RhythmCartStyle;
// トロッコの計画と描画を、共通の準備・保存・ホスト再生につなぐ。
interface
uses RhythmStyleOps;
function CartOperations:TStyleOperations;

implementation
uses System.SysUtils,RhythmAnimation,RhythmAudio,RhythmPlanRef,RhythmCartPlan,
  RhythmCartBuild,RhythmCartCodec,RhythmCartScene;

function CreateScene:TAnimationScene;
begin
  Result:=TCartAnimation.Create;
end;

procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin
  TCartAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin
  TCartAnimation(Scene).Audio:=Audio;
end;

procedure Prepare(const Context:TStylePrepareContext;var Ref:TRhythmPlanRef;
  var PreparedEnd:Double;var PreparedSummary:string);
var Plan:TCartPlan; Restored:TRhythmAudio;
begin
  Ref.SourceRevision:=Context.Audio.SourceRevision;
  Plan:=BuildCartPlan(Context.Audio,Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveCartPlan(Plan,Context.Audio,Ref);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  Restored:=LoadCartAudio(Ref,Context.Audio.Source,Context.Direction);
  try
    Plan:=LoadCartPlan(Ref,Restored,Context.Direction);
    try
      PreparedEnd:=Plan.Duration;
      PreparedSummary:=Format('コイン %d枚 / ギミック %d箇所 / 連結ボス %d戦',
        [Length(Plan.Coins),Length(Plan.Moves),Length(Plan.Bosses)]);
    finally
      Plan.Free;
    end;
  finally
    Restored.Free;
  end;
end;

function CartOperations:TStyleOperations;
begin
  Result:=Default(TStyleOperations);
  Result.UnitName:='RhythmCartStyle';
  Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;
  Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadCartAudio;
  Result.CreateImages:=EmptyStyleImages;
end;
end.
