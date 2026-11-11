unit RhythmMarbleStage;
// 世界座標で渡された走路と可動部を、ステージ固有の材質と構造で描く。
interface

uses System.Types, Vcl.Graphics, RhythmStyles, RhythmRenderSurface, RhythmBallGeometry;

type
  TMarblePalette = record
    Ink, Timber, TimberEdge: TColor; // 装置の影、胴体、縁。
    Brass, PaleBrass, Alloy: TColor; // 軸、ハイライト、補強材。
    Aqua, Orange, Pearl: TColor;     // 可動板、入力部、強い反射。
    TopColor, BottomColor: TColor;   // 背景の上端と下端。
    Grid, Pin, PinLight: TColor;     // 背景の建材、影、反射。
  end;

  TMarbleStagePainter = record
    Surface: TAnimationRenderSurface; // 描画中のサーフェスを借用する。
    Style: TMarbleStageStyle;         // 部品の材質と形を選ぶ。
    Colors: TMarblePalette;           // 同じステージの静止部品と可動部品で共有する。
    Left, Top: Double;                // 画面左上のワールド座標。
    Scale: Double;                    // ワールド座標1単位のピクセル数。
    function Screen(X, Y: Double): TPointF;
    procedure Box(X1, Y1, X2, Y2: Double; Color: TColor; Opacity: Double = 1);
    procedure Line(const A, B: TBallPoint; Width: Double; Color: TColor; Opacity: Double = 1);
    procedure Disc(const P: TBallPoint; Radius: Double; Color: TColor; Filled: Boolean = True; Opacity: Double = 1);
    procedure Quad(const A, B, C, D: TBallPoint; Color: TColor; Opacity: Double = 1);
    // 接触面ABから下へ部材の厚みを描く。可動中も同じ接触面を使う。
    procedure Beam(const A, B: TBallPoint; Depth: Double; Moving: Boolean);
    procedure Column(X, TopY, BaseY, HalfWidth: Double);
    procedure Joint(const P: TBallPoint; Radius, Angle: Double);
    procedure LinkRod(const A, B: TBallPoint; Active: Boolean);
    procedure Lever(const Pivot, Tip, Tail: TBallPoint; Angle: Double);
    // 皿の上縁とヒンジは、既存の傾斜と昇降に従う。
    procedure Tray(const Rear, Nose, BackRim, FrontRim, Axle: TBallPoint);
    procedure Weight(const P: TBallPoint);
    procedure PressureDial(const P: TBallPoint; Progress: Double);
    procedure ShutterBlade(X, Bottom, Height, Width: Double; Opening: Double);
    procedure Wheel(const Pivot: TBallPoint; Heading: Integer; Turn, Radius: Double);
    procedure Chime(const P: TBallPoint; Swing, Size, Age: Double);
    // 接触からの経過秒を使う。シークでも同じ時刻に同じ反応を描く。
    procedure Impact(const P: TBallPoint; Age, Power: Double);
  end;

function MarblePalette(Style: TMarbleStageStyle): TMarblePalette;
function MarbleMixColor(A, B: TColor; Amount: Double): TColor;

implementation

uses System.Math, Winapi.Windows;

const
  Palettes: array[TMarbleStageStyle] of TMarblePalette = (
    (Ink: $00171B25; Timber: $0035528F; TimberEdge: $00568DCA; Brass: $003F8BC6; PaleBrass: $0088CBF3; Alloy: $00607C95; Aqua: $008AAB8D; Orange: $003A62CA; Pearl: $00B8E9FF;
     TopColor: $002F3F59; BottomColor: $001B1D2B; Grid: $00435774; Pin: $00222739; PinLight: $005B82AD),
    (Ink: $00503D2F; Timber: $0055A6D3; TimberEdge: $0093D8F5; Brass: $008D7050; PaleBrass: $00BFF0FF; Alloy: $00978072; Aqua: $008E9832; Orange: $004750D8; Pearl: $00E7F9FF;
     TopColor: $00EEF3ED; BottomColor: $00D7DCCD; Grid: $00C7CCB8; Pin: $009E9E7D; PinLight: $00E9F7FA),
    (Ink: $001B1917; Timber: $003B4550; TimberEdge: $005581A9; Brass: $004680BA; PaleBrass: $0083CAF2; Alloy: $00797165; Aqua: $00A6BA8F; Orange: $003967BD; Pearl: $00B7E8FF;
     TopColor: $003A3026; BottomColor: $00231C17; Grid: $00554938; Pin: $00353D54; PinLight: $00456084),
    (Ink: $00694E21; Timber: $00DDD69C; TimberEdge: $00FFFCD3; Brass: $00C5A674; PaleBrass: $00FFFCE6; Alloy: $00CAAC8B; Aqua: $00C4C955; Orange: $00A655A6; Pearl: $00FFFFFC;
     TopColor: $00F3EEDD; BottomColor: $00CFBE9C; Grid: $00DCD1B3; Pin: $00A99571; PinLight: $00FFFBEF),
    (Ink: $00220D0E; Timber: $004D3026; TimberEdge: $00A25262; Brass: $00EB74AB; PaleBrass: $00FFF9B8; Alloy: $008E7068; Aqua: $00F5F437; Orange: $008D56FF; Pearl: $00FFF9F9;
     TopColor: $00351421; BottomColor: $00230D08; Grid: $005D273B; Pin: $0072364C; PinLight: $00D264AC),
    (Ink: $004B3629; Timber: $00C08F16; TimberEdge: $00F7D87B; Brass: $0036CFFF; PaleBrass: $00AEF5FF; Alloy: $00ECF5F6; Aqua: $0074BA27; Orange: $00464EF0; Pearl: $00ECFFFF;
     TopColor: $00CDE9F7; BottomColor: $00E5DFCB; Grid: $00ACC8E6; Pin: $00C7C4B4; PinLight: $00E5F6FF),
    (Ink: $00202625; Timber: $005E7577; TimberEdge: $0084AAB9; Brass: $004A8395; PaleBrass: $0098CAD8; Alloy: $0084A2A5; Aqua: $005D9385; Orange: $004578B3; Pearl: $00B4E7F8;
     TopColor: $00374249; BottomColor: $00212825; Grid: $004B5962; Pin: $00272D30; PinLight: $00517079));

