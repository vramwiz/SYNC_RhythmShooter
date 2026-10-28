program RhythmSmoke;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.Math, System.IOUtils, System.JSON,
  System.Hash, System.Diagnostics, Vcl.Graphics, Winapi.Windows,
  RhythmAudio in '..\Source\Audio\RhythmAudio.pas',
  RhythmPlayback in '..\Source\Audio\RhythmPlayback.pas',
  RhythmScene in '..\Source\Engine\RhythmScene.pas',
  RhythmPaths in '..\Source\Common\RhythmPaths.pas',
  MimiChildProcess in '..\Source\Lib\Process\MimiChildProcess.pas';
var A,B:TRhythmAudio;Renderer:TRhythmRenderer;Bitmap:Vcl.Graphics.TBitmap;
  Root,Item:TJSONObject;Events:TJSONArray;Watch:TStopwatch;Player:TRhythmPlayback;
  I,Direction,BossIndex,HitIndex:Integer;P,Q:TRhythmPoint;MaxError,MaxSpeedError,Speed,T1,T2,T3,T4,T5,T6,BossTarget:Double;
  Folder,Hash1,Hash2,ErrorText:string;
procedure Require(Value:Boolean;const MessageText:string);
begin if not Value then raise Exception.Create(MessageText);end;
function FrameHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Hash:THashSHA2;
begin
  Stream:=TMemoryStream.Create;
  try Bitmap.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;
    Stream.ReadBuffer(Bytes[0],Length(Bytes));Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;
  finally Stream.Free;end;
