unit RhythmMarbleScene;
// 球の経路と仕掛けを横から描き、接触した仕掛けだけを反応させる。
interface

uses RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmMarblePlan, RhythmRenderSurface, RhythmEqualizer,
  RhythmImageBank, RhythmStyles;

type
  TMarbleAnimation = class(TAnimationScene)
  private
    FPlan: TMarblePlan; // 復元したコースを描画器が所有する。
    FRef: TRhythmPlanRef;
    FAttempt, FError: string; // 復元を試した計画・音源の組み合わせと、そのエラー。
  public
    Audio: TRhythmAudio; // 借用。描画は保存した接触列から復元する。
    BallStyle: TMarbleBallStyle;
    StageStyle: TMarbleStageStyle;
    destructor Destroy; override;
    // 次のPrepareが復元に使う計画参照を設定する。
    procedure SetReference(const Ref: TRhythmPlanRef);
    procedure Prepare(const Frame: TAnimationFrame); override;
    procedure Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame); override;
    function Notice: string; override;
    function GoalTime: Double; override;
    function Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
  end;

// 描画器が所有する球の画像バンクを作る。
function CreateMarbleImages: TAnimationImageBank;

implementation

uses System.Types, System.SysUtils, System.Math, Vcl.Graphics, Winapi.Windows, RhythmBallGeometry, RhythmMarbleImages;

type
  TMarblePalette = record
    Ink, Timber, TimberEdge, Brass, PaleBrass, Alloy, Aqua, Orange, Pearl: TColor;
    TopColor, BottomColor, Grid, Pin, PinLight: TColor;
  end;

  TMarblePainter = record
    Surface: TAnimationRenderSurface;
    Plan: TMarblePlan;
    BallStyle: TMarbleBallStyle;
    StageStyle: TMarbleStageStyle;
    Colors: TMarblePalette;
    Frame: TAnimationFrame;
    Time, Left, Top, Scale, Width, Height: Double;
    function Screen(X, Y: Double): TPointF;
    procedure Rect(X1, Y1, X2, Y2: Double; Color: TColor);
    procedure Line(X1, Y1, X2, Y2, Stroke: Double; Color: TColor);
    procedure Dot(X, Y, Radius: Double; Color: TColor; Filled: Boolean = True);
    procedure Backboard;
    procedure RailFinish(X1, Y1, X2, Y2: Double);
    procedure Rail(const A, B: TBallPoint);
    procedure Plate(X, Y, HalfWidth, Slope: Double; Color: TColor);
    procedure Gate(const Cue: TMarbleCue; Age: Double);
    procedure Bell(X, Y, Age: Double);
    procedure Spring(X, Y, Age, Slope: Double);
    procedure CatchTray(X, Y, Slope: Double; Heading: Integer);
    procedure Tip(const Cue: TMarbleCue; Age: Double);
    procedure Goal(const Cue: TMarbleCue; Age: Double);
    procedure TurnGuide(const Leg: TMarbleLeg);
    procedure Carrier(const Leg: TMarbleLeg; DeviceKind: TMarbleDevice; Parked: Double = 0);
    procedure SwingArm(const Leg: TMarbleLeg);
    procedure Chute(const Leg, Previous: TMarbleLeg);
    procedure Cradle(const Leg: TMarbleLeg; const P: TBallPoint; Color: TColor);
    procedure TiltingTray(const Bridge: TMarbleBridge; const Trigger: TBallPoint);
    procedure AuxiliaryTrack(const A, B: TBallPoint);
    procedure AuxiliaryBell(const P: TBallPoint; const Beat: TMarbleBeat; Heading: Integer);
    procedure AuxiliaryRocker(const Bridge: TMarbleBridge; const Contact, Along: TBallPoint; Age, Throw: Double);
    procedure AuxiliaryShutter(const Link: TMarbleLink);
    procedure Shutter(const Link: TMarbleLink; const Arm: TBallPoint; Size, Opening: Double);
    procedure AuxiliaryBridge(const Bridge, Reply: TMarbleBridge; const GateArm: TBallPoint; Opening: Double);
    procedure PassingTrack(const Aux: TMarbleAuxiliary; const CarrierLeg: TMarbleLeg);
    procedure CounterTrack(const Aux: TMarbleAuxiliary);
    procedure InterlockDevice(const Interlock: TMarbleInterlock);
    procedure SeesawBoard(const Board: TMarbleBoard);
    procedure ReceivingTray(const Saw: TMarbleSeesaw);
    procedure WeightedLift(const Saw: TMarbleSeesaw);
    procedure JunctionDevice(const Saw: TMarbleSeesaw; const Leg: TMarbleLeg);
    procedure WheelBell(const P: TBallPoint; const Beat: TMarbleBeat; H: Integer);
    procedure SeesawTrack(const Aux: TMarbleAuxiliary; const JunctionLeg: TMarbleLeg);
    procedure SharedTap(const Cue: TMarbleCue);
    procedure Linkage(const Link: TMarbleLink);
    procedure ContactPulse(X, Y, Age, Power: Double);
    procedure Device(Index: Integer);
    procedure Sphere(const P: TBallPoint; Radius: Double; Asset: Integer);
    procedure Ball(const P: TBallPoint);
    procedure Course(const P: TBallPoint);
    function SectionVisible(const Section: TMarbleSection): Boolean;
    procedure Paint;
  end;

const
  StagePalettes: array[TMarbleStageStyle] of TMarblePalette = (
    (Ink:$0028231B; Timber:$0049749E; TimberEdge:$0077AAD0; Brass:$0051A9E9; PaleBrass:$0088DDFB; Alloy:$00B4B49E; Aqua:$00BFDB5E; Orange:$004C83FA; Pearl:$00D4F9FF;
     TopColor:$004A4624; BottomColor:$002D2A15; Grid:$004E6257; Pin:$002B332B; PinLight:$00657566),
    (Ink:$00633B65; Timber:$00966CB9; TimberEdge:$00CEB8F4; Brass:$00408BD6; PaleBrass:$00A1E5FF; Alloy:$00D8A2B1; Aqua:$007D932C; Orange:$00754FC0; Pearl:$00E1F7FF;
     TopColor:$00F2DDC1; BottomColor:$00DFCAE7; Grid:$00ECC7DA; Pin:$00D7B6C3; PinLight:$00F8EFF9),
    (Ink:$001B1520; Timber:$003C6298; TimberEdge:$00549AD5; Brass:$0046AEE9; PaleBrass:$00A3E4FF; Alloy:$007B8994; Aqua:$009BA881; Orange:$004874F0; Pearl:$00BCF0FF;
     TopColor:$002F353F; BottomColor:$001F191D; Grid:$00374760; Pin:$0024222B; PinLight:$00546278),
    (Ink:$002E2A1F; Timber:$00747565; TimberEdge:$009CAB9C; Brass:$0063ABC9; PaleBrass:$00A2DBE8; Alloy:$00B5B7A4; Aqua:$00A8C772; Orange:$00558DEC; Pearl:$00CDF7F6;
     TopColor:$00545645; BottomColor:$00312E22; Grid:$00434132; Pin:$0038382A; PinLight:$00687164),
    (Ink:$004A2E14; Timber:$00AE8A46; TimberEdge:$00F6E7A6; Brass:$00EABE77; PaleBrass:$00FFF8D6; Alloy:$00D1B68D; Aqua:$00E9E378; Orange:$008BB3FF; Pearl:$00FFFBF6;
     TopColor:$00835F35; BottomColor:$00502D18; Grid:$0098774F; Pin:$006B4627; PinLight:$00B79E74),
    (Ink:$00290B10; Timber:$006D2C44; TimberEdge:$00E855B2; Brass:$00F071BD; PaleBrass:$00FEABE9; Alloy:$00B26F81; Aqua:$00F4E84B; Orange:$009C70FF; Pearl:$00FFEFF7;
     TopColor:$00481323; BottomColor:$002A130A; Grid:$0070344A; Pin:$0050222B; PinLight:$008B5465));

function CreateMarbleImages: TAnimationImageBank;
begin
  Result := RhythmMarbleImages.CreateMarbleImages;
end;

function TMarblePainter.Screen(X, Y: Double): TPointF;
begin
  Result := PointF((X - Left) * Scale, (Top - Y) * Scale);
end;

procedure TMarblePainter.Rect(X1, Y1, X2, Y2: Double; Color: TColor);
var A, B: TPointF;
begin
  A := Screen(Min(X1, X2), Y2);
  B := Screen(Max(X1, X2), Y1);
  Surface.FillRect(A.X, A.Y, B.X, B.Y, Color);
end;

procedure TMarblePainter.Line(X1, Y1, X2, Y2, Stroke: Double; Color: TColor);
var A, B: TPointF;
begin
  A := Screen(X1, Y1);
  B := Screen(X2, Y2);
  Surface.Line(A.X, A.Y, B.X, B.Y, Color, Max(1.0, Stroke * Scale));
end;

procedure TMarblePainter.Dot(X, Y, Radius: Double; Color: TColor; Filled: Boolean);
var A: TPointF;
begin
  A := Screen(X, Y);
  Surface.Circle(A.X, A.Y, Radius * Scale, Color, Filled, Max(1.0, 0.016 * Scale));
end;

function BlendColor(A, B: TColor; U: Double): TColor;
begin
  Result := RGB(Round(GetRValue(A) + (GetRValue(B) - GetRValue(A)) * U),
    Round(GetGValue(A) + (GetGValue(B) - GetGValue(A)) * U),
    Round(GetBValue(A) + (GetBValue(B) - GetBValue(A)) * U));
end;

