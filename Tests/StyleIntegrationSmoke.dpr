program StyleIntegrationSmoke;
{$APPTYPE CONSOLE}
{$POINTERMATH ON}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,AviUtl2FilterTypes,RhythmAudio,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmSettings,
  RhythmPrepare,RhythmScene,RhythmStyleRegistry,RhythmPaths,RhythmMotion;
type TInitPlugin=function(Version:DWORD):Byte;cdecl;
 TDonePlugin=procedure;cdecl;
 TGetPlugin=function:PFILTER_PLUGIN_TABLE;cdecl;
var Captured:TBytes;CapturedWidth,CapturedHeight:Integer;
var Root,Source,Revision,Expected,Actual:string;Stamp:TWin32FileAttributeData;Style:TRhythmStyle;
  Audio,Cold:TRhythmAudio;Worker:TRhythmPrepareThread;Ref:TRhythmPlanRef;Renderer:TRhythmRenderer;
  Image:TBitmap;Settings,Restored:TRhythmSettings;Backend,Meter,J,Checks,HostChecks,MusicChecks,OffsetChecks,Density,StylesChecked,BaseHits:Integer;T,Shift:Double;PNG:TPngImage;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
function MakeAudio:TRhythmAudio;
var I,J,Start:Integer;Time,Gap,Phase:Double;Samples:PSmallInt;V:SmallInt;
begin
 Result:=TRhythmAudio.Create;Result.Source:=Source;Result.Key:=THashSHA2.GetHashString('shared-preparation-native-v1');Result.Sensitivity:=50;Result.SourceRevision:=Revision;Result.Duration:=100;
 // 初見殺しは小数秒の曲で保存後の丸め差も含めて実DLLの復元を検査する。
 if Style=rsTrapAction then Result.Duration:=100+1523/RHYTHM_RATE;
 SetLength(Result.Envelope,10000);for I:=0 to 9499 do if ((I>2200) and (I<4300)) or ((I>6500) and (I<8500)) then Result.Envelope[I]:=0.85 else Result.Envelope[I]:=0.16;
 if Density<AUDIO_DEFAULT_DENSITY then SetLength(Result.PCM,100*RHYTHM_RATE*4);
 Samples:=PSmallInt(Result.PCM);
 SetLength(Result.Hits,3000);I:=0;Time:=0.5;
 while Time<94 do begin
  Result.Hits[I].Time:=Time;Result.Hits[I].Strength:=0.28+(I mod 7)*0.12;Result.Hits[I].Lane:=0.5;
  if Density=100 then Result.Hits[I].Strength:=Min(0.98,Result.Hits[I].Strength);
  Result.Hits[I].Flight:=ShotFlightTime(Time,0.5,Result.Hits[I].Strength);
  Inc(I);Gap:=0.32;
  if ((Time>22) and (Time<43)) or ((Time>65) and (Time<85)) then Gap:=0.10
  else if Samples<>nil then begin
   Gap:=0.58;Start:=Round((Time+0.28)*RHYTHM_RATE)*2;
   for J:=0 to 1499 do begin
    Phase:=J/RHYTHM_RATE;
    V:=Round(14500*Exp(-85*Phase)*(0.7*Sin(2*Pi*810*Phase)+0.3*Sin(2*Pi*3150*Phase)));
    Samples[Start+J*2]:=V;Samples[Start+J*2+1]:=V;
   end;
  end;
  Time:=Time+Gap;
 end;
 SetLength(Result.Hits,I);Result.UpdateSoundBounds;
