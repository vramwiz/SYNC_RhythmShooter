unit RhythmOrbitLayout;
// 音楽計画から惑星、接線と円弧、一定速度で進むための累積弧長を組み立てる。
interface
uses RhythmOrbitPlan,RhythmOrbitTypes;
type
  TOrbitPathPoint=record
    Center:TOrbitPoint;
    Distance:Double; // 区間の始点からの弧長。座標と同じ世界単位。
  end;
  TOrbitPath=TArray<TOrbitPathPoint>;
  TOrbitSection=record
    Path:TOrbitPath;
    Center:TOrbitPoint;
    // Start/Finishは航路全体の弧長。Radiusが正ならPhaseから始まる円弧。
    Start,Finish,Phase,Radius:Double;
  end;
  TOrbitLayout=record
  public
    // 生成した配列はレコードが保持する。準備後の描画・予告からは読み取り専用。
    Bodies:TArray<TOrbitBody>;
    Legs:TArray<TOrbitLeg>;
    Sections:TArray<TOrbitSection>;
    Speed,TotalLength,FinishTime:Double;
    // Planは呼び出し中だけ借用する。画面ピクセルを世界の距離単位に使い、導入・離脱線はPaddingだけ画面端から離す。
    procedure Prepare(Plan:TOrbitPlan;Width,Height,Padding,GameplayStart:Double);
  private
    procedure PrepareItinerary(Plan:TOrbitPlan;GameplayStart:Double);
  end;
implementation
uses System.Math;

procedure TOrbitLayout.PrepareItinerary(Plan:TOrbitPlan;GameplayStart:Double);
const NotesPerVisit=9;
var FirstBody,Visits:TArray<Integer>;I,J,N,StartTap,AfterTap,Count,BodyTotal,LegTotal:Integer;
  L,Part:TOrbitLeg;Body:TOrbitBody;At,Step,ScoredStart,ScoredLength:Double;
begin
  SetLength(FirstBody,Plan.BodyCount);
  SetLength(Visits,Plan.BodyCount);
  for I:=0 to High(Visits) do Visits[I]:=1;
  for I:=0 to Plan.LegCount-1 do begin
    L:=Plan.Legs[I];
    if L.Kind<>0 then Continue;
    ScoredStart:=Max(L.Start,GameplayStart);
    ScoredLength:=L.Finish-ScoredStart;
    if ScoredLength<1.5 then Continue;
    StartTap:=Plan.Before(ScoredStart,False)+1;
    AfterTap:=Plan.Before(L.Finish,False)+1;
    Count:=0;
    while StartTap<AfterTap do begin
      Inc(Count);
      StartTap:=Plan.Before(Plan.Taps[StartTap].Time)+1;
    end;
    // 連続して音が多い区間は同じ惑星を周回せず、途中の惑星を増やす。
    if (ScoredLength>=2.0) and (Count>=6*ScoredLength) then
      Visits[L.FromBody]:=Min(Ceil(ScoredLength/1.65),Ceil(Count/NotesPerVisit));
    // 短い譜面でも周回に時間と音が揃えば、途中で次の空域へ渡る。
    if (Plan.BodyCount=1) and (Count>=4) then Visits[L.FromBody]:=Max(2,Visits[L.FromBody]);
  end;

  BodyTotal:=0;
  for I:=0 to High(Visits) do begin
    FirstBody[I]:=BodyTotal;
    Inc(BodyTotal,Visits[I]);
  end;
  SetLength(Bodies,BodyTotal);
  for I:=0 to High(Visits) do begin
    Body:=Plan.Bodies[I];
    for J:=0 to Visits[I]-1 do begin
      Bodies[FirstBody[I]+J]:=Body;
      Bodies[FirstBody[I]+J].Hue:=(Body.Hue+J*3) mod 8;
    end;
  end;

  LegTotal:=0;
  SetLength(Legs,Plan.LegCount+2*(BodyTotal-Plan.BodyCount));
  for I:=0 to Plan.LegCount-1 do begin
    L:=Plan.Legs[I];
    if L.Kind=4 then Continue;
    if L.Kind=0 then begin
      N:=Visits[L.FromBody];
      ScoredStart:=Max(L.Start,GameplayStart);
      Step:=(L.Finish-ScoredStart)/N;
      At:=L.Start;
      for J:=0 to N-1 do begin
        Part:=L;
        Part.FromBody:=FirstBody[L.FromBody]+J;
        Part.ToBody:=Part.FromBody;
        Part.Start:=At;
        if J<N-1 then Part.Finish:=ScoredStart+Step*(J+0.72);
        Legs[LegTotal]:=Part;Inc(LegTotal);
        if J=N-1 then Break;
        Part.Kind:=1;
        Inc(Part.ToBody);
        Part.Start:=Part.Finish;
        At:=ScoredStart+Step*(J+1);
        Part.Finish:=At;
        Bodies[Part.FromBody].Clear:=At+1.4;
        Legs[LegTotal]:=Part;Inc(LegTotal);
      end;
    end else begin
      Part:=L;
      Part.FromBody:=FirstBody[L.FromBody];
      if L.Kind in [1,3] then Inc(Part.FromBody,Visits[L.FromBody]-1);
      Part.ToBody:=FirstBody[L.ToBody];
      if L.Kind=3 then Part.ToBody:=Part.FromBody;
      Legs[LegTotal]:=Part;Inc(LegTotal);
    end;
  end;
  SetLength(Legs,LegTotal);
