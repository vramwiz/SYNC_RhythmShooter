program MiningPlanSmoke;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,System.Math,System.IOUtils,System.Classes,System.Hash,System.JSON,
  Winapi.Windows,Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmMiningPlan in '..\Source\Mining\RhythmMiningPlan.pas',
  RhythmMiningScene in '..\Source\Mining\RhythmMiningScene.pas',
  RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmProduct,RhythmPaths,RhythmAnimation,RhythmImageBank;
var Audio,Meta:TRhythmAudio;Plan,Cold:TMiningPlan;Ref:TRhythmPlanRef;Scene:TMiningAnimation;Renderer:TAnimationRenderer;
  Image:TBitmap;PNG:TPngImage;Report,CaseData:TJSONObject;Cases:TJSONArray;Stream:TMemoryStream;Bytes:TBytes;
  D,Gap,T,Time,MinClear,Diff:Double;I,J,C,Frequency,MaxEnemies,MaxShots,SeenEnemies,SeenShots,LightHits:Integer;
  P,Q:TMiningPoint;H:TMiningHit;S:TMiningShot;Enemy:TMiningEnemy;Boss:TMiningBoss;Source,Stamp,Output,BeforeHash,AfterHash:string;
  Id:TGUID;Info:TWin32FileAttributeData;Rejected:Boolean;
