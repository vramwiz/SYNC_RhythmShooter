unit RhythmRobotPlan;
// ロボット大戦の全曲演出。保存する秒は検出音そのものを使い、描画履歴を持たない。
interface

uses System.SysUtils, RhythmAudio;

type
  TRobotTeam = (rtAlly, rtEnemy);
  TRobotForm = (rfCar, rfJet, rfTrain, rfBeast);
  TRobotStageKind = (rkLanding, rkArrival, rkTransform, rkBattle, rkCombine,
    rkFinisher, rkCollapse, rkVictory);
  TRobotAttack = (raPunch, raKick, raSlash, raShot, raMissile, raBeam, raSpecial);
  TRobotReaction = (rrHit, rrGuard, rrDodge, rrDown);
  TRobotStage = record
    Start, Finish: Double;
    Kind: TRobotStageKind;
    Team: TRobotTeam;
    Allies, Enemies, AllyAssembly, EnemyAssembly: Integer;
    // 変形・合体の8工程。候補のない工程は補間時刻とし、同期発光を出さない。
    Locks: array[0..7] of Double;
    Synced: array[0..7] of Boolean;
    function Progress(Time: Double): Double;
    function Mechanism(Time: Double): Double;
    function Members(Side: TRobotTeam): Integer;
    function Assembly(Side: TRobotTeam): Integer;
  end;
  TRobotCue = record
    Time, Lead, Recover, Power: Double;
    Stage, Member: Integer;
    Team: TRobotTeam;
    Attack: TRobotAttack;
    Reaction: TRobotReaction;
  end;
  TRobotPlan = class
  public
    Duration: Double;
    Palette: Integer;
    Stages: TArray<TRobotStage>;
    Cues: TArray<TRobotCue>;
    function StageAt(Time: Double): Integer;
    function CueAt(Time: Double): Integer;
  end;

function RobotEase(Value: Double): Double;
function RobotRange(Time, First, Last: Double): Double;
function RobotForm(Team: TRobotTeam; Member: Integer): TRobotForm;
function BuildRobotPlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TRobotPlan;

implementation

uses System.Math, System.Generics.Collections;

function RobotEase(Value: Double): Double;
begin
  Value := EnsureRange(Value, 0.0, 1.0);
  Result := Value * Value * (3 - 2 * Value);
end;

function RobotRange(Time, First, Last: Double): Double;
begin
  if Last <= First then Exit(Ord(Time >= Last));
  Result := RobotEase((Time - First) / (Last - First));
end;

function RobotForm(Team: TRobotTeam; Member: Integer): TRobotForm;
const Forms: array[TRobotTeam, 0..2] of TRobotForm =
  ((rfCar, rfJet, rfBeast), (rfBeast, rfTrain, rfJet));
begin
  Result := Forms[Team, EnsureRange(Member, 0, 2)];
end;

function TRobotStage.Progress(Time: Double): Double;
begin
  Result := EnsureRange((Time - Start) / (Finish - Start), 0.0, 1.0);
end;

function TRobotStage.Mechanism(Time: Double): Double;
var I: Integer; Previous: Double;
begin
  Previous := Start;
  for I := 0 to High(Locks) do
  begin
    if Time < Locks[I] then Exit((I + RobotRange(Time, Previous, Locks[I])) / 8);
    Previous := Locks[I];
  end;
  Result := 1;
end;

function TRobotStage.Members(Side: TRobotTeam): Integer;
begin
  if Side = rtAlly then Result := Allies else Result := Enemies;
end;

function TRobotStage.Assembly(Side: TRobotTeam): Integer;
begin
  if Side = rtAlly then Result := AllyAssembly else Result := EnemyAssembly;
end;

function TRobotPlan.StageAt(Time: Double): Integer;
var L, R, M: Integer;
begin
  L := 0;
  R := High(Stages);
  Result := 0;
  while L <= R do
  begin
    M := (L + R) div 2;
    if Stages[M].Start <= Time then begin Result := M; L := M + 1; end
    else R := M - 1;
  end;
end;

