unit RhythmAudioDecode;
// 設定画面の準備用デコード。MP3は純Delphi、WAVは既存のFFmpegでPCM化する。
interface
uses System.SysUtils,RhythmAudioData;
function DecodeRhythmAudio(const Source:string;Sensitivity:Integer;const Cancel:TFunc<Boolean> = nil):TRhythmAudio;
implementation
uses Winapi.Windows,System.Classes,System.IOUtils,System.Hash,System.Math,RhythmPaths,MimiChildProcess,RhythmAudioCache,MP3Decoder;

function Cancelled(const Cancel:TFunc<Boolean>):Boolean;
begin Result:=Assigned(Cancel) and Cancel();
end;

function DecodeRhythmAudio(const Source: string; Sensitivity: Integer;
  const Cancel: TFunc<Boolean>): TRhythmAudio;
var
  Input: TFileStream;
  Buffer: TBytes;
  Hash: THashSHA2;
  N: Integer;
  Ext, Temp, Log, OutLog, Exe, FinalPath: string;
  Id: TGUID;
  Audio:TDecodedAudio;
begin
  Result:=nil;Temp:='';Log:='';OutLog:='';
  Ext := LowerCase(ExtractFileExt(Source));
  if (Ext <> '.wav') and (Ext <> '.mp3') then raise Exception.Create('WAV / MP3 を指定してください。');
  Input := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite);
  try
    Result := TRhythmAudio.Create;
    try
      Hash := THashSHA2.Create;
      SetLength(Buffer, 1024 * 1024);
      repeat
        if Cancelled(Cancel) then Abort;
        N := Input.Read(Buffer[0], Length(Buffer));
        if N > 0 then Hash.Update(Buffer, N);
      until N = 0;
      Buffer:=nil;
      Result.Source := ExpandFileName(Source);
      Result.SourceRevision:=AudioSourceStamp(Result.Source);
      Result.Key := Hash.HashAsString;
      Result.Sensitivity := EnsureRange(Sensitivity, 1, 100);
      FinalPath := AudioPCMCachePath(Result.Source,Result.Key);
      Result.CacheReused := TFile.Exists(FinalPath);
      if not Result.CacheReused then
      begin
        CreateGUID(Id);
        Temp := TPath.Combine(CacheFolder, GUIDToString(Id) + '.pcm');
        if Ext='.mp3' then
        begin
          Audio:=DecodeMP3(Result.Source,Cancel);
          Buffer:=ToStereo44100(Audio,Cancel);
          Audio.PCM:=nil;
          if Cancelled(Cancel) then Abort;
          TFile.WriteAllBytes(Temp,Buffer);
          Buffer:=nil;
        end
        else
        begin
          Log := ChangeFileExt(Temp, '.log');
          OutLog := ChangeFileExt(Temp, '.stdout');
          Exe := TPath.Combine(ModuleFolder, 'ThirdParty\FFmpeg\bin\ffmpeg.exe');
          RunAudioTool(Exe, ['-hide_banner','-loglevel','error','-nostdin','-n',
            '-protocol_whitelist','file,pipe','-f','wav','-i',Result.Source,
            '-map','0:a:0','-vn','-ac','2','-ar','44100','-f','s16le',Temp],
            OutLog, Log, function: Boolean begin Result := Cancelled(Cancel); end, 180000);
        end;
        if Cancelled(Cancel) then Abort;
        if not TFile.Exists(Temp) or (TFile.GetSize(Temp) = 0) then
          raise Exception.Create('音声サンプルを取得できませんでした。');
        if not MoveFileEx(PChar(Temp), PChar(FinalPath), MOVEFILE_WRITE_THROUGH) then
        begin
          if not TFile.Exists(FinalPath) then RaiseLastOSError;
          TFile.Delete(Temp);
        end;
        Temp:='';
      end;
      if Cancelled(Cancel) then Abort;
      if (TFile.GetSize(FinalPath) < 4) or (TFile.GetSize(FinalPath) mod 4 <> 0) or
        (TFile.GetSize(FinalPath) > MP3_MAX_PCM_BYTES) then
        raise Exception.Create('PCMキャッシュが不正、または約50分のメモリ上限を超えています。');
      Result.PcmPath := FinalPath;
      Result.PCM := TFile.ReadAllBytes(FinalPath);
      Result.Detect;
      if Cancelled(Cancel) then Abort;
      SaveRhythmAudioCache(Result);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    Input.Free;
    if (Temp<>'') and TFile.Exists(Temp) then TFile.Delete(Temp);
    if (Log<>'') and TFile.Exists(Log) then TFile.Delete(Log);
    if (OutLog<>'') and TFile.Exists(OutLog) then TFile.Delete(OutLog);
  end;
end;


end.
