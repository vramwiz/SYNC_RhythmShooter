program SideRaceSmoke;
{$APPTYPE CONSOLE}
// 音時刻の車体接触、道路の通過、HP、時間帯と保存後の同じ描画を検証する。
uses System.SysUtils,System.Types,System.Math,System.Classes,System.Hash,System.IOUtils,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmAudioCache,RhythmStyles,RhythmPlanRef,
  RhythmSettings,RhythmStyleOps,RhythmStyleRegistry,RhythmScene,RhythmSideRacePlan,
  RhythmSideRaceBuild,RhythmSideRaceCodec;

var Checks:Integer;

procedure Need(Valid:Boolean;const MessageText:string);
begin
  if not Valid then raise Exception.Create(MessageText);
  Inc(Checks);
end;

function Fixture(const Source:string):TRhythmAudio;
const Steps:array[0..7] of Double=(0.54,0.34,0.058,0.39,0.79,0.049,0.31,0.45);
var I,N,Section:Integer; T:Double;
begin
  TFile.WriteAllText(Source,'2D highway 180-second synthetic accents.',TEncoding.UTF8);
  Result:=TRhythmAudio.Create;
  Result.Source:=Source;
  Result.SourceRevision:=AudioSourceStamp(Source);
  Result.Key:=THashSHA2.GetHashStringFromFile(Source);
  Result.Sensitivity:=50;
  Result.Duration:=180;
  SetLength(Result.Envelope,18000);
  for I:=0 to High(Result.Envelope) do begin
    Section:=I div 1000;
    Result.Envelope[I]:=0.11+0.095*((Section*5+Section div 3) mod 8)+0.02*Sqr(Sin(I*0.071));
    if I mod 1000>967 then Result.Envelope[I]:=0.001;
  end;
  Result.UpdateSoundBounds;
  N:=0;
  T:=0;
  SetLength(Result.Hits,6000);
  while T<179.5 do begin
    Section:=Trunc(T/10) mod Length(Steps);
    Result.Hits[N].Time:=T;
    Result.Hits[N].Strength:=0.22+0.105*(N mod 8);
    Inc(N);
    T:=T+Steps[Section]*(0.87+(N mod 6)*0.052);
  end;
  SetLength(Result.Hits,N);
end;

procedure EdgeCases;
var A:TRhythmAudio; P:TSideRacePlan;
begin
  A:=TRhythmAudio.Create;
  try
    A.Duration:=0.80;
    A.SetBossFrequency(0);
    P:=BuildSideRace(A,nil);
    try
      Need((Length(P.Bosses)=1) and not P.Cues[P.Bosses[0].Last].Musical,'Silent short clip needs one boss');
      Need(P.Cues[P.Bosses[0].Last].Time<P.Goal,'Boss after goal');
    finally
      P.Free;
    end;
    SetLength(A.Hits,2);
    A.Hits[1].Time:=0.798;
    A.SoundEnd:=0.80;
    P:=BuildSideRace(A,nil);
    try
      Need((Length(P.Cues)=3) and (P.Cues[2].Time=A.Hits[1].Time),'Late accent lost');
      Need(P.Cues[P.Bosses[0].Last].Time<P.Goal,'Short clip boss after goal');
    finally
      P.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure Verify(P:TSideRacePlan;Audio:TRhythmAudio;Full:Boolean);
var
  I,K,B,SpanHits,Musical,Repairs,RoofHits,Rams,RearHits,FrontHits,Gaps,Lifts,Chains:Integer;
  T,A,Last,Height,NearEdge,V:Double;
  X,Q,R:TPointF;
  Pose:TSidePose;
  J:TSideJump;
  F:TSideCar;
  Boss:TSideBoss;
  Rig:TSideRig;
  Cue:TSideCue;
  Deck:TSideDeck;
  Levels:set of 1..5;
  Phases:set of 0..3;
  Moves:set of TSideAction;
  Types:set of 0..4;
