program StepGameSmoke;
{$APPTYPE CONSOLE}
{$POINTERMATH ON}
// Synthetic PCM, absolute hit timing, shared density, saved chart and GDI/D2D rendering.
uses System.SysUtils,System.Classes,System.IOUtils,System.Math,System.Hash,System.JSON,System.Diagnostics,
  Winapi.Windows,Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmAudio,RhythmAudioCache,RhythmOrbitAudio,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmSettings,RhythmPrepare,
  RhythmStepPlan,RhythmStepScene,RhythmScene,RhythmGamePlan,RhythmStyleRegistry,RhythmPreparedData,RhythmOverlay;
var
  Audio,Cold:TRhythmAudio;
  Plan:TStepPlan;
  Worker:TRhythmPrepareThread;
  Renderer:TRhythmRenderer;
  Image:TBitmap;
  Ref:TRhythmPlanRef;
  Folder,Source,Expected:string;
  I,J,Backend,Checks,ChordCount,Different:Integer;
  T,SampleTime:Double;
  Note:TStepNote;

procedure Need(Value:Boolean;const Why:string);
begin
  if not Value then raise Exception.Create(Why);
  Inc(Checks);
end;

function MakePulses(const Path:string):TRhythmAudio;
const PulseSamples=2500;PulseCount=43;Duration=15;
var Samples:TArray<SmallInt>;
  I,J,Start:Integer;T,X,Level:Double;V:SmallInt;
begin
  SetLength(Samples,Duration*RHYTHM_RATE*2);
  T:=0.25;
  for I:=0 to PulseCount-1 do begin
    Start:=Round(T*RHYTHM_RATE)*2;
    Level:=0.10+(I mod 5)*0.21;
    for J:=0 to PulseSamples-1 do begin
      X:=J/RHYTHM_RATE;
      V:=Round(25000*Level*Exp(-X*63)*(0.50*Sin(X*Pi*2*95)+0.35*Sin(X*Pi*2*740)+0.15*Sin(X*Pi*2*3700)));
      Samples[Start+J*2]:=V;
      Samples[Start+J*2+1]:=V;
    end;
    T:=T+0.23+(I mod 7)*0.032;
  end;
  Result:=TRhythmAudio.Create;
  try
    SetLength(Result.PCM,Length(Samples)*SizeOf(SmallInt));
    Move(Samples[0],Result.PCM[0],Length(Result.PCM));
    TFile.WriteAllBytes(Path,Result.PCM);
    Result.Source:=Path;
    Result.SourceRevision:=AudioSourceStamp(Path);
    Result.Key:=THashSHA2.GetHashStringFromFile(Path);
    Result.Sensitivity:=50;
    Result.Detect;
  except
    Result.Free;
    raise;
  end;
end;

procedure CheckDensity;
var Raw,Thin,Dense,Middle,Sparse:TArray<TRhythmHit>;
  Pool:TOrbitCandidatePool;I,J:Integer;Settings,Parsed:TRhythmSettings;S:TRhythmStyle;
  Base,Changed:TRhythmPlanRef;Stats:TOrbitAudioStats;
