program BallPlanSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.JSON,System.IOUtils,Vcl.Graphics,
  RhythmAudio,RhythmBallGeometry,RhythmBallPlan,RhythmPlanRef,RhythmStyles,RhythmSettings,RhythmProduct,RhythmScene,RhythmPaths;
var Audio:TRhythmAudio;Plan,Again,Loaded:TRhythmBallPlan;Ref,BadRef:TRhythmPlanRef;P,Q,N:TBallPoint;
  I,J,CaseIndex,Direction,Backend,Moving,Breaking,Bumpers:Integer;Gap:Double;State,Restored:TRhythmSettings;
  Renderer:TRhythmRenderer;Image:TBitmap;Hash:string;Rejected:Boolean;O:TBallObstacle;C:TBallContact;Pulse:TBallPulse;BallSettingsPath,SharedCachePath:string;
procedure Require(Value:Boolean;const Text:string);
begin if not Value then raise Exception.Create(Text);end;
function ImageHash:string;
var S:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin S:=TMemoryStream.Create;try Image.SaveToStream(S);SetLength(Bytes,S.Size);S.Position:=0;S.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;finally S.Free;end;end;
procedure MakeAudio(Spacing:Double);
var K:Integer;
begin
  Audio:=TRhythmAudio.Create;Audio.Key:=StringOfChar('a',64);Audio.Sensitivity:=50;Audio.Duration:=22;
  SetLength(Audio.Envelope,2200);for K:=0 to 1999 do Audio.Envelope[K]:=0.5;
  SetLength(Audio.Hits,Floor(19.5/Spacing)+1);
  for K:=0 to High(Audio.Hits) do begin Audio.Hits[K].Time:=0.5+K*Spacing;Audio.Hits[K].Strength:=0.45+(K mod 5)*0.125;Audio.Hits[K].Lane:=-10;Audio.Hits[K].Flight:=100;end;
  Audio.UpdateSoundBounds;
end;
// A disk-only round trip, deliberately without any PCM file or live editor.
procedure CheckColdRestore;
var SourceFile,StateFile,PlanFile,LegacyFile,PlanJSON,LegacyEvents,IndexJSON,FirstHash,Failure:string;
  Id:TGUID;Info:TWin32FileAttributeData;N:Integer;J,Item,Header:TJSONObject;Events,Wave:TJSONArray;
  Meta:TRhythmAudio;Saved,Cold:TRhythmSettings;ColdRef,LegacyRef:TRhythmPlanRef;Rejected:Boolean;
