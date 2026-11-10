unit RhythmMarbleStyle;
// からくりリレーの準備、保存後の照合、プレビューとホスト再生を接続する。
interface

uses RhythmStyleOps;

function MarbleOperations: TStyleOperations;

implementation

uses System.SysUtils, RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmEqualizer,
  RhythmMarblePlan, RhythmMarbleScene, RhythmStyles;

function CreateScene: TAnimationScene;
begin
  Result := TMarbleAnimation.Create;
end;

procedure SetReference(Scene: TAnimationScene; const Ref: TRhythmPlanRef);
begin
  TMarbleAnimation(Scene).SetReference(Ref);
end;

procedure SetAudio(Scene: TAnimationScene; Audio: TRhythmAudio; BossFrequency: Integer);
begin
  TMarbleAnimation(Scene).Audio := Audio;
end;

procedure SetAppearance(Scene: TAnimationScene; Ball: TMarbleBallStyle; Stage: TMarbleStageStyle);
begin
  TMarbleAnimation(Scene).BallStyle := Ball;
  TMarbleAnimation(Scene).StageStyle := Stage;
end;

function Activity(Scene: TAnimationScene; Time: Double; out Value: TEqualizerActivity): Boolean;
begin
  Result := TMarbleAnimation(Scene).Activity(Time, Value);
end;

procedure Prepare(const Context: TStylePrepareContext; var Ref: TRhythmPlanRef;
  var PreparedEnd: Double; var PreparedSummary: string);
var Plan: TMarblePlan; Restored: TRhythmAudio; Cue: TMarbleCue; Link: TMarbleLink; Leg: TMarbleLeg;
  Turns, Transfers, Chains, Bridges, Auxiliary, Duets, Reciprocal, Crossovers, Merges, Passes, Counters, Interlocks, Seesaws, WeightedLifts, TrayReleases, Junctions, WheelBells: Integer;
begin
  Ref.SourceRevision := Context.Audio.SourceRevision;
  Plan := BuildMarblePlan(Context.Audio, Context.Cancel);
  try
    Context.CheckCancel;
    Context.SetStage(3);
    SaveMarblePlan(Plan, Context.Audio, Ref);
  finally
    Plan.Free;
  end;
  Context.CheckCancel;
  Context.SetStage(4);
  Restored := LoadMarbleAudio(Ref, Context.Audio.Source, Context.Direction);
  try
    Plan := LoadMarblePlan(Ref, Restored, Context.Direction);
    try
      Turns := 0;
      Transfers := 0;
      Chains := 0;
      Bridges := 0;
      Auxiliary := 0;
      Duets := 0;
      Reciprocal := 0;
      Crossovers := 0;
      Merges := 0;
      Passes := 0;
      Counters := 0;
      Interlocks := 0;
      Seesaws := 0;
      WeightedLifts := 0;
      TrayReleases := 0;
      Junctions := 0;
      WheelBells := 0;
      for Cue in Plan.Cues do
      begin
        if Cue.Device = mdBend then Inc(Turns);
        if Cue.Device in [mdLift, mdShuttle, mdSwing, mdChute] then Inc(Transfers);
      end;
      for Link in Plan.Links do
        if Link.Kind <> mlNone then Inc(Chains);
      for Leg in Plan.Legs do
      begin
        if Leg.Bridge.Auxiliary.Active then Inc(Auxiliary)
        else if Leg.Bridge.Active then Inc(Bridges);
        if Leg.Bridge.Auxiliary.Duet then Inc(Duets);
        if Leg.Bridge.Auxiliary.Reciprocal then Inc(Reciprocal);
        if Leg.Bridge.Auxiliary.Crossover then Inc(Crossovers);
        if Leg.Bridge.Auxiliary.Merge.Active then Inc(Merges);
        if Leg.Bridge.Auxiliary.Merge.Pass.Active then Inc(Passes);
        if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Active then Inc(Counters);
        if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Interlock.Active then Inc(Interlocks);
        if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.Active then Inc(Seesaws);
        if Leg.HasWeightLift then Inc(WeightedLifts);
        if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.TrayRelease.Active then Inc(TrayReleases);
        if Leg.Junction.Active then Inc(Junctions);
        if Leg.Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.ExitBell.Time > 0 then Inc(WheelBells);
      end;
      PreparedEnd := Plan.EndTime;
      PreparedSummary := Format('接触 %d / 連鎖 %d（3段 %d・小球橋 %d・交互 %d・相互 %d・上下交代 %d・合流 %d・追い越し %d・追い越し返し %d・両レバー %d・シーソー %d・着地リフト %d・受け皿のレバー %d・回転分岐 %d・羽根車の鐘 %d）/ 折り返し %d / 昇降・移送 %d',
        [Length(Plan.Cues) + (Duets + Seesaws) * 2 + Reciprocal + (Merges + Passes + Counters) * 3 + WheelBells,
         Chains + Reciprocal * 2 + Merges + Passes + Counters + Interlocks + Seesaws + TrayReleases + Junctions + WheelBells,
         Bridges - Reciprocal - Merges, Auxiliary, Duets - Reciprocal, Reciprocal - Crossovers,
         Crossovers - Merges, Merges - Passes, Passes - Counters, Counters - Interlocks,
         Interlocks - Seesaws, Seesaws - WeightedLifts, WeightedLifts - TrayReleases, TrayReleases, Junctions, WheelBells, Turns, Transfers]);
    finally
      Plan.Free;
    end;
  finally
    Restored.Free;
  end;
end;

function MarbleOperations: TStyleOperations;
begin
  Result := Default(TStyleOperations);
  Result.UnitName := 'RhythmMarbleStyle';
  Result.CreateScene := CreateScene;
  Result.SetReference := SetReference;
  Result.SetAudio := SetAudio;
  Result.Prepare := Prepare;
  Result.LoadAudio := LoadMarbleAudio;
  Result.CreateImages := CreateMarbleImages;
  Result.Activity := Activity;
  Result.MarbleAppearance := SetAppearance;
end;

end.
