unit RhythmTrapBuild;
// 57種類の仕掛けを進行度と最近の動作から選び、元音への接地と全方向の安全性を検証する。
// 全曲の選択・地形統合を担当し、個々の連動する罠の組立はRhythmTrapGimmicksへ委ねる。
interface
uses System.SysUtils, RhythmAudio, RhythmStyles, RhythmTrapPlan;
// 準備時専用。Audio/Cancelは借用、返した計画は呼出側がFreeする。中止はEAbortで伝える。
function BuildTrapPlan(Audio: TRhythmAudio; Theme: TTrapStage; const Cancel: TFunc<Boolean>): TTrapPlan;
// 借用したPlanを変更せず、保存契約・床支持・罠との距離を検査する。不正なら例外を返す。
procedure ValidateTrapPlan(Plan: TTrapPlan; const Cancel: TFunc<Boolean>);
implementation
uses System.Math, System.Generics.Collections,System.Generics.Defaults,RhythmTrapGimmicks;
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
  if Trap.Kind=tkSideSpear then begin
    Left:=Min(Trap.X,Trap.X+Trap.Power*Trap.W)-TrapHalfWidth-0.11;
    Right:=Max(Trap.X,Trap.X+Trap.Power*Trap.W)+TrapHalfWidth+0.11;
  end;
  if Trap.Kind=tkBlade then begin Left:=Left-Trap.Travel;Right:=Right+Trap.Travel;end;
  if Trap.Kind=tkWall then begin Left:=Left-Trap.Travel;Right:=Right+Trap.Travel;end;
  for J := 0 to High(Plan.Moves) do
  begin
    M := Plan.Moves[J];
    // 後退や再接近も調べる。進行方向に依存せず、身体が近づく全区間を検査する。
    if (Max(M.Target.X, M.Origin.X) < Left) or (Min(M.Origin.X, M.Target.X) > Right) then Continue;
    First := Max(M.Start, Trap.Fire); Last := Min(M.Finish, Trap.Finish);
    if Trap.Kind in [tkWall,tkBlade,tkPress,tkClosingDoor,tkCeilingNeedles,tkSpearMount] then begin First:=M.Start;Last:=M.Finish;end;
    if Last < First then Continue;
    Span := M.Finish - M.Start;
    Speed := (Abs(M.Target.X - M.Origin.X) + Abs(M.Target.Y - M.Origin.Y) + 4 * M.Arc) / Span;
    if M.Kind=tmVault then Speed:=Speed*2;
    if Trap.Kind = tkHiddenSpikes then
      Speed := Speed + 1.5 * (Trap.H+TrapSpikeTipDrop-TrapSpikeLowering) / (Trap.Cue - Trap.Fire) +
        1.5 * (Trap.H+TrapSpikeTipDrop-TrapSpikeLowering) / (Trap.Finish - Trap.RetractionStart);
    if Trap.Kind in [tkCeiling,tkRock] then Speed := Speed + 2 * Trap.Travel / (Trap.Cue - Trap.Fire);
    if Trap.Kind=tkBlade then Speed:=Speed+Trap.Travel*2*Pi/Trap.Power;
    if Trap.Kind=tkWall then Speed:=Speed+Trap.Travel/Min(Trap.Cue-Trap.Fire,
      Trap.Finish-Trap.Cue-Min(0.12,(Trap.Finish-Trap.Cue)*0.25));
    case Trap.Kind of
      tkSideSpear:Speed:=Speed+1.5*Trap.W/(Trap.Cue-Trap.Fire)+1.5*Trap.W/(Trap.Finish-Trap.RetractionStart);
      tkPress:Speed:=Speed+2*Trap.Travel/(Trap.Cue-Trap.Fire)+1.5*Trap.Travel/(Trap.Finish-Trap.RetractionStart);
      tkClosingDoor:Speed:=Speed+1.5*Trap.Travel/(Trap.Cue-Trap.Fire);
      tkFireJet:Speed:=Speed+1.5*Trap.H/(Trap.Cue-Trap.Fire)+1.5*Trap.H/(Trap.Finish-Trap.RetractionStart);
    end;
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
var Tile:TTrapPlatform;I,N:Integer;Span,Speed,TileSpeed,Time,Left,Right:Double;
  function ClearAt(const F:TTrapPlatform;At:Double):Boolean;
  var A,B:TTrapBox;P:TTrapPoint;
  begin
    if not F.Solid(At,Plan.Duration) then Exit(True);
    P:=M.Position(At);A.Left:=P.X-TrapHalfWidth;A.Right:=P.X+TrapHalfWidth;
    A.Bottom:=P.Y+0.035;A.Top:=P.Y+TrapStandingHeight;B:=F.BoundsAt(At);
    if F.Motion=pmHinge then Exit(not F.Intersects(A,At));
    Result:=(A.Right<=B.Left+1E-8) or (A.Left>=B.Right-1E-8) or
      (A.Bottom>=B.Top-1E-8) or (A.Top<=B.Bottom+1E-8);
  end;
  function RoofClearAt(const F:TTrapPlatform;At:Double):Boolean;
  var P:TTrapPoint;B:TTrapBox;
  begin
    P:=M.Position(At);B:=F.CeilingBoundsAt(At);
    Result:=(P.X+TrapHalfWidth<=B.Left-0.10+1E-8) or (P.X-TrapHalfWidth>=B.Right+0.10-1E-8) or
      (P.Y+TrapStandingHeight<=B.Bottom-0.12+1E-8);
  end;
begin
  Result:=False;Span:=M.Finish-M.Start;
  Left:=Min(M.Origin.X,M.Target.X)-TrapHalfWidth;Right:=Max(M.Origin.X,M.Target.X)+TrapHalfWidth;
  Speed:=(Abs(M.Target.X-M.Origin.X)+Abs(M.Target.Y-M.Origin.Y)+4*M.Arc)/Span;
  if M.Kind=tmVault then Speed:=Speed*2;
  if M.Kind=tmHeadBump then Speed:=Max(4*M.Arc/(3*(M.Cue-M.Start)),2*M.Arc/(M.Finish-M.Cue));
  if M.Kind=tmRide then Speed:=Speed*Pi;
  for Tile in Plan.Platforms do begin
    if (Tile.Left-Abs(Tile.DX)>=Right) or (Tile.Right+Abs(Tile.DX)<=Left) then Continue;
    TileSpeed:=0;
    case Tile.Motion of
      pmDrop:TileSpeed:=40;
      pmFeint:TileSpeed:=Tile.DY*Pi/(Tile.Settle-Tile.Trigger);
      pmHorizontal,pmVertical:TileSpeed:=(Abs(Tile.DX)+Abs(Tile.DY))*Pi*0.5/(Tile.Settle-Tile.Trigger);
      pmRoofRise:TileSpeed:=Tile.DY*Pi*0.5/(Tile.Settle-Tile.Trigger);
      pmGoalLift:TileSpeed:=Tile.DY*1.5/(Tile.Settle-Tile.Trigger);
      pmNeedleLift:TileSpeed:=Max(Tile.DY*Pi*0.5/(Tile.Settle-Tile.Trigger),Tile.DY*Pi*0.5/(Tile.Recover-Tile.Release));
      pmHinge:TileSpeed:=(Tile.Right-Tile.Left+TrapPlatformThickness)*Pi*0.75/(Tile.Settle-Tile.Trigger);
      pmLift:TileSpeed:=Max(Tile.DY*Pi*0.5/(Tile.Settle-Tile.Trigger),
        Max(1.5*Tile.DX/(Tile.Release-Tile.Settle),1.5*(Tile.DY+Tile.DX)/(Tile.Recover-Tile.Release)));
    end;
    N:=Max(8,Ceil(Span*Max(240.0,(Speed+TileSpeed)/0.018)));
    for I:=0 to N do begin
      Time:=M.Start+Span*I/N;if not ClearAt(Tile,Time) then Exit;
    end;
    if not ClearAt(Tile,M.Cue) then Exit;
  end;
  // すべての軌道は端点の高い方+Arcより下。天井には連続時間の上限で余白を確保する。
  for Tile in Plan.Ceilings do if (Tile.Left<Right+0.10) and (Tile.Right>Left-0.10) then begin
    if Tile.Motion in [pmStatic,pmGoalWall] then begin
      if (Tile.Left<Right) and (Tile.Right>Left) and
        (Max(M.Origin.Y,M.Target.Y)+M.Arc+TrapStandingHeight>Tile.Y-0.12) then Exit;
    end else begin
      TileSpeed:=Max(2*Tile.DY/(Tile.Settle-Tile.Trigger),
        (1.5*Tile.DY+Tile.DX*Pi*0.5)/(Tile.Recover-Tile.Release));
      N:=Max(8,Ceil(Span*Max(240.0,(Speed+TileSpeed)/0.018)));
      for I:=0 to N do if not RoofClearAt(Tile,M.Start+Span*I/N) then Exit;
      if not RoofClearAt(Tile,M.Cue) then Exit;
    end;
  end;
  Result:=True;
