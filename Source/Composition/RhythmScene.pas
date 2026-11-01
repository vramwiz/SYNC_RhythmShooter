unit RhythmScene;
interface
uses Vcl.Graphics,RhythmAudio,RhythmMotion,RhythmDesignTypes,RhythmAnimation,RhythmShootingScene,RhythmBallScene,RhythmFireworksScene,RhythmRunnerScene,RhythmBreakoutScene,RhythmRaceScene,RhythmBombScene,RhythmFightingScene,RhythmMiningScene,RhythmTrainScene,RhythmNavalScene,RhythmStyles,RhythmPlanRef;
type
  TRhythmPoint=RhythmMotion.TRhythmPoint;
  // Compatibility facade shared by AviUtl2 and the preview. New animations can
  // compose TAnimationRenderer directly without importing the shooting scene.
  TRhythmRenderer=class
  private
    FRenderer:TAnimationRenderer;
    FShooting:TShootingAnimation;
    FBall:TBallAnimation;
    FFireworks:TFireworksAnimation;
    FRunner:TRunnerAnimation;
    FBreakout:TBreakoutAnimation;
    FRace:TRaceAnimation;FBombAction:TBombActionAnimation;
    FFighting:TFightingAnimation;FMining:TMiningAnimation;FTrain:TTrainAnimation;FNaval:TNavalAnimation;
    FStyle:TRhythmStyle;
    FChoices:TRhythmDesigns;
    FUseD2D:Boolean;
    FBossFrequency:Integer;
    procedure CreateStyle(Style:TRhythmStyle);
    function GetAssetCount:Integer;
    function GetWarning:string;
    function GetUseD2D:Boolean;
    procedure SetUseD2D(Value:Boolean);
    function GetLastD2D:Boolean;
  public
    constructor Create;
    destructor Destroy;override;
    procedure ConfigureStyle(Style:TRhythmStyle;const Plan:TRhythmPlanRef;BossFrequency:Integer=-1);
    procedure ApplyDesigns(const Designs:TRhythmDesigns;Force:Boolean=False);
    procedure StandardBackgroundPreview(Target:TBitmap;Direction,Layer:Integer);
    procedure Render(Target:TBitmap;Audio:TRhythmAudio;Time:Double;Direction:Integer;
      const MessageText:string='';Zoom:Double=1;OffsetX:Double=0;OffsetY:Double=0);
    property AssetCount:Integer read GetAssetCount;
    property DesignWarning:string read GetWarning;
    property UseD2D:Boolean read GetUseD2D write SetUseD2D;
    property LastUsedD2D:Boolean read GetLastD2D;
  end;
function PlayerAt(Time:Double):TRhythmPoint;
function EnemyAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
function BulletAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
function ExplosionOpacity(Age,Lifetime:Double):Double;
implementation
uses RhythmShootingAssets,RhythmImageBank,RhythmProduct;
constructor TRhythmRenderer.Create;
begin inherited;FBossFrequency:=100;FUseD2D:=True;CreateStyle(ProductDefaultStyle);end;
procedure TRhythmRenderer.CreateStyle(Style:TRhythmStyle);
var Images:TAnimationImageBank;Scene:TAnimationScene;NewRenderer:TAnimationRenderer;Shooting:TShootingAnimation;Ball:TBallAnimation;Fireworks:TFireworksAnimation;Runner:TRunnerAnimation;Breakout:TBreakoutAnimation;Race:TRaceAnimation;BombAction:TBombActionAnimation;Fighting:TFightingAnimation;Mining:TMiningAnimation;Train:TTrainAnimation;Naval:TNavalAnimation;
begin
  Shooting:=nil;Ball:=nil;Fireworks:=nil;Runner:=nil;Breakout:=nil;Race:=nil;BombAction:=nil;Fighting:=nil;Mining:=nil;Train:=nil;Naval:=nil;
  if Style=rsShooting then begin Shooting:=TShootingAnimation.Create;Scene:=Shooting;
    try Images:=TShootingImageBank.Create;except Scene.Free;raise;end;
  end else begin
    if Style=rsFireworks then begin Fireworks:=TFireworksAnimation.Create;Scene:=Fireworks;end
    else if Style=rsRunner then begin Runner:=TRunnerAnimation.Create;Scene:=Runner;end
    else if Style=rsBreakout then begin Breakout:=TBreakoutAnimation.Create;Scene:=Breakout;end
    else if Style=rsRace then begin Race:=TRaceAnimation.Create;Scene:=Race;end
    else if Style=rsBombAction then begin BombAction:=TBombActionAnimation.Create;Scene:=BombAction;end
    else if Style=rsFighting then begin Fighting:=TFightingAnimation.Create;Scene:=Fighting;end
    else if Style=rsMining then begin Mining:=TMiningAnimation.Create;Scene:=Mining;end
    else if Style=rsTrain then begin Train:=TTrainAnimation.Create;Scene:=Train;end
    else if Style=rsNaval then begin Naval:=TNavalAnimation.Create;Scene:=Naval;end
    else begin Ball:=TBallAnimation.Create;Scene:=Ball;end;
    try if Style=rsBreakout then Images:=TShootingImageBank.Create else Images:=TAnimationImageBank.Create([],0);except Scene.Free;raise;end;
  end;
  NewRenderer:=TAnimationRenderer.Create(Scene,Images);
  try NewRenderer.UseD2D:=FUseD2D;if Style in [rsShooting,rsBreakout] then NewRenderer.ApplyChoices(FChoices);except NewRenderer.Free;raise;end;
  FRenderer.Free;FRenderer:=NewRenderer;FShooting:=Shooting;FBall:=Ball;FFireworks:=Fireworks;FRunner:=Runner;FBreakout:=Breakout;FRace:=Race;FBombAction:=BombAction;FFighting:=Fighting;FMining:=Mining;FTrain:=Train;FNaval:=Naval;FStyle:=Style;
