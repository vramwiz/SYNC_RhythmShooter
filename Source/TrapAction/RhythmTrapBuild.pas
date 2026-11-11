unit RhythmTrapBuild;
// 床上の針に対する停止・後退・再前進を音時刻へ接続し、全方向の再接近も検査する。
interface
uses System.SysUtils, RhythmAudio, RhythmStyles, RhythmTrapPlan;
function BuildTrapPlan(Audio: TRhythmAudio; Theme: TTrapStage; const Cancel: TFunc<Boolean>): TTrapPlan;
procedure ValidateTrapPlan(Plan: TTrapPlan; const Cancel: TFunc<Boolean>);
implementation
uses System.Math, System.Generics.Collections;
type
  TAnchor = record
    Time, Power: Double;
    Synced: Boolean;
  end;

function SafeDuring(Plan: TTrapPlan; const Trap: TTrapObstacle): Boolean;
var I, J, Count: Integer; First, Last, Speed, Span, Time, Left, Right: Double; M: TTrapMove;
begin
  if TrapHarmless(Trap.Kind) then Exit(True);
  Left := Trap.X - Trap.W * 0.5 - TrapHalfWidth - 0.11;
  Right := Trap.X + Trap.W * 0.5 + TrapHalfWidth + 0.11;
  for J := 0 to High(Plan.Moves) do
  begin
    M := Plan.Moves[J];
    // 後退や再接近も調べる。進行方向に依存せず、身体が近づく全区間を検査する。
    if (Max(M.Target.X, M.Origin.X) < Left) or (Min(M.Origin.X, M.Target.X) > Right) then Continue;
    First := Max(M.Start, Trap.Fire); Last := Min(M.Finish, Trap.Finish);
    if Last < First then Continue;
    Span := M.Finish - M.Start;
    Speed := (Abs(M.Target.X - M.Origin.X) + Abs(M.Target.Y - M.Origin.Y) + 4 * M.Arc) / Span;
    if Trap.Kind = tkHiddenSpikes then
      Speed := Speed + 1.5 * Trap.H / (Trap.Cue - Trap.Fire) +
        1.5 * Trap.H / (Trap.Finish - Trap.RetractionStart);
    if Trap.Kind = tkCeiling then Speed := Speed + 2 * Trap.Travel / (Trap.Cue - Trap.Fire);
    // 相対速度の上限でサンプル間の移動を0.05以内に抑え、0.10の余白を要求する。
    Count := Max(2, Ceil((Last - First) * Max(120.0, Speed / 0.05)));
    for I := 0 to Count do
    begin
      Time := First + (Last - First) * I / Count;
      if Plan.Clearance(Trap, Time) < 0.10 then Exit(False);
    end;
  end;
  Result := True;
end;

// 水平移動と放物線の極値から、サンプル間を含む床・天井への侵入を検査する。
function SafeTerrainMove(Plan: TTrapPlan; const M: TTrapMove): Boolean;
var Tile:TTrapPlatform; A,B,X0,X1,DX,Span,V,LowY,HighY:Double;
  function Y(U:Double):Double;
  begin Result:=M.Origin.Y+(M.Target.Y-M.Origin.Y)*U+4*M.Arc*U*(1-U);end;
  function Window(const T:TTrapPlatform):Boolean;
  var C:Double;
  begin
    A:=0;B:=1;
    if Abs(DX)<1E-10 then begin
      if (M.Origin.X+TrapHalfWidth<=T.Left) or (M.Origin.X-TrapHalfWidth>=T.Right) then Exit(False);
    end else begin
      X0:=(T.Left-TrapHalfWidth-M.Origin.X)/DX;X1:=(T.Right+TrapHalfWidth-M.Origin.X)/DX;
      if X0>X1 then begin C:=X0;X0:=X1;X1:=C;end;
      A:=Max(0.0,X0);B:=Min(1.0,X1);
    end;
    A:=Max(A,(T.Start-M.Start)/Span);
    if T.Finish<Plan.Duration then B:=Min(B,(T.Finish-M.Start)/Span);
    Result:=B>A+1E-10;
  end;