procedure Need(Value:Boolean;const Why:string);begin if not Value then raise Exception.Create(Why);end;
function FrameHash:string;
var Hash:THashSHA2;
begin Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;Stream.ReadBuffer(Bytes[0],Length(Bytes));Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;finally Stream.Free;end;end;
procedure RenderShot(Time:Double;const Name:string);
begin Renderer.Render(Image,Time,0);PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Output,Name+'.png'));finally PNG.Free;end;end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Cold:=nil;Renderer:=nil;Image:=nil;Report:=TJSONObject.Create;
  try
    ConfigureRhythmProduct('SYNC_RhythmMining','Mining verification',rsMining);
    Output:=TPath.Combine(ExtractFilePath(ParamStr(0)),'Evidence');ForceDirectories(Output);Cases:=TJSONArray.Create;Report.AddPair('cases',Cases);
    Need((StyleId(rsMining)='mining') and (StylePlanVersion(rsMining)=1),'Mining style registration');
    for C:=0 to 7 do begin
      case C of 0:begin D:=18;Gap:=0.18;Frequency:=0;end;1:begin D:=175;Gap:=0.26;Frequency:=50;end;2:begin D:=90;Gap:=0.008;Frequency:=100;end;3:begin D:=3000;Gap:=1.10;Frequency:=0;end;4:begin D:=0.12;Gap:=0.008;Frequency:=50;end;6:begin D:=240;Gap:=45;Frequency:=100;end;7:begin D:=30;Gap:=1;Frequency:=0;end;else begin D:=1;Gap:=1;Frequency:=50;end;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=D;Audio.Sensitivity:=50;Audio.Key:=THashSHA2.GetHashString('mining-smoke-'+IntToStr(C));
      SetLength(Audio.Envelope,Ceil(D*100));for I:=0 to High(Audio.Envelope) do begin Audio.Envelope[I]:=0.65;if (I div 1000) mod 3=2 then Audio.Envelope[I]:=0.025;end;
      Audio.SoundEnd:=D;if C=5 then begin Audio.SoundEnd:=0;SetLength(Audio.Envelope,0);end;
      if (C<5) or (C=6) then begin SetLength(Audio.Hits,Floor((D-0.01)/Gap)+1);for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=I*Gap;Audio.Hits[I].Strength:=0.3+(I mod 8)*0.1;end;end;
      Audio.SetBossFrequency(Frequency);CreateGUID(Id);Source:=TPath.Combine(CacheFolder,GUIDToString(Id)+'.identity');TFile.WriteAllText(Source,'mining deterministic source');Audio.Source:=Source;
      Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Info),'Source stamp');Stamp:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);Audio.SourceRevision:=Stamp;
      Plan:=TMiningPlan.Build(Audio);Need(Plan.PulseCount=Length(Audio.Hits),'Lost source accents');Need((Plan.Count<=20000) and (Plan.EnemyCount<=14000) and (Plan.ShotCount<=80000),'Actor budgets');if Frequency=0 then Need(Plan.BossCount=0,'Boss slider zero');
      if C=1 then Need(Plan.BossCount>0,'No periodic mining boss');if C=5 then Need((Plan.Count=0) and (Plan.EndTime=0) and (Plan.EnemyCount=0),'Silence');
      if C=0 then begin Rejected:=False;try Cold:=TMiningPlan.Build(Audio,function:Boolean begin Result:=True;end);except on EAbort do Rejected:=True;end;Need(Rejected and (Cold=nil),'Preparation cancellation ignored');end;
      MinClear:=1E9;
      for I:=0 to Plan.PulseCount-1 do begin Need(Plan.Pulse[I].Time=Audio.Hits[I].Time,'Audio clock changed');H:=Plan.Hit[Plan.Pulse[I].Event];P:=Plan.ActorAt(Plan.Pulse[I].Time);Need((P.Y+MINING_TIP>=H.Top-1E-7) and (P.Y+MINING_TIP<=H.Bottom+1E-7),'Drill misses material');Need(Abs(P.X-H.X)<MINING_HALF,'Horizontal miss');end;
      for I:=0 to Plan.EnemyCount-1 do begin Enemy:=Plan.Enemy[I];if not Enemy.Ambient then begin P:=Plan.EnemyAt(I,Enemy.Hit);Q:=Plan.ActorAt(Enemy.Hit);Need(Abs(P.Y-0.025-Q.Y-MINING_TIP)<1E-7,'Enemy face not on bit');end;end;
      LightHits:=0;for I:=0 to Plan.ShotCount-1 do begin S:=Plan.Shot[I];if S.Hit then begin Inc(LightHits);P:=Plan.ActorAt(S.Impact);Need(Abs(MiningHullDistance(S.B,P)-S.Radius)<0.001,'Light hit is not on armor');end
        else for J:=0 to 160 do begin Time:=S.Launch+(S.Impact-S.Launch)*J/160;P:=Plan.ShotAt(I,Time);Q:=Plan.ActorAt(Time);Diff:=MiningHullDistance(P,Q)-S.Radius;Need(Diff>0,'Unplanned projectile contact');MinClear:=Min(MinClear,Diff);end;
      end;
      for I:=0 to Plan.BossCount-1 do begin Boss:=Plan.Boss[I];Need(Plan.HealthAt(I,Boss.Kill)=0,'Boss survives final audio hit');Need(Boss.Kill=Plan.Pulse[Boss.LastPulse].Time,'Boss kill off accent');for J:=Boss.FirstPulse to Boss.LastPulse do begin P:=Plan.ActorAt(Plan.Pulse[J].Time);Need(Abs(Plan.BossTop(I,Plan.Pulse[J].Time)-P.Y-MINING_TIP)<1E-7,'Boss contact off bit');end;end;
      Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsMining,StyleVariant(rsMining,50,Frequency));Ref.SourceRevision:=Stamp;Plan.Save(Ref,Audio);
      Meta:=TMiningPlan.LoadAudioMetadata(Ref,Source,0);Need((Length(Meta.PCM)=0) and (Length(Meta.Envelope)=0),'Cold restore reads audio PCM');Need(Meta.BossFrequency=Frequency,'Cold frequency lost');Cold:=TMiningPlan.Load(Ref,Meta,0);
      if C=0 then begin FreeAndNil(Cold);Rejected:=False;try Cold:=TMiningPlan.Load(Ref,Meta,1);except on E:Exception do Rejected:=True;end;Need(Rejected and (Cold=nil),'Wrong direction accepted');Cold:=TMiningPlan.Load(Ref,Meta,0);end;
      Need((Cold.Count=Plan.Count) and (Cold.ShotCount=Plan.ShotCount) and (Cold.EnemyCount=Plan.EnemyCount),'JSON counts changed');
      for I:=0 to 127 do begin T:=(Plan.EndTime+2)*((I*73) mod 131)/131;P:=Plan.ActorAt(T);Q:=Cold.ActorAt(T);Need((Abs(P.X-Q.X)<1E-9) and (Abs(P.Y-Q.Y)<1E-9),'Seek changed path');Need(Abs(Plan.ZoomAt(T)-Cold.ZoomAt(T))<1E-9,'Seek changed camera');end;
      Scene:=TMiningAnimation.Create;Scene.Audio:=Audio;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);
      Time:=Min(5.4,Audio.SoundEnd*0.45);Renderer.Render(Image,Time,0);BeforeHash:=FrameHash;Renderer.Render(Image,Plan.EndTime+10,0);Renderer.Render(Image,Time,0);AfterHash:=FrameHash;Need(BeforeHash=AfterHash,'Frame history dependence');Need(Renderer.DesignWarning='','Render error');
      if C=0 then begin RenderShot(4.8,'mining-normal');Image.SetSize(720,1280);RenderShot(4.8,'mining-portrait');Image.SetSize(1280,720);end;
      if C=1 then begin Boss:=Plan.Boss[0];RenderShot(Boss.Start+3.2,'mining-boss');RenderShot((Boss.Start+Boss.Kill)/2,'mining-boss-purge');RenderShot(Boss.Kill+0.22,'mining-boss-kill');end;
      if C=2 then RenderShot(12.2,'mining-dense');
      Renderer.Render(Image,Plan.EndTime+1,0);BeforeHash:=FrameHash;Renderer.Render(Image,Plan.EndTime+30,0);Need(BeforeHash=FrameHash,'Terminal scene keeps moving');FreeAndNil(Renderer);FreeAndNil(Image);
      Scene:=TMiningAnimation.Create;Scene.Audio:=Meta;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);Renderer.Render(Image,Time,0);Need(FrameHash=AfterHash,'Cold rendered frame differs');FreeAndNil(Renderer);FreeAndNil(Image);
      // Count actual viewport intersections, not only scheduled/live objects.
      MaxEnemies:=0;MaxShots:=0;for I:=0 to 399 do begin Time:=Audio.SoundEnd*I/400;SeenEnemies:=0;SeenShots:=0;
        for J:=Max(0,Plan.EnemyBefore(Time-3.1)) to Plan.EnemyBefore(Time) do if (Time>=Plan.Enemy[J].First) and (Time<Plan.Enemy[J].Last) then begin
          P:=Plan.EnemyAt(J,Time);if (P.Y-Plan.DepthAt(Time)>=-0.03) and (P.Y-Plan.DepthAt(Time)<=1.03) and (P.X>=-0.04) and (P.X<=1.64) then Inc(SeenEnemies);
        end;
        for J:=Max(0,Plan.ShotBefore(Time-1.55)) to Plan.ShotBefore(Time) do if (Time>=Plan.Shot[J].Launch) and (Time<Plan.Shot[J].Finish) then begin
          P:=Plan.ShotAt(J,Time);if (P.Y-Plan.DepthAt(Time)>=-0.03) and (P.Y-Plan.DepthAt(Time)<=1.03) and (P.X>=-0.04) and (P.X<=1.64) then Inc(SeenShots);
        end;
        MaxEnemies:=Max(MaxEnemies,SeenEnemies);MaxShots:=Max(MaxShots,SeenShots);
      end;
      CaseData:=TJSONObject.Create;Cases.AddElement(CaseData);CaseData.AddPair('case',TJSONNumber.Create(C));CaseData.AddPair('duration',TJSONNumber.Create(D));CaseData.AddPair('pulses',TJSONNumber.Create(Plan.PulseCount));CaseData.AddPair('cuts',TJSONNumber.Create(Plan.Count));CaseData.AddPair('bosses',TJSONNumber.Create(Plan.BossCount));CaseData.AddPair('enemies',TJSONNumber.Create(Plan.EnemyCount));CaseData.AddPair('shots',TJSONNumber.Create(Plan.ShotCount));CaseData.AddPair('lightHits',TJSONNumber.Create(LightHits));CaseData.AddPair('maxEnemies',TJSONNumber.Create(MaxEnemies));CaseData.AddPair('maxShots',TJSONNumber.Create(MaxShots));CaseData.AddPair('minClearance',TJSONNumber.Create(MinClear));
      Writeln('Mining case ',C,' ',Plan.Count,' cuts, ',Plan.EnemyCount,' enemies, ',Plan.ShotCount,' attacks, ',Plan.BossCount,' bosses');
      FreeAndNil(Plan);FreeAndNil(Cold);FreeAndNil(Audio);FreeAndNil(Meta);
    end;
    Report.AddPair('native',TJSONBool.Create(True));Report.AddPair('build',TJSONBool.Create(True));Report.AddPair('coldPCM',TJSONBool.Create(False));Report.AddPair('seeks',TJSONNumber.Create(8*128));Report.AddPair('sourceClockError',TJSONNumber.Create(0));TFile.WriteAllText(TPath.Combine(Output,'Mining-results.json'),Report.ToJSON,TEncoding.UTF8);Writeln('MiningPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  Renderer.Free;Image.Free;Plan.Free;Cold.Free;Audio.Free;Meta.Free;Report.Free;
end.
