unit RhythmGDaily;
// 日常8ゲームの専用舞台と対象物の軌道。描画状態を蓄積せずTGDrawの実音位相だけを使う。
interface
uses RhythmGDraw;
procedure DrawGDaily(var D: TGDraw);
implementation
uses System.Math, Vcl.Graphics;

procedure Stamp(var D: TGDraw);
var X,Y: Double; I: Integer;
begin
  D.Window(660,85,220,180); D.Rect(115,100,170,125,GColor($FFD16A));
  for I:=0 to 2 do D.Rect(140,125+I*25,115,7,D.Ink,False);
  D.Person(340,380,1.50,D.Secondary,0);
  D.Rect(278,248,124,18,D.Secondary); D.Disc(315,290,16,clWhite); D.Disc(365,290,16,clWhite);
  D.Line(331,290,349,290,D.Ink,4);
  D.Rect(90,480,820,110,GColor($DC9C6C));
  D.Rect(120,590,45,80,D.Ink); D.Rect(840,590,45,80,D.Ink);
  X:=585; if D.HasCue then
    if D.Age<0 then X:=GMix(880,585,D.Wind) else X:=GMix(585,230,D.After);
  D.Rect(X-74,430,148,70,clWhite);
  for I:=0 to 2 do D.Line(X-50,450+I*11,X+10,450+I*11,GColor($B2B6C7),3);
  if D.Action=1 then D.Star(X+40,451,22,-Pi/2,D.Accent);
  Y:=360+90*D.Hit;
  D.Line(400,370,560,Y-5,D.Ink,21); D.Disc(560,Y-5,19,GColor($FFE1BC));
  D.Rect(540,Y-30,40,55,D.Secondary); D.Rect(516,Y+16,88,24,D.Accent);
  if D.Resolved or (D.Ending>0) then begin
    D.Disc(X,468,22,D.Accent,False); D.Disc(X,468,15,clWhite,False);
    if D.Action=1 then D.Star(X,468,13,0,D.Accent) else D.Line(X-10,468,X+10,468,D.Accent,5);
  end;
  D.Burst(560,430);
end;

procedure Laundry(var D: TGDraw);
var X,Y,Lean: Double; I: Integer;
begin
  D.Floor(600,GColor($AEE3B0));
  for I:=0 to 2 do begin D.Line(90,140+I*22,910,140+I*22,D.Ink,3); end;
  for I:=0 to 4 do begin
    D.Rect(150+I*145,152,70,90,D.Secondary); D.Rect(160+I*145,145,7,20,D.Accent);
  end;
  Lean:=0; if D.Action=1 then Lean:=D.Hit*65;
  D.Person(365-Lean,445+Lean*0.3,1.6,D.Accent,Ord(D.Hit>0.3));
  D.Disc(310-Lean,300+Lean*0.3,26,D.Ink);
  D.Quad(300-Lean,315+Lean*0.3,430-Lean,315+Lean*0.3,405-Lean,285+Lean*0.3,325-Lean,285+Lean*0.3,D.Secondary);
  D.Rect(240,535,230,90,GColor($F4CF7C));
  for I:=0 to 5 do D.Line(270+I*30,550,270+I*30,608,D.Ink,3);
  if D.HasCue then begin
    X:=GMix(900,440,D.Wind); Y:=GMix(250,405,D.Wind);
    if D.Resolved then begin X:=GMix(440,360,D.After); Y:=GMix(405,560,D.After); end;
    if D.Action=0 then begin
      D.Quad(X-35,Y-35,X-70,Y-5,X-50,Y+18,X-30,Y,clWhite);
      D.Quad(X+35,Y-35,X+70,Y-5,X+50,Y+18,X+30,Y,clWhite);
      D.Rect(X-35,Y-35,70,92,D.Secondary); D.Disc(X,Y-30,14,clWhite,False);
    end else begin
      if D.Resolved then X:=GMix(440,110,D.After);
      D.Rect(X-20,Y-36,42,68,D.Ink); D.Rect(X-20,Y+15,83,30,D.Ink);
      D.Line(X-12,Y-10,X+14,Y-10,clWhite,4);
    end;
  end;
  if D.Action=0 then D.Burst(430,420);
end;

