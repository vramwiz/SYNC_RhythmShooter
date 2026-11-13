unit RhythmMelodyDevices;
// レールの木製三角金具と、鉄琴専用の箱型台座・バネ・縦ガイドを描き分ける。
interface
uses RhythmMelodyDraw,RhythmMelodyPlan;
procedure DrawMelodyDevice(const P:TMelodyPainter; const S:TMelodySpan; Index:Integer);
procedure DrawMelodyBarMount(const P:TMelodyPainter; const B:TMelodyBar; Top:Double);
procedure DrawMelodyHammer(const P:TMelodyPainter; const B:TMelodyBar);
implementation
uses System.Math;
procedure DrawMelodyDevice(const P:TMelodyPainter; const S:TMelodySpan; Index:Integer);
var A,L,R:TMelodyPoint; I,J:Integer; X,Lo,Hi,U:Double;
begin
  if (S.Motion<>mmRolling) or not MelodyHasRail(S.Kind) then Exit;
  L:=MelodyRail(S,0); R:=MelodyRail(S,1);
  // 連続音で支持解が細分化されても、棚受けを毎打撃に重ねない。壁上の1.6m格子へ固定する。
  for I:=Ceil(Min(L.X,R.X)/1.6) to Floor(Max(L.X,R.X)/1.6) do begin
    X:=I*1.6; if Abs(X-L.X)<1E-8 then Continue;
    Lo:=0; Hi:=1;
    for J:=0 to 23 do begin
      U:=(Lo+Hi)/2; A:=MelodyRail(S,U);
      if (A.X<X)=(R.X>L.X) then Lo:=U else Hi:=U;
    end;
    A:=MelodyRail(S,(Lo+Hi)/2); P.Foot(A.X,A.Y-0.12);
  end;
end;
procedure DrawMelodyBarMount(const P:TMelodyPainter; const B:TMelodyBar; Top:Double);
var I,J:Integer; X,Margin,Base,Y0,Y1:Double; A,C:TMelodyPoint;
begin
  if B.Strike=msHammer then begin
    // 上の鉄琴はバネ台と別の吊り金具。ハンマーが下から叩けるよう下面を開ける。
    P.Line(B.Left+0.08,Top+0.06,B.Left+0.08,Top+0.45,0.05,$00647279);
    P.Line(B.Right-0.08,Top+0.06,B.Right-0.08,Top+0.45,0.05,$00647279);
    P.Line(B.Left-0.08,Top+0.45,B.Right+0.08,Top+0.45,0.13,$0076878D);
    P.Dot(B.Left+0.08,Top+0.45,0.035,$00DCE2E5); P.Dot(B.Right-0.08,Top+0.45,0.035,$00DCE2E5);
    Exit;
  end;
  Base:=B.Top-0.62; Margin:=Min(0.25,(B.Right-B.Left)*0.23);
  P.Quad(MelodyPoint(B.Left-0.06,Base-0.04),MelodyPoint(B.Right+0.06,Base-0.04),
    MelodyPoint(B.Right+0.06,Base+0.12),MelodyPoint(B.Left-0.06,Base+0.12),$0076878D);
  P.Line(B.Left-0.04,Base+0.10,B.Right+0.04,Base+0.10,0.035,$00C2C9CC);
  for I:=0 to 1 do begin
    if I=0 then X:=B.Left+Margin else X:=B.Right-Margin;
    P.Dot(X,Base+0.025,0.035,$00E0E4E4);
    Y0:=Base+0.14; Y1:=Top-0.13;
    P.Line(X,Y0,X,Y1,0.045,$00C9D5D7);
    if B.Terminal or (B.Strike=msStep) then P.Line(X-0.07,Y0,X+0.07,Y1,0.12,$00889E82)
    else begin
      A:=MelodyPoint(X,Y0);
      for J:=1 to 12 do begin
        C:=MelodyPoint(X+0.085*Sin(J*Pi/2),Y0+(Y1-Y0)*J/12);
        P.Line(A.X,A.Y,C.X,C.Y,0.032,$004B626C); A:=C;
      end;
      P.Line(X-0.10,Y1,X+0.10,Y1,0.055,$00A4B9C3);
    end;
  end;
