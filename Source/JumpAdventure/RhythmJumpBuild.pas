unit RhythmJumpBuild;
// 曲の区切りと音の接触時刻を先に確定し、足場とジャンプを逆算する。
interface
uses System.SysUtils,RhythmAudio,RhythmJumpPlan;
function BuildJumpPlan(Audio:TRhythmAudio;const Generation:string;const Cancel:TFunc<Boolean>):TJumpPlan;

implementation
uses System.Math,System.Types,System.Generics.Collections,RhythmSections;

type
  TJumpBuilder=class
  private
    FAudio:TRhythmAudio; // 準備スレッドから借用。
    FPlan:TJumpPlan;
    FCancel:TFunc<Boolean>;
    FSeed:UInt64;
    FFinish:Double;
    procedure CheckCancel;
    function Pick(Count:Integer):Integer;
    procedure StageLayout;
    procedure ScheduleBeats;
    procedure ScheduleBosses;
    procedure ScheduleRolls;
    procedure PlaceRoute;
    procedure PlaceEnemies;
    procedure PlanLegs;
    procedure ClearLandings;
  public
    procedure Build(Audio:TRhythmAudio;Plan:TJumpPlan;const Generation:string;const Cancel:TFunc<Boolean>);
  end;

procedure TJumpBuilder.CheckCancel;
begin
  if Assigned(FCancel) and FCancel() then Abort;
end;

function TJumpBuilder.Pick(Count:Integer):Integer;
begin
  FSeed:=(FSeed*48271) mod 2147483647;
  Result:=Integer(FSeed mod UInt64(Count));
end;

procedure TJumpBuilder.StageLayout;
var
  I,J,K,Count,Theme,Rank,SameDirection,Nearest:Integer;
  Span,Center,T,BestTime,Score,BestScore,Left,Right,BeatDistance:Double;
  Energy:TArray<Double>;
begin
  Count:=Max(1,Min(64,Round(Sqrt(FFinish)*1.08)));
  if FFinish<5 then Count:=1 else Count:=Max(2,Count);
  Span:=FFinish/Count;
  SetLength(FPlan.Stages,Count);
  SetLength(Energy,Count);
  Theme:=Pick(5);
  for I:=0 to Count-1 do begin
    CheckCancel;
    FPlan.Stages[I].Vertical:=Odd(I);
    FPlan.Stages[I].Theme:=(Theme+I) mod 5;
    FPlan.Stages[I].Boss:=-1;
    if I=0 then Continue;
    Center:=Span*I;
    BestScore:=-1;
    BestTime:=Center;
    for J:=-10 to 10 do begin
      T:=Center+J*Span*0.022;
      Left:=FAudio.LevelAt(T-0.48);
      Right:=FAudio.LevelAt(T+0.48);
      Nearest:=FAudio.NearestHit(T);
      BeatDistance:=1;
      if Nearest>=0 then BeatDistance:=Min(1.0,Abs(T-FAudio.Hits[Nearest].Time)*4);
      Score:=Abs(Right-Left)*3+(1-Min(Left,Right))*0.08+
        BeatDistance*0.09-Abs(J)*0.012;
      if Score>BestScore then begin
        BestScore:=Score;
        BestTime:=T;
      end;
    end;
    FPlan.Stages[I].StartTime:=BestTime;
  end;
  for I:=0 to Count-1 do begin
    T:=FFinish;
    if I<Count-1 then T:=FPlan.Stages[I+1].StartTime;
    Left:=FPlan.Stages[I].StartTime;
    for J:=0 to 7 do
      Energy[I]:=Energy[I]+FAudio.LevelAt(JumpBlend(Left,T,(J+0.5)/8))/8;
    Energy[I]:=Energy[I]+I/Max(1,Count-1)*0.15;
  end;
  Energy[0]:=-1;
  if Count>1 then Energy[1]:=-1;
  for I:=0 to Count-1 do begin
    Rank:=0;
    SameDirection:=0;
    for K:=0 to Count-1 do
      if FPlan.Stages[K].Vertical=FPlan.Stages[I].Vertical then begin
        Inc(SameDirection);
        if (Energy[K]<Energy[I]) or ((Energy[K]=Energy[I]) and (K<I)) then Inc(Rank);
      end;
    FPlan.Stages[I].Level:=1+Round(4*Rank/Max(1,SameDirection-1));
  end;