begin
  Meta:=nil;CreateGUID(Id);
  SourceFile:=TPath.Combine(CacheFolder,GUIDToString(Id)+'-source-identity.dat');
  StateFile:=SourceFile+'.settings.json';
  TFile.WriteAllText(SourceFile,'cold restore fixture '+GUIDToString(Id),TEncoding.UTF8);
  MakeAudio(0.5);Audio.Source:=SourceFile;Audio.Key:=THashSHA2.GetHashString(GUIDToString(Id));
  if not GetFileAttributesEx(PChar(SourceFile),GetFileExInfoStandard,@Info) then RaiseLastOSError;
  Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+
    IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
  for N:=0 to High(Audio.Hits) do Audio.Hits[N].Lane:=0.5;
  J:=TJSONObject.Create;
  try
    J.AddPair('analysisVersion',TJSONNumber.Create(2));J.AddPair('sourceSHA256',Audio.Key);
    J.AddPair('sensitivity',TJSONNumber.Create(Audio.Sensitivity));J.AddPair('duration',TJSONNumber.Create(Audio.Duration));
    Wave:=TJSONArray.Create;J.AddPair('envelope',Wave);for N:=0 to High(Audio.Envelope) do Wave.Add(Audio.Envelope[N]);
    Events:=TJSONArray.Create;J.AddPair('hits',Events);
    for N:=0 to High(Audio.Hits) do begin
      Item:=TJSONObject.Create;Events.AddElement(Item);Item.AddPair('time',TJSONNumber.Create(Audio.Hits[N].Time));
      Item.AddPair('strength',TJSONNumber.Create(Audio.Hits[N].Strength));Item.AddPair('lane',TJSONNumber.Create(0.5));
    end;LegacyEvents:=J.ToJSON;
  finally J.Free;end;
  J:=TJSONObject.Create;
  try J.AddPair('sourceSHA256',Audio.Key);J.AddPair('sourceStamp',Audio.SourceRevision);IndexJSON:=J.ToJSON;finally J.Free;end;
  Plan:=TRhythmBallPlan.Build(Audio);ColdRef:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsBall);ColdRef.SourceRevision:=Audio.SourceRevision;Plan.Save(ColdRef);
  Saved:=TRhythmSettings.Defaults;Saved.Style:=rsBall;Saved.Music:=SourceFile;Saved.Plan:=ColdRef;Saved.Designs[8].Memo:='retain per-object memo';
  TFile.WriteAllText(StateFile,Saved.ToJSON,TEncoding.UTF8);
  Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Renderer.ConfigureStyle(rsBall,ColdRef);
  Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);Renderer.Render(Image,Audio,2.75,0);FirstHash:=ImageHash;
  FreeAndNil(Renderer);FreeAndNil(Plan);FreeAndNil(Audio); // No in-memory preparation survives.
  try
    Require(TRhythmSettings.TryJSON(TFile.ReadAllText(StateFile,TEncoding.UTF8),Cold),'Cannot reopen saved object JSON');
    Require((Cold.Style=rsBall) and (Cold.Plan.Key=ColdRef.Key) and (Cold.Plan.SourceRevision=Saved.Plan.SourceRevision) and (Cold.Designs[8].Memo=Saved.Designs[8].Memo),'Cold settings lost fields');
    Meta:=TRhythmBallPlan.LoadAudioMetadata(Cold.Plan,Cold.Music,Cold.Direction);
    Require((Length(Meta.PCM)=0) and (Meta.Key=Cold.Plan.SourceKey),'Cold restoration requires PCM');
    Plan:=TRhythmBallPlan.Load(Cold.Plan,Meta,Cold.Direction);
    Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Renderer.ConfigureStyle(Cold.Style,Cold.Plan);
    Renderer.Render(Image,Meta,2.75,Cold.Direction);Require(ImageHash=FirstHash,'New renderer does not restore the saved plan');
    FreeAndNil(Renderer);FreeAndNil(Plan);FreeAndNil(Meta);
    PlanFile:=TPath.Combine(PlanFolder,ColdRef.Key+'.json');PlanJSON:=TFile.ReadAllText(PlanFile,TEncoding.UTF8);
    // Legacy v4 has no audio header. Its event metadata remains sufficient even
    // if the unrelated PCM cache was never created or has been removed.
    TFile.WriteAllText(TPath.Combine(CacheFolder,ColdRef.SourceKey+'-s50-events-v1.json'),LegacyEvents,TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(CacheFolder,THashSHA2.GetHashString(LowerCase(ExpandFileName(SourceFile)))+'-s50-index.json'),IndexJSON,TEncoding.UTF8);
    Meta:=LoadCachedRhythmAudio(SourceFile,50,True,Failure);Require(Meta=nil,'Fixture unexpectedly contains PCM');
    LegacyRef:=Saved.Plan;LegacyRef.Version:=4;LegacyRef.SourceRevision:='';
    LegacyRef.Key:=THashSHA2.GetHashString('ball-v4|'+LegacyRef.SourceKey+'|50|0');
    LegacyFile:=TPath.Combine(PlanFolder,LegacyRef.Key+'.json');
    J:=TJSONObject.ParseJSONValue(PlanJSON) as TJSONObject;
    try
      J.RemovePair('audio').Free;J.RemovePair('version').Free;J.RemovePair('key').Free;
      J.AddPair('version',TJSONNumber.Create(4));J.AddPair('key',LegacyRef.Key);
      TFile.WriteAllText(LegacyFile,J.ToJSON,TEncoding.UTF8);
    finally J.Free;end;
    LegacyRef.Digest:=THashSHA2.GetHashStringFromFile(LegacyFile);
    Require(LegacyRef.Matches(LegacyRef.SourceKey,50,0,rsBall),'Legacy v4 key is not preserved');
    Saved.Plan:=LegacyRef;Require(TRhythmSettings.TryJSON(Saved.ToJSON,Cold) and (Cold.Plan.Key=LegacyRef.Key),'Existing v4 object was discarded');
    Saved.Plan:=ColdRef;
    Meta:=TRhythmBallPlan.LoadAudioMetadata(LegacyRef,SourceFile,0);Plan:=TRhythmBallPlan.Load(LegacyRef,Meta,0);
    Require((Length(Meta.PCM)=0) and (Plan.ObstacleCount>0),'Legacy restoration depends on PCM');
    FreeAndNil(Plan);FreeAndNil(Meta);
    // A correct digest must not make an invalid metadata header acceptable.
    J:=TJSONObject.ParseJSONValue(PlanJSON) as TJSONObject;
    try
      Header:=J.GetValue<TJSONObject>('audio');Header.RemovePair('duration').Free;Header.AddPair('duration',TJSONNumber.Create(-1));
      TFile.WriteAllText(PlanFile,J.ToJSON,TEncoding.UTF8);
    finally J.Free;end;
    ColdRef.Digest:=THashSHA2.GetHashStringFromFile(PlanFile);Rejected:=False;
    try Meta:=TRhythmBallPlan.LoadAudioMetadata(ColdRef,SourceFile,0);except Rejected:=True;end;
    Require(Rejected,'Invalid metadata bypassed validation');FreeAndNil(Meta);
    TFile.WriteAllText(PlanFile,PlanJSON,TEncoding.UTF8);ColdRef:=Saved.Plan;
    TFile.AppendAllText(SourceFile,' changed',TEncoding.UTF8);Rejected:=False;
    try Meta:=TRhythmBallPlan.LoadAudioMetadata(ColdRef,SourceFile,0);except Rejected:=True;end;
    Require(Rejected,'Changed music identity reused a stale prepared plan');
  finally Meta.Free;FreeAndNil(Renderer);FreeAndNil(Plan);FreeAndNil(Image);end;
