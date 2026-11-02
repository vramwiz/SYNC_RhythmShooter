unit RhythmBreakoutScoreGeometry;
// 保存された曲線・矩形の前向き検証。音アクセントや逆探索結果を移動しない。
interface
uses System.SysUtils,RhythmBreakoutGeometry,RhythmBreakoutScoreTypes;
type
  TScoreControls=array[0..3] of TBreakPoint;
  // 曲線評価・連続分離・補助球の検証を生成処理と共用する。
function Finite(V:Double):Boolean;
function Near(A,B:Double):Boolean;
function MixPoint(const A,B:TBreakPoint;U:Double):TBreakPoint;
function Distance(const A,B:TBreakPoint):Double;
function UnitDirection(const A,B:TBreakPoint):TBreakPoint;
function GridX(Col:Integer):Double;
function Fold(X:Double):Double;
function KeyBefore(const Keys:TArray<TScoreKey>;Time:Double):Integer;
function KeyAt(const Keys:TArray<TScoreKey>;Time:Double;Derivative:Boolean=False):Double;
function Controls(const A,B:TScoreNode):TScoreControls;
function CurveAt(const C:TScoreControls;U:Double):TBreakPoint;
function RectangleAt(const B:TScoreBrick;ContactY,Offset:Double):TBreakBlock;
function PointRectDistance(const P:TBreakPoint;const R:TBreakBlock):Double;
function CurveClears(const C:TScoreControls;const R:TBreakBlock;Target:Boolean;Depth:Integer=0):Boolean;
procedure CheckScore(const Events:TArray<TScoreEvent>;const Nodes:TArray<TScoreNode>;const Bricks:TArray<TScoreBrick>;
  const Shifts,Paddles:TArray<TScoreKey>;ContactY,Launch,Goal,Finish,TargetSpeed,PaddleHalf:Double;SourceCount,Rows:Integer;const Cancel:TFunc<Boolean>);
function BonusRectangle(const Brick:TScoreBonus;ContactY,Offset:Double):TBreakBlock;
function ExtraSegments(const Ball:TScoreExtraBall):TArray<TBreakSegment>;
implementation
uses System.Math,System.Generics.Collections;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

function Near(A,B:Double):Boolean;
begin Result:=Abs(A-B)<1E-7;
end;

function MixPoint(const A,B:TBreakPoint;U:Double):TBreakPoint;
begin Result:=BreakPoint(A.X+(B.X-A.X)*U,A.Y+(B.Y-A.Y)*U);
end;

function Distance(const A,B:TBreakPoint):Double;
begin Result:=Hypot(B.X-A.X,B.Y-A.Y);
end;

function UnitDirection(const A,B:TBreakPoint):TBreakPoint;
var
  D:Double;
begin D:=Distance(A,B);
  if D<1E-12 then raise Exception.Create('Score has a zero flight');
  Result:=BreakPoint((B.X-A.X)/D,(B.Y-A.Y)/D);
end;

function GridX(Col:Integer):Double;
begin Result:=0.15+0.144*Col;
end;

function Fold(X:Double):Double;
var
  W,U:Double;
begin W:=BREAK_WIDTH-2*BREAK_RADIUS;
  U:=X-BREAK_RADIUS;
  U:=U-Floor(U/(2*W))*2*W;
  if U>W then U:=2*W-U;
  Result:=BREAK_RADIUS+U;
end;

