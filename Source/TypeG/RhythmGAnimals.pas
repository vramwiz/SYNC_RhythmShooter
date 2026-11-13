unit RhythmGAnimals;
// 動物8ゲーム。専用シルエット・舞台・対象物を持ち、危険物には対応する回避を描く。
interface
uses RhythmGDraw;
procedure DrawGAnimals(var D: TGDraw);
implementation
uses System.Math, Vcl.Graphics;

procedure Penguin(var D: TGDraw);
var X,Y,Jump,Scroll: Double; I: Integer;
begin
  D.Disc(805,130,60,GColor($FFE690),False);
  D.Quad(65,430,290,150,505,430,65,430,GColor($DBF7FF));
  D.Quad(510,430,700,205,950,430,510,430,GColor($C2EBFC));
  D.Floor(530,GColor($62CDE1));
  Scroll:=D.Wind*220*(1+D.Action);
  for I:=-1 to 5 do begin
    X:=I*220+10-Scroll;
    D.Quad(X-80,533,X+74,533,X+55,575,X-57,575,GColor($9ADBE8));
    D.Quad(X-90,520,X+80,520,X+74,543,X-80,543,clWhite);
    if (I=3) and (D.Action=1) then begin D.Line(X-30,525,X,536,D.Ink,4); D.Line(X,536,X+25,523,D.Ink,4); end;
  end;
  Jump:=0; if D.Active and (D.Age<0) then Jump:=Sin(D.Wind*Pi)*(110+40*D.Action);
  X:=450; Y:=405-Jump+D.Sway*3;
  D.Oval(X,Y+10,85,110,D.Ink); D.Oval(X,Y+30,59,81,clWhite);
  D.Disc(X,Y-72,65,D.Ink); D.Oval(X,Y-60,52,45,clWhite); D.Face(X,Y-70,44,Ord(D.Hit>0.2));
  D.Quad(X-20,Y-35,X+20,Y-35,X,Y-12,X,Y-12,GColor($FFB64C));
  D.Line(X-70,Y-5,X-118,Y+25-Jump*0.3,D.Ink,20); D.Line(X+70,Y-5,X+118,Y+25-Jump*0.3,D.Ink,20);
  D.Oval(X-40,Y+111,36,13,GColor($FFAE4B)); D.Oval(X+40,Y+111,36,13,GColor($FFAE4B));
  D.Burst(X,520);
end;

procedure Frogs(var D: TGDraw);
var I: Integer; X,Y,Open: Double;
begin
  D.Floor(490,GColor($8DD7C8));
  for I:=0 to 3 do begin
    X:=155+I*220; Y:=400+D.Sway*9;
    D.Oval(X,520,100,25,GColor($62AD79)); D.Oval(X,Y+45,70,65,GColor($75BF68));
    D.Disc(X,Y,72,GColor($8FD47A)); D.Disc(X-38,Y-55,28,GColor($8FD47A)); D.Disc(X+38,Y-55,28,GColor($8FD47A));
    D.Disc(X-38,Y-57,11,D.Ink,False); D.Disc(X+38,Y-57,11,D.Ink,False);
    Open:=D.Hit*(18+D.Action*15);
    if (D.Action=1) and D.Resolved then Open:=25*(1-D.After*0.3);
    D.Oval(X,Y+17,40,5+Open,D.Ink); D.Oval(X,Y+22+Open*0.4,20,Max(1.0,Open*0.4),GColor($FC9DAB));
    if D.Resolved then begin
      D.Disc(X+55+D.After*70,Y-100-D.After*70,13,D.Accent,False);
      D.Line(X+65+D.After*70,Y-105-D.After*70,X+65+D.After*70,Y-145-D.After*70,D.Accent,6);
      if D.Action=1 then D.Line(X+65+D.After*70,Y-145-D.After*70,X+110+D.After*70,Y-145-D.After*70,D.Accent,7);
    end;
  end;
  D.Rect(390,120,220,35,GColor($E5C38C)); D.Line(500,155,500,255,D.Ink,8);
  D.Line(500,200,585,175+D.Sway*30,D.Ink,8); D.Star(585,175+D.Sway*30,18,0,D.Accent);
end;

