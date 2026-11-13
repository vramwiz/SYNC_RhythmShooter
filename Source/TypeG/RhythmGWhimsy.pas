unit RhythmGWhimsy;
// 不思議・コミカル8ゲーム。組立・交信・発見・変身・変形・破壊・歩行・連鎖を個別に描く。
interface
uses RhythmGDraw;
procedure DrawGWhimsy(var D: TGDraw);
implementation
uses System.Math, Vcl.Graphics;

procedure Factory(var D: TGDraw);
var I: Integer; X,Y: Double;
begin
  for I:=0 to 3 do begin
    D.Rect(110+I*210,85,150,100,D.Secondary); D.Gear(185+I*210,135,35,D.T*(1-I mod 2*2),D.Accent);
  end;
  D.Floor(575,GColor($C5DFDF)); D.Rect(90,500,820,65,D.Ink);
  for I:=0 to 10 do D.Disc(130+I*73,533,20,GColor($9EBCD1));
  D.Rect(400,350,180,150,D.Secondary); D.Rect(445,370,90,65,clWhite);
  D.Star(490,402,23,D.T,D.Accent); D.Line(430,500,415,540,D.Ink,15); D.Line(550,500,565,540,D.Ink,15);
  D.Line(400,385,330,440,D.Ink,21); D.Disc(330,440,30,D.Accent);
  D.Line(580,385,650,440,D.Ink,21); D.Disc(650,440,30,D.Accent);
  D.Line(160,240,160,330,D.Ink,24); D.Line(160,330,300,270,D.Ink,24);
  D.Line(300,270,370+D.Wind*100,260-D.Wind*20,D.Ink,20);
  X:=GMix(850,490,D.Wind); Y:=GMix(265,280,D.Wind);
  if D.HasCue or (D.Ending>0) then begin
    if D.Ending>0 then begin X:=490; Y:=280; end;
    if D.Action=0 then begin
      D.Rect(X-65,Y-50,130,95,GColor($D5F1F0)); D.Disc(X-27,Y-8,11,D.Ink,False); D.Disc(X+27,Y-8,11,D.Ink,False);
      D.Line(X-25,Y+21,X+25,Y+21,D.Accent,6);
    end else begin
      D.Gear(X,Y,70,D.T,D.Accent); D.Disc(X,Y,30,clWhite); D.Star(X,Y,24,-D.T,D.Secondary);
      D.Line(430,335,380-D.Hit*30,265,D.Secondary,17); D.Line(550,335,600+D.Hit*30,265,D.Secondary,17);
    end;
  end;
  D.Burst(490,280);
end;

procedure AlienShape(var D: TGDraw; X,Y,S: Double; Color: TColor; Open: Double);
begin
  D.Oval(X,Y,S*0.8,S,Color); D.Oval(X-S*0.32,Y-S*0.15,S*0.15,S*0.24,D.Ink);
  D.Oval(X+S*0.32,Y-S*0.15,S*0.15,S*0.24,D.Ink);
  D.Disc(X-S*0.35,Y-S*0.22,S*0.05,clWhite,False); D.Disc(X+S*0.30,Y-S*0.22,S*0.05,clWhite,False);
  D.Oval(X,Y+S*0.4,S*0.22,S*(0.04+Open*0.18),D.Ink);
  D.Line(X,Y+S*0.85,X-S*0.2,Y+S*1.65,D.Ink,12);
  D.Line(X,Y+S*0.85,X+S*0.3,Y+S*1.65,D.Ink,12);
  D.Line(X-S*0.4,Y+S*0.6,X-S*1.2,Y+S*(0.6-Open),D.Ink,10);
  D.Line(X+S*0.4,Y+S*0.6,X+S*1.2,Y+S*(0.6-Open),D.Ink,10);
  D.Line(X,Y-S*0.9,X,Y-S*1.3,D.Ink,5); D.Disc(X,Y-S*1.4,S*0.16,D.Accent);
