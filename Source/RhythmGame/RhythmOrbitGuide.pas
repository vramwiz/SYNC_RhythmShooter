unit RhythmOrbitGuide;
// 準備した航路を絶対時刻で評価し、判定位置と先読み表示を決める。
interface
uses RhythmOrbitPlan,RhythmOrbitTypes,RhythmOrbitLayout;
const
  ORBIT_GUIDE_STEPS=640;
  ORBIT_MARKER_LIMIT=128;
  ORBIT_MARKER_GAP=2.0;
  ORBIT_MARKER_LEAD=2.40;
  ORBIT_MIN_MARKER_LEAD=0.80;
  ORBIT_WIDE_SCALE=0.82;
type
  TOrbitView=record
    // Centerは世界座標、ViewportCenterは描画領域の座標。惑星・自機・航路・マークで共有する。
    Center,ViewportCenter:TOrbitPoint;
    Scale:Double;
    function Project(const Point:TOrbitPoint):TOrbitPoint;
  end;
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
    // Centerと大きさは世界単位。描画時に自機や航路と一緒に投影する。
    Center:TOrbitPoint;
    Radius,Extent,Approach,Opacity,Visibility:Double;
    TapIndex,TapCount:Integer;
  end;
  TOrbitMarkers=array[0..ORBIT_MARKER_LIMIT-1] of TOrbitMarker;
  TOrbitCourse=record
  private type
    TCue=record
      Center:TOrbitPoint;
      // Timeは元の音時刻、ShowAtは交差と画面内の余裕を満たす表示開始時刻。
      Time,ShowAt,Radius,Extent:Double;
      TapIndex,TapCount:Integer;
    end;
  private
    FLayout:TOrbitLayout;
    FCues:TArray<TCue>;
    FWidth,FHeight,FHitRadius,FMinRadius:Double;
    function GetSpeed:Double;
    function SectionAt(Distance:Double):Integer;
    function DistanceAt(Time:Double):Double;
    function NextCue(Time:Double):Integer;
    function AfterPreviousPass(const Cue:TCue):Double;
    function InViewFrom(const Cue:TCue):Double;
    procedure DelayCrossingPreviews;
    class function PathPoint(const Path:TOrbitPath;Distance:Double):TOrbitPoint;static;
  public
    // Planを借用し、描画寸法に合わせて航路と判定の配列を作り直す。
    procedure Prepare(Plan:TOrbitPlan;Width,Height:Double);
    function Body(Index:Integer):TOrbitBody;
    function Leg(Index:Integer):TOrbitLeg;
    function BodyCount:Integer;
    function LegAt(Time:Double):Integer;
    function ViewAt(Time:Double):TOrbitView;
    // 等速航行の時刻を演出用の元の計画時刻に対応づける。判定の音時刻は保持する。
    function StoryTime(Time:Double):Double;
    function CursorAt(Time:Double):TOrbitPoint;
    function HitRadiusAt(Time:Double):Double;
    function HitIndex(Time:Double):Integer;
    function HitCount(Time:Double):Integer;
    property Speed:Double read GetSpeed;
    // 戻り値は固定長バッファに書き込んだ件数。位置は判定時刻から事前に確定している。
    function Visible(const State:TOrbitVisualState;Time:Double;out Markers:TOrbitMarkers):Integer;
    // 予告の線と判定中心を一致させるため、表示マークの時刻を線のサンプルに含める。
    function Route(Plan:TOrbitPlan;Start,Finish:Double;const Markers:TOrbitMarkers;
      MarkerCount:Integer;out Points:TOrbitRoute):Integer;
  end;
function OrbitGameplayStart(Plan:TOrbitPlan):Double;
function OrbitOpeningTapCount(Plan:TOrbitPlan):Integer;
function OrbitVisualState(Plan:TOrbitPlan;Time:Double):TOrbitVisualState;
function OrbitMarkerOpacity(Ahead,Horizon:Double):Double;
function OrbitMarkerGap(ShortSide:Double):Double;
function OrbitCursorRadius(ShortSide:Double):Double;
function OrbitCursorExtent(ShortSide:Double):Double;
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
  Result.Horizon:=Min(Max(0.0,Plan.SoundEnd-Time),ORBIT_MARKER_LEAD+0.35+0.35*(1-Result.Density));
