unit RhythmCartCodec;
// 共通の準備キャッシュを使い、検証済みの座標と音時刻を正確に復元する。
interface
uses RhythmAudio,RhythmPlanRef,RhythmCartPlan;
procedure SaveCartPlan(Plan:TCartPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
function LoadCartPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TCartPlan;
function LoadCartAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;

implementation
uses System.JSON,System.SysUtils,System.Math,System.Generics.Collections,RhythmStyles,RhythmPreparedData;

procedure Require(Condition:Boolean;const Field:string);
begin
  if not Condition then raise EConvertError.Create('トロッコの保存計画が不正です。'+Field);
end;

procedure SaveCartPlan(Plan:TCartPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
var
  Root:TJSONObject;
  Rows,Row:TJSONArray;
  Knot:TCartKnot;
  Coin:TCartCoin;
  Move:TCartMove;
  Boss:TCartBoss;

  procedure List(const Name:string);
  begin
    Rows:=TJSONArray.Create;
    Root.AddPair(Name,Rows);
  end;

  procedure NewRow;
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
    Root.AddPair('style',StyleId(rsMineCart));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('goal',PreparedExact(Plan.Goal));
    AddPreparedAudio(Root,Audio);
    List('rail');
    for Knot in Plan.Knots do begin
      NewRow;
      Exact(Knot.Time);
      Exact(Knot.X);
      Exact(Knot.Y);
      Exact(Knot.Speed);
      Row.Add(Knot.Theme);
    end;
    List('coins');
    for Coin in Plan.Coins do begin
      NewRow;
      Exact(Coin.Time);
      Exact(Coin.Strength);
      Exact(Coin.X);
      Exact(Coin.Y);
    end;
    List('moves');
    for Move in Plan.Moves do begin
      NewRow;
      Exact(Move.Start);
      Exact(Move.Hit);
      Exact(Move.Finish);
      Exact(Move.Height);
      Row.Add(Ord(Move.Kind));
    end;
    List('bosses');
    for Boss in Plan.Bosses do begin
      NewRow;
      Row.Add(Boss.FirstMove);
      Row.Add(Boss.LastMove);
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

function LoadCartAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin
  Root:=ReadPreparedData(Ref,rsMineCart,Direction);
  try
    Result:=PreparedAudio(Root,Ref,Source);
  finally
    Root.Free;
  end;
end;

procedure ReadPlan(Root:TJSONObject;Plan:TCartPlan;Audio:TRhythmAudio;Version:Integer);
var
  Rows,Row:TJSONArray;
  Info:TJSONObject;
  I,MaxMoveKind:Integer;
  Knot:TCartKnot;
  Coin:TCartCoin;
  Move:TCartMove;
  Boss:TCartBoss;

  function Count(const Name:string;MinCount,MaxCount:Integer):Integer;
  begin
    Rows:=Root.GetValue<TJSONArray>(Name);
    Require((Rows<>nil) and InRange(Rows.Count,MinCount,MaxCount),Name);
    Result:=Rows.Count;
  end;

  procedure SelectRow(Index,Size:Integer);
  begin
    Require(Rows.Items[Index] is TJSONArray,'行');
    Row:=TJSONArray(Rows.Items[Index]);
    Require(Row.Count=Size,'列数');
  end;

  function Exact(Index:Integer;LowValue,HighValue:Double):Double;
  begin
    Result:=ReadPreparedExact(Row.Items[Index]);
    Require(InRange(Result,LowValue,HighValue),'座標・時刻');
  end;

  function IntAt(Index,LowValue,HighValue:Integer):Integer;
  begin
    Require((Row.Items[Index] is TJSONNumber) and TryStrToInt(Row.Items[Index].Value,Result) and
      InRange(Result,LowValue,HighValue),'番号');
  end;

begin
  Info:=Root.GetValue<TJSONObject>('audio');
  Require((Info<>nil) and (Info.GetValue<Integer>('events',-1)=Length(Audio.Hits)),'音声情報');
  Plan.Duration:=Audio.Duration;
  Plan.Goal:=ReadPreparedExact(Root.GetValue('goal'));
  Require((Plan.Goal>0) and (Plan.Goal<=Plan.Duration),'ゴール');
  SetLength(Plan.Knots,Count('rail',2,4000));
  for I:=0 to High(Plan.Knots) do begin
    SelectRow(I,5);
    Knot.Time:=Exact(0,0,Plan.Goal);
    Knot.X:=Exact(1,0,100000);
    Knot.Y:=Exact(2,-2,6);
    Knot.Speed:=Exact(3,5,12);
    Knot.Theme:=IntAt(4,0,4);
    Plan.Knots[I]:=Knot;
  end;
  SetLength(Plan.Coins,Count('coins',0,Length(Audio.Hits)));
  for I:=0 to High(Plan.Coins) do begin
    SelectRow(I,4);
    Coin.Time:=Exact(0,0,Plan.Goal);
    Coin.Strength:=Exact(1,0,1);
    Coin.X:=Exact(2,0,100001);
    Coin.Y:=Exact(3,-3,10);
    Plan.Coins[I]:=Coin;
  end;
  SetLength(Plan.Moves,Count('moves',0,4000));
  MaxMoveKind:=Ord(cmBoss);
  if Version=2 then MaxMoveKind:=Ord(cmRam);
  if Version>=3 then MaxMoveKind:=Ord(cmBossBump);
  for I:=0 to High(Plan.Moves) do begin
    SelectRow(I,5);
    Move.Start:=Exact(0,0,Plan.Goal);
    Move.Hit:=Exact(1,0,Plan.Goal);
    Move.Finish:=Exact(2,0,Plan.Goal);
    Move.Height:=Exact(3,0,2);
    Move.Kind:=TCartMoveKind(IntAt(4,0,MaxMoveKind));
    Plan.Moves[I]:=Move;
  end;
  SetLength(Plan.Bosses,Count('bosses',0,80));
  for I:=0 to High(Plan.Bosses) do begin
    SelectRow(I,2);
    Boss.FirstMove:=IntAt(0,0,High(Plan.Moves));
    Boss.LastMove:=IntAt(1,Boss.FirstMove+1,High(Plan.Moves));
    Plan.Bosses[I]:=Boss;
  end;
  Plan.Verify(Version>=2);
end;

function LoadCartPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TCartPlan;
var Root:TJSONObject;
begin
  Require((Audio<>nil) and Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsMineCart,Ref.Variant),'参照');
  Root:=ReadPreparedData(Ref,rsMineCart,Direction);
  try
    Result:=TCartPlan.Create;
    try
      ReadPlan(Root,Result,Audio,Ref.Version);
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;
end.
