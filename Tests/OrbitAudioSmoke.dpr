program OrbitAudioSmoke;
{$APPTYPE CONSOLE}
{$POINTERMATH ON}
uses RhythmSettings,RhythmPrepare,Winapi.Windows,System.Hash,RhythmGamePlan,RhythmPlanRef,RhythmStyles,RhythmProduct,System.SysUtils,System.Math,System.Classes,System.IOUtils,System.JSON,RhythmAudio,RhythmOrbitAudio;
const Values:array[0..10] of Integer=(-100,-75,-50,-25,-1,0,20,50,75,90,100);
var Audio,Snapshot:TRhythmAudio;Pool:TOrbitCandidatePool;Stats:TOrbitAudioStats;Samples:PSmallInt;
  C,I,J,K,F,Frames,Count,Prior,Checks,DenseGain,QuietExtra:Integer;X,T,Local,Spacing,PeakError:Double;Seed:Cardinal;
  Saved,Restored:TRhythmSettings;
  Worker:TRhythmPrepareThread;
  Plan,Cold:TGamePlan;Ref:TRhythmPlanRef;Meta:TRhythmAudio;Stamp:TWin32FileAttributeData;Source,Revision,PCMHash:string;
  Folder:string;Root,Row:TJSONObject;Rows,Counts:TJSONArray;
procedure Need(OK:Boolean;const S:string);
begin if not OK then raise Exception.Create(S);end;
function BytesHash(const Bytes:TBytes):string;
var H:THashSHA2;
begin H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;end;
function Rand:Double;
begin Seed:=Cardinal((UInt64(Seed)*1664525+1013904223) and $FFFFFFFF);Result:=(Seed shr 8)/16777216.0-0.5;end;
procedure ReadTestWav;
var Bytes:TBytes;Pos,Size,DataPos,DataSize:Integer;Rate:Cardinal;Channels,Bits:Word;Tag:AnsiString;
begin
  Bytes:=TFile.ReadAllBytes('Win64/NativeTests/AudioEdges/Checked/Verification/generated-pulses.wav');Pos:=12;DataPos:=0;DataSize:=0;Rate:=0;Channels:=0;Bits:=0;
  while Pos+8<=Length(Bytes) do begin SetString(Tag,PAnsiChar(@Bytes[Pos]),4);Move(Bytes[Pos+4],Size,4);
    Need((Size>=0) and (Size<=Length(Bytes)-Pos-8),'WAV chunk');
    if Tag='fmt ' then begin Need(Size>=16,'WAV fmt');Move(Bytes[Pos+10],Channels,2);Move(Bytes[Pos+12],Rate,4);Move(Bytes[Pos+22],Bits,2);end;
    if Tag='data' then begin DataPos:=Pos+8;DataSize:=Size;end;Pos:=Pos+8+Size+(Size mod 2);
  end;
  Need((Rate=44100) and (Channels=2) and (Bits=16) and (DataPos>0),'Existing WAV format');SetLength(Audio.PCM,DataSize);Move(Bytes[DataPos],Audio.PCM[0],DataSize);
