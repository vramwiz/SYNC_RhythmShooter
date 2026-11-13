unit RhythmMelodyPlan;
// 重力で転がる中実球の保存型と幾何。世界単位=m、右/上が正、原音声秒を使う。
// 支持中はI=2mr^2/5の転がり、離床中は一定重力。再生は保存済み解を読むだけ。
interface
uses System.SysUtils;
const MelodyRadius=0.24;
  MelodyGravity=9.81;
  MelodyInertia=0.4;
  MelodyPaddleArm=0.95;
  MelodyHammerArm=0.90;
  MelodyHammerRadius=0.12;
  MelodyHammerStroke=1.10;
  MelodyRotorInertia=2*MelodyPaddleArm*MelodyPaddleArm;
  MelodyPaddleRestitution=0.15;
type
  TMelodyPoint=record X,Y:Double; end;
  // 保存IDの順序を維持する。水平板への落下、または球が駆動するハンマーの実打撃。
  TMelodyCourse=(mcSlope,mcCurve,mcCrest,mcValley,mcHop,mcJump,mcLoop,
    mcWave,mcSeesaw,mcHammer,mcFlipper,mcTrapdoor,mcBranch,mcArm,mcLift,mcWheel,mcBelt);
  TMelodyBarKind=(mbNormal,mbSpring,mbPower,mbAngled,mbRotating,mbRapid,mbGiant,mbSoft);
  TMelodyMotion=(mmRolling,mmFlight,mmRest,mmSpring);
  TMelodyStrike=(msStep,msSpring,msHammer);
  TMelodySectionKind=(mpSteps,mpSeesaw,mpSpring,mpTurns);
  TMelodySection=record
    Start,Finish:Double;
    Kind:TMelodySectionKind;
    SourceCount:Integer;
  end;
  TMelodyKnot=packed record
    Time,Distance,Speed:Double; // 区間内の秒、弧長m、接線速度m/s。準備時の力学解。
  end;
  TMelodySpan=record
    Start,Finish:Double;
    A,B,Launch:TMelodyPoint;
    Theta,Curvature,Speed,Drag,Spin,SpringOmega:Double;
    // Theta=出発接線rad、Curvature=符号付き1/m、Drag=抵抗1/s、Spin=出発時の向きrad。
    Motion:TMelodyMotion;
    Kind:TMelodyCourse;
    Direction:Integer; // 局所xの向き。左向きでも支持法線は上側、速度は正の弧長速度。
    Knots:TArray<TMelodyKnot>;
    MinX,MaxX,MinY,MaxY:Double; // 復元時に作る描画範囲。力学解は再生成しない。
  end;
  TMelodyBar=record
    Time,Power,Left,Right,Top,Restitution:Double;
    Contact:TMelodyPoint;
    Kind:TMelodyBarKind;
    Source,Span:Integer;
    Terminal:Boolean;
    Strike:TMelodyStrike;
    Trigger,AngularSpeed:Double;
    TriggerSpan:Integer;
    Pivot:TMelodyPoint; // 坂道の球が押すパドルと、釣り合い錘付きハンマーの固定支点。
    MechanismScale,RotorRatio:Double; // 連続打撃には小さく軽い機構を使い、球の前進を保つ。
  end;
  TMelodyPlan=class
  private
    FCameraKeys:TArray<TMelodyPoint>;
    FZoomKeys:TArray<Double>;
  public
    Duration,EndTime:Double;
    Beat,BeatOrigin,BeatConfidence,SectionLength:Double;
    Meter:Integer; // 0は拍節不明。3/4拍子が推定できた場合だけ4小節の区切りを使う。
    Sections:TArray<TMelodySection>;
    Bars:TArray<TMelodyBar>;
    Spans:TArray<TMelodySpan>;
  private
    function CameraGuide(Time:Double):TMelodyPoint;
  public
    procedure IndexGeometry(const Cancel:TFunc<Boolean> = nil);
    procedure Validate;
    function SpanAt(Time:Double):Integer;
    function BarAt(Time:Double):Integer;
    function SectionAt(Time:Double):Integer;
    function Position(Time:Double):TMelodyPoint;
    function Velocity(Time:Double):TMelodyPoint;
    function Rotation(Time:Double):Double;
    function BarCompression(Index:Integer; Time:Double):Double;
    // IndexGeometryで作るC2のカメラ経路。球の反発やバネの圧縮を追わない。
    function CameraPoint(Time:Double):TMelodyPoint;
    function CameraZoom(Time:Double):Double;
  end;
