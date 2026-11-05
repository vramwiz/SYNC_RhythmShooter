unit RhythmRushCodec;
// 共通の計画ファイルとハッシュを使い、技と座標を音源なしで復元する。
interface
uses RhythmAudio,RhythmPlanRef,RhythmRushPlan;
procedure SaveRushPlan(Plan:TRushPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
function LoadRushPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRushPlan;
function LoadRushAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;

implementation
uses System.JSON,System.SysUtils,System.Math,System.Generics.Collections,RhythmStyles,RhythmPreparedData;

procedure Require(Valid:Boolean;const Field:string);
begin
  if not Valid then raise EConvertError.Create('格闘ラッシュの計画が不正です: '+Field);
end;

procedure SaveRushPlan(Plan:TRushPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
var Root:TJSONObject; Rows,Row:TJSONArray; S:TRushStage; A:TRushCue; F:TRushFoe; Arc:TRushArc;

  procedure List(const Name:string);
  begin
    Rows:=TJSONArray.Create;
    Root.AddPair(Name,Rows);
  end;

  procedure RecordRow;
  begin
    Row:=TJSONArray.Create;
    Rows.AddElement(Row);
  end;

  procedure Exact(Value:Double);
  begin
    Row.AddElement(PreparedExact(Value));
  end;

begin
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsFightingRush));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('duration',PreparedExact(Plan.Duration));
    Root.AddPair('finish',PreparedExact(Plan.Finish));
    AddPreparedAudio(Root,Audio);
    List('stages');
    for S in Plan.Stages do begin
      RecordRow;
      Exact(S.StartTime);
      Exact(S.X);
      Exact(S.Speed);
      Row.Add(Ord(S.Mode));
      Row.Add(S.Level);
      Row.Add(S.Theme);
      Row.Add(S.Boss);
    end;
    List('cues');
    for A in Plan.Cues do begin
      RecordRow;
      Exact(A.Time);
      Exact(A.Power);
      Exact(A.Flight);
      Row.Add(Ord(A.Move));
      Row.Add(A.Foe);
      Row.Add(A.Cause);
    end;
    List('foes');
    for F in Plan.Foes do begin
      RecordRow;
      Row.Add(F.First);
      Row.Add(F.Last);
      Row.Add(F.Kind);
      Row.Add(F.Side);
      Row.Add(Ord(F.Boss));
    end;
    List('arcs');
    for Arc in Plan.Arcs do begin
      RecordRow;
      Row.Add(Arc.First);
      Row.Add(Arc.Last);
      Exact(Arc.Height);
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

function LoadRushAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin
  Root:=ReadPreparedData(Ref,rsFightingRush,Direction);
  try
    Result:=PreparedAudio(Root,Ref,Source);
  finally
    Root.Free;
  end;
end;

procedure Parse(Root:TJSONObject;Plan:TRushPlan;EventCount:Integer);
var Rows,Row:TJSONArray;
  I,J,K,Expected:Integer;
  Previous:Double;
  S:TRushStage;
  A:TRushCue;
  F:TRushFoe;
  Arc:TRushArc;

  function Count(const Name:string;MinCount,MaxCount:Integer):Integer;
  begin
    Rows:=Root.GetValue<TJSONArray>(Name);
    Require((Rows<>nil) and (Rows.Count>=MinCount) and (Rows.Count<=MaxCount),Name);
    Result:=Rows.Count;
  end;

  procedure ReadRow(Index,Size:Integer);
  begin
    Require(Rows.Items[Index] is TJSONArray,'row type');
    Row:=TJSONArray(Rows.Items[Index]);
    Require(Row.Count=Size,'row size');
  end;

  function Exact(Index:Integer;LowValue,HighValue:Double):Double;
  begin
    Result:=ReadPreparedExact(Row.Items[Index]);
    Require((Result>=LowValue) and (Result<=HighValue),'coordinate/time');
  end;

  function IntAt(Index,LowValue,HighValue:Integer):Integer;
  begin
    Require((Row.Items[Index] is TJSONNumber) and TryStrToInt(Row.Items[Index].Value,Result) and
      (Result>=LowValue) and (Result<=HighValue),'index');
  end;