begin
  Result:=False;DX:=M.Target.X-M.Origin.X;Span:=M.Finish-M.Start;
  for Tile in Plan.Platforms do if Window(Tile) then begin
    LowY:=Min(Y(A),Y(B))+0.035;
    if LowY<Tile.Y-1E-8 then Exit;
  end;
  for Tile in Plan.Ceilings do if Window(Tile) then begin
    HighY:=Max(Y(A),Y(B));
    if M.Arc>0 then begin
      V:=EnsureRange(0.5+(M.Target.Y-M.Origin.Y)/(8*M.Arc),A,B);
      HighY:=Max(HighY,Y(V));
    end;
    if HighY+TrapStandingHeight>Tile.Y-0.12 then Exit;
  end;
  Result:=True;
end;

procedure ValidateTrapPlan(Plan: TTrapPlan; const Cancel: TFunc<Boolean>);
var I,J:Integer;M:TTrapMove;Trap:TTrapObstacle;Tile:TTrapPlatform;
  Previous,P:TTrapPoint;Time,Edge:Double;
begin
  if (Plan=nil) or (Length(Plan.Moves)=0) then raise EArgumentException.Create('空の罠計画');
  Edge:=-1E8;
  for Tile in Plan.Platforms do begin
    if (Tile.Move<>-1) or (Tile.Left<Edge) or (Tile.Right<=Tile.Left) or
      (Abs(Tile.Y)>2) or (Tile.EndY<>Tile.Y) or (Tile.Start<>0) or
      (Tile.Finish<=0) or (Tile.Finish>Plan.Duration) then raise EConvertError.Create('段差床の配置が不正です。');
    Edge:=Tile.Left;
  end;
  Edge:=-1E8;
  for Tile in Plan.Ceilings do begin
    if (Tile.Move<>-1) or (Tile.Left<Edge) or (Tile.Right<=Tile.Left) or
      (Abs(Tile.Y)>7) or (Tile.EndY<>Tile.Y) or (Tile.Start<>0) or
      (Tile.Finish<>Plan.Duration) then raise EConvertError.Create('段差天井の配置が不正です。');
    Edge:=Tile.Left;
  end;
  Previous:=Plan.Moves[0].Origin;
  for I:=0 to High(Plan.Moves) do begin
    if Assigned(Cancel) and Cancel() then Abort;M:=Plan.Moves[I];
    if (M.Finish<=M.Start) or (M.Cue<M.Start) or (M.Cue>M.Finish) or
      (Hypot(M.Origin.X-Previous.X,M.Origin.Y-Previous.Y)>1E-8) or
      ((I>0) and (M.Start<>Plan.Moves[I-1].Finish)) or
      not (M.Kind in [tmRun,tmJump,tmStop]) or not M.Landing or
      (Abs(M.Origin.Y)>2) or (Abs(M.Target.Y)>2) or
      (Abs(M.Target.X-M.Origin.X)>20) or (M.Arc<0) or (M.Arc>2.1) or
      ((M.Kind in [tmRun,tmStop]) and ((M.Arc<>0) or (M.Origin.Y<>M.Target.Y))) or
      ((M.Kind=tmStop) and (M.Target.X<>M.Origin.X)) or
      ((M.Kind<>tmStop) and (M.Target.X=M.Origin.X)) or
      ((M.Kind=tmJump) and (M.Arc<0.45)) then raise EConvertError.Create('歩行・ジャンプの連続軌道が不正です。');
    if ((M.Kind=tmStop) and (M.Cue<>M.Start)) or
      ((M.Kind<>tmStop) and (M.Cue<>M.Finish)) then raise EConvertError.Create('接地・停止の結果時刻が不正です。');
    if (M.Kind in [tmRun,tmStop]) and
      (not Plan.FloorSupports(Min(M.Origin.X,M.Target.X)-TrapHalfWidth,
        Max(M.Origin.X,M.Target.X)+TrapHalfWidth,M.Origin.Y,M.Start) or
       not Plan.FloorSupports(Min(M.Origin.X,M.Target.X)-TrapHalfWidth,
        Max(M.Origin.X,M.Target.X)+TrapHalfWidth,M.Origin.Y,M.Finish)) then
      raise EConvertError.Create('歩行区間の途中に床の欠落があります。');
    for J:=0 to 8 do begin
      Time:=M.Start+(M.Finish-M.Start)*J/8;P:=M.Position(Time);
      if ((M.Kind in [tmRun,tmStop]) or (J=0) or (J=8)) and
        not Plan.FloorSupports(P.X-TrapHalfWidth,P.X+TrapHalfWidth,P.Y,Time) then
        raise EConvertError.CreateFmt('動作%dの歩行・踏切・着地を支える床がありません。',[I]);
    end;
    if not SafeTerrainMove(Plan,M) then
      raise EConvertError.CreateFmt('動作%dが段差床または天井へ接触します。',[I]);
    Previous:=M.Target;
  end;
  for Trap in Plan.Obstacles do begin
    if Assigned(Cancel) and Cancel() then Abort;
    if not (Trap.Kind in [tkSpikes,tkHiddenSpikes,tkCeiling,tkPit,tkCrumble,tkVanish]) or
      (Abs(Trap.Y)>2) or (Trap.H>TrapStandingHeight) or (Trap.Travel<0) or (Trap.Travel>6) then
      raise EConvertError.Create('針の寸法が不正です。');
    if not TrapHarmless(Trap.Kind) then begin
      if (Trap.W>0.80) or not Plan.FloorSupports(Trap.X-Trap.W*0.5,Trap.X+Trap.W*0.5,Trap.Y,Trap.Finish) then
        raise EConvertError.Create('針を支える床がありません。');
      if (Trap.Kind=tkCeiling) and not Plan.CeilingSupports(Trap.X-Trap.W*0.5,
        Trap.X+Trap.W*0.5,Trap.Y+Trap.Travel+Trap.H) then raise EConvertError.Create('落下針を支える天井がありません。');
      if not SafeDuring(Plan,Trap) then raise EConvertError.CreateFmt('動作%dの針と軌道が接触します。',[Trap.Move]);
    end;
  end;
