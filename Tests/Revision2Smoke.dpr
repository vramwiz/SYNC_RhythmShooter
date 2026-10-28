program Revision2Smoke;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Math,System.Classes,System.IOUtils,System.JSON,System.Hash,System.Diagnostics,
  Vcl.Graphics,RhythmAudio,RhythmMotion,RhythmScene,RhythmBarrage,RhythmPaths,RhythmSettings;
var Audio:TRhythmAudio;Renderer:TRhythmRenderer;Bitmap:TBitmap;Root:TJSONObject;Plan:TArray<TRhythmEnemyBullet>;
  H:TRhythmHit;B:TRhythmEnemyBullet;P,Q,Origin:TRhythmPoint;I,J,Direction,Boss,Index,Live,MaxLive,Emissions:Integer;
  XError,HitError,Minimum,Distance,T,ScaleX,ScaleY,Kill,Start,Flight,Target:Double;Folder,ErrorText,Hash1:string;Watch:TStopwatch;
  State,Restored:TRhythmSettings;
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
      XError:=0;HitError:=0;
      for H in Audio.Hits do
      begin
        Origin:=RhythmMotion.PlayerAt(H.Time-H.Flight);
        for J:=0 to 20 do begin P:=BulletAt(H,H.Time-H.Flight+H.Flight*J/20);XError:=Max(XError,Abs(P.X-Origin.X));end;
        P:=BulletAt(H,H.Time);Q:=EnemyAt(H,H.Time);HitError:=Max(HitError,Hypot(P.X-Q.X,P.Y-Q.Y));
      end;
      Require(XError<1E-12,'Normal shot changes its lateral coordinate');Require(HitError<1E-10,'Forward shot misses the enemy');
      Root.AddPair('normalShotMaxLateralError',TJSONNumber.Create(XError));Root.AddPair('normalShotMaxImpactError',TJSONNumber.Create(HitError));
      for Boss:=0 to 1 do
      begin
        if Boss=0 then Target:=Audio.Duration*0.5 else Target:=Audio.Duration*0.94;
        Index:=Audio.NearestHit(Target);Kill:=Audio.Hits[Index].Time;Start:=Kill-Min(6.0,Audio.Duration*0.18);Flight:=ShotFlightToY(Kill,0.19);
        P:=PlayerShotAt(psForward,Kill,Flight,0.19,Kill);Q:=BossAt(Kill,Start,Kill);Require(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-10,'Forward boss shot misses');
      end;
      Renderer:=TRhythmRenderer.Create;Bitmap:=TBitmap.Create;Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(1280,720);
      for Direction:=0 to 1 do
      begin
        Plan:=BuildBarrage(Audio,1280,720,Direction);Minimum:=100;Emissions:=0;
        if Direction=0 then begin ScaleX:=720/1280;ScaleY:=1;end else begin ScaleX:=1;ScaleY:=720/1280;end;
        for B in Plan do for J:=0 to 1008 do
        begin
          T:=B.Launch+J/240;P:=EnemyBulletAt(B,T);Q:=RhythmMotion.PlayerAt(T);
          Distance:=Hypot((P.X-Q.X)/ScaleX,(P.Y-Q.Y)/ScaleY);Minimum:=Min(Minimum,Distance);
        end;
        Require(Minimum>0.054,'Radial bullet intersects the reserved ship bounds');Require(Length(Plan)>100,'Radial pattern is unexpectedly sparse');
        MaxLive:=0;for I:=0 to 600 do begin T:=I/20;Live:=0;for B in Plan do if (T>=B.Launch) and (T<B.Finish) then begin P:=EnemyBulletAt(B,T);if (P.X>=0) and (P.X<=1) and (P.Y>=0) and (P.Y<=1) then Inc(Live);end;MaxLive:=Max(MaxLive,Live);end;
        Root.AddPair('acceptedRadialBullets_'+IntToStr(Direction),TJSONNumber.Create(Length(Plan)));Root.AddPair('maxVisibleBullets_'+IntToStr(Direction),TJSONNumber.Create(MaxLive));Root.AddPair('minimumShipDistanceInViewportUnits_'+IntToStr(Direction),TJSONNumber.Create(Minimum));
        Renderer.Render(Bitmap,Audio,14.48,Direction);Hash1:=FrameHash;Renderer.Render(Bitmap,Audio,26.68,Direction);Renderer.Render(Bitmap,Audio,14.48,Direction);Require(Hash1=FrameHash,'Seek is nondeterministic');
        Bitmap.SaveToFile(TPath.Combine(Folder,'radial-direction'+IntToStr(Direction)+'.bmp'));
      end;
      Bitmap.SetSize(1920,1080);Renderer.Render(Bitmap,Audio,14.48,0);Watch:=TStopwatch.StartNew;
      for I:=0 to 59 do Renderer.Render(Bitmap,Audio,12+I/60*5,0);
      Root.AddPair('d2d1920x1080MeanMs',TJSONNumber.Create(Watch.Elapsed.TotalMilliseconds/60));Root.AddPair('d2dUsed',TJSONBool.Create(Renderer.LastUsedD2D));
      Root.AddPair('waveform','cached opaque double-buffered control; GUI flicker not visually verified');Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.ClassName+': '+E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    TFile.WriteAllText(TPath.Combine(Folder,'revision2-smoke.json'),Root.ToJSON,TEncoding.UTF8);Writeln(Root.ToJSON);
  finally Bitmap.Free;Renderer.Free;Audio.Free;Root.Free;end;
  if ErrorText<>'' then Halt(1);
end.