procedure Alarm(var D: TGDraw);
var X,Y,A: Double; I: Integer;
begin
  D.Window(110,80,235,190); D.Floor(590,GColor($DBB4EA));
  D.Rect(95,440,450,140,D.Secondary); D.Rect(110,420,420,60,clWhite);
  D.Cloud(235,410,65,clWhite); D.Person(350,400,1.4,D.Accent,0);
  D.Quad(298,285,405,285,372,220,298,285,D.Secondary); D.Disc(372,220,17,clWhite);
  D.Rect(600,485,280,110,GColor($F4C888));
  for I:=0 to 1 do begin
    X:=670+I*135; Y:=345+Sin(D.T*2+I)*4;
    if D.Active and (D.Action=I) and not D.Resolved then X:=X+Sin(D.T*65)*5;
    if I=0 then begin D.Disc(X-35,Y-65,25,D.Accent); D.Disc(X+35,Y-65,25,D.Accent); end
    else begin D.Rect(X-50,Y-85,100,30,D.Secondary); D.Line(X-45,Y-85,X+45,Y-85,D.Ink,7); end;
    D.Disc(X,Y,65,clWhite); A:=D.T*0.35;
    D.Line(X,Y,X+Sin(A)*37,Y-Cos(A)*37,D.Ink,5); D.Line(X,Y,X-23,Y-10,D.Ink,6);
    D.Line(X-35,Y+48,X-43,Y+90,D.Ink,9); D.Line(X+35,Y+48,X+43,Y+90,D.Ink,9);
  end;
  X:=670+D.Action*135; Y:=215+D.Hit*70;
  D.Line(400,365,X,Y,D.Ink,23); D.Disc(X,Y,30,GColor($FFE1BC));
  if D.Active and not D.Resolved then for I:=0 to 2 do
    D.Line(X+70+I*15,290-I*20,X+85+I*15,275-I*20,D.Accent,5);
  D.Burst(X,300);
end;

procedure Chef(var D: TGDraw);
var X,Y: Double; I: Integer;
begin
  for I:=0 to 4 do begin D.Rect(100+I*165,85,145,130,D.Secondary); D.Disc(225+I*165,155,6,D.Ink,False); end;
  D.Person(340,390,1.65,clWhite,0); D.Cloud(340,212,62,clWhite);
  D.Rect(90,535,820,105,GColor($8CCBDD)); D.Rect(575,505,175,35,D.Ink);
  X:=600; Y:=435-12*D.Hit;
  D.Line(420,405,555,Y,D.Ink,18); D.Line(510,Y+12,610,Y+12,D.Ink,15);
  D.Oval(X+45,Y+14,85,23,D.Ink); D.Oval(X+45,Y+7,75,15,GColor($9DAAB8));
  if D.HasCue then begin
    X:=GMix(840,645,D.Wind); Y:=GMix(225,416,D.Wind)-Sin(D.Wind*Pi)*110;
    if D.Action=0 then begin X:=645+Sin(D.Wind*Pi)*80; Y:=416-Sin(D.Wind*Pi)*190; end;
    if D.Resolved then begin
      if D.Action=0 then begin X:=645; Y:=416-12*D.Hit; end
      else begin X:=GMix(645,850,D.After); Y:=416-Sin(D.After*Pi)*180; end;
    end;
    if D.Action=0 then begin D.Disc(X,Y,32,GColor($FFA950)); D.Star(X,Y-23,17,0,GColor($62A875)); end
    else D.Ball(X,Y,34,3);
  end;
  D.Burst(645,420);
end;

procedure Sushi(var D: TGDraw);
var X,Y: Double; I: Integer;
begin
  D.Rect(95,85,810,60,D.Accent); D.Rect(135,102,220,24,clWhite,False);
  D.Person(385,365,1.65,D.Secondary,0);
  D.Disc(385,196,24,D.Ink); D.Rect(318,228,134,20,clWhite);
  D.Rect(70,480,860,125,D.Ink); D.Rect(80,495,840,90,GColor($ECD9BE),False);
  for I:=0 to 10 do D.Line(80+Frac(D.T*0.2+I/11)*840,500,80+Frac(D.T*0.2+I/11)*840,580,GColor($CEB695),3);
  for I:=0 to 3 do begin
    X:=110+I*225; D.Oval(X,560,67,16,D.Secondary); D.Rect(X-35,520,70,35,clWhite);
    D.Rect(X-40,507,80,23,GColor($F99288));
  end;
  D.Rect(700,195,160,170,clWhite); D.Oval(780,295,51,15,D.Accent);
  D.Rect(749,245,62,40,clWhite); D.Rect(745,236,70,20,GColor($F99288));
  if D.HasCue then begin
    X:=GMix(870,490,D.Wind); Y:=515;
    if D.Resolved then
      if D.Action=0 then begin X:=GMix(490,392,D.After); Y:=GMix(515,300,D.After); end
      else X:=GMix(490,110,D.After);
    D.Oval(X,Y+35,70,17,D.Accent); D.Rect(X-35,Y,70,34,clWhite);
    if D.Action=0 then D.Rect(X-40,Y-14,80,25,GColor($F99288))
    else begin D.Rect(X-35,Y-17,70,47,GColor($497E6F)); D.Disc(X,Y-7,19,GColor($B8E78C)); end;
  end;
  if D.Action=0 then D.Burst(490,450);
end;

