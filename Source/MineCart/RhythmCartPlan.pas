unit RhythmCartPlan;
// 保存した時刻からレール、トロッコ、コインの位置を再現する。座標は右と上が正。
interface
uses System.Types;

const
  CartGradeDrag=1.45;
  CartHalfWidth=0.46;
  CartCoinHeight=0.43;
  CartCoinAhead=0.20;
  CartBossSpacing=2.55;
  CartBossApproach=2.65;
  CartBossApproachWindow=0.56;
  CartBossHeight=1.12;
  CartRamHalfWidth=0.72;
  CartRamHeight=1.20;
  CartThrowLead=0.43;
  CartThrowDistance=2.48;
  CartChaseContact=1.24;
  CartChaseLead=1.23;
  CartChaseAir=0.84;
  CartFinishLanding=0.76;
  CartFinishDrop=1.36;
  CartFinishLedge=2.16;
  CartFireHeight=1.46;
  CartBlockHeight=0.90;
  CartRockRadius=0.59;
  CartRockLandLead=0.51;
  CartRockFallTime=0.67;

type
  TCartMoveKind=(cmGap,cmStomp,cmFork,cmLift,cmCollapse,cmFlame,cmRival,cmBoss,cmRam,cmBossBump,
    cmFireJet,cmBlocker,cmRockfall);
  TCartKnot=record
    Time,X,Y,Speed:Double;
    Theme:Integer;
  end;
  TCartCoin=record
    Time,Strength,X,Y:Double;
  end;
  TCartMove=record
    Start,Hit,Finish,Height:Double;
    Kind:TCartMoveKind;
  end;
  TCartBoss=record
    FirstMove,LastMove:Integer;
  end;
  TCartPosition=record
    X,Y,Speed,Slope:Double;
  end;
  TCartBossShot=record
    ReleaseTime,CrossTime:Double;
    Origin,Target:TPointF;
    function Position(Time:Double):TPointF;
  end;
  TCartPlan=class
  public
    Duration,Goal:Double;
    Knots:TArray<TCartKnot>;
    Coins:TArray<TCartCoin>;
    Moves:TArray<TCartMove>;
    Bosses:TArray<TCartBoss>;
    function KnotAt(Time:Double):Integer;
    function CoinFrom(Time:Double):Integer;
    function MoveFrom(Time:Double):Integer;
    function MoveAt(Time:Double):Integer;
    function Track(Time:Double):TCartPosition;
    function Rail(Time,Clock:Double):TCartPosition;
    function RailAtX(X,Clock:Double):TCartPosition;
    function Cart(Time:Double):TCartPosition;
    function FinishRider(Time:Double):TPointF;
    function GapAt(Time:Double):Boolean;
    function CoinPosition(Time:Double):TPointF;
    function StompTop(const Move:TCartMove):Double;
    function WingTop(const Move:TCartMove;Time:Double):TPointF;
    function CanStomp(const Move:TCartMove):Boolean;
    function RamPosition(const Move:TCartMove;Time:Double):TCartPosition;
    function CanClearRam(const Move:TCartMove):Boolean;
    function CanClearBoss(const Move:TCartMove;First:Boolean):Boolean;
    function ThrowBomb(const Move:TCartMove;Time:Double):TPointF;
    function CanClearThrow(const Move:TCartMove):Boolean;
    function FlameTop(const Move:TCartMove):Double;
    function CanClearFlame(const Move:TCartMove):Boolean;
    function ObstacleHeight(const Move:TCartMove;Time:Double):Double;
    function CanClearObstacle(const Move:TCartMove):Boolean;
    function BossProgress(Index:Integer;Time:Double):Double;
    function ChaseCar(Index,Car:Integer;Time:Double):TCartPosition;
    function ChaseShotCount(Index,Car:Integer):Integer;
    function ChaseShot(Index,Car,Shot:Integer):TCartBossShot;
    procedure Verify(CheckNewAttacks:Boolean=True);
  end;

function CartEase(U:Double):Double;
function CartJump(const Move:TCartMove;Time:Double):Double;
function CartRunDistance(const A,B:TCartKnot):Double;
function CartObstacleHalfWidth(Kind:TCartMoveKind):Double;

implementation
uses System.SysUtils,System.Math;

function CartEase(U:Double):Double;
begin
  U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function CartJump(const Move:TCartMove;Time:Double):Double;
