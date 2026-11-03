program RunnerPlanSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmPreparedData,
  RhythmRunnerPlan,RhythmRunnerAction,RhythmRunnerScene,RhythmSettings,RhythmAnimation,RhythmImageBank,RhythmPaths;
var Audio,Cold:TRhythmAudio;Plan,Restored,BadPlan:TRunnerPlan;Score,Again:TRunnerActionPlan;Ref,BadRef:TRhythmPlanRef;
  Scene:TRunnerAnimation;Render:TAnimationRenderer;Image:TBitmap;PNG:TPngImage;Stamp:TWin32FileAttributeData;
  Source,OutDir,Hash,JSON,Revision:string;C,I,J,K,N,Backend,Checks,Contacts,Moving,Falls,Both,Bosses,Frequency,FloorChecks,TimingChecks,WalkChecks,IdleChecks,OpposingChecks,BodyContactChecks:Integer;
  Time,Gap,Duration,Err,MaxErr:Double;Pose,Other:TRunPose;Pad:TRunPad;Jump:TRunJump;H:TRunHit;G,Tip,O:TRunPoint;
  Root,CopyRoot:TJSONObject;State,Loaded:TRhythmSettings;Rejected:Boolean;Seen,Snapped:array[TRunHitKind] of Boolean;Kind:TRunHitKind;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
function ImageHash:string;
var M:TMemoryStream;B:TBytes;Hasher:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(B,M.Size);M.Position:=0;if Length(B)>0 then M.ReadBuffer(B[0],Length(B));Hasher:=THashSHA2.Create;Hasher.Update(B);Result:=Hasher.HashAsString;finally M.Free;end;end;
procedure Snap(const Name:string;T:Double);
begin Render.Render(Image,T,0);Need(Scene.Notice='','Scene error: '+Scene.Notice);PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(OutDir,Name+'.png'));finally FreeAndNil(PNG);end;end;
// v6の保存済みABCは再生成せず読み、元の行動・出現時刻を維持する。
procedure LegacyABC6;
var J,Original,CopyJSON:TJSONObject;R:TRhythmPlanRef;Meta:TRhythmAudio;Old:TRunnerPlan;
begin
 J:=TJSONObject.ParseJSONValue(TFile.ReadAllText('Tests/Fixtures/Runner-v6.json',TEncoding.UTF8)) as TJSONObject;
 Meta:=nil;Old:=nil;
 try
  Original:=J.GetValue<TJSONObject>('action');R:=NewPlanRef(J.GetValue<string>('source'),50,0,rsRunner,Original.GetValue<Integer>('frequency')+1);
  R.Version:=6;R.Key:=J.GetValue<string>('key');R.SourceRevision:=Revision;WritePreparedData(J,R);
  Meta:=TRunnerPlan.LoadAudioMetadata(R,Source,0);Old:=TRunnerPlan.Load(R,Meta,0);
  Need((Old.RecipeVersion=6) and (Old.Action.Version=6),'Legacy ABC version');
  CopyJSON:=Old.Action.ToJSON;try Need(CopyJSON.ToJSON=Original.ToJSON,'Legacy ABC regenerated');finally CopyJSON.Free;end;
  Writeln('Legacy ABC v6 saved score PASS');
 finally Old.Free;Meta.Free;J.Free;end;
