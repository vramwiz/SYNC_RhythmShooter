unit RhythmRunnerPlan;
// Absolute-time course: accents are planned foot or sword contacts.
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef;
const RUN_SPEED=0.42;RUN_GRAVITY=3.8;RUN_EXIT=1.60;RUN_SWORD_LENGTH=0.105;RUN_SWORD_HALF=0.004;
type
  TRunnerStep=record Time,Y,Takeoff,StartY,Velocity,Strength:Double;end;
  TRunnerPlatform=record Left,Right,Y:Double;end;
  TRunnerPulse=record Time,Strength:Double;Step:Integer;end;
  TRunnerPoint=record X,Y:Double;Airborne:Boolean;end;
  TRunnerSetPieceKind=(rkVault,rkBounce);
  TRunnerSetPiece=record Kind:TRunnerSetPieceKind;FirstStep,LastStep:Integer;end;
  TRunnerEncounter=record Time,Show,X,Y,Radius:Double;Step,Count:Integer;end;
  TRunnerSwordRun=record FirstStep,LastStep:Integer;end;
  TRunnerCut=record Time,Show,X,Y,Radius:Double;Step:Integer;end;
  TRunnerStrike=record FirstCut,LastCut:Integer;Show,X,Y:Double;end;
  TRunnerBladeKey=record Time,GripOffset:Double;Tip:TRunnerPoint;Carry:Boolean;end;
  TRunnerPlan=class
  private
    FSteps:TArray<TRunnerStep>;FPlatforms:TArray<TRunnerPlatform>;FPulses:TArray<TRunnerPulse>;
    FSetPieces:TArray<TRunnerSetPiece>;FRecipeVersion:Integer;
    FEncounters:TArray<TRunnerEncounter>;
    FGoal:Double;FExcluded:Integer;
    FSwordRuns:TArray<TRunnerSwordRun>;FCuts:TArray<TRunnerCut>;FGroundAnchors:TArray<Integer>;
    FStrikes:TArray<TRunnerStrike>;FBladeKeys:TArray<TRunnerBladeKey>;
    procedure MakeStrikes(const Cancel:TFunc<Boolean>);
    procedure ValidateRapid;
    function RapidSwordAt(Time:Double;out Grip,Tip:TRunnerPoint):Boolean;
    function GetStrikeCount:Integer;function GetStrike(Index:Integer):TRunnerStrike;
    procedure MakeSwordRuns(const Cancel:TFunc<Boolean>);
    procedure MakeCuts(const Cancel:TFunc<Boolean>);
    procedure ValidateSword;
    function SwordRunForStep(Index:Integer):Integer;
    function SwordRunBefore(Time:Double):Integer;
    function CutRadius(Index:Integer):Double;
    function GetSwordRunCount:Integer;function GetSwordRun(Index:Integer):TRunnerSwordRun;
    function GetCutCount:Integer;function GetCut(Index:Integer):TRunnerCut;
    procedure MakeCourse;
    procedure MakeEncounters(const Cancel:TFunc<Boolean>);
    procedure ValidateEncounters;
    function GetEncounterCount:Integer;function GetEncounter(I:Integer):TRunnerEncounter;
    procedure MakeSetPieces(const Cancel:TFunc<Boolean>);
    procedure ValidateSetPieces;
    function PieceForStep(Index:Integer):Integer;
    function PlannedStep(const Previous:TRunnerStep;Time,Strength:Double;Index:Integer):TRunnerStep;
    function GetSetPieceCount:Integer;
    function GetSetPiece(I:Integer):TRunnerSetPiece;
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
    property RecipeVersion:Integer read FRecipeVersion;
    property StrikeCount:Integer read GetStrikeCount;property Strike[I:Integer]:TRunnerStrike read GetStrike;
    function SwordAt(Time:Double;out Grip,Tip:TRunnerPoint):Boolean;
    function SwordStep(Index:Integer):Boolean;
    function StrikeBefore(Time:Double):Integer;
    function CutBefore(Time:Double):Integer;
    property SwordRunCount:Integer read GetSwordRunCount;property SwordRun[I:Integer]:TRunnerSwordRun read GetSwordRun;
    property CutCount:Integer read GetCutCount;property Cut[I:Integer]:TRunnerCut read GetCut;
    function EncounterBefore(Time:Double):Integer;
    function EncounterTarget(Index,Target:Integer;Time:Double):TRunnerPoint;
    property EncounterCount:Integer read GetEncounterCount;property Encounter[I:Integer]:TRunnerEncounter read GetEncounter;
    function GroundAnchor(Index:Integer):Integer;
    function StepBefore(Time:Double):Integer;
    function PulseBefore(Time:Double):Integer;
    function PositionAt(Time:Double):TRunnerPoint;
    function EntryDuration:Double;
    function FirstPlatform(X:Double):Integer;
    function SetPieceBefore(Time:Double):Integer;
    property Count:Integer read GetCount;
    property Step[I:Integer]:TRunnerStep read GetStep;
    property PlatformCount:Integer read GetPlatformCount;
    property Platform[I:Integer]:TRunnerPlatform read GetPlatform;
    property PulseCount:Integer read GetPulseCount;
    property Pulse[I:Integer]:TRunnerPulse read GetPulse;
    property SetPieceCount:Integer read GetSetPieceCount;
    property SetPiece[I:Integer]:TRunnerSetPiece read GetSetPiece;
    property GoalTime:Double read FGoal;
    property EndTime:Double read GetEnd;
    property ExcludedCount:Integer read FExcluded;
  end;
procedure RunnerVaultBounds(const S:TRunnerStep;out Left,Right,Top:Double);
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
function VaultDuration(const S:TRunnerStep;PreviousTime:Double):Double;
begin
  // The lower endpoint bounds the whole parabola, including an uneven landing.
  // Leave 0.24 stage units above the apex for the accepted chibi silhouette.
  Result:=Min(1.04,Min(S.Time-PreviousTime-0.045,
    Sqrt(Max(0.0,8*(Min(S.StartY,S.Y)-0.24)/RUN_GRAVITY))));
end;
procedure RunnerVaultBounds(const S:TRunnerStep;out Left,Right,Top:Double);
var Apex,T0,T1:Double;
begin
  Apex:=RUN_SPEED*(S.Takeoff-S.Velocity/RUN_GRAVITY);Left:=Apex-0.044;Right:=Apex+0.044;
  // Expand the collision interval by the entire chibi silhouette, not just its
  // centre. A convex parabola is deepest at one of these two interval ends.
  T0:=(Left-0.085)/RUN_SPEED-S.Takeoff;T1:=(Right+0.085)/RUN_SPEED-S.Takeoff;
  Top:=Max(S.StartY+S.Velocity*T0+0.5*RUN_GRAVITY*T0*T0,
    S.StartY+S.Velocity*T1+0.5*RUN_GRAVITY*T1*T1)+0.023;
