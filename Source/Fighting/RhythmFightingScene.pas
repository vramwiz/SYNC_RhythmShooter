unit RhythmFightingScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmFightingPlan;
type
  TFightingAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TFightingPlan;
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
uses System.SysUtils,RhythmFightingLegacyScene,RhythmFightingDuelScene;

destructor TFightingAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TFightingAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TFightingAnimation.Notice:string;
begin Result:=FError;
end;

procedure TFightingAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TFightingPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TFightingAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
begin
  if (FPlan<>nil) and (FPlan.Action<>nil) then begin DrawFightingDuel(FPlan.Action,Surface,Frame.Time,Frame.Width,Frame.Height,Frame.BackgroundOnly);
    Exit;
  end;
  DrawFightingLegacy(FPlan,Surface,Frame);
end;
end.