procedure TMarblePainter.Backboard;
var I, J, K: Integer; X, Y, Bottom, StepX, StepY, Angle, RowX: Double; Tint: TColor;
begin
  for I := 0 to 13 do
    Surface.FillRect(0, Frame.Height * I / 14, Frame.Width, Frame.Height * (I + 1) / 14,
      BlendColor(Colors.TopColor, Colors.BottomColor, I / 13));
  Bottom := Top - Height;
  if StageStyle = msWoodWorkshop then
  begin
    for I := Floor(Left / 0.60) to Ceil((Left + Width) / 0.60) do
    begin
      X := I * 0.60;
      if I mod 5 = 0 then Line(X, Bottom, X, Top, 0.014, Colors.Grid);
      for J := Floor(Bottom / 0.60) to Ceil(Top / 0.60) do
      begin
        Y := J * 0.60;
        Dot(X, Y, 0.022, Colors.Pin);
        Dot(X - 0.008, Y - 0.010, 0.009, Colors.PinLight);
      end;
    end;
    Exit;
  end;

  // 模様はコース上の位置に固定し、カメラが動いてもちらつかないようにする。
  StepX := 1.55;
  StepY := 1.18;
  case StageStyle of
    msFairyTale: begin StepX := 2.00; StepY := 1.45; end;
    msBrassWorks: begin StepX := 2.25; StepY := 1.75; end;
    msStoneRuins: begin StepX := 0.92; StepY := 0.48; end;
    msIcePalace: begin StepX := 1.37; StepY := 1.36; end;
  end;
  for J := Floor(Bottom / StepY) - 1 to Ceil(Top / StepY) do
  begin
    Y := J * StepY;
    RowX := StepX * 0.5 * Ord(Odd(J));
    if StageStyle = msStoneRuins then Line(Left, Y, Left + Width, Y, 0.024, Colors.Grid);
    for I := Floor((Left - RowX) / StepX) - 1 to Ceil((Left + Width - RowX) / StepX) do
    begin
      X := I * StepX + RowX;
      case StageStyle of
        msFairyTale:
          begin
            Tint := BlendColor(Colors.Grid, Colors.PinLight, 0.65);
            Dot(X - 0.22, Y, 0.18, Tint);
            Dot(X, Y + 0.065, 0.25, Tint);
            Dot(X + 0.24, Y, 0.18, Tint);
            Rect(X - 0.23, Y - 0.15, X + 0.24, Y - 0.018, Tint);
            Line(X + 0.68, Y + 0.48, X + 0.68, Y + 0.71, 0.020, Colors.PinLight);
            Line(X + 0.58, Y + 0.595, X + 0.78, Y + 0.595, 0.020, Colors.PinLight);
            Dot(X + 0.88, Y + 0.32, 0.025, Colors.Grid);
          end;
        msBrassWorks:
          begin
            Line(X - 0.80, Y - 0.78, X - 0.80, Y + 0.78, 0.027, Colors.Pin);
            Dot(X, Y, 0.42, Colors.Grid, False);
            Dot(X, Y, 0.27, Colors.Grid, False);
            Dot(X, Y, 0.080, Colors.Grid, False);
            for K := 0 to 11 do
            begin
              Angle := K * Pi / 6;
              Line(X + 0.40 * Cos(Angle), Y + 0.40 * Sin(Angle), X + 0.49 * Cos(Angle),
                Y + 0.49 * Sin(Angle), 0.052, Colors.Grid);
            end;
            Dot(X - 0.80, Y - 0.65, 0.032, Colors.PinLight);
            Dot(X - 0.80, Y + 0.65, 0.032, Colors.PinLight);
          end;
        msStoneRuins:
          begin
            Line(X, Y, X, Y + StepY, 0.021, Colors.Grid);
            Line(X + 0.10, Y - 0.041, X + 0.63, Y - 0.041, 0.014, Colors.PinLight);
            if (I + J) mod 3 = 0 then
            begin
              Line(X + 0.22, Y + 0.17, X + 0.29, Y + 0.21, 0.013, Colors.Pin);
              Line(X + 0.29, Y + 0.21, X + 0.40, Y + 0.18, 0.013, Colors.Pin);
            end;
          end;
        msIcePalace:
          begin
            Tint := BlendColor(Colors.TopColor, Colors.Grid, 0.38);
            Surface.FillQuad(Screen(X, Y + 0.52), Screen(X + 0.27, Y + 0.10),
              Screen(X, Y - 0.43), Screen(X - 0.27, Y + 0.10), Tint);
            Line(X, Y + 0.52, X, Y - 0.43, 0.014, Colors.Grid);
            Line(X - 0.27, Y + 0.10, X + 0.27, Y + 0.10, 0.015, Colors.Grid);
            Dot(X + 0.50, Y + 0.49, 0.024, Colors.PinLight);
          end;
        msNeonCircuit:
          begin
            Line(X - 0.44, Y + 0.29, X, Y + 0.29, 0.017, Colors.Grid);
            Line(X, Y + 0.29, X + 0.23, Y + 0.065, 0.017, Colors.Grid);
            Line(X + 0.23, Y + 0.065, X + 0.63, Y + 0.065, 0.017, Colors.Grid);
            Line(X - 0.29, Y - 0.24, X + 0.18, Y - 0.24, 0.014, Colors.PinLight);
            Dot(X - 0.44, Y + 0.29, 0.045, Colors.Grid, False);
            Dot(X + 0.63, Y + 0.065, 0.040, Colors.Grid, False);
            Dot(X + 0.18, Y - 0.24, 0.027, Colors.PinLight, False);
          end;
      end;
    end;
  end;
end;

procedure TMarblePainter.RailFinish(X1, Y1, X2, Y2: Double);
var I: Integer; X, Y: Double;
begin
  case StageStyle of
    msFairyTale:
      Line(X1, Y1 - 0.105, X2, Y2 - 0.105, 0.027, Colors.PaleBrass);
    msBrassWorks:
      begin
        Line(X1, Y1 - 0.064, X2, Y2 - 0.064, 0.021, Colors.PaleBrass);
        Line(X1, Y1 - 0.132, X2, Y2 - 0.132, 0.019, Colors.Ink);
      end;
    msStoneRuins, msIcePalace:
      for I := Ceil((X1 + 0.08) / 0.43) to Floor((X2 - 0.08) / 0.43) do
      begin
        X := I * 0.43;
        Y := Y1 + (Y2 - Y1) * (X - X1) / (X2 - X1);
        if StageStyle = msStoneRuins then
        begin
          Line(X, Y - 0.038, X + 0.025, Y - 0.165, 0.028, Colors.Ink);
          Line(X + 0.050, Y - 0.07, X + 0.125, Y - 0.088, 0.019, Colors.Alloy);
        end
        else
        begin
          Line(X, Y - 0.15, X + 0.066, Y - 0.038, 0.029, Colors.PaleBrass);
          Line(X - 0.032, Y - 0.15, X + 0.040, Y - 0.05, 0.014, Colors.Alloy);
        end;
      end;
    msNeonCircuit:
      begin
        Line(X1, Y1 - 0.065, X2, Y2 - 0.065, 0.085, Colors.TimberEdge);
        Line(X1, Y1 - 0.065, X2, Y2 - 0.065, 0.027, Colors.PaleBrass);
        Line(X1, Y1 - 0.139, X2, Y2 - 0.139, 0.018, Colors.Aqua);
      end;
  end;
end;

procedure TMarblePainter.Rail(const A, B: TBallPoint);
var I: Integer; X, Y, X1, X2, Y1, Y2: Double;
begin
  if A.X > B.X then
  begin
    Rail(B, A);
    Exit;
  end;
  X1 := Max(A.X, Left - 0.5);
  X2 := Min(B.X, Left + Width + 0.5);
  if X2 - X1 < 1E-6 then Exit;
  Y1 := A.Y + (B.Y - A.Y) * (X1 - A.X) / (B.X - A.X);
  Y2 := A.Y + (B.Y - A.Y) * (X2 - A.X) / (B.X - A.X);
  Surface.FillQuad(Screen(X1, Y1), Screen(X2, Y2), Screen(X2, Y2 - 0.18), Screen(X1, Y1 - 0.18), Colors.Timber);
  Line(X1, Y1 - 0.022, X2, Y2 - 0.022, 0.042, Colors.TimberEdge);
  Line(X1, Y1 - 0.17, X2, Y2 - 0.17, 0.026, Colors.Ink);
  RailFinish(X1, Y1, X2, Y2);
  for I := Ceil((X1 + 0.20) / 0.78) to Floor((X2 - 0.20) / 0.78) do
  begin
    X := I * 0.78;
    Y := Y1 + (Y2 - Y1) * (X - X1) / (X2 - X1);
    Rect(X - 0.065, Y - 0.47, X + 0.065, Y - 0.17, Colors.Timber);
    Line(X, Y - 0.45, X + 0.30, Y - 0.22, 0.055, Colors.Timber);
    Dot(X, Y - 0.105, 0.023, Colors.Ink);
    case StageStyle of
      msFairyTale: Dot(X, Y - 0.105, 0.034, Colors.Pearl);
      msBrassWorks: Dot(X - 0.032, Y - 0.104, 0.019, Colors.Alloy);
      msIcePalace, msNeonCircuit: Line(X, Y - 0.41, X, Y - 0.23, 0.018, Colors.Aqua);
    end;
  end;
end;

procedure TMarblePainter.Plate(X, Y, HalfWidth, Slope: Double; Color: TColor);
var L, R: Double;
begin
  L := Y - Slope * HalfWidth;
  R := Y + Slope * HalfWidth;
  Surface.FillQuad(Screen(X - HalfWidth, L), Screen(X + HalfWidth, R),
    Screen(X + HalfWidth, R - 0.09), Screen(X - HalfWidth, L - 0.09), Color);
  Line(X - HalfWidth, L - 0.015, X + HalfWidth, R - 0.015, 0.026, Colors.Pearl);
end;

procedure TMarblePainter.Gate(const Cue: TMarbleCue; Age: Double);
var X, Y, Swing, ArmX, ArmY, A: Double; I, Dir: Integer;
begin
  Dir := Cue.Heading;
  X := Cue.Surface.X + Dir * 0.025;
  Y := Cue.Center.Y + 0.48;
  Swing := 1.57 * (1 - Exp(-Max(0.0, Age) * 34));
  ArmX := X + Dir * 0.48 * Sin(Swing);
  ArmY := Y - 0.48 * Cos(Swing);
  // 軸は背板に固定し、球が進む高さには支柱を置かない。
  Rect(X + Dir * 0.32, Y - 0.025, X + Dir * 0.51, Y + 0.22, Colors.Timber);
  Dot(X + Dir * 0.42, Y + 0.155, 0.034, Colors.Ink);
  Dot(X + Dir * 0.42, Y + 0.155, 0.017, Colors.Alloy);
  Line(X - Dir * 0.11, Y + 0.04, X + Dir * 0.45, Y + 0.04, 0.073, Colors.TimberEdge);
  Line(X, Y, ArmX, ArmY, 0.055, Colors.Orange);
  for I := 0 to 7 do
  begin
    A := Dir * Swing + I * Pi / 4;
    Line(X + 0.071 * Cos(A), Y + 0.071 * Sin(A), X + 0.109 * Cos(A), Y + 0.109 * Sin(A), 0.039, Colors.Brass);
  end;
  Dot(X, Y, 0.084, Colors.Ink);
  Dot(X, Y, 0.062, Colors.Brass);
  Dot(X, Y, 0.024, Colors.Ink);
  Dot(ArmX, ArmY, 0.025, Colors.PaleBrass);
end;

procedure TMarblePainter.Bell(X, Y, Age: Double);
var Sway, RimX, KnobX: Double;
begin
  Sway := 0;
  if Age >= 0 then Sway := 0.10 * Sin(Age * 48) * Exp(-Age * 6);
  RimX := X + Sway;
  KnobX := X - Sway * 0.32;
  Rect(X - 0.22, Y - 0.22, X + 0.22, Y - 0.065, Colors.Timber);
  Dot(X - 0.16, Y - 0.145, 0.029, Colors.Ink);
  Dot(X + 0.16, Y - 0.145, 0.029, Colors.Ink);
  Line(X, Y - 0.07, X, Y - 0.20, 0.052, Colors.Alloy);
  Surface.FillQuad(Screen(KnobX - 0.083, Y - 0.17), Screen(KnobX + 0.083, Y - 0.17),
    Screen(RimX + 0.20, Y - 0.43), Screen(RimX - 0.20, Y - 0.43), Colors.Brass);
  Line(RimX - 0.22, Y - 0.43, RimX + 0.22, Y - 0.43, 0.057, Colors.PaleBrass);
  Dot(RimX + Sway * 0.34, Y - 0.47, 0.047, Colors.Orange);
  Plate(X, Y, 0.22, 0, Colors.Brass);
end;

