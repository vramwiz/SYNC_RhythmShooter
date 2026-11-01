unit RhythmBreakoutAction;
// Persisted, independently checked action overlays on the accepted reverse score.
interface
uses System.SysUtils,System.JSON,RhythmAudio,RhythmBreakoutGeometry;
type
  TActionNode=record Time,Speed:Double;P:TBreakPoint;Kind,Source,Brick,Core,Room:Integer;end;
  TActionBrick=record R:TBreakBlock;Base,Row,Axis,Cause:Integer;Born:Double;end;
  TActionKey=record Time,Value:Double;end;
  TActionRoom=record First,Last:Double;end;
  TActionCharge=record First,Last,Radius:Double;Source:Integer;end;
  TActionBall=record Launch,Hit,Catch:Double;A,B,C:TBreakPoint;Target:Integer;end;
  TBreakActionPlan=class
  private
    FCoreNodes,FNodes:TArray<TActionNode>;FCoreBricks,FBricks:TArray<TActionBrick>;
    FEvents:TArray<TActionNode>;FShifts,FPaddles:TArray<TActionKey>;
    FRooms:TArray<TActionRoom>;FCharges:TArray<TActionCharge>;FExtra:TArray<TActionBall>;
    FContactY,FLaunch,FGoal,FEnd,FBallEnd,FPaddleHalf:Double;
    procedure ReadCore(Data:TJSONObject);
    procedure Reindex;
    procedure MakeRooms(const Cancel:TFunc<Boolean>);
    procedure MakeCharges(const Cancel:TFunc<Boolean>);
    procedure MakeFinishers(const Cancel:TFunc<Boolean>);
    function GetCount:Integer;function GetExtraCount:Integer;function GetRoomCount:Integer;
    function EventIndex(Source:Integer):Integer;
    function RadiusBound(First,Last:Double):Double;
    function FirstTouch(const B:TActionBrick;First,Last:Double;out Hit:Double):Boolean;
    function ClearsMain(const B:TActionBrick;UntilTime:Double):Boolean;
    function ClearsBall(const Ball:TActionBall;const B:TActionBrick;Own:Boolean):Boolean;
  public
    class function Build(Core:TJSONObject;ClearWave:Boolean;const Cancel:TFunc<Boolean>):TBreakActionPlan;static;
    class function Load(Data:TJSONObject):TBreakActionPlan;static;
    function ExportData(Core:TJSONObject;Audio:TRhythmAudio):TJSONObject;
    procedure Verify(const Cancel:TFunc<Boolean> = nil);
    function PositionAt(Time:Double):TBreakPoint;
    function RadiusAt(Time:Double):Double;
    function BrickAt(Index:Integer;Time:Double):TBreakBlock;
    function BrickRow(Index:Integer):Integer;
    function BrickVisible(Index:Integer;Time:Double):Boolean;
    function ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
    function ExtraLaunch(Index:Integer):Double;
    function SyncCount:Integer;function AuxiliaryCount:Integer;
    property Count:Integer read GetCount;property ExtraCount:Integer read GetExtraCount;
    property RoomCount:Integer read GetRoomCount;
  end;
implementation
uses System.Math,System.Generics.Collections;
type TControls=array[0..3] of TBreakPoint;
function Finite(V:Double):Boolean;begin Result:=not IsNan(V) and not IsInfinite(V);end;
function Mix(const A,B:TBreakPoint;U:Double):TBreakPoint;begin Result:=BreakPoint(A.X+(B.X-A.X)*U,A.Y+(B.Y-A.Y)*U);end;
function Dist(const A,B:TBreakPoint):Double;begin Result:=Hypot(B.X-A.X,B.Y-A.Y);end;
function KeyAt(const K:TArray<TActionKey>;Time:Double):Double;
var A,B,M:Integer;U:Double;
begin Result:=0;if Length(K)=0 then Exit;A:=0;B:=Length(K);while A<B do begin M:=(A+B) div 2;if K[M].Time<=Time then A:=M+1 else B:=M;end;A:=Max(0,A-1);Result:=K[A].Value;
  if A<High(K) then begin U:=EnsureRange((Time-K[A].Time)/(K[A+1].Time-K[A].Time),0.0,1.0);Result:=Result+(K[A+1].Value-Result)*U*U*(3-2*U);end;
end;
function Controls(const A,B:TActionNode):TControls;
var D,L,T:Double;
begin Result[0]:=A.P;Result[3]:=B.P;L:=Dist(A.P,B.P);if L<1E-10 then begin Result[1]:=A.P;Result[2]:=B.P;Exit;end;
  D:=B.Time-A.Time;T:=D/(3*L);Result[1]:=BreakPoint(A.P.X+(B.P.X-A.P.X)*A.Speed*T,A.P.Y+(B.P.Y-A.P.Y)*A.Speed*T);
  Result[2]:=BreakPoint(B.P.X-(B.P.X-A.P.X)*B.Speed*T,B.P.Y-(B.P.Y-A.P.Y)*B.Speed*T);
end;
function CurveAt(const C:TControls;U:Double):TBreakPoint;
var V:Double;begin U:=EnsureRange(U,0.0,1.0);V:=1-U;Result:=BreakPoint(C[0].X*V*V*V+3*C[1].X*V*V*U+3*C[2].X*V*U*U+C[3].X*U*U*U,C[0].Y*V*V*V+3*C[1].Y*V*V*U+3*C[2].Y*V*U*U+C[3].Y*U*U*U);end;
procedure Split(const C:TControls;U:Double;out L,R:TControls);
var A,B,D,E,F,P:TBreakPoint;
begin A:=Mix(C[0],C[1],U);B:=Mix(C[1],C[2],U);D:=Mix(C[2],C[3],U);E:=Mix(A,B,U);F:=Mix(B,D,U);P:=Mix(E,F,U);L[0]:=C[0];L[1]:=A;L[2]:=E;L[3]:=P;R[0]:=P;R[1]:=F;R[2]:=D;R[3]:=C[3];end;
function Clip(const C:TControls;Lo,Hi:Double):TControls;
var L,R:TControls;
begin Result:=C;if Hi<1 then begin Split(Result,Hi,L,R);Result:=L;end;if Lo>0 then begin Split(Result,Lo/Max(Hi,1E-12),L,R);Result:=R;end;end;
function PointRect(const P:TBreakPoint;const B:TBreakBlock):Double;
begin Result:=Hypot(Max(0.0,Max(B.Left-P.X,P.X-B.Right)),Max(0.0,Max(B.Top-P.Y,P.Y-B.Bottom)));end;
function ClearCurve(const C:TControls;const B:TBreakBlock;Radius:Double;Depth:Integer=0):Boolean;
var I:Integer;LX,RX,TY,BY,DX,DY:Double;L,R:TControls;
begin LX:=C[0].X;RX:=LX;TY:=C[0].Y;BY:=TY;for I:=1 to 3 do begin LX:=Min(LX,C[I].X);RX:=Max(RX,C[I].X);TY:=Min(TY,C[I].Y);BY:=Max(BY,C[I].Y);end;
  DX:=Max(0.0,Max(B.Left-RX,LX-B.Right));DY:=Max(0.0,Max(B.Top-BY,TY-B.Bottom));if Hypot(DX,DY)>Radius+1E-8 then Exit(True);
  if Depth>=16 then Exit(False);Split(C,0.5,L,R);Result:=ClearCurve(L,B,Radius,Depth+1) and ClearCurve(R,B,Radius,Depth+1);
