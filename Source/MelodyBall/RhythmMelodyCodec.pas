unit RhythmMelodyCodec;
// 拍節推定と反復禁止の区間を含む計画v7。音源情報と力学列は共通32MB枠へ圧縮する。
// 共通I/OのSHAと音源照合を利用し、描画中の解析や物理積分を必要としない。
interface
uses RhythmMelodyPlan,RhythmAudio,RhythmPlanRef;
// Plan/Audioは借用。保存ファイルのSHAだけをRefへ書き戻す。
procedure SaveMelodyPlan(Plan:TMelodyPlan; Audio:TRhythmAudio; var Ref:TRhythmPlanRef);
// 戻り値は呼出側所有。不正な版・支持解・元音参照は例外にする。
function LoadMelodyPlan(const Ref:TRhythmPlanRef; Audio:TRhythmAudio; Direction:Integer):TMelodyPlan;
// PCMを読み込まず、保存済みの音源情報を呼出側所有で返す。
function LoadMelodyAudio(const Ref:TRhythmPlanRef; const Source:string; Direction:Integer):TRhythmAudio;
implementation
uses System.SysUtils,System.Classes,System.JSON,System.Math,System.NetEncoding,System.ZLib,
  System.Generics.Collections,RhythmPreparedData,RhythmStyles;
procedure Need(B:Boolean);
begin if not B then raise EConvertError.Create('メロディボールの物理計画が不正です'); end;
procedure PackData(Root,Data:TJSONObject; const Name:string);
var Raw,PackedBytes:TBytes; Stream:TMemoryStream; Zip:TCompressionStream;
begin
  Raw:=TEncoding.UTF8.GetBytes(Data.ToJSON); Need(Length(Raw)<=192*1024*1024);
  Stream:=TMemoryStream.Create;
  try
    Zip:=TCompressionStream.Create(clMax,Stream);
    try if Length(Raw)>0 then Zip.WriteBuffer(Raw[0],Length(Raw)); finally Zip.Free; end;
    Need(Stream.Size<24*1024*1024); SetLength(PackedBytes,Stream.Size);
    if Stream.Size>0 then Move(Stream.Memory^,PackedBytes[0],Stream.Size);
    Root.AddPair(Name+'Bytes',TJSONNumber.Create(Length(Raw)));
    Root.AddPair(Name,TNetEncoding.Base64.EncodeBytesToString(PackedBytes));
  finally Stream.Free; end;
end;
function UnpackData(Root:TJSONObject; const Name:string):TJSONObject;
var Raw,PackedBytes:TBytes; Stream:TBytesStream; Zip:TDecompressionStream; Count:Integer; Extra:Byte; V:TJSONValue;
begin
  Need(Root.GetValue(Name) is TJSONString);
  Count:=Root.GetValue<Integer>(Name+'Bytes',0); Need(InRange(Count,2,192*1024*1024));
  PackedBytes:=TNetEncoding.Base64.DecodeStringToBytes(Root.GetValue<string>(Name)); SetLength(Raw,Count);
  Stream:=TBytesStream.Create(PackedBytes);
  try
    Zip:=TDecompressionStream.Create(Stream);
    try Zip.ReadBuffer(Raw[0],Count); Need(Zip.Read(Extra,1)=0); finally Zip.Free; end;
  finally Stream.Free; end;
  V:=TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Raw));
  if not (V is TJSONObject) then begin V.Free; Need(False); end;
  Result:=TJSONObject(V);
end;
procedure SaveMelodyPlan(Plan:TMelodyPlan; Audio:TRhythmAudio; var Ref:TRhythmPlanRef);
var O,Physics,AudioInfo:TJSONObject; Rows,Row:TJSONArray; S:TMelodySpan; B:TMelodyBar; Bytes:TBytes;
  procedure D(V:Double);
  begin Row.AddElement(PreparedExact(V)); end;