procedure TMarblePainter.Spring(X, Y, Age, Slope: Double);
var I: Integer; PreviousX, PreviousY, PX, PY, Press: Double;
begin
  Press := 0;
  if Age > 0 then Press := 0.068 * (1 - Exp(-Age * 42)) * Exp(-Age * 12);
  Rect(X - 0.23, Y - 0.46, X + 0.23, Y - 0.39, Colors.TimberEdge);
  Dot(X - 0.17, Y - 0.428, 0.019, Colors.Ink);
  Dot(X + 0.17, Y - 0.428, 0.019, Colors.Ink);
  PreviousX := X;
  PreviousY := Y - 0.40;
  for I := 1 to 7 do
  begin
    PX := X + 0.12 * (1 - 2 * (I mod 2));
    PY := Y - 0.40 + (0.31 - Press) * I / 7;
    Line(PreviousX, PreviousY, PX, PY, 0.042, Colors.Aqua);
    PreviousX := PX;
    PreviousY := PY;
  end;
  Plate(X, Y - Press, 0.21, Slope, Colors.Aqua);
end;

procedure TMarblePainter.CatchTray(X, Y, Slope: Double; Heading: Integer);
begin
  Line(X - Heading * 0.25, Y - 0.37, X + Heading * 0.15, Y - 0.14, 0.084, Colors.Timber);
  Line(X - Heading * 0.21, Y - 0.13, X - Heading * 0.21, Y - 0.40, 0.082, Colors.Timber);
  Plate(X, Y, 0.26, Slope, Colors.Orange);
  Dot(X - Heading * 0.17, Y - 0.19, 0.035, Colors.Brass);
end;

procedure TMarblePainter.Tip(const Cue: TMarbleCue; Age: Double);
var Angle, X, Y: Double;
begin
  X := Cue.Surface.X;
  Y := Cue.Surface.Y;
  Angle := ArcTan(Cue.Slope * Cue.Heading) - 1.03 * (1 - Exp(-Max(0.0, Age) * 29));
  Line(X, Y - 0.024, X + Cue.Heading * 0.33 * Cos(Angle), Y - 0.024 + 0.33 * Sin(Angle), 0.048, Colors.Orange);
  Dot(X, Y - 0.084, 0.058, Colors.TimberEdge);
  Dot(X, Y - 0.084, 0.027, Colors.Ink);
end;

procedure TMarblePainter.Goal(const Cue: TMarbleCue; Age: Double);
var X, Y, Lift: Double; Dir: Integer;
begin
  X := Cue.Center.X;
  Y := Cue.Center.Y - MarbleRadius;
  Dir := Cue.Heading;
  Rect(X - Dir * 0.20, Y - 0.28, X + Dir * 0.86, Y, Colors.Timber);
  Rect(X + Dir * 0.75, Y, X + Dir * 0.86, Y + 0.18, Colors.Brass);
  Line(X - Dir * 0.20, Y - 0.02, X + Dir * 0.86, Y - 0.02, 0.036, Colors.TimberEdge);
  Dot(X + Dir * 0.58, Y - 0.14, 0.048, Colors.Brass);
  Lift := 0.52 * (1 - Exp(-Max(0.0, Age) * 9));
  Line(X + Dir * 0.79, Y + 0.12, X + Dir * 0.79, Y + 0.30 + Lift, 0.040, Colors.Alloy);
  Surface.FillQuad(Screen(X + Dir * 0.81, Y + 0.30 + Lift), Screen(X + Dir * 1.15, Y + 0.27 + Lift),
    Screen(X + Dir * 1.15, Y + 0.12 + Lift), Screen(X + Dir * 0.81, Y + 0.12 + Lift), Colors.Orange);
end;

procedure TMarblePainter.TurnGuide(const Leg: TMarbleLeg);
const Segments = 30;
var I: Integer; Pivot, P, N, Outer, Inner, LastOuter, LastInner: TBallPoint;
begin
  Pivot := Leg.ArcPivot;
  LastOuter := BallPoint(Pivot.X, Pivot.Y + Leg.Radius + MarbleRadius + 0.04);
  LastInner := BallPoint(Pivot.X, Pivot.Y + Leg.Radius - MarbleRadius - 0.04);
  for I := 1 to Segments do
  begin
    P := Leg.ArcPoint(Pi * I / Segments);
    N := BallScale(BallUnit(BallSub(P, Pivot)), MarbleRadius + 0.04);
    Outer := BallAdd(P, N);
    Inner := BallSub(P, N);
    Line(LastOuter.X, LastOuter.Y, Outer.X, Outer.Y, 0.075, Colors.TimberEdge);
    Line(LastInner.X, LastInner.Y, Inner.X, Inner.Y, 0.062, Colors.Alloy);
    if I mod 6 = 0 then
    begin
      P := BallAdd(Outer, BallScale(N, 0.56));
      Line(Outer.X, Outer.Y, P.X, P.Y, 0.053, Colors.Timber);
      Dot(P.X, P.Y, 0.041, Colors.Ink);
      Dot(P.X, P.Y, 0.023, Colors.Brass);
    end;
    LastOuter := Outer;
    LastInner := Inner;
  end;
end;

procedure TMarblePainter.Cradle(const Leg: TMarbleLeg; const P: TBallPoint; Color: TColor);
var Q: TBallPoint; X, Y, Slope, Release: Double; Side: Integer;
begin
  Release := 0;
  if Leg.Rollout then Release := EnsureRange((Time - Leg.Dock + 0.065) / 0.065, 0.0, 1.0);
  Slope := Leg.RailSlope * Release;
  Q := MarbleRailSurface(P, Slope);
  Plate(Q.X, Q.Y, 0.25, Slope, Color);
  for Side := -1 to 1 do
  begin
    if Side = 0 then Continue;
    X := Side * 0.25;
    Y := Q.Y + Slope * X;
    if (Side = Leg.Heading) and (Release > 0) then
      Line(Q.X + X, Y - 0.03, Q.X + X + Side * (0.04 + 0.046 * Release), Y + 0.046 * (1 - Release), 0.043, Color)
    else Line(Q.X + X, Y - 0.03, Q.X + X + Side * 0.04, Y + 0.046, 0.043, Color);
  end;
  Dot(Q.X, Q.Y - 0.068, 0.027, Colors.Ink);
end;

procedure TMarblePainter.Carrier(const Leg: TMarbleLeg; DeviceKind: TMarbleDevice; Parked: Double);
var A, B, P, Q, Previous: TBallPoint; X, Y, Phase, Angle, EntrySide, ExitSide: Double; I: Integer;
begin
  A := Leg.Origin;
  B := Leg.Carriage(Leg.Finish);
  P := Leg.Carriage(Time);
  P.Y := P.Y - Parked;
  if DeviceKind = mdLift then
  begin
    EntrySide := A.X - Leg.Heading * 0.34;
    ExitSide := A.X + Leg.Heading * 0.34;
    Line(EntrySide, A.Y + 0.19, EntrySide, B.Y + 0.22, 0.071, Colors.Timber);
    Line(ExitSide, A.Y - 0.40, ExitSide, B.Y - 0.19, 0.071, Colors.Timber);
    Rect(A.X - 0.42, B.Y + 0.16, A.X + 0.42, B.Y + 0.26, Colors.TimberEdge);
    Line(EntrySide, P.Y - 0.28, EntrySide, B.Y + 0.21, 0.024, Colors.Alloy);
    X := EntrySide;
    Y := B.Y + 0.21;
    Phase := (P.Y - A.Y) * 5.8;
    Dot(X, Y, 0.115, Colors.Ink);
    for I := 0 to 7 do
    begin
      Angle := Phase + I * Pi / 4;
      Line(X + 0.062 * Cos(Angle), Y + 0.062 * Sin(Angle), X + 0.115 * Cos(Angle), Y + 0.115 * Sin(Angle), 0.036, Colors.Brass);
    end;
    Dot(X, Y, 0.056, Colors.Alloy);
    Rect(P.X - 0.34, P.Y - 0.28, P.X + 0.34, P.Y - 0.19, Colors.Aqua);
  end
  else if Leg.Travel.Y < 0 then
  begin
    Previous := A;
    for I := 1 to 12 do
    begin
      Q := Leg.Carriage(Leg.Start + (Leg.Dock - Leg.Start) * I / 12);
      Line(Previous.X - Leg.Heading * 0.18, Previous.Y - 0.35, Q.X - Leg.Heading * 0.18, Q.Y - 0.35, 0.069, Colors.TimberEdge);
      Line(Previous.X - Leg.Heading * 0.32, Previous.Y - 0.47, Q.X - Leg.Heading * 0.32, Q.Y - 0.47, 0.036, Colors.Alloy);
      Previous := Q;
    end;
    Line(P.X - Leg.Heading * 0.18, P.Y - 0.35, P.X, P.Y - 0.17, 0.051, Colors.Brass);
    Dot(P.X - Leg.Heading * 0.18, P.Y - 0.35, 0.055, Colors.Ink);
  end
  else
  begin
    Y := A.Y - MarbleRadius - 0.22;
    Line(A.X - Leg.Heading * 0.27, Y, B.X + Leg.Heading * 0.27, Y, 0.072, Colors.TimberEdge);
    Line(A.X, Y - 0.14, B.X, Y - 0.14, 0.048, Colors.Timber);
    Dot(A.X, Y, 0.056, Colors.Ink);
    Dot(B.X, Y, 0.056, Colors.Ink);
    Dot(P.X - 0.17, Y + 0.038, 0.062, Colors.Alloy);
    Dot(P.X + 0.17, Y + 0.038, 0.062, Colors.Alloy);
    Rect(P.X - 0.25, Y + 0.075, P.X + 0.25, P.Y - MarbleRadius - 0.06, Colors.Timber);
  end;
  Cradle(Leg, P, Colors.Aqua);
end;

procedure TMarblePainter.SwingArm(const Leg: TMarbleLeg);
var Pivot, P, Counter: TBallPoint;
begin
  Pivot := Leg.ArcPivot;
  P := Leg.Carriage(Time);
  Counter := BallAdd(Pivot, BallScale(BallSub(Pivot, P), 0.30));
  Rect(Pivot.X - 0.17, Pivot.Y - 0.13, Pivot.X + 0.17, Pivot.Y + 0.13, Colors.Timber);
  Line(Counter.X, Counter.Y, P.X, P.Y - MarbleRadius - 0.035, 0.076, Colors.TimberEdge);
  Dot(Counter.X, Counter.Y, 0.095, Colors.Orange);
  Dot(Pivot.X, Pivot.Y, 0.10, Colors.Ink);
  Dot(Pivot.X, Pivot.Y, 0.064, Colors.Brass);
  Dot(Pivot.X, Pivot.Y, 0.023, Colors.Ink);
  Cradle(Leg, P, Colors.Brass);
end;

