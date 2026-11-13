unit RhythmScene;
// 全種類の描画窓口。MV重ねの種類は透明RGBA、他の種類は単独描画。
interface
uses Vcl.Graphics,RhythmAudio,RhythmMotion,RhythmAnimation,RhythmStyleOps,RhythmStyleRegistry,RhythmStyles,RhythmPlanRef,RhythmPresentation,RhythmLayerBlend,RhythmOverlay;
type
  TRhythmPoint=RhythmMotion.TRhythmPoint;
  // Compatibility facade shared by AviUtl2 and the preview. New animations can
  // compose TAnimationRenderer directly without importing the shooting scene.
  TRhythmRenderer=class
  private
    FRenderer:TAnimationRenderer;
    FChild:TAnimationScene;FOps:TStyleOperations;
    FPresentation:TRhythmPresentationScene;
    FPrimaryRef:TRhythmPlanRef;FEqualizerMode:Integer;
    FWasComposite,FCompositeD2D,FHasAlpha:Boolean;
    FLayers:TRhythmLayerBlend;FOverlay:TRhythmOverlay;
    FStyle:TRhythmStyle;
    FUseD2D:Boolean;
    FBossFrequency:Integer;
    procedure CreateStyle(Style:TRhythmStyle);
    function GetImageCount:Integer;
    function GetNotice:string;
    function GetUseD2D:Boolean;
    procedure SetUseD2D(Value:Boolean);
    function GetLastD2D:Boolean;
  public
    constructor Create;
    destructor Destroy;override;
    procedure ConfigureStyle(Style:TRhythmStyle;const Plan:TRhythmPlanRef;BossFrequency:Integer=-1;EqualizerMode:Integer=-1;
      MarbleBall:TMarbleBallStyle=mbSteel;MarbleStage:TMarbleStageStyle=msWoodWorkshop);
    procedure Render(Target:TBitmap;Audio:TRhythmAudio;Time:Double;Direction:Integer;
      const MessageText:string='';Zoom:Double=1;OffsetX:Double=0;OffsetY:Double=0;OffsetSeconds:Double=0);
    property ImageCount:Integer read GetImageCount;
    property Notice:string read GetNotice;
    property UseD2D:Boolean read GetUseD2D write SetUseD2D;
    property LastUsedD2D:Boolean read GetLastD2D;
    property OutputHasAlpha:Boolean read FHasAlpha;
  end;
function PlayerAt(Time:Double):TRhythmPoint;
function EnemyAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
function BulletAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
function ExplosionOpacity(Age,Lifetime:Double):Double;
implementation
uses RhythmShootingScene,RhythmImageBank,RhythmProduct,RhythmSettings,RhythmEqualizer,RhythmTiming,System.SysUtils,System.Math;
constructor TRhythmRenderer.Create;
begin inherited;FEqualizerMode:=-1;FBossFrequency:=100;FUseD2D:=True;CreateStyle(ProductDefaultStyle);end;
procedure TRhythmRenderer.CreateStyle(Style:TRhythmStyle);
var Images:TAnimationImageBank;Child,Presented:TAnimationScene;NewRenderer:TAnimationRenderer;Ops:TStyleOperations;
begin
  Ops:=StyleOperations(Style);Child:=Ops.CreateScene;
  try Images:=Ops.CreateImages;except Child.Free;raise;end;
  try Presented:=TRhythmPresentationScene.Create(Child,Ops.Activity);except Images.Free;Child.Free;raise;end;
  NewRenderer:=TAnimationRenderer.Create(Presented,Images);
  NewRenderer.UseD2D:=FUseD2D;
  FRenderer.Free;FRenderer:=NewRenderer;FChild:=Child;FOps:=Ops;
  FPresentation:=TRhythmPresentationScene(Presented);FStyle:=Style;
end;
procedure TRhythmRenderer.ConfigureStyle(Style:TRhythmStyle;const Plan:TRhythmPlanRef;BossFrequency,EqualizerMode:Integer;
  MarbleBall:TMarbleBallStyle;MarbleStage:TMarbleStageStyle);
begin
  FBossFrequency:=BossFrequency;
  if FBossFrequency<0 then FBossFrequency:=BossFrequencyFromVariant(Plan.Variant);
  if Style<>FStyle then CreateStyle(Style);
  FPrimaryRef:=Plan;
  FEqualizerMode:=EqualizerMode;
  FOps.SetReference(FChild,Plan);
  if Assigned(FOps.MarbleAppearance) then FOps.MarbleAppearance(FChild,MarbleBall,MarbleStage);
end;
destructor TRhythmRenderer.Destroy;
begin FOverlay.Free;FLayers.Free;FRenderer.Free;inherited;end;
function TRhythmRenderer.GetImageCount:Integer;
begin Result:=FRenderer.ImageCount;end;
function TRhythmRenderer.GetNotice:string;
begin Result:=FRenderer.Notice;end;
function TRhythmRenderer.GetUseD2D:Boolean;
begin Result:=FRenderer.UseD2D;end;
procedure TRhythmRenderer.SetUseD2D(Value:Boolean);
begin FUseD2D:=Value;FRenderer.UseD2D:=Value;end;
function TRhythmRenderer.GetLastD2D:Boolean;
begin if FWasComposite then Result:=FCompositeD2D else Result:=FRenderer.LastUsedD2D;end;
procedure TRhythmRenderer.Render(Target:TBitmap;Audio:TRhythmAudio;Time:Double;Direction:Integer;
  const MessageText:string;Zoom,OffsetX,OffsetY,OffsetSeconds:Double);