end;
function TRunnerPlan.PieceForStep(Index:Integer):Integer;
var A,B,M:Integer;
begin
  A:=0;B:=SetPieceCount;while A<B do begin M:=(A+B) div 2;if FSetPieces[M].FirstStep<=Index then A:=M+1 else B:=M;end;
  Result:=A-1;if Result>=0 then if FSetPieces[Result].LastStep<Index then Result:=-1;
end;
function TRunnerPlan.PlannedStep(const Previous:TRunnerStep;Time,Strength:Double;Index:Integer):TRunnerStep;
var K:Integer;D:Double;
begin
  if (FRecipeVersion>=4) and SwordStep(Index) then begin
    Result:=Default(TRunnerStep);Result.Time:=Time;Result.Takeoff:=Time;Result.Strength:=Strength;
    Result.StartY:=Previous.Y;Result.Y:=Previous.Y;Exit;
  end;
  Result:=NewStep(Previous,Time,Strength,Index);K:=PieceForStep(Index);if K<0 then Exit;
  if FSetPieces[K].Kind=rkVault then begin D:=VaultDuration(Result,Previous.Time);Result.Takeoff:=Time-D;end
  else begin D:=Time-Previous.Time;Result.Takeoff:=Previous.Time;end;
  if D<=0 then raise Exception.Create('Invalid runner special flight time');
  Result.Velocity:=(Result.Y-Previous.Y)/D-0.5*RUN_GRAVITY*D;
end;
procedure TRunnerPlan.MakeSetPieces(const Cancel:TFunc<Boolean>);
var List:TList<TRunnerSetPiece>;Candidate,Best:TRunnerSetPiece;
  I,J,N,Cursor:Integer;WindowStart,WindowEnd,Score,BestScore,Mean,Gap,D:Double;
  procedure Offer(Kind:TRunnerSetPieceKind;First,Last:Integer;Start,Value:Double);
  begin
    if (Start<WindowStart) or (FSteps[Last].Time>WindowEnd) then Exit;
    if FRecipeVersion>=4 then begin if Kind=rkBounce then Exit;if SwordStep(First) then Exit;end;
    if List.Count>0 then if List[List.Count-1].Kind<>Kind then Value:=Value+0.12;
    if Value<=BestScore+1E-9 then Exit;
    BestScore:=Value;Best.Kind:=Kind;Best.FirstStep:=First;Best.LastStep:=Last;
  end;
begin
  // Selection runs only during settings preparation. Load reads the saved list.
  if (FGoal<22) or (Count<8) then Exit;
  List:=TList<TRunnerSetPiece>.Create;
  try
    WindowStart:=5;Cursor:=1;
    while (WindowStart<FGoal-5) and (List.Count<1000) do begin
      if Assigned(Cancel) and Cancel() then Abort;
      WindowEnd:=Min(WindowStart+8,FGoal-5);BestScore:=-1;
      while (Cursor<Count) and (FSteps[Cursor].Time<WindowStart) do Inc(Cursor);
      for I:=Cursor to Count-1 do begin
        if Assigned(Cancel) and Cancel() then Abort;
        if FSteps[I-1].Time>WindowEnd then Break;
        Mean:=0;N:=0;
        for J:=I to Min(I+3,Count-1) do begin
          Gap:=FSteps[J].Time-FSteps[J-1].Time;
          if (Gap<0.30) or (Gap>0.62) or (FSteps[J].Time>WindowEnd) then Break;
          Mean:=Mean+FSteps[J].Strength;Inc(N);
        end;
        if (N>=3) and (Mean/N>=0.48) then Offer(rkBounce,I,I+N-1,FSteps[I-1].Time,Mean/N+0.08+0.01*N);
        if (I>=2) and (I+2<Count) then begin
          D:=VaultDuration(FSteps[I],FSteps[I-1].Time);
          Gap:=FSteps[I+2].Time-FSteps[I-2].Time;Mean:=0;
          for J:=I-2 to I+2 do Mean:=Mean+FSteps[J].Strength/5;
          if (D>=0.90) and (D>=FSteps[I].Time-FSteps[I].Takeoff+0.08) and
            (Gap<=5.0) and (Mean>=0.50) then begin
            Score:=Mean+0.10;Offer(rkVault,I,I,FSteps[I].Time-D,Score);
          end;
        end;
      end;
      if BestScore>=0 then begin
        Candidate:=Best;List.Add(Candidate);WindowStart:=FSteps[Candidate.LastStep].Time+10;
      end else WindowStart:=WindowStart+8;
    end;
    FSetPieces:=List.ToArray;
    for I:=1 to Count-1 do FSteps[I]:=PlannedStep(FSteps[I-1],FSteps[I].Time,FSteps[I].Strength,I);
    ValidateSetPieces;
  finally List.Free;end;
end;
procedure TRunnerPlan.ValidateSetPieces;
var I,J:Integer;Piece:TRunnerSetPiece;Base:TRunnerStep;Start,Mean,Gap,D,PreviousEnd:Double;
begin
  PreviousEnd:=-5;
  for I:=0 to SetPieceCount-1 do begin
    Piece:=FSetPieces[I];Start:=FSteps[Piece.FirstStep].Takeoff;
    if (FGoal<22) or (Start<5-1E-7) or (FSteps[Piece.LastStep].Time>FGoal-5+1E-7) or
      (Start<PreviousEnd+10-1E-7) then raise Exception.Create('Invalid runner set-piece spacing');
    Mean:=0;
    if Piece.Kind=rkBounce then begin
      if (Piece.LastStep-Piece.FirstStep<2) or (Piece.LastStep-Piece.FirstStep>3) then raise Exception.Create('Invalid runner bounce count');
      for J:=Piece.FirstStep to Piece.LastStep do begin
        Gap:=FSteps[J].Time-FSteps[J-1].Time;
        if (Gap<0.30) or (Gap>0.62) then raise Exception.Create('Invalid runner bounce rhythm');
        Mean:=Mean+FSteps[J].Strength/(Piece.LastStep-Piece.FirstStep+1);
      end;
      if Mean<0.48-1E-9 then raise Exception.Create('Invalid runner bounce strength');
    end else begin
      J:=Piece.FirstStep;
      if (Piece.LastStep<>J) or (J<2) or (J+2>=Count) then raise Exception.Create('Invalid runner vault link');
      Base:=NewStep(FSteps[J-1],FSteps[J].Time,FSteps[J].Strength,J);D:=FSteps[J].Time-Start;
      for J:=Piece.FirstStep-2 to Piece.FirstStep+2 do Mean:=Mean+FSteps[J].Strength/5;
      if (D<0.90-1E-7) or (D<Base.Time-Base.Takeoff+0.08-1E-7) or (Mean<0.50-1E-9) or
        (FSteps[Piece.FirstStep+2].Time-FSteps[Piece.FirstStep-2].Time>5.0) then raise Exception.Create('Invalid runner vault rhythm');
    end;
    PreviousEnd:=FSteps[Piece.LastStep].Time;
  end;
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
    Result.FGoal:=Audio.SoundEnd;Result.FRecipeVersion:=5;
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
    Result.FSteps:=Steps.ToArray;Result.FPulses:=Pulses.ToArray;Result.MakeSwordRuns(Cancel);Result.MakeSetPieces(Cancel);Result.MakeCourse;Result.MakeCuts(Cancel);Result.MakeEncounters(Cancel);Result.ValidateEncounters;Result.ValidateSword;
  except Result.Free;Steps.Free;Pulses.Free;raise;end;Steps.Free;Pulses.Free;
