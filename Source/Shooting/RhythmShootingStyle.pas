unit RhythmShootingStyle;
// シューティング専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function ShootingOperations:TStyleOperations;
implementation
uses System.SysUtils,System.Math,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,
  RhythmShootingScene,RhythmAudioCache,RhythmShootingAssets;
function CreateScene:TAnimationScene;
begin Result:=TShootingAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin if Audio<>nil then Audio.SetBossFrequency(BossFrequency);TShootingAnimation(Scene).Audio:=Audio;end;
function CreateImages:TAnimationImageBank;
begin Result:=TShootingImageBank.Create;end;
function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=LoadCachedRhythmAudio(Source,Ref.Sensitivity,False);end;
procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
begin
  PreparedSummary:=IntToStr(Length(Context.Audio.Hits))+'イベント / ボス'+IntToStr(Context.Audio.BossCount)+' / '+BossFrequencyText(Context.Audio.BossFrequency);
end;
function ShootingOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmShootingStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=CreateImages;
end;
end.