function MelodyPoint(X,Y:Double):TMelodyPoint;
function MelodyMix(const A,B:TMelodyPoint; U:Double):TMelodyPoint;
function MelodyLength(const P:TMelodyPoint):Double;
function MelodyUnit(const P:TMelodyPoint):TMelodyPoint;
function MelodySmooth(U:Double):Double;
function MelodyAcceleration(Theta,Speed,Drag:Double):Double;
function MelodyNormalForce(Theta,Speed,Curvature:Double):Double;
// 弧長から搬送用の木レールと球中心を求める。鉄琴の板は別の水平面として保存する。
function MelodyTrackPoint(const S:TMelodySpan; Distance:Double):TMelodyPoint;
function MelodyRailPoint(const S:TMelodySpan; Distance:Double):TMelodyPoint;
procedure MelodyTravel(const S:TMelodySpan; Time:Double; out Distance,Speed:Double);
function MelodySample(const S:TMelodySpan; U:Double):TMelodyPoint;
function MelodySpanVelocity(const S:TMelodySpan; Time:Double):TMelodyPoint;
function MelodyRail(const S:TMelodySpan; U:Double):TMelodyPoint;
function MelodyHasRail(Kind:TMelodyCourse):Boolean;
function MelodyCompression(const S:TMelodySpan; Time:Double):Double;
function MelodyHammer(const B:TMelodyBar; Direction:Integer; Time:Double):TMelodyPoint;
function MelodyHammerSpeed(Speed:Double; Scale:Double=1; RotorRatio:Double=2):Double;
function MelodyHammerInertia(const B:TMelodyBar):Double;
function MelodyCounterArm(const B:TMelodyBar):Double;
function MelodyStroke(const B:TMelodyBar):Double;
function MelodyHeadAngle(const B:TMelodyBar; Time:Double):Double;
implementation
uses System.Math;
function MelodyPoint(X,Y:Double):TMelodyPoint;
begin Result.X:=X; Result.Y:=Y; end;
function MelodyMix(const A,B:TMelodyPoint; U:Double):TMelodyPoint;
begin Result:=MelodyPoint(A.X+(B.X-A.X)*U,A.Y+(B.Y-A.Y)*U); end;
function MelodyLength(const P:TMelodyPoint):Double;
begin Result:=Sqrt(Sqr(P.X)+Sqr(P.Y)); end;
function MelodyUnit(const P:TMelodyPoint):TMelodyPoint;
var L:Double;
begin L:=Max(1E-12,MelodyLength(P)); Result:=MelodyPoint(P.X/L,P.Y/L); end;
function MelodySmooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0); Result:=U*U*U*(10+U*(-15+6*U)); end;
function MelodyAcceleration(Theta,Speed,Drag:Double):Double;
begin Result:=-MelodyGravity*Sin(Theta)/(1+MelodyInertia)-Drag*Speed; end;
function MelodyNormalForce(Theta,Speed,Curvature:Double):Double;
begin Result:=MelodyGravity*Cos(Theta)+Sqr(Speed)*Curvature; end;
function MelodyTrackPoint(const S:TMelodySpan; Distance:Double):TMelodyPoint;
var T:Double;
begin
  T:=S.Theta+S.Curvature*Distance;
  if Abs(S.Curvature)<1E-9 then Result:=MelodyPoint(S.A.X+S.Direction*Distance*Cos(S.Theta),S.A.Y+Distance*Sin(S.Theta))
  else Result:=MelodyPoint(S.A.X+S.Direction*(Sin(T)-Sin(S.Theta))/S.Curvature,
    S.A.Y-(Cos(T)-Cos(S.Theta))/S.Curvature);
end;
function MelodyRailPoint(const S:TMelodySpan; Distance:Double):TMelodyPoint;
var T:Double;
begin
  Result:=MelodyTrackPoint(S,Distance); T:=S.Theta+S.Curvature*Distance;
  Result.X:=Result.X+S.Direction*MelodyRadius*Sin(T); Result.Y:=Result.Y-MelodyRadius*Cos(T);
