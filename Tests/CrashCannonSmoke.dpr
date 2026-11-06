program CrashCannonSmoke;
{$APPTYPE CONSOLE}
// 命中と反撃の同期、連鎖・着地、無音や短曲、PCMなし復元後の画素を確認する。

uses System.SysUtils,System.Classes,System.Math,System.Types,System.Hash,System.IOUtils,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmAudioCache,RhythmPlanRef,RhythmStyles,
  RhythmSettings,RhythmStyleOps,RhythmStyleRegistry,RhythmScene,RhythmCannonPlan,
  RhythmCannonTargets,RhythmCannonBuild,RhythmCannonCodec;

var Checks:Integer;

procedure Need(Valid:Boolean;const Description:string);
begin
  if not Valid then raise Exception.Create(Description);
  Inc(Checks);
end;

function Fixture(const Source:string;Duration,Gap:Double;Count:Integer):TRhythmAudio;
var I:Integer; Time:Double;
begin
  TFile.WriteAllText(Source,Format('Crash Cannon, %.5f / %.5f / %d',[Duration,Gap,Count]),TEncoding.UTF8);
  Result:=TRhythmAudio.Create;
  Result.Source:=Source;
  Result.SourceRevision:=AudioSourceStamp(Source);
  Result.Key:=THashSHA2.GetHashStringFromFile(Source);
  Result.Sensitivity:=50;
  Result.Duration:=Duration;
  Result.SoundEnd:=Duration;
  SetLength(Result.Hits,Count);
  Time:=Gap*0.87;
  for I:=0 to Count-1 do begin
    if Time>=Duration then begin SetLength(Result.Hits,I); Break; end;
    Result.Hits[I].Time:=Time;
    Result.Hits[I].Strength:=0.31+(I mod 9)*0.080;
    Time:=Time+Gap*(0.72+0.12*(I mod 7));
  end;
end;

procedure VerifyPlan(Plan:TCannonPlan;Audio:TRhythmAudio;Full:Boolean);
var Stage:TCannonStage; Cue:TCannonCue; Part:TCannonPart; A,B:TPointF; P,Q:TCannonPose;
  Targets:set of TCannonTarget; Enemy:set of TCannonEnemy;
  I,J,K,L,Hits,Counters,BossHits,Bosses,Landings,AlignedLaunch,LargeVolley:Integer;
  Time,Launch,Before,Landing:Double; R:TCannonPose;