end;

procedure ValidateTrapPlan(Plan: TTrapPlan; const Cancel: TFunc<Boolean>);
var I,J:Integer;M:TTrapMove;Trap:TTrapObstacle;Tile,Lift:TTrapPlatform;Body,Box:TTrapBox;
  Previous,P:TTrapPoint;Time,Edge,SupportLeft,SupportRight,SupportY:Double;
begin
  if (Plan=nil) or (Length(Plan.Moves)=0) then raise EArgumentException.Create('空の罠計画');
  Edge:=-1E8;
  for Tile in Plan.Platforms do begin
    if (Tile.Move<>-1) or (Tile.Left<Edge) or (Tile.Right<=Tile.Left) or
      (Abs(Tile.Y)>3.5) or (Tile.EndY<>Tile.Y) or (Tile.Start<0) or (Tile.Start>=Tile.Finish) or
      ((Tile.Motion<>pmNeedleLift) and (Tile.Start<>0)) or
      (Tile.Finish<=0) or (Tile.Finish>Plan.Duration) then raise EConvertError.Create('段差床の配置が不正です。');
    if Tile.Motion in [pmRoofDrop,pmGoalWall] then raise EConvertError.Create('天井の動作が床へ混入しています。');
    if Tile.Motion=pmFeint then raise EConvertError.Create('沈んで戻る床は現行計画では使用しません。');
    if (Tile.Reveal<0) or (Tile.Reveal>Plan.Duration) or (Tile.Trigger<0) or
      (Abs(Tile.DX)>1.5) or (not (Tile.Motion in [pmLift,pmRoofRise,pmNeedleLift,pmGoalLift]) and (Abs(Tile.DY)>1.0)) or
      ((Tile.Motion in [pmFeint,pmHorizontal,pmVertical,pmHinge,pmLift,pmRoofRise,pmNeedleLift]) and (Tile.Settle<=Tile.Trigger)) then
      raise EConvertError.Create('可動足場の時刻・移動量が不正です。');
    if (Tile.Motion=pmGoalLift) and ((Tile.DY<>TrapGoalRise) or (Tile.DX<>0) or
      (Tile.Y<>Plan.Moves[High(Plan.Moves)].Target.Y) or (Tile.Reveal<>0) or (Tile.Kind<>tkMoving) or
      (Tile.Left<>Plan.GoalX+TrapGoalAhead-0.90) or (Tile.Right<>Plan.GoalX+TrapGoalAhead+0.90) or
      (Abs(Tile.Trigger-Plan.GoalTime-TrapGoalAhead/TrapWalkSpeed)>1E-8) or
      (Abs(Tile.Settle-Tile.Trigger-TrapGoalLaunchSeconds)>1E-8) or
      (Tile.Release<>Tile.Settle) or (Abs(Tile.Recover-Tile.Settle-TrapGoalCelebration)>1E-8) or
      (Tile.Finish<>Plan.Duration)) then
      raise EConvertError.Create('地上へ出るゴール床の軌道が不正です。');
    if (Tile.Motion=pmNeedleLift) and ((Tile.DY<>TrapNeedleLiftHeight) or ((Tile.DX<>0) and (Tile.DX<>1)) or
      (Tile.Trigger<Tile.Start) or (Tile.Release<=Tile.Settle) or (Tile.Recover<=Tile.Release) or
      ((Tile.DX=0) and (Tile.Finish<>Tile.Recover)) or
      ((Tile.DX=1) and (Tile.Finish<>Plan.Duration)) or (Tile.Recover>Plan.Duration)) then
      raise EConvertError.Create('天井針に連動する上下床の行程が不正です。');
    if (Tile.Motion=pmRoofRise) and ((Tile.DX<>0) or (Tile.DY<>TrapRoofBedRise) or
      (Tile.Settle>Plan.Duration)) then raise EConvertError.Create('天井に連動する床の上昇量が不正です。');
    if ((Tile.Motion=pmHinge) and ((Tile.Right-Tile.Left>3.5) or (Tile.DX<>0) or (Tile.DY<>0) or
      (Tile.Settle>Plan.Duration))) or
      ((Tile.Motion=pmLift) and ((Tile.DY<=0) or (Tile.DX<0) or (Tile.DY+Tile.DX>2.3) or
      (Tile.Release<=Tile.Settle) or (Tile.Recover<=Tile.Release) or (Tile.Recover>Plan.Duration))) then
      raise EConvertError.Create('回転床・上昇地面の動作が不正です。');
    Edge:=Tile.Left;
  end;
  Edge:=-1E8;
  for Tile in Plan.Ceilings do begin
    if (Tile.Move<>-1) or (Tile.Left<Edge) or (Tile.Right<=Tile.Left) or
      (Abs(Tile.Y)>7) or (Tile.EndY<>Tile.Y) or (Tile.Start<>0) or
      (Tile.Finish<>Plan.Duration) then raise EConvertError.Create('段差天井の配置が不正です。');
    if not (Tile.Motion in [pmStatic,pmRoofDrop,pmGoalWall]) then raise EConvertError.Create('天井の動作が不正です。');
    if (Tile.Motion=pmGoalWall) and ((Tile.DY<=Tile.Y) or (Tile.DY>12) or (Tile.DX<>0)) then
      raise EConvertError.Create('地上へ通じる縦穴の壁が不正です。');
    if (Tile.Motion=pmRoofDrop) and ((Tile.Reveal<>0) or not InRange(Tile.DX,0.0,TrapRoofBedRise) or
      (Tile.DY<2.0) or (Tile.DY>4.0) or (Tile.Trigger<0) or (Tile.Settle<Tile.Trigger+0.85) or
      (Tile.Release<Tile.Settle+0.10) or (Tile.Recover<=Tile.Release) or (Tile.Recover>Plan.Duration)) then
      raise EConvertError.Create('落ちる天井の時刻・移動量が不正です。');
    Edge:=Tile.Left;
  end;
  Previous:=Plan.Moves[0].Origin;
  for I:=0 to High(Plan.Moves) do begin
    if Assigned(Cancel) and Cancel() then Abort;M:=Plan.Moves[I];
    if (M.Finish<=M.Start) or (M.Cue<M.Start) or (M.Cue>M.Finish) or
      (Hypot(M.Origin.X-Previous.X,M.Origin.Y-Previous.Y)>1E-8) or
      ((I>0) and (M.Start<>Plan.Moves[I-1].Finish)) or
      not (M.Kind in [tmRun,tmJump,tmStop,tmRide,tmHeadBump,tmVault]) or not M.Landing or
      ((M.Pattern<>18) and not TrapPatternEnabled(M.Avoidance)) or
      (Abs(M.Origin.Y)>3.5) or (Abs(M.Target.Y)>3.5) or
      (Abs(M.Target.X-M.Origin.X)>20) or (M.Arc<0) or (M.Arc>2.1) or
      ((M.Kind in [tmRun,tmStop]) and ((M.Arc<>0) or (M.Origin.Y<>M.Target.Y))) or
      ((M.Kind=tmStop) and (M.Target.X<>M.Origin.X)) or
      ((M.Kind in [tmRun,tmJump,tmVault]) and (M.Target.X=M.Origin.X)) or
      ((M.Kind=tmRide) and (M.Arc<>0)) or
      ((M.Kind in [tmJump,tmVault]) and (M.Arc<0.45)) then raise EConvertError.Create('歩行・ジャンプの連続軌道が不正です。');
    if ((M.Kind=tmStop) and (M.Cue<>M.Start)) or
      ((M.Kind=tmHeadBump) and ((M.Cue<=M.Start) or (M.Cue>=M.Finish) or
       (M.Origin.X<>M.Target.X) or (M.Origin.Y<>M.Target.Y))) or
      (not (M.Kind in [tmStop,tmHeadBump]) and (M.Cue<>M.Finish)) then
      raise EConvertError.Create('接地・停止・頭上接触の結果時刻が不正です。');
    Time:=Abs(M.Target.X-M.Origin.X);if M.Kind=tmRide then Time:=Time*Pi*0.5;
    if M.Kind=tmVault then Time:=Time*2;
    if Time>(M.Finish-M.Start)*TrapWalkSpeed+1E-8 then
      raise EConvertError.Create('通常の歩行速度を超えるダッシュが含まれています。再準備してください。');
    if (M.Kind in [tmRun,tmStop]) and
      (not Plan.FloorSupports(Min(M.Origin.X,M.Target.X)-TrapHalfWidth,
        Max(M.Origin.X,M.Target.X)+TrapHalfWidth,M.Origin.Y,M.Start) or
       not Plan.FloorSupports(Min(M.Origin.X,M.Target.X)-TrapHalfWidth,
        Max(M.Origin.X,M.Target.X)+TrapHalfWidth,M.Origin.Y,M.Finish)) then
      raise EConvertError.Create('歩行区間の途中に床の欠落があります。');
    for J:=0 to 8 do begin
      Time:=M.Start+(M.Finish-M.Start)*J/8;P:=M.Position(Time);
      if ((M.Kind in [tmRun,tmStop,tmRide]) or (J=0) or (J=8)) and
        not Plan.FloorSupports(P.X-TrapHalfWidth,P.X+TrapHalfWidth,P.Y,Time) then
        raise EConvertError.CreateFmt('動作%dの歩行・踏切・着地を支える床がありません。',[I]);
    end;
    if not SafeTerrainMove(Plan,M) then
      raise EConvertError.CreateFmt('動作%dが段差床または天井へ接触します。',[I]);
    Previous:=M.Target;
  end;
  for Trap in Plan.Obstacles do begin
    if Assigned(Cancel) and Cancel() then Abort;
    if Trap.Kind in [tkSideSpear,tkPress,tkCeilingNeedles,tkClosingDoor,tkFireJet,tkSpearMount] then begin
      if (Trap.Move<0) or (Trap.Move>=Length(Plan.Moves)) or (Abs(Trap.Y)>5.0) or
        (Trap.W<=0) or (Trap.W>3.0) or (Trap.H<=0) or (Trap.H>3.0) or
        (Trap.Reveal<0) or (Trap.Reveal>Trap.Fire) or (Trap.Fire<0) or (Trap.Fire>=Trap.Cue) or
        (Trap.Cue>=Trap.Finish) or (Trap.Finish>Plan.Duration) or (Trap.Embed<>0) then
        raise EConvertError.Create('追加の仕掛けの寸法・時刻が不正です。');
      if (Trap.Kind=tkSideSpear) and ((Abs(Trap.Power)<>1) or (Trap.H>0.4)) then
        raise EConvertError.Create('横槍の方向・太さが不正です。');
      if (Trap.Kind in [tkPress,tkClosingDoor]) and not InRange(Trap.Travel,2.0,3.5) then
        raise EConvertError.Create('プレス・閉鎖扉の移動量が不正です。');
      if (Trap.Kind=tkCeilingNeedles) and (Trap.H>1.0) then raise EConvertError.Create('天井針が長すぎます。');
      if ((Trap.Kind=tkPress) and (Trap.W>1.6)) or ((Trap.Kind=tkClosingDoor) and (Trap.W>1.0)) or
        ((Trap.Kind=tkFireJet) and (Trap.W>1.5)) or
        ((Trap.Kind=tkSpearMount) and ((Trap.W>0.6) or (Trap.H>1.2))) or
        ((Trap.Kind<>tkSideSpear) and (Trap.Power<>0)) or
        (not (Trap.Kind in [tkPress,tkClosingDoor]) and (Trap.Travel<>0)) or
        ((Trap.Kind in [tkClosingDoor,tkCeilingNeedles,tkSpearMount]) and (Trap.Finish<>Plan.Duration)) then
        raise EConvertError.Create('追加の仕掛けの固定部・経路が不正です。');
      SupportLeft:=Trap.X-Trap.W*0.5;SupportRight:=Trap.X+Trap.W*0.5;SupportY:=Trap.Y;
      if Trap.Kind=tkSideSpear then begin
        SupportLeft:=Min(Trap.X,Trap.X+Trap.Power*Trap.W);SupportRight:=Max(Trap.X,Trap.X+Trap.Power*Trap.W);
        SupportY:=Trap.Y-0.40;
      end;
      if Trap.Kind=tkCeilingNeedles then begin
        if not Plan.CeilingSupports(SupportLeft,SupportRight,Trap.Y+Trap.H) then
          raise EConvertError.Create('固定天井針を支える天井がありません。');
      end else begin
        if not Plan.FloorSupports(SupportLeft,SupportRight,SupportY,Trap.Cue) then
          raise EConvertError.Create('追加の仕掛けを支える地面がありません。');
        if (Trap.Kind in [tkPress,tkClosingDoor]) and
          not Plan.CeilingSupports(SupportLeft,SupportRight,Trap.Y+Trap.Travel+Trap.H) then
          raise EConvertError.Create('プレス・閉鎖扉の固定部が天井から離れています。');
      end;
      if not SafeDuring(Plan,Trap) then raise EConvertError.CreateFmt('追加の仕掛けと軌道が接触します。 kind=%d move=%d cue=%.3f',
        [Ord(Trap.Kind),Trap.Move,Trap.Cue]);
      Continue;
    end;
    if not (Trap.Kind in [tkSpikes,tkHiddenSpikes,tkCeiling,tkRock,tkBlade,tkWall,tkPit,tkCrumble,tkVanish,tkFalseFloor]) or
      (Abs(Trap.Y)>3.5) or ((Trap.Kind<>tkWall) and (Trap.H>TrapStandingHeight)) or
      (Trap.H>3) or (Trap.Travel<0) or (Trap.Travel>6) or not InRange(Trap.Embed,0.0,0.75) then
      raise EConvertError.Create('針の寸法が不正です。');
    if not TrapHarmless(Trap.Kind) then begin
      Edge:=0;if Trap.Kind=tkBlade then Edge:=Trap.Travel;
      SupportLeft:=Trap.X-Trap.W*0.5-Edge;SupportRight:=Trap.X+Trap.W*0.5+Edge;
      SupportY:=Trap.Y;if TrapFloorSpikes(Trap.Kind) then SupportY:=SupportY-TrapSpikePitDepth;
      if Trap.Kind=tkWall then begin
        SupportLeft:=SupportLeft+Min(0.0,Trap.Power*Trap.Travel);
        SupportRight:=SupportRight+Max(0.0,Trap.Power*Trap.Travel);
      end;
      if ((Trap.Kind<>tkWall) and (Trap.W>0.90)) or (Trap.W>1.5) or
        ((Trap.Kind=tkWall) and (Abs(Trap.Power)<>1)) or
        ((Trap.Kind=tkBlade) and ((Trap.Power<0.4) or (Trap.Power>3) or (Trap.Travel>0.3))) or
        not Plan.FloorSupports(SupportLeft,SupportRight,SupportY,Trap.Finish) then
        raise EConvertError.CreateFmt('罠を支える床がありません。 kind=%d move=%d pattern=%d x=%.3f y=%.3f',
          [Ord(Trap.Kind),Trap.Move,Ord(Plan.Moves[Trap.Move].Avoidance),Trap.X,Trap.Y]);
      if (Trap.Kind in [tkCeiling,tkRock]) and not Plan.CeilingSupports(Trap.X-Trap.W*0.5,
        Trap.X+Trap.W*0.5,Trap.Y+Trap.Travel+Trap.H*(1-Trap.Embed)) then raise EConvertError.Create('落下針を支える天井がありません。');
      if not SafeDuring(Plan,Trap) then raise EConvertError.CreateFmt('罠と軌道が接触します。 kind=%d move=%d pattern=%d x=%.3f y=%.3f cue=%.3f',
        [Ord(Trap.Kind),Trap.Move,Ord(Plan.Moves[Trap.Move].Avoidance),Trap.X,Trap.Y,Trap.Cue]);
    end;
  end;
  if Plan.GoalLift(Lift) then begin
    // 長い無音の末尾があっても、乗り込みと急上昇の検査密度を落とさない。
    for I:=0 to 241 do begin
      Time:=Plan.GoalTime+(Lift.Recover-Plan.GoalTime)*Min(I,240)/240;
      if I=241 then Time:=Plan.EndTime;
      P:=Plan.Position(Time);Body:=Plan.PlayerBounds(Time);
      if not Plan.FloorSupports(Body.Left,Body.Right,P.Y,Time) then
        raise EConvertError.Create('ゴールの歩行・急上昇中に床から離れます。');
      for Tile in Plan.Ceilings do if (Body.Right>Tile.Left-0.10) and (Body.Left<Tile.Right+0.10) then begin
        Box:=Tile.CeilingBoundsAt(Time);
        if (Body.Top>Box.Bottom-0.12) and (Body.Bottom<Box.Top) then
          raise EConvertError.Create('ゴールの縦穴の天井または壁へ接触します。');
      end;
      for Trap in Plan.Obstacles do if Plan.Clearance(Trap,Time)<0.10 then
        raise EConvertError.Create('地上へ向かう途中で最後の罠へ接触します。');
    end;
  end;