end;
procedure Number(const Name:string;Value:Double);
begin Root.AddPair(Name,TJSONNumber.Create(Value));end;
begin
  A:=nil;B:=nil;Renderer:=nil;Bitmap:=nil;Player:=nil;Root:=TJSONObject.Create;
  try
    try
      if ParamCount<1 then raise Exception.Create('Pass the WAV/MP3 source. Optional second argument: --audio');
      Folder:=TPath.Combine(ModuleFolder,'Verification');ForceDirectories(Folder);
      Watch:=TStopwatch.StartNew;A:=LoadRhythmAudio(ParamStr(1),50);Number('firstLoadMs',Watch.Elapsed.TotalMilliseconds);
      Root.AddPair('source',A.Source);Root.AddPair('sha256',A.Key);Number('durationSeconds',A.Duration);
      Number('pcmBytes',Length(A.PCM));Number('hitCount',Length(A.Hits));
      Root.AddPair('firstLoadCacheReused',TJSONBool.Create(A.CacheReused));
      Require(A.Duration>0,'No decoded duration');Require(Length(A.Hits)>0,'No accent events detected');
      Watch:=TStopwatch.StartNew;B:=LoadRhythmAudio(ParamStr(1),50);Number('cachedLoadMs',Watch.Elapsed.TotalMilliseconds);
      Require(B.CacheReused,'PCM cache not reused');Require(Length(A.Hits)=Length(B.Hits),'Hit count changed on cached load');
      MaxError:=0;MaxSpeedError:=0;
      Events:=TJSONArray.Create;Root.AddPair('firstHits',Events);
      for I:=0 to High(A.Hits) do
      begin
        Require(Abs(A.Hits[I].Time-B.Hits[I].Time)<1E-9,'Hit timestamp changed');
        Require(A.Hits[I].Time-A.Hits[I].Flight>=-1E-9,'Shot precedes audio start');
        if I>0 then Require(A.Hits[I].Time-A.Hits[I-1].Time>=0.18-1E-9,'Hit events too dense');
        P:=BulletAt(A.Hits[I],A.Hits[I].Time);Q:=EnemyAt(A.Hits[I],A.Hits[I].Time);
        MaxError:=Max(MaxError,Hypot(P.X-Q.X,P.Y-Q.Y));
        if A.Hits[I].Time-A.Hits[I].Flight>1E-6 then
        begin
          P:=PlayerAt(A.Hits[I].Time-A.Hits[I].Flight);
          Speed:=Hypot(P.X-Q.X,P.Y-Q.Y)/A.Hits[I].Flight;
          MaxSpeedError:=Max(MaxSpeedError,Abs(Speed-1.25));
        end;
        if I<12 then begin Item:=TJSONObject.Create;Item.AddPair('hit',TJSONNumber.Create(A.Hits[I].Time));
          Item.AddPair('fire',TJSONNumber.Create(A.Hits[I].Time-A.Hits[I].Flight));Events.AddElement(Item);end;
      end;
      Number('maxHitPositionErrorNormalized',MaxError);Require(MaxError<1E-9,'Bullet misses at hit time');
      Number('maxNominalBulletSpeedError',MaxSpeedError);Require(MaxSpeedError<1E-6,'Distance/speed launch inversion failed');
      Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Require(Renderer.AssetCount=15,'Not all module-relative assets loaded');Number('assetCount',Renderer.AssetCount);
      Bitmap:=Vcl.Graphics.TBitmap.Create;Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(1280,720);
      for Direction:=0 to 1 do
      begin
        Renderer.Render(Bitmap,A,A.Hits[Min(8,High(A.Hits))].Time+0.03,Direction);
        Hash1:=FrameHash;Renderer.Render(Bitmap,A,A.Duration*0.8,Direction);
        Renderer.Render(Bitmap,A,A.Hits[Min(8,High(A.Hits))].Time+0.03,Direction);Hash2:=FrameHash;
        Require(Hash1=Hash2,'Random seek changed the rendered frame');
        Root.AddPair('deterministicFrameSHA256_'+IntToStr(Direction),Hash1);
        Bitmap.SaveToFile(TPath.Combine(Folder,'direction'+IntToStr(Direction)+'.bmp'));
      end;
      Bitmap.SetSize(1920,1080);Watch:=TStopwatch.StartNew;
      for I:=0 to 119 do Renderer.Render(Bitmap,A,(I/119)*A.Duration,0);
      Number('render1920x1080MeanMs',Watch.Elapsed.TotalMilliseconds/120);
      Renderer.UseD2D:=True;
      for BossIndex:=0 to 1 do
      begin
        if BossIndex=0 then BossTarget:=A.Duration*0.5 else BossTarget:=A.Duration*0.94;
        HitIndex:=A.NearestHit(BossTarget);
        for Direction:=0 to 1 do
        begin
          Renderer.Render(Bitmap,A,Max(0.0,A.Hits[HitIndex].Time-0.6),Direction);
          Bitmap.SaveToFile(TPath.Combine(Folder,'sample-boss'+IntToStr(BossIndex)+'-direction'+IntToStr(Direction)+'.bmp'));
        end;
      end;
      Renderer.UseD2D:=False;
      FreeAndNil(B);B:=TRhythmAudio.Create;B.Duration:=30;SetLength(B.Hits,1501);
      for I:=0 to High(B.Hits) do begin B.Hits[I].Time:=I*0.02;B.Hits[I].Lane:=0.15+(I mod 31)/30*0.7;B.Hits[I].Strength:=0.7;B.Hits[I].Flight:=0.45;end;
      Watch:=TStopwatch.StartNew;
      for I:=0 to 9 do Renderer.Render(Bitmap,B,14.45+I*0.001,0);
      Number('synthetic1260BossBullets1920x1080MeanMs',Watch.Elapsed.TotalMilliseconds/10);
      Renderer.Render(Bitmap,B,14.45,0);Bitmap.SaveToFile(TPath.Combine(Folder,'stress-bullets.bmp'));
      Renderer.UseD2D:=True;Watch:=TStopwatch.StartNew;
      for I:=0 to 119 do Renderer.Render(Bitmap,A,(I/119)*A.Duration,0);
      Number('d2dRender1920x1080MeanMs',Watch.Elapsed.TotalMilliseconds/120);
      Watch:=TStopwatch.StartNew;
      for I:=0 to 9 do Renderer.Render(Bitmap,B,14.45+I*0.001,0);
      Number('d2dSynthetic1260BossBullets1920x1080MeanMs',Watch.Elapsed.TotalMilliseconds/10);
      Root.AddPair('d2dActuallyUsed',TJSONBool.Create(Renderer.LastUsedD2D));
      Renderer.Render(Bitmap,B,14.45,0);Bitmap.SaveToFile(TPath.Combine(Folder,'stress-d2d.bmp'));
      for Direction:=0 to 1 do
      begin
        Renderer.Render(Bitmap,A,8.69,Direction);Hash1:=FrameHash;Renderer.Render(Bitmap,A,24,Direction);
        Renderer.Render(Bitmap,A,8.69,Direction);Require(Hash1=FrameHash,'D2D seek changed the rendered frame');
        Bitmap.SaveToFile(TPath.Combine(Folder,'d2d-direction'+IntToStr(Direction)+'.bmp'));
      end;
      Renderer.UseD2D:=False;
      if (ParamCount>1) and (ParamStr(2)='--audio') then
      begin
        Player:=TRhythmPlayback.Create;Player.SetAudio(A);Player.Play;
        Sleep(250);T1:=Player.Position;Sleep(250);T2:=Player.Position;
        Require(T2>T1,'Audio output clock does not advance');
        Player.Pause;T3:=Player.Position;Sleep(250);T4:=Player.Position;
        Require(Abs(T4-T3)<0.025,'Paused audio clock advanced');
        Player.Seek(4.5);T5:=Player.Position;Require(Player.Paused,'Paused seek lost pause state');
        Require(Abs(T5-4.5)<0.025,'Paused seek timestamp mismatch');
        Player.Play;Sleep(250);T6:=Player.Position;Require(T6>T5,'Resume clock does not advance');
        Player.Seek(17);Sleep(200);Number('playingSeekPosition',Player.Position);
        Player.Stop;Require(Abs(Player.Position)<1E-9,'Stop did not rewind');
        Number('playPosition1',T1);Number('playPosition2',T2);Number('pauseBefore',T3);Number('pauseAfter',T4);Number('pausedSeek',T5);Number('resumedPosition',T6);
        FreeAndNil(Player);Root.AddPair('audioResourceCleanup','completed');
      end else Root.AddPair('audioDeviceTest','not requested');
      Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.ClassName+': '+E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    if Folder<>'' then
      if (ParamCount>1) and (ParamStr(2)='--audio') then
        TFile.WriteAllText(TPath.Combine(Folder,'smoke-audio.json'),Root.ToJSON,TEncoding.UTF8)
      else TFile.WriteAllText(TPath.Combine(Folder,'smoke.json'),Root.ToJSON,TEncoding.UTF8);
    Writeln(Root.ToJSON);
  finally Player.Free;Bitmap.Free;Renderer.Free;B.Free;A.Free;Root.Free;end;
  if ErrorText<>'' then Halt(1);
end.
