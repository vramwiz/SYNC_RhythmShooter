unit RhythmShootingScene;
interface
uses System.Types,RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmMotion,RhythmBarrage,RhythmStage;
type
  TRhythmPoint=RhythmMotion.TRhythmPoint;
  TShootingAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FSchedule:TRhythmStageSchedule;
    FBarrage:TArray<TRhythmEnemyBullet>;
    FFlybys:TArray<TRhythmFlyby>;
    FPlanKey:string;
    function MapPoint(const P:TRhythmPoint;Width,Height,Direction:Integer):TPoint;
    procedure Sprite(Surface:TAnimationRenderSurface;Index:Integer;const P:TRhythmPoint;
      Size:Double;Width,Height,Direction:Integer;Opacity:Double=1);
    procedure Explosion(Surface:TAnimationRenderSurface;const P:TRhythmPoint;
      Age:Double;Boss:Boolean;Width,Height,Direction:Integer);
    procedure EnemyProjectile(Surface:TAnimationRenderSurface;const Bullet:TRhythmEnemyBullet;
      const P:TRhythmPoint;Size:Double;Width,Height,Direction:Integer;Opacity:Double);
  public
    // Audio is borrowed from the existing host/preview cache; never freed here.
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
  end;
function PlayerAt(Time:Double):TRhythmPoint;
function EnemyAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
function BulletAt(const Hit:TRhythmHit;Time:Double):TRhythmPoint;
function ExplosionOpacity(Age,Lifetime:Double):Double;
implementation
uses System.SysUtils,System.Math,RhythmParallax,RhythmShootingAssets;
function PlayerAt(Time: Double): TRhythmPoint;
begin
  Result:=RhythmMotion.PlayerAt(Time);
end;

function EnemyAt(const Hit: TRhythmHit; Time: Double): TRhythmPoint;
var Age,Ease,TargetX: Double;
begin
  Age := EnsureRange((Time - Hit.Time + 1.6)/1.6,0.0,1.0);
  TargetX:=PlayerAt(Hit.Time-Hit.Flight).X;Ease:=Age*Age*(3-2*Age);
  Result.X := Hit.Lane*(1-Ease)+TargetX*Ease+0.07*Sin(Age*Pi)*(1-Age);
  Result.Y := -0.12 + Age * (ImpactPoint(Hit.Lane,Hit.Strength).Y+0.12);
end;

function BulletAt(const Hit: TRhythmHit; Time: Double): TRhythmPoint;
begin
  Result:=PlayerShotAt(psForward,Hit.Time,Hit.Flight,ImpactPoint(Hit.Lane,Hit.Strength).Y,Time);
end;

function ExplosionOpacity(Age,Lifetime:Double):Double;
begin
  if (Age<0) or (Lifetime<=0) or (Age>=Lifetime) then Exit(0);
  Result:=Power(1-Age/Lifetime,1.5);
end;

function TShootingAnimation.MapPoint(const P:TRhythmPoint;Width,Height,Direction:Integer):TPoint;
begin
  if Direction=0 then Result:=Point(Round(P.X*Width),Round(P.Y*Height))
  else Result:=Point(Round((1-P.Y)*Width),Round(P.X*Height));
end;
procedure TShootingAnimation.Sprite(Surface:TAnimationRenderSurface;Index:Integer;const P:TRhythmPoint;
  Size:Double;Width,Height,Direction:Integer;Opacity:Double);
var Center:TPoint;W,H,Swap,Bucket:Integer;
begin
  if Opacity<=0 then Exit;Opacity:=Min(1.0,Opacity);
  Center:=MapPoint(P,Width,Height,Direction);
  // Keep arbitrary custom ship silhouettes inside the existing avoidance
  // corridor, including opaque square imports. Default artwork is unchanged.
  if Index in [6,7] then if Surface.Images.IsCustom[Index] then Size:=Size*0.8;
  W:=Max(2,Round(Size*Min(Width,Height))); H:=W;
  if Index in [9,10] then W:=W*8 div 5;
  if Direction=1 then
  begin
    case Index of 8:Index:=15;9:Index:=16;10:Index:=17;11:Index:=18;13:Index:=19;14:Index:=20;end;
    if Index>=15 then begin Swap:=W;W:=H;H:=Swap;end;
  end;
  Bucket:=0;if (Index in [11,18]) and (Size>0.025) then Bucket:=1;
  if (Index in [11,18]) and (Size>0.04) then Bucket:=2;
  if Index in [SHOOT_BOSS_BULLET_FIRST..SHOOT_BOSS_BULLET_LAST] then begin
    if Size>0.020 then Bucket:=1;if Size>0.022 then Bucket:=2;
  end;
  Surface.DrawAsset(Index,Center,W,H,Opacity,Index=12,Bucket);
