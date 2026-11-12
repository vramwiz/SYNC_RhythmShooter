unit RhythmAudioData;
// PCM・包絡線・アクセントとボス区間のデータモデル。ファイルI/Oは扱わない。
interface
uses System.SysUtils,RhythmSections;
const
  RHYTHM_RATE=44100;
type
  TRhythmHit = record
    Time, Strength, Lane, Flight: Double;
  end;
  TRhythmAudio = class
  private
    FBossCues: TRhythmBossCues;
    FBossCuesReady: Boolean;
    FEnvelopePeak: Double;
    FTimelineRevision: Cardinal;
    FBossFrequency:Integer;
    FOriginalHits:TArray<TRhythmHit>;
    FHasSelection:Boolean;
  public
    Source, Key, PcmPath, SourceRevision: string;
    // 44.1kHz・signed16 little-endian・stereo。1フレーム4byte。
    // 44.1kHz・signed16 little-endian・stereo。1フレーム4byte。
    PCM: TBytes;
    Envelope: TArray<Single>;
    Hits: TArray<TRhythmHit>;
    HasHitDetails:Boolean; // Falseは旧保存の件数だけの配列。音反応へ0埋めの値を渡さない。
    Duration,SoundEnd: Double;
    Sensitivity: Integer;
    CacheReused: Boolean;
    constructor Create;
    procedure SetBossFrequency(Value:Integer);
    procedure SetSelectedHits(const Value:TArray<TRhythmHit>);
    procedure ResetSelectedHits;
    property BossFrequency:Integer read FBossFrequency;
    property TimelineRevision: Cardinal read FTimelineRevision;
    procedure Detect;
    procedure UpdateSoundBounds;
    function NearestHit(Time: Double): Integer;
    function BossCue(Index: Integer): TRhythmBossCue;
    function BossCount: Integer;
    function LevelAt(Time: Double): Double;
  end;

implementation
uses System.Math,RhythmMotion,RhythmAudioAnalysis;

constructor TRhythmAudio.Create;
begin inherited Create;
  FBossFrequency:=100;
  HasHitDetails:=True;
end;

procedure TRhythmAudio.SetBossFrequency(Value:Integer);
begin Value:=EnsureRange(Value,0,100);
  if Value=FBossFrequency then Exit;
  FBossFrequency:=Value;
  FBossCuesReady:=False;
  FBossCues:=nil;
  Inc(FTimelineRevision);
end;

procedure TRhythmAudio.SetSelectedHits(const Value:TArray<TRhythmHit>);
begin
  if not FHasSelection then FOriginalHits:=Hits;
  FHasSelection:=True;
  Hits:=Value;
  FBossCuesReady:=False;
  Inc(FTimelineRevision);
end;

procedure TRhythmAudio.ResetSelectedHits;
begin
  if not FHasSelection then Exit;
  Hits:=FOriginalHits;
  FOriginalHits:=nil;
  FHasSelection:=False;
  FBossCuesReady:=False;
  Inc(FTimelineRevision);
end;

procedure TRhythmAudio.UpdateSoundBounds;
var
  Peak:Double;
  I:Integer;
begin
  FBossCuesReady:=False;
  Inc(FTimelineRevision);
  SoundEnd:=0;
  Peak:=0;
  for I:=0 to High(Envelope) do Peak:=Max(Peak,Envelope[I]);
  FEnvelopePeak:=Peak;
  for I:=High(Envelope) downto 0 do
  if Envelope[I]>Max(0.0001,Peak*0.015) then begin SoundEnd:=Min(Duration,(I+1)*0.01);
    Break;
  end;
end;

function TRhythmAudio.BossCue(Index:Integer):TRhythmBossCue;
var
  Times:TArray<Double>;
  I:Integer;
begin
  if not FBossCuesReady then
  begin
    SetLength(Times,Length(Hits));
    for I:=0 to High(Hits) do Times[I]:=Hits[I].Time;
    FBossCues:=BuildBossCues(Envelope,Duration,SoundEnd,Times,FBossFrequency);
    FBossCuesReady:=True;
  end;
  Result:=Default(TRhythmBossCue);
  Result.KillTime:=-1;
  if (Index>=0) and (Index<Length(FBossCues)) then Result:=FBossCues[Index];
end;

function TRhythmAudio.BossCount:Integer;
begin if not FBossCuesReady then BossCue(-1);
  Result:=Length(FBossCues);
end;

function TRhythmAudio.LevelAt(Time:Double):Double;
var
  I,First,Last:Integer;
  Sum:Double;
begin
  if (Length(Envelope)=0) or (FEnvelopePeak<=0) then Exit(0);
  First:=EnsureRange(Round(Time*100)-20,0,High(Envelope));
  Last:=EnsureRange(Round(Time*100)+20,First,High(Envelope));
  Sum:=0;
  for I:=First to Last do Sum:=Sum+Envelope[I];
  Result:=EnsureRange(Sum/((Last-First+1)*FEnvelopePeak),0.0,1.0);
end;

procedure TRhythmAudio.Detect;
var
  Analysis:TRhythmAnalysis;
  I,J:Integer;
  Accent:TRhythmAccent;
  H:TRhythmHit;
begin
  Analysis:=AnalyzeRhythmPCM(PCM,Sensitivity);
  ResetSelectedHits;
  Duration:=Analysis.Duration;
  Envelope:=Analysis.Envelope;
  SetLength(Hits,Length(Analysis.Accents));
  for I:=0 to High(Analysis.Accents) do begin
    Accent:=Analysis.Accents[I];
    H.Time:=Accent.Time;
    H.Strength:=Accent.Strength;
    // Legacy shooting metadata is kept here for existing callers and v1 caches.
    // Other animations can consume RhythmAudioAnalysis without this adapter.
    J:=(Accent.HopIndex*73+(Accent.HopIndex mod 17)*131) mod 997;
    H.Lane:=0.14+J/996.0*0.72;
    H.Flight:=ShotFlightTime(H.Time,H.Lane,H.Strength);
    Hits[I]:=H;
  end;
  UpdateSoundBounds;
end;

function TRhythmAudio.NearestHit(Time: Double): Integer;
var
  A, B, M: Integer;
begin
  A := 0;
  B := Length(Hits);
  while A < B do
  begin
    M := (A + B) div 2;
    if Hits[M].Time < Time then A := M + 1 else B := M;
  end;
  Result := Min(A, High(Hits));
end;


end.
