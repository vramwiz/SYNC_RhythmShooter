unit RhythmMarbleBackdrop;
// 装置の後ろに工房、机、機関室などを描く。背景は球との接触に関与しない。
interface

uses RhythmMarbleStage;

// 表示範囲の幅と高さはワールド座標で渡す。
procedure DrawMarbleBackdrop(const Art: TMarbleStagePainter; Width, Height: Double);

implementation

uses System.Math, Vcl.Graphics, RhythmBallGeometry, RhythmStyles;

type
  TBackdrop = record
    Art: TMarbleStagePainter; // 描画器と画角を借用する。
    Width, Height: Double;    // 表示範囲のワールド座標の幅と高さ。
    function Point(U, V: Double): TBallPoint;
    procedure Box(X1, Y1, X2, Y2: Double; Color: TColor);
    procedure Stroke(X1, Y1, X2, Y2, Size: Double; Color: TColor);
    procedure Gradient;
    procedure Workshop;
    procedure Desk;
    procedure EngineRoom;
    procedure Showroom;
    procedure Arcade;
    procedure Playroom;
    procedure Ruins;
  end;

function TBackdrop.Point(U, V: Double): TBallPoint;
begin
  Result := BallPoint(Art.Left + Width * U, Art.Top - Height * V);
end;

procedure TBackdrop.Box(X1, Y1, X2, Y2: Double; Color: TColor);
var P, Q: TBallPoint;
begin
  P := Point(X1, Y1);
  Q := Point(X2, Y2);
  Art.Box(P.X, P.Y, Q.X, Q.Y, Color);
end;

procedure TBackdrop.Stroke(X1, Y1, X2, Y2, Size: Double; Color: TColor);
begin
  Art.Line(Point(X1, Y1), Point(X2, Y2), Size, Color);
end;

procedure TBackdrop.Gradient;
const Bands = 36;
var I, W, H: Integer;
begin
  W := Ceil(Width * Art.Scale);
  H := Ceil(Height * Art.Scale);
  for I := 0 to Bands - 1 do
    Art.Surface.FillRect(0, H * I div Bands, W, H * (I + 1) div Bands,
      MarbleMixColor(Art.Colors.TopColor, Art.Colors.BottomColor, I / (Bands - 1)));
end;

procedure TBackdrop.Workshop;
var I, J: Integer; X, Y: Double; Light, Dark: TColor; P: TBallPoint;
begin
  Dark := Art.Colors.Pin;
  Light := Art.Colors.Grid;
  for I := -1 to 12 do
  begin
    X := I * 0.092 - Frac(Art.Left * 0.08) * 0.092;
    Stroke(X, 0, X, 0.84, 0.025, Dark);
    Stroke(X + 0.006, 0, X + 0.006, 0.83, 0.009, Light);
    for J := 0 to 2 do
    begin
      Y := 0.12 + J * 0.22 + 0.012 * (I mod 4);
      Stroke(X + 0.034, Y, X + 0.030, Y + 0.13, 0.008, Light);
    end;
  end;
  Box(0, 0.84, 1, 1, Art.Colors.BottomColor);
  Box(0, 0.825, 1, 0.851, Light);
  Box(0.04, 0.13, 0.27, 0.39, MarbleMixColor(Light, Art.Colors.PinLight, 0.42));
  Box(0.053, 0.149, 0.257, 0.371, Dark);
  for I := 1 to 7 do Stroke(0.06 + I * 0.024, 0.153, 0.06 + I * 0.024, 0.366, 0.007, Light);
  for I := 1 to 5 do Stroke(0.058, 0.15 + I * 0.034, 0.25, 0.15 + I * 0.034, 0.007, Light);
  Stroke(0.067, 0.222, 0.128, 0.304, 0.014, Art.Colors.PinLight);
  Stroke(0.128, 0.304, 0.230, 0.243, 0.014, Art.Colors.PinLight);
  Box(0.75, 0.52, 0.97, 0.553, Light);
  for I := 0 to 3 do
  begin
    P := Point(0.773 + I * 0.049, 0.31 + 0.028 * Ord(Odd(I)));
    Art.Line(P, BallAdd(P, BallPoint(0, -0.45)), 0.034, Light);
    Art.Disc(P, 0.064, Light, False);
  end;
end;