end;
function TRunnerPlan.StrikeBefore(Time:Double):Integer;
var A,B,M:Integer;begin A:=0;B:=StrikeCount;while A<B do begin M:=(A+B) div 2;if FCuts[FStrikes[M].FirstCut].Time<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
function TRunnerPlan.GetStrikeCount:Integer;begin Result:=Length(FStrikes);end;
function TRunnerPlan.GetStrike(Index:Integer):TRunnerStrike;begin Result:=FStrikes[Index];end;
function TRunnerPlan.RapidSwordAt(Time:Double;out Grip,Tip:TRunnerPoint):Boolean;
var A,B,M:Integer;U:Double;K,L:TRunnerBladeKey;
begin
  Time:=EnsureRange(Time,0.0,EndTime);Grip:=PositionAt(Time);Grip.X:=Grip.X+0.028;Grip.Y:=Grip.Y-0.072;Tip:=Grip;
  Tip.X:=Grip.X+RUN_SWORD_LENGTH*Cos(-1.02);Tip.Y:=Grip.Y+RUN_SWORD_LENGTH*Sin(-1.02);Result:=True;
  A:=0;B:=Length(FBladeKeys);while A<B do begin M:=(A+B) div 2;if FBladeKeys[M].Time<=Time then A:=M+1 else B:=M;end;
  if (A=0) or (A>=Length(FBladeKeys)) then Exit;K:=FBladeKeys[A-1];L:=FBladeKeys[A];if K.Carry and L.Carry then Exit;
  U:=EnsureRange((Time-K.Time)/Max(1E-12,L.Time-K.Time),0.0,1.0);U:=U*U*(3-2*U);
  Grip.Y:=Grip.Y+K.GripOffset+(L.GripOffset-K.GripOffset)*U;Tip.X:=K.Tip.X+(L.Tip.X-K.Tip.X)*U;Tip.Y:=K.Tip.Y+(L.Tip.Y-K.Tip.Y)*U;
end;
procedure TRunnerPlan.MakeStrikes(const Cancel:TFunc<Boolean>);
var Groups:TList<TRunnerStrike>;Keys:TList<TRunnerBladeKey>;A:TRunnerStrike;K:TRunnerBladeKey;C:TRunnerCut;
  I,J,N,Run:Integer;First,Last,Previous,Next,Start,Finish,Follow,U,Sign:Double;
  procedure CarryKey(Time:Double);
  var P:TRunnerPoint;
  begin P:=PositionAt(Time);K:=Default(TRunnerBladeKey);K.Time:=Time;K.Carry:=True;K.Tip.X:=P.X+0.028+RUN_SWORD_LENGTH*Cos(-1.02);K.Tip.Y:=P.Y-0.072+RUN_SWORD_LENGTH*Sin(-1.02);
    if (Keys.Count>0) and (Abs(Keys[Keys.Count-1].Time-Time)<1E-10) then Keys[Keys.Count-1]:=K else Keys.Add(K);
  end;
begin
  Groups:=TList<TRunnerStrike>.Create;Keys:=TList<TRunnerBladeKey>.Create;
  try I:=0;while I<CutCount do begin if Assigned(Cancel) and Cancel() then Abort;J:=I;
      while J<CutCount-1 do begin if SwordRunForStep(FCuts[J+1].Step)<>SwordRunForStep(FCuts[I].Step) then Break;
        if (FCuts[J+1].Time-FCuts[I].Time>0.14+1E-9) or (FCuts[J+1].Time-FCuts[J].Time>0.105+1E-9) then Break;Inc(J);
      end;A.FirstCut:=I;A.LastCut:=J;A.Show:=FCuts[I].Show;A.X:=RUN_SPEED*FCuts[I].Time+0.19;A.Y:=FSteps[FCuts[I].Step].Y-0.075;Groups.Add(A);I:=J+1;
    end;FStrikes:=Groups.ToArray;
    for N:=0 to StrikeCount-1 do begin A:=FStrikes[N];First:=FCuts[A.FirstCut].Time;Last:=FCuts[A.LastCut].Time;Run:=SwordRunForStep(FCuts[A.FirstCut].Step);
      Previous:=-10;if N>0 then Previous:=FCuts[FStrikes[N-1].LastCut].Time;Next:=EndTime+1;if N<StrikeCount-1 then Next:=FCuts[FStrikes[N+1].FirstCut].Time;
      Start:=Max(FSteps[Max(0,FSwordRuns[Run].FirstStep-1)].Time,First-0.045);
      if First-Previous>0.12 then CarryKey(Start);Sign:=1;if N mod 2=1 then Sign:=-1;
      for I:=A.FirstCut to A.LastCut do begin C:=FCuts[I];C.X:=A.X;C.Y:=A.Y;C.Radius:=0.020;C.Show:=A.Show;FCuts[I]:=C;
        U:=0.5;if Last>First then U:=(C.Time-First)/(Last-First);K:=Default(TRunnerBladeKey);K.Time:=C.Time;K.GripOffset:=Sign*(-0.012+0.024*U);
        K.Tip.X:=A.X-0.020-RUN_SWORD_HALF;K.Tip.Y:=A.Y+Sign*(-0.026+0.052*U);
        if (Keys.Count>0) and (Abs(Keys[Keys.Count-1].Time-K.Time)<1E-10) then Keys[Keys.Count-1]:=K else Keys.Add(K);
      end;
      if Next-Last>0.12 then begin Finish:=Min(Last+0.14,Next-0.045);J:=FCuts[A.LastCut].Step;if J<Count-1 then if FSteps[J+1].Takeoff<FSteps[J+1].Time then Finish:=Min(Finish,FSteps[J+1].Takeoff);Follow:=Min(Last+0.045,Finish-0.015);
        if Follow>Last then begin K.Time:=Follow;K.Tip.X:=K.Tip.X+0.05;K.Tip.Y:=K.Tip.Y+Sign*0.045;Keys.Add(K);end;
        CarryKey(Finish);
      end;
    end;FBladeKeys:=Keys.ToArray;
  finally Groups.Free;Keys.Free;end;
