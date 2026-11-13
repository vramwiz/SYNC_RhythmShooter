unit RhythmMelodyStyle;
// メロディボールを共通の準備・保存・UI・ホスト描画へ接続する所有権の窓口。
interface
uses RhythmStyleOps;
function MelodyOperations: TStyleOperations;
implementation
uses System.SysUtils,RhythmAnimation,RhythmAudio,RhythmPlanRef,
  RhythmMelodyPlan,RhythmMelodyBuild,RhythmMelodyCodec,RhythmMelodyScene;
function CreateScene: TAnimationScene;
begin Result:=TMelodyAnimation.Create; end;
procedure SetReference(Scene: TAnimationScene; const Ref: TRhythmPlanRef);
begin TMelodyAnimation(Scene).SetReference(Ref); end;
procedure SetAudio(Scene: TAnimationScene; Audio: TRhythmAudio; BossFrequency: Integer);
begin TMelodyAnimation(Scene).Audio:=Audio; end;
procedure Prepare(const Context: TStylePrepareContext; var Ref: TRhythmPlanRef;
  var PreparedEnd: Double; var PreparedSummary: string);
var P: TMelodyPlan; A: TRhythmAudio;
begin
  Ref.SourceRevision:=Context.Audio.SourceRevision;
  P:=BuildMelodyPlan(Context.Audio,Context.Cancel);
  try Context.CheckCancel; Context.SetStage(3); SaveMelodyPlan(P,Context.Audio,Ref);
  finally P.Free; end;
  Context.CheckCancel; Context.SetStage(4);
  A:=LoadMelodyAudio(Ref,Context.Audio.Source,Context.Direction);
  try
    P:=LoadMelodyPlan(Ref,A,Context.Direction);
    try PreparedEnd:=P.EndTime;
      if P.Meter>0 then PreparedSummary:=Format('%d個の鉄琴 / %d演出区間（推定%d拍子・約4小節ごと）',
        [Length(P.Bars),Length(P.Sections),P.Meter])
      else PreparedSummary:=Format('%d個の鉄琴 / %d演出区間（拍節未確定・約8秒ごと）',
        [Length(P.Bars),Length(P.Sections)]);
    finally P.Free; end;
  finally A.Free; end;
end;
function MelodyOperations: TStyleOperations;
begin
  Result:=Default(TStyleOperations); Result.UnitName:='RhythmMelodyStyle';
  Result.CreateScene:=CreateScene; Result.SetReference:=SetReference; Result.SetAudio:=SetAudio;
  Result.Prepare:=Prepare; Result.LoadAudio:=LoadMelodyAudio; Result.CreateImages:=EmptyStyleImages;
  Result.EqualizerPreservesBrightness:=True;
end;
end.
