unit RhythmPinballScene;
// Draw the same cabinet and contact geometry at every time and aspect ratio.
interface

uses RhythmPinballPlan, RhythmRenderSurface, RhythmAnimation;

type
  TPinballView = record
    Scale, Left, Top: Double;
  end;

  TPinballCamera = class
  private
    FPlan: TPinballPlan; // Borrowed from the animation scene.
    FHeight, FLastSample: Double;
    FKeys: TArray<Double>;
    procedure BuildTrack(ViewHeight: Double);
    function CenterAt(Time: Double): Double;
  public
    constructor Create(Plan: TPinballPlan);
    function ViewAt(Time: Double; Width, Height: Integer): TPinballView;
  end;

procedure DrawFixedPinball(Plan: TPinballPlan; Camera: TPinballCamera;
  Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);

implementation

uses System.Math, System.Types, Winapi.Windows, Vcl.Graphics, RhythmBallGeometry;

const
  ShotTop = -0.033;
  ShotBottom = 1.71;
  WideMinimumHeight = 0.67;
  TrackStep = 1/60;
  EdgeReserve = 0.083;
  ContactLead = 0.16;

constructor TPinballCamera.Create(Plan: TPinballPlan);
begin
  inherited Create;
  FPlan := Plan;
end;

procedure TPinballCamera.BuildTrack(ViewHeight: Double);
var
  FloorAt, CeilingAt, Lower, Upper, Track: TArray<Double>;
  I,J,K,N,Radius,Iterations: Integer;
  HeightHalf, MinCenter, MaxCenter, Y, LowSpeed, HighSpeed, Speed, StepLimit: Double;
  Center, Weight, WeightSum, AverageDistance: Double;
  T, Age, Amount, ContactTop, ContactBottom, FitLower, FitUpper, Reserve: Double;
  Hit: TPinContact;

  function Feasible(SpeedLimit: Double): Boolean;
  var K: Integer; Advance: Double;
  begin
    Advance := SpeedLimit*TrackStep;
    Lower[N] := FloorAt[N];
    Upper[N] := CeilingAt[N];
    for K := N-1 downto 0 do begin
      Lower[K] := Max(FloorAt[K],Lower[K+1]-Advance);
      Upper[K] := Min(CeilingAt[K],Upper[K+1]+Advance);
      if Lower[K]>Upper[K] then Exit(False);
    end;
    Result := True;
  end;

