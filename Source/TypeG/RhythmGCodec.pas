unit RhythmGCodec;
// Type.G計画の不変スナップショット。共通I/Oのハッシュ照合とbinary64表現を使う。
interface
uses RhythmGPlan, RhythmAudio, RhythmPlanRef;
procedure SaveGPlan(Plan: TGPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
function LoadGPlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TGPlan;
function LoadGAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
// 編集時だけ新しいIDを発行し、以前のプロジェクトが参照する構成を上書きしない。
procedure SaveGEdit(Plan: TGPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
implementation
uses System.SysUtils, System.JSON, System.Math, System.Hash, System.Generics.Collections, RhythmPreparedData, RhythmStyles;
procedure Need(B: Boolean; const Why: string);
begin if not B then raise EConvertError.Create('Type.G 保存計画: '+Why); end;
function IntAt(Row: TJSONArray; I,Lo,Hi: Integer): Integer;
begin
  Need((Row.Items[I] is TJSONNumber) and TryStrToInt(Row.Items[I].Value,Result),'整数');
  Need(InRange(Result,Lo,Hi),'値の範囲');
end;
procedure SaveGPlan(Plan: TGPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
var Root: TJSONObject; Rows,Row: TJSONArray; S: TGScene; C: TGCue;
begin
  Plan.Validate; Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1)); Root.AddPair('style',StyleId(rsTypeG));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version)); Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey); Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction)); AddPreparedAudio(Root,Audio);
    Root.AddPair('duration',PreparedExact(Plan.Duration)); Root.AddPair('beat',PreparedExact(Plan.Beat));
    Root.AddPair('origin',PreparedExact(Plan.Origin)); Root.AddPair('transitions',TJSONBool.Create(Plan.Transitions));
    Rows:=TJSONArray.Create; Root.AddPair('scenes',Rows);
    for S in Plan.Scenes do begin
      Row:=TJSONArray.Create; Rows.AddElement(Row); Row.AddElement(PreparedExact(S.Start));
      Row.AddElement(PreparedExact(S.Finish)); Row.AddElement(PreparedExact(S.ActionStart));
      Row.AddElement(PreparedExact(S.ActionEnd)); Row.Add(S.Game); Row.Add(S.Transition);
    end;
    Rows:=TJSONArray.Create; Root.AddPair('cues',Rows);
    for C in Plan.Cues do begin
      Row:=TJSONArray.Create; Rows.AddElement(Row); Row.AddElement(PreparedExact(C.Time));
      Row.AddElement(PreparedExact(C.Lead)); Row.AddElement(PreparedExact(C.Recover));
      Row.AddElement(PreparedExact(C.Power)); Row.Add(C.Scene); Row.Add(C.Action); Row.Add(C.Source);
    end;
    WritePreparedData(Root,Ref);
  finally Root.Free; end;
end;
procedure SaveGEdit(Plan: TGPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
var Id: TGUID; NewRef: TRhythmPlanRef; Verified: TGPlan;
begin
  if CreateGUID(Id)<>0 then raise Exception.Create('Type.G 編集IDを作成できません');
  NewRef:=NewPlanRef(Audio.Key,Audio.Sensitivity,Ref.Direction,rsTypeG,0,Ref.AudioDensity,
    THashSHA2.GetHashString(GUIDToString(Id)));
  NewRef.SourceRevision:=Audio.SourceRevision; SaveGPlan(Plan,Audio,NewRef);
  Verified:=LoadGPlan(NewRef,Audio,NewRef.Direction);
  Verified.Free; Ref:=NewRef;
end;
function LoadGAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
var Root: TJSONObject;
begin
  Root:=ReadPreparedData(Ref,rsTypeG,Direction);
  try Result:=PreparedAudio(Root,Ref,Source); finally Root.Free; end;
end;
function LoadGPlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TGPlan;
var Root: TJSONObject; V: TJSONValue; Rows,Row: TJSONArray; I: Integer; C: TGCue; S: TGScene;
begin
  Need((Audio<>nil) and Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsTypeG,0),'音源参照');
  Root:=ReadPreparedData(Ref,rsTypeG,Direction);
  try
    Result:=TGPlan.Create;
    try
      Result.Duration:=ReadPreparedExact(Root.GetValue('duration'));
      Need(Abs(Result.Duration-Audio.Duration)<1E-8,'音源長');
      Result.Beat:=ReadPreparedExact(Root.GetValue('beat')); Result.Origin:=ReadPreparedExact(Root.GetValue('origin'));
      Need(Root.GetValue('transitions') is TJSONBool,'トランジション');
      Result.Transitions:=Root.GetValue<Boolean>('transitions');
      V:=Root.GetValue('scenes'); Need(V is TJSONArray,'シーン'); Rows:=TJSONArray(V);
      Need(InRange(Rows.Count,1,2048),'シーン数'); SetLength(Result.Scenes,Rows.Count);
      for I:=0 to Rows.Count-1 do begin
        Need(Rows.Items[I] is TJSONArray,'シーン行'); Row:=TJSONArray(Rows.Items[I]); Need(Row.Count=6,'シーン項目');
        S.Start:=ReadPreparedExact(Row.Items[0]); S.Finish:=ReadPreparedExact(Row.Items[1]);
        S.ActionStart:=ReadPreparedExact(Row.Items[2]); S.ActionEnd:=ReadPreparedExact(Row.Items[3]);
        S.Game:=IntAt(Row,4,0,31); S.Transition:=IntAt(Row,5,0,5); Result.Scenes[I]:=S;
      end;
      V:=Root.GetValue('cues'); Need(V is TJSONArray,'動作'); Rows:=TJSONArray(V);
      Need(Rows.Count<=100000,'動作数'); SetLength(Result.Cues,Rows.Count);
      for I:=0 to Rows.Count-1 do begin
        Need(Rows.Items[I] is TJSONArray,'動作行'); Row:=TJSONArray(Rows.Items[I]); Need(Row.Count=7,'動作項目');
        C.Time:=ReadPreparedExact(Row.Items[0]); C.Lead:=ReadPreparedExact(Row.Items[1]);
        C.Recover:=ReadPreparedExact(Row.Items[2]); C.Power:=ReadPreparedExact(Row.Items[3]);
        C.Scene:=IntAt(Row,4,0,High(Result.Scenes)); C.Action:=IntAt(Row,5,0,2);
        C.Source:=IntAt(Row,6,0,High(Audio.Hits));
        Need(Audio.HasHitDetails and (C.Time=Audio.Hits[C.Source].Time),'元の実音時刻');
        Result.Cues[I]:=C;
      end;
      Result.Validate;
    except Result.Free; raise; end;
  finally Root.Free; end;
end;
end.