end;
procedure TRunnerPlan.ValidateRapid;
var I,J,N,Expected:Integer;A:TRunnerStrike;C:TRunnerCut;G,T:TRunnerPoint;D:Double;
  procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create('Rapid sword: '+S);end;
begin
  Need((StrikeCount<=20000) and (CutCount<=20000) and (Length(FBladeKeys)<=100000),'limits');Expected:=0;
  for I:=0 to SwordRunCount-1 do for J:=FSwordRuns[I].FirstStep to FSwordRuns[I].LastStep do begin Inc(Expected);Need((FSteps[J].Takeoff=FSteps[J].Time) and (FSteps[J].Velocity=0) and (FSteps[J].Y=FSteps[Max(0,FSwordRuns[I].FirstStep-1)].Y),'flat');end;
  Need(Expected=CutCount,'cut count');N:=0;
  for I:=0 to StrikeCount-1 do begin A:=FStrikes[I];Need((A.FirstCut=N) and (A.LastCut>=A.FirstCut) and (A.LastCut<CutCount),'group order');N:=A.LastCut+1;
    Need(Finite(A.X) and Finite(A.Y) and Finite(A.Show),'finite group');Need(FCuts[A.LastCut].Time-FCuts[A.FirstCut].Time<=0.14+1E-8,'group duration');
    if I>0 then Need(A.X-FStrikes[I-1].X>0.040,'full-size overlap');
    for J:=A.FirstCut to A.LastCut do begin C:=FCuts[J];Need((C.Step>=0) and (C.Step<Count) and SwordStep(C.Step),'source step');Need((C.Time=FSteps[C.Step].Time) and (C.X=A.X) and (C.Y=A.Y) and (C.Radius=0.020),'source contact');
      SwordAt(C.Time,G,T);D:=Hypot(T.X-G.X,T.Y-G.Y);Need((D>0.035) and (D<0.24),'blade reach');
      Need((Abs(T.X-(A.X-0.020-RUN_SWORD_HALF))<1E-7) and (Abs(T.Y-A.Y)<=0.026+1E-7),'blade face');
    end;
  end;Need(N=CutCount,'group coverage');
  for I:=0 to High(FBladeKeys) do begin Need(Finite(FBladeKeys[I].Time) and Finite(FBladeKeys[I].Tip.X) and Finite(FBladeKeys[I].Tip.Y) and Finite(FBladeKeys[I].GripOffset),'finite key');if I>0 then Need(FBladeKeys[I].Time>FBladeKeys[I-1].Time,'key order');end;
end;

function TRunnerPlan.GetSwordRunCount:Integer;begin Result:=Length(FSwordRuns);end;
function TRunnerPlan.GetSwordRun(Index:Integer):TRunnerSwordRun;begin Result:=FSwordRuns[Index];end;
function TRunnerPlan.GetCutCount:Integer;begin Result:=Length(FCuts);end;
function TRunnerPlan.GetCut(Index:Integer):TRunnerCut;begin Result:=FCuts[Index];end;
function TRunnerPlan.SwordRunForStep(Index:Integer):Integer;
var A,B,M:Integer;
begin A:=0;B:=SwordRunCount;while A<B do begin M:=(A+B) div 2;if FSwordRuns[M].FirstStep<=Index then A:=M+1 else B:=M;end;
  Result:=A-1;if Result>=0 then if Index>FSwordRuns[Result].LastStep then Result:=-1;
end;
function TRunnerPlan.SwordStep(Index:Integer):Boolean;
begin Result:=(FRecipeVersion>=4) and (SwordRunForStep(Index)>=0);end;
function TRunnerPlan.SwordRunBefore(Time:Double):Integer;
var A,B,M:Integer;Start:Double;
begin A:=0;B:=SwordRunCount;while A<B do begin M:=(A+B) div 2;
    Start:=Max(FSteps[Max(0,FSwordRuns[M].FirstStep-1)].Time,FSteps[FSwordRuns[M].FirstStep].Time-0.16);
    if Start<=Time then A:=M+1 else B:=M;
  end;Result:=A-1;
end;
function TRunnerPlan.SwordAt(Time:Double;out Grip,Tip:TRunnerPoint):Boolean;
var K:Integer;R:TRunnerSwordRun;First,Last,Start,Finish,U,Angle,EndAngle:Double;
begin
  if FRecipeVersion>=5 then Exit(RapidSwordAt(Time,Grip,Tip));
  Grip:=Default(TRunnerPoint);Tip:=Grip;Result:=FRecipeVersion>=4;if not Result then Exit;
  Time:=EnsureRange(Time,0.0,EndTime);Grip:=PositionAt(Time);Grip.X:=Grip.X+0.028;Grip.Y:=Grip.Y-0.072;Angle:=-1.02;
  K:=SwordRunBefore(Time);
  if K>=0 then begin R:=FSwordRuns[K];First:=FSteps[R.FirstStep].Time;Last:=FSteps[R.LastStep].Time;
    Start:=Max(FSteps[Max(0,R.FirstStep-1)].Time,First-0.16);
    if Time<First then begin U:=(Time-Start)/Max(1E-12,First-Start);U:=U*U*(3-2*U);Angle:=-1.02+0.57*U;if First-Start<0.08 then Angle:=-0.45;end
    else if Time<=Last then Angle:=-0.45*Cos(2*Pi*(Time-First)/0.42)
    else begin Finish:=Last+0.18;if R.LastStep<Count-1 then Finish:=Min(Finish,FSteps[R.LastStep+1].Takeoff);
      if Time<Finish then begin U:=(Time-Last)/Max(1E-12,Finish-Last);U:=U*U*(3-2*U);
        EndAngle:=-0.45*Cos(2*Pi*(Last-First)/0.42);Angle:=EndAngle+(-1.02-EndAngle)*U;end;
    end;
  end;
  Grip.X:=Grip.X+0.008*Sin(Angle);Tip:=Grip;Tip.X:=Grip.X+RUN_SWORD_LENGTH*Cos(Angle);Tip.Y:=Grip.Y+RUN_SWORD_LENGTH*Sin(Angle);
end;
function TRunnerPlan.CutBefore(Time:Double):Integer;
var A,B,M:Integer;begin A:=0;B:=CutCount;while A<B do begin M:=(A+B) div 2;if FCuts[M].Time<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
procedure TRunnerPlan.MakeSwordRuns(const Cancel:TFunc<Boolean>);
var List:TList<TRunnerSwordRun>;I,J,K,Pulse:Integer;R:TRunnerSwordRun;
  function RealStep(Index:Integer):Boolean;
  begin Pulse:=PulseBefore(FSteps[Index].Time);Result:=(Pulse>=0);if Result then Result:=(FPulses[Pulse].Time=FSteps[Index].Time) and (FPulses[Pulse].Step=Index);end;
