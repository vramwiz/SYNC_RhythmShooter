unit RhythmBreakoutScore;
// Fixed accent score plus precomputed, unsynchronised multiball intervals.
interface
uses System.SysUtils,System.JSON,RhythmAudio,RhythmPlanRef,RhythmBreakoutGeometry,RhythmBreakoutAction;
const SCORE_COLUMNS=10;SCORE_PITCH=0.041;SCORE_BRICK_W=0.126;SCORE_BRICK_H=0.028;SCORE_MAX_BRICKS=8000;
type
  TScoreKind=(snBlock,snWall,snPaddle,snLaunch,snFinish,snCorner,snCatch,snServe);
  TScoreEvent=record Time,Strength:Double;Source:Integer;end;
  TScoreNode=record Time,Speed:Double;P:TBreakPoint;Kind:TScoreKind;Source,Brick,Row,Col:Integer;end;
  TScoreBrick=record Time,Strength:Double;Source,Row,Col:Integer;end;
  TScoreKey=record Time,Value:Double;end;
  TScoreItem=record Source:Integer;Drop,Take,Finish:Double;end;
  TScoreBonus=record X,Time:Double;Row:Integer;end;
  TScoreExtraBall=record Launch,Hit,Catch:Double;A,B,C:TBreakPoint;Target,Item:Integer;end;
  TBreakScorePlan=class
  private
    FAction:TBreakActionPlan;
    FEvents:TArray<TScoreEvent>;FNodes:TArray<TScoreNode>;FBricks:TArray<TScoreBrick>;FShifts,FPaddles:TArray<TScoreKey>;
    FItems:TArray<TScoreItem>;FBonus:TArray<TScoreBonus>;FExtra:TArray<TScoreExtraBall>;
    FPaddleHalf,FDuration,FSoundEnd,FContactY,FTarget,FLaunch,FGoal,FEnd,FBallEnd:Double;FSourceCount,FRows,FTrials:Integer;
    procedure Attempt(Seed:Integer;const Cancel:TFunc<Boolean>);
    procedure FinalizeScore(const Reverse:TArray<TScoreNode>);
    procedure Verify(const Cancel:TFunc<Boolean> = nil);
    procedure MakeShows(const Cancel:TFunc<Boolean>);
    procedure VerifyShows(const Cancel:TFunc<Boolean>);
    function ClearsMain(const Brick:TScoreBonus;const Cancel:TFunc<Boolean>):Boolean;
    function CheckExtra(const Ball:TScoreExtraBall):Boolean;
    function GetTotalCount:Integer;function GetItemCount:Integer;function GetExtraCount:Integer;
    function GetCount:Integer;function GetSyncCount:Integer;function GetAuxCount:Integer;function GetCatchCount:Integer;
    function ExportCoreData(Audio:TRhythmAudio;Version:Integer):TJSONObject;
  public
    destructor Destroy;override;
    procedure Enhance(Audio:TRhythmAudio;ClearWave:Boolean;const Cancel:TFunc<Boolean>);
    function RadiusAt(Time:Double):Double;
    function BrickVisible(Index:Integer;Time:Double):Boolean;
    function ExtraLaunch(Index:Integer):Double;
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>;AllowShows:Boolean=True;PaddleHalf:Double=BREAK_PADDLE_HALF):TBreakScorePlan;static;
    class function Load(Root:TJSONObject;Audio:TRhythmAudio):TBreakScorePlan;static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    function ExportData(Audio:TRhythmAudio;Version:Integer=4):TJSONObject;
    function PositionAt(Time:Double):TBreakPoint;
    function PaddleAt(Time:Double):Double;
    function BrickAt(Index:Integer;Time:Double):TBreakBlock;
    function BrickRow(Index:Integer):Integer;
    function HeldAt(Time:Double):Boolean;
    function Item(Index:Integer):TScoreItem;
    function ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Opacity:Double):Boolean;
    property BlockCount:Integer read GetTotalCount;property ItemCount:Integer read GetItemCount;property ExtraCount:Integer read GetExtraCount;
    property Count:Integer read GetCount;property SyncCount:Integer read GetSyncCount;
    property LaunchTime:Double read FLaunch;property GoalTime:Double read FGoal;property EndTime:Double read FEnd;property BallEnd:Double read FBallEnd;
    property Trials:Integer read FTrials;property PaddleHalf:Double read FPaddleHalf;
    property AuxiliaryCount:Integer read GetAuxCount;property CatchCount:Integer read GetCatchCount;
  end;
implementation
uses System.Math,System.Generics.Collections,System.Generics.Defaults,RhythmStyles,RhythmPreparedData;
type
  TScoreControls=array[0..3] of TBreakPoint;
  TScorePick=record Index:Integer;Average,Cost:Double;end;
  TScoreState=record Index,Mask,Serial:Integer;Time:Double;P:TBreakPoint;Average,Cost:Double;Path:TArray<TScoreNode>;end;
function Finite(V:Double):Boolean;begin Result:=not IsNan(V) and not IsInfinite(V);end;
function Near(A,B:Double):Boolean;begin Result:=Abs(A-B)<1E-7;end;
function MixPoint(const A,B:TBreakPoint;U:Double):TBreakPoint;
begin Result:=BreakPoint(A.X+(B.X-A.X)*U,A.Y+(B.Y-A.Y)*U);end;
function Distance(const A,B:TBreakPoint):Double;begin Result:=Hypot(B.X-A.X,B.Y-A.Y);end;
function UnitDirection(const A,B:TBreakPoint):TBreakPoint;
var D:Double;begin D:=Distance(A,B);if D<1E-12 then raise Exception.Create('Score has a zero flight');Result:=BreakPoint((B.X-A.X)/D,(B.Y-A.Y)/D);end;
function GridX(Col:Integer):Double;begin Result:=0.15+0.144*Col;end;
function Fold(X:Double):Double;
var W,U:Double;begin W:=BREAK_WIDTH-2*BREAK_RADIUS;U:=X-BREAK_RADIUS;U:=U-Floor(U/(2*W))*2*W;if U>W then U:=2*W-U;Result:=BREAK_RADIUS+U;end;
function KeyBefore(const Keys:TArray<TScoreKey>;Time:Double):Integer;
var A,B,M:Integer;begin A:=0;B:=Length(Keys);while A<B do begin M:=(A+B) div 2;if Keys[M].Time<=Time then A:=M+1 else B:=M;end;Result:=Max(0,A-1);end;
function KeyAt(const Keys:TArray<TScoreKey>;Time:Double;Derivative:Boolean=False):Double;
var I:Integer;U,D:Double;
begin
  Result:=0;if Length(Keys)=0 then Exit;I:=KeyBefore(Keys,Time);if I=High(Keys) then begin if not Derivative then Result:=Keys[I].Value;Exit;end;
  D:=Keys[I+1].Time-Keys[I].Time;U:=EnsureRange((Time-Keys[I].Time)/D,0.0,1.0);
  if Derivative then Result:=(Keys[I+1].Value-Keys[I].Value)*6*U*(1-U)/D
  else Result:=Keys[I].Value+(Keys[I+1].Value-Keys[I].Value)*U*U*(3-2*U);
end;
function Controls(const A,B:TScoreNode):TScoreControls;
var D:TBreakPoint;T:Double;
begin
  if (A.Kind=snCatch) and (B.Kind=snServe) and Near(A.P.X,B.P.X) and Near(A.P.Y,B.P.Y) then begin Result[0]:=A.P;Result[1]:=A.P;Result[2]:=A.P;Result[3]:=A.P;Exit;end;
  D:=UnitDirection(A.P,B.P);T:=(B.Time-A.Time)/3;Result[0]:=A.P;Result[3]:=B.P;
  Result[1]:=BreakPoint(A.P.X+D.X*A.Speed*T,A.P.Y+D.Y*A.Speed*T);
  Result[2]:=BreakPoint(B.P.X-D.X*B.Speed*T,B.P.Y-D.Y*B.Speed*T);
end;
function CurveAt(const C:TScoreControls;U:Double):TBreakPoint;
var V:Double;begin U:=EnsureRange(U,0.0,1.0);V:=1-U;Result:=BreakPoint(C[0].X*V*V*V+3*C[1].X*V*V*U+3*C[2].X*V*U*U+C[3].X*U*U*U,C[0].Y*V*V*V+3*C[1].Y*V*V*U+3*C[2].Y*V*U*U+C[3].Y*U*U*U);end;
function RectangleAt(const B:TScoreBrick;ContactY,Offset:Double):TBreakBlock;
begin
  Result.Left:=GridX(B.Col)-SCORE_BRICK_W/2;Result.Right:=Result.Left+SCORE_BRICK_W;
  Result.Bottom:=ContactY-BREAK_RADIUS-B.Row*SCORE_PITCH+Offset;Result.Top:=Result.Bottom-SCORE_BRICK_H;
  Result.Time:=B.Time;Result.Strength:=B.Strength;Result.Source:=B.Source;
end;
function PointRectDistance(const P:TBreakPoint;const R:TBreakBlock):Double;
begin Result:=Hypot(Max(0.0,Max(R.Left-P.X,P.X-R.Right)),Max(0.0,Max(R.Top-P.Y,P.Y-R.Bottom)));end;
function CurveClears(const C:TScoreControls;const R:TBreakBlock;Target:Boolean;Depth:Integer=0):Boolean;
var I:Integer;MinX,MaxX,MinY,MaxY,DX,DY,Plane:Double;Left,Right:TScoreControls;A,B,D,E,F,P:TBreakPoint;Strict:Boolean;
begin
  MinX:=C[0].X;MaxX:=MinX;MinY:=C[0].Y;MaxY:=MinY;
  for I:=1 to 3 do begin MinX:=Min(MinX,C[I].X);MaxX:=Max(MaxX,C[I].X);MinY:=Min(MinY,C[I].Y);MaxY:=Max(MaxY,C[I].Y);end;
  DX:=Max(0.0,Max(R.Left-MaxX,MinX-R.Right));DY:=Max(0.0,Max(R.Top-MaxY,MinY-R.Bottom));
  if Hypot(DX,DY)>BREAK_RADIUS+1E-8 then Exit(True);
  Plane:=R.Bottom+BREAK_RADIUS;Strict:=MaxY>Plane+1E-9;
  if MinY>=Plane-1E-9 then begin
    if Target then Exit(True);
    // Nonnegative Bernstein coefficients prove interior separation. The two
    // endpoints are checked separately, so a tangent to another brick fails.
    if Strict and (PointRectDistance(C[0],R)>BREAK_RADIUS+1E-8) and
      (PointRectDistance(C[3],R)>BREAK_RADIUS+1E-8) then Exit(True);
  end;
  if Depth>=16 then Exit(False);
  A:=MixPoint(C[0],C[1],0.5);B:=MixPoint(C[1],C[2],0.5);D:=MixPoint(C[2],C[3],0.5);E:=MixPoint(A,B,0.5);F:=MixPoint(B,D,0.5);P:=MixPoint(E,F,0.5);
  Left[0]:=C[0];Left[1]:=A;Left[2]:=E;Left[3]:=P;Right[0]:=P;Right[1]:=F;Right[2]:=D;Right[3]:=C[3];
  Result:=CurveClears(Left,R,Target,Depth+1) and CurveClears(Right,R,Target,Depth+1);
