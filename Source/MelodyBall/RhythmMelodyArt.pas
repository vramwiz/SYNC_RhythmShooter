unit RhythmMelodyArt;
// 木の壁に取り付けた重力コース。実際の支持面と接触位置を描き、球へ描画側の移動を加えない。
interface
uses RhythmRenderSurface,RhythmMelodyPlan,RhythmAnimation;
procedure DrawMelodyBall(Surface:TAnimationRenderSurface; Plan:TMelodyPlan; const Frame:TAnimationFrame);
implementation
uses System.Math,System.Types,Winapi.Windows,Vcl.Graphics,RhythmMelodyDraw,RhythmMelodyCamera,RhythmMelodyDevices;

procedure Background(const P:TMelodyPainter);
var Row,Column,J:Integer; A,B:TPointF; X,Y,Shade:Double;
begin
  // 同じ木壁が世界座標へ固定される。カメラ移動に合わせて空や風景を差し込まない。
  P.Surface.FillRect(0,0,P.Frame.Width,P.Frame.Height,$008DB8D5);
  for Row:=Floor(P.View.Bottom/0.85)-1 to Ceil(P.View.Top/0.85)+1 do begin
    Y:=Row*0.85; A:=P.Screen(MelodyPoint(P.View.Left,Y)); B:=P.Screen(MelodyPoint(P.View.Right,Y+0.84));
    Shade:=Abs(Row*7) mod 5;
    P.Surface.FillRect(A.X,B.Y,B.X,A.Y,RGB(Round(211+Shade*2),Round(175+Shade*2),Round(123+Shade*3)));
    P.Line(P.View.Left,Y,P.View.Right,Y,0.022,$007D9DB6);
    for Column:=Floor(P.View.Left/3.4)-1 to Ceil(P.View.Right/3.4)+1 do begin
      X:=Column*3.4+Ord(Odd(Row))*1.7;
      P.Line(X,Y,X,Y+0.85,0.018,$008AA5BB);
      for J:=1 to 3 do P.Line(X+0.20,Y+J*0.19,X+2.9,Y+J*0.19+0.025*Sin(Column+Row+J),0.009,$009FBED5);
      P.Dot(X+0.10,Y+0.11,0.025,$008299AB); P.Dot(X+0.10,Y+0.74,0.025,$008299AB);
    end;
  end;
  // 室内の額縁状の柱。支柱は床を追いかけず、この壁へ固定する。
  for Column:=Floor(P.View.Left/12)-1 to Ceil(P.View.Right/12)+1 do begin
    X:=Column*12-2.2;
    P.Line(X+0.04,P.View.Bottom,X+0.04,P.View.Top,0.20,$006885A2);
    P.Line(X-0.055,P.View.Bottom,X-0.055,P.View.Top,0.05,$00B3CADB);
  end;
end;

procedure Rail(const P:TMelodyPainter; const S:TMelodySpan);
var J,N:Integer; A,B:TMelodyPoint;
begin
  if (S.Motion<>mmRolling) or not MelodyHasRail(S.Kind) then Exit;
  N:=Max(1,Ceil(Abs(S.Curvature)*S.Knots[High(S.Knots)].Distance*20)); if S.Kind=mcLoop then N:=120;
  A:=MelodyRail(S,0);
  for J:=1 to N do begin
    B:=MelodyRail(S,J/N);
    P.Line(A.X+0.04,A.Y-0.11,B.X+0.04,B.Y-0.11,0.20,$004F7190);
    P.Line(A.X,A.Y-0.045,B.X,B.Y-0.045,0.17,$007DADD0);
    P.Line(A.X,A.Y,B.X,B.Y,0.035,$00D5E5EF); A:=B;
  end;
end;

procedure Iron(const P:TMelodyPainter; const B:TMelodyBar; Index:Integer);
var Color:TColor; Top:Double;
begin
  if not P.Visible(B.Left,B.Top-1,B.Right,B.Top+0.5) then Exit;
  Color:=MelodyColor(Index); Top:=B.Top-P.Plan.BarCompression(Index,P.Time);
  DrawMelodyHammer(P,B);
  // 鉄琴は独立した水平の棒状板。両端の上面は同じTopで、レールの傾斜に追従しない。
  DrawMelodyBarMount(P,B,Top);
  P.Quad(MelodyPoint(B.Left,Top-0.11),MelodyPoint(B.Right,Top-0.11),
    MelodyPoint(B.Right,Top),MelodyPoint(B.Left,Top),$0094AEBB);
  P.Line(B.Left,Top-0.018,B.Right,Top-0.018,0.035,$00E8EFF0);
  P.Line(B.Left+0.02,Top-0.080,B.Right-0.02,Top-0.080,0.030,Color);
  P.Dot(B.Left+0.08,Top-0.052,0.020,$006F8087);
  P.Dot(B.Right-0.08,Top-0.052,0.020,$006F8087);
end;