procedure TMarblePainter.Chute(const Leg, Previous: TMarbleLeg);
var X, Inlet, Outlet, GuideEnd, NearSide, FarSide, Angle, FlapLength: Double; A, Hinge: TBallPoint;
begin
  X := Leg.Origin.X;
  Inlet := Leg.Origin.Y;
  Outlet := Leg.Position(Leg.Finish).Y;
  GuideEnd := Outlet + Min(0.82, (Inlet - Outlet) * 0.72);
  NearSide := X - Leg.Heading * (MarbleRadius + 0.043);
  FarSide := X + Leg.Heading * (MarbleRadius + 0.043);
  Line(FarSide, Inlet + 0.17, FarSide, GuideEnd, 0.065, Colors.TimberEdge);
  if GuideEnd < Inlet - 0.24 then Line(NearSide, Inlet - 0.24, NearSide, GuideEnd, 0.060, Colors.Alloy);
  Rect(FarSide, Inlet - 0.08, FarSide + Leg.Heading * 0.19, Inlet + 0.13, Colors.Orange);
  Dot(FarSide + Leg.Heading * 0.125, Inlet + 0.022, 0.036, Colors.Ink);
  Line(FarSide, (Inlet + Outlet) * 0.5, FarSide + Leg.Heading * 0.28, (Inlet + Outlet) * 0.5, 0.066, Colors.Timber);
  Dot(FarSide + Leg.Heading * 0.28, (Inlet + Outlet) * 0.5, 0.043, Colors.Ink);
  Previous.RailSupport(A, Hinge);
  FlapLength := Previous.DropLip * Hypot(1, Previous.Grade);
  Angle := ArcTan(Previous.Grade) - 1.42 * (1 - Exp(-Max(0.0, Time - Leg.Start) * 48));
  Line(Hinge.X, Hinge.Y - 0.024, Hinge.X + Leg.Heading * FlapLength * Cos(Angle),
    Hinge.Y - 0.024 + FlapLength * Sin(Angle), 0.048, Colors.Orange);
  Dot(Hinge.X, Hinge.Y - 0.047, 0.036, Colors.Brass);
end;

procedure TMarblePainter.SharedTap(const Cue: TMarbleCue);
var Age, X, Y, Press, Power: Double;
begin
  Age := Time - Cue.Time;
  Power := Cue.Power;
  if (Time >= Cue.SharedBeat.Time) and ((Time < Cue.Time) or (Cue.SharedBeat.Time > Cue.Time)) then
  begin
    Age := Time - Cue.SharedBeat.Time;
    Power := Cue.SharedBeat.Power;
  end;
  X := Cue.Surface.X;
  Y := Cue.Surface.Y;
  Press := 0.058 * (1 - Exp(-Max(0.0, Age) * 60)) * Exp(-Max(0.0, Age) * 11);
  Rect(X - 0.14, Y - 0.25, X + 0.14, Y - 0.18, Colors.Ink);
  Line(X, Y - 0.21, X, Y - Press, 0.050, Colors.Alloy);
  Plate(X, Y + 0.035 - Press, 0.19, Cue.Slope, Colors.Brass);
  Dot(X, Y - 0.16 - Press * 0.45, 0.042, Colors.Orange);
  ContactPulse(X, Y, Age, Power);
end;

procedure TMarblePainter.Device(Index: Integer);
var Cue: TMarbleCue; Age, X, Y, U: Double;
begin
  Cue := Plan.Cues[Index];
  X := Cue.Surface.X;
  Y := Cue.Surface.Y;
  Age := Time - Cue.Time;
  case Cue.Device of
    mdGate, mdJunctionGate: Gate(Cue, Age);
    mdBell: Bell(X, Y, Age);
    mdSpring: Spring(X, Y, Age, Cue.Slope);
    mdCatch: CatchTray(X, Y, Cue.Slope, Cue.Heading);
    mdTip: Tip(Cue, Age);
    mdGoal: Goal(Cue, Age);
    mdBend: TurnGuide(Plan.Legs[Index + 1]);
    mdLift, mdShuttle: Carrier(Plan.Legs[Index + 1], Cue.Device);
    mdSwing: SwingArm(Plan.Legs[Index + 1]);
    mdChute: Chute(Plan.Legs[Index + 1], Plan.Legs[Index]);
    mdSeesaw: SeesawBoard(Plan.Legs[Index + 1].Board);
    mdSharedTap:
      begin
        if Plan.Legs[Index + 1].Motion = mmCarry then
        begin
          U := EnsureRange((Time - Cue.SharedBeat.Time - 0.19) / Max(0.05, Cue.Time - Cue.SharedBeat.Time - 0.19), 0.0, 1.0);
          Carrier(Plan.Legs[Index + 1], mdLift, 0.34 * (1 - U * U * (3 - 2 * U)));
        end;
        SharedTap(Cue);
        Exit;
      end;
  end;
  ContactPulse(X, Y, Age, Cue.Power);
end;

procedure TMarblePainter.ContactPulse(X, Y, Age, Power: Double);
begin
  if Frame.BackgroundOnly or (Age < 0) or (Age >= 0.14) then Exit;
  Dot(X, Y, 0.035 + 0.30 * Age, Colors.Pearl);
  Dot(X, Y, 0.076 + Age * (0.48 + 0.35 * Power), Colors.PaleBrass, False);
end;

procedure TMarblePainter.TiltingTray(const Bridge: TMarbleBridge; const Trigger: TBallPoint);
var Tip, Hinge, Along, Under, Weight, Guide: TBallPoint; StopX: Double;
begin
  Hinge := Bridge.Hinge;
  Tip := Bridge.Tip(Time);
  Along := BallUnit(BallSub(Hinge, Tip));
  StopX := Bridge.Entry.X;
  if Bridge.Sliding then
  begin
    Along := BallUnit(BallSub(Hinge, Bridge.Entry));
    StopX := StopX - Sign(Along.X) * 0.075;
  end;
  Under := BallPoint(Sign(Along.X) * Along.Y * 0.078, -Abs(Along.X) * 0.078);
  Weight := BallAdd(Hinge, BallScale(Along, 0.16));
  if Bridge.Sliding then
  begin
    Guide := BallAdd(Hinge, BallScale(Along, 0.19));
    Line(Hinge.X, Hinge.Y - 0.095, Guide.X, Guide.Y - 0.095, 0.062, Colors.Alloy);
    Weight := BallAdd(Tip, BallScale(Along, 0.09));
  end;
  Rect(StopX - 0.075, Bridge.Entry.Y - 0.15, StopX + 0.075, Bridge.Entry.Y - 0.056, Colors.Timber);
  Dot(StopX, Bridge.Entry.Y - 0.105, 0.022, Colors.Ink);
  Line(Trigger.X, Trigger.Y, Weight.X, Weight.Y, 0.019, Colors.Brass);
  Line(Hinge.X, Hinge.Y - 0.036, Weight.X, Weight.Y, 0.043, Colors.Alloy);
  if not Bridge.Sliding or (Abs(Tip.X - Hinge.X) > 1E-6) then
  begin
    Surface.FillQuad(Screen(Tip.X, Tip.Y), Screen(Hinge.X, Hinge.Y),
      Screen(Hinge.X + Under.X, Hinge.Y + Under.Y), Screen(Tip.X + Under.X, Tip.Y + Under.Y), Colors.Aqua);
    Line(Tip.X + Under.X * 0.17, Tip.Y + Under.Y * 0.17,
      Hinge.X + Under.X * 0.17, Hinge.Y + Under.Y * 0.17, 0.024, Colors.Pearl);
  end;
  Dot(Weight.X, Weight.Y, 0.048, Colors.Orange);
  Dot(Hinge.X, Hinge.Y - 0.042, 0.053, Colors.Ink);
  Dot(Hinge.X, Hinge.Y - 0.042, 0.031, Colors.Brass);
end;

procedure TMarblePainter.AuxiliaryTrack(const A, B: TBallPoint);
begin
  Line(A.X, A.Y - 0.055, B.X, B.Y - 0.055, 0.10, Colors.Timber);
  Line(A.X, A.Y - 0.012, B.X, B.Y - 0.012, 0.025, Colors.PaleBrass);
end;

procedure TMarblePainter.AuxiliaryBell(const P: TBallPoint; const Beat: TMarbleBeat; Heading: Integer);
var X, Y, Age, Swing: Double;
begin
  X := P.X + Heading * (MarbleAuxRadius + 0.045);
  Y := P.Y + 0.32;
  Age := Time - Beat.Time;
  Swing := Heading * 0.17 * Sin(Max(0.0, Age) * 21) * Exp(-Max(0.0, Age) * 5);
  Rect(X - 0.13, Y, X + 0.13, Y + 0.08, Colors.Timber);
  Dot(X, Y + 0.03, 0.032, Colors.Alloy);
  Line(X, Y, X + Swing * 0.54, Y - 0.14, 0.035, Colors.Alloy);
  X := X + Swing;
  Surface.FillQuad(Screen(X - 0.049, Y - 0.13), Screen(X + 0.049, Y - 0.13),
    Screen(X + 0.105, Y - 0.25), Screen(X - 0.105, Y - 0.25), Colors.Brass);
  Line(X - 0.11, Y - 0.25, X + 0.11, Y - 0.25, 0.034, Colors.PaleBrass);
  Dot(X - Heading * 0.043, Y - 0.29, 0.028, Colors.Orange);
  ContactPulse(P.X, P.Y, Age, Beat.Power);
end;

procedure TMarblePainter.AuxiliaryRocker(const Bridge: TMarbleBridge; const Contact, Along: TBallPoint;
  Age, Throw: Double);
var Sensor, Pivot, Arm, Tail: TBallPoint; H: Integer; Angle: Double;
begin
  H := Sign(Along.X);
  Sensor := BallAdd(Contact, BallScale(Along, MarbleAuxRadius));
  Pivot := BallAdd(Sensor, BallPoint(H * 0.105, 0.18));
  Angle := H * Throw * EnsureRange(Age / 0.095, 0.0, 1.0);
  Arm := BallPoint(-H * 0.105 * Cos(Angle) + 0.18 * Sin(Angle), -H * 0.105 * Sin(Angle) - 0.18 * Cos(Angle));
  Sensor := BallAdd(Pivot, Arm);
  Tail := BallSub(Pivot, BallScale(Arm, 0.42));
  TiltingTray(Bridge, Tail);
  Line(Sensor.X, Sensor.Y, Tail.X, Tail.Y, 0.044, Colors.Orange);
  Dot(Sensor.X, Sensor.Y, 0.032, Colors.Brass);
  Dot(Pivot.X, Pivot.Y, 0.041, Colors.Alloy);
end;

procedure TMarblePainter.AuxiliaryShutter(const Link: TMarbleLink);
var U: Double; Arm: TBallPoint;
begin
  U := Link.Opening(Time);
  Arm := BallAdd(Link.Driver, BallPoint(Link.Heading * 0.10 * U, -0.10 * U));
  Shutter(Link, Arm, 1, U);
  Line(Link.Driver.X, Link.Driver.Y, Arm.X, Arm.Y, 0.043, Colors.Orange);
  Dot(Arm.X, Arm.Y, 0.032, Colors.Brass);
end;

procedure TMarblePainter.Shutter(const Link: TMarbleLink; const Arm: TBallPoint; Size, Opening: Double);
var X, Y, Z, RodX, RodY: Double; Wire: TColor;
begin
  X := Link.Receiver.X;
  Y := Link.Receiver.Y;
  Z := Y + 0.28 * Size * Opening;
  RodX := X + Link.Heading * 0.09 * Size;
  RodY := Z + 0.23 * Size;
  Wire := Colors.Brass;
  if (Opening > 0) and (Opening < 1) then Wire := Colors.PaleBrass;
  Line(Arm.X, Arm.Y, RodX, RodY, 0.021, Wire);
  Rect(X - 0.13 * Size, Y + 0.52 * Size, X + 0.13 * Size, Y + 0.58 * Size, Colors.Timber);
  Line(X - 0.047 * Size, Y + 0.22 * Size, X - 0.047 * Size, Y + 0.54 * Size, 0.022, Colors.Alloy);
  Line(X + 0.047 * Size, Y + 0.22 * Size, X + 0.047 * Size, Y + 0.54 * Size, 0.022, Colors.Alloy);
  Rect(X - 0.035 * Size, Z, X + 0.035 * Size, RodY, Colors.Orange);
  Line(X, Z + 0.07 * Size, X, Z + 0.21 * Size, 0.021, Colors.PaleBrass);
  Line(X, RodY, RodX, RodY, 0.028, Colors.Alloy);
  Dot(RodX, RodY, 0.026 * Size, Colors.Brass);
