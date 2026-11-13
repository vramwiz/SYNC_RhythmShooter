unit RhythmTrapScene;
// 保存計画の所有窓口。借用音声と参照を照合し、描画中に解析や計画生成を行わない。
// 描画と保存形式の詳細をArt/Codecへ分け、参照が変わったときだけ復元を試みる。
interface
uses RhythmAnimation,RhythmAudio,RhythmPlanRef,RhythmTrapPlan,RhythmRenderSurface;
type TTrapAnimation=class(TAnimationScene)
  private FPlan:TTrapPlan;FReference:TRhythmPlanRef;FAttempt,FError:string; // FPlanを所有し、破棄時に解放する。
  public Audio:TRhythmAudio; // Rendererからの借用。Sceneは解放しない。
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    // 失敗も参照キーと一緒に保持し、同じ不正ファイルを毎フレーム読み直さない。
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    function GoalTime:Double;override; // 0で共通花火を抑止する。地上の花火はArtが同じ共通描画を呼ぶ。
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
