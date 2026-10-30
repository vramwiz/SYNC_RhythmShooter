unit RhythmShootingAssets;
interface
uses RhythmImageBank;
type
  TShootingImageBank=class(TAnimationImageBank)
  private
    procedure BrightenStandardEnemies;
  protected
    procedure PrepareImages;override;
    function UsesAlpha(Index:Integer):Boolean;override;
  public
    constructor Create;
  end;
implementation
uses System.SysUtils,System.Math,Vcl.Graphics,RhythmDesignTypes;
constructor TShootingImageBank.Create;
var Specs:array[0..RHYTHM_DESIGN_COUNT-1] of TAnimationAssetSpec;I:Integer;
begin
  for I:=0 to High(Specs) do begin Specs[I].Name:=DesignInfo(I).Id;Specs[I].Title:=DesignInfo(I).Title;Specs[I].Opaque:=I in [0,3];end;
  inherited Create(Specs,24);
end;
procedure TShootingImageBank.PrepareImages;
const Originals:array[0..5] of Integer=(8,9,10,11,13,14);
  Upward:array[0..2] of Integer=(8,13,14);
var I:Integer;
begin
  BrightenStandardEnemies;
  for I:=0 to High(Originals) do RotateImage(Originals[I],15+I,1);
  for I:=0 to High(Upward) do RotateImage(Upward[I],21+I,2);
end;
function TShootingImageBank.UsesAlpha(Index:Integer):Boolean;
begin Result:=Index in [8,11,12,13,14,15,18,19,20,21,22,23];end;

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