function MarblePalette(Style: TMarbleStageStyle): TMarblePalette;
begin
  Result := Palettes[Style];
end;

function MarbleMixColor(A, B: TColor; Amount: Double): TColor;
begin
  Result := RGB(Round(GetRValue(A) + (GetRValue(B) - GetRValue(A)) * Amount),
    Round(GetGValue(A) + (GetGValue(B) - GetGValue(A)) * Amount),
    Round(GetBValue(A) + (GetBValue(B) - GetBValue(A)) * Amount));
end;

function Offset(const P: TBallPoint; X, Y: Double): TBallPoint;
begin
  Result := BallAdd(P, BallPoint(X, Y));
end;

function TMarbleStagePainter.Screen(X, Y: Double): TPointF;
begin
  Result := PointF((X - Left) * Scale, (Top - Y) * Scale);
end;

procedure TMarbleStagePainter.Box(X1, Y1, X2, Y2: Double; Color: TColor; Opacity: Double);
var A, B: TPointF;
begin
  A := Screen(Min(X1, X2), Max(Y1, Y2));
  B := Screen(Max(X1, X2), Min(Y1, Y2));
  Surface.FillRect(A.X, A.Y, B.X, B.Y, Color, Opacity);
end;

procedure TMarbleStagePainter.Line(const A, B: TBallPoint; Width: Double; Color: TColor; Opacity: Double);
var P, Q: TPointF;
begin
  P := Screen(A.X, A.Y);
  Q := Screen(B.X, B.Y);
  Surface.Line(P.X, P.Y, Q.X, Q.Y, Color, Max(1.0, Width * Scale), Opacity);
end;

procedure TMarbleStagePainter.Disc(const P: TBallPoint; Radius: Double; Color: TColor; Filled: Boolean; Opacity: Double);
var Center: TPointF;
begin
  Center := Screen(P.X, P.Y);
  Surface.Circle(Center.X, Center.Y, Radius * Scale, Color, Filled, Max(1.0, 0.012 * Scale), Opacity);
end;

procedure TMarbleStagePainter.Quad(const A, B, C, D: TBallPoint; Color: TColor; Opacity: Double);
begin
  Surface.FillQuad(Screen(A.X, A.Y), Screen(B.X, B.Y), Screen(C.X, C.Y), Screen(D.X, D.Y), Color, Opacity);
end;

procedure TMarbleStagePainter.Beam(const A, B: TBallPoint; Depth: Double; Moving: Boolean);
var P, Q, Down: TBallPoint; Body, Rim: TColor; I, Marks: Integer; Span, Tick, UnitPos: Double;
  function Below(const Point: TBallPoint; Distance: Double): TBallPoint;
  begin
    Result := BallAdd(Point, BallScale(Down, Distance));
  end;
