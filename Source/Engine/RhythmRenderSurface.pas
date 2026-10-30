unit RhythmRenderSurface;
interface
uses System.Types,Vcl.Graphics,RhythmImageBank,RhythmDesignTypes,RhythmD2D;
type
  TAnimationScaledBuckets=array[0..2] of TBitmap;
  TAnimationRenderSurface=class
  private
    FImages:TAnimationImageBank;
    FScaled:TArray<TAnimationScaledBuckets>;
    FD2D:TRhythmD2D;
    FTarget:TBitmap;
    FD2DActive,FUseD2D,FLastD2D:Boolean;
    procedure ResetScaled;
    function GetCanvas:TCanvas;
  public
    // Takes ownership of Images; the scene never owns rendering resources.
    constructor Create(Images:TAnimationImageBank);
    destructor Destroy;override;
    procedure BeginFrame(Target:TBitmap);
    function EndFrame:Boolean;
    procedure DrawAsset(Index:Integer;const Center:TPoint;W,H:Integer;
      Opacity:Double=1;ForceAlpha:Boolean=False;Bucket:Integer=0);
    procedure ApplyChoices(const Choices:array of TRhythmDesign;Force:Boolean=False);
    property Images:TAnimationImageBank read FImages;
    property Canvas:TCanvas read GetCanvas;
    property D2D:TRhythmD2D read FD2D;
    property D2DActive:Boolean read FD2DActive;
    property UseD2D:Boolean read FUseD2D write FUseD2D;
    property LastUsedD2D:Boolean read FLastD2D;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows;
constructor TAnimationRenderSurface.Create(Images:TAnimationImageBank);
begin
  inherited Create;FImages:=Images;
  if FImages=nil then raise EArgumentNilException.Create('Images');
  FImages.EnsurePrepared;ResetScaled;
  try FD2D:=TRhythmD2D.Create(FImages.Images,FImages.ColorKeys);FUseD2D:=True;
  except FD2D:=nil;FUseD2D:=False;end;
end;
destructor TAnimationRenderSurface.Destroy;
var I,J:Integer;
begin
  FD2D.Free;
  for I:=0 to High(FScaled) do for J:=0 to 2 do FreeAndNil(FScaled[I][J]);
  FImages.Free;inherited;
end;
procedure TAnimationRenderSurface.ResetScaled;
var I,J:Integer;
begin
  for I:=0 to High(FScaled) do for J:=0 to 2 do FreeAndNil(FScaled[I][J]);
  SetLength(FScaled,Length(FImages.Images));
  for I:=0 to High(FScaled) do for J:=0 to 2 do FScaled[I][J]:=Vcl.Graphics.TBitmap.Create;
end;
function TAnimationRenderSurface.GetCanvas:TCanvas;
begin Result:=FTarget.Canvas;end;
procedure TAnimationRenderSurface.BeginFrame(Target:Vcl.Graphics.TBitmap);
begin
  FTarget:=Target;FLastD2D:=False;
  FD2DActive:=FUseD2D and (FD2D<>nil) and FD2D.BeginFrame(Target);
  if not FD2DActive then begin Canvas.Brush.Color:=RGB(7,13,29);Canvas.FillRect(Rect(0,0,Target.Width,Target.Height));end;
end;
function TAnimationRenderSurface.EndFrame:Boolean;
begin
  Result:=True;if not FD2DActive then Exit;FD2DActive:=False;
  if not FD2D.EndFrame then begin FUseD2D:=False;Exit(False);end;
  FLastD2D:=True;
end;
procedure TAnimationRenderSurface.ApplyChoices(const Choices:array of TRhythmDesign;Force:Boolean);
begin
  if not FImages.ApplyChoices(Choices,Force) then Exit;
  ResetScaled;FreeAndNil(FD2D);
  try FD2D:=TRhythmD2D.Create(FImages.Images,FImages.ColorKeys);except FUseD2D:=False;end;
end;

procedure TAnimationRenderSurface.DrawAsset(Index:Integer;const Center:TPoint;
  W,H:Integer;Opacity:Double;ForceAlpha:Boolean;Bucket:Integer);
var Scaled:Vcl.Graphics.TBitmap;Blend:TBlendFunction;Swap:Integer;Canvas:TCanvas;
begin
  if Opacity<=0 then Exit;Opacity:=Min(1.0,Opacity);Canvas:=GetCanvas;
  if FD2DActive then begin FD2D.DrawAsset(Index,Rect(Center.X-W div 2,Center.Y-H div 2,Center.X+W div 2,Center.Y+H div 2),Opacity);Exit;end;
  if ((Opacity<1) or ForceAlpha) and not FImages.AlphaImage[Index].Empty then
  begin
    Blend.BlendOp:=AC_SRC_OVER;Blend.BlendFlags:=0;Blend.SourceConstantAlpha:=Round(Opacity*255);Blend.AlphaFormat:=AC_SRC_ALPHA;
    Winapi.Windows.AlphaBlend(Canvas.Handle,Center.X-W div 2,Center.Y-H div 2,W,H,
      FImages.AlphaImage[Index].Canvas.Handle,0,0,FImages.AlphaImage[Index].Width,FImages.AlphaImage[Index].Height,Blend);Exit;
  end;
  if not FImages.Image[Index].Empty then
  begin
    if ForceAlpha then
      Canvas.StretchDraw(Rect(Center.X-W div 2,Center.Y-H div 2,Center.X+W div 2,Center.Y+H div 2),FImages.Image[Index])
    else
    begin
      Scaled:=FScaled[Index][Bucket];
      if (Scaled.Width<>W) or (Scaled.Height<>H) then
      begin
        if FImages.Image[Index].AlphaFormat<>afIgnored then begin
          Scaled.PixelFormat:=pf32bit;Scaled.SetSize(W,H);Scaled.AlphaFormat:=afPremultiplied;
          for Swap:=0 to H-1 do FillChar(Scaled.ScanLine[Swap]^,W*4,0);
          Scaled.Canvas.StretchDraw(Rect(0,0,W,H),FImages.Image[Index]);
        end else begin
          Scaled.PixelFormat:=pf24bit;Scaled.SetSize(W,H);Scaled.Transparent:=False;
          Scaled.Canvas.Brush.Color:=clFuchsia;Scaled.Canvas.FillRect(Rect(0,0,W,H));
          Scaled.Canvas.StretchDraw(Rect(0,0,W,H),FImages.Image[Index]);
          Scaled.TransparentColor:=clFuchsia;Scaled.Transparent:=True;
        end;
      end;
      Canvas.Draw(Center.X-W div 2,Center.Y-H div 2,Scaled);
    end;
  end
  else begin Canvas.Brush.Color:=clAqua;Canvas.Ellipse(Center.X-W div 2,Center.Y-H div 2,Center.X+W div 2,Center.Y+H div 2);end;
end;
end.
