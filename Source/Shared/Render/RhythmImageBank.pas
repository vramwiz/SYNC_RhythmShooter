unit RhythmImageBank;
interface
uses Vcl.Graphics,RhythmDesignTypes;
type
  TAnimationAssetSpec=record
    Name,Title:string;
    Opaque:Boolean;
  end;
  TAnimationImageBank=class
  private
    FSpecs:TArray<TAnimationAssetSpec>;
    FDesignKey,FDesignWarning:string;
    FAssetCount:Integer;
    FPrepared:Boolean;
    procedure LoadDefault(Index:Integer);
    procedure PrepareAlphaAssets;
    function ChoiceKey(const Choices:array of TRhythmDesign):string;
    function GetImage(Index:Integer):TBitmap;
    function GetAlphaImage(Index:Integer):TBitmap;
    function GetCustom(Index:Integer):Boolean;
  protected
    FImages,FAlphaImages:TArray<TBitmap>;
    FCustom,FColorKeys:TArray<Boolean>;
    procedure PrepareImages;virtual;
    function UsesAlpha(Index:Integer):Boolean;virtual;
    procedure RotateImage(SourceIndex,TargetIndex,QuarterTurns:Integer);
  public
    // Owns all images. Derived preparation runs only after base images exist.
    constructor Create(const Specs:array of TAnimationAssetSpec;TotalCount:Integer);
    destructor Destroy;override;
    procedure EnsurePrepared;
    function ApplyChoices(const Choices:array of TRhythmDesign;Force:Boolean=False):Boolean;
    property Images:TArray<TBitmap> read FImages;
    property ColorKeys:TArray<Boolean> read FColorKeys;
    property Image[Index:Integer]:TBitmap read GetImage;
    property AlphaImage[Index:Integer]:TBitmap read GetAlphaImage;
    property IsCustom[Index:Integer]:Boolean read GetCustom;
    property AssetCount:Integer read FAssetCount;
    property DesignWarning:string read FDesignWarning;
  end;
implementation
uses System.SysUtils,System.IOUtils,System.Hash,Winapi.Windows,RhythmPaths,RhythmDesignImages;

constructor TAnimationImageBank.Create(const Specs:array of TAnimationAssetSpec;TotalCount:Integer);
var I:Integer;
begin
  inherited Create;
  if TotalCount<Length(Specs) then raise EArgumentException.Create('Image bank is smaller than its catalog.');
  SetLength(FSpecs,Length(Specs));for I:=0 to High(Specs) do FSpecs[I]:=Specs[I];
  SetLength(FImages,TotalCount);SetLength(FAlphaImages,TotalCount);
  SetLength(FCustom,TotalCount);SetLength(FColorKeys,TotalCount);
  for I:=0 to TotalCount-1 do begin
    FImages[I]:=Vcl.Graphics.TBitmap.Create;
    if I>=Length(FSpecs) then Continue;
    if FileExists(TPath.Combine(AssetFolder,FSpecs[I].Name+'.bmp')) then begin LoadDefault(I);Inc(FAssetCount);end;
  end;
end;

procedure TAnimationImageBank.EnsurePrepared;
begin
  if FPrepared then Exit;
  PrepareImages;PrepareAlphaAssets;FPrepared:=True;
end;

destructor TAnimationImageBank.Destroy;
var B:Vcl.Graphics.TBitmap;
begin for B in FImages do B.Free;for B in FAlphaImages do B.Free;inherited;end;
procedure TAnimationImageBank.LoadDefault(Index:Integer);
var Path:string;
begin
  Path:=TPath.Combine(AssetFolder,FSpecs[Index].Name+'.bmp');
  if FileExists(Path) then FImages[Index].LoadFromFile(Path);
  FColorKeys[Index]:=not FSpecs[Index].Opaque;
  FImages[Index].Transparent:=FColorKeys[Index];FImages[Index].TransparentColor:=clFuchsia;
end;
function TAnimationImageBank.GetImage(Index:Integer):Vcl.Graphics.TBitmap;
begin Result:=FImages[Index];end;
function TAnimationImageBank.GetAlphaImage(Index:Integer):Vcl.Graphics.TBitmap;
begin Result:=FAlphaImages[Index];end;
function TAnimationImageBank.GetCustom(Index:Integer):Boolean;
begin Result:=FCustom[Index];end;
procedure TAnimationImageBank.PrepareImages;
begin end;
function TAnimationImageBank.UsesAlpha(Index:Integer):Boolean;
begin Result:=True;end;

