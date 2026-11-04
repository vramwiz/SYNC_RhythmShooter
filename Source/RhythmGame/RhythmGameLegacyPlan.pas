unit RhythmGameLegacyPlan;
// 全曲の音時刻から判定マークとカーソル軌道を逆算する。描画状態やPCMは保存しない。
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef;
const
  GAME_MAX_NOTES=100000;
  GAME_VISIBLE_NOTES=128;
  GAME_VISIBLE_EFFECTS=32;
  GAME_EFFECT_LIFE=0.48;
type
  TGamePoint=record
    X,Y:Double;
  end;
  TGameNote=record
    Time,Appear,Start,Strength:Double;
    Source,Hue,Mode,Chain:Integer;
    A,B,C,D:TGamePoint;
    Roll:Boolean;
  end;
  TLegacyGamePlan=class
  private
    FEvents:TArray<TRhythmHit>;
    FNotes:TArray<TGameNote>;
    FDuration,FSoundEnd,FEnd:Double;
    FExcluded:Integer;
    procedure Validate;
    function GetCount:Integer;
    function GetNote(Index:Integer):TGameNote;
  public
    // 借用Audioのアクセントは並べ替え・間引き・時刻変更しない。
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TLegacyGamePlan; static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TLegacyGamePlan; static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio; static;
    function Before(Time:Double):Integer;
    procedure VisibleRange(Time:Double;out First,Last:Integer);
    function CursorAt(Time:Double):TGamePoint;
    property Count:Integer read GetCount;
    property Notes[Index:Integer]:TGameNote read GetNote;
    property Duration:Double read FDuration;
    property SoundEnd:Double read FSoundEnd;
    property EndTime:Double read FEnd;
    property Excluded:Integer read FExcluded;
  end;
function GamePoint(X,Y:Double):TGamePoint;
function GameNoteAt(const N:TGameNote;Time:Double):TGamePoint;
function GameCurveAt(const N:TGameNote;U:Double):TGamePoint;
function GameEffectOpacity(Age:Double):Double;
implementation
uses System.Math,System.JSON,RhythmStyles,RhythmPreparedData;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

// Delphi JSONの十進変換で失われる最下位ビットも保存し、warm/coldを一致させる。
function ExactJSON(V:Double):TJSONString;
var Bits:UInt64;
begin Move(V,Bits,8);Result:=TJSONString.Create(IntToHex(Bits,16));end;

function ExactValue(Value:TJSONValue):Double;
var Bits:UInt64;
begin
  if not (Value is TJSONString) or (Length(Value.Value)<>16) or
  not TryStrToUInt64('$'+Value.Value,Bits) then raise Exception.Create('RhythmGame binary64');
  Move(Bits,Result,8);
  if not Finite(Result) then raise Exception.Create('RhythmGame nonfinite binary64');
end;

function GamePoint(X,Y:Double):TGamePoint;
begin Result.X:=X;
  Result.Y:=Y;
end;

function GameCurveAt(const N:TGameNote;U:Double):TGamePoint;
var V:Double;
begin U:=EnsureRange(U,0.0,1.0);V:=1-U;
  Result.X:=V*V*V*N.A.X+3*V*V*U*N.B.X+3*V*U*U*N.C.X+U*U*U*N.D.X;
  Result.Y:=V*V*V*N.A.Y+3*V*V*U*N.B.Y+3*V*U*U*N.C.Y+U*U*U*N.D.Y;
end;

function GameNoteAt(const N:TGameNote;Time:Double):TGamePoint;
var U:Double;
begin
  // 接触は音時刻そのもの。移動開始だけを逆算し、曲頭の音も後ろへずらさない。
  if Time>=N.Time then Exit(N.D);
  if Time<=N.Start then Exit(N.A);
  U:=EnsureRange((Time-N.Start)/(N.Time-N.Start),0.0,1.0);
  Result:=GameCurveAt(N,U*U*(3-2*U));
