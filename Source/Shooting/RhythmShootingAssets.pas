unit RhythmShootingAssets;
interface
uses RhythmImageBank;

// Private render slots. The 15 public custom-design IDs remain unchanged.
const SHOOT_BOSS_BULLET_FIRST=24;SHOOT_BOSS_BULLET_LAST=27;SHOOT_FLASH=28;SHOOT_SHOCKWAVE=29;
  SHOOT_SPARK=30;SHOOT_SMOKE=31;SHOOT_EMBER=32;
type
  TShootingImageBank=class(TAnimationImageBank)
  private
    procedure BrightenStandardEnemies;
    procedure PrepareStandardEffects;
  protected
    procedure PrepareImages;override;
    function UsesAlpha(Index:Integer):Boolean;override;
  public
    constructor Create;
  end;
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics,RhythmDesignTypes;
constructor TShootingImageBank.Create;
var Specs:array[0..RHYTHM_DESIGN_COUNT-1] of TAnimationAssetSpec;I:Integer;
begin
  for I:=0 to High(Specs) do begin Specs[I].Name:=DesignInfo(I).Id;Specs[I].Title:=DesignInfo(I).Title;Specs[I].Opaque:=I in [0,3];end;
  inherited Create(Specs,SHOOT_EMBER+1);
end;
procedure TShootingImageBank.PrepareImages;
const Originals:array[0..5] of Integer=(8,9,10,11,13,14);
  Upward:array[0..2] of Integer=(8,13,14);
var I:Integer;
begin
  BrightenStandardEnemies;
  PrepareStandardEffects;
  for I:=0 to High(Originals) do RotateImage(Originals[I],15+I,1);
  for I:=0 to High(Upward) do RotateImage(Upward[I],21+I,2);
end;
function TShootingImageBank.UsesAlpha(Index:Integer):Boolean;
begin Result:=Index in [8,11,12,13,14,15,18,19,20,21,22,23,SHOOT_BOSS_BULLET_FIRST..SHOOT_EMBER];end;

procedure TShootingImageBank.PrepareStandardEffects;
  procedure Paint(Index,Kind:Integer;Tint:TColor);
  var Bitmap:Vcl.Graphics.TBitmap;Pixel:PByte;X,Y,W,V:Integer;
    Uv,Vv,R,D,Q,Edge,Angle,A,Light,Red,Green,Blue,TR,TG,TB:Double;
  begin
    W:=64;if Kind in [3,4] then W:=128 else if Kind=6 then W:=96 else if Kind in [5,7] then W:=32;
    Bitmap:=FImages[Index];Bitmap.Transparent:=False;Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(W,W);
    // Set the format before filling: VCL otherwise premultiplies an existing DIB.
    Bitmap.AlphaFormat:=afPremultiplied;FColorKeys[Index]:=False;
    V:=ColorToRGB(Tint);TR:=V and 255;TG:=(V shr 8) and 255;TB:=(V shr 16) and 255;
    for Y:=0 to W-1 do begin
      Pixel:=Bitmap.ScanLine[Y];Vv:=2*(Y+0.5)/W-1;
      for X:=0 to W-1 do begin
        Uv:=2*(X+0.5)/W-1;R:=Sqrt(Uv*Uv+Vv*Vv);
        Red:=TR;Green:=TG;Blue:=TB;A:=0;
        case Kind of
          0:begin // Narrow forward lance, cool glow and a white centre.
            D:=Sqrt(Uv*Uv+Sqr(Max(0.0,Abs(Vv)-0.56)));
            A:=0.35*Sqr(Max(0.0,1-D/0.36));
            if D<0.16 then A:=Max(A,0.90);
            if D<0.075 then begin Red:=240;Green:=255;Blue:=255;A:=1;end;
          end;
          1:begin // Round hostile orb: coloured edge, dark rim and hot core.
            A:=0.26*Sqr(EnsureRange((0.98-R)/0.40,0.0,1.0));
            if R<0.86 then A:=Max(A,0.75);
            if R<0.72 then begin Red:=TR*0.43;Green:=TG*0.43;Blue:=TB*0.43;A:=0.96;end;
            if R<0.60 then begin Red:=TR;Green:=TG;Blue:=TB;A:=1;end;
            if R<0.24 then begin Red:=245;Green:=250;Blue:=231;A:=1;end;
          end;
          2:begin // Short-lived flash with a small cross-shaped glint.
            D:=Min(Abs(Uv),Abs(Vv));
            A:=Max(0.9*Power(Max(0.0,1-R/0.92),1.2),
              0.65*Max(0.0,1-D/0.07)*Max(0.0,1-R));
            if R<0.23 then A:=1;
          end;
          3:begin // Irregular fire lobe rather than a flat circular stamp.
            Angle:=ArcTan2(Vv,Uv);Edge:=0.76+0.09*Sin(5*Angle)+0.045*Sin(11*Angle);
            Q:=R/Edge;A:=EnsureRange((1-Q)*4,0.0,1.0);Light:=EnsureRange(Q,0.0,1.0);
            Red:=255-32*Light;Green:=246-178*Power(Light,0.75);Blue:=185-160*Light;
          end;
          4:begin
            D:=Abs(R-0.78);A:=0.9*Power(Max(0.0,1-D/0.14),1.5);
          end;
          5:begin
            D:=Abs(Uv)+Abs(Vv);A:=EnsureRange((1-D)*4,0.0,1.0);
            Light:=Max(0.0,1-D*2);Red:=TR+(255-TR)*Light;Green:=TG+(252-TG)*Light;Blue:=TB+(215-TB)*Light;
          end;
          6:begin
            Angle:=ArcTan2(Vv,Uv);Edge:=0.82+0.07*Sin(3*Angle)+0.04*Cos(7*Angle);
            A:=0.52*Sqr(Max(0.0,1-Sqr(R/Edge)));
          end;
          7:begin
            A:=0.9*Power(Max(0.0,1-R/0.9),1.8);
          end;
        end;
        A:=EnsureRange(A,0.0,1.0);
        Pixel[0]:=Round(EnsureRange(Blue,0.0,255.0)*A);
        Pixel[1]:=Round(EnsureRange(Green,0.0,255.0)*A);
        Pixel[2]:=Round(EnsureRange(Red,0.0,255.0)*A);
        Pixel[3]:=Round(255*A);Inc(Pixel,4);
      end;
    end;
  end;
