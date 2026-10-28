unit RhythmD2D;
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
    constructor Create(const Assets:array of TBitmap);
    function BeginFrame(Target:TBitmap):Boolean;
    function EndFrame:Boolean;
    procedure DrawAsset(Index:Integer;const Bounds:TRect);
    procedure Ring(X,Y,Radius:Single);
    procedure Star(X,Y,Radius,Trail:Single;Layer,Direction:Integer);
  end;
implementation
uses Winapi.Windows, Winapi.DXGIFormat, System.SysUtils;
constructor TRhythmD2D.Create(const Assets:array of Vcl.Graphics.TBitmap);
var Props:TD2D1RenderTargetProperties;BitmapProps:TD2D1BitmapProperties;
  I,X,Y:Integer;Temp:Vcl.Graphics.TBitmap;Pixels:TBytes;Source,Destination:PByte;
  Size:TD2D1SizeU;Color:TD2D1ColorF;
begin
  inherited Create;
  if D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED,ID2D1Factory,nil,FFactory)<0 then
    raise Exception.Create('D2D factory unavailable');
  Props:=D2D1RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT,
    D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,D2D1_ALPHA_MODE_IGNORE),96,96);
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
          end else if (I<>0) and (I<>3) and (Source[0]=255) and (Source[1]=0) and (Source[2]=255) then
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
function TRhythmD2D.BeginFrame(Target:Vcl.Graphics.TBitmap):Boolean;
var Color:TD2D1ColorF;
begin
  Result:=FTarget.BindDC(Target.Canvas.Handle,Rect(0,0,Target.Width,Target.Height))>=0;
  if not Result then Exit;
  FTarget.BeginDraw;Color.r:=7/255;Color.g:=13/255;Color.b:=29/255;Color.a:=1;FTarget.Clear(Color);
end;
function TRhythmD2D.EndFrame:Boolean;
begin Result:=FTarget.EndDraw()>=0;end;
procedure TRhythmD2D.DrawAsset(Index:Integer;const Bounds:TRect);
var R:TD2D1RectF;
begin
  if (Index<0) or (Index>High(FBitmaps)) or (FBitmaps[Index]=nil) then Exit;
  R.left:=Bounds.Left;R.top:=Bounds.Top;R.right:=Bounds.Right;R.bottom:=Bounds.Bottom;
  FTarget.DrawBitmap(FBitmaps[Index],@R,1,D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
end;
procedure TRhythmD2D.Ring(X,Y,Radius:Single);
var Shape:TD2D1Ellipse;
begin Shape.point.x:=X;Shape.point.y:=Y;Shape.radiusX:=Radius;Shape.radiusY:=Radius;FTarget.DrawEllipse(Shape,FBrush,1);end;
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
