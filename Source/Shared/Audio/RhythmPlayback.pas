unit RhythmPlayback;

// 専用プレビューのPCM再生と絶対時刻を管理し、余韻用の無音だけを私有出力へ追加する。

interface

uses Winapi.Windows, Winapi.MMSystem, System.SysUtils, RhythmAudio;

type
  TRhythmPlayback = class
  private
    FAudio: TRhythmAudio;
    FHandle: HWAVEOUT;
    FHeader: TWaveHdr;
    FPrepared, FPlaying, FPaused: Boolean;
    FBaseFrame, FPositionFrame, FTotalFrames: Int64;
    FOutput:TBytes;
    FLastRaw, FKind: Cardinal;
    FUnwrapped: UInt64;
    function GetDuration:Double;
    procedure CloseOutput;
    procedure StartOutput(Paused: Boolean);
  public
    destructor Destroy; override;
    // Audioは借用。再生を停止して結び直し、ExtraSecondsは元PCMを変えず出力側へ追加する。
    procedure SetAudio(Audio: TRhythmAudio;ExtraSeconds:Double=0);
    // 現在位置から開始または再開する。必要時に音声デバイスを開く。
    procedure Play;
    // 音声デバイス時計の現在位置を保持して一時停止する。
    procedure Pause;
    // 出力を解放して先頭へ戻す。借用音声と再生範囲は保持する。
    procedure Stop;
    // 余韻を含む再生範囲内へ移動し、再生/一時停止状態を保つ。
    procedure Seek(Seconds: Double);
    // 音声デバイス時計を秒へ変換し、停止中は保持した絶対位置を返す。
    function Position: Double;
    property Duration:Double read GetDuration;
    property Playing: Boolean read FPlaying;
    property Paused: Boolean read FPaused;
  end;

implementation

uses System.Math;

procedure CheckMM(Code: MMRESULT);
var Text: array[0..255] of Char;
begin
  if Code = MMSYSERR_NOERROR then Exit;
  waveOutGetErrorText(Code, Text, Length(Text));
  raise Exception.CreateFmt('音声出力 (%d): %s', [Code, string(Text)]);
end;

procedure TRhythmPlayback.CloseOutput;
var Code: MMRESULT; Started: UInt64;
begin
  if FHandle = 0 then begin SetLength(FOutput,0);FPlaying:=False;FPaused:=False;Exit;end;
  CheckMM(waveOutReset(FHandle));
  if FPrepared then
  begin
    Started := GetTickCount64;
    repeat
      Code := waveOutUnprepareHeader(FHandle, @FHeader, SizeOf(FHeader));
      if Code <> WAVERR_STILLPLAYING then Break;
      Sleep(1);
    until GetTickCount64 - Started > 1000;
    CheckMM(Code);
    FPrepared := False;
  end;
  CheckMM(waveOutClose(FHandle));
  FHandle := 0; FPlaying := False; FPaused := False;SetLength(FOutput,0);
end;

procedure TRhythmPlayback.SetAudio(Audio: TRhythmAudio;ExtraSeconds:Double);
begin
  if IsNan(ExtraSeconds) or IsInfinite(ExtraSeconds) or (ExtraSeconds<0) or (ExtraSeconds>4) then raise EArgumentException.Create('Invalid preview afterglow.');
  CloseOutput;FAudio:=Audio;FPositionFrame:=0;FTotalFrames:=0;
  if FAudio<>nil then FTotalFrames:=Length(FAudio.PCM) div 4+Round(ExtraSeconds*RHYTHM_RATE);
end;
function TRhythmPlayback.GetDuration:Double;
begin Result:=FTotalFrames/RHYTHM_RATE;end;

