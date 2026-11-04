program OrbitGuideSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmOrbitPlan,RhythmOrbitTypes,RhythmOrbitGuide,
  RhythmOrbitScene,RhythmAnimation,RhythmImageBank,RhythmPlanRef,RhythmStyles,RhythmProduct;
var
  Audio:TRhythmAudio;Plan:TOrbitPlan;Ref:TRhythmPlanRef;Scene:TOrbitAnimation;Render:TAnimationRenderer;
  Image:TBitmap;PNG:TPngImage;Source,Folder,Revision,Hash:string;Stamp:TWin32FileAttributeData;
  C,I,J,K,B,AspectIndex,N,Checks,Seek,MaxMarkers,MaxNear,MaxFar,MoreCues,OldVisible:Integer;
  Time,Gap,Duration,Aspect,Height,Error,MaxError,MaxChordError,LastOpacity:Double;
  State:TOrbitVisualState;A,D:TOrbitGuideSample;P:TOrbitPoint;Cam:TOrbitCamera;Tap:TOrbitTap;Stats:TOrbitRenderStats;
procedure Need(OK:Boolean;const S:string);
begin if not OK then raise Exception.Create(S);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;finally M.Free;end;end;
begin Audio:=nil;Plan:=nil;Render:=nil;Image:=nil;PNG:=nil;Checks:=0;Seek:=0;MaxError:=0;MaxChordError:=0;MaxMarkers:=0;MaxNear:=0;MaxFar:=0;MoreCues:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','Orbit Guide Native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);Source:=TPath.Combine(Folder,'guide.identity');TFile.WriteAllText(Source,'Synthetic guide test.',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(960,540);
    for C:=0 to 5 do begin
      Duration:=96;Gap:=0.6;if C=1 then Gap:=0.08;if C=2 then begin Duration:=8;Gap:=0.001;end;
      if C=3 then begin Duration:=3000;Gap:=0.44;end;if C=4 then begin Duration:=32;Gap:=0.04;end;if C=5 then Duration:=1;
      Audio:=TRhythmAudio.Create;Audio.Duration:=Duration;Audio.SoundEnd:=Duration;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Sensitivity:=50;Audio.Key:=THashSHA2.GetHashString('guide-'+IntToStr(C));
      N:=Floor((Duration-0.01)/Gap)+1;SetLength(Audio.Hits,N);
      for I:=0 to N-1 do begin Audio.Hits[I].Time:=I*Gap;if C=4 then Audio.Hits[I].Time:=(I div 3)*Gap;Audio.Hits[I].Strength:=0.3+(I mod 8)*0.1;end;
      if C=5 then begin Audio.Hits:=nil;Audio.SoundEnd:=0;end;
      Plan:=TOrbitPlan.Build(Audio,20);Ref:=NewPlanRef(Audio.Key,50,0,rsRhythmGame,121);Ref.SourceRevision:=Revision;Plan.Save(Ref,Audio);
      Scene:=TOrbitAnimation.Create;Scene.Audio:=Audio;Scene.SetReference(Ref);Render:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));
      for J:=0 to 11 do begin Time:=Min(Duration,0.23+J*0.79);State:=OrbitVisualState(Plan,Time);
        Need((State.Horizon>=0) and (State.Horizon<=6.8) and (State.Pulse>=0) and (State.Pulse<=1.4),'Visual limits');
        if State.Horizon>0 then begin
          A:=OrbitGuideAt(Plan,Time,State.Horizon,0);P:=Plan.CursorAt(Time);Need((A.P.X=P.X) and (A.P.Y=P.Y),'Guide does not start at ship');LastOpacity:=1;
          for I:=1 to ORBIT_GUIDE_STEPS do begin
            D:=OrbitGuideAt(Plan,Time,State.Horizon,I/ORBIT_GUIDE_STEPS);Need(D.Opacity<=LastOpacity,'Future line grows brighter');LastOpacity:=D.Opacity;
            P:=Plan.CursorAt((A.Time+D.Time)*0.5);Error:=Hypot(P.X-(A.P.X+D.P.X)*0.5,P.Y-(A.P.Y+D.P.Y)*0.5);
            for AspectIndex:=0 to 2 do begin Aspect:=16/9;Height:=540;if AspectIndex=1 then begin Aspect:=9/16;Height:=960;end;if AspectIndex=2 then begin Aspect:=1;Height:=720;end;
              Cam:=Plan.CameraAt(Time,Aspect);MaxChordError:=Max(MaxChordError,Error*Height/Cam.Span);Need(Error*Height/Cam.Span<0.65,'Ship departs rendered line');Inc(Checks);
            end;A:=D;
          end;
          K:=Plan.Before(Time)+1;
          for I:=K to Min(Plan.Count-1,K+127) do begin Tap:=Plan.Taps[I];if Tap.Time>Time+State.Horizon then Break;
            D:=OrbitGuideAt(Plan,Time,State.Horizon,(Tap.Time-Time)/State.Horizon);Error:=Hypot(D.P.X-Tap.P.X,D.P.Y-Tap.P.Y);MaxError:=Max(MaxError,Error);Need(Error<1E-9,'Guide misses future saved tap');Inc(Checks);
          end;
        end;
        for B:=0 to 1 do begin Render.UseD2D:=B=1;Render.Render(Image,Time,0);Need(Scene.Notice='','Scene error: '+Scene.Notice);Stats:=Scene.RenderStats;
          Need((Stats.RouteSegments<=ORBIT_GUIDE_STEPS) and (Stats.Markers<=128) and (Stats.NearMarkers<=8) and (Stats.Effects<=24) and (Stats.Stars=512),'Draw budget');
          if State.Horizon>0 then Need(Stats.RouteSegments=ORBIT_GUIDE_STEPS,'Missing future route');
          if C=5 then Need((Stats.RouteSegments=0) and (Stats.Markers=0) and (Stats.Effects=0),'Silent music invented cues');
          MaxMarkers:=Max(MaxMarkers,Stats.Markers);MaxNear:=Max(MaxNear,Stats.NearMarkers);MaxFar:=Max(MaxFar,Stats.FarMarkers);
          OldVisible:=0;Cam:=Plan.CameraAt(Time,16/9);
          for I:=Plan.Before(Time)+1 to Plan.Count-1 do begin Tap:=Plan.Taps[I];if Tap.Time>Time+1.45 then Break;P:=OrbitProject(Tap.P,Cam,16/9);
            if (P.X>=0) and (P.X<=1) and (P.Y>=0) and (P.Y<=1) then Inc(OldVisible);
          end;
          if (C<=1) and (Stats.Markers>OldVisible+2) then Inc(MoreCues);
          Hash:=ImageHash;Render.Render(Image,Duration-Time,0);Render.Render(Image,Time,0);Need(ImageHash=Hash,'Visual seek drift');Inc(Seek);
          if B=1 then Need(Render.LastUsedD2D,'D2D unavailable');
          if (C<=1) and (J in [1,3,7,9]) then begin PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Format('case%d-backend%d-frame%d.png',[C,B,J])));finally FreeAndNil(PNG);end;end;
        end;
      end;
      FreeAndNil(Render);FreeAndNil(Plan);FreeAndNil(Audio);WriteLn('Guide CASE ',C,' PASS');
    end;
    Need((MaxFar>10) and (MoreCues>8),'Future cues did not increase');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"cases":6,"guideChecks":%d,"seekChecks":%d,"maxMarkers":%d,"maxNearMarkers":%d,"maxFarMarkers":%d,"moreCueFrames":%d,"maxContactError":%.16f,"maxChordPixelError":%.9f}',[Checks,Seek,MaxMarkers,MaxNear,MaxFar,MoreCues,MaxError,MaxChordError],TFormatSettings.Invariant),TEncoding.UTF8);
    WriteLn('Orbit guide PASS checks=',Checks,' seek=',Seek,' maxMarkers=',MaxMarkers,' far=',MaxFar,' richerFrames=',MoreCues,' pixelError=',MaxChordError:0:6);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  PNG.Free;Render.Free;Plan.Free;Audio.Free;Image.Free;
end.
