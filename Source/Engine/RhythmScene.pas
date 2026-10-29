unit RhythmScene;

interface

uses System.Types, Vcl.Graphics, RhythmAudio, RhythmD2D, RhythmMotion, RhythmBarrage,RhythmDesignTypes;

type
  TRhythmPoint = RhythmMotion.TRhythmPoint;
  TRhythmRenderer = class
  private
    FAssets: array[0..23] of TBitmap;
    FAlphaAssets: array[0..23] of TBitmap;
    FScaled: array[0..23,0..2] of TBitmap;
    FD2D:TRhythmD2D;
    FD2DActive,FUseD2D,FLastD2D:Boolean;
    FAssetCount: Integer;
    FBarrage:TArray<TRhythmEnemyBullet>;
    FFlybys:TArray<TRhythmFlyby>;
    FPlanKey:string;
    FTransform:TBitmap;
    FDesignKey,FDesignWarning:string;
    FCustom:array[0..14] of Boolean;
    function MapPoint(const P: TRhythmPoint; Width,Height,Direction: Integer): TPoint;
    procedure PrepareAlphaAssets;
    procedure BrightenStandardEnemies;
    procedure PrepareUpwardEnemies;
    procedure Sprite(Canvas: TCanvas; Index: Integer; const P: TRhythmPoint;
      Size: Double; Width,Height,Direction: Integer;Opacity:Double=1);
    procedure Explosion(Canvas:TCanvas;const P:TRhythmPoint;Age:Double;Boss:Boolean;Width,Height,Direction:Integer);
    procedure Background(Canvas: TCanvas; Time: Double; Width,Height,Direction: Integer;OnlyLayer:Integer=-1);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ApplyDesigns(const Designs:TRhythmDesigns;Force:Boolean=False);
    procedure StandardBackgroundPreview(Target:TBitmap;Direction,Layer:Integer);
    property DesignWarning:string read FDesignWarning;
    procedure Render(Target: TBitmap; Audio: TRhythmAudio; Time: Double;
      Direction: Integer; const MessageText: string = '';Zoom:Double=1;OffsetX:Double=0;OffsetY:Double=0);
    property AssetCount: Integer read FAssetCount;
    property UseD2D:Boolean read FUseD2D write FUseD2D;
    property LastUsedD2D:Boolean read FLastD2D;
  end;

function PlayerAt(Time: Double): TRhythmPoint;
function EnemyAt(const Hit: TRhythmHit; Time: Double): TRhythmPoint;
function BulletAt(const Hit: TRhythmHit; Time: Double): TRhythmPoint;
function ExplosionOpacity(Age,Lifetime:Double):Double;

implementation

uses System.SysUtils, System.Math, System.IOUtils, Winapi.Windows, RhythmPaths,RhythmStage,RhythmDesignImages;

function PlayerAt(Time: Double): TRhythmPoint;
begin
  Result:=RhythmMotion.PlayerAt(Time);
end;

function EnemyAt(const Hit: TRhythmHit; Time: Double): TRhythmPoint;
var Age,Ease,TargetX: Double;
begin
  Age := EnsureRange((Time - Hit.Time + 1.6)/1.6,0.0,1.0);
  TargetX:=PlayerAt(Hit.Time-Hit.Flight).X;Ease:=Age*Age*(3-2*Age);
  Result.X := Hit.Lane*(1-Ease)+TargetX*Ease+0.07*Sin(Age*Pi)*(1-Age);
  Result.Y := -0.12 + Age * (ImpactPoint(Hit.Lane,Hit.Strength).Y+0.12);
end;

function BulletAt(const Hit: TRhythmHit; Time: Double): TRhythmPoint;
begin
  Result:=PlayerShotAt(psForward,Hit.Time,Hit.Flight,ImpactPoint(Hit.Lane,Hit.Strength).Y,Time);
end;

function ExplosionOpacity(Age,Lifetime:Double):Double;
begin
  if (Age<0) or (Lifetime<=0) or (Age>=Lifetime) then Exit(0);
  Result:=Power(1-Age/Lifetime,1.5);
end;

procedure TRhythmRenderer.BrightenStandardEnemies;
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
    Bitmap:=FAssets[I];if Bitmap.Empty then Continue;
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

