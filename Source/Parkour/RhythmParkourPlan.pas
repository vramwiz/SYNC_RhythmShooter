unit RhythmParkourPlan;
// 元の音時刻を使って接触を決め、移動と地形を同じワールド座標から評価する。
interface

uses System.SysUtils, RhythmAudio, RhythmPlanRef;

type
  TParkourKind = (pkVault, pkWall, pkWire, pkDrop, pkStride, pkWallRun);
  TParkourPoint = record
    X, Y: Double; // Yは上向き。移動の座標は足元を表す。
  end;
  TParkourMove = record
    Kind: TParkourKind;
    Start, Cue, Release, Finish: Double;
    LandSynced: Boolean;
    Steps: TArray<Double>; // 元の音時刻。先頭はCue、壁走りの末尾はRelease。
    Origin, Landing, Contact, Anchor: TParkourPoint;
    RoofLeft: Double;
    function Position(Time: Double): TParkourPoint;
    function StepAt(Time: Double): Integer;
    function StepPoint(Index: Integer): TParkourPoint;
    function WallGripPoint(Index: Integer): TParkourPoint;
    function WallGripWeight(Index: Integer; Time: Double): Double;
  end;
  TParkourPlan = class
  public
    Duration: Double;
    Moves: TArray<TParkourMove>;
    function MoveAt(Time: Double): Integer;
    function Position(Time: Double): TParkourPoint;
    function RunEnd: Double;
  end;

const
  ParkourHandHeight = 1.48;
  ParkourHandOffset = 0.32;
  ParkourWallFoot = 0.24;
  ParkourStepHeight = 0.17;

