unit RhythmMarbleImages;
// 球の材質と回転位相ごとの画像を準備し、描画側と画像番号を共有する。
interface

uses RhythmImageBank, RhythmStyles;

const
  BallPhases = 16; // 主球の材質ごとに割り当てる回転位相の枚数。
  AuxiliaryGlassAsset = (Ord(High(TMarbleBallStyle)) + 1) * BallPhases; // 小球の画像番号。

// 球の画像バンクを作る。呼び出し側が描画器へ所有権を渡す。
function CreateMarbleImages: TAnimationImageBank;

implementation

uses System.SysUtils, System.Math, Vcl.Graphics;

type
  TMarbleImages = class(TAnimationImageBank)
  protected
    procedure PrepareImages; override;
  end;

procedure TMarbleImages.PrepareImages;
const Size = 128;
type TPixel = packed record B, G, R, A: Byte; end; // pf32bitの画素順。色成分はアルファ乗算済み。
var Material: TMarbleBallStyle; Bitmap: Vcl.Graphics.TBitmap; Pixels: ^TPixel; I, J, Asset, Alpha: Integer;
  X, Y, Z, Radius, Light, Glint, Rim, Bounce, Reflection, R, G, B, Phase, CosPhase, SinPhase, U, V, Pattern: Double;
begin
  // 反射は照明に固定し、材質の模様だけを球の回転に合わせる。
  for Asset := 0 to AuxiliaryGlassAsset do
  begin
    Material := mbGlass;
    if Asset <> AuxiliaryGlassAsset then Material := TMarbleBallStyle(Asset div BallPhases);
    Phase := 2 * Pi * (Asset mod BallPhases) / BallPhases;
    CosPhase := Cos(Phase);
    SinPhase := Sin(Phase);
    Bitmap := FImages[Asset];
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Size, Size);
    Bitmap.AlphaFormat := afPremultiplied;
    for J := 0 to Size - 1 do
    begin
      Pixels := Bitmap.ScanLine[J];
      Y := (J + 0.5 - Size * 0.5) / (Size * 0.49);
      for I := 0 to Size - 1 do
      begin
        X := (I + 0.5 - Size * 0.5) / (Size * 0.49);
        Radius := Hypot(X, Y);
        Alpha := Round(255 * EnsureRange((1 - Radius) * Size * 0.40 + 0.5, 0.0, 1.0));
        if Alpha = 0 then Pixels^ := Default(TPixel)
        else
        begin
          Z := Sqrt(Max(0.0, 1 - Sqr(Radius)));
          Light := Max(0.0, -0.42 * X - 0.55 * Y + 0.72 * Z);
          Glint := Power(EnsureRange(-0.37 * X - 0.49 * Y + 0.79 * Z, 0.0, 1.0), 54);
          Rim := Sqr(1 - Z);
          Bounce := Exp(-9 * (Sqr(X - 0.28) + Sqr(Y - 0.66)));
          U := X * CosPhase - Y * SinPhase;
          V := X * SinPhase + Y * CosPhase;
          case Material of
            mbSteel:
              begin
                Pattern := 22 * Power(EnsureRange(0.43 * U + 0.90 * Z, 0.0, 1.0), 17);
                Reflection := 0.44 + 0.25 * Tanh(-3.7 * (Y + 0.12 * X)) + 0.20 * Light + 0.18 * Bounce;
                R := 222 * Reflection + 90 * Glint + 38 * Rim * Light + Pattern;
                G := 237 * Reflection + 85 * Glint + 36 * Rim * Light + Pattern;
                B := 252 * Reflection + 76 * Glint + 30 * Rim * Light + Pattern;
              end;
            mbGlass:
              begin
                if Asset = AuxiliaryGlassAsset then
                begin
                  Reflection := Exp(-7.5 * (Sqr(X - 0.28) + Sqr(Y - 0.39))) * Z;
                  R := 11 + 40 * Light + 183 * Glint + 76 * Rim * Light + 80 * Bounce;
                  G := 57 + 71 * Light + 143 * Glint + 117 * Rim * Light + 84 * Bounce + 31 * Reflection;
                  B := 76 + 91 * Light + 118 * Glint + 138 * Rim * Light + 35 * Bounce + 69 * Reflection;
                end
                else
                begin
                  Pattern := Z * Exp(-18 * Sqr(U + 0.28 * Sin(4.5 * V + 2.0 * Z)));
                  R := 19 + 48 * Light + 191 * Glint + 78 * Bounce + 134 * Pattern;
                  G := 74 + 81 * Light + 139 * Glint + 101 * Bounce + 79 * Pattern;
                  B := 49 + 53 * Light + 157 * Glint + 49 * Bounce + 27 * Pattern;
                end;
                Alpha := Round(Alpha * (1 - 0.14 * Z * (1 - Glint)));
              end;
            mbWood:
              begin
                Pattern := Sin(24 * U + 2.3 * Sin(5 * V) + 5 * Sqr(V) + 2 * Z);
                Reflection := 0.44 + 0.53 * Light + 0.12 * Bounce;
                R := (205 + 22 * Pattern) * Reflection + 17 * Glint;
                G := (144 + 20 * Pattern) * Reflection + 14 * Glint;
                B := (82 + 15 * Pattern) * Reflection + 10 * Glint;
              end;
            mbPorcelain:
              begin
                Pattern := EnsureRange((Cos(18 * (V + 0.20 * U * Z)) - 0.40) * 3.5, 0.0, 1.0);
                Reflection := 0.50 + 0.48 * Light + 0.10 * Bounce;
                R := (248 - 191 * Pattern) * Reflection + 74 * Glint;
                G := (242 - 128 * Pattern) * Reflection + 74 * Glint;
                B := (229 - 25 * Pattern) * Reflection + 80 * Glint;
              end;
          else
            raise EArgumentOutOfRangeException.Create('Marble ball material');
          end;
          Pixels.A := Alpha;
          Pixels.R := Round(EnsureRange(R, 0.0, 255.0) * Alpha / 255);
          Pixels.G := Round(EnsureRange(G, 0.0, 255.0) * Alpha / 255);
          Pixels.B := Round(EnsureRange(B, 0.0, 255.0) * Alpha / 255);
        end;
        Inc(Pixels);
      end;
    end;
  end;
end;

function CreateMarbleImages: TAnimationImageBank;
begin
  Result := TMarbleImages.Create(AuxiliaryGlassAsset + 1);
end;

end.
