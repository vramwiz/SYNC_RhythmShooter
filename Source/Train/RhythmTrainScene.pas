unit RhythmTrainScene;
// 列車の屋根・レールと音ハメを同じ座標系で描く。素材が無ければ従来の図形描画に戻る。
interface

uses
  RhythmAnimation, RhythmRenderSurface, RhythmAudio, RhythmPlanRef, RhythmTrainPlan;

type
  TTrainAnimation = class(TAnimationScene)
  private
    FAudio: TRhythmAudio;
    FRef: TRhythmPlanRef;
    FPlan: TTrainPlan;
    FAttempt, FError: string;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref: TRhythmPlanRef);
    procedure Prepare(const Frame: TAnimationFrame); override;
    procedure Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame); override;
    function Notice: string; override;
    property Audio: TRhythmAudio read FAudio write FAudio;
  end;

implementation

uses
  System.SysUtils, System.Math, System.Types, Winapi.Windows, Vcl.Graphics, RhythmTrainArt;

const
  RailY = 3.68;
  Ink = $30241C;
  HeroColor = $50CEF9;
  EnemyColor = $6377E7;
  BossColor = $BC7ECD;
  MainColor = $A76A38;
  NextColor = $767A2C;

function MixColor(A,B: TColor; U: Double): TColor;
begin
  Result := RGB(Round(GetRValue(A)+(GetRValue(B)-GetRValue(A))*U),
    Round(GetGValue(A)+(GetGValue(B)-GetGValue(A))*U),
    Round(GetBValue(A)+(GetBValue(B)-GetBValue(A))*U));
end;

destructor TTrainAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TTrainAnimation.SetReference(const Ref: TRhythmPlanRef);
begin
  FRef := Ref;
end;

function TTrainAnimation.Notice: string;
begin
  Result := FError;
end;

procedure TTrainAnimation.Prepare(const Frame: TAnimationFrame);
var
  Key: string;
begin
  Key := FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key := Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity)
  else Key := Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt := Key;
  FreeAndNil(FPlan);
  FError := '';
  if FAudio=nil then Exit;
  try
    FPlan := TTrainPlan.Load(FRef,FAudio,Frame.Direction);
  except
    on E: Exception do FError := E.Message;
  end;
end;