end;
function OnPlane(const C:TControls;const B:TBreakBlock;Axis:Integer;Radius:Double):Boolean;
var I:Integer;begin Result:=True;for I:=0 to 3 do case Axis of
  1:Result:=Result and (C[I].X<=B.Left-Radius+1E-8);-1:Result:=Result and (C[I].X>=B.Right+Radius-1E-8);
  2:Result:=Result and (C[I].Y<=B.Top-Radius+1E-8);-2:Result:=Result and (C[I].Y>=B.Bottom+Radius-1E-8);
  else Result:=False;end;end;
procedure TBreakActionPlan.ReadCore(Data:TJSONObject);
var A:TJSONArray;J:TJSONObject;I:Integer;B:TActionBrick;
  procedure Keys(const Name:string;out Dest:TArray<TActionKey>);
  var K:Integer;V:TJSONObject;Items:TJSONArray;
  begin Items:=Data.GetValue<TJSONArray>(Name);SetLength(Dest,Items.Count);for K:=0 to Items.Count-1 do begin V:=Items.Items[K] as TJSONObject;Dest[K].Time:=V.GetValue<Double>('time');Dest[K].Value:=V.GetValue<Double>('value');end;end;
begin
  if Data.GetValue<string>('layout','')<>'score-grid' then raise Exception.Create('Rush core layout');
  FContactY:=Data.GetValue<Double>('contactY');FLaunch:=Data.GetValue<Double>('launch');FGoal:=Data.GetValue<Double>('goal');FEnd:=Data.GetValue<Double>('end');FBallEnd:=Data.GetValue<Double>('ballEnd');FPaddleHalf:=Data.GetValue<Double>('paddleHalf');
  A:=Data.GetValue<TJSONArray>('events');SetLength(FEvents,A.Count);for I:=0 to A.Count-1 do begin J:=A.Items[I] as TJSONObject;FEvents[I]:=Default(TActionNode);FEvents[I].Time:=J.GetValue<Double>('time');FEvents[I].Speed:=J.GetValue<Double>('strength');FEvents[I].Source:=J.GetValue<Integer>('source');end;
  A:=Data.GetValue<TJSONArray>('nodes');SetLength(FCoreNodes,A.Count);for I:=0 to A.Count-1 do begin J:=A.Items[I] as TJSONObject;FCoreNodes[I]:=Default(TActionNode);FCoreNodes[I].Time:=J.GetValue<Double>('time');FCoreNodes[I].Speed:=J.GetValue<Double>('speed');FCoreNodes[I].P:=BreakPoint(J.GetValue<Double>('x'),J.GetValue<Double>('y'));FCoreNodes[I].Kind:=J.GetValue<Integer>('kind');FCoreNodes[I].Source:=J.GetValue<Integer>('source');FCoreNodes[I].Brick:=J.GetValue<Integer>('brick');FCoreNodes[I].Core:=I;FCoreNodes[I].Room:=-1;end;
  A:=Data.GetValue<TJSONArray>('bricks');SetLength(FCoreBricks,A.Count);for I:=0 to A.Count-1 do begin J:=A.Items[I] as TJSONObject;B:=Default(TActionBrick);B.Base:=I;B.Row:=J.GetValue<Integer>('row');B.Axis:=-2;B.R.Source:=J.GetValue<Integer>('source');B.R.Time:=J.GetValue<Double>('time');B.R.Strength:=J.GetValue<Double>('strength');B.R.Left:=0.15+0.144*J.GetValue<Integer>('col')-0.063;B.R.Right:=B.R.Left+0.126;B.R.Bottom:=FContactY-BREAK_RADIUS-B.Row*0.041;B.R.Top:=B.R.Bottom-0.028;FCoreBricks[I]:=B;end;
  Keys('shifts',FShifts);Keys('paddles',FPaddles);FNodes:=Copy(FCoreNodes);FBricks:=Copy(FCoreBricks);
end;
class function TBreakActionPlan.Build(Core:TJSONObject;ClearWave:Boolean;const Cancel:TFunc<Boolean>):TBreakActionPlan;
begin Result:=TBreakActionPlan.Create;try Result.ReadCore(Core);Result.MakeRooms(Cancel);Result.MakeCharges(Cancel);if ClearWave then Result.MakeFinishers(Cancel);Result.Reindex;Result.Verify(Cancel);except Result.Free;raise;end;end;
procedure TBreakActionPlan.Reindex;
var I,J,K:Integer;B:TActionBrick;Targets:TArray<TBreakBlock>;Indices:TDictionary<Integer,Integer>;
begin
  SetLength(Targets,Length(FExtra));for I:=0 to High(FExtra) do Targets[I]:=FBricks[FExtra[I].Target].R;
  // Stable insertion order is sufficient for the bounded added formations.
  for I:=1 to High(FBricks) do begin B:=FBricks[I];J:=I-1;while (J>=0) and (FBricks[J].R.Time>B.R.Time) do begin FBricks[J+1]:=FBricks[J];Dec(J);end;FBricks[J+1]:=B;end;
  Indices:=TDictionary<Integer,Integer>.Create;try
    for I:=0 to High(FBricks) do if FBricks[I].R.Source>=0 then Indices.Add(FBricks[I].R.Source,I);
    for I:=0 to High(FNodes) do if FNodes[I].Kind=0 then begin if not Indices.TryGetValue(FNodes[I].Source,K) then K:=-1;FNodes[I].Brick:=K;end;
  finally Indices.Free;end;
  for I:=0 to High(FExtra) do for J:=0 to High(FBricks) do if (FBricks[J].Cause=I+1) and (FBricks[J].R.Time=Targets[I].Time) then begin FExtra[I].Target:=J;Break;end;
end;
procedure TBreakActionPlan.MakeRooms(const Cancel:TFunc<Boolean>);
var A,B,I,J,N,Peak,PairA,PairB,HIndex,KIndex,SignIndex,Room,Original,EventFirst,EventLast,M:Integer;
  StartNode,EndNode,Node:TActionNode;Times:TArray<Double>;Sources:TArray<Integer>;DX,DY,SX,Velocity:TArray<Double>;
  Picks:TList<TActionNode>;Path,NewNodes:TArray<TActionNode>;Bricks:TArray<TActionBrick>;Brick:TActionBrick;C:TControls;Group:TActionRoom;
  Height,Ratio,Side,Sum,Wanted,Delta,X,Y,V,Average,U,LastRoom,Lo:Double;Good,Found:Boolean;
  Heights:array[0..3] of Double;Ratios:array[0..7] of Double;
  procedure AddPick(const E:TActionNode);
  var Z:Integer;
  begin for Z:=0 to Picks.Count-1 do if Abs(Picks[Z].Time-E.Time)<0.065 then Exit;Picks.Add(E);end;