end;
procedure MelodyTravel(const S:TMelodySpan; Time:Double; out Distance,Speed:Double);
var L,H,M:Integer; A,B:TMelodyKnot; U,T,H0,H1,H2,H3:Double;
begin
  Time:=EnsureRange(Time,0.0,S.Finish-S.Start); L:=0; H:=High(S.Knots);
  while L<H do begin M:=(L+H) div 2; if S.Knots[M].Time<Time then L:=M+1 else H:=M; end;
  H:=Max(1,L); A:=S.Knots[H-1]; B:=S.Knots[H]; T:=B.Time-A.Time;
  U:=EnsureRange((Time-A.Time)/T,0.0,1.0);
  // 弧長と時間微分を同じHermite式から得る。形状を勝手に接続する補間ではない。
  H0:=2*U*U*U-3*U*U+1; H1:=1-H0; H2:=U*U*U-2*U*U+U; H3:=U*U*U-U*U;
  Distance:=H0*A.Distance+H1*B.Distance+T*(H2*A.Speed+H3*B.Speed);
  Speed:=((6*U*U-6*U)*A.Distance+(-6*U*U+6*U)*B.Distance)/T+
    (3*U*U-4*U+1)*A.Speed+(3*U*U-2*U)*B.Speed;
end;
function MelodySample(const S:TMelodySpan; U:Double):TMelodyPoint;
var T,D,V:Double;
begin
  T:=EnsureRange(U,0.0,1.0)*(S.Finish-S.Start);
  if S.Motion=mmRest then Exit(S.A);
  if S.Motion=mmSpring then
    Exit(MelodyPoint(S.A.X+S.Launch.X*T,S.A.Y-MelodyCompression(S,T)));
  if S.Motion=mmFlight then Exit(MelodyPoint(S.A.X+S.Launch.X*T,S.A.Y+S.Launch.Y*T-0.5*MelodyGravity*T*T));
  MelodyTravel(S,T,D,V); Result:=MelodyTrackPoint(S,D);
end;
function MelodySpanVelocity(const S:TMelodySpan; Time:Double):TMelodyPoint;
var D,V,T:Double;
begin
  Time:=EnsureRange(Time,0.0,S.Finish-S.Start);
  if S.Motion=mmRest then Exit(MelodyPoint(0,0));
  if S.Motion=mmSpring then Exit(MelodyPoint(S.Launch.X,
    -MelodyGravity/S.SpringOmega*Sin(S.SpringOmega*Time)+S.Launch.Y*Cos(S.SpringOmega*Time)));
  if S.Motion=mmFlight then Exit(MelodyPoint(S.Launch.X,S.Launch.Y-MelodyGravity*Time));
  MelodyTravel(S,Time,D,V); T:=S.Theta+S.Curvature*D;
  Result:=MelodyPoint(S.Direction*V*Cos(T),V*Sin(T));
end;
function MelodyRail(const S:TMelodySpan; U:Double):TMelodyPoint;
var D,V:Double;
begin MelodyTravel(S,EnsureRange(U,0.0,1.0)*(S.Finish-S.Start),D,V); Result:=MelodyRailPoint(S,D); end;
function MelodyHasRail(Kind:TMelodyCourse):Boolean;
begin Result:=Kind in [mcSlope,mcCurve,mcCrest,mcValley,mcLoop,mcWave]; end;
function MelodyCompression(const S:TMelodySpan; Time:Double):Double;
var W:Double;
begin
  Time:=EnsureRange(Time,0.0,S.Finish-S.Start); W:=S.SpringOmega;
  Result:=MelodyGravity/(W*W)*(1-Cos(W*Time))-S.Launch.Y/W*Sin(W*Time);
end;
function MelodyHammerSpeed(Speed,Scale,RotorRatio:Double):Double;
begin
  // 接線方向の衝突。転がる球の有効質量1.4、静止ローターのIと腕長から角運動量を解く。
  Result:=(1+MelodyPaddleRestitution)*Speed/
    (MelodyPaddleArm*Scale*(1+RotorRatio/(1+MelodyInertia)));
end;
function MelodyHammerInertia(const B:TMelodyBar):Double;
begin Result:=B.RotorRatio*Sqr(MelodyPaddleArm*B.MechanismScale); end;
function MelodyCounterArm(const B:TMelodyBar):Double;
begin
  // 連続打撃では球が支点の下を素早く抜ける。重い錘を軸近くへ置いて通路を開ける。
  if B.MechanismScale<0.9 then Result:=0.05 else Result:=0.50;
end;
function MelodyStroke(const B:TMelodyBar):Double;
begin if B.MechanismScale<1 then Result:=1.65 else Result:=MelodyHammerStroke; end;
function MelodyHeadAngle(const B:TMelodyBar; Time:Double):Double;
begin
  Result:=EnsureRange((Time-B.Trigger)*B.AngularSpeed,0.0,MelodyStroke(B));
  if B.MechanismScale<1 then Result:=Result-0.35;
