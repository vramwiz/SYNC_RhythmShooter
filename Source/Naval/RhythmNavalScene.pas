unit RhythmNavalScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmNavalPlan;
type
  TNavalAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TNavalPlan;
    FAttempt,FError:string;
  public
    destructor Destroy; override;
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;

destructor TNavalAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TNavalAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TNavalAnimation.Notice:string;
begin Result:=FError;
end;

procedure TNavalAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TNavalPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function Mix(A,B:TColor;U:Double):TColor;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
end;

procedure TNavalAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var
  Scale,Left,Top,Clock,Zoom,Age,U,Angle,Size,Power,Radius:Double;
  Center,Hero,P,Q,A,B:TNavalPoint;
  I,J,First,Last,Index,Theme,Count,SplashBudget,Stride:Integer;
  Phrase:TNavalPhrase;
  H:TNavalHit;
  Shot:TNavalShot;
  Ocean:TColor;
  GunAim:array[0..2] of TNavalPoint;
  AimAge:array[0..2] of Double;
  procedure Map(const P:TNavalPoint;out X,Y:Double);
  begin X:=Left+(0.9+(P.X-Center.X)*Zoom)*Scale;
    Y:=Top+(0.5+(P.Y-Center.Y)*Zoom)*Scale;
  end;
  procedure Line(X1,Y1,X2,Y2:Double;Color:TColor;Width:Double);
  var
    A,B,C,D:Double;
  begin Map(NavalPoint(X1,Y1),A,B);
    Map(NavalPoint(X2,Y2),C,D);
    Surface.Line(A,B,C,D,Color,Max(1.0,Width*Scale*Zoom));
  end;
  procedure Circle(X,Y,R:Double;Color:TColor;Filled:Boolean=True);
  var
    A,B:Double;
  begin if R<=0 then Exit;
    Map(NavalPoint(X,Y),A,B);
    Surface.Circle(A,B,R*Scale*Zoom,Color,Filled,Max(1.0,0.0015*Scale*Zoom));
  end;
  procedure Box(X1,Y1,X2,Y2:Double;Color:TColor);
  var
    A,B,C,D:Double;
  begin Map(NavalPoint(X1,Y1),A,B);
    Map(NavalPoint(X2,Y2),C,D);
    Surface.FillRect(A,B,C,D,Color);
  end;
  procedure Triangle(const P0,P1,P2:TNavalPoint;Color:TColor);
  var
    N,K:Integer;
    U:Double;
    A,B:TNavalPoint;
  begin N:=EnsureRange(Ceil(Max(Hypot(P2.X-P0.X,P2.Y-P0.Y),Hypot(P2.X-P1.X,P2.Y-P1.Y))*Scale*Zoom/3),4,48);
    for K:=0 to N-1 do begin U:=(K+0.5)/N;
      A:=NavalPoint(P0.X+(P2.X-P0.X)*U,P0.Y+(P2.Y-P0.Y)*U);
      B:=NavalPoint(P1.X+(P2.X-P1.X)*U,P1.Y+(P2.Y-P1.Y)*U);
      Line(A.X,A.Y,B.X,B.Y,Color,Max(0.001,Abs(P2.Y-(P0.Y+P1.Y)/2)/N*1.4));
    end;
  end;
  procedure Background;
  var
    N,K:Integer;
    Y,X,W,R,Phase:Double;
    Color,Sea:TColor;
  begin
    Sea:=RGB(18,112,146);
    if Theme=1 then Sea:=RGB(27,108,143) else if Theme=2 then Sea:=RGB(19,91,129);
    Ocean:=Sea;
    for N:=0 to 23 do begin U:=N/23;
      Color:=Mix(RGB(128,199,218),RGB(218,232,210),U);
      if Theme=1 then Color:=Mix(RGB(193,141,160),RGB(243,201,157),U) else if Theme=2 then Color:=Mix(RGB(83,128,167),RGB(164,193,206),U);
      Surface.FillRect(0,N*Frame.Height*0.22/24,Frame.Width,(N+1)*Frame.Height*0.22/24+1,Color);
    end;
    Surface.FillRect(0,Frame.Height*0.22,Frame.Width,Frame.Height,Sea);
    Circle(1.55,0.09,0.046,Mix(RGB(255,235,169),RGB(200,218,211),Theme/4));
    for N:=0 to 8 do begin X:=N*0.28-Frac(Clock*0.007+Theme*0.17)*0.28;
      Y:=0.17+0.012*Sin(N*2.3+Theme);
      Triangle(NavalPoint(X-0.12,0.225),NavalPoint(X+0.12,0.225),NavalPoint(X,Y),Mix(Sea,RGB(68,129,132),0.6));
    end;
    // Four layers use world distance and speed; the water never freezes in defence.
    for N:=0 to 19 do begin Y:=0.24+N*0.039;
      Phase:=Clock*(0.09+N*0.006);
      for K:=-1 to 11 do begin X:=K*0.19-Frac(Phase)*0.19+0.018*Sin(N*1.7+K);
        W:=0.07+0.04*Sin(N*2.1+K+Clock*0.9);
        R:=0.004+N*0.00025;
        Line(X,Y+Sin(Clock*1.3+N+K)*0.004,X+W,Y+Sin(Clock*1.3+N+K+0.8)*0.004,Mix(Sea,RGB(112,206,216),0.22+N*0.015),R);
      end;
    end;
  end;
  procedure Splash(X,Y,Age,Strength:Double;Enemy:Boolean);
  var
    K:Integer;
    U,H,W,DX:Double;
    Color:TColor;
  begin if (Age<0) or (Age>=0.58) or (SplashBudget<=0) then Exit;
    Dec(SplashBudget);
    U:=Age/0.58;
    H:=(0.055+0.08*Strength)*Sin(Pi*Min(1.0,Age/0.42));
    W:=0.012+Age*0.085;
    Color:=RGB(154,232,240);
    if Enemy then Color:=RGB(234,224,190);
    Line(X-W,Y,X+W,Y,Mix(Color,Ocean,U),0.003*(1-U));
    Triangle(NavalPoint(X-W*0.7,Y),NavalPoint(X+W*0.8,Y),NavalPoint(X,Y-H),Mix(Color,Ocean,U*0.80));
    for K:=0 to 3 do begin DX:=(K-1.5)*Age*(0.07+Strength*0.03);
      Circle(X+DX,Y-H*(0.55+K*0.1)+Age*Age*0.12,0.0028*(1-U),Mix(RGB(236,252,245),Ocean,U));
    end;
  end;
  procedure Ship(X,Y,Size,Turn,Health,Damage,SinkAge:Double;Player,Boss:Boolean;ShipIndex:Integer);
  var
    N,K,Masts:Integer;
    LocalY,W,HalfW,HalfH,Height,DX,SailWidth,Wind,Age,U,Fade,PieceAngle,TX,TY:Double;
    Hull,Sail,Edge,Color:TColor;
    function Pt(AX,AY:Double):TNavalPoint;
    begin Result:=NavalPoint(X+(AX*Cos(Turn)-AY*Sin(Turn))*Size,Y+(AX*Sin(Turn)+AY*Cos(Turn))*Size);
    end;
    procedure Bar(AX,AY,BX,BY:Double;Tint:TColor;Width:Double);
    var
      A,B:TNavalPoint;
    begin A:=Pt(AX,AY);
      B:=Pt(BX,BY);
      Line(A.X,A.Y,B.X,B.Y,Tint,Width*Size);
    end;
    procedure Dot(AX,AY,R:Double;Tint:TColor);
    var
      P:TNavalPoint;
    begin P:=Pt(AX,AY);
      Circle(P.X,P.Y,R*Size,Tint);
    end;
  begin
    Fade:=1;
    if SinkAge>=0 then Fade:=Sqr(1-EnsureRange(SinkAge/1.5,0.0,1.0));
    Hull:=RGB(102,60,42);
    Sail:=RGB(221,83,79);
    Edge:=RGB(232,180,107);
    HalfW:=0.12;
    HalfH:=0.035;
    if Player then begin Hull:=RGB(98,61,40);
      Sail:=RGB(71,157,221);
      Edge:=RGB(238,198,118);
      HalfW:=0.15;
      HalfH:=0.045;
    end
    else if Boss then begin Hull:=RGB(39,34,61);
      Sail:=RGB(107,65,139);
      Edge:=RGB(172,137,195);
    end;
    Hull:=Mix(Ocean,Hull,Fade);
    Sail:=Mix(Ocean,Sail,Fade);
    Edge:=Mix(Ocean,Edge,Fade);
    // The lower horizontal edge is the opaque hull contact used by the plan.
    for N:=0 to 31 do begin LocalY:=-HalfH+(N+0.5)*HalfH*2/32;
      W:=HalfW*(0.74+0.26*Sqrt(Max(0.0,1-Sqr(LocalY/HalfH))));
      Color:=Mix(Hull,RGB(43,28,34),0.10+0.28*N/32);
      if Boss then Color:=Mix(Hull,RGB(97,85,128),0.35*(1-N/32));
      Bar(-W,LocalY,W,LocalY,Color,HalfH*2/32*1.5);
    end;
    Bar(-HalfW*0.86,-HalfH+0.002,HalfW*0.85,-HalfH+0.002,Edge,0.004);
    Bar(-HalfW*0.90,HalfH-0.0015,HalfW*0.90,HalfH-0.0015,Edge,0.003);
    Bar(-HalfW*0.7,-HalfH*0.25,HalfW*0.65,-HalfH*0.25,Mix(Edge,Hull,0.6),0.009);
    if Boss then for K:=-2 to 2 do if (Health>0.18) or (Abs(K)<2) then begin Bar(K*0.038,-0.016,K*0.038+0.010,-0.016,RGB(128,116,151),0.020);
      Bar(K*0.038,0.010,K*0.038-0.015,0.035,RGB(39,32,53),0.010);
    end;
    Masts:=2;
    if Boss then Masts:=3;
    Height:=0.17;
    if Boss then Height:=0.118;
    for K:=0 to Masts-1 do begin DX:=(K-(Masts-1)/2)*0.085;
      if not Player and (Health<0.36) and (K=0) then begin Bar(DX,0,DX,-0.035,RGB(90,60,48),0.004);
        Continue;
      end;
      Wind:=0.008*Sin(Clock*2.2+K)+Damage*0.008;
      SailWidth:=0.042;
      if Boss then SailWidth:=0.033;
      Bar(DX,0,DX+Wind,-Height,RGB(85,58,43),0.004);
      Bar(DX-0.058,-Height*0.36,DX+0.058,-Height*0.36,RGB(139,106,69),0.002);
      for N:=0 to 31 do begin LocalY:=-Height*0.91+N*Height*0.0195;
        W:=SailWidth*(1+0.12*Sin(N*Pi/31));
        TX:=DX+Wind*(0.6+N*0.0125);
        if ((Health<0.65) or (Damage>0.1)) and (K=0) and (N>19) then W:=W*(0.82-0.07*(N mod 3));
        Color:=Mix(Sail,RGB(226,239,222),0.08+0.12*Sin(N*Pi/31));
        Bar(TX-W,LocalY,TX+W,LocalY,Color,Height*0.028);
      end;
      Bar(DX-SailWidth*0.88,-Height*0.86,DX+SailWidth*0.88,-Height*0.86,Mix(Sail,clWhite,0.5),0.002);
      // Canvas folds make the sail legible as a surface, not a floating marker.
      Bar(DX,-Height*0.84,DX+Wind,-Height*0.30,Mix(Sail,RGB(44,75,110),0.35),0.0018);
      Bar(DX+Wind,-Height-0.005,DX+Wind,-Height-0.023,RGB(83,58,47),0.002);
      Triangle(Pt(DX+Wind,-Height-0.022),Pt(DX+Wind+0.032,-Height-0.014),Pt(DX+Wind,-Height-0.008),Mix(Sail,clWhite,0.08));
    end;
    if not Player then begin
      for K:=-1 to 1 do begin Bar(K*0.05+0.021,0.020,K*0.05,0.035,RGB(39,38,45),0.009);
        Dot(K*0.05+0.020,0.018,0.008,RGB(143,122,102));
      end;
      if ShipIndex>=0 then begin
        Age:=Clock-FPlan.PartTime(ShipIndex,1);
        if (Age>=0) and (Age<0.9) then begin PieceAngle:=Age*1.7;
          TX:=X-0.05*Size+Age*0.13;
          TY:=Y-0.04*Size+Age*Age*0.10;
          Line(TX,TY,TX+Sin(PieceAngle)*0.13*Size,TY-Cos(PieceAngle)*0.13*Size,Mix(RGB(135,93,65),Ocean,Age/0.9),0.004*Size);
          Triangle(NavalPoint(TX,TY),NavalPoint(TX+Sin(PieceAngle)*0.12*Size,TY-Cos(PieceAngle)*0.12*Size),NavalPoint(TX+0.06*Size,TY-0.035*Size),Mix(Sail,Ocean,Age/0.9));
        end;
      end;
    end;
    if (Health<0.70) or (Damage>0.01) then begin Bar(-0.065,0.001,-0.045,0.018,RGB(38,25,28),0.003);
      Bar(0.04,-0.010,0.07,0.014,RGB(38,25,28),0.003);
    end;
    if Damage>0.01 then for K:=0 to 3 do begin W:=0.018*(0.55+0.45*Sin(Clock*14+K));
      DX:=(K-1.5)*0.035;
      Bar(DX-W,0,DX, -0.025*Damage,RGB(237,119,54),0.009*Damage);
      Bar(DX,-0.023*Damage,DX+W,0,RGB(255,205,103),0.005*Damage);
    end;
    // Wake is tied to a physical stern and remains active during both roles.
    for N:=0 to 3 do begin U:=Frac(Clock*0.7+N*0.25);
      Bar(-HalfW-0.02-U*0.13,0.005-U*0.025,-HalfW-U*0.13,0.005+U*0.025,Mix(RGB(179,230,222),Ocean,U),0.003*(1-U));
    end;
  end;
  procedure DrawEnemy(Index:Integer);
  var
    Data:TNavalShip;
    P:TNavalPoint;
    Age,Health,Size,Tilt:Double;
  begin Data:=FPlan.Ships[Index];
    if (Clock<Data.Show) or (Clock>=Data.Kill+1.5) then Exit;
    P:=FPlan.ShipAt(Index,Clock);
    Age:=Clock-Data.Kill;
    Health:=FPlan.HealthAt(Index,Clock);
    Size:=Data.Size;
    Tilt:=0;
    if Age>=0 then begin U:=Smooth(Age/1.5);
      P.Y:=P.Y+0.13*U;
      Tilt:=0.55*U;
      Size:=Size*(1-0.18*U);
    end;
    Ship(P.X,P.Y,Size,Tilt,Health,0,Age,False,Data.Boss<>0,Index);
    if Age>=0 then begin Splash(P.X-0.06*Size,P.Y+0.035*Size,Age,1.0,False);
      Splash(P.X+0.07*Size,P.Y+0.035*Size,Age-0.12,0.8,False);
    end;
    if (Age<0) and (Data.Boss<>0) then begin Surface.FillRect(Left+0.58*Scale,Top+0.035*Scale,Left+1.22*Scale,Top+0.063*Scale,RGB(30,27,50));
      Surface.FillRect(Left+0.585*Scale,Top+0.040*Scale,Left+(0.585+0.63*Health)*Scale,Top+0.058*Scale,RGB(199,127,209));
    end;
  end;