end;
// Independent forward validator: it consumes only persisted geometry/timing.
// It never invokes the inverse search or moves an accent to a contact.
procedure CheckScore(const Events:TArray<TScoreEvent>;const Nodes:TArray<TScoreNode>;const Bricks:TArray<TScoreBrick>;
  const Shifts,Paddles:TArray<TScoreKey>;ContactY,Launch,Goal,Finish,TargetSpeed,PaddleHalf:Double;SourceCount,Rows:Integer;const Cancel:TFunc<Boolean>);
var I,J,K,PreviousSource:Integer;N:TScoreNode;A,B:TBreakPoint;C,Relative:TScoreControls;R:TBreakBlock;
  D,L,U,V,Average,FirstAverage,LastAverage,OffsetA,OffsetB,VelocityA,VelocityB,Minimum:Double;
  Seen:TDictionary<Integer,Boolean>;Hits,RowCounts:TArray<Integer>;Event:TScoreEvent;FirstLive,RowLimit,Lo,Hi,M:Integer;Hold:Boolean;
  procedure Need(Value:Boolean;const Msg:string);begin if not Value then raise Exception.Create('ブロック崩し反射譜検証: '+Msg);end;
  function EventFor(Source:Integer):TScoreEvent;
  var Lo,Hi,M:Integer;
  begin Lo:=0;Hi:=Length(Events);while Lo<Hi do begin M:=(Lo+Hi) div 2;if Events[M].Source<Source then Lo:=M+1 else Hi:=M;end;
    Need((Lo<Length(Events)) and (Events[Lo].Source=Source),'音候補参照');Result:=Events[Lo];end;
  function SparseSpan(First,Last:Double):Boolean;
  var A,B,M:Integer;LowTime,HighTime:Double;
  begin
    A:=0;B:=Length(Events);while A<B do begin M:=(A+B) div 2;if Events[M].Time<Last-1E-8 then A:=M+1 else B:=M;end;
    LowTime:=0;if A>0 then LowTime:=Events[A-1].Time;HighTime:=Goal;if A<Length(Events) then HighTime:=Events[A].Time;
    Result:=(HighTime-LowTime>=1.6) and (First>LowTime+1E-8) and (Last<=HighTime+1E-8);
  end;
  procedure Keys(const Values:TArray<TScoreKey>;Paddle:Boolean);
  var K:Integer;DT:Double;
  begin
    Need((Length(Values)>0) and (Values[0].Time=0),'キーの開始');
    for K:=0 to High(Values) do begin
      Need(Finite(Values[K].Time) and Finite(Values[K].Value) and (Values[K].Time>=0) and (Values[K].Time<=Finish),'キーの数値');
      if K>0 then begin DT:=Values[K].Time-Values[K-1].Time;Need(DT>1E-9,'キー順序');
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
      (Events[I].Strength>=0) and (Events[I].Strength<=1),'元候補');if I>0 then Need(Events[I].Time>Events[I-1].Time,'元音時刻の順序');PreviousSource:=Events[I].Source;
  end;
  if Length(Bricks)=0 then begin Need((Length(Nodes)=0) and (Length(Events)=0) and (Length(Shifts)=0) and (Length(Paddles)=0) and (Goal=0) and (Launch=0) and (Rows=0),'無音');Exit;end;
  Need(Length(Events)>0,'Missing score accents');
  Need((Rows>0) and (Rows<=800) and (Length(Nodes)>=3) and (Launch>=0) and (Goal=Events[High(Events)].Time) and Near(Finish,Goal+0.55),'終端');
  Need((ContactY>BREAK_RADIUS+SCORE_BRICK_H) and (ContactY<BREAK_PADDLE_Y),'接触面');Keys(Shifts,False);Keys(Paddles,True);
  SetLength(Hits,Length(Bricks));SetLength(RowCounts,Rows);Seen:=TDictionary<Integer,Boolean>.Create;
  try
    for I:=0 to High(Bricks) do begin
      Need((Bricks[I].Row>=0) and (Bricks[I].Row<Rows) and (Bricks[I].Col>=0) and (Bricks[I].Col<SCORE_COLUMNS),'整列セル');
      K:=Bricks[I].Row*SCORE_COLUMNS+Bricks[I].Col;Need(not Seen.ContainsKey(K),'ブロック重複');Seen.Add(K,True);Inc(RowCounts[Bricks[I].Row]);
      Event:=EventFor(Bricks[I].Source);Need((Bricks[I].Time=Event.Time) and (Bricks[I].Strength=Event.Strength),'破壊音');
      if I>0 then Need((Bricks[I].Time>Bricks[I-1].Time) and (Bricks[I].Row>=Bricks[I-1].Row),'下段から全破壊');
      Need(Near(KeyAt(Shifts,Bricks[I].Time),Bricks[I].Row*SCORE_PITCH) and (Abs(KeyAt(Shifts,Bricks[I].Time,True))<1E-7),'群の接触位置/速度');
    end;
    for I:=1 to Rows-1 do Need(RowCounts[I]=SCORE_COLUMNS,'上段が密な整列群であること');
  finally Seen.Free;end;
  Need((Nodes[0].Kind=snLaunch) and Near(Nodes[0].Time,Launch) and Near(Nodes[0].P.Y,BREAK_PADDLE_Y) and (Nodes[0].Speed=0),'発射');
  Need((Nodes[High(Nodes)].Kind=snFinish) and (Nodes[High(Nodes)].Speed=0) and (Nodes[High(Nodes)-1].Kind=snBlock) and (Nodes[High(Nodes)-1].Time=Goal),'終了');
  PreviousSource:=-1;
  for I:=0 to High(Nodes) do begin
    if Assigned(Cancel) and Cancel() then Abort;N:=Nodes[I];
    Need(Finite(N.Time) and Finite(N.P.X) and Finite(N.P.Y) and Finite(N.Speed) and (N.Speed>=0),'反射数値');
    Need((N.P.X>=BREAK_RADIUS-1E-8) and (N.P.X<=BREAK_WIDTH-BREAK_RADIUS+1E-8) and (N.P.Y>=BREAK_RADIUS) and (N.P.Y<=BREAK_PADDLE_Y+1E-8),'球の境界');
    if N.Kind in [snBlock,snWall,snPaddle,snCorner] then begin
      if N.Source>=0 then begin Event:=EventFor(N.Source);Need((N.Source>PreviousSource) and (Event.Time=N.Time),'反射音時刻');PreviousSource:=N.Source;end
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
      A:=UnitDirection(Nodes[I-1].P,N.P);B:=UnitDirection(N.P,Nodes[I+1].P);
      case N.Kind of
        snBlock:begin
          Need((N.Brick>=0) and (N.Brick<Length(Bricks)),'破壊参照');Inc(Hits[N.Brick]);R:=RectangleAt(Bricks[N.Brick],ContactY,KeyAt(Shifts,N.Time));
          Need((Bricks[N.Brick].Time=N.Time) and (N.Source=Bricks[N.Brick].Source) and Near(N.P.Y,R.Bottom+BREAK_RADIUS) and (N.P.X>=R.Left) and (N.P.X<=R.Right) and (A.Y<0),'矩形接触');
          Need(Near(A.X,B.X) and Near(A.Y,-B.Y),'ブロック反射');
        end;
        snWall:begin Need((Near(N.P.X,BREAK_RADIUS) and (A.X<0)) or (Near(N.P.X,BREAK_WIDTH-BREAK_RADIUS) and (A.X>0)),'壁接触');Need(Near(A.X,-B.X) and Near(A.Y,B.Y),'壁反射');end;
        snPaddle:Need(Near(N.P.Y,BREAK_PADDLE_Y) and (A.Y>0) and (B.Y<0) and (Abs(N.P.X-KeyAt(Paddles,N.Time))<=PaddleHalf+1E-8),'音同期パドル');
        snCorner:Need(Near(N.P.X,BREAK_RADIUS) and Near(N.P.Y,BREAK_RADIUS) and (A.X<=0) and (A.Y<0) and Near(A.X,-B.X) and Near(A.Y,-B.Y),'上/横壁の補助反射');
      else Need(False,'接触のない方向変更');end;
      end;
    end;
    if I=High(Nodes) then Continue;
    D:=Nodes[I+1].Time-N.Time;Need(D>1E-9,'区間時間');L:=Distance(N.P,Nodes[I+1].P);Average:=L/D;C:=Controls(N,Nodes[I+1]);
    Hold:=(N.Kind=snCatch) and (Nodes[I+1].Kind=snServe);
    if Hold then begin
      Need(L<1E-9,'待機中のワープ');
      for K:=0 to High(Paddles) do if (Paddles[K].Time>=N.Time) and (Paddles[K].Time<=Nodes[I+1].Time) then Need(Near(Paddles[K].Value,KeyAt(Paddles,N.Time)),'捕球中のパドル保持');
    end else begin
    if I<High(Nodes)-1 then Need((Average>=TargetSpeed*0.32-1E-8) and (Average<=Min(3.0,TargetSpeed*1.9)+1E-8),'区間速度の範囲');
    Need((N.Speed<=3*Average+1E-8) and (Nodes[I+1].Speed<=3*Average+1E-8),'単調な速度補間');
    // All control points lie on one straight line in traversal order.
    U:=N.Speed/(3*Average);V:=1-Nodes[I+1].Speed/(3*Average);Need((U>=0) and (U<=V+1E-8) and (V<=1),'直線上の前進');
    for K:=0 to 3 do Need((C[K].X>=BREAK_RADIUS-1E-8) and (C[K].X<=BREAK_WIDTH-BREAK_RADIUS+1E-8) and (C[K].Y>=BREAK_RADIUS) and (C[K].Y<=BREAK_PADDLE_Y+1E-8),'制御点の境界');
    if I<High(Nodes)-1 then begin
      if (I>0) and (N.Kind<>snServe) then begin FirstAverage:=Distance(Nodes[I-1].P,N.P)/(N.Time-Nodes[I-1].Time);Need(Max(Average/FirstAverage,FirstAverage/Average)<=1.6+1E-7,'急な速度差');end;
    end;
    end;
    OffsetA:=KeyAt(Shifts,N.Time);OffsetB:=KeyAt(Shifts,Nodes[I+1].Time);VelocityA:=KeyAt(Shifts,N.Time,True);VelocityB:=KeyAt(Shifts,Nodes[I+1].Time,True);
    Relative:=C;Relative[0].Y:=Relative[0].Y-OffsetA;Relative[1].Y:=Relative[1].Y-OffsetA-VelocityA*D/3;
    Relative[2].Y:=Relative[2].Y-OffsetB+VelocityB*D/3;Relative[3].Y:=Relative[3].Y-OffsetB;
    K:=KeyBefore(Shifts,N.Time+1E-8);if K<High(Shifts) then Need(Shifts[K+1].Time>=Nodes[I+1].Time-1E-8,'区間内の移動キー');
    Minimum:=Relative[0].Y;for K:=1 to 3 do Minimum:=Min(Minimum,Relative[K].Y);
    RowLimit:=Floor((ContactY-Minimum+1E-8)/SCORE_PITCH);
    Lo:=0;Hi:=Length(Bricks);while Lo<Hi do begin M:=(Lo+Hi) div 2;if Bricks[M].Time<=N.Time+1E-9 then Lo:=M+1 else Hi:=M;end;FirstLive:=Lo;
    // Rows above this bound are separated from the whole relative Bezier hull
    // by a horizontal half-plane. Only the nearby live rows need subdivision.
    for J:=FirstLive to High(Bricks) do begin
      if Bricks[J].Row>RowLimit then Break;
      R:=RectangleAt(Bricks[J],ContactY,0);Need(CurveClears(Relative,R,(Nodes[I+1].Kind=snBlock) and (Nodes[I+1].Brick=J)),'移動群への先行接触');
    end;
  end;
  for I:=0 to High(Hits) do Need(Hits[I]=1,'最後の音で残ブロック0');