procedure TRhythmRenderer.PrepareUpwardEnemies;
const Originals:array[0..2] of Integer=(8,13,14);
var I,X,Y:Integer;Source,Rotated:Vcl.Graphics.TBitmap;P,Q:PByte;
begin
  for I:=0 to 2 do begin
    Source:=FAssets[Originals[I]];FreeAndNil(FAssets[21+I]);Rotated:=Vcl.Graphics.TBitmap.Create;FAssets[21+I]:=Rotated;
    if Source.Empty then Continue;
    if Source.AlphaFormat=afIgnored then begin
      Rotated.PixelFormat:=pf24bit;Rotated.SetSize(Source.Width,Source.Height);
      for Y:=0 to Source.Height-1 do for X:=0 to Source.Width-1 do Rotated.Canvas.Pixels[Source.Width-1-X,Source.Height-1-Y]:=Source.Canvas.Pixels[X,Y];
      Rotated.TransparentColor:=clFuchsia;Rotated.Transparent:=True;
    end else begin
      Rotated.PixelFormat:=pf32bit;Rotated.SetSize(Source.Width,Source.Height);Rotated.AlphaFormat:=afPremultiplied;
      for Y:=0 to Source.Height-1 do begin P:=Source.ScanLine[Y];Q:=Rotated.ScanLine[Source.Height-1-Y];
        for X:=0 to Source.Width-1 do begin Move(P^,PByte(NativeUInt(Q)+NativeUInt((Source.Width-1-X)*4))^,4);Inc(P,4);end;
      end;
    end;
  end;
end;
procedure TRhythmRenderer.PrepareAlphaAssets;
var I,X,Y,A:Integer;Temp:Vcl.Graphics.TBitmap;P,Q:PByte;Premultiplied,HasAlpha:Boolean;
begin
  PrepareUpwardEnemies;
  Temp:=Vcl.Graphics.TBitmap.Create;
  try
    for I:=0 to High(FAssets) do
    begin
      FreeAndNil(FAlphaAssets[I]);FAlphaAssets[I]:=Vcl.Graphics.TBitmap.Create;
      if FAssets[I].Empty or not (I in [8,11,12,13,14,15,18,19,20,21,22,23]) then Continue;
      HasAlpha:=FAssets[I].AlphaFormat<>afIgnored;
      Premultiplied:=FAssets[I].AlphaFormat=afPremultiplied;
      Temp.Assign(FAssets[I]);Temp.PixelFormat:=pf32bit;
      FAlphaAssets[I].PixelFormat:=pf32bit;FAlphaAssets[I].SetSize(Temp.Width,Temp.Height);
      FAlphaAssets[I].AlphaFormat:=afPremultiplied;
      for Y:=0 to Temp.Height-1 do
      begin
        P:=Temp.ScanLine[Y];Q:=FAlphaAssets[I].ScanLine[Y];
        for X:=0 to Temp.Width-1 do
        begin
          if HasAlpha then A:=P[3]
          else if (I<>0) and (I<>3) and (P[0]=255) and (P[1]=0) and (P[2]=255) then A:=0
          else A:=255;
          if Premultiplied then begin Q[0]:=P[0];Q[1]:=P[1];Q[2]:=P[2];end
          else begin Q[0]:=P[0]*A div 255;Q[1]:=P[1]*A div 255;Q[2]:=P[2]*A div 255;end;
          Q[3]:=A;Inc(P,4);Inc(Q,4);
        end;
      end;
    end;
  finally Temp.Free;end;
end;

constructor TRhythmRenderer.Create;
const Names: array[0..14] of string = ('vertical_layer0','vertical_layer1','vertical_layer2',
  'horizontal_layer0','horizontal_layer1','horizontal_layer2','player_vertical','player_horizontal',
  'enemy','boss0','boss1','bullet','explosion','enemy1','enemy2');
  RotateIndices:array[0..5] of Integer=(8,9,10,11,13,14);
