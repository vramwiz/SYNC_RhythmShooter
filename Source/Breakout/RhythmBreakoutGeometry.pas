unit RhythmBreakoutGeometry;
// Independent forward checks for the reverse planner; no audio or JSON I/O.
interface
uses System.SysUtils;
const
  BREAK_WIDTH=1.6;
  BREAK_HEIGHT=1.0;
  BREAK_RADIUS=0.014;
  BREAK_PADDLE_Y=0.886;
  BREAK_PADDLE_HALF=0.105;
  BREAK_PADDLE_HALF_V6=0.095;
  BREAK_PADDLE_HALF_NEW=0.080;
  BREAK_BLOCK_W=0.064;
  BREAK_BLOCK_H=0.028;
  BREAK_MAX_SEGMENTS=24000;
type
  TBreakPoint=record
    X,Y:Double;
  end;
  TBreakBlock=record
    Left,Right,Top,Bottom,Time,Strength:Double;
    Source:Integer;
  end;
  TBreakEnd=(beBlock,beWallX,beTop,beCorner,bePaddle,beFinish);
  TBreakSegment=record
    First,Last:Double;
    A,B:TBreakPoint;
    Kind:TBreakEnd;
    Block:Integer;
  end;
  TBreakPaddle=record
    Time,X:Double;
  end;
function BreakPoint(X,Y:Double):TBreakPoint;
function BreakSegmentPoint(const S:TBreakSegment;Time:Double):TBreakPoint;
function BreakPaddleAt(const Keys:TArray<TBreakPaddle>;Time:Double):Double;
function BreakRectDistance(const A,B:TBreakPoint;const R:TBreakBlock):Double;
function BreakOverlap(const A,B:TBreakBlock):Boolean;
procedure ValidateBreakout(const Blocks:TArray<TBreakBlock>;const Segments:TArray<TBreakSegment>;
  const Paddles:TArray<TBreakPaddle>;BaseSpeed,Launch,Goal,Finish:Double;const Cancel:TFunc<Boolean> = nil);
implementation
uses System.Math;

function BreakPoint(X,Y:Double):TBreakPoint;
begin Result.X:=X;
  Result.Y:=Y;
end;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

function Near(A,B:Double):Boolean;
begin Result:=Abs(A-B)<1E-6;
end;

function BreakSegmentPoint(const S:TBreakSegment;Time:Double):TBreakPoint;
var
  U:Double;
begin U:=EnsureRange((Time-S.First)/(S.Last-S.First),0.0,1.0);
  Result:=BreakPoint(S.A.X+(S.B.X-S.A.X)*U,S.A.Y+(S.B.Y-S.A.Y)*U);
end;

function BreakPaddleAt(const Keys:TArray<TBreakPaddle>;Time:Double):Double;
var
  A,B,M:Integer;
  U:Double;
begin
  Result:=BREAK_WIDTH/2;
  if Length(Keys)=0 then Exit;
  A:=0;
  B:=Length(Keys);
  while A<B do begin M:=(A+B) div 2;
    if Keys[M].Time<=Time then A:=M+1 else B:=M;
  end;
  M:=Max(0,A-1);
  Result:=Keys[M].X;
  if M=High(Keys) then Exit;
  U:=EnsureRange((Time-Keys[M].Time)/(Keys[M+1].Time-Keys[M].Time),0.0,1.0);
  U:=U*U*(3-2*U);
  Result:=Result+(Keys[M+1].X-Result)*U;
end;

function BreakOverlap(const A,B:TBreakBlock):Boolean;
begin Result:=(A.Left<B.Right+0.008) and (A.Right>B.Left-0.008) and (A.Top<B.Bottom+0.008) and (A.Bottom>B.Top-0.008);
end;

function PointRect(const P:TBreakPoint;const R:TBreakBlock):Double;
begin Result:=Hypot(Max(0.0,Max(R.Left-P.X,P.X-R.Right)),Max(0.0,Max(R.Top-P.Y,P.Y-R.Bottom)));
end;

function PointSegment(const P,A,B:TBreakPoint):Double;
var
  DX,DY,U:Double;
begin DX:=B.X-A.X;
  DY:=B.Y-A.Y;
  U:=EnsureRange(((P.X-A.X)*DX+(P.Y-A.Y)*DY)/(DX*DX+DY*DY),0.0,1.0);
  Result:=Hypot(P.X-A.X-U*DX,P.Y-A.Y-U*DY);
end;

function BreakRectDistance(const A,B:TBreakPoint;const R:TBreakBlock):Double;
var
  Low,High:Double;
  procedure Clip(U,D,MinV,MaxV:Double);
  var
    X,Y,V:Double;
  begin
    if Abs(D)<1E-15 then begin if (U<MinV) or (U>MaxV) then Low:=2;
      Exit;
    end;
    X:=(MinV-U)/D;
    Y:=(MaxV-U)/D;
    if X>Y then begin V:=X;
      X:=Y;
      Y:=V;
    end;
    Low:=Max(Low,X);
    High:=Min(High,Y);
  end;
