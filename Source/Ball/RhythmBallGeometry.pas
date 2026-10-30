unit RhythmBallGeometry;
interface
const
  BALL_RADIUS=0.022;
  BALL_BOARD_WIDTH=1.0;
  BALL_BOARD_HEIGHT=1.4;
type
  TBallPoint=record X,Y:Double;end;
  TBallObstacleKind=(boBumper,boBreakable);
  TBallObstacle=record
    Kind:TBallObstacleKind;
    Spawn,Arrive,Hit,Retire,Radius,Strength:Double;
    Origin,Center,Normal:TBallPoint;
  end;
  TBallFlight=record
    StartTime,EndTime:Double;
    A,B,C,D:TBallPoint;
  end;
function BallPoint(X,Y:Double):TBallPoint;
function BallAdd(const A,B:TBallPoint):TBallPoint;
function BallSub(const A,B:TBallPoint):TBallPoint;
function BallScale(const P:TBallPoint;S:Double):TBallPoint;
function BallDot(const A,B:TBallPoint):Double;
function BallLength(const P:TBallPoint):Double;
function BallUnit(const P:TBallPoint):TBallPoint;
function BallMix(const A,B:TBallPoint;U:Double):TBallPoint;
function FlightPoint(const F:TBallFlight;Time:Double):TBallPoint;
function ClipFlight(const F:TBallFlight;First,Last:Double):TBallFlight;
function ObstaclePoint(const O:TBallObstacle;Time:Double):TBallPoint;
function ObstacleSolidEnd(const O:TBallObstacle):Double;
// Conservative Bezier hull / moving-circle check, including planned tangent contact.
function FlightClearsObstacle(const F:TBallFlight;const O:TBallObstacle):Boolean;
implementation
uses System.Math;
function BallPoint(X,Y:Double):TBallPoint;begin Result.X:=X;Result.Y:=Y;end;
function BallAdd(const A,B:TBallPoint):TBallPoint;begin Result:=BallPoint(A.X+B.X,A.Y+B.Y);end;
function BallSub(const A,B:TBallPoint):TBallPoint;begin Result:=BallPoint(A.X-B.X,A.Y-B.Y);end;
function BallScale(const P:TBallPoint;S:Double):TBallPoint;begin Result:=BallPoint(P.X*S,P.Y*S);end;
function BallDot(const A,B:TBallPoint):Double;begin Result:=A.X*B.X+A.Y*B.Y;end;
function BallLength(const P:TBallPoint):Double;begin Result:=Hypot(P.X,P.Y);end;
function BallUnit(const P:TBallPoint):TBallPoint;
var L:Double;begin L:=BallLength(P);if L<1E-10 then Result:=BallPoint(0,-1) else Result:=BallScale(P,1/L);end;
function BallMix(const A,B:TBallPoint;U:Double):TBallPoint;
begin Result:=BallAdd(BallScale(A,1-U),BallScale(B,U));end;
procedure SplitFlight(const F:TBallFlight;U:Double;out Left,Right:TBallFlight);
var AB,BC,CD,ABC,BCD,P:TBallPoint;T:Double;
begin
  AB:=BallMix(F.A,F.B,U);BC:=BallMix(F.B,F.C,U);CD:=BallMix(F.C,F.D,U);
  ABC:=BallMix(AB,BC,U);BCD:=BallMix(BC,CD,U);P:=BallMix(ABC,BCD,U);
  T:=F.StartTime+(F.EndTime-F.StartTime)*U;
  Left:=F;Left.B:=AB;Left.C:=ABC;Left.D:=P;Left.EndTime:=T;
  Right:=F;Right.A:=P;Right.B:=BCD;Right.C:=CD;Right.StartTime:=T;
end;
function FlightPoint(const F:TBallFlight;Time:Double):TBallPoint;
var U,V:Double;
begin
  U:=EnsureRange((Time-F.StartTime)/Max(1E-10,F.EndTime-F.StartTime),0.0,1.0);V:=1-U;
  Result:=BallAdd(BallAdd(BallScale(F.A,V*V*V),BallScale(F.B,3*V*V*U)),
    BallAdd(BallScale(F.C,3*V*U*U),BallScale(F.D,U*U*U)));
