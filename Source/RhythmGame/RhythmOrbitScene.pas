unit RhythmOrbitScene;
// Type.Vの惑星・航路・判定を同じカメラで投影し、宇宙の背景に重ねる。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmOrbitPlan,RhythmEqualizer,RhythmOrbitGuide;
type
  TOrbitRenderStats=record
    RouteSegments,Markers,Effects,Stars:Integer;
    Horizon,Density:Double;
  end;
  TOrbitAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio; // 呼び出し側からの借用。描画中の生存は呼び出し側が保証する。
    FTransparentBackground:Boolean;
    FRef:TRhythmPlanRef;
    FPlan:TOrbitPlan; // シーンが所有し、入力が変わったときに差し替える。
    FAttempt,FError:string;
    FStats:TOrbitRenderStats;
    FCourse:TOrbitCourse;
    FLayoutWidth,FLayoutHeight:Integer;
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
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics,RhythmOrbitTypes,RhythmOrbitShow,RhythmOrbitMarks;
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
var V:TOrbitVisualState;L:TOrbitLeg;Leg:Integer;
begin Activity:=Default(TEqualizerActivity);Result:=FPlan<>nil;if not Result or (FPlan.Count=0) then Exit;
  V:=OrbitVisualState(FPlan,Time);if not V.Playing then Exit;
  Activity.Valid:=Time<=FPlan.EndTime;Activity.Pulse:=V.Pulse;
  Activity.Energy:=V.Energy;Activity.Hit:=V.LastHit-V.FirstTap;
  Leg:=FCourse.LegAt(Time);
  if Leg>=0 then begin L:=FCourse.Leg(Leg);Activity.Hue:=FCourse.Body(L.ToBody).Hue;end
  else begin L:=FPlan.Legs[FPlan.LegAt(Time)];Activity.Hue:=FPlan.Bodies[L.ToBody].Hue;end;
end;
procedure TOrbitAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+FAudio.SourceRevision else Key:=Key+'|none';
  if Key<>FAttempt then begin
    FAttempt:=Key;FreeAndNil(FPlan);FError:='';
    FCourse:=Default(TOrbitCourse);FLayoutWidth:=0;
    if FAudio<>nil then
      try FPlan:=TOrbitPlan.Load(FRef,FAudio,Frame.Direction);except on E:Exception do FError:=E.Message;end;
  end;
  if (FPlan=nil) or (FPlan.Count=0) or (Frame.Width<=0) or (Frame.Height<=0) then Exit;
  // 同じ計画でも画面寸法が変われば、画面外の配置と予告の余白を計算し直す。
  if (FLayoutWidth=Frame.Width) and (FLayoutHeight=Frame.Height) then Exit;
  FCourse.Prepare(FPlan,Frame.Width,Frame.Height);
  FLayoutWidth:=Frame.Width;FLayoutHeight:=Frame.Height;