end;

function BuildTrapPlan(Audio:TRhythmAudio;Theme:TTrapStage;const Cancel:TFunc<Boolean>):TTrapPlan;
var
  Anchors:TList<TAnchor>;Motions:TList<TTrapMove>;Floors,Roofs,SpecialFloors,SpecialRoofs:TList<TTrapPlatform>;
  Traps:TList<TTrapObstacle>;A:TAnchor;Hit:TRhythmHit;M:TTrapMove;
  Tile,F,Cut:TTrapPlatform;Trap,Placed:TTrapObstacle;P:TTrapPoint;V:TTrapAvoidance;G:TTrapGimmick;
  BeatTimes:TArray<Double>;
  I,J,Section,StopIndex,BackIndex,EndIndex,WaitIndex,ClearMove,Role:Integer;
  Tier,LastRetreat,Candidate,Best,Score,BestScore,Steps,Phase,RoofUses:Integer;
  PatternUses:array[TTrapAvoidance] of Integer; Recent:array[0..2] of Integer;
  Beats:array[0..4] of Integer;Chosen:TTrapAvoidance;
  FinalPlaced,Aligned:Boolean;CeilingIndex:Integer;RoofHeight:Double;
  Cursor,Duration,Goal,StopTime,BackTime,EndTime,Hold,StopX,BackDistance,
    ApproachX,Frontier,Travel,SpikeEnd,GroundEnd,Arc,BaseY,RoofRight,RoofBase:Double;
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
    // 音へ間に合わせるための加速はしない。ジャンプ・後退にも歩行と同じ上限を適用する。
    if Abs(TargetX-P.X)>(UntilTime-Cursor)*TrapWalkSpeed+1E-8 then
      raise EInvalidOpException.Create('歩行速度では動作時間内に届きません。');
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
  procedure Needle(X,Height,Cue,UntilTime:Double;MoveIndex:Integer;GroundY:Double=1E9);
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkHiddenSpikes;Trap.Move:=MoveIndex;
    Trap.X:=X;Trap.Y:=P.Y;Trap.W:=0.62;Trap.H:=Height;Trap.Cue:=Cue;Trap.Synced:=True;
    if GroundY<1E8 then Trap.Y:=GroundY;
    Trap.Fire:=Max(0.0,Cue-0.04);Trap.Reveal:=0;
    Trap.Finish:=UntilTime;Traps.Add(Trap);
  end;
  procedure Falling(X,Y,Cue:Double;MoveIndex:Integer;Rock:Boolean=False);
  const EmbedLevels:array[0..3] of Double=(0.10,0.32,0.56,0.70);
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkCeiling;Trap.Move:=MoveIndex;
    Trap.X:=X;Trap.Y:=Y;Trap.W:=0.46;Trap.H:=0.80;Trap.Cue:=Cue;Trap.Synced:=True;
    if Rock then begin Trap.Kind:=tkRock;Trap.W:=0.72;Trap.H:=0.74;end;
    Trap.Embed:=EmbedLevels[Min(3,Trunc(Cue/Duration*4))];
    // 天井を作った後で、吊り下げ位置と重力から正確な発射時刻を逆算する。
    Trap.Fire:=Max(0.0,Cue-0.3);Trap.Reveal:=0;
    Trap.Finish:=Duration;Traps.Add(Trap);
  end;
  procedure StaticSpike(U,Height:Double);
  begin
    if M.Origin.Y<>M.Target.Y then U:=0.40;
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkSpikes;Trap.Move:=Motions.Count-1;
    Trap.Cue:=M.Start+(M.Finish-M.Start)*U;Trap.X:=M.Position(Trap.Cue).X;
    Trap.Y:=M.Origin.Y;Trap.W:=0.42;Trap.H:=Height;Trap.Finish:=Duration;
    Traps.Add(Trap);
  end;
  procedure PulseSpike(U,Height:Double);
  var B:Integer;
  begin
    if M.Origin.Y<>M.Target.Y then U:=0.40;
    Needle(M.Position(M.Start+(M.Finish-M.Start)*U).X,Height,M.Start,
      Min(Duration,M.Finish+0.12),Motions.Count-1,M.Origin.Y);
    if M.Origin.Y<>M.Target.Y then begin Trap.W:=0.42;Traps[Traps.Count-1]:=Trap;end;
    B:=BeatAfter(M.Start);Trap.Synced:=(B<Anchors.Count) and (Abs(Anchors[B].Time-M.Start)<1E-9);
    Traps[Traps.Count-1]:=Trap;
  end;
  procedure SweepNeedles;
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkBlade;Trap.Move:=Motions.Count-1;
    Trap.X:=(M.Origin.X+M.Target.X)*0.5;Trap.Y:=M.Origin.Y;
    Trap.W:=0.56;Trap.H:=0.56;Trap.Travel:=0.18;Trap.Power:=0.9-Tier*0.09;
    if M.Origin.Y<>M.Target.Y then begin
      Trap.X:=M.Origin.X+(M.Target.X-M.Origin.X)*0.39;
      Trap.W:=0.40;Trap.H:=0.40;Trap.Travel:=0.08;
    end;
    Trap.Cue:=(M.Start+M.Finish)*0.5;Trap.Finish:=Min(Duration,M.Finish+0.10);
    Trap.Fire:=Max(0.0,M.Start-0.15);Trap.Reveal:=0;Traps.Add(Trap);
  end;
  procedure FloorMarker(Kind:TTrapKind);
  begin
    Trap:=Default(TTrapObstacle);Trap.Kind:=Kind;Trap.Move:=Motions.Count-1;
    Trap.Cue:=M.Finish;Trap.Synced:=M.LandSynced;Trap.Finish:=Duration;
    Trap.Reveal:=0;Trap.Fire:=M.Start;Trap.Y:=M.Origin.Y;
    Trap.X:=(M.Origin.X+M.Target.X)*0.5;Trap.W:=(M.Target.X-M.Origin.X)*0.64;
    Trap.H:=0.1;Traps.Add(Trap);
  end;
  procedure AddFloor(Left,Right,Y:Double;Kind:TTrapKind;UntilTime:Double);
  var F,Previous,Special:TTrapPlatform;Q:TTrapObstacle;DesiredLeft,Take,QLeft,QRight:Double;
  begin
    F:=Default(TTrapPlatform);F.Left:=Left;F.Right:=Right;F.Y:=Y;F.EndY:=Y;
    F.Kind:=Kind;F.Move:=-1;F.Finish:=UntilTime;
    if Kind in [tkCrumble,tkVanish] then begin
      F.Motion:=pmDrop;F.Trigger:=M.Start+0.025;F.Finish:=Duration;
      DesiredLeft:=Min(F.Left,F.Right-(3.2+(M.Section mod 3)*1.4));
      // 既設の針・岩・壁を宙に浮かせないよう、支持が必要な地面の手前で止める。
      for Q in Traps do if not TrapHarmless(Q.Kind) and (Abs(Q.Y-Y)<1E-8) then begin
        QLeft:=Q.X-Q.W*0.5;QRight:=Q.X+Q.W*0.5;
        if Q.Kind=tkBlade then begin QLeft:=QLeft-Q.Travel;QRight:=QRight+Q.Travel;end;
        if Q.Kind=tkWall then begin QLeft:=QLeft+Min(0.0,Q.Power*Q.Travel);QRight:=QRight+Max(0.0,Q.Power*Q.Travel);end;
        if (QLeft<F.Left) and (QRight>DesiredLeft) then DesiredLeft:=Min(F.Left,Max(DesiredLeft,QRight+0.12));
      end;
      // U字の縁や仕掛けの出口と二重に重なる地面を巻き込まない。
      for Special in SpecialFloors do if (Abs(Special.Y-Y)<1E-8) and
        (Special.Left-Abs(Special.DX)<F.Left) and (Special.Right+Abs(Special.DX)>DesiredLeft) then
        DesiredLeft:=Min(F.Left,Max(DesiredLeft,Special.Right+Abs(Special.DX)));
      // 直前まで歩いていた同じ高さの地面を取り込み、一つの塊としてすぐ落とす。
      while (Floors.Count>0) and (F.Left>DesiredLeft+1E-8) do begin
        Previous:=Floors.Last;
        if (Previous.Motion<>pmStatic) or (Previous.Finish<>Duration) or
          (Abs(Previous.Y-Y)>1E-8) or (Abs(Previous.Right-F.Left)>1E-8) then Break;
        Take:=Previous.Right-Max(Previous.Left,DesiredLeft);if Take<=1E-8 then Break;
        F.Left:=F.Left-Take;Previous.Right:=Previous.Right-Take;
        if Previous.Right<=Previous.Left+1E-8 then Floors.Delete(Floors.Count-1)
        else begin Floors[Floors.Count-1]:=Previous;Break;end;
      end;
    end;
    Floors.Add(F);
  end;
  procedure ExcavateSpikePits;
  var Q:TTrapObstacle;F:TTrapPlatform;A,B:Double;
    procedure CutGround(AtY:Double);
    var N:Integer;Tile,Part:TTrapPlatform;
    begin
      for N:=Floors.Count-1 downto 0 do begin
        Tile:=Floors[N];
        if (Tile.Motion<>pmStatic) or (Abs(Tile.Y-AtY)>1E-8) or
          (Tile.Right<=A+1E-8) or (Tile.Left>=B-1E-8) then Continue;
        Floors.Delete(N);
        if Tile.Left<A-1E-8 then begin Part:=Tile;Part.Right:=A;Floors.Add(Part);end;
        if Tile.Right>B+1E-8 then begin Part:=Tile;Part.Left:=B;Floors.Add(Part);end;
      end;
    end;
  begin
    for Q in Traps do if TrapFloorSpikes(Q.Kind) then begin
      A:=Q.X-Q.W*0.5;B:=Q.X+Q.W*0.5;
      if Q.Kind=tkBlade then begin A:=A-Q.Travel;B:=B+Q.Travel;end;
      CutGround(Q.Y);CutGround(Q.Y-TrapSpikePitDepth);
      F:=Default(TTrapPlatform);F.Left:=A;F.Right:=B;F.Y:=Q.Y-TrapSpikePitDepth;F.EndY:=F.Y;
      F.Move:=-1;F.Kind:=tkPit;F.Finish:=Duration;Floors.Add(F);
      // 待機中に歩く収納式の針だけは、透ける薄い格子で従来の足元を支える。
      if Q.Kind=tkHiddenSpikes then begin
        F.Y:=Q.Y;F.EndY:=F.Y;F.Kind:=tkBridge;F.Motion:=pmGrate;Floors.Add(F);
      end;
    end;
  end;
  procedure AddRoof(Left,Right,Y:Double);
  var R,Platform:TTrapPlatform;Move:TTrapMove;Q:TTrapObstacle;Height:Double;
  begin
    Height:=Y+2.05+(Roofs.Count mod 3)*0.15;
    for Move in Result.Moves do
      if (Max(Move.Origin.X,Move.Target.X)+TrapHalfWidth>Left) and
        (Min(Move.Origin.X,Move.Target.X)-TrapHalfWidth<Right) then
        Height:=Max(Height,Max(Move.Origin.Y,Move.Target.Y)+Move.Arc+TrapStandingHeight+
          0.27-0.035*Min(3,Trunc(Move.Start/Duration*4)));
    for Q in Traps do if (Q.Kind in [tkCeiling,tkRock]) and (Q.X+Q.W*0.5>Left) and (Q.X-Q.W*0.5<Right) then
      Height:=Max(Height,Q.Y+Q.H+2.6+Ord(Q.Kind=tkRock)*0.5);
    for Q in Traps do if (Q.Kind=tkWall) and (Q.X+Q.Travel+Q.W*0.5>Left) and
      (Q.X-Q.Travel-Q.W*0.5<Right) then Height:=Max(Height,Q.Y+Q.H+0.20);
    for Platform in Result.Platforms do if (Platform.Motion=pmHinge) and
      (Platform.Right>Left) and (Platform.Left<Right) then
      Height:=Max(Height,Platform.Y+Platform.Right-Platform.Left+0.20);
    // 最後の歩行区間にも、縦穴へ向かうための頭上余白を残す。
    if Right>Result.GoalX-4.0 then Height:=Max(Height,5.3);
    R:=Default(TTrapPlatform);R.Left:=Left;R.Right:=Right;R.Y:=Height;R.EndY:=Height;
    R.Move:=-1;R.Kind:=tkCeiling;R.Finish:=Duration;Roofs.Add(R);
  end;
  procedure GoalFloor;
  var N:Integer;F,Part:TTrapPlatform;A,B,Base:Double;
  begin
    // 音同期済みのコース終点を動かさず、その先だけを昇降板の穴と支持床へ置き換える。
    Base:=Result.Moves[High(Result.Moves)].Target.Y;
    A:=Result.GoalX+TrapGoalAhead-0.90;B:=Result.GoalX+TrapGoalAhead+0.90;
    for N:=Floors.Count-1 downto 0 do begin
      F:=Floors[N];if (F.Motion<>pmStatic) or (F.Right<=A) or (F.Left>=B) then Continue;
      Floors.Delete(N);
      if F.Left<A then begin Part:=F;Part.Right:=A;Floors.Add(Part);end;
      if F.Right>B then begin Part:=F;Part.Left:=B;Floors.Add(Part);end;
    end;
    F:=Default(TTrapPlatform);F.Left:=A;F.Right:=B;F.Y:=Base-1.20;F.EndY:=F.Y;
    F.Move:=-1;F.Kind:=tkPit;F.Finish:=Duration;Floors.Add(F);
    F.Y:=Base;F.EndY:=Base;F.Kind:=tkMoving;F.Motion:=pmGoalLift;F.DY:=TrapGoalRise;
    F.Trigger:=Result.GoalTime+TrapGoalAhead/TrapWalkSpeed;F.Settle:=F.Trigger+TrapGoalLaunchSeconds;
    F.Release:=F.Settle;F.Recover:=F.Settle+TrapGoalCelebration;Floors.Add(F);
  end;
  procedure GoalShaft;
  var R,Part:TTrapPlatform;N:Integer;Base,Edge:Double;
  begin
    // 絵だけの開口にせず、実天井を切って有限高さの左右壁を保存する。
    Base:=Result.Moves[High(Result.Moves)].Target.Y;Edge:=Result.GoalX+0.55;
    Roofs.Clear;Roofs.AddRange(Result.Ceilings);
    for N:=Roofs.Count-1 downto 0 do begin
      R:=Roofs[N];if R.Right<=Edge then Continue;Roofs.Delete(N);
      if R.Left<Edge then begin Part:=R;Part.Right:=Edge;Roofs.Add(Part);end;
    end;
    R:=Default(TTrapPlatform);R.Left:=Edge;R.Right:=Result.GoalX+0.80;R.Y:=Base+2.20;R.EndY:=R.Y;
    R.Move:=-1;R.Kind:=tkCeiling;R.Motion:=pmGoalWall;R.DY:=Base+TrapGoalRise;R.Finish:=Duration;Roofs.Add(R);
    R.Left:=Result.GoalX+4.00;R.Right:=Result.GoalX+8.00;R.Y:=Base;R.EndY:=R.Y;Roofs.Add(R);
    Roofs.Sort(TComparer<TTrapPlatform>.Construct(function(const A,B:TTrapPlatform):Integer
      begin Result:=CompareValue(A.Left,B.Left);end));
    Result.Ceilings:=Roofs.ToArray;
  end;
  function ChainFits(Kind:TTrapAvoidance):Boolean;
  var N,B,Stage:Integer;At,Limit:Double;
  begin
    At:=StopTime;Result:=False;
    if IsTrapGimmick(Kind) then begin
      B:=BeatAfter(Cursor+0.62);if B>=Anchors.Count then Exit;
      Stage:=Min(3,Trunc(Anchors[B].Time/Max(0.01,Goal)*4));
      if ((Kind=taRoofShelters) and (Stage>1)) or ((Kind=taRoofNarrow) and (Stage<>2)) or
        ((Kind=taRoofLastGap) and (Stage<>3)) then Exit;
      Result:=TrapGimmickFits(Kind,BeatTimes,Anchors[B].Time,Goal,Section,RoofUses);Exit;
    end;
    Limit:=3.0;
    if Kind in [taDropStopJump,taRockStopJump,taRetreatJump,taWaitPass,taBaitDrop,
      taRunUnderDrops,taBetweenDrops,taBackHop,taRockRun,taRockBait] then Limit:=0.64;
    for N:=0 to TrapPatternSteps(Kind)-1 do begin
      B:=BeatAfter(At+0.32);
      if (B>=Anchors.Count) or (Anchors[B].Time-At>Limit+1E-8) then Exit;
      At:=Anchors[B].Time;
    end;
    Result:=True;
  end;
  procedure Remember;
  begin
    Inc(PatternUses[V]);Recent[2]:=Recent[1];Recent[1]:=Recent[0];Recent[0]:=TrapPatternFamily(V);
    if Recent[0]=5 then LastRetreat:=Section;
    if (V=taFinalGauntlet) and (Cursor>Goal*0.86) then FinalPlaced:=True;
    Inc(Section);
  end;
  // 各連鎖は先に全着地音を確保する。終端に収まらない未完成の仕掛けは置かない。
  procedure ForwardChain;
  var N,B:Integer;At,Height,Delta:Double;Rock:Boolean;
  begin
    Steps:=TrapPatternSteps(V);At:=StopTime;
    for N:=0 to Steps-1 do begin B:=BeatAfter(At+0.32);Beats[N]:=B;At:=Anchors[B].Time;end;
    WalkUntil(StopTime);
    for N:=0 to Steps-1 do begin
      EndTime:=Anchors[Beats[N]].Time;Role:=20;Delta:=0;Height:=0.90;Rock:=False;
      if (V=taDropSprintHop) and (N=0) then begin
        StopX:=P.X;BaseY:=P.Y;At:=Cursor;WalkUntil(EndTime,24);
        Falling(StopX-1.45,BaseY,At,Motions.Count-1);
        Falling(P.X-1.45,BaseY,EndTime,Motions.Count-1);Continue;
      end;
      // 疎らな音でも着地を失わない。無音部分は歩き、音の0.5秒前から一つの放物線で跳ぶ。
      if EndTime-Cursor>0.64+1E-8 then WalkUntil(EndTime-0.50);
      case V of
        taLowHop,taTripleHop:Height:=0.70;
        taLongJump:Height:=1.45;
        taStepUp:Delta:=0.45;
        taStepDown:Delta:=-0.45;
        taGapUp:begin Delta:=0.55;Height:=1.1;Role:=21;end;
        taGapDown:begin Delta:=-0.55;Height:=1.1;Role:=21;end;
        taCrumbleUp:begin Delta:=0.35;Role:=22;end;
        taVanishDown:begin Delta:=-0.35;Role:=23;end;
        taSawHop,taTwinSaws:Height:=1.25;
        taSawGap:begin Height:=1.25;if N=1 then Role:=21;end;
        taSawStair:begin Height:=1.35;Delta:=0.25*(1-2*(N mod 2));end;
        taRockGap:begin Role:=21;Height:=1.25;Rock:=True;end;
        taDoubleGap,taTripleGap:begin Role:=21;Height:=1.05;end;
        taRisingGaps:begin Role:=21;Delta:=-0.35+N*0.35-P.Y;Height:=1.15;end;
        taFallingGaps:begin Role:=21;Delta:=0.45-N*0.40-P.Y;Height:=1.15;end;
        taCrumbleChain:begin Role:=22;Delta:=0.20*(1-2*(N mod 2));end;
        taVanishChain:begin Role:=23;Delta:=0.2*(1-2*(N mod 2));Height:=1.05;end;
        taCrumbleNeedles:if N=0 then Role:=22 else Height:=1.20;
        taVanishDrop:begin if N=0 then Role:=23;Height:=1.15;end;
        taNeedleRelay:Height:=0.95+N*0.12;
        taAlternatingHops:begin Height:=0.95;Delta:=0.3*(1-2*(N mod 2));end;
        taLowHighHop:Height:=0.70+N*0.85;
        taDropStair:begin Delta:=0.25*(1-2*(N mod 2));Height:=1.15;end;
        taDropSprintHop:begin Height:=1.20;if N=1 then Role:=21;end;
        taDelayedLanding:begin if N=0 then Role:=21 else Role:=22;Height:=1.10;end;
        taCrossTrap:begin Height:=1.35;if N=0 then Role:=21;end;
        taFinalGauntlet:begin
          Height:=1.25;
          case N of 0:Role:=22;1:Role:=21;2:Delta:=0.30;3:Role:=23;4:Delta:=-0.30;end;
        end;
      end;
      Delta:=EnsureRange(P.Y+Delta,-0.55,0.70)-P.Y;
      Travel:=(EndTime-Cursor)*TrapWalkSpeed;
      Motion(EndTime,P.X+Travel,tmJump,Height,False,True,Role,Delta);
      case Role of 21:FloorMarker(tkPit);22:FloorMarker(tkCrumble);23:FloorMarker(tkVanish);end;
      case V of
        taLowHop,taTripleHop,taLowHighHop,taAlternatingHops:StaticSpike(0.5,0.22+Tier*0.035);
        taLongJump:begin StaticSpike(0.36,0.36);StaticSpike(0.64,0.36);end;
        taSawHop,taTwinSaws,taSawStair:SweepNeedles;
        taSawGap:if N=0 then SweepNeedles;
        taCrumbleNeedles:if N=1 then PulseSpike(0.5,0.38);
        taNeedleRelay:PulseSpike(0.5,0.30+N*0.07);
        taCrossTrap:if N=1 then SweepNeedles;
        taFinalGauntlet:case N of 2:SweepNeedles;4:PulseSpike(0.5,0.40);end;
      end;
      if Rock then Falling(M.Origin.X-1.05,M.Origin.Y,M.Finish,Motions.Count-1,True)
      else if (Role=20) and (V in [taVanishDrop,taDropStair,taDropSprintHop,taCrossTrap,taFinalGauntlet]) then
        Falling(M.Origin.X,M.Origin.Y,M.Finish,Motions.Count-1,
          (V in [taCrossTrap,taFinalGauntlet]) and Odd(N));
    end;
  end;
