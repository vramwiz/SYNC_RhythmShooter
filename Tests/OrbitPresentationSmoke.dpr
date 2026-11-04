program OrbitPresentationSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Hash,System.IOUtils,System.Classes,System.JSON,System.Diagnostics,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmPlanRef,RhythmStyles,RhythmSettings,RhythmProduct,
  RhythmScene,RhythmOrbitPlan,RhythmOrbitTypes,RhythmOrbitMarks,RhythmOrbitGuide,
  RhythmEqualizer,RhythmRenderSurface,RhythmImageBank,RhythmOverlay;
var A,Meta:TRhythmAudio;Plan:TOrbitPlan;Ref:TRhythmPlanRef;Render:TRhythmRenderer;Surface:TAnimationRenderSurface;
  Image:TBitmap;PNG:TPngImage;Folder,Source,Revision,First,OnHash,OffHash:string;Stamp:TWin32FileAttributeData;
  Saved,Loaded:TRhythmSettings;Style:TRhythmStyle;B,I,J,K,Mode,Checks,Frames,Count:Integer;
  Tap:TOrbitTap;Activity:TEqualizerActivity;Times:array[0..8] of Double=(0.03,0.4,1.8,3,3.1,6,7.8,8.6,19.5);
  Samples:array[0..2,0..24] of TColor;
  WideCore:array[0..2] of TColor;
procedure Need(V:Boolean;const S:string);
begin if not V then raise Exception.Create(S);Inc(Checks);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;
  try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;
  finally M.Free;end;
end;
procedure Snapshot(const Name:string);
begin PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));finally FreeAndNil(PNG);end;Inc(Frames);end;
procedure MeasureFrames;
const FrameCount=20;
var Backend,Frame:Integer;Watch:TStopwatch;Total,Slowest,Elapsed:Double;
begin
  Image.SetSize(960,540);
  Render.ConfigureStyle(rsRhythmGame,Ref,100,0);
  for Backend:=0 to 1 do begin
    Render.UseD2D:=Backend=1;
    Render.Render(Image,Meta,5.9,0);
    Total:=0;Slowest:=0;
    for Frame:=0 to FrameCount-1 do begin
      Watch:=TStopwatch.StartNew;
      Render.Render(Image,Meta,6+Frame/60,0);
      GdiFlush;
      Watch.Stop;
      Elapsed:=Watch.Elapsed.TotalMilliseconds;
      Total:=Total+Elapsed;Slowest:=Max(Slowest,Elapsed);
    end;
    Need(Render.LastUsedD2D=(Backend=1),'Wrong benchmark backend');
    WriteLn('Type.V 960x540 backend=',Backend,' meanMs=',Total/FrameCount:0:3,' maxMs=',Slowest:0:3);
    Flush(Output);
  end;
end;
procedure CheckMarkerLayout;
const Widths:array[0..3] of Integer=(960,540,320,720);
  Heights:array[0..3] of Integer=(540,960,180,720);
var State:TOrbitVisualState;Layout:TOrbitCourse;Markers:TOrbitMarkers;Point:TOrbitPoint;
  Previous,Current:TArray<Integer>;LastMarkers:TOrbitMarkers;
  View,Frame,Count,I,J,Index,LastIndex:Integer;Time,W,H,Gap:Double;ReadableFollower,Found:Boolean;
