unit RhythmTrapBuild;
// 先に安全な動作を連結し、その軌道に対して罠・足場・音の結果時刻を逆算して配置する。
interface

uses System.SysUtils, RhythmAudio, RhythmStyles, RhythmTrapPlan;

function BuildTrapPlan(Audio: TRhythmAudio; Theme: TTrapStage; const Cancel: TFunc<Boolean>): TTrapPlan;
procedure ValidateTrapPlan(Plan: TTrapPlan; const Cancel: TFunc<Boolean>);

implementation

uses System.Math, System.Generics.Collections, System.Generics.Defaults;

type
  TAnchor = record
    Time, Power: Double;
    Synced: Boolean;
  end;

function PatternFor(Section: Integer; Progress: Double; Theme: TTrapStage): Integer;
const Favorites: array[TTrapStage] of Integer = (3, 12, 6, 17, 11, 8, 15, 5);
begin
  Result := (Section * 7 + Ord(Theme) * 3 + (Section div 20) * 11) mod 20;
  if Progress < 0.25 then Result := (Section + Ord(Theme)) mod 6
  else if Section mod 4 = 2 then Result := Favorites[Theme];
end;

procedure ChooseMotion(Pattern, Phase: Integer; var Kind: TTrapMotion; var TargetY, Arc: Double;
  var Landing: Boolean);
begin
  Kind := tmJump; Arc := 1.30; TargetY := 0; Landing := True;
  case Pattern of
    0, 12: begin Arc := 1.0 + Phase * 0.35; if Phase = 1 then TargetY := 0.45; end;
    1, 8:
      case Phase of
        0: begin TargetY := 1.25; Arc := 0.95; Landing := False; end;
        1: begin Kind := tmDoubleJump; TargetY := 1.75; Arc := 1.20; end;
        2: begin TargetY := 0; Arc := 0.85; end;
      end;
    2, 6, 11, 19:
      begin
        Arc := 0;
        Kind := tmRun;
        if Phase = 1 then Kind := tmSlide;
        if (Phase = 2) and (Pattern = 19) then begin Kind := tmWallKick; Arc := 1.6; end;
      end;
    3, 14, 18:
      begin
        if Phase = 0 then begin Kind := tmStop; Arc := 0; end;
        if Phase = 1 then begin Kind := tmRun; Arc := 0; end;
        if Phase = 2 then begin Kind := tmLaunch; Arc := 2.0; end;
      end;
    4:
      case Phase of
        0: begin TargetY := 1.8; Arc := 1.2; end;
        1: begin Kind := tmFall; TargetY := -0.65; Arc := 0.9; Landing := False; end;
        2: begin Kind := tmWallKick; Arc := 1.8; end;
      end;
    5:
      case Phase of
        0: begin TargetY := 1.05; Arc := 1.4; Landing := False; end;
        1: begin Kind := tmHang; TargetY := 1.05; Arc := 0; Landing := False; end;
        2: begin Kind := tmClimb; TargetY := 2.17; Arc := 0; Landing := True; end;
        3: begin TargetY := 0; Arc := 1.3; end;
      end;
    7:
      begin
        if Phase = 0 then TargetY := 0.8;
        if Phase = 1 then begin Kind := tmRide; TargetY := 0.8; Arc := 0; end;
      end;
    9:
      begin
        if Phase = 0 then begin Kind := tmRun; Arc := 0; end;
        if Phase = 1 then begin Kind := tmRide; TargetY := -0.9; Arc := 0; end;
        if Phase = 2 then Arc := 1.7;
      end;
    10:
      begin
        if Phase = 0 then TargetY := 0.6;
        if Phase = 1 then begin Kind := tmLaunch; TargetY := 1.3; Arc := 1.6; end;
      end;
    13: if Phase = 0 then begin Kind := tmSlide; Arc := 0; end;
    15:
      begin
        if Phase = 0 then begin Kind := tmSkate; TargetY := -0.45; Arc := 0; end;
        if Phase = 2 then begin Kind := tmSlide; Arc := 0; end;
      end;
    16:
      begin
        if Phase = 0 then begin Kind := tmSkate; TargetY := 0.55; Arc := 0; end;
        if Phase = 2 then begin Kind := tmStop; Arc := 0; end;
      end;
    17: if Phase = 0 then begin Kind := tmRun; Arc := 0; end;
  end;
end;

