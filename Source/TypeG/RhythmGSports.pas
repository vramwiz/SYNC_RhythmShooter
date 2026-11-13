unit RhythmGSports;
// スポーツ8ゲーム。打点・着地・飛び移りは保存された実音時刻へ逆算して到達する。
interface
uses RhythmGDraw;
procedure DrawGSports(var D: TGDraw);
implementation
uses System.Math, Vcl.Graphics;

procedure Stadium(var D: TGDraw; FloorColor: TColor);
var I,J: Integer;
begin
  for J:=0 to 2 do for I:=0 to 11 do begin
    D.Disc(70+I*80,110+J*44+Sin(D.T/D.Beat*Pi+I)*4,15,D.Secondary,False);
    D.Rect(57+I*80,125+J*44,26,20,D.Accent,False);
  end;
  D.Floor(540,FloorColor);
end;

procedure PingPong(var D: TGDraw);
var X,Y,Arm: Double; I: Integer;
begin
  Stadium(D,GColor($F1CA8B));
  D.Rect(165,465,655,38,GColor($5CB8B0)); D.Line(210,503,185,620,D.Ink,15); D.Line(775,503,800,620,D.Ink,15);
  D.Line(492,470,492,390,D.Ink,6); D.Rect(492,390,100,70,clWhite);
  for I:=0 to 4 do D.Line(500+I*20,395,500+I*20,455,D.Secondary,2);
  D.Rect(155,280,150,160,D.Secondary); D.Rect(165,196,130,100,GColor($D9F3F0));
  D.Disc(195,241,12,D.Ink,False); D.Disc(265,241,12,D.Ink,False); D.Line(195,270,265,270,D.Ink,6);
  D.Line(230,195,230,165,D.Ink,6); D.Disc(230,155,13,D.Accent);
  Arm:=D.Hit*(70-35*D.Action); D.Line(300,340,382+Arm,355-Arm*0.3,D.Ink,18);
  D.Disc(405+Arm,345-Arm*0.3,42,D.Accent); D.Line(390+Arm,375,375+Arm,410,D.Ink,12);
  if D.HasCue then begin
    X:=GMix(880,445,D.Wind); Y:=GMix(330,355,D.Wind)-Sin(D.Wind*Pi)*(40+40*D.Action);
    if D.Resolved then begin X:=GMix(445,905,D.After); Y:=GMix(355,275,D.After)-Sin(D.After*Pi)*70; end;
    D.Disc(X,Y,20,clWhite);
    if D.Action=1 then for I:=0 to 2 do D.Line(X+35+I*18,Y+I*8,X+70+I*18,Y+I*8,D.Accent,4);
  end;
  D.Burst(445,355);
end;

procedure Rope(var D: TGDraw);
var I: Integer; X,Y,A,Jump,Phase: Double;
begin
  Stadium(D,GColor($B8E297));
  Jump:=0;
  if D.Active and (D.Age<0) then Jump:=Sin(D.Wind*Pi)*(105+60*D.Action);
  D.Person(500,420-Jump,1.65,D.Accent,0);
  D.Rect(430,290-Jump,140,16,D.Secondary);
  D.Disc(380,420-Jump,12,D.Secondary); D.Disc(620,420-Jump,12,D.Secondary);
  Phase:=D.T/D.Beat*Pi;
  if D.Active then Phase:=Pi/2+(D.Wind-1)*Pi*2;
  for I:=0 to 31 do begin
    A:=I*Pi/32; X:=500-125*Cos(A); Y:=420-Jump+Sin(A)*170*Sin(Phase);
    D.Line(X,Y,500-125*Cos((I+1)*Pi/32),420-Jump+Sin((I+1)*Pi/32)*170*Sin(Phase),D.Secondary,8);
  end;
  if D.Action=1 then begin D.Star(250,340,36,D.T,D.Secondary); D.Star(750,340,36,-D.T,D.Secondary); end;
  D.Burst(500,565);
end;

