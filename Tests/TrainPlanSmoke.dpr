program TrainPlanSmoke;
{$APPTYPE CONSOLE}
uses
  Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,
  Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmTrainPlan in '..\Source\Train\RhythmTrainPlan.pas',
  RhythmTrainScene in '..\Source\Train\RhythmTrainScene.pas',
  RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmProduct,RhythmPaths,
  RhythmAnimation,RhythmImageBank;
var Audio,Meta:TRhythmAudio;Plan,Cold:TTrainPlan;Ref:TRhythmPlanRef;
  Scene:TTrainAnimation;Renderer:TAnimationRenderer;Image:TBitmap;PNG:TPngImage;
  I,J,K,C,Frequency,First,Last,Idx,Alive,MaxAlive,Threats,MaxThreats,Grazes,Intercepts:Integer;
  D,Gap,T,Error:Double;SourceFile,OutDir,Hash:string;Info:TWin32FileAttributeData;Id:TGUID;
  P,Q,R:TTrainPoint;H:TTrainHit;S:TTrainShot;E:TTrainEnemy;Rejected:Boolean;
procedure Need(V:Boolean;const Text:string);begin if not V then raise Exception.Create(Text);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;if M.Size>0 then M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;finally M.Free;end;end;
procedure Snapshot(const Name:string;Time:Double);
begin Renderer.Render(Image,Time,0);PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(OutDir,Name+'.png'));end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Cold:=nil;Renderer:=nil;Image:=nil;PNG:=nil;
  try
    ConfigureRhythmProduct('SYNC_RhythmTrain','Train',rsTrain);OutDir:=ExtractFileDir(ParamStr(0));
    Need((Ord(rsTrain)=9) and (StylePlanVersion(rsTrain)=1),'Train registry');
    for C:=0 to 8 do begin
      D:=96;Gap:=0.18;Frequency:=50;
      case C of 1:Frequency:=0;2:begin D:=12;Gap:=0.09;Frequency:=100;end;
        3:begin D:=60;Gap:=0.005;end;4:begin D:=3000;Gap:=0.43;Frequency:=100;end;
        5:begin D:=0.1;Gap:=0.01;end;6:begin D:=1;Gap:=2;Frequency:=0;end;7:begin D:=4;Gap:=0.03;Frequency:=0;end;8:begin D:=2;Gap:=0.1;Frequency:=0;end;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=D;Audio.Sensitivity:=50;Audio.SetBossFrequency(Frequency);
      SetLength(Audio.Envelope,Ceil(D*100));for I:=0 to High(Audio.Envelope) do begin Audio.Envelope[I]:=0.7;if (I mod 3000>=2100) and (I mod 3000<2600) then Audio.Envelope[I]:=0.025;end;
      if C<>6 then begin SetLength(Audio.Hits,Max(0,Floor((D-0.05)/Gap)+1));for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.05+I*Gap;Audio.Hits[I].Strength:=0.3+(I mod 8)*0.1;end;end
      else for I:=0 to High(Audio.Envelope) do Audio.Envelope[I]:=0;
      if C=7 then for I:=0 to High(Audio.Hits) do Audio.Hits[I].Time:=0.7+(I div 4)*0.03;
      if C=8 then Audio.Hits[0].Time:=0;
      Audio.UpdateSoundBounds;CreateGUID(Id);SourceFile:=TPath.Combine(CacheFolder,GUIDToString(Id)+'.identity');TFile.WriteAllText(SourceFile,GUIDToString(Id),TEncoding.UTF8);
      Audio.Source:=SourceFile;Audio.Key:=THashSHA2.GetHashString(GUIDToString(Id));Need(GetFileAttributesEx(PChar(SourceFile),GetFileExInfoStandard,@Info),'Source stamp');
      Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
      Plan:=TTrainPlan.Build(Audio);Need(Plan.PulseCount=Length(Audio.Hits),'Accents discarded');if Frequency=0 then Need(Plan.BossCount=0,'Disabled boss');
      if C=7 then Need(Plan.IntroTime>0,'Delayed score loses entrance');if C=0 then Need(Plan.IntroTime=0,'Immediate accent squeezes entrance');
      if C=0 then Need(Plan.BossCount>0,'Long song has no boss');if C=6 then Need((Plan.Count=0) and (Plan.EndTime=0),'Silence generates battle');
      Error:=0;for I:=0 to Plan.HitCount-1 do begin H:=Plan.Hit[I];T:=Plan.Event[H.Source].Time;Need(T=Audio.Hits[H.Source].Time,'Changed impact clock');
        if H.Mode=0 then begin Need(Plan.HitAt(I,T,P),'Missing physical shot');Error:=Max(Error,Hypot(P.X-H.B.X,P.Y-H.B.Y));Q:=Plan.EnemyAt(H.Enemy,T);R:=Plan.EnemySize(H.Enemy);Need(Abs(P.Y-0.006-Q.Y-R.Y)<1E-7,'Shot misses hull');end;
      end;Need(Error<1E-7,'Impact error');
      Grazes:=0;Intercepts:=0;for I:=0 to Plan.ShotCount-1 do begin S:=Plan.Shot[I];if S.Outcome=2 then Inc(Grazes);if S.Outcome=1 then Inc(Intercepts);
        if I mod Max(1,Plan.ShotCount div 1024)<>0 then Continue;
        if S.Outcome=2 then begin Q:=Plan.HeroCarAt(S.Car,S.Near);Need(Abs(S.B.Y-Q.Y+0.047)<1E-7,'Graze endpoint');end;
        for J:=0 to 12 do begin T:=S.Start+(S.Finish-S.Start)*J/13;if not Plan.ShotAt(I,T,P) then Continue;
          for K:=0 to 7 do begin Q:=Plan.HeroCarAt(K,T);Need((Abs(P.X-Q.X)>0.058) or (Abs(P.Y-Q.Y)>0.033),'Unplanned incoming hull hit');
            Need((Abs(P.X-Q.X)>=0.014) or (P.Y<=Q.Y-0.072) or (P.Y>=Q.Y-0.015),'Incoming shot crosses gun');
          end;
        end;
      end;
      if C=0 then begin Need(Grazes>0,'No light-hit recovery');Need(Intercepts>0,'No interceptions');end;
      MaxAlive:=0;MaxThreats:=0;for I:=0 to 200 do begin T:=Plan.EndTime*I/200;Plan.VisibleEnemies(T,First,Last);Alive:=0;
        for J:=First to Last do begin Idx:=Plan.VisibleEnemy(J);E:=Plan.Enemy[Idx];P:=Plan.EnemyAt(Idx,T);R:=Plan.EnemySize(Idx);
          if (T<Plan.Event[E.KillSource].Time) and (P.X+R.X>=0) and (P.X-R.X<=16/9) then Inc(Alive);end;MaxAlive:=Max(MaxAlive,Alive);
        Threats:=0;for J:=Max(0,Plan.ShotBefore(T-1.6)+1) to Plan.ShotBefore(T) do if Plan.ShotAt(J,T,P) and (P.X>=0) and (P.X<=16/9) and (P.Y>=0) and (P.Y<=1) then Inc(Threats);MaxThreats:=Max(MaxThreats,Threats);
      end;
      Ref:=NewPlanRef(Audio.Key,50,0,rsTrain,StyleVariant(rsTrain,50,Frequency));Ref.SourceRevision:=Audio.SourceRevision;Plan.Save(Ref,Audio);
      Need(TFile.GetSize(TPath.Combine(PlanFolder,Ref.Key+'.json'))<32*1024*1024,'Oversized JSON');
      Meta:=TTrainPlan.LoadAudioMetadata(Ref,SourceFile,0);Need((Length(Meta.PCM)=0) and (Length(Meta.Envelope)=0) and (Meta.BossFrequency=Frequency),'Cold metadata decodes audio');Cold:=TTrainPlan.Load(Ref,Meta,0);
      Need((Cold.Count=Plan.Count) and (Cold.BossCount=Plan.BossCount) and (Cold.ShotCount=Plan.ShotCount),'Cold score changed');
      for I:=0 to 127 do begin T:=(Plan.EndTime+2)*((I*73) mod 131)/131;
        for J:=0 to 7 do begin P:=Plan.HeroCarAt(J,Min(T,Plan.EndTime));Q:=Cold.HeroCarAt(J,Min(T,Cold.EndTime));Need(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-10,'Seek changes own formation');end;
        Need(Abs(Plan.CameraAt(T)-Cold.CameraAt(T))<1E-12,'Seek changes camera');Need(Plan.SceneAt(T)=Cold.SceneAt(T),'Seek changes scene');
      end;
      if C=0 then begin
        Scene:=TTrainAnimation.Create;Scene.Audio:=Audio;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;
        Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);PNG:=TPngImage.Create;
        Snapshot('train-normal',5.3);T:=Plan.Boss[0].Show+3;Snapshot('train-boss',T);Hash:=ImageHash;
        Renderer.Render(Image,Plan.EndTime+10,0);Renderer.Render(Image,T,0);Need(ImageHash=Hash,'Native shuffled frame changed');
        for I:=1 to 400 do if Plan.SceneAt(Plan.EndTime*I/400)<>0 then begin Snapshot('train-landmark',Plan.EndTime*I/400);Break;end;
        for I:=0 to Plan.ShotCount-1 do if Plan.Shot[I].Outcome=2 then begin Snapshot('train-graze',Plan.Shot[I].Near+0.08);Break;end;
        Snapshot('train-finish',Plan.GoalTime+0.6);FreeAndNil(Renderer);
        Scene:=TTrainAnimation.Create;Scene.Audio:=Meta;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;
        Renderer.Render(Image,T,0);Need(ImageHash=Hash,'Cold native frame differs');
        Image.SetSize(720,1280);Snapshot('train-portrait',T);FreeAndNil(Renderer);FreeAndNil(Image);FreeAndNil(PNG);
      end;
      Writeln(Format('case=%d events=%d enemies=%d hits=%d shots=%d bosses=%d maxVisibleEnemies=%d maxVisibleThreats=%d grazes=%d intercepts=%d bytes=%d',[C,Plan.PulseCount,Plan.EnemyCount,Plan.HitCount,Plan.ShotCount,Plan.BossCount,MaxAlive,MaxThreats,Grazes,Intercepts,TFile.GetSize(TPath.Combine(PlanFolder,Ref.Key+'.json'))]));
      FreeAndNil(Cold);FreeAndNil(Plan);FreeAndNil(Meta);FreeAndNil(Audio);
    end;
    Audio:=TRhythmAudio.Create;Audio.Duration:=1;Audio.SoundEnd:=0;Rejected:=False;try Plan:=TTrainPlan.Build(Audio,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;Need(Rejected,'Cancellation ignored');FreeAndNil(Audio);
    Writeln('TrainPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Renderer.Free;Image.Free;PNG.Free;Cold.Free;Plan.Free;Meta.Free;Audio.Free;
end.
