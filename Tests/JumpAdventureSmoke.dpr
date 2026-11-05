program JumpAdventureSmoke;
{$APPTYPE CONSOLE}
// 曲全体の生成、音と接触、回避、両方向の地形、保存後のフレームを確認する。
uses System.SysUtils,System.Types,System.Math,System.Classes,System.Hash,System.IOUtils,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmAudioCache,RhythmStyles,RhythmPlanRef,
  RhythmSettings,RhythmStyleOps,RhythmStyleRegistry,RhythmScene,RhythmJumpPlan,RhythmJumpCodec;

type
  TLevelSets=array[Boolean] of set of 1..5;
var Checks:Integer;

procedure Need(Valid:Boolean;const Description:string);
begin
  if not Valid then raise Exception.Create(Description);
  Inc(Checks);
end;

function SyntheticAudio(const Source:string):TRhythmAudio;
const Spacing:array[0..7] of Double=(0.62,0.36,0.047,1.42,0.81,0.061,0.29,0.45);
var I,N,Section:Integer; T:Double;
begin
  TFile.WriteAllText(Source,'Jump adventure synthetic events.',TEncoding.UTF8);
  Result:=TRhythmAudio.Create;
  Result.Source:=Source;
  Result.SourceRevision:=AudioSourceStamp(Source);
  Result.Key:=THashSHA2.GetHashStringFromFile(Source);
  Result.Sensitivity:=50;
  Result.Duration:=180;
  SetLength(Result.Envelope,18000);
  for I:=0 to High(Result.Envelope) do begin
    Section:=(I div 1125) mod 8;
    Result.Envelope[I]:=0.025+0.11*((Section*5) mod 8)+0.012*Sqr(Sin(I*0.06));
    if (I mod 1125)>1095 then Result.Envelope[I]:=0.001;
  end;
  Result.UpdateSoundBounds;
  T:=0;
  N:=0;
  SetLength(Result.Hits,5000);
  while T<179.50 do begin
    Section:=Trunc(T/11.25) mod 8;
    Result.Hits[N].Time:=T;
    Result.Hits[N].Strength:=0.22+0.11*(N mod 7);
    Inc(N);
    T:=T+Spacing[Section]*(0.88+(N mod 5)*0.06);
  end;
  SetLength(Result.Hits,N);
end;

procedure Verify(const Plan:TJumpPlan;Audio:TRhythmAudio;LongFixture:Boolean);
var
  I,J,K,Stomps,Unassigned,Attacks,HitsOnBoss,UnassignedOnBoss,Springs,WrongCrossings,ShortBounces:Integer;
  T,PrevY,EndTime,Offset,Crossing,Side:Double;
  N,A:TJumpNode;
  P,Q,Weak:TPointF;
  B:TJumpBoss;
  H:TJumpHazard;
  Levels,Moving:TLevelSets;
  BossDirections:set of Boolean;
  OldBoss:Integer;