end;
function OrbitMarkerOpacity(Ahead,Horizon:Double):Double;
begin
  if (Ahead<0) or (Horizon<=0) or (Ahead>Horizon) then Exit(0);
  Result:=Smooth(1-Ahead/Horizon);
end;

function OrbitMarkerGap(ShortSide:Double):Double;
begin
  Result:=Max(0.5,ORBIT_MARKER_GAP*Sqr(Min(1.0,ShortSide/540)));
end;

function OrbitCursorRadius(ShortSide:Double):Double;
begin
  Result:=OrbitMinimumMarkRadius(ShortSide)*0.82/ORBIT_WIDE_SCALE;
end;

function OrbitCursorExtent(ShortSide:Double):Double;
var Radius:Double;
begin
  Radius:=OrbitCursorRadius(ShortSide);
  Result:=Radius+Max(1.2/ORBIT_WIDE_SCALE,Radius*0.12);
end;

procedure TOrbitCourse.Prepare(Plan:TOrbitPlan;Width,Height:Double);
var I,J,Count,LastAtTime:Integer;Gap,MarkerGap,LatestShow,ShortSide,Extent:Double;Cue:TCue;
begin
  FWidth:=Width;
  FHeight:=Height;
  FHitRadius:=OrbitHitRadius(Min(Width,Height));
  FMinRadius:=OrbitMinimumMarkRadius(Min(Width,Height))/ORBIT_WIDE_SCALE;
  ShortSide:=Min(Width,Height);
  Extent:=OrbitMarkExtent(FHitRadius,StartApproach);
  FLayout.Prepare(Plan,Width,Height,Min(ShortSide*0.18,Extent+ORBIT_MARKER_GAP+ShortSide*0.01),
    OrbitGameplayStart(Plan));
  I:=OrbitOpeningTapCount(Plan);
  SetLength(FCues,Plan.Count-I);
  MarkerGap:=OrbitMarkerGap(Min(Width,Height))/ORBIT_WIDE_SCALE;
  Count:=0;
  while I<Plan.Count do begin
    Cue.Time:=Plan.Taps[I].Time;
    LastAtTime:=Plan.Before(Cue.Time);
    Cue.TapIndex:=LastAtTime;
    Cue.TapCount:=LastAtTime-I+1;
    I:=LastAtTime+1;
    Cue.Center:=CursorAt(Cue.Time);
    Cue.Radius:=FMinRadius;
    Cue.Extent:=OrbitMarkExtent(Cue.Radius,StartApproach);
    Cue.ShowAt:=Max(0.0,Cue.Time-ORBIT_MARKER_LEAD);
    LatestShow:=Cue.Time-ORBIT_MIN_MARKER_LEAD;
    if Count>=ORBIT_MARKER_LIMIT then Cue.ShowAt:=Max(Cue.ShowAt,FCues[Count-ORBIT_MARKER_LIMIT].Time);
    for J:=Count-1 downto 0 do begin
      if FCues[J].Time<=Cue.ShowAt then Break;
      Gap:=FCues[J].Extent+Cue.Extent+MarkerGap;
      if Sqr(FCues[J].Center.X-Cue.Center.X)+Sqr(FCues[J].Center.Y-Cue.Center.Y)<Sqr(Gap) then begin
        Cue.ShowAt:=FCues[J].Time;
        Break;
      end;
    end;
    if Cue.ShowAt>LatestShow then Continue;
    Cue.ShowAt:=AfterPreviousPass(Cue);
    if Cue.ShowAt>LatestShow then Continue;
    Cue.ShowAt:=InViewFrom(Cue);
    // 読める間隔と予告時間が揃う音を判定にする。他の音も背景の音反応には残す。
    if Cue.ShowAt>LatestShow then Continue;
    FCues[Count]:=Cue;
    Inc(Count);
  end;
  SetLength(FCues,Count);
  DelayCrossingPreviews;
end;