function TRobotPlan.CueAt(Time: Double): Integer;
var L, R, M: Integer;
begin
  L := 0;
  R := High(Cues);
  Result := -1;
  while L <= R do
  begin
    M := (L + R) div 2;
    if Cues[M].Time <= Time then begin Result := M; L := M + 1; end
    else R := M - 1;
  end;
end;

function BuildRobotPlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TRobotPlan;
const
  Kinds: array[0..27] of TRobotStageKind =
    (rkLanding, rkArrival, rkTransform, rkBattle, rkBattle, rkArrival, rkTransform,
     rkBattle, rkCombine, rkBattle, rkArrival, rkTransform, rkBattle, rkCombine,
     rkBattle, rkArrival, rkTransform, rkBattle, rkCombine, rkBattle, rkArrival,
     rkTransform, rkBattle, rkCombine, rkBattle, rkFinisher, rkCollapse, rkVictory);
  Sides: array[0..27] of TRobotTeam =
    (rtEnemy, rtAlly, rtAlly, rtAlly, rtEnemy, rtAlly, rtAlly, rtAlly,
     rtAlly, rtAlly, rtEnemy, rtEnemy, rtEnemy, rtEnemy, rtEnemy,
     rtAlly, rtAlly, rtAlly, rtAlly, rtAlly, rtEnemy, rtEnemy, rtEnemy,
     rtEnemy, rtEnemy, rtAlly, rtEnemy, rtAlly);
  Weights: array[0..27] of Double =
    (2, 2, 3.5, 5, 2.5, 2, 3, 3, 5, 4, 2, 3, 3, 5, 4, 2, 3, 3, 5.5, 4,
     2, 3, 3, 5.5, 5, 3, 2.5, 3.5);
var
  Stage: TRobotStage; Cue: TRobotCue; Hit: TRhythmHit;
  List: TList<TRobotCue>; Counts, Assemblies: array[TRobotTeam] of Integer;
  I, J, K, Best, StageIndex, AttackIndex, Count: Integer;
  Total, Position, Target, Error, BestError, Previous, Gap, EndTime: Double;
