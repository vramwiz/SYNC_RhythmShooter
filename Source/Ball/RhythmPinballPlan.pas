unit RhythmPinballPlan;
// Fixed playfield and precomputed ballistic shots, with input only at powered contacts.
interface

uses System.SysUtils, RhythmAudio, RhythmPlanRef, RhythmBallGeometry;

const
  PIN_WIDTH = 1.0;
  PIN_HEIGHT = 1.67;
  PIN_RADIUS = 0.022;
  PIN_GRAVITY = 1.22;
  PIN_LEFT = 0.066;
  PIN_RIGHT = 0.856;
  PIN_FLIPPER_LENGTH = 0.172;
  PIN_FLIPPER_RADIUS = 0.017;
  PIN_BUMPERS = 3;
  PIN_LEFT_FLIPPER = 3;
  PIN_RIGHT_FLIPPER = 4;
  PIN_KICKER = 5;
  PIN_EXIT = -1;

type
  TPinContact = record
    Time: Double;
    Body, Source: Integer; // Source indexes the original accent; -1 means an incidental contact.
    P, Normal: TBallPoint;
  end;
  TPinFlight = record
    First, Last: Double;
    A, Velocity: TBallPoint;
    Bank: Integer; // -1/1 reflects at a fixed side rail.
  end;
  TPinballPlan = class
  private
    FContacts: TArray<TPinContact>;
    FFlights: TArray<TPinFlight>;
    FStart, FExit, FSoundEnd, FEnd: Double;
    FSynced, FFlippers, FBumpers, FStrong: Integer;
    function FlightAt(Time: Double): Integer;
    function GetCount: Integer;
    function GetContact(Index: Integer): TPinContact;
    function GetFlight(Index: Integer): TPinFlight;
    procedure Verify(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>);
  public
    class function Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TPinballPlan; static;
    class function Load(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TPinballPlan; static;
    procedure Save(var Ref: TRhythmPlanRef; Audio: TRhythmAudio);
    function Before(Time: Double): Integer;
    function PositionAt(Time: Double): TBallPoint;
    function FlipperAngle(Body: Integer; Time: Double): Double;
    function Flash(Body: Integer; Time: Double): Double;
    property Count: Integer read GetCount;
    property Contact[Index: Integer]: TPinContact read GetContact;
    property Flight[Index: Integer]: TPinFlight read GetFlight;
    property StartTime: Double read FStart;
    property EndTime: Double read FEnd;
    property SoundEnd: Double read FSoundEnd;
    property Synced: Integer read FSynced;
    property SyncedFlippers: Integer read FFlippers;
    property SyncedBumpers: Integer read FBumpers;
    property StrongCandidates: Integer read FStrong;
  end;

function PinBumper(Body: Integer): TBallPoint;
function PinBumperRadius(Body: Integer): Double;
function PinPivot(Body: Integer): TBallPoint;
function PinArm(Body: Integer; Angle: Double): TBallPoint;
function PinKicker: TBallPoint;
function PinLaunchGuide(U: Double): TBallPoint;
function PinPoint(const Shot: TPinFlight; Time: Double): TBallPoint;
function PinVelocity(const Shot: TPinFlight; Time: Double): TBallPoint;

implementation

uses System.Math, System.JSON, System.Generics.Collections, RhythmStyles, RhythmPreparedData;

const
  RestAngle = 0.47;
  StrikeAngle = -0.34;
  FlipperStrikeTime = 0.050;
  FlipperFollowTime = 0.029;
  FlipperReturnTime = 0.155;
  KickerRadius = 0.038;
  MinFlight = 0.145;
  MaxFlight = 1.24;
  MaxContacts = 24500;
  ContactEps = 1E-6;
  GuideLength = 0.75;
  GuideTurn = 0.30;
  LaunchX = 0.927;
  LaunchY = 1.451;
  StrongFraction = 0.54;

type
  TPinChoice = record
    Shot: TPinFlight;
    Target: TPinContact;
    EndVelocity: TBallPoint;
    Cost: Double;
  end;

function Finite(Value: Double): Boolean;
begin
  Result := not IsNan(Value) and not IsInfinite(Value);
end;

function PinBumper(Body: Integer): TBallPoint;
begin
  case Body of
    0: Result := BallPoint(0.342,0.435);
    1: Result := BallPoint(0.618,0.444);
  else Result := BallPoint(0.485,0.688);
  end;
end;

function PinBumperRadius(Body: Integer): Double;
begin
  if Body=2 then Result := 0.071 else Result := 0.078;
end;

function PinPivot(Body: Integer): TBallPoint;
begin
  if Body=PIN_LEFT_FLIPPER then Result := BallPoint(0.294,1.397)
  else Result := BallPoint(0.665,1.397);
end;

function PinArm(Body: Integer; Angle: Double): TBallPoint;
begin
  Result := BallPoint(Cos(Angle),Sin(Angle));
  if Body=PIN_RIGHT_FLIPPER then Result.X := -Result.X;
end;

function PinKicker: TBallPoint;
begin
  Result := BallPoint(0.184,1.048);
end;

function PinLaunchGuide(U: Double): TBallPoint;
var
  V: Double;
begin
  U := EnsureRange(U,0.0,1.0);
  V := 1-U;
  // Tangent from the shooter lane turns into the top-right area of the playfield.
  Result := BallPoint(
    V*V*V*LaunchX+3*V*V*U*LaunchX+3*V*U*U*0.886+U*U*U*0.805,
    V*V*V*0.268+3*V*V*U*0.102+3*V*U*U*0.289+U*U*U*0.354);
end;

function Smooth(U: Double): Double;
begin
  U := EnsureRange(U,0.0,1.0);
  Result := U*U*(3-2*U);
end;

function Swing(Age: Double): Double;
begin
  // The flipper is still driving through the ball at contact, then follows through.
  if Age<0 then Result := 1-Cos(0.5*Pi*EnsureRange(1+Age/FlipperStrikeTime,0.0,1.0))
  else if Age<FlipperFollowTime then Result := 1+0.16*Sin(0.5*Pi*Age/FlipperFollowTime)
  else Result := 1.16*(1-Smooth((Age-FlipperFollowTime)/(FlipperReturnTime-FlipperFollowTime)));
end;

function RadiusOK(const A,B: TBallPoint; Radius: Double): Boolean;
begin
  Result := BallLength(BallSub(A,B))>=Radius;
end;

function ArmDistance(const P: TBallPoint; Body: Integer; Angle: Double): Double;
var
  Relative, Along: TBallPoint;
begin
  Relative := BallSub(P,PinPivot(Body));
  Along := PinArm(Body,Angle);
  Result := BallLength(BallSub(Relative,BallScale(Along,EnsureRange(BallDot(Relative,Along),0.0,PIN_FLIPPER_LENGTH))));
end;

function RailX(Bank: Integer): Double;
begin
  if Bank<0 then Result := PIN_LEFT else Result := PIN_RIGHT;
end;

function PinPoint(const Shot: TPinFlight; Time: Double): TBallPoint;
var
  T, Wall: Double;
begin
  T := EnsureRange(Time,Shot.First,Shot.Last)-Shot.First;
  Result := BallPoint(Shot.A.X+Shot.Velocity.X*T,Shot.A.Y+Shot.Velocity.Y*T+0.5*PIN_GRAVITY*T*T);
  if Shot.Bank<>0 then begin
    Wall := RailX(Shot.Bank);
    if (Result.X-Wall)*Shot.Bank>0 then Result.X := 2*Wall-Result.X;
  end;
end;

function PinVelocity(const Shot: TPinFlight; Time: Double): TBallPoint;
var
  T: Double;
begin
  T := EnsureRange(Time,Shot.First,Shot.Last)-Shot.First;
  Result := BallPoint(Shot.Velocity.X,Shot.Velocity.Y+PIN_GRAVITY*T);
  if (Shot.Bank<>0) and ((Shot.A.X+Shot.Velocity.X*T-RailX(Shot.Bank))*Shot.Bank>0) then
    Result.X := -Result.X;
end;

function MakeShot(const A,B: TPinContact; Start: Double; Bank: Integer): TPinFlight;
var
  X, Gap: Double;
begin
  X := B.P.X;
  if Bank<>0 then X := 2*RailX(Bank)-X;
  Gap := B.Time-Start;
  Result.First := Start;
  Result.Last := B.Time;
  Result.A := A.P;
  Result.Velocity := BallPoint((X-A.P.X)/Gap,(B.P.Y-A.P.Y)/Gap-0.5*PIN_GRAVITY*Gap);
  Result.Bank := Bank;
end;

function TakesOff(const A: TPinContact; const Incoming,V: TBallPoint): Boolean;
var
  NormalSpeed, Slide: Double;
begin
  NormalSpeed := BallDot(V,A.Normal);
  if A.Body=PIN_EXIT then Exit((V.X< -0.08) and (BallDot(BallUnit(V),A.Normal)>0.64));
  if A.Body=PIN_KICKER then Exit((V.Y< -0.25) and (V.X> -0.25));
  if A.Body>=PIN_LEFT_FLIPPER then Exit((V.Y< -0.35) and (NormalSpeed>0.3));
  // Powered pop bumpers add impulse mainly along their radial normal.
  Slide := BallDot(BallSub(V,Incoming),BallPoint(-A.Normal.Y,A.Normal.X));
  Result := (NormalSpeed>0.16) and (Abs(Slide)<=0.48+0.52*BallLength(Incoming));
end;

function Lands(const B: TPinContact; const V: TBallPoint): Boolean;
begin
  if B.Body=PIN_KICKER then Exit((V.Y>0.13) and (BallLength(V)<2.6));
  Result := (BallDot(V,B.Normal)< -0.12) and ((B.Body<PIN_LEFT_FLIPPER) or (V.Y>0.16));
end;

function ShotAngle(Body: Integer; const A,B: TPinContact; Time: Double): Double;
var
  U: Double;
begin
  U := 0;
  if A.Body=Body then U := Swing(Time-A.Time);
  if B.Body=Body then U := Max(U,Swing(Time-B.Time));
  Result := RestAngle+(StrikeAngle-RestAngle)*U;
end;

function ClearShot(const Shot: TPinFlight; const A,B: TPinContact; StepsPerSecond: Integer): Boolean;
var
  I,J,N: Integer;
  Point: TBallPoint;
  T, Gap, Radius: Double;
  LeftCup: Boolean;
begin
  Gap := Shot.Last-Shot.First;
  N := Max(2,Ceil(Gap*StepsPerSecond));
  LeftCup := A.Body<>PIN_KICKER;
  for I := 0 to N do begin
    T := Shot.First+Gap*I/N;
    Point := PinPoint(Shot,T);
    if (Point.X<PIN_LEFT-ContactEps) or (Point.X>PIN_RIGHT+ContactEps) or
      (Point.Y<0.132) or (Point.Y>1.515) then Exit(False);
    if Point.Y<0.80 then for J := 0 to PIN_BUMPERS-1 do begin
      Radius := PIN_RADIUS+PinBumperRadius(J)-ContactEps;
      if not RadiusOK(Point,PinBumper(J),Radius) then Exit(False);
    end;
    if Point.Y>1.28 then for J := PIN_LEFT_FLIPPER to PIN_RIGHT_FLIPPER do
      if ArmDistance(Point,J,ShotAngle(J,A,B,T))<PIN_FLIPPER_RADIUS+PIN_RADIUS-ContactEps then Exit(False);
    if RadiusOK(Point,PinKicker,KickerRadius) then LeftCup := True
    else if LeftCup and (B.Body<>PIN_KICKER) then Exit(False);
  end;
  Result := True;
end;

function TargetSamples: TArray<TPinContact>;
var
  Body,I,N: Integer;
  Angle,Along: Double;
  P,Nrm: TBallPoint;
begin
  SetLength(Result,PIN_BUMPERS*16+7);
  N := 0;
  for Body := 0 to PIN_BUMPERS-1 do for I := 0 to 15 do begin
    Angle := I*Pi/8;
    Nrm := BallPoint(Cos(Angle),Sin(Angle));
    Result[N].Body := Body;
    Result[N].Normal := Nrm;
    Result[N].P := BallAdd(PinBumper(Body),BallScale(Nrm,PinBumperRadius(Body)+PIN_RADIUS));
    Inc(N);
  end;
  for Body := PIN_LEFT_FLIPPER to PIN_RIGHT_FLIPPER do for I := 0 to 2 do begin
    P := PinArm(Body,StrikeAngle);
    Nrm := BallPoint(P.Y,-P.X);
    if Body=PIN_RIGHT_FLIPPER then Nrm := BallScale(Nrm,-1);
    Along := 0.055+I*0.049;
    Result[N].Body := Body;
    Result[N].Normal := Nrm;
    Result[N].P := BallAdd(BallAdd(PinPivot(Body),BallScale(P,Along)),BallScale(Nrm,PIN_FLIPPER_RADIUS+PIN_RADIUS));
    Inc(N);
  end;
  Result[N].Body := PIN_KICKER;
  Result[N].P := PinKicker;
end;

function Threshold(Audio: TRhythmAudio): Double;
var
  Peak: Double;
  I: Integer;
begin
  Peak := 0;
  for I := 0 to High(Audio.Hits) do
    if Audio.Hits[I].Time<=Audio.SoundEnd then Peak := Max(Peak,Audio.Hits[I].Strength);
  Result := Max(0.20,Peak*StrongFraction);
end;

class function TPinballPlan.Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TPinballPlan;
const
  TrialTimes: array[0..10] of Double = (0.19,0.24,0.30,0.38,0.46,0.55,0.65,0.76,0.89,1.04,1.20);
var
  Contacts: TList<TPinContact>;
  Flights: TList<TPinFlight>;
  Samples: TArray<TPinContact>;
  A: TPinContact;
  Incoming: TBallPoint;
  Choice: TPinChoice;
  Start, NextTime, Cut, LastStrength, Rest, Minimum: Double;
  Source, LastSource, I, J, PreviousBody, UpperRally: Integer;
  procedure CancelPoint;
  begin
    if Assigned(Cancel) and Cancel() then Abort;
  end;
  function LowerBound(Time: Double): Integer;
  var Lo,Hi,Mid: Integer;
  begin
    Lo := 0;
    Hi := Length(Audio.Hits);
    while Lo<Hi do begin
      Mid := (Lo+Hi) div 2;
      if Audio.Hits[Mid].Time<Time then Lo := Mid+1 else Hi := Mid;
    end;
    Result := Lo;
  end;
  function FindAt(AtTime, Leave: Double; Onset: Integer; EscapeOnly: Boolean;
    const From: TPinContact; const InSpeed: TBallPoint; var Best: TPinChoice): Boolean;
  var
    S, Bank: Integer;
    B: TPinContact;
    Shot: TPinFlight;
    V: TBallPoint;
    Speed, Cost, Power, Turn: Double;
  begin
    Result := False;
    if (AtTime-Leave<MinFlight-1E-9) or (AtTime-Leave>MaxFlight+1E-9) then Exit;
    for S := 0 to High(Samples) do begin
      B := Samples[S];
      if (B.Body=From.Body) or ((From.Body=PIN_EXIT) and (B.Body>=PIN_LEFT_FLIPPER)) then Continue;
      if (B.Body=PIN_KICKER) and (From.Body=PIN_KICKER) then Continue;
      B.Time := AtTime;
      B.Source := Onset;
      for Bank := -1 to 1 do begin
        if (Bank<>0) and (From.Body=PIN_EXIT) then Continue;
        Shot := MakeShot(From,B,Leave,Bank);
        Speed := BallLength(Shot.Velocity);
        if (Speed<0.39) or (Speed>3.75) or not TakesOff(From,InSpeed,Shot.Velocity) then Continue;
        V := PinVelocity(Shot,AtTime);
        if (BallLength(V)>4.1) or not Lands(B,V) then Continue;
        Cost := 0;
        if not EscapeOnly then begin
          if Onset>=0 then Power := Audio.Hits[Onset].Strength else Power := 0;
          Turn := Abs(Ln(Max(0.20,Speed)/1.45));
          Cost := 0.45*Turn+0.15*Abs(AtTime-Leave-0.49)+0.055*Abs(Bank);
          if Onset>=0 then Cost := Cost-0.92-0.90*Power;
          if B.Body<PIN_BUMPERS then begin
            // Let the ball return to the lower playfield after a short bumper rally.
            if (B.P.Y<0.54) and (B.Normal.Y<0.10) then Cost := Cost+0.38+0.19*Min(4,UpperRally);
            if PreviousBody=B.Body then Cost := Cost+0.32;
            if (UpperRally>=3) and (From.Body<PIN_LEFT_FLIPPER) then Cost := Cost+0.50;
          end;
          if B.Body=PIN_KICKER then Cost := Cost+0.22;
          if (B.Body>=PIN_LEFT_FLIPPER) and (B.Body<=PIN_RIGHT_FLIPPER) and (From.Body<PIN_LEFT_FLIPPER) then
            Cost := Cost-0.10;
          if From.Body=PIN_KICKER then Cost := Cost+0.13*(Leave-From.Time);
          if Cost>=Best.Cost then Continue;
        end;
        if not ClearShot(Shot,From,B,240) then Continue;
        if EscapeOnly then Exit(True);
        Best.Shot := Shot;
        Best.Target := B;
        Best.Cost := Cost;
        Best.EndVelocity := V;
        Result := True;
      end;
    end;
  end;
  function CanContinue(const B: TPinContact; const Velocity: TBallPoint): Boolean;
  var
    K: Integer;
    Dummy: TPinChoice;
  begin
    for K := 2 to High(TrialTimes) do
      if FindAt(B.Time+TrialTimes[K],B.Time,-1,True,B,Velocity,Dummy) then Exit(True);
    Result := False;
  end;
  procedure Consider(AtTime, Leave: Double; Onset: Integer);
  var
    Candidate: TPinChoice;
  begin
    Candidate.Cost := Choice.Cost;
    if FindAt(AtTime,Leave,Onset,False,A,Incoming,Candidate) and
      CanContinue(Candidate.Target,Candidate.EndVelocity) then Choice := Candidate;
  end;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or
    (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then
    raise EArgumentException.Create('Pinball audio bounds');
  CancelPoint;
  Cut := Threshold(Audio);
  LastStrength := -1;
  for I := 0 to High(Audio.Hits) do begin
    if (I mod 128)=0 then CancelPoint;
    if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or
      (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time<LastStrength) or
      (Audio.Hits[I].Strength<0) or (Audio.Hits[I].Strength>1) then raise EArgumentException.Create('Pinball sound event');
    LastStrength := Audio.Hits[I].Time;
  end;
  Result := TPinballPlan.Create;
  Contacts := nil;
  Flights := nil;
  try
    try
      Result.FSoundEnd := Audio.SoundEnd;
      Result.FEnd := Audio.Duration;
      if (Audio.SoundEnd<0.98) or (Length(Audio.Hits)=0) then begin
        Result.Verify(Audio,Cancel);
        Exit;
      end;
      Contacts := TList<TPinContact>.Create;
      Flights := TList<TPinFlight>.Create;
      Samples := TargetSamples;
      A := Default(TPinContact);
      A.Time := GuideLength;
      A.Body := PIN_EXIT;
      A.Source := -1;
      A.P := PinLaunchGuide(1);
      A.Normal := BallUnit(BallPoint(-0.081,0.065));
      Incoming := BallPoint(0,0);
      LastSource := -1;
      PreviousBody := PIN_EXIT;
      UpperRally := 0;
      Result.FStart := 0;
      Result.FExit := A.Time;
      while (A.Time<Audio.SoundEnd) and (Contacts.Count<MaxContacts) do begin
        CancelPoint;
        Choice.Cost := 1E20;
        Start := A.Time;
        Minimum := Start+MinFlight;
        Source := LowerBound(Minimum);
        J := Source;
        while J<Length(Audio.Hits) do begin
          NextTime := Audio.Hits[J].Time;
          if (NextTime>Start+MaxFlight+Ord(A.Body=PIN_KICKER)*0.85) or (NextTime>Audio.SoundEnd) then Break;
          if (J>LastSource) and (Audio.Hits[J].Strength>=Cut) then begin
            Consider(NextTime,Start,J);
            if A.Body=PIN_KICKER then for I := 0 to 4 do begin
              Rest := 0.20+I*0.16;
              if NextTime-Start-Rest>=MinFlight then Consider(NextTime,Start+Rest,J);
            end;
          end;
          Inc(J);
        end;
        for I := 0 to High(TrialTimes) do Consider(Start+TrialTimes[I],Start,-1);
        if Choice.Cost>=1E19 then begin
          // Allow a safe final impact if there is no follow-on at the very end.
          for I := 0 to High(TrialTimes) do
            FindAt(Start+TrialTimes[I],Start,-1,False,A,Incoming,Choice);
          if Choice.Cost>=1E19 then Break;
        end;
        Flights.Add(Choice.Shot);
        Contacts.Add(Choice.Target);
        if Choice.Target.Source>=0 then LastSource := Choice.Target.Source;
        PreviousBody := A.Body;
        A := Choice.Target;
        if A.Body<PIN_BUMPERS then Inc(UpperRally) else UpperRally:=0;
        Incoming := Choice.EndVelocity;
      end;
      if (Contacts.Count=0) or (Contacts.Last.Time<Audio.SoundEnd-1E-9) then
        raise EInvalidOp.Create('Fixed pinball could not complete the rally to the end of the track');
      Result.FEnd := Max(Audio.Duration,Contacts.Last.Time);
      Result.FContacts := Contacts.ToArray;
      Result.FFlights := Flights.ToArray;
      Result.Verify(Audio,Cancel);
    except
      Result.Free;
      raise;
    end;
  finally
    Flights.Free;
    Contacts.Free;
  end;
end;

procedure TPinballPlan.Verify(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>);
var
  I,J,LastSource: Integer;
  A,B: TPinContact;
  Shot: TPinFlight;
  Incoming,V: TBallPoint;
  Cut: Double;
  procedure Need(Value: Boolean; const Reason: string);
  begin
    if not Value then raise EConvertError.CreateFmt('Fixed pinball flight %d: %s',[I,Reason]);
  end;
begin
  I := -1;
  Cut := Threshold(Audio);
  FSynced := 0;
  FFlippers := 0;
  FBumpers := 0;
  FStrong := 0;
  for J := 0 to High(Audio.Hits) do if (Audio.Hits[J].Time>=GuideLength+MinFlight) and
    (Audio.Hits[J].Time<=Audio.SoundEnd) and (Audio.Hits[J].Strength>=Cut) then Inc(FStrong);
  Need(Finite(FStart) and Finite(FExit) and Finite(FEnd) and (FStart>=0) and
    (FEnd>=Audio.Duration-1E-8) and (FEnd<=Audio.Duration+MaxFlight+1E-8) and
    (Length(FFlights)=Count) and (Count<=MaxContacts),'plan bounds');
  if Count=0 then begin
    Need((FStart=0) and (FExit=0),'stationary table');
    Exit;
  end;
  Need(Abs(FExit-FStart-GuideLength)<1E-8,'launch guide timing');
  Need(FContacts[Count-1].Time>=FSoundEnd-1E-9,'rally ended before sound');
  A := Default(TPinContact);
  A.Body := PIN_EXIT;
  A.Time := FExit;
  A.P := PinLaunchGuide(1);
  A.Normal := BallUnit(BallPoint(-0.081,0.065));
  Incoming := BallPoint(0,0);
  LastSource := -1;
  for I := 0 to Count-1 do begin
    if Assigned(Cancel) and Cancel() then Abort;
    Shot := FFlights[I];
    B := FContacts[I];
    Need(Finite(Shot.First) and Finite(Shot.Last) and Finite(Shot.Velocity.X) and Finite(Shot.Velocity.Y) and
      (Shot.First>=A.Time-1E-9) and ((A.Body=PIN_KICKER) or (Abs(Shot.First-A.Time)<1E-9)) and
      (B.Time=Shot.Last) and (Shot.Last-Shot.First>=MinFlight-1E-9) and
      (Shot.Last-Shot.First<=MaxFlight+1E-9) and (Shot.Bank>=-1) and (Shot.Bank<=1),'flight timing');
    Need((B.Body>=0) and (B.Body<=PIN_KICKER) and (A.Body<>B.Body) and
      (BallLength(BallSub(Shot.A,A.P))<=ContactEps) and
      (BallLength(BallSub(PinPoint(Shot,B.Time),B.P))<=ContactEps),'position continuity');
    V := PinVelocity(Shot,Shot.Last);
    Need((BallLength(Shot.Velocity)>=0.39-1E-8) and (BallLength(Shot.Velocity)<=3.75+1E-8) and
      (BallLength(V)<=4.1+1E-8) and TakesOff(A,Incoming,Shot.Velocity) and Lands(B,V),'contact direction or speed');
    if B.Body<PIN_BUMPERS then begin
      Need(Abs(BallLength(BallSub(B.P,PinBumper(B.Body)))-PinBumperRadius(B.Body)-PIN_RADIUS)<ContactEps,'bumper surface');
      Need(BallLength(BallSub(B.Normal,BallUnit(BallSub(B.P,PinBumper(B.Body)))))<ContactEps,'bumper normal');
    end else if B.Body<PIN_KICKER then begin
      Need(Abs(ArmDistance(B.P,B.Body,StrikeAngle)-PIN_FLIPPER_RADIUS-PIN_RADIUS)<ContactEps,'raised flipper surface');
    end else Need(BallLength(BallSub(B.P,PinKicker))<ContactEps,'kicker socket');
    Need(ClearShot(Shot,A,B,480),'unplanned contact');
    if B.Source>=0 then begin
      Need((B.Source>LastSource) and (B.Source<Length(Audio.Hits)) and Audio.HasHitDetails,'invalid onset reference');
      Need((B.Time=Audio.Hits[B.Source].Time) and (Audio.Hits[B.Source].Strength>=Cut),'onset or strength changed');
      LastSource := B.Source;
      Inc(FSynced);
      if B.Body<PIN_BUMPERS then Inc(FBumpers)
      else if B.Body<PIN_KICKER then Inc(FFlippers);
    end else Need(B.Source=-1,'incidental source');
    A := B;
    Incoming := V;
  end;
end;

function TPinballPlan.GetCount: Integer;
begin
  Result := Length(FContacts);
end;

function TPinballPlan.GetContact(Index: Integer): TPinContact;
begin
  Result := FContacts[Index];
end;

function TPinballPlan.GetFlight(Index: Integer): TPinFlight;
begin
  Result := FFlights[Index];
end;

function TPinballPlan.Before(Time: Double): Integer;
var Lo,Hi,Mid: Integer;
begin
  Lo := 0;
  Hi := Count;
  while Lo<Hi do begin
    Mid := (Lo+Hi) div 2;
    if FContacts[Mid].Time<=Time then Lo := Mid+1 else Hi := Mid;
  end;
  Result := Lo-1;
end;

function TPinballPlan.FlightAt(Time: Double): Integer;
begin
  Result := Min(Count-1,Before(Time)+1);
end;

function TPinballPlan.PositionAt(Time: Double): TBallPoint;
var
  U: Double;
begin
  if (Count=0) or (Time<=FStart) then Exit(BallPoint(LaunchX,LaunchY));
  if Time<FExit then begin
    if Time>=FExit-GuideTurn then Exit(PinLaunchGuide((Time-(FExit-GuideTurn))/GuideTurn));
    U := EnsureRange((Time-FStart)/(GuideLength-GuideTurn),0.0,1.0);
    Exit(BallPoint(LaunchX,LaunchY+(0.268-LaunchY)*U*U*(1.55-0.55*U)));
  end;
  Result := PinPoint(FFlights[FlightAt(Time)],Time);
end;

function TPinballPlan.FlipperAngle(Body: Integer; Time: Double): Double;
var I,K: Integer; Travel: Double;
begin
  Travel := 0;
  I := Before(Time);
  for K := Max(0,I-1) to Min(Count-1,I+1) do if FContacts[K].Body=Body then
    Travel := Max(Travel,Swing(Time-FContacts[K].Time));
  Result := RestAngle+(StrikeAngle-RestAngle)*Travel;
end;

function TPinballPlan.Flash(Body: Integer; Time: Double): Double;
var I: Integer; Age: Double;
begin
  Result := 0;
  for I := Before(Time) downto 0 do begin
    Age := Time-FContacts[I].Time;
    if Age>0.19 then Break;
    if FContacts[I].Body=Body then begin
      Result := Sqr(1-Age/0.19);
      if FContacts[I].Source<0 then Result := Result*0.35;
      Exit;
    end;
  end;
end;

procedure TPinballPlan.Save(var Ref: TRhythmPlanRef; Audio: TRhythmAudio);
var
  Root: TJSONObject;
  Rows, Row: TJSONArray;
  I: Integer;
  B: TPinContact;
  S: TPinFlight;
  procedure Add(Value: Double);
  begin
    Row.AddElement(PreparedExact(Value));
  end;
begin
  if (Ref.Version<>7) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsBall) then
    raise EArgumentException.Create('Pinball reference');
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema',1);
    Root.AddPair('layout','fixed-pinball-v1');
    Root.AddPair('style',StyleId(rsBall));
    Root.AddPair('version',Ref.Version);
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',Ref.Sensitivity);
    Root.AddPair('direction',Ref.Direction);
    Root.AddPair('start',PreparedExact(FStart));
    Root.AddPair('exit',PreparedExact(FExit));
    Root.AddPair('end',PreparedExact(FEnd));
    AddPreparedAudio(Root,Audio);
    Rows := TJSONArray.Create;
    Root.AddPair('shots',Rows);
    for I := 0 to Count-1 do begin
      B := FContacts[I];
      S := FFlights[I];
      Row := TJSONArray.Create;
      Rows.AddElement(Row);
      Row.Add(B.Body).Add(B.Source).Add(S.Bank);
      Add(B.Time); Add(B.P.X); Add(B.P.Y); Add(B.Normal.X); Add(B.Normal.Y);
      Add(S.First); Add(S.Velocity.X); Add(S.Velocity.Y);
    end;
    WritePreparedData(Root,Ref);
  finally
    Root.Free;
  end;
end;

class function TPinballPlan.Load(const Ref: TRhythmPlanRef; Audio: TRhythmAudio; Direction: Integer): TPinballPlan;
var
  Root: TJSONObject;
  Rows, Row: TJSONArray;
  I: Integer;
  P: TBallPoint;
  B: TPinContact;
  S: TPinFlight;
  function Number(Index: Integer): Double;
  begin
    Result := ReadPreparedExact(Row.Items[Index]);
  end;
begin
  if (Ref.Version<>7) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsBall) then
    raise EArgumentException.Create('Pinball reference');
  Root := ReadPreparedData(Ref,rsBall,Direction);
  try
    if Root.GetValue<string>('layout','')<>'fixed-pinball-v1' then raise EConvertError.Create('Pinball layout');
    Rows := Root.GetValue<TJSONArray>('shots');
    if (Rows=nil) or (Rows.Count>MaxContacts) then raise EConvertError.Create('Pinball flight array');
    Result := TPinballPlan.Create;
    try
      Result.FStart := ReadPreparedExact(Root.GetValue('start'));
      Result.FExit := ReadPreparedExact(Root.GetValue('exit'));
      Result.FEnd := ReadPreparedExact(Root.GetValue('end'));
      Result.FSoundEnd := Audio.SoundEnd;
      SetLength(Result.FContacts,Rows.Count);
      SetLength(Result.FFlights,Rows.Count);
      P := PinLaunchGuide(1);
      for I := 0 to Rows.Count-1 do begin
        if not (Rows.Items[I] is TJSONArray) then raise EConvertError.Create('Pinball flight record');
        Row := TJSONArray(Rows.Items[I]);
        if Row.Count<>11 then raise EConvertError.Create('Pinball flight width');
        B.Body := Row.Items[0].GetValue<Integer>;
        B.Source := Row.Items[1].GetValue<Integer>;
        S.Bank := Row.Items[2].GetValue<Integer>;
        B.Time := Number(3);
        B.P := BallPoint(Number(4),Number(5));
        B.Normal := BallPoint(Number(6),Number(7));
        S.A := P;
        S.First := Number(8);
        S.Last := B.Time;
        S.Velocity := BallPoint(Number(9),Number(10));
        Result.FContacts[I] := B;
        Result.FFlights[I] := S;
        P := B.P;
      end;
      Result.Verify(Audio,nil);
    except Result.Free;raise;end;
  finally
    Root.Free;
  end;
end;

end.
