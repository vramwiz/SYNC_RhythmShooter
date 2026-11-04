unit RhythmOrbitPlan;
// 音時刻を動かさず、惑星の周回と接続飛行・採用音・連続カメラを事前に確定する。
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmOrbitTypes;
type
  TOrbitPlan=class
  private
    FData:TOrbitData;
    procedure Validate;
    function GetCount:Integer;
    function GetBodyCount:Integer;
    function GetLegCount:Integer;
    function GetTap(Index:Integer):TOrbitTap;
    function GetBody(Index:Integer):TOrbitBody;
    function GetLeg(Index:Integer):TOrbitLeg;
    function GetExcluded:Integer;
    function GetEndTime:Double;
    function GetSoundEnd:Double;
    function GetThreshold:Integer;
    function GetVersion:Integer;
    function GetStage(Index:Integer):Double;
  public
    class function Build(Audio:TRhythmAudio;Threshold:Integer;const Cancel:TFunc<Boolean> = nil):TOrbitPlan;static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TOrbitPlan;static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;static;
    function Before(Time:Double;IncludeTime:Boolean=True):Integer;
    function IsRoll(Index:Integer):Boolean;
    function LegAt(Time:Double):Integer;
    function PointAt(Leg:Integer;Time:Double):TOrbitPoint;
    function CursorAt(Time:Double):TOrbitPoint;
    function CameraAt(Time,Aspect:Double):TOrbitCamera;
    property Count:Integer read GetCount;
    property BodyCount:Integer read GetBodyCount;
    property LegCount:Integer read GetLegCount;
    property Taps[Index:Integer]:TOrbitTap read GetTap;
    property Bodies[Index:Integer]:TOrbitBody read GetBody;
    property Legs[Index:Integer]:TOrbitLeg read GetLeg;
    property Excluded:Integer read GetExcluded;
    property EndTime:Double read GetEndTime;
    property SoundEnd:Double read GetSoundEnd;
    property Threshold:Integer read GetThreshold;
    property Version:Integer read GetVersion;
    // 0=導入完了、1=離脱開始、2=到着、3=クリア開始。全て曲の絶対秒。
    property Stages[Index:Integer]:Double read GetStage;
  end;
function OrbitProject(const P:TOrbitPoint;const Camera:TOrbitCamera;Aspect:Double):TOrbitPoint;
implementation
uses System.Math,System.Generics.Collections,RhythmOrbitCodec,RhythmOrbitAudio,RhythmStyles;

function TOrbitPlan.IsRoll(Index:Integer):Boolean;
var L,R:Integer;
begin
  if (Version<4) or (Threshold>RHYTHM_ROLL_SENSITIVITY) or (Index<0) or (Index>=Count) then Exit(False);
  L:=Index;R:=Index;
  while (L>0) and (Index-L<2) and RollPair(FData.Taps[L-1].Time,FData.Taps[L].Time) do Dec(L);
  while (R+1<Count) and (R-L<2) and RollPair(FData.Taps[R].Time,FData.Taps[R+1].Time) do Inc(R);
  Result:=R-L>=2;
