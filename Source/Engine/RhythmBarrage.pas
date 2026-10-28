unit RhythmBarrage;
interface
uses RhythmAudio, RhythmMotion;
type
  TRhythmBarragePattern=(bpPetals,bpSpiral,bpFans,bpCross);
  TRhythmEnemyBullet=record
    Launch,Finish:Double;
    Origin,Velocity:TRhythmPoint;
    Boss:Integer;
    Pattern:TRhythmBarragePattern;
    Intensity:Double;
  end;
  TRhythmFlyby=record
    Launch,Finish,Lane,Phase,Size:Double;
    FromLeft:Boolean;
    Variant:Integer;
  end;
function BossAt(KillTime,StartTime,Time:Double):TRhythmPoint;
function EnemyBulletAt(const Bullet:TRhythmEnemyBullet;Time:Double):TRhythmPoint;
function BuildBarrage(Audio:TRhythmAudio;Width,Height,Direction:Integer):TArray<TRhythmEnemyBullet>;
function BuildFlybys(Audio:TRhythmAudio):TArray<TRhythmFlyby>;
function FlybyAt(const Enemy:TRhythmFlyby;Time:Double):TRhythmPoint;
implementation
uses System.Math, System.Generics.Collections,RhythmStage;
function BossAt(KillTime,StartTime,Time:Double):TRhythmPoint;
var Blend,Flight,Entry:Double;Aim:TRhythmPoint;
begin
  Flight:=ShotFlightToY(KillTime,0.19);Aim:=PlayerAt(KillTime-Flight);
  Blend:=EnsureRange((Time-KillTime+1.2)/1.2,0.0,1.0);Blend:=Blend*Blend*(3-2*Blend);
  Result.X:=(0.5+0.14*Sin((Time-StartTime)*0.63))*(1-Blend)+Aim.X*Blend;
  Entry:=EnsureRange((Time-StartTime)/1.8,0.0,1.0);Entry:=Entry*Entry*(3-2*Entry);
  Result.Y:=-0.22+0.41*Entry;
end;
function EnemyBulletAt(const Bullet:TRhythmEnemyBullet;Time:Double):TRhythmPoint;
begin Result.X:=Bullet.Origin.X+Bullet.Velocity.X*(Time-Bullet.Launch);Result.Y:=Bullet.Origin.Y+Bullet.Velocity.Y*(Time-Bullet.Launch);end;
function BuildBarrage(Audio:TRhythmAudio;Width,Height,Direction:Integer):TArray<TRhythmEnemyBullet>;
var List:TList<TRhythmEnemyBullet>;Boss,J,K,N,Sequence,Sample,LastSample:Integer;
  Kill,Start,Angle,Speed,T,ScaleX,ScaleY,Track,Progress,Level,Interval,Radius2,DX,DY:Double;
  B:TRhythmEnemyBullet;P,Origin:TRhythmPoint;Ship:TArray<TRhythmPoint>;Safe:Boolean;Schedule:TRhythmStageSchedule;
