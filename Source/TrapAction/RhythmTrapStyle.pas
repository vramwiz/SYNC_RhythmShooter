unit RhythmTrapStyle;
// 共通の準備・保存・プレビュー・ホストへ、独立した罠アクションを登録する。
// この窓口は専用部品の接続だけを持ち、生成・保存・描画の実装を取り込まない。
interface
uses RhythmStyleOps;
// 操作表のScene/画像の生成結果はRendererへ所有権を渡し、SetAudioは音声を借用する。
function TrapOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAnimation,RhythmAudio,RhythmPlanRef,RhythmStyles,
  RhythmTrapPlan,RhythmTrapBuild,RhythmTrapCodec,RhythmTrapScene;
function CreateScene:TAnimationScene;
begin Result:=TTrapAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TTrapAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TTrapAnimation(Scene).Audio:=Audio;end;
procedure Prepare(const Context:TStylePrepareContext;var Ref:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Plan:TTrapPlan;Restored:TRhythmAudio;
begin
  // 保存後にPCMなしで読み戻して検証する。PreparedEndだけを演出終端へ延ばし、原音声長は保つ。
  if not InRange(Context.Variant,1,8) then raise EArgumentException.Create('ステージが不正です');
  Ref.SourceRevision:=Context.Audio.SourceRevision;
  Plan:=BuildTrapPlan(Context.Audio,TTrapStage(Context.Variant-1),Context.Cancel);
  try Context.CheckCancel;Context.SetStage(3);SaveTrapPlan(Plan,Context.Audio,Ref);finally Plan.Free;end;
  Context.CheckCancel;Context.SetStage(4);Restored:=LoadTrapAudio(Ref,Context.Audio.Source,Context.Direction);
  try Plan:=LoadTrapPlan(Ref,Restored,Context.Direction);
    try PreparedEnd:=Plan.EndTime;PreparedSummary:=Format('%s / %d動作・%dの罠 / 回避距離検証済み',
      [TrapStageTitles[Plan.Theme],Length(Plan.Moves),Length(Plan.Obstacles)]);finally Plan.Free;end;
  finally Restored.Free;end;
end;
function TrapOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmTrapStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadTrapAudio;Result.CreateImages:=EmptyStyleImages;
  Result.EqualizerPreservesBrightness:=True;
end;
end.
