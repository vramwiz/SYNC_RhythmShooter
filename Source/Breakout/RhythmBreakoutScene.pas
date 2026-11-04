unit RhythmBreakoutScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmBreakoutPlan;
type
  TBreakoutAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TBreakoutPlan;
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
uses System.SysUtils,System.Math,System.Types,Winapi.Windows,Vcl.Graphics,RhythmBreakoutGeometry,RhythmBreakoutScore,RhythmBreakoutCampaign,RhythmBarrage;

destructor TBreakoutAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TBreakoutAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TBreakoutAnimation.Notice:string;
begin Result:=FError;
end;

procedure TBreakoutAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TBreakoutPlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TBreakoutAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var
  Scale,Left,Top,Time,X,Y,U,Age,Alpha,BallAlpha,TrailAlpha,PaddleHalf,PaddleX,PaddleY,EntryOffset,EntryEnd,Angle,Radius:Double;
  I,J,N,First,Last,Previous,ChunkBudget:Integer;
  P,Q:TBreakPoint;
  B:TBreakBlock;
  Color:TColor;
  ItemData:TScoreItem;
  BossData:TBreakBoss;
  Enemy:TBreakBossBullet;
  Attack:TBreakAttack;
  function Mix(A,B:TColor;U:Double):TColor;
  begin U:=EnsureRange(U,0.0,1.0);
    Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
  end;
  procedure Line(X1,Y1,X2,Y2:Double;Tint:TColor;Width:Double);
  begin Surface.Line(Left+X1*Scale,Top+Y1*Scale,Left+X2*Scale,Top+Y2*Scale,Tint,Max(1.0,Width*Scale));
  end;
  procedure Circle(X,Y,R:Double;Tint:TColor;Filled:Boolean=True);
  begin Surface.Circle(Left+X*Scale,Top+Y*Scale,R*Scale,Tint,Filled,Max(1.0,Scale*0.002));
  end;
  procedure Box(L,T,R,B:Double;Tint:TColor);
  begin
    Surface.FillRect(Left+L*Scale,Top+T*Scale,Left+R*Scale,Top+B*Scale,Tint);
  end;
  function BlockTint(Row:Integer):TColor;
  begin
    case Row mod 7 of
      0:Result:=RGB(245,110,126);
      1:Result:=RGB(249,163,91);
      2:Result:=RGB(245,216,102);
      3:Result:=RGB(122,215,147);
      4:Result:=RGB(105,213,228);
      5:Result:=RGB(123,159,242);
      else Result:=RGB(190,137,235);
    end;
  end;
  function Smooth(Value:Double):Double;
  begin Value:=EnsureRange(Value,0.0,1.0);
    Result:=Value*Value*(3-2*Value);
  end;
  function HasBossImage(Index:Integer):Boolean;
  begin
    Result:=False;
    if (Index<0) or (Index>=Length(Surface.Images.Images)) then Exit;
    if Surface.Images.Image[Index]=nil then Exit;
    Result:=Surface.Images.Image[Index].Width>0;
  end;
  procedure BossImage(Index:Integer;const Bounds:TBreakBlock;Opacity:Double);
  begin
    if not HasBossImage(Index) then Exit;
    Surface.DrawAsset(Index,Point(Round(Left+(Bounds.Left+Bounds.Right)*Scale/2),Round(Top+(Bounds.Top+Bounds.Bottom)*Scale/2)),
    Max(1,Round((Bounds.Right-Bounds.Left)*Scale)),Max(1,Round((Bounds.Bottom-Bounds.Top)*Scale)),Opacity,Index=12);
  end;
  procedure ReactiveBossImage(Index:Integer;const Bounds:TBreakBlock;Flash:Double);
  var
    Reactive:TBreakBlock;
    ContactY,Fraction:Double;
  begin
    Reactive:=Bounds;
    if FPlan.Campaign.BodyContacts and (Flash>0) then begin
      // Compress the upper body while the opaque contact row stays in place.
      ContactY:=Bounds.Top+BreakBossContact(Index,8).Y-BREAK_RADIUS-0.12;
      Fraction:=(ContactY-Bounds.Top)/(Bounds.Bottom-Bounds.Top);
      if Fraction>0.5 then begin Reactive.Top:=Bounds.Top+0.012*Flash;
        Reactive.Bottom:=Reactive.Top+(ContactY-Reactive.Top)/Fraction;
      end;
    end;
    BossImage(9+(Index mod 2),Reactive,1);
  end;
  procedure Plate(CX,CY,HalfWidth,HalfHeight,Turn:Double;Tint:TColor);
  begin
    Line(CX-Cos(Turn)*HalfWidth,CY-Sin(Turn)*HalfWidth,CX+Cos(Turn)*HalfWidth,CY+Sin(Turn)*HalfWidth,Tint,HalfHeight*2);
  end;
  procedure BrokenBrick(Index:Integer;const Brick:TBreakBlock;Age:Double;Tint:TColor);
  var
    J:Integer;
    CX,CY,DX,DY,D,VX,VY,U,PartX,PartY,Speed,Fade:Double;
    Contact:TBreakPoint;
  begin
    if ChunkBudget<=0 then Exit;
    Dec(ChunkBudget);
    U:=Age/0.45;
    Fade:=1-U;
    CX:=(Brick.Left+Brick.Right)/2;
    CY:=(Brick.Top+Brick.Bottom)/2;
    DX:=0;
    DY:=-1;
    // Use the real primary contact. Legacy bonus bricks keep a neutral breakup.
    if (Brick.Source>=0) and (Index<FPlan.PrimaryCount) and FPlan.MainAt(Brick.Time,Contact,D) then begin
      DX:=CX-Contact.X;
      DY:=CY-Contact.Y;
      D:=Hypot(DX,DY);
      if D>1E-8 then begin DX:=DX/D;
        DY:=DY/D;
      end else begin DX:=0;
        DY:=-1;
      end;
    end;
    Speed:=0.34+0.40*Brick.Strength;
    if (Brick.Source<0) and (Brick.Strength>=0.9) then Speed:=Speed*1.55;
    for J:=0 to 2 do begin
      VX:=DX*Speed-DY*(J-1)*0.24;
      VY:=DY*Speed+DX*(J-1)*0.24;
      PartX:=CX+(J-1)*(Brick.Right-Brick.Left)/3+VX*Age;
      PartY:=CY+VY*Age+0.40*Age*Age;
      Plate(PartX,PartY,(Brick.Right-Brick.Left)/6*Fade,(Brick.Bottom-Brick.Top)*0.43*Fade,
      (J-1.25)*Age*9,Mix(Tint,RGB(18,28,48),U));
    end;
    if Age<0.06 then Line(Brick.Left,Brick.Top,Brick.Right,Brick.Bottom,Mix(clWhite,Tint,Age/0.06),0.004*(1-Age/0.06));
  end;
  procedure BossArmor(const Bounds:TBreakBlock;Flash,Health:Double;Tint:TColor);
  var
    K:Integer;
    CX,CY,W,Recoil:Double;
  begin
    W:=(Bounds.Right-Bounds.Left-0.10)/6;
    CY:=(Bounds.Top+Bounds.Bottom)/2;
    for K:=0 to 5 do begin CX:=Bounds.Left+0.05+(K+0.5)*W;
      // The outer contact hull stays still; internal plates kick and recover.
      Recoil:=0.012*Flash*(1+0.12*(K mod 2));
      Plate(CX,CY-Recoil,W*0.44,(Bounds.Bottom-Bounds.Top-0.05)*0.44,
      (K-2.5)*0.045*Flash,Mix(Tint,RGB(51,63,83),(1-Health)*0.35));
    end;
  end;