var U,Span:Double;
begin
  Span:=Move.Finish-Move.Start;
  if Move.Kind=cmFork then Span:=Span*0.62;
  if Move.Kind=cmBossBump then Span:=CartChaseAir;
  U:=EnsureRange((Time-Move.Start)/Span,0.0,1.0);
  Result:=4*Move.Height*U*(1-U);
end;

function CartRunDistance(const A,B:TCartKnot):Double;
begin
  Result:=(B.Time-A.Time)*(A.Speed+B.Speed)*0.5-CartGradeDrag*(B.Y-A.Y);
end;

function TCartPlan.KnotAt(Time:Double):Integer;
var Hi,Mid:Integer;
begin
  Result:=0;
  Hi:=High(Knots);
  while Result<Hi do begin
    Mid:=(Result+Hi+1) div 2;
    if Knots[Mid].Time<=Time then Result:=Mid else Hi:=Mid-1;
  end;
end;

function TCartPlan.CoinFrom(Time:Double):Integer;
var Hi,Mid:Integer;
begin
  Result:=0;
  Hi:=Length(Coins);
  while Result<Hi do begin
    Mid:=(Result+Hi) div 2;
    if Coins[Mid].Time<Time then Result:=Mid+1 else Hi:=Mid;
  end;
end;

function TCartPlan.MoveFrom(Time:Double):Integer;
var Hi,Mid:Integer;
begin
  Result:=0;
  Hi:=Length(Moves);
  while Result<Hi do begin
    Mid:=(Result+Hi) div 2;
    if Moves[Mid].Hit<Time then Result:=Mid+1 else Hi:=Mid;
  end;
end;

function TCartPlan.MoveAt(Time:Double):Integer;
var Hi,Mid:Integer;
begin
  Result:=0;
  Hi:=Length(Moves);
  while Result<Hi do begin
    Mid:=(Result+Hi) div 2;
    if Moves[Mid].Finish<Time then Result:=Mid+1 else Hi:=Mid;
  end;
  if (Result>=Length(Moves)) or (Moves[Result].Start>Time) then Result:=-1;
end;

function TCartPlan.Track(Time:Double):TCartPosition;
var I:Integer; A,B:TCartKnot; Span,U,DY,Grade,Blend:Double;
begin
  I:=KnotAt(Time);
  A:=Knots[I];
  if (Time<=0) or (I=High(Knots)) then begin
    Result.X:=A.X+(Time-A.Time)*A.Speed;
    Result.Y:=A.Y;
    Result.Speed:=A.Speed;
    Result.Slope:=0;
    Exit;
  end;
  B:=Knots[I+1];
  Span:=B.Time-A.Time;
  U:=(Time-A.Time)/Span;
  DY:=B.Y-A.Y;
  Blend:=CartEase(U);
  Grade:=DY*6*U*(1-U)/Span;
  // 速度を積分するので坂の境界で位置も速度も連続する。
  Result.X:=A.X+Span*(A.Speed*U+(B.Speed-A.Speed)*U*U*U*(1-U*0.5))-CartGradeDrag*DY*Blend;
  Result.Y:=A.Y+DY*Blend;
  Result.Speed:=A.Speed+(B.Speed-A.Speed)*Blend-CartGradeDrag*Grade;
  Result.Slope:=Grade/Result.Speed;
end;

function TCartPlan.Rail(Time,Clock:Double):TCartPosition;
var I:Integer; M:TCartMove; U,W:Double;
begin
  Result:=Track(Time);
  I:=MoveFrom(Time-0.85);
  while (I<Length(Moves)) and (Moves[I].Start<=Time) do begin
    M:=Moves[I];
    if (M.Kind=cmFork) and (Time<M.Finish) then begin
      U:=(Time-M.Start)/(M.Finish-M.Start);
      Result.Y:=Result.Y+0.92*Sqr(Sin(Pi*U));
      Result.Slope:=Result.Slope+0.92*Pi*Sin(2*Pi*U)/((M.Finish-M.Start)*Result.Speed);
    end;
    if M.Kind=cmLift then begin
      W:=CartEase((Time-M.Finish+0.19)/0.19)*(1-CartEase((Time-M.Finish)/0.42));
      Result.Y:=Result.Y+0.30*W*Sin((Clock-M.Finish)*3.7);
    end;
    Inc(I);
  end;
end;

