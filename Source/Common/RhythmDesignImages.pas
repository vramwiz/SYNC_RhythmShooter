unit RhythmDesignImages;
{$POINTERMATH ON}
interface
uses Vcl.Graphics,RhythmDesignTypes;
function ImportDesignImage(const Source:string;Index:Integer):TRhythmDesign;
function ResolveDesignImage(const Design:TRhythmDesign):string;
function ReadDesignBitmap(const Path:string;Width:Integer=0;Height:Integer=0;Fit:Boolean=False):Vcl.Graphics.TBitmap;
procedure WriteDesignPNG(Bitmap:Vcl.Graphics.TBitmap;const Path:string);
implementation
uses Winapi.Windows,Winapi.ActiveX,Winapi.Wincodec,System.SysUtils,System.Math,System.Classes,
  System.IOUtils,System.Hash,System.Win.ComObj,Vcl.Imaging.pngimage,RhythmPaths;
function ReadDesignBitmap(const Path:string;Width,Height:Integer;Fit:Boolean):Vcl.Graphics.TBitmap;
var Factory:IWICImagingFactory;Decoder:IWICBitmapDecoder;Frame:IWICBitmapFrameDecode;
  Converter:IWICFormatConverter;Scaler:IWICBitmapScaler;Pixels:TBytes;W,H:UINT;
  InitResult:HRESULT;DW,DH,DX,DY,Y:Integer;Scale:Double;
begin
  Result:=nil;InitResult:=CoInitializeEx(nil,COINIT_APARTMENTTHREADED);
  if Failed(InitResult) and (InitResult<>RPC_E_CHANGED_MODE) then OleCheck(InitResult);
  try
    OleCheck(CoCreateInstance(CLSID_WICImagingFactory,nil,CLSCTX_INPROC_SERVER,IWICImagingFactory,Factory));
    OleCheck(Factory.CreateDecoderFromFilename(PChar(Path),GUID_NULL,GENERIC_READ,WICDecodeMetadataCacheOnLoad,Decoder));
    OleCheck(Decoder.GetFrame(0,Frame));OleCheck(Frame.GetSize(W,H));
    if (W=0) or (H=0) or (W>4096) or (H>4096) or (Int64(W)*H>8*1024*1024) then raise Exception.Create('画像は4096px以内、合計800万画素以内で指定してください。');
    if Width=0 then Width:=W;if Height=0 then Height:=H;
    DW:=Width;DH:=Height;DX:=0;DY:=0;
    if Fit then begin Scale:=Min(Width/W,Height/H);DW:=Max(1,Round(W*Scale));DH:=Max(1,Round(H*Scale));DX:=(Width-DW) div 2;DY:=(Height-DH) div 2;end;
    OleCheck(Factory.CreateFormatConverter(Converter));
    OleCheck(Converter.Initialize(Frame,GUID_WICPixelFormat32bppPBGRA,WICBitmapDitherTypeNone,nil,0,WICBitmapPaletteTypeCustom));
    OleCheck(Factory.CreateBitmapScaler(Scaler));OleCheck(Scaler.Initialize(Converter,DW,DH,WICBitmapInterpolationModeFant));
    SetLength(Pixels,DW*DH*4);OleCheck(Scaler.CopyPixels(nil,DW*4,Length(Pixels),@Pixels[0]));
    Result:=Vcl.Graphics.TBitmap.Create;
    try
      Result.PixelFormat:=pf32bit;Result.SetSize(Width,Height);Result.AlphaFormat:=afPremultiplied;
      for Y:=0 to Height-1 do FillChar(Result.ScanLine[Y]^,Width*4,0);
      for Y:=0 to DH-1 do Move(Pixels[Y*DW*4],PByte(Result.ScanLine[Y+DY])[DX*4],DW*4);
    except FreeAndNil(Result);raise;end;
  finally Scaler:=nil;Converter:=nil;Frame:=nil;Decoder:=nil;Factory:=nil;if Succeeded(InitResult) then CoUninitialize;end;
end;
procedure WriteDesignPNG(Bitmap:Vcl.Graphics.TBitmap;const Path:string);
var PNG:TPngImage;X,Y,A:Integer;Source,RGB,Alpha:PByte;
begin
  PNG:=TPngImage.CreateBlank(COLOR_RGBALPHA,8,Bitmap.Width,Bitmap.Height);
  try
    for Y:=0 to Bitmap.Height-1 do begin
      Source:=Bitmap.ScanLine[Y];RGB:=PNG.Scanline[Y];Alpha:=PByte(PNG.AlphaScanline[Y]);
      for X:=0 to Bitmap.Width-1 do begin
        if Bitmap.AlphaFormat=afIgnored then A:=255 else A:=Source[3];Alpha[X]:=A;
        if A=0 then begin RGB[X*3]:=0;RGB[X*3+1]:=0;RGB[X*3+2]:=0;end
        else begin RGB[X*3]:=Min(255,(Integer(Source[0])*255+A div 2) div A);RGB[X*3+1]:=Min(255,(Integer(Source[1])*255+A div 2) div A);RGB[X*3+2]:=Min(255,(Integer(Source[2])*255+A div 2) div A);end;
        Inc(Source,4);
      end;
    end;
    PNG.SaveToFile(Path);
  finally PNG.Free;end;
