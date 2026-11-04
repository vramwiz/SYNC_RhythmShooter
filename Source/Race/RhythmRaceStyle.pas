unit RhythmRaceStyle;
// レースゲーム専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function RaceOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmRaceScene,RhythmRacePlan;
function CreateScene:TAnimationScene;
begin Result:=TRaceAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin TRaceAnimation(Scene).SetReference(Ref);end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin TRaceAnimation(Scene).Audio:=Audio;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=TRacePlan.LoadAudioMetadata(Ref,Source,Direction);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
var Race,RestoredRace:TRacePlan;RestoredAudio:TRhythmAudio;
begin
      Prepared.SourceRevision:=Context.Audio.SourceRevision;
      Race:=TRacePlan.Build(Context.Audio,Context.Cancel);
      try
        Context.SetStage(3);
        Context.CheckCancel;
        Race.Save(Prepared,Context.Audio);
        Context.CheckCancel;
        Context.SetStage(4);
        RestoredAudio:=TRacePlan.LoadAudioMetadata(Prepared,Context.Audio.Source,Context.Direction);
        try RestoredRace:=TRacePlan.Load(Prepared,RestoredAudio,Context.Direction);
        finally RestoredAudio.Free;
        end;
        try
          PreparedEnd:=Max(Context.Audio.Duration,RestoredRace.EndTime);
          if RestoredRace.Crash<>nil then PreparedSummary:=Format('%d音 → %d衝突 / 敵車%d・一般車%d・ボス%d / 採用外%d / ゴール %.3f秒',[Length(Context.Audio.Hits),Length(RestoredRace.Crash.Hits),Length(RestoredRace.Crash.Enemies),Length(RestoredRace.Crash.Traffic),Length(RestoredRace.Crash.Bosses),RestoredRace.Excluded,RestoredRace.GoalTime])
          else begin
            PreparedSummary:=Format('%d候補 → %dコイン取得 / 採用外%d / ゴール %.3f秒 / 終了 %.3f秒',[Length(Context.Audio.Hits),RestoredRace.Count,RestoredRace.Excluded,RestoredRace.GoalTime,RestoredRace.EndTime]);
            PreparedSummary:=PreparedSummary+Format(' / 妨害車%d・トレーラー%d・爆弾%d',[RestoredRace.TrafficCount,RestoredRace.TrailerCount,RestoredRace.BombCount]);
            PreparedSummary:=PreparedSummary+Format(' / 総得点%d',[RestoredRace.MaxScore]);
          end;
        finally RestoredRace.Free;
        end;
      finally Race.Free;
      end;
end;
function RaceOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmRaceStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=EmptyStyleImages;
end;
end.