begin
  Scale:=Min(Frame.Width/BREAK_WIDTH,Frame.Height/BREAK_HEIGHT);
  Left:=(Frame.Width-BREAK_WIDTH*Scale)/2;
  Top:=(Frame.Height-Scale)/2;
  Time:=Max(0.0,Frame.Time);
  for N:=0 to 23 do Line(0,(N+0.5)/24,BREAK_WIDTH,(N+0.5)/24,RGB(13+N div 4,22+N div 3,43+N div 2),1/24+1/Max(1.0,Scale));
  for I:=1 to 15 do Line(I*0.1,0.02,I*0.1,0.96,RGB(28,42,62),0.001);
  for I:=1 to 9 do Line(0.02,I*0.1,1.58,I*0.1,RGB(28,42,62),0.001);
  Line(0,0,0,0.94,RGB(95,149,174),0.005);
  Line(1.6,0,1.6,0.94,RGB(95,149,174),0.005);
  Line(0,0,1.6,0,RGB(95,149,174),0.005);
  if Frame.BackgroundOnly then begin
    if Left>0 then begin Surface.Line(Left/2,0,Left/2,Frame.Height,RGB(10,17,31),Left+1);Surface.Line(Frame.Width-Left/2,0,Frame.Width-Left/2,Frame.Height,RGB(10,17,31),Left+1);end;
    if Top>0 then begin Surface.Line(0,Top/2,Frame.Width,Top/2,RGB(10,17,31),Top+1);Surface.Line(0,Frame.Height-Top/2,Frame.Width,Frame.Height-Top/2,RGB(10,17,31),Top+1);end;Exit;
  end;
  PaddleHalf:=BREAK_PADDLE_HALF_NEW;
  if FPlan<>nil then PaddleHalf:=FPlan.PaddleHalf;
  PaddleX:=BREAK_WIDTH/2;
  PaddleY:=0.90;
  EntryOffset:=0;
  if FPlan<>nil then begin
    Time:=Min(Time,FPlan.EndTime);
    PaddleX:=FPlan.PaddleAt(Time);
    EntryEnd:=Min(0.65,Max(1E-5,FPlan.EndTime));
    if FPlan.Count>0 then EntryEnd:=Min(EntryEnd,FPlan.LaunchTime);
    if EntryEnd>1E-8 then EntryOffset:=0.17*(1-Smooth(Time/EntryEnd));
    PaddleY:=PaddleY+EntryOffset;
    if (FPlan.Count>0) and (Time>FPlan.ExitStart) then begin
      U:=Smooth((Time-FPlan.ExitStart)/1.10);
      PaddleY:=0.90-1.05*U;
      PaddleX:=PaddleX+(0.8-PaddleX)*U;
    end;
    ChunkBudget:=96;
    for I:=0 to FPlan.Count-1 do begin
      if not FPlan.BlockVisible(I,Time) then Continue;
      B:=FPlan.BlockAt(I,Time);
      Age:=Time-B.Time;
      if Age>=0 then B:=FPlan.BlockAt(I,B.Time);
      if Age>=0.45 then Continue;
      if (Age<0) and ((B.Bottom<0) or (B.Top>1)) then Continue;
      Color:=BlockTint(FPlan.BlockRow(I));
      X:=(B.Left+B.Right)/2;
      Y:=(B.Top+B.Bottom)/2;
      if Age<0 then begin
        Box(B.Left,B.Top,B.Right,B.Bottom,RGB(43,62,85));
        Box(B.Left+0.002,B.Top+0.002,B.Right-0.002,B.Bottom-0.003,Color);
        Line(B.Left+0.005,B.Top+0.005,B.Right-0.005,B.Top+0.005,Mix(Color,clWhite,0.55),0.002);
        if (FPlan.ItemCount>0) and (I<FPlan.PrimaryCount) then
        Line(B.Left+0.008,B.Bottom-0.005,B.Left+0.018,B.Bottom-0.005,RGB(239,245,246),0.002);
      end else if Age<0.45 then BrokenBrick(I,B,Age,Color);
    end;
    // Link only real recent destructions; live bricks keep their physical bounds.
    Last:=FPlan.BlockBefore(Time);
    First:=Max(0,FPlan.BlockBefore(Time-0.80)+1);
    Previous:=-1;
    for I:=First to Last do begin B:=FPlan.Block[I];
      if not FPlan.BlockVisible(I,B.Time) then Continue;
      B:=FPlan.BlockAt(I,B.Time);
      X:=(B.Left+B.Right)/2;
      Y:=(B.Top+B.Bottom)/2;
      Age:=Time-B.Time;
      if Previous>=0 then begin Q:=P;
        Line(Q.X,Q.Y,X,Y,Mix(BlockTint(FPlan.BlockRow(I)),RGB(18,28,48),Age/0.80),0.003*(1-Age/0.80));
      end;
      P:=BreakPoint(X,Y);
      Previous:=I;
    end;
    if FPlan.Campaign<>nil then begin
      for I:=0 to FPlan.BossCount-1 do begin
        BossData:=FPlan.Campaign.Boss(I);
        Color:=BlockTint(I+4);
        if (Time>=BossData.Start) and (Time<BossData.Kill) then begin
          B:=BreakBossRect(BossData,Time);
          U:=FPlan.Campaign.FlashAt(I,Time);
          if not HasBossImage(9+(I mod 2)) then begin
            Y:=B.Bottom;
            if FPlan.Campaign.BodyContacts then Y:=B.Top+BreakBossContact(I,8).Y-BREAK_RADIUS-0.12;
            Box(B.Left,B.Top,B.Right,Y,RGB(54,75,111));
            BossArmor(B,U,FPlan.Campaign.HealthAt(I,Time),Color);
            for J:=-1 to 1 do Circle(0.8+J*0.075,(B.Top+B.Bottom)/2,0.018,RGB(255,230,151));
          end;
          ReactiveBossImage(I,B,U);
          U:=FPlan.Campaign.FlashAt(I,Time);
          Box(0.454,0.034,1.146,0.078,RGB(6,12,23));
          Box(0.46,0.04,1.14,0.072,RGB(53,68,88));
          Box(0.46,0.04,0.46+0.68*FPlan.Campaign.HealthAt(I,Time),0.072,Mix(Color,clWhite,0.25+0.55*U));
          Line(0.46,0.04,1.14,0.04,RGB(212,239,255),0.003);
        end;
        Age:=Time-BossData.Kill;
        if (Age>=0) and (Age<0.75) then begin
          U:=Age/0.75;
          begin
            B:=BreakBossRect(BossData,BossData.Kill);
            for J:=0 to 5 do begin X:=B.Left+0.05+(J+0.5)*(B.Right-B.Left-0.10)/6+(J-2.5)*Age*0.18;
              Y:=(B.Top+B.Bottom)/2-Age*(0.18+0.04*(J mod 2))+0.30*Age*Age;
              Plate(X,Y,0.019*(1-U),0.048*(1-U),(J-2.5)*Age*4,Mix(Color,RGB(18,28,48),U));
            end;
          end;
          B.Left:=0.8-0.12-0.22*U;
          B.Right:=1.6-B.Left;
          B.Top:=0.2-0.10-0.22*U;
          B.Bottom:=0.4-B.Top;
          BossImage(12,B,1-U);
          Circle(0.8,0.2,0.03+Age*0.43,Mix(RGB(250,213,112),RGB(18,28,48),U),False);
          Circle(0.8,0.2,0.07*(1-U),Mix(clWhite,RGB(245,142,79),U));
          for J:=0 to 2 do begin Age:=Time-BossData.Kill-J*0.075;
            if (Age>=0) and (Age<0.28) then begin X:=0.8+(J-1)*0.10;
              Y:=0.19+0.03*(J mod 2);
              Circle(X,Y,0.014+Age*0.16,Mix(clWhite,Color,Age/0.28),False);
            end;
          end;
          Age:=Time-BossData.Kill;
          for J:=0 to 23 do begin Angle:=J*2.39996+I*0.7;
            Radius:=Age*(0.14+0.04*(J mod 4));
            Circle(0.8+Cos(Angle)*Radius,0.2+Sin(Angle)*Radius+Age*Age*0.05,0.008*(1-U),Mix(RGB(255,204,105),RGB(18,28,48),U));
          end;
        end;
      end;
      // Saved contacts, not an invisible plane: each flash sits on the actual hull.
      First:=Max(0,FPlan.Campaign.HitBefore(Time-0.09)+1);
      Last:=FPlan.Campaign.HitBefore(Time);
      for I:=First to Last do begin Attack:=FPlan.Campaign.Hit(I);
        Age:=Time-Attack.Path.Hit;
        U:=Age/0.09;
        P:=Attack.Path.B;
        Color:=BlockTint(Attack.Boss+4);
        Circle(P.X,P.Y-BREAK_RADIUS,0.009+0.018*U,Mix(clWhite,Color,U),False);
        for J:=0 to 2 do begin Angle:=-Pi/2+(J-1)*0.7;
          Line(P.X,P.Y-BREAK_RADIUS,P.X+Cos(Angle)*(0.012+0.025*U),P.Y-BREAK_RADIUS+Sin(Angle)*(0.012+0.025*U),Mix(clWhite,Color,U),0.002*(1-U));
        end;
      end;
      for I:=Max(0,FPlan.Campaign.BulletBefore(Time-3.80)+1) to FPlan.Campaign.BulletBefore(Time) do begin
        Enemy:=FPlan.Campaign.Bullet(I);
        Age:=Time-Enemy.Motion.Launch;
        case Enemy.Motion.Pattern of bpPetals:Color:=RGB(255,112,156);
          bpSpiral:Color:=RGB(174,139,255);
          bpFans:Color:=RGB(255,190,72);
          else Color:=RGB(126,232,121);
        end;
        if (Age>=0) and (Time<Enemy.Motion.Finish) then begin
          X:=Enemy.Motion.Origin.X+Enemy.Motion.Velocity.X*Age;
          Y:=Enemy.Motion.Origin.Y+Enemy.Motion.Velocity.Y*Age;
          U:=Min(1.0,(Enemy.Motion.Finish-Time)/0.18);
          Circle(X,Y,0.008*U,Color);
          Circle(X,Y,0.003*U,RGB(255,245,219));
        end else if Enemy.Shield and (Time>=Enemy.Motion.Finish) and (Time<Enemy.Motion.Finish+0.15) then begin
          U:=(Time-Enemy.Motion.Finish)/0.15;
          X:=Enemy.Motion.Origin.X+Enemy.Motion.Velocity.X*(Enemy.Motion.Finish-Enemy.Motion.Launch);
          X:=X+PaddleX-FPlan.PaddleAt(Enemy.Motion.Finish);
          Y:=Enemy.Motion.Origin.Y+Enemy.Motion.Velocity.Y*(Enemy.Motion.Finish-Enemy.Motion.Launch);
          Circle(X,Y,0.008+0.025*U,Mix(Color,RGB(18,28,48),U),False);
        end;
      end;
    end;
    for I:=0 to FPlan.ItemCount-1 do begin
      ItemData:=FPlan.Item(I);
      Color:=BlockTint(FPlan.BlockRow(ItemData.Source));
      if (Time>=ItemData.Drop) and (Time<ItemData.Take) then begin
        B:=FPlan.Block[ItemData.Source];
        U:=(Time-ItemData.Drop)/(ItemData.Take-ItemData.Drop);
        X:=(B.Left+B.Right)/2;
        X:=X+(FPlan.PaddleAt(ItemData.Take)-X)*U;
        Y:=B.Bottom+BREAK_RADIUS;
        Y:=Y+(BREAK_PADDLE_Y-Y)*U;
        Circle(X,Y,0.022,Mix(Color,RGB(18,28,48),0.6),False);
        Box(X-0.014,Y-0.014,X+0.014,Y+0.014,Color);
        for J:=-1 to 1 do Circle(X+J*0.006,Y+Abs(J)*0.003,0.003,RGB(255,251,231));
      end;
      Age:=Time-ItemData.Take;
      if (Age>=0) and (Age<0.35) then Circle(PaddleX,BREAK_PADDLE_Y,0.02+Age*0.18,Mix(Color,RGB(18,28,48),Age/0.35),False);
      if (Time>=ItemData.Take) and (Time<ItemData.Finish) then begin
        U:=(ItemData.Finish-Time)/(ItemData.Finish-ItemData.Take);
        Line(PaddleX-0.10,0.932,PaddleX-0.10+0.20*U,0.932,Color,0.004);
        Circle(PaddleX-0.10,0.932,0.007,Color);
        Circle(PaddleX+0.10,0.932,0.007,Color);
      end;
    end;
    First:=0;
    Last:=FPlan.ExtraCount-1;
    if FPlan.Campaign<>nil then begin First:=Max(0,FPlan.Campaign.ExtraBefore(Time-2.20)+1);
      Last:=FPlan.Campaign.ExtraBefore(Time);
    end;
    for I:=First to Last do if FPlan.ExtraAt(I,Time,P,BallAlpha) then begin
      Color:=BlockTint(I mod 7);
      for J:=3 downto 1 do if FPlan.ExtraAt(I,Time-J*0.025,Q,TrailAlpha) then
      Circle(Q.X,Q.Y,BREAK_RADIUS*0.45*TrailAlpha,Mix(RGB(18,28,48),Color,0.45*TrailAlpha));
      Circle(P.X,P.Y,BREAK_RADIUS*BallAlpha,Mix(RGB(18,28,48),Color,BallAlpha));
      Circle(P.X-0.003,P.Y-0.004,0.004*BallAlpha,Mix(RGB(18,28,48),clWhite,BallAlpha));
    end;
    if FPlan.Campaign<>nil then
    for I:=Max(FPlan.Campaign.BossExtraCount,FPlan.Campaign.NormalExtraBefore(Time-1.1)+1) to FPlan.Campaign.NormalExtraBefore(Time) do
    if FPlan.ExtraAt(I,Time,P,BallAlpha) then begin
      Color:=BlockTint(I mod 7);
      for J:=3 downto 1 do if FPlan.ExtraAt(I,Time-J*0.018,Q,TrailAlpha) then
      Circle(Q.X,Q.Y,BREAK_RADIUS*0.55*TrailAlpha,Mix(RGB(18,28,48),Color,0.55*TrailAlpha));
      Circle(P.X,P.Y,BREAK_RADIUS*BallAlpha,Color);
      Circle(P.X-0.003,P.Y-0.004,0.004*BallAlpha,clWhite);
    end;
    if FPlan.Count>0 then begin
      if FPlan.MainAt(Time,P,Alpha) then begin
        for J:=3 downto 1 do if FPlan.MainAt(Max(0.0,Time-J*0.022),Q,TrailAlpha) then Circle(Q.X,Q.Y+EntryOffset,FPlan.RadiusAt(Time-J*0.022)*(0.65-J*0.12)*Min(Alpha,TrailAlpha),Mix(RGB(18,28,48),RGB(77,121,148),Alpha));
        P.Y:=P.Y+EntryOffset;
        Radius:=FPlan.RadiusAt(Time);
        if Radius>BREAK_RADIUS+0.001 then begin Circle(P.X,P.Y,Radius*1.20*Alpha,RGB(244,130,48),False);
          Circle(P.X,P.Y,Radius*Alpha,RGB(255,190,74));
        end
        else Circle(P.X,P.Y,Radius*Alpha,Mix(RGB(18,28,48),RGB(255,246,214),Alpha));
        Circle(P.X-Radius*0.22,P.Y-Radius*0.28,Radius*0.30*Alpha,Mix(RGB(18,28,48),clWhite,Alpha));
        if FPlan.HeldAt(Time) then Circle(P.X,P.Y,0.022+0.002*Sin(Time*6),RGB(100,195,194),False);
      end;
    end;
  end;
  if (FPlan<>nil) and (FPlan.Count>0) and (Time>FPlan.ExitStart) and (Time<FPlan.EndTime) then
  for J:=1 to 3 do Line(PaddleX-0.07+J*0.035,PaddleY+0.025,PaddleX-0.07+J*0.035,PaddleY+0.09,RGB(52,99,125),0.006);
  Box(PaddleX-PaddleHalf,PaddleY,PaddleX+PaddleHalf,PaddleY+0.019,RGB(98,166,185));
  Line(PaddleX-PaddleHalf+0.012,PaddleY+0.003,PaddleX+PaddleHalf-0.012,PaddleY+0.003,RGB(206,242,237),0.003);
  if Left>0 then begin Surface.Line(Left/2,0,Left/2,Frame.Height,RGB(10,17,31),Left+1);
    Surface.Line(Frame.Width-Left/2,0,Frame.Width-Left/2,Frame.Height,RGB(10,17,31),Left+1);
  end;
  if Top>0 then begin Surface.Line(0,Top/2,Frame.Width,Top/2,RGB(10,17,31),Top+1);
    Surface.Line(0,Frame.Height-Top/2,Frame.Width,Frame.Height-Top/2,RGB(10,17,31),Top+1);
  end;
end;
end.
