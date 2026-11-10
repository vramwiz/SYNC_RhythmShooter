unit RhythmStepPlan;
// 譜面の時刻と左右のレーン割当を固定し、音声を再解析せず復元する。
{$POINTERMATH ON}
interface
uses System.SysUtils,System.JSON,RhythmAudio,RhythmPlanRef;

const
  STEP_LANE_COUNT=4;
  STEP_LOOKAHEAD=1.65; // 秒。譜面下端から判定線に達するまでの時間。
  STEP_FLASH_TIME=0.32;
  STEP_TIME_EPSILON=1E-10; // ホストの時刻−オフセットで生じる浮動小数点の丸めだけを吸収。
  STEP_PATTERN_VERSION=3;

type
  TStepKind=(stTap,stChord,stRoll,stRollEnd,stSweep,stSweepEnd,stHold,stSlide,stSlideEnd);
  TStepNote=record
    Time,Strength,EndTime:Double; // EndTimeはロングの離す時刻だけに使う。
    Lanes:array[0..1] of Byte; // 左右の譜面それぞれの4レーンをビットで表す。
    Kind:TStepKind;
  end;

  TStepPlan=class
  private
    FNotes:TArray<TStepNote>;
    FDuration,FSoundEnd:Double;
    FThreshold,FVersion:Integer;
    function GetCount:Integer;
    function GetNote(Index:Integer):TStepNote;
    procedure AssignPatterns(const PCM:TBytes;const Cancel:TFunc<Boolean>);
    procedure CheckPattern(Index:Integer);
    class function ReadChart(Root:TJSONObject;const Ref:TRhythmPlanRef):TStepPlan;static;
  public
    class function Build(Audio:TRhythmAudio;Threshold:Integer;const Cancel:TFunc<Boolean>=nil):TStepPlan;static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TStepPlan;static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;static;
    function CountThrough(Time:Double):Integer;
    function IsRoll(Index:Integer):Boolean;
    property Count:Integer read GetCount;
    property Notes[Index:Integer]:TStepNote read GetNote;
    property Duration:Double read FDuration;
    property SoundEnd:Double read FSoundEnd;
    property Version:Integer read FVersion;
  end;

function StepLane(Mask:Byte):Integer;

implementation
uses System.Math,System.Generics.Collections,RhythmStyles,RhythmPreparedData,RhythmOrbitAudio;

const
  MaxNotes=100000;
  Policy='prism-step-v';
  HoldMin=0.36;
  HoldMax=3.2;
  SweepGap=0.36;
  SlideMin=0.18;
  SlideMax=0.34;
  Motif:array[0..1,0..15] of Byte=(
    (0,1,3,2,1,2,0,3,2,0,1,3,1,3,2,1),
    (2,3,1,0,3,1,2,0,1,2,3,1,0,2,0,3));

function StepLane(Mask:Byte):Integer;
begin
  case Mask of
    1:Result:=0;
    2:Result:=1;
    4:Result:=2;
    8:Result:=3;
  else
    Result:=-1;
  end;
end;

function TStepPlan.IsRoll(Index:Integer):Boolean;
var L,R:Integer;
begin
  if (Index<0) or (Index>=Count) then Exit(False);
  if FVersion>=STEP_PATTERN_VERSION then Exit(FNotes[Index].Kind in [stRoll,stRollEnd]);
  if (FVersion<2) or (FThreshold>RHYTHM_ROLL_SENSITIVITY) then Exit(False);
  L:=Index;R:=Index;
  while (L>0) and (Index-L<2) and RollPair(FNotes[L-1].Time,FNotes[L].Time) do Dec(L);
  while (R+1<Count) and (R-L<2) and RollPair(FNotes[R].Time,FNotes[R+1].Time) do Inc(R);
  Result:=R-L>=2;
end;

function Finite(Value:Double):Boolean;
begin
  Result:=not (IsNan(Value) or IsInfinite(Value));
end;

procedure CheckBounds(Duration,SoundEnd:Double;Threshold,Count:Integer);
begin
  if not Finite(Duration) or not Finite(SoundEnd) or (Duration<=0) or
    (Duration>512*Int64(1024)*1024/4/RHYTHM_RATE) or (SoundEnd<0) or (SoundEnd>Duration) or
    (Threshold< -100) or (Threshold>100) or (Count>MaxNotes) then
    raise EArgumentException.Create('4レーン譜面の範囲が不正です。');