begin
  Heights[0]:=0.16;Heights[1]:=0.20;Heights[2]:=0.24;Heights[3]:=0.27;
  Ratios[0]:=0.7;Ratios[1]:=1;Ratios[2]:=1.5;Ratios[3]:=2;Ratios[4]:=2.5;Ratios[5]:=3;Ratios[6]:=4;Ratios[7]:=5;
  Picks:=TList<TActionNode>.Create;
  try LastRoom:=-10;A:=0;
    while A<Length(FNodes)-2 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      if (Length(FRooms)>=1000) or (Length(FNodes)>30000) or (Length(FBricks)>11000) then Break;
      if (FNodes[A].Kind<>2) or (FNodes[A].Time<LastRoom+3.5) or (FNodes[A].Time>FGoal-3.5) then begin Inc(A);Continue;end;
      B:=A+1;while (B<Length(FNodes)) and not (FNodes[B].Kind in [2,6,7,4]) do Inc(B);
      if (B>=Length(FNodes)) or (FNodes[B].Kind<>2) or (FNodes[B].Time-FNodes[A].Time>2.2) then begin Inc(A);Continue;end;
      Original:=-1;N:=0;for I:=A+1 to B-1 do if FNodes[I].Kind=0 then begin Original:=FNodes[I].Source;Inc(N);end;
      if (N<>1) or (Original<0) then begin Inc(A);Continue;end;
      StartNode:=FNodes[A];EndNode:=FNodes[B];Picks.Clear;
      for I:=A+1 to B-1 do if FNodes[I].Source>=0 then Picks.Add(FNodes[I]);
      EventFirst:=0;EventLast:=Length(FEvents);while EventFirst<EventLast do begin M:=(EventFirst+EventLast) div 2;if FEvents[M].Time<=StartNode.Time+0.07 then EventFirst:=M+1 else EventLast:=M;end;
      I:=EventFirst;while (I<Length(FEvents)) and (FEvents[I].Time<EndNode.Time-0.07) and (Picks.Count<10) do begin AddPick(FEvents[I]);Inc(I);end;
      for I:=1 to Picks.Count-1 do begin Node:=Picks[I];J:=I-1;while (J>=0) and (Picks[J].Time>Node.Time) do begin Picks[J+1]:=Picks[J];Dec(J);end;Picks[J+1]:=Node;end;
      N:=Picks.Count+1;if (N<4) or (N>11) then begin Inc(A);Continue;end;
      SetLength(Times,N+1);SetLength(Sources,N+1);Times[0]:=StartNode.Time;Times[N]:=EndNode.Time;
      for I:=1 to N-1 do begin Times[I]:=Picks[I-1].Time;Sources[I]:=Picks[I-1].Source;end;
      Found:=False;Room:=Length(FRooms);
      for Peak:=1 to N-1 do begin if Found then Break;
      // Prefer a compact chamber, then taller contact walls, then wider steps.
      // The endpoint/time solver and forward checks still decide feasibility.
      for HIndex:=0 to 3 do begin if Found then Break;Height:=Heights[(HIndex+(Room mod 3)) mod 4];
      for KIndex:=0 to 7 do begin if Found then Break;Ratio:=Ratios[(KIndex+2*(Room mod 3)) mod 8];
      for SignIndex:=0 to 1 do begin if Found then Break;SetLength(DY,N);SetLength(SX,N);SetLength(DX,N);SetLength(Velocity,N);Side:=SignIndex*2-1;Sum:=0;
        for I:=0 to N-1 do begin SX[I]:=Side;if I<Peak then DY[I]:=Height*(Times[I+1]-Times[I])/(Times[Peak]-Times[0]) else DY[I]:=Height*(Times[I+1]-Times[I])/(Times[N]-Times[Peak]);Sum:=Sum+Side*DY[I];if I+1<>Peak then Side:=-Side;end;
        Wanted:=(EndNode.P.X-StartNode.P.X)/Ratio;
        for PairA:=0 to N-1 do begin if Found then Break;for PairB:=PairA+1 to N-1 do begin
          if ((PairA<Peak)<>(PairB<Peak)) or (SX[PairA]=SX[PairB]) then Continue;Delta:=(Wanted-Sum)/(2*SX[PairA]);for I:=0 to N-1 do DX[I]:=DY[I];DX[PairA]:=DX[PairA]+Delta;DX[PairB]:=DX[PairB]-Delta;
          Good:=True;X:=StartNode.P.X;Y:=BREAK_PADDLE_Y;SetLength(Path,N+1);SetLength(Bricks,N-1);Path[0]:=StartNode;Path[0].Room:=Room;
          for I:=0 to N-1 do begin
            if DX[I]<0.008 then Good:=False;Velocity[I]:=Hypot(Ratio,1)*DX[I]/(Times[I+1]-Times[I]);if (Velocity[I]<0.55) or (Velocity[I]>4) then Good:=False;
            X:=X+SX[I]*Ratio*DX[I];if I<Peak then Y:=Y-DX[I] else Y:=Y+DX[I];
            if (X<0.085) or (X>1.515) or (Y<0.59) then Good:=False;
            if I=N-1 then Path[I+1]:=EndNode else begin Node:=Default(TActionNode);Node.P:=BreakPoint(X,Y);Node.Time:=Times[I+1];Node.Source:=Sources[I+1];Node.Kind:=0;Node.Core:=-1;Node.Room:=Room;Path[I+1]:=Node;end;
          end;Path[N].Room:=Room;if (Abs(X-EndNode.P.X)>1E-7) or (Abs(Y-BREAK_PADDLE_Y)>1E-7) then Good:=False;
          if not Good then Continue;
          for I:=1 to N-1 do Path[I].Speed:=0.95*Min(Velocity[I-1],Velocity[I]);
          for I:=1 to N-1 do begin
            Brick:=Default(TActionBrick);Brick.Base:=-1;Brick.Born:=Max(0.0,StartNode.Time-0.12);Brick.Row:=Floor(Path[I].P.Y/0.041);Brick.R.Time:=Times[I];Brick.R.Source:=Sources[I];Brick.R.Strength:=0.6;
            J:=EventIndex(Sources[I]);if J>=0 then Brick.R.Strength:=FEvents[J].Speed;
            if I=Peak then begin Brick.Axis:=-2;Brick.R.Left:=Path[I].P.X-0.060;Brick.R.Right:=Path[I].P.X+0.060;Brick.R.Bottom:=Path[I].P.Y-BREAK_RADIUS;Brick.R.Top:=Brick.R.Bottom-0.035;end
            else begin Brick.Axis:=Round(SX[I-1]);Brick.R.Top:=Path[I].P.Y-0.022;Brick.R.Bottom:=Path[I].P.Y+0.022;
              if Brick.Axis>0 then begin Brick.R.Left:=Path[I].P.X+BREAK_RADIUS;Brick.R.Right:=Brick.R.Left+0.058;end else begin Brick.R.Right:=Path[I].P.X-BREAK_RADIUS;Brick.R.Left:=Brick.R.Right-0.058;end;
            end;Bricks[I-1]:=Brick;
          end;
          for I:=0 to N-1 do begin C:=Controls(Path[I],Path[I+1]);Average:=Dist(Path[I].P,Path[I+1].P)/(Times[I+1]-Times[I]);
            U:=Path[I].Speed/(3*Average);V:=1-Path[I+1].Speed/(3*Average);if (U<0) or (V>1) or (U>V) then Good:=False;
            for J:=I to N-2 do if J=I then begin if not OnPlane(C,Bricks[J].R,Bricks[J].Axis,BREAK_RADIUS) then Good:=False;end else if not ClearCurve(C,Bricks[J].R,BREAK_RADIUS) then Good:=False;
          end;
          for I:=0 to High(Bricks) do for J:=I+1 to High(Bricks) do if BreakOverlap(Bricks[I].R,Bricks[J].R) then Good:=False;
          if Good then begin
            for I:=0 to A-1 do if FNodes[I+1].Time>=Bricks[0].Born then begin C:=Controls(FNodes[I],FNodes[I+1]);Lo:=Max(0.0,(Bricks[0].Born-FNodes[I].Time)/(FNodes[I+1].Time-FNodes[I].Time));C:=Clip(C,Lo,1);
              for J:=0 to High(Bricks) do if not ClearCurve(C,Bricks[J].R,BREAK_RADIUS) then Good:=False;
            end;
          end;
          if Good then begin Found:=True;Break;end;
        end;end;
      end;end;end;end;
      if Found then begin
        // Remove the original grid target and retain every outside paddle/node.
        for I:=0 to High(FBricks) do if FBricks[I].R.Source=Original then begin for J:=I to High(FBricks)-1 do FBricks[J]:=FBricks[J+1];SetLength(FBricks,Length(FBricks)-1);Break;end;
        I:=Length(FBricks);SetLength(FBricks,I+Length(Bricks));for J:=0 to High(Bricks) do FBricks[I+J]:=Bricks[J];
        NewNodes:=Copy(FNodes,0,A);SetLength(NewNodes,Length(FNodes)+Length(Path)-(B-A+1));
        for I:=0 to High(Path) do NewNodes[A+I]:=Path[I];
        for I:=B+1 to High(FNodes) do NewNodes[A+Length(Path)+I-B-1]:=FNodes[I];FNodes:=NewNodes;
        Group.First:=StartNode.Time;Group.Last:=EndNode.Time;SetLength(FRooms,Room+1);FRooms[Room]:=Group;LastRoom:=EndNode.Time;Inc(A,Length(Path));
      end else Inc(A);
    end;
  finally Picks.Free;end;Reindex;
