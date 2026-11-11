unit RhythmTrapArt;
// 保存軌道と同じ幾何を描く。アニメーションの積算状態を持たない。
interface
uses RhythmTrapPlan,RhythmRenderSurface,RhythmAnimation;
procedure DrawTrapAction(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
implementation
uses System.Math,System.Types,Vcl.Graphics,RhythmStyles;
type
  TPainter=record
    S:TAnimationRenderSurface;P:TTrapPlan;F:TAnimationFrame;
    T,K,L,Top,VW:Double;BG,Stone,Edge,Glow:TColor;
    procedure Bar(A,B,C,D:Double;Color:TColor;Alpha:Double=1);
    procedure Line(A,B,C,D,Width:Double;Color:TColor);
    procedure Dot(X,Y,R:Double;Color:TColor);
    procedure Quad(A,B,C,D:TTrapPoint;Color:TColor);
    procedure Backdrop;
    procedure Terrain;
    procedure Traps;
    procedure Hero;
    procedure Finish;
    procedure Paint;
  end;
const Palettes:array[TTrapStage,0..3] of TColor=(
  ($00251A14,$004E4239,$009C9A67,$00D7DF7B),
  ($00271F22,$00594E64,$008DA9C0,$008FECEB),
  ($00291E14,$004A4241,$00899AA1,$005ED4FF),
  ($002B1729,$005C3C56,$00A37F99,$0092A5FF),
  ($00251F14,$00433F31,$00859C65,$00E2FF74),
  ($001B152E,$00333057,$00566C9F,$003C89FF),
  ($004A2F19,$008D7357,$00EBD8A6,$00FFEDB2),
  ($00252015,$00454D32,$0081AA73,$00A4E2BC));
procedure TPainter.Bar(A,B,C,D:Double;Color:TColor;Alpha:Double);
begin if (C<=A) or (D<=B) then Exit;S.FillRect((A-L)*K,(Top-D)*K,(C-L)*K,(Top-B)*K,Color,Alpha);end;
procedure TPainter.Line(A,B,C,D,Width:Double;Color:TColor);
begin S.Line((A-L)*K,(Top-B)*K,(C-L)*K,(Top-D)*K,Color,Max(1.0,Width*K));end;
procedure TPainter.Dot(X,Y,R:Double;Color:TColor);
begin S.Circle((X-L)*K,(Top-Y)*K,R*K,Color,True);end;
procedure TPainter.Quad(A,B,C,D:TTrapPoint;Color:TColor);
begin S.FillQuad(PointF((A.X-L)*K,(Top-A.Y)*K),PointF((B.X-L)*K,(Top-B.Y)*K),
  PointF((C.X-L)*K,(Top-C.Y)*K),PointF((D.X-L)*K,(Top-D.Y)*K),Color);end;
procedure TPainter.Backdrop;
var I,J:Integer;X,Y,B:Double;
begin
  S.FillRect(0,0,F.Width,F.Height,BG);
  B:=Top-F.Height/K;
  for I:=System.Math.Floor((L*0.25)/2.8)-2 to Ceil((L*0.25+VW)/2.8)+2 do begin
    X:=I*2.8+L*0.75;Y:=2.4+Sin(I*2.4)*0.6;
    case P.Theme of
      tsCave,tsVolcano,tsIceCave:begin
        Quad(TrapPoint(X,Top),TrapPoint(X+1.9,Top),TrapPoint(X+1.1,Y),TrapPoint(X+0.8,Y+0.5),Stone);
        Line(X+0.8,Y+0.5,X+1.1,Y,0.04,Edge);
        if P.Theme=tsVolcano then begin Line(X,B,X+0.4,B+1.1,0.09,Glow);Line(X+0.4,B+1.1,X+0.1,B+1.7,0.06,Glow);end;
        if P.Theme=tsIceCave then begin Line(X+0.3,Y+1.5,X+0.6,Y+0.8,0.07,Glow);Line(X+0.5,Y+1.9,X+0.9,Y+0.7,0.04,Edge);end;
      end;
      tsRuins,tsCastle:begin
        Bar(X,B,X+0.38,Y+2.1,Stone);Bar(X-0.12,Y+1.8,X+0.52,Y+2.1,Edge);
        Line(X+0.4,Y+1.9,X+2.7,Y+1.9,0.16,Stone);
        if P.Theme=tsCastle then begin Bar(X+0.9,Y-0.3,X+1.5,Y+1.1,Stone);Dot(X+1.2,Y+1.1,0.3,Stone);Bar(X+1.1,Y-0.15,X+1.3,Y+0.9,Glow);end;
      end;
      tsFactory,tsFacility:begin
        Bar(X,B,X+0.16,Top,Stone);Line(X+0.2,Y+1.4,X+2.6,Y+1.4,0.13,Edge);
        Bar(X+0.4,Y-0.2,X+2.3,Y+1,Stone);
        for J:=0 to 3 do Bar(X+0.65+J*0.38,Y+0.2,X+0.77+J*0.38,Y+0.7,Glow);
        if P.Theme=tsFactory then begin Dot(X+2.2,Y+1.5,0.38,Edge);Dot(X+2.2,Y+1.5,0.21,BG);end;
      end;
      tsForestRuins:begin
        Bar(X,B,X+0.3,Top,Stone);Line(X,Y+1.4,X+1,Y+2.6,0.14,Stone);
        Dot(X+1,Y+2.6,0.6,Stone);Dot(X-0.2,Y+3.3,0.9,Stone);
        Line(X+2,Y+2.4,X+1.7,Y-0.2,0.05,Edge);Bar(X+0.7,B,X+1.4,Y-0.5,Stone);
      end;
    end;
  end;
  for I:=0 to 30 do begin
    X:=L+Frac(I*0.618033+T*0.007)*VW;Y:=Top-Frac(I*0.381966+T*0.013)*F.Height/K;
    Dot(X,Y,0.013+Ord(P.Theme=tsVolcano)*0.012,Edge);
  end;
  Bar(L,B,L+VW,B+0.10,Glow);
end;
procedure TPainter.Terrain;
var I,J:Integer;Floor:TTrapPlatform;A,B,Y,Z,Age,X:Double;V:TTrapPoint;M:TTrapMove;
begin
  for I:=0 to High(P.Platforms) do begin
    Floor:=P.Platforms[I];A:=Floor.Left;B:=Floor.Right;Y:=Floor.Y;Z:=Floor.EndY;
    if Floor.Move>=0 then begin M:=P.Moves[Floor.Move];V:=M.Position(T);A:=A+V.X;B:=B+V.X;Y:=Y+V.Y;Z:=Z+V.Y;end;
    if (B<L-2) or (A>L+VW+2) then Continue;
    Age:=Max(0.0,T-Floor.Finish);
    if (Floor.Move<0) and (T>=Floor.Finish) and (Floor.Finish<P.Duration) then begin
      if Floor.Kind in [tkVanish,tkFalseFloor,tkPit,tkSink] then Continue;
      if Floor.Kind in [tkCrumble,tkBridge,tkCollapse] then begin
        for J:=0 to 7 do begin X:=A+(B-A)*J/8;
          Bar(X,Y-Age*Age*(6+J*0.25)-0.25,X+(B-A)*0.10,Y-Age*Age*(6+J*0.25),Stone);
        end;
        Continue;
      end;
      if Floor.Kind=tkFlip then begin Y:=Y-Age*Age*7;Z:=Z-Age*Age*7-Sin(Min(1.0,Age)*Pi)*0.8;end;
    end;
    Quad(TrapPoint(A,Y),TrapPoint(B,Z),TrapPoint(B,Z-0.55),TrapPoint(A,Y-0.55),Stone);
    Line(A,Y,B,Z,0.09,Edge);Line(A,Y-0.15,B,Z-0.15,0.035,BG);
    for J:=Ceil(A/0.7) to System.Math.Floor(B/0.7) do begin X:=J*0.7;Line(X,Y+(Z-Y)*(X-A)/(B-A)-0.2,X+0.13,Y+(Z-Y)*(X-A)/(B-A)-0.43,0.025,Edge);end;
    if Floor.Kind=tkIce then Line(A,Y+0.03,B,Z+0.03,0.05,$00FFFFCE);
  end;
  for I:=Max(0,P.MoveAt(T)-3) to Min(High(P.Moves),P.MoveAt(T)+3) do begin
    M:=P.Moves[I];if M.Kind<>tmWallKick then Continue;
    Bar(M.Origin.X-0.55,M.Origin.Y-0.4,M.Origin.X-0.34,M.Origin.Y+2.2,Stone);
    Line(M.Origin.X-0.34,M.Origin.Y-0.4,M.Origin.X-0.34,M.Origin.Y+2.2,0.04,Edge);
  end;
  // 最後の安全そうな門を通る直前にも扉が落ちる。
  for I:=Max(0,P.MoveAt(T)-4) to Min(High(P.Moves),P.MoveAt(T)+3) do begin
    M:=P.Moves[I];if (M.Pattern<>17) or ((I>0) and (P.Moves[I-1].Pattern=17)) then Continue;
    X:=M.Target.X;Line(X,-0.2,X,2.8,0.09,Edge);Line(X,2.8,X+1.6,2.8,0.09,Edge);
    Bar(X+0.10,2.1,X+1.5,2.23,Glow);
  end;
  // 崩落片は通過済みの経路の後方へ落とす。
  for I:=Max(0,P.MoveAt(T)-5) to P.MoveAt(T) do begin
    M:=P.Moves[I];Age:=T-M.Cue;
    if (Age<0) or (Age>1.2) or not (M.Pattern in [1,4,9,10,12,14,18]) then Continue;
    for J:=0 to 5 do begin X:=M.Origin.X-1.3+J*0.38;Y:=M.Origin.Y-Age*Age*5-J*0.06;
      Bar(X,Y-0.17,X+0.28,Y,Stone);Line(X,Y,X+0.25,Y,0.04,Edge);end;
  end;
end;
procedure TPainter.Traps;
var I,J,N:Integer;Q:TTrapObstacle;B:TTrapBox;X,Y,W,H,A,Age:Double;C:TColor;
begin
  for I:=0 to High(P.Obstacles) do begin
    Q:=P.Obstacles[I];if (T<Q.Reveal) or (T>Q.Finish+0.25) then Continue;
    B:=Q.BoundsAt(T);if (B.Right<L-2) or (B.Left>L+VW+2) then Continue;
    X:=(B.Left+B.Right)*0.5;Y:=B.Bottom;W:=B.Right-B.Left;H:=B.Top-B.Bottom;
    if T<Q.Fire then begin Dot(Q.X,Q.Y+0.1,0.055,Glow);Continue;end;
    if TrapHarmless(Q.Kind) then begin
      Age:=Max(0.0,T-Q.Cue);N:=Max(3,Round(Q.W/0.4));
      for J:=0 to N do begin A:=Q.X-Q.W*0.5+Q.W*J/N;
        Bar(A,Q.Y-Age*Age*8-0.22,A+0.28,Q.Y-Age*Age*8,Edge);end;
      Continue;
    end;
    C:=$005265F5;
    case Q.Kind of
      tkSpikes,tkHiddenSpikes,tkFalseFloor,tkFlame,tkLava:begin
        N:=Max(2,Ceil(W/0.22));
        for J:=0 to N-1 do Quad(TrapPoint(B.Left+W*J/N,Y),TrapPoint(B.Left+W*(J+0.5)/N,Y+H),
          TrapPoint(B.Left+W*(J+1)/N,Y),TrapPoint(B.Left+W*J/N,Y),C);
        Line(B.Left,Y,B.Right,Y,0.05,Glow);
      end;
      tkBlade,tkFlyingBlade,tkHunter:begin
        Dot(X,Y+H*0.5,Min(W,H)*0.5,C);
        for J:=0 to 7 do begin A:=J*Pi/4+T*8;
          Line(X,Y+H*0.5,X+Cos(A)*W*0.5,Y+H*0.5+Sin(A)*H*0.5,0.05,Glow);end;
      end;
      tkArrow:begin Line(B.Left,Y+H*0.5,B.Right,Y+H*0.5,0.045,Glow);Line(B.Left,Y+H*0.5,B.Left+0.2,Y+H,0.035,C);end;
      tkLaser:begin Bar(B.Left,Y,B.Right,Y+H,C);Line(B.Left,Y+H*0.5,B.Right,Y+H*0.5,0.025,$00FFFFE8);Dot(B.Right,Y+H*0.5,0.13,Glow);end;
      tkBoulder:begin Dot(X,Y+H*0.5,W*0.5,Stone);S.Circle((X-L)*K,(Top-Y-H*0.5)*K,W*0.5*K,Edge,False,3);
        for J:=0 to 4 do begin A:=J*1.26+T*4;Line(X,Y+H*0.5,X+Cos(A)*W*0.4,Y+H*0.5+Sin(A)*H*0.4,0.05,BG);end;end;
      else begin
        Bar(B.Left,Y,B.Right,Y+H,Stone);Line(B.Left,Y,B.Right,Y,0.08,C);
        for J:=0 to Max(1,System.Math.Floor(W/0.4)) do begin A:=B.Left+J*0.4;Line(A,Y+0.04,Min(A+0.23,B.Right),Min(Y+0.27,Y+H),0.065,Glow);end;
        if Q.Kind=tkBackground then begin Bar(X-0.6,Y+H*0.65,X-0.24,Y+H*0.73,C);Bar(X+0.24,Y+H*0.65,X+0.6,Y+H*0.73,C);end;
      end;
    end;
    Age:=T-Q.Cue;
    if (Age>=0) and (Age<0.33) then for J:=0 to 7 do begin A:=J*Pi/4;
      Dot(X+Cos(A)*Age*2,Y+Sin(A)*Age*2,0.028*(1-Age/0.33),Glow);end;
  end;
end;
procedure TPainter.Hero;
var M:TTrapMove;V,Q:TTrapPoint;H,U,Swing,Lean,Age,Angle:Double;I,J:Integer;C:TColor;
begin
  I:=P.MoveAt(T);M:=P.Moves[I];V:=P.Position(T);H:=M.HeightAt(T);U:=M.Progress(T);
  Swing:=Sin(V.X*8)*0.16;Lean:=0.04;
  if M.Kind in [tmJump,tmDoubleJump,tmWallKick,tmLaunch,tmFall] then begin Swing:=Sin(U*Pi)*0.18;Lean:=0.09;end;
  if M.Kind in [tmHang,tmClimb,tmStop] then Swing:=0;
  if M.Kind=tmWallKick then Swing:=-0.2*(1-TrapRange(T,M.Start,M.Cue));
  if M.Kind=tmLaunch then Lean:=Sin(U*Pi*2)*0.16;
  if M.Kind in [tmDoubleJump,tmLaunch,tmSkate] then for J:=1 to 5 do begin
    Q:=M.Position(Max(M.Start,T-J*0.035));Dot(Q.X-0.15,Q.Y+0.14,0.025*(6-J),Glow);
  end;
  if T>=P.GoalTime then begin Swing:=0;Lean:=0;end;
  C:=$00B9E77B;
  Line(V.X-0.1,V.Y+0.08,V.X-0.13+Swing,V.Y+H*0.37,0.10,$006A8061);
  Line(V.X+0.13,V.Y+0.08,V.X+0.10-Swing,V.Y+H*0.37,0.10,C);
  Line(V.X,V.Y+H*0.35,V.X+Lean,V.Y+H*0.74,0.20,C);
  if (M.Kind in [tmHang,tmClimb]) or (T>=P.GoalTime) then begin
    Line(V.X,V.Y+H*0.64,V.X-0.25,V.Y+H*0.96,0.08,C);Line(V.X+0.08,V.Y+H*0.64,V.X+0.27,V.Y+H*0.96,0.08,C);
  end else begin
    Line(V.X-0.04,V.Y+H*0.68,V.X-0.23-Swing*0.35,V.Y+H*0.48,0.08,C);
    Line(V.X+0.10,V.Y+H*0.68,V.X+0.27,V.Y+H*0.48+Swing,0.08,C);
  end;
  Dot(V.X+Lean,V.Y+H*0.85,Min(0.16,H*0.22),$00DEF9DF);
  Dot(V.X+Lean+0.075,V.Y+H*0.87,0.028,BG);
  Line(V.X-0.07,V.Y+H*0.70,V.X-0.40,V.Y+H*0.65+Sin(T*15)*0.05,0.065,$0054B5FF);
  Age:=T-M.Cue;
  if M.CueSynced and (Age>=0) and (Age<0.20) then begin
    Q:=M.Position(M.Cue);
    for J:=0 to 7 do begin Angle:=J*Pi/4;Dot(Q.X+Cos(Angle)*(0.45+Age),Q.Y+0.55+Sin(Angle)*(0.45+Age),0.022*(1-Age/0.20),Glow);end;
  end;
  if (I>0) and P.Moves[I-1].Landing then begin Age:=T-M.Start;if (Age>=0) and (Age<0.22) then for J:=0 to 4 do
    Dot(V.X+(J-2)*Age*1.8,V.Y+0.03+Sin(J)*Age,0.033*(1-Age/0.22),Glow);end;
end;
procedure TPainter.Finish;
const Glyph:array[0..4,0..6] of Byte=((15,16,16,16,16,16,15),(16,16,16,16,16,16,31),
  (31,16,16,30,16,16,31),(14,17,17,31,17,17,17),(30,17,17,30,20,18,17));
var X,Y,A:Double;I,J,B:Integer;
begin
  X:=P.GoalX+1;Line(X,0,X,3.1,0.12,Edge);Line(X,3.1,X+2,3.1,0.12,Edge);Line(X+2,3.1,X+2,0,0.12,Edge);
  if T<P.GoalTime then begin Bar(X+0.1,2.2,X+1.9,2.35,Glow);Exit;end;
  A:=TrapRange(T,P.GoalTime,P.Duration);Y:=3.8;
  for I:=0 to 4 do for J:=0 to 6 do for B:=0 to 4 do
    if Glyph[I,J] and (1 shl (4-B))<>0 then Bar(P.GoalX-1.5+I*0.67+B*0.105,Y-J*0.12,
      P.GoalX-1.41+I*0.67+B*0.105,Y+0.09-J*0.12,Glow);
  for I:=0 to 35 do begin X:=P.GoalX-4+Frac(I*0.618)*9;Y:=4.5-Frac(I*0.382+A*0.9)*4;
    Bar(X,Y,X+0.05,Y+0.1,Palettes[TTrapStage(I mod 8),3]);end;
end;
procedure TPainter.Paint;
var V,A,B:TTrapPoint;Zoom,Progress,Weight,Needed:Double;Q:TTrapObstacle;Box:TTrapBox;
begin
  T:=EnsureRange(F.Time,0.0,P.Duration);V:=P.Position(T);Progress:=T/P.Duration;
  Zoom:=15+Progress*4+2*Sqr(Sin(Pi*P.Moves[P.MoveAt(T)].Progress(T)));
  VW:=Max(Zoom,F.Width/F.Height*7.5);
  for Q in P.Obstacles do begin
    if TrapHarmless(Q.Kind) or (T<Q.Reveal-0.25) or (T>Q.Finish+0.25) then Continue;
    Weight:=TrapRange(T,Q.Reveal-0.25,Q.Cue)*(1-TrapRange(T,Q.Cue,Q.Finish+0.25));
    Box:=Q.BoundsAt(Q.Cue);
    Needed:=Max((V.X-Box.Left+1)/0.32,(Box.Right-V.X+1)/0.68);
    Needed:=Max(Needed,Max((V.Y-Box.Bottom+1)/0.26,(Box.Top-V.Y+1)/0.74)*F.Width/F.Height);
    VW:=Max(VW,Zoom+(Needed-Zoom)*Weight);
  end;
  K:=F.Width/VW;
  A:=P.Position(Max(0.0,T-0.22));B:=P.Position(Min(P.GoalTime,T+0.22));
  L:=V.X-VW*0.32;Top:=F.Height/K*0.74+(A.Y+V.Y*2+B.Y)*0.25;
  BG:=Palettes[P.Theme,0];Stone:=Palettes[P.Theme,1];Edge:=Palettes[P.Theme,2];Glow:=Palettes[P.Theme,3];
  Backdrop;Terrain;Traps;Finish;if not F.BackgroundOnly then Hero;
end;
procedure DrawTrapAction(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
var Painter:TPainter;
begin Painter.S:=Surface;Painter.P:=Plan;Painter.F:=Frame;Painter.Paint;end;
end.
