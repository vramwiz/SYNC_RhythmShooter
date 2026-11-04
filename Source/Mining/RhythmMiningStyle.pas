unit RhythmMiningStyle;
// 採掘専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function MiningOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmMiningScene,RhythmMiningPlan;
function CreateScene:TAnimationScene;
begin Result:=TMiningAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TMiningAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TMiningAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TMiningPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Mining,RestoredMining:TMiningPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Mining:=TMiningPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Mining.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TMiningPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredMining:=TMiningPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try PreparedEnd:=Max(Context.Audio.Duration,RestoredMining.EndTime);
          PreparedSummary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredMining.PulseCount,RestoredMining.Count,RestoredMining.BossCount,RestoredMining.EndTime]);
        finally RestoredMining.Free;
        end;
      finally Mining.Free;
      end;
end;
function MiningOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmMiningStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
