unit RhythmTrapScene;
// 保存計画の所有窓口。借用音声と参照を照合し、描画中に解析や計画生成を行わない。
interface
uses RhythmAnimation,RhythmAudio,RhythmPlanRef,RhythmTrapPlan,RhythmRenderSurface;
type TTrapAnimation=class(TAnimationScene)
  private FPlan:TTrapPlan;FReference:TRhythmPlanRef;FAttempt,FError:string;
  public Audio:TRhythmAudio;
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    function GoalTime:Double;override;
  end;
implementation
uses System.SysUtils,RhythmTrapCodec,RhythmTrapArt;
destructor TTrapAnimation.Destroy;
begin FPlan.Free;inherited;end;
procedure TTrapAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FReference:=Ref;end;
procedure TTrapAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin Key:=FReference.Key+'|'+FReference.Digest+'|'+IntToStr(Frame.Direction);
  if Audio<>nil then Key:=Key+'|'+Audio.Key;
  if Key=FAttempt then Exit;FAttempt:=Key;FreeAndNil(FPlan);FError:='';if Audio=nil then Exit;
  try FPlan:=LoadTrapPlan(FReference,Audio,Frame.Direction);except on E:Exception do FError:=E.Message;end;
end;
procedure TTrapAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
begin if FPlan<>nil then DrawTrapAction(Surface,FPlan,Frame);end;
function TTrapAnimation.Notice:string;
begin Result:=FError;end;
function TTrapAnimation.GoalTime:Double;
begin Result:=0;end;
end.