begin
  Raw:=Audio.Hits;
  Sparse:=SelectAnimationHits(Audio,65,nil);
  WriteLn('Density threshold fixture base=',Length(Raw),' sparse=',Length(Sparse));
  Need((Length(Sparse)>0) and (Length(Sparse)<Length(Raw)),'Right slider reduces source accents');
  SetLength(Thin,Length(Raw) div 3);
  for I:=0 to High(Thin) do Thin[I]:=Raw[I*3];
  Audio.SetSelectedHits(Thin);
  Pool:=TOrbitCandidatePool.Analyze(Audio);
  try
    Dense:=Pool.SelectSpaced(Audio,-100,nil);
    Middle:=Pool.SelectSpaced(Audio,-40,nil);
    Need((Length(Dense)>Length(Thin)) and (Length(Middle)<=Length(Dense)),'Left slider adds spaced source peaks');
    J:=0;
    for I:=0 to High(Dense) do begin
      if I>0 then Need(Dense[I].Time-Dense[I-1].Time>=0.18-1E-10,'Legacy minimum interval');
      if (J<Length(Middle)) and (Dense[I].Time=Middle[J].Time) then Inc(J);
    end;
    Need(J=Length(Middle),'Lower threshold moved or removed an adopted event');
    Cold:=Pool.Select(Audio,-100,Stats);
    try Need(Length(Cold.Hits)>Length(Thin),'Dense mode keeps additional rhythm-game peaks');
    finally FreeAndNil(Cold);end;
  finally
    Pool.Free;
    Audio.ResetSelectedHits;
  end;
  Need(Length(Audio.Hits)=Length(Raw),'Switching density restores source candidates');
  for I:=0 to High(Raw) do Need(Audio.Hits[I].Time=Raw[I].Time,'Base candidate time changed');
  for S:=Low(TRhythmStyle) to High(TRhythmStyle) do begin
    Base:=NewPlanRef(Audio.Key,50,0,S,StyleVariant(S,50,100,20));
    Changed:=NewPlanRef(Audio.Key,50,0,S,StyleVariant(S,50,100,80),AudioDensityKey(S,80));
    Need(Base.Key<>Changed.Key,'Different density shares prepared key');
    Settings:=TRhythmSettings.Defaults;
    Settings.Style:=S;
    Settings.BossFrequency:=100;
    Settings.GameThreshold:=80;
    Changed.Digest:=StringOfChar('a',64);
    Settings.Plan:=Changed;
    Need(TRhythmSettings.TryJSON(Settings.ToJSON,Parsed) and (Parsed.Plan.Key=Changed.Key) and
      (Parsed.GameThreshold=80),'Density and plan JSON roundtrip');
    Settings.GameThreshold:=20;
    Need(TRhythmSettings.TryJSON(Settings.ToJSON,Parsed) and (Parsed.Plan.Key=''),'Stale density plan accepted');
  end;
  Need(TRhythmSettings.TryJSON('{"schema":1,"style":"runner","gameThreshold":-80}',Parsed) and
    (Parsed.Style=rsJumpAdventure) and (Parsed.GameThreshold=20),'Hidden legacy setting changed migrated density');
  Need(TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","gameThreshold":-80}',Parsed) and
    (Parsed.GameThreshold=-80),'Legacy game setting was lost');
  WriteLn('Density fixture base=',Length(Raw),' sparse=',Length(Sparse),' thinned=',Length(Thin),' restored-with-extras=',Length(Dense));
end;

function ImageHash:string;
var Stream:TMemoryStream;Hash:THashSHA2;
begin
  Stream:=TMemoryStream.Create;
  try
    Image.SaveToStream(Stream);
    Hash:=THashSHA2.Create;
    Hash.Update(Stream.Memory^,Stream.Size);
    Result:=Hash.HashAsString;
  finally
    Stream.Free;
  end;
end;

procedure SaveImage(const Name:string;Width,Height:Integer;Time:Double);
var PNG:TPngImage;
begin
  Image.SetSize(Width,Height);
  Renderer.Render(Image,Cold,Time,0);
  if Renderer.OutputHasAlpha then OverlayPreview(Image);
  PNG:=TPngImage.Create;
  try
    PNG.Assign(Image);
    PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));
  finally
    PNG.Free;
  end;
end;

procedure CheckJudgmentPixels(Time:Double);
var Player,Lane,X,Y:Integer;DeckWidth,LaneWidth,NoteHeight:Double;Note:TStepNote;
  Before,After:TColor;
begin
  Image.SetSize(1280,720);
  Note:=Plan.Notes[Plan.CountThrough(Time)-1];
  DeckWidth:=Min(Image.Height*0.666,Image.Width*0.386);
  LaneWidth:=DeckWidth/STEP_LANE_COUNT;
  NoteHeight:=Min(LaneWidth*0.30,Image.Height*0.036);
  Y:=Round(Image.Height*0.266+NoteHeight*0.52);
  for Player:=0 to 1 do begin
    Lane:=0;
    while Note.Lanes[Player] and (1 shl Lane)=0 do Inc(Lane);
    X:=Round(Image.Width*(0.266+Player*0.468)-DeckWidth*0.5+(Lane+0.5)*LaneWidth);
    Renderer.Render(Image,Cold,Time-0.002,0);
    Before:=Image.Canvas.Pixels[X,Y];
    Renderer.Render(Image,Cold,Time,0);
    After:=Image.Canvas.Pixels[X,Y];
    Need((After=$00F8F0E9) and (Before<>After),'Judgment flash does not meet the source hit');
  end;