end;

procedure TOrbitLayout.Prepare(Plan:TOrbitPlan;Width,Height,Padding,GameplayStart:Double);
const
  // 左右に十分な距離を取りながら、縦方向へ進んで前の空域から離れる。
  StepX:array[0..4] of Double=(0.62,0.73,0,-0.62,-0.73);
  StepY:array[0..4] of Double=(0.27,0.50,0.60,0.31,0.52);
var I,J,Steps,Last,Heading,HorizontalRun:Integer;L:TOrbitLeg;Section:TOrbitSection;LayoutState:Cardinal;
  LastUsed:array[0..High(StepX)] of Integer;
  EntryPhase,ExitPhase,Advance,S,Radius,Length,SideX,SideY,ReachX,ReachY,Score,BestScore:Double;
  PreviousLength,DotProduct,LengthProduct,PreviousHorizontal,SlantHeight:Double;
  P,Q,Center,Step,PreviousStep,Candidate:TOrbitPoint;
  function LayoutFraction:Double;
  begin
    LayoutState:=Cardinal((UInt64(LayoutState)*1664525+1013904223) and $FFFFFFFF);
    Result:=(LayoutState shr 8)/16777216.0;
  end;
  function ConnectorAngle(FromBody,ToBody:Integer):Double;
  var A,B:TOrbitPoint;
  begin
    A:=Bodies[FromBody].Center;B:=Bodies[ToBody].Center;
    Result:=ArcTan2(B.Y-A.Y,B.X-A.X)-Pi/2;
  end;
  function EntryAngle(Index:Integer):Double;
  begin
    if Index>0 then Exit(ConnectorAngle(Index-1,Index));
    if System.Length(Bodies)>1 then Exit(ConnectorAngle(0,1)-Pi);
    Result:=0.6;
  end;
  function ExitAngle(Index:Integer):Double;
  begin
    if Index<High(Bodies) then Exit(ConnectorAngle(Index,Index+1));
    if Index>0 then Exit(EntryAngle(Index)+Pi);
    Result:=4.7;
  end;
  function OnCircle(const Center:TOrbitPoint;Angle:Double):TOrbitPoint;
  begin
    Result:=OrbitPoint(Center.X+Radius*Cos(Angle),Center.Y+Radius*Sin(Angle));
  end;
  function ExtendTangent(const P,Focus:TOrbitPoint;Angle,Direction:Double):TOrbitPoint;
  var X,Y,D,LocalX,LocalY,HalfW,HalfH:Double;
  begin
    X:=-Sin(Angle)*Direction;Y:=Cos(Angle)*Direction;
    LocalX:=P.X-Focus.X;LocalY:=P.Y-Focus.Y;
    HalfW:=Width*0.5-Padding;HalfH:=Height*0.5-Padding;
    D:=S*0.38;
    if X>1E-9 then D:=Min(D,(HalfW-LocalX)/X)
    else if X< -1E-9 then D:=Min(D,(-HalfW-LocalX)/X);
    if Y>1E-9 then D:=Min(D,(HalfH-LocalY)/Y)
    else if Y< -1E-9 then D:=Min(D,(-HalfH-LocalY)/Y);
    D:=Max(0.0,D);
    Result:=OrbitPoint(P.X+X*D,P.Y+Y*D);
  end;