end;
procedure SaveShootingFixture;
var O,Index,Hit:TJSONObject;Envelope,Hits:TJSONArray;I:Integer;
begin
 O:=TJSONObject.Create;Index:=TJSONObject.Create;
 try
  O.AddPair('schema',TJSONNumber.Create(1));O.AddPair('analysisVersion',TJSONNumber.Create(2));
  O.AddPair('sourceSHA256',Audio.Key);O.AddPair('sensitivity',TJSONNumber.Create(50));O.AddPair('duration',TJSONNumber.Create(Audio.Duration));
  Envelope:=TJSONArray.Create;O.AddPair('envelope',Envelope);for I:=0 to High(Audio.Envelope) do Envelope.Add(Audio.Envelope[I]);
  Hits:=TJSONArray.Create;O.AddPair('hits',Hits);for I:=0 to High(Audio.Hits) do begin Hit:=TJSONObject.Create;Hits.AddElement(Hit);
   Hit.AddPair('time',TJSONNumber.Create(Audio.Hits[I].Time));Hit.AddPair('strength',TJSONNumber.Create(Audio.Hits[I].Strength));Hit.AddPair('lane',TJSONNumber.Create(Audio.Hits[I].Lane));end;
  TFile.WriteAllText(TPath.Combine(CacheFolder,Audio.Key+'-s50-events-v1.json'),O.ToJSON,TEncoding.UTF8);
  Index.AddPair('sourceSHA256',Audio.Key);Index.AddPair('sourceStamp',Revision);
  TFile.WriteAllText(TPath.Combine(CacheFolder,THashSHA2.GetHashString(LowerCase(ExpandFileName(Source)))+'-s50-index.json'),Index.ToJSON,TEncoding.UTF8);
 finally O.Free;Index.Free;end;
end;
function ImageHash:string;
var S:TMemoryStream;B:TBytes;H:THashSHA2;
begin S:=TMemoryStream.Create;try Image.SaveToStream(S);SetLength(B,S.Size);S.Position:=0;S.ReadBuffer(B[0],Length(B));H:=THashSHA2.Create;H.Update(B);Result:=H.HashAsString;finally S.Free;end;end;
function ProductForStyle:string;
begin case Style of rsBall:Result:='SYNC_RhythmBall';rsBreakout:Result:='SYNC_RhythmBreakout';rsBombAction:Result:='SYNC_RhythmBombAction';rsMining:Result:='SYNC_RhythmMining';rsTrain:Result:='SYNC_RhythmTrain';rsRhythmGame,rsStepGame:Result:='SYNC_RhythmGame';else Result:='SYNC_RhythmShooter';end;end;
procedure CaptureHost(Buffer:PPIXEL_RGBA;W,H:Integer);cdecl;
begin CapturedWidth:=W;CapturedHeight:=H;SetLength(Captured,W*H*4);Move(Buffer^,Captured[0],Length(Captured));end;
procedure VerifyHost;
var Lib:HMODULE;Init:TInitPlugin;Done:TDonePlugin;GetTable:TGetPlugin;Table:PFILTER_PLUGIN_TABLE;
 Json:PFILTER_ITEM_STRING;Music:PFILTER_ITEM_FILE;Offset:PFILTER_ITEM_TRACK;Item:Pointer;I,X,Y,K,Rules:Integer;
 Kind,JsonText,MusicText,Path,Config,FirstHash,SecondHash,OriginalJSON,ModeHash:string;SavedEqualizer,Mode:Integer;
 Scene:TSCENE_INFO;Obj:TOBJECT_INFO;Video:TFILTER_PROC_VIDEO;Hash:THashSHA2;Row:PByte;
 Expected,OriginalSource:TBytes;FileHandle:THandle;SavedStamp:TWin32FileAttributeData;
 procedure FindItems(Modern:Boolean);
 var MusicIndex,GroupIndex,OffsetIndex,N:Integer;Name:string;
 begin
  Json:=nil;Music:=nil;Offset:=nil;Rules:=0;MusicIndex:=-1;GroupIndex:=99;OffsetIndex:=-1;
  for N:=0 to 12 do begin
   Item:=PPointer(NativeUInt(Table.Items)+NativeUInt(N*SizeOf(Pointer)))^;if Item=nil then Break;
   Kind:=string(PWideChar(PPointer(Item)^));Name:=string(PWideChar(PPointer(NativeUInt(Item)+SizeOf(Pointer))^));
   Need((Kind<>'select') and (Name<>'スクロール方向') and (Name<>'小分類') and (Name<>'解析感度'),'Removed host settings still registered');
   if (Kind='track') and (Name='オフセット') then begin Offset:=PFILTER_ITEM_TRACK(Item);OffsetIndex:=N;end;
   if Kind='string' then Json:=PFILTER_ITEM_STRING(Item);
   if Kind='file' then begin Music:=PFILTER_ITEM_FILE(Item);MusicIndex:=N;Need(Name='音楽ファイル','SDK file label');end;
   if Kind='group' then GroupIndex:=N;
   if Kind='hiderule' then begin Inc(Rules);Need(Name<>'音楽ファイル','Music must remain visible');end;
  end;
  Need((Json<>nil) and (Music<>nil) and (Offset<>nil),'DLL JSON/file/offset items');
  Need((Offset.S=-1) and (Offset.E=1) and (Abs(Offset.Step-0.01)<1E-12),'Offset range or unit');
  Need((OffsetIndex<GroupIndex) and (OffsetIndex>=5),'Offset must remain visible');
  Need((MusicIndex=3) and (MusicIndex<GroupIndex),'Music visible before legacy group');
  if Modern then Need(Rules=1,'Only JSON is hidden') else Need(Rules=0,'Legacy host fallback');
 end;
 procedure Frame(const LabelText:string;Blank:Boolean);
 var B:Byte;
 begin
  Need(Table.Func_Proc_Video(@Video)=1,LabelText+' callback');
  Need((CapturedWidth=Image.Width) and (CapturedHeight=Image.Height),LabelText+' dimensions');
  if Blank then for B in Captured do if B<>0 then Need(False,LabelText+' must be transparent');
  Inc(MusicChecks);
 end;
 function CapturedHash:string;
 begin Hash:=THashSHA2.Create;Hash.Update(Captured);Result:=Hash.HashAsString;end;
 function PreviewHash:string;
 var X,Y:Integer;
 begin
   Renderer.ConfigureStyle(Style,Ref,100,Settings.EqualizerMode,Settings.MarbleBall,Settings.MarbleStage);
   Renderer.UseD2D:=True;Renderer.Render(Image,Cold,Obj.Time,0,'',1,0,0,Offset.Value);SetLength(Expected,Image.Width*Image.Height*4);K:=0;
   for Y:=0 to Image.Height-1 do begin Row:=Image.ScanLine[Y];for X:=0 to Image.Width-1 do begin
     Expected[K]:=Row[2];Expected[K+1]:=Row[1];Expected[K+2]:=Row[0];if Renderer.OutputHasAlpha then Expected[K+3]:=Row[3] else Expected[K+3]:=255;Inc(K,4);Inc(Row,4);
   end;end;
   Hash:=THashSHA2.Create;Hash.Update(Expected);Result:=Hash.HashAsString;
 end;
