program OrbitPresentationSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Hash,System.IOUtils,System.Classes,System.JSON,System.Diagnostics,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmPlanRef,RhythmStyles,RhythmSettings,RhythmProduct,
  RhythmScene,RhythmOrbitPlan,RhythmOrbitTypes,RhythmOrbitMarks,RhythmOrbitGuide,
  RhythmEqualizer,RhythmRenderSurface,RhythmImageBank,RhythmOverlay;
var A,Meta:TRhythmAudio;Plan:TOrbitPlan;Ref:TRhythmPlanRef;Render:TRhythmRenderer;Surface:TAnimationRenderSurface;
  Image:TBitmap;PNG:TPngImage;Folder,Source,Revision,First,OnHash,OffHash:string;Stamp:TWin32FileAttributeData;
  Saved,Loaded:TRhythmSettings;Style:TRhythmStyle;B,I,J,K,Mode,Checks,Frames,Count:Integer;
  Tap:TOrbitTap;Activity:TEqualizerActivity;Times:array[0..8] of Double=(0.03,0.4,1.8,3,3.1,6,7.8,8.6,19.5);
  Samples:array[0..2,0..24] of TColor;
  WideCore:array[0..2] of TColor;
procedure Need(V:Boolean;const S:string);
begin if not V then raise Exception.Create(S);Inc(Checks);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;
  try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;
  finally M.Free;end;
end;
procedure Snapshot(const Name:string);
begin PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));finally FreeAndNil(PNG);end;Inc(Frames);end;
procedure MeasureFrames;
const FrameCount=20;
var Backend,Frame:Integer;Watch:TStopwatch;Total,Slowest,Elapsed:Double;
begin
  Image.SetSize(960,540);
  Render.ConfigureStyle(rsRhythmGame,Ref,100,0);
  for Backend:=0 to 1 do begin
    Render.UseD2D:=Backend=1;
    Render.Render(Image,Meta,5.9,0);
    Total:=0;Slowest:=0;
    for Frame:=0 to FrameCount-1 do begin
      Watch:=TStopwatch.StartNew;
      Render.Render(Image,Meta,6+Frame/60,0);
      GdiFlush;
      Watch.Stop;
      Elapsed:=Watch.Elapsed.TotalMilliseconds;
      Total:=Total+Elapsed;Slowest:=Max(Slowest,Elapsed);
    end;
    Need(Render.LastUsedD2D=(Backend=1),'Wrong benchmark backend');
    WriteLn('Type.V 960x540 backend=',Backend,' meanMs=',Total/FrameCount:0:3,' maxMs=',Slowest:0:3);
    Flush(Output);
  end;
end;
procedure CheckMarkers(const Markers:TOrbitMarkers;Count:Integer;Time,MinGap:Double);
var I,J:Integer;Gap,Distance:Double;
begin
  for I:=0 to Count-1 do
    for J:=0 to I-1 do begin
      Gap:=Markers[I].Extent+Markers[J].Extent+MinGap;
      Distance:=Hypot(Markers[I].Center.X-Markers[J].Center.X,Markers[I].Center.Y-Markers[J].Center.Y);
      if Distance<Gap-1E-9 then
        Need(False,Format('Marker outlines overlap at %.4f s, taps %d and %d',
          [Time,Markers[J].TapIndex,Markers[I].TapIndex]));
      Inc(Checks);
    end;
end;

procedure CheckMarkerLayout;
const Widths:array[0..5] of Integer=(960,540,320,720,1920,576);
  Heights:array[0..5] of Integer=(540,960,180,720,1080,324);
var State:TOrbitVisualState;Course:TOrbitCourse;Camera:TOrbitView;Markers,LastMarkers:TOrbitMarkers;
  Point,Ship,Projected:TOrbitPoint;Route:TOrbitRoute;
  Previous,Current:TArray<Integer>;Entered:TArray<Boolean>;
  View,Frame,Count,I,J,Index,LastIndex,MaxMarkers,Accepted,Segments:Integer;
  Time,W,H,FullExtent,LeadStart,Extent,StepX,PreviousStepX:Double;Found:Boolean;