var I,J,X,Y: Integer; Path: string;Source,Rotated:Vcl.Graphics.TBitmap;
begin
  inherited;
  FTransform:=Vcl.Graphics.TBitmap.Create;FTransform.PixelFormat:=pf32bit;
  for I:=0 to High(FAssets) do
  begin
    FAssets[I]:=Vcl.Graphics.TBitmap.Create;
    for J:=0 to 2 do FScaled[I,J]:=Vcl.Graphics.TBitmap.Create;
    if I>High(Names) then Continue;
    Path:=TPath.Combine(AssetFolder,Names[I]+'.bmp');
    if FileExists(Path) then
    begin
      FAssets[I].LoadFromFile(Path); Inc(FAssetCount);
      FAssets[I].Transparent := I mod 3 <> 0;
      if I>=6 then FAssets[I].Transparent:=True;
      FAssets[I].TransparentColor:=clFuchsia;
    end;
  end;
  BrightenStandardEnemies;
  for I:=0 to High(RotateIndices) do
  begin
    Source:=FAssets[RotateIndices[I]];Rotated:=FAssets[15+I];
    if Source.Empty then Continue;
    Rotated.PixelFormat:=pf24bit;Rotated.SetSize(Source.Height,Source.Width);
    for Y:=0 to Source.Height-1 do for X:=0 to Source.Width-1 do
      Rotated.Canvas.Pixels[Source.Height-1-Y,X]:=Source.Canvas.Pixels[X,Y];
    Rotated.TransparentColor:=clFuchsia;Rotated.Transparent:=True;
  end;
  PrepareAlphaAssets;
  try FD2D:=TRhythmD2D.Create(FAssets);FUseD2D:=True;except FD2D:=nil;FUseD2D:=False;end;
end;

destructor TRhythmRenderer.Destroy;
var B: Vcl.Graphics.TBitmap;I,J:Integer;
begin
  FTransform.Free;FD2D.Free;for B in FAssets do B.Free;for B in FAlphaAssets do B.Free;
  for I:=0 to High(FScaled) do for J:=0 to 2 do FScaled[I,J].Free;
  inherited;
end;

procedure TRhythmRenderer.ApplyDesigns(const Designs:TRhythmDesigns;Force:Boolean);
const RotateIndices:array[0..5] of Integer=(8,9,10,11,13,14);
var Key,Path:string;I,J,X,Y:Integer;Loaded,Source,Rotated:Vcl.Graphics.TBitmap;P,Q:PByte;
begin
  Key:=DesignKey(Designs);if (Key=FDesignKey) and not Force then Exit;
  FDesignWarning:='';
  for I:=0 to 14 do begin
    FCustom[I]:=False;FAssets[I].Free;FAssets[I]:=Vcl.Graphics.TBitmap.Create;
    if Designs[I].Path<>'' then try
      Path:=ResolveDesignImage(Designs[I]);Loaded:=ReadDesignBitmap(Path);
      FAssets[I].Free;FAssets[I]:=Loaded;FCustom[I]:=True;
    except on E:Exception do FDesignWarning:=FDesignWarning+DesignInfo(I).Title+': '+E.Message+' ';end;
    if not FCustom[I] then begin
      Path:=TPath.Combine(AssetFolder,DesignInfo(I).Id+'.bmp');
      if FileExists(Path) then FAssets[I].LoadFromFile(Path);
      FAssets[I].Transparent:=(I>=6) or (I mod 3<>0);FAssets[I].TransparentColor:=clFuchsia;
    end;
  end;
  BrightenStandardEnemies;
  for I:=0 to High(RotateIndices) do begin
    Source:=FAssets[RotateIndices[I]];Rotated:=FAssets[15+I];Rotated.Free;Rotated:=Vcl.Graphics.TBitmap.Create;FAssets[15+I]:=Rotated;
    if Source.Empty then Continue;
    if Source.AlphaFormat=afIgnored then begin
      Rotated.PixelFormat:=pf24bit;Rotated.SetSize(Source.Height,Source.Width);
      for Y:=0 to Source.Height-1 do for X:=0 to Source.Width-1 do Rotated.Canvas.Pixels[Source.Height-1-Y,X]:=Source.Canvas.Pixels[X,Y];
      Rotated.TransparentColor:=clFuchsia;Rotated.Transparent:=True;
    end else begin
      Rotated.PixelFormat:=pf32bit;Rotated.SetSize(Source.Height,Source.Width);Rotated.AlphaFormat:=afPremultiplied;
      for Y:=0 to Source.Height-1 do begin P:=Source.ScanLine[Y];for X:=0 to Source.Width-1 do begin
        Q:=Rotated.ScanLine[X];Inc(Q,(Source.Height-1-Y)*4);Move(P^,Q^,4);Inc(P,4);
      end;end;
    end;
  end;
  for I:=0 to High(FScaled) do for J:=0 to 2 do begin FScaled[I,J].Free;FScaled[I,J]:=Vcl.Graphics.TBitmap.Create;end;
  PrepareAlphaAssets;
  FreeAndNil(FD2D);try FD2D:=TRhythmD2D.Create(FAssets);except FUseD2D:=False;end;
  FDesignKey:=Key;
