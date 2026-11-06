unit RhythmCannonPlan;
// 保存する音時刻から、砲弾・回避・部品ごとの離脱と地面への衝突を評価する。
interface

uses System.Types,RhythmCannonTargets;

const
  CannonWidth=24.0;
  CannonHeight=13.5;
  CannonGround=2.25;
  CannonLeftLane=3.0;
  CannonRightLane=6.2;
  CannonMaxStages=384;
  CannonMaxCues=112;
  CannonShellClearance=0.13;
  CannonSupportRearm=1.20;

type
  TCannonEnemy=(ceNone,ceShell,ceBurst,ceSpread,ceQuake,ceFire,ceLaser,ceHeavy);
  TCannonCue=record
    Time,Lead,Power:Double; // 着弾時刻、飛行秒数、音の強さ
    Volley:Integer; // 反撃の場合は0
    Enemy:TCannonEnemy;
  end;
  TCannonGeometry=record
    Part:Integer;
    Aim,Muzzle:array[0..3] of TPointF;
  end;
  TCannonPose=record
    X,Y,Angle:Double;
  end;
  TCannonSupportLife=record
    Arrival,Ready,Lost:Double;
  end;
  TCannonStage=class
  private
    FDodges,FSupportHits:TArray<Integer>;
    FGeometry:TArray<TCannonGeometry>;
    FDetach:TArray<TCannonPose>;
    FBuildSpan:Double;
  public
    Kind:TCannonTarget;
    Start,Stop:Double;
    Cues:TArray<TCannonCue>;
    Parts:TArray<TCannonPart>; // 保存譜面から再構築する
  private
    function DodgeCount(Time:Double):Integer;
    function IntactPose(Index:Integer;Time:Double):TCannonPose;
    function FrontPart(Time:Double):Integer;
    function Trace(const Origin,Target:TPointF;Time:Double;out HitPart:Integer):Double;
    procedure AimShot(Index,Front:Integer);
  public
    procedure Resolve;
    function Finish:Double;
    function HeroX(Time:Double):Double;
    function Threat(Time:Double):Double;
    function AssemblyTime(Index:Integer):Double;
    function AssemblyDrop(Index:Integer;Time:Double):Double;
    function PartPose(Index:Integer;Time:Double):TCannonPose;
    function ShatterTime(Index:Integer):Double;
    function Aim(Index:Integer;Barrel:Integer=0):TPointF;
    function HitPart(Index:Integer):Integer;
    function Wear(Index:Integer;Time:Double):Double;
    function Pivot(Barrel:Integer;Time:Double):TPointF;
    function Launch(Index,Barrel:Integer):Double;
    function Muzzle(Index,Barrel:Integer):TPointF;
    function Shell(Index,Barrel:Integer;Time:Double):TPointF;
    function EnemyOrigin(Time:Double):TPointF;
    function SupportHit(Index:Integer):Integer;
  end;
  TCannonPlan=class
  private
    FSupport:array[1..3] of TArray<TCannonSupportLife>;
  public
    Duration:Double;
    Stages:TArray<TCannonStage>;
    destructor Destroy;override;
    procedure ResolveSupport;
    function SupportAt(Barrel:Integer;Time:Double;out Life:TCannonSupportLife):Boolean;
    function Fires(Stage:TCannonStage;Index,Barrel:Integer):Boolean;
    function StageAt(Time:Double):Integer;
  end;

function CannonBoss(Kind:TCannonTarget):Boolean;
function CannonEase(Value:Double):Double;
function CannonMix(A,B,U:Double):Double;
function CannonNoise(Seed:Integer):Double;
function CannonHazardRadius(Enemy:TCannonEnemy):Double;

implementation

uses System.Math,System.Generics.Collections;

function CannonBoss(Kind:TCannonTarget):Boolean;
begin
  Result:=Kind>=ctTower;
end;

function CannonEase(Value:Double):Double;
begin
  Value:=EnsureRange(Value,0.0,1.0);
  Result:=Sqr(Value)*(3-2*Value);
end;

