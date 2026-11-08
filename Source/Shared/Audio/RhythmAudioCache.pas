unit RhythmAudioCache;
// 準備済みキャッシュの保存／検証／復元。欠落や更新時にも解析を開始しない。
interface
uses System.SysUtils,RhythmAudioData;
function AudioSourceStamp(const Source:string):string;
function AudioSourceUnchanged(Audio:TRhythmAudio):Boolean;
function AudioPCMCachePath(const Source,Key:string):string;
procedure SaveRhythmAudioCache(Audio:TRhythmAudio);
function ReadRhythmAudioCache(const Source:string;Sensitivity:Integer;NeedPCM:Boolean=True):TRhythmAudio; overload;
function ReadRhythmAudioCache(const Source:string;Sensitivity:Integer;NeedPCM:Boolean;out Failure:string):TRhythmAudio; overload;
implementation
uses Winapi.Windows,System.IOUtils,System.Hash,System.Math,System.Generics.Collections,System.JSON,RhythmPaths,RhythmMotion,MP3Decoder;

// MP3のPCM・解析索引をデコーダー別に分離し、旧FFmpegキャッシュを保持する。
function DecoderSuffix(const Source:string):string;
begin
  Result:='';
  if SameText(ExtractFileExt(Source),'.mp3') then Result:='-'+MP3_DECODER_VERSION;
end;

function AudioPCMCachePath(const Source,Key:string):string;
var Suffix:string;
begin
  Suffix:=DecoderSuffix(Source);
  if Suffix='' then Suffix:='-v1';
  Result:=TPath.Combine(CacheFolder,Key+'-44100-stereo'+Suffix+'.pcm');
end;

function AudioSourceStamp(const Source:string):string;
var
  Info:TWin32FileAttributeData;
begin
  if not GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Info) then RaiseLastOSError;
  Result:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+
  IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
end;

function AudioSourceUnchanged(Audio:TRhythmAudio):Boolean;
begin Result:=False;
  if (Audio=nil) or (Audio.SourceRevision='') then Exit;
  try Result:=Audio.SourceRevision=AudioSourceStamp(Audio.Source);
  except Result:=False;
  end;
end;

function IndexPath(const Source:string;Sensitivity:Integer):string;
begin Result:=TPath.Combine(CacheFolder,THashSHA2.GetHashString(LowerCase(ExpandFileName(Source)))+'-s'+IntToStr(Sensitivity)+DecoderSuffix(Source)+'-index.json');
end;

function EventsPath(const Source,Key:string;Sensitivity:Integer):string;
begin Result:=TPath.Combine(CacheFolder,Key+'-s'+IntToStr(Sensitivity)+DecoderSuffix(Source)+'-events-v1.json');
end;

procedure SaveRhythmAudioCache(Audio: TRhythmAudio);
var
  Root, Item,Index: TJSONObject;
  Events,Envelope: TJSONArray;
  H: TRhythmHit;
  V:Single;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(1));
    Root.AddPair('sourceSHA256', Audio.Key);
    Root.AddPair('sensitivity', TJSONNumber.Create(Audio.Sensitivity));
    Root.AddPair('duration', TJSONNumber.Create(Audio.Duration));
    Root.AddPair('analysisVersion',TJSONNumber.Create(2));
    Envelope:=TJSONArray.Create;
    Root.AddPair('envelope',Envelope);
    for V in Audio.Envelope do Envelope.Add(V);
    Events := TJSONArray.Create;
    Root.AddPair('hits', Events);
    for H in Audio.Hits do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('time', TJSONNumber.Create(H.Time));
      Item.AddPair('strength', TJSONNumber.Create(H.Strength));
      Item.AddPair('lane', TJSONNumber.Create(H.Lane));
      Item.AddPair('flight', TJSONNumber.Create(H.Flight));
      Events.AddElement(Item);
    end;
    TFile.WriteAllText(EventsPath(Audio.Source,Audio.Key,Audio.Sensitivity),Root.ToJSON,TEncoding.UTF8);
    Index:=TJSONObject.Create;
    try
      Index.AddPair('sourceSHA256',Audio.Key);
      Index.AddPair('sourceStamp',AudioSourceStamp(Audio.Source));
      TFile.WriteAllText(IndexPath(Audio.Source,Audio.Sensitivity),Index.ToJSON,TEncoding.UTF8);
    finally Index.Free;
    end;
  finally Root.Free;
  end;
end;

function ReadRhythmAudioCache(const Source:string;Sensitivity:Integer;NeedPCM:Boolean):TRhythmAudio;
var
  Failure:string;
begin Result:=ReadRhythmAudioCache(Source,Sensitivity,NeedPCM,Failure);
end;

