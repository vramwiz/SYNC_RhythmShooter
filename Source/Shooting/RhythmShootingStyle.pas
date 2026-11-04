unit RhythmShootingStyle;
// シューティング専用の生成・準備・復元アダプター。描画/物理本体と保存形式は変更しない。
interface
uses RhythmStyleOps;
function ShootingOperations:TStyleOperations;
implementation
uses System.SysUtils,System.JSON,System.Generics.Collections,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmAnimation,RhythmImageBank,
  RhythmShootingScene,RhythmShootingAssets,RhythmPreparedData;
const SelectionPolicy='shooting-selection-v1';
function CreateScene:TAnimationScene;
begin Result:=TShootingAnimation.Create;end;
procedure SetReference(Scene:TAnimationScene;const Ref:TRhythmPlanRef);
begin end;
procedure SetAudio(Scene:TAnimationScene;Audio:TRhythmAudio;BossFrequency:Integer);
begin if Audio<>nil then Audio.SetBossFrequency(BossFrequency);TShootingAnimation(Scene).Audio:=Audio;end;
function CreateImages:TAnimationImageBank;
begin Result:=TShootingImageBank.Create;end;
function ReadSelection(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TArray<TRhythmHit>;
var Root:TJSONObject;Rows,Row:TJSONArray;I:Integer;Last:Double;Hit:TRhythmHit;
begin
  Root:=ReadPreparedData(Ref,rsShooting,Direction);
  try
    Rows:=Root.GetValue<TJSONArray>('hits');
    if (Root.GetValue<string>('policy','')<>SelectionPolicy) or (Root.GetValue<Integer>('density',0)<>Ref.AudioDensity) or
      (Rows=nil) or (Rows.Count>100000) or (Audio.Key<>Ref.SourceKey) or
      (Audio.SourceRevision<>Ref.SourceRevision) then raise EConvertError.Create('Invalid shooting selection');
    SetLength(Result,Rows.Count);
    Last:=-1;
    for I:=0 to Rows.Count-1 do begin
      Row:=Rows.Items[I] as TJSONArray;
      if Row.Count<>4 then raise EConvertError.Create('Invalid shooting accent row');
      Hit.Time:=ReadPreparedExact(Row.Items[0]);
      Hit.Strength:=ReadPreparedExact(Row.Items[1]);
      Hit.Lane:=ReadPreparedExact(Row.Items[2]);
      Hit.Flight:=ReadPreparedExact(Row.Items[3]);
      if (Hit.Time<0) or (Hit.Time<Last) or (Hit.Time>Audio.Duration+0.011) or (Hit.Strength<0) or
        (Hit.Lane<0) or (Hit.Lane>1) or (Hit.Flight<0) then raise EConvertError.Create('Invalid shooting accent');
      Result[I]:=Hit;
      Last:=Hit.Time;
    end;
  finally
    Root.Free;
  end;
end;

function LoadAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin
  Result:=LoadCachedRhythmAudio(Source,Ref.Sensitivity,False);
  if (Result=nil) or (Ref.AudioDensity=0) then Exit;
  try
    // 従来キャッシュの包絡線と、準備時に保存した選抜済みイベントを組み合わせる。
    Result.SetSelectedHits(ReadSelection(Ref,Result,Direction));
  except
    Result.Free;
    raise;
  end;
end;

procedure SaveSelection(const Context:TStylePrepareContext;var Ref:TRhythmPlanRef);
var Root:TJSONObject;Rows,Row:TJSONArray;Hit:TRhythmHit;
begin
  Context.SetStage(3);
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsShooting));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('density',TJSONNumber.Create(Ref.AudioDensity));
    Root.AddPair('policy',SelectionPolicy);
    Rows:=TJSONArray.Create;
    Root.AddPair('hits',Rows);
    for Hit in Context.Audio.Hits do begin
      Context.CheckCancel;
      Row:=TJSONArray.Create;
      Rows.AddElement(Row);
      Row.AddElement(PreparedExact(Hit.Time));
      Row.AddElement(PreparedExact(Hit.Strength));
      Row.AddElement(PreparedExact(Hit.Lane));
      Row.AddElement(PreparedExact(Hit.Flight));
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
  Context.SetStage(4);
  Context.CheckCancel;
  if Length(ReadSelection(Ref,Context.Audio,Context.Direction))<>Length(Context.Audio.Hits) then
    raise EConvertError.Create('Shooting selection roundtrip');
end;

procedure Prepare(const Context:TStylePrepareContext;var Prepared:TRhythmPlanRef;var PreparedEnd:Double;var PreparedSummary:string);
begin
  if Prepared.AudioDensity<>0 then SaveSelection(Context,Prepared);
  PreparedSummary:=IntToStr(Length(Context.Audio.Hits))+'イベント / ボス'+IntToStr(Context.Audio.BossCount)+' / '+BossFrequencyText(Context.Audio.BossFrequency);
end;
function ShootingOperations:TStyleOperations;
begin Result:=Default(TStyleOperations);Result.UnitName:='RhythmShootingStyle';Result.CreateScene:=CreateScene;
  Result.SetReference:=SetReference;Result.SetAudio:=SetAudio;Result.Prepare:=Prepare;
  Result.LoadAudio:=LoadAudio;Result.CreateImages:=CreateImages;
end;
end.
