unit RhythmOrbitMarks;
// 命中時刻や配置を変えない記号描画。円=通常、矢印=連打、星=強アクセント。
interface
uses Vcl.Graphics,RhythmRenderSurface,RhythmOrbitTypes;
type TOrbitMarkKind=(omCircle,omArrow,omStar);
function OrbitMarkKind(const Tap:TOrbitTap):TOrbitMarkKind;
function OrbitMarkColor(const Tap:TOrbitTap):TColor;
procedure DrawOrbitMark(Surface:TAnimationRenderSurface;X,Y,Radius,Angle,Opacity,Approach:Double;
  Kind:TOrbitMarkKind;Color:TColor;Near:Boolean);
// GOODは自動成功の反応表示。操作成績と誤解しないようAUTOを添える。
procedure DrawOrbitGood(Surface:TAnimationRenderSurface;X,Y,Age:Double;W,H:Integer;Color:TColor;Roll:Boolean=False);
implementation
uses System.Math,Winapi.Windows;
function OrbitMarkKind(const Tap:TOrbitTap):TOrbitMarkKind;
begin if Tap.Strength>=0.78 then Result:=omStar else if Tap.Chain>1 then Result:=omArrow else Result:=omCircle;end;
function OrbitMarkColor(const Tap:TOrbitTap):TColor;
begin case (Tap.Source*3+Tap.Chain div 4) mod 8 of
  0:Result:=RGB(57,211,255);1:Result:=RGB(255,93,161);2:Result:=RGB(255,203,67);3:Result:=RGB(110,248,151);
  4:Result:=RGB(165,124,255);5:Result:=RGB(255,139,65);6:Result:=RGB(55,239,217);else Result:=RGB(238,113,255);end;
end;
function Dark(C:TColor;Light:Double):TColor;
var V:Cardinal;
begin V:=ColorToRGB(C);Result:=RGB(Round(GetRValue(V)*Light),Round(GetGValue(V)*Light),Round(GetBValue(V)*Light));end;
procedure DrawOrbitMark(Surface:TAnimationRenderSurface;X,Y,Radius,Angle,Opacity,Approach:Double;
  Kind:TOrbitMarkKind;Color:TColor;Near:Boolean);
var I:Integer;A,B,R,Stroke:Double;
  procedure Segment(X1,Y1,X2,Y2:Double);
  var C,S:Double;
  begin C:=Cos(Angle);S:=Sin(Angle);Surface.Line(X+(X1*C-Y1*S)*R,Y+(X1*S+Y1*C)*R,
    X+(X2*C-Y2*S)*R,Y+(X2*S+Y2*C)*R,clWhite,Stroke,1);end;
begin
  if Opacity<=0 then Exit;R:=Radius;if Near then R:=EnsureRange(R,7.0,20.0) else R:=EnsureRange(R,2.0,4.0);
  // コアはalpha=1。遠い予告は暗さと大きさで奥行きを示し、背景を透かす穴にしない。
  Surface.Circle(X,Y,R,Dark(Color,0.30+0.20*Opacity),True,1,1);
  Surface.Circle(X,Y,R,Dark(Color,0.55+0.45*Opacity),False,Max(1.0,R*0.16),1);
  if not Near then Exit;
  Surface.Circle(X,Y,R*(1+1.8*(1-Approach)),Color,False,1,Opacity*0.40);
  R:=R*0.53;Stroke:=Max(1.5,R*0.32);
  case Kind of
    omCircle:Surface.Circle(X,Y,R*0.45,clWhite,True,1,1);
    omArrow:begin Segment(-0.65,-0.75,0.65,0);Segment(0.65,0,-0.65,0.75);end;
    omStar:for I:=0 to 4 do begin A:=-Pi/2+I*4*Pi/5;B:=A+4*Pi/5;
      Surface.Line(X+Cos(A)*R,Y+Sin(A)*R,X+Cos(B)*R,Y+Sin(B)*R,clWhite,Stroke,1);end;
  end;
end;
procedure DrawOrbitGood(Surface:TAnimationRenderSurface;X,Y,Age:Double;W,H:Integer;Color:TColor;Roll:Boolean);
var Cell,Alpha,Top,Left:Double;
  function Glyph(C:Char):Cardinal;
  begin case C of
    'G':Result:=$1f085e2e;'O':Result:=$1d18c62e;'D':Result:=$3d18c63e;
    'A':Result:=$1d18fe31;'U':Result:=$2318c62e;'T':Result:=$3e421084;
    'R':Result:=$3d1f4a51;'L':Result:=$2108421f;else Result:=0;end;end;
  procedure Text(const S:string;X,Y,Size:Double);
  var I,J,K:Integer;Bits:Cardinal;
  begin
    for I:=1 to Length(S) do begin Bits:=Glyph(S[I]);
      for J:=0 to 5 do for K:=0 to 4 do if Bits and (Cardinal(1) shl (29-J*5-K))<>0 then
        Surface.FillRect(X+((I-1)*6+K)*Size,Y+J*Size,X+((I-1)*6+K+0.8)*Size,Y+(J+0.8)*Size,Color,Alpha);
    end;
  end;
begin
  if (Age<0) or (Age>=0.38) then Exit;Cell:=EnsureRange(Min(W,H)*0.0045,1.0,3.2);Alpha:=1-Sqr(Age/0.38);
  Left:=EnsureRange(X-11.5*Cell,4.0,Max(4.0,W-24*Cell-4));Top:=EnsureRange(Y-31-6*Cell-Age*15,4.0,Max(4.0,H-10*Cell-4));
  // 小さな読み取り用プレートだけを置き、密な火花や中層映像から評価文字を分離する。
  Surface.FillRect(Left-2,Top-2,Left+24*Cell,Top+11*Cell,RGB(4,10,24),Alpha*0.82);
  if Roll then Text('ROLL',Left,Top,Cell) else Text('GOOD',Left,Top,Cell);
  Text('AUTO',Left+5.75*Cell,Top+7*Cell,Cell*0.5);
end;
end.