end;

procedure TMarblePainter.AuxiliaryBridge(const Bridge, Reply: TMarbleBridge; const GateArm: TBallPoint; Opening: Double);
var Aux: TMarbleAuxiliary; Along, Above, A, B, C, D, Latch, Run, Contact, Tail, Rim, Join: TBallPoint;
  H: Integer; Throw: Double;
begin
  Aux := Bridge.Auxiliary;
  Along := BallUnit(BallSub(Aux.Receiver, Aux.Origin));
  H := Sign(Along.X);
  Above := BallPoint(-H * Along.Y, Abs(Along.X));
  A := BallSub(Aux.Origin, BallAdd(BallScale(Above, MarbleAuxRadius), BallScale(Along, 0.13)));
  B := BallSub(Aux.Receiver, BallScale(Above, MarbleAuxRadius));
  if Aux.Duet then
  begin
    Tail := Aux.Position(Aux.Finish);
    if Aux.Merge.Active then Tail := Aux.Merge.LaunchPoint;
    D := Tail;
    if Aux.Crossover then D := Aux.DropOrigin;
    Run := BallUnit(BallSub(D, Aux.Receiver));
    Above := BallScale(BallPoint(-H * Run.Y, Abs(Run.X)), MarbleAuxRadius);
    C := BallSub(Aux.Receiver, Above);
    D := BallSub(D, Above);
    AuxiliaryTrack(B, C);
    if Aux.Crossover then
    begin
      AuxiliaryTrack(C, D);
      Dot(D.X, D.Y - 0.047, 0.030, Colors.Alloy);
      Run := BallUnit(BallSub(Tail, Aux.Landing));
      Above := BallScale(BallPoint(-H * Run.Y, Abs(Run.X)), MarbleAuxRadius);
      C := BallSub(Aux.Landing, Above);
      D := BallSub(Tail, Above);
      Rim := BallSub(C, BallScale(Run, 0.12));
      Line(Rim.X, Rim.Y - 0.045, C.X + H * 0.16, C.Y - 0.057, 0.085, Colors.Alloy);
      Line(Rim.X, Rim.Y - 0.013, C.X + H * 0.16, C.Y - 0.022, 0.024, Colors.Aqua);
    end;
    if Aux.Merge.Active then
    begin
      AuxiliaryTrack(C, D);
      Spring(D.X, D.Y, Time - Aux.Merge.Launch.Time, Run.Y / Run.X);
      ContactPulse(Aux.Merge.LaunchPoint.X, Aux.Merge.LaunchPoint.Y, Time - Aux.Merge.Launch.Time, Aux.Merge.Launch.Power);
      Join := BallSub(Aux.Merge.JoinPoint, BallScale(BallUnit(BallPoint(-H * Aux.Merge.Grade, 1)), MarbleAuxRadius));
      Plate(Join.X, Join.Y, 0.16, H * Aux.Merge.Grade, Colors.Aqua);
    end
    else
    begin
      AuxiliaryTrack(C, BallAdd(D, BallPoint(H * 0.16, 0)));
      Line(D.X + H * 0.115, D.Y, D.X + H * 0.12, D.Y + 0.17, 0.063, Colors.Alloy);
    end;
    AuxiliaryBell(Aux.Position(Aux.Bell.Time), Aux.Bell, H);
  end
  else
  begin
    B := BallAdd(B, BallScale(Along, 0.11));
    Line(B.X, B.Y, B.X + H * 0.035, B.Y + 0.15, 0.050, Colors.Alloy);
  end;
  AuxiliaryTrack(A, B);
  Line(A.X, A.Y, A.X, A.Y + 0.10, 0.044, Colors.Alloy);

  // ゲートが上がると上段の留め金も引き上がる。
  Latch := BallAdd(Aux.Origin, BallScale(Along, MarbleAuxRadius + 0.028));
  Latch.Y := Latch.Y + 0.22 * Opening;
  Line(GateArm.X, GateArm.Y, Latch.X, Latch.Y + 0.13, 0.022, Colors.Brass);
  Line(Latch.X, Latch.Y - 0.035, Latch.X, Latch.Y + 0.13, 0.045, Colors.Orange);
  Dot(Latch.X, Latch.Y + 0.13, 0.030, Colors.PaleBrass);

  // 小球が下端のレバーを押し、反対側の腕が橋を引き上げる。
  Throw := 0.46;
  if Aux.Duet then Throw := 1.57;
  AuxiliaryRocker(Bridge, Aux.Receiver, Along, Time - Aux.Strike, Throw);
  if Aux.Duet then ContactPulse(Aux.Receiver.X, Aux.Receiver.Y, Time - Aux.Strike, Aux.StrikePower);
  if Aux.Reciprocal then
  begin
    AuxiliaryShutter(Aux.AuxGates[0]);
    AuxiliaryShutter(Aux.AuxGates[1]);
    Contact := Aux.Position(Aux.SecondStrike.Time);
    AuxiliaryRocker(Reply, Contact, Run, Time - Aux.SecondStrike.Time, 1.57);
    ContactPulse(Contact.X, Contact.Y, Time - Aux.SecondStrike.Time, Aux.SecondStrike.Power);
  end;
  if not Frame.BackgroundOnly then Sphere(Aux.Position(Time), MarbleAuxRadius, AuxiliaryGlassAsset);
end;

procedure TMarblePainter.PassingTrack(const Aux: TMarbleAuxiliary; const CarrierLeg: TMarbleLeg);
const TongueLength = 0.28;
var Pass: TMarblePass; H: Integer; A, B, Join, Along, Normal, Hinge, Tip, Driver, Cup: TBallPoint;
  U, Angle: Double;
begin
  Pass := Aux.Merge.Pass;
  H := CarrierLeg.Heading;
  Along := BallUnit(BallPoint(H, Pass.Bypass.Grade));
  Normal := BallUnit(BallPoint(-H * Pass.Bypass.Grade, 1));
  A := BallSub(Pass.Bypass.Origin, BallScale(Normal, MarbleAuxRadius));
  B := BallSub(Pass.Rejoin.Origin, BallScale(Normal, MarbleAuxRadius));
  Hinge := BallAdd(A, BallScale(Along, TongueLength));
  Join := BallSub(Pass.Rejoin.Origin, BallScale(BallUnit(BallPoint(-H * Pass.Rejoin.Grade, 1)), MarbleAuxRadius));
  AuxiliaryTrack(Hinge, B);
  Line(B.X, B.Y - 0.015, Join.X, Join.Y - 0.015, 0.045, Colors.PaleBrass);
  Plate(Join.X, Join.Y, 0.12, H * Pass.Rejoin.Grade, Colors.Aqua);

  U := EnsureRange((Time - Pass.SwitchPull) / (Pass.SwitchReady - Pass.SwitchPull), 0.0, 1.0);
  Angle := -1.48 + (ArcTan(Pass.Bypass.Grade) + 1.48) * U * U * (3 - 2 * U);
  Tip := BallSub(Hinge, BallPoint(H * TongueLength * Cos(Angle), TongueLength * Sin(Angle)));
  Driver := CarrierLeg.Carriage(Time);
  Line(Driver.X - H * 0.12, Driver.Y - 0.22, Hinge.X, Hinge.Y - 0.04, 0.018, Colors.Brass);
  Line(Tip.X, Tip.Y - 0.023, Hinge.X, Hinge.Y - 0.023, 0.064, Colors.Aqua);
  Dot(Hinge.X, Hinge.Y - 0.03, 0.037, Colors.Brass);
  ContactPulse(Pass.Bypass.Origin.X, Pass.Bypass.Origin.Y, Time - Pass.Fork.Time, Pass.Fork.Power);

  if not Pass.Counter.Active then
  begin
    Cup := Aux.Position(Aux.Finish);
    CatchTray(Cup.X, Cup.Y - MarbleAuxRadius, 0, H);
  end;
end;

procedure TMarblePainter.InterlockDevice(const Interlock: TMarbleInterlock);
var Latch: TMarbleLatch; Link: TMarbleLink; Arm, Tip, Tail, Pin: TBallPoint;
  X, Y, U, Angle: Double; I: Integer; Color: TColor;
begin
  Link := Interlock.Gate;
  X := Link.Receiver.X;
  Y := Link.Receiver.Y + 1.04;
  Shutter(Link, BallPoint(X, Y - 0.09), 1.65, Interlock.Opening(Time));
  Rect(X - 0.29, Y - 0.09, X + 0.29, Y + 0.12, Colors.Ink);
  Line(X - 0.28, Y - 0.072, X + 0.28, Y - 0.072, 0.038, Colors.TimberEdge);
  for I := 0 to High(Interlock.Inputs) do
  begin
    Latch := Interlock.Inputs[I];
    U := Latch.Amount(Time);
    Angle := Link.Heading * 1.38 * U;
    Arm := BallSub(Latch.Contact, Latch.Pivot);
    Tip := BallAdd(Latch.Pivot, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle),
      Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
    Tail := BallAdd(Latch.Pivot, BallScale(BallSub(Latch.Pivot, Tip), 0.40));
    Pin := BallPoint(X + Link.Heading * (2 * I - 1) * 0.15, Y + 0.18 - 0.125 * U);
    Color := Colors.Orange;
    if I = 1 then Color := Colors.Aqua;
    Line(Tail.X, Tail.Y, Pin.X, Pin.Y + 0.03, 0.018, Color);
    Line(Tip.X, Tip.Y, Tail.X, Tail.Y, 0.047, Color);
    Dot(Latch.Pivot.X, Latch.Pivot.Y, 0.045, Colors.Alloy);
    Dot(Tip.X, Tip.Y, 0.026, Colors.PaleBrass);
    Line(Pin.X, Y + 0.106, Pin.X, Y - 0.04, 0.060, Colors.Alloy);
    Line(Pin.X, Pin.Y - 0.031, Pin.X, Pin.Y + 0.043, 0.045, Color);
    Dot(Pin.X, Pin.Y - 0.025, 0.024, Color);
    if I = 1 then ContactPulse(Latch.Contact.X, Latch.Contact.Y, Time - Latch.Beat.Time, Latch.Beat.Power);
  end;
end;

procedure TMarblePainter.CounterTrack(const Aux: TMarbleAuxiliary);
const Samples = 28;
var Counter: TMarbleCounter; A, B, Pivot, Tip, Tail: TBallPoint; Angle: Double; H, I: Integer;
  function SurfaceAt(U: Double): TBallPoint;
  begin
    Result := BallSub(Counter.Guide(U), BallScale(BallUnit(BallPoint(-Counter.GuideSlope(U), 1)), MarbleAuxRadius));
  end;
