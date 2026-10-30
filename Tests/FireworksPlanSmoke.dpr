program FireworksPlanSmoke;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Math,System.Classes,System.Hash,Vcl.Graphics,
  RhythmAudio,RhythmFireworksPlan,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmSettings,RhythmScene,RhythmPaths,RhythmPlayback;
var Audio:TRhythmAudio;Plan,Again,Loaded:TFireworksPlan;Ref,BadRef:TRhythmPlanRef;
  Renderer:TRhythmRenderer;Image:TBitmap;B:TFireworkBurst;P,Q:TFireworkPoint;
  Player:TRhythmPlayback;State,Restored:TRhythmSettings;I,CaseIndex,Direction,Backend,RichnessIndex,Richness,Volley,J:Integer;
  DenseRays:array[0..2] of Integer;
  Gap,Time:Double;Hash,TerminalHash,FireworksSettings,CommonCache:string;Rejected:Boolean;
  Seen:array[TFireworkKind] of Boolean;
procedure Require(Value:Boolean;const MessageText:string);
begin if not Value then raise Exception.Create(MessageText);end;
function ImageHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Hash:THashSHA2;
begin
  Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;Stream.ReadBuffer(Bytes[0],Length(Bytes));
    Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;finally Stream.Free;end;
end;
procedure MakeAudio(Spacing:Double);
var N:Integer;
begin
  Audio:=TRhythmAudio.Create;Audio.Key:=StringOfChar('c',64);Audio.Sensitivity:=50;Audio.Duration:=22;
  SetLength(Audio.Envelope,2200);for N:=0 to 1999 do Audio.Envelope[N]:=0.5;
  SetLength(Audio.Hits,Floor(19.5/Spacing)+1);
  for N:=0 to High(Audio.Hits) do begin Audio.Hits[N].Time:=0.5+N*Spacing;Audio.Hits[N].Strength:=0.3+(N mod 5)*0.175;end;
  Audio.UpdateSoundBounds;
