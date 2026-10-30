unit RhythmAssets;

interface

uses Vcl.Graphics;

procedure BuildStandardAssets(const Folder: string);

implementation

uses System.SysUtils, System.Types, System.UITypes, System.IOUtils, Winapi.Windows, System.Math;

// Fixed, original mechanical silhouettes. Large planes and deep cut-outs remain
// readable at gameplay scale; lighting belongs to the bitmap, not the battle.
function Tone(Color:TColor;Offset:Integer):TColor;
  function Clamp(V:Integer):Integer;
  begin if V<0 then Result:=0 else if V>255 then Result:=255 else Result:=V;end;
var C:Longint;
begin C:=ColorToRGB(Color);Result:=RGB(Clamp((C and 255)+Offset),Clamp(((C shr 8) and 255)+Offset),Clamp(((C shr 16) and 255)+Offset));end;
procedure Hull(B:Vcl.Graphics.TBitmap;const Points:array of TPoint;Color:TColor);
begin
  B.Canvas.Brush.Style:=bsSolid;B.Canvas.Brush.Color:=Color;B.Canvas.Pen.Style:=psSolid;
  B.Canvas.Pen.Color:=RGB(12,17,28);B.Canvas.Pen.Width:=2;B.Canvas.Polygon(Points);B.Canvas.Pen.Width:=1;
end;
procedure Edge(B:Vcl.Graphics.TBitmap;X1,Y1,X2,Y2:Integer;Color:TColor;Width:Integer=1);
begin B.Canvas.Pen.Style:=psSolid;B.Canvas.Pen.Width:=Width;B.Canvas.Pen.Color:=Color;B.Canvas.MoveTo(X1,Y1);B.Canvas.LineTo(X2,Y2);B.Canvas.Pen.Width:=1;end;
procedure Fill(B:Vcl.Graphics.TBitmap;L,T,R,Bottom:Integer;Color:TColor);
begin B.Canvas.Brush.Style:=bsSolid;B.Canvas.Brush.Color:=Color;B.Canvas.FillRect(Rect(L,T,R,Bottom));end;
procedure Disc(B:Vcl.Graphics.TBitmap;X,Y,Radius:Integer;Color:TColor);
begin B.Canvas.Brush.Style:=bsSolid;B.Canvas.Brush.Color:=Color;B.Canvas.Pen.Style:=psClear;B.Canvas.Ellipse(X-Radius,Y-Radius,X+Radius+1,Y+Radius+1);B.Canvas.Pen.Style:=psSolid;end;
procedure Panel(B:Vcl.Graphics.TBitmap;L,T,R,Bottom:Integer;Color:TColor);
begin
  Fill(B,L+2,T+3,R+2,Bottom+3,RGB(12,17,28));Fill(B,L,T,R,Bottom,Color);
  Edge(B,L,T,R-1,T,Tone(Color,45));Edge(B,L,T,L,Bottom-1,Tone(Color,24));
  Edge(B,L,Bottom-1,R-1,Bottom-1,Tone(Color,-35));Edge(B,R-1,T,R-1,Bottom,Tone(Color,-45));
end;
procedure Core(B:Vcl.Graphics.TBitmap;X,Y,Radius:Integer;Color:TColor);
begin
  Disc(B,X,Y,Radius+6,RGB(14,22,34));Disc(B,X,Y,Radius+3,Tone(Color,-110));
  Disc(B,X,Y,Radius,Color);Disc(B,X-1,Y-1,Radius*3 div 5,Tone(Color,58));
  Disc(B,X-2,Y-2,Max(1,Radius div 4),RGB(255,245,205));
end;
procedure Thruster(B:Vcl.Graphics.TBitmap;X,Y,W,H:Integer);
begin
  Fill(B,X-W div 2+3,Y-6,X+W div 2-3,Y+H,RGB(29,78,116));
  Fill(B,X-W div 2+5,Y-2,X+W div 2-5,Y+H,RGB(79,169,212));
  Panel(B,X-W div 2,Y+H div 2,X+W div 2,Y+H,RGB(59,71,91));
  Edge(B,X-W div 2+3,Y+H div 2,X+W div 2-3,Y+H div 2,RGB(133,195,220),2);
