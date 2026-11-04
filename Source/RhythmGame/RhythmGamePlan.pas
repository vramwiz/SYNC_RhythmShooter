unit RhythmGamePlan;
// 同一スタイルの宇宙v4/v3/v2と旧平面v1の窓口。共有音声は書き換えず、描画時に再計画しない。
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmOrbitPlan,RhythmGameLegacyPlan;
type
  TGamePlan=class
  private
    FOrbit:TOrbitPlan;
    FLegacy:TLegacyGamePlan;
    function GetCount:Integer;
    function GetEndTime:Double;
    function GetExcluded:Integer;
  public
    destructor Destroy;override;
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil;Threshold:Integer=20):TGamePlan;static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TGamePlan;static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;static;
    property Count:Integer read GetCount;
    property EndTime:Double read GetEndTime;
    property Excluded:Integer read GetExcluded;
    property Orbit:TOrbitPlan read FOrbit;
  end;
implementation
uses RhythmOrbitAudio;
destructor TGamePlan.Destroy;
begin FOrbit.Free;FLegacy.Free;inherited;end;
function TGamePlan.GetCount:Integer;
begin if FOrbit<>nil then Result:=FOrbit.Count else Result:=FLegacy.Count;end;
function TGamePlan.GetEndTime:Double;
begin if FOrbit<>nil then Result:=FOrbit.EndTime else Result:=FLegacy.EndTime;end;
function TGamePlan.GetExcluded:Integer;
begin if FOrbit<>nil then Result:=FOrbit.Excluded else Result:=FLegacy.Excluded;end;
class function TGamePlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>;Threshold:Integer):TGamePlan;
var Snapshot:TRhythmAudio;Stats:TOrbitAudioStats;
begin Result:=TGamePlan.Create;Snapshot:=nil;
  // Extra detection is private to this style; never replace the common cached hits.
  try
    try Snapshot:=PrepareOrbitAudio(Audio,Threshold,Stats,Cancel);Result.FOrbit:=TOrbitPlan.Build(Snapshot,Threshold,Cancel);
    except Result.Free;raise;end;
  finally Snapshot.Free;end;
end;
procedure TGamePlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
begin if FOrbit<>nil then FOrbit.Save(Ref,Audio) else FLegacy.Save(Ref,Audio);end;
class function TGamePlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TGamePlan;
begin Result:=TGamePlan.Create;
  try if Ref.Version=1 then Result.FLegacy:=TLegacyGamePlan.Load(Ref,Audio,Direction)
    else Result.FOrbit:=TOrbitPlan.Load(Ref,Audio,Direction);
  except Result.Free;raise;end;
end;
class function TGamePlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin if Ref.Version=1 then Result:=TLegacyGamePlan.LoadAudioMetadata(Ref,Source,Direction)
  else Result:=TOrbitPlan.LoadAudioMetadata(Ref,Source,Direction);
end;
end.