end;

procedure MeasureFrames(const Chart:TRhythmPlanRef;Fixture:TRhythmAudio;Start,Window:Double);
const Frames=120;
var B,K,Eq:Integer;Watch:TStopwatch;
begin
  if GetEnvironmentVariable('RHYTHM_STEP_BENCHMARK')<>'1' then Exit;
  Image.SetSize(1920,1080);
  for Eq:=0 to 1 do begin
    Renderer.ConfigureStyle(rsStepGame,Chart,100,Eq);
    for B:=0 to 1 do begin
      Renderer.UseD2D:=B=1;
      for K:=0 to 11 do Renderer.Render(Image,Fixture,Start+Window*K/Frames,0);
      GdiFlush;
      Watch:=TStopwatch.StartNew;
      for K:=0 to Frames-1 do Renderer.Render(Image,Fixture,Start+Window*K/Frames,0);
      GdiFlush;
      Watch.Stop;
      WriteLn('1920x1080 backend=',B,' EQ=',Eq,' ms/frame=',Watch.Elapsed.TotalMilliseconds/Frames:0:3);
    end;
  end;
end;

procedure CheckAlpha;
var X,Y,Clear,Partial,Opaque:Integer;Row:PByte;Valid:Boolean;
begin
  Clear:=0;Partial:=0;Opaque:=0;Valid:=True;
  for Y:=0 to Image.Height-1 do begin
    Row:=Image.ScanLine[Y];
    for X:=0 to Image.Width-1 do begin
      if (Row[0]>Row[3]) or (Row[1]>Row[3]) or (Row[2]>Row[3]) then Valid:=False;
      case Row[3] of
        0:Inc(Clear);
        255:Inc(Opaque);
      else
        Inc(Partial);
      end;
      Inc(Row,4);
    end;
  end;
  Need(Renderer.OutputHasAlpha and Valid and (Clear>Image.Width*Image.Height div 3) and
    (Partial>1000) and (Opaque>100),'Missing transparent margins, deck tint or solid notes');
  Row:=Image.ScanLine[Image.Height div 2];
  Need(PCardinal(Row+Image.Width div 2*4)^=0,'MV center should stay clear');
end;

function PixelAt(X,Y:Integer):Cardinal;
begin
  Result:=PCardinal(PByte(Image.ScanLine[Y])+X*4)^;
end;

procedure CheckPatterns;
const Times:array[0..23] of Double=(0.55,1.10,1.19,1.33,2.1,2.33,2.54,2.8,
  3.5,3.71,3.99,4.23,5.0,5.22,5.49,5.73,6.02,6.21,6.53,7.8,8.01,8.61,10.0,12.3);
  ExpectedKinds:array[0..23] of TStepKind=(stTap,stRoll,stRoll,stRollEnd,
    stSweep,stSweep,stSweep,stSweepEnd,stSweep,stSweep,stSweep,stSweepEnd,
    stSweep,stSweep,stSweep,stSweep,stSweep,stSweep,stSweepEnd,stSlide,stSlideEnd,stChord,stHold,stTap);
  SweepLanes:array[4..18] of Integer=(0,1,2,3,3,2,1,0,0,1,2,3,2,1,0);
var Input,Restored:TRhythmAudio;Chart,Loaded:TStepPlan;Saved:TRhythmPlanRef;K,B,N,X,Y,Player:Integer;
  PCM:PSmallInt;Sample:SmallInt;Time,ReleaseAt,LaneWidth:Double;Hash:string;Event:TStepNote;
  PNG:TPngImage;Unshifted,Before:Cardinal;