begin
  HeightHalf := ViewHeight*0.5;
  MinCenter := ShotTop+HeightHalf;
  MaxCenter := ShotBottom-HeightHalf;
  N := Ceil(FPlan.EndTime/TrackStep);
  FLastSample := N*TrackStep;
  SetLength(FloorAt,N+1);
  SetLength(CeilingAt,N+1);
  SetLength(Lower,N+1);
  SetLength(Upper,N+1);
  SetLength(Track,N+1);
  SetLength(FKeys,N+1);
  for I := 0 to N do begin
    T := I*TrackStep;
    Y := FPlan.PositionAt(T).Y;
    // The shooter lane needs extra room during the initial climb.
    Reserve := EdgeReserve-0.025*EnsureRange((0.85-T)/0.15,0.0,1.0);
    FloorAt[I] := EnsureRange(Y-HeightHalf+Reserve,MinCenter,MaxCenter);
    CeilingAt[I] := EnsureRange(Y+HeightHalf-Reserve,MinCenter,MaxCenter);
    for K := FPlan.Before(T+ContactLead) downto 0 do begin
      Hit := FPlan.Contact[K];
      if Hit.Time<T-ContactLead then Break;
      Age := Abs(T-Hit.Time);
      if (Age>=ContactLead) or (Hit.Source<0) then Continue;
      if Hit.Body<PIN_BUMPERS then begin
        ContactTop := PinBumper(Hit.Body).Y-PinBumperRadius(Hit.Body);
        ContactBottom := ContactTop+2*PinBumperRadius(Hit.Body);
      end else if Hit.Body<PIN_KICKER then begin
        ContactTop := 1.29;
        ContactBottom := 1.50;
      end else begin
        ContactTop := PinKicker.Y-0.048;
        ContactBottom := PinKicker.Y+0.048;
      end;
      // Frame the struck mechanism as well as the ball near an impact.
      Amount := 1-Age/ContactLead;
      Amount := Amount*Amount*(3-2*Amount);
      FitLower := Max(FloorAt[I],EnsureRange(Y+(ContactBottom-Y)*Amount-HeightHalf+0.057,MinCenter,MaxCenter));
      FitUpper := Min(CeilingAt[I],EnsureRange(Y+(ContactTop-Y)*Amount+HeightHalf-0.057,MinCenter,MaxCenter));
      if FitLower<=FitUpper then begin
        FloorAt[I] := FitLower;
        CeilingAt[I] := FitUpper;
      end;
    end;
  end;

  // Propagate future margins backwards so a rapid launch can start the camera
  // moving before the ball is near a screen edge.
  Speed := 1.15;
  if not Feasible(Speed) then begin
    LowSpeed := Speed;
    HighSpeed := 6.0;
    for Iterations := 1 to 12 do begin
      Speed := (LowSpeed+HighSpeed)*0.5;
      if Feasible(Speed) then HighSpeed := Speed else LowSpeed := Speed;
    end;
    Speed := HighSpeed;
    Feasible(Speed);
  end;
  StepLimit := Speed*TrackStep;
  Center := EnsureRange(FPlan.PositionAt(0).Y-0.12,Lower[0],Upper[0]);
  for I := 0 to N do begin
    // Reframe with some spare room so a slight reflection near the margin
    // does not immediately trigger another camera movement.
    if Center<Lower[I] then Center := Min(Upper[I],Min(Center+StepLimit,Lower[I]+0.060))
    else if Center>Upper[I] then Center := Max(Lower[I],Max(Center-StepLimit,Upper[I]-0.060));
    Track[I] := Center;
  end;

  // Smooth the planned translations while retaining the spare space around the
  // ball. The cubic sampling below adds at most one more step of displacement.
  Radius := 8;
  while Radius>0 do begin
    AverageDistance := Radius*(Radius+2)/(3*(Radius+1));
    if StepLimit*(AverageDistance+1)<=EdgeReserve-PIN_RADIUS-0.011 then Break;
    Dec(Radius);
  end;
  for I := 0 to N do begin
    Center := 0;
    WeightSum := 0;
    for J := -Radius to Radius do begin
      Weight := Radius+1-Abs(J);
      Center := Center+Track[EnsureRange(I+J,0,N)]*Weight;
      WeightSum := WeightSum+Weight;
    end;
    FKeys[I] := Center/WeightSum;
  end;
  FHeight := ViewHeight;
end;

function TPinballCamera.CenterAt(Time: Double): Double;
var I,N: Integer; Sample,U,V: Double;
begin
  N := High(FKeys);
  Sample := EnsureRange(Time,0.0,FLastSample)/TrackStep;
  I := Min(Trunc(Sample),N);
  U := Sample-I;
  V := 1-U;
  // Uniform cubic B-spline: position, velocity and acceleration are continuous.
  Result := (V*V*V*FKeys[Max(0,I-1)]+(4-6*U*U+3*U*U*U)*FKeys[I]+
    (4-6*V*V+3*V*V*V)*FKeys[Min(N,I+1)]+U*U*U*FKeys[Min(N,I+2)])/6;
end;

function TPinballCamera.ViewAt(Time: Double; Width, Height: Integer): TPinballView;
var ViewHeight: Double;
begin
  if Width<=Height then begin
    Result.Scale := Min(Width/1.12,Height/1.78);
    Result.Top := (Height-Result.Scale*PIN_HEIGHT)*0.5;
  end else begin
    Result.Scale := Min(Width/1.10,Height/WideMinimumHeight);
    ViewHeight := Height/Result.Scale;
    if Abs(FHeight-ViewHeight)>1E-9 then BuildTrack(ViewHeight);
    Result.Top := Height*0.5-CenterAt(Time)*Result.Scale;
  end;
  Result.Left := (Width-Result.Scale*PIN_WIDTH)*0.5;
