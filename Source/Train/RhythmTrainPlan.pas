unit RhythmTrainPlan;
// 曲から選んだ接触時刻と屋根上の動きを保存する。走行、衝突、カメラも任意の時刻から復元できる。
{$POINTERMATH ON}
interface

uses
  System.SysUtils, RhythmAudio, RhythmPlanRef;

const
  TrainPitch = 12.8;
  TrainCarWidth = 11.86;
  TrainGap = TrainPitch-TrainCarWidth;
  TrainReach = 0.76;
  TrainShotReach = 2.14;
  TrainPlatformY = 2.15;
  TrainBoardX = -2.0;
  TrainRoofViewWidth = 11.7;

type
  TTrainMove = (tmBoard, tmHit, tmVaultHit, tmDuckHit, tmShot, tmJump, tmLeftImpact,
    tmRightImpact, tmCouple, tmTransfer, tmBossJump, tmBossDuck, tmBossFinish, tmStation,
    tmHurdle, tmHurdleHit);
  TTrainCue = record
    Kind: TTrainMove;
    Start, Time, Finish, FromX, ToX: Double;
    Source: Integer;
  end;
  TTrainObstacle = record
    Left, Right, Height: Double;
    Variant: Integer;
  end;
  TTrainPose = record
    X, Y, Run, Crouch, Reach, Land, Kick: Double;
    Airborne: Boolean;
  end;
  TTrainPlan = class
  private
    FCues: TArray<TTrainCue>;
    FDuration, FEndTime: Double;
    FInitialCars, FNextCars, FImpact, FSynced: Integer;
    function GetCount: Integer;
    function GetCue(Index: Integer): TTrainCue;
    function GetLength: Double;
    function GetArrival: Double;
    procedure Verify(Audio: TRhythmAudio);
  public
    class function Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean> = nil): TTrainPlan; static;
    class function Load(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TTrainPlan; static;
    class function LoadAudioMetadata(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio; static;
    procedure Save(var Ref: TRhythmPlanRef; Audio: TRhythmAudio);
    function PoseAt(Time: Double): TTrainPose;
    function RoofY(X: Double): Double;
    function RoofCameraX(Time: Double): Double;
    function RoofObstacle(Car: Integer; out Block: TTrainObstacle): Boolean;
    procedure CollisionCamera(Time: Double; out X, Width, Blend: Double);
    function LeftNoseAt(Time: Double): Double;
    function RightRearAt(Time: Double): Double;
    function TravelAt(Time: Double): Double;
    property Count: Integer read GetCount;
    property Cue[Index: Integer]: TTrainCue read GetCue;
    property InitialCars: Integer read FInitialCars;
    property NextCars: Integer read FNextCars;
    property ImpactIndex: Integer read FImpact;
    property Synced: Integer read FSynced;
    property Arrival: Double read GetArrival;
    property TrainLength: Double read GetLength;
    property EndTime: Double read FEndTime;
  end;

function TrainEase(T: Double): Double;
function TrainThreatTime(const Cue: TTrainCue): Double;
function TrainObstacle(const Cue: TTrainCue; out Block: TTrainObstacle): Boolean;
function TrainRegularEnemy(Kind: TTrainMove): Boolean;

implementation

uses
  System.Math, System.JSON, System.Generics.Collections, RhythmStyles, RhythmPreparedData;

const
  TrainPolicy = 'roof-action-v5';
  HurdleArc = 1.46;
  EarlyBoardSource = -2;
  MaxCues = 72;
  Epsilon = 1E-8;
  CruiseSpeed = 14.8;

function TrainEase(T: Double): Double;
begin
  T := EnsureRange(T, 0.0, 1.0);
  Result := T*T*(3-2*T);
end;

function Ramp(Time, Start, Finish: Double): Double;
begin
  Result := EnsureRange((Time-Start)/Max(Epsilon,Finish-Start),0.0,1.0);
end;

function TrainThreatTime(const Cue: TTrainCue): Double;
begin
  Result := Cue.Start+(Cue.Time-Cue.Start)*0.52;
end;

function TrainRegularEnemy(Kind: TTrainMove): Boolean;
begin
  Result := Kind in [tmHit,tmVaultHit,tmDuckHit,tmShot,tmHurdleHit];
end;

function TrainObstacle(const Cue: TTrainCue; out Block: TTrainObstacle): Boolean;
var Span: Double;
begin
  Block := Default(TTrainObstacle);
  Result := Cue.Kind in [tmHurdle,tmHurdleHit];
  if not Result then Exit;
  Span := Cue.ToX-Cue.FromX;
  Block.Left := Cue.FromX+Span*0.29;
  Block.Right := Cue.FromX+Span*0.62;
  Block.Variant := Floor(Cue.FromX/TrainPitch) mod 3;
  case Block.Variant of
    0: Block.Height := 0.79;
    1: Block.Height := 1.02;
    2: Block.Height := 0.89;
  end;
end;

function TTrainPlan.RoofObstacle(Car: Integer; out Block: TTrainObstacle): Boolean;
var Move: TTrainCue;
begin
  for Move in FCues do
    if (Move.Kind in [tmHurdle,tmHurdleHit]) and (Floor(Move.FromX/TrainPitch)=Car) then
      Exit(TrainObstacle(Move,Block));
  Block := Default(TTrainObstacle);
  Result := False;
end;

function TTrainPlan.RoofCameraX(Time: Double): Double;
var
  C: TTrainCue;
  Start, Finish, NextX: Double;
begin
  Result := 5.91;
  for C in FCues do
    if C.Kind in [tmJump,tmTransfer,tmBossJump] then begin
      Start := C.Start-0.11;
      Finish := C.Time+0.11;
      if Time<=Start then Exit;
      NextX := Floor(C.ToX/TrainPitch)*TrainPitch+5.91;
      if Time<Finish then
        Exit(Result+(NextX-Result)*TrainEase(Ramp(Time,Start,Finish)));
      Result := NextX;
    end;
end;

function TTrainPlan.GetCount: Integer;
begin
  Result := Length(FCues);
end;

function TTrainPlan.GetCue(Index: Integer): TTrainCue;
begin
  Result := FCues[Index];
end;

function TTrainPlan.GetLength: Double;
begin
  Result := (FInitialCars+FNextCars)*TrainPitch-TrainGap;
end;

function TTrainPlan.GetArrival: Double;
begin
  Result := FEndTime;
  if Count>0 then
    Result := FCues[High(FCues)].Time;
end;

function TTrainPlan.RoofY(X: Double): Double;
var
  Car: Integer;
begin
  Car := Floor(X/TrainPitch)-FInitialCars;
  Result := 0;
  if Car>=0 then
    case Car mod 3 of
      0: Result := 0.36;
      1: Result := 0.10;
      2: Result := 0.47;
    end;
end;

function TTrainPlan.TravelAt(Time: Double): Double;
var
  Departure, Brake, Accel, T: Double;
begin
  Departure := 0;
  if Count>0 then Departure := FCues[0].Time;
  Brake := Max(Departure,Arrival-2.1);
  Accel := Min(0.95,Brake-Departure);
  T := EnsureRange(Time-Departure,0.0,Brake-Departure);
  if T<Accel then Result := 0.5*T*T/Accel
  else Result := T-Accel*0.5;
  T := EnsureRange(Time-Brake,0.0,Arrival-Brake);
  Result := CruiseSpeed*(Result+T*(1-0.5*T/Max(Epsilon,Arrival-Brake)));
end;

function TTrainPlan.LeftNoseAt(Time: Double): Double;
var
  Joint, Detach, Contact, SeparationEnd, U: Double;
begin
  Joint := (FInitialCars-1)*TrainPitch-TrainGap;
  Detach := FCues[FImpact-1].Finish;
  Contact := FCues[FImpact].Time;
  SeparationEnd := Detach+(Contact-Detach)*0.43;
  if Time<=SeparationEnd then
    Exit(Joint-4.8*TrainEase(Ramp(Time,Detach,SeparationEnd)));
  if Time<=Contact then begin
    U := Ramp(Time,SeparationEnd,Contact);
    Exit(Joint-4.8*(1-Sqr(U)));
  end;
  Result := Joint-9.2*TrainEase(Ramp(Time,Contact,FCues[FImpact+2].Time+0.19));
end;

function TTrainPlan.RightRearAt(Time: Double): Double;
var
  C: TTrainCue;
  Dock, U: Double;
begin
  C := FCues[FImpact+1];
  Dock := FInitialCars*TrainPitch;
  if Time<=C.Time then begin
    U := Ramp(Time,C.Start,C.Time);
    Exit(Dock+10*(1-Sqr(U)));
  end;
  U := Ramp(Time,C.Time,FCues[FImpact+2].Time);
  Result := Dock+0.96*Sqr(Sin(Pi*U));
end;

procedure TTrainPlan.CollisionCamera(Time: Double; out X, Width, Blend: Double);
var
  LeftTime, RightTime, Gap, Detach, LeftJoint, RightJoint, Hero, Pan, LeftWidth: Double;
begin
  X := 0;
  Width := TrainRoofViewWidth;
  Blend := 0;
  if Count=0 then Exit;
  LeftTime := FCues[FImpact].Time;
  RightTime := FCues[FImpact+1].Time;
  Gap := RightTime-LeftTime;
  Detach := FCues[FImpact-1].Finish;
  Blend := TrainEase(Ramp(Time,Detach,Max(Detach+0.015,LeftTime-0.27)))*
    (1-TrainEase(Ramp(Time,FCues[FImpact+2].Time+0.05,FCues[FImpact+3].Time+0.12)));
  if Blend<=0 then Exit;

  // 衝突の前に、連結器と主人公を同じ画面に収める。左から右への移動も次の接触より先に終える。
  LeftJoint := (FInitialCars-1)*TrainPitch-TrainGap*0.5;
  RightJoint := FInitialCars*TrainPitch-TrainGap*0.5;
  Hero := FCues[FImpact].ToX;
  Pan := TrainEase(Ramp(Time,LeftTime+Min(0.17,Gap*0.27),RightTime-Min(0.26,Gap*0.32)));
  LeftWidth := Max(TrainRoofViewWidth,Hero-LeftJoint+4.7);
  X := (LeftJoint+Hero)*0.5*(1-Pan)+(RightJoint+Hero)*0.5*Pan;
  Width := LeftWidth*(1-Pan)+TrainRoofViewWidth*Pan;
end;

function RoofRunProgress(U: Double): Double;
const
  Blend = 0.12;
begin
  if U<Blend then Exit(Sqr(U)/(2*Blend*(1-Blend)));
  if U>1-Blend then Exit(1-Sqr(1-U)/(2*Blend*(1-Blend)));
  Result := (U-Blend*0.5)/(1-Blend);
end;

function TTrainPlan.PoseAt(Time: Double): TTrainPose;
var
  I, LowIndex, HighIndex, Middle: Integer;
  C: TTrainCue;
  U, Height, Y0, Y1, Displacement, Speed, AttackSpan: Double;
begin
  Result := Default(TTrainPose);
  Result.X := TrainBoardX;
  Result.Y := TrainPlatformY;
  if Count=0 then Exit;
  LowIndex := 0;
  HighIndex := Count;
  while LowIndex<HighIndex do begin
    Middle := (LowIndex+HighIndex) div 2;
    if FCues[Middle].Start<=Time then LowIndex := Middle+1
    else HighIndex := Middle;
  end;
  I := LowIndex-1;
  if I<0 then begin
    U := Ramp(Time,FCues[0].Start-0.19,FCues[0].Start);
    Result.X := TrainBoardX-1.6*(1-TrainEase(U));
    Result.Run := Sin(Pi*U);
    Exit;
  end;
  C := FCues[I];
  Y0 := RoofY(C.FromX);
  Y1 := RoofY(C.ToX);
  if C.Kind=tmBoard then Y0 := TrainPlatformY;
  if C.Kind=tmStation then Y1 := TrainPlatformY;
  if Time>C.Finish then begin
    Result.X := C.ToX;
    Result.Y := Y1;
    if I<High(FCues) then begin
      Displacement := FCues[I+1].FromX-C.ToX;
      U := Ramp(Time,C.Finish,FCues[I+1].Start);
      Result.X := C.ToX+Displacement*RoofRunProgress(U);
      if (Displacement>0.02) and (U>0) and (U<1) then begin
        Speed := Displacement/Max(Epsilon,FCues[I+1].Start-C.Finish);
        Result.Run := EnsureRange(0.63+Speed*0.075,0.0,1.0);
      end;
      Result.Y := RoofY(Result.X);
    end;
    Exit;
  end;
  U := Ramp(Time,C.Start,C.Time);
  Height := 0;
  case C.Kind of
    tmBoard: Height := 1.48;
    tmVaultHit: Height := 1.02;
    tmHurdle,tmHurdleHit: Height := HurdleArc;
    tmJump: Height := 0.94;
    tmTransfer: Height := 1.19;
    tmBossJump: Height := 1.45;
    tmStation: Height := 0.76;
  end;
  if Height>0 then begin
    Result.X := C.FromX+(C.ToX-C.FromX)*U;
    Result.Y := Y0+(Y1-Y0)*U-4*Height*U*(1-U);
    Result.Airborne := (U>0) and (U<1);
    if Time>=C.Time then
      Result.Land := Max(0.0,1-(Time-C.Time)/0.12);
    Result.Crouch := 0.54*Result.Land;
  end
  else begin
    Result.X := C.FromX+(C.ToX-C.FromX)*TrainEase(U);
    Result.Y := Y1;
    if (C.ToX-C.FromX>0.12) and (U<0.81) then
      Result.Run := 0.77*TrainEase((0.81-U)/0.32);
  end;
  if (Time>=C.Time) and (C.Kind in [tmLeftImpact,tmRightImpact]) then
    Result.Crouch := 0.57*Max(0.0,1-(Time-C.Time)/0.11);
  if C.Kind in [tmDuckHit,tmBossDuck] then
    Result.Crouch := Sqr(Sin(Pi*U))*0.88;
  if TrainRegularEnemy(C.Kind) or (C.Kind in [tmBossDuck,tmBossFinish]) then begin
    AttackSpan := Min(0.085,(C.Time-C.Start)*0.54);
    if C.Kind in [tmShot,tmBossFinish] then AttackSpan := Min(0.17,(C.Time-C.Start)*0.73);
    if Time>=C.Time then AttackSpan := 0.12;
    Result.Reach := Max(0.0,1-Abs(Time-C.Time)/Max(Epsilon,AttackSpan));
    if C.Kind in [tmVaultHit,tmHurdleHit] then Result.Kick := Result.Reach;
  end;
end;

procedure TTrainPlan.Verify(Audio: TRhythmAudio);
var
  I, LastSource: Integer;
  Previous, Span, Edge, Clearance: Double;
  C: TTrainCue;
  Block: TTrainObstacle;
begin
  if IsNan(FDuration) or IsInfinite(FDuration) or (FDuration<=0) or
     IsNan(FEndTime) or IsInfinite(FEndTime) or (FEndTime<0) or
     (FEndTime>Max(10.0,FDuration+1.4)) or (FInitialCars<2) or (FInitialCars>8) or
     (FNextCars<2) or (FNextCars>6) or (Count>MaxCues) then
    raise EConvertError.Create('Train plan bounds');
  FSynced := 0;
  FImpact := -1;
  if Count=0 then Exit;
  Previous := -1;
  LastSource := -1;
  for I := 0 to High(FCues) do begin
    C := FCues[I];
    if (C.Start<=Previous) or (C.Start<0) or (C.Time<=C.Start) or (C.Finish<C.Time) or
       (C.Finish>FEndTime) or (C.FromX<TrainBoardX) or (C.ToX<C.FromX) or
       (C.ToX>TrainLength+1.3) or ((I>0) and (C.FromX+Epsilon<FCues[I-1].ToX)) then
      raise EConvertError.Create('Train move bounds');
    if TrainObstacle(C,Block) then begin
      Span := C.ToX-C.FromX;
      if (Span<2.2) or (Floor(C.FromX/TrainPitch)<>Floor(C.ToX/TrainPitch)) or
         (C.ToX-Floor(C.ToX/TrainPitch)*TrainPitch>=TrainCarWidth) then
        raise EConvertError.Create('Train obstacle course');
      Edge := (Block.Left-C.FromX)/Span;
      Clearance := 4*HurdleArc*Edge*(1-Edge);
      Edge := (Block.Right-C.FromX)/Span;
      Clearance := Min(Clearance,4*HurdleArc*Edge*(1-Edge));
      if Clearance<Block.Height+0.12 then
        raise EConvertError.Create('Train obstacle clearance');
    end;
    Previous := C.Finish;
    if C.Kind=tmLeftImpact then FImpact := I;
    if C.Source=EarlyBoardSource then begin
      if (I<>0) or (C.Kind<>tmBoard) or (C.Time<0.45) or (C.Time>0.76) then
        raise EConvertError.Create('Train departure onset');
      Inc(FSynced);
    end
    else if C.Source<>-1 then begin
      if (C.Source<=LastSource) or (C.Source>=Length(Audio.Hits)) or
         (Abs(C.Time-Audio.Hits[C.Source].Time)>0.065) then
        raise EConvertError.Create('Train accent reference');
      LastSource := C.Source;
      Inc(FSynced);
    end;
  end;
  if (FImpact<2) or (FImpact+5>=High(FCues)) or (FCues[0].Kind<>tmBoard) or (FCues[0].Time>0.82) or
     (FCues[FImpact+1].Kind<>tmRightImpact) or (FCues[FImpact+2].Kind<>tmCouple) or
     (FCues[FImpact+3].Kind<>tmTransfer) or (FCues[High(FCues)-1].Kind<>tmBossFinish) or
     (FCues[High(FCues)].Kind<>tmStation) then
    raise EConvertError.Create('Train phase order');
end;

type
  TTrainTimingChoice = record
    Time, Merit, Total: Double;
    Source, Previous: Integer;
  end;

function FindTrainOnset(Audio: TRhythmAudio; Start, MinimumRise: Double; Windows: Integer): Double;
const
  Hop = 176; // 約4 ms
var
  Frames, FirstFrame, I, J, Addr: Integer;
  Samples: PSmallInt;
  Energy: TArray<Double>;
  L, R, Rise, Best: Double;
begin
  Result := -1;
  Frames := Length(Audio.PCM) div 4;
  FirstFrame := Round(Start*RHYTHM_RATE)-3*Hop;
  if (FirstFrame<0) or (FirstFrame+(Windows+3)*Hop>Frames) then Exit;
  SetLength(Energy,Windows+3);
  Samples := Pointer(Audio.PCM);
  for I := 0 to High(Energy) do begin
    Energy[I] := 0;
    for J := 0 to Hop-1 do begin
      Addr := (FirstFrame+I*Hop+J)*4;
      L := PSmallInt(PByte(Samples)+Addr)^/32768.0;
      R := PSmallInt(PByte(Samples)+Addr+2)^/32768.0;
      Energy[I] := Energy[I]+Sqr(L)+Sqr(R);
    end;
    Energy[I] := Sqrt(Energy[I]/(2*Hop));
  end;
  Best := MinimumRise;
  for I := 3 to High(Energy) do begin
    Rise := Energy[I]-(Energy[I-1]+Energy[I-2]+Energy[I-3])/3;
    if Rise>Best then begin
      Best := Rise;
      Result := (FirstFrame+I*Hop+Hop*0.35)/RHYTHM_RATE;
    end;
  end;
end;

procedure ScheduleTrainCues(Cues: TList<TTrainCue>; Audio: TRhythmAudio; EndTarget: Double;
  const Cancel: TFunc<Boolean>);
const
  CandidateLimit = 32;
  Unreachable = -1E20;
var
  Targets: TArray<Double>;
  Choices: TArray<TArray<TTrainTimingChoice>>;
  Options: TList<TTrainTimingChoice>;
  Entry, Prior: TTrainTimingChoice;
  Move: TTrainCue;
  I,J,K,Cursor,Worst,Winner: Integer;
  Sum,TimeScale,Clock,Target,Window,RangeStart,RangeEnd,Spacing,Time,Strength,Emphasis,Total: Double;
begin
  Sum := 0;
  for Move in Cues do Sum := Sum+Move.Time;
  TimeScale := EndTarget/Sum;
  SetLength(Targets,Cues.Count);
  SetLength(Choices,Cues.Count);
  Clock := 0;
  Options := TList<TTrainTimingChoice>.Create;
  try
    for I := 0 to Cues.Count-1 do begin
      if Assigned(Cancel) and Cancel() then Abort;
      Move := Cues[I];
      Clock := Clock+Move.Time*TimeScale;
      Target := Clock;
      if Move.Kind=tmBoard then Target := 0.56;
      Targets[I] := Target;
      Emphasis := 1.15;
      Window := Min(2.45,Max(0.68,1.55*Move.Time*TimeScale));
      case Move.Kind of
        tmBoard,tmLeftImpact,tmRightImpact,tmCouple,tmBossFinish:
          begin Emphasis := 2.2; Window := Min(3.2,Window+0.72); end;
        tmHit,tmVaultHit,tmDuckHit,tmShot,tmHurdleHit,tmBossDuck: Emphasis := 1.62;
      end;
      RangeStart := Max(0.32,Target-Window);
      RangeEnd := Min(Audio.Duration,Target+Window);
      if Move.Kind=tmBoard then begin
        RangeStart := 0.40;
        RangeEnd := Min(0.75,RangeEnd);
      end;
      Options.Clear;
      Entry := Default(TTrainTimingChoice);
      Entry.Time := Target;
      Entry.Source := -1;
      Entry.Merit := -0.37*Emphasis;
      Options.Add(Entry);
      if Move.Kind=tmBoard then begin
        Time := FindTrainOnset(Audio,0.45,0.004,75);
        if Time>=0.45 then begin
          Entry.Time := Time;
          Entry.Source := EarlyBoardSource;
          Entry.Merit := 0.48;
          Options.Add(Entry);
        end;
      end;
      Cursor := Audio.NearestHit(RangeStart);
      while (Cursor>=0) and (Cursor<Length(Audio.Hits)) and (Audio.Hits[Cursor].Time<=RangeEnd) do begin
        if ((Cursor and 511)=0) and Assigned(Cancel) and Cancel() then Abort;
        Time := Audio.Hits[Cursor].Time;
        if Time>=RangeStart then begin
          Strength := Audio.Hits[Cursor].Strength;
          Entry.Time := Time;
          Entry.Source := Cursor;
          Entry.Merit := 0.46+Emphasis*Strength-0.83*Abs(Time-Target)/Window;
          if Options.Count<=CandidateLimit then Options.Add(Entry)
          else begin
            Worst := 1;
            for K := 2 to Options.Count-1 do
              if Options[K].Merit<Options[Worst].Merit then Worst := K;
            if Entry.Merit>Options[Worst].Merit then Options[Worst] := Entry;
          end;
        end;
        Inc(Cursor);
      end;
      Choices[I] := Options.ToArray;
      Spacing := 0.0;
      if I>0 then begin
        Spacing := Min(0.38,(Targets[I]-Targets[I-1])*0.56);
        if Move.Kind in [tmLeftImpact,tmRightImpact,tmCouple,tmTransfer] then
          Spacing := Min(0.53,(Targets[I]-Targets[I-1])*0.62);
      end;
      for J := 0 to High(Choices[I]) do begin
        Entry := Choices[I][J];
        Entry.Previous := -1;
        Entry.Total := Entry.Merit;
        if I>0 then begin
          Entry.Total := Unreachable;
          for K := 0 to High(Choices[I-1]) do begin
            Prior := Choices[I-1][K];
            Total := Prior.Total+Entry.Merit;
            if (Prior.Time+Spacing<=Entry.Time) and (Total>Entry.Total) then begin
              Entry.Previous := K;
              Entry.Total := Total;
            end;
          end;
        end;
        Choices[I][J] := Entry;
      end;
    end;
  finally
    Options.Free;
  end;

  I := Cues.Count-1;
  Winner := 0;
  for J := 1 to High(Choices[I]) do
    if Choices[I][J].Total>Choices[I][Winner].Total then Winner := J;
  while I>=0 do begin
    Entry := Choices[I][Winner];
    Move := Cues[I];
    Move.Time := Entry.Time;
    Move.Source := Entry.Source;
    Cues[I] := Move;
    Winner := Entry.Previous;
    Dec(I);
  end;

  // 共通解析の候補を選んだ後、使用するPCMで直近の立ち上がりへ寄せる。
  // PCMがない合成音テストや復元では参照・保存した時刻をそのまま使う。
  for I := 0 to Cues.Count-1 do begin
    Move := Cues[I];
    if Move.Source<0 then Continue;
    Time := FindTrainOnset(Audio,Audio.Hits[Move.Source].Time-0.052,0.0012,17);
    RangeEnd := Audio.Duration;
    if I=0 then begin
      RangeStart := 0.37;
      RangeEnd := Min(0.81,RangeEnd);
    end
    else RangeStart := Cues[I-1].Time+0.16;
    if I<Cues.Count-1 then RangeEnd := Min(RangeEnd,Cues[I+1].Time-0.16);
    if (Time>=RangeStart) and (Time<=RangeEnd) then Move.Time := Time;
    Cues[I] := Move;
  end;
end;

class function TTrainPlan.Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TTrainPlan;
var
  Cues: TList<TTrainCue>;
  Plan: TTrainPlan;
  C: TTrainCue;
  I, Car, TotalCars: Integer;
  Clock, Gap, Time, EndTarget, Lead, Tail: Double;
  FullRoof: Boolean;

  procedure CheckCancel;
  begin
    if Assigned(Cancel) and Cancel() then Abort;
  end;

  procedure Add(Kind: TTrainMove; Weight, FromX, ToX: Double);
  var
    Move: TTrainCue;
  begin
    Move := Default(TTrainCue);
    Move.Kind := Kind;
    Move.Time := Weight;
    Move.FromX := FromX;
    Move.ToX := ToX;
    Move.Source := -1;
    Cues.Add(Move);
  end;

  procedure Jump(Kind: TTrainMove; CarIndex: Integer; Weight, Land: Double);
  var
    X: Double;
  begin
    X := CarIndex*TrainPitch;
    Add(Kind,Weight,X-TrainGap-0.57,X+Land);
  end;

  procedure Fight(Kind: TTrainMove; CarIndex: Integer; X: Double);
  const
    Travel: array[tmHit..tmShot] of Double = (0.94,1.97,1.65,0.92);
  begin
    X := CarIndex*TrainPitch+X;
    Add(Kind,0.98,X-Travel[Kind],X);
  end;

  procedure RoofEncounter(CarIndex: Integer);
  var X: Double;
  begin
    X := CarIndex*TrainPitch;
    if (CarIndex mod 3=1) and (CarIndex>0) then Fight(tmDuckHit,CarIndex,2.85)
    else Fight(tmHit,CarIndex,2.85);
    if not FullRoof or Odd(CarIndex) then
      Add(tmHurdleHit,1.02,X+4.28,X+7.52)
    else Add(tmHurdle,0.90,X+4.27,X+7.39);
    if not FullRoof then Exit;
    if CarIndex mod 3=1 then Fight(tmShot,CarIndex,9.26)
    else if CarIndex mod 3=2 then Fight(tmVaultHit,CarIndex,10.21)
    else Fight(tmDuckHit,CarIndex,9.56);
  end;

begin
  CheckCancel;
  if (Audio=nil) or (Audio.Duration<=0) or IsNan(Audio.Duration) or IsInfinite(Audio.Duration) or
     (Length(Audio.Hits)>100000) then
    raise EArgumentException.Create('Train audio bounds');
  Plan := TTrainPlan.Create;
  Cues := nil;
  try
    Plan.FDuration := Audio.Duration;
    Plan.FInitialCars := EnsureRange(2+Floor(Min(6.0,Audio.SoundEnd/11)),2,8);
    Plan.FNextCars := EnsureRange(2+Floor(Min(4.0,Audio.SoundEnd/21)),2,6);
    Plan.FEndTime := Audio.Duration;
    if (Audio.SoundEnd>0) and (Audio.Duration>=0.8) then begin
      Cues := TList<TTrainCue>.Create;
      TotalCars := Plan.InitialCars+Plan.NextCars;
      FullRoof := Audio.SoundEnd>=14;
      Add(tmBoard,0.72,TrainBoardX,0.73);
      for Car := 0 to Plan.InitialCars-1 do begin
        if Car>0 then Jump(tmJump,Car,0.83,0.60);
        RoofEncounter(Car);
      end;
      Time := Cues.Last.ToX+0.36;
      Add(tmLeftImpact,2.39,Time,Time);
      Add(tmRightImpact,1.34,Time,Time);
      Add(tmCouple,1.42,Time,Time);
      Jump(tmTransfer,Plan.InitialCars,0.92,0.70);
      for Car := Plan.InitialCars to TotalCars-2 do begin
        if Car>Plan.InitialCars then Jump(tmJump,Car,0.78,0.43);
        RoofEncounter(Car);
      end;
      Car := TotalCars-1;
      Jump(tmBossJump,Car,1.04,0.44);
      Add(tmBossDuck,1.10,Car*TrainPitch+2.45,Car*TrainPitch+4.30);
      Add(tmBossFinish,1.26,Car*TrainPitch+6.35,Car*TrainPitch+8.64);
      Add(tmStation,2.00,Plan.TrainLength-0.45,Plan.TrainLength+1.10);

      EndTarget := Max(8.50,Audio.SoundEnd+0.13);
      ScheduleTrainCues(Cues,Audio,EndTarget,Cancel);
      for I := 0 to Cues.Count-1 do begin
        C := Cues[I];
        Clock := 0;
        if I>0 then Clock := Cues[I-1].Time;
        Gap := C.Time-Clock;
        case C.Kind of
          tmBoard: Lead := 0.36;
          tmJump,tmTransfer,tmBossJump: Lead := 0.58;
          tmHit,tmBossFinish: Lead := 0.28;
          tmVaultHit,tmDuckHit,tmBossDuck: Lead := 0.48;
          tmHurdle,tmHurdleHit: Lead := 0.57;
          tmShot: Lead := 0.34;
          tmLeftImpact,tmRightImpact: Lead := 1.22;
          tmCouple: Lead := 0.48;
          tmStation: Lead := 0.65;
        else
          Lead := 0.50;
        end;
        C.Start := C.Time-Min(Lead,Gap*0.60);
        Tail := 0.051;
        if C.Kind in [tmLeftImpact,tmRightImpact,tmCouple,tmStation] then Tail := 0.12;
        if I<Cues.Count-1 then Tail := Min(Tail,(Cues[I+1].Time-C.Time)*0.18);
        C.Finish := C.Time+Tail;
        Cues[I] := C;
      end;
      Plan.FCues := Cues.ToArray;
      Plan.FEndTime := Plan.FCues[High(Plan.FCues)].Time+0.83;
    end;
    Plan.Verify(Audio);
    Result := Plan;
    Plan := nil;
  finally
    Cues.Free;
    Plan.Free;
  end;
end;

procedure TTrainPlan.Save(var Ref: TRhythmPlanRef; Audio: TRhythmAudio);
var
  Root: TJSONObject;
  Rows, Row: TJSONArray;
  C: TTrainCue;
begin
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsTrain,0) then
    raise EArgumentException.Create('Train reference');
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style',StyleId(rsTrain));
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    Root.AddPair('policy',TrainPolicy);
    Root.AddPair('end',PreparedExact(FEndTime));
    Root.AddPair('initialCars',TJSONNumber.Create(FInitialCars));
    Root.AddPair('nextCars',TJSONNumber.Create(FNextCars));
    AddPreparedAudio(Root,Audio);
    Rows := TJSONArray.Create;
    Root.AddPair('cues',Rows);
    for C in FCues do begin
      Row := TJSONArray.Create;
      Rows.AddElement(Row);
      Row.Add(Ord(C.Kind));
      Row.Add(C.Source);
      Row.AddElement(PreparedExact(C.Start));
      Row.AddElement(PreparedExact(C.Time));
      Row.AddElement(PreparedExact(C.Finish));
      Row.AddElement(PreparedExact(C.FromX));
      Row.AddElement(PreparedExact(C.ToX));
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

class function TTrainPlan.LoadAudioMetadata(const Ref: TRhythmPlanRef; const Source: string; Direction: Integer): TRhythmAudio;
var
  Root: TJSONObject;
begin
  Root := ReadPreparedData(Ref,rsTrain,Direction);
  try
    if Root.GetValue<string>('policy','')<>TrainPolicy then raise EConvertError.Create('Train plan policy');
    Result := PreparedAudio(Root,Ref,Source);
  finally
    Root.Free;
  end;
end;

class function TTrainPlan.Load(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TTrainPlan;
var
  Root, Info: TJSONObject;
  Rows, Row: TJSONArray;
  I, Kind: Integer;
  Plan: TTrainPlan;
begin
  if (Audio=nil) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsTrain,0) then
    raise EArgumentException.Create('屋上アクションを準備して適用してください。');
  Root := ReadPreparedData(Ref,rsTrain,Direction);
  Plan := nil;
  try
    if Root.GetValue<string>('policy','')<>TrainPolicy then raise EConvertError.Create('Train plan policy');
    Info := Root.GetValue<TJSONObject>('audio');
    Rows := Root.GetValue<TJSONArray>('cues');
    if (Info=nil) or (Info.GetValue<Integer>('events')<>Length(Audio.Hits)) or
       (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>Epsilon) or
       (Rows=nil) or (Rows.Count>MaxCues) then
      raise EConvertError.Create('Train audio identity');
    Plan := TTrainPlan.Create;
    Plan.FDuration := Audio.Duration;
    Plan.FEndTime := ReadPreparedExact(Root.GetValue('end'));
    Plan.FInitialCars := Root.GetValue<Integer>('initialCars');
    Plan.FNextCars := Root.GetValue<Integer>('nextCars');
    SetLength(Plan.FCues,Rows.Count);
    for I := 0 to Rows.Count-1 do begin
      if not (Rows.Items[I] is TJSONArray) then raise EConvertError.Create('Train cue row');
      Row := TJSONArray(Rows.Items[I]);
      if Row.Count<>7 then raise EConvertError.Create('Train cue columns');
      Kind := Row.Items[0].GetValue<Integer>;
      if (Kind<Ord(Low(TTrainMove))) or (Kind>Ord(High(TTrainMove))) then
        raise EConvertError.Create('Train cue kind');
      Plan.FCues[I].Kind := TTrainMove(Kind);
      Plan.FCues[I].Source := Row.Items[1].GetValue<Integer>;
      Plan.FCues[I].Start := ReadPreparedExact(Row.Items[2]);
      Plan.FCues[I].Time := ReadPreparedExact(Row.Items[3]);
      Plan.FCues[I].Finish := ReadPreparedExact(Row.Items[4]);
      Plan.FCues[I].FromX := ReadPreparedExact(Row.Items[5]);
      Plan.FCues[I].ToX := ReadPreparedExact(Row.Items[6]);
    end;
    Plan.Verify(Audio);
    Result := Plan;
    Plan := nil;
  finally
    Plan.Free;
    Root.Free;
  end;
end;

end.
