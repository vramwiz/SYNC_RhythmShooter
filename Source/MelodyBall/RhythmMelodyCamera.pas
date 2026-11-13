unit RhythmMelodyCamera;
// コースの大きな流れだけを追う。反発速度・バネ圧縮・瞬間的な球位置で構図を補正しない。
interface
uses RhythmMelodyPlan;
type TMelodyView=record
    Center:TMelodyPoint;
    Scale,Left,Right,Top,Bottom:Double;
  end;
function MelodyView(Plan:TMelodyPlan; Time:Double; Width,Height:Integer):TMelodyView;
implementation
uses System.Math;
function MelodyView(Plan:TMelodyPlan; Time:Double; Width,Height:Integer):TMelodyView;
var C,Ahead:TMelodyPoint; Lead,Zoom:Double;
begin
  C:=Plan.CameraPoint(Time); Ahead:=Plan.CameraPoint(Time+0.35);
  Zoom:=Plan.CameraZoom(Time); Lead:=0.75*(Ahead.X-C.X);
  C.X:=C.X+Lead/Sqrt(1+Sqr(Lead*Zoom/1.8)); C.Y:=C.Y-0.35;
  // 速い区間は従来の画角。遅さの持続と待ち時間を満たした経路だけ、最大1.35倍へ寄る。
  Result.Scale:=Min(Height/10.5,Width/10.5)*Zoom; Result.Center:=C;
  Result.Left:=C.X-Width/Result.Scale*0.5; Result.Right:=C.X+Width/Result.Scale*0.5;
  Result.Top:=C.Y+Height/Result.Scale*0.5; Result.Bottom:=C.Y-Height/Result.Scale*0.5;
end;
end.
