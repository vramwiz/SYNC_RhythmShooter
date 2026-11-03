program RacePlanSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.JSON,System.Hash,System.IOUtils,
  Vcl.Graphics,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmPreparedData,RhythmProduct,RhythmPaths,RhythmSettings,
  RhythmRacePlan,RhythmRaceCrash,RhythmRaceScene,RhythmAnimation,RhythmImageBank,RhythmRaceCrashScene,RhythmRenderSurface;
var Audio,Meta:TRhythmAudio;Plan,Cold,BadPlan:TRacePlan;D:TRaceCrashPlan;Ref,Bad:TRhythmPlanRef;
  Image:TBitmap;Renderer:TAnimationRenderer;Scene:TRaceAnimation;Root,Other:TJSONObject;State,Loaded:TRhythmSettings;
  Source,Revision,Folder,Serialized,Expected:string;Stamp:TWin32FileAttributeData;
  C,I,J,N,Frequency,Contacts,TrafficChecks,BossChecks,SeekChecks,SideHits,LargeHits,ShuntChecks,StraightCars,TurningCars:Integer;
  Duration,Audible,Gap,T,Previous,Z,Clearance:Double;H:TCrashHit;E:TCrashEnemy;V:TCrashTraffic;P,Q:TCrashPose;Projected:TCrashProjection;Rejected:Boolean;S:TCrashShunt;SavedKeys:TArray<TCrashKey>;LaneProbe:Double;
procedure Need(V:Boolean;const Why:string);begin if not V then raise Exception.Create(Why);end;
function ImageHash:string;
var M:TMemoryStream;B:TBytes;Hash:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(B,M.Size);M.Position:=0;if Length(B)>0 then M.ReadBuffer(B[0],Length(B));Hash:=THashSHA2.Create;Hash.Update(B);Result:=Hash.HashAsString;finally M.Free;end;end;
// 近端を後端だけが越えた長いトラックは、残るキャビンまで消してはいけない。
procedure NearTruckView;
var D:TRaceCrashPlan;Surface:TAnimationRenderSurface;Backend,Step,X,Y,Visible:Integer;Pixel:PByte;Clock:Double;
  procedure Frame(T:Double);
  begin
    Surface.BeginFrame(Image);DrawRaceCrash(D,Surface,T,Image.Width,Image.Height);
    Need(Surface.EndFrame,'Near truck frame');
    if Backend=1 then Need(Surface.LastUsedD2D,'Near truck D2D');
  end;
begin
 D:=TRaceCrashPlan.Create;Surface:=nil;
 try
  D.Version:=11;D.Duration:=10;D.SoundEnd:=9;D.EndTime:=10;D.Goal:=9;D.Acceleration:=1;D.TopSpeed:=150;
  SetLength(D.Traffic,1);
  with D.Traffic[0] do begin Spawn:=0.5;Clear:=5;Pass:=2;RelativeSpeed:=100;Width:=0.15;
   HalfLength:=14;Kind:=3;NearLane:=0.70;FarLane:=0.70;Shunt:=-1;end;
  Image.SetSize(1280,800);Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create([],0));
  for Backend:=0 to 1 do begin Surface.UseD2D:=Backend=1;
   for Step:=0 to 1 do begin Clock:=2.20+Step*0.10;Frame(Clock);Expected:=ImageHash;Visible:=0;
    for Y:=450 to 799 do begin Pixel:=Image.ScanLine[Y];Inc(Pixel,900*4);
     for X:=900 to 1259 do begin
      if (Pixel[2]>50) and (Abs(Integer(Pixel[2])-Pixel[1])<50) then Inc(Visible);Inc(Pixel,4);
     end;
    end;
    Need(Visible>3000,'Near truck front disappeared with rear clipping');
    Frame(4);Frame(Clock);Need(ImageHash=Expected,'Near truck return seek');
   end;
  end;
  Writeln('Near truck clipping PASS GDI/D2D frames=4 returnSeek=4');
 finally Surface.Free;D.Free;Image.SetSize(960,600);end;