end;
procedure TRhythmRenderer.StandardBackgroundPreview(Target:Vcl.Graphics.TBitmap;Direction,Layer:Integer);
var Active:Boolean;SavedCustom:array[0..14] of Boolean;
begin
  Active:=FD2DActive;Move(FCustom,SavedCustom,SizeOf(FCustom));FD2DActive:=False;FillChar(FCustom,SizeOf(FCustom),0);
  try Background(Target.Canvas,0,Target.Width,Target.Height,Direction,Layer);
  finally Move(SavedCustom,FCustom,SizeOf(FCustom));FD2DActive:=Active;end;
end;

function TRhythmRenderer.MapPoint(const P: TRhythmPoint; Width,Height,Direction: Integer): TPoint;
begin
  if Direction=0 then Result:=Point(Round(P.X*Width),Round(P.Y*Height))
  else Result:=Point(Round((1-P.Y)*Width),Round(P.X*Height));
end;

procedure TRhythmRenderer.Sprite(Canvas:TCanvas;Index:Integer;const P:TRhythmPoint;
  Size:Double;Width,Height,Direction:Integer;Opacity:Double);
var Center:TPoint; W,H,Bucket,Swap:Integer;Scaled:Vcl.Graphics.TBitmap;Blend:TBlendFunction;
begin
  if Opacity<=0 then Exit;Opacity:=Min(1.0,Opacity);
  Center:=MapPoint(P,Width,Height,Direction);
  // Keep arbitrary custom ship silhouettes inside the existing avoidance
  // corridor, including opaque square imports. Default artwork is unchanged.
  if Index in [6,7] then if FCustom[Index] then Size:=Size*0.8;
  W:=Max(2,Round(Size*Min(Width,Height))); H:=W;
  if Index in [9,10] then W:=W*8 div 5;
  if Direction=1 then
  begin
    case Index of 8:Index:=15;9:Index:=16;10:Index:=17;11:Index:=18;13:Index:=19;14:Index:=20;end;
    if Index>=15 then begin Swap:=W;W:=H;H:=Swap;end;
  end;
  if FD2DActive then begin FD2D.DrawAsset(Index,Rect(Center.X-W div 2,Center.Y-H div 2,Center.X+W div 2,Center.Y+H div 2),Opacity);Exit;end;
  if ((Opacity<1) or (Index=12)) and not FAlphaAssets[Index].Empty then
  begin
    Blend.BlendOp:=AC_SRC_OVER;Blend.BlendFlags:=0;Blend.SourceConstantAlpha:=Round(Opacity*255);Blend.AlphaFormat:=AC_SRC_ALPHA;
    Winapi.Windows.AlphaBlend(Canvas.Handle,Center.X-W div 2,Center.Y-H div 2,W,H,
      FAlphaAssets[Index].Canvas.Handle,0,0,FAlphaAssets[Index].Width,FAlphaAssets[Index].Height,Blend);Exit;
  end;
  if not FAssets[Index].Empty then
  begin
    if Index=12 then
      Canvas.StretchDraw(Rect(Center.X-W div 2,Center.Y-H div 2,Center.X+W div 2,Center.Y+H div 2),FAssets[Index])
    else
    begin
      Bucket:=0;if (Index in [11,18]) and (Size>0.025) then Bucket:=1;
      if (Index in [11,18]) and (Size>0.04) then Bucket:=2;
      Scaled:=FScaled[Index,Bucket];
      if (Scaled.Width<>W) or (Scaled.Height<>H) then
      begin
        if FAssets[Index].AlphaFormat<>afIgnored then begin
          Scaled.PixelFormat:=pf32bit;Scaled.SetSize(W,H);Scaled.AlphaFormat:=afPremultiplied;
          for Swap:=0 to H-1 do FillChar(Scaled.ScanLine[Swap]^,W*4,0);
          Scaled.Canvas.StretchDraw(Rect(0,0,W,H),FAssets[Index]);
        end else begin
          Scaled.PixelFormat:=pf24bit;Scaled.SetSize(W,H);Scaled.Transparent:=False;
          Scaled.Canvas.Brush.Color:=clFuchsia;Scaled.Canvas.FillRect(Rect(0,0,W,H));
          Scaled.Canvas.StretchDraw(Rect(0,0,W,H),FAssets[Index]);
          Scaled.TransparentColor:=clFuchsia;Scaled.Transparent:=True;
        end;
      end;
      Canvas.Draw(Center.X-W div 2,Center.Y-H div 2,Scaled);
    end;
  end
  else begin Canvas.Brush.Color:=clAqua;Canvas.Ellipse(Center.X-W div 2,Center.Y-H div 2,Center.X+W div 2,Center.Y+H div 2);end;
