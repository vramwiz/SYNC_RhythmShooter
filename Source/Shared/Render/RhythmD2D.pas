unit RhythmD2D;
// Direct2D描画バックエンド。計画・音解析・時刻更新は扱わない。
interface
uses System.Types, Vcl.Graphics, Winapi.D2D1;
type
  TRhythmD2D=class
  private
    FFactory:ID2D1Factory;
    FTarget:ID2D1DCRenderTarget;
    FBitmaps:array of ID2D1Bitmap;
    FBrush:ID2D1SolidColorBrush;
    FStarBrush:array[0..2] of ID2D1SolidColorBrush;
    FStarTrailBrush:ID2D1SolidColorBrush;
  public
    constructor Create(const Assets:array of TBitmap;const ColorKeys:TArray<Boolean> = nil;Premultiplied:Boolean=False);
    function BeginFrame(Target:TBitmap;ClearColor:TColor=$001D0D07;Transparent:Boolean=False):Boolean;
    function EndFrame:Boolean;
    procedure DrawAsset(Index:Integer;const Bounds:TRect;Opacity:Single=1);
    procedure Ring(X,Y,Radius:Single);
    procedure Circle(X,Y,Radius:Single;Color:TColor;Filled:Boolean;Stroke:Single=1;Opacity:Single=1);
    procedure Line(X1,Y1,X2,Y2:Single;Color:TColor;Stroke:Single=1;Opacity:Single=1);
    procedure FillRect(X1,Y1,X2,Y2:Single;Color:TColor;Opacity:Single=1);
    // 車体などの不透明面と、ライトなどの半透明面に使う。
    procedure FillQuad(const A,B,C,D:TPointF;Color:TColor;Opacity:Double=1);
    procedure Star(X,Y,Radius,Trail:Single;Layer,Direction:Integer);
  end;
implementation
uses Winapi.Windows, Winapi.DXGIFormat, System.SysUtils, System.Math;
constructor TRhythmD2D.Create(const Assets:array of Vcl.Graphics.TBitmap;const ColorKeys:TArray<Boolean>;Premultiplied:Boolean);
var Props:TD2D1RenderTargetProperties;BitmapProps:TD2D1BitmapProperties;
  I,X,Y:Integer;Temp:Vcl.Graphics.TBitmap;Pixels:TBytes;Source,Destination:PByte;
  Size:TD2D1SizeU;Color:TD2D1ColorF;AlphaMode:TD2D1AlphaMode;
  function UsesColorKey(Index:Integer):Boolean;
  begin
    if Length(ColorKeys)=0 then Result:=(Index<>0) and (Index<>3)
    else if Index<Length(ColorKeys) then Result:=ColorKeys[Index] else Result:=False;
  end;