begin
  Result:=nil;if (Audio=nil) or (Audio.Duration<=8) or (Length(Audio.Hits)=0) or (Width<=0) or (Height<=0) then Exit;
  if Direction=0 then begin ScaleX:=Min(Width,Height)/Width;ScaleY:=Min(Width,Height)/Height;end
  else begin ScaleX:=Min(Width,Height)/Height;ScaleY:=Min(Width,Height)/Width;end;
  Schedule:=StageSchedule(Audio);Radius2:=Sqr(0.065);
  // 自機の軌跡を一度だけ用意し、多数の弾ごとに三角関数を再計算しない。
  SetLength(Ship,Ceil((Audio.Duration+5)*120)+2);
  for K:=0 to High(Ship) do Ship[K]:=StagePoint(K/120,Schedule.EntryEnd,Schedule.ExitStart,Schedule.ExitEnd,Schedule.HoldTime);
  List:=TList<TRhythmEnemyBullet>.Create;
  try
    for Boss:=0 to Audio.BossCount-1 do
    begin
      Kill:=BossKillTime(Audio,Boss);if Kill<0 then Continue;
      Start:=BossStartTime(Audio,Boss);T:=Start+1.6;Sequence:=0;
      while T<Kill-0.18 do
      begin
        Track:=EnsureRange(T/Max(1.0,Audio.SoundEnd),0.0,1.0);
        Progress:=EnsureRange((T-Start)/Max(1.0,Kill-Start),0.0,1.0);
        Level:=Audio.LevelAt(T);
        B.Intensity:=EnsureRange(0.18+Track*0.45+Progress*0.30+Level*0.12,0.2,1.0);
        B.Boss:=Boss;B.Pattern:=TRhythmBarragePattern(Boss mod 4);
        B.Launch:=T;B.Finish:=Min(T+4.2,Kill+0.45);Origin:=BossAt(Kill,Start,T);
        if Boss=0 then begin N:=24+Round(18*B.Intensity);Interval:=0.52-B.Intensity*0.20;end
        else begin N:=40+Round(48*B.Intensity)+Boss*6;Interval:=0.36-B.Intensity*0.20;end;
        if B.Pattern=bpCross then N:=Round(N*1.35);
        Sample:=Max(0,Floor(B.Launch*120));LastSample:=Min(High(Ship),Ceil(B.Finish*120));
        for J:=0 to N-1 do
        begin
          B.Origin:=Origin;
          case B.Pattern of
          bpPetals:begin
            Angle:=J*2*Pi/N+Sequence*0.13;
            Speed:=0.25+B.Intensity*0.18+0.09*Sqr(Sin(Angle*5+Sequence*0.21));
          end;
          bpSpiral:begin
            Angle:=J*2*Pi/N+Sequence*0.43+0.17*Sin(Sequence*0.37);
            Speed:=0.34+B.Intensity*0.30+(J mod 3)*0.035;
          end;
          bpFans:begin
            Angle:=Pi/2+0.65*Sin(Sequence*0.27)+(J/(N-1)-0.5)*2.2;
            Speed:=0.30+B.Intensity*0.38+(J mod 4)*0.018;
          end;
          else begin
            B.Origin.X:=Origin.X+(2*(J mod 2)-1)*0.10;
            Angle:=Pi/2+(2*(J mod 2)-1)*0.55+0.24*Sin(Sequence*0.21)+((J div 2)-(N div 4))*0.014;
            Speed:=0.36+B.Intensity*0.34+(J mod 3)*0.025;
          end;
          end;
          B.Velocity.X:=Cos(Angle)*Speed*ScaleX;B.Velocity.Y:=Sin(Angle)*Speed*ScaleY;
          Safe:=True;
          // 危険な弾は発射時に省く。表示中の弾道を曲げたり途中消去したりしない。
          for K:=Sample to LastSample do
          begin
            P:=EnemyBulletAt(B,K/120);DX:=(P.X-Ship[K].X)/ScaleX;DY:=(P.Y-Ship[K].Y)/ScaleY;
            if DX*DX+DY*DY<Radius2 then begin Safe:=False;Break;end;
          end;
          if Safe then List.Add(B);
        end;
        Inc(Sequence);T:=T+Interval;
      end;
    end;
    Result:=List.ToArray;
  finally List.Free;end;
end;
function BuildFlybys(Audio:TRhythmAudio):TArray<TRhythmFlyby>;
var List:TList<TRhythmFlyby>;Enemy:TRhythmFlyby;T,Progress,Level:Double;Wave,J,Count:Integer;
begin
  Result:=nil;if (Audio=nil) or (Audio.SoundEnd<=0) then Exit;
  List:=TList<TRhythmFlyby>.Create;
  try
    T:=1.2;Wave:=0;
    while T<Audio.SoundEnd-0.5 do
    begin
      Progress:=T/Max(1.0,Audio.SoundEnd);Level:=Audio.LevelAt(T);
      Count:=3+Round(Progress*2+Level);
      for J:=0 to Count-1 do
      begin
        Enemy.Launch:=T+J*0.17;Enemy.Finish:=Enemy.Launch+4.6-Progress*1.0;
        Enemy.Lane:=0.08+((Wave*7+J*3) mod 5)*0.03;
        Enemy.Phase:=Wave*0.7+J*0.31;Enemy.Size:=0.037+((Wave+J) mod 3)*0.006;
        Enemy.FromLeft:=Wave mod 2=0;Enemy.Variant:=(Wave+J) mod 3;
        List.Add(Enemy);
      end;
      Inc(Wave);T:=T+2.6-Progress*1.0-Level*0.35;
    end;
    Result:=List.ToArray;
  finally List.Free;end;
end;
function FlybyAt(const Enemy:TRhythmFlyby;Time:Double):TRhythmPoint;
var U:Double;
begin
  U:=EnsureRange((Time-Enemy.Launch)/Max(0.01,Enemy.Finish-Enemy.Launch),0.0,1.0);
  if Enemy.FromLeft then Result.X:=-0.12+1.24*U else Result.X:=1.12-1.24*U;
  // 通常弾の命中列より上を通過させ、撃破対象とは別の編隊にする。
  Result.Y:=Enemy.Lane+0.035*Sin(U*2*Pi+Enemy.Phase);
end;
end.