end;

function ReadMask(Value:TJSONValue):Byte;
var Mask:Integer;
begin
  if not (Value is TJSONNumber) or not TryStrToInt(Value.Value,Mask) or (Mask<1) or (Mask>15) then
    raise EConvertError.Create('Invalid step chart lane mask');
  Result:=Byte(Mask);
end;

function TStepPlan.GetCount:Integer;
begin
  Result:=Length(FNotes);
end;

function TStepPlan.GetNote(Index:Integer):TStepNote;
begin
  Result:=FNotes[Index];
end;

function TStepPlan.CountThrough(Time:Double):Integer;
var Hi,Mid:Integer;
begin
  Result:=0;
  Hi:=Count;
  while Result<Hi do begin
    Mid:=Result+(Hi-Result) div 2;
    if FNotes[Mid].Time<=Time+STEP_TIME_EPSILON then Result:=Mid+1 else Hi:=Mid;
  end;
end;

// 先頭の立ち上がりを許容し、その直後から続く周期音だけをロングに使う。
function HoldEnd(const PCM:TBytes;Start,Limit:Double):Double;
const Block=RHYTHM_SUSTAIN_BLOCK_SAMPLES;MinBlocks=9;
var First,Finish,Pos,Run,Skip:Integer;
begin
  Result:=0;
  First:=Ceil(Start*RHYTHM_RATE-1E-8);
  Finish:=Min(Length(PCM) div 4,Floor(Min(Limit,Start+HoldMax)*RHYTHM_RATE));
  if Finish-First<MinBlocks*Block then Exit;
  Pos:=First;
  Run:=0;
  Skip:=0;
  while Pos+Block<=Finish do begin
    if SustainedBlock(PSmallInt(PCM)+Pos*2) then Inc(Run)
    else if (Run=0) and (Skip<2) then Inc(Skip)
    else Break;
    Inc(Pos,Block);
  end;
  if Run>=MinBlocks then Result:=Pos/RHYTHM_RATE;
end;

procedure TStepPlan.AssignPatterns(const PCM:TBytes;const Cancel:TFunc<Boolean>);
var I,J,K,Last,Lane,Steps,Sweeps,Start,Finish,RunPart:Integer;
  LastChord,Previous,Following,Gap,ReleaseAt,HoldLimit:Double;

  procedure CheckCancel(Index:Integer);
  begin
    if (Index mod 128=0) and Assigned(Cancel) and Cancel() then Abort;
  end;

