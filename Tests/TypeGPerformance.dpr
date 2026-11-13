program TypeGPerformance;
{$APPTYPE CONSOLE}
// Type.Gの32画面を実際のGDI/Direct2Dで描き、1080pの描画時間を記録する。解析・再生は行わない。
uses System.SysUtils, System.Math, System.Classes, System.IOUtils, System.Diagnostics,
  System.JSON, Vcl.Graphics, Vcl.Imaging.pngimage, RhythmAudio, RhythmGPlan,
  RhythmGArt, RhythmGImages, RhythmRenderSurface, RhythmAnimation;
var Audio: TRhythmAudio; Plan: TGPlan; Surface: TAnimationRenderSurface;
  Bitmap,Sheet: TBitmap; PNG: TPngImage; Frame: TAnimationFrame; Watch: TStopwatch;
  Rows: TJSONArray; Row: TJSONObject; Folder,Backend: string; Mode,G,I: Integer; Time,MS: Double;
begin
  Audio:=nil; Plan:=nil; Surface:=nil; Bitmap:=nil; Sheet:=nil; PNG:=nil; Rows:=nil;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence'); ForceDirectories(Folder);
    Audio:=TRhythmAudio.Create; Audio.Duration:=16; SetLength(Audio.Hits,32);
    for I:=0 to 31 do begin Audio.Hits[I].Time:=I*0.5+0.25; Audio.Hits[I].Strength:=0.7; end;
    Plan:=BuildGPlan(Audio); SetLength(Plan.Scenes,1); Plan.Scenes[0].Start:=0; Plan.Scenes[0].Finish:=16; Plan.Transitions:=False;
    Surface:=TAnimationRenderSurface.Create(CreateGImages); Bitmap:=TBitmap.Create;
    Bitmap.PixelFormat:=pf32bit; Bitmap.SetSize(1920,1080); Sheet:=TBitmap.Create; Sheet.SetSize(1600,2240);
    Rows:=TJSONArray.Create; Frame:=Default(TAnimationFrame); Frame.Width:=1920; Frame.Height:=1080;
    for Mode:=0 to 1 do begin
      Surface.UseD2D:=Mode=1; if Mode=0 then Backend:='GDI' else Backend:='Direct2D';
      for G:=0 to 31 do begin
        Plan.Scenes[0].Game:=G; Plan.RebuildCues(Audio); Time:=Plan.Cues[0].Time;
        Frame.Time:=Time; Surface.BeginFrame(Bitmap); DrawTypeG(Surface,Plan,Frame); Surface.EndFrame;
        Watch:=TStopwatch.StartNew;
        for I:=0 to 7 do begin
          Frame.Time:=Time+I*0.016; Surface.BeginFrame(Bitmap); DrawTypeG(Surface,Plan,Frame);
          if not Surface.EndFrame then raise Exception.Create('Render failure');
        end;
        Watch.Stop; MS:=Watch.Elapsed.TotalMilliseconds/8;
        Row:=TJSONObject.Create; Rows.AddElement(Row); Row.AddPair('game',GNames[G]);
        Row.AddPair('backend',Backend); Row.AddPair('meanMs',TJSONNumber.Create(MS));
        if Mode=1 then begin
          Frame.Time:=Time; Surface.BeginFrame(Bitmap); DrawTypeG(Surface,Plan,Frame); Surface.EndFrame;
          Sheet.Canvas.StretchDraw(Rect((G mod 4)*400,(G div 4)*280,(G mod 4+1)*400,(G div 4+1)*280),Bitmap);
        end;
      end;
    end;
    PNG:=TPngImage.Create; PNG.Assign(Sheet); PNG.SaveToFile(TPath.Combine(Folder,'all-32-games.png'));
    TFile.WriteAllText(TPath.Combine(Folder,'performance1080.json'),Rows.ToJSON,TEncoding.UTF8);
    WriteLn('Type.G 1080p performance + 32-game gallery PASS');
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message); ExitCode:=1; end; end;
  Rows.Free; PNG.Free; Sheet.Free; Bitmap.Free; Surface.Free; Plan.Free; Audio.Free;
end.
