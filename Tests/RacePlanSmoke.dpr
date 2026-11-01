program RacePlanSmoke;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,System.Math,
  RhythmRacePlan in '..\Source\Race\RhythmRacePlan.pas',
  RhythmAudio in '..\Source\Composition\RhythmAudio.pas',
  RhythmSections in '..\Source\Shooting\RhythmSections.pas',
  RhythmMotion in '..\Source\Shooting\RhythmMotion.pas',
  RhythmStyles in '..\Source\Shared\Settings\RhythmStyles.pas',
  RhythmPlanRef in '..\Source\Shared\Settings\RhythmPlanRef.pas',
  RhythmPreparedData in '..\Source\Shared\Settings\RhythmPreparedData.pas',
  RhythmPaths in '..\Source\Shared\Common\RhythmPaths.pas',
  RhythmProduct in '..\Source\Shared\Settings\RhythmProduct.pas',
  RhythmAudioAnalysis in '..\Source\Shared\Audio\RhythmAudioAnalysis.pas',
  MimiChildProcess in '..\Source\Lib\Process\MimiChildProcess.pas';
var Audio:TRhythmAudio;A,B:TRacePlan;P,Q:TRaceProjection;C:TRaceCoin;I,J,K:Integer;D,Gap,T,Previous:Double;Pose:TRacePose;
procedure Need(Value:Boolean;const Msg:string);begin if not Value then raise Exception.Create(Msg);end;
begin
  Audio:=nil;A:=nil;B:=nil;
  try
    Need((Ord(rsRace)=5) and (Ord(rsBreakout)=4) and (StylePlanVersion(rsRace)=7) and CompatiblePlanVersion(rsRace,1) and CompatiblePlanVersion(rsRace,2) and CompatiblePlanVersion(rsRace,3) and CompatiblePlanVersion(rsRace,4) and CompatiblePlanVersion(rsRace,5) and CompatiblePlanVersion(rsRace,6),'Style contract');
    Need((TRacePlan.CoinPoints(0.39)=10) and (TRacePlan.CoinPoints(0.40)=50) and (TRacePlan.CoinPoints(0.70)=100),'Score tiers');
    Need((TRacePlan.CoinMetal(0.39)=0) and (TRacePlan.CoinMetal(0.4)=1) and (TRacePlan.CoinMetal(0.7)=2),'Metal boundaries');
    for K:=0 to 7 do begin
      D:=64;Gap:=0.18;case K of 1:begin D:=1800;Gap:=0.43;end;2:begin D:=12;Gap:=0.005;end;3:begin D:=0.1;Gap:=0.01;end;4:D:=2;5:D:=100;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=D;Audio.SoundEnd:=D;if K=4 then Audio.SoundEnd:=0;if K=5 then Audio.SoundEnd:=64;
      if K<>4 then begin SetLength(Audio.Hits,Floor((Audio.SoundEnd-0.005)/Gap)+1);for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.005+I*Gap;Audio.Hits[I].Strength:=0.4+0.1*(I mod 6);end;end;
      Audio.SetBossFrequency(50);if K=6 then Audio.SetBossFrequency(0);if K=7 then Audio.SetBossFrequency(100);A:=TRacePlan.Build(Audio);B:=TRacePlan.Build(Audio);Need(A.Version=7,'Race v7');Need(A.Focus=40,'Faster perspective');if K=6 then Need(A.TrailerCount=0,'Boss disabled');Need(A.TrafficCount=B.TrafficCount,'Traffic determinism');Need(A.TrailerCount=B.TrailerCount,'Boss determinism');Need(A.GoalTime<A.EndTime,'No finish tail');Need(A.EndTime<=Audio.Duration,'Ends beyond music');
      Previous:=-1;for I:=0 to 100 do begin T:=A.EndTime*I/100;Need(A.DistanceAt(T)>=Previous,'Reverse driving');Previous:=A.DistanceAt(T);Need(A.SpeedAt(T)>=0,'Negative speed');end;
      for I:=0 to A.Count-1 do begin C:=A.Coin[I];Need(C.Time=Audio.Hits[C.Source].Time,'Accent time changed');Need(C.Points=TRacePlan.CoinPoints(C.Strength),'Point value');Need(A.ScoreAt(C.Time)>A.ScoreAt(C.Time-1E-6),'Missing award');P:=A.Project(C.Distance,C.Lane,C.Time,RACE_COIN_HEIGHT);Q:=A.Project(A.DistanceAt(C.Time),A.LaneAt(C.Time),C.Time,RACE_COIN_HEIGHT);Need(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-7,'Missed coin');end;
      for J:=0 to 99 do begin T:=A.EndTime*((J*37) mod 101)/101;B.DistanceAt(A.EndTime-T);Pose:=A.PoseAt(T);Need((Abs(Pose.Steer)<=1) and (Abs(Pose.Load)<=1) and (Abs(Pose.Offset)<=0.04),'Pose bounds');Need((A.DistanceAt(T)=B.DistanceAt(T)) and (A.LaneAt(T)=B.LaneAt(T)),'Seek changed route');end;
      Need((A.DistanceAt(A.EndTime)=A.DistanceAt(A.EndTime+100)) and (A.SpeedAt(A.EndTime+100)=0),'End does not freeze');
      Need((A.ScoreAt(A.EndTime)=A.MaxScore) and (A.ScoreAt(-1)=0),'Score endpoints');
      FreeAndNil(A);FreeAndNil(B);FreeAndNil(Audio);
    end;
    Writeln('RacePlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  A.Free;B.Free;Audio.Free;
end.
