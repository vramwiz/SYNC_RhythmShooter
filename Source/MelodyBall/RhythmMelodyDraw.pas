unit RhythmMelodyDraw;
// メロディボール専用の世界→画面変換と立体プリミティブ。Surface/Planは借用する。
interface
uses System.Types,Vcl.Graphics,RhythmAnimation,RhythmRenderSurface,RhythmMelodyPlan,RhythmMelodyCamera;
type
  TMelodyPainter = record
    Surface: TAnimationRenderSurface;
    Frame: TAnimationFrame;
    View: TMelodyView;
    Plan: TMelodyPlan;
    Time: Double;
    function Screen(const P: TMelodyPoint): TPointF;
    function Visible(X1,Y1,X2,Y2: Double): Boolean;
    procedure Line(X1,Y1,X2,Y2,Width: Double; Color: TColor; Opacity: Double = 1);
    procedure Dot(X,Y,R: Double; Color: TColor; Filled: Boolean = True; Opacity: Double = 1);
    procedure Quad(const A,B,C,D: TMelodyPoint; Color: TColor);
    procedure Beam(const A,B: TMelodyPoint; Width: Double; Color: TColor);
    procedure Foot(X,Y: Double);
  end;
function MelodyColor(Index: Integer): TColor;
implementation
uses System.Math,Winapi.Windows;
function MelodyColor(Index: Integer): TColor;
const Colors: array[0..7] of TColor=($0087B6F5,$008CCB69,$00E4B149,$00CC83DE,
  $007BCDEF,$00A3A0F4,$00C7CC45,$0096D8FC);
begin Result:=Colors[Abs(Index) mod 8]; end;
function TMelodyPainter.Screen(const P: TMelodyPoint): TPointF;
begin Result:=PointF((P.X-View.Left)*View.Scale,(View.Top-P.Y)*View.Scale); end;
function TMelodyPainter.Visible(X1,Y1,X2,Y2: Double): Boolean;
begin Result:=(X2>=View.Left-1) and (X1<=View.Right+1) and (Y2>=View.Bottom-1) and (Y1<=View.Top+1); end;
procedure TMelodyPainter.Line(X1,Y1,X2,Y2,Width: Double; Color: TColor; Opacity: Double);
var A,B: TPointF;
begin
  if not Visible(Min(X1,X2),Min(Y1,Y2),Max(X1,X2),Max(Y1,Y2)) then Exit;
  A:=Screen(MelodyPoint(X1,Y1)); B:=Screen(MelodyPoint(X2,Y2));
  Surface.Line(A.X,A.Y,B.X,B.Y,Color,Max(1.0,Width*View.Scale),Opacity);
end;
procedure TMelodyPainter.Dot(X,Y,R: Double; Color: TColor; Filled: Boolean; Opacity: Double);
var P: TPointF;
begin
  if not Visible(X-R,Y-R,X+R,Y+R) then Exit;
  P:=Screen(MelodyPoint(X,Y)); Surface.Circle(P.X,P.Y,R*View.Scale,Color,Filled,Max(1.0,0.025*View.Scale),Opacity);
end;
procedure TMelodyPainter.Quad(const A,B,C,D: TMelodyPoint; Color: TColor);
begin Surface.FillQuad(Screen(A),Screen(B),Screen(C),Screen(D),Color); end;
procedure TMelodyPainter.Beam(const A,B: TMelodyPoint; Width: Double; Color: TColor);
begin
  Line(A.X+0.055,A.Y-0.075,B.X+0.055,B.Y-0.075,Width+0.055,RGB(57,87,108));
  Line(A.X,A.Y,B.X,B.Y,Width,Color);
  Line(A.X-0.02,A.Y+0.025,B.X-0.02,B.Y+0.025,Max(0.02,Width*0.22),RGB(235,249,249));
end;
procedure TMelodyPainter.Foot(X,Y: Double);
begin
  // レール専用の木製三角棚受け。鉄琴の箱型台座にはこの形を使わない。
  Quad(MelodyPoint(X-0.07,Y-0.62),MelodyPoint(X+0.13,Y-0.62),
    MelodyPoint(X+0.13,Y-0.06),MelodyPoint(X-0.07,Y-0.06),$006B92B2);
  Line(X-0.32,Y-0.06,X+0.22,Y-0.06,0.14,$0089AFCE);
  Line(X-0.28,Y-0.10,X+0.03,Y-0.56,0.12,$00769BBB);
  Line(X-0.29,Y-0.09,X+0.01,Y-0.53,0.025,$00A7C5DD);
  Dot(X+0.025,Y-0.15,0.025,$0055656B); Dot(X+0.025,Y-0.52,0.025,$0055656B);
end;
end.