end;
function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);Result:=U*U*(3-2*U);end;
function OrbitProject(const P:TOrbitPoint;const Camera:TOrbitCamera;Aspect:Double):TOrbitPoint;
begin Result:=OrbitPoint(0.5+(P.X-Camera.Center.X)/(Camera.Span*Aspect),0.5+(P.Y-Camera.Center.Y)/Camera.Span);end;
function TOrbitPlan.GetCount:Integer;
begin Result:=Length(FData.Taps);end;
function TOrbitPlan.GetBodyCount:Integer;
begin Result:=Length(FData.Bodies);end;
function TOrbitPlan.GetLegCount:Integer;
begin Result:=Length(FData.Legs);end;
function TOrbitPlan.GetTap(Index:Integer):TOrbitTap;
begin Result:=FData.Taps[Index];end;
function TOrbitPlan.GetBody(Index:Integer):TOrbitBody;
begin Result:=FData.Bodies[Index];end;
function TOrbitPlan.GetLeg(Index:Integer):TOrbitLeg;
begin Result:=FData.Legs[Index];end;
function TOrbitPlan.GetExcluded:Integer;
begin Result:=FData.Weak+FData.Tail;end;
function TOrbitPlan.GetEndTime:Double;
begin Result:=FData.EndTime;end;
function TOrbitPlan.GetSoundEnd:Double;
begin Result:=FData.SoundEnd;end;
function TOrbitPlan.GetThreshold:Integer;
begin Result:=FData.Threshold;end;
function TOrbitPlan.GetVersion:Integer;
begin Result:=FData.Version;end;
function TOrbitPlan.GetStage(Index:Integer):Double;
begin case Index of 0:Result:=FData.IntroFinish;1:Result:=FData.DepartStart;2:Result:=FData.DepartFinish;else Result:=FData.ClearTime;end;end;
function TOrbitPlan.Before(Time:Double;IncludeTime:Boolean):Integer;
var L,R,M:Integer;
begin L:=0;R:=Count;while L<R do begin M:=L+(R-L) div 2;
    if (FData.Taps[M].Time<Time) or (IncludeTime and (FData.Taps[M].Time=Time)) then L:=M+1 else R:=M;end;Result:=L-1;
end;
function TOrbitPlan.LegAt(Time:Double):Integer;
var L,R,M:Integer;
begin
  if LegCount=0 then Exit(-1);
  L:=0;R:=LegCount-1;
  while L<R do begin M:=L+(R-L) div 2;if FData.Legs[M].Finish<Time then L:=M+1 else R:=M;end;
  Result:=L;
end;
function TOrbitPlan.PointAt(Leg:Integer;Time:Double):TOrbitPoint;
begin Result:=OrbitLegAt(FData,Leg,Time);end;
function TOrbitPlan.CursorAt(Time:Double):TOrbitPoint;
var I:Integer;
begin I:=LegAt(Time);if I<0 then Exit(OrbitPoint(0,0));Result:=PointAt(I,Time);end;

function TOrbitPlan.CameraAt(Time,Aspect:Double):TOrbitCamera;
var I:Integer;L:TOrbitLeg;A,B:TOrbitBody;U,V,Wave,Base,Other,Wide,Need:Double;P:TOrbitPoint;
  function FullSpan(const Body:TOrbitBody):Double;
  begin Result:=Max(3.7,Max((2*Max(Body.RX,Body.RY)+0.9)/Aspect,2*Max(Body.RX,Body.RY)+0.9));end;