function PrimaryKind(Pattern, Phase: Integer): TTrapKind;
const Kinds: array[0..19] of TTrapKind = (tkSpikes, tkFalseFloor, tkCeiling, tkBoulder,
  tkPit, tkBlade, tkLaser, tkMoving, tkFlame, tkSink, tkFlip, tkArrow, tkBridge,
  tkRain, tkBackground, tkIce, tkTilt, tkDoor, tkHunter, tkWallBlock);
begin
  Result := Kinds[Pattern];
  if (Phase = 0) and (Pattern = 1) then Result := tkVanish;
  if (Phase = 1) and (Pattern = 0) then Result := tkHiddenSpikes;
  if (Phase = 2) and (Pattern = 12) then Result := tkCrumble;
  if (Phase = 1) and (Pattern = 4) then Result := tkWall;
  if (Phase = 2) and (Pattern = 5) then Result := tkFlyingBlade;
  if (Phase = 2) and (Pattern = 13) then Result := tkRock;
end;

function SafeDuring(Plan: TTrapPlan; const Trap: TTrapObstacle): Boolean;
var I, J, Count: Integer; T, Speed, Step, Span: Double;M:TTrapMove;
begin
  if TrapHarmless(Trap.Kind) then Exit(True);
  // 罠と身体の速度上限から検査間隔を決め、時刻の間にも0.05以上の余白を残す。
  Step:=Max(1E-9,Min(Trap.Cue-Trap.Fire,Trap.Finish-Trap.Cue));
  Speed:=1.5*(Trap.Travel+Trap.H+5)/Step+4*Trap.Travel;
  for J:=Plan.MoveAt(Trap.Fire) to Plan.MoveAt(Trap.Finish) do begin
    M:=Plan.Moves[J];Span:=M.Finish-M.Start;
    Speed:=Max(Speed,1.5*(Trap.Travel+Trap.H+5)/Step+4*Trap.Travel+
      (1.5*(Abs(M.Target.X-M.Origin.X)+Abs(M.Target.Y-M.Origin.Y))+4*M.Arc)/Span+
      1.1/Max(1E-9,Min(M.Cue-M.Start,M.Finish-M.Cue)));
  end;
  Count := Max(2, Ceil((Trap.Finish - Trap.Fire) * Max(1000.0,Speed/0.05)));
  for I := 0 to Count do
  begin
    T := Trap.Fire + (Trap.Finish - Trap.Fire) * I / Count;
    // 速度上限とサブフレーム間隔を含めた余白。描画でも同じ当たり判定の形を使う。
    if Plan.Clearance(Trap, T) < 0.10 then Exit(False);
  end;
  Result := True;
end;

procedure FitObstacle(Plan: TTrapPlan; var Trap: TTrapObstacle);
var I: Integer;
begin
  for I := 0 to 100 do
  begin
    if SafeDuring(Plan, Trap) then Exit;
    if Trap.Kind in [tkLaser, tkArrow, tkFlyingBlade, tkDoor] then Trap.Y := Trap.Y + 0.07
    else Trap.X := Trap.X - 0.09;
  end;
  raise EInvalidOpException.Create('罠の回避余白を確保できません。');
end;

procedure ValidateTrapPlan(Plan: TTrapPlan; const Cancel: TFunc<Boolean>);
var I: Integer; Move: TTrapMove; Trap: TTrapObstacle; Previous: TTrapPoint;
begin
  if (Plan = nil) or (Length(Plan.Moves) = 0) then raise EArgumentException.Create('空の罠計画');
  Previous := Plan.Moves[0].Origin;
  for I := 0 to High(Plan.Moves) do
  begin
    if Assigned(Cancel) and Cancel() then Abort;
    Move := Plan.Moves[I];
    if (Move.Finish <= Move.Start) or (Move.Cue <= Move.Start) or (Move.Cue >= Move.Finish) or
      (Hypot(Move.Origin.X - Previous.X, Move.Origin.Y - Previous.Y) > 1E-8) or
      ((I > 0) and (Move.Start <> Plan.Moves[I - 1].Finish)) then
      raise EConvertError.Create('連続軌道が不正です。');
    Previous := Move.Target;
  end;
  for Trap in Plan.Obstacles do
  begin
    if Assigned(Cancel) and Cancel() then Abort;
    if not SafeDuring(Plan, Trap) then raise EConvertError.Create('保存された罠と軌道が接触します。');
  end;
end;