begin
  Low:=0;
  High:=1;
  Clip(A.X,B.X-A.X,R.Left,R.Right);
  Clip(A.Y,B.Y-A.Y,R.Top,R.Bottom);
  if Low<=High then Exit(0);
  Result:=Min(PointRect(A,R),PointRect(B,R));
  Result:=Min(Result,PointSegment(BreakPoint(R.Left,R.Top),A,B));
  Result:=Min(Result,PointSegment(BreakPoint(R.Right,R.Top),A,B));
  Result:=Min(Result,PointSegment(BreakPoint(R.Left,R.Bottom),A,B));
  Result:=Min(Result,PointSegment(BreakPoint(R.Right,R.Bottom),A,B));
end;

procedure ValidateBreakout(const Blocks:TArray<TBreakBlock>;const Segments:TArray<TBreakSegment>;
  const Paddles:TArray<TBreakPaddle>;BaseSpeed,Launch,Goal,Finish:Double;const Cancel:TFunc<Boolean>);
var
  I,J:Integer;
  S:TBreakSegment;
  R:TBreakBlock;
  V,N:TBreakPoint;
  Speed,NextSpeed,D,Ratio,PX:Double;
  Hits:TArray<Integer>;
  Target,FlipX,FlipY:Boolean;
  procedure Need(Value:Boolean;const MessageText:string);
  begin if not Value then raise Exception.Create('ブロック崩し検証: '+MessageText);
  end;
  function Velocity(const F:TBreakSegment):TBreakPoint;
  begin Need(Finite(F.First) and Finite(F.Last) and (F.Last-F.First>1E-9),'区間時刻');
    Result:=BreakPoint((F.B.X-F.A.X)/(F.Last-F.First),(F.B.Y-F.A.Y)/(F.Last-F.First));
  end;
  procedure PointInside(const P:TBreakPoint);
  begin Need(Finite(P.X) and Finite(P.Y) and (P.X>=BREAK_RADIUS-1E-6) and (P.X<=BREAK_WIDTH-BREAK_RADIUS+1E-6) and (P.Y>=BREAK_RADIUS-1E-6) and (P.Y<=BREAK_PADDLE_Y+1E-6),'球の境界');
  end;
