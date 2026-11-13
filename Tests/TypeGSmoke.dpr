program TypeGSmoke;
{$APPTYPE CONSOLE}
// 4小節の再配置、32ゲームの全動作、PCMなし復元・編集の不変性・順逆描画を隔離データで検証する。
uses System.SysUtils, System.Classes, System.Math, System.IOUtils, System.Hash,
  Vcl.Graphics, Vcl.Imaging.pngimage, RhythmAudio, RhythmAudioCache, RhythmStyles,
  RhythmGPlan, RhythmGCodec, RhythmGArt, RhythmGImages, RhythmGScene,
  RhythmPlanRef, RhythmSettings, RhythmAnimation, RhythmRenderSurface, RhythmImageBank,
  RhythmStyleRegistry, RhythmStyleOps, RhythmPrepare;
var Checks,Frames: Integer; Folder,SourceFile: string;
procedure Need(B: Boolean; const Why: string);
begin if not B then raise Exception.Create(Why); Inc(Checks); end;
function Audio(Seconds,BPM: Double; Silent: Boolean=False): TRhythmAudio;
var I,N: Integer;
begin
  Result:=TRhythmAudio.Create; Result.Source:=SourceFile; Result.SourceRevision:=AudioSourceStamp(SourceFile);
  Result.Key:=THashSHA2.GetHashString('Type.G fixture '+FloatToStr(Seconds)+' '+FloatToStr(BPM));
  Result.Duration:=Seconds; Result.SoundEnd:=Seconds; Result.Sensitivity:=50;
  if Silent then Exit;
  N:=Max(0,Floor((Seconds-0.25)*BPM/60)); SetLength(Result.Hits,N);
  for I:=0 to N-1 do begin Result.Hits[I].Time:=0.25+I*60/BPM;
    Result.Hits[I].Strength:=0.35+(I mod 5)*0.15; end;
end;
procedure SavePNG(B: TBitmap; const Name: string);
var PNG: TPngImage;
begin
  PNG:=TPngImage.Create;
  try PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Folder,Name)); finally PNG.Free; end;
end;
function PixelHash(B: TBitmap): string;
var H: THashSHA2; Y: Integer;
begin
  H:=THashSHA2.Create;
  for Y:=0 to B.Height-1 do H.Update(B.ScanLine[Y]^,B.Width*4);
  Result:=H.HashAsString;
end;
procedure CheckPlan;
var A,R: TRhythmAudio; P,Q: TGPlan; Ref,Original: TRhythmPlanRef; S,Loaded: TRhythmSettings;
  I,J,N,OldN: Integer; Used: array[0..31] of Boolean; Durations: array[0..6] of Double;
  Expected: Double; Failed: Boolean;
