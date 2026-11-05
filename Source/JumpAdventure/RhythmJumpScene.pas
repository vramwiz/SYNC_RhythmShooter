unit RhythmJumpScene;
// 同じ計画をPreviewとホストで描く。背景・カメラ・撃破演出も絶対時刻で復元する。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmJumpPlan;

type
  TJumpAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio; // 共通レンダラーから借用。
    FRef:TRhythmPlanRef;
    FPlan:TJumpPlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;

implementation
uses System.SysUtils,System.Math,System.Types,Vcl.Graphics,Winapi.Windows,RhythmJumpCodec;

type
  TJumpPalette=record
    Sky,Haze,Far,Near,Stone,Edge,Light:TColor;
  end;

  TJumpPainter=record
    Surface:TAnimationRenderSurface;
    Plan:TJumpPlan;
    Time,W,H,Scale,Left,Top:Double;
    Palette:TJumpPalette;
    function Screen(const P:TPointF):TPointF;
    procedure Box(X,Y,Width,Height:Double;Color:TColor);
    procedure Dot(X,Y,R:Double;Color:TColor);
    procedure Stroke(X1,Y1,X2,Y2,Width:Double;Color:TColor);
    procedure Backdrop(CamX,CamY,Climb,Profile:Double);
    procedure Platform(Index:Integer);
    procedure Bridge(Index:Integer);
    procedure Enemy(const P:TPointF;Variant:Integer;Age:Double);
    procedure Boss(Index:Integer);
    procedure Hazard(Index:Integer);
    procedure Pulse(const P:TPointF;Age,Power:Double;Color:TColor);
    procedure ContactDust(const P:TPointF;Age,Power:Double;Color:TColor);
    procedure Actor(const Foot:TPointF;Climb:Double);
    procedure FinishGate;
    procedure Badge(Level:Integer;Climb:Double);
    procedure Draw(const Frame:TAnimationFrame);
  end;

const
  Themes:array[0..4] of TJumpPalette=(
    (Sky:$00371B12;Haze:$0071512C;Far:$00513F26;Near:$005E5031;Stone:$00463D24;Edge:$00A2D163;Light:$00CCF9AE),
    (Sky:$00372827;Haze:$00775D9C;Far:$00624B71;Near:$00605283;Stone:$00553A57;Edge:$008BC9F8;Light:$00B9EBFF),
    (Sky:$0041261C;Haze:$0081543C;Far:$006E4831;Near:$0071583E;Stone:$005D4533;Edge:$00F0D86B;Light:$00FCEAB5),
    (Sky:$00262615;Haze:$004C8062;Far:$003C6042;Near:$003C765C;Stone:$003C5F43;Edge:$0085F1BA;Light:$00BFFFDD),
    (Sky:$00352129;Haze:$006D4079;Far:$00573A66;Near:$00754380;Stone:$00583868;Edge:$00C19CFA;Light:$00F5CAFF)
  );
  Enemies:array[0..3] of TColor=($00677BFA,$00A68FE9,$006BDCFC,$00D4C25F);
  BossColors:array[0..2] of TColor=($006174D5,$00BB69A9,$008EBC60);
  Ink=$00302524;
  White=$00EFFAFF;

function Tint(A,B:TColor;U:Double):TColor;
begin
  Result:=RGB(Round(JumpBlend(GetRValue(A),GetRValue(B),U)),
    Round(JumpBlend(GetGValue(A),GetGValue(B),U)),
    Round(JumpBlend(GetBValue(A),GetBValue(B),U)));
end;

function BlendPalette(const A,B:TJumpPalette;U:Double):TJumpPalette;
begin
  Result.Sky:=Tint(A.Sky,B.Sky,U);
  Result.Haze:=Tint(A.Haze,B.Haze,U);
  Result.Far:=Tint(A.Far,B.Far,U);
  Result.Near:=Tint(A.Near,B.Near,U);
  Result.Stone:=Tint(A.Stone,B.Stone,U);
  Result.Edge:=Tint(A.Edge,B.Edge,U);
  Result.Light:=Tint(A.Light,B.Light,U);
