unit RhythmRunnerScene;
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmRunnerPlan;
type TRunnerAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;FRef:TRhythmPlanRef;FPlan:TRunnerPlan;FAttempt,FError:string;
  public
    destructor Destroy;override;
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;
destructor TRunnerAnimation.Destroy;begin FPlan.Free;inherited;end;
procedure TRunnerAnimation.SetReference(const Ref:TRhythmPlanRef);begin FRef:=Ref;end;
function TRunnerAnimation.Notice:string;begin Result:=FError;end;
procedure TRunnerAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;FAttempt:=Key;FreeAndNil(FPlan);FError:='';if FAudio=nil then Exit;
  try FPlan:=TRunnerPlan.Load(FRef,FAudio,Frame.Direction);except on E:Exception do FError:=E.Message;end;
end;
procedure TRunnerAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Scale,Left,Top,Camera,Clock,GoalX,GoalY,Age,Phase,Entry,T,Leg,Thickness:Double;
  I,J,First,Last:Integer;P:TRunnerPoint;Pad:TRunnerPlatform;Pulse:TRunnerPulse;Tint:TColor;
  procedure Line(X1,Y1,X2,Y2:Double;Color:TColor;Width:Double);
  begin Surface.Line(Left+(X1-Camera)*Scale,Top+Y1*Scale,Left+(X2-Camera)*Scale,Top+Y2*Scale,Color,Max(1,Width*Scale));end;
  procedure Circle(X,Y,R:Double;Color:TColor;Filled:Boolean=True);
  begin Surface.Circle(Left+(X-Camera)*Scale,Top+Y*Scale,R*Scale,Color,Filled,Max(1,Scale*0.002));end;
  procedure Background;
  var N,Base:Integer;X,Y,Parallax:Double;
  begin
    for N:=0 to 31 do Surface.Line(0,(N+0.5)*Frame.Height/32,Frame.Width,(N+0.5)*Frame.Height/32,
      RGB(20+N,33+N,62+N),Frame.Height/32+1);
    Circle(Camera+1.43,0.18,0.08,RGB(237,207,133));
    Parallax:=Camera*0.12/0.26;Base:=Floor(Parallax);
    for N:=-2 to 10 do begin
      X:=Camera+N*0.26-(Parallax-Base)*0.26;Y:=0.52+0.035*Sin((N+Base)*1.7);
      Circle(X,Y,0.25,RGB(47,77,98));
    end;
    Parallax:=Camera*0.27/0.20;Base:=Floor(Parallax);
    for N:=-2 to 12 do begin
      X:=Camera+N*0.20-(Parallax-Base)*0.20;Y:=0.76+0.045*Sin((N+Base)*2.1);
      Circle(X,Y,0.23,RGB(35,92,91));
    end;
  end;
