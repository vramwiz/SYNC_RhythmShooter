unit RhythmAudioAnalysis;
{$POINTERMATH ON}
interface
uses System.SysUtils;
const RHYTHM_ANALYSIS_RATE=44100;
type
  TRhythmAccent=record
    Time,Strength:Double;
    HopIndex:Integer;
  end;
  TRhythmAnalysis=record
    Duration:Double;
    Envelope:TArray<Single>;
    Accents:TArray<TRhythmAccent>;
  end;
// Pure analysis of decoded 44.1 kHz stereo signed-16 PCM. No file access,
// timeline playback, enemy lanes, shot speeds, boss sections or global RNG.
function AnalyzeRhythmPCM(const PCM:TBytes;Sensitivity:Integer):TRhythmAnalysis;
implementation
uses System.Math,System.Generics.Collections;
function AnalyzeRhythmPCM(const PCM:TBytes;Sensitivity:Integer):TRhythmAnalysis;
const Hop = 441;
var
  Frame, Count, I, J, First, Last, LastPeak: Integer;
  Sum, L, R, Prior, Mean, Score, Threshold, Peak, GlobalPeak: Double;
  Flux: TArray<Double>;
  Found: TList<TRhythmAccent>;
  H: TRhythmAccent;
  Samples: PSmallInt;
begin
  Count := Length(PCM) div 4;
  Result.Duration := Count / RHYTHM_ANALYSIS_RATE;
  SetLength(Result.Envelope, (Count + Hop - 1) div Hop);
  SetLength(Flux, Length(Result.Envelope));
  Samples := PSmallInt(PCM);
  GlobalPeak := 0;
  for I := 0 to High(Result.Envelope) do
  begin
    Sum := 0; First := I * Hop; Last := Min(Count, First + Hop);
    for Frame := First to Last - 1 do
    begin
      L := Samples[Frame * 2] / 32768.0;
      R := Samples[Frame * 2 + 1] / 32768.0;
      Sum := Sum + (L * L + R * R) * 0.5;
    end;
    Result.Envelope[I] := Sqrt(Sum / Max(1, Last - First));
    GlobalPeak := Max(GlobalPeak, Result.Envelope[I]);
  end;
  Prior := 0;
  for I := 0 to High(Result.Envelope) do
  begin
    Flux[I] := Max(0.0, Result.Envelope[I] - Prior);
    Prior := Prior * 0.55 + Result.Envelope[I] * 0.45;
  end;
  Found := TList<TRhythmAccent>.Create;
  try
    LastPeak := -1000;
    for I := 2 to High(Result.Envelope) - 2 do
    begin
      Mean := 0; First := Max(0, I - 40); Last := Min(High(Flux), I + 40);
      for J := First to Last do Mean := Mean + Flux[J];
      Mean := Mean / (Last - First + 1);
      Threshold := Max(GlobalPeak * 0.012, Mean * (3.5 - Sensitivity * 0.025));
      Score := Flux[I];
      if (Score <= Threshold) or (Score < Flux[I-1]) or (Score <= Flux[I+1]) or
        (Result.Envelope[I] < GlobalPeak * 0.035) then Continue;
      // 180 ms of separation keeps fast arrangements readable. The larger
      // local onset replaces a weaker candidate rather than shifting its time.
      if (I - LastPeak < 18) and (Found.Count > 0) then
      begin
        if Score <= Flux[LastPeak] then Continue;
        Found.Delete(Found.Count - 1);
      end;
      H.Time := I * Hop / RHYTHM_ANALYSIS_RATE;
      Peak := EnsureRange(Score / Max(0.000001, GlobalPeak * 0.22), 0.15, 1.0);
      H.Strength := Peak;
      H.HopIndex := I;
      if H.Time >= 0.12 then Found.Add(H);
      LastPeak := I;
    end;
    Result.Accents := Found.ToArray;
  finally Found.Free; end;
end;
end.
