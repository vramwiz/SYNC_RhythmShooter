uses Winapi.Windows,System.SysUtils,System.Classes,System.Math,System.Hash,System.IOUtils,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmSettings,RhythmStyles,RhythmPlanRef,RhythmProduct,
  RhythmPrepare,RhythmScene,RhythmGamePlan,RhythmOverlay,RhythmPreparedData,
  RhythmLayerData in 'Support\RhythmLayerData.pas';
const Durations:array[0..4] of Double=(0.1,1,12,100,100);
var Worker:TRhythmPrepareThread;Audio,Cold:TRhythmAudio;R:TRhythmRenderer;Blend:TRhythmOverlay;
  Image,Movie:TBitmap;PNG:TPngImage;Ref,OldMovie:TRhythmPlanRef;Saved,Parsed:TRhythmSettings;
  Stamp:TWin32FileAttributeData;Folder,Source,Revision,Hash,Plain,WithEQ:string;
  CaseIndex,B,E,I,X,Y,C,A,Checks,Frames,Low,Partial:Integer;T:Double;Row:PByte;
procedure Need(OK:Boolean;const Why:string);
begin if not OK then raise Exception.Create(Why);Inc(Checks);end;
function MakeAudio(Index:Integer):TRhythmAudio;
var I:Integer;Time,Gap:Double;
begin
  Result:=TRhythmAudio.Create;Result.Source:=Source;Result.SourceRevision:=Revision;
  Result.Key:=THashSHA2.GetHashString('mv-overlay-'+IntToStr(Index));Result.Sensitivity:=50;Result.Duration:=Durations[Index];
  SetLength(Result.Envelope,Max(1,Ceil(Result.Duration*100)));for I:=0 to High(Result.Envelope) do Result.Envelope[I]:=0.25+(I mod 8)/16;
  if Index<>4 then begin SetLength(Result.Hits,2000);I:=0;Time:=Min(0.3,Result.Duration*0.3);
    while Time<Result.Duration-0.02 do begin Result.Hits[I].Time:=Time;Result.Hits[I].Strength:=0.30+(I mod 6)*0.13;Inc(I);
      Gap:=0.34;if (Time>Result.Duration*0.25) and (Time<Result.Duration*0.65) then Gap:=0.09;Time:=Time+Gap;
    end;SetLength(Result.Hits,I);
  end;Result.UpdateSoundBounds;
end;
function ImageHash:string;
var H:THashSHA2;Y:Integer;
begin H:=THashSHA2.Create;for Y:=0 to Image.Height-1 do H.Update(Image.ScanLine[Y]^,Image.Width*4);Result:=H.HashAsString;end;
procedure Snapshot(const Name:string;Alpha:Boolean);
var X,Y,C,A:Integer;Row:PByte;Color:array[0..2] of Integer;
begin
  if Alpha then begin PNG:=TPngImage.CreateBlank(COLOR_RGBALPHA,8,Image.Width,Image.Height);
    for Y:=0 to Image.Height-1 do begin Row:=Image.ScanLine[Y];
      for X:=0 to Image.Width-1 do begin A:=Row[3];for C:=0 to 2 do if A=0 then Color[C]:=0 else Color[C]:=Min(255,(Integer(Row[C])*255+A div 2) div A);
        PNG.Pixels[X,Y]:=RGB(Color[2],Color[1],Color[0]);PNG.AlphaScanLine[Y]^[X]:=A;Inc(Row,4);
      end;
    end;
  end else begin PNG:=TPngImage.Create;PNG.Assign(Image);end;
  try PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));finally FreeAndNil(PNG);end;Inc(Frames);
end;
procedure FakeMV;
var X,Y:Integer;Row:PByte;
begin Movie.SetSize(Image.Width,Image.Height);for Y:=0 to Movie.Height-1 do begin Row:=Movie.ScanLine[Y];
  for X:=0 to Movie.Width-1 do begin Row[0]:=40+(X div 40 mod 3)*65;Row[1]:=40+(Y div 30 mod 3)*65;
    Row[2]:=50+((X+Y+Round(T*50)) div 50 mod 3)*65;Row[3]:=255;Inc(Row,4);end;