end;
procedure Aliens(var D: TGDraw);
var I: Integer; X,Power: Double;
begin
  D.Floor(570,GColor($D1B8ED));
  for I:=0 to 4 do begin X:=100+I*200;
    D.Star(X,120+I mod 2*55,20,D.T*0.2,D.Secondary);
  end;
  D.Oval(500,240,175,45,D.Secondary); D.Disc(500,210,80,GColor($B3EAF1)); D.Oval(500,245,175,25,D.Accent);
  for I:=0 to 6 do D.Disc(380+I*40,245,10,clWhite,False);
  AlienShape(D,250,380+D.Sway*8,83,D.Secondary,D.Wind);
  Power:=D.Hit; if (D.Action=1) and D.Resolved then Power:=1-D.After*0.35;
  AlienShape(D,750,380-D.Sway*8,83,D.Accent,Power);
  for I:=0 to 4 do begin
    X:=360+I*70; D.Disc(X,420,12+(D.Wind+Power)*12,clWhite,False);
    if D.Action=1 then D.Rect(X-18,475,36,16,D.Secondary,False);
  end;
  if D.Resolved then D.Spark(750,220,30+Power*25);
end;

procedure GhostShape(var D: TGDraw; X,Y,R: Double; Fake: Boolean);
var I: Integer;
begin
  D.Disc(X,Y,R,clWhite); D.Rect(X-R+4,Y,2*R-8,R*0.65,clWhite,False);
  for I:=0 to 3 do D.Disc(X-R+R*0.25+I*R*0.5,Y+R*0.6,R*0.25,clWhite,False);
  D.Face(X,Y,R*0.7,2);
  if Fake then begin
    D.Line(X-R*0.7,Y+R*0.8,X+R*0.6,Y+R*0.8,D.Ink,7);
    D.Rect(X-R*0.6,Y+R*0.95,R*1.2,18,GColor($AD8CC4));
  end;
end;
procedure Ghosts(var D: TGDraw);
var I: Integer; X,Y: Double;
begin
  D.Floor(585,GColor($D6C5EB));
  for I:=0 to 2 do begin
    X:=170+I*320; D.Rect(X-85,135,170,340,D.Secondary); D.Rect(X-70,150,140,310,D.Paper,False);
    D.Disc(X+53,310,9,D.Accent);
  end;
  D.Person(360,485,1.15,D.Accent,0); D.Disc(445,385,49,clWhite);
  D.Disc(445,385,35,GColor($D7F0F5)); D.Line(417,420,395,452,D.Ink,14);
  if D.HasCue then begin
    X:=650; Y:=GMix(470,325,D.Wind);
    if D.Resolved then begin X:=650+Sin(D.After*Pi)*45; Y:=325-D.After*80; end;
    GhostShape(D,X,Y,76,D.Action=1);
    if (D.Action=0) and D.Resolved then begin
      D.Star(650,215,48,-Pi/2,D.Accent); D.Burst(650,325);
    end;
    if D.Action=1 then D.Line(400,345,450,335,D.Ink,7);
  end;
end;

procedure Magic(var D: TGDraw);
var I: Integer; X,Y,Power: Double;
begin
  D.Floor(590,GColor($D3C0ED)); D.Window(675,95,195,180);
  for I:=0 to 3 do begin
    D.Rect(110+I*60,110,42,145,D.Secondary); D.Star(130+I*60,160,13,0,D.Accent);
  end;
  D.Person(320,455,1.60,D.Secondary,0);
  D.Quad(240,300,320,120,405,300,240,300,D.Secondary); D.Star(325,240,22,D.T,D.Accent);
  D.Rect(240,295,165,18,D.Accent); D.Line(420,415,535,305-D.Hit*35,D.Ink,11);
  D.Star(535,305-D.Hit*35,30,D.T*2,D.Accent);
  D.Rect(615,500,205,35,GColor($EAB284)); D.Line(650,535,630,620,D.Ink,12); D.Line(785,535,805,620,D.Ink,12);
  X:=715; Y:=415;
  if not D.Resolved and (D.Ending=0) then begin
    D.Rect(X-45,Y-40,90,80,GColor($B7BEC9)); D.Line(X-20,Y-30,X+30,Y+22,D.Ink,4);
  end else begin
    Power:=1; if D.Action=1 then Power:=1.35;
    if D.Action=0 then begin
      D.Disc(X,Y,57,D.Accent); D.Disc(X-35,Y-45,28,D.Accent); D.Disc(X+35,Y-45,28,D.Accent); D.Face(X,Y,46,1);
    end else begin
      D.Cloud(X,Y+20,80,D.Accent); D.Quad(X-55,Y+10,X,Y-115,X+60,Y+10,X-55,Y+10,D.Accent);
      D.Star(X,Y-30,40,-D.T,D.Secondary);
    end;
    for I:=0 to 6 do D.Spark(X+Cos(I*Pi/3.5+D.T)*100*Power,Y+Sin(I*Pi/3.5+D.T)*95,12);
  end;
  D.Burst(X,Y);
