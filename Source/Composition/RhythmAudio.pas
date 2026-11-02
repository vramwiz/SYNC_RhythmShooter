unit RhythmAudio;
// 既存音声APIの互換窓口。データ・キャッシュ復元・準備時デコードを下位層へ委譲する。
{$POINTERMATH ON}

interface

uses System.Classes, System.SysUtils, RhythmAudioData;

const

  RHYTHM_RATE = RhythmAudioData.RHYTHM_RATE;

type
  TRhythmHit=RhythmAudioData.TRhythmHit;
  TRhythmAudio=RhythmAudioData.TRhythmAudio;
  TRhythmLoadThread = class(TThread)
  private
    FSource: string;
    FSensitivity: Integer;
    FForce:Boolean;
  public
    Audio: TRhythmAudio;
    Error: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const Source: string; Sensitivity: Integer;Force:Boolean=False);
    destructor Destroy; override;
    function TakeAudio: TRhythmAudio;
  end;

function AudioSourceUnchanged(Audio:TRhythmAudio):Boolean;
function LoadRhythmAudio(const Source: string; Sensitivity: Integer;
  const Cancel: TFunc<Boolean> = nil): TRhythmAudio;
  // Runtime only reads prepared data. Missing/stale caches never start analysis.
  // NeedPCM=False is for legacy Ball metadata restoration, never audio playback.
function LoadCachedRhythmAudio(const Source:string;Sensitivity:Integer;NeedPCM:Boolean=True):TRhythmAudio; overload;
function LoadCachedRhythmAudio(const Source:string;Sensitivity:Integer;NeedPCM:Boolean;out Failure:string):TRhythmAudio; overload;

implementation
uses RhythmAudioCache,RhythmAudioDecode;

function AudioSourceUnchanged(Audio:TRhythmAudio):Boolean;
begin Result:=RhythmAudioCache.AudioSourceUnchanged(Audio);
end;

function LoadRhythmAudio(const Source:string;Sensitivity:Integer;const Cancel:TFunc<Boolean>):TRhythmAudio;
begin Result:=DecodeRhythmAudio(Source,Sensitivity,Cancel);
end;

function LoadCachedRhythmAudio(const Source:string;Sensitivity:Integer;NeedPCM:Boolean):TRhythmAudio;
begin Result:=RhythmAudioCache.ReadRhythmAudioCache(Source,Sensitivity,NeedPCM);
end;

function LoadCachedRhythmAudio(const Source:string;Sensitivity:Integer;NeedPCM:Boolean;out Failure:string):TRhythmAudio;
begin Result:=RhythmAudioCache.ReadRhythmAudioCache(Source,Sensitivity,NeedPCM,Failure);
end;

constructor TRhythmLoadThread.Create(const Source: string; Sensitivity: Integer;Force:Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSource := Source;
  FSensitivity := Sensitivity;
  FForce:=Force;
end;

procedure TRhythmLoadThread.Execute;
begin
  try
    if not FForce then Audio:=LoadCachedRhythmAudio(FSource,FSensitivity);
    if Audio=nil then Audio := LoadRhythmAudio(FSource, FSensitivity,
    function: Boolean begin Result := Terminated; end);
  except on E: Exception do Error := E.ClassName + ': ' + E.Message;
  end;
end;

destructor TRhythmLoadThread.Destroy;
begin Audio.Free;
  inherited;
end;

function TRhythmLoadThread.TakeAudio: TRhythmAudio;
begin Result := Audio;
  Audio := nil;
end;

end.
