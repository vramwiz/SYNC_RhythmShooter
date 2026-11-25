unit RhythmTrainArt;
{$POINTERMATH ON}
{$R RhythmTrainArt.res}

interface

uses System.Types,RhythmImageBank;

const
  TrainArtRoutes = 4;
  TrainArtLayers = 5;
  TrainArtCars = 3;
  TrainArtRoles = 4;
  TrainArtCell = 160;
  TrainArtFeetX = 72;
  TrainArtFeetY = 144;
  TrainArtRailY = 494;
  TrainArtCarRoofY = 16;
  TrainArtCarRailY = 182;
  TrainArtBgWidth = 960;
  TrainArtBgHeight = 540;
  TrainArtCarWidth = 768;
  TrainArtCarHeight = 192;
type
  TTrainArtClip = (taIdle,taWalk,taPunch,taKick,taSpecial,taDuck,taImpact,taLand);

function CreateTrainArtImages: TAnimationImageBank;
function TrainArtAvailable(Bank: TAnimationImageBank): Boolean;
function TrainArtBackground(Route,Layer: Integer): Integer;
function TrainArtVehicle(Car: Integer; Lit: Boolean): Integer;
function TrainArtAtlas(Role: Integer; Clip: TTrainArtClip): Integer;
function TrainArtSample(Clip: TTrainArtClip; Phase: Double): Integer;
function TrainArtStride(Role: Integer): Double;
function TrainArtLowPhase(Crouch,Slide: Double; Grounded: Boolean; out Phase: Double): Boolean;
function TrainScarfRoot(Clip: TTrainArtClip; Sample: Integer): TPointF;
function TrainScarfPoint(U,Time,Wind: Double): TPointF;

implementation

uses System.Classes,System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics,Vcl.Imaging.pngimage;

const
  CarBase = TrainArtRoutes*TrainArtLayers;
  AtlasBase = CarBase+2*TrainArtCars;
  SlotCount = AtlasBase+2*TrainArtRoles;
  OneShots: array[0..11] of Double =
    (0,0.1,0.2,0.3,0.4,0.46,0.5,0.55,0.62,0.72,0.85,1.0);

type
  TTrainArtBank = class(TAnimationImageBank)
  protected
    procedure PrepareImages; override;
  public
    constructor Create;
  end;

constructor TTrainArtBank.Create;
begin
  inherited Create(SlotCount);
end;

procedure LoadHalfPng(const ResourceName: string; Target: Vcl.Graphics.TBitmap; W,H: Integer);
var
  S: TResourceStream;
  Png: TPngImage;
  C0,C1,A0,A1,Dest: PByte;
  X,Y,K,T0,T1,A,B,C,D: Integer;
begin
  S := TResourceStream.Create(HInstance,ResourceName,RT_RCDATA);
  try
    Png := TPngImage.Create;
    try
      Png.LoadFromStream(S);
      if (Png.Width<>W*2) or (Png.Height<>H*2) or (Png.Header.ColorType<>COLOR_RGBALPHA) then
        raise EReadError.Create('Invalid train art dimensions or format');
      Target.PixelFormat := pf32bit;
      Target.SetSize(W,H);
      Target.AlphaFormat := afPremultiplied;
      for Y := 0 to H-1 do begin
        C0 := Png.Scanline[Y*2];
        C1 := Png.Scanline[Y*2+1];
        A0 := PByte(Png.AlphaScanline[Y*2]);
        A1 := PByte(Png.AlphaScanline[Y*2+1]);
        if (A0=nil) or (A1=nil) then raise EReadError.Create('Missing train alpha');
        Dest := Target.ScanLine[Y];
        for X := 0 to W-1 do begin
          A := A0[0]; B := A0[1]; C := A1[0]; D := A1[1];
          for K := 0 to 2 do begin
            T0 := C0[K]*A+C0[3+K]*B;
            T1 := C1[K]*C+C1[3+K]*D;
            Dest[K] := (T0+T1+510) div 1020;
          end;
          Dest[3] := (A+B+C+D+2) div 4;
          Inc(C0,6); Inc(C1,6); Inc(A0,2); Inc(A1,2); Inc(Dest,4);
        end;
      end;
    finally Png.Free;end;
  finally S.Free;end;
