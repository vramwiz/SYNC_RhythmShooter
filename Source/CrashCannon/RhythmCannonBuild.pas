unit RhythmCannonBuild;
// 曲の区切りに決着を置き、その前の命中・反撃・砲弾の発射を割り当てる。
interface

uses System.SysUtils,RhythmAudio,RhythmCannonPlan;

function BuildCannonPlan(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TCannonPlan;

implementation

uses System.Math,RhythmCannonTargets;

function FirstHit(Audio:TRhythmAudio;Time:Double):Integer;
var Hi,Mid:Integer;
begin
  Result:=0;
  Hi:=Length(Audio.Hits);
  while Result<Hi do begin
    Mid:=(Result+Hi) div 2;
    if Audio.Hits[Mid].Time<Time then Result:=Mid+1 else Hi:=Mid;
  end;
end;

function Accent(Audio:TRhythmAudio;LowTime,HighTime,Preferred,Weight:Double;
  PreferBreak:Boolean=False):Integer;
var I:Integer; Score,Best,Time:Double;
begin
  Result:=-1;
  Best:=-1E9;
  I:=FirstHit(Audio,LowTime);
  while (I<Length(Audio.Hits)) and (Audio.Hits[I].Time<=HighTime) do begin
    Time:=Audio.Hits[I].Time;
    Score:=Audio.Hits[I].Strength-Weight*Abs(Time-Preferred);
    if PreferBreak then
      Score:=Score+0.55*Max(0.0,Audio.LevelAt(Time-0.22)-Audio.LevelAt(Time+0.38));
    if Score>Best then begin
      Best:=Score;
      Result:=I;
    end;
    Inc(I);
  end;
end;

procedure ScoreStage(Stage:TCannonStage;Audio:TRhythmAudio;var Counter:Integer;
  IsFinal:Boolean;const Cancel:TFunc<Boolean>);
var
  FinishIndex,Index,LaunchIndex,I,N,Nearby,Count,CounterGoal,StageCounters,NextCounter:Integer;
  Chosen:array[0..CannonMaxCues-1] of Integer;
  Settle,Last,Gap,Span,Time,Minimum,Maximum,Preference,Lead,Energy,Entry,LastEnemy:Double;
  Cue:TCannonCue;
  Boss,IsCounter:Boolean;

  procedure Add(HitIndex:Integer;FinalHit,Reply:Boolean);
  begin
    Time:=Audio.Hits[HitIndex].Time;
    Cue:=Default(TCannonCue);
    Cue.Time:=Time;
    Cue.Power:=EnsureRange(Double(Audio.Hits[HitIndex].Strength),0.0,1.0);
    Energy:=EnsureRange(Audio.LevelAt(Time),0.0,1.0);
    Nearby:=FirstHit(Audio,Time+0.70)-FirstHit(Audio,Time-0.64);
    Cue.Volley:=1;
    if N>=2 then begin
      if (Nearby>=4) or (Cue.Power+Energy*0.35>=0.66) then Inc(Cue.Volley);
      if ((Nearby>=7) and (Cue.Power+Energy*0.45>=0.61)) or
        (Cue.Power+Energy*0.45>=0.92) then Inc(Cue.Volley);
      if (Cue.Volley=3) and (Nearby>=10) and (Cue.Power+Energy*0.48>=0.82) then Inc(Cue.Volley);
    end;
    if FinalHit then begin
      Cue.Power:=Max(Cue.Power,0.73+0.27*Ord(IsFinal));
      if Boss and (Time-Stage.Start>1.1) then Cue.Volley:=Max(Cue.Volley,3+Ord(IsFinal));
    end;
    if Reply then begin
      Cue.Enemy:=TCannonEnemy(1+Counter mod Ord(High(TCannonEnemy)));
      Cue.Volley:=0;
      Cue.Lead:=Min(0.68,Time-Stage.Start);
      LaunchIndex:=Accent(Audio,Max(Stage.Start,Time-0.80),Time-0.49,Time-Cue.Lead,2.6);
      if LaunchIndex>=0 then Cue.Lead:=Time-Audio.Hits[LaunchIndex].Time;
      Inc(Counter);
      LastEnemy:=Time;
    end else begin
      Lead:=Min(0.61+0.16*Cue.Power,Time-Stage.Start);
      Minimum:=Max(Stage.Start,Time-0.89);
      Maximum:=Time-0.39;
      LaunchIndex:=Accent(Audio,Minimum,Maximum,Time-Lead,2.6);
      if LaunchIndex>=0 then Lead:=Time-Audio.Hits[LaunchIndex].Time;
      Cue.Lead:=Lead;
    end;
    Stage.Cues[N]:=Cue;
    Inc(N);
  end;

begin
  Span:=Stage.Stop-Stage.Start;
  Boss:=CannonBoss(Stage.Kind);
  Settle:=Min(IfThen(Boss,1.46,0.95),Span*0.31);
  if IsFinal then Settle:=Min(1.60,Span*0.34);
  Entry:=Min(0.53,Span*0.30);
  Preference:=Stage.Stop-Settle;
  FinishIndex:=Accent(Audio,Max(Stage.Start+Entry,Preference-Min(2.15,Span*0.37)),
    Preference,Preference,0.57,True);
  if FinishIndex<0 then
    FinishIndex:=Accent(Audio,Stage.Start+Min(0.13,Span*0.13),
      Stage.Stop-Min(0.035,Span*0.12),Preference,0.15,True);
  if FinishIndex<0 then begin
    Stage.Resolve;
    Exit;
  end;
  SetLength(Stage.Cues,CannonMaxCues);
  Last:=Stage.Start+Entry;
  LastEnemy:=Stage.Start-1.12;
  Count:=0;
  while Count<CannonMaxCues-1 do begin
    if Assigned(Cancel) and Cancel() then Abort;
    if Boss then Gap:=0.47 else Gap:=0.26;
    if Count=0 then Gap:=0;
    Minimum:=Last+Gap;
    Maximum:=Audio.Hits[FinishIndex].Time-Max(0.21,Gap*0.73);
    Index:=FirstHit(Audio,Minimum);
    if (Index>=FinishIndex) or (Audio.Hits[Index].Time>Maximum) then Break;
    Index:=Accent(Audio,Audio.Hits[Index].Time,Min(Maximum,Audio.Hits[Index].Time+0.09),
      Audio.Hits[Index].Time,0.9);
    Chosen[Count]:=Index;
    Last:=Audio.Hits[Index].Time;
    Inc(Count);
  end;
  Chosen[Count]:=FinishIndex;
  Inc(Count);
  // 先に着弾候補をそろえ、最終弾と避ける余白を確保してから反撃を配る。
  CounterGoal:=0;
  if Boss then CounterGoal:=Max(0,Min(Count-2,Round(Count/3)));
  StageCounters:=0;
  N:=0;
  for I:=0 to Count-1 do begin
    NextCounter:=Max(1,Round((StageCounters+1)*Count/(CounterGoal+1))-1);
    Time:=Audio.Hits[Chosen[I]].Time;
    IsCounter:=(StageCounters<CounterGoal) and (I>=NextCounter) and (I<Count-1) and
      (Time>=Stage.Start+0.91) and (Time>=LastEnemy+1.12) and
      (Audio.Hits[FinishIndex].Time-Time>0.36);
    if IsCounter then Inc(StageCounters);
    Add(Chosen[I],I=Count-1,IsCounter);
  end;
  SetLength(Stage.Cues,Count);
  Stage.Resolve;
end;

function BuildCannonPlan(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TCannonPlan;
var Stage:TCannonStage; ActiveEnd,Start,Boundary:Double;
  Count,I,Normal,Bosses,Counter:Integer;
  Boss,IsFinal:Boolean;
begin
  if (Audio=nil) or (Audio.Duration<=0) or IsNan(Audio.Duration) or IsInfinite(Audio.Duration) then
    raise EArgumentException.Create('Cannon audio duration');
  Result:=TCannonPlan.Create;
  try
    Result.Duration:=Audio.Duration;
    ActiveEnd:=Audio.SoundEnd;
    if (ActiveEnd<=0) or (Length(Audio.Hits)=0) then ActiveEnd:=Audio.Duration;
    if Length(Audio.Hits)>0 then
      ActiveEnd:=EnsureRange(Max(ActiveEnd,Audio.Hits[High(Audio.Hits)].Time+0.16),Min(0.001,Audio.Duration),Audio.Duration);
    Count:=EnsureRange(Round(ActiveEnd/8.6),1,CannonMaxStages);
    if Length(Audio.Hits)=0 then Count:=1;
    SetLength(Result.Stages,Count);
    Start:=0;
    Normal:=0;
    Bosses:=0;
    Counter:=0;
    for I:=0 to Count-1 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      Stage:=TCannonStage.Create;
      Result.Stages[I]:=Stage;
      Stage.Start:=Start;
      IsFinal:=I=Count-1;
      Boundary:=(I+1)*ActiveEnd/Count;
      if not IsFinal then
        Boundary:=Boundary+Min(0.41,ActiveEnd/Count*0.075)*Sin((I+1)*2.4);
      Stage.Stop:=Boundary;
      Boss:=((I mod 4=3) or IsFinal) and (ActiveEnd>=3.7) and (Length(Audio.Hits)>=2);
      if Boss then begin
        if IsFinal then Stage.Kind:=ctReactor
        else Stage.Kind:=TCannonTarget(Ord(ctTower)+Bosses mod 4);
        Inc(Bosses);
      end else begin
        Stage.Kind:=TCannonTarget(Normal mod (Ord(ctTrain)+1));
        Inc(Normal);
      end;
      ScoreStage(Stage,Audio,Counter,IsFinal,Cancel);
      Start:=Boundary;
    end;
    Result.ResolveSupport;
  except
    Result.Free;
    raise;
  end;
end;
end.
