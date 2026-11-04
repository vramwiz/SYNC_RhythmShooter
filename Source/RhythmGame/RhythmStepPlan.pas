unit RhythmStepPlan;
// 譜面の時刻と左右のレーン割当を固定し、音声を再解析せず復元する。
interface
uses System.SysUtils,System.JSON,RhythmAudio,RhythmPlanRef;

const
  STEP_LANE_COUNT=4;
  STEP_LOOKAHEAD=1.65; // 秒。譜面下端から判定線に達するまでの時間。
  STEP_FLASH_TIME=0.32;
  STEP_TIME_EPSILON=1E-10; // ホストの時刻−オフセットで生じる浮動小数点の丸めだけを吸収。

type
  TStepNote=record
    Time,Strength:Double;
    Lanes:array[0..1] of Byte; // 左右の譜面それぞれの4レーンをビットで表す。
  end;

  TStepPlan=class
  private
    FNotes:TArray<TStepNote>;
    FDuration,FSoundEnd:Double;
    FThreshold,FVersion:Integer;
    function GetCount:Integer;
    function GetNote(Index:Integer):TStepNote;
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
  end;

implementation
uses System.Math,System.Generics.Collections,RhythmStyles,RhythmPreparedData,RhythmOrbitAudio;

const
  MaxNotes=100000;
  Policy='prism-step-v';

function TStepPlan.IsRoll(Index:Integer):Boolean;
var L,R:Integer;
begin
  if (FVersion<2) or (FThreshold>RHYTHM_ROLL_SENSITIVITY) or (Index<0) or (Index>=Count) then Exit(False);
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

class function TStepPlan.Build(Audio:TRhythmAudio;Threshold:Integer;const Cancel:TFunc<Boolean>):TStepPlan;
const
  Motif:array[0..1,0..15] of Byte=(
    (0,1,3,2,1,2,0,3,2,0,1,3,1,3,2,1),
    (2,3,1,0,3,1,2,0,1,2,3,1,0,2,0,3));
var I,J,N,Lane:Integer;Hit:TRhythmHit;Last,Previous,LastChord:Double;Chord,Roll:Boolean;
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
    Previous:=-1;
    LastChord:=-1;
    for I:=0 to N-1 do begin
      if (I mod 256=0) and Assigned(Cancel) and Cancel() then Abort;
      // 強音でだけ同時押し風の二列発光。密な区間では単音の列を優先する。
      Roll:=Result.IsRoll(I);
      Chord:=not Roll and (Result.FNotes[I].Strength>=0.78) and (Result.FNotes[I].Time-LastChord>=0.72) and
        (Result.FNotes[I].Time-Previous>=0.16) and ((I=N-1) or (Result.FNotes[I+1].Time-Result.FNotes[I].Time>=0.16));
      for J:=0 to 1 do begin
        Lane:=Motif[J,I mod 16];
        if Roll then Lane:=(I+J) mod 2+2*J;
        Result.FNotes[I].Lanes[J]:=1 shl Lane;
        if Chord then Result.FNotes[I].Lanes[J]:=Result.FNotes[I].Lanes[J] or (1 shl (Lane xor (2-J)));
      end;
      Previous:=Result.FNotes[I].Time;
      if Chord then LastChord:=Previous;
    end;
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
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

class function TStepPlan.ReadChart(Root:TJSONObject;const Ref:TRhythmPlanRef):TStepPlan;
var Rows,Row:TJSONArray;I:Integer;Note:TStepNote;Last:Double;
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
    for I:=0 to Rows.Count-1 do begin
      Row:=Rows.Items[I] as TJSONArray;
      if Row.Count<>4 then raise EConvertError.Create('Invalid step chart row');
      Note.Time:=ReadPreparedExact(Row.Items[0]);
      Note.Strength:=ReadPreparedExact(Row.Items[1]);
      Note.Lanes[0]:=ReadMask(Row.Items[2]);
      Note.Lanes[1]:=ReadMask(Row.Items[3]);
      if (Note.Time<0) or (Note.Time<=Last) or (Result.SoundEnd<=0) or (Note.Time>Result.SoundEnd) or
        (Note.Strength<Result.FThreshold/100) then raise EConvertError.Create('Invalid step chart accent');
      Result.FNotes[I]:=Note;
      Last:=Note.Time;
    end;
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
