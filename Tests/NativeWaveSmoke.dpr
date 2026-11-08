program NativeWaveSmoke;
// FFmpegなしでWAVのビット深度・レート・チャンネルとキャンセルを検証する。
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Classes,System.IOUtils,System.Math,System.JSON,
  Winapi.ActiveX,Winapi.Windows,RhythmAudio,RhythmAudioCache,RhythmWaveDecode,RhythmPaths;
var Checks,Cases:Integer;Folder:string;
procedure Need(Value:Boolean;const Text:string);
begin Inc(Checks);if not Value then raise Exception.Create(Text);end;

procedure SaveWave(const Path:string;Rate,Channels,Bits:Integer;Float,Extensible,OddChunk:Boolean);
var S:TFileStream;I,C,Frames,BytesPerSample:Integer;Value:Double;F:Single;D:Double;
  V:Int64;ByteValue:Byte;WordValue:SmallInt;IntValue:Integer;Kind:Word;SubType:TGUID;
  procedure Tag(const Text:AnsiString);begin S.WriteBuffer(Text[1],4);end;
  procedure U16(Value:Word);begin S.WriteBuffer(Value,2);end;
  procedure U32(Value:Cardinal);begin S.WriteBuffer(Value,4);end;
begin
  Frames:=Rate*2;BytesPerSample:=Bits div 8;S:=TFileStream.Create(Path,fmCreate);
  try
    Tag('RIFF');U32(0);Tag('WAVE');
    if OddChunk then begin Tag('JUNK');U32(3);U32(0);end;
    Tag('fmt ');if Extensible then U32(40) else U32(16);
    Kind:=1;if Float then Kind:=3;
    if Extensible then U16($FFFE) else U16(Kind);
    U16(Channels);U32(Rate);U32(Rate*Channels*BytesPerSample);U16(Channels*BytesPerSample);U16(Bits);
    if Extensible then begin
      U16(22);U16(Bits);if Channels=6 then U32($3F) else if Channels=2 then U32(3) else U32(4);
      SubType:=StringToGUID('{00000001-0000-0010-8000-00AA00389B71}');SubType.D1:=Kind;S.WriteBuffer(SubType,16);
    end;
    Tag('data');U32(Frames*Channels*BytesPerSample);
    for I:=0 to Frames-1 do for C:=0 to Channels-1 do begin
      // 中央1秒だけ音を入れ、変換前後の開始位置と末尾を検証する。
      Value:=0;if (I>=Rate div 2) and (I<Rate*3 div 2) then
        Value:=0.2*Sin(2*Pi*(233+156*(C mod 2))*I/Rate);
      if Float then begin
        if Bits=32 then begin F:=Value;S.WriteBuffer(F,4);end else begin D:=Value;S.WriteBuffer(D,8);end;
      end else case Bits of
        8:begin ByteValue:=EnsureRange(Round(Value*128)+128,0,255);S.WriteBuffer(ByteValue,1);end;
        16:begin WordValue:=Round(Value*32768);S.WriteBuffer(WordValue,2);end;
        24:begin V:=Round(Value*8388608);IntValue:=V;S.WriteBuffer(IntValue,3);end;
        32:begin V:=Round(Value*2147483648.0);IntValue:=V;S.WriteBuffer(IntValue,4);end;
      end;
    end;
    S.Position:=4;U32(S.Size-8);
  finally S.Free;end;
end;

procedure CheckWave(Rate,Channels,Bits:Integer;Float,Extensible,OddChunk:Boolean);
var Path:string;A,B:TRhythmAudio;I,First,Last:Integer;L,R:SmallInt;Power:Double;
begin
  Path:=TPath.Combine(Folder,Format('wave-%d-%d-%d-%d-%d.wav',[Rate,Channels,Bits,Ord(Float),Ord(Extensible)]));
  SaveWave(Path,Rate,Channels,Bits,Float,Extensible,OddChunk);A:=LoadRhythmAudio(Path,50);
  try
    Need(Abs(A.Duration-2)<1/44100.0+1E-9,'WAV duration: '+Path);
    Need(Pos(WAVE_DECODER_VERSION,A.PcmPath)>0,'WAV reused legacy PCM');
    Need(not A.CacheReused,'WAV did not decode freshly');
    First:=-1;Last:=-1;Power:=0;
    for I:=0 to Length(A.PCM) div 4-1 do begin
      Move(A.PCM[I*4],L,2);Move(A.PCM[I*4+2],R,2);
      if (Abs(Integer(L))>100) or (Abs(Integer(R))>100) then begin if First<0 then First:=I;Last:=I;end;
      if (I>44100*3 div 4) and (I<44100*5 div 4) then Power:=Power+Sqr(Double(L))+Sqr(Double(R));
      if Channels=1 then Need(Abs(Integer(L)-R)<=1,'Mono conversion channel mismatch');
    end;
    Need(Abs(First/44100.0-0.5)<0.02,'WAV onset shifted');
    Need(Abs(Last/44100.0-1.5)<0.02,'WAV tail shifted');
    Need(Power>1E10,'WAV conversion produced silence');
    B:=LoadCachedRhythmAudio(Path,50,True);
    try Need((B<>nil) and (Length(B.PCM)=Length(A.PCM)) and CompareMem(@A.PCM[0],@B.PCM[0],Length(A.PCM)),'WAV PCM cache restore');
    finally B.Free;end;
    B:=LoadCachedRhythmAudio(Path,50,False);
    try Need((B<>nil) and (Length(B.PCM)=0),'WAV metadata restore');finally B.Free;end;
    Inc(Cases);
  finally A.Free;end;