end;
procedure TShootingAnimation.EnemyProjectile(Surface:TAnimationRenderSurface;const Bullet:TRhythmEnemyBullet;
  const P:TRhythmPoint;Size:Double;Width,Height,Direction:Integer;Opacity:Double);
var Index:Integer;
begin
  case Bullet.Pattern of
    bpPetals:Index:=SHOOT_BOSS_BULLET_FIRST;
    bpSpiral:Index:=SHOOT_BOSS_BULLET_FIRST+1;
    bpFans:Index:=SHOOT_BOSS_BULLET_FIRST+2;
  else Index:=SHOOT_BOSS_BULLET_FIRST+3;end;
  if Surface.Images.IsCustom[11] then begin
    // Keep the user's shared bullet intact, with a pattern-coloured halo behind it.
    Sprite(Surface,Index,P,Size*1.5,Width,Height,Direction,Opacity*0.8);
    Sprite(Surface,11,P,Size,Width,Height,Direction,Opacity);
  end else Sprite(Surface,Index,P,Size,Width,Height,Direction,Opacity);
end;
procedure TShootingAnimation.Explosion(Surface:TAnimationRenderSurface;const P:TRhythmPoint;Age:Double;Boss:Boolean;Width,Height,Direction:Integer);
var Lifetime,LocalAge,Size,Alpha,U,Magnitude,Seed,Angle,Radius,DX,DY,LocalU,Fade,FlashLife:Double;
  I,Count:Integer;Burst:TRhythmPoint;Center:TPoint;ShortSide:Integer;
  procedure Layer(Index:Integer;X,Y,Diameter,Opacity:Double);
  var Target:TPoint;Pixels:Integer;
  begin
    if (Opacity<=0) or (Diameter<=0) then Exit;
    Target:=Point(Center.X+Round(X*ShortSide),Center.Y+Round(Y*ShortSide));
    Pixels:=Max(2,Round(Diameter*ShortSide));
    Surface.DrawAsset(Index,Target,Pixels,Pixels,Min(1.0,Opacity),True);
  end;