end;

procedure JellyMarch(var D: TGDraw);
var I: Integer; X,Y,SX,SY,Jump: Double;
begin
  D.Floor(565,GColor($FFE5AD));
  for I:=0 to 5 do begin
    D.Line(120+I*155,150,120+I*155,550,D.Secondary,12);
    D.Disc(120+I*155,180,45,D.Accent); D.Disc(120+I*155,180,25,clWhite);
  end;
  SX:=1; SY:=1; Jump:=0;
  if D.Active then
    if D.Action=0 then begin if D.Age<0 then Jump:=Sin(D.Wind*Pi)*135; SX:=1+D.Hit*0.15; SY:=1-D.Hit*0.18; end
    else begin SX:=1+D.Hit*0.65; SY:=1-D.Hit*0.55; end;
  for I:=0 to 3 do begin
    X:=165+I*220; Y:=475-Jump+Sin(D.T/D.Beat*2*Pi-I)*10;
    D.Oval(X,Y,72*SX,85*SY,D.Secondary); D.Rect(X-69*SX,Y,138*SX,70*SY,D.Secondary,False);
    D.Oval(X,Y+68*SY,69*SX,18*SY,D.Secondary); D.Face(X,Y+10,45,1);
    D.Oval(X-25*SX,Y-35*SY,19*SX,13*SY,clWhite);
  end;
  if D.Action=0 then D.Rect(540-D.Wind*190,520,70,45,D.Accent)
  else begin D.Rect(300,400,400,35,D.Accent); D.Rect(300,400,30,160,D.Accent); D.Rect(670,400,30,160,D.Accent); end;
  D.Burst(500,535);
end;

procedure Wrecking(var D: TGDraw);
var I,J: Integer; X,Y,Angle: Double;
begin
  D.Floor(590,GColor($E9D6B1));
  D.Rect(110,220,70,355,D.Accent); D.Rect(110,200,475,42,D.Accent);
  for I:=0 to 6 do begin D.Line(125+I*55,205,160+I*55,236,D.Ink,5); end;
  D.Rect(80,490,170,95,D.Secondary); D.Disc(110,585,35,D.Ink); D.Disc(220,585,35,D.Ink);
  for I:=0 to 2 do for J:=0 to 3 do begin
    X:=675+I*65; Y:=345+J*57;
    if D.Resolved then begin X:=X+D.After*(90+I*12)*(1+D.Action*0.25); Y:=Y+D.After*D.After*90; end;
    if D.Ending>0 then begin X:=650+I*78+J*12; Y:=548+(J mod 2)*18; end;
    D.Rect(X,Y,62,54,GColor($EEA088));
    if (I+J) mod 2=0 then D.Rect(X+15,Y+10,28,28,GColor($FCEDC8));
  end;
  Angle:=-0.85+0.8*D.Sway;
  if D.HasCue then
    if D.Age<0 then Angle:=GMix(-1.05,0.40+D.Action*0.13,D.Wind)
    else Angle:=GMix(0.40+D.Action*0.13,0.05,D.After);
  X:=510+Sin(Angle)*325; Y:=225+Cos(Angle)*325;
  D.Line(510,225,X,Y,D.Ink,10); D.Disc(X,Y,66+10*D.Action,GColor($7E9FB1));
  D.Disc(X-22,Y-23,16,clWhite,False); D.Burst(690,500);
  if D.Ending>0 then D.Star(790,245,65,-Pi/2,D.Accent);