begin
  Need(OrbitGameplayStart(Plan)=3,'Opening length');
  Course.Prepare(Plan,960,540);
  LeadStart:=3-ORBIT_MARKER_LEAD;
  State:=OrbitVisualState(Plan,LeadStart-0.05);
  Need(not State.Playing and (State.Horizon=0) and (State.Pulse=0) and
    (Course.Visible(State,LeadStart-0.05,Markers)=0),'Opening leaked a cue too early');
  State:=OrbitVisualState(Plan,LeadStart+0.10);
  Need((State.PreviewAlpha>0) and (State.PreviewAlpha<1) and not State.Playing,'Preview did not fade in before gameplay');
  State:=OrbitVisualState(Plan,LeadStart+0.35);
  Need((State.PreviewAlpha>=0.99) and not State.Playing,'The guide did not finish fading in during the lead-in');
  State:=OrbitVisualState(Plan,2.5);
  Count:=Course.Visible(State,2.5,Markers);
  Need((Count>0) and (Markers[0].TapIndex=75) and (Markers[0].Radius>=0.99*Course.HitRadiusAt(3)) and
    not State.Playing and (State.LastHit=74) and (State.Pulse=0),
    'First target was not visible before gameplay');
  State:=OrbitVisualState(Plan,3);
  Need(State.Playing and (State.FirstTap=75) and (State.LastHit=75),'First hit did not start at its original time');
  SetLength(Previous,Plan.Count);
  SetLength(Current,Plan.Count);
  SetLength(Entered,Plan.Count);
  for View:=Low(Widths) to High(Widths) do begin
    W:=Widths[View];H:=Heights[View];
    Course.Prepare(Plan,W,H);
    PreviousStepX:=0;
    for I:=1 to Course.BodyCount-1 do begin
      StepX:=Course.Body(I).Center.X-Course.Body(I-1).Center.X;
      Need(StepX*PreviousStepX<=0,'Consecutive transfers headed to the same side of the screen');
      PreviousStepX:=StepX;
    end;
    MaxMarkers:=0;
    for I:=0 to Plan.Count-1 do begin Previous[I]:=-1;Entered[I]:=False;end;
    for Frame:=0 to Ceil((Plan.SoundEnd-LeadStart)*60)+1 do begin
      Time:=LeadStart+Frame/60;
      State:=OrbitVisualState(Plan,Time);
      Count:=Course.Visible(State,Time,Markers);
      MaxMarkers:=Max(MaxMarkers,Count);Ship:=Course.CursorAt(Time);Camera:=Course.ViewAt(Time);
      for I:=0 to Plan.Count-1 do Current[I]:=-1;
      for I:=0 to Count-1 do begin
        Index:=Markers[I].TapIndex;
        Current[Index]:=I;
        Need(Plan.Taps[Index].Time-Time<=State.Horizon+1E-9,'Preview marker exceeded the future guide');
        Need(Markers[I].Radius*Camera.Scale>=OrbitMinimumMarkRadius(Min(W,H))-1E-9,'Preview marker fell below its readable size');
        Point:=Course.CursorAt(Plan.Taps[Index].Time);
        Need((Markers[I].Center.X=Point.X) and (Markers[I].Center.Y=Point.Y),
          'Cursor missed the fixed marker at its hit');
        Projected:=Camera.Project(Point);
        Extent:=OrbitMarkExtent(Markers[I].Radius*Camera.Scale,Markers[I].Approach);
        Need((Projected.X>=Extent-1E-9) and (Projected.X+Extent<=W+1E-9) and
          (Projected.Y>=Extent-1E-9) and (Projected.Y+Extent<=H+1E-9),'Marker was clipped');
        FullExtent:=OrbitMarkExtent(Course.HitRadiusAt(Plan.Taps[Index].Time),0.65)+OrbitCursorExtent(Min(W,H));
        if Hypot(Point.X-Ship.X,Point.Y-Ship.Y)<=FullExtent then Entered[Index]:=True
        else Need(not Entered[Index],'Ship passed over a visible target and left before its hit');
        LastIndex:=Previous[Index];
        if LastIndex>=0 then begin
          Need((Point.X=LastMarkers[LastIndex].Center.X) and (Point.Y=LastMarkers[LastIndex].Center.Y),
            'Visible marker moved in the world');
          Need((Markers[I].Radius>=LastMarkers[LastIndex].Radius) and
            (Markers[I].Visibility>=LastMarkers[LastIndex].Visibility),'Visible marker shrank or faded before contact');
        end;
        Inc(Checks);
      end;
      if Count>0 then begin
        Segments:=Course.Route(Plan,Time,Plan.Taps[Markers[Count-1].TapIndex].Time,Markers,Count,Route);
        for I:=0 to Segments do begin
          Projected:=Camera.Project(Route[I].P);
          Need((Projected.X>=-0.5) and (Projected.X<=W+0.5) and (Projected.Y>=-0.5) and (Projected.Y<=H+0.5),
            'A visible target was beyond an offscreen part of the route');
        end;
      end;
      for I:=State.LastHit+1 to Plan.Count-1 do
        if Previous[I]>=0 then Need(Current[I]>=0,'Visible marker disappeared before contact');
      for I:=0 to Plan.Count-1 do Previous[I]:=Current[I];
      LastMarkers:=Markers;
      CheckMarkers(Markers,Count,Time,OrbitMarkerGap(Min(W,H))/ORBIT_WIDE_SCALE);
    end;
    Accepted:=Course.HitCount(Plan.SoundEnd);
    Need((Accepted>10) and (Accepted<Plan.Count-OrbitOpeningTapCount(Plan)),
      '40 ms fixture did not exercise readable cue selection');
    for I:=OrbitOpeningTapCount(Plan) to Plan.Count-1 do begin
      if Course.HitIndex(Plan.Taps[I].Time)<>I then Continue;
      Time:=Plan.Taps[I].Time-ORBIT_MIN_MARKER_LEAD+1E-9;
      Count:=Course.Visible(OrbitVisualState(Plan,Time),Time,Markers);
      Found:=False;
      for J:=0 to Count-1 do if Markers[J].TapIndex=I then Found:=True;
      Need(Found,'An accepted marker appeared without its minimum lead');
    end;
    WriteLn('Type.V view ',View,' accepted targets=',Accepted,' peak visible targets=',MaxMarkers);
  end;
