unit RhythmFireworksStyle;
// 花火専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function FireworksOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmFireworksScene,RhythmFireworksPlan;
function CreateScene:TAnimationScene;
begin Result:=TFireworksAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TFireworksAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TFireworksAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TFireworksPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Fireworks,Checked:TFireworksPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Fireworks:=TFireworksPlan.Build(Context.Audio,Context.Direction,Context.Variant,Context.Cancel);
      try
        Context.SetStage(3);
        Fireworks.Save(Prepared,Context.Cancel);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TFireworksPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try Checked:=TFireworksPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try if Checked.EndTime>PreparedEnd then PreparedEnd:=Checked.EndTime;
          PreparedSummary:=Format('%d音 → %d開花 / 華やかさ%d / 終端外%d',[Checked.SourceEventCount,Checked.Count,Checked.Richness,Checked.ExcludedCount]);
        finally Checked.Free;
        end;
      finally Fireworks.Free;
      end;
end;
function FireworksOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmFireworksStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
