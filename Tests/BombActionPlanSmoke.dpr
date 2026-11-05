program BombActionPlanSmoke;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,System.Math,
  RhythmBombPlan in '..\Source\BombAction\RhythmBombPlan.pas',
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
var Audio:TRhythmAudio;A,B:TBombActionPlan;I,J,K:Integer;D,Gap,T:Double;Bomb:TBABomb;Point:TBAPoint;Charge:TBACharge;Foe:TBACrowdEnemy;Raid:TBAEnemyShot;
procedure Need(Value:Boolean;const Why:string);begin if not Value then raise Exception.Create(Why);end;
begin
  Audio:=nil;A:=nil;B:=nil;
  try
    Need((Ord(rsBombAction)=6) and (Ord(rsSideRace)=5) and (StylePlanVersion(rsBombAction)=2),'Style identity');
    Need((StyleVariant(rsBombAction,50,0)=1) and (StyleVariant(rsBombAction,50,50)=51),'Frequency identity');
    for K:=0 to 7 do begin
      D:=90;Gap:=0.25;case K of 1:begin D:=1800;Gap:=0.43;end;2:begin D:=120;Gap:=0.005;end;3:begin D:=0.10;Gap:=0.01;end;4:D:=2;5:D:=100;end;
      Audio:=TRhythmAudio.Create;Audio.Key:=StringOfChar('a',64);Audio.Duration:=D;Audio.SoundEnd:=D;if K=4 then Audio.SoundEnd:=0;if K=5 then Audio.SoundEnd:=64;
      if K<>4 then begin SetLength(Audio.Hits,Max(0,Floor((Audio.SoundEnd-0.05)/Gap)+1));for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.05+I*Gap;Audio.Hits[I].Strength:=0.15+(I mod 9)*0.1;end;end;
      Audio.SetBossFrequency(50);if K=6 then Audio.SetBossFrequency(0);if K=7 then Audio.SetBossFrequency(100);
      A:=TBombActionPlan.Build(Audio);B:=TBombActionPlan.Build(Audio);Need((A.Count=B.Count) and (A.ChainCount=B.ChainCount) and (A.BossCount=B.BossCount) and (A.ChargeCount=B.ChargeCount) and (A.CrowdCount=B.CrowdCount) and (A.RaidCount=B.RaidCount),'Determinism');
      if K=6 then Need(A.BossCount=0,'Frequency zero');
      for I:=0 to A.Count-1 do begin Bomb:=A.Bomb[I];Need(Bomb.Time=Audio.Hits[Bomb.Source].Time,'Changed accent');Need(BALength(BASub(Bomb.Position,A.HeroAt(Bomb.Place)))<1E-7,'Planting mismatch');
        for J:=0 to 2 do begin T:=Bomb.Time+J*0.1;Need(BALength(BASub(A.HeroAt(T),Bomb.Position))>A.BlastRadius(I,T)+BA_HERO_RADIUS+BA_BLAST_PAD,'Blast contact');end;
      end;
      for I:=0 to A.ChargeCount-1 do begin Charge:=A.Charges[I];Need(Charge.Time=A.Bomb[Charge.Bomb].Time,'Salvo music clock');Need(BALength(BASub(Charge.Position,A.HeroAt(Charge.Place)))<1E-7,'Salvo planting');end;
      for I:=0 to A.CrowdCount-1 do begin Foe:=A.Crowd[I];if Foe.Bomb>=0 then Need(Foe.Kill=A.Bomb[Foe.Bomb].Time,'Formation music clock');end;
      for I:=0 to A.RaidCount-1 do begin Raid:=A.Raids[I];Need(BALength(BASub(Raid.Position,A.CrowdAt(Raid.Foe,Raid.Start)))<1E-7,'Shot launch origin');end;
      for I:=0 to 99 do begin T:=A.EndTime*((I*37) mod 101)/101;Point:=B.HeroAt(A.EndTime-T);Need(not IsNan(Point.X),'Invalid seek');Need(BALength(BASub(A.HeroAt(T),B.HeroAt(T)))<1E-10,'Seek dependency');end;
      Need(BALength(BASub(A.HeroAt(A.EndTime),A.HeroAt(A.EndTime+100)))=0,'End freeze');
      FreeAndNil(A);FreeAndNil(B);FreeAndNil(Audio);
    end;
    Writeln('BombActionPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  A.Free;B.Free;Audio.Free;
end.
