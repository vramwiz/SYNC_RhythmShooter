program PreparedAudioSmoke;
{$APPTYPE CONSOLE}
// 保存後の音時刻・強度と二音目以降のEQを確認する。PCM解析・再生・実アプリ操作はしない。
uses System.SysUtils,System.Math,System.IOUtils,System.JSON,System.Hash,
  RhythmAudio,RhythmAudioCache,RhythmPreparedData,RhythmPlanRef,RhythmStyles,RhythmEqualizer;

const Times:array[0..5] of Double=(0.25,1.5,4.75,8.125,14.25,19.75);
      Strengths:array[0..5] of Double=(0.2,0.7,0.45,0.95,0.6,0.85);
var Audio,Cold,Legacy:TRhythmAudio;Root,Saved:TJSONObject;Info:TJSONObject;
  Ref:TRhythmPlanRef;A,B:TEqualizerActivity;Folder,Source:string;
  I,Checks:Integer;At:Double;Rejected:Boolean;

procedure Need(Valid:Boolean;const Why:string);
begin if not Valid then raise Exception.Create(Why);Inc(Checks);end;

begin
  Audio:=nil;Cold:=nil;Legacy:=nil;Root:=nil;Saved:=nil;Checks:=0;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Source:=TPath.Combine(Folder,'prepared-audio.identity');
    TFile.WriteAllText(Source,'Metadata regression only. No audio playback.',TEncoding.UTF8);
    Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.SourceRevision:=AudioSourceStamp(Source);
    Audio.Key:=THashSHA2.GetHashString('prepared-audio-equalizer');Audio.Sensitivity:=50;
    Audio.Duration:=20.125;Audio.SoundEnd:=20;SetLength(Audio.PCM,4);SetLength(Audio.Hits,Length(Times));
    for I:=0 to High(Times) do begin
      Audio.Hits[I].Time:=Times[I];Audio.Hits[I].Strength:=Strengths[I];
      Audio.Hits[I].Lane:=(I mod 3)/2;Audio.Hits[I].Flight:=0.42+I*0.11;
    end;
    Ref:=NewPlanRef(Audio.Key,50,0,rsTrapAction,1);Ref.SourceRevision:=Audio.SourceRevision;
    Root:=TJSONObject.Create;AddPreparedAudio(Root,Audio);
    Saved:=TJSONObject.ParseJSONValue(Root.ToJSON) as TJSONObject;
    Cold:=PreparedAudio(Saved,Ref,Source);
    Need(Cold.HasHitDetails and (Length(Cold.PCM)=0),'Cold metadata requires PCM or lost event details');
    Need(Length(Cold.Hits)=Length(Times),'Event count changed');
    for I:=0 to High(Times) do begin
      Need((Cold.Hits[I].Time=Audio.Hits[I].Time) and (Cold.Hits[I].Strength=Audio.Hits[I].Strength) and
        (Cold.Hits[I].Lane=Audio.Hits[I].Lane) and (Cold.Hits[I].Flight=Audio.Hits[I].Flight),'Binary64 event changed');
      A:=EqualizerActivity(Audio,Times[I]);B:=EqualizerActivity(Cold,Times[I]);
      Need(B.Valid and (B.Pulse>0.1),'Equalizer stopped before a later sound');
      Need((A.Pulse=B.Pulse) and (A.Energy=B.Energy) and (A.Hit=B.Hit) and (A.Hue=B.Hue),'Warm/cold equalizer differs');
    end;
    for At in TArray<Double>.Create(19.8,0.1,8.2,1.6,20.1,4.76,0.25,14.3) do begin
      A:=EqualizerActivity(Audio,At);B:=EqualizerActivity(Cold,At);
      Need((A.Valid=B.Valid) and (A.Pulse=B.Pulse) and (A.Energy=B.Energy) and
        (A.Hit=B.Hit) and (A.Hue=B.Hue),'Random seek changed equalizer activity');
    end;
    Info:=Saved.GetValue<TJSONObject>('audio');
    Info.RemovePair('events').Free;Info.AddPair('events',TJSONNumber.Create(Length(Times)+1));Rejected:=False;
    try Legacy:=PreparedAudio(Saved,Ref,Source);FreeAndNil(Legacy);
    except on E:EConvertError do Rejected:=True;end;
    Need(Rejected,'Truncated audio events were accepted');
    Info.RemovePair('events').Free;Info.AddPair('events',TJSONNumber.Create(Length(Times)));
    Info.RemovePair('hits').Free;Legacy:=PreparedAudio(Saved,Ref,Source);
    Need(not Legacy.HasHitDetails and (Length(Legacy.Hits)=Length(Times)),'Legacy plan count was invalidated');
    for At in TArray<Double>.Create(0,0.1,1.5,8.125,19.75) do
      Need(not EqualizerActivity(Legacy,At).Valid,'Legacy count-only data created a false opening pulse');
    Writeln('Prepared audio/EQ PASS checks=',Checks,' later sounds=',Length(Times)-1,' no PCM, no playback');
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  Legacy.Free;Cold.Free;Audio.Free;Saved.Free;Root.Free;
end.