function TOrbitCourse.InViewFrom(const Cue:TCue):Double;
const SampleStep=1/60;
var At,Extent:Double;View:TOrbitView;P,NearEdge,FarEdge,TopLeft,BottomRight:TOrbitPoint;
begin
  Result:=Cue.Time;
  TopLeft:=Cue.Center;BottomRight:=Cue.Center;
  while Result>Cue.ShowAt do begin
    At:=Max(Cue.ShowAt,Result-SampleStep);
    View:=ViewAt(At);
    P:=View.Project(Cue.Center);
    Extent:=OrbitMarkExtent(Cue.Radius*View.Scale,StartApproach)+Min(FWidth,FHeight)*0.008;
    if (P.X<Extent) or (P.X>FWidth-Extent) or (P.Y<Extent) or (P.Y>FHeight-Extent) then Exit;
    // 一度画面外へ出る航路の先にある円は、手前の航路まで画面に入ってから予告する。
    P:=CursorAt(At);
    TopLeft:=OrbitPoint(Min(TopLeft.X,P.X),Min(TopLeft.Y,P.Y));
    BottomRight:=OrbitPoint(Max(BottomRight.X,P.X),Max(BottomRight.Y,P.Y));
    NearEdge:=View.Project(TopLeft);FarEdge:=View.Project(BottomRight);
    if (NearEdge.X<0) or (NearEdge.Y<0) or (FarEdge.X>FWidth) or (FarEdge.Y>FHeight) then Exit;
    Result:=At;
  end;
end;

function TOrbitCourse.AfterPreviousPass(const Cue:TCue):Double;
var I,J,FirstSection:Integer;Path:TOrbitPath;A,B:TOrbitPoint;
  First,Last,Start,Finish,SegmentStart,SegmentFinish,Radius,Radius2,DX,DY,Length2,Along,Offset,HalfSpan,ExitTime:Double;
  FinalApproach:Boolean;
begin
  Result:=Cue.ShowAt;
  First:=DistanceAt(Cue.ShowAt);
  Last:=DistanceAt(Cue.Time);
  Radius:=Cue.Extent+OrbitCursorExtent(Min(FWidth,FHeight));
  if Last-First<=Radius then Exit;

  Radius2:=Sqr(Radius);
  FinalApproach:=True;
  FirstSection:=SectionAt(First);
  for I:=SectionAt(Last) downto FirstSection do begin
    Path:=FLayout.Sections[I].Path;
    for J:=High(Path) downto 1 do begin
      SegmentStart:=FLayout.Sections[I].Start+Path[J-1].Distance;
      SegmentFinish:=FLayout.Sections[I].Start+Path[J].Distance;
      if SegmentStart>=Last then Continue;
      if SegmentFinish<=First then Break;
      if SegmentFinish<=SegmentStart then Continue;
      Start:=Max(First,SegmentStart);
      Finish:=Min(Last,SegmentFinish);
      A:=Path[J-1].Center;B:=Path[J].Center;
      DX:=(B.X-A.X)/(SegmentFinish-SegmentStart);
      DY:=(B.Y-A.Y)/(SegmentFinish-SegmentStart);
      A:=OrbitPoint(A.X+(Start-SegmentStart)*DX,A.Y+(Start-SegmentStart)*DY);
      if FinalApproach then begin
        // 最後に判定点へ入る一続きの区間は予告を出したままにする。
        FinalApproach:=Sqr(A.X-Cue.Center.X)+Sqr(A.Y-Cue.Center.Y)<=Radius2;
        Continue;
      end;
      DX:=DX*(Finish-Start);DY:=DY*(Finish-Start);
      Length2:=Sqr(DX)+Sqr(DY);
      if Length2<=1E-16 then Continue;
      Along:=((Cue.Center.X-A.X)*DX+(Cue.Center.Y-A.Y)*DY)/Length2;
      Offset:=Sqr((Cue.Center.X-A.X)*DY-(Cue.Center.Y-A.Y)*DX)/Length2;
      if Offset>Radius2 then Continue;
      HalfSpan:=Sqrt((Radius2-Offset)/Length2);
      if (Along+HalfSpan>=0) and (Along-HalfSpan<=1) then begin
        // 手前の航路が円の範囲を横切る場合は、その出口より後に予告を出す。
        ExitTime:=(Start+Min(1.0,Along+HalfSpan)*(Finish-Start))/FLayout.Speed;
        Result:=Max(Result,ExitTime+Min(1E-6,(Cue.Time-ExitTime)*0.5));
        Exit;
      end;
    end;
  end;
end;

