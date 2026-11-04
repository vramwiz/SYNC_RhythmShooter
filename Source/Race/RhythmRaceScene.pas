unit RhythmRaceScene;
// 事前計画を絶対時刻で描画する。任意シークで状態を進めたり音時刻を変えたりしない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmRacePlan;
type
  TRaceAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;
    FRef:TRhythmPlanRef;
    FPlan:TRacePlan;
    FAttempt,FError:string;
  protected
    // Narrow asset adapters: future image-bank overrides keep the same projection
    // and pick-up clocks. The standard race has no external material dependency.
    procedure DrawBackdrop(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;Distance,Bend:Double); virtual;
    procedure DrawVehicle(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;X,Y,Roll:Double); virtual;
    procedure DrawSteeringVehicle(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;X,Y,Steer,Load:Double); virtual;
    procedure DrawCollectible(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;const P:TRaceProjection;Spin:Double;Metal:Integer); virtual;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    property Audio:TRhythmAudio read FAudio write FAudio;
    procedure Prepare(const Frame:TAnimationFrame); override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame); override;
    function Notice:string; override;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics,RhythmRaceCrashScene;

function Mix(A,B:TColor;U:Double):TColor;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
end;

destructor TRaceAnimation.Destroy;
begin FPlan.Free;
  inherited;
end;

procedure TRaceAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;
end;

function TRaceAnimation.Notice:string;
begin Result:=FError;
end;

procedure TRaceAnimation.Prepare(const Frame:TAnimationFrame);
var
  Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity)+'|'+IntToHex(NativeUInt(FAudio),16) else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TRacePlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;
  end;
end;

procedure TRaceAnimation.DrawBackdrop(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;Distance,Bend:Double);
var
  S,L,T,X,Y,P:Double;
  I,Base:Integer;
  procedure Circle(AX,AY,R:Double;C:TColor);
  begin Surface.Circle(L+AX*S,T+AY*S,R*S,C,True);
  end;
begin
  S:=Min(Frame.Width/1.6,Frame.Height);
  L:=(Frame.Width-1.6*S)/2;
  T:=(Frame.Height-S)/2;
  for I:=0 to 31 do Surface.FillRect(0,I*Frame.Height/32,Frame.Width,(I+1)*Frame.Height/32+1,RGB(106+I*3,177+I*2,226+I div 2));
  Circle(1.35,0.13,0.065,RGB(255,238,177));
  P:=Distance*0.00008+Bend*0.18;
  Base:=Floor(P);
  for I:=-2 to 10 do begin X:=I*0.24-(P-Base)*0.24;
    Y:=0.30+0.035*Sin((I+Base)*1.7);
    Circle(X,Y,0.15,RGB(145,185,178));
  end;
  P:=Distance*0.00021+Bend*0.28;
  Base:=Floor(P);
  for I:=-2 to 16 do begin X:=I*0.12-(P-Base)*0.12;
    Y:=0.22+0.055*(0.5+0.5*Sin((I+Base)*2.3));
    Surface.FillRect(L+X*S,T+Y*S,L+(X+0.085)*S,T+0.35*S,RGB(106,149,162));
    Surface.FillRect(L+(X+0.014)*S,T+(Y+0.014)*S,L+(X+0.061)*S,T+(Y+0.023)*S,RGB(220,223,173));
  end;
end;

procedure TRaceAnimation.DrawVehicle(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;X,Y,Roll:Double);
var
  S,L,T,W,V,Shift,Yaw:Double;
  I:Integer;
  procedure Box(A,B,C,D:Double;Tint:TColor);
  var
    Depth,Offset,Factor,Mid,Half:Double;
  begin Depth:=((B+D)/2-Y)/0.20;
    Offset:=Yaw*Depth*0.020;
    Factor:=1+Yaw*Depth*0.22;
    Mid:=(A+C)/2-X;
    Half:=(C-A)*0.5*Factor;
    Surface.FillRect(L+(X+Mid*Factor-Half+Offset)*S,T+(Y+(B-Y)*(1-Abs(Yaw)*0.035))*S,
    L+(X+Mid*Factor+Half+Offset)*S,T+(Y+(D-Y)*(1-Abs(Yaw)*0.035))*S,Tint);
  end;
begin
  S:=Min(Frame.Width/1.6,Frame.Height);
  L:=(Frame.Width-1.6*S)/2;
  T:=(Frame.Height-S)/2;
  Yaw:=EnsureRange(Roll*4.0,-0.36,0.36);
  Box(X-0.104,Y+0.075,X+0.104,Y+0.104,RGB(23,37,44));
  Box(X-0.107,Y-0.056,X-0.074,Y+0.085,RGB(17,26,34));
  Box(X+0.074,Y-0.056,X+0.107,Y+0.085,RGB(17,26,34));
  for I:=0 to 23 do begin V:=-0.112+I*0.0085;
    W:=0.057+0.037*EnsureRange((V+0.112)/0.14,0.0,1.0);
    Shift:=Roll*V*1.8;
    Box(X-W+Shift,Y+V,X+W+Shift,Y+V+0.009,RGB(60+I div 3,164+I,204+I div 2));
  end;
  if Yaw<0 then Box(X-0.089,Y-0.014,X-0.076+Abs(Yaw)*0.010,Y+0.040,RGB(36,113,158))
  else Box(X+0.076-Abs(Yaw)*0.010,Y-0.014,X+0.089,Y+0.040,RGB(91,208,225));
  Box(X-0.046-Roll*0.06,Y-0.082,X+0.046-Roll*0.06,Y-0.026,RGB(27,60,82));
  Box(X-0.034-Roll*0.06,Y-0.074,X+0.034-Roll*0.06,Y-0.064,RGB(177,224,235));
  Box(X-0.071,Y+0.047,X-0.026,Y+0.061,RGB(255,102,108));
  Box(X+0.026,Y+0.047,X+0.071,Y+0.061,RGB(255,102,108));
  Box(X-0.100,Y+0.065,X+0.100,Y+0.078,RGB(29,58,78));
  Box(X-0.035,Y+0.077,X+0.035,Y+0.088,RGB(211,227,225));