begin
  inherited Create;
  if D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED,ID2D1Factory,nil,FFactory)<0 then
    raise Exception.Create('D2D factory unavailable');
  AlphaMode:=D2D1_ALPHA_MODE_IGNORE;
  if Premultiplied then AlphaMode:=D2D1_ALPHA_MODE_PREMULTIPLIED;
  Props:=D2D1RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT,
    D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,AlphaMode),96,96);
  if FFactory.CreateDCRenderTarget(Props,FTarget)<0 then raise Exception.Create('D2D DC target unavailable');
  BitmapProps:=D2D1BitmapProperties(D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,D2D1_ALPHA_MODE_PREMULTIPLIED),96,96);
  SetLength(FBitmaps,Length(Assets));Temp:=Vcl.Graphics.TBitmap.Create;
  try
    for I:=0 to High(Assets) do
    begin
      if Assets[I].Empty then Continue;Temp.Assign(Assets[I]);Temp.PixelFormat:=pf32bit;
      SetLength(Pixels,Temp.Width*Temp.Height*4);Destination:=@Pixels[0];
      for Y:=0 to Temp.Height-1 do
      begin
        Source:=Temp.ScanLine[Y];
        for X:=0 to Temp.Width-1 do
        begin
          if Temp.AlphaFormat<>afIgnored then begin
            Destination[0]:=Source[0];Destination[1]:=Source[1];Destination[2]:=Source[2];Destination[3]:=Source[3];
          end else if UsesColorKey(I) and (Source[0]=255) and (Source[1]=0) and (Source[2]=255) then
          begin Destination[0]:=0;Destination[1]:=0;Destination[2]:=0;Destination[3]:=0;end
          else begin Destination[0]:=Source[0];Destination[1]:=Source[1];Destination[2]:=Source[2];Destination[3]:=255;end;
          Inc(Source,4);Inc(Destination,4);
        end;
      end;
      Size.width:=Temp.Width;Size.height:=Temp.Height;
      if FTarget.CreateBitmap(Size,@Pixels[0],Temp.Width*4,BitmapProps,FBitmaps[I])<0 then
        raise Exception.Create('D2D sprite upload failed');
    end;
  finally Temp.Free;end;
  Color.r:=1;Color.g:=0.667;Color.b:=0.259;Color.a:=1;
  if FTarget.CreateSolidColorBrush(Color,nil,FBrush)<0 then raise Exception.Create('D2D brush unavailable');
  for I:=0 to 2 do begin
    Color.r:=(42+I*25)/255;Color.g:=(62+I*35)/255;Color.b:=(88+I*44)/255;
    if FTarget.CreateSolidColorBrush(Color,nil,FStarBrush[I])<0 then raise Exception.Create('D2D star brush unavailable');
  end;
  Color.r:=60/255;Color.g:=100/255;Color.b:=153/255;Color.a:=0.45;
  if FTarget.CreateSolidColorBrush(Color,nil,FStarTrailBrush)<0 then raise Exception.Create('D2D star trail brush unavailable');
end;
function TRhythmD2D.BeginFrame(Target:Vcl.Graphics.TBitmap;ClearColor:TColor;Transparent:Boolean):Boolean;
var Color:TD2D1ColorF;
begin
  Result:=FTarget.BindDC(Target.Canvas.Handle,Rect(0,0,Target.Width,Target.Height))>=0;
  if not Result then Exit;
  FTarget.BeginDraw;ClearColor:=ColorToRGB(ClearColor);Color.r:=(ClearColor and 255)/255;Color.g:=((ClearColor shr 8) and 255)/255;Color.b:=((ClearColor shr 16) and 255)/255;
  Color.a:=Ord(not Transparent);FTarget.Clear(Color);