procedure TOrbitCourse.DelayCrossingPreviews;
var Earlier,Later,I,J:Integer;BeforePath,AfterPath:TOrbitPath;A,B:TOrbitSection;
  LookAhead,BeforeFraction,AfterFraction,BeforeCross,AfterCross:Double;
  function SegmentCross(const P,Q,R,S:TOrbitPoint;out U,V:Double):Boolean;
  var DX,DY,EX,EY,Cross,X,Y:Double;
  begin
    Result:=False;
    DX:=Q.X-P.X;DY:=Q.Y-P.Y;EX:=S.X-R.X;EY:=S.Y-R.Y;
    Cross:=DX*EY-DY*EX;
    if Abs(Cross)<=1E-8*Hypot(DX,DY)*Hypot(EX,EY) then Exit;
    X:=R.X-P.X;Y:=R.Y-P.Y;
    U:=(X*EY-Y*EX)/Cross;
    V:=(X*DY-Y*DX)/Cross;
    Result:=(U>=0) and (U<=1) and (V>=0) and (V<=1);
  end;
  procedure DelayBranch(BeforeAt,BranchStart:Double);
  var Index:Integer;ReleaseAt,Limit:Double;
  begin
    // 後で通る枝は入口から伏せる。直線の先につながる円弧も同じ先読み範囲に含める。
    ReleaseAt:=(BeforeAt+Min(FMinRadius,(BranchStart-BeforeAt)*0.5))/FLayout.Speed;
    Limit:=ReleaseAt+ORBIT_MARKER_LEAD;
    Index:=NextCue(BranchStart/FLayout.Speed-1E-9);
    while (Index<Length(FCues)) and (FCues[Index].Time<=Limit) do begin
      FCues[Index].ShowAt:=Max(FCues[Index].ShowAt,ReleaseAt);
      Inc(Index);
    end;
  end;
begin
  if (FLayout.Speed<=0) or (Length(FCues)=0) then Exit;
  LookAhead:=FLayout.Speed*ORBIT_MARKER_LEAD;
  for Later:=2 to High(FLayout.Sections) do begin
    B:=FLayout.Sections[Later];AfterPath:=B.Path;
    // 隣り合う区間は接線でつながるため、継ぎ目は交差として扱わない。
    for Earlier:=Later-2 downto 0 do begin
      A:=FLayout.Sections[Earlier];
      if B.Start-A.Finish>=LookAhead then Break;
      if (A.Radius>0) and (B.Radius>0) then
        if ((A.Center.X=B.Center.X) and (A.Center.Y=B.Center.Y)) or
          (Hypot(A.Center.X-B.Center.X,A.Center.Y-B.Center.Y)>A.Radius+B.Radius) then Continue;
      BeforePath:=A.Path;
      for I:=1 to High(BeforePath) do begin
        if B.Start-A.Start-BeforePath[I].Distance>=LookAhead then Continue;
        for J:=1 to High(AfterPath) do begin
          if not SegmentCross(BeforePath[I-1].Center,BeforePath[I].Center,
            AfterPath[J-1].Center,AfterPath[J].Center,BeforeFraction,AfterFraction) then Continue;
          BeforeCross:=A.Start+BeforePath[I-1].Distance+
            (BeforePath[I].Distance-BeforePath[I-1].Distance)*BeforeFraction;
          AfterCross:=B.Start+AfterPath[J-1].Distance+
            (AfterPath[J].Distance-AfterPath[J-1].Distance)*AfterFraction;
          if (AfterCross-BeforeCross>1E-8) and (B.Start-BeforeCross<LookAhead) then
            DelayBranch(BeforeCross,B.Start);
        end;
      end;
    end;
  end;
end;

function TOrbitCourse.GetSpeed:Double;
begin
  Result:=FLayout.Speed;
end;

function TOrbitCourse.DistanceAt(Time:Double):Double;
begin
  Result:=EnsureRange(Time*FLayout.Speed,0.0,FLayout.TotalLength);
end;

function TOrbitCourse.SectionAt(Distance:Double):Integer;
var L,R,M:Integer;
begin
  L:=0;
  R:=High(FLayout.Sections);
  while L<R do begin
    M:=L+(R-L) div 2;
    if FLayout.Sections[M].Finish<=Distance then L:=M+1 else R:=M;
  end;
  Result:=L;
end;

function TOrbitCourse.Body(Index:Integer):TOrbitBody;
begin
  Result:=FLayout.Bodies[Index];
end;

function TOrbitCourse.Leg(Index:Integer):TOrbitLeg;
begin
  Result:=FLayout.Legs[Index];
end;

function TOrbitCourse.BodyCount:Integer;
begin
  Result:=Length(FLayout.Bodies);
end;

