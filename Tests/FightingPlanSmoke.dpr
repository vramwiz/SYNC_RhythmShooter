program FightingPlanSmoke;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,System.Math,System.Classes,System.IOUtils,System.Hash,Winapi.Windows,Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmFightingPlan in '..\Source\Fighting\RhythmFightingPlan.pas',
  RhythmFightingScene in '..\Source\Fighting\RhythmFightingScene.pas',
  RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmProduct,RhythmPaths,RhythmAnimation,RhythmImageBank;
var Audio,Meta:TRhythmAudio;Plan,Cold,RejectedPlan:TFightingPlan;Ref,Bad:TRhythmPlanRef;
  Scene:TFightingAnimation;Renderer:TAnimationRenderer;Image:TBitmap;PNG:TPngImage;
  I,J,K,C,N,Frequency,MaxBodies,MaxShots,Bodies,Shots:Integer;D,Gap,T,BeforeSpeed,NearSpeed,MaxReach,Error,MaxError,Zoom,CX,CY,ColdZoom,ColdCX,ColdCY:Double;
  H:TFightHit;E:TFightEnemy;P,Q:TFightPose;Pos,Other:TFightPoint;A:Double;
  Info:TWin32FileAttributeData;Identity,OutDir,Hash,Terminal:string;Rejected:Boolean;Id:TGUID;
