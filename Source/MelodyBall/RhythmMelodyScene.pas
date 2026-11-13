unit RhythmMelodyScene;
// 計画は所有、音声は借用。描画中に生成・解析をせず、復元失敗は参照の変更まで保持する。
interface
uses RhythmAnimation,RhythmAudio,RhythmPlanRef,RhythmMelodyPlan,RhythmRenderSurface;
type
  TMelodyAnimation = class(TAnimationScene)
  private
    FPlan: TMelodyPlan;
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
uses System.SysUtils,RhythmMelodyCodec,RhythmMelodyArt;
destructor TMelodyAnimation.Destroy;
begin FPlan.Free; inherited; end;
procedure TMelodyAnimation.SetReference(const Ref: TRhythmPlanRef);
begin FRef:=Ref; end;
procedure TMelodyAnimation.Prepare(const Frame: TAnimationFrame);
var Key: string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if Audio<>nil then Key:=Key+'|'+Audio.Key;
  if Key=FAttempt then Exit;
  FAttempt:=Key; FreeAndNil(FPlan); FError:=''; if Audio=nil then Exit;
  try FPlan:=LoadMelodyPlan(FRef,Audio,Frame.Direction);
  except on E: Exception do FError:=E.Message; end;
end;
procedure TMelodyAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
begin if FPlan<>nil then DrawMelodyBall(Surface,FPlan,Frame); end;
function TMelodyAnimation.Notice: string;
begin Result:=FError; end;
function TMelodyAnimation.GoalTime: Double;
begin Result:=0; end;
end.