end;end;
procedure CheckLegacyVersions;
var Version,B,Mode,J,X,Y,Low:Integer;Root:TJSONObject;LegacyRef:TRhythmPlanRef;Meta:TRhythmAudio;Renderer:TRhythmRenderer;Hash:string;Row:PByte;
begin
  for Version:=1 to 2 do begin
    Root:=TJSONObject.ParseJSONValue(TFile.ReadAllText('Tests/Fixtures/RhythmGame-v'+IntToStr(Version)+'.json',TEncoding.UTF8)) as TJSONObject;
    Meta:=nil;Renderer:=nil;
    try
      LegacyRef:=NewPlanRef(Root.GetValue<string>('source'),50,0,rsRhythmGame,0);if Version=2 then LegacyRef.Variant:=21;
      LegacyRef.Version:=Version;LegacyRef.Key:=Root.GetValue<string>('key');LegacyRef.SourceRevision:=Revision;WritePreparedData(Root,LegacyRef);
      Meta:=TGamePlan.LoadAudioMetadata(LegacyRef,Source,0);Need(Length(Meta.PCM)=0,'Legacy restore requires PCM');
      Saved:=TRhythmSettings.Defaults;Saved.Style:=rsRhythmGame;Saved.Plan:=LegacyRef;Saved.Music:=Source;
      Need(TRhythmSettings.TryJSON(Saved.ToJSON,Parsed) and (Parsed.Plan.Key=LegacyRef.Key),'Legacy version settings restore');
      Renderer:=TRhythmRenderer.Create;
      for B:=0 to 1 do for Mode:=0 to 1 do begin
        Renderer.UseD2D:=B=1;Renderer.ConfigureStyle(rsRhythmGame,LegacyRef,100,Mode);
        for J:=0 to 2 do begin
          T:=14.4+J*0.08;Renderer.Render(Image,Meta,T,0);Hash:=ImageHash;
          Renderer.Render(Image,Meta,2.0,0);Renderer.Render(Image,Meta,T,0);Need(ImageHash=Hash,'Legacy alpha seek drift');
          Need(Renderer.OutputHasAlpha,'Legacy output not transparent');Low:=0;
          for Y:=0 to Image.Height-1 do begin Row:=Image.ScanLine[Y];for X:=0 to Image.Width-1 do begin
            if Row[3]<250 then Inc(Low);Need((Row[0]<=Row[3]) and (Row[1]<=Row[3]) and (Row[2]<=Row[3]),'Legacy alpha not premultiplied');Inc(Row,4);
          end;end;
          Need(Low>Image.Width*Image.Height div 2,'Legacy overlay hides MV');
          if J=1 then Snapshot(Format('legacy%d-backend%d-eq%d-alpha',[Version,B,Mode]),True);
        end;
      end;
    finally Renderer.Free;Meta.Free;Root.Free;end;
  end;
end;
procedure Fill(Bitmap:TBitmap;Color:TColor);
begin Bitmap.Canvas.Brush.Color:=Color;Bitmap.Canvas.FillRect(Rect(0,0,Bitmap.Width,Bitmap.Height));end;
function LegacyJSON(Front,Middle:Boolean;const MiddleRef:TRhythmPlanRef;MiddleStyle:TRhythmStyle):string;
var Root,Layers,Old:TJSONObject;S:TRhythmSettings;
begin Root:=TJSONObject.ParseJSONValue(Saved.ToJSON) as TJSONObject;Layers:=TJSONObject.Create;
  try Root.RemovePair('presentationVersion').Free;Root.AddPair('layers',Layers);Layers.AddPair('version',TJSONNumber.Create(2));
    Layers.AddPair('foreground',TJSONBool.Create(Front));Layers.AddPair('movie',TJSONBool.Create(Middle));Layers.AddPair('style',StyleId(MiddleStyle));
    S:=Saved;S.Style:=MiddleStyle;S.Plan:=MiddleRef;Old:=TJSONObject.ParseJSONValue(S.ToJSON) as TJSONObject;
    try if Old.GetValue('plan')<>nil then Layers.AddPair('plan',TJSONObject.ParseJSONValue(Old.GetValue('plan').ToJSON));finally Old.Free;end;
    Result:=Root.ToJSON;
  finally Root.Free;end;
