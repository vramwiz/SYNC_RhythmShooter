unit RhythmOrbitScene;
// 広い宇宙の一部を連続カメラで見る。惑星・軌道・音要素・自機は同じ世界座標を使う。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmOrbitPlan,RhythmEqualizer;
type
  TOrbitRenderStats=record
    RouteSegments,Markers,NearMarkers,FarMarkers,Effects,Stars:Integer;
    Horizon,Density:Double;
  end;
  TOrbitAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;FTransparentBackground:Boolean;
    FRef:TRhythmPlanRef;
    FPlan:TOrbitPlan;
    FAttempt,FError:string;
    FStats:TOrbitRenderStats;
  public
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    function TryActivity(Time:Double;out Activity:TEqualizerActivity):Boolean;
    property TransparentBackground:Boolean read FTransparentBackground write FTransparentBackground;
    property Audio:TRhythmAudio read FAudio write FAudio;
    property RenderStats:TOrbitRenderStats read FStats;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics,RhythmOrbitTypes,RhythmOrbitGuide,RhythmOrbitShow,RhythmOrbitMarks;
function Palette(Hue:Integer):TColor;
begin case Hue mod 8 of
  0:Result:=RGB(65,213,255);1:Result:=RGB(205,128,255);2:Result:=RGB(255,185,93);3:Result:=RGB(109,255,198);
  4:Result:=RGB(126,156,255);5:Result:=RGB(255,112,172);6:Result:=RGB(239,230,131);else Result:=RGB(159,224,255);end;
end;
function Shade(Color:TColor;Light:Double):TColor;
var C:Cardinal;
begin C:=ColorToRGB(Color);Result:=RGB(Round(GetRValue(C)*Light),Round(GetGValue(C)*Light),Round(GetBValue(C)*Light));end;
function Noise(Index,Salt:Cardinal):Double;
var V:Cardinal;
begin V:=Cardinal((UInt64(Index+1)*747796405+UInt64(Salt)*2891336453) and $FFFFFFFF);
  V:=Cardinal((UInt64(V xor (V shr 16))*2246822519) and $FFFFFFFF);Result:=((V xor (V shr 13)) shr 8)/16777216.0;
end;
function Wrap(V:Double):Double;
begin Result:=V-Floor(V);end;
destructor TOrbitAnimation.Destroy;
begin FPlan.Free;inherited;end;
procedure TOrbitAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;end;
function TOrbitAnimation.Notice:string;
begin Result:=FError;end;
function TOrbitAnimation.TryActivity(Time:Double;out Activity:TEqualizerActivity):Boolean;
var V:TOrbitVisualState;L:TOrbitLeg;
begin Activity:=Default(TEqualizerActivity);Result:=FPlan<>nil;if not Result or (FPlan.Count=0) then Exit;
  V:=OrbitVisualState(FPlan,Time);Activity.Valid:=(Time>=0) and (Time<=FPlan.EndTime);Activity.Pulse:=V.Pulse;
  Activity.Energy:=V.Energy;Activity.Hit:=FPlan.Before(Time);L:=FPlan.Legs[FPlan.LegAt(Time)];Activity.Hue:=FPlan.Bodies[L.ToBody].Hue;
end;
procedure TOrbitAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+FAudio.SourceRevision else Key:=Key+'|none';
  if Key=FAttempt then Exit;FAttempt:=Key;FreeAndNil(FPlan);FError:='';if FAudio=nil then Exit;
  try FPlan:=TOrbitPlan.Load(FRef,FAudio,Frame.Direction);except on E:Exception do FError:=E.Message;end;
