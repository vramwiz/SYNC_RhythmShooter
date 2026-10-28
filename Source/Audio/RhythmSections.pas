unit RhythmSections;

interface

type
  TRhythmBossCue = record
    StartTime, KillTime: Double;
    QuietBoundary: Boolean;
  end;
  TRhythmBossCues = TArray<TRhythmBossCue>;

function BuildBossCues(const Envelope: TArray<Single>; Duration, SoundEnd: Double;
  const HitTimes: TArray<Double>): TRhythmBossCues;

implementation

uses System.Math;

function BuildBossCues(const Envelope: TArray<Single>; Duration, SoundEnd: Double;
  const HitTimes: TArray<Double>): TRhythmBossCues;
var
  Prefix: TArray<Double>;
  Peak, Mean, EndTime, PreviousKill, Span, Spacing, LowTime, HighTime, Target: Double;
  I, Count: Integer;
  function Energy(A, B: Double): Double;
  var First, Last: Integer;
  begin
    First:=EnsureRange(Floor(A*100),0,Length(Envelope));
    Last:=EnsureRange(Ceil(B*100),First,Length(Envelope));
    if Last=First then Exit(0);
    Result:=(Prefix[Last]-Prefix[First])/(Last-First);
  end;
  function NearestAccent(Time, LowTime, HighTime: Double): Double;
  var Hit, Distance: Double;
  begin
    Result:=Time;Distance:=1E100;
    for Hit in HitTimes do
      if (Hit>=LowTime) and (Hit<=HighTime) and
        (Abs(Hit-Time)<Distance) then begin Result:=Hit;Distance:=Abs(Hit-Time);end;
  end;
  function FindBoundary(LowTime, HighTime, Target: Double; out Found: Boolean): Double;
  var T, Before, After, Score, Best, Distance, Refined, Drop, BestDrop: Double;
    Step, First, Last: Integer;
  begin
    Result:=Target;Found:=False;Best:=0;
    First:=Ceil(LowTime*10);Last:=Floor(HighTime*10);
    for Step:=First to Last do
    begin
      T:=Step/10;
      if T+0.72>Length(Envelope)*0.01 then Continue;
      Before:=Energy(T-2.0,T-0.12);After:=Energy(T+0.12,T+1.6);
      if (Before<Max(Peak*0.20,Mean*1.05)) or (After>Before*0.70) then Continue;
      Distance:=Abs(T-Target)/Max(1.0,HighTime-LowTime);
      Score:=(Before-After)*(1-0.25*Distance);
      if Score>Best then begin Best:=Score;Result:=T;Found:=True;end;
    end;
    if not Found then Exit;
    // 平滑化した候補を実際の落ち込みへ戻し、窓幅による早過ぎる撃破を防ぐ。
    Refined:=Result;BestDrop:=-1;
    First:=Max(Ceil(LowTime*100),Round((Result-0.8)*100));
    Last:=Min(Floor(HighTime*100),Round((Result+0.8)*100));
    for Step:=First to Last do
    begin
      T:=Step/100;Drop:=Energy(T-0.20,T)-Energy(T,T+0.20);
      if Drop>BestDrop then begin BestDrop:=Drop;Refined:=T;end;
    end;
    Result:=NearestAccent(Refined,Refined-0.14,Refined+0.04);
  end;
begin
  Result:=nil;
  if (Duration<=8) or (Length(HitTimes)=0) then Exit;
  SetLength(Prefix,Length(Envelope)+1);Peak:=0;
  for I:=0 to High(Envelope) do
  begin Prefix[I+1]:=Prefix[I]+Envelope[I];Peak:=Max(Peak,Envelope[I]);end;
  Mean:=Prefix[High(Prefix)]/Max(1,Length(Envelope));
  EndTime:=Min(Duration,Max(SoundEnd,HitTimes[High(HitTimes)]));
  if EndTime<=8 then Exit;
  Count:=Max(1,Floor(EndTime/45+0.5));SetLength(Result,Count);
  Spacing:=EndTime/Count;Span:=EnsureRange(Spacing*0.46,8.0,23.0);PreviousKill:=-1;
  for I:=0 to Count-1 do
  begin
    if I=0 then LowTime:=Spacing*0.48 else LowTime:=Spacing*(I+0.28);
    if PreviousKill>=0 then LowTime:=Max(LowTime,PreviousKill+Min(10.0,Spacing*0.25));
    HighTime:=Min(EndTime-0.03,Spacing*(I+1.24));Target:=Min(EndTime-0.08,Spacing*(I+0.92));
    if I=Count-1 then HighTime:=EndTime-0.03;
    Result[I].KillTime:=FindBoundary(LowTime,HighTime,Target,Result[I].QuietBoundary);
    if not Result[I].QuietBoundary then
    begin
      if I=Count-1 then Result[I].KillTime:=Max(HitTimes[High(HitTimes)],EndTime-0.08)
      else Result[I].KillTime:=NearestAccent(Target,LowTime,HighTime);
    end;
    Result[I].StartTime:=Max(0.8,Result[I].KillTime-Span);
    if PreviousKill>=0 then Result[I].StartTime:=Max(Result[I].StartTime,PreviousKill+2.5);
    Result[I].StartTime:=Min(Result[I].StartTime,Result[I].KillTime-2.0);
    PreviousKill:=Result[I].KillTime;
  end;
end;

end.
