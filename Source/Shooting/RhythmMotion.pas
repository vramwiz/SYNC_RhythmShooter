unit RhythmMotion;
interface
type TRhythmPoint=record X,Y:Double;end;
type TPlayerShotPattern=(psForward);
function PlayerAt(Time:Double):TRhythmPoint;
function ImpactPoint(Lane,Strength:Double):TRhythmPoint;
function ShotFlightToY(HitTime,TargetY:Double):Double;
function ShotFlightTime(HitTime,Lane,Strength:Double):Double;
function PlayerShotAt(Pattern:TPlayerShotPattern;HitTime,Flight,TargetY,Time:Double):TRhythmPoint;
implementation
uses System.Math;
function PlayerAt(Time:Double):TRhythmPoint;
begin Result.X:=0.5+0.23*Sin(Time*0.83)+0.04*Sin(Time*2.17);Result.Y:=0.83+0.025*Sin(Time*1.37);end;
function ImpactPoint(Lane,Strength:Double):TRhythmPoint;
begin Result.X:=Lane;Result.Y:=0.27+Strength*0.08;end;
function ShotFlightToY(HitTime,TargetY:Double):Double;
const BulletSpeed=1.25;
var I:Integer;Origin:TRhythmPoint;
begin
  Result:=Min(HitTime,0.5);
  for I:=0 to 11 do
  begin Origin:=PlayerAt(HitTime-Result);Result:=Min(HitTime,(Origin.Y-TargetY)/BulletSpeed);end;
end;
function ShotFlightTime(HitTime,Lane,Strength:Double):Double;
begin Result:=ShotFlightToY(HitTime,ImpactPoint(Lane,Strength).Y);end;
function PlayerShotAt(Pattern:TPlayerShotPattern;HitTime,Flight,TargetY,Time:Double):TRhythmPoint;
var Origin:TRhythmPoint;Phase:Double;
begin
  Origin:=PlayerAt(HitTime-Flight);Phase:=EnsureRange((Time-HitTime+Flight)/Max(0.001,Flight),0.0,1.0);
  Result.X:=Origin.X;Result.Y:=Origin.Y+(TargetY-Origin.Y)*Phase;
end;
end.