end;
procedure TOrbitAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
const MaxEffects=24;
var W,H,S,Aspect,T,Scale,Age,Alpha,U,Angle,D,Progress:Double;Camera:TOrbitCamera;
  I,J,Hit,Next,LegIndex,FromBody,ToBody:Integer;L:TOrbitLeg;B:TOrbitBody;N:TOrbitTap;
  P,Q,Ship:TOrbitPoint;C,Theme:TColor;V:TOrbitVisualState;
  function Screen(const P:TOrbitPoint):TOrbitPoint;
  var V:TOrbitPoint;
  begin V:=OrbitProject(P,Camera,Aspect);Result:=OrbitPoint(V.X*W,V.Y*H);end;
  procedure Line(const A,B:TOrbitPoint;Color:TColor;Width,Opacity:Double);
  var X,Y:TOrbitPoint;
  begin X:=Screen(A);Y:=Screen(B);Surface.Line(X.X,X.Y,Y.X,Y.Y,Color,Max(1.0,Width*Scale),Opacity);end;
  procedure Ring(const P:TOrbitPoint;Radius:Double;Color:TColor;Width,Opacity:Double);
  var X:TOrbitPoint;
  begin X:=Screen(P);Surface.Circle(X.X,X.Y,Radius*Scale,Color,False,Max(1.0,Width*Scale),Opacity);end;
  procedure Dot(const P:TOrbitPoint;Radius:Double;Color:TColor;Opacity:Double);
  var X:TOrbitPoint;
  begin X:=Screen(P);Surface.Circle(X.X,X.Y,Max(1.0,Radius*Scale),Color,True,1,Opacity);end;
  procedure Background;
  var I,J:Integer;X,Y,Depth,Light,Size,Step,Offset,Focus,Pulse:Double;F:TOrbitPoint;Tint:TColor;
    function QuietAt(X,Y:Double):Double;
    begin
      if (FPlan=nil) or (FPlan.Count=0) then Exit(1);
      F:=Screen(Ship);Result:=0.30+0.70*EnsureRange((Hypot(X-F.X,Y-F.Y)/S-0.08)/0.15,0.0,1.0);
    end;
  begin
    Pulse:=V.Pulse;if not TransparentBackground then begin Surface.FillRect(0,0,W,H,RGB(1,3,11));
    // 大きな色面は背景に置き、近い進路の周囲は明度を抑えて主線を残す。
    for I:=0 to 23 do begin
      Light:=(0.018+0.009*V.Energy+0.008*Pulse)*Sqr(Sin(I*Pi/23));
      Surface.FillRect(0,H*I/24,W,H*(I+1)/24,Shade(Theme,Light));
    end;
    end;
    for I:=0 to 5 do begin
      X:=Wrap(Noise(I,17)-Camera.Center.X*0.008)*W;Y:=Wrap(Noise(I,81)-Camera.Center.Y*0.008)*H;
      Tint:=Palette((I+ToBody*3+2) mod 8);Size:=S*(0.16+Noise(I,22)*0.18);
      for J:=3 downto 1 do Surface.Circle(X,Y,Size*(0.7+J*0.3),Tint,True,1,(0.008+0.003*Pulse)*(4-J));
    end;
    Step:=EnsureRange(H/(Camera.Span*0.6),S*0.08,S*0.25);
    Offset:=Wrap(-Camera.Center.X*Scale*0.3/Step)*Step;
    for I:=-1 to Ceil(W/Step) do begin X:=Offset+I*Step;
      for J:=0 to 6 do begin Y:=H*J/7;Focus:=QuietAt(X,Y+H/14);
        Surface.Line(X,Y+3,X,Y+H/7-8,Theme,1,(0.065+0.025*Pulse)*Focus);
      end;
    end;
    Offset:=Wrap(-Camera.Center.Y*Scale*0.3/Step)*Step;
    for I:=-1 to Ceil(H/Step) do begin Y:=Offset+I*Step;
      Surface.Line(0,Y,W,Y,Theme,1,0.045+0.012*Pulse);
    end;
    // 星の視差と短い星座線。ラップ境界を結んで画面を横断する線は作らない。
    for I:=0 to 511 do begin
      Depth:=0.08+0.18*(I mod 3);X:=Wrap(Noise(I,13)-Camera.Center.X*Depth/18);Y:=Wrap(Noise(I,71)-Camera.Center.Y*Depth/13);
      Light:=(0.22+0.42*Noise(I,47)+0.10*Sin(T*0.6+I))*(1+0.14*Pulse)*QuietAt(X*W,Y*H);
      Size:=0.5+Noise(I,31)*1.25;
      if TransparentBackground then Surface.Circle(X*W,Y*H,Size,RGB(144,188,246),True,1,Min(0.75,Light*0.75))
      else Surface.Circle(X*W,Y*H,Size,Shade(RGB(144,188,246),Min(1.0,Light)),True);
      if I mod 23=0 then begin
        Surface.Line(X*W-3,Y*H,X*W+3,Y*H,Theme,1,0.45);
        Surface.Line(X*W,Y*H-3,X*W,Y*H+3,Theme,1,0.45);
      end;
      if (I mod 13=0) and (X<0.96) and (Y<0.96) then begin
        Surface.Line(X*W,Y*H,(X+0.028)*W,(Y+0.024)*H,Theme,1,0.13);
        Surface.FillRect(X*W-1,Y*H-1,X*W+2,Y*H+2,Theme,0.35);
      end;
    end;
    FStats.Stars:=512;
  end;
  procedure Planet(Index:Integer);
  var Body:TOrbitBody;X,P,Q:TOrbitPoint;K:Integer;Opacity,Radius:Double;Tint:TColor;
  begin
    Body:=FPlan.Bodies[Index];
    if (T<Body.Show) or (T>Body.Clear) then Exit;
    X:=Screen(Body.Center);Radius:=Body.RX*Scale;
    if (X.X+Radius<0) or (X.X-Radius>W) or (X.Y+Radius<0) or (X.Y-Radius>H) then Exit;
    Opacity:=Min(1.0,Min((T-Body.Show)/0.8,(Body.Clear-T)/0.8));Opacity:=Max(0.0,Opacity);
    Tint:=Palette(Body.Hue);
    Dot(Body.Center,Body.Radius*(1.55+0.12*V.Pulse),Tint,(0.10+0.035*V.Pulse)*Opacity);
    Dot(Body.Center,Body.Radius*1.20,Tint,0.14*Opacity);
    Dot(Body.Center,Body.Radius,Shade(Tint,0.22),Opacity);
    // 重なり円で惑星の輪郭と照らされた球体の陰影を保つ。
    for K:=0 to 9 do begin
      P:=OrbitPoint(Body.Center.X-Body.Radius*(0.015+K*0.014),Body.Center.Y-Body.Radius*(0.012+K*0.012));
      Dot(P,Body.Radius*(0.96-K*0.06),Shade(Tint,0.27+K*0.045),Opacity*0.92);
    end;
    P:=OrbitPoint(Body.Center.X-Body.Radius*0.28,Body.Center.Y-Body.Radius*0.25);Dot(P,Body.Radius*0.12,RGB(217,241,255),Opacity*0.65);
    // 惑星の計器環は細い点線だけ。明るい主線は実際の未来ルートから別に描く。
    // 実軌道と異なる細い装飾環は低輝度。採用音の接触は明るい主軌道だけ。
    P:=OrbitBodyAt(Body,0);P:=OrbitPoint(Body.Center.X+(P.X-Body.Center.X)*1.13,Body.Center.Y+(P.Y-Body.Center.Y)*1.13);
    for K:=1 to 64 do begin Q:=OrbitBodyAt(Body,K*2*Pi/64);
      Q:=OrbitPoint(Body.Center.X+(Q.X-Body.Center.X)*1.13,Body.Center.Y+(Q.Y-Body.Center.Y)*1.13);
      if K mod 3<>0 then Line(P,Q,Tint,0.003,Opacity*0.12);P:=Q;
    end;
  end;
  procedure FutureRoute;
  var I,K:Integer;A,B:TOrbitGuideSample;P,Q,R,Tangent,Normal:TOrbitPoint;D,Opacity,At:Double;Tint:TColor;
  begin
    if V.Horizon<=0 then Exit;
    // 遠い未来から近い未来の順に合成し、近い進路がループの重なりでも読めるようにする。
    for I:=ORBIT_GUIDE_STEPS downto 1 do begin
      A:=OrbitGuideAt(FPlan,T,V.Horizon,(I-1)/ORBIT_GUIDE_STEPS);B:=OrbitGuideAt(FPlan,T,V.Horizon,I/ORBIT_GUIDE_STEPS);
      Tint:=Palette(FPlan.Bodies[FPlan.Legs[A.Leg].ToBody].Hue);Opacity:=A.Opacity;
      Line(A.P,B.P,Tint,0.075,Opacity*0.12);Line(A.P,B.P,Tint,0.014,Opacity);
      Line(A.P,B.P,RGB(217,247,255),0.003,Opacity*0.32);Inc(FStats.RouteSegments);
    end;
    // 進行方向の矢印も同じ曲線から求める。音要素のリングとは形を分ける。
    for K:=0 to 17 do begin
      At:=0.24+K*0.34;if At>=V.Horizon then Break;
      P:=FPlan.CursorAt(T+At);Q:=FPlan.CursorAt(T+At+0.015);R:=FPlan.CursorAt(T+At-0.015);
      D:=Hypot(Q.X-R.X,Q.Y-R.Y);if D<1E-8 then Continue;
      Tangent:=OrbitPoint((Q.X-R.X)/D,(Q.Y-R.Y)/D);Normal:=OrbitPoint(-Tangent.Y,Tangent.X);
      Opacity:=0.60*OrbitMarkerOpacity(At,V.Horizon);
      Q:=OrbitPoint(P.X-Tangent.X*0.055+Normal.X*0.032,P.Y-Tangent.Y*0.055+Normal.Y*0.032);
      R:=OrbitPoint(P.X-Tangent.X*0.055-Normal.X*0.032,P.Y-Tangent.Y*0.055-Normal.Y*0.032);
      Line(Q,P,RGB(190,239,255),0.010,Opacity);Line(P,R,RGB(190,239,255),0.010,Opacity);
    end;
  end;
  procedure FutureMarkers;
  var I,K,Count,Rank:Integer;Indices:array[0..127] of Integer;N:TOrbitTap;P,A,B:TOrbitPoint;
    Ahead,Opacity,U,Radius,Angle:Double;Near:Boolean;Kind:TOrbitMarkKind;
  begin
    Count:=0;
    for I:=Max(0,Next) to Min(FPlan.Count-1,Next+ORBIT_MARKER_LIMIT-1) do begin
      N:=FPlan.Taps[I];Ahead:=N.Time-T;if Ahead>V.Horizon then Break;
      if OrbitMarkerOpacity(Ahead,V.Horizon)<0.015 then Continue;P:=Screen(N.P);
      if (P.X< -30) or (P.X>W+30) or (P.Y< -30) or (P.Y>H+30) then Continue;
      Indices[Count]:=I;Inc(Count);
    end;
    // 遠い予告から描き、重なる連打でも直近の塗りつぶしと記号を最前面に保つ。
    for K:=Count-1 downto 0 do begin I:=Indices[K];Rank:=K+1;N:=FPlan.Taps[I];Ahead:=N.Time-T;P:=Screen(N.P);
      Opacity:=OrbitMarkerOpacity(Ahead,V.Horizon);U:=EnsureRange(1-Ahead/1.45,0.0,1.0);Near:=(Ahead<=1.45) and (Rank<=8);
      if Near then begin Inc(FStats.NearMarkers);Radius:=(0.06+N.Strength*0.018)*Scale;end
      else begin Inc(FStats.FarMarkers);Radius:=(0.023+0.010*N.Strength)*Scale;end;
      A:=FPlan.CursorAt(N.Time-0.015);B:=FPlan.CursorAt(N.Time+0.015);Angle:=ArcTan2(B.Y-A.Y,B.X-A.X);
      Kind:=OrbitMarkKind(N);
      if FPlan.IsRoll(I) then Kind:=omArrow;
      DrawOrbitMark(Surface,P.X,P.Y,Radius,Angle,Opacity,U,Kind,OrbitMarkColor(N),Near);Inc(FStats.Markers);
    end;
  end;
  procedure Hud;
  var K,N,V,Bits,J:Integer;X,Y,Z:Double;
  const Digits:array[0..9] of Byte=($3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F);
    AX:array[0..6] of Double=(0,1,1,0,0,0,0);AY:array[0..6] of Double=(0,0,1,2,1,0,1);
    BX:array[0..6] of Double=(1,1,1,1,0,0,1);BY:array[0..6] of Double=(0,1,2,2,2,1,1);
  begin
    V:=Hit+1;Z:=S*0.010;Y:=H*0.035;
    for K:=5 downto 0 do begin N:=V mod 10;V:=V div 10;Bits:=Digits[N];X:=W*0.94-(5-K)*Z*1.6;
      for J:=0 to 6 do if Bits and (1 shl J)<>0 then Surface.Line(X+AX[J]*Z,Y+AY[J]*Z,X+BX[J]*Z,Y+BY[J]*Z,RGB(126,195,225),1);
    end;
    Progress:=EnsureRange(T/Max(0.001,FPlan.SoundEnd),0.0,1.0);
    Surface.FillRect(W*0.06,H*0.97,W*(0.06+0.88*Progress),H*0.972,RGB(56,144,187));
  end;