procedure TTrainAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
var
  T, Travel, CenterX, CenterY, ViewWidth, Scale, StationX,
    CrashX, CrashWidth, CrashBlend, Shake, Age, BossX, BossY, BossRoll, BossBlend, BossEntrance, U, Direction, Offset,
    BossArmorAge, BossStagger, BossGuard, BossDefeat, BossImpact: Double;
  I, FirstCar, LastCar, FirstCue, LastVisibleCue, ExchangeIndex, Formation, Area: Integer;
  C, Board, LastCue, BossEntry, BossFirst, BossFinal: TTrainCue;
  Exchange: TTrainExchange;
  P, N, Ahead: TTrainPose;
  FarEdge, NearEdge: Double;
  Color: TColor;
  Art: Boolean;

  function FormationColor(Index: Integer): TColor;
  begin
    case Index mod 4 of
      1: Result := NextColor;
      2: Result := RGB(150,87,53);
      3: Result := RGB(98,77,147);
    else Result := MainColor;
    end;
  end;

  function CollisionDamage(Car, Owner: Integer): Boolean;
  var E: TTrainExchange;
  begin
    if Owner<=0 then Exit(False);
    E := FPlan.Exchange[Owner-1];
    Result := (Car=E.LeadCar+1) and (E.RightIndex>=0) and (T>=FPlan.Cue[E.RightIndex].Time);
  end;

  procedure HeroCloseup(Weight: Double);
  var Top, Bottom, CloseWidth: Double;
  begin
    Top := Min(-1.60,P.Y-1.47);
    Bottom := RailY+0.39;
    CloseWidth := Max(10.4,(Bottom-Top)/0.56);
    ViewWidth := ViewWidth+(CloseWidth-ViewWidth)*Weight;
    CenterX := CenterX+(P.X+1.12-CenterX)*Weight;
    CenterY := CenterY+(Bottom-CloseWidth*0.28-CenterY)*Weight;
  end;

  procedure FocusSignatureCue;
  var
    L,R,M,K: Integer;
    Cue: TTrainCue;
    Lead,Tail,Peak,Zoom,Lift,Age,Envelope,Subject,Weight,Total,StrengthSum,
      PanSum,ZoomSum,LiftSum: Double;
  begin
    // 影響時間に入ったイベントだけを二分探索で拾う。重なっても切り替えない。
    L := 0;
    R := FPlan.Count;
    while L<R do begin
      M := (L+R) div 2;
      if FPlan.Cue[M].Time<T-0.35 then L := M+1 else R := M;
    end;
    StrengthSum := 0;
    Total := 0;
    PanSum := 0;
    ZoomSum := 0;
    LiftSum := 0;
    for K := L to FPlan.Count-1 do begin
      if FPlan.Cue[K].Time>T+0.33 then Break;
      Cue := FPlan.Cue[K];
      case Cue.Kind of
        tmShot: begin Lead := 0.24; Tail := 0.24; Peak := 0.76; Zoom := 0.10; Lift := 0.12; end;
        tmVaultHit: begin Lead := 0.19; Tail := 0.24; Peak := 0.76; Zoom := 0.12; Lift := 0.16; end;
        tmHurdleHit: begin Lead := 0.19; Tail := 0.24; Peak := 0.76; Zoom := 0.12; Lift := 0.16; end;
        tmBossFinish: begin Lead := 0.33; Tail := 0.35; Peak := 1.00; Zoom := 0.17; Lift := 0.23; end;
      else Continue;
      end;
      Age := T-Cue.Time;
      if (Age<=-Lead) or (Age>=Tail) then Continue;
      if Age<0 then Envelope := TrainEase(1+Age/Lead)
      else Envelope := 1-TrainEase(Age/Tail);
      Envelope := Envelope*Peak;
      Subject := Cue.ToX+0.60;
      if Cue.Kind=tmShot then Subject := Cue.ToX+1.02;
      Weight := Sqr(Envelope);
      Total := Total+Weight;
      PanSum := PanSum+Weight*EnsureRange(Subject-CenterX,-1.25,1.25);
      ZoomSum := ZoomSum+Weight*Zoom;
      LiftSum := LiftSum+Weight*Lift;
      StrengthSum := StrengthSum+Weight*Envelope;
    end;
    if Total<=0 then Exit;
    // 最大エンベロープより強くせず、重なった対象へ比率で滑らかに移行する。
    Weight := (StrengthSum/Total)*(1-CrashBlend)/Total;
    CenterX := CenterX+PanSum*Weight*0.67;
    CenterY := CenterY-LiftSum*Weight;
    ViewWidth := ViewWidth*(1-ZoomSum*Weight);
  end;

  function Screen(AX,AY: Double): TPointF;
  begin
    Result := PointF(Frame.Width*0.5+(AX-CenterX)*Scale,
      Frame.Height*0.5+(AY-CenterY+Shake)*Scale);
  end;

  function ArtWorld(Index,W,H: Integer; X1,Y1,X2,Y2: Double; Opacity: Double=1): Boolean;
  var A,B: TPointF;
  begin
    if not Art then Exit(False);
    A := Screen(X1,Y1);
    B := Screen(X2,Y2);
    Result := Surface.DrawAssetRegion(Index,Rect(0,0,W,H),
      Rect(Round(A.X),Round(A.Y),Round(B.X),Round(B.Y)),False,Opacity);
  end;

  procedure ArtRouteAt(out Route: Integer; out Blend: Double);
  var Segment,Fade: Double;
  begin
    Route := 0;
    Blend := 1;
    if FPlan=nil then Exit;
    Segment := FPlan.Arrival/TrainArtRoutes;
    if Segment<=0.001 then Exit;
    Route := Floor(EnsureRange(T/Segment,0.0,TrainArtRoutes-1.0));
    if Route=0 then Exit;
    Fade := Min(1.15,Segment*0.24);
    Blend := TrainEase((T-Route*Segment)/Fade);
  end;

  function ArtCarLight: Double;
  var Route: Integer; Blend: Double; NewLit,OldLit: Boolean;
  begin
    ArtRouteAt(Route,Blend);
    NewLit := Route>=2;
    OldLit := Route>2;
    Result := Ord(OldLit)*(1-Blend)+Ord(NewLit)*Blend;
  end;

  procedure ArtBackdrop(Front: Boolean);
  const
    Parallax: array[0..4] of Double = (0,0.14,0.38,0.69,1.0);
    WorldTile = 64.0;
  var
    L,First,Last,Route,W,H: Integer;
    Blend: Double;

    procedure PaintLayer(RouteIndex,Layer: Integer; Opacity: Double);
    var Index,Left: Integer;
    begin
      if Opacity<=0 then Exit;
      Index := TrainArtBackground(RouteIndex,Layer);
      if Layer=0 then begin
        Surface.DrawAssetRegion(Index,Rect(0,0,TrainArtBgWidth,TrainArtBgHeight),
          Rect(0,0,Frame.Width,Frame.Height),False,Opacity);
        Exit;
      end;
      // Tile phase is absolute travel in fixed screen-space; pans, zoom and shake
      // only affect the train and tracks. Positive travel rolls scenery to the left.
      Left := -(Round(Travel/WorldTile*W*Parallax[Layer]) mod W);
      while Left<Frame.Width do begin
        Surface.DrawAssetRegion(Index,Rect(0,0,TrainArtBgWidth,TrainArtBgHeight),
          Rect(Left,0,Left+W,H),False,Opacity);
        Inc(Left,W);
      end;
    end;

  begin
    if not Art or (Frame.Width<=0) or (Frame.Height<=0) then Exit;
    H := Frame.Height;
    W := Max(1,Round(H*TrainArtBgWidth/TrainArtBgHeight));
    // Four route segments over the trip, unrelated to collision or exchange indices.
    ArtRouteAt(Route,Blend);

    if Front then begin
      if Blend<1 then PaintLayer(Route-1,4,1-Blend);
      PaintLayer(Route,4,Blend);
    end else begin
      First := 0; Last := 3;
      if Blend<1 then
        for L := First to Last do PaintLayer(Route-1,L,1);
      for L := First to Last do PaintLayer(Route,L,Blend);
    end;
  end;

  procedure Box(X1,Y1,X2,Y2: Double; Tint: TColor);
  var A,B: TPointF;
  begin
    A := Screen(X1,Y1);
    B := Screen(X2,Y2);
    Surface.FillRect(A.X,A.Y,B.X,B.Y,Tint);
  end;

  procedure Line(X1,Y1,X2,Y2,Stroke: Double; Tint: TColor);
  var A,B: TPointF;
  begin
    A := Screen(X1,Y1);
    B := Screen(X2,Y2);
    Surface.Line(A.X,A.Y,B.X,B.Y,Tint,Max(1.0,Stroke*Scale));
  end;

  procedure Circle(X,Y,R: Double; Tint: TColor);
  var A: TPointF;
  begin
    A := Screen(X,Y);
    Surface.Circle(A.X,A.Y,Max(0.7,R*Scale),Tint,True);
  end;

  procedure Quad(X1,Y1,X2,Y2,X3,Y3,X4,Y4: Double; Tint: TColor);
  begin
    Surface.FillQuad(Screen(X1,Y1),Screen(X2,Y2),Screen(X3,Y3),Screen(X4,Y4),Tint);
  end;

  procedure TaperedFX(const A,B: TPointF; Width,Opacity: Double; Tint: TColor);
  var M,N: TPointF; DX,DY,Len,W: Double;
  begin
    if Opacity<0.025 then Exit;
    DX := B.X-A.X; DY := B.Y-A.Y;
    Len := Hypot(DX,DY);
    if Len<0.65 then Exit;
    W := Min(Width,Max(1.25,Min(Frame.Width,Frame.Height)*0.0032))*0.5;
    N := PointF(-DY*W/Len,DX*W/Len);
    M := PointF(A.X+DX*0.71,A.Y+DY*0.71);
    Surface.FillQuad(A,PointF(M.X+N.X,M.Y+N.Y),PointF(M.X-N.X,M.Y-N.Y),
      PointF(A.X+DX*0.025,A.Y+DY*0.025),Tint,0.44*Opacity);
    Surface.FillQuad(PointF(M.X+N.X,M.Y+N.Y),B,
      PointF(B.X-DX*0.025,B.Y-DY*0.025),PointF(M.X-N.X,M.Y-N.Y),Tint,Opacity);
  end;

  procedure CastGlow(X,Y,R,Power: Double; Tint: TColor);
  var A: TPointF;
  begin
    A := Screen(X,Y);
    R := R*Scale;
    Surface.Circle(A.X,A.Y,2.05*R,Tint,True,1,0.11*Power);
    Surface.Circle(A.X,A.Y,1.38*R,Tint,True,1,0.23*Power);
    Surface.Circle(A.X,A.Y,0.57*R,MixColor(Tint,clWhite,0.68),True,1,0.82*Power);
  end;

  procedure Bogie(WX: Double; Tint: TColor);
  var
    K, Spoke: Integer;
    A, PX: Double;
  begin
    Box(WX-0.25,RailY-1.01,WX+1.13,RailY-0.42,Ink);
    for K := 0 to 1 do begin
      PX := WX+K*0.87;
      Circle(PX,RailY-0.39,0.41,Ink);
      Circle(PX,RailY-0.39,0.33,RGB(100,118,129));
      Circle(PX,RailY-0.39,0.27,RGB(49,64,74));
      if Scale>=32 then
        for Spoke := 0 to 2 do begin
          A := Travel/0.40+Spoke*Pi/3;
          Line(PX-0.26*Cos(A),RailY-0.39-0.26*Sin(A),
            PX+0.26*Cos(A),RailY-0.39+0.26*Sin(A),0.045,RGB(143,158,163));
        end;
      Circle(PX,RailY-0.39,0.10,RGB(168,186,190));
      Circle(PX,RailY-0.39,0.04,Ink);
    end;
    Box(WX-0.16,RailY-0.73,WX+1.03,RailY-0.61,MixColor(Tint,Ink,0.50));
    for K := 0 to 2 do
      Box(WX+0.25,RailY-0.81+K*0.057,WX+0.62,RailY-0.78+K*0.057,RGB(152,173,174));
  end;

  procedure Car(CarX,Roof: Double; Tint: TColor; Cab, Bent: Boolean; CarIndex: Integer=-1);
  var
    K, N, First, Last, Livery: Integer;
    WindowX, RightX, Cursor, CarOffset, Width, Detail, SX: Double;
    Paint, Trim, Shadow, WindowColor, RoofDark, RoofLight, Lamp: TColor;
    Move: TTrainCue;
    Gap: TTrainObstacle;
    HasGaps: Boolean;

    procedure Deck(Left, Right: Double);
    var
      Mark: Double;
      MarkIndex: Integer;
    begin
      if Right<=Left then Exit;
      Box(Left,Roof-0.035,Right,Roof+0.20,RGB(90,111,124));
      Box(Left,Roof-0.035,Right,Roof+0.055,RGB(204,226,226));
      Box(Left+0.10,Roof+0.16,Left+0.29,RailY-0.72,RGB(87,107,116));
      Box(Right-0.29,Roof+0.16,Right-0.10,RailY-0.72,RGB(87,107,116));
      for MarkIndex := 0 to 4 do begin
        Mark := Left+(Right-Left)*(MarkIndex+0.5)/5;
        Box(Mark-0.055,Roof+0.08,Mark+0.055,Roof+0.145,Ink);
      end;
    end;

    procedure Glass(Left, Top, W, H: Double; Split: Boolean);
    begin
      Box(Left-0.055,Top-0.055,Left+W+0.055,Top+H+0.055,Shadow);
      Box(Left,Top,Left+W,Top+H,WindowColor);
      Box(Left+0.04,Top+0.042,Left+W-0.04,Top+0.102,MixColor(WindowColor,clWhite,0.43));
      if Scale>=34 then
        Quad(Left+W*0.29,Top+0.09,Left+W*0.55,Top+0.09,
          Left+W*0.29,Top+H-0.07,Left+W*0.11,Top+H-0.07,MixColor(WindowColor,clWhite,0.17));
      if Split then Box(Left+W*0.52-0.025,Top,Left+W*0.52+0.025,Top+H,Shadow);
      Box(Left-0.055,Top+H,Left+W+0.055,Top+H+0.054,MixColor(Paint,clWhite,0.49));
    end;

    procedure DamageMarks;
    begin
      if not Bent then Exit;
      Line(CarX+0.12,Roof+0.14,CarX+0.44,Roof+0.45,0.06,Ink);
      Line(CarX+0.44,Roof+0.45,CarX+0.63,Roof+0.37,0.06,Ink);
      Line(CarX+0.10,Roof+1.69,CarX+0.86,Roof+2.04,0.09,Shadow);
      Line(CarX+0.24,Roof+1.61,CarX+0.90,Roof+1.85,0.05,RoofLight);
    end;

    procedure Door(Left, Top, W, Bottom: Double);
    begin
      Box(Left,Top,Left+W,Bottom,Shadow);
      Box(Left+0.038,Top+0.042,Left+W-0.038,Bottom-0.042,MixColor(Paint,Ink,0.15));
      Glass(Left+W*0.20,Top+0.14,W*0.60,0.57,False);
      Box(Left+W*0.78,Top+0.92,Left+W*0.89,Top+0.964,Trim);
      Box(Left-0.05,Bottom,Left+W+0.05,Bottom+0.072,RoofLight);
    end;

  begin
    RightX := CarX+TrainCarWidth;
    if (RightX+0.3<FarEdge) or (CarX-0.3>NearEdge) then Exit;
    HasGaps := False;
    if CarIndex>=0 then begin
      FPlan.CarCues(CarIndex,CarIndex,First,Last);
      for K := First to Last do
        if FPlan.Cue[K].Kind=tmRoofGap then begin
          HasGaps := True;
          Break;
        end;
    end;
    Livery := 0;
    if CarIndex>=0 then Livery := (CarIndex div 2+FPlan.FormationOf(CarIndex)) mod 4
    else if Cab then Livery := 1;
    Paint := Tint;
    Trim := RGB(235,222,184);
    case Livery of
      1: begin Paint := MixColor(Tint,RGB(193,219,222),0.46); Trim := RGB(83,223,222); end;
      2: begin Paint := MixColor(Tint,RGB(123,95,77),0.55); Trim := RGB(223,179,76); end;
      3: begin Paint := MixColor(Tint,RGB(77,53,81),0.43); Trim := RGB(239,193,177); end;
    end;
    Shadow := MixColor(Paint,Ink,0.66);
    RoofDark := MixColor(Paint,RGB(43,56,67),0.58);
    RoofLight := MixColor(RoofDark,RGB(218,234,237),0.62);
    // Keep couplers and the playable roof at the original world coordinates.
    Box(CarX-0.5*TrainGap,RailY-0.71,CarX+0.15,RailY-0.57,Ink);
    Box(RightX-0.15,RailY-0.71,RightX+0.5*TrainGap,RailY-0.57,Ink);
    Box(CarX-0.48*TrainGap,RailY-0.72,CarX-0.37*TrainGap,RailY-0.55,RoofLight);
    Box(RightX+0.37*TrainGap,RailY-0.72,RightX+0.48*TrainGap,RailY-0.55,RoofLight);
    if Art and not HasGaps then begin
      if Cab then N := 2 else N := Livery mod TrainArtCars;
      Detail := (RailY-Roof)/(TrainArtCarRailY-TrainArtCarRoofY);
      SX := Roof-Detail*TrainArtCarRoofY;
      if ArtWorld(TrainArtVehicle(N,False),TrainArtCarWidth,TrainArtCarHeight,
        CarX,SX,RightX,SX+Detail*TrainArtCarHeight) then begin
        // Collision adds scars; the same vehicle sprite persists through the transfer.
        if ArtCarLight>0 then
          ArtWorld(TrainArtVehicle(N,True),TrainArtCarWidth,TrainArtCarHeight,
            CarX,SX,RightX,SX+Detail*TrainArtCarHeight,0.72*ArtCarLight);
        DamageMarks;
        Exit;
      end;
    end;
    Box(CarX+0.67,RailY-1.0,RightX-0.67,RailY-0.54,Ink);
    Bogie(CarX+1.16,Paint);
    Bogie(RightX-2.03,Paint);
    for K := 0 to 3 do
      Box(CarX+3.35+K*1.36,RailY-0.78,CarX+4.18+K*1.36,RailY-0.53,RoofDark);
    if CarIndex>=0 then begin
      if HasGaps then begin
        Box(CarX,RailY-0.85,RightX,RailY-0.43,Paint);
        Box(CarX,RailY-0.84,RightX,RailY-0.74,Trim);
        Cursor := CarX;
        CarOffset := CarX-CarIndex*TrainPitch;
        for K := First to Last do begin
          Move := FPlan.Cue[K];
          if (Move.Kind<>tmRoofGap) or not TrainRouteHazard(Move,Gap) then Continue;
          Deck(Cursor,Gap.Left+CarOffset);
          Cursor := Gap.Right+CarOffset;
        end;
        Deck(Cursor,RightX);
        Exit;
      end;
    end;
    // Draw all cosmetic relief below the walkable roof; route hazards stay distinct.
    Quad(CarX,Roof,RightX-0.18,Roof,RightX,RailY-0.52,CarX,RailY-0.52,Paint);
    Box(CarX,Roof-0.040,RightX,Roof+0.12,RoofLight);
    Box(CarX+0.04,Roof+0.11,RightX-0.04,Roof+0.25,RoofDark);
    for K := 0 to 7 do begin
      WindowX := CarX+0.57+1.44*K;
      Box(WindowX,Roof+0.006,WindowX+0.047,Roof+0.115,RoofDark);
      if Scale>=38 then Circle(WindowX+0.10,Roof+0.176,0.019,RoofLight);
    end;
    Box(CarX+0.08,Roof+1.84,RightX-0.08,Roof+1.97,Trim);
    Box(CarX+0.08,Roof+2.02,RightX-0.08,Roof+2.062,MixColor(Trim,Ink,0.36));
    Box(CarX+0.12,RailY-0.77,RightX-0.12,RailY-0.56,RoofDark);
    Box(CarX+0.14,RailY-0.781,RightX-0.12,RailY-0.725,MixColor(Paint,clWhite,0.45));
    WindowColor := RGB(37,58,77);
    WindowColor := MixColor(WindowColor,RGB(102,104,77),ArtCarLight);
    if Cab then begin
      WindowColor := RGB(88,148,165);
      for K := 0 to 2 do Glass(CarX+0.73+K*1.81,Roof+0.66,1.30,0.79,True);
      Door(CarX+6.32,Roof+0.47,1.08,Roof+2.27);
      Glass(RightX-2.98,Roof+0.56,1.79,0.88,True);
      Quad(RightX-1.08,Roof+0.33,RightX-0.18,Roof+0.27,RightX-0.03,Roof+1.62,
        RightX-0.92,Roof+1.69,MixColor(Trim,Paint,0.23));
      Lamp := RGB(255,241,165);
      Box(RightX-0.43,Roof+1.67,RightX-0.095,Roof+1.91,Shadow);
      Box(RightX-0.37,Roof+1.71,RightX-0.087,Roof+1.85,Lamp);
      Box(RightX-0.43,Roof+2.05,RightX-0.09,Roof+2.12,RGB(211,62,55));
    end
    else if Livery=2 then begin
      for K := 0 to 3 do begin
        SX := CarX+0.83+K*2.68;
        Box(SX,Roof+0.39,SX+2.12,Roof+1.73,Shadow);
        Box(SX+0.08,Roof+0.46,SX+2.04,Roof+1.65,RoofDark);
        Line(SX+0.12,Roof+1.59,SX+2.00,Roof+0.49,0.045,RoofLight);
        if Scale>=30 then
          for N := 0 to 6 do
            Box(SX+0.20+N*0.27,Roof+0.57,SX+0.24+N*0.27,Roof+1.59,MixColor(RoofDark,Ink,0.32));
      end;
    end
    else begin
      Door(CarX+0.31,Roof+0.49,0.92,Roof+2.34);
      Door(RightX-1.31,Roof+0.49,0.92,Roof+2.34);
      Width := (RightX-CarX-3.14)/5;
      for K := 0 to 4 do begin
        SX := CarX+1.55+K*Width;
        Glass(SX,Roof+0.65,Width-0.18,0.85,Livery<>3);
        if (ArtCarLight>0) and (K mod 3<>1) then
          Box(SX+0.09,Roof+1.08,SX+Width-0.25,Roof+1.42,
            MixColor(WindowColor,RGB(167,135,83),ArtCarLight));
      end;
    end;
    if Scale>=28 then begin
      Detail := Max(Roof+2.11,RailY-1.17);
      Box(CarX+2.27,Detail,CarX+3.02,Detail+0.19,Shadow);
      for K := 0 to 4 do
        Box(CarX+2.35+K*0.12,Detail+0.045,CarX+2.39+K*0.12,Detail+0.145,RoofLight);
      Line(CarX+0.23,Roof+0.26,CarX+0.23,RailY-0.78,0.042,Shadow);
      Line(RightX-0.23,Roof+0.26,RightX-0.23,RailY-0.78,0.042,Shadow);
    end;
    DamageMarks;
  end;

  procedure Platform(StartX,Width,Top: Double; Canopy: Boolean);
  var
    K: Integer;
    Mark: Double;
  begin
    if (StartX+Width<FarEdge) or (StartX>NearEdge) then Exit;
    Box(StartX,Top,StartX+Width,RailY+0.36,RGB(80,99,116));
    Box(StartX,Top,StartX+Width,Top+0.075,RGB(231,206,129));
    Box(StartX+0.05,Top+0.26,StartX+Width-0.05,Top+0.36,RGB(113,138,152));
    for K := 1 to Trunc(Width/1.04) do begin
      Mark := StartX+K*1.04;
      Box(Mark,Top+0.13,Mark+0.037,RailY+0.34,RGB(60,78,98));
      Box(Mark,Top+0.02,Mark+0.12,Top+0.056,RGB(241,228,173));
    end;
    if Canopy then begin
      Quad(StartX+1.68,-0.91,StartX+2.38,-1.37,StartX+Width-1.50,-1.37,StartX+Width-1.06,-0.91,
        RGB(44,67,90));
      Box(StartX+1.68,-0.93,StartX+Width-1.06,-0.82,RGB(101,137,155));
      for K := 0 to 2 do begin
        Mark := StartX+2.69+Width*0.27*K;
        Box(Mark,-0.82,Mark+0.16,Top,RGB(55,79,99));
        Box(Mark+0.12,-0.78,Mark+0.16,Top-0.03,RGB(120,151,157));
        Box(Mark-0.14,-0.83,Mark+0.70,-0.76,RGB(248,229,173));
      end;
      Box(StartX+4.0,-0.82,StartX+6.75,-0.35,RGB(48,94,117));
      Box(StartX+4.10,-0.74,StartX+6.65,-0.41,RGB(82,141,155));
      Line(StartX+4.27,-0.58,StartX+4.80,-0.58,0.055,RGB(232,240,231));
      Line(StartX+5.02,-0.58,StartX+6.45,-0.58,0.055,RGB(232,240,231));
    end;
  end;

  procedure DrawTrack;
  var
    Left, Right, Tie: Double;
    K: Integer;
  begin
    Left := FarEdge-1.8;
    Right := NearEdge+1.8;
    Box(Left,RailY-0.025,Right,RailY+0.51,RGB(129,129,117));
    Box(Left,RailY+0.43,Right,RailY+0.51,RGB(90,100,99));
    for K := Floor((Left+Travel)/0.89) to Ceil((Right+Travel)/0.89) do begin
      Tie := K*0.89-Travel;
      Quad(Tie,RailY+0.02,Tie+0.33,RailY+0.02,Tie+0.45,RailY+0.48,
        Tie-0.08,RailY+0.48,RGB(85,71,62));
      if Scale>=24 then begin
        Line(Tie+0.03,RailY+0.058,Tie+0.03,RailY+0.42,0.022,RGB(133,109,82));
        Circle(Tie+0.16,RailY+0.09,0.026,RGB(172,169,152));
        Circle(Tie+0.17,RailY+0.38,0.026,RGB(172,169,152));
      end;
    end;
    Box(Left,RailY-0.022,Right,RailY+0.052,RGB(71,79,82));
    Box(Left,RailY-0.024,Right,RailY+0.004,RGB(237,245,247));
    Box(Left,RailY+0.244,Right,RailY+0.334,RGB(61,66,69));
    Box(Left,RailY+0.24,Right,RailY+0.27,RGB(227,239,239));
  end;

  procedure Backdrop;
  var
    Layer, K, N, M: Integer;
    WX, WY, Shift, Span, Rise, SX, SY: Double;
    Sky, Haze, FarTint, MidTint, Ground, Light, Local: TColor;
  begin
    case Area of
      1: begin
        Sky := RGB(56,135,186); Haze := RGB(196,228,229);
        FarTint := RGB(110,160,169); MidTint := RGB(73,136,150);
        Ground := RGB(51,104,139); Light := RGB(235,246,222);
      end;
      2: begin
        Sky := RGB(110,139,165); Haze := RGB(218,214,188);
        FarTint := RGB(140,158,175); MidTint := RGB(97,119,140);
        Ground := RGB(112,116,117); Light := RGB(250,223,172);
      end;
      3: begin
        Sky := RGB(35,44,80); Haze := RGB(121,92,131);
        FarTint := RGB(89,86,131); MidTint := RGB(62,68,105);
        Ground := RGB(53,66,82); Light := RGB(251,217,158);
      end;
      4: begin
        Sky := RGB(125,97,118); Haze := RGB(247,193,147);
        FarTint := RGB(154,120,132); MidTint := RGB(120,87,102);
        Ground := RGB(135,116,106); Light := RGB(255,232,171);
      end;
    else
      Sky := RGB(81,166,211); Haze := RGB(230,245,236);
      FarTint := RGB(125,173,162); MidTint := RGB(81,142,125);
      Ground := RGB(100,151,101); Light := RGB(255,248,197);
    end;
    for Layer := 0 to 23 do
      Surface.FillRect(0,Layer*Frame.Height/24,Frame.Width,(Layer+1)*Frame.Height/24+1,
        MixColor(Sky,Haze,Layer/23));
    Span := Min(Frame.Width,Frame.Height);
    SX := Frame.Width*0.77;
    SY := Frame.Height*0.23;
    if Area=3 then begin
      Surface.Circle(SX,SY,Span*0.047,Light,True);
      Surface.Circle(SX+Span*0.020,SY-Span*0.009,Span*0.043,MixColor(Sky,Haze,0.24),True);
      for K := 0 to 23 do begin
        SX := ((K*131+23) mod 347)*Frame.Width/347;
        SY := ((K*73+19) mod 199)*Frame.Height/435;
        Surface.Circle(SX,SY,Max(0.8,Span*(0.0012+0.00053*(K mod 3))),
          MixColor(Haze,RGB(226,235,237),0.47+0.12*(K mod 3)),True);
      end;
    end else begin
      Surface.Circle(SX,SY,Span*0.088,MixColor(Light,Haze,0.48),True);
      Surface.Circle(SX,SY,Span*0.057,Light,True);
      Shift := Travel*0.065;
      for K := Floor((FarEdge+Shift)/9.3)-1 to Floor((NearEdge+Shift)/9.3)+1 do begin
        WX := K*9.3-Shift;
        WY := -4.1+1.32*Sqr(Sin(K*1.733));
        Local := MixColor(Haze,clWhite,0.43);
        Circle(WX,WY,0.39,Local);
        Circle(WX+0.52,WY-0.10,0.52,Local);
        Circle(WX+1.09,WY+0.03,0.36,Local);
      end;
    end;
    for Layer := 0 to 2 do begin
      WY := -1.7+Layer*0.75;
      Shift := Travel*(0.11+Layer*0.09);
      Span := 9.1-Layer*1.73;
      Local := MixColor(FarTint,MidTint,Layer*0.5);
      for K := Floor((FarEdge+Shift)/Span)-1 to Ceil((NearEdge+Shift)/Span) do begin
        WX := K*Span-Shift;
        Rise := 1.14+0.61*Sqr(Sin(K*1.97+Layer*0.82));
        Quad(WX-1.5,WY+2.7,WX+Span*0.29,WY-Rise,WX+Span*0.73,WY-0.47,WX+Span+1.4,WY+2.7,Local);
        if Layer=0 then
          Quad(WX+Span*0.29,WY-Rise,WX+Span*0.73,WY-0.47,WX+Span+1.4,WY+2.7,WX+Span*0.37,WY+2.7,
            MixColor(Local,Haze,0.22));
      end;
    end;
    Box(FarEdge,RailY+0.03,NearEdge,RailY+Frame.Height/Scale,Ground);
    case Area of
      0, 4: begin
        Shift := Travel*0.47;
        for K := Floor((FarEdge+Shift)/2.42)-1 to Ceil((NearEdge+Shift)/2.42) do begin
          WX := K*2.42-Shift;
          WY := 1.78-Sqr(Sin(K*2.19))*0.91;
          Local := MixColor(MidTint,Ground,0.35);
          Box(WX-0.041,WY+0.33,WX+0.051,RailY, MixColor(Local,Ink,0.22));
          Quad(WX-0.72,WY+1.23,WX,WY-0.26,WX+0.66,WY+1.23,WX,WY+1.32,Local);
          Quad(WX-0.53,WY+0.66,WX,WY-0.47,WX+0.47,WY+0.66,WX,WY+0.73,MixColor(Local,Haze,0.21));
        end;
      end;
      1: begin
        Box(FarEdge,RailY+0.36,NearEdge,RailY+0.67,RGB(84,116,131));
        Shift := Travel*0.48;
        for K := Floor((FarEdge+Shift)/3.25)-1 to Ceil((NearEdge+Shift)/3.25) do begin
          WX := K*3.25-Shift;
          WY := RailY+0.86+0.49*Sqr(Sin(K*1.83));
          Line(WX,WY,WX+1.04,WY,0.050,MixColor(Ground,Haze,0.37));
          Line(WX+0.31,WY+0.33,WX+1.59,WY+0.33,0.022,MixColor(Ground,Haze,0.55));
        end;
        Shift := Travel*0.72;
        for K := Floor((FarEdge+Shift)/5.2)-1 to Ceil((NearEdge+Shift)/5.2) do begin
          WX := K*5.2-Shift;
          Line(WX,RailY+0.42,WX+2.6,RailY+2.11,0.12,RGB(86,117,129));
          Line(WX+2.6,RailY+2.11,WX+5.2,RailY+0.42,0.12,RGB(86,117,129));
          Line(WX,RailY+0.42,WX,RailY+2.25,0.19,RGB(99,126,133));
        end;
      end;
      2, 3: begin
        Shift := Travel*0.45;
        for K := Floor((FarEdge+Shift)/3.12)-1 to Ceil((NearEdge+Shift)/3.12) do begin
          WX := K*3.12-Shift;
          WY := 0.51-2.48*Sqr(Sin(K*2.17));
          Span := 1.65+0.64*Sqr(Cos(K*2.81));
          Local := MixColor(MidTint,FarTint,0.27*Sqr(Sin(K)));
          Box(WX,WY,WX+Span,RailY,Local);
          Box(WX+0.13,WY-0.13,WX+Span-0.07,WY, MixColor(Local,Haze,0.27));
          if K mod 3=0 then begin
            Line(WX+Span*0.62,WY,WX+Span*0.62,WY-0.49,0.045,Local);
            Circle(WX+Span*0.62,WY-0.50,0.036,Light);
          end;
          if Scale>=22 then
            for N := 0 to 3 do
              for M := 0 to 2 do begin
                SX := WX+Span*(0.13+M*0.26);
                SY := WY+0.31+N*0.55;
                if ((Abs(K+N*3+M*5) mod 5)<>1) and (SY+0.17<RailY) then
                  Box(SX,SY,SX+0.22,SY+0.15,MixColor(Local,Light,0.29+0.20*Ord(Area=3)));
              end;
        end;
      end;
    end;
  end;

  procedure RoofEquipment(const Move: TTrainCue);
  var Block: TTrainObstacle; Offset,Roof,Top,Mid: Double; K,CarIndex: Integer;
  begin
    if not TrainObstacle(Move,Block) then Exit;
    CarIndex := Floor(Move.FromX/TrainPitch);
    if not FPlan.CarPosition(CarIndex,ExchangeIndex,T,Offset) then Exit;
    Block.Left := Block.Left+Offset;
    Block.Right := Block.Right+Offset;
    if (Block.Right<FarEdge) or (Block.Left>NearEdge) then Exit;
    Roof := FPlan.RoofY(Move.FromX);
    Top := Roof-Block.Height;
    Mid := (Block.Left+Block.Right)*0.5;
    Box(Block.Left,Top,Block.Right,Roof,RGB(60,68,76));
    Box(Block.Left-0.06,Top-0.01,Block.Right+0.06,Top+0.13,RGB(255,185,64));
    case Block.Variant of
      0: for K := 1 to 3 do
           Box(Block.Left+0.12,Top+0.14+K*0.15,Block.Right-0.12,Top+0.21+K*0.15,RGB(174,195,202));
      1: begin
           Box(Block.Left+0.12,Top+0.24,Block.Right-0.12,Roof-0.12,RGB(128,151,162));
           Line(Block.Left+0.19,Roof-0.18,Block.Right-0.19,Top+0.28,0.07,RGB(250,207,108));
         end;
      2: begin
           Circle(Mid-0.20,Top+0.50,0.16,RGB(195,219,221));
           Circle(Mid+0.20,Top+0.50,0.16,RGB(195,219,221));
         end;
    end;
  end;


  function ScarfFlow(const Pose: TTrainPose): Double;
  begin
    Result := 0;
    if FPlan<>nil then Result := FPlan.ScarfMotionAt(T,Pose.X);
  end;

  procedure DrawMotionFX(const Pose: TTrainPose);
  var K: Integer; Flow,Phase,Fade,WX,WY,Len: Double; A,B: TPointF;
  begin
    if Pose.Airborne then Exit;
    Flow := TrainEase((ScarfFlow(Pose)-0.35)/0.65)*Max(Pose.Run,Pose.Slide);
    if Flow<0.07 then Exit;
    for K := 0 to 3 do begin
      Phase := T*(3.2+0.49*K)+K*0.381966;
      Phase := Phase-Floor(Phase);
      Fade := Sqr(Sin(Pi*Phase))*Flow*(0.37-0.038*K);
      WX := Pose.X-0.29-Phase*(0.53+0.12*K);
      WY := Pose.Y-0.16-0.097*K+0.049*Phase;
      Len := (0.12+0.30*Phase)*Flow*(1+0.12*K);
      A := Screen(WX-Len,WY+0.017); B := Screen(WX,WY);
      TaperedFX(A,B,(0.009+0.002*K)*Scale,Fade,RGB(236,242,243));
    end;
  end;

  procedure DrawScarf(const Root: TPointF; Px,PxY,Flow: Double; Facing: Integer);
  const Segments = 12;
  var Prev,Cur,PrevN,CurN: TPointF; K: Integer;
      HalfNow,HalfPrev: Double;

    function Normal(U: Double): TPointF;
    var A,B: TPointF; DX,DY,L: Double;
    begin
      A := TrainScarfPoint(Max(0.0,U-0.025),T,Flow);
      B := TrainScarfPoint(Min(1.0,U+0.025),T,Flow);
      DX := B.X-A.X; DY := B.Y-A.Y;
      L := Max(0.001,Hypot(DX,DY));
      Result := PointF(-DY/L,DX/L);
    end;

    function Map(const Q,N: TPointF; Offset: Double): TPointF;
    begin
      Result := PointF(Root.X+(Q.X+N.X*Offset)*Px*Facing,
        Root.Y+(Q.Y+N.Y*Offset)*PxY);
    end;

  begin
    Prev := TrainScarfPoint(0,T,Flow); PrevN := Normal(0);
    HalfPrev := 2.8;
    for K := 1 to Segments do begin
      Cur := TrainScarfPoint(K/Segments,T,Flow); CurN := Normal(K/Segments);
      HalfNow := 2.8+Sin(Pi*K/Segments)*1.2-1.22*K/Segments;
      Surface.FillQuad(Map(Prev,PrevN,-HalfPrev-0.58),Map(Cur,CurN,-HalfNow-0.58),
        Map(Cur,CurN,HalfNow+0.58),Map(Prev,PrevN,HalfPrev+0.58),RGB(68,25,26));
      Surface.FillQuad(Map(Prev,PrevN,-HalfPrev),Map(Cur,CurN,-HalfNow),
        Map(Cur,CurN,HalfNow),Map(Prev,PrevN,HalfPrev),RGB(240,75+K*2,63));
      Surface.FillQuad(Map(Prev,PrevN,HalfPrev-0.95),Map(Cur,CurN,HalfNow-0.95),
        Map(Cur,CurN,HalfNow-0.28),Map(Prev,PrevN,HalfPrev-0.28),RGB(255,199,102));
      Prev := Cur; PrevN := CurN;
      HalfPrev := HalfNow;
    end;
  end;

  function ArtFigure(const Pose: TTrainPose; Size: Double; Facing,Model: Integer;
    WorldOffset,ArtImpact: Double): Boolean;
  var Clip: TTrainArtClip; Phase,Px,PxY,Opacity,Collapse: Double; At,Root: TPointF; J,K,Role,FeetX,L,U,W,H,DL,DT: Integer;
  begin
    if not Art then Exit(False);
    case Model of
      1: Role := 1;
      3: Role := 2;
      2,4: Role := 3;
    else Role := 0;
    end;
    Px := 0.014*Scale*Size;
    PxY := Px*(1-0.29*EnsureRange(Pose.Slide,0.0,1.0));
    Opacity := 1;
    if (Model=4) and (ArtImpact>=0) and (T>=BossFinal.Time) then begin
      Collapse := TrainEase(ArtImpact/0.54);
      PxY := PxY*(1-0.60*Collapse);
      Opacity := 1-TrainEase((ArtImpact-0.38)/0.68);
    end;
    Clip := taIdle;
    Phase := T/0.96;
    if ArtImpact>=0 then begin
      Clip := taImpact;
      if Model=4 then Phase := 0.5+0.5*EnsureRange(ArtImpact,0.0,0.34)
      else Phase := 0.5+0.5*EnsureRange(ArtImpact,0.0,1.0);
    end
    else if TrainArtLowPhase(Pose.Crouch,Pose.Slide,not Pose.Airborne,Phase) then
      Clip := taDuck
    else if (Pose.Gesture<>tgNone) and (Max(Pose.Reach,Max(Pose.Windup,Pose.FollowThrough))>0.025) then begin
      case Pose.Gesture of
        tgKick,tgSweep: Clip := taKick;
        tgAirKick,tgPulse,tgFinisher: Clip := taSpecial;
      else Clip := taPunch;
      end;
      if Model in [0,4] then
        Phase := Pose.ArtGesturePhase
      else
        Phase := EnsureRange(0.5*Pose.Reach+0.4*Pose.Windup,0.0,0.5);
    end else if Pose.Airborne then begin Clip := taSpecial; Phase := Pose.FlightPhase; end
    else if Pose.Land>0.035 then begin Clip := taLand; Phase := 0.5+0.5*(1-Pose.Land); end
    else if Pose.Run>0.16 then begin
      Clip := taWalk;
      // Phase is car-relative world distance; no advance merely from camera motion.
      Phase := Facing*(Pose.X-WorldOffset)*Scale/(TrainArtStride(Role)*Px);
    end else Phase := T/0.96;
    J := TrainArtSample(Clip,Phase);
    K := TrainArtAtlas(Role,Clip);
    L := (J mod 6)*TrainArtCell;
    U := (2*(Ord(Clip) mod 4)+J div 6)*TrainArtCell;
    At := Screen(Pose.X,Pose.Y);
    // Anchor sprite to the authored support-foot distance while a cell is held.
    if Clip=taWalk then At.X := At.X-
      (Phase-Floor(Phase)-J/12)*TrainArtStride(Role)*Px*Facing;
    FeetX := TrainArtFeetX;
    if Facing<0 then FeetX := TrainArtCell-1-FeetX;
    W := Max(1,Round(TrainArtCell*Px));
    H := Max(1,Round(TrainArtCell*PxY));
    DL := Round(At.X-FeetX*Px);
    DT := Round(At.Y-TrainArtFeetY*PxY);
    Result := Surface.DrawAssetRegion(K,Rect(L,U,L+TrainArtCell,U+TrainArtCell),
      Rect(DL,DT,DL+W,DT+H),Facing<0,Opacity);
    if Result and (Role=0) then begin
      Px := W/TrainArtCell;
      PxY := H/TrainArtCell;
      Root := TrainScarfRoot(Clip,J);
      if Facing<0 then Root.X := TrainArtCell-1-Root.X;
      DrawScarf(PointF(DL+Root.X*Px,DT+Root.Y*PxY),Px,PxY,ScarfFlow(Pose),Facing);
    end;
  end;

  procedure Figure(const Pose: TTrainPose; Tint: TColor; Size: Double; Facing: Integer;
    Roll: Double=0; Model: Integer=0; WorldOffset: Double=0; ArtImpact: Double=-1);
  var
    HipX,HipY,ShoulderX,ShoulderY,HeadX,HeadY,Stride,Lean,AngleS,AngleC,
      ArmX,ArmY,BackArmX,BackArmY,StepLength,GaitBlend,Lift,Air,AirWeight,Reach,Wind,Follow,Wide: Double;
    RearFoot, FrontFoot: TPointF;
    Dark, Light, Boot, Skin, Trim: TColor;

    function Rotate(LX,LY: Double): TPointF;
    var OffsetY: Double;
    begin
      OffsetY := LY+0.57;
      Result := PointF(Pose.X+Size*(LX*AngleC-OffsetY*AngleS),
        Pose.Y+Size*(-0.57+LX*AngleS+OffsetY*AngleC));
    end;

    procedure Dot(X,Y,R: Double; C: TColor);
    var A: TPointF;
    begin
      A := Rotate(X,Y);
      Circle(A.X,A.Y,R*Size,C);
    end;

    procedure Bone(X1,Y1,X2,Y2,Stroke: Double; C: TColor);
    var A,B: TPointF;
    begin
      A := Rotate(X1,Y1);
      B := Rotate(X2,Y2);
      Line(A.X,A.Y,B.X,B.Y,Stroke*Size,C);
    end;

    procedure Patch(X1,Y1,X2,Y2,X3,Y3,X4,Y4: Double; C: TColor);
    var A,B,D,E: TPointF;
    begin
      A := Rotate(X1,Y1);
      B := Rotate(X2,Y2);
      D := Rotate(X3,Y3);
      E := Rotate(X4,Y4);
      Quad(A.X,A.Y,B.X,B.Y,D.X,D.Y,E.X,E.Y,C);
    end;

    procedure Joint(X1,Y1,TX,TY,L1,L2,Bend,Stroke: Double; C: TColor; IsLeg, NearSide: Boolean);
    var DX,DY,LengthTo,Along,Side,JX,JY,EX,EY,Toe: Double;
    begin
      DX := TX-X1;
      DY := TY-Y1;
      LengthTo := Hypot(DX,DY);
      if LengthTo<0.001 then begin
        DX := Facing;
        DY := 0;
        LengthTo := 0.001;
      end else begin
        DX := DX/LengthTo;
        DY := DY/LengthTo;
      end;
      LengthTo := EnsureRange(LengthTo,Abs(L1-L2)+0.001,L1+L2-0.001);
      Along := (Sqr(L1)-Sqr(L2)+Sqr(LengthTo))/(2*LengthTo);
      Side := Bend*Sqrt(Max(0.0,Sqr(L1)-Sqr(Along)));
      JX := X1+DX*Along-DY*Side;
      JY := Y1+DY*Along+DX*Side;
      EX := X1+DX*LengthTo;
      EY := Y1+DY*LengthTo;
      Bone(X1,Y1,JX,JY,Stroke+0.067,Ink);
      Bone(JX,JY,EX,EY,Stroke+0.039,Ink);
      Dot(JX,JY,(Stroke+0.039)*0.5,Ink);
      Bone(X1,Y1,JX,JY,Stroke,C);
      Bone(JX,JY,EX,EY,Stroke*0.8,MixColor(C,Light,0.15));
      if IsLeg then begin
        Toe := EX+Facing*0.12;
        Bone(EX-Facing*0.037,EY-0.026,Toe,EY-0.020,0.094,Ink);
        Bone(EX,EY-0.047,Toe,EY-0.044,0.039,Boot);
        if NearSide then Dot(JX,JY,0.052,MixColor(C,Light,0.44));
      end else begin
        Dot(EX,EY,0.075,Ink);
        Dot(EX+Facing*0.011,EY-0.006,0.050,Boot);
        if NearSide then Bone(JX,JY,EX,EY,0.025,Trim);
      end;
    end;

    function FootAt(Shift, DefaultX: Double): TPointF;
    var Phase, Advance, LX, LY: Double;
    const Stance = 0.57;
    begin
      // 接地中は車両内の移動量を逆向きに打ち消し、車両の平行移動は加えない。
      Phase := Facing*(Pose.X-WorldOffset)/(StepLength*Size)+Shift;
      Phase := Phase-Floor(Phase);
      LY := -0.015;
      if Phase<Stance then
        LX := StepLength*(Stance*0.5-Phase)
      else begin
        Advance := (Phase-Stance)/(1-Stance);
        LX := StepLength*Stance*(TrainEase(Advance)-0.5);
        LY := LY-Lift*Sqr(Sin(Pi*Advance));
      end;
      Result := PointF(DefaultX*(1-GaitBlend)+Facing*LX*GaitBlend,
        -0.015+(LY+0.015)*GaitBlend);
    end;

  begin
    if ArtFigure(Pose,Size,Facing,Model,WorldOffset,ArtImpact) then Exit;
    AngleS := Sin(Roll);
    AngleC := Cos(Roll);
    Reach := Pose.Reach;
    Wind := Pose.Windup;
    Follow := Pose.FollowThrough;
    Wide := 1;
    Dark := MixColor(Tint,Ink,0.64);
    Light := MixColor(Tint,clWhite,0.55);
    Boot := RGB(112,170,180);
    Skin := RGB(249,216,177);
    Trim := RGB(253,234,151);
    case Model of
      1: begin Boot := RGB(171,100,143); Skin := RGB(232,185,151); Trim := RGB(255,192,117); end;
      2: begin Boot := RGB(79,141,139); Skin := RGB(216,232,214); Trim := RGB(177,239,163); end;
      3: begin Boot := RGB(136,135,178); Skin := RGB(171,201,212); Trim := RGB(250,131,100); Wide := 1.22; end;
      4: begin Boot := RGB(119,102,172); Skin := RGB(244,213,177); Trim := RGB(255,225,138); Wide := 1.31; end;
    end;
    StepLength := 1.04;
    if Model=2 then StepLength := 0.91;
    if Model>=3 then StepLength := 1.13;
    GaitBlend := TrainEase(Pose.Run*2.9);
    Lift := 0.13+0.17*Pose.Run;
    Stride := Pose.Run*Sin(2*Pi*Facing*(Pose.X-WorldOffset)/(StepLength*Size));
    RearFoot := FootAt(0,-0.18*Facing);
    FrontFoot := FootAt(0.5,0.20*Facing);
    Lean := Facing*(Pose.Run*0.16+Reach*0.22-Wind*0.12);
    HipX := (-0.06-0.04*Wind)*Facing;
    HipY := -0.54+0.24*Pose.Crouch+0.025*Pose.Run*Abs(Stride);
    ShoulderX := HipX+Lean;
    ShoulderY := HipY-0.37+0.12*Pose.Crouch;
    HeadX := ShoulderX+0.055*Facing;
    HeadY := ShoulderY-0.215;
    if Pose.Slide>0 then begin
      HipX := HipX+(-0.19*Facing-HipX)*Pose.Slide;
      HipY := HipY+(-0.24-HipY)*Pose.Slide;
      ShoulderX := ShoulderX+(0.24*Facing-ShoulderX)*Pose.Slide;
      ShoulderY := ShoulderY+(-0.33-ShoulderY)*Pose.Slide;
      HeadX := HeadX+(0.43*Facing-HeadX)*Pose.Slide;
      HeadY := HeadY+(-0.37-HeadY)*Pose.Slide;
      RearFoot := PointF(RearFoot.X+(-0.52*Facing-RearFoot.X)*Pose.Slide,RearFoot.Y*(1-Pose.Slide));
      FrontFoot := PointF(FrontFoot.X+(0.37*Facing-FrontFoot.X)*Pose.Slide,FrontFoot.Y*(1-Pose.Slide));
    end;
    if Pose.Airborne then begin
      Air := Sin(Pi*Pose.FlightPhase);
      AirWeight := TrainEase(Min(Pose.FlightPhase,1-Pose.FlightPhase)/0.125);
      Stride := Stride+(0.45-Stride)*AirWeight;
      RearFoot := PointF(RearFoot.X+(Facing*(-0.30-0.11*Air)-RearFoot.X)*AirWeight,
        RearFoot.Y+(-0.09-0.19*Air-RearFoot.Y)*AirWeight);
      FrontFoot := PointF(FrontFoot.X+(Facing*(0.28-0.11*Air)-FrontFoot.X)*AirWeight,
        FrontFoot.Y+(-0.055-0.29*Air-FrontFoot.Y)*AirWeight);
    end;
    ArmX := ShoulderX+Facing*(0.20-0.19*Stride);
    ArmY := ShoulderY+0.38;
    BackArmX := ShoulderX-Facing*(0.22-0.21*Stride);
    BackArmY := ShoulderY+0.36;
    if (Model=0) and not Pose.Airborne and (Pose.Slide<0.001) and (Pose.Run>0.16) then begin
      // The hero moves in a guard; arms follow the shoulders, not the leg stride.
      ArmX := ShoulderX+Facing*0.32;
      ArmY := ShoulderY-0.08;
      BackArmX := ShoulderX+Facing*0.19;
      BackArmY := ShoulderY-0.18;
    end;
    case Pose.Gesture of
      tgJab, tgLever:
        begin
          ArmX := ShoulderX+Facing*(0.25+0.43*Reach-0.22*Wind);
          ArmY := ShoulderY+0.18*(1-Reach)+0.13*Follow;
        end;
      tgCross:
        begin
          ArmX := ShoulderX+Facing*(0.13+0.50*Reach-0.27*Wind);
          ArmY := ShoulderY+0.24*(1-Reach)-0.04*Reach+0.19*Follow;
          BackArmX := ShoulderX-Facing*(0.24+0.08*Reach);
          BackArmY := ShoulderY+0.18;
        end;
      tgUpper:
        begin
          ArmX := ShoulderX+Facing*(0.18+0.33*Reach-0.21*Wind);
          ArmY := ShoulderY+0.39*(1-Reach)-0.30*Reach-0.10*Follow;
        end;
      tgKick,tgAirKick,tgSweep:
        begin
          FrontFoot.X := FrontFoot.X+Facing*(0.46*Pose.Kick+0.10*Wind);
          if Pose.Gesture=tgSweep then
            FrontFoot.Y := FrontFoot.Y-0.18*Pose.Kick-0.15*Wind
          else
            FrontFoot.Y := FrontFoot.Y-0.49*Pose.Kick-0.19*Wind;
          ArmX := ShoulderX+Facing*(0.32-0.37*Pose.Kick);
          ArmY := ShoulderY+0.13;
          BackArmX := ShoulderX-Facing*(0.24+0.29*Pose.Kick);
          BackArmY := ShoulderY+0.22;
        end;
      tgPulse,tgFinisher:
        begin
          ArmX := ShoulderX+Facing*(0.20+0.44*Reach-0.34*Wind);
          ArmY := ShoulderY+0.10+0.13*Follow;
          BackArmX := ShoulderX+Facing*(0.10+0.38*Reach-0.29*Wind);
          BackArmY := ShoulderY+0.26;
        end;
    end;
    Joint(ShoulderX,ShoulderY,BackArmX,BackArmY,0.29,0.31,-Facing,0.105*Wide,Dark,False,False);
    Joint(HipX,HipY,RearFoot.X,RearFoot.Y,0.31,0.31,Facing,0.120*Wide,Dark,True,False);
    Joint(HipX,HipY,FrontFoot.X,FrontFoot.Y,0.33,0.32,Facing,0.120*Wide,MixColor(Tint,Ink,0.55),True,True);
    // 胴は前後のパネルを重ね、関節の輪郭を途切れさせない。
    Patch(ShoulderX-0.24*Wide,ShoulderY-0.05,ShoulderX+0.24*Wide,ShoulderY-0.04,
      HipX+0.16*Wide,HipY+0.105,HipX-0.16*Wide,HipY+0.10,Ink);
    Patch(ShoulderX-0.18*Wide,ShoulderY,ShoulderX+0.18*Wide,ShoulderY+0.005,
      HipX+0.11*Wide,HipY+0.05,HipX-0.105*Wide,HipY+0.05,Tint);
    Bone(ShoulderX-0.07*Facing,ShoulderY+0.06,HipX+0.11*Facing,HipY+0.04,0.032,Light);
    Bone(HipX-0.12,HipY+0.036,HipX+0.122,HipY+0.036,0.053,Dark);
    Dot(HipX+Facing*0.05,HipY+0.035,0.029,Trim);
    if Model=0 then begin
      // 走行風によるマフラーは時刻から描画し、シークしても同じ形状。
      DrawScarf(Screen(Pose.X+(HeadX-Facing*0.13)*Size,Pose.Y+(HeadY+0.219)*Size),
        0.014*Scale*Size,0.014*Scale*Size,ScarfFlow(Pose),Facing);
      Bone(HeadX-Facing*0.13,HeadY+0.219,HeadX+Facing*0.15,HeadY+0.219,0.075,RGB(229,105,76));
    end else if Model>=3 then
      Bone(ShoulderX-0.21*Wide,ShoulderY,ShoulderX+0.21*Wide,ShoulderY,0.127,Dark);
    Dot(HeadX,HeadY,0.222*Min(1.13,Wide),Ink);
    Dot(HeadX+Facing*0.015,HeadY+0.006,0.169*Min(1.13,Wide),Skin);
    case Model of
      0:
        begin
          Bone(HeadX-0.14,HeadY-0.098,HeadX+0.14,HeadY-0.108,0.085,Dark);
          Bone(HeadX-Facing*0.17,HeadY-0.034,HeadX-Facing*0.12,HeadY+0.055,0.066,Dark);
        end;
      1: Bone(HeadX-0.14,HeadY+0.064,HeadX+0.14,HeadY+0.064,0.107,Dark);
      2: Bone(HeadX-0.16,HeadY-0.015,HeadX+0.16,HeadY-0.015,0.088,Dark);
      3,4:
        begin
          Bone(HeadX-0.16,HeadY-0.105,HeadX+0.16,HeadY-0.105,0.095,Dark);
          Bone(HeadX-Facing*0.18,HeadY-0.14,HeadX-Facing*0.23,HeadY-0.27,0.035,Ink);
          Dot(HeadX-Facing*0.23,HeadY-0.27,0.037,Trim);
        end;
    end;
    if Model=2 then
      Bone(HeadX-Facing*0.01,HeadY-0.021,HeadX+Facing*0.134,HeadY-0.021,0.032,Trim)
    else
      Bone(HeadX+Facing*0.044,HeadY-0.033,HeadX+Facing*0.129,HeadY-0.033,0.038,Ink);
    Joint(ShoulderX,ShoulderY,ArmX,ArmY,0.31,0.36,Facing,0.117*Wide,Tint,False,True);
  end;

  procedure Burst(BX,BY,Elapsed,Size: Double; Tint: TColor; Dust: Boolean=False;
    Bias: Double=1);
  var K,Count: Integer;
      A,B: TPointF;
      Q,Life,DX,DY,X,Y,R,W,Opacity,Seed: Double;
      Glow: TColor;
  begin
    if (Elapsed<0) or (Elapsed>0.49) then Exit;
    if Dust then Count := 6 else Count := 12;
    for K := 0 to Count-1 do begin
      Seed := K*0.61803398875-Floor(K*0.61803398875);
      Life := 0.19+0.28*Seed;
      if Elapsed>=Life then Continue;
      Q := Elapsed/Life;
      Opacity := Sqr(1-Q);
      DX := (0.4+(K mod 5)*0.37)*Size*Bias;
      if (K and 3)=0 then DX := -DX*0.57;
      DY := -(0.52+0.68*((K*7) mod 9)/8)*Size;
      if Dust then begin
        X := BX+DX*(0.025+Elapsed*0.56);
        Y := BY+DY*(0.015+Elapsed*0.37);
        A := Screen(X,Y);
        R := (0.035+0.15*Q)*Scale*Size*(0.55+0.55*Seed);
        Surface.Circle(A.X,A.Y,R,MixColor(Tint,RGB(173,158,148),0.49),
          True,1,0.20*Opacity);
      end else begin
        if K mod 5=0 then DY := DY*0.30;
        X := BX+(0.025+Elapsed*1.25)*DX;
        Y := BY+DY*(0.036+Elapsed*1.65)+2.8*Sqr(Elapsed);
        A := Screen(X-DX*(0.041+0.10*Opacity),Y-DY*0.052+0.031*Q);
        B := Screen(X,Y);
        Glow := MixColor(Tint,RGB(255,229,171),0.22+0.63*Seed);
        W := (0.013+0.016*Seed)*Size*Scale;
        TaperedFX(A,B,W,0.79*Opacity,Glow);
      end;
    end;
    if not Dust and (Elapsed<0.052) then begin
      Q := 1-Elapsed/0.052;
      A := Screen(BX,BY);
      R := (0.038+0.026*Q)*Size*Scale;
      Surface.Circle(A.X,A.Y,R,MixColor(Tint,RGB(255,232,180),0.54),True,1,0.63*Sqr(Q));
    end;
  end;

  procedure DrawLandingDust;
  var Lo,Hi,I,CarIndex: Integer; C: TTrainCue; X,Y,Delta,Age: Double;
  begin
    Lo := 0; Hi := FPlan.Count;
    while Lo<Hi do begin
      I := Lo+(Hi-Lo) div 2;
      if FPlan.Cue[I].Time<=T then Lo := I+1 else Hi := I;
    end;
    if Lo=0 then Exit;
    C := FPlan.Cue[Lo-1];
    Age := T-C.Time;
    if (Age>0.33) or not (C.Kind in [tmBoard,tmVaultHit,tmHurdle,tmHurdleHit,
       tmRoofGap,tmJump,tmTransfer,tmBossJump,tmStation,tmRightImpact]) then Exit;
    X := C.ToX;
    Y := FPlan.RoofY(X);
    if C.Kind=tmStation then begin
      X := X+FPlan.TravelAt(C.Time)-Travel;
      Y := TrainPlatformY;
    end else begin
      CarIndex := Floor(X/TrainPitch);
      if not FPlan.CarPosition(CarIndex,ExchangeIndex,T,Delta) then Exit;
      X := X+Delta;
    end;
    Burst(X,Y-0.045,Age,0.78,RGB(147,110,84),True,-1);
  end;

  procedure BossImpactFX(BX,BY,Roof,Elapsed,Power,Sign: Double; Tint: TColor; FinalHit: Boolean);
  var K,Count: Integer; Life,AgeRatio,Opacity,V,Angle,DX,DY,X,Y,R,Spin: Double;
      A,B: TPointF; Shade: TColor;
  begin
    Life := 0.40+0.35*Ord(FinalHit);
    if (Elapsed<0) or (Elapsed>=Life) then Exit;
    AgeRatio := Elapsed/Life;
    Count := 12+8*Ord(FinalHit);
    // Directional ejecta slow into gravity; steel chips then break into embers.
    for K := 0 to Count-1 do begin
      Angle := (K*0.61803398875-Floor(K*0.61803398875))*Pi-Pi*0.5;
      V := (1.7+0.42*((K*7) mod 9))*Power;
      DX := Sign*Cos(Angle)*V;
      DY := Sin(Angle)*V-0.24;
      X := BX+DX*Elapsed/(1+2.4*Elapsed);
      Y := Min(Roof-0.015,BY+DY*Elapsed+3.5*Sqr(Elapsed));
      A := Screen(X,Y);
      B := Screen(X-DX*(0.02+0.018*Ord(FinalHit))*(1-AgeRatio),
        Y-(DY+7*Elapsed)*0.024*(1-AgeRatio));
      Opacity := Sqr(1-AgeRatio);
      Shade := MixColor(Tint,RGB(255,247,213),0.35+0.12*(K mod 5));
      TaperedFX(B,A,(0.016+0.013*(K mod 4))*Power*Scale,Opacity,Shade);
      if K mod 3=0 then begin
        Spin := K*0.78+Elapsed*(8+K mod 4);
        R := (0.035+0.015*(K mod 4))*Scale*(1-AgeRatio);
        Surface.FillQuad(PointF(A.X+R*Cos(Spin),A.Y+R*Sin(Spin)),
          PointF(A.X+R*0.65*Sin(Spin),A.Y-R*0.65*Cos(Spin)),
          PointF(A.X-R*Cos(Spin),A.Y-R*Sin(Spin)),
          PointF(A.X-R*0.65*Sin(Spin),A.Y+R*0.65*Cos(Spin)),
          MixColor(RGB(59,57,69),Tint,0.35),Opacity);
      end;
    end;
    if Elapsed>0.042 then
      for K := 0 to 6+3*Ord(FinalHit) do begin
        X := BX+Sign*(0.05+(K mod 7)*0.10+
          Elapsed*(0.42+((K*5) mod 7)*0.26));
        Y := Roof-0.07-Elapsed*(0.37+0.11*(K mod 5));
        A := Screen(X,Y);
        R := (0.095+Elapsed*(0.40+0.15*(K mod 4)))*Scale;
        Surface.Circle(A.X,A.Y,R,RGB(64,67,75),True,1,0.26*Sqr(1-AgeRatio));
        Surface.Circle(A.X-R*0.1,A.Y-R*0.10,R*0.73,
          RGB(147,139,129),True,1,0.21*Sqr(1-AgeRatio));
      end;
    if Elapsed<0.19 then begin
      A := Screen(BX,BY);
      Opacity := Sqr(1-Elapsed/0.19);
      Surface.Circle(A.X,A.Y,(0.12+Elapsed*3.4)*Power*Scale,Tint,False,
        Max(1.0,0.035*Scale),Opacity);
      Surface.Circle(A.X,A.Y,(0.072+Elapsed*1.3)*Power*Scale,Tint,True,1,0.30*Opacity);
      Surface.Circle(A.X,A.Y,Max(0.7,0.075*Power*Scale*Opacity),RGB(255,249,219),True,1,Opacity);
      if FinalHit then begin
        B := Screen(BX-0.64*Opacity,BY+0.12);
        TaperedFX(B,PointF(A.X+0.68*Scale*Opacity,A.Y-0.08*Scale),
          0.029*Scale,Opacity,RGB(164,237,255));
      end;
    end;
  end;

  procedure RouteEquipment(Index: Integer);
  var
    Move, Lever: TTrainCue;
    Block: TTrainObstacle;
    CarIndex, K: Integer;
    Roof, Left, Right, CarOffset, Height, Lift, LeverX, LeverY, Open, Base: Double;
    Light: TColor;
  begin
    Move := FPlan.Cue[Index];
    if not TrainRouteHazard(Move,Block) then Exit;
    CarIndex := Floor(Move.FromX/TrainPitch);
    if not FPlan.CarPosition(CarIndex,ExchangeIndex,T,CarOffset) then Exit;
    Roof := FPlan.RoofY(Move.FromX);
    Left := Block.Left+CarOffset;
    Right := Block.Right+CarOffset;
    case Move.Kind of
      tmSlide: begin
        Box(Left-0.10,Roof-1.48,Left+0.05,Roof,RGB(69,94,111));
        Box(Right-0.05,Roof-1.48,Right+0.10,Roof,RGB(69,94,111));
        Base := Roof-Block.Height;
        Box(Left,Base-0.46,Right,Base,Ink);
        Box(Left,Base-0.15,Right,Base-0.045,RGB(246,184,64));
        for K := 1 to 3 do
          Line(Left+K*(Right-Left)/4,Base-0.15,Left+K*(Right-Left)/4+0.08,Base-0.045,0.04,Ink);
        Burst(Move.ToX+CarOffset-0.20,Roof-0.07,T-Move.Time,0.75,RGB(186,146,82),True,-1);
      end;
      tmRoofGap: begin
        Box(Left-0.27,Roof-0.05,Left,Roof+0.11,RGB(247,187,49));
        Box(Right,Roof-0.05,Right+0.27,Roof+0.11,RGB(247,187,49));
      end;
      tmGateRun: begin
        Lever := FPlan.Cue[Index-1];
        Open := TrainGateOpening(Lever,Move,T);
        Height := Block.Height;
        Lift := (Height+0.12)*Open;
        Box(Left-0.11,Roof-Height-0.38,Left+0.04,Roof,RGB(49,74,88));
        Box(Right-0.04,Roof-Height-0.38,Right+0.11,Roof,RGB(49,74,88));
        Box(Left+0.045,Roof-Height-Lift,Right-0.045,Roof-Lift,RGB(161,81,52));
        for K := 1 to 5 do
          Box(Left+0.04,Roof-Lift-K*Height/6,Right-0.04,Roof-Lift-K*Height/6+0.055,RGB(248,189,82));
        Light := RGB(232,72,58);
        if T>=Lever.Time then Light := RGB(72,218,126);
        Circle((Left+Right)*0.5,Roof-Height-0.37,0.115,Light);
        LeverX := Lever.ToX+TrainReach+CarOffset;
        LeverY := Roof-0.78;
        Box(LeverX-0.16,Roof-0.19,LeverX+0.16,Roof,RGB(69,94,109));
        Line(LeverX,Roof-0.16,LeverX+(Open-0.5)*0.41,LeverY+Open*0.16,0.105,Ink);
        Circle(LeverX+(Open-0.5)*0.41,LeverY+Open*0.16,0.125,Light);
        Burst(LeverX,LeverY,T-Lever.Time,0.76,RGB(250,180,58));
      end;
    end;
  end;

  procedure Bolt(StartX, EndX, BY, Progress: Double; Tint: TColor);
  var Head,Tail,Power,R: Double; A,B: TPointF;
  begin
    if (Progress<0) or (Progress>1) then Exit;
    Head := StartX+(EndX-StartX)*Progress;
    Tail := Head-Sign(EndX-StartX)*(0.18+0.25*Sin(Pi*Progress));
    Power := 0.62+0.38*Sin(Pi*Progress);
    A := Screen(Tail,BY); B := Screen(Head,BY);
    TaperedFX(A,B,Scale*0.047,Power,Tint);
    R := 0.047*Scale;
    Surface.Circle(B.X,B.Y,R*1.7,Tint,True,1,0.27*Power);
    Surface.Circle(B.X,B.Y,R,MixColor(Tint,clWhite,0.76),True,1,Power);
  end;

  procedure Sweep(const Move: TTrainCue; TargetX, BaseY: Double; LowSweep: Boolean);
  var AtTime, Height, Dur: Double;
  begin
    if (T<Move.Start) or (T>=Move.Time) then Exit;
    AtTime := TrainThreatTime(Move);
    Height := BaseY-1.02;
    if LowSweep then Height := BaseY-0.27;
    if T<AtTime then begin
      TaperedFX(Screen(TargetX-0.20,Height),Screen(TargetX+0.02,Height-0.31),
        0.035*Scale,0.66,RGB(225,73,65));
      Exit;
    end;
    Dur := Max(0.045,Min(0.14,(Move.Time-Move.Start)*0.19));
    Bolt(TargetX-0.24,Move.FromX-0.34,Height,(T-AtTime)/Dur,RGB(223,56,43));
  end;

  procedure EncounterSignal(const Pose: TTrainPose; Model: Integer; Phase: Double);
  var
    R, CY: Double;
    Accent: TColor;
  begin
    // 溜めだけ見せる短い非発光サイン。車両や画面全体はフラッシュさせない。
    if (Model<>3) or (Phase<0.27) then Exit;
    R := 0.07+0.06*Phase;
    CY := Pose.Y-1.49;
    Accent := MixColor(RGB(244,166,76),RGB(255,220,135),Phase);
    Quad(Pose.X,CY-R,Pose.X+R,CY,Pose.X,CY+R,Pose.X-R,CY,Accent);
    Line(Pose.X,CY-0.040,Pose.X,CY+0.006,0.028,Ink);
    Circle(Pose.X,CY+0.048,0.014,Ink);
  end;

  procedure RegularStrikeFX(const Move: TTrainCue; const Contact: TTrainPose; TargetX,Roof,Offset,Age: Double);
  var X,Y,AX,AY,TX,TY,Life,Q,G,DX,DY,V,R,Along,Lateral,Opacity: Double;
      K,Count: Integer;
      Tint,Core: TColor;
      A,B: TPointF;
      Kick,Pulse: Boolean;
  begin
    if (Age<0) or (Age>0.45) then Exit;
    Pulse := Move.Kind=tmShot;
    Kick := Contact.Gesture in [tgKick,tgAirKick,tgSweep];
    // First register the active palm or sole of the authored impact cell (scale
    // 0.007 world units per source pixel). Then meet the exposed target surface.
    AX := Contact.X+0.853; AY := Contact.Y-1.133;
    TX := TargetX-0.21; TY := Roof-1.01;
    if Contact.Gesture=tgUpper then TY := Roof-1.14;
    if Kick then begin
      AX := Contact.X+0.609; AY := Contact.Y-0.721;
      if Contact.Gesture=tgAirKick then begin
        AX := Contact.X+0.490; AY := Contact.Y-0.287;
      end;
      TX := TargetX-0.23; TY := Roof-0.66;
    end;
    X := 0.57*AX+0.43*TX+Offset;
    Y := 0.57*AY+0.43*TY;
    if Pulse then begin
      X := TargetX-0.18+Offset; Y := Roof-0.86;
      Life := 0.45; Count := 17; G := 0.08;
      Tint := RGB(58,188,252); Core := RGB(213,251,255);
    end else if Kick then begin
      Life := 0.34; Count := 14; G := 0.31;
      Tint := RGB(244,140,51); Core := RGB(255,230,151);
    end else begin
      Life := 0.23; Count := 9; G := 0.23;
      Tint := RGB(246,166,92); Core := RGB(255,246,219);
      if Contact.Gesture=tgUpper then G := 0.65;
    end;
    if Age>=Life then Exit;
    Q := Age/Life;
    Opacity := Sqr(1-Q);
    // A tiny contact core does not hide the attacking hand or the enemy pose.
    A := Screen(X,Y);
    Surface.Circle(A.X,A.Y,(0.07+0.10*Ord(Pulse))*Scale,Core,True,1,Opacity);
    if Kick or Pulse then begin
      R := (0.13+Q*(0.63+0.17*Ord(Pulse)))*Scale;
      Surface.Circle(A.X,A.Y,R,Tint,False,Max(1.0,Scale*0.032),Opacity);
      if Pulse then
        Surface.Circle(A.X,A.Y,R*0.61,Core,False,Max(1.0,Scale*0.020),0.62*Opacity);
    end;
    // Sweep marks stay short on punches. Kicks arc up, and projectiles vent
    // extra forward streaks after contact instead of replaying the punch flash.
    for K := 0 to Count-1 do begin
      Along := (K*0.61803398875-Floor(K*0.61803398875));
      Lateral := 2*((K*0.38196601125)-Floor(K*0.38196601125))-1;
      V := (0.37+0.72*Along)*(1+0.32*Ord(Kick)+0.42*Ord(Pulse));
      DX := (0.22+V*Q)*(0.63+0.31*(K mod 3));
      DY := Lateral*(0.10+Q*V*0.71)-G*Q+0.25*Sqr(Q);
      if (K mod 4=0) and not Pulse then DX := -0.38*DX;
      A := Screen(X+DX,Y+DY);
      B := Screen(X+DX-(0.035+0.12*V)*Opacity,Y+DY-Lateral*0.062*Opacity);
      TaperedFX(B,A,Scale*(0.013+0.012*(K mod 3)),Opacity,
        MixColor(Tint,Core,0.16+0.18*(K mod 4)));
      if (K mod 4=0) and (Kick or Pulse) then begin
        R := Scale*0.018*(1-Q);
        Surface.Circle(A.X,A.Y,R,Core,True,1,0.55*Opacity);
      end;
    end;
    if Kick or Pulse then
      for K := 0 to 3 do begin
        A := Screen(X+0.08*K+Q*(0.21+0.12*K),Roof-0.04-Q*(0.14+0.028*K));
        Surface.Circle(A.X,A.Y,(0.045+0.16*Q)*Scale,RGB(123,117,112),True,1,0.24*Opacity);
      end;
  end;

  procedure Enemy(Index: Integer);
  var
    Move, Following: TTrainCue;
    Pose, FiringPose, ContactPose: TTrainPose;
    Elapsed, Roof, TargetX, Offset, CarStart, StepRoof, U, Approach, EntryX, LandingX, Roll, ReadyAt, Flight: Double;
    FromNextCar: Boolean;
    CarIndex, Facing, Model: Integer;
    Block: TTrainObstacle;
    Patrol, Phase, FollowingX, ThreatPhase, Recoil, Lift: Double;
  begin
    Move := FPlan.Cue[Index];
    if not TrainRegularEnemy(Move.Kind) then Exit;
    TargetX := Move.ToX+TrainReach;
    if Move.Kind=tmShot then TargetX := Move.ToX+TrainShotReach;
    CarIndex := Floor(TargetX/TrainPitch);
    CarStart := CarIndex*TrainPitch;
    if not FPlan.CarPosition(CarIndex,ExchangeIndex,T,Offset) then Exit;
    Roof := FPlan.RoofY(TargetX);
    Elapsed := T-Move.Time;
    if Elapsed>0.60 then Exit;
    FromNextCar := (Move.Kind=tmVaultHit) and
      (FPlan.FormationOf(CarIndex+1)=FPlan.FormationOf(CarIndex));
    LandingX := Min(CarStart+TrainCarWidth-0.36,TargetX+1.35);
    if FPlan.NextRoofObstacle(CarIndex,TargetX,Block) and (TargetX<Block.Left) then
      LandingX := Min(LandingX,Block.Left-0.24);
    if Index+1<FPlan.Count then begin
      Following := FPlan.Cue[Index+1];
      if TrainRegularEnemy(Following.Kind) and (Following.Kind<>tmShot) then begin
        FollowingX := Following.ToX+TrainReach;
        if (FollowingX>TargetX+0.73) and (FollowingX<CarStart+TrainCarWidth) then
          LandingX := Min(LandingX,FollowingX-0.68);
      end;
    end;
    EntryX := LandingX;
    if FromNextCar then EntryX := CarStart+TrainPitch+0.53;
    if (TargetX+Offset<FarEdge-2.5) or (EntryX+Offset>NearEdge+6) then Exit;
    Pose := Default(TTrainPose);
    Pose.X := TargetX;
    Pose.Y := Roof;
    Roll := 0;
    Facing := -1;
    Model := 1+(Index mod 3);
    if Move.Kind=tmDuckHit then Model := 3;
    if Move.Kind=tmShot then Model := 2;
    ReadyAt := -0.67;
    if FromNextCar then ReadyAt := -1.05;
    if Elapsed<0 then begin
      if Elapsed<ReadyAt then begin
        U := TrainEase((ReadyAt-Elapsed)/0.22);
        Phase := T*(4.15+0.28*(CarIndex mod 3))+TargetX;
        Patrol := Min(1.12,Max(0.30,EntryX-TargetX+0.18));
        Pose.X := EntryX-Patrol*U*(0.5+0.5*Sin(Phase));
        Pose.Y := FPlan.RoofY(EntryX);
        Pose.Run := (0.50+0.39*Abs(Cos(Phase)))*U;
        if Cos(Phase)<0 then Facing := 1;
      end
      else if FromNextCar and (Elapsed<-0.47) then begin
        U := EnsureRange((Elapsed+1.05)/0.58,0.0,1.0);
        Pose.X := EntryX+(LandingX-EntryX)*U;
        StepRoof := FPlan.RoofY(EntryX);
        Pose.Y := StepRoof+(Roof-StepRoof)*U-4*1.28*U*(1-U);
        Pose.Airborne := (U>0) and (U<1);
        Pose.FlightPhase := U;
      end
      else begin
        if FromNextCar then Approach := TrainEase((Elapsed+0.47)/0.47)
        else Approach := TrainEase((Elapsed+0.67)/0.67);
        Pose.X := LandingX+(TargetX-LandingX)*Approach;
        Pose.Run := 1-TrainEase((Approach-0.72)/0.28);
        if Move.Kind in [tmVaultHit,tmDuckHit,tmHurdleHit] then begin
          ThreatPhase := T-TrainThreatTime(Move);
          Pose.Windup := Sin(Pi*EnsureRange((ThreatPhase+0.21)/0.22,0.0,1.0));
          Pose.Reach := 1-TrainEase(Abs(ThreatPhase)/0.12);
          if Move.Kind=tmDuckHit then Pose.Gesture := tgCross
          else begin
            Pose.Gesture := tgSweep;
            Pose.Kick := Pose.Reach;
          end;
        end else if (Approach>0.76) and (Model<>2) then begin
          Pose.Gesture := tgJab;
          Pose.Windup := TrainEase((Approach-0.76)/0.24)*0.64;
        end;

      end;
    end
    else begin
      ContactPose := FPlan.PoseAt(Move.Time);
      Recoil := 3.7; Lift := 3.1;
      if ContactPose.Gesture in [tgKick,tgAirKick,tgSweep] then begin
        Recoil := 5.2; Lift := 5.1;
      end else if Move.Kind=tmShot then begin
        Recoil := 4.8; Lift := 3.8;
      end;
      Pose.X := TargetX+Recoil*Elapsed/(1+0.38*Elapsed);
      Pose.Y := Roof-Max(0.0,Lift*Elapsed-7.5*Sqr(Elapsed));
      Pose.Airborne := True;
      Pose.FlightPhase := EnsureRange(Elapsed/0.60,0.0,1.0);
      Roll := Min(1.70,0.32+Elapsed*6.0);
    end;
    Pose.X := Pose.X+Offset;
    case Model of
      1: Figure(Pose,EnemyColor,0.97,Facing,Roll,Model,Offset,Elapsed/0.60);
      2: Figure(Pose,RGB(103,182,157),0.91,Facing,Roll,Model,Offset,Elapsed/0.60);
    else
      Figure(Pose,RGB(118,133,190),1.07,Facing,Roll,Model,Offset,Elapsed/0.60);
    end;
    if Elapsed<0 then EncounterSignal(Pose,Model,Pose.Windup)
    else RegularStrikeFX(Move,ContactPose,TargetX,Roof,Offset,Elapsed);
    if Move.Kind in [tmVaultHit,tmDuckHit,tmHurdleHit] then
      Sweep(Move,Pose.X,Roof,Move.Kind<>tmDuckHit);
    if Move.Kind=tmShot then begin
      Flight := Min(0.125,(Move.Time-Move.Start)*0.64);
      FiringPose := FPlan.PoseAt(Move.Time-Flight);
      Bolt(FiringPose.X+0.67+Offset,TargetX-0.18+Offset,Roof-0.86,
        (T-Move.Time+Flight)/Flight,RGB(38,166,234));
    end;
  end;


