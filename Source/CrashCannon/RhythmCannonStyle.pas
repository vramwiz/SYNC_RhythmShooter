unit RhythmCannonStyle;
// クラッシュキャノンを共通の設定・準備・描画・ホスト復元につなぐ。
interface

uses RhythmStyleOps;

function CannonOperations:TStyleOperations;

implementation

uses System.SysUtils,RhythmAnimation,RhythmAudio,RhythmPlanRef,RhythmEqualizer,
  RhythmCannonPlan,RhythmCannonBuild,RhythmCannonCodec,RhythmCannonScene;

function CreateScene:TAnimationScene;
begin
  Result:=TCannonAnimation.Create;
end;

procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin
  TCannonAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin
  TCannonAnimation(Scene).Audio:=Audio;
end;

function Activity(Scene:TAnimationScene;Time:Double;out Value:TEqualizerActivity):Boolean;
begin
  Result:=TCannonAnimation(Scene).Activity(Time,Value);
end;

procedure Prepare(const Context:TStylePrepareContext;var Ref:TRhythmPlanRef;
  var PreparedEnd:Double;var PreparedSummary:string);
var Plan:TCannonPlan; Cold:TRhythmAudio; Stage:TCannonStage; Cue:TCannonCue;
  Stages,Hits,Bosses:Integer;
begin
  Ref.SourceRevision:=Context.Audio.SourceRevision;
  Plan:=BuildCannonPlan(Context.Audio,Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveCannonPlan(Plan,Context.Audio,Ref);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  Cold:=LoadCannonAudio(Ref,Context.Audio.Source,Context.Direction);
  try
    Plan:=LoadCannonPlan(Ref,Cold,Context.Direction);
    try
      Stages:=0;
      Hits:=0;
      Bosses:=0;
      for Stage in Plan.Stages do begin
        if Length(Stage.Cues)=0 then Continue;
        Inc(Stages);
        if CannonBoss(Stage.Kind) then Inc(Bosses);
        for Cue in Stage.Cues do
          if Cue.Enemy=ceNone then Inc(Hits);
      end;
      PreparedEnd:=Plan.Duration;
      PreparedSummary:=Format('%dステージ / 着弾 %d回 / ボス %d戦',[Stages,Hits,Bosses]);
    finally
      Plan.Free;
    end;
  finally
    Cold.Free;
  end;
end;

function CannonOperations:TStyleOperations;
begin
  Result:=Default(TStyleOperations);
  Result.UnitName:='RhythmCannonStyle';
  Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;
  Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadCannonAudio;
  Result.CreateImages:=EmptyStyleImages;
  Result.Activity:=Activity;
end;
end.