end;

function Smooth(U:Double):Double;
begin
  U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function Wrap(Value,Period:Double):Double;
begin
  Result:=Value-Floor(Value/Period)*Period;
end;

function TJumpPainter.Screen(const P:TPointF):TPointF;
begin
  Result:=PointF((P.X-Left)*Scale,(Top-P.Y)*Scale);
end;

procedure TJumpPainter.Box(X,Y,Width,Height:Double;Color:TColor);
var P:TPointF;
begin
  P:=Screen(PointF(X,Y));
  Surface.FillRect(P.X,P.Y,P.X+Width*Scale,P.Y+Height*Scale,Color);
end;

procedure TJumpPainter.Dot(X,Y,R:Double;Color:TColor);
var P:TPointF;
begin
  P:=Screen(PointF(X,Y));
  Surface.Circle(P.X,P.Y,R*Scale,Color,True);
end;

procedure TJumpPainter.Stroke(X1,Y1,X2,Y2,Width:Double;Color:TColor);
var A,B:TPointF;
begin
  A:=Screen(PointF(X1,Y1));
  B:=Screen(PointF(X2,Y2));
  Surface.Line(A.X,A.Y,B.X,B.Y,Color,Max(1.0,Width*Scale));
end;

procedure TJumpPainter.Backdrop(CamX,CamY,Climb,Profile:Double);
var
  I,J,Layer:Integer;
  X,Y,R,Cell,Shift,Lift,Roof,Width,Cloud:Double;
  C:TColor;
  A,B,D,E:TPointF;
begin
  for I:=0 to 15 do
    Surface.FillRect(0,H*I/16,W,H*(I+1)/16+1,Tint(Palette.Sky,Palette.Haze,I/18));
  Lift:=Sin(CamY*0.06)*H*0.075;
  X:=W*0.75+Sin(CamX*0.027)*W*0.10;
  Y:=H*(0.27-0.07*Climb)+Lift;
  R:=Min(W,H)*0.105;
  Surface.Circle(X,Y,R*1.22,Tint(Palette.Sky,Palette.Haze,0.57),True);
  Surface.Circle(X,Y,R,Tint(Palette.Haze,Palette.Light,0.52),True);
  for I:=0 to 31 do begin
    X:=Wrap(I*173.13-CamX*Scale*0.066,W+90)-45;
    Y:=Wrap(I*89.27+CamY*Scale*0.082,H+40)-20;
    Surface.Circle(X,Y,1+(I mod 3)*0.58,Tint(Palette.Haze,Palette.Light,0.62),True);
  end;
  Cloud:=Min(W,H)*0.12;
  for I:=-1 to 6 do begin
    X:=Wrap(I*W*0.217-CamX*Scale*0.10,W+Cloud*3)-Cloud;
    Y:=H*(0.34+0.11*Sin(I*2.7))+Sin(CamY*0.065+I)*H*0.10*Climb;
    C:=Tint(Palette.Sky,Palette.Haze,0.31);
    Surface.FillRect(X-Cloud,Y-Cloud*0.02,X+Cloud*0.49,Y+Cloud*0.17,C);
    Surface.FillRect(X-Cloud*0.66,Y-Cloud*0.17,X+Cloud*0.23,Y+Cloud*0.17,C);
    Surface.FillRect(X-Cloud*0.38,Y-Cloud*0.27,X+Cloud*0.02,Y-Cloud*0.14,C);
  end;
  for Layer:=0 to 1 do begin
    Cell:=Scale*(3.8+Layer*1.9);
    Shift:=CamX*Scale*(0.15+Layer*0.14);
    Lift:=CamY*Scale*(0.10+Layer*0.12);
    if Layer=0 then C:=Palette.Far else C:=Palette.Near;
    for I:=-1 to Ceil(W/Cell)+1 do begin
      J:=I+Floor(Shift/Cell);
      X:=I*Cell-Wrap(Shift,Cell);
      R:=Cell*(0.62+0.33*Sin(J*3.11+Layer*2));
      Y:=H*(0.90+Layer*0.11)-R+Sin(Lift/(H+1))*H*0.26*Climb;
      A:=PointF(X-Cell*0.31,H+1);
      Roof:=Profile*(0.17+0.20*Sin(J*1.84+1));
      B:=PointF(X+Cell*(0.17+Roof*0.32),Y+R*(0.20-Roof*0.44));
      D:=PointF(X+Cell*(0.48+Roof*0.61),Y);
      E:=PointF(X+Cell*1.10,H+1);
      Surface.FillQuad(A,B,D,E,C);
      Surface.FillQuad(D,PointF(X+Cell*0.72,Y+R*0.54),E,
        PointF(X+Cell*0.48,H+1),Tint(C,Palette.Sky,0.22));
      Width:=Cell*Max(0.0,Profile-0.42)*0.065;
      if Width>0.6 then Surface.FillRect(D.X-Width*2,D.Y+R*0.35,D.X-Width,D.Y+R*0.56,Tint(C,Palette.Light,0.28));
    end;
  end;
