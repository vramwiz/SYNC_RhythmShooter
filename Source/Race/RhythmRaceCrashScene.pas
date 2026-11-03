unit RhythmRaceCrashScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmRaceCrash,RhythmRenderSurface;
procedure DrawRaceCrash(Plan:TRaceCrashPlan;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer);
// 地上の車体寸法は計画と共有し、高さ・陰影だけで立体感を作る描画ユニット。
implementation
uses System.Math,System.SysUtils,System.Types,Winapi.Windows,Vcl.Graphics,RhythmRaceImpact;
type
  TPointD=record
    X,Y:Double;
  end;

function Mix(A,B:TColor;U:Double):TColor;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
end;

procedure DrawRaceCrash(Plan:TRaceCrashPlan;Surface:TAnimationRenderSurface;Time:Double;Width,Height:Integer);
var
  Clock,Scale,Left,Top,Camera,Age,U,Y,Speed,BodyLean,BodyBounce,Health:Double;
  I,J,K,First,Last,Count:Integer;
  Cars:array[0..159]of TCrashPose;
  Pose,Temporary:TCrashPose;
  P,Center:TCrashProjection;
  E:TCrashEnemy;
  Body,Glass:TColor;
  procedure Line(X1,Y1,X2,Y2:Double;C:TColor;W:Double);
  begin Surface.Line(Left+X1*Scale,Top+Y1*Scale,Left+X2*Scale,Top+Y2*Scale,C,Max(1,W*Scale));
  end;
  procedure Box(X1,Y1,X2,Y2:Double;C:TColor);
  begin Surface.FillRect(Left+X1*Scale,Top+Y1*Scale,Left+X2*Scale,Top+Y2*Scale,C);
  end;
  procedure Dot(X,Y,R:Double;C:TColor;Filled:Boolean=True);
  begin Surface.Circle(Left+X*Scale,Top+Y*Scale,R*Scale,C,Filled,Max(1,0.002*Scale));
  end;
  procedure Add(const Value:TCrashPose);
  begin if Count>=Length(Cars) then Exit;
    if Value.Distance-Camera>900 then Exit;
    if Value.Alive then begin
      if Value.Distance-Camera+Value.Front<=-32.5 then Exit;
    end else if Value.Distance-Camera-Value.Back<=-32.5 then Exit;
    Cars[Count]:=Value;
    Inc(Count);
  end;
  function Vertex(D,L,H:Double):TPointD;
  var
    Q:TCrashProjection;
    DX,DY,Co,Si,Distance:Double;
  begin if Pose.Role=2 then H:=H*Plan.HeroScale;
    // 長い荷台は後端だけが近端を越えても前部が残る。接地車の面を近端で切る。
    Distance:=Pose.Distance+D;
    if Pose.Alive then Distance:=Max(Distance,Camera-32.5);
    Q:=Plan.Project(Distance,Pose.Lane+L,Clock,H+Pose.Lift);
    DX:=Q.X-Center.X;
    DY:=Q.Y-Center.Y;
    Co:=Cos(Pose.Turn);
    Si:=Sin(Pose.Turn);
    Result.X:=Center.X+DX*Co-DY*Si;
    Result.Y:=Center.Y+DX*Si+DY*Co;
  end;
  function BodyVertex(D,L,H:Double):TPointD;
  begin
    if H>0.020 then begin L:=L+BodyLean;
      H:=H+BodyBounce;
    end;
    Result:=Vertex(D,L,H);
  end;
  procedure Face(const A,B,C,D:TPointD;Color:TColor);
  begin
    // 太い線で面を掃引すると近接時に線端が外へ出る。投影した境界内だけを塗る。
    Surface.FillQuad(TPointF.Create(Left+A.X*Scale,Top+A.Y*Scale),
      TPointF.Create(Left+B.X*Scale,Top+B.Y*Scale),
      TPointF.Create(Left+C.X*Scale,Top+C.Y*Scale),
      TPointF.Create(Left+D.X*Scale,Top+D.Y*Scale),Color);
  end;
  procedure Panel(Front,Back,Lane1,Lane2,H:Double;C:TColor);
  begin Face(BodyVertex(Front,Lane1,H),BodyVertex(Front,Lane2,H),
    BodyVertex(Back,Lane2,H),BodyVertex(Back,Lane1,H),C);
  end;
  procedure Side(D1,D2,L,H1,H2:Double;C:TColor);
  begin Face(BodyVertex(D1,L,H2),BodyVertex(D2,L,H2),
    BodyVertex(D2,L,H1),BodyVertex(D1,L,H1),C);
  end;
  procedure EndFace(D,L1,L2,H1,H2:Double;C:TColor);
  begin Face(BodyVertex(D,L1,H2),BodyVertex(D,L2,H2),
    BodyVertex(D,L2,H1),BodyVertex(D,L1,H1),C);
  end;
  procedure Solid(F,B,L1,L2,Bottom,Roof:Double;C:TColor);
  begin
    // Physical ground dimensions stay unchanged; height creates the volume.
    EndFace(F,L1,L2,Bottom,Roof,Mix(C,clBlack,0.20));
    Side(F,B,L1,Bottom,Roof,Mix(C,clBlack,0.43));
    Side(F,B,L2,Bottom,Roof,Mix(C,clBlack,0.22));
    EndFace(B,L1,L2,Bottom,Roof,Mix(C,clBlack,0.32));
    Panel(F,B,L1,L2,Roof,Mix(C,clWhite,0.15));
  end;
  procedure Cabin(F,B,W,Base,Roof:Double;C:TColor);
  begin
    // Sloped glass and side windows join a smaller roof to the body deck.
    Face(BodyVertex(F,-W,Base),BodyVertex(F,W,Base),
    BodyVertex(F*0.72,W*0.86,Roof),BodyVertex(F*0.72,-W*0.86,Roof),Glass);
    Face(BodyVertex(F,-W,Base),BodyVertex(F*0.72,-W*0.86,Roof),
    BodyVertex(B*0.72,-W*0.86,Roof),BodyVertex(B,-W,Base),Mix(Glass,clBlack,0.20));
    Face(BodyVertex(F,W,Base),BodyVertex(F*0.72,W*0.86,Roof),
    BodyVertex(B*0.72,W*0.86,Roof),BodyVertex(B,W,Base),Mix(Glass,clWhite,0.15));
    Face(BodyVertex(B,-W,Base),BodyVertex(B,W,Base),
    BodyVertex(B*0.72,W*0.86,Roof),BodyVertex(B*0.72,-W*0.86,Roof),Glass);
    Panel(F*0.72,B*0.72,-W*0.86,W*0.86,Roof,Mix(C,clWhite,0.27));
  end;
  procedure Edge(Front,Back,Lane1,Lane2,H:Double;C:TColor;W:Double);
  var
    A,B:TPointD;
  begin if H>0.020 then begin Lane1:=Lane1+BodyLean;
      Lane2:=Lane2+BodyLean;
      H:=H+BodyBounce;
    end;
    A:=Vertex(Front,Lane1,H);
    B:=Vertex(Back,Lane2,H);
    Line(A.X,A.Y,B.X,B.Y,C,W*Center.Scale);
  end;
  procedure Post(D,L,H1,H2:Double;C:TColor;W:Double);
  var A,B:TPointD;
  begin
    A:=BodyVertex(D,L,H1);B:=BodyVertex(D,L,H2);
    Line(A.X,A.Y,B.X,B.Y,C,W*Center.Scale);
  end;
  procedure Vehicle;
  var
    W,F,B,H,CargoH,CabH,WindowBase,WindowTop,Axle,DamageD,DamageBase,DamageTop,MarkH:Double;
    Part,Stage:Integer;
    C:TColor;
  begin
    Center:=Plan.Project(Pose.Distance,Pose.Lane,Clock,Pose.Lift);
    if Pose.Alive and (Pose.Distance<Camera-32.5) then
      Center:=Plan.Project(Camera-32.5,Pose.Lane,Clock,Pose.Lift);
    if not Center.Visible then Exit;
    BodyLean:=0;
    BodyBounce:=0;
    if Pose.Role=2 then begin
      BodyLean:=EnsureRange(-Plan.LaneVelocity(Clock)*0.011,-0.011,0.011);
      BodyBounce:=0.0015*Speed*Sin(Clock*63);
      Part:=Plan.HitBefore(Clock);
      if Part>=0 then begin Age:=Clock-Plan.Hits[Part].Time;
        if (Age>=0) and (Age<0.20) then begin
          BodyLean:=EnsureRange(BodyLean+0.004*(1-Age/0.20)*Sin(Age*60),-0.013,0.013);
          BodyBounce:=BodyBounce+0.006*(1-Age/0.20)*Cos(Age*55);
        end;
      end;
    end;
    if (Plan.Version>=10) and (Pose.Role=0) and Pose.Alive then
      BodyLean:=EnsureRange(-Plan.TrafficLaneVelocity(Pose.Index,Clock)*0.004,-Pose.Width*0.05,Pose.Width*0.05);
    W:=Pose.Width;
    F:=Pose.Front;
    B:=-Pose.Back;
    H:=0.047;
    if Pose.Kind>0 then H:=0.064;
    if Pose.Kind>=3 then H:=0.070;
    DamageD:=B*0.945;DamageBase:=0.017;DamageTop:=H-0.006;
    Body:=RGB(105,151,190);
    if Pose.Role=2 then Body:=RGB(60,189,213)
    else if Pose.Role=1 then begin Body:=RGB(218,83,64);
      if Pose.Kind>=4 then Body:=RGB(183,99,55)
      else if Pose.Kind>0 then Body:=RGB(209,132,69);
    end
    else case Pose.Kind of 1:Body:=RGB(215,204,145);
      2:Body:=RGB(141,179,171);
      3:Body:=RGB(185,195,204);
    end;
    Glass:=RGB(35,65,83);
    Stage:=Floor(Pose.Damage*4);
    if Pose.Role=1 then Body:=Mix(Body,RGB(69,65,73),Pose.Damage*0.55);
    // Wheel blocks, body sides, rear bumper and roof occupy the original footprint.
    Panel(F,B,-W,W,0,RGB(24,34,44));
    for Part:=0 to 1 do begin
      Axle:=F*0.55;
      if Part=1 then Axle:=B*0.65;
      Solid(Axle+Min(1.1,F*0.20),Axle-Min(1.1,-B*0.20),-W,-W*0.78,0.002,0.020,RGB(20,25,31));
      Solid(Axle+Min(1.1,F*0.20),Axle-Min(1.1,-B*0.20),W*0.78,W,0.002,0.020,RGB(20,25,31));
    end;
    Solid(F*0.94,B*0.94,-W*0.91,W*0.91,0.012,H,Body);
    Edge(F*0.90,B*0.90,-W*0.92,-W*0.92,0.022,Mix(Body,clWhite,0.30),0.003);
    Edge(F*0.90,B*0.90,W*0.92,W*0.92,0.022,Mix(Body,clBlack,0.40),0.003);
    // 後輪は下部車体の後、荷台より先に描く。奥側の輪を後扉の上へ重ねず、接地点は保持する。
    if Pose.Kind>=3 then for Part:=0 to 1 do begin Axle:=B*(0.59+Part*0.18);
      Solid(Axle+0.85,Axle-0.85,-W,-W*0.77,0.002,0.022,RGB(20,25,31));
      Solid(Axle+0.85,Axle-0.85,W*0.77,W,0.002,0.022,RGB(20,25,31));
    end;
    if Pose.Kind>=3 then begin
      CargoH:=0.290;
      CabH:=0.245;
      // 細い一般トラックと大型敵の側壁を確保。地上寸法・車体下端は変えない。
      if Pose.Role=1 then begin
        CargoH:=0.350;
        CabH:=0.295;
        if Pose.Kind>=4 then CabH:=0.285;
      end;
      WindowBase:=CabH-0.100;
      WindowTop:=CabH-0.018;
      DamageD:=B*0.89;DamageBase:=H+0.024;DamageTop:=CargoH-0.024;
      // トラックのキャビンは進行方向側。後方から荷台の扉・側板・車軸が見える。
      Solid(F*0.94,F*0.52,-W*0.80,W*0.80,H,CabH,Body);
      EndFace(F*0.515,-W*0.66,W*0.66,WindowBase,WindowTop,Glass);
      Side(F*0.88,F*0.61,-W*0.805,WindowBase,WindowTop,Glass);
      Side(F*0.88,F*0.61,W*0.805,WindowBase,WindowTop,Mix(Glass,clWhite,0.13));
      Solid(F*0.43,B*0.88,-W*0.83,W*0.83,H,CargoH,RGB(154,164,169));
      for Part:=0 to 6 do begin
        Axle:=F*0.38+(B*0.82-F*0.38)*Part/7;
        Edge(Axle,Axle,-W*0.80,W*0.80,CargoH+0.001,RGB(88,107,119),0.004);
        Side(Axle+0.15,Axle-0.15,-W*0.835,H+0.006,CargoH,RGB(84,103,113));
        Side(Axle+0.15,Axle-0.15,W*0.835,H+0.006,CargoH,RGB(123,140,146));
      end;
      EndFace(B*0.885,-W*0.73,W*0.73,H+0.008,CargoH-0.008,RGB(132,144,153));
      Side(B*0.89,B*0.89+0.10,0,H+0.012,CargoH-0.012,RGB(65,82,98));
      // 縦の扉枠と屋根境界で、高さを長い屋根面から読み分けられるようにする。
      Post(B*0.89,-W*0.77,H+0.008,CargoH,RGB(184,198,201),0.003);
      Post(B*0.89,W*0.77,H+0.008,CargoH,RGB(79,101,112),0.003);
      Edge(B*0.89,B*0.89,-W*0.77,W*0.77,CargoH,RGB(188,201,204),0.003);
      Edge(B*0.89,B*0.89,-W*0.77,W*0.77,H+0.009,RGB(214,176,81),0.008);
      if Pose.Kind>=4 then begin
        for Part:=0 to Max(0,3-Stage) do Solid(
        F*0.34+(B*0.40-F*0.34)*Part/4,F*0.25+(B*0.43-F*0.25)*Part/4,
        -W*0.85,W*0.85,CargoH,CargoH+0.010,RGB(98,105,109));
      end;
    end else if Pose.Kind=2 then begin
      CabH:=0.255;
      DamageD:=B*0.765;DamageBase:=H+0.018;DamageTop:=CabH-0.025;
      Solid(F*0.82,B*0.76,-W*0.83,W*0.83,H,CabH,Body);
      EndFace(B*0.765,-W*0.70,W*0.70,0.135,0.230,Glass);
      for Part:=1 to 5 do begin Axle:=F+(B-F)*Part/6;
        Side(Axle+0.8,Axle-0.8,-W*0.835,0.135,0.230,Glass);
        Side(Axle+0.8,Axle-0.8,W*0.835,0.135,0.230,Mix(Glass,clWhite,0.12));
      end;
      Post(B*0.765,-W*0.80,H,CabH,Mix(Body,clWhite,0.27),0.003);
      Post(B*0.765,W*0.80,H,CabH,Mix(Body,clBlack,0.30),0.003);
    end else begin
      CabH:=0.105;
      if Pose.Kind=1 then begin
        CabH:=0.170;
        if Pose.Role=0 then CabH:=0.130; // 細い黄色バンだけを低くし、大型敵の比率は保つ。
      end;
      Cabin(F*0.44,B*0.36,W*0.72,H+0.001,CabH,Body);
      Edge(F*0.50,F*0.85,0,0,H+0.002,Mix(Body,clWhite,0.38),0.010);
      if Pose.Role=2 then begin
        Solid(B*0.64,B*0.70,-W*0.90,W*0.90,H+0.006,H+0.019,RGB(29,72,95));
        Edge(F*0.60,F*0.80,0,0,H+0.004,RGB(160,232,236),0.014);
      end;
    end;
    C:=RGB(255,109,93);
    if Pose.Role=0 then
    if Plan.Traffic[Pose.Index].RelativeSpeed>Plan.TopSpeed then C:=RGB(255,247,192);
    EndFace(B*0.945,-W*0.79,-W*0.35,0.028,0.039,C);
    EndFace(B*0.945,W*0.35,W*0.79,0.028,0.039,C);
    EndFace(B*0.95,-W*0.35,W*0.35,0.015,0.024,RGB(41,51,61));
    if Pose.Role=2 then begin
      Part:=Plan.HitBefore(Clock);
      if Part>=0 then
      if (Clock>Plan.Hits[Part].Time+0.018) and (Clock<Plan.Hits[Part].Time+0.25) then begin
        Edge(B,B-8,-W*0.5,-W*0.5,0.014,RGB(255,214,113),0.012);
        Edge(B,B-8,W*0.5,W*0.5,0.014,RGB(255,214,113),0.012);
      end;
    end;
    if (Pose.Role<>2) and (Pose.Damage>0) then for Part:=0 to Min(4,Stage+1) do begin
      C:=RGB(47,49,58);
      // 共通の高さは小型車の屋根より上に浮く。車種ごとの後面内へ傷を付ける。
      MarkH:=DamageBase+(DamageTop-DamageBase)*(Part+1)/6;
      Edge(DamageD,DamageD,-W*0.45,W*0.35,MarkH,C,0.004);
    end;
  end;