function ParkourPoint(X, Y: Double): TParkourPoint;
function BuildParkourPlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TParkourPlan;
procedure SaveParkourPlan(Plan: TParkourPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
function LoadParkourPlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TParkourPlan;
function LoadParkourAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;

implementation

uses System.Math, System.JSON, System.Generics.Collections, RhythmPreparedData, RhythmStyles;

const
  RunSpeed = 4.6;
  WireLength = 3.05;
  CatchAngle = -1.05;
  ReleaseAngle = 0.93;
  FinalRun = 0.85;
  MaxMoves = 10000;
  MinStepGap = 0.17;
  MaxStepGap = 0.57;
  MaxSteps = 4;
  StrideLead = 0.17;
  WallRunLead = 0.28;

function ParkourPoint(X, Y: Double): TParkourPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Mix(A, B, U: Double): Double;
begin
  Result := A + (B - A) * U;
end;

function Cubic(A, B, C, D, U: Double): Double;
begin
  Result := Mix(Mix(Mix(A, B, U), Mix(B, C, U), U),
    Mix(Mix(B, C, U), Mix(C, D, U), U), U);
end;

function WirePosition(const Anchor: TParkourPoint; Angle: Double): TParkourPoint;
begin
  Result := ParkourPoint(Anchor.X + WireLength * Sin(Angle) - ParkourHandOffset,
    Anchor.Y - WireLength * Cos(Angle) - ParkourHandHeight);
end;

function TParkourMove.StepAt(Time: Double): Integer;
begin
  Result := High(Steps);
  while (Result >= 0) and (Steps[Result] > Time) do Dec(Result);
end;

function TParkourMove.StepPoint(Index: Integer): TParkourPoint;
begin
  if Kind = pkStride then
    Result := ParkourPoint(Origin.X + RunSpeed * (Steps[Index] - Start), Origin.Y + ParkourStepHeight)
  else Result := ParkourPoint(Contact.X, Contact.Y + 0.44 * Index);
end;

function TParkourMove.WallGripPoint(Index: Integer): TParkourPoint;
begin
  if Index = High(Steps) then Exit(ParkourPoint(RoofLeft + 0.05, Landing.Y));
  Result := ParkourPoint(RoofLeft - 0.04, StepPoint(Index).Y + 0.87);
end;

function TParkourMove.WallGripWeight(Index: Integer; Time: Double): Double;
var Age, Weight: Double;
begin
  Age := Time - Steps[Index];
  if Age < 0 then Weight := (Age + 0.16) / 0.12
  else if Index = High(Steps) then
    Weight := 1 - (Age / (Finish - Release) - 0.20) / 0.23
  else
    // 次の手が掛かってから前の手を放す。
    Weight := 1 - (Time - Steps[Index + 1] + 0.04) / 0.11;
  Weight := EnsureRange(Weight, 0.0, 1.0);
  Result := Sqr(Weight) * (3 - 2 * Weight);
end;

function TParkourMove.Position(Time: Double): TParkourPoint;
var
  U, Travel: Double;
  Detach, Step: TParkourPoint;
  Index: Integer;
begin
  if Time <= Start then Exit(Origin);
  if Time >= Finish then Exit(Landing);
  if Time < Cue then
  begin
    U := (Time - Start) / (Cue - Start);
    if Kind = pkStride then
      Exit(ParkourPoint(Mix(Origin.X, Contact.X, U),
        Mix(Origin.Y, Contact.Y, Min(1.0, U / 0.68)) + 0.03 * Sin(Pi * U)));
    Exit(ParkourPoint(Mix(Origin.X, Contact.X, U),
      Mix(Origin.Y, Contact.Y, U) + 0.26 * Sin(Pi * U)));
  end;
  U := (Time - Cue) / (Finish - Cue);
  case Kind of
    pkVault:
      begin
        Travel := Sin(Pi * Power(U, 0.68));
        Result := ParkourPoint(Mix(Origin.X, Landing.X, U), Origin.Y + 0.92 * Travel);
      end;
    pkWall:
      Result := ParkourPoint(Cubic(Contact.X, Contact.X - 0.96, RoofLeft - 0.27, Landing.X, U),
        Cubic(Contact.Y, Landing.Y + 1.15, Landing.Y + 1.63, Landing.Y, U));
    pkWire:
      begin
        if Time <= Release then
        begin
          U := (Time - Cue) / (Release - Cue);
          // 振り子は底に近づくほど速くなる。離す瞬間までワイヤー長は一定。
          Travel := U - 0.36 * Sin(2 * Pi * U) / (2 * Pi);
          Exit(WirePosition(Anchor, Mix(CatchAngle, ReleaseAngle, Travel)));
        end;
        Detach := WirePosition(Anchor, ReleaseAngle);
        U := (Time - Release) / (Finish - Release);
        Result := ParkourPoint(Mix(Detach.X, Landing.X, U),
          Mix(Detach.Y, Landing.Y, U) + 1.18 * Sin(Pi * U));
      end;
    pkDrop:
      Result := ParkourPoint(Mix(Origin.X, Landing.X, U), Mix(Origin.Y, Landing.Y, Sqr(U)));
    pkStride, pkWallRun:
      begin
        Index := StepAt(Time);
        Step := StepPoint(Index);
        if Index < High(Steps) then
        begin
          U := (Time - Steps[Index]) / (Steps[Index + 1] - Steps[Index]);
          if Kind = pkStride then
            Exit(ParkourPoint(Origin.X + RunSpeed * (Time - Start), Step.Y + 0.13 * Sin(Pi * U)));
          Exit(ParkourPoint(Step.X - 0.19 * Sin(Pi * U), Step.Y + 0.44 * U));
        end;
        U := (Time - Steps[Index]) / (Finish - Steps[Index]);
        if Kind = pkStride then
        begin
          // 最後の足場の端を越えてから屋上へ足元を戻す。
          Travel := Max(0.0, (U - 0.45) / 0.55);
          Result := ParkourPoint(Origin.X + RunSpeed * (Time - Start), Mix(Step.Y, Landing.Y, Travel));
        end
        else
          // 屋上の縁を支点に引き上げ、足が縁の高さを越えてから前へ移す。
          Result := ParkourPoint(Cubic(Step.X, Step.X - 0.25, RoofLeft - 0.12, Landing.X, U),
            Cubic(Step.Y, Landing.Y + 0.15, Landing.Y + 0.95, Landing.Y, U));
      end;
  end;
end;

procedure PlaceMoves(Plan: TParkourPlan);
var
  I: Integer;
  Previous: TParkourPoint;
  PreviousEnd, X, Y, Width: Double;
begin
  Previous := ParkourPoint(0, 0);
  PreviousEnd := 0;
  for I := 0 to High(Plan.Moves) do
    with Plan.Moves[I] do
    begin
      X := Previous.X + RunSpeed * (Start - PreviousEnd);
      Y := Previous.Y;
      Origin := ParkourPoint(X, Y);
      Contact := Origin;
      Width := RunSpeed * (Finish - Start);
      case Kind of
        pkVault:
          begin
            Landing := ParkourPoint(X + EnsureRange(Width, 1.85, 3.95), Y);
            RoofLeft := X;
          end;
        pkWall:
          begin
            Contact := ParkourPoint(X + 1.75, Y + 0.66);
            RoofLeft := Contact.X + ParkourWallFoot;
            Landing := ParkourPoint(X + 4.6, Y + 1.85);
          end;
        pkWire:
          begin
            Contact := ParkourPoint(X + 1.50, Y + 1.32);
            Anchor := ParkourPoint(Contact.X + ParkourHandOffset - WireLength * Sin(CatchAngle),
              Contact.Y + ParkourHandHeight + WireLength * Cos(CatchAngle));
            Landing := WirePosition(Anchor, ReleaseAngle);
            RoofLeft := Landing.X + 1.45;
            Landing := ParkourPoint(Landing.X + 2.95, Y + 0.35);
          end;
        pkDrop:
          begin
            Landing := ParkourPoint(X + EnsureRange(Width, 2.85, 5.2), Y - 2.20);
            RoofLeft := X + (Landing.X - X) * 0.60;
          end;
        pkStride:
          begin
            Contact := StepPoint(0);
            Landing := ParkourPoint(X + Width, Y);
            RoofLeft := X;
          end;
        pkWallRun:
          begin
            Contact := ParkourPoint(X + 1.47, Y + 0.58);
            RoofLeft := Contact.X + ParkourWallFoot;
            Landing := ParkourPoint(RoofLeft + 1.35, StepPoint(High(Steps)).Y + 0.78);
          end;
      end;
      Previous := Landing;
      PreviousEnd := Finish;
    end;
end;

function TParkourPlan.RunEnd: Double;
begin
  if Length(Moves) = 0 then Exit(0);
  Result := Min(Duration, Moves[High(Moves)].Finish + FinalRun);
end;

function TParkourPlan.MoveAt(Time: Double): Integer;
var L, R, M: Integer;
begin
  L := 0;
  R := Length(Moves);
  while L < R do
  begin
    M := (L + R) div 2;
    if Moves[M].Start <= Time then L := M + 1 else R := M;
  end;
  Result := L - 1;
end;

function TParkourPlan.Position(Time: Double): TParkourPoint;
var I: Integer;
begin
  Time := EnsureRange(Time, 0.0, Duration);
  I := MoveAt(Time);
  if I < 0 then
  begin
    if Length(Moves) = 0 then Exit(ParkourPoint(0, 0));
    Exit(ParkourPoint(Time * RunSpeed, 0));
  end;
  if Time <= Moves[I].Finish then Exit(Moves[I].Position(Time));
  Result := Moves[I].Landing;
  if I = High(Moves) then
  begin
    // 曲末の短い駆け抜けは、屋上で減速して終える。
    Time := Min(Time, RunEnd) - Moves[I].Finish;
    Result.X := Result.X + RunSpeed * (Time - Sqr(Time) / (2 * FinalRun));
  end
  else Result.X := Result.X + RunSpeed * (Time - Moves[I].Finish);
end;

function BuildParkourPlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TParkourPlan;
const Approach: array[pkVault..pkDrop] of Double = (0.0, WallRunLead, 0.34, 0.0);
      Travel: array[pkVault..pkDrop] of Double = (0.42, 0.61, 0.46, 0.46);
var
  Moves: TList<TParkourMove>;
  Kind: pkVault..pkDrop;
  Move: TParkourMove;
  I, R, E: Integer;
  Available, Deadline, Cue: Double;

  function NextHit(Index: Integer; AtLeast, AtMost: Double): Integer;
  begin
    while (Index < Length(Audio.Hits)) and (Audio.Hits[Index].Time < AtLeast) do Inc(Index);
    if (Index = Length(Audio.Hits)) or (Audio.Hits[Index].Time > AtMost) then Exit(-1);
    Result := Index;
  end;

  function TryFootwork(var Next: Integer; out Footwork: TParkourMove): Boolean;
  var N, Candidate, Count, Minimum: Integer; StepTime, Lead: Double; FootKind: TParkourKind;
  begin
    Result := False;
    if Kind = pkWall then
    begin
      FootKind := pkWallRun;
      Minimum := 2;
      Lead := WallRunLead;
    end
    else
    begin
      // 連打中はワイヤーへ移る代わりに、足運びをもう一度使う。
      if (Kind <> pkVault) and ((Kind <> pkWire) or (NextHit(Next, Cue + MinStepGap, Cue + 0.34) < 0)) then Exit;
      FootKind := pkStride;
      Minimum := 3;
      Lead := StrideLead;
    end;
    if Cue - Lead < Available then Exit;
    Footwork := Default(TParkourMove);
    SetLength(Footwork.Steps, MaxSteps);
    Footwork.Steps[0] := Cue;
    Count := 1;
    N := Next;
    StepTime := Cue;
    while Count < MaxSteps do
    begin
      Candidate := NextHit(N, StepTime + MinStepGap, Min(StepTime + MaxStepGap, Deadline - 0.15));
      if Candidate < 0 then Break;
      StepTime := Audio.Hits[Candidate].Time;
      Footwork.Steps[Count] := StepTime;
      Inc(Count);
      N := Candidate + 1;
    end;
    if Count < Minimum then Exit;
    SetLength(Footwork.Steps, Count);
    Footwork.Kind := FootKind;
    Footwork.Start := Cue - Lead;
    Footwork.Cue := Cue;
    Footwork.Release := Cue;
    Footwork.Finish := StepTime + 0.14;
    if FootKind = pkWallRun then
    begin
      if StepTime + 0.38 > Audio.Duration then Exit;
      Footwork.Release := StepTime;
      Candidate := NextHit(N, StepTime + 0.39, Min(StepTime + 0.82, Deadline));
      Footwork.LandSynced := Candidate >= 0;
      if Footwork.LandSynced then
      begin
        Footwork.Finish := Audio.Hits[Candidate].Time;
        N := Candidate + 1;
      end
      else Footwork.Finish := Min(Audio.Duration, StepTime + 0.49);
    end;
    Next := N;
    Result := True;
  end;

begin
  Moves := TList<TParkourMove>.Create;
  try
    Kind := pkVault;
    Available := 0;
    I := 0;
    Deadline := Audio.Duration;
    if Audio.SoundEnd > 0 then Deadline := Min(Deadline, Audio.SoundEnd + 0.18);
    while (I < Length(Audio.Hits)) and (Moves.Count < MaxMoves) do
    begin
      if Assigned(Cancel) and Cancel() then Abort;
      Cue := Audio.Hits[I].Time;
      Inc(I);
      if (Cue < Available + Approach[Kind]) or (Cue + 0.32 > Audio.Duration) then Continue;
      if TryFootwork(I, Move) then Available := Move.Finish + 0.05
      else
      begin
        Move := Default(TParkourMove);
        Move.Kind := Kind;
        Move.Start := Cue - Approach[Kind];
        Move.Cue := Cue;
        Move.Release := Cue;
        R := I;
        if Kind = pkWire then
        begin
          R := NextHit(I, Cue + 0.62, Min(Cue + 1.24, Deadline - 0.48));
          if R < 0 then
          begin
            // 疎な曲では、実音のないワイヤーの解除を作らず短い柵越えへ戻す。
            Move.Kind := pkVault;
            Move.Start := Cue;
            R := I;
          end
          else Move.Release := Audio.Hits[R].Time;
        end;
        E := NextHit(R, Move.Release + Travel[Move.Kind], Min(Move.Release + 1.19, Deadline));
        Move.LandSynced := E >= 0;
        if Move.LandSynced then
        begin
          Move.Finish := Audio.Hits[E].Time;
          I := E + 1;
        end
        else
        begin
          Move.Finish := Min(Audio.Duration, Move.Release + Travel[Move.Kind] + 0.06);
          while (I < Length(Audio.Hits)) and (Audio.Hits[I].Time <= Move.Finish) do Inc(I);
        end;
        Available := Move.Finish + 0.12;
      end;
      Moves.Add(Move);
      if Kind = pkDrop then Kind := pkVault else Inc(Kind);
    end;
    Result := TParkourPlan.Create;
    try
      Result.Duration := Audio.Duration;
      Result.Moves := Moves.ToArray;
      PlaceMoves(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Moves.Free;
  end;
end;

procedure SaveParkourPlan(Plan: TParkourPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
var Root: TJSONObject; Rows, Row, Steps: TJSONArray; Move: TParkourMove; Time: Double;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(1));
    Root.AddPair('style', StyleId(rsParkour));
    Root.AddPair('version', TJSONNumber.Create(Ref.Version));
    Root.AddPair('key', Ref.Key);
    Root.AddPair('source', Ref.SourceKey);
    Root.AddPair('sensitivity', TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction', TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root, Audio);
    Root.AddPair('duration', PreparedExact(Plan.Duration));
    Rows := TJSONArray.Create;
    Root.AddPair('moves', Rows);
    for Move in Plan.Moves do
    begin
      Row := TJSONArray.Create;
      Rows.AddElement(Row);
      Row.Add(Ord(Move.Kind));
      Row.AddElement(PreparedExact(Move.Start));
      Row.AddElement(PreparedExact(Move.Cue));
      Row.AddElement(PreparedExact(Move.Release));
      Row.AddElement(PreparedExact(Move.Finish));
      Row.Add(Ord(Move.LandSynced));
      if Ref.Version >= 2 then
      begin
        Steps := TJSONArray.Create;
        Row.AddElement(Steps);
        for Time in Move.Steps do Steps.AddElement(PreparedExact(Time));
      end;
    end;
    WritePreparedData(Root, Ref);
  finally
    Root.Free;
  end;
end;

function LoadParkourAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
var Root: TJSONObject;
begin
  Root := ReadPreparedData(Ref, rsParkour, Direction);
  try
    Result := PreparedAudio(Root, Ref, Source);
    Result.Hits := nil; // 曲解析は不要。共通EQへは保存済みの接触から活動値を返す。
  finally
    Root.Free;
  end;
end;

procedure RequirePlan(Valid: Boolean);
begin
  if not Valid then raise EConvertError.Create('パルクールの保存計画が不正です。再準備してください。');
end;

procedure ReadSteps(Value: TJSONValue; var Move: TParkourMove);
var Steps: TJSONArray; I: Integer;
begin
  RequirePlan(Value is TJSONArray);
  Steps := TJSONArray(Value);
  if not (Move.Kind in [pkStride, pkWallRun]) then
  begin
    RequirePlan(Steps.Count = 0);
    Exit;
  end;
  RequirePlan((Steps.Count >= 2) and (Steps.Count <= MaxSteps));
  SetLength(Move.Steps, Steps.Count);
  for I := 0 to High(Move.Steps) do
  begin
    Move.Steps[I] := ReadPreparedExact(Steps.Items[I]);
    if I > 0 then RequirePlan(InRange(Move.Steps[I] - Move.Steps[I - 1], MinStepGap - 1E-8, MaxStepGap + 1E-8));
  end;
  RequirePlan((Move.Steps[0] = Move.Cue) and (Move.Steps[High(Move.Steps)] < Move.Finish));
  if Move.Kind = pkWallRun then RequirePlan(Move.Steps[High(Move.Steps)] = Move.Release);
end;

function LoadParkourPlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TParkourPlan;
var Root: TJSONObject; Value: TJSONValue; Rows, Row: TJSONArray;
  I, Kind, LandSynced, MaxKind: Integer; PreviousEnd: Double; Move: TParkourMove;
begin
  RequirePlan(Ref.Matches(Audio.Key, Audio.Sensitivity, Direction, rsParkour));
  Root := ReadPreparedData(Ref, rsParkour, Direction);
  try
    Result := TParkourPlan.Create;
    try
      Result.Duration := ReadPreparedExact(Root.GetValue('duration'));
      RequirePlan((Result.Duration > 0) and (Abs(Result.Duration - Audio.Duration) < 1E-8));
      Value := Root.GetValue('moves');
      RequirePlan(Value is TJSONArray);
      Rows := TJSONArray(Value);
      RequirePlan(Rows.Count <= MaxMoves);
      SetLength(Result.Moves, Rows.Count);
      MaxKind := Ord(High(TParkourKind));
      if Ref.Version = 1 then MaxKind := Ord(pkDrop);
      PreviousEnd := 0;
      for I := 0 to Rows.Count - 1 do
      begin
        RequirePlan(Rows.Items[I] is TJSONArray);
        Row := TJSONArray(Rows.Items[I]);
        RequirePlan(Row.Count = 5 + Ref.Version);
        Kind := StrToInt(Row.Items[0].Value);
        LandSynced := StrToInt(Row.Items[5].Value);
        RequirePlan((Kind >= Ord(Low(TParkourKind))) and (Kind <= MaxKind) and
          (LandSynced in [0, 1]));
        Move := Default(TParkourMove);
        Move.Kind := TParkourKind(Kind);
        Move.LandSynced := LandSynced = 1;
        Move.Start := ReadPreparedExact(Row.Items[1]);
        Move.Cue := ReadPreparedExact(Row.Items[2]);
        Move.Release := ReadPreparedExact(Row.Items[3]);
        Move.Finish := ReadPreparedExact(Row.Items[4]);
        RequirePlan((Move.Start >= PreviousEnd) and (Move.Start <= Move.Cue) and
          (Move.Cue <= Move.Release) and (Move.Release < Move.Finish) and (Move.Finish <= Result.Duration) and
          ((Move.Kind in [pkWire, pkWallRun]) = (Move.Release > Move.Cue)));
        if Ref.Version >= 2 then ReadSteps(Row.Items[6], Move);
        Result.Moves[I] := Move;
        PreviousEnd := Move.Finish;
      end;
      PlaceMoves(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;

end.