procedure Clockmaker(var D: TGDraw);
var X,Y: Double;
begin
  D.Rect(110,90,270,230,GColor($C2E7DD)); D.Gear(190,180,60,D.T*0.5,D.Accent);
  D.Gear(300,245,50,-D.T*0.6,D.Secondary);
  D.Rect(535,100,320,440,GColor($DCAB73)); D.Disc(695,240,125,clWhite);
  D.Line(695,240,695+Sin(D.T)*75,240-Cos(D.T)*75,D.Ink,8);
  D.Line(695,240,645,220,D.Ink,10); D.Line(695,360,695+Sin(D.T*3)*45,455,D.Ink,9);
  D.Disc(695+Sin(D.T*3)*45,455,32,D.Accent);
  D.Person(315,460,1.55,D.Secondary,0); D.Floor(600,GColor($F2CA90));
  D.Disc(340,370,24,clWhite); D.Disc(340,370,16,GColor($B8E4EF));
  D.Line(360,370,380,385,D.Ink,5); D.Rect(285,448,60,65,GColor($DAB484));
  D.Disc(600,350,42,D.Ink); D.Disc(600,350,12,clWhite);
  if D.HasCue then begin
    X:=GMix(420,600,D.Wind); Y:=GMix(440,350,D.Wind);
    if D.Resolved then begin X:=600; Y:=350; end;
    D.Gear(X,Y,50,D.T*1.5,D.Accent);
  end;
  if D.Ending>0 then D.Gear(600,350,50,D.T*1.5,D.Accent);
  D.Burst(600,350);
end;

procedure Delivery(var D: TGDraw);
var X,Y,Side: Double; I: Integer;
begin
  D.Rect(410,65,180,140,GColor($B8D6F3));
  for I:=0 to 3 do D.Line(430,90+I*27,570,90+I*27,D.Ink,4);
  D.Person(500,410,1.6,D.Secondary,Ord(D.Hit>0.35));
  D.Rect(445,248,110,35,D.Secondary); D.Rect(430,277,155,15,D.Accent);
  D.Rect(100,460,245,170,D.Accent); D.Rect(655,460,245,170,D.Secondary);
  D.Quad(180,515,225,485,270,515,225,545,clWhite);
  D.Star(775,520,40,0,clWhite);
  if D.Ending>0 then for I:=0 to 2 do begin
    D.Rect(155+I*42,405-I mod 2*35,70,55,GColor($EAC18B));
    D.Rect(705+I*42,405-I mod 2*35,70,55,GColor($EAC18B));
  end;
  if D.HasCue then begin
    Side:=225; if D.Action=1 then Side:=775;
    X:=500; Y:=GMix(180,340,D.Wind);
    if D.Resolved then begin X:=GMix(500,Side,D.After); Y:=GMix(340,500,D.After)-Sin(D.After*Pi)*100; end;
    D.Rect(X-50,Y-40,100,80,GColor($EAC18B)); D.Line(X,Y-36,X,Y+36,clWhite,12);
    if D.Action=0 then D.Quad(X-22,Y,X,Y-18,X+22,Y,X,Y+18,D.Accent)
    else D.Star(X,Y,23,0,D.Secondary);
  end;
  D.Burst(500,340);
end;

procedure Barber(var D: TGDraw);
var X,Y,A: Double; I: Integer;
begin
  D.Rect(540,85,330,365,clWhite); D.Rect(555,100,300,335,GColor($BDE9EE));
  for I:=0 to 6 do D.Quad(125,120+I*50,175,140+I*50,175,168+I*50,125,148+I*50,D.Accent);
  D.Line(150,110,150,495,D.Ink,9); D.Disc(150,102,34,clWhite);
  D.Person(305,430,1.55,D.Secondary,0);
  D.Disc(260,292,26,D.Ink); D.Disc(298,279,29,D.Ink); D.Disc(337,290,25,D.Ink);
  D.Rect(525,480,250,95,D.Accent); D.Line(650,575,650,630,D.Ink,15); D.Line(580,630,720,630,D.Ink,12);
  D.Quad(545,405,755,405,795,510,505,510,D.Secondary);
  D.Disc(650,330,82,GColor($FFE1BC)); D.Face(650,340,68,Ord(D.Hit>0.3));
  for I:=0 to 6 do D.Disc(584+I*22,274+Sin(I)*8,27,D.Ink,False);
  if D.Ending>0 then begin
    D.Line(590,262,710,262,D.Secondary,8); D.Spark(735,290,24+D.Pulse*8);
  end;
  X:=D.Hit*60; Y:=310-25*D.Hit; A:=30*(1-D.Hit);
  D.Line(380,385,520+X,Y,D.Ink,18);
  if D.Action=0 then begin
    D.Disc(510+X,Y+18,15,D.Secondary); D.Disc(510+X,Y-18,15,D.Secondary);
    D.Line(520+X,Y+15,590+X,Y-A,D.Ink,7); D.Line(520+X,Y-15,590+X,Y+A,D.Ink,7);
    if D.Resolved then for I:=0 to 4 do D.Line(620+I*18+D.After*30,280+D.After*140,
      628+I*18+D.After*30,290+D.After*140,D.Ink,4);
  end else begin
    D.Rect(510+X,Y-15,100,18,D.Accent);
    for I:=0 to 7 do D.Line(520+X+I*11,Y,520+X+I*11,Y+30,D.Ink,4);
  end;
  D.Burst(610,300);
end;

procedure DrawGDaily(var D: TGDraw);
begin
  case D.Game of
    0: Stamp(D); 1: Laundry(D); 2: Alarm(D); 3: Chef(D);
    4: Sushi(D); 5: Clockmaker(D); 6: Delivery(D); 7: Barber(D);
  end;
end;
end.
