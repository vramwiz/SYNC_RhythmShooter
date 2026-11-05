unit RhythmBombScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmBombPlan;
type
  TBombActionAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TBombActionPlan;
    FAttempt,FError:string;
  protected
    // Standard vector actors; narrow hooks allow future shared image-bank skins.
    procedure DrawHero(Surface:TAnimationRenderSurface;X,Y,Scale,Heading,Pose,Impact:Double); virtual;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    property Audio:TRhythmAudio read FAudio write FAudio;
    function GoalTime:Double; override;
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;

function Mix(A,B:TColor;U:Double):TColor;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

destructor TBombActionAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TBombActionAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TBombActionAnimation.Notice:string;
begin Result:=FError;
end;

procedure TBombActionAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity)+'|'+IntToHex(NativeUInt(FAudio),16) else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TBombActionPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TBombActionAnimation.DrawHero(Surface:TAnimationRenderSurface;X,Y,Scale,Heading,Pose,Impact:Double);
var
  D,N:TBAPoint;
  I:Integer;
  P,Q:TBAPoint;
  Squash:Double;
  procedure Circle(const Offset:TBAPoint;R:Double;Color:TColor);
  begin Surface.Circle(X+Offset.X*Scale,Y+Offset.Y*Scale,R*Scale,Color,True);
  end;
begin
  D:=BAV(Cos(Heading),Sin(Heading));
  N:=BANormal(D);
  Squash:=1-0.06*Impact;
  for I:=-1 to 1 do if I<>0 then begin
    P:=BAAdd(BAScale(D,-0.095+0.020*Sin(Pose*26+I)),BAScale(N,I*0.075));
    Circle(P,0.035,RGB(34,60,77));
    P:=BAAdd(BAScale(D,0.005),BAScale(N,I*0.115));
    Q:=BAAdd(BAScale(D,0.065),BAScale(N,I*0.125));
    Surface.Line(X+P.X*Scale,Y+P.Y*Scale,X+Q.X*Scale,Y+Q.Y*Scale,RGB(123,220,223),Max(1,0.035*Scale));
  end;
  Circle(BAV(0.015,0.02),0.120,RGB(18,30,48));
  Circle(BAV(0,0),0.115*Squash,RGB(71,184,206));
  Circle(BAScale(D,0.035),0.080,RGB(209,243,236));
  Circle(BAScale(D,0.068),0.047,RGB(28,67,100));
  Circle(BAAdd(BAScale(D,0.087),BAScale(N,-0.018)),0.012,RGB(255,236,166));
end;

procedure TBombActionAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
const
  Masks:array[0..9] of Byte=($3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F);
