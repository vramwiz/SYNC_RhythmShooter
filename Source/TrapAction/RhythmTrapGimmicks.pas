unit RhythmTrapGimmicks;
// 狭い退避場所・隠し階段・可動足場の連鎖を、保存可能な絶対時刻の動作と地形へ組み立てる。
interface
uses RhythmTrapPlan;
type
  TTrapGimmick=record
    Moves:TArray<TTrapMove>;
    Floors:TArray<TTrapPlatform>;
    Roofs:TArray<TTrapPlatform>;
    Traps:TArray<TTrapObstacle>;
  end;
function IsTrapGimmick(Kind:TTrapAvoidance):Boolean;
function TrapGimmickFits(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal:Double;Section:Integer=0):Boolean;
function MakeTrapGimmick(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal,Duration:Double;
  Origin:TTrapPoint;Section:Integer;out G:TTrapGimmick):Boolean;
implementation
uses System.Math,System.Generics.Collections;
type TTimes=array[0..10] of Double;
  TRoofRecipe=record
    Slots:Integer;
    Width,Headroom,FallMin,FallMax,Hold,ReturnTime:Double;
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

function Schedule(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal:Double;Section:Integer;out T:TTimes):Boolean;
var N,Pre:Integer;Recipe:TRoofRecipe;
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
    taRoofShelters,taRoofNarrow,taRoofLastGap:begin
      Recipe:=RoofRecipe(Kind);Pre:=Section mod 3+1;
      if not Next(1,0.40,0.90) then Exit;
      for N:=2 to Pre do if not Next(N,0.50,1.10) then Exit;
      if not Next(Pre+1,0.40,0.65) or
        not Find(T[Pre],Recipe.FallMin,Recipe.FallMax,T[9]) then Exit;
      if not Next(Pre+2,T[9]+Recipe.Hold+Recipe.ReturnTime+0.12-T[Pre+1],5.0) then Exit;
      for N:=Pre+3 to 6 do if not Next(N,0.55,1.10) then Exit;
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

function TrapGimmickFits(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal:Double;Section:Integer):Boolean;
var T:TTimes;
begin Result:=Schedule(Kind,Beats,Start,Goal,Section,T);end;

function MakeTrapGimmick(Kind:TTrapAvoidance;const Beats:TArray<Double>;Start,Goal,Duration:Double;
  Origin:TTrapPoint;Section:Integer;out G:TTrapGimmick):Boolean;
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
  procedure RoofCascade;
  const Heights:array[0..5] of Double=(0.30,-0.35,0.50,-0.15,0.35,-0.35);
  var Recipe:TRoofRecipe;SafeIndex,Cell,Slot,Pre,N:Integer;A,B,C,Height:Double;Safe:Boolean;
    procedure Piece(Left,Right,ClosedY:Double);
    var R:TTrapPlatform;
    begin
      R:=Default(TTrapPlatform);R.Left:=Left;R.Right:=Right;R.Y:=ClosedY+3.2;R.EndY:=R.Y;
      R.Move:=-1;R.Kind:=tkCeiling;R.Finish:=Duration;R.Motion:=pmRoofDrop;R.DY:=3.2;
      R.Trigger:=T[Pre];R.Settle:=T[9];R.Release:=T[9]+Recipe.Hold;R.Recover:=R.Release+Recipe.ReturnTime;
      Roofs.Add(R);
    end;
  begin
    Recipe:=RoofRecipe(Kind);SafeIndex:=Section mod 3;Pre:=SafeIndex+1;
    Floor(X-3.5,X+0.75,Y);
    for Cell:=0 to 5 do begin
      A:=X+0.75+Cell*1.6;B:=A+1.6;C:=(A+B)*0.5;Height:=Y+Heights[Cell];
      Floor(A,B,Height);Slot:=Cell div 2;
      Safe:=Odd(Cell) and ((Recipe.Slots=3) or ((Recipe.Slots=2) and (Slot<>(SafeIndex+2) mod 3)) or (Slot=SafeIndex));
      if Safe then begin
        Piece(A,C-Recipe.Width*0.5,Height+0.10);
        Piece(C-Recipe.Width*0.5,C+Recipe.Width*0.5,Height+Recipe.Headroom);
        Piece(C+Recipe.Width*0.5,B,Height+0.10);
      end else Piece(A,B,Height+0.10);
    end;
    Floor(X+10.35,X+12.3,Y);
    for N:=0 to SafeIndex do Move(T[N+1],X+1.55+N*3.2,Y+Heights[N*2],tmJump,1.05);
    Move(T[Pre+1],X+3.15+SafeIndex*3.2,Y+Heights[SafeIndex*2+1],tmJump,0.90);
    Move(T[Pre+2],P.X,P.Y,tmStop);N:=Pre+3;Cell:=(SafeIndex+1)*2;
    while Cell<=4 do begin Move(T[N],X+1.55+Cell*1.6,Y+Heights[Cell],tmJump,1.10);Inc(N);Inc(Cell,2);end;
    Move(T[N],X+11.5,Y,tmJump,1.05);
  end;
begin
  G:=Default(TTrapGimmick);Result:=Schedule(Kind,Beats,Start,Goal,Section,T);if not Result then Exit;
  Moves:=TList<TTrapMove>.Create;Floors:=TList<TTrapPlatform>.Create;Traps:=TList<TTrapObstacle>.Create;
  Roofs:=TList<TTrapPlatform>.Create;
  try
    P:=Origin;Cursor:=Start;X:=P.X;Y:=P.Y;
    case Kind of
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
