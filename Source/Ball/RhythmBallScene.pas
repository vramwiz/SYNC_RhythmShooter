unit RhythmBallScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmBallPlan;
type
  TBallAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TRhythmBallPlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure SetReference(const Ref:TRhythmPlanRef);
    function GoalTime:Double; override;
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
  end;
implementation
uses System.SysUtils,RhythmBallLegacyScene,RhythmBallCircuitScene;

destructor TBallAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TBallAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TBallAnimation.Notice:string;
begin Result:=FError;
end;

procedure TBallAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TRhythmBallPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TBallAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
begin
  if (FPlan<>nil) and (FPlan.Circuit<>nil) then begin DrawBallCircuit(FPlan.Circuit,Surface,Frame);
    Exit;
  end;
  DrawBallLegacy(FPlan,Surface,Frame);
end;

function TBallAnimation.GoalTime:Double;
begin
  Result:=inherited GoalTime;
  if (FPlan<>nil) and (FPlan.Circuit<>nil) then Result:=FPlan.Circuit.SoundEnd;
end;
end.