begin
  for I:=0 to Count-1 do begin
    CheckCancel(I);
    for J:=0 to 1 do FNotes[I].Lanes[J]:=1 shl Motif[J,I mod 16];
  end;

  // 密集した打音は、同じレーンの連打にまとめる。
  I:=0;
  while I<Count do begin
    CheckCancel(I);
    Last:=I;
    while (Last+1<Count) and RollPair(FNotes[Last].Time,FNotes[Last+1].Time) do begin
      Inc(Last);
      CheckCancel(Last);
    end;
    Start:=I;
    RunPart:=0;
    while Last-Start>=2 do begin
      Finish:=Min(Last,Start+5);
      for K:=Start to Finish do begin
        FNotes[K].Lanes:=FNotes[Start].Lanes;
        FNotes[K].Kind:=stRoll;
      end;
      FNotes[Finish].Kind:=stRollEnd;
      Start:=Finish+1;
      // 長い密集区間には横移動も挟み、同じレーンの連打だけが続くのを防ぐ。
      if (RunPart mod 3=2) and (Last-Start>=6) then Inc(Start,7)
      else if Last-Start>=3 then Inc(Start,4);
      Inc(RunPart);
    end;
    I:=Last+1;
  end;

  // 間隔に余裕のある連続音は左右へ流す。2Pは逆向きにする。
  I:=0;
  Sweeps:=0;
  while I<Count do begin
    CheckCancel(I);
    Last:=I;
    if FNotes[I].Kind=stTap then
      while (Last+1<Count) and (Last-I<6) and (FNotes[Last+1].Kind=stTap) and
        (FNotes[Last+1].Time-FNotes[Last].Time<=SweepGap) do Inc(Last);
    if Last-I<3 then begin Inc(I);Continue;end;
    Steps:=4;
    if (Last-I>=6) and (Sweeps mod 3=2) then Steps:=7;
    for K:=0 to Steps-1 do begin
      Lane:=Min(K,6-K);
      if Sweeps mod 3=1 then Lane:=3-Lane;
      FNotes[I+K].Lanes[0]:=1 shl Lane;
      FNotes[I+K].Lanes[1]:=1 shl (3-Lane);
      FNotes[I+K].Kind:=stSweep;
    end;
    FNotes[I+Steps-1].Kind:=stSweepEnd;
    Inc(Sweeps);
    Inc(I,Steps);
    // 長い等間隔のフレーズにも単発や同時押しを差し込める余地を残す。
    if (I<Count) and (FNotes[I].Time-FNotes[I-1].Time<=SweepGap) then Inc(I);
  end;

  LastChord:=-1;
  for I:=0 to Count-1 do begin
    CheckCancel(I);
    if FNotes[I].Kind<>stTap then Continue;
    Previous:=-1;
    Following:=FSoundEnd;HoldLimit:=FSoundEnd;
    if I>0 then Previous:=FNotes[I-1].Time;
    if I+1<Count then begin
      Following:=FNotes[I+1].Time;
      HoldLimit:=Following-0.04;
    end;
    ReleaseAt:=HoldEnd(PCM,FNotes[I].Time,HoldLimit);
    if ReleaseAt>0 then begin
      FNotes[I].Kind:=stHold;
      FNotes[I].EndTime:=ReleaseAt;
    end else if (FNotes[I].Strength>=0.78) and (FNotes[I].Time-LastChord>=0.72) and
      (FNotes[I].Time-Previous>=0.16) and ((I+1=Count) or (Following-FNotes[I].Time>=0.16)) then begin
      for J:=0 to 1 do begin
        Lane:=StepLane(FNotes[I].Lanes[J]);
        FNotes[I].Lanes[J]:=FNotes[I].Lanes[J] or (1 shl (Lane xor (2-J)));
      end;
      FNotes[I].Kind:=stChord;
      LastChord:=FNotes[I].Time;
    end;
  end;

  for I:=0 to Count-2 do begin
    CheckCancel(I);
    if (FNotes[I].Kind<>stTap) or (FNotes[I+1].Kind<>stTap) then Continue;
    Gap:=FNotes[I+1].Time-FNotes[I].Time;
    if (Gap<SlideMin) or (Gap>SlideMax) or (FNotes[I+1].Strength<FNotes[I].Strength) then Continue;
    for J:=0 to 1 do
      if FNotes[I].Lanes[J]=FNotes[I+1].Lanes[J] then
        FNotes[I+1].Lanes[J]:=1 shl ((StepLane(FNotes[I].Lanes[J])+1) mod STEP_LANE_COUNT);
    FNotes[I].Kind:=stSlide;
    FNotes[I+1].Kind:=stSlideEnd;
  end;
end;

class function TStepPlan.Build(Audio:TRhythmAudio;Threshold:Integer;const Cancel:TFunc<Boolean>):TStepPlan;
var I,N:Integer;Hit:TRhythmHit;Last:Double;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  CheckBounds(Audio.Duration,Audio.SoundEnd,Threshold,Length(Audio.Hits));
  Result:=TStepPlan.Create;
  try
    Result.FDuration:=Audio.Duration;
    Result.FSoundEnd:=Audio.SoundEnd;
    Result.FThreshold:=Threshold;
    Result.FVersion:=StylePlanVersion(rsStepGame);
    SetLength(Result.FNotes,Length(Audio.Hits));
    Last:=-1;
    N:=0;
    for I:=0 to High(Audio.Hits) do begin
      if (I mod 256=0) and Assigned(Cancel) and Cancel() then Abort;
      Hit:=Audio.Hits[I];
      if not Finite(Hit.Time) or not Finite(Hit.Strength) or (Hit.Time<0) or (Hit.Time<Last) or (Hit.Time>Audio.Duration+0.011) then
        raise EArgumentException.Create('音の時刻または強度が不正です。');
      Last:=Hit.Time;
      if (Audio.SoundEnd<=0) or (Hit.Time>Audio.SoundEnd) or (Hit.Strength<Threshold/100) then Continue;
      // 同時刻の候補は一拍にまとめ、元の時刻と最も強い候補を保持する。
      if (N>0) and (Result.FNotes[N-1].Time=Hit.Time) then begin
        Result.FNotes[N-1].Strength:=Max(Result.FNotes[N-1].Strength,Hit.Strength);
        Continue;
      end;
      Result.FNotes[N].Time:=Hit.Time;
      Result.FNotes[N].Strength:=Hit.Strength;
      Inc(N);
    end;
    SetLength(Result.FNotes,N);
    Result.AssignPatterns(Audio.PCM,Cancel);
  except
    Result.Free;
    raise;
  end;
