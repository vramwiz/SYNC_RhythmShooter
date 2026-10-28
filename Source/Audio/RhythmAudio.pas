unit RhythmAudio;
{$POINTERMATH ON}

interface

uses System.Classes, System.SysUtils;

const RHYTHM_RATE = 44100;

type
  TRhythmHit = record
    Time, Strength, Lane, Flight: Double;
  end;
  TRhythmAudio = class
  public
    Source, Key, PcmPath: string;
    PCM: TBytes;
    Envelope: TArray<Single>;
    Hits: TArray<TRhythmHit>;
    Duration,SoundEnd: Double;
    Sensitivity: Integer;
    CacheReused: Boolean;
    procedure Detect;
    procedure UpdateSoundBounds;
    function NearestHit(Time: Double): Integer;
  end;
  TRhythmLoadThread = class(TThread)
  private
    FSource: string;
    FSensitivity: Integer;
    FForce:Boolean;
  protected
    procedure Execute; override;
  public
    Audio: TRhythmAudio;
    Error: string;
    constructor Create(const Source: string; Sensitivity: Integer;Force:Boolean=False);
    destructor Destroy; override;
    function TakeAudio: TRhythmAudio;
  end;

function LoadRhythmAudio(const Source: string; Sensitivity: Integer;
  const Cancel: TFunc<Boolean> = nil): TRhythmAudio;
// Runtime only reads prepared data. Missing/stale caches never start analysis.
function LoadCachedRhythmAudio(const Source:string;Sensitivity:Integer):TRhythmAudio;

implementation

uses Winapi.Windows, System.IOUtils, System.Hash, System.Math,
  System.Generics.Collections, System.JSON, RhythmPaths, RhythmMotion, MimiChildProcess;

function Cancelled(const Cancel: TFunc<Boolean>): Boolean;
begin Result := Assigned(Cancel) and Cancel(); end;

procedure TRhythmAudio.UpdateSoundBounds;
var Peak:Double;I:Integer;
begin
  SoundEnd:=0;Peak:=0;for I:=0 to High(Envelope) do Peak:=Max(Peak,Envelope[I]);
  for I:=High(Envelope) downto 0 do
    if Envelope[I]>Max(0.0001,Peak*0.015) then begin SoundEnd:=Min(Duration,(I+1)*0.01);Break;end;
end;

procedure TRhythmAudio.Detect;
const Hop = 441;
var
  Frame, Count, I, J, First, Last, LastPeak: Integer;
  Sum, L, R, Prior, Mean, Score, Threshold, Peak, GlobalPeak: Double;
  Flux: TArray<Double>;
  Found: TList<TRhythmHit>;
  H: TRhythmHit;
  Samples: PSmallInt;
begin
  Count := Length(PCM) div 4;
  Duration := Count / RHYTHM_RATE;
  SetLength(Envelope, (Count + Hop - 1) div Hop);
  SetLength(Flux, Length(Envelope));
  Samples := PSmallInt(PCM);
  GlobalPeak := 0;
  for I := 0 to High(Envelope) do
  begin
    Sum := 0; First := I * Hop; Last := Min(Count, First + Hop);
    for Frame := First to Last - 1 do
    begin
      L := Samples[Frame * 2] / 32768.0;
      R := Samples[Frame * 2 + 1] / 32768.0;
      Sum := Sum + (L * L + R * R) * 0.5;
    end;
    Envelope[I] := Sqrt(Sum / Max(1, Last - First));
    GlobalPeak := Max(GlobalPeak, Envelope[I]);
  end;
  Prior := 0;
  for I := 0 to High(Envelope) do
  begin
    Flux[I] := Max(0.0, Envelope[I] - Prior);
    Prior := Prior * 0.55 + Envelope[I] * 0.45;
  end;
  Found := TList<TRhythmHit>.Create;
  try
    LastPeak := -1000;
    for I := 2 to High(Envelope) - 2 do
    begin
      Mean := 0; First := Max(0, I - 40); Last := Min(High(Flux), I + 40);
      for J := First to Last do Mean := Mean + Flux[J];
      Mean := Mean / (Last - First + 1);
      Threshold := Max(GlobalPeak * 0.012, Mean * (3.5 - Sensitivity * 0.025));
      Score := Flux[I];
      if (Score <= Threshold) or (Score < Flux[I-1]) or (Score <= Flux[I+1]) or
        (Envelope[I] < GlobalPeak * 0.035) then Continue;
      // 180 ms of separation keeps fast arrangements readable. The larger
      // local onset replaces a weaker candidate rather than shifting its time.
      if (I - LastPeak < 18) and (Found.Count > 0) then
      begin
        if Score <= Flux[LastPeak] then Continue;
        Found.Delete(Found.Count - 1);
      end;
      H.Time := I * Hop / RHYTHM_RATE;
      Peak := EnsureRange(Score / Max(0.000001, GlobalPeak * 0.22), 0.15, 1.0);
      H.Strength := Peak;
      // A bounded integer hash provides stable variation without global RNG state.
      J := (I * 73 + (I mod 17) * 131) mod 997;
      H.Lane := 0.14 + J / 996.0 * 0.72;
      H.Flight := ShotFlightTime(H.Time,H.Lane,H.Strength);
      if H.Time >= 0.12 then Found.Add(H);
      LastPeak := I;
    end;
    Hits := Found.ToArray;UpdateSoundBounds;
  finally Found.Free; end;