function KeyBefore(const Keys:TArray<TScoreKey>;Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(Keys);
  while A<B do begin M:=(A+B) div 2;
    if Keys[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=Max(0,A-1);
end;

function KeyAt(const Keys:TArray<TScoreKey>;Time:Double;Derivative:Boolean):Double;
var
  I:Integer;
  U,D:Double;
begin
  Result:=0;
  if Length(Keys)=0 then Exit;
  I:=KeyBefore(Keys,Time);
  if I=High(Keys) then begin if not Derivative then Result:=Keys[I].Value;
    Exit;
  end;
  D:=Keys[I+1].Time-Keys[I].Time;
  U:=EnsureRange((Time-Keys[I].Time)/D,0.0,1.0);
  if Derivative then Result:=(Keys[I+1].Value-Keys[I].Value)*6*U*(1-U)/D
  else Result:=Keys[I].Value+(Keys[I+1].Value-Keys[I].Value)*U*U*(3-2*U);
end;

function Controls(const A,B:TScoreNode):TScoreControls;
var
  D:TBreakPoint;
  T:Double;
begin
  if (A.Kind=snCatch) and (B.Kind=snServe) and Near(A.P.X,B.P.X) and Near(A.P.Y,B.P.Y) then begin Result[0]:=A.P;
    Result[1]:=A.P;
    Result[2]:=A.P;
    Result[3]:=A.P;
    Exit;
  end;
  D:=UnitDirection(A.P,B.P);
  T:=(B.Time-A.Time)/3;
  Result[0]:=A.P;
  Result[3]:=B.P;
  Result[1]:=BreakPoint(A.P.X+D.X*A.Speed*T,A.P.Y+D.Y*A.Speed*T);
  Result[2]:=BreakPoint(B.P.X-D.X*B.Speed*T,B.P.Y-D.Y*B.Speed*T);
end;

function CurveAt(const C:TScoreControls;U:Double):TBreakPoint;
var
  V:Double;
begin U:=EnsureRange(U,0.0,1.0);
  V:=1-U;
  Result:=BreakPoint(C[0].X*V*V*V+3*C[1].X*V*V*U+3*C[2].X*V*U*U+C[3].X*U*U*U,C[0].Y*V*V*V+3*C[1].Y*V*V*U+3*C[2].Y*V*U*U+C[3].Y*U*U*U);
end;

function RectangleAt(const B:TScoreBrick;ContactY,Offset:Double):TBreakBlock;
begin
  Result.Left:=GridX(B.Col)-SCORE_BRICK_W/2;
  Result.Right:=Result.Left+SCORE_BRICK_W;
  Result.Bottom:=ContactY-BREAK_RADIUS-B.Row*SCORE_PITCH+Offset;
  Result.Top:=Result.Bottom-SCORE_BRICK_H;
  Result.Time:=B.Time;
  Result.Strength:=B.Strength;
  Result.Source:=B.Source;
end;

function PointRectDistance(const P:TBreakPoint;const R:TBreakBlock):Double;
begin Result:=Hypot(Max(0.0,Max(R.Left-P.X,P.X-R.Right)),Max(0.0,Max(R.Top-P.Y,P.Y-R.Bottom)));
end;

function CurveClears(const C:TScoreControls;const R:TBreakBlock;Target:Boolean;Depth:Integer):Boolean;
var
  I:Integer;
  MinX,MaxX,MinY,MaxY,DX,DY,Plane:Double;
  Left,Right:TScoreControls;
  A,B,D,E,F,P:TBreakPoint;
  Strict:Boolean;
begin
  MinX:=C[0].X;
  MaxX:=MinX;
  MinY:=C[0].Y;
  MaxY:=MinY;
  for I:=1 to 3 do begin MinX:=Min(MinX,C[I].X);
    MaxX:=Max(MaxX,C[I].X);
    MinY:=Min(MinY,C[I].Y);
    MaxY:=Max(MaxY,C[I].Y);
  end;
  DX:=Max(0.0,Max(R.Left-MaxX,MinX-R.Right));
  DY:=Max(0.0,Max(R.Top-MaxY,MinY-R.Bottom));
  if Hypot(DX,DY)>BREAK_RADIUS+1E-8 then Exit(True);
  Plane:=R.Bottom+BREAK_RADIUS;
  Strict:=MaxY>Plane+1E-9;
  if MinY>=Plane-1E-9 then begin
    if Target then Exit(True);
    // Nonnegative Bernstein coefficients prove interior separation. The two
    // endpoints are checked separately, so a tangent to another brick fails.
    if Strict and (PointRectDistance(C[0],R)>BREAK_RADIUS+1E-8) and
    (PointRectDistance(C[3],R)>BREAK_RADIUS+1E-8) then Exit(True);
  end;
  if Depth>=16 then Exit(False);
  A:=MixPoint(C[0],C[1],0.5);
  B:=MixPoint(C[1],C[2],0.5);
  D:=MixPoint(C[2],C[3],0.5);
  E:=MixPoint(A,B,0.5);
  F:=MixPoint(B,D,0.5);
  P:=MixPoint(E,F,0.5);
  Left[0]:=C[0];
  Left[1]:=A;
  Left[2]:=E;
  Left[3]:=P;
  Right[0]:=P;
  Right[1]:=F;
  Right[2]:=D;
  Right[3]:=C[3];
  Result:=CurveClears(Left,R,Target,Depth+1) and CurveClears(Right,R,Target,Depth+1);
end;
// Independent forward validator: it consumes only persisted geometry/timing.
// It never invokes the inverse search or moves an accent to a contact.

procedure CheckScore(const Events:TArray<TScoreEvent>;const Nodes:TArray<TScoreNode>;const Bricks:TArray<TScoreBrick>;
  const Shifts,Paddles:TArray<TScoreKey>;ContactY,Launch,Goal,Finish,TargetSpeed,PaddleHalf:Double;SourceCount,Rows:Integer;const Cancel:TFunc<Boolean>);
var
  I,J,K,PreviousSource:Integer;
  N:TScoreNode;
  A,B:TBreakPoint;
  C,Relative:TScoreControls;
  R:TBreakBlock;
  D,L,U,V,Average,FirstAverage,LastAverage,OffsetA,OffsetB,VelocityA,VelocityB,Minimum:Double;
  Seen:TDictionary<Integer,Boolean>;
  Hits,RowCounts:TArray<Integer>;
  Event:TScoreEvent;
  FirstLive,RowLimit,Lo,Hi,M:Integer;
  Hold:Boolean;
  procedure Need(Value:Boolean;const Msg:string);
  begin if not Value then raise Exception.Create('ブロック崩し反射譜検証: '+Msg);
  end;
  function EventFor(Source:Integer):TScoreEvent;
  var
    Lo,Hi,M:Integer;
  begin Lo:=0;
    Hi:=Length(Events);
    while Lo<Hi do begin M:=(Lo+Hi) div 2;
      if Events[M].Source<Source then Lo:=M+1 else Hi:=M;
    end;
    Need((Lo<Length(Events)) and (Events[Lo].Source=Source),'音候補参照');
    Result:=Events[Lo];
  end;
  function SparseSpan(First,Last:Double):Boolean;
  var
    A,B,M:Integer;
    LowTime,HighTime:Double;
  begin
    A:=0;
    B:=Length(Events);
    while A<B do begin M:=(A+B) div 2;
      if Events[M].Time<Last-1E-8 then A:=M+1 else B:=M;
    end;
    LowTime:=0;
    if A>0 then LowTime:=Events[A-1].Time;
    HighTime:=Goal;
    if A<Length(Events) then HighTime:=Events[A].Time;
    Result:=(HighTime-LowTime>=1.6) and (First>LowTime+1E-8) and (Last<=HighTime+1E-8);
  end;
  procedure Keys(const Values:TArray<TScoreKey>;Paddle:Boolean);
  var
    K:Integer;
    DT:Double;
  begin
    Need((Length(Values)>0) and (Values[0].Time=0),'キーの開始');
    for K:=0 to High(Values) do begin
      Need(Finite(Values[K].Time) and Finite(Values[K].Value) and (Values[K].Time>=0) and (Values[K].Time<=Finish),'キーの数値');
      if K>0 then begin DT:=Values[K].Time-Values[K-1].Time;
        Need(DT>1E-9,'キー順序');
        if Paddle then Need(1.5*Abs(Values[K].Value-Values[K-1].Value)/DT<=5.0,'パドル速度')
        else Need(Values[K].Value>=Values[K-1].Value,'群が下方へ動くこと');
      end;
      if Paddle then Need((Values[K].Value>=PaddleHalf) and (Values[K].Value<=BREAK_WIDTH-PaddleHalf),'パドル範囲')
      else Need((Values[K].Value>=0) and (Values[K].Value<=(Rows-1)*SCORE_PITCH+1E-8),'群移動範囲');
    end;
  end;
begin
  Need((Length(Bricks)<=SCORE_MAX_BRICKS) and (Length(Nodes)<=3*SCORE_MAX_BRICKS+2) and (Length(Events)<=100000),'件数');
  Need(Finite(ContactY) and Finite(Launch) and Finite(Goal) and Finite(Finish) and Finite(TargetSpeed),'計画数値');
  Need((TargetSpeed>=0.9-1E-8) and (TargetSpeed<=1.7+1E-8),'自然な基準速度');
  PreviousSource:=-1;
  for I:=0 to High(Events) do begin
    Need(Finite(Events[I].Time) and Finite(Events[I].Strength) and (Events[I].Time>1E-5) and (Events[I].Source>PreviousSource) and (Events[I].Source<SourceCount) and
    (Events[I].Strength>=0) and (Events[I].Strength<=1),'元候補');
    if I>0 then Need(Events[I].Time>Events[I-1].Time,'元音時刻の順序');
    PreviousSource:=Events[I].Source;
  end;
  if Length(Bricks)=0 then begin Need((Length(Nodes)=0) and (Length(Events)=0) and (Length(Shifts)=0) and (Length(Paddles)=0) and (Goal=0) and (Launch=0) and (Rows=0),'無音');
    Exit;
  end;
  Need(Length(Events)>0,'Missing score accents');
  Need((Rows>0) and (Rows<=800) and (Length(Nodes)>=3) and (Launch>=0) and (Goal=Events[High(Events)].Time) and Near(Finish,Goal+0.55),'終端');
  Need((ContactY>BREAK_RADIUS+SCORE_BRICK_H) and (ContactY<BREAK_PADDLE_Y),'接触面');
  Keys(Shifts,False);
  Keys(Paddles,True);
  SetLength(Hits,Length(Bricks));
  SetLength(RowCounts,Rows);
  Seen:=TDictionary<Integer,Boolean>.Create;
  try
    for I:=0 to High(Bricks) do begin
      Need((Bricks[I].Row>=0) and (Bricks[I].Row<Rows) and (Bricks[I].Col>=0) and (Bricks[I].Col<SCORE_COLUMNS),'整列セル');
      K:=Bricks[I].Row*SCORE_COLUMNS+Bricks[I].Col;
      Need(not Seen.ContainsKey(K),'ブロック重複');
      Seen.Add(K,True);
      Inc(RowCounts[Bricks[I].Row]);
      Event:=EventFor(Bricks[I].Source);
      Need((Bricks[I].Time=Event.Time) and (Bricks[I].Strength=Event.Strength),'破壊音');
      if I>0 then Need((Bricks[I].Time>Bricks[I-1].Time) and (Bricks[I].Row>=Bricks[I-1].Row),'下段から全破壊');
      Need(Near(KeyAt(Shifts,Bricks[I].Time),Bricks[I].Row*SCORE_PITCH) and (Abs(KeyAt(Shifts,Bricks[I].Time,True))<1E-7),'群の接触位置/速度');
    end;
    for I:=1 to Rows-1 do Need(RowCounts[I]=SCORE_COLUMNS,'上段が密な整列群であること');
  finally Seen.Free;
  end;
  Need((Nodes[0].Kind=snLaunch) and Near(Nodes[0].Time,Launch) and Near(Nodes[0].P.Y,BREAK_PADDLE_Y) and (Nodes[0].Speed=0),'発射');
  Need((Nodes[High(Nodes)].Kind=snFinish) and (Nodes[High(Nodes)].Speed=0) and (Nodes[High(Nodes)-1].Kind=snBlock) and (Nodes[High(Nodes)-1].Time=Goal),'終了');
  PreviousSource:=-1;
  for I:=0 to High(Nodes) do begin
    if Assigned(Cancel) and Cancel() then Abort;
    N:=Nodes[I];
    Need(Finite(N.Time) and Finite(N.P.X) and Finite(N.P.Y) and Finite(N.Speed) and (N.Speed>=0),'反射数値');
    Need((N.P.X>=BREAK_RADIUS-1E-8) and (N.P.X<=BREAK_WIDTH-BREAK_RADIUS+1E-8) and (N.P.Y>=BREAK_RADIUS) and (N.P.Y<=BREAK_PADDLE_Y+1E-8),'球の境界');
    if N.Kind in [snBlock,snWall,snPaddle,snCorner] then begin
      if N.Source>=0 then begin Event:=EventFor(N.Source);
        Need((N.Source>PreviousSource) and (Event.Time=N.Time),'反射音時刻');
        PreviousSource:=N.Source;
      end
      else Need((N.Kind<>snBlock) and SparseSpan(N.Time-1E-9,N.Time),'補助反射は疎音区間だけ');
      Need(N.Speed>0,'途中停止');
    end;
    if I>0 then Need(N.Time>Nodes[I-1].Time+1E-9,'反射時刻順序');
    if (I>0) and (I<High(Nodes)) then begin
      FirstAverage:=Distance(Nodes[I-1].P,N.P)/(N.Time-Nodes[I-1].Time);
      LastAverage:=FirstAverage;
      if (N.Kind<>snCatch) and (I<High(Nodes)-1) then LastAverage:=Min(LastAverage,Distance(N.P,Nodes[I+1].P)/(Nodes[I+1].Time-N.Time));
      if N.Kind=snServe then LastAverage:=0 else LastAverage:=0.95*LastAverage;
      Need(Near(N.Speed,LastAverage),'保存した速度プロファイル');
    end;
    if (I>0) and (I<High(Nodes)) then begin
      if N.Kind=snCatch then begin
        A:=UnitDirection(Nodes[I-1].P,N.P);
        Need((N.Source<0) and Near(N.P.Y,BREAK_PADDLE_Y) and (A.Y>0) and (N.Speed>0) and (Nodes[I+1].Kind=snServe) and
        Near(N.P.X,Nodes[I+1].P.X) and Near(N.P.Y,Nodes[I+1].P.Y) and SparseSpan(N.Time,Nodes[I+1].Time),'パドル捕球/待機');
        Need(Abs(N.P.X-KeyAt(Paddles,N.Time))<=PaddleHalf+1E-8,'捕球位置');
      end else if N.Kind=snServe then begin
        B:=UnitDirection(N.P,Nodes[I+1].P);
        Need((Nodes[I-1].Kind=snCatch) and (N.Speed=0) and (N.Source<0) and Near(N.P.X,Nodes[I-1].P.X) and Near(N.P.Y,BREAK_PADDLE_Y) and (B.Y<0),'連続位置からの再発射');
        Need(Abs(N.P.X-KeyAt(Paddles,N.Time))<=PaddleHalf+1E-8,'再発射位置');
      end else begin
        A:=UnitDirection(Nodes[I-1].P,N.P);
        B:=UnitDirection(N.P,Nodes[I+1].P);
        case N.Kind of
          snBlock:begin
            Need((N.Brick>=0) and (N.Brick<Length(Bricks)),'破壊参照');
            Inc(Hits[N.Brick]);
            R:=RectangleAt(Bricks[N.Brick],ContactY,KeyAt(Shifts,N.Time));
            Need((Bricks[N.Brick].Time=N.Time) and (N.Source=Bricks[N.Brick].Source) and Near(N.P.Y,R.Bottom+BREAK_RADIUS) and (N.P.X>=R.Left) and (N.P.X<=R.Right) and (A.Y<0),'矩形接触');
            Need(Near(A.X,B.X) and Near(A.Y,-B.Y),'ブロック反射');
          end;
          snWall:begin Need((Near(N.P.X,BREAK_RADIUS) and (A.X<0)) or (Near(N.P.X,BREAK_WIDTH-BREAK_RADIUS) and (A.X>0)),'壁接触');
            Need(Near(A.X,-B.X) and Near(A.Y,B.Y),'壁反射');
          end;
          snPaddle:Need(Near(N.P.Y,BREAK_PADDLE_Y) and (A.Y>0) and (B.Y<0) and (Abs(N.P.X-KeyAt(Paddles,N.Time))<=PaddleHalf+1E-8),'音同期パドル');
          snCorner:Need(Near(N.P.X,BREAK_RADIUS) and Near(N.P.Y,BREAK_RADIUS) and (A.X<=0) and (A.Y<0) and Near(A.X,-B.X) and Near(A.Y,-B.Y),'上/横壁の補助反射');
          else Need(False,'接触のない方向変更');
        end;
      end;
    end;
    if I=High(Nodes) then Continue;
    D:=Nodes[I+1].Time-N.Time;
    Need(D>1E-9,'区間時間');
    L:=Distance(N.P,Nodes[I+1].P);
    Average:=L/D;
    C:=Controls(N,Nodes[I+1]);
    Hold:=(N.Kind=snCatch) and (Nodes[I+1].Kind=snServe);
    if Hold then begin
      Need(L<1E-9,'待機中のワープ');
      for K:=0 to High(Paddles) do if (Paddles[K].Time>=N.Time) and (Paddles[K].Time<=Nodes[I+1].Time) then Need(Near(Paddles[K].Value,KeyAt(Paddles,N.Time)),'捕球中のパドル保持');
    end else begin
      if I<High(Nodes)-1 then Need((Average>=TargetSpeed*0.32-1E-8) and (Average<=Min(3.0,TargetSpeed*1.9)+1E-8),'区間速度の範囲');
      Need((N.Speed<=3*Average+1E-8) and (Nodes[I+1].Speed<=3*Average+1E-8),'単調な速度補間');
      // All control points lie on one straight line in traversal order.
      U:=N.Speed/(3*Average);
      V:=1-Nodes[I+1].Speed/(3*Average);
      Need((U>=0) and (U<=V+1E-8) and (V<=1),'直線上の前進');
      for K:=0 to 3 do Need((C[K].X>=BREAK_RADIUS-1E-8) and (C[K].X<=BREAK_WIDTH-BREAK_RADIUS+1E-8) and (C[K].Y>=BREAK_RADIUS) and (C[K].Y<=BREAK_PADDLE_Y+1E-8),'制御点の境界');
      if I<High(Nodes)-1 then begin
        if (I>0) and (N.Kind<>snServe) then begin FirstAverage:=Distance(Nodes[I-1].P,N.P)/(N.Time-Nodes[I-1].Time);
          Need(Max(Average/FirstAverage,FirstAverage/Average)<=1.6+1E-7,'急な速度差');
        end;
      end;
    end;
    OffsetA:=KeyAt(Shifts,N.Time);
    OffsetB:=KeyAt(Shifts,Nodes[I+1].Time);
    VelocityA:=KeyAt(Shifts,N.Time,True);
    VelocityB:=KeyAt(Shifts,Nodes[I+1].Time,True);
    Relative:=C;
    Relative[0].Y:=Relative[0].Y-OffsetA;
    Relative[1].Y:=Relative[1].Y-OffsetA-VelocityA*D/3;
    Relative[2].Y:=Relative[2].Y-OffsetB+VelocityB*D/3;
    Relative[3].Y:=Relative[3].Y-OffsetB;
    K:=KeyBefore(Shifts,N.Time+1E-8);
    if K<High(Shifts) then Need(Shifts[K+1].Time>=Nodes[I+1].Time-1E-8,'区間内の移動キー');
    Minimum:=Relative[0].Y;
    for K:=1 to 3 do Minimum:=Min(Minimum,Relative[K].Y);
    RowLimit:=Floor((ContactY-Minimum+1E-8)/SCORE_PITCH);
    Lo:=0;
    Hi:=Length(Bricks);
    while Lo<Hi do begin M:=(Lo+Hi) div 2;
      if Bricks[M].Time<=N.Time+1E-9 then Lo:=M+1 else Hi:=M;
    end;
    FirstLive:=Lo;
    // Rows above this bound are separated from the whole relative Bezier hull
    // by a horizontal half-plane. Only the nearby live rows need subdivision.
    for J:=FirstLive to High(Bricks) do begin
      if Bricks[J].Row>RowLimit then Break;
      R:=RectangleAt(Bricks[J],ContactY,0);
      Need(CurveClears(Relative,R,(Nodes[I+1].Kind=snBlock) and (Nodes[I+1].Brick=J)),'移動群への先行接触');
    end;
  end;
  for I:=0 to High(Hits) do Need(Hits[I]=1,'最後の音で残ブロック0');
end;

function BonusRectangle(const Brick:TScoreBonus;ContactY,Offset:Double):TBreakBlock;
begin
  Result.Left:=Brick.X-0.006;
  Result.Right:=Brick.X+0.006;
  Result.Bottom:=ContactY-BREAK_RADIUS-Brick.Row*SCORE_PITCH+Offset;
  Result.Top:=Result.Bottom-SCORE_BRICK_H;
  Result.Time:=Brick.Time;
  Result.Strength:=0.7;
  Result.Source:=-1;
end;

function ExtraSegments(const Ball:TScoreExtraBall):TArray<TBreakSegment>;
var
  N:Integer;
  X,U,T:Double;
  P:TBreakPoint;
begin
  SetLength(Result,3);
  Result[0]:=Default(TBreakSegment);
  Result[0].First:=Ball.Launch;
  Result[0].Last:=Ball.Hit;
  Result[0].A:=Ball.A;
  Result[0].B:=Ball.B;
  Result[0].Kind:=beBlock;
  Result[0].Block:=Ball.Target;
  N:=1;
  X:=2*Ball.B.X-Ball.A.X;
  T:=Ball.Hit;
  P:=Ball.B;
  if (X<BREAK_RADIUS) or (X>BREAK_WIDTH-BREAK_RADIUS) then begin
    U:=BREAK_RADIUS;
    if X>BREAK_WIDTH-BREAK_RADIUS then U:=BREAK_WIDTH-BREAK_RADIUS;
    U:=(U-Ball.B.X)/(X-Ball.B.X);
    Result[N]:=Default(TBreakSegment);
    Result[N].First:=T;
    Result[N].Last:=Ball.Hit+(Ball.Catch-Ball.Hit)*U;
    Result[N].A:=P;
    Result[N].B:=BreakPoint(Ball.B.X+(X-Ball.B.X)*U,Ball.B.Y+(BREAK_PADDLE_Y-Ball.B.Y)*U);
    Result[N].Kind:=beWallX;
    Result[N].Block:=-1;
    T:=Result[N].Last;
    P:=Result[N].B;
    Inc(N);
  end;
  Result[N]:=Default(TBreakSegment);
  Result[N].First:=T;
  Result[N].Last:=Ball.Catch;
  Result[N].A:=P;
  Result[N].B:=Ball.C;
  Result[N].Kind:=bePaddle;
  Result[N].Block:=-1;
  SetLength(Result,N+1);
end;

end.