end;

procedure TRhythmRenderer.Explosion(Canvas:TCanvas;const P:TRhythmPoint;Age:Double;Boss:Boolean;Width,Height,Direction:Integer);
var Lifetime,LocalAge,Size,Alpha:Double;I:Integer;Burst:TRhythmPoint;
begin
  if Boss then begin Lifetime:=1.35;Size:=0.16+Age*0.20;end
  else begin Lifetime:=0.60;Size:=0.04+Age*0.18;end;
  Alpha:=ExplosionOpacity(Age,Lifetime);if Alpha<=0 then Exit;
  Sprite(Canvas,12,P,Size,Width,Height,Direction,Alpha);
  if Boss then for I:=0 to 5 do
  begin
    LocalAge:=Age-I*0.055-0.06;
    Burst.X:=P.X+Cos(I*2.399)*0.07;Burst.Y:=P.Y+Sin(I*2.399)*0.05;
    Sprite(Canvas,12,Burst,0.05+Max(0.0,LocalAge)*0.14,Width,Height,Direction,
      ExplosionOpacity(LocalAge,0.7)*0.8);
  end;
end;

procedure TRhythmRenderer.Background(Canvas:TCanvas;Time:Double;Width,Height,Direction,OnlyLayer:Integer);
const Speeds:array[0..2] of Double=(30,110,260);
  Density:array[0..2] of Double=(0.00013,0.000075,0.000020);
  Sizes:array[0..2] of Double=(0.65,1.8,3.4);
  Trails:array[0..2] of Double=(0,6,18);
var Layer,I,Count,Index,Tile,Offset,TX,TY:Integer;Seed:UInt64;Across,Along,Period,Span,Position,X,Y,Radius,Scale,Trail:Double;
  function RandomUnit:Double;
  begin Seed:=(Seed*48271) mod 2147483647;Result:=Seed/2147483647;end;
begin
  if not FD2DActive then begin Canvas.Brush.Color:=RGB(7,13,29);Canvas.FillRect(Rect(0,0,Width,Height));end;
  // A long torus has no small repeated tile or per-cell regularity. Each layer
  // has its own fixed seed, density, point size, brightness and travel speed.
  if Direction=0 then begin Span:=Width;Period:=Max(Height,1080)*5;end
  else begin Span:=Height;Period:=Max(Width,1920)*5;end;
  Scale:=Min(Width,Height)/720;
  for Layer:=0 to 2 do
  begin
    if (OnlyLayer>=0) and (Layer<>OnlyLayer) then Continue;
    Index:=Direction*3+Layer;
    if FCustom[Index] then begin
      Tile:=Max(1,Round(1024*Scale));Offset:=Round(Time*Speeds[Layer]*Scale) mod Tile;
      if Direction=0 then begin TY:=Offset-Tile;while TY<Height do begin TX:=0;while TX<Width do begin
        if FD2DActive then FD2D.DrawAsset(Index,Rect(TX,TY,TX+Tile,TY+Tile)) else Canvas.StretchDraw(Rect(TX,TY,TX+Tile,TY+Tile),FAssets[Index]);Inc(TX,Tile);
      end;Inc(TY,Tile);end;end
      else begin TX:=-Offset;while TX<Width do begin TY:=0;while TY<Height do begin
        if FD2DActive then FD2D.DrawAsset(Index,Rect(TX,TY,TX+Tile,TY+Tile)) else Canvas.StretchDraw(Rect(TX,TY,TX+Tile,TY+Tile),FAssets[Index]);Inc(TY,Tile);
      end;Inc(TX,Tile);end;end;Continue;
    end;
    Seed:=7919+Layer*104729;Count:=Round(Span*Period*Density[Layer]);
    Radius:=Sizes[Layer]*Max(0.8,Scale);Trail:=Trails[Layer]*Scale;
    if not FD2DActive then begin Canvas.Pen.Style:=psClear;Canvas.Brush.Color:=RGB(42+Layer*25,62+Layer*35,88+Layer*44);end;
    for I:=0 to Count-1 do
    begin
      Across:=RandomUnit*Span;Along:=RandomUnit*Period;
      Position:=Along+Time*Speeds[Layer]*Scale;Position:=Position-Floor(Position/Period)*Period;
      if Direction=0 then begin X:=Across;Y:=Position;end else begin X:=Width-Position;Y:=Across;end;
      if (X< -Radius) or (X>Width+Radius) or (Y< -Radius) or (Y>Height+Radius) then Continue;
      if FD2DActive then FD2D.Star(X,Y,Radius,Trail,Layer,Direction)
      else begin
        if Trail>0 then begin
          Canvas.Pen.Style:=psSolid;Canvas.Pen.Color:=RGB(30,50,77);Canvas.Pen.Width:=Max(1,Round(Radius*0.48));Canvas.MoveTo(Round(X),Round(Y));
          if Direction=0 then Canvas.LineTo(Round(X),Round(Y-Trail)) else Canvas.LineTo(Round(X+Trail),Round(Y));
          Canvas.Pen.Width:=1;Canvas.Pen.Style:=psClear;
        end;
        Canvas.Ellipse(Floor(X-Radius),Floor(Y-Radius),Ceil(X+Radius),Ceil(Y+Radius));
      end;
    end;
  end;
  if not FD2DActive then Canvas.Pen.Style:=psSolid;
