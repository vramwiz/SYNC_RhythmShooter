unit RhythmGImages;
// 日本語のゲーム名を標準フォントで一度だけメモリーへ描く。外部画像・ファイル出力は使わない。
interface
uses RhythmImageBank;
function CreateGImages: TAnimationImageBank;
implementation
uses System.SysUtils, System.Types, Vcl.Graphics, RhythmGPlan, RhythmGDraw;
type
  TGImages = class(TAnimationImageBank)
  protected
    procedure PrepareImages; override;
  end;
procedure TGImages.PrepareImages;
var I: Integer; C: TCanvas; Text: string;
begin
  for I:=0 to 31 do begin
    FImages[I].PixelFormat:=pf24bit; FImages[I].SetSize(720,76); FColorKeys[I]:=False;
    C:=FImages[I].Canvas; C.Brush.Color:=clWhite; C.FillRect(Rect(0,0,720,76));
    C.Brush.Color:=GColor($25344D); C.FillRect(Rect(0,0,76,76));
    C.Font.Name:='Yu Gothic UI'; C.Font.Height:=-34; C.Font.Style:=[fsBold]; C.Font.Color:=clWhite;
    C.TextOut(15,14,Format('%.2d',[I+1]));
    C.Brush.Color:=clWhite; C.Font.Color:=GColor($25344D); Text:=GNames[I];
    C.TextOut(100,(76-C.TextHeight(Text)) div 2,Text);
  end;
end;
function CreateGImages: TAnimationImageBank;
begin Result:=TGImages.Create(32); end;
end.
