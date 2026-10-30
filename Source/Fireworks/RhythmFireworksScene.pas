unit RhythmFireworksScene;
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmFireworksPlan;
type TFireworksAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;FRef:TRhythmPlanRef;FPlan:TFireworksPlan;FAttempt,FError:string;
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
function Noise(Index,Salt:Cardinal):Double;
var V:Cardinal;
begin
  V:=Cardinal(((UInt64(Index)+1)*747796405+UInt64(Salt)*2891336453) and $FFFFFFFF);
  V:=Cardinal((UInt64(V xor (V shr 16))*2246822519) and $FFFFFFFF);V:=V xor (V shr 13);
  Result:=(V shr 8)/16777216.0;
end;
function FadeColor(Color:TColor;Amount:Double):TColor;
var C:Cardinal;
begin C:=ColorToRGB(Color);Amount:=EnsureRange(Amount,0.0,1.0);Result:=RGB(Round(7+(GetRValue(C)-7)*Amount),Round(13+(GetGValue(C)-13)*Amount),Round(29+(GetBValue(C)-29)*Amount));end;
function Palette(Hue:Integer):TColor;
begin
  case Hue mod 8 of
    0:Result:=RGB(255,199,92);1:Result:=RGB(92,231,255);2:Result:=RGB(255,126,193);3:Result:=RGB(119,151,255);
    4:Result:=RGB(142,255,155);5:Result:=RGB(255,125,97);6:Result:=RGB(205,145,255);
  else Result:=RGB(228,244,255);end;
end;
destructor TFireworksAnimation.Destroy;begin FPlan.Free;inherited;end;
procedure TFireworksAnimation.SetReference(const Ref:TRhythmPlanRef);begin FRef:=Ref;end;
function TFireworksAnimation.Notice:string;begin Result:=FError;end;
procedure TFireworksAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity) else Key:=Key+'|none';
  if Key=FAttempt then Exit;FAttempt:=Key;FreeAndNil(FPlan);FError:='';if FAudio=nil then Exit;
  try FPlan:=TFireworksPlan.Load(FRef,FAudio,Frame.Direction);except on E:Exception do FError:=E.Message;end;
end;
procedure TFireworksAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
const MaxClouds=128;
var W,H,S,Clock,Age,Opacity,Width,StepAge:Double;
  I,J,K,First,Last,Stride,Slots,Remaining,Rays,FlashBudget,RocketBudget:Integer;B:TFireworkBurst;
  P,Q:TFireworkPoint;Tint:TColor;Selected:Boolean;
  procedure Background;
  var N,M:Integer;U,V,Size,Brightness,BX,BW,BY:Double;
  begin
    for N:=0 to 31 do begin
      U:=N/31;Surface.Line(0,(N+0.5)*H/32,W,(N+0.5)*H/32,RGB(Round(4+U*8),Round(9+U*13),Round(24+U*15)),H/32+1);
    end;
    for N:=0 to 139 do begin
      U:=Noise(N,11);V:=Noise(N,23)*0.70;Size:=(0.55+(N mod 3)*0.42)*Max(0.8,S/720);
      Brightness:=0.45+Noise(N,61)*0.25+0.18*Sin(Clock*0.55+Noise(N,73)*Pi*2);
      Surface.Circle(U*W,V*H,Size,FadeColor(RGB(139,176,211),Brightness),True);
    end;
    // Distant city, followed by a dark foreground ridge. Both remain below the
    // sky in either composition; changing direction never turns the horizon sideways.
    BX:=0;N:=0;
    while (BX<1.02) and (N<80) do begin
      BW:=0.018+Noise(N,83)*0.027;BY:=0.79-Noise(N,97)*0.11;
      Surface.Line((BX+BW/2)*W,BY*H,(BX+BW/2)*W,H,RGB(7,15,24),BW*W+1);
      for M:=0 to 5 do if Noise(N*7+M,107)>0.53 then
        Surface.Line((BX+BW*0.34)*W,(BY+0.012+M*0.014)*H,(BX+BW*0.54)*W,(BY+0.012+M*0.014)*H,RGB(76,65,43),Max(1,S*0.0012));
      BX:=BX+BW+0.004;Inc(N);
    end;
    for N:=0 to 96 do begin
      U:=N/96;V:=0.895+Sin(N*0.13)*0.023+Sin(N*0.31)*0.010;
      Surface.Line(U*W,V*H,U*W,H,RGB(3,8,14),W/96+1);
    end;
  end;
  function Particle(Index:Integer;T:Double):TFireworkPoint;
  var Offset:TFireworkPoint;
  begin
    Offset:=FireworkSparkOffset(B,Index,T);
    Result.X:=B.X*W+Offset.X*S;Result.Y:=B.Y*H+Offset.Y*S;
  end;