begin
  Levels:=[];
  Phases:=[];
  Moves:=[];
  Types:=[];
  Musical:=0;
  SpanHits:=0;
  Repairs:=0;
  RoofHits:=0;
  Rams:=0;
  RearHits:=0;
  FrontHits:=0;
  Gaps:=0;
  Lifts:=0;
  Chains:=0;
  for I:=0 to High(P.Stages) do begin
    Include(Levels,P.Stages[I].Level);
    if I=0 then Need(P.Stages[I].Level=1,'Opening difficulty');
    if I>0 then begin
      T:=P.Stages[I].Time;
      Need(Abs(P.Speed(T-1E-7)-P.Speed(T+1E-7))<0.001,'Speed break at stage cut');
      Need(P.Hero(T-1E-5).Distance(P.Hero(T+1E-5))<0.005,'Stage teleported vehicle');
    end;
  end;
  Last:=-1;
  for I:=0 to 300 do begin
    T:=P.Duration*I/300;
    V:=P.Phase(T);
    Include(Phases,Floor(V));
    Need((V>=Last) and (V<=3),'Day cycle reversed');
    Last:=V;
    if I>0 then Need(P.Distance(T)>P.Distance(P.Duration*(I-1)/300),'Forward movement stopped');
  end;
  Need((Phases=[0..3]) and (P.Goal<P.Duration),'Day, dusk, night and dawn cycle');
  Last:=1;
  for I:=0 to High(P.Cues) do begin
    Cue:=P.Cues[I];
    T:=Cue.Time;
    if Cue.Musical then begin
      Inc(Musical);
      Need(Audio.Hits[Audio.NearestHit(T)].Time=T,'Music cue shifted');
    end;
    X:=P.Hero(T);
    Q:=P.Contact(I);
    Need(P.Speed(T)>14,'Collision lost forward speed');
    Need((Cue.Health>=0.20) and (Cue.Health<=1),'Health outside bounds');
    Need(P.Health(T)=Cue.Health,'Health update missed timing');
    Include(Moves,Cue.Action);
    if Cue.Car>=0 then begin
      F:=P.Cars[Cue.Car];
      Pose:=P.CarPose(Cue.Car,T);
      Need(Abs(Pose.Root.X-F.Side*P.CarHalf(Cue.Car)-Q.X)<0.00065,'Bumpers missed the cue');
      Need(Abs(Pose.Root.Y-X.Y)<0.0003,'Vehicle missed contact height');
      if F.Side<0 then Inc(RearHits) else Inc(FrontHits);
      if (I>0) and (P.Cues[I-1].Car>=0) and (T-P.Cues[I-1].Time<0.185) and
        (F.Side<>P.Cars[P.Cues[I-1].Car].Side) then Inc(SpanHits);
    end;
    if SideBodyHit(Cue.Action) then begin
      Inc(Rams);
      Pose:=P.BossPose(Cue.Boss,T);
      Rig:=P.BossRig(Cue.Boss);
      Need(Abs(Pose.Root.X-Rig.Half-Q.X)<0.00065,'Truck missed bumper contact');
      Need(Abs(Pose.Root.Y-X.Y)<0.0005,'Truck missed contact height');
    end;
    if Cue.Action=saBossRoof then begin
      Inc(RoofHits);
      Pose:=P.BossPose(Cue.Boss,T);
      Rig:=P.BossRig(Cue.Boss);
      Need((Abs(Pose.Root.Y+Rig.Roof-X.Y)<0.0005) and
        (X.X>Pose.Root.X-Rig.Half) and (X.X<Pose.Root.X+Rig.Half*0.37),'Cargo roof missed');
    end;
    if Cue.Action=saRepair then begin
      Inc(Repairs);
      Need((P.JumpAt(T)>=0) and (Q.Y-P.BaseRoad(Q.X)>1.10) and (Cue.Health>Last),'Repair accessible from road or no recovery');
    end else Need(Cue.Health<=Last,'HP recovered without item');
    Last:=Cue.Health;
  end;
  for J in P.Jumps do begin
    A:=P.Cues[J.First].Time;
    T:=P.Cues[J.Last].Time;
    Need((T-A>=0.57) and (T-A<1.47),'Jump duration');
    X:=P.Hero(A);
    Need(P.Road(X.X,A,Height,Deck) and (Abs(Height-X.Y)<0.001),'Ramp takeoff mismatch');
    X:=P.Hero(T);
    Need(P.Road(X.X,T,Height,Deck) and (Abs(Height-X.Y)<0.001),'Deck landing mismatch');
    if J.Gap>0 then begin
      Inc(Gaps);
      Need(not P.Road((J.X0+J.X1)*0.5,(A+T)*0.5,Height,Deck),'Gap filled');
    end;
    if J.Lift>0 then begin
      Inc(Lifts);
      Need(P.Road(X.X,T,Height,Deck) and (Deck=sdMoving),'Moving deck absent');
      Need(P.Road(X.X,T+0.1,NearEdge,Deck) and (Abs(Height-NearEdge)>0.04),'Deck did not move');
    end;
    for K:=0 to 96 do begin
      Last:=SideMix(A,T,K/96);
      X:=P.Hero(Last);
      if P.Road(X.X,Last,Height,Deck) then
        Need(X.Y>=Height-0.007,'Vehicle crossed road surface in flight');
      if J.Roof<0 then Continue;
      B:=P.Cues[J.Roof].Boss;
      Pose:=P.BossPose(B,Last);
      Rig:=P.BossRig(B);
      if K>0 then Need(Pose.Root.X>P.BossPose(B,SideMix(A,T,(K-1)/96)).Root.X,
        'Truck reversed during cargo approach');
      if X.X+SideHeroHalf>Pose.Root.X-Rig.Half+0.004 then
        Need(X.Y>=Pose.Root.Y+Rig.Roof-0.026,Format('Vehicle clips cargo before roof touch %.3fs',[Last]));
    end;
  end;
  for I:=0 to High(P.Cars) do begin
    K:=P.ChainCue(I);
    if K<0 then Continue;
    Inc(Chains);
    T:=P.Cues[K].Time;
    Q:=P.CarPose(I,T).Root;
    R:=P.ChainCar(I,K,T).Root;
    Need(Abs(R.X-0.92-Q.X-P.CarHalf(I))<0.00065,'Chain collision missed follow-up cue');
  end;
  for Boss in P.Bosses do begin
    Include(Types,Boss.Kind);
    T:=P.Cues[Boss.Last].Time;
    Need(P.Distance(T+0.10)>P.Distance(T),'Vehicle stopped after boss');
  end;
  WriteLn(Format('%.2fs / %d stages / %d musical cues / %d front / %d rear / %d alternating / %d chain / %d jumps / %d gaps / %d moving / %d repairs / %d bosses / %d body / %d roof',
    [P.Duration,Length(P.Stages),Musical,FrontHits,RearHits,SpanHits,Chains,
    Length(P.Jumps),Gaps,Lifts,Repairs,Length(P.Bosses),Rams,RoofHits]));
  if Full then begin
    Need((Levels=[1..5]) and (Musical=Length(Audio.Hits)),'Level or cue coverage');
    Need((FrontHits>0) and (RearHits>0) and (SpanHits>50) and (Chains>0),'Missing high-density collisions');
    Need([saRock,saBump,saBossRam,saBossDrop,saBossEscort]<=Moves,'Missing road or truck attacks');
    Need((Gaps>0) and (Lifts>0) and (Repairs>0),'Missing road/recovery mechanics');
    Need((Length(P.Bosses)>=3) and (Rams>8) and (RoofHits>0),'Missing truck fights or roof contacts');
    Need((Types-[P.Bosses[0].Kind])<>[],'Truck appearance repeated');
  end;
