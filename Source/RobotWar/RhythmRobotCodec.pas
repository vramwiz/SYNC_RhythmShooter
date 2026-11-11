unit RhythmRobotCodec;
// 全曲の工程と命中をbinary64で保存する。PCMや再解析を使わず検証して復元する。
interface

uses RhythmRobotPlan, RhythmAudio, RhythmPlanRef;

procedure SaveRobotPlan(Plan: TRobotPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
function LoadRobotPlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TRobotPlan;
function LoadRobotAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;

implementation

uses System.SysUtils, System.Math, System.JSON, System.Generics.Collections, RhythmPreparedData, RhythmStyles;

procedure Require(Value: Boolean; const Field: string);
begin
  if not Value then raise EConvertError.Create('ロボット大戦の保存計画が不正です。' + Field);
end;

procedure SaveRobotPlan(Plan: TRobotPlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
var Root: TJSONObject; Stages, Cues, Row: TJSONArray; Stage: TRobotStage; Cue: TRobotCue; I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(1));
    Root.AddPair('style', StyleId(rsRobotWar));
    Root.AddPair('version', TJSONNumber.Create(Ref.Version));
    Root.AddPair('key', Ref.Key);
    Root.AddPair('source', Ref.SourceKey);
    Root.AddPair('sensitivity', TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction', TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root, Audio);
    Root.AddPair('duration', PreparedExact(Plan.Duration));
    Root.AddPair('palette', TJSONNumber.Create(Plan.Palette));
    Stages := TJSONArray.Create;
    Root.AddPair('stages', Stages);
    for Stage in Plan.Stages do
    begin
      Row := TJSONArray.Create;
      Stages.AddElement(Row);
      Row.AddElement(PreparedExact(Stage.Start));
      Row.AddElement(PreparedExact(Stage.Finish));
      Row.Add(Ord(Stage.Kind));
      Row.Add(Ord(Stage.Team));
      Row.Add(Stage.Allies);
      Row.Add(Stage.Enemies);
      Row.Add(Stage.AllyAssembly);
      Row.Add(Stage.EnemyAssembly);
      for I := 0 to High(Stage.Locks) do
      begin
        Row.AddElement(PreparedExact(Stage.Locks[I]));
        Row.Add(Ord(Stage.Synced[I]));
      end;
    end;
    Cues := TJSONArray.Create;
    Root.AddPair('cues', Cues);
    for Cue in Plan.Cues do
    begin
      Row := TJSONArray.Create;
      Cues.AddElement(Row);
      Row.AddElement(PreparedExact(Cue.Time));
      Row.AddElement(PreparedExact(Cue.Lead));
      Row.AddElement(PreparedExact(Cue.Recover));
      Row.AddElement(PreparedExact(Cue.Power));
      Row.Add(Cue.Stage);
      Row.Add(Cue.Member);
      Row.Add(Ord(Cue.Team));
      Row.Add(Ord(Cue.Attack));
      Row.Add(Ord(Cue.Reaction));
    end;
    WritePreparedData(Root, Ref);
  finally
    Root.Free;
  end;
end;

function LoadRobotAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
var Root: TJSONObject;
begin
  Root := ReadPreparedData(Ref, rsRobotWar, Direction);
  try
    Result := PreparedAudio(Root, Ref, Source);
  finally
    Root.Free;
  end;
end;

function IntegerAt(Row: TJSONArray; Index, Minimum, Maximum: Integer): Integer;
begin
  Require((Row.Items[Index] is TJSONNumber) and TryStrToInt(Row.Items[Index].Value, Result), '整数');
  Require(InRange(Result, Minimum, Maximum), '列挙・機体数');
end;

function LoadRobotPlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TRobotPlan;
var Root: TJSONObject; Rows, Row: TJSONArray; Value: TJSONValue;
  I, J: Integer; Previous, LockTime: Double; Stage: TRobotStage; Cue: TRobotCue;
  Template: TRobotPlan;
begin
  Require((Audio <> nil) and Ref.Matches(Audio.Key, Audio.Sensitivity, Direction, rsRobotWar, 0), '参照');
  Root := ReadPreparedData(Ref, rsRobotWar, Direction);
  try
    Result := TRobotPlan.Create;
    try
      Result.Duration := ReadPreparedExact(Root.GetValue('duration'));
      Require((Result.Duration > 0) and (Abs(Result.Duration - Audio.Duration) < 1E-8), '音源長');
      Result.Palette := Root.GetValue<Integer>('palette', -1);
      Require(InRange(Result.Palette, 0, 3), '配色');
      Value := Root.GetValue('stages');
      Require((Value is TJSONArray) and (TJSONArray(Value).Count = 28), '工程数');
      Rows := TJSONArray(Value);
      SetLength(Result.Stages, Rows.Count);
      Previous := 0;
      // v1の物語・合体人数も検証する。復元音声の空Hitsを走査する必要はない。
      Template := BuildRobotPlan(Audio, nil);
      try
        for I := 0 to High(Result.Stages) do
        begin
          Require(Rows.Items[I] is TJSONArray, '工程');
          Row := TJSONArray(Rows.Items[I]);
          Require(Row.Count = 24, '工程項目');
          Stage := Default(TRobotStage);
          Stage.Start := ReadPreparedExact(Row.Items[0]);
          Stage.Finish := ReadPreparedExact(Row.Items[1]);
          Stage.Kind := TRobotStageKind(IntegerAt(Row, 2, 0, Ord(High(TRobotStageKind))));
          Stage.Team := TRobotTeam(IntegerAt(Row, 3, 0, 1));
          Stage.Allies := IntegerAt(Row, 4, 0, 3);
          Stage.Enemies := IntegerAt(Row, 5, 1, 3);
          Stage.AllyAssembly := IntegerAt(Row, 6, 1, 3);
          Stage.EnemyAssembly := IntegerAt(Row, 7, 1, 3);
          Require((Stage.Start = Previous) and (Stage.Finish > Stage.Start) and
            (Stage.Finish <= Result.Duration) and (Stage.Kind = Template.Stages[I].Kind) and
            (Stage.Team = Template.Stages[I].Team) and (Stage.Allies = Template.Stages[I].Allies) and
            (Stage.Enemies = Template.Stages[I].Enemies) and
            (Stage.AllyAssembly = Template.Stages[I].AllyAssembly) and
            (Stage.EnemyAssembly = Template.Stages[I].EnemyAssembly), '展開・時刻');
          LockTime := Stage.Start;
          for J := 0 to High(Stage.Locks) do
          begin
            Stage.Locks[J] := ReadPreparedExact(Row.Items[8 + J * 2]);
            Stage.Synced[J] := IntegerAt(Row, 9 + J * 2, 0, 1) = 1;
            Require((Stage.Locks[J] > LockTime) and (Stage.Locks[J] < Stage.Finish), '接続順序');
            LockTime := Stage.Locks[J];
          end;
          Result.Stages[I] := Stage;
          Previous := Stage.Finish;
        end;
      finally
        Template.Free;
      end;
      Require(Previous = Result.Duration, '勝利終端');
      Value := Root.GetValue('cues');
      Require((Value is TJSONArray) and (TJSONArray(Value).Count <= 100000), '命中リスト');
      Rows := TJSONArray(Value);
      SetLength(Result.Cues, Rows.Count);
      Previous := -1;
      for I := 0 to High(Result.Cues) do
      begin
        Require(Rows.Items[I] is TJSONArray, '命中');
        Row := TJSONArray(Rows.Items[I]);
        Require(Row.Count = 9, '命中項目');
        Cue.Time := ReadPreparedExact(Row.Items[0]);
        Cue.Lead := ReadPreparedExact(Row.Items[1]);
        Cue.Recover := ReadPreparedExact(Row.Items[2]);
        Cue.Power := ReadPreparedExact(Row.Items[3]);
        Cue.Stage := IntegerAt(Row, 4, 0, High(Result.Stages));
        Cue.Member := IntegerAt(Row, 5, 0, 2);
        Cue.Team := TRobotTeam(IntegerAt(Row, 6, 0, 1));
        Cue.Attack := TRobotAttack(IntegerAt(Row, 7, 0, Ord(High(TRobotAttack))));
        Cue.Reaction := TRobotReaction(IntegerAt(Row, 8, 0, Ord(High(TRobotReaction))));
        Stage := Result.Stages[Cue.Stage];
        Require((Stage.Kind in [rkBattle, rkFinisher]) and (Cue.Time > Previous) and
          (Cue.Lead > 0) and (Cue.Lead <= 0.85) and (Cue.Recover > 0) and (Cue.Recover <= 0.65) and
          (Cue.Time - Cue.Lead >= Stage.Start) and (Cue.Time + Cue.Recover <= Stage.Finish) and
          InRange(Cue.Power, 0.0, 1.0) and (Cue.Member < Stage.Members(Cue.Team)) and
          ((Cue.Member = 0) or (Cue.Member >= Stage.Assembly(Cue.Team))), '動作の範囲');
        if Stage.Kind = rkFinisher then Require((Cue.Team = rtAlly) and
          (Cue.Attack = raSpecial) and (Cue.Reaction = rrHit), '最終攻撃');
        Result.Cues[I] := Cue;
        Previous := Cue.Time;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;

end.
