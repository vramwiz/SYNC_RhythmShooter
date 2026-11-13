unit RhythmStyleOps;
// 専用ユニットと共通実行部の契約。生成したScene/ImagesはRendererへ所有権を渡す。
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmAnimation,RhythmImageBank,RhythmEqualizer,RhythmStyles;
type
  TStylePrepareContext=record
    Audio:TRhythmAudio;
    Direction,Variant:Integer;
    Cancel:TFunc<Boolean>;
    Progress:TProc<Integer>;
    procedure CheckCancel;
    procedure SetStage(Value:Integer);
  end;
  TStyleCreateScene=function:TAnimationScene;
  TStyleSetReference=procedure(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
  TStyleSetAudio=procedure(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
  TStylePreparePlan=procedure(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
  TStyleLoadAudio=function(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
  TStyleCreateImages=function:TAnimationImageBank;
  TStyleTransparency=procedure(Scene:TAnimationScene;Value:Boolean);
  TStyleMarbleAppearance=procedure(Scene:TAnimationScene;Ball:TMarbleBallStyle;Stage:TMarbleStageStyle);
  TStyleActivity=function(Scene:TAnimationScene;Time:Double;out Value:TEqualizerActivity):Boolean;
  TStyleOperations=record
    UnitName:string;
    CreateScene:TStyleCreateScene;
    SetReference:TStyleSetReference;
    SetAudio:TStyleSetAudio;
    Prepare:TStylePreparePlan;
    LoadAudio:TStyleLoadAudio;
    CreateImages:TStyleCreateImages;
    Transparency:TStyleTransparency;
    MarbleAppearance:TStyleMarbleAppearance;
    DirectAlphaFromVersion:Integer; // 0は従来の描画経路。指定版からは最初から背景を透過して描く。
    Activity:TStyleActivity;
    EqualizerPreservesBrightness:Boolean; // 元の明るさを保ち、EQの光だけを背景へ加える。
  end;
function EmptyStyleImages:TAnimationImageBank;
implementation
procedure TStylePrepareContext.CheckCancel;
begin if Assigned(Cancel) and Cancel() then Abort;end;
procedure TStylePrepareContext.SetStage(Value:Integer);
begin if Assigned(Progress) then Progress(Value);end;
function EmptyStyleImages:TAnimationImageBank;
begin Result:=TAnimationImageBank.Create(0);end;
end.