end;
// Source time alone is insufficient: verify the actual sprite is already at the right edge.
procedure CheckEnemyEntry(Score:TRunnerActionPlan;Renderer:TAnimationRenderer);
var I,J,X,Y,Count,Samples,LastSection:Integer;H:TRunHit;Clock,Scale,Left,Top,CX,CY:Double;Tint:TColor;Pixel:PByte;
begin
 Samples:=0;LastSection:=-1;Scale:=Min(Image.Width/1.8,Image.Height);Left:=(Image.Width-Scale*1.8)/2;Top:=(Image.Height-Scale)/2;
 for I:=0 to Score.EnemyCount-1 do begin
  H:=Score.Hits[Score.EnemyIndex(I)];if H.Section=LastSection then Continue;
  LastSection:=H.Section;Clock:=H.Time-2.6;Need(Clock>=H.Show,'Entry window too late');
  Renderer.Render(Image,Clock,0);CX:=Left+(H.X+0.026-Score.WorldAt(Clock)+0.42)*Scale;CY:=Top+(H.Y+0.009)*Scale;
  Tint:=RGB(103,80,134);if H.Target mod 3=1 then Tint:=RGB(166,88,91) else if H.Target mod 3=2 then Tint:=RGB(58,119,129);
  Count:=0;
  for Y:=Max(0,Round(CY-0.003*Scale)) to Min(Image.Height-1,Round(CY+0.003*Scale)) do begin Pixel:=Image.ScanLine[Y];
   for X:=Max(0,Round(CX-0.014*Scale)) to Min(Image.Width-1,Round(CX+0.014*Scale)) do begin J:=X*4;
    if (Pixel[J]=GetBValue(Tint)) and (Pixel[J+1]=GetGValue(Tint)) and (Pixel[J+2]=GetRValue(Tint)) then Inc(Count);
   end;
  end;
  Need(Count>3,'Enemy sprite missing at scroll entry (old time culling)');Inc(Samples);if Samples>=8 then Break;
 end;
 if Score.EnemyCount>0 then Need(Samples>0,'Entry coverage missing');
 Writeln('Runner enemy scroll-entry pixels PASS sections=',Samples);
end;
procedure CheckContactTiming(Score:TRunnerActionPlan;Index:Integer);
const Lead:array[0..4] of Double=(0.020,0.012,0.006,0.001,0.0001);
var H,Previous:TRunHit;Pose:TRunPose;Grip,Tip:TRunPoint;Time:Double;N,Prior:Integer;
begin
  H:=Score.Hits[Index];
  for N:=Low(Lead) to High(Lead) do begin
    Time:=H.Time-Lead[N];if Time<0 then Continue;
    // Coalesced armor contacts may deliberately retain an earlier impact.
    // Check the anticipation only when this is the selected upcoming action.
    if Score.ActionBefore(Time+0.055)<>Index then Continue;
    Prior:=Score.ActionBefore(Time);if (H.Kind=rhSword) and (Prior>=0) then begin Previous:=Score.Hits[Prior];if (Previous.Kind=rhSword) and (Previous.Target=H.Target) then Continue;end;
    if H.Kind in [rhSword,rhBossCut,rhParry,rhFinish] then begin
      Need(Score.BladeAt(Time,Grip,Tip),'Missing anticipation');
      Need(Max(Grip.X,Tip.X)<H.X-0.005,'Blade reaches the contact before the accent');
      Pose:=Score.HeroAt(Time);Need(Pose.Pose<>4,'Contact pose begins before the accent');Inc(TimingChecks);
    end;
    if H.Kind=rhHurt then begin Pose:=Score.HeroAt(Time);Need(Pose.Pose<>7,'Hurt pose begins before the enemy impact');Inc(TimingChecks);end;
  end;
  if H.Kind in [rhSword,rhBossCut,rhFinish] then begin Pose:=Score.HeroAt(H.Time);Need(Pose.Pose=4,'Contact pose misses the accent');end;
  if H.Kind=rhHurt then begin Pose:=Score.HeroAt(H.Time);Need(Pose.Pose=7,'Hurt pose misses the enemy impact');end;
end;
procedure CheckStride(Score:TRunnerActionPlan;Time:Double;Boss:Boolean);
var A,B:TRunFeet;P,Q:TRunPose;BP,BQ:TRunBossPose;S:TRunSection;Pad:Integer;F,G,O1,O2:TRunPoint;Support,Ground:Double;
begin
  S:=Score.Sections[Score.SectionAt(Time)];Support:=0;Ground:=RA_GROUND;
  if Boss then begin BP:=Score.BossAt(Time);BQ:=Score.BossAt(Time+0.001);if BP.Airborne or BQ.Airborne then Exit;A:=Score.BossFeetAt(Time);B:=Score.BossFeetAt(Time+0.001);end
  else begin
    P:=Score.HeroAt(Time);Q:=Score.HeroAt(Time+0.001);if P.Airborne or Q.Airborne then Exit;A:=Score.FeetAt(Time);B:=Score.FeetAt(Time+0.001);Ground:=P.Y;
    if S.Mode=rmJump then begin Pad:=Score.PadBefore(Time);if Pad<>Score.PadBefore(Time+0.001) then Exit;O1:=Score.PadOffset(Pad,Time);O2:=Score.PadOffset(Pad,Time+0.001);Support:=O2.X-O1.X;end;
  end;
  if A.Plant=0 then F:=A.LeftFoot else F:=A.RightFoot;
  if B.Plant=0 then G:=B.LeftFoot else G:=B.RightFoot;
  Need(Abs(F.Y-Ground)<1E-7,'Planted sole leaves the floor');Need((A.LeftFoot.Y<=Ground+1E-7) and (A.RightFoot.Y<=Ground+1E-7),'Sole penetrates floor');
  if (A.Step=B.Step) and (A.Direction=B.Direction) and A.Moving and B.Moving then begin Need(Abs(G.X-F.X-Support)<1E-7,'Planted foot slides');Inc(WalkChecks);end;
  if not A.Moving and not B.Moving then begin
    Need((Abs(A.LeftFoot.X-B.LeftFoot.X)<1E-7) and (Abs(A.RightFoot.X-B.RightFoot.X)<1E-7),'Feet walk while stopped');
    Need((Abs(A.LeftFoot.Y-Ground)<1E-7) and (Abs(A.RightFoot.Y-Ground)<1E-7),'Stopped foot is floating');Inc(IdleChecks);
  end;