begin
  List:=TList<TRunnerSwordRun>.Create;
  try I:=0;while I<Count do begin if Assigned(Cancel) and Cancel() then Abort;
      if not RealStep(I) then begin Inc(I);Continue;end;J:=I;
      while J<Count-1 do begin if not RealStep(J+1) then Break;if FSteps[J+1].Time-FSteps[J].Time>0.62+1E-9 then Break;Inc(J);end;
      if J-I>=2 then begin R.FirstStep:=I;R.LastStep:=J;List.Add(R);end;I:=J+1;
    end;FSwordRuns:=List.ToArray;
    for K:=1 to Count-1 do FSteps[K]:=PlannedStep(FSteps[K-1],FSteps[K].Time,FSteps[K].Strength,K);
  finally List.Free;end;
end;
function TRunnerPlan.CutRadius(Index:Integer):Double;
var G,T,OtherG,OtherT:TRunnerPoint;X,Gap,D,Down,Ground:Double;J:Integer;
begin
  SwordAt(FCuts[Index].Time,G,T);D:=Hypot(T.X-G.X,T.Y-G.Y);X:=T.X+(T.X-G.X)/D*RUN_SWORD_HALF;Gap:=1;
  for J:=Max(0,Index-1) to Min(CutCount-1,Index+1) do if J<>Index then begin
    SwordAt(FCuts[J].Time,OtherG,OtherT);D:=Hypot(OtherT.X-OtherG.X,OtherT.Y-OtherG.Y);
    Gap:=Min(Gap,Abs(X-(OtherT.X+(OtherT.X-OtherG.X)/D*RUN_SWORD_HALF)));
  end;Result:=Min(0.024,Gap*0.22);
  D:=Hypot(T.X-G.X,T.Y-G.Y);Down:=(T.Y-G.Y)/D;Ground:=G.Y+0.072;
  Result:=Min(Result,(Ground-T.Y-Down*RUN_SWORD_HALF-0.004)/(1+Down));
end;
procedure TRunnerPlan.MakeCuts(const Cancel:TFunc<Boolean>);
var List:TList<TRunnerCut>;I,J:Integer;C:TRunnerCut;G,T:TRunnerPoint;D:Double;
begin List:=TList<TRunnerCut>.Create;
  try
    for I:=0 to SwordRunCount-1 do for J:=FSwordRuns[I].FirstStep to FSwordRuns[I].LastStep do begin
      if Assigned(Cancel) and Cancel() then Abort;C:=Default(TRunnerCut);C.Step:=J;C.Time:=FSteps[J].Time;
      C.Show:=Max(FSteps[Max(0,FSwordRuns[I].FirstStep-1)].Time,C.Time-0.90);List.Add(C);
    end;FCuts:=List.ToArray;
    if FRecipeVersion>=5 then begin MakeStrikes(Cancel);Exit;end;
    for I:=0 to CutCount-1 do begin C:=FCuts[I];C.Radius:=CutRadius(I);SwordAt(C.Time,G,T);D:=Hypot(T.X-G.X,T.Y-G.Y);
      C.X:=T.X+(T.X-G.X)/D*(C.Radius+RUN_SWORD_HALF);C.Y:=T.Y+(T.Y-G.Y)/D*(C.Radius+RUN_SWORD_HALF);FCuts[I]:=C;
    end;
  finally List.Free;end;
end;
procedure TRunnerPlan.ValidateSword;
var I,J,K,Pulse,ExpectedCount:Integer;R:TRunnerSwordRun;C:TRunnerCut;G,T,Q:TRunnerPoint;D,ExpectedShow,DX,DY,AtTime,Along,Distance:Double;
  procedure Need(Value:Boolean;const Why:string);begin if not Value then raise Exception.Create('Runner sword: '+Why);end;
begin
  if FRecipeVersion>=5 then begin ValidateRapid;Exit;end;
  Need((SwordRunCount<=7000) and (CutCount<=20000),'count');
  if FRecipeVersion<4 then begin Need((SwordRunCount=0) and (CutCount=0),'legacy fields');Exit;end;ExpectedCount:=0;
  for I:=0 to SetPieceCount-1 do Need(FSetPieces[I].Kind<>rkBounce,'bounce in sword recipe');
  for I:=0 to SwordRunCount-1 do begin R:=FSwordRuns[I];Need((R.FirstStep>=0) and (R.LastStep<Count) and (R.LastStep-R.FirstStep>=2),'run bounds');
    if I>0 then Need(R.FirstStep>FSwordRuns[I-1].LastStep,'run order');
    for J:=R.FirstStep to R.LastStep do begin Inc(ExpectedCount);Pulse:=PulseBefore(FSteps[J].Time);
      Need((Pulse>=0),'run source');Need((FPulses[Pulse].Time=FSteps[J].Time) and (FPulses[Pulse].Step=J),'run source clock');
      if J>R.FirstStep then Need(FSteps[J].Time-FSteps[J-1].Time<=0.62+1E-9,'run gap');
      Need((FSteps[J].Takeoff=FSteps[J].Time) and (FSteps[J].Velocity=0) and (FSteps[J].Y=FSteps[Max(0,R.FirstStep-1)].Y),'not flat');
    end;
  end;Need(ExpectedCount=CutCount,'missing cuts');
  for I:=0 to CutCount-1 do begin C:=FCuts[I];Need((C.Step>=0) and (C.Step<Count) and SwordStep(C.Step),'cut step');
    Need(Finite(C.Time) and Finite(C.Show) and Finite(C.X) and Finite(C.Y) and Finite(C.Radius),'finite');
    Need((C.Time=FSteps[C.Step].Time) and (C.Radius>0) and (C.Radius<=0.024) and (Abs(C.Radius-CutRadius(I))<1E-10),'cut clock/radius');
    if I>0 then Need((C.Time>FCuts[I-1].Time) and (C.Step>FCuts[I-1].Step) and (C.X-FCuts[I-1].X>C.Radius+FCuts[I-1].Radius),'overlap/order');
    K:=SwordRunForStep(C.Step);ExpectedShow:=Max(FSteps[Max(0,FSwordRuns[K].FirstStep-1)].Time,C.Time-0.90);Need(Abs(C.Show-ExpectedShow)<1E-8,'show');
    SwordAt(C.Time,G,T);DX:=T.X-G.X;DY:=T.Y-G.Y;D:=Hypot(DX,DY);Need(Abs(D-RUN_SWORD_LENGTH)<1E-8,'length');
    Need((Abs(C.X-(T.X+DX/D*(C.Radius+RUN_SWORD_HALF)))<1E-8) and (Abs(C.Y-(T.Y+DY/D*(C.Radius+RUN_SWORD_HALF)))<1E-8),'blade contact');
    // Before this accent the entire target circle lies outside sword reach.
    Q:=PositionAt(C.Time);Need(not Q.Airborne,'air attack');Need(C.Y+C.Radius<=Q.Y-0.004+1E-7,'target below ground');
    for J:=1 to 6 do begin AtTime:=C.Time-(C.Time-C.Show)*J/6;if AtTime>=C.Time then Continue;
      SwordAt(AtTime,G,T);DX:=T.X-G.X;DY:=T.Y-G.Y;Along:=EnsureRange(((C.X-G.X)*DX+(C.Y-G.Y)*DY)/(DX*DX+DY*DY),0.0,1.0);
      Distance:=Hypot(C.X-G.X-Along*DX,C.Y-G.Y-Along*DY);Need(Distance>C.Radius+RUN_SWORD_HALF-1E-9,'early blade collision');
    end;
    for J:=Max(0,EncounterBefore(C.Time-1.55)) to EncounterBefore(C.Time) do begin
      if (FEncounters[J].Time<C.Time) and (FEncounters[J].Time>=C.Show) then Need(Hypot(C.X-FEncounters[J].X,C.Y-(FEncounters[J].Y-0.015))>FEncounters[J].Radius+C.Radius+0.010,'earlier landing shock');
    end;
  end;
