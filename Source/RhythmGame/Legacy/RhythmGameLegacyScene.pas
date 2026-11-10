unit RhythmGameLegacyScene;
// 画面全体のマーク・曲線・光るカーソルを描く。任意seekでも成功数や粒子は変わらない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmGameLegacyPlan;
type
  TLegacyGameAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;FTransparentBackground:Boolean;
    FRef:TRhythmPlanRef;
    FPlan:TLegacyGamePlan;
    FAttempt,FError:string;
  public
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    property TransparentBackground:Boolean read FTransparentBackground write FTransparentBackground;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;

function Tint(Hue:Integer):TColor;
begin
  case Hue mod 8 of
    0:Result:=RGB(64,224,255);
    1:Result:=RGB(255,105,208);
    2:Result:=RGB(255,205,74);
    3:Result:=RGB(127,255,141);
    4:Result:=RGB(154,132,255);
    5:Result:=RGB(255,130,88);
    6:Result:=RGB(90,177,255);
    else Result:=RGB(244,247,255);
  end;
end;

destructor TLegacyGameAnimation.Destroy;
begin FPlan.Free;inherited;end;

procedure TLegacyGameAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;end;

function TLegacyGameAnimation.Notice:string;
begin Result:=FError;end;

procedure TLegacyGameAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key+'|'+FAudio.SourceRevision else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;FreeAndNil(FPlan);FError:='';
  if FAudio=nil then Exit;
  try FPlan:=TLegacyGamePlan.Load(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;end;
end;

procedure TLegacyGameAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var
  W,H,S,Clock,Age,U,R,Alpha,Theta,Distance,Progress,Lead:Double;
  I,J,First,Last,Drawn,Hit,Next:Integer;
  N:TGameNote;P,Q,Cursor:TGamePoint;C:TColor;
  function PX(X:Double):Double;
  begin Result:=W*(0.06+X*0.88);end;
  function PY(Y:Double):Double;
  begin Result:=H*(0.10+Y*0.80);end;
  procedure Ring(const P:TGamePoint;Radius:Double;Color:TColor;Width:Double;Opacity:Double=1);
  begin Surface.Circle(PX(P.X),PY(P.Y),Radius*S,Color,False,Max(1.0,Width*S),Opacity);end;
  procedure Segment(const A,B:TGamePoint;Color:TColor;Width:Double;Opacity:Double=1);
  begin Surface.Line(PX(A.X),PY(A.Y),PX(B.X),PY(B.Y),Color,Max(1.0,Width*S),Opacity);end;
  procedure Tick(const P:TGamePoint;Scale:Double;Color:TColor;Opacity:Double);
  begin
    Segment(GamePoint(P.X-0.013*Scale,P.Y),GamePoint(P.X-0.002*Scale,P.Y+0.012*Scale),Color,0.003,Opacity);
    Segment(GamePoint(P.X-0.002*Scale,P.Y+0.012*Scale),GamePoint(P.X+0.019*Scale,P.Y-0.015*Scale),Color,0.003,Opacity);
  end;
  procedure Counter(Value:Integer);
  const Digits:array[0..9] of Byte=($3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F);
    AX:array[0..6] of Double=(0,1,1,0,0,0,0);AY:array[0..6] of Double=(0,0,1,2,1,0,1);
    BX:array[0..6] of Double=(1,1,1,1,0,0,1);BY:array[0..6] of Double=(0,1,2,2,2,1,1);
  var D,Bits,I,J:Integer;X,Y,Size:Double;
  begin
    Size:=S*0.014;Y:=H*0.045;
    for I:=5 downto 0 do begin
      D:=Value mod 10;Value:=Value div 10;Bits:=Digits[D];X:=W*0.5+(I-2.8)*Size*1.6;
      for J:=0 to 6 do if Bits and (1 shl J)<>0 then
        Surface.Line(X+AX[J]*Size,Y+AY[J]*Size,X+BX[J]*Size,Y+BY[J]*Size,RGB(173,213,231),Max(1.0,S*0.002));
    end;
  end;
begin
  W:=Frame.Width;H:=Frame.Height;S:=Min(W,H);Clock:=Frame.Time;
  if not TransparentBackground then Surface.FillRect(0,0,W,H,clBlack);
  if FPlan=nil then Exit;
  Hit:=FPlan.Before(Clock);Next:=Hit+1;
  FPlan.VisibleRange(Clock,First,Last);
  // 先読みの軌道は次の6区間だけ。明るいカーソルと判定リングを埋めない。
  for I:=Min(FPlan.Count-1,Next+5) downto Next do begin
    N:=FPlan.Notes[I];
    if Clock<N.Appear then Continue;
    C:=Tint(N.Hue);P:=N.A;
    for J:=1 to 24 do begin Q:=GameCurveAt(N,J/24);
      Segment(P,Q,C,0.0015,0.14);P:=Q;
    end;
  end;
  Drawn:=0;
  for I:=Max(0,Next) to Last do begin
    N:=FPlan.Notes[I];if Clock<N.Appear then Continue;
    Inc(Drawn);if Drawn>GAME_VISIBLE_NOTES then Break;
    C:=Tint(N.Hue);Lead:=N.Time-N.Appear;
    U:=EnsureRange((Clock-N.Appear)/Lead,0.0,1.0);
    R:=0.035+N.Strength*0.008;if N.Roll then R:=0.025;
    // 大きな接近リングが音時刻に判定円へ重なる。未来のマークに接触光は出さない。
    Alpha:=Min(1.0,U*8);
    Ring(N.D,R*(1+1.7*(1-U)),C,0.002,Alpha*0.55);
    Ring(N.D,R,C,0.003,Alpha);
    Ring(N.D,R*0.78,RGB(34,61,72),0.001,Alpha);
    Surface.Circle(PX(N.D.X),PY(N.D.Y),S*0.0035,C,True,1,Alpha);
    if N.Roll then begin
      Segment(GamePoint(N.D.X-0.008,N.D.Y-0.008),GamePoint(N.D.X+0.008,N.D.Y+0.008),C,0.0015,Alpha);
      Segment(GamePoint(N.D.X+0.008,N.D.Y-0.008),GamePoint(N.D.X-0.008,N.D.Y+0.008),C,0.0015,Alpha);
    end;
  end;
  // 全ての成功は計画に残し、極端な密音時の粒子だけ直近32打に制限する。
  for I:=Hit downto Max(0,Hit-GAME_VISIBLE_EFFECTS+1) do begin
    N:=FPlan.Notes[I];Age:=Clock-N.Time;if Age>=GAME_EFFECT_LIFE then Break;
    C:=Tint(N.Hue);Alpha:=GameEffectOpacity(Age);U:=Age/GAME_EFFECT_LIFE;
    Ring(N.D,0.035+0.12*U,C,0.003,Alpha*0.8);
    Ring(N.D,0.022+0.18*U,C,0.0015,Alpha*0.45);
    for J:=0 to 9 do begin
      Theta:=J*Pi/5+N.Source*0.37;Distance:=0.022+0.10*(1-Sqr(1-U));
      P:=GamePoint(N.D.X+Cos(Theta)*Distance,N.D.Y+Sin(Theta)*Distance);
      Q:=GamePoint(N.D.X+Cos(Theta)*(Distance+0.012),N.D.Y+Sin(Theta)*(Distance+0.012));
      Segment(P,Q,C,0.0025,Alpha);
    end;
    if Age<0.075 then begin
      Surface.Circle(PX(N.D.X),PY(N.D.Y),S*(0.027-Age*0.18),clWhite,True,1,1-Age/0.075);
      Segment(GamePoint(N.D.X-0.062,N.D.Y),GamePoint(N.D.X+0.062,N.D.Y),clWhite,0.004,1-Age/0.075);
      Segment(GamePoint(N.D.X,N.D.Y-0.062),GamePoint(N.D.X,N.D.Y+0.062),clWhite,0.004,1-Age/0.075);
    end else Tick(N.D,0.8,C,Alpha);
  end;
  if FPlan.Count>0 then begin
    Alpha:=1;
    if Clock>FPlan.SoundEnd then Alpha:=Max(0.0,1-(Clock-FPlan.SoundEnd)/0.8);
    C:=Tint(0);if Next<FPlan.Count then C:=Tint(FPlan.Notes[Next].Hue) else if Hit>=0 then C:=Tint(FPlan.Notes[Hit].Hue);
    P:=FPlan.CursorAt(Clock);
    for J:=18 downto 1 do begin
      Q:=FPlan.CursorAt(Clock-J*0.007);
      Surface.Circle(PX(Q.X),PY(Q.Y),S*(0.003+0.008*(19-J)/18),C,True,1,Alpha*(19-J)/36);
    end;
    Cursor:=P;
    Ring(Cursor,0.020,C,0.003,Alpha*0.5);
    Surface.Circle(PX(Cursor.X),PY(Cursor.Y),S*0.013,C,True,1,Alpha);
    Surface.Circle(PX(Cursor.X),PY(Cursor.Y),S*0.0065,clWhite,True,1,Alpha);
  end;
  Counter(Hit+1);
  Progress:=EnsureRange(Clock/Max(0.001,FPlan.SoundEnd),0.0,1.0);
  Surface.FillRect(W*0.12,H*0.946,W*0.88,H*0.949,RGB(21,37,43));
  Surface.FillRect(W*0.12,H*0.946,W*(0.12+0.76*Progress),H*0.949,RGB(83,207,228));
  if (FPlan.Count>0) and (Hit=FPlan.Count-1) and (Clock>=FPlan.SoundEnd) then
    Tick(GamePoint(0.5,0.99),0.7,RGB(110,255,190),1);
end;
end.
