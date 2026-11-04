unit RhythmOrbitAudio;
// 細粒度の音候補。音ゲーは密な候補、他の演出は既存の180ms間隔を保つ候補を使う。
{$POINTERMATH ON}
interface
uses System.SysUtils,RhythmAudio;
type
  TOrbitAudioStats=record
    Legacy,Peaks,Qualified,SelectedExtra,NoiseRejected,Merged,Capped,RollTicks:Integer;
  end;
  TOrbitCandidate=record
    Hit:TRhythmHit;
    Quality,Score:Double;
  end;
  TOrbitCandidatePool=class
  private
    FLegacy:TArray<TRhythmHit>;
    FExtras:TArray<TOrbitCandidate>;
    FStats:TOrbitAudioStats;
  public
    class function Analyze(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TOrbitCandidatePool;static;
    // Value<0は追加候補の品質閾値。固定候補集合なので左ほど採用数が単調に増える。
    function Select(Audio:TRhythmAudio;Value:Integer;out Stats:TOrbitAudioStats):TRhythmAudio;
    function SelectSpaced(Audio:TRhythmAudio;Value:Integer;const Cancel:TFunc<Boolean>):TArray<TRhythmHit>;
  end;
function PrepareOrbitAudio(Audio:TRhythmAudio;Value:Integer;out Stats:TOrbitAudioStats;
  const Cancel:TFunc<Boolean> = nil;IncludeRollTicks:Boolean=True):TRhythmAudio;
function SelectAnimationHits(Audio:TRhythmAudio;Value:Integer;const Cancel:TFunc<Boolean>):TArray<TRhythmHit>;
function RollPair(First,Second:Double):Boolean;
// 44.1 kHzのステレオPCM約40msから持続的な周期音を判定する。
function SustainedBlock(Samples:PSmallInt):Boolean;
const
  RHYTHM_ROLL_SENSITIVITY=-35;
  RHYTHM_SUSTAIN_BLOCK_SAMPLES=1764;
implementation
uses System.Math,System.Generics.Collections,System.Generics.Defaults,RhythmMotion,RhythmStyles;

function RollPair(First,Second:Double):Boolean;
begin
  Result:=(Second>First) and (Second-First<=0.17);
end;

function SustainedBlock(Samples:PSmallInt):Boolean;
const Stride=16; Points=110;
var Signal:array[0..Points-1] of Double;
  Power:array[0..1] of Double;
  I,J,Lag,Channel:Integer;
  X,A,B,Mean,Cross,First,Second:Double;
  Reversed:Boolean;
begin
  Power[0]:=0;Power[1]:=0;
  for I:=0 to Points-1 do for J:=0 to 1 do begin
    X:=Samples[I*Stride*2+J];Power[J]:=Power[J]+X*X;
  end;
  Channel:=Ord(Power[1]>Power[0]);
  if Power[Channel]<Points*320.0*320.0 then Exit(False);
  Mean:=0;
  for I:=0 to Points-1 do begin
    Signal[I]:=Samples[I*Stride*2+Channel];Mean:=Mean+Signal[I];
  end;
  Mean:=Mean/Points;First:=0;Second:=0;
  for I:=0 to Points-1 do begin
    Signal[I]:=Signal[I]-Mean;
    X:=Signal[I]*Signal[I];
    if I<Points div 2 then First:=First+X else Second:=Second+X;
  end;
  // 無音、直流、短い打音の減衰を先に落とし、周期が続く波形だけを見る。
  if (First+Second<Points*320.0*320.0) or (Min(First,Second)<Max(First,Second)*0.32) then Exit(False);
  Reversed:=False;
  for Lag:=3 to 42 do begin
    Cross:=0;First:=0;Second:=0;
    for I:=Lag to Points-1 do begin
      A:=Signal[I];B:=Signal[I-Lag];
      Cross:=Cross+A*B;First:=First+A*A;Second:=Second+B*B;
    end;
    // 短い遅延で似ているだけの低域雑音を避け、位相反転の後の一致を使う。
    if Cross<=0 then Reversed:=True
    else if Reversed and (Cross*Cross>=0.78*First*Second) then Exit(True);
  end;
  Result:=False;
end;

function AddRollTicks(Audio,Snapshot:TRhythmAudio;const Cancel:TFunc<Boolean>):Integer;
const BlockSamples=RHYTHM_SUSTAIN_BLOCK_SAMPLES; Step=0.12; Guard=0.047;
var List:TList<TRhythmHit>;Samples:PSmallInt;Blocks,I,Run,Near,J:Integer;
  Time,Finish:Double;Blocked,Tonal:Boolean;Hit:TRhythmHit;
begin
  Result:=0;
  // 有音端の直後も確認し、曲頭の持続音に続く無音を区間の境界として扱う。
  Blocks:=Min(Length(Audio.PCM) div (BlockSamples*4),Ceil(Audio.SoundEnd/0.04)+1);
  if Blocks<9 then Exit;
  Samples:=PSmallInt(Audio.PCM);
  List:=TList<TRhythmHit>.Create;
  try
    List.AddRange(Snapshot.Hits);Run:=-1;
    for I:=0 to Blocks do begin
      if (I mod 64=0) and Assigned(Cancel) and Cancel() then Abort;
      Tonal:=(I<Blocks) and SustainedBlock(Samples+I*BlockSamples*2);
      if Tonal then begin
        if Run<0 then Run:=I;
        Continue;
      end;
      if (Run>=0) and (I-Run>=9) and ((Run>0) or (I<Blocks)) then begin
        // 持続区間の内側だけで演出を刻む。既に採用したピークは元の位置を使う。
        Time:=Run*0.04+0.08;Finish:=Min(I*0.04-0.04,Audio.SoundEnd);
        while (Time<=Finish) and (List.Count<100000) do begin
          Near:=Snapshot.NearestHit(Time);Blocked:=False;
          for J:=Max(0,Near-1) to Near do
            if Abs(Snapshot.Hits[J].Time-Time)<Guard then Blocked:=True;
          if not Blocked then begin
            Hit:=Default(TRhythmHit);Hit.Time:=Time;Hit.Strength:=0.67;
            List.Add(Hit);Inc(Result);
          end;
          Time:=Time+Step;
        end;
      end;
      Run:=-1;
    end;
    if Result>0 then begin
      Snapshot.Hits:=List.ToArray;
      TArray.Sort<TRhythmHit>(Snapshot.Hits,TComparer<TRhythmHit>.Construct(
        function(const A,B:TRhythmHit):Integer
        begin Result:=CompareValue(A.Time,B.Time,0.0);end));
    end;
  finally
    List.Free;
  end;
end;
type
  TBandValues=array[0..2] of Double;
  TOrbitFrame=record
    Band:TBandValues;
    Envelope,Score:Double;
  end;
function Snapshot(Audio:TRhythmAudio):TRhythmAudio;
begin
  Result:=TRhythmAudio.Create;Result.Source:=Audio.Source;Result.Key:=Audio.Key;Result.SourceRevision:=Audio.SourceRevision;
  Result.Sensitivity:=Audio.Sensitivity;Result.Duration:=Audio.Duration;Result.SoundEnd:=Audio.SoundEnd;Result.CacheReused:=True;
end;
class function TOrbitCandidatePool.Analyze(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TOrbitCandidatePool;
const Hop=220;Gap=0.032;LegacyGuard=0.025;
var
  Frames:TArray<TOrbitFrame>;Prefix:array[0..2] of TArray<Double>;ScorePrefix:TArray<Double>;
  Samples:PSmallInt;Count,N,I,J,K,F,First,Last,Near,Capacity:Integer;
  A250,A2500,X,Low,Mid,High,Total,Global,Mean,Ratio,MaxContrast,Second,MidHigh,Contrast,Q,Strength:Double;
  LP250,LP2500:array[0..1] of Double;Sum,Peak,Prior:TBandValues;
  List:TList<TOrbitCandidate>;C:TOrbitCandidate;Extra:TArray<TOrbitCandidate>;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;end;
begin
  // PCMは借用し、サンプルや元Hitsには書き込まない。
  if (Audio=nil) or (Length(Audio.PCM)<4) or (Length(Audio.PCM) mod 4<>0) then raise Exception.Create('追加の音検出には音声PCMが必要です。音源から再準備してください。');
  Result:=TOrbitCandidatePool.Create;List:=nil;
  try
    try
    Result.FLegacy:=Copy(Audio.Hits);Result.FStats.Legacy:=Length(Audio.Hits);
    Count:=Length(Audio.PCM) div 4;N:=(Count+Hop-1) div Hop;SetLength(Frames,N);Samples:=PSmallInt(Audio.PCM);
    FillChar(LP250,SizeOf(LP250),0);FillChar(LP2500,SizeOf(LP2500),0);FillChar(Peak,SizeOf(Peak),0);
    A250:=1-Exp(-2*Pi*250/RHYTHM_RATE);A2500:=1-Exp(-2*Pi*2500/RHYTHM_RATE);Global:=0;
    for I:=0 to N-1 do begin
      if I mod 128=0 then Check;FillChar(Sum,SizeOf(Sum),0);Total:=0;First:=I*Hop;Last:=Min(Count,First+Hop);
      for F:=First to Last-1 do for J:=0 to 1 do begin
        X:=Samples[F*2+J]/32768.0;LP250[J]:=LP250[J]+A250*(X-LP250[J]);LP2500[J]:=LP2500[J]+A2500*(X-LP2500[J]);
        Low:=LP250[J];Mid:=LP2500[J]-Low;High:=X-LP2500[J];
        Sum[0]:=Sum[0]+Low*Low;Sum[1]:=Sum[1]+Mid*Mid;Sum[2]:=Sum[2]+High*High;Total:=Total+X*X;
      end;
      Frames[I].Envelope:=Sqrt(Total/Max(1,2*(Last-First)));Global:=Max(Global,Frames[I].Envelope);
      for K:=0 to 2 do begin Frames[I].Band[K]:=Sqrt(Sum[K]/Max(1,2*(Last-First)));Peak[K]:=Max(Peak[K],Frames[I].Band[K]);end;
    end;
    for K:=0 to 2 do SetLength(Prefix[K],N+1);SetLength(ScorePrefix,N+1);FillChar(Prior,SizeOf(Prior),0);
    for I:=0 to N-1 do begin
      Frames[I].Score:=0;
      for K:=0 to 2 do begin
        Q:=0.20;if K=1 then Q:=0.35;if K=2 then Q:=0.45;
        Frames[I].Score:=Frames[I].Score+Q*Max(0.0,Frames[I].Band[K]-Prior[K])/Max(0.0006,Peak[K]*0.20);
        Prior[K]:=Prior[K]*0.65+Frames[I].Band[K]*0.35;Prefix[K][I+1]:=Prefix[K][I]+Frames[I].Band[K];
      end;
      ScorePrefix[I+1]:=ScorePrefix[I]+Frames[I].Score;
    end;
    List:=TList<TOrbitCandidate>.Create;Near:=0;
    for I:=0 to N-1 do begin
      if I mod 1024=0 then Check;
      if (I>0) and (Frames[I].Score<Frames[I-1].Score) then Continue;
      if (I<N-1) and (Frames[I].Score<=Frames[I+1].Score) then Continue;Inc(Result.FStats.Peaks);
      C:=Default(TOrbitCandidate);C.Hit.Time:=I*Hop/RHYTHM_RATE;
      if C.Hit.Time>Audio.SoundEnd then Continue;
      while (Near<Length(Audio.Hits)) and (Audio.Hits[Near].Time<C.Hit.Time-LegacyGuard) do Inc(Near);
      if (Near<Length(Audio.Hits)) and (Abs(Audio.Hits[Near].Time-C.Hit.Time)<=LegacyGuard) then begin Inc(Result.FStats.Merged);Continue;end;
      First:=Max(0,I-40);Last:=Min(N,I+41);Mean:=(ScorePrefix[Last]-ScorePrefix[First])/Max(1,Last-First);
      Ratio:=Frames[I].Score/Max(0.005,Mean);MaxContrast:=0;Second:=0;MidHigh:=0;
      for K:=0 to 2 do begin
        First:=Max(0,I-10);Q:=(Prefix[K][I]-Prefix[K][First])/Max(1,I-First);
        Contrast:=(Frames[I].Band[K]-Q)/Max(Q,Peak[K]*0.006+0.00005);
        if K>0 then MidHigh:=Max(MidHigh,Contrast);
        if Contrast>MaxContrast then begin Second:=MaxContrast;MaxContrast:=Contrast;end else Second:=Max(Second,Contrast);
      end;
      if (Frames[I].Envelope<Max(0.0006,Global*0.008)) or (Frames[I].Score<0.02) or (Ratio<1.25) or
      not (((MidHigh>=0.45) and (Second>=0.20)) or (MidHigh>=0.85)) then begin Inc(Result.FStats.NoiseRejected);Continue;end;
      Q:=0.45*EnsureRange(Ratio/5,0.0,1.0)+0.30*EnsureRange(MaxContrast/2,0.0,1.0)+0.25*EnsureRange(Second/0.7,0.0,1.0);
      Strength:=EnsureRange(0.12+0.50*EnsureRange(Ratio/5,0.0,1.0)+0.38*EnsureRange(MaxContrast/2,0.0,1.0),0.06,1.0);
      C.Hit.Strength:=Strength;C.Hit.Lane:=0.5;C.Quality:=Q*100;C.Score:=Frames[I].Score;
      // 同じ立上りの細かな山は品質と無関係に先に統合し、設定値による時刻移動を防ぐ。
      if (List.Count>0) and (C.Hit.Time-List[List.Count-1].Hit.Time<Gap) then begin
        if C.Score>List[List.Count-1].Score then List[List.Count-1]:=C;Inc(Result.FStats.Merged);
      end else List.Add(C);
    end;
    Extra:=List.ToArray;Capacity:=Max(0,100000-Length(Audio.Hits));Result.FStats.Qualified:=Length(Extra);
    if Length(Extra)>Capacity then begin
      Result.FStats.Capped:=Length(Extra)-Capacity;
      TArray.Sort<TOrbitCandidate>(Extra,TComparer<TOrbitCandidate>.Construct(function(const A,B:TOrbitCandidate):Integer
        begin Result:=CompareValue(B.Quality,A.Quality);if Result=0 then Result:=CompareValue(A.Hit.Time,B.Hit.Time);end));
      SetLength(Extra,Capacity);
    end;
    TArray.Sort<TOrbitCandidate>(Extra,TComparer<TOrbitCandidate>.Construct(function(const A,B:TOrbitCandidate):Integer begin Result:=CompareValue(A.Hit.Time,B.Hit.Time);end));
    Result.FExtras:=Extra;
    except Result.Free;raise;end;
  finally List.Free;end;
end;
function TOrbitCandidatePool.Select(Audio:TRhythmAudio;Value:Integer;out Stats:TOrbitAudioStats):TRhythmAudio;
var I,J:Integer;List:TList<TRhythmHit>;Cut:Double;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if (Value< -100) or (Value>100) then raise EArgumentOutOfRangeException.Create('音要素');
  Result:=Snapshot(Audio);Stats:=FStats;List:=TList<TRhythmHit>.Create;
  try
    try
      I:=0;J:=0;Cut:=100+Value;
      while (I<Length(FLegacy)) or (J<Length(FExtras)) do begin
        if (I<Length(FLegacy)) and ((J>=Length(FExtras)) or (FLegacy[I].Time<FExtras[J].Hit.Time)) then begin List.Add(FLegacy[I]);Inc(I);end
        else begin if (Value<0) and (FExtras[J].Quality>=Cut) then begin List.Add(FExtras[J].Hit);Inc(Stats.SelectedExtra);end;Inc(J);end;
      end;
      Result.Hits:=List.ToArray;
    except Result.Free;raise;end;
  finally List.Free;end;
end;
function PrepareOrbitAudio(Audio:TRhythmAudio;Value:Integer;out Stats:TOrbitAudioStats;
  const Cancel:TFunc<Boolean>;IncludeRollTicks:Boolean):TRhythmAudio;
var Pool:TOrbitCandidatePool;
begin
  if (Value< -100) or (Value>100) then raise EArgumentOutOfRangeException.Create('音要素');
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if Value>=0 then begin Stats:=Default(TOrbitAudioStats);Stats.Legacy:=Length(Audio.Hits);Result:=Snapshot(Audio);Result.Hits:=Copy(Audio.Hits);Exit;end;
  Pool:=TOrbitCandidatePool.Analyze(Audio,Cancel);
  try
    Result:=Pool.Select(Audio,Value,Stats);
    try
      if IncludeRollTicks and (Value<=RHYTHM_ROLL_SENSITIVITY) then Stats.RollTicks:=AddRollTicks(Audio,Result,Cancel);
    except
      Result.Free;
      raise;
    end;
  finally
    Pool.Free;
  end;
end;

function TOrbitCandidatePool.SelectSpaced(Audio:TRhythmAudio;Value:Integer;const Cancel:TFunc<Boolean>):TArray<TRhythmHit>;
const Gap=0.18;
var
  Candidates:TArray<TOrbitCandidate>;
  Occupied:TArray<Double>;
  List:TList<TRhythmHit>;
  Candidate:TOrbitCandidate;
  Hit:TRhythmHit;
  I,J,Bucket,Near,Seed:Integer;
  Cut:Double;
  Blocked:Boolean;
begin
  Cut:=100-(AUDIO_DEFAULT_DENSITY-Value)*100/(AUDIO_DEFAULT_DENSITY+100);
  Candidates:=Copy(FExtras);
  // 品質の高い候補から採用する。左へ動かしても先に採用した時刻は動かない。
  TArray.Sort<TOrbitCandidate>(Candidates,TComparer<TOrbitCandidate>.Construct(
    function(const A,B:TOrbitCandidate):Integer
    begin
      Result:=CompareValue(B.Quality,A.Quality,0.0);
      if Result=0 then Result:=CompareValue(A.Hit.Time,B.Hit.Time,0.0);
    end));
  SetLength(Occupied,Floor(Audio.SoundEnd/Gap)+1);
  for I:=0 to High(Occupied) do Occupied[I]:=-1;
  List:=TList<TRhythmHit>.Create;
  try
    List.AddRange(Audio.Hits);
    for I:=0 to High(Candidates) do begin
      if (I mod 256=0) and Assigned(Cancel) and Cancel() then Abort;
      Candidate:=Candidates[I];
      if Candidate.Quality<Cut then Break;
      Hit:=Candidate.Hit;
      Near:=Audio.NearestHit(Hit.Time);
      Blocked:=False;
      for J:=Max(0,Near-1) to Near do
        if Abs(Audio.Hits[J].Time-Hit.Time)<Gap then Blocked:=True;
      if Blocked then Continue;
      Bucket:=Floor(Hit.Time/Gap);
      for J:=Max(0,Bucket-1) to Min(High(Occupied),Bucket+1) do
        if (Occupied[J]>=0) and (Abs(Occupied[J]-Hit.Time)<Gap) then Blocked:=True;
      if Blocked then Continue;
      Occupied[Bucket]:=Hit.Time;
      Seed:=Round(Hit.Time*100);
      Seed:=(Seed*73+(Seed mod 17)*131) mod 997;
      Hit.Lane:=0.14+Seed/996.0*0.72;
      Hit.Flight:=ShotFlightTime(Hit.Time,Hit.Lane,Hit.Strength);
      List.Add(Hit);
    end;
    Result:=List.ToArray;
    TArray.Sort<TRhythmHit>(Result,TComparer<TRhythmHit>.Construct(
      function(const A,B:TRhythmHit):Integer
      begin
        Result:=CompareValue(A.Time,B.Time,0.0);
      end));
  finally
    List.Free;
  end;
end;

function SelectAnimationHits(Audio:TRhythmAudio;Value:Integer;const Cancel:TFunc<Boolean>):TArray<TRhythmHit>;
var Pool:TOrbitCandidatePool;I,Count:Integer;Cut:Double;
begin
  if Value<AUDIO_DEFAULT_DENSITY then begin
    Pool:=TOrbitCandidatePool.Analyze(Audio,Cancel);
    try
      Result:=Pool.SelectSpaced(Audio,Value,Cancel);
    finally
      Pool.Free;
    end;
    Exit;
  end;
  if Value=AUDIO_DEFAULT_DENSITY then Exit(Audio.Hits);
  Cut:=0.15+0.85*(Value-AUDIO_DEFAULT_DENSITY)/(100-AUDIO_DEFAULT_DENSITY);
  SetLength(Result,Length(Audio.Hits));
  Count:=0;
  for I:=0 to High(Audio.Hits) do begin
    if (I mod 256=0) and Assigned(Cancel) and Cancel() then Abort;
    if Audio.Hits[I].Strength<Cut then Continue;
    Result[Count]:=Audio.Hits[I];
    Inc(Count);
  end;
  SetLength(Result,Count);
end;
end.