procedure TBackdrop.Desk;
var I: Integer; Edge, Paper: TColor; A, B: TBallPoint;
begin
  Paper := Art.Colors.PinLight;
  Edge := Art.Colors.Grid;
  Art.Quad(Point(-0.08, 0.12), Point(0.43, 0.08), Point(0.49, 0.67), Point(-0.03, 0.73), Edge);
  Art.Quad(Point(-0.09, 0.11), Point(0.42, 0.07), Point(0.48, 0.65), Point(-0.04, 0.71), Paper);
  for I := 1 to 11 do Stroke(0.011, 0.12 + I * 0.045, 0.427, 0.085 + I * 0.045, 0.006, Edge);
  for I := 1 to 10 do Stroke(I * 0.039, 0.105, I * 0.039 + 0.042, 0.674, 0.006, Edge);
  Art.Quad(Point(0.72, 0.64), Point(0.99, 0.53), Point(1.06, 1.04), Point(0.78, 1.13), Paper);
  for I := 1 to 5 do Stroke(0.76 + I * 0.047, 0.68, 0.81 + I * 0.047, 0.96, 0.008, Edge);
  A := Point(0.77, 0.16);
  B := Point(0.95, 0.26);
  Art.Line(A, B, 0.112, Edge);
  Art.Line(A, B, 0.074, MarbleMixColor(Art.Colors.Brass, Art.Colors.TopColor, 0.46));
  Art.Line(B, Point(0.972, 0.274), 0.045, Art.Colors.Pin);
  Art.Disc(Point(0.77, 0.16), 0.056, MarbleMixColor(Art.Colors.Orange, Paper, 0.49));
  Art.Line(Point(0.08, 0.91), Point(0.32, 0.88), 0.095, Edge);
  for I := 0 to 3 do Art.Disc(Point(0.14 + I * 0.037, 0.87), 0.037, Paper);
end;

procedure TBackdrop.EngineRoom;
var I, J: Integer; X: Double; P, A, B: TBallPoint; Metal, Shade: TColor;
begin
  Metal := Art.Colors.Grid;
  Shade := Art.Colors.BottomColor;
  for I := 0 to 3 do
  begin
    X := 0.16 + I * 0.27;
    P := Point(X, 0.29);
    Art.Disc(P, 0.51, Shade);
    Art.Disc(P, 0.46, Metal, False);
    Art.Disc(P, 0.34, Metal, False);
    for J := 0 to 9 do
      Art.Disc(BallAdd(P, BallPoint(0.42 * Cos(J * Pi / 5), 0.42 * Sin(J * Pi / 5))), 0.020, Art.Colors.PinLight);
    Box(X - 0.075, 0.30, X + 0.075, 0.82, Shade);
    Stroke(X - 0.061, 0.32, X - 0.061, 0.80, 0.040, Metal);
    Stroke(X + 0.056, 0.32, X + 0.056, 0.80, 0.018, Metal);
  end;
  A := Point(0, 0.81);
  B := Point(0.85, 0.81);
  Art.Line(A, B, 0.146, Art.Colors.Pin);
  Art.Line(B, Point(0.85, 0.53), 0.145, Art.Colors.Pin);
  Art.Line(A, B, 0.032, Art.Colors.PinLight);
  for I := 1 to 5 do
    Box(I * 0.15, 0.780, I * 0.15 + 0.019, 0.833, Art.Colors.PinLight);
  Stroke(0, 0.92, 1, 0.92, 0.055, Metal);
end;

procedure TBackdrop.Showroom;
var I: Integer; X: Double; Edge, White: TColor;
begin
  Edge := Art.Colors.Grid;
  White := Art.Colors.PinLight;
  Box(0.05, 0.12, 0.95, 0.79, MarbleMixColor(Art.Colors.TopColor, White, 0.63));
  Box(0.06, 0.13, 0.94, 0.155, White);
  for I := 0 to 4 do
  begin
    X := 0.05 + I * 0.225;
    Stroke(X, 0.12, X, 0.79, 0.016, Edge);
    Stroke(X, 0.79, 0.5 + (X - 0.5) * 1.45, 1, 0.013, Edge);
  end;
  Stroke(0, 0.79, 1, 0.79, 0.016, Edge);
  Stroke(0, 0.915, 1, 0.915, 0.010, Edge);
  Art.Quad(Point(0.12, 0.15), Point(0.30, 0.15), Point(0.53, 0.72), Point(0.43, 0.72), White, 0.47);
  Art.Quad(Point(0.68, 0.15), Point(0.73, 0.15), Point(0.93, 0.61), Point(0.86, 0.61), White, 0.55);
  Box(0.12, 0.057, 0.88, 0.070, White);
end;

procedure TBackdrop.Arcade;
var I, J: Integer; X, Y: Double; Edge, CaseColor: TColor;
begin
  Edge := Art.Colors.Grid;
  CaseColor := MarbleMixColor(Art.Colors.BottomColor, Edge, 0.31);
  for I := -1 to 3 do
  begin
    X := I * 0.29 + 0.078;
    Art.Quad(Point(X, 0.13), Point(X + 0.18, 0.13), Point(X + 0.22, 0.86), Point(X - 0.04, 0.86), CaseColor);
    Box(X + 0.017, 0.185, X + 0.165, 0.46, Art.Colors.BottomColor);
    Stroke(X + 0.019, 0.19, X + 0.157, 0.19, 0.023, Edge);
    for J := 0 to 4 do
    begin
      Y := 0.23 + J * 0.037;
      Stroke(X + 0.034, Y, X + 0.136 - 0.012 * (J mod 3), Y, 0.016, Edge);
      Art.Disc(Point(X + 0.035 + J * 0.025, 0.54), 0.032, Art.Colors.Pin);
    end;
    Stroke(X - 0.017, 0.70, X + 0.204, 0.70, 0.026, Edge);
  end;
  Stroke(0, 0.094, 1, 0.094, 0.039, Edge);
  Stroke(0, 0.87, 1, 0.87, 0.031, Edge);
  for I := -4 to 4 do Stroke(0.5 + I * 0.075, 0.87, 0.5 + I * 0.22, 1, 0.012, Edge);