end;
function ClipFlight(const F:TBallFlight;First,Last:Double):TBallFlight;
var Left,Right:TBallFlight;U:Double;
begin
  Result:=F;First:=Max(First,F.StartTime);Last:=Min(Last,F.EndTime);
  if Last<F.EndTime then begin
    U:=EnsureRange((Last-F.StartTime)/Max(1E-10,F.EndTime-F.StartTime),0.0,1.0);
    SplitFlight(Result,U,Left,Right);Result:=Left;
  end;
  if First>Result.StartTime then begin
    U:=EnsureRange((First-Result.StartTime)/Max(1E-10,Result.EndTime-Result.StartTime),0.0,1.0);
    SplitFlight(Result,U,Left,Right);Result:=Right;
  end;
end;
function ObstaclePoint(const O:TBallObstacle;Time:Double):TBallPoint;
var U:Double;
begin
  if O.Arrive<=O.Spawn then Exit(O.Center);
  U:=EnsureRange((Time-O.Spawn)/(O.Arrive-O.Spawn),0.0,1.0);U:=U*U*(3-2*U);
  Result:=BallMix(O.Origin,O.Center,U);
end;
function ObstacleSolidEnd(const O:TBallObstacle):Double;
begin if O.Kind=boBreakable then Result:=O.Hit else Result:=O.Retire;end;
function FlightClearsObstacle(const F:TBallFlight;const O:TBallObstacle):Boolean;
var First,Last:Double;Clipped:TBallFlight;
  function Clear(const S:TBallFlight;Depth:Integer):Boolean;
  var A,B:TBallPoint;L,R,DX,DY,MinX,MaxX,MinY,MaxY,OX1,OX2,OY1,OY2:Double;
    Left,Right:TBallFlight;
    function Outside(const P:TBallPoint):Boolean;
    begin Result:=BallDot(BallSub(P,O.Center),O.Normal)>=O.Radius+BALL_RADIUS-1E-9;end;
  begin
    // After arrival the target is stationary. The tangent half-plane contains
    // the whole Bezier hull, so endpoint contact is safe without a sample gap.
    if (S.StartTime>=O.Arrive-1E-9) and Outside(S.A) and Outside(S.B) and Outside(S.C) and Outside(S.D) then Exit(True);
    A:=ObstaclePoint(O,S.StartTime);B:=ObstaclePoint(O,S.EndTime);
    MinX:=Min(Min(S.A.X,S.B.X),Min(S.C.X,S.D.X));MaxX:=Max(Max(S.A.X,S.B.X),Max(S.C.X,S.D.X));
    MinY:=Min(Min(S.A.Y,S.B.Y),Min(S.C.Y,S.D.Y));MaxY:=Max(Max(S.A.Y,S.B.Y),Max(S.C.Y,S.D.Y));
    OX1:=Min(A.X,B.X);OX2:=Max(A.X,B.X);OY1:=Min(A.Y,B.Y);OY2:=Max(A.Y,B.Y);
    DX:=Max(0.0,Max(MinX-OX2,OX1-MaxX));DY:=Max(0.0,Max(MinY-OY2,OY1-MaxY));
    R:=O.Radius+BALL_RADIUS;L:=DX*DX+DY*DY;
    if L>=(R+0.00005)*(R+0.00005) then Exit(True);
    if Depth>=14 then Exit(False);
    SplitFlight(S,0.5,Left,Right);Result:=Clear(Left,Depth+1) and Clear(Right,Depth+1);
  end;
begin
  First:=Max(F.StartTime,O.Spawn);Last:=Min(F.EndTime,ObstacleSolidEnd(O));
  if Last<First then Exit(True);
  Clipped:=ClipFlight(F,First,Last);Result:=Clear(Clipped,0);
end;
end.