end;

procedure DrawFixedPinball(Plan: TPinballPlan; Camera: TPinballCamera;
  Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
var
  Scale, Left, Top, Clock, Glow, T, X, Y: Double;
  View: TPinballView;
  A,B,P,Arm: TBallPoint;
  I,J: Integer;
  Shade, Accent: TColor;
  function Screen(const V: TBallPoint): TPointF;
  begin
    Result := PointF(Left+V.X*Scale,Top+V.Y*Scale);
  end;
  procedure Box(X1,Y1,X2,Y2: Double; Color: TColor);
  begin
    Surface.FillRect(Left+X1*Scale,Top+Y1*Scale,Left+X2*Scale,Top+Y2*Scale,Color);
  end;
  procedure Stroke(const FromPoint,ToPoint: TBallPoint; Color: TColor; Width: Double);
  var U,V: TPointF;
  begin
    U := Screen(FromPoint);
    V := Screen(ToPoint);
    Surface.Line(U.X,U.Y,V.X,V.Y,Color,Max(0.8,Width*Scale));
  end;
  procedure Line(X1,Y1,X2,Y2: Double; Color: TColor; Width: Double);
  begin
    Stroke(BallPoint(X1,Y1),BallPoint(X2,Y2),Color,Width);
  end;
  procedure Disc(const V: TBallPoint; Radius: Double; Color: TColor; Opacity: Double = 1);
  var U: TPointF;
  begin
    U := Screen(V);
    Surface.Circle(U.X,U.Y,Radius*Scale,Color,True,1,Opacity);
  end;
  procedure Ring(const V: TBallPoint; Radius, Width: Double; Color: TColor; Opacity: Double = 1);
  var U: TPointF;
  begin
    U := Screen(V);
    Surface.Circle(U.X,U.Y,Radius*Scale,Color,False,Max(1.0,Width*Scale),Opacity);
  end;
  procedure Quad(X1,Y1,X2,Y2,X3,Y3,X4,Y4: Double; Color: TColor);
  begin
    Surface.FillQuad(Screen(BallPoint(X1,Y1)),Screen(BallPoint(X2,Y2)),
      Screen(BallPoint(X3,Y3)),Screen(BallPoint(X4,Y4)),Color);
  end;
  procedure Rail(X1,Y1,X2,Y2: Double);
  begin
    Line(X1+0.004,Y1+0.005,X2+0.004,Y2+0.005,RGB(10,19,26),0.019);
    Line(X1,Y1,X2,Y2,RGB(123,151,153),0.012);
    Line(X1-0.002,Y1,X2-0.002,Y2,RGB(212,226,208),0.003);
  end;
  procedure Bolt(X1,Y1: Double);
  begin
    Disc(BallPoint(X1,Y1),0.011,RGB(18,24,28));
    Disc(BallPoint(X1,Y1-0.0018),0.007,RGB(178,168,150));
    Line(X1-0.004,Y1+0.002,X1+0.004,Y1-0.003,RGB(57,61,52),0.0018);
  end;
  procedure InsertLamp(X1,Y1: Double; Color: TColor);
  var Lamp: TBallPoint;
  begin
    Lamp := BallPoint(X1,Y1);
    Disc(Lamp,0.014,RGB(19,43,48));
    Disc(Lamp,0.010,Color,0.73);
    Ring(Lamp,0.014,0.002,RGB(151,154,111),0.67);
    Disc(BallPoint(X1-0.003,Y1-0.003),0.003,RGB(232,223,169),0.69);
  end;
begin
  Clock := Max(0.0,Frame.Time);
  View := Camera.ViewAt(Clock,Frame.Width,Frame.Height);
  Scale := View.Scale;
  Left := View.Left;
  Top := View.Top;
  Surface.FillRect(0,0,Frame.Width,Frame.Height,RGB(11,17,23));
  Box(-0.032,-0.022,1.044,1.705,RGB(5,9,15));
  Box(-0.027,-0.027,1.027,1.69,RGB(83,44,33));
  Box(-0.019,-0.017,1.019,1.686,RGB(130,76,47));
  for I := 0 to 8 do begin
    X := -0.024+I*0.004;
    Shade := RGB(71+I mod 3*12,37+I mod 4*9,27+I mod 5*4);
    Line(X,0,X,1.682,Shade,0.003);
    Line(1-X,0,1-X,1.682,Shade,0.003);
  end;
  Box(0.014,0.011,0.987,1.659,RGB(10,31,38));
  for I := 0 to 39 do begin
    T := I/40;
    Box(0.031,0.068+T*1.475,0.968,0.068+(I+1)/40*1.475,RGB(13+I div 4,39+I div 3,43+I div 3));
  end;
  for I := 0 to 8 do for J := 0 to 16 do begin
    X := 0.110+I*0.085;
    Y := 0.285+J*0.058;
    Disc(BallPoint(X+0.015*(J mod 2),Y),0.0024,RGB(68,96,85),0.55);
  end;
  // Painted lanes and sunburst. These marks lie flat under the ball and guides.
  Quad(0.116,0.984,0.226,0.843,0.403,1.240,0.334,1.284,RGB(32,86,86));
  Quad(0.782,0.861,0.817,0.952,0.593,1.307,0.523,1.237,RGB(32,86,86));
  for I := 0 to 5 do begin
    X := 0.240+I*0.086;
    Line(X,0.841,0.489+(X-0.489)*0.32,1.156,RGB(53,109,102),0.004);
  end;
  Ring(BallPoint(0.486,1.048),0.102,0.0038,RGB(128,116,69),0.80);
  Ring(BallPoint(0.486,1.048),0.112,0.0018,RGB(96,133,114),0.88);
  for I := 0 to 2 do begin
    X := 0.418+I*0.065;
    Quad(X,1.033,X+0.022,1.067,X,1.099,X-0.022,1.067,RGB(181,122,58));
  end;
  for I := 0 to 4 do InsertLamp(0.386+I*0.052,1.219,RGB(227,147,66));
  for I := 0 to 2 do begin
    InsertLamp(0.211+0.025*I,1.228+0.028*I,RGB(51,181,166));
    InsertLamp(0.760-0.025*I,1.228+0.028*I,RGB(51,181,166));
  end;
  // Full-height collision rails and the separate shooter lane.
  Box(0.884,0.301,0.970,1.576,RGB(12,30,37));
  Box(0.896,0.310,0.959,1.565,RGB(22,51,53));
  Rail(PIN_LEFT-PIN_RADIUS,0.123,PIN_LEFT-PIN_RADIUS,1.529);
  Rail(PIN_RIGHT+PIN_RADIUS,0.123,PIN_RIGHT+PIN_RADIUS,1.526);
  Rail(0.959,0.270,0.959,1.544);
  Rail(0.892,0.274,0.892,1.543);
  for I := 1 to 32 do begin
    A := PinLaunchGuide((I-1)/32);
    B := PinLaunchGuide(I/32);
    Arm := BallUnit(BallSub(B,A));
    P := BallScale(BallPoint(-Arm.Y,Arm.X),0.0335);
    Stroke(BallAdd(A,P),BallAdd(B,P),RGB(139,164,164),0.008);
    Stroke(BallSub(A,P),BallSub(B,P),RGB(182,188,165),0.007);
  end;
  Box(0.912,1.475,0.942,1.619,RGB(120,144,143));
  for I := 0 to 6 do Line(0.910,1.490+I*0.013,0.946,1.484+I*0.013,RGB(36,58,62),0.005);
  Box(0.902,1.596,0.953,1.631,RGB(170,83,60));
  // Apron and central drain cutout.
  Quad(0.046,1.486,0.361,1.557,0.441,1.630,0.046,1.630,RGB(46,65,64));
  Quad(0.875,1.486,0.596,1.557,0.526,1.630,0.875,1.630,RGB(46,65,64));
  Box(0.423,1.538,0.544,1.643,RGB(7,12,18));
  Line(0.060,1.529,0.381,1.598,RGB(164,152,86),0.006);
  Line(0.861,1.529,0.579,1.598,RGB(164,152,86),0.006);
  Box(0.026,1.645,0.975,1.66,RGB(174,159,124));
  // Metal posts, radial bumpers, and the kicker socket share the planned locations.
  for I := 0 to PIN_BUMPERS-1 do begin
    P := PinBumper(I);
    T := PinBumperRadius(I);
    Glow := Plan.Flash(I,Clock);
    if I=2 then Accent := RGB(208,104,76) else Accent := RGB(207,155,73);
    if Glow>0 then Disc(P,T+0.041+Glow*0.022,Accent,0.32*Glow);
    Disc(BallAdd(P,BallPoint(0.004,0.007)),T+0.006,RGB(11,26,30));
    Disc(P,T,RGB(175,188,167));
    Disc(P,T-0.007,RGB(60,78,74));
    Disc(P,T-0.015,Accent);
    Disc(BallAdd(P,BallPoint(-0.004,-0.005)),T-0.022,RGB(249,218,154),0.57+0.41*Glow);
    Ring(P,T-0.031,0.004,RGB(167,104,50));
    for J := 0 to 5 do begin
      X := Cos(J*Pi/3)*(T-0.028);
      Y := Sin(J*Pi/3)*(T-0.028);
      Disc(BallAdd(P,BallPoint(X,Y)),0.006,RGB(240,227,188));
    end;
    Disc(P,0.013,RGB(43,70,67));
    Disc(BallAdd(P,BallPoint(-0.004,-0.006)),0.005,RGB(224,238,179));
  end;
  P := PinKicker;
  Disc(P,0.048,RGB(118,142,128));
  Disc(P,0.038,RGB(7,19,24));
  Ring(P,0.035,0.002,RGB(164,177,115));
  Glow := Plan.Flash(PIN_KICKER,Clock);
  if Glow>0 then Ring(P,0.048+0.03*(1-Glow),0.004,RGB(95,243,193),Glow);
  for I := PIN_LEFT_FLIPPER to PIN_RIGHT_FLIPPER do begin
    A := PinPivot(I);
    Arm := PinArm(I,Plan.FlipperAngle(I,Clock));
    B := BallAdd(A,BallScale(Arm,PIN_FLIPPER_LENGTH));
    Glow := Plan.Flash(I,Clock);
    if Glow>0 then Stroke(A,B,RGB(180,133,70),0.046);
    Stroke(BallAdd(A,BallPoint(0.004,0.005)),BallAdd(B,BallPoint(0.004,0.005)),RGB(8,17,23),0.047);
    Stroke(A,B,RGB(148,68,60),2*PIN_FLIPPER_RADIUS);
    Disc(A,PIN_FLIPPER_RADIUS,RGB(148,68,60));
    Disc(B,PIN_FLIPPER_RADIUS,RGB(148,68,60));
    Stroke(BallAdd(A,BallPoint(0,-0.002)),BallAdd(B,BallPoint(0,-0.002)),RGB(242,215,151),0.022);
    Disc(A,0.012,RGB(82,91,86));
    Disc(BallAdd(A,BallPoint(-0.003,-0.003)),0.006,RGB(232,236,200));
  end;
  for I := 0 to 5 do begin
    Y := 0.052+I*0.306;
    Bolt(0.013,Y);
    Bolt(0.986,Y);
  end;
  // Ball shadow and highlights are drawn with the same fixed-radius silhouette.
  if not Frame.BackgroundOnly then begin
    P := Plan.PositionAt(Clock);
    Disc(BallAdd(P,BallPoint(0.007,0.009)),PIN_RADIUS+0.003,RGB(5,14,19),0.75);
    Disc(P,PIN_RADIUS,RGB(116,153,161));
    Disc(BallAdd(P,BallPoint(-0.002,-0.003)),0.018,RGB(188,217,215));
    Disc(BallAdd(P,BallPoint(-0.005,-0.006)),0.012,RGB(235,244,224));
    Disc(BallAdd(P,BallPoint(-0.008,-0.009)),0.0055,clWhite);
  end;
end;

end.