end;

procedure CheckCrossingPreviews;
const Widths:array[0..3] of Integer=(960,540,720,1280);
  Heights:array[0..3] of Integer=(540,960,720,540);
type TTransfer=record Start,Finish:Double;Leg:Integer;end;
var Course:TOrbitCourse;Transfers:TArray<TTransfer>;BeforeMarks,AfterMarks:TOrbitMarkers;
  L:TOrbitLeg;I,J,K,M,View,Frame,LegIndex,BeforeCount,AfterCount,Revealed,Groups,EntryRevealed,ArcRevealed,AfterLeg,MarkLeg:Integer;
  Time,Early,Later,ClearAt,MarkTime,Radius:Double;
  function CrossingTimes(const A,B:TTransfer;out Early,Later:Double):Boolean;
  var P,Q,R,S:TOrbitPoint;DX,DY,EX,EY,Den,U,V:Double;
  begin
    P:=Course.CursorAt(A.Start);Q:=Course.CursorAt(A.Finish);
    R:=Course.CursorAt(B.Start);S:=Course.CursorAt(B.Finish);
    DX:=Q.X-P.X;DY:=Q.Y-P.Y;EX:=S.X-R.X;EY:=S.Y-R.Y;
    Den:=DX*EY-DY*EX;
    if Abs(Den)<1E-8 then Exit(False);
    U:=((R.X-P.X)*EY-(R.Y-P.Y)*EX)/Den;
    V:=((R.X-P.X)*DY-(R.Y-P.Y)*DX)/Den;
    Early:=A.Start+(A.Finish-A.Start)*U;
    Later:=B.Start+(B.Finish-B.Start)*V;
    Result:=(U>0) and (U<1) and (V>0) and (V<1);
  end;
begin
  Groups:=0;EntryRevealed:=0;ArcRevealed:=0;
  for View:=Low(Widths) to High(Widths) do begin
    Course.Prepare(Plan,Widths[View],Heights[View]);
    Transfers:=nil;
    SetLength(Transfers,Course.BodyCount);
    for Frame:=1 to Floor(Plan.SoundEnd*200) do begin
      Time:=Frame/200;
      LegIndex:=Course.LegAt(Time);
      L:=Course.Leg(LegIndex);
      if L.Kind<>1 then Continue;
      if Transfers[L.FromBody].Start=0 then begin
        Transfers[L.FromBody].Start:=Time;
        Transfers[L.FromBody].Leg:=LegIndex;
      end;
      Transfers[L.FromBody].Finish:=Time;
    end;

    Radius:=OrbitMinimumMarkRadius(Min(Widths[View],Heights[View]))/ORBIT_WIDE_SCALE;
    for I:=1 to Course.BodyCount-2 do for M:=0 to I-1 do begin
      if (Transfers[M].Start=0) or (Transfers[I].Start=0) then Continue;
      if not CrossingTimes(Transfers[M],Transfers[I],Early,Later) then Continue;
      if (Early<=3.01) or (Later<=Early) or (Later-Early>=ORBIT_MARKER_LEAD) then Continue;
      AfterLeg:=Transfers[I].Leg;
      ClearAt:=Early+Min(Radius/Course.Speed,(Transfers[I].Start-Early)*0.5);
      BeforeCount:=Course.Visible(OrbitVisualState(Plan,Early-0.01),Early-0.01,BeforeMarks);
      AfterCount:=Course.Visible(OrbitVisualState(Plan,ClearAt+0.002),ClearAt+0.002,AfterMarks);
      Revealed:=0;
      for J:=0 to AfterCount-1 do begin
        MarkTime:=Plan.Taps[AfterMarks[J].TapIndex].Time;
        if MarkTime-Early+0.01>=ORBIT_MARKER_LEAD then Continue;
        MarkLeg:=Course.LegAt(MarkTime);
        if MarkLeg=AfterLeg then begin
          if Abs(MarkTime-Later)<Radius/Course.Speed then Continue;
          if MarkTime<Later then Inc(EntryRevealed) else Inc(Revealed);
        end else if (MarkLeg=AfterLeg+1) and (Course.Leg(MarkLeg).Kind=0) then Inc(ArcRevealed)
        else Continue;
        for K:=0 to BeforeCount-1 do
          Need(BeforeMarks[K].TapIndex<>AfterMarks[J].TapIndex,
            'A marker on the later branch appeared before the first crossing pass');
      end;
      if Revealed>=2 then Inc(Groups);
    end;
  end;
  WriteLn('Type.V crossing groups revealed=',Groups,' entrance=',EntryRevealed,' following arc=',ArcRevealed);
  Need(Groups>0,'No crossing revealed a group of markers beyond the junction');
  Need(EntryRevealed>0,'The fixture missed the branch entrance');
