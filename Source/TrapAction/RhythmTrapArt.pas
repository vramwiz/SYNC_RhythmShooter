unit RhythmTrapArt;
// 保存軌道と同じ幾何を描く。アニメーションの積算状態を持たない。
interface
uses RhythmTrapPlan,RhythmRenderSurface,RhythmAnimation;
procedure DrawTrapAction(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
procedure DrawTrapBackdrop(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
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
    procedure Setup;
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
var I,J:Integer;X,Y,B,SavedLeft:Double;
begin
  // 背景専用の画面座標へ切替え、横追従・時刻から完全に切り離す。
  SavedLeft:=L;L:=0;
  S.FillRect(0,0,F.Width,F.Height,BG);
  B:=Top-F.Height/K;
  for I:=-2 to Ceil(VW/2.8)+2 do begin
    X:=I*2.8;Y:=2.4+Sin(I*2.4)*0.6;
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
    X:=Frac(I*0.618033)*VW;Y:=Top-Frac(I*0.381966)*F.Height/K;
    Dot(X,Y,0.013+Ord(P.Theme=tsVolcano)*0.012,Edge);
  end;
  Bar(0,B,VW,B+0.10,Glow);
  L:=SavedLeft;
end;
procedure TPainter.Terrain;
var I,J:Integer;Floor:TTrapPlatform;A,B,Y,Age,X:Double;
begin
  for I:=0 to High(P.Platforms) do begin
    Floor:=P.Platforms[I];A:=Floor.Left;B:=Floor.Right;Y:=Floor.Y;
    if (B<L-2) or (A>L+VW+2) or (T<Floor.Start) then Continue;
    if (T>=Floor.Finish) and (Floor.Finish<P.Duration) then begin
      if Floor.Kind=tkCrumble then begin
        Age:=T-Floor.Finish;
        if Age<0.7 then for J:=0 to 5 do begin
          X:=A+(B-A)*J/6;
          Bar(X,Y-0.25-Age*Age*7,X+(B-A)*0.13,Y-Age*Age*7,Stone);
        end;
      end;
      Continue;
    end;
    Bar(A,Min(-1.5,Y-0.65),B,Y,Stone);Line(A,Y,B,Y,0.09,Edge);
    Line(A,Y-0.15,B,Y-0.15,0.035,BG);
    for J:=Ceil(A/0.7) to System.Math.Floor(B/0.7) do begin
      X:=J*0.7;Line(X,Y-0.2,Min(B,X+0.13),Y-0.43,0.025,Edge);
    end;
    if Floor.Kind=tkCrumble then
      Line(A+(B-A)*0.45,Y,A+(B-A)*0.56,Y-0.22,0.025,BG);
  end;
  // 天井の下面は当たり判定と同じ保存座標。段差の縦面も描く。
  for I:=0 to High(P.Ceilings) do begin
    Floor:=P.Ceilings[I];A:=Floor.Left;B:=Floor.Right;Y:=Floor.Y;
    if (B<L-1) or (A>L+VW+1) then Continue;
    Bar(A,Y,B,Y+0.65,Stone);Line(A,Y,B,Y,0.075,Edge);
    if (I>0) and (Abs(P.Ceilings[I-1].Right-A)<1E-8) then
      Line(A,P.Ceilings[I-1].Y,A,Y,0.06,Edge);
    for J:=Ceil(A/0.9) to System.Math.Floor(B/0.9) do begin
      X:=J*0.9;Line(X,Y+0.18,Min(X+0.15,B),Y+0.37,0.025,BG);
    end;
  end;
end;
procedure TPainter.Traps;
var I,J,N:Integer;Q:TTrapObstacle;B:TTrapBox;Y,W,H:Double;C:TColor;
begin
  for I:=0 to High(P.Obstacles) do begin
    Q:=P.Obstacles[I];
    // 穴と崩れる床はTerrainの実タイルだけで描く。後方への無関係な落下物を作らない。
    if TrapHarmless(Q.Kind) or (T<Q.Reveal) or (T>Q.Finish) then Continue;
    B:=Q.BoundsAt(T);if (B.Right<L-1) or (B.Left>L+VW+1) then Continue;
    Y:=B.Bottom;W:=B.Right-B.Left;H:=B.Top-B.Bottom;
    C:=$005265F5;
    case Q.Kind of
      tkSpikes,tkHiddenSpikes:begin
        if H>0.001 then begin
          N:=Max(2,Ceil(W/0.22));
          for J:=0 to N-1 do Quad(TrapPoint(B.Left+W*J/N,Y),TrapPoint(B.Left+W*(J+0.5)/N,Y+H),
            TrapPoint(B.Left+W*(J+1)/N,Y),TrapPoint(B.Left+W*J/N,Y),C);
        end;
        Line(B.Left,Y+0.02,B.Right,Y+0.02,0.04,Edge);
      end;
      tkCeiling:begin
        N:=Max(1,Ceil(W/0.23));
        for J:=0 to N-1 do Quad(TrapPoint(B.Left+W*J/N,Y+H),
          TrapPoint(B.Left+W*(J+0.5)/N,Y),TrapPoint(B.Left+W*(J+1)/N,Y+H),
          TrapPoint(B.Left+W*J/N,Y+H),C);
        Line(B.Left,Y+H,B.Right,Y+H,0.055,Glow);
        if (T>=Q.Cue) and (T<Q.Cue+0.10) then
          Line(Q.X-0.25,Q.Y+0.02,Q.X+0.25,Q.Y+0.02,0.05,Glow);
      end;
    end;
  end;
end;
procedure TPainter.Hero;
var M,E:TTrapMove;V,Q:TTrapPoint;H,U,Swing,Lean,Age,At,LiftA,LiftB,Face:Double;I,J,N:Integer;C:TColor;
begin
  I:=P.MoveAt(T);M:=P.Moves[I];V:=P.Position(T);H:=M.HeightAt(T);U:=M.Progress(T);
  Face:=P.Facing(T);Swing:=Sin(M.StepPhase(T))*0.22*Cos((I mod 2)*Pi);Lean:=0.04*Face;
  LiftA:=M.FootLift(T,I mod 2);LiftB:=M.FootLift(T,(I+1) mod 2);
  if M.Kind=tmJump then begin
    Swing:=Sin(U*Pi)*0.13;Lean:=0.07*Face;LiftA:=Sin(U*Pi)*0.13;LiftB:=LiftA;
  end;
  if (M.Kind=tmStop) or (T>=P.GoalTime) then begin Swing:=0;Lean:=0;LiftA:=0;LiftB:=0;end;
  C:=$00B9E77B;
  Line(V.X-0.12+Swing,V.Y+0.05+LiftA,V.X-0.08,V.Y+H*0.37,0.10,$006A8061);
  Line(V.X+0.12-Swing,V.Y+0.05+LiftB,V.X+0.08,V.Y+H*0.37,0.10,C);
  Line(V.X,V.Y+H*0.35,V.X+Lean,V.Y+H*0.74,0.20,C);
  if T>=P.GoalTime then begin
    Line(V.X,V.Y+H*0.64,V.X-0.25,V.Y+H*0.96,0.08,C);
    Line(V.X+0.08,V.Y+H*0.64,V.X+0.27,V.Y+H*0.96,0.08,C);
  end else begin
    Line(V.X-0.04*Face,V.Y+H*0.68,V.X-(0.23+Swing*0.35)*Face,V.Y+H*0.48,0.08,C);
    Line(V.X+0.10*Face,V.Y+H*0.68,V.X+0.27*Face,V.Y+H*0.48+Swing,0.08,C);
  end;
  Dot(V.X+Lean,V.Y+H*0.85,0.16,$00DEF9DF);
  Dot(V.X+Lean+0.075*Face,V.Y+H*0.87,0.028,BG);
  Line(V.X-0.07*Face,V.Y+H*0.70,V.X-0.30*Face,V.Y+H*0.65+Sin(T*15)*0.03,0.065,$0054B5FF);
  // 音の瞬間の接地・停止を足元に描く。動作途中の無関係な円形点滅は使わない。
  for N:=Max(0,I-2) to I do begin
    E:=P.Moves[N];At:=E.Finish;
    if E.Kind=tmStop then begin
      if not E.CueSynced then Continue;At:=E.Start;
    end else if not E.LandSynced then Continue;
    Age:=T-At;if (Age<0) or (Age>=0.12) then Continue;
    Q:=E.Position(At);
    Line(Q.X-0.10-Age,Q.Y+0.015,Q.X+0.10+Age,Q.Y+0.015,0.035,Glow);
    for J:=0 to 4 do
      Dot(Q.X+(J-2)*Age*1.7,Q.Y+0.035+Sin(J*0.7)*Age,0.025*(1-Age/0.12),Glow);
  end;
end;
procedure TPainter.Finish;
const Glyph:array[0..4,0..6] of Byte=((15,16,16,16,16,16,15),(16,16,16,16,16,16,31),
  (31,16,16,30,16,16,31),(14,17,17,31,17,17,17),(30,17,17,30,20,18,17));
var X,Y,A,Base:Double;I,J,B:Integer;
begin
  Base:=P.Position(P.GoalTime).Y;
  X:=P.GoalX+1;Line(X,Base,X,Base+3.1,0.12,Edge);Line(X,Base+3.1,X+2,Base+3.1,0.12,Edge);Line(X+2,Base+3.1,X+2,Base,0.12,Edge);
  if T<P.GoalTime then begin Bar(X+0.1,Base+2.2,X+1.9,Base+2.35,Glow);Exit;end;
  A:=TrapRange(T,P.GoalTime,P.Duration);Y:=Base+3.8;
  for I:=0 to 4 do for J:=0 to 6 do for B:=0 to 4 do
    if Glyph[I,J] and (1 shl (4-B))<>0 then Bar(P.GoalX-1.5+I*0.67+B*0.105,Y-J*0.12,
      P.GoalX-1.41+I*0.67+B*0.105,Y+0.09-J*0.12,Glow);
  for I:=0 to 35 do begin X:=P.GoalX-4+Frac(I*0.618)*9;Y:=Base+4.5-Frac(I*0.382+A*0.9)*4;
    Bar(X,Y,X+0.05,Y+0.1,Palettes[TTrapStage(I mod 8),3]);end;
end;
procedure TPainter.Setup;
begin
  if (F.Width<=0) or (F.Height<=0) then Exit;
  T:=EnsureRange(F.Time,0.0,P.Duration);
  // 倍率と上下の視点は固定。床と天井の段差やジャンプで画角を揺らさない。
  K:=Min(F.Width/18.0,F.Height/8.0);VW:=F.Width/K;
  L:=P.ForwardX(T)-VW*0.32;Top:=F.Height/K*0.74;
  BG:=Palettes[P.Theme,0];Stone:=Palettes[P.Theme,1];Edge:=Palettes[P.Theme,2];Glow:=Palettes[P.Theme,3];
end;
procedure TPainter.Paint;
begin
  if (F.Width<=0) or (F.Height<=0) then Exit;
  Setup;Backdrop;Terrain;Traps;Finish;if not F.BackgroundOnly then Hero;
end;
procedure DrawTrapAction(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
var Painter:TPainter;
begin Painter.S:=Surface;Painter.P:=Plan;Painter.F:=Frame;Painter.Paint;end;
procedure DrawTrapBackdrop(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
var Painter:TPainter;
begin Painter.S:=Surface;Painter.P:=Plan;Painter.F:=Frame;Painter.Setup;Painter.Backdrop;end;
end.
