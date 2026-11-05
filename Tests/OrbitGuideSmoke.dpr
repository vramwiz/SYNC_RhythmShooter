program OrbitGuideSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmOrbitPlan,RhythmOrbitTypes,RhythmOrbitGuide,
  RhythmOrbitScene,RhythmAnimation,RhythmImageBank,RhythmPlanRef,RhythmStyles,RhythmProduct;
var
  Audio:TRhythmAudio;Plan:TOrbitPlan;Ref:TRhythmPlanRef;Scene:TOrbitAnimation;Render:TAnimationRenderer;
  Image:TBitmap;PNG:TPngImage;Source,Folder,Revision,Hash:string;Stamp:TWin32FileAttributeData;
  C,I,J,B,AspectIndex,N,Checks,Seek,MaxMarkers,Count,MarkerCount,NextMarker,OrbitSamples,ChordChecks:Integer;
  Time,Gap,Duration,Error,Mid,MaxChordError,DX,DY,U,Finish,LocalX,LocalY:Double;
  State:TOrbitVisualState;Leg:TOrbitLeg;Body:TOrbitBody;Course:array[0..2] of TOrbitCourse;
  Points:TOrbitRoute;P,LeftPoint,RightPoint,MidPoint:TOrbitPoint;Tap:TOrbitTap;
  Stats:TOrbitRenderStats;Markers:TOrbitMarkers;