end;
procedure TBreakScorePlan.Attempt(Seed:Integer;const Cancel:TFunc<Boolean>);
var Reverse:TList<TScoreNode>;Outcomes,Next:TList<TScoreState>;Seen:TDictionary<string,Boolean>;
  State,Best,S,Z:TScoreState;Beam,Prior:TArray<TScoreState>;Picks:TArray<TScorePick>;Pick:TScorePick;
  N,Last:TScoreNode;Virtual,B:TBreakPoint;Row,Depth,Col,I,J,Serial,LastIndex:Integer;D,Serve:Double;Key:string;
  procedure Check;begin if Assigned(Cancel) and Cancel() then Abort;end;
  function BeforeTime(Time:Double):Integer;
  var A,B,M:Integer;begin A:=0;B:=Length(FEvents);while A<B do begin M:=(A+B) div 2;if FEvents[M].Time<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
  function SparseWindow(Time:Double;out Index:Integer;out LowTime,HighTime:Double):Boolean;
  begin
    Index:=BeforeTime(Time-1E-8);LowTime:=0;if Index>=0 then LowTime:=FEvents[Index].Time;
    HighTime:=Time;if Index<High(FEvents) then HighTime:=FEvents[Index+1].Time;Result:=HighTime-LowTime>=1.6;
  end;
  function SparseSpan(First,Last:Double):Boolean;
  var I:Integer;L,H:Double;
  begin Result:=SparseWindow(Last,I,L,H) and (First>L+1E-8) and (Last<=H+1E-8);end;
  function MakeNode(const P:TBreakPoint;Index:Integer;Kind:TScoreKind;Row,Col:Integer):TScoreNode;
  begin Result:=Default(TScoreNode);Result.P:=P;Result.Time:=FEvents[Index].Time;Result.Source:=FEvents[Index].Source;Result.Kind:=Kind;Result.Row:=Row;Result.Col:=Col;Result.Brick:=-1;end;
  function Append(const Path:TArray<TScoreNode>;const Node:TScoreNode):TArray<TScoreNode>;
  begin Result:=Copy(Path,0,Length(Path));SetLength(Result,Length(Result)+1);Result[High(Result)]:=Node;end;
  function AuxNode(const P:TBreakPoint;Time:Double;Kind:TScoreKind):TScoreNode;
  begin Result:=Default(TScoreNode);Result.P:=P;Result.Time:=Time;Result.Source:=-1;Result.Kind:=Kind;Result.Brick:=-1;Result.Row:=-1;Result.Col:=-1;end;
  procedure AppendReverse(const Path:TArray<TScoreNode>);
  var N:TScoreNode;
  begin for N in Path do begin
    if (Reverse.Count>0) and (N.Kind=snServe) and Near(Reverse[Reverse.Count-1].Time,N.Time) then Reverse[Reverse.Count-1]:=N else Reverse.Add(N);
    if Reverse.Count>3*SCORE_MAX_BRICKS+2 then raise Exception.Create('反射計画区間の上限です');
  end;end;
  function FindPicks(Time,Length,NextAverage:Double):TArray<TScorePick>;
  var J,Q,Lo,Hi,Center,Sample,MaxSample:Integer;DT,V,Cost,MinV,MaxV:Double;P:TScorePick;
    procedure Consider(J:Integer);
    begin
      if (J<0) or (J>=System.Length(FEvents)) then Exit;if FEvents[J].Time>=Time-1E-9 then Exit;DT:=Time-FEvents[J].Time;V:=Length/DT;
      if (V<MinV) or (V>MaxV) then Exit;
      Cost:=Abs(Ln(V/FTarget))+0.015*(BeforeTime(Time-1E-9)-J);P.Index:=J;P.Average:=V;P.Cost:=Cost;
      if System.Length(Result)>0 then if Result[0].Index=J then Exit;
      if System.Length(Result)>1 then if Result[1].Index=J then Exit;
      if System.Length(Result)=0 then begin SetLength(Result,1);Result[0]:=P;end
      else if Cost<Result[0].Cost then begin SetLength(Result,2);Result[1]:=Result[0];Result[0]:=P;end
      else if (System.Length(Result)=1) or (Cost<Result[1].Cost) then begin SetLength(Result,2);Result[1]:=P;end;
    end;
  begin
    Result:=nil;Check;MinV:=FTarget*0.32;MaxV:=Min(3.0,FTarget*1.9);
    if NextAverage>0 then begin MinV:=Max(MinV,NextAverage/1.6);MaxV:=Min(MaxV,NextAverage*1.6);end;
    Lo:=Max(0,BeforeTime(Time-Length/MinV)-1);Hi:=Min(BeforeTime(Time-1E-9),BeforeTime(Time-Length/MaxV)+1);if Lo>Hi then Exit;
    MaxSample:=Min(63,Hi-Lo);
    // Fixed-size time-index search also bounds adversarial ultra-dense input.
    for Sample:=MaxSample downto 0 do begin
      J:=Lo;if MaxSample>0 then J:=Lo+(Hi-Lo)*Sample div MaxSample;Consider(J);
    end;
    Center:=BeforeTime(Time-Length/FTarget);for Q:=-4 to 4 do Consider(Center+Q);
  end;
  function PriorPaddle(const Block:TBreakPoint;Index:Integer;const Future:TBreakPoint;NextAverage:Double;const Path:TArray<TScoreNode>):TArray<TScoreState>;
  var Destinations:array[0..1] of TBreakPoint;Kinds:array[0..1] of TScoreKind;States,Found:TArray<TScoreState>;Count,K,J:Integer;
    Unfolded,Wall,U,D,AuxTime:Double;S,Z:TScoreState;Choices:TArray<TScorePick>;P:TScorePick;
  begin
    Unfolded:=2*Block.X-Future.X;Count:=0;
    if (Unfolded<BREAK_RADIUS) or (Unfolded>BREAK_WIDTH-BREAK_RADIUS) then begin
      Wall:=BREAK_RADIUS;if Unfolded>BREAK_WIDTH-BREAK_RADIUS then Wall:=BREAK_WIDTH-BREAK_RADIUS;U:=(Wall-Block.X)/(Unfolded-Block.X);
      Destinations[0]:=BreakPoint(Wall,FContactY+(BREAK_PADDLE_Y-FContactY)*U);Kinds[0]:=snWall;Inc(Count);
    end;
    Destinations[Count]:=BreakPoint(Fold(Unfolded),BREAK_PADDLE_Y);Kinds[Count]:=snPaddle;Inc(Count);
    SetLength(States,1);States[0]:=Default(TScoreState);States[0].Index:=Index;States[0].Time:=FEvents[Index].Time;States[0].P:=Block;States[0].Average:=NextAverage;States[0].Path:=Copy(Path,0,Length(Path));
    for K:=0 to Count-1 do begin
      Found:=nil;
      for S in States do begin
        D:=Distance(S.P,Destinations[K]);Choices:=FindPicks(S.Time,D,S.Average);
        for P in Choices do begin
          Z:=Default(TScoreState);Z.Index:=P.Index;Z.Time:=FEvents[P.Index].Time;Z.P:=Destinations[K];Z.Average:=P.Average;Z.Cost:=S.Cost+P.Cost;
          Z.Path:=Append(S.Path,MakeNode(Z.P,Z.Index,Kinds[K],-1,-1));J:=Length(Found);SetLength(Found,J+1);Found[J]:=Z;
        end;
        AuxTime:=S.Time-D/FTarget;
        if (Length(Choices)=0) and (AuxTime>=0) and ((S.Average<=0) or (Max(S.Average/FTarget,FTarget/S.Average)<=1.6)) and
          (SparseSpan(AuxTime,S.Time) or ((Kinds[K]=snPaddle) and (BeforeTime(S.Time-1E-8)<0))) then begin
          Z:=Default(TScoreState);Z.Index:=BeforeTime(AuxTime);Z.Time:=AuxTime;Z.P:=Destinations[K];Z.Average:=FTarget;Z.Cost:=S.Cost+0.25;
          Z.Path:=Append(S.Path,AuxNode(Z.P,AuxTime,Kinds[K]));J:=Length(Found);SetLength(Found,J+1);Found[J]:=Z;
        end;
      end;
      States:=Found;if Length(States)=0 then Break;
    end;Result:=States;
  end;
  function SparseBridge(const S:TScoreState;const Block:TBreakPoint;Col,Row:Integer):TArray<TScoreState>;
  var Index,J,K,N,Nominal:Integer;LowTime,HighTime,Total,D,Corner,FlightLow,FlightHigh,Flight,LoopSpeed,Average,Time,Half,CatchTime:Double;
    Path:TArray<TScoreNode>;Prior:TArray<TScoreState>;Z:TScoreState;Serve:TScoreNode;
  begin
    Result:=nil;if not SparseWindow(S.Time,Index,LowTime,HighTime) or (Index<0) then Exit;
    Total:=S.Time-LowTime;D:=Distance(S.P,Block);Corner:=Distance(S.P,BreakPoint(BREAK_RADIUS,BREAK_RADIUS));
    if S.P.X<=0.105+1E-9 then begin
      Nominal:=Floor((Total-D/FTarget)*FTarget/(2*Corner));
      for K:=-2 to 2 do begin
        Check;N:=Max(1,Nominal+K);if N>1024 then Continue;
        FlightLow:=Max(D/Min(3.0,FTarget*1.9),Total-2*Corner*N/(FTarget*0.9));
        FlightHigh:=Min(D/(FTarget*0.32),Total-2*Corner*N/(FTarget*1.1));if (FlightLow>FlightHigh) or (FlightHigh<=0) then Continue;
        Flight:=EnsureRange(D/FTarget,FlightLow,FlightHigh);LoopSpeed:=2*Corner*N/(Total-Flight);Average:=D/Flight;
        if ((S.Average>0) and (Max(S.Average/LoopSpeed,LoopSpeed/S.Average)>1.6)) or (Max(Average/LoopSpeed,LoopSpeed/Average)>1.6) then Continue;
        Path:=Copy(S.Path,0,Length(S.Path));Time:=S.Time;Half:=Corner/LoopSpeed;
        for J:=0 to N-1 do begin Time:=Time-Half;Path:=Append(Path,AuxNode(BreakPoint(BREAK_RADIUS,BREAK_RADIUS),Time,snCorner));Time:=Time-Half;Path:=Append(Path,AuxNode(S.P,Time,snPaddle));end;
        Path[High(Path)].Time:=LowTime+Flight;Path:=Append(Path,MakeNode(Block,Index,snBlock,Row,Col));
        Prior:=PriorPaddle(Block,Index,S.P,Average,Path);
        for Z in Prior do begin J:=Length(Result);SetLength(Result,J+1);Result[J]:=Z;Result[J].Cost:=S.Cost+Z.Cost+0.2+0.002*N;Result[J].Mask:=S.Mask or (1 shl Col);end;
        Break;
      end;
    end;
    // Priority two: a contact-based catch, stationary hold, continuous re-serve.
    if Length(Result)=0 then begin
      CatchTime:=LowTime+D/FTarget;
      if (CatchTime<S.Time-0.15) and SparseSpan(CatchTime,S.Time) then begin
        Path:=Copy(S.Path,0,Length(S.Path));Serve:=AuxNode(S.P,S.Time,snServe);
        if (Length(Path)>0) and Near(Path[High(Path)].Time,S.Time) then Path[High(Path)]:=Serve else Path:=Append(Path,Serve);
        Path:=Append(Path,AuxNode(S.P,CatchTime,snCatch));Path:=Append(Path,MakeNode(Block,Index,snBlock,Row,Col));Prior:=PriorPaddle(Block,Index,S.P,FTarget,Path);
        for Z in Prior do begin J:=Length(Result);SetLength(Result,J+1);Result[J]:=Z;Result[J].Cost:=S.Cost+Z.Cost+20;Result[J].Mask:=S.Mask or (1 shl Col);end;
      end;
    end;
  end;