end;

procedure TStepPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var Root,Info:TJSONObject;Rows,Row:TJSONArray;Note:TStepNote;
begin
  if (Audio=nil) or (Ref.Version<>FVersion) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsStepGame,FThreshold+101) or
    (Audio.Duration<>FDuration) or (Audio.SoundEnd<>FSoundEnd) then raise EArgumentException.Create('Step chart save identity');
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsStepGame));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('policy',Policy+IntToStr(FVersion));
    Root.AddPair('threshold',TJSONNumber.Create(FThreshold));
    Root.AddPair('durationExact',PreparedExact(FDuration));
    Root.AddPair('soundEndExact',PreparedExact(FSoundEnd));
    AddPreparedAudio(Root,Audio);
    Info:=Root.GetValue<TJSONObject>('audio');
    Info.RemovePair('events').Free;
    Info.AddPair('events',TJSONNumber.Create(Count));
    Rows:=TJSONArray.Create;
    Root.AddPair('notes',Rows);
    for Note in FNotes do begin
      Row:=TJSONArray.Create;
      Rows.AddElement(Row);
      Row.AddElement(PreparedExact(Note.Time));
      Row.AddElement(PreparedExact(Note.Strength));
      Row.Add(Note.Lanes[0]);
      Row.Add(Note.Lanes[1]);
      if FVersion>=STEP_PATTERN_VERSION then begin
        Row.Add(Ord(Note.Kind));
        Row.AddElement(PreparedExact(Note.EndTime));
      end;
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

procedure TStepPlan.CheckPattern(Index:Integer);
var Note,Other:TStepNote;J,Lane,OtherLane:Integer;Valid:Boolean;Gap:Double;
begin
  Note:=FNotes[Index];
  Valid:=True;
  for J:=0 to 1 do
    if Note.Kind=stChord then Valid:=Valid and (StepLane(Note.Lanes[J])<0) and
      (StepLane(Note.Lanes[J] and (Note.Lanes[J]-1))>=0)
    else Valid:=Valid and (StepLane(Note.Lanes[J])>=0);
  if Note.Kind=stHold then begin
    Valid:=Valid and (Note.EndTime-Note.Time>=HoldMin-STEP_TIME_EPSILON) and
      (Note.EndTime-Note.Time<=HoldMax+STEP_TIME_EPSILON) and (Note.EndTime<=SoundEnd);
    if Index+1<Count then Valid:=Valid and (Note.EndTime<FNotes[Index+1].Time);
  end else Valid:=Valid and (Note.EndTime=0);
  if Note.Kind in [stRoll,stSweep,stSlide] then begin
    if Index+1>=Count then Valid:=False
    else begin
      Other:=FNotes[Index+1];
      Gap:=Other.Time-Note.Time;
      for J:=0 to 1 do begin
        Lane:=StepLane(Note.Lanes[J]);
        OtherLane:=StepLane(Other.Lanes[J]);
        case Note.Kind of
          stRoll:Valid:=Valid and (Other.Kind in [stRoll,stRollEnd]) and (Lane=OtherLane) and RollPair(Note.Time,Other.Time);
          stSweep:Valid:=Valid and (Other.Kind in [stSweep,stSweepEnd]) and (Abs(Lane-OtherLane)=1) and (Gap<=SweepGap);
          stSlide:Valid:=Valid and (Other.Kind=stSlideEnd) and (Lane<>OtherLane) and (Gap>=SlideMin) and (Gap<=SlideMax);
        end;
      end;
    end;
  end;
  case Note.Kind of
    stRollEnd:Valid:=Valid and (Index>0) and (FNotes[Index-1].Kind=stRoll);
    stSweepEnd:Valid:=Valid and (Index>0) and (FNotes[Index-1].Kind=stSweep);
    stSlideEnd:Valid:=Valid and (Index>0) and (FNotes[Index-1].Kind=stSlide);
  end;
  if not Valid then raise EConvertError.Create('Invalid step chart pattern');
end;

