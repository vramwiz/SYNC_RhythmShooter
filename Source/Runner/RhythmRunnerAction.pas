unit RhythmRunnerAction;
// Runner v6. Immutable A/B/C score; rendering and cold restore never re-plan.
interface
uses System.SysUtils,System.JSON,RhythmAudio;
const
  RA_SPEED=0.42;
  RA_GROUND=0.76;
  RA_GRAVITY=3.8;
  RA_WALK_STEP=0.060;
type
  TRunMode=(rmJump,rmSword,rmBoss);
  TRunHitKind=(rhPulse,rhLand,rhSword,rhBossCut,rhParry,rhDodge,rhHurt,rhFinish);
  TRunPoint=record
    X,Y:Double;
  end;
  TRunSection=record
    Start,Finish,X:Double;
    Mode:TRunMode;
    First,Last:Integer;
  end;
  TRunPad=record
    Land,Leave,Left,Right,Y,AX,AY,Phase,Period,Fall:Double;
    Section:Integer;
  end;
  TRunJump=record
    Time,Takeoff,StartX,StartY,X,Y,Velocity:Double;
    Pad,FromPad,Source:Integer;
  end;
  TRunHit=record
    Time,Strength,X,Y,Show,Kill:Double;
    Source,Section,Target,BossHP,HeroHP:Integer;
    Kind:TRunHitKind;
  end;
  TRunPose=record
    X,Y:Double;
    Airborne:Boolean;
    Pose:Integer;
  end;
  TRunFeet=record
    LeftFoot,RightFoot:TRunPoint;
    Step,Phase,Plant,Direction:Integer;
    Moving:Boolean;
  end;
  TRunMotionKey=record
    Time,X,Travel,Direction:Double;
  end;
  TRunMotionSample=record
    X,Travel,Velocity,Direction:Double;
  end;
  TRunBossPose=record
    X,Y,Turn,Size:Double;
    Airborne:Boolean;
  end;
  TRunnerActionPlan=class
  private
    FActive,FEnemies:TArray<Integer>;
    FHeroMotion,FBossMotion:TArray<TRunMotionKey>;
    FSectionTravel:TArray<Double>;
    FHeroTravelEnd:Double;
  public
    Sections:TArray<TRunSection>;
    Pads:TArray<TRunPad>;
    Jumps:TArray<TRunJump>;
    Hits:TArray<TRunHit>;
    Goal:Double;
    Frequency,SourceCount,Excluded:Integer;
  private
    procedure MakeMotion;
    procedure IndexActions;
  public
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRunnerActionPlan; static;
    function ToJSON:TJSONObject;
    class function FromJSON(Root:TJSONObject;Audio:TRhythmAudio):TRunnerActionPlan; static;
    procedure Validate;
    function SectionAt(Time:Double):Integer;
    function HitBefore(Time:Double):Integer;
    function ActionBefore(Time:Double):Integer;
    function EnemyBefore(Time:Double):Integer;
    function EnemyIndex(Index:Integer):Integer;
    function EnemyCount:Integer;
    function PadBefore(Time:Double):Integer;
    function JumpBefore(Time:Double):Integer;
    function WorldAt(Time:Double):Double;
    function PadOffset(Index:Integer;Time:Double):TRunPoint;
    function PadAt(Index:Integer;Time:Double):TRunPad;
    function HeroAt(Time:Double):TRunPose;
    function FeetAt(Time:Double):TRunFeet;
    function BossAt(Time:Double):TRunBossPose;
    function BossFeetAt(Time:Double):TRunFeet;
    function BladeAt(Time:Double;out Grip,Tip:TRunPoint):Boolean;
    function EnemyBladeAt(Time:Double;out Grip,Tip:TRunPoint):Boolean;
    function ModeCount(Mode:TRunMode):Integer;
  end;
implementation
uses System.Math,System.Generics.Collections,RhythmSections;

function Pt(X,Y:Double):TRunPoint;
begin Result.X:=X;
  Result.Y:=Y;
end;