end;

function TRhythmAudio.NearestHit(Time: Double): Integer;
var A, B, M: Integer;
begin
  A := 0; B := Length(Hits);
  while A < B do
  begin
    M := (A + B) div 2;
    if Hits[M].Time < Time then A := M + 1 else B := M;
  end;
  Result := Min(A, High(Hits));
end;

function SourceStamp(const Source:string):string;
var Info:TWin32FileAttributeData;
begin
  if not GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Info) then RaiseLastOSError;
  Result:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+
    IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
end;
function IndexPath(const Source:string;Sensitivity:Integer):string;
begin Result:=TPath.Combine(CacheFolder,THashSHA2.GetHashString(LowerCase(ExpandFileName(Source)))+'-s'+IntToStr(Sensitivity)+'-index.json');end;
function EventsPath(const Key:string;Sensitivity:Integer):string;
begin Result:=TPath.Combine(CacheFolder,Key+'-s'+IntToStr(Sensitivity)+'-events-v1.json');end;
procedure WriteEvents(Audio: TRhythmAudio);
var Root, Item,Index: TJSONObject; Events,Envelope: TJSONArray; H: TRhythmHit;V:Single;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(1));
    Root.AddPair('sourceSHA256', Audio.Key);
    Root.AddPair('sensitivity', TJSONNumber.Create(Audio.Sensitivity));
    Root.AddPair('duration', TJSONNumber.Create(Audio.Duration));
    Root.AddPair('analysisVersion',TJSONNumber.Create(2));
    Envelope:=TJSONArray.Create;Root.AddPair('envelope',Envelope);
    for V in Audio.Envelope do Envelope.Add(V);
    Events := TJSONArray.Create; Root.AddPair('hits', Events);
    for H in Audio.Hits do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('time', TJSONNumber.Create(H.Time));
      Item.AddPair('strength', TJSONNumber.Create(H.Strength));
      Item.AddPair('lane', TJSONNumber.Create(H.Lane));
      Item.AddPair('flight', TJSONNumber.Create(H.Flight));
      Events.AddElement(Item);
    end;
    TFile.WriteAllText(EventsPath(Audio.Key,Audio.Sensitivity),Root.ToJSON,TEncoding.UTF8);
    Index:=TJSONObject.Create;
    try
      Index.AddPair('sourceSHA256',Audio.Key);Index.AddPair('sourceStamp',SourceStamp(Audio.Source));
      TFile.WriteAllText(IndexPath(Audio.Source,Audio.Sensitivity),Index.ToJSON,TEncoding.UTF8);
    finally Index.Free;end;
  finally Root.Free; end;
end;

