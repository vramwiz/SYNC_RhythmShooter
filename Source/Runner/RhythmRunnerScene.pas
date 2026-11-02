unit RhythmRunnerScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmRunnerPlan;
type
  TRunnerAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TRunnerPlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
  end;
implementation
uses System.SysUtils,RhythmRunnerLegacyScene,RhythmRunnerPixels;

destructor TRunnerAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TRunnerAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TRunnerAnimation.Notice:string;
begin Result:=FError;
end;

procedure TRunnerAnimation.Prepare(const Frame:TAnimationFrame);
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
  try FPlan:=TRunnerPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TRunnerAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
begin
  if (FPlan<>nil) and (FPlan.Action<>nil) then begin RenderRunnerPixels(FPlan.Action,Surface,Frame.Time,Frame.Width,Frame.Height);
    Exit;
  end;
  DrawRunnerLegacy(FPlan,Surface,Frame);
end;
end.
