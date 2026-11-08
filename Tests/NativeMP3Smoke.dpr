program NativeMP3Smoke;
// 実アプリのデコード・キャッシュ・再生を、FFmpegのない出力先で検証する。
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Classes,System.IOUtils,System.Math,System.Hash,System.JSON,
  Winapi.Windows,RhythmAudio,RhythmAudioCache,RhythmPaths,RhythmPlayback;
var Checks,Fixtures:Integer;Peak:Integer;Music,FixtureRoot:string;Audio:TRhythmAudio;

procedure Need(Value:Boolean;const Text:string);
begin Inc(Checks);if not Value then raise Exception.Create(Text);end;

function FileKey(const Path:string):string;
var Hash:THashSHA2;
begin Hash:=THashSHA2.Create;Hash.Update(TFile.ReadAllBytes(Path));Result:=Hash.HashAsString;end;

function ReadWave(const Path:string;out Rate,Channels:Integer):TBytes;
var S:TFileStream;Tag:array[0..3] of AnsiChar;Size:Cardinal;Code,Bits:Word;Next:Int64;
begin
  Result:=nil;Rate:=0;Channels:=0;S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    S.Position:=12;
    while S.Position+8<=S.Size do begin
      S.ReadBuffer(Tag,4);S.ReadBuffer(Size,4);Next:=S.Position+Size+(Size and 1);
      Need(Next<=S.Size,'Truncated reference WAV');
      if string(AnsiString(Tag))='fmt ' then begin
        S.ReadBuffer(Code,2);S.ReadBuffer(Channels,2);S.ReadBuffer(Rate,4);
        S.Seek(6,soCurrent);S.ReadBuffer(Bits,2);
        Need((Code=1) and (Bits=16),'Reference must be PCM16');
      end else if string(AnsiString(Tag))='data' then begin
        SetLength(Result,Size);if Size>0 then S.ReadBuffer(Result[0],Size);
      end;
      S.Position:=Next;
    end;
    Need((Rate>0) and (Channels in [1,2]) and (Length(Result)>0),'Invalid reference WAV');
  finally S.Free;end;
end;

procedure CheckFixture(const Folder:string);
var A,B:TRhythmAudio;Reference:TBytes;Rate,Channels,I,Error,LocalPeak:Integer;
  L,R:SmallInt;Power:Double;Expected:Int64;
begin
  Reference:=ReadWave(TPath.Combine(Folder,'reference.wav'),Rate,Channels);
  A:=LoadRhythmAudio(TDirectory.GetFiles(Folder,'*.mp3')[0],50);
  try
    Expected:=Ceil((Length(Reference) div (Channels*2))*44100.0/Rate);
    Need(Length(A.PCM)=Expected*4,'Reference sample count: '+Folder);
    Need(not A.CacheReused,'Fresh decode reused PCM: '+Folder);
    Need(Pos('pascal-minimp3-2',A.PcmPath)>0,'Wrong decoder cache');
    if Rate=44100 then begin
      Power:=0;LocalPeak:=0;
      for I:=0 to Length(A.PCM) div 2-1 do begin
        Move(A.PCM[I*2],L,2);
        if Channels=2 then Move(Reference[I*2],R,2)
        else begin Move(Reference[(I div 2)*2],R,2);R:=Round(R*Sqrt(0.5));end;
        Error:=Abs(Integer(L)-R);LocalPeak:=Max(LocalPeak,Error);Power:=Power+Sqr(Error);
      end;
      Peak:=Max(Peak,LocalPeak);
      Need(LocalPeak<=2,'Reference PCM peak exceeds 2 LSB');
      Need(Sqrt(Power/(Length(A.PCM) div 2))<=0.3,'Reference PCM RMS exceeds 0.3 LSB');
    end;
    B:=LoadCachedRhythmAudio(A.Source,50,True);
    try
      Need(B<>nil,'PCM cache restore failed');
      Need((Length(B.PCM)=Length(A.PCM)) and CompareMem(@A.PCM[0],@B.PCM[0],Length(A.PCM)),'Cached PCM changed');
      Need(Length(A.Hits)=Length(B.Hits),'Cached accents changed');
    finally B.Free;end;
    B:=LoadCachedRhythmAudio(A.Source,50,False);
    try Need((B<>nil) and (Length(B.PCM)=0) and (Abs(B.Duration-A.Duration)<1E-9),'Metadata restore failed: '+Folder);
    finally B.Free;end;
    B:=LoadRhythmAudio(A.Source,50);
    try Need(B.CacheReused,'Second decode did not reuse native PCM');finally B.Free;end;
    Inc(Fixtures);
  finally A.Free;end;
end;

procedure CheckLegacyIsolation;
var Path,Key,Index,Events,PCM,EnvelopeText,LegacyHash:string;A:TRhythmAudio;Bytes:TBytes;I:Integer;
begin
  Path:=TPath.Combine(FixtureRoot,'rate44100_ch2_cbr\input.mp3');
  Key:=FileKey(Path);
  Index:=TPath.Combine(CacheFolder,THashSHA2.GetHashString(LowerCase(ExpandFileName(Path)))+'-s50-index.json');
  Events:=TPath.Combine(CacheFolder,Key+'-s50-events-v1.json');
  PCM:=TPath.Combine(CacheFolder,Key+'-44100-stereo-v1.pcm');
  TFile.WriteAllText(Index,'{"sourceSHA256":"'+Key+'","sourceStamp":"'+AudioSourceStamp(Path)+'"}');
  EnvelopeText:='0';for I:=1 to 99 do EnvelopeText:=EnvelopeText+',0';
  TFile.WriteAllText(Events,'{"analysisVersion":2,"sourceSHA256":"'+Key+'","sensitivity":50,"duration":1,"envelope":['+EnvelopeText+'],"hits":[]}');
  SetLength(Bytes,44100*4);FillChar(Bytes[0],Length(Bytes),$5A);TFile.WriteAllBytes(PCM,Bytes);
  LegacyHash:=FileKey(PCM);
  A:=LoadCachedRhythmAudio(Path,50);
  try Need(A=nil,'Legacy analysis cache was accepted');finally A.Free;end;
  CheckFixture(ExtractFileDir(Path));
  Need(FileKey(PCM)=LegacyHash,'Legacy PCM was changed');
  Need(TFile.Exists(Index) and TFile.Exists(Events),'Legacy analysis was removed');