function ReadRhythmAudioCache(const Source:string;Sensitivity:Integer;NeedPCM:Boolean;out Failure:string):TRhythmAudio;
var
  Index,Root:TJSONObject;
  J:TJSONValue;
  Envelope,Hits:TJSONArray;
  I,Frames:Integer;
  Key,Path:string;
  SavedDuration:Double;
begin
  Result:=nil;
  Index:=nil;
  Root:=nil;
  Failure:='';
  try
    try
      J:=TJSONObject.ParseJSONValue(TFile.ReadAllText(IndexPath(Source,Sensitivity),TEncoding.UTF8));
      if not (J is TJSONObject) then begin J.Free;
        raise Exception.Create('音声キャッシュ索引JSONが不正です。');
      end;
      Index:=TJSONObject(J);
      if Index.GetValue<string>('sourceStamp','')<>AudioSourceStamp(Source) then raise Exception.Create('音楽ファイルの更新情報が解析時と一致しません。');
      Key:=Index.GetValue<string>('sourceSHA256','');
      if Length(Key)<>64 then raise Exception.Create('音声キャッシュ索引のキーが不正です。');
      for I:=1 to Length(Key) do if not CharInSet(Key[I],['0'..'9','a'..'f','A'..'F']) then raise Exception.Create('音声キャッシュ索引のキー文字が不正です。');
      J:=TJSONObject.ParseJSONValue(TFile.ReadAllText(EventsPath(Source,Key,Sensitivity),TEncoding.UTF8));
      if not (J is TJSONObject) then begin J.Free;
        raise Exception.Create('音声イベントJSONが不正です。');
      end;
      Root:=TJSONObject(J);
      if (Root.GetValue<Integer>('analysisVersion',0)<>2) or (Root.GetValue<string>('sourceSHA256','')<>Key) or
      (Root.GetValue<Integer>('sensitivity',0)<>Sensitivity) then raise Exception.Create('音声イベントの解析版・キー・感度が一致しません。');
      Envelope:=Root.GetValue<TJSONArray>('envelope');
      Hits:=Root.GetValue<TJSONArray>('hits');
      if (Envelope=nil) or (Hits=nil) then raise Exception.Create('音声イベントに波形または検出時刻がありません。');
      SavedDuration:=Root.GetValue<Double>('duration',0);
      if IsNan(SavedDuration) or IsInfinite(SavedDuration) or (SavedDuration<=0) or
      (SavedDuration>512*Int64(1024)*1024/4/RHYTHM_RATE) then raise Exception.Create('Cache duration invalid');
      Frames:=Round(SavedDuration*RHYTHM_RATE);
      if Abs(Frames/RHYTHM_RATE-SavedDuration)>0.0001 then raise Exception.Create('Cache sample count invalid');
      Result:=TRhythmAudio.Create;
      Result.Source:=ExpandFileName(Source);
      Result.Key:=Key;
      Result.SourceRevision:=AudioSourceStamp(Source);
      Result.Sensitivity:=Sensitivity;
      Result.CacheReused:=True;
      Result.Duration:=SavedDuration;
      if NeedPCM then begin
        Path:=AudioPCMCachePath(Source,Key);
        if (TFile.GetSize(Path)<4) or (TFile.GetSize(Path) mod 4<>0) or (TFile.GetSize(Path)>512*Int64(1024)*1024) then raise Exception.Create('PCM cache invalid');
        Result.PcmPath:=Path;
        Result.PCM:=TFile.ReadAllBytes(Path);
        Result.Duration:=Length(Result.PCM)/4/RHYTHM_RATE;
        if Abs(Result.Duration-SavedDuration)>0.0001 then raise Exception.Create('Cache duration mismatch');
        Frames:=Length(Result.PCM) div 4;
      end;
      if Envelope.Count<>((Frames+440) div 441) then raise Exception.Create('Cache waveform length mismatch');
      SetLength(Result.Envelope,Envelope.Count);
      for I:=0 to Envelope.Count-1 do begin
        Result.Envelope[I]:=Envelope.Items[I].GetValue<Single>;
        if IsNan(Result.Envelope[I]) or IsInfinite(Result.Envelope[I]) or (Result.Envelope[I]<0) or (Result.Envelope[I]>1) then raise Exception.Create('Cache waveform invalid');
      end;
      SetLength(Result.Hits,Hits.Count);
      for I:=0 to Hits.Count-1 do
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
    except on E:Exception do begin Failure:=E.ClassName+': '+E.Message;
        FreeAndNil(Result);
      end;
    end;
  finally Root.Free;
    Index.Free;
  end;
end;


end.
