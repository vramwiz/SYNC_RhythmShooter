unit RhythmRushBuild;
// 楽曲の節目と音時刻から、戦闘区間、敵の出入り、技の順序を逆算する。
interface
uses System.SysUtils,RhythmAudio,RhythmRushPlan;

function BuildRushPlan(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRushPlan;

implementation
uses System.Math,System.Types,System.Generics.Collections,RhythmSections;

type
  TRushWindow=record
    First,Last,Kind:Integer;
  end;

  TRushBuilder=class
  private
    FAudio:TRhythmAudio; // 共通の音声準備から借用。
    FPlan:TRushPlan;
    FCancel:TFunc<Boolean>;
    FWindows:TArray<TRushWindow>;
    FSeed:UInt64;
    procedure CheckCancel;
    function Pick(Count:Integer):Integer;
    procedure CopyCues;
    procedure DivideSong;
    procedure ChooseBosses;
    procedure ChooseArcs;
    procedure Choreograph;
    function SelectMove(Index:Integer;const Foe:TRushFoe;Arc,Level:Integer):TRushMove;
  public
    procedure Build(Audio:TRhythmAudio;Plan:TRushPlan;const Cancel:TFunc<Boolean>);
  end;

procedure TRushBuilder.CheckCancel;
begin
  if Assigned(FCancel) and FCancel() then Abort;
end;

function TRushBuilder.Pick(Count:Integer):Integer;
begin
  FSeed:=(FSeed*48271) mod 2147483647;
  Result:=Integer(FSeed mod UInt64(Count));
end;

procedure TRushBuilder.CopyCues;
var I,N:Integer; Hit:TRhythmHit;
begin
  SetLength(FPlan.Cues,Length(FAudio.Hits));
  N:=0;
  for I:=0 to High(FAudio.Hits) do begin
    if I mod 128=0 then CheckCancel;
    Hit:=FAudio.Hits[I];
    if (Hit.Time<0) or (Hit.Time>FPlan.Finish) then Continue;
    if (N>0) and (Hit.Time<=FPlan.Cues[N-1].Time) then begin
      if Hit.Time=FPlan.Cues[N-1].Time then
        FPlan.Cues[N-1].Power:=Max(FPlan.Cues[N-1].Power,EnsureRange(Hit.Strength,0.0,1.0));
      Continue;
    end;
    FPlan.Cues[N].Time:=Hit.Time;
    FPlan.Cues[N].Power:=EnsureRange(Hit.Strength,0.0,1.0);
    FPlan.Cues[N].Cause:=-1;
    Inc(N);
  end;
  SetLength(FPlan.Cues,N);
end;

procedure TRushBuilder.DivideSong;
const Modes:array[0..7] of TRushMode=(rmStreet,rmCrowd,rmChase,rmAir,rmStreet,rmAir,rmCrowd,rmChase);
  Speeds:array[TRushMode] of Double=(2.35,0.28,1.05,4.30);
var Count,I,J,K,Rank,Phase:Integer; Span,T,Center,Score,Best,FromTime,EndTime,X:Double;
  Energy:TArray<Double>; S:TRushStage;
begin
  Count:=EnsureRange(Round(Sqrt(FPlan.Finish)*1.06),1,64);
  if FPlan.Finish<6 then Count:=1;
  Span:=FPlan.Finish/Count;
  SetLength(FPlan.Stages,Count);
  SetLength(FWindows,Count);
  SetLength(Energy,Count);
  Phase:=Pick(5);
  for I:=0 to Count-1 do begin
    CheckCancel;
    S:=Default(TRushStage);
    S.Mode:=Modes[I mod Length(Modes)];
    S.Theme:=(Phase+I) mod 5;
    S.Boss:=-1;
    FWindows[I].First:=-1;
    FWindows[I].Last:=-1;
    if I>0 then begin
      Center:=I*Span;
      Best:=-1;
      S.StartTime:=Center;
      for J:=-8 to 8 do begin
        T:=Center+J*Span*0.027;
        K:=FPlan.CueFrom(T);
        Score:=Abs(FAudio.LevelAt(T-0.50)-FAudio.LevelAt(T+0.50))*2.8-Abs(J)*0.012;
        if (K>0) and (K<Length(FPlan.Cues)) then
          Score:=Score+Min(0.22,FPlan.Cues[K].Time-FPlan.Cues[K-1].Time)*0.43;
        if Score>Best then begin
          Best:=Score;
          S.StartTime:=T;
        end;
      end;
    end;
    FPlan.Stages[I]:=S;
  end;
  X:=0;
  for I:=0 to Count-1 do begin
    FromTime:=FPlan.Stages[I].StartTime;
    EndTime:=FPlan.Finish;
    if I<Count-1 then EndTime:=FPlan.Stages[I+1].StartTime;
    Energy[I]:=I/Max(1,Count-1)*0.17;
    for J:=0 to 7 do
      Energy[I]:=Energy[I]+FAudio.LevelAt(RushMix(FromTime,EndTime,(J+0.5)/8))/8;
    Energy[I]:=Energy[I]+Min(0.24,(FPlan.CueFrom(EndTime)-FPlan.CueFrom(FromTime))/
      (EndTime-FromTime)*0.018);
    S:=FPlan.Stages[I];
    S.X:=X;
    S.Speed:=Speeds[S.Mode];
    X:=X+S.Speed*(EndTime-FromTime);
    FPlan.Stages[I]:=S;
  end;
  Energy[0]:=-1;
  for I:=0 to Count-1 do begin
    Rank:=0;
    for J:=0 to Count-1 do
      if (Energy[J]<Energy[I]) or ((Energy[J]=Energy[I]) and (J<I)) then Inc(Rank);
    FPlan.Stages[I].Level:=1+Round(4*Rank/Max(1,Count-1));
  end;
end;

procedure TRushBuilder.ChooseBosses;
var I,S,First,Last,K,BestStage,PreviousStage,Kind:Integer;
  Cue:TRhythmBossCue;
  EndTime,StartTime,Score,Best:Double;
  Candidate:TRushWindow;
begin
  Kind:=Pick(6);
  PreviousStage:=-1;
  for I:=0 to FAudio.BossCount-1 do begin
    CheckCancel;
    Cue:=FAudio.BossCue(I);
    Best:=1E9;
    BestStage:=-1;
    Candidate:=Default(TRushWindow);
    for S:=PreviousStage+1 to High(FPlan.Stages) do begin
      StartTime:=FPlan.Stages[S].StartTime;
      EndTime:=FPlan.Finish;
      if S<High(FPlan.Stages) then EndTime:=FPlan.Stages[S+1].StartTime;
      First:=FPlan.CueFrom(Max(StartTime+0.20,EndTime-13.0));
      Last:=FPlan.CueFrom(EndTime-0.16)-1;
      if Last<First+2 then Continue;
      K:=EnsureRange(FPlan.CueFrom(Cue.KillTime),First+2,Last);
      if (K>First+2) and (Abs(FPlan.Cues[K-1].Time-Cue.KillTime)<Abs(FPlan.Cues[K].Time-Cue.KillTime)) then Dec(K);
      if FPlan.Cues[K].Time-FPlan.Cues[First].Time<1.5 then Continue;
      Score:=Abs(FPlan.Cues[K].Time-Cue.KillTime);
      if S=0 then Score:=Score+4;
      if Score<Best then begin
        Best:=Score;
        BestStage:=S;
        Candidate.First:=First;
        Candidate.Last:=K;
      end;
    end;
    if (BestStage<0) or (Best>Max(12.0,FPlan.Finish*0.12)) then Continue;
    Candidate.Kind:=Kind;
    Kind:=(Kind+5) mod 6;
    FWindows[BestStage]:=Candidate;
    PreviousStage:=BestStage;
  end;
end;

procedure TRushBuilder.ChooseArcs;
var Arcs:TList<TRushArc>; I,S,J,Limit:Integer; T,NextTime,Span:Double;
  A:TRushArc; Stage:TRushStage; Boss:Boolean;
begin
  Arcs:=TList<TRushArc>.Create;
  try
    NextTime:=0;
    I:=0;
    while I<Length(FPlan.Cues)-2 do begin
      if I mod 128=0 then CheckCancel;
      T:=FPlan.Cues[I].Time;
      S:=FPlan.StageAt(T);
      Stage:=FPlan.Stages[S];
      Boss:=(FWindows[S].First>=0) and (I>=FWindows[S].First) and (I<=FWindows[S].Last);
      Limit:=High(FPlan.Cues);
      if S<High(FPlan.Stages) then Limit:=FPlan.CueFrom(FPlan.Stages[S+1].StartTime)-1;
      if Boss then Limit:=FWindows[S].Last-Ord(FWindows[S].Kind<>4)
      else if FWindows[S].First>I then Limit:=Min(Limit,FWindows[S].First-1);
      if (T<NextTime) or
        (not Boss and (Stage.Mode<>rmAir) and ((Stage.Level<2) or (I mod 17<>8))) or
        (Boss and (I=FWindows[S].First)) then begin
        Inc(I);
        Continue;
      end;
      Span:=1.07+0.085*Stage.Level;
      if Boss then Span:=Span+0.12;
      J:=Min(Limit,FPlan.CueFrom(T+Span)-1);
      if (J<I+2) or (FPlan.Cues[J].Time-T<0.60) then begin
        Inc(I);
        Continue;
      end;
      A.First:=I;
      A.Last:=J;
      A.Height:=0.90+Stage.Level*0.17+Pick(5)*0.06+0.20*Ord(Boss);
      Arcs.Add(A);
      NextTime:=FPlan.Cues[J].Time+0.48+(5-Stage.Level)*0.09;
      I:=J+1;
    end;
    FPlan.Arcs:=Arcs.ToArray;
  finally
    Arcs.Free;
  end;
end;

function TRushBuilder.SelectMove(Index:Integer;const Foe:TRushFoe;Arc,Level:Integer):TRushMove;
const Finishes:array[0..5] of TRushMove=(raPunch,raKick,raThrow,raOrb,raSlam,raSpecial);
var T,BeforeGap,AfterGap:Double; PosInFight:Integer;
begin
  T:=FPlan.Cues[Index].Time;
  BeforeGap:=2;
  AfterGap:=2;
  if Index>0 then BeforeGap:=T-FPlan.Cues[Index-1].Time;
  if Index<High(FPlan.Cues) then AfterGap:=FPlan.Cues[Index+1].Time-T;
  PosInFight:=Index-Foe.First;
  if (Arc>=0) and (Index=FPlan.Arcs[Arc].First) then begin
    if (Foe.Kind+Level) mod 3=0 then Exit(raThrow);
    Exit(raLaunch);
  end;
  if (Arc>=0) and (Index=FPlan.Arcs[Arc].Last) then Exit(raSlam);
  if Foe.Boss and (Index=Foe.Last) then begin
    if (Foe.Kind=4) and (Arc<0) then Exit(raKick);
    Exit(Finishes[Foe.Kind]);
  end;
  if (Index>Foe.First) and Defensive(FPlan.Cues[Index-1].Move) then begin
    if (BeforeGap<0.15) and (T>0.11) then Exit(raOrb);
    Exit(raCounter);
  end;
  if Arc>=0 then begin
    if (BeforeGap<0.14) and (PosInFight mod 3<>1) then Exit(raOrb);
    if Odd(PosInFight) then Exit(raAirPunch);
    Exit(raAirKick);
  end;
  if (Index<Foe.Last) and (BeforeGap>=0.14) and (AfterGap>=0.18) and
    ((Foe.Boss and (PosInFight mod Max(3,7-Level) in [0,1])) or
     (not Foe.Boss and (Index=Foe.First) and (Level>=2) and (Pick(3)<>0))) then begin
    case (Foe.Kind+Index) mod 6 of
      0:Exit(raHurt);
      1,3:Exit(raDodge);
      else Exit(raGuard);
    end;
  end;
  if (T>0.12) and (Min(BeforeGap,AfterGap)<0.145) then Exit(raOrb);
  if (BeforeGap>=0.25) and ((Level=5) and (Index mod 11=5) or
    ((Level>=3) and (Index=Foe.Last) and (Index mod 9=5) and
    (FPlan.Stages[FPlan.StageAt(T)].Mode=rmCrowd))) then Exit(raSpecial);
  if (Level>=3) and (BeforeGap>0.29) and (Pick(8)=0) then Exit(raThrow);
  if (Index+Foe.Kind) mod 3=1 then Exit(raKick);
  Result:=raPunch;
end;

procedure TRushBuilder.Choreograph;
var
  Foes:TList<TRushFoe>;
  F:TRushFoe;
  A:TRushCue;
  Stage:TRushStage;
  I,J,S,Arc,Limit,Cause,NextArc:Integer;
  T,Gap,NextExchange:Double;
begin
  Foes:=TList<TRushFoe>.Create;
  try
    I:=0;
    NextExchange:=1.6;
    while I<Length(FPlan.Cues) do begin
      CheckCancel;
      T:=FPlan.Cues[I].Time;
      S:=FPlan.StageAt(T);
      Stage:=FPlan.Stages[S];
      Arc:=FPlan.ArcAt(T);
      F:=Default(TRushFoe);
      F.First:=I;
      F.Last:=I;
      F.Kind:=Pick(6);
      F.Side:=1;
      if Stage.Mode=rmCrowd then F.Side:=1-2*(Foes.Count mod 2)
      else if (Stage.Mode=rmStreet) and (Pick(6)=0) then F.Side:=-1;
      Limit:=High(FPlan.Cues);
      if S<High(FPlan.Stages) then Limit:=FPlan.CueFrom(FPlan.Stages[S+1].StartTime)-1;
      if FWindows[S].First>I then Limit:=Min(Limit,FWindows[S].First-1);
      if I=FWindows[S].First then begin
        F.Last:=FWindows[S].Last;
        F.Boss:=True;
        F.Side:=1;
        F.Kind:=FWindows[S].Kind;
        FPlan.Stages[S].Boss:=Foes.Count;
      end else if Arc>=0 then F.Last:=FPlan.Arcs[Arc].Last
      else if (I<Limit) and (FPlan.Cues[I+1].Time-T<0.145) then begin
        J:=I+1;
        while J<=Min(Limit,I+2) do begin
          if (FPlan.Cues[J].Time-FPlan.Cues[J-1].Time>=0.145) or
            (FPlan.ArcAt(FPlan.Cues[J].Time)>=0) then Break;
          F.Last:=J;
          Inc(J);
        end;
      end else if Stage.Level>=2 then begin
        J:=I+1;
        while J<=Min(Limit,I+1+2*Ord(Stage.Mode=rmChase)) do begin
          Gap:=FPlan.Cues[J].Time-FPlan.Cues[J-1].Time;
          NextArc:=FPlan.ArcAt(FPlan.Cues[J].Time);
          if (Gap<0.19) or (Gap>0.85) or (NextArc>=0) then Break;
          if (Stage.Mode<>rmChase) and ((I mod 4)<>2) then Break;
          F.Last:=J;
          Inc(J);
        end;
      end;
      if (T>=NextExchange) and (Arc<0) and (I<Limit) and
        (FPlan.ArcAt(FPlan.Cues[I+1].Time)<0) and
        InRange(FPlan.Cues[I+1].Time-T,0.20,0.88) and
        ((I=0) or (T-FPlan.Cues[I-1].Time>=0.15)) then begin
        // 単発技が続く序盤にも、敵が先に打ち込める二拍の攻防を作る。
        F.Last:=Max(F.Last,I+1);
        NextExchange:=T+4.0;
      end;
      if (I>0) and (T-FPlan.Cues[I-1].Time<0.12) and
        (FPlan.Cues[I-1].Move=raOrb) and not F.Boss then F.Side:=Foes.Last.Side;
      Cause:=-1;
      if (Stage.Mode=rmCrowd) and (Stage.Level>=3) and (Arc<0) and
        (not F.Boss) and (I=F.Last) and (I>0) and (I mod 3<>0) then begin
        Gap:=T-FPlan.Cues[I-1].Time;
        if (Gap>=0.16) and (Gap<=0.56) and (FPlan.Cues[I-1].Move<>raCrash) and
          not Foes.Last.Boss then begin
          Cause:=Foes.Count-1;
          F.Side:=Foes.Last.Side;
        end;
      end;
      for J:=I to F.Last do begin
        A:=FPlan.Cues[J];
        A.Foe:=Foes.Count;
        A.Cause:=Cause;
        if Cause>=0 then A.Move:=raCrash
        else A.Move:=SelectMove(J,F,FPlan.ArcAt(A.Time),Stage.Level);
        if A.Move=raOrb then A.Flight:=Min(A.Time,0.17+0.034*F.Kind+0.05*Ord(F.First=F.Last));
        if Defensive(A.Move) and (F.Kind=5) then A.Flight:=Min(A.Time,0.24);
        FPlan.Cues[J]:=A;
      end;
      Foes.Add(F);
      I:=F.Last+1;
    end;
    FPlan.Foes:=Foes.ToArray;
  finally
    Foes.Free;
  end;
end;

procedure TRushBuilder.Build(Audio:TRhythmAudio;Plan:TRushPlan;const Cancel:TFunc<Boolean>);
begin
  FAudio:=Audio;
  FPlan:=Plan;
  FCancel:=Cancel;
  CheckCancel;
  if not TryStrToUInt64('$'+Copy(Audio.Key,1,12),FSeed) then FSeed:=5917;
  FSeed:=1+FSeed mod 2147483646;
  Plan.Duration:=Audio.Duration;
  Plan.Finish:=Audio.SoundEnd;
  if Length(Audio.Hits)>0 then Plan.Finish:=Max(Plan.Finish,Audio.Hits[High(Audio.Hits)].Time+0.45);
  Plan.Finish:=EnsureRange(Plan.Finish,Min(Audio.Duration,0.6),Audio.Duration);
  CopyCues;
  DivideSong;
  ChooseBosses;
  ChooseArcs;
  Choreograph;
end;

function BuildRushPlan(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRushPlan;
var Builder:TRushBuilder;
begin
  Builder:=TRushBuilder.Create;
  try
    Result:=TRushPlan.Create;
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