end;
function TBreakActionPlan.GetCount:Integer;begin Result:=Length(FBricks);end;
function TBreakActionPlan.GetExtraCount:Integer;begin Result:=Length(FExtra);end;
function TBreakActionPlan.GetRoomCount:Integer;begin Result:=Length(FRooms);end;
function TBreakActionPlan.EventIndex(Source:Integer):Integer;
var A,B,M:Integer;begin A:=0;B:=Length(FEvents);while A<B do begin M:=(A+B) div 2;if FEvents[M].Source<Source then A:=M+1 else B:=M;end;Result:=-1;if (A<Length(FEvents)) and (FEvents[A].Source=Source) then Result:=A;end;
function TBreakActionPlan.PositionAt(Time:Double):TBreakPoint;
var A,B,M:Integer;C:TControls;
begin Result:=BreakPoint(0.8,BREAK_PADDLE_Y);if Length(FNodes)=0 then Exit;if Time<=FNodes[0].Time then Exit(FNodes[0].P);A:=1;B:=Length(FNodes);while A<B do begin M:=(A+B) div 2;if FNodes[M].Time<Time then A:=M+1 else B:=M;end;A:=Min(A,High(FNodes));C:=Controls(FNodes[A-1],FNodes[A]);Result:=CurveAt(C,(Time-FNodes[A-1].Time)/(FNodes[A].Time-FNodes[A-1].Time));end;
function TBreakActionPlan.BrickAt(Index:Integer;Time:Double):TBreakBlock;
begin Result:=FBricks[Index].R;if FBricks[Index].Base>=0 then begin Time:=KeyAt(FShifts,Min(Time,Result.Time));Result.Top:=Result.Top+Time;Result.Bottom:=Result.Bottom+Time;end;end;
function TBreakActionPlan.BrickRow(Index:Integer):Integer;begin Result:=FBricks[Index].Row;end;
function TBreakActionPlan.BrickVisible(Index:Integer;Time:Double):Boolean;begin Result:=Time>=FBricks[Index].Born;end;
function TBreakActionPlan.RadiusAt(Time:Double):Double;
var C:TActionCharge;U:Double;
begin Result:=BREAK_RADIUS;for C in FCharges do if (Time>C.First) and (Time<C.Last) then begin U:=(Time-C.First)/(C.Last-C.First);U:=Min(1.0,Min(U/0.2,(1-U)/0.2));Result:=Max(Result,BREAK_RADIUS+(C.Radius-BREAK_RADIUS)*U);end;end;
function TBreakActionPlan.RadiusBound(First,Last:Double):Double;
var C:TActionCharge;begin Result:=Max(RadiusAt(First),RadiusAt(Last));for C in FCharges do
  if (First<=C.First+0.8*(C.Last-C.First)) and (Last>=C.First+0.2*(C.Last-C.First)) then Result:=Max(Result,C.Radius);end;
function TBreakActionPlan.FirstTouch(const B:TActionBrick;First,Last:Double;out Hit:Double):Boolean;
var I:Integer;T,Previous,Lo,Hi:Double;P:TBreakPoint;
begin Result:=False;Hit:=0;Previous:=First;for I:=0 to Ceil((Last-First)/0.001) do begin T:=Min(Last,First+I*0.001);P:=PositionAt(T);if PointRect(P,B.R)<=RadiusAt(T) then begin Lo:=Previous;Hi:=T;while Hi-Lo>1E-10 do begin T:=(Lo+Hi)/2;if PointRect(PositionAt(T),B.R)<=RadiusAt(T) then Hi:=T else Lo:=T;end;Hit:=Hi;Exit(True);end;Previous:=T;end;end;
function TBreakActionPlan.ClearsMain(const B:TActionBrick;UntilTime:Double):Boolean;
var I:Integer;C:TControls;First,Last,D:Double;
  function ClearTimed(const Q:TControls;A,Z:Double;Depth:Integer):Boolean;
  var L,R:TControls;M:Double;
  begin
    if ClearCurve(Q,B.R,RadiusBound(A,Z),0) then Exit(True);
    if Depth>=18 then Exit(False);M:=(A+Z)/2;Split(Q,0.5,L,R);
    Result:=ClearTimed(L,A,M,Depth+1) and ClearTimed(R,M,Z,Depth+1);
  end;
begin
  Result:=True;
  for I:=0 to High(FNodes)-1 do begin
    First:=Max(B.Born,FNodes[I].Time);Last:=Min(UntilTime,FNodes[I+1].Time);
    if Last<=First then Continue;D:=FNodes[I+1].Time-FNodes[I].Time;
    C:=Clip(Controls(FNodes[I],FNodes[I+1]),(First-FNodes[I].Time)/D,(Last-FNodes[I].Time)/D);
    if not ClearTimed(C,First,Last,0) then Exit(False);
  end;