begin
  Aspect:=EnsureRange(Aspect,0.2,5.0);I:=LegAt(Time);
  if I<0 then begin Result.Center:=OrbitPoint(0,0);Result.Span:=8;Exit;end;
  L:=FData.Legs[I];A:=FData.Bodies[L.FromBody];B:=FData.Bodies[L.ToBody];
  U:=EnsureRange((Time-L.Start)/(L.Finish-L.Start),0.0,1.0);Wave:=Sqr(Sin(Pi*U));Base:=FullSpan(A);
  if L.Kind=2 then begin
    V:=Smooth(U);Result.Center:=OrbitPoint(A.Center.X+(L.A.X-A.Center.X)*0.32*(1-V),A.Center.Y+(L.A.Y-A.Center.Y)*0.32*(1-V));
    Result.Span:=14+(Base-14)*V;
  end else if L.Kind in [3,4] then begin
    if L.Kind=4 then begin L:=FData.Legs[I-1];U:=1;end;
    V:=Smooth(U);Result.Center:=OrbitPoint(A.Center.X+(L.D.X-L.A.X)*0.24*V,A.Center.Y+(L.D.Y-L.A.Y)*0.24*V);
    Result.Span:=Base+(14-Base)*V;
  end else if L.Kind=0 then begin
    P:=CursorAt(Time);Result.Center:=OrbitPoint(A.Center.X+(P.X-A.Center.X)*0.12*Wave,A.Center.Y+(P.Y-A.Center.Y)*0.12*Wave);
    Result.Span:=Base*(1-0.24*Wave);
  end else begin
    V:=Smooth(U);Other:=FullSpan(B);
    Result.Center:=OrbitPoint(A.Center.X+(B.Center.X-A.Center.X)*V,A.Center.Y+(B.Center.Y-A.Center.Y)*V);
    Wide:=Max(Abs(A.Center.Y-B.Center.Y)+A.RX+B.RX+1.3,(Abs(A.Center.X-B.Center.X)+A.RX+B.RX+1.3)/Aspect);
    Result.Span:=Base+(Other-Base)*V+Wave*Max(0.0,Wide-Max(Base,Other));
  end;
  // カメラ補正は絶対時刻の連続関数。飛行中も船を画面外へ捨てず、視野だけを広げる。
  P:=CursorAt(Time);Need:=Max(2*Abs(P.Y-Result.Center.Y)+1.0,(2*Abs(P.X-Result.Center.X)+1.0)/Aspect);
  Result.Span:=Max(Result.Span,Need);
  if FData.Version>=3 then begin
    // Fast entry/exit also reserve space for the next 300ms, before its beat is due.
    P:=CursorAt(Time);Need:=Max(2.4*Abs(P.Y-Result.Center.Y)+1.0,(2.4*Abs(P.X-Result.Center.X)+1.0)/Aspect);
    Result.Span:=Max(Result.Span,Need);
    P:=CursorAt(Time+0.30);Need:=Max(2.4*Abs(P.Y-Result.Center.Y)+1.0,(2.4*Abs(P.X-Result.Center.X)+1.0)/Aspect);
    Result.Span:=Max(Result.Span,Need);
  end;
end;

