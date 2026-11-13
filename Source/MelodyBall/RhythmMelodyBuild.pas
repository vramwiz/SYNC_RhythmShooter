unit RhythmMelodyBuild;
// 拍節に沿って段差・連続てこ・圧縮バネ・左右の受け面を組み、同じ演出を継続しない。
// 音密度から助走と抵抗を設計する。加速は重力のみ。Audioは借用、返したPlanは呼出側所有。
interface
uses System.SysUtils,RhythmAudio,RhythmMelodyPlan;
function BuildMelodyPlan(Audio:TRhythmAudio; const Cancel:TFunc<Boolean> = nil):TMelodyPlan;
implementation
uses System.Math,System.Generics.Collections;
procedure Step(const Span:TMelodySpan; var S,V:Double; H:Double);
var A1,A2,A3,A4,V2,V3,V4:Double;
begin
  A1:=MelodyAcceleration(Span.Theta+Span.Curvature*S,V,Span.Drag);
  V2:=V+A1*H/2; A2:=MelodyAcceleration(Span.Theta+Span.Curvature*(S+V*H/2),V2,Span.Drag);
  V3:=V+A2*H/2; A3:=MelodyAcceleration(Span.Theta+Span.Curvature*(S+V2*H/2),V3,Span.Drag);
  V4:=V+A3*H; A4:=MelodyAcceleration(Span.Theta+Span.Curvature*(S+V3*H),V4,Span.Drag);
  S:=S+H*(V+2*V2+2*V3+V4)/6; V:=V+H*(A1+2*A2+2*A3+A4)/6;
end;
function Integrate(var Span:TMelodySpan; Duration,MaxDistance:Double; const Cancel:TFunc<Boolean>):Boolean;
var Samples:TList<TMelodyKnot>; K:TMelodyKnot; T,S,V,H,SaveAt,NextS,NextV,Lo,Hi,TestS,TestV:Double; I:Integer;
begin
  Result:=False; Samples:=TList<TMelodyKnot>.Create;
  try
    T:=0; S:=0; V:=Span.Speed; K.Time:=0; K.Distance:=0; K.Speed:=V; Samples.Add(K); SaveAt:=1/120;
    while T<Duration-1E-10 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      H:=Min(0.002,Min(Duration-T,SaveAt-T)); NextS:=S; NextV:=V; Step(Span,NextS,NextV,H);
      if (MaxDistance>0) and (NextS>=MaxDistance) then begin
        Lo:=0; Hi:=H;
        for I:=0 to 35 do begin
          TestS:=S; TestV:=V; Step(Span,TestS,TestV,(Lo+Hi)/2);
          if TestS<MaxDistance then Lo:=(Lo+Hi)/2 else Hi:=(Lo+Hi)/2;
        end;
        H:=(Lo+Hi)/2; NextS:=S; NextV:=V; Step(Span,NextS,NextV,H);
      end;
      T:=T+H; S:=NextS; V:=NextV;
      if (V<0) or (V>60) or (MelodyNormalForce(Span.Theta+Span.Curvature*S,V,Span.Curvature)<0.05) then Exit;
      if (T>=SaveAt-1E-9) or (T>=Duration-1E-9) or ((MaxDistance>0) and (Abs(S-MaxDistance)<1E-8)) then begin
        K.Time:=T; K.Distance:=S; K.Speed:=V; Samples.Add(K); SaveAt:=SaveAt+1/120;
      end;
      if (MaxDistance>0) and (Abs(S-MaxDistance)<1E-8) then Break;
    end;
    if (MaxDistance>0) and (Abs(S-MaxDistance)>1E-7) then Exit;
    Span.Finish:=Span.Start+T; Span.Knots:=Samples.ToArray; Span.B:=MelodyTrackPoint(Span,S); Result:=True;
  finally Samples.Free; end;