end;

procedure TRaceAnimation.DrawSteeringVehicle(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;X,Y,Steer,Load:Double);
var
  S,L,T,W,V,Shift,Yaw,Weight:Double;
  I:Integer;
  procedure Box(A,B,C,D:Double;Tint:TColor);
  var
    Depth,Offset,Factor,Mid,Half:Double;
  begin Depth:=((B+D)/2-Y)/0.20;
    Offset:=-Yaw*Depth*0.055+Weight*(0.6-Depth)*0.007;
    Factor:=1+Yaw*Depth*0.12;
    Mid:=(A+C)/2-X;
    Half:=(C-A)*0.5*Factor;
    Surface.FillRect(L+(X+Mid*Factor-Half+Offset)*S,T+(Y+(B-Y)*(1-Abs(Weight)*0.015))*S,
    L+(X+Mid*Factor+Half+Offset)*S,T+(Y+(D-Y)*(1-Abs(Weight)*0.015))*S,Tint);
  end;
  procedure Tire(CX,CY:Double);
  var
    AX,AY,BX,BY:Double;
    procedure Point(A,B:Double;out PX,PY:Double);
    var
      Depth:Double;
    begin Depth:=(B-Y)/0.20;
      PX:=X+(A-X)*(1+Yaw*Depth*0.12)-Yaw*Depth*0.055+Weight*(0.6-Depth)*0.007;
      PY:=Y+(B-Y)*(1-Abs(Weight)*0.015);
    end;
  begin
    Point(CX+Yaw*0.011,CY-0.023,AX,AY);
    Point(CX-Yaw*0.011,CY+0.023,BX,BY);
    Surface.Line(L+AX*S,T+AY*S,L+BX*S,T+BY*S,RGB(17,26,34),Max(1,0.019*S));
    Surface.Line(L+AX*S,T+AY*S,L+BX*S,T+BY*S,RGB(92,118,126),Max(1,0.003*S));
  end;
begin
  S:=Min(Frame.Width/1.6,Frame.Height);
  L:=(Frame.Width-1.6*S)/2;
  T:=(Frame.Height-S)/2;
  Yaw:=EnsureRange(Steer,-1.0,1.0);
  Weight:=EnsureRange(Load,-1.0,1.0);
  Box(X-0.092,Y+0.075,X+0.092,Y+0.104,RGB(23,37,44));
  Box(X-0.107,Y+0.018,X-0.074,Y+0.085,RGB(17,26,34));
  Box(X+0.074,Y+0.018,X+0.107,Y+0.085,RGB(17,26,34));
  Tire(X-0.074,Y-0.055);
  Tire(X+0.074,Y-0.055);
  for I:=0 to 23 do begin V:=-0.112+I*0.0085;
    W:=0.057+0.037*EnsureRange((V+0.112)/0.14,0.0,1.0);
    Shift:=0;
    Box(X-W+Shift,Y+V,X+W+Shift,Y+V+0.009,RGB(60+I div 3,164+I,204+I div 2));
  end;
  Box(X-0.089,Y-0.014,X-0.081+Max(0.0,Yaw)*0.014,Y+0.040,Mix(RGB(36,113,158),RGB(102,216,231),(1+Yaw)/2));
  Box(X+0.081-Max(0.0,-Yaw)*0.014,Y-0.014,X+0.089,Y+0.040,Mix(RGB(36,113,158),RGB(102,216,231),(1-Yaw)/2));
  Box(X-0.046,Y-0.082,X+0.046,Y-0.026,RGB(27,60,82));
  Box(X-0.034,Y-0.074,X+0.034,Y-0.064,RGB(177,224,235));
  Box(X-0.071,Y+0.047,X-0.026,Y+0.061,RGB(255,102,108));
  Box(X+0.026,Y+0.047,X+0.071,Y+0.061,RGB(255,102,108));
  Box(X-0.100,Y+0.065,X+0.100,Y+0.078,RGB(29,58,78));
  Box(X-0.035,Y+0.077,X+0.035,Y+0.088,RGB(211,227,225));
end;

procedure TRaceAnimation.DrawCollectible(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame;const P:TRaceProjection;Spin:Double;Metal:Integer);
var
  S,L,T,R,W:Double;
  Body,Edge,Shine:TColor;
