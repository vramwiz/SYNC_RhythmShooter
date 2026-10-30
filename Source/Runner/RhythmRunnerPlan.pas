unit RhythmRunnerPlan;
// Absolute-time course: accents are foot contacts, not physics simulation ticks.
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef;
const RUN_SPEED=0.42;RUN_GRAVITY=3.8;RUN_EXIT=1.60;
type
  TRunnerStep=record Time,Y,Takeoff,StartY,Velocity,Strength:Double;end;
  TRunnerPlatform=record Left,Right,Y:Double;end;
  TRunnerPulse=record Time,Strength:Double;Step:Integer;end;
  TRunnerPoint=record X,Y:Double;Airborne:Boolean;end;
  TRunnerPlan=class
  private
    FSteps:TArray<TRunnerStep>;FPlatforms:TArray<TRunnerPlatform>;FPulses:TArray<TRunnerPulse>;
    FGoal:Double;FExcluded:Integer;
    procedure MakeCourse;
    function GetCount:Integer;
    function GetStep(I:Integer):TRunnerStep;
    function GetPlatformCount:Integer;
    function GetPlatform(I:Integer):TRunnerPlatform;
    function GetPulseCount:Integer;
    function GetPulse(I:Integer):TRunnerPulse;
    function GetEnd:Double;
  public
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TRunnerPlan;static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRunnerPlan;static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;static;
    function StepBefore(Time:Double):Integer;
    function PulseBefore(Time:Double):Integer;
    function PositionAt(Time:Double):TRunnerPoint;
    function EntryDuration:Double;
    function FirstPlatform(X:Double):Integer;
    property Count:Integer read GetCount;
    property Step[I:Integer]:TRunnerStep read GetStep;
    property PlatformCount:Integer read GetPlatformCount;
    property Platform[I:Integer]:TRunnerPlatform read GetPlatform;
    property PulseCount:Integer read GetPulseCount;
    property Pulse[I:Integer]:TRunnerPulse read GetPulse;
    property GoalTime:Double read FGoal;
    property EndTime:Double read GetEnd;
    property ExcludedCount:Integer read FExcluded;
  end;
implementation
uses System.Math,System.JSON,System.Generics.Collections,RhythmStyles,RhythmPreparedData;
function Finite(V:Double):Boolean;begin Result:=not IsNan(V) and not IsInfinite(V);end;
function NewStep(const Previous:TRunnerStep;Time,Strength:Double;Index:Integer):TRunnerStep;
var Gap,D,Desired,Limit:Double;
begin
  Result:=Default(TRunnerStep);Result.Time:=Time;Result.Strength:=Strength;Result.StartY:=Previous.Y;Result.Y:=Previous.Y;
  Gap:=Time-Previous.Time;D:=0;if Gap>=0.16 then D:=Min(0.82,Gap-0.045);
  Result.Takeoff:=Time-D;if D=0 then Exit;
  // Dense accents become low hops. Height changes only when flight time allows
  // both upward departure and downward arrival on the target platform.
  if D>=0.26 then begin
    case (Index div 4) mod 3 of
      0:Desired:=Previous.Y-0.055;
      1:Desired:=0.60+0.11*Sin(Index*1.37);
    else Desired:=Previous.Y+0.050;end;
    Limit:=Min(0.10,0.15*RUN_GRAVITY*D*D);Result.Y:=EnsureRange(Previous.Y+EnsureRange(Desired-Previous.Y,-Limit,Limit),0.52,0.78);
  end;
  Result.Velocity:=(Result.Y-Previous.Y)/D-0.5*RUN_GRAVITY*D;