begin
  Clock:=EnsureRange(Time,0.0,Plan.EndTime);
  Scale:=Min(Width/1.6,Height);
  Left:=(Width-1.6*Scale)/2;
  Top:=(Height-Scale)/2;
  Camera:=Plan.DistanceAt(Clock);
  Speed:=Plan.SpeedAt(Clock)/Plan.TopSpeed;
  Count:=0;
  First:=Max(0,Plan.TrafficBefore(Clock-1.11)+1);
  Last:=Plan.TrafficBefore(Clock+2.81);
  for I:=First to Last do begin
    if (Clock<Plan.Traffic[I].Spawn) or (Clock>Plan.Traffic[I].Clear) then Continue;
    K:=Plan.Traffic[I].Shunt;
    if K>=0 then if Clock>Plan.Shunts[K].Time+0.85 then Continue;
    Add(Plan.TrafficAt(I,Clock));
  end;
  First:=Max(0,Plan.EnemyBefore(Clock-1.30)+1);
  Last:=Plan.EnemyBefore(Clock+3.81);
  for I:=First to Last do begin E:=Plan.Enemies[I];
    if (Clock<E.Spawn) or (Clock>E.Clear) then Continue;
    Add(Plan.EnemyAt(I,Clock));
  end;
  // Boss lifetimes exceed the short normal-enemy lookup window.
  for I:=0 to High(Plan.Bosses) do begin K:=Plan.Bosses[I].Enemy;
    if (K>=First) and (K<=Last) then Continue;
    if K<0 then Continue;
    E:=Plan.Enemies[K];
    if (Clock>=E.Spawn) and (Clock<=E.Clear) then Add(Plan.EnemyAt(K,Clock));
  end;
  Add(Plan.HeroAt(Clock));
  for I:=1 to Count-1 do begin Temporary:=Cars[I];
    J:=I-1;
    while (J>=0) and (Cars[J].Distance<Temporary.Distance) do begin Cars[J+1]:=Cars[J];
      Dec(J);
    end;
    Cars[J+1]:=Temporary;
  end;
  for I:=0 to Count-1 do begin Pose:=Cars[I];
    Vehicle;
  end;
  DrawRaceContactEffects(Plan,Surface,Clock,Width,Height);
  if Speed>0.65 then for I:=0 to 27 do begin U:=Frac(Camera*0.025+I*0.618);
    Y:=0.40+0.60*U;
    Line(0.05+0.09*U,Y,0.01+0.11*U,Y+0.075*Speed,RGB(205,229,217),0.0015);
    Line(1.55-0.09*U,Y,1.59-0.11*U,Y+0.075*Speed,RGB(205,229,217),0.0015);
  end;
  Health:=Plan.BossHealth(Clock);
  if Health>=0 then begin Box(0.53,0.033,1.12,0.063,RGB(44,43,66));
    Box(0.535,0.038,0.535+0.58*Health,0.058,RGB(227,164,109));
  end;
end;
end.