end;
procedure TOrbitAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
const MaxEffects=24;
var W,H,S,T,StoryTime,Scale,Age,Alpha,U,Angle,D,Progress,HitRadius:Double;View:TOrbitView;
  I,J,Hit,FromBody,ToBody,MarkerCount:Integer;L:TOrbitLeg;N:TOrbitTap;
  Markers:TOrbitMarkers;
  P,Q,Ship,FirstPlanet,Destination:TOrbitPoint;C,Theme:TColor;V:TOrbitVisualState;
  HitScale,EffectScale,EffectLife,MarkRadius,X,Y,Zoom,CursorStroke:Double;
  function Cursor(At:Double):TOrbitPoint;
  begin Result:=View.Project(FCourse.CursorAt(At));end;
  procedure Dot(const P:TOrbitPoint;Radius:Double;Color:TColor;Opacity:Double);
  begin Surface.Circle(P.X,P.Y,Max(1.0,Radius),Color,True,1,Opacity);end;
  procedure Background;
  var I,J:Integer;X,Y,Depth,Light,Size,Step,Offset,Focus,Pulse,TravelX,TravelY:Double;F:TOrbitPoint;Tint:TColor;
    function QuietAt(X,Y:Double):Double;
    begin
      if (FPlan=nil) or (FPlan.Count=0) then Exit(1);
      Result:=0.30+0.70*EnsureRange((Hypot(X-F.X,Y-F.Y)/S-0.08)/0.15,0.0,1.0);
    end;
  begin
    TravelX:=View.Center.X-View.ViewportCenter.X;
    TravelY:=View.Center.Y-View.ViewportCenter.Y;
    F:=Ship;Pulse:=V.Pulse;if not TransparentBackground then begin Surface.FillRect(0,0,W,H,RGB(1,3,11));
    // 大きな色面は背景に置き、近い進路の周囲は明度を抑えて主線を残す。
    for I:=0 to 23 do begin
      Light:=(0.018+0.009*V.Energy+0.008*Pulse)*Sqr(Sin(I*Pi/23));
      Surface.FillRect(0,H*I/24,W,H*(I+1)/24,Shade(Theme,Light));
    end;
    end;
    for I:=0 to 5 do begin
      X:=Wrap(0.5+(Noise(I,17)-0.5)*Zoom-TravelX/W*0.08)*W;
      Y:=Wrap(0.5+(Noise(I,81)-0.5)*Zoom-TravelY/H*0.08)*H;
      Tint:=Palette((I+ToBody*3+2) mod 8);Size:=S*(0.16+Noise(I,22)*0.18)*Zoom;
      for J:=3 downto 1 do Surface.Circle(X,Y,Size*(0.7+J*0.3),Tint,True,1,(0.008+0.003*Pulse)*(4-J));
    end;
    Step:=S*0.21*Zoom;
    Offset:=Wrap(-TravelX*0.45/(S*0.21))*Step;
    for I:=-1 to Ceil(W/Step) do begin X:=Offset+I*Step;
      for J:=0 to 6 do begin Y:=H*J/7;Focus:=QuietAt(X,Y+H/14);
        Surface.Line(X,Y+3,X,Y+H/7-8,Theme,1,(0.065+0.025*Pulse)*Focus);
      end;
    end;
    Offset:=Wrap(-TravelY*0.45/(S*0.21))*Step;
    for I:=-1 to Ceil(H/Step) do begin Y:=Offset+I*Step;
      Surface.Line(0,Y,W,Y,Theme,1,0.045+0.012*Pulse);
    end;
    // 星の視差と短い星座線。ラップ境界を結んで画面を横断する線は作らない。
    for I:=0 to 511 do begin
      Depth:=0.08+0.18*(I mod 3);
      X:=Wrap(0.5+(Noise(I,13)-0.5)*Zoom-TravelX/W*Depth);
      Y:=Wrap(0.5+(Noise(I,71)-0.5)*Zoom-TravelY/H*Depth);
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
  var Body:TOrbitBody;P:TOrbitPoint;K:Integer;Opacity,Halo:Double;Tint:TColor;
  begin
    Body:=FCourse.Body(Index);
    Body.Center:=View.Project(Body.Center);
    Body.Radius:=Body.Radius*Zoom;
    Halo:=Body.Radius*(1.55+0.12*V.Pulse);
    if (Body.Center.X+Halo<0) or (Body.Center.X-Halo>W) or
      (Body.Center.Y+Halo<0) or (Body.Center.Y-Halo>H) then Exit;
    Opacity:=EnsureRange((Body.Clear-StoryTime)/0.8,0.0,1.0);
    if Index>ToBody then Opacity:=Opacity*0.48;
    if Index<FromBody then Opacity:=Opacity*0.58;
    if Opacity<=0 then Exit;
    Tint:=Palette(Body.Hue);
    Dot(Body.Center,Halo,Tint,(0.10+0.035*V.Pulse)*Opacity);
    Dot(Body.Center,Body.Radius*1.20,Tint,0.14*Opacity);
    Dot(Body.Center,Body.Radius,Shade(Tint,0.22),Opacity);
    // 重なり円で惑星の輪郭と照らされた球体の陰影を保つ。
    for K:=0 to 9 do begin
      P:=OrbitPoint(Body.Center.X-Body.Radius*(0.015+K*0.014),Body.Center.Y-Body.Radius*(0.012+K*0.012));
      Dot(P,Body.Radius*(0.96-K*0.06),Shade(Tint,0.27+K*0.045),Opacity*0.92);
    end;
    P:=OrbitPoint(Body.Center.X-Body.Radius*0.28,Body.Center.Y-Body.Radius*0.25);Dot(P,Body.Radius*0.12,RGB(217,241,255),Opacity*0.65);
  end;
  procedure FutureRoute;
  var I,K,Count:Integer;Points:TOrbitRoute;P,Q,R,Tangent,Normal,NearPoint,FarPoint:TOrbitPoint;
    D,Opacity,At,Horizon,ArrowScale:Double;
  begin
    if V.Horizon<=0 then Exit;
    Count:=FCourse.Route(FPlan,T,T+V.Horizon,Markers,MarkerCount,Points);
    for I:=1 to Count do begin
      P:=View.Project(Points[I].P);
      if (P.X<0) or (P.X>W) or (P.Y<0) or (P.Y>H) then begin
        Count:=I;
        Break;
      end;
    end;
    FStats.RouteSegments:=Count;
    Horizon:=Points[Count].Time-T;
    ArrowScale:=S/3.7;
    // 通過点をサンプルに含め、連打で時刻が詰まっても線が丸を飛び越えない。
    FarPoint:=View.Project(Points[Count].P);
    for I:=Count downto 1 do begin
      NearPoint:=View.Project(Points[I-1].P);
      Opacity:=(0.18+0.79*OrbitMarkerOpacity(Points[I-1].Time-T,Horizon))*V.PreviewAlpha;
      Surface.Line(NearPoint.X,NearPoint.Y,FarPoint.X,FarPoint.Y,Theme,Max(1.0,0.075*ArrowScale),Opacity*0.12);
      Surface.Line(NearPoint.X,NearPoint.Y,FarPoint.X,FarPoint.Y,Theme,Max(1.0,0.022*ArrowScale),Opacity);
      Surface.Line(NearPoint.X,NearPoint.Y,FarPoint.X,FarPoint.Y,RGB(217,247,255),Max(1.0,0.008*ArrowScale),Opacity*0.62);
      FarPoint:=NearPoint;
    end;
    // 進行方向の矢印も同じ曲線から求める。音要素のリングとは形を分ける。
    for K:=0 to 3 do begin
      At:=0.24+K*0.34;if At>=Horizon then Break;
      P:=Cursor(T+At);Q:=Cursor(T+At+0.015);R:=Cursor(T+At-0.015);
      D:=Hypot(Q.X-R.X,Q.Y-R.Y);if D<1E-8 then Continue;
      Tangent:=OrbitPoint((Q.X-R.X)/D,(Q.Y-R.Y)/D);Normal:=OrbitPoint(-Tangent.Y,Tangent.X);
      Opacity:=0.60*OrbitMarkerOpacity(At,Horizon)*V.PreviewAlpha;
      Q:=OrbitPoint(P.X+(-Tangent.X*0.055+Normal.X*0.032)*ArrowScale,P.Y+(-Tangent.Y*0.055+Normal.Y*0.032)*ArrowScale);
      R:=OrbitPoint(P.X+(-Tangent.X*0.055-Normal.X*0.032)*ArrowScale,P.Y+(-Tangent.Y*0.055-Normal.Y*0.032)*ArrowScale);
      Surface.Line(Q.X,Q.Y,P.X,P.Y,RGB(190,239,255),Max(1.0,0.010*ArrowScale),Opacity);
      Surface.Line(P.X,P.Y,R.X,R.Y,RGB(190,239,255),Max(1.0,0.010*ArrowScale),Opacity);
    end;
  end;
  procedure FutureMarkers;
  var I,K:Integer;Mark:TOrbitMarker;N:TOrbitTap;A,B,P:TOrbitPoint;
    Angle:Double;Kind:TOrbitMarkKind;
  begin
    for K:=MarkerCount-1 downto 0 do begin
      Mark:=Markers[K];I:=Mark.TapIndex;N:=FPlan.Taps[I];
      A:=Cursor(N.Time-0.015);B:=Cursor(N.Time+0.015);Angle:=ArcTan2(B.Y-A.Y,B.X-A.X);
      Kind:=OrbitMarkKind(N);
      if FPlan.IsRoll(I) then Kind:=omArrow;
      if Mark.TapCount>1 then Kind:=omChord;
      P:=View.Project(Mark.Center);
      DrawOrbitMark(Surface,P.X,P.Y,Mark.Radius*Zoom,Angle,Mark.Opacity,Mark.Approach,
        Kind,OrbitMarkColor(N),Mark.Visibility);
      Inc(FStats.Markers);
    end;
  end;
  procedure Hud;
  var K,N,Count,Bits,J:Integer;X,Y,Z:Double;
  const Digits:array[0..9] of Byte=($3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F);
    AX:array[0..6] of Double=(0,1,1,0,0,0,0);AY:array[0..6] of Double=(0,0,1,2,1,0,1);
    BX:array[0..6] of Double=(1,1,1,1,0,0,1);BY:array[0..6] of Double=(0,1,2,2,2,1,1);
  begin
    Count:=FCourse.HitCount(T);Z:=S*0.010;Y:=H*0.035;
    for K:=5 downto 0 do begin N:=Count mod 10;Count:=Count div 10;Bits:=Digits[N];X:=W*0.94-(5-K)*Z*1.6;
      for J:=0 to 6 do if Bits and (1 shl J)<>0 then Surface.Line(X+AX[J]*Z,Y+AY[J]*Z,X+BX[J]*Z,Y+BY[J]*Z,RGB(126,195,225),1);
    end;
    Progress:=EnsureRange(T/Max(0.001,FPlan.SoundEnd),0.0,1.0);
    Surface.FillRect(W*0.06,H*0.97,W*(0.06+0.88*Progress),H*0.972,RGB(56,144,187));
  end;
