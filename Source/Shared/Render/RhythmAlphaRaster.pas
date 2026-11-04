unit RhythmAlphaRaster;
// Software fallback for drawing into a premultiplied BGRA DIB in one pass.
{$POINTERMATH ON}
interface
uses System.Types,Vcl.Graphics;

type
  TRhythmAlphaRaster=record
  private
    FStart:PByte;
    FPitch:NativeInt;
    FWidth,FHeight:Integer;
    function GetActive:Boolean;
    procedure Span(Y,L,R:Integer;Source:Cardinal);
  public
    procedure BeginFrame(Target:TBitmap);
    procedure EndFrame;
    procedure FillRect(X1,Y1,X2,Y2:Double;Color:TColor;Opacity:Double);
    procedure FillQuad(const A,B,C,D:TPointF;Color:TColor;Opacity:Double=1);
    procedure Line(X1,Y1,X2,Y2,Stroke:Double;Color:TColor;Opacity:Double);
    procedure Circle(X,Y,Radius,Stroke:Double;Color:TColor;Filled:Boolean;Opacity:Double);
    procedure DrawBitmap(Image:TBitmap;const Bounds:TRect;Opacity:Double);
    property Active:Boolean read GetActive;
  end;

implementation
uses System.Math,Winapi.Windows;

function ScalePixel(Pixel:Cardinal;Alpha:Integer):Cardinal;
var I:Integer;Value:Cardinal;
begin
  Result:=0;
  for I:=0 to 3 do begin
    Value:=((Pixel and $FF)*Cardinal(Alpha)+127) div 255;
    Result:=Result or (Value shl (I*8));
    Pixel:=Pixel shr 8;
  end;
end;

function BrushPixel(Color:TColor;Opacity:Double):Cardinal;
var C:Cardinal;
begin
  C:=Cardinal(ColorToRGB(Color));
  Result:=$FF000000 or ((C and $FF) shl 16) or (C and $FF00) or ((C shr 16) and $FF);
  if Opacity<1 then Result:=ScalePixel(Result,Round(EnsureRange(Opacity,0.0,1.0)*255));
end;

function TRhythmAlphaRaster.GetActive:Boolean;
begin
  Result:=FStart<>nil;
end;

procedure TRhythmAlphaRaster.BeginFrame(Target:Vcl.Graphics.TBitmap);
var Y:Integer;
begin
  Target.PixelFormat:=pf32bit;
  FWidth:=Target.Width;FHeight:=Target.Height;
  FStart:=Target.ScanLine[0];
  FPitch:=0;
  if FHeight>1 then FPitch:=NativeInt(Target.ScanLine[1])-NativeInt(FStart);
  for Y:=0 to FHeight-1 do FillChar((FStart+Y*FPitch)^,FWidth*4,0);
end;

procedure TRhythmAlphaRaster.EndFrame;
begin
  FStart:=nil;
end;

procedure TRhythmAlphaRaster.Span(Y,L,R:Integer;Source:Cardinal);
var X,Alpha:Integer;Dest:PCardinal;
begin
  L:=Max(0,L);R:=Min(FWidth,R);
  if (L>=R) or (Source=0) then Exit;
  Dest:=PCardinal(FStart+Y*FPitch+L*4);
  Alpha:=Source shr 24;
  if Alpha=255 then
    for X:=L to R-1 do begin Dest^:=Source;Inc(Dest);end
  else
    for X:=L to R-1 do begin
      if Dest^=0 then Dest^:=Source
      else Dest^:=Source+ScalePixel(Dest^,255-Alpha);
      Inc(Dest);
    end;
end;

procedure TRhythmAlphaRaster.FillRect(X1,Y1,X2,Y2:Double;Color:TColor;Opacity:Double);
var L,R,Y:Integer;Source:Cardinal;
begin
  L:=Round(X1);R:=Round(X2);
  if L>=R then Exit;
  Source:=BrushPixel(Color,Opacity);
  for Y:=Max(0,Round(Y1)) to Min(FHeight,Round(Y2))-1 do Span(Y,L,R,Source);
end;

procedure TRhythmAlphaRaster.FillQuad(const A,B,C,D:TPointF;Color:TColor;Opacity:Double);
var Points:array[0..3] of TPointF;I,J,Y,T,Bottom:Integer;
  L,R,X,SampleY:Double;Source:Cardinal;