begin
  Input:=TRhythmAudio.Create;Restored:=nil;Chart:=nil;Loaded:=nil;
  try
    Input.Source:=Audio.Source;Input.SourceRevision:=Audio.SourceRevision;
    Input.Key:=THashSHA2.GetHashString('step-patterns-fixture');Input.Sensitivity:=50;
    Input.Duration:=13;Input.SoundEnd:=13;
    SetLength(Input.PCM,13*RHYTHM_RATE*4);PCM:=PSmallInt(Input.PCM);
    for K:=10*RHYTHM_RATE to Round(11.33*RHYTHM_RATE)-1 do begin
      Time:=K/RHYTHM_RATE;
      Sample:=Round(10000*Sin(2*Pi*220*Time));
      PCM[K*2]:=Sample;PCM[K*2+1]:=Sample;
    end;
    SetLength(Input.Hits,Length(Times));
    for K:=Low(Times) to High(Times) do begin
      Input.Hits[K].Time:=Times[K];Input.Hits[K].Strength:=0.46;
    end;
    Input.Hits[21].Strength:=0.94;
    Chart:=TStepPlan.Build(Input,20);
    Saved:=NewPlanRef(Input.Key,50,0,rsStepGame,121);
    Saved.SourceRevision:=Input.SourceRevision;
    Chart.Save(Saved,Input);
    Restored:=TStepPlan.LoadAudioMetadata(Saved,Input.Source,0);
    Loaded:=TStepPlan.Load(Saved,Restored,0);
    Need((Length(Restored.PCM)=0) and (Loaded.Count=Length(Times)),'Pattern chart PCM-free restoration');
    for K:=Low(Times) to High(Times) do begin
      Event:=Loaded.Notes[K];
      Need((Event.Time=Times[K]) and (Event.Kind=ExpectedKinds[K]),'Wrong event time or pattern at '+IntToStr(K));
      Need((Loaded.CountThrough(Event.Time-1E-8)=K) and (Loaded.CountThrough(Event.Time)=K+1),'Pattern hit boundary');
      if K in [1..3] then Need((Event.Lanes[0]=Loaded.Notes[1].Lanes[0]) and
        (Event.Lanes[1]=Loaded.Notes[1].Lanes[1]),'Roll changed lanes');
      if K in [4..18] then Need((StepLane(Event.Lanes[0])=SweepLanes[K]) and
        (StepLane(Event.Lanes[1])=3-SweepLanes[K]),'Sweep sequence');
    end;
    ReleaseAt:=Loaded.Notes[22].EndTime;
    Need((ReleaseAt>=11.26) and (ReleaseAt<=11.33),'Hold release escaped the sustained sound');
    Renderer.ConfigureStyle(rsStepGame,Saved,100,0);
    Image.SetSize(960,540);
    for B:=0 to 1 do begin
      Renderer.UseD2D:=B=1;
      Renderer.Render(Image,Restored,Times[0]-0.002,0);
      LaneWidth:=540*0.666/STEP_LANE_COUNT;
      for Player:=0 to 1 do
        for K:=0 to STEP_LANE_COUNT do begin
          X:=Round(960*(0.266+Player*0.468)+(K-2)*LaneWidth);
          Need(((PixelAt(X,225) and $FF)>=200) and ((PixelAt(X+1,340) and $FF)>=200),'Lane boundary is too dim or narrow');
        end;
      X:=Round(960*0.266+1.5*LaneWidth);
      Need(((PixelAt(X,186) and $FF)<55) and ((PixelAt(X,186) and $FF)>(PixelAt(X,184) and $FF)),
        'Horizontal guide should be visible but faint');
      X:=Round(960*0.266+(StepLane(Loaded.Notes[0].Lanes[0])-1.5)*LaneWidth);
      Y:=Round(Image.Height*0.49);
      Before:=PixelAt(X,Y);
      Renderer.Render(Image,Restored,Times[0]+0.18,0);
      Need(PixelAt(X,Y)=Before,'Hit sent a moving flash down the lane');
      for N:=0 to 5 do begin
        case N of
          0:Time:=1.19;
          1:Time:=2.46;
          2:Time:=7.9;
          3:Time:=8.61;
          4:Time:=10.65;
        else
          Time:=ReleaseAt;
        end;
        Renderer.Render(Image,Input,Time,0);CheckAlpha;
        Need(Renderer.LastUsedD2D=(B=1),'Wrong backend for the alpha overlay');
        Hash:=ImageHash;
        Renderer.Render(Image,Restored,Time+2.3,0);
        Renderer.Render(Image,Restored,Time,0);
        Need(ImageHash=Hash,'Pattern changed after PCM-free restore or reverse seek');
        if N=5 then begin
          X:=Round(960*0.266+(StepLane(Loaded.Notes[22].Lanes[0])-1.5)*540*0.666/4);
          Y:=Round(540*0.266+540*0.036*0.52);
          Unshifted:=PixelAt(X,Y);
          Renderer.Render(Image,Restored,Time-0.002,0);
          Before:=PixelAt(X,Y);
          Need((Unshifted=$FFE9F0F8) and (Before<>Unshifted),'Hold release did not flash at its planned time');
          Renderer.Render(Image,Restored,Time,0,'',1,13,-9);
          Need((PixelAt(X+13,Y-9)=Unshifted) and (PixelAt(0,0)=0),'Position transform broke the overlay');
          Renderer.Render(Image,Restored,Time,0);
        end;
        if B=1 then begin
          OverlayPreview(Image);
          PNG:=TPngImage.Create;
          try
            PNG.Assign(Image);
            PNG.SaveToFile(TPath.Combine(Folder,'ddr-pattern-'+IntToStr(N)+'.png'));
          finally
            PNG.Free;
          end;
        end;
      end;
    end;
  finally
    Loaded.Free;Chart.Free;Restored.Free;Input.Free;
  end;
