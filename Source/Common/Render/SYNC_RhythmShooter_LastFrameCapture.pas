unit SYNC_RhythmShooter_LastFrameCapture;

{$WARN IMPLICIT_STRING_CAST OFF}

interface

uses
  System.SysUtils,
  AviUtl2FilterTypes;

procedure InitializeLastFrameCapture;
procedure FinalizeLastFrameCapture;
procedure CaptureLastFrame(Video: PFILTER_PROC_VIDEO);
function CopyLastFrame(out Pixels: TBytes; out Width, Height: Integer;
  out Status: string): Boolean;

implementation

uses
  System.Math,
  Winapi.D3D11,
  Winapi.DXGIFormat,
  Winapi.Windows;

const
  MAX_CAPTURE_DIMENSION = 16384;

type
  TPixelWords = array[0..3] of Word;
  PPixelWords = ^TPixelWords;

var
  CaptureBuffer: TBytes;
  CaptureDevice: ID3D11Device;
  CaptureFormat: DXGI_FORMAT;
  CaptureHeight: Integer;
  CaptureInitialized: Boolean;
  CaptureLock: TRTLCriticalSection;
  CaptureStagingTexture: ID3D11Texture2D;
  CaptureStatus: string;
  CaptureWidth: Integer;

function BytesPerPixel(Format: DXGI_FORMAT): Integer;
begin
  case Format of
    DXGI_FORMAT_R8G8B8A8_UNORM,
    DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
    DXGI_FORMAT_B8G8R8A8_UNORM,
    DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
      Result := 4;
    DXGI_FORMAT_R16G16B16A16_UNORM,
    DXGI_FORMAT_R16G16B16A16_FLOAT:
      Result := 8;
  else
    Result := 0;
  end;
end;

function HalfToSingle(Value: Word): Single;
var
  Exponent: Integer;
  Mantissa: Cardinal;
  ResultBits: Cardinal;
  SignBits: Cardinal;
begin
  SignBits := Cardinal(Value and $8000) shl 16;
  Exponent := (Value shr 10) and $1F;
  Mantissa := Value and $03FF;
  if Exponent = 0 then
  begin
    if Mantissa = 0 then
      ResultBits := SignBits
    else
    begin
      Exponent := -14;
      while (Mantissa and $0400) = 0 do
      begin
        Mantissa := Mantissa shl 1;
        Dec(Exponent);
      end;
      Mantissa := Mantissa and $03FF;
      ResultBits := SignBits or Cardinal(Exponent + 127) shl 23 or
        Mantissa shl 13;
    end;
  end
  else if Exponent = $1F then
    ResultBits := SignBits or $7F800000 or Mantissa shl 13
  else
    ResultBits := SignBits or Cardinal(Exponent + 112) shl 23 or
      Mantissa shl 13;
  Result := PSingle(@ResultBits)^;
end;

function FloatToByte(Value: Single): Byte;
begin
  if IsNan(Value) or (Value <= 0) then
    Exit(0);
  if Value >= 1 then
    Exit(255);
  Result := Round(Value * 255);
end;

procedure ClearCapture;
begin
  CaptureBuffer := nil;
  CaptureWidth := 0;
  CaptureHeight := 0;
  CaptureStagingTexture := nil;
  CaptureDevice := nil;
end;

procedure SetCaptureError(const Value: string);
begin
  CaptureBuffer := nil;
  CaptureWidth := 0;
  CaptureHeight := 0;
  CaptureStatus := Value;
end;

procedure InitializeLastFrameCapture;
begin
  if CaptureInitialized then
    Exit;
  InitializeCriticalSection(CaptureLock);
  CaptureInitialized := True;
  CaptureStatus := #$6620#$50CF#$306F#$307E#$3060#$53D6#$5F97#$3055#$308C#$3066#$3044#$307E#$305B#$3093#$3002;
end;

procedure FinalizeLastFrameCapture;
begin
  if not CaptureInitialized then
    Exit;
  EnterCriticalSection(CaptureLock);
  try
    ClearCapture;
  finally
    LeaveCriticalSection(CaptureLock);
  end;
  DeleteCriticalSection(CaptureLock);
  CaptureInitialized := False;
end;

