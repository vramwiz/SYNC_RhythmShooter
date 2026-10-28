unit RhythmBarrage;
interface
uses RhythmAudio, RhythmMotion;
type
  TRhythmEnemyBullet=record
    Launch,Finish:Double;
    Origin,Velocity:TRhythmPoint;
  end;
function BossAt(KillTime,StartTime,Time:Double):TRhythmPoint;
function EnemyBulletAt(const Bullet:TRhythmEnemyBullet;Time:Double):TRhythmPoint;
function BuildBarrage(Audio:TRhythmAudio;Width,Height,Direction:Integer):TArray<TRhythmEnemyBullet>;
implementation
uses System.Math, System.Generics.Collections,RhythmStage;
function BossAt(KillTime,StartTime,Time:Double):TRhythmPoint;
var Blend,Flight:Double;Aim:TRhythmPoint;
begin
  Flight:=ShotFlightToY(KillTime,0.19);Aim:=PlayerAt(KillTime-Flight);
  Blend:=EnsureRange((Time-KillTime+1.2)/1.2,0.0,1.0);Blend:=Blend*Blend*(3-2*Blend);
  Result.X:=(0.5+0.08*Sin(Time*1.2))*(1-Blend)+Aim.X*Blend;
  Result.Y:=0.19-Min(0.0,Time-StartTime-0.7)*0.4;
end;
function EnemyBulletAt(const Bullet:TRhythmEnemyBullet;Time:Double):TRhythmPoint;
begin Result.X:=Bullet.Origin.X+Bullet.Velocity.X*(Time-Bullet.Launch);Result.Y:=Bullet.Origin.Y+Bullet.Velocity.Y*(Time-Bullet.Launch);end;
function BuildBarrage(Audio:TRhythmAudio;Width,Height,Direction:Integer):TArray<TRhythmEnemyBullet>;
var List:TList<TRhythmEnemyBullet>;Boss,I,J,K,N:Integer;Kill,Start,Angle,Speed,T,Radius,ScaleX,ScaleY,EntryEnd,ExitStart,ExitEnd:Double;
  B:TRhythmEnemyBullet;P,Ship:TRhythmPoint;Safe:Boolean;Schedule:TRhythmStageSchedule;
begin
  Result:=nil;if (Audio=nil) or (Audio.Duration<=8) or (Length(Audio.Hits)=0) then Exit;
  if Direction=0 then begin ScaleX:=Min(Width,Height)/Width;ScaleY:=Min(Width,Height)/Height;end
  else begin ScaleX:=Min(Width,Height)/Height;ScaleY:=Min(Width,Height)/Width;end;
  Radius:=0.061;
  StageTimes(Audio,EntryEnd,ExitStart,ExitEnd);
  Schedule:=StageSchedule(Audio);
  List:=TList<TRhythmEnemyBullet>.Create;
  try
    for Boss:=0 to 1 do
    begin
      Kill:=BossKillTime(Audio,Boss);Start:=Kill-Min(6.0,Audio.Duration*0.18);
      for I:=0 to High(Audio.Hits) do
      begin
        B.Launch:=Audio.Hits[I].Time;if (B.Launch<Start) or (B.Launch>=Kill-0.1) then Continue;
        B.Finish:=B.Launch+4.2;B.Origin:=BossAt(Kill,Start,B.Launch);
        N:=48;if Audio.Hits[I].Strength>0.7 then N:=64;
        for J:=0 to N-1 do
        begin
          Angle:=J*2*Pi/N+(I mod 13)*0.19+Boss*0.11;
          Speed:=0.42+(J mod 3)*0.035;
          B.Velocity.X:=Cos(Angle)*Speed*ScaleX;B.Velocity.Y:=Sin(Angle)*Speed*ScaleY;
          Safe:=True;
          // Reserve the complete known ship trajectory before publishing a
          // projectile. Unsafe rays are omitted at emission, never warped later.
          for K:=0 to 504 do
          begin
            T:=B.Launch+K/120;P:=EnemyBulletAt(B,T);Ship:=StagePoint(T,EntryEnd,ExitStart,ExitEnd,Schedule.HoldTime);
            if Hypot((P.X-Ship.X)/ScaleX,(P.Y-Ship.Y)/ScaleY)<Radius then begin Safe:=False;Break;end;
          end;
          if Safe then List.Add(B);
        end;
      end;
    end;
    Result:=List.ToArray;
  finally List.Free;end;
end;
end.
