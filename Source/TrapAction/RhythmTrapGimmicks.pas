unit RhythmTrapGimmicks;
// 退避・横槍・プレス・回転床・上昇床・扉・火柱を、保存可能な絶対時刻の動作と地形へ組み立てる。
// コース全体の採用順や保存I/Oは担当せず、一つの仕掛けに必要な音時刻と局所地形だけを返す。
interface
uses RhythmTrapPlan;
type
  TTrapGimmick=record
    // オブジェクトの所有権は持たない値配列。Buildがコース本体へ統合するための一時結果。
    Moves:TArray<TTrapMove>;
    Floors:TArray<TTrapPlatform>;
    Roofs:TArray<TTrapPlatform>;
    Traps:TArray<TTrapObstacle>;
  end;
function IsTrapGimmick(Kind:TTrapAvoidance):Boolean;
// Beatsは昇順の原音声秒。Start以降、Goalまでに全行程が収まる場合だけTrue。
function TrapGimmickFits(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal:Double;Section:Integer=0;RoofRouteIndex:Integer=-1):Boolean;
// 同じ日程判定で組み立てる。Originは絶対世界座標、Durationは音声長で、入力配列は借用する。
// RoofRouteIndexは天井罠の登場順。-1ならSectionを代用し、他種の罠による避難先の偏りを避ける。
function MakeTrapGimmick(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal,Duration:Double;
  Origin:TTrapPoint;Section:Integer;out G:TTrapGimmick;RoofRouteIndex:Integer=-1):Boolean;
implementation
uses System.Math,System.Generics.Collections;
type TTimes=array[0..16] of Double;
  TRoofEntry=(reForward,reRetreat,reWait);
  TRoofRoute=record
    SafeIndex,Pre:Integer;
    Entry:TRoofEntry;
  end;
  TRoofRecipe=record
    Slots:Integer;
    Width,Headroom,FallMin,FallMax,Hold,ReturnTime:Double;
  end;
// 天井の登場順で入口と避難先を分散する。右端の外へ出てから戻るだけの回避は作らない。
function RoofRoute(Section,RouteIndex:Integer):TRoofRoute;
const Targets:array[0..7] of Integer=(0,1,2,0,1,2,0,1);
      Entries:array[0..7] of TRoofEntry=(reRetreat,reForward,reWait,reForward,reRetreat,reForward,reWait,reWait);
begin
  if RouteIndex<0 then RouteIndex:=Section;
  RouteIndex:=RouteIndex mod Length(Targets);
  Result.SafeIndex:=Targets[RouteIndex];Result.Entry:=Entries[RouteIndex];
  Result.Pre:=Result.SafeIndex+1+Ord(Result.Entry<>reForward);
end;
function RoofRecipe(Kind:TTrapAvoidance):TRoofRecipe;
begin
  Result.Slots:=3;Result.Width:=1.42;Result.Headroom:=1.70;
  Result.FallMin:=1.80;Result.FallMax:=2.50;Result.Hold:=0.35;Result.ReturnTime:=0.90;
  if Kind=taRoofNarrow then begin
    Result.Slots:=2;Result.Width:=1.14;Result.Headroom:=1.48;
    Result.FallMin:=1.30;Result.FallMax:=1.75;Result.Hold:=0.25;Result.ReturnTime:=0.75;
  end;
  if Kind=taRoofLastGap then begin
    Result.Slots:=1;Result.Width:=0.90;Result.Headroom:=1.30;
    Result.FallMin:=0.90;Result.FallMax:=1.25;Result.Hold:=0.18;Result.ReturnTime:=0.60;
  end;
end;

function IsTrapGimmick(Kind:TTrapAvoidance):Boolean;
begin Result:=(Kind>=taFeintFloor) and TrapPatternEnabled(Kind);end;