begin
  Levels:=Default(TLevelSets);
  Moving:=Default(TLevelSets);
  Stomps:=0;
  Unassigned:=0;
  Attacks:=0;
  HitsOnBoss:=0;
  UnassignedOnBoss:=0;
  Springs:=0;
  WrongCrossings:=0;
  ShortBounces:=0;
  BossDirections:=[];
  OldBoss:=-1;
  for I:=0 to High(Plan.Stages) do begin
    Include(Levels[Plan.Stages[I].Vertical],Plan.Stages[I].Level);
    if I=0 then Need(Plan.Stages[I].Level=1,'Opening must be LV1');
    if I>0 then begin
      Need(Plan.Stages[I].Vertical<>Plan.Stages[I-1].Vertical,'Scroll direction did not switch');
      T:=Plan.Stages[I].StartTime;
      Need(Plan.Foot(T-0.001).Distance(Plan.Foot(T+0.001))<0.05,'Cut displaced the actor');
    end;
  end;
  for I:=0 to High(Plan.Nodes) do begin
    N:=Plan.Nodes[I];
    P:=Plan.Foot(N.Time);
    Q:=PointF(N.X,N.Y);
    Need(P.Distance(Q)<0.00003,'Contact lost');
    if I=0 then Continue;
    A:=Plan.Nodes[I-1];
    Need(Plan.Foot(N.Time-1E-6).Distance(P)<0.00004,'Arrival discontinuity');
    if N.Landing in [jlGround,jlSpring] then
      Need(Plan.Platform(I,N.Time).Distance(P)<0.00003,'Platform contact');
    J:=Plan.StageAt((A.Time+N.Time)*0.5);
    if (N.MoveX<>0) or (N.MoveY<>0) then
      Include(Moving[Plan.Stages[J].Vertical],Plan.Stages[J].Level);
    if N.Landing=jlSpring then Inc(Springs);
    if Plan.Stages[J].Vertical then Need(N.Y>A.Y,'Climb did not gain height')
    else Need(N.X>A.X,'Horizontal route did not progress right');
    if (N.Time-A.Time<0.49) and (A.Landing in [jlStomp,jlBoss]) and
      (Plan.Legs[I-1].Height<0.5) then Inc(ShortBounces);
    EndTime:=N.Time;
    T:=Plan.Legs[I-1].Takeoff;
    P:=Plan.Foot(T);
    Need(Plan.Foot(T-1E-6).Distance(P)<0.00004,'Takeoff discontinuity');
    if Plan.Legs[I-1].Height>0 then begin
      // 接地足の下向き通過を調べる。下から上がる一方向の足場は通過できる。
      for J:=Max(0,Plan.NodeAt(A.Time-7)-1) to Min(High(Plan.Nodes),Plan.NodeAt(N.Time+7)+1) do begin
        Need(not Plan.EarlierLanding(I-1,J,Crossing,Side),'Unresolved solid platform crossing');
        PrevY:=P.Y-Plan.Platform(J,T).Y;
        for K:=1 to 32 do begin
          Offset:=JumpBlend(T,EndTime,K/32);
          Q:=Plan.Foot(Offset);
          Weak:=Plan.Platform(J,Offset);
          if (PrevY>0.00002) and (Q.Y<Weak.Y-0.00002) and
            (Abs(Q.X-Weak.X)<Plan.Nodes[J].Width*0.5-0.03) and
            (Offset>=Plan.Nodes[J].SolidFrom) and (Offset<=Plan.Nodes[J].SolidUntil) then begin
            Inc(WrongCrossings);
            if WrongCrossings<=18 then WriteLn(Format('Cross: leg %d / platform %d at %.3fs, planned %.3fs, foot %.2f %.2f, deck %.2f %.2f, width %.2f',[I-1,J,Offset,Plan.Nodes[J].Time,Q.X,Q.Y,Weak.X,Weak.Y,Plan.Nodes[J].Width]));
            Break;
          end;
          PrevY:=Q.Y-Weak.Y;
        end;
      end;
    end;
    H:=Plan.Hazard(I-1);
    if H.Kind=0 then Continue;
    Inc(Attacks);
    for J:=0 to 16 do begin
      T:=JumpBlend(H.StartTime,H.EndTime,J/16);
      Need(Plan.Foot(T).Y>H.Y+H.Height+0.12,'Boss attack intersects the actor');
    end;
  end;
  for I:=0 to High(Plan.Beats) do begin
    T:=Plan.Beats[I].Time;
    Need(Audio.Hits[Audio.NearestHit(T)].Time=T,'Accent timing changed');
    J:=Plan.StageAt(T);
    K:=Plan.Beats[I].Node;
    if K<0 then begin
      Inc(Unassigned);
      if Plan.BossAt(T)>=0 then Inc(UnassignedOnBoss);
      Continue;
    end;
    if Plan.Nodes[K].Landing=jlStomp then begin
      Inc(Stomps);
    end;
    if Plan.Nodes[K].Landing<>jlBoss then Continue;
    Inc(HitsOnBoss);
    B:=Plan.Bosses[Plan.Stages[J].Boss];
    P:=Plan.BossCore(Plan.Stages[J].Boss,T);
    Weak:=JumpWeakPoint(B.Variant,Plan.Nodes[K].Variant);
    Need(PointF(P.X+Weak.X,P.Y+Weak.Y).Distance(Plan.Foot(T))<0.00008,'Boss weak point missed');
  end;
  for B in Plan.Bosses do begin
    J:=Plan.StageAt(Plan.Nodes[B.LastNode].Time);
    Include(BossDirections,Plan.Stages[J].Vertical);
    Need(B.Variant<>OldBoss,'Repeated boss variant');
    OldBoss:=B.Variant;
    K:=Plan.BeatFrom(Plan.Nodes[B.LastNode].Time);
    Need((K<Length(Plan.Beats)) and (Plan.Beats[K].Node=B.LastNode),'Kill not on beat');
  end;
  WriteLn(Format('%.2fs, %d stages, %d accents, %d stomps, %d unassigned accents, %d short bounces, %d springs, %d bosses, %d boss hits, %d unassigned boss accents, %d dodges, %d early platform crossings',
    [Plan.Duration,Length(Plan.Stages),Length(Plan.Beats),Stomps,Unassigned,ShortBounces,Springs,
     Length(Plan.Bosses),HitsOnBoss,UnassignedOnBoss,Attacks,WrongCrossings]));
  Need(WrongCrossings=0,'Earlier landing found by independent sampler');
  if LongFixture then begin
    Need(Length(Plan.Beats)=Length(Audio.Hits),'Missing distinct accents');
    Need((Levels[False]=[1..5]) and (Levels[True]=[1..5]),'Missing direction/level coverage');
    Need((Moving[False]=[4,5]) and (Moving[True]=[4,5]),'Missing moving platforms');
    Need((Stomps>0) and (Unassigned>0) and (ShortBounces>0) and (Springs>0),'Missing dense/gimmick coverage');
    Need(BossDirections=[False,True],'Both boss directions not generated');
    Need((HitsOnBoss>5) and (UnassignedOnBoss>0) and (Attacks>0),'Missing boss attacks or dense accents');
  end;
