unit RhythmLayerData;
// 旧三層JSON試験専用のキャッシュ入出力。製品の描画／準備からは参照しない。
interface
uses RhythmAudio,RhythmPlanRef;
function SaveLayerShootingAudio(Audio:TRhythmAudio):string;
function LoadLayerAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
implementation
uses System.SysUtils,System.IOUtils,System.Hash,RhythmPaths,RhythmStyles,RhythmAudioCache,
  RhythmBallPlan,RhythmFireworksPlan,RhythmRunnerPlan,RhythmBreakoutPlan,RhythmRacePlan,RhythmBombPlan,
  RhythmFightingPlan,RhythmMiningPlan,RhythmTrainPlan,RhythmNavalPlan;
function ShootingEvents(const Ref:TRhythmPlanRef):string;
begin Result:=TPath.Combine(CacheFolder,Ref.SourceKey+'-s'+IntToStr(Ref.Sensitivity)+'-events-v1.json');end;
function SaveLayerShootingAudio(Audio:TRhythmAudio):string;
var R:TRhythmPlanRef;
begin
  SaveRhythmAudioCache(Audio);R:=Default(TRhythmPlanRef);R.SourceKey:=Audio.Key;R.Sensitivity:=Audio.Sensitivity;
  Result:=THashSHA2.GetHashStringFromFile(ShootingEvents(R));
end;
function LoadLayerAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
begin
  Result:=nil;
  case Ref.Style of
    rsShooting:begin
      if not ValidDigest(Ref.Digest) or not SameText(THashSHA2.GetHashStringFromFile(ShootingEvents(Ref)),Ref.Digest) then raise Exception.Create('Movie shooting cache changed; prepare again');
      Result:=LoadCachedRhythmAudio(Source,Ref.Sensitivity,False);
      if Result=nil then raise Exception.Create('Movie shooting cache missing; prepare again');
    end;
    rsBall:Result:=TRhythmBallPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsFireworks:Result:=TFireworksPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsRunner:Result:=TRunnerPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsBreakout:Result:=TBreakoutPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsRace:Result:=TRacePlan.LoadAudioMetadata(Ref,Source,Direction);
    rsBombAction:Result:=TBombActionPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsFighting:Result:=TFightingPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsMining:Result:=TMiningPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsTrain:Result:=TTrainPlan.LoadAudioMetadata(Ref,Source,Direction);
    rsNaval:Result:=TNavalPlan.LoadAudioMetadata(Ref,Source,Direction);
    else raise Exception.Create('Recursive rhythm movie is forbidden');
  end;
  try
    if (Result.Key<>Ref.SourceKey) or (Result.Sensitivity<>Ref.Sensitivity) or (Result.SourceRevision<>Ref.SourceRevision) then raise Exception.Create('Movie audio source mismatch');
    Result.SetBossFrequency(BossFrequencyFromVariant(Ref.Variant));
  except Result.Free;raise;end;
end;
end.