end;

function GameEffectOpacity(Age:Double):Double;
var U:Double;
begin
  if (Age<0) or (Age>=GAME_EFFECT_LIFE) then Exit(0);
  U:=EnsureRange((Age-0.018)/(GAME_EFFECT_LIFE-0.018),0.0,1.0);
  Result:=1-U*U*(3-2*U);
end;

function TLegacyGamePlan.GetCount:Integer;
begin Result:=Length(FNotes);
end;

function TLegacyGamePlan.GetNote(Index:Integer):TGameNote;
begin Result:=FNotes[Index];
end;

function TLegacyGamePlan.Before(Time:Double):Integer;
var L,R,M:Integer;
begin L:=0;R:=Count;
  while L<R do begin M:=L+(R-L) div 2;
    if FNotes[M].Time<=Time then L:=M+1 else R:=M;
  end;
  Result:=L-1;
end;

procedure TLegacyGamePlan.VisibleRange(Time:Double;out First,Last:Integer);
begin First:=Before(Time-GAME_EFFECT_LIFE)+1;Last:=Before(Time+0.95);
end;

function TLegacyGamePlan.CursorAt(Time:Double):TGamePoint;
var I:Integer;
begin
  if Count=0 then Exit(GamePoint(0.5,0.5));
  I:=Before(Time);
  if I=Count-1 then Exit(FNotes[I].D);
  Result:=GameNoteAt(FNotes[I+1],Time);
end;

procedure TLegacyGamePlan.Validate;
var I,Expected:Integer;N:TGameNote;Last,Gap,DX,DY:Double;Previous:TGamePoint;
  procedure CheckPoint(const P:TGamePoint);
  begin
    if not Finite(P.X) or not Finite(P.Y) or (P.X<0.05) or (P.X>0.95) or
    (P.Y<0.08) or (P.Y>0.92) then raise Exception.Create('RhythmGame path bounds');
  end;
begin
  if not Finite(FDuration) or not Finite(FSoundEnd) or not Finite(FEnd) or
  (FDuration<=0) or (FDuration>3043.5) or (FSoundEnd<0) or (FSoundEnd>FDuration) or
  (FEnd<>Max(FDuration,FSoundEnd+GAME_EFFECT_LIFE)) or
  (Length(FEvents)>GAME_MAX_NOTES) or (Count>Length(FEvents)) then raise Exception.Create('RhythmGame bounds');
  Last:=-1;Expected:=0;
  for I:=0 to High(FEvents) do begin
    if not Finite(FEvents[I].Time) or not Finite(FEvents[I].Strength) or
    (FEvents[I].Time<0) or (FEvents[I].Time<Last) or (FEvents[I].Time>FDuration+0.011) then raise Exception.Create('RhythmGame accent');
    Last:=FEvents[I].Time;
    if (FSoundEnd>0) and (Last<=FSoundEnd) then begin
      if Expected>=Count then raise Exception.Create('RhythmGame missing note');
      N:=FNotes[Expected];
      if (N.Source<>I) or (N.Time<>Last) or (N.Strength<>EnsureRange(FEvents[I].Strength,0.0,1.0)) then raise Exception.Create('RhythmGame source time');
      Inc(Expected);
    end;
  end;
  if (Expected<>Count) or (FExcluded<>Length(FEvents)-Count) then raise Exception.Create('RhythmGame event coverage');
  Previous:=GamePoint(0.5,0.5);
  for I:=0 to Count-1 do begin
    N:=FNotes[I];
    if not Finite(N.Appear) or not Finite(N.Start) or (N.Time-N.Appear<0.39) or
    (N.Time-N.Appear>0.96) or (N.Start>N.Time) or (N.Time-N.Start>0.81) or
    (N.Hue<0) or (N.Hue>7) or (N.Mode<0) or (N.Mode>2) or
    (N.Chain<1) or (N.Chain>I+1) then raise Exception.Create('RhythmGame note');
    if (N.A.X<>Previous.X) or (N.A.Y<>Previous.Y) then raise Exception.Create('RhythmGame cursor discontinuity');
    if I>0 then begin Gap:=N.Time-FNotes[I-1].Time;
      if N.Start<FNotes[I-1].Time then raise Exception.Create('RhythmGame premature movement');
      DX:=N.D.X-N.A.X;DY:=N.D.Y-N.A.Y;
      if Hypot(DX,DY)>Min(0.84,Gap*2.7)+1E-9 then raise Exception.Create('RhythmGame dense travel');
    end;
    CheckPoint(N.A);CheckPoint(N.B);CheckPoint(N.C);CheckPoint(N.D);Previous:=N.D;
  end;