procedure TRhythmPlayback.StartOutput(Paused: Boolean);
var Format: TWaveFormatEx;Total,RealFrames,StartByte,RealBytes,OutputBytes:Int64;
begin
  if FAudio = nil then Exit;
  Total:=FTotalFrames;RealFrames:=Length(FAudio.PCM) div 4;if Total<=0 then Exit;
  if FPositionFrame >= Total then FPositionFrame := 0;
  OutputBytes:=(Total-FPositionFrame)*4;if OutputBytes>High(DWORD) then raise Exception.Create('プレビュー音声が出力バッファの上限を超えました。');
  FillChar(Format, SizeOf(Format), 0);
  Format.wFormatTag := WAVE_FORMAT_PCM; Format.nChannels := 2;
  Format.nSamplesPerSec := RHYTHM_RATE; Format.wBitsPerSample := 16;
  Format.nBlockAlign := 4; Format.nAvgBytesPerSec := RHYTHM_RATE * 4;
  CheckMM(waveOutOpen(@FHandle, WAVE_MAPPER, @Format, 0, 0, CALLBACK_NULL));
  try
    FBaseFrame := FPositionFrame; FLastRaw := 0; FUnwrapped := 0; FKind := 0;
    FillChar(FHeader, SizeOf(FHeader), 0);
    if Total>RealFrames then begin
      // Add private silence to the output only. The decoded PCM, source duration
      // and shared cache remain untouched. The device clock also covers the tail.
      StartByte:=FBaseFrame*4;RealBytes:=Max(Int64(0),Length(FAudio.PCM)-StartByte);
      FOutput:=Copy(FAudio.PCM,Min(Int64(Length(FAudio.PCM)),StartByte),RealBytes);
      SetLength(FOutput,OutputBytes);FHeader.lpData:=PAnsiChar(@FOutput[0]);
    end else FHeader.lpData:=PAnsiChar(@FAudio.PCM[FBaseFrame*4]);
    FHeader.dwBufferLength:=DWORD(OutputBytes);
    CheckMM(waveOutPrepareHeader(FHandle, @FHeader, SizeOf(FHeader)));
    FPrepared := True;
    if Paused then CheckMM(waveOutPause(FHandle));
    CheckMM(waveOutWrite(FHandle, @FHeader, SizeOf(FHeader)));
    FPlaying := True; FPaused := Paused;
  except CloseOutput; raise; end;
end;

function TRhythmPlayback.Position: Double;
var Time: TMMTime; Raw: Cardinal; Frames: UInt64;
begin
  if FHandle <> 0 then
  begin
    FillChar(Time, SizeOf(Time), 0); Time.wType := TIME_SAMPLES;
    CheckMM(waveOutGetPosition(FHandle, @Time, SizeOf(Time)));
    case Time.wType of
      TIME_SAMPLES: Raw := Time.sample;
      TIME_BYTES: Raw := Time.cb;
      TIME_MS: Raw := Time.ms;
    else raise Exception.Create('音声時計の形式に対応していません。'); end;
    if (FKind <> 0) and (FKind <> Time.wType) then
      raise Exception.Create('音声時計の単位が途中で変更されました。');
    FKind := Time.wType;
    Inc(FUnwrapped, (UInt64(Raw) + UInt64($100000000) - FLastRaw) and UInt64($FFFFFFFF));
    FLastRaw := Raw;
    case FKind of
      TIME_SAMPLES: Frames := FUnwrapped;
      TIME_BYTES: Frames := FUnwrapped div 4;
    else Frames := FUnwrapped * RHYTHM_RATE div 1000; end;
    FPositionFrame := Min(FTotalFrames, FBaseFrame + Int64(Frames));
    if (FHeader.dwFlags and WHDR_DONE) <> 0 then
    begin
      FPositionFrame := FTotalFrames;
      CloseOutput;
    end;
  end;
  Result := FPositionFrame / RHYTHM_RATE;
end;

procedure TRhythmPlayback.Play;
begin
  if FHandle = 0 then StartOutput(False)
  else if FPaused then begin CheckMM(waveOutRestart(FHandle)); FPaused := False; end;
end;

procedure TRhythmPlayback.Pause;
begin
  if (FHandle <> 0) and not FPaused then
  begin CheckMM(waveOutPause(FHandle)); Position; FPaused := True; end;
end;

procedure TRhythmPlayback.Stop;
begin CloseOutput; FPositionFrame := 0; end;

procedure TRhythmPlayback.Seek(Seconds: Double);
var WasPlaying, WasPaused: Boolean;
begin
  WasPlaying := FPlaying; WasPaused := FPaused;
  CloseOutput;
  if FAudio = nil then FPositionFrame := 0
  else FPositionFrame := Round(EnsureRange(Seconds, 0.0, Duration) * RHYTHM_RATE);
  if WasPlaying and (FAudio<>nil) and (FPositionFrame<FTotalFrames) then StartOutput(WasPaused);
end;

destructor TRhythmPlayback.Destroy;
begin CloseOutput; inherited; end;

end.
