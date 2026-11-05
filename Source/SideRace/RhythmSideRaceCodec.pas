unit RhythmSideRaceCodec;
// 保存参照を検証し、音時刻・速度・道路・接触を準備済みデータから復元する。
interface
uses RhythmAudio,RhythmPlanRef,RhythmSideRacePlan;
procedure SaveSideRace(Plan:TSideRacePlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
function LoadSideRace(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TSideRacePlan;
function LoadSideRaceAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;

implementation
uses System.SysUtils,System.Math,System.JSON,System.Generics.Collections,RhythmStyles,RhythmPreparedData;

// 共通PCM上限では45秒間隔のボスが64戦を超える場合がある。
const MaxBosses=80;

procedure Need(Valid:Boolean;const Field:string);
begin
  if not Valid then raise EConvertError.Create('2Dハイウェイの計画が不正です: '+Field);
end;

procedure SaveSideRace(Plan:TSideRacePlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
var Root:TJSONObject; Rows,Row:TJSONArray;
  S:TSideStage; A:TSideCue; F:TSideCar; B:TSideBoss; J:TSideJump;

  procedure List(const Name:string);
  begin
    Rows:=TJSONArray.Create;
    Root.AddPair(Name,Rows);
  end;

  procedure AddRow;
  begin
    Row:=TJSONArray.Create;
    Rows.AddElement(Row);
  end;

  procedure AddReal(Value:Double);
  begin
    Row.AddElement(PreparedExact(Value));
  end;

begin
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsSideRace));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('duration',PreparedExact(Plan.Duration));
    Root.AddPair('goal',PreparedExact(Plan.Goal));
    AddPreparedAudio(Root,Audio);
    List('stages');
    for S in Plan.Stages do begin
      AddRow;
      AddReal(S.Time);
      AddReal(S.X);
      AddReal(S.Speed);
      Row.Add(S.Level);
      Row.Add(S.Theme);
    end;
    List('cues');
    for A in Plan.Cues do begin
      AddRow;
      AddReal(A.Time);
      AddReal(A.Power);
      AddReal(A.Health);
      Row.Add(Ord(A.Action));
      Row.Add(A.Car);
      Row.Add(A.Boss);
      Row.Add(Ord(A.Musical));
    end;
    List('cars');
    for F in Plan.Cars do begin
      AddRow;
      Row.Add(F.First);
      Row.Add(F.Last);
      Row.Add(F.Stride);
      Row.Add(F.Side);
      Row.Add(F.Kind);
    end;
    List('bosses');
    for B in Plan.Bosses do begin
      AddRow;
      Row.Add(B.First);
      Row.Add(B.Last);
      Row.Add(B.Kind);
    end;
    List('jumps');
    for J in Plan.Jumps do begin
      AddRow;
      Row.Add(J.First);
      Row.Add(J.Last);
      Row.Add(J.Roof);
      AddReal(J.Height);
      AddReal(J.Ramp);
      AddReal(J.Gap);
      AddReal(J.Lift);
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

function LoadSideRaceAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin
  Root:=ReadPreparedData(Ref,rsSideRace,Direction);
  try
    Result:=PreparedAudio(Root,Ref,Source);
  finally
    Root.Free;
  end;
end;

procedure Parse(Root:TJSONObject;Plan:TSideRacePlan;EventCount:Integer);
var Rows,Row:TJSONArray; I,K,Previous,MusicCount,Bonus:Integer;
  Last:Double; S,Prev:TSideStage; A:TSideCue; F:TSideCar; B:TSideBoss; J:TSideJump;
  CarSeen:TArray<Boolean>;

  function Count(const Name:string;MinCount,MaxCount:Integer):Integer;
  begin
    Rows:=Root.GetValue<TJSONArray>(Name);
    Need((Rows<>nil) and (Rows.Count>=MinCount) and (Rows.Count<=MaxCount),Name);
    Result:=Rows.Count;
  end;

  procedure ReadRow(Index,Size:Integer);
  begin
    Need(Rows.Items[Index] is TJSONArray,'row type');
    Row:=TJSONArray(Rows.Items[Index]);
    Need(Row.Count=Size,'row size');
  end;

  function Exact(Index:Integer;MinValue,MaxValue:Double):Double;
  begin
    Result:=ReadPreparedExact(Row.Items[Index]);
    Need((Result>=MinValue) and (Result<=MaxValue),'position/time');
  end;

  function IntAt(Index,MinValue,MaxValue:Integer):Integer;
  begin
    Need((Row.Items[Index] is TJSONNumber) and TryStrToInt(Row.Items[Index].Value,Result) and
      (Result>=MinValue) and (Result<=MaxValue),'index');
  end;

begin
  SetLength(Plan.Stages,Count('stages',1,64));
  Last:=-1;
  for I:=0 to High(Plan.Stages) do begin
    ReadRow(I,5);
    S.Time:=Exact(0,0,Plan.Duration);
    Need((S.Time>Last) and (S.Time<Plan.Duration),'stage order');
    S.X:=Exact(1,0,100000);
    S.Speed:=Exact(2,14,29);
    S.Level:=IntAt(3,1,5);
    S.Theme:=IntAt(4,0,3);
    if I>0 then begin
      Prev:=Plan.Stages[I-1];
      Need(Abs(S.X-Prev.X-(S.Time-Prev.Time)*(S.Speed+Prev.Speed)*0.5)<1E-8,'stage distance');
    end else Need((S.X=0) and (S.Time=0),'opening');
    Plan.Stages[I]:=S;
    Last:=S.Time;
  end;

  SetLength(Plan.Cues,Count('cues',1,EventCount+1));
  Last:=-1;
  MusicCount:=0;
  Bonus:=0;
  for I:=0 to High(Plan.Cues) do begin
    ReadRow(I,7);
    A.Time:=Exact(0,0,Plan.Duration);
    Need(A.Time>Last,'cue order');
    A.Power:=Exact(1,0,1);
    A.Health:=Exact(2,0.20,1);
    A.Action:=TSideAction(IntAt(3,0,Ord(High(TSideAction))));
    A.Car:=IntAt(4,-1,High(Plan.Cues));
    A.Boss:=IntAt(5,-1,MaxBosses-1);
    A.Musical:=IntAt(6,0,1)=1;
    if A.Musical then Inc(MusicCount) else begin
      Need(A.Action=saBossClear,'non-musical cue');
      Inc(Bonus);
    end;
    Need((A.Car>=0)=(A.Action in [saFront,saRear,saBossEscort]),'opponent cue');
    Plan.Cues[I]:=A;
    Last:=A.Time;
  end;
  Need((MusicCount<=EventCount) and (Bonus<=1),'cue count');

  SetLength(Plan.Bosses,Count('bosses',1,Min(MaxBosses,Length(Plan.Cues))));
  Previous:=-1;
  for I:=0 to High(Plan.Bosses) do begin
    ReadRow(I,3);
    B.First:=IntAt(0,Previous+1,High(Plan.Cues));
    B.Last:=IntAt(1,B.First,High(Plan.Cues));
    B.Kind:=IntAt(2,0,4);
    Need((Plan.Cues[B.Last].Action=saBossClear) and (Plan.Cues[B.Last].Time<Plan.Goal),'boss finish');
    for K:=B.First to B.Last do Need(Plan.Cues[K].Boss=I,'boss cue');
    Plan.Bosses[I]:=B;
    Previous:=B.Last;
  end;
  for I:=0 to High(Plan.Cues) do begin
    Need(Plan.Cues[I].Boss=Plan.BossAt(Plan.Cues[I].Time),'boss bounds');
    if Plan.Cues[I].Action in [saBossRam,saBossTire,saBossRoof,saBossDrop,saBossEscort,saBossClear] then
      Need(Plan.Cues[I].Boss>=0,'boss action outside battle');
  end;

  SetLength(Plan.Cars,Count('cars',0,Length(Plan.Cues)));
  SetLength(CarSeen,Length(Plan.Cues));
  for I:=0 to High(Plan.Cars) do begin
    ReadRow(I,5);
    F.First:=IntAt(0,0,High(Plan.Cues));
    F.Last:=IntAt(1,F.First,High(Plan.Cues));
    F.Stride:=IntAt(2,1,2);
    F.Side:=IntAt(3,-1,1);
    F.Kind:=IntAt(4,0,5);
    Need((F.Side<>0) and ((F.Last-F.First) mod F.Stride=0),'car stride');
    K:=F.First;
    while K<=F.Last do begin
      A:=Plan.Cues[K];
      Need(not CarSeen[K] and (A.Car=I) and ((A.Action=saFront)=(F.Side=1)),'car contact');
      CarSeen[K]:=True;
      Inc(K,F.Stride);
    end;
    Plan.Cars[I]:=F;
  end;
  for I:=0 to High(Plan.Cues) do Need((Plan.Cues[I].Car>=0)=CarSeen[I],'unlinked car');

  SetLength(Plan.Jumps,Count('jumps',0,Length(Plan.Cues) div 2));
  Previous:=-1;
  for I:=0 to High(Plan.Jumps) do begin
    ReadRow(I,7);
    J:=Default(TSideJump);
    J.First:=IntAt(0,Previous+1,High(Plan.Cues)-1);
    J.Last:=IntAt(1,J.First+1,High(Plan.Cues));
    J.Roof:=IntAt(2,-1,J.Last-1);
    J.Height:=Exact(3,0.50,3.1);
    J.Ramp:=Exact(4,0.20,1.1);
    J.Gap:=Exact(5,0,0.90);
    J.Lift:=Exact(6,0,0.85);
    Need((Plan.Cues[J.Last].Time-Plan.Cues[J.First].Time>=0.57) and
      (Plan.Cues[J.First].Action=saLaunch) and (Plan.Cues[J.Last].Action=saLand),'jump timing');
    if J.Roof>=0 then
      Need((J.Roof>J.First) and (Plan.Cues[J.Roof].Action=saBossRoof) and (J.Gap=0) and
        (Plan.Cues[J.First].Boss=Plan.Cues[J.Roof].Boss) and (Plan.Cues[J.Last].Boss=Plan.Cues[J.Roof].Boss),'cargo landing');
    Plan.Jumps[I]:=J;
    Previous:=J.Last;
  end;
  for I:=0 to High(Plan.Cues) do begin
    A:=Plan.Cues[I];
    if A.Action in [saLaunch,saLand,saRepair,saBossRoof] then begin
      K:=Plan.JumpAt(A.Time);
      Need(K>=0,'unlinked jump cue');
      J:=Plan.Jumps[K];
      case A.Action of
        saLaunch:Need(I=J.First,'jump start');
        saLand:Need(I=J.Last,'jump end');
        saRepair:Need((I>J.First) and (I<J.Last) and (J.Roof<0),'repair must be airborne');
        saBossRoof:Need(I=J.Roof,'roof contact');
      end;
    end;
  end;
  Plan.IndexTrack;
end;

function LoadSideRace(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TSideRacePlan;
var Root,Info:TJSONObject;
begin
  Need(Audio<>nil,'audio');
  Need(Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsSideRace,Ref.Variant),'identity');
  Root:=ReadPreparedData(Ref,rsSideRace,Direction);
  try
    Info:=Root.GetValue<TJSONObject>('audio');
    Need((Info<>nil) and (Info.GetValue<Integer>('events',-1)=Length(Audio.Hits)),'audio events');
    Result:=TSideRacePlan.Create;
    try
      Result.Duration:=ReadPreparedExact(Root.GetValue('duration'));
      Result.Goal:=ReadPreparedExact(Root.GetValue('goal'));
      Need((Abs(Result.Duration-Audio.Duration)<1E-6) and (Result.Goal>0) and
        (Result.Goal<Result.Duration),'duration');
      Parse(Root,Result,Length(Audio.Hits));
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;
end.
