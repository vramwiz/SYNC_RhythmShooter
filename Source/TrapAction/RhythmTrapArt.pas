unit RhythmTrapArt;
// 保存軌道と同じ幾何を描く。アニメーションの積算状態を持たない。
// 描画だけを担当し、罠の採用・音声解析・保存データの変更は行わない。
interface
uses RhythmTrapPlan,RhythmRenderSurface,RhythmAnimation;
// Surface/Planは借用。Frameの寸法は画素、Timeは原音声先頭からの秒で末尾演出も同じ時計を使う。
// BackgroundOnlyでも地形と罠は描き、共通EQの背景抽出用に主人公と花火だけを省く。
procedure DrawTrapAction(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
// 奥壁と地上の空だけを描く背景専用入口。床・天井・罠は含めない。
procedure DrawTrapBackdrop(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
implementation
uses System.Math,System.Types,Vcl.Graphics,RhythmStyles,RhythmFireworksScene;
type
  TPainter=record
    S:TAnimationRenderSurface;P:TTrapPlan;F:TAnimationFrame;
    T,K,L,Top,VW:Double;BG,Stone,Edge,Glow:TColor; // Kは画素/世界単位、L/Top/VWは世界座標の画角。
    procedure Bar(A,B,C,D:Double;Color:TColor;Alpha:Double=1);
    procedure Line(A,B,C,D,Width:Double;Color:TColor);
    procedure Limb(A,B,C,D,Width:Double;Color:TColor);
    procedure Dot(X,Y,R:Double;Color:TColor);
    procedure Quad(A,B,C,D:TTrapPoint;Color:TColor);
    procedure Spike(X,Y,W,H:Double;Down:Boolean;Side:Double=0);
    procedure Backdrop;
    procedure SurfaceBackdrop;
    procedure Setup;
    procedure Terrain;
    procedure Traps;
    procedure Hero;
    procedure Finish;
    procedure Paint;
  end;
// TColorはBGR順。奥壁・暖色の地面・寒色の天井を明度と色相の両方で分ける。
const CaveBackground=$00564634;CaveStone=$00738DA4;CaveEdge=$00B2D2E8;
      CaveCeiling=$009D8A77;CaveCeilingEdge=$00E1D3C2;
      SurfaceSky=$00FFE2AF;
      Palettes:array[TTrapStage,0..3] of TColor=(
  (CaveBackground,CaveStone,CaveEdge,$009CEFD1),
  (CaveBackground,CaveStone,CaveEdge,$00A6DFEA),
  (CaveBackground,CaveStone,CaveEdge,$00B4D7F0),
  (CaveBackground,CaveStone,CaveEdge,$00E6C2DF),
  (CaveBackground,CaveStone,CaveEdge,$00E3D8A3),
  (CaveBackground,CaveStone,CaveEdge,$0071BEFA),
  (CaveBackground,CaveStone,CaveEdge,$00EFE2BB),
  (CaveBackground,CaveStone,CaveEdge,$00ADD9AB));
procedure TPainter.Bar(A,B,C,D:Double;Color:TColor;Alpha:Double);
begin if (C<=A) or (D<=B) then Exit;S.FillRect(Round((A-L)*K),Round((Top-D)*K),Round((C-L)*K),Round((Top-B)*K),Color,Alpha);end;
procedure TPainter.Line(A,B,C,D,Width:Double;Color:TColor);
begin S.Line((A-L)*K,(Top-B)*K,(C-L)*K,(Top-D)*K,Color,Max(1.0,Width*K));end;
procedure TPainter.Limb(A,B,C,D,Width:Double;Color:TColor);
begin Line(A,B,C,D,Width+0.065,$00150F0C);Line(A,B,C,D,Width,Color);end;
procedure TPainter.Dot(X,Y,R:Double;Color:TColor);
begin S.Circle((X-L)*K,(Top-Y)*K,R*K,Color,True);end;
procedure TPainter.Quad(A,B,C,D:TTrapPoint;Color:TColor);
begin S.FillQuad(PointF((A.X-L)*K,(Top-A.Y)*K),PointF((B.X-L)*K,(Top-B.Y)*K),
  PointF((C.X-L)*K,(Top-C.Y)*K),PointF((D.X-L)*K,(Top-D.Y)*K),Color);end;
procedure TPainter.Spike(X,Y,W,H:Double;Down:Boolean;Side:Double);
var V:Double;
  function P(U,V:Double):TTrapPoint;
  begin
    if Side<>0 then Exit(TrapPoint(X+Side*V*H,Y+(U-0.5)*W));
    if Down then V:=1-V;Result:=TrapPoint(X+(U-0.5)*W,Y+V*H);
  end;
begin
  if (H<=0.001) or (W<=0) then Exit;
  Quad(P(0,0),P(0.5,1),P(1,0),P(0,0),$004A4138);
  Quad(P(0.03,0),P(0.5,1),P(0.46,0.07),P(0.03,0),$00DDD8D1);
  Quad(P(0.46,0.07),P(0.5,1),P(0.96,0),P(0.46,0.07),$00A99E90);
  Quad(P(0.39,0.04),P(0.5,0.99),P(0.58,0.04),P(0.39,0.04),$00FCFAF7);
  V:=0.35+0.18*Sin(T*2.7+X*0.8);
  Line(P(V*0.5,V).X,P(V*0.5,V).Y,P(1-V*0.5,V).X,P(1-V*0.5,V).Y,0.018,$00FFFFFF);
  Line(P(0.04,0.02).X,P(0.04,0.02).Y,P(0.5,0.98).X,P(0.5,0.98).Y,0.017,$00ECE6DE);
end;
procedure TPainter.Backdrop;
var I,J:Integer;X,Y,Y1,B,SavedLeft,A0,A1,CX,CY,RX,RY:Double;
begin
  // 洞窟の奥の丸い岩壁だけを低コントラストで描く。実天井と紛らわしい尖り・発光は置かない。
  SavedLeft:=L;L:=0;
  S.FillRect(0,0,F.Width,F.Height,BG);
  B:=Top-F.Height/K;
  CX:=VW*0.57;CY:=1.3;
  for J:=0 to 2 do begin
    RX:=VW*(0.36+J*0.15);RY:=2.5+J*0.8;
    for I:=0 to 27 do begin
      A0:=Pi*I/27;A1:=Pi*(I+1)/27;
      Line(CX+Cos(A0)*RX,CY+Sin(A0)*RY,CX+Cos(A1)*RX,CY+Sin(A1)*RY,
        0.16+J*0.09,$006D5841+J*$00030202);
    end;
  end;
  for I:=-1 to Ceil(VW/3.6) do begin
    X:=I*3.6;Y:=3.2+Sin(I*1.7)*0.35;Y1:=3.2+Sin((I+1)*1.7)*0.35;
    Quad(TrapPoint(X,Top),TrapPoint(X+3.6,Top),TrapPoint(X+3.6,Y1),TrapPoint(X,Y),$0066523D);
    Line(X+0.4,Y+0.15,X+2.8,Y+0.48,0.025,$007E6A53);
    Quad(TrapPoint(X,B),TrapPoint(X+3.8,B),TrapPoint(X+3.3,B+0.65),TrapPoint(X+0.6,B+0.8),$00604E3A);
  end;
  L:=SavedLeft;
end;
procedure TPainter.SurfaceBackdrop;
var Lift:TTrapPlatform;Surface,Center,X,Y,SkyBottom:Double;I,J:Integer;
begin
  if (T<P.GoalTime) or not P.GoalLift(Lift) then Exit;
  Surface:=Lift.Y+Lift.DY;Center:=(Lift.Left+Lift.Right)*0.5;SkyBottom:=(Top-Surface)*K;
  if SkyBottom<=0 then Exit;
  S.FillRect(0,0,F.Width,Min(F.Height,Ceil(SkyBottom)),SurfaceSky);
  Dot(Center+5.2,Surface+4.2,0.58,$00E2F8FF);Dot(Center+5.2,Surface+4.2,0.42,$00C1EEFF);
  for I:=-1 to 2 do begin
    X:=Center-5.8+I*4.3;Y:=Surface+2.8+(I mod 2)*0.9;
    for J:=0 to 3 do Dot(X+J*0.28,Y+Sin(J*1.2)*0.10,0.27,$00FFFFFF);
  end;
  for I:=Floor(L/3.2)-1 to Ceil((L+VW)/3.2) do begin
    X:=I*3.2;Y:=Surface+0.35+0.24*Sin(I*1.7);
    Quad(TrapPoint(X,Surface),TrapPoint(X+1.5,Y),TrapPoint(X+3.3,Surface),TrapPoint(X,Surface),$00A2DCA8);
  end;
end;
procedure TPainter.Terrain;
var I,J:Integer;Floor,Lift:TTrapPlatform;A,B,Y,X,Age,Bottom,RockTop:Double;Bounds:TTrapBox;Corners:TTrapCorners;
  function Joined(Index:Integer;AtX,Height:Double;LeftSide:Boolean):Boolean;
  var N:Integer;Tile:TTrapPlatform;Box:TTrapBox;
  begin
    Result:=False;
    for N:=0 to High(P.Platforms) do begin
      if N=Index then Continue;Tile:=P.Platforms[N];
      if Tile.Motion=pmGrate then Continue;
      if not Tile.Solid(T,P.Duration) then Continue;Box:=Tile.BoundsAt(T);
      if Abs(Box.Top-Height)>1E-8 then Continue;
      if LeftSide then Result:=(Box.Left<AtX-1E-8) and (Box.Right>=AtX-1E-8)
      else Result:=(Box.Right>AtX+1E-8) and (Box.Left<=AtX+1E-8);
      if Result then Exit;
    end;
  end;
  procedure StoneTile(const Tile:TTrapPlatform;const Box:TTrapBox;Index:Integer);
  var Row,Col:Integer;A,B,Y,Low,CellX,Depth,Width,Drop,Age,X:Double;
  begin
    A:=Max(Box.Left,L-0.5);B:=Min(Box.Right,L+VW+0.5);Y:=Box.Top;Low:=Max(Bottom,Box.Bottom);
    if (B<=A) or (Y<=Low) then Exit;
    // 種別・作動前の時刻に依存しない同一の石材。地面の分割線も目印にしない。
    Bar(A,Low,B,Y,Stone);Bar(A,Max(Low,Y-0.12),B,Y,Edge);
    if Low<Y-0.19 then Line(A,Y-0.17,B,Y-0.17,0.035,$00516471);
    for Row:=0 to 6 do begin
      Depth:=0.30+Row*0.52;
      for Col:=System.Math.Floor(A/1.35)-1 to Ceil(B/1.35) do begin
        CellX:=Col*1.35+(Row mod 2)*0.48;Width:=0.72+0.24*Sin(Col*4.2+Row*1.2);
        Bar(Max(A,CellX),Max(Low,Y-Depth-0.10),Min(B,CellX+Width),Y-Depth,Stone-$00060708);
        Bar(Max(A,CellX+0.07),Max(Low,Y-Depth-0.13),Min(B,CellX+0.65),Y-Depth-0.10,$0063798D);
      end;
    end;
    if not Joined(Index,Box.Left,Y,True) then Line(Box.Left,Low,Box.Left,Y,0.035,$002B3647);
    if not Joined(Index,Box.Right,Y,False) then Line(Box.Right,Low,Box.Right,Y,0.035,$002B3647);
    if Tile.Motion in [pmHorizontal,pmVertical,pmReveal] then
      Line(A,Box.Bottom,B,Box.Bottom,0.025,$00242C3C);
    // 地割れと破片は実際に地面が動き出してから出す。事前の色分け・鋲・ひびは付けない。
    if Tile.Motion in [pmDrop,pmFeint] then begin
      Drop:=Abs(Tile.OffsetAt(T).Y);
      if Drop>0.004 then begin
        X:=Max(A,Min(B-0.3,(Tile.Left+Tile.Right)*0.5));
        Line(X,Y,X+0.14,Y-0.13,0.025,$002B3647);
        Line(X+0.14,Y-0.13,Min(B,X+0.28),Y-0.07,0.025,$002B3647);
      end;
      if (Tile.Motion=pmDrop) and (T>Tile.Trigger) and (T<Tile.Trigger+0.32) then begin
        Age:=T-Tile.Trigger;
        for Col:=0 to 6 do begin
          X:=Tile.Left+(Tile.Right-Tile.Left)*(Col+0.5)/7;
          Bar(X-0.025,Tile.Y-0.1-Age*Age*18,X+0.025,Tile.Y-Age*Age*18,Stone);
        end;
      end;
    end;
  end;
begin
  Bottom:=Top-F.Height/K-0.5;
  for I:=0 to High(P.Platforms) do begin
    Floor:=P.Platforms[I];Bounds:=Floor.BoundsAt(T);A:=Bounds.Left;B:=Bounds.Right;Y:=Bounds.Top;
    if (B<L-2) or (A>L+VW+2) or (T<Floor.Reveal) or not Floor.Solid(T,P.Duration) then Continue;
    if Floor.Motion=pmGrate then begin
      Line(A,Y,B,Y,0.022,$00B5A99D);
      for J:=Ceil(A/0.16) to System.Math.Floor(B/0.16) do begin
        X:=J*0.16;Line(X,Y,Min(B,X+0.035),Y-0.09,0.014,$008D8276);
      end;
      Continue;
    end;
    if Floor.Motion=pmGoalLift then begin
      // 昇降板の下へ伸びる一本の棒。板の実体と同じ絶対時刻・高さで描く。
      X:=(A+B)*0.5;
      Bar(X-0.24,Floor.Y-1.20,X+0.24,Floor.Y-0.20,$0048586A);
      Bar(X-0.10,Floor.Y-1.20,X+0.10,Y-TrapPlatformThickness,$0098B3C4);
      Line(X-0.04,Floor.Y-1.15,X-0.04,Y-TrapPlatformThickness,0.025,$00EFF5F1);
      Bar(A,Bounds.Bottom,B,Y,$003D5369);Bar(A+0.04,Y-0.10,B-0.04,Y,$00C9DDE5);
      Line(A,Y,B,Y,0.035,$00ECF7F5);Continue;
    end;
    if (Floor.Motion=pmHinge) and (T>Floor.Trigger) then begin
      Corners:=Floor.CornersAt(T);Quad(Corners[0],Corners[1],Corners[2],Corners[3],Stone);
      Line(Corners[0].X,Corners[0].Y,Corners[1].X,Corners[1].Y,0.055,Edge);
      Line(Corners[3].X,Corners[3].Y,Corners[2].X,Corners[2].Y,0.025,$00242C3C);
      Dot(Floor.Left,Floor.Y,0.085,$00647386);Dot(Floor.Left,Floor.Y,0.035,$00D4DDD8);
      Continue;
    end;
    if Floor.Motion=pmHorizontal then
      Line(Floor.Left-Abs(Floor.DX),Floor.Y-0.35,Floor.Right+Abs(Floor.DX),Floor.Y-0.35,0.045,$00546578);
    if Floor.Motion=pmVertical then
      Line((A+B)*0.5,Floor.Y-Abs(Floor.DY)-0.4,(A+B)*0.5,Floor.Y+Abs(Floor.DY)+0.4,0.045,$00546578);
    if Floor.Motion=pmLift then
      Line(A+0.10,Floor.Y-0.6,A+0.10,Floor.Y+Floor.DY+Floor.DX,0.06,$00647386);
    if Floor.Motion=pmNeedleLift then
      Line(A+0.10,Floor.Y-0.6,A+0.10,Floor.Y+Floor.DY,0.06,$00647386);
    StoneTile(Floor,Bounds,I);
    if (Floor.Motion=pmReveal) and (T<Floor.Reveal+0.16) then begin
      Age:=1-(T-Floor.Reveal)/0.16;
      Line(A,Y+0.02,B,Y+0.02,0.025+Age*0.04,$00F1FFFF);
      Line(A,Y-0.02,A-0.15*Age,Y+0.15*Age,0.03,$00F1FFFF);
      Line(B,Y-0.02,B+0.15*Age,Y+0.15*Age,0.03,$00F1FFFF);
    end;
  end;
  // 天井の下面は当たり判定と同じ保存座標。段差の縦面も描く。
  for I:=0 to High(P.Ceilings) do begin
    Floor:=P.Ceilings[I];Bounds:=Floor.CeilingBoundsAt(T);A:=Bounds.Left;B:=Bounds.Right;Y:=Bounds.Bottom;
    if (B<L-1) or (A>L+VW+1) then Continue;
    RockTop:=Top+0.5;
    if Floor.Motion=pmGoalWall then RockTop:=Min(RockTop,Bounds.Top);
    if (T>=P.GoalTime) and P.GoalLift(Lift) then RockTop:=Min(RockTop,Lift.Y+Lift.DY);
    Bar(A,Y,B,RockTop,CaveCeiling);Bar(A,Y,B,Min(Y+0.10,RockTop),CaveCeilingEdge);
    if (I>0) and (Abs(P.Ceilings[I-1].Right-A)<1E-8) then
      Line(A,P.Ceilings[I-1].CeilingBoundsAt(T).Bottom,A,Y,0.06,Edge);
    for J:=Ceil(A/0.9) to System.Math.Floor(B/0.9) do begin
      X:=J*0.9;Line(X,Y+0.18,Min(X+0.15,B),Y+0.37,0.025,BG);
    end;
    for J:=Ceil(A/1.5) to System.Math.Floor((B-0.9)/1.5) do begin
      X:=J*1.5;
      Quad(TrapPoint(X,Y+0.35),TrapPoint(X+0.75,Y+0.55),TrapPoint(X+0.9,Y+1.4),
        TrapPoint(X+0.25,Y+1.15),$00907B68);
      Line(X,Y+0.35,X+0.75,Y+0.55,0.025,$00BDA893);
    end;
    // 通常の天井と同じ岩肌のまま下降する。作動後だけ地層から石片がこぼれる。
    if (Floor.Motion=pmRoofDrop) and (T>Floor.Trigger) and (T<Floor.Trigger+0.35) then begin
      Age:=T-Floor.Trigger;
      for J:=0 to 2 do begin
        X:=A+(B-A)*(J+0.5)/3;
        Bar(X-0.025,Y-0.10-Age*Age*8,X+0.025,Y-0.025-Age*Age*8,$0093AFC9);
      end;
    end;
  end;
end;
procedure TPainter.Traps;
var I,J,N:Integer;Q:TTrapObstacle;B,Core:TTrapBox;Y,W,H,X,A,Roof,Visible,NeedleReach,CoreWidth,Age:Double;C:TColor;
begin
  for I:=0 to High(P.Obstacles) do begin
    Q:=P.Obstacles[I];
    // 穴と崩れる床はTerrainの実タイルだけで描く。後方への無関係な落下物を作らない。
    if TrapHarmless(Q.Kind) then Continue;
    B:=Q.BoundsAt(T);if (B.Right<L-1) or (B.Left>L+VW+1) then Continue;
    Y:=B.Bottom;W:=B.Right-B.Left;H:=B.Top-B.Bottom;
    C:=$005459FA;
    case Q.Kind of
      tkSpearMount:begin
        Bar(B.Left,Y,B.Right,B.Top,Stone);Bar(B.Left+0.035,Y+0.08,B.Right-0.035,B.Top-0.08,$00647386);
        Bar(B.Left-0.015,Y+0.36,B.Right+0.015,Y+0.64,$00242C3C);
        Dot(Q.X,Y+0.15,0.035,$00C4D3E1);Dot(Q.X,B.Top-0.05,0.025,$00C4D3E1);
      end;
      tkSideSpear:begin
        // 槍の根元は固定、先端と軸の実長だけが伸びる。左右を同じ接触矩形で描く。
        if W>0.001 then begin
          X:=Q.X+Q.Power*W;A:=Min(0.42,W);
          Bar(Min(Q.X,X-Q.Power*A),Y+H*0.30,Max(Q.X,X-Q.Power*A),Y+H*0.70,$00BDB7AA);
          Line(Q.X,Y+H*0.50,X-Q.Power*A,Y+H*0.50,0.025,$00F4F2E9);
          Spike(X-Q.Power*A,Y+H*0.50,H,A,False,Q.Power);
        end;
      end;
      tkPress,tkClosingDoor:begin
        Roof:=Q.Y+Q.Travel+Q.H;
        Line(B.Left-0.05,Q.Y,B.Left-0.05,Roof,0.035,$004D5662);
        Line(B.Right+0.05,Q.Y,B.Right+0.05,Roof,0.035,$004D5662);
        Bar(Q.X-0.10,B.Top,Q.X+0.10,Roof,$0096A9B5);
        Bar(B.Left-0.12,Roof,B.Right+0.12,Roof+0.12,$005B6B7A);
        Bar(B.Left,Y,B.Right,B.Top,$002D374B);Bar(B.Left+0.06,Y+0.09,B.Right-0.06,B.Top-0.07,$00748191);
        N:=Max(2,Ceil(H/0.30));
        for J:=0 to N-1 do begin A:=Y+(J+0.5)*H/N;
          Line(B.Left+0.07,A,B.Right-0.07,A,0.025,$00A4B3C7);end;
        C:=$004A59ED;if Q.Kind=tkPress then C:=$005ABBEA;
        Bar(B.Left,Y,B.Right,Y+0.14,C);
        for J:=0 to 3 do begin X:=B.Left+W*(J+0.5)/4;
          Line(X-0.05,Y+0.02,X+0.02,Y+0.12,0.025,$002D374B);end;
        Age:=T-Q.Cue;
        if (Age>=0) and (Age<0.18) then for J:=0 to 5 do begin
          X:=Q.X+(J-2.5)*(0.15+Age*2);
          Bar(X-0.025,Q.Y+0.02+Age*(0.3+(J mod 2)),X+0.025,Q.Y+0.07+Age*(0.3+(J mod 2)),Edge);
        end;
      end;
      tkCeilingNeedles:begin
        N:=Max(2,Ceil(W/0.22));
        for J:=0 to N-1 do Spike(B.Left+W*(J+0.5)/N,Y,W/N,H,True);
        Bar(B.Left-0.04,B.Top,B.Right+0.04,B.Top+0.07,$00283143);
        Line(B.Left,B.Top-0.01,B.Right,B.Top-0.01,0.04,$004A59ED);
      end;
      tkFireJet:begin
        // 噴出口は常設。炎の色面は当たり判定の幅・高さの内側へ収める。
        Bar(B.Left-0.06,Q.Y-0.09,B.Right+0.06,Q.Y,$003F4C62);
        Bar(B.Left,Q.Y-0.055,B.Right,Q.Y-0.015,$00202A35);
        C:=$006B7C8C;
        if ((T>=Q.Fire-0.20) or ((Q.Reveal>0) and (T>=Q.Reveal))) and (T<Q.Finish) then C:=$004775FF;
        Line(B.Left,Q.Y,B.Right,Q.Y,0.045,C);
        if H>0.005 then begin
          for J:=0 to 4 do begin
            X:=B.Left+W*(J+0.5)/5;A:=H*(0.72+0.28*Sin(T*13+J*1.7)*Sin(T*13+J*1.7));
            if J=2 then A:=H;
            Quad(TrapPoint(Max(B.Left,X-W*0.17),Y),TrapPoint(X,Y+A),
              TrapPoint(Min(B.Right,X+W*0.17),Y),TrapPoint(Max(B.Left,X-W*0.17),Y),$002C69FF);
          end;
          Quad(TrapPoint(B.Left+W*0.15,Y),TrapPoint(Q.X,Y+H*0.75),
            TrapPoint(B.Right-W*0.15,Y),TrapPoint(B.Left+W*0.15,Y),$004DCFFF);
          Quad(TrapPoint(B.Left+W*0.32,Y),TrapPoint(Q.X,Y+H*0.42),
            TrapPoint(B.Right-W*0.32,Y),TrapPoint(B.Left+W*0.32,Y),$00C5F7FF);
        end;
      end;
      tkSpikes,tkHiddenSpikes:begin
        // 先端と歩行面の間に落差を残し、待機中も穴底から1ブロックの銀の針を見せる。
        if H>0.001 then begin
          N:=Max(2,Ceil(W/0.22));
          for J:=0 to N-1 do begin
            Spike(B.Left+W*(J+0.5)/N,Y,W/N,H,False);
          end;
        end;
        Bar(B.Left-0.04,Y-0.07,B.Right+0.04,Y,$00283143);
        Line(B.Left,Y+0.01,B.Right,Y+0.01,0.04,C);
      end;
      tkCeiling:begin
        Roof:=Q.Y+Q.Travel+Q.H*(1-Q.Embed);Visible:=Min(H,Max(0.0,Roof-Y));
        N:=Max(1,Ceil(W/0.23));
        for J:=0 to N-1 do begin
          Spike(B.Left+W*(J+0.5)/N,Y,W/N*Visible/H,Visible,True);
        end;
        Line(B.Left,Y+Visible,B.Right,Y+Visible,0.045,$00637591);
        if (T>=Q.Cue) and (T<Q.Cue+0.10) then
          Line(Q.X-0.25,Q.Y+0.02,Q.X+0.25,Q.Y+0.02,0.05,Glow);
      end;
      tkRock:begin
        Roof:=Q.Y+Q.Travel+Q.H*(1-Q.Embed);H:=Min(H,Max(0.0,Roof-Y));
        Quad(TrapPoint(B.Left,Y+H*0.20),TrapPoint(B.Left+W*0.16,Y+H),
          TrapPoint(B.Right-W*0.12,Y+H),TrapPoint(B.Right,Y+H*0.18),$00565B71);
        Bar(B.Left+W*0.15,Y,B.Right-W*0.12,Y+H*0.73,$00565B71);
        Line(B.Left+W*0.16,Y+H,B.Right-W*0.12,Y+H,0.06,$00C2CFED);
        Line(B.Left+W*0.23,Y+H*0.73,B.Right-W*0.23,Y+H*0.22,0.075,C);
        Line(B.Left+W*0.23,Y+H*0.22,B.Right-W*0.23,Y+H*0.73,0.075,C);
        if (T>=Q.Cue) and (T<Q.Cue+0.15) then
          Line(Q.X-0.40,Q.Y+0.02,Q.X+0.40,Q.Y+0.02,0.07,$00D6DDF5);
      end;
      tkWall:begin
        if H<0.04 then Continue;
        // 針先を共有の危険矩形の先端へ合わせ、逃げ場・接触限界と見た目を一致させる。
        NeedleReach:=Min(0.26,W*0.5);Core:=B;
        if Q.Power>0 then Core.Right:=Core.Right-NeedleReach else Core.Left:=Core.Left+NeedleReach;
        CoreWidth:=Core.Right-Core.Left;
        // 片壁のレールと固定部は、くぼみへ入る前から存在する。
        Line(Min(Q.X,Q.X+Q.Power*Q.Travel)-W*0.5,Y-0.035,
          Max(Q.X,Q.X+Q.Power*Q.Travel)+W*0.5,Y-0.035,0.07,$00A4B3C7);
        Bar(Q.X-W*0.45,Y-0.12,Q.X+W*0.45,Y-0.03,$00434D60);
        X:=P.Moves[Q.Move].Origin.X;
        Bar(X-0.33,Y-0.055,X+0.33,Y+0.025,$003F4C62);
        C:=$008B9EAD;if (T>=Q.Fire) and (T<Q.Finish) then C:=$003F8FFF;
        Bar(X-0.24,Y-0.015,X+0.24,Y+0.035,C);
        Bar(Core.Left,Y,Core.Right,Y+H,$002D374B);
        Bar(Core.Left+0.07,Y+0.04,Core.Right-0.07,Y+H-0.04,$00748191);
        Bar(Core.Left+CoreWidth*0.22,Y+0.08,Core.Left+CoreWidth*0.39,Y+H-0.08,$00C4D3E1);
        if H>0.24 then for J:=0 to 6 do begin
          A:=Y+0.12+J*(H-0.24)/6;Dot((Core.Left+Core.Right)*0.5,A,0.045,$002C3447);
          Line(Core.Left+0.06,A,Core.Right-0.06,A+0.10,0.025,$004C5D73);
        end;
        X:=Core.Left;if Q.Power>0 then X:=Core.Right;
        Line(X,Y+0.02,X,Y+H-0.02,0.045,$004A59ED);
        // 床・天井と同じ銀色の針を接近側へ向け、待機・前進・保持・復帰で壁と一緒に動かす。
        N:=Max(3,Ceil(H/0.24));A:=H/N;
        for J:=0 to N-1 do Spike(X,Y+(J+0.5)*A,A*0.88,NeedleReach,False,Q.Power);
      end;
      tkBlade:begin
        // 旧保存IDは維持。丸い飾りに見える刃を、同じ接触範囲の鋭い金属の針束へ置き換える。
        Line(Q.X-Q.Travel-W*0.5,Y-0.035,Q.X+Q.Travel+W*0.5,Y-0.035,0.045,$00647386);
        Bar(B.Left,Y-0.025,B.Right,Y+0.045,$00283143);
        N:=Max(2,Ceil(W/0.18));
        for J:=0 to N-1 do begin
          X:=B.Left+W*(J+0.5)/N;
          A:=H;if (J=0) or (J=N-1) then A:=H*0.88;
          Spike(X,Y,W/N,A,False);
        end;
        Line(B.Left,Y+0.025,B.Right,Y+0.025,0.025,$004A59ED);
      end;
    end;
  end;
end;
procedure TPainter.Hero;
var M,E:TTrapMove;V,Q:TTrapPoint;Lift:TTrapPlatform;H,U,Swing,Lean,Age,At,LiftA,LiftB,Face:Double;
  I,J,N:Integer;C:TColor;Celebrate:Boolean;
begin
  I:=P.MoveAt(T);M:=P.Moves[I];V:=P.Position(T);H:=M.HeightAt(T);U:=M.Progress(T);
  Face:=P.Facing(T);Swing:=Sin(M.StepPhase(T))*0.22*Cos((I mod 2)*Pi);Lean:=0.04*Face;
  Celebrate:=(P.SurfaceTime>0) and (T>=P.SurfaceTime);
  LiftA:=M.FootLift(T,I mod 2);LiftB:=M.FootLift(T,(I+1) mod 2);
  if M.Kind in [tmJump,tmHeadBump,tmVault] then begin
    Swing:=Sin(U*Pi)*0.13;Lean:=0.07*Face;LiftA:=Sin(U*Pi)*0.13;LiftB:=LiftA;
  end;
  if M.Kind=tmRide then begin Swing:=0;Lean:=0;LiftA:=0;LiftB:=0;end;
  if (M.Kind=tmStop) or Celebrate then begin Swing:=0;Lean:=0;LiftA:=0;LiftB:=0;end;
  if (T>=P.GoalTime) and P.GoalLift(Lift) then begin
    Swing:=0;Lean:=0;LiftA:=0;LiftB:=0;
    if T<Lift.Trigger then begin
      U:=EnsureRange((T-P.GoalTime)/(Lift.Trigger-P.GoalTime),0.0,1.0);At:=U*4*Pi;
      Swing:=Sin(At)*0.22;LiftA:=Max(0.0,Sin(At))*0.18;LiftB:=Max(0.0,-Sin(At))*0.18;Lean:=0.04;
    end;
  end;
  C:=$00F4D153;
  Limb(V.X-0.12+Swing,V.Y+0.05+LiftA,V.X-0.08,V.Y+H*0.37,0.10,$00B79047);
  Limb(V.X+0.12-Swing,V.Y+0.05+LiftB,V.X+0.08,V.Y+H*0.37,0.10,$00F1EEE1);
  Limb(V.X,V.Y+H*0.35,V.X+Lean,V.Y+H*0.74,0.20,C);
  if Celebrate then begin
    Limb(V.X,V.Y+H*0.64,V.X-0.25,V.Y+H*0.96,0.08,C);
    Limb(V.X+0.08,V.Y+H*0.64,V.X+0.27,V.Y+H*0.96,0.08,C);
  end else begin
    Limb(V.X-0.04*Face,V.Y+H*0.68,V.X-(0.23+Swing*0.35)*Face,V.Y+H*0.48,0.08,C);
    Limb(V.X+0.10*Face,V.Y+H*0.68,V.X+0.27*Face,V.Y+H*0.48+Swing,0.08,C);
  end;
  Dot(V.X+Lean,V.Y+H*0.85,0.19,$00150F0C);
  Dot(V.X+Lean,V.Y+H*0.85,0.16,$00DAEEFF);
  Dot(V.X+Lean+0.075*Face,V.Y+H*0.87,0.028,BG);
  if (M.Kind=tmHeadBump) and (T>=M.Cue) and (T<M.Cue+0.14) then begin
    Q:=M.Position(M.Cue);Age:=1-(T-M.Cue)/0.14;
    for J:=0 to 4 do begin
      At:=J*2*Pi/5;
      Line(Q.X+Cos(At)*0.06,Q.Y+H+Sin(At)*0.06,
        Q.X+Cos(At)*(0.10+Age*0.14),Q.Y+H+Sin(At)*(0.10+Age*0.14),0.028,$00D7F5FF);
    end;
  end;
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
var Lift:TTrapPlatform;Ground:Double;
begin
  if (T<P.GoalTime) or not P.GoalLift(Lift) then Exit;
  Ground:=Lift.Y+Lift.DY;
  Bar(L-1,Ground-0.12,Lift.Left-0.70,Ground+0.04,$0078CF6A);
  Bar(Lift.Right+0.70,Ground-0.12,L+VW+1,Ground+0.04,$0078CF6A);
  if not F.BackgroundOnly then DrawGoalFireworks(S,F.Width,F.Height,F.Time-Lift.Settle);
end;
procedure TPainter.Setup;
var Lift:TTrapPlatform;
begin
  if (F.Width<=0) or (F.Height<=0) then Exit;
  T:=EnsureRange(F.Time,0.0,P.EndTime);
  // 倍率と上下の視点は固定。床と天井の段差やジャンプで画角を揺らさない。
  K:=Min(F.Width/18.0,F.Height/8.0);VW:=F.Width/K;
  L:=P.CameraLeft(T,VW);Top:=F.Height/K*0.74;
  // 横の構図は乗る前に固定済み。上昇中は上下だけを板へ追従させる。
  if (T>=P.GoalTime) and P.GoalLift(Lift) then Top:=Top+Lift.OffsetAt(T).Y;
  BG:=Palettes[P.Theme,0];Stone:=Palettes[P.Theme,1];Edge:=Palettes[P.Theme,2];Glow:=Palettes[P.Theme,3];
end;
procedure TPainter.Paint;
begin
  if (F.Width<=0) or (F.Height<=0) then Exit;
  Setup;Backdrop;SurfaceBackdrop;Terrain;Traps;Finish;if not F.BackgroundOnly then Hero;
end;
procedure DrawTrapAction(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
var Painter:TPainter;
begin Painter.S:=Surface;Painter.P:=Plan;Painter.F:=Frame;Painter.Paint;end;
procedure DrawTrapBackdrop(Surface:TAnimationRenderSurface;Plan:TTrapPlan;const Frame:TAnimationFrame);
var Painter:TPainter;
begin Painter.S:=Surface;Painter.P:=Plan;Painter.F:=Frame;Painter.Setup;Painter.Backdrop;Painter.SurfaceBackdrop;end;
end.
