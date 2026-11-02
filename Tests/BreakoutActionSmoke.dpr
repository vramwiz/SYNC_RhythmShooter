program BreakoutActionSmoke;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Math,System.JSON,System.Generics.Collections,System.IOUtils,RhythmAudio,RhythmBreakoutScore,RhythmBreakoutGeometry;
var Audio:TRhythmAudio;Plan,Again:TBreakScorePlan;Data:TJSONObject;I,J,C:Integer;T:Double;P,Q:TBreakPoint;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
procedure RejectModified(const Name,Field:string;Value:Double);
var Bad,Item:TJSONObject;Items:TJSONArray;Pair:TJSONPair;Check:TBreakScorePlan;Rejected:Boolean;
begin Bad:=Data.Clone as TJSONObject;Check:=nil;Rejected:=False;
  try Items:=Bad.GetValue<TJSONArray>(Name);Need(Items.Count>0,'missing mutation fixture');Item:=Items.Items[0] as TJSONObject;
    Pair:=Item.RemovePair(Field);Pair.Free;Item.AddPair(Field,TJSONNumber.Create(Value));
    try Check:=TBreakScorePlan.Load(Bad,Audio);except Rejected:=True;end;
    Need(Rejected,'modified overlay accepted: '+Name+'.'+Field);
  finally Check.Free;Bad.Free;end;
end;
begin
  Audio:=nil;Plan:=nil;Again:=nil;Data:=nil;
  try
    for C:=0 to 15 do begin
      Audio:=TRhythmAudio.Create;Audio.Duration:=64;Audio.SoundEnd:=64;
      if C=1 then Audio.Duration:=180;if C=1 then Audio.SoundEnd:=180;
      if C=2 then begin Audio.Duration:=0.5;Audio.SoundEnd:=0.5;end;
      SetLength(Audio.Hits,Floor((Audio.Duration-0.05)/0.18)+1);
      for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.05+I*0.18;Audio.Hits[I].Strength:=0.5+0.5*(I mod 4)/3;end;
      if C=3 then SetLength(Audio.Hits,0);
      if C>=4 then begin
        Audio.Duration:=8+(C-4)*3.7;Audio.SoundEnd:=Audio.Duration;
        case C mod 4 of 0:T:=0.03;1:T:=0.11;2:T:=0.43;else T:=1.3;end;
        SetLength(Audio.Hits,Floor((Audio.Duration-0.05)/T)+1);
        for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.05+I*T;Audio.Hits[I].Strength:=0.4+0.6*((I*13) mod 17)/16;end;
        Audio.Hits[High(Audio.Hits)].Strength:=1;
      end;
      Plan:=TBreakScorePlan.Build(Audio,nil,False,BREAK_PADDLE_HALF_NEW);
      Writeln('BASE ',C,': ',Plan.Count);Plan.Enhance(Audio,C<2,nil);Data:=Plan.ExportData(Audio);
      Writeln('ACTION ',C,': bricks=',Plan.Count,' rooms=',Data.GetValue<TJSONArray>('rooms').Count,' charges=',Data.GetValue<TJSONArray>('charges').Count,' extras=',Plan.ExtraCount);
      if C=0 then begin
        ForceDirectories(TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence'));
        TFile.WriteAllText(TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence/Breakout.action.json'),Data.ToJSON,TEncoding.UTF8);
      end;
      Again:=TBreakScorePlan.Load(Data,Audio);
      for I:=0 to 99 do begin T:=Plan.EndTime*((I*37) mod 101)/101;P:=Plan.PositionAt(T);Again.PositionAt(Plan.EndTime-T);Q:=Again.PositionAt(T);Need((Hypot(P.X-Q.X,P.Y-Q.Y)<1E-12) and (Abs(Plan.RadiusAt(T)-Again.RadiusAt(T))<1E-12),'seek roundtrip');
        for J:=0 to Plan.ExtraCount-1 do Need(Abs(Plan.ExtraLaunch(J)-Again.ExtraLaunch(J))<1E-12,'extra roundtrip');
      end;
      if C=0 then begin RejectModified('nodes','x',0.42);RejectModified('actionBricks','left',0.001);RejectModified('charges','radius',0.12);RejectModified('actionExtra','target',0);end;
      FreeAndNil(Data);FreeAndNil(Again);FreeAndNil(Plan);FreeAndNil(Audio);
    end;
    Writeln('BreakoutActionSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Data.Free;Again.Free;Plan.Free;Audio.Free;
end.