end;
function MelodyHammer(const B:TMelodyBar; Direction:Integer; Time:Double):TMelodyPoint;
var Angle:Double;
begin
  Angle:=MelodyHeadAngle(B,Time);
  Result:=MelodyPoint(B.Pivot.X+Direction*B.MechanismScale*MelodyHammerArm*Cos(Angle),
    B.Pivot.Y+B.MechanismScale*MelodyHammerArm*Sin(Angle));
end;
function TMelodyPlan.SpanAt(Time:Double):Integer;
var L,H,M:Integer;
begin
  L:=0; H:=High(Spans);
  while L<H do begin M:=(L+H) div 2; if Time<Spans[M].Finish then H:=M else L:=M+1; end;
  Result:=L;
end;
function TMelodyPlan.BarAt(Time:Double):Integer;
var L,H,M:Integer;
begin
  L:=0; H:=Length(Bars);
  while L<H do begin M:=(L+H) div 2; if Bars[M].Time<=Time then L:=M+1 else H:=M; end;
  Result:=L-1;
end;
function TMelodyPlan.SectionAt(Time:Double):Integer;
var L,H,M:Integer;
begin
  L:=0; H:=High(Sections);
  while L<H do begin M:=(L+H) div 2; if Time<Sections[M].Finish then H:=M else L:=M+1; end;
  Result:=L;
end;
function TMelodyPlan.Position(Time:Double):TMelodyPoint;
var I:Integer;
begin I:=SpanAt(Time); Result:=MelodySample(Spans[I],(Time-Spans[I].Start)/(Spans[I].Finish-Spans[I].Start)); end;
function TMelodyPlan.Velocity(Time:Double):TMelodyPoint;
var I:Integer;
begin
  if (Time<0) or (Time>=EndTime) then Exit(MelodyPoint(0,0));
  I:=SpanAt(Time); Result:=MelodySpanVelocity(Spans[I],Time-Spans[I].Start);
end;
function TMelodyPlan.Rotation(Time:Double):Double;
var I:Integer; D,V,T:Double;
begin
  I:=SpanAt(Time); T:=EnsureRange(Time-Spans[I].Start,0.0,Spans[I].Finish-Spans[I].Start);
  if Spans[I].Motion=mmRest then Exit(Spans[I].Spin);
  if Spans[I].Motion in [mmFlight,mmSpring] then D:=Spans[I].Speed*T else MelodyTravel(Spans[I],T,D,V);
  Result:=Spans[I].Spin+Spans[I].Direction*D/MelodyRadius;
end;
function TMelodyPlan.BarCompression(Index:Integer; Time:Double):Double;
var S:TMelodySpan;
begin
  Result:=0; if Bars[Index].Strike<>msSpring then Exit;
  S:=Spans[Bars[Index].Span+1];
  if (S.Motion=mmSpring) and (Time>S.Start) and (Time<S.Finish) then
    Result:=Max(0.0,MelodyCompression(S,Time-S.Start));
end;
function TMelodyPlan.CameraGuide(Time:Double):TMelodyPoint;
var I,J,K:Integer; S:TMelodySpan; HasRail:Boolean;
begin
  Time:=EnsureRange(Time,0.0,EndTime); I:=BarAt(Time);
  if (I>=0) and (I<High(Bars)) then begin
    HasRail:=False;
    for K:=Bars[I].Span+1 to Bars[I+1].Span do
      if (Spans[K].Motion=mmRolling) and MelodyHasRail(Spans[K].Kind) then begin HasRail:=True; Break; end;
    if not HasRail then
      Exit(MelodyMix(Bars[I].Contact,Bars[I+1].Contact,(Time-Bars[I].Time)/(Bars[I+1].Time-Bars[I].Time)));
  end;
  J:=SpanAt(Time); S:=Spans[J];
  if (S.Motion=mmRolling) or ((S.Motion=mmFlight) and (S.Finish-S.Start>0.55)) then
    Result:=MelodySample(S,(Time-S.Start)/(S.Finish-S.Start))
  else Result:=MelodyMix(S.A,S.B,EnsureRange((Time-S.Start)/(S.Finish-S.Start),0.0,1.0));
end;
function TMelodyPlan.CameraPoint(Time:Double):TMelodyPoint;
var I,J:Integer; U,W:Double;
begin
  U:=EnsureRange(Time,0.0,EndTime)/0.20+4; I:=Floor(U); U:=U-I; Result:=MelodyPoint(0,0);
  for J:=0 to 3 do begin
    case J of
      0:W:=Power(1-U,3)/6;
      1:W:=(3*U*U*U-6*U*U+4)/6;
      2:W:=(-3*U*U*U+3*U*U+3*U+1)/6;
      else W:=U*U*U/6;
    end;
    Result.X:=Result.X+FCameraKeys[I+J-1].X*W;
    Result.Y:=Result.Y+FCameraKeys[I+J-1].Y*W;
  end;