begin
  Targets:=[];
  Enemy:=[];
  Hits:=0;
  Counters:=0;
  BossHits:=0;
  Bosses:=0;
  Landings:=0;
  AlignedLaunch:=0;
  LargeVolley:=0;
  Before:=0;
  for Stage in Plan.Stages do begin
    Need((Stage.Start=Before) and (Stage.Stop>Stage.Start) and (Stage.Stop<=Audio.Duration),'Stage boundaries');
    Before:=Stage.Stop;
    if Length(Stage.Cues)=0 then Continue;
    for J:=0 to High(Stage.Parts) do begin
      Part:=Stage.Parts[J];
      Landing:=Stage.AssemblyTime(J)-Stage.Start;
      P:=Stage.PartPose(J,Stage.Start);
      Need((P.Y-Part.H*0.5>CannonHeight-CannonGround) and
        (Stage.AssemblyTime(J)<Stage.Cues[0].Time),'Part starts in view or lands after the first impact');
      P:=Stage.PartPose(J,Stage.Start+Landing*0.40);
      Q:=Stage.PartPose(J,Stage.Start+Landing*0.65);
      R:=Stage.PartPose(J,Stage.Start+Landing*0.90);
      Need((P.Y>Q.Y) and (Q.Y-R.Y>P.Y-Q.Y),'Assembly fall must accelerate');
    end;
    Include(Targets,Stage.Kind);
    if CannonBoss(Stage.Kind) then Inc(Bosses);
    Need(Stage.Cues[High(Stage.Cues)].Enemy=ceNone,'Stage must end with a player impact');
    for I:=0 to High(Stage.Cues) do begin
      Cue:=Stage.Cues[I];
      J:=Audio.NearestHit(Cue.Time);
      Need((J>=0) and (Audio.Hits[J].Time=Cue.Time),'Impact moved off its accent');
      if Cue.Enemy<>ceNone then begin
        Include(Enemy,Cue.Enemy);
        Inc(Counters);
        Need(Abs(Stage.HeroX(Cue.Time)-Stage.HeroX(Cue.Time-0.83))>2.0,'Missing physical dodge');
        for K:=0 to 5 do
          Need(Abs(Stage.HeroX(Cue.Time+K*0.07)-Stage.Threat(Cue.Time))>
            CannonHazardRadius(Cue.Enemy)+1.0,'Cannon in enemy footprint');
        Continue;
      end;
      Inc(Hits);
      if CannonBoss(Stage.Kind) then Inc(BossHits);
      if Cue.Volley=4 then Inc(LargeVolley);
      J:=Stage.HitPart(I);
      Need((J>=0) and (Stage.Parts[J].BreakAt>=Cue.Time),'Direct hit did not reach intact armor');
      if Stage.Parts[J].Attack=I then Need(Stage.Parts[J].BreakAt=Cue.Time,'Impact did not start destruction');
      for K:=0 to Cue.Volley-1 do begin
        Launch:=Stage.Launch(I,K);
        Need((Launch>=Stage.Start-1E-9) and (Launch<Cue.Time),'Invalid launch time');
        A:=Stage.Shell(I,K,Launch);
        B:=Stage.Muzzle(I,K);
        Need((Abs(A.X-B.X)<1E-5) and (Abs(A.Y-B.Y)<1E-5),'Round starts outside muzzle');
        B:=Stage.Aim(I,K);
        Need(B.X>A.X+4.0,'Flight distance too short');
        A:=Stage.Shell(I,K,Cue.Time);
        Need((Abs(A.X-B.X)<1E-5) and (Abs(A.Y-B.Y)<1E-5),'Round misses target');
        for L:=1 to 14 do begin
          Time:=Launch+(Cue.Time-Launch)*L/15;
          A:=Stage.Shell(I,K,Time);
          for J:=0 to High(Stage.Parts) do begin
            Part:=Stage.Parts[J];
            if Part.BreakAt<Time then Continue;
            P:=Stage.PartPose(J,Time);
            Need((Abs((A.X-P.X)*Cos(P.Angle)+(A.Y-P.Y)*Sin(P.Angle))>=Part.W*0.5+0.126) or
              (Abs((A.Y-P.Y)*Cos(P.Angle)-(A.X-P.X)*Sin(P.Angle))>=Part.H*0.5+0.126),
              'Shell crossed a standing part');
          end;
        end;
        if K=0 then begin
          J:=Audio.NearestHit(Launch);
          if (J>=0) and (Abs(Audio.Hits[J].Time-Launch)<1E-8) then Inc(AlignedLaunch);
        end;
      end;
    end;
    for I:=0 to High(Stage.Parts) do begin
      Part:=Stage.Parts[I];
      Need((Part.Attack>=0) and (Part.BreakAt<Part.LandAt) and (Part.LandAt<Stage.Stop),
        'Piece failed to land by stage end');
      if CannonBoss(Stage.Kind) then
        Need((Stage.ShatterTime(I)>=Part.LandAt) and (Stage.ShatterTime(I)<Stage.Stop),
          'Boss piece must shatter before the end of the stage');
      P:=Stage.PartPose(I,Part.BreakAt-0.00001);
      Q:=Stage.PartPose(I,Part.LandAt);
      if (P.Y>1.6) and (P.Y-Q.Y>0.5) then Inc(Landings);
      Need((Stage.Cues[Part.Attack].Enemy=ceNone) and (Part.BreakAt>=Stage.Cues[Part.Attack].Time),
        'Untriggered debris');
    end;
  end;
  if Full then begin
    Need(Targets=[Low(TCannonTarget)..High(TCannonTarget)],'Target variety');
    Need(Enemy=[ceShell..ceHeavy],'Enemy attack variety');
    Need((Length(Plan.Stages)>=16) and (Bosses>=4),'Three-minute pacing');
    Need((BossHits>=Counters*1.8) and (BossHits<=Counters*2.30),'Boss turn ratio');
    Need((Landings>=55) and (LargeVolley>10) and (AlignedLaunch>60),'Missing major falls or music-linked firing');
  end;
  Time:=Plan.Stages[High(Plan.Stages)].Finish;
  WriteLn(Format('%.3fs, stages=%d bosses=%d hits=%d boss hits=%d counters=%d lands=%d aligned launches=%d final=%.3fs',
    [Plan.Duration,Length(Plan.Stages),Bosses,Hits,BossHits,Counters,Landings,AlignedLaunch,Time]));