end;
function ResolveDesignImage(const Design:TRhythmDesign):string;
begin
  if not ValidDesignReference(Design.Path,Design.SHA256) or (Design.Path='') then raise Exception.Create('素材の保存参照が不正です。');
  Result:=TPath.Combine(ModuleFolder,Design.Path);
  if not FileExists(Result) then raise Exception.Create('保存した素材が見つかりません。再度参照してください。');
  if not SameText(THashSHA2.GetHashStringFromFile(Result),Design.SHA256) then raise Exception.Create('保存した素材のハッシュが一致しません。');
end;
function ImportDesignImage(const Source:string;Index:Integer):TRhythmDesign;
var Info:TRhythmDesignInfo;Bitmap,RawBitmap:Vcl.Graphics.TBitmap;Lease:TFileStream;Folder,Temp,KeyedPath,Destination,Ext:string;Id:TGUID;
  X,Y,Visible:Integer;Pixel:PByte;
begin
  Result:=Default(TRhythmDesign);Info:=DesignInfo(Index);Ext:=LowerCase(ExtractFileExt(Source));
  if (Ext<>'.png') and (Ext<>'.bmp') and (Ext<>'.jpg') and (Ext<>'.jpeg') then raise Exception.Create('PNG / BMP / JPEGを指定してください。');
  Lease:=TFileStream.Create(Source,fmOpenRead or fmShareDenyWrite);Bitmap:=nil;RawBitmap:=nil;Temp:='';KeyedPath:='';
  try
    if (Lease.Size=0) or (Lease.Size>32*1024*1024) then raise Exception.Create('画像は32MB以内で指定してください。');
    // Convert the legacy BMP color key before resampling, so the matte cannot
    // be mixed into visible edge pixels by the scaler.
    if (Ext='.bmp') and (not Info.Background or (Index mod 3<>0)) then begin
      RawBitmap:=ReadDesignBitmap(Source);
      for Y:=0 to RawBitmap.Height-1 do begin Pixel:=RawBitmap.ScanLine[Y];for X:=0 to RawBitmap.Width-1 do begin
        if (Pixel[0]=255) and (Pixel[1]=0) and (Pixel[2]=255) then begin Pixel[0]:=0;Pixel[1]:=0;Pixel[2]:=0;Pixel[3]:=0;end;Inc(Pixel,4);
      end;end;
      Folder:=TPath.Combine(ModuleFolder,'DesignAssets');ForceDirectories(Folder);CreateGUID(Id);KeyedPath:=TPath.Combine(Folder,GUIDToString(Id)+'-keyed.png');
      WriteDesignPNG(RawBitmap,KeyedPath);FreeAndNil(RawBitmap);
      Bitmap:=ReadDesignBitmap(KeyedPath,Info.Width,Info.Height,not Info.Background);
    end else Bitmap:=ReadDesignBitmap(Source,Info.Width,Info.Height,not Info.Background);
    Visible:=0;
    for Y:=0 to Bitmap.Height-1 do begin Pixel:=Bitmap.ScanLine[Y];for X:=0 to Bitmap.Width-1 do begin
      if (Ext='.bmp') and not Info.Background and (Pixel[0]=255) and (Pixel[1]=0) and (Pixel[2]=255) then begin Pixel[0]:=0;Pixel[1]:=0;Pixel[2]:=0;Pixel[3]:=0;end;
      if Pixel[3]>0 then Inc(Visible);Inc(Pixel,4);
    end;end;
    if Visible=0 then raise Exception.Create('完全に透明な素材は採用できません。');
    Folder:=TPath.Combine(ModuleFolder,'DesignAssets');ForceDirectories(Folder);CreateGUID(Id);
    Temp:=TPath.Combine(Folder,GUIDToString(Id)+'.png');WriteDesignPNG(Bitmap,Temp);
    Result.SHA256:=THashSHA2.GetHashStringFromFile(Temp);Result.Path:='DesignAssets\'+Result.SHA256+'.png';
    Destination:=TPath.Combine(ModuleFolder,Result.Path);
    if FileExists(Destination) then begin if not SameText(THashSHA2.GetHashStringFromFile(Destination),Result.SHA256) then raise Exception.Create('同名の素材ファイルが変更されています。上書きしません。');end
    else if not MoveFileEx(PChar(Temp),PChar(Destination),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally RawBitmap.Free;Bitmap.Free;Lease.Free;if (Temp<>'') and FileExists(Temp) then TFile.Delete(Temp);if (KeyedPath<>'') and FileExists(KeyedPath) then TFile.Delete(KeyedPath);end;
end;
end.
