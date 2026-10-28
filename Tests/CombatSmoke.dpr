program CombatSmoke;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Classes,System.Types,System.Math,System.IOUtils,System.JSON,
  System.Hash,System.Diagnostics,Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmAudio,RhythmSections,RhythmStage,RhythmMotion,RhythmBarrage,RhythmScene;

var Audio,Flat,Short,Silent,EffectAudio,RealAudio,LongAudio,TailAudio:TRhythmAudio;
  Renderer:TRhythmRenderer;Image,Background:TBitmap;Report:TJSONObject;
  Cue:TRhythmBossCue;Plan:TArray<TRhythmEnemyBullet>;Flybys:TArray<TRhythmFlyby>;
  Schedule:TRhythmStageSchedule;
  B:TRhythmEnemyBullet;Enemy:TRhythmFlyby;P,Q:TRhythmPoint;Hit:TRhythmHit;
  Direction,Backend,I,J,Boss,Count0,Count1,Early,Later,Active,EarlyActive,LateActive:Integer;
  Duration0,Duration1,Speed0,Speed1,ScaleX,ScaleY,T,Minimum,Distance,EarlySpeed,LaterSpeed:Double;
  FirstDifference,LastDifference,BuildMs:Double;Folder,Hash,ErrorText:string;Watch:TStopwatch;

procedure Require(Value:Boolean;const MessageText:string);
begin if not Value then raise Exception.Create(MessageText);end;

function Synthetic(Duration:Double;Varied:Boolean):TRhythmAudio;
var K,N:Integer;Time,Level:Double;
begin
  Result:=TRhythmAudio.Create;Result.Duration:=Duration;Result.Sensitivity:=50;
  SetLength(Result.Envelope,Ceil(Duration*100));
  for K:=0 to High(Result.Envelope) do
  begin
    Time:=K/100;Level:=0.25;
    if Varied then
    begin
      if (Time>=12) and (Time<32) then Level:=0.85;
      if (Time>=32) and (Time<39) then Level:=0.08;
      if (Time>=52) and (Time<75) then Level:=0.95;
      if (Time>=75) and (Time<82) then Level:=0.09;
      if Time>=87 then Level:=0;
    end;
    Result.Envelope[K]:=Level;
  end;
  if Varied then N:=Floor((Min(Duration,87)-0.4)/0.42) else N:=Floor((Duration-0.4)/0.42);
  SetLength(Result.Hits,Max(0,N));
  for K:=0 to High(Result.Hits) do
  begin
    Result.Hits[K].Time:=0.4+K*0.42;Result.Hits[K].Strength:=0.7;
    Result.Hits[K].Lane:=0.15+(K mod 7)*0.1;
    Result.Hits[K].Flight:=ShotFlightTime(Result.Hits[K].Time,Result.Hits[K].Lane,0.7);
  end;
  Result.UpdateSoundBounds;
end;

procedure SaveImage(const Name:string);
var PNG:TPngImage;
begin
  PNG:=TPngImage.Create;
  try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));
  finally PNG.Free;end;
end;

function ImageHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Digest:THashSHA2;
begin
  Stream:=TMemoryStream.Create;
  try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;
    Stream.ReadBuffer(Bytes[0],Length(Bytes));Digest:=THashSHA2.Create;Digest.Update(Bytes);Result:=Digest.HashAsString;
  finally Stream.Free;end;
end;

function CenterDifference(const H:TRhythmHit):Double;
var X,Y,CX,CY:Integer;A,C:Longint;Point:TRhythmPoint;
begin
  Point:=EnemyAt(H,H.Time);CX:=Round(Point.X*Image.Width);CY:=Round(Point.Y*Image.Height);Result:=0;
  for Y:=CY-2 to CY+2 do for X:=CX-2 to CX+2 do
  begin
    A:=ColorToRGB(Image.Canvas.Pixels[X,Y]);C:=ColorToRGB(Background.Canvas.Pixels[X,Y]);
    Result:=Result+Abs((A and 255)-(C and 255))+Abs(((A shr 8) and 255)-((C shr 8) and 255))+
      Abs(((A shr 16) and 255)-((C shr 16) and 255));
  end;
