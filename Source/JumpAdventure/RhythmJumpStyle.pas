unit RhythmJumpStyle;
// 共通の準備・保存・プレビュー経路へ新しいジャンプゲームを登録する。
interface
uses RhythmStyleOps;
function JumpOperations:TStyleOperations;

implementation
uses System.SysUtils,System.Hash,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,
  RhythmJumpBuild,RhythmJumpCodec,RhythmJumpPlan,RhythmJumpScene;

function CreateScene:TAnimationScene;
begin
  Result:=TJumpAnimation.Create;
end;

procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin
  TJumpAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin
  TJumpAnimation(Scene).Audio:=Audio;
end;

procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;
  var PreparedEnd:Double;var PreparedSummary:string);
var Plan:TJumpPlan; RestoredAudio:TRhythmAudio; Id:TGUID;
begin
  if Prepared.Generation='' then begin
    // 同じ曲の再準備も別の計画にし、以前の作品が参照する計画を上書きしない。
    if CreateGUID(Id)<>0 then raise Exception.Create('ジャンプ計画の生成IDを作成できません');
    Prepared:=NewPlanRef(Prepared.SourceKey,Prepared.Sensitivity,Prepared.Direction,rsJumpAdventure,
      Prepared.Variant,Prepared.AudioDensity,THashSHA2.GetHashString(GUIDToString(Id)));
  end;
  Prepared.SourceRevision:=Context.Audio.SourceRevision;
  Plan:=BuildJumpPlan(Context.Audio,Prepared.Generation,Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveJumpPlan(Plan,Context.Audio,Prepared);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  RestoredAudio:=LoadJumpAudio(Prepared,Context.Audio.Source,Context.Direction);
  try
    Plan:=LoadJumpPlan(Prepared,RestoredAudio,Context.Direction);
    try
      PreparedEnd:=Plan.Duration;
      PreparedSummary:=Format('横・縦 %d区間 / %dアクセント / ボス %d戦',
        [Length(Plan.Stages),Length(Plan.Beats),Length(Plan.Bosses)]);
    finally
      Plan.Free;
    end;
  finally
    RestoredAudio.Free;
  end;
end;

function JumpOperations:TStyleOperations;
begin
  Result:=Default(TStyleOperations);
  Result.UnitName:='RhythmJumpStyle';
  Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;
  Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadJumpAudio;
  Result.CreateImages:=EmptyStyleImages;
end;
end.
