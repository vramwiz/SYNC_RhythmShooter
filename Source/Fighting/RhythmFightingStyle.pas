unit RhythmFightingStyle;
// 格闘専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function FightingOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmFightingScene,RhythmFightingPlan;
function CreateScene:TAnimationScene;
begin Result:=TFightingAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TFightingAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TFightingAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TFightingPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Fighting,RestoredFighting:TFightingPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Fighting:=TFightingPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Fighting.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TFightingPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredFighting:=TFightingPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try PreparedEnd:=Max(Context.Audio.Duration,RestoredFighting.EndTime);
          PreparedSummary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredFighting.PulseCount,RestoredFighting.Count,RestoredFighting.BossCount,RestoredFighting.EndTime]);
        finally RestoredFighting.Free;
        end;
      finally Fighting.Free;
      end;
end;
function FightingOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmFightingStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
