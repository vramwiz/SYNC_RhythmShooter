unit RhythmOrbitCodec;
// 宇宙v4/v3/v2をbinary64で保存・復元。版別の候補数を検証し、PCM解析や軌道の再生成はしない。
interface
uses RhythmAudio,RhythmPlanRef,RhythmOrbitTypes;
procedure WriteOrbitData(const Data:TOrbitData;var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
function ReadOrbitData(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TOrbitData;
function ReadOrbitMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
implementation
uses System.SysUtils,System.JSON,System.Math,RhythmPreparedData,RhythmStyles;
function Exact(V:Double):TJSONString;
var Bits:UInt64;
begin Move(V,Bits,8);Result:=TJSONString.Create(IntToHex(Bits,16));end;
function Value(V:TJSONValue):Double;
var Bits:UInt64;
begin
  if not (V is TJSONString) or (Length(V.Value)<>16) or not TryStrToUInt64('$'+V.Value,Bits) then raise Exception.Create('Orbit binary64');
  Move(Bits,Result,8);if not OrbitFinite(Result) then raise Exception.Create('Orbit nonfinite');
end;
procedure WriteOrbitData(const Data:TOrbitData;var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var Root:TJSONObject;A,R:TJSONArray;Info:TJSONObject;E:TRhythmHit;B:TOrbitBody;L:TOrbitLeg;N:TOrbitTap;
  procedure Num(V:Double);
  begin R.AddElement(Exact(V));end;
  procedure Point(const P:TOrbitPoint);
  begin Num(P.X);Num(P.Y);end;
  procedure Row;
  begin R:=TJSONArray.Create;A.AddElement(R);end;
begin
  if (Audio=nil) or (Ref.Version<>Data.Version) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsRhythmGame,Data.Threshold+1+Ord(Data.Version>=3)*100) or
    (Data.Duration<>Audio.Duration) or (Data.SoundEnd<>Audio.SoundEnd) then raise Exception.Create('Orbit save identity');
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','rhythm-game');Root.AddPair('version',TJSONNumber.Create(Data.Version));
    Root.AddPair('key',Ref.Key);Root.AddPair('source',Ref.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));Root.AddPair('policy','planet-orbit-v'+IntToStr(Data.Version));AddPreparedAudio(Root,Audio);
    // v3 keeps a private dense event set; the source audio/cache remains classic.
    Info:=Root.GetValue<TJSONObject>('audio');Info.RemovePair('events').Free;Info.AddPair('events',TJSONNumber.Create(Length(Data.Events)));
    if Data.Version>=3 then begin Root.AddPair('intro',Exact(Data.IntroFinish));Root.AddPair('depart',Exact(Data.DepartStart));
      Root.AddPair('arrival',Exact(Data.DepartFinish));Root.AddPair('clear',Exact(Data.ClearTime));end;
    Root.AddPair('durationExact',Exact(Data.Duration));Root.AddPair('soundEndExact',Exact(Data.SoundEnd));Root.AddPair('end',Exact(Data.EndTime));
    Root.AddPair('threshold',TJSONNumber.Create(Data.Threshold));Root.AddPair('weak',TJSONNumber.Create(Data.Weak));Root.AddPair('tail',TJSONNumber.Create(Data.Tail));
    A:=TJSONArray.Create;Root.AddPair('events',A);
    for E in Data.Events do begin Row;Num(E.Time);Num(E.Strength);end;
    A:=TJSONArray.Create;Root.AddPair('bodies',A);
    for B in Data.Bodies do begin Row;Point(B.Center);Num(B.Show);Num(B.Entry);Num(B.Exit);Num(B.Clear);Num(B.Radius);
      Num(B.RX);Num(B.RY);Num(B.Rotation);Num(B.Phase);Num(B.Speed);R.Add(B.Hue);end;
    A:=TJSONArray.Create;Root.AddPair('legs',A);
    for L in Data.Legs do begin Row;Num(L.Start);Num(L.Finish);R.Add(L.FromBody);R.Add(L.ToBody);Point(L.A);Point(L.B);Point(L.C);Point(L.D);if Data.Version>=3 then R.Add(L.Kind);end;
    A:=TJSONArray.Create;Root.AddPair('taps',A);
    for N in Data.Taps do begin Row;Num(N.Time);Num(N.Appear);Num(N.Strength);R.Add(N.Source);R.Add(N.Leg);R.Add(N.Chain);Point(N.P);end;
    WritePreparedData(Root,Ref);
  finally Root.Free;end;
end;
procedure Restore(Root:TJSONObject;Audio:TRhythmAudio);
var A,R:TJSONArray;I:Integer;T,S,Last,D,G:Double;
begin
  if Root.GetValue<string>('policy','')<>'planet-orbit-v'+IntToStr(Root.GetValue<Integer>('version')) then raise Exception.Create('Orbit policy');
  D:=Value(Root.GetValue('durationExact'));G:=Value(Root.GetValue('soundEndExact'));
  if (Abs(D-Audio.Duration)>1E-7) or (Abs(G-Audio.SoundEnd)>1E-7) or (D<=0) or (G<0) or (G>D) then raise Exception.Create('Orbit metadata identity');
  Audio.Duration:=D;Audio.SoundEnd:=G;A:=Root.GetValue<TJSONArray>('events');
  if (A=nil) or ((Root.GetValue<Integer>('version')=2) and (A.Count<>Length(Audio.Hits))) or (A.Count>ORBIT_MAX_EVENTS) or (Root.GetValue<TJSONObject>('audio').GetValue<Integer>('events',-1)<>A.Count) then raise Exception.Create('Orbit metadata events');
  SetLength(Audio.Hits,A.Count);Last:=-1;
  for I:=0 to A.Count-1 do begin R:=A.Items[I] as TJSONArray;
    if R.Count<>2 then raise Exception.Create('Orbit event row');T:=Value(R.Items[0]);S:=Value(R.Items[1]);
    if (T<0) or (T<Last) or (T>D+0.011) then raise Exception.Create('Orbit event order');
    Audio.Hits[I].Time:=T;Audio.Hits[I].Strength:=S;Last:=T;
  end;
end;
function ReadOrbitMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin
  if not (Ref.Version in [2,3,4]) then raise Exception.Create('Orbit metadata version');Root:=ReadPreparedData(Ref,rsRhythmGame,Direction);
  try
    if (Root.GetValue<Integer>('threshold',-1000)+1+Ord(Ref.Version>=3)*100<>Ref.Variant) or (Ref.Variant<1) or (Ref.Variant>101+Ord(Ref.Version>=3)*100) then raise Exception.Create('Orbit metadata threshold');
    Result:=PreparedAudio(Root,Ref,Source);
    try Restore(Root,Result);except Result.Free;raise;end;
  finally Root.Free;end;
end;
function ReadOrbitData(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TOrbitData;
var Root:TJSONObject;A,R:TJSONArray;I:Integer;Meta:TRhythmAudio;B:TOrbitBody;L:TOrbitLeg;N:TOrbitTap;
  function Rows(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Orbit rows '+Name);end;
  procedure Row(Index,Width:Integer);
  begin R:=A.Items[Index] as TJSONArray;if R.Count<>Width then raise Exception.Create('Orbit row width');end;
  function Num(Index:Integer):Double;
  begin Result:=Value(R.Items[Index]);end;
  function Int(Index:Integer):Integer;
  var V:Double;
  begin V:=R.Items[Index].GetValue<Double>;if not OrbitFinite(V) or (Abs(V)>MaxInt) or (V<>Trunc(V)) then raise Exception.Create('Orbit integer');Result:=Round(V);end;
  function Point(Index:Integer):TOrbitPoint;
  begin Result:=OrbitPoint(Num(Index),Num(Index+1));end;
begin
  Result:=Default(TOrbitData);Result.Version:=Ref.Version;
  if (Audio=nil) or not (Ref.Version in [2,3,4]) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsRhythmGame,Ref.Variant) then raise Exception.Create('Orbit load identity');
  Root:=ReadPreparedData(Ref,rsRhythmGame,Direction);
  try
    Meta:=TRhythmAudio.Create;
    try Meta.Duration:=Audio.Duration;Meta.SoundEnd:=Audio.SoundEnd;SetLength(Meta.Hits,Length(Audio.Hits));Restore(Root,Meta);
      Result.Events:=Copy(Meta.Hits);Result.Duration:=Meta.Duration;Result.SoundEnd:=Meta.SoundEnd;
    finally Meta.Free;end;
    if Ref.Version=2 then for I:=0 to High(Result.Events) do if (Result.Events[I].Time<>Audio.Hits[I].Time) or (Result.Events[I].Strength<>Audio.Hits[I].Strength) then raise Exception.Create('Orbit supplied audio differs');
    Result.EndTime:=Value(Root.GetValue('end'));Result.Threshold:=Root.GetValue<Integer>('threshold');
    if Result.Threshold+1+Ord(Ref.Version>=3)*100<>Ref.Variant then raise Exception.Create('Orbit threshold identity');
    if Ref.Version>=3 then begin Result.IntroFinish:=Value(Root.GetValue('intro'));Result.DepartStart:=Value(Root.GetValue('depart'));
      Result.DepartFinish:=Value(Root.GetValue('arrival'));Result.ClearTime:=Value(Root.GetValue('clear'));end;
    Result.Weak:=Root.GetValue<Integer>('weak');Result.Tail:=Root.GetValue<Integer>('tail');
    A:=Rows('bodies',ORBIT_MAX_BODIES);SetLength(Result.Bodies,A.Count);
    for I:=0 to A.Count-1 do begin Row(I,13);B.Center:=Point(0);B.Show:=Num(2);B.Entry:=Num(3);B.Exit:=Num(4);B.Clear:=Num(5);
      B.Radius:=Num(6);B.RX:=Num(7);B.RY:=Num(8);B.Rotation:=Num(9);B.Phase:=Num(10);B.Speed:=Num(11);B.Hue:=Int(12);Result.Bodies[I]:=B;end;
    A:=Rows('legs',2*ORBIT_MAX_BODIES+3);SetLength(Result.Legs,A.Count);
    for I:=0 to A.Count-1 do begin Row(I,12+Ord(Ref.Version>=3));L.Start:=Num(0);L.Finish:=Num(1);L.FromBody:=Int(2);L.ToBody:=Int(3);L.A:=Point(4);L.B:=Point(6);L.C:=Point(8);L.D:=Point(10);L.Kind:=Ord(L.FromBody<>L.ToBody);if Ref.Version>=3 then L.Kind:=Int(12);Result.Legs[I]:=L;end;
    A:=Rows('taps',ORBIT_MAX_EVENTS);SetLength(Result.Taps,A.Count);
    for I:=0 to A.Count-1 do begin Row(I,8);N.Time:=Num(0);N.Appear:=Num(1);N.Strength:=Num(2);N.Source:=Int(3);N.Leg:=Int(4);N.Chain:=Int(5);N.P:=Point(6);Result.Taps[I]:=N;end;
  finally Root.Free;end;
end;
end.