procedure Impact(const P:TMelodyPainter; const B:TMelodyBar; Index:Integer);
var Age,U,R,Angle,Life:Double; I:Integer; Pos:TMelodyPoint; Color:TColor;
begin
  Life:=0.25; if (B.Strike=msHammer) and (B.MechanismScale<1) then Life:=0.09;
  Age:=P.Time-B.Time; if (Age<0) or (Age>Life) then Exit;
  U:=Age/Life; R:=0.13+U*(0.4+B.Power*0.35); Pos:=MelodyPoint(B.Contact.X,B.Top);
  if B.Strike=msHammer then begin
    Pos:=MelodyHammer(B,P.Plan.Spans[B.TriggerSpan].Direction,B.Time); Pos.Y:=Pos.Y+MelodyHammerRadius*B.MechanismScale;
    R:=R*B.MechanismScale;
  end;
  Color:=MelodyColor(Index); P.Dot(Pos.X,Pos.Y,R,Color,False,0.8*(1-U));
  for I:=0 to 4 do begin
    Angle:=I*2*Pi/5+Index*0.37;
    P.Line(Pos.X+R*0.7*Cos(Angle),Pos.Y+R*0.7*Sin(Angle),Pos.X+R*Cos(Angle),Pos.Y+R*Sin(Angle),0.018,Color,1-U);
  end;
end;

procedure Ball(const P:TMelodyPainter);
var Pos:TMelodyPoint; I:Integer; R,Angle,A:Double;
begin
  Pos:=P.Plan.Position(P.Time); R:=MelodyRadius; P.Dot(Pos.X+0.02,Pos.Y-0.02,R+0.025,$004C6579);
  for I:=0 to 8 do P.Dot(Pos.X-I*0.008,Pos.Y+I*0.008,R*(1-I*0.064),RGB(242+I,92+I*10,57+I*8));
  Angle:=-P.Plan.Rotation(P.Time);
  for I:=-8 to 8 do begin A:=I/8*R*0.9; P.Dot(Pos.X+A*Cos(Angle),Pos.Y+A*Sin(Angle),R*0.12,$00F2FCF5); end;
  P.Dot(Pos.X-R*0.30,Pos.Y+R*0.35,R*0.20,$00FFFFFF);
end;

procedure Dock(const P:TMelodyPainter);
var Pos:TMelodyPoint; Top,X:Double; TerminalBar:Boolean; Direction:Integer;
begin
  Pos:=P.Plan.Spans[High(P.Plan.Spans)].B; Top:=Pos.Y-MelodyRadius;
  Direction:=P.Plan.Spans[High(P.Plan.Spans)].Direction;
  if not P.Visible(Pos.X-1.2,Pos.Y-1,Pos.X+1,Pos.Y+1) then Exit;
  TerminalBar:=(Length(P.Plan.Bars)>0) and P.Plan.Bars[High(P.Plan.Bars)].Terminal;
  if not TerminalBar then begin
    P.Quad(MelodyPoint(Pos.X-1.1,Top-0.16),MelodyPoint(Pos.X+0.4,Top-0.16),
      MelodyPoint(Pos.X+0.4,Top),MelodyPoint(Pos.X-1.1,Top),$007EABC8);
    P.Foot(Pos.X-0.8,Top-0.2); P.Foot(Pos.X+0.15,Top-0.2);
  end;
  // フェルト付きの終端壁で水平運動も吸収する。接触面は球中心から半径だけ前方。
  X:=Pos.X+Direction*(MelodyRadius+0.06);
  P.Line(X,Top-0.04,X,Top+0.65,0.12,$006D8EAA);
  P.Line(X-Direction*0.04,Top+0.02,X-Direction*0.04,Top+0.58,0.04,$007C9B7A);
end;

procedure DrawMelodyBall(Surface:TAnimationRenderSurface; Plan:TMelodyPlan; const Frame:TAnimationFrame);
var P:TMelodyPainter; I,First,Last:Integer; S:TMelodySpan;
begin
  P.Surface:=Surface; P.Plan:=Plan; P.Frame:=Frame; P.Time:=EnsureRange(Frame.Time,0.0,Plan.EndTime);
  P.View:=MelodyView(Plan,P.Time,Frame.Width,Frame.Height); Background(P);
  First:=Plan.SpanAt(P.Time-7); Last:=Plan.SpanAt(P.Time+9);
  for I:=First to Last do begin
    S:=Plan.Spans[I]; if not P.Visible(S.MinX-1,S.MinY-1,S.MaxX+1,S.MaxY+1) then Continue;
    DrawMelodyDevice(P,S,I); Rail(P,S);
  end;
  First:=Max(0,Plan.BarAt(P.Time-7)); Last:=Min(High(Plan.Bars),Plan.BarAt(P.Time+9)+1);
  for I:=First to Last do Iron(P,Plan.Bars[I],I); Dock(P);
  if Frame.BackgroundOnly then Exit;
  First:=Max(0,Plan.BarAt(P.Time-0.3)); Last:=Plan.BarAt(P.Time);
  for I:=First to Last do Impact(P,Plan.Bars[I],I); Ball(P);
end;
end.