end;
procedure BuildSections(Plan:TMelodyPlan; Audio:TRhythmAudio; const Cancel:TFunc<Boolean>);
const Order:array[0..7]of TMelodySectionKind=(mpSteps,mpSeesaw,mpSpring,mpTurns,mpSeesaw,mpSteps,mpTurns,mpSpring);
var Sections:TList<TMelodySection>; Section:TMelodySection;
  I,J,N,BPM,Meter,BestMeter,SourceIndex:Integer;
  Mean,Weight,TotalWeight,AllWeight,C,S,Phase,Period,Beat,Amplitude,Timing,Score:Double;
  Best,Runner,BestBeat,BestOrigin,Origin,Distance,Nearest,T,Finish:Double;
begin
  Plan.Beat:=0; Plan.Meter:=0; Plan.BeatOrigin:=0; Plan.BeatConfidence:=0; Plan.SectionLength:=8;
  N:=Min(Length(Audio.Hits),4096); Mean:=0;
  for I:=0 to N-1 do Mean:=Mean+Audio.Hits[I].Strength;
  if N>0 then Mean:=Mean/N;
  TotalWeight:=0; AllWeight:=0;
  for I:=0 to N-1 do begin
    TotalWeight:=TotalWeight+Max(0.0,Audio.Hits[I].Strength-Mean);
    AllWeight:=AllWeight+0.2+Audio.Hits[I].Strength;
  end;
  Best:=0; Runner:=0; BestBeat:=0; BestOrigin:=0; BestMeter:=0;
  // 明瞭なアクセント周期と拍格子が両方合う場合だけ3/4拍子を推定する。密度をBPMと断定しない。
  if (N>=24) and (Audio.Hits[N-1].Time-Audio.Hits[0].Time>=16) and
    (TotalWeight>0.03*N) then for Meter:=3 to 4 do for BPM:=120 to 360 do begin
    if Assigned(Cancel) and Cancel() then Abort;
    Beat:=120/BPM; Period:=Beat*Meter; C:=0; S:=0;
    for I:=0 to N-1 do begin
      Weight:=Max(0.0,Audio.Hits[I].Strength-Mean); Phase:=2*Pi*Audio.Hits[I].Time/Period;
      C:=C+Weight*Cos(Phase); S:=S+Weight*Sin(Phase);
    end;
    Amplitude:=Sqrt(C*C+S*S)/TotalWeight; if Amplitude<0.50 then Continue;
    Origin:=ArcTan2(S,C)*Period/(2*Pi); Origin:=Origin-Floor(Origin/Period)*Period;
    Nearest:=1E20; J:=0;
    for I:=0 to Min(N-1,127) do if Audio.Hits[I].Strength>Mean then begin
      Phase:=(Audio.Hits[I].Time-Origin)/Period;
      Distance:=Abs(Phase-Round(Phase));
      if Distance<Nearest then begin Nearest:=Distance; J:=I; end;
    end;
    Origin:=Audio.Hits[J].Time-Floor(Audio.Hits[J].Time/Period)*Period; Timing:=0;
    for I:=0 to N-1 do begin
      Phase:=(Audio.Hits[I].Time-Origin)/Beat;
      Timing:=Timing+(0.2+Audio.Hits[I].Strength)*Max(0.0,1-Abs(Phase-Round(Phase))/0.12);
    end;
    Score:=Amplitude*(0.30+0.70*Timing/AllWeight);
    if Score>Best then begin
      Runner:=Best; Best:=Score; BestBeat:=Beat; BestOrigin:=Origin; BestMeter:=Meter;
    end else Runner:=Max(Runner,Score);
  end;
  if (Best>=0.62) and (Best-Runner>=0.025) then begin
    Plan.Beat:=BestBeat; Plan.Meter:=BestMeter; Plan.BeatOrigin:=BestOrigin;
    Plan.BeatConfidence:=Min(1.0,Best); Plan.SectionLength:=4*BestMeter*BestBeat;
  end;
  Sections:=TList<TMelodySection>.Create;
  try
    T:=0; Finish:=Plan.SectionLength; SourceIndex:=0;
    if Plan.Meter<>0 then begin
      Origin:=Plan.BeatOrigin;
      if Origin>Plan.Meter*Plan.Beat/2 then Origin:=Origin-Plan.Meter*Plan.Beat;
      Finish:=Finish+Origin;
    end;
    while T<Plan.Duration do begin
      Section:=Default(TMelodySection); Section.Start:=T; Section.Finish:=Min(Plan.Duration,Finish);
      Section.Kind:=Order[Sections.Count mod Length(Order)];
      while (SourceIndex<Length(Audio.Hits)) and (Audio.Hits[SourceIndex].Time<Section.Finish) do begin
        if Audio.Hits[SourceIndex].Time>=T then Inc(Section.SourceCount); Inc(SourceIndex);
      end;
      Sections.Add(Section); T:=Section.Finish; Finish:=T+Plan.SectionLength;
    end;
    Plan.Sections:=Sections.ToArray;
  finally Sections.Free; end;