function Schedule(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal:Double;Section,RoofRouteIndex:Integer;out T:TTimes):Boolean;
var N,Pre:Integer;Recipe:TRoofRecipe;Route:TRoofRoute;
  function Find(From,Gap,Limit:Double;out At:Double):Boolean;
  var L,R,M:Integer;
  begin
    L:=0;R:=Length(Beats);
    while L<R do begin M:=(L+R) div 2;
      if Beats[M]<From+Gap-1E-9 then L:=M+1 else R:=M;end;
    Result:=(L<Length(Beats));if not Result then Exit;
    At:=Beats[L];Result:=(At<=Goal) and (At-From<=Limit+1E-8);
  end;
  function Next(Index:Integer;Gap,Limit:Double):Boolean;
  begin Result:=Find(T[Index-1],Gap,Limit,T[Index]);end;
begin
  T:=Default(TTimes);T[0]:=Start;Result:=False;
  if not TrapPatternEnabled(Kind) then Exit;
  case Kind of
    taSideSpears:begin
      if not Next(1,0.35,0.90) or not Next(2,0.60,1.20) or not Next(3,0.70,1.30) or
        not Next(4,0.35,0.90) or not Next(5,0.60,1.20) or not Next(6,0.80,1.40) then Exit;
    end;
    taAlternatingPresses,taFireChase:begin
      for N:=1 to 9 do
        if N mod 3=0 then begin if not Next(N,0.65,1.30) then Exit;end
        else if N mod 3=1 then begin if not Next(N,0.40,0.90) then Exit;end
        else if not Next(N,0.60,1.20) then Exit;
    end;
    taFlipPit:if not Next(1,0.65,1.20) or not Next(2,0.70,1.30) then Exit;
    taCeilingLift:begin
      if not Next(1,0.50,1.10) then Exit;
      for N:=2 to 14 do case N mod 4 of
        0,2:if not Next(N,0.60,1.20) then Exit;
        1:if not Next(N,0.55,1.10) then Exit;
        3:if not Next(N,0.35,0.90) then Exit;
      end;
      if not Next(15,0.55,1.10) or not Next(16,0.60,1.20) then Exit;
    end;
    taClosingDoors:for N:=1 to 3 do if not Next(N,0.65,1.20) then Exit;
    taRoofShelters,taRoofNarrow,taRoofLastGap:begin
      Recipe:=RoofRecipe(Kind);Route:=RoofRoute(Section,RoofRouteIndex);Pre:=Route.Pre;
      if not Next(1,0.40,0.90) then Exit;
      for N:=2 to Pre do if not Next(N,0.50,1.10) then Exit;
      if not Next(Pre+1,0.40,0.65) or
        not Find(T[Pre],Recipe.FallMin,Recipe.FallMax,T[9]) then Exit;
      if not Next(Pre+2,T[9]+Recipe.Hold+Recipe.ReturnTime+0.12-T[Pre+1],5.0) then Exit;
      for N:=Pre+3 to 7+Ord(Route.Entry<>reForward) do if not Next(N,0.55,1.10) then Exit;
    end;
    taCrushSlot:begin
      if not Next(1,0.40,0.90) or not Next(2,0.62,1.30) or
        not Next(3,0.35,0.90) or not Next(4,0.60,1.30) then Exit;
    end;
    taCrushReverse:begin
      if not Next(1,0.70,1.40) or not Next(2,0.56,1.20) or not Next(3,0.35,0.90) or
        not Next(4,0.55,1.20) or not Next(5,0.60,1.30) then Exit;
    end;
    taCrushHop:begin
      if not Next(1,0.40,0.90) or not Next(2,0.45,1.0) or not Next(3,0.50,1.10) then Exit;
    end;
    taCrushFeint:begin
      if not Next(1,0.40,0.90) or not Next(2,0.35,0.90) or not Next(3,0.35,0.90) or
        not Next(4,0.35,0.90) or not Next(5,0.60,1.30) then Exit;
    end;
    taHiddenStairs,taHiddenSwitchback:begin
      if not Next(1,0.22,0.65) or not Next(2,0.22,0.65) or not Next(3,0.36,0.90) then Exit;
      for N:=4 to 10 do if not Next(N,0.40,0.90) then Exit;
    end;
    taMovingDescentX,taMovingDescentY:
      for N:=1 to 4 do if not Next(N,0.40,0.90) then Exit;
    else Exit;
  end;
  Result:=True;
end;

