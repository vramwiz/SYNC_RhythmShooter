unit RhythmStyles;
// 保存ID/計画版の契約と、設定画面だけの分類・機能カタログ。分類値はJSONやホストへ保存しない。
interface
type TRhythmStyle=(rsShooting,rsBall,rsJumpAdventure,rsBreakout,rsSideRace,rsBombAction,rsFightingRush,rsMining,rsTrain,rsRhythmGame,rsStepGame,rsMineCart,rsCrashCannon,rsParkour,rsMarbleRelay,rsRobotWar,rsTrapAction);
type
  TRhythmStyleGroup=(sgShooting,sgBall,sgAction,sgRace,sgMusic);
  TStyleSmallKind=(skFixed,skScroll);
  TMarbleBallStyle=(mbSteel,mbGlass,mbWood,mbPorcelain);
  TMarbleStageStyle=(msWoodWorkshop,msDeskCraft,msSteampunk,msClearAcrylic,msNeonArcade,msColorToys,msStoneRuins);
  TTrapStage=(tsCave,tsRuins,tsFactory,tsCastle,tsFacility,tsVolcano,tsIceCave,tsForestRuins);
  TStyleVariantKind=(svNone,svBoss,svRhythm,svTrap);
  TStyleFeature=(sfBoss,sfPrepared,sfThreshold,sfTransparent,sfDefaultBoss50,sfOwnFinale);
  TStyleFeatures=set of TStyleFeature;
  TStyleInfo=record
    Id,Title,MiddleTitle,FixedSmall,ProgressText:string;
    Group:TRhythmStyleGroup;
    Order:Integer;
    SmallKind:TStyleSmallKind;
    Version:Integer;
    Versions:set of Byte;
    Features:TStyleFeatures;
    VariantKind:TStyleVariantKind;
  end;
function StyleInfo(Style:TRhythmStyle):TStyleInfo;
function StyleHas(Style:TRhythmStyle;Feature:TStyleFeature):Boolean;
function StyleGroupTitle(Group:TRhythmStyleGroup):string;
function GroupStyleCount(Group:TRhythmStyleGroup):Integer;
function GroupStyleAt(Group:TRhythmStyleGroup;Index:Integer):TRhythmStyle;
function GroupStyleIndex(Style:TRhythmStyle):Integer;
function StyleSmallCount(Style:TRhythmStyle):Integer;
function StyleSmallTitle(Style:TRhythmStyle;Index:Integer):string;
function StyleId(Style:TRhythmStyle):string;
function StyleTitle(Style:TRhythmStyle):string;
function TryStyle(const Id:string;out Style:TRhythmStyle):Boolean;
function StylePlanVersion(Style:TRhythmStyle):Integer;
function CompatiblePlanVersion(Style:TRhythmStyle;Version:Integer):Boolean;
function StyleVariant(Style:TRhythmStyle;FireworksRichness:Integer;BossFrequency:Integer=-1;GameThreshold:Integer=20;TrapStage:TTrapStage=tsCave):Integer;
function AudioDensityKey(Style:TRhythmStyle;Value:Integer):Integer;
function BossPeriod(Frequency:Integer):Double;
function BossFrequencyText(Frequency:Integer):string;
function BossFrequencyFromVariant(Variant:Integer):Integer;
const FIREWORKS_DEFAULT_RICHNESS=50;BOSS_DEFAULT_FREQUENCY=50;AUDIO_DEFAULT_DENSITY=20;
  TrapStageTitles:array[TTrapStage] of string=('洞窟','遺跡','工場','城内','地下施設','火山','氷の洞窟','森林遺跡');
  TrapStageIds:array[TTrapStage] of string=('cave','ruins','factory','castle','facility','volcano','ice','forest');
  TYPE_V_TITLE='Type.V';
  TYPE_D_TITLE='Type.D';
  MarbleBallTitles:array[TMarbleBallStyle] of string=('鉄球（銀）','ビー玉（緑）','木球','陶器玉');
  MarbleStageTitles:array[TMarbleStageStyle] of string=('木製からくり','ピタゴラ装置風','スチームパンク',
    '透明アクリル','ネオンアーケード','カラフル玩具','古代石造遺跡');
  MarbleStageIds:array[TMarbleStageStyle] of string=('wood','desk','steampunk','acrylic','neon','toys','ruins');