function LoadCachedRhythmAudio(const Source:string;Sensitivity:Integer):TRhythmAudio;
var Index,Root:TJSONObject;J:TJSONValue;Envelope,Hits:TJSONArray;I:Integer;Key,Path:string;
begin
  Result:=nil;Index:=nil;Root:=nil;
  try
    try
      J:=TJSONObject.ParseJSONValue(TFile.ReadAllText(IndexPath(Source,Sensitivity),TEncoding.UTF8));
      if not (J is TJSONObject) then begin J.Free;Exit;end;Index:=TJSONObject(J);
      if Index.GetValue<string>('sourceStamp','')<>SourceStamp(Source) then Exit;
      Key:=Index.GetValue<string>('sourceSHA256','');if Length(Key)<>64 then Exit;
      for I:=1 to Length(Key) do if not CharInSet(Key[I],['0'..'9','a'..'f','A'..'F']) then Exit;
      J:=TJSONObject.ParseJSONValue(TFile.ReadAllText(EventsPath(Key,Sensitivity),TEncoding.UTF8));
      if not (J is TJSONObject) then begin J.Free;Exit;end;Root:=TJSONObject(J);
      if (Root.GetValue<Integer>('analysisVersion',0)<>2) or (Root.GetValue<string>('sourceSHA256','')<>Key) or
        (Root.GetValue<Integer>('sensitivity',0)<>Sensitivity) then Exit;
      Envelope:=Root.GetValue<TJSONArray>('envelope');Hits:=Root.GetValue<TJSONArray>('hits');
      if (Envelope=nil) or (Hits=nil) then Exit;
      Path:=TPath.Combine(CacheFolder,Key+'-44100-stereo-v1.pcm');
      if (TFile.GetSize(Path)<4) or (TFile.GetSize(Path) mod 4<>0) or (TFile.GetSize(Path)>512*Int64(1024)*1024) then Exit;
      Result:=TRhythmAudio.Create;Result.Source:=ExpandFileName(Source);Result.Key:=Key;Result.PcmPath:=Path;
      Result.Sensitivity:=Sensitivity;Result.CacheReused:=True;Result.PCM:=TFile.ReadAllBytes(Path);
      Result.Duration:=Length(Result.PCM)/4/RHYTHM_RATE;
      if Abs(Result.Duration-Root.GetValue<Double>('duration',0))>0.0001 then raise Exception.Create('Cache duration mismatch');
      if Envelope.Count<>((Length(Result.PCM) div 4+440) div 441) then raise Exception.Create('Cache waveform length mismatch');
      SetLength(Result.Envelope,Envelope.Count);for I:=0 to Envelope.Count-1 do begin
        Result.Envelope[I]:=Envelope.Items[I].GetValue<Single>;
        if IsNan(Result.Envelope[I]) or IsInfinite(Result.Envelope[I]) or (Result.Envelope[I]<0) or (Result.Envelope[I]>1) then raise Exception.Create('Cache waveform invalid');
      end;
      SetLength(Result.Hits,Hits.Count);for I:=0 to Hits.Count-1 do
      begin
        if not (Hits.Items[I] is TJSONObject) then raise Exception.Create('Cache event invalid');
        Result.Hits[I].Time:=TJSONObject(Hits.Items[I]).GetValue<Double>('time');
        Result.Hits[I].Strength:=TJSONObject(Hits.Items[I]).GetValue<Double>('strength');
        Result.Hits[I].Lane:=TJSONObject(Hits.Items[I]).GetValue<Double>('lane');
        Result.Hits[I].Flight:=ShotFlightTime(Result.Hits[I].Time,Result.Hits[I].Lane,Result.Hits[I].Strength);
        if IsNan(Result.Hits[I].Time) or IsInfinite(Result.Hits[I].Time) or IsNan(Result.Hits[I].Strength) or IsInfinite(Result.Hits[I].Strength) or
          IsNan(Result.Hits[I].Lane) or IsInfinite(Result.Hits[I].Lane) or (Result.Hits[I].Strength<0) or (Result.Hits[I].Strength>1) or
          (Result.Hits[I].Lane<0) or (Result.Hits[I].Lane>1) or (Result.Hits[I].Time<0) or (Result.Hits[I].Time>Result.Duration) or
          ((I>0) and (Result.Hits[I].Time<=Result.Hits[I-1].Time)) then raise Exception.Create('Cache event order invalid');
      end;
      Result.UpdateSoundBounds;
    except FreeAndNil(Result);end;
  finally Root.Free;Index.Free;end;