begin
  S:=Min(Frame.Width/1.6,Frame.Height);
  L:=(Frame.Width-1.6*S)/2;
  T:=(Frame.Height-S)/2;
  R:=0.024*P.Scale;
  W:=R*(0.40+0.60*Abs(Cos(Spin)));
  case Metal of
    2:begin Body:=RGB(255,211,72);
      Edge:=RGB(184,118,32);
      Shine:=RGB(255,252,207);
    end;
    1:begin Body:=RGB(204,223,238);
      Edge:=RGB(94,125,155);
      Shine:=RGB(249,255,255);
    end;
    else begin Body:=RGB(207,130,81);
      Edge:=RGB(121,69,49);
      Shine:=RGB(255,207,165);
    end;
  end;
  Surface.Circle(L+P.X*S,T+(P.Y+0.005*P.Scale)*S,R*1.25*S,Edge,False,Max(1,S*0.002*P.Scale));
  Surface.Circle(L+P.X*S,T+P.Y*S,R*S,Body,True);
  Surface.FillRect(L+(P.X-W*0.4)*S,T+(P.Y-R*0.65)*S,L+(P.X+W*0.2)*S,T+(P.Y+R*0.65)*S,Shine);
  if Metal>0 then Surface.Line(L+(P.X-R*0.5)*S,T+(P.Y-R*0.5)*S,L+(P.X+R*0.4)*S,T+(P.Y-R*0.7)*S,Shine,Max(1,S*0.002*P.Scale));
  if Metal=2 then begin Surface.Line(L+(P.X+R*0.75)*S,T+(P.Y-R*1.1)*S,L+(P.X+R*0.75)*S,T+(P.Y-R*0.6)*S,Shine,Max(1,S*0.002*P.Scale));
  end;
end;

procedure TRaceAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
const
  DigitMask:array[0..9] of Byte=($3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F);