implementation
uses System.SysUtils,System.Math;
const
  // カタログはenum順。プロジェクトと準備済み計画は文字列IDで識別する。
  Catalog:array[TRhythmStyle] of TStyleInfo=(
    (Id:'shooting';Title:'シューティング';MiddleTitle:'宇宙シューティング';FixedSmall:'';ProgressText:'敵・弾・命中を準備中';Group:sgShooting;Order:0;SmallKind:skScroll;Version:1;Versions:[1];Features:[sfBoss];VariantKind:svBoss),
    (Id:'ball';Title:'ボール（ピンボール）';MiddleTitle:'ピンボール';FixedSmall:'';ProgressText:'障害物と軌道を準備中';Group:sgBall;Order:0;SmallKind:skScroll;Version:6;Versions:[4,5,6];Features:[sfPrepared];VariantKind:svNone),
    (Id:'jump-adventure';Title:'ジャンプアドベンチャー';MiddleTitle:'ジャンプアドベンチャー';FixedSmall:'横・縦の自動切替';ProgressText:'音時刻から足場・踏みつけ・ボス戦を逆算中';Group:sgAction;Order:0;SmallKind:skFixed;Version:3;Versions:[1,2,3];Features:[sfPrepared,sfBoss,sfDefaultBoss50];VariantKind:svBoss),
    (Id:'breakout';Title:'ブロック崩し';MiddleTitle:'ブロック崩し';FixedSmall:'固定盤面';ProgressText:'破壊時刻から逆算・配置・前向き検証中';Group:sgBall;Order:1;SmallKind:skFixed;Version:10;Versions:[1,2,3,4,5,6,7,8,9,10];Features:[sfPrepared,sfBoss];VariantKind:svBoss),
    (Id:'side-race';Title:'2Dハイウェイ';MiddleTitle:'2Dハイウェイ';FixedSmall:'横スクロール';ProgressText:'高速道路・ジャンプ・前後の衝突を音時刻から逆算中';Group:sgRace;Order:0;SmallKind:skFixed;Version:1;Versions:[1];Features:[sfPrepared,sfBoss,sfDefaultBoss50];VariantKind:svBoss),
    (Id:'bomb-action';Title:'爆弾アクション';MiddleTitle:'爆弾アクション';FixedSmall:'見下ろし';ProgressText:'音時刻から設置・連鎖・破壊・ボス回避を逆算/検証中';Group:sgAction;Order:1;SmallKind:skFixed;Version:2;Versions:[1,2];Features:[sfPrepared,sfBoss,sfDefaultBoss50];VariantKind:svBoss),
    (Id:'fighting-rush';Title:'格闘ラッシュ';MiddleTitle:'格闘ラッシュ';FixedSmall:'地上戦・空中戦';ProgressText:'打撃・防御・空中コンボを音時刻から逆算中';Group:sgAction;Order:2;SmallKind:skFixed;Version:1;Versions:[1];Features:[sfPrepared,sfBoss,sfDefaultBoss50];VariantKind:svBoss),
    (Id:'mining';Title:'採掘';MiddleTitle:'掘削アクション';FixedSmall:'見下ろし';ProgressText:'切削・敵・ボスを逆算/保存検証中';Group:sgAction;Order:3;SmallKind:skFixed;Version:1;Versions:[1];Features:[sfPrepared,sfBoss,sfDefaultBoss50];VariantKind:svBoss),
    (Id:'train';Title:'列車';MiddleTitle:'装甲列車';FixedSmall:'横からの視点';ProgressText:'列車・砲撃・ボスを逆算/保存検証中';Group:sgShooting;Order:1;SmallKind:skFixed;Version:1;Versions:[1];Features:[sfPrepared,sfBoss,sfDefaultBoss50];VariantKind:svBoss),
    (Id:'rhythm-game';Title:TYPE_V_TITLE;MiddleTitle:TYPE_V_TITLE;FixedSmall:'MV重ね（透過）';ProgressText:'音時刻からマーク・カーソル軌道・連打を逆算/保存検証中';Group:sgMusic;Order:0;SmallKind:skFixed;Version:4;Versions:[1,2,3,4];Features:[sfPrepared,sfThreshold,sfTransparent];VariantKind:svRhythm),
    (Id:'prism-step';Title:TYPE_D_TITLE;MiddleTitle:TYPE_D_TITLE;FixedSmall:'縦';ProgressText:'音時刻から4レーン譜面を準備中';Group:sgMusic;Order:1;SmallKind:skFixed;Version:3;Versions:[1,2,3];Features:[sfPrepared,sfThreshold];VariantKind:svRhythm),
    (Id:'mine-cart';Title:'トロッコアクション';MiddleTitle:'トロッコアクション';FixedSmall:'鉱山の横スクロール';ProgressText:'コインの接触・線路・回避を逆算中';Group:sgAction;Order:4;SmallKind:skFixed;Version:4;Versions:[1,2,3,4];Features:[sfPrepared,sfBoss,sfDefaultBoss50];VariantKind:svBoss),
    (Id:'crash-cannon';Title:'クラッシュキャノン';MiddleTitle:'クラッシュキャノン';FixedSmall:'横からの視点';ProgressText:'音時刻から着弾・反撃・連鎖崩壊を逆算中';Group:sgAction;Order:5;SmallKind:skFixed;Version:1;Versions:[1];Features:[sfPrepared,sfOwnFinale];VariantKind:svNone),
    (Id:'parkour';Title:'パルクール（試作）';MiddleTitle:'パルクール（試作）';FixedSmall:'屋上の横スクロール';ProgressText:'音時刻から連続ステップ・壁走り・ワイヤーを準備中';Group:sgAction;Order:6;SmallKind:skFixed;Version:2;Versions:[1,2];Features:[sfPrepared,sfOwnFinale];VariantKind:svNone),
    (Id:'marble-relay';Title:'からくりリレー（試作）';MiddleTitle:'からくりリレー（試作）';FixedSmall:'球を追うコース';ProgressText:'音時刻から球の経路と仕掛けの連鎖を準備中';Group:sgBall;Order:2;SmallKind:skFixed;Version:16;Versions:[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16];Features:[sfPrepared,sfOwnFinale];VariantKind:svNone),
    (Id:'robot-war';Title:'ロボット大戦';MiddleTitle:'ロボット大戦';FixedSmall:'都市の変形・合体戦';ProgressText:'音時刻から変形・合体・都市戦を準備中';Group:sgAction;Order:7;SmallKind:skFixed;Version:1;Versions:[1];Features:[sfPrepared,sfOwnFinale];VariantKind:svNone),
    (Id:'trap-action';Title:'初見殺しアクション';MiddleTitle:'初見殺しアクション';FixedSmall:'罠を突破する横スクロール';ProgressText:'洞窟・57種類の仕掛け・連動する罠を準備中';Group:sgAction;Order:8;SmallKind:skFixed;Version:19;Versions:[19];Features:[sfPrepared,sfOwnFinale];VariantKind:svTrap)
  );
  GroupTitles:array[TRhythmStyleGroup] of string=('シューティング','ボールアクション','アクション','レース','音楽・演出');
