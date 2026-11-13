unit RhythmGDraw;
// Type.Gだけの図形部品とフレーム状態。1000x700の安全領域を出力へ等比配置する。
interface
uses Vcl.Graphics, RhythmRenderSurface, RhythmGPlan;
type
  TGDraw = record
    Surface: TAnimationRenderSurface;
    K,OX,OY,T,Local,Beat,Sway,Pulse,Hit,Wind,After,Age,Progress,Ending: Double;
    Game,Action,CueIndex: Integer;
    HasCue,Active,Resolved,BackgroundOnly: Boolean;
    Ink,Paper,Accent,Secondary: TColor;
    procedure Line(X1,Y1,X2,Y2: Double; Color: TColor; Width: Double=6);
    procedure Rect(X,Y,W,H: Double; Color: TColor; Border: Boolean=True);
    procedure Disc(X,Y,R: Double; Color: TColor; Border: Boolean=True);
    procedure Oval(X,Y,RX,RY: Double; Color: TColor);
    procedure Quad(X1,Y1,X2,Y2,X3,Y3,X4,Y4: Double; Color: TColor);
    procedure Face(X,Y,R: Double; Mood: Integer=0);
    procedure Person(X,Y,Size: Double; Color: TColor; Pose: Integer=0);
    procedure Star(X,Y,R,Angle: Double; Color: TColor);
    procedure Gear(X,Y,R,Angle: Double; Color: TColor);
    procedure Spark(X,Y,Size: Double);
    procedure Ball(X,Y,R: Double; Kind: Integer=0);
    procedure Cloud(X,Y,Size: Double; Color: TColor);
    procedure Window(X,Y,W,H: Double);
    procedure Floor(Y: Double; Color: TColor);
    procedure Burst(X,Y: Double);
  end;
function GColor(RGB: Cardinal): TColor;
function GSmooth(V: Double): Double;
function GMix(A,B,V: Double): Double;
implementation
uses System.Math, System.Types;
function GColor(RGB: Cardinal): TColor;
begin Result:=TColor(((RGB and $FF) shl 16) or (RGB and $FF00) or (RGB shr 16)); end;
function GSmooth(V: Double): Double;
begin V:=EnsureRange(V,0.0,1.0); Result:=V*V*(3-2*V); end;
function GMix(A,B,V: Double): Double;
begin Result:=A+(B-A)*EnsureRange(V,0.0,1.0); end;
procedure TGDraw.Line(X1,Y1,X2,Y2: Double; Color: TColor; Width: Double);
begin Surface.Line(OX+X1*K,OY+Y1*K,OX+X2*K,OY+Y2*K,Color,Width*K); end;
procedure TGDraw.Rect(X,Y,W,H: Double; Color: TColor; Border: Boolean);
begin
  if Border then Surface.FillRect(OX+X*K,OY+Y*K,OX+(X+W)*K,OY+(Y+H)*K,Ink);
  if Border then begin X:=X+4; Y:=Y+4; W:=W-8; H:=H-8; end;
  Surface.FillRect(OX+X*K,OY+Y*K,OX+(X+W)*K,OY+(Y+H)*K,Color);
end;
procedure TGDraw.Disc(X,Y,R: Double; Color: TColor; Border: Boolean);
begin
  if Border then Surface.Circle(OX+X*K,OY+Y*K,R*K,Ink,True);
  if Border then R:=Max(0.0,R-4);
  Surface.Circle(OX+X*K,OY+Y*K,R*K,Color,True);
end;
procedure TGDraw.Oval(X,Y,RX,RY: Double; Color: TColor);
var I: Integer; A,B: Double;
begin
  for I:=0 to 19 do begin
    A:=I*2*Pi/20; B:=(I+1)*2*Pi/20;
    Quad(X,Y,X+Cos(A)*RX,Y+Sin(A)*RY,X+Cos(B)*RX,Y+Sin(B)*RY,X,Y,Color);
  end;
end;
procedure TGDraw.Quad(X1,Y1,X2,Y2,X3,Y3,X4,Y4: Double; Color: TColor);
begin
  Surface.FillQuad(PointF(OX+X1*K,OY+Y1*K),PointF(OX+X2*K,OY+Y2*K),
    PointF(OX+X3*K,OY+Y3*K),PointF(OX+X4*K,OY+Y4*K),Color);
end;
procedure TGDraw.Face(X,Y,R: Double; Mood: Integer);
begin
  if Mood=1 then begin
    Line(X-R*0.45,Y,X-R*0.23,Y-R*0.12,Ink,4); Line(X+R*0.23,Y-R*0.12,X+R*0.45,Y,Ink,4);
  end else begin Disc(X-R*0.30,Y-R*0.1,R*0.075,Ink,False); Disc(X+R*0.30,Y-R*0.1,R*0.075,Ink,False); end;
  Disc(X-R*0.58,Y+R*0.18,R*0.12,GColor($F993A4),False);
  Disc(X+R*0.58,Y+R*0.18,R*0.12,GColor($F993A4),False);
  if Mood=2 then Disc(X,Y+R*0.38,R*0.18,Ink,False)
  else begin Line(X-R*0.17,Y+R*0.30,X,Y+R*0.42,Ink,3); Line(X,Y+R*0.42,X+R*0.17,Y+R*0.30,Ink,3); end;