end;

procedure VerifySupport(Plan:TCannonPlan;Full:Boolean);
var Stage:TCannonStage; Cue:TCannonCue; Life,Before:TCannonSupportLife;
  I,Barrel,Losses,StageLosses,Suppressed,Carry:Integer; Launch:Double;
begin
  Losses:=0;
  Suppressed:=0;
  Carry:=0;
  for Stage in Plan.Stages do begin
    if Stage.Start>0 then
      for Barrel:=1 to 3 do
        if Plan.SupportAt(Barrel,Stage.Start-0.0001,Before) and
          (Before.Ready<Stage.Start) and (Before.Lost>Stage.Start) then begin
          Need(Plan.SupportAt(Barrel,Stage.Start,Life) and (Life.Ready=Before.Ready) and
            (Life.Lost=Before.Lost),'Ready support disappeared at a stage boundary');
          Inc(Carry);
        end;
    StageLosses:=0;
    for I:=0 to High(Stage.Cues) do begin
      Cue:=Stage.Cues[I];
      Barrel:=Stage.SupportHit(I);
      if Barrel>0 then begin
        Need((Cue.Enemy<>ceNone) and CannonBoss(Stage.Kind),'Support lost without a boss counter');
        Need(Plan.SupportAt(Barrel,Cue.Time-Cue.Lead,Before) and
          (Before.Ready<=Cue.Time-Cue.Lead) and (Before.Lost=Cue.Time),'Enemy fired at absent support');
        Need(Plan.SupportAt(Barrel,Cue.Time+0.58,Life) and (Life.Lost=Cue.Time),
          'Destroyed support returned too early');
        Inc(Losses);
        Inc(StageLosses);
      end;
      for Barrel:=1 to Cue.Volley-1 do begin
        Launch:=Stage.Launch(I,Barrel);
        Need(Plan.SupportAt(Barrel,Launch,Life),'Scheduled support never deployed');
        if Plan.Fires(Stage,I,Barrel) then
          Need((Launch>=Life.Ready) and (Launch<Life.Lost),'Absent support opened fire')
        else begin
          Need((Launch<Life.Ready) or (Launch>=Life.Lost),'Ready support missed its launch');
          Inc(Suppressed);
        end;
      end;
    end;
    Need(StageLosses<=1,'Too many support losses in one stage');
  end;
  WriteLn('Support losses=',Losses,' suppressed shots=',Suppressed,' carried across stages=',Carry);
  if Full then Need((Losses>=4) and (Carry>0),'Missing support lifecycle coverage');
end;

procedure VerifySupportInterruption;
var Plan:TCannonPlan; Stage:TCannonStage; I:Integer;
begin
  Plan:=TCannonPlan.Create;
  try
    SetLength(Plan.Stages,1);
    Stage:=TCannonStage.Create;
    Plan.Stages[0]:=Stage;
    Stage.Kind:=ctTower;
    SetLength(Stage.Cues,4);
    for I:=0 to High(Stage.Cues) do begin
      Stage.Cues[I].Time:=1.0+I;
      Stage.Cues[I].Lead:=0.5;
      Stage.Cues[I].Volley:=2;
    end;
    Stage.Cues[1].Enemy:=ceShell;
    Stage.Cues[1].Volley:=0;
    Plan.ResolveSupport;
    Need(Plan.Fires(Stage,0,1) and (Stage.SupportHit(1)=1),'Support did not fire and get hit');
    Need(Plan.Fires(Stage,2,0) and not Plan.Fires(Stage,2,1),'Lost support still fires, or the main gun stopped');
    Need(Plan.Fires(Stage,3,1),'Replacement did not resume the later volley');
  finally
    Plan.Free;
  end;