end;

procedure CheckShortPreviews;
var Audio:TRhythmAudio;ShortPlan:TOrbitPlan;State:TOrbitVisualState;Course:TOrbitCourse;
  Markers:TOrbitMarkers;I,Count:Integer;Time:Double;A,B:TOrbitPoint;
begin
  Audio:=TRhythmAudio.Create;ShortPlan:=nil;
  try
    Audio.Duration:=7.5;Audio.SoundEnd:=7.5;
    SetLength(Audio.Hits,7000);
    for I:=0 to High(Audio.Hits) do begin
      Audio.Hits[I].Time:=I*0.001;Audio.Hits[I].Strength:=0.5;
    end;
    ShortPlan:=TOrbitPlan.Build(Audio,20);
    Course.Prepare(ShortPlan,960,540);
    Need((Course.HitCount(ShortPlan.SoundEnd)>5) and (Course.HitCount(ShortPlan.SoundEnd)<ShortPlan.Count div 10),
      'Millisecond chart did not select a readable set of marks');
    for I:=3001 to 6999 do begin
      Time:=ShortPlan.Taps[I].Time-0.0005;
      State:=OrbitVisualState(ShortPlan,Time);
      Count:=Course.Visible(State,Time,Markers);
      CheckMarkers(Markers,Count,Time,OrbitMarkerGap(540));
    end;
    FreeAndNil(ShortPlan);
    // 連打に頼らない短曲でも、最初の惑星から画面外の次の空域へ渡る。
    SetLength(Audio.Hits,20);
    for I:=0 to High(Audio.Hits) do begin
      Audio.Hits[I].Time:=I*0.37;Audio.Hits[I].Strength:=0.8;
    end;
    ShortPlan:=TOrbitPlan.Build(Audio,20);
    Need(ShortPlan.BodyCount=1,'Short fixture already had a planet transfer');
    Course.Prepare(ShortPlan,960,540);
    Need(Course.BodyCount=2,'Short song stayed at one planet');
    A:=Course.Body(0).Center;B:=Course.Body(1).Center;
    Need((Abs(B.X-A.X)>=0.60*960) or (Abs(B.Y-A.Y)>=0.60*540),'Short song did not travel to the next screen');
    Course.Prepare(ShortPlan,540,960);
    A:=Course.Body(0).Center;B:=Course.Body(1).Center;
    Need((Abs(B.X-A.X)>=0.60*540) or (Abs(B.Y-A.Y)>=0.60*960),'Portrait short song did not travel to the next screen');
    FreeAndNil(ShortPlan);
    SetLength(Audio.Hits,1);
    Audio.Hits[0].Time:=Audio.SoundEnd;
    ShortPlan:=TOrbitPlan.Build(Audio,20);
    Course.Prepare(ShortPlan,960,540);
    Need(Course.Visible(OrbitVisualState(ShortPlan,7.4),7.4,Markers)=1,'Final note was never previewed');
  finally
    ShortPlan.Free;Audio.Free;
  end;