end;
procedure Cannon(B:Vcl.Graphics.TBitmap;X,Y,Length,Width:Integer;Color:TColor);
begin
  Disc(B,X,Y,Width+3,RGB(15,21,31));Disc(B,X,Y,Width,Tone(Color,12));
  Panel(B,X-Width div 2-2,Y,X+Width div 2+2,Y+Length,Color);
  Fill(B,X-Width div 2,Y+4,X-Width div 2+2,Y+Length-3,Tone(Color,55));
  Panel(B,X-Width div 2-3,Y+Length-7,X+Width div 2+3,Y+Length,RGB(41,48,63));
  Fill(B,X-Width div 2+1,Y+Length-4,X+Width div 2-1,Y+Length-1,RGB(232,136,57));
end;
procedure ClearShip(B:Vcl.Graphics.TBitmap;W,H:Integer);
begin B.PixelFormat:=pf24bit;B.SetSize(W,H);B.Canvas.Pen.Width:=1;B.Canvas.Pen.Style:=psSolid;Fill(B,0,0,W,H,clFuchsia);end;
procedure DrawEnemyShip(B:Vcl.Graphics.TBitmap;Kind:Integer);
var C:TColor;I:Integer;
begin
  ClearShip(B,96,96);
  case Kind of
  0:begin
    C:=RGB(164,53,71);Thruster(B,27,18,16,23);Thruster(B,69,18,16,23);
    Hull(B,[Point(7,28),Point(31,34),Point(39,12),Point(57,12),Point(65,34),Point(89,28),Point(80,64),Point(64,72),Point(55,88),Point(41,88),Point(32,72),Point(16,64)],Tone(C,-45));
    Hull(B,[Point(11,32),Point(31,40),Point(34,62),Point(19,59)],C);
    Hull(B,[Point(85,32),Point(65,40),Point(62,62),Point(77,59)],C);
    Hull(B,[Point(39,16),Point(57,16),Point(64,54),Point(54,82),Point(42,82),Point(32,54)],Tone(C,15));
    Hull(B,[Point(39,19),Point(47,18),Point(44,63),Point(39,70),Point(35,53)],Tone(C,52));
    Edge(B,13,34,28,40,RGB(240,153,129),2);Edge(B,68,40,83,34,RGB(240,153,129),2);
    Cannon(B,23,56,27,9,RGB(90,87,100));Cannon(B,73,56,27,9,RGB(90,87,100));
    Hull(B,[Point(43,31),Point(53,31),Point(56,44),Point(48,53),Point(40,44)],RGB(24,27,43));
    Hull(B,[Point(45,34),Point(51,34),Point(52,42),Point(48,47),Point(44,42)],RGB(255,186,111));
    Panel(B,42,58,54,66,RGB(57,32,48));Edge(B,45,76,51,76,RGB(248,183,143),2);
  end;
  1:begin
    C:=RGB(113,80,157);Thruster(B,34,13,16,22);Thruster(B,62,13,16,22);
    Hull(B,[Point(48,7),Point(78,22),Point(88,48),Point(74,78),Point(56,84),Point(48,92),Point(40,84),Point(22,78),Point(8,48),Point(18,22)],Tone(C,-42));
    Hull(B,[Point(22,24),Point(38,15),Point(37,35),Point(21,49),Point(14,46)],Tone(C,27));
    Hull(B,[Point(74,24),Point(58,15),Point(59,35),Point(75,49),Point(82,46)],C);
    Panel(B,14,46,29,68,C);Panel(B,67,46,82,68,C);
    Disc(B,48,49,26,RGB(35,32,57));Disc(B,48,49,22,Tone(C,13));Disc(B,48,49,17,RGB(18,28,44));
    Core(B,48,49,9,RGB(81,173,216));
    for I:=0 to 2 do begin Fill(B,17,49+I*6,25,52+I*6,RGB(37,35,54));Fill(B,71,49+I*6,79,52+I*6,RGB(37,35,54));end;
    Cannon(B,31,71,16,7,RGB(98,88,132));Cannon(B,65,71,16,7,RGB(98,88,132));
    Hull(B,[Point(42,74),Point(54,74),Point(48,88)],Tone(C,45));
    Edge(B,24,27,33,22,RGB(197,160,231),2);Edge(B,64,22,73,27,RGB(197,160,231),2);
  end;
  else begin
    C:=RGB(177,128,56);Thruster(B,30,17,16,22);Thruster(B,66,17,16,22);
    Hull(B,[Point(8,21),Point(31,30),Point(40,7),Point(56,7),Point(65,30),Point(88,21),Point(75,55),Point(62,69),Point(48,91),Point(34,69),Point(21,55)],Tone(C,-51));
    Hull(B,[Point(13,27),Point(31,36),Point(36,57),Point(25,50)],Tone(C,27));
    Hull(B,[Point(83,27),Point(65,36),Point(60,57),Point(71,50)],C);
    Hull(B,[Point(41,12),Point(55,12),Point(61,43),Point(55,72),Point(48,87),Point(41,72),Point(35,43)],C);
    Hull(B,[Point(42,15),Point(47,14),Point(44,62),Point(41,69),Point(38,43)],Tone(C,54));
    Hull(B,[Point(43,31),Point(53,31),Point(55,45),Point(48,52),Point(41,45)],RGB(18,44,61));
    Edge(B,45,35,51,35,RGB(145,212,233),2);
    Cannon(B,26,57,22,7,RGB(88,76,62));Cannon(B,70,57,22,7,RGB(88,76,62));
    Panel(B,42,58,54,66,RGB(66,51,38));Edge(B,46,73,50,78,RGB(255,223,150),2);
  end;
  end;
