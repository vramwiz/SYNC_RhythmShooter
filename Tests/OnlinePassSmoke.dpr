program OnlinePassSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.IOUtils,System.Hash,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmPaths,
  RhythmRunnerAction,RhythmRunnerPlan,RhythmRunnerScene,RhythmFireworksPlan,RhythmFireworksScene,
  RhythmAnimation,RhythmImageBank;
var Audio,Cold:TRhythmAudio;Runner:TRunnerPlan;Fire:TFireworksPlan;Ref:TRhythmPlanRef;
  Scene:TRunnerAnimation;FireScene:TFireworksAnimation;Render:TAnimationRenderer;Image:TBitmap;
  J,N,Calls:Integer;OutDir,Source,FrameHash:string;Stamp:TWin32FileAttributeData;Time:Double;
  Report,Entry:TJSONObject;Entries:TJSONArray;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
function BitmapHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Hash:THashSHA2;
begin Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;Stream.ReadBuffer(Bytes[0],Length(Bytes));Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;finally Stream.Free;end;end;
procedure Snapshot(const Name:string;T:Double);
var PNG:TPngImage;
begin Render.Render(Image,T,0);Need(Render.DesignWarning='','Material warning');if Runner<>nil then Need(Scene.Notice='','Runner scene load: '+Scene.Notice) else if Fire<>nil then Need(FireScene.Notice='','Firework scene load: '+FireScene.Notice);PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(OutDir,Name+'.png'));finally PNG.Free;end;end;
procedure MakeAudio;
var K:Integer;T,Gap:Double;
begin
  Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.Key:=THashSHA2.GetHashString('online-pass-native-fixture');Audio.Sensitivity:=50;Audio.Duration:=96;
  Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Fixture stat');
  Audio.SourceRevision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
  SetLength(Audio.Envelope,9600);for K:=0 to 8999 do begin Audio.Envelope[K]:=0.12;if ((K>=1800) and (K<3500)) or ((K>=5600) and (K<7600)) then Audio.Envelope[K]:=0.8;end;
  SetLength(Audio.Hits,2000);N:=0;T:=0.4;while T<90 do begin Audio.Hits[N].Time:=T;Audio.Hits[N].Strength:=0.25+(N mod 6)*0.15;Inc(N);Gap:=0.30;if ((T>=18) and (T<35)) or ((T>=56) and (T<76)) then Gap:=0.08;T:=T+Gap;end;SetLength(Audio.Hits,N);Audio.UpdateSoundBounds;
end;
begin
  Audio:=nil;Cold:=nil;Runner:=nil;Fire:=nil;Render:=nil;Image:=nil;Report:=nil;
  try
    OutDir:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Frames');ForceDirectories(OutDir);Source:=TPath.Combine(OutDir,'native-source.identity');TFile.WriteAllText(Source,'synthetic fixed accent fixture; no audio playback',TEncoding.UTF8);
    MakeAudio;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);Report:=TJSONObject.Create;Entries:=TJSONArray.Create;Report.AddPair('frames',Entries);Calls:=0;
    ConfigureRhythmProduct('SYNC_RhythmRunner','Native runner check',rsRunner);Runner:=TRunnerPlan.Build(Audio);Ref:=NewPlanRef(Audio.Key,50,0,rsRunner);Ref.SourceRevision:=Audio.SourceRevision;Runner.Save(Ref,Audio);
    Need((Runner.Action<>nil) and (Runner.Action.ModeCount(rmSword)>0),'ABC sword section missing');
    Cold:=TRunnerPlan.LoadAudioMetadata(Ref,Source,0);Need(Length(Cold.PCM)=0,'Runner cold read has PCM');
    Scene:=TRunnerAnimation.Create;Scene.Audio:=Cold;Scene.SetReference(Ref);Render:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Render.UseD2D:=False;
    N:=0;for J:=0 to High(Runner.Action.Hits) do if Runner.Action.Hits[J].Kind in [rhSword,rhBossCut,rhParry,rhDodge,rhFinish] then begin
      Time:=Runner.Action.Hits[J].Time;Snapshot('runner-'+IntToStr(N)+'-windup',Max(0.0,Time-0.025));Snapshot('runner-'+IntToStr(N)+'-contact',Time);Snapshot('runner-'+IntToStr(N)+'-follow',Time+0.035);Inc(N);if N=4 then Break;
    end;
    for J:=0 to 31 do begin Time:=Runner.EndTime*((J*17) mod 37)/37;Render.Render(Image,Time,0);FrameHash:=BitmapHash;Render.Render(Image,Runner.EndTime-Time,0);Render.Render(Image,Time,0);Need(BitmapHash=FrameHash,'Runner seek image drift');Inc(Calls);end;
    Entry:=TJSONObject.Create;Entries.AddElement(Entry);Entry.AddPair('style','runner');Entry.AddPair('version',TJSONNumber.Create(Ref.Version));Entry.AddPair('contacts',TJSONNumber.Create(Length(Runner.Action.Hits)));Entry.AddPair('actors',TJSONNumber.Create(Runner.Action.EnemyCount));
    FreeAndNil(Render);FreeAndNil(Cold);FreeAndNil(Runner);
    ConfigureRhythmProduct('SYNC_RhythmFireworks','Native firework check',rsFireworks);Fire:=TFireworksPlan.Build(Audio,0,70);Ref:=NewPlanRef(Audio.Key,50,0,rsFireworks,70);Ref.SourceRevision:=Audio.SourceRevision;Fire.Save(Ref);
    Cold:=TFireworksPlan.LoadAudioMetadata(Ref,Source,0);Need((Length(Cold.PCM)=0) and (Length(Cold.Hits)=Length(Audio.Hits)),'Firework cold descriptor');
    FireScene:=TFireworksAnimation.Create;FireScene.Audio:=Cold;FireScene.SetReference(Ref);Render:=TAnimationRenderer.Create(FireScene,TAnimationImageBank.Create([],0));Render.UseD2D:=False;
    for J:=0 to 3 do Snapshot('fireworks-'+IntToStr(J),20+J*5.7);
    for J:=0 to 31 do begin Time:=Fire.EndTime*((J*17) mod 37)/37;Render.Render(Image,Time,0);FrameHash:=BitmapHash;Render.Render(Image,Fire.EndTime-Time,0);Render.Render(Image,Time,0);Need(BitmapHash=FrameHash,'Fireworks seek image drift');Inc(Calls);end;
    Entry:=TJSONObject.Create;Entries.AddElement(Entry);Entry.AddPair('style','fireworks');Entry.AddPair('version',TJSONNumber.Create(Ref.Version));Entry.AddPair('blooms',TJSONNumber.Create(Fire.Count));
    Report.AddPair('nativeRenderSeekChecks',TJSONNumber.Create(Calls));Report.AddPair('audioPlayback',TJSONBool.Create(False));TFile.WriteAllText(TPath.Combine(OutDir,'native-render.json'),Report.ToJSON,TEncoding.UTF8);Writeln('OnlinePassSmoke passed; snapshots: '+OutDir);
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Report.Free;Render.Free;Image.Free;Fire.Free;Runner.Free;Cold.Free;Audio.Free;
end.