function BuildTrapPlan(Audio: TRhythmAudio; Theme: TTrapStage; const Cancel: TFunc<Boolean>): TTrapPlan;
var
  Anchors: TList<TAnchor>; Motions: TList<TTrapMove>; Platforms: TList<TTrapPlatform>;
  Traps: TList<TTrapObstacle>; Anchor: TAnchor; Hit: TRhythmHit; Move: TTrapMove;
  Floor: TTrapPlatform; Trap: TTrapObstacle; P: TTrapPoint;
  I, J, Index, Section, Phase, Pattern, Phases, Level: Integer;
  Duration, Travel, TargetY, Arc, Progress, Span, MaxTime, Gap, CollapseTime: Double; Kind: TTrapMotion; Landing: Boolean;
  procedure AddPlatform(Left, Right, Y, EndY: Double; FloorKind: TTrapKind; MoveIndex: Integer = -1; CollapseAt: Double = -1);
  begin
    Floor := Default(TTrapPlatform);
    Floor.Left := Left; Floor.Right := Right; Floor.Y := Y; Floor.EndY := EndY;
    Floor.Start := 0; Floor.Finish := Audio.Duration;
    if (CollapseAt >= 0) and (MoveIndex < 0) and (FloorKind in [tkCrumble,tkVanish,tkFalseFloor,tkPit,tkFlip,tkBridge,tkCollapse,tkSink]) then Floor.Finish := CollapseAt;
    Floor.Kind := FloorKind; Floor.Move := MoveIndex;
    Platforms.Add(Floor);
  end;
