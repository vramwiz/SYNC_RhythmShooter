unit RhythmMarblePlan;
// 音の接触候補の選択と保存・復元を担当する。既存の型名もこの窓口から参照できる。
interface

uses System.SysUtils, RhythmAudio, RhythmPlanRef, RhythmBallGeometry, RhythmMarbleCourse;

const
  MarbleRadius = RhythmMarbleCourse.MarbleRadius;
  MarbleAuxRadius = RhythmMarbleCourse.MarbleAuxRadius;
  MarbleAuxGateNose = RhythmMarbleCourse.MarbleAuxGateNose;
  MarbleSlope = RhythmMarbleCourse.MarbleSlope;
  MarbleGravity = RhythmMarbleCourse.MarbleGravity;
  MarbleSeesawExitGrade = RhythmMarbleCourse.MarbleSeesawExitGrade;
  MarbleTrayRear = RhythmMarbleCourse.MarbleTrayRear;
  MarbleTrayNose = RhythmMarbleCourse.MarbleTrayNose;
  MarbleJunctionSpan = RhythmMarbleCourse.MarbleJunctionSpan;

  mmRail = RhythmMarbleCourse.mmRail;
  mmFlight = RhythmMarbleCourse.mmFlight;
  mmSettle = RhythmMarbleCourse.mmSettle;
  mmBend = RhythmMarbleCourse.mmBend;
  mmCarry = RhythmMarbleCourse.mmCarry;
  mmSwing = RhythmMarbleCourse.mmSwing;
  mmSeesaw = RhythmMarbleCourse.mmSeesaw;
  mdGate = RhythmMarbleCourse.mdGate;
  mdBell = RhythmMarbleCourse.mdBell;
  mdSpring = RhythmMarbleCourse.mdSpring;
  mdCatch = RhythmMarbleCourse.mdCatch;
  mdTip = RhythmMarbleCourse.mdTip;
  mdGoal = RhythmMarbleCourse.mdGoal;
  mdBend = RhythmMarbleCourse.mdBend;
  mdLift = RhythmMarbleCourse.mdLift;
  mdShuttle = RhythmMarbleCourse.mdShuttle;
  mdSwing = RhythmMarbleCourse.mdSwing;
  mdChute = RhythmMarbleCourse.mdChute;
  mdSharedTap = RhythmMarbleCourse.mdSharedTap;
  mdSeesaw = RhythmMarbleCourse.mdSeesaw;
  mdTrayRelease = RhythmMarbleCourse.mdTrayRelease;
  mdJunctionGate = RhythmMarbleCourse.mdJunctionGate;
  mlNone = RhythmMarbleCourse.mlNone;
  mlShutter = RhythmMarbleCourse.mlShutter;
  mlSpringLatch = RhythmMarbleCourse.mlSpringLatch;

type
  TMarbleMotion = RhythmMarbleCourse.TMarbleMotion;
  TMarbleDevice = RhythmMarbleCourse.TMarbleDevice;
  TMarbleLinkKind = RhythmMarbleCourse.TMarbleLinkKind;
  TMarbleBeat = RhythmMarbleCourse.TMarbleBeat;
  TMarbleLink = RhythmMarbleCourse.TMarbleLink;
  TMarbleRun = RhythmMarbleCourse.TMarbleRun;
  TMarbleJunction = RhythmMarbleCourse.TMarbleJunction;
  TMarbleLatch = RhythmMarbleCourse.TMarbleLatch;
  TMarbleInterlock = RhythmMarbleCourse.TMarbleInterlock;
  TMarbleBoard = RhythmMarbleCourse.TMarbleBoard;
  TMarbleWeightLift = RhythmMarbleCourse.TMarbleWeightLift;
  TMarbleTrayRelease = RhythmMarbleCourse.TMarbleTrayRelease;
  TMarbleSeesaw = RhythmMarbleCourse.TMarbleSeesaw;
  TMarbleCounter = RhythmMarbleCourse.TMarbleCounter;
  TMarblePass = RhythmMarbleCourse.TMarblePass;
  TMarbleMerge = RhythmMarbleCourse.TMarbleMerge;
  TMarbleAuxiliary = RhythmMarbleCourse.TMarbleAuxiliary;
  TMarbleBridge = RhythmMarbleCourse.TMarbleBridge;
  TMarbleLeg = RhythmMarbleCourse.TMarbleLeg;
  TMarbleCue = RhythmMarbleCourse.TMarbleCue;
  TMarbleSection = RhythmMarbleCourse.TMarbleSection;
  TMarblePlan = RhythmMarbleCourse.TMarblePlan;