begin
  Check;Reverse:=TList<TScoreNode>.Create;Outcomes:=TList<TScoreState>.Create;Next:=TList<TScoreState>.Create;Seen:=TDictionary<string,Boolean>.Create;
  try
    Serial:=0;LastIndex:=High(FEvents);Col:=(Seed*3+4) mod SCORE_COLUMNS;B:=BreakPoint(GridX(Col),FContactY);
    case Seed mod 4 of 0:Virtual:=BreakPoint(0.30,BREAK_PADDLE_Y);1:Virtual:=BreakPoint(0.65,BREAK_PADDLE_Y);2:Virtual:=BreakPoint(1.0,BREAK_PADDLE_Y);else Virtual:=BreakPoint(1.35,BREAK_PADDLE_Y);end;
    if FEvents[LastIndex].Time<1 then Virtual.X:=B.X;
    Last:=MakeNode(B,LastIndex,snBlock,0,Col);Reverse.Add(Last);Prior:=PriorPaddle(B,LastIndex,Virtual,0,nil);
    if Length(Prior)=0 then begin
      D:=Distance(B,Virtual);Serve:=Max(0.0,Last.Time-D/FTarget);N:=Default(TScoreNode);N.P:=BreakPoint(Fold(2*B.X-Virtual.X),BREAK_PADDLE_Y);
      if (2*B.X-Virtual.X<BREAK_RADIUS) or (2*B.X-Virtual.X>BREAK_WIDTH-BREAK_RADIUS) then raise Exception.Create('発射前の壁反射に音候補がありません');
      N.Time:=Serve;N.Source:=-1;N.Kind:=snLaunch;N.Row:=-1;N.Col:=-1;Reverse.Add(N);FinalizeScore(Reverse.ToArray);Exit;
    end;
    State:=Prior[0];for S in Prior do if S.Cost<State.Cost then State:=S;
    AppendReverse(State.Path);State.Mask:=1 shl Col;State.Path:=nil;
    for Row:=0 to 799 do begin
      Check;SetLength(Beam,1);Beam[0]:=State;Beam[0].Path:=nil;Beam[0].Cost:=0;if Row>0 then Beam[0].Mask:=0;Best:=Beam[0];Depth:=0;if Row=0 then Depth:=1;
      while Depth<SCORE_COLUMNS do begin
        Outcomes.Clear;
        for S in Beam do for Col:=0 to SCORE_COLUMNS-1 do begin
          Check;if (S.Mask and (1 shl Col))<>0 then Continue;B:=BreakPoint(GridX(Col),FContactY);D:=Distance(S.P,B);Picks:=FindPicks(S.Time,D,S.Average);
          for Pick in Picks do begin
            N:=MakeNode(B,Pick.Index,snBlock,Row,Col);Prior:=PriorPaddle(B,Pick.Index,S.P,Pick.Average,Append(S.Path,N));
            for I:=0 to High(Prior) do begin Z:=Prior[I];
              Z.Cost:=S.Cost+Pick.Cost+Z.Cost;Z.Mask:=S.Mask or (1 shl Col);Inc(Serial);Z.Serial:=Serial;Outcomes.Add(Z);
            end;
          end;
          if Length(Picks)=0 then begin
            Prior:=SparseBridge(S,B,Col,Row);
            for I:=0 to High(Prior) do begin Z:=Prior[I];Inc(Serial);Z.Serial:=Serial;Outcomes.Add(Z);end;
          end;
        end;
        if Outcomes.Count=0 then Break;
        Outcomes.Sort(TComparer<TScoreState>.Construct(function(const A,B:TScoreState):Integer
          begin
            if A.Cost<B.Cost then Exit(-1);if A.Cost>B.Cost then Exit(1);
            if A.Serial<B.Serial then Result:=-1 else if A.Serial>B.Serial then Result:=1 else Result:=0;
          end));Next.Clear;Seen.Clear;
        for S in Outcomes do begin
          Key:=IntToStr(S.Mask)+':'+IntToStr(Round(S.Time*1E6))+':'+IntToStr(Round(S.P.X*1E7));if Seen.ContainsKey(Key) then Continue;Seen.Add(Key,True);Next.Add(S);if Next.Count=16 then Break;
        end;
        Beam:=Next.ToArray;Best:=Beam[0];Inc(Depth);
      end;
      if Length(Best.Path)=0 then Break;
      AppendReverse(Best.Path);State:=Best;State.Path:=nil;
      if Best.Mask<>(1 shl SCORE_COLUMNS)-1 then Break;
    end;
    if (State.P.X<=0.105+1E-9) and SparseWindow(State.Time,I,D,Serve) then begin
      Serve:=Distance(State.P,BreakPoint(BREAK_RADIUS,BREAK_RADIUS))/FTarget;J:=Min(Min(1024,(3*SCORE_MAX_BRICKS+2-Reverse.Count) div 2),Floor((State.Time-D)/(2*Serve)));D:=State.Time;
      for I:=0 to J-1 do begin D:=D-Serve;Reverse.Add(AuxNode(BreakPoint(BREAK_RADIUS,BREAK_RADIUS),D,snCorner));D:=D-Serve;Reverse.Add(AuxNode(State.P,D,snPaddle));end;
    end;
    N:=Reverse[Reverse.Count-1];N.Kind:=snLaunch;Reverse[Reverse.Count-1]:=N;FinalizeScore(Reverse.ToArray);
  finally Reverse.Free;Outcomes.Free;Next.Free;Seen.Free;end;
end;
procedure TBreakScorePlan.FinalizeScore(const Reverse:TArray<TScoreNode>);
var Bricks:TList<TScoreBrick>;ShiftKeys,PaddleKeys:TList<TScoreKey>;I,Count,First:Integer;N,EndNode:TScoreNode;B:TScoreBrick;Key:TScoreKey;
  Averages:TArray<Double>;U:TBreakPoint;D,Speed,Limit,Tail:Double;
  function EventFor(Source:Integer):TScoreEvent;
  var A,C,M:Integer;begin A:=0;C:=Length(FEvents);while A<C do begin M:=(A+C) div 2;if FEvents[M].Source<Source then A:=M+1 else C:=M;end;Result:=FEvents[A];end;
begin
  Count:=Length(Reverse);First:=Count-1;
  // Keep the original accent clock. Omit only the opening flights when a
  // later real paddle contact can provide room for the entrance animation.
  if (FSoundEnd>=8) and (Reverse[First].Time<0.65) then for I:=Count-2 downto 1 do
    if (Reverse[I].Time>=0.65) and (Reverse[I].Kind=snPaddle) then begin First:=I;Break;end;
  Count:=First+1;SetLength(FNodes,Count);FRows:=0;
  for I:=0 to Count-1 do begin FNodes[I]:=Reverse[Count-1-I];if FNodes[I].Kind=snBlock then FRows:=Max(FRows,FNodes[I].Row+1);end;
  FNodes[0].Kind:=snLaunch;FNodes[0].Source:=-1;
  Bricks:=TList<TScoreBrick>.Create;ShiftKeys:=TList<TScoreKey>.Create;PaddleKeys:=TList<TScoreKey>.Create;
  try
    for I:=0 to High(FNodes) do if FNodes[I].Kind=snBlock then begin
      B.Row:=FRows-1-FNodes[I].Row;B.Col:=FNodes[I].Col;B.Time:=FNodes[I].Time;B.Source:=FNodes[I].Source;B.Strength:=EventFor(B.Source).Strength;
      FNodes[I].Brick:=Bricks.Count;FNodes[I].Row:=B.Row;Bricks.Add(B);
    end;FBricks:=Bricks.ToArray;
    Key.Time:=0;Key.Value:=0;ShiftKeys.Add(Key);
    for I:=1 to High(FBricks) do if FBricks[I].Row<>FBricks[I-1].Row then begin
      B:=FBricks[I-1];if ShiftKeys[ShiftKeys.Count-1].Time<B.Time then begin Key.Time:=B.Time;Key.Value:=B.Row*SCORE_PITCH;ShiftKeys.Add(Key);end;
      Key.Time:=FBricks[I].Time;Key.Value:=FBricks[I].Row*SCORE_PITCH;ShiftKeys.Add(Key);
    end;FShifts:=ShiftKeys.ToArray;
    SetLength(Averages,Count-1);for I:=0 to Count-2 do Averages[I]:=Distance(FNodes[I].P,FNodes[I+1].P)/(FNodes[I+1].Time-FNodes[I].Time);
    FNodes[0].Speed:=0;
    for I:=1 to Count-1 do begin
      if FNodes[I].Kind=snServe then FNodes[I].Speed:=0
      else begin D:=Averages[I-1];if (FNodes[I].Kind<>snCatch) and (I<Count-1) then D:=Min(D,Averages[I]);FNodes[I].Speed:=0.95*D;end;
    end;
    FLaunch:=FNodes[0].Time;FGoal:=FBricks[High(FBricks)].Time;FEnd:=FGoal+0.55;
    N:=FNodes[Count-1];U:=UnitDirection(FNodes[Count-2].P,N.P);U.Y:=-U.Y;Speed:=N.Speed;Limit:=1E10;
    if U.X>1E-12 then Limit:=Min(Limit,(BREAK_WIDTH-BREAK_RADIUS-N.P.X)/U.X) else if U.X< -1E-12 then Limit:=Min(Limit,(BREAK_RADIUS-N.P.X)/U.X);
    if U.Y>0 then Limit:=Min(Limit,(BREAK_PADDLE_Y-N.P.Y)/U.Y);
    Tail:=Min(0.35,Limit*0.8/Speed);EndNode:=Default(TScoreNode);EndNode.Kind:=snFinish;EndNode.Source:=-1;EndNode.Brick:=-1;EndNode.Row:=-1;EndNode.Col:=-1;
    EndNode.Time:=FGoal+Tail;EndNode.P:=BreakPoint(N.P.X+U.X*Speed*Tail*0.5,N.P.Y+U.Y*Speed*Tail*0.5);FBallEnd:=EndNode.Time;
    SetLength(FNodes,Count+1);FNodes[Count]:=EndNode;
    Key.Time:=0;Key.Value:=EnsureRange(FNodes[0].P.X,FPaddleHalf,BREAK_WIDTH-FPaddleHalf);PaddleKeys.Add(Key);
    if FLaunch>1E-9 then begin Key.Time:=FLaunch;PaddleKeys.Add(Key);end;
    for N in FNodes do if N.Kind in [snPaddle,snCatch,snServe] then begin Key.Time:=N.Time;Key.Value:=EnsureRange(N.P.X,FPaddleHalf,BREAK_WIDTH-FPaddleHalf);PaddleKeys.Add(Key);end;FPaddles:=PaddleKeys.ToArray;
  finally Bricks.Free;ShiftKeys.Free;PaddleKeys.Free;end;