begin
  W:=Frame.Width;H:=Frame.Height;S:=Min(W,H);Clock:=0;
  if FPlan<>nil then Clock:=Min(Frame.Time,FPlan.EndTime);
  Background;
  if (FPlan=nil) or (Frame.Time>=FPlan.EndTime) then Exit;
  FPlan.VisibleRange(Frame.Time,First,Last);Remaining:=800+FPlan.Richness*24;FlashBudget:=256;RocketBudget:=128;
  Stride:=Max(1,Ceil((Last-First+1)/MaxClouds));Slots:=Max(1,(Last-First+Stride) div Stride);
  for I:=First to Last do begin
    B:=FPlan.Burst[I];Age:=Frame.Time-B.Time;Selected:=((I-First) mod Stride)=0;
    Rays:=0;
    if Selected then begin Rays:=Min(B.Rays,Remaining div Max(1,Slots));Dec(Slots);end;
    if Frame.Time<B.LaunchTime then Continue;
    if Age<0 then begin
      if RocketBudget<=0 then Continue;Dec(RocketBudget);Tint:=Palette(0);
      P:=FireworkRocketAt(B,Frame.Time);
      for K:=1 to 4 do begin
        Q:=FireworkRocketAt(B,Max(B.LaunchTime,Frame.Time-K*0.035));
        Surface.Line(P.X*W,P.Y*H,Q.X*W,Q.Y*H,FadeColor(Tint,(1-K/5)*0.75),Max(1,S*0.002));P:=Q;
      end;
      P:=FireworkRocketAt(B,Frame.Time);Surface.Circle(P.X*W,P.Y*H,Max(1.2,S*0.0025),RGB(255,235,181),True);Continue;
    end;
    if Age>B.Lifetime then Continue;
    if (Age<0.14) and (FlashBudget>0) then begin
      Dec(FlashBudget);Opacity:=(1-Age/0.14)*(0.55+B.Strength*0.45);
      Surface.Circle(B.X*W,B.Y*H,S*(0.006+Age*0.10),FadeColor(RGB(255,247,216),Opacity),True);
      Surface.Circle(B.X*W,B.Y*H,S*(0.012+Age*0.33),FadeColor(Palette(B.Hue),Opacity*0.65),False,Max(1,S*0.002));
    end;
    if Rays<=0 then Continue;Dec(Remaining,Rays);Tint:=Palette(B.Hue);
    Opacity:=Power(EnsureRange(1-Age/B.Lifetime,0.0,1.0),0.85);
    for J:=0 to Rays-1 do begin
      P:=Particle(J,Age);Width:=Max(0.7,S*(0.0011+B.Strength*0.0008));
      for K:=1 to 3 do begin
        StepAge:=Max(0.0,Age-K*0.035);Q:=Particle(J,StepAge);
        Surface.Line(P.X,P.Y,Q.X,Q.Y,FadeColor(Tint,Opacity*(1-K/4)*0.78),Width);P:=Q;
      end;
      P:=Particle(J,Age);Surface.Circle(P.X,P.Y,Width,FadeColor(Tint,Opacity*(0.83+0.17*Sin(Age*11+J))),True);
      if (J mod 7=0) and (Age<0.8) then Surface.Circle(P.X,P.Y,Width*0.45,FadeColor(RGB(249,252,230),Opacity),True);
    end;
  end;
end;
end.