function CannonMix(A,B,U:Double):Double;
begin
  Result:=A+(B-A)*U;
end;

function CannonNoise(Seed:Integer):Double;
var Value:UInt64;
begin
  Value:=(UInt64(Cardinal(Seed))*1664525+1013904223) and UInt64($FFFFFFFF);
  Value:=((Value xor (Value shr 16))*UInt64(2246822519)) and UInt64($FFFFFFFF);
  Result:=(Value xor (Value shr 13))/4294967295;
end;

function CannonHazardRadius(Enemy:TCannonEnemy):Double;
const Radius:array[TCannonEnemy] of Double=(0,0.68,0.81,1.42,1.23,1.26,0.92,1.36);
begin
  Result:=Radius[Enemy];
end;

procedure TCannonStage.Resolve;
var I,J,K,Attacks,Damage,Destroyed,Quota,Front:Integer; Settle,Reserve,Delay,Impact:Double;
begin
  Parts:=CannonParts(Kind);
  SetLength(FGeometry,Length(Cues));
  SetLength(FDetach,Length(Parts));
  FDodges:=nil;
  FBuildSpan:=Min(0.73,(Stop-Start)*0.85);
  if Length(Cues)>0 then FBuildSpan:=Min(FBuildSpan,(Cues[0].Time-Start)*0.94);
  Attacks:=0;
  for I:=0 to High(Cues) do
    if Cues[I].Enemy=ceNone then Inc(Attacks)
    else FDodges:=FDodges+[I];
  Damage:=0;
  Destroyed:=0;
  Settle:=Stop-Finish;
  Reserve:=Min(0.23,Settle*0.20);
  for I:=0 to High(Cues) do begin
    if Cues[I].Enemy<>ceNone then Continue;
    Inc(Damage);
    Front:=FrontPart(Cues[I].Time);
    AimShot(I,Front);
    // 命中した面から手前の部品を順に外し、決着には残りの構造をまとめて崩す。
    Quota:=((Length(Parts)-2)*Damage+Attacks-1) div Attacks;
    if I=High(Cues) then Quota:=Length(Parts);
    J:=HitPart(I);
    K:=0;
    while Destroyed<Quota do begin
      Delay:=Min(0.52,K*0.085);
      if I=High(Cues) then
        Delay:=Min(Settle*0.29,K*Settle*0.08)
      else
        Delay:=Min(Delay,(Cues[I+1].Time-Cues[I].Time)*0.66);
      Impact:=Cues[I].Time+Delay;
      Parts[J].Attack:=I;
      Parts[J].BreakAt:=Impact;
      Parts[J].Drift:=(CannonNoise(121*J+53*Ord(Kind))-0.40)*(1.7+1.8*Cues[I].Power);
      Parts[J].Spin:=(CannonNoise(651*J+9)*2-1)*(0.8+2.8/Max(1.0,Parts[J].W));
      if Parts[J].Shape in [cpDeck,cpCar,cpEngine,cpGate] then
        Parts[J].Spin:=(0.83+0.41*Cues[I].Power)*(1-2*Ord(Odd(J)));
      Parts[J].LandAt:=Impact+Min(Stop-Impact-Reserve,
        0.22+Sqrt(Max(0.0,Parts[J].Y-Parts[J].H*0.27)*0.12)+0.16*Cues[I].Power);
      Inc(Destroyed);
      Inc(K);
      if Destroyed<Quota then J:=FrontPart(Impact);
    end;
  end;
  for I:=0 to High(Parts) do
    if Parts[I].Attack>=0 then FDetach[I]:=IntactPose(I,Parts[I].BreakAt-0.000001);
end;

function TCannonStage.Finish:Double;
begin
  if Length(Cues)>0 then Result:=Cues[High(Cues)].Time else Result:=Stop;
end;

function TCannonStage.DodgeCount(Time:Double):Integer;
var Lo,Hi,Mid:Integer;
begin
  Lo:=0;
  Hi:=Length(FDodges);
  while Lo<Hi do begin
    Mid:=(Lo+Hi) div 2;
    if Cues[FDodges[Mid]].Time<=Time then Lo:=Mid+1 else Hi:=Mid;
  end;
  Result:=Lo;