end;

procedure CheckLongChart;
const Notes=100000;Gap=0.029;
var Input,Restored:TRhythmAudio;Chart:TStepPlan;Saved:TRhythmPlanRef;K,B:Integer;
  Time:Double;Hash:string;
begin
  Input:=TRhythmAudio.Create;Chart:=nil;Restored:=nil;
  try
    Input.Source:=Audio.Source;Input.SourceRevision:=Audio.SourceRevision;
    Input.Key:=THashSHA2.GetHashString('step-long-dense-fixture');Input.Sensitivity:=50;
    Input.Duration:=3000;Input.SoundEnd:=3000;
    SetLength(Input.Hits,Notes);
    for K:=0 to Notes-1 do begin
      Input.Hits[K].Time:=0.5+K*Gap;
      Input.Hits[K].Strength:=0.52;
    end;
    Chart:=TStepPlan.Build(Input,-80);
    Need((Chart.Count=Notes) and Chart.IsRoll(0) and (Chart.Notes[6].Kind=stSweep),'Dense long chart lost pattern variation');
    Time:=Chart.Notes[Notes-80].Time;
    Need(Chart.CountThrough(Time)=Notes-79,'Long chart seek boundary');
    Need(Chart.CountThrough(Time+STEP_LOOKAHEAD)-Chart.CountThrough(Time)=56,'Dense lookahead range');
    Saved:=NewPlanRef(Input.Key,50,0,rsStepGame,21);
    Saved.SourceRevision:=Input.SourceRevision;
    Chart.Save(Saved,Input);
    Restored:=TStepPlan.LoadAudioMetadata(Saved,Input.Source,0);
    Renderer.ConfigureStyle(rsStepGame,Saved,100,0);
    Image.SetSize(960,540);
    for B:=0 to 1 do begin
      Renderer.UseD2D:=B=1;
      Renderer.Render(Image,Restored,Time,0);
      CheckAlpha;
      Hash:=ImageHash;
      Renderer.Render(Image,Restored,0,0);
      Renderer.Render(Image,Restored,Time,0);
      Need(ImageHash=Hash,'Dense long chart changed after seek');
    end;
    WriteLn('Dense chart PASS notes=',Notes,' duration=',Input.Duration:0:0);
  finally
    Restored.Free;Chart.Free;Input.Free;
  end;
end;