begin
  if Boss then begin Lifetime:=1.35;Size:=0.16+Age*0.20;end
  else begin Lifetime:=0.60;Size:=0.04+Age*0.18;end;
  Alpha:=ExplosionOpacity(Age,Lifetime);if Alpha<=0 then Exit;
  if Surface.Images.IsCustom[12] then begin
    // Preserve the existing custom-image growth, opacity and delayed boss bursts.
    Sprite(Surface,12,P,Size,Width,Height,Direction,Alpha);
    if Boss then for I:=0 to 5 do begin
      LocalAge:=Age-I*0.055-0.06;
      Burst.X:=P.X+Cos(I*2.399)*0.07;Burst.Y:=P.Y+Sin(I*2.399)*0.05;
      Sprite(Surface,12,Burst,0.05+Max(0.0,LocalAge)*0.14,Width,Height,Direction,
        ExplosionOpacity(LocalAge,0.7)*0.8);
    end;
    Exit;
  end;
  // Every layer is reconstructed from absolute age. Screen-space offsets keep
  // rings circular and smoke rising in either scrolling direction/aspect ratio.
  U:=Age/Lifetime;Magnitude:=1;if Boss then Magnitude:=2.2;
  Center:=MapPoint(P,Width,Height,Direction);ShortSide:=Min(Width,Height);
  Seed:=Frac(Abs(P.X*37.17+P.Y*53.11));
  Count:=3;if Boss then Count:=5;
  Fade:=0.45*EnsureRange((U-0.18)/0.18,0.0,1.0)*(1-U);
  for I:=0 to Count-1 do begin
    Angle:=I*2.399963+Seed*2*Pi;
    DX:=Cos(Angle)*(0.010+0.030*U)*Magnitude;
    DY:=(Sin(Angle)*(0.008+0.020*U)-0.010-0.030*U)*Magnitude;
    Layer(SHOOT_SMOKE,DX,DY,(0.032+0.065*U)*Magnitude,Fade);
  end;
  Layer(SHOOT_SHOCKWAVE,0,0,(0.045+0.19*Sqrt(U))*Magnitude,0.75*Power(1-U,1.6));
  Layer(12,0,0,Size*0.92,Alpha);
  Count:=2;if Boss then Count:=5;
  for I:=0 to Count-1 do begin
    LocalAge:=Age-(I+1)*Lifetime*0.055;
    if (LocalAge>=0) and (LocalAge<Lifetime*0.62) then begin
      LocalU:=LocalAge/(Lifetime*0.62);Angle:=I*2.399963+Seed*2*Pi;
      Radius:=(0.009+0.035*LocalU)*Magnitude;
      Fade:=ExplosionOpacity(LocalAge,Lifetime*0.62)*Min(1.0,LocalAge/(Lifetime*0.06))*0.70;
      Layer(12,Cos(Angle)*Radius,Sin(Angle)*Radius-0.010*LocalU*Magnitude,
        (0.026+0.060*LocalU)*Magnitude,Fade);
    end;
  end;
  if U<0.74 then begin
    Count:=8;if Boss then Count:=14;
    Fade:=Power(1-U/0.74,1.4);
    for I:=0 to Count-1 do begin
      Angle:=I*2.399963+Seed*2*Pi;
      Radius:=(0.012+0.11*(1-Sqr(1-U)))*(0.75+0.075*(I mod 4))*Magnitude;
      DX:=Cos(Angle)*Radius;DY:=Sin(Angle)*Radius+0.022*U*U*Magnitude;
      Layer(SHOOT_EMBER,DX*0.82,DY*0.82,0.006*Magnitude,Fade*0.6);
      Layer(SHOOT_SPARK,DX,DY,(0.010-0.004*U)*Magnitude,Fade);
    end;
  end;
  if U>0.42 then begin
    Count:=4;if Boss then Count:=6;
    Fade:=0.60*EnsureRange((U-0.42)/0.12,0.0,1.0)*Power(1-U,1.1);
    for I:=0 to Count-1 do begin
      Angle:=I*2.399963+Seed*2*Pi;
      Radius:=(0.025+0.050*U)*Magnitude;
      Layer(SHOOT_EMBER,Cos(Angle)*Radius,Sin(Angle)*Radius+0.018*U*U*Magnitude,
        0.006*Magnitude,Fade);
    end;
  end;
  FlashLife:=Min(0.12,Lifetime*0.20);
  if Age<FlashLife then begin
    Fade:=Sqr(1-Age/FlashLife);
    Layer(SHOOT_FLASH,0,0,0.055*Magnitude*(1+0.25*Age/FlashLife),Fade);
    Layer(SHOOT_FLASH,0,0,0.030*Magnitude,Fade*0.9);
  end;
end;


procedure TShootingAnimation.Prepare(const Frame:TAnimationFrame);
var Audio:TRhythmAudio;PlanKey:string;Width,Height,Direction,I,J:Integer;Additional:TArray<TRhythmFlyby>;
begin
  Audio:=FAudio;Width:=Frame.Width;Height:=Frame.Height;Direction:=Frame.Direction;FSchedule:=StageSchedule(Audio);
  if Audio=nil then Exit;
  PlanKey:=Audio.Key+'|'+IntToHex(NativeUInt(Audio),16)+'|'+IntToStr(Audio.TimelineRevision)+'|'+IntToStr(Width)+'x'+IntToStr(Height)+'|'+IntToStr(Direction);
  if PlanKey=FPlanKey then Exit;
  FBarrage:=BuildBarrage(Audio,Width,Height,Direction);FFlybys:=BuildFlybys(Audio);
  if Direction=0 then begin
    Additional:=BuildLowerFlybys(Audio);I:=Length(FFlybys);SetLength(FFlybys,I+Length(Additional));
    for J:=0 to High(Additional) do FFlybys[I+J]:=Additional[J];
  end;
  FPlanKey:=PlanKey;