begin
  Counter := Aux.Merge.Pass.Counter;
  H := Counter.Gate.Heading;
  A := SurfaceAt(0);
  for I := 1 to Samples do
  begin
    B := SurfaceAt(I / Samples);
    AuxiliaryTrack(A, B);
    A := B;
  end;
  Plate(A.X, A.Y, 0.13, H * Counter.Rejoin.Grade, Colors.Aqua);
  if Counter.Interlock.Active then InterlockDevice(Counter.Interlock)
  else AuxiliaryBell(Aux.Position(Counter.DetourBeat.Time), Counter.DetourBeat, H);

  // 小球の進路に出たレバーが、直線側のシャッターを引き上げる。
  Pivot := Counter.Gate.Driver;
  Angle := H * 1.38 * EnsureRange((Time - Counter.Start) / 0.13, 0.0, 1.0);
  Tip := BallAdd(Pivot, BallPoint(-H * 0.083 * Cos(Angle) + 0.23 * Sin(Angle),
    -H * 0.083 * Sin(Angle) - 0.23 * Cos(Angle)));
  Tail := BallAdd(Pivot, BallScale(BallSub(Pivot, Tip), 0.38));
  Shutter(Counter.Gate, Tail, 1.65, Counter.Gate.Opening(Time));
  Line(Tip.X, Tip.Y, Tail.X, Tail.Y, 0.042, Colors.Orange);
  Dot(Pivot.X, Pivot.Y, 0.049, Colors.Alloy);
  Dot(Tip.X, Tip.Y, 0.031, Colors.Brass);
end;

procedure TMarblePainter.SeesawBoard(const Board: TMarbleBoard);
var A, B, C, D, PadA, PadB: TBallPoint; X, Y: Double;
begin
  X := Board.Pivot.X;
  Y := Board.Pivot.Y;
  Surface.FillQuad(Screen(X - 0.07, Y - 0.08), Screen(X + 0.07, Y - 0.08),
    Screen(X + 0.25, Y - 0.59), Screen(X - 0.25, Y - 0.59), Colors.Timber);
  Rect(X - 0.30, Y - 0.64, X + 0.30, Y - 0.58, Colors.TimberEdge);
  A := Board.PointAt(Time, Board.Rear, 0);
  B := Board.PointAt(Time, Board.Front, 0);
  C := Board.PointAt(Time, Board.Front, -0.115);
  D := Board.PointAt(Time, Board.Rear, -0.115);
  Surface.FillQuad(Screen(A.X, A.Y), Screen(B.X, B.Y), Screen(C.X, C.Y), Screen(D.X, D.Y), Colors.Timber);
  Line(A.X, A.Y - 0.02, B.X, B.Y - 0.02, 0.041, Colors.Aqua);
  PadA := Board.PointAt(Time, Board.LoadPoint - 0.09, 0.026);
  PadB := Board.PointAt(Time, Board.Front - 0.05, 0.026);
  Line(PadA.X, PadA.Y, PadB.X, PadB.Y, 0.051, Colors.Orange);
  Dot(X, Y - 0.055, 0.116, Colors.Ink);
  Dot(X, Y - 0.055, 0.081, Colors.Brass);
  Dot(X, Y - 0.055, 0.036, Colors.Alloy);
end;

procedure TMarblePainter.ReceivingTray(const Saw: TMarbleSeesaw);
var Latch: TMarbleLatch; Arm, Tip, Tail, Socket, Pin, Rear, Nose, Rim, Axle: TBallPoint;
  Push, Angle, Stop, RimHeight: Double; H: Integer; RodColor: TColor;
begin
  H := Saw.Board.Heading;
  Latch := Saw.TrayRelease.Lever;
  Push := Latch.Amount(Time);
  Angle := H * 1.44 * Push;
  Arm := BallSub(Latch.Contact, Latch.Pivot);
  Tip := BallAdd(Latch.Pivot, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle),
    Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
  Tail := BallAdd(Latch.Pivot, BallScale(BallSub(Latch.Pivot, Tip), 0.48));

  // ドック側の留め金を押し下げると、受け皿の軸が回る。
  Socket := Saw.TrayPoint(Saw.WeightLift.Dock, MarbleTrayRear, 0);
  Socket := BallAdd(Socket, BallPoint(-H * 0.05, -0.115));
  Pin := BallAdd(Socket, BallPoint(0, 0.115 - 0.090 * Push));
  RodColor := Colors.Brass;
  if Push > 0 then RodColor := Colors.Orange;
  Line(Tail.X, Tail.Y, Pin.X, Pin.Y - 0.03, 0.026, Colors.Ink);
  Line(Tail.X, Tail.Y, Pin.X, Pin.Y - 0.03, 0.014, RodColor);
  Line(Socket.X, Socket.Y - 0.085, Socket.X, Socket.Y + 0.045, 0.071, Colors.TimberEdge);
  Line(Pin.X, Pin.Y - 0.06, Pin.X, Pin.Y, 0.043, RodColor);
  Line(Pin.X, Pin.Y, Pin.X + H * 0.075, Pin.Y + 0.035, 0.036, RodColor);

  Line(Latch.Pivot.X, Latch.Pivot.Y, Latch.Pivot.X + H * 0.20, Latch.Pivot.Y + 0.12, 0.069, Colors.TimberEdge);
  Line(Tip.X, Tip.Y, Tail.X, Tail.Y, 0.054, Colors.Orange);
  Dot(Tip.X, Tip.Y, 0.031, Colors.PaleBrass);
  Dot(Latch.Pivot.X, Latch.Pivot.Y, 0.055, Colors.Ink);
  Dot(Latch.Pivot.X, Latch.Pivot.Y, 0.034, Colors.Alloy);

  Rear := Saw.TrayPoint(Time, MarbleTrayRear, 0);
  Nose := Saw.TrayPoint(Time, MarbleTrayNose, 0);
  Axle := Saw.TrayPoint(Time, 0, -0.040);
  Line(Rear.X, Rear.Y - 0.038, Nose.X, Nose.Y - 0.038, 0.086, Colors.TimberEdge);
  Line(Rear.X, Rear.Y, Nose.X, Nose.Y, 0.039, Colors.Aqua);
  Rim := Saw.TrayPoint(Time, MarbleTrayRear - 0.025, 0.066);
  Line(Rear.X, Rear.Y, Rim.X, Rim.Y, 0.043, Colors.Aqua);
  Stop := EnsureRange((Time - Saw.TrayRelease.Start) / 0.10, 0.0, 1.0);
  RimHeight := 0.15 - 0.16 * Stop;
  Rim := Saw.TrayPoint(Time, MarbleTrayNose + 0.075 * Stop, RimHeight);
  Line(Nose.X, Nose.Y, Rim.X, Rim.Y, 0.043, Colors.Aqua);
  Dot(Axle.X, Axle.Y, 0.038, Colors.Ink);
  Dot(Axle.X, Axle.Y, 0.022, Colors.PaleBrass);
end;

procedure TMarblePainter.WeightedLift(const Saw: TMarbleSeesaw);
var Lift: TMarbleWeightLift; Deck, Pan, MainFloor, SmallFloor: TBallPoint;
  DeckCable, PanCable, Beam, PanBottom, MainTop, Release, Ramp, U: Double; H: Integer;
begin
  Lift := Saw.WeightLift;
  H := Saw.Board.Heading;
  Deck := Lift.Carriage(Time);
  Pan := Saw.Pan(Time);
  MainFloor := MarbleRailSurface(Deck, H * MarbleSeesawExitGrade);
  if Saw.TrayRelease.Active then SmallFloor := Saw.TrayPoint(Time, 0, 0)
  else SmallFloor := BallSub(Pan, BallScale(BallUnit(BallPoint(-H * Saw.CatchRail.Grade, 1)), MarbleAuxRadius));
  DeckCable := MainFloor.X + H * 0.23;
  PanCable := SmallFloor.X - H * 0.23;
  Beam := Saw.Landing.Y + 0.25;
  PanBottom := Saw.Landing.Y - Lift.Rise - 0.36;
  MainTop := Lift.Load.Y + Lift.Rise + 0.10;

  // ガイドの中を二つの台が動き、上の滑車で同じロープを引く。
  Line(PanCable, PanBottom, PanCable, Beam, 0.089, Colors.Timber);
  Line(DeckCable, Lift.Load.Y - 0.31, DeckCable, Beam, 0.089, Colors.Timber);
  Line(PanCable, Beam + 0.045, DeckCable, Beam + 0.045, 0.13, Colors.Timber);
  Line(PanCable, Beam + 0.09, DeckCable, Beam + 0.09, 0.023, Colors.TimberEdge);
  Line(PanCable, PanBottom, PanCable, Saw.Landing.Y + 0.03, 0.033, Colors.Alloy);
  Line(DeckCable, Lift.Load.Y - 0.25, DeckCable, MainTop, 0.033, Colors.Alloy);
  Line(PanCable, SmallFloor.Y - 0.06, PanCable, Beam, 0.023, Colors.PaleBrass);
  Line(DeckCable, MainFloor.Y - 0.06, DeckCable, Beam, 0.023, Colors.PaleBrass);
  Line(PanCable, Beam + 0.062, DeckCable, Beam + 0.062, 0.023, Colors.PaleBrass);
  Dot(PanCable, Beam, 0.081, Colors.Ink);
  Dot(DeckCable, Beam, 0.081, Colors.Ink);
  Dot(PanCable, Beam, 0.060, Colors.Brass);
  Dot(DeckCable, Beam, 0.060, Colors.Brass);
  Dot(PanCable, Beam, 0.023, Colors.Alloy);
  Dot(DeckCable, Beam, 0.023, Colors.Alloy);

  Release := EnsureRange((Lift.Dock - Time) / 0.055, 0.0, 1.0);
  Rect(PanCable - 0.068, SmallFloor.Y - 0.23, PanCable + 0.068, SmallFloor.Y - 0.065, Colors.Brass);
  Line(PanCable - 0.041, SmallFloor.Y - 0.11, PanCable + 0.041, SmallFloor.Y - 0.11, 0.023, Colors.PaleBrass);
  Line(MainFloor.X, MainFloor.Y - 0.064, DeckCable, MainFloor.Y - 0.064, 0.081, Colors.TimberEdge);
  Plate(MainFloor.X, MainFloor.Y, 0.16, H * MarbleSeesawExitGrade, Colors.Brass);
  if Lift.Ramp > 0 then
  begin
    U := EnsureRange((Time - Lift.Dock + 0.10) / 0.10, 0.0, 1.0);
    Ramp := 0.09 + (Lift.Ramp - 0.09) * Sqr(U) * (3 - 2 * U);
    Line(MainFloor.X + H * 0.055, MainFloor.Y + MarbleSeesawExitGrade * 0.055 - 0.022,
      MainFloor.X + H * Ramp, MainFloor.Y + MarbleSeesawExitGrade * Ramp - 0.022, 0.062, Colors.Alloy);
    Line(MainFloor.X + H * 0.055, MainFloor.Y + MarbleSeesawExitGrade * 0.055,
      MainFloor.X + H * Ramp, MainFloor.Y + MarbleSeesawExitGrade * Ramp, 0.022, Colors.PaleBrass);
  end;
  Line(MainFloor.X + H * 0.10, MainFloor.Y - 0.03,
    MainFloor.X + H * (0.19 - 0.036 * Release), MainFloor.Y - 0.058 + 0.15 * Release, 0.038, Colors.Orange);
  Dot(DeckCable, MainFloor.Y - 0.064, 0.041, Colors.Alloy);

  Line(PanCable, SmallFloor.Y - 0.055, SmallFloor.X, SmallFloor.Y - 0.055, 0.067, Colors.TimberEdge);
  if Saw.TrayRelease.Active then ReceivingTray(Saw)
  else
  begin
    Plate(SmallFloor.X, SmallFloor.Y, 0.155, H * Saw.CatchRail.Grade, Colors.Aqua);
    Line(SmallFloor.X - H * 0.14, SmallFloor.Y, SmallFloor.X - H * 0.19, SmallFloor.Y + 0.065, 0.037, Colors.Aqua);
    Line(SmallFloor.X + H * 0.10, SmallFloor.Y - 0.025, SmallFloor.X + H * (0.17 - 0.038 * Release),
      SmallFloor.Y - 0.023 + 0.16 * Release, 0.046, Colors.Aqua);
  end;
  Dot(PanCable, SmallFloor.Y - 0.055, 0.035, Colors.Brass);
  ContactPulse(SmallFloor.X, SmallFloor.Y, Time - Saw.Trigger.Time, Saw.Trigger.Power);