end;
// 損傷前と同じ姿勢を使い、傷が車体の外の空中へ描かれないことを確認する。
procedure DamageSurfaceView;
var D:TRaceCrashPlan;Surface:TAnimationRenderSurface;Mask:array of Byte;
  Backend,Pass,I,X,Y,DX,DY,N:Integer;Pixel:PByte;Covered:Boolean;
  procedure Frame;
  begin Surface.BeginFrame(Image);DrawRaceCrash(D,Surface,1.8,Image.Width,Image.Height);
   Need(Surface.EndFrame,'Damage frame');GdiFlush;
   if Backend=1 then Need(Surface.LastUsedD2D,'Damage D2D');end;
begin
 D:=TRaceCrashPlan.Create;Surface:=nil;Image.SetSize(1280,800);SetLength(Mask,1280*800);
 try
  D.Version:=11;D.Duration:=20;D.EndTime:=20;D.SoundEnd:=19;D.Goal:=19;D.Acceleration:=1;D.TopSpeed:=150;
  SetLength(D.Enemies,1);SetLength(D.Hits,5);
  with D.Enemies[0] do begin Spawn:=0;Ready:=1;Kill:=10;Clear:=11;First:=0;Last:=4;
   Kind:=0;Width:=0.12;HalfLength:=6;Boss:=-1;end;
  Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create([],0));
  for Backend:=0 to 1 do begin Surface.UseD2D:=Backend=1;
   for Pass:=0 to 1 do begin
    for I:=0 to 4 do D.Hits[I].Time:=100-Pass*99;
    Frame;N:=0;
    for Y:=0 to 799 do begin Pixel:=Image.ScanLine[Y];
     for X:=0 to 1279 do begin
      if Pass=0 then Mask[Y*1280+X]:=Ord((Pixel[2]<>7) or (Pixel[1]<>13) or (Pixel[0]<>29))
      else if (Pixel[2]<>7) or (Pixel[1]<>13) or (Pixel[0]<>29) then begin Covered:=False;
       for DY:=-2 to 2 do for DX:=-2 to 2 do
        if (X+DX>=0) and (X+DX<1280) and (Y+DY>=0) and (Y+DY<800) then
         Covered:=Covered or (Mask[(Y+DY)*1280+X+DX]<>0);
       if not Covered then Inc(N);
      end;
      Inc(Pixel,4);
     end;
    end;
    if Pass=1 then Need(N=0,'Damage line floated outside vehicle silhouette');
   end;
  end;
  Writeln('Damage surface attachment PASS backends=GDI,D2D');
 finally Surface.Free;D.Free;Image.SetSize(960,600);end;
end;
// 旧プランへ新しい接触寸法を後付けせず、元の自車寸法で復元する。
procedure LegacyCrash8To10(P:TRaceCrashPlan;A:TRhythmAudio);
var J,C:TJSONObject;R:TRhythmPlanRef;M:TRhythmAudio;Old:TRacePlan;Version,I:Integer;Bits:UInt64;D:Double;SourceKey:string;
begin
 for Version:=8 to 10 do begin
  if Version=10 then J:=TJSONObject.ParseJSONValue(TFile.ReadAllText('Tests/Fixtures/Race-v10.json',TEncoding.UTF8)) as TJSONObject
  else J:=TJSONObject.ParseJSONValue(TFile.ReadAllText('Tests/Fixtures/Race-v9.json',TEncoding.UTF8)) as TJSONObject;
  try
   C:=J.GetValue<TJSONObject>('crash');SourceKey:=J.GetValue<string>('source');
   R:=NewPlanRef(SourceKey,50,0,rsRace);R.Version:=Version;R.SourceRevision:=A.SourceRevision;
   Need(TryStrToUInt64('$'+C.GetValue<TJSONArray>('meta').Items[0].GetValue<TJSONArray>.Items[7].Value,Bits),'Legacy frequency bits');Move(Bits,D,8);R.Variant:=Round(D)+1;
   R.Key:=THashSHA2.GetHashString('race-v'+IntToStr(Version)+'|'+SourceKey+'|50|0|variant='+IntToStr(R.Variant));
   J.RemovePair('version').Free;J.AddPair('version',TJSONNumber.Create(Version));J.RemovePair('key').Free;J.AddPair('key',R.Key);
   J.RemovePair('layout').Free;J.AddPair('layout','crash-highway-v'+IntToStr(Version));
   C.RemovePair('policy').Free;C.AddPair('policy','inverse-ram-traffic-v'+IntToStr(Version));
   if Version=8 then C.RemovePair('shunts').Free;
   WritePreparedData(J,R);
  finally J.Free;end;
  M:=TRacePlan.LoadAudioMetadata(R,A.Source,0);try Old:=TRacePlan.Load(R,M,0);try
   Need(Old.Version=Version,'Legacy version changed');
   if Version=10 then Need(Abs(Old.Crash.HeroScale-0.90)<1E-12,'Legacy v10 dimensions changed')
   else Need(Old.Crash.HeroScale=1,'Legacy v8/v9 dimensions changed');
   if Version=8 then Need(Length(Old.Crash.Shunts)=0,'Legacy v8 got new shunts');
  finally Old.Free;end;finally M.Free;end;
 end;