end;

procedure TJumpBuilder.ScheduleBeats;
const
  IsolatedStompGap=0.90;
var
  Nodes:TList<TJumpNode>;
  Beats:TList<TJumpBeat>;
  Hit:TRhythmHit;
  N,Previous:TJumpNode;
  B:TJumpBeat;
  I:Integer;
  LastContact,LastStomp:Double;

  procedure AddNode(Time:Double);
  begin
    N:=Default(TJumpNode);
    N.Time:=Time;
    N.SolidUntil:=FPlan.Duration;
    Nodes.Add(N);
  end;

  procedure FillTo(Time:Double);
  var J,Steps:Integer; Start:Double;
  begin
    Start:=Nodes.Last.Time;
    Steps:=Max(1,Ceil((Time-Start)/1.23));
    for J:=1 to Steps-1 do AddNode(JumpBlend(Start,Time,J/Steps));
  end;

begin
  Nodes:=TList<TJumpNode>.Create;
  Beats:=nil;
  try
    Beats:=TList<TJumpBeat>.Create;
    AddNode(0);
    LastContact:=-1;
    LastStomp:=-1;
    for I:=0 to High(FAudio.Hits) do begin
      if I mod 128=0 then CheckCancel;
      Hit:=FAudio.Hits[I];
      if (Hit.Time<0) or (Hit.Time>FFinish) then Continue;
      if (Beats.Count>0) and (Hit.Time<=Beats.Last.Time) then begin
        // 解析の同時刻は強い方を使い、同じ足への二重接触を避ける。
        if Hit.Time=Beats.Last.Time then begin
          B:=Beats.Last;
          B.Strength:=Max(B.Strength,EnsureRange(Hit.Strength,0.0,1.0));
          Beats[Beats.Count-1]:=B;
        end;
        Continue;
      end;
      B.Time:=Hit.Time;
      B.Strength:=EnsureRange(Hit.Strength,0.0,1.0);
      B.Node:=-1;
      if (Hit.Time>=LastContact+JumpMinBeatGap) and
        ((Hit.Time=0) or ((Hit.Time>=0.24) and (FFinish-Hit.Time>=0.27))) then begin
        FillTo(Hit.Time);
        if Hit.Time>0 then AddNode(Hit.Time);
        B.Node:=Nodes.Count-1;
        LastContact:=Hit.Time;
        if B.Node>0 then begin
          Previous:=Nodes[B.Node-1];
          if (Previous.Landing<>jlStomp) and (Hit.Time-LastStomp>=IsolatedStompGap) and (Pick(7)<3) then begin
            N:=Nodes.Last;
            N.Landing:=jlStomp;
            N.Variant:=Pick(4);
            Nodes[B.Node]:=N;
            LastStomp:=Hit.Time;
          end;
        end;
      end;
      Beats.Add(B);
    end;
    if FFinish>Nodes.Last.Time then begin
      FillTo(FFinish);
      AddNode(FFinish);
    end;
    FPlan.Nodes:=Nodes.ToArray;
    FPlan.Beats:=Beats.ToArray;
  finally
    Beats.Free;
    Nodes.Free;
  end;
end;

procedure TJumpBuilder.ScheduleBosses;
var
  Fights:TList<TJumpBoss>;
  I,S,J,K,First,Last,BestStage,SearchFrom,PreviousStage,PriorVertical:Integer;
  B:TJumpBoss;
  Cue:TRhythmBossCue;
  Time,EndTime,Score,BestScore:Double;