end;

function TCannonStage.HeroX(Time:Double):Double;
var Count:Integer; A,B,U:Double;
begin
  Count:=DodgeCount(Time+0.82);
  if Count=0 then Exit(CannonLeftLane+0.58*CannonEase((Time-Start)*1.5));
  A:=CannonLeftLane;
  B:=CannonRightLane;
  if not Odd(Count) then begin A:=CannonRightLane; B:=CannonLeftLane; end;
  if Count=1 then A:=A+0.58;
  U:=CannonEase((Time-Cues[FDodges[Count-1]].Time+0.82)/0.60);
  Result:=CannonMix(A,B,U);
end;

function TCannonStage.Threat(Time:Double):Double;
begin
  if Odd(DodgeCount(Time+0.000001)) then Result:=CannonLeftLane+0.28 else Result:=CannonRightLane;
end;

function TCannonStage.AssemblyTime(Index:Integer):Double;
begin
  // 下段を先に着地させ、上段へ短い時間差で積み上げる。
  Result:=Start+FBuildSpan*(0.64+0.28*EnsureRange(Parts[Index].Y/9.3,0.0,1.0)+
    0.08*CannonNoise(Ord(Kind)*47+Index));
end;

function TCannonStage.AssemblyDrop(Index:Integer;Time:Double):Double;
var FromTime,U:Double;
begin
  FromTime:=Start+FBuildSpan*0.13*CannonNoise(Index*19+27);
  U:=EnsureRange((Time-FromTime)/Max(0.000001,AssemblyTime(Index)-FromTime),0.0,1.0);
  Result:=1-Sqr(U);
end;

function TCannonStage.IntactPose(Index:Integer;Time:Double):TCannonPose;
var I:Integer; Tilt,Sag,U,PivotX,DX,Y,S,C,Drop:Double; Part:TCannonPart;
begin
  Part:=Parts[Index];
  Tilt:=0;
  Sag:=0;
  PivotX:=19.0;
  if CannonBoss(Kind) then
    for I:=0 to High(Parts) do
      if (Parts[I].Attack>=0) and (Parts[I].BreakAt<Time) and
        (((Kind=ctAirship) and (Parts[I].Shape=cpEngine)) or
          ((Kind<>ctAirship) and (Parts[I].Y<3.0) and
          (Parts[I].Shape in [cpGirder,cpEngine,cpArmor]))) then begin
        U:=CannonEase((Time-Parts[I].BreakAt)/0.51);
        Tilt:=Tilt+0.21*U*(1-2*Ord(Parts[I].X<PivotX));
        if Kind=ctAirship then Sag:=Sag+0.86*U else Sag:=Sag+0.16*U;
      end;
  if Part.Support>=0 then
    if (Parts[Part.Support].Attack>=0) and (Parts[Part.Support].BreakAt<Time) then begin
      U:=CannonEase((Time-Parts[Part.Support].BreakAt)/0.37);
      Tilt:=Tilt+0.24*U*(1-2*Ord(Odd(Index)));
      Sag:=Sag+0.46*U;
      PivotX:=Part.X;
    end;
  SinCos(Tilt,S,C);
  DX:=Part.X-PivotX;
  Y:=Part.Y;
  Drop:=AssemblyDrop(Index,Time);
  Result.X:=PivotX+DX*C-Y*S+(CannonNoise(Index*17+113)-0.35)*1.0*Drop;
  Result.Y:=CannonMix(Max(Part.H*0.40,DX*S+Y*C-Sag),
    CannonHeight+1.1+Part.H*0.58,Drop);
  Result.Angle:=Tilt+(CannonNoise(Index*19+133)-0.5)*0.33*Drop;
end;