end;
function BonusRectangle(const Brick:TScoreBonus;ContactY,Offset:Double):TBreakBlock;
begin
  Result.Left:=Brick.X-0.006;Result.Right:=Brick.X+0.006;
  Result.Bottom:=ContactY-BREAK_RADIUS-Brick.Row*SCORE_PITCH+Offset;Result.Top:=Result.Bottom-SCORE_BRICK_H;
  Result.Time:=Brick.Time;Result.Strength:=0.7;Result.Source:=-1;
end;
function ExtraSegments(const Ball:TScoreExtraBall):TArray<TBreakSegment>;
var N:Integer;X,U,T:Double;P:TBreakPoint;
begin
  SetLength(Result,3);Result[0]:=Default(TBreakSegment);Result[0].First:=Ball.Launch;Result[0].Last:=Ball.Hit;
  Result[0].A:=Ball.A;Result[0].B:=Ball.B;Result[0].Kind:=beBlock;Result[0].Block:=Ball.Target;
  N:=1;X:=2*Ball.B.X-Ball.A.X;T:=Ball.Hit;P:=Ball.B;
  if (X<BREAK_RADIUS) or (X>BREAK_WIDTH-BREAK_RADIUS) then begin
    U:=BREAK_RADIUS;if X>BREAK_WIDTH-BREAK_RADIUS then U:=BREAK_WIDTH-BREAK_RADIUS;
    U:=(U-Ball.B.X)/(X-Ball.B.X);Result[N]:=Default(TBreakSegment);
    Result[N].First:=T;Result[N].Last:=Ball.Hit+(Ball.Catch-Ball.Hit)*U;
    Result[N].A:=P;Result[N].B:=BreakPoint(Ball.B.X+(X-Ball.B.X)*U,Ball.B.Y+(BREAK_PADDLE_Y-Ball.B.Y)*U);
    Result[N].Kind:=beWallX;Result[N].Block:=-1;T:=Result[N].Last;P:=Result[N].B;Inc(N);
  end;
  Result[N]:=Default(TBreakSegment);Result[N].First:=T;Result[N].Last:=Ball.Catch;Result[N].A:=P;Result[N].B:=Ball.C;
  Result[N].Kind:=bePaddle;Result[N].Block:=-1;SetLength(Result,N+1);
end;
function TBreakScorePlan.ClearsMain(const Brick:TScoreBonus;const Cancel:TFunc<Boolean>):Boolean;
var I:Integer;D,A,B,VA,VB:Double;C:TScoreControls;R:TBreakBlock;
begin
  Result:=False;R:=BonusRectangle(Brick,FContactY,0);
  for I:=0 to High(FNodes)-1 do begin
    if Assigned(Cancel) and Cancel() then Abort;if FNodes[I].Time>=Brick.Time then Break;
    D:=FNodes[I+1].Time-FNodes[I].Time;C:=Controls(FNodes[I],FNodes[I+1]);
    A:=KeyAt(FShifts,FNodes[I].Time);B:=KeyAt(FShifts,FNodes[I+1].Time);
    VA:=KeyAt(FShifts,FNodes[I].Time,True);VB:=KeyAt(FShifts,FNodes[I+1].Time,True);
    C[0].Y:=C[0].Y-A;C[1].Y:=C[1].Y-A-VA*D/3;C[2].Y:=C[2].Y-B+VB*D/3;C[3].Y:=C[3].Y-B;
    if not CurveClears(C,R,False) then Exit;
  end;Result:=True;
end;
function TBreakScorePlan.CheckExtra(const Ball:TScoreExtraBall):Boolean;
var S:TBreakSegment;J,A,B,M,Row,FirstMain,FirstBonus:Integer;R:TBreakBlock;P:TBreakPoint;U,D:Double;Contact:Boolean;
  function Clears(Index:Integer):Boolean;
  begin
    Result:=True;R:=BrickAt(Index,S.First);if R.Time<=S.First+1E-9 then Exit;
    U:=Min(1.0,(R.Time-S.First)/(S.Last-S.First));P:=MixPoint(S.A,S.B,U);
    D:=BreakRectDistance(S.A,P,R);Contact:=(Ball.Target=Index) and (S.First<=Ball.Hit+1E-9);
    if Contact then Result:=D>=BREAK_RADIUS-1E-7 else Result:=D>BREAK_RADIUS+1E-8;
  end;
begin
  Result:=False;
  if not Near(KeyAt(FShifts,Ball.Launch),KeyAt(FShifts,Ball.Catch)) or
    (Abs(Ball.C.X-PaddleAt(Ball.Catch))>FPaddleHalf-0.006) then Exit;
  Row:=Round(KeyAt(FShifts,Ball.Launch)/SCORE_PITCH);
  // Every secondary ray is below the current bottom row. Higher rows are
  // separated by a half-plane; lower rows have already been destroyed.
  A:=0;B:=Length(FBricks);while A<B do begin M:=(A+B) div 2;if FBricks[M].Row<Row then A:=M+1 else B:=M;end;FirstMain:=A;
  A:=0;B:=Length(FBonus);while A<B do begin M:=(A+B) div 2;if FBonus[M].Row<Row then A:=M+1 else B:=M;end;FirstBonus:=A;
  for S in ExtraSegments(Ball) do begin
    J:=FirstMain;while (J<Length(FBricks)) and (FBricks[J].Row=Row) do begin if not Clears(J) then Exit;Inc(J);end;
    J:=FirstBonus;while (J<Length(FBonus)) and (FBonus[J].Row=Row) do begin if not Clears(Length(FBricks)+J) then Exit;Inc(J);end;
  end;Result:=True;
end;
procedure TBreakScorePlan.MakeShows(const Cancel:TFunc<Boolean>);
type TCandidate=record Item:TScoreItem;Weight:Double;end;
var Candidates:TList<TCandidate>;Used:TArray<Boolean>;Candidate:TCandidate;First,Last,I,J,A,B,M,Best,TryIndex:Integer;
  Earliest,Edge,Take,Finish,Weight:Double;
  procedure Check;begin if Assigned(Cancel) and Cancel() then Abort;end;
  function TryShow(const Item:TScoreItem):Boolean;
  var Bonus:TScoreBonus;Ball,Previous:TScoreExtraBall;NB,NS,Ordinal,Pass,Slot,Row,Target,Phase,VI,K,Destroyed:Integer;
    Launch,Speed,Flight,D,X:Double;NewBrick,Found,Valid,Duplicate:Boolean;
  begin
    Result:=False;NB:=Length(FBonus);NS:=Length(FExtra);Ordinal:=0;Destroyed:=0;Row:=FBricks[Item.Source].Row;
    for Pass:=0 to 3 do for Slot:=0 to 18 do begin
      Check;if Length(FExtra)-NS>=32 then Break;if (Pass>0) and (Slot<9) then Continue;NewBrick:=Slot<9;
      if NewBrick then begin
        X:=0.222+0.144*Slot;Duplicate:=False;for Bonus in FBonus do if (Bonus.Row=Row) and Near(Bonus.X,X) then Duplicate:=True;
        if Duplicate then Continue;Bonus.X:=X;Bonus.Row:=Row;Bonus.Time:=Item.Finish;
        if not ClearsMain(Bonus,Cancel) then Continue;Target:=Length(FBricks)+Length(FBonus);
      end else begin
        Target:=Item.Source;while (Target<Length(FBricks)) and (FBricks[Target].Row=Row) and (FBricks[Target].Col<>Slot-9) do Inc(Target);
        if (Target>=Length(FBricks)) or (FBricks[Target].Row<>Row) then Continue;X:=GridX(Slot-9);
      end;
      Found:=False;
      for Phase:=0 to 11 do begin
        Check;Launch:=Item.Take+(Ordinal mod 8)*0.19+Phase*0.075;Ball:=Default(TScoreExtraBall);
        Ball.Launch:=Launch;Ball.A:=BreakPoint(PaddleAt(Launch),BREAK_PADDLE_Y);Ball.B:=BreakPoint(X,FContactY);
        Ball.Target:=Target;Ball.Item:=Length(FItems);D:=Distance(Ball.A,Ball.B);
        for VI:=0 to 28 do begin
          Speed:=1.0+VI*0.045;Flight:=D/Speed;Ball.Hit:=Launch+Flight;Ball.Catch:=Launch+2*Flight;
          if Ball.Catch+0.20>Item.Finish then Continue;Ball.C:=BreakPoint(Fold(2*X-Ball.A.X),BREAK_PADDLE_Y);
          if NewBrick then begin
            Bonus.Time:=Ball.Hit;K:=Length(FBonus);SetLength(FBonus,K+1);FBonus[K]:=Bonus;Valid:=True;
            for Previous in FExtra do if (Previous.Item=Length(FItems)) and not CheckExtra(Previous) then begin Valid:=False;Break;end;
            if not Valid then begin SetLength(FBonus,K);Continue;end;
          end;
          Valid:=NewBrick;if not NewBrick then Valid:=FBricks[Target].Time>Ball.Hit+1E-7;
          if Valid then for Previous in FExtra do if (Abs(Previous.Launch-Launch)<0.01) and
            (Abs(Previous.Hit-Ball.Hit)<0.01) and Near(Previous.B.X,Ball.B.X) then begin Valid:=False;Break;end;
          if Valid then Valid:=CheckExtra(Ball);
          if not Valid then begin if NewBrick then SetLength(FBonus,Length(FBonus)-1);Continue;end;
          K:=Length(FExtra);SetLength(FExtra,K+1);FExtra[K]:=Ball;if NewBrick then Inc(Destroyed);Found:=True;Inc(Ordinal);Break;
        end;if Found then Break;
      end;
    end;
    if (Destroyed>=2) and (Length(FExtra)-NS>=12) then begin K:=Length(FItems);SetLength(FItems,K+1);FItems[K]:=Item;Result:=True;end
    else begin SetLength(FBonus,NB);SetLength(FExtra,NS);end;
  end;
