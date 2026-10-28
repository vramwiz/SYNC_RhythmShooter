unit RhythmAssets;

interface

uses Vcl.Graphics;

procedure BuildStandardAssets(const Folder: string);

implementation

uses System.SysUtils, System.Types, System.UITypes, System.IOUtils, Winapi.Windows;

procedure BuildStandardAssets(const Folder: string);
var B: Vcl.Graphics.TBitmap; Layer, Direction, I, X, Y: Integer; Name: string;
  procedure Clear(W, H: Integer; Color: TColor);
  begin
    B.SetSize(W,H); B.PixelFormat := pf24bit;
    B.Canvas.Brush.Color := Color; B.Canvas.FillRect(Rect(0,0,W,H));
    B.Canvas.Pen.Color := Color;
  end;
  procedure Save(const FileName: string);
  begin B.SaveToFile(TPath.Combine(Folder,FileName + '.bmp')); end;
  procedure Polygon(const P: array of TPoint; Color: TColor);
  begin B.Canvas.Brush.Color := Color; B.Canvas.Pen.Color := Color; B.Canvas.Polygon(P); end;
begin
  ForceDirectories(Folder); B := Vcl.Graphics.TBitmap.Create;
  try
    for Direction := 0 to 1 do
      for Layer := 0 to 2 do
      begin
        if Layer=0 then Clear(256,256,RGB(7,13,29)) else Clear(256,256,clFuchsia);
        for I := 0 to 55 - Layer*16 do
        begin
          X := 4 + ((I*73 + Layer*31 + Direction*47) mod 248);
          Y := 4 + ((I*137 + Layer*61 + Direction*17) mod 248);
          B.Canvas.Brush.Color := RGB(40+Layer*25,75+Layer*30,115+Layer*40);
          B.Canvas.Pen.Color := B.Canvas.Brush.Color;
          B.Canvas.Ellipse(X,Y,X+2+Layer,Y+2+Layer);
        end;
        if Direction=0 then Name := 'vertical' else Name := 'horizontal';
        Save(Name+'_layer'+IntToStr(Layer));
      end;
    Clear(64,64,clFuchsia);
    Polygon([Point(32,3),Point(40,28),Point(59,49),Point(38,44),Point(32,56),Point(26,44),Point(5,49),Point(24,28)],RGB(71,209,238));
    Polygon([Point(32,14),Point(37,34),Point(32,40),Point(27,34)],RGB(232,249,255));
    Save('player_vertical');
    Clear(64,64,clFuchsia);
    Polygon([Point(61,32),Point(36,40),Point(15,59),Point(20,38),Point(8,32),Point(20,26),Point(15,5),Point(36,24)],RGB(71,209,238));
    Polygon([Point(50,32),Point(30,37),Point(24,32),Point(30,27)],RGB(232,249,255));
    Save('player_horizontal');
    Clear(64,64,clFuchsia);
    Polygon([Point(6,13),Point(25,21),Point(32,11),Point(39,21),Point(58,13),Point(48,43),Point(32,55),Point(16,43)],RGB(226,95,126));
    Polygon([Point(22,29),Point(42,29),Point(32,44)],RGB(255,219,125));
    Save('enemy');
    Clear(64,64,clFuchsia);
    Polygon([Point(32,5),Point(56,21),Point(50,48),Point(32,59),Point(14,48),Point(8,21)],RGB(166,114,239));
    Polygon([Point(22,23),Point(42,23),Point(42,39),Point(22,39)],RGB(168,246,236));Save('enemy1');
    Clear(64,64,clFuchsia);
    Polygon([Point(6,21),Point(25,21),Point(32,5),Point(39,21),Point(58,21),Point(49,53),Point(32,43),Point(15,53)],RGB(228,168,64));
    Polygon([Point(25,27),Point(39,27),Point(32,40)],RGB(255,242,185));Save('enemy2');
    for I:=0 to 1 do
    begin
      Clear(128,80,clFuchsia);
      if I=0 then B.Canvas.Brush.Color:=RGB(153,104,230) else B.Canvas.Brush.Color:=RGB(234,153,68);
      B.Canvas.Pen.Color:=B.Canvas.Brush.Color;
      B.Canvas.Polygon([Point(5,14),Point(42,25),Point(64,4),Point(86,25),Point(123,14),Point(114,63),Point(79,68),Point(64,77),Point(49,68),Point(14,63)]);
      B.Canvas.Brush.Color:=RGB(246,223,147); B.Canvas.Ellipse(47,27,81,60);
      Save('boss'+IntToStr(I));
    end;
    Clear(20,32,clFuchsia); B.Canvas.Brush.Color:=RGB(144,250,224); B.Canvas.Pen.Color:=RGB(144,250,224);
    B.Canvas.Ellipse(6,2,14,30); Save('bullet');
    Clear(64,64,clFuchsia); B.Canvas.Brush.Color:=RGB(255,175,72); B.Canvas.Pen.Color:=RGB(255,175,72);
    B.Canvas.Polygon([Point(32,1),Point(39,21),Point(58,8),Point(45,28),Point(63,32),Point(44,39),Point(57,56),Point(38,45),Point(32,63),Point(25,45),Point(7,56),Point(20,38),Point(1,32),Point(21,25),Point(8,7),Point(27,20)]);
    B.Canvas.Brush.Color:=RGB(255,243,177); B.Canvas.Ellipse(21,21,43,43); Save('explosion');
  finally B.Free; end;
end;

end.