end;

class function TLegacyGamePlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TLegacyGamePlan;
var I,K,Section,Chain:Integer;N:TGameNote;Gap,Lead,SectionStart,Last,Phase,Distance,Limit,Bend,DX,DY:Double;
  Previous,Desired:TGamePoint;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if Assigned(Cancel) and Cancel() then Abort;
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or
  (Audio.Duration>3043.5) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) then raise Exception.Create('RhythmGame audio bounds');
  Result:=TLegacyGamePlan.Create;
  try
    Result.FDuration:=Audio.Duration;Result.FSoundEnd:=Audio.SoundEnd;
    Result.FEnd:=Max(Audio.Duration,Audio.SoundEnd+GAME_EFFECT_LIFE);
    if Length(Audio.Hits)>GAME_MAX_NOTES then raise Exception.Create('RhythmGame too many accents');
    Result.FEvents:=Copy(Audio.Hits);SetLength(Result.FNotes,Length(Audio.Hits));
    K:=0;Section:=0;SectionStart:=0;Chain:=0;Last:=-1;Previous:=GamePoint(0.5,0.5);
    for I:=0 to High(Audio.Hits) do begin
      if Assigned(Cancel) and Cancel() then Abort;
      if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or
      (Audio.Hits[I].Time<Last) or (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('RhythmGame input order');
      Last:=Audio.Hits[I].Time;
      if (Audio.SoundEnd<=0) or (Last>Audio.SoundEnd) then begin Inc(Result.FExcluded);Continue;end;
      Gap:=1;if K>0 then Gap:=Last-Result.FNotes[K-1].Time;
      if (K>0) and ((Gap>0.85) or ((Last-SectionStart>=5.2) and (I mod 16=0))) then begin Inc(Section);SectionStart:=Last;end;
      if (K=0) or (Gap>0.18) then Chain:=1 else Inc(Chain);
      N:=Default(TGameNote);N.Time:=Last;N.Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);
      N.Source:=I;N.Mode:=Section mod 3;N.Hue:=(Section*2+I div 8) mod 8;
      N.Chain:=Chain;N.Roll:=Gap<=0.18;
      Lead:=0.58+Min(0.32,Gap*0.34)-N.Strength*0.035;N.Appear:=N.Time-Lead;
      N.Start:=N.Time-Min(0.8,Max(0.0,Gap));
      if K>0 then N.Start:=Max(Result.FNotes[K-1].Time,N.Time-0.8);
      // 時間を進めるシミュレーションではなく、隣接アクセントから一本の軌道を確定。
      Phase:=(Last-SectionStart)*1.9+Section*0.83;
      case N.Mode of
        1:Desired:=GamePoint(0.5+0.40*Sin(Phase),0.5+0.32*Sin(Phase*2+0.6));
        2:Desired:=GamePoint(0.5+0.39*Cos(Phase*0.85),0.5+0.33*Sin(Phase*1.7));
        else Desired:=GamePoint(0.5+0.41*Cos(Phase),0.5+0.34*Sin(Phase));
      end;
      DX:=Desired.X-Previous.X;DY:=Desired.Y-Previous.Y;Distance:=Hypot(DX,DY);Limit:=Min(0.84,Gap*2.7);
      if (K>0) and (Distance>Limit) then begin Desired.X:=Previous.X+DX*Limit/Distance;Desired.Y:=Previous.Y+DY*Limit/Distance;end;
      N.A:=Previous;N.D:=Desired;DX:=N.D.X-N.A.X;DY:=N.D.Y-N.A.Y;Bend:=0.15*Sin(Phase+Section);
      N.B:=GamePoint(EnsureRange(N.A.X+DX/3-DY*Bend,0.05,0.95),EnsureRange(N.A.Y+DY/3+DX*Bend,0.08,0.92));
      N.C:=GamePoint(EnsureRange(N.A.X+DX*2/3-DY*Bend,0.05,0.95),EnsureRange(N.A.Y+DY*2/3+DX*Bend,0.08,0.92));
      Result.FNotes[K]:=N;Inc(K);Previous:=N.D;
    end;
    SetLength(Result.FNotes,K);Result.Validate;
  except Result.Free;raise;
  end;
