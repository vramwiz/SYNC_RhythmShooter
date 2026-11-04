unit RhythmGameStyle;
// リズムゲーム専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function GameOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmGameScene,RhythmGamePlan;
function CreateScene:TAnimationScene;
begin Result:=TGameAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TGameAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TGameAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TGamePlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Game,RestoredGame:TGamePlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Game:=TGamePlan.Build(Context.Audio,Context.Cancel,EnsureRange(Context.Variant-101,-100,100));
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Game.Save(Prepared,Context.Audio);
        Context.SetStage(4);
        Context.CheckCancel;
        RestoredAudio:=TGamePlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredGame:=TGamePlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;end;
        try PreparedEnd:=Max(Context.Audio.Duration,RestoredGame.EndTime);
          PreparedSummary:=Format('%d音 → %d自動成功 / 除外%d / %.3f秒',[Length(Context.Audio.Hits),RestoredGame.Count,RestoredGame.Excluded,PreparedEnd]);
        finally RestoredGame.Free;end;
      finally Game.Free;end;
end;
procedure Transparency(Scene:TAnimationScene;Value:Boolean);
begin TGameAnimation(Scene).TransparentBackground:=Value;end;
function Activity(Scene:TAnimationScene;Time:Double;out Value:TEqualizerActivity):Boolean;
begin Result:=TGameAnimation(Scene).TryActivity(Time,Value);end;
function GameOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmGameStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;Result.Transparency:=Transparency;Result.Activity:=Activity;
end;
end.
