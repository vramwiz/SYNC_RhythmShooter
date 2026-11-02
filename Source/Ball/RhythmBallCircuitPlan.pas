unit RhythmBallCircuitPlan;
// Version 6: fixed audio clocks, explicit guided routes and contact surfaces.
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmBallGeometry;
const
  CIRCUIT_WIDTH=16/9;
  CIRCUIT_HEIGHT=1.0;
  CIRCUIT_RADIUS=0.022;
type
  TCircuitMotion=(cmLine,cmRail,cmArm,cmLoop,cmHold,cmLaunch);
  TCircuitNodeKind=(cnStart,cnBumper,cnArmCapture,cnArmRelease,cnRailEntry,cnRailExit,cnCatch,cnLaunch,cnFinish);
  TCircuitNode=record
    Time,Strength,Radius:Double;
    P,Normal:TBallPoint;
    Source:Integer;
    Kind:TCircuitNodeKind;
  end;
  TCircuitSegment=record
    First,Last,Radius,Angle,Sweep:Double;
    A,B,C,D,Center:TBallPoint;
    Kind:TCircuitMotion;
  end;
  TCircuitObjectKind=(coImpact,coWall,coGear,coCharge);
  TCircuitObject=record
    Time,Show,Half:Double;
    Point,Normal:TBallPoint;
    Owner:Integer;
    Kind:TCircuitObjectKind;
  end;
  TCircuitPulse=record
    Time,Strength:Double;
    Source,ObjectIndex:Integer;
  end;
  TBallCircuitPlan=class
  private
    FNodes:TArray<TCircuitNode>;
    FSegments:TArray<TCircuitSegment>;
    FObjects:TArray<TCircuitObject>;
    FPulses:TArray<TCircuitPulse>;
    FEnd,FSoundEnd,FDuration:Double;
    FExcluded,FSourceCount:Integer;
    function GetNodeCount:Integer;
    function GetSegmentCount:Integer;
    function GetObjectCount:Integer;
    function GetPulseCount:Integer;
    function GetNode(I:Integer):TCircuitNode;
    function GetSegment(I:Integer):TCircuitSegment;
    function GetObject(I:Integer):TCircuitObject;
    function GetPulse(I:Integer):TCircuitPulse;
  public
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TBallCircuitPlan; static;
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TBallCircuitPlan; static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio; static;
    procedure Save(var Ref:TRhythmPlanRef);
    procedure Verify(const Cancel:TFunc<Boolean> = nil);
    function SegmentAt(Time:Double):Integer;
    function NodeBefore(Time:Double):Integer;
    function ObjectBefore(Time:Double):Integer;
    function PulseBefore(Time:Double):Integer;
    function PositionAt(Time:Double):TBallPoint;
    function TangentAt(Time:Double):TBallPoint;
    property NodeCount:Integer read GetNodeCount;
    property Node[I:Integer]:TCircuitNode read GetNode;
    property SegmentCount:Integer read GetSegmentCount;
    property Segment[I:Integer]:TCircuitSegment read GetSegment;
    property ObjectCount:Integer read GetObjectCount;
    property Obj[I:Integer]:TCircuitObject read GetObject;
    property PulseCount:Integer read GetPulseCount;
    property Pulse[I:Integer]:TCircuitPulse read GetPulse;
    property EndTime:Double read FEnd;
    property SoundEnd:Double read FSoundEnd;
    property ExcludedCount:Integer read FExcluded;
  end;
function CircuitPoint(const S:TCircuitSegment;Time:Double):TBallPoint;
function CircuitDistanceToWall(const P:TBallPoint;const O:TCircuitObject):Double;
implementation
uses System.Math,System.JSON,System.Generics.Collections,RhythmPreparedData,RhythmStyles;

function Finite(X:Double):Boolean;
begin Result:=not IsNan(X) and not IsInfinite(X);
end;

function Inside(const P:TBallPoint;Margin:Double):Boolean;
begin Result:=Finite(P.X) and Finite(P.Y) and (P.X>=Margin) and (P.X<=CIRCUIT_WIDTH-Margin) and (P.Y>=Margin) and (P.Y<=1-Margin);
end;

procedure Check(const Cancel:TFunc<Boolean>);
begin if Assigned(Cancel) and Cancel() then Abort;
end;

function CircuitPoint(const S:TCircuitSegment;Time:Double):TBallPoint;
var
  U,V,A:Double;