begin
  T := Frame.Time;
  Travel := 0;
  Scale := 1;
  CenterX := 4.3;
  CenterY := -0.36;
  ViewWidth := 15.0;
  Shake := 0;
  ExchangeIndex := 0;
  Area := 0;
  CrashBlend := 0;
  BossEntrance := 0;
  if FPlan<>nil then begin
    T := Min(T,FPlan.EndTime);
    Travel := FPlan.TravelAt(T);
    if FPlan.Count>0 then begin
      P := FPlan.PoseAt(T);
      ExchangeIndex := FPlan.ExchangeAt(T);
      Area := ExchangeIndex mod 5;
      LastCue := FPlan.Cue[FPlan.Count-1];
      ViewWidth := TrainRoofViewWidth;
      CenterX := FPlan.RoofCameraX(T);
      CenterY := -0.72;
      FPlan.CollisionCamera(ExchangeIndex,T,CrashX,CrashWidth,CrashBlend);
      if CrashBlend<1 then FocusSignatureCue;
      if CrashBlend>0 then begin
        CenterX := CenterX+(CrashX-CenterX)*CrashBlend;
        CenterY := CenterY+(1.17-CenterY)*CrashBlend;
        ViewWidth := ViewWidth+(CrashWidth-ViewWidth)*CrashBlend;
      end;
      Board := FPlan.Cue[0];
      if T<Board.Time+0.51 then
        HeroCloseup(1-TrainEase((T-Board.Time-0.06)/0.45));
      if T>=LastCue.Start-0.20 then
        HeroCloseup(TrainEase((T-LastCue.Start+0.20)/0.52));
      BossEntry := FPlan.Cue[FPlan.Count-4];
      BossFirst := FPlan.Cue[FPlan.Count-3];
      BossFinal := FPlan.Cue[FPlan.Count-2];
      BossEntrance := Max(0.0,BossEntry.Start-0.32);
      BossBlend := TrainEase((T-BossEntrance)/0.32)*
        (1-TrainEase((T-BossFinal.Time-0.19)/0.39));
      if BossBlend>0 then begin
        U := BossFirst.ToX+TrainReach+1.9*(1-TrainEase((T-BossEntry.Start)/0.65))+
          (BossFinal.ToX-BossFirst.ToX)*TrainEase((T-BossFirst.Time)/Max(0.14,BossFinal.Start-BossFirst.Time));
        CenterX := CenterX+((P.X+U)*0.5-CenterX)*BossBlend;
        CenterY := CenterY+(-0.75-CenterY)*BossBlend;
        U := EnsureRange(Abs(U-P.X)+4.5,9.2,18.0);
        ViewWidth := ViewWidth+(U-ViewWidth)*BossBlend;
        Age := T-BossFinal.Time;
        if (Age>=0) and (Age<0.27) then begin
          U := Sqr(1-Age/0.27);
          CenterX := CenterX+0.19*U*Sin(33*Age);
          Shake := Shake+0.22*U*Sin(54*Age);
        end;
        Age := T-BossFirst.Time;
        if (Age>=0) and (Age<0.14) then
          Shake := Shake+0.071*(1-Age/0.14)*Sin(61*Age);
      end;
      if ExchangeIndex<FPlan.ExchangeCount then begin
        Exchange := FPlan.Exchange[ExchangeIndex];
        for I := Exchange.StartIndex to Exchange.CoupleIndex-1 do begin
          Age := T-FPlan.Cue[I].Time;
          if (Age>=0) and (Age<0.36) then begin
            U := 1-Age/0.36;
            Direction := 1;
            if I=Exchange.RightIndex then Direction := -1;
            CenterX := CenterX-Direction*0.59*U*Sin(34*Age);
            Shake := Shake+0.36*U*Sin(76*Age);
          end;
        end;
      end;
    end;
  end;
  Scale := Min(Frame.Width/ViewWidth,Frame.Height/(ViewWidth*0.56));
  FarEdge := CenterX-Frame.Width/(2*Scale)-0.1;
  NearEdge := CenterX+Frame.Width/(2*Scale)+0.1;

  Art := TrainArtAvailable(Surface.Images);
  if Art then ArtBackdrop(False) else Backdrop;

  if (FPlan=nil) or (FPlan.Count=0) then begin
    DrawTrack;
    if not Frame.BackgroundOnly then begin
      Car(0,0,MainColor,False,False);
      Car(TrainPitch,0,MainColor,True,False);
    end;
    ArtBackdrop(True);
    Exit;
  end;
  if T<FPlan.Cue[0].Time+0.65 then
    Platform(-10.6-Travel,13.00,TrainPlatformY,True);
  StationX := FPlan.TrainLength-1.5+FPlan.TravelAt(FPlan.Arrival)-Travel;
  Platform(StationX,14.0,TrainPlatformY,True);
  DrawTrack;

  if Frame.BackgroundOnly then begin ArtBackdrop(True); Exit; end;
  FirstCar := Max(0,Floor((FarEdge-10)/TrainPitch)-1);
  LastCar := Min(FPlan.Cars-1,Floor((NearEdge+33)/TrainPitch)+1);
  for I := FirstCar to LastCar do
    if FPlan.CarPosition(I,ExchangeIndex,T,Offset) then begin
      Formation := FPlan.FormationOf(I);
      Color := FormationColor(Formation);
      if (ExchangeIndex<FPlan.ExchangeCount) and (Exchange.LeftIndex>=0) and (I=Exchange.LeadCar-1) then
        Color := MixColor(Color,Ink,0.27*CrashBlend);
      Car(I*TrainPitch+Offset,FPlan.RoofY(I*TrainPitch+0.4),Color,
        Formation<>FPlan.FormationOf(I+1),CollisionDamage(I,Formation),I);
    end;
  ArtBackdrop(True);
  FPlan.CarCues(FirstCar,LastCar,FirstCue,LastVisibleCue);
  for I := FirstCue to LastVisibleCue do begin
    RoofEquipment(FPlan.Cue[I]);
    RouteEquipment(I);
  end;
  if ExchangeIndex<FPlan.ExchangeCount then begin
    if Exchange.LeftIndex>=0 then
      Burst(Exchange.LeadCar*TrainPitch-TrainGap*0.5,RailY-0.65,
        T-FPlan.Cue[Exchange.LeftIndex].Time,1.63,RGB(241,85,26));
    if Exchange.RightIndex>=0 then
      Burst((Exchange.LeadCar+1)*TrainPitch-TrainGap*0.5,RailY-0.65,
        T-FPlan.Cue[Exchange.RightIndex].Time,1.63,RGB(241,85,26),False,-1);
    Burst((Exchange.LeadCar+1)*TrainPitch-TrainGap*0.5,RailY-0.64,
      T-FPlan.Cue[Exchange.CoupleIndex].Time,0.92,RGB(69,161,213));
  end;

  for I := FirstCue to LastVisibleCue do Enemy(I);
  BossX := BossFirst.ToX+TrainReach;
  N := Default(TTrainPose);
  BossArmorAge := T-BossFirst.Time;
  BossGuard := TrainEase((T-BossFirst.Finish)/Max(0.14,BossFinal.Start-BossFirst.Finish));
  BossStagger := Min(0.42,Max(0.10,(BossFinal.Start-BossFirst.Time)*0.66));
  BossDefeat := Min(0.96,Max(0.55,LastCue.Time-BossFinal.Time+0.18));
  BossImpact := -1;
  N.Gesture := tgCross;
  if BossArmorAge<0 then begin
    U := TrainEase((T-BossFirst.Start+0.29)/Max(0.02,BossFirst.Time-BossFirst.Start+0.29));
    BossX := BossX+2.2*(1-U);
    N.Run := 0.88*(1-U);
    N.Windup := TrainEase((T-BossFirst.Start+0.12)/0.21);
    N.Reach := Max(0.0,1-Abs(T-TrainThreatTime(BossFirst))/0.13);
    N.ArtGesturePhase := 0.32*N.Windup+0.18*N.Reach;
  end else begin
    U := EnsureRange(BossArmorAge/BossStagger,0.0,1.0);
    BossX := BossX+(BossFinal.ToX-BossFirst.ToX)*BossGuard+0.72*Sin(Pi*U);
    if U<1 then begin
      BossImpact := Min(0.55,U*0.84);
      N.Crouch := 0.42*Sin(Pi*U);
    end else begin
      // Replant the feet and brace for the final charge after the armor hit.
      N.Run := 0.72*Sin(Pi*BossGuard);
      N.Windup := 0.68*TrainEase((BossGuard-0.48)/0.45);
      N.ArtGesturePhase := 0.34*N.Windup;
    end;
  end;
  BossY := FPlan.RoofY(BossX);
  if (T>=BossEntrance) and (T<BossFinal.Time+BossDefeat) and
    FPlan.CarPosition(FPlan.Cars-1,ExchangeIndex,T,Offset) and
    (BossX+Offset>=FarEdge-1.8) and (BossX+Offset<=NearEdge+1.8) then begin
    BossX := BossX+Offset;
    N.X := BossX;
    N.Y := BossY;
    Age := T-BossFinal.Time;
    BossRoll := 0;
    if Age>=0 then begin
      U := EnsureRange(Age/BossDefeat,0.0,1.0);
      N.X := N.X+2.0*TrainEase(U/0.58);
      N.Y := N.Y-1.7*U*Max(0.0,1-U*2.6);
      N.Airborne := U<0.39;
      N.FlightPhase := EnsureRange(U/0.39,0.0,1.0);
      BossRoll := Min(1.68,0.24+Age*4.6);
      BossImpact := 1.07*U;
    end else if T>=BossFinal.Start then begin
      N.Reach := Max(0.0,1-Abs(T-TrainThreatTime(BossFinal))/0.12);
      N.ArtGesturePhase := 0.34+0.16*N.Reach;
    end;
    Figure(N,BossColor,1.24,-1,BossRoll,4,Offset,BossImpact);
    if (Age<0) and (BossArmorAge>=0) and (BossArmorAge<0.30) then
      BossImpactFX(BossFirst.ToX+0.70+Offset,BossY-0.87,BossY,
        BossArmorAge,0.82,1,RGB(232,153,77),False);
    if Age<0 then begin
      // The rival and the final boss share base artwork. This crown and red gauge
      // identify the larger boss from the entrance until the finishing hit.
      U := N.Y-2.07;
      Box(N.X-0.38,U-0.02,N.X+0.38,U+0.10,Ink);
      if BossArmorAge<0 then Box(N.X-0.34,U+0.014,N.X+0.34,U+0.063,RGB(239,81,83))
      else Box(N.X-0.34,U+0.014,N.X+0.02,U+0.063,RGB(239,141,71));
      Quad(N.X-0.18,U-0.13,N.X+0.18,U-0.13,N.X+0.24,U-0.36,N.X-0.24,U-0.36,Ink);
      Line(N.X-0.15,U-0.20,N.X-0.18,U-0.31,0.035,RGB(255,200,94));
      Line(N.X-0.15,U-0.20,N.X,U-0.34,0.035,RGB(255,200,94));
      Line(N.X,U-0.34,N.X+0.15,U-0.20,0.035,RGB(255,200,94));
      Line(N.X+0.15,U-0.20,N.X+0.18,U-0.31,0.035,RGB(255,200,94));
    end;
    C := BossEntry;
    if (T>=C.Start) and (T<C.Time) then
      Bolt(BossX-0.31,C.FromX-0.61,BossY-0.24,(T-TrainThreatTime(C))/0.18,RGB(229,52,57));
    if BossArmorAge<0 then Sweep(BossFirst,BossX,BossY-0.10,False);
    if (Age<0) and (T>=BossFirst.Finish) and (BossGuard>0.45) then begin
      U := N.X-0.44;
      CastGlow(U,N.Y-0.90,0.051+0.050*N.Windup,0.51+0.38*N.Windup,RGB(231,74,74));
    end;
    if T>=BossFinal.Start then begin
      U := Min(0.10,(BossFinal.Time-BossFinal.Start)*0.60);
      Ahead := FPlan.PoseAt(BossFinal.Time-U);
      Bolt(Ahead.X+0.49,BossFinal.ToX+TrainReach,BossY-0.77,(Age+U)/U,RGB(19,132,242));
    end;
    BossImpactFX(BossFinal.ToX+0.72+Offset,BossY-0.77,BossY,
      Age,1.45,1,RGB(249,160,75),True);
    BossImpactFX(BossFinal.ToX+1.62+Offset,BossY-0.10,BossY,
      Age-BossDefeat*0.39,0.64,1,RGB(171,141,114),False);
  end;
  DrawMotionFX(P);
  DrawLandingDust;
  Figure(P,HeroColor,1.0,1);
  if (P.Reach>0.38) and (P.Gesture in [tgPulse,tgFinisher]) then begin
    U := P.Reach;
    CastGlow(P.X+0.69,P.Y-1.08,0.068+0.065*U,U,RGB(58,171,228));
    if P.Gesture=tgFinisher then
      TaperedFX(Screen(P.X+0.24,P.Y-0.58),Screen(P.X+0.78,P.Y-1.05),
        0.026*Scale,U*0.67,RGB(140,246,252));
  end;
end;

end.