begin
  Fights:=TList<TJumpBoss>.Create;
  try
    PreviousStage:=-1;
    PriorVertical:=-1;
    for I:=0 to FAudio.BossCount-1 do begin
      CheckCancel;
      Cue:=FAudio.BossCue(I);
      BestStage:=-1;
      BestScore:=1E10;
      B:=Default(TJumpBoss);
      for S:=PreviousStage+1 to High(FPlan.Stages) do begin
        Time:=FPlan.Stages[S].StartTime;
        EndTime:=FFinish;
        if S<High(FPlan.Stages) then EndTime:=FPlan.Stages[S+1].StartTime;
        First:=-1;
        Last:=-1;
        SearchFrom:=FPlan.BeatFrom(Max(Time+0.18,EndTime-13));
        for J:=SearchFrom to High(FPlan.Beats) do begin
          if FPlan.Beats[J].Time>EndTime-0.21 then Break;
          K:=FPlan.Beats[J].Node;
          if K<1 then Continue;
          if First<0 then First:=K;
          if (Last<0) or (Abs(FPlan.Nodes[K].Time-Cue.KillTime)<=
            Abs(FPlan.Nodes[Last].Time-Cue.KillTime)) then Last:=K;
        end;
        if (First<0) or (Last<First+2) then Continue;
        if FPlan.Nodes[Last].Time-FPlan.Nodes[First].Time<1.35 then Continue;
        Score:=Abs(FPlan.Nodes[Last].Time-Cue.KillTime)+
          Ord(Ord(FPlan.Stages[S].Vertical)=PriorVertical)*Min(12.0,FFinish*0.065);
        if Score<BestScore then begin
          BestScore:=Score;
          BestStage:=S;
          B.FirstNode:=First;
          B.LastNode:=Last;
        end;
      end;
      if (BestStage<0) or (BestScore>Max(11.0,FFinish*0.13)) then Continue;
      B.Variant:=(FPlan.Stages[BestStage].Theme+Fights.Count) mod 3;
      if Fights.Count>0 then
        if B.Variant=Fights.Last.Variant then B.Variant:=(B.Variant+1) mod 3;
      FPlan.Stages[BestStage].Boss:=Fights.Count;
      Fights.Add(B);
      PreviousStage:=BestStage;
      PriorVertical:=Ord(FPlan.Stages[BestStage].Vertical);
      K:=Pick(3);
      for J:=B.FirstNode to B.LastNode do begin
        FPlan.Nodes[J].Landing:=jlBoss;
        // 弱点は同じ場所を何度か使ってから変え、ボス本体の移動を穏やかにする。
        FPlan.Nodes[J].Variant:=K;
        if (J-B.FirstNode) mod (6-FPlan.Stages[BestStage].Level div 2)=0 then
          K:=EnsureRange(K+1-2*Pick(2),0,2);
      end;
    end;
    FPlan.Bosses:=Fights.ToArray;
  finally
    Fights.Free;
  end;
end;

procedure TJumpBuilder.ScheduleRolls;
const DenseBeatGap=0.24;
var
  Rolls:TList<TJumpRoll>;
  Hits:TList<Double>;
  Roll:TJumpRoll;
  I,J,K,StartNode,EndNode,LastRoad:Integer;
  StartTime,HitTime:Double;