end;

procedure TJumpPainter.Bridge(Index:Integer);
var A,B:TJumpNode; TopY:Double; Stage:TJumpStage;
begin
  A:=Plan.Nodes[Index];
  B:=Plan.Nodes[Index+1];
  Stage:=Plan.Stages[Plan.StageAt((A.Time+B.Time)*0.5)];
  if Stage.Vertical or (B.X<=A.X) or ((Stage.Level<>1) and (Plan.Legs[Index].Height>0)) then Exit;
  TopY:=A.Y;
  if Plan.Legs[Index].Height>0 then TopY:=Min(A.Y,B.Y)-0.42;
  Box(A.X,TopY,B.X-A.X,0.41,Palette.Stone);
  Box(A.X,TopY,B.X-A.X,0.075,Palette.Edge);
end;

procedure TJumpPainter.Platform(Index:Integer);
var N:TJumpNode; P:TPointF; X,Ready:Double; C,Deck:TColor;
begin
  N:=Plan.Nodes[Index];
  P:=Plan.Platform(Index,Time);
  if (P.X<Left-2) or (P.X>Left+W/Scale+2) or (P.Y>Top+2) or (P.Y<Top-H/Scale-2) then Exit;
  X:=P.X-N.Width*0.5;
  C:=Palette.Edge;
  if (N.MoveX<>0) or (N.MoveY<>0) then begin
    C:=$00E8BD64;
    if N.MoveX<>0 then Stroke(N.X-N.MoveX*2,P.Y-0.15,N.X+N.MoveX*2,P.Y-0.15,0.05,$00A47B47);
    if N.MoveY<>0 then Stroke(P.X,N.Y-N.MoveY*2-0.16,P.X,N.Y+N.MoveY*2-0.16,0.05,$00A47B47);
  end;
  Ready:=1;
  if N.SolidFrom>0 then Ready:=Smooth((Time-N.SolidFrom+0.11)/0.14);
  if N.SolidUntil<Plan.Duration then Ready:=Min(Ready,Smooth((N.SolidUntil-Time+0.11)/0.14));
  C:=Tint(Palette.Far,C,0.25+0.75*Ready);
  Deck:=Tint(Palette.Far,Palette.Stone,0.22+0.78*Ready);
  Box(X-0.035,P.Y+0.015,N.Width+0.07,0.29,Tint(Palette.Far,Ink,Ready));
  Box(X,P.Y,N.Width,0.23,Deck);
  Box(X,P.Y,N.Width,0.075,C);
  Dot(X+0.12,P.Y-0.15,0.028,C);
  Dot(X+N.Width-0.12,P.Y-0.15,0.028,C);
  if N.Landing=jlSpring then begin
    Stroke(P.X-0.19,P.Y-0.21,P.X+0.16,P.Y-0.13,0.055,White);
    Stroke(P.X+0.16,P.Y-0.13,P.X-0.15,P.Y-0.04,0.055,White);
    Box(P.X-0.24,P.Y,0.48,0.063,$0074EDFD);
  end;
end;