end;

procedure TRunnerPlan.MakeCourse;
var List:TList<TRunnerPlatform>;P,Previous:TRunnerPlatform;I,Anchor:Integer;D,Lead:Double;
begin
  SetLength(FGroundAnchors,Count);Anchor:=0;
  for I:=0 to Count-1 do begin if FSteps[I].Takeoff<FSteps[I].Time then Anchor:=I;FGroundAnchors[I]:=Anchor;end;
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
function TRunnerPlan.GetSetPieceCount:Integer;begin Result:=Length(FSetPieces);end;
function TRunnerPlan.GetSetPiece(I:Integer):TRunnerSetPiece;begin Result:=FSetPieces[I];end;
function TRunnerPlan.SetPieceBefore(Time:Double):Integer;
var A,B,M:Integer;
begin A:=0;B:=SetPieceCount;while A<B do begin M:=(A+B) div 2;if FSteps[FSetPieces[M].FirstStep].Takeoff<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
function TRunnerPlan.GetEnd:Double;begin Result:=0;if FGoal>0 then Result:=FGoal+RUN_EXIT;end;
function TRunnerPlan.GroundAnchor(Index:Integer):Integer;
begin Result:=FGroundAnchors[EnsureRange(Index,0,Count-1)];end;
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
function TRunnerPlan.GetEncounterCount:Integer;begin Result:=Length(FEncounters);end;
function TRunnerPlan.GetEncounter(I:Integer):TRunnerEncounter;begin Result:=FEncounters[I];end;
function TRunnerPlan.EncounterBefore(Time:Double):Integer;
var A,B,M:Integer;begin A:=0;B:=EncounterCount;while A<B do begin M:=(A+B) div 2;if FEncounters[M].Time<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
function TRunnerPlan.EncounterTarget(Index,Target:Integer;Time:Double):TRunnerPoint;
var E:TRunnerEncounter;Gap:Double;
begin E:=FEncounters[Index];Gap:=0.08;if E.Count=2 then Gap:=0.06;Result.X:=E.X+0.13+Target*Gap;Result.Y:=E.Y-0.030-0.004*Sin(Time*8+Target*1.7);Result.Airborne:=False;end;
procedure TRunnerPlan.MakeEncounters(const Cancel:TFunc<Boolean>);
var List:TList<TRunnerEncounter>;I,J,K,N,Pulse:Integer;E,Old:TRunnerEncounter;S:TRunnerStep;Point:TRunnerPoint;Last:Double;Bounce,Good:Boolean;
begin List:=TList<TRunnerEncounter>.Create;
  try Last:=-3;
    for I:=1 to Count-1 do begin if Assigned(Cancel) and Cancel() then Abort;S:=FSteps[I];if SwordStep(I) then Continue;
      if (S.Time<1.5) or (S.Time>FGoal-1.0) then Continue;Pulse:=PulseBefore(S.Time);if (Pulse<0) or (FPulses[Pulse].Time<>S.Time) then Continue;
      K:=PieceForStep(I);Bounce:=(K>=0) and (FSetPieces[K].Kind=rkBounce);
      if Bounce then begin if S.Time-Last<0.28 then Continue;end
      else begin if (S.Time-Last<1.3) or ((K<0) and (S.Strength<0.5) and (S.Time-Last<2.8)) then Continue;
        Good:=True;for J:=0 to SetPieceCount-1 do if (FSteps[FSetPieces[J].FirstStep].Time>S.Time) and (FSteps[FSetPieces[J].FirstStep].Time-S.Time<1.3) then Good:=False;if not Good then Continue;
      end;
      E.Time:=S.Time;E.Show:=Max(0.0,S.Time-1.55);E.X:=RUN_SPEED*S.Time;E.Y:=S.Y;E.Step:=I;E.Count:=2;E.Radius:=0.205;if not Bounce and ((K>=0) or (S.Strength>=0.82)) then begin E.Count:=4;E.Radius:=0.40;end;
      Good:=True;for J:=Max(0,List.Count-8) to List.Count-1 do begin Old:=List[J];if Old.Time<E.Show then Continue;
        for N:=0 to E.Count-1 do begin Point.X:=E.X+0.13+N*0.08;if E.Count=2 then Point.X:=E.X+0.13+N*0.06;Point.Y:=E.Y-0.030;
          if Hypot(Point.X-Old.X,Point.Y-(Old.Y-0.015))<=Old.Radius+0.034 then Good:=False;
        end;
      end;
      if FRecipeVersion>=4 then for J:=Max(0,CutBefore(S.Time)+1) to CutBefore(S.Time+1.55) do
        if (FCuts[J].Show<=S.Time) and (Hypot(FCuts[J].X-E.X,FCuts[J].Y-(E.Y-0.015))<=E.Radius+FCuts[J].Radius+0.010+Ord(FRecipeVersion>=5)*0.010) then Good:=False;
      if Good then begin List.Add(E);Last:=S.Time;end;if List.Count>=5000 then Break;
    end;FEncounters:=List.ToArray;
  finally List.Free;end;