begin
  Span := BallLength(BallSub(B, A));
  if Span < 0.0001 then Exit;
  Down := BallPoint(0, -1);
  if Moving then
  begin
    Down := BallPoint((B.Y - A.Y) / Span, (A.X - B.X) / Span);
    if B.X < A.X then Down := BallScale(Down, -1);
  end;
  Body := Colors.Timber;
  Rim := Colors.TimberEdge;
  if Moving then Rim := Colors.Aqua;
  case Style of
    msWoodWorkshop:
      begin
        Quad(A, B, Below(B, Depth), Below(A, Depth), Body);
        Line(Below(A, Depth * 0.12), Below(B, Depth * 0.12), 0.022, Rim);
        Line(Below(A, Depth * 0.89), Below(B, Depth * 0.89), 0.016, Colors.Ink);
        for I := 1 to 3 do
        begin
          Tick := Depth * (0.22 + I * 0.16);
          P := BallMix(A, B, 0.18 + I * 0.11);
          Q := Below(P, Tick * 0.87);
          Line(Below(A, Tick), Q, 0.007, Colors.TimberEdge, 0.53);
          Line(Q, Below(B, Tick), 0.007, Colors.TimberEdge, 0.53);
        end;
        Disc(Below(BallMix(A, B, 0.10), Depth * 0.51), 0.016, Colors.Brass);
      end;
    msDeskCraft:
      begin
        Depth := Depth * 0.61;
        Quad(A, B, Below(B, Depth), Below(A, Depth), Body);
        Line(A, B, 0.016, Colors.Pearl);
        Line(Below(A, Depth), Below(B, Depth), 0.016, Colors.Orange);
        Marks := Min(36, Floor(Span / 0.065));
        for I := 1 to Marks do
        begin
          P := BallMix(A, B, I / (Marks + 1));
          Tick := 0.34;
          if I mod 5 = 0 then Tick := 0.71;
          Line(Below(P, 0.009), Below(P, Depth * Tick), 0.008, Colors.Ink);
        end;
        if Moving then
          Line(Below(BallMix(A, B, 0.33), Depth * 0.60),
            Below(BallMix(A, B, 0.61), Depth * 0.60), 0.025, Colors.Aqua);
      end;
    msSteampunk:
      begin
        Quad(A, B, Below(B, Depth), Below(A, Depth), Colors.Ink);
        Quad(Below(A, Depth * 0.24), Below(B, Depth * 0.24),
          Below(B, Depth * 0.76), Below(A, Depth * 0.76), Body);
        Line(A, B, 0.025, Colors.Alloy);
        Line(Below(A, Depth * 0.77), Below(B, Depth * 0.77), 0.026, Colors.Brass);
        for I := 1 to Min(12, Floor(Span / 0.19)) do
        begin
          UnitPos := I * 0.17 / Span;
          P := Below(BallMix(A, B, UnitPos), Depth * 0.50);
          Disc(P, 0.020, Colors.Ink);
          Disc(Below(P, -0.005), 0.011, Colors.PaleBrass);
        end;
      end;
    msClearAcrylic:
      begin
        Quad(A, B, Below(B, Depth), Below(A, Depth), Colors.Aqua, 0.22);
        Quad(A, B, Below(B, Depth * 0.31), Below(A, Depth * 0.31), Colors.Pearl, 0.42);
        Line(A, B, 0.015, Colors.Ink, 0.66);
        Line(Below(A, Depth * 0.26), Below(B, Depth * 0.26), 0.025, Colors.Pearl, 0.87);
        Line(Below(A, Depth), Below(B, Depth), 0.014, Colors.Brass, 0.81);
        Line(A, Below(A, Depth), 0.014, Colors.Brass);
        Line(B, Below(B, Depth), 0.014, Colors.Brass);
        P := BallMix(A, B, 0.21);
        Q := BallMix(A, B, 0.35);
        Quad(P, Q, Below(BallMix(A, B, 0.30), Depth), Below(BallMix(A, B, 0.16), Depth),
          Colors.Pearl, 0.29);
      end;
    msNeonArcade:
      begin
        Quad(A, B, Below(B, Depth), Below(A, Depth), Body);
        Line(Below(A, Depth * 0.74), Below(B, Depth * 0.74), 0.037, Colors.Ink);
        Line(Below(A, Depth * 0.37), Below(B, Depth * 0.37), 0.095, Rim, 0.18);
        Line(Below(A, Depth * 0.37), Below(B, Depth * 0.37), 0.034, Rim);
        Line(Below(A, Depth * 0.37), Below(B, Depth * 0.37), 0.012, Colors.Pearl);
        for I := 1 to Min(11, Floor(Span / 0.22)) do
        begin
          P := BallMix(A, B, I * 0.19 / Span);
          Line(Offset(P, -0.025, -Depth * 0.79), Offset(P, 0.024, -Depth * 0.79), 0.013, Colors.Orange);
        end;
      end;
    msColorToys:
      begin
        if Moving then Body := Colors.Orange;
        Line(Below(A, Depth * 0.54), Below(B, Depth * 0.54), Depth, Colors.Ink);
        Line(Below(A, Depth * 0.51), Below(B, Depth * 0.51), Depth * 0.83, Body);
        Line(Below(A, Depth * 0.21), Below(B, Depth * 0.21), Depth * 0.14, Colors.TimberEdge);
        Disc(Below(A, Depth * 0.54), Depth * 0.32, Colors.Brass);
        Disc(Below(B, Depth * 0.54), Depth * 0.32, Colors.Brass);
      end;
    msStoneRuins:
      begin
        Quad(A, B, Below(B, Depth), Below(A, Depth), Body);
        Quad(A, B, Below(B, Depth * 0.35), Below(A, Depth * 0.35), Rim);
        Line(Below(A, Depth * 0.89), Below(B, Depth * 0.89), 0.035, Colors.Ink);
        for I := 1 to Min(10, Floor(Span / 0.32)) do
        begin
          P := BallMix(A, B, I * 0.28 / Span);
          Line(Offset(P, 0.021, -Depth * 0.06), Offset(P, -0.028, -Depth * 0.80), 0.015, Colors.Ink);
          if Odd(I) then
            Line(Offset(P, 0.022, -Depth * 0.55), Offset(P, 0.135, -Depth * 0.60), 0.022, Colors.Aqua);
        end;
      end;
  end;
end;