begin
  if (Audio = nil) or IsNan(Audio.Duration) or IsInfinite(Audio.Duration) or (Audio.Duration <= 0) then
    raise EArgumentException.Create('音源長が不正です。');
  Result := TTrapPlan.Create;
  Anchors := TList<TAnchor>.Create; Motions := TList<TTrapMove>.Create;
  Platforms := TList<TTrapPlatform>.Create; Traps := TList<TTrapObstacle>.Create;
  try
    Result.Duration := Audio.Duration; Result.Theme := Theme;
    Duration := Audio.Duration;MaxTime := Duration - Min(1.2, Duration * 0.10);Gap := Max(0.25, Duration / 9700);
    Anchor := Default(TAnchor); Anchors.Add(Anchor);
    for Hit in Audio.Hits do
    begin
      if Assigned(Cancel) and Cancel() then Abort;
      if IsNan(Hit.Time) or IsInfinite(Hit.Time) or (Hit.Time <= 0.12) or
        (Hit.Time >= MaxTime) or
        (Hit.Time - Anchors.Last.Time < Gap) then Continue;
      while Hit.Time - Anchors.Last.Time > Max(1.7, Gap * 2) do begin
        Anchor.Time := Anchors.Last.Time + Max(1.0, Gap);Anchor.Power := 0.18;Anchor.Synced := False;Anchors.Add(Anchor);
      end;
      Anchor.Time := Hit.Time; Anchor.Power := EnsureRange(Hit.Strength, 0.0, 1.0);
      Anchor.Synced := True; Anchors.Add(Anchor);
      if Anchors.Count >= 10000 then Break;
    end;
    while MaxTime - Anchors.Last.Time > Max(1.7, Gap * 2) do begin
      if Assigned(Cancel) and Cancel() then Abort;
      Anchor.Time := Anchors.Last.Time + Max(1.0, Gap);Anchor.Power := 0.18;Anchor.Synced := False;Anchors.Add(Anchor);
    end;
    if (Anchors.Count >= 3) and (MaxTime - Anchors.Last.Time > Max(0.4, Gap)) then begin
      Anchor.Time := MaxTime;Anchor.Power := 0.25;Anchor.Synced := False;Anchors.Add(Anchor);
    end;
    if Anchors.Count < 3 then
    begin
      Anchors.Clear;
      Anchor := Default(TAnchor); Anchors.Add(Anchor);
      Anchor.Time := Duration * 0.46; Anchors.Add(Anchor);
      Anchor.Time := Duration * 0.92; Anchors.Add(Anchor);
    end;
    Result.GoalTime := Anchors.Last.Time;
    Index := 0; Section := 0; P := TrapPoint(0, 0);
    while Index + 2 < Anchors.Count do
    begin
      Progress := Anchors[Index].Time / Duration;
      Pattern := PatternFor(Section, Progress, Theme);
      if Index + 9 >= Anchors.Count then Pattern := 17;
      Phases := 3;
      if Pattern = 5 then Phases := 4;
      for Phase := 0 to Phases - 1 do
      begin
        if Index + 2 >= Anchors.Count then Break;
        if Assigned(Cancel) and Cancel() then Abort;
        Move := Default(TTrapMove);
        Move.Start := Anchors[Index].Time; Move.Cue := Anchors[Index + 1].Time;
        Move.Finish := Anchors[Index + 2].Time;
        Move.CueSynced := Anchors[Index + 1].Synced;
        Move.LandSynced := Anchors[Index + 2].Synced;
        Move.Origin := P; Move.Section := Section; Move.Pattern := Pattern;
        ChooseMotion(Pattern, Phase, Kind, TargetY, Arc, Landing);
        if Index + 4 >= Anchors.Count then begin Kind := tmJump; TargetY := 0; Arc := 1.2; Landing := True; end;
        Span := Move.Finish - Move.Start;
        Travel := Min(7.5, Span * (3.0 + Progress * 1.4 + Phase * 0.55));
        if Kind = tmStop then Travel := Min(0.5, Travel * 0.12);
        if Kind = tmHang then Travel := 0;
        if Kind = tmClimb then Travel := 0.30;
        if (Kind = tmRide) and (Pattern = 9) then Travel := 0;
        Move.Target := TrapPoint(P.X + Travel, TargetY);
        Move.Kind := Kind; Move.Arc := Arc * Min(1.0, Span / 0.4) * (0.82 + 0.30 * Anchors[Index + 1].Power); Move.Landing := Landing;
        Motions.Add(Move);
        P := Move.Target;
        Inc(Index, 2);
      end;
      Inc(Section);
    end;
    if Index < Anchors.Count - 1 then
    begin
      Move := Default(TTrapMove);
      Move.Start := Anchors[Index].Time; Move.Finish := Anchors.Last.Time;
      Move.Cue := (Move.Start + Move.Finish) * 0.5;
      Move.Origin := P; Move.Target := TrapPoint(P.X + (Move.Finish - Move.Start) * 3, 0);
      Move.Arc := 0.8; Move.Kind := tmJump; Move.Landing := True;
      Move.LandSynced := Anchors.Last.Synced; Move.Section := Section;
      Motions.Add(Move); P := Move.Target;
    end;
    Result.Moves := Motions.ToArray; Result.GoalX := P.X;
    AddPlatform(-8, 0.5, 0, 0, tkMoving);
    for I := 0 to High(Result.Moves) do
    begin
      Move := Result.Moves[I];
      Pattern := Move.Pattern;
      Phase := 0;
      if I > 0 then begin J := I - 1; while (J >= 0) and (Result.Moves[J].Section = Move.Section) do begin Inc(Phase); Dec(J); end; end;
      Kind := Move.Kind;CollapseTime := Duration;
      if I < High(Result.Moves) then CollapseTime := Result.Moves[I+1].Cue;
      if (Pattern=9) and (Kind=tmRun) then CollapseTime := Move.Finish;
      if Kind in [tmRun, tmSlide, tmStop, tmSkate] then
        AddPlatform(Move.Origin.X - 0.03, Max(Move.Origin.X + 0.35, Move.Target.X), Move.Origin.Y,
          Move.Target.Y, PrimaryKind(Pattern, Phase), -1, CollapseTime)
      else if Kind = tmRide then AddPlatform(-0.65, 0.65, 0, 0, PrimaryKind(Pattern, Phase), I);
      if Move.Landing then AddPlatform(Move.Target.X - 0.48, Move.Target.X + 0.46,
        Move.Target.Y, Move.Target.Y, PrimaryKind(Pattern, Phase), -1, CollapseTime);
      if Kind = tmHang then AddPlatform(Move.Target.X + 0.24, Move.Target.X + 1.8,
        Move.Target.Y + 1.12, Move.Target.Y + 1.12, tkMoving);
      Trap := Default(TTrapObstacle);
      Trap.Kind := PrimaryKind(Pattern, Phase); Trap.Move := I;
      Trap.Cue := Move.Cue; Trap.Synced := Move.CueSynced;
      Span := Move.Finish - Move.Start;
      Trap.Fire := Max(Move.Start, Trap.Cue - Min(0.6, Span * 0.31));
      Trap.Reveal := Max(Move.Start, Trap.Fire - Min(0.20, Span * 0.12));
      Trap.Finish := Min(Duration, Trap.Cue + Min(0.27, Span * 0.22));
      P := Move.Position(Trap.Cue);
      Level := Min(3, System.Math.Floor(4 * Move.Start / Duration));
      Trap.Power := Anchors[Min(Anchors.Count - 1, I * 2 + 1)].Power;
      Trap.X := P.X; Trap.Y := Min(Move.Origin.Y, Move.Target.Y);
      Trap.W := 0.85 + Level * 0.13; Trap.H := 0.55 + Level * 0.11;
      Trap.W := Trap.W * (0.82 + Trap.Power * 0.36);Trap.H := Trap.H * (0.82 + Trap.Power * 0.36);
      Trap.Travel := 3.5 + Level * 0.8;
      if (Theme=tsVolcano) and (Trap.Kind=tkFlame) and (I mod 2=0) then begin
        Trap.Kind:=tkLava;Trap.Y:=Trap.Y-0.85;Trap.W:=5.0+Level;Trap.H:=0.75+Level*0.35;
      end;
      case Trap.Kind of
        tkCeiling, tkDoor:
          begin Trap.W := 2.1; Trap.H := 1.3 + Level * 0.3;
            Trap.Y := P.Y + Move.HeightAt(Trap.Cue) + 0.15; end;
        tkWall, tkWallBlock:
          begin Trap.W := 0.55; Trap.H := 3.8; Trap.X := P.X - 0.65; Trap.Y := P.Y - 0.5; end;
        tkBlade, tkFlyingBlade, tkArrow, tkHunter:
          begin Trap.Y := P.Y + Move.HeightAt(Trap.Cue) + 0.22;
            Trap.W := 0.65; Trap.H := 0.35; if Trap.Kind = tkArrow then Trap.H := 0.10;
            if Trap.Kind = tkBlade then Trap.Travel := 0.12; end;
        tkLaser:
          begin Trap.Y := P.Y + Move.HeightAt(Trap.Cue) + 0.13; Trap.H := 0.08; Trap.W := 5.5; end;
        tkBoulder:
          begin Trap.W := 2.0 + Level * 0.40; Trap.H := Trap.W;
            Trap.X := P.X - Trap.W * 0.5 - 0.42; Trap.Y := P.Y; end;
        tkRock, tkRain, tkBackground:
          begin Trap.X := P.X - 0.75; Trap.W := 0.75 + Level * 0.3;
            Trap.H := Trap.W; if Trap.Kind = tkBackground then begin Trap.W := 2.7; Trap.H := 4.0; end; end;
      end;
      FitObstacle(Result, Trap); Traps.Add(Trap);
      if (Level >= 1) and (I mod 3 = 2) then
      begin
        Trap.Kind := tkRock;
        if Level >= 2 then Trap.Kind := tkCeiling;
        Trap.Cue := Move.Finish; Trap.Synced := Move.LandSynced;
        Trap.Fire := Max(Move.Start, Trap.Cue - Min(0.48, Span * 0.30));
        Trap.Reveal := Trap.Fire; Trap.Finish := Min(Duration, Trap.Cue + 0.18);
        P := Move.Target; Trap.X := P.X - 0.75; Trap.Y := P.Y;
        Trap.W := 1.2 + Level * 0.25; Trap.H := 1.1 + Level * 0.3; Trap.Travel := 5;
        FitObstacle(Result, Trap); Traps.Add(Trap);
      end;
      if (Level = 3) and (I mod 4 = 0) then
      begin
        Trap.Kind := tkCollapse;if I mod 8 = 0 then Trap.Kind := tkTunnelCollapse; Trap.Cue := Move.Finish; Trap.Synced := Move.LandSynced;
        Trap.Reveal := Move.Start; Trap.Fire := Move.Cue; Trap.Finish := Min(Duration, Move.Finish + 0.4);
        Trap.X := Move.Origin.X; Trap.Y := Move.Origin.Y; Trap.W := Max(2.0, Move.Target.X - Move.Origin.X);
        Trap.H := 0.45; Traps.Add(Trap);
      end;
    end;
    AddPlatform(Result.GoalX - 0.25, Result.GoalX + 8, 0, 0, tkMoving);
    Result.Platforms := Platforms.ToArray;
    Traps.Sort(TComparer<TTrapObstacle>.Construct(
      function(const A, B: TTrapObstacle): Integer
      begin if A.Cue < B.Cue then Result := -1 else if A.Cue > B.Cue then Result := 1 else Result := A.Move - B.Move; end));
    Result.Obstacles := Traps.ToArray;
    ValidateTrapPlan(Result, Cancel);
  except
    Result.Free;
    Anchors.Free; Motions.Free; Platforms.Free; Traps.Free;
    raise;
  end;
  Anchors.Free; Motions.Free; Platforms.Free; Traps.Free;
end;

end.