function TOrbitCourse.LegAt(Time:Double):Integer;
begin
  if Length(FLayout.Sections)=0 then Exit(-1);
  Result:=SectionAt(DistanceAt(Time));
end;

function TOrbitView.Project(const Point:TOrbitPoint):TOrbitPoint;
begin
  Result:=OrbitPoint(ViewportCenter.X+(Point.X-Center.X)*Scale,
    ViewportCenter.Y+(Point.Y-Center.Y)*Scale);
end;

function TOrbitCourse.ViewAt(Time:Double):TOrbitView;
var Index:Integer;Distance:Double;View:TOrbitView;
  function FrameTransfer(Index:Integer):Boolean;
  var Start,Finish,Span,Blend,Offset,Progress,U:Double;A,B:TOrbitPoint;
  begin
    Result:=False;
    if (Index<=0) or (Index>=High(FLayout.Sections)) or (FLayout.Legs[Index].Kind<>1) then Exit;
    Start:=FLayout.Sections[Index].Start;Finish:=FLayout.Sections[Index].Finish;Span:=Finish-Start;
    Blend:=Min(Span*0.55,0.48*Min(Start-FLayout.Sections[Index-1].Start,FLayout.Sections[Index+1].Finish-Finish));
    if (Distance<Start-Blend) or (Distance>Finish+Blend) then Exit;
    // 出発前と到着後にパンをならす。直線区間ではカメラが自機よりゆっくり進む。
    Offset:=Distance-Start;
    if Offset<0 then Progress:=Sqr(Offset+Blend)/(2*Blend)
    else if Offset>Span then Progress:=Span+Blend-Sqr(Span+Blend-Offset)/(2*Blend)
    else Progress:=Offset+Blend*0.5;
    Progress:=Progress/(Span+Blend);
    A:=FLayout.Bodies[FLayout.Legs[Index].FromBody].Center;B:=FLayout.Bodies[FLayout.Legs[Index].ToBody].Center;
    View.Center:=OrbitPoint(A.X+(B.X-A.X)*Progress,A.Y+(B.Y-A.Y)*Progress);
    U:=(Offset+Blend)/(Span+2*Blend);
    View.Scale:=1-(1-ORBIT_WIDE_SCALE)*Sqr(Sin(Pi*U));
    Result:=True;
  end;
begin
  View.ViewportCenter:=OrbitPoint(FWidth*0.5,FHeight*0.5);
  View.Center:=View.ViewportCenter;
  View.Scale:=1;
  if Length(FLayout.Sections)>0 then begin
    Distance:=DistanceAt(Time);
    Index:=SectionAt(Distance);
    View.Center:=FLayout.Bodies[FLayout.Legs[Index].FromBody].Center;
    if not FrameTransfer(Index) and not FrameTransfer(Index-1) then FrameTransfer(Index+1);
  end;
  Result:=View;
end;

function TOrbitCourse.StoryTime(Time:Double):Double;
var Index:Integer;Distance,Length:Double;L:TOrbitLeg;
begin
  if System.Length(FLayout.Sections)=0 then Exit(Time);
  Distance:=DistanceAt(Time);
  Index:=SectionAt(Distance);
  L:=FLayout.Legs[Index];
  if Time>=FLayout.FinishTime then Exit(L.Finish+Time-FLayout.FinishTime);
  Length:=FLayout.Sections[Index].Finish-FLayout.Sections[Index].Start;
  if Length<=0 then Exit(L.Finish);
  Result:=L.Start+(L.Finish-L.Start)*(Distance-FLayout.Sections[Index].Start)/Length;
end;

class function TOrbitCourse.PathPoint(const Path:TOrbitPath;Distance:Double):TOrbitPoint;
var L,R,M:Integer;U:Double;A,B:TOrbitPathPoint;
begin
  if Distance<=0 then Exit(Path[0].Center);
  L:=0;R:=High(Path);
  if Distance>=Path[R].Distance then Exit(Path[R].Center);
  while R-L>1 do begin
    M:=L+(R-L) div 2;
    if Path[M].Distance<=Distance then L:=M else R:=M;
  end;
  A:=Path[L];B:=Path[R];
  U:=(Distance-A.Distance)/(B.Distance-A.Distance);
  Result:=OrbitPoint(A.Center.X+(B.Center.X-A.Center.X)*U,A.Center.Y+(B.Center.Y-A.Center.Y)*U);
end;