procedure TMarbleStagePainter.Column(X, TopY, BaseY, HalfWidth: Double);
var I, Blocks: Integer; Step, Y, W: Double; P: TBallPoint;
begin
  if TopY <= BaseY then Exit;
  W := HalfWidth;
  case Style of
    msWoodWorkshop:
      begin
        Box(X - W, BaseY, X + W, TopY, Colors.Timber);
        Line(BallPoint(X - W * 0.63, BaseY), BallPoint(X - W * 0.63, TopY), W * 0.28, Colors.TimberEdge);
        Quad(BallPoint(X, BaseY + 0.08), BallPoint(X + 0.27, TopY), BallPoint(X + 0.20, TopY),
          BallPoint(X - 0.036, BaseY + 0.10), Colors.Timber);
        Box(X - W * 1.40, BaseY - 0.045, X + W * 1.40, BaseY + 0.013, Colors.TimberEdge);
      end;
    msDeskCraft:
      begin
        Blocks := Min(12, Max(2, Ceil((TopY - BaseY) / 0.18)));
        Step := (TopY - BaseY) / Blocks;
        for I := 0 to Blocks - 1 do
        begin
          Y := BaseY + I * Step;
          W := HalfWidth * (1.5 + 0.23 * Ord(Odd(I)));
          Box(X - W, Y, X + W, Y + Step - 0.009, Colors.Ink);
          Box(X - W + 0.013, Y + 0.010, X + W - 0.013, Y + Step - 0.014, Colors.Pearl);
          if Odd(I) then Box(X - W, Y + Step * 0.44, X + W, Y + Step - 0.014, Colors.Aqua, 0.74);
        end;
        Box(X - W * 1.28, TopY - 0.064, X + W * 1.28, TopY, Colors.Orange);
      end;
    msSteampunk:
      begin
        Box(X - W * 1.25, BaseY, X + W * 1.25, TopY, Colors.Ink);
        Box(X - W * 0.65, BaseY, X + W * 0.65, TopY, Colors.Alloy);
        Line(BallPoint(X - W * 0.86, BaseY), BallPoint(X - W * 0.86, TopY), 0.019, Colors.Brass);
        for I := 0 to Min(12, Floor((TopY - BaseY) / 0.23)) do
        begin
          P := BallPoint(X, TopY - I * 0.23);
          Box(X - W * 1.56, P.Y - 0.038, X + W * 1.56, P.Y + 0.026, Colors.Brass);
          Disc(Offset(P, -W, -0.006), 0.015, Colors.Ink);
          Disc(Offset(P, W, -0.006), 0.015, Colors.Ink);
        end;
      end;
    msClearAcrylic:
      begin
        Box(X - W, BaseY, X + W, TopY, Colors.Aqua, 0.20);
        Line(BallPoint(X - W, BaseY), BallPoint(X - W, TopY), 0.019, Colors.Pearl, 0.84);
        Line(BallPoint(X + W, BaseY), BallPoint(X + W, TopY), 0.012, Colors.Ink, 0.59);
        Box(X - W * 1.36, TopY - 0.056, X + W * 1.36, TopY + 0.013, Colors.Brass, 0.82);
        Box(X - W * 1.63, BaseY - 0.029, X + W * 1.63, BaseY + 0.024, Colors.Pearl, 0.74);
      end;
    msNeonArcade:
      begin
        W := W * 1.45;
        Quad(BallPoint(X - W, TopY), BallPoint(X + W, TopY), BallPoint(X + W * 0.66, BaseY),
          BallPoint(X - W * 0.66, BaseY), Colors.Ink);
        Box(X - W * 0.47, BaseY + 0.026, X + W * 0.47, TopY - 0.021, Colors.Alloy);
        Line(BallPoint(X, BaseY + 0.036), BallPoint(X, TopY - 0.04), 0.032, Colors.Aqua);
        Line(BallPoint(X, BaseY + 0.036), BallPoint(X, TopY - 0.04), 0.010, Colors.Pearl);
        Box(X - W, TopY - 0.034, X + W, TopY + 0.018, Colors.TimberEdge);
      end;
    msColorToys:
      begin
        W := W * 1.72;
        Line(BallPoint(X, BaseY + 0.03), BallPoint(X, TopY - 0.045), W * 1.72, Colors.Aqua);
        Line(BallPoint(X - W * 0.40, BaseY + 0.055), BallPoint(X - W * 0.40, TopY - 0.055), 0.022,
          Colors.Pearl, 0.62);
        Line(BallPoint(X - W * 0.77, BaseY), BallPoint(X + W * 0.77, BaseY), 0.094, Colors.Orange);
        Line(BallPoint(X - W, TopY - 0.026), BallPoint(X + W, TopY - 0.026), 0.089, Colors.Brass);
        Disc(BallPoint(X, TopY - 0.026), 0.030, Colors.Timber);
      end;
    msStoneRuins:
      begin
        W := W * 1.75;
        Box(X - W * 1.30, BaseY - 0.053, X + W * 1.30, BaseY + 0.043, Colors.Ink);
        Blocks := Min(13, Max(2, Ceil((TopY - BaseY) / 0.22)));
        Step := (TopY - BaseY) / Blocks;
        for I := 0 to Blocks - 1 do
        begin
          Y := BaseY + I * Step;
          Box(X - W, Y, X + W, Y + Step - 0.017, Colors.Timber);
          Box(X - W, Y + Step - 0.040, X + W, Y + Step - 0.017, Colors.TimberEdge);
          Line(BallPoint(X - W * 0.43, Y + 0.024), BallPoint(X - W * 0.72, Y + Step * 0.63), 0.014, Colors.Ink);
        end;
        Box(X - W * 1.34, TopY - 0.068, X + W * 1.34, TopY, Colors.TimberEdge);
      end;
  end;
