unit RhythmCannonCodec;
// 共通の準備キャッシュへ秒を正確に保存し、PCMや音解析なしで状態を再構成する。
interface

uses RhythmAudio,RhythmPlanRef,RhythmCannonPlan;

procedure SaveCannonPlan(Plan:TCannonPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
function LoadCannonPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TCannonPlan;
function LoadCannonAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;

implementation

uses System.JSON,System.SysUtils,System.Math,System.Generics.Collections,RhythmPreparedData,RhythmStyles,
  RhythmCannonTargets;

procedure Require(Valid:Boolean;const Field:string);
begin
  if not Valid then raise EConvertError.Create('クラッシュキャノンの保存計画が不正です。'+Field);
end;

function ExactDuration(Root:TJSONObject;AudioDuration:Double):Double;
begin
  Result:=ReadPreparedExact(Root.GetValue('duration'));
  Require((Result>0) and (Abs(Result-AudioDuration)<1E-8),'音源長');
end;

procedure SaveCannonPlan(Plan:TCannonPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
var Root,Section:TJSONObject; Stages,Cues,Row:TJSONArray; Stage:TCannonStage; Cue:TCannonCue;
begin
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsCrashCannon));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root,Audio);
    Root.AddPair('duration',PreparedExact(Plan.Duration));
    Stages:=TJSONArray.Create;
    Root.AddPair('stages',Stages);
    for Stage in Plan.Stages do begin
      Section:=TJSONObject.Create;
      Stages.AddElement(Section);
      Section.AddPair('start',PreparedExact(Stage.Start));
      Section.AddPair('stop',PreparedExact(Stage.Stop));
      Section.AddPair('kind',TJSONNumber.Create(Ord(Stage.Kind)));
      Cues:=TJSONArray.Create;
      Section.AddPair('cues',Cues);
      for Cue in Stage.Cues do begin
        Row:=TJSONArray.Create;
        Cues.AddElement(Row);
        Row.AddElement(PreparedExact(Cue.Time));
        Row.AddElement(PreparedExact(Cue.Lead));
        Row.AddElement(PreparedExact(Cue.Power));
        Row.Add(Cue.Volley);
        Row.Add(Ord(Cue.Enemy));
      end;
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

function LoadCannonAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin
  Root:=ReadPreparedData(Ref,rsCrashCannon,Direction);
  try
    Result:=PreparedAudio(Root,Ref,Source);
    try
      Result.Duration:=ExactDuration(Root,Result.Duration);
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;

procedure ReadStage(Section:TJSONObject;Stage:TCannonStage;Previous,Duration:Double);
var Rows,Row:TJSONArray; V:TJSONValue; I,Kind,Enemy:Integer;
  Cue:TCannonCue; LastTime,LastEnemy:Double;
begin
  Stage.Start:=ReadPreparedExact(Section.GetValue('start'));
  Stage.Stop:=ReadPreparedExact(Section.GetValue('stop'));
  Kind:=Section.GetValue<Integer>('kind',-1);
  Require((Stage.Start=Previous) and (Stage.Stop>Stage.Start) and (Stage.Stop<=Duration+1E-8),'区間');
  Require((Kind>=Ord(Low(TCannonTarget))) and (Kind<=Ord(High(TCannonTarget))),'標的');
  Stage.Kind:=TCannonTarget(Kind);
  V:=Section.GetValue('cues');
  Require(V is TJSONArray,'着弾リスト');
  Rows:=TJSONArray(V);
  Require(Rows.Count<=CannonMaxCues,'着弾数');
  SetLength(Stage.Cues,Rows.Count);
  LastTime:=Stage.Start;
  LastEnemy:=Stage.Start-1.12;
  for I:=0 to High(Stage.Cues) do begin
    Require(Rows.Items[I] is TJSONArray,'着弾');
    Row:=TJSONArray(Rows.Items[I]);
    Require(Row.Count=5,'着弾項目');
    Cue.Time:=ReadPreparedExact(Row.Items[0]);
    Cue.Lead:=ReadPreparedExact(Row.Items[1]);
    Cue.Power:=ReadPreparedExact(Row.Items[2]);
    Require(TryStrToInt(Row.Items[3].Value,Cue.Volley) and TryStrToInt(Row.Items[4].Value,Enemy),
      '砲門・反撃');
    Require((Enemy>=0) and (Enemy<=Ord(High(TCannonEnemy))) and (Cue.Time>LastTime) and
      (Cue.Time<Stage.Stop) and (Cue.Lead>0) and (Cue.Lead<=0.89+1E-8) and
      (Cue.Time-Cue.Lead>=Stage.Start-1E-8) and (Cue.Power>=0) and (Cue.Power<=1),'時刻・強度');
    Cue.Enemy:=TCannonEnemy(Enemy);
    if Cue.Enemy=ceNone then Require((Cue.Volley>=1) and (Cue.Volley<=4),'砲門数')
    else begin
      Require(CannonBoss(Stage.Kind) and (Cue.Volley=0) and (I<High(Stage.Cues)) and
        (Cue.Time>=Stage.Start+0.90) and (Cue.Time-LastEnemy>=1.11),'反撃間隔');
      LastEnemy:=Cue.Time;
    end;
    Stage.Cues[I]:=Cue;
    LastTime:=Cue.Time;
  end;
  Stage.Resolve;
end;

function LoadCannonPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TCannonPlan;
var Root:TJSONObject; Stages:TJSONArray; V:TJSONValue; I:Integer; Stop:Double;
begin
  Require((Audio<>nil) and Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsCrashCannon,0),'参照');
  Root:=ReadPreparedData(Ref,rsCrashCannon,Direction);
  try
    V:=Root.GetValue('stages');
    Require(V is TJSONArray,'区間リスト');
    Stages:=TJSONArray(V);
    Require((Stages.Count>0) and (Stages.Count<=CannonMaxStages),'区間数');
    Result:=TCannonPlan.Create;
    try
      Result.Duration:=ExactDuration(Root,Audio.Duration);
      SetLength(Result.Stages,Stages.Count);
      Stop:=0;
      for I:=0 to High(Result.Stages) do begin
        Require(Stages.Items[I] is TJSONObject,'区間データ');
        Result.Stages[I]:=TCannonStage.Create;
        ReadStage(TJSONObject(Stages.Items[I]),Result.Stages[I],Stop,Result.Duration);
        Stop:=Result.Stages[I].Stop;
      end;
      Result.ResolveSupport;
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;
end.