class function TOrbitPlan.Build(Audio:TRhythmAudio;Threshold:Integer;const Cancel:TFunc<Boolean>):TOrbitPlan;
var Times:TList<Double>;Bodies:TList<TOrbitBody>;Legs:TList<TOrbitLeg>;Taps:TList<TOrbitTap>;
  Body,Next:TOrbitBody;L,Flight,Intro,Departure,Hold:TOrbitLeg;Tap:TOrbitTap;I,J,Index,Chain:Integer;
  T,EndOrbit,EndFlight,Last,Angle,DX,DY,Distance,Duration,Story,IntroStart,ClearHold:Double;P,V,W,Direction:TOrbitPoint;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;end;
  function Near(Target:Double):Double;
  var A,B,M,K:Integer;Best:Double;
  begin Result:=Target;Best:=0.28;A:=0;B:=Times.Count;
    while A<B do begin M:=A+(B-A) div 2;if Times[M]<Target then A:=M+1 else B:=M;end;
    for K:=Max(0,A-1) to Min(Times.Count-1,A+1) do if Abs(Times[K]-Target)<Best then begin Best:=Abs(Times[K]-Target);Result:=Times[K];end;
  end;
  function MakeBody(N:Integer;const Center:TOrbitPoint;Entry:Double):TOrbitBody;
  begin Result:=Default(TOrbitBody);Result.Center:=Center;Result.Entry:=Entry;
    Result.Show:=Entry-3;Result.Clear:=Audio.SoundEnd+ORBIT_EFFECT_LIFE;
    Result.Radius:=0.28+0.10*(0.5+0.5*Sin(N*2.31));Result.RX:=1.15+0.32*(0.5+0.5*Cos(N*1.37));
    Result.RY:=Result.RX*(0.62+0.16*(0.5+0.5*Sin(N*0.91)));Result.Rotation:=Sin(N*1.7)*0.48;
    Result.Speed:=1.1+0.24*Sin(N*1.23);Result.Phase:=0.6;Result.Hue:=(N*3) mod 8;
  end;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if not OrbitFinite(Audio.Duration) or not OrbitFinite(Audio.SoundEnd) or (Audio.Duration<=0) or
  (Audio.Duration>3043.5) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or
  (Length(Audio.Hits)>ORBIT_MAX_EVENTS) or (Threshold< -100) or (Threshold>100) then raise Exception.Create('Orbit input bounds');
  Check;Result:=TOrbitPlan.Create;Times:=nil;Bodies:=nil;Legs:=nil;Taps:=nil;
  try
    try
      Result.FData.Version:=StylePlanVersion(rsRhythmGame);Result.FData.Duration:=Audio.Duration;Result.FData.SoundEnd:=Audio.SoundEnd;
      Result.FData.EndTime:=Audio.Duration;Result.FData.Threshold:=Threshold;
      Result.FData.Events:=Copy(Audio.Hits);Times:=TList<Double>.Create;Last:=-1;
      for I:=0 to High(Audio.Hits) do begin Check;T:=Audio.Hits[I].Time;
        if not OrbitFinite(T) or not OrbitFinite(Audio.Hits[I].Strength) or (T<Last) or (T<0) or (T>Audio.Duration+0.011) then raise Exception.Create('Orbit accent order');Last:=T;
        if (Audio.SoundEnd<=0) or (T>Audio.SoundEnd) then Inc(Result.FData.Tail)
        else if Audio.Hits[I].Strength<Threshold/100 then Inc(Result.FData.Weak) else Times.Add(T);
      end;
      Bodies:=TList<TOrbitBody>.Create;Legs:=TList<TOrbitLeg>.Create;Taps:=TList<TOrbitTap>.Create;
      if Times.Count>0 then begin
        Story:=Audio.SoundEnd;
        Result.FData.IntroFinish:=Min(Max(1.5,Times[0]),Story*0.28);IntroStart:=-Min(0.55,Story*0.10);
        ClearHold:=Min(0.32,Story*0.10);Result.FData.DepartFinish:=Story-ClearHold;
        Result.FData.DepartStart:=Result.FData.DepartFinish-Min(2.4,Story*0.34);
        Result.FData.ClearTime:=Result.FData.DepartFinish;
        T:=Result.FData.IntroFinish;Body:=MakeBody(0,OrbitPoint(0,0),T);Body.Show:=IntroStart-0.8;Bodies.Add(Body);Index:=0;
        Intro:=Default(TOrbitLeg);Intro.Kind:=2;Intro.Start:=IntroStart;Intro.Finish:=T;Intro.FromBody:=0;Intro.ToBody:=0;
        Intro.D:=OrbitBodyAt(Body,Body.Phase);V:=OrbitTangent(Body,Body.Phase);
        DX:=Intro.D.X-Body.Center.X;DY:=Intro.D.Y-Body.Center.Y;Distance:=Hypot(DX,DY);Direction:=OrbitPoint(DX/Distance,DY/Distance);
        Distance:=Hypot(V.X,V.Y);W:=OrbitPoint(V.X/Distance,V.Y/Distance);
        Intro.A:=OrbitPoint(Intro.D.X+Direction.X*6.5+W.X*1.3,Intro.D.Y+Direction.Y*6.5+W.Y*1.3);
        Intro.B:=OrbitPoint(Intro.A.X-Direction.X*2.7,Intro.A.Y-Direction.Y*2.7);
        Intro.C:=OrbitPoint(Intro.D.X-V.X*(T-IntroStart)/3,Intro.D.Y-V.Y*(T-IntroStart)/3);Legs.Add(Intro);
        // 先頭音も入場曲線上で叩く。演出のために音を後ろへ移動しない。
        while True do begin Check;
          EndOrbit:=Near(T+6.4+0.8*Sin(Index*1.7));
          if EndOrbit+3.4>=Result.FData.DepartStart then EndOrbit:=Result.FData.DepartStart;
          Body:=Bodies[Index];Body.Exit:=EndOrbit;Bodies[Index]:=Body;
          L:=Default(TOrbitLeg);L.Kind:=0;L.Start:=T;L.Finish:=EndOrbit;L.FromBody:=Index;L.ToBody:=Index;
          L.A:=OrbitBodyAt(Body,Body.Phase);Angle:=Body.Phase+(EndOrbit-Body.Entry)*Body.Speed;L.D:=OrbitBodyAt(Body,Angle);L.B:=L.A;L.C:=L.D;Legs.Add(L);
          if EndOrbit>=Result.FData.DepartStart then Break;
          EndFlight:=Near(EndOrbit+1.65+0.25*(0.5+0.5*Cos(Index)));Duration:=EndFlight-EndOrbit;
          P:=L.D;DX:=P.X-Body.Center.X;DY:=P.Y-Body.Center.Y;Distance:=Hypot(DX,DY);
          Next:=MakeBody(Index+1,OrbitPoint(Body.Center.X+DX/Distance*6.2,Body.Center.Y+DY/Distance*6.2),EndFlight);Next.Show:=EndOrbit-1.6;
          DX:=Body.Center.X-Next.Center.X;DY:=Body.Center.Y-Next.Center.Y;V:=OrbitPoint(DX*Cos(Next.Rotation)+DY*Sin(Next.Rotation),-DX*Sin(Next.Rotation)+DY*Cos(Next.Rotation));
          Next.Phase:=ArcTan2(V.Y/Next.RY,V.X/Next.RX);Bodies.Add(Next);
          Flight:=Default(TOrbitLeg);Flight.Kind:=1;Flight.Start:=EndOrbit;Flight.Finish:=EndFlight;Flight.FromBody:=Index;Flight.ToBody:=Index+1;
          Flight.A:=P;Flight.D:=OrbitBodyAt(Next,Next.Phase);V:=OrbitTangent(Body,Angle);W:=OrbitTangent(Next,Next.Phase);
          Flight.B:=OrbitPoint(P.X+V.X*Duration/3,P.Y+V.Y*Duration/3);Flight.C:=OrbitPoint(Flight.D.X-W.X*Duration/3,Flight.D.Y-W.Y*Duration/3);Legs.Add(Flight);
          Body.Clear:=EndFlight+1.4;Bodies[Index]:=Body;Inc(Index);T:=EndFlight;if Bodies.Count>=ORBIT_MAX_BODIES then raise Exception.Create('Orbit planet capacity');
        end;
        Body:=Bodies[Index];P:=L.D;V:=OrbitTangent(Body,Angle);DX:=P.X-Body.Center.X;DY:=P.Y-Body.Center.Y;Distance:=Hypot(DX,DY);Direction:=OrbitPoint(DX/Distance,DY/Distance);
        Distance:=Hypot(V.X,V.Y);W:=OrbitPoint(V.X/Distance,V.Y/Distance);Duration:=Result.FData.DepartFinish-Result.FData.DepartStart;
        Departure:=Default(TOrbitLeg);Departure.Kind:=3;Departure.Start:=Result.FData.DepartStart;Departure.Finish:=Result.FData.DepartFinish;Departure.FromBody:=Index;Departure.ToBody:=Index;
        Departure.A:=P;Departure.B:=OrbitPoint(P.X+V.X*Duration/3,P.Y+V.Y*Duration/3);
        Departure.D:=OrbitPoint(P.X+Direction.X*7.5+W.X*0.9,P.Y+Direction.Y*7.5+W.Y*0.9);
        // 終点の速度を0にし、停止するクリア区間へ接線の折れ目なく接続する。
        Departure.C:=Departure.D;Legs.Add(Departure);
        Hold:=Default(TOrbitLeg);Hold.Kind:=4;Hold.Start:=Departure.Finish;Hold.Finish:=Story;Hold.FromBody:=Index;Hold.ToBody:=Index;
        Hold.A:=Departure.D;Hold.B:=Hold.A;Hold.C:=Hold.A;Hold.D:=Hold.A;Legs.Add(Hold);
      end;
      Result.FData.Bodies:=Bodies.ToArray;Result.FData.Legs:=Legs.ToArray;J:=0;Chain:=0;Last:=-1;
      for I:=0 to High(Audio.Hits) do begin Check;T:=Audio.Hits[I].Time;
        if (Audio.SoundEnd<=0) or (T>Audio.SoundEnd) or (Audio.Hits[I].Strength<Threshold/100) then Continue;
        while (J<Legs.Count-1) and (Legs[J].Finish<T) do Inc(J);
        Tap:=Default(TOrbitTap);Tap.Time:=T;Tap.Source:=I;Tap.Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);Tap.Leg:=J;
        if (Last<0) or (T-Last>0.18) then Chain:=1 else Inc(Chain);Tap.Chain:=Chain;Tap.Appear:=T-1.45;Tap.P:=OrbitLegAt(Result.FData,J,T);Taps.Add(Tap);Last:=T;
      end;
      Result.FData.Taps:=Taps.ToArray;Result.Validate;
    except Result.Free;raise;end;
  finally Taps.Free;Legs.Free;Bodies.Free;Times.Free;end;