begin
 if ParamCount=0 then Exit;
 Config:='Release';if ParamCount>1 then Config:=ParamStr(2);Need((Config='Debug') or (Config='Release'),'DLL test configuration');
 Path:=TPath.Combine(ParamStr(1),ProductForStyle+'\'+Config+'\'+ProductForStyle+'.dll');
 Lib:=LoadLibraryEx(PChar(Path),0,LOAD_WITH_ALTERED_SEARCH_PATH);if Lib=0 then RaiseLastOSError;
 try
  @Init:=GetProcAddress(Lib,'InitializePlugin');@Done:=GetProcAddress(Lib,'UninitializePlugin');@GetTable:=GetProcAddress(Lib,'GetFilterPluginTable');
  Need(Assigned(Init) and Assigned(Done) and Assigned(GetTable),'DLL exports');Need(Init(2011500)=1,'DLL initialization');
  try
   Table:=GetTable();Need((Table<>nil) and Assigned(Table.Func_Proc_Video),'DLL filter callback');FindItems(True);
   // Host track wins over the Preview-only JSON snapshot. Changing it must not reprepare or alter the plan.
   Settings.HostMusic:=True;Settings.OffsetSeconds:=0.41;Offset.Value:=0;JsonText:=Settings.ToJSON;OriginalJSON:=JsonText;Json.Value:=PWideChar(JsonText);
   MusicText:=Source;Music.Value:=PWideChar(MusicText);
   FillChar(Scene,SizeOf(Scene),0);Scene.Width:=Image.Width;Scene.Height:=Image.Height;Scene.Rate:=60;Scene.Scale:=1;
   FillChar(Obj,SizeOf(Obj),0);Obj.Width:=Image.Width;Obj.Height:=Image.Height;Obj.Time:=32.3;
   FillChar(Video,SizeOf(Video),0);Video.Scene:=@Scene;Video.Object_:=@Obj;Video.SetImageData:=CaptureHost;
   FirstHash:=PreviewHash;
   Frame('DLL cold frame',False);SecondHash:=CapturedHash;Need(FirstHash=SecondHash,'DLL/preview pixel mismatch '+StyleId(Style));
   // Scrambled offsets also exercise a backwards seek and both clip boundaries for every actual DLL.
   for I:=0 to 6 do begin
     case I of 0:Offset.Value:=1;1:Offset.Value:=-0.01;2:Offset.Value:=-1;3:Offset.Value:=0.25;4:Offset.Value:=0;5:Offset.Value:=0.01;6:Offset.Value:=-0.25;end;
     ModeHash:=PreviewHash;Frame('Offset DLL/preview '+IntToStr(I),False);Need(CapturedHash=ModeHash,'Offset not shared by host and Preview');Inc(OffsetChecks);
     Need(string(Json.Value)=OriginalJSON,'Render changed settings or plan for an offset');
   end;
   Offset.Value:=1;Obj.Time:=0;Frame('Delay before first source frame',True);Inc(OffsetChecks);
   Obj.Time:=0.999;Frame('Delay just before boundary',True);Inc(OffsetChecks);
   Obj.Time:=1;ModeHash:=PreviewHash;Frame('Delay exact start',False);Need(CapturedHash=ModeHash,'Delayed start time');Inc(OffsetChecks);
   Obj.Time:=100;ModeHash:=PreviewHash;Frame('Delay near source end',False);Need(CapturedHash=ModeHash,'Delayed end time');Inc(OffsetChecks);
   Offset.Value:=-1;Obj.Time:=0;ModeHash:=PreviewHash;Frame('Advance at object start',False);Need(CapturedHash=ModeHash,'Advanced start time');Inc(OffsetChecks);
   Obj.Time:=100;ModeHash:=PreviewHash;Frame('Advance after source end',False);Need(CapturedHash=ModeHash,'Advanced end time');Inc(OffsetChecks);
   Obj.Time:=32.3;Offset.Value:=0;Frame('Offset reset',False);Need(CapturedHash=SecondHash,'Offset reset or backwards seek drift');Inc(OffsetChecks);
   if Style=rsMarbleRelay then begin
     Settings.MarbleStage:=msClearAcrylic;
     JsonText:=Settings.ToJSON;Json.Value:=PWideChar(JsonText);ModeHash:=PreviewHash;
     Frame('Marble stage change',False);Need((CapturedHash=ModeHash) and (ModeHash<>SecondHash),'Stage toggle missing from host');
     FirstHash:=ModeHash;
     Settings.MarbleBall:=mbGlass;
     JsonText:=Settings.ToJSON;Json.Value:=PWideChar(JsonText);ModeHash:=PreviewHash;
     Frame('Marble ball change',False);Need((CapturedHash=ModeHash) and (ModeHash<>FirstHash),'Ball toggle missing from host');
     Settings.MarbleBall:=mbSteel;Settings.MarbleStage:=msWoodWorkshop;
     JsonText:=OriginalJSON;Json.Value:=PWideChar(JsonText);ModeHash:=PreviewHash;
     Frame('Marble appearance restored',False);Need((CapturedHash=SecondHash) and (ModeHash=SecondHash),'Appearance toggle return drift');
   end;
   SavedEqualizer:=Settings.EqualizerMode;
   for Mode:=0 to 1 do begin Settings.EqualizerMode:=Mode;JsonText:=Settings.ToJSON;Json.Value:=PWideChar(JsonText);ModeHash:=PreviewHash;
     Frame('Equalizer toggle '+IntToStr(Mode),False);Need(CapturedHash=ModeHash,'Equalizer DLL/preview mismatch');
     Need(Settings.Plan.Key=Ref.Key,'View toggle changed analysis plan');
   end;
   Settings.EqualizerMode:=SavedEqualizer;JsonText:=OriginalJSON;Json.Value:=PWideChar(JsonText);ModeHash:=PreviewHash;
   Frame('Equalizer original restored',False);Need((CapturedHash=SecondHash) and (ModeHash=SecondHash),'Equalizer toggle return drift');
   Obj.Time:=63.1;Frame('DLL other frame',False);Obj.Time:=32.3;Frame('DLL return seek',False);Need(CapturedHash=SecondHash,'DLL seek drift');
   MusicText:=Source+'.different';Music.Value:=PWideChar(MusicText);Frame('Changed file with old plan',True);
   MusicText:='';Music.Value:=PWideChar(MusicText);Frame('Cleared host file',True);
   MusicText:=Source;Music.Value:=PWideChar(MusicText);Frame('Same prepared file reselected',False);Need(CapturedHash=SecondHash,'Re-select prepared file');
   JsonText:='';Json.Value:=PWideChar(JsonText);Frame('Unprepared existing file',True);
   JsonText:=OriginalJSON;Json.Value:=PWideChar(JsonText);Frame('Saved AUP2 restored',False);Need(CapturedHash=SecondHash,'Saved restore');
   Settings.HostMusic:=False;JsonText:=Settings.ToJSON;Json.Value:=PWideChar(JsonText);
   Frame('Legacy JSON same host file',False);Need(CapturedHash=SecondHash,'Legacy JSON restore');
   MusicText:='';Music.Value:=PWideChar(MusicText);Frame('Legacy JSON awaiting host migration',True);Need(string(Json.Value)=JsonText,'Rendering must not mutate legacy JSON');
   MusicText:=Source;Music.Value:=PWideChar(MusicText);Frame('Restored before source overwrite',False);
   OriginalSource:=TFile.ReadAllBytes(Source);Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@SavedStamp),'Source timestamp');
   try
    TFile.AppendAllText(Source,'changed in place',TEncoding.UTF8);Frame('Source overwritten in place',True);
   finally
    TFile.WriteAllBytes(Source,OriginalSource);FileHandle:=CreateFile(PChar(Source),FILE_WRITE_ATTRIBUTES,FILE_SHARE_READ or FILE_SHARE_WRITE,nil,OPEN_EXISTING,0,0);
    Need(FileHandle<>INVALID_HANDLE_VALUE,'Restore source handle');try Need(SetFileTime(FileHandle,nil,nil,@SavedStamp.ftLastWriteTime),'Restore source stamp');finally CloseHandle(FileHandle);end;
   end;
   MusicText:='';Music.Value:=PWideChar(MusicText);Frame('Source revision reset',True);
   MusicText:=Source;Music.Value:=PWideChar(MusicText);Frame('Source revision restored',False);Need(CapturedHash=SecondHash,'Source revision restore');
   Inc(HostChecks);WriteLn('DLL host music/cold/preview/seek PASS: ',ProductForStyle);
  finally Done();end;
  Need(Init(0)=1,'Old host initialization');try Table:=GetTable();FindItems(False);
   MusicText:=Source;Music.Value:=PWideChar(MusicText);JsonText:=OriginalJSON;Json.Value:=PWideChar(JsonText);
   Frame('Old host prepared',False);Need(CapturedHash=SecondHash,'Old host prepared equality');
   MusicText:='';Music.Value:=PWideChar(MusicText);Frame('Old host file cleared',True);
  finally Done();end;
 finally FreeLibrary(Lib);end;