function TCannonStage.PartPose(Index:Integer;Time:Double):TCannonPose;
var Part:TCannonPart; Base:TCannonPose; Age,U,Ground,After,Drop:Double;
begin
  Part:=Parts[Index];
  if (Part.Attack<0) or (Time<Part.BreakAt) then Exit(IntactPose(Index,Time));
  Base:=FDetach[Index];
  Age:=Time-Part.BreakAt;
  // 重い部品は先に傾き、落下を加速して着地後に短く跳ねる。
  U:=EnsureRange(Age/Max(0.000001,Part.LandAt-Part.BreakAt),0.0,1.0);
  Ground:=Min(Base.Y,Max(0.16,(Abs(Sin(Base.Angle+Part.Spin))*Part.W+
    Abs(Cos(Base.Angle+Part.Spin))*Part.H)*0.37));
  After:=Max(0.0,Time-Part.LandAt);
  Drop:=Sqr(Max(0.0,(U-0.12)/0.88));
  Result.X:=Base.X+Part.Drift*Sqr(U)+Part.Drift*0.20*CannonEase(After*3.0);
  Result.Y:=CannonMix(Base.Y,Ground,Drop)+Min(0.30,Part.H*0.15)*Sin(Pi*Min(1.0,After*4));
  Result.Angle:=Base.Angle+Part.Spin*(0.18*U+0.82*Sqr(U))+0.17*Sin(10*After)*Exp(-6*After);
end;

function TCannonStage.ShatterTime(Index:Integer):Double;
begin
  if not CannonBoss(Kind) or (Parts[Index].Attack<0) then Exit(Infinity);
  Result:=Parts[Index].LandAt+Min(0.06,(Stop-Parts[Index].LandAt)*0.25);
end;

function TCannonStage.Aim(Index,Barrel:Integer):TPointF;
begin
  Result:=FGeometry[Index].Aim[Barrel];
end;

function TCannonStage.HitPart(Index:Integer):Integer;
begin
  Result:=FGeometry[Index].Part;
end;

function TCannonStage.Wear(Index:Integer;Time:Double):Double;
var I:Integer;
begin
  Result:=0;
  for I:=0 to High(Cues) do begin
    if Cues[I].Time>Time then Break;
    if (Cues[I].Enemy=ceNone) and (FGeometry[I].Part=Index) then
      Result:=Min(0.66,Result+0.16+Cues[I].Power*0.08);
  end;
end;

function TCannonStage.Pivot(Barrel:Integer;Time:Double):TPointF;
begin
  if Barrel=0 then Exit(PointF(HeroX(Time),0.98));
  Result:=PointF(1.20+(Barrel-1)*1.27,2.08+0.29*(Barrel mod 2));
end;

function TCannonStage.Launch(Index,Barrel:Integer):Double;
begin
  Result:=Cues[Index].Time-Cues[Index].Lead+Barrel*Min(0.048,Cues[Index].Lead*0.12);
end;

function TCannonStage.FrontPart(Time:Double):Integer;
var I:Integer; P:TCannonPose; Left,Nearest,S,C:Double; Part:TCannonPart;
begin
  Result:=-1;
  Nearest:=Infinity;
  for I:=0 to High(Parts) do begin
    Part:=Parts[I];
    if Part.Attack>=0 then Continue;
    P:=IntactPose(I,Time);
    SinCos(P.Angle,S,C);
    Left:=P.X-(Abs(C)*Part.W+Abs(S)*Part.H)*0.5;
    if Left<Nearest then begin
      Nearest:=Left;
      Result:=I;
    end;
  end;
end;

function TCannonStage.Trace(const Origin,Target:TPointF;Time:Double;out HitPart:Integer):Double;
var I:Integer; Part:TCannonPart; P:TCannonPose; X,Y,DX,DY,S,C,HalfW,HalfH,EnterAt,LeaveAt:Double;

  function Clip(From,Delta,Half:Double):Boolean;
  var A,B:Double;
  begin
    if Abs(Delta)<1E-9 then Exit(Abs(From)<=Half);
    A:=(-Half-From)/Delta;
    B:=(Half-From)/Delta;
    EnterAt:=Max(EnterAt,Min(A,B));
    LeaveAt:=Min(LeaveAt,Max(A,B));
    Result:=EnterAt<=LeaveAt;
  end;