end;

function BitmapHash(Image:TBitmap):string;
var Buffer:TMemoryStream;
begin
  Buffer:=TMemoryStream.Create;
  try
    Image.SaveToStream(Buffer);
    Result:=THashSHA2.GetHashString(Buffer);
  finally
    Buffer.Free;
  end;
end;

procedure Frames(Plan:TCannonPlan;Audio,Cold:TRhythmAudio;const Ref:TRhythmPlanRef;const Folder:string);
var Live,Restored:TRhythmRenderer; Image:TBitmap; PNG:TPngImage; Stage:TCannonStage; Cue:TCannonCue;
  Seen:set of TCannonTarget; I,J:Integer; HasDodge,HasLoss:Boolean;

  procedure Capture(const Name:string;Time:Double;Save:Boolean);
  var Expected:string;
  begin
    Live.Render(Image,Audio,Time,0);
    Expected:=BitmapHash(Image);
    if Save then begin
      PNG.Assign(Image);
      PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));
    end;
    Restored.Render(Image,Cold,Plan.Duration-Time,0);
    Restored.Render(Image,Cold,Time+0.25,0,'',1,0,0,0.25);
    Need(Expected=BitmapHash(Image),'Cold seek or offset changed frame '+Name);
  end;

begin
  Live:=TRhythmRenderer.Create;
  Restored:=TRhythmRenderer.Create;
  Image:=TBitmap.Create;
  PNG:=TPngImage.Create;
  try
    Live.ConfigureStyle(rsCrashCannon,Ref,0,0);
    Restored.ConfigureStyle(rsCrashCannon,Ref,0,0);
    Image.PixelFormat:=pf32bit;
    Image.SetSize(960,540);
    Stage:=Plan.Stages[0];
    Capture('assembly-start',Stage.Start,True);
    Capture('assembly-fall',Stage.Start+0.80*(Stage.AssemblyTime(0)-Stage.Start),True);
    if Length(Stage.Cues)>0 then Capture('front-impact',Stage.Cues[0].Time+0.065,True);
    Seen:=[];
    HasDodge:=False;
    HasLoss:=False;
    for Stage in Plan.Stages do begin
      if not HasLoss then
        for J:=0 to High(Stage.Cues) do
          if Stage.SupportHit(J)>0 then begin
            Cue:=Stage.Cues[J];
            Capture('support-incoming',Cue.Time-Cue.Lead*0.27,True);
            Capture('support-hit',Cue.Time+0.10,True);
            Capture('support-wreckage',Cue.Time+0.62,True);
            HasLoss:=True;
            Break;
          end;
      if (Stage.Kind in Seen) or (Length(Stage.Cues)=0) then Continue;
      Include(Seen,Stage.Kind);
      I:=Ord(Stage.Kind);
      Capture('target-'+IntToStr(I),Max(Stage.AssemblyTime(High(Stage.Parts)),Stage.Cues[0].Time-0.09),True);
      Capture('blast-'+IntToStr(I),Stage.Finish+Min(0.22,(Stage.Stop-Stage.Finish)*0.36),True);
      if CannonBoss(Stage.Kind) and not HasDodge then
        for Cue in Stage.Cues do
          if Cue.Enemy<>ceNone then begin
            Capture('counter-flight',Cue.Time-0.36,True);
            Capture('counter-impact',Cue.Time+0.07,True);
            HasDodge:=True;
            Break;
          end;
    end;
    Stage:=Plan.Stages[High(Plan.Stages)];
    Capture('final-collapse',Stage.Finish+(Stage.Stop-Stage.Finish)*0.71,True);
    Capture('final-wreckage',Plan.Duration,True);
    for J:=0 to 1 do begin
      Live.UseD2D:=J=1;
      Restored.UseD2D:=J=1;
      Live.ConfigureStyle(rsCrashCannon,Ref,0,1);
      Restored.ConfigureStyle(rsCrashCannon,Ref,0,1);
      Image.SetSize(576,324);
      Capture('equalizer',Plan.Duration*0.48,False);
      Image.SetSize(360,540);
      Capture('vertical',Plan.Duration*0.74,False);
    end;
  finally
    PNG.Free;
    Image.Free;
    Restored.Free;
    Live.Free;
  end;
