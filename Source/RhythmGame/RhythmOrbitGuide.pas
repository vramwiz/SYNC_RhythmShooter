unit RhythmOrbitGuide;
// 採用音の時刻と表示サイズから、Type.Vのコースを組み立てる。
interface
uses RhythmOrbitPlan,RhythmOrbitTypes;
const
  ORBIT_GUIDE_STEPS=432;
  ORBIT_MARKER_LIMIT=128;
  ORBIT_MARKER_GAP=2.0;
  ORBIT_MARKER_LEAD=1.45;
type
  TOrbitVisualState=record
    Horizon,Density,Energy,Pulse,PreviewAlpha:Double;
    FirstTap,LastHit:Integer;
    Playing:Boolean;
  end;
  TOrbitRoutePoint=record
    Time:Double;
    P:TOrbitPoint;
  end;
  TOrbitRoute=array[0..ORBIT_GUIDE_STEPS] of TOrbitRoutePoint;
  TOrbitMarker=record
    Center:TOrbitPoint;
    Radius,Extent,Approach,Opacity,Visibility:Double;
    TapIndex,TapCount:Integer;
  end;
  TOrbitMarkers=array[0..ORBIT_MARKER_LIMIT-1] of TOrbitMarker;
  TOrbitCourse=record
  private type
    TCue=record
      Center,Velocity:TOrbitPoint;
      Time,ShowAt,Pace:Double;
      TapIndex,TapCount:Integer;
    end;
  private
    FCues:TArray<TCue>;
    FTapCue:TArray<Integer>;
    FWidth,FHeight,FHitRadius,FEntryTime,FExitTime:Double;
    FEntry,FExit:TOrbitPoint;
    function NextCue(Time:Double):Integer;
    function BackdropPoint(Plan:TOrbitPlan;Time:Double):TOrbitPoint;
  public
    procedure Prepare(Plan:TOrbitPlan;Width,Height:Double);
    function Center(TapIndex:Integer):TOrbitPoint;
    function CursorAt(Plan:TOrbitPlan;Time:Double):TOrbitPoint;
    function Route(Plan:TOrbitPlan;Start,Finish:Double;out Points:TOrbitRoute):Integer;
    function Visible(const State:TOrbitVisualState;Time:Double;out Markers:TOrbitMarkers):Integer;
  end;
function OrbitGameplayStart(Plan:TOrbitPlan):Double;
function OrbitOpeningTapCount(Plan:TOrbitPlan):Integer;
function OrbitVisualState(Plan:TOrbitPlan;Time:Double):TOrbitVisualState;
function OrbitMarkerOpacity(Ahead,Horizon:Double):Double;
implementation
uses System.Math,RhythmOrbitMarks;
const
  StartApproach=0.65;
function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);Result:=U*U*(3-2*U);end;
function EaseOut(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);Result:=U*(2-U);end;
function TapPace(Plan:TOrbitPlan;Index,FirstTap:Integer;Time:Double):Double;
var Gap:Double;
begin
  Gap:=0.42;
  if Index>FirstTap then Gap:=Min(Gap,Time-Plan.Taps[Index-1].Time);
  if Index+1<Plan.Count then Gap:=Min(Gap,Plan.Taps[Index+1].Time-Time);
  Result:=Smooth((0.42-Gap)/0.32);
end;
function OrbitGameplayStart(Plan:TOrbitPlan):Double;
begin
  if Plan=nil then Exit(0);
  Result:=Min(3.0,Plan.SoundEnd*0.5);
end;
function OrbitOpeningTapCount(Plan:TOrbitPlan):Integer;
begin
  if Plan=nil then Exit(0);
  Result:=Plan.Before(OrbitGameplayStart(Plan),False)+1;
