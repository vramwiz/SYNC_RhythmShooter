unit RhythmParkourStyle;
// パルクール試作を共通の準備・描画・ホスト復元へ登録する。
interface

uses RhythmStyleOps;

function ParkourOperations: TStyleOperations;

implementation

uses System.SysUtils, RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmEqualizer,
  RhythmParkourPlan, RhythmParkourScene;

function CreateScene: TAnimationScene;
begin
  Result := TParkourAnimation.Create;
end;

procedure SetReference(Scene: TAnimationScene; const Ref: TRhythmPlanRef);
begin
  TParkourAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene: TAnimationScene; Audio: TRhythmAudio; BossFrequency: Integer);
begin
  TParkourAnimation(Scene).Audio := Audio;
end;

function Activity(Scene: TAnimationScene; Time: Double; out Value: TEqualizerActivity): Boolean;
begin
  Result := TParkourAnimation(Scene).Activity(Time, Value);
end;

procedure Prepare(const Context: TStylePrepareContext; var Ref: TRhythmPlanRef;
  var PreparedEnd: Double; var PreparedSummary: string);
var Plan: TParkourPlan; Restored: TRhythmAudio; Move: TParkourMove;
  Counts: array[TParkourKind] of Integer;
begin
  Ref.SourceRevision := Context.Audio.SourceRevision;
  Plan := BuildParkourPlan(Context.Audio, Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveParkourPlan(Plan, Context.Audio, Ref);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  Restored := LoadParkourAudio(Ref, Context.Audio.Source, Context.Direction);
  try
    Plan := LoadParkourPlan(Ref, Restored, Context.Direction);
    try
      FillChar(Counts, SizeOf(Counts), 0);
      for Move in Plan.Moves do Inc(Counts[Move.Kind]);
      PreparedEnd := Plan.Duration;
      PreparedSummary := Format('連続ステップ %d / 壁走り %d / ワイヤー %d / その他 %d',
        [Counts[pkStride], Counts[pkWallRun], Counts[pkWire], Counts[pkVault] + Counts[pkWall] + Counts[pkDrop]]);
    finally
      Plan.Free;
    end;
  finally
    Restored.Free;
  end;
end;

function ParkourOperations: TStyleOperations;
begin
  Result := Default(TStyleOperations);
  Result.UnitName := 'RhythmParkourStyle';
  Result.CreateScene := CreateScene;
  Result.SetReference := SetReference;
  Result.SetAudio := SetAudio;
  Result.Prepare := Prepare;
  Result.LoadAudio := LoadParkourAudio;
  Result.CreateImages := EmptyStyleImages;
  Result.Activity := Activity;
end;

end.