begin
  Plan.Validate; O:=TJSONObject.Create; Physics:=TJSONObject.Create; AudioInfo:=TJSONObject.Create;
  try
    O.AddPair('schema',TJSONNumber.Create(1)); O.AddPair('style',StyleId(rsMelodyBall));
    O.AddPair('version',TJSONNumber.Create(Ref.Version)); O.AddPair('key',Ref.Key); O.AddPair('source',Ref.SourceKey);
    O.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity)); O.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(AudioInfo,Audio); PackData(O,AudioInfo,'audioData');
    O.AddPair('duration',PreparedExact(Plan.Duration)); O.AddPair('endTime',PreparedExact(Plan.EndTime));
    O.AddPair('beat',PreparedExact(Plan.Beat)); O.AddPair('beatOrigin',PreparedExact(Plan.BeatOrigin));
    O.AddPair('beatConfidence',PreparedExact(Plan.BeatConfidence)); O.AddPair('sectionLength',PreparedExact(Plan.SectionLength));
    O.AddPair('meter',TJSONNumber.Create(Plan.Meter));
    Rows:=TJSONArray.Create; Physics.AddPair('sections',Rows);
    for var Section in Plan.Sections do begin
      Row:=TJSONArray.Create; Rows.AddElement(Row); D(Section.Start); D(Section.Finish);
      Row.Add(Ord(Section.Kind)); Row.Add(Section.SourceCount);
    end;
    Rows:=TJSONArray.Create; Physics.AddPair('spans',Rows);
    for S in Plan.Spans do begin
      Row:=TJSONArray.Create; Rows.AddElement(Row); D(S.Start); D(S.Finish); D(S.A.X); D(S.A.Y); D(S.B.X); D(S.B.Y);
      D(S.Theta); D(S.Curvature); D(S.Speed); D(S.Drag); D(S.Spin); D(S.Launch.X); D(S.Launch.Y); D(S.SpringOmega);
      Row.Add(Ord(S.Motion)); Row.Add(Ord(S.Kind));
      SetLength(Bytes,Length(S.Knots)*SizeOf(TMelodyKnot));
      if Length(Bytes)>0 then Move(S.Knots[0],Bytes[0],Length(Bytes));
      Row.Add(TNetEncoding.Base64.EncodeBytesToString(Bytes));
      Row.Add(S.Direction);
    end;
    Rows:=TJSONArray.Create; Physics.AddPair('bars',Rows);
    for B in Plan.Bars do begin
      Row:=TJSONArray.Create; Rows.AddElement(Row); D(B.Time); D(B.Contact.X); D(B.Contact.Y); D(B.Power);
      D(B.Left); D(B.Right); D(B.Top); D(B.Restitution);
      Row.Add(Ord(B.Kind)); Row.Add(B.Source); Row.Add(B.Span); Row.Add(Ord(B.Terminal));
      Row.Add(Ord(B.Strike)); D(B.Trigger); D(B.AngularSpeed); Row.Add(B.TriggerSpan); D(B.Pivot.X); D(B.Pivot.Y);
      D(B.MechanismScale); D(B.RotorRatio);
    end;
    PackData(O,Physics,'physics');
    Need(Length(TEncoding.UTF8.GetBytes(O.ToJSON))<=32*1024*1024); WritePreparedData(O,Ref);
  finally AudioInfo.Free; Physics.Free; O.Free; end;
end;
function LoadMelodyAudio(const Ref:TRhythmPlanRef; const Source:string; Direction:Integer):TRhythmAudio;
var O,AudioInfo:TJSONObject;
begin
  O:=ReadPreparedData(Ref,rsMelodyBall,Direction); AudioInfo:=nil;
  try AudioInfo:=UnpackData(O,'audioData'); Result:=PreparedAudio(AudioInfo,Ref,Source);
  finally AudioInfo.Free; O.Free; end;
end;
function LoadMelodyPlan(const Ref:TRhythmPlanRef; Audio:TRhythmAudio; Direction:Integer):TMelodyPlan;
var O,Physics:TJSONObject; Rows,Row:TJSONArray; I:Integer; Bytes:TBytes;
  function D(N:Integer):Double;
  begin Result:=ReadPreparedExact(Row.Items[N]); Need(Abs(Result)<1E7); end;
  function N(Index,Lo,Hi:Integer):Integer;
  begin Need((Row.Items[Index] is TJSONNumber) and TryStrToInt(Row.Items[Index].Value,Result)); Need(InRange(Result,Lo,Hi)); end;
  procedure SelectRows(const Name:string; MinCount,MaxCount:Integer);
  begin Need(Physics.GetValue(Name) is TJSONArray); Rows:=TJSONArray(Physics.GetValue(Name)); Need(InRange(Rows.Count,MinCount,MaxCount)); end;
  procedure SelectRow(Index,Count:Integer);
  begin Need(Rows.Items[Index] is TJSONArray); Row:=TJSONArray(Rows.Items[Index]); Need(Row.Count=Count); end;