procedure Boxing(var D: TGDraw);
var I: Integer; X,Y,Lean: Double;
begin
  Stadium(D,GColor($C4D5F6));
  for I:=0 to 2 do D.Line(90,300+I*90,910,300+I*90,D.Accent,7);
  D.Rect(90,260,25,330,clWhite); D.Rect(885,260,25,330,clWhite);
  Lean:=0; if D.Action=2 then Lean:=D.Hit*100;
  X:=410-Lean; Y:=410+Lean*0.45;
  D.Person(X,Y,1.65,D.Secondary,0);
  D.Disc(X-65,Y-95,22,D.Accent); D.Disc(X+65,Y-95,22,D.Accent);
  D.Rect(X-65,Y-148,130,20,D.Accent);
  D.Line(720,280,720,520,D.Ink,14); D.Disc(720,370,82,GColor($FFC98A)); D.Face(720,370,65,2);
  D.Rect(660,440,120,55,D.Accent); D.Disc(720,270,28,D.Accent);
  case D.Action of
    0:begin
      D.Line(X+55,Y,X+120+D.Hit*140,Y-10,D.Ink,18);
      D.Disc(X+125+D.Hit*140,Y-15,43,D.Accent);
      D.Disc(X-70,Y-35,38,D.Accent);
      D.Burst(650,370);
    end;
    1:begin
      D.Disc(X+40,Y-70-D.Hit*22,43,D.Accent); D.Disc(X-35,Y-65-D.Hit*22,43,D.Accent);
      if D.HasCue then begin
        D.Disc(GMix(830,475,D.Wind),Y-85,38,GColor($F29CC3));
        if D.Resolved then D.Spark(X+60,Y-90,50*D.Hit);
      end;
    end;
    2:begin
      D.Disc(X-60,Y+20,38,D.Accent); D.Disc(X+75,Y+10,38,D.Accent);
      if D.HasCue then D.Disc(GMix(850,300,D.Wind),325,40,GColor($F29CC3));
    end;
  end;
end;

procedure Trapeze(var D: TGDraw);
var X,Y,LX,RX: Double; I: Integer;
begin
  D.Quad(0,0,260,0,180,590,0,700,D.Accent); D.Quad(740,0,1000,0,1000,700,820,590,D.Accent);
  for I:=0 to 5 do D.Line(30+I*25,20,20+I*18,530,D.Secondary,4);
  D.Floor(605,GColor($F0D59B)); D.Rect(230,585,540,22,D.Secondary);
  LX:=310+Sin(D.T/D.Beat)*65; RX:=730-Sin(D.T/D.Beat)*55;
  D.Line(220,50,LX-45,330,D.Ink,5); D.Line(300,50,LX+45,330,D.Ink,5); D.Line(LX-50,330,LX+50,330,D.Secondary,13);
  D.Line(710,50,RX-45,330,D.Ink,5); D.Line(790,50,RX+45,330,D.Ink,5); D.Line(RX-50,330,RX+50,330,D.Accent,13);
  X:=LX; Y:=425;
  if D.HasCue then begin
    if D.Age<0 then begin X:=GMix(LX,RX,D.Wind); Y:=425-Sin(D.Wind*Pi)*170; end
    else begin X:=RX; Y:=425+D.Sway*5; end;
  end;
  D.Person(X,Y,1.2,D.Secondary,1);
  D.Disc(X+42,Y-105,20,D.Accent);
  if (D.Action=1) and D.Active then begin
    D.Star(X-120,Y-70,28,D.T*3,D.Accent); D.Star(X+120,Y-70,28,-D.T*3,D.Accent);
    D.Line(X-40,Y+50,X-90,Y+75,D.Ink,10); D.Line(X+40,Y+50,X+90,Y+75,D.Ink,10);
  end;
  D.Burst(RX,330);
end;

procedure Soccer(var D: TGDraw);
var X,Y,TX,TY: Double; I: Integer;
begin
  Stadium(D,GColor($87CB92));
  D.Rect(670,270,220,270,clWhite); D.Rect(680,280,200,250,GColor($BEE7DA),False);
  for I:=0 to 6 do D.Line(685+I*30,280,685+I*30,530,clWhite,3);
  for I:=0 to 7 do D.Line(680,285+I*34,880,285+I*34,clWhite,3);
  D.Line(65,600,935,600,clWhite,7); D.Person(385,420,1.7,D.Secondary,0);
  D.Line(367,418,407,418,clWhite,8); D.Line(407,418,382,458,clWhite,8);
  TX:=445; TY:=500;
  if D.Action=1 then begin TX:=400; TY:=300; D.Disc(400,300,58,GColor($FFE1BC)); D.Face(400,300,43,1); end;
  if D.Action=0 then D.Line(420,485,445+D.Hit*75,505-D.Hit*35,D.Ink,22);
  if D.HasCue then begin
    X:=GMix(880,TX,D.Wind); Y:=GMix(200+Ord(D.Action=0)*170,TY,D.Wind)-Sin(D.Wind*Pi)*65;
    if D.Resolved then begin X:=GMix(TX,840,D.After); Y:=GMix(TY,340,D.After)-Sin(D.After*Pi)*110; end;
    D.Ball(X,Y,35,1);
  end;
  D.Burst(TX,TY);
end;