procedure Need(Value:Boolean;const Msg:string);begin if not Value then raise Exception.Create(Msg);end;
function ImageHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Hasher:THashSHA2;
begin Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;if Length(Bytes)>0 then Stream.ReadBuffer(Bytes[0],Length(Bytes));Hasher:=THashSHA2.Create;Hasher.Update(Bytes);Result:=Hasher.HashAsString;finally Stream.Free;end;end;
procedure SaveFrame(const Name:string;Time:Double;Width:Integer=1280;Height:Integer=720);
begin Image.SetSize(Width,Height);Renderer.Render(Image,Time,0);PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(OutDir,Name+'.png'));end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Cold:=nil;RejectedPlan:=nil;Renderer:=nil;Image:=nil;PNG:=nil;MaxBodies:=0;MaxShots:=0;MaxReach:=0;MaxError:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmFighting','音楽同期格闘',rsFighting);
    OutDir:=ExtractFilePath(ParamStr(0));ForceDirectories(OutDir);
    Need((Ord(rsFighting)=7) and (StylePlanVersion(rsFighting)=1),'Style identity');
    for C:=0 to 8 do begin
      D:=32;Gap:=0.18;Frequency:=50;
      case C of 1:begin D:=16;Gap:=0.008;end;2:begin D:=3000;Gap:=0.16;end;3:begin D:=0.10;Gap:=0.01;end;4:begin D:=1;Gap:=1;end;5:D:=180;6:begin D:=180;Frequency:=0;end;7:begin D:=180;Gap:=1.1;end;8:begin D:=16;Gap:=0.09;end;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=D;Audio.SoundEnd:=D;Audio.Sensitivity:=50;Audio.SetBossFrequency(Frequency);
      SetLength(Audio.Envelope,Ceil(D*100));for I:=0 to High(Audio.Envelope) do Audio.Envelope[I]:=0.75;
      if D>=90 then for I:=0 to High(Audio.Envelope) do if ((I div 100>=45) and (I div 100<50)) or ((I div 100>=100) and (I div 100<108)) then Audio.Envelope[I]:=0.01;
      N:=Floor((D-0.005)/Gap)+1;if C=4 then N:=0;SetLength(Audio.Hits,N);
      for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.005+I*Gap;Audio.Hits[I].Strength:=0.25+(I mod 6)*0.15;end;
      if C=8 then begin Audio.Hits[0].Time:=0;Audio.Hits[1].Time:=0;end;
      Audio.UpdateSoundBounds;if C=4 then Audio.SoundEnd:=0;
      CreateGUID(Id);Identity:=TPath.Combine(CacheFolder,GUIDToString(Id)+'.fighting-identity');TFile.WriteAllText(Identity,'fighting-native-'+GUIDToString(Id),TEncoding.UTF8);
      Audio.Source:=Identity;Audio.Key:=THashSHA2.GetHashString(Identity);
      if not GetFileAttributesEx(PChar(Identity),GetFileExInfoStandard,@Info) then RaiseLastOSError;
      Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
      Plan:=TFightingPlan.Build(Audio);Need(Plan.Count=N,'Valid impact count');Need(Plan.PulseCount=N,'Pulse count');if Frequency=0 then Need(Plan.BossCount=0,'Boss frequency zero');if C=5 then Need(Plan.BossCount>0,'Long song lacks boss');
      for I:=0 to Plan.Count-1 do begin H:=Plan.Hit[I];Need(H.Time=Audio.Hits[H.Source].Time,'Impact clock shifted');P:=Plan.HeroAt(H.Time);Error:=Abs(P.Attack-1);MaxError:=Max(MaxError,Error);Need(Error<1E-7,'Impact pose not extended');E:=Plan.Enemy[H.Enemy];
        Error:=Abs(P.ContactX-H.Contact.X)+Abs(P.ContactY-H.Contact.Y);MaxError:=Max(MaxError,Error);Need(Error<1E-7,'Weapon contact mismatch');
        if E.Boss<0 then Need(Abs(H.Contact.X-(E.X-H.Side*0.036))<1E-7,'Enemy surface mismatch') else begin Pos:=Plan.BossCenter(E.Boss,H.Time);Need(Abs(H.Contact.X-(Pos.X-H.Side*0.20))<1E-7,'Boss surface mismatch');end;
        if H.Kind=1 then A:=Hypot(H.Contact.X-H.Side*0.017-P.X,H.Contact.Y-(P.Y-0.046)) else A:=Hypot(H.Contact.X-H.Side*0.014-(P.X+H.Side*0.022),H.Contact.Y-(P.Y-0.100));
        MaxReach:=Max(MaxReach,A);if H.Kind=1 then Need(A<0.171,'Kick cannot reach enemy') else Need(A<0.155,'Punch cannot reach enemy');
        if (I=E.FirstHit) and (H.Time>0.001) then begin P:=Plan.HeroAt(H.Time-0.001);if E.Boss<0 then Other:=Plan.EnemyAt(H.Enemy,H.Time-0.001) else begin Other:=Plan.BossCenter(E.Boss,H.Time-0.001);Other.X:=Other.X-H.Side*0.164;end;
          if H.Kind=1 then A:=P.X+H.Side*0.029+(P.ContactX-H.Side*0.017-(P.X+H.Side*0.029))*P.Attack+H.Side*(0.027-0.010*P.Attack)
          else begin A:=P.X+P.Lean*0.035+P.Side*P.Attack*0.006+H.Side*0.055;A:=A+(P.ContactX-H.Side*0.014-A)*P.Attack+H.Side*0.014;end;
          Need(H.Side*(Other.X-H.Side*0.036-A)>-0.00005,'Premature first contact');
        end;
      end;
      Ref:=NewPlanRef(Audio.Key,50,0,rsFighting,StyleVariant(rsFighting,50,Frequency));Ref.SourceRevision:=Audio.SourceRevision;Plan.Save(Ref,Audio);
      Meta:=TFightingPlan.LoadAudioMetadata(Ref,Identity,0);Need(Length(Meta.PCM)=0,'PCM restored');Need(Meta.BossFrequency=Frequency,'Frequency not restored');Cold:=TFightingPlan.Load(Ref,Meta,0);
      Need((Cold.Count=Plan.Count) and (Cold.BossCount=Plan.BossCount) and (Cold.EnemyCount=Plan.EnemyCount),'Cold plan count');
      for I:=0 to 127 do begin T:=Plan.EndTime*((I*73) mod 131)/131;P:=Plan.HeroAt(T);Q:=Cold.HeroAt(T);Need((Abs(P.X-Q.X)<1E-10) and (Abs(P.Y-Q.Y)<1E-10) and (Abs(P.ContactX-Q.ContactX)<1E-10) and (Abs(P.Attack-Q.Attack)<1E-8),Format('Cold/seek changes pose case%d t%.12f x%.12f/%.12f contact%.12f/%.12f attack%.12f/%.12f',[C,T,P.X,Q.X,P.ContactX,Q.ContactX,P.Attack,Q.Attack]));
        Plan.CameraAt(T,CX,CY,Zoom);Need((Zoom>=1) and (Zoom<=1.181),'Camera bounds');Cold.CameraAt(T,ColdCX,ColdCY,ColdZoom);Need((Abs(CX-ColdCX)<1E-9) and (Abs(CY-ColdCY)<1E-9) and (Abs(Zoom-ColdZoom)<1E-9) and (Plan.ThemeAt(T)=Cold.ThemeAt(T)),'Cold camera/stage');
        J:=Plan.EnemyBefore(T);if J>=0 then begin Pos:=Plan.EnemyAt(J,T);Other:=Cold.EnemyAt(J,T);Need(Hypot(Pos.X-Other.X,Pos.Y-Other.Y)<1E-9,'Cold enemy movement');end;
        if Plan.BossCount>0 then begin J:=I mod Plan.BossCount;Need(Abs(Plan.BossHealth(J,T)-Cold.BossHealth(J,T))<1E-10,'Cold boss HP');end;
        J:=Plan.VolleyBefore(T);if J>=0 then begin K:=Plan.Volley[J].Count div 2;Rejected:=Plan.ShotAt(J,K,T,Pos,A);Need(Cold.ShotAt(J,K,T,Other,Error)=Rejected,'Cold shot lifetime');if Rejected then Need((Hypot(Pos.X-Other.X,Pos.Y-Other.Y)<1E-9) and (Abs(A-Error)<1E-9),'Cold shot trajectory');end;
        Bodies:=0;Shots:=0;
        for J:=Max(0,Plan.EnemyBefore(T-0.90)+1) to Plan.EnemyBefore(T+2) do begin E:=Plan.Enemy[J];if (E.Boss<0) and (T>=E.Spawn) and (T<E.Kill+0.75) then Inc(Bodies);end;
        for J:=Max(0,Plan.VolleyBefore(T-0.80)+1) to Plan.VolleyBefore(T) do for K:=0 to Plan.Volley[J].Count-1 do if Plan.ShotAt(J,K,T,Pos,A) then Inc(Shots);
        MaxBodies:=Max(MaxBodies,Bodies);MaxShots:=Max(MaxShots,Shots);
      end;
      Bad:=Ref;Bad.Digest:=StringOfChar('0',64);Rejected:=False;try RejectedPlan:=TFightingPlan.Load(Bad,Meta,0);except Rejected:=True;end;Need(Rejected,'Digest accepted');
      if C in [0,5,8] then begin
        Scene:=TFightingAnimation.Create;Scene.Audio:=Meta;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;
        Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);PNG:=TPngImage.Create;
        T:=Min(8.23,Plan.EndTime*0.5);Renderer.Render(Image,T,0);Hash:=ImageHash;Renderer.Render(Image,Plan.EndTime+2,0);Terminal:=ImageHash;Renderer.Render(Image,Plan.EndTime+20,0);Need(ImageHash=Terminal,'End is not stable');Renderer.Render(Image,T,0);Need(ImageHash=Hash,'Random seek changes bitmap');
        if C=0 then begin SaveFrame('crowd-impact',Plan.Hit[30].Time);SaveFrame('crowd-defense',Plan.Hit[35].Time-0.13);SaveFrame('crowd-blowout',Plan.Hit[30].Time+0.09);SaveFrame('portrait',Plan.Hit[30].Time,720,1280);end;
        if (C=5) and (Plan.BossCount>0) then begin SaveFrame('boss-intro',Plan.Boss[0].Start+0.4);SaveFrame('boss-fight',(Plan.Boss[0].Ready+Plan.Boss[0].Kill)/2);SaveFrame('boss-purge',Plan.Boss[0].Purge[1]+0.10);SaveFrame('boss-defeat',Plan.Boss[0].Kill+0.14);end;
        if C=8 then SaveFrame('fast-combo',Plan.Hit[40].Time);
        FreeAndNil(Renderer);FreeAndNil(Image);FreeAndNil(PNG);
      end;
      if (C=0) and (Plan.EnemyCount>2) then begin E:=Plan.Enemy[2];Pos:=Plan.EnemyAt(2,E.Ready-0.8);Other:=Plan.EnemyAt(2,E.Ready-0.79);BeforeSpeed:=Abs(Other.X-Pos.X)/0.01;Pos:=Plan.EnemyAt(2,E.Ready-0.01);Other:=Plan.EnemyAt(2,E.Ready);NearSpeed:=Abs(Other.X-Pos.X)/0.01;Need(NearSpeed>BeforeSpeed*1.5,'Approach lacks acceleration');end;
      Writeln(Format('case=%d events=%d enemies=%d bosses=%d volleys=%d stages=%d',[C,Plan.Count,Plan.EnemyCount,Plan.BossCount,Plan.VolleyCount,Plan.StageCount]));
      FreeAndNil(Plan);FreeAndNil(Cold);FreeAndNil(Meta);FreeAndNil(Audio);
    end;
    Writeln(Format('FightingPlanSmoke passed: maxBodies=%d maxShots=%d maxReach=%.6f impactError=%.12f approach=%.4f->%.4f',[MaxBodies,MaxShots,MaxReach,MaxError,BeforeSpeed,NearSpeed]));
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Renderer.Free;Image.Free;PNG.Free;Plan.Free;Cold.Free;RejectedPlan.Free;Meta.Free;Audio.Free;
end.
