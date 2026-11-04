program OrbitPresentationSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Hash,System.IOUtils,System.Classes,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmPlanRef,RhythmStyles,RhythmSettings,RhythmProduct,
  RhythmScene,RhythmOrbitPlan,RhythmOrbitTypes,RhythmOrbitMarks,RhythmEqualizer,RhythmRenderSurface,RhythmImageBank;
var A,Meta:TRhythmAudio;Plan:TOrbitPlan;Ref:TRhythmPlanRef;Render:TRhythmRenderer;Surface:TAnimationRenderSurface;
  Image:TBitmap;PNG:TPngImage;Folder,Source,Revision,First,OnHash,OffHash:string;Stamp:TWin32FileAttributeData;
  Saved,Loaded:TRhythmSettings;Style:TRhythmStyle;B,I,J,K,Mode,Checks,Frames,Count:Integer;
  Tap:TOrbitTap;Activity:TEqualizerActivity;Times:array[0..4] of Double=(0.03,0.4,2.4,6,7.8);
  Samples:array[0..2,0..24] of TColor;
procedure Need(V:Boolean;const S:string);
begin if not V then raise Exception.Create(S);Inc(Checks);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;
  try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;
  finally M.Free;end;
end;
procedure Snapshot(const Name:string);
begin PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));finally FreeAndNil(PNG);end;Inc(Frames);end;
begin A:=nil;Meta:=nil;Plan:=nil;Render:=nil;Surface:=nil;Image:=nil;PNG:=nil;Checks:=0;Frames:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','Presentation native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    for Style:=Low(TRhythmStyle) to High(TRhythmStyle) do begin
      Saved:=TRhythmSettings.Defaults;Saved.Style:=Style;
      Need(Saved.EqualizerMode=-1,'New default mode');Need(EqualizerEnabled(-1,Style,3)=(Style=rsRhythmGame),'Migration style default');
      for Mode:=-1 to 1 do begin Saved.EqualizerMode:=Mode;Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded),'Mode JSON parse');
        Need((Loaded.EqualizerMode=Mode) and (Loaded.Style=Style),'Mode JSON roundtrip');
      end;
    end;
    Need(not EqualizerEnabled(-1,rsRhythmGame,1),'Flat v1 migration gained meter');Need(EqualizerEnabled(1,rsRhythmGame,1),'Legacy explicit on');
    Need(not TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","equalizer":"false"}',Loaded),'Bad boolean accepted');
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(360,120);Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create([],0));
    for B:=0 to 1 do begin Surface.UseD2D:=B=1;
      for J:=0 to 1 do begin Surface.BeginFrame(Image);
        if J=0 then Surface.FillRect(0,0,360,120,RGB(240,10,10)) else Surface.FillRect(0,0,360,120,RGB(10,10,240));
        for K:=0 to 2 do begin Tap:=Default(TOrbitTap);Tap.Source:=K;Tap.Chain:=1;Tap.Strength:=0.4;
          if K=1 then Tap.Chain:=3;if K=2 then Tap.Strength:=0.9;
          Need(Ord(OrbitMarkKind(Tap))=K,'Symbol meaning');
          DrawOrbitMark(Surface,70+K*110,60,20,0,0.4,0.7,OrbitMarkKind(Tap),OrbitMarkColor(Tap),True);
        end;
        Need(Surface.EndFrame,'Shape end frame');
        for K:=0 to 2 do for I:=0 to 24 do begin
          if J=0 then Samples[K,I]:=Image.Canvas.Pixels[66+K*110+(I mod 5)*2,56+(I div 5)*2]
          else Need(Samples[K,I]=Image.Canvas.Pixels[66+K*110+(I mod 5)*2,56+(I div 5)*2],'Marker core is transparent');
        end;
        Snapshot(Format('symbols-backend%d-background%d',[B,J]));
      end;
      for J:=0 to 2 do begin Surface.BeginFrame(Image);Surface.FillRect(0,0,360,120,clBlack);
        DrawOrbitGood(Surface,180,90,J*0.19,360,120,RGB(80,230,255));Need(Surface.EndFrame,'GOOD end frame');Count:=0;
        for I:=0 to 359 do for K:=0 to 119 do if ColorToRGB(Image.Canvas.Pixels[I,K])<>0 then Inc(Count);
        if J=2 then Need(Count=0,'GOOD does not expire') else Need(Count>40,'GOOD missing');Snapshot(Format('good-backend%d-stage%d',[B,J]));
      end;
      if B=1 then Need(Surface.LastUsedD2D,'D2D unavailable');
    end;
    FreeAndNil(Surface);Image.SetSize(640,360);
    Source:=TPath.Combine(Folder,'presentation.identity');TFile.WriteAllText(Source,'Synthetic presentation identity',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    A:=TRhythmAudio.Create;A.Source:=Source;A.SourceRevision:=Revision;A.Key:=THashSHA2.GetHashString('presentation-v3');A.Sensitivity:=50;A.Duration:=8;A.SoundEnd:=8;
    SetLength(A.Hits,200);for I:=0 to 199 do begin A.Hits[I].Time:=I*0.04;A.Hits[I].Strength:=0.3+(I mod 8)*0.1;end;
    Plan:=TOrbitPlan.Build(A,20);Ref:=NewPlanRef(A.Key,50,0,rsRhythmGame,121);Ref.SourceRevision:=Revision;Plan.Save(Ref,A);Meta:=TOrbitPlan.LoadAudioMetadata(Ref,Source,0);
    Render:=TRhythmRenderer.Create;
    for B:=0 to 1 do begin Render.UseD2D:=B=1;
      for J:=0 to 4 do begin
        for Mode:=0 to 1 do begin Render.ConfigureStyle(rsRhythmGame,Ref,100,Mode);Render.Render(Image,A,Times[J],0);First:=ImageHash;
          Render.Render(Image,Meta,8-Times[J],0);Render.Render(Image,Meta,Times[J],0);Need(ImageHash=First,'Overlay warm/cold/seek drift');
          if Mode=0 then OffHash:=First else OnHash:=First;
          if J=2 then Snapshot(Format('game-backend%d-eq%d',[B,Mode]));
          Saved:=TRhythmSettings.Defaults;Saved.Style:=rsRhythmGame;Saved.Plan:=Ref;Saved.GameThreshold:=20;Saved.EqualizerMode:=Mode;
          Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded) and (Loaded.Plan.Key=Ref.Key) and (Loaded.Plan.Digest=Ref.Digest),'Display mode invalidated plan');
        end;
        Need(OffHash<>OnHash,'Equalizer toggle has no visual effect');
        Render.ConfigureStyle(rsRhythmGame,Ref,100,-1);Render.Render(Image,Meta,Times[J],0);Need(ImageHash=OnHash,'Auto game default');
      end;
      Render.ConfigureStyle(rsRhythmGame,Ref,100,0);Render.Render(Image,nil,2.4,0);OffHash:=ImageHash;
      Render.ConfigureStyle(rsRhythmGame,Ref,100,1);Render.Render(Image,nil,2.4,0);Need(ImageHash=OffHash,'No-audio overlay unsafe');
    end;
    Activity:=EqualizerActivity(nil,1);Need(not Activity.Valid,'Nil audio reaction');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"frames":%d,"opaqueCore":true,"symbols":3,"settingsStyles":12,"planUnchanged":true}',[Checks,Frames]),TEncoding.UTF8);
    WriteLn('Orbit presentation PASS checks=',Checks,' frames=',Frames);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  PNG.Free;Surface.Free;Render.Free;Plan.Free;Meta.Free;A.Free;Image.Free;
end.