end;
function OrbitVisualState(Plan:TOrbitPlan;Time:Double):TOrbitVisualState;
var I:Integer;N:TOrbitTap;Delta,Weight,Count,Power,FirstTime,Lead:Double;
begin
  Result:=Default(TOrbitVisualState);
  Result.LastHit:=-1;
  if (Plan=nil) or (Plan.Count=0) then Exit;
  Result.FirstTap:=OrbitOpeningTapCount(Plan);
  Result.LastHit:=Result.FirstTap-1;
  if Result.FirstTap>=Plan.Count then Exit;
  Result.Playing:=Time>=OrbitGameplayStart(Plan);
  if Result.Playing then Result.LastHit:=Plan.Before(Time);
  // 判定やEQを起こさず、最初の判定時刻の手前から予告だけを立ち上げる。
  FirstTime:=Plan.Taps[Result.FirstTap].Time;
  Lead:=FirstTime-Time;
  Result.PreviewAlpha:=EaseOut((ORBIT_MARKER_LEAD-Lead)/
    (0.45-0.20*TapPace(Plan,Result.FirstTap,Result.FirstTap,FirstTime)));
  if Result.PreviewAlpha<=0 then Exit;
  Count:=0;Power:=0;
  for I:=Max(Result.FirstTap,Result.LastHit-32) to Min(Plan.Count-1,Result.LastHit+32) do begin
    N:=Plan.Taps[I];Delta:=N.Time-Time;
    if Abs(Delta)<2 then begin Weight:=(1+Cos(Pi*Delta/2))*0.5;Count:=Count+Weight;Power:=Power+Weight*N.Strength;end;
  end;
  Result.Density:=EnsureRange(Count/12,0.0,1.0);
  if Count>0 then Result.Energy:=EnsureRange(Power/Count,0.0,1.0);
  for I:=Result.LastHit downto Max(Result.FirstTap,Result.LastHit-12) do begin
    Delta:=Time-Plan.Taps[I].Time;if Delta>0.8 then Break;
    // 反応光は実際の採用音の後だけ。先読みの密度は装飾の構図にのみ使う。
    if Delta>=0 then Result.Pulse:=Result.Pulse+Exp(-Delta*9)*(0.25+Plan.Taps[I].Strength*0.75);
  end;
  Result.Pulse:=EnsureRange(Result.Pulse,0.0,1.4);
  Result.Horizon:=Min(Max(0.0,Plan.SoundEnd-Time),5.6+1.2*(1-Result.Density));
end;
function OrbitMarkerOpacity(Ahead,Horizon:Double):Double;
begin
  if (Ahead<0) or (Horizon<=0) or (Ahead>Horizon) then Exit(0);
  Result:=Smooth(1-Ahead/Horizon);
end;

function TOrbitCourse.BackdropPoint(Plan:TOrbitPlan;Time:Double):TOrbitPoint;
begin
  Result:=OrbitProject(Plan.CursorAt(Time),Plan.CameraAt(Time,FWidth/FHeight),FWidth/FHeight);
  Result.X:=Result.X*FWidth;
  Result.Y:=Result.Y*FHeight;
end;

procedure TOrbitCourse.Prepare(Plan:TOrbitPlan;Width,Height:Double);
type
  TSlot=record
    Center:TOrbitPoint;
    LastHit:Double;
  end;
var
  Slots:TArray<TSlot>;
  First,I,J,Col,Row,Cols,Rows,Count,Best:Integer;
  Tap:TOrbitTap;
  Cue,Prior,Next:TCue;
  ShortSide,Padding,Spacing,Oldest,AvailableAt,Goal,DX,DY,Distance,Score,BestScore:Double;
  PrevGap,NextGap,Handle,Speed:Double;
  Origin,Previous,Direction:TOrbitPoint;
