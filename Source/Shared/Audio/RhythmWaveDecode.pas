unit RhythmWaveDecode;
// ローカルWAVをWindows標準のMedia Foundationで44.1kHz・16bit・ステレオへ変換する。
interface
uses System.SysUtils;
const WAVE_DECODER_VERSION='windows-wave-1';
function DecodeWavePCM44100(const FileName:string;const Cancel:TFunc<Boolean> = nil):TBytes;
implementation
uses Winapi.Windows,Winapi.ActiveX,System.Classes,System.Math,System.Win.ComObj,RhythmMediaFoundation,MP3Decoder;
const MaxPCMBytes=512*Int64(1024)*1024;

// Windowsの変換器が受理しない64bit floatのmono/stereo WAVを補完する。
function TryReadFloat64Wave(Input:TStream;const Cancel:TFunc<Boolean>;out Audio:TDecodedAudio):Boolean;
const FloatSubType:TGUID='{00000003-0000-0010-8000-00AA00389B71}';
var Tag:array[0..3] of AnsiChar;Size:Cardinal;Next,DataStart,DataSize,SampleCount,Done:Int64;
  Fmt:TBytes;Format,Channels,Align,Bits:Word;Rate:Cardinal;SubType:TGUID;
  Chunk:array[0..4095] of Double;Count,I:Integer;Value:Double;Sample:SmallInt;IsFloat64:Boolean;
begin
  Result:=False;Audio:=Default(TDecodedAudio);DataStart:=-1;DataSize:=0;IsFloat64:=False;
  Channels:=0;Rate:=0;Align:=0;Input.Position:=12;
  while Input.Position+8<=Input.Size do begin
    if Assigned(Cancel) and Cancel() then Abort;
    Input.ReadBuffer(Tag,4);Input.ReadBuffer(Size,4);Next:=Input.Position+Int64(Size)+(Size and 1);
    if Next>Input.Size then raise Exception.Create('WAVチャンクが途中で切れています。');
    if (Tag[0]='f') and (Tag[1]='m') and (Tag[2]='t') and (Tag[3]=' ') then begin
      if (Size<16) or (Size>65536) then raise Exception.Create('WAVのfmtチャンクが不正です。');
      SetLength(Fmt,Size);Input.ReadBuffer(Fmt[0],Size);
      Move(Fmt[0],Format,2);Move(Fmt[2],Channels,2);Move(Fmt[4],Rate,4);Move(Fmt[12],Align,2);Move(Fmt[14],Bits,2);
      if Bits<>64 then Exit;
      IsFloat64:=Format=3;
      if (Format=$FFFE) and (Size>=40) then begin Move(Fmt[24],SubType,16);IsFloat64:=IsEqualGUID(SubType,FloatSubType);end;
      if not IsFloat64 or not (Channels in [1,2]) then Exit;
      if (Rate=0) or (Rate>768000) or (Align<>Channels*8) then raise Exception.Create('64bit float WAVの形式が不正です。');
    end else if (Tag[0]='d') and (Tag[1]='a') and (Tag[2]='t') and (Tag[3]='a') then begin
      DataStart:=Input.Position;DataSize:=Size;
    end;
    Input.Position:=Next;
  end;
  if not IsFloat64 then Exit;
  if (DataStart<0) or (DataSize=0) or (DataSize mod Align<>0) or (DataSize div 4>MaxPCMBytes) then
    raise Exception.Create('64bit float WAVの音声データが不正、または上限を超えています。');
  Audio.SampleRate:=Rate;Audio.Channels:=Channels;SampleCount:=DataSize div 8;
  SetLength(Audio.PCM,SampleCount*2);Input.Position:=DataStart;Done:=0;
  while Done<SampleCount do begin
    if Assigned(Cancel) and Cancel() then Abort;
    Count:=Min(Int64(Length(Chunk)),SampleCount-Done);Input.ReadBuffer(Chunk,Count*8);
    for I:=0 to Count-1 do begin
      Value:=Chunk[I];
      if IsNan(Value) or IsInfinite(Value) then raise Exception.Create('WAVに有限でない音声サンプルがあります。');
      if Value>=1 then Sample:=32767 else if Value<=-1 then Sample:=-32768 else Sample:=EnsureRange(Round(Value*32768),-32768,32767);
      Move(Sample,Audio.PCM[(Done+I)*2],2);
    end;
    Inc(Done,Count);
  end;
  Result:=True;
end;

procedure VerifyPCM(const Reader:IMFSourceReader;ExpectedRate,ExpectedChannels:Cardinal);
var MediaType:IMFMediaType;Kind:TGUID;Rate,Channels,Bits:Cardinal;
begin
  OleCheck(Reader.GetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM,MediaType));
  OleCheck(MediaType.GetGUID(MF_MT_SUBTYPE,Kind));
  OleCheck(MediaType.GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,Rate));
  OleCheck(MediaType.GetUINT32(MF_MT_AUDIO_NUM_CHANNELS,Channels));
  OleCheck(MediaType.GetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,Bits));
  if not IsEqualGUID(Kind,MFAudioFormat_PCM) or (Rate<>ExpectedRate) or (Channels<>ExpectedChannels) or (Bits<>16) then
    raise Exception.Create('WAVのPCM変換形式が一致しません。');