end;
procedure CheckBodyMotion(Score:TRunnerActionPlan);
var K,I:Integer;S:TRunSection;H:TRunHit;P,Q:TRunPose;B,After:TRunBossPose;T,Finish,HeroMin,HeroMax,BossMin,BossMax:Double;
begin
  P:=Score.HeroAt(Score.Goal+1.0);Q:=Score.HeroAt(Score.Goal);Need(P.X>Q.X+0.7,'Boss motion suppresses the goal runout');
  for K:=0 to High(Score.Sections) do begin S:=Score.Sections[K];
    if S.Mode<>rmBoss then begin T:=S.Start+0.05;while T<Min(S.Finish-0.01,S.Start+2) do begin CheckStride(Score,T,False);T:=T+0.0125;end;Continue;end;
    Finish:=S.Finish;for I:=S.First to S.Last do if Score.Hits[I].Kind=rhFinish then Finish:=Score.Hits[I].Time;
    T:=S.Start+0.60;HeroMin:=1E30;HeroMax:=-1E30;BossMin:=1E30;BossMax:=-1E30;
    while T<Finish-0.002 do begin
      P:=Score.HeroAt(T);Q:=Score.HeroAt(T+0.001);B:=Score.BossAt(T);After:=Score.BossAt(T+0.001);
      HeroMin:=Min(HeroMin,P.X);HeroMax:=Max(HeroMax,P.X);BossMin:=Min(BossMin,B.X);BossMax:=Max(BossMax,B.X);
      Need((P.X>=S.X-0.36) and (P.X<=S.X+1.32) and (B.X>=S.X-0.33) and (B.X<=S.X+1.29),'Body leaves boss arena');Need(B.X-P.X>0.14,'Boss and hero bodies overlap');
      if (Q.X-P.X)*(After.X-B.X)<-1E-9 then Inc(OpposingChecks);
      CheckStride(Score,T,False);CheckStride(Score,T,True);T:=T+0.025;
    end;
    Need((HeroMax-HeroMin>0.10) and (BossMax-BossMin>0.15),'One side remains static');
    for I:=S.First to S.Last do begin H:=Score.Hits[I];P:=Score.HeroAt(H.Time);B:=Score.BossAt(H.Time);
      if H.Kind in [rhBossCut,rhFinish] then begin Need(Abs(B.X-0.027*2.9-H.X)<0.004,'Moving boss armor misses blade');Inc(BodyContactChecks);end;
      if H.Kind=rhBossCut then begin After:=Score.BossAt(H.Time+0.15);Need(After.X>B.X+0.05,'Boss is not knocked back');end;
      if H.Kind=rhHurt then begin Need(Abs(H.X-P.X-0.025)<1E-7,'Enemy hit misses moving hero');Q:=Score.HeroAt(H.Time+0.15);Need(Q.X<P.X-0.05,'Hero is not pushed back');Inc(BodyContactChecks);end;
    end;
  end;
end;

procedure Legacy;
var Version:Integer;A:TJSONArray;J:TJSONObject;R:TRhythmPlanRef;
  procedure AddStep(Time,Y,Takeoff,StartY,Velocity,Strength:Double);
  begin J:=TJSONObject.Create;A.AddElement(J);J.AddPair('time',TJSONNumber.Create(Time));J.AddPair('y',TJSONNumber.Create(Y));J.AddPair('takeoff',TJSONNumber.Create(Takeoff));J.AddPair('startY',TJSONNumber.Create(StartY));J.AddPair('velocity',TJSONNumber.Create(Velocity));J.AddPair('strength',TJSONNumber.Create(Strength));end;