end;

procedure CheckErrors;
var Aborted,Failed:Boolean;Count:Integer;Bytes:TBytes;Path:string;
begin
  Path:=TPath.Combine(Folder,'wave-48000-2-16-0-0.wav');
  Aborted:=False;
  try Bytes:=DecodeWavePCM44100(Path,function:Boolean begin Result:=True;end);
  except on E:EAbort do Aborted:=True;end;
  Need(Aborted,'Immediate WAV cancellation');
  Count:=0;Aborted:=False;
  try Bytes:=DecodeWavePCM44100(Path,function:Boolean begin Inc(Count);Result:=Count>=4;end);
  except on E:EAbort do Aborted:=True;end;
  Need(Aborted and (Count>=4),'Streaming WAV cancellation');
  Path:=TPath.Combine(Folder,'invalid.wav');TFile.WriteAllText(Path,'not a wave file');Failed:=False;
  try Bytes:=DecodeWavePCM44100(Path);except on E:EExternalException do raise;on E:Exception do Failed:=True;end;
  Need(Failed,'Invalid WAV accepted');
  Path:=TPath.Combine(Folder,'empty.wav');SaveWave(Path,44100,2,16,False,False,False);
  Bytes:=TFile.ReadAllBytes(Path);SetLength(Bytes,44);FillChar(Bytes[40],4,0);TFile.WriteAllBytes(Path,Bytes);Failed:=False;
  try Bytes:=DecodeWavePCM44100(Path);except on E:EExternalException do raise;on E:Exception do Failed:=True;end;
  Need(Failed,'Empty WAV accepted');
end;

var Rate,Channels,Bits:Integer;Report:TJSONObject;Init:HRESULT;Bytes:TBytes;
begin
  Report:=TJSONObject.Create;
  try
    try
      SetEnvironmentVariable('LOCALAPPDATA',PChar(TPath.Combine(ModuleFolder,'TestUserData-'+GUIDToString(TGUID.NewGuid))));
      Folder:=TPath.Combine(ModuleFolder,'WaveFixtures-'+GUIDToString(TGUID.NewGuid));ForceDirectories(Folder);
      Need(not TFile.Exists(TPath.Combine(ModuleFolder,'ThirdParty\FFmpeg\bin\ffmpeg.exe')),'WAV test output contains FFmpeg');
      for Rate in [8000,22050,32000,44100,48000,96000] do for Channels in [1,2] do
        CheckWave(Rate,Channels,16,False,False,True);
      for Bits in [8,24,32] do for Channels in [1,2] do CheckWave(44100,Channels,Bits,False,False,False);
      for Bits in [32,64] do CheckWave(48000,2,Bits,True,False,False);
      CheckWave(48000,2,24,False,True,True);CheckWave(48000,6,16,False,True,False);
      CheckWave(48000,2,32,True,True,False);CheckErrors;
      // 既にSTAを初期化しているGUIスレッドでも利用できることを確認する。
      Init:=CoInitializeEx(nil,COINIT_APARTMENTTHREADED);Need(Succeeded(Init),'STA initialization');
      try Bytes:=DecodeWavePCM44100(TPath.Combine(Folder,'wave-44100-2-16-0-0.wav'));Need(Length(Bytes)=2*44100*4,'STA WAV conversion');
      finally CoUninitialize;end;
      Report.AddPair('result','passed');Report.AddPair('cases',TJSONNumber.Create(Cases));Report.AddPair('checks',TJSONNumber.Create(Checks));
    except on E:Exception do begin Report.AddPair('result','failed');Report.AddPair('error',E.ClassName+': '+E.Message);ExitCode:=1;end;end;
    Writeln(Report.ToJSON);TFile.WriteAllText(TPath.Combine(ModuleFolder,'native-wave-smoke.json'),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free;end;
end.