var
  Clock,UnitScale,UI,Left,CameraX,CameraY,Age,U,R,Angle,Life,Heading,PoseClock,Impact,Shake,HP,FinishAt,SeedPhase,Hit,PartU:Double;
  I,J,First,Last,HitIndex,PartIndex:Integer;
  Hero,Past,P,Q,D:TBAPoint;
  B:TBABomb;
  Target:TBATarget;
  Boss:TBABoss;
  Shot:TBAShot;
  Charge:TBACharge;
  Foe:TBACrowdEnemy;
  Raid:TBAEnemyShot;
  Color:TColor;
  function Screen(const Point:TBAPoint):TBAPoint;
  begin Result:=BAV((Point.X-CameraX)*UnitScale,Frame.Height/2+(Point.Y-CameraY)*UnitScale);
  end;
  function Visible(const Point:TBAPoint;Radius:Double):Boolean;
  var
    V:TBAPoint;
    R:Double;
  begin V:=Screen(Point);
    R:=Radius*UnitScale;
    Result:=(V.X+R>=0) and (V.X-R<=Frame.Width) and (V.Y+R>=0) and (V.Y-R<=Frame.Height);
  end;
  procedure Circle(const Point:TBAPoint;Radius:Double;Tint:TColor;Fill:Boolean=True;Stroke:Double=0.02);
  var
    V:TBAPoint;
  begin V:=Screen(Point);
    Surface.Circle(V.X,V.Y,Max(0.0,Radius)*UnitScale,Tint,Fill,Max(1,Stroke*UnitScale));
  end;
  procedure Line(const A,C:TBAPoint;Tint:TColor;Stroke:Double=0.025);
  var
    V,W:TBAPoint;
  begin V:=Screen(A);
    W:=Screen(C);
    Surface.Line(V.X,V.Y,W.X,W.Y,Tint,Max(1,Stroke*UnitScale));
  end;
  procedure Box(const Point:TBAPoint;W,H:Double;Tint:TColor);
  var
    V:TBAPoint;
  begin V:=Screen(Point);
    Surface.FillRect(V.X-W*UnitScale,V.Y-H*UnitScale,V.X+W*UnitScale,V.Y+H*UnitScale,Tint);
  end;
  procedure Digit(Value:Integer;X,Y,Size:Double;Tint:TColor);
  var
    M:Byte;
    procedure Seg(A,B,C,D:Double);
    begin Surface.Line(X+A*Size,Y+B*Size,X+C*Size,Y+D*Size,Tint,Max(1,Size*0.12));
    end;
  begin M:=Masks[EnsureRange(Value,0,9)];
    if M and 1<>0 then Seg(0,0,1,0);
    if M and 2<>0 then Seg(1,0,1,1);
    if M and 4<>0 then Seg(1,1,1,2);
    if M and 8<>0 then Seg(0,2,1,2);
    if M and 16<>0 then Seg(0,1,0,2);
    if M and 32<>0 then Seg(0,0,0,1);
    if M and 64<>0 then Seg(0,1,1,1);
  end;
  procedure Number(Value:Integer;X,Y,Size:Double;Tint:TColor);
  var
    Text:string;
    L:Integer;
  begin Text:=IntToStr(Value);
    for L:=1 to Length(Text) do Digit(Ord(Text[L])-Ord('0'),X+(L-1)*Size*1.45,Y,Size,Tint);
  end;
  procedure DrawWord(const Text:string;X,Y,Size:Double;Tint:TColor);
  var
    L:Integer;
    PX:Double;
    procedure Seg(A,B,C,D:Double);
    begin Surface.Line(PX+A*Size,Y+B*Size,PX+C*Size,Y+D*Size,Tint,Max(1,Size*0.10));
    end;
  begin
    for L:=1 to Length(Text) do begin PX:=X+(L-1)*Size*1.5;
      case Text[L] of
        'C','G','O':begin Seg(0,0,1,0);
          Seg(0,0,0,2);
          Seg(0,2,1,2);
          if Text[L]='O' then Seg(1,0,1,2);
          if Text[L]='G' then begin Seg(1,1,1,2);
            Seg(0.5,1,1,1);
          end;
        end;
        'L':begin Seg(0,0,0,2);
          Seg(0,2,1,2);
        end;
        'E':begin Seg(0,0,0,2);
          Seg(0,0,1,0);
          Seg(0,1,0.8,1);
          Seg(0,2,1,2);
        end;
        'A':begin Seg(0,2,0.5,0);
          Seg(0.5,0,1,2);
          Seg(0.25,1.1,0.75,1.1);
        end;
        'R':begin Seg(0,0,0,2);
          Seg(0,0,1,0);
          Seg(1,0,1,1);
          Seg(0,1,1,1);
          Seg(0.4,1,1,2);
        end;
      end;
    end;
  end;
  procedure Spark(const Center:TBAPoint;Radius,Progress:Double;Seed:Integer;Tint:TColor;Count:Integer);
  var
    L:Integer;
    A,V:Double;
    S,T:TBAPoint;
  begin
    for L:=0 to Count-1 do begin A:=L*2.399963+Seed*0.73;
      V:=Radius*(0.30+0.70*Progress);
      S:=BAAdd(Center,BAV(Cos(A)*V,Sin(A)*V));
      T:=BAAdd(Center,BAV(Cos(A)*Min(Radius,V+0.06),Sin(A)*Min(Radius,V+0.06)));
      Line(S,T,Tint,0.014*(1-Progress));
    end;
  end;
  procedure Blast(Index:Integer);
  var
    Bomb:TBABomb;
    Age,F,R,Theta,LastR:Double;
    A,C:TBAPoint;
    L,N:Integer;
    BaseTint,Fire,Edge:TColor;
  begin
    Bomb:=FPlan.Bomb[Index];
    Age:=Clock-Bomb.Time;
    if (Age<0) or (Age>Bomb.Life+0.22) then Exit;
    R:=FPlan.BlastRadius(Index,Clock);
    F:=EnsureRange(Age/(Bomb.Life+0.22),0.0,1.0);
    case Bomb.Pattern of 1:BaseTint:=RGB(243,150,114);
      2:BaseTint:=RGB(88,218,218);
      3:BaseTint:=RGB(175,150,255);
      4:BaseTint:=RGB(255,153,204);
      else BaseTint:=RGB(255,185,91);
    end;
    Fire:=Mix(BaseTint,RGB(36,49,75),F);
    Edge:=Mix(RGB(255,246,192),BaseTint,Min(1.0,Age*6));
    if Age<=Bomb.Life then begin
      case Bomb.Pattern of
        0:begin Circle(Bomb.Position,R,Fire);
          Circle(Bomb.Position,R*(0.72-0.25*F),Mix(RGB(255,245,168),Fire,F));
          Circle(Bomb.Position,R,Edge,False,0.025);
        end;
        1:begin
          for L:=0 to 2 do begin LastR:=R*(0.52+L*0.23);
            A:=BAAdd(Bomb.Position,BAV(Cos(Bomb.Angle-0.65)*LastR,Sin(Bomb.Angle-0.65)*LastR));
            for N:=1 to 24 do begin Theta:=Bomb.Angle-0.65+1.3*N/24;
              C:=BAAdd(Bomb.Position,BAV(Cos(Theta)*LastR,Sin(Theta)*LastR));
              Line(A,C,Fire,0.045);
              A:=C;
            end;
          end;
          for L:=-2 to 2 do begin Theta:=Bomb.Angle+L*0.26;
            Line(Bomb.Position,BAAdd(Bomb.Position,BAV(Cos(Theta)*R,Sin(Theta)*R)),Edge,0.025);
          end;
        end;
        2:begin Circle(Bomb.Position,R,Edge,False,0.035);
          if Bomb.Child<0 then Circle(Bomb.Position,R*0.68,Fire,False,0.045)
          else if R>0.10 then Circle(Bomb.Position,R-0.10,Fire,False,0.035);
        end;
        3:for L:=-1 to 1 do begin Theta:=Bomb.Angle+L*0.35;
          C:=BAAdd(Bomb.Position,BAV(Cos(Theta)*(R-0.04),Sin(Theta)*(R-0.04)));
          Line(Bomb.Position,C,Fire,0.09);
          Line(Bomb.Position,C,Edge,0.025);
        end;
        4:begin A:=Bomb.Position;
          for L:=1 to 40 do begin LastR:=(R-0.04)*L/40;
            Theta:=Bomb.Angle+2*Pi*L/40;
            C:=BAAdd(Bomb.Position,BAV(Cos(Theta)*LastR,Sin(Theta)*LastR));
            Line(A,C,Fire,0.055);
            A:=C;
          end;
        end;
      end;
    end else Circle(Bomb.Position,R*0.64,Mix(BaseTint,RGB(32,43,62),F),False,0.018);
    if Age<0.07 then Circle(Bomb.Position,0.20*(1-Age/0.07),RGB(255,249,213));
    Spark(Bomb.Position,Max(0.0,R-0.03),F,Index,Fire,8+Round(Bomb.Strength*6));
  end;
  procedure DrawBackdrop;
  var
    K,L,N,Cell,Index,FirstBeat,LastBeat:Integer;
    Step,Shift,X,Y,A,Phase,Progress,Pulse,Age,Light:Double;
    Center,EndPoint,Joint:TBAPoint;
    TopTint,BottomTint,PanelTint,TraceTint:TColor;
  begin
    Progress:=0;
    Pulse:=0;
    if FPlan<>nil then begin
      Progress:=Clock/FPlan.EndTime;
      FirstBeat:=FPlan.BombBefore(Clock-0.40)+1;
      LastBeat:=FPlan.BombBefore(Clock);
      for K:=FirstBeat to LastBeat do begin Age:=Clock-FPlan.Bomb[K].Time;
        Pulse:=Max(Pulse,FPlan.Bomb[K].Strength*(1-Age/0.40));
      end;
    end;
    Pulse:=EnsureRange(Pulse,0.0,1.0);
    Phase:=0.5+0.5*Sin(Progress*2*Pi+SeedPhase*0.12);
    TopTint:=Mix(RGB(14,23,49),RGB(31,19,55),Phase);
    BottomTint:=Mix(RGB(17,42,60),RGB(28,31,67),Phase);
    // Only this backmost gradient uses large opaque surfaces.
    for K:=0 to 23 do Surface.FillRect(0,K*Frame.Height/24,Frame.Width,(K+1)*Frame.Height/24+1,Mix(TopTint,BottomTint,K/23));
    // Distant reactor chambers move slower than the foreground machinery.
    Step:=Max(3.8,Frame.Width/UnitScale/18);
    Shift:=CameraX*0.32;
    Cell:=Floor(Shift/Step);
    N:=Ceil(Frame.Width/UnitScale/Step)+2;
    for K:=-1 to N do begin Index:=Cell+K;
      X:=(Index*Step-Shift)*UnitScale;
      Y:=Frame.Height*(0.48+0.24*Sin(Index*1.31+SeedPhase));
      Surface.Circle(X,Y,0.92*UnitScale,RGB(37,45,81),False,Max(1,0.022*UnitScale));
      Surface.Circle(X,Y,0.70*UnitScale,Mix(RGB(37,54,85),RGB(57,63,106),Phase),False,Max(1,0.012*UnitScale));
      Surface.Line(X-0.55*UnitScale,Y+0.75*UnitScale,X+0.65*UnitScale,Y+0.50*UnitScale,RGB(42,49,82),Max(1,0.014*UnitScale));
    end;
    Light:=0.46+0.18*Pulse;
    PanelTint:=Mix(RGB(37,61,91),RGB(63,112,145),Light);
    TraceTint:=Mix(RGB(32,58,83),RGB(71,135,164),Light);
    Step:=Max(4.7,Frame.Width/UnitScale/48);
    Cell:=Floor(CameraX/Step);
    N:=Ceil(Frame.Width/UnitScale/Step)+1;
    for K:=-1 to N do begin Index:=Cell+K;
      Center:=BAV(Index*Step,2.1*Sin(Index*1.17+SeedPhase));
      Circle(Center,0.72,RGB(30,49,74),False,0.045);
      Circle(Center,0.70,PanelTint,False,0.022);
      Circle(Center,0.40,TraceTint,False,0.014);
      for L:=0 to 2 do begin A:=L*2*Pi/3+Clock*0.18+Index*0.31;
        EndPoint:=BAAdd(Center,BAV(Cos(A)*0.63,Sin(A)*0.63));
        Joint:=BAAdd(Center,BAV(Cos(A)*0.45,Sin(A)*0.45));
        Line(Joint,EndPoint,TraceTint,0.014);
      end;
      Joint:=BAAdd(Center,BAV(-1.4,-1.4));
      EndPoint:=BAAdd(Center,BAV(1.2,-0.9));
      Line(Joint,EndPoint,PanelTint,0.028);
      Joint:=BAAdd(Center,BAV(0.9,1.2));
      EndPoint:=BAAdd(Center,BAV(2.0,0.3));
      Line(Joint,EndPoint,RGB(41,68,101),0.022);
      A:=Clock*0.35+Index*0.13+SeedPhase;
      A:=A-Floor(A);
      Circle(BAAdd(Joint,BAScale(BASub(EndPoint,Joint),A)),0.027,TraceTint);
    end;
    // Six thin streams stay near the screen edges and below all gameplay.
    for K:=0 to 5 do begin A:=Frac(Clock*(0.13+K*0.017)+K*0.173+SeedPhase*0.1);
      X:=A*Frame.Width;
      Y:=Frame.Height*(0.08+0.06*(K mod 3));
      if K>=3 then Y:=Frame.Height-Y;
      Surface.Line(X-Frame.Width*0.034,Y+Frame.Height*0.010,X,Y,TraceTint,Max(1,0.009*UnitScale));
    end;
  end;