end;

function FrameHash(Image:TBitmap):string;
var Hash:THashSHA2; Y:Integer;
begin
  Hash:=THashSHA2.Create;
  for Y:=0 to Image.Height-1 do Hash.Update(Image.ScanLine[Y]^,Image.Width*4);
  Result:=Hash.HashAsString;
end;

procedure RenderProof(P:TSideRacePlan;Audio,Cold:TRhythmAudio;const Ref:TRhythmPlanRef;const Folder:string);
var R:TRhythmRenderer; Image:TBitmap; PNG:TPngImage; I:Integer; Captured:set of TSideAction;

  procedure Snapshot(const Name:string;Time:Double);
  var H:string;
  begin
    R.Render(Image,Audio,Time,0);
    H:=FrameHash(Image);
    PNG.Assign(Image);
    PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));
    R.Render(Image,Cold,P.Duration-Time,0);
    R.Render(Image,Cold,Time+0.20,0,'',1,0,0,0.20);
    Need(FrameHash(Image)=H,'Cold restore / offset frame changed');
  end;

begin
  Image:=TBitmap.Create;
  R:=nil;
  PNG:=nil;
  try
    R:=TRhythmRenderer.Create;
    R.ConfigureStyle(rsSideRace,Ref,Audio.BossFrequency);
    R.UseD2D:=True;
    Image.PixelFormat:=pf32bit;
    Image.SetSize(960,540);
    PNG:=TPngImage.Create;
    Snapshot('day',P.Goal*0.13);
    Snapshot('dusk',P.Goal*0.43);
    Snapshot('night',P.Goal*0.67);
    Snapshot('finish',P.Goal);
    Captured:=[];
    for I:=0 to High(P.Cues) do
      if not (P.Cues[I].Action in Captured) and (P.Cues[I].Time+0.20<P.Duration) then begin
        Snapshot(Format('cue-%.2d',[Ord(P.Cues[I].Action)]),P.Cues[I].Time);
        Include(Captured,P.Cues[I].Action);
      end;
    for I:=0 to High(P.Jumps) do
      if P.Jumps[I].Lift>0 then begin
        Snapshot('moving-deck',(P.Cues[P.Jumps[I].First].Time+P.Cues[P.Jumps[I].Last].Time)*0.5);
        Break;
      end;
    if (ParamCount>1) and SameText(ParamStr(2),'Scan') then begin
      Image.SetSize(480,270);
      for I:=0 to Ceil(P.Duration*30)-1 do begin
        R.Render(Image,Cold,I/30,0);
        Need(R.LastUsedD2D,'Full-course render');
      end;
      WriteLn('Full-course frames: ',Ceil(P.Duration*30));
    end;
  finally
    PNG.Free;
    R.Free;
    Image.Free;
  end;
