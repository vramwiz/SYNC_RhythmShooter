unit RhythmJumpCodec;
// 準備済みデータと保存参照を照合。位置と時刻をbinary64のまま復元する。
interface
uses RhythmAudio,RhythmPlanRef,RhythmJumpPlan;
procedure SaveJumpPlan(Plan:TJumpPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
function LoadJumpPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TJumpPlan;
function LoadJumpAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;

implementation
uses System.JSON,System.SysUtils,System.Math,System.Types,System.Generics.Collections,RhythmStyles,RhythmPreparedData;

procedure Require(Valid:Boolean;const Field:string);
begin
  if not Valid then raise EConvertError.Create('ジャンプ計画が不正です: '+Field);
end;

procedure SaveJumpPlan(Plan:TJumpPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
var
  Root:TJSONObject;
  Items,Row:TJSONArray;
  Stage:TJumpStage;
  Node:TJumpNode;
  Leg:TJumpLeg;
  Beat:TJumpBeat;
  Boss:TJumpBoss;

  procedure NewList(const Name:string);
  begin
    Items:=TJSONArray.Create;
    Root.AddPair(Name,Items);
  end;

  procedure NewRow;
  begin
    Row:=TJSONArray.Create;
    Items.AddElement(Row);
  end;

  procedure Exact(Value:Double);
  begin
    Row.AddElement(PreparedExact(Value));
  end;

begin
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsJumpAdventure));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('duration',PreparedExact(Plan.Duration));
    AddPreparedAudio(Root,Audio);
    NewList('stages');
    for Stage in Plan.Stages do begin
      NewRow;
      Exact(Stage.StartTime);
      Row.Add(Ord(Stage.Vertical));
      Row.Add(Stage.Level);
      Row.Add(Stage.Theme);
      Row.Add(Stage.Boss);
    end;
    NewList('nodes');
    for Node in Plan.Nodes do begin
      NewRow;
      Exact(Node.Time);
      Exact(Node.X);
      Exact(Node.Y);
      Exact(Node.Width);
      Exact(Node.MoveX);
      Exact(Node.MoveY);
      Exact(Node.SolidFrom);
      Exact(Node.SolidUntil);
      Row.Add(Ord(Node.Landing));
      Row.Add(Node.Variant);
    end;
    NewList('legs');
    for Leg in Plan.Legs do begin
      NewRow;
      Exact(Leg.Takeoff);
      Exact(Leg.Height);
      Row.Add(Leg.Attack);
    end;
    NewList('beats');
    for Beat in Plan.Beats do begin
      NewRow;
      Exact(Beat.Time);
      Exact(Beat.Strength);
      Row.Add(Beat.Node);
    end;
    NewList('bosses');
    for Boss in Plan.Bosses do begin
      NewRow;
      Row.Add(Boss.FirstNode);
      Row.Add(Boss.LastNode);
      Row.Add(Boss.Variant);
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

function LoadJumpAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin
  Root:=ReadPreparedData(Ref,rsJumpAdventure,Direction);
  try
    Result:=PreparedAudio(Root,Ref,Source);
  finally
    Root.Free;
  end;
end;

procedure ReadPlan(Root:TJSONObject;Plan:TJumpPlan;EventCount:Integer);
var
  List,Row:TJSONArray;
  I,J,StageIndex:Integer;
  Previous:Double;
  P:TPointF;
  Stage:TJumpStage;
  Node:TJumpNode;
  Leg:TJumpLeg;
  Beat:TJumpBeat;
  Boss:TJumpBoss;

  function Count(const Name:string;MinCount,MaxCount:Integer):Integer;
  begin
    List:=Root.GetValue<TJSONArray>(Name);
    Require((List<>nil) and (List.Count>=MinCount) and (List.Count<=MaxCount),Name);
    Result:=List.Count;
  end;

  procedure GetRow(Index,Size:Integer);
  begin
    Require(List.Items[Index] is TJSONArray,'row');
    Row:=TJSONArray(List.Items[Index]);
    Require(Row.Count=Size,'row size');
  end;

  function Exact(Index:Integer;MinValue,MaxValue:Double):Double;
  begin
    Result:=ReadPreparedExact(Row.Items[Index]);
    Require((Result>=MinValue) and (Result<=MaxValue),'coordinate/time');
  end;

  function IntegerAt(Index,MinValue,MaxValue:Integer):Integer;
  begin
    Require((Row.Items[Index] is TJSONNumber) and TryStrToInt(Row.Items[Index].Value,Result) and
      (Result>=MinValue) and (Result<=MaxValue),'index');
  end;