end;
class function TRunnerPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRunnerPlan;
var Steps:TList<TRunnerStep>;Pulses:TList<TRunnerPulse>;S:TRunnerStep;P:TRunnerPulse;I:Integer;Last:Double;
  procedure Check;begin if Assigned(Cancel) and Cancel() then Abort;end;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');Check;
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) then raise Exception.Create('Invalid runner audio bounds');
  Result:=TRunnerPlan.Create;Steps:=nil;Pulses:=nil;
  try
    Steps:=TList<TRunnerStep>.Create;Pulses:=TList<TRunnerPulse>.Create;
    Result.FGoal:=Audio.SoundEnd;
    S:=Default(TRunnerStep);S.Y:=0.72;S.StartY:=S.Y;Steps.Add(S);Last:=-1;
    for I:=0 to High(Audio.Hits) do begin
      Check;
      if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or (Audio.Hits[I].Time<0) or
        (Audio.Hits[I].Time<Last) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('Invalid runner accent');
      Last:=Audio.Hits[I].Time;
      if (Audio.SoundEnd<=0) or (Last>Audio.SoundEnd+1E-6) then begin Inc(Result.FExcluded);Continue;end;
      if Pulses.Count>=100000 then raise Exception.Create('ランナーの音イベント数が上限です。');
      if Last>Steps[Steps.Count-1].Time then begin
        if Steps.Count>=20000 then raise Exception.Create('ランナーの着地点数が上限です。');
        S:=NewStep(Steps[Steps.Count-1],Last,EnsureRange(Audio.Hits[I].Strength,0.0,1.0),Steps.Count);Steps.Add(S);
      end;
      P.Time:=Last;P.Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);P.Step:=Steps.Count-1;Pulses.Add(P);
    end;
    if Result.FGoal>Steps[Steps.Count-1].Time then Steps.Add(NewStep(Steps[Steps.Count-1],Result.FGoal,0.8,Steps.Count));
    Result.FSteps:=Steps.ToArray;Result.FPulses:=Pulses.ToArray;Result.MakeCourse;
  except Result.Free;Steps.Free;Pulses.Free;raise;end;Steps.Free;Pulses.Free;
end;
procedure TRunnerPlan.MakeCourse;
var List:TList<TRunnerPlatform>;P,Previous:TRunnerPlatform;I:Integer;D,Lead:Double;
begin
  List:=TList<TRunnerPlatform>.Create;
  try
    for I:=0 to High(FSteps) do begin
      Lead:=0.04;if I>0 then begin D:=FSteps[I].Time-FSteps[I].Takeoff;if D>0 then Lead:=Max(0.004,Min(0.065,RUN_SPEED*D*0.18));end;
      P.Left:=RUN_SPEED*FSteps[I].Time-Lead;if I=0 then P.Left:=-2;
      P.Y:=FSteps[I].Y;
      if I<High(FSteps) then P.Right:=RUN_SPEED*FSteps[I+1].Takeoff+0.006
      else P.Right:=RUN_SPEED*FGoal+3;
      P.Right:=Max(P.Right,P.Left+0.018);
      if List.Count>0 then begin
        Previous:=List[List.Count-1];
        if (Abs(P.Y-Previous.Y)<1E-9) and (P.Left<=Previous.Right+1E-9) then begin
          Previous.Right:=Max(Previous.Right,P.Right);List[List.Count-1]:=Previous;Continue;
        end;
      end;List.Add(P);
    end;FPlatforms:=List.ToArray;
  finally List.Free;end;