var
  Scale,Left,Top,Clock,Camera,Speed,Bend,Y0,Y1,Y,S,Z,D,Half,Center,Age,U,Radius,Angle,Life,CarX,Roll,Bob:Double;
  I,J,N,Base,First,Last,Picked:Integer;
  P:TRaceProjection;
  C:TRaceCoin;
  Tint:TColor;
  Text:string;
  Boss:TRaceTrailer;
  Acceleration,Focus,Clip,ImpactRoll,ImpactHeave,ImpactPower,ImpactSide:Double;
  Score:Integer;
  Pose:TRacePose;
  ActiveCount:Integer;
  ActiveCars:array[0..127] of Integer;
  ActiveDistance:array[0..127] of Double;
  procedure Box(A,B,C,D:Double;Color:TColor);
  begin Surface.FillRect(Left+A*Scale,Top+B*Scale,Left+C*Scale,Top+D*Scale,Color);
  end;
  procedure Line(A,B,C,D:Double;Color:TColor;Stroke:Double);
  begin Surface.Line(Left+A*Scale,Top+B*Scale,Left+C*Scale,Top+D*Scale,Color,Max(1,Stroke*Scale));
  end;
  procedure Circle(X,Y,R:Double;Color:TColor;Filled:Boolean=True);
  begin Surface.Circle(Left+X*Scale,Top+Y*Scale,R*Scale,Color,Filled,Max(1,Scale*0.002));
  end;
  function At(Distance,Lane,Height:Double):TRaceProjection;
  begin
    if FPlan<>nil then Exit(FPlan.Project(Distance,Lane,Clock,Height));
    Result:=Default(TRaceProjection);
    if Distance<=-Clip then Exit;
    Result.Scale:=Focus/(Focus+Distance);
    Result.X:=0.8+0.58*Lane*Result.Scale;
    Result.Y:=RACE_HORIZON+(RACE_CONTACT_Y-RACE_HORIZON-Height)*Result.Scale;
    Result.Visible:=True;
  end;
  procedure Digit(Value:Integer;X,Y,Size:Double;Color:TColor);
  var
    Mask:Byte;
  begin
    Mask:=DigitMask[EnsureRange(Value,0,9)];
    if Mask and 1<>0 then Line(X,Y,X+Size,Y,Color,Size*0.12);
    if Mask and 2<>0 then Line(X+Size,Y,X+Size,Y+Size,Color,Size*0.12);
    if Mask and 4<>0 then Line(X+Size,Y+Size,X+Size,Y+2*Size,Color,Size*0.12);
    if Mask and 8<>0 then Line(X,Y+2*Size,X+Size,Y+2*Size,Color,Size*0.12);
    if Mask and 16<>0 then Line(X,Y+Size,X,Y+2*Size,Color,Size*0.12);
    if Mask and 32<>0 then Line(X,Y,X,Y+Size,Color,Size*0.12);
    if Mask and 64<>0 then Line(X,Y+Size,X+Size,Y+Size,Color,Size*0.12);
  end;
  procedure DrawWord(const Value:string;X,Y,Size:Double;Color:TColor);
  var
    K:Integer;
    PX:Double;
    Ch:Char;
  begin
    for K:=1 to Length(Value) do begin PX:=X+(K-1)*Size*1.45;
      Ch:=Value[K];
      case Ch of
        '0'..'9':Digit(Ord(Ch)-Ord('0'),PX,Y,Size,Color);
        'G','O','C','S':begin
          Line(PX,Y,PX+Size,Y,Color,Size*0.12);
          Line(PX,Y+2*Size,PX+Size,Y+2*Size,Color,Size*0.12);
          if Ch<>'S' then Line(PX,Y,PX,Y+2*Size,Color,Size*0.12)
          else begin Line(PX,Y,PX,Y+Size,Color,Size*0.12);
            Line(PX,Y+Size,PX+Size,Y+Size,Color,Size*0.12);
          end;
          if Ch='O' then Line(PX+Size,Y,PX+Size,Y+2*Size,Color,Size*0.12);
          if (Ch='G') or (Ch='S') then begin Line(PX+Size,Y+Size,PX+Size,Y+2*Size,Color,Size*0.12);
            Line(PX+Size*0.55,Y+Size,PX+Size,Y+Size,Color,Size*0.12);
          end;
        end;
        '+':begin Line(PX,Y+Size,PX+Size,Y+Size,Color,Size*0.12);
          Line(PX+Size/2,Y+Size*0.5,PX+Size/2,Y+Size*1.5,Color,Size*0.12);
        end;
        'A':begin Line(PX,Y,PX,Y+2*Size,Color,Size*0.12);
          Line(PX,Y,PX+Size,Y,Color,Size*0.12);
          Line(PX+Size,Y,PX+Size,Y+2*Size,Color,Size*0.12);
          Line(PX,Y+Size,PX+Size,Y+Size,Color,Size*0.12);
        end;
        'E':begin Line(PX,Y,PX,Y+2*Size,Color,Size*0.12);
          Line(PX,Y,PX+Size,Y,Color,Size*0.12);
          Line(PX,Y+Size,PX+Size*0.85,Y+Size,Color,Size*0.12);
          Line(PX,Y+2*Size,PX+Size,Y+2*Size,Color,Size*0.12);
        end;
        'R':begin Line(PX,Y,PX,Y+2*Size,Color,Size*0.12);
          Line(PX,Y,PX+Size,Y,Color,Size*0.12);
          Line(PX,Y+Size,PX+Size,Y+Size,Color,Size*0.12);
          Line(PX+Size,Y,PX+Size,Y+Size,Color,Size*0.12);
          Line(PX+Size*0.35,Y+Size,PX+Size,Y+2*Size,Color,Size*0.12);
        end;
        'B':begin Line(PX,Y,PX,Y+2*Size,Color,Size*0.12);
          Line(PX,Y,PX+Size*0.8,Y,Color,Size*0.12);
          Line(PX,Y+Size,PX+Size*0.8,Y+Size,Color,Size*0.12);
          Line(PX,Y+2*Size,PX+Size*0.8,Y+2*Size,Color,Size*0.12);
          Line(PX+Size*0.8,Y,PX+Size*0.8,Y+2*Size,Color,Size*0.12);
        end;
        'F','H':begin Line(PX,Y,PX,Y+2*Size,Color,Size*0.12);
          Line(PX,Y+Size,PX+Size,Y+Size,Color,Size*0.12);
          if Ch='F' then Line(PX,Y,PX+Size,Y,Color,Size*0.12) else Line(PX+Size,Y,PX+Size,Y+2*Size,Color,Size*0.12);
        end;
        'I':begin Line(PX,Y,PX+Size,Y,Color,Size*0.12);
          Line(PX+Size/2,Y,PX+Size/2,Y+2*Size,Color,Size*0.12);
          Line(PX,Y+2*Size,PX+Size,Y+2*Size,Color,Size*0.12);
        end;
        'N':begin Line(PX,Y,PX,Y+2*Size,Color,Size*0.12);
          Line(PX,Y,PX+Size,Y+2*Size,Color,Size*0.12);
          Line(PX+Size,Y,PX+Size,Y+2*Size,Color,Size*0.12);
        end;
      end;
    end;
  end;
  procedure Checker(Distance:Double;Gate:Boolean);
  var
    A,B:TRaceProjection;
    K,Row:Integer;
    W,H,TopY:Double;
  begin
    A:=At(Distance,-1.02,0);
    B:=At(Distance,1.02,0);
    if not A.Visible then Exit;
    W:=(B.X-A.X)/14;
    H:=0.035*A.Scale;
    TopY:=A.Y;
    if Gate then TopY:=A.Y-0.32*A.Scale;
    if Gate then begin Line(A.X,A.Y,A.X,TopY,RGB(221,234,234),0.013*A.Scale);
      Line(B.X,B.Y,B.X,TopY,RGB(221,234,234),0.013*A.Scale);
    end;
    for Row:=0 to 1 do for K:=0 to 13 do begin
      if (K+Row) mod 2=0 then Tint:=RGB(244,242,217) else Tint:=RGB(26,43,59);
      Box(A.X+K*W,TopY+Row*H,A.X+(K+1)*W+0.001,TopY+(Row+1)*H,Tint);
    end;
  end;

  function MetalColor(Metal:Integer):TColor;
  begin case Metal of 2:Result:=RGB(255,224,104);
      1:Result:=RGB(210,238,255);
      else Result:=RGB(235,156,104);
    end;
  end;
  procedure ObstacleCar(const Point:TRaceProjection;Trailer:Boolean;Warning:Double;Variant:Integer=0;Tilt:Double=0);
  var
    X,Y,S,W,H:Double;
    K:Integer;
    Body:TColor;
    procedure CarBox(A,B,C,D:Double;Tint:TColor);
    var
      I,N:Integer;
      T0,T1,Shift:Double;
    begin if Abs(Tilt)<0.001 then begin Box(A,B,C,D,Tint);
        Exit;
      end;
      N:=EnsureRange(Ceil((D-B)*Scale/8),1,12);
      for I:=0 to N-1 do begin T0:=B+(D-B)*I/N;
        T1:=B+(D-B)*(I+1)/N;
        Shift:=Tilt*((T0+T1)/2-Y);
        Box(A+Shift,T0,C+Shift,T1+0.0001*S,Tint);
      end;
    end;
    procedure CarLine(A,B,C,D:Double;Tint:TColor;Stroke:Double);
    begin Line(A+Tilt*(B-Y),B,C+Tilt*(D-Y),D,Tint,Stroke);
    end;
  begin
    X:=Point.X;
    Y:=Point.Y;
    S:=Point.Scale;
    W:=0.075*S;
    H:=0.145*S;
    Body:=RGB(220,100,76);
    if not Trailer then case Variant mod 4 of 1:Body:=RGB(104,149,190);
      2:Body:=RGB(225,191,104);
      3:Body:=RGB(180,198,207);
    end;
    if Trailer then begin W:=0.132*S;
      H:=0.32*S;
      if (FPlan<>nil) and (FPlan.Version>=3) then begin W:=0.165*S;
        H:=0.40*S;
      end;
      Body:=RGB(95,89,151);
    end;
    // Half-width bounds: car .15; trailer .26 legacy / .33 in plan3.
    CarBox(X-W*1.10,Y-0.020*S,X+W*1.10,Y+0.010*S,RGB(24,38,48));
    for K:=-1 to 1 do if K<>0 then begin CarBox(X+K*W-W*0.13,Y-H*0.28,X+K*W+W*0.13,Y,RGB(24,30,39));
      if Trailer then CarBox(X+K*W-W*0.13,Y-H*0.55,X+K*W+W*0.13,Y-H*0.42,RGB(24,30,39));
    end;
    CarBox(X-W,Y-H,X+W,Y-0.020*S,Body);
    if Trailer then begin
      CarBox(X-W*0.90,Y-H*0.91,X+W*0.90,Y-H*0.14,RGB(161,174,193));
      for K:=1 to 7 do CarLine(X-W*0.82,Y-H*(0.18+K*0.085),X+W*0.82,Y-H*(0.18+K*0.085),RGB(108,126,151),0.003*S);
      CarLine(X,Y-H*0.85,X,Y-H*0.18,RGB(79,98,126),0.003*S);
      CarBox(X-W*0.90,Y-H*0.13,X+W*0.90,Y-H*0.06,RGB(238,198,92));
    end else begin CarBox(X-W*0.65,Y-H*0.86,X+W*0.65,Y-H*0.50,RGB(34,61,78));
      CarLine(X-W*0.52,Y-H*0.79,X+W*0.45,Y-H*0.79,RGB(185,213,217),0.006*S);
    end;
    CarBox(X-W*0.84,Y-H*0.13,X-W*0.39,Y-H*0.04,RGB(255,160,110));
    CarBox(X+W*0.39,Y-H*0.13,X+W*0.84,Y-H*0.04,RGB(255,160,110));
    if Warning>0 then CarLine(X-W,Y+0.025*S,X+W,Y+0.025*S,RGB(255,201,102),0.004*S);
  end;
  procedure DrawObjects(FarZ,NearZ:Double);
  var
    K,Order,FromCoin,ToCoin,Part:Integer;
    B:TRaceBomb;
    V:TRaceTraffic;
    Boss:TRaceTrailer;
    Point,Ground:TRaceProjection;
    Dist,Lane,Height,Z,U,A,R:Double;
    Coin:TRaceCoin;
  begin
    FromCoin:=FPlan.CoinAtDistance(Camera+Max(0.0,NearZ));
    FromCoin:=Max(FromCoin,FPlan.CoinBefore(Clock));
    ToCoin:=Min(FPlan.CoinAtDistance(Camera+FarZ),FPlan.CoinBefore(Clock)+160);
    for K:=ToCoin downto FromCoin+1 do begin Coin:=FPlan.Coin[K];
      Point:=At(Coin.Distance,Coin.Lane,RACE_COIN_HEIGHT);
      if Point.Visible and (Point.Y>RACE_HORIZON+0.006) then DrawCollectible(Surface,Frame,Point,Clock*5+Coin.Source*0.7,TRacePlan.CoinMetal(Coin.Strength));
    end;
    for Order:=0 to ActiveCount-1 do begin K:=ActiveCars[Order];
      V:=FPlan.Traffic[K];
      if (Clock<V.First) or (Clock>V.Last) then Continue;
      Dist:=FPlan.TrafficDistance(K,Clock);
      Z:=Dist-Camera;
      if (Z>FarZ) or (Z<=NearZ) then Continue;
      Point:=At(Dist,FPlan.TrafficLaneAt(K,Clock),0);
      if Point.Visible then ObstacleCar(Point,False,1,K,FPlan.TrafficTilt(K,Clock));
    end;
    for K:=0 to FPlan.TrailerCount-1 do begin Boss:=FPlan.Trailer[K];
      if (Clock<Boss.First) or (Clock>Boss.Last) then Continue;
      Dist:=FPlan.TrailerDistance(K,Clock);
      Z:=Dist-Camera;
      if (Z>FarZ) or (Z<=NearZ) then Continue;
      Point:=At(Dist,Boss.Lane,0);
      if Point.Visible then ObstacleCar(Point,True,1);
    end;
    for K:=Max(0,FPlan.BombDropBefore(Clock-2.20)+1) to FPlan.BombDropBefore(Clock) do begin B:=FPlan.Bomb[K];
      if (Clock<B.Drop) or (Clock>=B.Clear) then Continue;
      FPlan.BombPosition(K,Clock,Dist,Lane,Height);
      Z:=Dist-Camera;
      if (Z>FarZ) or (Z<=NearZ) then Continue;
      Point:=At(Dist,Lane,Height);
      Ground:=At(B.Distance,B.Lane,0);
      if not Point.Visible then Continue;
      if Clock<B.Burst then begin
        Circle(Point.X,Point.Y,0.030*Point.Scale,RGB(42,48,63));
        Circle(Point.X-0.009*Point.Scale,Point.Y-0.010*Point.Scale,0.010*Point.Scale,RGB(135,144,157));
        Line(Point.X,Point.Y-0.025*Point.Scale,Point.X+0.012*Point.Scale,Point.Y-0.043*Point.Scale,RGB(250,201,104),0.004*Point.Scale);
        Circle(Point.X+0.013*Point.Scale,Point.Y-0.044*Point.Scale,0.007*Point.Scale,RGB(255,224,149));
      end else begin U:=(Clock-B.Burst)/(B.Clear-B.Burst);
        Circle(Ground.X,Ground.Y-0.018*Point.Scale,(0.025+0.055*U)*Point.Scale,Mix(RGB(255,215,113),RGB(109,111,113),U));
        Circle(Ground.X,Ground.Y,(0.04+0.055*U)*Point.Scale,Mix(RGB(255,239,166),RGB(148,106,93),U),False);
        for Part:=0 to 11 do begin A:=Part*Pi/6;
          R:=(0.025+0.055*U)*Point.Scale;
          Line(Ground.X+Cos(A)*R*0.6,Ground.Y+Sin(A)*R*0.5,Ground.X+Cos(A)*R,Ground.Y+Sin(A)*R*0.7,RGB(248,160,86),0.003*Point.Scale);
        end;
      end;
    end;
  end;