end;

function FrameHash(Image:TBitmap):string;
var Hash:THashSHA2; Y:Integer;
begin
  Hash:=THashSHA2.Create;
  for Y:=0 to Image.Height-1 do Hash.Update(Image.ScanLine[Y]^,Image.Width*4);
  Result:=Hash.HashAsString;
end;

procedure RenderProof(Plan:TJumpPlan;Audio,Cold:TRhythmAudio;const Ref:TRhythmPlanRef;const Folder:string);
var
  R:TRhythmRenderer;
  Image:TBitmap;
  PNG:TPngImage;
  S:string;
  I,J,K:Integer;
  T:Double;
  FullBeats,ContactBeats:TArray<TJumpBeat>;
  ContactRef:TRhythmPlanRef;
  SampleTimes:TArray<Double>;
  SampleHashes:TArray<string>;

  procedure Snapshot(const Name:string;Time:Double);
  begin
    R.Render(Image,Cold,Time,0);
    PNG.Assign(Image);
    PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));
  end;

begin
  Image:=TBitmap.Create;
  PNG:=nil;
  R:=nil;
  try
    R:=TRhythmRenderer.Create;
    R.ConfigureStyle(rsJumpAdventure,Ref,Audio.BossFrequency);
    R.UseD2D:=True;
    Image.PixelFormat:=pf32bit;
    Image.SetSize(960,540);
    PNG:=TPngImage.Create;
    for I:=0 to High(Plan.Stages) do begin
      T:=Plan.Stages[I].StartTime+0.85;
      J:=Plan.Stages[I].Boss;
      if J>=0 then T:=Plan.Nodes[Plan.Bosses[J].LastNode-1].Time;
      R.Render(Image,Audio,T,0);
      S:=FrameHash(Image);
      PNG.Assign(Image);
      PNG.SaveToFile(TPath.Combine(Folder,Format('stage-%.2d.png',[I])));
      R.Render(Image,Cold,Plan.Duration-T,0);
      R.Render(Image,Cold,T+0.25,0,'',1,0,0,0.25);
      Need(FrameHash(Image)=S,'Cold seek/offset pixels');
    end;
    for I:=0 to High(Plan.Legs) do
      if (Plan.Legs[I].Height=0) and (Plan.Nodes[I+1].Time-Plan.Nodes[I].Time>0.3) then begin
        Snapshot('run-arm-swing',Plan.Nodes[I].Time+0.19);
        Break;
      end;
    for I:=1 to High(Plan.Nodes) do
      if Plan.Nodes[I].Landing=jlStomp then begin
        T:=Plan.Nodes[I].Time;
        Snapshot('jump-forward-hand',JumpBlend(Plan.Legs[I-1].Takeoff,T,0.50));
        Snapshot('stomp-before',T-0.018);
        Snapshot('stomp-contact',T);
        Break;
      end;

    // 同じ保存計画から足が触れないアクセントを除いても、画素が変わらない。
    if ParamCount=0 then begin
      FullBeats:=Plan.Beats;
      SetLength(ContactBeats,Length(FullBeats));
      SetLength(SampleTimes,Length(FullBeats));
      J:=0;
      K:=0;
      for I:=0 to High(FullBeats) do
        if FullBeats[I].Node>=0 then begin
          ContactBeats[J]:=FullBeats[I];
          Inc(J);
        end else if I mod 13=0 then begin
          SampleTimes[K]:=FullBeats[I].Time+0.027;
          Inc(K);
        end;
      Need(K>0,'No off-contact accent samples');
      SetLength(ContactBeats,J);
      SetLength(SampleTimes,K);
      SetLength(SampleHashes,K);
      ContactRef:=NewPlanRef(Ref.SourceKey,Ref.Sensitivity,Ref.Direction,Ref.Style,Ref.Variant,
        Ref.AudioDensity,THashSHA2.GetHashString(Ref.Generation+'-contacts'));
      ContactRef.SourceRevision:=Ref.SourceRevision;
      Plan.Beats:=ContactBeats;
      try
        SaveJumpPlan(Plan,Audio,ContactRef);
      finally
        Plan.Beats:=FullBeats;
      end;
      for I:=0 to High(SampleTimes) do begin
        R.Render(Image,Cold,SampleTimes[I],0);
        SampleHashes[I]:=FrameHash(Image);
      end;
      R.ConfigureStyle(rsJumpAdventure,ContactRef,Audio.BossFrequency);
      for I:=0 to High(SampleTimes) do begin
        R.Render(Image,Cold,SampleTimes[I],0);
        Need(FrameHash(Image)=SampleHashes[I],'Off-contact accent changed a frame');
      end;
      WriteLn('Off-contact pixel checks: ',Length(SampleTimes));
      R.ConfigureStyle(rsJumpAdventure,Ref,Audio.BossFrequency);
    end;

    if (ParamCount>=2) and SameText(ParamStr(2),'Scan') then begin
      Image.SetSize(480,270);
      for I:=0 to Ceil(Plan.Duration*30)-1 do begin
        R.Render(Image,Cold,I/30,0);
        Need(R.LastUsedD2D,'Full-course frame rendering');
      end;
      WriteLn('Full-course 30fps frames: ',Ceil(Plan.Duration*30));
    end;
  finally
    R.Free;
    PNG.Free;
    Image.Free;
  end;
