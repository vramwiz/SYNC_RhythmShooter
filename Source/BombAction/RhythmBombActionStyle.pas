unit RhythmBombActionStyle;
// 爆弾アクション専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function BombActionOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmBombScene,RhythmBombPlan;
function CreateScene:TAnimationScene;
begin Result:=TBombActionAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TBombActionAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TBombActionAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TBombActionPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var BombAction,RestoredBombAction:TBombActionPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      BombAction:=TBombActionPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        BombAction.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TBombActionPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredBombAction:=TBombActionPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try PreparedEnd:=Max(Context.Audio.Duration,RestoredBombAction.EndTime);
          PreparedSummary:=Format('%d音候補 → 爆発%d・連鎖%d・破壊%d・ボス%d・攻撃弾%d / 採用外%d',[Length(Context.Audio.Hits),RestoredBombAction.Count+RestoredBombAction.ChargeCount,RestoredBombAction.ChainCount,RestoredBombAction.TargetCount+RestoredBombAction.CrowdDestroyed(RestoredBombAction.EndTime),RestoredBombAction.BossCount,RestoredBombAction.ShotCount+RestoredBombAction.RaidCount,RestoredBombAction.Excluded]);
        finally RestoredBombAction.Free;
        end;
      finally BombAction.Free;
      end;
end;
function BombActionOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmBombActionStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