begin
  W:=Frame.Width;H:=Frame.Height;S:=Min(W,H);T:=Frame.Time;
  HitRadius:=OrbitHitRadius(S);
  FStats:=Default(TOrbitRenderStats);V:=OrbitVisualState(FPlan,T);FStats.Horizon:=V.Horizon;FStats.Density:=V.Density;
  Theme:=Palette(0);FromBody:=0;ToBody:=0;Ship:=OrbitPoint(0,0);
  StoryTime:=T;View.ViewportCenter:=OrbitPoint(W*0.5,H*0.5);View.Center:=View.ViewportCenter;View.Scale:=1;
  if (FPlan<>nil) and (FPlan.Count>0) then begin
    StoryTime:=FCourse.StoryTime(T);
    L:=FCourse.Leg(FCourse.LegAt(T));FromBody:=L.FromBody;ToBody:=L.ToBody;
    Theme:=Palette(FCourse.Body(ToBody).Hue);
    View:=FCourse.ViewAt(T);
    Ship:=Cursor(T);
    FirstPlanet:=View.Project(FCourse.Body(0).Center);
    Destination:=Cursor(FPlan.SoundEnd);
  end;
  Zoom:=View.Scale;Scale:=S/8*Zoom;Background;
  if (FPlan=nil) or (FPlan.Count=0) then Exit;
  DrawOrbitShow(Surface,FPlan,StoryTime,W,H,FirstPlanet,Destination,False);
  Hit:=FCourse.HitIndex(T);
  // 現在と前後の惑星だけを空間に置く。全曲の惑星を最初から画面へ並べない。
  for I:=Min(FCourse.BodyCount-1,FromBody+1) downto Max(0,FromBody-1) do Planet(I);
  HitScale:=S/3.7*Zoom;
  for I:=Hit downto Max(V.FirstTap,Hit-MaxEffects+1) do begin
    N:=FPlan.Taps[I];Age:=T-N.Time;if Age>=0.18 then Break;
    // 予告された音だけ判定を発光させる。
    if FCourse.HitIndex(N.Time)<>I then Continue;
    MarkRadius:=FCourse.HitRadiusAt(N.Time);
    EffectLife:=0.18;
    Inc(FStats.Effects);
    EffectScale:=HitScale*MarkRadius/HitRadius;
    U:=Age/EffectLife;C:=OrbitMarkColor(N);Alpha:=OrbitFade(U*ORBIT_EFFECT_LIFE);
    P:=Cursor(N.Time);X:=P.X;Y:=P.Y;
    for J:=0 to 11 do begin Angle:=J*Pi/6+N.Source*0.37;D:=(0.09+0.36*(1-Sqr(1-U)))*(0.7+Noise(J,Cardinal(N.Source))*0.5);
      P:=OrbitPoint(X+Cos(Angle)*D*EffectScale,Y+Sin(Angle)*D*EffectScale);
      Surface.Line(P.X,P.Y,P.X+Cos(Angle)*0.07*EffectScale,P.Y+Sin(Angle)*0.07*EffectScale,C,Max(1.0,0.012*EffectScale),Alpha);
    end;
    if Age<0.09 then begin
      Surface.Circle(X,Y,MarkRadius*Zoom*(0.72-0.22*Age/0.09),RGB(245,254,255),True,1,1-Age/0.09);
      D:=0.32*EffectScale;
      Surface.Line(X-D,Y,X+D,Y,clWhite,Max(1.0,0.014*EffectScale),1-Age/0.09);
      Surface.Line(X,Y-D,X,Y+D,clWhite,Max(1.0,0.014*EffectScale),1-Age/0.09);
    end;
  end;
  // 予告の主線と判定リングを反応粒子より手前へ置き、密音でも進路を読ませる。
  MarkerCount:=FCourse.Visible(V,T,Markers);
  FutureRoute;
  if Hit>=V.FirstTap then begin N:=FPlan.Taps[Hit];P:=Cursor(N.Time);DrawOrbitGood(Surface,P.X,P.Y,T-N.Time,Round(W),Round(H),OrbitMarkColor(N),FPlan.IsRoll(Hit));end;
  FutureMarkers;
  C:=Palette(FCourse.Body(ToBody).Hue);Alpha:=1;
  if T>FPlan.SoundEnd then Alpha:=Max(0.0,1-(T-FPlan.SoundEnd)/0.9);
  P:=Cursor(T-0.10);
  for J:=1 to 10 do begin Q:=Cursor(T-0.10+J*0.01);
    Surface.Line(P.X,P.Y,Q.X,Q.Y,C,Max(1.0,(0.015+0.027*J/10)*Scale),Alpha*0.56*Sqr(J/10));P:=Q;
  end;
  // 判定円よりひと回り小さい照準。輪の内側を開け、重なったときもマークを読めるようにする。
  D:=OrbitCursorRadius(S)*Zoom*OrbitShipSize(FPlan,StoryTime);
  CursorStroke:=Max(1.0,D*0.10);
  Surface.Circle(Ship.X,Ship.Y,D,RGB(5,12,21),False,CursorStroke*2.4,Alpha*0.95);
  Surface.Circle(Ship.X,Ship.Y,D,clWhite,False,CursorStroke,Alpha);
  Surface.Circle(Ship.X,Ship.Y,Max(1.0,D*0.14),clWhite,True,1,Alpha);
  if V.Playing then Hud;
  DrawOrbitShow(Surface,FPlan,StoryTime,W,H,FirstPlanet,Destination,True);
end;
end.
