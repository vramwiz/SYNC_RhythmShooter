unit RhythmRaceCrash;
// Race衝突プランの既存公開窓口。所有権と生成／保存の接続だけを担当する。
interface
uses System.SysUtils,System.JSON,RhythmAudio,RhythmRaceCrashMotion;
const
  CRASH_FOCUS=RhythmRaceCrashMotion.CRASH_FOCUS;
  CRASH_HERO_WIDTH=RhythmRaceCrashMotion.CRASH_HERO_WIDTH;
  CRASH_HERO_FRONT=RhythmRaceCrashMotion.CRASH_HERO_FRONT;
  CRASH_HERO_BACK=RhythmRaceCrashMotion.CRASH_HERO_BACK;
  CRASH_MAX_SECONDS=RhythmRaceCrashMotion.CRASH_MAX_SECONDS;
type
  TCrashKey=RhythmRaceCrashMotion.TCrashKey;
  TCrashHit=RhythmRaceCrashMotion.TCrashHit;
  TCrashEnemy=RhythmRaceCrashMotion.TCrashEnemy;
  TCrashTraffic=RhythmRaceCrashMotion.TCrashTraffic;
  TCrashShunt=RhythmRaceCrashMotion.TCrashShunt;
  TCrashBoss=RhythmRaceCrashMotion.TCrashBoss;
  TCrashProjection=RhythmRaceCrashMotion.TCrashProjection;
  TCrashPose=RhythmRaceCrashMotion.TCrashPose;
  TRaceCrashPlan=class(TRaceCrashMotion)
  public
    // 既存呼出元へ同じ型・破棄責任を保ち、失敗した途中計画を公開しない。
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TRaceCrashPlan; static;
    function ToJSON:TJSONObject;
    class function FromJSON(Root:TJSONObject;Audio:TRhythmAudio):TRaceCrashPlan; static;
    procedure Validate(const Cancel:TFunc<Boolean> = nil);
  end;
implementation
uses RhythmRaceCrashBuild,RhythmRaceCrashCodec;

class function TRaceCrashPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRaceCrashPlan;
begin Result:=TRaceCrashPlan.Create;
  try BuildRaceCrashPlan(Result,Audio,Cancel);
  except Result.Free;
    raise;
  end;
end;

function TRaceCrashPlan.ToJSON:TJSONObject;
begin Result:=RaceCrashJSON(Self);
end;

class function TRaceCrashPlan.FromJSON(Root:TJSONObject;Audio:TRhythmAudio):TRaceCrashPlan;
begin Result:=TRaceCrashPlan.Create;
  try ReadRaceCrashJSON(Result,Root,Audio);
  except Result.Free;
    raise;
  end;
end;

procedure TRaceCrashPlan.Validate(const Cancel:TFunc<Boolean>);
begin ValidateRaceCrashPlan(Self,Cancel);
end;
end.