procedure TJumpPainter.Enemy(const P:TPointF;Variant:Integer;Age:Double);
var X,Y,U,R:Double; C:TColor;
begin
  X:=P.X;
  Y:=P.Y;
  C:=Enemies[Variant];
  R:=0.23;
  if Age>=0 then begin
    U:=Age/0.33;
    if U>=1 then Exit;
    case Variant of
      0:Box(X-R*(1+U),Y-0.21,R*2*(1+U),0.10*(1-U),C);
      1:Dot(X+U*0.52,Y+0.58*U*(1-U)-0.20,R*0.61*(1-U),C);
      2:begin
        Dot(X-R-U*0.21,Y+0.13*U-0.16,R*(1-U)*0.57,C);
        Dot(X+R+U*0.21,Y+0.21*U-0.16,R*(1-U)*0.57,White);
      end;
      3:ContactDust(P,Age,0.65,C);
    end;
    Exit;
  end;
  Dot(X,Y-R,R,Ink);
  Dot(X,Y-R*0.98,R*0.84,C);
  if Variant in [1,3] then begin
    Stroke(X-R*0.44,Y-R*0.62,X-R*1.13,Y-R*0.13,0.065,C);
    Stroke(X+R*0.44,Y-R*0.62,X+R*1.13,Y-R*0.13,0.065,C);
  end else
    Box(X-R,Y-R*1.49,R*2,R*0.62,Tint(C,Ink,0.26));
  Box(X-R*0.49,Y-R*0.58,R*0.27,R*0.39,White);
  Box(X+R*0.18,Y-R*0.58,R*0.27,R*0.39,White);
end;

procedure TJumpPainter.Pulse(const P:TPointF;Age,Power:Double;Color:TColor);
var U,R,X,Y:Double; I:Integer; Q:TPointF;
begin
  U:=Age/(0.23+Power*0.25);
  if (U<0) or (U>=1) then Exit;
  R:=0.08+U*(0.48+Power*0.96);
  Q:=Screen(P);
  Surface.Circle(Q.X,Q.Y,R*Scale,Color,False,Max(1.0,Scale*0.048*(1-U)));
  for I:=0 to 3+Round(Power*3) do begin
    X:=P.X+Cos(I*2.399)*R;
    Y:=P.Y+Sin(I*2.399)*R;
    Dot(X,Y,(1-U)*(0.04+Power*0.05),Tint(Color,White,0.28));
  end;
end;

procedure TJumpPainter.ContactDust(const P:TPointF;Age,Power:Double;Color:TColor);
var U,Spread,Lift:Double; I:Integer;
begin
  U:=Age/0.18;
  if (U<0) or (U>=1) then Exit;
  for I:=-2 to 2 do begin
    Spread:=I*(0.08+U*(0.08+Power*0.04));
    Lift:=0.05+(0.14+Power*0.09)*4*U*(1-U)*(1-Abs(I)*0.23);
    Dot(P.X+Spread,P.Y+Lift,(0.045+Power*0.024)*(1-U),Color);
  end;
end;

procedure TJumpPainter.Boss(Index:Integer);
var
  B:TJumpBoss;
  P,Q,Weak:TPointF;
  C,D:TColor;
  Start,Finish,Age,Fade,Size:Double;
  I,Spot,ActiveSpot:Integer;