end;

begin
  Audio:=nil;Plan:=nil;Again:=nil;Loaded:=nil;Renderer:=nil;Image:=nil;
  try
    ConfigureRhythmProduct('SYNC_RhythmBall','リズムボール',rsBall);
    Require(TRhythmSettings.Defaults.Style=rsBall,'Ball default missing');
    Require(StylePlanVersion(rsBall)=5,'Pinball plan version missing');Require(StylePlanVersion(rsShooting)=1,'Shooting plan was invalidated');
    Require(TRhythmSettings.TryJSON('{"schema":1,"music":"old.wav","direction":1,"sensitivity":72}',State) and (State.Style=rsShooting),'Old JSON no longer resolves to shooting');
    for CaseIndex:=0 to 3 do begin
      case CaseIndex of 0,3:Gap:=0.18;1:Gap:=0.5;else Gap:=3.5;end;MakeAudio(Gap);
      if CaseIndex=3 then begin
        Audio.Hits[0].Time:=0;Audio.Hits[1].Time:=0;Audio.Hits[2].Time:=0.005;Audio.Hits[3].Time:=0.010;
        Audio.Hits[4].Time:=0.06;Audio.Hits[5].Time:=0.09;Audio.Hits[6].Time:=0.18;Audio.Hits[7].Time:=0.20;
      end;
      Plan:=TRhythmBallPlan.Build(Audio);Again:=TRhythmBallPlan.Build(Audio);
      Require(Plan.PulseCount=Length(Audio.Hits),'Dense accents were discarded');
      for I:=0 to Plan.PulseCount-1 do begin
        Pulse:=Plan.Pulse[I];Require(Pulse.Time=Audio.Hits[I].Time,'Pulse time drifted');
        Require(Pulse.Strength=Audio.Hits[I].Strength,'Pulse strength changed');
        Require((Pulse.ContactIndex>=1) and (Pulse.ContactIndex<Plan.Count),'Pulse has no real collision');
        Require((Pulse.Time>=Plan.Contact[Pulse.ContactIndex].Time) and (Pulse.Time<=Plan.Contact[Pulse.ContactIndex].Time+0.721),'Resonance is too far from impact');
      end;
      if (CaseIndex=0) or (CaseIndex=3) then Require(Plan.PulseCount>Plan.ObstacleCount,'Dense grouping was not used');
      Require(Plan.ObstacleCount=Plan.Count-1,'A contact has no obstacle');Moving:=0;Breaking:=0;Bumpers:=0;
      for I:=1 to Plan.Count-1 do begin
        C:=Plan.Contact[I];O:=Plan.Obstacle[I-1];Require(Plan.Pulse[Plan.PulseBefore(C.Time)].Time=C.Time,'Primary collision lost its audio event');
        P:=Plan.PositionAt(C.Time);Q:=Again.PositionAt(C.Time);Require(BallLength(BallSub(P,Q))<1E-12,'Plan is not deterministic');
        Require(Abs(BallLength(BallSub(P,ObstaclePoint(O,C.Time)))-O.Radius-BALL_RADIUS)<1E-8,'Ball does not touch the visible obstacle');
        Require(BallDot(C.Incoming,C.Normal)<-0.5,'Incoming ball is behind the obstacle');
        N:=BallSub(C.Incoming,BallScale(C.Normal,2*BallDot(C.Incoming,C.Normal)));
        Require(BallLength(BallSub(N,C.Outgoing))<1E-8,'Departure is not a reflection');
        Require(BallLength(BallSub(C.Incoming,Plan.Contact[I-1].Outgoing))<1E-8,'Flight bends after departure');
        if C.Time>Plan.Contact[I-1].Time then begin
          N:=BallUnit(BallSub(C.Position,Plan.Contact[I-1].Position));
          Require(BallLength(BallSub(N,C.Incoming))<1E-8,'Chord differs from the incoming direction');
          for J:=1 to 9 do begin
            P:=Plan.PositionAt(Plan.Contact[I-1].Time+(C.Time-Plan.Contact[I-1].Time)*J/10);
            Q:=BallMix(Plan.Contact[I-1].Position,C.Position,J/10);
            Require(BallLength(BallSub(P,Q))<1E-8,'Pinball flight is not a straight segment');
          end;
        end;
        P:=Plan.PositionAt(C.Time);
        Q:=Plan.PositionAt(C.Time-1E-7);Require(BallLength(BallSub(P,Q))<0.0001,'Contact arrival is discontinuous');
        Q:=Plan.PositionAt(C.Time+1E-7);Require(BallLength(BallSub(P,Q))<0.0001,'Contact departure is discontinuous');
        Require((O.Spawn<=Max(0.0,O.Hit-0.85)+1E-8) and (O.Arrive<=O.Hit),'Obstacle appeared without a lead-in');
        if O.Kind=boBreakable then Inc(Breaking) else Inc(Bumpers);
        if BallLength(BallSub(O.Origin,O.Center))>0.1 then Inc(Moving);
        for J:=1 to Plan.Count-1 do Require(FlightClearsObstacle(Plan.Flight[J],O),'Flight crosses an unhit obstacle');
        Require(FlightClearsObstacle(Plan.Tail,O),'Terminal departure crosses an obstacle');
      end;
      Require((Moving>0) and (Breaking>0) and (Bumpers>0),'Pinball obstacle variety missing');
      P:=Plan.PositionAt(Plan.EndTime);Q:=Plan.PositionAt(Plan.EndTime+100);Require(BallLength(BallSub(P,Q))<1E-12,'Ball moves after the end');
      Ref:=NewPlanRef(Audio.Key,50,0,rsBall);Plan.Save(Ref);Loaded:=TRhythmBallPlan.Load(Ref,Audio,0);
      Require((Loaded.Count=Plan.Count) and (Loaded.ObstacleCount=Plan.ObstacleCount) and (Loaded.PulseCount=Plan.PulseCount),'Plan save/load changed the board');
      for I:=0 to Plan.ObstacleCount-1 do begin
        Require(Loaded.Obstacle[I].Spawn=Plan.Obstacle[I].Spawn,'Spawn was not saved');
        Require(BallLength(BallSub(Loaded.Obstacle[I].Origin,Plan.Obstacle[I].Origin))<1E-12,'Moving origin was not saved');
      end;FreeAndNil(Loaded);
      State:=TRhythmSettings.Defaults;State.Music:='keep.wav';State.Style:=rsBall;State.Plan:=Ref;State.Designs[8].Memo:='keep shooting design';
      Require(TRhythmSettings.TryJSON(State.ToJSON,Restored) and (Restored.Style=rsBall) and (Restored.Plan.Digest=Ref.Digest) and (Restored.Designs[8].Memo=State.Designs[8].Memo),'Style, plan or shooting settings did not round trip');
      BadRef:=Ref;BadRef.Version:=3;State.Plan:=BadRef;
      Require(TRhythmSettings.TryJSON(State.ToJSON,Restored) and (Restored.Plan.Key='') and (Restored.Music=State.Music) and (Restored.Designs[8].Memo=State.Designs[8].Memo),'Old plan was not invalidated without losing settings');
      Require(not BadRef.Matches(Audio.Key,50,0,rsBall),'Old plan accepted');
      State.Plan:=Default(TRhythmPlanRef);
      Require(TRhythmSettings.TryJSON(State.ToJSON,Restored) and (Restored.Plan.Key='') and (Restored.Music=State.Music) and (Restored.Designs[8].Memo=State.Designs[8].Memo),'Pending settings cannot be saved without a plan');
      BadRef:=Ref;BadRef.Digest:=StringOfChar('0',64);Rejected:=False;
      try Loaded:=TRhythmBallPlan.Load(BadRef,Audio,0);except Rejected:=True;end;Require(Rejected,'Invalid plan digest accepted');FreeAndNil(Loaded);
      Require(AnimationPlanKey(Audio.Key,50,1,rsBall)<>Ref.Key,'Direction failed to invalidate the plan');
      Renderer:=TRhythmRenderer.Create;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);
      for Direction:=0 to 1 do begin
        Ref:=NewPlanRef(Audio.Key,50,Direction,rsBall);Plan.Save(Ref);Renderer.ConfigureStyle(rsBall,Ref);
        for Backend:=0 to 1 do begin
          Renderer.UseD2D:=Backend=1;Renderer.Render(Image,Audio,Audio.Hits[2].Time+0.05,Direction);Hash:=ImageHash;
          Renderer.Render(Image,Audio,Audio.Duration+10,Direction);Renderer.Render(Image,Audio,Audio.Hits[2].Time+0.05,Direction);
          Require(ImageHash=Hash,'Pinball rendering changed after terminal seek');
        end;
      end;
      FreeAndNil(Renderer);FreeAndNil(Image);FreeAndNil(Again);FreeAndNil(Plan);FreeAndNil(Audio);
    end;
    CheckColdRestore;
    Audio:=TRhythmAudio.Create;Audio.Key:=StringOfChar('b',64);Audio.Sensitivity:=50;Audio.Duration:=0.01;Audio.UpdateSoundBounds;
    Plan:=TRhythmBallPlan.Build(Audio);Require((Plan.Count=1) and (Plan.ObstacleCount=0) and (Plan.EndTime=0),'Silence created obstacles');FreeAndNil(Plan);FreeAndNil(Audio);
    MakeAudio(0.5);Rejected:=False;
    try Plan:=TRhythmBallPlan.Build(Audio,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;
    Require(Rejected,'Planning cancellation was ignored');
    BallSettingsPath:=SettingsPath;SharedCachePath:=CacheFolder;
    ConfigureRhythmProduct('SYNC_RhythmShooter','リズムシューティング',rsShooting);
    Require(not SameFileName(SettingsPath,BallSettingsPath),'Product settings paths are mixed');
    Require(SameFileName(CacheFolder,SharedCachePath),'Common audio cache was moved');
    Writeln('BallPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Image.Free;Renderer.Free;Loaded.Free;Again.Free;Plan.Free;Audio.Free;
end.