begin
  SetLength(Plan.Nodes,Count('nodes',2,20000));
  Previous:=-1;
  for I:=0 to High(Plan.Nodes) do begin
    GetRow(I,10);
    Node.Time:=Exact(0,0,Plan.Duration);
    Require(Node.Time>Previous,'node order');
    Node.X:=Exact(1,-1E5,1E5);
    Node.Y:=Exact(2,0,1E5);
    Node.Width:=Exact(3,0.20,2);
    Node.MoveX:=Exact(4,0,0.7);
    Node.MoveY:=Exact(5,0,0.5);
    Node.SolidFrom:=Exact(6,0,Node.Time);
    Node.SolidUntil:=Exact(7,Node.Time,Plan.Duration);
    Node.Landing:=TJumpLanding(IntegerAt(8,0,Ord(High(TJumpLanding))));
    Node.Variant:=IntegerAt(9,0,3);
    if Node.Landing=jlBoss then Require(Node.Variant<3,'weak point');
    Plan.Nodes[I]:=Node;
    Previous:=Node.Time;
  end;
  Require((Plan.Nodes[0].Time=0) and (Plan.Nodes[0].Landing=jlGround) and
    (Plan.Nodes[High(Plan.Nodes)].Landing=jlGround),'endpoints');

  SetLength(Plan.Legs,Count('legs',High(Plan.Nodes),High(Plan.Nodes)));
  for I:=0 to High(Plan.Legs) do begin
    GetRow(I,3);
    Node:=Plan.Nodes[I];
    Leg.Takeoff:=Exact(0,Node.Time,Plan.Nodes[I+1].Time);
    Leg.Height:=Exact(1,0,2.5);
    Leg.Attack:=IntegerAt(2,0,3);
    Require((Leg.Takeoff<Plan.Nodes[I+1].Time) and (Leg.Takeoff<=Node.SolidUntil),'takeoff');
    if Node.Landing in [jlStomp,jlBoss] then Require(Leg.Takeoff=Node.Time,'stomp rebound');
    P:=Plan.Platform(I,Leg.Takeoff);
    if Node.Landing in [jlStomp,jlBoss] then P.Y:=Node.Y;
    if Leg.Height>0 then
      Require(Abs(Plan.Nodes[I+1].Y-P.Y)<4*Leg.Height,'jump tangent')
    else
      Require((Leg.Attack=0) and (Abs(Plan.Nodes[I+1].Y-P.Y)<1E-5) and
        (Node.Landing=jlGround) and (Plan.Nodes[I+1].Landing=jlGround),'ground leg');
    Plan.Legs[I]:=Leg;
  end;

  SetLength(Plan.Beats,Count('beats',0,EventCount));
  Previous:=-1;
  for I:=0 to High(Plan.Beats) do begin
    GetRow(I,3);
    Beat.Time:=Exact(0,0,Plan.Nodes[High(Plan.Nodes)].Time);
    Beat.Strength:=Exact(1,0,1);
    Beat.Node:=IntegerAt(2,-1,High(Plan.Nodes));
    Require(Beat.Time>Previous,'beat order');
    if Beat.Node>=0 then Require(Plan.Nodes[Beat.Node].Time=Beat.Time,'beat timing');
    Plan.Beats[I]:=Beat;
    Previous:=Beat.Time;
  end;

  SetLength(Plan.Stages,Count('stages',1,64));
  Previous:=-1;
  for I:=0 to High(Plan.Stages) do begin
    GetRow(I,5);
    Stage.StartTime:=Exact(0,0,Plan.Duration);
    Require((Stage.StartTime>Previous) and (Stage.StartTime<Plan.Nodes[High(Plan.Nodes)].Time),'stage time');
    Stage.Vertical:=IntegerAt(1,0,1)=1;
    Stage.Level:=IntegerAt(2,1,5);
    Stage.Theme:=IntegerAt(3,0,4);
    Stage.Boss:=IntegerAt(4,-1,63);
    Plan.Stages[I]:=Stage;
    Previous:=Stage.StartTime;
  end;
  Require(Plan.Stages[0].StartTime=0,'initial stage');

  SetLength(Plan.Bosses,Count('bosses',0,Length(Plan.Stages)));
  J:=0;
  for I:=0 to High(Plan.Bosses) do begin
    GetRow(I,3);
    Boss.FirstNode:=IntegerAt(0,J+1,High(Plan.Nodes)-1);
    Boss.LastNode:=IntegerAt(1,Boss.FirstNode+2,High(Plan.Nodes)-1);
    Boss.Variant:=IntegerAt(2,0,2);
    StageIndex:=Plan.StageAt(Plan.Nodes[Boss.FirstNode].Time);
    Require((Plan.Stages[StageIndex].Boss=I) and (Plan.StageAt(Plan.Nodes[Boss.LastNode].Time)=StageIndex),'boss stage');
    for J:=Boss.FirstNode to Boss.LastNode do Require(Plan.Nodes[J].Landing=jlBoss,'boss contact');
    J:=Boss.LastNode;
    StageIndex:=Plan.BeatFrom(Plan.Nodes[J].Time);
    Require((StageIndex<Length(Plan.Beats)) and (Plan.Beats[StageIndex].Node=J),'boss finish beat');
    Plan.Bosses[I]:=Boss;
  end;
  for I:=0 to High(Plan.Stages) do
    if Plan.Stages[I].Boss>=0 then begin
      J:=Plan.Stages[I].Boss;
      Require(J<Length(Plan.Bosses),'boss index');
      Require(Plan.StageAt(Plan.Nodes[Plan.Bosses[J].FirstNode].Time)=I,'stage boss index');
    end;
end;

function LoadJumpPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TJumpPlan;
var Root,Info:TJSONObject;
begin
  Require(Audio<>nil,'audio');
  Require(Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsJumpAdventure,Ref.Variant),'identity');
  Root:=ReadPreparedData(Ref,rsJumpAdventure,Direction);
  try
    Info:=Root.GetValue<TJSONObject>('audio');
    Require((Info<>nil) and (Info.GetValue<Integer>('events',-1)=Length(Audio.Hits)),'audio events');
    Result:=TJumpPlan.Create;
    try
      Result.Duration:=ReadPreparedExact(Root.GetValue('duration'));
      Require((Result.Duration>0) and (Abs(Result.Duration-Audio.Duration)<1E-6),'duration');
      ReadPlan(Root,Result,Length(Audio.Hits));
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;
end.