begin
  B:=Plan.Bosses[Index];
  Start:=Plan.Nodes[B.FirstNode].Time;
  Finish:=Plan.Nodes[B.LastNode].Time;
  if (Time<Start-0.94) or (Time>Finish+0.87) then Exit;
  P:=Plan.BossCore(Index,Time);
  Age:=Time-Finish;
  Fade:=Smooth((Time-Start+0.94)/0.94);
  if Age>0 then Fade:=1-Smooth(Age/0.73);
  P.Y:=P.Y-(1-Fade)*1.22;
  Size:=1+B.Variant*0.15;
  C:=Tint(Palette.Near,BossColors[B.Variant],Fade);
  D:=Tint(C,Ink,0.46);
  case B.Variant of
    0:begin
      Box(P.X-1.32*Size,P.Y+0.79,2.65*Size,0.76,Ink);
      Box(P.X-1.22*Size,P.Y+0.74,2.44*Size,0.58,C);
      for I:=-1 to 1 do Dot(P.X+I*0.88,P.Y+0.05,0.30,D);
    end;
    1:begin
      Dot(P.X,P.Y+0.37,1.03,C);
      Box(P.X-1.35*Size,P.Y+0.61,2.70*Size,0.27,Ink);
      Stroke(P.X-1.35,P.Y+0.18,P.X-0.37,P.Y-0.42,0.20,D);
      Stroke(P.X+1.30,P.Y+0.18,P.X+0.37,P.Y-0.42,0.20,D);
    end;
    2:begin
      Box(P.X-0.88*Size,P.Y+1.11,1.83*Size,1.38,D);
      Dot(P.X-1.1,P.Y+0.51,0.43,C);
      Dot(P.X+1.13,P.Y+0.58,0.47,C);
      Box(P.X-0.53,P.Y+0.86,1.06,0.61,C);
    end;
  end;
  Box(P.X-0.35,P.Y+0.53,0.70,0.14,Ink);
  Box(P.X+0.02,P.Y+0.51,0.25,0.082,$007BCAFD);
  ActiveSpot:=Plan.Nodes[EnsureRange(Plan.NodeAt(Time)+1,B.FirstNode,B.LastNode)].Variant;
  for Spot:=0 to 2 do begin
    Weak:=JumpWeakPoint(B.Variant,Spot);
    Q:=PointF(P.X+Weak.X,P.Y+Weak.Y);
    Stroke(Q.X,Q.Y-0.20,P.X+Weak.X*0.65,P.Y+0.58,0.095,C);
    Box(Q.X-0.24,Q.Y,0.48,0.15,Ink);
    if Spot=ActiveSpot then Box(Q.X-0.19,Q.Y,0.38,0.06,Tint(C,White,0.82))
    else Box(Q.X-0.19,Q.Y,0.38,0.045,Tint(C,White,0.26));
  end;
  if Age>=0 then begin
    for I:=0 to 3 do begin
      Q:=PointF(P.X+(I-1.5)*0.49,P.Y+0.75+0.19*(I mod 2));
      Pulse(Q,Age-I*0.085,1.25,Enemies[(B.Variant+I) mod 4]);
    end;
  end else begin
    // 弱点を踏んだフレームでだけ残りを減らす。
    Box(P.X-0.74,P.Y+1.87,1.48,0.12,Ink);
    Box(P.X-0.71,P.Y+1.84,1.42*(B.LastNode-EnsureRange(Plan.NodeAt(Time),B.FirstNode-1,B.LastNode))/
      (B.LastNode-B.FirstNode+1),0.060,$008C9DFD);
  end;
end;

procedure TJumpPainter.Hazard(Index:Integer);
var A:TJumpHazard; C:TColor; Y:Double;
begin
  A:=Plan.Hazard(Index);
  if (A.Kind=0) or (Time<A.StartTime-0.27) or (Time>A.EndTime) then Exit;
  Y:=A.Y;
  if Time<A.StartTime then begin
    Dot(A.X-0.36,Y,0.038,$0097B1FB);
    Dot(A.X,Y,0.038,$0097B1FB);
    Dot(A.X+0.36,Y,0.038,$0097B1FB);
    Exit;
  end;
  C:=$006783FD;
  case A.Kind of
    1:begin
      Box(A.X-0.85,Y+A.Height,1.70,A.Height,Ink);
      Box(A.X-0.77,Y+A.Height*0.82,1.54,A.Height*0.64,Tint(C,Ink,0.46));
      Dot(A.X-0.60,Y+A.Height*0.52,A.Height*0.14,C);
      Dot(A.X,Y+A.Height*0.52,A.Height*0.14,C);
      Dot(A.X+0.60,Y+A.Height*0.52,A.Height*0.14,C);
    end;
    2:begin
      Stroke(A.X-0.55,Y,A.X-0.42,Y+A.Height,0.09,C);
      Stroke(A.X-0.42,Y+A.Height,A.X-0.29,Y,0.09,C);
      Stroke(A.X-0.13,Y,A.X,Y+A.Height,0.09,C);
      Stroke(A.X,Y+A.Height,A.X+0.13,Y,0.09,C);
      Stroke(A.X+0.29,Y,A.X+0.42,Y+A.Height,0.09,C);
      Stroke(A.X+0.42,Y+A.Height,A.X+0.55,Y,0.09,C);
    end;
    3:Dot(A.X+(Time-A.StartTime-0.5*(A.EndTime-A.StartTime))*2,
      Y+A.Height*0.5,A.Height*0.5,C);
  end;