procedure CaptureLastFrame(Video: PFILTER_PROC_VIDEO);
var
  Context: ID3D11DeviceContext;
  Device: ID3D11Device;
  Destination: PByte;
  Mapped: D3D11_MAPPED_SUBRESOURCE;
  RowBytes: NativeInt;
  Source: PByte;
  SourceDesc: D3D11_TEXTURE2D_DESC;
  SourcePointer: Pointer;
  SourceTexture: ID3D11Texture2D;
  StagingDesc: D3D11_TEXTURE2D_DESC;
  Y: Integer;
begin
  if not CaptureInitialized then
    Exit;
  EnterCriticalSection(CaptureLock);
  try
    try
      if Video = nil then
      begin
        SetCaptureError(#$6620#$50CF#$30B3#$30F3#$30C6#$30AD#$30B9#$30C8#$3092#$53D6#$5F97#$3067#$304D#$307E#$305B#$3093#$3002);
        Exit;
      end;
      SourcePointer := nil;
      if Assigned(Video^.GetImageTexture2D) then
        SourcePointer := Video^.GetImageTexture2D();
      if (SourcePointer = nil) and Assigned(Video^.GetFramebufferTexture2D) then
        SourcePointer := Video^.GetFramebufferTexture2D();
      if SourcePointer = nil then
      begin
        SetCaptureError(#$5165#$529B#$753B#$50CF#$3092#$53D6#$5F97#$3067#$304D#$307E#$305B#$3093#$3002);
        Exit;
      end;
      SourceTexture := ID3D11Texture2D(SourcePointer);
      SourceTexture.GetDesc(SourceDesc);
      if (SourceDesc.Width = 0) or (SourceDesc.Height = 0) or
        (SourceDesc.Width > MAX_CAPTURE_DIMENSION) or
        (SourceDesc.Height > MAX_CAPTURE_DIMENSION) then
      begin
        SetCaptureError(#$5165#$529B#$753B#$50CF#$306E#$30B5#$30A4#$30BA#$304C#$4E0D#$6B63#$3067#$3059#$3002);
        Exit;
      end;
      RowBytes := NativeInt(SourceDesc.Width) *
        BytesPerPixel(SourceDesc.Format);
      if RowBytes = 0 then
      begin
        SetCaptureError(Format(#$672A#$5BFE#$5FDC#$306E#$753B#$50CF#$5F62#$5F0F#$3067#$3059#$FF08 + 'DXGI %d' + #$FF09#$3002,
          [Ord(SourceDesc.Format)]));
        Exit;
      end;
      if SourceDesc.SampleDesc.Count <> 1 then
      begin
        SetCaptureError(#$30DE#$30EB#$30C1#$30B5#$30F3#$30D7#$30EB#$753B#$50CF#$306B#$306F#$5BFE#$5FDC#$3057#$3066#$3044#$307E#$305B#$3093#$3002);
        Exit;
      end;
      SourceTexture.GetDevice(Device);
      if Device = nil then
      begin
        SetCaptureError(#$753B#$50CF#$30C7#$30D0#$30A4#$30B9#$3092#$53D6#$5F97#$3067#$304D#$307E#$305B#$3093#$3002);
        Exit;
      end;
      if (CaptureStagingTexture = nil) or
        (Pointer(CaptureDevice) <> Pointer(Device)) or
        (CaptureWidth <> Integer(SourceDesc.Width)) or
        (CaptureHeight <> Integer(SourceDesc.Height)) or
        (CaptureFormat <> SourceDesc.Format) then
      begin
        CaptureStagingTexture := nil;
        CaptureDevice := nil;
        StagingDesc := SourceDesc;
        StagingDesc.MipLevels := 1;
        StagingDesc.ArraySize := 1;
        StagingDesc.Usage := D3D11_USAGE_STAGING;
        StagingDesc.BindFlags := 0;
        StagingDesc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
        StagingDesc.MiscFlags := 0;
        if Device.CreateTexture2D(StagingDesc, nil,
          CaptureStagingTexture) < 0 then
        begin
          SetCaptureError(#$753B#$50CF#$8AAD#$307F#$53D6#$308A#$7528#$30D0#$30C3#$30D5#$30A1#$30FC#$3092#$4F5C#$6210#$3067#$304D#$307E#$305B#$3093#$3002);
          Exit;
        end;
        CaptureDevice := Device;
      end;
      Device.GetImmediateContext(Context);
      Context.CopyResource(CaptureStagingTexture, SourceTexture);
      FillChar(Mapped, SizeOf(Mapped), 0);
      if Context.Map(CaptureStagingTexture, 0, D3D11_MAP_READ, 0,
        Mapped) < 0 then
      begin
        SetCaptureError(#$5165#$529B#$753B#$50CF#$3092#$8AAD#$307F#$53D6#$308C#$307E#$305B#$3093#$3002);
        Exit;
      end;
      try
        CaptureWidth := SourceDesc.Width;
        CaptureHeight := SourceDesc.Height;
        CaptureFormat := SourceDesc.Format;
        SetLength(CaptureBuffer, RowBytes * CaptureHeight);
        Source := Mapped.pData;
        Destination := @CaptureBuffer[0];
        for Y := 0 to CaptureHeight - 1 do
        begin
          Move(Source^, Destination^, RowBytes);
          Inc(Source, Mapped.RowPitch);
          Inc(Destination, RowBytes);
        end;
      finally
        Context.Unmap(CaptureStagingTexture, 0);
      end;
      CaptureStatus := Format(#$5165#$529B#$753B#$50CF + ' %d x %d',
        [CaptureWidth, CaptureHeight]);
    except
      on E: Exception do
        SetCaptureError(#$753B#$50CF#$53D6#$5F97#$30A8#$30E9#$30FC + ': ' + E.Message);
    end;
  finally
    LeaveCriticalSection(CaptureLock);
  end;
end;

function CopyLastFrame(out Pixels: TBytes; out Width, Height: Integer;
  out Status: string): Boolean;
var
  I: NativeInt;
  PixelCount: NativeInt;
  Source: PByte;
  Destination: PByte;
  SourceWords: PPixelWords;
begin
  Pixels := nil;
  Width := 0;
  Height := 0;
  Status := #$753B#$50CF#$53D6#$5F97#$6A5F#$80FD#$304C#$521D#$671F#$5316#$3055#$308C#$3066#$3044#$307E#$305B#$3093#$3002;
  if not CaptureInitialized then
    Exit(False);
  EnterCriticalSection(CaptureLock);
  try
    Status := CaptureStatus;
    Result := (Length(CaptureBuffer) > 0) and
      (CaptureWidth > 0) and (CaptureHeight > 0);
    if not Result then
      Exit;
    Width := CaptureWidth;
    Height := CaptureHeight;
    PixelCount := NativeInt(Width) * Height;
    SetLength(Pixels, PixelCount * 4);
    Source := @CaptureBuffer[0];
    Destination := @Pixels[0];
    case CaptureFormat of
      DXGI_FORMAT_R8G8B8A8_UNORM,
      DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
        Move(Source^, Destination^, Length(Pixels));
      DXGI_FORMAT_B8G8R8A8_UNORM,
      DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
        for I := 0 to PixelCount - 1 do
        begin
          Destination[0] := Source[2];
          Destination[1] := Source[1];
          Destination[2] := Source[0];
          Destination[3] := Source[3];
          Inc(Source, 4);
          Inc(Destination, 4);
        end;
      DXGI_FORMAT_R16G16B16A16_UNORM:
        begin
          SourceWords := PPixelWords(Source);
          for I := 0 to PixelCount - 1 do
          begin
            Destination[0] := SourceWords[0] div 257;
            Destination[1] := SourceWords[1] div 257;
            Destination[2] := SourceWords[2] div 257;
            Destination[3] := SourceWords[3] div 257;
            Inc(SourceWords);
            Inc(Destination, 4);
          end;
        end;
      DXGI_FORMAT_R16G16B16A16_FLOAT:
        begin
          SourceWords := PPixelWords(Source);
          for I := 0 to PixelCount - 1 do
          begin
            Destination[0] := FloatToByte(HalfToSingle(SourceWords[0]));
            Destination[1] := FloatToByte(HalfToSingle(SourceWords[1]));
            Destination[2] := FloatToByte(HalfToSingle(SourceWords[2]));
            Destination[3] := Round(EnsureRange(
              HalfToSingle(SourceWords[3]), 0.0, 1.0) * 255);
            Inc(SourceWords);
            Inc(Destination, 4);
          end;
        end;
    else
      Pixels := nil;
      Result := False;
    end;
  finally
    LeaveCriticalSection(CaptureLock);
  end;
end;

end.