end;
procedure TRunnerPlan.ValidateEncounters;
var I,J,K,Pulse:Integer;E,Old:TRunnerEncounter;P:TRunnerPoint;
begin
  if (EncounterCount>5000) or ((FRecipeVersion<3) and (EncounterCount<>0)) then raise Exception.Create('Runner encounter count');
  for I:=0 to EncounterCount-1 do begin E:=FEncounters[I];
    if not Finite(E.Time) or not Finite(E.Show) or not Finite(E.X) or not Finite(E.Y) or not Finite(E.Radius) or (E.Step<1) or (E.Step>=Count) or not (E.Count in [2,4]) or (E.Time<1.5) or (E.Time>FGoal-1.0) then raise Exception.Create('Runner encounter data');
    Pulse:=PulseBefore(E.Time);if (Pulse<0) or (FPulses[Pulse].Time<>E.Time) or (E.Time<>FSteps[E.Step].Time) or (Abs(E.X-RUN_SPEED*E.Time)>1E-7) or (Abs(E.Y-FSteps[E.Step].Y)>1E-7) or (Abs(E.Show-Max(0.0,E.Time-1.55))>1E-7) then raise Exception.Create('Runner encounter accent');
    if ((E.Count=4) and (E.Radius<>0.40)) or ((E.Count=2) and (E.Radius<>0.205)) then raise Exception.Create('Runner encounter radius');
    if I>0 then if E.Time-FEncounters[I-1].Time<0.28-1E-7 then raise Exception.Create('Runner encounter order');
    for J:=0 to E.Count-1 do begin P:=EncounterTarget(I,J,E.Time);if (P.X-E.X<0.12) or (Hypot(P.X-E.X,P.Y-(E.Y-0.015))>E.Radius+0.024) then raise Exception.Create('Runner target miss');
      for K:=Max(0,I-8) to I-1 do begin Old:=FEncounters[K];if Old.Time<E.Show then Continue;if Hypot(P.X-Old.X,E.Y-0.030-(Old.Y-0.015))<=Old.Radius+0.034 then raise Exception.Create('Runner earlier target hit');end;
    end;
  end;
end;

procedure TRunnerPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var Root,J:TJSONObject;Items:TJSONArray;S:TRunnerStep;P:TRunnerPulse;Piece:TRunnerSetPiece;E:TRunnerEncounter;R:TRunnerSwordRun;C:TRunnerCut;A:TRunnerStrike;K:TRunnerBladeKey;
begin
  if (Ref.Version<>5) or (FRecipeVersion<>5) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsRunner) then raise Exception.Create('Invalid runner reference');
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
    Root.AddPair('setPiecesVersion',TJSONNumber.Create(1));Items:=TJSONArray.Create;Root.AddPair('setPieces',Items);
    for Piece in FSetPieces do begin
      J:=TJSONObject.Create;Items.AddElement(J);
      if Piece.Kind=rkVault then J.AddPair('kind','vault') else J.AddPair('kind','bounce');
      J.AddPair('first',TJSONNumber.Create(Piece.FirstStep));J.AddPair('last',TJSONNumber.Create(Piece.LastStep));
    end;
    Root.AddPair('encounterPolicy','landing-rows-v1');Items:=TJSONArray.Create;Root.AddPair('encounters',Items);
    for E in FEncounters do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(E.Time));J.AddPair('show',TJSONNumber.Create(E.Show));J.AddPair('x',TJSONNumber.Create(E.X));J.AddPair('y',TJSONNumber.Create(E.Y));J.AddPair('radius',TJSONNumber.Create(E.Radius));J.AddPair('step',TJSONNumber.Create(E.Step));J.AddPair('count',TJSONNumber.Create(E.Count));end;
    Root.AddPair('swordPolicy','rapid-armor-v2');Items:=TJSONArray.Create;Root.AddPair('swordRuns',Items);
    for R in FSwordRuns do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('first',TJSONNumber.Create(R.FirstStep));J.AddPair('last',TJSONNumber.Create(R.LastStep));end;
    Items:=TJSONArray.Create;Root.AddPair('cuts',Items);
    for C in FCuts do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(C.Time));J.AddPair('show',TJSONNumber.Create(C.Show));J.AddPair('x',TJSONNumber.Create(C.X));J.AddPair('y',TJSONNumber.Create(C.Y));J.AddPair('radius',TJSONNumber.Create(C.Radius));J.AddPair('step',TJSONNumber.Create(C.Step));end;
    Items:=TJSONArray.Create;Root.AddPair('strikes',Items);
    for A in FStrikes do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('first',TJSONNumber.Create(A.FirstCut));J.AddPair('last',TJSONNumber.Create(A.LastCut));J.AddPair('show',TJSONNumber.Create(A.Show));J.AddPair('x',TJSONNumber.Create(A.X));J.AddPair('y',TJSONNumber.Create(A.Y));end;
    Items:=TJSONArray.Create;Root.AddPair('blades',Items);
    for K in FBladeKeys do begin J:=TJSONObject.Create;Items.AddElement(J);J.AddPair('time',TJSONNumber.Create(K.Time));J.AddPair('grip',TJSONNumber.Create(K.GripOffset));J.AddPair('x',TJSONNumber.Create(K.Tip.X));J.AddPair('y',TJSONNumber.Create(K.Tip.Y));J.AddPair('carry',TJSONBool.Create(K.Carry));end;
    WritePreparedData(Root,Ref);
  finally Root.Free;end;
end;
class function TRunnerPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root:TJSONObject;
begin Root:=ReadPreparedData(Ref,rsRunner,Direction);try Result:=PreparedAudio(Root,Ref,Source);finally Root.Free;end;end;
class function TRunnerPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRunnerPlan;
var Root,J,Info:TJSONObject;Items,Specials:TJSONArray;I:Integer;S,Expected:TRunnerStep;P:TRunnerPulse;D:Double;
  Piece:TRunnerSetPiece;Kind:string;E:TRunnerEncounter;R:TRunnerSwordRun;C:TRunnerCut;A:TRunnerStrike;K:TRunnerBladeKey;
