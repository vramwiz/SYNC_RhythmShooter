unit RhythmRenderSurface;
// GDIとDirect2Dの描画入口を揃え、シーン側の座標を共通化する。
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
    FAlphaLayer,FAlphaMask:TBitmap;
    FD2DActive,FUseD2D,FLastD2D:Boolean;
    // GDI用の形状被覆マスク。既定Opacity=1の描画経路は変更しない。
    procedure BlendPrimitive(Kind:Integer;X1,Y1,X2,Y2,Stroke:Double;Color:TColor;Opacity:Double);
    procedure ResetScaled;
    function GetCanvas:TCanvas;
  public
    // Takes ownership of Images; the scene never owns rendering resources.
    constructor Create(Images:TAnimationImageBank);
    destructor Destroy;override;
    procedure BeginFrame(Target:TBitmap;ClearColor:TColor=$001D0D07);
    procedure DrawViewportMatte(Left,Top:Double;W,H:Integer;Color:TColor);
    function EndFrame:Boolean;
    procedure DrawAsset(Index:Integer;const Center:TPoint;W,H:Integer;
      Opacity:Double=1;ForceAlpha:Boolean=False;Bucket:Integer=0);
    procedure Circle(X,Y,Radius:Double;Color:TColor;Filled:Boolean;Stroke:Double=1;Opacity:Double=1);
    procedure Line(X1,Y1,X2,Y2:Double;Color:TColor;Stroke:Double=1;Opacity:Double=1);
    procedure FillRect(X1,Y1,X2,Y2:Double;Color:TColor;Opacity:Double=1);
    // 不透明な四辺形だけを追加。既存プリミティブ・alpha経路には触れない。
    procedure FillQuad(const A,B,C,D:TPointF;Color:TColor);
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
  FD2D.Free;FAlphaLayer.Free;FAlphaMask.Free;
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
procedure TAnimationRenderSurface.BeginFrame(Target:Vcl.Graphics.TBitmap;ClearColor:TColor);
begin
  FTarget:=Target;FLastD2D:=False;
  FD2DActive:=FUseD2D and (FD2D<>nil) and FD2D.BeginFrame(Target,ClearColor);
  if not FD2DActive then begin Canvas.Brush.Color:=ClearColor;Canvas.FillRect(Rect(0,0,Target.Width,Target.Height));end;
end;
procedure TAnimationRenderSurface.DrawViewportMatte(Left,Top:Double;W,H:Integer;Color:TColor);
begin if Left>0 then begin FillRect(0,0,Left,H,Color);FillRect(W-Left,0,W,H,Color);end;
  if Top>0 then begin FillRect(0,0,W,Top,Color);FillRect(0,H-Top,W,H,Color);end;
end;
function TAnimationRenderSurface.EndFrame:Boolean;
begin
  Result:=True;if not FD2DActive then Exit;FD2DActive:=False;
  if not FD2D.EndFrame then begin FUseD2D:=False;Exit(False);end;
  FLastD2D:=True;
end;
procedure TAnimationRenderSurface.Circle(X,Y,Radius:Double;Color:TColor;Filled:Boolean;Stroke,Opacity:Double);
begin
  if (Radius<=0) or (Opacity<=0) then Exit;
  if FD2DActive then begin FD2D.Circle(X,Y,Radius,Color,Filled,Stroke,Opacity);Exit;end;
  if Opacity<1 then begin BlendPrimitive(3-Ord(Filled),X,Y,Radius,0,Stroke,Color,Opacity);Exit;end;
  Canvas.Pen.Color:=Color;Canvas.Pen.Width:=Max(1,Round(Stroke));Canvas.Brush.Color:=Color;
  if Filled then begin Canvas.Pen.Style:=psClear;Canvas.Brush.Style:=bsSolid;end else begin Canvas.Pen.Style:=psSolid;Canvas.Brush.Style:=bsClear;end;
  Canvas.Ellipse(Round(X-Radius),Round(Y-Radius),Round(X+Radius),Round(Y+Radius));Canvas.Pen.Width:=1;Canvas.Pen.Style:=psSolid;Canvas.Brush.Style:=bsSolid;
end;
procedure TAnimationRenderSurface.Line(X1,Y1,X2,Y2:Double;Color:TColor;Stroke,Opacity:Double);
begin
  if Opacity<=0 then Exit;
  if FD2DActive then begin FD2D.Line(X1,Y1,X2,Y2,Color,Stroke,Opacity);Exit;end;
  if Opacity<1 then begin BlendPrimitive(1,X1,Y1,X2,Y2,Stroke,Color,Opacity);Exit;end;
  Canvas.Pen.Style:=psSolid;Canvas.Pen.Color:=Color;Canvas.Pen.Width:=Max(1,Round(Stroke));
  Canvas.MoveTo(Round(X1),Round(Y1));Canvas.LineTo(Round(X2),Round(Y2));Canvas.Pen.Width:=1;