procedure CheckRolls;
var Input,Peaks,Dense,Restored:TRhythmAudio;Pool:TOrbitCandidatePool;Stats:TOrbitAudioStats;
  Step:TStepPlan;Game:TGamePlan;Job:TRhythmPrepareThread;Saved,Legacy:TRhythmPlanRef;
  Style:TRhythmStyle;Path,Policy,FrameHash:string;Samples:PSmallInt;Seed:Cardinal;I,J,Added,Rolls,ToneBytes:Integer;
  Time,Value,ShowAt:Double;Sample:SmallInt;N:TStepNote;PNG:TPngImage;
  Root:TJSONObject;Row:TJSONArray;Settings,Parsed:TRhythmSettings;
begin
  Input:=TRhythmAudio.Create;Peaks:=nil;Dense:=nil;
  try
    SetLength(Input.PCM,4*RHYTHM_RATE*4);
    Samples:=PSmallInt(Input.PCM);Seed:=17;
    for I:=0 to 4*RHYTHM_RATE-1 do begin
      Time:=I/RHYTHM_RATE;
      Seed:=Cardinal((UInt64(Seed)*1664525+1013904223) and $FFFFFFFF);
      Value:=((Seed shr 16)/65535.0-0.5)*0.09;
      if (Time>=0.64) and (Time<2.36) then
        Value:=0.22*Sin(2*Pi*220*Time)+0.08*Sin(2*Pi*440*Time);
      Sample:=Round(Value*32767);Samples[I*2]:=Sample;Samples[I*2+1]:=Sample;
    end;
    Path:=TPath.Combine(Folder,'hold-with-noise.pcm');
    TFile.WriteAllBytes(Path,Input.PCM);
    Input.Source:=Path;Input.SourceRevision:=AudioSourceStamp(Path);
    Input.Key:=THashSHA2.GetHashStringFromFile(Path);Input.Sensitivity:=50;Input.Detect;
    Pool:=TOrbitCandidatePool.Analyze(Input);
    try Peaks:=Pool.Select(Input,-80,Stats);finally Pool.Free;end;
    Dense:=PrepareOrbitAudio(Input,-34,Stats);
    Need(Stats.RollTicks=0,'Rolls start below the high-sensitivity setting');
    FreeAndNil(Dense);
    Dense:=PrepareOrbitAudio(Input,-80,Stats);
    Need(Stats.RollTicks>=5,'Sustained tone produced no roll');
    J:=0;Added:=0;
    for I:=0 to High(Dense.Hits) do begin
      if (J<Length(Peaks.Hits)) and (Dense.Hits[I].Time=Peaks.Hits[J].Time) then begin Inc(J);Continue;end;
      Need((Dense.Hits[I].Time>0.64) and (Dense.Hits[I].Time<2.36),'Roll tick escaped into noise');
      Inc(Added);
    end;
    Need((Added=Stats.RollTicks) and (J=Length(Peaks.Hits)),'Roll moved existing peaks');
    for Style:=rsRhythmGame to rsStepGame do begin
      Job:=TRhythmPrepareThread.Create(Path,50,0,Style,False,Input,2,StyleVariant(Style,50,100,-80),-80);
      Input:=nil;Job.Start;Job.WaitFor;
      try Need(Job.Error='',Job.Error);Input:=Job.TakeAudio;Saved:=Job.Plan;finally Job.Free;end;
      Restored:=LoadStyleAudio(Style,Saved,Path,0);
      try
        Need(Length(Restored.PCM)=0,'Roll restore needs PCM');
        Rolls:=0;ShowAt:=0;
        if Style=rsStepGame then begin
          Step:=TStepPlan.Load(Saved,Restored,0);
          try
            Need(Step.Count=Length(Peaks.Hits),'DDR added synthetic peak times');
            for I:=0 to Step.Count-1 do begin
              N:=Step.Notes[I];
              Need(N.Time=Peaks.Hits[I].Time,'DDR peak time changed');
            end;
            ShowAt:=1.5;
          finally Step.Free;end;
        end else begin
          Game:=TGamePlan.Load(Saved,Restored,0);
          try
            for I:=0 to Game.Count-1 do if Game.Orbit.IsRoll(I) then begin
              Inc(Rolls);
              Time:=Game.Orbit.Taps[I].Time;
              if Abs(Time-1.5)<Abs(ShowAt-1.5) then ShowAt:=Time;
            end;
          finally Game.Free;end;
        end;
        if Style=rsRhythmGame then Need(Rolls>=5,'Saved chart lost roll classification');
        Renderer.ConfigureStyle(Style,Saved,100,0);
        Renderer.UseD2D:=False;
        Image.SetSize(960,540);Renderer.Render(Image,Restored,ShowAt,0);
        FrameHash:=ImageHash;
        Renderer.Render(Image,Restored,ShowAt+0.6,0);
        Renderer.Render(Image,Restored,ShowAt,0);
        Need(ImageHash=FrameHash,'Roll seek changed the GDI frame');
        Renderer.UseD2D:=True;
        Image.SetSize(960,540);Renderer.Render(Image,Restored,ShowAt,0);
        Need(Renderer.LastUsedD2D,'Roll preview lost D2D');
        PNG:=TPngImage.Create;
        try
          PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,StyleId(Style)+'-roll.png'));
        finally PNG.Free;end;
        if Style=rsStepGame then MeasureFrames(Saved,Restored,0.8,1.3);
      finally Restored.Free;end;

      // 旧キー・旧policyと旧版の列数で保存したファイルを新readerで開く。
      Legacy:=Saved;Dec(Legacy.Version);
      Legacy.Key:=THashSHA2.GetHashString(Format('%s-v%d|%s|50|0|variant=%d',
        [StyleId(Style),Legacy.Version,Legacy.SourceKey,Legacy.Variant]));
      if Style=rsStepGame then Policy:='prism-step-v2' else Policy:='planet-orbit-v3';
      Root:=ReadPreparedData(Saved,Style,0);
      try
        Root.RemovePair('version').Free;Root.AddPair('version',TJSONNumber.Create(Legacy.Version));
        Root.RemovePair('key').Free;Root.AddPair('key',Legacy.Key);
        Root.RemovePair('policy').Free;Root.AddPair('policy',Policy);
        if Style=rsStepGame then
          for I:=0 to Root.GetValue<TJSONArray>('notes').Count-1 do begin
            Row:=Root.GetValue<TJSONArray>('notes').Items[I] as TJSONArray;
            Row.Remove(5).Free;Row.Remove(4).Free;
          end;
        WritePreparedData(Root,Legacy);
      finally Root.Free;end;
      Settings:=TRhythmSettings.Defaults;Settings.Style:=Style;Settings.GameThreshold:=-80;Settings.Plan:=Legacy;
      Need(TRhythmSettings.TryJSON(Settings.ToJSON,Parsed) and (Parsed.Plan.Key=Legacy.Key),'Old settings lost saved chart');
      Restored:=LoadStyleAudio(Style,Legacy,Path,0);
      try
        if Style=rsStepGame then begin
          Step:=TStepPlan.Load(Legacy,Restored,0);
          try Need((Step.Version=2) and (Step.Count=Length(Peaks.Hits)),'Old 4-lane chart migration');finally Step.Free;end;
        end else begin
          Game:=TGamePlan.Load(Legacy,Restored,0);
          try Need((Game.Count>=5) and not Game.Orbit.IsRoll(3),'Old orbit chart migration');finally Game.Free;end;
        end;
      finally Restored.Free;end;
    end;
    FreeAndNil(Dense);
    ToneBytes:=Round(1.72*RHYTHM_RATE)*4;
    Move(Input.PCM[Round(0.64*RHYTHM_RATE)*4],Input.PCM[0],ToneBytes);
    FillChar(Input.PCM[ToneBytes],Length(Input.PCM)-ToneBytes,0);
    Input.Detect;
    Dense:=PrepareOrbitAudio(Input,-80,Stats);
    Need(Stats.RollTicks>=5,'Leading sustained tone was lost before trailing silence');
    WriteLn('Sustained roll PASS inserted=',Added,' isolated from noise; both saved styles restored');
  finally
    Dense.Free;Peaks.Free;Input.Free;
  end;