begin
  Result:=nil;if Audio=nil then raise Exception.Create('Runner audio metadata missing');
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsRunner) then raise Exception.Create('Runner settings mismatch');
  Root:=ReadPreparedData(Ref,rsRunner,Direction);
  try
    try
      Info:=Root.GetValue<TJSONObject>('audio');if (Info=nil) or not Finite(Info.GetValue<Double>('duration')) or not Finite(Info.GetValue<Double>('soundEnd')) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or
        (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-6) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-6) then raise Exception.Create('Runner audio identity mismatch');
      Result:=TRunnerPlan.Create;Result.FGoal:=Root.GetValue<Double>('goal');Result.FExcluded:=Root.GetValue<Integer>('excluded',0);Result.FRecipeVersion:=Ref.Version;
      if not Finite(Result.FGoal) or (Abs(Result.FGoal-Audio.SoundEnd)>1E-6) or (Result.FGoal<0) or (Result.FGoal>Audio.Duration) or (Result.FExcluded<0) then raise Exception.Create('Invalid runner goal');
      
      Items:=Root.GetValue<TJSONArray>('steps');if (Items=nil) or (Items.Count<1) or (Items.Count>20001) then raise Exception.Create('Invalid runner step count');
      SetLength(Result.FSteps,Items.Count);
      if Ref.Version>=2 then begin
        Specials:=Root.GetValue<TJSONArray>('setPieces');
        if (Root.GetValue<Integer>('setPiecesVersion',0)<>1) or (Specials=nil) or (Specials.Count>1000) then raise Exception.Create('Invalid runner set-piece data');
        SetLength(Result.FSetPieces,Specials.Count);
        for I:=0 to Specials.Count-1 do begin
          if not (Specials.Items[I] is TJSONObject) then raise Exception.Create('Invalid runner set-piece');J:=TJSONObject(Specials.Items[I]);
          Kind:=J.GetValue<string>('kind','');if Kind='vault' then Piece.Kind:=rkVault else if Kind='bounce' then Piece.Kind:=rkBounce else raise Exception.Create('Invalid runner set-piece kind');
          Piece.FirstStep:=J.GetValue<Integer>('first',-1);Piece.LastStep:=J.GetValue<Integer>('last',-1);
          if (Piece.FirstStep<1) or (Piece.LastStep<Piece.FirstStep) or (Piece.LastStep>=Items.Count) or
            ((I>0) and (Piece.FirstStep<=Result.FSetPieces[I-1].LastStep)) then raise Exception.Create('Invalid runner set-piece indices');
          Result.FSetPieces[I]:=Piece;
        end;
      end;
      if Ref.Version>=4 then begin
        Specials:=Root.GetValue<TJSONArray>('swordRuns');if (((Ref.Version=4) and (Root.GetValue<string>('swordPolicy','')<>'flat-blade-contact-v1')) or ((Ref.Version>=5) and (Root.GetValue<string>('swordPolicy','')<>'rapid-armor-v2'))) or (Specials=nil) or (Specials.Count>7000) then raise Exception.Create('Invalid runner sword runs');
        SetLength(Result.FSwordRuns,Specials.Count);for I:=0 to Specials.Count-1 do begin if not (Specials.Items[I] is TJSONObject) then raise Exception.Create('Invalid runner sword run');J:=TJSONObject(Specials.Items[I]);
          R.FirstStep:=J.GetValue<Integer>('first',-1);R.LastStep:=J.GetValue<Integer>('last',-1);
          if (R.FirstStep<0) or (R.LastStep-R.FirstStep<2) or (R.LastStep>=Items.Count) or ((I>0) and (R.FirstStep<=Result.FSwordRuns[I-1].LastStep)) then raise Exception.Create('Invalid runner sword indices');Result.FSwordRuns[I]:=R;
        end;
      end;
      for I:=0 to Items.Count-1 do begin
        if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid runner step');J:=TJSONObject(Items.Items[I]);
        S.Time:=J.GetValue<Double>('time');S.Y:=J.GetValue<Double>('y');S.Takeoff:=J.GetValue<Double>('takeoff');S.StartY:=J.GetValue<Double>('startY');S.Velocity:=J.GetValue<Double>('velocity');S.Strength:=J.GetValue<Double>('strength');
        if not Finite(S.Time) or not Finite(S.Y) or not Finite(S.Takeoff) or not Finite(S.StartY) or not Finite(S.Velocity) or not Finite(S.Strength) or
          (S.Time<0) or (S.Time>Result.FGoal+1E-6) or (S.Y<0.51) or (S.Y>0.79) or (S.Strength<0) or (S.Strength>1) then raise Exception.Create('Runner step out of bounds');
        if I=0 then begin if (S.Time<>0) or (S.Takeoff<>0) or (Abs(S.Y-0.72)>1E-8) or (S.Velocity<>0) then raise Exception.Create('Invalid runner start');end
        else begin
          if S.Time<=Result.FSteps[I-1].Time then raise Exception.Create('Invalid runner step order');
          Expected:=Result.PlannedStep(Result.FSteps[I-1],S.Time,S.Strength,I);
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
      end;
      if Ref.Version>=3 then begin
        Items:=Root.GetValue<TJSONArray>('encounters');if (Root.GetValue<string>('encounterPolicy','')<>'landing-rows-v1') or (Items=nil) or (Items.Count>5000) then raise Exception.Create('Invalid runner encounters');
        SetLength(Result.FEncounters,Items.Count);for I:=0 to Items.Count-1 do begin if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid runner encounter');J:=TJSONObject(Items.Items[I]);
          E.Time:=J.GetValue<Double>('time');E.Show:=J.GetValue<Double>('show');E.X:=J.GetValue<Double>('x');E.Y:=J.GetValue<Double>('y');E.Radius:=J.GetValue<Double>('radius');E.Step:=J.GetValue<Integer>('step');E.Count:=J.GetValue<Integer>('count');Result.FEncounters[I]:=E;
        end;
      end;
      if Ref.Version>=4 then begin Items:=Root.GetValue<TJSONArray>('cuts');if (Items=nil) or (Items.Count>20000) then raise Exception.Create('Invalid runner cuts');
        SetLength(Result.FCuts,Items.Count);for I:=0 to Items.Count-1 do begin if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid runner cut');J:=TJSONObject(Items.Items[I]);
          C.Time:=J.GetValue<Double>('time');C.Show:=J.GetValue<Double>('show');C.X:=J.GetValue<Double>('x');C.Y:=J.GetValue<Double>('y');C.Radius:=J.GetValue<Double>('radius');C.Step:=J.GetValue<Integer>('step');Result.FCuts[I]:=C;
        end;
      end;
      if Ref.Version>=5 then begin
        Items:=Root.GetValue<TJSONArray>('strikes');if (Items=nil) or (Items.Count>20000) then raise Exception.Create('Invalid strikes');SetLength(Result.FStrikes,Items.Count);
        for I:=0 to Items.Count-1 do begin J:=Items.Items[I] as TJSONObject;A.FirstCut:=J.GetValue<Integer>('first');A.LastCut:=J.GetValue<Integer>('last');A.Show:=J.GetValue<Double>('show');A.X:=J.GetValue<Double>('x');A.Y:=J.GetValue<Double>('y');Result.FStrikes[I]:=A;end;
        Items:=Root.GetValue<TJSONArray>('blades');if (Items=nil) or (Items.Count>100000) then raise Exception.Create('Invalid blades');SetLength(Result.FBladeKeys,Items.Count);
        for I:=0 to Items.Count-1 do begin J:=Items.Items[I] as TJSONObject;K.Time:=J.GetValue<Double>('time');K.GripOffset:=J.GetValue<Double>('grip');K.Tip:=Default(TRunnerPoint);K.Tip.X:=J.GetValue<Double>('x');K.Tip.Y:=J.GetValue<Double>('y');K.Carry:=J.GetValue<Boolean>('carry');Result.FBladeKeys[I]:=K;end;
      end;Result.ValidateSetPieces;Result.MakeCourse;Result.ValidateEncounters;Result.ValidateSword;
    except Result.Free;Result:=nil;raise;end;
  finally Root.Free;end;
end;
end.