procedure Moles(var D: TGDraw);
var I: Integer; X,Y,Side: Double;
begin
  D.Floor(410,GColor($D8AE7D));
  for I:=0 to 4 do begin
    X:=130+I*185; D.Oval(X,525,74,28,D.Ink); D.Oval(X,532,68,15,GColor($A97D61));
  end;
  D.Rect(110,190,175,120,D.Secondary); D.Rect(715,190,175,120,D.Accent);
  D.Quad(140,245,200,215,200,235,250,235,clWhite);
  D.Quad(200,235,250,235,250,255,200,255,clWhite);
  D.Quad(860,245,800,215,800,235,750,235,clWhite);
  D.Quad(800,235,750,235,750,255,800,255,clWhite);
  Side:=-1; if D.Action=1 then Side:=1;
  X:=500; Y:=500;
  if D.Active then begin
    if D.Age<0 then Y:=500-Sin(D.Wind*Pi/2)*160
    else begin X:=500+Side*D.After*330; Y:=340+Sqr(D.After)*160; end;
  end;
  D.Oval(X,Y+15,63,80,GColor($B6856F)); D.Disc(X,Y-35,65,GColor($B6856F));
  D.Disc(X-53,Y-65,24,GColor($B6856F)); D.Disc(X+53,Y-65,24,GColor($B6856F));
  D.Face(X,Y-36,53,0); D.Disc(X,Y-9,18,GColor($ED91A2));
  D.Line(X-58,Y+10,X-98,Y-15,D.Ink,13); D.Line(X+58,Y+10,X+98,Y-15,D.Ink,13);
  D.Rect(X-45,Y+50,90,65,GColor($F8D277)); D.Star(X,Y+80,25,0,D.Secondary);
  D.Burst(500,340);
end;

procedure Octopus(var D: TGDraw);
var I: Integer; X,Y,A,H: Double;
begin
  D.Floor(590,GColor($EFBDDF));
  D.Rect(90,120,820,55,GColor($FBEA90));
  for I:=0 to 6 do D.Disc(155+I*115,147,20,D.Accent,False);
  for I:=0 to 3 do begin
    X:=175+I*215; D.Rect(X-65,475,130,100,D.Secondary); D.Oval(X,475,67,24,clWhite);
    D.Line(X-60,510,X+60,560,D.Ink,4); D.Line(X+60,510,X-60,560,D.Ink,4);
  end;
  D.Oval(500,350,145,112,D.Accent); D.Disc(500,285,115,D.Accent); D.Face(500,275,90,Ord(D.Hit>0.3));
  for I:=0 to 7 do begin
    A:=(I-3.5)*0.25; X:=500+Sin(A)*270;
    H:=D.Hit; if (D.Action=1) and D.Resolved then H:=Abs(Sin(D.After*Pi*5+I));
    Y:=430+H*45+Sin(D.T*3+I)*8;
    D.Line(500+Sin(A)*110,355,X,Y,D.Ink,28); D.Line(500+Sin(A)*110,355,X,Y,D.Accent,21);
    D.Disc(X,Y,22,D.Accent); D.Line(X,Y,X+25,Y-40+H*60,D.Ink,8);
    D.Disc(X+25,Y-40+H*60,12,GColor($FBEA90));
  end;
  D.Burst(500,450);
end;

procedure Crab(var D: TGDraw);
var I: Integer; X,Y,Side: Double;
begin
  D.Floor(470,GColor($F5DC9B)); D.Rect(-500,350,2000,110,GColor($83D7E7),False);
  for I:=0 to 7 do D.Cloud(65+I*140,460,30,clWhite);
  Side:=-1; if D.Action=1 then Side:=1;
  X:=500+Side*D.Hit*110; Y:=430+D.Sway*8;
  for I:=0 to 3 do begin
    D.Line(X-65,Y+I*13,X-120-I*12,Y+50+Sin(D.T*10+I)*12,D.Ink,10);
    D.Line(X+65,Y+I*13,X+120+I*12,Y+50+Sin(D.T*10+I+Pi)*12,D.Ink,10);
  end;
  D.Oval(X,Y,110,72,D.Accent);
  D.Line(X-44,Y-45,X-55,Y-95,D.Ink,10); D.Line(X+44,Y-45,X+55,Y-95,D.Ink,10);
  D.Disc(X-55,Y-98,22,clWhite); D.Disc(X+55,Y-98,22,clWhite);
  D.Disc(X-55,Y-100,8,D.Ink,False); D.Disc(X+55,Y-100,8,D.Ink,False); D.Face(X,Y,50,1);
  for I:=-1 to 1 do if I<>0 then begin
    D.Line(X+I*85,Y-10,X+I*165,Y-80,D.Ink,16); D.Disc(X+I*170,Y-100,43,D.Accent);
    D.Quad(X+I*170,Y-100,X+I*150,Y-145,X+I*190,Y-145,X+I*170,Y-100,D.Paper);
  end;
  if D.HasCue then begin
    D.Gear(GMix(850,500,D.Wind),565,35,D.T*3,GColor($9E8DAC));
    D.Star(500-Side*180,320,40,0,D.Secondary);
  end;
  D.Burst(X,Y);
end;