end;

procedure TTrainArtBank.PrepareImages;
var I,W,H: Integer;
begin
  try
    for I := 0 to SlotCount-1 do begin
      if I<CarBase then begin W := TrainArtBgWidth; H := TrainArtBgHeight; end
      else if I<AtlasBase then begin W := TrainArtCarWidth; H := TrainArtCarHeight; end
      else begin W := 6*TrainArtCell; H := 8*TrainArtCell; end;
      LoadHalfPng('TR_ART_'+IntToStr(I),FImages[I],W,H);
    end;
  except
    // An absent or malformed resource must not turn a scene into partial art.
    for I := 0 to SlotCount-1 do FImages[I].SetSize(0,0);
  end;
end;

function CreateTrainArtImages: TAnimationImageBank;
begin
  Result := TTrainArtBank.Create;
end;

function TrainArtAvailable(Bank: TAnimationImageBank): Boolean;
begin
  Result := (Bank is TTrainArtBank) and (Bank.ImageCount=SlotCount);
end;

function TrainArtBackground(Route,Layer: Integer): Integer;
begin
  Result := (Route mod TrainArtRoutes)*TrainArtLayers+Layer;
end;

function TrainArtVehicle(Car: Integer; Lit: Boolean): Integer;
begin
  Result := CarBase+(Car mod TrainArtCars)*2+Ord(Lit);
end;

function TrainArtAtlas(Role: Integer; Clip: TTrainArtClip): Integer;
begin
  Result := AtlasBase+EnsureRange(Role,0,TrainArtRoles-1)*2+Ord(Clip) div 4;
end;

function TrainArtSample(Clip: TTrainArtClip; Phase: Double): Integer;
begin
  if Clip in [taIdle,taWalk] then Exit(Min(11,Floor(12*(Phase-Floor(Phase))+1E-8)));
  Result := 11;
  while (Result>0) and (Phase+1E-8<OneShots[Result]) do Dec(Result);
end;

function TrainArtStride(Role: Integer): Double;
const Strides: array[0..3] of Double = (38.0,31.62,34.24,42.435);
begin
  Result := Strides[EnsureRange(Role,0,TrainArtRoles-1)];
end;

function TrainArtLowPhase(Crouch,Slide: Double; Grounded: Boolean; out Phase: Double): Boolean;
begin
  // Slides and tall/short crouches use the same authored low silhouette, regardless of overlapping attack.
  Phase := 0.5*EnsureRange(Max(Crouch/0.88,Slide),0.0,1.0);
  Result := Grounded and (Phase>0.0125);
end;

function TrainScarfRoot(Clip: TTrainArtClip; Sample: Integer): TPointF;
const
  Roots: array[TTrainArtClip,0..11,0..1] of Single = {$I RhythmTrainScarfAnchors.inc};
begin
  Result := PointF(Roots[Clip,Sample,0],Roots[Clip,Sample,1]);
end;

function TrainScarfPoint(U,Time,Wind: Double): TPointF;
var Flare,Spread,Rate: Double;
begin
  U := EnsureRange(U,0.0,1.0);
  Wind := EnsureRange(Wind,0.0,1.0);
  Spread := Wind*Wind*(3-2*Wind);
  Rate := Time*8.1;
  // The hanging tail follows gravity. Only movement contributes a traveling ripple.
  Flare := 2.8*Spread*Sqr(U)*Sin(Rate-4.9*U);
  Result := PointF((-5.5*Sin(Pi*U)+4*Sqr(U))*(1-Spread)-36*U*Spread,
    (47*(1-Spread)+36*Spread)*U+Flare);
end;

end.