procedure TAnimationImageBank.RotateImage(SourceIndex,TargetIndex,QuarterTurns:Integer);
var Source,Rotated:Vcl.Graphics.TBitmap;X,Y,DX,DY:Integer;P,Q:PByte;UseAlpha:Boolean;
begin
  if not (QuarterTurns in [1,2]) then raise EArgumentException.Create('Only quarter and half turns are supported.');
  Source:=FImages[SourceIndex];FreeAndNil(FImages[TargetIndex]);
  Rotated:=Vcl.Graphics.TBitmap.Create;FImages[TargetIndex]:=Rotated;FColorKeys[TargetIndex]:=FColorKeys[SourceIndex];
  if Source.Empty then Exit;
  // 元画像のアルファ方式を固定し、走査行を取得した経路だけでPを参照する。
  UseAlpha:=Source.AlphaFormat<>afIgnored;
  if not UseAlpha then Rotated.PixelFormat:=pf24bit
  else Rotated.PixelFormat:=pf32bit;
  if QuarterTurns=1 then Rotated.SetSize(Source.Height,Source.Width)
  else Rotated.SetSize(Source.Width,Source.Height);
  if UseAlpha then Rotated.AlphaFormat:=afPremultiplied;
  for Y:=0 to Source.Height-1 do begin
    P:=nil;if UseAlpha then P:=Source.ScanLine[Y];
    for X:=0 to Source.Width-1 do begin
      if QuarterTurns=1 then begin DX:=Source.Height-1-Y;DY:=X;end
      else begin DX:=Source.Width-1-X;DY:=Source.Height-1-Y;end;
      if not UseAlpha then Rotated.Canvas.Pixels[DX,DY]:=Source.Canvas.Pixels[X,Y]
      else begin Q:=Rotated.ScanLine[DY];Inc(Q,DX*4);Move(P^,Q^,4);Inc(P,4);end;
    end;
  end;
  if not UseAlpha then begin Rotated.TransparentColor:=clFuchsia;Rotated.Transparent:=FColorKeys[TargetIndex];end;
end;

function TAnimationImageBank.ChoiceKey(const Choices:array of TRhythmDesign):string;
var I:Integer;Text:string;
begin
  Text:='';for I:=0 to High(Choices) do if Choices[I].Path<>'' then
    Text:=Text+IntToStr(I)+':'+Choices[I].Path+'|'+Choices[I].SHA256+';';
  Result:='';if Text<>'' then Result:=THashSHA2.GetHashString(Text);
end;
function TAnimationImageBank.ApplyChoices(const Choices:array of TRhythmDesign;Force:Boolean):Boolean;
var Key,Path:string;I:Integer;Loaded:Vcl.Graphics.TBitmap;
begin
  if Length(Choices)<>Length(FSpecs) then raise EArgumentException.Create('Image choices do not match the catalog.');
  Key:=ChoiceKey(Choices);Result:=Force or (Key<>FDesignKey);if not Result then Exit;
  FDesignWarning:='';
  for I:=0 to High(FSpecs) do begin
    FCustom[I]:=False;FImages[I].Free;FImages[I]:=Vcl.Graphics.TBitmap.Create;
    if Choices[I].Path<>'' then try
      Path:=ResolveDesignImage(Choices[I]);Loaded:=ReadDesignBitmap(Path);
      FImages[I].Free;FImages[I]:=Loaded;FCustom[I]:=True;FColorKeys[I]:=not FSpecs[I].Opaque;
    except on E:Exception do FDesignWarning:=FDesignWarning+FSpecs[I].Title+': '+E.Message+' ';end;
    if not FCustom[I] then LoadDefault(I);
  end;
  FPrepared:=False;EnsurePrepared;FDesignKey:=Key;
end;

procedure TAnimationImageBank.PrepareAlphaAssets;
var I,X,Y,A:Integer;Temp:Vcl.Graphics.TBitmap;P,Q:PByte;Premultiplied,HasAlpha:Boolean;
begin
  Temp:=Vcl.Graphics.TBitmap.Create;
  try
    for I:=0 to High(FImages) do
    begin
      FreeAndNil(FAlphaImages[I]);FAlphaImages[I]:=Vcl.Graphics.TBitmap.Create;
      if FImages[I].Empty or not UsesAlpha(I) then Continue;
      HasAlpha:=FImages[I].AlphaFormat<>afIgnored;
      Premultiplied:=FImages[I].AlphaFormat=afPremultiplied;
      Temp.Assign(FImages[I]);Temp.PixelFormat:=pf32bit;
      FAlphaImages[I].PixelFormat:=pf32bit;FAlphaImages[I].SetSize(Temp.Width,Temp.Height);
      FAlphaImages[I].AlphaFormat:=afPremultiplied;
      for Y:=0 to Temp.Height-1 do
      begin
        P:=Temp.ScanLine[Y];Q:=FAlphaImages[I].ScanLine[Y];
        for X:=0 to Temp.Width-1 do
        begin
          if HasAlpha then A:=P[3]
          else if FColorKeys[I] and (P[0]=255) and (P[1]=0) and (P[2]=255) then A:=0
          else A:=255;
          if Premultiplied then begin Q[0]:=P[0];Q[1]:=P[1];Q[2]:=P[2];end
          else begin Q[0]:=P[0]*A div 255;Q[1]:=P[1]*A div 255;Q[2]:=P[2]*A div 255;end;
          Q[3]:=A;Inc(P,4);Inc(Q,4);
        end;
      end;
    end;
  finally Temp.Free;end;
end;
end.