begin
  A:=Audio(300.037,120); P:=BuildGPlan(A); Q:=nil; R:=nil;
  try
    Need(Abs(P.Beat-0.5)<0.005,'120 BPM estimate'); Need(Length(P.Scenes)=38,'4 bars grid count');
    FillChar(Used,SizeOf(Used),0);
    for I:=0 to High(P.Scenes) do begin
      Used[P.Scenes[I].Game]:=True;
      if I>0 then Need(P.Scenes[I].Game<>P.Scenes[I-1].Game,'consecutive game');
      Need(Abs(P.Scenes[I].Start-I*8)<1E-8,'4 bars boundary');
    end;
    for I:=0 to 31 do Need(Used[I],'missing game in five minutes '+IntToStr(I));
    for I:=0 to High(P.Cues) do begin
      Need(P.Cues[I].Time=A.Hits[P.Cues[I].Source].Time,'actual audio cue');
      Need(P.Cues[I].Time-P.Cues[I].Lead>=P.Scenes[P.Cues[I].Scene].ActionStart,'intro contains cue');
    end;
    Ref:=NewPlanRef(A.Key,50,0,rsTypeG); Ref.SourceRevision:=A.SourceRevision; SaveGPlan(P,A,Ref); Original:=Ref;
    R:=LoadGAudio(Ref,A.Source,0); Need(Length(R.PCM)=0,'cold restore PCM');
    Q:=LoadGPlan(Ref,R,0); Need(Length(Q.Scenes)=38,'cold scenes'); FreeAndNil(Q);
    Q:=P.Clone; Q.Regrid(90,A); Need(Length(Q.Scenes)=29,'slower BPM removes overflow');
    for I:=0 to High(Q.Scenes) do Need(Q.Scenes[I].Game=P.Scenes[I].Game,'regrid preserves games');
    Q.Regrid(180,A); Need(Length(Q.Scenes)=57,'faster BPM fills missing scenes');
    for I:=0 to High(Q.Scenes) do Need(Abs(Q.Scenes[I].Finish-Min(Q.Duration,(I+1)*16/3))<1E-8,'manual grid finish');
    Q.Transitions:=False; SaveGEdit(Q,A,Ref); Need(Ref.Key<>Original.Key,'edit overwrote original plan');
    S:=TRhythmSettings.Defaults; S.Style:=rsTypeG; S.Music:=A.Source; S.Plan:=Ref;
    Need(TRhythmSettings.TryJSON(S.ToJSON,Loaded) and (Loaded.Plan.Key=Ref.Key),'edited settings reference');
    FreeAndNil(Q); Q:=LoadGPlan(Loaded.Plan,R,0); Need(not Q.Transitions,'transition preference');
    Need(Abs(Q.Beat-1/3)<1E-12,'manual BPM persisted'); FreeAndNil(Q);
    Q:=LoadGPlan(Original,R,0); Need(Length(Q.Scenes)=38,'old project plan mutated');
    N:=Length(Q.Scenes); Q.Split(0,4); Q.RebuildCues(A); Need(Length(Q.Scenes)=N+1,'split');
    Q.Merge(0); Q.RebuildCues(A); Need(Length(Q.Scenes)=N,'merge');
    Q.Bounds(1,7.5,16.5); Q.RebuildCues(A); Need((Q.Scenes[0].Finish=7.5) and (Q.Scenes[2].Start=16.5),'adjacent bounds');
    Q.Delete(0); Q.RebuildCues(A); Need(Q.Scenes[0].Start=0,'delete first');
    Q.Delete(High(Q.Scenes)); Q.RebuildCues(A); Need(Q.Scenes[High(Q.Scenes)].Finish=A.Duration,'delete last');
    Failed:=False; OldN:=Length(Q.Scenes);
    try Q.Split(0,-1); except on E: EConvertError do Failed:=True; end;
    Need(Failed and (Length(Q.Scenes)=OldN),'rejected edit mutated plan');
    Durations[0]:=0.02; Durations[1]:=0.25; Durations[2]:=1; Durations[3]:=5.3;
    Durations[4]:=16; Durations[5]:=31.99; Durations[6]:=300.037;
  finally Q.Free; R.Free; P.Free; A.Free; end;
  for I:=0 to High(Durations) do for J:=0 to 1 do begin
    A:=Audio(Durations[I],120,J=1); P:=BuildGPlan(A);
    try
      for N:=60 to 240 do if N mod 15=0 then begin
        P.Regrid(N,A); P.Validate; Expected:=0;
        for OldN:=0 to High(P.Scenes) do begin
          Need(P.Scenes[OldN].Start=Expected,'grid gap'); Expected:=P.Scenes[OldN].Finish;
        end;
        Need(Expected=A.Duration,'grid truncated song');
      end;
      if J=1 then Need(Length(P.Cues)=0,'silent song generated audio hits');
    finally P.Free; A.Free; end;
  end;
  for J:=90 to 150 do if J mod 30=0 then begin
    A:=Audio(90,J); P:=BuildGPlan(A);
    try Need(Abs(60/P.Beat-J)<1.1,'BPM fixture '+IntToStr(J)); finally P.Free; A.Free; end;
  end;
end;

procedure CheckRender;
const W: array[0..2] of Integer=(640,360,1000); H: array[0..2] of Integer=(448,640,700);
var A: TRhythmAudio; P: TGPlan; B,Sheet: TBitmap; Surface: TAnimationRenderSurface; F: TAnimationFrame;
  G,Action,Size,Mode,I,J,N: Integer; Times: array[0..8] of Double; Hashes: array[0..8] of string;
  Colors: array[0..31] of string; Count: Integer; C: TGCue;
  procedure Draw(T: Double);
  begin
    F.Time:=T; F.Width:=B.Width; F.Height:=B.Height; F.Direction:=0; F.BackgroundOnly:=False;
    Surface.BeginFrame(B); DrawTypeG(Surface,P,F); Need(Surface.EndFrame,'surface failure'); Inc(Frames);
  end;