end;
procedure TShootingAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Audio:TRhythmAudio;Schedule:TRhythmStageSchedule;I,J,First,Last,BossIndex,Width,Height,Direction:Integer;
  Time,Age,BossTime,StartTime,Flight,Alpha:Double;H:TRhythmHit;P,Q,Aim:TRhythmPoint;
  EnemyBullet:TRhythmEnemyBullet;Enemy:TRhythmFlyby;
begin
  Audio:=FAudio;Schedule:=FSchedule;Time:=Frame.Time;Width:=Frame.Width;Height:=Frame.Height;Direction:=Frame.Direction;
  DrawParallax(Surface.Canvas,Surface.Images,Surface.D2D,Surface.D2DActive,Time,Width,Height,Direction,-1,False,False);
  if Audio<>nil then
  begin
    for Enemy in FFlybys do if (Time>=Enemy.Launch) and (Time<Enemy.Finish) and ((Direction<>0) or (Time<Schedule.ClearTime)) then
    begin
      P:=FlybyAt(Enemy,Time);J:=8;if Enemy.Variant=1 then J:=13 else if Enemy.Variant=2 then J:=14;
      if Enemy.Route<>frUpperCross then J:=21+Enemy.Variant;
      Alpha:=Min(1.0,Min((Time-Enemy.Launch)/0.3,(Enemy.Finish-Time)/0.4));
      Sprite(Surface,J,P,Enemy.Size,Width,Height,Direction,Alpha*0.9);
    end;
    First:=Max(0,Audio.NearestHit(Time-0.6)-1);Last:=Min(High(Audio.Hits),Audio.NearestHit(Time+1.6)+1);
    for I:=First to Last do
    begin
      H:=Audio.Hits[I];Age:=Time-H.Time;
      J:=8;if I mod 3=1 then J:=13 else if I mod 3=2 then J:=14;
      if (Age>=-1.6) and (Age<0) then Sprite(Surface,J,EnemyAt(H,Time),0.065,Width,Height,Direction);
      if (Age>=-H.Flight) and (Age<0) then Sprite(Surface,11,BulletAt(H,Time),0.027,Width,Height,Direction);
      if (Age>=0) and (Age<0.6) then Explosion(Surface,EnemyAt(H,H.Time),Age,False,Width,Height,Direction);
    end;
    // 盛り上がり後の静かな区切りへ撃破を合わせ、長めの戦闘区間を共有する。
    if (Audio.Duration>8) and (Length(Audio.Hits)>0) then
      for BossIndex:=0 to Audio.BossCount-1 do
      begin
        BossTime:=BossKillTime(Audio,BossIndex);if BossTime<0 then Continue;
        StartTime:=BossStartTime(Audio,BossIndex);Age:=Time-BossTime;
        P:=BossAt(BossTime,StartTime,Time);
        if (Time>=StartTime) and (Age<0) then
        begin
          Sprite(Surface,9+(BossIndex mod 2),P,0.18,Width,Height,Direction);
        end;
        Age:=Time-BossTime;
        Aim:=BossAt(BossTime,StartTime,BossTime);Flight:=ShotFlightToY(BossTime,0.19);
        if (Age>=-Flight) and (Age<0) then
        begin
          Q:=PlayerShotAt(psForward,BossTime,Flight,0.19,Time);
          Sprite(Surface,11,Q,0.045,Width,Height,Direction);
        end;
        if (Age>=0) and (Age<1.35) then Explosion(Surface,Aim,Age,True,Width,Height,Direction);
      end;
    if Time<Schedule.ClearTime then for EnemyBullet in FBarrage do
      if (Time>=EnemyBullet.Launch) and (Time<EnemyBullet.Finish) then
      begin
        Q:=EnemyBulletAt(EnemyBullet,Time);
        if (Q.X>=-0.05) and (Q.X<=1.05) and (Q.Y>=-0.05) and (Q.Y<=1.05) then
        begin
          BossTime:=BossKillTime(Audio,EnemyBullet.Boss);
          Alpha:=EnsureRange((BossTime+0.45-Time)/0.45,0.0,1.0);
          EnemyProjectile(Surface,EnemyBullet,Q,0.018+EnemyBullet.Intensity*0.005,Width,Height,Direction,Alpha);
        end;
      end;
  end;
  Sprite(Surface,6+Direction,StagePoint(Time,Schedule.EntryEnd,Schedule.ExitStart,Schedule.ExitEnd,Schedule.HoldTime),0.078,Width,Height,Direction);

end;
end.
