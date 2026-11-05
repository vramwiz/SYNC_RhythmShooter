program BreakoutPlanSmoke;
{$APPTYPE CONSOLE}
// Native regression entry: geometry, legacy/cold restore and deterministic render.
uses
  RhythmBombPlan in '..\Source\BombAction\RhythmBombPlan.pas',
  RhythmBombScene in '..\Source\BombAction\RhythmBombScene.pas',
  Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Generics.Collections,System.Hash,System.IOUtils,System.JSON,Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmAudio,RhythmBreakoutPlan,RhythmBreakoutGeometry,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmSettings,RhythmScene,RhythmPaths,RhythmPreparedData,RhythmBreakoutCampaign;
var Audio,Meta:TRhythmAudio;Plan,Again:TBreakoutPlan;Ref,Bad:TRhythmPlanRef;Settings:TRhythmSettings;
  Renderer:TRhythmRenderer;Image:TBitmap;I,J,K,C:Integer;Gap,Duration,T:Double;P,Q:TBreakPoint;B:TBreakBlock;BossData:TBreakBoss;
  Id:TGUID;Path,Hash,Serialized:string;Info:TWin32FileAttributeData;Rejected:Boolean;Opacity:Double;
// 試験成果物は過去の検証記録を上書きせず、当該EXEの専用出力へ保存する。
function EvidencePath(const Name:string):string;
var Folder:string;
begin Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);Result:=TPath.Combine(Folder,Name);end;
procedure Need(Value:Boolean;const MessageText:string);begin if not Value then raise Exception.Create(MessageText);end;
procedure CheckLegacyNine;
var Root,Board,Score,CopyScore:TJSONObject;Boards:TJSONArray;OldRef:TRhythmPlanRef;OldAudio:TRhythmAudio;OldPlan:TBreakoutPlan;K:Integer;Pair:TJSONPair;
begin
  Root:=ReadPreparedData(Ref,rsBreakout,0);OldAudio:=nil;OldPlan:=nil;
  try
    OldRef:=Ref;OldRef.Version:=9;OldRef.Key:=THashSHA2.GetHashString('breakout-v9|'+Audio.Key+'|50|0');
    Pair:=Root.RemovePair('version');Pair.Free;Root.AddPair('version',TJSONNumber.Create(9));Pair:=Root.RemovePair('key');Pair.Free;Root.AddPair('key',OldRef.Key);
    Pair:=Root.RemovePair('bossPolicy');Pair.Free;Root.AddPair('bossPolicy','impact-density-v5');
    Boards:=Root.GetValue<TJSONArray>('boards');
    for K:=0 to Boards.Count-1 do begin Board:=Boards.Items[K] as TJSONObject;Score:=Board.GetValue<TJSONObject>('score');
      CopyScore:=Score.GetValue<TJSONObject>('baseScore').Clone as TJSONObject;Pair:=Board.RemovePair('score');Pair.Free;Board.AddPair('score',CopyScore);
    end;
    WritePreparedData(Root,OldRef);OldAudio:=TBreakoutPlan.LoadAudioMetadata(OldRef,Audio.Source,0);OldPlan:=TBreakoutPlan.Load(OldRef,OldAudio,0);
    Need((Length(OldAudio.PCM)=0) and (OldPlan.BossCount=Plan.BossCount) and (Abs(OldPlan.GoalTime-Plan.GoalTime)<1E-12),'Legacy nine cold restoration');
    for K:=0 to 99 do begin T:=OldPlan.EndTime*((K*37) mod 101)/101;P:=OldPlan.PositionAt(T);OldPlan.PositionAt(OldPlan.EndTime-T);Q:=OldPlan.PositionAt(T);Need((P.X=Q.X) and (P.Y=Q.Y),'Legacy nine random seek');end;
    Writeln('legacy9 cold: blocks=',OldPlan.Count,' bosses=',OldPlan.BossCount);
  finally OldPlan.Free;OldAudio.Free;Root.Free;end;
end;
procedure SaveFrame(const Name:string;Time:Double);
var PNG:TPngImage;
begin
  Image.SetSize(1280,720);Renderer.Render(Image,Meta,Time,0);PNG:=TPngImage.Create;
  try PNG.Assign(Image);PNG.SaveToFile(EvidencePath('Breakout.'+Name+'.png'));finally PNG.Free;end;