end;
function TRunnerPlan.GetCount:Integer;begin Result:=Length(FSteps);end;
function TRunnerPlan.GetStep(I:Integer):TRunnerStep;begin Result:=FSteps[I];end;
function TRunnerPlan.GetPlatformCount:Integer;begin Result:=Length(FPlatforms);end;
function TRunnerPlan.GetPlatform(I:Integer):TRunnerPlatform;begin Result:=FPlatforms[I];end;
function TRunnerPlan.GetPulseCount:Integer;begin Result:=Length(FPulses);end;
function TRunnerPlan.GetPulse(I:Integer):TRunnerPulse;begin Result:=FPulses[I];end;
function TRunnerPlan.GetEnd:Double;begin Result:=0;if FGoal>0 then Result:=FGoal+RUN_EXIT;end;
function TRunnerPlan.StepBefore(Time:Double):Integer;
var A,B,M:Integer;
begin A:=0;B:=Count;while A<B do begin M:=(A+B) div 2;if FSteps[M].Time<=Time then A:=M+1 else B:=M;end;Result:=Max(0,A-1);end;
function TRunnerPlan.PulseBefore(Time:Double):Integer;
var A,B,M:Integer;
begin A:=0;B:=PulseCount;while A<B do begin M:=(A+B) div 2;if FPulses[M].Time<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
function TRunnerPlan.PositionAt(Time:Double):TRunnerPoint;
var I:Integer;S:TRunnerStep;T,Age:Double;
begin
  Time:=EnsureRange(Time,0.0,EndTime);I:=StepBefore(Min(Time,FGoal));Result.X:=RUN_SPEED*Time;Result.Y:=FSteps[I].Y;Result.Airborne:=False;
  if Time>FGoal then begin Age:=Time-FGoal;Result.X:=RUN_SPEED*FGoal+RUN_SPEED*Age+1.5*Sqr(Max(0.0,Age-0.25));Exit;end;
  if I<Count-1 then begin
    S:=FSteps[I+1];
    if (S.Takeoff<S.Time) and (Time>S.Takeoff) then begin
      T:=Time-S.Takeoff;Result.Y:=S.StartY+S.Velocity*T+0.5*RUN_GRAVITY*T*T;Result.Airborne:=True;
    end;
  end;
end;
function TRunnerPlan.EntryDuration:Double;
begin Result:=0;if (PulseCount>0) and (FPulses[0].Time<0.65) then Exit;if Count>1 then if FSteps[1].Takeoff>=0.65 then Result:=Min(0.60,FSteps[1].Takeoff-0.05);end;
function TRunnerPlan.FirstPlatform(X:Double):Integer;
var A,B,M:Integer;
begin A:=0;B:=PlatformCount;while A<B do begin M:=(A+B) div 2;if FPlatforms[M].Right<X then A:=M+1 else B:=M;end;Result:=A;end;
procedure TRunnerPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var Root,J:TJSONObject;Items:TJSONArray;S:TRunnerStep;P:TRunnerPulse;
begin
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsRunner) then raise Exception.Create('Invalid runner reference');
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','runner');Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);Root.AddPair('source',Ref.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root,Audio);Root.AddPair('goal',TJSONNumber.Create(FGoal));Root.AddPair('excluded',TJSONNumber.Create(FExcluded));
    Items:=TJSONArray.Create;Root.AddPair('steps',Items);
    for S in FSteps do begin
      J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(S.Time));J.AddPair('y',TJSONNumber.Create(S.Y));
      J.AddPair('takeoff',TJSONNumber.Create(S.Takeoff));J.AddPair('startY',TJSONNumber.Create(S.StartY));J.AddPair('velocity',TJSONNumber.Create(S.Velocity));J.AddPair('strength',TJSONNumber.Create(S.Strength));
    end;
    Items:=TJSONArray.Create;Root.AddPair('pulses',Items);
    for P in FPulses do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(P.Time));J.AddPair('strength',TJSONNumber.Create(P.Strength));J.AddPair('step',TJSONNumber.Create(P.Step));end;
    WritePreparedData(Root,Ref);
  finally Root.Free;end;
