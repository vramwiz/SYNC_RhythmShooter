unit RhythmRushStyle;
// 格闘ラッシュ専用計画を共通の準備・保存・描画に接続する。
interface
uses RhythmStyleOps;
function RushOperations:TStyleOperations;

implementation
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmAnimation,
  RhythmRushBuild,RhythmRushCodec,RhythmRushPlan,RhythmRushScene;

function CreateScene:TAnimationScene;
begin
  Result:=TRushAnimation.Create;
end;

procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin
  TRushAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin
  TRushAnimation(Scene).Audio:=Audio;
end;

procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;
  var PreparedEnd:Double;var PreparedSummary:string);
var Plan:TRushPlan; Cold:TRhythmAudio; F:TRushFoe; Bosses:Integer;
begin
  Prepared.SourceRevision:=Context.Audio.SourceRevision;
  Plan:=BuildRushPlan(Context.Audio,Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveRushPlan(Plan,Context.Audio,Prepared);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  Cold:=LoadRushAudio(Prepared,Context.Audio.Source,Context.Direction);
  try
    Plan:=LoadRushPlan(Prepared,Cold,Context.Direction);
    try
      Bosses:=0;
      for F in Plan.Foes do if F.Boss then Inc(Bosses);
      PreparedEnd:=Plan.Duration;
      PreparedSummary:=Format('%d区間 / %dアクション / 空中コンボ %d回 / ボス %d戦',
        [Length(Plan.Stages),Length(Plan.Cues),Length(Plan.Arcs),Bosses]);
    finally
      Plan.Free;
    end;
  finally
    Cold.Free;
  end;
end;

function RushOperations:TStyleOperations;
begin
  Result:=Default(TStyleOperations);
  Result.UnitName:='RhythmRushStyle';
  Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;
  Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadRushAudio;
  Result.CreateImages:=EmptyStyleImages;
end;
end.