end;
procedure CheckUniformTravel;
const Gaps:array[0..2] of Double=(0.04,0.11,0.23);
var Audio:TRhythmAudio;Mixed:TOrbitPlan;Course:TOrbitCourse;Leg:TOrbitLeg;Planet,NextPlanet:TOrbitBody;
  LastPoint,Point,Other,Before,After,Projected,LastProjected,Step,PreviousStep:TOrbitPoint;Camera:TOrbitView;
  Time,Gap,Start,Distance,Ratio,MinRatio,Sweep,PreviousTime,MinZoom,Boundary,TransferStart,SideY:Double;
  I,J,K,LegIndex,PreviousLeg,Visits,Transfers,Diagonals,Offscreen,ForwardSteps:Integer;
  Left,Right,Vertical:Boolean;
  procedure CheckPlanetClearance(Index:Integer);
  var Body:TOrbitBody;
  begin
    Body:=Course.Body(Index);
    Need(Hypot(Point.X-Body.Center.X,Point.Y-Body.Center.Y)>Body.Radius*1.67,'Ship entered a planet halo');
  end;
  function CheckTangent(LowTime,HighTime:Double;OldLeg:Integer):Double;
  const Dt=1E-5;
  var Step:Integer;Boundary:Double;A,B,C,D:TOrbitPoint;BeforeView,AfterView:TOrbitView;
  begin
    for Step:=1 to 32 do begin
      Boundary:=(LowTime+HighTime)*0.5;
      if Course.LegAt(Boundary)=OldLeg then LowTime:=Boundary else HighTime:=Boundary;
    end;
    Boundary:=(LowTime+HighTime)*0.5;
    A:=Course.CursorAt(Boundary-2*Dt);B:=Course.CursorAt(Boundary-Dt);
    C:=Course.CursorAt(Boundary+Dt);D:=Course.CursorAt(Boundary+2*Dt);
    Need(Hypot((B.X-A.X)-(D.X-C.X),(B.Y-A.Y)-(D.Y-C.Y))<Course.Speed*Dt*0.002,
      'Straight connector and orbit did not share a tangent');
    BeforeView:=Course.ViewAt(Boundary-Dt);
    AfterView:=Course.ViewAt(Boundary+Dt);
    Need(Hypot(AfterView.Center.X-BeforeView.Center.X,AfterView.Center.Y-BeforeView.Center.Y)<=Course.Speed*Dt*2,
      'Camera jumped at the tangent point');
    Need(Abs(BeforeView.Scale-AfterView.Scale)<0.0001,'Zoom jumped at the tangent point');
    Result:=Boundary;
  end;
  procedure CheckTransferMidpoint(TransferLeg:Integer;Start,Finish:Double);
  var A,B:TOrbitPoint;View:TOrbitView;Transfer:TOrbitLeg;
  begin
    Transfer:=Course.Leg(TransferLeg);
    A:=Course.Body(Transfer.FromBody).Center;B:=Course.Body(Transfer.ToBody).Center;
    View:=Course.ViewAt((Start+Finish)*0.5);
    Need(Hypot(View.Center.X-(A.X+B.X)*0.5,View.Center.Y-(A.Y+B.Y)*0.5)<1E-6,
      'Transfer midpoint was not centered between the planets');
    Need(Abs(View.Scale-ORBIT_WIDE_SCALE)<1E-9,'The widest framing was not at the midpoint');
  end;
