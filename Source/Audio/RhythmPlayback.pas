unit RhythmPlayback;

interface

uses Winapi.Windows, Winapi.MMSystem, System.SysUtils, RhythmAudio;

type
  TRhythmPlayback = class
  private
    FAudio: TRhythmAudio;
    FHandle: HWAVEOUT;
    FHeader: TWaveHdr;
    FPrepared, FPlaying, FPaused: Boolean;
    FBaseFrame, FPositionFrame: Int64;
    FLastRaw, FKind: Cardinal;
    FUnwrapped: UInt64;
    procedure CloseOutput;
    procedure StartOutput(Paused: Boolean);
  public
    destructor Destroy; override;
    procedure SetAudio(Audio: TRhythmAudio);
    procedure Play;
    procedure Pause;
    procedure Stop;
    procedure Seek(Seconds: Double);
    function Position: Double;
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
  if FHandle = 0 then Exit;
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
  FHandle := 0; FPlaying := False; FPaused := False;
end;

procedure TRhythmPlayback.SetAudio(Audio: TRhythmAudio);
begin CloseOutput; FAudio := Audio; FPositionFrame := 0; end;

procedure TRhythmPlayback.StartOutput(Paused: Boolean);
var Format: TWaveFormatEx; Total: Int64;
begin
  if FAudio = nil then Exit;
  Total := Length(FAudio.PCM) div 4;
  if FPositionFrame >= Total then FPositionFrame := 0;
  FillChar(Format, SizeOf(Format), 0);
  Format.wFormatTag := WAVE_FORMAT_PCM; Format.nChannels := 2;
  Format.nSamplesPerSec := RHYTHM_RATE; Format.wBitsPerSample := 16;
  Format.nBlockAlign := 4; Format.nAvgBytesPerSec := RHYTHM_RATE * 4;
  CheckMM(waveOutOpen(@FHandle, WAVE_MAPPER, @Format, 0, 0, CALLBACK_NULL));
  try
    FBaseFrame := FPositionFrame; FLastRaw := 0; FUnwrapped := 0; FKind := 0;
    FillChar(FHeader, SizeOf(FHeader), 0);
    FHeader.lpData := PAnsiChar(@FAudio.PCM[FBaseFrame * 4]);
    FHeader.dwBufferLength := (Total - FBaseFrame) * 4;
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
    FPositionFrame := Min(Length(FAudio.PCM) div 4, FBaseFrame + Int64(Frames));
    if (FHeader.dwFlags and WHDR_DONE) <> 0 then
    begin
      FPositionFrame := Length(FAudio.PCM) div 4;
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
  else FPositionFrame := Round(EnsureRange(Seconds, 0.0, FAudio.Duration) * RHYTHM_RATE);
  if WasPlaying and (FAudio<>nil) and (FPositionFrame<Length(FAudio.PCM) div 4) then StartOutput(WasPaused);
end;

destructor TRhythmPlayback.Destroy;
begin CloseOutput; inherited; end;

end.