function TCartPlan.RailAtX(X,Clock:Double):TCartPosition;
var Lo,Hi,Mid,I:Integer; LeftTime,RightTime,T:Double; N:TCartKnot;
begin
  if X<=0 then T:=X/Knots[0].Speed
  else if X>=Knots[High(Knots)].X then begin
    N:=Knots[High(Knots)];
    T:=N.Time+(X-N.X)/N.Speed;
  end else begin
    Lo:=0;
    Hi:=High(Knots);
    while Lo+1<Hi do begin
      Mid:=(Lo+Hi) div 2;
      if Knots[Mid].X<=X then Lo:=Mid else Hi:=Mid;
    end;
    LeftTime:=Knots[Lo].Time;
    RightTime:=Knots[Hi].Time;
    for I:=1 to 22 do begin
      T:=(LeftTime+RightTime)*0.5;
      if Track(T).X<X then LeftTime:=T else RightTime:=T;
    end;
    T:=(LeftTime+RightTime)*0.5;
  end;
  Result:=Rail(T,Clock);
  Result.X:=X;
  // 敵も途切れた区間では同じレールの両端を結ぶ。
  I:=MoveAt(T);
  if (I>=0) and (Moves[I].Kind in [cmGap,cmLift]) then
    Result.Y:=Result.Y+CartJump(Moves[I],T);
end;

function TCartPlan.Cart(Time:Double):TCartPosition;
var I:Integer;
begin
  Time:=EnsureRange(Time,0.0,Goal);
  Result:=Rail(Time,Time);
  I:=MoveAt(Time);
  if I>=0 then Result.Y:=Result.Y+CartJump(Moves[I],Time);
end;

function TCartPlan.GapAt(Time:Double):Boolean;
var I:Integer;
begin
  I:=MoveAt(Time);
  Result:=(I>=0) and (Moves[I].Kind in [cmGap,cmLift]) and
    (Time>Moves[I].Start+0.13) and (Time<Moves[I].Finish-0.13);
end;

function TCartPlan.FinishRider(Time:Double):TPointF;
var P:TCartPosition; U:Double;
begin
  P:=Track(Goal);
  U:=EnsureRange((Time-Goal)/CartFinishLanding,0.0,1.0);
  Result:=PointF(P.X+3.58*U*(1.22-0.22*U),
    P.Y+0.53+3.75*U*(1-U)-(0.53+CartFinishDrop)*Sqr(U));
end;

function TCartPlan.CoinPosition(Time:Double):TPointF;
var P:TCartPosition;
begin
  P:=Cart(Time);
  Result:=PointF(P.X+CartCoinAhead,P.Y+CartCoinHeight);
end;

function TCartPlan.StompTop(const Move:TCartMove):Double;
begin
  Result:=Track(Move.Hit).Y+CartJump(Move,Move.Hit);
end;

function TCartPlan.WingTop(const Move:TCartMove;Time:Double):TPointF;
var Lead:Double;
begin
  Lead:=Max(0.0,Move.Hit-Time);
  Result:=PointF(Track(Move.Hit).X+4.5*Lead,
    StompTop(Move)-0.16*Sqr(Sin(Lead*5.4)));
end;

function TCartPlan.CanStomp(const Move:TCartMove):Boolean;
var I:Integer; T,X,Y:Double; P:TCartPosition;
begin
  X:=Track(Move.Hit).X;
  Y:=StompTop(Move);
  for I:=0 to 31 do begin
    T:=Move.Start+(Move.Hit-Move.Start)*(I/32);
    P:=Track(T);
    if (X-P.X<CartHalfWidth+0.52) and (P.Y+CartJump(Move,T)<Y) then Exit(False);
  end;
  Result:=Track(Move.Hit-0.008).Y+CartJump(Move,Move.Hit-0.008)>Y+0.002;
end;

function TCartPlan.RamPosition(const Move:TCartMove;Time:Double):TCartPosition;
begin
  Result:=RailAtX(Track(Move.Hit).X-4.2*(Time-Move.Hit),Time);
end;

function TCartPlan.CanClearRam(const Move:TCartMove):Boolean;
var I:Integer; T,HitX:Double; P,Enemy:TCartPosition;
begin
  HitX:=Track(Move.Hit).X;
  for I:=0 to 64 do begin
    T:=Move.Start+(Move.Finish-Move.Start)*(I/64);
    P:=Track(T);
    if Abs(P.X-(HitX-4.2*(T-Move.Hit)))<CartHalfWidth+CartRamHalfWidth+0.14 then begin
      Enemy:=RamPosition(Move,T);
      if P.Y+CartJump(Move,T)<Enemy.Y+CartRamHeight+0.08 then Exit(False);
    end;
  end;
  Result:=True;
