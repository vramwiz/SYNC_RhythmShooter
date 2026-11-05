unit RhythmSideRaceBuild;
// 曲のアクセントと節目から、速度、道路、挟撃、回復とボス戦を組み立てる。
interface
uses System.SysUtils,RhythmAudio,RhythmSideRacePlan;

function BuildSideRace(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TSideRacePlan;

implementation
uses System.Math,System.Generics.Collections,RhythmSections;

const DenseGap=0.185;

type
  TSideBuilder=class
  private
    FAudio:TRhythmAudio;
    FPlan:TSideRacePlan;
    FCancel:TFunc<Boolean>;
    FSeed:UInt64;
    procedure CheckCancel;
    function Pick(Count:Integer):Integer;
    procedure CopyCues;
    procedure MakeStages;
    procedure MakeBosses;
    procedure MakeJumps;
    procedure AssignContacts;
    procedure MakeCars;
  public
    procedure Build(Audio:TRhythmAudio;Plan:TSideRacePlan;const Cancel:TFunc<Boolean>);
  end;

procedure TSideBuilder.CheckCancel;
begin
  if Assigned(FCancel) and FCancel() then Abort;
end;

function TSideBuilder.Pick(Count:Integer):Integer;
begin
  FSeed:=(FSeed*48271) mod 2147483647;
  Result:=Integer(FSeed mod UInt64(Count));
end;

procedure TSideBuilder.CopyCues;
var I,N,BeforeGoal:Integer; Hit:TRhythmHit; Cue:TSideCue;
begin
  N:=0;
  SetLength(FPlan.Cues,Length(FAudio.Hits)+1);
  Cue:=Default(TSideCue);
  Cue.Car:=-1;
  Cue.Boss:=-1;
  Cue.Health:=1;
  Cue.Musical:=True;
  for I:=0 to High(FAudio.Hits) do begin
    if I mod 128=0 then CheckCancel;
    Hit:=FAudio.Hits[I];
    if (Hit.Time<0) or (Hit.Time>FPlan.Duration) then Continue;
    Cue.Time:=Hit.Time;
    Cue.Power:=EnsureRange(Hit.Strength,0.0,1.0);
    if (N>0) and (Cue.Time<=FPlan.Cues[N-1].Time) then begin
      if Cue.Time=FPlan.Cues[N-1].Time then FPlan.Cues[N-1].Power:=Max(Cue.Power,FPlan.Cues[N-1].Power);
      Continue;
    end;
    FPlan.Cues[N]:=Cue;
    Inc(N);
  end;
  // 音がない／冒頭にしかない素材でも、コース上の節目を一つ使ってトラックを出す。
  BeforeGoal:=N;
  while (BeforeGoal>0) and (FPlan.Cues[BeforeGoal-1].Time>=FPlan.Goal) do Dec(BeforeGoal);
  if (BeforeGoal=0) or (FPlan.Cues[BeforeGoal-1].Time<Min(0.40,FPlan.Goal*0.43)) then begin
    Cue.Time:=FPlan.Goal*0.77;
    Cue.Power:=0.74;
    Cue.Musical:=False;
    for I:=N downto BeforeGoal+1 do FPlan.Cues[I]:=FPlan.Cues[I-1];
    FPlan.Cues[BeforeGoal]:=Cue;
    Inc(N);
  end;
  SetLength(FPlan.Cues,N);
end;

procedure TSideBuilder.MakeStages;
var I,J,K,Count,Rank,Theme:Integer;
  Energy:TArray<Double>;
  Nominal,T,Best,Score,Center,A,B:Double;
  S:TSideStage;
begin
  Count:=EnsureRange(Round(Sqrt(FPlan.Duration)*1.04),1,64);
  if FPlan.Duration<6 then Count:=1;
  SetLength(FPlan.Stages,Count);
  SetLength(Energy,Count);
  Nominal:=FPlan.Duration/Count;
  Theme:=Pick(4);
  for I:=0 to Count-1 do begin
    CheckCancel;
    S:=Default(TSideStage);
    S.Theme:=(Theme+I) mod 4;
    if I>0 then begin
      Center:=I*Nominal;
      Best:=-1;
      S.Time:=Center;
      for J:=-9 to 9 do begin
        T:=Center+J*Nominal*0.024;
        Score:=Abs(FAudio.LevelAt(T+0.55)-FAudio.LevelAt(T-0.55))*3.2-Abs(J)*0.015;
        if Score>Best then begin
          S.Time:=T;
          Best:=Score;
        end;
      end;
    end;
    FPlan.Stages[I]:=S;
  end;
  for I:=0 to Count-1 do begin
    A:=FPlan.Stages[I].Time;
    B:=FPlan.Duration;
    if I<Count-1 then B:=FPlan.Stages[I+1].Time;
    Energy[I]:=I/Max(1,Count-1)*0.58;
    for J:=0 to 7 do Energy[I]:=Energy[I]+FAudio.LevelAt(SideMix(A,B,(J+0.5)/8))*0.125;
    Energy[I]:=Energy[I]+Min(0.18,(FPlan.CueFrom(B)-FPlan.CueFrom(A))/(B-A)*0.012);
  end;
  Energy[0]:=-1;
  for I:=0 to Count-1 do begin
    Rank:=0;
    for K:=0 to Count-1 do
      if (Energy[K]<Energy[I]) or ((Energy[K]=Energy[I]) and (K<I)) then Inc(Rank);
    S:=FPlan.Stages[I];
    S.Level:=1+Round(4*Rank/Max(1,Count-1));
    S.Speed:=14.9+S.Level*1.92+0.18*Pick(8);
    if I>0 then S.X:=FPlan.Stages[I-1].X+
      (S.Time-FPlan.Stages[I-1].Time)*(S.Speed+FPlan.Stages[I-1].Speed)*0.5;
    FPlan.Stages[I]:=S;
  end;
end;

procedure TSideBuilder.MakeBosses;
var List:TList<TSideBoss>; I,J,K,Kind,Previous,Limit:Integer; B:TSideBoss; Cue:TRhythmBossCue;
  Target,Start:Double;
begin
  List:=TList<TSideBoss>.Create;
  try
    Kind:=Pick(5);
    Previous:=-1;
    Limit:=FPlan.CueFrom(FPlan.Goal)-1;
    for I:=0 to FAudio.BossCount-1 do begin
      CheckCancel;
      if Previous>=Limit-1 then Break;
      Cue:=FAudio.BossCue(I);
      Target:=Min(FPlan.Goal-0.82,Cue.KillTime);
      K:=EnsureRange(FPlan.CueFrom(Target),Previous+1,Limit);
      if (K>Previous+1) and (Abs(FPlan.Cues[K-1].Time-Target)<Abs(FPlan.Cues[K].Time-Target)) then Dec(K);
      if (K<=Previous) or (FPlan.Cues[K].Time<Min(2.0,FPlan.Goal*0.35)) then Continue;
      Start:=FPlan.Cues[K].Time-Min(13.2,Max(4.7,FPlan.Duration*0.095));
      Start:=Max(Start,Cue.StartTime);
      if Previous>=0 then Start:=Max(Start,FPlan.Cues[Previous].Time+2.4);
      J:=FPlan.CueFrom(Start);
      if (J>K-1) or (FPlan.Cues[K].Time-FPlan.Cues[J].Time<0.5) then Continue;
      B.First:=J;
      B.Last:=K;
      B.Kind:=Kind;
      List.Add(B);
      Kind:=(Kind+3) mod 5;
      Previous:=K;
    end;
    if List.Count=0 then begin
      B.Last:=Max(0,Limit);
      B.First:=FPlan.CueFrom(FPlan.Cues[B.Last].Time-Min(12.0,Max(3.8,FPlan.Goal*0.50)));
      B.Kind:=Kind;
      List.Add(B);
    end;
    FPlan.Bosses:=List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TSideBuilder.MakeJumps;
var List:TList<TSideJump>; I,K,R,S,B,Limit,NextBoss:Integer; J:TSideJump;
  T,Duration,NextTime,Window:Double;
begin
  List:=TList<TSideJump>.Create;
  try
    I:=0;
    NextTime:=Min(1.15,FPlan.Goal*0.18);
    NextBoss:=0;
    while I<High(FPlan.Cues) do begin
      if I mod 128=0 then CheckCancel;
      T:=FPlan.Cues[I].Time;
      if T>=FPlan.Goal-0.64 then Break;
      if T<NextTime then begin Inc(I); Continue; end;
      S:=FPlan.StageAt(T);
      B:=FPlan.BossAt(T);
      while (NextBoss<Length(FPlan.Bosses)) and (FPlan.Bosses[NextBoss].First<=I) do Inc(NextBoss);
      Limit:=FPlan.CueFrom(FPlan.Goal)-1;
      if B>=0 then Limit:=Min(Limit,FPlan.Bosses[B].Last-1)
      else if NextBoss<Length(FPlan.Bosses) then Limit:=Min(Limit,FPlan.Bosses[NextBoss].First-1);
      Window:=0.87+FPlan.Stages[S].Level*0.067;
      K:=Min(Limit,FPlan.CueFrom(T+Window)-1);
      if (K<=I) or (FPlan.Cues[K].Time-T<0.57) then begin
        K:=Min(Limit,FPlan.CueFrom(T+1.46)-1);
        if (K<=I) or (FPlan.Cues[K].Time-T<0.57) then begin Inc(I); Continue; end;
      end;
      J:=Default(TSideJump);
      J.First:=I;
      J.Last:=K;
      J.Roof:=-1;
      J.Ramp:=0.38+FPlan.Stages[S].Level*0.071;
      J.Height:=0.77+FPlan.Stages[S].Level*0.19+Pick(5)*0.07;
      Duration:=FPlan.Cues[K].Time-T;
      if (B<0) and (FPlan.Stages[S].Level>1) then
        J.Gap:=0.14+FPlan.Stages[S].Level*0.145;
      if (J.Gap>0) and (FPlan.Stages[S].Level>=4) then J.Lift:=0.28+Pick(4)*0.08;
      if (B>=0) and (Duration>0.85) and (K-I<=9) then begin
        R:=FPlan.CueFrom(T+Duration*0.39);
        if (R<K) and (FPlan.Cues[R].Time<=T+Duration*0.62) then begin
          J.Roof:=R;
          J.Height:=1.79;
          FPlan.Cues[R].Action:=saBossRoof;
        end;
      end;
      FPlan.Cues[I].Action:=saLaunch;
      FPlan.Cues[K].Action:=saLand;
      List.Add(J);
      NextTime:=FPlan.Cues[K].Time+2.0+(5-FPlan.Stages[S].Level)*0.44+Pick(5)*0.19;
      if K-I>9 then NextTime:=NextTime+2.2;
      I:=K+1;
    end;
    FPlan.Jumps:=List.ToArray;
    FPlan.IndexTrack;
  finally
    List.Free;
  end;
end;

procedure TSideBuilder.AssignContacts;
var I,B,J,Run,Variant:Integer; C:TSideCue;
  BeforeGap,AfterGap,T,Middle,Hp:Double; Dense,Air:Boolean;
begin
  Hp:=1;
  Run:=0;
  for I:=0 to High(FPlan.Cues) do begin
    if I mod 128=0 then CheckCancel;
    C:=FPlan.Cues[I];
    T:=C.Time;
    B:=FPlan.BossAt(T);
    J:=FPlan.JumpAt(T);
    C.Boss:=B;
    BeforeGap:=2;
    AfterGap:=2;
    if I>0 then BeforeGap:=T-FPlan.Cues[I-1].Time;
    if I<High(FPlan.Cues) then AfterGap:=FPlan.Cues[I+1].Time-T;
    Dense:=Min(BeforeGap,AfterGap)<DenseGap;
    if BeforeGap>=DenseGap then Run:=0 else Inc(Run);
    Air:=J>=0;
    if (B>=0) and (I=FPlan.Bosses[B].Last) then C.Action:=saBossClear
    else if not (C.Action in [saLaunch,saLand,saBossRoof]) then begin
      Middle:=0;
      if Air then Middle:=(T-FPlan.Cues[FPlan.Jumps[J].First].Time)/
        (FPlan.Cues[FPlan.Jumps[J].Last].Time-FPlan.Cues[FPlan.Jumps[J].First].Time);
      if Air and (FPlan.Jumps[J].Roof<0) and (Hp<0.76) and (Middle>=0.36) and (Middle<=0.66) then
        C.Action:=saRepair
      else if (B>=0) and not Air then begin
        Variant:=(I-FPlan.Bosses[B].First+FPlan.Bosses[B].Kind) mod 7;
        if Dense then begin
          if Odd(Run) then C.Action:=saBossEscort else C.Action:=saBossTire;
        end else case Variant of
          0,4:C.Action:=saBossRam;
          2:C.Action:=saBossDrop;
          5:C.Action:=saBossEscort;
          else C.Action:=saBossTire;
        end;
      end else if Dense then begin
        if Odd(Run) then C.Action:=saRear else C.Action:=saFront;
      end else if Air then begin
        if Pick(4)=0 then C.Action:=saRear;
      end else case Pick(8) of
        0:C.Action:=saRear;
        1:C.Action:=saBump;
        2:C.Action:=saRock;
      end;
    end;
    case C.Action of
      saFront:Hp:=Hp-(0.014+0.012*C.Power);
      saRear,saBossEscort:Hp:=Hp-(0.031+0.017*C.Power);
      saRock,saBossDrop:Hp:=Hp-(0.040+0.014*C.Power);
      saBossRam:Hp:=Hp-(0.054+0.029*C.Power);
      saBossTire:Hp:=Hp-0.023;
      saRepair:Hp:=Hp+0.43;
    end;
    Hp:=EnsureRange(Hp,0.20,1.0);
    C.Health:=Hp;
    FPlan.Cues[I]:=C;
  end;
end;

function CarSide(Action:TSideAction):Integer;
begin
  case Action of
    saFront:Result:=1;
    saRear,saBossEscort:Result:=-1;
    else Result:=0;
  end;
end;

procedure TSideBuilder.MakeCars;
var List:TList<TSideCar>; I,K,Next,Side:Integer; F:TSideCar; Gap:Double;
begin
  List:=TList<TSideCar>.Create;
  try
    for I:=0 to High(FPlan.Cues) do begin
      if I mod 128=0 then CheckCancel;
      Side:=CarSide(FPlan.Cues[I].Action);
      if (Side=0) or (FPlan.Cues[I].Car>=0) then Continue;
      F.First:=I;
      F.Last:=I;
      F.Stride:=1;
      F.Kind:=Pick(6);
      F.Side:=Side;
      K:=I;
      while K+2<Length(FPlan.Cues) do begin
        Next:=K+2;
        Gap:=FPlan.Cues[Next].Time-FPlan.Cues[K].Time;
        if (Gap>=DenseGap*2) or (CarSide(FPlan.Cues[Next].Action)<>Side) or
          (CarSide(FPlan.Cues[K+1].Action)=Side) or (FPlan.Cues[Next].Car>=0) then Break;
        F.Stride:=2;
        F.Last:=Next;
        K:=Next;
      end;
      K:=F.First;
      while K<=F.Last do begin
        FPlan.Cues[K].Car:=List.Count;
        Inc(K,F.Stride);
      end;
      List.Add(F);
    end;
    FPlan.Cars:=List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TSideBuilder.Build(Audio:TRhythmAudio;Plan:TSideRacePlan;const Cancel:TFunc<Boolean>);
begin
  FAudio:=Audio;
  FPlan:=Plan;
  FCancel:=Cancel;
  CheckCancel;
  if not TryStrToUInt64('$'+Copy(Audio.Key,1,12),FSeed) then FSeed:=22937;
  FSeed:=1+FSeed mod 2147483646;
  Plan.Duration:=Audio.Duration;
  Plan.Goal:=EnsureRange(Audio.SoundEnd+0.13,Audio.Duration*0.87,
    Audio.Duration-Min(0.48,Audio.Duration*0.06));
  CopyCues;
  MakeStages;
  MakeBosses;
  MakeJumps;
  AssignContacts;
  MakeCars;
end;

function BuildSideRace(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TSideRacePlan;
var Builder:TSideBuilder;
begin
  Builder:=TSideBuilder.Create;
  try
    Result:=TSideRacePlan.Create;
    try
      Builder.Build(Audio,Result,Cancel);
    except
      Result.Free;
      raise;
    end;
  finally
    Builder.Free;
  end;
end;
end.