function TrapGimmickFits(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal:Double;Section,RoofRouteIndex:Integer):Boolean;
var T:TTimes;
begin Result:=Schedule(Kind,Beats,Start,Goal,Section,RoofRouteIndex,T);end;

function MakeTrapGimmick(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal,Duration:Double;
  Origin:TTrapPoint;Section:Integer;out G:TTrapGimmick;RoofRouteIndex:Integer):Boolean;
var T:TTimes;Moves:TList<TTrapMove>;Floors,Roofs:TList<TTrapPlatform>;Traps:TList<TTrapObstacle>;
  P:TTrapPoint;Cursor,X,Y,Top,Side,Pocket,ExitX,PitY:Double;M:TTrapMove;F:TTrapPlatform;Q:TTrapObstacle;
  procedure Move(UntilTime,TargetX,TargetY:Double;Motion:TTrapMotion;Arc:Double=0;Cue:Double=-1;
    EndSynced:Boolean=True;StartSynced:Boolean=True);
  begin
    M:=Default(TTrapMove);M.Start:=Cursor;M.Finish:=UntilTime;M.Cue:=UntilTime;
    M.Origin:=P;M.Target:=TrapPoint(TargetX,TargetY);M.Kind:=Motion;M.Arc:=Arc;
    M.Pattern:=30;M.Section:=Section;M.Avoidance:=Kind;M.Landing:=True;
    M.CueSynced:=EndSynced;M.LandSynced:=EndSynced;
    if Motion=tmStop then begin M.Cue:=Cursor;M.CueSynced:=StartSynced;end;
    if Cue>=0 then begin M.Cue:=Cue;M.CueSynced:=True;end;
    Moves.Add(M);P:=M.Target;Cursor:=UntilTime;
  end;
  procedure Floor(A,B,Height:Double;Motion:TTrapPlatformMotion=pmStatic;
    Reveal:Double=0;Trigger:Double=0;Settle:Double=0;DX:Double=0;DY:Double=0);
  begin
    F:=Default(TTrapPlatform);F.Left:=A;F.Right:=B;F.Y:=Height;F.EndY:=Height;
    F.Move:=-1;F.Finish:=Duration;F.Kind:=tkMoving;F.Motion:=Motion;
    F.Reveal:=Reveal;F.Trigger:=Trigger;F.Settle:=Settle;F.DX:=DX;F.DY:=DY;
    if Motion=pmDrop then F.Kind:=tkCrumble;
    if Motion=pmReveal then F.Kind:=tkBridge;
    Floors.Add(F);
  end;
  procedure Wall(InitialCenter,Direction,Distance,Height:Double);
  begin
    Q:=Default(TTrapObstacle);Q.Kind:=tkWall;Q.Move:=1;Q.X:=InitialCenter;Q.Y:=PitY;
    Q.W:=0.60;Q.H:=Height;Q.Power:=Direction;Q.Travel:=Distance;
    // くぼみに入った着地で作動する。待機・復帰後も同じ実体を残す。
    Q.Reveal:=0;Q.Fire:=T[1];Q.Cue:=T[2];Q.Finish:=T[3];Q.Synced:=True;
    Traps.Add(Q);
  end;
  procedure CrushArea;
  begin
    PitY:=Y-0.80;ExitX:=X+8.4;
    Floor(X-3.5,X+0.5,Y);Floor(X+0.5,X+6.8,PitY);Floor(X+6.8,X+9.0,Y);
  end;
  // 新しい機械も元の音をCueへ保存する。寸法・方向・経路は描画と接触判定で共用する。
  procedure Hazard(Shape:TTrapKind;MoveIndex:Integer;AtX,Width,Height,FireTime,CueTime,EndTime:Double;
    Distance:Double=0;Direction:Double=0;AtY:Double=1E9);
  begin
    Q:=Default(TTrapObstacle);Q.Kind:=Shape;Q.Move:=MoveIndex;Q.X:=AtX;Q.Y:=Y;
    if AtY<1E8 then Q.Y:=AtY;
    Q.W:=Width;Q.H:=Height;Q.Fire:=FireTime;Q.Cue:=CueTime;Q.Finish:=EndTime;
    Q.Travel:=Distance;Q.Power:=Direction;Q.Synced:=True;Traps.Add(Q);
  end;
  procedure Ceiling(A,B,Height:Double);
  var R:TTrapPlatform;
  begin
    R:=Default(TTrapPlatform);R.Left:=A;R.Right:=B;R.Y:=Height;R.EndY:=Height;
    R.Move:=-1;R.Finish:=Duration;R.Kind:=tkCeiling;Roofs.Add(R);
  end;
  procedure SideSpears;
  begin
    Floor(X-3.5,X+8.8,Y);
    Hazard(tkSpearMount,0,X+1.4,0.32,0.72,T[0],T[1],Duration);
    Hazard(tkSpearMount,0,X+6.7,0.32,0.72,T[0],T[1],Duration);
    Hazard(tkSideSpear,0,X+1.4,2.65,0.22,T[0],T[1],T[2]-0.14,0,1,Y+0.40);
    Hazard(tkSideSpear,2,X+6.7,2.65,0.22,T[3],T[4],T[5]-0.14,0,-1,Y+0.40);
    Move(T[2],X,Y,tmStop);Move(T[3],X+3.5,Y,tmJump,1.30);
    Move(T[5],P.X,Y,tmStop);Move(T[6],X+8.0,Y,tmJump,1.50);
  end;
  procedure AlternatingPresses;
  var I:Integer;
  begin
    Floor(X-3.5,X+10.6,Y);Ceiling(X+1.7,X+8.7,Y+4.4);
    for I:=0 to 2 do begin
      Hazard(tkPress,I*2,X+2.4+I*2.8,1.10,1.60,T[I*3],T[I*3+1],T[I*3+2]-0.14,2.8);
      Move(T[I*3+2],P.X,Y,tmStop);Move(T[I*3+3],X+3.8+I*2.8,Y,tmRun);
    end;
  end;
  procedure FlipPit;
  var I:Integer;
  begin
    Floor(X-3.5,X+1.0,Y);Floor(X+1.0,X+4.0,Y-TrapSpikePitDepth);
    // 跳躍の長さに合わせて回転させ、疎らな音でも板が身体へ追い付かないようにする。
    Floor(X+1.0,X+4.0,Y,pmHinge,0,T[1]+(T[2]-T[1])*0.10,T[1]+(T[2]-T[1])*0.90);
    Floor(X+4.0,X+6.8,Y);
    for I:=0 to 4 do Hazard(tkSpikes,1,X+1.35+I*0.57,0.55,0.30,T[0],T[1],Duration);
    Move(T[1],X+3.3,Y,tmJump,1.10);Move(T[2],X+6.0,Y,tmJump,1.25);
  end;
  procedure CeilingLift;
  var Cycle,Index:Integer;
    procedure LiftStage(First,Last:Double;Beat:Integer;Hold:Boolean);
    begin
      Floor(X+1.3,X+10.5,Y,pmNeedleLift,0,T[Beat],T[Beat+1],Ord(Hold),TrapNeedleLiftHeight);
      F.Start:=First;F.Finish:=Last;F.Release:=T[Beat+2];F.Recover:=T[Beat+3];Floors[Floors.Count-1]:=F;
    end;
    procedure Needles(A,B:Double;MoveIndex,Beat:Integer);
    begin
      Ceiling(X+A,X+B,Y+2.7);
      Hazard(tkCeilingNeedles,MoveIndex,X+(A+B)*0.5,B-A,0.70,T[0],T[Beat],Duration,0,0,Y+2.0);
    end;
  begin
    Floor(X-3.5,X+1.3,Y);Floor(X+10.5,X+12.3,Y+TrapNeedleLiftExit);Floor(X+12.3,X+14.8,Y);
    // 同じ幅の床を行程の境界で切り替え、上下する曲線も各実音へ保存する。
    LiftStage(0,T[4],1,False);LiftStage(T[4],T[8],5,False);
    LiftStage(T[8],T[12],9,False);LiftStage(T[12],Duration,13,True);
    Needles(0.90,1.75,1,2);Ceiling(X+1.75,X+3.05,Y+4.7);
    Needles(3.05,4.45,5,6);Ceiling(X+4.45,X+5.75,Y+4.7);
    Needles(5.75,7.15,9,10);Ceiling(X+7.15,X+8.45,Y+4.7);
    Needles(8.45,9.10,13,14);Ceiling(X+9.10,X+12.3,Y+5.3);
    Move(T[1],X+2.4,Y,tmJump,0.60);
    for Cycle:=0 to 2 do begin
      Index:=Cycle*4;
      Move(T[Index+2],P.X,Y+TrapNeedleLiftHeight,tmRide);
      Move(T[Index+3],P.X,P.Y,tmStop);
      Move(T[Index+4],P.X,Y,tmRide);
      Pocket:=X+5.1+Cycle*2.7;if Cycle=2 then Pocket:=X+9.7;
      Move(T[Index+5],Pocket,Y,tmRun);
    end;
    // 最後は頭上に針がない区間で持ち上げてもらい、高い出口へ跳び移る。
    Move(T[14],P.X,Y+TrapNeedleLiftHeight,tmRide);
    Move(T[15],X+11.5,Y+TrapNeedleLiftExit,tmJump,1.15);
    Move(T[16],X+14.0,Y,tmJump,1.25);
  end;
  procedure ClosingDoors;
  var I:Integer;Gap:Double;
  begin
    Floor(X-3.5,X+10.0,Y);Ceiling(X+1.1,X+8.1,Y+5.2);
    for I:=0 to 2 do begin
      Gap:=T[I+1]-T[I];
      Hazard(tkClosingDoor,I,X+1.5+I*3.1,0.52,2.40,T[I]+Gap*0.42,T[I+1],Duration,2.8);
      Move(T[I+1],X+3.0+I*3.1,Y,tmRun);
    end;
  end;
  procedure FireChase;
  begin
    Floor(X-3.5,X+10.2,Y);
    Hazard(tkFireJet,0,X+2.2,0.65,2.10,T[0],T[1],T[2]-0.14);
    Hazard(tkFireJet,2,X+5.0,0.65,2.10,T[3],T[4],T[5]-0.14);
    Hazard(tkFireJet,4,X+7.1,1.30,2.10,T[7]-0.08,T[7],T[8]-0.14);
    Q.Reveal:=T[6];Traps[Traps.Count-1]:=Q;
    Move(T[2],X,Y,tmStop);Move(T[3],X+3.6,Y,tmRun);
    Move(T[5],P.X,Y,tmStop);Move(T[6],X+6.4,Y,tmRun);
    Move(T[7],X+5.9,Y,tmRun);Move(T[8],P.X,Y,tmStop);Move(T[9],X+9.4,Y,tmRun);
  end;
  procedure RoofCascade;
  const Heights:array[0..5] of Double=(0.30,-0.35,0.50,-0.15,0.35,-0.35);
  var Recipe:TRoofRecipe;Route:TRoofRoute;SafeIndex,Cell,Slot,Pre,N:Integer;
    A,B,C,Height,BedY,RaisedY,ReleaseTime,RecoverTime:Double;Safe:Boolean;
    procedure Piece(Left,Right,ClosedY:Double);
    var R:TTrapPlatform;
    begin
      R:=Default(TTrapPlatform);R.Left:=Left;R.Right:=Right;R.Y:=ClosedY+3.2;R.EndY:=R.Y;
      R.Move:=-1;R.Kind:=tkCeiling;R.Finish:=Duration;R.Motion:=pmRoofDrop;R.DY:=3.2;R.DX:=TrapRoofBedRise;
      R.Trigger:=T[Pre];R.Settle:=T[9];R.Release:=T[9]+Recipe.Hold;R.Recover:=R.Release+Recipe.ReturnTime;
      Roofs.Add(R);
    end;
  begin
    Recipe:=RoofRecipe(Kind);Route:=RoofRoute(Section,RoofRouteIndex);SafeIndex:=Route.SafeIndex;Pre:=Route.Pre;
    BedY:=Y-TrapRoofBedLowering;RaisedY:=BedY+TrapRoofBedRise;
    ReleaseTime:=T[9]+Recipe.Hold;RecoverTime:=ReleaseTime+Recipe.ReturnTime;
    Floor(X-3.5,X+0.75,Y);
    for Cell:=0 to 5 do begin
      A:=X+0.75+Cell*1.6;B:=A+1.6;C:=(A+B)*0.5;Height:=BedY+Heights[Cell];
      Floor(A,B,Height,pmRoofRise,0,ReleaseTime,RecoverTime,0,TrapRoofBedRise);Slot:=Cell div 2;
      Safe:=Odd(Cell) and ((Recipe.Slots=3) or ((Recipe.Slots=2) and (Slot<>(SafeIndex+2) mod 3)) or (Slot=SafeIndex));
      if Safe then begin
        Piece(A,C-Recipe.Width*0.5,Height+0.10);
        Piece(C-Recipe.Width*0.5,C+Recipe.Width*0.5,Height+Recipe.Headroom);
        Piece(C+Recipe.Width*0.5,B,Height+0.10);
      end else Piece(A,B,Height+0.10);
    end;
    // 高い出口は初めから実体として置く。くぼみのどの段からも先に飛び出せない。
    Floor(X+10.35,X+12.3,Y+TrapRoofExitHeight);Floor(X+12.3,X+14.8,Y);
    for N:=0 to SafeIndex do Move(T[N+1],X+1.55+N*3.2,BedY+Heights[N*2],tmJump,1.05);
    // 隙間を通り過ぎて戻る、先へ進む、その場で天井を待つ入口を使い分ける。
    if Route.Entry=reRetreat then
      Move(T[Pre],X+1.55+(SafeIndex+1)*3.2,BedY+Heights[(SafeIndex+1)*2],tmJump,1.05)
    else if Route.Entry=reWait then
      Move(T[Pre],X+3.15+SafeIndex*3.2,BedY+Heights[SafeIndex*2+1],tmJump,0.90);
    if Route.Entry=reWait then Move(T[Pre+1],P.X,P.Y,tmStop)
    else Move(T[Pre+1],X+3.15+SafeIndex*3.2,BedY+Heights[SafeIndex*2+1],tmJump,0.90);
    Move(ReleaseTime,P.X,P.Y,tmStop,0,-1,False);
    // 復帰の間も身体を床と同じ曲線で運び、天井との相対的な隙間を広げる。
    Move(RecoverTime,P.X,P.Y+TrapRoofBedRise,tmRide,0,-1,False);
    Move(T[Pre+2],P.X,P.Y,tmStop,0,-1,True,False);N:=Pre+3;Cell:=(SafeIndex+1)*2;
    while Cell<=4 do begin Move(T[N],X+1.55+Cell*1.6,RaisedY+Heights[Cell],tmJump,1.10);Inc(N);Inc(Cell,2);end;
    Move(T[N],X+11.5,Y+TrapRoofExitHeight,tmJump,1.10);
    Move(T[N+1],X+14.0,Y,tmJump,1.05);
  end;