end;

function LoadRhythmAudio(const Source: string; Sensitivity: Integer;
  const Cancel: TFunc<Boolean>): TRhythmAudio;
var Input: TFileStream; Buffer: TBytes; Hash: THashSHA2; N: Integer;
  Ext, Temp, Log, OutLog, Exe, FinalPath: string; Id: TGUID;
begin
  Ext := LowerCase(ExtractFileExt(Source));
  if (Ext <> '.wav') and (Ext <> '.mp3') then raise Exception.Create('WAV / MP3 を指定してください。');
  Input := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite);
  Result := TRhythmAudio.Create;
  try
    Hash := THashSHA2.Create;
    SetLength(Buffer, 1024 * 1024);
    repeat
      if Cancelled(Cancel) then Abort;
      N := Input.Read(Buffer[0], Length(Buffer));
      if N > 0 then Hash.Update(Buffer, N);
    until N = 0;
    Result.Source := ExpandFileName(Source);
    Result.Key := Hash.HashAsString;
    Result.Sensitivity := EnsureRange(Sensitivity, 1, 100);
    FinalPath := TPath.Combine(CacheFolder, Result.Key + '-44100-stereo-v1.pcm');
    Result.CacheReused := TFile.Exists(FinalPath);
    if not Result.CacheReused then
    begin
      CreateGUID(Id);
      Temp := TPath.Combine(CacheFolder, GUIDToString(Id) + '.pcm');
      Log := ChangeFileExt(Temp, '.log'); OutLog := ChangeFileExt(Temp, '.stdout');
      Exe := TPath.Combine(ModuleFolder, 'ThirdParty\FFmpeg\bin\ffmpeg.exe');
      RunAudioTool(Exe, ['-hide_banner','-loglevel','error','-nostdin','-n',
        '-protocol_whitelist','file,pipe','-f',Copy(Ext,2,MaxInt),'-i',Result.Source,
        '-map','0:a:0','-vn','-ac','2','-ar','44100','-f','s16le',Temp],
        OutLog, Log, function: Boolean begin Result := Cancelled(Cancel); end, 180000);
      if not TFile.Exists(Temp) or (TFile.GetSize(Temp) = 0) then
        raise Exception.Create('音声サンプルを取得できませんでした。');
      if not MoveFileEx(PChar(Temp), PChar(FinalPath), MOVEFILE_WRITE_THROUGH) then
      begin
        if not TFile.Exists(FinalPath) then RaiseLastOSError;
        TFile.Delete(Temp);
      end;
    end;
    if Cancelled(Cancel) then Abort;
    if (TFile.GetSize(FinalPath) < 4) or (TFile.GetSize(FinalPath) mod 4 <> 0) or
      (TFile.GetSize(FinalPath) > 512 * Int64(1024) * 1024) then
      raise Exception.Create('PCMキャッシュが不正、または約50分のメモリ上限を超えています。');
    Result.PcmPath := FinalPath;
    Result.PCM := TFile.ReadAllBytes(FinalPath);
    Result.Detect;
    if Cancelled(Cancel) then Abort;
    WriteEvents(Result);
  except
    Result.Free;
    Input.Free;
    raise;
  end;
  Input.Free;
end;

constructor TRhythmLoadThread.Create(const Source: string; Sensitivity: Integer;Force:Boolean);
begin
  inherited Create(True); FreeOnTerminate := False;
  FSource := Source; FSensitivity := Sensitivity;FForce:=Force;
end;

procedure TRhythmLoadThread.Execute;
begin
  try
    if not FForce then Audio:=LoadCachedRhythmAudio(FSource,FSensitivity);
    if Audio=nil then Audio := LoadRhythmAudio(FSource, FSensitivity,
      function: Boolean begin Result := Terminated; end);
  except on E: Exception do Error := E.ClassName + ': ' + E.Message; end;
end;

destructor TRhythmLoadThread.Destroy;
begin Audio.Free; inherited; end;

function TRhythmLoadThread.TakeAudio: TRhythmAudio;
begin Result := Audio; Audio := nil; end;

end.
