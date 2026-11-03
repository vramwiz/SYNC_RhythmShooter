program FightingPlanSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.JSON,System.Hash,System.IOUtils,
  Vcl.Graphics,RhythmAudio,RhythmStyles,RhythmPlanRef,RhythmPreparedData,RhythmProduct,RhythmPaths,RhythmSettings,
  RhythmFightingPlan,RhythmFightingDuel,RhythmFightingScene,RhythmAnimation,RhythmImageBank;
var Audio,Meta:TRhythmAudio;Plan,Cold,BadPlan:TFightingPlan;D:TFightingDuel;Ref,Bad:TRhythmPlanRef;
  Image:TBitmap;Renderer:TAnimationRenderer;Scene:TFightingAnimation;Root,Other:TJSONObject;
  Source,Revision,Serialized,Expected,Folder:string;Stamp:TWin32FileAttributeData;
  C,I,J,N,Frequency,Rear,HeroHits,EnemyHits,Finishes,SeekChecks,CameraChecks:Integer;
  Duration,Gap,T,CX,CY,Zoom,PreviousHP,ScreenX,ScreenY:Double;
  H:TDuelHit;E:TDuelEnemy;S:TDuelSection;P,Q:TDuelPose;W:TDuelStrike;Rejected:Boolean;
  Styles:set of 0..2;State,Loaded:TRhythmSettings;
procedure Need(V:Boolean;const M:string);begin if not V then raise Exception.Create(M);end;
function BitmapHash:string;
var M:TMemoryStream;Bytes:TBytes;Hash:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;if Length(Bytes)>0 then M.ReadBuffer(Bytes[0],Length(Bytes));Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;finally M.Free;end;end;
procedure InFrame(X,Y:Double);
begin ScreenX:=(X-CX)*Zoom+0.8;ScreenY:=(Y-CY)*Zoom+0.66;Need((ScreenX>=0) and (ScreenX<=1.6) and (ScreenY>=0) and (ScreenY<=1),'Camera cuts a body/weapon/contact');Inc(CameraChecks);end;
procedure LegacyV1;
var R:TRhythmPlanRef;A:TJSONArray;J:TJSONObject;
begin
  Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Key:=THashSHA2.GetHashString('legacy-fighting');Audio.Duration:=1;Audio.Sensitivity:=50;Audio.SetBossFrequency(0);
  R:=NewPlanRef(Audio.Key,50,0,rsFighting,1);R.Version:=1;R.SourceRevision:=Revision;R.Key:=THashSHA2.GetHashString('fighting-v1|'+Audio.Key+'|50|0|variant=1');
  Root:=TJSONObject.Create;
  try Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','fighting');Root.AddPair('version',TJSONNumber.Create(1));Root.AddPair('key',R.Key);Root.AddPair('source',R.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(50));Root.AddPair('direction',TJSONNumber.Create(0));AddPreparedAudio(Root,Audio);
    Root.AddPair('policy','contact-crowd-v1');Root.AddPair('goal',TJSONNumber.Create(0));Root.AddPair('end',TJSONNumber.Create(0));Root.AddPair('entry',TJSONNumber.Create(0));Root.AddPair('frequency',TJSONNumber.Create(0));Root.AddPair('excluded',TJSONNumber.Create(0));
    Root.AddPair('events',TJSONArray.Create);Root.AddPair('hits',TJSONArray.Create);Root.AddPair('enemies',TJSONArray.Create);Root.AddPair('bosses',TJSONArray.Create);Root.AddPair('volleys',TJSONArray.Create);Root.AddPair('focus',TJSONArray.Create);
    A:=TJSONArray.Create;Root.AddPair('stages',A);J:=TJSONObject.Create;A.AddElement(J);J.AddPair('t',TJSONNumber.Create(0));J.AddPair('theme',TJSONNumber.Create(0));WritePreparedData(Root,R);
  finally Root.Free;Root:=nil;end;
  Meta:=TFightingPlan.LoadAudioMetadata(R,Source,0);Cold:=TFightingPlan.Load(R,Meta,0);Need((Cold.RecipeVersion=1) and (Cold.Action=nil) and (Length(Meta.PCM)=0),'Legacy v1 reader');FreeAndNil(Cold);FreeAndNil(Meta);FreeAndNil(Audio);