begin
  Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.Key:=THashSHA2.GetHashString('legacy-native');Audio.SourceRevision:=Revision;Audio.Duration:=1;Audio.Sensitivity:=50;
  Audio.SoundEnd:=1;SetLength(Audio.Hits,1);Audio.Hits[0].Time:=0.7;Audio.Hits[0].Strength:=0.8;
  for Version:=1 to 5 do begin
    R:=NewPlanRef(Audio.Key,50,0,rsRunner);R.Version:=Version;R.Key:=THashSHA2.GetHashString('runner-v'+IntToStr(Version)+'|'+Audio.Key+'|50|0');R.SourceRevision:=Revision;
    Root:=TJSONObject.Create;
    try Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','runner');Root.AddPair('version',TJSONNumber.Create(Version));Root.AddPair('key',R.Key);Root.AddPair('source',R.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(50));Root.AddPair('direction',TJSONNumber.Create(0));AddPreparedAudio(Root,Audio);
      Root.AddPair('goal',TJSONNumber.Create(1));Root.AddPair('excluded',TJSONNumber.Create(0));A:=TJSONArray.Create;Root.AddPair('steps',A);AddStep(0,0.72,0,0.72,0,0);AddStep(0.7,0.665,0.045,0.72,-0.055/0.655-0.5*3.8*0.655,0.8);AddStep(1,0.665,0.745,0.665,-0.5*3.8*0.255,0.8);
      A:=TJSONArray.Create;Root.AddPair('pulses',A);J:=TJSONObject.Create;A.AddElement(J);J.AddPair('time',TJSONNumber.Create(0.7));J.AddPair('strength',TJSONNumber.Create(0.8));J.AddPair('step',TJSONNumber.Create(1));Root.AddPair('setPiecesVersion',TJSONNumber.Create(1));Root.AddPair('setPieces',TJSONArray.Create);Root.AddPair('encounterPolicy','landing-rows-v1');Root.AddPair('encounters',TJSONArray.Create);Root.AddPair('swordRuns',TJSONArray.Create);Root.AddPair('cuts',TJSONArray.Create);Root.AddPair('strikes',TJSONArray.Create);Root.AddPair('blades',TJSONArray.Create);
      if Version=4 then Root.AddPair('swordPolicy','flat-blade-contact-v1') else Root.AddPair('swordPolicy','rapid-armor-v2');WritePreparedData(Root,R);
    finally Root.Free;end;
    Cold:=TRunnerPlan.LoadAudioMetadata(R,Source,0);Restored:=TRunnerPlan.Load(R,Cold,0);Need((Restored.RecipeVersion=Version) and (Restored.Action=nil),'Legacy reader changed');
    Need((Restored.PulseCount=1) and (Abs(Restored.PositionAt(0.7).Y-0.665)<1E-8),'Legacy moving score changed');
    State:=TRhythmSettings.Defaults;State.Style:=rsRunner;State.Music:=Source;State.Plan:=R;Need(TRhythmSettings.TryJSON(State.ToJSON,Loaded) and (Loaded.Plan.Key=R.Key),'Legacy settings dropped saved plan');
    FreeAndNil(Restored);FreeAndNil(Cold);
  end;FreeAndNil(Audio);