end;
class function TRunnerPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin Root:=ReadPreparedData(Ref,rsRunner,Direction);try Result:=PreparedAudio(Root,Ref,Source);finally Root.Free;end;end;
class function TRunnerPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRunnerPlan;
var Root,J,Info:TJSONObject;Items:TJSONArray;I:Integer;S,Expected:TRunnerStep;P:TRunnerPulse;D:Double;
begin
  Result:=nil;if Audio=nil then raise Exception.Create('Runner audio metadata missing');
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsRunner) then raise Exception.Create('Runner settings mismatch');
  Root:=ReadPreparedData(Ref,rsRunner,Direction);
  try
    try
      Info:=Root.GetValue<TJSONObject>('audio');if (Info=nil) or not Finite(Info.GetValue<Double>('duration')) or not Finite(Info.GetValue<Double>('soundEnd')) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or
        (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-6) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-6) then raise Exception.Create('Runner audio identity mismatch');
      Result:=TRunnerPlan.Create;Result.FGoal:=Root.GetValue<Double>('goal');Result.FExcluded:=Root.GetValue<Integer>('excluded',0);
      if not Finite(Result.FGoal) or (Abs(Result.FGoal-Audio.SoundEnd)>1E-6) or (Result.FGoal<0) or (Result.FGoal>Audio.Duration) or (Result.FExcluded<0) then raise Exception.Create('Invalid runner goal');
      
      Items:=Root.GetValue<TJSONArray>('steps');if (Items=nil) or (Items.Count<1) or (Items.Count>20001) then raise Exception.Create('Invalid runner step count');
      SetLength(Result.FSteps,Items.Count);
      for I:=0 to Items.Count-1 do begin
        if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid runner step');J:=TJSONObject(Items.Items[I]);
        S.Time:=J.GetValue<Double>('time');S.Y:=J.GetValue<Double>('y');S.Takeoff:=J.GetValue<Double>('takeoff');S.StartY:=J.GetValue<Double>('startY');S.Velocity:=J.GetValue<Double>('velocity');S.Strength:=J.GetValue<Double>('strength');
        if not Finite(S.Time) or not Finite(S.Y) or not Finite(S.Takeoff) or not Finite(S.StartY) or not Finite(S.Velocity) or not Finite(S.Strength) or
          (S.Time<0) or (S.Time>Result.FGoal+1E-6) or (S.Y<0.51) or (S.Y>0.79) or (S.Strength<0) or (S.Strength>1) then raise Exception.Create('Runner step out of bounds');
        if I=0 then begin if (S.Time<>0) or (S.Takeoff<>0) or (Abs(S.Y-0.72)>1E-8) or (S.Velocity<>0) then raise Exception.Create('Invalid runner start');end
        else begin
          Expected:=NewStep(Result.FSteps[I-1],S.Time,S.Strength,I);
          if (S.Time<=Result.FSteps[I-1].Time) or (S.Takeoff<Result.FSteps[I-1].Time) or
            (Abs(S.Y-Expected.Y)>1E-7) or (Abs(S.Takeoff-Expected.Takeoff)>1E-7) or
            (Abs(S.StartY-Expected.StartY)>1E-7) or (Abs(S.Velocity-Expected.Velocity)>1E-7) then raise Exception.Create('Runner ballistic contact mismatch');
          D:=S.Time-S.Takeoff;
          if (D>0) and ((S.Velocity>=0) or (S.Velocity+RUN_GRAVITY*D<=0)) then raise Exception.Create('Runner jump does not land downward');
        end;Result.FSteps[I]:=S;
      end;
      if Abs(Result.FSteps[Result.Count-1].Time-Result.FGoal)>1E-6 then raise Exception.Create('Runner goal contact missing');
      Items:=Root.GetValue<TJSONArray>('pulses');if (Items=nil) or (Items.Count>100000) or (Items.Count+Result.FExcluded<>Length(Audio.Hits)) then raise Exception.Create('Runner pulse count mismatch');
      SetLength(Result.FPulses,Items.Count);
      for I:=0 to Items.Count-1 do begin
        if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid runner pulse');J:=TJSONObject(Items.Items[I]);
        P.Time:=J.GetValue<Double>('time');P.Strength:=J.GetValue<Double>('strength');P.Step:=J.GetValue<Integer>('step');
        if not Finite(P.Time) or not Finite(P.Strength) or (P.Strength<0) or (P.Strength>1) or
          (P.Step<0) or (P.Step>=Result.Count) or (P.Time<>Result.FSteps[P.Step].Time) or
          ((I>0) and (P.Time<Result.FPulses[I-1].Time)) then raise Exception.Create('Invalid runner pulse link');
        Result.FPulses[I]:=P;
      end;Result.MakeCourse;
    except Result.Free;Result:=nil;raise;end;
  finally Root.Free;end;
end;
end.