begin
  Rolls:=TList<TJumpRoll>.Create;
  Hits:=nil;
  try
    Hits:=TList<Double>.Create;
    LastRoad:=0;
    for I:=0 to High(FPlan.Beats)-3 do begin
      if I mod 128=0 then CheckCancel;
      StartNode:=FPlan.Beats[I].Node;
      if StartNode<=LastRoad then Continue;
      StartTime:=FPlan.Beats[I].Time;
      if FPlan.Beats[I+1].Time-StartTime>DenseBeatGap then Continue;
      EndNode:=FPlan.NodeAt(StartTime+1.98)+1;
      if (EndNode>High(FPlan.Nodes)) or
        (FPlan.StageAt(FPlan.Nodes[EndNode].Time)<>FPlan.StageAt(StartTime)) then Continue;
      K:=StartNode;
      while (K<=EndNode) and (FPlan.Nodes[K].Landing<>jlBoss) do Inc(K);
      if K<=EndNode then Continue;
      Hits.Clear;
      HitTime:=StartTime;
      for J:=I+1 to High(FPlan.Beats) do begin
        if (FPlan.Beats[J].Time-StartTime>0.96) or
          (FPlan.Beats[J].Time-FPlan.Beats[J-1].Time>DenseBeatGap) then Break;
        // 半径分の間隔を確保し、敵同士が重ならない拍を使う。
        if FPlan.Beats[J].Time-HitTime<0.09 then Continue;
        HitTime:=FPlan.Beats[J].Time;
        Hits.Add(HitTime);
      end;
      if Hits.Count<3 then Continue;
      Roll.FirstNode:=StartNode;
      Roll.LastNode:=EndNode;
      Roll.Hits:=Hits.ToArray;
      Rolls.Add(Roll);
      FPlan.Nodes[StartNode].Landing:=jlRoll;
      for J:=StartNode+1 to EndNode do FPlan.Nodes[J].Landing:=jlGround;
      LastRoad:=EndNode;
    end;
    FPlan.Rolls:=Rolls.ToArray;
  finally
    Hits.Free;
    Rolls.Free;
  end;
end;

procedure TJumpBuilder.PlaceRoute;
const Widths:array[1..5] of Double=(1.60,1.28,0.83,0.76,0.67);
var
  I,S,PreviousStage,Direction,MoveCooldown,Roll:Integer;
  N:TJumpNode;
  Prev:TJumpNode;
  Stage:TJumpStage;
  Dt,Column,Step,Gap:Double;
begin
  FPlan.Nodes[0].Width:=1.6;
  Direction:=1;
  PreviousStage:=-1;
  MoveCooldown:=0;
  Column:=0;
  for I:=1 to High(FPlan.Nodes) do begin
    if I mod 128=0 then CheckCancel;
    Prev:=FPlan.Nodes[I-1];
    N:=FPlan.Nodes[I];
    Dt:=N.Time-Prev.Time;
    S:=FPlan.StageAt((N.Time+Prev.Time)*0.5);
    Stage:=FPlan.Stages[S];
    if S<>PreviousStage then begin
      Column:=Prev.X;
      MoveCooldown:=0;
      Direction:=1-2*Pick(2);
      PreviousStage:=S;
    end;
    N.Width:=Widths[Stage.Level]*(0.91+Pick(5)*0.045);
    N.X:=Prev.X;
    N.Y:=Prev.Y;
    Roll:=FPlan.RollAtNode(I);
    if (Roll>=0) and (I>FPlan.Rolls[Roll].FirstNode) then begin
      N.X:=N.X+4.6*Dt;
    end else if Stage.Vertical then begin
      Step:=(1.8+Stage.Level*0.33)*Dt;
      if Abs(Prev.X+Direction*Step-Column)>2.65 then Direction:=-Direction;
      N.X:=N.X+Step*Direction;
      N.Y:=N.Y+Max(0.53,Dt*(1.02+0.19*Stage.Level));
      if (N.Landing=jlGround) and (Dt>0.55) and (Pick(7)=0) and
        (I<High(FPlan.Nodes)) then N.Landing:=jlSpring;
    end else begin
      Gap:=(2.65+Stage.Level*0.35+Pick(4)*0.13)*Dt;
      N.X:=N.X+Gap;
      if (Dt>0.42) and (Dt<1.06) then begin
        if Stage.Level>1 then N.Y:=Max(0.0,N.Y+(Pick(5)-2)*0.24)
        else if Pick(7)=0 then N.Y:=Max(0.0,N.Y+(1-2*Pick(2))*0.16);
      end;
      if Stage.Level>1 then N.Width:=Min(N.Width,Max(0.22,Gap*0.62));
    end;
    if MoveCooldown>0 then Dec(MoveCooldown);
    if (Roll<0) and (Stage.Level>=4) and (N.Landing in [jlGround,jlSpring]) and (Dt>=0.27) and
      (I<High(FPlan.Nodes)) and (MoveCooldown=0) then begin
      if Stage.Vertical or (Dt<0.58) or (Pick(2)=0) then N.MoveX:=0.27+Pick(4)*0.06
      else N.MoveY:=0.16+Pick(4)*0.05;
      MoveCooldown:=4+Pick(5);
    end;
    if (I=High(FPlan.Nodes)) and (N.Landing=jlGround) then N.Width:=Max(0.9,N.Width);
    FPlan.Nodes[I]:=N;
  end;