end;

begin
  Audio:=nil;Cold:=nil;Plan:=nil;Worker:=nil;Renderer:=nil;Image:=nil;
  Checks:=0;ChordCount:=0;Different:=0;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');
    ForceDirectories(Folder);
    Source:=TPath.Combine(Folder,'step-pulses.pcm');
    ConfigureRhythmProduct('SYNC_RhythmGame','Step native test',rsStepGame);
    Audio:=MakePulses(Source);
    Need((Length(Audio.PCM)>0) and (Length(Audio.Hits)>25),'Detected pulse fixture');
    CheckDensity;
    Worker:=TRhythmPrepareThread.Create(Source,50,0,rsStepGame,False,Audio,1,121);
    Audio:=nil;
    Worker.Start;
    Worker.WaitFor;
    Need(Worker.Error='',Worker.Error);
    Ref:=Worker.Plan;
    Audio:=Worker.TakeAudio;
    FreeAndNil(Worker);
    Cold:=TStepPlan.LoadAudioMetadata(Ref,Source,0);
    Need(Length(Cold.PCM)=0,'Saved chart needs PCM');
    Plan:=TStepPlan.Load(Ref,Cold,0);
    Need(Plan.Count>25,'Prepared chart has too few taps');
    Need((StepPlayerCount(1280,720)=2) and (StepPlayerCount(720,1280)=1) and (StepPlayerCount(720,720)=1),'Responsive board count');
    Need((StepNoteY(0,100,500)=100) and (StepNoteY(STEP_LOOKAHEAD,100,500)=500),'Note endpoints');
    J:=0;
    SampleTime:=Plan.Notes[Plan.Count div 3].Time;
    for I:=0 to Plan.Count-1 do begin
      Note:=Plan.Notes[I];
      while (J<Length(Audio.Hits)) and (Audio.Hits[J].Time<Note.Time) do Inc(J);
      Need((J<Length(Audio.Hits)) and (Audio.Hits[J].Time=Note.Time),'Changed source hit time');
      Need((Plan.CountThrough(Note.Time)=I+1) and (Plan.CountThrough(Note.Time-1E-8)=I),'Exact hit boundary');
      if Note.Lanes[0]<>Note.Lanes[1] then Inc(Different);
      if (Note.Lanes[0] and (Note.Lanes[0]-1))<>0 then begin
        Inc(ChordCount);
        if (Note.Time>3) and (Note.Time<8) then SampleTime:=Note.Time;
      end;
    end;
    Need((ChordCount>0) and (Different>=Plan.Count div 2),'Missing accents or distinct duet lanes');
    Renderer:=TRhythmRenderer.Create;
    Renderer.ConfigureStyle(rsStepGame,Ref,100,0);
    Image:=TBitmap.Create;
    Image.PixelFormat:=pf32bit;
    for Backend:=0 to 1 do begin
      Renderer.UseD2D:=Backend=1;
      for I:=0 to 1 do begin
        if I=0 then Image.SetSize(960,540) else Image.SetSize(540,960);
        for J:=0 to 5 do begin
          T:=SampleTime+(J-3)*0.028;
          Renderer.Render(Image,Audio,T,0);
          Expected:=ImageHash;
          Renderer.Render(Image,Cold,0,0);
          Renderer.Render(Image,Cold,T,0);
          Need(ImageHash=Expected,'Warm/cold or backwards seek pixel mismatch');
          Renderer.Render(Image,Cold,T+0.25,0,'',1,0,0,0.25);
          Need(ImageHash=Expected,'Host render offset changed the chart alignment');
        end;
      end;
      if Backend=1 then Need(Renderer.LastUsedD2D,'Direct2D fallback');
      CheckJudgmentPixels(SampleTime);
    end;
    SaveImage('prism-step-duo',1280,720,SampleTime);
    SaveImage('prism-step-solo',540,960,SampleTime);
    SaveImage('prism-step-clear',960,540,Audio.Duration);
    MeasureFrames(Ref,Cold,3,4);
    CheckRolls;
    CheckPatterns;
    CheckLongChart;
    WriteLn('Step game PASS checks=',Checks,' taps=',Plan.Count,' chords=',ChordCount,' sample=',SampleTime:0:3);
  except
    on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;
  end;
  Image.Free;
  Renderer.Free;
  Worker.Free;
  Plan.Free;
  Cold.Free;
  Audio.Free;
end.