end;

procedure TMarbleStagePainter.Joint(const P: TBallPoint; Radius, Angle: Double);
var I: Integer; A: Double; Rim: TColor; Q: TBallPoint;
begin
  case Style of
    msWoodWorkshop:
      begin
        Disc(P, Radius, Colors.Ink);
        Disc(P, Radius * 0.74, Colors.Brass);
        Line(Offset(P, -Radius * 0.48 * Cos(Angle), -Radius * 0.48 * Sin(Angle)),
          Offset(P, Radius * 0.48 * Cos(Angle), Radius * 0.48 * Sin(Angle)), 0.014, Colors.Ink);
      end;
    msDeskCraft:
      begin
        Box(P.X - Radius, P.Y - Radius * 0.68, P.X + Radius, P.Y + Radius * 0.42, Colors.Ink);
        Line(Offset(P, -Radius * 0.75, 0), Offset(P, -Radius * 0.50, Radius * 1.17), 0.016, Colors.Alloy);
        Line(Offset(P, Radius * 0.75, 0), Offset(P, Radius * 0.50, Radius * 1.17), 0.016, Colors.Alloy);
        Line(Offset(P, -Radius * 0.50, Radius * 1.17), Offset(P, Radius * 0.50, Radius * 1.17), 0.016, Colors.Alloy);
      end;
    msSteampunk:
      begin
        Disc(P, Radius, Colors.Ink);
        for I := 0 to 7 do
        begin
          A := Angle + I * Pi / 4;
          Q := Offset(P, Radius * Cos(A), Radius * Sin(A));
          Line(BallMix(P, Q, 0.66), Q, Radius * 0.30, Colors.Brass);
        end;
        Disc(P, Radius * 0.69, Colors.Brass);
        Disc(P, Radius * 0.37, Colors.Ink);
        Disc(Offset(P, -Radius * 0.11, Radius * 0.10), Radius * 0.20, Colors.Alloy);
      end;
    msClearAcrylic:
      begin
        Disc(P, Radius * 1.12, Colors.Pearl, True, 0.41);
        Disc(P, Radius, Colors.Ink, False, 0.70);
        Disc(P, Radius * 0.59, Colors.Pearl, False);
        Disc(P, Radius * 0.24, Colors.Ink);
      end;
    msNeonArcade:
      begin
        Disc(P, Radius * 1.12, Colors.Ink);
        Disc(P, Radius * 0.88, Colors.Aqua, False);
        Disc(P, Radius * 0.53, Colors.TimberEdge);
        Disc(P, Radius * 0.22, Colors.Pearl);
      end;
    msColorToys:
      begin
        Disc(P, Radius * 1.15, Colors.Ink);
        Disc(P, Radius * 0.97, Colors.Brass);
        Disc(Offset(P, -Radius * 0.22, Radius * 0.24), Radius * 0.32, Colors.PaleBrass);
        Disc(P, Radius * 0.32, Colors.Orange);
      end;
    msStoneRuins:
      begin
        Rim := Colors.TimberEdge;
        Quad(Offset(P, -Radius, Radius * 0.56), Offset(P, Radius, Radius * 0.56),
          Offset(P, Radius * 0.80, -Radius * 0.70), Offset(P, -Radius * 0.80, -Radius * 0.70), Rim);
        Disc(P, Radius * 0.64, Colors.Ink);
        Disc(P, Radius * 0.41, Colors.Brass);
      end;
  end;
end;

procedure TMarbleStagePainter.LinkRod(const A, B: TBallPoint; Active: Boolean);
var P, Q: TBallPoint; Color: TColor; I: Integer;
begin
  Color := Colors.Brass;
  if Active then Color := Colors.Orange;
  case Style of
    msWoodWorkshop:
      begin
        Line(A, B, 0.030, Colors.Ink);
        Line(A, B, 0.016, Colors.PaleBrass);
      end;
    msDeskCraft: Line(A, B, 0.014, Colors.Orange);
    msSteampunk:
      begin
        Line(A, B, 0.036, Colors.Ink);
        Line(A, B, 0.019, Colors.Alloy);
        P := BallMix(A, B, 0.36);
        Q := BallMix(A, B, 0.73);
        Line(P, Q, 0.049, Color);
        Disc(P, 0.024, Colors.PaleBrass);
      end;
    msClearAcrylic:
      begin
        Line(A, B, 0.042, Colors.Ink, 0.39);
        Line(A, B, 0.024, Colors.Pearl, 0.81);
      end;
    msNeonArcade:
      begin
        Line(A, B, 0.039, Colors.Ink);
        Line(A, B, 0.015, Colors.TimberEdge);
        if Active then Line(A, B, 0.023, Colors.Aqua);
      end;
    msColorToys:
      begin
        Line(A, B, 0.047, Colors.Ink);
        Line(A, B, 0.026, Colors.Orange);
        Disc(B, 0.036, Colors.Brass);
      end;
    msStoneRuins:
      begin
        Line(A, B, 0.042, Colors.Ink);
        Line(A, B, 0.025, Colors.Brass);
        for I := 1 to 8 do
        begin
          P := BallMix(A, B, I / 9);
          Line(Offset(P, -0.011, 0.012), Offset(P, 0.011, -0.012), 0.009, Colors.PaleBrass);
        end;
      end;
  end;
