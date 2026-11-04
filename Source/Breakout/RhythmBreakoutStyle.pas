unit RhythmBreakoutStyle;
// ブロック崩し専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function BreakoutOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmBreakoutScene,RhythmBreakoutPlan,RhythmShootingAssets;
function CreateScene:TAnimationScene;
begin Result:=TBreakoutAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TBreakoutAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TBreakoutAnimation(Scene).Audio:=Audio;end;
function CreateImages:TAnimationImageBank;
begin Result:=TShootingImageBank.Create;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TBreakoutPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Breakout,RestoredBreakout:TBreakoutPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Breakout:=TBreakoutPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Breakout.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TBreakoutPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredBreakout:=TBreakoutPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try
          PreparedEnd:=Max(Context.Audio.Duration,RestoredBreakout.EndTime);
          PreparedSummary:=Format('%d音候補 / %dブロック / 音同期%d・補助%d・捕球%d / 全破壊 %.3f 秒',[RestoredBreakout.SourceCount,RestoredBreakout.Count,RestoredBreakout.ReflectionCount,RestoredBreakout.AuxiliaryCount,RestoredBreakout.CatchCount,RestoredBreakout.GoalTime]);
          PreparedSummary:=PreparedSummary+Format(' / 見せ場%d・追加球%d',[RestoredBreakout.ItemCount,RestoredBreakout.ExtraCount]);
          if RestoredBreakout.Campaign<>nil then PreparedSummary:=PreparedSummary+Format('・ボス%d（候補%d）',[RestoredBreakout.BossCount,RestoredBreakout.Campaign.CandidateCount])
          else PreparedSummary:=PreparedSummary+Format('・ボス%d',[RestoredBreakout.BossCount]);
        finally RestoredBreakout.Free;
        end;
      finally Breakout.Free;
      end;
end;
function BreakoutOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmBreakoutStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=CreateImages;
end;
end.
