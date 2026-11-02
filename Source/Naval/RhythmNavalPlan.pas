unit RhythmNavalPlan;
// Prepared broadside battle. Music clocks are inputs, never simulation outcomes.
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef;
type
  TNavalPoint=record
    X,Y:Double;
  end;
  TNavalEvent=record
    Time,Strength:Double;
  end;
  TNavalPhrase=record
    First,Last,Zoom:Double;
    Mode,Theme:Integer;
    Section:Boolean;
  end;
  TNavalShip=record
    Show,Arrive,Kill,X,Y,Size,Phase:Double;
    Boss,KillSource,HP:Integer;
  end;
  TNavalHit=record
    Source,Target,Kind,Gun,Shot:Integer;
  end;
  TNavalShot=record
    Launch,Finish,Radius,Arc:Double;
    A,B:TNavalPoint;
    Kind,Owner:Integer;
  end;
  TNavalPlan=class
  private
    FEvents:TArray<TNavalEvent>;
    FShips:TArray<TNavalShip>;
    FHits:TArray<TNavalHit>;
    FShots:TArray<TNavalShot>;
    FPhrases:TArray<TNavalPhrase>;
    FShipOrder,FShotOrder,FBosses,FPlayerHits:TArray<Integer>;
    FShipHits:TArray<TArray<Double>>;
    FDuration,FGoal,FEnd:Double;
    FFrequency,FPulses,FExcluded:Integer;
    FSeed:Cardinal;
    procedure Reindex;
    procedure Validate;
    procedure MakePhrases(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
    procedure MakeBattle(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
    function BossFor(Time:Double):Integer;
    function GetCount:Integer;
    function GetPulseCount:Integer;
    function GetBossCount:Integer;
    function GetShipCount:Integer;
    function GetShotCount:Integer;
    function GetPhraseCount:Integer;
    function GetHit(Index:Integer):TNavalHit;
    function GetEvent(Index:Integer):TNavalEvent;
    function GetShip(Index:Integer):TNavalShip;
    function GetShot(Index:Integer):TNavalShot;
    function GetPhrase(Index:Integer):TNavalPhrase;
    function GunBase(Time:Double;Gun:Integer):TNavalPoint;
    function HullContact(Index:Integer;Time:Double;const From:TNavalPoint;Radius:Double):TNavalPoint;
  public
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TNavalPlan; static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TNavalPlan; static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio; static;
    function HeroAt(Time:Double):TNavalPoint;
    function HeroAngle(Time:Double):Double;
    function ShipAt(Index:Integer;Time:Double):TNavalPoint;
    function ShipAngle(Index:Integer;Time:Double):Double;
    function HealthAt(Index:Integer;Time:Double):Double;
    function PartTime(Index,Part:Integer):Double;
    function HeroGun(Time:Double;Gun:Integer):TNavalPoint;
    function DamageAt(Time:Double):Double;
    function PhraseBefore(Time:Double):Integer;
    function HitBefore(Time:Double):Integer;
    function ShotBefore(Time:Double):Integer;
    function ShipBefore(Time:Double):Integer;
    function DrawShot(Index:Integer):TNavalShot;
    function DrawShipIndex(Index:Integer):Integer;
    function Boss(Index:Integer):Integer;
    function CannonPath(Index:Integer;out Launch,Finish,Arc:Double;out A,B:TNavalPoint):Boolean;
    function CannonAt(Index:Integer;Time:Double;out P:TNavalPoint):Boolean;
    function ShotAt(const Shot:TNavalShot;Time:Double):TNavalPoint;
    function ShotSafe(const Shot:TNavalShot):Boolean;
    procedure CameraAt(Time:Double;out Center:TNavalPoint;out Zoom:Double);
    property Count:Integer read GetCount;
    property PulseCount:Integer read GetPulseCount;
    property BossCount:Integer read GetBossCount;
    property ShipCount:Integer read GetShipCount;
    property ShotCount:Integer read GetShotCount;
    property PhraseCount:Integer read GetPhraseCount;
    property Hits[Index:Integer]:TNavalHit read GetHit;
    property Events[Index:Integer]:TNavalEvent read GetEvent;
    property Ships[Index:Integer]:TNavalShip read GetShip;
    property Shots[Index:Integer]:TNavalShot read GetShot;
    property Phrases[Index:Integer]:TNavalPhrase read GetPhrase;
    property EndTime:Double read FEnd;
    property GoalTime:Double read FGoal;
    property Frequency:Integer read FFrequency;
    property Excluded:Integer read FExcluded;
  end;
function NavalPoint(X,Y:Double):TNavalPoint;
implementation
uses System.Math,System.JSON,System.Generics.Collections,System.Generics.Defaults,RhythmStyles,RhythmPreparedData,RhythmSections;
type
  TNavalOrder=record
    Time:Double;
    Index:Integer;
  end;
  TNavalBoundary=record
    Time:Double;
    Section:Boolean;
  end;

function NavalPoint(X,Y:Double):TNavalPoint;
begin Result.X:=X;
  Result.Y:=Y;
end;

function Finite(X:Double):Boolean;
begin Result:=not IsNan(X) and not IsInfinite(X);
end;

function Number(X:Double):TJSONNumber;
begin Result:=TJSONNumber.Create(FloatToStrF(X,ffGeneral,17,0,TFormatSettings.Invariant));
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function VAdd(const A,B:TNavalPoint):TNavalPoint;
begin Result:=NavalPoint(A.X+B.X,A.Y+B.Y);
end;

function VSub(const A,B:TNavalPoint):TNavalPoint;
begin Result:=NavalPoint(A.X-B.X,A.Y-B.Y);
end;

function VMul(const A:TNavalPoint;S:Double):TNavalPoint;
begin Result:=NavalPoint(A.X*S,A.Y*S);
end;

function VUnit(const A:TNavalPoint):TNavalPoint;
var
  D:Double;
begin D:=Hypot(A.X,A.Y);
  if D<1E-12 then Exit(NavalPoint(1,0));
  Result:=VMul(A,1/D);
end;

function ArcPoint(const A,B:TNavalPoint;U,Arc:Double):TNavalPoint;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=NavalPoint(A.X+(B.X-A.X)*U,A.Y+(B.Y-A.Y)*U-Arc*Sin(Pi*U));
end;

procedure Check(const Cancel:TFunc<Boolean>);
begin if Assigned(Cancel) and Cancel() then Abort;
end;

function TNavalPlan.GetCount:Integer;
begin Result:=Length(FHits);
end;

function TNavalPlan.GetPulseCount:Integer;
begin Result:=FPulses;
end;

function TNavalPlan.GetBossCount:Integer;
begin Result:=Length(FBosses);
end;

function TNavalPlan.GetShipCount:Integer;
begin Result:=Length(FShips);
end;

function TNavalPlan.GetShotCount:Integer;
begin Result:=Length(FShots);
end;

function TNavalPlan.GetPhraseCount:Integer;
begin Result:=Length(FPhrases);
end;

function TNavalPlan.GetHit(Index:Integer):TNavalHit;
begin Result:=FHits[Index];
end;

function TNavalPlan.GetEvent(Index:Integer):TNavalEvent;
begin Result:=FEvents[Index];
end;

function TNavalPlan.GetShip(Index:Integer):TNavalShip;
begin Result:=FShips[Index];
end;

function TNavalPlan.GetShot(Index:Integer):TNavalShot;
begin Result:=FShots[Index];
end;

function TNavalPlan.GetPhrase(Index:Integer):TNavalPhrase;
begin Result:=FPhrases[Index];
end;

function TNavalPlan.DrawShot(Index:Integer):TNavalShot;
begin Result:=FShots[FShotOrder[Index]];
end;

function TNavalPlan.DrawShipIndex(Index:Integer):Integer;
begin Result:=FShipOrder[Index];
end;

function TNavalPlan.Boss(Index:Integer):Integer;
begin Result:=FBosses[Index];
end;

function TNavalPlan.PhraseBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=PhraseCount;
  while A<B do begin M:=(A+B) div 2;
    if FPhrases[M].First<=Time then A:=M+1 else B:=M;
  end;
  Result:=Max(0,A-1);
end;

function TNavalPlan.HitBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=Count;
  while A<B do begin M:=(A+B) div 2;
    if FEvents[FHits[M].Source].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TNavalPlan.ShotBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=ShotCount;
  while A<B do begin M:=(A+B) div 2;
    if FShots[FShotOrder[M]].Launch<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TNavalPlan.ShipBefore(Time:Double):Integer;
var
  A,B,M:Integer;
begin A:=0;
  B:=ShipCount;
  while A<B do begin M:=(A+B) div 2;
    if FShips[FShipOrder[M]].Kill<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TNavalPlan.HeroAt(Time:Double):TNavalPoint;
var
  I:Integer;
  U,D,Entry,Exit:Double;
begin Time:=EnsureRange(Time,0.0,FEnd);
  I:=PhraseBefore(Time);
  D:=0;
  if PhraseCount>0 then if FPhrases[I].Mode=1 then begin U:=(Time-FPhrases[I].First)/Max(1E-6,FPhrases[I].Last-FPhrases[I].First);
    D:=Sqr(Sin(Pi*EnsureRange(U,0.0,1.0)));
  end;
  Result:=NavalPoint(0.46+0.075*Sin(Time*0.53)+0.030*Sin(Time*1.31)+0.035*D*Sin(Time*2.6),0.685+0.036*Sin(Time*0.82)+0.045*D*Sin(Time*2.1));
  Entry:=1-Smooth(Time/0.75);
  Result.X:=Result.X-0.42*Entry;
  if Time>FGoal then begin Exit:=Smooth((Time-FGoal)/Max(0.1,FEnd-FGoal));
    Result.X:=Result.X+0.36*Exit;
    Result.Y:=Result.Y-0.16*Exit;
  end;
end;

function TNavalPlan.HeroAngle(Time:Double):Double;
var
  I:Integer;
  D,U:Double;
begin I:=PhraseBefore(Time);
  D:=0;
  if PhraseCount>0 then if FPhrases[I].Mode=1 then begin U:=(Time-FPhrases[I].First)/Max(1E-6,FPhrases[I].Last-FPhrases[I].First);
    D:=Sqr(Sin(Pi*EnsureRange(U,0.0,1.0)));
  end;
  Result:=0.045*Sin(Time*1.1)+0.15*D*Sin(Time*2.1);
end;

function TNavalPlan.HeroGun(Time:Double;Gun:Integer):TNavalPoint;
begin Result:=GunBase(Time,Gun);
end;

function TNavalPlan.PartTime(Index,Part:Integer):Double;
var
  N:Integer;
  Fraction:Double;
begin Result:=FShips[Index].Kill;
  if Length(FShipHits[Index])=0 then Exit;
  Fraction:=0.35;
  if Part=1 then Fraction:=0.68 else if Part>=2 then Fraction:=0.82;
  N:=EnsureRange(Ceil(FShips[Index].HP*Fraction)-1,0,High(FShipHits[Index]));
  Result:=FShipHits[Index][N];
end;

function TNavalPlan.GunBase(Time:Double;Gun:Integer):TNavalPoint;
var
  P:TNavalPoint;
  A,X,Y:Double;
begin P:=HeroAt(Time);
  A:=HeroAngle(Time);
  X:=(Gun mod 3-1)*0.075;
  Y:=-0.035;
  Result:=NavalPoint(P.X+X*Cos(A)-Y*Sin(A),P.Y+X*Sin(A)+Y*Cos(A));
end;

function TNavalPlan.ShipAt(Index:Integer;Time:Double):TNavalPoint;
var
  S:TNavalShip;
  U:Double;
  P:TNavalPoint;
begin S:=FShips[Index];
  Time:=Min(Time,S.Kill);
  if S.Boss<>0 then P:=NavalPoint(1.27+0.055*Sin(Time*0.73+S.Phase),0.29+0.015*Sin(Time*1.1))
  else P:=NavalPoint(S.X+0.14*(S.Kill-Time)+0.065*Sin(Time*(0.72+0.09*(Index mod 3))+S.Phase),S.Y+0.023*Sin(Time*1.15+S.Phase));
  U:=1;
  if S.Arrive>S.Show then U:=Smooth((Time-S.Show)/(S.Arrive-S.Show));
  Result:=NavalPoint(2.05+(P.X-2.05)*U,P.Y+0.045*(1-U));
end;

function TNavalPlan.ShipAngle(Index:Integer;Time:Double):Double;
begin Result:=0.035*Sin(Time*1.1+FShips[Index].Phase);
  if FShips[Index].Boss=0 then Result:=Result+0.025*Sin(Time*2.1);
end;

function TNavalPlan.HealthAt(Index:Integer;Time:Double):Double;
var
  A,B,M:Integer;
begin if (Index<0) or (Index>=ShipCount) then Exit(0);
  if Time>=FShips[Index].Kill then Exit(0);
  A:=0;
  B:=Length(FShipHits[Index]);
  while A<B do begin M:=(A+B) div 2;
    if FShipHits[Index][M]<=Time then A:=M+1 else B:=M;
  end;
  Result:=EnsureRange((FShips[Index].HP-A)/Max(1,FShips[Index].HP),0.0,1.0);
end;

function TNavalPlan.DamageAt(Time:Double):Double;
var
  I,A,B,M:Integer;
  Age:Double;
begin A:=0;
  B:=Length(FPlayerHits);
  while A<B do begin M:=(A+B) div 2;
    if FEvents[FHits[FPlayerHits[M]].Source].Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=0;
  for I:=A-1 downto Max(0,A-8) do begin Age:=Time-FEvents[FHits[FPlayerHits[I]].Source].Time;
    if (Age>=0) and (Age<2.8) then Result:=Max(Result,(1-Age/2.8));
  end;
  if Time>FGoal then Result:=Result*(1-Smooth((Time-FGoal)/Max(0.1,FEnd-FGoal)));
end;

function TNavalPlan.HullContact(Index:Integer;Time:Double;const From:TNavalPoint;Radius:Double):TNavalPoint;
var
  P:TNavalPoint;
  S,DX,DY,W,H,T:Double;
begin P:=ShipAt(Index,Time);
  S:=FShips[Index].Size;
  W:=0.12*S;
  H:=0.035*S;
  DX:=From.X-P.X;
  DY:=From.Y-P.Y;
  // Lower broadside is an opaque, axis-aligned physical hull face.
  T:=(H+Radius)/Max(1E-6,Abs(DY));
  Result:=NavalPoint(P.X+EnsureRange(DX*T,-W*0.82,W*0.82),P.Y+H+Radius);
end;

function TNavalPlan.CannonPath(Index:Integer;out Launch,Finish,Arc:Double;out A,B:TNavalPoint):Boolean;
var
  H:TNavalHit;
  Base,Direction:TNavalPoint;
  Flight:Double;
begin H:=FHits[Index];
  Finish:=FEvents[H.Source].Time;
  Flight:=0.46+FEvents[H.Source].Strength*0.10+(H.Gun mod 3)*0.025;
  Launch:=Max(0.0,Finish-Flight);
  Base:=GunBase(Launch,H.Gun);
  Result:=H.Kind<>2;
  if not Result then begin A:=Base;
    B:=Base;
    Arc:=0;
    Exit;
  end;
  if H.Kind=0 then B:=HullContact(H.Target,Finish,Base,0.008) else B:=FShots[H.Shot].B;
  Direction:=VUnit(VSub(B,Base));
  A:=VAdd(Base,VMul(Direction,0.025));
  Arc:=Min(0.055,Abs(B.Y-A.Y)*0.18);
  // Arrive from below faster than the drifting hull: a shallow near-horizontal
  // lob must not enter its moving side several milliseconds before the beat.
  if (H.Kind=0) and (Finish>Launch) then Arc:=Min(Arc,(-0.08*(Finish-Launch)-(B.Y-A.Y))/Pi);
end;

function TNavalPlan.CannonAt(Index:Integer;Time:Double;out P:TNavalPoint):Boolean;
var
  A,B:TNavalPoint;
  Launch,Finish,Arc:Double;
begin Result:=CannonPath(Index,Launch,Finish,Arc,A,B);
  if not Result then Exit;
  Result:=(Time>=Launch) and (Time<=Finish);
  if Result then begin if Time>=Finish then P:=B else P:=ArcPoint(A,B,(Time-Launch)/Max(1E-12,Finish-Launch),Arc);
  end;
end;

function TNavalPlan.ShotAt(const Shot:TNavalShot;Time:Double):TNavalPoint;
begin if Time>=Shot.Finish then Result:=Shot.B else Result:=ArcPoint(Shot.A,Shot.B,(Time-Shot.Launch)/Max(1E-12,Shot.Finish-Shot.Launch),Shot.Arc);
end;

function TNavalPlan.ShotSafe(const Shot:TNavalShot):Boolean;
var
  J:Integer;
  T:Double;
  P,H:TNavalPoint;
begin Result:=True;
  for J:=0 to 48 do begin T:=Shot.Launch+(Shot.Finish-Shot.Launch)*J/48;
    P:=ShotAt(Shot,T);
    H:=HeroAt(T);
    if (Abs(P.X-H.X)<0.168+Shot.Radius) and (Abs(P.Y-H.Y)<0.080+Shot.Radius) then Exit(False);
  end;
end;

function TNavalPlan.BossFor(Time:Double):Integer;
var
  I:Integer;
begin Result:=-1;
  for I:=0 to High(FBosses) do if (Time>=FShips[FBosses[I]].Show+0.90) and (Time<=FShips[FBosses[I]].Kill+1E-9) then Exit(FBosses[I]);
end;

procedure TNavalPlan.MakePhrases(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
var
  Boundaries:TList<TNavalBoundary>;
  List:TList<TNavalPhrase>;
  B:TNavalBoundary;
  P:TNavalPhrase;
  Cue:TRhythmBossCue;
  Prefix:TArray<Double>;
  I,J,Theme:Integer;
  T,Target,Best,Value,Peak,LastSection,Before,After:Double;
  procedure Add(Time:Double;Section:Boolean);
  begin if (Time<0) or (Time>FGoal) then Exit;
    B.Time:=Time;
    B.Section:=Section;
    Boundaries.Add(B);
  end;
  function Energy(A,B:Double):Double;
  var
    First,Last:Integer;
  begin First:=EnsureRange(Floor(A*100),0,Length(Audio.Envelope));
    Last:=EnsureRange(Ceil(B*100),First,Length(Audio.Envelope));
    Result:=0;
    if Last>First then Result:=(Prefix[Last]-Prefix[First])/(Last-First);
  end;
begin Boundaries:=TList<TNavalBoundary>.Create;
  List:=TList<TNavalPhrase>.Create;
  try Add(0,False);
    T:=0;
    Peak:=0;
    SetLength(Prefix,Length(Audio.Envelope)+1);
    for I:=0 to High(Audio.Envelope) do begin Prefix[I+1]:=Prefix[I]+Audio.Envelope[I];
      Peak:=Max(Peak,Audio.Envelope[I]);
    end;
    while T+5<FGoal do begin Check(Cancel);
      Target:=Min(FGoal,T+7.2);
      Best:=Target;
      Value:=-1;
      for I:=Max(0,Audio.NearestHit(T+5)) to Min(High(Audio.Hits),Audio.NearestHit(T+9.4)) do
      if (Audio.Hits[I].Time>T+5) and (Audio.Hits[I].Time<FGoal) and (Audio.Hits[I].Strength-Abs(Audio.Hits[I].Time-Target)*0.06>Value) then begin Value:=Audio.Hits[I].Strength-Abs(Audio.Hits[I].Time-Target)*0.06;
        Best:=Audio.Hits[I].Time;
      end;
      if Best<=T+1 then Break;
      Add(Best,False);
      T:=Best;
    end;
    // Camera phrases may change freely; scenery only cuts at a measured musical drop.
    LastSection:=-12;
    for I:=4 to Floor(FGoal*2)-3 do begin T:=I/2;
      Before:=Energy(T-1.5,T-0.10);
      After:=Energy(T+0.10,T+1.0);
      if (T-LastSection>=12) and (Before>Peak*0.20) and (After<Before*0.58) then begin Add(T,True);
        LastSection:=T;
      end;
    end;
    if FFrequency>0 then for I:=0 to Audio.BossCount-1 do begin Cue:=Audio.BossCue(I);
      Add(Cue.StartTime,False);
      if Cue.QuietBoundary then Add(Cue.KillTime,True);
    end;
    Add(FGoal,False);
    Boundaries.Sort(TComparer<TNavalBoundary>.Construct(function(const A,B:TNavalBoundary):Integer begin Result:=0;if A.Time<B.Time then Result:=-1 else if A.Time>B.Time then Result:=1 else if A.Section<>B.Section then if A.Section then Result:=-1 else Result:=1;end));
    Theme:=0;
    LastSection:=-12;
    I:=0;
    while I<Boundaries.Count-1 do begin B:=Boundaries[I];
      J:=I+1;
      while (J<Boundaries.Count) and (Boundaries[J].Time-B.Time<0.35) do begin B.Section:=B.Section or Boundaries[J].Section;
        Inc(J);
      end;
      if J>=Boundaries.Count then Break;
      if B.Section and (B.Time>0.1) then begin if B.Time-LastSection>=10 then begin Theme:=(Theme+1) mod 3;
          LastSection:=B.Time;
        end else B.Section:=False;
      end;
      P.First:=B.Time;
      P.Last:=Boundaries[J].Time;
      P.Section:=B.Section;
      P.Theme:=Theme;
      P.Mode:=List.Count mod 3;
      P.Zoom:=1.055;
      if P.Mode=1 then P.Zoom:=1.10 else if P.Mode=2 then P.Zoom:=1.14;
      List.Add(P);
      I:=J;
    end;
    if List.Count=0 then begin P.First:=0;
      P.Last:=Max(0.01,FGoal);
      P.Mode:=0;
      P.Theme:=0;
      P.Zoom:=1;
      P.Section:=False;
      List.Add(P);
    end;
    FPhrases:=List.ToArray;
  finally Boundaries.Free;
    List.Free;
  end;
end;

procedure TNavalPlan.MakeBattle(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>);
var
  Ships:TList<TNavalShip>;
  Hits:TList<TNavalHit>;
  Shots:TList<TNavalShot>;
  BossIDs:TList<Integer>;
  S:TNavalShip;
  H:TNavalHit;
  Shot:TNavalShot;
  Cue:TRhythmBossCue;
  P,Hero:TNavalPoint;
  I,J,K,Target,BossID,Source,Mode,Wave,Fan,Attempt,ExtraUsed,ExtraStride,CueIndex,CueTotal:Integer;
  Time,Step,Angle,LastGlance,First,Kill,Health,Estimated,ShotScale:Double;
  function AddShip(First,Kill:Double;KillSource,Slot,Boss:Integer):Integer;
  begin S:=Default(TNavalShip);
    S.Kill:=Kill;
    S.KillSource:=KillSource;
    S.Boss:=Boss;
    S.Size:=0.78+Slot*0.11;
    S.Show:=Max(0.0,Min(First-0.8,Kill-4.5));
    S.Arrive:=Max(S.Show,Min(S.Show+0.8,First-0.12));
    S.X:=1.09+Slot*0.20;
    S.Y:=0.28+Slot*0.115;
    S.Phase:=(Ships.Count*2.399963)+(FSeed mod 997)/997*2*Pi;
    if Boss<>0 then begin S.Show:=First;
      S.Arrive:=First+0.85;
      S.Size:=1.85;
      S.X:=1.27;
      S.Y:=0.29;
    end;
    Result:=Ships.Count;
    Ships.Add(S);
  end;
  procedure Hit(Source,Target,Kind,Gun:Integer);
  begin H.Source:=Source;
    H.Target:=Target;
    H.Kind:=Kind;
    H.Gun:=Gun;
    H.Shot:=-1;
    if Kind<>0 then begin Time:=FEvents[Source].Time;
      Shot:=Default(TNavalShot);
      Shot.Kind:=Kind;
      Shot.Owner:=Target;
      Shot.Finish:=Time;
      Shot.Launch:=Max(FShips[Target].Show,Time-0.72);
      Shot.Radius:=0.006;
      Shot.Arc:=0.03;
      P:=ShipAt(Target,Shot.Launch);
      Shot.A:=NavalPoint(P.X-0.06*FShips[Target].Size,P.Y+0.035*FShips[Target].Size);
      Hero:=HeroAt(Time);
      if Kind=1 then Shot.B:=NavalPoint(Hero.X+0.22,Hero.Y-0.15) else begin Angle:=HeroAngle(Time);
        Shot.B:=NavalPoint(Hero.X+0.07*Cos(Angle)+(0.045+Shot.Radius)*Sin(Angle),Hero.Y+0.07*Sin(Angle)-(0.045+Shot.Radius)*Cos(Angle));
      end;
      H.Shot:=Shots.Count;
      Shots.Add(Shot);
    end;
    Hits.Add(H);
  end;
begin Ships:=TList<TNavalShip>.Create;
  Hits:=TList<TNavalHit>.Create;
  Shots:=TList<TNavalShot>.Create;
  BossIDs:=TList<Integer>.Create;
  try
    CueTotal:=0;
    if FFrequency>0 then CueTotal:=Audio.BossCount;
    for I:=0 to Min(64,CueTotal)-1 do begin Check(Cancel);
      CueIndex:=I;
      if CueTotal>64 then CueIndex:=Round(I*(CueTotal-1)/63);
      Cue:=Audio.BossCue(CueIndex);
      if (Cue.KillTime-Cue.StartTime<3) or (Cue.KillTime>FGoal) then Continue;
      Source:=Audio.NearestHit(Cue.KillTime);
      if (Source<0) or (Source>=FPulses) or (Abs(FEvents[Source].Time-Cue.KillTime)>1E-7) then Continue;
      BossID:=AddShip(Cue.StartTime,Cue.KillTime,Source,0,1);
      BossIDs.Add(BossID);
      if BossIDs.Count>=64 then Break;
    end;
    FShips:=Ships.ToArray;
    FBosses:=BossIDs.ToArray;
    I:=0;
    LastGlance:=-5;
    ExtraUsed:=0;
    ExtraStride:=Max(1,Ceil(FPulses*2/30000));
    while I<FPulses do begin Check(Cancel);
      BossID:=BossFor(FEvents[I].Time);
      if BossID>=0 then begin Target:=BossID;
        J:=I;
      end
      else begin J:=I;
        while J<FPulses-1 do begin if BossFor(FEvents[J+1].Time)>=0 then Break;
          if FEvents[J+1].Time-FEvents[I].Time>1.15+FEvents[I].Strength*0.45 then Break;
          Inc(J);
        end;
        First:=FEvents[I].Time;
        Kill:=FEvents[J].Time;
        Target:=AddShip(First,Kill,J,0,0);
        AddShip(First,Kill,J,1,0);
        AddShip(First,Kill,J,2,0);
        FShips:=Ships.ToArray;
      end;
      for K:=I to J do begin Mode:=FPhrases[PhraseBefore(FEvents[K].Time)].Mode;
        if (Mode=1) and (K<>FShips[Target].KillSource) and (FEvents[K].Time-LastGlance>3.5) and (K mod 17=7) then begin Hit(K,Target,2,K mod 3);
          LastGlance:=FEvents[K].Time;
        end
        else if (Mode=1) and (K<>FShips[Target].KillSource) and (K mod 3<>0) then Hit(K,Target,1,K mod 3)
        else begin
          if (K=FShips[Target].KillSource) or (FEvents[K].Strength>=0.78) or (Mode=2) then Hit(K,Target,0,1) else Hit(K,Target,0,K mod 3);
          if (K<>FShips[Target].KillSource) and ((FEvents[K].Strength>=0.78) or (Mode=2)) and (K mod ExtraStride=0) and (ExtraUsed<30000) then begin
            if BossID<0 then begin Hit(K,Target+1,0,0);
              Hit(K,Target+2,0,2);
            end else begin Hit(K,Target,0,0);
              Hit(K,Target,0,2);
            end;
            Inc(ExtraUsed,2);
          end;
        end;
      end;
      if BossID<0 then begin Hit(J,Target+1,0,0);
        Hit(J,Target+2,0,2);
      end else if J=FShips[Target].KillSource then begin Hit(J,Target,0,0);
        Hit(J,Target,0,2);
      end;
      I:=J+1;
    end;
    FHits:=Hits.ToArray;
    FShots:=Shots.ToArray;
    Reindex;
    for I:=0 to ShipCount-1 do begin S:=FShips[I];
      S.HP:=Length(FShipHits[I]);
      FShips[I]:=S;
    end;
    Estimated:=0;
    for I:=0 to ShipCount-1 do begin S:=FShips[I];
      Time:=Max(S.Arrive+0.12,S.Show+0.55);
      if S.Boss<>0 then Estimated:=Estimated+Max(0.0,S.Kill-Time)*45 else Estimated:=Estimated+Max(0.0,S.Kill-Time)*10;
    end;
    ShotScale:=Max(1.0,Estimated/Max(1000,74000-Shots.Count));
    for I:=0 to ShipCount-1 do begin Check(Cancel);
      S:=FShips[I];
      Time:=Max(S.Arrive+0.12,S.Show+0.55);
      Wave:=0;
      while (Time<S.Kill-0.12) and (Shots.Count<80000) do begin
        Mode:=FPhrases[PhraseBefore(Time)].Mode;
        Step:=0.40;
        if Mode=1 then Step:=0.30;
        if S.Boss<>0 then Step:=0.20;
        Fan:=3;
        if ShotScale>3 then Fan:=1;
        if S.Boss<>0 then begin Health:=HealthAt(I,Time);
          Fan:=9;
          if Health<0.55 then Fan:=7;
          if Health<0.25 then Fan:=5;
        end;
        P:=ShipAt(I,Time);
        for J:=0 to Fan-1 do begin
          Shot:=Default(TNavalShot);
          Shot.Owner:=I;
          Shot.Kind:=0;
          Shot.Launch:=Time;
          Shot.Finish:=Time+0.85+0.08*(J mod 4);
          Shot.Radius:=0.0055;
          Shot.Arc:=0.035;
          Shot.A:=NavalPoint(P.X+(J mod 3-1)*0.05*S.Size,P.Y+0.035*S.Size);
          Hero:=HeroAt(Shot.Finish);
          for Attempt:=0 to 3 do begin Angle:=2*Pi*(J+Wave*0.618)/Max(1,Fan)+Attempt*1.4;
            Shot.B:=NavalPoint(Hero.X+0.21+0.025*Cos(Angle),Hero.Y+(J mod 2*2-1)*(0.09+Attempt*0.045));
            if ShotSafe(Shot) then begin Shots.Add(Shot);
              Break;
            end;
          end;
        end;
        Inc(Wave);
        Time:=Time+Step*ShotScale;
      end;
    end;
    FShots:=Shots.ToArray;
    Reindex;
  finally Ships.Free;
    Hits.Free;
    Shots.Free;
    BossIDs.Free;
  end;
end;

procedure TNavalPlan.Reindex;
var
  Orders:TArray<TNavalOrder>;
  Counts:TArray<Integer>;
  I,J,N:Integer;
  Players,BossIDs:TList<Integer>;
begin
  SetLength(Orders,ShipCount);
  for I:=0 to ShipCount-1 do begin Orders[I].Time:=FShips[I].Kill;
    Orders[I].Index:=I;
  end;
  TArray.Sort<TNavalOrder>(Orders,TComparer<TNavalOrder>.Construct(function(const A,B:TNavalOrder):Integer begin Result:=0;if A.Time<B.Time then Exit(-1);if A.Time>B.Time then Exit(1);if A.Index<B.Index then Result:=-1 else if A.Index>B.Index then Result:=1;end));
  SetLength(FShipOrder,ShipCount);
  for I:=0 to ShipCount-1 do FShipOrder[I]:=Orders[I].Index;
  SetLength(Orders,ShotCount);
  for I:=0 to ShotCount-1 do begin Orders[I].Time:=FShots[I].Launch;
    Orders[I].Index:=I;
  end;
  TArray.Sort<TNavalOrder>(Orders,TComparer<TNavalOrder>.Construct(function(const A,B:TNavalOrder):Integer begin Result:=0;if A.Time<B.Time then Exit(-1);if A.Time>B.Time then Exit(1);if A.Index<B.Index then Result:=-1 else if A.Index>B.Index then Result:=1;end));
  SetLength(FShotOrder,ShotCount);
  for I:=0 to ShotCount-1 do FShotOrder[I]:=Orders[I].Index;
  SetLength(Counts,ShipCount);
  SetLength(FShipHits,ShipCount);
  for I:=0 to Count-1 do if (FHits[I].Kind=0) and (FHits[I].Target>=0) and (FHits[I].Target<ShipCount) then Inc(Counts[FHits[I].Target]);
  for I:=0 to ShipCount-1 do begin SetLength(FShipHits[I],Counts[I]);
    Counts[I]:=0;
  end;
  Players:=TList<Integer>.Create;
  BossIDs:=TList<Integer>.Create;
  try for I:=0 to Count-1 do begin if FHits[I].Kind=2 then Players.Add(I);
      if FHits[I].Kind<>0 then Continue;
      J:=FHits[I].Target;
      if (J<0) or (J>=ShipCount) then Continue;
      N:=Counts[J];
      FShipHits[J][N]:=FEvents[FHits[I].Source].Time;
      Inc(Counts[J]);
    end;
    for I:=0 to ShipCount-1 do if FShips[I].Boss<>0 then BossIDs.Add(I);
    FBosses:=BossIDs.ToArray;
    FPlayerHits:=Players.ToArray;
  finally Players.Free;
    BossIDs.Free;
  end;
end;

procedure TNavalPlan.CameraAt(Time:Double;out Center:TNavalPoint;out Zoom:Double);
var
  I,J,A,B:Integer;
  P,H:TNavalPoint;
  U,W,MinX,MaxX,MinY,MaxY,S,Fit:Double;
begin Time:=EnsureRange(Time,0.0,FEnd);
  H:=HeroAt(Time);
  MinX:=H.X-0.18;
  MaxX:=H.X+0.18;
  MinY:=H.Y-0.24;
  MaxY:=H.Y+0.08;
  I:=PhraseBefore(Time);
  U:=EnsureRange((Time-FPhrases[I].First)/Max(0.01,FPhrases[I].Last-FPhrases[I].First),0.0,1.0);
  Zoom:=1+(FPhrases[I].Zoom-1)*Sqr(Sin(Pi*U));
  A:=Max(0,ShipBefore(Time-1.5));
  B:=Min(ShipCount-1,ShipBefore(Time+6.1));
  for J:=A to B do begin I:=FShipOrder[J];
    if (Time<FShips[I].Arrive) or (Time>=FShips[I].Kill) then Continue;
    P:=ShipAt(I,Time);
    S:=FShips[I].Size;
    MinX:=Min(MinX,P.X-0.13*S);
    MaxX:=Max(MaxX,P.X+0.13*S);
    MinY:=Min(MinY,P.Y-0.23*Min(1.25,S));
    MaxY:=Max(MaxY,P.Y+0.06*S);
  end;
  for J:=0 to BossCount-1 do begin I:=FBosses[J];
    if (Time<FShips[I].Arrive) or (Time>=FShips[I].Kill) then Continue;
    P:=ShipAt(I,Time);
    MinX:=Min(MinX,P.X-0.26);
    MaxX:=Max(MaxX,P.X+0.26);
    MinY:=Min(MinY,P.Y-0.28);
  end;
  Fit:=Min(1.70/Max(0.1,MaxX-MinX),0.93/Max(0.1,MaxY-MinY));
  Zoom:=EnsureRange(Min(Zoom,Fit),1.0,1.14);
  W:=0.9/Zoom;
  Center.X:=EnsureRange((MinX+MaxX)/2,W,1.8-W);
  W:=0.5/Zoom;
  Center.Y:=EnsureRange((MinY+MaxY)/2,W,1-W);
end;

procedure TNavalPlan.Validate;
var
  I,J:Integer;
  E:TNavalEvent;
  S:TNavalShip;
  H:TNavalHit;
  Shot:TNavalShot;
  A,B,P,Q:TNavalPoint;
  Launch,Finish,Arc,T,Last,U:Double;
  procedure Need(V:Boolean;const Msg:string);
  begin if not V then raise Exception.Create('Naval plan: '+Msg);
  end;
begin
  Need(Finite(FDuration) and Finite(FGoal) and Finite(FEnd) and (FDuration>0) and (FGoal>=0) and (FGoal<=FDuration) and (FEnd>=FDuration) and (FEnd<=FDuration+1.61),'bounds');
  Need((Length(FEvents)<=100000) and (Count<=150000) and (ShipCount<=10000) and (ShotCount<=90000) and (PhraseCount>=1) and (PhraseCount<=10000) and (BossCount<=64),'limits');
  Need((FFrequency>=0) and (FFrequency<=100) and ((FFrequency>0) or (BossCount=0)),'frequency');
  Last:=-1;
  for E in FEvents do begin Need(Finite(E.Time) and Finite(E.Strength) and (E.Time>=Last) and (E.Time>=0) and (E.Time<=FDuration+0.011) and (E.Strength>=0) and (E.Strength<=1),'event');
    Last:=E.Time;
  end;
  Need((FPulses+FExcluded=Length(FEvents)) and (FPulses>=0),'event count');
  for I:=0 to ShipCount-1 do begin S:=FShips[I];
    Need(Finite(S.Show) and Finite(S.Arrive) and Finite(S.Kill) and Finite(S.X) and Finite(S.Y) and Finite(S.Size) and Finite(S.Phase),'ship finite');
    Need((S.KillSource>=0) and (S.KillSource<FPulses) and (S.Kill=FEvents[S.KillSource].Time) and (S.Show>=0) and (S.Arrive>=S.Show) and (S.Arrive<=S.Kill) and (S.Size>=0.7) and (S.Size<=1.9),'ship clocks');
    Need((S.HP=Length(FShipHits[I])) and (S.HP>0) and (Length(FShipHits[I])>0) and (Abs(FShipHits[I][High(FShipHits[I])]-S.Kill)<1E-8),'HP and last real hit');
  end;
  Last:=-1;
  for I:=0 to Count-1 do begin H:=FHits[I];
    Need((H.Source>=0) and (H.Source<FPulses) and (H.Target>=0) and (H.Target<ShipCount) and (H.Kind in [0,1,2]) and (H.Gun in [0,1,2]),'hit link');
    T:=FEvents[H.Source].Time;
    Need(T>=Last,'hit order');
    Last:=T;
    if H.Kind=0 then Need((T>=FShips[H.Target].Arrive) and (T<=FShips[H.Target].Kill),'hit on absent hull')
    else Need((H.Shot>=0) and (H.Shot<ShotCount) and (FShots[H.Shot].Kind=H.Kind) and (FShots[H.Shot].Finish=T),'incoming hit link');
    if CannonPath(I,Launch,Finish,Arc,A,B) then begin Need(Finish=T,'audio impact clock');
      P:=ArcPoint(A,B,1,Arc);
      Need(Hypot(P.X-B.X,P.Y-B.Y)<1E-9,'impact endpoint');
      if H.Kind=0 then begin P:=ShipAt(H.Target,T);
        Need(Abs(B.Y-(P.Y+0.035*FShips[H.Target].Size+0.008))<1E-8,'hull surface');
        if Finish>Launch then for J:=1 to 20 do begin U:=1-Power(0.5,J);
          P:=ArcPoint(A,B,U,Arc);
          Q:=ShipAt(H.Target,Launch+(Finish-Launch)*U);
          S:=FShips[H.Target];
          Need(Hypot(Max(0.0,Abs(P.X-Q.X)-0.12*S.Size),Max(0.0,Abs(P.Y-Q.Y)-0.035*S.Size))>=0.008-1E-8,'early moving hull contact');
        end;
      end;
    end;
  end;
  for I:=0 to ShotCount-1 do begin Shot:=FShots[I];
    Need(Finite(Shot.Launch) and Finite(Shot.Finish) and Finite(Shot.A.X) and Finite(Shot.A.Y) and Finite(Shot.B.X) and Finite(Shot.B.Y) and Finite(Shot.Radius) and Finite(Shot.Arc),'shot finite');
    Need((Shot.Owner>=0) and (Shot.Owner<ShipCount) and (Shot.Launch>=FShips[Shot.Owner].Show) and (Shot.Launch<=FShips[Shot.Owner].Kill) and (Shot.Finish>=Shot.Launch) and (Shot.Finish<=FEnd) and (Shot.Kind in [0,1,2]) and (Shot.Radius>0) and (Shot.Radius<=0.012),'shot bounds');
    if Shot.Kind=0 then Need(ShotSafe(Shot),'unplanned player hit');
    if Shot.Kind=1 then Need(ShotSafe(Shot),'intercept too close');
  end;
  for I:=0 to PhraseCount-1 do begin Need(Finite(FPhrases[I].First) and Finite(FPhrases[I].Last) and (FPhrases[I].First>=0) and (FPhrases[I].Last>FPhrases[I].First) and (FPhrases[I].Mode in [0,1,2]) and (FPhrases[I].Theme in [0,1,2]),'phrase');
    if I>0 then Need(FPhrases[I].First>=FPhrases[I-1].Last-1E-8,'phrase overlap');
  end;
end;

class function TNavalPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TNavalPlan;
var
  I:Integer;
  Last:Double;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  Result:=TNavalPlan.Create;
  try Result.FDuration:=Audio.Duration;
    Result.FGoal:=Audio.SoundEnd;
    Result.FEnd:=Max(Audio.Duration,Audio.SoundEnd+1.6);
    Result.FFrequency:=Audio.BossFrequency;
    Result.FSeed:=Cardinal(StrToInt64Def('$'+Copy(Audio.Key,1,8),173));
    if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.Duration>512*Int64(1024)*1024/4/RHYTHM_RATE) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then raise Exception.Create('Invalid naval audio');
    SetLength(Result.FEvents,Length(Audio.Hits));
    Last:=-1;
    for I:=0 to High(Audio.Hits) do begin Check(Cancel);
      if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or (Audio.Hits[I].Time<Last) or (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('Invalid naval accent');
      Result.FEvents[I].Time:=Audio.Hits[I].Time;
      Result.FEvents[I].Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);
      Last:=Audio.Hits[I].Time;
      if (Audio.SoundEnd>0) and (Last<=Audio.SoundEnd+1E-8) then Inc(Result.FPulses) else Inc(Result.FExcluded);
    end;
    Result.MakePhrases(Audio,Cancel);
    Result.MakeBattle(Audio,Cancel);
    Result.Validate;
  except Result.Free;
    raise;
  end;
end;

procedure TNavalPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var
  Root:TJSONObject;
  A,R:TJSONArray;
  E:TNavalEvent;
  S:TNavalShip;
  H:TNavalHit;
  Shot:TNavalShot;
  P:TNavalPhrase;
  procedure N(V:Double);
  begin R.AddElement(Number(V));
  end;
begin
  if (Ref.Version<>1) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsNaval,Ref.Variant) or (BossFrequencyFromVariant(Ref.Variant)<>FFrequency) then raise Exception.Create('Naval save identity');
  Root:=TJSONObject.Create;
  try Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style','naval');
    Root.AddPair('version',TJSONNumber.Create(1));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root,Audio);
    Root.AddPair('policy','broadside-phrases-v1');
    Root.AddPair('frequency',TJSONNumber.Create(FFrequency));
    Root.AddPair('seed',TJSONNumber.Create(Int64(FSeed)));
    Root.AddPair('durationExact',Number(FDuration));
    Root.AddPair('goal',Number(FGoal));
    Root.AddPair('end',Number(FEnd));
    Root.AddPair('pulses',TJSONNumber.Create(FPulses));
    Root.AddPair('excluded',TJSONNumber.Create(FExcluded));
    A:=TJSONArray.Create;
    Root.AddPair('events',A);
    for E in FEvents do begin R:=TJSONArray.Create;
      A.AddElement(R);
      N(E.Time);
      N(E.Strength);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('ships',A);
    for S in FShips do begin R:=TJSONArray.Create;
      A.AddElement(R);
      N(S.Show);
      N(S.Arrive);
      N(S.Kill);
      N(S.X);
      N(S.Y);
      N(S.Size);
      N(S.Phase);
      N(S.Boss);
      N(S.KillSource);
      N(S.HP);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('hits',A);
    for H in FHits do begin R:=TJSONArray.Create;
      A.AddElement(R);
      N(H.Source);
      N(H.Target);
      N(H.Kind);
      N(H.Gun);
      N(H.Shot);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('shots',A);
    for Shot in FShots do begin R:=TJSONArray.Create;
      A.AddElement(R);
      N(Shot.Launch);
      N(Shot.Finish);
      N(Shot.Radius);
      N(Shot.Arc);
      N(Shot.A.X);
      N(Shot.A.Y);
      N(Shot.B.X);
      N(Shot.B.Y);
      N(Shot.Kind);
      N(Shot.Owner);
    end;
    A:=TJSONArray.Create;
    Root.AddPair('phrases',A);
    for P in FPhrases do begin R:=TJSONArray.Create;
      A.AddElement(R);
      N(P.First);
      N(P.Last);
      N(P.Zoom);
      N(P.Mode);
      N(P.Theme);
      N(Ord(P.Section));
    end;
    WritePreparedData(Root,Ref);
  finally Root.Free;
  end;