begin
  G:=Default(TTrapGimmick);Result:=Schedule(Kind,Beats,Start,Goal,Section,RoofRouteIndex,T);if not Result then Exit;
  Moves:=TList<TTrapMove>.Create;Floors:=TList<TTrapPlatform>.Create;Traps:=TList<TTrapObstacle>.Create;
  Roofs:=TList<TTrapPlatform>.Create;
  try
    P:=Origin;Cursor:=Start;X:=P.X;Y:=P.Y;
    case Kind of
      taSideSpears:SideSpears;
      taAlternatingPresses:AlternatingPresses;
      taFlipPit:FlipPit;
      taCeilingLift:CeilingLift;
      taClosingDoors:ClosingDoors;
      taFireChase:FireChase;
      taRoofShelters,taRoofNarrow,taRoofLastGap:RoofCascade;
      taCrushSlot,taCrushReverse:begin
        CrushArea;
        if Kind=taCrushSlot then begin
          Pocket:=X+6.37;Wall(X+1.0,1,4.64,1.45);
          Move(T[1],X+2.3,PitY,tmJump,1.85);
          Move(T[2],Pocket,PitY,tmRun);Move(T[3],Pocket,PitY,tmStop);
          Move(T[4],ExitX,Y,tmVault,1.35);
        end else begin
          Pocket:=X+0.93;Wall(X+6.1,-1,4.44,1.45);
          Move(T[1],X+4.5,PitY,tmJump,1.10);
          Move(T[2],Pocket,PitY,tmRun);Move(T[3],Pocket,PitY,tmStop);
          Move(T[4],X+4.5,PitY,tmRun);Move(T[5],ExitX,Y,tmJump,1.85);
        end;
      end;
      taCrushHop:begin
        CrushArea;Wall(X+6.1,-1,4.44,0.80);
        Move(T[1],X+2.3,PitY,tmJump,1.10);
        Move(T[2],X+5.2,PitY,tmJump,1.45);Move(T[3],ExitX,Y,tmJump,1.35);
      end;
      taCrushFeint:begin
        CrushArea;Wall(X+6.1,-1,3.07,1.45);
        Move(T[1],X+2.3,PitY,tmJump,1.10);
        Move(T[2],X+2.3,PitY,tmStop);Move(T[3],X+2.3,PitY,tmStop);
        Move(T[4],X+4.5,PitY,tmRun);Move(T[5],ExitX,Y,tmJump,1.85);
      end;
      taHiddenStairs,taHiddenSwitchback:begin
        Side:=-1;if Kind=taHiddenSwitchback then Side:=1;
        Floor(X-3.1,X+3.1,Y);Top:=Y+0.55+TrapStandingHeight+TrapPlatformThickness;
        Floor(X-0.55,X+0.55,Top,pmReveal,T[1]);
        Floor(X+2.0,X+3.2,Top+0.45,pmReveal,T[4]);
        // 頭上接触は実音に一致。衝突後はすぐ落ち、接地後に次の動作へ備える。
        Move(T[1]-0.20,X,Y,tmStop,0,-1,False);
        Move(T[1]+0.16,X,Y,tmHeadBump,0.55,T[1],False);
        Move(T[2],X,Y,tmStop,0,-1,False,False);
        Move(T[3],X+Side*2.4,Y,tmRun);
        Move(T[4],X,Top,tmJump,1.0);Move(T[5],X+2.6,Top+0.45,tmJump,1.05);
        Floor(X+4.6,X+5.8,Y+1.3,pmHorizontal,0,T[6],T[7],0.8,0);
        Move(T[6],X+5.2,Y+1.3,tmJump,1.05);Move(T[7],X+6.0,Y+1.3,tmRide);
        Floor(X+7.9,X+9.1,Y+0.55,pmVertical,0,T[8],T[9],0,-0.55);
        Move(T[8],X+8.5,Y+0.55,tmJump,1.0);Move(T[9],X+8.5,Y,tmRide);
        Move(T[10],X+11.0,Y,tmJump,1.0);Floor(P.X-0.8,P.X+0.65,Y);
      end;
      taMovingDescentX,taMovingDescentY:begin
        Floor(X-0.65,X+0.75,Y);Floor(X+1.9,X+3.1,Y+0.9,pmReveal);
        Move(T[1],X+2.5,Y+0.9,tmJump,1.0);
        if Kind=taMovingDescentX then begin
          Floor(X+4.4,X+5.6,Y+0.25,pmHorizontal,0,T[2],T[3],0.8,0);
          Move(T[2],X+5.0,Y+0.25,tmJump,1.0);Move(T[3],X+5.8,Y+0.25,tmRide);
        end else begin
          Floor(X+4.4,X+5.6,Y+0.55,pmVertical,0,T[2],T[3],0,-0.55);
          Move(T[2],X+5.0,Y+0.55,tmJump,1.0);Move(T[3],X+5.0,Y,tmRide);
        end;
        Move(T[4],P.X+2.5,Y,tmJump,1.0);Floor(P.X-0.8,P.X+0.65,Y);
      end;
    end;
    G.Moves:=Moves.ToArray;G.Floors:=Floors.ToArray;G.Roofs:=Roofs.ToArray;G.Traps:=Traps.ToArray;
  finally Roofs.Free;Traps.Free;Floors.Free;Moves.Free;end;
end;
end.