function StyleInfo(Style:TRhythmStyle):TStyleInfo;
begin Result:=Catalog[Style];end;
function StyleHas(Style:TRhythmStyle;Feature:TStyleFeature):Boolean;
begin Result:=Feature in Catalog[Style].Features;end;
function StyleGroupTitle(Group:TRhythmStyleGroup):string;
begin Result:=GroupTitles[Group];end;
function GroupStyleCount(Group:TRhythmStyleGroup):Integer;
var S:TRhythmStyle;
begin Result:=0;for S:=Low(TRhythmStyle) to High(TRhythmStyle) do if Catalog[S].Group=Group then Inc(Result);end;
function GroupStyleAt(Group:TRhythmStyleGroup;Index:Integer):TRhythmStyle;
var S:TRhythmStyle;
begin for S:=Low(TRhythmStyle) to High(TRhythmStyle) do if (Catalog[S].Group=Group) and (Catalog[S].Order=Index) then Exit(S);
  raise EArgumentOutOfRangeException.Create('Style group index');
end;
function GroupStyleIndex(Style:TRhythmStyle):Integer;
begin Result:=Catalog[Style].Order;end;
function StyleSmallCount(Style:TRhythmStyle):Integer;
begin Result:=1;if Catalog[Style].SmallKind<>skFixed then Result:=2;end;
function StyleSmallTitle(Style:TRhythmStyle;Index:Integer):string;
begin if (Index<0) or (Index>=StyleSmallCount(Style)) then raise EArgumentOutOfRangeException.Create('Small category index');
  case Catalog[Style].SmallKind of
    skScroll:if Index=0 then Result:='縦スクロール' else Result:='横スクロール';
    else Result:=Catalog[Style].FixedSmall;
  end;