end;
begin
  try
    ConfigureRhythmProduct('SYNC_RhythmFighting','Fighting v2 native',rsFighting);Need((StylePlanVersion(rsFighting)=2) and CompatiblePlanVersion(rsFighting,1),'Version compatibility');Need(CompatiblePlanVersion(rsRunner,6),'Runner changed');
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'DuelEvidence');ForceDirectories(Folder);Source:=TPath.Combine(Folder,'source.identity');TFile.WriteAllText(Source,'Synthetic native fighting source; no playback',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stat');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);LegacyV1;
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(960,600);Styles:=[];
    for C:=0 to 13 do begin
      Duration:=96;Gap:=0.18;Frequency:=50;case C of 0:begin Duration:=0.1;Gap:=0.02;end;1:Duration:=1;2:begin Duration:=8;Gap:=0.7;end;3:Duration:=32;5:Duration:=180;6:begin Duration:=180;Frequency:=0;end;7:begin Duration:=3000;Gap:=0.16;end;8:begin Duration:=16;Gap:=0.008;end;9:Gap:=1.1;10:begin Duration:=420;Frequency:=100;Gap:=0.20;end;11:begin Duration:=16;Gap:=0.09;end;12:begin Duration:=96;Frequency:=100;Gap:=0.001;end;end;
      Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Key:=THashSHA2.GetHashString('duel-native-'+IntToStr(C));Audio.Duration:=Duration;Audio.Sensitivity:=50;Audio.SetBossFrequency(Frequency);SetLength(Audio.Envelope,Ceil(Duration*100));if C<>1 then for I:=0 to High(Audio.Envelope) do Audio.Envelope[I]:=0.5;
      SetLength(Audio.Hits,100000);N:=0;T:=0.005;if C<>1 then while (T<Duration-0.005) and (N<100000) do begin Audio.Hits[N].Time:=T;Audio.Hits[N].Strength:=0.25+(N mod 6)*0.15;Inc(N);if (C=13) and (N mod 5=0) then begin Audio.Hits[N]:=Audio.Hits[N-1];Audio.Hits[N].Strength:=1;Inc(N);end;T:=T+Gap;end;SetLength(Audio.Hits,N);Audio.UpdateSoundBounds;
      Plan:=TFightingPlan.Build(Audio);D:=Plan.Action;Need(D<>nil,'v2 plan missing');D.Validate;Need(Length(D.Hits)=N,'Source events discarded');if Frequency=0 then Need(D.BossCount=0,'Frequency zero');
      for I:=0 to High(D.Enemies) do begin E:=D.Enemies[I];if E.Side<0 then begin Inc(Rear);Need(E.Speed>DUEL_SPEED,'Rear chaser too slow');T:=Max(E.Spawn,E.Ready-0.5);if E.Ready-T>0.01 then begin P:=D.EnemyAt(I,T);Q:=D.EnemyAt(I,E.Ready);Need(Q.X-D.WorldAt(E.Ready)>P.X-D.WorldAt(T),'Rear chaser never catches');end;end;end;
      for I:=0 to High(D.Hits) do begin H:=D.Hits[I];Need(H.Time=Audio.Hits[H.Source].Time,'Audio clock changed');
        if H.Role in [1,5] then begin Need(D.HeroStrike(H.Time,W),'Hero strike absent');Need(Hypot(W.Tip.X-H.X,W.Tip.Y-H.Y)<1E-7,'Hero strike contact');Need(Hypot(W.Tip.X-W.Grip.X,W.Tip.Y-W.Grip.Y)<0.22,'Hero limb reach');Inc(HeroHits);end;
        if H.Role in [2,3,4] then begin Need(D.EnemyStrike(H.Time,W),'Enemy strike absent');Need(Hypot(W.Tip.X-H.X,W.Tip.Y-H.Y)<1E-7,'Enemy strike contact');
          if W.StraightArm then begin Need(Hypot(W.Hand.X-W.Grip.X,W.Hand.Y-W.Grip.Y)<0.22,'Boss arm overextends');for J:=0 to 63 do begin T:=H.Time-0.175+J*0.005;if not D.EnemyStrike(T,W) then Continue;if W.Hit<>I then Continue;Q:=D.BossAt(T);Need(Hypot(W.Grip.X-(Q.X+W.Side*0.020*Q.Scale),W.Grip.Y-(Q.Y-0.106*Q.Scale))<1E-7,'Arm detached from shoulder');Need(Hypot(W.Hand.X-W.Grip.X,W.Hand.Y-W.Grip.Y)<0.22,'Swing arm overextends');D.CameraAt(T,CX,CY,Zoom);InFrame(W.Grip.X,W.Grip.Y);InFrame(W.Hand.X,W.Hand.Y);InFrame(W.Tip.X,W.Tip.Y);end;end;
          if D.Sections[H.Section].Mode=0 then if D.Enemies[H.Enemy].Kill<H.Time+0.1 then begin Need(not D.EnemyStrike(D.Enemies[H.Enemy].Kill+0.0001,W) or (W.Hit<>I),'Normal enemy attacks after KO');end;Inc(EnemyHits);end;
      end;
      for I:=0 to High(D.Sections) do begin S:=D.Sections[I];if S.Mode=0 then begin if S.Finish-S.Start>1 then Need(D.WorldAt(S.Start+1)>D.WorldAt(S.Start)+0.29,'Normal stage does not advance right');Continue;end;Include(Styles,S.Style);Need(Abs(D.WorldAt(S.Ready)-D.WorldAt(S.Kill))<1E-7,'Boss stage scrolls');N:=0;PreviousHP:=S.HP;
        for J:=0 to High(D.Hits) do if D.Hits[J].Section=I then begin H:=D.Hits[J];Need(H.HP<=PreviousHP,'Boss HP reverses');PreviousHP:=H.HP;if H.Role=5 then begin Inc(N);Inc(Finishes);Need(H.Time=S.Kill,'KO not on source');end;if H.Time>S.Kill then Need(H.Role=0,'Boss attacks after KO');end;Need((N=1) and (PreviousHP=0),'Missing final KO');
        T:=S.Start;while T<S.Finish do begin D.CameraAt(T,CX,CY,Zoom);P:=D.HeroAt(T);Q:=D.BossAt(T);InFrame(P.X-0.075,P.Y-0.22);InFrame(P.X+0.075,P.Y+0.035);InFrame(Q.X-0.1,Q.Y-0.29);InFrame(Q.X+0.1,Q.Y+0.1);if D.HeroStrike(T,W) then begin InFrame(W.Grip.X,W.Grip.Y);InFrame(W.Tip.X,W.Tip.Y);end;if D.EnemyStrike(T,W) then begin InFrame(W.Grip.X,W.Grip.Y);if W.StraightArm then InFrame(W.Hand.X,W.Hand.Y);InFrame(W.Tip.X,W.Tip.Y);end;T:=T+0.12;end;
      end;
      Ref:=NewPlanRef(Audio.Key,50,0,rsFighting,Frequency+1);Ref.SourceRevision:=Revision;Plan.Save(Ref,Audio);State:=TRhythmSettings.Defaults;State.Style:=rsFighting;State.Music:=Source;State.Plan:=Ref;State.BossFrequency:=Frequency;Need(TRhythmSettings.TryJSON(State.ToJSON,Loaded) and (Loaded.Plan.Key=Ref.Key),'Settings v2 reference');Root:=D.ToJSON;try Serialized:=Root.ToJSON;finally Root.Free;Root:=nil;end;
      Meta:=TFightingPlan.LoadAudioMetadata(Ref,Source,0);Need((Length(Meta.PCM)=0) and (Length(Meta.Envelope)=0),'Cold restore needs PCM');Cold:=TFightingPlan.Load(Ref,Meta,0);Other:=Cold.Action.ToJSON;try Need(Other.ToJSON=Serialized,'Cold score changes');finally Other.Free;end;
      for I:=0 to 63 do begin T:=D.EndTime*((I*37) mod 67)/67;P:=D.HeroAt(T);Q:=Cold.Action.HeroAt(T);Need(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-9,'Random seek changes hero');Need(Abs(Plan.HeroAt(T).X-P.X)<1E-9,'Plan API does not forward v2');Inc(SeekChecks);end;
      Bad:=Ref;Bad.Digest:=StringOfChar('0',64);Rejected:=False;try BadPlan:=TFightingPlan.Load(Bad,Meta,0);except Rejected:=True;end;FreeAndNil(BadPlan);Need(Rejected,'Bad digest accepted');
      if C in [3,5,10] then begin Scene:=TFightingAnimation.Create;Scene.Audio:=Meta;Scene.SetReference(Ref);Renderer:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));Renderer.UseD2D:=False;Image.SetSize(720,1280);Renderer.Render(Image,D.Goal*0.5,0);Image.SetSize(960,600);T:=D.Goal*0.6;Renderer.Render(Image,T,0);Expected:=BitmapHash;Renderer.Render(Image,D.EndTime,0);Renderer.Render(Image,T,0);Need((Scene.Notice='') and (BitmapHash=Expected),'Preview seek/restore mismatch');FreeAndNil(Renderer);end;
      FreeAndNil(Cold);FreeAndNil(Meta);FreeAndNil(Plan);FreeAndNil(Audio);
    end;
    Need((Rear>0) and (HeroHits>0) and (EnemyHits>0) and (Finishes>0) and (Styles=[0,1,2]),'Coverage incomplete');Writeln(Format('Fighting v2 PASS rear=%d heroContacts=%d enemyContacts=%d KO=%d seeks=%d cameraPoints=%d',[Rear,HeroHits,EnemyHits,Finishes,SeekChecks,CameraChecks]));
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Renderer.Free;Image.Free;BadPlan.Free;Cold.Free;Plan.Free;Meta.Free;Audio.Free;
end.
