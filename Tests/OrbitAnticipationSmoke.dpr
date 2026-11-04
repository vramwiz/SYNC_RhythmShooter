program OrbitAnticipationSmoke;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.Math,RhythmAudio,RhythmOrbitPlan,RhythmOrbitTypes;
var A:TRhythmAudio;P:TOrbitPlan;C:TOrbitCamera;Q:TOrbitPoint;I,J,K,N,Checks:Integer;T,Gap,Aspect:Double;
begin A:=nil;P:=nil;Checks:=0;
  try
    for K:=0 to 3 do begin
      A:=TRhythmAudio.Create;A.Duration:=96;A.SoundEnd:=96;Gap:=0.08;
      if K=1 then Gap:=0.6;if K=2 then Gap:=2.8;if K=3 then Gap:=0.031;
      N:=Floor(95.99/Gap)+1;SetLength(A.Hits,N);
      for I:=0 to N-1 do begin A.Hits[I].Time:=I*Gap;A.Hits[I].Strength:=0.8;end;
      P:=TOrbitPlan.Build(A,20);
      for I:=0 to P.Count-1 do if P.Taps[I].Time>0.3 then
        for J:=0 to 2 do begin Aspect:=16/9;if J=1 then Aspect:=9/16;if J=2 then Aspect:=1;
          T:=P.Taps[I].Time-0.25;C:=P.CameraAt(T,Aspect);Q:=OrbitProject(P.Taps[I].P,C,Aspect);
          if (Q.X<0.01) or (Q.X>0.99) or (Q.Y<0.01) or (Q.Y>0.99) then
            raise Exception.CreateFmt('Future tap not visible: case%d note%d aspect%.3f at%.3f => %.6f %.6f',[K,I,Aspect,T,Q.X,Q.Y]);
          Inc(Checks);
        end;
      FreeAndNil(P);FreeAndNil(A);
    end;
    WriteLn('Orbit anticipation PASS 250ms-before-contact checks=',Checks);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  P.Free;A.Free;
end.