end;
function StyleId(Style:TRhythmStyle):string;
begin Result:=Catalog[Style].Id;end;
function StyleTitle(Style:TRhythmStyle):string;
begin Result:=Catalog[Style].Title;end;
function TryStyle(const Id:string;out Style:TRhythmStyle):Boolean;
var S:TRhythmStyle;
begin Style:=rsShooting;for S:=Low(TRhythmStyle) to High(TRhythmStyle) do if Catalog[S].Id=Id then begin Style:=S;Exit(True);end;Result:=False;end;
function StylePlanVersion(Style:TRhythmStyle):Integer;
begin Result:=Catalog[Style].Version;end;
function CompatiblePlanVersion(Style:TRhythmStyle;Version:Integer):Boolean;
begin Result:=(Version>=0) and (Version<=255);if Result then Result:=Byte(Version) in Catalog[Style].Versions;end;
function StyleVariant(Style:TRhythmStyle;FireworksRichness:Integer;BossFrequency,GameThreshold:Integer;TrapStage:TTrapStage):Integer;
begin Result:=0;case Catalog[Style].VariantKind of
  svRhythm:Result:=EnsureRange(GameThreshold,-100,100)+101;
  svTrap:Result:=Ord(TrapStage)+1;
  svBoss:if BossFrequency>=0 then Result:=Min(BossFrequency,100)+1;
end;end;
function AudioDensityKey(Style:TRhythmStyle;Value:Integer):Integer;
begin
  // 音ゲーの密度は既存のvariant規約を使う。他の種類の標準値は旧計画キーを維持する。
  Result:=0;
  if not StyleHas(Style,sfThreshold) and (Value<>AUDIO_DEFAULT_DENSITY) then
    Result:=EnsureRange(Value,-100,100)+101;
end;
function BossPeriod(Frequency:Integer):Double;
begin if Frequency<=0 then Exit(0);if Frequency>100 then Frequency:=100;Result:=135.0-0.9*Frequency;end;
function BossFrequencyFromVariant(Variant:Integer):Integer;
begin if Variant=0 then Exit(100);Result:=Variant-1;if Result<0 then Result:=0;if Result>100 then Result:=100;end;
function BossFrequencyText(Frequency:Integer):string;
begin if Frequency<=0 then Exit('0 / 出現なし');Result:=Format('%d / 約%.0f秒',[Frequency,BossPeriod(Frequency)]);end;
end.
