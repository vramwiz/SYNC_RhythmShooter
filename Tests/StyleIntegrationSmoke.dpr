program StyleIntegrationSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,AviUtl2FilterTypes,RhythmAudio,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmSettings,
  RhythmPrepare,RhythmScene,RhythmBallPlan,RhythmFireworksPlan,RhythmRunnerPlan,RhythmBreakoutPlan,
  RhythmRacePlan,RhythmBombPlan,RhythmFightingPlan,RhythmMiningPlan,RhythmTrainPlan,RhythmNavalPlan;
type TInitPlugin=function(Version:DWORD):Byte;cdecl;
 TDonePlugin=procedure;cdecl;
 TGetPlugin=function:PFILTER_PLUGIN_TABLE;cdecl;
var Captured:TBytes;CapturedWidth,CapturedHeight:Integer;
var Root,Source,Revision,Expected,Actual:string;Stamp:TWin32FileAttributeData;Style:TRhythmStyle;
  Audio,Cold:TRhythmAudio;Worker:TRhythmPrepareThread;Ref:TRhythmPlanRef;Renderer:TRhythmRenderer;
  Image:TBitmap;Settings,Restored:TRhythmSettings;Backend,J,Checks,HostChecks:Integer;T:Double;PNG:TPngImage;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
function MakeAudio:TRhythmAudio;
var I:Integer;Time,Gap:Double;
begin
 Result:=TRhythmAudio.Create;Result.Source:=Source;Result.Key:=THashSHA2.GetHashString('shared-preparation-native-v1');Result.Sensitivity:=50;Result.SourceRevision:=Revision;Result.Duration:=100;
 SetLength(Result.Envelope,10000);for I:=0 to 9499 do if ((I>2200) and (I<4300)) or ((I>6500) and (I<8500)) then Result.Envelope[I]:=0.85 else Result.Envelope[I]:=0.16;
 SetLength(Result.Hits,3000);I:=0;Time:=0.5;while Time<94 do begin Result.Hits[I].Time:=Time;Result.Hits[I].Strength:=0.28+(I mod 7)*0.12;Inc(I);Gap:=0.32;if ((Time>22) and (Time<43)) or ((Time>65) and (Time<85)) then Gap:=0.10;Time:=Time+Gap;end;SetLength(Result.Hits,I);Result.UpdateSoundBounds;
end;
function ColdRead:TRhythmAudio;
begin
 case Style of
 rsBall:Result:=TRhythmBallPlan.LoadAudioMetadata(Ref,Source,0);
 rsFireworks:Result:=TFireworksPlan.LoadAudioMetadata(Ref,Source,0);
 rsRunner:Result:=TRunnerPlan.LoadAudioMetadata(Ref,Source,0);
 rsBreakout:Result:=TBreakoutPlan.LoadAudioMetadata(Ref,Source,0);
 rsRace:Result:=TRacePlan.LoadAudioMetadata(Ref,Source,0);
 rsBombAction:Result:=TBombActionPlan.LoadAudioMetadata(Ref,Source,0);
 rsFighting:Result:=TFightingPlan.LoadAudioMetadata(Ref,Source,0);
 rsMining:Result:=TMiningPlan.LoadAudioMetadata(Ref,Source,0);
 rsTrain:Result:=TTrainPlan.LoadAudioMetadata(Ref,Source,0);
 rsNaval:Result:=TNavalPlan.LoadAudioMetadata(Ref,Source,0);
 else raise Exception.Create('Unknown cold style');end;