function TOrbitCourse.CursorAt(Time:Double):TOrbitPoint;
var Index:Integer;Distance,Angle:Double;
begin
  if Length(FLayout.Sections)=0 then Exit(OrbitPoint(FWidth*0.5,FHeight*0.5));
  Distance:=DistanceAt(Time);
  Index:=SectionAt(Distance);
  Distance:=Distance-FLayout.Sections[Index].Start;
  if FLayout.Sections[Index].Radius>0 then begin
    Angle:=FLayout.Sections[Index].Phase+Distance/FLayout.Sections[Index].Radius;
    Exit(OrbitPoint(FLayout.Sections[Index].Center.X+FLayout.Sections[Index].Radius*Cos(Angle),
      FLayout.Sections[Index].Center.Y+FLayout.Sections[Index].Radius*Sin(Angle)));
  end;
  Result:=PathPoint(FLayout.Sections[Index].Path,Distance);
end;

function TOrbitCourse.HitRadiusAt(Time:Double):Double;
var I:Integer;
begin
  I:=NextCue(Time)-1;
  if (I>=0) and (FCues[I].Time=Time) then Exit(FCues[I].Radius);
  Result:=FHitRadius;
end;

function TOrbitCourse.HitCount(Time:Double):Integer;
begin
  Result:=NextCue(Time);
end;

function TOrbitCourse.HitIndex(Time:Double):Integer;
var Count:Integer;
begin
  Count:=NextCue(Time);
  if Count=0 then Exit(-1);
  Result:=FCues[Count-1].TapIndex;
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

function TOrbitCourse.Visible(const State:TOrbitVisualState;Time:Double;out Markers:TOrbitMarkers):Integer;
var I,Next:Integer;Cue:TCue;Mark:TOrbitMarker;Lead,Age:Double;
begin
  Result:=0;
  if State.PreviewAlpha<=0 then Exit;
  Next:=NextCue(Time);
  for I:=Next to Min(High(FCues),Next+ORBIT_MARKER_LIMIT-1) do begin
    Cue:=FCues[I];
    Lead:=Cue.Time-Time;
    if Lead>=ORBIT_MARKER_LEAD then Break;
    if Time<Cue.ShowAt then Continue;
    Age:=Time-Cue.ShowAt;
    Mark.TapIndex:=Cue.TapIndex;
    Mark.TapCount:=Cue.TapCount;
    Mark.Center:=Cue.Center;
    Mark.Visibility:=(0.86+0.14*EaseOut(Age/0.10))*State.PreviewAlpha;
    Mark.Opacity:=0.58+0.42*OrbitMarkerOpacity(Lead,ORBIT_MARKER_LEAD);
    Mark.Radius:=Cue.Radius;
    Mark.Approach:=StartApproach+(1-StartApproach)*Smooth(1-Lead/ORBIT_MARKER_LEAD);
    Mark.Extent:=OrbitMarkExtent(Mark.Radius,Mark.Approach);
    Markers[Result]:=Mark;
    Inc(Result);
  end;
end;

function TOrbitCourse.Route(Plan:TOrbitPlan;Start,Finish:Double;const Markers:TOrbitMarkers;
  MarkerCount:Integer;out Points:TOrbitRoute):Integer;
var I,J,Samples:Integer;At,NextTime,Step,SampleTime:Double;
begin
  Points[0].Time:=Start;
  Points[0].P:=CursorAt(Start);
  Result:=0;
  if Finish<=Start then Exit;
  // 各判定間の端数を切り上げられるよう、バッファの一部を区間の終点用に確保する。
  Step:=Max((Finish-Start)/(ORBIT_GUIDE_STEPS-MarkerCount-1),Min(1/45,Min(FWidth,FHeight)*0.018/Max(1.0,FLayout.Speed)));
  At:=Start;
  for I:=0 to MarkerCount do begin
    NextTime:=Finish;
    if I<MarkerCount then NextTime:=Min(Finish,Plan.Taps[Markers[I].TapIndex].Time);
    Samples:=Ceil((NextTime-At)/Step);
    for J:=1 to Samples do begin
      if J=Samples then SampleTime:=NextTime else SampleTime:=At+(NextTime-At)*J/Samples;
      Inc(Result);
      Points[Result].Time:=SampleTime;
      Points[Result].P:=CursorAt(SampleTime);
    end;
    At:=NextTime;
    if At>=Finish then Break;
  end;
end;
end.