end;
function BuildMelodyPlan(Audio:TRhythmAudio; const Cancel:TFunc<Boolean>):TMelodyPlan;
var Pieces:TList<TMelodySpan>; Bars:TList<TMelodyBar>; Selected:TList<Integer>;
  I,J,K,L,N,Direction,Transfers,CurrentSection,PreviousSection:Integer;
  Time,Theta,Omega,Spin,RampEnd,Gap,MinGap,LastCue,D,UntilTime,Width:Double;
  ContactTime,LoadSpeed,LastRequired,Required,Reserve,Typical,Temp,RailSince:Double;
  Tempo:TArray<Double>; Window:array[0..8]of Double;
  Plan:TMelodyPlan;
  P,Velocity:TMelodyPoint; S:TMelodySpan; B:TMelodyBar;
  OnRail,Finished,ShortSong,NewSection:Boolean; Section:TMelodySection;
  procedure CheckCancel;
  begin if Assigned(Cancel) and Cancel() then Abort; end;
  function TempoGap(T:Double):Double;
  var Lo,Hi,Mid:Integer;
  begin
    if Length(Tempo)=0 then Exit(1);
    Lo:=0; Hi:=High(Tempo);
    while Lo<Hi do begin Mid:=(Lo+Hi) div 2; if Audio.Hits[Mid].Time<T then Lo:=Mid+1 else Hi:=Mid; end;
    Result:=Tempo[Lo];
  end;
  function RailDrag:Double;
  begin
    // 強い抵抗で急坂の速度を抑えない。遅い球に合わせるのは下のRailAngleで傾斜を変える。
    Result:=0.025;
  end;
  function TargetSpeed(T:Double):Double;
  begin Result:=EnsureRange(0.72/Min(TempoGap(T),TempoGap(T+2.6)),4.5,21.0); end;
  function RailAngle(T:Double):Double;
  var Loss,Acceleration,Force:Double;
  begin
    Loss:=0;
    if (Plan.Sections[Plan.SectionAt(T)].Kind=mpSeesaw) and (TempoGap(T)<0.44) then
      Loss:=-Ln(1-(1+MelodyPaddleRestitution)*0.004/(1+MelodyInertia+0.004))/TempoGap(T);
    Acceleration:=EnsureRange((TargetSpeed(T)-Omega)/1.2,-0.8,4.0);
    Force:=(1+MelodyInertia)*(Acceleration+(0.025+Loss)*Omega)/MelodyGravity;
    Result:=-ArcSin(EnsureRange(Force,-Sin(0.12),Sin(0.80)));
  end;
  procedure CommitRoll;
  begin
    if MelodyHasRail(S.Kind) and ((Pieces.Count=0) or (Pieces[Pieces.Count-1].Motion<>mmRolling) or
      not MelodyHasRail(Pieces[Pieces.Count-1].Kind)) then RailSince:=S.Start;
    Pieces.Add(S); P:=S.B; Time:=S.Finish;
    MelodyTravel(S,S.Finish-S.Start,D,Omega); Velocity:=MelodySpanVelocity(S,S.Finish-S.Start);
    Spin:=S.Spin+Direction*D/MelodyRadius;
    Theta:=ArcTan2(Sin(S.Theta+S.Curvature*D),Cos(S.Theta+S.Curvature*D)); OnRail:=True;
  end;
  procedure FlyUntil(Finish:Double); forward;
  procedure Capture(Angle:Double; NewDirection:Integer); forward;
  procedure RollUntil(Finish:Double; Straight:Boolean=False; FixedDrag:Double=-1);
  var Limit,Target,K,Safe,Angle:Double;
  begin
    while Time<Finish-1E-9 do begin
      if not Straight and (Time-RailSince>=Result.SectionLength+0.25) and (Finish-Time>0.80) then begin
        // 音の少ない区間でも同じ坂を延々と延ばさない。実際に端を離れ、下の受け面へ落とす。
        FlyUntil(Time+0.35);
        Angle:=EnsureRange(ArcTan2(Velocity.Y,Abs(Velocity.X))+0.08,-1.02,-0.02);
        Capture(Angle,Direction); Continue;
      end;
      CheckCancel; Limit:=Min(Finish,Time+0.75); S:=Default(TMelodySpan);
      if not Straight and (Time<RailSince+Result.SectionLength+0.25) then
        Limit:=Min(Limit,RailSince+Result.SectionLength+0.25);
      S.Start:=Time; S.A:=P; S.Theta:=Theta; S.Speed:=Omega; S.Spin:=Spin; S.Direction:=Direction;
      S.Motion:=mmRolling; S.Kind:=mcCurve; S.Drag:=RailDrag;
      if FixedDrag>=0 then S.Drag:=FixedDrag;
      if Straight then begin S.Curvature:=0; S.Kind:=mcSlope; end
      else begin
        Target:=RailAngle(Time);
        K:=(Target-Theta)/(Max(1.0,Omega)*0.7);
        Safe:=0.6*MelodyGravity*Max(0.15,Cos(Theta))/Max(1.0,Sqr(Omega));
        S.Curvature:=EnsureRange(K,-Safe,0.25);
      end;
      if not Integrate(S,Limit-Time,0,Cancel) then begin
        S.Curvature:=0; S.Kind:=mcSlope; S.Knots:=nil;
        if not Integrate(S,Limit-Time,0,Cancel) then raise EConvertError.Create('搬送レールの支持が成立しません');
      end;
      S.Finish:=Limit; S.Knots[High(S.Knots)].Time:=Limit-S.Start; CommitRoll;
    end;
  end;
  procedure FlyUntil(Finish:Double);
  begin
    if Finish<=Time+1E-10 then Exit;
    S:=Default(TMelodySpan); S.Start:=Time; S.Finish:=Finish; S.A:=P; S.Launch:=Velocity;
    S.Speed:=Omega; S.Spin:=Spin; S.Direction:=Direction; S.Motion:=mmFlight; S.Kind:=mcTrapdoor;
    S.B:=MelodySample(S,1); Pieces.Add(S); P:=S.B; Velocity:=MelodySpanVelocity(S,Finish-Time);
    Spin:=Spin+Direction*Omega*(Finish-Time)/MelodyRadius; Time:=Finish; OnRail:=False;
  end;
  procedure SpringContact(Duration,Load:Double);
  var Lo,Hi,W,Period:Double; K:Integer;
  begin
    // 下降時に受けたエネルギーだけを蓄え、圧縮を経てから解放する受動バネ。
    Lo:=1; Hi:=5000;
    for K:=0 to 48 do begin
      W:=(Lo+Hi)/2; Period:=2*(Pi-ArcTan(Load*W/MelodyGravity))/W;
      if Period>Duration then Lo:=W else Hi:=W;
    end;
    S:=Default(TMelodySpan); S.Start:=Time; S.Finish:=Time+Duration;
    S.A:=P; S.Launch:=MelodyPoint(Velocity.X,-Load); S.SpringOmega:=(Lo+Hi)/2;
    S.Speed:=Omega; S.Spin:=Spin; S.Direction:=Direction; S.Motion:=mmSpring; S.Kind:=mcHop;
    S.B:=MelodySample(S,1); Pieces.Add(S); P:=S.B; Velocity:=MelodySpanVelocity(S,Duration);
    Spin:=Spin+Direction*Omega*Duration/MelodyRadius; Time:=S.Finish; OnRail:=False;
  end;
  procedure Capture(Angle:Double; NewDirection:Integer);
  var Tangent,Normal:Double;
  begin
    Normal:=-NewDirection*Velocity.X*Sin(Angle)+Velocity.Y*Cos(Angle);
    if Normal>1E-7 then raise EConvertError.Create('受けレールへ上から接触していません');
    Tangent:=NewDirection*Velocity.X*Cos(Angle)+Velocity.Y*Sin(Angle);
    Omega:=(Tangent+MelodyInertia*NewDirection*Direction*Omega)/(1+MelodyInertia);
    if Omega<0 then raise EConvertError.Create('受けレールの接線速度が負です');
    Direction:=NewDirection; Theta:=Angle;
    Velocity:=MelodyPoint(Direction*Omega*Cos(Angle),Omega*Sin(Angle)); OnRail:=True; RailSince:=Time;
  end;
  procedure Transport(Cue:Double; ForceReverse:Boolean=False);
  var FlightTime,ReverseTime,Down,Angle:Double; NewDirection:Integer;
  begin
    if OnRail or (Cue-Time<=1.4) then Exit;
    // 左右の反転は空中で行わない。深く落ち、反対へ傾く木の受け面に衝突して向きを変える。
    Inc(Transfers); NewDirection:=Direction;
    Angle:=-0.55; Down:=Abs(Velocity.X)*Tan(-Angle)+0.60;
    FlightTime:=Max(0.20,(Velocity.Y+Down)/MelodyGravity);
    if Odd(Transfers) or ForceReverse then begin
      Down:=(Abs(Velocity.X)*Cos(-1.02)+MelodyInertia*Omega+2.8)/(-Sin(-1.02));
      ReverseTime:=Max(0.25,(Velocity.Y+Down)/MelodyGravity);
      if ReverseTime+0.55<=Cue-Time then begin
        NewDirection:=-Direction; Angle:=-1.02; FlightTime:=ReverseTime;
      end;
    end;
    if FlightTime+0.32>Cue-Time then Exit;
    FlyUntil(Time+FlightTime); Capture(Angle,NewDirection);
  end;
  procedure ApproachCue(Cue:Double);
  begin
    Transport(Cue);
    if OnRail and (Cue-Time>0.30) then RollUntil(Cue-0.26);
    FlyUntil(Cue);
  end;
  procedure CatchRolling(Cue:Double);
  var FallTime,Angle:Double;
  begin
    Transport(Cue); if OnRail then Exit;
    FallTime:=Max(0.08,Velocity.Y/MelodyGravity+0.12);
    if FallTime+0.035>=Cue-Time then Exit;
    FlyUntil(Time+FallTime);
    Angle:=EnsureRange(ArcTan2(Velocity.Y,Abs(Velocity.X))+0.08,-1.02,-0.02);
    if -Direction*Velocity.X*Sin(Angle)+Velocity.Y*Cos(Angle)>0 then Exit;
    Capture(Angle,Direction);
  end;
  function HammerCue(Cue:Double; Scale:Double=1; Ratio:Double=2):Boolean;
  var Total,Lo,Hi,Mid,V,Impulse,Angle,Drag,Gravity,Budget,Stroke,Head:Double; K:Integer;
    function StrokeAt(T:Double):Double;
    begin
      // 一定の傾斜・線形抵抗の解。探索のたびに積分列を割り当てず、確定後だけ保存する。
      V:=Omega*Exp(-Drag*T)+Gravity/Drag*(1-Exp(-Drag*T));
      Result:=(Total-T)*MelodyHammerSpeed(V,Scale,Ratio);
    end;
  begin
    Result:=False;
    if not OnRail or (Cue-Time<0.003) then Exit;
    Stroke:=MelodyHammerStroke; Head:=Stroke;
    if Scale<1 then begin Stroke:=1.65; Head:=Stroke-0.35; end;
    if Scale<1 then begin
      Budget:=Max(0.012,1.4*Stroke/MelodyHammerSpeed(Max(1.0,Omega),Scale,Ratio));
      if Cue-Time>Budget+0.005 then RollUntil(Cue-Budget);
    end else if Cue-Time>1.2 then RollUntil(Cue-1.2);
    Total:=Cue-Time; Lo:=-1; Hi:=Total; Drag:=RailDrag;
    Gravity:=-MelodyGravity*Sin(Theta)/(1+MelodyInertia);
    for K:=0 to 24 do begin
      Mid:=Total*K/24;
      if StrokeAt(Mid)>=Stroke then Lo:=Mid;
    end;
    if Lo<0 then Exit;
    for K:=0 to 40 do begin
      Mid:=(Lo+Hi)/2;
      if StrokeAt(Mid)>Stroke then Lo:=Mid else Hi:=Mid;
    end;
    RollUntil(Time+(Lo+Hi)/2,True,Drag);
    B.Strike:=msHammer; B.Trigger:=Time; B.TriggerSpan:=Pieces.Count-1;
    B.MechanismScale:=Scale; B.RotorRatio:=Ratio;
    B.AngularSpeed:=MelodyHammerSpeed(Omega,Scale,Ratio); Angle:=Theta;
    B.Pivot:=MelodyPoint(P.X+Direction*(MelodyRadius*Cos(Angle)-MelodyPaddleArm*Scale*Sin(Angle)),
      P.Y+MelodyRadius*Sin(Angle)+MelodyPaddleArm*Scale*Cos(Angle));
    // 有効質量1.4の球から釣り合いローターへ力積を渡す。外部から加速しない。
    Impulse:=MelodyHammerInertia(B)*B.AngularSpeed/(MelodyPaddleArm*Scale);
    Omega:=Omega-Impulse/(1+MelodyInertia);
    Velocity:=MelodyPoint(Direction*Omega*Cos(Theta),Omega*Sin(Theta));
    // 衝突後は球とローターが離れている。球の支持レールは曲げられ、角速度/打撃時刻は保たれる。
    RollUntil(Cue,False,Drag); B.Time:=Time; B.Span:=Pieces.Count-1; B.Contact:=P;
    B.Top:=B.Pivot.Y+Scale*(MelodyHammerArm*Sin(Head)+MelodyHammerRadius)+0.11;
    D:=B.Pivot.X+Direction*Scale*MelodyHammerArm*Cos(Head);
    B.Left:=D-0.50*Scale; B.Right:=D+0.50*Scale; B.Kind:=mbPower;
    if Scale<1 then B.Kind:=mbRapid;
    Result:=True;
  end;
  procedure RestUntil(Finish:Double);
  begin
    S:=Default(TMelodySpan); S.Start:=Time; S.Finish:=Finish; S.A:=P; S.B:=P;
    S.Spin:=Spin; S.Direction:=Direction; S.Motion:=mmRest; S.Kind:=mcSlope; Pieces.Add(S);
    Time:=Finish; Velocity:=MelodyPoint(0,0); Omega:=0;
  end;
  procedure FinishOnTray;
  begin
    Capture(0,Direction);
    if Omega>0.01 then begin
      S:=Default(TMelodySpan); S.Start:=Time; S.A:=P; S.Theta:=0; S.Speed:=Omega;
      S.Spin:=Spin; S.Direction:=Direction; S.Drag:=0.35; S.Motion:=mmRolling; S.Kind:=mcArm;
      if not Integrate(S,Min(1.0,Result.EndTime-Time),0.45,Cancel) then
        raise EConvertError.Create('終端の受け止め位置へ到達できません');
      CommitRoll;
    end;
    RestUntil(Result.EndTime); Finished:=True;
  end;
  procedure StepContact(Duration:Double);
  begin
    Capture(0,Direction);
    Duration:=Min(Duration,2.15/Max(0.01,Omega));
    S:=Default(TMelodySpan); S.Start:=Time; S.A:=P; S.Theta:=0; S.Speed:=Omega;
    S.Spin:=Spin; S.Direction:=Direction; S.Drag:=0.01; S.Motion:=mmRolling; S.Kind:=mcArm;
    if not Integrate(S,Duration,0,Cancel) then raise EConvertError.Create('打撃後の水平移動が成立しません');
    CommitRoll; OnRail:=False;
    if Direction=1 then begin B.Left:=B.Contact.X-0.20; B.Right:=P.X; end
    else begin B.Left:=P.X; B.Right:=B.Contact.X+0.20; end;
  end;
