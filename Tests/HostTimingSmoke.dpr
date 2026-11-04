program HostTimingSmoke;
{$APPTYPE CONSOLE}
// オフセットの符号/境界と旧JSON互換を、ホスト/フォーム/音声再生なしで検証する。
uses System.SysUtils,System.Math,System.IOUtils,System.JSON,
  RhythmTiming,RhythmSettings,RhythmStyles,RhythmPlanRef;
var Checks,I,J,D:Integer;O,T,Hit:Double;S:TRhythmStyle;Saved,Loaded:TRhythmSettings;Ref:TRhythmPlanRef;Text,Key,Folder:string;
procedure Need(V:Boolean;const Why:string);
begin if not V then raise Exception.Create(Why);Inc(Checks);end;
begin
  Checks:=0;
  try
    Need(NormalizeRenderOffset(NaN)=0,'NaN offset');Need(NormalizeRenderOffset(Infinity)=0,'Infinite offset');
    Need((NormalizeRenderOffset(-2)=-1) and (NormalizeRenderOffset(2)=1),'Offset bounds');
    Need((AnimationTime(NaN,0)<0) and (AnimationTime(Infinity,0)<0),'Invalid host time');
    Need((AnimationTime(0,1)=-1) and (AnimationTime(1,1)=0),'Delayed opening boundary');
    Need(AnimationTime(0,-1)=1,'Advance at object start');Need(AnimationTime(100,1)=99,'Delayed end');Need(AnimationTime(100,-1)=101,'Advance end');
    for I:=-100 to 100 do begin O:=I/100.0;
      Need(Abs(NormalizeRenderOffset(O)-O)<1E-12,'0.01-second grid');
      for J:=0 to 20 do begin Hit:=J*0.087+0.031;T:=Hit+O;
        Need(Abs(AnimationTime(T,O)-Hit)<1E-12,'Original sound time changed');
      end;
    end;
    Key:=StringOfChar('a',64);
    for S:=Low(TRhythmStyle) to High(TRhythmStyle) do for D:=0 to 1 do begin
      Text:=Format('{"schema":1,"style":"%s","direction":%d,"sensitivity":37}',[StyleId(S),D]);
      Need(TRhythmSettings.TryJSON(Text,Loaded),'Legacy JSON parse');
      Need((Loaded.Direction=D) and (Loaded.Sensitivity=37) and (Loaded.OffsetSeconds=0),'Legacy direction/sensitivity/default offset');
      Saved:=Loaded;Saved.BossFrequency:=100;
      Ref:=NewPlanRef(Key,37,D,S,StyleVariant(S,Saved.FireworksRichness,Saved.BossFrequency,Saved.GameThreshold));
      Ref.Digest:=StringOfChar('b',64);Saved.Plan:=Ref;
      for I:=-100 to 100 do begin Saved.OffsetSeconds:=I/100.0;
        Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded),'Offset JSON roundtrip');
        Need((Abs(Loaded.OffsetSeconds-Saved.OffsetSeconds)<1E-12) and (Loaded.Plan.Key=Ref.Key) and
          (Loaded.Direction=D) and (Loaded.Sensitivity=37),'Offset invalidated saved plan or editor settings');
      end;
    end;
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"shooting","offsetSeconds":8}',Loaded) and (Loaded.OffsetSeconds=1),'Positive JSON bound');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"shooting","offsetSeconds":-8}',Loaded) and (Loaded.OffsetSeconds=-1),'Negative JSON bound');
    Need(not TRhythmSettings.TryJSON('{"schema":1,"offsetSeconds":"bad"}',Loaded),'Bad offset type');
    Saved:=TRhythmSettings.Defaults;Saved.OffsetSeconds:=NaN;
    Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded) and (Loaded.OffsetSeconds=0),'Finite serialization fallback');
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"styles":13,"offsetSteps":201,"oldJson":true,"gui":false}',[Checks]),TEncoding.UTF8);
    WriteLn('Host timing PASS checks=',Checks,' styles=13 offsetSteps=201 old JSON no GUI');
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
end.