begin
  U:=EnsureRange((Time-S.First)/Max(1E-12,S.Last-S.First),0.0,1.0);
  case S.Kind of
    cmArm,cmLoop:begin A:=S.Angle+S.Sweep*U;
      Exit(BallAdd(S.Center,BallPoint(Cos(A)*S.Radius,Sin(A)*S.Radius)));
    end;
    cmHold:Exit(S.A);
    cmLaunch:U:=U*U;
    cmRail:begin V:=1-U;
      Exit(BallAdd(BallAdd(BallScale(S.A,V*V*V),BallScale(S.B,3*V*V*U)),BallAdd(BallScale(S.C,3*V*U*U),BallScale(S.D,U*U*U))));
    end;
  end;
  Result:=BallMix(S.A,S.D,U);
end;

function CircuitDistanceToWall(const P:TBallPoint;const O:TCircuitObject):Double;
var
  C,T,D:TBallPoint;
  U:Double;
begin C:=BallSub(O.Point,BallScale(O.Normal,O.Half));
  T:=BallPoint(-O.Normal.Y,O.Normal.X);
  D:=BallSub(P,C);
  U:=EnsureRange(BallDot(D,T),-0.065,0.065);
  Result:=BallLength(BallSub(D,BallScale(T,U)));
end;

function TBallCircuitPlan.GetNodeCount:Integer;
begin Result:=Length(FNodes);
end;

function TBallCircuitPlan.GetSegmentCount:Integer;
begin Result:=Length(FSegments);
end;

function TBallCircuitPlan.GetObjectCount:Integer;
begin Result:=Length(FObjects);
end;

function TBallCircuitPlan.GetPulseCount:Integer;
begin Result:=Length(FPulses);
end;

function TBallCircuitPlan.GetNode(I:Integer):TCircuitNode;
begin Result:=FNodes[I];
end;

function TBallCircuitPlan.GetSegment(I:Integer):TCircuitSegment;
begin Result:=FSegments[I];
end;

function TBallCircuitPlan.GetObject(I:Integer):TCircuitObject;
begin Result:=FObjects[I];
end;

function TBallCircuitPlan.GetPulse(I:Integer):TCircuitPulse;
begin Result:=FPulses[I];
end;