begin
  if (Audio=nil) or not Audio.HasHitDetails then raise EArgumentException.Create('解析済みの音声が必要です');
  if IsNan(Audio.Duration) or IsInfinite(Audio.Duration) or not InRange(Audio.Duration,0.001,3044.0) then
    raise EConvertError.Create('音声長が不正です');
  Pieces:=TList<TMelodySpan>.Create; Bars:=TList<TMelodyBar>.Create; Selected:=TList<Integer>.Create; Result:=nil;
  try
    try
      for I:=0 to High(Audio.Hits) do begin
        CheckCancel; UntilTime:=Audio.Hits[I].Time;
        if IsNan(UntilTime) or IsInfinite(UntilTime) or not InRange(UntilTime,0.0,Audio.Duration) or
          IsNan(Audio.Hits[I].Strength) or not InRange(Audio.Hits[I].Strength,0.0,1.0) then
          raise EConvertError.Create('音ハメ候補が不正です');
        if (I>0) and (UntilTime<Audio.Hits[I-1].Time) then raise EConvertError.Create('音ハメ時刻の順序が不正です');
      end;
      // 局所9間隔の中央値。先読みは坂と抵抗の設計にだけ使い、速度を直接書き換えない。
      SetLength(Tempo,Length(Audio.Hits));
      for I:=0 to High(Tempo) do begin
        N:=0;
        for K:=Max(0,I-3) to Min(High(Audio.Hits)-1,I+5) do begin
          Temp:=EnsureRange(Audio.Hits[K+1].Time-Audio.Hits[K].Time,0.035,4.0);
          L:=N; while (L>0) and (Window[L-1]>Temp) do begin Window[L]:=Window[L-1]; Dec(L); end;
          Window[L]:=Temp; Inc(N);
        end;
        if N=0 then Tempo[I]:=1 else Tempo[I]:=Window[N div 2];
      end;
      Result:=TMelodyPlan.Create; Plan:=Result; Result.Duration:=Audio.Duration; Result.EndTime:=Audio.Duration+1.2;
      BuildSections(Result,Audio,Cancel);
      Time:=0; P:=MelodyPoint(0,5); Velocity:=MelodyPoint(0,0); Omega:=0; Spin:=0; Direction:=1; Transfers:=0;
      Theta:=-0.62; OnRail:=True; Finished:=False; ShortSong:=Audio.Duration<1.4;
      RailSince:=0; PreviousSection:=-1;
      if ShortSong then begin
        OnRail:=False;
        for I:=0 to High(Audio.Hits) do if Audio.Hits[I].Time>=0.06 then begin Selected.Add(I); Break; end;
      end else begin
        Typical:=TargetSpeed(0); RampEnd:=Min(5.5,Max(0.75,Typical/4.0));
        RampEnd:=Min(RampEnd,Audio.Duration*0.55);
        Theta:=-ArcSin(EnsureRange((1+MelodyInertia)*(Typical/RampEnd+0.025*Typical/2)/MelodyGravity,0.05,0.85));
        RollUntil(RampEnd,True);
        LastCue:=-1; LastRequired:=0;
        for I:=0 to High(Audio.Hits) do begin
          UntilTime:=Audio.Hits[I].Time; Section:=Result.Sections[Result.SectionAt(UntilTime)];
          case Section.Kind of
            mpSteps:Required:=0.32;
            mpSeesaw:Required:=0.035;
            mpSpring:Required:=0.50;
            else Required:=0.44;
          end;
          if Section.Kind=mpTurns then begin
            Reserve:=Min(Max(0.0,Section.Finish-Section.Start-0.55),2.0+0.1*TargetSpeed(UntilTime));
            if UntilTime<Section.Start+Reserve then Continue;
          end;
          MinGap:=Max(Required,LastRequired);
          if (UntilTime>=RampEnd+0.10) and (UntilTime-LastCue>=MinGap-1E-9) then begin
            Selected.Add(I); LastCue:=UntilTime; LastRequired:=Required;
          end;
        end;
      end;
      for J:=0 to Selected.Count-1 do begin
        CheckCancel; I:=Selected[J]; B:=Default(TMelodyBar);
        B.Source:=I; B.Power:=Audio.Hits[I].Strength; B.Terminal:=J=Selected.Count-1;
        CurrentSection:=Result.SectionAt(Audio.Hits[I].Time); Section:=Result.Sections[CurrentSection];
        NewSection:=CurrentSection<>PreviousSection; PreviousSection:=CurrentSection;
        if (Section.Kind=mpSeesaw) and not ShortSong then begin
          CatchRolling(Audio.Hits[I].Time); B.Terminal:=False;
          if HammerCue(Audio.Hits[I].Time,0.32,0.004) then begin Bars.Add(B); Continue; end;
          // 助走中など、まだ打撃ストロークを取れない音は球を飛ばさず搬送を続ける。
          if OnRail then RollUntil(Audio.Hits[I].Time) else FlyUntil(Audio.Hits[I].Time);
          Continue;
        end;
        if (Section.Kind=mpTurns) and NewSection then begin
          Transport(Audio.Hits[I].Time,True);
          if not B.Terminal and OnRail and HammerCue(Audio.Hits[I].Time,1.0,0.04) then begin Bars.Add(B); Continue; end;
        end;
        ApproachCue(Audio.Hits[I].Time);
        if Velocity.Y>=-1E-6 then raise EConvertError.Create('水平板の上面へ下降していません');
        B.Time:=Time; B.Contact:=P; B.Top:=P.Y-MelodyRadius; B.Span:=Pieces.Count-1; B.Kind:=mbNormal;
        if B.Terminal then begin
          B.Left:=P.X-0.55; B.Right:=P.X+0.55;
          if Direction=1 then B.Right:=P.X+0.85 else B.Left:=P.X-0.85;
          Bars.Add(B); FinishOnTray; Break;
        end;
        Gap:=Audio.Hits[Selected[J+1]].Time-Time;
        if Section.Kind=mpSpring then begin
          B.Strike:=msSpring; B.Kind:=mbSpring;
          ContactTime:=Min(0.20,1.5/Max(1.0,Abs(Velocity.X)));
          LoadSpeed:=Min(0.65*(-Velocity.Y),0.25*MelodyGravity*Min(Gap-ContactTime,0.70));
          Width:=Min(2.4,Max(0.60,Abs(Velocity.X)*(ContactTime+0.06)+0.30));
          if Direction=1 then begin B.Left:=P.X-0.20; B.Right:=B.Left+Width; end
          else begin B.Right:=P.X+0.20; B.Left:=B.Right-Width; end;
          B.Restitution:=LoadSpeed/(-Velocity.Y); Bars.Add(B); SpringContact(ContactTime,LoadSpeed);
        end else begin
          B.Strike:=msStep;
          ContactTime:=Min(Gap-0.28,Min(0.24,1.6/Max(2.0,Abs(Velocity.X))));
          StepContact(ContactTime); Bars.Add(B);
        end;
      end;
      if not Finished then begin
        if (Pieces.Count=0) and (Selected.Count=0) then RestUntil(Result.EndTime)
        else begin FlyUntil(Time+Max(0.25,Velocity.Y/MelodyGravity+0.18)); FinishOnTray; end;
      end;
      Result.Spans:=Pieces.ToArray; Result.Bars:=Bars.ToArray;
      Result.IndexGeometry(Cancel); Result.Validate;
    except Result.Free; raise; end;
  finally Selected.Free; Bars.Free; Pieces.Free; end;
end;
end.
