unit RhythmOverlay;
// MV用の乗算済みBGRA。黒/白の二色マットからalphaを復元し、黒い記号も保持する。
{$POINTERMATH ON}
interface
uses Vcl.Graphics;
type
  TRhythmOverlay=class
  private
    FBlack,FWhite,FAlpha:TBitmap;
  public
    constructor Create;
    destructor Destroy;override;
    procedure Resize(W,H:Integer);
    procedure Resolve(Target:TBitmap;Zoom,X,Y:Double);
    property Black:TBitmap read FBlack;
    property White:TBitmap read FWhite;
  end;
// Previewは同じRGBAを市松背景へ合成する。出力用バッファには呼ばない。
procedure OverlayPreview(Target:TBitmap);
procedure OverlayOver(Target,Overlay:TBitmap);
implementation
uses System.Math,System.SysUtils;
constructor TRhythmOverlay.Create;
begin inherited;FBlack:=TBitmap.Create;FWhite:=TBitmap.Create;FAlpha:=TBitmap.Create;
  FBlack.PixelFormat:=pf32bit;FWhite.PixelFormat:=pf32bit;FAlpha.PixelFormat:=pf32bit;
end;
destructor TRhythmOverlay.Destroy;
begin FBlack.Free;FWhite.Free;FAlpha.Free;inherited;end;
procedure TRhythmOverlay.Resize(W,H:Integer);
begin
  if (W<1) or (H<1) or (W>8192) or (H>8192) then raise EArgumentOutOfRangeException.Create('Overlay size');
  FBlack.SetSize(W,H);FWhite.SetSize(W,H);FAlpha.SetSize(W,H);
end;
procedure TRhythmOverlay.Resolve(Target:TBitmap;Zoom,X,Y:Double);
var I,J,C,A,T,SX,SY,W,H,DW,DH,L,Top:Integer;B,White,OutRow,Src:PByte;LeftD,TopD:Double;
begin
  W:=FBlack.Width;H:=FBlack.Height;Target.PixelFormat:=pf32bit;Target.SetSize(W,H);
  for J:=0 to H-1 do begin B:=FBlack.ScanLine[J];White:=FWhite.ScanLine[J];OutRow:=FAlpha.ScanLine[J];
    for I:=0 to W-1 do begin
      // チャンネル別の丸め差には最大の被覆率を使い、RGB<=Aを保証する。黒のRGB=0は透明判定に使わない。
      T:=255;for C:=0 to 2 do T:=Min(T,EnsureRange(Integer(White[C])-B[C],0,255));A:=255-T;
      for C:=0 to 2 do OutRow[C]:=Min(A,Integer(B[C]));OutRow[3]:=A;
      Inc(B,4);Inc(White,4);Inc(OutRow,4);
    end;
  end;
  if IsNan(Zoom) or IsInfinite(Zoom) or IsNan(X) or IsInfinite(X) or IsNan(Y) or IsInfinite(Y) then raise EArgumentException.Create('Non-finite overlay transform');
  DW:=Max(1,Round(W*EnsureRange(Zoom,0.01,4.0)));DH:=Max(1,Round(H*EnsureRange(Zoom,0.01,4.0)));
  LeftD:=(W-DW)/2+X;TopD:=(H-DH)/2+Y;
  for J:=0 to H-1 do FillChar(Target.ScanLine[J]^,W*4,0);
  if (LeftD>=W) or (TopD>=H) or (LeftD+DW<=0) or (TopD+DH<=0) then Exit;
  L:=Round(LeftD);Top:=Round(TopD);
  // alphaを含む四成分を同じ座標で運ぶ。余白は透明。Canvas.StretchDrawで黒枠や濃い縁を作らない。
  for J:=Max(0,Top) to Min(H,Top+DH)-1 do begin
    SY:=(J-Top)*H div DH;OutRow:=Target.ScanLine[J];Src:=FAlpha.ScanLine[SY];
    for I:=Max(0,L) to Min(W,L+DW)-1 do begin SX:=(I-L)*W div DW;
      PCardinal(OutRow+I*4)^:=PCardinal(Src+SX*4)^;
    end;
  end;
end;
procedure OverlayOver(Target,Overlay:TBitmap);
var X,Y,C,T:Integer;D,S:PByte;
begin
  if (Target.Width<>Overlay.Width) or (Target.Height<>Overlay.Height) then raise EArgumentException.Create('Overlay dimensions');
  for Y:=0 to Target.Height-1 do begin D:=Target.ScanLine[Y];S:=Overlay.ScanLine[Y];
    for X:=0 to Target.Width-1 do begin T:=255-S[3];for C:=0 to 2 do D[C]:=Min(255,Integer(S[C])+(Integer(D[C])*T+127) div 255);
      D[3]:=255;Inc(D,4);Inc(S,4);
    end;
  end;
end;
procedure OverlayPreview(Target:TBitmap);
var X,Y,C,T,Shade:Integer;D:PByte;
begin
  for Y:=0 to Target.Height-1 do begin D:=Target.ScanLine[Y];
    for X:=0 to Target.Width-1 do begin
      Shade:=24;if ((X div 16+Y div 16) mod 2)=1 then Shade:=42;T:=255-D[3];
      for C:=0 to 2 do D[C]:=Min(255,Integer(D[C])+(Shade*T+127) div 255);D[3]:=255;Inc(D,4);
    end;
  end;
end;
end.