end;
begin Audio:=nil;Snapshot:=nil;Pool:=nil;Root:=nil;Checks:=0;DenseGain:=0;QuietExtra:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','Orbit audio density native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);Root:=TJSONObject.Create;Rows:=TJSONArray.Create;Root.AddPair('cases',Rows);
    Source:=TPath.Combine(Folder,'density.identity');TFile.WriteAllText(Source,'Density source identity',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    for C:=0 to 10 do begin
      Audio:=TRhythmAudio.Create;Audio.Sensitivity:=50;Seed:=173;
      if C=6 then ReadTestWav else begin
        Frames:=8*RHYTHM_RATE;if C=7 then Frames:=RHYTHM_RATE div 10;SetLength(Audio.PCM,Frames*4);Samples:=PSmallInt(Audio.PCM);Spacing:=0.6;
        if C=1 then Spacing:=0.08;if C=2 then Spacing:=0.04;if C=3 then Spacing:=0.06;if C=9 then Spacing:=0.08;
        for F:=0 to Frames-1 do begin T:=F/RHYTHM_RATE;if C=8 then begin if T<4 then Spacing:=0.6 else Spacing:=0.06;end;Local:=T-Floor(T/Spacing)*Spacing;X:=0;
          if Local<0.018 then X:=0.7*Sin(2*Pi*1800*Local)*Exp(-Local*230);
          if C=3 then begin X:=0.12*Sin(2*Pi*110*T);if Local<0.015 then X:=X+0.45*Sin(2*Pi*6500*Local)*Exp(-Local*260);end;
          if C=9 then begin X:=0;if Local<0.032 then X:=0.8*Sin(2*Pi*80*Local)*Exp(-Local*90);end;
          if C=10 then X:=0.2*Sin(2*Pi*80*T);
          if C=4 then X:=0.00005*Rand;
          if C=5 then X:=0.18*Rand;
          K:=Round(EnsureRange(X,-0.99,0.99)*32767);Samples[F*2]:=K;Samples[F*2+1]:=K;
        end;
      end;
      Audio.Detect;Audio.Source:=Source;Audio.SourceRevision:=Revision;Audio.Key:=THashSHA2.GetHashString('density-'+IntToStr(C));PCMHash:=BytesHash(Audio.PCM);Pool:=TOrbitCandidatePool.Analyze(Audio);Row:=TJSONObject.Create;Rows.AddElement(Row);Row.AddPair('case',TJSONNumber.Create(C));Row.AddPair('oldLeft',TJSONNumber.Create(Length(Audio.Hits)));Counts:=TJSONArray.Create;Row.AddPair('countsLeftToRight',Counts);Prior:=MaxInt;
      for J:=0 to High(Values) do begin Snapshot:=Pool.Select(Audio,Values[J],Stats);Count:=0;
        for I:=0 to High(Snapshot.Hits) do if (Values[J]<=0) or (Snapshot.Hits[I].Strength>=Values[J]/100) then Inc(Count);
        if C=1 then begin
          Plan:=TGamePlan.Build(Audio,nil,Values[J]);Meta:=nil;Cold:=nil;
          try Need(Plan.Count=Count,'Full pipeline count differs');Ref:=NewPlanRef(Audio.Key,50,0,rsRhythmGame,StyleVariant(rsRhythmGame,50,100,Values[J]));Ref.SourceRevision:=Revision;
            Plan.Save(Ref,Audio);Saved:=TRhythmSettings.Defaults;Saved.Style:=rsRhythmGame;Saved.Music:=Source;Saved.GameThreshold:=Values[J];Saved.Plan:=Ref;
            Need(TRhythmSettings.TryJSON(Saved.ToJSON,Restored) and (Restored.GameThreshold=Values[J]) and (Restored.Plan.Key=Ref.Key),'Signed setting roundtrip');Meta:=TGamePlan.LoadAudioMetadata(Ref,Source,0);Cold:=TGamePlan.Load(Ref,Meta,0);
            Need((Length(Meta.PCM)=0) and (Cold.Count=Count),'Dense PCM-free restore');
            Need(BytesHash(Audio.PCM)=PCMHash,'Private detector changed PCM');Need(Length(Audio.Hits)=Stats.Legacy,'Private detector changed classic hits');
            for I:=0 to Cold.Count-1 do Need(Cold.Orbit.Taps[I].Time=Plan.Orbit.Taps[I].Time,'Dense cold clock shifted');
          finally Cold.Free;Meta.Free;Plan.Free;end;
        end;
        Need(Count<=Prior,'Density is not monotonic');Prior:=Count;Counts.Add(Count);Inc(Checks);
        if Values[J]=-100 then begin
          PeakError:=0;if C<=3 then for I:=0 to High(Snapshot.Hits) do PeakError:=Max(PeakError,Abs(Snapshot.Hits[I].Time-Round(Snapshot.Hits[I].Time/Spacing)*Spacing));
          if C<=3 then Need(PeakError<=0.020001,'Detected peak detached from actual pulse');
          Row.AddPair('maxPulseErrorSeconds',TJSONNumber.Create(PeakError));
          Need(Length(Snapshot.Hits)>=Length(Audio.Hits),'Lost original peaks');K:=0;
          for I:=0 to High(Audio.Hits) do begin while (K<Length(Snapshot.Hits)) and (Snapshot.Hits[K].Time<Audio.Hits[I].Time) do Inc(K);
            Need((K<Length(Snapshot.Hits)) and (Snapshot.Hits[K].Time=Audio.Hits[I].Time),'Shifted original peak');Inc(Checks);
          end;
          for I:=1 to High(Snapshot.Hits) do Need(Snapshot.Hits[I].Time-Snapshot.Hits[I-1].Time>=0.024999,'Double detection');
          if C in [1,2,3] then begin Need(Length(Snapshot.Hits)>Length(Audio.Hits)*1.5,'Dense left does not add real peaks');Inc(DenseGain);end;
          if C=9 then Need(Length(Snapshot.Hits)>Length(Audio.Hits)*1.5,'Dense bass added no real pulses');
          if C=10 then Need(Stats.SelectedExtra<=2,'Constant bass invented repeated extras');
          if C=7 then Need(Length(Snapshot.Hits)>0,'Short clip lost its opening');
          if C=8 then Need(Length(Snapshot.Hits)>Length(Audio.Hits),'Changing density added no cues');
          if C in [4,5] then begin Inc(QuietExtra,Stats.SelectedExtra);Need(Stats.SelectedExtra<=2,'Stationary noise created extra beats');end;
          Row.AddPair('newLeft',TJSONNumber.Create(Length(Snapshot.Hits)));Row.AddPair('extra',TJSONNumber.Create(Stats.SelectedExtra));Row.AddPair('qualified',TJSONNumber.Create(Stats.Qualified));
        end;
        FreeAndNil(Snapshot);
      end;
      if C in [4,5,6,10] then begin
        Snapshot:=PrepareOrbitAudio(Audio,-100,Stats);
        Need(Stats.RollTicks=0,'Stationary signal created a sustained roll');
        FreeAndNil(Snapshot);Inc(Checks);
      end;
      if C=1 then begin
        Worker:=TRhythmPrepareThread.Create(Source,50,0,rsRhythmGame,False,Audio,1,1);Audio:=nil;Worker.Start;Worker.WaitFor;
        try Need(Worker.Error='','Dense worker '+Worker.Error);Audio:=Worker.TakeAudio;Need((Length(Audio.Hits)=Stats.Legacy) and (BytesHash(Audio.PCM)=PCMHash),'Worker leaked private dense events');
          Meta:=TGamePlan.LoadAudioMetadata(Worker.Plan,Source,0);try Need(Length(Meta.Hits)>Length(Audio.Hits),'Worker saved classic instead of dense');finally Meta.Free;end;
        finally Worker.Free;end;
        Worker:=TRhythmPrepareThread.Create(Source,50,0,rsJumpAdventure,False,Audio,2,101);Audio:=nil;Worker.Start;Worker.WaitFor;
        try Need(Worker.Error='','Style switch '+Worker.Error);Audio:=Worker.TakeAudio;Need((Length(Audio.Hits)=Stats.Legacy) and (BytesHash(Audio.PCM)=PCMHash),'Dense events contaminated Jump Adventure');
        finally Worker.Free;end;
      end;
      WriteLn('Audio case ',C,' old=',Length(Audio.Hits),' new=',Row.GetValue<Integer>('newLeft'));Flush(Output);FreeAndNil(Pool);FreeAndNil(Audio);
    end;
    Need(DenseGain=3,'Density corpus');Root.AddPair('checks',TJSONNumber.Create(Checks));Root.AddPair('quietExtras',TJSONNumber.Create(QuietExtra));Root.AddPair('passed',TJSONBool.Create(True));
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Root.ToJSON,TEncoding.UTF8);WriteLn('Orbit audio PASS checks=',Checks,' denseCases=',DenseGain,' quietExtras=',QuietExtra);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  Root.Free;Pool.Free;Snapshot.Free;Audio.Free;
end.