end;

procedure TLegacyGamePlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var Root:TJSONObject;A,R:TJSONArray;E:TRhythmHit;N:TGameNote;
  procedure Add(V:Double);
  begin R.AddElement(ExactJSON(V));end;
begin
  Validate;
  if (Audio=nil) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsRhythmGame,0) or (Ref.Version<>1) then raise Exception.Create('RhythmGame save identity');
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','rhythm-game');Root.AddPair('version',TJSONNumber.Create(1));
    Root.AddPair('key',Ref.Key);Root.AddPair('source',Ref.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));Root.AddPair('policy','cursor-marks-bezier-v1');AddPreparedAudio(Root,Audio);
    Root.AddPair('durationExact',ExactJSON(FDuration));Root.AddPair('soundEndExact',ExactJSON(FSoundEnd));
    Root.AddPair('end',ExactJSON(FEnd));Root.AddPair('excluded',TJSONNumber.Create(FExcluded));
    A:=TJSONArray.Create;Root.AddPair('events',A);
    for E in FEvents do begin R:=TJSONArray.Create;A.AddElement(R);Add(E.Time);Add(E.Strength);end;
    A:=TJSONArray.Create;Root.AddPair('notes',A);
    for N in FNotes do begin R:=TJSONArray.Create;A.AddElement(R);
      Add(N.Time);Add(N.Appear);Add(N.Start);Add(N.Strength);R.Add(N.Source);R.Add(N.Hue);R.Add(N.Mode);R.Add(N.Chain);R.Add(Ord(N.Roll));
      Add(N.A.X);Add(N.A.Y);Add(N.B.X);Add(N.B.Y);Add(N.C.X);Add(N.C.Y);Add(N.D.X);Add(N.D.Y);
    end;
    WritePreparedData(Root,Ref);
  finally Root.Free;end;
end;

procedure RestoreEvents(Root:TJSONObject;Audio:TRhythmAudio);
var A,R:TJSONArray;I:Integer;T,S,Last,D,G:Double;
begin
  if Root.GetValue<string>('policy','')<>'cursor-marks-bezier-v1' then raise Exception.Create('RhythmGame policy');
  D:=ExactValue(Root.GetValue('durationExact'));G:=ExactValue(Root.GetValue('soundEndExact'));
  if not Finite(D) or not Finite(G) or (Abs(D-Audio.Duration)>1E-7) or (Abs(G-Audio.SoundEnd)>1E-7) or (G<0) or (G>D) then raise Exception.Create('RhythmGame audio identity');
  Audio.Duration:=D;Audio.SoundEnd:=G;A:=Root.GetValue<TJSONArray>('events');
  if (A=nil) or (A.Count<>Length(Audio.Hits)) or (A.Count>GAME_MAX_NOTES) then raise Exception.Create('RhythmGame audio events');
  Last:=-1;
  for I:=0 to A.Count-1 do begin R:=A.Items[I] as TJSONArray;
    if R.Count<>2 then raise Exception.Create('RhythmGame event row');
    T:=ExactValue(R.Items[0]);S:=ExactValue(R.Items[1]);
    if not Finite(T) or not Finite(S) or (T<0) or (T<Last) or (T>D+0.011) then raise Exception.Create('RhythmGame stored accent');
    Audio.Hits[I].Time:=T;Audio.Hits[I].Strength:=S;Last:=T;
  end;