end;

function BuildTrapPlan(Audio:TRhythmAudio;Theme:TTrapStage;const Cancel:TFunc<Boolean>):TTrapPlan;
var
  Anchors:TList<TAnchor>;Motions:TList<TTrapMove>;Floors,Roofs:TList<TTrapPlatform>;
  Traps:TList<TTrapObstacle>;A:TAnchor;Hit:TRhythmHit;M:TTrapMove;
  Tile:TTrapPlatform;Trap:TTrapObstacle;P:TTrapPoint;V:TTrapAvoidance;
  I,J,Section,StopIndex,BackIndex,EndIndex,WaitIndex,ClearMove,Role:Integer;
  Cursor,Duration,Goal,StopTime,BackTime,EndTime,Hold,StopX,BackDistance,
    ApproachX,Frontier,Travel,SpikeEnd,DY,Arc,BaseY,RoofRight,RoofBase:Double;
  function BeatAfter(Time:Double):Integer;
  var L,R,Mid:Integer;
  begin
    L:=0;R:=Anchors.Count;
    while L<R do begin Mid:=(L+R) div 2;
      if Anchors[Mid].Time<Time-1E-9 then L:=Mid+1 else R:=Mid;end;
    Result:=L;
  end;
  procedure Motion(UntilTime,TargetX:Double;Kind:TTrapMotion;Lift:Double;
    StartSynced,EndSynced:Boolean;Pattern:Integer=18;DeltaY:Double=0);
  begin
    if UntilTime<=Cursor+1E-9 then Exit;
    M:=Default(TTrapMove);M.Start:=Cursor;M.Finish:=UntilTime;
    M.Cue:=UntilTime;M.CueSynced:=EndSynced;
    if Kind=tmStop then begin M.Cue:=Cursor;M.CueSynced:=StartSynced;end;
    M.Origin:=P;M.Target:=TrapPoint(TargetX,P.Y+DeltaY);M.Kind:=Kind;M.Arc:=Lift;
    M.Landing:=True;M.LandSynced:=EndSynced;M.Section:=Section;M.Pattern:=Pattern;M.Avoidance:=V;
    Motions.Add(M);P:=M.Target;Cursor:=UntilTime;
  end;
  procedure WalkUntil(UntilTime:Double;Pattern:Integer=18);
  var N:Integer;Next:Double;Synced:Boolean;
  begin
    N:=BeatAfter(Cursor+1E-7);
    while Cursor<UntilTime-1E-9 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      Next:=Min(UntilTime,Cursor+1.0);Synced:=False;
      if (N<Anchors.Count) and (Anchors[N].Time<=Next+1E-9) then begin
        Next:=Anchors[N].Time;Synced:=True;Inc(N);end;
      Motion(Next,P.X+(Next-Cursor)*TrapWalkSpeed,tmRun,0,False,Synced,Pattern);
    end;
  end;
  procedure Needle(X,Height,Cue,UntilTime:Double;MoveIndex:Integer);
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkHiddenSpikes;Trap.Move:=MoveIndex;
    Trap.X:=X;Trap.Y:=P.Y;Trap.W:=0.62;Trap.H:=Height;Trap.Cue:=Cue;Trap.Synced:=True;
    Trap.Fire:=Max(0.0,Cue-0.04);Trap.Reveal:=Max(0.0,Trap.Fire-0.07);
    Trap.Finish:=UntilTime;Traps.Add(Trap);
  end;
  procedure Falling(X,Y,Cue:Double;MoveIndex:Integer);
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkCeiling;Trap.Move:=MoveIndex;
    Trap.X:=X;Trap.Y:=Y;Trap.W:=0.46;Trap.H:=0.80;Trap.Cue:=Cue;Trap.Synced:=True;
    // 天井を作った後で、吊り下げ位置と重力から正確な発射時刻を逆算する。
    Trap.Fire:=Max(0.0,Cue-0.3);Trap.Reveal:=Max(0.0,Trap.Fire-0.07);
    Trap.Finish:=Duration;Traps.Add(Trap);
  end;
  procedure StaticSpike(U,Height:Double);
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkSpikes;Trap.Move:=Motions.Count-1;
    Trap.Cue:=M.Start+(M.Finish-M.Start)*U;Trap.X:=M.Position(Trap.Cue).X;
    Trap.Y:=M.Origin.Y;Trap.W:=0.42;Trap.H:=Height;Trap.Finish:=Duration;
    Traps.Add(Trap);
  end;
  procedure FloorMarker(Kind:TTrapKind);
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=Kind;Trap.Move:=Motions.Count-1;
    Trap.Cue:=M.Finish;Trap.Synced:=M.LandSynced;Trap.Finish:=Duration;
    Trap.Reveal:=M.Start;Trap.Fire:=M.Start;Trap.Y:=M.Origin.Y;
    Trap.X:=(M.Origin.X+M.Target.X)*0.5;Trap.W:=(M.Target.X-M.Origin.X)*0.64;
    Trap.H:=0.1;Traps.Add(Trap);
  end;
  procedure AddFloor(Left,Right,Y:Double;Kind:TTrapKind;UntilTime:Double);
  var F:TTrapPlatform;
  begin
    F:=Default(TTrapPlatform);F.Left:=Left;F.Right:=Right;F.Y:=Y;F.EndY:=Y;
    F.Kind:=Kind;F.Move:=-1;F.Finish:=UntilTime;Floors.Add(F);
  end;
  procedure AddRoof(Left,Right,Y:Double);
  var R:TTrapPlatform;Move:TTrapMove;Q:TTrapObstacle;Height:Double;
  begin
    Height:=Y+2.05+(Roofs.Count mod 3)*0.25;
    for Move in Result.Moves do
      if (Max(Move.Origin.X,Move.Target.X)+TrapHalfWidth>Left) and
        (Min(Move.Origin.X,Move.Target.X)-TrapHalfWidth<Right) then
        Height:=Max(Height,Max(Move.Origin.Y,Move.Target.Y)+Move.Arc+TrapStandingHeight+0.22);
    for Q in Traps do if (Q.Kind=tkCeiling) and (Q.X+Q.W*0.5>Left) and (Q.X-Q.W*0.5<Right) then
      Height:=Max(Height,Q.Y+Q.H+2.6);
    if Right>Result.GoalX+0.1 then Height:=Max(Height,P.Y+4.4);
    R:=Default(TTrapPlatform);R.Left:=Left;R.Right:=Right;R.Y:=Height;R.EndY:=Height;
    R.Move:=-1;R.Kind:=tkCeiling;R.Finish:=Duration;Roofs.Add(R);
  end;