end;
procedure SaveShowFrames;
var Root,Score,Room:TJSONObject;Boards,Rooms,Charges:TJSONArray;
begin
  Root:=ReadPreparedData(Ref,rsBreakout,0);
  try
    TFile.WriteAllText(EvidencePath('Breakout.campaign-'+IntToStr(C)+'.json'),Root.ToJSON,TEncoding.UTF8);
    Boards:=Root.GetValue<TJSONArray>('boards');Score:=(Boards.Items[0] as TJSONObject).GetValue<TJSONObject>('score');
    Rooms:=Score.GetValue<TJSONArray>('rooms');Charges:=Score.GetValue<TJSONArray>('charges');
    Writeln('case ',C,': blocks=',Plan.Count,' reflections=',Plan.ReflectionCount,' rooms=',Rooms.Count,' charges=',Charges.Count,' extras=',Plan.ExtraCount,' bosses=',Plan.BossCount);
    if C=0 then begin
      Need((Rooms.Count>=3) and (Charges.Count>=2),'Rush/pierce features missing');
      Room:=Rooms.Items[0] as TJSONObject;SaveFrame('rush',(Room.GetValue<Double>('first')+Room.GetValue<Double>('last'))/2);
      Room:=Charges.Items[0] as TJSONObject;SaveFrame('pierce',(Room.GetValue<Double>('first')+Room.GetValue<Double>('last'))/2);
      SaveFrame('start',0.1);SaveFrame('exit',Plan.ExitStart+0.55);
    end;
    if C=7 then begin SaveFrame('preboss',Plan.Campaign.Boss(0).Start-1.25);SaveFrame('boss',Plan.Campaign.Boss(0).Start+6);end;
  finally Root.Free;end;
end;
procedure CheckLegacyEmpty;
var Root:TJSONObject;OldRef:TRhythmPlanRef;OldAudio:TRhythmAudio;OldPlan:TBreakoutPlan;Name:string;
begin
  OldRef:=NewPlanRef(Audio.Key,50,0,rsBreakout);OldRef.Version:=1;OldRef.SourceRevision:=Audio.SourceRevision;
  OldRef.Key:=THashSHA2.GetHashString('breakout-v1|'+Audio.Key+'|50|0');
  Root:=TJSONObject.Create;OldAudio:=nil;OldPlan:=nil;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));Root.AddPair('style','breakout');Root.AddPair('version',TJSONNumber.Create(1));
    Root.AddPair('key',OldRef.Key);Root.AddPair('source',OldRef.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(50));Root.AddPair('direction',TJSONNumber.Create(0));
    AddPreparedAudio(Root,Audio);Root.AddPair('launch',TJSONNumber.Create(0));Root.AddPair('goal',TJSONNumber.Create(0));Root.AddPair('end',TJSONNumber.Create(Audio.Duration));
    Root.AddPair('speed',TJSONNumber.Create(0));Root.AddPair('attempts',TJSONNumber.Create(0));
    for Name in TArray<string>.Create('candidates','blocks','segments','paddles') do Root.AddPair(Name,TJSONArray.Create);
    WritePreparedData(Root,OldRef);OldAudio:=TBreakoutPlan.LoadAudioMetadata(OldRef,Audio.Source,0);OldPlan:=TBreakoutPlan.Load(OldRef,OldAudio,0);
    Need((OldPlan.Count=0) and (Length(OldAudio.PCM)=0) and (OldPlan.EndTime=Audio.Duration),'Legacy version-one restoration');Need(OldPlan.PaddleHalf=BREAK_PADDLE_HALF,'Legacy paddle width');
  finally OldPlan.Free;OldAudio.Free;Root.Free;end;