end;
procedure DrawBossShip(B:Vcl.Graphics.TBitmap;Kind:Integer);
var C:TColor;Side,X,J:Integer;
begin
  ClearShip(B,256,160);
  if Kind=0 then begin
    // Heavy gunship: compact reactor, broad shoulders and four projecting guns.
    C:=RGB(94,115,147);Thruster(B,50,13,25,31);Thruster(B,206,13,25,31);
    Hull(B,[Point(31,38),Point(96,28),Point(160,28),Point(225,38),Point(246,73),Point(231,116),Point(174,120),Point(158,145),Point(98,145),Point(82,120),Point(25,116),Point(10,73)],RGB(30,41,61));
    Hull(B,[Point(98,22),Point(158,22),Point(173,62),Point(168,126),Point(145,151),Point(111,151),Point(88,126),Point(83,62)],Tone(C,-22));
    for Side:=0 to 1 do begin
      if Side=0 then X:=25 else X:=181;
      Panel(B,X,43,X+50,93,C);Panel(B,X+6,91,X+44,126,Tone(C,-20));
      Hull(B,[Point(X+5,47),Point(X+42,47),Point(X+33,61),Point(X+5,67)],Tone(C,28));
      for J:=0 to 3 do Fill(B,X+9+J*8,71,X+13+J*8,84,RGB(28,38,57));
      Cannon(B,X+25,105,49,15,RGB(83,99,125));
      if Side=0 then Cannon(B,23,102,35,9,RGB(78,91,117)) else Cannon(B,233,102,35,9,RGB(78,91,117));
      Panel(B,X+5,47,X+12,53,RGB(232,151,70));
    end;
    Hull(B,[Point(100,28),Point(122,25),Point(114,61),Point(94,72),Point(89,60)],Tone(C,32));
    Hull(B,[Point(156,28),Point(134,25),Point(142,61),Point(162,72),Point(167,60)],C);
    Panel(B,112,32,144,47,RGB(38,52,77));Fill(B,117,35,139,40,RGB(120,177,203));
    Panel(B,79,73,97,101,RGB(73,87,110));Panel(B,159,73,177,101,RGB(73,87,110));
    Core(B,128,79,15,RGB(232,143,51));
    Hull(B,[Point(104,105),Point(128,115),Point(152,105),Point(149,130),Point(128,146),Point(107,130)],Tone(C,8));
    Hull(B,[Point(108,109),Point(126,119),Point(126,139),Point(111,128)],Tone(C,39));
    Edge(B,109,108,125,115,RGB(186,206,226),2);Edge(B,131,115,147,108,RGB(142,163,188),2);
    Panel(B,119,122,137,128,RGB(40,51,70));
  end else begin
    // Capital ship: long central keel, separate hangar sponsons and deck turrets.
    C:=RGB(137,57,66);Thruster(B,30,17,23,31);Thruster(B,70,25,20,27);
    Thruster(B,186,25,20,27);Thruster(B,226,17,23,31);
    Hull(B,[Point(8,36),Point(57,21),Point(100,40),Point(108,72),Point(80,83),Point(63,69),Point(12,79)],Tone(C,-34));
    Hull(B,[Point(248,36),Point(199,21),Point(156,40),Point(148,72),Point(176,83),Point(193,69),Point(244,79)],Tone(C,-34));
    for Side:=0 to 1 do begin
      if Side=0 then begin
        Hull(B,[Point(12,42),Point(47,32),Point(76,48),Point(81,103),Point(62,129),Point(22,119),Point(8,99)],Tone(C,-14));
        Hull(B,[Point(17,46),Point(46,39),Point(65,53),Point(63,74),Point(18,84)],Tone(C,27));X:=22;
      end else begin
        Hull(B,[Point(244,42),Point(209,32),Point(180,48),Point(175,103),Point(194,129),Point(234,119),Point(248,99)],Tone(C,-14));
        Hull(B,[Point(239,46),Point(210,39),Point(191,53),Point(193,74),Point(238,84)],C);X:=195;
      end;
      Panel(B,X,86,X+39,106,RGB(17,25,39));
      for J:=0 to 2 do begin Fill(B,X+4,90+J*5,X+33,92+J*5,RGB(136,104,69));end;
      Panel(B,X+4,109,X+31,117,RGB(112,61,62));
      Cannon(B,X+15,52,27,10,RGB(145,117,86));
      Cannon(B,X+32,77,25,8,RGB(113,89,75));
      Edge(B,X+4,47,X+22,43,RGB(225,143,119),2);
    end;
    Hull(B,[Point(111,10),Point(145,10),Point(159,52),Point(156,110),Point(142,153),Point(128,157),Point(114,153),Point(100,110),Point(97,52)],Tone(C,-16));
    Hull(B,[Point(110,34),Point(121,29),Point(116,105),Point(108,124),Point(103,107),Point(102,58)],Tone(C,29));
    Hull(B,[Point(146,34),Point(135,29),Point(140,105),Point(148,124),Point(153,107),Point(154,58)],Tone(C,4));
    Panel(B,112,16,144,39,RGB(135,108,76));Panel(B,118,21,138,31,RGB(29,48,68));
    Fill(B,120,23,136,26,RGB(128,191,217));
    Hull(B,[Point(116,47),Point(140,47),Point(149,69),Point(142,101),Point(114,101),Point(107,69)],RGB(29,26,34));
    Hull(B,[Point(120,51),Point(136,51),Point(144,70),Point(138,96),Point(118,96),Point(112,70)],RGB(174,87,43));
    Hull(B,[Point(124,55),Point(132,55),Point(137,71),Point(132,91),Point(124,91),Point(119,71)],RGB(255,193,81));
    Fill(B,125,60,130,82,RGB(255,242,179));
    Panel(B,89,46,103,69,RGB(118,96,79));Panel(B,153,46,167,69,RGB(118,96,79));
    Hull(B,[Point(110,108),Point(128,118),Point(146,108),Point(139,144),Point(128,152),Point(117,144)],C);
    Hull(B,[Point(113,112),Point(126,121),Point(126,145),Point(120,140)],Tone(C,44));
    Edge(B,131,121,142,114,RGB(188,117,94),2);Fill(B,124,132,132,139,RGB(43,30,37));
    Panel(B,60,35,77,43,RGB(177,126,75));Panel(B,179,35,196,43,RGB(177,126,75));
  end;
  B.Canvas.Brush.Style:=bsSolid;B.Canvas.Pen.Style:=psSolid;B.Canvas.Pen.Width:=1;
end;

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
    DrawEnemyShip(B,0);Save('enemy');
    DrawEnemyShip(B,1);Save('enemy1');
    DrawEnemyShip(B,2);Save('enemy2');
    DrawBossShip(B,0);Save('boss0');
    DrawBossShip(B,1);Save('boss1');
    Clear(20,32,clFuchsia); B.Canvas.Brush.Color:=RGB(144,250,224); B.Canvas.Pen.Color:=RGB(144,250,224);
    B.Canvas.Ellipse(6,2,14,30); Save('bullet');
    Clear(64,64,clFuchsia); B.Canvas.Brush.Color:=RGB(255,175,72); B.Canvas.Pen.Color:=RGB(255,175,72);
    B.Canvas.Polygon([Point(32,1),Point(39,21),Point(58,8),Point(45,28),Point(63,32),Point(44,39),Point(57,56),Point(38,45),Point(32,63),Point(25,45),Point(7,56),Point(20,38),Point(1,32),Point(21,25),Point(8,7),Point(27,20)]);
    B.Canvas.Brush.Color:=RGB(255,243,177); B.Canvas.Ellipse(21,21,43,43); Save('explosion');
  finally B.Free; end;
end;

end.
