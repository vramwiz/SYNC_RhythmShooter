unit RhythmRobotStyle;
// ロボット大戦を既存の種類選択・準備スレッド・プレビュー・DLL復元へ登録する。
interface

uses RhythmStyleOps;

function RobotOperations: TStyleOperations;

implementation

uses System.SysUtils, RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmEqualizer,
  RhythmRobotPlan, RhythmRobotCodec, RhythmRobotScene;

function CreateScene: TAnimationScene;
begin
  Result := TRobotAnimation.Create;
end;

procedure SetReference(Scene: TAnimationScene; const Ref: TRhythmPlanRef);
begin
  TRobotAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene: TAnimationScene; Audio: TRhythmAudio; BossFrequency: Integer);
begin
  TRobotAnimation(Scene).Audio := Audio;
end;

function Activity(Scene: TAnimationScene; Time: Double; out Value: TEqualizerActivity): Boolean;
begin
  Result := TRobotAnimation(Scene).Activity(Time, Value);
end;

procedure Prepare(const Context: TStylePrepareContext; var Ref: TRhythmPlanRef;
  var PreparedEnd: Double; var PreparedSummary: string);
var Plan: TRobotPlan; Restored: TRhythmAudio;
begin
  Ref.SourceRevision := Context.Audio.SourceRevision;
  Plan := BuildRobotPlan(Context.Audio, Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveRobotPlan(Plan, Context.Audio, Ref);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  Restored := LoadRobotAudio(Ref, Context.Audio.Source, Context.Direction);
  try
    Plan := LoadRobotPlan(Ref, Restored, Context.Direction);
    try
      PreparedEnd := Plan.Duration;
      PreparedSummary := Format('敵味方の変形・2体/3体合体 / 戦闘 %d音 / 勝利まで28場面', [Length(Plan.Cues)]);
    finally
      Plan.Free;
    end;
  finally
    Restored.Free;
  end;
end;

function RobotOperations: TStyleOperations;
begin
  Result := Default(TStyleOperations);
  Result.UnitName := 'RhythmRobotStyle';
  Result.CreateScene := CreateScene;
  Result.SetReference := SetReference;
  Result.SetAudio := SetAudio;
  Result.Prepare := Prepare;
  Result.LoadAudio := LoadRobotAudio;
  Result.CreateImages := EmptyStyleImages;
  Result.Activity := Activity;
end;

end.