end;

class function TNavalPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var
  Root:TJSONObject;
  A,R:TJSONArray;
  I:Integer;
  D,G:Double;
begin Root:=ReadPreparedData(Ref,rsNaval,Direction);
  try Result:=PreparedAudio(Root,Ref,Source);
    try D:=Root.GetValue<Double>('durationExact');
      G:=Root.GetValue<Double>('goal');
      if not Finite(D) or not Finite(G) or (Abs(D-Result.Duration)>1E-7) or (Abs(G-Result.SoundEnd)>1E-7) or (G<0) or (G>D) then raise Exception.Create('Naval exact metadata');
      Result.Duration:=D;
      Result.SoundEnd:=G;
      A:=Root.GetValue<TJSONArray>('events');
      if (A=nil) or (A.Count<>Length(Result.Hits)) then raise Exception.Create('Naval metadata events');
      for I:=0 to A.Count-1 do begin R:=A.Items[I] as TJSONArray;
        if R.Count<>2 then raise Exception.Create('Naval event row');
        Result.Hits[I].Time:=R.Items[0].GetValue<Double>;
        Result.Hits[I].Strength:=R.Items[1].GetValue<Double>;
      end;
      Result.SetBossFrequency(BossFrequencyFromVariant(Ref.Variant));
    except Result.Free;
      raise;
    end;
  finally Root.Free;
  end;