begin
  Scale:=Min(Frame.Width/1.8,Frame.Height/1.0);Left:=(Frame.Width-1.8*Scale)/2;Top:=(Frame.Height-Scale)/2;
  Clock:=0;if FPlan<>nil then Clock:=Min(Frame.Time,FPlan.EndTime);
  Camera:=RUN_SPEED*Clock-0.42;
  if FPlan<>nil then Camera:=RUN_SPEED*Min(Clock,FPlan.GoalTime)-0.42;
  Background;
  if FPlan<>nil then begin
    First:=FPlan.FirstPlatform(Camera-0.08);
    for I:=First to Min(FPlan.PlatformCount-1,First+255) do begin
      Pad:=FPlan.Platform[I];if Pad.Left>Camera+1.86 then Break;
      Thickness:=Min(0.055,(Pad.Right-Pad.Left)*0.65);Tint:=RGB(107,166,121);
      Line(Max(Pad.Left,Camera-0.03)+Thickness/2,Pad.Y+Thickness/2,Min(Pad.Right,Camera+1.83)-Thickness/2,Pad.Y+Thickness/2,RGB(80,111,117),Thickness);
      Line(Max(Pad.Left,Camera),Pad.Y,Min(Pad.Right,Camera+1.8),Pad.Y,Tint,0.006);
      if Pad.Right-Pad.Left>0.11 then begin
        Line(Max(Pad.Left+0.015,Camera),Pad.Y+0.014,Min(Pad.Right-0.015,Camera+1.8),Pad.Y+0.014,RGB(177,213,151),0.003);
      end;
    end;
    GoalX:=RUN_SPEED*FPlan.GoalTime;GoalY:=FPlan.Step[FPlan.Count-1].Y;
    if FPlan.GoalTime>0 then begin
      Line(GoalX,GoalY,GoalX,GoalY-0.23,RGB(225,226,193),0.008);
      Line(GoalX,GoalY-0.23,GoalX+0.10,GoalY-0.19,RGB(255,184,91),0.025);
      Line(GoalX+0.10,GoalY-0.19,GoalX,GoalY-0.15,RGB(255,184,91),0.025);
      Age:=Clock-FPlan.GoalTime;
      if (Age>=0) and (Age<0.70) then for J:=0 to 15 do begin
        T:=J*2.39996;Circle(GoalX+Cos(T)*Age*0.3,GoalY-0.12+Sin(T)*Age*0.25+Age*Age*0.2,0.004,RGB(255,223,137));
      end;
    end;
    Last:=FPlan.PulseBefore(Clock);First:=Max(0,Last-47);
    for I:=Last downto First do begin
      Pulse:=FPlan.Pulse[I];Age:=Clock-Pulse.Time;if Age>0.30 then Break;
      if Age>=0 then begin
        Circle(RUN_SPEED*Pulse.Time,FPlan.Step[Pulse.Step].Y,0.012+Age*0.22,RGB(238,204,116),False);
        for J:=0 to 3 do Circle(RUN_SPEED*Pulse.Time+(J-1.5)*Age*0.12,FPlan.Step[Pulse.Step].Y-Age*0.22+Age*Age*0.45,0.003,RGB(196,232,167));
      end;
    end;
    if (FPlan.GoalTime>0) and (Frame.Time<FPlan.EndTime) then begin
      P:=FPlan.PositionAt(Clock);Entry:=FPlan.EntryDuration;
      if (Entry>0) and (Clock<Entry) then begin T:=Clock/Entry;P.X:=P.X-0.64*(1-T*T*(3-2*T));end;
      Phase:=Clock*Pi*9;Leg:=Sin(Phase)*0.027;
      if P.Airborne then Leg:=0.015;
      // Original scarfed courier: large light silhouette with articulated legs.
      Circle(P.X,P.Y-0.096,0.023,RGB(255,210,160));
      Line(P.X-0.015,P.Y-0.072,P.X+0.010,P.Y-0.043,RGB(82,191,214),0.033);
      Line(P.X-0.012,P.Y-0.070,P.X-0.062-0.008*Sin(Phase),P.Y-0.068,RGB(240,145,104),0.012);
      Line(P.X,P.Y-0.045,P.X-0.020-Leg,P.Y-0.023,RGB(177,232,229),0.010);
      Line(P.X-0.020-Leg,P.Y-0.023,P.X,P.Y,RGB(231,235,205),0.012);
      Line(P.X+0.003,P.Y-0.044,P.X+0.018+Leg,P.Y-0.020,RGB(103,181,202),0.010);
      Line(P.X+0.018+Leg,P.Y-0.020,P.X+0.026+Leg,P.Y-(0.008+0.008*Sin(Phase)),RGB(178,217,212),0.012);
      Circle(P.X+0.010,P.Y-0.100,0.003,RGB(32,54,72));
      Line(P.X+0.006,P.Y-0.066,P.X+0.030,P.Y-0.049+Leg*0.4,RGB(255,210,160),0.009);
    end;
  end;
  // Fixed horizontal stage, letterboxed for portrait/extreme aspect frames.
  if Left>0 then begin
    Surface.Line(Left/2,0,Left/2,Frame.Height,RGB(15,24,42),Left+1);
    Surface.Line(Frame.Width-Left/2,0,Frame.Width-Left/2,Frame.Height,RGB(15,24,42),Left+1);
  end;
  if Top>0 then begin
    Surface.Line(0,Top/2,Frame.Width,Top/2,RGB(15,24,42),Top+1);
    Surface.Line(0,Frame.Height-Top/2,Frame.Width,Frame.Height-Top/2,RGB(15,24,42),Top+1);
  end;
end;
end.
