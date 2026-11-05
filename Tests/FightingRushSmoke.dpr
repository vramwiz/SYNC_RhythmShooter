program FightingRushSmoke;
{$APPTYPE CONSOLE}
// 接触・回避・気合弾・空中コンボと、既存の保存／シーク／オフセット経路を検証する。
uses System.SysUtils,System.Types,System.Math,System.Classes,System.Hash,System.IOUtils,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmAudioCache,RhythmStyles,RhythmPlanRef,
  RhythmSettings,RhythmStyleOps,RhythmStyleRegistry,RhythmScene,RhythmRushPlan,RhythmRushCodec;

var Checks:Integer;

procedure Need(Valid:Boolean;const Description:string);
begin
  if not Valid then raise Exception.Create(Description);
  Inc(Checks);
end;

function Fixture(const Source:string):TRhythmAudio;
const Gap:array[0..9] of Double=(0.53,0.33,0.046,0.37,0.62,0.29,0.054,0.48,0.31,0.40);
var I,N,Section:Integer; T:Double;
begin
  TFile.WriteAllText(Source,'Fighting Rush 180-second synthetic accents.',TEncoding.UTF8);
  Result:=TRhythmAudio.Create;
  Result.Source:=Source;
  Result.SourceRevision:=AudioSourceStamp(Source);
  Result.Key:=THashSHA2.GetHashStringFromFile(Source);
  Result.Sensitivity:=50;
  Result.Duration:=180;
  SetLength(Result.Envelope,18000);
  for I:=0 to High(Result.Envelope) do begin
    Section:=I div 1000;
    Result.Envelope[I]:=0.09+0.087*((Section*7) mod 10)+0.04*Sqr(Sin(I*0.04));
    if I mod 1000>970 then Result.Envelope[I]:=0.002;
  end;
  Result.UpdateSoundBounds;
  N:=0;
  T:=0;
  SetLength(Result.Hits,6000);
  while T<179.6 do begin
    Section:=Trunc(T/10) mod Length(Gap);
    Result.Hits[N].Time:=T;
    Result.Hits[N].Strength:=0.23+0.11*(N mod 7);
    Inc(N);
    T:=T+Gap[Section]*(0.86+(N mod 5)*0.061);
  end;
  SetLength(Result.Hits,N);
end;

procedure Verify(Plan:TRushPlan;Audio:TRhythmAudio;Full:Boolean);
var
  I,J,Bosses,BossArcs,AirHits,BossAirHits,GroundOrbs,AirOrbs,Parries,Crashes,Chases,GroupFinishes,EnemyOrbs:Integer;
  T:Double;
  P,Q,R:TPointF;
  A:TRushCue;
  F:TRushFoe;
  Arc:TRushArc;
  Levels:set of 1..5;
  Modes:set of TRushMode;
  Moves,Finishes:set of TRushMove;
  Kinds:set of 0..5;
  Sides:set of Boolean;
  Threats:set of TRushThreat;