end;

var
  Source,Folder:string;
  Audio,Cold:TRhythmAudio;
  Plan,OtherPlan:TJumpPlan;
  Ops:TStyleOperations;
  Context:TStylePrepareContext;
  Ref,OtherRef:TRhythmPlanRef;
  Settings,Restored:TRhythmSettings;
  Span:Double;
  Summary:string;
  I:Integer;
  Different:Boolean;
begin
  Audio:=nil;
  Cold:=nil;
  Plan:=nil;
  OtherPlan:=nil;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');
    if ParamCount>0 then Folder:=TPath.Combine(Folder,'Music');
    ForceDirectories(Folder);
    if ParamCount=0 then begin
      Source:=TPath.Combine(Folder,'source.identity');
      Audio:=SyntheticAudio(Source);
    end else begin
      Source:=ExpandFileName(ParamStr(1));
      Audio:=LoadRhythmAudio(Source,50);
    end;
    Audio.SetBossFrequency(75);
    Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsJumpAdventure,StyleVariant(rsJumpAdventure,50,75),0,Audio.Key);
    Context:=Default(TStylePrepareContext);
    Context.Audio:=Audio;
    Context.Variant:=Ref.Variant;
    Ops:=StyleOperations(rsJumpAdventure);
    Ops.Prepare(Context,Ref,Span,Summary);
    Need(Span=Audio.Duration,'Preview duration');
    OtherRef:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsJumpAdventure,Ref.Variant);
    Ops.Prepare(Context,OtherRef,Span,Summary);
    Need((OtherRef.Generation<>Ref.Generation) and (OtherRef.Key<>Ref.Key) and
      (OtherRef.Digest<>Ref.Digest),'Same track regeneration overwrote the project plan');
    Settings:=TRhythmSettings.Defaults;
    Settings.Style:=rsJumpAdventure;
    Settings.BossFrequency:=75;
    Settings.Music:=Source;
    Settings.Plan:=Ref;
    Need(TRhythmSettings.TryJSON(Settings.ToJSON,Restored) and
      (Restored.Style=rsJumpAdventure) and (Restored.Plan.Digest=Ref.Digest) and
      (Restored.Plan.Generation=Ref.Generation),'Saved settings');
    Cold:=Ops.LoadAudio(Restored.Plan,Source,0);
    Need(Length(Cold.PCM)=0,'Cold restore decoded PCM');
    Plan:=LoadJumpPlan(Restored.Plan,Cold,0);
    OtherPlan:=LoadJumpPlan(OtherRef,Cold,0);
    Different:=Length(OtherPlan.Nodes)<>Length(Plan.Nodes);
    for I:=1 to Min(High(OtherPlan.Nodes),High(Plan.Nodes)) do
      if (OtherPlan.Nodes[I].X<>Plan.Nodes[I].X) or (OtherPlan.Nodes[I].Y<>Plan.Nodes[I].Y) or
        (OtherPlan.Nodes[I].Landing<>Plan.Nodes[I].Landing) then begin
        Different:=True;
        Break;
      end;
    if Audio.Duration>10 then Need(Different,'Regeneration did not vary the route');
    Verify(Plan,Audio,ParamCount=0);
    RenderProof(Plan,Audio,Cold,Ref,Folder);
    WriteLn('Jump adventure PASS checks=',Checks);
  except
    on E:Exception do begin
      WriteLn(E.ClassName,': ',E.Message);
      ExitCode:=1;
    end;
  end;
  OtherPlan.Free;
  Plan.Free;
  Cold.Free;
  Audio.Free;
end.