begin
  Audio:=TRhythmAudio.Create;Mixed:=nil;
  try
    Audio.Duration:=40;Audio.SoundEnd:=40;
    SetLength(Audio.Hits,275);
    Time:=0;
    for I:=0 to High(Audio.Hits) do begin
      Audio.Hits[I].Time:=Time;Audio.Hits[I].Strength:=0.8;
      Time:=Time+Gaps[I mod Length(Gaps)];
      if I=95 then Time:=Time+3;
    end;
    SetLength(Audio.Hits,Length(Audio.Hits)+1);
    Audio.Hits[High(Audio.Hits)].Time:=Audio.SoundEnd;
    Audio.Hits[High(Audio.Hits)].Strength:=0.8;
    Mixed:=TOrbitPlan.Build(Audio,20);
    Course.Prepare(Mixed,960,540);
    Visits:=0;Transfers:=0;Diagonals:=0;Offscreen:=0;ForwardSteps:=0;
    PreviousLeg:=-1;MinRatio:=1;MinZoom:=1;Sweep:=0;PreviousTime:=0;TransferStart:=-1;
    Need(Course.BodyCount>=14,'The fixture did not cover the old twelve-step cycle');
    Left:=False;Right:=False;Vertical:=False;
    Before:=Course.Body(0).Center;After:=Course.Body(Course.BodyCount-1).Center;
    SideY:=Sign(After.Y-Before.Y);
    PreviousStep:=OrbitPoint(0,0);
    for I:=1 to Course.BodyCount-1 do begin
      Before:=Course.Body(I-1).Center;After:=Course.Body(I).Center;
      Step:=OrbitPoint(After.X-Before.X,After.Y-Before.Y);
      Need(SideY*Step.Y>=0.26*540,'A transfer doubled back into an earlier region');
      Need(Step.X*PreviousStep.X+Step.Y*PreviousStep.Y<=
        Cos(Pi/10)*Hypot(Step.X,Step.Y)*Hypot(PreviousStep.X,PreviousStep.Y)+1E-6,
        'Consecutive transfers had almost the same heading');
      Need(Step.X*PreviousStep.X<=0,'Consecutive transfers headed to the same side of the screen');
      PreviousStep:=Step;
      Left:=Left or (Step.X< -0.17*960);
      Right:=Right or (Step.X>0.17*960);
      Vertical:=Vertical or ((Abs(Step.X)<0.12*960) and (Abs(Step.Y)>0.60*540));
    end;
    Need(Left and Right and Vertical,'The journey missed leftward, rightward, or vertical transfers');
    Before:=Course.Body(1).Center;After:=Course.Body(13).Center;Other:=Course.Body(12).Center;
    Need(Hypot(Before.X-Course.Body(0).Center.X-(After.X-Other.X),
      Before.Y-Course.Body(0).Center.Y-(After.Y-Other.Y))>1,'The old twelve-step cycle repeated');
    for I:=1 to Mixed.Count-1 do begin
      Start:=Mixed.Taps[I-1].Time;
      Gap:=Mixed.Taps[I].Time-Start;
      LastPoint:=Course.CursorAt(Start);
      Distance:=0;
      for J:=1 to 160 do begin
        Time:=Start+Gap*J/160;
        Point:=Course.CursorAt(Time);
        Distance:=Distance+Hypot(Point.X-LastPoint.X,Point.Y-LastPoint.Y);
        LegIndex:=Course.LegAt(Time);
        Leg:=Course.Leg(LegIndex);
        Planet:=Course.Body(Leg.FromBody);
        Camera:=Course.ViewAt(Time);
        Projected:=Camera.Project(Point);
        Need((Projected.X>=0) and (Projected.X<=960) and (Projected.Y>=0) and (Projected.Y<=540),
          'Ship left the viewport');
        if Leg.Kind=1 then begin
          Other:=Course.Body(Leg.ToBody).Center;
          Need((Camera.Scale>=ORBIT_WIDE_SCALE-1E-9) and (Camera.Scale<=1),'Transfer zoom outside the viewing range');
          MinZoom:=Min(MinZoom,Camera.Scale);
          if PreviousLeg=LegIndex then begin
            Need((Projected.X-LastProjected.X)*(Other.X-Planet.Center.X)+
              (Projected.Y-LastProjected.Y)*(Other.Y-Planet.Center.Y)>0,'The ship reversed on a straight transfer');
            Inc(ForwardSteps);
          end;
        end else if (Leg.Kind=0) and (Camera.Scale=1) then begin
          Need((Camera.Center.X=Planet.Center.X) and (Camera.Center.Y=Planet.Center.Y),'Orbit camera drifted from its planet');
          if Leg.FromBody+1<Course.BodyCount then begin
            NextPlanet:=Course.Body(Leg.FromBody+1);
            Other:=Camera.Project(NextPlanet.Center);
            Need((Other.X+NextPlanet.Radius<0) or (Other.X-NextPlanet.Radius>960) or
              (Other.Y+NextPlanet.Radius<0) or (Other.Y-NextPlanet.Radius>540),'Next planet was already inside the orbit view');
            Inc(Offscreen);
          end;
        end;
        for K:=Max(0,Leg.FromBody-1) to Min(Course.BodyCount-1,Leg.FromBody+1) do CheckPlanetClearance(K);
        if LegIndex<>PreviousLeg then begin
          if (PreviousLeg>=0) and (LegIndex=PreviousLeg+1) then begin
            Boundary:=CheckTangent(PreviousTime,Time,PreviousLeg);
            if Leg.Kind=1 then TransferStart:=Boundary
            else if (Course.Leg(PreviousLeg).Kind=1) and (TransferStart>=0) then begin
              CheckTransferMidpoint(PreviousLeg,TransferStart,Boundary);
              TransferStart:=-1;
            end;
          end;
          Need(Sweep<2*Pi,'Ship made a full lap before leaving a planet');
          Sweep:=0;
          if Leg.Kind=0 then Inc(Visits);
          if Leg.Kind=1 then begin
            Inc(Transfers);
            Other:=Course.Body(Leg.ToBody).Center;
            Need(Hypot(Other.X-Planet.Center.X,Other.Y-Planet.Center.Y)>180,'Two planets shared a screen position');
            if (Abs(Other.X-Planet.Center.X)>30) and (Abs(Other.Y-Planet.Center.Y)>30) then Inc(Diagonals);
          end;
          PreviousLeg:=LegIndex;
        end else if Leg.Kind=0 then begin
          Before:=OrbitPoint(LastPoint.X-Planet.Center.X,LastPoint.Y-Planet.Center.Y);
          After:=OrbitPoint(Point.X-Planet.Center.X,Point.Y-Planet.Center.Y);
          Sweep:=Sweep+Abs(ArcTan2(Before.X*After.Y-Before.Y*After.X,Before.X*After.X+Before.Y*After.Y));
        end;
        LastPoint:=Point;LastProjected:=Projected;PreviousTime:=Time;
      end;
      Ratio:=Distance/(Course.Speed*Gap);
      MinRatio:=Min(MinRatio,Ratio);
      Need((Ratio>=0.995) and (Ratio<=1.000001),'Cursor speed changed with the audio gap');
      Inc(Checks);
    end;
    Need(Sweep<2*Pi,'Final orbit contained a full lap');
    Need((Visits>=3) and (Transfers=Visits-1),Format('Incomplete planetary journey (%d visits, %d transfers)',[Visits,Transfers]));
    Need((Diagonals>=6) and (MinZoom<0.85) and (Offscreen>0) and (ForwardSteps>0),'The fixture missed offscreen travel');
    WriteLn('Type.V visits=',Visits,' transfers=',Transfers,' diagonals=',Diagonals,' minimum travel ratio=',MinRatio:0:6);
  finally
    Mixed.Free;Audio.Free;
  end;
