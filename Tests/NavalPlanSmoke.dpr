program NavalPlanSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.IOUtils,System.Hash,System.JSON,System.Diagnostics,
  Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmAudio,RhythmNavalPlan,RhythmNavalScene,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmPaths,
  RhythmAnimation,RhythmImageBank;
var Audio,Meta:TRhythmAudio;Plan,Cold:TNavalPlan;Scene:TNavalAnimation;Renderer:TAnimationRenderer;Image:TBitmap;PNG:TPngImage;
  Ref,BadRef:TRhythmPlanRef;Info:TWin32FileAttributeData;ID:TGUID;Path,OutDir,Hash,WarmHash:string;Rejected,UsedD2D:Boolean;
  C,I,J,Frequency,TotalHits,TotalShots,TotalSeeks,Glances,Intercepts,Frames,Active,PeakShots,PeakShips,LateShots:Integer;
  Duration,Gap,T,Launch,Finish,Arc,Error,MaxError,DX,DY,Aim,Zoom,Zoom2,MinClear,Clear,ClockError,MaxClockError,BuildMS,WarmGDI,WarmD2D:Double;
  A,B,P,Q,H,Camera,Camera2:TNavalPoint;Hit:TNavalHit;Shot:TNavalShot;Ship:TNavalShip;
  Seen:TArray<Boolean>;SeenModes:array[0..2] of Boolean;Timer:TStopwatch;Elapsed,MaxFrame:Double;Results,Row:TJSONObject;Rows:TJSONArray;
procedure Need(Value:Boolean;const Msg:string);begin if not Value then raise Exception.Create(Msg);end;
function ImageHash:string;
var Stream:TMemoryStream;Bytes:TBytes;D:THashSHA2;
begin Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;Stream.ReadBuffer(Bytes[0],Length(Bytes));D:=THashSHA2.Create;D.Update(Bytes);Result:=D.HashAsString;finally Stream.Free;end;end;
procedure MakeAudio(Duration,Gap:Double;Frequency:Integer;Silent:Boolean);
var N,Count:Integer;Phase,Level:Double;
begin Audio:=TRhythmAudio.Create;Audio.Duration:=Duration;Audio.Sensitivity:=50;Audio.SetBossFrequency(Frequency);SetLength(Audio.Envelope,Ceil(Duration*100));
  for N:=0 to High(Audio.Envelope) do begin Phase:=Frac(N/4000);Level:=0.40;if (Phase>0.45) and (Phase<0.78) then Level:=0.85;if Phase>0.91 then Level:=0.03;if N>Length(Audio.Envelope)-40 then Level:=0;if Silent then Level:=0;Audio.Envelope[N]:=Level;end;
  Audio.UpdateSoundBounds;
  if not Silent then begin Count:=Max(0,Floor((Audio.SoundEnd-0.05)/Gap)+1);SetLength(Audio.Hits,Count);for N:=0 to Count-1 do begin Audio.Hits[N].Time:=0.05+N*Gap;Audio.Hits[N].Strength:=0.25+(N mod 7)*0.12;end;end;
  CreateGUID(ID);Path:=TPath.Combine(CacheFolder,GUIDToString(ID)+'.naval-identity');TFile.WriteAllText(Path,GUIDToString(ID));Audio.Source:=Path;Audio.Key:=THashSHA2.GetHashString(GUIDToString(ID));
  if not GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Info) then RaiseLastOSError;
  Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
end;
procedure Render(Time:Double;const Name:string;Save:Boolean);
begin Timer:=TStopwatch.StartNew;Renderer.Render(Image,Time,0);Elapsed:=Timer.Elapsed.TotalMilliseconds;MaxFrame:=Max(MaxFrame,Elapsed);Inc(Frames);Need(Scene.Notice='','Render notice '+Scene.Notice);
  if Save then begin PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(OutDir,Name+'.png'));end;