begin
  if (Audio=nil) or IsNan(Audio.Duration) or IsInfinite(Audio.Duration) or (Audio.Duration<=0) then
    raise EArgumentException.Create('音源長が不正です。');
  Result:=TTrapPlan.Create;Anchors:=TList<TAnchor>.Create;Motions:=TList<TTrapMove>.Create;
  Floors:=TList<TTrapPlatform>.Create;Roofs:=TList<TTrapPlatform>.Create;Traps:=TList<TTrapObstacle>.Create;
  SpecialFloors:=TList<TTrapPlatform>.Create;
  SpecialRoofs:=TList<TTrapPlatform>.Create;
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
    SetLength(BeatTimes,Anchors.Count);for I:=0 to Anchors.Count-1 do BeatTimes[I]:=Anchors[I].Time;
    Cursor:=0;P:=TrapPoint(0,0);Section:=0;RoofUses:=0;V:=taTravel;
    FillChar(PatternUses,SizeOf(PatternUses),0);for I:=0 to 2 do Recent[I]:=-1;LastRetreat:=-100;FinalPlaced:=False;
    while Cursor<Goal-0.6 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      Tier:=Min(3,Trunc(Cursor/Max(0.01,Goal)*4));
      StopIndex:=BeatAfter(Cursor+0.48-Tier*0.09);if StopIndex>=Anchors.Count then Break;
      StopTime:=Anchors[StopIndex].Time;
      // 使用回数の少ない仕掛けを優先し、直近と同じ系列・短い間隔の後退を避ける。
      Best:=-1;BestScore:=MaxInt;
      for Chosen:=Low(TTrapAvoidance) to High(TTrapAvoidance) do begin
        if not TrapPatternEnabled(Chosen) or (TrapPatternTier(Chosen)>Tier) or not ChainFits(Chosen) then Continue;
        if (Tier>=2) and (TrapPatternTier(Chosen)<Tier-1) then Continue;
        if (Cursor>Goal*0.92) and (TrapPatternSteps(Chosen)<3) then Continue;
        if (TrapPatternFamily(Chosen)=5) and (Section-LastRetreat<8) then Continue;
        Candidate:=Ord(Chosen);Score:=PatternUses[Chosen]*100+(Candidate*13+Section*7+Ord(Theme)*11) mod 31;
        for Phase:=0 to 2 do if TrapPatternFamily(Chosen)=Recent[Phase] then Inc(Score,65-Phase*20);
        if TrapPatternFamily(Chosen)=5 then begin
          Inc(Score,35);
        end;
        if Score<BestScore then begin Best:=Candidate;BestScore:=Score;end;
      end;
      if (Cursor>Goal*0.86) and not FinalPlaced and ChainFits(taFinalGauntlet) then Best:=Ord(taFinalGauntlet);
      if Best<0 then begin V:=taTravel;WalkUntil(StopTime);Inc(Section);Continue;end;
      V:=TTrapAvoidance(Best);
      if IsTrapGimmick(V) then begin
        StopIndex:=BeatAfter(Cursor+0.62);StopTime:=Anchors[StopIndex].Time;WalkUntil(StopTime);
        if not MakeTrapGimmick(V,BeatTimes,StopTime,Goal,Duration,P,Section,G,RoofUses) then begin Inc(Section);Continue;end;
        ClearMove:=Motions.Count;Motions.AddRange(G.Moves);SpecialFloors.AddRange(G.Floors);
        SpecialRoofs.AddRange(G.Roofs);
        if Length(G.Roofs)>0 then Inc(RoofUses); // 他の仕掛けの通し番号で避難先が偏らないようにする。
        for Trap in G.Traps do begin Placed:=Trap;Placed.Move:=Trap.Move+ClearMove;Traps.Add(Placed);end;
        M:=Motions.Last;Cursor:=M.Finish;P:=M.Target;Remember;Continue;
      end;
      if (TrapPatternFamily(V)=5) and (StopTime-Cursor<0.55) then begin
        StopIndex:=BeatAfter(Cursor+0.55);if StopIndex>=Anchors.Count then Break;
        StopTime:=Anchors[StopIndex].Time;
      end;
      if not (V in [taRetreatJump,taWaitPass,taDropStopJump,taBaitDrop,taRunUnderDrops,
        taBetweenDrops,taBackHop,taRockRun,taRockStopJump,taRockBait]) then begin
        ForwardChain;Remember;Continue;
      end;
      if V in [taDropStopJump,taRockStopJump] then begin
        EndIndex:=BeatAfter(StopTime+0.44);
        if (EndIndex>=Anchors.Count) or (Anchors[EndIndex].Time-StopTime>0.64) then begin
          WalkUntil(StopTime);Inc(Section);Continue;end;
        WalkUntil(StopTime);StopX:=P.X;BaseY:=P.Y;EndTime:=Anchors[EndIndex].Time;
        Motion(StopTime+0.06,P.X,tmStop,0,True,False,0);
        Motion(EndTime,P.X+(EndTime-Cursor)*TrapWalkSpeed,tmJump,1.9,False,True,4);
        Falling(StopX+1.2,BaseY,StopTime,Motions.Count-1,V=taRockStopJump);
        Remember;Continue;
      end;
      BackIndex:=BeatAfter(StopTime+0.25);
      // 短い後退でも落下物から身体が離れる時間を残す。距離や速度を増やして補わない。
      if TrapPatternFamily(V)=5 then BackIndex:=BeatAfter(StopTime+0.32);
      if (BackIndex>=Anchors.Count) or (Anchors[BackIndex].Time-StopTime>0.55) then begin
        WalkUntil(StopTime);Inc(Section);Continue;end;
      BackTime:=Anchors[BackIndex].Time;EndIndex:=BeatAfter(BackTime+0.38);
      // 後退からの復帰は、歩行速度で針を越せる跳躍時間を先に確保する。
      if TrapPatternFamily(V)=5 then EndIndex:=BeatAfter(BackTime+0.50);
      WaitIndex:=BeatAfter(BackTime+0.15);
      if (V=taWaitPass) and (WaitIndex<Anchors.Count) and
        (Anchors[WaitIndex].Time-BackTime<=0.55) then EndIndex:=WaitIndex
      else if V=taWaitPass then begin V:=taTravel;WalkUntil(StopTime);Inc(Section);Continue;end;
      if (EndIndex>=Anchors.Count) or ((V<>taWaitPass) and
        (Anchors[EndIndex].Time-BackTime>0.68)) then begin
        WalkUntil(StopTime);Inc(Section);Continue;end;
      EndTime:=Anchors[EndIndex].Time;ApproachX:=P.X;
      WalkUntil(StopTime);StopX:=P.X;BaseY:=P.Y;
      if V=taWaitPass then begin
        Motion(BackTime,P.X,tmStop,0,True,True,3);ClearMove:=Motions.Count-1;
        Needle(StopX+1.05,0.58,StopTime,BackTime,ClearMove);
        WalkUntil(EndTime,24);Remember;Continue;
      end;
      if V in [taRunUnderDrops,taRockRun] then begin
        WalkUntil(EndTime,24);ClearMove:=Motions.Count-1;
        Falling(StopX-1.45,BaseY,StopTime,ClearMove,V=taRockRun);
        Falling(StopX+(BackTime-StopTime)*TrapWalkSpeed-1.45,BaseY,BackTime,ClearMove,V=taRockRun);
        Falling(StopX+(EndTime-StopTime)*TrapWalkSpeed-1.45,BaseY,EndTime,ClearMove,V=taRockRun);
        Remember;Continue;
      end;
      if V=taBetweenDrops then begin
        Motion(BackTime,P.X,tmStop,0,True,True,3);
        Motion(BackTime+0.04,P.X,tmStop,0,True,False,3);
        Motion(EndTime,P.X+(EndTime-Cursor)*TrapWalkSpeed,tmJump,1.9,False,True,4);ClearMove:=Motions.Count-1;
        Falling(StopX-1.50,BaseY,StopTime,ClearMove);Falling(StopX+1.35,BaseY,BackTime,ClearMove);
        Remember;Continue;
      end;
      Hold:=Min(0.08,(BackTime-StopTime)*0.25);
      Motion(StopTime+Hold,P.X,tmStop,0,True,False,0);
      BackDistance:=Min(1.30,Min((BackTime-Cursor)*TrapWalkSpeed,StopX-ApproachX-0.65));
      if (V=taBackHop) and (BackTime-Cursor>=0.30) then
        // 距離1.3の後ろ跳びでは、上半身を落下針の下降経路へ持ち上げすぎない。
        Motion(BackTime,StopX-BackDistance,tmJump,TrapBackHopArc,False,True,2)
      else Motion(BackTime,StopX-BackDistance,tmRun,0,False,True,2);
      Motion(BackTime+0.04,P.X,tmStop,0,True,False,3);
      Arc:=1.90;if V=taBackHop then Arc:=1.70;
      Motion(EndTime,P.X+(EndTime-Cursor)*TrapWalkSpeed,tmJump,Arc,False,True,4);
      SpikeEnd:=Min(Duration,EndTime+0.08);ClearMove:=Motions.Count-1;
      Needle(StopX+0.80,0.58,StopTime,SpikeEnd,ClearMove);
      if V in [taBaitDrop,taBackHop,taRockBait] then Falling(StopX,BaseY,BackTime,ClearMove,V=taRockBait)
      else Needle(StopX,0.50,BackTime,SpikeEnd,ClearMove);
      Remember;
    end;
    V:=taTravel;WalkUntil(Goal);
    Result.Moves:=Motions.ToArray;Result.GoalTime:=Cursor;Result.GoalX:=P.X;
    Frontier:=0;AddFloor(-8,0,0,tkMoving,Duration);
    for I:=0 to High(Result.Moves) do begin
      M:=Result.Moves[I];if M.Target.X<=Frontier then Continue;
      if M.Pattern=30 then begin Frontier:=M.Target.X;Continue;end;
      Travel:=M.Target.X-M.Origin.X;
      if M.Pattern in [21,22,23] then begin
        if M.Pattern=22 then Trap.Kind:=tkCrumble else if M.Pattern=23 then Trap.Kind:=tkVanish else Trap.Kind:=tkPit;
        // 崩落は初めから穴にしない。踏切後に地続きの地層を落として初めて空洞を作る。
        GroundEnd:=M.Origin.X+Travel*0.18;
        if M.Pattern in [22,23] then GroundEnd:=M.Origin.X+Travel*0.82;
        AddFloor(Frontier,GroundEnd,M.Origin.Y,Trap.Kind,Duration);
        AddFloor(M.Origin.X+Travel*0.82,M.Target.X,M.Target.Y,tkMoving,Duration);
      end else if M.Origin.Y<>M.Target.Y then begin
        AddFloor(Frontier,M.Origin.X+Travel*0.55,M.Origin.Y,tkMoving,Duration);
        AddFloor(M.Origin.X+Travel*0.55,M.Target.X,M.Target.Y,tkMoving,Duration);
      end else AddFloor(Frontier,M.Target.X,M.Target.Y,tkMoving,Duration);
      Frontier:=M.Target.X;
    end;
    AddFloor(Frontier,Frontier+8,P.Y,tkMoving,Duration);
    Floors.AddRange(SpecialFloors);
    ExcavateSpikePits;
    GoalFloor;
    Floors.Sort(TComparer<TTrapPlatform>.Construct(function(const A,B:TTrapPlatform):Integer
      begin Result:=CompareValue(A.Left,B.Left);if Result=0 then Result:=CompareValue(A.Y,B.Y);end));
    Result.Platforms:=Floors.ToArray;RoofRight:=-8;
    while RoofRight<Frontier+8-1E-8 do begin
      RoofBase:=Min(Frontier+8,RoofRight+2.5);AddRoof(RoofRight,RoofBase,0);RoofRight:=RoofBase;
    end;
    // 普通の天井と同じ場所へ静止した天井を二重に残さず、段違いの地層へ置き換える。
    for F in SpecialRoofs do begin
      for J:=Roofs.Count-1 downto 0 do begin
        Tile:=Roofs[J];if (Tile.Right<=F.Left+1E-8) or (Tile.Left>=F.Right-1E-8) then Continue;
        Roofs.Delete(J);
        if Tile.Left<F.Left-1E-8 then begin Cut:=Tile;Cut.Right:=F.Left;Roofs.Add(Cut);end;
        if Tile.Right>F.Right+1E-8 then begin Cut:=Tile;Cut.Left:=F.Right;Roofs.Add(Cut);end;
      end;
    end;
    Roofs.AddRange(SpecialRoofs);
    Roofs.Sort(TComparer<TTrapPlatform>.Construct(function(const A,B:TTrapPlatform):Integer
      begin Result:=0;if A.Left<B.Left then Result:=-1 else if A.Left>B.Left then Result:=1;end));
    Result.Ceilings:=Roofs.ToArray;
    // 落下物が天井の段差をまたぐ箇所は、支持するタイルの下面を揃えてから吊るす。
    // 高さは既存値の最大値へだけ動かすので、重なる支持範囲も有限回で同じ面に収束する。
    Aligned:=False;
    while not Aligned do begin
      if Assigned(Cancel) and Cancel() then Abort;Aligned:=True;
      for Trap in Traps do if Trap.Kind in [tkCeiling,tkRock] then begin
        RoofHeight:=-7;
        for Tile in Result.Ceilings do
          if (Tile.Right>Trap.X-Trap.W*0.5) and (Tile.Left<Trap.X+Trap.W*0.5) then
            RoofHeight:=Max(RoofHeight,Tile.Y);
        for CeilingIndex:=0 to High(Result.Ceilings) do begin
          Tile:=Result.Ceilings[CeilingIndex];
          if (Tile.Right>Trap.X-Trap.W*0.5) and (Tile.Left<Trap.X+Trap.W*0.5) and (Tile.Y<RoofHeight) then begin
            Result.Ceilings[CeilingIndex].Y:=RoofHeight;Result.Ceilings[CeilingIndex].EndY:=RoofHeight;Aligned:=False;
          end;
        end;
      end;
    end;
    for I:=0 to Traps.Count-1 do begin
      Trap:=Traps[I];if not (Trap.Kind in [tkCeiling,tkRock]) then Continue;
      for Tile in Result.Ceilings do if (Trap.X>=Tile.Left) and (Trap.X<=Tile.Right) then begin
        Trap.Travel:=Tile.Y-Trap.Y-Trap.H*(1-Trap.Embed);Break;end;
      Trap.Fire:=Trap.Cue-Sqrt(2*Trap.Travel/48);
      Trap.Reveal:=0;
      if Trap.Fire<0 then raise EInvalidOpException.Create('天井の落下準備時間が足りません。');
      Traps[I]:=Trap;
    end;
    GoalShaft;
    Result.Obstacles:=Traps.ToArray;ValidateTrapPlan(Result,Cancel);
  except
    Result.Free;Anchors.Free;Motions.Free;Floors.Free;Roofs.Free;Traps.Free;SpecialFloors.Free;SpecialRoofs.Free;raise;
  end;
  Anchors.Free;Motions.Free;Floors.Free;Roofs.Free;Traps.Free;SpecialFloors.Free;SpecialRoofs.Free;
end;
end.