begin
  SetLength(Plan.Stages,Count('stages',1,64));
  Previous:=-1;
  for I:=0 to High(Plan.Stages) do begin
    ReadRow(I,7);
    S.StartTime:=Exact(0,0,Plan.Finish);
    Require((S.StartTime>Previous) and (S.StartTime<Plan.Finish),'stage timing');
    S.X:=Exact(1,0,100000);
    S.Speed:=Exact(2,0,8);
    S.Mode:=TRushMode(IntAt(3,0,Ord(High(TRushMode))));
    S.Level:=IntAt(4,1,5);
    S.Theme:=IntAt(5,0,4);
    S.Boss:=IntAt(6,-1,EventCount-1);
    if I>0 then Require(Abs(S.X-Plan.Stages[I-1].X-(S.StartTime-Previous)*
      Plan.Stages[I-1].Speed)<1E-8,'stage continuity')
    else Require((S.StartTime=0) and (S.X=0),'initial stage');
    Plan.Stages[I]:=S;
    Previous:=S.StartTime;
  end;

  SetLength(Plan.Cues,Count('cues',0,EventCount));
  Previous:=-1;
  for I:=0 to High(Plan.Cues) do begin
    A:=Default(TRushCue);
    ReadRow(I,6);
    A.Time:=Exact(0,0,Plan.Finish);
    Require(A.Time>Previous,'cue order');
    A.Power:=Exact(1,0,1);
    A.Flight:=Exact(2,0,Min(0.6,A.Time));
    A.Move:=TRushMove(IntAt(3,0,Ord(High(TRushMove))));
    A.Foe:=IntAt(4,0,High(Plan.Cues));
    A.Cause:=IntAt(5,-1,A.Foe-1);
    Require((A.Cause>=0)=(A.Move=raCrash),'group collision');
    Require((A.Flight=0) or (Defensive(A.Move) or (A.Move=raOrb)),'flight type');
    if A.Move=raOrb then Require(A.Flight>0,'orb lead');
    Plan.Cues[I]:=A;
    Previous:=A.Time;
  end;

  SetLength(Plan.Foes,Count('foes',Ord(Length(Plan.Cues)>0),Length(Plan.Cues)));
  Expected:=0;
  for I:=0 to High(Plan.Foes) do begin
    ReadRow(I,5);
    F.First:=IntAt(0,Expected,Expected);
    F.Last:=IntAt(1,F.First,High(Plan.Cues));
    F.Kind:=IntAt(2,0,5);
    F.Side:=IntAt(3,-1,1);
    F.Boss:=IntAt(4,0,1)=1;
    Require((F.Side<>0) and not Defensive(Plan.Cues[F.Last].Move),'enemy end');
    K:=Plan.StageAt(Plan.Cues[F.First].Time);
    Require((not F.Boss or (Plan.Stages[K].Boss=I)) and
      (Plan.StageAt(Plan.Cues[F.Last].Time)=K),'enemy stage');
    for J:=F.First to F.Last do begin
      Require(Plan.Cues[J].Foe=I,'cue enemy');
      if Plan.Cues[J].Cause>=0 then
        Require((Plan.Cues[J].Cause=I-1) and (J=F.First) and (J=F.Last) and
          (Plan.Cues[J-1].Move<>raCrash),'collision chain');
    end;
    Expected:=F.Last+1;
    Plan.Foes[I]:=F;
  end;
  Require(Expected=Length(Plan.Cues),'unused cues');
  for I:=0 to High(Plan.Stages) do begin
    K:=Plan.Stages[I].Boss;
    if K>=0 then
      Require((K<Length(Plan.Foes)) and Plan.Foes[K].Boss and
        (Plan.StageAt(Plan.Cues[Plan.Foes[K].First].Time)=I),'boss index');
  end;

  SetLength(Plan.Arcs,Count('arcs',0,Length(Plan.Cues) div 3));
  Expected:=0;
  for I:=0 to High(Plan.Arcs) do begin
    ReadRow(I,3);
    Arc.First:=IntAt(0,Expected,High(Plan.Cues)-2);
    Arc.Last:=IntAt(1,Arc.First+2,High(Plan.Cues));
    Arc.Height:=Exact(2,0.5,3);
    Require((Plan.Cues[Arc.Last].Time-Plan.Cues[Arc.First].Time>=0.60) and
      (Plan.Cues[Arc.Last].Foe=Plan.Cues[Arc.First].Foe) and
      (Plan.Cues[Arc.First].Move in [raLaunch,raThrow]) and
      (Plan.Cues[Arc.Last].Move=raSlam),'air combo');
    Expected:=Arc.Last+1;
    Plan.Arcs[I]:=Arc;
  end;
end;

function LoadRushPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRushPlan;
var Root,Info:TJSONObject;
begin
  Require(Audio<>nil,'audio');
  Require(Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsFightingRush,Ref.Variant),'identity');
  Root:=ReadPreparedData(Ref,rsFightingRush,Direction);
  try
    Info:=Root.GetValue<TJSONObject>('audio');
    Require((Info<>nil) and (Info.GetValue<Integer>('events',-1)=Length(Audio.Hits)),'audio events');
    Result:=TRushPlan.Create;
    try
      Result.Duration:=ReadPreparedExact(Root.GetValue('duration'));
      Result.Finish:=ReadPreparedExact(Root.GetValue('finish'));
      Require((Abs(Result.Duration-Audio.Duration)<1E-6) and (Result.Finish>0) and
        (Result.Finish<=Result.Duration),'duration');
      Parse(Root,Result,Length(Audio.Hits));
      Result.ArrangeHealth;
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;
end.