end;

procedure TMarbleStagePainter.Lever(const Pivot, Tip, Tail: TBallPoint; Angle: Double);
var Pad, Edge: TBallPoint;
begin
  Pad := BallMix(Tip, Pivot, 0.40);
  Edge := BallScale(BallUnit(BallSub(Pivot, Tip)), 0.037);
  Edge := BallPoint(-Edge.Y, Edge.X);
  case Style of
    msWoodWorkshop:
      begin
        Line(Tip, Tail, 0.073, Colors.Ink);
        Line(Tip, Tail, 0.058, Colors.Timber);
        Line(Offset(Tip, Edge.X * 0.45, Edge.Y * 0.45),
          Offset(Tail, Edge.X * 0.45, Edge.Y * 0.45), 0.014, Colors.TimberEdge);
        Disc(Tip, 0.022, Colors.Brass);
      end;
    msDeskCraft:
      begin
        Line(Offset(Tip, Edge.X, Edge.Y), Tail, 0.042, Colors.Orange);
        Line(Offset(Tip, -Edge.X, -Edge.Y), Pad, 0.029, Colors.Timber);
        Line(Offset(Pad, Edge.X, Edge.Y), Offset(Pad, -Edge.X, -Edge.Y), 0.014, Colors.Alloy);
      end;
    msSteampunk:
      begin
        LinkRod(Tip, Tail, True);
        Line(Tip, Pad, 0.069, Colors.Brass);
        Disc(Tip, 0.030, Colors.Ink);
      end;
    msClearAcrylic:
      begin
        Line(Tip, Tail, 0.091, Colors.Ink, 0.57);
        Line(Tip, Tail, 0.065, Colors.Aqua, 0.57);
        Line(Offset(Tip, Edge.X * 0.53, Edge.Y * 0.53),
          Offset(Tail, Edge.X * 0.53, Edge.Y * 0.53), 0.015, Colors.Pearl);
      end;
    msNeonArcade:
      begin
        Line(Tip, Tail, 0.096, Colors.Ink);
        Line(Tip, Tail, 0.034, Colors.Aqua);
        Disc(Tip, 0.043, Colors.Orange);
      end;
    msColorToys:
      begin
        Line(Tip, Tail, 0.094, Colors.Orange);
        Disc(Tip, 0.063, Colors.Brass);
        Line(Pad, Pivot, 0.018, Colors.Pearl, 0.71);
      end;
    msStoneRuins:
      begin
        Line(Tip, Tail, 0.088, Colors.Ink);
        Line(Tip, Tail, 0.062, Colors.TimberEdge);
        Line(Tip, Pad, 0.031, Colors.Aqua);
      end;
  end;
  Joint(Pivot, 0.065, Angle);
end;

procedure TMarbleStagePainter.Tray(const Rear, Nose, BackRim, FrontRim, Axle: TBallPoint);
var A, B, Center, Rib, Along, Down: TBallPoint; I: Integer; Lip: TColor;
  function Below(const Point: TBallPoint; Distance: Double): TBallPoint;
  begin
    Result := BallAdd(Point, BallScale(Down, Distance));
  end;
begin
  Along := BallUnit(BallSub(Nose, Rear));
  Down := BallPoint(Along.Y, -Along.X);
  if Nose.X < Rear.X then Down := BallScale(Down, -1);
  Lip := Colors.Aqua;
  case Style of
    msWoodWorkshop: Beam(Rear, Nose, 0.123, True);
    msDeskCraft:
      begin
        A := Below(BallMix(Rear, Nose, 0.18), 0.20);
        B := Below(BallMix(Rear, Nose, 0.82), 0.20);
        Quad(Rear, Nose, B, A, Colors.Pearl);
        Quad(Below(Rear, 0.05), Below(Nose, 0.05), Below(B, -0.055),
          Below(A, -0.055), Colors.Orange);
        for I := 1 to 6 do
        begin
          Rib := BallMix(Rear, Nose, I / 7);
          Line(Rib, BallMix(A, B, I / 7), 0.009, Colors.TimberEdge);
        end;
        Lip := Colors.Orange;
      end;
    msSteampunk:
      begin
        Quad(Rear, Nose, Below(BallMix(Rear, Nose, 0.75), 0.18),
          Below(BallMix(Rear, Nose, 0.25), 0.18), Colors.Brass);
        Beam(Rear, Nose, 0.085, True);
        Disc(Below(Axle, 0.082), 0.032, Colors.PaleBrass);
        Lip := Colors.Brass;
      end;
    msClearAcrylic:
      begin
        Quad(BackRim, FrontRim, Below(Nose, 0.12), Below(Rear, 0.12), Colors.Aqua, 0.24);
        Beam(Rear, Nose, 0.12, True);
        Lip := Colors.Pearl;
      end;
    msNeonArcade:
      begin
        Beam(Rear, Nose, 0.14, True);
        for I := 1 to 4 do
          Disc(Below(BallMix(Rear, Nose, I / 5), 0.093), 0.016, Colors.Orange);
      end;
    msColorToys:
      begin
        Beam(Rear, Nose, 0.17, True);
        Center := Below(BallMix(Rear, Nose, 0.5), 0.105);
        Disc(Center, 0.060, Colors.Brass);
        Disc(Offset(Center, -0.018, 0.022), 0.024, Colors.Pearl);
        Lip := Colors.Orange;
      end;
    msStoneRuins:
      begin
        Beam(Rear, Nose, 0.20, True);
        Quad(Below(Rear, 0.05), Below(BallMix(Rear, Nose, 0.26), 0.04),
          Below(BallMix(Rear, Nose, 0.33), 0.20), Below(Rear, 0.20), Colors.Brass, 0.76);
        Lip := Colors.TimberEdge;
      end;
  end;
  Line(Rear, BackRim, 0.039, Lip);
  Line(Nose, FrontRim, 0.037, Lip);
  Line(Rear, Nose, 0.017, Colors.PaleBrass);
  Joint(Below(Axle, 0.036), 0.048, ArcTan2(Nose.Y - Rear.Y, Nose.X - Rear.X));