end;
function TBreakActionPlan.ClearsBall(const Ball:TActionBall;const B:TActionBrick;Own:Boolean):Boolean;
var K,J:Integer;A,Z,First,Last:Double;P,Q:TBreakPoint;C:TControls;
begin
  Result:=True;
  for K:=0 to 1 do begin
    if K=0 then begin A:=Ball.Launch;Z:=Ball.Hit;P:=Ball.A;Q:=Ball.B;end
    else begin A:=Ball.Hit;Z:=Ball.Catch;P:=Ball.B;Q:=Ball.C;end;
    First:=Max(A,B.Born);Last:=Min(Z,B.R.Time);if Last<=First+1E-10 then Continue;
    for J:=0 to 3 do C[J]:=Mix(P,Q,J/3);C:=Clip(C,(First-A)/(Z-A),(Last-A)/(Z-A));
    if Own and (K=0) then begin if not OnPlane(C,B.R,-2,BREAK_RADIUS) then Exit(False);end
    else if not ClearCurve(C,B.R,BREAK_RADIUS) then Exit(False);
  end;
end;
procedure TBreakActionPlan.MakeCharges(const Cancel:TFunc<Boolean>);
var I,J,K,OldCount,Added:Integer;C:TActionCharge;B:TActionBrick;P:TBreakPoint;
  T,Hit,LastCharge:Double;Good:Boolean;
begin
  LastCharge:=-10;
  for I:=1 to High(FNodes)-1 do begin
    if Assigned(Cancel) and Cancel() then Abort;
    if (Length(FCharges)>=1000) or (Length(FBricks)>11450) then Break;
    if (FNodes[I].Kind<>0) or (FNodes[I].Room>=0) or (FNodes[I].Time<LastCharge+3.8) or
      (FNodes[I+1].Time-FNodes[I].Time<0.35) or (FNodes[I+1].P.Y<FNodes[I].P.Y+0.15) then Continue;
    J:=EventIndex(FNodes[I].Source);if (J<0) or (FEvents[J].Speed<0.78) then Continue;
    C.Source:=FNodes[I].Source;C.Radius:=0.048;C.First:=0;C.Last:=0;
    for J:=1 to 99 do begin T:=FNodes[I].Time+(FNodes[I+1].Time-FNodes[I].Time)*J/100;P:=PositionAt(T);
      if (P.Y>=FContactY+0.085) and (P.Y<=0.81) and (P.X>C.Radius+0.02) and (P.X<BREAK_WIDTH-C.Radius-0.02) then begin if C.First=0 then C.First:=T;C.Last:=T;end;
    end;
    if (C.Last-C.First<0.16) or (C.Last>=FGoal-0.05) then Continue;
    SetLength(FCharges,Length(FCharges)+1);FCharges[High(FCharges)]:=C;Good:=True;
    // A room may materialise near the next paddle return. Enlargement must
    // not touch one of those still-reserved contacts before its fixed accent.
    for J:=0 to High(FBricks) do if (FBricks[J].Base<0) and (FBricks[J].Born<C.Last) and (FBricks[J].R.Time>C.First) then
      if not ClearsMain(FBricks[J],FBricks[J].R.Time-1E-7) then Good:=False;
    if not Good then begin SetLength(FCharges,Length(FCharges)-1);Continue;end;
    OldCount:=Length(FBricks);Added:=0;
    // A compact row is crossed by the growing ball. These are real targets,
    // not ghosts on the primary's reserved future contacts.
    P:=PositionAt(C.First+(C.Last-C.First)*0.55);
    for K:=-2 to 2 do begin
      B:=Default(TActionBrick);B.Base:=-1;B.Axis:=0;B.Cause:=0;B.Born:=Max(0.0,FNodes[I].Time-0.12);
      B.R.Source:=-1;B.R.Strength:=1;B.Row:=Floor(P.Y/0.041);B.R.Left:=P.X+K*0.030-0.013;B.R.Right:=B.R.Left+0.026;
      B.R.Top:=P.Y-0.022;B.R.Bottom:=P.Y+0.022;
      if B.R.Top<=FContactY+0.045 then Continue;
      if not FirstTouch(B,C.First,C.Last,Hit) or (Hit<=C.First+0.01) then Continue;
      B.R.Time:=Hit;Good:=ClearsMain(B,Hit-1E-7);
      for J:=0 to High(FBricks) do if (FBricks[J].Base<0) and (FBricks[J].R.Time>B.Born) and BreakOverlap(B.R,FBricks[J].R) then Good:=False;
      if Good then begin SetLength(FBricks,Length(FBricks)+1);FBricks[High(FBricks)]:=B;Inc(Added);end;
    end;
    if Added<2 then begin SetLength(FBricks,OldCount);SetLength(FCharges,Length(FCharges)-1);end else LastCharge:=C.Last;
  end;
end;
procedure TBreakActionPlan.MakeFinishers(const Cancel:TFunc<Boolean>);
var I,J:Integer;Ball:TActionBall;B:TActionBrick;Good:Boolean;D,Speed:Double;
begin
  if FGoal<5 then Exit;
  for I:=0 to 143 do begin
    if Assigned(Cancel) and Cancel() then Abort;if Length(FExtra)>=24 then Break;
    D:=0.18+0.035*(I mod 7);Ball.Hit:=FGoal-1.20+0.0065*I;Ball.Launch:=Ball.Hit-D;Ball.Catch:=Ball.Hit+D;
    Ball.A:=BreakPoint(KeyAt(FPaddles,Ball.Launch)+((I mod 5)-2)*FPaddleHalf*0.4,BREAK_PADDLE_Y);
    Ball.C:=BreakPoint(KeyAt(FPaddles,Ball.Catch)+(((I div 5) mod 5)-2)*FPaddleHalf*0.4,BREAK_PADDLE_Y);
    Ball.B:=BreakPoint((Ball.A.X+Ball.C.X)/2,0.625+0.025*((I div 3) mod 7));
    Speed:=Dist(Ball.A,Ball.B)/D;if (Speed<0.5) or (Speed>4.0) then Continue;
    B:=Default(TActionBrick);B.Base:=-1;B.Axis:=-2;B.Cause:=Length(FExtra)+1;B.Born:=Max(0.0,FGoal-1.85);B.Row:=I mod 7;
    B.R.Source:=-1;B.R.Time:=Ball.Hit;B.R.Strength:=0.90;B.R.Left:=Ball.B.X-0.018;B.R.Right:=Ball.B.X+0.018;
    B.R.Bottom:=Ball.B.Y-BREAK_RADIUS;B.R.Top:=B.R.Bottom-0.024;
    Good:=ClearsMain(B,B.R.Time) and ClearsBall(Ball,B,True);
    for J:=0 to High(FBricks) do if (FBricks[J].Base<0) and (FBricks[J].R.Time>B.Born) then begin
      if BreakOverlap(B.R,FBricks[J].R) or not ClearsBall(Ball,FBricks[J],False) then Good:=False;
    end;
    for J:=0 to High(FExtra) do if not ClearsBall(FExtra[J],B,False) then Good:=False;
    if not Good then Continue;
    Ball.Target:=Length(FBricks);SetLength(FBricks,Length(FBricks)+1);FBricks[High(FBricks)]:=B;
    SetLength(FExtra,Length(FExtra)+1);FExtra[High(FExtra)]:=Ball;
  end;
