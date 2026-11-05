unit RhythmSideRaceStyle;
// 2Dハイウェイを既存の音声準備、保存、プレビューへ接続する。
interface
uses RhythmStyleOps;
function SideRaceOperations:TStyleOperations;

implementation
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmAnimation,
  RhythmSideRaceBuild,RhythmSideRaceCodec,RhythmSideRacePlan,RhythmSideRaceScene;

function CreateScene:TAnimationScene;
begin
  Result:=TSideRaceAnimation.Create;
end;

procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin
  TSideRaceAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin
  TSideRaceAnimation(Scene).Audio:=Audio;
end;

procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;
  var PreparedEnd:Double;var PreparedSummary:string);
var Plan:TSideRacePlan; Cold:TRhythmAudio;
begin
  Prepared.SourceRevision:=Context.Audio.SourceRevision;
  Plan:=BuildSideRace(Context.Audio,Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveSideRace(Plan,Context.Audio,Prepared);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  Cold:=LoadSideRaceAudio(Prepared,Context.Audio.Source,Context.Direction);
  try
    Plan:=LoadSideRace(Prepared,Cold,Context.Direction);
    try
      PreparedEnd:=Plan.Duration;
      PreparedSummary:=Format('%d音 / ジャンプ%d回 / 敵車%d台 / ボス%d戦 / ゴール %.2f秒',
        [Length(Plan.Cues),Length(Plan.Jumps),Length(Plan.Cars),Length(Plan.Bosses),Plan.Goal]);
    finally
      Plan.Free;
    end;
  finally
    Cold.Free;
  end;
end;

function SideRaceOperations:TStyleOperations;
begin
  Result:=Default(TStyleOperations);
  Result.UnitName:='RhythmSideRaceStyle';
  Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;
  Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadSideRaceAudio;
  Result.CreateImages:=EmptyStyleImages;
end;
end.