end;
procedure TRhythmRenderer.Render(Target:Vcl.Graphics.TBitmap;Audio:TRhythmAudio;Time:Double;Direction:Integer;const MessageText:string;Zoom,OffsetX,OffsetY:Double);
var I,J,First,Last,BossIndex:Integer;H:TRhythmHit;P,Q,Aim:TRhythmPoint;
  Age,BossTime,StartTime,Flight,Alpha:Double;
  C:TCanvas;Width,Height:Integer;Text,PlanKey:string;EnemyBullet:TRhythmEnemyBullet;Enemy:TRhythmFlyby;Schedule:TRhythmStageSchedule;Additional:TArray<TRhythmFlyby>;
begin
  Width:=Target.Width;Height:=Target.Height;if (Width<1) or (Height<1) then Exit;
  if (Abs(Zoom-1)>1E-8) or (Abs(OffsetX)>1E-8) or (Abs(OffsetY)>1E-8) then
  begin
    FTransform.SetSize(Width,Height);Render(FTransform,Audio,Time,Direction,MessageText,1,0,0);
    Target.Canvas.Brush.Color:=clBlack;Target.Canvas.FillRect(Rect(0,0,Width,Height));
    I:=Round((Width-Width*Zoom)/2+OffsetX);J:=Round((Height-Height*Zoom)/2+OffsetY);
    Target.Canvas.StretchDraw(Rect(I,J,I+Round(Width*Zoom),J+Round(Height*Zoom)),FTransform);Exit;
  end;
  C:=Target.Canvas;Direction:=EnsureRange(Direction,0,1);Time:=Max(0.0,Time);
  Schedule:=StageSchedule(Audio);
  if Audio<>nil then
  begin
    PlanKey:=Audio.Key+'|'+IntToHex(NativeUInt(Audio),16)+'|'+IntToStr(Audio.TimelineRevision)+'|'+IntToStr(Width)+'x'+IntToStr(Height)+'|'+IntToStr(Direction);
    if PlanKey<>FPlanKey then begin
      FBarrage:=BuildBarrage(Audio,Width,Height,Direction);FFlybys:=BuildFlybys(Audio);
      if Direction=0 then begin
        Additional:=BuildLowerFlybys(Audio);I:=Length(FFlybys);SetLength(FFlybys,I+Length(Additional));
        for J:=0 to High(Additional) do FFlybys[I+J]:=Additional[J];
      end;
      FPlanKey:=PlanKey;
    end;
  end;
  FLastD2D:=False;FD2DActive:=FUseD2D and (FD2D<>nil) and FD2D.BeginFrame(Target);
  Background(C,Time,Width,Height,Direction);
  if Audio<>nil then
  begin
    for Enemy in FFlybys do if (Time>=Enemy.Launch) and (Time<Enemy.Finish) and ((Direction<>0) or (Time<Schedule.ClearTime)) then
    begin
      P:=FlybyAt(Enemy,Time);J:=8;if Enemy.Variant=1 then J:=13 else if Enemy.Variant=2 then J:=14;
      if Enemy.Route<>frUpperCross then J:=21+Enemy.Variant;
      Alpha:=Min(1.0,Min((Time-Enemy.Launch)/0.3,(Enemy.Finish-Time)/0.4));
      Sprite(C,J,P,Enemy.Size,Width,Height,Direction,Alpha*0.9);
    end;
    First:=Max(0,Audio.NearestHit(Time-0.6)-1);Last:=Min(High(Audio.Hits),Audio.NearestHit(Time+1.6)+1);
    for I:=First to Last do
    begin
      H:=Audio.Hits[I];Age:=Time-H.Time;
      J:=8;if I mod 3=1 then J:=13 else if I mod 3=2 then J:=14;
      if (Age>=-1.6) and (Age<0) then Sprite(C,J,EnemyAt(H,Time),0.065,Width,Height,Direction);
      if (Age>=-H.Flight) and (Age<0) then Sprite(C,11,BulletAt(H,Time),0.027,Width,Height,Direction);
      if (Age>=0) and (Age<0.6) then Explosion(C,EnemyAt(H,H.Time),Age,False,Width,Height,Direction);
    end;
    // 盛り上がり後の静かな区切りへ撃破を合わせ、長めの戦闘区間を共有する。
    if (Audio.Duration>8) and (Length(Audio.Hits)>0) then
      for BossIndex:=0 to Audio.BossCount-1 do
      begin
        BossTime:=BossKillTime(Audio,BossIndex);if BossTime<0 then Continue;
        StartTime:=BossStartTime(Audio,BossIndex);Age:=Time-BossTime;
        P:=BossAt(BossTime,StartTime,Time);
        if (Time>=StartTime) and (Age<0) then
        begin
          Sprite(C,9+(BossIndex mod 2),P,0.18,Width,Height,Direction);
        end;
        Age:=Time-BossTime;
        Aim:=BossAt(BossTime,StartTime,BossTime);Flight:=ShotFlightToY(BossTime,0.19);
        if (Age>=-Flight) and (Age<0) then
        begin
          Q:=PlayerShotAt(psForward,BossTime,Flight,0.19,Time);
          Sprite(C,11,Q,0.045,Width,Height,Direction);
        end;
        if (Age>=0) and (Age<1.35) then Explosion(C,Aim,Age,True,Width,Height,Direction);
      end;
    if Time<Schedule.ClearTime then for EnemyBullet in FBarrage do
      if (Time>=EnemyBullet.Launch) and (Time<EnemyBullet.Finish) then
      begin
        Q:=EnemyBulletAt(EnemyBullet,Time);
        if (Q.X>=-0.05) and (Q.X<=1.05) and (Q.Y>=-0.05) and (Q.Y<=1.05) then
        begin
          BossTime:=BossKillTime(Audio,EnemyBullet.Boss);
          Alpha:=EnsureRange((BossTime+0.45-Time)/0.45,0.0,1.0);
          Sprite(C,11,Q,0.018+EnemyBullet.Intensity*0.005,Width,Height,Direction,Alpha);
        end;
      end;
  end;
  Sprite(C,6+Direction,StagePoint(Time,Schedule.EntryEnd,Schedule.ExitStart,Schedule.ExitEnd,Schedule.HoldTime),0.078,Width,Height,Direction);
  if FD2DActive then
  begin
    FD2DActive:=False;
    if not FD2D.EndFrame then begin FUseD2D:=False;Render(Target,Audio,Time,Direction,MessageText);Exit;end;
    FLastD2D:=True;
  end;
  C.Font.Name:='Segoe UI';C.Font.Size:=Max(9,Round(Min(Width,Height)/60));C.Font.Color:=RGB(184,212,235);
  C.Brush.Style:=bsClear;
  if FDesignWarning<>'' then Text:='素材が見つからないため標準表示: '+FDesignWarning
  else if Audio=nil then Text:=MessageText
  else Text:='';
  if Text<>'' then C.TextOut(16,14,Text);
  C.Brush.Style:=bsSolid;
end;

end.