begin
  HitPart:=-1;
  Result:=1;
  DX:=Target.X-Origin.X;
  DY:=Target.Y-Origin.Y;
  for I:=0 to High(Parts) do begin
    Part:=Parts[I];
    if (Part.Attack>=0) and (Part.BreakAt<Time) then Continue;
    P:=IntactPose(I,Time);
    SinCos(P.Angle,S,C);
    HalfW:=Part.W*0.5+CannonShellClearance;
    HalfH:=Part.H*0.5+CannonShellClearance;
    if P.X-Abs(C)*HalfW-Abs(S)*HalfH>Origin.X+DX*Result then Continue;
    X:=Origin.X-P.X;
    Y:=Origin.Y-P.Y;
    EnterAt:=0;
    LeaveAt:=Result;
    // 回転した部品のローカル座標で弾の半径を含む表面を求める。
    if Clip(X*C+Y*S,DX*C+DY*S,HalfW) and Clip(Y*C-X*S,DY*C-DX*S,HalfH) then begin
      Result:=EnterAt;
      HitPart:=I;
    end;
  end;
end;

procedure TCannonStage.AimShot(Index,Front:Integer);
var Barrel,Contact:Integer; Base,Center,Origin:TPointF; Pose:TCannonPose; Angle,Reach,U,Time:Double;
begin
  Time:=Cues[Index].Time;
  Pose:=IntactPose(Front,Time);
  Center:=PointF(Pose.X,Pose.Y);
  for Barrel:=0 to Cues[Index].Volley-1 do begin
    Base:=Pivot(Barrel,Launch(Index,Barrel));
    Angle:=ArcTan2(Center.Y-Base.Y,Center.X-Base.X);
    if Barrel=0 then Reach:=1.20 else Reach:=0.70;
    Origin:=PointF(Base.X+Reach*Cos(Angle),Base.Y+Reach*Sin(Angle));
    U:=Trace(Origin,Center,Time,Contact);
    FGeometry[Index].Muzzle[Barrel]:=Origin;
    FGeometry[Index].Aim[Barrel]:=PointF(CannonMix(Origin.X,Center.X,U),CannonMix(Origin.Y,Center.Y,U));
    if Barrel=0 then FGeometry[Index].Part:=Contact;
  end;
end;

function TCannonStage.Muzzle(Index,Barrel:Integer):TPointF;
begin
  Result:=FGeometry[Index].Muzzle[Barrel];
end;

function TCannonStage.Shell(Index,Barrel:Integer;Time:Double):TPointF;
var Origin,Target:TPointF; T,U:Double; Contact:Integer;
begin
  Origin:=Muzzle(Index,Barrel);
  Target:=Aim(Index,Barrel);
  T:=Launch(Index,Barrel);
  U:=EnsureRange((Time-T)/(Cues[Index].Time-T),0.0,1.0);
  if (U<1) and (CannonMix(Origin.X,Target.X,U)>8.5) then
    // 飛行中も傾く支柱や装甲を突き抜けない。
    U:=Min(U,Trace(Origin,Target,Time,Contact));
  Result:=PointF(CannonMix(Origin.X,Target.X,U),CannonMix(Origin.Y,Target.Y,U));
end;

function TCannonStage.EnemyOrigin(Time:Double):TPointF;
var I:Integer; P:TCannonPose;
begin
  for I:=0 to High(Parts) do
    if (Parts[I].Shape=cpTurret) and ((Parts[I].Attack<0) or (Parts[I].BreakAt>Time)) then begin
      P:=PartPose(I,Time);
      Exit(PointF(P.X-Parts[I].W*0.45,P.Y));
    end;
  P:=PartPose(High(Parts),Time);
  Result:=PointF(P.X-Parts[High(Parts)].W*0.48,P.Y);
end;

function TCannonStage.SupportHit(Index:Integer):Integer;
begin
  Result:=FSupportHits[Index];
end;

