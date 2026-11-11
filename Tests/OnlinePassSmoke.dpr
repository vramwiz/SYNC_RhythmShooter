program OnlinePassSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.IOUtils,System.Hash,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmStyles,RhythmPlanRef,
  RhythmJumpBuild,RhythmJumpCodec,RhythmJumpPlan,RhythmJumpScene,RhythmPresentation,RhythmFireworksScene,
  RhythmAnimation,RhythmImageBank;
var Audio,Cold:TRhythmAudio;Plan:TJumpPlan;Ref:TRhythmPlanRef;
  Scene:TJumpAnimation;Presented:TRhythmPresentationScene;Render:TAnimationRenderer;Image:TBitmap;
  J,N,Calls:Integer;OutDir,Source,FrameHash:string;Stamp:TWin32FileAttributeData;Time,Goal:Double;
  Report,Entry:TJSONObject;Entries:TJSONArray;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
function BitmapHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Hash:THashSHA2;
begin Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;Stream.ReadBuffer(Bytes[0],Length(Bytes));Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;finally Stream.Free;end;end;
procedure Snapshot(const Name:string;T:Double);
var PNG:TPngImage;
begin Render.Render(Image,T,0);Need(Render.Notice='','Material warning');Need(Scene.Notice='','Jump scene load: '+Scene.Notice);PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(OutDir,Name+'.png'));finally PNG.Free;end;end;
procedure CheckFireworks(Time:Double;Visible:Boolean);
var Before:string;
begin
  Presented.Audio:=nil;
  Render.Render(Image,Time,0);
  Before:=BitmapHash;
  Presented.Audio:=Cold;
  Render.Render(Image,Time,0);
  Need((BitmapHash<>Before)=Visible,'Fireworks outside the goal interval or missing at goal');
end;
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
  Audio:=nil;Cold:=nil;Plan:=nil;Render:=nil;Image:=nil;Report:=nil;
  try
    OutDir:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Frames');ForceDirectories(OutDir);Source:=TPath.Combine(OutDir,'native-source.identity');TFile.WriteAllText(Source,'synthetic fixed accent fixture; no audio playback',TEncoding.UTF8);
    MakeAudio;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);Report:=TJSONObject.Create;Entries:=TJSONArray.Create;Report.AddPair('frames',Entries);Calls:=0;
    Audio.SetBossFrequency(50);
    Ref:=NewPlanRef(Audio.Key,50,0,rsJumpAdventure,StyleVariant(rsJumpAdventure,50,50),0,Audio.Key);
    Ref.SourceRevision:=Audio.SourceRevision;
    Plan:=BuildJumpPlan(Audio,Ref.Generation,nil);
    SaveJumpPlan(Plan,Audio,Ref);
    Goal:=Plan.Nodes[High(Plan.Nodes)].Time;
    Cold:=LoadJumpAudio(Ref,Source,0);Need(Length(Cold.PCM)=0,'Jump cold read has PCM');
    Scene:=TJumpAnimation.Create;Scene.Audio:=Cold;Scene.SetReference(Ref);
    Presented:=TRhythmPresentationScene.Create(Scene);
    Presented.Audio:=Cold;
    Render:=TAnimationRenderer.Create(Presented,TAnimationImageBank.Create(0));Render.UseD2D:=False;
    N:=0;for J:=0 to High(Plan.Nodes) do if Plan.Nodes[J].Landing in [jlStomp,jlRoll] then begin
      Time:=Plan.Nodes[J].Time;Snapshot('jump-'+IntToStr(N)+'-windup',Max(0.0,Time-0.025));Snapshot('jump-'+IntToStr(N)+'-contact',Time);Snapshot('jump-'+IntToStr(N)+'-follow',Time+0.035);Inc(N);if N=4 then Break;
    end;
    for J:=0 to 31 do begin Time:=Plan.Duration*((J*17) mod 37)/37;Render.Render(Image,Time,0);FrameHash:=BitmapHash;Render.Render(Image,Plan.Duration-Time,0);Render.Render(Image,Time,0);Need(BitmapHash=FrameHash,'Jump seek image drift');Inc(Calls);end;
    Entry:=TJSONObject.Create;Entries.AddElement(Entry);Entry.AddPair('style',StyleId(rsJumpAdventure));Entry.AddPair('version',TJSONNumber.Create(Ref.Version));Entry.AddPair('rollingItems',TJSONNumber.Create(Length(Plan.Rolls)));
    CheckFireworks(Goal-0.01,False);
    CheckFireworks(Goal+0.30,True);
    CheckFireworks(Goal+GoalFireworksDuration+0.01,False);
    Snapshot('goal-fireworks',Goal+0.38);
    Report.AddPair('nativeRenderSeekChecks',TJSONNumber.Create(Calls));Report.AddPair('audioPlayback',TJSONBool.Create(False));TFile.WriteAllText(TPath.Combine(OutDir,'native-render.json'),Report.ToJSON,TEncoding.UTF8);Writeln('OnlinePassSmoke passed; snapshots: '+OutDir);
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Report.Free;Render.Free;Image.Free;Plan.Free;Cold.Free;Audio.Free;
end.