function TBallCircuitPlan.NodeBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=NodeCount;
  while A<B do begin M:=(A+B) div 2;
    if FNodes[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=Max(0,A-1);
end;

function TBallCircuitPlan.SegmentAt(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=SegmentCount;
  while A<B do begin M:=(A+B) div 2;
    if FSegments[M].First<=Time then A:=M+1 else B:=M;
  end;
  Result:=EnsureRange(A-1,0,Max(0,SegmentCount-1));
end;

function TBallCircuitPlan.ObjectBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=ObjectCount;
  while A<B do begin M:=(A+B) div 2;
    if FObjects[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBallCircuitPlan.PulseBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=PulseCount;
  while A<B do begin M:=(A+B) div 2;
    if FPulses[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBallCircuitPlan.PositionAt(Time:Double):TBallPoint;
begin if SegmentCount=0 then Exit(FNodes[0].P);
  Time:=EnsureRange(Time,0.0,FEnd);
  Result:=CircuitPoint(FSegments[SegmentAt(Time)],Time);
end;

function TBallCircuitPlan.TangentAt(Time:Double):TBallPoint;
var
  I:Integer;
  S:TCircuitSegment;
  A,B:TBallPoint;
  D,U:Double;
begin
  if SegmentCount=0 then Exit(BallPoint(0,-1));
  I:=SegmentAt(Time);
  S:=FSegments[I];
  if S.Kind=cmHold then Exit(BallPoint(0,-1));
  if S.Kind in [cmArm,cmLoop] then begin U:=EnsureRange((Time-S.First)/Max(1E-12,S.Last-S.First),0.0,1.0);
    D:=S.Angle+S.Sweep*U;
    Result:=BallUnit(BallPoint(-Sin(D)*S.Sweep,Cos(D)*S.Sweep));
    Exit;
  end;
  A:=CircuitPoint(S,Max(S.First,Time-1E-5));
  B:=CircuitPoint(S,Min(S.Last,Time+1E-5));
  Result:=BallUnit(BallSub(B,A));
end;

class function TBallCircuitPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TBallCircuitPlan;
var
  Nodes:TList<TCircuitNode>;
  Segments:TList<TCircuitSegment>;
  Objects:TList<TCircuitObject>;
  Pulses:TList<TCircuitPulse>;
  N,Q:TCircuitNode;
  S,Previous:TCircuitSegment;
  O:TCircuitObject;
  P:TCircuitPulse;
  I,J,K,Phase,LastSource,Owner:Integer;
  T,Gap,Side,Sweep,Limit,D,Lead,Half:Double;
  A,B,Incoming,Outgoing:TBallPoint;
  Clear:Boolean;
  procedure AddAnchor(Source:Integer);
  var
    Node:TCircuitNode;
    Segment:TCircuitSegment;
    Point,Dir,Probe:TBallPoint;
    R,MidY:Double;
    Sample:Integer;
    Good:Boolean;
  begin
    Check(Cancel);
    Node:=Default(TCircuitNode);
    Node.Time:=Audio.Hits[Source].Time;
    Node.Source:=Source;
    Node.Strength:=EnsureRange(Audio.Hits[Source].Strength,0.0,1.0);
    Q:=Nodes[Nodes.Count-1];
    Segment:=Default(TCircuitSegment);
    Segment.First:=Q.Time;
    Segment.Last:=Node.Time;
    Segment.A:=Q.P;
    Segment.Kind:=cmLine;
    Phase:=Nodes.Count mod 10;
    if Segments.Count>0 then Previous:=Segments[Segments.Count-1] else Previous:=Default(TCircuitSegment);
    if (Nodes.Count=1) and (Node.Time<0.35) then Segment.Kind:=cmHold
    else if (Segments.Count>0) and (Previous.Kind=cmHold) then Segment.Kind:=cmLaunch
    else case Phase of 3:Segment.Kind:=cmArm;
      5:Segment.Kind:=cmRail;
      6:Segment.Kind:=cmLoop;
      8:if (Node.Time-Q.Time>=0.60) and (Node.Strength>=0.70) then Segment.Kind:=cmHold else Segment.Kind:=cmRail;
    end;
    if Segment.Kind=cmHold then Point:=Q.P
    else if Segment.Kind in [cmArm,cmLoop] then begin
      Side:=1;
      if Q.P.X>CIRCUIT_WIDTH/2 then Side:=-1;
      R:=0.19;
      Segment.Center:=BallAdd(Q.P,BallPoint(Side*R,0));
      Segment.Radius:=R;
      Segment.Angle:=0;
      if Side>0 then Segment.Angle:=Pi;
      Sweep:=Side*2*Pi;
      if Segments.Count>0 then begin Dir:=BallUnit(BallSub(Previous.D,CircuitPoint(Previous,Max(Previous.First,Previous.Last-0.0001))));
        if Dir.Y>0 then Sweep:=-Side*2*Pi;
      end;
      if Segment.Kind=cmArm then begin R:=0.18;
        Dir:=BallUnit(BallSub(Previous.D,CircuitPoint(Previous,Max(Previous.First,Previous.Last-0.0001))));
        Segment.Center:=BallAdd(Q.P,BallScale(Dir,R));
        Segment.Radius:=R;
        Segment.Angle:=ArcTan2(Q.P.Y-Segment.Center.Y,Q.P.X-Segment.Center.X);
        Sweep:=Pi;
        Good:=True;
        for Sample:=0 to 16 do begin Probe:=BallAdd(Segment.Center,BallPoint(Cos(Segment.Angle+Sweep*Sample/16)*R,Sin(Segment.Angle+Sweep*Sample/16)*R));
          if not Inside(Probe,0.03) then Good:=False;
        end;
        if not Good then Sweep:=-Pi;
      end;
      Segment.Sweep:=Sweep;
      Point:=BallAdd(Segment.Center,BallPoint(Cos(Segment.Angle+Sweep)*R,Sin(Segment.Angle+Sweep)*R));
    end else begin
      Point.X:=0.18;
      if Q.P.X<CIRCUIT_WIDTH/2 then Point.X:=CIRCUIT_WIDTH-0.18;
      Point.Y:=0.22;
      if Q.P.Y<0.5 then Point.Y:=0.78;
      if (Phase=2) and (Segment.Kind in [cmLine,cmLaunch]) then Point:=BallPoint(CIRCUIT_WIDTH*0.5,0.5);
      if (Segments.Count>0) and (Previous.Kind in [cmArm,cmLoop]) then begin
        D:=Previous.Angle+Previous.Sweep;
        Dir:=BallUnit(BallPoint(-Sin(D)*Previous.Sweep,Cos(D)*Previous.Sweep));
        Limit:=10;
        if Dir.X>1E-8 then Limit:=Min(Limit,(CIRCUIT_WIDTH-0.16-Q.P.X)/Dir.X) else if Dir.X< -1E-8 then Limit:=Min(Limit,(0.16-Q.P.X)/Dir.X);
        if Dir.Y>1E-8 then Limit:=Min(Limit,(0.84-Q.P.Y)/Dir.Y) else if Dir.Y< -1E-8 then Limit:=Min(Limit,(0.16-Q.P.Y)/Dir.Y);
        Point:=BallAdd(Q.P,BallScale(Dir,Max(0.12,Limit)));
      end;
    end;
    Segment.D:=Point;
    Segment.B:=BallMix(Q.P,Point,1/3);
    Segment.C:=BallMix(Q.P,Point,2/3);
    if Segment.Kind=cmRail then begin MidY:=0.12;
      if Q.P.Y<0.5 then MidY:=0.88;
      Segment.B:=BallPoint(Q.P.X,MidY);
      Segment.C:=BallPoint(Point.X,MidY);
    end;
    Node.P:=Point;
    Nodes.Add(Node);
    Segments.Add(Segment);
  end;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  Check(Cancel);
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then raise Exception.Create('Circuit audio bounds');
  Result:=TBallCircuitPlan.Create;
  Nodes:=TList<TCircuitNode>.Create;
  Segments:=TList<TCircuitSegment>.Create;
  Objects:=TList<TCircuitObject>.Create;
  Pulses:=TList<TCircuitPulse>.Create;
  try
    Result.FDuration:=Audio.Duration;
    Result.FSoundEnd:=Audio.SoundEnd;
    Result.FSourceCount:=Length(Audio.Hits);
    Result.FEnd:=Audio.SoundEnd;
    N:=Default(TCircuitNode);
    N.P:=BallPoint(0.18,0.78);
    N.Kind:=cnStart;
    N.Source:=-1;
    Nodes.Add(N);
    LastSource:=-1;
    T:=-1;
    for I:=0 to High(Audio.Hits) do begin Check(Cancel);
      if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or (Audio.Hits[I].Time<T) or (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('Circuit source order');
      T:=Audio.Hits[I].Time;
      if (Audio.SoundEnd<=0) or (T>Audio.SoundEnd+1E-6) then begin Inc(Result.FExcluded);
        Continue;
      end;
      if (LastSource<0) or (T-Audio.Hits[LastSource].Time>=0.60-1E-9) then begin AddAnchor(I);
        LastSource:=I;
      end;
    end;
    if Nodes.Count>1 then begin Q:=Nodes[Nodes.Count-1];
      if Q.Time<Result.FEnd then begin S:=Default(TCircuitSegment);
        S.First:=Q.Time;
        S.Last:=Result.FEnd;
        S.Kind:=cmHold;
        S.A:=Q.P;
        S.B:=Q.P;
        S.C:=Q.P;
        S.D:=Q.P;
        Segments.Add(S);
      end;
    end;
    Result.FNodes:=Nodes.ToArray;
    Result.FSegments:=Segments.ToArray;
    // Classify actual junctions: every change has a visible mechanism.
    for I:=1 to Result.NodeCount-1 do begin N:=Result.FNodes[I];
      N.Kind:=cnBumper;
      Incoming:=Result.TangentAt(Max(0.0,N.Time-1E-5));
      Outgoing:=Result.TangentAt(N.Time+1E-5);
      if I<Result.SegmentCount then begin S:=Result.FSegments[I];
        case S.Kind of cmArm:N.Kind:=cnArmCapture;
          cmLoop,cmRail:N.Kind:=cnRailEntry;
          cmHold:N.Kind:=cnCatch;
        end;
      end;
      if I>0 then begin S:=Result.FSegments[I-1];
        case S.Kind of cmArm:N.Kind:=cnArmRelease;
          cmLoop,cmRail:if N.Kind=cnBumper then N.Kind:=cnRailExit;
          cmHold:N.Kind:=cnLaunch;
        end;
      end;
      if N.Kind=cnBumper then begin N.Normal:=BallUnit(BallSub(Outgoing,Incoming));
        if BallDot(Incoming,N.Normal)>-0.05 then begin N.Kind:=cnRailExit;
          N.Normal:=BallScale(Incoming,-1);
        end;
      end
      else if N.Kind=cnLaunch then N.Normal:=Outgoing
      else if N.Kind=cnArmCapture then N.Normal:=BallUnit(BallSub(N.P,Result.FSegments[I].Center))
      else if N.Kind=cnArmRelease then N.Normal:=BallUnit(BallSub(N.P,Result.FSegments[I-1].Center))
      else if N.Kind=cnRailEntry then begin S:=Result.FSegments[I];
        if S.Kind=cmLoop then N.Normal:=BallUnit(BallSub(N.P,S.Center)) else N.Normal:=BallPoint(-Outgoing.Y,Outgoing.X);
      end
      else if N.Kind=cnRailExit then begin S:=Result.FSegments[I-1];
        if S.Kind=cmLoop then N.Normal:=BallUnit(BallSub(N.P,S.Center)) else N.Normal:=BallPoint(-Incoming.Y,Incoming.X);
      end
      else N.Normal:=BallScale(Incoming,-1);
      N.Radius:=0.090+N.Strength*0.045;
      Result.FNodes[I]:=N;
    end;
    for I:=0 to High(Audio.Hits) do begin Check(Cancel);
      T:=Audio.Hits[I].Time;
      if (Audio.SoundEnd<=0) or (T>Audio.SoundEnd+1E-6) then Continue;
      P.Time:=T;
      P.Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);
      P.Source:=I;
      if (Objects.Count>0) and (Objects[Objects.Count-1].Time=T) then P.ObjectIndex:=Objects.Count-1
      else begin
        O:=Default(TCircuitObject);
        O.Time:=T;
        Owner:=Result.NodeBefore(T);
        A:=Result.PositionAt(T);
        O.Kind:=coImpact;
        O.Owner:=Owner;
        N:=Result.FNodes[Owner];
        if Abs(N.Time-T)<1E-9 then begin O.Normal:=N.Normal;
          if N.Kind=cnStart then O.Normal:=BallPoint(0,-1);
          O.Point:=BallSub(A,BallScale(O.Normal,CIRCUIT_RADIUS));
          O.Show:=Max(0.0,T-0.20);
        end
        else begin Owner:=Result.SegmentAt(T);
          S:=Result.FSegments[Owner];
          O.Owner:=Owner;
          case S.Kind of
            cmHold:begin O.Kind:=coCharge;
              O.Normal:=BallPoint(0,-1);
            end;
            cmArm:begin O.Kind:=coGear;
              O.Normal:=BallUnit(BallSub(A,S.Center));
            end;
            else O.Kind:=coWall;
            O.Normal:=BallScale(Result.TangentAt(T),-1);
          end;
          O.Point:=BallSub(A,BallScale(O.Normal,CIRCUIT_RADIUS));
          O.Show:=Max(S.First,T-Min(0.20,(S.Last-S.First)*0.20));
          if O.Kind=coWall then begin
            Half:=0.003;
            Gap:=1;
            if I>0 then Gap:=Min(Gap,T-Audio.Hits[I-1].Time);
            if I<High(Audio.Hits) then Gap:=Min(Gap,Audio.Hits[I+1].Time-T);
            B:=Result.PositionAt(Min(S.Last,T+Max(1E-5,Gap)));
            Half:=Min(Half,Max(1E-7,BallLength(BallSub(B,A))*0.15));
            O.Half:=Half;
            // Shorten only a wall's materialisation lead if a curved earlier path intersects it.
            Lead:=T-O.Show;
            for K:=0 to 8 do begin Clear:=True;
              for J:=1 to 16 do begin D:=T-Lead*J/16;
                B:=Result.PositionAt(D);
                if CircuitDistanceToWall(B,O)<CIRCUIT_RADIUS+O.Half-1E-8 then Clear:=False;
              end;
              if Clear then Break;
              Lead:=Lead*0.5;
              O.Show:=T-Lead;
            end;
          end;
        end;
        P.ObjectIndex:=Objects.Count;
        Objects.Add(O);
      end;
      Pulses.Add(P);
    end;
    Result.FObjects:=Objects.ToArray;
    Result.FPulses:=Pulses.ToArray;
    Result.Verify(Cancel);
  except Result.Free;
    Nodes.Free;
    Segments.Free;
    Objects.Free;
    Pulses.Free;
    raise;
  end;
  Nodes.Free;
  Segments.Free;
  Objects.Free;
  Pulses.Free;
end;

procedure TBallCircuitPlan.Verify(const Cancel:TFunc<Boolean>);
var
  I,J,K:Integer;
  S:TCircuitSegment;
  O:TCircuitObject;
  N:TCircuitNode;
  P,Q,V,Normal,Center:TBallPoint;
  T,Distance:Double;
  procedure Need(V:Boolean;const Msg:string);
  begin if not V then raise Exception.Create('Circuit verification: '+Msg);
  end;
begin
  Need((NodeCount>=1) and (NodeCount<=10000) and (SegmentCount<=10000) and (ObjectCount<=100000) and (PulseCount<=100000),'counts');
  Need(Finite(FEnd) and Finite(FDuration) and Finite(FSoundEnd) and (FEnd=FSoundEnd) and (FDuration>0) and (FEnd>=0) and (FEnd<=FDuration),'end');
  Need((FExcluded>=0) and (FSourceCount<=100000) and (PulseCount+FExcluded=FSourceCount),'source coverage');
  Need((FNodes[0].Time=0) and (FNodes[0].Kind=cnStart),'start node');
  Need((SegmentCount>=NodeCount-1) and (SegmentCount<=NodeCount),'route count');
  for I:=0 to NodeCount-1 do begin Check(Cancel);
    N:=FNodes[I];
    Need(Finite(N.Time) and Inside(N.P,0.025),Format('node bounds %d (%.5f,%.5f)',[I,N.P.X,N.P.Y]));
    if I>0 then Need((N.Time>=FNodes[I-1].Time) and ((I=1) or (N.Time>FNodes[I-1].Time)),'node order');
    if I>0 then begin Need((N.Source>=0) and (N.Source<FSourceCount),'node source');
      Need(Finite(N.Strength) and (N.Strength>=0) and (N.Strength<=1) and Finite(N.Radius) and (N.Radius>=0.09) and (N.Radius<=0.13501),'node size');
      Need(Abs(BallLength(N.Normal)-1)<1E-7,'node normal');
      K:=PulseBefore(N.Time);
      Need((K>=0) and (Abs(FPulses[K].Time-N.Time)<1E-9),'node audio clock');
      if N.Kind=cnBumper then begin
        P:=TangentAt(N.Time-1E-5);
        Q:=TangentAt(N.Time+1E-5);
        V:=BallSub(P,BallScale(N.Normal,2*BallDot(P,N.Normal)));
        Need((BallDot(P,N.Normal)<0) and (BallDot(Q,N.Normal)>0) and (BallLength(BallSub(V,Q))<1E-6),'bumper reflection');
        Center:=BallSub(N.P,BallScale(N.Normal,N.Radius+CIRCUIT_RADIUS));
        // Independently replay the active approach/departure against the circle.
        for J:=0 to 32 do begin T:=N.Time-0.22+0.52*J/32;
          P:=PositionAt(T);
          Need(BallLength(BallSub(P,Center))>=N.Radius+CIRCUIT_RADIUS-1E-6,'earlier/later bumper collision');
        end;
      end;
    end;
  end;
  for I:=0 to SegmentCount-1 do begin Check(Cancel);
    S:=FSegments[I];
    Need(Finite(S.First) and Finite(S.Last) and (S.Last>=S.First),'segment time');
    if I>0 then Need(Abs(S.First-FSegments[I-1].Last)<1E-8,'segment continuity');
    Need(Finite(S.Radius) and Finite(S.Angle) and Finite(S.Sweep),'route parameters');
    if S.Kind in [cmArm,cmLoop] then Need((S.Radius>0) and (S.Radius<=0.20) and (Abs(S.Sweep)>0) and (Abs(S.Sweep)<=2*Pi+1E-9),'circular guide');
    if I<NodeCount-1 then Need((Abs(S.First-FNodes[I].Time)<1E-8) and (Abs(S.Last-FNodes[I+1].Time)<1E-8) and (BallLength(BallSub(S.A,FNodes[I].P))<1E-7) and (BallLength(BallSub(S.D,FNodes[I+1].P))<1E-7),'route node clock/position');
    P:=CircuitPoint(S,S.First);
    Q:=CircuitPoint(S,S.Last);
    Need(BallLength(BallSub(P,S.A))<1E-7,'segment start');
    Need(BallLength(BallSub(Q,S.D))<1E-7,'segment end');
    for J:=0 to 32 do begin T:=S.First+(S.Last-S.First)*J/32;
      Need(Inside(CircuitPoint(S,T),0.024),'path bounds');
    end;
  end;
  for I:=0 to ObjectCount-1 do begin Check(Cancel);
    O:=FObjects[I];
    Need(Finite(O.Time) and Finite(O.Show) and Finite(O.Half) and (O.Show>=0) and (O.Show<=O.Time),'object time');
    if I>0 then Need(O.Time>FObjects[I-1].Time,'object order');
    if O.Kind=coImpact then Need((O.Owner>=0) and (O.Owner<NodeCount),'node owner') else Need((O.Owner>=0) and (O.Owner<SegmentCount),'route owner');
    Need(Abs(BallLength(O.Normal)-1)<1E-7,'surface normal');
    P:=PositionAt(O.Time);
    Need(Abs(BallLength(BallSub(P,O.Point))-CIRCUIT_RADIUS)<1E-7,'visible surface contact');
    if O.Kind=coGear then begin S:=FSegments[O.Owner];
      Normal:=BallUnit(BallSub(P,S.Center));
      Center:=BallSub(P,BallScale(Normal,CIRCUIT_RADIUS+0.007));
      Need((S.Kind=cmArm) and (Abs(BallLength(BallSub(P,Center))-CIRCUIT_RADIUS-0.007)<1E-8),'arm joint contact');
    end;
    if O.Kind=coCharge then Need(FSegments[O.Owner].Kind=cmHold,'charge cup');
    if O.Kind=coWall then begin
      Need((O.Half>0) and (O.Half<=0.00301),'wall thickness');
      Distance:=CircuitDistanceToWall(P,O);
      Need(Abs(Distance-CIRCUIT_RADIUS-O.Half)<1E-7,'wall face');
      for J:=1 to 24 do begin T:=O.Time-(O.Time-O.Show)*J/24;
        P:=PositionAt(T);
        Need(CircuitDistanceToWall(P,O)>=CIRCUIT_RADIUS+O.Half-1E-7,'earlier wall collision');
      end;
    end;
  end;
  for I:=0 to PulseCount-1 do begin Check(Cancel);
    Need(Finite(FPulses[I].Time) and Finite(FPulses[I].Strength) and (FPulses[I].Strength>=0) and (FPulses[I].Strength<=1) and (FPulses[I].Source>=0) and (FPulses[I].Source<FSourceCount),'pulse source');
    Need((FPulses[I].ObjectIndex>=0) and (FPulses[I].ObjectIndex<ObjectCount),'pulse object');
    Need(Abs(FPulses[I].Time-FObjects[FPulses[I].ObjectIndex].Time)<1E-9,'pulse clock');
    if I>0 then Need((FPulses[I].Time>=FPulses[I-1].Time) and (FPulses[I].Source>FPulses[I-1].Source),'pulse order');
  end;
end;

procedure AddPoint(J:TJSONObject;const Name:string;const P:TBallPoint);
var
  A:TJSONArray;
begin A:=TJSONArray.Create;
  A.Add(P.X);
  A.Add(P.Y);
  J.AddPair(Name,A);
end;

function ReadPoint(J:TJSONObject;const Name:string):TBallPoint;
var
  A:TJSONArray;
begin A:=J.GetValue<TJSONArray>(Name);
  if (A=nil) or (A.Count<>2) then raise Exception.Create('Circuit point');
  Result.X:=A.Items[0].GetValue<Double>;
  Result.Y:=A.Items[1].GetValue<Double>;
  if not Finite(Result.X) or not Finite(Result.Y) then raise Exception.Create('Circuit nonfinite point');
end;

procedure TBallCircuitPlan.Save(var Ref:TRhythmPlanRef);
var
  Root,Info,J:TJSONObject;
  A:TJSONArray;
  N:TCircuitNode;
  S:TCircuitSegment;
  O:TCircuitObject;
  P:TCircuitPulse;
begin
  if (Ref.Style<>rsBall) or (Ref.Version<>6) then raise Exception.Create('Circuit reference');
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style','ball');
    Root.AddPair('version',TJSONNumber.Create(6));
    Root.AddPair('layout','full-field-circuit-v1');
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('end',TJSONNumber.Create(FEnd));
    Root.AddPair('excluded',TJSONNumber.Create(FExcluded));
    Info:=TJSONObject.Create;
    Root.AddPair('audio',Info);
    Info.AddPair('schema',TJSONNumber.Create(1));
    Info.AddPair('duration',TJSONNumber.Create(FDuration));
    Info.AddPair('soundEnd',TJSONNumber.Create(FSoundEnd));
    Info.AddPair('events',TJSONNumber.Create(FSourceCount));
    A:=TJSONArray.Create;
    Root.AddPair('nodes',A);
    for N in FNodes do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('t',TJSONNumber.Create(N.Time));
      J.AddPair('s',TJSONNumber.Create(N.Strength));
      J.AddPair('r',TJSONNumber.Create(N.Radius));
      J.AddPair('i',TJSONNumber.Create(N.Source));
      J.AddPair('k',TJSONNumber.Create(Ord(N.Kind)));
      AddPoint(J,'p',N.P);
      AddPoint(J,'n',N.Normal);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('routes',A);
    for S in FSegments do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('f',TJSONNumber.Create(S.First));
      J.AddPair('l',TJSONNumber.Create(S.Last));
      J.AddPair('r',TJSONNumber.Create(S.Radius));
      J.AddPair('a',TJSONNumber.Create(S.Angle));
      J.AddPair('w',TJSONNumber.Create(S.Sweep));
      J.AddPair('k',TJSONNumber.Create(Ord(S.Kind)));
      AddPoint(J,'p',S.A);
      AddPoint(J,'b',S.B);
      AddPoint(J,'c',S.C);
      AddPoint(J,'d',S.D);
      AddPoint(J,'o',S.Center);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('objects',A);
    for O in FObjects do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('t',TJSONNumber.Create(O.Time));
      J.AddPair('v',TJSONNumber.Create(O.Show));
      J.AddPair('h',TJSONNumber.Create(O.Half));
      J.AddPair('i',TJSONNumber.Create(O.Owner));
      J.AddPair('k',TJSONNumber.Create(Ord(O.Kind)));
      AddPoint(J,'p',O.Point);
      AddPoint(J,'n',O.Normal);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('pulses',A);
    for P in FPulses do begin J:=TJSONObject.Create;
      A.AddElement(J);
      J.AddPair('t',TJSONNumber.Create(P.Time));
      J.AddPair('s',TJSONNumber.Create(P.Strength));
      J.AddPair('i',TJSONNumber.Create(P.Source));
      J.AddPair('o',TJSONNumber.Create(P.ObjectIndex));
    end;
    WritePreparedData(Root,Ref);
  finally Root.Free;
  end;
end;

class function TBallCircuitPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var
  Root:TJSONObject;
begin Root:=ReadPreparedData(Ref,rsBall,Direction);
  try Result:=PreparedAudio(Root,Ref,Source);
  finally Root.Free;
  end;
end;

class function TBallCircuitPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TBallCircuitPlan;
var
  Root,J,Info:TJSONObject;
  A:TJSONArray;
  I,K:Integer;
  N:TCircuitNode;
  S:TCircuitSegment;
  O:TCircuitObject;
  P:TCircuitPulse;
  function Items(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);
    if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Circuit array '+Name);
  end;
begin
  Result:=nil;
  if Audio=nil then raise Exception.Create('Circuit audio missing');
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsBall) then raise Exception.Create('Circuit identity');
  Root:=ReadPreparedData(Ref,rsBall,Direction);
  try
    if Root.GetValue<string>('layout','')<>'full-field-circuit-v1' then raise Exception.Create('Circuit layout');
    Info:=Root.GetValue<TJSONObject>('audio');
    if (Info=nil) or (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-6) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-6) or (Info.GetValue<Integer>('events')<>Length(Audio.Hits)) then raise Exception.Create('Circuit audio identity');
    Result:=TBallCircuitPlan.Create;
    try
      Result.FDuration:=Audio.Duration;
      Result.FSoundEnd:=Audio.SoundEnd;
      Result.FSourceCount:=Length(Audio.Hits);
      Result.FEnd:=Root.GetValue<Double>('end');
      Result.FExcluded:=Root.GetValue<Integer>('excluded');
      A:=Items('nodes',10000);
      SetLength(Result.FNodes,A.Count);
      for I:=0 to A.Count-1 do begin J:=A.Items[I] as TJSONObject;
        N.Time:=J.GetValue<Double>('t');
        N.Strength:=J.GetValue<Double>('s');
        N.Radius:=J.GetValue<Double>('r');
        N.Source:=J.GetValue<Integer>('i');
        K:=J.GetValue<Integer>('k');
        if not (K in [0..8]) then raise Exception.Create('Circuit node kind');
        N.Kind:=TCircuitNodeKind(K);
        N.P:=ReadPoint(J,'p');
        N.Normal:=ReadPoint(J,'n');
        Result.FNodes[I]:=N;
      end;
      A:=Items('routes',10000);
      SetLength(Result.FSegments,A.Count);
      for I:=0 to A.Count-1 do begin J:=A.Items[I] as TJSONObject;
        S.First:=J.GetValue<Double>('f');
        S.Last:=J.GetValue<Double>('l');
        S.Radius:=J.GetValue<Double>('r');
        S.Angle:=J.GetValue<Double>('a');
        S.Sweep:=J.GetValue<Double>('w');
        K:=J.GetValue<Integer>('k');
        if not (K in [0..5]) then raise Exception.Create('Circuit route kind');
        S.Kind:=TCircuitMotion(K);
        S.A:=ReadPoint(J,'p');
        S.B:=ReadPoint(J,'b');
        S.C:=ReadPoint(J,'c');
        S.D:=ReadPoint(J,'d');
        S.Center:=ReadPoint(J,'o');
        Result.FSegments[I]:=S;
      end;
      A:=Items('objects',100000);
      SetLength(Result.FObjects,A.Count);
      for I:=0 to A.Count-1 do begin J:=A.Items[I] as TJSONObject;
        O.Time:=J.GetValue<Double>('t');
        O.Show:=J.GetValue<Double>('v');
        O.Half:=J.GetValue<Double>('h');
        O.Owner:=J.GetValue<Integer>('i');
        K:=J.GetValue<Integer>('k');
        if not (K in [0..3]) then raise Exception.Create('Circuit object kind');
        O.Kind:=TCircuitObjectKind(K);
        O.Point:=ReadPoint(J,'p');
        O.Normal:=ReadPoint(J,'n');
        Result.FObjects[I]:=O;
      end;
      A:=Items('pulses',100000);
      SetLength(Result.FPulses,A.Count);
      for I:=0 to A.Count-1 do begin J:=A.Items[I] as TJSONObject;
        P.Time:=J.GetValue<Double>('t');
        P.Strength:=J.GetValue<Double>('s');
        P.Source:=J.GetValue<Integer>('i');
        P.ObjectIndex:=J.GetValue<Integer>('o');
        Result.FPulses[I]:=P;
      end;
      Result.Verify;
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally Root.Free;
  end;
end;
end.
