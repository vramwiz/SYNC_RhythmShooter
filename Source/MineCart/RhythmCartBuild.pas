unit RhythmCartBuild;
// 音時刻を先に決め、速度・地形・危険とコインの接触位置を組み立てる。
interface
uses System.SysUtils,RhythmAudio,RhythmCartPlan;
function BuildCartPlan(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TCartPlan;

implementation
uses System.Math,System.Types,System.Generics.Collections,RhythmSections;

type
  TCartBuilder=class
  private
    Audio:TRhythmAudio;
    Plan:TCartPlan;
    Cancel:TFunc<Boolean>;
    Seed:UInt64;
    Moves:TList<TCartMove>;
    Bosses:TList<TCartBoss>;
    NextAction:Double;
    ActionNumber:Integer;
    procedure CheckCancel;
    function Pick(Count:Integer):Integer;
    procedure ReadAccents;
    procedure LayRail;
    function AtAccent(Time,Limit:Double):Double;
    function MakeMove(Kind:TCartMoveKind;Time:Double):TCartMove;
    procedure RegularUntil(Limit:Double);
    procedure Choreograph;
  public
    procedure Build(Source:TRhythmAudio;Destination:TCartPlan;const IsCancelled:TFunc<Boolean>);
  end;

procedure TCartBuilder.CheckCancel;
begin
  if Assigned(Cancel) and Cancel() then Abort;
end;

function TCartBuilder.Pick(Count:Integer):Integer;
begin
  Seed:=(Seed*48271) mod 2147483647;
  Result:=Integer(Seed mod UInt64(Count));
end;

procedure TCartBuilder.ReadAccents;
var I,N:Integer; H:TRhythmHit;
begin
  SetLength(Plan.Coins,Length(Audio.Hits));
  N:=0;
  for I:=0 to High(Audio.Hits) do begin
    if I mod 128=0 then CheckCancel;
    H:=Audio.Hits[I];
    if (H.Time<0) or (H.Time>Plan.Goal) then Continue;
    if (N>0) and (H.Time<=Plan.Coins[N-1].Time) then begin
      if H.Time=Plan.Coins[N-1].Time then
        Plan.Coins[N-1].Strength:=Max(Plan.Coins[N-1].Strength,EnsureRange(H.Strength,0.0,1.0));
      Continue;
    end;
    Plan.Coins[N].Time:=H.Time;
    Plan.Coins[N].Strength:=EnsureRange(H.Strength,0.0,1.0);
    Inc(N);
  end;
  SetLength(Plan.Coins,N);
end;

procedure TCartBuilder.LayRail;
const Ridge:array[0..11] of Double=(0,1.28,3.18,0.19,-0.66,1.67,3.43,0.82,-0.92,1.59,2.89,0.31);
var I,Count,Phase:Integer; Span,T,Energy:Double; N,Previous:TCartKnot;
begin
  Count:=Max(1,Round(Plan.Goal/2.45));
  Span:=Plan.Goal/Count;
  SetLength(Plan.Knots,Count+1);
  Phase:=Pick(Length(Ridge)-3);
  for I:=0 to Count do begin
    CheckCancel;
    T:=I*Span;
    if (I>0) and (I<Count) then T:=AtAccent(T,T+0.18);
    if I=Count then T:=Plan.Goal;
    Energy:=EnsureRange(Audio.LevelAt(T),0.0,1.0);
    N:=Default(TCartKnot);
    N.Time:=T;
    N.Speed:=6.15+2.65*T/Plan.Goal+0.95*Energy;
    N.Theme:=Trunc(T/16.0) mod 5;
    if I>0 then begin
      Previous:=Plan.Knots[I-1];
      N.Y:=EnsureRange(Ridge[(I+Phase) mod Length(Ridge)]+0.19*Pick(4),
        Previous.Y-(T-Previous.Time)*1.95,Previous.Y+(T-Previous.Time)*1.32);
      N.X:=Previous.X+CartRunDistance(Previous,N);
    end;
    Plan.Knots[I]:=N;
  end;
end;

function TCartBuilder.AtAccent(Time,Limit:Double):Double;
var I:Integer; Distance:Double;
begin
  Result:=Time;
  Distance:=0.30;
  I:=Plan.CoinFrom(Time-0.30);
  while (I<Length(Plan.Coins)) and (Plan.Coins[I].Time<=Min(Limit,Time+0.30)) do begin
    if Abs(Plan.Coins[I].Time-Time)<Distance then begin
      Result:=Plan.Coins[I].Time;
      Distance:=Abs(Result-Time);
    end;
    Inc(I);
  end;
end;

function TCartBuilder.MakeMove(Kind:TCartMoveKind;Time:Double):TCartMove;
begin
  Result.Kind:=Kind;
  Result.Hit:=Time;
  Result.Start:=Time-0.43;
  Result.Finish:=Time+0.40;
  Result.Height:=1.22;
  case Kind of
    cmStomp,cmBoss:begin
      Result.Start:=Time-0.58;
      Result.Finish:=Time+0.21;
      Result.Height:=1.62+Ord(Kind=cmBoss)*0.17;
    end;
    cmFork:begin
      Result.Start:=Time-0.56;
      Result.Finish:=Time+0.51;
      Result.Height:=0.50;
    end;
    cmLift:Result.Height:=1.40;
    cmFlame:Result.Height:=1.54;
    cmRam:Result.Height:=1.88;
    cmCollapse,cmRival:Result.Height:=0;
  end;
end;

procedure TCartBuilder.RegularUntil(Limit:Double);
const Sequence:array[0..13] of TCartMoveKind=(cmGap,cmFork,cmStomp,cmRam,cmFlame,cmLift,cmCollapse,
  cmRival,cmRam,cmStomp,cmFork,cmRival,cmCollapse,cmRam);
var Time:Double; M:TCartMove; Kind:TCartMoveKind;
begin
  while NextAction+0.64<Limit do begin
    CheckCancel;
    Time:=AtAccent(NextAction,Limit-0.55);
    Kind:=Sequence[ActionNumber mod Length(Sequence)];
    if (Time<6.0) and (Kind=cmRival) then Kind:=cmCollapse;
    M:=MakeMove(Kind,Time);
    if ((Kind=cmStomp) and not Plan.CanStomp(M)) or ((Kind=cmFlame) and not Plan.CanClearFlame(M)) or
      ((Kind=cmRam) and not Plan.CanClearRam(M)) or ((Kind=cmRival) and not Plan.CanClearThrow(M)) then
      M:=MakeMove(cmGap,Time);
    Moves.Add(M);
    Inc(ActionNumber);
    NextAction:=Time+2.42-0.83*Time/Plan.Goal+0.13*Pick(4);
  end;
end;

procedure TCartBuilder.Choreograph;
var
  I,J,Required:Integer;
  First,Last,Previous,Time,StartLimit:Double;
  Cue:TRhythmBossCue;
  M:TCartMove;
  Boss:TCartBoss;
  Spots:TList<TCartMove>;
begin
  Spots:=TList<TCartMove>.Create;
  try
    NextAction:=2.05;
    Previous:=0;
    for I:=0 to Audio.BossCount-1 do begin
      CheckCancel;
      Cue:=Audio.BossCue(I);
      Required:=Min(8,Bosses.Count+2);
      Last:=Min(Plan.Goal-0.42,Cue.KillTime);
      First:=Max(Previous+2.30,Last-(Required*1.50+2.8));
      First:=Max(First,5.0);
      Spots.Clear;
      J:=Plan.CoinFrom(Last+0.000001)-1;
      while (J>=0) and (Plan.Coins[J].Time>=First) and (Spots.Count<Required) do begin
        if J mod 128=0 then CheckCancel;
        Time:=Plan.Coins[J].Time;
        if Time<=Last then begin
          M:=MakeMove(cmBoss,Time);
          if Plan.CanStomp(M) and Plan.CanClearBoss(M,True) and Plan.CanClearBoss(M,False) then begin
            Spots.Add(M);
            Last:=Time-0.97;
          end;
        end;
        Dec(J);
      end;
      if Spots.Count<>Required then Continue;
      StartLimit:=Spots.Last.Start-0.25;
      RegularUntil(StartLimit);
      Boss.FirstMove:=Moves.Count;
      for J:=Spots.Count-1 downto 0 do Moves.Add(Spots[J]);
      Boss.LastMove:=Moves.Count-1;
      Bosses.Add(Boss);
      Previous:=Moves.Last.Finish;
      NextAction:=Previous+1.08;
    end;
    RegularUntil(Plan.Goal-0.23);
    Plan.Moves:=Moves.ToArray;
    Plan.Bosses:=Bosses.ToArray;
  finally
    Spots.Free;
  end;
end;

procedure TCartBuilder.Build(Source:TRhythmAudio;Destination:TCartPlan;const IsCancelled:TFunc<Boolean>);
var I:Integer; P:TPointF;
begin
  Audio:=Source;
  Plan:=Destination;
  Cancel:=IsCancelled;
  if not TryStrToUInt64('$'+Copy(Audio.Key,1,10),Seed) then Seed:=8317;
  Seed:=1+Seed mod 2147483646;
  CheckCancel;
  Plan.Duration:=Audio.Duration;
  Plan.Goal:=EnsureRange(Audio.SoundEnd,Min(2.0,Audio.Duration),Audio.Duration);
  if Length(Audio.Hits)>0 then
    Plan.Goal:=Min(Audio.Duration,Max(Plan.Goal,Audio.Hits[High(Audio.Hits)].Time+0.42));
  ReadAccents;
  LayRail;
  Moves:=TList<TCartMove>.Create;
  Bosses:=nil;
  try
    Bosses:=TList<TCartBoss>.Create;
    Choreograph;
  finally
    Bosses.Free;
    Moves.Free;
  end;
  for I:=0 to High(Plan.Coins) do begin
    if I mod 128=0 then CheckCancel;
    P:=Plan.CoinPosition(Plan.Coins[I].Time);
    Plan.Coins[I].X:=P.X;
    Plan.Coins[I].Y:=P.Y;
  end;
  Plan.Verify;
end;

function BuildCartPlan(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TCartPlan;
var Builder:TCartBuilder;
begin
  Builder:=TCartBuilder.Create;
  try
    Result:=TCartPlan.Create;
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
