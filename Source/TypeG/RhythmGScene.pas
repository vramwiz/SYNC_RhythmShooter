unit RhythmGScene;
// 計画を所有し、音声を借用するType.Gの描画窓口。復元失敗は参照変更まで保持する。
interface
uses RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmGPlan, RhythmRenderSurface;
type
  TGAnimation = class(TAnimationScene)
  private
    FPlan: TGPlan;
    FRef: TRhythmPlanRef;
    FAttempt,FError: string;
  public
    Audio: TRhythmAudio;
    destructor Destroy; override;
    procedure SetReference(const Ref: TRhythmPlanRef);
    procedure Prepare(const Frame: TAnimationFrame); override;
    procedure Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame); override;
    function Notice: string; override;
    function GoalTime: Double; override;
  end;
implementation
uses System.SysUtils, RhythmGCodec, RhythmGArt;
destructor TGAnimation.Destroy;
begin FPlan.Free; inherited; end;
procedure TGAnimation.SetReference(const Ref: TRhythmPlanRef);
begin FRef:=Ref; end;
procedure TGAnimation.Prepare(const Frame: TAnimationFrame);
var Key: string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if Audio<>nil then Key:=Key+'|'+Audio.Key;
  if Key=FAttempt then Exit;
  FAttempt:=Key; FreeAndNil(FPlan); FError:=''; if Audio=nil then Exit;
  try FPlan:=LoadGPlan(FRef,Audio,Frame.Direction);
  except on E: Exception do FError:=E.Message; end;
end;
procedure TGAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
begin if FPlan<>nil then DrawTypeG(Surface,FPlan,Frame); end;
function TGAnimation.Notice: string;
begin Result:=FError; end;
function TGAnimation.GoalTime: Double;
begin Result:=0; end;
end.