procedure Ninja(var D: TGDraw);
var X,Y: Double; I: Integer;
begin
  D.Floor(580,GColor($D9C8A9)); D.Disc(800,135,65,GColor($FFE0A5),False);
  for I:=0 to 5 do begin D.Line(100+I*30,120,100+I*30,580,GColor($6FB597),10);
    D.Line(100+I*30,250,115+I*30,225,GColor($6FB597),9); end;
  D.Rect(745,145,130,340,GColor($E9B580));
  D.Disc(810,295,82,clWhite); D.Disc(810,295,57,D.Accent); D.Disc(810,295,32,clWhite); D.Disc(810,295,13,D.Ink);
  X:=350; Y:=435; if D.Action=1 then Y:=Y+D.Hit*70;
  D.Person(X,Y,1.5,D.Ink,0); D.Rect(X-46,Y-82,92,30,GColor($FFE1BC));
  D.Disc(X-18,Y-65,5,D.Ink,False); D.Disc(X+18,Y-65,5,D.Ink,False);
  D.Quad(X-35,Y-45,X-130,Y-20-D.Sway*15,X-115,Y-55,X-35,Y-65,D.Accent);
  if D.HasCue then
    if D.Action=0 then begin
      X:=GMix(410,810,D.Wind); Y:=GMix(380,295,D.Wind);
      D.Star(X,Y,35,D.T*15,GColor($8DAFC6)); D.Disc(X,Y,8,D.Ink,False); D.Burst(810,295);
    end else begin
      X:=GMix(920,180,D.Wind); D.Rect(X-70,330,140,45,GColor($B28D67));
      for I:=0 to 3 do D.Line(X-55+I*28,340,X-35+I*28,361,D.Ink,3);
    end;
end;

procedure Unicycle(var D: TGDraw);
var X,Y,Jump,Lean: Double;
begin
  D.Floor(615,GColor($F4CD95)); D.Line(70,545,930,545,D.Ink,9);
  D.Rect(80,545,60,90,D.Accent); D.Rect(860,545,60,90,D.Secondary);
  Jump:=0; if D.Active and (D.Action=1) and (D.Age<0) then Jump:=Sin(D.Wind*Pi)*85;
  Lean:=D.Sway*18; if D.Action=0 then Lean:=Lean+D.Hit*32;
  X:=500; Y:=480-Jump;
  D.Disc(X,Y,62,D.Ink); D.Disc(X,Y,48,clWhite);
  D.Line(X,Y,X+Cos(D.T*5)*46,Y+Sin(D.T*5)*46,D.Secondary,6);
  D.Line(X,Y,X-Cos(D.T*5)*46,Y-Sin(D.T*5)*46,D.Secondary,6);
  D.Line(X,Y-8,X,Y-90,D.Ink,13); D.Line(X-35,Y-90,X+35,Y-90,D.Ink,15);
  D.Person(X+Lean,Y-195,1.15,D.Accent,0);
  D.Line(X-95+Lean,Y-187,X+95+Lean,Y-187+D.Sway*35,D.Ink,9);
  D.Disc(X-105+Lean,Y-187,17,D.Secondary); D.Disc(X+105+Lean,Y-187+D.Sway*35,17,D.Secondary);
  if D.Action=1 then D.Rect(680-D.Wind*180,495,55,48,D.Secondary);
  D.Burst(X,540);
end;

procedure Balloon(var D: TGDraw);
var X,Y: Double; I: Integer;
begin
  D.Floor(590,GColor($F4D593));
  for I:=0 to 5 do begin
    D.Line(100+I*160,100,100+I*160,210,D.Ink,3); D.Star(100+I*160,220,28,D.Sway*0.2,D.Secondary);
  end;
  D.Rect(695,375,13,220,D.Ink); D.Rect(705,375,170,180,clWhite);
  for I:=0 to 6 do D.Line(710+I*25,380,710+I*25,550,D.Secondary,2);
  X:=385; Y:=425; if D.Action=1 then X:=X-D.Hit*95;
  D.Person(X,Y,1.5,D.Accent,Ord((D.Action=0) and (D.Hit>0.2)));
  if D.HasCue then begin
    X:=GMix(790,480,D.Wind); Y:=GMix(150,340,D.Wind);
    if D.Resolved then begin X:=GMix(480,750,D.After); Y:=340-Sin(D.After*Pi/2)*200; end;
    if D.Action=0 then begin
      D.Oval(X,Y,53,66,D.Secondary); D.Disc(X-16,Y-20,12,clWhite,False);
      D.Quad(X,Y+62,X-9,Y+77,X+9,Y+77,X,Y+62,D.Secondary);
      D.Line(X,Y+77,X+Sin(D.T*5)*20,Y+110,D.Ink,2);
    end else begin
      D.Gear(X,Y,49,D.T*4,D.Ink); D.Disc(X,Y,23,GColor($F6B76A));
    end;
  end;
  if D.Action=0 then D.Burst(480,340);
end;

procedure DrawGSports(var D: TGDraw);
begin
  case D.Game of
    16: PingPong(D); 17: Rope(D); 18: Boxing(D); 19: Trapeze(D);
    20: Soccer(D); 21: Ninja(D); 22: Unicycle(D); 23: Balloon(D);
  end;
end;
end.