begin
  Need(Finite(BaseSpeed) and Finite(Launch) and Finite(Goal) and Finite(Finish) and (Launch>=0) and (Finish>=Goal),'計画範囲');
  Need((Length(Blocks)<=24) and (Length(Segments)<=BREAK_MAX_SEGMENTS),'件数上限');
  if Length(Blocks)=0 then begin Need((Length(Segments)=0) and (Length(Paddles)=0) and (BaseSpeed=0) and (Goal=0) and (Launch=0),'無音計画');
    Exit;
  end;
  Need((BaseSpeed>=0.94-1E-6) and (BaseSpeed<=1.22+1E-6) and (Length(Segments)>0),'基準速度');
  Need(Near(Goal,Blocks[High(Blocks)].Time) and Near(Finish,Goal+0.55) and Near(Launch,Segments[0].First) and Near(Finish,Segments[High(Segments)].Last),'開始/全破壊/終端');
  SetLength(Hits,Length(Blocks));
  for I:=0 to High(Blocks) do begin
    R:=Blocks[I];
    Need(Finite(R.Left) and Finite(R.Right) and Finite(R.Top) and Finite(R.Bottom) and Finite(R.Time) and Finite(R.Strength),'ブロック数値');
    Need((R.Left>=0.02) and (R.Right<=BREAK_WIDTH-0.02) and (R.Top>=BREAK_RADIUS) and (R.Bottom<BREAK_PADDLE_Y-BREAK_RADIUS) and
    Near(R.Right-R.Left,BREAK_BLOCK_W) and Near(R.Bottom-R.Top,BREAK_BLOCK_H) and (R.Strength>=0) and (R.Strength<=1),'ブロック範囲');
    if I>0 then Need((R.Time>Blocks[I-1].Time) and (R.Source>Blocks[I-1].Source),'破壊順序');
    for J:=0 to I-1 do Need(not BreakOverlap(R,Blocks[J]),'ブロック重複');
  end;
  Need((Length(Paddles)>0) and (Length(Paddles)<=Length(Segments)+2) and (Paddles[0].Time=0),'パドル経路');
  for I:=0 to High(Paddles) do begin
    Need(Finite(Paddles[I].X) and Finite(Paddles[I].Time) and (Paddles[I].X>=BREAK_PADDLE_HALF) and (Paddles[I].X<=BREAK_WIDTH-BREAK_PADDLE_HALF) and
    (Paddles[I].Time>=0) and (Paddles[I].Time<=Finish),'パドル範囲');
    if I>0 then begin D:=Paddles[I].Time-Paddles[I-1].Time;
      Need(D>1E-9,'パドル時刻順序');
      Need(1.5*Abs(Paddles[I].X-Paddles[I-1].X)/D<=2.1+1E-6,'パドル速度');
    end;
  end;
  Need(Near(BreakPaddleAt(Paddles,0),BreakPaddleAt(Paddles,Launch)),'発射待機中のパドル');
  for I:=0 to High(Segments) do begin
    if Assigned(Cancel) and Cancel() then Abort;
    S:=Segments[I];
    V:=Velocity(S);
    Speed:=Hypot(V.X,V.Y);
    PointInside(S.A);
    PointInside(S.B);
    Need(Finite(Speed) and (Speed>=BaseSpeed*0.90-1E-6) and (Speed<=BaseSpeed*1.10+1E-6),'球速');
    if I>0 then Need(Near(Segments[I-1].Last,S.First) and Near(Segments[I-1].B.X,S.A.X) and Near(Segments[I-1].B.Y,S.A.Y),'連続性');
    case S.Kind of
      beBlock:begin
        Need((S.Block>=0) and (S.Block<Length(Blocks)),'破壊参照');
        R:=Blocks[S.Block];
        Inc(Hits[S.Block]);
        Need(Near(S.Last,R.Time) and Near(S.B.Y,R.Bottom+BREAK_RADIUS) and (S.B.X>=R.Left) and (S.B.X<=R.Right) and (V.Y<0),'球/矩形接触時刻');
      end;
      beWallX:Need((Near(S.B.X,BREAK_RADIUS) and (V.X<0)) or (Near(S.B.X,BREAK_WIDTH-BREAK_RADIUS) and (V.X>0)),'左右壁接触');
      beTop:Need(Near(S.B.Y,BREAK_RADIUS) and (V.Y<0),'上壁接触');
      beCorner:Need(((Near(S.B.X,BREAK_RADIUS) and (V.X<0)) or (Near(S.B.X,BREAK_WIDTH-BREAK_RADIUS) and (V.X>0))) and
      ((Near(S.B.Y,BREAK_RADIUS) and (V.Y<0)) or (Near(S.B.Y,BREAK_PADDLE_Y) and (V.Y>0))),'角の接触');
      bePaddle:begin PX:=BreakPaddleAt(Paddles,S.Last);
        Need(Near(S.B.Y,BREAK_PADDLE_Y) and (V.Y>0) and (Abs(S.B.X-PX)<=BREAK_PADDLE_HALF+1E-6),'パドル接触');
      end;
      beFinish:Need(I=High(Segments),'終端位置');
    end;
    if (S.Kind=beCorner) and Near(S.B.Y,BREAK_PADDLE_Y) then Need(Abs(S.B.X-BreakPaddleAt(Paddles,S.Last))<=BREAK_PADDLE_HALF+1E-6,'角でのパドル接触');
    if I<High(Segments) then begin
      N:=Velocity(Segments[I+1]);
      NextSpeed:=Hypot(N.X,N.Y);
      if S.Kind=bePaddle then begin Ratio:=NextSpeed/Speed;
        Need((N.Y<0) and (Ratio<=1.23) and (Ratio>=1/1.23),'パドル打返し');
      end
      else begin
        FlipX:=S.Kind in [beWallX,beCorner];
        FlipY:=S.Kind in [beBlock,beTop,beCorner];
        if FlipX then V.X:=-V.X;
        if FlipY then V.Y:=-V.Y;
        Need(Near(N.X,V.X) and Near(N.Y,V.Y),'接触面での反射/空中方向転換');
      end;
    end;
    for J:=0 to High(Blocks) do begin
      R:=Blocks[J];
      if R.Time<=S.First+1E-8 then Continue;
      D:=BreakRectDistance(S.A,S.B,R);
      Target:=(S.Kind=beBlock) and (S.Block=J);
      if Target then Need(D>=BREAK_RADIUS-1E-7,'接触前の矩形侵入') else Need(D>BREAK_RADIUS+1E-7,'未破壊ブロックへの先行接触');
    end;
  end;
  V:=Velocity(Segments[0]);
  Need(Near(Segments[0].A.Y,BREAK_PADDLE_Y) and (V.Y<0) and
  (Abs(Segments[0].A.X-BreakPaddleAt(Paddles,Launch))<=BREAK_PADDLE_HALF+1E-6),'発射位置');
  for I:=0 to High(Hits) do Need(Hits[I]=1,'最後の音で残ブロック0');
  Need(Segments[High(Segments)].Kind=beFinish,'終了区間');
end;
end.
