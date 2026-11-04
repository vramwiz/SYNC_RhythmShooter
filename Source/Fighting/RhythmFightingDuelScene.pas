unit RhythmFightingDuelScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmFightingDuel,RhythmRenderSurface;
procedure DrawFightingDuel(Plan:TFightingDuel;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer;BackgroundOnly:Boolean=False);
implementation
uses System.Math,System.SysUtils,Winapi.Windows,Vcl.Graphics;

function Blend(A,B:TColor;U:Double):TColor;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
end;

procedure DrawFightingDuel(Plan:TFightingDuel;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer;BackgroundOnly:Boolean);
var
  Scale,Left,Top,Clock,CX,CY,Zoom,X,Y,Age,U,A,Health:Double;
  I,J,First,Last,Theme:Integer;
  Hero,Boss,Enemy:TDuelPose;
  S:TDuelSection;
  H:TDuelHit;
  E:TDuelEnemy;
  Strike:TDuelStrike;
  Tint,Background:TColor;
  function PX(X:Double):Double;
  begin Result:=Left+((X-CX)*Zoom+0.8)*Scale;
  end;
  function PY(Y:Double):Double;
  begin Result:=Top+((Y-CY)*Zoom+0.66)*Scale;
  end;
  procedure Line(X1,Y1,X2,Y2:Double;C:TColor;W:Double);
  begin Surface.Line(PX(X1),PY(Y1),PX(X2),PY(Y2),C,Max(1,W*Scale*Zoom));
  end;
  procedure Box(X1,Y1,X2,Y2:Double;C:TColor);
  begin Surface.FillRect(PX(X1),PY(Y1),PX(X2),PY(Y2),C);
  end;
  procedure Dot(X,Y,R:Double;C:TColor;Filled:Boolean=True);
  begin Surface.Circle(PX(X),PY(Y),R*Scale*Zoom,C,Filled,Max(1,0.002*Scale*Zoom));
  end;
  procedure HUD(X1,Y1,X2,Y2:Double;C:TColor);
  begin Surface.FillRect(Left+X1*Scale,Top+Y1*Scale,Left+X2*Scale,Top+Y2*Scale,C);
  end;
  function ThemeColor(N:Integer):TColor;
  begin case N mod 4 of 0:Result:=RGB(20,31,55);
      1:Result:=RGB(67,37,44);
      2:Result:=RGB(17,48,54);
      else Result:=RGB(43,29,66);
    end;
  end;
  procedure Limb(X1,Y1,X2,Y2:Double;C:TColor;W:Double;Bend:Double);
  var
    MX,MY:Double;
  begin MX:=(X1+X2)/2+Bend;
    MY:=(Y1+Y2)/2-0.012;
    Line(X1,Y1,MX,MY,C,W);
    Dot(MX,MY,W*0.48,C);
    Line(MX,MY,X2,Y2,C,W);
  end;
  procedure Person(P:TDuelPose;C:TColor;Main:Boolean);
  var
    Co,Si,Walk:Double;
    Skin:TColor;
    Kick,Hand:Boolean;
    function TX(AX,AY:Double):Double;
    begin Result:=P.X+(AX*Co-AY*Si)*P.Scale;
    end;
    function TY(AX,AY:Double):Double;
    begin Result:=P.Y-0.10*P.Scale+(AX*Si+AY*Co)*P.Scale;
    end;
    procedure L(AX,AY,BX,BY:Double;Color:TColor;W:Double);
    begin Line(TX(AX,AY),TY(AX,AY),TX(BX,BY),TY(BX,BY),Color,W*P.Scale);
    end;
    procedure O(AX,AY,R:Double;Color:TColor);
    begin Dot(TX(AX,AY),TY(AX,AY),R*P.Scale,Color);
    end;
  begin
    if P.Scale<=0 then Exit;
    Co:=Cos(P.Turn);
    Si:=Sin(P.Turn);
    Skin:=RGB(237,195,159);
    if Main then Skin:=RGB(252,216,176);
    Walk:=0;
    if (S.Mode=0) and (Abs(P.Turn)<0.01) then Walk:=Sin(Clock*DUEL_SPEED/0.065*Pi)*0.018;
    Kick:=(P.Hit>=0) and (P.Kind=1) and (P.Weapon=0) and ((Main and (P.Role in [1,2,5])) or (not Main and (P.Role in [2,3,4])));
    Hand:=(P.Hit>=0) and not Kick and ((Main and (P.Role in [1,2,5])) or (not Main and (P.Role in [2,3,4])));
    if not Kick or (P.Side>0) then begin L(-0.010,0.048,-0.026-Walk,0.094,RGB(46,60,79),0.017);
      L(-0.038-Walk,0.096,-0.015-Walk,0.096,RGB(245,180,124),0.014);
    end;
    if not Kick or (P.Side<0) then begin L(0.010,0.048,0.026+Walk,0.094,RGB(62,96,126),0.017);
      L(0.015+Walk,0.096,0.038+Walk,0.096,RGB(245,180,124),0.014);
    end;
    L(0,0.045,0,-0.020+P.Duck,C,0.058);
    L(-0.024,0.040,0.024,0.040,RGB(231,195,116),0.008);
    if not Hand or (P.Side>0) then begin L(-0.020,-0.006+P.Duck,-0.042,0.027+P.Duck,C,0.017);
      O(-0.043,0.028+P.Duck,0.014,Skin);
    end;
    if not Hand or (P.Side<0) then begin L(0.020,-0.006+P.Duck,0.042,0.027+P.Duck,C,0.017);
      O(0.043,0.028+P.Duck,0.014,Skin);
    end;
    O(0,-0.065+P.Duck,0.045,RGB(65,67,83));
    O(0.003,-0.060+P.Duck,0.040,Skin);
    O(-0.019,-0.086+P.Duck,0.024,RGB(78,79,97));
    O(0.012,-0.087+P.Duck,0.023,RGB(78,79,97));
    if Main then begin
      // One forward eye and a small projecting nose make the side profile clear.
      // Clear only the forelock around this eye; leave a visible skin margin.
      O(P.Side*0.024,-0.062+P.Duck,0.011,Skin);
      O(P.Side*0.024,-0.062+P.Duck,0.007,RGB(255,252,239));
      O(P.Side*0.0255,-0.062+P.Duck,0.0035,RGB(32,40,55));
      L(P.Side*0.035,-0.055+P.Duck,P.Side*0.048,-0.052+P.Duck,Skin,0.008);
      L(P.Side*0.029,-0.038+P.Duck,P.Side*0.036,-0.038+P.Duck,RGB(110,75,72),0.002);
    end else O(P.Side*0.019,-0.061+P.Duck,0.005,RGB(46,50,69));
    L(-0.029,-0.076+P.Duck,0.031,-0.076+P.Duck,RGB(99,194,172),0.007);
    if not Main then begin if P.Kind=2 then L(-0.022,0.004,0.022,0.004,RGB(232,180,103),0.007);
    end;
  end;
  procedure DrawStrike(const W:TDuelStrike;C:TColor);
  var
    Base:TDuelPoint;
    DX,DY,D:Double;
  begin
    Base:=W.Grip;
    DX:=W.Tip.X-Base.X;
    DY:=W.Tip.Y-Base.Y;
    D:=Max(1E-8,Hypot(DX,DY));
    if W.StraightArm then begin
      // One straight shoulder-to-hand segment; every weapon starts at this hand.
      Line(Base.X,Base.Y,W.Hand.X,W.Hand.Y,C,0.024);
      Dot(W.Hand.X,W.Hand.Y,0.011,RGB(237,200,143));
      DX:=W.Tip.X-W.Hand.X;
      DY:=W.Tip.Y-W.Hand.Y;
      D:=Max(1E-8,Hypot(DX,DY));
      if W.Weapon=1 then begin
        Line(W.Hand.X,W.Hand.Y,W.Tip.X-DX/D*0.012,W.Tip.Y-DY/D*0.012,RGB(131,87,57),0.017);
        Line(W.Tip.X-DX/D*0.060,W.Tip.Y-DY/D*0.060,W.Tip.X-DX/D*0.012,W.Tip.Y-DY/D*0.012,RGB(204,158,91),0.024);
        Dot(W.Tip.X-DX/D*0.012,W.Tip.Y-DY/D*0.012,0.012,RGB(204,158,91));
      end else if W.Weapon=2 then begin
        Line(W.Hand.X,W.Hand.Y,W.Tip.X,W.Tip.Y,RGB(227,240,231),0.006);
      end else Dot(W.Tip.X-DX/D*0.014,W.Tip.Y-DY/D*0.014,0.014,RGB(237,200,143));
      Exit;
    end;
    if W.Weapon=1 then begin // club: visible arm + long blunt lever
      Limb(Base.X,Base.Y,Base.X+DX*0.30,Base.Y+DY*0.30,C,0.018,0.012*W.Side);
      Line(Base.X+DX*0.30,Base.Y+DY*0.30,W.Tip.X,W.Tip.Y,RGB(131,87,57),0.017);
      Line(W.Tip.X-DX/D*0.055,W.Tip.Y-DY/D*0.055,W.Tip.X,W.Tip.Y,RGB(204,158,91),0.024);
    end else if W.Weapon=2 then begin // knife: short thrust/slash, different range
      Limb(Base.X,Base.Y,W.Tip.X-DX/D*0.070,W.Tip.Y-DY/D*0.070,C,0.017,-0.014*W.Side);
      Line(W.Tip.X-DX/D*0.075,W.Tip.Y-DY/D*0.075,W.Tip.X,W.Tip.Y,RGB(227,240,231),0.006);
    end else if W.Kind=1 then begin
      Limb(Base.X,Base.Y,W.Tip.X-W.Side*0.017,W.Tip.Y,RGB(62,96,126),0.020,-0.012*W.Side);
      Line(W.Tip.X-W.Side*0.028,W.Tip.Y,W.Tip.X,W.Tip.Y,RGB(245,180,124),0.024);
    end else begin
      Limb(Base.X,Base.Y,W.Tip.X-W.Side*0.014,W.Tip.Y,C,0.018,0.015*W.Side);
      Dot(W.Tip.X-W.Side*0.014,W.Tip.Y,0.014,RGB(237,200,143));
    end;
  end;
