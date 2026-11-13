unit RhythmGStyle;
// Type.Gを共通の選択・全曲準備・保存復元へ接続する。編集済み参照は再生成しない。
interface
uses RhythmStyleOps;
function GOperations: TStyleOperations;
implementation
uses System.SysUtils, RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmGPlan, RhythmGCodec, RhythmGScene, RhythmGImages;
function CreateScene: TAnimationScene;
begin Result:=TGAnimation.Create; end;
procedure SetReference(Scene: TAnimationScene; const Ref: TRhythmPlanRef);
begin TGAnimation(Scene).SetReference(Ref); end;
procedure SetAudio(Scene: TAnimationScene; Audio: TRhythmAudio; BossFrequency: Integer);
begin TGAnimation(Scene).Audio:=Audio; end;
procedure Prepare(const Context: TStylePrepareContext; var Ref: TRhythmPlanRef;
  var PreparedEnd: Double; var PreparedSummary: string);
var P: TGPlan; A: TRhythmAudio;
begin
  Ref.SourceRevision:=Context.Audio.SourceRevision;
  if Ref.Digest='' then begin
    P:=BuildGPlan(Context.Audio,Context.Cancel);
    try Context.CheckCancel; Context.SetStage(3); SaveGPlan(P,Context.Audio,Ref);
    finally P.Free; end;
  end;
  Context.CheckCancel; Context.SetStage(4);
  A:=LoadGAudio(Ref,Context.Audio.Source,Context.Direction);
  try
    P:=LoadGPlan(Ref,A,Context.Direction);
    try PreparedEnd:=P.Duration;
      PreparedSummary:=Format('%dシーン / %dアクション / 32種のミニゲーム',[Length(P.Scenes),Length(P.Cues)]);
    finally P.Free; end;
  finally A.Free; end;
end;
function GOperations: TStyleOperations;
begin
  Result:=Default(TStyleOperations); Result.UnitName:='RhythmGStyle';
  Result.CreateScene:=CreateScene; Result.SetReference:=SetReference; Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare; Result.LoadAudio:=LoadGAudio; Result.CreateImages:=CreateGImages;
  Result.EqualizerPreservesBrightness:=True;
end;
end.