end;
procedure TAnimationRenderSurface.FillRect(X1,Y1,X2,Y2:Double;Color:TColor;Opacity:Double);
begin
  if (X2<=X1) or (Y2<=Y1) or (Opacity<=0) then Exit;
  if FD2DActive then begin FD2D.FillRect(X1,Y1,X2,Y2,Color,Opacity);Exit;end;
  if Opacity<1 then begin BlendPrimitive(0,X1,Y1,X2,Y2,1,Color,Opacity);Exit;end;
  Canvas.Brush.Style:=bsSolid;Canvas.Brush.Color:=Color;Canvas.FillRect(Rect(Round(X1),Round(Y1),Round(X2),Round(Y2)));
end;
procedure TAnimationRenderSurface.FillQuad(const A,B,C,D:TPointF;Color:TColor);
var Points:array[0..3] of TPoint;
begin
  if FD2DActive then begin FD2D.FillQuad(A,B,C,D,Color);Exit;end;
  Points[0]:=Point(Round(A.X),Round(A.Y));Points[1]:=Point(Round(B.X),Round(B.Y));
  Points[2]:=Point(Round(C.X),Round(C.Y));Points[3]:=Point(Round(D.X),Round(D.Y));
  Canvas.Pen.Style:=psClear;Canvas.Brush.Style:=bsSolid;Canvas.Brush.Color:=Color;
  Canvas.Polygon(Points);Canvas.Pen.Style:=psSolid;
end;
procedure TAnimationRenderSurface.BlendPrimitive(Kind:Integer;X1,Y1,X2,Y2,Stroke:Double;Color:TColor;Opacity:Double);
type PPixel=^TPixel;TPixel=packed record B,G,R,A:Byte;end;
var L,T,R,B,W,H,X,Y,Pad:Integer;Mask,Pixel:PPixel;C:Longint;Blend:TBlendFunction;Canvas:TCanvas;
begin
  if (FTarget=nil) or (Opacity<=0) then Exit;
  Pad:=Ceil(Max(1.0,Stroke)*0.5)+2;
  if Kind>=2 then begin
    L:=Floor(X1-X2)-Pad;R:=Ceil(X1+X2)+Pad;
    T:=Floor(Y1-X2)-Pad;B:=Ceil(Y1+X2)+Pad;
  end else begin
    L:=Floor(Min(X1,X2))-Pad;R:=Ceil(Max(X1,X2))+Pad;
    T:=Floor(Min(Y1,Y2))-Pad;B:=Ceil(Max(Y1,Y2))+Pad;
  end;
  L:=Max(0,L);T:=Max(0,T);R:=Min(FTarget.Width,R);B:=Min(FTarget.Height,B);
  W:=R-L;H:=B-T;if (W<=0) or (H<=0) then Exit;
  // 小さい形状領域だけを再利用し、黒背景ではなく被覆マスクで透過する。
  if FAlphaLayer=nil then begin
    FAlphaLayer:=Vcl.Graphics.TBitmap.Create;FAlphaLayer.PixelFormat:=pf32bit;
    FAlphaMask:=Vcl.Graphics.TBitmap.Create;FAlphaMask.PixelFormat:=pf32bit;
  end;
  if (FAlphaLayer.Width<W) or (FAlphaLayer.Height<H) then begin
    FAlphaLayer.SetSize(Max(W,FAlphaLayer.Width),Max(H,FAlphaLayer.Height));
    FAlphaMask.SetSize(FAlphaLayer.Width,FAlphaLayer.Height);
  end;
  Canvas:=FAlphaMask.Canvas;Canvas.Brush.Style:=bsSolid;Canvas.Brush.Color:=clBlack;
  Canvas.FillRect(Rect(0,0,W,H));Canvas.Pen.Color:=clWhite;Canvas.Pen.Width:=Max(1,Round(Stroke));
  Canvas.Pen.Style:=psSolid;Canvas.Brush.Color:=clWhite;
  case Kind of
    0:Canvas.FillRect(Rect(Round(X1)-L,Round(Y1)-T,Round(X2)-L,Round(Y2)-T));
    1:begin Canvas.MoveTo(Round(X1)-L,Round(Y1)-T);Canvas.LineTo(Round(X2)-L,Round(Y2)-T);end;
    2,3:begin
      if Kind=2 then Canvas.Pen.Style:=psClear else Canvas.Brush.Style:=bsClear;
      Canvas.Ellipse(Round(X1-X2)-L,Round(Y1-X2)-T,Round(X1+X2)-L,Round(Y1+X2)-T);
    end;
  end;
  GdiFlush;
  C:=ColorToRGB(Color);
  for Y:=0 to H-1 do begin Mask:=FAlphaMask.ScanLine[Y];Pixel:=FAlphaLayer.ScanLine[Y];
    for X:=0 to W-1 do begin
      Pixel.A:=Mask.B;Pixel.B:=Round(GetBValue(C)*Pixel.A/255);
      Pixel.G:=Round(GetGValue(C)*Pixel.A/255);Pixel.R:=Round(GetRValue(C)*Pixel.A/255);
      Inc(Mask);Inc(Pixel);
    end;
  end;
  Blend.BlendOp:=AC_SRC_OVER;Blend.BlendFlags:=0;Blend.SourceConstantAlpha:=Round(EnsureRange(Opacity,0.0,1.0)*255);Blend.AlphaFormat:=AC_SRC_ALPHA;
  Winapi.Windows.AlphaBlend(FTarget.Canvas.Handle,L,T,W,H,FAlphaLayer.Canvas.Handle,0,0,W,H,Blend);
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