begin
  Clock:=EnsureRange(Time,0.0,Plan.EndTime);
  Scale:=Min(Width/1.6,Height);
  Left:=(Width-1.6*Scale)/2;
  Top:=(Height-Scale)/2;
  Plan.CameraAt(Clock,CX,CY,Zoom);
  S:=Plan.Sections[Plan.SectionAt(Clock)];
  Theme:=Plan.ThemeAt(Clock);
  Background:=ThemeColor(Theme);
  for I:=1 to High(Plan.Stages) do if (Clock>=Plan.Stages[I].Time) and (Clock<Plan.Stages[I].Time+0.65) then Background:=Blend(ThemeColor(Plan.Stages[I-1].Theme),Background,(Clock-Plan.Stages[I].Time)/0.65);
  for I:=0 to 31 do Surface.FillRect(0,I*Height/32,Width,(I+1)*Height/32+1,Blend(Background,RGB(56,75,88),I/42));
  First:=Floor((CX-1)/0.16);
  for I:=First to First+18 do begin X:=I*0.16;
    Y:=0.28+0.10*(0.5+0.5*Sin(I*1.71+Theme));
    Box(X,Y,X+0.10,0.61,Blend(Background,RGB(86,110,127),0.23));
    for J:=0 to 3 do Line(X+0.015,Y+0.02+J*0.04,X+0.085,Y+0.02+J*0.04,RGB(112,123,132),0.003);
  end;
  Box(CX-2,DUEL_FLOOR,CX+2,1.6,RGB(36,49,64));
  Line(CX-2,DUEL_FLOOR,CX+2,DUEL_FLOOR,RGB(120,151,162),0.006);
  First:=Floor((CX-1.6)/0.16);
  for I:=First to First+22 do Line(I*0.16,DUEL_FLOOR,I*0.16-0.15,1.05,RGB(61,80,97),0.002);
  if BackgroundOnly then begin Surface.DrawViewportMatte(Left,Top,Width,Height,RGB(9,16,29));Exit;end;
  First:=Max(0,Plan.EnemyBefore(Clock-1)+1);
  Last:=Min(High(Plan.Enemies),Min(Plan.EnemyBefore(Clock+2),First+95));
  for I:=Last downto First do begin E:=Plan.Enemies[I];
    if (Clock<E.Spawn) or (Clock>E.Kill+0.75) then Continue;
    Enemy:=Plan.EnemyAt(I,Clock);
    if Abs(Enemy.X-CX)>1.25 then Continue;
    Tint:=RGB(181,85,82);
    if E.Kind=1 then Tint:=RGB(151,122,86) else if E.Kind=2 then Tint:=RGB(111,114,158);
    Person(Enemy,Tint,False);
  end;
  Boss:=Plan.BossAt(Clock);
  if S.Mode=1 then begin Person(Boss,RGB(138,99,162),False);
    Health:=Plan.HealthAt(Clock);
    HUD(0.44,0.045,1.18,0.075,RGB(8,13,26));
    HUD(0.445,0.050,0.445+0.73*Health,0.070,RGB(211,151,234));
    // Weapon is visible even while held; strike rendering replaces its reach.
    if (Clock<S.Kill) and not Plan.EnemyStrike(Clock,Strike) then begin if S.Style=1 then Line(Boss.X+Boss.Side*0.043*Boss.Scale,Boss.Y-0.072*Boss.Scale,Boss.X+Boss.Side*(0.043*Boss.Scale+0.04),Boss.Y-0.072*Boss.Scale-0.22,RGB(173,127,78),0.016) else if S.Style=2 then Line(Boss.X+Boss.Side*0.043*Boss.Scale,Boss.Y-0.072*Boss.Scale,Boss.X+Boss.Side*(0.043*Boss.Scale+0.06),Boss.Y-0.072*Boss.Scale-0.01,RGB(225,238,232),0.006);
    end;
  end;
  Hero:=Plan.HeroAt(Clock);
  if Clock<Plan.EndTime then Person(Hero,RGB(71,180,165),True);
  if Plan.HeroStrike(Clock,Strike) then DrawStrike(Strike,RGB(58,154,149));
  if Plan.EnemyStrike(Clock,Strike) then DrawStrike(Strike,RGB(145,94,128));
  Last:=Plan.HitBefore(Clock);
  First:=Max(0,Last-63);
  for I:=Last downto First do begin H:=Plan.Hits[I];
    Age:=Clock-H.Time;
    if Age>0.30 then Break;
    if H.Role=0 then Continue;
    U:=Age/0.30;
    for J:=0 to 7 do begin A:=J*2.39996;
      Line(H.X,H.Y,H.X+Cos(A)*Age*(0.35+H.Strength*0.3),H.Y+Sin(A)*Age*0.25,Blend(RGB(255,229,139),Background,U),0.003*(1-U));
    end;
    if H.Role=5 then begin
      for J:=0 to 2 do if Age>=J*0.045 then Dot(H.X,H.Y,0.02+(Age-J*0.045)*0.70,Blend(RGB(255,221,125),Background,U),False);
      for J:=0 to 13 do begin A:=J*2.39996;
        X:=H.X+Cos(A)*Age*(0.6+0.06*(J mod 4));
        Y:=H.Y+Sin(A)*Age*0.4+Age*Age*0.6;
        Line(X-0.01,Y,X+0.01,Y,Blend(RGB(247,191,107),Background,U),0.012*(1-U));
      end;
      Line(H.X-0.35*Age,DUEL_FLOOR,H.X+0.55*Age,DUEL_FLOOR,RGB(232,189,113),0.008*(1-U));
    end;
  end;
  if Left>0 then begin Surface.FillRect(0,0,Left,Height,RGB(9,16,29));
    Surface.FillRect(Width-Left,0,Width,Height,RGB(9,16,29));
  end;
  if Top>0 then begin Surface.FillRect(0,0,Width,Top,RGB(9,16,29));
    Surface.FillRect(0,Height-Top,Width,Height,RGB(9,16,29));
  end;
end;
end.