end;

procedure TMarblePainter.JunctionDevice(const Saw: TMarbleSeesaw; const Leg: TMarbleLeg);
var Latch: TMarbleLatch; Joint, RailTip, Pin, Arm, LeverTip, Tail: TBallPoint; Angle: Double; H: Integer;
begin
  H := Leg.Heading;
  Latch := Saw.SwitchLever;
  Joint := Leg.Junction.Pivot(H);
  RailTip := Leg.Junction.Tip(Time, H);
  Pin := BallAdd(Joint, BallScale(BallSub(RailTip, Joint), 0.50));
  Pin.Y := Pin.Y - 0.055;
  Angle := H * 1.45 * Latch.Amount(Time);
  Arm := BallSub(Latch.Contact, Latch.Pivot);
  LeverTip := BallAdd(Latch.Pivot, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle),
    Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
  Tail := BallAdd(Latch.Pivot, BallScale(BallSub(Latch.Pivot, LeverTip), 0.43));

  Line(Tail.X, Tail.Y, Pin.X, Pin.Y, 0.032, Colors.Ink);
  Line(Tail.X, Tail.Y, Pin.X, Pin.Y, 0.020, Colors.Orange);
  Line(Joint.X, Joint.Y - 0.035, RailTip.X, RailTip.Y - 0.035, 0.10, Colors.Ink);
  Line(Joint.X, Joint.Y - 0.031, RailTip.X, RailTip.Y - 0.031, 0.069, Colors.Brass);
  Line(Joint.X, Joint.Y, RailTip.X, RailTip.Y, 0.030, Colors.PaleBrass);
  Dot(Pin.X, Pin.Y, 0.030, Colors.Alloy);
  Dot(Joint.X, Joint.Y - 0.036, 0.068, Colors.Ink);
  Dot(Joint.X, Joint.Y - 0.036, 0.047, Colors.Alloy);
  Dot(Joint.X, Joint.Y - 0.036, 0.021, Colors.Brass);

  Line(Latch.Pivot.X, Latch.Pivot.Y, Latch.Pivot.X + H * 0.14, Latch.Pivot.Y + 0.10, 0.064, Colors.TimberEdge);
  Line(LeverTip.X, LeverTip.Y, Tail.X, Tail.Y, 0.043, Colors.Orange);
  Dot(Latch.Pivot.X, Latch.Pivot.Y, 0.045, Colors.Alloy);
  Dot(LeverTip.X, LeverTip.Y, 0.027, Colors.PaleBrass);
  ContactPulse(Latch.Contact.X, Latch.Contact.Y, Time - Latch.Beat.Time, Latch.Beat.Power);
end;

procedure TMarblePainter.WheelBell(const P: TBallPoint; const Beat: TMarbleBeat; H: Integer);
var Pivot, Tip, Paddle, BellPivot, Cam: TBallPoint; Age, U, Turn, Angle, Swing: Double; I: Integer;
begin
  Age := Time - Beat.Time;
  U := EnsureRange(Age / 0.28, 0.0, 1.0);
  Turn := 1.76 * (1 - Sqr(1 - U));
  Pivot := BallAdd(P, BallPoint(H * MarbleAuxRadius, 0.18));
  BellPivot := BallAdd(Pivot, BallPoint(H * 0.20, 0.27));
  Line(Pivot.X, Pivot.Y + 0.21, Pivot.X, Pivot.Y, 0.060, Colors.TimberEdge);
  Line(Pivot.X - H * 0.11, Pivot.Y + 0.22, BellPivot.X + H * 0.10, Pivot.Y + 0.22, 0.069, Colors.Timber);
  for I := 0 to 3 do
  begin
    Angle := -Pi / 2 + I * Pi / 2 + Turn;
    Tip := BallAdd(Pivot, BallPoint(H * Cos(Angle) * 0.18, Sin(Angle) * 0.18));
    Paddle := BallPoint(H * -Sin(Angle) * 0.048, Cos(Angle) * 0.048);
    Line(Pivot.X, Pivot.Y, Tip.X, Tip.Y, 0.042, Colors.Alloy);
    Line(Tip.X - Paddle.X, Tip.Y - Paddle.Y, Tip.X + Paddle.X, Tip.Y + Paddle.Y, 0.042, Colors.Aqua);
  end;
  Dot(Pivot.X, Pivot.Y, 0.052, Colors.Ink);
  Dot(Pivot.X, Pivot.Y, 0.029, Colors.Brass);
  Swing := H * 0.074 * Sin(Max(0.0, Age) * 26) * Exp(-Max(0.0, Age) * 5);
  Cam := BallAdd(Pivot, BallPoint(H * 0.052 * Sin(Turn), 0.052 * Cos(Turn)));
  Line(Cam.X, Cam.Y, BellPivot.X + Swing - H * 0.04, BellPivot.Y - 0.205, 0.022, Colors.Orange);
  Dot(Cam.X, Cam.Y, 0.024, Colors.PaleBrass);
  Line(BellPivot.X, BellPivot.Y, BellPivot.X + Swing, BellPivot.Y - 0.10, 0.033, Colors.Alloy);
  Surface.FillQuad(Screen(BellPivot.X + Swing - 0.035, BellPivot.Y - 0.08),
    Screen(BellPivot.X + Swing + 0.035, BellPivot.Y - 0.08),
    Screen(BellPivot.X + Swing + 0.080, BellPivot.Y - 0.19),
    Screen(BellPivot.X + Swing - 0.080, BellPivot.Y - 0.19), Colors.Brass);
  Dot(BellPivot.X + Swing, BellPivot.Y - 0.20, 0.028, Colors.Orange);
  ContactPulse(P.X + H * MarbleAuxRadius, P.Y, Age, Beat.Power);
end;

procedure TMarblePainter.SeesawTrack(const Aux: TMarbleAuxiliary; const JunctionLeg: TMarbleLeg);
const CurveSamples = 9;
var Saw: TMarbleSeesaw; A, B, PointOnRail, Normal, CupA, CupB, Arm, Tip, Tail: TBallPoint;
  H, I: Integer; Distance, Angle, Opening, T, Grade: Double;

  function RunSurface(AtTime: Double): TBallPoint;
  var N: TBallPoint;
  begin
    N := BallScale(BallUnit(BallPoint(-H * Saw.RunGrade(AtTime), 1)), MarbleAuxRadius);
    Result := BallSub(Saw.RunPosition(AtTime), N);
  end;

begin
  Saw := Aux.Merge.Pass.Counter.Seesaw;
  H := Saw.Board.Heading;
  Distance := Saw.Seat + Saw.SeatSpeed * (EnsureRange(Time, Saw.Board.Start, Saw.Board.Stop) - Saw.Board.Start);
  CupA := Saw.Board.PointAt(Time, Distance - 0.115, 0.025);
  CupB := Saw.Board.PointAt(Time, Distance + 0.115, 0.025);
  Line(CupA.X, CupA.Y, CupB.X, CupB.Y, 0.048, Colors.PaleBrass);
  Dot(CupA.X, CupA.Y + 0.035, 0.028, Colors.Brass);
  Dot(CupB.X, CupB.Y + 0.035, 0.028, Colors.Brass);

  Normal := BallScale(BallUnit(BallPoint(-H * Saw.CatchRail.Grade, 1)), MarbleAuxRadius);
  A := BallSub(Saw.CatchRail.Origin, Normal);
  if Saw.ExitRail.Start > 0 then
  begin
    PointOnRail := A;
    for I := 0 to CurveSamples do
    begin
      T := Saw.ExitCurveStart + (Saw.ExitRail.Start - Saw.ExitCurveStart) * I / CurveSamples;
      B := RunSurface(T);
      AuxiliaryTrack(PointOnRail, B);
      PointOnRail := B;
    end;
  end
  else PointOnRail := A;
  Grade := Saw.RunGrade(Aux.Finish);
  Normal := BallScale(BallUnit(BallPoint(-H * Grade, 1)), MarbleAuxRadius);
  B := BallSub(Aux.Position(Aux.Finish), Normal);
  if Saw.TrayRelease.Active then AuxiliaryTrack(PointOnRail, BallAdd(B, BallPoint(H * 0.13, Grade * 0.13)))
  else AuxiliaryTrack(PointOnRail, BallAdd(B, BallPoint(H * 0.13, 0)));
  if not Saw.WeightLift.Active then Plate(A.X, A.Y, 0.14, H * Saw.CatchRail.Grade, Colors.Aqua);
  Line(B.X + H * 0.095, B.Y, B.X + H * 0.095, B.Y + 0.13, 0.041, Colors.Alloy);
  if JunctionLeg.Junction.Active and (Saw.SwitchLever.Beat.Time > 0) then JunctionDevice(Saw, JunctionLeg)
  else AuxiliaryBell(Aux.Position(Saw.Bell.Time), Saw.Bell, H);
  if Saw.ExitGate.Kind <> mlNone then
  begin
    Opening := Saw.ExitGate.Opening(Time);
    Arm := BallAdd(Saw.ExitGate.Driver, BallPoint(H * 0.10 * Opening, -0.10 * Opening));
    Shutter(Saw.ExitGate, Arm, 1.22, Opening);
    Line(Saw.ExitGate.Driver.X, Saw.ExitGate.Driver.Y, Arm.X, Arm.Y, 0.042, Colors.Orange);
    WheelBell(Aux.Position(Saw.ExitBell.Time), Saw.ExitBell, H);
  end;

  if Saw.WeightLift.Active then
  begin
    WeightedLift(Saw);
    Exit;
  end;
  Arm := BallSub(Saw.LeverContact, Saw.Gate.Driver);
  Angle := H * 1.43 * EnsureRange((Time - Saw.Trigger.Time) / 0.12, 0.0, 1.0);
  Tip := BallAdd(Saw.Gate.Driver, BallPoint(Arm.X * Cos(Angle) - Arm.Y * Sin(Angle), Arm.X * Sin(Angle) + Arm.Y * Cos(Angle)));
  Tail := BallAdd(Saw.Gate.Driver, BallScale(BallSub(Saw.Gate.Driver, Tip), 0.42));
  Shutter(Saw.Gate, Tail, 1.60, Saw.Gate.Opening(Time));
  Line(Tip.X, Tip.Y, Tail.X, Tail.Y, 0.047, Colors.Orange);
  Dot(Saw.Gate.Driver.X, Saw.Gate.Driver.Y, 0.045, Colors.Alloy);
  Dot(Tip.X, Tip.Y, 0.029, Colors.Brass);
  ContactPulse(Saw.LeverContact.X, Saw.LeverContact.Y, Time - Saw.Trigger.Time, Saw.Trigger.Power);
