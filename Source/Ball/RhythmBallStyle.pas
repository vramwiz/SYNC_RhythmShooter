unit RhythmBallStyle;
// ボール（ピンボール）専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function BallOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmBallScene,RhythmBallPlan;
function CreateScene:TAnimationScene;
begin Result:=TBallAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TBallAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TBallAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TRhythmBallPlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Ball,Verified:TRhythmBallPlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Ball:=TRhythmBallPlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Ball.Save(Prepared,Context.Cancel);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TRhythmBallPlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try Verified:=TRhythmBallPlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try PreparedSummary:=Format('%d音イベント → %d衝突＋%d共鳴 / 終端外%d',[Verified.PulseCount,Verified.ObstacleCount,Verified.PulseCount-Verified.ObstacleCount,Verified.ExcludedCount]);
        finally Verified.Free;
        end;
      finally Ball.Free;
      end;
end;
function BallOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmBallStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