end;

procedure TBackdrop.Playroom;
var I, J: Integer; X, Y: Double; Color, Edge: TColor;
begin
  Edge := Art.Colors.Grid;
  Box(0, 0.75, 1, 1, Art.Colors.BottomColor);
  Stroke(0, 0.75, 1, 0.75, 0.035, Art.Colors.PinLight);
  Stroke(0.04, 0.10, 0.94, 0.13, 0.017, Edge);
  for I := 0 to 9 do
  begin
    X := 0.078 + I * 0.088;
    Y := 0.10 + X * 0.03;
    Color := Art.Colors.Brass;
    if Odd(I) then Color := Art.Colors.Aqua;
    if I mod 3 = 0 then Color := Art.Colors.Orange;
    Color := MarbleMixColor(Color, Art.Colors.PinLight, 0.42);
    Art.Quad(Point(X, Y), Point(X + 0.055, Y + 0.003), Point(X + 0.025, Y + 0.089),
      Point(X + 0.025, Y + 0.088), Color);
  end;
  for I := 0 to 5 do
    for J := 0 to 2 do
      if Odd(I + J) then Box(I / 6, 0.76 + J * 0.085, (I + 1) / 6, 0.76 + (J + 1) * 0.085,
        MarbleMixColor(Art.Colors.PinLight, Art.Colors.BottomColor, 0.50));
  Box(0.035, 0.48, 0.24, 0.507, Edge);
  for I := 0 to 3 do
  begin
    X := 0.047 + I * 0.047;
    Box(X, 0.36 + 0.026 * Ord(Odd(I)), X + 0.040, 0.48,
      MarbleMixColor(Art.Colors.Aqua, Art.Colors.PinLight, 0.66));
    Art.Disc(Point(X + 0.020, 0.434), 0.043, Art.Colors.PinLight);
  end;
end;

procedure TBackdrop.Ruins;
var I, J: Integer; X, Y, ArchWidth, Angle: Double; Center, A, B: TBallPoint; Stone, Shadow: TColor;
begin
  Stone := Art.Colors.Grid;
  Shadow := Art.Colors.BottomColor;
  for I := 0 to 3 do
  begin
    X := 0.10 + I * 0.29;
    ArchWidth := 0.106;
    Box(X - ArchWidth, 0.32, X + ArchWidth, 0.92, Shadow);
    Center := Point(X, 0.32);
    Art.Disc(Center, ArchWidth * Width, Shadow);
    for J := 0 to 9 do
    begin
      Angle := J * Pi / 10;
      A := BallAdd(Center, BallPoint(Cos(Angle) * ArchWidth * Width, Sin(Angle) * ArchWidth * Width));
      Angle := (J + 1) * Pi / 10;
      B := BallAdd(Center, BallPoint(Cos(Angle) * ArchWidth * Width, Sin(Angle) * ArchWidth * Width));
      Art.Line(A, B, 0.096, Stone);
      Art.Line(A, BallAdd(A, BallPoint(0, 0.045)), 0.016, Art.Colors.PinLight);
    end;
    for J := 0 to 5 do
    begin
      Y := 0.31 + J * 0.097;
      Box(X - ArchWidth - 0.022, Y, X - ArchWidth + 0.016, Y + 0.090, Stone);
      Box(X + ArchWidth - 0.016, Y, X + ArchWidth + 0.022, Y + 0.090, Stone);
    end;
  end;
  Art.Quad(Point(0.63, 0), Point(0.72, 0), Point(0.47, 0.91), Point(0.34, 0.91), Art.Colors.PinLight, 0.19);
  Art.Quad(Point(0.75, 0), Point(0.77, 0), Point(0.60, 0.89), Point(0.55, 0.89), Art.Colors.PinLight, 0.12);
  Stroke(0, 0.93, 1, 0.93, 0.029, Stone);
end;

procedure DrawMarbleBackdrop(const Art: TMarbleStagePainter; Width, Height: Double);
var Backdrop: TBackdrop;
begin
  Backdrop.Art := Art;
  Backdrop.Width := Width;
  Backdrop.Height := Height;
  Backdrop.Gradient;
  case Art.Style of
    msWoodWorkshop: Backdrop.Workshop;
    msDeskCraft: Backdrop.Desk;
    msSteampunk: Backdrop.EngineRoom;
    msClearAcrylic: Backdrop.Showroom;
    msNeonArcade: Backdrop.Arcade;
    msColorToys: Backdrop.Playroom;
    msStoneRuins: Backdrop.Ruins;
  end;
end;

end.