begin
  Points[0]:=A;Points[1]:=B;Points[2]:=C;Points[3]:=D;
  T:=Max(0,Floor(Min(Min(A.Y,B.Y),Min(C.Y,D.Y))));
  Bottom:=Min(FHeight,Ceil(Max(Max(A.Y,B.Y),Max(C.Y,D.Y))));
  Source:=BrushPixel(Color,Opacity);
  for Y:=T to Bottom-1 do begin
    SampleY:=Y+0.5;L:=FWidth;R:=0;
    for I:=0 to 3 do begin
      J:=(I+1) and 3;
      if (Points[I].Y>SampleY)=(Points[J].Y>SampleY) then Continue;
      X:=Points[I].X+(SampleY-Points[I].Y)*(Points[J].X-Points[I].X)/(Points[J].Y-Points[I].Y);
      L:=Min(L,X);R:=Max(R,X);
    end;
    Span(Y,Ceil(L-0.5),Ceil(R-0.5),Source);
  end;
end;

procedure TRhythmAlphaRaster.Line(X1,Y1,X2,Y2,Stroke:Double;Color:TColor;Opacity:Double);
var Length,Half,DX,DY:Double;
begin
  Half:=Max(1.0,Stroke)*0.5;
  Length:=Hypot(X2-X1,Y2-Y1);
  if Length<0.01 then begin
    FillRect(X1-Half,Y1-Half,X1+Half,Y1+Half,Color,Opacity);
    Exit;
  end;
  DX:=(Y2-Y1)*Half/Length;DY:=(X1-X2)*Half/Length;
  FillQuad(PointF(X1+DX,Y1+DY),PointF(X2+DX,Y2+DY),PointF(X2-DX,Y2-DY),
    PointF(X1-DX,Y1-DY),Color,Opacity);
end;

procedure TRhythmAlphaRaster.Circle(X,Y,Radius,Stroke:Double;Color:TColor;Filled:Boolean;Opacity:Double);
var Row,L,R:Integer;Outer,Inner,Delta,Reach:Double;Source:Cardinal;
begin
  Outer:=Radius;
  Inner:=0;
  if not Filled then begin
    Outer:=Radius+Stroke*0.5;
    Inner:=Max(0.0,Radius-Stroke*0.5);
  end;
  Source:=BrushPixel(Color,Opacity);
  for Row:=Max(0,Floor(Y-Outer)) to Min(FHeight,Ceil(Y+Outer))-1 do begin
    Delta:=Abs(Row+0.5-Y);
    if Delta>=Outer then Continue;
    Reach:=Sqrt(Sqr(Outer)-Sqr(Delta));L:=Ceil(X-Reach-0.5);R:=Ceil(X+Reach-0.5);
    if Delta>=Inner then Span(Row,L,R,Source)
    else begin
      Reach:=Sqrt(Sqr(Inner)-Sqr(Delta));
      Span(Row,L,Ceil(X-Reach-0.5),Source);
      Span(Row,Ceil(X+Reach-0.5),R,Source);
    end;
  end;
end;

procedure TRhythmAlphaRaster.DrawBitmap(Image:Vcl.Graphics.TBitmap;const Bounds:TRect;Opacity:Double);
var X,Y,L,R,StepX,Position,Strength:Integer;SrcStart,Src:PByte;SrcPitch:NativeInt;
  Dest:PCardinal;Pixel:Cardinal;
begin
  if Image.Empty or (Bounds.Width<=0) or (Bounds.Height<=0) or (Opacity<=0) then Exit;
  L:=Max(0,Bounds.Left);R:=Min(FWidth,Bounds.Right);
  if L>=R then Exit;
  SrcStart:=Image.ScanLine[0];SrcPitch:=0;
  if Image.Height>1 then SrcPitch:=NativeInt(Image.ScanLine[1])-NativeInt(SrcStart);
  Strength:=Round(Min(1.0,Opacity)*255);
  StepX:=(Image.Width shl 16) div Bounds.Width;
  for Y:=Max(0,Bounds.Top) to Min(FHeight,Bounds.Bottom)-1 do begin
    Src:=SrcStart+((Y-Bounds.Top)*Image.Height div Bounds.Height)*SrcPitch;
    Dest:=PCardinal(FStart+Y*FPitch+L*4);
    Position:=(L-Bounds.Left)*StepX;
    for X:=L to R-1 do begin
      Pixel:=PCardinal(Src+(Position shr 16)*4)^;
      if Pixel<>0 then begin
        if Strength<255 then Pixel:=ScalePixel(Pixel,Strength);
        if ((Pixel shr 24)=255) or (Dest^=0) then Dest^:=Pixel
        else Dest^:=Pixel+ScalePixel(Dest^,255-Integer(Pixel shr 24));
      end;
      Inc(Position,StepX);Inc(Dest);
    end;
  end;
end;
end.