end;
function TRhythmD2D.EndFrame:Boolean;
begin Result:=FTarget.EndDraw()>=0;end;
procedure TRhythmD2D.DrawAsset(Index:Integer;const Bounds:TRect;Opacity:Single);
var R:TD2D1RectF;
begin
  if (Index<0) or (Index>High(FBitmaps)) or (FBitmaps[Index]=nil) then Exit;
  R.left:=Bounds.Left;R.top:=Bounds.Top;R.right:=Bounds.Right;R.bottom:=Bounds.Bottom;
  FTarget.DrawBitmap(FBitmaps[Index],@R,Opacity,D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
end;
procedure TRhythmD2D.Ring(X,Y,Radius:Single);
var Shape:TD2D1Ellipse;
begin Shape.point.x:=X;Shape.point.y:=Y;Shape.radiusX:=Radius;Shape.radiusY:=Radius;FTarget.DrawEllipse(Shape,FBrush,1);end;
procedure TRhythmD2D.Circle(X,Y,Radius:Single;Color:TColor;Filled:Boolean;Stroke,Opacity:Single);
var Shape:TD2D1Ellipse;C:TD2D1ColorF;V:Longint;
begin
  V:=ColorToRGB(Color);C.r:=(V and 255)/255;C.g:=((V shr 8) and 255)/255;C.b:=((V shr 16) and 255)/255;C.a:=Opacity;FBrush.SetColor(C);
  Shape.point.x:=X;Shape.point.y:=Y;Shape.radiusX:=Radius;Shape.radiusY:=Radius;
  if Filled then FTarget.FillEllipse(Shape,FBrush) else FTarget.DrawEllipse(Shape,FBrush,Stroke);
end;
procedure TRhythmD2D.Line(X1,Y1,X2,Y2:Single;Color:TColor;Stroke,Opacity:Single);
var A,B:TD2DPoint2f;C:TD2D1ColorF;V:Longint;
begin
  V:=ColorToRGB(Color);C.r:=(V and 255)/255;C.g:=((V shr 8) and 255)/255;C.b:=((V shr 16) and 255)/255;C.a:=Opacity;FBrush.SetColor(C);
  A.x:=X1;A.y:=Y1;B.x:=X2;B.y:=Y2;FTarget.DrawLine(A,B,FBrush,Stroke);
end;
procedure TRhythmD2D.FillRect(X1,Y1,X2,Y2:Single;Color:TColor;Opacity:Single);
var Bounds:TD2D1RectF;C:TD2D1ColorF;V:Longint;
begin
  V:=ColorToRGB(Color);C.r:=(V and 255)/255;C.g:=((V shr 8) and 255)/255;C.b:=((V shr 16) and 255)/255;C.a:=Opacity;FBrush.SetColor(C);
  Bounds.left:=X1;Bounds.top:=Y1;Bounds.right:=X2;Bounds.bottom:=Y2;FTarget.FillRectangle(Bounds,FBrush);
end;
procedure TRhythmD2D.FillQuad(const A,B,C,D:TPointF;Color:TColor;Opacity:Double);
var Geometry:ID2D1PathGeometry;Sink:ID2D1GeometrySink;Point:TD2D1Point2F;
  Tint:TD2D1ColorF;V:Longint;Mode:TD2D1AntialiasMode;
begin
  if FFactory.CreatePathGeometry(Geometry)<0 then raise Exception.Create('D2D face geometry unavailable');
  if Geometry.Open(Sink)<0 then raise Exception.Create('D2D face sink unavailable');
  Point.x:=A.X;Point.y:=A.Y;Sink.BeginFigure(Point,D2D1_FIGURE_BEGIN_FILLED);
  Point.x:=B.X;Point.y:=B.Y;Sink.AddLine(Point);
  Point.x:=C.X;Point.y:=C.Y;Sink.AddLine(Point);
  Point.x:=D.X;Point.y:=D.Y;Sink.AddLine(Point);
  Sink.EndFigure(D2D1_FIGURE_END_CLOSED);
  if Sink.Close<0 then raise Exception.Create('D2D face geometry invalid');
  V:=ColorToRGB(Color);Tint.r:=(V and 255)/255;Tint.g:=((V shr 8) and 255)/255;Tint.b:=((V shr 16) and 255)/255;Tint.a:=EnsureRange(Opacity,0.0,1.0);
  FBrush.SetColor(Tint);
  // 面同士の共有辺に半透明の隙間を残さない。既存の線・円のAA設定は戻す。
  Mode:=FTarget.GetAntialiasMode;
  if Opacity>=1 then FTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_ALIASED);
  try FTarget.FillGeometry(Geometry,FBrush);finally FTarget.SetAntialiasMode(Mode);end;
end;
procedure TRhythmD2D.Star(X,Y,Radius,Trail:Single;Layer,Direction:Integer);
var Shape:TD2D1Ellipse;Bounds:TD2D1RectF;
begin
  if Trail>0 then begin
    if Direction=0 then begin Bounds.left:=X-Radius*0.24;Bounds.right:=X+Radius*0.24;Bounds.top:=Y-Trail;Bounds.bottom:=Y;end
    else begin Bounds.left:=X;Bounds.right:=X+Trail;Bounds.top:=Y-Radius*0.24;Bounds.bottom:=Y+Radius*0.24;end;
    FTarget.FillRectangle(Bounds,FStarTrailBrush);
  end;
  Shape.point.x:=X;Shape.point.y:=Y;Shape.radiusX:=Radius;Shape.radiusY:=Radius;FTarget.FillEllipse(Shape,FStarBrush[Layer]);
end;
end.