begin
  Speed:=0;TotalLength:=0;
  Bodies:=nil;Legs:=nil;Sections:=nil;
  if Plan.LegCount=0 then Exit;
  PrepareItinerary(Plan,GameplayStart);
  S:=Min(Width,Height);
  Radius:=S*0.29;
  if System.Length(Bodies)=1 then Radius:=S*0.32;
  Center:=OrbitPoint(Width*0.5,Height*0.5);
  // 曲の時刻から乱数列を再現し、シークや再準備で惑星の位置が変わるのを防ぐ。
  LayoutState:=Cardinal(Plan.Count) xor Cardinal(Round(Frac(Plan.SoundEnd)*1000000));
  if Plan.Count>0 then LayoutState:=LayoutState xor Cardinal(Round(Frac(Plan.Taps[Plan.Count div 3].Time)*1000000));
  if LayoutFraction<0.5 then SideX:=1 else SideX:=-1;
  if LayoutFraction<0.5 then SideY:=-1 else SideY:=1;
  for J:=Low(LastUsed) to High(LastUsed) do LastUsed[J]:=-4;
  PreviousStep:=OrbitPoint(0,0);PreviousLength:=0;
  PreviousHorizontal:=0;HorizontalRun:=0;
  SlantHeight:=Min(Height,2*Width);
  for I:=0 to High(Bodies) do begin
    Bodies[I].Center:=Center;
    if I=High(Bodies) then Break;
    BestScore:=MaxDouble;Heading:=0;Step:=OrbitPoint(0,0);
    for J:=Low(StepX) to High(StepX) do begin
      ReachX:=1+0.11*LayoutFraction;ReachY:=1+0.11*LayoutFraction;
      if StepX[J]=0 then ReachY:=ReachY*Height else ReachY:=ReachY*SlantHeight;
      Candidate:=OrbitPoint(SideX*StepX[J]*ReachX*Width,SideY*StepY[J]*ReachY);
      Score:=LayoutFraction+Max(0,4-(I-LastUsed[J]))*0.30;
      // 近い角度の連続を避ける。大きく折り返す向きも、他に同程度の候補があれば避ける。
      DotProduct:=PreviousStep.X*Candidate.X+PreviousStep.Y*Candidate.Y;
      LengthProduct:=PreviousLength*Hypot(Candidate.X,Candidate.Y);
      if DotProduct>Cos(Pi/10)*LengthProduct then Score:=Score+3
      else if DotProduct< -0.15*LengthProduct then Score:=Score+0.20;
      // 斜めも横成分の符号で数え、縦を挟む場合も前に使った側は選びにくくする。
      if PreviousStep.X*Candidate.X>0 then Score:=Score+3
      else if (PreviousStep.X=0) and (PreviousHorizontal*Candidate.X>0) then Score:=Score+0.50;
      if Candidate.X<>0 then Score:=Score+Max(0,HorizontalRun-2)*0.35;
      if Score<BestScore then begin
        BestScore:=Score;Heading:=J;Step:=Candidate;
      end;
    end;
    LastUsed[Heading]:=I;
    if Step.X=0 then HorizontalRun:=0
    else begin
      Inc(HorizontalRun);
      PreviousHorizontal:=Step.X;
    end;
    PreviousStep:=Step;PreviousLength:=Hypot(Step.X,Step.Y);
    Center:=OrbitPoint(Center.X+Step.X,Center.Y+Step.Y);
  end;
  for I:=0 to High(Bodies) do begin
    Bodies[I].RX:=Radius;Bodies[I].RY:=Radius;Bodies[I].Rotation:=0;
    Bodies[I].Radius:=Bodies[I].Radius*Radius*0.76;
  end;

  Last:=High(Legs);
  SetLength(Sections,Last+1);
  FinishTime:=Plan.SoundEnd;
  for I:=0 to Last do begin
    L:=Legs[I];
    Section:=Default(TOrbitSection);
    if L.Kind=0 then begin
      EntryPhase:=EntryAngle(L.FromBody);
      ExitPhase:=ExitAngle(L.FromBody);
      Advance:=ExitPhase-EntryPhase;
      Advance:=Advance-2*Pi*Floor(Advance/(2*Pi));
      Section.Center:=Bodies[L.FromBody].Center;
      Section.Radius:=Radius;
      Section.Phase:=EntryPhase;
      Length:=Radius*Advance;
      // 円弧は角度と弧長で評価する。予告の交差判定だけ細かい線分を使う。
      Steps:=Max(1,Ceil(192*Advance/(2*Pi)));
      SetLength(Section.Path,Steps+1);
      for J:=0 to Steps do begin
        Section.Path[J].Center:=OnCircle(Section.Center,EntryPhase+Advance*J/Steps);
        Section.Path[J].Distance:=Length*J/Steps;
      end;
    end else begin
      ExitPhase:=ExitAngle(L.FromBody);
      EntryPhase:=EntryAngle(L.ToBody);
      P:=OnCircle(Bodies[L.FromBody].Center,ExitPhase);
      Q:=OnCircle(Bodies[L.ToBody].Center,EntryPhase);
      if L.Kind=2 then P:=ExtendTangent(Q,Bodies[L.ToBody].Center,EntryPhase,-1)
      else if L.Kind=3 then Q:=ExtendTangent(P,Bodies[L.FromBody].Center,ExitPhase,1);
      // 半径をそろえた惑星同士の共通接線。直線と周回が同じ向きでつながる。
      Length:=Hypot(Q.X-P.X,Q.Y-P.Y);
      SetLength(Section.Path,2);
      Section.Path[0].Center:=P;
      Section.Path[1].Center:=Q;
      Section.Path[1].Distance:=Length;
    end;
    Section.Start:=TotalLength;
    TotalLength:=TotalLength+Length;
    Section.Finish:=TotalLength;
    Sections[I]:=Section;
  end;
  // この譜面の全区間を一つの速さで進む。
  Speed:=TotalLength/FinishTime;
end;

end.
