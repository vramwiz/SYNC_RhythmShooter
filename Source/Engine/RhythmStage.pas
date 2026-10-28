unit RhythmStage;
interface
uses RhythmAudio,RhythmMotion;
type
  TRhythmStageState=(ssEntering,ssPlaying,ssDefeat,ssClear,ssExiting,ssEnded);
  TRhythmStageSchedule=record
    EntryEnd,SoundEnd,HoldTime,ClearTime,ExitStart,ExitEnd:Double;
  end;
function AudibleEnd(Audio:TRhythmAudio):Double;
function BossKillTime(Audio:TRhythmAudio;Boss:Integer):Double;
function StageSchedule(Audio:TRhythmAudio):TRhythmStageSchedule;
function StageStateAt(const Schedule:TRhythmStageSchedule;Time:Double):TRhythmStageState;
procedure StageTimes(Audio:TRhythmAudio;out EntryEnd,ExitStart,ExitEnd:Double);
function StagePlayerAt(Audio:TRhythmAudio;Time:Double):TRhythmPoint;
function StagePoint(Time,EntryEnd,ExitStart,ExitEnd:Double;HoldTime:Double=1E100):TRhythmPoint;
implementation
uses System.Math;
function AudibleEnd(Audio:TRhythmAudio):Double;
begin Result:=0;if Audio<>nil then Result:=Audio.SoundEnd;end;
function BossKillTime(Audio:TRhythmAudio;Boss:Integer):Double;
var I:Integer;
begin
  Result:=-1;if (Audio=nil) or (Audio.Duration<=8) or (Length(Audio.Hits)=0) then Exit;
  if Boss=0 then I:=Audio.NearestHit(Audio.Duration*0.5) else I:=High(Audio.Hits);
  Result:=Audio.Hits[I].Time;
  if Boss=1 then Result:=Max(Result,AudibleEnd(Audio)-0.08);
end;
function StageSchedule(Audio:TRhythmAudio):TRhythmStageSchedule;
var H:TRhythmHit;FirstShot,LastHit,Kill:Double;
begin
  Result:=Default(TRhythmStageSchedule);Result.HoldTime:=1E100;Result.ClearTime:=1E100;Result.ExitStart:=1E100;Result.ExitEnd:=1E100;
  if Audio=nil then Exit;
  Result.SoundEnd:=AudibleEnd(Audio);LastHit:=0;FirstShot:=1E100;
  for H in Audio.Hits do begin FirstShot:=Min(FirstShot,H.Time-H.Flight);LastHit:=Max(LastHit,H.Time);end;
  Result.HoldTime:=Max(Result.SoundEnd,LastHit);Kill:=BossKillTime(Audio,1);
  Result.ClearTime:=Result.HoldTime;
  if Kill>=0 then Result.ClearTime:=Max(Result.ClearTime,Kill+0.6)
  else if Result.SoundEnd>0 then Result.ClearTime:=Result.ClearTime+0.12;
  // Even silence and very short clips reach a terminal state; the host length
  // is unchanged. Any extra output shows the deterministic departure.
  Result.ExitStart:=Result.ClearTime+0.20;
  if Audio.Duration-Result.ExitStart>=0.22 then Result.ExitEnd:=Result.ExitStart+Min(0.65,Audio.Duration-Result.ExitStart)
  else Result.ExitEnd:=Result.ExitStart+0.65;
  if FirstShot>=0.4 then Result.EntryEnd:=Min(1.4,Min(FirstShot-0.10,Result.HoldTime-0.10));
  if Result.EntryEnd<0.3 then Result.EntryEnd:=0;
end;
function StageStateAt(const Schedule:TRhythmStageSchedule;Time:Double):TRhythmStageState;
begin
  if Time>=Schedule.ExitEnd then Exit(ssEnded);
  if Time>=Schedule.ExitStart then Exit(ssExiting);
  if Time>=Schedule.ClearTime then Exit(ssClear);
  if Time>=Schedule.HoldTime then Exit(ssDefeat);
  if Time<Schedule.EntryEnd then Exit(ssEntering);
  Result:=ssPlaying;
end;
procedure StageTimes(Audio:TRhythmAudio;out EntryEnd,ExitStart,ExitEnd:Double);
var S:TRhythmStageSchedule;
begin S:=StageSchedule(Audio);EntryEnd:=S.EntryEnd;ExitStart:=S.ExitStart;ExitEnd:=S.ExitEnd;end;
function StagePlayerAt(Audio:TRhythmAudio;Time:Double):TRhythmPoint;
var S:TRhythmStageSchedule;
begin
  S:=StageSchedule(Audio);Result:=StagePoint(Time,S.EntryEnd,S.ExitStart,S.ExitEnd,S.HoldTime);
end;
function StagePoint(Time,EntryEnd,ExitStart,ExitEnd,HoldTime:Double):TRhythmPoint;
var U:Double;Anchor:TRhythmPoint;
begin
  Result:=PlayerAt(Time);
  if (EntryEnd>0) and (Time<EntryEnd) then
  begin
    U:=EnsureRange(Time/EntryEnd,0.0,1.0);U:=U*U*(3-2*U);
    Result.Y:=1.16*(1-U)+Result.Y*U;
  end;
  if Time>=HoldTime then Result:=PlayerAt(HoldTime);
  if Time>=ExitStart then
  begin
    Anchor:=PlayerAt(Min(HoldTime,ExitStart));U:=EnsureRange((Time-ExitStart)/Max(0.0001,ExitEnd-ExitStart),0.0,1.0);
    Result.X:=Anchor.X;Result.Y:=Anchor.Y+(-0.25-Anchor.Y)*U*U;
  end;
end;
end.