end;

procedure CheckColdEqualizer;
var Cold:TRhythmRenderer;First:string;
begin
  Cold:=TRhythmRenderer.Create;
  try
    Cold.ConfigureStyle(rsRhythmGame,Ref,100,1);
    Cold.Render(Image,Meta,4.2,0);
    First:=ImageHash;
    Cold.Render(Image,Meta,8.2,0);
    Cold.Render(Image,Meta,4.2,0);
    Need(ImageHash=First,'First frame used the wrong planet for the equalizer');
  finally
    Cold.Free;
  end;
end;

procedure SnapshotTransfer;
var Course:TOrbitCourse;Time,Start:Double;
begin
  Course.Prepare(Plan,Image.Width,Image.Height);
  Time:=OrbitGameplayStart(Plan);
  while (Time<Plan.SoundEnd) and (Course.Leg(Course.LegAt(Time)).Kind<>1) do Time:=Time+0.005;
  Need(Time<Plan.SoundEnd,'No interplanetary transfer in the presentation fixture');
  Start:=Time;
  while (Time<Plan.SoundEnd) and (Course.Leg(Course.LegAt(Time)).Kind=1) do Time:=Time+0.005;
  Time:=(Start+Time)*0.5;
  Render.UseD2D:=True;
  Render.ConfigureStyle(rsRhythmGame,Ref,100,0);
  Render.Render(Image,Meta,Time,0);
  OverlayPreview(Image);
  Snapshot('type-v-transfer');
end;