end;

procedure GiantFeet(var D: TGDraw);
var I: Integer; X,Y,LeftLift,RightLift: Double;
begin
  D.Floor(570,GColor($BDD9A3));
  for I:=0 to 8 do begin
    X:=65+I*110; D.Rect(X,370+I mod 3*25,75,190,D.Secondary);
    D.Rect(X+15,395+I mod 3*25,15,22,clWhite); D.Rect(X+45,395+I mod 3*25,15,22,clWhite);
  end;
  LeftLift:=18+Max(0.0,D.Sway)*22; RightLift:=18+Max(0.0,-D.Sway)*22;
  if D.Active then begin
    if D.Action=0 then LeftLift:=(1-D.Wind)*130*(1-Ord(D.Resolved))
    else RightLift:=(1-D.Wind)*130*(1-Ord(D.Resolved));
  end;
  D.Rect(270,50,460,130,D.Accent); D.Rect(330,160,340,110,D.Secondary);
  for I:=0 to 1 do begin
    X:=365+I*270; Y:=LeftLift; if I=1 then Y:=RightLift;
    D.Line(X,220,X,420-Y,D.Ink,85); D.Line(X,220,X,420-Y,D.Secondary,70);
    D.Disc(X,350-Y,49,D.Accent); D.Rect(X-95,430-Y,190,115,D.Ink);
    D.Rect(X-88,435-Y,176,92,D.Accent); D.Rect(X-95,527-Y,190,18,D.Ink,False);
  end;
  D.Rect(470,535,60,35,GColor($F6B577)); D.Star(500,500,18,D.T,D.Accent);
  if D.Action=0 then D.Burst(365,550) else D.Burst(635,550);
end;

procedure Chain(var D: TGDraw);
var I: Integer; X,Y,P: Double;
begin
  D.Floor(600,GColor($EAC69D));
  D.Rect(100,330,230,24,D.Secondary); D.Rect(120,355,20,235,D.Ink); D.Rect(290,355,20,235,D.Ink);
  D.Line(330,342,480,440,D.Secondary,14); D.Rect(400,440,190,20,D.Accent);
  D.Quad(485,460,510,460,500,550,485,460,D.Secondary);
  D.Line(500,450,600,380-D.Hit*80,D.Ink,12);
  D.Gear(675,385,85,D.T*0.7+D.Hit*0.9,D.Secondary); D.Gear(805,450,68,-D.T*0.9-D.Hit*1.1,D.Accent);
  D.Rect(730,565,160,25,D.Secondary); D.Line(810,515,810,565,D.Ink,8);
  if D.HasCue then begin
    if D.Age<0 then begin
      P:=D.Wind;
      if P<0.55 then begin X:=GMix(120,320,P/0.55); Y:=302; end
      else begin X:=GMix(320,500,(P-0.55)/0.45); Y:=GMix(302,420,(P-0.55)/0.45); end;
    end else begin
      X:=GMix(500,805,D.After); Y:=420-Sin(D.After*Pi)*150;
    end;
    D.Ball(X,Y,27,D.Action*2);
    if D.Action=1 then begin
      for I:=0 to 4 do D.Star(620+I*45,245+Sin(I+D.T)*20,15,-D.T,D.Accent);
      D.Line(585,290,735,290,D.Secondary,12);
    end;
  end else if D.Ending=0 then D.Ball(155,302,27,0)
  else D.Ball(805,535,27,0);
  if D.Resolved then D.Spark(805,515,50*D.Hit);
  D.Burst(500,420);
  if D.Ending>0 then D.Star(805,300,57,-Pi/2,D.Accent);
end;

procedure DrawGWhimsy(var D: TGDraw);
begin
  case D.Game of
    24: Factory(D); 25: Aliens(D); 26: Ghosts(D); 27: Magic(D);
    28: JellyMarch(D); 29: Wrecking(D); 30: GiantFeet(D); 31: Chain(D);
  end;
end;
end.