end;
begin
  try
    OutDir:=TPath.Combine(ExtractFileDir(ParamStr(0)),'ABCFrames');ForceDirectories(OutDir);Source:=TPath.Combine(OutDir,'runner-native.identity');TFile.WriteAllText(Source,'fixed native Runner test source; no PCM',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    ConfigureRhythmProduct('SYNC_RhythmRunner','Runner ABC native',rsRunner);Need(StylePlanVersion(rsRunner)=7,'v7 missing');Need((StylePlanVersion(rsBall)=6) and (StylePlanVersion(rsBreakout)=10),'Other style versions changed');Legacy;LegacyABC6;
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);Checks:=0;FloorChecks:=0;TimingChecks:=0;WalkChecks:=0;IdleChecks:=0;OpposingChecks:=0;BodyContactChecks:=0;MaxErr:=0;Contacts:=0;Moving:=0;Falls:=0;Both:=0;Bosses:=0;FillChar(Seen,SizeOf(Seen),0);
    for C:=0 to 15 do begin Writeln('fixture ',C);
      Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Key:=THashSHA2.GetHashString('runner-abc-native-'+IntToStr(C));Audio.Sensitivity:=50;
      Duration:=96;case C of 0:Duration:=0.1;1:Duration:=1;2:Duration:=8;3:Duration:=30;6:Duration:=3000;7:Duration:=0.5;8:Duration:=3;end;
      Audio.Duration:=Duration;SetLength(Audio.Envelope,Ceil(Duration*100));for I:=0 to High(Audio.Envelope) do Audio.Envelope[I]:=0.5;
      SetLength(Audio.Hits,20000);Time:=0.18;N:=0;while (Time<Duration-0.05) and (N<20000) do begin
        Audio.Hits[N].Time:=Time;Audio.Hits[N].Strength:=0.3+0.14*(N mod 6);Inc(N);Gap:=0.70;
        case C of 3:Gap:=0.20;4:Gap:=0.70;5,6,9,10,11,12:if (Trunc(Time/12) mod 2)=1 then Gap:=0.20;
          8:Gap:=0.001;13:Gap:=0.44+0.055*Sin(N*1.7);14:Gap:=0.008;15:Gap:=0.50;end;Time:=Time+Gap;
      end;SetLength(Audio.Hits,N);Audio.UpdateSoundBounds;Frequency:=0;if C in [5,6,9,10,11,12] then Frequency:=100;if C=10 then Frequency:=50;Audio.SetBossFrequency(Frequency);
      Plan:=TRunnerPlan.Build(Audio);Score:=Plan.Action;Need(Score<>nil,'No ABC plan');Score.Validate;CheckBodyMotion(Score);
      Pad:=Score.Pads[High(Score.Pads)];Need((Pad.Fall<0) and (Pad.Right>=Score.WorldAt(Score.Goal)+1.8),'Exit floor does not support the visible runout');
      if C in [5,6,9,10,11,12] then begin Need((Score.ModeCount(rmJump)>0) and (Score.ModeCount(rmSword)>0),'Mixed fixture lacks A/B');Inc(Both);end;
      if Frequency=0 then Need(Score.ModeCount(rmBoss)=0,'Boss zero ignored');Bosses:=Bosses+Score.ModeCount(rmBoss);
      for K:=0 to High(Score.Sections) do if Score.Sections[K].Mode=rmBoss then begin
        Time:=-1;for I:=Score.Sections[K].First to Score.Sections[K].Last do if Score.Hits[I].Kind=rhFinish then Time:=Score.Hits[I].Time;
        Need(Time>=0,'Boss final impact missing');
        for I:=Score.Sections[K].First to Score.Sections[K].Last do if Score.Hits[I].Time>Time then Need(Score.Hits[I].Kind=rhPulse,'Boss attacks after defeat');
      end;
      if C=13 then Need(Length(Score.Sections)<=20,'Phrase chatter');
      for I:=0 to High(Score.Hits) do begin H:=Score.Hits[I];Need(H.Time=Audio.Hits[H.Source].Time,'Raw clock changed');Seen[H.Kind]:=True;CheckContactTiming(Score,I);
        if H.Kind in [rhSword,rhBossCut,rhParry,rhFinish] then begin Need(Score.BladeAt(H.Time,G,Tip),'No blade');Err:=Hypot(Tip.X-H.X,Tip.Y-H.Y);MaxErr:=Max(MaxErr,Err);Need(Err<1E-7,'Contact mismatch');Inc(Contacts);end;
        if H.Kind=rhDodge then begin Pose:=Score.HeroAt(H.Time);Need(Pose.Airborne and (Pose.Y<RA_GROUND-0.12),'Dodge failed');end;
        if H.Kind in [rhParry,rhDodge,rhHurt] then begin Need(Score.EnemyBladeAt(H.Time,G,Tip),'Enemy blade missing');Need(Hypot(Tip.X-H.X,Tip.Y-H.Y)<1E-7,'Enemy blade contact mismatch');end;
      end;
      for I:=0 to High(Score.Jumps) do begin Jump:=Score.Jumps[I];
        if Jump.Source>=0 then Need(Jump.Time=Audio.Hits[Jump.Source].Time,'Jump landing moved off source clock');
        Need(Jump.Time-Jump.Takeoff>=0.32,'Jump flight too short');
        Pad:=Score.PadAt(Jump.Pad,Jump.Time);Pose:=Score.HeroAt(Jump.Time);Err:=Abs(Pose.Y-Pad.Y);MaxErr:=Max(MaxErr,Err);Need(Err<1E-7,'Foot missed moving pad');
        O:=Score.PadOffset(Jump.Pad,Jump.Takeoff-0.18);if (Score.Pads[Jump.Pad].AX<>0) or (Score.Pads[Jump.Pad].AY<>0) then begin Need(Hypot(O.X,O.Y)>1E-7,'Destination does not move before takeoff');Inc(Moving);end;
        Pad:=Score.PadAt(Jump.FromPad,Jump.Takeoff+0.50);Need(Pad.Y>Score.Pads[Jump.FromPad].Y+0.30,'Departed pad did not fall');Inc(Falls);
        for J:=0 to 32 do begin Time:=Jump.Takeoff+(Jump.Time-Jump.Takeoff)*J/32;Pose:=Score.HeroAt(Time);Need(not IsNan(Pose.X) and not IsNan(Pose.Y) and not IsInfinite(Pose.Y),'Invalid flight');
          if (J>0) and (J<32) then for K:=Max(0,Jump.FromPad-1) to Min(High(Score.Pads),Jump.Pad+1) do begin Pad:=Score.PadAt(K,Time);if (Pose.X+0.009>=Pad.Left) and (Pose.X-0.009<=Pad.Right) then begin Need(Pose.Y<=Pad.Y+0.001,'Feet penetrate a moving floor');Inc(FloorChecks);end;end;
        end;
      end;
      for I:=1 to High(Score.Sections) do begin Time:=Score.Sections[I].Start;Pose:=Score.HeroAt(Time-1E-7);Other:=Score.HeroAt(Time);Need(Hypot(Pose.X-Other.X,Pose.Y-Other.Y)<1E-5,'ABC boundary teleports');
        if (I<High(Score.Sections)) and (Score.Sections[I-1].Mode<>rmBoss) and (Score.Sections[I].Mode<>rmBoss) and (Score.Sections[I+1].Mode<>rmBoss) then
          Need(Score.Sections[I].Finish-Time>=3-1E-7,'Per-note A/B switching');
      end;
      Root:=Score.ToJSON;try JSON:=Root.ToJSON;Again:=TRunnerActionPlan.FromJSON(Root,Audio);try CopyRoot:=Again.ToJSON;try if CopyRoot.ToJSON<>JSON then begin TFile.WriteAllText(TPath.Combine(OutDir,'expected.json'),JSON,TEncoding.UTF8);TFile.WriteAllText(TPath.Combine(OutDir,'actual.json'),CopyRoot.ToJSON,TEncoding.UTF8);end;Need(CopyRoot.ToJSON=JSON,'JSON changes score');finally CopyRoot.Free;end;
        if C=6 then begin K:=0;while (K<Length(Again.Sections)) and (Again.Sections[K].Mode<>rmBoss) do Inc(K);
          Need(K<Length(Again.Sections),'Long-song boss fixture missing');Dec(Again.Sections[K].Last);Rejected:=False;
          try Again.Validate;except Rejected:=True;end;Need(Rejected,'Omitted boundary accent accepted');
        end;
      finally Again.Free;end;finally Root.Free;end;
      Ref:=NewPlanRef(Audio.Key,50,0,rsRunner,Frequency+1);Ref.SourceRevision:=Revision;Plan.Save(Ref,Audio);
      State:=TRhythmSettings.Defaults;State.Style:=rsRunner;State.Music:=Source;State.Plan:=Ref;State.BossFrequency:=Frequency;Need(TRhythmSettings.TryJSON(State.ToJSON,Loaded) and (Loaded.Plan.Key=Ref.Key),'Settings drops ABC');
      Cold:=TRunnerPlan.LoadAudioMetadata(Ref,Source,0);Need((Length(Cold.PCM)=0) and (Length(Cold.Envelope)=0),'Cold restore needs PCM');Restored:=TRunnerPlan.Load(Ref,Cold,0);Pose:=Restored.Action.HeroAt(Score.Goal/2);O.X:=Restored.PositionAt(Score.Goal/2).X;O.Y:=Restored.PositionAt(Score.Goal/2).Y;Need(Hypot(Pose.X-O.X,Pose.Y-O.Y)<1E-7,'PositionAt does not forward the v6 score');Root:=Restored.Action.ToJSON;try Need(Root.ToJSON=JSON,'Cold changes score');finally Root.Free;end;
      BadRef:=Ref;BadRef.Digest:=StringOfChar('0',64);Rejected:=False;try BadPlan:=TRunnerPlan.Load(BadRef,Cold,0);except Rejected:=True;end;FreeAndNil(BadPlan);Need(Rejected,'Invalid digest accepted');
      Scene:=TRunnerAnimation.Create;Scene.Audio:=Cold;Scene.SetReference(Ref);Render:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));
      if C in [3,5,6,9] then CheckEnemyEntry(Score,Render);
      if C in [5,9] then begin FillChar(Snapped,SizeOf(Snapped),0);for I:=0 to High(Score.Hits) do begin H:=Score.Hits[I];if (H.Kind in [rhLand,rhSword,rhBossCut,rhParry,rhDodge,rhHurt,rhFinish]) and not Snapped[H.Kind] then begin Snap(IntToStr(C)+'-'+IntToStr(Ord(H.Kind)),H.Time);Snapped[H.Kind]:=True;end;end;end;
      for Backend:=0 to 1 do begin Render.UseD2D:=Backend=1;for I:=0 to 15 do begin Time:=(Score.Goal+1.6)*((I*17) mod 31)/31;Render.Render(Image,Time,0);Need(Scene.Notice='','Scene load');Hash:=ImageHash;Render.Render(Image,Score.Goal-Time,0);Render.Render(Image,Time,0);Need(ImageHash=Hash,'Seek image drift');Inc(Checks);end;end;
      FreeAndNil(Render);FreeAndNil(Restored);FreeAndNil(Cold);FreeAndNil(Plan);FreeAndNil(Audio);
    end;
    for Kind:=rhSword to rhFinish do Need(Seen[Kind],'Missing boss/sword action coverage');Need((Both>=3) and (Bosses>0) and (Moving>0) and (Falls>0),'Coverage incomplete');
    Rejected:=False;Audio:=TRhythmAudio.Create;Audio.Duration:=1;Plan:=TRunnerPlan.Build(Audio);Need((Plan.EndTime=0) and (Plan.PulseCount=0),'Silence creates actions');FreeAndNil(Plan);
    try Plan:=TRunnerPlan.Build(Audio,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;Need(Rejected,'Cancel ignored');
    SetLength(Audio.Hits,100001);Rejected:=False;try Plan:=TRunnerPlan.Build(Audio);except Rejected:=True;end;Need(Rejected,'Source cap ignored');FreeAndNil(Audio);
    Need((WalkChecks>0) and (IdleChecks>0) and (OpposingChecks>0) and (BodyContactChecks>0),'Motion coverage missing');
    Writeln(Format('Runner motion: stance %d / idle %d / opposing %d / body contacts %d',[WalkChecks,IdleChecks,OpposingChecks,BodyContactChecks]));
    TFile.WriteAllText(TPath.Combine(OutDir,'motion-results.txt'),Format('stance=%d idle=%d opposing=%d bodyContacts=%d',[WalkChecks,IdleChecks,OpposingChecks,BodyContactChecks]),TEncoding.UTF8);
    Writeln(Format('Runner ABC PASS: 16 fixtures; legacy 1..6; %d seeks; %d blade contacts; %d moving landings; %d falls; mixed A/B %d; bosses %d; floor samples %d; timing samples %d; max error %.12g',[Checks,Contacts,Moving,Falls,Both,Bosses,FloorChecks,TimingChecks,MaxErr]));
    TFile.WriteAllText(TPath.Combine(OutDir,'results.txt'),Format('fixtures=16 legacy=1..6 seeks=%d contacts=%d moving=%d falls=%d mixed=%d bosses=%d floorSamples=%d timingSamples=%d maxError=%.12g',[Checks,Contacts,Moving,Falls,Both,Bosses,FloorChecks,TimingChecks,MaxErr]),TEncoding.UTF8);
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  PNG.Free;Image.Free;Render.Free;Restored.Free;Plan.Free;Cold.Free;Audio.Free;
end.