end;
procedure Legacy;
var Version,Variant:Integer;R:TRhythmPlanRef;A:TJSONArray;J:TJSONObject;Speed,FinalDistance:Double;
  procedure Num(const Name:string;Value:Double);begin if Frac(Value)=0 then Root.AddPair(Name,TJSONNumber.Create(Trunc(Value))) else Root.AddPair(Name,TJSONNumber.Create(Value));end;
  procedure Key(Time,Value:Double);begin J:=TJSONObject.Create;A.AddElement(J);J.AddPair('position',TJSONNumber.Create(Time));J.AddPair('value',TJSONNumber.Create(Value));end;
begin
  for Version:=1 to 7 do begin
    Writeln('Legacy v',Version);
    Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Duration:=1;Audio.SoundEnd:=0;Audio.Sensitivity:=50;Audio.Key:=THashSHA2.GetHashString('Race legacy '+IntToStr(Version));Variant:=1;if Version=1 then Variant:=0;
    R:=NewPlanRef(Audio.Key,50,0,rsRace,Variant);R.Version:=Version;R.SourceRevision:=Revision;Serialized:='race-v'+IntToStr(Version)+'|'+Audio.Key+'|50|0';if Variant<>0 then Serialized:=Serialized+'|variant='+IntToStr(Variant);R.Key:=THashSHA2.GetHashString(Serialized);
    Root:=TJSONObject.Create;try Num('schema',1);Root.AddPair('style','race');Num('version',Version);Root.AddPair('layout','rear-road-v'+IntToStr(Version));Root.AddPair('key',R.Key);Root.AddPair('source',R.SourceKey);Num('sensitivity',50);Num('direction',0);AddPreparedAudio(Root,Audio);Num('launch',0.1);Num('acceleration',0.1);Num('goal',0.85);Num('end',1);Speed:=90;if Version>=3 then Speed:=150;Num('topSpeed',Speed);Num('excluded',0);FinalDistance:=Speed*(0.05+0.65+0.075);Num('distance',FinalDistance);Num('bossFrequency',0);if Version=1 then Num('bossFrequencyLegacy',100);
      if Version>=3 then begin Num('focus',40);Root.AddPair('scoring','metal-100-50-10-v1');Num('totalScore',0);end;
      if Version>=4 then begin Root.AddPair('posePolicy','curvature-lag-v1');case Version of 4:Root.AddPair('trafficPolicy','dense-overtake-v1');5:Root.AddPair('trafficPolicy','convoy-overtake-v2');6:Root.AddPair('trafficPolicy','dynamic-contact-v3');7:Root.AddPair('trafficPolicy','fender-contact-v4');end;end;
      Root.AddPair('events',TJSONArray.Create);Root.AddPair('coins',TJSONArray.Create);Root.AddPair('traffic',TJSONArray.Create);Root.AddPair('trailers',TJSONArray.Create);Root.AddPair('bombs',TJSONArray.Create);
      A:=TJSONArray.Create;Root.AddPair('lanes',A);Key(0,0);Key(1,0);A:=TJSONArray.Create;Root.AddPair('road',A);Key(0,0);Key(3000,0);WritePreparedData(Root,R);
    finally Root.Free;Root:=nil;end;
    Meta:=TRacePlan.LoadAudioMetadata(R,Source,0);Cold:=TRacePlan.Load(R,Meta,0);Need((Cold.Version=Version) and (Cold.Crash=nil) and (Length(Meta.PCM)=0),'Legacy1..7 reader');FreeAndNil(Cold);FreeAndNil(Meta);FreeAndNil(Audio);
  end;