begin
  A:=Audio(16,120); P:=BuildGPlan(A); B:=TBitmap.Create; Sheet:=TBitmap.Create;
  Surface:=TAnimationRenderSurface.Create(CreateGImages);
  try
    B.PixelFormat:=pf32bit; Sheet.PixelFormat:=pf32bit; Sheet.SetSize(1600,2240);
    SetLength(P.Scenes,1); P.Scenes[0].Start:=0; P.Scenes[0].Finish:=16; P.Transitions:=False;
    for G:=0 to 31 do begin
      if (ParamCount>0) and (ParamStr(1)='Changed') and not (G in [0,3,6,7,8,9,11,14,15,16,24,25,27,29,31]) then Continue;
      P.Scenes[0].Game:=G; P.RebuildCues(A); Need(Length(P.Cues)>2,'game has no action');
      for Action:=0 to GActionCount(G)-1 do begin
        N:=-1; for I:=0 to High(P.Cues) do if P.Cues[I].Action=Action then begin N:=I; Break; end;
        Need(N>=0,'action not scheduled '+GNames[G]); C:=P.Cues[N];
        Times[0]:=0.2; Times[1]:=0.33; Times[2]:=C.Time-C.Lead;
        Times[3]:=C.Time-C.Lead*0.5; Times[4]:=C.Time; Times[5]:=C.Time+C.Recover*0.5;
        Times[6]:=C.Time+C.Recover; Times[7]:=15.8; Times[8]:=16;
        for Size:=0 to 2 do for Mode:=0 to 1 do begin
          B.SetSize(W[Size],H[Size]); Surface.UseD2D:=Mode=1;
          for I:=0 to High(Times) do begin Draw(Times[I]); Hashes[I]:=PixelHash(B); end;
          Need(Hashes[0]<>Hashes[1],'intro does not move '+GNames[G]);
          Need(Hashes[3]<>Hashes[4],'action does not move '+GNames[G]);
          for I:=High(Times) downto 0 do begin Draw(Times[I]); Need(PixelHash(B)=Hashes[I],'reverse seek '+GNames[G]); end;
          if (Size=0) and (Mode=1) and (Action=0) then begin
            Draw(C.Time); Colors[G]:=PixelHash(B);
            Sheet.Canvas.StretchDraw(Rect((G mod 4)*400,(G div 4)*280,(G mod 4+1)*400,(G div 4+1)*280),B);
            SavePNG(B,Format('game-%.2d.png',[G+1]));
          end;
        end;
      end;
    end;
    for I:=0 to 31 do for J:=I+1 to 31 do if (Colors[I]<>'') and (Colors[J]<>'') then Need(Colors[I]<>Colors[J],'two games are identical');
    SavePNG(Sheet,'all-32-games.png');
    // 音ハメがない全曲でも全ゲームが動き続けることを別途確認する。
    P.Cues:=nil; B.SetSize(640,448); Surface.UseD2D:=True;
    for G:=0 to 31 do begin P.Scenes[0].Game:=G; Draw(7.123); Hashes[0]:=PixelHash(B);
      Draw(7.278); Need(Hashes[0]<>PixelHash(B),'silent scene frozen '+GNames[G]); end;
    // 切替6方式も絶対時刻で復元できる。
    P.Split(0,8); P.RebuildCues(A); P.Transitions:=True;
    for Count:=0 to 5 do begin P.Scenes[1].Transition:=Count;
      Draw(8.12); Hashes[0]:=PixelHash(B); Draw(9); Draw(8.12); Need(Hashes[0]=PixelHash(B),'transition seek'); end;
  finally Surface.Free; Sheet.Free; B.Free; P.Free; A.Free; end;
end;

procedure CheckWorkerResume;
var A: TRhythmAudio; P: TGPlan; Ref: TRhythmPlanRef; Worker: TRhythmPrepareThread;
begin
  A:=Audio(16,120); P:=BuildGPlan(A);
  try
    P.Scenes[0].Game:=27; P.Regrid(90,A);
    Ref:=NewPlanRef(A.Key,50,0,rsTypeG); Ref.SourceRevision:=A.SourceRevision; SaveGEdit(P,A,Ref);
  finally P.Free; end;
  Worker:=TRhythmPrepareThread.Create(A.Source,50,0,rsTypeG,False,A,1);
  try
    Worker.ResumePlan:=Ref; Worker.Start; Worker.WaitFor;
    Need(Worker.Error='',Worker.Error); Need(Worker.Plan.Key=Ref.Key,'worker regenerated edited plan');
    P:=LoadGPlan(Worker.Plan,Worker.Audio,0);
    try Need((P.Scenes[0].Game=27) and (Abs(60/P.Beat-90)<1E-10),'worker lost game/BPM'); finally P.Free; end;
  finally Worker.Free; end;
end;
begin
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence'); ForceDirectories(Folder);
    SourceFile:=TPath.Combine(Folder,'fixture.source'); TFile.WriteAllText(SourceFile,'Type.G synthetic metadata test');
    CheckPlan; if (ParamCount=0) or (ParamStr(1)<>'PlanOnly') then CheckRender; CheckWorkerResume;
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"frames":%d,"games":32,"gridBars":4,"silentAnimation":true,"pcmFreeRestore":true,"workerResume":true}',[Checks,Frames]),TEncoding.UTF8);
    WriteLn('Type.G PASS checks=',Checks,' frames=',Frames,' games=32');
  except on E: Exception do begin WriteLn(E.ClassName,': ',E.Message); ExitCode:=1; end; end;
end.