end;

begin
  Audio:=nil;Flat:=nil;Short:=nil;Silent:=nil;EffectAudio:=nil;RealAudio:=nil;LongAudio:=nil;TailAudio:=nil;
  Renderer:=nil;Image:=nil;Background:=nil;Report:=TJSONObject.Create;
  Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'CombatVerification');ForceDirectories(Folder);
  try
    try
      Audio:=Synthetic(90,True);Flat:=Synthetic(90,False);Short:=Synthetic(12,False);Silent:=TRhythmAudio.Create;
      LongAudio:=Synthetic(175,False);TailAudio:=Synthetic(90,False);
      for I:=2000 to High(TailAudio.Envelope) do TailAudio.Envelope[I]:=0;
      SetLength(TailAudio.Hits,40);TailAudio.UpdateSoundBounds;
      Silent.Duration:=90;Silent.UpdateSoundBounds;
      Require(Audio.BossCount=2,'90 second music does not have two bosses');
      Require(LongAudio.BossCount=4,'175 second music does not have four bosses');
      Require((TailAudio.BossCount=1) and (TailAudio.BossCue(0).KillTime<=20),'Trailing silence generated extra bosses');
      for Boss:=1 to LongAudio.BossCount-1 do Require(LongAudio.BossCue(Boss).StartTime>LongAudio.BossCue(Boss-1).KillTime+2,'Long-song bosses overlap');
      Cue:=Audio.BossCue(0);Require(Cue.QuietBoundary and (Abs(Cue.KillTime-32)<0.25),'First boss missed the quiet boundary');
      Require(Cue.KillTime-Cue.StartTime>=18,'First boss encounter is too short');
      Report.AddPair('firstBossStart',TJSONNumber.Create(Cue.StartTime));Report.AddPair('firstBossKill',TJSONNumber.Create(Cue.KillTime));
      Cue:=Audio.BossCue(1);Require(Cue.QuietBoundary and (Abs(Cue.KillTime-75)<0.25),'Second boss missed the quiet boundary');
      Require(Cue.StartTime>Audio.BossCue(0).KillTime+2,'Boss encounters overlap');
      Require(Cue.KillTime-Cue.StartTime>=18,'Second boss encounter is too short');
      Report.AddPair('secondBossStart',TJSONNumber.Create(Cue.StartTime));Report.AddPair('secondBossKill',TJSONNumber.Create(Cue.KillTime));
      Require(Flat.BossCue(1).KillTime>89,'Constant music produced a false early boundary');
      Require(Short.BossCount=1,'Short clip incorrectly schedules multiple bosses');
      Require((Short.BossCue(0).KillTime>10) and (Short.BossCue(0).StartTime>=0),'Short clip has no final boss');
      Require((Silent.BossCue(0).KillTime<0) and (Silent.BossCue(1).KillTime<0),'Silence has a boss');
      Require((ExplosionOpacity(0,0.6)=1) and (ExplosionOpacity(0.6,0.6)=0),'Explosion endpoints are wrong');
      for I:=1 to 59 do Require(ExplosionOpacity(I/100,0.6)<ExplosionOpacity((I-1)/100,0.6),'Explosion opacity does not decrease');
      for Boss:=0 to 1 do
      begin
        Cue:=Audio.BossCue(Boss);T:=ShotFlightToY(Cue.KillTime,0.19);
        P:=PlayerShotAt(psForward,Cue.KillTime,T,0.19,Cue.KillTime);Q:=BossAt(Cue.KillTime,Cue.StartTime,Cue.KillTime);
        Require(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-10,'Boss finisher misses');
      end;
      Flybys:=BuildFlybys(Audio);Require(Length(Flybys)>100,'Flyby traffic is too sparse');
      EarlyActive:=0;LateActive:=0;
      for I:=10 to 80 do
      begin
        Active:=0;
        for Enemy in Flybys do if (I>=Enemy.Launch) and (I<Enemy.Finish) then
        begin
          Inc(Active);P:=FlybyAt(Enemy,I);Require(P.Y<0.26,'Flyby enters normal shot impact lanes');
        end;
        if I<35 then Inc(EarlyActive,Active);
        if I>=56 then Inc(LateActive,Active);
      end;
      Require(LateActive>EarlyActive,'Flyby traffic does not intensify');
      Report.AddPair('flybyCount',TJSONNumber.Create(Length(Flybys)));
      Renderer:=TRhythmRenderer.Create;Image:=TBitmap.Create;Background:=TBitmap.Create;
      Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);Background.SetSize(1280,720);
      for Direction:=0 to 1 do
      begin
        Schedule:=StageSchedule(Audio);
        Watch:=TStopwatch.StartNew;Plan:=BuildBarrage(Audio,1280,720,Direction);BuildMs:=Watch.Elapsed.TotalMilliseconds;
        Count0:=0;Count1:=0;Speed0:=0;Speed1:=0;Minimum:=100;Early:=0;Later:=0;EarlySpeed:=0;LaterSpeed:=0;
        if Direction=0 then begin ScaleX:=720/1280;ScaleY:=1;end else begin ScaleX:=1;ScaleY:=720/1280;end;
        for B in Plan do
        begin
          Distance:=Hypot(B.Velocity.X/ScaleX,B.Velocity.Y/ScaleY);
          if B.Boss=0 then begin Inc(Count0);Speed0:=Speed0+Distance;Require(B.Pattern=bpPetals,'Wrong first boss pattern');end
          else begin
            Inc(Count1);Speed1:=Speed1+Distance;Require(B.Pattern=bpSpiral,'Wrong second boss pattern');
            Cue:=Audio.BossCue(1);T:=(B.Launch-Cue.StartTime)/(Cue.KillTime-Cue.StartTime);
            if T<0.40 then begin Inc(Early);EarlySpeed:=EarlySpeed+Distance;end;
            if T>0.70 then begin Inc(Later);LaterSpeed:=LaterSpeed+Distance;end;
          end;
          for J:=0 to Ceil((B.Finish-B.Launch)*240) do
          begin
            T:=Min(B.Finish,B.Launch+J/240);P:=EnemyBulletAt(B,T);
            Q:=StagePoint(T,Schedule.EntryEnd,Schedule.ExitStart,Schedule.ExitEnd,Schedule.HoldTime);
            Minimum:=Min(Minimum,Hypot((P.X-Q.X)/ScaleX,(P.Y-Q.Y)/ScaleY));
          end;
        end;
        Duration0:=Audio.BossCue(0).KillTime-Audio.BossCue(0).StartTime;
        Duration1:=Audio.BossCue(1).KillTime-Audio.BossCue(1).StartTime;
        Require(Count1/Duration1>Count0/Duration0*1.5,'Second boss density does not increase');
        Require(Speed1/Count1>Speed0/Count0,'Second boss projectiles are not faster');
        Require((Later/0.30>Early/0.40) and (LaterSpeed/Later>EarlySpeed/Early),'Final boss does not ramp up');
        Require(Minimum>0.054,'Projectile intersects the reserved ship corridor');
        Report.AddPair('bullets'+IntToStr(Direction),TJSONNumber.Create(Length(Plan)));
        Report.AddPair('minimumClearance'+IntToStr(Direction),TJSONNumber.Create(Minimum));
        Report.AddPair('planBuildMs'+IntToStr(Direction),TJSONNumber.Create(BuildMs));
        for Backend:=0 to 1 do
        begin
          Renderer.UseD2D:=Backend=1;
          for Boss:=0 to 1 do
          begin
            Cue:=Audio.BossCue(Boss);T:=Cue.KillTime-1.5;
            Renderer.Render(Image,Audio,T,Direction);Hash:=ImageHash;
            SaveImage(Format('boss%d-direction%d-backend%d',[Boss,Direction,Backend]));
            Renderer.Render(Image,Audio,Cue.StartTime+2,Direction);Renderer.Render(Image,Audio,T,Direction);
            Require(Hash=ImageHash,'Random access changed the rendered encounter');
            Renderer.Render(Image,Audio,Cue.KillTime+0.3,Direction);
            SaveImage(Format('boss%d-explosion-direction%d-backend%d',[Boss,Direction,Backend]));
          end;
        end;
      end;
      EffectAudio:=Synthetic(20,False);SetLength(EffectAudio.Hits,1);EffectAudio.Hits[0].Time:=2;
      EffectAudio.Hits[0].Strength:=0.7;EffectAudio.Hits[0].Lane:=0.4;EffectAudio.Hits[0].Flight:=ShotFlightTime(2,0.4,0.7);
      EffectAudio.UpdateSoundBounds;Hit:=EffectAudio.Hits[0];
      for Backend:=0 to 1 do
      begin
        Renderer.UseD2D:=Backend=1;
        Renderer.Render(Background,nil,2.05,0,'');Renderer.Render(Image,EffectAudio,2.05,0);FirstDifference:=CenterDifference(Hit);
        SaveImage('explosion-early-backend'+IntToStr(Backend));
        Renderer.Render(Background,nil,2.50,0,'');Renderer.Render(Image,EffectAudio,2.50,0);LastDifference:=CenterDifference(Hit);
        SaveImage('explosion-late-backend'+IntToStr(Backend));
        Require((FirstDifference>100) and (LastDifference<FirstDifference*0.4),'Rendered explosion does not fade into the background');
      end;
      if ParamCount>0 then
      begin
        RealAudio:=LoadRhythmAudio(ParamStr(1),50);
        Report.AddPair('realDuration',TJSONNumber.Create(RealAudio.Duration));
        Report.AddPair('realBossCount',TJSONNumber.Create(RealAudio.BossCount));
        Plan:=BuildBarrage(RealAudio,1280,720,0);
        for B in Plan do Require(Ord(B.Pattern)=B.Boss mod 4,'Long-song pattern rotation changed');
        for Boss:=0 to RealAudio.BossCount-1 do
        begin
          Cue:=RealAudio.BossCue(Boss);Report.AddPair('realBossKill'+IntToStr(Boss),TJSONNumber.Create(Cue.KillTime));
          Report.AddPair('realBossStart'+IntToStr(Boss),TJSONNumber.Create(Cue.StartTime));
          Report.AddPair('realQuietBoundary'+IntToStr(Boss),TJSONBool.Create(Cue.QuietBoundary));
          if Cue.KillTime>=0 then begin Renderer.UseD2D:=True;Renderer.Render(Image,RealAudio,Cue.KillTime-1.5,0);SaveImage('real-boss'+IntToStr(Boss));end;
        end;
        if RealAudio.BossCount>0 then
        begin
          Cue:=RealAudio.BossCue(RealAudio.BossCount-1);Image.SetSize(1920,1080);
          Renderer.Render(Image,RealAudio,Cue.KillTime-2,0);Watch:=TStopwatch.StartNew;
          for I:=0 to 29 do Renderer.Render(Image,RealAudio,Cue.KillTime-2+I*0.04,0);
          Report.AddPair('realFinalBoss1920MeanMs',TJSONNumber.Create(Watch.Elapsed.TotalMilliseconds/30));
          Report.AddPair('realFinalBossD2D',TJSONBool.Create(Renderer.LastUsedD2D));
        end;
      end;
      Report.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.ClassName+': '+E.Message;Report.AddPair('result','failed');Report.AddPair('error',ErrorText);end;end;
    TFile.WriteAllText(TPath.Combine(Folder,'combat-smoke.json'),Report.ToJSON,TEncoding.UTF8);Writeln(Report.ToJSON);
  finally
    RealAudio.Free;TailAudio.Free;LongAudio.Free;Background.Free;Image.Free;Renderer.Free;EffectAudio.Free;Silent.Free;Short.Free;Flat.Free;Audio.Free;Report.Free;
  end;
  if ErrorText<>'' then Halt(1);
end.