begin
  FWidth:=Width;
  FHeight:=Height;
  First:=OrbitOpeningTapCount(Plan);
  SetLength(FCues,Plan.Count-First);
  SetLength(FTapCue,Plan.Count);
  if First=Plan.Count then Exit;

  ShortSide:=Min(Width,Height);
  FHitRadius:=OrbitHitRadius(ShortSide);
  Padding:=OrbitMarkExtent(FHitRadius,StartApproach)+0.026*ShortSide;
  Spacing:=2*OrbitMarkExtent(FHitRadius,StartApproach)+ORBIT_MARKER_GAP+0.022*ShortSide;
  Cols:=1+Floor(Max(0.0,Min(Width-2*Padding,1.62*ShortSide))/Spacing);
  Rows:=1+Floor(Max(0.0,Min(Height-2*Padding,1.62*ShortSide))/Spacing);
  SetLength(Slots,Cols*Rows);
  for Row:=0 to Rows-1 do
    for Col:=0 to Cols-1 do begin
      I:=Row*Cols+Col;
      // 格子をわずかに崩しつつ、最大の外周同士にも余白を取る。
      Slots[I].Center:=OrbitPoint(Width*0.5+(Col-(Cols-1)*0.5)*Spacing+0.007*ShortSide*Sin(I*2.39996),
        Height*0.5+(Row-(Rows-1)*0.5)*Spacing+0.007*ShortSide*Cos(I*2.39996));
      Slots[I].LastHit:=-MaxDouble;
    end;

  FEntryTime:=Plan.Taps[First].Time-ORBIT_MARKER_LEAD;
  FExitTime:=Plan.Taps[Plan.Count-1].Time+0.65;
  FEntry:=BackdropPoint(Plan,FEntryTime);
  FExit:=BackdropPoint(Plan,FExitTime);
  Origin:=BackdropPoint(Plan,Plan.Taps[First].Time);
  Direction:=OrbitPoint(0,0);
  Count:=0;
  for I:=First to Plan.Count-1 do begin
    Tap:=Plan.Taps[I];
    if (Count>0) and (Tap.Time=FCues[Count-1].Time) then begin
      Inc(FCues[Count-1].TapCount);
      FCues[Count-1].TapIndex:=I;
      FTapCue[I]:=Count-1;
      Continue;
    end;

    Cue:=Default(TCue);
    Cue.Time:=Tap.Time;
    Cue.TapIndex:=I;
    Cue.TapCount:=1;
    Cue.Pace:=TapPace(Plan,I,First,Tap.Time);
    AvailableAt:=Tap.Time-ORBIT_MARKER_LEAD;
    Oldest:=Tap.Time;
    for J:=0 to High(Slots) do Oldest:=Min(Oldest,Slots[J].LastHit);
    // 画面を埋め切る密度では、先に判定が終わる場所から再利用する。
    AvailableAt:=Max(AvailableAt,Oldest);
    Goal:=Spacing*(1.10+0.55*Cue.Pace);
    Best:=0;
    BestScore:=MaxDouble;
    for J:=0 to High(Slots) do begin
      if Slots[J].LastHit>AvailableAt then Continue;
      DX:=Slots[J].Center.X-Origin.X;
      DY:=Slots[J].Center.Y-Origin.Y;
      Distance:=Hypot(DX,DY);
      Score:=Distance;
      if Count>0 then
        Score:=Abs(Distance-Goal)-0.36*Spacing*(DX*Direction.X+DY*Direction.Y)/Max(1.0,Distance);
      if Score<BestScore then begin
        Best:=J;
        BestScore:=Score;
      end;
    end;

    Previous:=Origin;
    Cue.Center:=Slots[Best].Center;
    Cue.ShowAt:=Max(Tap.Time-ORBIT_MARKER_LEAD,Slots[Best].LastHit);
    Slots[Best].LastHit:=Tap.Time;
    Origin:=Cue.Center;
    DX:=Origin.X-Previous.X;
    DY:=Origin.Y-Previous.Y;
    Distance:=Max(1.0,Hypot(DX,DY));
    Direction:=OrbitPoint(DX/Distance,DY/Distance);
    FTapCue[I]:=Count;
    FCues[Count]:=Cue;
    Inc(Count);
  end;
  SetLength(FCues,Count);

  Prior.Time:=FEntryTime;
  Prior.Center:=FEntry;
  for I:=0 to High(FCues) do begin
    Cue:=FCues[I];
    if I<High(FCues) then Next:=FCues[I+1]
    else begin Next.Time:=FExitTime;Next.Center:=FExit;end;
    PrevGap:=Cue.Time-Prior.Time;
    NextGap:=Next.Time-Cue.Time;
    DX:=Next.Center.X-Prior.Center.X;
    DY:=Next.Center.Y-Prior.Center.Y;
    // 前後の区間で同じ接線速度を使い、急な折り返しや外へのはみ出しを抑える。
    Handle:=Min(0.12*ShortSide,0.78*Min(Hypot(Cue.Center.X-Prior.Center.X,Cue.Center.Y-Prior.Center.Y),
      Hypot(Next.Center.X-Cue.Center.X,Next.Center.Y-Cue.Center.Y)));
    Speed:=Handle/Max(PrevGap,NextGap);
    Distance:=Max(1.0,Hypot(DX,DY));
    FCues[I].Velocity:=OrbitPoint(DX/Distance*Speed,DY/Distance*Speed);
    Prior:=Cue;
  end;
end;

function TOrbitCourse.NextCue(Time:Double):Integer;
var L,R,M:Integer;
begin
  L:=0;
  R:=Length(FCues);
  while L<R do begin
    M:=L+(R-L) div 2;
    if FCues[M].Time<=Time then L:=M+1 else R:=M;
  end;
  Result:=L;
end;

function TOrbitCourse.Center(TapIndex:Integer):TOrbitPoint;
begin
  Result:=FCues[FTapCue[TapIndex]].Center;
end;

