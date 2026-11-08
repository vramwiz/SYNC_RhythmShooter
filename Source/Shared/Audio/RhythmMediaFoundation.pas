unit RhythmMediaFoundation;
// WAV用Media Foundation ABI。Windows SDK 10.0.19041のmfobjects/mfreadwrite/mfapiから必要な宣言を定義。
interface
uses Winapi.Windows;
type
  IMFAttributes=interface;
  IMFMediaType=interface;
  IMFMediaBuffer=interface;
  IMFSample=interface;
  // この経路で使わないPROPVARIANT引数は不透明なポインターとして保持する。
  IMFAttributes=interface(IUnknown)
    ['{2CD2D921-C447-44A7-A13C-4ADABFC247E3}']
    function GetItem(const Key:TGUID;Value:Pointer):HRESULT;stdcall;
    function GetItemType(const Key:TGUID;out Kind:Integer):HRESULT;stdcall;
    function CompareItem(const Key:TGUID;Value:Pointer;out Equal:BOOL):HRESULT;stdcall;
    function Compare(const Other:IMFAttributes;Mode:Integer;out Equal:BOOL):HRESULT;stdcall;
    function GetUINT32(const Key:TGUID;out Value:Cardinal):HRESULT;stdcall;
    function GetUINT64(const Key:TGUID;out Value:UInt64):HRESULT;stdcall;
    function GetDouble(const Key:TGUID;out Value:Double):HRESULT;stdcall;
    function GetGUID(const Key:TGUID;out Value:TGUID):HRESULT;stdcall;
    function GetStringLength(const Key:TGUID;out Count:Cardinal):HRESULT;stdcall;
    function GetString(const Key:TGUID;Value:PWideChar;Capacity:Cardinal;Count:PCardinal):HRESULT;stdcall;
    function GetAllocatedString(const Key:TGUID;out Value:PWideChar;out Count:Cardinal):HRESULT;stdcall;
    function GetBlobSize(const Key:TGUID;out Count:Cardinal):HRESULT;stdcall;
    function GetBlob(const Key:TGUID;Value:PByte;Capacity:Cardinal;Count:PCardinal):HRESULT;stdcall;
    function GetAllocatedBlob(const Key:TGUID;out Value:PByte;out Count:Cardinal):HRESULT;stdcall;
    function GetUnknown(const Key,IID:TGUID;out Value):HRESULT;stdcall;
    function SetItem(const Key:TGUID;Value:Pointer):HRESULT;stdcall;
    function DeleteItem(const Key:TGUID):HRESULT;stdcall;
    function DeleteAllItems:HRESULT;stdcall;
    function SetUINT32(const Key:TGUID;Value:Cardinal):HRESULT;stdcall;
    function SetUINT64(const Key:TGUID;Value:UInt64):HRESULT;stdcall;
    function SetDouble(const Key:TGUID;Value:Double):HRESULT;stdcall;
    function SetGUID(const Key,Value:TGUID):HRESULT;stdcall;
    function SetString(const Key:TGUID;Value:PWideChar):HRESULT;stdcall;
    function SetBlob(const Key:TGUID;Value:PByte;Count:Cardinal):HRESULT;stdcall;
    function SetUnknown(const Key:TGUID;const Value:IUnknown):HRESULT;stdcall;
    function LockStore:HRESULT;stdcall;
    function UnlockStore:HRESULT;stdcall;
    function GetCount(out Count:Cardinal):HRESULT;stdcall;
    function GetItemByIndex(Index:Cardinal;out Key:TGUID;Value:Pointer):HRESULT;stdcall;
    function CopyAllItems(const Destination:IMFAttributes):HRESULT;stdcall;
  end;
  IMFMediaType=interface(IMFAttributes)
    ['{44AE0FA8-EA31-4109-8D2E-4CAE4997C555}']
    function GetMajorType(out Major:TGUID):HRESULT;stdcall;
    function IsCompressedFormat(out Compressed:BOOL):HRESULT;stdcall;
    function IsEqual(const Other:IMFMediaType;out Flags:DWORD):HRESULT;stdcall;
    function GetRepresentation(Kind:TGUID;out Value:Pointer):HRESULT;stdcall;
    function FreeRepresentation(Kind:TGUID;Value:Pointer):HRESULT;stdcall;
  end;
  IMFMediaBuffer=interface(IUnknown)
    ['{045FA593-8799-42B8-BC8D-8968C6453507}']
    function Lock(out Data:PByte;Capacity,Count:PCardinal):HRESULT;stdcall;
    function Unlock:HRESULT;stdcall;
    function GetCurrentLength(out Count:Cardinal):HRESULT;stdcall;
    function SetCurrentLength(Count:Cardinal):HRESULT;stdcall;
    function GetMaxLength(out Count:Cardinal):HRESULT;stdcall;
  end;
  IMFSample=interface(IMFAttributes)
    ['{C40A00F2-B93A-4D80-AE8C-5A1C634F58E4}']
    function GetSampleFlags(out Flags:DWORD):HRESULT;stdcall;
    function SetSampleFlags(Flags:DWORD):HRESULT;stdcall;
    function GetSampleTime(out Time:Int64):HRESULT;stdcall;
    function SetSampleTime(Time:Int64):HRESULT;stdcall;
    function GetSampleDuration(out Duration:Int64):HRESULT;stdcall;
    function SetSampleDuration(Duration:Int64):HRESULT;stdcall;
    function GetBufferCount(out Count:DWORD):HRESULT;stdcall;
    function GetBufferByIndex(Index:DWORD;out Buffer:IMFMediaBuffer):HRESULT;stdcall;
    function ConvertToContiguousBuffer(out Buffer:IMFMediaBuffer):HRESULT;stdcall;
    function AddBuffer(const Buffer:IMFMediaBuffer):HRESULT;stdcall;
    function RemoveBufferByIndex(Index:DWORD):HRESULT;stdcall;
    function RemoveAllBuffers:HRESULT;stdcall;
    function GetTotalLength(out Count:DWORD):HRESULT;stdcall;
    function CopyToBuffer(const Buffer:IMFMediaBuffer):HRESULT;stdcall;
  end;
  IMFSourceReader=interface(IUnknown)
    ['{70AE66F2-C809-4E4F-8915-BDCB406B7993}']
    function GetStreamSelection(Index:DWORD;out Selected:BOOL):HRESULT;stdcall;
    function SetStreamSelection(Index:DWORD;Selected:BOOL):HRESULT;stdcall;
    function GetNativeMediaType(Index,TypeIndex:DWORD;out MediaType:IMFMediaType):HRESULT;stdcall;
    function GetCurrentMediaType(Index:DWORD;out MediaType:IMFMediaType):HRESULT;stdcall;
    function SetCurrentMediaType(Index:DWORD;Reserved:PDWORD;const MediaType:IMFMediaType):HRESULT;stdcall;
    function SetCurrentPosition(const Format:TGUID;Position:Pointer):HRESULT;stdcall;
    function ReadSample(Index,Control:DWORD;ActualIndex,Flags:PDWORD;Timestamp:PInt64;out Sample:IMFSample):HRESULT;stdcall;
    function Flush(Index:DWORD):HRESULT;stdcall;
    function GetServiceForStream(Index:DWORD;const Service,IID:TGUID;out Value):HRESULT;stdcall;
    function GetPresentationAttribute(Index:DWORD;const Attribute:TGUID;Value:Pointer):HRESULT;stdcall;
  end;