end;

class function TNavalPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TNavalPlan;
var
  Root,Info:TJSONObject;
  A,R:TJSONArray;
  I:Integer;
  P:TNavalPhrase;
  S:TNavalShip;
  H:TNavalHit;
  Shot:TNavalShot;
  function Rows(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);
    if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Naval array '+Name);
  end;
  procedure Row(Index,Width:Integer);
  begin R:=A.Items[Index] as TJSONArray;
    if R.Count<>Width then raise Exception.Create('Naval row width');
  end;
  function N(Index:Integer):Double;
  begin Result:=R.Items[Index].GetValue<Double>;
    if not Finite(Result) then raise Exception.Create('Naval nonfinite JSON');
  end;
  function Int(Index:Integer):Integer;
  var
    V:Double;
  begin V:=N(Index);
    if (V<>Trunc(V)) or (Abs(V)>MaxInt) then raise Exception.Create('Naval integer');
    Result:=Round(V);
  end;
begin if Audio=nil then raise Exception.Create('Naval metadata missing');
  Root:=ReadPreparedData(Ref,rsNaval,Direction);
  try
    if (Root.GetValue<string>('policy','')<>'broadside-phrases-v1') or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsNaval,Ref.Variant) then raise Exception.Create('Naval policy/identity');
    Info:=Root.GetValue<TJSONObject>('audio');
    if (Info=nil) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-7) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-7) then raise Exception.Create('Naval audio identity');
    Result:=TNavalPlan.Create;
    try Result.FDuration:=Audio.Duration;
      Result.FGoal:=Root.GetValue<Double>('goal');
      Result.FEnd:=Root.GetValue<Double>('end');
      Result.FFrequency:=Root.GetValue<Integer>('frequency');
      Result.FSeed:=Cardinal(Root.GetValue<Int64>('seed'));
      Result.FPulses:=Root.GetValue<Integer>('pulses');
      Result.FExcluded:=Root.GetValue<Integer>('excluded');
      if Result.FFrequency<>BossFrequencyFromVariant(Ref.Variant) then raise Exception.Create('Naval frequency identity');
      A:=Rows('events',100000);
      SetLength(Result.FEvents,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,2);
        Result.FEvents[I].Time:=N(0);
        Result.FEvents[I].Strength:=N(1);
      end;
      A:=Rows('ships',10000);
      SetLength(Result.FShips,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,10);
        S.Show:=N(0);
        S.Arrive:=N(1);
        S.Kill:=N(2);
        S.X:=N(3);
        S.Y:=N(4);
        S.Size:=N(5);
        S.Phase:=N(6);
        S.Boss:=Int(7);
        S.KillSource:=Int(8);
        S.HP:=Int(9);
        Result.FShips[I]:=S;
      end;
      A:=Rows('hits',150000);
      SetLength(Result.FHits,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,5);
        H.Source:=Int(0);
        H.Target:=Int(1);
        H.Kind:=Int(2);
        H.Gun:=Int(3);
        H.Shot:=Int(4);
        Result.FHits[I]:=H;
      end;
      A:=Rows('shots',90000);
      SetLength(Result.FShots,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,10);
        Shot.Launch:=N(0);
        Shot.Finish:=N(1);
        Shot.Radius:=N(2);
        Shot.Arc:=N(3);
        Shot.A:=NavalPoint(N(4),N(5));
        Shot.B:=NavalPoint(N(6),N(7));
        Shot.Kind:=Int(8);
        Shot.Owner:=Int(9);
        Result.FShots[I]:=Shot;
      end;
      A:=Rows('phrases',10000);
      SetLength(Result.FPhrases,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,6);
        P.First:=N(0);
        P.Last:=N(1);
        P.Zoom:=N(2);
        P.Mode:=Int(3);
        P.Theme:=Int(4);
        P.Section:=Int(5)<>0;
        Result.FPhrases[I]:=P;
      end;
      for I:=0 to Result.Count-1 do begin H:=Result.FHits[I];
        if (H.Source<0) or (H.Source>=Result.FPulses) or (H.Target<0) or (H.Target>=Result.ShipCount) or not (H.Kind in [0,1,2]) then raise Exception.Create('Naval saved hit reference');
      end;
      Result.Reindex;
      Result.Validate;
    except Result.Free;
      raise;
    end;
  finally Root.Free;
  end;
end;
end.