begin
  Scale:=Min(Frame.Width/1.8,Frame.Height);
  Left:=(Frame.Width-1.8*Scale)/2;
  Top:=(Frame.Height-Scale)/2;
  Clock:=Max(0.0,Frame.Time);
  Center:=NavalPoint(0.9,0.5);
  Zoom:=1;
  Theme:=0;
  Ocean:=RGB(18,112,146);
  if FPlan<>nil then begin Clock:=Min(Clock,FPlan.EndTime);
    Phrase:=FPlan.Phrases[FPlan.PhraseBefore(Clock)];
    Theme:=Phrase.Theme;
    FPlan.CameraAt(Clock,Center,Zoom);
  end;
  SplashBudget:=96;
  Background;
  if Frame.BackgroundOnly then begin Surface.DrawViewportMatte(Left,Top,Frame.Width,Frame.Height,RGB(8,39,58));Exit;end;
  if FPlan<>nil then begin
    First:=Max(0,FPlan.ShipBefore(Clock-1.5));
    Last:=Min(FPlan.ShipCount-1,FPlan.ShipBefore(Clock+6.1));
    Count:=0;
    for I:=Last downto First do begin Index:=FPlan.DrawShipIndex(I);
      if FPlan.Ships[Index].Boss<>0 then Continue;
      DrawEnemy(Index);
      Inc(Count);
      if Count>=96 then Break;
    end;
    for I:=0 to FPlan.BossCount-1 do DrawEnemy(FPlan.Boss(I));
    // Incoming shells use a different warm colour/core from our broadside.
    Last:=FPlan.ShotBefore(Clock);
    First:=Max(Max(0,FPlan.ShotBefore(Clock-2.4)+1),Last-767);
    for I:=First to Last do begin Shot:=FPlan.DrawShot(I);
      if (Clock<Shot.Launch) or (Clock>Shot.Finish+0.58) then Continue;
      Age:=Clock-Shot.Launch;
      if Clock<Shot.Finish then begin P:=FPlan.ShotAt(Shot,Clock);
        Q:=FPlan.ShotAt(Shot,Max(Shot.Launch,Clock-0.035));
        Line(Q.X,Q.Y,P.X,P.Y,RGB(225,116,84),Shot.Radius*0.85);
        Circle(P.X,P.Y,Shot.Radius,RGB(239,149,82));
        Circle(P.X-0.0015,P.Y-0.0015,Shot.Radius*0.40,RGB(255,226,161));
      end
      else begin Age:=Clock-Shot.Finish;
        if Shot.Kind=0 then Splash(Shot.B.X,Shot.B.Y,Age,0.6,True)
        else if Age<0.20 then begin U:=1-Age/0.20;
          for J:=0 to 4 do begin Angle:=J*2.3999;
            Line(Shot.B.X,Shot.B.Y,Shot.B.X+Cos(Angle)*Age*0.18,Shot.B.Y+Sin(Angle)*Age*0.18,RGB(248,217,151),0.002*U);
          end;
        end;
      end;
    end;
    Hero:=FPlan.HeroAt(Clock);
    Ship(Hero.X,Hero.Y,1,FPlan.HeroAngle(Clock),1,FPlan.DamageAt(Clock),-1,True,False,-1);
    for J:=0 to 2 do begin GunAim[J]:=NavalPoint(0.70,-0.70);
      AimAge[J]:=1E100;
    end;
    Last:=FPlan.HitBefore(Clock+0.80);
    First:=Max(0,FPlan.HitBefore(Clock-0.20));
    Stride:=Max(1,Ceil((Last-First+1)/256));
    I:=First;
    while I<=Last do begin
      if FPlan.CannonPath(I,Age,U,Power,A,B) then if (Clock>=Age-0.065) and (Clock<Age+0.08) then begin H:=FPlan.Hits[I];
        Radius:=Hypot(B.X-A.X,B.Y-A.Y);
        if (Radius>1E-8) and (Abs(Clock-Age)<AimAge[H.Gun]) then begin GunAim[H.Gun]:=NavalPoint((B.X-A.X)/Radius,(B.Y-A.Y)/Radius);
          AimAge[H.Gun]:=Abs(Clock-Age);
        end;
      end;
      Inc(I,Stride);
    end;
    for J:=0 to 2 do begin P:=FPlan.HeroGun(Clock,J);
      Line(P.X,P.Y,P.X+GunAim[J].X*0.025,P.Y+GunAim[J].Y*0.025,RGB(42,50,60),0.010);
      Circle(P.X,P.Y,0.008,RGB(191,150,95));
    end;
    // Only the last 0.8 s of source hits can own a visible projectile or impact.
    Last:=FPlan.HitBefore(Clock+0.72);
    First:=Max(0,FPlan.HitBefore(Clock-0.65));
    Stride:=Max(1,Ceil((Last-First+1)/512));
    I:=First;
    while I<=Last do begin H:=FPlan.Hits[I];
      Age:=Clock-FPlan.Events[H.Source].Time;
      if FPlan.CannonPath(I,U,Power,Radius,A,B) then begin
        if (Clock>=U) and (Clock<Power) then begin FPlan.CannonAt(I,Clock,P);
          FPlan.CannonAt(I,Max(U,Clock-0.026),Q);
          Line(Q.X,Q.Y,P.X,P.Y,RGB(232,218,153),0.004);
          Circle(P.X,P.Y,0.008,RGB(255,238,173));
          Circle(P.X-0.002,P.Y-0.002,0.0035,RGB(255,255,231));
        end;
        if (Clock>=U) and (Clock<U+0.055) then begin Size:=1-(Clock-U)/0.055;
          Radius:=Max(1E-8,Hypot(B.X-A.X,B.Y-A.Y));
          Line(A.X,A.Y,A.X+(B.X-A.X)/Radius*0.026*Size,A.Y+(B.Y-A.Y)/Radius*0.026*Size,RGB(255,234,145),0.011*Size);
        end;
        if (Age>=0) and (Age<0.40) then begin
          if H.Kind=0 then begin P:=B;
            U:=Age/0.40;
            Size:=0.018+0.035*FPlan.Events[H.Source].Strength;
            if Age<0.075 then Circle(P.X,P.Y,Size*(1-Age/0.075),RGB(255,235,164));
            for J:=0 to 7 do begin Angle:=J*2.39996+H.Target;
              Radius:=Age*(0.13+0.03*(J mod 3));
              Q:=NavalPoint(P.X+Cos(Angle)*Radius,P.Y+Sin(Angle)*Radius+Age*Age*0.14);
              Line(Q.X-0.004*(1-U),Q.Y,Q.X+0.004*(1-U),Q.Y,Mix(RGB(214,158,92),Ocean,U),0.005*(1-U));
            end;
          end;
        end;
      end;
      Inc(I,Stride);
    end;

  end;
  if Left>0 then begin Surface.FillRect(0,0,Left,Frame.Height,RGB(8,39,58));
    Surface.FillRect(Frame.Width-Left,0,Frame.Width,Frame.Height,RGB(8,39,58));
  end;
  if Top>0 then begin Surface.FillRect(0,0,Frame.Width,Top,RGB(8,39,58));
    Surface.FillRect(0,Frame.Height-Top,Frame.Width,Frame.Height,RGB(8,39,58));
  end;
end;
end.