begin
  Levels:=[];
  Modes:=[];
  Moves:=[];
  Finishes:=[];
  Kinds:=[];
  Sides:=[];
  Threats:=[];
  Bosses:=0;
  BossArcs:=0;
  AirHits:=0;
  BossAirHits:=0;
  GroundOrbs:=0;
  AirOrbs:=0;
  Parries:=0;
  Crashes:=0;
  Chases:=0;
  GroupFinishes:=0;
  EnemyOrbs:=0;
  for I:=0 to High(Plan.Stages) do begin
    Include(Levels,Plan.Stages[I].Level);
    Include(Modes,Plan.Stages[I].Mode);
    if I=0 then Need(Plan.Stages[I].Level=1,'Opening difficulty');
    if I>0 then begin
      T:=Plan.Stages[I].StartTime;
      Need(Plan.Hero(T-1E-5).Distance(Plan.Hero(T+1E-5))<0.004,'Cut moved the player');
    end;
  end;
  for I:=0 to High(Plan.Cues) do begin
    A:=Plan.Cues[I];
    F:=Plan.Foes[A.Foe];
    Include(Moves,A.Move);
    Include(Sides,F.Side<0);
    Need(Audio.Hits[Audio.NearestHit(A.Time)].Time=A.Time,'Original accent moved');
    Need(Plan.MoveAt(A.Time)=I,'Pose hit missed beat');
    P:=Plan.Contact(I);
    Q:=Plan.Enemy(A.Foe,A.Time);
    Need(P.Distance(Q)<0.0006,'Opponent missed its contact');
    if A.Time>0 then Need(Plan.Enemy(A.Foe,Max(0.0,A.Time-1E-5)).Distance(Q)<0.018,
      Format('Opponent teleported before hit %d at %.4fs',[I,A.Time]));
    Need(Plan.Enemy(A.Foe,A.Time+1E-5).Distance(Q)<0.018,'Opponent teleported after a hit');
    R:=Plan.Hero(A.Time);
    if A.Flight>0 then begin
      if Defensive(A.Move) then P:=Plan.Incoming(I) else P:=Plan.Impact(I);
      Need(Plan.Projectile(I,A.Time).Distance(P)<0.0003,'Projectile missed target');
      Q:=Plan.Projectile(I,A.Time-A.Flight);
      if Defensive(A.Move) then begin
        Inc(EnemyOrbs);
        Need((Q.X-P.X)*F.Side>0.21,'Enemy projectile fires backward');
      end else Need((P.X-Q.X)*F.Side>0.21,'Hero projectile fires backward');
      Q:=Plan.Enemy(A.Foe,A.Time);
      if not Defensive(A.Move) then begin
        if R.Y>0.10 then Inc(AirOrbs) else Inc(GroundOrbs);
      end;
    end;
    if Defensive(A.Move) then begin
      Inc(Parries);
      Include(Threats,Plan.Threat(I));
      Need((I<F.Last) and not Defensive(Plan.Cues[I+1].Move),'No answer to enemy attack');
    end else if (A.Move<>raOrb) and (A.Move<>raCrash) then
      Need(Abs(Plan.Impact(I).X-R.X)<1.10,'Melee hit reaches across the screen');
    if Plan.CrowdExtras(I)>0 then begin
      Inc(GroupFinishes);
      Need(Plan.CrowdEnemy(I,0,A.Time).Distance(Q)<0.56,'Group target out of range');
    end;
    if A.Move=raCrash then begin
      Inc(Crashes);
      Need(Plan.Enemy(A.Cause,A.Time).Distance(Q)<0.255,'Airborne enemy misses the second body');
    end;
    if A.Move in [raAirPunch,raAirKick] then begin
      Need(R.Y>0,'Air strike outside its arc');
      Inc(AirHits);
      if F.Boss then Inc(BossAirHits);
    end;
  end;
  for Arc in Plan.Arcs do begin
    Need((Plan.Hero(Plan.Cues[Arc.First].Time).Y=0) and (Plan.Hero(Plan.Cues[Arc.Last].Time).Y=0),'Takeoff/landing off beat');
    Need(Plan.Hero((Plan.Cues[Arc.First].Time+Plan.Cues[Arc.Last].Time)*0.5).Y>0.85,'No aerial lift');
    if Plan.Foes[Plan.Cues[Arc.First].Foe].Boss then Inc(BossArcs);
  end;
  for I:=0 to High(Plan.Foes) do begin
    F:=Plan.Foes[I];
    if F.Boss then begin
      Inc(Bosses);
      Include(Kinds,F.Kind);
      Include(Finishes,Plan.Cues[F.Last].Move);
    end else if (F.Last>F.First) and (Plan.Stages[Plan.StageAt(Plan.Cues[F.First].Time)].Mode=rmChase) then
      Inc(Chases);
  end;
  J:=0;
  for I:=0 to 5 do if I in Kinds then Inc(J);
  WriteLn(Format('%.2fs: %d stages, %d cues, %d orbs ground / %d air, %d defences, %d collisions, %d chases, %d air strikes, %d bosses (%d types), %d boss arcs / %d boss air strikes',
    [Plan.Duration,Length(Plan.Stages),Length(Plan.Cues),GroundOrbs,AirOrbs,Parries,Crashes,Chases,AirHits,Bosses,J,BossArcs,BossAirHits]));
  WriteLn('Synchronized group finishers: ',GroupFinishes,' / enemy orbs: ',EnemyOrbs);
  if not Full then Exit;
  Need(Length(Plan.Cues)=Length(Audio.Hits),'Accent lost');
  Need((Levels=[1..5]) and (Modes=[Low(TRushMode)..High(TRushMode)]),'Missing level or scene');
  Need((GroundOrbs>0) and (AirOrbs>0) and (Parries>0) and (Crashes>0) and (Chases>0) and (GroupFinishes>0),'Missing combat coverage');
  Need([raPunch,raKick,raLaunch,raAirPunch,raAirKick,raGuard,raDodge,raCounter,raThrow,raSlam,raSpecial]<=Moves,'Missing move');
  Need(Sides=[False,True],'No attacks from behind');
  Need((J>=3) and (BossArcs>0) and (BossAirHits>0) and (Finishes<>[raSlam]),'Boss variation or combo missing');
  Need((rtKick in Threats) and (rtWeapon in Threats) and (EnemyOrbs>0),'Missing enemy attack types');
end;

function FrameHash(Image:TBitmap):string;
var Hash:THashSHA2; Y:Integer;
begin
  Hash:=THashSHA2.Create;
  for Y:=0 to Image.Height-1 do Hash.Update(Image.ScanLine[Y]^,Image.Width*4);
  Result:=Hash.HashAsString;