end;

function DecodeWavePCM44100(const FileName:string;const Cancel:TFunc<Boolean>):TBytes;
var Input:TFileStream;Output:TMemoryStream;Reader:IMFSourceReader;MediaType:IMFMediaType;
  Sample:IMFSample;Buffer:IMFMediaBuffer;Data:PByte;Count,Flags:DWORD;
  InitResult:HRESULT;Started:Boolean;Header:array[0..11] of AnsiChar;StartTick:UInt64;
  NativeType:IMFMediaType;Rate,Channels:Cardinal;Audio:TDecodedAudio;
  procedure CheckCancel;
  begin
    if Assigned(Cancel) and Cancel() then Abort;
    if GetTickCount64-StartTick>180000 then raise Exception.Create('WAVの変換が制限時間を超えました。');
  end;
begin
  Result:=nil;Started:=False;Output:=nil;StartTick:=GetTickCount64;
  CheckCancel;
  Input:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if Input.Size<12 then raise Exception.Create('WAVヘッダーが短すぎます。');
    Input.ReadBuffer(Header,SizeOf(Header));
    if not ((Header[0]='R') and (Header[1]='I') and (Header[2]='F') and (Header[3]='F') and
      (Header[8]='W') and (Header[9]='A') and (Header[10]='V') and (Header[11]='E')) then
      raise Exception.Create('RIFF/WAVE形式のファイルを指定してください。');
    if TryReadFloat64Wave(Input,Cancel,Audio) then begin Result:=ToStereo44100(Audio,Cancel);CheckCancel;Exit;end;
    InitResult:=CoInitializeEx(nil,COINIT_MULTITHREADED);
    if InitResult<>RPC_E_CHANGED_MODE then OleCheck(InitResult);
    try
      OleCheck(MFStartup(MF_VERSION,MFSTARTUP_NOSOCKET));Started:=True;
      OleCheck(MFCreateSourceReaderFromURL(PChar(ExpandFileName(FileName)),nil,Reader));
      OleCheck(Reader.SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS,False));
      OleCheck(Reader.SetStreamSelection(MF_SOURCE_READER_FIRST_AUDIO_STREAM,True));
      OleCheck(Reader.GetNativeMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM,0,NativeType));
      OleCheck(NativeType.GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,Rate));
      OleCheck(NativeType.GetUINT32(MF_MT_AUDIO_NUM_CHANNELS,Channels));
      Channels:=Min(Channels,2);
      if (Rate=0) or (Rate>768000) or (Channels=0) then raise Exception.Create('WAVの音声形式が不正です。');
      OleCheck(MFCreateMediaType(MediaType));
      OleCheck(MediaType.SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Audio));
      OleCheck(MediaType.SetGUID(MF_MT_SUBTYPE,MFAudioFormat_PCM));
      OleCheck(MediaType.SetUINT32(MF_MT_AUDIO_NUM_CHANNELS,Channels));
      OleCheck(MediaType.SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,Rate));
      OleCheck(MediaType.SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,16));
      OleCheck(MediaType.SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT,Channels*2));
      OleCheck(MediaType.SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,Rate*Channels*2));
      OleCheck(Reader.SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM,nil,MediaType));
      VerifyPCM(Reader,Rate,Channels);Output:=TMemoryStream.Create;
      repeat
        CheckCancel;Sample:=nil;Flags:=0;
        OleCheck(Reader.ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM,0,nil,@Flags,nil,Sample));
        if Flags and MF_SOURCE_READERF_ERROR<>0 then raise Exception.Create('WAVの読み込み中にエラーが発生しました。');
        if Flags and MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED<>0 then VerifyPCM(Reader,Rate,Channels);
        if Sample<>nil then begin
          OleCheck(Sample.ConvertToContiguousBuffer(Buffer));
          OleCheck(Buffer.Lock(Data,nil,@Count));
          try
            if Output.Size+Count>MaxPCMBytes then raise Exception.Create('WAVのPCMが512 MiBの上限を超えています。');
            if Count>0 then Output.WriteBuffer(Data^,Count);
          finally Buffer.Unlock;end;
          Buffer:=nil;Sample:=nil;
        end;
      until Flags and MF_SOURCE_READERF_ENDOFSTREAM<>0;
      CheckCancel;
      if (Output.Size=0) or (Output.Size mod (Channels*2)<>0) then raise Exception.Create('WAVの音声サンプルを取得できませんでした。');
      Audio:=Default(TDecodedAudio);Audio.SampleRate:=Rate;Audio.Channels:=Channels;
      SetLength(Audio.PCM,Output.Size);Output.Position:=0;Output.ReadBuffer(Audio.PCM[0],Length(Audio.PCM));
      // Windowsのリサンプル終端丸めを避け、MP3と同じサンプル数規則で変換する。
      Result:=ToStereo44100(Audio,Cancel);CheckCancel;
    finally
      Buffer:=nil;Sample:=nil;MediaType:=nil;NativeType:=nil;Reader:=nil;
      if Started then MFShutdown;
      if Succeeded(InitResult) then CoUninitialize;
    end;
  finally Output.Free;Input.Free;end;
end;
end.
