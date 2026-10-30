program RunnerPlanSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,Vcl.Graphics,
  RhythmAudio,RhythmRunnerPlan,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmSettings,RhythmScene,RhythmPaths;
var Audio,Meta:TRhythmAudio;Plan,Again:TRunnerPlan;Ref:TRhythmPlanRef;State,Cold:TRhythmSettings;
  Renderer:TRhythmRenderer;Image:TBitmap;I,J,C:Integer;S:TRunnerStep;Pad:TRunnerPlatform;P,Q:TRunnerPoint;
  Found,Rejected:Boolean;Gap,T,D:Double;Path,Hash:string;Id:TGUID;Info:TWin32FileAttributeData;
procedure Require(Value:Boolean;const Text:string);begin if not Value then raise Exception.Create(Text);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;finally M.Free;end;end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Again:=nil;Renderer:=nil;Image:=nil;
  try
    ConfigureRhythmProduct('SYNC_RhythmRunner','リズムランナー',rsRunner);
    Require((Ord(rsRunner)=3) and (Ord(rsFireworks)=2) and (StylePlanVersion(rsBall)=5),'Existing style contract changed');
    Require(TRhythmSettings.Defaults.Style=rsRunner,'Runner default missing');
    Require(TRhythmSettings.TryJSON('{"schema":1,"music":"old.wav"}',State) and (State.Style=rsShooting),'Legacy JSON changed style');
    for C:=0 to 3 do begin
      case C of 0:Gap:=0.18;1:Gap:=0.7;2:Gap:=3;else Gap:=0.09;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=22;Audio.Sensitivity:=50;SetLength(Audio.Envelope,2200);
      for I:=0 to 1999 do Audio.Envelope[I]:=0.5;SetLength(Audio.Hits,Floor(19/Gap)+1);
      for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.5+I*Gap;Audio.Hits[I].Strength:=0.3+(I mod 5)*0.175;end;
      if C=3 then begin Audio.Hits[0].Time:=0;Audio.Hits[1].Time:=0;end;
      Audio.UpdateSoundBounds;CreateGUID(Id);Path:=TPath.Combine(CacheFolder,GUIDToString(Id)+'.identity');
      TFile.WriteAllText(Path,GUIDToString(Id),TEncoding.UTF8);Audio.Source:=Path;Audio.Key:=THashSHA2.GetHashString(GUIDToString(Id));
      if not GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Info) then RaiseLastOSError;
      Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
      Plan:=TRunnerPlan.Build(Audio);Again:=TRunnerPlan.Build(Audio);
      Require(Plan.PulseCount=Length(Audio.Hits),'Runner discarded valid accents');
      Require((Plan.GoalTime=Audio.SoundEnd) and (Plan.EndTime=Plan.GoalTime+RUN_EXIT),'Goal/ending is not based on whole-song sound end');
      for I:=0 to Plan.PulseCount-1 do Require(Plan.Pulse[I].Time=Audio.Hits[I].Time,'Contact time drifted');
      for I:=0 to Plan.Count-1 do begin
        S:=Plan.Step[I];P:=Plan.PositionAt(S.Time);Q:=Again.PositionAt(S.Time);
        Require((Abs(P.X-RUN_SPEED*S.Time)<1E-8) and (Abs(P.Y-S.Y)<1E-8),'Runner misses its landing');
        Require((P.X=Q.X) and (P.Y=Q.Y),'Runner is not deterministic');
        Found:=False;for J:=0 to Plan.PlatformCount-1 do begin Pad:=Plan.Platform[J];if (P.X>=Pad.Left-1E-8) and (P.X<=Pad.Right+1E-8) and (Abs(P.Y-Pad.Y)<1E-8) then Found:=True;end;
        Require(Found,'Landing has no platform');
        D:=S.Time-S.Takeoff;
        if D>0 then for J:=1 to 9 do begin
          T:=D*J/10;P:=Plan.PositionAt(S.Takeoff+T);
          Require(Abs(P.X-RUN_SPEED*(S.Takeoff+T))<1E-8,'Airborne horizontal motion changes direction');
          Require(Abs(P.Y-(S.StartY+S.Velocity*T+0.5*RUN_GRAVITY*T*T))<1E-8,'Jump is not ballistic');
        end;
      end;
      P:=Plan.PositionAt(Plan.GoalTime);Q:=Plan.PositionAt(Plan.GoalTime+1.3);Require(Q.X>P.X+1,'Runner does not leave toward the right');
      Ref:=NewPlanRef(Audio.Key,50,0,rsRunner);Ref.SourceRevision:=Audio.SourceRevision;Plan.Save(Ref,Audio);
      State:=TRhythmSettings.Defaults;State.Music:=Path;State.Plan:=Ref;State.Designs[8].Memo:='keep existing design';
      TFile.WriteAllText(Path+'.json',State.ToJSON,TEncoding.UTF8);
      Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Renderer.ConfigureStyle(rsRunner,Ref);Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);
      Renderer.Render(Image,Audio,2.75,0);Hash:=ImageHash;
      FreeAndNil(Renderer);FreeAndNil(Plan);FreeAndNil(Again);FreeAndNil(Audio);
      Require(TRhythmSettings.TryJSON(TFile.ReadAllText(Path+'.json',TEncoding.UTF8),Cold) and (Cold.Plan.SourceRevision=Ref.SourceRevision),'Runner object settings were not restored');
      Meta:=TRunnerPlan.LoadAudioMetadata(Cold.Plan,Cold.Music,0);Require(Length(Meta.PCM)=0,'Cold runner restoration reads PCM');
      Plan:=TRunnerPlan.Load(Cold.Plan,Meta,0);Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Renderer.ConfigureStyle(Cold.Style,Cold.Plan);
      Renderer.Render(Image,Meta,2.75,0);Require(ImageHash=Hash,'New instance changed the restored frame');
      Renderer.Render(Image,Meta,Plan.EndTime+1,0);Hash:=ImageHash;Renderer.Render(Image,Meta,Plan.EndTime+20,0);Require(ImageHash=Hash,'Runner moves after exit');
      Ref:=Cold.Plan;Ref.Digest:=StringOfChar('0',64);Rejected:=False;
      try Again:=TRunnerPlan.Load(Ref,Meta,0);except Rejected:=True;end;Require(Rejected,'Invalid content digest accepted');
      FreeAndNil(Renderer);FreeAndNil(Image);FreeAndNil(Plan);FreeAndNil(Meta);
    end;
    Audio:=TRhythmAudio.Create;Audio.Duration:=1;Audio.SoundEnd:=0;
    Plan:=TRunnerPlan.Build(Audio);Require((Plan.PulseCount=0) and (Plan.EndTime=0),'Silence generates running');FreeAndNil(Plan);
    Rejected:=False;try Plan:=TRunnerPlan.Build(Audio,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;
    Require(Rejected,'Cancellation ignored');
    Writeln('RunnerPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Image.Free;Renderer.Free;Again.Free;Plan.Free;Meta.Free;Audio.Free;
end.