end;

function TCartPlan.CanClearBoss(const Move:TCartMove;First:Boolean):Boolean;
var I:Integer; T,Distance,U:Double; P,Enemy:TCartPosition;
begin
  for I:=0 to 64 do begin
    T:=Move.Start+(Move.Hit-Move.Start)*(I/64);
    if First then Distance:=(Move.Hit-T)*CartBossApproach*CartBossSpacing
    else begin
      U:=EnsureRange(1+(T-Move.Hit)/CartBossApproachWindow,0.0,1.0);
      Distance:=CartBossSpacing*(1-U*U*(2-U));
    end;
    if Distance<CartHalfWidth+0.86 then begin
      P:=Track(T);
      Enemy:=RailAtX(P.X+Distance,T);
      if P.Y+CartJump(Move,T)<Enemy.Y+CartBossHeight+0.08 then Exit(False);
    end;
  end;
  Result:=True;
end;

function TCartPlan.ThrowBomb(const Move:TCartMove;Time:Double):TPointF;
var Start,Hit:TCartPosition; U,Launch,Top:Double;
begin
  Launch:=Move.Hit-CartThrowLead;
  Start:=RailAtX(Track(Launch).X-CartThrowDistance,Launch);
  Hit:=Track(Move.Hit);
  Top:=Max(Track(Move.Hit-0.18).Y,Max(Hit.Y,Track(Move.Hit+0.18).Y))+
    1.58+0.45*Max(0.0,Hit.Y-Start.Y);
  U:=(Time-Launch)/CartThrowLead;
  Result:=PointF(Start.X+(Hit.X-Start.X)*U,Start.Y+0.83+(Top-Start.Y-0.83)*U+0.94*U*(1-U));
end;

function TCartPlan.CanClearThrow(const Move:TCartMove):Boolean;
var I:Integer; T:Double; Bomb:TPointF; P:TCartPosition;
begin
  for I:=0 to 32 do begin
    T:=Move.Hit-0.19+I*0.012;
    Bomb:=ThrowBomb(Move,T);
    P:=Track(T);
    if (Abs(Bomb.X-P.X)<CartHalfWidth+0.20) and (Bomb.Y<P.Y+1.10) then Exit(False);
  end;
  Result:=True;
end;

function TCartPlan.FlameTop(const Move:TCartMove):Double;
begin
  Result:=Track(Move.Hit).Y+0.50;
end;

function TCartPlan.CanClearFlame(const Move:TCartMove):Boolean;
var I:Integer; T,X,Y:Double; P:TCartPosition;
begin
  X:=Track(Move.Hit).X;
  Y:=FlameTop(Move);
  for I:=0 to 32 do begin
    T:=Move.Start+(Move.Finish-Move.Start)*(I/32);
    P:=Track(T);
    if (Abs(P.X-X)<CartHalfWidth+0.32) and (P.Y+CartJump(Move,T)<=Y+0.10) then Exit(False);
  end;
  Result:=True;
end;

function CartObstacleHalfWidth(Kind:TCartMoveKind):Double;
begin
  case Kind of
    cmFireJet:Result:=0.34;
    cmBlocker:Result:=0.40;
    cmRockfall:Result:=CartRockRadius;
    else Result:=0;
  end;
end;

function TCartPlan.ObstacleHeight(const Move:TCartMove;Time:Double):Double;
var U:Double;
begin
  case Move.Kind of
    cmFireJet:Result:=CartFireHeight*(1-CartEase(Abs(Time-Move.Hit)/0.46));
    cmBlocker:Result:=CartBlockHeight;
    cmRockfall:begin
      U:=EnsureRange(1+(Time-Move.Hit+CartRockLandLead)/CartRockFallTime,0.0,1.0);
      Result:=2*CartRockRadius+4.9*(1-Sqr(U));
    end;
    else Result:=0;
  end;
end;

function TCartPlan.CanClearObstacle(const Move:TCartMove):Boolean;
var I:Integer; T,Width,Top:Double; Base,P:TCartPosition;
begin
  Base:=Track(Move.Hit);
  Width:=CartHalfWidth+CartObstacleHalfWidth(Move.Kind)+0.08;
  for I:=0 to 64 do begin
    T:=Move.Start+(Move.Finish-Move.Start)*(I/64);
    P:=Track(T);
    if Abs(P.X-Base.X)<Width then begin
      Top:=ObstacleHeight(Move,T);
      // 表示済みのコインも火柱の最大の高さを越える軌道に置く。
      if Move.Kind=cmFireJet then Top:=CartFireHeight;
      if P.Y+CartJump(Move,T)<Base.Y+Top+0.12 then Exit(False);
    end;
  end;
  Result:=True;