begin
  W:=Frame.Width;H:=Frame.Height;S:=Min(W,H);Aspect:=W/H;T:=Frame.Time;
  FStats:=Default(TOrbitRenderStats);V:=OrbitVisualState(FPlan,T);FStats.Horizon:=V.Horizon;FStats.Density:=V.Density;
  Theme:=Palette(0);ToBody:=0;Hit:=-1;Ship:=OrbitPoint(0,0);
  if (FPlan<>nil) and (FPlan.Count>0) then begin
    L:=FPlan.Legs[FPlan.LegAt(T)];ToBody:=L.ToBody;Theme:=Palette(FPlan.Bodies[ToBody].Hue);Hit:=FPlan.Before(T);Ship:=FPlan.CursorAt(T);
  end;
  Camera.Center:=OrbitPoint(0,0);Camera.Span:=8;
  if FPlan<>nil then Camera:=FPlan.CameraAt(T,Aspect);
  Scale:=H/Camera.Span;Background;
  DrawOrbitShow(Surface,FPlan,T,W,H,Camera,False);
  if (FPlan=nil) or (FPlan.Count=0) then Exit;
  LegIndex:=FPlan.LegAt(T);L:=FPlan.Legs[LegIndex];FromBody:=L.FromBody;ToBody:=L.ToBody;Hit:=FPlan.Before(T);Next:=Hit+1;
  // 現在と前後の惑星だけを空間に置く。全曲の惑星を最初から画面へ並べない。
  for I:=Min(FPlan.BodyCount-1,ToBody+1) downto Max(0,FromBody-1) do Planet(I);
  for I:=Hit downto Max(0,Hit-MaxEffects+1) do begin
    N:=FPlan.Taps[I];Age:=T-N.Time;if Age>=ORBIT_EFFECT_LIFE then Break;Inc(FStats.Effects);
    B:=FPlan.Bodies[FPlan.Legs[N.Leg].ToBody];C:=OrbitMarkColor(N);Alpha:=OrbitFade(Age);U:=Age/ORBIT_EFFECT_LIFE;
    Ring(N.P,0.08+U*0.67,C,0.014,Alpha);Ring(N.P,0.06+U*0.95,C,0.006,Alpha*0.45);
    for J:=0 to 17 do begin Angle:=J*Pi/9+N.Source*0.37;D:=(0.09+0.58*(1-Sqr(1-U)))*(0.7+Noise(J,Cardinal(N.Source))*0.5);
      P:=OrbitPoint(N.P.X+Cos(Angle)*D,N.P.Y+Sin(Angle)*D);Q:=OrbitPoint(P.X+Cos(Angle)*0.07,P.Y+Sin(Angle)*0.07);
      Line(P,Q,C,0.012,Alpha);
    end;
    if Age<0.09 then begin Dot(N.P,0.10,RGB(245,254,255),1-Age/0.09);
      Line(OrbitPoint(N.P.X-0.32,N.P.Y),OrbitPoint(N.P.X+0.32,N.P.Y),clWhite,0.014,1-Age/0.09);
      Line(OrbitPoint(N.P.X,N.P.Y-0.32),OrbitPoint(N.P.X,N.P.Y+0.32),clWhite,0.014,1-Age/0.09);
    end;
  end;
  // 予告の主線と判定リングを反応粒子より手前へ置き、密音でも進路を読ませる。
  FutureRoute;FutureMarkers;
  if Hit>=0 then begin N:=FPlan.Taps[Hit];P:=Screen(N.P);DrawOrbitGood(Surface,P.X,P.Y,T-N.Time,Round(W),Round(H),OrbitMarkColor(N),FPlan.IsRoll(Hit));end;
  C:=Palette(FPlan.Bodies[ToBody].Hue);Alpha:=1;
  if T>FPlan.SoundEnd then Alpha:=Max(0.0,1-(T-FPlan.SoundEnd)/0.9);
  P:=FPlan.CursorAt(T-0.28);
  for J:=1 to 28 do begin Q:=FPlan.CursorAt(T-0.28+J*0.01);
    Line(P,Q,C,0.015+0.027*J/28,Alpha*J/38);P:=Q;
  end;
  Ship:=FPlan.CursorAt(T);D:=OrbitShipSize(FPlan,T);Dot(Ship,0.10*D,C,Alpha*0.18);Dot(Ship,0.063*D,C,Alpha*0.35);Dot(Ship,0.035*D,clWhite,Alpha);
  Ring(Ship,0.055*D,C,0.010,Alpha);Hud;DrawOrbitShow(Surface,FPlan,T,W,H,Camera,True);
end;
end.