begin
  // Factory defaults are rebuilt in memory only; custom pixels and disk assets
  // are never painted over. Extra slots have no public design IDs or JSON data.
  if not FCustom[11] then Paint(11,0,RGB(77,218,255));
  if not FCustom[12] then Paint(12,3,RGB(255,174,61));
  // Same order as the explicit bpPetals/bpSpiral/bpFans/bpCross scene mapping.
  Paint(SHOOT_BOSS_BULLET_FIRST,1,RGB(255,112,156));
  Paint(SHOOT_BOSS_BULLET_FIRST+1,1,RGB(174,139,255));
  Paint(SHOOT_BOSS_BULLET_FIRST+2,1,RGB(255,190,72));
  Paint(SHOOT_BOSS_BULLET_FIRST+3,1,RGB(126,232,121));
  Paint(SHOOT_FLASH,2,RGB(255,248,213));
  Paint(SHOOT_SHOCKWAVE,4,RGB(255,192,96));
  Paint(SHOOT_SPARK,5,RGB(255,184,75));
  Paint(SHOOT_SMOKE,6,RGB(130,120,127));
  Paint(SHOOT_EMBER,7,RGB(255,155,54));
end;


procedure TShootingImageBank.BrightenStandardEnemies;
const Originals:array[0..4] of Integer=(8,9,10,13,14);
  // RGB shadow / main armor / lit armor for fighter, drone, interceptor.
  // Colored seams and broad midtones survive the tiny flyby display size.
  Armor:array[0..2,0..2,0..2] of Byte=(
    ((128,71,88),(238,137,158),(250,187,200)),
    ((102,78,145),(193,151,231),(229,196,250)),
    ((133,99,49),(239,185,86),(250,214,135)));
var I,X,Y,R,G,B,Luma,Peak,Lift,Kind,LowTone,HighTone,Weight,Scale,Channel:Integer;
  Bitmap:Vcl.Graphics.TBitmap;Pixel:PByte;
begin
  // Correct factory artwork once per disk load, before directional/alpha copies.
  // Small enemies need colored faces, while bosses retain their accepted curve.
  // Object-specific images keep their colors, including their original seams.
  for I in Originals do begin
    if FCustom[I] then Continue;
    Kind:=-1;if I=8 then Kind:=0 else if I=13 then Kind:=1 else if I=14 then Kind:=2;
    Bitmap:=FImages[I];if Bitmap.Empty then Continue;
    Bitmap.PixelFormat:=pf24bit;
    for Y:=0 to Bitmap.Height-1 do begin
      Pixel:=Bitmap.ScanLine[Y];
      for X:=0 to Bitmap.Width-1 do begin
        B:=Pixel[0];G:=Pixel[1];R:=Pixel[2];
        // Preserve the transparent key and existing bright emissive pixels.
        if not ((R=255) and (G=0) and (B=255)) then begin
          Luma:=(54*R+183*G+19*B) shr 8;Peak:=Max(R,Max(G,B));
          if Kind>=0 then begin
            // Consolidate dark plating and near-black outlines into the same
            // colored armor family; do not brighten only the tiny glowing core.
            // Keep the factory cyan reactor/exhaust colors as emissive accents.
            if (Peak<224) and not ((G>=140) and (B>=160) and (G-R>=40) and (B-R>=60)) then begin
              if Luma<152 then begin
                if Luma<=24 then begin LowTone:=0;HighTone:=0;Weight:=0;Scale:=1;end
                else if Luma<80 then begin LowTone:=0;HighTone:=1;Weight:=Luma-24;Scale:=56;end
                else begin LowTone:=1;HighTone:=2;Weight:=Luma-80;Scale:=72;end;
                for Channel:=0 to 2 do
                  Pixel[2-Channel]:=(Integer(Armor[Kind,LowTone,Channel])*(Scale-Weight)+
                    Integer(Armor[Kind,HighTone,Channel])*Weight) div Scale;
              end else if Luma<208 then begin
                // Join the lit armor back to the source highlights smoothly.
                Weight:=208-Luma;
                for Channel:=0 to 2 do
                  Pixel[2-Channel]:=(Integer(Armor[Kind,2,Channel])*Weight+
                    Integer(Pixel[2-Channel])*(56-Weight)) div 56;
              end;
            end;
          end else if (Luma>=24) and (Luma<184) and (Peak<224) then begin
            if Luma<=96 then Lift:=12+(Luma-24)*40 div 72
            else Lift:=(184-Luma)*52 div 88;
            Lift:=Min(Lift,224-Peak);
            Pixel[0]:=B+Lift;Pixel[1]:=G+Lift;Pixel[2]:=R+Lift;
          end;
        end;
        Inc(Pixel,3);
      end;
    end;
  end;
end;
end.