procedure Need(OK:Boolean;const S:string);
begin if not OK then raise Exception.Create(S);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;finally M.Free;end;end;
begin Audio:=nil;Plan:=nil;Render:=nil;Image:=nil;PNG:=nil;Checks:=0;Seek:=0;MaxChordError:=0;MaxMarkers:=0;OrbitSamples:=0;ChordChecks:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','Orbit Guide Native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);Source:=TPath.Combine(Folder,'guide.identity');TFile.WriteAllText(Source,'Synthetic guide test.',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(960,540);
    for C:=0 to 5 do begin
      Duration:=96;Gap:=0.95;if C=1 then Gap:=0.08;if C=2 then begin Duration:=8;Gap:=0.001;end;
      if C=3 then begin Duration:=3000;Gap:=0.44;end;if C=4 then begin Duration:=32;Gap:=0.04;end;if C=5 then Duration:=1;
      Audio:=TRhythmAudio.Create;Audio.Duration:=Duration;Audio.SoundEnd:=Duration;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Sensitivity:=50;Audio.Key:=THashSHA2.GetHashString('guide-'+IntToStr(C));
      N:=Floor((Duration-0.01)/Gap)+1;SetLength(Audio.Hits,N);
      for I:=0 to N-1 do begin Audio.Hits[I].Time:=I*Gap;if C=4 then Audio.Hits[I].Time:=(I div 3)*Gap;Audio.Hits[I].Strength:=0.3+(I mod 8)*0.1;end;
      if C=5 then begin Audio.Hits:=nil;Audio.SoundEnd:=0;end;
      Plan:=TOrbitPlan.Build(Audio,20);Ref:=NewPlanRef(Audio.Key,50,0,rsRhythmGame,121);Ref.SourceRevision:=Revision;Plan.Save(Ref,Audio);
      Scene:=TOrbitAnimation.Create;Scene.Audio:=Audio;Scene.SetReference(Ref);
      Scene.TransparentBackground:=True;Render:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));
      Course[0].Prepare(Plan,960,540);
      Course[1].Prepare(Plan,540,960);
      Course[2].Prepare(Plan,720,720);
      for J:=0 to 11 do begin Time:=Min(Duration,0.23+J*0.79);State:=OrbitVisualState(Plan,Time);
        Need((State.Horizon>=0) and (State.Horizon<=6.8) and (State.Pulse>=0) and (State.Pulse<=1.4),'Visual limits');
        if State.Horizon>0 then
          for AspectIndex:=0 to 2 do begin
            MarkerCount:=Course[AspectIndex].Visible(State,Time,Markers);
            Finish:=Time+State.Horizon;
            Count:=Course[AspectIndex].Route(Plan,Time,Finish,Markers,MarkerCount,Points);
            P:=Course[AspectIndex].CursorAt(Time);
            Need((Count>0) and (Points[0].P.X=P.X) and (Points[0].P.Y=P.Y),'Guide does not start at ship');
            Need(Points[Count].Time=Finish,'Guide shortened the preview of the orbit');
            NextMarker:=0;
            for I:=1 to Count do begin
              Need(Points[I].Time>Points[I-1].Time,'Guide times are out of order');
              Leg:=Course[AspectIndex].Leg(Course[AspectIndex].LegAt(Points[I].Time));
              if Leg.Kind=0 then begin
                Body:=Course[AspectIndex].Body(Leg.FromBody);
                DX:=Points[I].P.X-Body.Center.X;
                DY:=Points[I].P.Y-Body.Center.Y;
                LocalX:=DX*Cos(Body.Rotation)+DY*Sin(Body.Rotation);
                LocalY:=-DX*Sin(Body.Rotation)+DY*Cos(Body.Rotation);
                Need(Abs(Sqr(LocalX/Body.RX)+Sqr(LocalY/Body.RY)-1)<1E-9,'Guide left the planet ellipse');
                Inc(OrbitSamples);
              end;
              LeftPoint:=Points[I-1].P;
              RightPoint:=Points[I].P;
              Mid:=(Points[I-1].Time+Points[I].Time)*0.5;
              MidPoint:=Course[AspectIndex].CursorAt(Mid);
              DX:=RightPoint.X-LeftPoint.X;DY:=RightPoint.Y-LeftPoint.Y;
              U:=EnsureRange(((MidPoint.X-LeftPoint.X)*DX+(MidPoint.Y-LeftPoint.Y)*DY)/Max(1E-12,Sqr(DX)+Sqr(DY)),0.0,1.0);
              Error:=Hypot(MidPoint.X-LeftPoint.X-U*DX,MidPoint.Y-LeftPoint.Y-U*DY);
              MaxChordError:=Max(MaxChordError,Error);
              if Error>=3 then Need(False,Format('Ship departs rendered line by %.3f px at %.4f s (case %d, view %d)',
                [Error,Mid,C,AspectIndex]));
              if NextMarker<MarkerCount then begin
                Tap:=Plan.Taps[Markers[NextMarker].TapIndex];
                if Tap.Time<=Points[I].Time then begin
                  P:=Markers[NextMarker].Center;
                  Need((Tap.Time=Points[I].Time) and (Hypot(P.X-RightPoint.X,P.Y-RightPoint.Y)<1E-9),
                    'Guide misses a visible contact');
                  Inc(NextMarker);Inc(Checks);
                end;
              end;
              Inc(Checks);
            end;
            Need(NextMarker=MarkerCount,'A visible marker was outside the guide');
          end;
        Count:=Course[0].Visible(State,Time,Markers);
        if (C=4) and (State.Horizon>0) then begin
          for I:=0 to Count-1 do begin
            Need(Markers[I].TapCount=3,'Same-time hits did not share a marker');Inc(ChordChecks);
          end;
        end;
        for B:=0 to 1 do begin Render.UseD2D:=B=1;Need(Render.TryRenderAlpha(Image,Time,0),'Scene error: '+Scene.Notice);Stats:=Scene.RenderStats;
          Need((Stats.RouteSegments<=ORBIT_GUIDE_STEPS) and (Stats.Markers=Count) and (Stats.Effects<=24) and (Stats.Stars=512),'Draw budget or marker mismatch');
          if State.Horizon>0 then Need(Stats.RouteSegments>0,'Missing future route');
          if C=5 then Need((Stats.RouteSegments=0) and (Stats.Markers=0) and (Stats.Effects=0),'Silent music invented cues');
          MaxMarkers:=Max(MaxMarkers,Stats.Markers);
          Hash:=ImageHash;
          Need(Render.TryRenderAlpha(Image,Duration-Time,0) and Render.TryRenderAlpha(Image,Time,0),'Seek render failed');
          Need(ImageHash=Hash,'Visual seek drift');Inc(Seek);
          if B=1 then Need(Render.LastUsedD2D,'D2D unavailable');
          if (C<=1) and (J in [1,3,7,9]) then begin PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Format('case%d-backend%d-frame%d.png',[C,B,J])));finally FreeAndNil(PNG);end;end;
        end;
      end;
      FreeAndNil(Render);FreeAndNil(Plan);FreeAndNil(Audio);WriteLn('Guide CASE ',C,' PASS');
    end;
    Need((OrbitSamples>0) and (MaxMarkers>1) and (ChordChecks>0),'Fixtures missed orbit samples or simultaneous previews');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"cases":6,"guideChecks":%d,"seekChecks":%d,"maxMarkers":%d,"orbitSamples":%d,"maxChordPixelError":%.9f}',[Checks,Seek,MaxMarkers,OrbitSamples,MaxChordError],TFormatSettings.Invariant),TEncoding.UTF8);
    WriteLn('Orbit guide PASS checks=',Checks,' seek=',Seek,' maxMarkers=',MaxMarkers,' pixelError=',MaxChordError:0:6);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  PNG.Free;Render.Free;Plan.Free;Audio.Free;Image.Free;
end.