begin
  if FGoal<24 then Exit;Candidates:=TList<TCandidate>.Create;
  try
    First:=0;
    while First<Length(FBricks) do begin
      Check;Last:=First;while (Last<High(FBricks)) and (FBricks[Last+1].Row=FBricks[First].Row) do Inc(Last);
      A:=0;B:=Length(FEvents);while A<B do begin M:=(A+B) div 2;if FEvents[M].Time<FBricks[First].Time+1.1-1E-8 then A:=M+1 else B:=M;end;
      if A<Length(FEvents) then begin
        Take:=FEvents[A].Time;Finish:=Min(Take+6,FBricks[Last].Time-0.08);Weight:=0;
        for I:=First to Last do Weight:=Weight+FBricks[I].Strength;Weight:=Weight/(Last-First+1);
        if (FBricks[First].Time>=10) and (Take-FBricks[First].Time<=1.8) and (Finish-Take>=2.8) and (Finish<=FGoal-4) then begin
          Candidate.Item.Source:=First;Candidate.Item.Drop:=FBricks[First].Time;Candidate.Item.Take:=Take;Candidate.Item.Finish:=Finish;Candidate.Weight:=Weight;Candidates.Add(Candidate);
        end;
      end;First:=Last+1;
    end;
    Earliest:=10;
    while Length(FItems)<64 do begin
      Check;First:=0;while (First<Candidates.Count) and (Candidates[First].Item.Drop<Earliest) do Inc(First);if First=Candidates.Count then Break;
      Edge:=Candidates[First].Item.Drop+8;Last:=First;while (Last<Candidates.Count-1) and (Candidates[Last+1].Item.Drop<=Edge) do Inc(Last);
      SetLength(Used,Last-First+1);for I:=0 to High(Used) do Used[I]:=False;Best:=-1;
      for TryIndex:=First to Last do begin
        Best:=-1;for J:=First to Last do if not Used[J-First] then
          if (Best<0) or (Candidates[J].Weight>Candidates[Best].Weight) then Best:=J;
        Used[Best-First]:=True;Candidate:=Candidates[Best];
        if TryShow(Candidate.Item) then begin Earliest:=Candidate.Item.Finish+12;Break;end;Best:=-1;
      end;if Best<0 then Earliest:=Edge+1E-6;
    end;
  finally Candidates.Free;end;
end;
procedure TBreakScorePlan.VerifyShows(const Cancel:TFunc<Boolean>);
var I,J,A,B,M,Gap:Integer;ItemData:TScoreItem;Ball:TScoreExtraBall;Bonus:TScoreBonus;R,S:TBreakBlock;
  Counts,Hits,Kills:TArray<Integer>;Flight,Speed:Double;P:TBreakPoint;
  procedure Need(Value:Boolean;const Msg:string);begin if not Value then raise Exception.Create('Multiball plan: '+Msg);end;
  procedure Check;begin if Assigned(Cancel) and Cancel() then Abort;end;
begin
  Need((Length(FItems)<=64) and (Length(FBonus)<=576) and (Length(FExtra)<=2048),'limits');
  if Length(FItems)=0 then begin Need((Length(FBonus)=0) and (Length(FExtra)=0),'orphan extra data');Exit;end;
  SetLength(Counts,Length(FItems));SetLength(Kills,Length(FItems));SetLength(Hits,Length(FBonus));
  for I:=0 to High(FItems) do begin
    Check;ItemData:=FItems[I];Need((ItemData.Source>=0) and (ItemData.Source<Length(FBricks)),'item source');
    Need(Finite(ItemData.Drop) and Finite(ItemData.Take) and Finite(ItemData.Finish),'item numbers');
    Need((ItemData.Drop=FBricks[ItemData.Source].Time) and (ItemData.Drop>=10) and
      (ItemData.Take-ItemData.Drop>=1.1-1E-8) and (ItemData.Take-ItemData.Drop<=1.8) and
      (ItemData.Finish-ItemData.Take>=2.8) and (ItemData.Finish-ItemData.Take<=6+1E-8) and (ItemData.Finish<=FGoal-4),'item interval');
    if I>0 then Need(ItemData.Drop>=FItems[I-1].Finish+12,'normal interval');
    A:=0;B:=Length(FEvents);while A<B do begin M:=(A+B) div 2;if FEvents[M].Time<ItemData.Take then A:=M+1 else B:=M;end;
    Need((A<Length(FEvents)) and (FEvents[A].Time=ItemData.Take),'pickup accent');
  end;
  for I:=0 to High(FBonus) do begin
    Check;Bonus:=FBonus[I];Need(Finite(Bonus.X) and Finite(Bonus.Time) and (Bonus.Row>=0) and (Bonus.Row<FRows),'bonus numbers');
    Gap:=Round((Bonus.X-0.222)/0.144);Need((Gap>=0) and (Gap<9) and Near(Bonus.X,0.222+0.144*Gap),'bonus cell');
    Need((Bonus.Time>0) and (Bonus.Time<FGoal-4),'bonus destruction');
    Need(Near(KeyAt(FShifts,Bonus.Time),Bonus.Row*SCORE_PITCH) and (Abs(KeyAt(FShifts,Bonus.Time,True))<1E-7),'bonus active row');
    if I>0 then Need(Bonus.Row>=FBonus[I-1].Row,'bonus row ordering');
    R:=BonusRectangle(Bonus,FContactY,0);
    for J:=0 to I-1 do Need((FBonus[J].Row<>Bonus.Row) or not Near(FBonus[J].X,Bonus.X),'duplicate bonus');
    for J:=0 to High(FBricks) do if FBricks[J].Row=Bonus.Row then begin
      S:=RectangleAt(FBricks[J],FContactY,0);Need((R.Right<=S.Left) or (R.Left>=S.Right),'overlapping cells');
    end;
    Need(ClearsMain(Bonus,Cancel),'bonus intersects reserved main flight');
  end;
  for I:=0 to High(FExtra) do begin
    Check;Ball:=FExtra[I];Need((Ball.Item>=0) and (Ball.Item<Length(FItems)) and (Ball.Target>=0) and (Ball.Target<GetTotalCount),'ball references');
    Need(Finite(Ball.Launch) and Finite(Ball.Hit) and Finite(Ball.Catch) and Finite(Ball.A.X) and Finite(Ball.A.Y) and
      Finite(Ball.B.X) and Finite(Ball.B.Y) and Finite(Ball.C.X) and Finite(Ball.C.Y),'ball numbers');
    ItemData:=FItems[Ball.Item];Inc(Counts[Ball.Item]);Flight:=Ball.Hit-Ball.Launch;
    Need((Flight>1E-9) and Near(Ball.Catch-Ball.Hit,Flight) and (Ball.Launch>=ItemData.Take) and (Ball.Catch+0.20<=ItemData.Finish),'ball lifetime');
    Speed:=Distance(Ball.A,Ball.B)/Flight;Need((Speed>=1.0-1E-8) and (Speed<=2.26+1E-8),'ball speed');
    Need(Near(Ball.A.X,PaddleAt(Ball.Launch)) and Near(Ball.A.Y,BREAK_PADDLE_Y) and Near(Ball.C.Y,BREAK_PADDLE_Y) and
      Near(Ball.C.X,Fold(2*Ball.B.X-Ball.A.X)),'launch/return position');
    R:=BrickAt(Ball.Target,Ball.Hit);Need(Near(Ball.B.Y,FContactY) and Near(Ball.B.Y,R.Bottom+BREAK_RADIUS) and (Ball.B.X>=R.Left) and (Ball.B.X<=R.Right) and (Ball.B.Y<Ball.A.Y),'contact face');
    if Ball.Target<Length(FBricks) then Need(R.Time>Ball.Hit+1E-7,'reserved contact already destroyed')
    else begin Need(R.Time=Ball.Hit,'bonus kill time');Inc(Hits[Ball.Target-Length(FBricks)]);Inc(Kills[Ball.Item]);end;
    Need(CheckExtra(Ball),'unintended earlier collision or missed paddle');
    Need(ExtraAt(I,Ball.Catch,P,Speed) and Near(P.X,Ball.C.X) and Near(P.Y,Ball.C.Y),'capture continuity');
  end;
  for I:=0 to High(Counts) do Need((Counts[I]>=12) and (Counts[I]<=32) and (Kills[I]>=2),'ball and destruction count per item');
  for I:=0 to High(Hits) do Need(Hits[I]=1,'shared destruction ownership');
end;
procedure TBreakScorePlan.Verify(const Cancel:TFunc<Boolean>);
begin
  if not Finite(FDuration) or not Finite(FSoundEnd) or (FDuration<=0) or (FSoundEnd<0) or (FSoundEnd>FDuration) or (FSourceCount<0) or (FSourceCount>100000) then raise Exception.Create('Invalid score audio metadata');
  if not Finite(FPaddleHalf) or ((FPaddleHalf<>BREAK_PADDLE_HALF) and (FPaddleHalf<>BREAK_PADDLE_HALF_V6) and (FPaddleHalf<>BREAK_PADDLE_HALF_NEW)) then raise Exception.Create('Invalid score paddle width');
  if not Finite(FBallEnd) or (FTrials<0) or (FTrials>32) then raise Exception.Create('Invalid score finish metadata');
  if Length(FBricks)=0 then begin if (FEnd<>FDuration) or (FBallEnd<>FEnd) then raise Exception.Create('Invalid silent score finish');end
  else if (Length(FNodes)=0) or not Near(FBallEnd,FNodes[High(FNodes)].Time) or (FBallEnd<=FGoal) or (FBallEnd>FEnd) then raise Exception.Create('Invalid score ball finish');
  if Length(FEvents)>0 then if FEvents[High(FEvents)].Time>FSoundEnd+1E-8 then raise Exception.Create('Score beyond sound end');
  CheckScore(FEvents,FNodes,FBricks,FShifts,FPaddles,FContactY,FLaunch,FGoal,FEnd,FTarget,FPaddleHalf,FSourceCount,FRows,Cancel);
  VerifyShows(Cancel);if FAction<>nil then FAction.Verify(Cancel);