end;

procedure TJumpPainter.Actor(const Foot:TPointF;Climb:Double);
var
  X,Y,Stride,Tilt,Height,Direction,Finish,Rest,Crouch,Flight,AirPose,ArmSwing:Double;
  I:Integer;
  Air:Boolean;

  procedure Arm(Front:Boolean);
  var Side,ShoulderX,ShoulderY,ElbowX,ElbowY,HandX,HandY,Lift:Double; Sleeve,Skin:TColor;
  begin
    Side:=2*Ord(Front)-1;
    ShoulderX:=X+Tilt+Direction*Side*0.095;
    ShoulderY:=Y+0.49-Crouch*0.055;
    Lift:=AirPose;
    if Front then Lift:=Max(Lift,Rest*0.78);
    ElbowX:=ShoulderX+Direction*JumpBlend(-0.035+Side*ArmSwing*0.57,Side*0.055,Lift);
    ElbowY:=ShoulderY+JumpBlend(-0.17,-0.16+Ord(Front)*0.035,Lift);
    HandX:=ShoulderX+Direction*JumpBlend(0.05+Side*ArmSwing,0.05+Side*0.12,Lift);
    HandY:=ShoulderY+JumpBlend(-0.24+Abs(ArmSwing)*0.43,-0.235+Ord(Front)*0.12,Lift);
    if Front then begin Sleeve:=$00D4B054; Skin:=$0099DDFE; end
    else begin Sleeve:=$00998545; Skin:=$007BAFDE; end;
    Stroke(ShoulderX,ShoulderY,ElbowX,ElbowY,0.14,Ink);
    Stroke(ElbowX,ElbowY,HandX,HandY,0.125,Ink);
    Stroke(ShoulderX,ShoulderY,ElbowX,ElbowY,0.096,Sleeve);
    Stroke(ElbowX,ElbowY,HandX,HandY,0.083,Skin);
    Dot(HandX,HandY,0.082,Ink);
    Dot(HandX,HandY,0.058,Skin);
  end;