end;

function TCartPlan.BossProgress(Index:Integer;Time:Double):Double;
var B:TCartBoss; I:Integer; First,Last,Span,U:Double;
begin
  B:=Bosses[Index];
  First:=Moves[B.FirstMove].Hit;
  Last:=Moves[B.LastMove].Hit;
  if Time<First then Exit((Time-First)*CartBossApproach);
  if Time>=Last then Exit(B.LastMove-B.FirstMove+(Time-Last)*1.3);
  I:=EnsureRange(MoveFrom(Time)-1,B.FirstMove,B.LastMove-1);
  Span:=Min(CartBossApproachWindow,Moves[I+1].Hit-Moves[I].Hit);
  U:=EnsureRange(1+(Time-Moves[I+1].Hit)/Span,0.0,1.0);
  Result:=I-B.FirstMove+U*U*(2-U);
end;

function TCartPlan.ChaseCar(Index,Car:Integer;Time:Double):TCartPosition;
var B:TCartBoss; I:Integer; HeroX,FromX,ToX,Offset,U:Double;
begin
  B:=Bosses[Index];
  HeroX:=Track(Time).X;
  if Time<Moves[B.FirstMove].Hit then
    Offset:=0.68*(Track(Moves[B.FirstMove].Hit).X-HeroX)
  else begin
    I:=EnsureRange(MoveFrom(Time)-1,B.FirstMove,B.LastMove-1);
    FromX:=Track(Moves[I].Hit).X;
    ToX:=Track(Moves[I+1].Hit).X;
    U:=EnsureRange((HeroX-FromX)/(ToX-FromX),0.0,1.0);
    // 撃破直後は残りの車両が前へ離れ、次の体当たりに向けて詰める。
    Offset:=-(I-B.FirstMove+U*(0.62+0.38*U))*CartBossSpacing;
  end;
  Result:=RailAtX(HeroX+CartChaseContact+(Car-B.FirstMove)*CartBossSpacing+Offset,Time);
end;

function TCartPlan.ChaseShotCount(Index,Car:Integer):Integer;
begin
  Result:=Min(4,1+Car-Bosses[Index].FirstMove+Index);
end;

function TCartPlan.ChaseShot(Index,Car,Shot:Integer):TCartBossShot;
var P:TCartPosition; Lead:Double;
begin
  Result.CrossTime:=Moves[Car].Start+0.42+(Shot-(ChaseShotCount(Index,Car)-1)*0.5)*0.084;
  P:=Track(Result.CrossTime);
  Result.Target:=PointF(P.X,P.Y+0.42);
  Lead:=0.39;
  repeat
    Result.ReleaseTime:=Result.CrossTime-Lead;
    P:=ChaseCar(Index,Car,Result.ReleaseTime);
    Result.Origin:=PointF(P.X-0.33,P.Y+1.03);
    Lead:=Lead-0.045;
  until (Result.Origin.X>=Result.Target.X+0.70) or (Lead<0.12);
end;

function TCartBossShot.Position(Time:Double):TPointF;
var U:Double;
begin
  U:=(Time-ReleaseTime)/(CrossTime-ReleaseTime);
  Result:=PointF(Origin.X+(Target.X-Origin.X)*U,
    Origin.Y+(Target.Y-Origin.Y)*U+0.62*U*(1-U));
end;

procedure TCartPlan.Verify(CheckNewAttacks:Boolean);
var
  I,J,K,Sample,LastBoss:Integer;
  A,B:TCartKnot;
  M:TCartMove;
  C:TCartCoin;
  Convoy:TCartBoss;
  Q:TPointF;
  Shot:TCartBossShot;
  P:TCartPosition;
  T,EndTime:Double;

  procedure Need(Condition:Boolean;const Detail:string);
  begin
    if not Condition then raise EConvertError.Create('トロッコの走行計画が不正です。'+Detail);
  end;