end;
class function TBreakScorePlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>;AllowShows:Boolean;PaddleHalf:Double):TBreakScorePlan;
var List:TList<TScoreEvent>;Gaps:TArray<Double>;Events:TArray<TScoreEvent>;Candidate:TScoreEvent;Trial:TBreakScorePlan;I,Seed:Integer;Previous,Median,LaunchLimit:Double;LastError:string;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if not Finite(PaddleHalf) or ((PaddleHalf<>BREAK_PADDLE_HALF) and (PaddleHalf<>BREAK_PADDLE_HALF_V6) and (PaddleHalf<>BREAK_PADDLE_HALF_NEW)) then raise Exception.Create('Invalid score paddle width');
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.SoundEnd<0) or
    (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then raise Exception.Create('Invalid score audio bounds');
  Result:=nil;List:=TList<TScoreEvent>.Create;Trial:=nil;
  try
    Previous:=-1;
    for I:=0 to High(Audio.Hits) do begin
      if Assigned(Cancel) and Cancel() then Abort;Candidate.Time:=Audio.Hits[I].Time;Candidate.Strength:=Audio.Hits[I].Strength;Candidate.Source:=I;
      if not Finite(Candidate.Time) or not Finite(Candidate.Strength) or (Candidate.Time<0) or (Candidate.Time<Previous) or (Candidate.Time>Audio.Duration+0.011) then raise Exception.Create('Invalid score accent');Previous:=Candidate.Time;
      if (Candidate.Time<=1E-5) or (Candidate.Time>Audio.SoundEnd+1E-8) then Continue;Candidate.Strength:=EnsureRange(Candidate.Strength,0.0,1.0);
      if (List.Count>0) and (List[List.Count-1].Time=Candidate.Time) then List[List.Count-1]:=Candidate else List.Add(Candidate);
    end;
    Events:=List.ToArray;Median:=0.5;
    if Length(Events)>1 then begin SetLength(Gaps,Length(Events)-1);for I:=0 to High(Gaps) do Gaps[I]:=Events[I+1].Time-Events[I].Time;TArray.Sort<Double>(Gaps);Median:=Gaps[Length(Gaps) div 2];end;
    LaunchLimit:=Min(1.0,Median*2);if Audio.SoundEnd>=8 then LaunchLimit:=Max(LaunchLimit,1.35);
    LastError:='';
    for Seed:=0 to 31 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      Trial:=TBreakScorePlan.Create;Trial.FPaddleHalf:=PaddleHalf;Trial.FEvents:=Events;Trial.FDuration:=Audio.Duration;Trial.FSoundEnd:=Audio.SoundEnd;Trial.FSourceCount:=Length(Audio.Hits);
      Trial.FTarget:=EnsureRange(0.70/Median,0.9,1.7);Trial.FContactY:=0.54;
      if (Length(Events)>0) and (Events[High(Events)].Time<1) then Trial.FContactY:=BREAK_PADDLE_Y-Min(BREAK_PADDLE_Y-0.54,Trial.FTarget*Events[High(Events)].Time*0.65);
      try
        if Length(Events)>0 then Trial.Attempt(Seed,Cancel) else begin Trial.FEnd:=Audio.Duration;Trial.FBallEnd:=Audio.Duration;end;
        Trial.Verify(Cancel);
        if (Result=nil) or (Trial.Count>Result.Count) or ((Trial.Count=Result.Count) and (Trial.FLaunch<Result.FLaunch)) then begin Result.Free;Result:=Trial;Trial:=nil;end;
      except on E:EAbort do raise;on E:Exception do LastError:=E.Message;end;
      FreeAndNil(Trial);if Result<>nil then begin if Length(Events)>0 then Result.FTrials:=Seed+1;if (Result.FLaunch<=LaunchLimit) or (Length(Events)=0) then Break;end;
    end;
    if Result=nil then raise Exception.Create('音時刻からの反射譜を構成できません: '+LastError);
    if AllowShows then Result.MakeShows(Cancel);Result.Verify(Cancel);
  except Trial.Free;List.Free;Result.Free;Result:=nil;raise;end;List.Free;
end;
function TBreakScorePlan.GetCount:Integer;begin if FAction<>nil then Exit(FAction.Count);Result:=Length(FBricks);end;
function TBreakScorePlan.GetTotalCount:Integer;begin if FAction<>nil then Exit(FAction.Count);Result:=Length(FBricks)+Length(FBonus);end;
function TBreakScorePlan.GetItemCount:Integer;begin Result:=Length(FItems);end;
function TBreakScorePlan.GetExtraCount:Integer;begin if FAction<>nil then Exit(FAction.ExtraCount);Result:=Length(FExtra);end;
function TBreakScorePlan.Item(Index:Integer):TScoreItem;begin Result:=FItems[Index];end;
function TBreakScorePlan.ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Opacity:Double):Boolean;
var Ball:TScoreExtraBall;U:Double;
begin
  if FAction<>nil then Exit(FAction.ExtraAt(Index,Time,P,Opacity));
  Ball:=FExtra[Index];Result:=False;Opacity:=0;P:=Ball.A;if (Time<Ball.Launch) or (Time>=Ball.Catch+0.20) then Exit;
  if Time>=Ball.Catch then begin
    U:=(Time-Ball.Catch)/0.20;Opacity:=1-U;
    P:=BreakPoint(EnsureRange(PaddleAt(Time)+(Ball.C.X-PaddleAt(Ball.Catch))*(1-U*U*(3-2*U)),BREAK_RADIUS,BREAK_WIDTH-BREAK_RADIUS),BREAK_PADDLE_Y);
  end else begin
    Opacity:=Min(1.0,(Time-Ball.Launch)/0.06);
    if Time<=Ball.Hit then P:=MixPoint(Ball.A,Ball.B,(Time-Ball.Launch)/(Ball.Hit-Ball.Launch))
    else begin U:=(Time-Ball.Hit)/(Ball.Catch-Ball.Hit);P:=BreakPoint(Fold(Ball.B.X+(Ball.B.X-Ball.A.X)*U),Ball.B.Y+(BREAK_PADDLE_Y-Ball.B.Y)*U);end;
  end;Result:=True;
end;
function TBreakScorePlan.GetSyncCount:Integer;
var N:TScoreNode;begin if FAction<>nil then Exit(FAction.SyncCount);Result:=0;for N in FNodes do if (N.Source>=0) and (N.Kind in [snBlock,snWall,snPaddle,snCorner]) then Inc(Result);end;
function TBreakScorePlan.GetAuxCount:Integer;
var N:TScoreNode;begin if FAction<>nil then Exit(FAction.AuxiliaryCount);Result:=0;for N in FNodes do if (N.Source<0) and (N.Kind in [snWall,snPaddle,snCorner]) then Inc(Result);end;
function TBreakScorePlan.GetCatchCount:Integer;
var N:TScoreNode;begin Result:=0;for N in FNodes do if N.Kind=snCatch then Inc(Result);end;
function TBreakScorePlan.HeldAt(Time:Double):Boolean;
var I,A,B,M:Integer;
begin Result:=False;if Length(FNodes)=0 then Exit;if Time<FLaunch then Exit(True);
  A:=0;B:=Length(FNodes);while A<B do begin M:=(A+B) div 2;if FNodes[M].Time<=Time then A:=M+1 else B:=M;end;I:=Max(0,A-1);
  Result:=(I<High(FNodes)) and (FNodes[I].Kind=snCatch) and (FNodes[I+1].Kind=snServe);
end;
function TBreakScorePlan.PositionAt(Time:Double):TBreakPoint;
var A,B,M:Integer;C:TScoreControls;
begin
  if FAction<>nil then Exit(FAction.PositionAt(Time));
  Result:=BreakPoint(BREAK_WIDTH/2,BREAK_PADDLE_Y);if Length(FNodes)=0 then Exit;if Time<=FLaunch then Exit(FNodes[0].P);
  A:=1;B:=Length(FNodes);while A<B do begin M:=(A+B) div 2;if FNodes[M].Time<Time then A:=M+1 else B:=M;end;
  M:=Min(A,High(FNodes));C:=Controls(FNodes[M-1],FNodes[M]);Result:=CurveAt(C,(Time-FNodes[M-1].Time)/(FNodes[M].Time-FNodes[M-1].Time));
end;
function TBreakScorePlan.PaddleAt(Time:Double):Double;
begin Result:=BREAK_WIDTH/2;if Length(FPaddles)>0 then Result:=KeyAt(FPaddles,Time);end;
function TBreakScorePlan.BrickAt(Index:Integer;Time:Double):TBreakBlock;
begin
  if FAction<>nil then Exit(FAction.BrickAt(Index,Time));
  if Index<Length(FBricks) then Result:=RectangleAt(FBricks[Index],FContactY,KeyAt(FShifts,Min(Time,FBricks[Index].Time)))
  else begin Dec(Index,Length(FBricks));Result:=BonusRectangle(FBonus[Index],FContactY,KeyAt(FShifts,Min(Time,FBonus[Index].Time)));end;