begin A:=nil;Meta:=nil;Plan:=nil;Render:=nil;Surface:=nil;Image:=nil;PNG:=nil;Checks:=0;Frames:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','Presentation native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    for Style:=Low(TRhythmStyle) to High(TRhythmStyle) do begin
      Saved:=TRhythmSettings.Defaults;Saved.Style:=Style;
      Need(Saved.EqualizerMode=-1,'New default mode');Need(EqualizerEnabled(-1,Style,3)=(Style=rsRhythmGame),'Migration style default');
      for Mode:=-1 to 1 do begin Saved.EqualizerMode:=Mode;Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded),'Mode JSON parse');
        Need((Loaded.EqualizerMode=Mode) and (Loaded.Style=Style),'Mode JSON roundtrip');
      end;
    end;
    Need(not EqualizerEnabled(-1,rsRhythmGame,1),'Flat v1 migration gained meter');Need(EqualizerEnabled(1,rsRhythmGame,1),'Legacy explicit on');
    Need(not TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","equalizer":"false"}',Loaded),'Bad boolean accepted');
    Need((Abs(OrbitHitRadius(540)*2-49.68)<1E-9) and (Abs(OrbitHitRadius(1080)*2-99.36)<1E-9),
      'Type.V target diameter does not follow the viewport');
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(360,120);Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0));
    for B:=0 to 1 do begin Surface.UseD2D:=B=1;
      for J:=0 to 1 do begin Surface.BeginFrame(Image);
        if J=0 then Surface.FillRect(0,0,360,120,RGB(240,10,10)) else Surface.FillRect(0,0,360,120,RGB(10,10,240));
        for K:=0 to 2 do begin Tap:=Default(TOrbitTap);Tap.Source:=K;Tap.Chain:=1;Tap.Strength:=0.4;
          if K=1 then Tap.Chain:=3;if K=2 then Tap.Strength:=0.9;
          Need(Ord(OrbitMarkKind(Tap))=K,'Symbol meaning');
          DrawOrbitMark(Surface,70+K*110,60,OrbitHitRadius(720),0,0.4,0.7,OrbitMarkKind(Tap),OrbitMarkColor(Tap));
        end;
        Need(Surface.EndFrame,'Shape end frame');
        for K:=0 to 2 do for I:=0 to 24 do begin
          if J=0 then Samples[K,I]:=Image.Canvas.Pixels[66+K*110+(I mod 5)*2,56+(I div 5)*2]
          else Need(Samples[K,I]=Image.Canvas.Pixels[66+K*110+(I mod 5)*2,56+(I div 5)*2],'Marker core is transparent');
        end;
        for K:=0 to 2 do begin
          if J=0 then WideCore[K]:=Image.Canvas.Pixels[99+K*110,60]
          else Need(WideCore[K]=Image.Canvas.Pixels[99+K*110,60],'Enlarged target lost its opaque outer area');
        end;
        Snapshot(Format('symbols-backend%d-background%d',[B,J]));
      end;
      for J:=0 to 2 do begin Surface.BeginFrame(Image);Surface.FillRect(0,0,360,120,clBlack);
        DrawOrbitGood(Surface,180,90,J*0.19,360,120,RGB(80,230,255));Need(Surface.EndFrame,'GOOD end frame');Count:=0;
        for I:=0 to 359 do for K:=0 to 119 do if ColorToRGB(Image.Canvas.Pixels[I,K])<>0 then Inc(Count);
        if J=2 then Need(Count=0,'GOOD does not expire') else Need(Count>40,'GOOD missing');Snapshot(Format('good-backend%d-stage%d',[B,J]));
      end;
      if B=1 then Need(Surface.LastUsedD2D,'D2D unavailable');
    end;
    FreeAndNil(Surface);Image.SetSize(640,360);
    Source:=TPath.Combine(Folder,'presentation.identity');TFile.WriteAllText(Source,'Synthetic presentation identity',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    A:=TRhythmAudio.Create;A.Source:=Source;A.SourceRevision:=Revision;A.Key:=THashSHA2.GetHashString('presentation-v3');A.Sensitivity:=50;A.Duration:=20;A.SoundEnd:=20;
    SetLength(A.Hits,500);for I:=0 to High(A.Hits) do begin A.Hits[I].Time:=I*0.04;A.Hits[I].Strength:=0.3+(I mod 8)*0.1;end;
    Plan:=TOrbitPlan.Build(A,20);Ref:=NewPlanRef(A.Key,50,0,rsRhythmGame,121);Ref.SourceRevision:=Revision;Plan.Save(Ref,A);Meta:=TOrbitPlan.LoadAudioMetadata(Ref,Source,0);
    CheckMarkerLayout;
    CheckCrossingPreviews;
    CheckShortPreviews;
    CheckUniformTravel;
    Render:=TRhythmRenderer.Create;
    if GetEnvironmentVariable('RHYTHM_ORBIT_BENCHMARK')='1' then MeasureFrames
    else
    for B:=0 to 1 do begin Render.UseD2D:=B=1;
      for J:=Low(Times) to High(Times) do begin
        for Mode:=0 to 1 do begin Render.ConfigureStyle(rsRhythmGame,Ref,100,Mode);Render.Render(Image,A,Times[J],0);First:=ImageHash;
          Render.Render(Image,Meta,A.Duration-Times[J],0);Render.Render(Image,Meta,Times[J],0);Need(ImageHash=First,'Overlay warm/cold/seek drift');
          if Mode=0 then OffHash:=First else OnHash:=First;
          if J=4 then begin
            Snapshot(Format('game-backend%d-eq%d',[B,Mode]));
            if (B=1) and (Mode=0) then begin OverlayPreview(Image);Snapshot('type-v-preview');end;
          end;
          if (J=2) and (B=1) and (Mode=0) then begin OverlayPreview(Image);Snapshot('type-v-lead-in');end;
          Saved:=TRhythmSettings.Defaults;Saved.Style:=rsRhythmGame;Saved.Plan:=Ref;Saved.GameThreshold:=20;Saved.EqualizerMode:=Mode;
          Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded) and (Loaded.Plan.Key=Ref.Key) and (Loaded.Plan.Digest=Ref.Digest),'Display mode invalidated plan');
        end;
        Need((OffHash<>OnHash)=(Times[J]>=OrbitGameplayStart(Plan)),'Equalizer did not follow the opening boundary');
        Render.ConfigureStyle(rsRhythmGame,Ref,100,-1);Render.Render(Image,Meta,Times[J],0);Need(ImageHash=OnHash,'Auto game default');
      end;
      Render.ConfigureStyle(rsRhythmGame,Ref,100,0);Render.Render(Image,nil,2.4,0);OffHash:=ImageHash;
      Render.ConfigureStyle(rsRhythmGame,Ref,100,1);Render.Render(Image,nil,2.4,0);Need(ImageHash=OffHash,'No-audio overlay unsafe');
    end;
    if GetEnvironmentVariable('RHYTHM_ORBIT_BENCHMARK')<>'1' then begin CheckColdEqualizer;SnapshotTransfer;end;
    Activity:=EqualizerActivity(nil,1);Need(not Activity.Valid,'Nil audio reaction');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"frames":%d,"opaqueCore":true,"symbols":3,"settingsStyles":12,"planUnchanged":true}',[Checks,Frames]),TEncoding.UTF8);
    WriteLn('Orbit presentation PASS checks=',Checks,' frames=',Frames);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  PNG.Free;Surface.Free;Render.Free;Plan.Free;Meta.Free;A.Free;Image.Free;
end.