begin
  I:=Plan.NodeAt(Time);
  Finish:=Plan.Nodes[High(Plan.Nodes)].Time;
  Rest:=Smooth((Time-Finish+0.26)/0.26);
  X:=Foot.X;
  Y:=Foot.Y;
  Direction:=1;
  Air:=False;
  Crouch:=0;
  AirPose:=0;
  if I<Length(Plan.Legs) then begin
    if Plan.Nodes[I+1].X<Plan.Nodes[I].X then Direction:=-1;
    Air:=(Plan.Legs[I].Height>0) and (Time>Plan.Legs[I].Takeoff);
    if Air then begin
      Flight:=(Time-Plan.Legs[I].Takeoff)/(Plan.Nodes[I+1].Time-Plan.Legs[I].Takeoff);
      AirPose:=Smooth(Flight/0.20)*(1-Smooth((Flight-0.70)/0.30));
    end else if Plan.Legs[I].Takeoff>Plan.Nodes[I].Time then
      Crouch:=Smooth((Time-Plan.Nodes[I].Time)/(Plan.Legs[I].Takeoff-Plan.Nodes[I].Time));
  end;
  ArmSwing:=Sin(Time*25)*0.24*(1-Rest)*(1-Crouch)*(1-AirPose);
  Stride:=Direction*ArmSwing*0.58;
  if Air then begin
    Stride:=JumpBlend(Stride,Direction*0.13,AirPose);
    if Plan.Nodes[I+1].Landing in [jlStomp,jlBoss] then
      Stride:=Stride*Smooth((Plan.Nodes[I+1].Time-Time)/0.075);
  end;
  if Plan.Nodes[I].Landing in [jlStomp,jlBoss] then
    Stride:=Stride*Smooth((Time-Plan.Nodes[I].Time)/0.075);
  Tilt:=Direction*(0.09-0.04*Climb)*(1-Rest);
  Height:=0.69-0.09*Crouch;
  Arm(False);
  Stroke(X-0.10,Y+0.32,X-0.13+Stride,Y+0.08+0.18*AirPose,0.15,Ink);
  Box(X-0.23+Stride,Y+0.115+0.18*AirPose,0.23,0.085,$00678FB6);
  Stroke(X+0.09,Y+0.31,X-Stride,Y+0.060,0.16,Ink);
  Stroke(X+0.09,Y+0.27,X-Stride,Y+0.10,0.065,$007C7464);
  Box(X-Stride-0.125,Y+0.085,0.25,0.085,$007FBEFA);
  Dot(X+Tilt,Y+0.38-Crouch*0.045,0.22,Ink);
  Dot(X+Tilt,Y+0.40-Crouch*0.045,0.17,$00D4B054);
  Dot(X+Tilt,Y+Height,0.24,Ink);
  Dot(X+Tilt,Y+Height,0.194,$0081CFFD);
  Box(X+Tilt-0.155,Y+Height+0.048,0.31,0.139,$00544634);
  Box(X+Tilt+Direction*0.058-0.04,Y+Height+0.025,0.079,0.045,White);
  Arm(True);
end;

procedure TJumpPainter.FinishGate;
var N:TJumpNode; Light:TColor; X,Y,U:Double;
begin
  N:=Plan.Nodes[High(Plan.Nodes)];
  if Time<N.Time-1.75 then Exit;
  X:=N.X+0.62;
  Y:=N.Y;
  U:=Smooth((Time-N.Time+0.45)/0.45);
  Light:=Tint(Palette.Edge,White,U*0.77);
  Stroke(X,Y,X,Y+1.22,0.056,Light);
  Stroke(X,Y+1.20,X+0.41,Y+1.04+0.03*Sin(Time*12),0.09,Light);
  Stroke(X+0.41,Y+1.04+0.03*Sin(Time*12),X,Y+0.91,0.09,Light);
  Dot(X,Y+1.23,0.065,Light);
  Pulse(PointF(X,Y+1.23),Time-N.Time,0.98,Light);
end;

procedure TJumpPainter.Badge(Level:Integer;Climb:Double);
var U,X,Y:Double; I:Integer; C:TColor;
begin
  U:=Max(2.0,Scale*0.12);
  X:=W*0.048;
  Y:=H*0.07;
  Surface.FillRect(X-U*2,Y-U*2,X+U*13,Y+U*2,Ink);
  Surface.Line(X,Y,X+U*(1-Climb),Y-U*Climb,Palette.Light,U*0.65);
  for I:=1 to 5 do begin
    C:=Tint(Palette.Sky,Palette.Light,0.25);
    if I<=Level then C:=Palette.Light;
    Surface.FillRect(X+U*(2*I+1),Y-U*0.5,X+U*(2*I+2),Y+U*0.5,C);
  end;
end;

procedure TJumpPainter.Draw(const Frame:TAnimationFrame);
var
  I,J,Stage,Other,First,Last,B:Integer;
  U,Climb,Blend,Age,CamX,CamY,Profile:Double;
  Foot,A,C,P:TPointF;
  Beat:TJumpBeat;
  N:TJumpNode;