end;

procedure Run(Audio:TRhythmAudio;const Folder:string;Full,Draw:Boolean);
var Plan,Rebuilt:TCannonPlan; Cold:TRhythmAudio; Ref,RepeatRef:TRhythmPlanRef;
  Settings,Loaded:TRhythmSettings; Ops:TStyleOperations; Context:TStylePrepareContext;
  EndTime:Double; Summary:string;
begin
  Ops:=StyleOperations(rsCrashCannon);
  Context:=Default(TStylePrepareContext);
  Context.Audio:=Audio;
  Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsCrashCannon);
  Ops.Prepare(Context,Ref,EndTime,Summary);
  Need(EndTime=Audio.Duration,'Playback extends past the source');
  Settings:=TRhythmSettings.Defaults;
  Settings.Style:=rsCrashCannon;
  Settings.Music:=Audio.Source;
  Settings.Plan:=Ref;
  Need(TRhythmSettings.TryJSON(Settings.ToJSON,Loaded) and (Loaded.Style=rsCrashCannon) and
    (Loaded.Plan.Digest=Ref.Digest),'Settings did not round-trip');
  Cold:=Ops.LoadAudio(Loaded.Plan,Audio.Source,0);
  try
    Need(Length(Cold.PCM)=0,'PCM required for cold restore');
    Plan:=LoadCannonPlan(Loaded.Plan,Cold,0);
    try
      VerifyPlan(Plan,Audio,Full);
      VerifySupport(Plan,Full);
      Rebuilt:=BuildCannonPlan(Audio,nil);
      try
        RepeatRef:=Ref;
        SaveCannonPlan(Rebuilt,Audio,RepeatRef);
        Need(RepeatRef.Digest=Ref.Digest,'Plan generation is nondeterministic');
      finally
        Rebuilt.Free;
      end;
      if Draw then Frames(Plan,Audio,Cold,Ref,Folder);
    finally
      Plan.Free;
    end;
  finally
    Cold.Free;
  end;
end;

var Audio:TRhythmAudio; Folder,Path:string;
begin
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');
    ForceDirectories(Folder);
    if ParamCount>0 then begin
      Path:=TPath.Combine(Folder,'Song');
      ForceDirectories(Path);
      Audio:=LoadRhythmAudio(ParamStr(1),50);
      try Run(Audio,Path,False,True); finally Audio.Free; end;
    end else begin
      VerifySupportInterruption;
      Audio:=Fixture(TPath.Combine(Folder,'dense.identity'),180,0.084,4000);
      try Run(Audio,Folder,True,True); finally Audio.Free; end;
      Audio:=Fixture(TPath.Combine(Folder,'short.identity'),6.4,0.23,50);
      try Run(Audio,Folder,False,False); finally Audio.Free; end;
      Audio:=Fixture(TPath.Combine(Folder,'sparse.identity'),58.6,2.64,60);
      try Run(Audio,Folder,False,False); finally Audio.Free; end;
      Audio:=Fixture(TPath.Combine(Folder,'silent.identity'),0.18,0.01,0);
      try Run(Audio,Folder,False,False); finally Audio.Free; end;
    end;
    WriteLn('Crash Cannon PASS checks=',Checks);
  except
    on E:Exception do begin
      WriteLn(E.ClassName,': ',E.Message);
      ExitCode:=1;
    end;
  end;
end.
