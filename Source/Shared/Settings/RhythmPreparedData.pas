unit RhythmPreparedData;
// Prepared-plan I/O shared by animation styles. No decoding or analysis.
interface
uses System.JSON,RhythmAudio,RhythmPlanRef,RhythmStyles;
function ReadPreparedData(const Ref:TRhythmPlanRef;Style:TRhythmStyle;Direction:Integer):TJSONObject;
function PreparedAudio(Root:TJSONObject;const Ref:TRhythmPlanRef;const Source:string):TRhythmAudio;
procedure AddPreparedAudio(Root:TJSONObject;Audio:TRhythmAudio);
procedure WritePreparedData(Root:TJSONObject;var Ref:TRhythmPlanRef);
implementation
uses System.SysUtils,System.Math,System.IOUtils,System.Hash,Winapi.Windows,RhythmPaths;
function PathFor(const Key:string):string;
begin if not ValidDigest(Key) then raise Exception.Create('Invalid prepared key');Result:=TPath.Combine(PlanFolder,Key+'.json');end;
function ReadPreparedData(const Ref:TRhythmPlanRef;Style:TRhythmStyle;Direction:Integer):TJSONObject;
var Path:string;V:TJSONValue;
begin
  Result:=nil;
  if not Ref.Matches(Ref.SourceKey,Ref.Sensitivity,Direction,Style,Ref.Variant) or not ValidDigest(Ref.SourceKey) or
    not ValidDigest(Ref.Digest) then raise Exception.Create('動作計画が未準備か旧版です。設定画面で準備して適用してください。');
  Path:=PathFor(Ref.Key);
  if not FileExists(Path) then raise Exception.Create('保存済み動作計画がありません。設定画面で再準備してください: '+Path);
  if TFile.GetSize(Path)>32*1024*1024 then raise Exception.Create('Prepared plan too large');
  if not SameText(THashSHA2.GetHashStringFromFile(Path),Ref.Digest) then raise Exception.Create('動作計画の内容ハッシュが一致しません。再準備してください。');
  V:=TJSONObject.ParseJSONValue(TFile.ReadAllText(Path,TEncoding.UTF8));
  if not (V is TJSONObject) then begin V.Free;raise Exception.Create('Invalid prepared JSON');end;
  Result:=TJSONObject(V);
  try
    if (Result.GetValue<Integer>('schema',0)<>1) or (Result.GetValue<string>('style','')<>StyleId(Style)) or
      (Result.GetValue<Integer>('version',0)<>Ref.Version) or (Result.GetValue<string>('key','')<>Ref.Key) or
      (Result.GetValue<string>('source','')<>Ref.SourceKey) or (Result.GetValue<Integer>('sensitivity',0)<>Ref.Sensitivity) or
      (Result.GetValue<Integer>('direction',-1)<>Direction) then raise Exception.Create('Prepared identity mismatch');
  except Result.Free;Result:=nil;raise;end;
end;
function PreparedAudio(Root:TJSONObject;const Ref:TRhythmPlanRef;const Source:string):TRhythmAudio;
var V:TJSONValue;Info:TJSONObject;Count:Integer;
begin
  Result:=nil;V:=Root.GetValue('audio');
  if not (V is TJSONObject) then raise Exception.Create('復元用の音声情報がありません。再準備してください。');
  Info:=TJSONObject(V);if Info.GetValue<Integer>('schema',0)<>1 then raise Exception.Create('Invalid prepared audio schema');
  Result:=TRhythmAudio.Create;
  try
    Result.Source:=ExpandFileName(Source);Result.Key:=Ref.SourceKey;Result.Sensitivity:=Ref.Sensitivity;Result.CacheReused:=True;
    Result.Duration:=Info.GetValue<Double>('duration');Result.SoundEnd:=Info.GetValue<Double>('soundEnd');
    Count:=Info.GetValue<Integer>('events',-1);Result.SourceRevision:=Ref.SourceRevision;
    if IsNan(Result.Duration) or IsInfinite(Result.Duration) or IsNan(Result.SoundEnd) or IsInfinite(Result.SoundEnd) or
      (Result.Duration<=0) or (Result.Duration>512*Int64(1024)*1024/4/RHYTHM_RATE) or
      (Result.SoundEnd<0) or (Result.SoundEnd>Result.Duration) or (Count<0) or (Count>100000) then raise Exception.Create('Invalid prepared audio bounds');
    if not FileExists(Source) then raise Exception.Create('音楽ファイルがありません: '+Source);
    if not AudioSourceUnchanged(Result) then raise Exception.Create('音楽の更新情報が変わったか復元情報が不足しています。再準備してください。');
    SetLength(Result.Hits,Count);
  except Result.Free;Result:=nil;raise;end;
end;
procedure AddPreparedAudio(Root:TJSONObject;Audio:TRhythmAudio);
var Info:TJSONObject;
begin
  Info:=TJSONObject.Create;Root.AddPair('audio',Info);Info.AddPair('schema',TJSONNumber.Create(1));
  Info.AddPair('duration',TJSONNumber.Create(Audio.Duration));Info.AddPair('soundEnd',TJSONNumber.Create(Audio.SoundEnd));
  Info.AddPair('events',TJSONNumber.Create(Length(Audio.Hits)));
end;
procedure WritePreparedData(Root:TJSONObject;var Ref:TRhythmPlanRef);
var Path,Temp:string;Id:TGUID;
begin
  Path:=PathFor(Ref.Key);ForceDirectories(ExtractFileDir(Path));CreateGUID(Id);Temp:=Path+'.'+GUIDToString(Id)+'.tmp';
  try
    TFile.WriteAllText(Temp,Root.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(Temp),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    Ref.Digest:=THashSHA2.GetHashStringFromFile(Path);
  finally if FileExists(Temp) then TFile.Delete(Temp);end;
end;
end.