begin
  Need(OrbitGameplayStart(Plan)=3,'Opening length');
  Layout.Prepare(Plan,960,540);
  State:=OrbitVisualState(Plan,1.2);
  Need(not State.Playing and (State.Horizon=0) and (State.Pulse=0) and
    (Layout.Visible(State,1.2,Markers)=0),'Opening leaked a cue too early');
  State:=OrbitVisualState(Plan,1.7);
  Need((State.PreviewAlpha>0) and (State.PreviewAlpha<1) and not State.Playing,'Preview did not fade in before gameplay');
  Count:=Layout.Visible(State,1.7,Markers);
  Need((Count>0) and (Markers[0].TapIndex=75) and (Markers[0].Radius>=0.95*OrbitHitRadius(540)),
    'Fast lead-in target was too small at the start of the preview');
  State:=OrbitVisualState(Plan,1.8);
  Count:=Layout.Visible(State,1.8,Markers);
  Need((Count>0) and (Markers[0].TapIndex=75) and (Markers[0].Radius>=0.99*OrbitHitRadius(540)) and
    (State.PreviewAlpha>=0.99) and not State.Playing,'Fast lead-in target stayed small until the hit');
  State:=OrbitVisualState(Plan,2.25);
  Count:=Layout.Visible(State,2.25,Markers);
  Need((Count>0) and (Markers[0].TapIndex=75) and not State.Playing and (State.LastHit=74) and (State.Pulse=0),
    'First target was not visible before its hit');
  State:=OrbitVisualState(Plan,3);
  Need(State.Playing and (State.FirstTap=75) and (State.LastHit=75),'First hit did not start at its original time');
  ReadableFollower:=False;
  SetLength(Previous,Plan.Count);SetLength(Current,Plan.Count);
  for View:=Low(Widths) to High(Widths) do begin
    W:=Widths[View];H:=Heights[View];
    Layout.Prepare(Plan,W,H);
    for I:=0 to Plan.Count-1 do Previous[I]:=-1;
    for Frame:=0 to Ceil((Plan.SoundEnd-1.4)*60)+1 do begin
      Time:=1.4+Frame/60;
      State:=OrbitVisualState(Plan,Time);
      Count:=Layout.Visible(State,Time,Markers);
      for I:=0 to Plan.Count-1 do Current[I]:=-1;
      for I:=0 to Count-1 do begin
        Index:=Markers[I].TapIndex;Current[Index]:=I;LastIndex:=Previous[Index];
        Point:=Layout.CursorAt(Plan,Plan.Taps[Index].Time);
        Need((Markers[I].Center.X=Point.X) and (Markers[I].Center.Y=Point.Y),'Cursor missed the marker at its hit');
        Need((Point.X>=0) and (Point.X<=W) and (Point.Y>=0) and (Point.Y<=H),'Marker center left the playfield');
        if LastIndex>=0 then begin
          Need((Markers[I].Center.X=LastMarkers[LastIndex].Center.X) and
            (Markers[I].Center.Y=LastMarkers[LastIndex].Center.Y),'Marker drifted between frames');
          Need((Markers[I].Radius>=LastMarkers[LastIndex].Radius) and
            (Markers[I].Visibility>=LastMarkers[LastIndex].Visibility),'Marker shrank or faded before the hit');
        end;
        if (I>0) and (Plan.Taps[Index].Time-Time>=0.5) and
          (Markers[I].Radius>=0.44*OrbitHitRadius(Min(W,H))-1E-9) then ReadableFollower:=True;
        for J:=0 to I-1 do begin
          Gap:=Markers[I].Extent+Markers[J].Extent+ORBIT_MARKER_GAP;
          if Sqr(Markers[I].Center.X-Markers[J].Center.X)+Sqr(Markers[I].Center.Y-Markers[J].Center.Y)<Sqr(Gap) then
            Need(False,Format('Displayed marker outlines overlap, view %d, t %.4f, taps %d and %d, radii %.2f and %.2f, gap %.2f',
              [View,Time,Index,Markers[J].TapIndex,Markers[I].Radius,Markers[J].Radius,Gap]))
          else Inc(Checks);
        end;
      end;
      for I:=State.LastHit+1 to Plan.Count-1 do
        if Previous[I]>=0 then Need(Current[I]>=0,'Visible marker disappeared before its hit');
      for I:=0 to Plan.Count-1 do Previous[I]:=Current[I];
      LastMarkers:=Markers;
    end;
    for I:=OrbitOpeningTapCount(Plan) to Plan.Count-1 do begin
      Time:=Plan.Taps[I].Time-0.50;
      Count:=Layout.Visible(OrbitVisualState(Plan,Time),Time,Markers);
      Found:=False;
      for J:=0 to Count-1 do
        if (Markers[J].TapIndex=I) and (Markers[J].Visibility>=0.99) then Found:=True;
      Need(Found,'40 ms chart hit had no fully visible marker 500 ms before contact');
    end;
  end;
  Need(ReadableFollower,'Dense previews stayed tiny until they were the next hit');