end;
begin
  try
    ConfigureRhythmProduct('SYNC_RhythmRace','Race v9 native',rsRace);Need(StylePlanVersion(rsRace)=11,'v11 style');for I:=1 to 10 do Need(CompatiblePlanVersion(rsRace,I),'Legacy version');Need((CompatiblePlanVersion(rsRunner,6)) and (StylePlanVersion(rsFighting)=2),'Other completed styles changed');
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'CrashEvidence');ForceDirectories(Folder);Source:=TPath.Combine(Folder,'source.identity');TFile.WriteAllText(Source,'Synthetic Race v9 identity; no audio playback',TEncoding.UTF8);Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stat');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);Legacy;
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(960,600);
    NearTruckView;
    DamageSurfaceView;
    Contacts:=0;TrafficChecks:=0;BossChecks:=0;SeekChecks:=0;SideHits:=0;LargeHits:=0;ShuntChecks:=0;StraightCars:=0;TurningCars:=0;
    for C:=0 to 15 do begin
      Writeln('Case ',C);
      Duration:=96;Gap:=0.18;Frequency:=50;case C of 0:begin Duration:=0.1;Gap:=0.01;end;1:Duration:=2;2:begin Duration:=8;Gap:=0.5;end;3:Duration:=32;4:Duration:=180;5:begin Duration:=180;Frequency:=0;end;6:begin Duration:=3000;Gap:=0.16;end;7:begin Duration:=16;Gap:=0.005;end;8:Gap:=1.1;9:begin Duration:=420;Frequency:=100;Gap:=0.20;end;10:begin Gap:=0.001;Frequency:=100;end;11:begin Duration:=1;Frequency:=0;end;12:Gap:=8;13:Duration:=32;14:begin Duration:=3000;Gap:=0.20;Frequency:=100;end;15:Duration:=150;end;Audible:=Duration;if C=11 then Audible:=0;if C=15 then Audible:=96;
      Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Key:=THashSHA2.GetHashString('Race v8 '+IntToStr(C));Audio.Sensitivity:=50;Audio.Duration:=Duration;Audio.SoundEnd:=Audible;Audio.SetBossFrequency(Frequency);SetLength(Audio.Envelope,Ceil(Duration*100));for I:=0 to High(Audio.Envelope) do if I*0.01<Audible then Audio.Envelope[I]:=0.5;
      SetLength(Audio.Hits,100000);N:=0;T:=0.005;if Audible>0 then while (T<Audible-0.005) and (N<99999) do begin Audio.Hits[N].Time:=T;Audio.Hits[N].Strength:=0.25+(N mod 6)*0.15;Inc(N);if (C=13) and (N mod 5=0) then begin Audio.Hits[N]:=Audio.Hits[N-1];Audio.Hits[N].Strength:=1;Inc(N);end;T:=T+Gap;end;SetLength(Audio.Hits,N);
      Plan:=TRacePlan.Build(Audio);D:=Plan.Crash;Need((D<>nil) and (Plan.Version=11) and (Plan.Count=0),'v8 must not generate coins');D.Validate;Need(Length(D.Events)=Length(Audio.Hits),'Lost original accents');Need((Plan.GoalTime<Plan.EndTime) and (Plan.EndTime<=Audio.Duration),'Goal reservation');if Frequency=0 then Need(Length(D.Bosses)=0,'Boss frequency zero');
      Previous:=-1;for I:=0 to 200 do begin T:=D.EndTime*I/200;Need(D.DistanceAt(T)>=Previous,'Reverse driving');Previous:=D.DistanceAt(T);Need(Abs(D.LaneVelocity(T))<=0.975+1E-7,'Teleport lane speed');end;
      for I:=0 to High(D.Hits) do begin H:=D.Hits[I];E:=D.Enemies[H.Enemy];P:=D.EnemyAt(H.Enemy,H.Time);Q:=D.HeroAt(H.Time);Need(H.Time=Audio.Hits[H.Source].Time,'Original collision clock shifted');if E.Side=0 then Need(Abs(P.Distance-P.Back-Q.Distance-Q.Front)<1E-6,'Actual front bumper misses') else begin Need(Abs(Abs(P.Lane-Q.Lane)-P.Width-Q.Width)<1E-7,'Actual fender misses');Inc(SideHits);end;Need(H.HP=E.Last-I,'HP monotonicity');if E.Kind>0 then Inc(LargeHits);Inc(Contacts);
        for J:=0 to 3 do begin T:=E.Ready-Power(10,-J-1);if T<E.Spawn then Continue;P:=D.EnemyAt(H.Enemy,T);Q:=D.HeroAt(T);Need((P.Distance-P.Back>Q.Distance+Q.Front) or (Abs(P.Lane-Q.Lane)>P.Width+Q.Width),'Premature first collision');end;
      end;
      for I:=0 to High(D.Traffic) do begin V:=D.Traffic[I];Need(D.TrafficCertified(I),'Whole-interval traffic certificate');for J:=0 to 48 do begin T:=V.Spawn+(V.Clear-V.Spawn)*J/48;P:=D.TrafficAt(I,T);Q:=D.HeroAt(T);Z:=P.Distance-Q.Distance;Clearance:=Abs(P.Lane-Q.Lane)-P.Width-Q.Width;Need(not ((Z-P.Back<Q.Front) and (Z+P.Front> -Q.Back) and (Clearance<=0)),'General car collision');Inc(TrafficChecks);end;T:=V.Pass;P:=D.TrafficRoadAt(I,T);Need(Abs(P.Lane-D.LaneAt(T))-P.Width-D.HeroWidth>=V.Gap-1E-8,'Close pass gap');Projected:=D.Project(P.Distance,P.Lane,T,0);Need(Projected.Visible,'Passing car disappeared');end;
      for I:=0 to High(D.Traffic) do begin
        V:=D.Traffic[I];if V.TurnFinish>V.TurnStart then begin
          Inc(TurningCars);Need((V.TurnFinish-V.TurnStart>=0.179) and (V.TurnFinish-V.TurnStart<=0.271),'Late turn span');
          Need(Abs(D.TrafficLaneVelocity(I,V.TurnStart))<1E-12,'Turn start derivative');
          Need(Abs(D.TrafficLaneVelocity(I,V.TurnFinish))<1E-12,'Turn end derivative');
          Need(Abs(D.TrafficLaneAt(I,V.TurnStart-1E-7)-D.TrafficLaneAt(I,V.TurnStart+1E-7))<1E-6,'Turn start jump');
          Need(Abs(D.TrafficLaneAt(I,V.TurnFinish-1E-7)-D.TrafficLaneAt(I,V.TurnFinish+1E-7))<1E-6,'Turn end jump');
        end else begin Inc(StraightCars);Need(D.TrafficLaneAt(I,V.Spawn)=D.TrafficLaneAt(I,V.Clear),'Straight traffic follows hero');end;
      end;
      if Length(D.Traffic)>0 then begin
        T:=D.Traffic[0].Pass;LaneProbe:=D.TrafficRoadAt(0,T).Lane;SavedKeys:=Copy(D.Keys);
        for I:=0 to High(D.Keys) do D.Keys[I].Value:=D.Keys[I].Value+0.10;
        Need(D.TrafficRoadAt(0,T).Lane=LaneProbe,'Traffic uses current hero lane');D.Keys:=SavedKeys;
      end;
      Need(Abs(D.HeroScale-0.75)<1E-12,'Hero scale');
      for I:=0 to High(D.Shunts) do begin
        S:=D.Shunts[I];Need(D.Traffic[S.Traffic].Shunt=I,'Unique shunt index');
        P:=D.TrafficRoadAt(S.Traffic,S.Time);Q:=D.EnemyAt(S.Enemy,S.Time);
        Z:=Max(Abs(P.Lane-Q.Lane)-P.Width-Q.Width,Max(P.Distance-P.Back-Q.Distance-Q.Front,Q.Distance-Q.Back-P.Distance-P.Front));
        Need(Abs(Z)<2E-6,'Boss contact does not meet body');
        for J:=0 to 40 do begin T:=S.Time+0.85*J/40;P:=D.TrafficAt(S.Traffic,T);Q:=D.HeroAt(T);
          Need(not P.Alive,'Destroyed traffic reappears');
          Need(not ((P.Distance-P.Back<Q.Distance+Q.Front) and (P.Distance+P.Front>Q.Distance-Q.Back) and (Abs(P.Lane-Q.Lane)<=P.Width+Q.Width)),'Shunt crosses hero');
        end;
        P:=D.TrafficAt(S.Traffic,S.Time-1E-7);Need(P.Alive,'Traffic breaks before contact');
        P:=D.TrafficAt(S.Traffic,S.Time+0.2);Need((Abs(P.Turn)>0) and (P.Lift>0),'Traffic lacks throw/spin');Inc(ShuntChecks);
      end;
      for I:=0 to High(D.Bosses) do begin E:=D.Enemies[D.Bosses[I].Enemy];Need((E.Last>E.First) and (D.Hits[E.Last].HP=0) and (D.Hits[E.Last].Time=D.Bosses[I].Kill),'Boss final strike');P:=D.EnemyAt(D.Bosses[I].Enemy,E.Kill+0.20);Need(not P.Alive,'Boss acts after defeat');Need(Abs(P.Turn)>0,'Boss does not roll');Inc(BossChecks);end;
      if Length(D.Enemies)>0 then Need(D.Enemies[High(D.Enemies)].Kind>=3,'Weak finale');
      Ref:=NewPlanRef(Audio.Key,50,0,rsRace,Frequency+1);Ref.SourceRevision:=Revision;Plan.Save(Ref,Audio);Root:=D.ToJSON;try Serialized:=Root.ToJSON;finally Root.Free;Root:=nil;end;Meta:=TRacePlan.LoadAudioMetadata(Ref,Source,0);Need((Length(Meta.PCM)=0) and (Length(Meta.Envelope)=0),'PCM-free restore');Cold:=TRacePlan.Load(Ref,Meta,0);Other:=Cold.Crash.ToJSON;try Need(Other.ToJSON=Serialized,'Saved binary64 plan changed');finally Other.Free;end;
      State:=TRhythmSettings.Defaults;State.Style:=rsRace;State.Music:=Source;State.Plan:=Ref;State.BossFrequency:=Frequency;Need(TRhythmSettings.TryJSON(State.ToJSON,Loaded) and (Loaded.Plan.Key=Ref.Key),'v8 settings reference');
      for I:=0 to 63 do begin T:=D.EndTime*((I*37) mod 67)/67;P:=D.HeroAt(T);Q:=Cold.Crash.HeroAt(T);Need((P.Distance=Q.Distance) and (P.Lane=Q.Lane),'Seek changes route');Inc(SeekChecks);end;Bad:=Ref;Bad.Digest:=StringOfChar('0',64);Rejected:=False;try BadPlan:=TRacePlan.Load(Bad,Meta,0);except Rejected:=True;end;FreeAndNil(BadPlan);Need(Rejected,'Corrupt digest accepted');
      if C in [3,4,9] then begin Scene:=TRaceAnimation.Create;Scene.Audio:=Meta;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;Image.SetSize(720,1280);Renderer.Render(Image,D.Goal*0.5,0);Image.SetSize(960,600);T:=D.Goal*0.6;Renderer.Render(Image,T,0);Expected:=ImageHash;Renderer.Render(Image,D.EndTime,0);Renderer.Render(Image,T,0);Need((Scene.Notice='') and (Expected=ImageHash),'Preview random seek');FreeAndNil(Renderer);end;
      if C=3 then LegacyCrash8To10(D,Audio);
      FreeAndNil(Cold);FreeAndNil(Meta);FreeAndNil(Plan);FreeAndNil(Audio);
    end;
    Need(StraightCars>2*TurningCars,'Too many steering cars');Need(ShuntChecks>0,'No boss traffic contacts');Need((Contacts>0) and (SideHits>0) and (LargeHits>0) and (BossChecks>0) and (TrafficChecks>0),'Coverage incomplete');Writeln(Format('Race v11 PASS contacts=%d side=%d large=%d bosses=%d trafficChecks=%d seek=%d shunts=%d straight=%d turning=%d',[Contacts,SideHits,LargeHits,BossChecks,TrafficChecks,SeekChecks,ShuntChecks,StraightCars,TurningCars]));
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Renderer.Free;Image.Free;BadPlan.Free;Cold.Free;Plan.Free;Meta.Free;Audio.Free;
end.