end;
function ImageHash:string;
var S:TMemoryStream;B:TBytes;H:THashSHA2;
begin S:=TMemoryStream.Create;try Image.SaveToStream(S);SetLength(B,S.Size);S.Position:=0;S.ReadBuffer(B[0],Length(B));H:=THashSHA2.Create;H.Update(B);Result:=H.HashAsString;finally S.Free;end;end;
function ProductForStyle:string;
begin case Style of rsBall:Result:='SYNC_RhythmBall';rsFireworks:Result:='SYNC_RhythmFireworks';rsRunner:Result:='SYNC_RhythmRunner';rsBreakout:Result:='SYNC_RhythmBreakout';rsRace:Result:='SYNC_RhythmRace';rsBombAction:Result:='SYNC_RhythmBombAction';rsFighting:Result:='SYNC_RhythmFighting';rsMining:Result:='SYNC_RhythmMining';rsTrain:Result:='SYNC_RhythmTrain';rsNaval:Result:='SYNC_RhythmNaval';else Result:='SYNC_RhythmShooter';end;end;
procedure CaptureHost(Buffer:PPIXEL_RGBA;W,H:Integer);cdecl;
begin CapturedWidth:=W;CapturedHeight:=H;SetLength(Captured,W*H*4);Move(Buffer^,Captured[0],Length(Captured));end;
procedure VerifyHost;
var Lib:HMODULE;Init:TInitPlugin;Done:TDonePlugin;GetTable:TGetPlugin;Table:PFILTER_PLUGIN_TABLE;Json:PFILTER_ITEM_STRING;
 Item:Pointer;I,X,Y,K:Integer;Kind,JsonText,Path,Config:string;Scene:TSCENE_INFO;Obj:TOBJECT_INFO;Video:TFILTER_PROC_VIDEO;H:THashSHA2;FirstHash,SecondHash:string;Row:PByte;Expected:TBytes;