end;

procedure TMarbleStagePainter.Weight(const P: TBallPoint);
var Face: TColor;
begin
  Face := Colors.Brass;
  case Style of
    msDeskCraft: Face := Colors.Orange;
    msClearAcrylic: Face := Colors.Alloy;
    msNeonArcade: Face := Colors.Timber;
    msStoneRuins: Face := Colors.TimberEdge;
  end;
  Box(P.X - 0.085, P.Y - 0.10, P.X + 0.085, P.Y + 0.09, Colors.Ink);
  Box(P.X - 0.069, P.Y - 0.086, P.X + 0.069, P.Y + 0.076, Face);
  Line(Offset(P, -0.063, 0.054), Offset(P, 0.063, 0.054), 0.020, Colors.PaleBrass);
  Joint(P, 0.035, Pi / 3);
end;

procedure TMarbleStagePainter.PressureDial(const P: TBallPoint; Progress: Double);
var I: Integer; A, B, Tip: TBallPoint; Angle: Double;
begin
  Disc(P, 0.146, Colors.Ink);
  Disc(P, 0.132, Colors.Brass);
  Disc(P, 0.106, Colors.Pearl);
  for I := 0 to 4 do
  begin
    Angle := 3.55 - I * 1.02;
    A := Offset(P, 0.074 * Cos(Angle), 0.074 * Sin(Angle));
    B := Offset(P, 0.094 * Cos(Angle), 0.094 * Sin(Angle));
    Line(A, B, 0.010, Colors.Ink);
  end;
  Angle := 3.55 - 4.08 * Progress;
  Tip := Offset(P, 0.080 * Cos(Angle), 0.080 * Sin(Angle));
  Line(P, Tip, 0.018, Colors.Orange);
  Disc(P, 0.017, Colors.Ink);
end;

procedure TMarbleStagePainter.ShutterBlade(X, Bottom, Height, Width: Double; Opening: Double);
var P, Q: TBallPoint; Opacity: Double;
begin
  P := BallPoint(X - Width, Bottom + Height);
  Q := BallPoint(X + Width, Bottom + Height);
  Opacity := 1;
  if Style = msClearAcrylic then Opacity := 0.43;
  Quad(P, Q, BallPoint(X + Width * 0.74, Bottom), BallPoint(X - Width * 0.74, Bottom),
    Colors.Orange, Opacity);
  if Style in [msStoneRuins, msSteampunk, msWoodWorkshop] then
    Line(Offset(P, 0, -Height * 0.75), Offset(Q, 0, -Height * 0.75), 0.036, Colors.Brass);
  if Style = msNeonArcade then
    Line(BallPoint(X, Bottom + Height * 0.21), BallPoint(X, Bottom + Height * 0.89),
      0.027, MarbleMixColor(Colors.Orange, Colors.Aqua, Opening));
  Joint(Offset(BallMix(P, Q, 0.5), 0, -0.043), 0.034, Opening * Pi);
end;

procedure TMarbleStagePainter.Wheel(const Pivot: TBallPoint; Heading: Integer; Turn, Radius: Double);
var I, Count: Integer; Angle: Double; Tip, Paddle, Base: TBallPoint; Color: TColor;
begin
  Count := 4;
  if Style in [msSteampunk, msStoneRuins] then Count := 6;
  if Style = msSteampunk then Disc(Pivot, Radius * 0.75, Colors.Ink, False);
  if Style = msNeonArcade then Disc(Pivot, Radius * 0.79, Colors.Aqua, False, 0.54);
  for I := 0 to Count - 1 do
  begin
    Angle := -Pi / 2 + I * (2 * Pi / Count) + Turn;
    Tip := Offset(Pivot, Heading * Cos(Angle) * Radius, Sin(Angle) * Radius);
    Paddle := BallPoint(Heading * -Sin(Angle) * 0.049, Cos(Angle) * 0.049);
    Base := BallMix(Pivot, Tip, 0.23);
    Color := Colors.Aqua;
    case Style of
      msWoodWorkshop: begin Line(Base, Tip, 0.064, Colors.Timber); Color := Colors.TimberEdge; end;
      msDeskCraft: begin Line(Base, Tip, 0.028, Colors.Alloy); Color := Colors.Orange; end;
      msSteampunk: begin Line(Base, Tip, 0.043, Colors.Brass); Color := Colors.PaleBrass; end;
      msClearAcrylic: begin Line(Base, Tip, 0.042, Colors.Pearl, 0.73); Color := Colors.Brass; end;
      msNeonArcade: begin Line(Base, Tip, 0.067, Colors.Ink); Line(Base, Tip, 0.025, Colors.Aqua); end;
      msColorToys:
        begin
          if Odd(I) then Color := Colors.Orange;
          Quad(Base, Offset(Tip, Paddle.X, Paddle.Y), Tip, Offset(Tip, -Paddle.X, -Paddle.Y), Color);
        end;
      msStoneRuins: begin Line(Base, Tip, 0.053, Colors.TimberEdge); Color := Colors.Brass; end;
    end;
    Line(BallSub(Tip, Paddle), BallAdd(Tip, Paddle), 0.035, Color);
  end;
  Joint(Pivot, Radius * 0.36, Turn * Heading);