procedure TCannonPlan.ResolveSupport;
var
  Shots:array[1..3] of TList<Double>;
  Next:array[1..3] of Integer;
  Stage:TCannonStage;
  Cue:TCannonCue;
  I,Barrel,Current:Integer;

  procedure Deploy(Gun:Integer;Ready:Double);
  var Life:TCannonSupportLife;
  begin
    Life.Arrival:=Max(0.0,Ready-0.38);
    Life.Ready:=Ready;
    Life.Lost:=Infinity;
    FSupport[Gun]:=FSupport[Gun]+[Life];
  end;

begin
  for Barrel:=1 to 3 do Shots[Barrel]:=nil;
  try
    for Barrel:=1 to 3 do begin
      Shots[Barrel]:=TList<Double>.Create;
      FSupport[Barrel]:=nil;
      Next[Barrel]:=0;
    end;
    for Stage in Stages do begin
      Stage.FSupportHits:=nil;
      SetLength(Stage.FSupportHits,Length(Stage.Cues));
      for I:=0 to High(Stage.Cues) do
        for Barrel:=1 to Stage.Cues[I].Volley-1 do
          Shots[Barrel].Add(Stage.Launch(I,Barrel));
    end;
    for Barrel:=1 to 3 do begin
      Shots[Barrel].Sort;
      if Shots[Barrel].Count>0 then Deploy(Barrel,Shots[Barrel][0]);
    end;
    // 曲全体で在籍を持ち、場面転換や発射間隔を退場の条件にしない。
    for Stage in Stages do
      for I:=0 to High(Stage.Cues) do begin
        Cue:=Stage.Cues[I];
        if Cue.Enemy=ceNone then Continue;
        for Barrel:=3 downto 1 do begin
          Current:=High(FSupport[Barrel]);
          if (Current<0) or (FSupport[Barrel][Current].Ready>Cue.Time-Cue.Lead) or
            not IsInfinite(FSupport[Barrel][Current].Lost) then Continue;
          FSupport[Barrel][Current].Lost:=Cue.Time;
          Stage.FSupportHits[I]:=Barrel;
          while (Next[Barrel]<Shots[Barrel].Count) and
            (Shots[Barrel][Next[Barrel]]<Cue.Time+CannonSupportRearm) do Inc(Next[Barrel]);
          if Next[Barrel]<Shots[Barrel].Count then Deploy(Barrel,Shots[Barrel][Next[Barrel]]);
          Break;
        end;
        if Stage.FSupportHits[I]>0 then Break;
      end;
  finally
    for Barrel:=1 to 3 do Shots[Barrel].Free;
  end;
end;

function TCannonPlan.SupportAt(Barrel:Integer;Time:Double;out Life:TCannonSupportLife):Boolean;
var Lo,Hi,Mid:Integer;
begin
  Lo:=0;
  Hi:=Length(FSupport[Barrel]);
  while Lo<Hi do begin
    Mid:=(Lo+Hi) div 2;
    if FSupport[Barrel][Mid].Arrival<=Time then Lo:=Mid+1 else Hi:=Mid;
  end;
  Result:=Lo>0;
  if Result then Life:=FSupport[Barrel][Lo-1];
end;

function TCannonPlan.Fires(Stage:TCannonStage;Index,Barrel:Integer):Boolean;
var Time:Double; Life:TCannonSupportLife;
begin
  if Barrel>=Stage.Cues[Index].Volley then Exit(False);
  if Barrel=0 then Exit(True);
  Time:=Stage.Launch(Index,Barrel);
  Result:=SupportAt(Barrel,Time,Life) and (Time>=Life.Ready) and (Time<Life.Lost);
end;

destructor TCannonPlan.Destroy;
var Stage:TCannonStage;
begin
  for Stage in Stages do Stage.Free;
  inherited;
end;

function TCannonPlan.StageAt(Time:Double):Integer;
var Lo,Hi,Mid:Integer;
begin
  Lo:=0;
  Hi:=High(Stages);
  while Lo<Hi do begin
    Mid:=(Lo+Hi+1) div 2;
    if Stages[Mid].Start<=Time then Lo:=Mid else Hi:=Mid-1;
  end;
  Result:=Lo;
end;
end.