end;
procedure TRhythmRenderer.ConfigureStyle(Style:TRhythmStyle;const Plan:TRhythmPlanRef;BossFrequency:Integer);
begin FBossFrequency:=BossFrequency;if FBossFrequency<0 then FBossFrequency:=BossFrequencyFromVariant(Plan.Variant);if Style<>FStyle then CreateStyle(Style);if FBall<>nil then FBall.SetReference(Plan);if FFireworks<>nil then FFireworks.SetReference(Plan);if FRunner<>nil then FRunner.SetReference(Plan);if FBreakout<>nil then FBreakout.SetReference(Plan);if FRace<>nil then FRace.SetReference(Plan);if FBombAction<>nil then FBombAction.SetReference(Plan);if FFighting<>nil then FFighting.SetReference(Plan);if FMining<>nil then FMining.SetReference(Plan);if FTrain<>nil then FTrain.SetReference(Plan);if FNaval<>nil then FNaval.SetReference(Plan);end;
destructor TRhythmRenderer.Destroy;
begin FRenderer.Free;inherited;end;
function TRhythmRenderer.GetAssetCount:Integer;
begin Result:=FRenderer.AssetCount;end;
function TRhythmRenderer.GetWarning:string;
begin Result:=FRenderer.DesignWarning;end;
function TRhythmRenderer.GetUseD2D:Boolean;
begin Result:=FRenderer.UseD2D;end;
procedure TRhythmRenderer.SetUseD2D(Value:Boolean);
begin FUseD2D:=Value;FRenderer.UseD2D:=Value;end;
function TRhythmRenderer.GetLastD2D:Boolean;
begin Result:=FRenderer.LastUsedD2D;end;
procedure TRhythmRenderer.ApplyDesigns(const Designs:TRhythmDesigns;Force:Boolean);
begin FChoices:=Designs;if FStyle in [rsShooting,rsBreakout] then FRenderer.ApplyChoices(Designs,Force);end;
procedure TRhythmRenderer.StandardBackgroundPreview(Target:TBitmap;Direction,Layer:Integer);
begin if FStyle=rsShooting then FRenderer.StandardBackgroundPreview(Target,Direction,Layer) else begin Target.Canvas.Brush.Color:=clBlack;Target.Canvas.FillRect(Target.Canvas.ClipRect);end;end;
procedure TRhythmRenderer.Render(Target:TBitmap;Audio:TRhythmAudio;Time:Double;Direction:Integer;
  const MessageText:string;Zoom,OffsetX,OffsetY:Double);
var Text:string;
begin
  if (FStyle=rsShooting) and (Audio<>nil) then Audio.SetBossFrequency(FBossFrequency);
  if FShooting<>nil then FShooting.Audio:=Audio;if FBall<>nil then FBall.Audio:=Audio;if FFireworks<>nil then FFireworks.Audio:=Audio;if FRunner<>nil then FRunner.Audio:=Audio;if FBreakout<>nil then FBreakout.Audio:=Audio;if FRace<>nil then FRace.Audio:=Audio;if FBombAction<>nil then FBombAction.Audio:=Audio;if FFighting<>nil then FFighting.Audio:=Audio;if FMining<>nil then FMining.Audio:=Audio;if FTrain<>nil then FTrain.Audio:=Audio;if FNaval<>nil then FNaval.Audio:=Audio;Text:='';if Audio=nil then Text:=MessageText;
  FRenderer.Render(Target,Time,Direction,Text,Zoom,OffsetX,OffsetY);
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
