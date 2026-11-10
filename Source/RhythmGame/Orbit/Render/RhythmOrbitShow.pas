unit RhythmOrbitShow;
// Absolute-time entry/clear staging. Render-only: never shifts or manufactures audio taps.
interface
uses RhythmOrbitPlan,RhythmOrbitTypes,RhythmRenderSurface;
// 背景層と前景層を明示して合成。判定位置・カメラ・採用音は変更しない。
procedure DrawOrbitShow(Surface:TAnimationRenderSurface;Plan:TOrbitPlan;Time,W,H:Double;const FirstPlanet,Destination:TOrbitPoint;Foreground:Boolean);
// 遠方へ飛ぶ見た目の縮小だけを返す。保存された実接触位置はそのまま。
function OrbitShipSize(Plan:TOrbitPlan;Time:Double):Double;
implementation
uses System.Math,Winapi.Windows,Vcl.Graphics;
function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);Result:=U*U*(3-2*U);end;
function OrbitShipSize(Plan:TOrbitPlan;Time:Double):Double;
begin Result:=1;if (Plan=nil) or (Plan.Version<3) or (Plan.Count=0) then Exit;
  if Time>Plan.Stages[1] then Result:=1-0.68*Smooth((Time-Plan.Stages[1])/(Plan.Stages[2]-Plan.Stages[1]));
end;
procedure DrawOrbitShow(Surface:TAnimationRenderSurface;Plan:TOrbitPlan;Time,W,H:Double;const FirstPlanet,Destination:TOrbitPoint;Foreground:Boolean);
var I:Integer;U,V,Alpha,Angle,R,Length,Scale,S,X,Y:Double;Center:TOrbitPoint;
  // Small original vector glyphs avoid installed-font and DPI differences in headless/export.
  function Glyph(C:Char):Cardinal;
  begin case C of
    'S':Result:=$1f07043e;'Y':Result:=$23151084;'N':Result:=$239ace31;'C':Result:=$1f08420f;
    'L':Result:=$2108421f;'E':Result:=$3f0f421f;'A':Result:=$1d18fe31;'R':Result:=$3d1f5251;
    else Result:=0;end;end;
  procedure Caption(const Value:string;At,Opacity:Double);
  var C,Row,Col:Integer;G:Cardinal;Cell,Left:Double;
  begin Cell:=S*0.008;Left:=(W-(System.Length(Value)*6-1)*Cell)/2;
    for C:=1 to System.Length(Value) do begin G:=Glyph(Value[C]);
      for Row:=0 to 5 do for Col:=0 to 4 do if G and (Cardinal(1) shl (29-Row*5-Col))<>0 then
        Surface.FillRect(Left+(C-1)*6*Cell+Col*Cell,H*At+Row*Cell,Left+(C-1)*6*Cell+(Col+0.8)*Cell,H*At+(Row+0.8)*Cell,RGB(198,245,255),Opacity);
    end;
  end;
begin
  if (Plan=nil) or (Plan.Version<3) or (Plan.Count=0) then Exit;
  S:=Min(W,H);Scale:=S/3.7;
  if Time<Plan.Stages[0] then begin
    U:=EnsureRange(Time/Plan.Stages[0],0.0,1.0);V:=Smooth(U);Alpha:=Sqr(1-U);
    if Foreground then begin Caption('SYNC',0.78,Min(1.0,U*8)*(1-Smooth((U-0.58)/0.42)));Exit;end;
    Center:=FirstPlanet;
    // Layered star tunnel converges on the already planned first orbit, not a second route.
    for I:=0 to 79 do begin Angle:=I*2.399963;R:=0.05+Frac(I*0.618+U*1.9)*0.76;Length:=(0.018+0.13*V)*Alpha;
      X:=Cos(Angle);Y:=Sin(Angle);Surface.Line(Center.X+X*R*W,Center.Y+Y*R*H,Center.X+X*(R+Length)*W,Center.Y+Y*(R+Length)*H,RGB(111,205,255),1+I mod 2,Alpha*0.36);
    end;
    for I:=0 to 2 do begin R:=Scale*(1.9+I*0.45)*(1+1.7*(1-V));
      Surface.Circle(Center.X,Center.Y,R,RGB(75,181,242),False,1,Alpha*0.18);
    end;
    // Distant, dim planet silhouettes make the initial wide shot read as a whole sector.
    for I:=0 to 6 do begin Angle:=I*2.399963;R:=S*(0.21+0.04*I);X:=W/2+Cos(Angle)*R;Y:=H/2+Sin(Angle)*R;
      Surface.Circle(X,Y,S*(0.012+I*0.003),RGB(25,54+I*8,95+I*10),True,1,Alpha*0.75);
      Surface.Circle(X,Y,S*(0.018+I*0.004),RGB(62,126,172),False,1,Alpha*0.25);
    end;
  end else if Time>=Plan.Stages[1] then begin
    U:=EnsureRange((Time-Plan.Stages[1])/(Plan.Stages[2]-Plan.Stages[1]),0.0,1.0);V:=Smooth(U);
    Center:=Destination;Alpha:=Smooth(U*2);
    if Foreground then begin
      if U>=0.85 then begin Caption('CLEAR',0.17,Smooth((U-0.85)/0.15));
        Surface.Line(W*0.35,H*0.245,W*0.65,H*0.245,RGB(110,222,255),2,0.65*Smooth((U-0.85)/0.15));
      end;Exit;
    end;
    // The portal is the actual terminal point; the ship and final beats arrive on its center.
    for I:=5 downto 1 do Surface.Circle(Center.X,Center.Y,Scale*(0.10+I*0.16)*(0.7+0.3*V),RGB(80,185,255),True,1,Alpha*0.028*(6-I));
    for I:=0 to 2 do Surface.Circle(Center.X,Center.Y,Scale*(0.22+I*0.16),RGB(127,220,255),False,Max(1.0,Scale*0.012),Alpha*(0.7-I*0.16));
    for I:=0 to 23 do begin Angle:=I*Pi/12+Time*0.18;R:=Scale*(0.45+0.12*Sin(Time*2+I));
      Surface.Line(Center.X+Cos(Angle)*R,Center.Y+Sin(Angle)*R,Center.X+Cos(Angle)*R*1.24,Center.Y+Sin(Angle)*R*1.24,RGB(135,224,255),1,Alpha*0.55);
    end;
    Surface.Circle(Center.X,Center.Y,Max(2.0,Scale*0.11),RGB(226,251,255),True,1,Alpha*0.8);
  end;
end;
end.