end;

begin
 Audio:=nil;Cold:=nil;Worker:=nil;Renderer:=nil;Image:=nil;PNG:=nil;Checks:=0;HostChecks:=0;MusicChecks:=0;OffsetChecks:=0;StylesChecked:=0;
 try
  Density:=AUDIO_DEFAULT_DENSITY;if ParamCount>3 then Density:=StrToInt(ParamStr(4));
  Root:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Root);Source:=TPath.Combine(Root,'shared-source.identity');TFile.WriteAllText(Source,'Synthetic events only. No sound playback.',TEncoding.UTF8);
  Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stat');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
  Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(960,540);
  for Style:=Low(TRhythmStyle) to High(TRhythmStyle) do begin
   if (ParamCount>=3) and (ParamStr(3)<>'*') and (ParamStr(3)<>StyleId(Style)) then Continue;
   Inc(StylesChecked);
   ConfigureRhythmProduct(ProductForStyle,'Shared integration',Style);
   Audio:=MakeAudio;BaseHits:=Length(Audio.Hits);if Style=rsShooting then SaveShootingFixture;
   Worker:=TRhythmPrepareThread.Create(Source,50,0,Style,False,Audio,Ord(Style)+1,StyleVariant(Style,70,100,Density),Density);Audio:=nil;
   Worker.Start;Worker.WaitFor;
   Need(Worker.Error='','Prepare '+StyleId(Style)+': '+Worker.Error);Ref:=Worker.Plan;Audio:=Worker.TakeAudio;WriteLn(StyleId(Style),' v',Ref.Version,': ',Worker.Summary);FreeAndNil(Worker);
   Settings:=TRhythmSettings.Defaults;Settings.Style:=Style;Settings.Music:=Source;Settings.BossFrequency:=100;Settings.FireworksRichness:=70;Settings.Plan:=Ref;Settings.GameThreshold:=Density;
   if (Density>AUDIO_DEFAULT_DENSITY) and not StyleHas(Style,sfThreshold) then Need(Length(Audio.Hits)<BaseHits,'Audio density did not reduce adopted hits');
   if (Density<AUDIO_DEFAULT_DENSITY) and not StyleHas(Style,sfThreshold) then Need(Length(Audio.Hits)>BaseHits,'Audio density did not add spaced hits');
   Need(TRhythmSettings.TryJSON(Settings.ToJSON,Restored),'Settings parse');Need((Restored.Style=Style) and (Restored.Plan.Key=Ref.Key) and (Restored.BossFrequency=100),'Settings style/frequency/plan');
   Restored.BindHostMusic(UpperCase(Source));Need(Restored.Plan.Key=Ref.Key,'Same path preserves plan');
   Restored.BindHostMusic(Source+'.new');Need((Restored.Plan.Key='') and Restored.HostMusic,'Changed host file invalidates plan');
   Actual:=Restored.ToJSON;Need(TRhythmSettings.TryJSON(Actual,Restored) and Restored.HostMusic,'Host authority JSON roundtrip');
   Cold:=LoadStyleAudio(Style,Ref,Source,0);Need(Cold<>nil,'PCM-free restore fixture');
   Need(Length(Cold.PCM)=0,'PCM-free restore');Renderer:=TRhythmRenderer.Create;Renderer.ConfigureStyle(Style,Ref,100);
   // 初見殺しはEQを明示ONにして、件数だけの冷復元で二音目以降が止まる退行も検出する。
   for Meter:=0 to Ord(Style=rsTrapAction) do begin
    if Meter=0 then Renderer.ConfigureStyle(Style,Ref,100) else Renderer.ConfigureStyle(Style,Ref,100,1);
    for Backend:=0 to 1 do begin
    Renderer.UseD2D:=Backend=1;
    for J:=0 to 7 do begin
     T:=0.5+((J*19) mod 91);Renderer.Render(Image,Audio,T,0);Expected:=ImageHash;Renderer.Render(Image,Cold,99-T,0);Renderer.Render(Image,Cold,T,0);Actual:=ImageHash;Need(Actual=Expected,'Warm/cold/seek '+StyleId(Style)+' backend '+IntToStr(Backend));Inc(Checks);
    end;
    for J:=-2 to 2 do begin Shift:=J*0.5;
     Renderer.Render(Image,Cold,32.3-Shift,0);Expected:=ImageHash;
     Renderer.Render(Image,Cold,32.3,0,'',1,0,0,Shift);Need(ImageHash=Expected,'Offset renderer source time '+StyleId(Style));Inc(OffsetChecks);
    end;
     if Backend=1 then Need(Renderer.LastUsedD2D,'D2D backend unavailable '+StyleId(Style));
    end;
   end;
   VerifyHost;
   Renderer.Render(Image,Cold,32.3,0);PNG:=TPngImage.Create;PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Root,StyleId(Style)+'.png'));FreeAndNil(PNG);
   FreeAndNil(Renderer);FreeAndNil(Cold);FreeAndNil(Audio);
  end;
  TFile.WriteAllText(TPath.Combine(Root,'result.json'),Format('{"styles":%d,"density":%d,"warmColdSeekChecks":%d,"hostDLLChecks":%d,"hostMusicChecks":%d,"offsetChecks":%d,"backends":["GDI","Direct2D"],"audioPlayback":false}',[StylesChecked,Density,Checks,HostChecks,MusicChecks,OffsetChecks]),TEncoding.UTF8);WriteLn('Shared preparation/factory/settings/cold/seek PASS: ',Checks);
 except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
 PNG.Free;Renderer.Free;Worker.Free;Cold.Free;Audio.Free;Image.Free;
end.