class function TStepPlan.ReadChart(Root:TJSONObject;const Ref:TRhythmPlanRef):TStepPlan;
var Rows,Row:TJSONArray;I,Kind,Columns:Integer;Note:TStepNote;Last:Double;
begin
  if Root.GetValue<string>('policy','')<>Policy+IntToStr(Ref.Version) then raise EConvertError.Create('Unknown step chart policy');
  Rows:=Root.GetValue<TJSONArray>('notes');
  Result:=TStepPlan.Create;
  try
    Result.FDuration:=ReadPreparedExact(Root.GetValue('durationExact'));
    Result.FSoundEnd:=ReadPreparedExact(Root.GetValue('soundEndExact'));
    Result.FThreshold:=Root.GetValue<Integer>('threshold',-1000);
    Result.FVersion:=Ref.Version;
    if (Rows=nil) or (Ref.Variant<>Result.FThreshold+101) then raise EConvertError.Create('Invalid step chart identity');
    CheckBounds(Result.Duration,Result.SoundEnd,Result.FThreshold,Rows.Count);
    SetLength(Result.FNotes,Rows.Count);
    Last:=-1;
    Columns:=4;
    if Ref.Version>=STEP_PATTERN_VERSION then Columns:=6;
    for I:=0 to Rows.Count-1 do begin
      Row:=Rows.Items[I] as TJSONArray;
      if (Row=nil) or (Row.Count<>Columns) then raise EConvertError.Create('Invalid step chart row');
      Note:=Default(TStepNote);
      Note.Time:=ReadPreparedExact(Row.Items[0]);
      Note.Strength:=ReadPreparedExact(Row.Items[1]);
      Note.Lanes[0]:=ReadMask(Row.Items[2]);
      Note.Lanes[1]:=ReadMask(Row.Items[3]);
      if Columns=6 then begin
        if not (Row.Items[4] is TJSONNumber) or not TryStrToInt(Row.Items[4].Value,Kind) or
          (Kind<Ord(Low(TStepKind))) or (Kind>Ord(High(TStepKind))) then raise EConvertError.Create('Invalid step note kind');
        Note.Kind:=TStepKind(Kind);
        Note.EndTime:=ReadPreparedExact(Row.Items[5]);
      end;
      if (Note.Time<0) or (Note.Time<=Last) or (Result.SoundEnd<=0) or (Note.Time>Result.SoundEnd) or
        (Note.Strength<Result.FThreshold/100) then raise EConvertError.Create('Invalid step chart accent');
      Result.FNotes[I]:=Note;
      Last:=Note.Time;
    end;
    if Columns=6 then for I:=0 to Rows.Count-1 do Result.CheckPattern(I);
  except
    Result.Free;
    raise;
  end;
end;

class function TStepPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TStepPlan;
var Root:TJSONObject;
begin
  if (Audio=nil) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsStepGame,Ref.Variant) then
    raise EArgumentException.Create('Step chart load identity');
  Root:=ReadPreparedData(Ref,rsStepGame,Direction);
  try
    Result:=ReadChart(Root,Ref);
    if (Abs(Result.Duration-Audio.Duration)>1E-7) or (Abs(Result.SoundEnd-Audio.SoundEnd)>1E-7) then begin
      Result.Free;
      raise EConvertError.Create('Step chart source duration mismatch');
    end;
  finally
    Root.Free;
  end;
end;

class function TStepPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;Plan:TStepPlan;I:Integer;
begin
  Root:=ReadPreparedData(Ref,rsStepGame,Direction);
  try
    Plan:=ReadChart(Root,Ref);
    try
      Result:=PreparedAudio(Root,Ref,Source);
      try
        if (Length(Result.Hits)<>Plan.Count) or (Abs(Result.Duration-Plan.Duration)>1E-7) or
          (Abs(Result.SoundEnd-Plan.SoundEnd)>1E-7) then raise EConvertError.Create('Step chart audio metadata mismatch');
        Result.Duration:=Plan.Duration;
        Result.SoundEnd:=Plan.SoundEnd;
        for I:=0 to Plan.Count-1 do begin
          Result.Hits[I].Time:=Plan.FNotes[I].Time;
          Result.Hits[I].Strength:=Plan.FNotes[I].Strength;
        end;
      except
        Result.Free;
        raise;
      end;
    finally
      Plan.Free;
    end;
  finally
    Root.Free;
  end;
end;
end.
