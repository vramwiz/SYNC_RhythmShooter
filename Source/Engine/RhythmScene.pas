unit RhythmScene;

interface

uses System.Types, Vcl.Graphics, RhythmAudio, RhythmD2D, RhythmMotion, RhythmBarrage,RhythmDesignTypes;

type
  TRhythmPoint = RhythmMotion.TRhythmPoint;
  TRhythmRenderer = class
  private
    FAssets: array[0..20] of TBitmap;
    FScaled: array[0..20,0..2] of TBitmap;
    FD2D:TRhythmD2D;
    FD2DActive,FUseD2D,FLastD2D:Boolean;
    FAssetCount: Integer;
    FBarrage:TArray<TRhythmEnemyBullet>;
    FPlanKey:string;
    FTransform:TBitmap;
    FDesignKey,FDesignWarning:string;
    FCustom:array[0..14] of Boolean;
    function MapPoint(const P: TRhythmPoint; Width,Height,Direction: Integer): TPoint;
    procedure Sprite(Canvas: TCanvas; Index: Integer; const P: TRhythmPoint;
      Size: Double; Width,Height,Direction: Integer);
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
  for I:=0 to High(RotateIndices) do
  begin
    Source:=FAssets[RotateIndices[I]];Rotated:=FAssets[15+I];
    if Source.Empty then Continue;
    Rotated.PixelFormat:=pf24bit;Rotated.SetSize(Source.Height,Source.Width);
    for Y:=0 to Source.Height-1 do for X:=0 to Source.Width-1 do
      Rotated.Canvas.Pixels[Source.Height-1-Y,X]:=Source.Canvas.Pixels[X,Y];
    Rotated.TransparentColor:=clFuchsia;Rotated.Transparent:=True;
  end;
  try FD2D:=TRhythmD2D.Create(FAssets);FUseD2D:=True;except FD2D:=nil;FUseD2D:=False;end;
end;

destructor TRhythmRenderer.Destroy;
var B: Vcl.Graphics.TBitmap;I,J:Integer;
begin
  FTransform.Free;FD2D.Free;for B in FAssets do B.Free;
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
  Size:Double;Width,Height,Direction:Integer);
var Center:TPoint; W,H,Bucket,Swap:Integer;Scaled:Vcl.Graphics.TBitmap;
begin
  Center:=MapPoint(P,Width,Height,Direction);
  // Keep arbitrary custom ship silhouettes inside the existing avoidance
  // corridor, including opaque square imports. Default artwork is unchanged.
  if (Index in [6,7]) and FCustom[Index] then Size:=Size*0.8;
  W:=Max(2,Round(Size*Min(Width,Height))); H:=W;
  if Index in [9,10] then W:=W*8 div 5;
  if Direction=1 then
  begin
    case Index of 8:Index:=15;9:Index:=16;10:Index:=17;11:Index:=18;13:Index:=19;14:Index:=20;end;
    if Index>=15 then begin Swap:=W;W:=H;H:=Swap;end;
  end;
  if FD2DActive then begin FD2D.DrawAsset(Index,Rect(Center.X-W div 2,Center.Y-H div 2,Center.X+W div 2,Center.Y+H div 2));Exit;end;
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
  Age,BossTime,StartTime,Flight:Double;
  C:TCanvas;Width,Height:Integer;Center:TPoint;Text,PlanKey:string;EnemyBullet:TRhythmEnemyBullet;Schedule:TRhythmStageSchedule;
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
    PlanKey:=Audio.Key+'|'+IntToStr(Audio.Sensitivity)+'|'+IntToStr(Length(Audio.Hits))+'|'+IntToStr(Width)+'x'+IntToStr(Height)+'|'+IntToStr(Direction);
    if PlanKey<>FPlanKey then begin FBarrage:=BuildBarrage(Audio,Width,Height,Direction);FPlanKey:=PlanKey;end;
  end;
  FLastD2D:=False;FD2DActive:=FUseD2D and (FD2D<>nil) and FD2D.BeginFrame(Target);
  Background(C,Time,Width,Height,Direction);
  if Audio<>nil then
  begin
    First:=Max(0,Audio.NearestHit(Time-0.5)-1);Last:=Min(High(Audio.Hits),Audio.NearestHit(Time+1.6)+1);
    for I:=First to Last do
    begin
      H:=Audio.Hits[I];Age:=Time-H.Time;
      J:=8;if I mod 3=1 then J:=13 else if I mod 3=2 then J:=14;
      if (Age>=-1.6) and (Age<0) then Sprite(C,J,EnemyAt(H,Time),0.065,Width,Height,Direction);
      if (Age>=-H.Flight) and (Age<0) then Sprite(C,11,BulletAt(H,Time),0.027,Width,Height,Direction);
      if (Age>=0) and (Age<0.42) then
      begin
        P:=EnemyAt(H,H.Time);Sprite(C,12,P,0.04+Age*0.18,Width,Height,Direction);
        Center:=MapPoint(P,Width,Height,Direction);C.Brush.Style:=bsClear;C.Pen.Color:=RGB(255,170,66);
        J:=Round((0.015+Age*0.16)*Min(Width,Height));
        if FD2DActive then FD2D.Ring(Center.X,Center.Y,J) else C.Ellipse(Center.X-J,Center.Y-J,Center.X+J,Center.Y+J);C.Brush.Style:=bsSolid;
      end;
    end;
    // Boss endpoints are snapped to detected accents. Short songs scale the
    // encounter windows so they never overlap or require a hand-authored stage.
    if (Audio.Duration>8) and (Length(Audio.Hits)>0) then
      for BossIndex:=0 to 1 do
      begin
        BossTime:=BossKillTime(Audio,BossIndex);if BossTime<0 then Continue;
        StartTime:=BossTime-Min(6.0,Audio.Duration*0.18);Age:=Time-BossTime;
        P:=BossAt(BossTime,StartTime,Time);
        if (Time>=StartTime) and (Age<0) then
        begin
          Sprite(C,9+BossIndex,P,0.18,Width,Height,Direction);
        end;
        Age:=Time-BossTime;
        Aim:=BossAt(BossTime,StartTime,BossTime);Flight:=ShotFlightToY(BossTime,0.19);
        if (Age>=-Flight) and (Age<0) then
        begin
          Q:=PlayerShotAt(psForward,BossTime,Flight,0.19,Time);
          Sprite(C,11,Q,0.045,Width,Height,Direction);
        end;
        if (Age>=0) and (Age<0.7) then Sprite(C,12,Aim,0.16+Age*0.2,Width,Height,Direction);
      end;
    if Time<Schedule.ClearTime then for EnemyBullet in FBarrage do
      if (Time>=EnemyBullet.Launch) and (Time<EnemyBullet.Finish) then
      begin
        Q:=EnemyBulletAt(EnemyBullet,Time);
        if (Q.X>=-0.05) and (Q.X<=1.05) and (Q.Y>=-0.05) and (Q.Y<=1.05) then
          Sprite(C,11,Q,0.021,Width,Height,Direction);
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
  else if Time>=Schedule.ClearTime then Text:='CLEAR'
  else Text:=Format('SYNC  /  %.2fs  /  %d accents',[Time,Length(Audio.Hits)]);
  if Text<>'' then C.TextOut(16,14,Text);
  C.Brush.Style:=bsSolid;
end;

end.