end;
procedure TGDraw.Person(X,Y,Size: Double; Color: TColor; Pose: Integer);
var A,B,Bob,Arm: Double;
begin
  if (Ending>0.1) and (GEnding(Game)=gePose) then Pose:=1;
  Bob:=Sway*4*Size; Y:=Y+Bob; A:=30*Size; B:=45*Size;
  Line(X-A*0.55,Y+B,X-A*0.8-Sway*6*Size,Y+B+55*Size,Ink,14*Size);
  Line(X+A*0.55,Y+B,X+A*0.8+Sway*6*Size,Y+B+55*Size,Ink,14*Size);
  Oval(X,Y+18*Size,42*Size,55*Size,Ink); Oval(X,Y+16*Size,37*Size,50*Size,Color);
  Arm:=15*Size; if Pose=1 then Arm:=-50*Size; if Pose=2 then Arm:=35*Size;
  Line(X-A,Y,X-A-45*Size,Y+Arm,Ink,12*Size);
  Line(X+A,Y,X+A+45*Size,Y+Arm,Ink,12*Size);
  Disc(X-A-45*Size,Y+Arm,11*Size,GColor($FFE1BC)); Disc(X+A+45*Size,Y+Arm,11*Size,GColor($FFE1BC));
  Disc(X,Y-55*Size,44*Size,GColor($FFE1BC)); Face(X,Y-55*Size,37*Size,Ord((Hit>0.4) or (Ending>0.3)));
end;
procedure TGDraw.Star(X,Y,R,Angle: Double; Color: TColor);
var I: Integer; A,B: Double;
begin
  for I:=0 to 4 do begin
    A:=Angle+I*2*Pi/5; B:=A+Pi/5;
    Quad(X,Y,X+Cos(A)*R,Y+Sin(A)*R,X+Cos(B)*R*0.4,Y+Sin(B)*R*0.4,
      X+Cos(A+2*Pi/5)*R,Y+Sin(A+2*Pi/5)*R,Color);
  end;
end;
procedure TGDraw.Gear(X,Y,R,Angle: Double; Color: TColor);
var I: Integer; A: Double;
begin
  for I:=0 to 11 do begin A:=Angle+I*Pi/6;
    Line(X+Cos(A)*R*0.72,Y+Sin(A)*R*0.72,X+Cos(A)*R,Y+Sin(A)*R,Ink,R*0.24);
  end;
  Disc(X,Y,R*0.82,Color); Disc(X,Y,R*0.31,Paper); Disc(X,Y,R*0.1,Ink,False);
end;
procedure TGDraw.Spark(X,Y,Size: Double);
begin
  Quad(X,Y-Size,X+Size*0.24,Y-Size*0.24,X+Size,Y,X+Size*0.24,Y+Size*0.24,clWhite);
  Quad(X,Y+Size,X-Size*0.24,Y+Size*0.24,X-Size,Y,X-Size*0.24,Y-Size*0.24,clWhite);
end;
procedure TGDraw.Ball(X,Y,R: Double; Kind: Integer);
begin
  case Kind of
    1:begin Disc(X,Y,R,GColor($FFF8EA)); Star(X,Y,R*0.48,T,Ink); end;
    2:begin Disc(X,Y,R,GColor($6EC5F6)); Line(X-R*0.7,Y,X+R*0.7,Y,clWhite,4); end;
    3:begin Gear(X,Y,R,T*2,GColor($8BA1AF)); end;
    else begin Disc(X,Y,R,Accent); Disc(X-R*0.28,Y-R*0.30,R*0.20,clWhite,False); end;
  end;
end;
procedure TGDraw.Cloud(X,Y,Size: Double; Color: TColor);
begin Disc(X-Size*0.55,Y,Size*0.5,Color,False); Disc(X,Y-Size*0.18,Size*0.66,Color,False);
  Disc(X+Size*0.62,Y,Size*0.43,Color,False); end;
procedure TGDraw.Window(X,Y,W,H: Double);
begin
  Rect(X,Y,W,H,clWhite); Rect(X+9,Y+9,W-18,H-18,GColor($95DEFA),False);
  Disc(X+W*0.72,Y+H*0.30,Min(W,H)*0.15,GColor($FFE070),False);
  Cloud(X+W*0.32,Y+H*0.55,W*0.20,clWhite);
  Line(X+W/2,Y+5,X+W/2,Y+H-5,Ink,5); Line(X+5,Y+H/2,X+W-5,Y+H/2,Ink,5);
end;
procedure TGDraw.Floor(Y: Double; Color: TColor);
var I: Integer;
begin
  Rect(-500,Y,2000,1000,Color,False); Line(-500,Y,1500,Y,Ink,5);
  for I:=0 to 11 do Line(I*100,Y+35,I*100+55,Y+35,Secondary,3);
end;
procedure TGDraw.Burst(X,Y: Double);
var I: Integer; A,R: Double;
begin
  if not Resolved then Exit;
  for I:=0 to 8 do begin
    A:=I*2*Pi/9+Game*0.4; R:=45+After*120;
    Star(X+Cos(A)*R,Y+Sin(A)*R,Max(0.0,(1-After)*15),A+After*3,Accent);
  end;
end;
end.