end;
procedure DrawMelodyHammer(const P:TMelodyPainter; const B:TMelodyBar);
var S:TMelodySpan; H,C,W,Elbow:TMelodyPoint; Angle,Head,Theta,D,V,Scale,Counter:Double;
begin
  if B.Strike<>msHammer then Exit;
  S:=P.Plan.Spans[B.TriggerSpan]; MelodyTravel(S,S.Finish-S.Start,D,V); Theta:=S.Theta+S.Curvature*D;
  Scale:=B.MechanismScale; Counter:=MelodyCounterArm(B);
  Angle:=EnsureRange((P.Time-B.Trigger)*B.AngularSpeed,0.0,MelodyStroke(B)); Head:=MelodyHeadAngle(B,P.Time);
  H:=MelodyHammer(B,S.Direction,P.Time);
  C:=MelodyPoint(B.Pivot.X+S.Direction*Scale*MelodyPaddleArm*Sin(Theta+Angle),B.Pivot.Y-Scale*MelodyPaddleArm*Cos(Theta+Angle));
  // 接触面の前側に厚みを置き、球と端部の丸みが初接触時に重ならないようにする。
  C.X:=C.X+S.Direction*Scale*0.04*Cos(Theta+Angle); C.Y:=C.Y+Scale*0.04*Sin(Theta+Angle);
  Elbow:=MelodyPoint(B.Pivot.X+S.Direction*MelodyPaddleArm*Scale*(0.55*Cos(Theta+Angle)+0.5*Sin(Theta+Angle)),
    B.Pivot.Y+MelodyPaddleArm*Scale*(0.55*Sin(Theta+Angle)-0.5*Cos(Theta+Angle)));
  W:=MelodyPoint(B.Pivot.X-S.Direction*Scale*MelodyHammerArm*Counter*Cos(Head),B.Pivot.Y-Scale*MelodyHammerArm*Counter*Sin(Head));
  // 三本腕の釣り合いローター。球が下のパドルを押し、反対側の錘と上のハンマーが回る。
  P.Line(B.Pivot.X,B.Pivot.Y-0.16*Scale,B.Pivot.X,B.Pivot.Y+0.20*Scale,0.30*Scale,$00728188);
  P.Dot(B.Pivot.X,B.Pivot.Y+0.15*Scale,0.035*Scale,$00DDE3E5);
  // 球を跳ね返さず抜くため、パドル腕を前方へ曲げて球の通路を開ける。
  P.Line(C.X,C.Y,Elbow.X,Elbow.Y,0.075*Scale,$00637379);
  P.Line(Elbow.X,Elbow.Y,B.Pivot.X,B.Pivot.Y,0.075*Scale,$00637379);
  P.Line(W.X,W.Y,H.X,H.Y,0.075*Scale,$0073848B);
  P.Dot(C.X,C.Y,0.04*Scale,$009CB3BC);
  P.Dot(H.X,H.Y,MelodyHammerRadius*Scale,$004E6878);
  P.Dot(H.X-0.025*Scale,H.Y+0.025*Scale,MelodyHammerRadius*0.64*Scale,$00B3C7D2);
  P.Dot(W.X,W.Y,0.15*Scale,$006C7B83);
  // パドル腕の重心も釣り合わせる錘。無接触中に重力の回転加速を生じない。
  P.Line(B.Pivot.X,B.Pivot.Y,B.Pivot.X-(C.X-B.Pivot.X)*0.40,B.Pivot.Y-(C.Y-B.Pivot.Y)*0.40,0.06*Scale,$00637379);
  P.Dot(B.Pivot.X-(C.X-B.Pivot.X)*0.40,B.Pivot.Y-(C.Y-B.Pivot.Y)*0.40,0.095*Scale,$006C7B83);
  P.Dot(B.Pivot.X,B.Pivot.Y,0.11*Scale,$004E626D); P.Dot(B.Pivot.X,B.Pivot.Y,0.04*Scale,$00D9E3E5);
  // 打撃角で止まる爪付きストッパー。打撃後の反対回転で球を塞がない。
  P.Line(B.Pivot.X+S.Direction*0.13*Scale,B.Pivot.Y+0.03*Scale,B.Pivot.X+S.Direction*0.24*Scale,B.Pivot.Y+0.11*Scale,0.05*Scale,$004C6068);
end;
end.