end;

procedure RenderProof(Plan:TRushPlan;Audio,Cold:TRhythmAudio;const Ref:TRhythmPlanRef;const Folder:string);
var R:TRhythmRenderer; Image:TBitmap; PNG:TPngImage;
  H:string; S,I,J,B:Integer; T,FromTime:Double;
  Saved:set of TRushMove;
  BossFrame:Boolean;

  procedure Snapshot(const Name:string;Time:Double);
  begin
    R.Render(Image,Audio,Time,0);
    H:=FrameHash(Image);
    PNG.Assign(Image);
    PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));
    R.Render(Image,Cold,Plan.Duration-Time,0);
    R.Render(Image,Cold,Time+0.20,0,'',1,0,0,0.20);
    Need(FrameHash(Image)=H,'Cold restore / offset frame changed');
  end;

begin
  Image:=TBitmap.Create;
  R:=nil;
  PNG:=nil;
  try
    R:=TRhythmRenderer.Create;
    R.ConfigureStyle(rsFightingRush,Ref,Audio.BossFrequency);
    R.UseD2D:=True;
    Image.PixelFormat:=pf32bit;
    Image.SetSize(960,540);
    PNG:=TPngImage.Create;
    for S:=0 to High(Plan.Stages) do begin
      FromTime:=Plan.Stages[S].StartTime;
      B:=Plan.Stages[S].Boss;
      I:=Plan.CueFrom(FromTime+0.55);
      if B>=0 then I:=Plan.Foes[B].Last-1;
      if (I<Length(Plan.Cues)) and (Plan.StageAt(Plan.Cues[I].Time)=S) then
        Snapshot(Format('stage-%.2d',[S]),Plan.Cues[I].Time);
    end;
    Saved:=[];
    BossFrame:=False;
    for I:=0 to High(Plan.Cues) do begin
      T:=Plan.Cues[I].Time;
      J:=Ord(Plan.Cues[I].Move);
      if (T+0.20<Plan.Duration) and not (Plan.Cues[I].Move in Saved) then begin
        Snapshot(Format('move-%.2d',[J]),T+0.012);
        Include(Saved,Plan.Cues[I].Move);
      end;
      if not BossFrame and Plan.Foes[Plan.Cues[I].Foe].Boss and
        (Plan.Cues[I].Move in [raAirPunch,raAirKick]) then begin
        Snapshot('boss-air-combo',T+0.012);
        BossFrame:=True;
      end;
    end;
    if (ParamCount>1) and SameText(ParamStr(2),'Scan') then begin
      Image.SetSize(480,270);
      for I:=0 to Ceil(Plan.Duration*30)-1 do begin
        R.Render(Image,Cold,I/30,0);
        Need(R.LastUsedD2D,'Full-course render');
      end;
      WriteLn('Full-course frames: ',Ceil(Plan.Duration*30));
    end;
  finally
    PNG.Free;
    R.Free;
    Image.Free;
  end;
end;

var Audio,Cold:TRhythmAudio; Plan:TRushPlan; Ops:TStyleOperations; Context:TStylePrepareContext;
  Ref:TRhythmPlanRef; Source,Folder,Summary:string; Span:Double; Settings,Loaded:TRhythmSettings;
begin
  Audio:=nil;
  Cold:=nil;
  Plan:=nil;
  try
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
    Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsFightingRush,StyleVariant(rsFightingRush,50,100));
    Context:=Default(TStylePrepareContext);
    Context.Audio:=Audio;
    Context.Variant:=Ref.Variant;
    Ops:=StyleOperations(rsFightingRush);
    Ops.Prepare(Context,Ref,Span,Summary);
    Need(Span=Audio.Duration,'Preview duration');
    Settings:=TRhythmSettings.Defaults;
    Settings.Style:=rsFightingRush;
    Settings.Music:=Source;
    Settings.BossFrequency:=100;
    Settings.Plan:=Ref;
    Need(TRhythmSettings.TryJSON(Settings.ToJSON,Loaded) and (Loaded.Style=rsFightingRush) and
      (Loaded.Plan.Digest=Ref.Digest),'Saved settings did not roundtrip');
    Cold:=Ops.LoadAudio(Loaded.Plan,Source,0);
    Need(Length(Cold.PCM)=0,'Cold plan decoded PCM');
    Plan:=LoadRushPlan(Loaded.Plan,Cold,0);
    Verify(Plan,Audio,ParamCount=0);
    RenderProof(Plan,Audio,Cold,Ref,Folder);
    WriteLn('Fighting Rush PASS checks=',Checks);
  except
    on E:Exception do begin
      WriteLn(E.ClassName,': ',E.Message);
      ExitCode:=1;
    end;
  end;
  Plan.Free;
  Cold.Free;
  Audio.Free;
end.