// 球の中心と勾配から、レール面上の接触位置を返す。
function MarbleRailSurface(const Center: TBallPoint; Slope: Double = MarbleSlope): TBallPoint;
// 借用した音声の接触候補から譜面を組む。戻り値は呼び出し側が所有する。
function BuildMarblePlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TMarblePlan;
// 接触の時刻・強度を保存し、Refに書き込み後の内容ハッシュを設定する。
procedure SaveMarblePlan(Plan: TMarblePlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
// 保存版の配置規則で接触列からコースを復元する。戻り値は呼び出し側が所有する。
function LoadMarblePlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TMarblePlan;
// 保存計画に添えた再生用の音声情報をPCMなしで読む。戻り値は呼び出し側が所有する。
function LoadMarbleAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;

implementation

uses System.Math, System.JSON, System.Generics.Collections, RhythmPreparedData, RhythmStyles,
  RhythmMarbleLayout, RhythmMarbleLinkage;

const
  MinContactGap = 0.15;
  MaxCues = 22000;
  DuetSecondGap = 0.53;
  ReciprocalGap = 0.72;

function MarbleRailSurface(const Center: TBallPoint; Slope: Double): TBallPoint;
begin
  Result := RhythmMarbleCourse.MarbleRailSurface(Center, Slope);
end;

function BuildMarblePlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TMarblePlan;
var Selected: TList<TMarbleCue>; Hit: TRhythmHit; Cue: TMarbleCue; Last, Gap, BeatDelay: Double;
  I, Part, Previous, Version: Integer;
begin
  Selected := TList<TMarbleCue>.Create;
  try
    Version := StylePlanVersion(rsMarbleRelay);
    Last := -1;
    for I := 0 to High(Audio.Hits) do
    begin
      if Assigned(Cancel) and Cancel() then Abort;
      Hit := Audio.Hits[I];
      if (Hit.Time < 0) or (Hit.Time > Audio.Duration) then Continue;
      Gap := MinContactGap;
      Part := -1;
      Previous := Selected.Count - 1;
      // 密集時も大きな機構を通す余白を取る。採用した音は元の時刻をそのまま使う。
      if (Previous >= 0) and (I < High(Audio.Hits)) then
      begin
        Part := CoursePart(Version, Previous);
        if Part in [5, 8, 9, 10, 12, 14] then Gap := 0.30;
        // 連打が続く曲では、小球用に広く取る区画を絞って接触を残す。
        if Part = 1 then
        begin
          Gap := 0.46;
          if ((Previous div 20) mod 3 = 0) or
            (Last - Selected[Previous - 1].Time >= 0.30) then Gap := 0.72;
        end;
        if (Version >= 6) and (Part = 2) and (Selected[Previous - 1].RelayBeat.Time > 0) then Gap := DuetSecondGap;
        // 通常の交互区間と長い区間を混ぜ、速い連打では短い区間を使う。
        if (Version >= 7) and (Part = 3) and ((Previous div 20) mod 2 = 0) and
          (Selected[Previous - 1].RelayBeat.Time > 0) and (Selected[Previous - 2].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if (Version >= 9) and (Part in [4, 5, 6]) and (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if PassSlot(Version, Previous) and (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if CounterSlot(Version, Previous) and (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
        if (SeesawSlot(Version, Previous) or JunctionTailSlot(Version, Previous)) and
          (Selected[Previous - 1].RelayBeat.Time > 0) and
          (Last - Selected[Previous - 1].Time >= ReciprocalGap - 1E-10) then Gap := ReciprocalGap;
      end;
      if Hit.Time < Last + Gap - 1E-10 then
      begin
        // 主球用に空けた間隔の音を、小球の橋レバーとベルの候補にする。
        BeatDelay := Hit.Time - Last;
        if (Version >= 6) and
          (((Part = 1) and (Gap >= 0.72) and InRange(BeatDelay, 0.34, 0.56)) or
           ((Part = 2) and (Gap = DuetSecondGap) and (BeatDelay >= 0.18 - 1E-10)) or
           ((Part = 3) and (Gap = ReciprocalGap) and InRange(BeatDelay, 0.22, 0.59)) or
           ((Version >= 9) and (Part in [4, 5, 6]) and (Gap = ReciprocalGap) and InRange(BeatDelay, 0.30, 0.60)) or
           ((PassSlot(Version, Previous) or CounterSlot(Version, Previous) or SeesawSlot(Version, Previous) or
             JunctionTailSlot(Version, Previous)) and
            (Gap = ReciprocalGap) and InRange(BeatDelay, 0.30, 0.60))) then
        begin
          Cue := Selected[Previous];
          if Cue.RelayBeat.Time = 0 then
          begin
            Cue.RelayBeat.Time := Hit.Time;
            Cue.RelayBeat.Power := EnsureRange(Hit.Strength, 0.0, 1.0);
            Selected[Previous] := Cue;
          end;
        end;
        Continue;
      end;
      Cue := Default(TMarbleCue);
      Cue.Time := Hit.Time;
      Cue.Power := EnsureRange(Hit.Strength, 0.0, 1.0);
      Selected.Add(Cue);
      Last := Cue.Time;
    end;
    Result := TMarblePlan.Create;
    try
      Result.Version := Version;
      Result.Duration := Audio.Duration;
      Result.Cues := Selected.ToArray;
      if Length(Result.Cues) > 0 then Result.Cues[High(Result.Cues)].RelayBeat := Default(TMarbleBeat);
      LayLinkedCourse(Result, Cancel);
      IndexRotation(Result);
      IndexCourse(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Selected.Free;
  end;
end;

procedure SaveMarblePlan(Plan: TMarblePlan; Audio: TRhythmAudio; var Ref: TRhythmPlanRef);
var Root: TJSONObject; Rows, Row: TJSONArray; Cue: TMarbleCue;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(1));
    Root.AddPair('style', StyleId(rsMarbleRelay));
    Root.AddPair('version', TJSONNumber.Create(Ref.Version));
    Root.AddPair('key', Ref.Key);
    Root.AddPair('source', Ref.SourceKey);
    Root.AddPair('sensitivity', TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction', TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root, Audio);
    Root.AddPair('duration', PreparedExact(Plan.Duration));
    Rows := TJSONArray.Create;
    Root.AddPair('cues', Rows);
    for Cue in Plan.Cues do
    begin
      Row := TJSONArray.Create;
      Rows.AddElement(Row);
      Row.AddElement(PreparedExact(Cue.Time));
      Row.AddElement(PreparedExact(Cue.Power));
      if Ref.Version >= 6 then
      begin
        Row.AddElement(PreparedExact(Cue.RelayBeat.Time));
        Row.AddElement(PreparedExact(Cue.RelayBeat.Power));
      end;
    end;
    WritePreparedData(Root, Ref);
  finally
    Root.Free;
  end;
end;

function LoadMarbleAudio(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
var Root: TJSONObject;
begin
  Root := ReadPreparedData(Ref, rsMarbleRelay, Direction);
  try
    Result := PreparedAudio(Root, Ref, Source);
    Result.Hits := nil; // 冷復元時のEQは保存した接触列を使う。
  finally
    Root.Free;
  end;
end;

procedure RequirePlan(Valid: Boolean);
begin
  if not Valid then raise EConvertError.Create('からくりリレーの保存計画が不正です。再準備してください。');
end;

function LoadMarblePlan(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TMarblePlan;
var Root: TJSONObject; Value: TJSONValue; Rows, Row: TJSONArray;
  I, Columns: Integer; Last: Double; Cue: TMarbleCue;
begin
  RequirePlan(Ref.Matches(Audio.Key, Audio.Sensitivity, Direction, rsMarbleRelay));
  Root := ReadPreparedData(Ref, rsMarbleRelay, Direction);
  try
    Result := TMarblePlan.Create;
    try
      Result.Version := Ref.Version;
      Result.Duration := ReadPreparedExact(Root.GetValue('duration'));
      RequirePlan((Result.Duration > 0) and (Abs(Result.Duration - Audio.Duration) < 1E-8));
      Value := Root.GetValue('cues');
      RequirePlan(Value is TJSONArray);
      Rows := TJSONArray(Value);
      RequirePlan(Rows.Count <= MaxCues);
      SetLength(Result.Cues, Rows.Count);
      Columns := 2;
      if Ref.Version >= 6 then Columns := 4;
      Last := -1;
      for I := 0 to Rows.Count - 1 do
      begin
        RequirePlan(Rows.Items[I] is TJSONArray);
        Row := TJSONArray(Rows.Items[I]);
        RequirePlan(Row.Count = Columns);
        Cue := Default(TMarbleCue);
        Cue.Time := ReadPreparedExact(Row.Items[0]);
        Cue.Power := ReadPreparedExact(Row.Items[1]);
        RequirePlan(InRange(Cue.Time, 0.0, Result.Duration) and (Cue.Time >= Last + MinContactGap - 1E-10) and
          InRange(Cue.Power, 0.0, 1.0));
        if Columns = 4 then
        begin
          Cue.RelayBeat.Time := ReadPreparedExact(Row.Items[2]);
          Cue.RelayBeat.Power := ReadPreparedExact(Row.Items[3]);
          if Cue.RelayBeat.Time <> 0 then
            RequirePlan((I < Rows.Count - 1) and
              ((CoursePart(Ref.Version, I) in [1, 2]) or ((Ref.Version >= 7) and (CoursePart(Ref.Version, I) = 3)) or
               ((Ref.Version >= 9) and (CoursePart(Ref.Version, I) in [4, 5, 6])) or
               PassSlot(Ref.Version, I) or CounterSlot(Ref.Version, I) or SeesawSlot(Ref.Version, I) or
               JunctionTailSlot(Ref.Version, I)) and
              (Cue.Time < Cue.RelayBeat.Time) and InRange(Cue.RelayBeat.Power, 0.0, 1.0));
          if I > 0 then RequirePlan(Result.Cues[I - 1].RelayBeat.Time < Cue.Time);
        end;
        Result.Cues[I] := Cue;
        Last := Cue.Time;
      end;
      LayLinkedCourse(Result);
      IndexRotation(Result);
      IndexCourse(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;

end.