begin
  if (Audio = nil) or IsNan(Audio.Duration) or IsInfinite(Audio.Duration) or
    (Audio.Duration <= 0) then raise EArgumentException.Create('ロボット大戦の音源長が不正です。');
  Result := TRobotPlan.Create;
  List := TList<TRobotCue>.Create;
  try
    Result.Duration := Audio.Duration;
    // 同じ曲の色と展開を再現し、解析の感度や描画順序には依存させない。
    Result.Palette := 0;
    if Audio.Key <> '' then Result.Palette := Ord(Audio.Key[1]) mod 4;
    Total := 0;
    for I := 0 to High(Weights) do Total := Total + Weights[I];
    Counts[rtAlly] := 0;
    Counts[rtEnemy] := 1;
    Assemblies[rtAlly] := 1;
    Assemblies[rtEnemy] := 1;
    Position := 0;
    SetLength(Result.Stages, Length(Kinds));
    for I := 0 to High(Kinds) do
    begin
      if Assigned(Cancel) and Cancel() then Abort;
      Stage := Default(TRobotStage);
      Stage.Kind := Kinds[I];
      Stage.Team := Sides[I];
      Stage.Start := Position / Total * Result.Duration;
      Position := Position + Weights[I];
      Stage.Finish := Position / Total * Result.Duration;
      if I = High(Kinds) then Stage.Finish := Result.Duration;
      if Stage.Kind = rkArrival then Inc(Counts[Stage.Team]);
      Stage.Allies := Counts[rtAlly];
      Stage.Enemies := Counts[rtEnemy];
      Stage.AllyAssembly := Assemblies[rtAlly];
      Stage.EnemyAssembly := Assemblies[rtEnemy];
      Previous := Stage.Start;
      for J := 0 to High(Stage.Locks) do
      begin
        Target := Stage.Start + (Stage.Finish - Stage.Start) * (J + 1) / 8.6;
        Best := -1;
        BestError := (Stage.Finish - Stage.Start) * 0.036;
        K := Max(0, Audio.NearestHit(Target) - 2);
        while K < Length(Audio.Hits) do
        begin
          Hit := Audio.Hits[K];
          if Hit.Time > Target + BestError then Break;
          Error := Abs(Hit.Time - Target);
          if (Hit.Time > Previous + (Stage.Finish - Stage.Start) * 0.045) and
            (Hit.Time < Stage.Finish) and (Error <= BestError) then
          begin
            Best := K;
            BestError := Error;
          end;
          Inc(K);
        end;
        Stage.Synced[J] := Best >= 0;
        if Best >= 0 then Stage.Locks[J] := Audio.Hits[Best].Time else Stage.Locks[J] := Target;
        Previous := Stage.Locks[J];
      end;
      Result.Stages[I] := Stage;
      if Stage.Kind = rkCombine then Assemblies[Stage.Team] := Counts[Stage.Team];
    end;
    StageIndex := 0;
    AttackIndex := 0;
    Previous := -1;
    for I := 0 to High(Audio.Hits) do
    begin
      if Assigned(Cancel) and Cancel() then Abort;
      Hit := Audio.Hits[I];
      if IsNan(Hit.Time) or IsInfinite(Hit.Time) or (Hit.Time < 0) or
        (Hit.Time > Result.Duration) or (Hit.Time <= Previous) then Continue;
      while (StageIndex < High(Result.Stages)) and
        (Hit.Time >= Result.Stages[StageIndex].Finish) do Inc(StageIndex);
      Stage := Result.Stages[StageIndex];
      if not (Stage.Kind in [rkBattle, rkFinisher]) then Continue;
      Gap := 0.6;
      if I > 0 then Gap := Min(Gap, Hit.Time - Audio.Hits[I - 1].Time);
      if I < High(Audio.Hits) then Gap := Min(Gap, Audio.Hits[I + 1].Time - Hit.Time);
      Gap := Min(Gap, Min(Hit.Time - Stage.Start, Stage.Finish - Hit.Time));
      if (Gap < 0.045) or (Hit.Time - Previous < 0.095) then Continue;
      Cue := Default(TRobotCue);
      Cue.Stage := StageIndex;
      Cue.Time := Hit.Time;
      Cue.Power := EnsureRange(Hit.Strength, 0.0, 1.0);
      Cue.Lead := Min(0.48, Gap * 0.76);
      Cue.Recover := Min(0.46, Gap * 0.78);
      Cue.Team := Stage.Team;
      if AttackIndex mod 5 = 3 then Cue.Team := TRobotTeam(1 - Ord(Cue.Team));
      Count := Stage.Members(Cue.Team);
      Cue.Member := 0;
      if (Count > Stage.Assembly(Cue.Team)) and Odd(AttackIndex) then Cue.Member := Count - 1;
      Cue.Attack := TRobotAttack(AttackIndex mod 6);
      if Gap < 0.22 then Cue.Attack := raShot;
      Cue.Reaction := rrHit;
      if AttackIndex mod 6 = 2 then Cue.Reaction := rrGuard;
      if AttackIndex mod 8 = 4 then Cue.Reaction := rrDodge;
      if (AttackIndex mod 11 = 7) and (Gap > 0.28) then Cue.Reaction := rrDown;
      if Stage.Kind = rkFinisher then
      begin
        Cue.Team := rtAlly;
        Cue.Member := 0;
        Cue.Attack := raSpecial;
        Cue.Reaction := rrHit;
        Cue.Lead := Min(0.85, Gap * 0.90);
        Cue.Recover := Min(0.65, Gap * 0.85);
      end;
      List.Add(Cue);
      Previous := Hit.Time;
      Inc(AttackIndex);
    end;
    // 静かな曲も完全な物語を持つ。未検出の音に命中や同期の印は捏造しない。
    Result.Cues := List.ToArray;
    EndTime := Result.Stages[High(Result.Stages) - 1].Start;
    for I := 0 to High(Result.Cues) do
      if Result.Cues[I].Time >= EndTime then
        raise EInvalidOpException.Create('勝利演出と攻撃時刻が重なっています。');
  except
    List.Free;
    Result.Free;
    raise;
  end;
  List.Free;
end;

end.