function Good(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

procedure Need(V:Boolean;const S:string);
begin if not V then raise Exception.Create('Runner ABC: '+S);
end;

function TRunnerActionPlan.ModeCount(Mode:TRunMode):Integer;
var
  S:TRunSection;
begin Result:=0;
  for S in Sections do if S.Mode=Mode then Inc(Result);
end;

function TRunnerActionPlan.SectionAt(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(Sections);
  while A<B do begin M:=(A+B) div 2;
    if Sections[M].Start<=Time then A:=M+1 else B:=M;
  end;
  Result:=Max(0,A-1);
end;

function TRunnerActionPlan.HitBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(Hits);
  while A<B do begin M:=(A+B) div 2;
    if Hits[M].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

procedure TRunnerActionPlan.IndexActions;
var
  I,N,E:Integer;
begin SetLength(FActive,Length(Hits));
  SetLength(FEnemies,Length(Hits));
  N:=0;
  E:=0;
  for I:=0 to High(Hits) do begin if Hits[I].Kind<>rhPulse then begin FActive[N]:=I;
      Inc(N);
    end;
    if Hits[I].Kind=rhSword then if (I=0) or (Hits[I-1].Kind<>rhSword) or (Hits[I-1].Target<>Hits[I].Target) then begin FEnemies[E]:=I;
      Inc(E);
    end;
  end;
  SetLength(FActive,N);
  SetLength(FEnemies,E);
  MakeMotion;
end;

function TRunnerActionPlan.ActionBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(FActive);
  while A<B do begin M:=(A+B) div 2;
    if Hits[FActive[M]].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=-1;
  if A>0 then Result:=FActive[A-1];
end;

function TRunnerActionPlan.EnemyBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(FEnemies);
  while A<B do begin M:=(A+B) div 2;
    if Hits[FEnemies[M]].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TRunnerActionPlan.EnemyCount:Integer;
begin Result:=Length(FEnemies);
end;

function TRunnerActionPlan.EnemyIndex(Index:Integer):Integer;
begin Result:=FEnemies[Index];
end;

function TRunnerActionPlan.PadBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(Pads);
  while A<B do begin M:=(A+B) div 2;
    if Pads[M].Land<=Time then A:=M+1 else B:=M;
  end;
  Result:=Max(0,A-1);
end;

function TRunnerActionPlan.JumpBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Length(Jumps);
  while A<B do begin M:=(A+B) div 2;
    if Jumps[M].Takeoff<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TRunnerActionPlan.WorldAt(Time:Double):Double;
var
  S:TRunSection;
begin Time:=EnsureRange(Time,0.0,Goal+1.6);
  S:=Sections[SectionAt(Min(Time,Goal))];
  Result:=S.X;
  if S.Mode<>rmBoss then Result:=Result+RA_SPEED*(Min(Time,Goal)-S.Start);
  if Time>Goal then Result:=Result+RA_SPEED*(Time-Goal)+1.5*Sqr(Max(0.0,Time-Goal-0.25));
end;

function TRunnerActionPlan.PadOffset(Index:Integer;Time:Double):TRunPoint;
var
  P:TRunPad;
  A,B:Double;
begin P:=Pads[Index];
  A:=Sin((Time-P.Land)*2*Pi/P.Period+P.Phase);
  B:=Sin(P.Phase);
  Result:=Pt(P.AX*(A-B),P.AY*(A-B));
end;

function TRunnerActionPlan.PadAt(Index:Integer;Time:Double):TRunPad;
var
  O:TRunPoint;
begin Result:=Pads[Index];
  O:=PadOffset(Index,Time);
  Result.Left:=Result.Left+O.X;
  Result.Right:=Result.Right+O.X;
  Result.Y:=Result.Y+O.Y;
  if (Result.Fall>=0) and (Time>Result.Fall) then Result.Y:=Result.Y+2.8*Sqr(Time-Result.Fall);
end;
// Derived presentation keys use the saved accent times/contact anchors. They
// never alter the score, boss HP, sections, audio clock or serialized rows.

function SampleRunnerMotion(const Keys:TArray<TRunMotionKey>;Time:Double):TRunMotionSample;
var
  A,B,M:Integer;
  K,L:TRunMotionKey;
  U,D:Double;
begin
  Result:=Default(TRunMotionSample);
  Result.Direction:=1;
  if Length(Keys)=0 then Exit;
  A:=0;
  B:=Length(Keys);
  while A<B do begin M:=(A+B) div 2;
    if Keys[M].Time<=Time then A:=M+1 else B:=M;
  end;
  A:=Max(0,A-1);
  K:=Keys[A];
  Result.X:=K.X;
  Result.Travel:=K.Travel;
  Result.Direction:=K.Direction;
  if A>=High(Keys) then Exit;
  L:=Keys[A+1];
  D:=L.Time-K.Time;
  if D<=0 then Exit;
  U:=EnsureRange((Time-K.Time)/D,0.0,1.0);
  Result.X:=K.X+(L.X-K.X)*U;
  Result.Travel:=K.Travel+Abs(Result.X-K.X);
  Result.Velocity:=(L.X-K.X)/D;
  if Abs(Result.Velocity)>1E-8 then Result.Direction:=Sign(Result.Velocity);
end;

function RunnerGroundFeet(X,Y,Travel,Velocity,Direction,StepLength:Double):TRunFeet;
var
  U,Anchor,SwingX,SwingY:Double;
  Plant,Swing:TRunPoint;
begin
  Result:=Default(TRunFeet);
  Result.Step:=Floor(Travel/StepLength);
  U:=Travel/StepLength-Result.Step;
  Result.Phase:=EnsureRange(Trunc(U*4),0,3);
  Result.Plant:=Result.Step mod 2;
  Result.Direction:=Round(Direction);
  Result.Moving:=Abs(Velocity)>0.01;
  Anchor:=X-Direction*U*StepLength;
  Plant:=Pt(Anchor+Direction*0.5*StepLength,Y);
  case Result.Phase of
    0:begin SwingX:=-0.5;
      SwingY:=0;
    end;
    1:begin SwingX:=0;
      SwingY:=-0.012;
    end;
    2:begin SwingX:=0.75;
      SwingY:=-0.018;
    end;
    else SwingX:=1.5;
    SwingY:=0;
  end;
  if not Result.Moving then SwingY:=0;
  Swing:=Pt(Anchor+Direction*SwingX*StepLength,Y+SwingY);
  if Result.Plant=0 then begin Result.LeftFoot:=Plant;
    Result.RightFoot:=Swing;
  end
  else begin Result.LeftFoot:=Swing;
    Result.RightFoot:=Plant;
  end;
end;

procedure TRunnerActionPlan.MakeMotion;
var
  HeroKeys,BossKeys:TList<TRunMotionKey>;
  Events:TList<Integer>;
  S:TRunSection;
  H:TRunHit;
  I,J,N,HeroFirst,BossFirst:Integer;
  HeroExtra,BossExtra,Previous,Next,Pre,Post:Double;
  HeroPre,HeroHit,HeroPost,BossPre,BossHit,BossPost:Double;
  procedure Key(List:TList<TRunMotionKey>;First:Integer;Time,X,BaseTravel:Double);
  var
    K,P:TRunMotionKey;
    Index:Integer;
  begin
    K:=Default(TRunMotionKey);
    K.Time:=Time;
    K.X:=X;
    K.Direction:=1;
    Index:=List.Count;
    if Index>First then if Abs(List[Index-1].Time-Time)<1E-10 then Dec(Index);
    K.Travel:=BaseTravel;
    if Index>First then begin P:=List[Index-1];
      Need(Time>P.Time,'motion key order');
      K.Travel:=P.Travel+Abs(X-P.X);
      K.Direction:=P.Direction;
      if Abs(X-P.X)>1E-8 then K.Direction:=Sign(X-P.X);
    end;
    if Index<List.Count then List[Index]:=K else List.Add(K);
  end;
begin
  SetLength(FSectionTravel,Length(Sections));
  HeroExtra:=0;
  BossExtra:=0;
  HeroKeys:=TList<TRunMotionKey>.Create;
  BossKeys:=TList<TRunMotionKey>.Create;
  Events:=TList<Integer>.Create;
  try
    N:=0;
    for I:=0 to High(Sections) do begin
      S:=Sections[I];
      FSectionTravel[I]:=HeroExtra;
      if S.Mode<>rmBoss then Continue;
      Events.Clear;
      while N<Length(FActive) do begin J:=FActive[N];
        if Hits[J].Section>I then Break;
        if Hits[J].Section=I then Events.Add(J);
        Inc(N);
      end;
      HeroFirst:=HeroKeys.Count;
      BossFirst:=BossKeys.Count;
      Key(HeroKeys,HeroFirst,S.Start,S.X,S.X+HeroExtra);
      Key(BossKeys,BossFirst,S.Start,S.X+1.11,S.X+BossExtra);
      Key(HeroKeys,HeroFirst,S.Start+0.60,S.X,S.X+HeroExtra);
      Key(BossKeys,BossFirst,S.Start+0.60,S.X+0.40,S.X+BossExtra);
      Previous:=S.Start+0.60;
      for J:=0 to Events.Count-1 do begin H:=Hits[Events[J]];
        if not (H.Kind in [rhBossCut,rhParry,rhDodge,rhHurt,rhFinish]) then Continue;
        Next:=S.Finish;
        if J<Events.Count-1 then Next:=Hits[Events[J+1]].Time;
        Pre:=Min(0.24,Max(0.0,(H.Time-Previous)*0.42));
        Post:=Min(0.20,Max(0.0,(Next-H.Time)*0.40));
        case H.Kind of
          rhBossCut,rhFinish:begin HeroPre:=-0.045;
            HeroHit:=0.080;
            HeroPost:=-0.030;
            BossPre:=0.40;
            BossHit:=0.31;
            BossPost:=0.445;
          end;
          rhParry:begin HeroPre:=0.035;
            HeroHit:=-0.015;
            HeroPost:=-0.060;
            BossPre:=0.44;
            BossHit:=0.24;
            BossPost:=0.38;
          end;
          rhDodge:begin HeroPre:=0.015;
            HeroHit:=-0.095;
            HeroPost:=-0.040;
            BossPre:=0.43;
            BossHit:=0.20;
            BossPost:=0.37;
          end;
          else HeroPre:=0.020;
          HeroHit:=0;
          HeroPost:=-0.115;
          BossPre:=0.43;
          BossHit:=0.20;
          BossPost:=0.36;
        end;
        Key(HeroKeys,HeroFirst,H.Time-Pre,S.X+HeroPre,S.X+HeroExtra);
        Key(BossKeys,BossFirst,H.Time-Pre,S.X+BossPre,S.X+BossExtra);
        Key(HeroKeys,HeroFirst,H.Time,S.X+HeroHit,S.X+HeroExtra);
        Key(BossKeys,BossFirst,H.Time,S.X+BossHit,S.X+BossExtra);
        // Brief grounded hold makes the contact readable before recoil.
        Key(HeroKeys,HeroFirst,H.Time+Min(0.025,Post*0.25),S.X+HeroHit,S.X+HeroExtra);
        Key(BossKeys,BossFirst,H.Time+Min(0.025,Post*0.25),S.X+BossHit,S.X+BossExtra);
        Key(HeroKeys,HeroFirst,H.Time+Post,S.X+HeroPost,S.X+HeroExtra);
        if H.Kind=rhFinish then BossPost:=BossHit;
        Key(BossKeys,BossFirst,H.Time+Post,S.X+BossPost,S.X+BossExtra);
        Previous:=H.Time;
      end;
      Key(HeroKeys,HeroFirst,S.Finish,S.X,S.X+HeroExtra);
      Key(BossKeys,BossFirst,S.Finish,S.X+0.40,S.X+BossExtra);
      HeroExtra:=HeroKeys[HeroKeys.Count-1].Travel-S.X;
      BossExtra:=BossKeys[BossKeys.Count-1].Travel-S.X;
    end;
    FHeroMotion:=HeroKeys.ToArray;
    FBossMotion:=BossKeys.ToArray;
    FHeroTravelEnd:=HeroExtra;
  finally Events.Free;
    BossKeys.Free;
    HeroKeys.Free;
  end;
end;

function TRunnerActionPlan.BossAt(Time:Double):TRunBossPose;
var
  S:TRunSection;
  M:TRunMotionSample;
  K:Integer;
  Age:Double;
begin
  Result:=Default(TRunBossPose);
  Time:=EnsureRange(Time,0.0,Goal+1.6);
  S:=Sections[SectionAt(Time)];
  if S.Mode<>rmBoss then Exit;
  M:=SampleRunnerMotion(FBossMotion,Time);
  Result.X:=M.X;
  Result.Size:=2.9;
  Result.Y:=RA_GROUND-0.028*Result.Size;
  K:=ActionBefore(Time);
  if K>=0 then if (Hits[K].Section=SectionAt(Time)) and (Hits[K].Kind=rhFinish) then begin
    Age:=Time-Hits[K].Time;
    Result.X:=Result.X+Age*0.48;
    Result.Y:=Result.Y-Age*0.65+1.1*Age*Age;
    Result.Turn:=Age*7;
    Result.Size:=Result.Size*Max(0.0,1-Age/0.6);
    Result.Airborne:=True;
  end;
end;

function TRunnerActionPlan.FeetAt(Time:Double):TRunFeet;
var
  P:TRunPose;
  M:TRunMotionSample;
  I:Integer;
  Travel,Velocity,Direction,Age:Double;
begin
  Time:=EnsureRange(Time,0.0,Goal+1.6);
  P:=HeroAt(Time);
  I:=SectionAt(Time);
  Travel:=WorldAt(Time)+FSectionTravel[I];
  Velocity:=RA_SPEED;
  Direction:=1;
  if (Sections[I].Mode=rmBoss) and (Time<=Goal) then begin M:=SampleRunnerMotion(FHeroMotion,Time);
    Travel:=M.Travel;
    Velocity:=M.Velocity;
    Direction:=M.Direction;
  end;
  if Time>Goal then begin Travel:=WorldAt(Time)+FHeroTravelEnd;
    Age:=Time-Goal;
    Velocity:=RA_SPEED+3*Max(0.0,Age-0.25);
  end;
  Result:=RunnerGroundFeet(P.X,P.Y,Travel,Velocity,Direction,RA_WALK_STEP);
  if P.Airborne then begin Result.Moving:=False;
    Result.LeftFoot:=Pt(P.X-0.018,P.Y-0.012);
    Result.RightFoot:=Pt(P.X+0.018,P.Y-0.018);
  end;
end;

function TRunnerActionPlan.BossFeetAt(Time:Double):TRunFeet;
var
  M:TRunMotionSample;
  B:TRunBossPose;
begin M:=SampleRunnerMotion(FBossMotion,Time);
  B:=BossAt(Time);
  Result:=RunnerGroundFeet(B.X,RA_GROUND,M.Travel,M.Velocity,M.Direction,RA_WALK_STEP*1.6);
  if B.Airborne then Result.Moving:=False;
end;

function TRunnerActionPlan.HeroAt(Time:Double):TRunPose;
var
  K,I,N:Integer;
  P:TRunPad;
  O:TRunPoint;
  J:TRunJump;
  Age,U:Double;
  H:TRunHit;
  Motion:TRunMotionSample;
begin
  Time:=EnsureRange(Time,0.0,Goal+1.6);
  Result:=Default(TRunPose);
  Result.X:=WorldAt(Time);
  Result.Y:=RA_GROUND;
  Result.Pose:=0;
  if (Time<=Goal) and (Sections[SectionAt(Time)].Mode=rmBoss) then begin Motion:=SampleRunnerMotion(FHeroMotion,Time);
    Result.X:=Motion.X;
  end;
  if Sections[SectionAt(Time)].Mode=rmJump then begin K:=PadBefore(Time);
    P:=Pads[K];
    O:=PadOffset(K,Time);
    Result.X:=Result.X+O.X;
    Result.Y:=P.Y+O.Y;
  end;
  K:=JumpBefore(Time);
  if K>=0 then begin J:=Jumps[K];
    if (Time>=J.Takeoff) and (Time<J.Time) then begin Age:=Time-J.Takeoff;
      U:=Age/(J.Time-J.Takeoff);
      Result.X:=J.StartX+(J.X-J.StartX)*U;
      Result.Y:=J.StartY+J.Velocity*Age+0.5*RA_GRAVITY*Age*Age;
      Result.Airborne:=True;
      Result.Pose:=2;
    end;
  end;
  I:=ActionBefore(Time);
  if (I<0) or (Abs(Hits[I].Time-Time)>1E-8) then I:=ActionBefore(Time+0.055);
  for N:=0 to 3 do begin if I<0 then Break;
    H:=Hits[I];
    Age:=Time-H.Time;
    I:=ActionBefore(H.Time-1E-8);
    if Age>0.22 then Break;
    if Age< -0.055 then Continue;
    if H.Kind in [rhSword,rhBossCut,rhFinish] then begin
      // Anticipation is visible before the accent; contact starts on its time.
      if Age< 0 then Result.Pose:=3 else if Age<=0.025 then Result.Pose:=4 else Result.Pose:=5;
      Break;
    end;
    if H.Kind=rhParry then begin Result.Pose:=6;
      Break;
    end;
    if H.Kind=rhHurt then begin if Age<0 then Result.Pose:=6 else Result.Pose:=7;
      Break;
    end;
    if H.Kind=rhDodge then begin U:=(Age+0.20)/0.40;
      if (U>=0) and (U<1) then begin Result.Y:=RA_GROUND-0.17*4*U*(1-U);
        Result.Airborne:=True;
        Result.Pose:=2;
      end;
      Break;
    end;
  end;
  // Dodge wind-up begins earlier than a sword anticipation.
  I:=ActionBefore(Time+0.20);
  if I>=0 then begin H:=Hits[I];
    Age:=Time-H.Time;
    if (H.Kind=rhDodge) and (Age>=-0.20) and (Age<=0.20) then begin U:=(Age+0.20)/0.40;
      Result.Y:=RA_GROUND-0.17*4*U*(1-U);
      Result.Airborne:=True;
      Result.Pose:=2;
    end;
  end;
end;

function TRunnerActionPlan.BladeAt(Time:Double;out Grip,Tip:TRunPoint):Boolean;
var
  P:TRunPose;
  H:TRunHit;
  I:Integer;
  Age:Double;
begin P:=HeroAt(Time);
  Grip:=Pt(P.X+0.028,P.Y-0.082);
  Tip:=Pt(Grip.X+0.025,Grip.Y-0.10);
  Result:=False;
  I:=ActionBefore(Time);
  if (I<0) or (Abs(Hits[I].Time-Time)>1E-8) then I:=ActionBefore(Time+0.055);
  if I<0 then Exit;
  H:=Hits[I];
  Age:=Time-H.Time;
  if (Age< -0.055) or (Age>0.16) or not (H.Kind in [rhSword,rhBossCut,rhParry,rhFinish]) then Exit;
  Result:=True;
  if Age< 0 then begin Grip:=Pt(P.X+0.012,P.Y-0.12);
    Tip:=Pt(Grip.X-0.04,Grip.Y-0.065);
  end
  else if Age<=0.025 then Tip:=Pt(H.X,H.Y)
  else Tip:=Pt(Grip.X+0.10,Grip.Y+0.065);
end;

function TRunnerActionPlan.EnemyBladeAt(Time:Double;out Grip,Tip:TRunPoint):Boolean;
var
  I:Integer;
  H:TRunHit;
  Age,U:Double;
  Boss:TRunBossPose;
begin Grip:=Pt(0,0);
  Tip:=Grip;
  Result:=False;
  I:=ActionBefore(Time+0.28);
  if I<0 then Exit;
  H:=Hits[I];
  Age:=Time-H.Time;
  if not (H.Kind in [rhParry,rhDodge,rhHurt]) or (Age< -0.28) or (Age>0.18) then Exit;
  Boss:=BossAt(Time);
  Grip:=Pt(Boss.X-0.05,RA_GROUND-0.14);
  U:=EnsureRange(1+Age/0.28,0.0,1.0);
  Tip:=Pt(Grip.X+(H.X-Grip.X)*U,Grip.Y+(H.Y-Grip.Y)*U);
  Result:=True;
end;

class function TRunnerActionPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRunnerActionPlan;
var
  Sec,Base:TList<TRunSection>;
  PL:TList<TRunPad>;
  JL:TList<TRunJump>;
  HL:TList<TRunHit>;
  S,B:TRunSection;
  P:TRunPad;
  J:TRunJump;
  H:TRunHit;
  Cue:TRhythmBossCue;
  I,K,N,Q,V,From,BI,GroupFirst,HP,HeroHP,Cursor:Integer;
  Mode,Want:TRunMode;
  Last,Gap,Median,Start,Finish,X,D,T,Y,KillTime:Double;
  Gaps:TArray<Double>;
  procedure Check;
  begin if Assigned(Cancel) and Cancel() then Abort;
  end;
  procedure AddSection(A,Z:Double;M:TRunMode);
  begin if Z<=A+1E-8 then Exit;
    S:=Default(TRunSection);
    S.Start:=A;
    S.Finish:=Z;
    S.X:=X;
    S.Mode:=M;
    S.First:=-1;
    S.Last:=-1;
    Sec.Add(S);
    if M<>rmBoss then X:=X+RA_SPEED*(Z-A);
  end;
  procedure AddPad(Land,Y:Double;Moving:Boolean;Section:Integer);
  begin P:=Default(TRunPad);
    P.Land:=Land;
    P.Leave:=Result.Sections[Section].Finish;
    P.Left:=Result.WorldAt(Land)-0.09;
    P.Right:=Result.WorldAt(P.Leave)+0.10;
    P.Y:=Y;
    P.Fall:=-1;
    P.Period:=1.7+0.17*(PL.Count mod 4);
    P.Phase:=PL.Count*1.37;
    P.Section:=Section;
    if Moving then if PL.Count mod 2=0 then P.AX:=0.038 else P.AY:=0.030;
    PL.Add(P);
  end;
  procedure LandAt(Time,Y:Double;Source:Integer;Moving:Boolean);
  begin
    From:=PL.Count-1;
    P:=PL[From];
    D:=Min(0.82,Time-P.Land-0.10);
    if D<0.32 then Exit;
    J:=Default(TRunJump);
    J.Time:=Time;
    J.Takeoff:=Time-D;
    J.FromPad:=From;
    J.Source:=Source;
    // The launch point follows its support. Destination motion is evaluated at
    // the fixed audio time; it is not moved to meet the character at draw time.
    T:=Sin((J.Takeoff-P.Land)*2*Pi/P.Period+P.Phase)-Sin(P.Phase);
    J.StartX:=Result.WorldAt(J.Takeoff)+P.AX*T;
    J.StartY:=P.Y+P.AY*T;
    J.X:=Result.WorldAt(Time);
    J.Y:=Y;
    J.Velocity:=(Y-J.StartY)/D-0.5*RA_GRAVITY*D;
    P.Leave:=J.Takeoff;
    P.Right:=Max(P.Left+0.18,Result.WorldAt(J.Takeoff)+0.085);
    P.Fall:=J.Takeoff+0.10;
    PL[From]:=P;
    AddPad(Time,Y,Moving,K);
    J.Pad:=PL.Count-1;
    JL.Add(J);
  end;
begin
  Need(Audio<>nil,'missing audio');
  Check;
  Result:=TRunnerActionPlan.Create;
  Sec:=TList<TRunSection>.Create;
  Base:=TList<TRunSection>.Create;
  PL:=TList<TRunPad>.Create;
  JL:=TList<TRunJump>.Create;
  HL:=TList<TRunHit>.Create;
  try try
      Result.Goal:=Audio.SoundEnd;
      Result.Frequency:=Audio.BossFrequency;
      Result.SourceCount:=Length(Audio.Hits);
      Need(Good(Result.Goal) and (Result.Goal>=0) and (Result.Goal<=Audio.Duration) and (Length(Audio.Hits)<=100000),'audio bounds');
      Last:=-1;
      for I:=0 to High(Audio.Hits) do begin Check;
        T:=Audio.Hits[I].Time;
        Need(Good(T) and Good(Audio.Hits[I].Strength) and (T>=Last) and (T>=0) and (T<=Audio.Duration+0.011),'source order');
        Last:=T;
      end;
      // Local median uses ORIGINAL analysis accents, before action grouping.
      // Separate entry/exit thresholds and a 3 s dwell prevent threshold chatter.
      Mode:=rmJump;
      Start:=0;
      Last:=-10;
      for I:=1 to High(Audio.Hits) do begin Check;
        if Audio.Hits[I].Time>Result.Goal then Break;
        SetLength(Gaps,0);
        for Q:=Max(1,I-3) to Min(High(Audio.Hits),I+3) do begin Gap:=Audio.Hits[Q].Time-Audio.Hits[Q-1].Time;
          if Gap>1E-7 then begin N:=Length(Gaps);
            SetLength(Gaps,N+1);
            Gaps[N]:=Gap;
          end;
        end;
        if Length(Gaps)<3 then Continue;
        TArray.Sort<Double>(Gaps);
        Median:=Gaps[Length(Gaps) div 2];
        Want:=Mode;
        if Median<=0.38 then Want:=rmSword else if Median>=0.52 then Want:=rmJump;
        if (Want<>Mode) and (Audio.Hits[I].Time-Last>=3.0) then begin
          B:=Default(TRunSection);
          B.Start:=Start;
          B.Finish:=Audio.Hits[I].Time;
          B.Mode:=Mode;
          if B.Finish>Start then Base.Add(B);
          Start:=B.Finish;
          Last:=Start;
          Mode:=Want;
        end;
      end;
      B:=Default(TRunSection);
      B.Start:=Start;
      B.Finish:=Result.Goal;
      B.Mode:=Mode;
      Base.Add(B);
      // Overlay common boss cues. Ready/kill are actual source events. Short
      // clips and cues with too few attacks remain normal A/B sections.
      Start:=0;
      X:=0;
      BI:=0;
      for I:=0 to Audio.BossCount-1 do begin Check;
        if BI>=64 then Break;
        Cue:=Audio.BossCue(I);
        Q:=Audio.NearestHit(Cue.StartTime);
        V:=Audio.NearestHit(Cue.KillTime);
        if (Q<0) or (V<=Q+3) or (V>High(Audio.Hits)) then Continue;
        Finish:=Audio.Hits[V].Time;
        T:=Max(Start+1.0,Audio.Hits[Q].Time-0.75);
        if (Finish-T<3) or (Finish>Result.Goal) then Continue;
        for B in Base do if (B.Finish>Start) and (B.Start<T) then AddSection(Max(Start,B.Start),Min(T,B.Finish),B.Mode);
        AddSection(T,Min(Result.Goal,Finish+0.60),rmBoss);
        Start:=Min(Result.Goal,Finish+0.60);
        Inc(BI);
      end;
      for B in Base do if B.Finish>Start then AddSection(Max(Start,B.Start),B.Finish,B.Mode);
      if Sec.Count=0 then AddSection(0,Max(0.001,Result.Goal),rmJump);
      Result.Sections:=Sec.ToArray;
      Q:=0;
      for K:=0 to High(Result.Sections) do begin Check;
        S:=Result.Sections[K];
        AddPad(S.Start,RA_GROUND,False,K);
        while (Q<Length(Audio.Hits)) and (Audio.Hits[Q].Time<=S.Start+1E-8) do Inc(Q);
        if S.Mode=rmJump then begin
          while (Q<Length(Audio.Hits)) and (Audio.Hits[Q].Time<S.Finish-0.95) do begin Check;
            T:=Audio.Hits[Q].Time;
            if T-PL[PL.Count-1].Land>=0.66 then begin Y:=0.68+0.045*Sin(JL.Count*1.7);
              LandAt(T,Y,Q,True);
            end;
            Inc(Q);
          end;
          if S.Finish-PL[PL.Count-1].Land>=0.48 then LandAt(S.Finish,RA_GROUND,-1,False);
        end;
      end;
      Result.Pads:=PL.ToArray;
      Result.Jumps:=JL.ToArray;
      Result.Pads[High(Result.Pads)].Right:=Result.WorldAt(Result.Goal)+3.0;
      // Assign every source accent. Dense accents can hit successive armor
      // points on one enemy for <=140 ms; each audio contact is retained.
      GroupFirst:=-1;
      N:=0;
      for I:=0 to High(Audio.Hits) do begin Check;
        T:=Audio.Hits[I].Time;
        if (Result.Goal<=0) or (T>Result.Goal+1E-6) then begin Inc(Result.Excluded);
          Continue;
        end;
        K:=Result.SectionAt(T);
        S:=Result.Sections[K];
        H:=Default(TRunHit);
        H.Time:=T;
        H.Source:=I;
        H.Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);
        H.Section:=K;
        H.Target:=-1;
        H.Kind:=rhPulse;
        H.Show:=Max(S.Start,T-1.8);
        H.Kill:=T;
        H.X:=Result.WorldAt(T);
        H.Y:=RA_GROUND;
        if S.Mode=rmJump then begin for Q:=Max(0,Result.JumpBefore(T)-1) to Min(High(Result.Jumps),Result.JumpBefore(T)+1) do if Result.Jumps[Q].Source=I then begin H.Kind:=rhLand;
            H.X:=Result.Jumps[Q].X;
            H.Y:=Result.Jumps[Q].Y;
            Break;
          end;
        end
        else if S.Mode=rmSword then begin
          H.Kind:=rhSword;
          if (GroupFirst<0) or (HL[GroupFirst].Section<>K) or (T-HL[GroupFirst].Time>0.14+1E-9) or (T-HL[HL.Count-1].Time>0.105+1E-9) then begin GroupFirst:=HL.Count;
            Inc(N);
          end;
          H.Target:=N;
          H.Y:=RA_GROUND-0.028;
          if GroupFirst=HL.Count then H.X:=Result.WorldAt(T)+0.145 else begin H.X:=HL[GroupFirst].X;
            H.Show:=HL[GroupFirst].Show;
          end;
        end
        else begin
          H.Kind:=rhBossCut;
          H.X:=S.X+0.23;
          H.Y:=RA_GROUND-0.10;
          H.Show:=S.Start;
        end;
        HL.Add(H);
      end;
      Result.Hits:=HL.ToArray;
      // Use the already assigned section IDs. Subtracting an epsilon from a
      // floating boundary can omit its final source accent on long songs.
      Cursor:=0;
      for K:=0 to High(Result.Sections) do begin S:=Result.Sections[K];
        S.First:=Cursor;
        while (Cursor<Length(Result.Hits)) and (Result.Hits[Cursor].Section=K) do Inc(Cursor);
        S.Last:=Cursor-1;
        Result.Sections[K]:=S;
        if S.Mode=rmBoss then begin
          V:=Result.HitBefore(S.Finish-0.59);
          V:=EnsureRange(V,S.First,S.Last);
          KillTime:=Result.Hits[V].Time;
          HeroHP:=4;
          V:=0;
          Last:=-10;
          for I:=S.First to S.Last do begin H:=Result.Hits[I];
            if Abs(H.Time-KillTime)<1E-8 then begin H.Kind:=rhFinish;
              Last:=H.Time;
            end
            else if (H.Time<S.Start+0.60) or (H.Time>KillTime-0.46) or (H.Time-Last<0.44) then H.Kind:=rhPulse
            else begin case V mod 8 of 1,7:H.Kind:=rhParry;
                3:H.Kind:=rhDodge;
                5:H.Kind:=rhHurt;
                else H.Kind:=rhBossCut;
              end;
              Inc(V);
              Last:=H.Time;
            end;
            if H.Kind=rhParry then begin H.X:=S.X+0.09;
              H.Y:=RA_GROUND-0.10;
            end;
            if H.Kind=rhDodge then begin H.X:=S.X;
              H.Y:=RA_GROUND;
            end;
            if H.Kind=rhHurt then begin H.X:=S.X+0.025;
              H.Y:=RA_GROUND-0.10;
              HeroHP:=Max(1,HeroHP-1);
            end;
            H.HeroHP:=HeroHP;
            Result.Hits[I]:=H;
          end;
          HP:=0;
          for I:=S.First to S.Last do if Result.Hits[I].Kind in [rhBossCut,rhFinish] then Inc(HP);
          Q:=HP;
          for I:=S.First to S.Last do begin H:=Result.Hits[I];
            if H.Kind in [rhBossCut,rhFinish] then Dec(Q);
            H.BossHP:=Q;
            H.Target:=Max(1,HP);
            Result.Hits[I]:=H;
          end;
        end;
      end;
      // Propagate grouped enemy kill times without dropping any source accent.
      I:=0;
      while I<Length(Result.Hits) do begin H:=Result.Hits[I];
        V:=I;
        if H.Kind=rhSword then begin while (V<High(Result.Hits)) and (Result.Hits[V+1].Kind=rhSword) and (Result.Hits[V+1].Target=H.Target) do Inc(V);
          for Q:=I to V do begin H:=Result.Hits[Q];
            H.Kill:=Result.Hits[V].Time;
            Result.Hits[Q]:=H;
          end;
        end;
        I:=V+1;
      end;
      Result.IndexActions;
      Result.Validate;
    except Result.Free;
      raise;
    end;
  finally Sec.Free;
    Base.Free;
    PL.Free;
    JL.Free;
    HL.Free;
  end;
end;

procedure TRunnerActionPlan.Validate;
var
  I,K:Integer;
  S:TRunSection;
  P:TRunPad;
  J:TRunJump;
  H:TRunHit;
  Pose:TRunPose;
  G,T:TRunPoint;
  Previous:Double;
begin
  Need(Good(Goal) and (Goal>=0) and (Frequency>=0) and (Frequency<=100) and (Excluded>=0) and (SourceCount>=0) and (SourceCount<=100000),'header');
  Need((Length(Sections)>0) and (Length(Sections)<=20000) and (Length(Pads)>0) and (Length(Pads)<=40001) and (Length(Jumps)<=20000) and (Length(Hits)<=100000),'limits');
  Previous:=0;
  for I:=0 to High(Sections) do begin S:=Sections[I];
    Need(Good(S.Start) and Good(S.Finish) and Good(S.X) and (Abs(S.Start-Previous)<1E-7) and (S.Finish>S.Start) and (S.X>=0),'sections');
    Previous:=S.Finish;
    Need((S.First>=0) and (S.Last<Length(Hits)) and (S.Last>=S.First-1),'section hit range');
    if I>0 then Need(Abs(S.X-(Sections[I-1].X+Ord(Sections[I-1].Mode<>rmBoss)*RA_SPEED*(Sections[I-1].Finish-Sections[I-1].Start)))<1E-7,'scroll continuity');
  end;
  Need(Abs(Previous-Max(0.001,Goal))<1E-7,'section end');
  Previous:=-1;
  for P in Pads do begin Need(Good(P.Land) and Good(P.Leave) and Good(P.Left) and Good(P.Right) and Good(P.Y) and Good(P.AX) and Good(P.AY) and Good(P.Phase) and Good(P.Period) and Good(P.Fall),'finite pad');
    Need((P.Land>=Previous) and (P.Leave>=P.Land) and (P.Right>P.Left) and (Abs(P.AX)<=0.04) and (Abs(P.AY)<=0.04) and (P.Period>=1) and (P.Section>=0) and (P.Section<Length(Sections)),'pad bounds');
    Previous:=P.Land;
  end;
  Previous:=-1;
  for J in Jumps do begin Need(Good(J.Time) and Good(J.Takeoff) and Good(J.StartX) and Good(J.StartY) and Good(J.X) and Good(J.Y) and Good(J.Velocity),'finite jump');
    Need((J.Takeoff>=Previous) and (J.Time>J.Takeoff) and (J.Time<=Goal+1E-7) and (J.Pad>=0) and (J.Pad<Length(Pads)) and (J.FromPad>=0) and (J.FromPad<J.Pad) and (J.Source>=-1) and (J.Source<SourceCount),'jump bounds');
    Previous:=J.Time;
    Need((J.Velocity<0) and (J.Velocity+RA_GRAVITY*(J.Time-J.Takeoff)>0),'jump direction');
    P:=PadAt(J.Pad,J.Time);
    Need((J.X>=P.Left) and (J.X<=P.Right) and (Abs(J.Y-P.Y)<1E-7),'moving destination');
    P:=PadAt(J.FromPad,J.Takeoff);
    Need((J.StartX>=P.Left) and (J.StartX<=P.Right) and (Abs(J.StartY-P.Y)<1E-7),'moving departure');
    Need(Abs(J.StartY+J.Velocity*(J.Time-J.Takeoff)+0.5*RA_GRAVITY*Sqr(J.Time-J.Takeoff)-J.Y)<1E-7,'ballistic endpoint');
  end;
  Previous:=-1;
  for I:=0 to High(Hits) do begin H:=Hits[I];
    Need(Good(H.Time) and Good(H.Strength) and Good(H.X) and Good(H.Y) and Good(H.Show) and Good(H.Kill),'finite hit');
    Need((H.Time>=Previous) and (H.Time<=Goal+1E-6) and (H.Show<=H.Time) and (H.Kill>=H.Time) and (H.Source>=0) and (H.Source<SourceCount) and (H.Section>=0) and (H.Section<Length(Sections)),'hit bounds');
    Previous:=H.Time;
    Need((H.Strength>=0) and (H.Strength<=1) and (H.Source=I),'source/strength');
    K:=SectionAt(H.Time);
    Need(K=H.Section,Format('hit section index %d time %.12f saved %d expected %d',[I,H.Time,H.Section,K]));
    Need((I>=Sections[K].First) and (I<=Sections[K].Last),'section action range; re-prepare Runner');
    if H.Kind in [rhSword,rhBossCut,rhParry,rhFinish] then begin BladeAt(H.Time,G,T);
      Need(Hypot(T.X-H.X,T.Y-H.Y)<1E-7,'blade contact');
      Pose:=HeroAt(H.Time);
      Need(not Pose.Airborne,'ground sword');
    end;
    if H.Kind in [rhParry,rhDodge,rhHurt] then begin Need(EnemyBladeAt(H.Time,G,T),'enemy attack');
      Need(Hypot(T.X-H.X,T.Y-H.Y)<1E-7,'enemy contact');
    end;
  end;
  Need(Length(Hits)+Excluded=SourceCount,'source retention');
end;

function TRunnerActionPlan.ToJSON:TJSONObject;
var
  A,R:TJSONArray;
  S:TRunSection;
  P:TRunPad;
  J:TRunJump;
  H:TRunHit;
  // JSON's decimal reader can round a 17-digit value by one ULP. Exact binary64
  // rows keep contact times and section boundaries identical after cold load.
  procedure Row(const Values:array of Double);
  var
    V:Double;
    Bits:UInt64;
  begin R:=TJSONArray.Create;
    A.AddElement(R);
    for V in Values do begin Move(V,Bits,SizeOf(Bits));
      R.Add(IntToHex(Bits,16));
    end;
  end;
begin Result:=TJSONObject.Create;
  Result.AddPair('policy','abc-moving-pixel-v1');
  Result.AddPair('goal',TJSONNumber.Create(Goal));
  Result.AddPair('frequency',TJSONNumber.Create(Frequency));
  Result.AddPair('sourceCount',TJSONNumber.Create(SourceCount));
  Result.AddPair('excluded',TJSONNumber.Create(Excluded));
  A:=TJSONArray.Create;
  Result.AddPair('sections',A);
  for S in Sections do Row([S.Start,S.Finish,S.X,Ord(S.Mode),S.First,S.Last]);
  A:=TJSONArray.Create;
  Result.AddPair('pads',A);
  for P in Pads do Row([P.Land,P.Leave,P.Left,P.Right,P.Y,P.AX,P.AY,P.Phase,P.Period,P.Fall,P.Section]);
  A:=TJSONArray.Create;
  Result.AddPair('jumps',A);
  for J in Jumps do Row([J.Time,J.Takeoff,J.StartX,J.StartY,J.X,J.Y,J.Velocity,J.Pad,J.FromPad,J.Source]);
  A:=TJSONArray.Create;
  Result.AddPair('hits',A);
  for H in Hits do Row([H.Time,H.Strength,H.X,H.Y,H.Show,H.Kill,H.Source,H.Section,H.Target,H.BossHP,H.HeroHP,Ord(H.Kind)]);
end;

class function TRunnerActionPlan.FromJSON(Root:TJSONObject;Audio:TRhythmAudio):TRunnerActionPlan;
var
  A,R:TJSONArray;
  I:Integer;
  function Table(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);
    Need((Result<>nil) and (Result.Count<=Limit),'JSON '+Name);
  end;
  procedure Row(N:Integer);
  begin Need(A.Items[I] is TJSONArray,'JSON row');
    R:=A.Items[I] as TJSONArray;
    Need(R.Count=N,'JSON columns');
  end;
  function V(K:Integer):Double;
  var
    Bits:UInt64;
  begin Need((R.Items[K] is TJSONString) and (Length(R.Items[K].Value)=16),'JSON binary64');
    Need(TryStrToUInt64('$'+R.Items[K].Value,Bits),'JSON binary64 digits');
    Move(Bits,Result,SizeOf(Result));
    Need(Good(Result),'JSON finite');
  end;
  function Int(K,Low,High:Integer):Integer;
  var
    D:Double;
  begin D:=V(K);
    Need((D>=Low) and (D<=High) and (Frac(D)=0),'JSON integer');
    Result:=Trunc(D);
  end;
begin Need(Root<>nil,'missing action score');
  Need(Root.GetValue<string>('policy','')='abc-moving-pixel-v1','JSON policy');
  Result:=TRunnerActionPlan.Create;
  try Result.Goal:=Root.GetValue<Double>('goal');
    Result.Frequency:=Root.GetValue<Integer>('frequency');
    Result.SourceCount:=Root.GetValue<Integer>('sourceCount');
    Result.Excluded:=Root.GetValue<Integer>('excluded');
    Need((Abs(Result.Goal-Audio.SoundEnd)<1E-7) and (Result.SourceCount=Length(Audio.Hits)),'JSON audio identity');
    A:=Table('sections',20000);
    SetLength(Result.Sections,A.Count);
    for I:=0 to A.Count-1 do begin Row(6);
      with Result.Sections[I] do begin Start:=V(0);
        Finish:=V(1);
        X:=V(2);
        Mode:=TRunMode(Int(3,0,2));
        First:=Int(4,0,100000);
        Last:=Int(5,-1,100000);
      end;
    end;
    A:=Table('pads',40001);
    SetLength(Result.Pads,A.Count);
    for I:=0 to A.Count-1 do begin Row(11);
      with Result.Pads[I] do begin Land:=V(0);
        Leave:=V(1);
        Left:=V(2);
        Right:=V(3);
        Y:=V(4);
        AX:=V(5);
        AY:=V(6);
        Phase:=V(7);
        Period:=V(8);
        Fall:=V(9);
        Section:=Int(10,0,20000);
      end;
    end;
    A:=Table('jumps',20000);
    SetLength(Result.Jumps,A.Count);
    for I:=0 to A.Count-1 do begin Row(10);
      with Result.Jumps[I] do begin Time:=V(0);
        Takeoff:=V(1);
        StartX:=V(2);
        StartY:=V(3);
        X:=V(4);
        Y:=V(5);
        Velocity:=V(6);
        Pad:=Int(7,0,40001);
        FromPad:=Int(8,0,40001);
        Source:=Int(9,-1,100000);
      end;
    end;
    A:=Table('hits',100000);
    SetLength(Result.Hits,A.Count);
    for I:=0 to A.Count-1 do begin Row(12);
      with Result.Hits[I] do begin Time:=V(0);
        Strength:=V(1);
        X:=V(2);
        Y:=V(3);
        Show:=V(4);
        Kill:=V(5);
        Source:=Int(6,0,100000);
        Section:=Int(7,0,20000);
        Target:=Int(8,-1,100000);
        BossHP:=Int(9,0,100000);
        HeroHP:=Int(10,0,4);
        Kind:=TRunHitKind(Int(11,0,7));
      end;
    end;
    Result.IndexActions;
    Result.Validate;
  except Result.Free;
    raise;
  end;
end;
end.
