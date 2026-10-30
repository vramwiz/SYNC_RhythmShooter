unit RhythmAnimation;
interface
uses Vcl.Graphics,RhythmRenderSurface,RhythmImageBank,RhythmDesignTypes;
type
  TAnimationFrame=record
    Time:Double;
    Width,Height,Direction:Integer;
  end;
  TAnimationScene=class
  public
    // Scene-owned source data is borrowed and must outlive Prepare/Draw.
    // Prepare may cache a plan; Draw must reconstruct any absolute Time.
    procedure Prepare(const Frame:TAnimationFrame);virtual;abstract;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);virtual;abstract;
    function Notice:string;virtual;
  end;
  TAnimationRenderer=class
  private
    FScene:TAnimationScene;
    FSurface:TAnimationRenderSurface;
    FTransform:TBitmap;
    function GetAssetCount:Integer;
    function GetWarning:string;
    function GetUseD2D:Boolean;
    procedure SetUseD2D(Value:Boolean);
    function GetLastD2D:Boolean;
  public
    // Takes ownership of both scene and image bank. No game or audio dependency.
    constructor Create(Scene:TAnimationScene;Images:TAnimationImageBank);
    destructor Destroy;override;
    procedure Render(Target:TBitmap;Time:Double;Direction:Integer;const MessageText:string='';
      Zoom:Double=1;OffsetX:Double=0;OffsetY:Double=0);
    procedure ApplyChoices(const Choices:array of TRhythmDesign;Force:Boolean=False);
    procedure StandardBackgroundPreview(Target:TBitmap;Direction,Layer:Integer);
    property AssetCount:Integer read GetAssetCount;
    property DesignWarning:string read GetWarning;
    property UseD2D:Boolean read GetUseD2D write SetUseD2D;
    property LastUsedD2D:Boolean read GetLastD2D;
  end;
implementation
uses System.SysUtils,System.Types,System.Math,Winapi.Windows,RhythmParallax;
function TAnimationScene.Notice:string;
begin Result:='';end;
constructor TAnimationRenderer.Create(Scene:TAnimationScene;Images:TAnimationImageBank);
begin
  inherited Create;FScene:=Scene;FSurface:=TAnimationRenderSurface.Create(Images);
  if FScene=nil then raise EArgumentNilException.Create('Scene');
  FTransform:=Vcl.Graphics.TBitmap.Create;FTransform.PixelFormat:=pf32bit;
end;
destructor TAnimationRenderer.Destroy;
begin FTransform.Free;FScene.Free;FSurface.Free;inherited;end;
function TAnimationRenderer.GetAssetCount:Integer;
begin Result:=FSurface.Images.AssetCount;end;
function TAnimationRenderer.GetWarning:string;
begin Result:=FSurface.Images.DesignWarning;end;
function TAnimationRenderer.GetUseD2D:Boolean;
begin Result:=FSurface.UseD2D;end;
procedure TAnimationRenderer.SetUseD2D(Value:Boolean);
begin FSurface.UseD2D:=Value;end;
function TAnimationRenderer.GetLastD2D:Boolean;
begin Result:=FSurface.LastUsedD2D;end;
procedure TAnimationRenderer.ApplyChoices(const Choices:array of TRhythmDesign;Force:Boolean);
begin FSurface.ApplyChoices(Choices,Force);end;
procedure TAnimationRenderer.StandardBackgroundPreview(Target:Vcl.Graphics.TBitmap;Direction,Layer:Integer);
begin DrawParallax(Target.Canvas,FSurface.Images,nil,False,0,Target.Width,Target.Height,Direction,Layer,True);end;
procedure TAnimationRenderer.Render(Target:Vcl.Graphics.TBitmap;Time:Double;Direction:Integer;
  const MessageText:string;Zoom,OffsetX,OffsetY:Double);
var I,J,Width,Height:Integer;C:TCanvas;Text:string;Frame:TAnimationFrame;
begin
  Width:=Target.Width;Height:=Target.Height;if (Width<1) or (Height<1) then Exit;
  if (Abs(Zoom-1)>1E-8) or (Abs(OffsetX)>1E-8) or (Abs(OffsetY)>1E-8) then begin
    FTransform.SetSize(Width,Height);Render(FTransform,Time,Direction,MessageText,1,0,0);
    Target.Canvas.Brush.Color:=clBlack;Target.Canvas.FillRect(Rect(0,0,Width,Height));
    I:=Round((Width-Width*Zoom)/2+OffsetX);J:=Round((Height-Height*Zoom)/2+OffsetY);
    Target.Canvas.StretchDraw(Rect(I,J,I+Round(Width*Zoom),J+Round(Height*Zoom)),FTransform);Exit;
  end;
  Frame.Time:=Max(0.0,Time);Frame.Direction:=EnsureRange(Direction,0,1);
  Frame.Width:=Width;Frame.Height:=Height;FScene.Prepare(Frame);
  FSurface.BeginFrame(Target);FScene.Draw(FSurface,Frame);
  if not FSurface.EndFrame then begin Render(Target,Time,Direction,MessageText);Exit;end;
  C:=Target.Canvas;
  C.Font.Name:='Segoe UI';C.Font.Size:=Max(9,Round(Min(Width,Height)/60));C.Font.Color:=RGB(184,212,235);C.Brush.Style:=bsClear;
  if DesignWarning<>'' then Text:='素材が見つからないため標準表示: '+DesignWarning else if FScene.Notice<>'' then Text:=FScene.Notice else Text:=MessageText;
  if Text<>'' then C.TextOut(16,14,Text);C.Brush.Style:=bsSolid;
end;
end.