end;
function TBreakScorePlan.BrickRow(Index:Integer):Integer;
begin if FAction<>nil then Exit(FAction.BrickRow(Index));if Index<Length(FBricks) then Result:=FBricks[Index].Row else Result:=FBonus[Index-Length(FBricks)].Row;end;
function TBreakScorePlan.ExportCoreData(Audio:TRhythmAudio;Version:Integer):TJSONObject;
var Root,J:TJSONObject;Items:TJSONArray;E:TScoreEvent;N:TScoreNode;B:TScoreBrick;K:TScoreKey;ItemData:TScoreItem;Bonus:TScoreBonus;Ball:TScoreExtraBall;
begin
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','breakout');Root.AddPair('version',TJSONNumber.Create(Version));Root.AddPair('layout','score-grid');Root.AddPair('sparsePolicy','aux-then-hold');
    if Version=4 then Root.AddPair('multiballPolicy','reserved-core-and-bonus-v1');AddPreparedAudio(Root,Audio);
    Root.AddPair('launch',TJSONNumber.Create(FLaunch));Root.AddPair('goal',TJSONNumber.Create(FGoal));Root.AddPair('end',TJSONNumber.Create(FEnd));Root.AddPair('ballEnd',TJSONNumber.Create(FBallEnd));
    Root.AddPair('paddleHalf',TJSONNumber.Create(FPaddleHalf));
    Root.AddPair('contactY',TJSONNumber.Create(FContactY));Root.AddPair('target',TJSONNumber.Create(FTarget));Root.AddPair('rows',TJSONNumber.Create(FRows));Root.AddPair('trials',TJSONNumber.Create(FTrials));
    Items:=TJSONArray.Create;Root.AddPair('events',Items);
    for E in FEvents do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(E.Time));J.AddPair('strength',TJSONNumber.Create(E.Strength));J.AddPair('source',TJSONNumber.Create(E.Source));end;
    Items:=TJSONArray.Create;Root.AddPair('nodes',Items);
    for N in FNodes do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(N.Time));J.AddPair('x',TJSONNumber.Create(N.P.X));J.AddPair('y',TJSONNumber.Create(N.P.Y));J.AddPair('speed',TJSONNumber.Create(N.Speed));J.AddPair('kind',TJSONNumber.Create(Ord(N.Kind)));J.AddPair('source',TJSONNumber.Create(N.Source));J.AddPair('brick',TJSONNumber.Create(N.Brick));end;
    Items:=TJSONArray.Create;Root.AddPair('bricks',Items);
    for B in FBricks do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(B.Time));J.AddPair('strength',TJSONNumber.Create(B.Strength));J.AddPair('source',TJSONNumber.Create(B.Source));J.AddPair('row',TJSONNumber.Create(B.Row));J.AddPair('col',TJSONNumber.Create(B.Col));end;
    Items:=TJSONArray.Create;Root.AddPair('shifts',Items);
    for K in FShifts do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(K.Time));J.AddPair('value',TJSONNumber.Create(K.Value));end;
    Items:=TJSONArray.Create;Root.AddPair('paddles',Items);
    for K in FPaddles do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(K.Time));J.AddPair('value',TJSONNumber.Create(K.Value));end;
    Items:=TJSONArray.Create;Root.AddPair('items',Items);
    for ItemData in FItems do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('source',TJSONNumber.Create(ItemData.Source));J.AddPair('drop',TJSONNumber.Create(ItemData.Drop));J.AddPair('take',TJSONNumber.Create(ItemData.Take));J.AddPair('finish',TJSONNumber.Create(ItemData.Finish));end;
    Items:=TJSONArray.Create;Root.AddPair('bonus',Items);
    for Bonus in FBonus do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('x',TJSONNumber.Create(Bonus.X));J.AddPair('time',TJSONNumber.Create(Bonus.Time));J.AddPair('row',TJSONNumber.Create(Bonus.Row));end;
    Items:=TJSONArray.Create;Root.AddPair('extraBalls',Items);
    for Ball in FExtra do begin
      J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('launch',TJSONNumber.Create(Ball.Launch));J.AddPair('hit',TJSONNumber.Create(Ball.Hit));J.AddPair('catch',TJSONNumber.Create(Ball.Catch));
      J.AddPair('ax',TJSONNumber.Create(Ball.A.X));J.AddPair('ay',TJSONNumber.Create(Ball.A.Y));J.AddPair('bx',TJSONNumber.Create(Ball.B.X));J.AddPair('by',TJSONNumber.Create(Ball.B.Y));J.AddPair('cx',TJSONNumber.Create(Ball.C.X));J.AddPair('cy',TJSONNumber.Create(Ball.C.Y));
      J.AddPair('target',TJSONNumber.Create(Ball.Target));J.AddPair('item',TJSONNumber.Create(Ball.Item));
    end;
    Result:=Root;
  except Root.Free;raise;end;
end;
destructor TBreakScorePlan.Destroy;begin FAction.Free;inherited;end;
procedure TBreakScorePlan.Enhance(Audio:TRhythmAudio;ClearWave:Boolean;const Cancel:TFunc<Boolean>);
var Data:TJSONObject;
begin if FAction<>nil then Exit;Data:=ExportCoreData(Audio,4);try FAction:=TBreakActionPlan.Build(Data,ClearWave,Cancel);finally Data.Free;end;Verify(Cancel);end;
function TBreakScorePlan.RadiusAt(Time:Double):Double;
begin Result:=BREAK_RADIUS;if FAction<>nil then Result:=FAction.RadiusAt(Time);end;
function TBreakScorePlan.BrickVisible(Index:Integer;Time:Double):Boolean;
begin Result:=True;if FAction<>nil then Result:=FAction.BrickVisible(Index,Time);end;
function TBreakScorePlan.ExtraLaunch(Index:Integer):Double;
begin if FAction<>nil then Exit(FAction.ExtraLaunch(Index));Result:=FExtra[Index].Launch;end;
function TBreakScorePlan.ExportData(Audio:TRhythmAudio;Version:Integer):TJSONObject;
begin if FAction<>nil then Result:=FAction.ExportData(ExportCoreData(Audio,4),Audio) else Result:=ExportCoreData(Audio,Version);end;
procedure TBreakScorePlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var Root:TJSONObject;
begin
  if not (Ref.Version in [2,3,4]) or ((Length(FItems)>0) and (Ref.Version<>4)) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsBreakout) then raise Exception.Create('Invalid score reference');
  Root:=ExportData(Audio,Ref.Version);
  try
    Root.AddPair('key',Ref.Key);Root.AddPair('source',Ref.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    WritePreparedData(Root,Ref);
  finally Root.Free;end;
end;
class function TBreakScorePlan.Load(Root:TJSONObject;Audio:TRhythmAudio):TBreakScorePlan;
var Info,J:TJSONObject;Items:TJSONArray;I,K:Integer;
  function List(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Invalid score array: '+Name);end;
  function Item(Index:Integer):TJSONObject;
  begin if not (Items.Items[Index] is TJSONObject) then raise Exception.Create('Invalid score item');Result:=TJSONObject(Items.Items[Index]);end;
begin
  Result:=nil;if Audio=nil then raise Exception.Create('Score audio metadata missing');
  if Root.GetValue<string>('layout','')='rush-overlay-v1' then begin
    Result:=Load(Root.GetValue<TJSONObject>('baseScore'),Audio);try Result.FAction:=TBreakActionPlan.Load(Root);Result.Verify;except Result.Free;raise;end;Exit;
  end;
  if Root.GetValue<string>('layout','')<>'score-grid' then raise Exception.Create('Invalid score layout');
  if Root.GetValue<string>('sparsePolicy','')<>'aux-then-hold' then raise Exception.Create('Invalid sparse score policy');
  Info:=Root.GetValue<TJSONObject>('audio');if (Info=nil) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or
    not Finite(Info.GetValue<Double>('duration')) or not Finite(Info.GetValue<Double>('soundEnd')) or
    not Near(Info.GetValue<Double>('duration'),Audio.Duration) or not Near(Info.GetValue<Double>('soundEnd'),Audio.SoundEnd) then raise Exception.Create('Score audio identity mismatch');
  Result:=TBreakScorePlan.Create;
  try
    Result.FPaddleHalf:=Root.GetValue<Double>('paddleHalf',BREAK_PADDLE_HALF);
    Result.FDuration:=Audio.Duration;Result.FSoundEnd:=Audio.SoundEnd;Result.FSourceCount:=Length(Audio.Hits);
    Result.FLaunch:=Root.GetValue<Double>('launch');Result.FGoal:=Root.GetValue<Double>('goal');Result.FEnd:=Root.GetValue<Double>('end');Result.FBallEnd:=Root.GetValue<Double>('ballEnd');
    Result.FContactY:=Root.GetValue<Double>('contactY');Result.FTarget:=Root.GetValue<Double>('target');Result.FRows:=Root.GetValue<Integer>('rows',-1);Result.FTrials:=Root.GetValue<Integer>('trials',-1);
    Items:=List('events',100000);SetLength(Result.FEvents,Items.Count);
    for I:=0 to Items.Count-1 do begin J:=Item(I);Result.FEvents[I].Time:=J.GetValue<Double>('time');Result.FEvents[I].Strength:=J.GetValue<Double>('strength');Result.FEvents[I].Source:=J.GetValue<Integer>('source',-1);end;
    Items:=List('nodes',3*SCORE_MAX_BRICKS+2);SetLength(Result.FNodes,Items.Count);
    for I:=0 to Items.Count-1 do begin
      J:=Item(I);Result.FNodes[I].Time:=J.GetValue<Double>('time');Result.FNodes[I].P:=BreakPoint(J.GetValue<Double>('x'),J.GetValue<Double>('y'));Result.FNodes[I].Speed:=J.GetValue<Double>('speed');
      K:=J.GetValue<Integer>('kind',-1);if (K<Ord(Low(TScoreKind))) or (K>Ord(High(TScoreKind))) then raise Exception.Create('Invalid score contact kind');Result.FNodes[I].Kind:=TScoreKind(K);
      Result.FNodes[I].Source:=J.GetValue<Integer>('source',-1);Result.FNodes[I].Brick:=J.GetValue<Integer>('brick',-1);
    end;
    Items:=List('bricks',SCORE_MAX_BRICKS);SetLength(Result.FBricks,Items.Count);
    for I:=0 to Items.Count-1 do begin J:=Item(I);Result.FBricks[I].Time:=J.GetValue<Double>('time');Result.FBricks[I].Strength:=J.GetValue<Double>('strength');Result.FBricks[I].Source:=J.GetValue<Integer>('source',-1);Result.FBricks[I].Row:=J.GetValue<Integer>('row',-1);Result.FBricks[I].Col:=J.GetValue<Integer>('col',-1);end;
    Items:=List('shifts',1602);SetLength(Result.FShifts,Items.Count);
    for I:=0 to Items.Count-1 do begin J:=Item(I);Result.FShifts[I].Time:=J.GetValue<Double>('time');Result.FShifts[I].Value:=J.GetValue<Double>('value');end;
    Items:=List('paddles',3*SCORE_MAX_BRICKS+2);SetLength(Result.FPaddles,Items.Count);
    for I:=0 to Items.Count-1 do begin J:=Item(I);Result.FPaddles[I].Time:=J.GetValue<Double>('time');Result.FPaddles[I].Value:=J.GetValue<Double>('value');end;
    if Root.GetValue<Integer>('version',0)>=4 then begin
      if Root.GetValue<string>('multiballPolicy','')<>'reserved-core-and-bonus-v1' then raise Exception.Create('Invalid multiball policy');
      Items:=List('items',64);SetLength(Result.FItems,Items.Count);
      for I:=0 to Items.Count-1 do begin J:=Item(I);Result.FItems[I].Source:=J.GetValue<Integer>('source',-1);Result.FItems[I].Drop:=J.GetValue<Double>('drop');Result.FItems[I].Take:=J.GetValue<Double>('take');Result.FItems[I].Finish:=J.GetValue<Double>('finish');end;
      Items:=List('bonus',576);SetLength(Result.FBonus,Items.Count);
      for I:=0 to Items.Count-1 do begin J:=Item(I);Result.FBonus[I].X:=J.GetValue<Double>('x');Result.FBonus[I].Time:=J.GetValue<Double>('time');Result.FBonus[I].Row:=J.GetValue<Integer>('row',-1);end;
      Items:=List('extraBalls',2048);SetLength(Result.FExtra,Items.Count);
      for I:=0 to Items.Count-1 do begin
        J:=Item(I);Result.FExtra[I].Launch:=J.GetValue<Double>('launch');Result.FExtra[I].Hit:=J.GetValue<Double>('hit');Result.FExtra[I].Catch:=J.GetValue<Double>('catch');
        Result.FExtra[I].A:=BreakPoint(J.GetValue<Double>('ax'),J.GetValue<Double>('ay'));Result.FExtra[I].B:=BreakPoint(J.GetValue<Double>('bx'),J.GetValue<Double>('by'));Result.FExtra[I].C:=BreakPoint(J.GetValue<Double>('cx'),J.GetValue<Double>('cy'));
        Result.FExtra[I].Target:=J.GetValue<Integer>('target',-1);Result.FExtra[I].Item:=J.GetValue<Integer>('item',-1);
      end;
    end;
    Result.Verify;
  except Result.Free;Result:=nil;raise;end;
end;
end.
