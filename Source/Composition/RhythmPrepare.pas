unit RhythmPrepare;
interface
uses System.Classes,RhythmAudio,RhythmStyles,RhythmPlanRef;
type TRhythmPrepareThread=class(TThread)
  private
    FSource:string;FSensitivity,FDirection,FStage,FVariant:Integer;FStyle:TRhythmStyle;FForce:Boolean;FExisting:TRhythmAudio;
    function GetStage:Integer;
  protected
    procedure Execute;override;
  public
    Audio:TRhythmAudio;Plan:TRhythmPlanRef;Error,Summary:string;RequestId:Cardinal;Cancelled:Boolean;PreviewEnd:Double;
    constructor Create(const Source:string;Sensitivity,Direction:Integer;Style:TRhythmStyle;Force:Boolean;Existing:TRhythmAudio;Serial:Cardinal;Variant:Integer=0);
    destructor Destroy;override;
    function TakeAudio:TRhythmAudio;
    property Stage:Integer read GetStage;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,RhythmBallPlan,RhythmFireworksPlan,RhythmRunnerPlan,RhythmBreakoutPlan,RhythmRacePlan,RhythmBombPlan,RhythmFightingPlan,RhythmMiningPlan,RhythmTrainPlan,RhythmNavalPlan;
function TRhythmPrepareThread.GetStage:Integer;begin Result:=InterlockedCompareExchange(FStage,0,0);end;
constructor TRhythmPrepareThread.Create(const Source:string;Sensitivity,Direction:Integer;Style:TRhythmStyle;Force:Boolean;Existing:TRhythmAudio;Serial:Cardinal;Variant:Integer);
begin inherited Create(True);FreeOnTerminate:=False;FSource:=Source;FSensitivity:=Sensitivity;FDirection:=Direction;FVariant:=Variant;FStyle:=Style;FForce:=Force;FExisting:=Existing;RequestId:=Serial;end;
procedure TRhythmPrepareThread.Execute;
var Ball,Verified:TRhythmBallPlan;Fireworks,Checked:TFireworksPlan;RestoredAudio:TRhythmAudio;Runner,RestoredRunner:TRunnerPlan;Breakout,RestoredBreakout:TBreakoutPlan;Race,RestoredRace:TRacePlan;BombAction,RestoredBombAction:TBombActionPlan;Fighting,RestoredFighting:TFightingPlan;Mining,RestoredMining:TMiningPlan;Train,RestoredTrain:TTrainPlan;Naval,RestoredNaval:TNavalPlan;
begin
  try
    if Terminated then Abort;
    InterlockedExchange(FStage,1);
    if not FForce and (FExisting<>nil) and SameFileName(FExisting.Source,ExpandFileName(FSource)) and (FExisting.Sensitivity=FSensitivity) and AudioSourceUnchanged(FExisting) then begin Audio:=FExisting;FExisting:=nil;Audio.CacheReused:=True;end;
    FreeAndNil(FExisting);
    if (Audio=nil) and not FForce then Audio:=LoadCachedRhythmAudio(FSource,FSensitivity);
    if Audio=nil then Audio:=LoadRhythmAudio(FSource,FSensitivity,function:Boolean begin Result:=Terminated;end);
    if Terminated then Abort;
    if FStyle in [rsShooting,rsBreakout,rsRace,rsBombAction,rsFighting,rsMining,rsTrain,rsNaval] then begin Audio.SetBossFrequency(BossFrequencyFromVariant(FVariant));Audio.BossCount;end;
    PreviewEnd:=Audio.Duration;InterlockedExchange(FStage,2);Plan:=NewPlanRef(Audio.Key,FSensitivity,FDirection,FStyle,FVariant);
    if FStyle=rsBall then begin
      Plan.SourceRevision:=Audio.SourceRevision;
      Ball:=TRhythmBallPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);Ball.Save(Plan,function:Boolean begin Result:=Terminated;end);
        if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TRhythmBallPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try Verified:=TRhythmBallPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try Summary:=Format('%d音イベント → %d衝突＋%d共鳴 / 終端外%d',[Verified.PulseCount,Verified.ObstacleCount,Verified.PulseCount-Verified.ObstacleCount,Verified.ExcludedCount]);finally Verified.Free;end;
      finally Ball.Free;end;
    end;
    if FStyle=rsRunner then begin
      Plan.SourceRevision:=Audio.SourceRevision;
      Runner:=TRunnerPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;Runner.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TRunnerPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredRunner:=TRunnerPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try
          PreviewEnd:=Max(Audio.Duration,RestoredRunner.EndTime);
          Summary:=Format('%d音 / 平地%d区間・斬撃%d接触・敵%d体 / 塔%d区間・着地攻撃%d群 / ゴール %.3f秒',[RestoredRunner.PulseCount,RestoredRunner.SwordRunCount,RestoredRunner.CutCount,RestoredRunner.StrikeCount,RestoredRunner.SetPieceCount,RestoredRunner.EncounterCount,RestoredRunner.GoalTime]);
        finally RestoredRunner.Free;end;
      finally Runner.Free;end;
    end;
    if FStyle=rsBreakout then begin
      Plan.SourceRevision:=Audio.SourceRevision;
      Breakout:=TBreakoutPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;Breakout.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TBreakoutPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredBreakout:=TBreakoutPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try
          PreviewEnd:=Max(Audio.Duration,RestoredBreakout.EndTime);
          Summary:=Format('%d音候補 / %dブロック / 音同期%d・補助%d・捕球%d / 全破壊 %.3f 秒',[RestoredBreakout.SourceCount,RestoredBreakout.Count,RestoredBreakout.ReflectionCount,RestoredBreakout.AuxiliaryCount,RestoredBreakout.CatchCount,RestoredBreakout.GoalTime]);
            Summary:=Summary+Format(' / 見せ場%d・追加球%d',[RestoredBreakout.ItemCount,RestoredBreakout.ExtraCount]);
            if RestoredBreakout.Campaign<>nil then Summary:=Summary+Format('・ボス%d（候補%d）',[RestoredBreakout.BossCount,RestoredBreakout.Campaign.CandidateCount])
            else Summary:=Summary+Format('・ボス%d',[RestoredBreakout.BossCount]);
        finally RestoredBreakout.Free;end;
      finally Breakout.Free;end;
    end;
    if FStyle=rsRace then begin
      Plan.SourceRevision:=Audio.SourceRevision;Race:=TRacePlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;Race.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TRacePlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredRace:=TRacePlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try
          PreviewEnd:=Max(Audio.Duration,RestoredRace.EndTime);
          Summary:=Format('%d候補 → %dコイン取得 / 採用外%d / ゴール %.3f秒 / 終了 %.3f秒',[Length(Audio.Hits),RestoredRace.Count,RestoredRace.Excluded,RestoredRace.GoalTime,RestoredRace.EndTime]);
          Summary:=Summary+Format(' / 妨害車%d・トレーラー%d・爆弾%d',[RestoredRace.TrafficCount,RestoredRace.TrailerCount,RestoredRace.BombCount]);Summary:=Summary+Format(' / 総得点%d',[RestoredRace.MaxScore]);
        finally RestoredRace.Free;end;
      finally Race.Free;end;
    end;
    if FStyle=rsBombAction then begin
      Plan.SourceRevision:=Audio.SourceRevision;BombAction:=TBombActionPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;BombAction.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TBombActionPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredBombAction:=TBombActionPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try PreviewEnd:=Max(Audio.Duration,RestoredBombAction.EndTime);
          Summary:=Format('%d音候補 → 爆発%d・連鎖%d・破壊%d・ボス%d・攻撃弾%d / 採用外%d',[Length(Audio.Hits),RestoredBombAction.Count+RestoredBombAction.ChargeCount,RestoredBombAction.ChainCount,RestoredBombAction.TargetCount+RestoredBombAction.CrowdDestroyed(RestoredBombAction.EndTime),RestoredBombAction.BossCount,RestoredBombAction.ShotCount+RestoredBombAction.RaidCount,RestoredBombAction.Excluded]);
        finally RestoredBombAction.Free;end;
      finally BombAction.Free;end;
    end;
    if FStyle=rsFighting then begin
      Plan.SourceRevision:=Audio.SourceRevision;Fighting:=TFightingPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;Fighting.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TFightingPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredFighting:=TFightingPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try PreviewEnd:=Max(Audio.Duration,RestoredFighting.EndTime);
          Summary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredFighting.PulseCount,RestoredFighting.Count,RestoredFighting.BossCount,RestoredFighting.EndTime]);
        finally RestoredFighting.Free;end;
      finally Fighting.Free;end;
    end;
    if FStyle=rsMining then begin
      Plan.SourceRevision:=Audio.SourceRevision;Mining:=TMiningPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;Mining.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TMiningPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredMining:=TMiningPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try PreviewEnd:=Max(Audio.Duration,RestoredMining.EndTime);
          Summary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredMining.PulseCount,RestoredMining.Count,RestoredMining.BossCount,RestoredMining.EndTime]);
        finally RestoredMining.Free;end;
      finally Mining.Free;end;
    end;
    if FStyle=rsTrain then begin
      Plan.SourceRevision:=Audio.SourceRevision;Train:=TTrainPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;Train.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TTrainPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredTrain:=TTrainPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try PreviewEnd:=Max(Audio.Duration,RestoredTrain.EndTime);
          Summary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredTrain.PulseCount,RestoredTrain.Count,RestoredTrain.BossCount,RestoredTrain.EndTime]);
        finally RestoredTrain.Free;end;
      finally Train.Free;end;
    end;
    if FStyle=rsNaval then begin
      Plan.SourceRevision:=Audio.SourceRevision;Naval:=TNavalPlan.Build(Audio,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);if Terminated then Abort;Naval.Save(Plan,Audio);if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TNavalPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try RestoredNaval:=TNavalPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try PreviewEnd:=Max(Audio.Duration,RestoredNaval.EndTime);
          Summary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredNaval.PulseCount,RestoredNaval.Count,RestoredNaval.BossCount,RestoredNaval.EndTime]);
        finally RestoredNaval.Free;end;
      finally Naval.Free;end;
    end;
    if FStyle=rsFireworks then begin
      Plan.SourceRevision:=Audio.SourceRevision;
      Fireworks:=TFireworksPlan.Build(Audio,FDirection,FVariant,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);Fireworks.Save(Plan,function:Boolean begin Result:=Terminated;end);
        if Terminated then Abort;
        InterlockedExchange(FStage,4);RestoredAudio:=TFireworksPlan.LoadAudioMetadata(Plan,Audio.Source,FDirection);
        try Checked:=TFireworksPlan.Load(Plan,RestoredAudio,FDirection);finally RestoredAudio.Free;end;
        try if Checked.EndTime>PreviewEnd then PreviewEnd:=Checked.EndTime;Summary:=Format('%d音 → %d開花 / 華やかさ%d / 終端外%d',[Checked.SourceEventCount,Checked.Count,Checked.Richness,Checked.ExcludedCount]);finally Checked.Free;end;
      finally Fireworks.Free;end;
    end;
    if FStyle=rsShooting then Summary:=IntToStr(Length(Audio.Hits))+'イベント / ボス'+IntToStr(Audio.BossCount)+' / '+BossFrequencyText(Audio.BossFrequency);
    if Terminated then Abort;
  except on E:Exception do begin
    Cancelled:=Terminated;
    if Cancelled then Error:='準備を中止しました。'
    else Error:=Format('準備失敗（段階%d）: %s: %s',[GetStage,E.ClassName,E.Message]);
    // Decoded audio stays available for a plan-only retry. It is never treated
    // as a valid animation without a matching, read-back-verified plan.
    if Cancelled or (GetStage<2) then FreeAndNil(Audio);
    Plan:=Default(TRhythmPlanRef);
  end;end;
end;
destructor TRhythmPrepareThread.Destroy;
begin
  // TThread.Destroy terminates and joins even a never-started suspended thread.
  // Keep its source data alive until the base destructor has finished joining.
  inherited Destroy;FExisting.Free;Audio.Free;
end;
function TRhythmPrepareThread.TakeAudio:TRhythmAudio;begin Result:=Audio;Audio:=nil;end;
end.