end;
procedure CheckDensePreview;
var Audio:TRhythmAudio;Dense:TOrbitPlan;State:TOrbitVisualState;Layout:TOrbitCourse;
  Markers:TOrbitMarkers;I,Count:Integer;Time:Double;
begin
  Audio:=TRhythmAudio.Create;Dense:=nil;
  try
    Audio.Duration:=7.5;Audio.SoundEnd:=7.5;
    SetLength(Audio.Hits,7000);
    for I:=0 to High(Audio.Hits) do begin
      Audio.Hits[I].Time:=I*0.001;Audio.Hits[I].Strength:=0.5;
    end;
    Dense:=TOrbitPlan.Build(Audio,20);
    State:=OrbitVisualState(Dense,3);
    Layout.Prepare(Dense,960,540);
    Count:=Layout.Visible(State,3,Markers);
    Need((Count>=40) and (Markers[0].TapIndex=State.LastHit+1),
      'Full playfield did not preview the upcoming notes');
    for I:=3001 to 6999 do begin
      Time:=Dense.Taps[I].Time-0.0005;
      Count:=Layout.Visible(OrbitVisualState(Dense,Time),Time,Markers);
      Need((Count>0) and (Markers[0].TapIndex=I),'Full playfield skipped the next hit');
    end;
    FreeAndNil(Dense);
    SetLength(Audio.Hits,1);
    Audio.Hits[0].Time:=Audio.SoundEnd;
    Dense:=TOrbitPlan.Build(Audio,20);
    State:=OrbitVisualState(Dense,7.4);
    Layout.Prepare(Dense,960,540);
    Need(Layout.Visible(State,7.4,Markers)=1,'Final note was never previewed');
  finally
    Dense.Free;Audio.Free;
  end;
end;
procedure CheckSensitivityCourse;
var Sparse:TOrbitPlan;DenseCourse,SparseCourse:TOrbitCourse;I,J:Integer;
  DenseDistance,SparseDistance,Time:Double;P,Q,PreviousDense,PreviousSparse:TOrbitPoint;
  Moved:Boolean;
begin
  Sparse:=TOrbitPlan.Build(A,80);
  try
    DenseCourse.Prepare(Plan,960,540);
    SparseCourse.Prepare(Sparse,960,540);
    Need(Plan.Count>Sparse.Count*2,'Fixture does not exercise sensitivity');
    Moved:=False;
    for I:=OrbitOpeningTapCount(Sparse) to Sparse.Count-1 do begin
      Time:=Sparse.Taps[I].Time;
      J:=Plan.Before(Time);
      Need((J>=0) and (Plan.Taps[J].Time=Time),'Sensitivity moved a common hit time');
      P:=DenseCourse.Center(J);Q:=SparseCourse.Center(I);
      if Hypot(P.X-Q.X,P.Y-Q.Y)>OrbitHitRadius(540) then Moved:=True;
    end;
    Need(Moved,'Sensitivity did not change common hit positions');
    DenseDistance:=0;SparseDistance:=0;
    PreviousDense:=DenseCourse.CursorAt(Plan,4);
    PreviousSparse:=SparseCourse.CursorAt(Sparse,4);
    for I:=1 to 2400 do begin
      Time:=4+I/240;
      P:=DenseCourse.CursorAt(Plan,Time);
      Q:=SparseCourse.CursorAt(Sparse,Time);
      DenseDistance:=DenseDistance+Hypot(P.X-PreviousDense.X,P.Y-PreviousDense.Y);
      SparseDistance:=SparseDistance+Hypot(Q.X-PreviousSparse.X,Q.Y-PreviousSparse.Y);
      PreviousDense:=P;
      PreviousSparse:=Q;
    end;
    Need(DenseDistance>1.8*SparseDistance,'Dense course did not increase travel and speed');
    WriteLn('Type.V distance in 10 s, sparse=',SparseDistance:0:1,' px, dense=',DenseDistance:0:1,' px');
  finally
    Sparse.Free;
  end;
