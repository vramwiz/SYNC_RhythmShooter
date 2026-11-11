unit RhythmLayerBlend;
// 一種類のアニメーションの背景と主役を分けて共通EQへ合成する。別種類の重ね合わせはしない。
{$POINTERMATH ON}
interface
uses Vcl.Graphics,RhythmRenderSurface,RhythmEqualizer;
type
  TRhythmLayerBlend=class
  private
    FImage,FBackdrop,FZoom:Vcl.Graphics.TBitmap;
    FSurface:TAnimationRenderSurface;
    function GetLastD2D:Boolean;
  public
    constructor Create;
    destructor Destroy;override;
    procedure Resize(W,H:Integer;Image,Backdrop:Boolean);
    procedure BeginBase(Target:Vcl.Graphics.TBitmap;const Activity:TEqualizerActivity;Equalizer,UseD2D:Boolean);
    procedure ImageOver(Target:Vcl.Graphics.TBitmap);
    procedure Transform(Target:Vcl.Graphics.TBitmap;Zoom,X,Y:Double);
    property LastUsedD2D:Boolean read GetLastD2D;
    property Image:Vcl.Graphics.TBitmap read FImage;
    property Backdrop:Vcl.Graphics.TBitmap read FBackdrop;
  end;
implementation
uses System.SysUtils,System.Math,System.Types,Winapi.Windows,RhythmImageBank;
constructor TRhythmLayerBlend.Create;
  function Bitmap:Vcl.Graphics.TBitmap;
  begin Result:=Vcl.Graphics.TBitmap.Create;Result.PixelFormat:=pf32bit;end;
begin inherited Create;FImage:=Bitmap;FBackdrop:=Bitmap;FZoom:=Bitmap;
  FSurface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0));
end;
destructor TRhythmLayerBlend.Destroy;
begin FSurface.Free;FImage.Free;FBackdrop.Free;FZoom.Free;inherited;end;
function TRhythmLayerBlend.GetLastD2D:Boolean;
begin Result:=FSurface.LastUsedD2D;end;
procedure TRhythmLayerBlend.Resize(W,H:Integer;Image,Backdrop:Boolean);
begin
  if (W<1) or (H<1) or (W>8192) or (H>8192) then raise EArgumentOutOfRangeException.Create('Layer size');
  if Image then FImage.SetSize(W,H);if Backdrop then FBackdrop.SetSize(W,H);
end;
procedure TRhythmLayerBlend.BeginBase(Target:Vcl.Graphics.TBitmap;const Activity:TEqualizerActivity;Equalizer,UseD2D:Boolean);
begin
  FSurface.UseD2D:=UseD2D;FSurface.BeginFrame(Target,clBlack);
  if Equalizer then DrawEqualizer(FSurface,Target.Width,Target.Height,Activity,True);
  if not FSurface.EndFrame then begin FSurface.UseD2D:=False;BeginBase(Target,Activity,Equalizer,False);end;
end;
procedure TRhythmLayerBlend.ImageOver(Target:Vcl.Graphics.TBitmap);
var X,Y,C,D,A:Integer;OutRow,MovieRow,BackRow:PByte;
begin
  for Y:=0 to Target.Height-1 do begin OutRow:=Target.ScanLine[Y];MovieRow:=FImage.ScanLine[Y];BackRow:=FBackdrop.ScanLine[Y];
    for X:=0 to Target.Width-1 do begin
      D:=Max(Abs(Integer(MovieRow[0])-BackRow[0]),Max(Abs(Integer(MovieRow[1])-BackRow[1]),Abs(Integer(MovieRow[2])-BackRow[2])));
      // 同じ背景だけを約60%にし、差のある主役のコアは不透明。単純な全画面半透明ではない。
      A:=153+Min(102,D*102 div 12);
      for C:=0 to 2 do OutRow[C]:=(Integer(MovieRow[C])*A+Integer(OutRow[C])*(255-A)+127) div 255;
      OutRow[3]:=255;Inc(OutRow,4);Inc(MovieRow,4);Inc(BackRow,4);
    end;
  end;
end;
procedure TRhythmLayerBlend.Transform(Target:Vcl.Graphics.TBitmap;Zoom,X,Y:Double);
var L,T,W,H:Integer;
begin
  if (Abs(Zoom-1)<1E-8) and (Abs(X)<1E-8) and (Abs(Y)<1E-8) then Exit;
  W:=Target.Width;H:=Target.Height;FZoom.Assign(Target);L:=Round((W-W*Zoom)/2+X);T:=Round((H-H*Zoom)/2+Y);
  Target.Canvas.Brush.Color:=clBlack;Target.Canvas.FillRect(Rect(0,0,W,H));Target.Canvas.StretchDraw(Rect(L,T,L+Round(W*Zoom),T+Round(H*Zoom)),FZoom);
end;
end.