begin
  W:=Frame.Width;
  H:=Frame.Height;
  Scale:=Min(W/10.6,H/7.8);
  Time:=EnsureRange(Frame.Time,0.0,Plan.Duration);
  Stage:=Plan.StageAt(Time);
  Other:=Stage;
  Blend:=0;
  // 区切りの前後で進行軸と色を連続補間する。ワールド座標は切り替えない。
  if (Stage>0) and (Time<Plan.Stages[Stage].StartTime+0.60) then begin
    Other:=Stage-1;
    Blend:=1-Smooth((Time-Plan.Stages[Stage].StartTime+0.60)/1.20);
  end else if (Stage<High(Plan.Stages)) and (Time>Plan.Stages[Stage+1].StartTime-0.60) then begin
    Other:=Stage+1;
    Blend:=Smooth((Time-Plan.Stages[Other].StartTime+0.60)/1.20);
  end;
  Climb:=JumpBlend(Ord(Plan.Stages[Stage].Vertical),Ord(Plan.Stages[Other].Vertical),Blend);
  Palette:=BlendPalette(Themes[Plan.Stages[Stage].Theme],Themes[Plan.Stages[Other].Theme],Blend);
  Foot:=Plan.Foot(Time);
  A:=Plan.Foot(Max(0.0,Time-0.38));
  C:=Plan.Foot(Min(Plan.Duration,Time+0.43));
  CamX:=0.55*Foot.X+0.25*A.X+0.20*C.X;
  CamY:=0.40*Foot.Y+0.33*A.Y+0.27*C.Y;
  B:=Plan.Stages[Stage].Boss;
  if B>=0 then begin
    U:=Plan.Nodes[Plan.Bosses[B].LastNode].Time;
    if Abs(Time-U)<0.37 then CamX:=CamX+0.092*Sin((Time-U)*91)*(1-Abs(Time-U)/0.37);
  end;
  Left:=CamX-W/Scale*JumpBlend(0.36,0.50,Climb);
  Top:=CamY+H/Scale*JumpBlend(0.60,0.64,Climb);
  Profile:=JumpBlend(Plan.Stages[Stage].Theme,Plan.Stages[Other].Theme,Blend)*0.25;
  Backdrop(CamX,CamY,Climb,Profile);
  if Frame.BackgroundOnly then Exit;
  First:=Max(0,Plan.NodeAt(Time-7)-1);
  Last:=Min(High(Plan.Nodes),Plan.NodeAt(Time+7)+1);
  for I:=First to Min(Last,High(Plan.Legs)) do Bridge(I);
  for I:=First to Last do Platform(I);
  for I:=0 to High(Plan.Bosses) do Boss(I);
  J:=Plan.NodeAt(Time);
  for I:=Max(0,J-1) to Min(High(Plan.Legs),J+2) do Hazard(I);
  I:=Plan.BeatFrom(Time-0.40);
  while I<Length(Plan.Beats) do begin
    Beat:=Plan.Beats[I];
    Age:=Time-Beat.Time;
    if Age< -1.36 then Break;
    if Beat.Node>=0 then begin
      N:=Plan.Nodes[Beat.Node];
      P:=PointF(N.X,N.Y);
      if N.Landing=jlStomp then begin
        if Age<0 then begin
          P:=Plan.Platform(Beat.Node,Time);
          P.Y:=P.Y+0.32;
        end;
        Enemy(P,N.Variant,Age);
      end;
      if Age>=0 then ContactDust(P,Age,0.38+Beat.Strength*0.45,Palette.Light);
    end;
    Inc(I);
  end;
  FinishGate;
  Actor(Foot,Climb);
  Badge(Plan.Stages[Stage].Level,Climb);
end;

destructor TJumpAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TJumpAnimation.SetReference(const Ref:TRhythmPlanRef);
begin
  FRef:=Ref;
end;

procedure TJumpAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try
    FPlan:=LoadJumpPlan(FRef,FAudio,Frame.Direction);
  except
    on E:Exception do FError:=E.Message;
  end;
end;

function TJumpAnimation.Notice:string;
begin
  Result:=FError;
end;

procedure TJumpAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Painter:TJumpPainter;
begin
  if FPlan=nil then Exit;
  Painter.Surface:=Surface;
  Painter.Plan:=FPlan;
  Painter.Draw(Frame);
end;
end.