end;
function TBreakActionPlan.ExtraLaunch(Index:Integer):Double;begin Result:=FExtra[Index].Launch;end;
function TBreakActionPlan.ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
var A:TActionBall;U:Double;
begin A:=FExtra[Index];P:=A.A;Alpha:=0;Result:=(Time>=A.Launch) and (Time<A.Catch+0.2);if not Result then Exit;
  Alpha:=Min(1.0,(Time-A.Launch)/0.05);if Time<=A.Hit then P:=Mix(A.A,A.B,(Time-A.Launch)/(A.Hit-A.Launch))
  else if Time<=A.Catch then P:=Mix(A.B,A.C,(Time-A.Hit)/(A.Catch-A.Hit)) else begin U:=(Time-A.Catch)/0.2;P:=BreakPoint(KeyAt(FPaddles,Time)+(A.C.X-KeyAt(FPaddles,A.Catch))*(1-U*U*(3-2*U)),BREAK_PADDLE_Y);Alpha:=1-U;end;
end;
function TBreakActionPlan.SyncCount:Integer;var N:TActionNode;begin Result:=0;for N in FNodes do if (N.Source>=0) and (N.Kind in [0,1,2,5]) then Inc(Result);end;
function TBreakActionPlan.AuxiliaryCount:Integer;var N:TActionNode;begin Result:=0;for N in FNodes do if (N.Source<0) and (N.Kind in [1,2,5]) then Inc(Result);end;
procedure TBreakActionPlan.Verify(const Cancel:TFunc<Boolean>);
var I,J,K,Axis:Integer;C,Part:TControls;B:TActionBrick;R:TBreakBlock;N:TActionNode;A,D:TBreakPoint;Lo,Hi,First,Last:Double;X:TActionBall;Charge:TActionCharge;Seen:TDictionary<Integer,Boolean>;Hits:TArray<Integer>;
  procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create('Breakout action forward: '+S);end;
