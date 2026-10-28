program AudioEdges;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.Math, System.JSON,
  Winapi.MMSystem, RhythmAudio in '..\Source\Audio\RhythmAudio.pas',
  RhythmPaths in '..\Source\Common\RhythmPaths.pas',
  MimiChildProcess in '..\Source\Lib\Process\MimiChildProcess.pas';
var Root:TJSONObject;Folder,Path,FirstKey,ErrorText:string;Audio:TRhythmAudio;
  Samples:TArray<SmallInt>;I,J,LowCount,HighCount:Integer;T,Age,Value,Distance:Double;Stream:TFileStream;
const Onsets:array[0..3] of Double=(0.4,1.2,2.1,3.4);
procedure Require(Value:Boolean;const Text:string);
begin if not Value then raise Exception.Create(Text);end;
procedure SaveWave(const FileName:string;const PCM:array of SmallInt);
var S:TFileStream;Size:Cardinal;Format:TWaveFormatEx;
  procedure Tag(const Text:AnsiString);
  begin S.WriteBuffer(Text[1],4);end;
begin
  S:=TFileStream.Create(FileName,fmCreate);
  try
    Tag('RIFF');Size:=36+Length(PCM)*2;S.WriteBuffer(Size,4);Tag('WAVE');Tag('fmt ');Size:=16;S.WriteBuffer(Size,4);
    FillChar(Format,SizeOf(Format),0);Format.wFormatTag:=1;Format.nChannels:=2;Format.nSamplesPerSec:=44100;
    Format.nAvgBytesPerSec:=176400;Format.nBlockAlign:=4;Format.wBitsPerSample:=16;S.WriteBuffer(Format,16);
    Tag('data');Size:=Length(PCM)*2;S.WriteBuffer(Size,4);if Length(PCM)>0 then S.WriteBuffer(PCM[0],Size);
  finally S.Free;end;
end;
begin
  Root:=TJSONObject.Create;Audio:=nil;
  try
    try
      Folder:=TPath.Combine(ModuleFolder,'Verification');ForceDirectories(Folder);Path:=TPath.Combine(Folder,'generated-pulses.wav');
      SetLength(Samples,44100*4*2);
      for I:=0 to Length(Samples) div 2-1 do
      begin
        T:=I/44100;Value:=0;
        for J:=0 to High(Onsets) do begin Age:=T-Onsets[J];if (Age>=0) and (Age<0.14) then Value:=Value+0.7*Exp(-Age*25)*Sin(Age*2*Pi*880);end;
        Samples[I*2]:=Round(Value*32767);Samples[I*2+1]:=Samples[I*2];
      end;
      SaveWave(Path,Samples);Audio:=LoadRhythmAudio(Path,50);FirstKey:=Audio.Key;
      Require(Abs(Audio.Duration-4)<1E-6,'WAV duration mismatch');Require(Length(Audio.Hits)=4,'Expected four pulse accents');
      for J:=0 to High(Onsets) do begin Distance:=100;
        for I:=0 to High(Audio.Hits) do Distance:=Min(Distance,Abs(Audio.Hits[I].Time-Onsets[J]));
        Require(Distance<=0.02,'Pulse onset timing outside 20ms');end;
      Root.AddPair('wavPulseHitCount',TJSONNumber.Create(Length(Audio.Hits)));FreeAndNil(Audio);
      Audio:=LoadRhythmAudio(Path,1);LowCount:=Length(Audio.Hits);FreeAndNil(Audio);
      Audio:=LoadRhythmAudio(Path,100);HighCount:=Length(Audio.Hits);FreeAndNil(Audio);
      Require(HighCount>=LowCount,'Higher sensitivity unexpectedly removed pulse hits');
      Root.AddPair('sensitivity1Hits',TJSONNumber.Create(LowCount));Root.AddPair('sensitivity100Hits',TJSONNumber.Create(HighCount));
      FillChar(Samples[0],Length(Samples)*2,0);SaveWave(Path,Samples);Audio:=LoadRhythmAudio(Path,50);
      Require(Audio.Key<>FirstKey,'Replacing source at same path did not change cache key');Require(Length(Audio.Hits)=0,'Silence generated false hits');
      Root.AddPair('samePathContentChange','new content hash used');Root.AddPair('silenceHits',TJSONNumber.Create(Length(Audio.Hits)));FreeAndNil(Audio);
      Path:=TPath.Combine(Folder,'generated-invalid.mp3');Stream:=TFileStream.Create(Path,fmCreate);
      try I:=$12345678;Stream.WriteBuffer(I,4);finally Stream.Free;end;
      try Audio:=LoadRhythmAudio(Path,50);except on E:Exception do ErrorText:=E.Message;end;
      Require(ErrorText<>'','Invalid MP3 was accepted');FreeAndNil(Audio);ErrorText:='';Root.AddPair('invalidMp3','reported error');
      try Audio:=LoadRhythmAudio(TPath.Combine(Folder,'does-not-exist.wav'),50);except on E:Exception do ErrorText:=E.Message;end;
      Require(ErrorText<>'','Missing file was accepted');ErrorText:='';Root.AddPair('missingFile','reported error');
      Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.ClassName+': '+E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    TFile.WriteAllText(TPath.Combine(Folder,'audio-edges.json'),Root.ToJSON,TEncoding.UTF8);Writeln(Root.ToJSON);
  finally Audio.Free;Root.Free;end;
  if ErrorText<>'' then Halt(1);
end.