end;
begin Worker:=nil;Audio:=nil;Cold:=nil;R:=nil;Blend:=nil;Image:=nil;Movie:=nil;PNG:=nil;Checks:=0;Frames:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','MV overlay native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Movie:=TBitmap.Create;Movie.PixelFormat:=pf32bit;Image.SetSize(80,80);
    Blend:=TRhythmOverlay.Create;Blend.Resize(80,80);Fill(Blend.Black,clBlack);Fill(Blend.White,clWhite);
    Blend.Black.Canvas.Brush.Color:=RGB(100,0,0);Blend.Black.Canvas.FillRect(Rect(0,0,20,20));
    Blend.White.Canvas.Brush.Color:=RGB(227,127,127);Blend.White.Canvas.FillRect(Rect(0,0,20,20));
    Blend.White.Canvas.Brush.Color:=clBlack;Blend.White.Canvas.FillRect(Rect(30,30,50,50));Blend.Resolve(Image,1,0,0);
    Row:=Image.ScanLine[5];Need((Row[5*4+3]=128) and (Row[5*4+2]=100),'Premultiplied translucent fixture');
    Row:=Image.ScanLine[40];Need((Row[40*4+3]=255) and (Row[40*4]=0),'Opaque black mark was keyed out');
    Row:=Image.ScanLine[70];Need(PCardinal(Row+70*4)^=0,'Empty background is not transparent');
    Movie.SetSize(80,80);Fill(Movie,clBlue);OverlayOver(Movie,Image);Need(ColorToRGB(Movie.Canvas.Pixels[40,40])=0,'Black mark did not cover MV');
    Need(ColorToRGB(Movie.Canvas.Pixels[70,70])=ColorToRGB(clBlue),'Transparent pixel changed MV');
    Need(ColorToRGB(Movie.Canvas.Pixels[5,5])=TColor(RGB(100,0,127)),'Wrong alpha multiplication');
    Blend.Resolve(Image,0.5,0,0);Row:=Image.ScanLine[0];Need(PCardinal(Row)^=0,'Zoom adds opaque margins');
    Blend.Resolve(Image,1,1E100,0);Row:=Image.ScanLine[40];Need(PCardinal(Row+40*4)^=0,'Offscreen transform not transparent');FreeAndNil(Blend);
    Source:=TPath.Combine(Folder,'mv-source.identity');TFile.WriteAllText(Source,'Synthetic music metadata; no audio playback.',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stat');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    Image.SetSize(320,180);
    for CaseIndex:=0 to High(Durations) do begin
      Worker:=TRhythmPrepareThread.Create(Source,50,0,rsRhythmGame,False,MakeAudio(CaseIndex),CaseIndex+1,121);Worker.Start;Worker.WaitFor;
      Need(Worker.Error='','Single-plan prepare '+Worker.Error);Ref:=Worker.Plan;Audio:=Worker.TakeAudio;FreeAndNil(Worker);
      Cold:=TGamePlan.LoadAudioMetadata(Ref,Source,0);Need(Length(Cold.PCM)=0,'Restore requires PCM');
      Saved:=TRhythmSettings.Defaults;Saved.Music:=Source;Saved.Style:=rsRhythmGame;Saved.Plan:=Ref;Saved.BossFrequency:=100;Saved.EqualizerMode:=0;
      Need(TRhythmSettings.TryJSON(Saved.ToJSON,Parsed) and (Parsed.Style=rsRhythmGame) and (Parsed.Plan.Key=Ref.Key),'Single style JSON restore');
      Need(not Saved.ToJSON.Contains('"layers"'),'New settings still write layering controls');
      if CaseIndex=3 then begin
        OldMovie:=NewPlanRef(Audio.Key,50,0,rsShooting,StyleVariant(rsShooting,70,100));OldMovie.SourceRevision:=Revision;OldMovie.Digest:=SaveLayerShootingAudio(Audio);
        Need(TRhythmSettings.TryJSON(LegacyJSON(True,True,OldMovie,rsShooting),Parsed) and (Parsed.Plan.Key=Ref.Key) and (Parsed.Style=rsRhythmGame),'Old front ON migration');
        Need(TRhythmSettings.TryJSON(LegacyJSON(True,True,Default(TRhythmPlanRef),rsShooting),Parsed) and (Parsed.Plan.Key=Ref.Key),'Missing obsolete movie invalidated rhythm');
        Need(TRhythmSettings.TryJSON(LegacyJSON(False,True,OldMovie,rsShooting),Parsed) and (Parsed.Style=rsShooting) and (Parsed.Plan.Key=OldMovie.Key),'Old movie-only migration');
        Need(TRhythmSettings.TryJSON(LegacyJSON(False,False,OldMovie,rsShooting),Parsed) and (Parsed.Style=rsRhythmGame),'Old all-off migration');
        Saved.EqualizerMode:=-1;Need(TRhythmSettings.TryJSON(LegacyJSON(False,True,OldMovie,rsShooting),Parsed) and (Parsed.EqualizerMode=1),'Movie migration changed automatic EQ');Saved.EqualizerMode:=0;
        OldMovie.SourceKey:=StringOfChar('b',64);Need(TRhythmSettings.TryJSON(LegacyJSON(False,True,OldMovie,rsShooting),Parsed) and (Parsed.Plan.Key=''),'Wrong source movie accepted');
        Parsed:=Saved;Parsed.BindHostMusic(Source+'.changed');Need(Parsed.Plan.Key='','Changed music kept stale plan');
      end;
      R:=TRhythmRenderer.Create;
      for B:=0 to 1 do begin R.UseD2D:=B=1;
        for E:=0 to 1 do begin R.ConfigureStyle(rsRhythmGame,Ref,100,E);
          for I:=0 to 4 do begin
            case I of 0:T:=0;1:T:=Audio.Duration*0.10;2:T:=Audio.Duration*0.38;3:T:=Audio.Duration*0.85;else T:=Audio.Duration-0.001;end;
            R.Render(Image,Audio,T,0);Hash:=ImageHash;Need(R.OutputHasAlpha,'Game output is opaque');Need(R.LastUsedD2D=(B=1),'Wrong backend');
            R.Render(Image,Cold,Audio.Duration*0.7,0);R.Render(Image,Cold,T,0);Need(ImageHash=Hash,'Warm/cold/seek alpha drift');
            Low:=0;Partial:=0;for Y:=0 to Image.Height-1 do begin Row:=Image.ScanLine[Y];for X:=0 to Image.Width-1 do begin
              A:=Row[3];if A<250 then Inc(Low);if (A>0) and (A<255) then Inc(Partial);
              for C:=0 to 2 do Need(Row[C]<=A,'Non-premultiplied output');Inc(Row,4);
            end;end;
            Need(Low>Image.Width*Image.Height div 2,'Overlay hides most MV');Need(Partial>0,'No translucent effects');
            if (CaseIndex in [2,3]) and (I=2) then begin
              Snapshot(Format('case%d-backend%d-eq%d-alpha',[CaseIndex,B,E]),True);FakeMV;OverlayOver(Movie,Image);Image.Assign(Movie);
              Snapshot(Format('case%d-backend%d-eq%d-over-mv',[CaseIndex,B,E]),False);
            end;
          end;
          T:=Audio.Duration*0.38;R.Render(Image,Cold,T,0, '',0.5,17,-9);Hash:=ImageHash;
          R.Render(Image,Cold,0.0,0);R.Render(Image,Cold,T,0,'',0.5,17,-9);Need(ImageHash=Hash,'Transformed seek drift');
          Row:=Image.ScanLine[0];Need(Row[3]=0,'Transformed corner is not transparent');
          R.Render(Image,Cold,T,0);if E=0 then Plain:=ImageHash else WithEQ:=ImageHash;
        end;
        if CaseIndex<>4 then Need(Plain<>WithEQ,'Equalizer toggle has no effect');
      end;
      FreeAndNil(R);FreeAndNil(Cold);FreeAndNil(Audio);
    end;
    CheckLegacyVersions;
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"cases":5,"legacyVersions":2,"frames":%d,"premultiplied":true,"legacyMigration":true,"pcmFree":true,"gui":false}',[Checks,Frames]),TEncoding.UTF8);
    WriteLn('MV overlay PASS checks=',Checks,' cases=5 frames=',Frames);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  PNG.Free;R.Free;Worker.Free;Audio.Free;Cold.Free;Blend.Free;Image.Free;Movie.Free;
end.
