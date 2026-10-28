program Revision3Smoke;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Math,System.Classes,System.IOUtils,System.JSON,System.Hash,System.Diagnostics,
  Vcl.Graphics,RhythmAudio,RhythmMotion,RhythmScene,RhythmBarrage,RhythmPaths,RhythmSettings,RhythmStage;
var Audio:TRhythmAudio;Renderer:TRhythmRenderer;Bitmap:TBitmap;Root:TJSONObject;Plan:TArray<TRhythmEnemyBullet>;
  H:TRhythmHit;B:TRhythmEnemyBullet;P,Q,Origin:TRhythmPoint;I,J,Direction,Boss,Live,MaxLive,Emissions:Integer;
  XError,HitError,Minimum,Distance,T,ScaleX,ScaleY,Kill,Start,Flight:Double;Folder,ErrorText,Hash1:string;Watch:TStopwatch;
  State,Restored:TRhythmSettings;Cached:TRhythmAudio;EntryEnd,ExitStart,ExitEnd:Double;Synthetic:TRhythmAudio;Schedule,Other:TRhythmStageSchedule;Small:TBitmap;
procedure Require(Value:Boolean;const Text:string);
begin if not Value then raise Exception.Create(Text);end;
function FrameHash:string;
var S:TMemoryStream;Bytes:TBytes;Hash:THashSHA2;
begin S:=TMemoryStream.Create;try Bitmap.SaveToStream(S);SetLength(Bytes,S.Size);S.Position:=0;S.ReadBuffer(Bytes[0],Length(Bytes));Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;finally S.Free;end;end;
begin
  Root:=TJSONObject.Create;Audio:=nil;Renderer:=nil;Bitmap:=nil;
  try
    try
      Folder:=TPath.Combine(ModuleFolder,'Verification');ForceDirectories(Folder);Audio:=LoadRhythmAudio(ParamStr(1),50);
      State:=TRhythmSettings.Defaults;State.Music:=ParamStr(1);State.Direction:=1;State.Sensitivity:=73;State.Zoom:=125;State.X:=-15;State.Y:=27;
      Require(TRhythmSettings.TryJSON(State.ToJSON,Restored),'JSON read failed');Require((Restored.Music=State.Music) and (Restored.Direction=1) and (Restored.Sensitivity=73) and (Restored.Zoom=125) and (Restored.X=-15) and (Restored.Y=27),'JSON round trip changed values');Root.AddPair('jsonRoundTrip','passed');
      Cached:=LoadCachedRhythmAudio(ParamStr(1),50);Require(Cached<>nil,'Prepared cache cannot be loaded');
      try Require((Cached.Key=Audio.Key) and (Length(Cached.Hits)=Length(Audio.Hits)) and (Length(Cached.Envelope)=Length(Audio.Envelope)),'Cache data changed');finally Cached.Free;end;
      Cached:=LoadCachedRhythmAudio(ParamStr(1)+'.missing',50);Require(Cached=nil,'Missing source was accepted');Root.AddPair('preparedCache','passed');
      StageTimes(Audio,EntryEnd,ExitStart,ExitEnd);Schedule:=StageSchedule(Audio);Root.AddPair('entryEnd',TJSONNumber.Create(EntryEnd));Root.AddPair('exitStart',TJSONNumber.Create(ExitStart));Root.AddPair('exitEnd',TJSONNumber.Create(ExitEnd));Root.AddPair('duration',TJSONNumber.Create(Audio.Duration));
      Root.AddPair('soundEnd',TJSONNumber.Create(Audio.SoundEnd));Root.AddPair('clearTime',TJSONNumber.Create(Schedule.ClearTime));Root.AddPair('requiredExtraOutputSeconds',TJSONNumber.Create(Max(0.0,Schedule.ExitEnd-Audio.Duration)));
      if Audio.BossCount>1 then Require(BossKillTime(Audio,Audio.BossCount-1)>BossKillTime(Audio,0),'Boss order is invalid');
      Require(BossKillTime(Audio,Audio.BossCount-1)<=Audio.SoundEnd+0.001,'Final boss is after audible sound');
      if not Audio.BossCue(Audio.BossCount-1).QuietBoundary then Require(BossKillTime(Audio,Audio.BossCount-1)>=Audio.SoundEnd-0.081,'Fallback final boss is too early');
      Require(StageStateAt(Schedule,ExitEnd+30)=ssEnded,'Terminal state reverted');
      for H in Audio.Hits do begin P:=StagePlayerAt(Audio,H.Time-H.Flight);Q:=RhythmMotion.PlayerAt(H.Time-H.Flight);Require(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-10,'Ship displaced during launch');end;
      Require(StagePlayerAt(Audio,ExitEnd+10).Y< -0.1,'Ship returns after exit');
      Synthetic:=TRhythmAudio.Create;
      try
        Synthetic.Duration:=12;SetLength(Synthetic.Hits,1);Synthetic.Hits[0].Time:=3;Synthetic.Hits[0].Flight:=0.5;SetLength(Synthetic.Envelope,1200);Synthetic.Envelope[1000]:=0.5;Synthetic.UpdateSoundBounds;
        StageTimes(Synthetic,T,Minimum,Distance);Require(T>0,'Entrance with time margin was omitted');Require(Minimum>10,'Intermediate silence triggered departure');
        P:=StagePlayerAt(Synthetic,0);Require(P.Y>1,'Entrance does not start below the image');P:=StagePlayerAt(Synthetic,T);Q:=StagePlayerAt(Audio,T);Require(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-12,'Entrance end jumps');
        Synthetic.Hits[0].Time:=0.12;Synthetic.Hits[0].Flight:=0.12;StageTimes(Synthetic,T,Minimum,Distance);Require(T=0,'No-margin entrance interferes with shot');
        Require(BossKillTime(Synthetic,Synthetic.BossCount-1)>9.9,'Sparse accents finish during remaining music');
        Other:=StageSchedule(Synthetic);P:=StagePlayerAt(Synthetic,Other.HoldTime+0.01);Q:=StagePlayerAt(Synthetic,Other.ExitStart-0.01);Require(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-12,'Ship wanders after sound end');
        Synthetic.Hits:=nil;Synthetic.Envelope:=nil;Synthetic.Duration:=4;Synthetic.UpdateSoundBounds;Other:=StageSchedule(Synthetic);Require(Other.ClearTime=0,'Silent track never clears');Require(StageStateAt(Other,2)=ssEnded,'Silent track never exits');
        Synthetic.Duration:=0.05;SetLength(Synthetic.Envelope,5);Synthetic.Envelope[4]:=0.5;Synthetic.UpdateSoundBounds;Other:=StageSchedule(Synthetic);Require(Other.ClearTime>=0.05,'Short track clears before audio ends');Require(Other.ExitEnd>0.05,'Short clip incorrectly changes its host length');
      finally Synthetic.Free;end;
      Root.AddPair('stageTiming','passed');
      XError:=0;HitError:=0;
      for H in Audio.Hits do
      begin
        Origin:=RhythmMotion.PlayerAt(H.Time-H.Flight);
        for J:=0 to 20 do begin P:=BulletAt(H,H.Time-H.Flight+H.Flight*J/20);XError:=Max(XError,Abs(P.X-Origin.X));end;
        P:=BulletAt(H,H.Time);Q:=EnemyAt(H,H.Time);HitError:=Max(HitError,Hypot(P.X-Q.X,P.Y-Q.Y));
      end;
      Require(XError<1E-12,'Normal shot changes its lateral coordinate');Require(HitError<1E-10,'Forward shot misses the enemy');
      Root.AddPair('normalShotMaxLateralError',TJSONNumber.Create(XError));Root.AddPair('normalShotMaxImpactError',TJSONNumber.Create(HitError));
      for Boss:=0 to Audio.BossCount-1 do
      begin
        Kill:=BossKillTime(Audio,Boss);if Kill<0 then Continue;Start:=BossStartTime(Audio,Boss);Flight:=ShotFlightToY(Kill,0.19);
        P:=PlayerShotAt(psForward,Kill,Flight,0.19,Kill);Q:=BossAt(Kill,Start,Kill);Require(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-10,'Forward boss shot misses');
      end;
      Renderer:=TRhythmRenderer.Create;Bitmap:=TBitmap.Create;Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(1280,720);
      for Direction:=0 to 1 do
      begin
        Plan:=BuildBarrage(Audio,1280,720,Direction);Minimum:=100;Emissions:=0;
        if Direction=0 then begin ScaleX:=720/1280;ScaleY:=1;end else begin ScaleX:=1;ScaleY:=720/1280;end;
        for B in Plan do for J:=0 to Ceil((B.Finish-B.Launch)*240) do
        begin
          T:=Min(B.Finish,B.Launch+J/240);P:=EnemyBulletAt(B,T);Q:=StagePoint(T,EntryEnd,ExitStart,ExitEnd,Schedule.HoldTime);
          Distance:=Hypot((P.X-Q.X)/ScaleX,(P.Y-Q.Y)/ScaleY);Minimum:=Min(Minimum,Distance);
        end;
        Require(Minimum>0.054,'Radial bullet intersects the reserved ship bounds');Require(Length(Plan)>100,'Radial pattern is unexpectedly sparse');
        MaxLive:=0;for I:=0 to Ceil(Audio.Duration*10) do begin T:=I/10;Live:=0;for B in Plan do if (T>=B.Launch) and (T<B.Finish) then begin P:=EnemyBulletAt(B,T);if (P.X>=0) and (P.X<=1) and (P.Y>=0) and (P.Y<=1) then Inc(Live);end;MaxLive:=Max(MaxLive,Live);end;
        Root.AddPair('acceptedRadialBullets_'+IntToStr(Direction),TJSONNumber.Create(Length(Plan)));Root.AddPair('maxVisibleBullets_'+IntToStr(Direction),TJSONNumber.Create(MaxLive));Root.AddPair('minimumShipDistanceInViewportUnits_'+IntToStr(Direction),TJSONNumber.Create(Minimum));
        Renderer.Render(Bitmap,Audio,14.48,Direction);Hash1:=FrameHash;Renderer.Render(Bitmap,Audio,26.68,Direction);Renderer.Render(Bitmap,Audio,14.48,Direction);Require(Hash1=FrameHash,'Seek is nondeterministic');
        Bitmap.SaveToFile(TPath.Combine(Folder,'radial-direction'+IntToStr(Direction)+'.bmp'));
      end;
      Bitmap.SetSize(1920,1080);Renderer.Render(Bitmap,Audio,14.48,0);Watch:=TStopwatch.StartNew;
      for I:=0 to 59 do Renderer.Render(Bitmap,Audio,12+I/60*5,0);
      Root.AddPair('d2d1920x1080MeanMs',TJSONNumber.Create(Watch.Elapsed.TotalMilliseconds/60));Root.AddPair('d2dUsed',TJSONBool.Create(Renderer.LastUsedD2D));
      for Direction:=0 to 1 do begin
        Renderer.Render(Bitmap,nil,0,Direction,'');Bitmap.SaveToFile(TPath.Combine(Folder,'stars-direction'+IntToStr(Direction)+'.bmp'));
        Renderer.Render(Bitmap,nil,0.25,Direction,'');Bitmap.SaveToFile(TPath.Combine(Folder,'stars-quarter-direction'+IntToStr(Direction)+'.bmp'));
        Small:=TBitmap.Create;try Small.SetSize(640,360);Small.Canvas.StretchDraw(Rect(0,0,640,360),Bitmap);Small.SaveToFile(TPath.Combine(Folder,'stars-reduced-direction'+IntToStr(Direction)+'.bmp'));finally Small.Free;end;
        Renderer.Render(Bitmap,Audio,0.7,Direction);Bitmap.SaveToFile(TPath.Combine(Folder,'entry-direction'+IntToStr(Direction)+'.bmp'));
        Renderer.Render(Bitmap,Audio,ExitStart+0.4,Direction);Bitmap.SaveToFile(TPath.Combine(Folder,'exit-direction'+IntToStr(Direction)+'.bmp'));
        Renderer.Render(Bitmap,Audio,ExitEnd+10,Direction);Hash1:=FrameHash;
        Renderer.Render(Bitmap,Audio,0.7,Direction);Renderer.Render(Bitmap,Audio,ExitEnd+10,Direction);Require(Hash1=FrameHash,'Exit seek differs');
      end;
      Root.AddPair('waveform','unchanged; flicker fix accepted by user');Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.ClassName+': '+E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    TFile.WriteAllText(TPath.Combine(Folder,'revision3-smoke.json'),Root.ToJSON,TEncoding.UTF8);Writeln(Root.ToJSON);
  finally Bitmap.Free;Renderer.Free;Audio.Free;Root.Free;end;
  if ErrorText<>'' then Halt(1);
end.