begin
  Need((Length(FNodes)<=32000) and (Length(FBricks)<=11500) and (Length(FRooms)<=1000) and (Length(FCharges)<=1000) and (Length(FExtra)<=24),'limits');
  if Length(FCoreNodes)>0 then begin
    Need((Length(FNodes)>1) and (Count>0),'nonempty accepted score');
    Need((FNodes[0].Core=0) and (FNodes[High(FNodes)].Core=High(FCoreNodes)),'original launch and finish');
    Need(FBricks[High(FBricks)].R.Time=FGoal,'all-clear on original last accent');
  end else Need((Count=0) and (Length(FRooms)=0) and (Length(FCharges)=0) and (Length(FExtra)=0),'silent action data');
  for I:=0 to High(FRooms) do begin
    Need(Finite(FRooms[I].First) and Finite(FRooms[I].Last) and (FRooms[I].First>=0) and (FRooms[I].Last>FRooms[I].First) and (FRooms[I].Last-FRooms[I].First<=2.2+1E-8),'room bounds');
    if I>0 then Need(FRooms[I].First>=FRooms[I-1].Last+3.5-1E-8,'normal interval between rooms');
    J:=0;K:=0;for N in FNodes do begin if (N.Room=I) and (N.Kind=0) then Inc(J);
      if (N.Room=I) and (N.Kind=2) and (N.Core>=0) and ((N.Time=FRooms[I].First) or (N.Time=FRooms[I].Last)) then Inc(K);
    end;Need((J>=3) and (J<=10) and (K=2),'room real paddle boundaries');
  end;
  SetLength(Hits,Count);
  Seen:=TDictionary<Integer,Boolean>.Create;
  try
  for I:=0 to High(FNodes) do begin N:=FNodes[I];Need(Finite(N.Time) and Finite(N.P.X) and Finite(N.P.Y) and Finite(N.Speed),'finite');if I>0 then Need(N.Time>FNodes[I-1].Time,'time order');
    Need((N.Kind>=0) and (N.Kind<=7) and (N.Room>=-1) and (N.Room<Length(FRooms)) and (N.Speed>=0),'node metadata');
    if (N.Source>=0) and (N.Kind in [0,1,2,5]) then begin Need(not Seen.ContainsKey(N.Source),'unique primary accent');Seen.Add(N.Source,True);end;
    if (N.Core>=0) then begin Need(N.Core<Length(FCoreNodes),'core index');Need((N.Time=FCoreNodes[N.Core].Time) and (N.Speed=FCoreNodes[N.Core].Speed) and (N.P.X=FCoreNodes[N.Core].P.X) and (N.P.Y=FCoreNodes[N.Core].P.Y) and (N.Source=FCoreNodes[N.Core].Source) and (N.Kind=FCoreNodes[N.Core].Kind),'outside core unchanged');end;
    if (I>0) and (I<High(FNodes)) and (N.Kind=0) then begin Need((N.Source>=0) and (N.Brick>=0) and (N.Brick<Count),'target');Inc(Hits[N.Brick]);R:=BrickAt(N.Brick,N.Time);Need((R.Source=N.Source) and (R.Time=N.Time),'target event identity');Need(Abs(PointRect(N.P,R)-BREAK_RADIUS)<1E-7,'contact');
      A:=BreakPoint(N.P.X-FNodes[I-1].P.X,N.P.Y-FNodes[I-1].P.Y);D:=BreakPoint(FNodes[I+1].P.X-N.P.X,FNodes[I+1].P.Y-N.P.Y);Lo:=Hypot(A.X,A.Y);Hi:=Hypot(D.X,D.Y);Axis:=FBricks[N.Brick].Axis;
      if Abs(Axis)=1 then Need((Abs(A.X/Lo+D.X/Hi)<1E-7) and (Abs(A.Y/Lo-D.Y/Hi)<1E-7),'X reflection') else Need((Abs(A.X/Lo-D.X/Hi)<1E-7) and (Abs(A.Y/Lo+D.Y/Hi)<1E-7),'Y reflection');
    end;
    if I=High(FNodes) then Continue;C:=Controls(N,FNodes[I+1]);
    if (N.Room>=0) and (N.Room=FNodes[I+1].Room) then begin
      Need((N.Time>=FRooms[N.Room].First) and (FNodes[I+1].Time<=FRooms[N.Room].Last),'rush interval');
      for K:=0 to 3 do Need(C[K].Y>FContactY+0.045,'rush below live grid');
    end else Need((N.Core>=0) and (FNodes[I+1].Core=N.Core+1),'no unplanned outside turn');
    for J:=0 to High(FBricks) do begin B:=FBricks[J];if (B.Base>=0) or ((B.R.Source=-1) and (B.Cause=0)) or (B.R.Time<N.Time-1E-9) or (B.Born>FNodes[I+1].Time) then Continue;
      First:=Max(N.Time,B.Born);Last:=Min(FNodes[I+1].Time,B.R.Time);if Last<=First+1E-10 then Continue;Lo:=(First-N.Time)/(FNodes[I+1].Time-N.Time);Hi:=(Last-N.Time)/(FNodes[I+1].Time-N.Time);Part:=Clip(C,Lo,Hi);
      if (FNodes[I+1].Kind=0) and (FNodes[I+1].Brick=J) and (Abs(Last-B.R.Time)<1E-8) then Need(OnPlane(Part,B.R,B.Axis,BREAK_RADIUS),'target approach')
      // Other targets are checked below with the time-varying charged radius.
      // A single maximum radius over an entire leg rejects legal grow/shrink.
      ;
    end;
  end;
  finally Seen.Free;end;
  for I:=0 to High(FBricks) do begin B:=FBricks[I];Need(Finite(B.R.Time) and Finite(B.R.Left) and Finite(B.R.Right) and Finite(B.R.Top) and Finite(B.R.Bottom) and Finite(B.Born) and (B.R.Right>B.R.Left) and (B.R.Bottom>B.R.Top),'brick');
    Need((B.Base>=-1) and (B.Cause>=0) and (B.Cause<=Length(FExtra)) and (B.R.Source>=-1),'brick metadata');
    if I>0 then Need(B.R.Time>=FBricks[I-1].R.Time,'brick order');if B.R.Source>=0 then begin K:=EventIndex(B.R.Source);Need((K>=0) and (B.R.Time=FEvents[K].Time),'unchanged accent');Need(Hits[I]=1,'one primary destruction');end else Need(Hits[I]=0,'no primary steals extra target');end;
  for I:=0 to High(FBricks) do begin B:=FBricks[I];if B.Base>=0 then Continue;
    Need((B.Born>=0) and (B.Born<B.R.Time) and (B.R.Time<=FGoal),'live bounds');
    for J:=I+1 to High(FBricks) do if (FBricks[J].Base<0) and (FBricks[J].Born<B.R.Time) then Need(not BreakOverlap(B.R,FBricks[J].R),'formation overlap');
    if (B.R.Source=-1) and (B.Cause=0) then begin
      Need(RadiusAt(B.R.Time)>BREAK_RADIUS+0.003,'piercing charge');
      Need(Abs(PointRect(PositionAt(B.R.Time),B.R)-RadiusAt(B.R.Time))<1E-7,'piercing first contact');
      Need(ClearsMain(B,B.R.Time-1E-7),'piercing early collision');
    end else if B.R.Source>=0 then Need(ClearsMain(B,B.R.Time-1E-7),'rush early collision')
    else Need(ClearsMain(B,B.R.Time),'finisher main reservation');
  end;
  for I:=0 to High(FBricks) do begin B:=FBricks[I];if B.Base<0 then Continue;Need(B.Base<Length(FCoreBricks),'base brick index');R:=FCoreBricks[B.Base].R;
    Need((B.R.Time=R.Time) and (B.R.Source=R.Source) and (Abs(B.R.Left-R.Left)<1E-12) and (Abs(B.R.Right-R.Right)<1E-12) and (Abs(B.R.Top-R.Top)<1E-12) and (Abs(B.R.Bottom-R.Bottom)<1E-12) and (B.Row=FCoreBricks[B.Base].Row) and (B.Born=0),'unchanged live grid');
  end;
  for Charge in FCharges do begin
    Need(Finite(Charge.First) and Finite(Charge.Last) and Finite(Charge.Radius) and (Charge.First<Charge.Last) and (Charge.Radius>BREAK_RADIUS) and (Charge.Radius<=0.05) and (Charge.Last<FGoal),'charge bounds');
    K:=EventIndex(Charge.Source);Need((K>=0) and (FEvents[K].Speed>=0.78) and (Charge.First>=FEvents[K].Time),'charge original strong accent');
    for I:=0 to 100 do begin First:=Charge.First+(Charge.Last-Charge.First)*I/100;A:=PositionAt(First);
      Need((A.Y-RadiusAt(First)>FContactY+0.025) and (A.X-RadiusAt(First)>0) and (A.X+RadiusAt(First)<BREAK_WIDTH),'charge separated from reserved grid/walls');end;
    for I:=0 to High(FNodes)-1 do begin First:=Max(Charge.First,FNodes[I].Time);Last:=Min(Charge.Last,FNodes[I+1].Time);if Last<=First then Continue;
      Lo:=(First-FNodes[I].Time)/(FNodes[I+1].Time-FNodes[I].Time);Hi:=(Last-FNodes[I].Time)/(FNodes[I+1].Time-FNodes[I].Time);C:=Clip(Controls(FNodes[I],FNodes[I+1]),Lo,Hi);
      for K:=0 to 3 do Need((C[K].Y-Charge.Radius>FContactY+0.025) and (C[K].X-Charge.Radius>0) and (C[K].X+Charge.Radius<BREAK_WIDTH),'charge continuous hull separation');
    end;
  end;
  for I:=0 to High(FExtra) do begin X:=FExtra[I];Need((X.Target>=0) and (X.Target<Count),'finisher target');B:=FBricks[X.Target];
    Need((B.Cause=I+1) and (B.R.Source=-1) and (B.R.Time=X.Hit) and (X.Launch<X.Hit) and (X.Hit<X.Catch) and (X.Hit<FGoal),'finisher identity');
    Need((X.A.Y=BREAK_PADDLE_Y) and (X.C.Y=BREAK_PADDLE_Y) and (X.B.Y>FContactY+0.07),'finisher reserved grid separation');
    Need((Abs(X.A.X-KeyAt(FPaddles,X.Launch))<=FPaddleHalf-BREAK_RADIUS+1E-8) and (Abs(X.C.X-KeyAt(FPaddles,X.Catch))<=FPaddleHalf-BREAK_RADIUS+1E-8),'finisher paddle');
    A:=BreakPoint((X.B.X-X.A.X)/(X.Hit-X.Launch),(X.B.Y-X.A.Y)/(X.Hit-X.Launch));
    D:=BreakPoint((X.C.X-X.B.X)/(X.Catch-X.Hit),(X.C.Y-X.B.Y)/(X.Catch-X.Hit));
    Need((Abs(A.X-D.X)<1E-7) and (Abs(A.Y+D.Y)<1E-7),'finisher physical reflection');
    Need(Abs(PointRect(X.B,B.R)-BREAK_RADIUS)<1E-8,'finisher contact');
    for J:=0 to High(FBricks) do if FBricks[J].Base<0 then Need(ClearsBall(X,FBricks[J],J=X.Target),'finisher earlier live block');
  end;