end;
function TMelodyPlan.CameraZoom(Time:Double):Double;
var I,J:Integer; U,W:Double;
begin
  U:=EnsureRange(Time,0.0,EndTime)/0.20+4; I:=Floor(U); U:=U-I; Result:=0;
  for J:=0 to 3 do begin
    case J of
      0:W:=Power(1-U,3)/6;
      1:W:=(3*U*U*U-6*U*U+4)/6;
      2:W:=(-3*U*U*U+3*U*U+3*U+1)/6;
      else W:=U*U*U/6;
    end;
    Result:=Result+FZoomKeys[I+J-1]*W;
  end;
end;
procedure TMelodyPlan.IndexGeometry(const Cancel:TFunc<Boolean>);
var I,J:Integer; P,Q:TMelodyPoint; W,Total,T,Speed,LowSince,WideUntil:Double;
  Zoom,Target,FromZoom,ChangeAt,Transition:Double;
begin
  for I:=0 to High(Spans) do begin
    if Assigned(Cancel) and Cancel() then Abort;
    P:=Spans[I].A; Spans[I].MinX:=P.X; Spans[I].MaxX:=P.X; Spans[I].MinY:=P.Y; Spans[I].MaxY:=P.Y;
    for J:=1 to 96 do begin
      P:=MelodySample(Spans[I],J/96);
      Spans[I].MinX:=Min(Spans[I].MinX,P.X); Spans[I].MaxX:=Max(Spans[I].MaxX,P.X);
      Spans[I].MinY:=Min(Spans[I].MinY,P.Y); Spans[I].MaxY:=Max(Spans[I].MaxY,P.Y);
    end;
  end;
  // 固定時間格子の平滑経路を準備する。描画で前フレームや瞬間速度を参照しない。
  SetLength(FCameraKeys,Ceil(EndTime/0.20)+12);
  for I:=0 to High(FCameraKeys) do begin
    if Assigned(Cancel) and Cancel() then Abort;
    P:=MelodyPoint(0,0); Total:=0;
    for J:=-9 to 9 do begin
      W:=Exp(-0.5*Sqr(J*0.10/0.40)); Q:=CameraGuide((I-4)*0.20+J*0.10);
      P.X:=P.X+W*Q.X; P.Y:=P.Y+W*Q.Y; Total:=Total+W;
    end;
    FCameraKeys[I]:=MelodyPoint(P.X/Total,P.Y/Total);
  end;
  // 遅い流れが2.6秒以上続く場合だけ寄る。速さは構造経路の1秒差で測り、圧縮を参照しない。
  SetLength(FZoomKeys,Length(FCameraKeys)); LowSince:=-1; WideUntil:=1.5;
  Zoom:=1; Target:=1; FromZoom:=1; ChangeAt:=-10; Transition:=2;
  for I:=0 to High(FZoomKeys) do begin
    T:=(I-4)*0.20;
    Zoom:=FromZoom+(Target-FromZoom)*MelodySmooth((T-ChangeAt)/Transition);
    P:=CameraPoint(T+1.4); Q:=CameraPoint(T+0.4);
    Speed:=MelodyLength(MelodyPoint(P.X-Q.X,P.Y-Q.Y));
    if (Speed<5.5) and (T>1.5) and (T<Duration-1) then begin
      if LowSince<0 then LowSince:=T;
    end else LowSince:=-1;
    if (Target>1) and ((Speed>7.0) or (T>=Duration-0.5)) then begin
      FromZoom:=Zoom; Target:=1; ChangeAt:=T; Transition:=1.2; WideUntil:=T+8.0;
    end else if (Target=1) and (LowSince>=0) and (T-LowSince>=2.6) and (T>=WideUntil) then begin
      FromZoom:=Zoom; Target:=1.35; ChangeAt:=T; Transition:=2.0;
    end;
    FZoomKeys[I]:=Zoom;
  end;