end;

class function TLegacyGamePlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin Root:=ReadPreparedData(Ref,rsRhythmGame,Direction);
  try Result:=PreparedAudio(Root,Ref,Source);
    try RestoreEvents(Root,Result);except Result.Free;raise;end;
  finally Root.Free;end;
end;

class function TLegacyGamePlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TLegacyGamePlan;
var Root:TJSONObject;A,R:TJSONArray;I,J:Integer;N:TGameNote;Meta:TRhythmAudio;
  function Num(Index:Integer):Double;
  begin Result:=ExactValue(R.Items[Index]);if not Finite(Result) then raise Exception.Create('RhythmGame nonfinite row');end;
  function Int(Index:Integer):Integer;
  var Value:Double;
  begin Value:=R.Items[Index].GetValue<Double>;if not Finite(Value) then raise Exception.Create('RhythmGame nonfinite integer');if (Abs(Value)>MaxInt) or (Value<>Trunc(Value)) then raise Exception.Create('RhythmGame integer');Result:=Round(Value);end;
begin
  if (Audio=nil) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsRhythmGame,0) then raise Exception.Create('RhythmGame load identity');
  Root:=ReadPreparedData(Ref,rsRhythmGame,Direction);
  try Result:=TLegacyGamePlan.Create;
    try
      // 保存軌道を読むだけで再計画しない。借用Audioも変更しない。
      Meta:=TRhythmAudio.Create;
      try Meta.Duration:=Audio.Duration;Meta.SoundEnd:=Audio.SoundEnd;SetLength(Meta.Hits,Length(Audio.Hits));
        RestoreEvents(Root,Meta);Result.FEvents:=Copy(Meta.Hits);
      finally Meta.Free;end;
      for I:=0 to High(Result.FEvents) do
        if (Result.FEvents[I].Time<>Audio.Hits[I].Time) or (Result.FEvents[I].Strength<>Audio.Hits[I].Strength) then raise Exception.Create('RhythmGame supplied audio mismatch');
      Result.FDuration:=Audio.Duration;Result.FSoundEnd:=Audio.SoundEnd;Result.FEnd:=ExactValue(Root.GetValue('end'));Result.FExcluded:=Root.GetValue<Integer>('excluded');
      A:=Root.GetValue<TJSONArray>('notes');if (A=nil) or (A.Count>GAME_MAX_NOTES) then raise Exception.Create('RhythmGame notes array');SetLength(Result.FNotes,A.Count);
      for I:=0 to A.Count-1 do begin R:=A.Items[I] as TJSONArray;if R.Count<>17 then raise Exception.Create('RhythmGame note width');
        N.Time:=Num(0);N.Appear:=Num(1);N.Start:=Num(2);N.Strength:=Num(3);N.Source:=Int(4);N.Hue:=Int(5);N.Mode:=Int(6);N.Chain:=Int(7);J:=Int(8);
        if not (J in [0,1]) then raise Exception.Create('RhythmGame roll flag');N.Roll:=J=1;
        N.A:=GamePoint(Num(9),Num(10));N.B:=GamePoint(Num(11),Num(12));N.C:=GamePoint(Num(13),Num(14));N.D:=GamePoint(Num(15),Num(16));Result.FNotes[I]:=N;
      end;
      Result.Validate;
    except Result.Free;raise;end;
  finally Root.Free;end;
end;
end.