begin
  Clock:=0;
  if (FPlan<>nil) and not IsNan(Frame.Time) and not IsInfinite(Frame.Time) then Clock:=EnsureRange(Frame.Time,0.0,FPlan.EndTime);
  UnitScale:=Min(Frame.Width/10.4,Frame.Height/6.5);
  if (FPlan<>nil) and (FPlan.Version=1) then UnitScale:=Min(Frame.Width/8.0,Frame.Height/5.0);
  UI:=Min(Frame.Width/1.6,Frame.Height);
  Left:=(Frame.Width-1.6*UI)/2;
  Hero:=BAV(0,0);
  Past:=Hero;
  Heading:=0;
  PoseClock:=Clock;
  Impact:=0;
  Shake:=0;
  SeedPhase:=0;
  FinishAt:=0;
  if FPlan<>nil then begin SeedPhase:=(FPlan.Seed mod 256)*0.01;
    FinishAt:=FPlan.GoalTime;
    if FPlan.Count>0 then FinishAt:=Max(FinishAt,FPlan.Bomb[FPlan.Count-1].Time+0.12);
    Hero:=FPlan.HeroAt(Clock);
    Past:=FPlan.HeroAt(Clock-0.16);
    D:=FPlan.HeroVelocity(Clock);
    if BALength(D)>0.01 then Heading:=ArcTan2(D.Y,D.X);
    First:=FPlan.BombBefore(Clock-0.075)+1;
    Last:=FPlan.BombBefore(Clock);
    for I:=First to Last do begin B:=FPlan.Bomb[I];
      Age:=Clock-B.Time;
      U:=1-Age/0.075;
      Shake:=Shake+Sin(Age*140+I)*0.018*B.Strength*U;
      if Age<0.03 then begin PoseClock:=B.Time;
        Impact:=Max(Impact,U*B.Strength);
      end;
    end;
  end;
  CameraX:=Past.X-Frame.Width/UnitScale*0.5+EnsureRange(Shake,-0.025,0.025);
  CameraY:=Hero.Y*0.18+EnsureRange(Shake*0.6,-0.015,0.015);
  DrawBackdrop;
  if Frame.BackgroundOnly then Exit;
  if FPlan=nil then begin P:=Screen(Hero);
    DrawHero(Surface,P.X,P.Y,UnitScale,0,0,0);
    Exit;
  end;
  // Shallow cyan afterimages are drawn below the visible fire and actual actor.
  for I:=4 downto 1 do begin P:=FPlan.HeroAt(Clock-I*0.035);
    Circle(P,0.085-I*0.012,RGB(39,83-I*6,108-I*5),False,0.02);
  end;
  // Precomputed moving formations; only the 2.60 s window is visited.
  First:=FPlan.CrowdBefore(Clock-0.22)+1;
  Last:=FPlan.CrowdBefore(Clock+2.60+1E-8);
  for I:=First to Last do begin Foe:=FPlan.Crowd[I];
    if Clock<Foe.Show then Continue;
    P:=FPlan.CrowdAt(I,Clock);
    if not Visible(P,0.23) then Continue;
    if Clock<Foe.Kill then begin U:=Smooth((Clock-Foe.Show)/0.12);
      R:=Foe.Radius*U;
      case Foe.Kind of 0:Color:=RGB(245,143,116);
        1:Color:=RGB(212,134,221);
        else Color:=RGB(239,196,111);
      end;
      D:=BAUnit(BASub(Hero,P));
      Q:=BANormal(D);
      Line(BAAdd(P,BAScale(Q,-R*0.8)),BAAdd(P,BAScale(Q,R*0.8)),Color,0.035);
      Circle(P,R*0.72,Mix(Color,RGB(46,40,67),0.45));
      Circle(BAAdd(P,BAScale(D,R*0.25)),R*0.32,Color);
      Line(P,BAAdd(P,BAScale(D,R*0.82)),RGB(255,226,180),0.024);
    end else if Foe.Bomb>=0 then begin U:=(Clock-Foe.Kill)/0.22;
      Spark(P,Foe.Radius+0.035,U,I,RGB(248,181,136),6);
      Circle(P,Foe.Radius*(1-U),Mix(RGB(255,237,180),RGB(33,46,64),U));
    end;
  end;
  First:=FPlan.TargetBefore(Clock-0.30)+1;
  Last:=FPlan.TargetBefore(Clock+0.50);
  for I:=First to Last do begin Target:=FPlan.Target[I];
    if Clock<Target.Show then Continue;
    if Clock<Target.Kill then begin U:=Smooth((Clock-Target.Show)/0.10);
      case Target.Kind of
        2:begin Box(Target.Position,Target.Radius*0.78*U,Target.Radius*0.60*U,RGB(151,137,115));
          Line(BAAdd(Target.Position,BAV(-Target.Radius*0.7,-Target.Radius*0.45)),BAAdd(Target.Position,BAV(Target.Radius*0.7,Target.Radius*0.45)),RGB(240,203,138),0.025);
        end;
        1:begin Circle(Target.Position,Target.Radius*U,RGB(172,104,166));
          Circle(Target.Position,Target.Radius*0.45*U,RGB(250,181,173));
        end;
        else begin Circle(Target.Position,Target.Radius*U,RGB(126,148,184));
          D:=BAUnit(BASub(Hero,Target.Position));
          Line(Target.Position,BAAdd(Target.Position,BAScale(D,Target.Radius-0.02)),RGB(243,188,139),0.04);
        end;
      end;
    end else begin U:=(Clock-Target.Kill)/0.30;
      Spark(Target.Position,Target.Radius+0.04,U,I,RGB(236,179,122),7);
      Circle(Target.Position,Target.Radius*(1-U),Mix(RGB(255,224,153),RGB(31,47,65),U));
    end;
  end;
  First:=FPlan.BombBefore(Clock)+1;
  Last:=FPlan.BombBefore(Clock+BA_FUSE+1E-8);
  for I:=First to Last do begin B:=FPlan.Bomb[I];
    if Clock<B.Place then Continue;
    Color:=RGB(118,146,174);
    if B.Parent>=0 then Color:=RGB(110,222,215);
    Circle(B.Position,BA_BOMB_RADIUS,RGB(28,47,68));
    Circle(B.Position,BA_BOMB_RADIUS*0.62,Color);
    U:=(Clock-B.Place)/(B.Time-B.Place);
    Circle(B.Position,0.025+0.025*U,RGB(255,199,128));
    if B.Parent>=0 then begin P:=FPlan.Bomb[B.Parent].Position;
      Age:=Clock-FPlan.Bomb[B.Parent].Time;
      if Age>=0 then begin D:=BAUnit(BASub(B.Position,P));
        R:=Min(BALength(BASub(B.Position,P))-BA_BOMB_RADIUS,FPlan.Bomb[B.Parent].WaveSpeed*Age);
        Line(P,BAAdd(P,BAScale(D,R)),RGB(105,235,225),0.02);
        Circle(BAAdd(P,BAScale(D,R)),0.035,RGB(232,255,231));
      end;
    end;
  end;
  // Three staggered planting clocks per salvo, all on original accent clocks.
  First:=FPlan.ChargeBefore(Clock-0.46)+1;
  Last:=FPlan.ChargeBefore(Clock+1.50+1E-8);
  for I:=First to Last do begin Charge:=FPlan.Charges[I];
    if Clock<Charge.Place then Continue;
    if not Visible(Charge.Position,Charge.Radius+0.04) then Continue;
    if Clock<Charge.Time then begin
      Circle(Charge.Position,0.10,RGB(26,39,60));
      Circle(Charge.Position,0.078,RGB(185,144+Charge.Pattern*25,105));
      U:=(Clock-Charge.Place)/(Charge.Time-Charge.Place);
      Circle(Charge.Position,0.022+0.024*U,RGB(255,237,163));
      Circle(Charge.Position,0.11,RGB(128,122,155),False,0.012);
    end else begin
      Age:=Clock-Charge.Time;
      if Age>Charge.Life+0.14 then Continue;
      U:=Age/(Charge.Life+0.14);
      R:=Charge.Radius;
      Color:=Mix(RGB(188+Charge.Pattern*24,140+Charge.Pattern*22,202-Charge.Pattern*32),RGB(29,42,63),U);
      Circle(Charge.Position,R,Color,False,0.025*(1-U));
      Circle(Charge.Position,R*(0.46+0.30*U),Color,False,0.018);
      if Charge.Pattern=1 then begin
        for J:=0 to 7 do begin Angle:=J*Pi/4+I*0.33;
          Line(BAAdd(Charge.Position,BAV(Cos(Angle)*R*0.3,Sin(Angle)*R*0.3)),BAAdd(Charge.Position,BAV(Cos(Angle)*(R-0.04),Sin(Angle)*(R-0.04))),Color,0.018);
        end;
      end;
      if Age<0.06 then Circle(Charge.Position,0.18*(1-Age/0.06),RGB(255,237,195));
      Spark(Charge.Position,R-0.04,U,I,Color,10);
    end;
  end;
  First:=FPlan.BombBefore(Clock-0.72)+1;
  Last:=FPlan.BombBefore(Clock);
  for I:=First to Last do Blast(I);
  for I:=0 to FPlan.BossCount-1 do begin Boss:=FPlan.Boss[I];
    if (Clock<Boss.Show) or (Clock>Boss.Kill+0.50) then Continue;
    P:=FPlan.BossAt(I,Clock);
    if Clock<Boss.Kill then begin HP:=FPlan.BossHP(I,Clock)/(Boss.LastBomb-Boss.FirstBomb+1);
      Hit:=0;
      HitIndex:=FPlan.BombBefore(Clock);
      if (HitIndex>=Boss.FirstBomb) and (HitIndex<=Boss.LastBomb) then Hit:=EnsureRange(1-(Clock-FPlan.Bomb[HitIndex].Time)/0.08,0.0,1.0);
      U:=Smooth((Clock-Boss.Show)/0.50)*(1-0.05*Hit);
      // Midnight armour and lime machinery distinguish the boss from warm/pink enemies.
      // Solid dark backing is confined to the physical body and masks underlying fire.
      for J:=0 to 2 do if HP>(2-J)/3 then begin Angle:=J*2*Pi/3+Clock*0.35;
        Q:=BAAdd(P,BAV(Cos(Angle)*0.32,Sin(Angle)*0.32));
        Line(P,Q,RGB(10,20,43),0.16*U);
        Line(P,Q,RGB(41,76,91),0.10*U);
        Line(P,Q,RGB(167,255,84),0.024*U);
      end;
      Circle(P,0.34*U,RGB(10,20,43));
      Circle(P,0.31*U,Mix(RGB(18,36,73),RGB(62,107,92),Hit*0.7));
      Circle(P,0.31*U,RGB(167,255,84),False,0.025*U);
      Circle(P,0.24*U,RGB(21,65,69));
      Circle(P,0.22*U,RGB(73,138,104),False,0.018*U);
      Circle(P,0.12*U,Mix(RGB(182,255,110),RGB(240,255,216),Hit));
      Circle(P,0.065*U,RGB(13,36,47));
      Circle(P,0.024*U,RGB(233,255,208));
      // Remaining modules sit above the core so their centres stay readable.
      for J:=0 to 2 do if HP>(2-J)/3 then begin Angle:=J*2*Pi/3+Clock*0.35;
        Q:=BAAdd(P,BAV(Cos(Angle)*0.32,Sin(Angle)*0.32));
        Circle(Q,0.10*U,RGB(10,20,43));
        Circle(Q,0.077*U,RGB(25,62,75));
        Circle(Q,0.092*U,RGB(167,255,84),False,0.020*U);
        Circle(Q,0.034*U,RGB(217,255,161));
      end;
      for J:=0 to 1 do begin PartIndex:=Boss.FirstBomb+Ceil((Boss.LastBomb-Boss.FirstBomb+1)*(J+1)/3)-1;
        Age:=Clock-FPlan.Bomb[PartIndex].Time;
        if (Age>=0) and (Age<0.18) then begin PartU:=Age/0.18;
          Angle:=J*2*Pi/3+FPlan.Bomb[PartIndex].Time*0.35;
          Q:=BAAdd(FPlan.BossAt(I,FPlan.Bomb[PartIndex].Time),BAV(Cos(Angle)*(0.32+0.06*Smooth(PartU)),Sin(Angle)*(0.32+0.06*Smooth(PartU))));
          Circle(Q,0.075*(1-PartU),RGB(12,32,53));
          Circle(Q,0.070*(1-PartU),Mix(RGB(182,255,110),RGB(37,62,69),PartU),False,0.014);
          Spark(Q,0.10,PartU,PartIndex,RGB(190,244,124),7);
        end;
      end;
      Q:=Screen(P);
      Surface.FillRect(Q.X-0.55*UnitScale,Q.Y-0.68*UnitScale,Q.X+0.55*UnitScale,Q.Y-0.60*UnitScale,RGB(18,29,47));
      Surface.FillRect(Q.X-0.52*UnitScale,Q.Y-0.665*UnitScale,Q.X+(-0.52+1.04*HP)*UnitScale,Q.Y-0.615*UnitScale,RGB(182,255,110));
    end else begin U:=(Clock-Boss.Kill)/0.50;
      Circle(P,1.30*Smooth(U),Mix(RGB(213,255,148),RGB(37,51,72),U),False,0.04);
      Spark(P,1.25,U,I,RGB(187,245,113),28);
      Circle(P,0.42*(1-U),RGB(240,255,213));
    end;
  end;
  First:=FPlan.ShotBefore(Clock-0.70)+1;
  Last:=FPlan.ShotBefore(Clock);
  for I:=First to Last do begin Shot:=FPlan.Shot[I];
    if (Clock<Shot.Start) or (Clock>=Shot.Finish) then Continue;
    P:=BAAdd(Shot.Position,BAScale(Shot.Velocity,Clock-Shot.Start));
    D:=BAUnit(Shot.Velocity);
    U:=Min(1.0,(Shot.Finish-Clock)/0.12);
    Color:=Mix(RGB(34,48,68),RGB(239,132+35*(I mod 3),193),U);
    Line(BAAdd(P,BAScale(D,-0.08)),P,Color,0.045);
    Circle(P,0.045,Color);
    Circle(P,0.020,Mix(RGB(34,48,68),RGB(255,234,198),U));
  end;
  // Real enemy projectiles keep their original straight flight after launch.
  First:=FPlan.RaidBefore(Clock-1.50)+1;
  Last:=FPlan.RaidBefore(Clock);
  for I:=First to Last do begin Raid:=FPlan.Raids[I];
    if Clock>=Raid.Finish then Continue;
    P:=BAAdd(Raid.Position,BAScale(Raid.Velocity,Clock-Raid.Start));
    if not Visible(P,0.08) then Continue;
    D:=BAUnit(Raid.Velocity);
    U:=Min(1.0,(Raid.Finish-Clock)/0.12);
    Color:=Mix(RGB(29,42,63),RGB(250,151+30*(Raid.Foe mod 3),143+35*(Raid.Foe mod 2)),U);
    Line(BAAdd(P,BAScale(D,-0.045)),P,Color,0.024);
    Circle(P,0.048,Color);
    Circle(P,0.022,Mix(RGB(29,42,63),RGB(255,240,198),U));
  end;
  P:=Screen(Hero);
  U:=1;
  if Clock<FPlan.LaunchTime then U:=Smooth(Clock/Max(0.001,FPlan.LaunchTime));
  DrawHero(Surface,P.X,P.Y,UnitScale*U,Heading,PoseClock,Impact);
  Surface.FillRect(Left+0.04*UI,0.025*UI,Left+0.52*UI,0.11*UI,RGB(19,34,53));
  Number(FPlan.BombBefore(Clock)+1,Left+0.08*UI,0.045*UI,0.018*UI,RGB(255,223,147));
  Number(FPlan.TargetBefore(Clock)+1+FPlan.CrowdDestroyed(Clock),Left+0.30*UI,0.045*UI,0.018*UI,RGB(130,228,221));
  if Clock<FPlan.LaunchTime then Digit(3-Min(2,Floor(Clock/Max(0.001,FPlan.LaunchTime)*3)),Frame.Width/2-0.035*UI,Frame.Height*0.32,0.07*UI,RGB(246,232,173));
  if (Clock>=FPlan.LaunchTime) and (Clock<FPlan.LaunchTime+0.35) then DrawWord('GO',Frame.Width/2-0.075*UI,Frame.Height*0.30,0.06*UI,RGB(231,245,194));
  if Clock>=FinishAt then begin
    Surface.FillRect(Frame.Width/2-0.28*UI,Frame.Height*0.24,Frame.Width/2+0.28*UI,Frame.Height*0.24+0.12*UI,RGB(24,53,68));
    DrawWord('CLEAR',Frame.Width/2-0.158*UI,Frame.Height*0.24+0.015*UI,0.045*UI,RGB(213,247,224));
  end;
  if Clock>=FinishAt then begin U:=EnsureRange((Clock-FinishAt)/(FPlan.EndTime-FinishAt),0.0,1.0);
    Circle(Hero,0.25+0.15*U,RGB(134,230,223),False,0.025);
  end;
end;

function TBombActionAnimation.GoalTime:Double;
begin
  Result:=inherited GoalTime;
  if FPlan<>nil then Result:=FPlan.GoalTime;
end;
end.