end;

procedure TOrbitPlan.Validate;
var I,J,Adopted,Weak,Tail:Integer;E:TRhythmHit;N:TOrbitTap;L:TOrbitLeg;B:TOrbitBody;P:TOrbitPoint;Last,T:Double;
  procedure Require(OK:Boolean;const Why:string);
  begin if not OK then raise Exception.Create('Orbit '+Why);end;
  procedure Point(const P:TOrbitPoint);
  begin Require(OrbitFinite(P.X) and OrbitFinite(P.Y) and (Abs(P.X)<10000) and (Abs(P.Y)<10000),'point');end;
begin
  Require(OrbitFinite(FData.Duration) and OrbitFinite(FData.SoundEnd) and OrbitFinite(FData.EndTime) and
    (FData.Duration>0) and (FData.Duration<=3043.5) and (FData.SoundEnd>=0) and (FData.SoundEnd<=FData.Duration) and
    (((FData.Version=2) and (FData.EndTime=Max(FData.Duration,FData.SoundEnd+ORBIT_EFFECT_LIFE)) and (FData.Threshold>=0)) or
     ((FData.Version>=3) and (FData.EndTime=FData.Duration) and (FData.Threshold>=-100))) and (FData.Threshold<=100),'bounds');
  Require((Length(FData.Events)<=ORBIT_MAX_EVENTS) and (Count<=Length(FData.Events)) and (BodyCount<=ORBIT_MAX_BODIES) and (LegCount<=2*ORBIT_MAX_BODIES+3),'capacity');
  Adopted:=0;Weak:=0;Tail:=0;Last:=-1;
  for I:=0 to High(FData.Events) do begin E:=FData.Events[I];
    Require(OrbitFinite(E.Time) and OrbitFinite(E.Strength) and (E.Time>=0) and (E.Time>=Last) and (E.Time<=FData.Duration+0.011),'event');Last:=E.Time;
    if (FData.SoundEnd<=0) or (E.Time>FData.SoundEnd) then Inc(Tail)
    else if E.Strength<FData.Threshold/100 then Inc(Weak) else begin
      Require(Adopted<Count,'missing tap');N:=FData.Taps[Adopted];
      Require((N.Source=I) and (N.Time=E.Time) and (N.Strength=EnsureRange(E.Strength,0.0,1.0)),'source clock');Inc(Adopted);
    end;
  end;
  Require((Adopted=Count) and (Weak=FData.Weak) and (Tail=FData.Tail),'selection coverage');
  if (FData.Version>=3) and (Count>0) then Require((FData.IntroFinish>0) and (FData.IntroFinish<FData.DepartStart) and
    (FData.DepartStart<FData.DepartFinish) and (FData.DepartFinish<FData.SoundEnd) and
    (FData.ClearTime>=FData.DepartStart) and (FData.ClearTime<=FData.SoundEnd) and
    (FData.Legs[0].Kind=2) and (FData.Legs[LegCount-1].Kind=4),'show timeline');
  Require((Count=0)=(LegCount=0),'empty legs');Require((Count=0)=(BodyCount=0),'empty planets');
  for B in FData.Bodies do begin Point(B.Center);
    Require(OrbitFinite(B.Show) and OrbitFinite(B.Entry) and OrbitFinite(B.Exit) and OrbitFinite(B.Clear) and
      (B.Show<B.Entry) and (B.Entry<B.Exit) and (B.Exit<B.Clear) and (B.Radius>=0.27) and (B.Radius<=0.39) and
      (B.RX>=1.1) and (B.RX<=1.5) and (B.RY>=0.6) and (B.RY<=1.3) and
      OrbitFinite(B.Phase) and OrbitFinite(B.Rotation) and (Abs(B.Rotation)<=0.5) and (B.Speed>=0.85) and (B.Speed<=1.35) and (B.Hue in [0..7]),'body');
  end;
  for I:=0 to LegCount-1 do begin L:=FData.Legs[I];
    Require(OrbitFinite(L.Start) and OrbitFinite(L.Finish) and (L.Start<L.Finish) and (L.FromBody>=0) and (L.FromBody<BodyCount) and
      (L.ToBody>=L.FromBody) and (L.ToBody<BodyCount) and (L.ToBody<=L.FromBody+1) and (L.Kind in [0..4]) and
      (((L.Kind=1) and (L.ToBody=L.FromBody+1)) or ((L.Kind<>1) and (L.ToBody=L.FromBody))),'leg');Point(L.A);Point(L.B);Point(L.C);Point(L.D);
    if I>0 then Require((L.Start=FData.Legs[I-1].Finish) and (L.A.X=FData.Legs[I-1].D.X) and (L.A.Y=FData.Legs[I-1].D.Y),'connection');
    for J:=0 to 32 do begin T:=L.Start+(L.Finish-L.Start)*J/32;P:=PointAt(I,T);Point(P);
      B:=FData.Bodies[L.FromBody];Require(Hypot(P.X-B.Center.X,P.Y-B.Center.Y)>B.Radius+0.04,'source planet penetration');
      if L.ToBody<>L.FromBody then begin B:=FData.Bodies[L.ToBody];Require(Hypot(P.X-B.Center.X,P.Y-B.Center.Y)>B.Radius+0.04,'arrival penetration');end;
    end;
  end;
  for I:=0 to Count-1 do begin N:=FData.Taps[I];Point(N.P);
    Require((N.Leg>=0) and (N.Leg<LegCount) and OrbitFinite(N.Appear) and (N.Appear<N.Time) and (N.Chain>=1) and (N.Chain<=I+1),'tap');
    L:=FData.Legs[N.Leg];Require((N.Time>=L.Start) and (N.Time<=L.Finish),'tap interval');P:=CursorAt(N.Time);
    Require((P.X=N.P.X) and (P.Y=N.P.Y),'actual contact');
  end;
end;
procedure TOrbitPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
begin Validate;WriteOrbitData(FData,Ref,Audio);end;
class function TOrbitPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TOrbitPlan;
begin Result:=TOrbitPlan.Create;
  try Result.FData:=ReadOrbitData(Ref,Audio,Direction);Result.Validate;except Result.Free;raise;end;
end;
class function TOrbitPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin Result:=ReadOrbitMetadata(Ref,Source,Direction);end;
end.