end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Cold:=nil;Scene:=nil;Renderer:=nil;Image:=nil;PNG:=nil;Results:=TJSONObject.Create;Rows:=TJSONArray.Create;Results.AddPair('cases',Rows);
  UsedD2D:=False;WarmGDI:=0;WarmD2D:=0;MaxClockError:=0;TotalHits:=0;TotalShots:=0;TotalSeeks:=0;MaxError:=0;MinClear:=1000;MaxFrame:=0;Frames:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmNaval','Music Sync Naval',rsNaval);OutDir:=TPath.Combine(GetCurrentDir,'Win64\OnlinePass\Naval\Frames');ForceDirectories(OutDir);
    Need((Ord(rsNaval)=10) and (StylePlanVersion(rsNaval)=1),'Naval registration');
    for C:=0 to 9 do begin
      Duration:=175;Gap:=0.24;Frequency:=50;case C of 1:begin Duration:=90;Gap:=0.008;Frequency:=100;end;2:begin Duration:=24;Gap:=0.95;Frequency:=0;end;3:begin Duration:=2;Gap:=0.05;end;4:begin Duration:=1;Gap:=1;end;5:begin Duration:=1800;Gap:=0.43;Frequency:=100;end;6:begin Duration:=3000;Gap:=0.16;Frequency:=50;end;7:begin Duration:=90;Frequency:=0;end;8:begin Duration:=1000;Gap:=0.010;Frequency:=100;end;9:begin Duration:=12000;Gap:=0.15;Frequency:=100;end;end;
      MakeAudio(Duration,Gap,Frequency,C=4);if C=3 then Audio.Hits[0].Time:=0;if C=9 then begin Rejected:=False;try TNavalPlan.Build(Audio).Free;except on E:Exception do Rejected:=True;end;Need(Rejected,'Accepted duration beyond shared PCM bound');Row:=TJSONObject.Create;Rows.AddElement(Row);Row.AddPair('case',TJSONNumber.Create(C));Row.AddPair('duration',TJSONNumber.Create(Duration));Row.AddPair('rejectedOutOfBounds',TJSONBool.Create(True));FreeAndNil(Audio);Continue;end;Timer:=TStopwatch.StartNew;Plan:=TNavalPlan.Build(Audio);BuildMS:=Timer.Elapsed.TotalMilliseconds;
      Need(Plan.PulseCount=Length(Audio.Hits),'Discarded source accents');if Frequency=0 then Need(Plan.BossCount=0,'Boss disabled');if C=4 then Need((Plan.Count=0) and (Plan.ShipCount=0),'Silent battle');
      if C=0 then begin
        Rejected:=False;try TNavalPlan.Build(Audio,function:Boolean begin Result:=True;end).Free;except on E:EAbort do Rejected:=True;end;Need(Rejected,'Preparation ignored cancellation');
        Cold:=TNavalPlan.Build(Audio);Need((Cold.Count=Plan.Count) and (Cold.ShotCount=Plan.ShotCount),'Same input changed event count');
        for I:=0 to Plan.ShotCount-1 do begin Shot:=Cold.Shots[I];Need((Shot.A.X=Plan.Shots[I].A.X) and (Shot.B.Y=Plan.Shots[I].B.Y) and (Shot.Launch=Plan.Shots[I].Launch),'Same input changed shot path');end;FreeAndNil(Cold);
      end;
      SetLength(Seen,Length(Audio.Hits));FillChar(SeenModes,SizeOf(SeenModes),0);for I:=0 to Plan.PhraseCount-1 do begin SeenModes[Plan.Phrases[I].Mode]:=True;if I>0 then if Plan.Phrases[I].Theme<>Plan.Phrases[I-1].Theme then Need(Plan.Phrases[I].Section,'Theme changes outside music section');end;
      if Duration>25 then Need(SeenModes[0] and SeenModes[1] and SeenModes[2],'Missing attack/defend/counter roles');
      Glances:=0;Intercepts:=0;for I:=0 to Plan.Count-1 do begin Hit:=Plan.Hits[I];Seen[Hit.Source]:=True;T:=Plan.Events[Hit.Source].Time;
        if Hit.Kind=2 then Inc(Glances) else if Hit.Kind=1 then Inc(Intercepts);
        if Plan.CannonPath(I,Launch,Finish,Arc,A,B) then begin
          Need(Finish=Audio.Hits[Hit.Source].Time,'Moved music clock');Need(Plan.CannonAt(I,Finish,P),'Cannon absent at hit');Error:=Hypot(P.X-B.X,P.Y-B.Y);MaxError:=Max(MaxError,Error);Need(Error<1E-8,'Cannon endpoint');
          if Finish>Launch then begin Need(Plan.CannonAt(I,Launch,P),'Missing launch');Need(Hypot(P.X-A.X,P.Y-A.Y)<1E-8,'Muzzle mismatch');end;
          if Hit.Kind=0 then begin Ship:=Plan.Ships[Hit.Target];H:=Plan.ShipAt(Hit.Target,T);DX:=Max(0.0,Abs(B.X-H.X)-0.12*Ship.Size);DY:=Max(0.0,Abs(B.Y-H.Y)-0.035*Ship.Size);Need(Abs(Hypot(DX,DY)-0.008)<1E-8,'No physical hull contact');
            Need((B.X>=0) and (B.X<=1.8) and (B.Y>=0) and (B.Y<=1),'Impact outside stage');
            if Finish>Launch then for J:=0 to 71 do begin
              Aim:=J/48;if J>=48 then Aim:=1-Power(0.5,J-46);Aim:=Launch+(Finish-Launch)*Aim;Need(Plan.CannonAt(I,Aim,P),'Projectile missing before hull contact');H:=Plan.ShipAt(Hit.Target,Aim);DX:=Max(0.0,Abs(P.X-H.X)-0.12*Ship.Size);DY:=Max(0.0,Abs(P.Y-H.Y)-0.035*Ship.Size);
              Need(Hypot(DX,DY)>=0.008-1E-8,Format('Early moving hull collision source=%d target=%d time=%.9f/%.9f',[Hit.Source,Hit.Target,Aim,Finish]));
            end;
          end else begin Shot:=Plan.Shots[Hit.Shot];Q:=Plan.ShotAt(Shot,T);Need(Hypot(B.X-Q.X,B.Y-Q.Y)<1E-8,'Interception misses incoming shell');end;
        end;
      end;for I:=0 to High(Seen) do Need(Seen[I],'Unmapped audio source');Inc(TotalHits,Plan.Count);
      for I:=0 to Plan.ShotCount-1 do begin Shot:=Plan.Shots[I];if Shot.Kind=0 then begin
          for J:=0 to 96 do begin T:=Shot.Launch+(Shot.Finish-Shot.Launch)*J/96;P:=Plan.ShotAt(Shot,T);H:=Plan.HeroAt(T);Aim:=Plan.HeroAngle(T);DX:=(P.X-H.X)*Cos(Aim)+(P.Y-H.Y)*Sin(Aim);DY:=-(P.X-H.X)*Sin(Aim)+(P.Y-H.Y)*Cos(Aim);Clear:=Hypot(Max(0.0,Abs(DX)-0.15),Max(0.0,Abs(DY)-0.045))-Shot.Radius;MinClear:=Min(MinClear,Clear);Need(Clear>0,'Unplanned player collision');end;
        end else if Shot.Kind=2 then begin P:=Plan.ShotAt(Shot,Shot.Finish);H:=Plan.HeroAt(Shot.Finish);Aim:=Plan.HeroAngle(Shot.Finish);DX:=(P.X-H.X)*Cos(Aim)+(P.Y-H.Y)*Sin(Aim);DY:=-(P.X-H.X)*Sin(Aim)+(P.Y-H.Y)*Cos(Aim);Need(Abs(Hypot(Max(0.0,Abs(DX)-0.15),Max(0.0,Abs(DY)-0.045))-Shot.Radius)<1E-7,'Glancing hit misses hull');end;
      end;Inc(TotalShots,Plan.ShotCount);
      for I:=0 to Plan.BossCount-1 do begin J:=Plan.Boss(I);T:=Plan.Ships[J].Kill;Need((Plan.HealthAt(J,T)=0) and (Plan.HealthAt(J,T-1E-7)>0),'Boss defeat not last real hit');Need((Plan.PartTime(J,0)<=Plan.PartTime(J,1)) and (Plan.PartTime(J,1)<=Plan.PartTime(J,2)),'Parts out of order');end;
      Need(Plan.DamageAt(Plan.EndTime)=0,'Deck fire remains at ending');
      for I:=0 to Plan.ShipCount-1 do Need((Plan.HealthAt(I,Plan.EndTime)=0) and (Plan.Ships[I].Kill+1.5<=Plan.EndTime),'Ship survives ending');
      for I:=0 to Plan.ShotCount-1 do Need(Plan.Shots[I].Finish+0.58<=Plan.EndTime+1E-8,'Enemy shot effect survives ending');
      Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsNaval,StyleVariant(rsNaval,50,Frequency));Ref.SourceRevision:=Audio.SourceRevision;Plan.Save(Ref,Audio);if C=0 then begin Hash:=Ref.Digest;Plan.Save(Ref,Audio);Need(Ref.Digest=Hash,'Same plan changed JSON digest');end;Meta:=TNavalPlan.LoadAudioMetadata(Ref,Audio.Source,0);Need((Length(Meta.PCM)=0) and (Length(Meta.Envelope)=0) and (Meta.BossFrequency=Frequency),'Cold restore decodes music/frequency');Cold:=TNavalPlan.Load(Ref,Meta,0);
      BadRef:=Ref;BadRef.Digest:=StringOfChar('0',64);Rejected:=False;
      try TNavalPlan.Load(BadRef,Meta,0).Free;except on E:Exception do Rejected:=True;end;Need(Rejected,'Accepted bad plan digest');
      for I:=0 to Plan.PulseCount-1 do begin ClockError:=Abs(Plan.Events[I].Time-Cold.Events[I].Time);MaxClockError:=Max(MaxClockError,ClockError);Need(ClockError<1E-10,'Source clock JSON drift');end;
      Need((Cold.Count=Plan.Count) and (Cold.BossCount=Plan.BossCount) and (Cold.ShotCount=Plan.ShotCount),'Cold plan count');
      for I:=0 to 63 do begin T:=Plan.EndTime*((I*37) mod 71)/71;P:=Plan.HeroAt(T);Q:=Cold.HeroAt(T);Need((Abs(P.X-Q.X)<1E-12) and (Abs(P.Y-Q.Y)<1E-12),'Hero seek differs');Plan.CameraAt(T,Camera,Zoom);Cold.CameraAt(T,Camera2,Zoom2);Need((Abs(Camera.X-Camera2.X)<1E-12) and (Abs(Camera.Y-Camera2.Y)<1E-12) and (Abs(Zoom-Zoom2)<1E-12),Format('Camera seek differs T=%.12g X=%.16g/%.16g Y=%.16g/%.16g Z=%.16g/%.16g',[T,Camera.X,Camera2.X,Camera.Y,Camera2.Y,Zoom,Zoom2]));for J:=0 to Plan.BossCount-1 do Need(Plan.HealthAt(Plan.Boss(J),T)=Cold.HealthAt(Cold.Boss(J),T),'HP seek differs');Inc(TotalSeeks);end;
      PeakShots:=0;PeakShips:=0;LateShots:=0;
      for I:=0 to Plan.ShotCount-1 do if Plan.Shots[I].Launch>Duration*0.85 then Inc(LateShots);
      if Duration>100 then Need(LateShots>0,'Later track starved of enemy fire');
      for I:=0 to 127 do begin
        T:=Plan.EndTime*I/128;Active:=0;
        for J:=Max(0,Plan.ShotBefore(T-2.4)) to Plan.ShotBefore(T) do begin Shot:=Plan.DrawShot(J);if (Shot.Launch<=T) and (Shot.Finish>T) then Inc(Active);end;PeakShots:=Max(PeakShots,Active);Active:=0;
        for J:=Max(0,Plan.ShipBefore(T-1.5)) to Min(Plan.ShipCount-1,Plan.ShipBefore(T+6.1)) do begin Ship:=Plan.Ships[Plan.DrawShipIndex(J)];if (Ship.Show<=T) and (Ship.Kill>T) then Inc(Active);end;PeakShips:=Max(PeakShips,Active);
      end;
      if C=0 then begin
        Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1600,900);PNG:=TPngImage.Create;Scene:=TNavalAnimation.Create;Scene.Audio:=Audio;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;
        Render(5,'01-attack',True);Render(13,'02-defend',True);Render(21,'03-counter',True);
        for I:=0 to Plan.Count-1 do if Plan.Hits[I].Kind=2 then begin Render(Plan.Events[Plan.Hits[I].Source].Time+0.12,'09-light-hit',True);Break;end;
        for I:=0 to Plan.Count-1 do if Plan.Hits[I].Kind=1 then begin Render(Plan.Events[Plan.Hits[I].Source].Time+0.05,'10-interception',True);Break;end;
        for I:=0 to Plan.BossCount-1 do begin J:=Plan.Boss(I);Render(Plan.Ships[J].Show+3,'04-boss-'+IntToStr(I),True);Render(Plan.Ships[J].Kill-2,'05-boss-damage-'+IntToStr(I),True);Render(Plan.Ships[J].Kill+0.30,'06-boss-sinking-'+IntToStr(I),True);end;
        Render(13,'',False);Hash:=ImageHash;Render(Plan.EndTime+1,'',False);Render(13,'',False);Need(ImageHash=Hash,'Frame differs after random seek');Render(Plan.EndTime+1,'07-ending',True);Hash:=ImageHash;Render(Plan.EndTime+100,'',False);Need(ImageHash=Hash,'Post-end keeps moving');
        Render(13,'',False);WarmHash:=ImageHash;FreeAndNil(Renderer);Scene:=TNavalAnimation.Create;Scene.Audio:=Meta;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;Render(13,'',False);Need(ImageHash=WarmHash,'Fresh cold scene frame differs');
        for I:=0 to 31 do begin Render(5+I*0.021,'',False);WarmGDI:=WarmGDI+Elapsed/32;end;
        Renderer.UseD2D:=True;Render(13,'08-defend-d2d',True);UsedD2D:=Renderer.LastUsedD2D;
        Hash:=ImageHash;Render(60,'',False);Render(13,'',False);Need(ImageHash=Hash,'D2D seek differs');
        for I:=0 to 31 do begin Render(5+I*0.021,'',False);WarmD2D:=WarmD2D+Elapsed/32;end;
        FreeAndNil(Renderer);Scene:=nil;FreeAndNil(Image);FreeAndNil(PNG);
      end;
      Row:=TJSONObject.Create;Rows.AddElement(Row);Row.AddPair('case',TJSONNumber.Create(C));Row.AddPair('duration',TJSONNumber.Create(Duration));Row.AddPair('events',TJSONNumber.Create(Plan.PulseCount));Row.AddPair('hits',TJSONNumber.Create(Plan.Count));Row.AddPair('ships',TJSONNumber.Create(Plan.ShipCount));Row.AddPair('bosses',TJSONNumber.Create(Plan.BossCount));Row.AddPair('shots',TJSONNumber.Create(Plan.ShotCount));Row.AddPair('glances',TJSONNumber.Create(Glances));Row.AddPair('intercepts',TJSONNumber.Create(Intercepts));Row.AddPair('peakLiveEnemyShots',TJSONNumber.Create(PeakShots));Row.AddPair('peakLiveShips',TJSONNumber.Create(PeakShips));Row.AddPair('lateShots',TJSONNumber.Create(LateShots));Row.AddPair('preparedBytes',TJSONNumber.Create(TFile.GetSize(TPath.Combine(PlanFolder,Ref.Key+'.json'))));Row.AddPair('buildMilliseconds',TJSONNumber.Create(BuildMS));Writeln(Row.ToJSON);
      FreeAndNil(Cold);FreeAndNil(Meta);FreeAndNil(Plan);FreeAndNil(Audio);
    end;
    Results.AddPair('contacts',TJSONNumber.Create(TotalHits));Results.AddPair('shots',TJSONNumber.Create(TotalShots));Results.AddPair('randomSeeks',TJSONNumber.Create(TotalSeeks));Results.AddPair('maxEndpointError',TJSONNumber.Create(MaxError));Results.AddPair('minUnplannedShotClearance',TJSONNumber.Create(MinClear));Results.AddPair('maxSourceJSONClockError',TJSONNumber.Create(MaxClockError));Results.AddPair('frames',TJSONNumber.Create(Frames));Results.AddPair('maxGDIFrameMilliseconds',TJSONNumber.Create(MaxFrame));Results.AddPair('native',TJSONBool.Create(True));Results.AddPair('audioPlayed',TJSONBool.Create(False));
    Results.AddPair('warmGDIFrameMilliseconds',TJSONNumber.Create(WarmGDI));Results.AddPair('warmD2DFrameMilliseconds',TJSONNumber.Create(WarmD2D));Results.AddPair('usedD2D',TJSONBool.Create(UsedD2D));
    TFile.WriteAllText(TPath.Combine(OutDir,'..\native-results.json'),Results.ToJSON,TEncoding.UTF8);Writeln('NavalPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Renderer.Free;Image.Free;PNG.Free;Cold.Free;Plan.Free;Meta.Free;Audio.Free;Results.Free;
end.