begin
  if (Audio=nil) or IsNan(Audio.Duration) or IsInfinite(Audio.Duration) or (Audio.Duration<=0) then
    raise EArgumentException.Create('音源長が不正です。');
  Result:=TTrapPlan.Create;Anchors:=TList<TAnchor>.Create;Motions:=TList<TTrapMove>.Create;
  Floors:=TList<TTrapPlatform>.Create;Roofs:=TList<TTrapPlatform>.Create;Traps:=TList<TTrapObstacle>.Create;
  try
    Duration:=Audio.Duration;Result.Duration:=Duration;Result.Theme:=Theme;
    Goal:=Duration-Min(0.35,Duration*0.06);
    for Hit in Audio.Hits do begin
      if Assigned(Cancel) and Cancel() then Abort;
      if IsNan(Hit.Time) or IsInfinite(Hit.Time) or (Hit.Time<0.12) or (Hit.Time>Goal) then Continue;
      if (Anchors.Count>0) and (Hit.Time-Anchors.Last.Time<0.12) then Continue;
      A.Time:=Hit.Time;A.Power:=Hit.Strength;A.Synced:=True;Anchors.Add(A);
      if Anchors.Count>=10000 then Break;
    end;
    if Anchors.Count>0 then Goal:=Anchors.Last.Time;
    Cursor:=0;P:=TrapPoint(0,0);Section:=0;V:=taTravel;
    while Cursor<Goal-0.6 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      V:=TTrapAvoidance((Section+Ord(Theme)*2) mod Ord(taTravel));
      StopIndex:=BeatAfter(Cursor+0.48);if StopIndex>=Anchors.Count then Break;
      StopTime:=Anchors[StopIndex].Time;
      // 単発・連続ジャンプと段差越え。すべて着地は次の実音へ接続する。
      if V in [taDropStopJump,taLowHop,taLongJump,taStepUp,taStepDown,taGapUp,
        taGapDown,taCrumbleUp,taVanishDown,taTripleHop] then begin
        EndIndex:=BeatAfter(StopTime+0.38);
        if (EndIndex>=Anchors.Count) or (Anchors[EndIndex].Time-StopTime>0.64) then begin
          WalkUntil(StopTime);Inc(Section);Continue;end;
        WalkUntil(StopTime);StopX:=P.X;BaseY:=P.Y;EndTime:=Anchors[EndIndex].Time;
        case V of
          taDropStopJump:begin
            Motion(StopTime+0.06,P.X,tmStop,0,True,False,0);
            Motion(EndTime,StopX+3.8,tmJump,1.9,False,True,4);
            Falling(StopX+1.2,BaseY,StopTime,Motions.Count-1);
          end;
          taLowHop:begin Motion(EndTime,P.X+(EndTime-Cursor)*TrapWalkSpeed,tmJump,0.70,False,True,4);StaticSpike(0.5,0.26);end;
          taLongJump:begin Motion(EndTime,P.X+5.8,tmJump,1.45,False,True,4);StaticSpike(0.40,0.36);StaticSpike(0.65,0.36);end;
          taTripleHop:begin
            for J:=0 to 2 do begin
              I:=BeatAfter(Cursor+0.32);
              if (I>=Anchors.Count) or (Anchors[I].Time-Cursor>0.56) then Break;
              EndTime:=Anchors[I].Time;
              Motion(EndTime,P.X+(EndTime-Cursor)*TrapWalkSpeed,tmJump,0.70,False,True,4);
              StaticSpike(0.5,0.26);
            end;
          end;
          else begin
            DY:=0;Arc:=0.85;Role:=20;
            case V of
              taStepUp:DY:=0.45;taStepDown:DY:=-0.45;
              taGapUp:begin DY:=0.55;Arc:=1.10;Role:=21;end;
              taGapDown:begin DY:=-0.55;Arc:=1.10;Role:=21;end;
              taCrumbleUp:begin DY:=0.35;Arc:=1.0;Role:=22;end;
              taVanishDown:begin DY:=-0.35;Arc:=0.85;Role:=23;end;
            end;
            DY:=EnsureRange(P.Y+DY,-0.55,0.70)-P.Y;
            Motion(EndTime,P.X+(EndTime-Cursor)*TrapWalkSpeed,tmJump,Arc,False,True,Role,DY);
            case Role of 21:FloorMarker(tkPit);22:FloorMarker(tkCrumble);23:FloorMarker(tkVanish);end;
          end;
        end;
        Inc(Section);Continue;
      end;
      BackIndex:=BeatAfter(StopTime+0.25);
      if (BackIndex>=Anchors.Count) or (Anchors[BackIndex].Time-StopTime>0.55) then begin
        WalkUntil(StopTime);Inc(Section);Continue;end;
      BackTime:=Anchors[BackIndex].Time;EndIndex:=BeatAfter(BackTime+0.38);
      WaitIndex:=BeatAfter(BackTime+0.15);
      if (V=taWaitPass) and (WaitIndex<Anchors.Count) and
        (Anchors[WaitIndex].Time-BackTime<=0.55) then EndIndex:=WaitIndex
      else if V=taWaitPass then V:=taRetreatJump;
      if (EndIndex>=Anchors.Count) or ((V<>taWaitPass) and
        (Anchors[EndIndex].Time-BackTime>0.68)) then begin
        WalkUntil(StopTime);Inc(Section);Continue;end;
      EndTime:=Anchors[EndIndex].Time;ApproachX:=P.X;
      WalkUntil(StopTime);StopX:=P.X;BaseY:=P.Y;
      if V=taRunUnderDrops then begin
        WalkUntil(EndTime,24);ClearMove:=Motions.Count-1;
        Falling(StopX-1.45,BaseY,StopTime,ClearMove);
        Falling(StopX+(BackTime-StopTime)*TrapWalkSpeed-1.45,BaseY,BackTime,ClearMove);
        Falling(StopX+(EndTime-StopTime)*TrapWalkSpeed-1.45,BaseY,EndTime,ClearMove);
        Inc(Section);Continue;
      end;
      if V=taBetweenDrops then begin
        Motion(BackTime,P.X,tmStop,0,True,True,3);
        Motion(BackTime+0.04,P.X,tmStop,0,True,False,3);
        Motion(EndTime,StopX+4.2,tmJump,1.9,False,True,4);ClearMove:=Motions.Count-1;
        Falling(StopX-1.50,BaseY,StopTime,ClearMove);Falling(StopX+1.35,BaseY,BackTime,ClearMove);
        Inc(Section);Continue;
      end;
      Hold:=Min(0.08,(BackTime-StopTime)*0.25);
      Motion(StopTime+Hold,P.X,tmStop,0,True,False,0);
      BackDistance:=Min(Max(1.30,(BackTime-Cursor)*TrapWalkSpeed),StopX-ApproachX-0.65);
      if (V=taBackHop) and (BackTime-Cursor>=0.30) then
        Motion(BackTime,StopX-BackDistance,tmJump,0.80,False,True,2)
      else Motion(BackTime,StopX-BackDistance,tmRun,0,False,True,2);
      if V=taWaitPass then begin
        Motion(EndTime,P.X,tmStop,0,True,True,3);SpikeEnd:=EndTime;ClearMove:=Motions.Count-1;
      end else begin
        Motion(BackTime+0.04,P.X,tmStop,0,True,False,3);
        Arc:=1.90;if V=taBackHop then Arc:=1.70;
        Motion(EndTime,StopX+3.0,tmJump,Arc,False,True,4);
        SpikeEnd:=Min(Duration,EndTime+0.08);ClearMove:=Motions.Count-1;
      end;
      Needle(StopX+1.0,0.58,StopTime,SpikeEnd,ClearMove);
      if V in [taBaitDrop,taBackHop] then Falling(StopX,BaseY,BackTime,ClearMove)
      else Needle(StopX,0.50,BackTime,SpikeEnd,ClearMove);
      Inc(Section);
    end;
    V:=taTravel;WalkUntil(Goal);
    Result.Moves:=Motions.ToArray;Result.GoalTime:=Cursor;Result.GoalX:=P.X;
    Frontier:=0;AddFloor(-8,0,0,tkMoving,Duration);
    for I:=0 to High(Result.Moves) do begin
      M:=Result.Moves[I];if M.Target.X<=Frontier then Continue;
      Travel:=M.Target.X-M.Origin.X;
      if M.Pattern in [21,22,23] then begin
        SpikeEnd:=Duration;if M.Pattern in [22,23] then SpikeEnd:=M.Finish;
        if M.Pattern=22 then Trap.Kind:=tkCrumble else if M.Pattern=23 then Trap.Kind:=tkVanish else Trap.Kind:=tkPit;
        AddFloor(Frontier,M.Origin.X+Travel*0.18,M.Origin.Y,Trap.Kind,SpikeEnd);
        AddFloor(M.Origin.X+Travel*0.82,M.Target.X,M.Target.Y,tkMoving,Duration);
      end else if M.Origin.Y<>M.Target.Y then begin
        AddFloor(Frontier,M.Origin.X+Travel*0.55,M.Origin.Y,tkMoving,Duration);
        AddFloor(M.Origin.X+Travel*0.55,M.Target.X,M.Target.Y,tkMoving,Duration);
      end else AddFloor(Frontier,M.Target.X,M.Target.Y,tkMoving,Duration);
      Frontier:=M.Target.X;
    end;
    AddFloor(Frontier,Frontier+8,P.Y,tkMoving,Duration);
    Result.Platforms:=Floors.ToArray;RoofRight:=Result.Platforms[0].Left;RoofBase:=0;
    for Tile in Result.Platforms do begin
      if Tile.Left>RoofRight then AddRoof(RoofRight,Tile.Left,Max(RoofBase,Tile.Y));
      AddRoof(Tile.Left,Tile.Right,Tile.Y);RoofRight:=Tile.Right;RoofBase:=Tile.Y;
    end;
    Result.Ceilings:=Roofs.ToArray;
    for I:=0 to Traps.Count-1 do begin
      Trap:=Traps[I];if Trap.Kind<>tkCeiling then Continue;
      for Tile in Result.Ceilings do if (Trap.X>=Tile.Left) and (Trap.X<=Tile.Right) then begin
        Trap.Travel:=Tile.Y-Trap.Y-Trap.H;Break;end;
      Trap.Fire:=Trap.Cue-Sqrt(2*Trap.Travel/48);Trap.Reveal:=Max(0.0,Trap.Fire-0.07);
      if Trap.Fire<0 then raise EInvalidOpException.Create('天井の落下準備時間が足りません。');
      Traps[I]:=Trap;
    end;
    Result.Obstacles:=Traps.ToArray;ValidateTrapPlan(Result,Cancel);
  except
    Result.Free;Anchors.Free;Motions.Free;Floors.Free;Roofs.Free;Traps.Free;raise;
  end;
  Anchors.Free;Motions.Free;Floors.Free;Roofs.Free;Traps.Free;
end;
end.