function TOrbitCourse.CursorAt(Plan:TOrbitPlan;Time:Double):TOrbitPoint;
var I:Integer;A,B:TCue;U,V,Gap,InWeight,OutWeight:Double;
begin
  if (Length(FCues)=0) or (Time<=FEntryTime) or (Time>=FExitTime) then
    Exit(BackdropPoint(Plan,Time));
  I:=NextCue(Time);
  if I=0 then begin
    A:=Default(TCue);
    A.Time:=FEntryTime;
    A.Center:=FEntry;
  end else A:=FCues[I-1];
  if Time=A.Time then Exit(A.Center);
  if I=Length(FCues) then begin
    B:=Default(TCue);
    B.Time:=FExitTime;
    B.Center:=FExit;
  end else B:=FCues[I];
  Gap:=B.Time-A.Time;
  U:=(Time-A.Time)/Gap;
  V:=1-U;
  InWeight:=U*V*V*Gap;
  OutWeight:=-U*U*V*Gap;
  U:=Smooth(U);
  Result:=OrbitPoint(A.Center.X+(B.Center.X-A.Center.X)*U+A.Velocity.X*InWeight+B.Velocity.X*OutWeight,
    A.Center.Y+(B.Center.Y-A.Center.Y)*U+A.Velocity.Y*InWeight+B.Velocity.Y*OutWeight);
end;

function TOrbitCourse.Route(Plan:TOrbitPlan;Start,Finish:Double;out Points:TOrbitRoute):Integer;
var I,J,Last,Legs,SamplesPerLeg:Integer;At,NextTime,SampleTime:Double;
begin
  Points[0].Time:=Start;
  Points[0].P:=CursorAt(Plan,Start);
  Result:=0;
  if Finish<=Start then Exit;
  At:=Start;
  I:=NextCue(Start);
  Last:=NextCue(Finish);
  Legs:=Last-I;
  if (Last=0) or (FCues[Last-1].Time<Finish) then Inc(Legs);
  if (Start<FExitTime) and (FExitTime<Finish) then Inc(Legs);
  Legs:=Min(ORBIT_GUIDE_STEPS div 5,Legs);
  SamplesPerLeg:=Min(8,ORBIT_GUIDE_STEPS div Legs);
  while (At<Finish) and (Result<ORBIT_GUIDE_STEPS) do begin
    NextTime:=Finish;
    if I<Length(FCues) then NextTime:=Min(NextTime,FCues[I].Time)
    else if At<FExitTime then NextTime:=Min(NextTime,FExitTime);
    for J:=1 to SamplesPerLeg do begin
      if J=SamplesPerLeg then SampleTime:=NextTime else SampleTime:=At+(NextTime-At)*J/SamplesPerLeg;
      Inc(Result);
      Points[Result].Time:=SampleTime;
      Points[Result].P:=CursorAt(Plan,SampleTime);
    end;
    At:=NextTime;
    Inc(I);
    Dec(Legs);
    if Legs=0 then Break;
  end;
end;

function TOrbitCourse.Visible(const State:TOrbitVisualState;Time:Double;out Markers:TOrbitMarkers):Integer;
var I:Integer;Cue:TCue;Mark:TOrbitMarker;Lead,Age,Duration,Growth,PreviewRadius:Double;
begin
  Result:=0;
  if State.PreviewAlpha<=0 then Exit;
  for I:=NextCue(Time) to High(FCues) do begin
    Cue:=FCues[I];
    Lead:=Cue.Time-Time;
    if Lead>ORBIT_MARKER_LEAD then Break;
    if Time<=Cue.ShowAt then Continue;
    Age:=Time-Cue.ShowAt;
    Duration:=Cue.Time-Cue.ShowAt;
    Mark.TapIndex:=Cue.TapIndex;
    Mark.TapCount:=Cue.TapCount;
    Mark.Center:=Cue.Center;
    Mark.Visibility:=EaseOut(Age/Min(0.10,Duration*0.4))*State.PreviewAlpha;
    Mark.Opacity:=0.58+0.42*OrbitMarkerOpacity(Lead,ORBIT_MARKER_LEAD);
    Growth:=EaseOut(Age/Min(0.48-0.30*Cue.Pace,Duration*0.50));
    PreviewRadius:=FHitRadius*(0.74+0.15*Cue.Pace);
    if I=0 then PreviewRadius:=FHitRadius;
    Mark.Radius:=FHitRadius*0.55+(PreviewRadius-FHitRadius*0.55)*Growth+
      (FHitRadius-PreviewRadius)*Smooth(1-Lead/0.42);
    Mark.Approach:=StartApproach+(1-StartApproach)*Smooth(1-Lead/ORBIT_MARKER_LEAD);
    Mark.Extent:=OrbitMarkExtent(Mark.Radius,Mark.Approach);
    Markers[Result]:=Mark;
    Inc(Result);
  end;
end;
end.