end;

procedure CheckCancellation;
var A:TRhythmAudio;Aborted:Boolean;Count:Integer;Path:string;
begin
  Path:=TPath.Combine(FixtureRoot,'rate48000_ch2_cbr\input.mp3');
  Count:=0;Aborted:=False;A:=nil;
  try
    A:=LoadRhythmAudio(Path,50,function:Boolean begin Inc(Count);Result:=Count>=8;end);
  except on E:EAbort do Aborted:=True;end;
  A.Free;Need(Aborted,'Frame cancellation did not abort');
  Need(not TFile.Exists(AudioPCMCachePath(Path,FileKey(Path))),'Cancelled decode published PCM');
  Need(Length(TDirectory.GetFiles(CacheFolder,'{*.pcm'))=0,'Cancelled temporary PCM remains');
  Aborted:=False;A:=nil;
  try
    A:=LoadRhythmAudio(Path,50,function:Boolean
      begin Result:=Length(TDirectory.GetFiles(CacheFolder,'{*.pcm'))>0;end);
  except on E:EAbort do Aborted:=True;end;
  A.Free;Need(Aborted,'Cancellation before publication did not abort');
  Need(not TFile.Exists(AudioPCMCachePath(Path,FileKey(Path))),'Late cancellation published PCM');
  Need(Length(TDirectory.GetFiles(CacheFolder,'{*.pcm'))=0,'Late cancellation left temporary PCM');
end;

procedure CheckInvalid;
var Name:string;Failed:Boolean;A:TRhythmAudio;
begin
  for Name in ['empty','text','header_only','truncated_half','truncated_tail','damaged_middle','random'] do begin
    Failed:=False;A:=nil;
    try A:=LoadRhythmAudio(TPath.Combine(FixtureRoot,Name+'\input.mp3'),50);
    except on E:EExternalException do raise;on E:Exception do Failed:=True;end;
    A.Free;Need(Failed,'Invalid MP3 accepted: '+Name);
  end;
end;

procedure CheckPlayback(A:TRhythmAudio);
var Player:TRhythmPlayback;T1,T2:Double;
begin
  Player:=TRhythmPlayback.Create;
  try
    Player.SetAudio(A);Player.Play;Sleep(120);T1:=Player.Position;Sleep(120);
    Need(Player.Position>T1,'Playback clock did not advance');
    Player.Pause;T1:=Player.Position;Sleep(80);Need(Abs(Player.Position-T1)<0.025,'Pause clock changed');
    T2:=Min(1.0,A.Duration*0.5);Player.Seek(T2);
    Need(Player.Paused and (Abs(Player.Position-T2)<0.025),'Paused seek failed');
    Player.Play;Sleep(120);Need(Player.Position>T2,'Resume failed');
    Player.Stop;Need(Abs(Player.Position)<1E-9,'Stop failed');
  finally Player.Free;end;
end;

var Folder:string;Report:TJSONObject;DoAudio:Boolean;
begin
  Audio:=nil;Report:=TJSONObject.Create;
  try
    try
      Need(ParamCount>=1,'Pass fixture directory, optional music.mp3, optional --audio');
      FixtureRoot:=ExpandFileName(ParamStr(1));DoAudio:=(ParamStr(ParamCount)='--audio');
      Need(not TFile.Exists(TPath.Combine(ModuleFolder,'ThirdParty\FFmpeg\bin\ffmpeg.exe')),'Test output must have no FFmpeg');
      CheckLegacyIsolation;CheckCancellation;
      for Folder in TDirectory.GetDirectories(FixtureRoot) do
        if TFile.Exists(TPath.Combine(Folder,'reference.wav')) and
          not SameText(ExtractFileName(Folder),'rate44100_ch2_cbr') then CheckFixture(Folder);
      CheckInvalid;
      if (ParamCount>=2) and (ParamStr(2)<>'--audio') then Music:=ParamStr(2)
      else Music:=TPath.Combine(FixtureRoot,'rate44100_ch2_cbr\input.mp3');
      Audio:=LoadRhythmAudio(Music,50);Need(Length(Audio.PCM)>0,'Music decode is empty');
      Report.AddPair('musicDuration',TJSONNumber.Create(Audio.Duration));
      Report.AddPair('musicAccents',TJSONNumber.Create(Length(Audio.Hits)));
      if DoAudio then CheckPlayback(Audio);
      Report.AddPair('audioDeviceTest',TJSONBool.Create(DoAudio));
      Report.AddPair('fixtures',TJSONNumber.Create(Fixtures));
      Report.AddPair('checks',TJSONNumber.Create(Checks));
      Report.AddPair('peak44100LSB',TJSONNumber.Create(Peak));
      Report.AddPair('result','passed');
    except on E:Exception do begin Report.AddPair('result','failed');Report.AddPair('error',E.ClassName+': '+E.Message);ExitCode:=1;end;end;
    TFile.WriteAllText(TPath.Combine(ModuleFolder,'native-mp3-smoke.json'),Report.ToJSON,TEncoding.UTF8);
    Writeln(Report.ToJSON);
  finally Audio.Free;Report.Free;end;
end.
