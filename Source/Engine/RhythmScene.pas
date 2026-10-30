unit RhythmScene;
interface
uses Vcl.Graphics,RhythmAudio,RhythmMotion,RhythmDesignTypes,RhythmAnimation,RhythmShootingScene;
type
  TRhythmPoint=RhythmMotion.TRhythmPoint;
  // Compatibility facade shared by AviUtl2 and the preview. New animations can
  // compose TAnimationRenderer directly without importing the shooting scene.
  TRhythmRenderer=class
  private
    FRenderer:TAnimationRenderer;
    FShooting:TShootingAnimation;
    function GetAssetCount:Integer;
    function GetWarning:string;
    function GetUseD2D:Boolean;
    procedure SetUseD2D(Value:Boolean);
    function GetLastD2D:Boolean;
  public
    constructor Create;
    destructor Destroy;override;
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
uses RhythmShootingAssets;
constructor TRhythmRenderer.Create;
var Images:TShootingImageBank;
begin
  inherited;FShooting:=TShootingAnimation.Create;
  try Images:=TShootingImageBank.Create;
  except FShooting.Free;FShooting:=nil;raise;end;
  FRenderer:=TAnimationRenderer.Create(FShooting,Images);
end;
destructor TRhythmRenderer.Destroy;
begin FRenderer.Free;inherited;end;
function TRhythmRenderer.GetAssetCount:Integer;
begin Result:=FRenderer.AssetCount;end;
function TRhythmRenderer.GetWarning:string;
begin Result:=FRenderer.DesignWarning;end;
function TRhythmRenderer.GetUseD2D:Boolean;
begin Result:=FRenderer.UseD2D;end;
procedure TRhythmRenderer.SetUseD2D(Value:Boolean);
begin FRenderer.UseD2D:=Value;end;
function TRhythmRenderer.GetLastD2D:Boolean;
begin Result:=FRenderer.LastUsedD2D;end;
procedure TRhythmRenderer.ApplyDesigns(const Designs:TRhythmDesigns;Force:Boolean);
begin FRenderer.ApplyChoices(Designs,Force);end;
procedure TRhythmRenderer.StandardBackgroundPreview(Target:TBitmap;Direction,Layer:Integer);
begin FRenderer.StandardBackgroundPreview(Target,Direction,Layer);end;
procedure TRhythmRenderer.Render(Target:TBitmap;Audio:TRhythmAudio;Time:Double;Direction:Integer;
  const MessageText:string;Zoom,OffsetX,OffsetY:Double);
var Text:string;
begin
  FShooting.Audio:=Audio;Text:='';if Audio=nil then Text:=MessageText;
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