end;

var Audio,Cold:TRhythmAudio; P:TSideRacePlan; Ops:TStyleOperations; Context:TStylePrepareContext;
  Ref:TRhythmPlanRef; Source,Folder,Summary:string; Span:Double; Settings,Loaded:TRhythmSettings;
begin
  Audio:=nil;
  Cold:=nil;
  P:=nil;
  try
    EdgeCases;
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');
    if ParamCount>0 then Folder:=TPath.Combine(Folder,'Music');
    ForceDirectories(Folder);
    if ParamCount=0 then begin
      Source:=TPath.Combine(Folder,'source.identity');
      Audio:=Fixture(Source);
    end else begin
      Source:=ExpandFileName(ParamStr(1));
      Audio:=LoadRhythmAudio(Source,50);
    end;
    Audio.SetBossFrequency(100);
    Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsSideRace,StyleVariant(rsSideRace,50,100));
    Context:=Default(TStylePrepareContext);
    Context.Audio:=Audio;
    Context.Variant:=Ref.Variant;
    Ops:=StyleOperations(rsSideRace);
    Ops.Prepare(Context,Ref,Span,Summary);
    Need(Span=Audio.Duration,'Preview duration');
    Settings:=TRhythmSettings.Defaults;
    Settings.Style:=rsSideRace;
    Settings.Music:=Source;
    Settings.BossFrequency:=100;
    Settings.Plan:=Ref;
    Need(TRhythmSettings.TryJSON(Settings.ToJSON,Loaded) and (Loaded.Style=rsSideRace) and
      (Loaded.Plan.Digest=Ref.Digest),'Saved settings did not roundtrip');
    Cold:=Ops.LoadAudio(Loaded.Plan,Source,0);
    Need(Length(Cold.PCM)=0,'Cold plan decoded PCM');
    P:=LoadSideRace(Loaded.Plan,Cold,0);
    Verify(P,Audio,ParamCount=0);
    RenderProof(P,Audio,Cold,Ref,Folder);
    WriteLn('Side race PASS checks=',Checks);
  except
    on E:Exception do begin
      WriteLn(E.ClassName,': ',E.Message);
      ExitCode:=1;
    end;
  end;
  P.Free;
  Cold.Free;
  Audio.Free;
end.