begin
  Need((Goal>0) and (Goal<=Duration) and (Length(Knots)>=2),'走行時間');
  Need((Knots[0].Time=0) and (Knots[0].X=0) and (Knots[High(Knots)].Time=Goal),'コースの両端');
  for I:=1 to High(Knots) do begin
    A:=Knots[I-1];
    B:=Knots[I];
    Need(B.Time>A.Time,'レールの順序');
    Need((Min(A.Speed,B.Speed)-CartGradeDrag*1.5*Max(0.0,B.Y-A.Y)/(B.Time-A.Time)>2.7) and
      (Abs(B.X-A.X-CartRunDistance(A,B))<1E-6),'レールの連続性');
  end;
  EndTime:=-1;
  for M in Moves do begin
    Need((M.Start>EndTime) and (M.Hit>M.Start) and (M.Finish>M.Hit) and (M.Finish<=Goal),'ギミックの順序');
    Need((M.Height=0)=(M.Kind in [cmCollapse,cmRival]),'ジャンプの高さ');
    EndTime:=M.Finish;
  end;
  for M in Moves do begin
    Need(Abs(Cart(M.Start).Y-Rail(M.Start,M.Start).Y)<1E-8,'踏み切り');
    Need(Abs(Cart(M.Finish).Y-Rail(M.Finish,M.Finish).Y)<1E-8,'着地');
    if M.Kind in [cmStomp,cmBoss] then Need(CanStomp(M),'敵の踏みつけ');
    if M.Kind=cmFlame then Need(CanClearFlame(M),'炎の回避');
    if M.Kind in [cmFireJet,cmBlocker,cmRockfall] then Need(CanClearObstacle(M),'火柱・車止め・落石の回避');
    if M.Kind=cmRam then Need(CanClearRam(M),'対向トロッコの回避');
    if CheckNewAttacks and (M.Kind=cmRival) then Need(CanClearThrow(M),'爆弾の回避');
    if M.Kind=cmFork then begin
      T:=M.Start+(M.Finish-M.Start)*0.78;
      Need((Cart(T).Y>Track(T).Y+0.20) and (Abs(Cart(T).Y-Rail(T,T).Y)<1E-8),'上段の分岐に乗る');
    end;
    if M.Kind in [cmGap,cmLift] then
      for J:=1 to 12 do begin
        T:=M.Start+0.13+(M.Finish-M.Start-0.26)*(J/13);
        Need(GapAt(T) and (Cart(T).Y>Rail(T,T).Y+0.20),'線路の途切れ');
      end;
  end;
  T:=-1;
  for C in Coins do begin
    Need((C.Time>T) and (C.Time<=Goal),'コインの順序');
    Q:=CoinPosition(C.Time);
    Need((Abs(C.X-Q.X)<1E-6) and (Abs(C.Y-Q.Y)<1E-6),'コインの接触');
    T:=C.Time;
  end;
  LastBoss:=-1;
  for I:=0 to High(Bosses) do begin
    Convoy:=Bosses[I];
    Need((Convoy.FirstMove>LastBoss) and (Convoy.LastMove>Convoy.FirstMove) and
      (Convoy.LastMove<=High(Moves)),'連結ボスの区間');
    for J:=Convoy.FirstMove to Convoy.LastMove do begin
      M:=Moves[J];
      Need(M.Kind=Moves[Convoy.FirstMove].Kind,'ボス車両の種類');
      if M.Kind=cmBossBump then begin
        Need((M.Start+CartChaseAir<M.Hit) and (CartJump(M,M.Hit)=0),'体当たり前の着地');
        P:=ChaseCar(I,J,M.Hit);
        Need(Abs(P.X-Cart(M.Hit).X-CartChaseContact)<1E-6,'体当たりの接触');
        for K:=0 to ChaseShotCount(I,J)-1 do begin
          Shot:=ChaseShot(I,J,K);
          Need(Shot.Origin.X>Shot.Target.X,'ボスの爆弾を投げる方向');
          for Sample:=0 to 24 do begin
            T:=Shot.ReleaseTime+(Shot.CrossTime+0.16-Shot.ReleaseTime)*(Sample/24);
            P:=Cart(T);
            Q:=Shot.Position(T);
            if Abs(P.X-Q.X)<CartHalfWidth+0.24 then Need(P.Y>Q.Y+0.20,'ボスの爆弾回避');
          end;
        end;
      end else begin
        Need(M.Kind=cmBoss,'ボス車両');
        if CheckNewAttacks then Need(CanClearBoss(M,J=Convoy.FirstMove),'連結車両の回避');
      end;
    end;
    LastBoss:=Convoy.LastMove;
  end;
end;
end.
