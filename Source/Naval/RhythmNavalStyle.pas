unit RhythmNavalStyle;
// 海戦専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function NavalOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmNavalScene,RhythmNavalPlan;
function CreateScene:TAnimationScene;
begin Result:=TNavalAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TNavalAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TNavalAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TNavalPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Naval,RestoredNaval:TNavalPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Naval:=TNavalPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Naval.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TNavalPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredNaval:=TNavalPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try PreparedEnd:=Max(Context.Audio.Duration,RestoredNaval.EndTime);
          PreparedSummary:=Format('%d音 → %dアクション / ボス%d / 終了 %.3f秒',[RestoredNaval.PulseCount,RestoredNaval.Count,RestoredNaval.BossCount,RestoredNaval.EndTime]);
        finally RestoredNaval.Free;
        end;
      finally Naval.Free;
      end;
end;
function NavalOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmNavalStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