end;

procedure TJumpBuilder.PlaceEnemies;
var I,ArrivalStage,DepartureStage:Integer; Before,After:TJumpNode;
  Lift:Double;
begin
  for I:=1 to High(FPlan.Nodes)-1 do begin
    if I mod 128=0 then CheckCancel;
    if FPlan.Nodes[I].Landing=jlRoll then FPlan.Nodes[I].Y:=FPlan.Nodes[I].Y+2*JumpRollRadius;
    if FPlan.Nodes[I].Landing<>jlStomp then Continue;
    Before:=FPlan.Nodes[I-1];
    After:=FPlan.Nodes[I+1];
    ArrivalStage:=FPlan.StageAt((Before.Time+FPlan.Nodes[I].Time)*0.5);
    DepartureStage:=FPlan.StageAt((FPlan.Nodes[I].Time+After.Time)*0.5);
    if (Before.Landing=jlGround) and (After.Landing=jlGround) and
      not (FPlan.Stages[ArrivalStage].Vertical or FPlan.Stages[DepartureStage].Vertical) and
      (Before.Y=FPlan.Nodes[I].Y) and (After.Y=FPlan.Nodes[I].Y) and
      (Before.MoveY=0) and (After.MoveY=0) then begin
      FPlan.Nodes[I].Enemy:=jeGround;
      FPlan.Nodes[I].Y:=FPlan.Nodes[I].Y+2*JumpEnemyRadius;
    end else begin
      FPlan.Nodes[I].Enemy:=jeFlying;
      Lift:=0.82;
      if FPlan.Stages[DepartureStage].Vertical then
        Lift:=Min(Lift,After.Y-FPlan.Nodes[I].Y-0.12);
      FPlan.Nodes[I].Y:=FPlan.Nodes[I].Y+Lift;
    end;
  end;
end;

procedure TJumpBuilder.PlanLegs;
var
  I,S,B,Roll:Integer;
  A,C:TJumpNode;
  Stage:TJumpStage;
  L:TJumpLeg;
  Dt,Span:Double;
  P:TPointF;
  OnRollRoad:Boolean;
begin
  SetLength(FPlan.Legs,Length(FPlan.Nodes)-1);
  for I:=0 to High(FPlan.Legs) do begin
    A:=FPlan.Nodes[I];
    C:=FPlan.Nodes[I+1];
    S:=FPlan.StageAt((A.Time+C.Time)*0.5);
    Stage:=FPlan.Stages[S];
    Roll:=FPlan.RollAtNode(I);
    OnRollRoad:=(Roll>=0) and (I<FPlan.Rolls[Roll].LastNode);
    if OnRollRoad then begin
      Stage.Vertical:=False;
      Stage.Level:=1;
    end;
    L:=Default(TJumpLeg);
    L.Takeoff:=A.Time;
    Dt:=C.Time-A.Time;
    if Stage.Vertical or ((Stage.Level>1) and (Dt<1.06)) or (A.Y<>C.Y) or
      (A.Landing<>jlGround) or (C.Landing<>jlGround) or
      (Abs(A.MoveX)+Abs(A.MoveY)+Abs(C.MoveX)+Abs(C.MoveY)>0) or
      ((not OnRollRoad) and (Dt>0.58) and (Dt<1.06) and (Pick(4)=0)) then begin
      if (Dt>0.60) and (A.Landing in [jlGround,jlSpring]) then
        L.Takeoff:=A.Time+Min(0.23,Dt*0.22);
      Span:=C.Time-L.Takeoff;
      P:=FPlan.Platform(I,L.Takeoff);
      if A.Landing in [jlStomp,jlBoss,jlRoll] then P.Y:=A.Y;
      // 上方向の移動でも頂点を越えてから着地する。
      if Stage.Vertical then
        L.Height:=Abs(C.Y-P.Y)*0.25+0.075+Span*0.13
      else
        L.Height:=Max(Abs(C.Y-P.Y)*0.29+0.026,Min(1.25,0.13+Span*0.82));
      // 着地先が低い場合も、踏み台より通常のジャンプ分だけ上がる。
      if A.Enemy=jeFlying then L.Height:=Max(L.Height,0.42+Max(0.0,P.Y-C.Y)*0.5);
      if A.Landing=jlSpring then L.Height:=L.Height+0.19;
    end;
    B:=Stage.Boss;
    if (B>=0) and (I>=FPlan.Bosses[B].FirstNode) and
      (I<FPlan.Bosses[B].LastNode) and (L.Height>0) and
      ((I-FPlan.Bosses[B].FirstNode) mod Max(2,6-Stage.Level)=0) then
      L.Attack:=1+(FPlan.Bosses[B].Variant+Pick(Min(3,Stage.Level))) mod 3;
    FPlan.Legs[I]:=L;
  end;
