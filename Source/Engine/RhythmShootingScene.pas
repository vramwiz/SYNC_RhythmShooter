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
uses System.SysUtils,System.Math,RhythmParallax;
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
  Surface.DrawAsset(Index,Center,W,H,Opacity,Index=12,Bucket);
end;
procedure TShootingAnimation.Explosion(Surface:TAnimationRenderSurface;const P:TRhythmPoint;Age:Double;Boss:Boolean;Width,Height,Direction:Integer);
var Lifetime,LocalAge,Size,Alpha:Double;I:Integer;Burst:TRhythmPoint;
begin
  if Boss then begin Lifetime:=1.35;Size:=0.16+Age*0.20;end
  else begin Lifetime:=0.60;Size:=0.04+Age*0.18;end;
  Alpha:=ExplosionOpacity(Age,Lifetime);if Alpha<=0 then Exit;
  Sprite(Surface,12,P,Size,Width,Height,Direction,Alpha);
  if Boss then for I:=0 to 5 do
  begin
    LocalAge:=Age-I*0.055-0.06;
    Burst.X:=P.X+Cos(I*2.399)*0.07;Burst.Y:=P.Y+Sin(I*2.399)*0.05;
    Sprite(Surface,12,Burst,0.05+Max(0.0,LocalAge)*0.14,Width,Height,Direction,
      ExplosionOpacity(LocalAge,0.7)*0.8);
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
          Sprite(Surface,11,Q,0.018+EnemyBullet.Intensity*0.005,Width,Height,Direction,Alpha);
        end;
      end;
  end;
  Sprite(Surface,6+Direction,StagePoint(Time,Schedule.EntryEnd,Schedule.ExitStart,Schedule.ExitEnd,Schedule.HoldTime),0.078,Width,Height,Direction);

end;
end.