end;

procedure TMarblePainter.Linkage(const Link: TMarbleLink);
var U, X, Y, Z, DriverX, DriverY, RodY, HatchU: Double; H: Integer;
  Bridge, Reply, Hatch: TMarbleBridge; GateArm: TBallPoint; Cue: TMarbleCue;
begin
  if Link.Kind = mlNone then Exit;
  U := Link.Opening(Time);
  H := Link.Heading;
  X := Link.Receiver.X;
  Y := Link.Receiver.Y;
  DriverX := Link.Driver.X + H * 0.10 * U;
  DriverY := Link.Driver.Y - 0.10 * U;
  if Link.Kind = mlShutter then
  begin
    Z := Y + 0.47 * U;
    RodY := Z + 0.42;
    Line(DriverX, DriverY, X + H * 0.13, RodY, 0.022, Colors.Brass);
    Rect(X - 0.19, Y + 0.89, X + 0.19, Y + 0.97, Colors.Timber);
    Line(X - 0.068, Y + 0.42, X - 0.068, Y + 0.91, 0.030, Colors.Alloy);
    Line(X + 0.068, Y + 0.42, X + 0.068, Y + 0.91, 0.030, Colors.Alloy);
    Rect(X - 0.052, Z - 0.01, X + 0.052, Z + 0.42, Colors.Orange);
    Line(X, Z + 0.09, X, Z + 0.40, 0.028, Colors.PaleBrass);
    Dot(X + H * 0.13, RodY, 0.036, Colors.Brass);
    Line(X, RodY, X + H * 0.13, RodY, 0.035, Colors.Alloy);
    Bridge := Plan.Legs[Link.Target + 1].Bridge;
    GateArm := BallPoint(X + H * 0.13, RodY);
    if Bridge.Auxiliary.Active then
    begin
      Reply := Default(TMarbleBridge);
      if Bridge.Auxiliary.Reciprocal then Reply := Plan.Legs[Link.Target + 2].Bridge;
      if Bridge.Auxiliary.Merge.Pass.Active then PassingTrack(Bridge.Auxiliary, Plan.Legs[Link.Target + 7]);
      if Bridge.Auxiliary.Merge.Pass.Counter.Active then CounterTrack(Bridge.Auxiliary);
      if Bridge.Auxiliary.Merge.Pass.Counter.Seesaw.Active then
        SeesawTrack(Bridge.Auxiliary, Plan.Legs[Link.Target + 14]);
      AuxiliaryBridge(Bridge, Reply, GateArm, U);
      if Bridge.Auxiliary.Merge.Active then
      begin
        Hatch := Plan.Legs[Link.Target + 3].Bridge;
        Cue := Plan.Cues[Link.Target + 3];
        HatchU := EnsureRange((Time - Hatch.Pull) / (Hatch.Ready - Hatch.Pull), 0.0, 1.0);
        TiltingTray(Hatch, BallPoint(Cue.Surface.X + H * (0.025 + 0.10 * HatchU), Cue.Center.Y + 0.48 - 0.10 * HatchU));
      end;
    end
    else if Bridge.Active then TiltingTray(Bridge, GateArm);
  end
  else
  begin
    X := X + H * 0.15 * U;
    Line(DriverX, DriverY, X, Y, 0.025, Colors.Brass);
    Line(X + H * 0.12, Y + 0.03, X - H * 0.10, Y + 0.03, 0.065, Colors.Orange);
    Line(X - H * 0.10, Y + 0.03, X - H * 0.10, Y - 0.085, 0.045, Colors.Orange);
    Dot(X + H * 0.10, Y + 0.03, 0.034, Colors.Brass);
  end;
  Line(Link.Driver.X, Link.Driver.Y, DriverX, DriverY, 0.043, Colors.Orange);
  Dot(Link.Driver.X, Link.Driver.Y, 0.028, Colors.Alloy);
  Dot(DriverX, DriverY, 0.036, Colors.Brass);
end;

procedure TMarblePainter.Sphere(const P: TBallPoint; Radius: Double; Asset: Integer);
var Center: TPointF; Size: Integer;
begin
  Center := Screen(P.X, P.Y);
  Size := 2 * Max(1, Round(Radius * Scale / 0.98));
  Surface.DrawAsset(Asset, Point(Round(Center.X), Round(Center.Y)), Size, Size, 1, True);
end;

procedure TMarblePainter.Ball(const P: TBallPoint);
var Asset: Integer;
begin
  Asset := Ord(BallStyle) * BallPhases +
    (Round(Frac(Plan.Rotation(Time) / (2 * Pi)) * BallPhases) + BallPhases) mod BallPhases;
  Sphere(P, MarbleRadius, Asset);
end;

function TMarblePainter.SectionVisible(const Section: TMarbleSection): Boolean;
begin
  Result := (Section.Left <= Left + Width + 1.25) and (Section.Right >= Left - 1.25) and
    (Section.Top >= Top - Height - 1.25) and (Section.Bottom <= Top + 1.25);
end;

procedure TMarblePainter.Course(const P: TBallPoint);
var Section: TMarbleSection; I: Integer; Leg, Previous: TMarbleLeg; A, B, JoinA, JoinB: TBallPoint;
begin
  if Length(Plan.Legs) = 0 then
  begin
    Rail(BallPoint(P.X - 1.2, P.Y - MarbleRadius), BallPoint(P.X + 0.3, P.Y - MarbleRadius));
    Exit;
  end;
  // 折り返した先の仕掛けも、画面内にあれば先に見せる。
  for Section in Plan.Sections do
    if SectionVisible(Section) then
      for I := Section.First to Section.Last do
      begin
        Leg := Plan.Legs[I];
        if Leg.Motion = mmSeesaw then
        begin
          Leg.RailSupport(A, B);
          JoinA := Leg.Board.PointAt(Leg.Dock, Leg.Board.Front, 0);
          Line(JoinA.X, JoinA.Y - 0.021, A.X, A.Y - 0.021, 0.037, Colors.TimberEdge);
          Rail(A, B);
          if Leg.HasWeightLift and Leg.LiftRailSupport(A, B) then Rail(A, B);
          Continue;
        end;
        if Leg.Motion <> mmRail then Continue;
        Leg.RailSupport(A, B);
        if I = 0 then A := BallAdd(A, BallPoint(-0.65, -0.65 * Leg.RailSlope));
        if (Plan.Version >= 3) and (I > 0) then
        begin
          Previous := Plan.Legs[I - 1];
          if Previous.Rollout then
            Rail(MarbleRailSurface(Previous.Carriage(Previous.Dock), Previous.RailSlope), A)
          else if (Previous.Motion in [mmRail, mmSeesaw]) and (Previous.DropLip = 0) and (Leg.EntryGap = 0) then
          begin
            if Previous.Junction.Active then Previous.BranchRailSupport(JoinA, JoinB)
            else if Previous.HasWeightLift then Previous.LiftRailSupport(JoinA, JoinB)
            else Previous.RailSupport(JoinA, JoinB);
            Line(JoinB.X, JoinB.Y - 0.02, A.X, A.Y - 0.02, 0.042, Colors.TimberEdge);
          end;
        end;
        if Leg.Junction.Active then
        begin
          Rail(A, B);
          Leg.BranchRailSupport(JoinA, JoinB);
          Line(B.X, B.Y - 0.022, JoinA.X, JoinA.Y - 0.022, 0.052, Colors.TimberEdge);
          Rail(Leg.Junction.Tip(Leg.Junction.Ready, Leg.Heading), JoinB);
          Leg.Junction.Spur(A, B, Leg.Heading);
          Rail(A, B);
          Dot(B.X, B.Y, 0.056, Colors.Alloy);
          Continue;
        end;
        if Leg.Bridge.Active then
        begin
          Rail(A, Leg.Bridge.Entry);
          Rail(Leg.Bridge.Hinge, B);
        end
        else Rail(A, B);
      end;
  for Section in Plan.Sections do
    if SectionVisible(Section) then
      for I := Max(1, Section.First) to Section.Last do Device(I - 1);
  if Length(Plan.Links) > 0 then
    for Section in Plan.Sections do
      if SectionVisible(Section) then
        for I := Max(1, Section.First) to Section.Last do Linkage(Plan.Links[I - 1]);
end;

procedure TMarblePainter.Paint;
var P, Camera: TBallPoint; CenterX: Double;
begin
  Time := EnsureRange(Frame.Time, 0.0, Plan.EndTime);
  Scale := Max(1.0, Min(Frame.Height / 3.75, Frame.Width / 5.8));
  Width := Frame.Width / Scale;
  Height := Frame.Height / Scale;
  P := Plan.Position(Time);
  Camera := Plan.CameraTarget(Time);
  CenterX := 0.40;
  if Plan.Version >= 2 then CenterX := 0.50;
  Left := Camera.X - Width * CenterX;
  Top := Camera.Y + Height * 0.54;
  Colors := StagePalettes[StageStyle];
  Backboard;
  Course(P);
  if not Frame.BackgroundOnly then Ball(P);
end;

destructor TMarbleAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TMarbleAnimation.SetReference(const Ref: TRhythmPlanRef);
begin
  FRef := Ref;
end;

procedure TMarbleAnimation.Prepare(const Frame: TAnimationFrame);
var Key: string;
begin
  Key := FRef.Key + '|' + FRef.Digest + '|' + IntToStr(Frame.Direction);
  if Audio <> nil then Key := Key + '|' + Audio.Key else Key := Key + '|none';
  if Key = FAttempt then Exit;
  FAttempt := Key;
  FreeAndNil(FPlan);
  FError := '';
  if Audio = nil then Exit;
  try
    FPlan := LoadMarblePlan(FRef, Audio, Frame.Direction);
  except
    on E: Exception do FError := E.Message;
  end;
end;

procedure TMarbleAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
var Painter: TMarblePainter;
begin
  if FPlan = nil then Exit;
  Painter.Surface := Surface;
  Painter.Frame := Frame;
  Painter.Plan := FPlan;
  Painter.BallStyle := BallStyle;
  Painter.StageStyle := StageStyle;
  Painter.Paint;
end;

function TMarbleAnimation.Notice: string;
begin
  Result := FError;
end;

function TMarbleAnimation.GoalTime: Double;
begin
  Result := 0; // 最後の球受けがこの演出の終点。
end;

function TMarbleAnimation.Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
var I: Integer; Age: Double; Beat: TMarbleBeat;
begin
  Result := True;
  Value := Default(TEqualizerActivity);
  if FPlan = nil then Exit;
  I := FPlan.BeatAt(Time, Beat);
  if I < 0 then Exit;
  Age := Time - Beat.Time;
  if Age > 0.65 then Exit;
  Value.Valid := True;
  Value.Hit := I;
  Value.Pulse := (0.6 + 0.4 * Beat.Power) * Exp(-Age * 10);
  Value.Energy := (0.35 + 0.65 * Beat.Power) * Exp(-Age * 4);
end;

end.