procedure Chicks(var D: TGDraw);
var I: Integer; X,Y,Jump: Double;
begin
  D.Disc(790,120,65,GColor($FFE28E),False); D.Floor(555,GColor($A0D590));
  for I:=0 to 8 do begin D.Rect(65+I*110,350,14,180,clWhite,False); end;
  D.Rect(65,395,895,18,clWhite,False); D.Rect(65,455,895,18,clWhite,False);
  Jump:=0; if D.Active and (D.Age<0) and (D.Action=1) then Jump:=Sin(D.Wind*Pi)*125;
  for I:=0 to 4 do begin
    X:=175+I*158; Y:=465-Jump+Sin(D.T/D.Beat*2*Pi-I*0.6)*7;
    D.Disc(X,Y,52,GColor($FFDA63)); D.Disc(X+16,Y-43,40,GColor($FFE58B));
    D.Disc(X+30,Y-50,6,D.Ink,False);
    D.Quad(X+49,Y-44,X+74,Y-33,X+45,Y-25,X+49,Y-44,GColor($F39152));
    D.Oval(X-5,Y+5,24,32,D.Accent);
    D.Line(X-17,Y+43,X-20+D.Sway*13,Y+83,D.Ink,6); D.Line(X+17,Y+43,X+20-D.Sway*13,Y+83,D.Ink,6);
  end;
  if D.Action=1 then D.Rect(430,520,100,35,GColor($D99B71));
  D.Burst(500,520);
end;

procedure Jellyfish(var D: TGDraw);
var I,J: Integer; X,Y,R,Glow: Double;
begin
  D.Floor(600,GColor($87C8E1));
  for I:=0 to 10 do D.Disc(70+I*89,160+Frac(D.T*0.14+I*0.37)*400,6+I mod 3*3,clWhite,False);
  Glow:=D.Hit; if D.Action=1 then Glow:=Min(1.0,Glow*1.5);
  for I:=0 to 2 do begin
    X:=230+I*270; Y:=310+Sin(D.T/D.Beat*Pi+I)*24; R:=82+Glow*(10+I*2);
    if D.Resolved then D.Disc(X,Y,R+35,D.Secondary,False);
    for J:=0 to 5 do
      D.Line(X-60+J*24,Y+35,X-70+J*28+Sin(D.T*4+J)*17,Y+190,D.Accent,10);
    D.Oval(X,Y,R,R*0.8,D.Accent); D.Rect(X-R,Y,2*R,40,D.Accent,False);
    D.Face(X,Y+3,R*0.60,Ord(D.Hit>0.3));
    D.Spark(X-30,Y-25,12+Glow*14);
    if D.Action=1 then begin D.Star(X-95,Y-70,15+Glow*14,D.T,D.Secondary); D.Star(X+95,Y-70,15+Glow*14,-D.T,D.Secondary); end;
  end;
  D.Burst(500,300);
end;

procedure Bee(var D: TGDraw);
var I,J: Integer; X,Y,FX,FY: Double;
begin
  D.Floor(565,GColor($A6D98B));
  for I:=0 to 3 do begin
    FX:=160+I*225; FY:=390+(I mod 2)*60;
    D.Line(FX,FY,FX,610,GColor($4F976D),12);
    for J:=0 to 5 do D.Disc(FX+Cos(J*Pi/3)*43,FY+Sin(J*Pi/3)*43,32,D.Secondary);
    D.Disc(FX,FY,35,GColor($FFE581));
    if (I=2) and (D.Action=1) then begin
      D.Gear(FX,FY,36,D.T,D.Ink); D.Line(FX-16,FY-12,FX+16,FY+12,clWhite,7);
    end;
  end;
  X:=GMix(280,610,D.Wind); Y:=265+Sin(D.T*3)*18;
  if D.HasCue then begin
    if D.Age<0 then Y:=GMix(210,360,D.Wind)-Sin(D.Wind*Pi)*40
    else begin X:=GMix(610,820,D.After); Y:=GMix(360,240,D.After); end;
    if D.Action=1 then
      if D.Age<0 then Y:=Y-Sin(D.Wind*Pi)*20-Power(D.Wind,4)*90
      else Y:=Y-D.Hit*90;
  end;
  D.Oval(X-30,Y-55,42,52+Sin(D.T*35)*12,clWhite); D.Oval(X+25,Y-55,42,52-Sin(D.T*35)*12,clWhite);
  D.Oval(X,Y,75,52,GColor($FFDB6B));
  for I:=0 to 2 do D.Line(X-48+I*30,Y-36,X-48+I*30,Y+36,D.Ink,12);
  D.Disc(X+57,Y-8,44,GColor($FFE583)); D.Face(X+60,Y-8,35,1);
  D.Line(X+60,Y-45,X+65,Y-80,D.Ink,5); D.Disc(X+65,Y-80,8,D.Accent,False);
  if D.Ending>0 then begin
    D.Rect(X-80,Y+25,60,65,GColor($EAB66B));
    D.Disc(X-50,Y+20,33,GColor($FFE283)); D.Star(X-50,Y+20,20,D.T,D.Secondary);
  end;
  if D.Action=0 then D.Burst(610,390);
end;

procedure DrawGAnimals(var D: TGDraw);
begin
  case D.Game of
    8: Penguin(D); 9: Frogs(D); 10: Moles(D); 11: Octopus(D);
    12: Crab(D); 13: Chicks(D); 14: Jellyfish(D); 15: Bee(D);
  end;
end;
end.