begin
  Need((Audio<>nil) and Audio.HasHitDetails and Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsMelodyBall));
  O:=ReadPreparedData(Ref,rsMelodyBall,Direction); Physics:=nil;
  try
    Physics:=UnpackData(O,'physics');
    Result:=TMelodyPlan.Create;
    try
      Result.Duration:=ReadPreparedExact(O.GetValue('duration')); Need(Abs(Result.Duration-Audio.Duration)<1E-8);
      Result.EndTime:=ReadPreparedExact(O.GetValue('endTime'));
      Result.Beat:=ReadPreparedExact(O.GetValue('beat')); Result.BeatOrigin:=ReadPreparedExact(O.GetValue('beatOrigin'));
      Result.BeatConfidence:=ReadPreparedExact(O.GetValue('beatConfidence'));
      Result.SectionLength:=ReadPreparedExact(O.GetValue('sectionLength')); Result.Meter:=O.GetValue<Integer>('meter',-1);
      SelectRows('sections',1,1024); SetLength(Result.Sections,Rows.Count);
      for I:=0 to Rows.Count-1 do begin
        SelectRow(I,4); Result.Sections[I].Start:=D(0); Result.Sections[I].Finish:=D(1);
        Result.Sections[I].Kind:=TMelodySectionKind(N(2,0,Ord(High(TMelodySectionKind))));
        Result.Sections[I].SourceCount:=N(3,0,100000);
      end;
      SelectRows('spans',1,300000); SetLength(Result.Spans,Rows.Count);
      for I:=0 to Rows.Count-1 do begin
        SelectRow(I,18); Result.Spans[I].Start:=D(0); Result.Spans[I].Finish:=D(1);
        Result.Spans[I].A:=MelodyPoint(D(2),D(3)); Result.Spans[I].B:=MelodyPoint(D(4),D(5));
        Result.Spans[I].Theta:=D(6); Result.Spans[I].Curvature:=D(7); Result.Spans[I].Speed:=D(8);
        Result.Spans[I].Drag:=D(9); Result.Spans[I].Spin:=D(10); Result.Spans[I].Launch:=MelodyPoint(D(11),D(12));
        Result.Spans[I].SpringOmega:=D(13);
        Result.Spans[I].Motion:=TMelodyMotion(N(14,0,3)); Result.Spans[I].Kind:=TMelodyCourse(N(15,0,Ord(High(TMelodyCourse))));
        Need((Row.Items[16] is TJSONString) and (Length(Row.Items[16].Value)<40000));
        Bytes:=TNetEncoding.Base64.DecodeStringToBytes(Row.Items[16].Value);
        Need((Length(Bytes) mod SizeOf(TMelodyKnot)=0) and (Length(Bytes)<=1024*SizeOf(TMelodyKnot)));
        SetLength(Result.Spans[I].Knots,Length(Bytes) div SizeOf(TMelodyKnot));
        if Length(Bytes)>0 then Move(Bytes[0],Result.Spans[I].Knots[0],Length(Bytes));
        Result.Spans[I].Direction:=N(17,-1,1); Need(Result.Spans[I].Direction<>0);
      end;
      SelectRows('bars',0,100000); SetLength(Result.Bars,Rows.Count);
      for I:=0 to Rows.Count-1 do begin
        SelectRow(I,20); Result.Bars[I].Time:=D(0); Result.Bars[I].Contact:=MelodyPoint(D(1),D(2));
        Result.Bars[I].Power:=D(3); Result.Bars[I].Left:=D(4); Result.Bars[I].Right:=D(5);
        Result.Bars[I].Top:=D(6); Result.Bars[I].Restitution:=D(7);
        Result.Bars[I].Kind:=TMelodyBarKind(N(8,0,Ord(High(TMelodyBarKind)))); Result.Bars[I].Source:=N(9,0,High(Audio.Hits));
        Result.Bars[I].Span:=N(10,0,High(Result.Spans)); Result.Bars[I].Terminal:=N(11,0,1)=1;
        Result.Bars[I].Strike:=TMelodyStrike(N(12,0,Ord(High(TMelodyStrike))));
        Result.Bars[I].Trigger:=D(13); Result.Bars[I].AngularSpeed:=D(14);
        Result.Bars[I].TriggerSpan:=N(15,0,High(Result.Spans)); Result.Bars[I].Pivot:=MelodyPoint(D(16),D(17));
        Result.Bars[I].MechanismScale:=D(18); Result.Bars[I].RotorRatio:=D(19);
        Need(Result.Bars[I].Time=Audio.Hits[Result.Bars[I].Source].Time);
      end;
      Result.Validate; Result.IndexGeometry;
    except Result.Free; raise; end;
  finally Physics.Free; O.Free; end;
end;
end.