begin
  Scale:=Min(Frame.Width/1.6,Frame.Height);
  Left:=(Frame.Width-1.6*Scale)/2;
  Top:=(Frame.Height-Scale)/2;
  Clock:=0;
  Camera:=0;
  Speed:=0;
  Bend:=0;
  Focus:=RACE_FOCUS;
  Clip:=Focus*0.85;
  ImpactRoll:=0;
  ImpactHeave:=0;
  ImpactPower:=0;
  ImpactSide:=0;
  if (FPlan<>nil) and not IsNan(Frame.Time) and not IsInfinite(Frame.Time) then begin Clock:=EnsureRange(Frame.Time,0.0,FPlan.EndTime);
    Camera:=FPlan.DistanceAt(Clock);
    Speed:=FPlan.SpeedAt(Clock)/FPlan.TopSpeed;
    Bend:=FPlan.BendAt(Camera);
    Focus:=FPlan.Focus;
    Clip:=FPlan.NearClip;
    FPlan.ImpactAt(Clock,ImpactRoll,ImpactHeave,ImpactPower,ImpactSide);
  end;
  ActiveCount:=0;
  if FPlan<>nil then for I:=Max(0,FPlan.TrafficBefore(Clock-2.20)+1) to FPlan.TrafficBefore(Clock+2.90) do begin
    if (Clock<FPlan.Traffic[I].First) or (Clock>FPlan.Traffic[I].Last) then Continue;
    D:=FPlan.TrafficDistance(I,Clock);
    if (D-Camera<=-Clip) or (D-Camera>950) then Continue;
    if ActiveCount>=Length(ActiveCars) then Break;
    J:=ActiveCount-1;
    while (J>=0) and (ActiveDistance[J]<D) do begin ActiveCars[J+1]:=ActiveCars[J];
      ActiveDistance[J+1]:=ActiveDistance[J];
      Dec(J);
    end;
    ActiveCars[J+1]:=I;
    ActiveDistance[J+1]:=D;
    Inc(ActiveCount);
  end;
  DrawBackdrop(Surface,Frame,Camera,Bend);
  // World-distance stripes change scale and direction with depth and road bend.
  for I:=0 to 111 do begin
    Y0:=RACE_HORIZON+(1.06-RACE_HORIZON)*I/112;
    Y1:=RACE_HORIZON+(1.06-RACE_HORIZON)*(I+1)/112;
    Y:=(Y0+Y1)/2;
    S:=(Y-RACE_HORIZON)/(RACE_CONTACT_Y-RACE_HORIZON);
    Z:=Focus*(1/S-1);
    D:=Camera+Z;
    P:=At(D,0,0);
    Half:=0.58*S;
    Center:=P.X;
    N:=Floor(D/9);
    if N mod 2=0 then Tint:=RGB(97,157,106) else Tint:=RGB(85,146,98);
    Box(0,Y0,1.6,Y1+0.001,Tint);
    if N mod 2=0 then Tint:=RGB(237,225,203) else Tint:=RGB(209,105,107);
    Box(Center-Half-0.035*S,Y0,Center+Half+0.035*S,Y1+0.001,Tint);
    Box(Center-Half,Y0,Center+Half,Y1+0.001,RGB(50+(N mod 2)*3,64+(N mod 2)*3,77+(N mod 2)*3));
    if Floor(D/9) mod 2=0 then for J:=-1 to 1 do if J<>0 then Box(Center+J*Half/3-0.003*S,Y0,Center+J*Half/3+0.003*S,Y1+0.001,RGB(236,234,205));
    for J:=-1 to 1 do if J<>0 then Box(Center+J*(Half+0.053*S)-0.003*S,Y0,Center+J*(Half+0.053*S)+0.003*S,Y1+0.001,RGB(184,203,199));
  end;
  Base:=Floor((Camera-20)/40);
  for I:=12 downto 0 do begin D:=(Base+I)*40;
    for J:=-1 to 1 do if J<>0 then begin P:=At(D,J*1.34,0);
      if P.Visible and (D>=Camera-8) then begin
        Line(P.X,P.Y,P.X,P.Y-0.18*P.Scale,RGB(101,104,76),0.014*P.Scale);
        if (Base+I) mod 3=0 then begin Box(P.X-0.07*P.Scale,P.Y-0.23*P.Scale,P.X+0.07*P.Scale,P.Y-0.12*P.Scale,RGB(34,119,128));
          Line(P.X-0.04*P.Scale,P.Y-0.17*P.Scale,P.X+0.04*P.Scale,P.Y-0.17*P.Scale,RGB(235,229,180),0.009*P.Scale);
        end
        else Circle(P.X,P.Y-0.18*P.Scale,0.08*P.Scale,RGB(62,126,104));
      end;
    end;
  end;
  if Frame.BackgroundOnly then begin Surface.DrawViewportMatte(Left,Top,Frame.Width,Frame.Height,RGB(13,28,39));Exit;end;
  if FPlan<>nil then begin
    if Camera<65 then Checker(0,False);
    Checker(FPlan.DistanceAt(FPlan.GoalTime),True);
    if FPlan.Crash<>nil then begin
      DrawRaceCrash(FPlan.Crash,Surface,Clock,Frame.Width,Frame.Height);
      Box(0.05,0.028,0.46,0.13,RGB(27,58,77));
      DrawWord('CRASH',0.072,0.041,0.011,RGB(246,202,153));
      DrawWord(IntToStr(FPlan.ScoreAt(Clock)),0.072,0.077,0.023,RGB(255,240,176));
      DrawWord(IntToStr(FPlan.Crash.DefeatedAt(Clock)),0.30,0.078,0.018,RGB(195,231,226));
      Box(1.24,0.038,1.54,0.101,RGB(27,58,77));
      DrawWord(IntToStr(Round(FPlan.SpeedAt(Clock)*3.6)),1.28,0.052,0.018,RGB(246,243,202));
      if FPlan.Crash.SoundEnd>0 then begin
        if Clock<FPlan.LaunchTime then begin Circle(0.8,0.44,0.10,RGB(25,55,75));
          Digit(3-Min(2,Floor(Clock/FPlan.LaunchTime*3)),0.765,0.37,0.07,RGB(255,237,166));
        end
        else if Clock<FPlan.LaunchTime+Min(0.55,FPlan.AccelerationTime) then begin Box(0.65,0.35,0.95,0.50,RGB(29,95,108));
          DrawWord('GO',0.727,0.365,0.06,RGB(255,245,179));
        end;
        if Clock>=FPlan.GoalTime then begin Box(0.47,0.35,1.13,0.50,RGB(27,67,82));
          DrawWord('FINISH',0.55,0.372,0.06,RGB(255,237,166));
        end;
      end;
      if Left>0 then begin Surface.FillRect(0,0,Left,Frame.Height,RGB(13,28,39));
        Surface.FillRect(Frame.Width-Left,0,Frame.Width,Frame.Height,RGB(13,28,39));
      end;
      if Top>0 then begin Surface.FillRect(0,0,Frame.Width,Top,RGB(13,28,39));
        Surface.FillRect(0,Frame.Height-Top,Frame.Width,Frame.Height,RGB(13,28,39));
      end;
      Exit;
    end;
    // Depth bands include traffic, trailer, bomb and coin; near objects cover far ones.
    for I:=23 downto 0 do begin Z:=Power(I/24,2)*950;
      D:=Power((I+1)/24,2)*950;
      DrawObjects(D,Z);
    end;
  end;
  P:=At(Camera,0,RACE_COIN_HEIGHT);
  CarX:=P.X;
  Roll:=0;
  Bob:=0;
  if FPlan<>nil then begin P:=At(Camera,FPlan.LaneAt(Clock),RACE_COIN_HEIGHT);
    CarX:=P.X;
    if FPlan.Version<4 then Roll:=EnsureRange(-FPlan.LaneVelocity(Clock)*0.12-Bend*Speed*0.20,-0.09,0.09);
    Bob:=0.0015*Speed*Sin(Clock*63);
  end;
  if (FPlan<>nil) and (Clock>FPlan.LaunchTime) and (Clock<FPlan.LaunchTime+FPlan.AccelerationTime) then begin
    Acceleration:=1-(Clock-FPlan.LaunchTime)/FPlan.AccelerationTime;
    for J:=-1 to 1 do if J<>0 then Line(CarX+J*0.056,0.933,CarX+J*0.058,0.95+0.045*Acceleration,RGB(255,220,140),0.008);
  end;
  if Speed>0.65 then begin N:=22;
    if (FPlan<>nil) and (Clock>=FPlan.GoalTime*0.75) then N:=30;
    for I:=0 to N-1 do begin U:=Frac(Camera*0.025+I*0.618);
      Y:=0.40+0.60*U;
      Line(0.05+0.09*U,Y,0.01+0.11*U,Y+0.075*Speed,Mix(RGB(112,158,162),RGB(224,238,217),U),0.0015);
      Line(1.55-0.09*U,Y,1.59-0.11*U,Y+0.075*Speed,Mix(RGB(112,158,162),RGB(224,238,217),U),0.0015);
    end;
  end;
  if (FPlan<>nil) and (FPlan.Version>=4) then begin Pose:=FPlan.PoseAt(Clock);
    DrawSteeringVehicle(Surface,Frame,CarX,0.845+Bob+ImpactHeave,Pose.Steer,EnsureRange(Pose.Load+ImpactRoll*8,-1.0,1.0));
  end else DrawVehicle(Surface,Frame,CarX,0.845+Bob+ImpactHeave,EnsureRange(Roll+ImpactRoll,-0.09,0.09));
  if FPlan<>nil then DrawObjects(0,-Clip+0.1);
  if ImpactPower>0 then begin
    // Real near-body contact: sharp metal streaks and a short shedding trim piece.
    for J:=0 to 3 do begin U:=Frac((Clock+J*0.019)*7);
      Radius:=0.02+0.06*U;
      Angle:=J*1.7+Clock*9;
      Box(CarX+ImpactSide*(0.10+Radius)-0.003,0.85+Sin(Angle)*Radius*0.4-0.002,CarX+ImpactSide*(0.10+Radius)+0.003,0.85+Sin(Angle)*Radius*0.4+0.002,Mix(RGB(224,232,229),RGB(84,105,116),U));
    end;
    for J:=0 to 11 do begin Angle:=J*0.71+Clock*21;
      U:=Frac((Clock+J*0.037)*9);
      Radius:=0.012+0.045*U;
      Line(CarX+ImpactSide*(0.094+Radius),0.84+Sin(Angle)*Radius*0.5,
      CarX+ImpactSide*(0.105+Radius),0.84+Sin(Angle)*Radius*0.5-0.008*ImpactPower,RGB(255,216,127),0.0025*ImpactPower);
    end;
  end;
  if FPlan<>nil then begin
    First:=FPlan.CoinBefore(Clock-0.45)+1;
    Last:=FPlan.CoinBefore(Clock);
    for I:=First to Last do begin C:=FPlan.Coin[I];
      Age:=Clock-C.Time;
      Life:=Min(0.45,FPlan.EndTime-C.Time);
      if (Age<0) or (Age>=Life) then Continue;
      U:=Age/Life;
      if I=Last then DrawWord('+'+IntToStr(C.Points),CarX-0.04,RACE_CONTACT_Y-RACE_COIN_HEIGHT-0.07-Age*0.12,0.016*(1-U*0.20),MetalColor(TRacePlan.CoinMetal(C.Strength)));
      Circle(CarX,RACE_CONTACT_Y-RACE_COIN_HEIGHT,0.025+Age*0.12,Mix(MetalColor(TRacePlan.CoinMetal(C.Strength)),RGB(68,94,109),U),False);
      for J:=0 to 5 do begin Angle:=J*Pi/3+C.Source*0.73;
        Radius:=Age*(0.10+0.02*(J mod 3));
        Circle(CarX+Cos(Angle)*Radius,RACE_CONTACT_Y-RACE_COIN_HEIGHT+Sin(Angle)*Radius,0.004*(1-U),Mix(RGB(255,249,193),RGB(90,126,130),U));
      end;
    end;
    for I:=0 to FPlan.TrailerCount-1 do begin Boss:=FPlan.Trailer[I];
      if (Clock>=Boss.First) and (Clock<=Boss.Last) then begin
        Box(0.59,0.04,1.01,0.095,RGB(102,68,104));
        DrawWord('BOSS',0.752,0.048,0.018,RGB(255,224,166));
      end;
    end;
    Picked:=FPlan.CoinBefore(Clock)+1;
    Score:=FPlan.ScoreAt(Clock);
    Box(0.05,0.028,0.54,0.145,RGB(27,58,77));
    DrawWord('SCORE',0.072,0.041,0.011,RGB(176,206,217));
    DrawWord(IntToStr(Score),0.072,0.077,0.023,RGB(255,240,176));
    Circle(0.354,0.116,0.009,RGB(255,220,104));
    DrawWord(IntToStr(Picked),0.38,0.104,0.011,RGB(215,229,222));
    Box(1.24,0.038,1.54,0.101,RGB(27,58,77));
    Text:=IntToStr(Round(FPlan.SpeedAt(Clock)*3.6));
    DrawWord(Text,1.28,0.052,0.018,RGB(246,243,202));
    if Clock<FPlan.LaunchTime then begin Circle(0.8,0.44,0.10,RGB(25,55,75));
      Digit(3-Min(2,Floor(Clock/FPlan.LaunchTime*3)),0.765,0.37,0.07,RGB(255,237,166));
    end
    else if Clock<FPlan.LaunchTime+Min(0.55,FPlan.AccelerationTime) then begin Box(0.65,0.35,0.95,0.50,RGB(29,95,108));
      DrawWord('GO',0.727,0.365,0.06,RGB(255,245,179));
    end;
    if Clock>=FPlan.GoalTime then begin U:=EnsureRange((Clock-FPlan.GoalTime)/(FPlan.EndTime-FPlan.GoalTime),0.0,1.0);
      Box(0.47,0.35,1.13,0.50,RGB(27,67,82));
      DrawWord('FINISH',0.55,0.372,0.06,RGB(255,237,166));
      if U<1 then for I:=0 to 11 do begin Angle:=I*2.39996;
        Circle(0.8+Cos(Angle)*0.32*U,0.42+Sin(Angle)*0.15*U,0.005*(1-U),RGB(255,225,123));
      end;
    end;
  end;
  if Left>0 then begin Surface.FillRect(0,0,Left,Frame.Height,RGB(13,28,39));
    Surface.FillRect(Frame.Width-Left,0,Frame.Width,Frame.Height,RGB(13,28,39));
  end;
  if Top>0 then begin Surface.FillRect(0,0,Frame.Width,Top,RGB(13,28,39));
    Surface.FillRect(0,Frame.Height-Top,Frame.Width,Frame.Height,RGB(13,28,39));
  end;
end;
end.
