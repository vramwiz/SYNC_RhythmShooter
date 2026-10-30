unit RhythmBallScene;
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmBallPlan;
type TBallAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;FRef:TRhythmPlanRef;FPlan:TRhythmBallPlan;FAttempt,FError:string;
  public
    destructor Destroy;override;
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics,RhythmBallGeometry;
destructor TBallAnimation.Destroy;begin FPlan.Free;inherited;end;
procedure TBallAnimation.SetReference(const Ref:TRhythmPlanRef);begin FRef:=Ref;end;
function TBallAnimation.Notice:string;begin Result:=FError;end;
procedure TBallAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;FAttempt:=Key;FreeAndNil(FPlan);FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TRhythmBallPlan.Load(FRef,FAudio,Frame.Direction);except on E:Exception do FError:=E.Message;end;
end;
procedure TBallAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Scale,Left,Top,W,H,Fade,Radius,Age,Power,Amount,Angle,Distance:Double;
  I,J,First,Last:Integer;P,Q,Center,Impact,A,B:TBallPoint;O:TBallObstacle;Pulse:TBallPulse;
  function Color(R,G,B:Integer;Opacity:Double=1):TColor;
  begin Opacity:=EnsureRange(Opacity,0.0,1.0);Result:=RGB(Round(7+(R-7)*Opacity),Round(13+(G-13)*Opacity),Round(29+(B-29)*Opacity));end;
  procedure Map(const V:TBallPoint;out X,Y:Double);
  begin
    if Frame.Direction=0 then begin X:=Left+V.X*Scale;Y:=Top+V.Y*Scale;end
    else begin X:=Left+(BALL_BOARD_HEIGHT-V.Y)*Scale;Y:=Top+V.X*Scale;end;
  end;
  procedure Line(const A,B:TBallPoint;Tint:TColor;Stroke:Double);
  var X1,Y1,X2,Y2:Double;
  begin Map(A,X1,Y1);Map(B,X2,Y2);Surface.Line(X1,Y1,X2,Y2,Tint,Max(1,Stroke*Scale));end;
  procedure Segment(X1,Y1,X2,Y2:Double;Tint:TColor;Stroke:Double);
  begin Line(BallPoint(X1,Y1),BallPoint(X2,Y2),Tint,Stroke);end;
  procedure Circle(const V:TBallPoint;R:Double;Tint:TColor;Filled:Boolean;Stroke:Double=0.002);
  var X,Y:Double;
  begin Map(V,X,Y);Surface.Circle(X,Y,R*Scale,Tint,Filled,Max(1,Stroke*Scale));end;
  procedure RingPart(const V:TBallPoint;R,StartAngle,Arc:Double;Tint:TColor;Stroke:Double);
  var K:Integer;A,B:TBallPoint;T:Double;
  begin
    A:=BallAdd(V,BallPoint(Cos(StartAngle)*R,Sin(StartAngle)*R));
    for K:=1 to 8 do begin T:=StartAngle+Arc*K/8;B:=BallAdd(V,BallPoint(Cos(T)*R,Sin(T)*R));Line(A,B,Tint,Stroke);A:=B;end;
  end;
  procedure Board;
  var K:Integer;Tint:TColor;
  begin
    // Recessed playfield, chamfered rails and light strips are outside the
    // planned collision area. They are decoration, not unplanned targets.
    for K:=0 to 9 do begin
      Segment(0.08,0.12+K*0.125,0.92,0.12+K*0.125,Color(15,29,47),0.001);
      Segment(0.12+K*0.084,0.08,0.12+K*0.084,1.32,Color(13,25,43),0.001);
    end;
    for K:=0 to 1 do begin
      if K=0 then Tint:=Color(22,50,72) else Tint:=Color(72,139,167);
      Segment(0.04,0.14,0.04,1.26,Tint,0.020-K*0.014);Segment(0.96,0.14,0.96,1.26,Tint,0.020-K*0.014);
      Segment(0.04,0.14,0.14,0.04,Tint,0.020-K*0.014);Segment(0.14,0.04,0.86,0.04,Tint,0.020-K*0.014);
      Segment(0.86,0.04,0.96,0.14,Tint,0.020-K*0.014);Segment(0.04,1.26,0.14,1.36,Tint,0.020-K*0.014);
      Segment(0.14,1.36,0.86,1.36,Tint,0.020-K*0.014);Segment(0.86,1.36,0.96,1.26,Tint,0.020-K*0.014);
    end;
    for K:=0 to 7 do begin
      Segment(0.04,0.22+K*0.13,0.04,0.27+K*0.13,Color(75,191,205,0.65),0.008);
      Segment(0.96,0.22+K*0.13,0.96,0.27+K*0.13,Color(75,191,205,0.65),0.008);
    end;
    Segment(0.18,1.33,0.40,1.33,Color(155,112,60),0.006);Segment(0.60,1.33,0.82,1.33,Color(155,112,60),0.006);
  end;