end;

procedure TMarbleStagePainter.Chime(const P: TBallPoint; Swing, Size, Age: Double);
var Crown, Rim, A, B: TBallPoint; Color: TColor; I: Integer; Glow: Double;
begin
  Crown := Offset(P, Swing * 0.48, -Size * 0.36);
  Rim := Offset(P, Swing, -Size * 0.92);
  Line(P, Crown, Size * 0.16, Colors.Alloy);
  Color := Colors.Brass;
  case Style of
    msDeskCraft: Color := Colors.Alloy;
    msClearAcrylic: Color := Colors.Brass;
    msColorToys: Color := Colors.Orange;
  end;
  case Style of
    msSteampunk, msStoneRuins:
      begin
        Disc(Offset(Rim, 0, Size * 0.24), Size * 0.40, Colors.Ink);
        Disc(Offset(Rim, 0, Size * 0.24), Size * 0.34, Color);
        Disc(Offset(Rim, 0, Size * 0.24), Size * 0.21, Colors.PaleBrass, False);
      end;
    msNeonArcade:
      begin
        Box(Rim.X - Size * 0.48, Rim.Y - Size * 0.06, Rim.X + Size * 0.48, Crown.Y, Colors.Ink);
        Glow := 0;
        if Age >= 0 then Glow := Exp(-Age * 13);
        for I := -1 to 1 do
        begin
          A := Offset(Rim, I * Size * 0.28, Size * 0.07);
          B := Offset(A, 0, Size * (0.22 + 0.10 * I));
          Line(A, B, Size * 0.14, MarbleMixColor(Colors.TimberEdge, Colors.Aqua, Glow));
        end;
      end;
    msClearAcrylic:
      begin
        for I := -1 to 1 do
        begin
          A := Offset(Crown, I * Size * 0.23, 0);
          B := Offset(Rim, I * Size * 0.23, I * Size * 0.15);
          Line(A, B, Size * 0.17, Color, 0.74);
          Line(Offset(A, -0.010, 0), Offset(B, -0.010, 0), 0.012, Colors.Pearl);
        end;
      end;
    else
      begin
        Quad(Offset(Crown, -Size * 0.20, 0), Offset(Crown, Size * 0.20, 0),
          Offset(Rim, Size * 0.42, 0), Offset(Rim, -Size * 0.42, 0), Color);
        Line(Offset(Rim, -Size * 0.47, 0), Offset(Rim, Size * 0.47, 0),
          Size * 0.13, Colors.PaleBrass);
        Disc(Offset(Rim, Swing * 0.19, -Size * 0.11), Size * 0.13, Colors.Orange);
      end;
  end;
end;

procedure TMarbleStagePainter.Impact(const P: TBallPoint; Age, Power: Double);
var I, Count: Integer; U, Angle, Radius: Double; A, B: TBallPoint; Color: TColor;
begin
  if (Age < 0) or (Age >= 0.25) then Exit;
  U := Age / 0.25;
  Radius := 0.059 + U * (0.12 + 0.16 * Power);
  Color := Colors.PaleBrass;
  Count := 5;
  case Style of
    msWoodWorkshop: Color := Colors.TimberEdge;
    msDeskCraft: Color := Colors.Orange;
    msSteampunk: Color := Colors.Brass;
    msClearAcrylic: begin Count := 3; Color := Colors.Pearl; end;
    msNeonArcade:
      begin
        Disc(P, Radius * 0.81, Colors.Aqua, False, 0.78 * (1 - U));
        Disc(P, Radius * 1.42, Colors.Orange, False, 0.37 * (1 - U));
        Color := Colors.Aqua;
      end;
    msColorToys: begin Count := 6; Color := Colors.Orange; end;
    msStoneRuins: Color := Colors.TimberEdge;
  end;
  for I := 0 to Count - 1 do
  begin
    Angle := (I + 0.18) * 2 * Pi / Count;
    A := Offset(P, Radius * Cos(Angle), Radius * Sin(Angle));
    B := Offset(P, (Radius + 0.055) * Cos(Angle), (Radius + 0.055) * Sin(Angle));
    case Style of
      msStoneRuins, msSteampunk: Disc(Offset(A, 0, -0.115 * Sqr(U)), 0.025 * (1 - U), Color, True, 0.63);
      msColorToys: Quad(A, Offset(B, 0, 0.014), B, Offset(A, 0, -0.022), Color, 1 - U);
      else Line(A, B, 0.019, Color, 1 - U);
    end;
  end;
  Disc(P, 0.028 * (1 - U), Colors.Pearl, True, 1 - U);
end;

end.