end;
function TBreakActionPlan.ExportData(Core:TJSONObject;Audio:TRhythmAudio):TJSONObject;
var Root,J:TJSONObject;Items:TJSONArray;N:TActionNode;B:TActionBrick;R:TActionRoom;C:TActionCharge;X:TActionBall;
begin Root:=TJSONObject.Create;try Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','breakout');Root.AddPair('version',TJSONNumber.Create(5));Root.AddPair('layout','rush-overlay-v1');Root.AddPair('baseScore',Core);
  Items:=TJSONArray.Create;Root.AddPair('events',Items);for N in FEvents do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(N.Time));J.AddPair('strength',TJSONNumber.Create(N.Speed));J.AddPair('source',TJSONNumber.Create(N.Source));end;
  Items:=TJSONArray.Create;Root.AddPair('nodes',Items);for N in FNodes do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(N.Time));J.AddPair('speed',TJSONNumber.Create(N.Speed));J.AddPair('x',TJSONNumber.Create(N.P.X));J.AddPair('y',TJSONNumber.Create(N.P.Y));J.AddPair('kind',TJSONNumber.Create(N.Kind));J.AddPair('source',TJSONNumber.Create(N.Source));J.AddPair('brick',TJSONNumber.Create(N.Brick));J.AddPair('core',TJSONNumber.Create(N.Core));J.AddPair('room',TJSONNumber.Create(N.Room));end;
  Items:=TJSONArray.Create;Root.AddPair('actionBricks',Items);for B in FBricks do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(B.R.Time));J.AddPair('strength',TJSONNumber.Create(B.R.Strength));J.AddPair('source',TJSONNumber.Create(B.R.Source));J.AddPair('left',TJSONNumber.Create(B.R.Left));J.AddPair('right',TJSONNumber.Create(B.R.Right));J.AddPair('top',TJSONNumber.Create(B.R.Top));J.AddPair('bottom',TJSONNumber.Create(B.R.Bottom));J.AddPair('base',TJSONNumber.Create(B.Base));J.AddPair('row',TJSONNumber.Create(B.Row));J.AddPair('axis',TJSONNumber.Create(B.Axis));J.AddPair('cause',TJSONNumber.Create(B.Cause));J.AddPair('born',TJSONNumber.Create(B.Born));end;
  Items:=TJSONArray.Create;Root.AddPair('rooms',Items);for R in FRooms do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('first',TJSONNumber.Create(R.First));J.AddPair('last',TJSONNumber.Create(R.Last));end;
  Items:=TJSONArray.Create;Root.AddPair('charges',Items);for C in FCharges do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('first',TJSONNumber.Create(C.First));J.AddPair('last',TJSONNumber.Create(C.Last));J.AddPair('radius',TJSONNumber.Create(C.Radius));J.AddPair('source',TJSONNumber.Create(C.Source));end;
  Items:=TJSONArray.Create;Root.AddPair('actionExtra',Items);for X in FExtra do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('launch',TJSONNumber.Create(X.Launch));J.AddPair('hit',TJSONNumber.Create(X.Hit));J.AddPair('catch',TJSONNumber.Create(X.Catch));J.AddPair('ax',TJSONNumber.Create(X.A.X));J.AddPair('ay',TJSONNumber.Create(X.A.Y));J.AddPair('bx',TJSONNumber.Create(X.B.X));J.AddPair('by',TJSONNumber.Create(X.B.Y));J.AddPair('cx',TJSONNumber.Create(X.C.X));J.AddPair('cy',TJSONNumber.Create(X.C.Y));J.AddPair('target',TJSONNumber.Create(X.Target));end;Result:=Root;
  except Root.Free;raise;end;
end;
class function TBreakActionPlan.Load(Data:TJSONObject):TBreakActionPlan;
var Items:TJSONArray;J:TJSONObject;I:Integer;
begin Result:=TBreakActionPlan.Create;try Result.ReadCore(Data.GetValue<TJSONObject>('baseScore'));
  Items:=Data.GetValue<TJSONArray>('nodes');if (Items=nil) or (Items.Count>32000) then raise Exception.Create('Action nodes');SetLength(Result.FNodes,Items.Count);for I:=0 to Items.Count-1 do begin J:=Items.Items[I] as TJSONObject;Result.FNodes[I].Time:=J.GetValue<Double>('time');Result.FNodes[I].Speed:=J.GetValue<Double>('speed');Result.FNodes[I].P:=BreakPoint(J.GetValue<Double>('x'),J.GetValue<Double>('y'));Result.FNodes[I].Kind:=J.GetValue<Integer>('kind');Result.FNodes[I].Source:=J.GetValue<Integer>('source');Result.FNodes[I].Brick:=J.GetValue<Integer>('brick');Result.FNodes[I].Core:=J.GetValue<Integer>('core');Result.FNodes[I].Room:=J.GetValue<Integer>('room');end;
  Items:=Data.GetValue<TJSONArray>('actionBricks');if (Items=nil) or (Items.Count>11500) then raise Exception.Create('Action bricks');SetLength(Result.FBricks,Items.Count);for I:=0 to Items.Count-1 do begin J:=Items.Items[I] as TJSONObject;Result.FBricks[I].R.Time:=J.GetValue<Double>('time');Result.FBricks[I].R.Strength:=J.GetValue<Double>('strength');Result.FBricks[I].R.Source:=J.GetValue<Integer>('source');Result.FBricks[I].R.Left:=J.GetValue<Double>('left');Result.FBricks[I].R.Right:=J.GetValue<Double>('right');Result.FBricks[I].R.Top:=J.GetValue<Double>('top');Result.FBricks[I].R.Bottom:=J.GetValue<Double>('bottom');Result.FBricks[I].Base:=J.GetValue<Integer>('base');Result.FBricks[I].Row:=J.GetValue<Integer>('row');Result.FBricks[I].Axis:=J.GetValue<Integer>('axis');Result.FBricks[I].Cause:=J.GetValue<Integer>('cause');Result.FBricks[I].Born:=J.GetValue<Double>('born');end;
  Items:=Data.GetValue<TJSONArray>('rooms');if (Items=nil) or (Items.Count>1000) then raise Exception.Create('Action rooms');SetLength(Result.FRooms,Items.Count);for I:=0 to Items.Count-1 do begin J:=Items.Items[I] as TJSONObject;Result.FRooms[I].First:=J.GetValue<Double>('first');Result.FRooms[I].Last:=J.GetValue<Double>('last');end;
  Items:=Data.GetValue<TJSONArray>('charges');if (Items=nil) or (Items.Count>1000) then raise Exception.Create('Action charges');SetLength(Result.FCharges,Items.Count);for I:=0 to Items.Count-1 do begin J:=Items.Items[I] as TJSONObject;Result.FCharges[I].First:=J.GetValue<Double>('first');Result.FCharges[I].Last:=J.GetValue<Double>('last');Result.FCharges[I].Radius:=J.GetValue<Double>('radius');Result.FCharges[I].Source:=J.GetValue<Integer>('source');end;
  Items:=Data.GetValue<TJSONArray>('actionExtra');if (Items=nil) or (Items.Count>128) then raise Exception.Create('Action extras');SetLength(Result.FExtra,Items.Count);for I:=0 to Items.Count-1 do begin J:=Items.Items[I] as TJSONObject;Result.FExtra[I].Launch:=J.GetValue<Double>('launch');Result.FExtra[I].Hit:=J.GetValue<Double>('hit');Result.FExtra[I].Catch:=J.GetValue<Double>('catch');Result.FExtra[I].A:=BreakPoint(J.GetValue<Double>('ax'),J.GetValue<Double>('ay'));Result.FExtra[I].B:=BreakPoint(J.GetValue<Double>('bx'),J.GetValue<Double>('by'));Result.FExtra[I].C:=BreakPoint(J.GetValue<Double>('cx'),J.GetValue<Double>('cy'));Result.FExtra[I].Target:=J.GetValue<Integer>('target');end;
  Result.Verify;
  except Result.Free;raise;end;
end;
end.