begin
  if Frame.Direction=0 then begin W:=BALL_BOARD_WIDTH;H:=BALL_BOARD_HEIGHT;end else begin W:=BALL_BOARD_HEIGHT;H:=BALL_BOARD_WIDTH;end;
  Scale:=Min(Frame.Width/(W+0.10),Frame.Height/(H+0.10));Left:=(Frame.Width-W*Scale)/2;Top:=(Frame.Height-H*Scale)/2;
  Board;
  if (FPlan=nil) or (FPlan.EndTime<=0) or (Frame.Time>=FPlan.EndTime+0.75) then Exit;
  Fade:=1;if Frame.Time>FPlan.EndTime then Fade:=1-(Frame.Time-FPlan.EndTime)/0.75;
  FPlan.VisibleObstacles(Frame.Time,First,Last);
  for I:=First to Last do begin
    O:=FPlan.Obstacle[I];if (Frame.Time<O.Spawn) or (Frame.Time>O.Retire) then Continue;
    Center:=ObstaclePoint(O,Frame.Time);Age:=Frame.Time-O.Hit;Radius:=O.Radius;
    Amount:=Fade;if O.Spawn>0 then Amount:=Amount*EnsureRange((Frame.Time-O.Spawn)/0.18,0.0,1.0);
    if (O.Kind=boBumper) or (Age<0) then begin
      if Age>=0 then Amount:=Amount*EnsureRange((O.Retire-Frame.Time)/0.28,0.0,1.0);
      if O.Kind=boBumper then begin
        Circle(Center,Radius*1.26,Color(29,84,112,Amount*0.5),False,0.004);
        Circle(Center,Radius,Color(40,92,122,Amount),True);
        Circle(Center,Radius,Color(110,213,231,Amount),False,0.005);
        Circle(Center,Radius*0.68,Color(15,44,69,Amount),True);
        RingPart(Center,Radius*0.81,Pi,Pi*0.8,Color(184,239,247,Amount),0.004);
        Circle(Center,Radius*0.38,Color(57,171,201,Amount),True);
        Circle(BallAdd(Center,BallPoint(-Radius*0.12,-Radius*0.12)),Radius*0.14,Color(221,254,255,Amount),True);
      end else begin
        Circle(Center,Radius,Color(102,58,47,Amount),True);
        Circle(Center,Radius,Color(250,157,86,Amount),False,0.004);
        Circle(Center,Radius*0.66,Color(50,30,42,Amount),True);
        for J:=0 to 5 do begin
          Angle:=J*Pi/3+Pi/6;A:=BallAdd(Center,BallPoint(Cos(Angle)*Radius*0.42,Sin(Angle)*Radius*0.42));
          B:=BallAdd(Center,BallPoint(Cos(Angle)*Radius*0.88,Sin(Angle)*Radius*0.88));Line(A,B,Color(194,111,74,Amount),0.006);
        end;
        Circle(Center,Radius*0.30,Color(255,199,105,Amount),True);
        Segment(Center.X-Radius*0.15,Center.Y,Center.X+Radius*0.15,Center.Y,Color(255,241,186,Amount),0.004);
      end;
      // The next hit is readable without illuminating every future obstacle.
      if (Age<0) and (Age>-0.42) then begin
        Power:=(1+Age/0.42)*Amount;
        Circle(Center,Radius*1.42,Color(221,228,172,Power*0.75),False,0.002);
      end;
    end;
  end;
  // Every source accent remains visible. Dense accents resonate from a shared
  // physical collision; they do not pretend the moving ball hits empty space.
  First:=Max(0,FPlan.PulseBefore(Frame.Time-0.65));Last:=FPlan.PulseBefore(Frame.Time);
  for I:=First to Last do begin
    Pulse:=FPlan.Pulse[I];O:=FPlan.Obstacle[Pulse.ContactIndex-1];Age:=Frame.Time-Pulse.Time;Radius:=O.Radius;
    if (Age>=0) and (Age<=0.65) then begin
      Power:=Sqr(1-Age/0.65)*Fade*(0.60+Pulse.Strength*0.40);
      Impact:=BallAdd(O.Center,BallScale(O.Normal,O.Radius));
      Circle(Impact,0.014+Age*(0.13+Pulse.Strength*0.12),Color(255,213,132,Power),False,0.004);
      if Age<0.12 then Circle(Impact,0.016+(0.12-Age)*0.20,Color(252,252,225,Power),True);
      if (O.Kind=boBreakable) and (Pulse.Time=O.Hit) then begin
        Circle(O.Center,Radius+Age*(0.22+Pulse.Strength*0.16),Color(255,147,82,Power*0.65),False,0.003);
        for J:=0 to 7+Round(Pulse.Strength*6) do begin
          Angle:=J*2.399963+I*0.73;Distance:=Age*(0.20+Pulse.Strength*0.24)*(0.7+(J mod 3)*0.18);
          A:=BallAdd(O.Center,BallPoint(Cos(Angle)*(Radius*0.6+Distance),Sin(Angle)*(Radius*0.6+Distance)+Age*Age*0.15));
          B:=BallAdd(A,BallPoint(Cos(Angle+Age*4)*0.012,Sin(Angle+Age*4)*0.012));
          Line(A,B,Color(255,170+(J mod 3)*20,94,Power),0.004);
        end;
      end else if O.Kind=boBumper then Circle(O.Center,Radius*0.62+Age*0.11,Color(174,248,255,Power),False,0.005);
    end;
  end;
  for I:=9 downto 1 do begin
    P:=FPlan.PositionAt(Max(0.0,Frame.Time-I*0.018));Q:=FPlan.PositionAt(Max(0.0,Frame.Time-(I-1)*0.018));
    Line(P,Q,Color(85,208,239,(1-I/11)*0.58*Fade),BALL_RADIUS*(1-I/11));
  end;
  P:=FPlan.PositionAt(Frame.Time);
  Circle(P,BALL_RADIUS*1.45,Color(47,115,149,Fade*0.65),True);
  Circle(P,BALL_RADIUS,Color(120,223,249,Fade),True);
  Circle(BallAdd(P,BallPoint(-BALL_RADIUS*0.20,-BALL_RADIUS*0.20)),BALL_RADIUS*0.62,Color(234,253,255,Fade),True);
end;
end.