end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;finally M.Free;end;end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Again:=nil;Renderer:=nil;Image:=nil;
  try
    ConfigureRhythmProduct('SYNC_RhythmBreakout','リズムブロック崩し',rsBreakout);
    Need((Ord(rsBreakout)=4) and (Ord(rsRunner)=3) and (StylePlanVersion(rsShooting)=1) and (StylePlanVersion(rsBall)=6) and
      (StylePlanVersion(rsFireworks)=3) and (CompatiblePlanVersion(rsRunner,6)) and CompatiblePlanVersion(rsBall,4) and CompatiblePlanVersion(rsRunner,1),'Old style contract changed');
    Need((StylePlanVersion(rsBreakout)=10) and CompatiblePlanVersion(rsBreakout,1) and CompatiblePlanVersion(rsBreakout,2) and CompatiblePlanVersion(rsBreakout,3) and CompatiblePlanVersion(rsBreakout,4) and CompatiblePlanVersion(rsBreakout,5) and CompatiblePlanVersion(rsBreakout,6) and CompatiblePlanVersion(rsBreakout,7) and CompatiblePlanVersion(rsBreakout,8) and CompatiblePlanVersion(rsBreakout,9),'Breakout legacy compatibility');
    Need(TRhythmSettings.Defaults.Style=rsBreakout,'New product default');
    Need(TRhythmSettings.TryJSON('{"schema":1,"music":"old.wav"}',Settings) and (Settings.Style=rsShooting),'Old JSON default');
    for C:=0 to 7 do begin
      Duration:=64;Gap:=0.18;case C of 1:begin Duration:=180;Gap:=0.5;end;2:begin Duration:=95;Gap:=11;end;
        3:begin Duration:=0.5;Gap:=0.18;end;4:begin Duration:=1800;Gap:=0.43;end;5:Duration:=2;6:Duration:=1;7:begin Duration:=90;Gap:=0.18;end;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=Duration;Audio.SoundEnd:=Duration;Audio.Sensitivity:=50;
      if (C<5) or (C=7) then begin
        SetLength(Audio.Hits,Floor((Duration-0.05)/Gap)+1);
        for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.05+I*Gap;Audio.Hits[I].Strength:=0.5+0.5*(I mod 4)/3;end;
      end else if C=6 then begin SetLength(Audio.Hits,1);Audio.Hits[0].Time:=0;Audio.Hits[0].Strength:=1;end;
      if C=7 then begin
        SetLength(Audio.Envelope,9000);for I:=0 to High(Audio.Envelope) do
          if ((I>=2000) and (I<3200)) or ((I>=6000) and (I<7200)) then Audio.Envelope[I]:=0.75 else Audio.Envelope[I]:=0.03125;
        Audio.UpdateSoundBounds;
      end;
      CreateGUID(Id);Path:=TPath.Combine(CacheFolder,GUIDToString(Id)+'.breakout-test');TFile.WriteAllText(Path,'test-source',TEncoding.UTF8);
      Audio.Source:=Path;Audio.Key:=THashSHA2.GetHashString(GUIDToString(Id));Need(GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Info),'source stamp');
      Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
      if C=5 then CheckLegacyEmpty;
      Plan:=TBreakoutPlan.Build(Audio);Again:=TBreakoutPlan.Build(Audio);
      Need((Plan.Count=Again.Count) and (Plan.Attempts<=288),'bounded deterministic adoption');
      if C=0 then Need(Plan.Count>=60,'Dense song still has a sparse field');
      if C=1 then Need(Plan.Count>=80,'Normal song still has a sparse field');
      if C=4 then Need(Plan.Count>=100,'Long song lost the descending grid');
      Need(Plan.ItemCount=0,'Old item multiball overlaps boss stages');
      if C=7 then begin
        Need((Plan.BossCount>=2) and (Plan.ExtraCount>=48),'Prepared boss stages missing');
        for J:=0 to Plan.BossCount-1 do begin
          BossData:=Plan.Campaign.Boss(J);Need(BossData.Kill-BossData.Start>=16,'Boss duration was not extended');Need(BossData.Kill<BossData.Quiet,'Defeat happened after quiet boundary');
          Need((Plan.Campaign.HealthAt(J,BossData.Kill-1E-6)>0) and (Plan.Campaign.HealthAt(J,BossData.Kill)=0),'Boss HP does not match final impact');
          for K:=0 to Plan.Count-1 do if Plan.BlockVisible(K,BossData.Start) then Need(Plan.Block[K].Time<=BossData.Start,'Live blocks under boss');
        end;
      end else Need(Plan.BossCount=0,'Unknown peak forced a boss');
      if C in [0,1] then Need((Plan.ReflectionCount>0) and (Plan.AuxiliaryCount=0) and (Plan.CatchCount=0),'Normal reflections are not all scored');
      if C=2 then Need((Plan.AuxiliaryCount>0) or (Plan.CatchCount>0),'Sparse policy did not use auxiliary reflections or catching');
      if (Plan.Count>0) and (Plan.LaunchTime>0) then begin
        P:=Plan.PositionAt(Max(0.0,Plan.LaunchTime-1E-8));Q:=Plan.PositionAt(Plan.LaunchTime);
        Need(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-6,'Launch snaps from paddle centre to edge');
      end;
      if (C<5) or (C=7) then begin Need(Plan.Count>0,'No final event');Need(Plan.GoalTime=Audio.Hits[High(Audio.Hits)].Time,'Last accent was shifted or omitted');end
      else Need(Plan.Count=0,'Silence/zero-time event creates impossible launch');
      for I:=0 to Plan.PrimaryCount-1 do begin
        B:=Plan.Block[I];P:=Plan.PositionAt(B.Time);
        if B.Source>=0 then begin
          Need(B.Time=Audio.Hits[B.Source].Time,'Changed an adopted audio time');
          Need(Abs(Hypot(Max(0.0,Max(B.Left-P.X,P.X-B.Right)),Max(0.0,Max(B.Top-P.Y,P.Y-B.Bottom)))-Plan.RadiusAt(B.Time))<1E-6,'Ball misses block face');
        end;
        Q:=Again.PositionAt(B.Time);Need((P.X=Q.X) and (P.Y=Q.Y),'Different reverse plan');
      end;
      for I:=Plan.PrimaryCount to Plan.Count-1 do begin
        B:=Plan.Block[I];Need((B.Source=-1) and (B.Time<Plan.GoalTime-4),'Additional blocks remain at final accent');
      end;
      Ref:=NewPlanRef(Audio.Key,50,0,rsBreakout);Ref.SourceRevision:=Audio.SourceRevision;Plan.Save(Ref,Audio);
      if C in [0,7] then CheckLegacyNine;
      Settings:=TRhythmSettings.Defaults;Settings.Music:=Path;Settings.BossFrequency:=Audio.BossFrequency;Settings.Plan:=Ref;Settings.Designs[8].Memo:='keep custom design';Serialized:=Settings.ToJSON;
      FreeAndNil(Again);FreeAndNil(Plan);FreeAndNil(Audio);Need(TRhythmSettings.TryJSON(Serialized,Settings),'Settings roundtrip');
      Meta:=TBreakoutPlan.LoadAudioMetadata(Settings.Plan,Settings.Music,0);Need(Length(Meta.PCM)=0,'Restoration requires PCM');
      Plan:=TBreakoutPlan.Load(Settings.Plan,Meta,0);Again:=TBreakoutPlan.Load(Settings.Plan,Meta,0);
      Need((Plan.ItemCount=Again.ItemCount) and (Plan.ExtraCount=Again.ExtraCount),'Multiball JSON restoration');
      for I:=0 to 99 do begin
        T:=Plan.EndTime*((I*37) mod 101)/101;P:=Plan.PositionAt(T);Again.PositionAt(Plan.EndTime-T);Q:=Again.PositionAt(T);
        Need((P.X=Q.X) and (P.Y=Q.Y) and (Plan.PaddleAt(T)=Again.PaddleAt(T)),'Random seek changed state');
        for J:=0 to Plan.ExtraCount-1 do if Plan.ExtraAt(J,T,P,Opacity) then begin
          Need(Again.ExtraAt(J,T,Q,Opacity) and (P.X=Q.X) and (P.Y=Q.Y),'Extra ball random seek changed state');
        end;
      end;
      Bad:=Ref;Bad.Digest:=StringOfChar('0',64);Rejected:=False;
      try FreeAndNil(Again);Again:=TBreakoutPlan.Load(Bad,Meta,0);except Rejected:=True;end;Need(Rejected,'Bad digest accepted');
      Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Renderer.ConfigureStyle(rsBreakout,Ref);Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;
      if C in [0,7] then SaveShowFrames;
      for J:=0 to 2 do begin
        case J of 0:Image.SetSize(1280,720);1:Image.SetSize(720,1280);else Image.SetSize(320,320);end;
        T:=Plan.GoalTime*0.6;Renderer.Render(Image,Meta,T,0);Hash:=ImageHash;Renderer.Render(Image,Meta,Plan.EndTime+2,1);Renderer.Render(Image,Meta,T,0);Need(Hash=ImageHash,'Render seek differs');
      end;
      Renderer.Render(Image,Meta,Plan.EndTime+1,0);Hash:=ImageHash;Renderer.Render(Image,Meta,Plan.EndTime+20,0);Need(Hash=ImageHash,'Moves forever after clear');
      FreeAndNil(Renderer);FreeAndNil(Image);FreeAndNil(Plan);FreeAndNil(Again);FreeAndNil(Meta);
    end;
    Audio:=TRhythmAudio.Create;Audio.Duration:=1;Rejected:=False;
    try Plan:=TBreakoutPlan.Build(Audio,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;Need(Rejected,'Cancellation ignored');
    Writeln('BreakoutPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Audio.Free;Meta.Free;Plan.Free;Again.Free;Renderer.Free;Image.Free;
end.