end;
procedure TMelodyPlan.Validate;
var I,J,K,Counts:Integer; S,After:TMelodySpan; P,V,Incoming,Outgoing:TMelodyPoint;
  D,Speed,Theta,PreviousEnergy,Energy,T,Impulse,RailStart:Double;
  procedure Need(B:Boolean; const Why:string);
  begin if not B then raise EConvertError.Create('メロディボール物理計画: '+Why); end;
  function Finite(V:Double):Boolean;
  begin Result:=not IsNan(V) and not IsInfinite(V) and (Abs(V)<1E7); end;
begin
  Need(Finite(Duration) and InRange(Duration,0.001,3044.0),'音声長');
  Need(Finite(EndTime) and (EndTime>=Duration) and (EndTime<=Duration+2),'終端');
  Need(Finite(Beat) and Finite(BeatOrigin) and InRange(BeatConfidence,0.0,1.0) and
    (Meter in [0,3,4]) and InRange(SectionLength,4.0,16.0),'拍節の推定');
  if Meter=0 then Need((Beat=0) and (BeatOrigin=0) and (SectionLength=8),'拍節不明の時間区切り')
  else Need(InRange(Beat,1/3,1.0) and (BeatOrigin>=0) and (BeatOrigin<Beat*Meter) and
    (Abs(SectionLength-4*Meter*Beat)<1E-7),'推定4小節');
  Need(InRange(Length(Sections),1,1024),'演出区間'); T:=0;
  for I:=0 to High(Sections) do begin
    Need((Sections[I].Start=T) and (Sections[I].Finish>T) and
      (Sections[I].Finish<=Duration) and (Sections[I].SourceCount>=0),'演出区間の範囲');
    if I>0 then Need(Sections[I].Kind<>Sections[I-1].Kind,'同じ演出の連続は禁止');
    if I=0 then Need(Sections[I].Finish-T<=SectionLength+Beat*Meter/2+1E-7,'導入と推定小節への整列')
    else Need(Sections[I].Finish-T<=SectionLength+1E-7,'演出を4小節程度で切り替える');
    T:=Sections[I].Finish;
  end;
  Need(T=Duration,'演出区間の全曲範囲');
  Need(InRange(Length(Spans),1,300000) and (Length(Bars)<=100000),'要素数'); T:=0; PreviousEnergy:=1E20;
  RailStart:=0;
  for I:=0 to High(Spans) do begin
    S:=Spans[I]; Need(Finite(S.Start) and Finite(S.Finish) and (S.Start=T) and (S.Finish>S.Start) and (S.Finish<=EndTime),'時間範囲');
    Need(Abs(S.Direction)=1,'左右の向き');
    Need(Finite(S.A.X) and Finite(S.A.Y) and Finite(S.B.X) and Finite(S.B.Y) and
      Finite(S.Theta) and Finite(S.Curvature) and Finite(S.Speed) and Finite(S.Drag) and
      Finite(S.Spin) and Finite(S.SpringOmega) and InRange(S.Speed,0.0,60.0) and InRange(S.Drag,0.0,2.0),'保存値');
    if I=0 then Need((S.Speed=0) and (S.Launch.X=0) and (S.Launch.Y=0),'静止から開始');
    if I>0 then Need((Abs(S.A.X-Spans[I-1].B.X)<1E-8) and (Abs(S.A.Y-Spans[I-1].B.Y)<1E-8),'位置の連続性');
    if (I>0) and (S.Direction<>Spans[I-1].Direction) then
      Need((S.Motion=mmRolling) and MelodyHasRail(S.Kind) and (Spans[I-1].Motion=mmFlight),'受け面で左右を切り替える');
    if S.Motion=mmRolling then begin
      Need((MelodyHasRail(S.Kind) or (S.Kind=mcArm)) and InRange(Length(S.Knots),2,1024),'支持解');
      Need((S.Knots[0].Time=0) and (S.Knots[0].Distance=0) and (S.Knots[0].Speed=S.Speed),'支持解の開始');
      for J:=0 to High(S.Knots) do begin
        Need(Finite(S.Knots[J].Time) and Finite(S.Knots[J].Distance) and Finite(S.Knots[J].Speed) and (S.Knots[J].Speed>=0),'支持解の値');
        if J>0 then Need((S.Knots[J].Time>S.Knots[J-1].Time) and (S.Knots[J].Distance>=S.Knots[J-1].Distance),'支持解の順序');
      end;
      Need(Abs(S.Knots[High(S.Knots)].Time-(S.Finish-S.Start))<1E-9,'支持解の終端');
      if MelodyHasRail(S.Kind) then begin
        if (I=0) or (Spans[I-1].Motion<>mmRolling) or not MelodyHasRail(Spans[I-1].Kind) then RailStart:=S.Start;
        Need(S.Finish-RailStart<=SectionLength+1.5,'坂道だけの連続は禁止');
        Need(S.Drag<=0.031,'強い不可視抵抗で坂の速度を抑えない');
      end;
    end else if S.Motion=mmFlight then
      Need((Length(S.Knots)=0) and (S.Kind=mcTrapdoor) and Finite(S.Launch.X) and Finite(S.Launch.Y),'自由落下')
    else if S.Motion=mmSpring then begin
      Need((Length(S.Knots)=0) and InRange(S.SpringOmega,1.0,5000.0) and
        Finite(S.Launch.X) and (S.Launch.Y<0),'バネ接触');
      Need(Abs(MelodyCompression(S,S.Finish-S.Start))<1E-7,'バネの解放位置');
    end
    else Need((Length(S.Knots)=0) and (S.Speed=0),'受け止め後の静止');
    for J:=0 to 60 do begin
      P:=MelodySample(S,J/60); V:=MelodySpanVelocity(S,(S.Finish-S.Start)*J/60);
      Need(Finite(P.X) and Finite(P.Y) and Finite(V.X) and Finite(V.Y),'有限の状態');
      Energy:=0.5*(Sqr(V.X)+Sqr(V.Y))+MelodyGravity*P.Y;
      if S.Motion=mmRolling then begin
        MelodyTravel(S,(S.Finish-S.Start)*J/60,D,Speed); Theta:=S.Theta+S.Curvature*D;
        Need(MelodyNormalForce(Theta,Speed,S.Curvature)>=-1E-5,'レールから離床');
        Energy:=Energy+0.5*MelodyInertia*Sqr(Speed);
      end else Energy:=Energy+0.5*MelodyInertia*Sqr(S.Speed);
      if S.Motion=mmSpring then begin
        D:=MelodyCompression(S,(S.Finish-S.Start)*J/60);
        Need(D>=-1E-8,'バネの引張り'); Energy:=Energy+0.5*Sqr(S.SpringOmega*D);
      end;
      Need(Energy<=PreviousEnergy+0.002,'外力のないエネルギー増加'); PreviousEnergy:=Energy;
    end;
    P:=MelodySample(S,1); Need((Abs(P.X-S.B.X)<1E-8) and (Abs(P.Y-S.B.Y)<1E-8),'終点'); T:=S.Finish;
  end;
  Need(T=EndTime,'全曲範囲'); T:=-1;
  for I:=0 to High(Bars) do begin
    Need(Finite(Bars[I].Time) and (Bars[I].Time>=0) and (Bars[I].Time<=Duration) and
      (Bars[I].Time>T) and InRange(Bars[I].Span,0,High(Spans)-1) and (Bars[I].Source>=0),'実音参照');
    S:=Spans[Bars[I].Span]; After:=Spans[Bars[I].Span+1];
    Need((S.Finish=Bars[I].Time) and InRange(Bars[I].Power,0.0,1.0) and
      Finite(Bars[I].Left) and Finite(Bars[I].Right) and Finite(Bars[I].Top) and
      InRange(Bars[I].Right-Bars[I].Left,0.23999999,2.40000001) and
      InRange(Bars[I].Restitution,0.0,0.8200000001),'horizontal plate / flight bounds');
    P:=Position(Bars[I].Time);
    Need((Abs(P.X-Bars[I].Contact.X)<1E-8) and (Abs(P.Y-Bars[I].Contact.Y)<1E-8),'実音時刻の接触');
    if Bars[I].Strike=msHammer then begin
      Need(InRange(Bars[I].MechanismScale,0.32,1.0) and InRange(Bars[I].RotorRatio,0.004,2.0),'機構の寸法と慣性');
      Need(not Bars[I].Terminal and InRange(Bars[I].TriggerSpan,0,Bars[I].Span-1),'ハンマーの作動参照');
      S:=Spans[Bars[I].TriggerSpan]; After:=Spans[Bars[I].TriggerSpan+1];
      Need((S.Motion=mmRolling) and (After.Motion=mmRolling) and
        MelodyHasRail(S.Kind) and MelodyHasRail(After.Kind) and
        (S.Finish=Bars[I].Trigger) and (Bars[I].Trigger<Bars[I].Time),'坂道でのパドル衝突');
      MelodyTravel(S,S.Finish-S.Start,D,Speed); Theta:=S.Theta+S.Curvature*D;
      Need(Abs(Bars[I].AngularSpeed-MelodyHammerSpeed(Speed,Bars[I].MechanismScale,Bars[I].RotorRatio))<1E-8,'ハンマーの角運動量');
      Impulse:=MelodyHammerInertia(Bars[I])*Bars[I].AngularSpeed/(MelodyPaddleArm*Bars[I].MechanismScale);
      Need(Abs(After.Speed-(Speed-Impulse/(1+MelodyInertia)))<1E-8,'球からパドルへの力積');
      Need(Abs((Bars[I].Time-Bars[I].Trigger)*Bars[I].AngularSpeed-MelodyStroke(Bars[I]))<1E-7,'音時刻のハンマー打撃');
      P:=MelodyPoint(S.B.X+S.Direction*(MelodyRadius*Cos(Theta)-MelodyPaddleArm*Bars[I].MechanismScale*Sin(Theta)),
        S.B.Y+MelodyRadius*Sin(Theta)+MelodyPaddleArm*Bars[I].MechanismScale*Cos(Theta));
      Need(MelodyLength(MelodyPoint(P.X-Bars[I].Pivot.X,P.Y-Bars[I].Pivot.Y))<1E-8,'固定支点とパドル接点');
      P:=MelodyHammer(Bars[I],S.Direction,Bars[I].Time);
      Need((P.X>Bars[I].Left+0.04) and (P.X<Bars[I].Right-0.04) and
        (Abs(P.Y+MelodyHammerRadius*Bars[I].MechanismScale-(Bars[I].Top-0.11))<1E-8),'ハンマーと鉄琴下面の実接触');
      Need(P.Y>Bars[I].Contact.Y+MelodyRadius,'球の上にある鉄琴');
      T:=Bars[I].Time; Continue;
    end;
    Need(S.Motion=mmFlight,'転がり通過を音ハメにしない');
    Need((Abs(P.Y-MelodyRadius-Bars[I].Top)<1E-8) and
      (P.X>Bars[I].Left+0.04) and (P.X<Bars[I].Right-0.04),'球の底と板上面');
    Incoming:=MelodySpanVelocity(S,S.Finish-S.Start); Outgoing:=MelodySpanVelocity(After,0);
    Need(Incoming.Y< -1E-6,'上から下降して衝突');
    if Bars[I].Terminal then begin
      Need((Bars[I].Restitution=0) and (After.Motion in [mmRolling,mmRest]) and (Abs(Outgoing.Y)<1E-8),'終端の吸収');
    end else if Bars[I].Strike=msSpring then begin
      Need((After.Motion=mmSpring) and (Abs(Outgoing.X-Incoming.X)<1E-8) and
        (Abs(Outgoing.Y-Bars[I].Restitution*Incoming.Y)<1E-8),'バネへ落下する初速');
      Outgoing:=MelodySpanVelocity(After,After.Finish-After.Start);
      Need((Abs(Outgoing.Y+Bars[I].Restitution*Incoming.Y)<1E-7) and
        (After.B.X>Bars[I].Left+0.02) and (After.B.X<Bars[I].Right-0.02),'板上で圧縮・解放してから発射');
    end else begin
      Need((After.Motion=mmRolling) and (After.Kind=mcArm) and (After.Theta=0) and
        (Abs(Outgoing.Y)<1E-8) and (Bars[I].Restitution=0),'打撃後の水平な転がり');
      Need(Abs(After.B.X-IfThen(After.Direction=1,Bars[I].Right,Bars[I].Left))<1E-8,'板の端から落下');
      Need(Bars[I].Span+2<=High(Spans),'段差の落下参照');
      Need(Spans[Bars[I].Span+2].Motion=mmFlight,'段差の自由落下');
    end;
    T:=Bars[I].Time;
  end;
  // 保存した区間名だけを変えて通過させない。実打撃の種類も一致させる。
  for I:=0 to High(Sections) do begin
    Counts:=0; K:=0;
    for J:=Max(0,BarAt(Sections[I].Start-1E-8)) to BarAt(Sections[I].Finish-1E-8) do begin
      if Bars[J].Time<Sections[I].Start then Continue;
      Inc(Counts);
      case Sections[I].Kind of
        mpSteps:if Bars[J].Strike=msStep then Inc(K);
        mpSeesaw:if Bars[J].Strike=msHammer then Inc(K);
        mpSpring:if (Bars[J].Strike=msSpring) or Bars[J].Terminal then Inc(K);
        mpTurns:Inc(K);
      end;
    end;
    if (Counts>1) and (Sections[I].Finish-Sections[I].Start>2) then Need(K>0,'区間名と実際の機構');
  end;
end;
end.