end;
begin A:=nil;Meta:=nil;Plan:=nil;Render:=nil;Surface:=nil;Image:=nil;PNG:=nil;Checks:=0;Frames:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','Presentation native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    for Style:=Low(TRhythmStyle) to High(TRhythmStyle) do begin
      Saved:=TRhythmSettings.Defaults;Saved.Style:=Style;
      Need(Saved.EqualizerMode=-1,'New default mode');Need(EqualizerEnabled(-1,Style,3)=(Style=rsRhythmGame),'Migration style default');
      for Mode:=-1 to 1 do begin Saved.EqualizerMode:=Mode;Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded),'Mode JSON parse');
        Need((Loaded.EqualizerMode=Mode) and (Loaded.Style=Style),'Mode JSON roundtrip');
      end;
    end;
    Need(not EqualizerEnabled(-1,rsRhythmGame,1),'Flat v1 migration gained meter');Need(EqualizerEnabled(1,rsRhythmGame,1),'Legacy explicit on');
    Need(not TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","equalizer":"false"}',Loaded),'Bad boolean accepted');
    Need((Abs(OrbitHitRadius(540)*2-49.68)<1E-9) and (Abs(OrbitHitRadius(1080)*2-99.36)<1E-9),
      'Type.V target diameter does not follow the viewport');
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(360,120);Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create([],0));
    for B:=0 to 1 do begin Surface.UseD2D:=B=1;
      for J:=0 to 1 do begin Surface.BeginFrame(Image);
        if J=0 then Surface.FillRect(0,0,360,120,RGB(240,10,10)) else Surface.FillRect(0,0,360,120,RGB(10,10,240));
        for K:=0 to 2 do begin Tap:=Default(TOrbitTap);Tap.Source:=K;Tap.Chain:=1;Tap.Strength:=0.4;
          if K=1 then Tap.Chain:=3;if K=2 then Tap.Strength:=0.9;
          Need(Ord(OrbitMarkKind(Tap))=K,'Symbol meaning');
          DrawOrbitMark(Surface,70+K*110,60,OrbitHitRadius(720),0,0.4,0.7,OrbitMarkKind(Tap),OrbitMarkColor(Tap));
        end;
        Need(Surface.EndFrame,'Shape end frame');
        for K:=0 to 2 do for I:=0 to 24 do begin
          if J=0 then Samples[K,I]:=Image.Canvas.Pixels[66+K*110+(I mod 5)*2,56+(I div 5)*2]
          else Need(Samples[K,I]=Image.Canvas.Pixels[66+K*110+(I mod 5)*2,56+(I div 5)*2],'Marker core is transparent');
        end;
        for K:=0 to 2 do begin
          if J=0 then WideCore[K]:=Image.Canvas.Pixels[99+K*110,60]
          else Need(WideCore[K]=Image.Canvas.Pixels[99+K*110,60],'Enlarged target lost its opaque outer area');
        end;
        Snapshot(Format('symbols-backend%d-background%d',[B,J]));
      end;
      for J:=0 to 2 do begin Surface.BeginFrame(Image);Surface.FillRect(0,0,360,120,clBlack);
        DrawOrbitGood(Surface,180,90,J*0.19,360,120,RGB(80,230,255));Need(Surface.EndFrame,'GOOD end frame');Count:=0;
        for I:=0 to 359 do for K:=0 to 119 do if ColorToRGB(Image.Canvas.Pixels[I,K])<>0 then Inc(Count);
        if J=2 then Need(Count=0,'GOOD does not expire') else Need(Count>40,'GOOD missing');Snapshot(Format('good-backend%d-stage%d',[B,J]));
      end;
      if B=1 then Need(Surface.LastUsedD2D,'D2D unavailable');
    end;
    FreeAndNil(Surface);Image.SetSize(640,360);
    Source:=TPath.Combine(Folder,'presentation.identity');TFile.WriteAllText(Source,'Synthetic presentation identity',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    A:=TRhythmAudio.Create;A.Source:=Source;A.SourceRevision:=Revision;A.Key:=THashSHA2.GetHashString('presentation-v3');A.Sensitivity:=50;A.Duration:=20;A.SoundEnd:=20;
    SetLength(A.Hits,500);for I:=0 to High(A.Hits) do begin A.Hits[I].Time:=I*0.04;A.Hits[I].Strength:=0.3+(I mod 8)*0.1;end;
    Plan:=TOrbitPlan.Build(A,20);Ref:=NewPlanRef(A.Key,50,0,rsRhythmGame,121);Ref.SourceRevision:=Revision;Plan.Save(Ref,A);Meta:=TOrbitPlan.LoadAudioMetadata(Ref,Source,0);
    CheckMarkerLayout;
    CheckDensePreview;
    CheckSensitivityCourse;
    Render:=TRhythmRenderer.Create;
    if GetEnvironmentVariable('RHYTHM_ORBIT_BENCHMARK')='1' then MeasureFrames
    else
    for B:=0 to 1 do begin Render.UseD2D:=B=1;
      for J:=Low(Times) to High(Times) do begin
        for Mode:=0 to 1 do begin Render.ConfigureStyle(rsRhythmGame,Ref,100,Mode);Render.Render(Image,A,Times[J],0);First:=ImageHash;
          Render.Render(Image,Meta,A.Duration-Times[J],0);Render.Render(Image,Meta,Times[J],0);Need(ImageHash=First,'Overlay warm/cold/seek drift');
          if Mode=0 then OffHash:=First else OnHash:=First;
          if J=4 then begin
            Snapshot(Format('game-backend%d-eq%d',[B,Mode]));
            if (B=1) and (Mode=0) then begin OverlayPreview(Image);Snapshot('type-v-preview');end;
          end;
          if (J=2) and (B=1) and (Mode=0) then begin OverlayPreview(Image);Snapshot('type-v-lead-in');end;
          Saved:=TRhythmSettings.Defaults;Saved.Style:=rsRhythmGame;Saved.Plan:=Ref;Saved.GameThreshold:=20;Saved.EqualizerMode:=Mode;
          Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded) and (Loaded.Plan.Key=Ref.Key) and (Loaded.Plan.Digest=Ref.Digest),'Display mode invalidated plan');
        end;
        Need((OffHash<>OnHash)=(Times[J]>=OrbitGameplayStart(Plan)),'Equalizer did not follow the opening boundary');
        Render.ConfigureStyle(rsRhythmGame,Ref,100,-1);Render.Render(Image,Meta,Times[J],0);Need(ImageHash=OnHash,'Auto game default');
      end;
      Render.ConfigureStyle(rsRhythmGame,Ref,100,0);Render.Render(Image,nil,2.4,0);OffHash:=ImageHash;
      Render.ConfigureStyle(rsRhythmGame,Ref,100,1);Render.Render(Image,nil,2.4,0);Need(ImageHash=OffHash,'No-audio overlay unsafe');
    end;
    Activity:=EqualizerActivity(nil,1);Need(not Activity.Valid,'Nil audio reaction');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"frames":%d,"opaqueCore":true,"symbols":3,"settingsStyles":12,"planUnchanged":true}',[Checks,Frames]),TEncoding.UTF8);
    WriteLn('Orbit presentation PASS checks=',Checks,' frames=',Frames);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  PNG.Free;Surface.Free;Render.Free;Plan.Free;Meta.Free;A.Free;Image.Free;
end.