end;
begin
  Audio:=nil;Plan:=nil;Again:=nil;Loaded:=nil;Renderer:=nil;Image:=nil;Player:=nil;FillChar(DenseRays,SizeOf(DenseRays),0);
  try
    ConfigureRhythmProduct('SYNC_RhythmFireworks','リズム花火',rsFireworks);
    Require(TRhythmSettings.Defaults.Style=rsFireworks,'Fireworks default missing');
    Require((Ord(rsShooting)=0) and (Ord(rsBall)=1) and (StylePlanVersion(rsBall)=5),'Existing styles changed');
    Require(TRhythmSettings.TryJSON('{"schema":1,"music":"old.wav"}',State) and (State.Style=rsShooting),'Legacy JSON changed style');
    FireworksSettings:=SettingsPath;CommonCache:=CacheFolder;
    for CaseIndex:=0 to 3 do begin
      case CaseIndex of 0,3:Gap:=0.18;1:Gap:=1.4;else Gap:=3.5;end;MakeAudio(Gap);
      if CaseIndex=3 then for I:=0 to 7 do Audio.Hits[I].Time:=0;
      for RichnessIndex:=0 to 2 do begin
        case RichnessIndex of 0:Richness:=0;1:Richness:=50;else Richness:=100;end;
        Volley:=FireworkVolleyCount(Richness);
      for Direction:=0 to 1 do begin
        Plan:=TFireworksPlan.Build(Audio,Direction,Richness);Again:=TFireworksPlan.Build(Audio,Direction,Richness);FillChar(Seen,SizeOf(Seen),0);
        Require((Plan.SourceEventCount=Length(Audio.Hits)) and (Plan.Count=Length(Audio.Hits)*Volley),'Fireworks discarded accents');
        for I:=0 to Plan.Count-1 do begin
          B:=Plan.Burst[I];Seen[B.Kind]:=True;
          Require(B.Time=Audio.Hits[B.AccentIndex].Time,'Bloom no longer matches the accent');
          Require((B.X=Again.Burst[I].X) and (B.Y=Again.Burst[I].Y) and (B.Seed=Again.Burst[I].Seed),'Fireworks plan is not deterministic');
          Require((B.LaunchTime>=0) and (B.LaunchTime<=B.Time),'Launch was not inverted from bloom');
          P:=FireworkRocketAt(B,B.Time);Require((Abs(P.X-B.X)<1E-10) and (Abs(P.Y-B.Y)<1E-10),'Rocket misses its bloom point');
          if B.LaunchTime<B.Time then begin P:=FireworkRocketAt(B,B.LaunchTime);Require(Abs(P.Y-0.88)<1E-10,'Rocket does not start at the horizon');end;
          Require((B.Rays>=16) and (B.Rays<=128),'Particle count is unbounded');
          Require((B.AccentIndex=I div Volley) and (B.Member=I mod Volley),'Audio-to-volley mapping changed');
          Require(B.GroundX=B.X,'Launch is not vertical');
          for J:=1 to 9 do begin
            P:=FireworkRocketAt(B,B.LaunchTime+(B.Time-B.LaunchTime)*J/10);
            Require(Abs(P.X-B.X)<1E-10,'Rocket curves horizontally');
            Q:=FireworkSparkOffset(B,J,0.5);P:=FireworkSparkOffset(B,J,0.5);
            Require((Q.X=P.X) and (Q.Y=P.Y),'Spark shape is not deterministic');
          end;
          if I>=Volley then Require(B.LaunchTime>=Plan.Burst[I-Volley].LaunchTime,'Consecutive launches changed order');
          Require(Plan.EndTime>=B.Time+B.Lifetime,'Afterglow is cut off by the plan');
        end;
        Require(Seen[fwPeony] and Seen[fwWillow] and Seen[fwRings] and Seen[fwStar] and Seen[fwHeart] and Seen[fwPalm],'Firework shapes missing');
        if (CaseIndex=0) and (Direction=0) then DenseRays[RichnessIndex]:=Plan.Burst[1].Rays;
        if (CaseIndex=2) and (Direction=0) then Require(Plan.Burst[1].Rays>DenseRays[RichnessIndex],'Dense particle scaling missing');
        Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,Direction,rsFireworks,Richness);Plan.Save(Ref);Loaded:=TFireworksPlan.Load(Ref,Audio,Direction);
        Require((Loaded.Count=Plan.Count) and (Abs(Loaded.EndTime-Plan.EndTime)<1E-8),'Fireworks did not round trip');
        for I:=0 to Loaded.Count-1 do Require((Abs(Loaded.Burst[I].Time-Plan.Burst[I].Time)<1E-9) and (Loaded.Burst[I].Seed=Plan.Burst[I].Seed),'Saved bloom changed');FreeAndNil(Loaded);
        State:=TRhythmSettings.Defaults;State.Music:='keep.mp3';State.Plan:=Ref;State.Direction:=Direction;State.FireworksRichness:=Richness;State.Designs[8].Memo:='keep shooting design';
        Require(TRhythmSettings.TryJSON(State.ToJSON,Restored) and (Restored.Style=rsFireworks) and (Restored.Plan.Digest=Ref.Digest) and (Restored.FireworksRichness=Richness) and (Restored.Designs[8].Memo=State.Designs[8].Memo),'Fireworks settings did not round trip');
        State.Plan:=Default(TRhythmPlanRef);Require(TRhythmSettings.TryJSON(State.ToJSON,Restored) and (Restored.Music=State.Music) and (Restored.Plan.Key=''),'Unprepared fireworks settings cannot be saved');
        BadRef:=Ref;BadRef.Version:=1;State.Plan:=BadRef;
        Require(TRhythmSettings.TryJSON(State.ToJSON,Restored) and (Restored.Plan.Key='') and (Restored.FireworksRichness=Richness) and (Restored.Music=State.Music),'Old fireworks plan lost user settings');
        Require(not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsFireworks,(Richness+1) mod 101),'Richness does not invalidate the plan');
        Require(AnimationPlanKey(Audio.Key,50,Direction,rsShooting)=AnimationPlanKey(Audio.Key,50,Direction,rsShooting,StyleVariant(rsShooting,Richness)),'Richness changed Shooting cache identity');
        BadRef:=Ref;BadRef.Digest:=StringOfChar('0',64);Rejected:=False;
        try Loaded:=TFireworksPlan.Load(BadRef,Audio,Direction);except Rejected:=True;end;Require(Rejected,'Invalid fireworks digest accepted');FreeAndNil(Loaded);
        Require(AnimationPlanKey(Audio.Key,50,Direction,rsBall)<>Ref.Key,'Genre plan keys collide');
        Renderer:=TRhythmRenderer.Create;Renderer.ConfigureStyle(rsFireworks,Ref);Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);
        for Backend:=0 to 1 do begin
          Renderer.UseD2D:=Backend=1;Time:=Audio.Hits[3].Time+0.25;Renderer.Render(Image,Audio,Time,Direction);Hash:=ImageHash;
          Renderer.Render(Image,Audio,Plan.EndTime+1,Direction);TerminalHash:=ImageHash;
          Require(Image.Canvas.Pixels[Image.Width div 2,Image.Height div 3]<>Image.Canvas.Pixels[Image.Width div 2,Image.Height-2],'Night sky and lower landscape are indistinguishable');
          Renderer.Render(Image,Audio,Plan.EndTime+100,Direction);Require(ImageHash=TerminalHash,'Background keeps moving after the end');
          Renderer.Render(Image,Audio,Time,Direction);Require(ImageHash=Hash,'Fireworks changed after terminal seek');
        end;
        FreeAndNil(Renderer);FreeAndNil(Image);FreeAndNil(Again);FreeAndNil(Plan);
      end;end;FreeAndNil(Audio);
    end;
    Audio:=TRhythmAudio.Create;Audio.Key:=StringOfChar('d',64);Audio.Sensitivity:=50;Audio.Duration:=0.01;Audio.UpdateSoundBounds;
    Plan:=TFireworksPlan.Build(Audio,0);Require((Plan.Count=0) and (Plan.EndTime=0),'Silence generated fireworks');FreeAndNil(Plan);FreeAndNil(Audio);
    MakeAudio(0.5);Rejected:=False;
    try Plan:=TFireworksPlan.Build(Audio,0,FIREWORKS_DEFAULT_RICHNESS,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;
    Require(Rejected,'Fireworks cancellation failed');
    FreeAndNil(Audio);Audio:=TRhythmAudio.Create;Audio.Duration:=1;SetLength(Audio.PCM,RHYTHM_RATE*4);
    Player:=TRhythmPlayback.Create;Player.SetAudio(Audio);Require(Abs(Player.Duration-1)<1E-9,'Default playback duration changed');
    Player.SetAudio(Audio,2);Require(Abs(Player.Duration-3)<1E-9,'Preview tail was not added');
    Player.Seek(2.5);Require(Abs(Player.Position-2.5)<1E-9,'Cannot seek into the silent tail');
    Require(not Player.Playing and not Player.Paused,'Seeking a stopped player started playback');
    Require((Audio.Duration=1) and (Length(Audio.PCM)=RHYTHM_RATE*4),'Preview tail modified decoded audio');FreeAndNil(Player);
    ConfigureRhythmProduct('SYNC_RhythmBall','リズムボール',rsBall);Require(not SameFileName(SettingsPath,FireworksSettings),'Product settings are mixed');Require(SameFileName(CacheFolder,CommonCache),'Shared audio cache moved');
    Writeln('FireworksPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Player.Free;Image.Free;Renderer.Free;Loaded.Free;Again.Free;Plan.Free;Audio.Free;
end.
