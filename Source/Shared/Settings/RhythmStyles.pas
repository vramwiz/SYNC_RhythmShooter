unit RhythmStyles;
// 全11スタイルの識別・計画版互換・共通ボス頻度の契約を定義する。
interface
type TRhythmStyle=(rsShooting,rsBall,rsFireworks,rsRunner,rsBreakout,rsRace,rsBombAction,rsFighting,rsMining,rsTrain,rsNaval);
function StyleId(Style:TRhythmStyle):string;
function StyleTitle(Style:TRhythmStyle):string;
function TryStyle(const Id:string;out Style:TRhythmStyle):Boolean;
function StylePlanVersion(Style:TRhythmStyle):Integer;
function CompatiblePlanVersion(Style:TRhythmStyle;Version:Integer):Boolean;
function StyleVariant(Style:TRhythmStyle;FireworksRichness:Integer;BossFrequency:Integer=-1):Integer;
function BossPeriod(Frequency:Integer):Double;
function BossFrequencyText(Frequency:Integer):string;
function BossFrequencyFromVariant(Variant:Integer):Integer;
const FIREWORKS_DEFAULT_RICHNESS=50;BOSS_DEFAULT_FREQUENCY=50;
implementation
uses System.SysUtils;
function StyleId(Style:TRhythmStyle):string;
begin case Style of rsBall:Result:='ball';rsFireworks:Result:='fireworks';rsRunner:Result:='runner';rsBreakout:Result:='breakout';rsRace:Result:='race';rsBombAction:Result:='bomb-action';rsFighting:Result:='fighting';rsMining:Result:='mining';rsTrain:Result:='train';rsNaval:Result:='naval';else Result:='shooting';end;end;
function StyleTitle(Style:TRhythmStyle):string;
begin case Style of rsBall:Result:='ボール（ピンボール）';rsFireworks:Result:='花火';rsRunner:Result:='ランナー';rsBreakout:Result:='ブロック崩し';rsRace:Result:='レースゲーム';rsBombAction:Result:='爆弾アクション';rsFighting:Result:='格闘';rsMining:Result:='採掘';rsTrain:Result:='列車';rsNaval:Result:='海戦';else Result:='シューティング';end;end;
function TryStyle(const Id:string;out Style:TRhythmStyle):Boolean;
begin Style:=rsShooting;Result:=True;if Id='shooting' then Exit;if Id='ball' then begin Style:=rsBall;Exit;end;if Id='fireworks' then begin Style:=rsFireworks;Exit;end;if Id='runner' then begin Style:=rsRunner;Exit;end;if Id='breakout' then begin Style:=rsBreakout;Exit;end;if Id='race' then begin Style:=rsRace;Exit;end;if Id='bomb-action' then begin Style:=rsBombAction;Exit;end;if Id='fighting' then begin Style:=rsFighting;Exit;end;if Id='mining' then begin Style:=rsMining;Exit;end;if Id='train' then begin Style:=rsTrain;Exit;end;if Id='naval' then begin Style:=rsNaval;Exit;end;Result:=False;end;
function StylePlanVersion(Style:TRhythmStyle):Integer;
begin case Style of rsBall:Result:=6;rsFireworks:Result:=3;rsRunner:Result:=6;rsBreakout:Result:=10;rsRace:Result:=10;rsBombAction:Result:=2;rsFighting:Result:=2;rsMining,rsTrain,rsNaval:Result:=1;else Result:=1;end;end;
function CompatiblePlanVersion(Style:TRhythmStyle;Version:Integer):Boolean;
begin Result:=((Style=rsFighting) and (Version=1)) or ((Style=rsFireworks) and (Version=2)) or ((Style=rsBombAction) and (Version=1)) or ((Style=rsRunner) and (Version in [2,3,4,5])) or (Version=StylePlanVersion(Style)) or ((Style=rsBall) and (Version in [4,5])) or ((Style in [rsRunner,rsBreakout,rsRace]) and (Version=1)) or ((Style=rsRace) and (Version in [2,3,4,5,6,7,8,9])) or ((Style=rsBreakout) and (Version in [2,3,4,5,6,7,8,9]));end;
function StyleVariant(Style:TRhythmStyle;FireworksRichness:Integer;BossFrequency:Integer):Integer;
begin Result:=0;if (Style in [rsShooting,rsRunner,rsBreakout,rsRace,rsBombAction,rsFighting,rsMining,rsTrain,rsNaval]) and (BossFrequency>=0) then begin Result:=BossFrequency;if Result>100 then Result:=100;Inc(Result);Exit;end;if Style=rsFireworks then begin Result:=FireworksRichness;if Result<0 then Result:=0;if Result>100 then Result:=100;end;end;
function BossPeriod(Frequency:Integer):Double;
begin if Frequency<=0 then Exit(0);if Frequency>100 then Frequency:=100;Result:=135.0-0.9*Frequency;end;
function BossFrequencyFromVariant(Variant:Integer):Integer;
begin if Variant=0 then Exit(100);Result:=Variant-1;if Result<0 then Result:=0;if Result>100 then Result:=100;end;
function BossFrequencyText(Frequency:Integer):string;
begin if Frequency<=0 then Exit('0 / 出現なし');Result:=Format('%d / 約%.0f秒',[Frequency,BossPeriod(Frequency)]);end;
end.
