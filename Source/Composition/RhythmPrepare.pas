unit RhythmPrepare;
// 設定画面から起動する全曲準備。解析・スタイル計画・保存後の再読込検証を接続する。
interface
uses System.Classes,RhythmAudio,RhythmStyles,RhythmPlanRef;
type
  TRhythmPrepareThread=class(TThread)
  private
    FSource:string;
    FSensitivity,FDirection,FStage,FVariant:Integer;
    FStyle:TRhythmStyle;
    FForce:Boolean;
    FExisting:TRhythmAudio;
  public
    Audio:TRhythmAudio;
    Plan:TRhythmPlanRef;
    Error,Summary:string;
    RequestId:Cardinal;
    Cancelled:Boolean;
    PreviewEnd:Double;
  private
    function GetStage:Integer;
    procedure BuildPlan(Style:TRhythmStyle;Variant:Integer;out Prepared:TRhythmPlanRef;out PreparedEnd:Double;out PreparedSummary:string);
  protected
    procedure Execute; override;
  public
    constructor Create(const Source:string;Sensitivity,Direction:Integer;Style:TRhythmStyle;Force:Boolean;Existing:TRhythmAudio;Serial:Cardinal;Variant:Integer=0);
    destructor Destroy; override;
    function TakeAudio:TRhythmAudio;
    property Stage:Integer read GetStage;
  end;
implementation
uses System.SysUtils,Winapi.Windows,RhythmStyleOps,RhythmStyleRegistry;

function TRhythmPrepareThread.GetStage:Integer;
begin Result:=InterlockedCompareExchange(FStage,0,0);
end;

constructor TRhythmPrepareThread.Create(const Source:string;Sensitivity,Direction:Integer;Style:TRhythmStyle;Force:Boolean;Existing:TRhythmAudio;Serial:Cardinal;Variant:Integer);
begin inherited Create(True);
  FreeOnTerminate:=False;
  FSource:=Source;
  FSensitivity:=Sensitivity;
  FDirection:=Direction;
  FVariant:=Variant;
  FStyle:=Style;
  FForce:=Force;
  FExisting:=Existing;
  RequestId:=Serial;
end;

procedure TRhythmPrepareThread.BuildPlan(Style:TRhythmStyle;Variant:Integer;out Prepared:TRhythmPlanRef;out PreparedEnd:Double;out PreparedSummary:string);
var Context:TStylePrepareContext;Ops:TStyleOperations;
begin
  if StyleHas(Style,sfBoss) then begin Audio.SetBossFrequency(BossFrequencyFromVariant(Variant));Audio.BossCount;end;
  Context.Audio:=Audio;Context.Direction:=FDirection;Context.Variant:=Variant;
  Context.Cancel:=function:Boolean begin Result:=Terminated;end;
  Context.Progress:=procedure(Value:Integer) begin InterlockedExchange(FStage,Value);end;
  Context.SetStage(2);PreparedEnd:=Audio.Duration;PreparedSummary:='';
  Prepared:=NewPlanRef(Audio.Key,FSensitivity,FDirection,Style,Variant);Prepared.SourceRevision:=Audio.SourceRevision;
  Ops:=StyleOperations(Style);Ops.Prepare(Context,Prepared,PreparedEnd,PreparedSummary);Context.CheckCancel;
end;
procedure TRhythmPrepareThread.Execute;
begin
  try
    if Terminated then Abort;
    InterlockedExchange(FStage,1);
    if not FForce and (FExisting<>nil) and not (StyleHas(FStyle,sfThreshold) and (FVariant<101) and (Length(FExisting.PCM)=0)) and SameFileName(FExisting.Source,ExpandFileName(FSource)) and (FExisting.Sensitivity=FSensitivity) and AudioSourceUnchanged(FExisting) then begin Audio:=FExisting;
      FExisting:=nil;
      Audio.CacheReused:=True;
    end;
    FreeAndNil(FExisting);
    if (Audio=nil) and not FForce then Audio:=LoadCachedRhythmAudio(FSource,FSensitivity);
    if Audio=nil then Audio:=LoadRhythmAudio(FSource,FSensitivity,function:Boolean begin Result:=Terminated;end);
    if Terminated then Abort;
    BuildPlan(FStyle,FVariant,Plan,PreviewEnd,Summary);
  except on E:Exception do begin
      Cancelled:=Terminated;
      if Cancelled then Error:='準備を中止しました。'
      else Error:=Format('準備失敗（段階%d）: %s: %s',[GetStage,E.ClassName,E.Message]);
      // Decoded audio stays available for a plan-only retry. It is never treated
      // as a valid animation without a matching, read-back-verified plan.
      if Cancelled or (GetStage<2) then FreeAndNil(Audio);
      Plan:=Default(TRhythmPlanRef);
    end;
  end;
end;

destructor TRhythmPrepareThread.Destroy;
begin
  // TThread.Destroy terminates and joins even a never-started suspended thread.
  // Keep its source data alive until the base destructor has finished joining.
  inherited Destroy;
  FExisting.Free;
  Audio.Free;
end;

function TRhythmPrepareThread.TakeAudio:TRhythmAudio;
begin Result:=Audio;
  Audio:=nil;
end;
end.