begin
 if (ParamCount=0) or (Style=rsShooting) then Exit;
 Config:='Release';if ParamCount>1 then Config:=ParamStr(2);Need((Config='Debug') or (Config='Release'),'DLL test configuration');
 Path:=TPath.Combine(ParamStr(1),ProductForStyle+'\'+Config+'\'+ProductForStyle+'.dll');Lib:=LoadLibraryEx(PChar(Path),0,LOAD_WITH_ALTERED_SEARCH_PATH);if Lib=0 then RaiseLastOSError;
 try
  @Init:=GetProcAddress(Lib,'InitializePlugin');@Done:=GetProcAddress(Lib,'UninitializePlugin');@GetTable:=GetProcAddress(Lib,'GetFilterPluginTable');Need(Assigned(Init) and Assigned(Done) and Assigned(GetTable),'DLL exports');Need(Init(0)=1,'DLL initialization');
  try
   Table:=GetTable();Need((Table<>nil) and Assigned(Table.Func_Proc_Video),'DLL filter callback');Json:=nil;
   for I:=0 to 12 do begin Item:=PPointer(NativeUInt(Table.Items)+NativeUInt(I*SizeOf(Pointer)))^;if Item=nil then Break;Kind:=string(PWideChar(PPointer(Item)^));if Kind='string' then Json:=PFILTER_ITEM_STRING(Item);end;
   Need(Json<>nil,'DLL JSON item');JsonText:=Settings.ToJSON;Json.Value:=PWideChar(JsonText);
   FillChar(Scene,SizeOf(Scene),0);Scene.Width:=Image.Width;Scene.Height:=Image.Height;Scene.Rate:=60;Scene.Scale:=1;FillChar(Obj,SizeOf(Obj),0);Obj.Width:=Image.Width;Obj.Height:=Image.Height;Obj.Time:=32.3;
   FillChar(Video,SizeOf(Video),0);Video.Scene:=@Scene;Video.Object_:=@Obj;Video.SetImageData:=CaptureHost;
   Renderer.UseD2D:=True;Renderer.Render(Image,Cold,Obj.Time,0);SetLength(Expected,Image.Width*Image.Height*4);K:=0;
   for Y:=0 to Image.Height-1 do begin Row:=Image.ScanLine[Y];for X:=0 to Image.Width-1 do begin Expected[K]:=Row[2];Expected[K+1]:=Row[1];Expected[K+2]:=Row[0];Expected[K+3]:=255;Inc(K,4);Inc(Row,4);end;end;
   H:=THashSHA2.Create;H.Update(Expected);FirstHash:=H.HashAsString;
   Need(Table.Func_Proc_Video(@Video)=1,'DLL cold frame');Need((CapturedWidth=Image.Width) and (CapturedHeight=Image.Height),'DLL dimensions');H:=THashSHA2.Create;H.Update(Captured);SecondHash:=H.HashAsString;Need(FirstHash=SecondHash,'DLL/preview pixel mismatch '+StyleId(Style));
   Obj.Time:=63.1;Need(Table.Func_Proc_Video(@Video)=1,'DLL other frame');Obj.Time:=32.3;Need(Table.Func_Proc_Video(@Video)=1,'DLL return seek');H:=THashSHA2.Create;H.Update(Captured);Need(H.HashAsString=SecondHash,'DLL seek drift');Inc(HostChecks);WriteLn('DLL cold/preview/seek PASS: ',ProductForStyle);
  finally Done();end;
 finally FreeLibrary(Lib);end;
end;
begin
 Audio:=nil;Cold:=nil;Worker:=nil;Renderer:=nil;Image:=nil;PNG:=nil;Checks:=0;HostChecks:=0;
 try
  Root:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Root);Source:=TPath.Combine(Root,'shared-source.identity');TFile.WriteAllText(Source,'Synthetic events only. No sound playback.',TEncoding.UTF8);
  Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stat');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
  Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(960,540);
  for Style:=Low(TRhythmStyle) to High(TRhythmStyle) do begin
   ConfigureRhythmProduct(ProductForStyle,'Shared integration',Style);
   Worker:=TRhythmPrepareThread.Create(Source,50,0,Style,False,MakeAudio,Ord(Style)+1,StyleVariant(Style,70,100));Worker.Start;Worker.WaitFor;
   Need(Worker.Error='','Prepare '+StyleId(Style)+': '+Worker.Error);Ref:=Worker.Plan;Audio:=Worker.TakeAudio;WriteLn(StyleId(Style),' v',Ref.Version,': ',Worker.Summary);FreeAndNil(Worker);
   Settings:=TRhythmSettings.Defaults;Settings.Style:=Style;Settings.Music:=Source;Settings.BossFrequency:=100;Settings.FireworksRichness:=70;Settings.Plan:=Ref;
   Need(TRhythmSettings.TryJSON(Settings.ToJSON,Restored),'Settings parse');Need((Restored.Style=Style) and (Restored.Plan.Key=Ref.Key) and (Restored.BossFrequency=100),'Settings style/frequency/plan');
   if Style=rsShooting then Cold:=MakeAudio else Cold:=ColdRead;
   Need(Length(Cold.PCM)=0,'PCM-free restore');Renderer:=TRhythmRenderer.Create;Renderer.ConfigureStyle(Style,Ref,100);
   for Backend:=0 to 1 do begin
    Renderer.UseD2D:=Backend=1;
    for J:=0 to 7 do begin
     T:=0.5+((J*19) mod 91);Renderer.Render(Image,Audio,T,0);Expected:=ImageHash;Renderer.Render(Image,Cold,99-T,0);Renderer.Render(Image,Cold,T,0);Actual:=ImageHash;Need(Actual=Expected,'Warm/cold/seek '+StyleId(Style)+' backend '+IntToStr(Backend));Inc(Checks);
    end;
    if Backend=1 then Need(Renderer.LastUsedD2D,'D2D backend unavailable '+StyleId(Style));
   end;
   VerifyHost;
   Renderer.Render(Image,Cold,32.3,0);PNG:=TPngImage.Create;PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Root,StyleId(Style)+'.png'));FreeAndNil(PNG);
   FreeAndNil(Renderer);FreeAndNil(Cold);FreeAndNil(Audio);
  end;
  TFile.WriteAllText(TPath.Combine(Root,'result.json'),Format('{"styles":11,"warmColdSeekChecks":%d,"hostDLLChecks":%d,"backends":["GDI","Direct2D"],"audioPlayback":false}',[Checks,HostChecks]),TEncoding.UTF8);WriteLn('Shared preparation/factory/settings/cold/seek PASS: ',Checks);
 except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
 PNG.Free;Renderer.Free;Worker.Free;Cold.Free;Audio.Free;Image.Free;
end.