end;

procedure TJumpBuilder.ClearLandings;
var I,J,First,Last,S:Integer; Time,Side,Width:Double;
begin
  for I:=0 to High(FPlan.Legs) do begin
    if I mod 128=0 then CheckCancel;
    if FPlan.Legs[I].Height=0 then Continue;
    First:=Max(0,FPlan.NodeAt(FPlan.Nodes[I].Time-7)-1);
    Last:=Min(High(FPlan.Nodes),FPlan.NodeAt(FPlan.Nodes[I+1].Time+7)+1);
    for J:=First to Last do begin
      if not FPlan.EarlierLanding(I,J,Time,Side) then Continue;
      S:=FPlan.StageAt(FPlan.Nodes[J].Time);
      Width:=2*(Side-0.115);
      if (FPlan.Stages[S].Level>1) and (Width>=0.46) then
        FPlan.Nodes[J].Width:=Min(FPlan.Nodes[J].Width,Width)
      else if J>I+1 then begin
        // 重なる奥の足場は下見用の表示を残し、通過後に接地できる状態へ移す。
        FPlan.Nodes[J].SolidFrom:=Max(FPlan.Nodes[J].SolidFrom,
          Min(Time+0.035,FPlan.Nodes[J].Time-0.012));
      end else begin
        FPlan.Nodes[J].SolidUntil:=Min(FPlan.Nodes[J].SolidUntil,
          Max(FPlan.Legs[J].Takeoff,Time-0.035));
      end;
    end;
  end;
end;

procedure TJumpBuilder.Build(Audio:TRhythmAudio;Plan:TJumpPlan;const Generation:string;const Cancel:TFunc<Boolean>);
begin
  FAudio:=Audio;
  FPlan:=Plan;
  FCancel:=Cancel;
  CheckCancel;
  if not TryStrToUInt64('$'+Copy(Generation,1,12),FSeed) then FSeed:=4137;
  FSeed:=1+FSeed mod 2147483646;
  FPlan.Duration:=Audio.Duration;
  FFinish:=Audio.SoundEnd;
  if Length(Audio.Hits)>0 then FFinish:=Max(FFinish,Audio.Hits[High(Audio.Hits)].Time+0.46);
  FFinish:=EnsureRange(FFinish,Min(Audio.Duration,0.8),Audio.Duration);
  StageLayout;
  ScheduleBeats;
  ScheduleBosses;
  ScheduleRolls;
  PlaceRoute;
  PlaceEnemies;
  PlanLegs;
  ClearLandings;
end;

function BuildJumpPlan(Audio:TRhythmAudio;const Generation:string;const Cancel:TFunc<Boolean>):TJumpPlan;
var Builder:TJumpBuilder;
begin
  Builder:=TJumpBuilder.Create;
  try
    Result:=TJumpPlan.Create;
    try
      Builder.Build(Audio,Result,Generation,Cancel);
    except
      Result.Free;
      raise;
    end;
  finally
    Builder.Free;
  end;
end;
end.