const
  MF_VERSION=$00020070;
  MFSTARTUP_NOSOCKET=1;
  MF_SOURCE_READER_ALL_STREAMS=DWORD($FFFFFFFE);
  MF_SOURCE_READER_FIRST_AUDIO_STREAM=DWORD($FFFFFFFD);
  MF_SOURCE_READERF_ERROR=1;
  MF_SOURCE_READERF_ENDOFSTREAM=2;
  MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED=$20;
  MF_MT_MAJOR_TYPE:TGUID='{48EBA18E-F8C9-4687-BF11-0A74C9F96A8F}';
  MF_MT_SUBTYPE:TGUID='{F7E34C9A-42E8-4714-B74B-CB29D72C35E5}';
  MFMediaType_Audio:TGUID='{73647561-0000-0010-8000-00AA00389B71}';
  MFAudioFormat_PCM:TGUID='{00000001-0000-0010-8000-00AA00389B71}';
  MF_MT_AUDIO_NUM_CHANNELS:TGUID='{37E48BF5-645E-4C5B-89DE-ADA9E29B696A}';
  MF_MT_AUDIO_SAMPLES_PER_SECOND:TGUID='{5FAEEAE7-0290-4C31-9E8A-C534F68D9DBA}';
  MF_MT_AUDIO_BITS_PER_SAMPLE:TGUID='{F2DEB57F-40FA-4764-AA33-ED4F2D1FF669}';
  MF_MT_AUDIO_BLOCK_ALIGNMENT:TGUID='{322DE230-9EEB-43BD-AB7A-FF412251541D}';
  MF_MT_AUDIO_AVG_BYTES_PER_SECOND:TGUID='{1AAB75C8-CFEF-451C-AB95-AC034B8E1731}';
// 遅延読み込みにより、MP3だけを使う場合にMedia Foundationへ依存しない。
function MFStartup(Version,Flags:DWORD):HRESULT;stdcall;
function MFShutdown:HRESULT;stdcall;
function MFCreateMediaType(out MediaType:IMFMediaType):HRESULT;stdcall;
function MFCreateSourceReaderFromURL(URL:PWideChar;const Attributes:IMFAttributes;out Reader:IMFSourceReader):HRESULT;stdcall;
implementation
{$WARN SYMBOL_PLATFORM OFF}
function MFStartup;external 'mfplat.dll' delayed;
function MFShutdown;external 'mfplat.dll' delayed;
function MFCreateMediaType;external 'mfplat.dll' delayed;
function MFCreateSourceReaderFromURL;external 'mfreadwrite.dll' delayed;
{$WARN SYMBOL_PLATFORM ON}
end.