var Text:string;EQ,DirectAlpha,Transform:Boolean;Frame:TAnimationFrame;Activity:TEqualizerActivity;OldColor:TColor;Row:Integer;
  AlphaTarget:TBitmap;
begin
  FHasAlpha:=False;FWasComposite:=False;if (Target.Width<1) or (Target.Height<1) then Exit;
  // オフセットは全種類/EQ/透明合成の前に一度だけ適用。音声再生・Plan・カメラの保存値は変更しない。
  Time:=AnimationTime(Time,OffsetSeconds);
  if (Audio<>nil) and (Time<0) then begin
    Target.PixelFormat:=pf32bit;for Row:=0 to Target.Height-1 do FillChar(Target.ScanLine[Row]^,Target.Width*4,0);
    FHasAlpha:=True;FWasComposite:=True;FCompositeD2D:=False;Exit;
  end;
  FOps.SetAudio(FChild,Audio,FBossFrequency);
  FPresentation.Audio:=Audio;Text:='';if Audio=nil then Text:=MessageText;
  EQ:=EqualizerEnabled(FEqualizerMode,FStyle,FPrimaryRef.Version);
  if Audio=nil then begin FRenderer.Render(Target,Time,Direction,Text,Zoom,OffsetX,OffsetY);Exit;end;
  DirectAlpha:=(FOps.DirectAlphaFromVersion>0) and (FPrimaryRef.Version>=FOps.DirectAlphaFromVersion);
  if StyleHas(FStyle,sfTransparent) or DirectAlpha then begin
    OldColor:=FRenderer.ClearColor;
    if Assigned(FOps.Transparency) then FOps.Transparency(FChild,True);
    FPresentation.IncludeEqualizer:=EQ;
    try
      if DirectAlpha then begin
        Transform:=(Zoom<>1) or (OffsetX<>0) or (OffsetY<>0);
        AlphaTarget:=Target;
        if Transform then begin
          if FOverlay=nil then FOverlay:=TRhythmOverlay.Create;
          AlphaTarget:=FOverlay.AlphaBuffer(Target.Width,Target.Height);
        end;
        if FRenderer.TryRenderAlpha(AlphaTarget,Time,Direction) then begin
          if Transform then FOverlay.TransformAlpha(Target,Zoom,OffsetX,OffsetY);
          FHasAlpha:=True;
          Exit;
        end;
      end;
      if FOverlay=nil then FOverlay:=TRhythmOverlay.Create;
      FOverlay.Resize(Target.Width,Target.Height);
      FRenderer.ClearColor:=clBlack;FRenderer.Render(FOverlay.Black,Time,Direction);
      FCompositeD2D:=FRenderer.LastUsedD2D;
      FRenderer.ClearColor:=clWhite;FRenderer.Render(FOverlay.White,Time,Direction);
      FCompositeD2D:=FCompositeD2D and FRenderer.LastUsedD2D;
    finally
      if Assigned(FOps.Transparency) then FOps.Transparency(FChild,False);
      FPresentation.IncludeEqualizer:=False;
      FRenderer.ClearColor:=OldColor;
    end;
    FOverlay.Resolve(Target,Zoom,OffsetX,OffsetY);FHasAlpha:=True;FWasComposite:=True;Exit;
  end;
  if not EQ then begin FRenderer.Render(Target,Time,Direction,Text,Zoom,OffsetX,OffsetY);Exit;end;
  // 単独描画の種類へ共通EQを合成する。同じ種類の背景だけを抽出する。
  if FLayers=nil then FLayers:=TRhythmLayerBlend.Create;
  FLayers.Resize(Target.Width,Target.Height,True,True);
  Frame:=Default(TAnimationFrame);Frame.Time:=Max(0.0,Time);Frame.Width:=Target.Width;Frame.Height:=Target.Height;Frame.Direction:=EnsureRange(Direction,0,1);
  FPresentation.Prepare(Frame);Activity:=FPresentation.Activity(Frame.Time);
  FLayers.BeginBase(Target,Activity,True,FUseD2D);FWasComposite:=True;FCompositeD2D:=FLayers.LastUsedD2D;
  FRenderer.Render(FLayers.Image,Time,Direction);FCompositeD2D:=FCompositeD2D and FRenderer.LastUsedD2D;
  FRenderer.BackgroundOnly:=True;
  try FRenderer.Render(FLayers.Backdrop,Time,Direction);finally FRenderer.BackgroundOnly:=False;end;
  FCompositeD2D:=FCompositeD2D and FRenderer.LastUsedD2D;
  FLayers.ImageOver(Target,FOps.EqualizerPreservesBrightness);FLayers.Transform(Target,Zoom,OffsetX,OffsetY);
end;
function PlayerAt(Time:Double):TRhythmPoint;
begin Result:=RhythmShootingScene.PlayerAt(Time);end;
function EnemyAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
begin Result:=RhythmShootingScene.EnemyAt(Hit,Time);end;
function BulletAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
begin Result:=RhythmShootingScene.BulletAt(Hit,Time);end;
function ExplosionOpacity(Age,Lifetime:Double):Double;
begin Result:=RhythmShootingScene.ExplosionOpacity(Age,Lifetime);end;
end.
