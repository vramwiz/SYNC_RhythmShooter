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
uses System.SysUtils,System.Math,Winapi.Windows,RhythmBallPlan,RhythmFireworksPlan,RhythmRunnerPlan;
function TRhythmPrepareThread.GetStage:Integer;begin Result:=InterlockedCompareExchange(FStage,0,0);end;
constructor TRhythmPrepareThread.Create(const Source:string;Sensitivity,Direction:Integer;Style:TRhythmStyle;Force:Boolean;Existing:TRhythmAudio;Serial:Cardinal;Variant:Integer);
begin inherited Create(True);FreeOnTerminate:=False;FSource:=Source;FSensitivity:=Sensitivity;FDirection:=Direction;FVariant:=Variant;FStyle:=Style;FForce:=Force;FExisting:=Existing;RequestId:=Serial;end;
procedure TRhythmPrepareThread.Execute;
var Ball,Verified:TRhythmBallPlan;Fireworks,Checked:TFireworksPlan;RestoredAudio:TRhythmAudio;Runner,RestoredRunner:TRunnerPlan;
begin
  try
    if Terminated then Abort;
    InterlockedExchange(FStage,1);
    if not FForce and (FExisting<>nil) and SameFileName(FExisting.Source,ExpandFileName(FSource)) and (FExisting.Sensitivity=FSensitivity) and AudioSourceUnchanged(FExisting) then begin Audio:=FExisting;FExisting:=nil;Audio.CacheReused:=True;end;
    FreeAndNil(FExisting);
    if (Audio=nil) and not FForce then Audio:=LoadCachedRhythmAudio(FSource,FSensitivity);
    if Audio=nil then Audio:=LoadRhythmAudio(FSource,FSensitivity,function:Boolean begin Result:=Terminated;end);
    if Terminated then Abort;
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
          Summary:=Format('%d音 / %d着地点 / ゴール %.3f 秒',[RestoredRunner.PulseCount,RestoredRunner.Count,RestoredRunner.GoalTime]);
        finally RestoredRunner.Free;end;
      finally Runner.Free;end;
    end;
    if FStyle=rsFireworks then begin
      Fireworks:=TFireworksPlan.Build(Audio,FDirection,FVariant,function:Boolean begin Result:=Terminated;end);
      try
        InterlockedExchange(FStage,3);Fireworks.Save(Plan,function:Boolean begin Result:=Terminated;end);
        if Terminated then Abort;
        InterlockedExchange(FStage,4);Checked:=TFireworksPlan.Load(Plan,Audio,FDirection);
        try if Checked.EndTime>PreviewEnd then PreviewEnd:=Checked.EndTime;Summary:=Format('%d音 → %d開花 / 華やかさ%d / 終端外%d',[Checked.SourceEventCount,Checked.Count,Checked.Richness,Checked.ExcludedCount]);finally Checked.Free;end;
      finally Fireworks.Free;end;
    end;
    if FStyle=rsShooting then Summary:=IntToStr(Length(Audio.Hits))+'イベント';
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
