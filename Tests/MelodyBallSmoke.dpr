program MelodyBallSmoke;
{$APPTYPE CONSOLE}
// 段差への落下打撃、てこの力積と上の鉄琴への実接触、重力、左右の受け面を検証する。
uses System.SysUtils,System.Classes,System.Math,System.IOUtils,System.Hash,System.Generics.Collections,
  Winapi.Windows,Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmAudioCache,
  RhythmMelodyPlan,RhythmMelodyBuild,RhythmMelodyCodec,RhythmMelodyCamera,RhythmMelodyArt,
  RhythmStyles,RhythmPlanRef,RhythmSettings,RhythmAnimation,RhythmRenderSurface,RhythmImageBank,RhythmScene;
var Checks,Frames,Impacts,Falls,Springs,RecurringRails,Hammers,Steps,LeftRuns,Turns:Integer; Folder,SourceFile:string;
  MaxForceError,MaxEnergyGain,MaxSpeed,CameraNewResidual,CameraOldResidual:Double;
  DenseFastSpeed,DenseSlowSpeed,DenseMinCoverage,ZoomMaximum:Double;
  ZoomCloseTransitions:Integer;
  PhraseChanges,EstimatedMeters,StableSlowSamples:Integer;
  MaxWoodRun,StableSlowAngle,MaxWoodFraction:Double;
procedure Need(B:Boolean; const Why:string);
begin if not B then raise Exception.Create(Why); Inc(Checks); end;
function Audio(Seconds,Gap:Double; Silent:Boolean=False):TRhythmAudio;
var I,N:Integer;
begin
  Result:=TRhythmAudio.Create; Result.Source:=SourceFile; Result.SourceRevision:=AudioSourceStamp(SourceFile);
  Result.Key:=THashSHA2.GetHashString('melody physics '+FloatToStr(Seconds)+' '+FloatToStr(Gap));
  Result.Duration:=Seconds; Result.SoundEnd:=Seconds; Result.Sensitivity:=50;
  if Silent then Exit;
  N:=Max(0,Floor((Seconds-0.25)/Gap)+1); SetLength(Result.Hits,N);
  for I:=0 to N-1 do begin Result.Hits[I].Time:=0.25+I*Gap; Result.Hits[I].Strength:=0.3+(I mod 8)*0.09; end;
end;
function MixedAudio:TRhythmAudio;
var T:Double; I:Integer;
begin
  Result:=Audio(50,0.04); T:=0.25; I:=0;
  while T<50 do begin
    Result.Hits[I].Time:=T; Inc(I);
    if InRange(T,12.0,27.99) then T:=T+0.04 else T:=T+0.24;
  end;
  SetLength(Result.Hits,I); Result.Key:=THashSHA2.GetHashString('melody slow-fast-slow');
end;
function TempoInterval(A:TRhythmAudio; Index:Integer):Double;
begin
  Result:=1;
  if Index>0 then Result:=A.Hits[Index].Time-A.Hits[Index-1].Time
  else if Length(A.Hits)>1 then Result:=A.Hits[1].Time-A.Hits[0].Time;
  Result:=Max(0.035,Result);
end;
function Hash(B:TBitmap):string;
var H:THashSHA2; Y:Integer;
begin H:=THashSHA2.Create; for Y:=0 to B.Height-1 do H.Update(B.ScanLine[Y]^,B.Width*4); Result:=H.HashAsString; end;
procedure PNG(B:TBitmap; const Name:string);
var P:TPngImage;
begin P:=TPngImage.Create; try P.Assign(B); P.SaveToFile(TPath.Combine(Folder,Name)); finally P.Free; end; end;
function Energy(const S:TMelodySpan; T:Double):Double;
var P,V:TMelodyPoint; D,Speed:Double;
begin
  P:=MelodySample(S,T/(S.Finish-S.Start)); V:=MelodySpanVelocity(S,T);
  if S.Motion=mmRolling then MelodyTravel(S,T,D,Speed) else Speed:=S.Speed;
  Result:=0.5*(Sqr(V.X)+Sqr(V.Y))+0.2*Sqr(Speed)+9.81*P.Y;
  if S.Motion=mmSpring then Result:=Result+0.5*Sqr(S.SpringOmega*MelodyCompression(S,T));
end;
procedure Physics(P:TMelodyPlan);
var I,J,K,ViewMode:Integer; S,After:TMelodySpan; Pos,V,A,B,N,Elbow:TMelodyPoint;
  T,D,Speed,Theta,Expected,Error,E,Previous,DX,DY,Impulse,BeforeEnergy,AfterEnergy,Scale,H:Double;
  View:TMelodyView; Board:TMelodyBar; Triggered:Boolean;
  procedure ClearArm(const BallPos,A,B:TMelodyPoint; Radius:Double);
  var X,Y,U:Double;
  begin
    X:=B.X-A.X; Y:=B.Y-A.Y;
    U:=EnsureRange(((BallPos.X-A.X)*X+(BallPos.Y-A.Y)*Y)/(X*X+Y*Y),0.0,1.0);
    Need(Sqr(BallPos.X-A.X-U*X)+Sqr(BallPos.Y-A.Y-U*Y)>=Sqr(0.24+Radius-0.00001),
      Format('rotor arm penetrates ball i=%d t=%.6f theta=%.4f scale=%.2f angle=%.4f distance=%.6f',[I,T,Theta,Scale,D,
        Sqrt(Sqr(BallPos.X-A.X-U*X)+Sqr(BallPos.Y-A.Y-U*Y))]));
  end;
begin
  P.Validate; V:=P.Velocity(0); Need(MelodyLength(V)<1E-10,'initial external push'); Previous:=1E20;
  for I:=0 to High(P.Spans) do begin
    S:=P.Spans[I]; if S.Motion=mmFlight then Inc(Falls);
    if S.Motion=mmSpring then Inc(Springs);
    if (S.Motion=mmRolling) and MelodyHasRail(S.Kind) and (S.Start>4) then Inc(RecurringRails);
    if (S.Motion=mmRolling) and (S.Direction=-1) and (S.B.Y<S.A.Y) then Inc(LeftRuns);
    for J:=0 to 20 do begin
      T:=(S.Finish-S.Start)*J/20; Pos:=MelodySample(S,J/20); V:=MelodySpanVelocity(S,T);
      MaxSpeed:=Max(MaxSpeed,MelodyLength(V)); E:=Energy(S,T);
      MaxEnergyGain:=Max(MaxEnergyGain,E-Previous); Need(E<=Previous+0.003,'energy appears without work'); Previous:=E;
      for ViewMode:=0 to 1 do begin
        if ViewMode=0 then View:=MelodyView(P,S.Start+T,540,960) else View:=MelodyView(P,S.Start+T,960,540);
        Need((Pos.X-MelodyRadius>View.Left) and (Pos.X+MelodyRadius<View.Right) and
          (Pos.Y-MelodyRadius>View.Bottom) and (Pos.Y+MelodyRadius<View.Top),'camera loses ball');
      end;
      if S.Motion=mmFlight then begin
        Need(Abs(V.X-S.Launch.X)<1E-9,'horizontal force in flight');
        Need(Abs(V.Y-(S.Launch.Y-9.81*T))<1E-9,'free fall ignores gravity');
        Need(Abs(Pos.Y-(S.A.Y+S.Launch.Y*T-4.905*T*T))<1E-8,'non-ballistic air path');
      end else if S.Motion=mmRolling then begin
        MelodyTravel(S,T,D,Speed); Theta:=S.Theta+S.Curvature*D;
        N:=MelodyRailPoint(S,D);
        Need(Abs(MelodyLength(MelodyPoint(Pos.X-N.X,Pos.Y-N.Y))-0.24)<1E-8,'unsupported ball');
        Need(9.81*Cos(Theta)+Speed*Speed*S.Curvature>=-1E-6,'negative supporting force');
      end else if S.Motion=mmSpring then begin
        D:=MelodyCompression(S,T); K:=P.BarAt(S.Start);
        Need((K>=0) and (D>=-1E-8),'spring pulls the ball');
        Need(Abs(Pos.Y-0.24-(P.Bars[K].Top-P.BarCompression(K,S.Start+T)))<1E-7,'ball separates from compressing plate');
        Need((Pos.X>P.Bars[K].Left) and (Pos.X<P.Bars[K].Right),'ball leaves the spring plate before release');
      end;
    end;
    if S.Motion=mmSpring then for J:=1 to 5 do begin
      T:=(S.Finish-S.Start)*J/6; D:=MelodyCompression(S,T);
      A:=MelodySpanVelocity(S,T-0.00001); B:=MelodySpanVelocity(S,T+0.00001);
      Need(Abs((B.Y-A.Y)/0.00002-(-9.81+Sqr(S.SpringOmega)*D))<0.01,'spring force disagrees with acceleration');
      Need(Abs(A.X-B.X)<1E-9,'spring adds horizontal force');
    end;
    if S.Motion=mmRolling then for J:=1 to 5 do begin
      T:=(S.Finish-S.Start)*J/6; MelodyTravel(S,T,D,Speed); Theta:=S.Theta+S.Curvature*D;
      H:=Min(0.0001,Min(T,S.Finish-S.Start-T)*0.1);
      A:=MelodySpanVelocity(S,T-H); B:=MelodySpanVelocity(S,T+H);
      // 球中心の接線加速度は(5/7)g成分-抵抗、法線加速度はv^2*k。
      Expected:=-9.81*Sin(Theta)*5/7-S.Drag*Speed;
      V:=MelodyPoint((B.X-A.X)/(2*H),(B.Y-A.Y)/(2*H));
      Error:=Abs(S.Direction*V.X*Cos(Theta)+V.Y*Sin(Theta)-Expected); MaxForceError:=Max(MaxForceError,Error);
      Need(Error<0.035,Format('Newton tangential span=%d kind=%d t=%.9f err=%.9f expected=%.9f v=%.9f theta=%.9f',[I,Ord(S.Kind),T,Error,Expected,Speed,Theta]));
      Error:=Abs(-S.Direction*V.X*Sin(Theta)+V.Y*Cos(Theta)-Speed*Speed*S.Curvature);
      Need(Error<0.035,'centripetal acceleration disagrees with track');
    end;
    if I>0 then begin
      A:=MelodySample(P.Spans[I-1],1); B:=MelodySample(S,0);
      Need(MelodyLength(MelodyPoint(A.X-B.X,A.Y-B.Y))<1E-8,'teleport');
      if (P.Spans[I-1].Motion=mmRolling) and (S.Motion<>mmRest) then begin
        A:=MelodySpanVelocity(P.Spans[I-1],P.Spans[I-1].Finish-P.Spans[I-1].Start); B:=MelodySpanVelocity(S,0);
        Triggered:=False;
        for K:=Max(0,P.BarAt(S.Start)-1) to Min(High(P.Bars),P.BarAt(S.Start+2)+1) do
          if (P.Bars[K].Strike=msHammer) and (P.Bars[K].TriggerSpan=I-1) then Triggered:=True;
        if not Triggered then Need(MelodyLength(MelodyPoint(A.X-B.X,A.Y-B.Y))<1E-7,'velocity changes away from collision');
      end;
      if S.Direction<>P.Spans[I-1].Direction then begin
        Inc(Turns); Need((P.Spans[I-1].Motion=mmFlight) and (S.Motion=mmRolling) and MelodyHasRail(S.Kind),'turn has no receiving surface');
        A:=MelodySpanVelocity(P.Spans[I-1],P.Spans[I-1].Finish-P.Spans[I-1].Start);
        Need((-S.Direction*A.X*Sin(S.Theta)+A.Y*Cos(S.Theta))<0,'turn approaches rail from underside');
        Expected:=(S.Direction*A.X*Cos(S.Theta)+A.Y*Sin(S.Theta)+
          0.4*S.Direction*P.Spans[I-1].Direction*P.Spans[I-1].Speed)/1.4;
        Need(Abs(S.Speed-Expected)<1E-8,'turn violates tangential impulse with sphere inertia');
      end;
    end;
  end;
  for I:=0 to High(P.Bars) do begin
    Inc(Impacts); Board:=P.Bars[I]; S:=P.Spans[Board.Span]; After:=P.Spans[Board.Span+1];
    A:=P.Position(P.Bars[I].Time); Need(MelodyLength(MelodyPoint(A.X-P.Bars[I].Contact.X,A.Y-P.Bars[I].Contact.Y))<1E-8,'missed steel contact');
    if Board.Strike=msHammer then begin
      Inc(Hammers); S:=P.Spans[Board.TriggerSpan]; After:=P.Spans[Board.TriggerSpan+1];
      Scale:=Board.MechanismScale;
      MelodyTravel(S,S.Finish-S.Start,D,Speed); Theta:=S.Theta+S.Curvature*D;
      Impulse:=1.4*(Speed-After.Speed);
      Need(Abs(Impulse*MelodyPaddleArm*Scale-MelodyHammerInertia(Board)*Board.AngularSpeed)<1E-8,'rotor angular impulse does not come from ball');
      Need(Abs(MelodyPaddleArm*Scale*Board.AngularSpeed-After.Speed-0.15*Speed)<1E-8,'paddle restitution');
      BeforeEnergy:=0.7*Sqr(Speed); AfterEnergy:=0.7*Sqr(After.Speed)+0.5*MelodyHammerInertia(Board)*Sqr(Board.AngularSpeed);
      Need(AfterEnergy<BeforeEnergy,'lever creates energy');
      if Scale<1 then Need((After.Motion=mmRolling) and (Abs(After.Theta-Theta)<1E-9) and
        (After.Speed>Speed*0.995),'continuous seesaw rebounds or stops ball');
      A:=MelodyHammer(Board,S.Direction,Board.Time);
      B:=MelodyHammer(Board,S.Direction,Board.Time-0.001);
      Need((Abs(A.Y+MelodyHammerRadius*Scale-Board.Top+0.11)<1E-8) and (B.Y<A.Y),'hammer does not strike upward into steel');
      Need((A.X>Board.Left) and (A.X<Board.Right) and (P.Position(Board.Time).Y+0.24<Board.Top-0.11),'overhead plate counted as ball rolling');
      for J:=0 to 100 do begin
        T:=Board.Trigger+(Board.Time-Board.Trigger+0.3)*J/100;
        D:=EnsureRange((T-Board.Trigger)*Board.AngularSpeed,0.0,MelodyStroke(Board));
        A:=MelodyPoint(Board.Pivot.X+S.Direction*Scale*MelodyPaddleArm*Sin(Theta+D),Board.Pivot.Y-Scale*MelodyPaddleArm*Cos(Theta+D));
        A.X:=A.X+S.Direction*Scale*0.04*Cos(Theta+D); A.Y:=A.Y+Scale*0.04*Sin(Theta+D);
        Pos:=P.Position(T); B:=Board.Pivot;
        // 球とパドル腕の線分距離。打撃後にパドルが軌道を塞いだままにならない。
        Need(Sqr(Pos.X-A.X)+Sqr(Pos.Y-A.Y)>=Sqr(0.24+0.04*Scale-0.00001),
          Format('paddle blocks ball i=%d t=%.6f theta=%.4f scale=%.2f angle=%.4f',[I,T,Theta,Scale,D]));
        Elbow:=MelodyPoint(B.X+S.Direction*MelodyPaddleArm*Scale*(0.55*Cos(Theta+D)+0.5*Sin(Theta+D)),
          B.Y+MelodyPaddleArm*Scale*(0.55*Sin(Theta+D)-0.5*Cos(Theta+D)));
        ClearArm(Pos,B,Elbow,0.0375*Scale); ClearArm(Pos,Elbow,A,0.0375*Scale);
        A:=MelodyHammer(Board,S.Direction,T);
        N:=MelodyPoint(B.X-(A.X-B.X)*MelodyCounterArm(Board),B.Y-(A.Y-B.Y)*MelodyCounterArm(Board));
        ClearArm(Pos,N,A,0.0375*Scale);
        Need(Sqr(Pos.X-N.X)+Sqr(Pos.Y-N.Y)>=Sqr(0.24+0.15*Scale-0.00001),
          Format('counterweight blocks ball i=%d t=%.6f theta=%.4f scale=%.2f angle=%.4f',[I,T,Theta,Scale,D]));
        Need(Sqr(Pos.X-A.X)+Sqr(Pos.Y-A.Y)>=Sqr(0.24+0.12*Scale-0.00001),'hammer blocks ball');
        for K:=Max(0,P.BarAt(T)-2) to Min(High(P.Bars),P.BarAt(T)+2) do begin
          DX:=Pos.X-EnsureRange(Pos.X,P.Bars[K].Left,P.Bars[K].Right);
          E:=P.Bars[K].Top-P.BarCompression(K,T);
          DY:=Pos.Y-EnsureRange(Pos.Y,E-0.11,E);
          Need(DX*DX+DY*DY>=Sqr(0.24-0.00001),'continuous seesaw path penetrates steel');
        end;
        if T<=Board.Time+0.05 then for ViewMode:=0 to 1 do begin
          if ViewMode=0 then View:=MelodyView(P,T,540,960) else View:=MelodyView(P,T,960,540);
          Need((A.X>View.Left+0.12) and (A.X<View.Right-0.12) and
            (A.Y>View.Bottom+0.12) and (A.Y<View.Top-0.12),'camera loses hammer strike');
        end;
      end;
      Continue;
    end;
    Need(S.Motion=mmFlight,'a rolling pass is incorrectly counted as impact');
    Need(Abs(A.Y-0.24-Board.Top)<1E-8,'ball bottom does not meet horizontal top');
    A:=MelodySpanVelocity(S,S.Finish-S.Start); B:=MelodySpanVelocity(After,0);
    Need(A.Y< -0.001,'impact is not descending from above');
    Pos:=MelodySample(S,1-Min(0.001,S.Finish-S.Start)/(S.Finish-S.Start));
    Need(Pos.Y-0.24>Board.Top,'ball is not above the board just before impact');
    if not Board.Terminal and (Board.Strike=msSpring) then begin
      Need(Abs(B.X-A.X)<1E-9,'horizontal board adds horizontal impulse');
      Need((After.Motion=mmSpring) and (Abs(B.Y-Board.Restitution*A.Y)<1E-9),'spring loading velocity does not match');
      Need(B.Y<0,'velocity flips upward before compression');
      B:=MelodySpanVelocity(After,After.Finish-After.Start);
      Need(Abs(B.Y+Board.Restitution*A.Y)<1E-7,'spring release velocity does not match stored energy');
      Need((B.Y>0) and (B.Y<=-A.Y+1E-7),'active boost on passive spring');
      Need(MelodyCompression(After,(After.Finish-After.Start)*0.5)>0.0001,'no visible spring compression');
    end else if not Board.Terminal then begin
      Inc(Steps); Need((After.Motion=mmRolling) and (After.Kind=mcArm) and (After.Theta=0),'plate is not horizontal after impact');
      Need((P.Spans[Board.Span+2].Motion=mmFlight) and (Abs(B.Y)<1E-9),'no free fall at step edge');
    end;
    // 全板の近傍で球と板の厚みを検査し、予定衝突より前の側面/前の板への貫通も拒否する。
    for J:=0 to 100 do begin
      Pos:=MelodySample(S,J/100);
      for K:=Max(0,I-2) to Min(High(P.Bars),I+2) do begin
        DX:=Pos.X-EnsureRange(Pos.X,P.Bars[K].Left,P.Bars[K].Right);
        D:=P.Bars[K].Top-P.BarCompression(K,S.Start+(S.Finish-S.Start)*J/100);
        DY:=Pos.Y-EnsureRange(Pos.Y,D-0.11,D);
        Need(DX*DX+DY*DY>=Sqr(0.24-0.00001),Format('sphere penetrates board hit=%d other=%d t=%.6f strike=%d x=%.4f y=%.4f left=%.4f right=%.4f top=%.4f',
          [I,K,S.Start+(S.Finish-S.Start)*J/100,Ord(P.Bars[K].Strike),Pos.X,Pos.Y,P.Bars[K].Left,P.Bars[K].Right,D]));
      end;
    end;
  end;
end;
procedure CheckPlans;
var A,R:TRhythmAudio; P,Q:TMelodyPlan; Ref,Wrong:TRhythmPlanRef; I,J,K:Integer; Failed:Boolean; OriginalDigest,Path:string; Bytes:TBytes;
  L,H,RailSeconds,NextHit:Double;
  Saved,Loaded:TRhythmSettings; Flat:TMelodySpan;
begin
  for I:=0 to 19 do begin
    case I of
      0:A:=Audio(0.02,1,True); 1:A:=Audio(1.1,0.12); 2:A:=Audio(25,0.04); 3:A:=Audio(120,0.5);
      4:A:=Audio(300.037,1.8); 5:A:=Audio(30,1,True); 6:A:=Audio(100,7); 7:A:=Audio(1200,0.12);
      else A:=Audio(30+I*3,0.08);
    end;
    if I>=8 then begin
      NextHit:=0.25; K:=0;
      while (K<Length(A.Hits)) and (NextHit<A.Duration) do begin
        A.Hits[K].Time:=NextHit; A.Hits[K].Strength:=((K*31+I*17) mod 101)/100;
        NextHit:=NextHit+0.09+((K*47+I*13) mod 97)*0.014;
        if (K mod 19)=7 then NextHit:=NextHit+2.4;
        Inc(K);
      end;
      SetLength(A.Hits,K); A.Key:=THashSHA2.GetHashString('irregular melody '+IntToStr(I));
    end;
    WriteLn('fixture ',I); P:=BuildMelodyPlan(A); Q:=nil; R:=nil;
    try
      Physics(P); if I in [0,5] then Need(Length(P.Bars)=0,'silent music invented notes');
      if I in [3,7] then for K:=0 to 2 do begin
        L:=4+(A.Duration-8)*K/3; H:=4+(A.Duration-8)*(K+1)/3; RailSeconds:=0;
        for J:=0 to High(P.Spans) do if (P.Spans[J].Motion=mmRolling) and MelodyHasRail(P.Spans[J].Kind) then
          RailSeconds:=RailSeconds+Max(0.0,Min(H,P.Spans[J].Finish)-Max(L,P.Spans[J].Start));
        Need(RailSeconds>0.5,'no real rolling rails in a later third of the song');
      end;
      for J:=0 to High(P.Bars) do Need(P.Bars[J].Time=A.Hits[P.Bars[J].Source].Time,'altered musical cue');
      Ref:=NewPlanRef(A.Key,50,I mod 2,rsMelodyBall); Ref.SourceRevision:=A.SourceRevision; SaveMelodyPlan(P,A,Ref);
      OriginalDigest:=Ref.Digest; Q:=BuildMelodyPlan(A); SaveMelodyPlan(Q,A,Ref); Need(Ref.Digest=OriginalDigest,'nonrepeatable physics'); FreeAndNil(Q);
      R:=LoadMelodyAudio(Ref,A.Source,I mod 2); Need(Length(R.PCM)=0,'cold playback decodes PCM'); Q:=LoadMelodyPlan(Ref,R,I mod 2);
      for J:=0 to 100 do begin
        Need(P.Position(P.EndTime*J/100).X=Q.Position(Q.EndTime*J/100).X,'saved X drift');
        Need(P.Position(P.EndTime*J/100).Y=Q.Position(Q.EndTime*J/100).Y,'saved Y drift');
        Need(P.Rotation(P.EndTime*J/100)=Q.Rotation(Q.EndTime*J/100),'saved angular drift');
        Need(P.CameraZoom(P.EndTime*J/100)=Q.CameraZoom(Q.EndTime*J/100),'saved zoom drift');
        Need(P.SectionAt(P.Duration*J/100)=Q.SectionAt(Q.Duration*J/100),'saved phrase drift');
      end;
      Need((P.Meter=Q.Meter) and (P.Beat=Q.Beat) and (P.BeatOrigin=Q.BeatOrigin) and
        (P.BeatConfidence=Q.BeatConfidence) and (P.SectionLength=Q.SectionLength),'saved musical grid drift');
      Wrong:=Ref; Wrong.Direction:=1-Ref.Direction; Failed:=False;
      try LoadMelodyPlan(Wrong,R,Ref.Direction).Free; except on E:Exception do Failed:=True; end; Need(Failed,'wrong source identity');
      if I=4 then begin
        Path:=TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'SYNC_RhythmShooter\Plans\'+Ref.Key+'.json'); Bytes:=TFile.ReadAllBytes(Path);
        try TFile.AppendAllText(Path,' ',TEncoding.UTF8); Failed:=False;
          try LoadMelodyPlan(Ref,R,Ref.Direction).Free; except on E:Exception do Failed:=True; end; Need(Failed,'corrupt hash accepted');
        finally TFile.WriteAllBytes(Path,Bytes); end;
      end;
    finally Q.Free; R.Free; P.Free; A.Free; end;
  end;
  Need(Impacts>0,'no top-face impacts'); Need(Falls>0,'no free fall');
  Need(Springs>0,'no compression before release'); Need(RecurringRails>0,'no rails after the introduction');
  Need((Hammers>0) and (Steps>0) and (LeftRuns>0) and (Turns>0),'missing lever / steps / left downhill route');
  A:=Audio(30,0.24); P:=BuildMelodyPlan(A);
  try
    for I:=0 to High(A.Hits) do A.Hits[I].Strength:=0.99;
    Q:=BuildMelodyPlan(A);
    try for I:=0 to 300 do begin
      Need(P.Position(I/10).X=Q.Position(I/10).X,'audio strength accelerates ball');
      Need(P.Position(I/10).Y=Q.Position(I/10).Y,'audio strength launches ball');
    end; finally Q.Free; end;
    Failed:=False; try BuildMelodyPlan(A,function:Boolean begin Result:=True; end).Free; except on E:EAbort do Failed:=True; end; Need(Failed,'cancel ignored');
  finally P.Free; A.Free; end;
  Need(not CompatiblePlanVersion(rsMelodyBall,1) and not CompatiblePlanVersion(rsMelodyBall,2) and
    not CompatiblePlanVersion(rsMelodyBall,3) and not CompatiblePlanVersion(rsMelodyBall,4) and
    not CompatiblePlanVersion(rsMelodyBall,5) and not CompatiblePlanVersion(rsMelodyBall,6) and
    CompatiblePlanVersion(rsMelodyBall,7),'old repeating slope plan accepted');
  Saved:=TRhythmSettings.Defaults; Saved.Style:=rsMelodyBall; Saved.Music:=SourceFile;
  for J:=1 to 6 do begin
    Saved.Plan:=NewPlanRef(StringOfChar('a',64),50,0,rsMelodyBall); Saved.Plan.Version:=J;
    Saved.Plan.Key:=THashSHA2.GetHashString('melody-ball-v'+IntToStr(J)+'|'+StringOfChar('a',64)+'|50|0');
    Saved.Plan.Digest:=StringOfChar('b',64);
    Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded) and (Loaded.Style=rsMelodyBall) and
      (Loaded.Music=SourceFile) and (Loaded.Plan.Key=''),'old path does not require reprepare');
  end;
  P:=TMelodyPlan.Create;
  try
    P.Duration:=1; P.EndTime:=1; Flat:=Default(TMelodySpan); Flat.Direction:=1; Flat.Finish:=1; Flat.Motion:=mmRolling; Flat.Kind:=mcSlope;
    P.SectionLength:=8; SetLength(P.Sections,1); P.Sections[0].Finish:=1;
    SetLength(Flat.Knots,2); Flat.Knots[1].Time:=1; SetLength(P.Spans,1); P.Spans[0]:=Flat;
    P.IndexGeometry; Physics(P); Need((P.Position(0.5).X=0) and (P.Position(0.5).Y=0),'horizontal shelf moves a resting ball');
  finally P.Free; end;
end;
function OldCameraY(P:TMelodyPlan; T:Double):Double;
var I:Integer; W,Sum,Y,V:Double;
begin
  Sum:=0; Y:=0; V:=0;
  for I:=-4 to 4 do begin
    W:=5-Abs(I); Y:=Y+P.Position(T+I*0.09).Y*W; V:=V+P.Velocity(T+I*0.09).Y*W; Sum:=Sum+W;
  end;
  Result:=Y/Sum+EnsureRange(V/Sum*0.22,-1.6,1.2)-0.25;
end;
procedure CheckCamera;
var A:TRhythmAudio; P,Q:TMelodyPlan; I,J:Integer; T,Lo,Hi,W,Load,Period,Scale:Double;
  View,Again:TMelodyView; Rows:TStringList;
begin
  A:=Audio(60,0.5); P:=BuildMelodyPlan(A); Q:=BuildMelodyPlan(A); Rows:=TStringList.Create;
  try
    // カメラの独立性を検査するため、接点・時間・端点を保ってバネの圧縮量だけを変える。
    // 球の力学試験とは別の描画入力で、接触中の微振動がカメラへ伝播しないことを確認する。
    for I:=0 to High(Q.Spans) do if Q.Spans[I].Motion=mmSpring then begin
      Load:=-Q.Spans[I].Launch.Y*0.4; Lo:=1; Hi:=5000;
      for J:=0 to 48 do begin
        W:=(Lo+Hi)/2; Period:=2*(Pi-ArcTan(Load*W/9.81))/W;
        if Period>Q.Spans[I].Finish-Q.Spans[I].Start then Lo:=W else Hi:=W;
      end;
      Q.Spans[I].Launch.Y:=-Load; Q.Spans[I].SpringOmega:=(Lo+Hi)/2;
    end;
    Q.IndexGeometry; Scale:=MelodyView(P,0,960,540).Scale;
    Rows.Add('time,cameraY,changedCompressionCameraY,oldCameraY,changedCompressionOldCameraY');
    for I:=0 to 7200 do begin
      T:=60*I/7200; View:=MelodyView(P,T,960,540); Again:=MelodyView(P,60-T,960,540);
      Again:=MelodyView(P,T,960,540); Need((View.Center.X=Again.Center.X) and (View.Center.Y=Again.Center.Y),'camera depends on seek history');
      Again:=MelodyView(Q,T,960,540);
      CameraNewResidual:=Max(CameraNewResidual,MelodyLength(MelodyPoint(View.Center.X-Again.Center.X,View.Center.Y-Again.Center.Y)));
      CameraOldResidual:=Max(CameraOldResidual,Abs(OldCameraY(P,T)-OldCameraY(Q,T)));
      Need(Abs(View.Scale-Again.Scale)<1E-10,'camera zoom responds to bounce');
      Need(InRange(View.Scale/Scale,1.0-1E-10,1.35+1E-10),'zoom outside bounded range');
      Rows.Add(Format('%s,%s,%s,%s,%s',[FloatToStr(T,TFormatSettings.Invariant),
        FloatToStr(View.Center.Y,TFormatSettings.Invariant),FloatToStr(Again.Center.Y,TFormatSettings.Invariant),
        FloatToStr(OldCameraY(P,T),TFormatSettings.Invariant),FloatToStr(OldCameraY(Q,T),TFormatSettings.Invariant)]));
    end;
    Need(CameraNewResidual<0.0001,'camera follows individual spring strokes');
    Need((CameraOldResidual>0.00001) and (CameraNewResidual<CameraOldResidual*0.05),'camera shake regression not improved');
    Rows.SaveToFile(TPath.Combine(Folder,'camera-comparison.csv'),TEncoding.UTF8);
  finally Rows.Free; Q.Free; P.Free; A.Free; end;
end;
procedure CheckTempo;
var A:TRhythmAudio; P:TMelodyPlan; I,J,Expected,Heard,Count:Integer; B:TMelodyBar;
  Gap,Sum,Coverage,T:Double; Hit:TArray<Boolean>; Rows:TStringList;
begin
  Rows:=TStringList.Create; DenseMinCoverage:=1;
  try
    Rows.Add('fixture,time,speed,zoom');
    for I:=0 to 2 do begin
      if I=0 then Gap:=0.04 else Gap:=0.12;
      if I=2 then A:=MixedAudio else A:=Audio(40,Gap);
      P:=BuildMelodyPlan(A);
      try
        if I=2 then Physics(P);
        SetLength(Hit,Length(A.Hits)); for J:=0 to High(Hit) do Hit[J]:=False;
        for B in P.Bars do Hit[B.Source]:=True;
        Expected:=0; Heard:=0;
        for J:=0 to High(A.Hits) do if InRange(A.Hits[J].Time,5.0,35.0) then begin
          if P.Sections[P.SectionAt(A.Hits[J].Time)].Kind<>mpSeesaw then Continue;
          if A.Hits[J].Time<P.Sections[P.SectionAt(A.Hits[J].Time)].Start+0.3 then Continue;
          if MelodyLength(P.Velocity(A.Hits[J].Time))<0.54/TempoInterval(A,J) then Continue;
          Inc(Expected); if Hit[J] then Inc(Heard);
        end;
        Need(Expected>0,'no eligible continuous-hammer notes');
        Coverage:=Heard/Expected; DenseMinCoverage:=Min(DenseMinCoverage,Coverage);
        Need(Coverage>=0.98,Format('continuous notes missed fixture=%d coverage=%.6f',[I,Coverage]));
        Sum:=0; Count:=0;
        for J:=0 to 1200 do begin
          T:=10+20*J/1200; Gap:=MelodyLength(P.Velocity(T));
          Rows.Add(Format('%d,%s,%s,%s',[I,FloatToStr(T,TFormatSettings.Invariant),FloatToStr(Gap,TFormatSettings.Invariant),
            FloatToStr(P.CameraZoom(T),TFormatSettings.Invariant)]));
          if P.Sections[P.SectionAt(T)].Kind<>mpSeesaw then Continue;
          if T<P.Sections[P.SectionAt(T)].Start+3.0 then Continue;
          Sum:=Sum+Gap; Inc(Count);
          Need(P.Spans[P.SpanAt(T)].Motion=mmRolling,'rapid seesaw sends ball airborne');
        end;
        if I=0 then DenseFastSpeed:=Sum/Count else if I=1 then DenseSlowSpeed:=Sum/Count;
      finally P.Free; A.Free; end;
    end;
    Rows.SaveToFile(TPath.Combine(Folder,'tempo-comparison.csv'),TEncoding.UTF8);
    Need(DenseFastSpeed>DenseSlowSpeed*1.7,Format('tempo speed fast=%.4f slow=%.4f',[DenseFastSpeed,DenseSlowSpeed]));
    Need(DenseFastSpeed>14,Format('dense physical speed too low %.4f',[DenseFastSpeed]));
  finally Rows.Free; end;
end;
procedure CheckPhrases;
var A:TRhythmAudio; P,Bad:TMelodyPlan; I,J,K,Count,Relevant,Changes,TurnCount:Integer;
  SourceMeter:Integer; S:TMelodySpan; B:TMelodyBar; SavedKind:TMelodySectionKind;
  RunStart,WoodSeconds,T,D,V,Angle,Acceleration:Double; Failed:Boolean; Rows:TStringList;
begin
  Rows:=TStringList.Create;
  try
    Rows.Add('fixture,section,start,finish,kind,strikes,matchingMechanism,woodSeconds');
    for I:=0 to 3 do begin
      if I=0 then A:=Audio(80,0.04) else if I=1 then A:=Audio(80,0.24) else A:=Audio(60,0.5);
      SourceMeter:=0;
      if I>=2 then begin
        SourceMeter:=I+1;
        for J:=0 to High(A.Hits) do if (J mod SourceMeter)=0 then A.Hits[J].Strength:=1 else A.Hits[J].Strength:=0.2;
        A.Key:=THashSHA2.GetHashString('melody meter '+IntToStr(SourceMeter));
      end;
      P:=BuildMelodyPlan(A);
      try
        Physics(P);
        if SourceMeter>0 then begin
          Need(P.Meter=SourceMeter,Format('clear meter not detected input=%d output=%d confidence=%.4f',[SourceMeter,P.Meter,P.BeatConfidence]));
          Need(Abs(P.Beat-0.5)<0.001,'clear quarter pulse estimate');
          Need(Abs(P.SectionLength-SourceMeter*2)<0.001,'sections are not four measures'); Inc(EstimatedMeters);
        end else Need((P.Meter=0) and (P.SectionLength=8),'ambiguous data incorrectly claims a meter');
        WoodSeconds:=0; RunStart:=0;
        for J:=0 to High(P.Spans) do begin
          S:=P.Spans[J];
          if (S.Motion<>mmRolling) or not MelodyHasRail(S.Kind) then begin RunStart:=S.Finish; Continue; end;
          WoodSeconds:=WoodSeconds+S.Finish-S.Start;
          MaxWoodRun:=Max(MaxWoodRun,S.Finish-RunStart);
          Need(S.Finish-RunStart<=P.SectionLength+1.5,'continuous wood slope exceeds phrase limit');
          Need(S.Drag<=0.03,'steep slope slowed by invisible resistance');
          for K:=1 to 5 do begin
            T:=(S.Finish-S.Start)*K/6; MelodyTravel(S,T,D,V); Angle:=S.Theta+S.Curvature*D;
            Acceleration:=-9.81*Sin(Angle)/1.4-S.Drag*V;
            if (S.Start>6) and (V<6) and (Abs(Acceleration)<0.20) then begin
              Inc(StableSlowSamples); StableSlowAngle:=Max(StableSlowAngle,Abs(Angle));
              Need(Abs(Angle)<0.12,'steady slow ball on a visibly steep slope');
            end;
          end;
        end;
        MaxWoodFraction:=Max(MaxWoodFraction,WoodSeconds/P.Duration);
        Need(WoodSeconds/P.Duration<0.65,'track still dominated by the same wood slope');
        Changes:=0;
        for J:=0 to High(P.Sections) do begin
          if J>0 then begin Need(P.Sections[J].Kind<>P.Sections[J-1].Kind,'adjacent motif repeats'); Inc(Changes); end;
          Count:=0; Relevant:=0; TurnCount:=0; WoodSeconds:=0;
          for B in P.Bars do if (B.Time>=P.Sections[J].Start) and (B.Time<P.Sections[J].Finish) then begin
            Inc(Count);
            case P.Sections[J].Kind of
              mpSteps:if B.Strike=msStep then Inc(Relevant);
              mpSeesaw:if B.Strike=msHammer then Inc(Relevant);
              mpSpring:if B.Strike=msSpring then Inc(Relevant);
              mpTurns:Inc(Relevant);
            end;
          end;
          for K:=1 to High(P.Spans) do if (P.Spans[K].Start>=P.Sections[J].Start) and
            (P.Spans[K].Start<P.Sections[J].Finish) and (P.Spans[K].Direction<>P.Spans[K-1].Direction) then Inc(TurnCount);
          for K:=0 to High(P.Spans) do if (P.Spans[K].Motion=mmRolling) and MelodyHasRail(P.Spans[K].Kind) then
            WoodSeconds:=WoodSeconds+Max(0.0,Min(P.Sections[J].Finish,P.Spans[K].Finish)-Max(P.Sections[J].Start,P.Spans[K].Start));
          if (P.Sections[J].Finish-P.Sections[J].Start>=5) and (P.Sections[J].SourceCount>=6) then begin
            Need((Count>0) and (Relevant>0),Format('motif label without actual mechanism case=%d section=%d kind=%d',[I,J,Ord(P.Sections[J].Kind)]));
            if P.Sections[J].Kind=mpTurns then Need(TurnCount>0,'turn section does not change travel direction at contact');
          end;
          Rows.Add(Format('%d,%d,%s,%s,%d,%d,%d,%s',[I,J,
            FloatToStr(P.Sections[J].Start,TFormatSettings.Invariant),FloatToStr(P.Sections[J].Finish,TFormatSettings.Invariant),
            Ord(P.Sections[J].Kind),Count,Relevant,FloatToStr(WoodSeconds,TFormatSettings.Invariant)]));
        end;
        Need(Changes>=6,'long constant data does not change presentation'); PhraseChanges:=PhraseChanges+Changes;
        SavedKind:=P.Sections[1].Kind; P.Sections[1].Kind:=P.Sections[0].Kind; Failed:=False;
        try P.Validate; except on E:EConvertError do Failed:=Pos('同じ演出',E.Message)>0; end;
        Need(Failed,'repeated adjacent section was accepted'); P.Sections[1].Kind:=SavedKind;
      finally P.Free; A.Free; end;
    end;
    Need(StableSlowSamples>0,'no slope/speed matching evidence');
    Bad:=TMelodyPlan.Create;
    try
      Bad.Duration:=20; Bad.EndTime:=20; Bad.SectionLength:=8; SetLength(Bad.Sections,3);
      for I:=0 to 2 do begin Bad.Sections[I].Start:=I*8; Bad.Sections[I].Finish:=Min(20,(I+1)*8); Bad.Sections[I].Kind:=TMelodySectionKind(I); end;
      S:=Default(TMelodySpan); S.Finish:=20; S.Direction:=1; S.Motion:=mmRolling; S.Kind:=mcSlope;
      SetLength(S.Knots,2); S.Knots[1].Time:=20; SetLength(Bad.Spans,1); Bad.Spans[0]:=S;
      Failed:=False; try Bad.Validate; except on E:EConvertError do Failed:=Pos('坂道だけ',E.Message)>0; end;
      Need(Failed,'renaming sections disguised a single continuous rail');
    finally Bad.Free; end;
    Rows.SaveToFile(TPath.Combine(Folder,'phrase-cadence.csv'),TEncoding.UTF8);
  finally Rows.Free; end;
end;
procedure CheckZoom;
var P:TMelodyPlan; Pieces:TList<TMelodySpan>; S:TMelodySpan; Rows:TStringList;
  Mode,I:Integer; T,Limit,V,X,Z,Previous,LastClose,Again:Double; WasClose:Boolean;
begin
  Rows:=TStringList.Create;
  try
    Rows.Add('fixture,time,zoom');
    for Mode:=0 to 3 do begin
      P:=TMelodyPlan.Create; Pieces:=TList<TMelodySpan>.Create;
      try
        // カメラ入力だけの等速経路。物理試験とは別に、持続時間と頻繁な切り替えを制御する。
        P.Duration:=60; P.EndTime:=60; T:=0; X:=0;
        while T<60-1E-8 do begin
          V:=3;
          case Mode of
            1:V:=12;
            2:if Odd(Round(T/0.6)) then V:=12;
            3:if (Floor(T) mod 18)>=12 then V:=12;
          end;
          Limit:=Min(60.0,T+0.6); S:=Default(TMelodySpan); S.Direction:=1;
          S.Start:=T; S.Finish:=Limit; S.A:=MelodyPoint(X,0); S.Speed:=V; S.Motion:=mmRolling; S.Kind:=mcSlope;
          X:=X+V*(Limit-T); S.B:=MelodyPoint(X,0); SetLength(S.Knots,2);
          S.Knots[0].Speed:=V; S.Knots[1].Time:=Limit-T; S.Knots[1].Distance:=V*(Limit-T); S.Knots[1].Speed:=V;
          Pieces.Add(S); T:=Limit;
        end;
        P.Spans:=Pieces.ToArray; P.IndexGeometry; Previous:=1; WasClose:=False; LastClose:=-100;
        for I:=0 to 3480 do begin
          T:=I/60; Z:=P.CameraZoom(T); Again:=P.CameraZoom(60-T);
          Need(InRange(Again,1.0-1E-9,1.35+1E-9),'opposite seek zoom range'); Again:=P.CameraZoom(T);
          Need(Z=Again,'zoom has playback history'); Need(InRange(Z,1.0-1E-9,1.35+1E-9),'zoom range');
          Need(Abs(Z-Previous)<0.012,'zoom changes abruptly'); Previous:=Z; ZoomMaximum:=Max(ZoomMaximum,Z);
          if (Z>1.15) and not WasClose then begin
            Need(T-LastClose>=8,'zoom repeats without a wide hold'); LastClose:=T; Inc(ZoomCloseTransitions);
          end;
          WasClose:=Z>1.15;
          if Mode in [1,2] then Need(Abs(Z-1)<1E-9,'fast or brief alternating speed zooms in');
          Rows.Add(Format('%d,%s,%s',[Mode,FloatToStr(T,TFormatSettings.Invariant),FloatToStr(Z,TFormatSettings.Invariant)]));
        end;
        if Mode=0 then Need(P.CameraZoom(10)>1.34,'sustained slow motion does not zoom in');
      finally Pieces.Free; P.Free; end;
    end;
    Rows.SaveToFile(TPath.Combine(Folder,'zoom-cadence.csv'),TEncoding.UTF8);
  finally Rows.Free; end;
end;
procedure CheckDrawing;
const W:array[0..2]of Integer=(960,540,1280); H:array[0..2]of Integer=(540,960,720);
  Captions:array[0..3]of string=('落下','着地','バネ圧縮','解放・発射');
var A:TRhythmAudio; P:TMelodyPlan; B,Sheet,Strip,HammerStrip:TBitmap; Surface:TAnimationRenderSurface; F:TAnimationFrame;
  Times:TList<Double>; Hashes:TArray<string>; I,J,K,Size,Mode,Index,Large,HammerIndex,TurnIndex:Integer;
  Cue,Duration,RailTime:Double; Report:TStringList; Caption:string;
  procedure Draw(Time:Double);
  begin F.Time:=Time; F.Width:=B.Width; F.Height:=B.Height; F.BackgroundOnly:=False;
    Surface.BeginFrame(B); DrawMelodyBall(Surface,P,F); Need(Surface.EndFrame,'surface'); Inc(Frames); end;
begin
  A:=Audio(45,0.5); P:=BuildMelodyPlan(A); B:=TBitmap.Create; Sheet:=TBitmap.Create; Strip:=TBitmap.Create; HammerStrip:=TBitmap.Create;
  Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0)); Times:=TList<Double>.Create; Report:=TStringList.Create;
  try
    B.PixelFormat:=pf32bit; Sheet.PixelFormat:=pf32bit; Sheet.SetSize(1600,900);
    Strip.PixelFormat:=pf32bit; Strip.SetSize(960,540); HammerStrip.PixelFormat:=pf32bit; HammerStrip.SetSize(960,540);
    Large:=0; RailTime:=0; HammerIndex:=-1; TurnIndex:=-1;
    for I:=0 to High(P.Bars) do if P.Bars[I].Kind=mbSpring then begin Large:=I; Break; end;
    for I:=0 to High(P.Bars) do if P.Bars[I].Strike=msHammer then begin HammerIndex:=I; Break; end;
    for I:=1 to High(P.Spans) do if P.Spans[I].Direction<>P.Spans[I-1].Direction then begin TurnIndex:=I; Break; end;
    for I:=0 to High(P.Spans) do if (P.Spans[I].Motion=mmRolling) and MelodyHasRail(P.Spans[I].Kind) and (P.Spans[I].Start>5) then begin
      RailTime:=(P.Spans[I].Start+P.Spans[I].Finish)/2; Break;
    end;
    Need((Large>0) and (RailTime>5) and (HammerIndex>0) and (TurnIndex>0),'no rail / spring / hammer / turn preview');
    for J:=0 to 2 do begin
      case J of 0:Index:=0; 1:Index:=Large; else Index:=HammerIndex; end;
      Cue:=P.Bars[Index].Time; Duration:=P.Spans[P.Bars[Index].Span+1].Finish-Cue;
      if J=2 then begin
        Times.Add(P.Bars[Index].Trigger-0.08); Times.Add(P.Bars[Index].Trigger);
        Times.Add((P.Bars[Index].Trigger+Cue)/2); Times.Add(Cue);
      end else begin
        Times.Add(Cue-0.10); Times.Add(Cue); Times.Add(Cue+Duration*0.5); Times.Add(Cue+Duration+0.08);
      end;
    end;
    Cue:=P.Spans[TurnIndex].Start; Duration:=P.Spans[TurnIndex].Finish-Cue;
    Times.Add(Cue-0.12); Times.Add(Cue); Times.Add(Cue+Duration*0.5); Times.Add(Cue+Duration);
    Times.Add(0); Times.Add(1); Times.Add(RailTime); Times.Add(P.EndTime-0.1); SetLength(Hashes,Times.Count);
    for Size:=0 to 2 do for Mode:=0 to 1 do begin
      B.SetSize(W[Size],H[Size]); Surface.UseD2D:=Mode=1;
      for I:=0 to Times.Count-1 do begin Draw(Times[I]); Hashes[I]:=Hash(B); end;
      for I:=Times.Count-1 downto 0 do begin Draw(Times[I]); Need(Hash(B)=Hashes[I],'reverse seek changes spring / camera'); end;
      if Mode=1 then Need(Surface.LastUsedD2D,'Direct2D');
      if (Size=0) and (Mode=1) then begin
        for I:=0 to 15 do begin
          Draw(Times[I]); Sheet.Canvas.StretchDraw(Rect((I mod 4)*400,(I div 4)*225,(I mod 4+1)*400,(I div 4+1)*225),B);
          Sheet.Canvas.Font.Name:='Yu Gothic UI'; Sheet.Canvas.Font.Size:=10;
          Sheet.Canvas.Font.Color:=RGB(50,54,58); Sheet.Canvas.Brush.Style:=bsClear;
          Caption:=Captions[I mod 4];
          case I div 4 of
            0:case I mod 4 of 2:Caption:='打撃後の水平移動'; 3:Caption:='端から次の段へ落下'; end;
            2:case I mod 4 of 0:Caption:='坂道の球が接近'; 1:Caption:='球がパドルを押す'; 2:Caption:='てこでハンマー上昇'; 3:Caption:='上の鉄琴を打撃'; end;
            3:case I mod 4 of 0:Caption:='受けレールへ落下'; 1:Caption:='斜面へ接触'; 2:Caption:='左下へ転がる'; 3:Caption:='左へ進むコース'; end;
          end;
          Sheet.Canvas.TextOut((I mod 4)*400+10,(I div 4)*225+8,Caption+Format('  %.2fs',[Times[I]]));
          if I in [4,5,6,7] then begin
            K:=I-4; Strip.Canvas.StretchDraw(Rect((K mod 2)*480,(K div 2)*270,(K mod 2+1)*480,(K div 2+1)*270),B);
            Strip.Canvas.Font.Name:='Yu Gothic UI'; Strip.Canvas.Font.Size:=10; Strip.Canvas.Font.Color:=RGB(50,54,58);
            Strip.Canvas.Brush.Style:=bsClear; Strip.Canvas.TextOut((K mod 2)*480+10,(K div 2)*270+8,Captions[K]);
            PNG(B,'spring-phase-'+IntToStr(K)+'.png');
          end;
          if I in [8,9,10,11] then begin
            K:=I-8; HammerStrip.Canvas.StretchDraw(Rect((K mod 2)*480,(K div 2)*270,(K mod 2+1)*480,(K div 2+1)*270),B);
            HammerStrip.Canvas.Font.Name:='Yu Gothic UI'; HammerStrip.Canvas.Font.Size:=10;
            HammerStrip.Canvas.Font.Color:=RGB(50,54,58); HammerStrip.Canvas.Brush.Style:=bsClear;
            HammerStrip.Canvas.TextOut((K mod 2)*480+10,(K div 2)*270+8,Caption);
            PNG(B,'hammer-phase-'+IntToStr(K)+'.png');
          end;
          if I=14 then PNG(B,'left-down.png');
          if I=2 then PNG(B,'step-after-impact.png');
        end;
        Draw(RailTime); PNG(B,'later-rail.png'); Draw(1); PNG(B,'rail-support.png');
      end;
    end;
    Report.Add('time,ballX,ballY,verticalVelocity,compression');
    for I:=4 to 7 do Report.Add(Format('%s,%s,%s,%s,%s',[FloatToStr(Times[I],TFormatSettings.Invariant),
      FloatToStr(P.Position(Times[I]).X,TFormatSettings.Invariant),FloatToStr(P.Position(Times[I]).Y,TFormatSettings.Invariant),
      FloatToStr(P.Velocity(Times[I]).Y,TFormatSettings.Invariant),FloatToStr(P.BarCompression(Large,Times[I]),TFormatSettings.Invariant)]));
    Report.SaveToFile(TPath.Combine(Folder,'spring-phases.csv'),TEncoding.UTF8);
    PNG(Sheet,'mechanisms.png'); PNG(Strip,'one-spring.png'); PNG(HammerStrip,'one-hammer.png');
  finally Report.Free; Times.Free; Surface.Free; HammerStrip.Free; Strip.Free; Sheet.Free; B.Free; P.Free; A.Free; end;
end;

procedure CheckTempoDrawing;
const Widths:array[0..2]of Integer=(960,540,1280); Heights:array[0..2]of Integer=(540,960,720);
var A:TRhythmAudio; P:TMelodyPlan; B,Sheet:TBitmap; Surface:TAnimationRenderSurface; F:TAnimationFrame;
  Times:array[0..5]of Double; Hashes:array[0..5]of string; I,J,Size,Mode:Integer;
  T,Z,Best:Double; Caption:string; Report:TStringList;
  procedure Draw(T:Double);
  begin
    F.Time:=T; F.Width:=B.Width; F.Height:=B.Height; F.BackgroundOnly:=False;
    Surface.BeginFrame(B); DrawMelodyBall(Surface,P,F); Need(Surface.EndFrame,'tempo surface'); Inc(Frames);
  end;
begin
  A:=MixedAudio; P:=BuildMelodyPlan(A); B:=TBitmap.Create; Sheet:=TBitmap.Create;
  Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0)); Report:=TStringList.Create;
  try
    Times[0]:=6; Times[1]:=14; Times[2]:=38; Times[3]:=14.04; Times[4]:=14.08; Times[5]:=14.12;
    for J:=0 to 1 do begin
      Best:=0;
      for I:=0 to 600 do begin
        if J=0 then T:=5+7*I/600 else T:=32+14*I/600;
        Z:=P.CameraZoom(T);
        if Z>Best then begin Best:=Z; Times[J*2]:=T; end;
      end;
      Need(Best>1.3,'slow-fast-slow preview has no sustained zoom');
    end;
    Need(Abs(P.CameraZoom(Times[1])-1)<1E-9,'fast preview is zoomed in');
    B.PixelFormat:=pf32bit; Sheet.PixelFormat:=pf32bit; Sheet.SetSize(1440,540);
    Report.Add('time,speed,zoom');
    for Size:=0 to 2 do for Mode:=0 to 1 do begin
      B.SetSize(Widths[Size],Heights[Size]); Surface.UseD2D:=Mode=1;
      for I:=0 to 5 do begin Draw(Times[I]); Hashes[I]:=Hash(B); end;
      for I:=5 downto 0 do begin Draw(Times[I]); Need(Hash(B)=Hashes[I],'tempo zoom depends on seek order'); end;
      if Mode=1 then Need(Surface.LastUsedD2D,'tempo Direct2D');
      if (Size=0) and (Mode=1) then for I:=0 to 5 do begin
        Draw(Times[I]); Sheet.Canvas.StretchDraw(Rect((I mod 3)*480,(I div 3)*270,(I mod 3+1)*480,(I div 3+1)*270),B);
        case I of 0:Caption:='低速でズームイン'; 1:Caption:='高速は従来の画角'; 2:Caption:='低速へ戻り、待ってから寄る';
          else Caption:='球は跳ねずに連続打撃'; end;
        Sheet.Canvas.Font.Name:='Yu Gothic UI'; Sheet.Canvas.Font.Size:=10; Sheet.Canvas.Font.Color:=RGB(50,54,58);
        Sheet.Canvas.Brush.Style:=bsClear;
        Sheet.Canvas.TextOut((I mod 3)*480+10,(I div 3)*270+8,Caption);
        Sheet.Canvas.TextOut((I mod 3)*480+10,(I div 3)*270+28,Format('%.2fs / %.2fm/s / x%.2f',
          [Times[I],MelodyLength(P.Velocity(Times[I])),P.CameraZoom(Times[I])]));
        case I of 0:PNG(B,'slow-zoom.png'); 1:PNG(B,'fast-wide.png'); 2:PNG(B,'slow-return.png');
          else PNG(B,'rapid-'+IntToStr(I-2)+'.png'); end;
        Report.Add(Format('%s,%s,%s',[FloatToStr(Times[I],TFormatSettings.Invariant),
          FloatToStr(MelodyLength(P.Velocity(Times[I])),TFormatSettings.Invariant),FloatToStr(P.CameraZoom(Times[I]),TFormatSettings.Invariant)]));
      end;
    end;
    PNG(Sheet,'tempo-and-zoom.png'); Report.SaveToFile(TPath.Combine(Folder,'tempo-frames.csv'),TEncoding.UTF8);
  finally Report.Free; Surface.Free; Sheet.Free; B.Free; P.Free; A.Free; end;
end;

procedure CheckLongDense;
var A,R:TRhythmAudio; P,Q:TMelodyPlan; Ref:TRhythmPlanRef; Path,ReportName:string; Size,RandomState:Int64; I:Integer; Gap:Double;
  function NextValue:Double;
  begin RandomState:=(RandomState*48271) mod 2147483647; Result:=RandomState/2147483647; end;
begin
  Gap:=0.04; ReportName:='long-dense.json';
  if ParamStr(2)='35ms' then begin Gap:=0.035; ReportName:='long-dense-35ms.json'; end;
  // 共通PCM上限512MiB/float/44100Hzの内側で、ほぼ最長の冷復元も検査する。
  A:=Audio(3043,Gap); RandomState:=19;
  for I:=0 to High(A.Hits) do begin
    A.Hits[I].Strength:=NextValue; A.Hits[I].Lane:=NextValue; A.Hits[I].Flight:=0.1+NextValue;
  end;
  P:=BuildMelodyPlan(A); Q:=nil; R:=nil;
  try
    Need(Length(P.Bars)>12000,'long dense music has insufficient real strikes');
    Ref:=NewPlanRef(A.Key,50,0,rsMelodyBall); Ref.SourceRevision:=A.SourceRevision; SaveMelodyPlan(P,A,Ref);
    Path:=TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'SYNC_RhythmShooter\Plans\'+Ref.Key+'.json');
    Size:=TFile.GetSize(Path); Need(Size<=32*1024*1024,'long dense plan exceeds shared prepared file limit');
    R:=LoadMelodyAudio(Ref,A.Source,0); Q:=LoadMelodyPlan(Ref,R,0);
    Need(Length(R.PCM)=0,'long dense cold load decodes PCM');
    for I:=0 to 100 do begin
      Need(P.Position(I*30).X=Q.Position(I*30).X,'long dense saved X');
      Need(P.Position(I*30).Y=Q.Position(I*30).Y,'long dense saved Y');
      Need(P.CameraZoom(I*30)=Q.CameraZoom(I*30),'long dense saved zoom');
      Need(A.Hits[(Length(A.Hits)-1)*I div 100].Strength=R.Hits[(Length(A.Hits)-1)*I div 100].Strength,'long dense saved strength');
      Need(A.Hits[(Length(A.Hits)-1)*I div 100].Lane=R.Hits[(Length(A.Hits)-1)*I div 100].Lane,'long dense saved lane');
      Need(A.Hits[(Length(A.Hits)-1)*I div 100].Flight=R.Hits[(Length(A.Hits)-1)*I div 100].Flight,'long dense saved flight');
    end;
    TFile.WriteAllText(TPath.Combine(Folder,ReportName),Format('{"duration":3043,"gap":%s,"strikes":%d,"spans":%d,"bytes":%d,"checks":%d}',
      [FloatToStr(Gap,TFormatSettings.Invariant),Length(P.Bars),Length(P.Spans),Size,Checks]),TEncoding.UTF8);
    WriteLn('Long dense PASS: strikes=',Length(P.Bars),' spans=',Length(P.Spans),' bytes=',Size);
  finally R.Free; Q.Free; P.Free; A.Free; end;
end;

procedure CheckPhraseDrawing;
const Widths:array[0..2]of Integer=(960,540,1280); Heights:array[0..2]of Integer=(540,960,720);
  Times:array[0..5]of Double=(6,12,20,28.5,36,44);
  Captions:array[0..5]of string=('段差へ落下して打撃','緩いレールと連続シーソー','圧縮バネと落下','受け面で左へ切り替え','左へ進む連続打撃','水平な段差へ戻る');
var A,SlowAudio:TRhythmAudio; P,SlowPlan:TMelodyPlan; B,Sheet:TBitmap; Surface:TAnimationRenderSurface; F:TAnimationFrame;
  Hashes:array[0..5]of string; I,Size,Mode:Integer; Rows:TStringList; S:TMelodySpan; D,V,Angle:Double;
  procedure Draw(T:Double);
  begin
    F.Time:=T; F.Width:=B.Width; F.Height:=B.Height; F.BackgroundOnly:=False;
    Surface.BeginFrame(B); DrawMelodyBall(Surface,P,F); Need(Surface.EndFrame,'phrase surface'); Inc(Frames);
  end;
begin
  A:=Audio(64,0.04); P:=BuildMelodyPlan(A); B:=TBitmap.Create; Sheet:=TBitmap.Create;
  Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0)); Rows:=TStringList.Create;
  try
    B.PixelFormat:=pf32bit; Sheet.PixelFormat:=pf32bit; Sheet.SetSize(1440,540);
    Rows.Add('time,section,kind,speed,direction');
    for Size:=0 to 2 do for Mode:=0 to 1 do begin
      B.SetSize(Widths[Size],Heights[Size]); Surface.UseD2D:=Mode=1;
      for I:=0 to 5 do begin Draw(Times[I]); Hashes[I]:=Hash(B); end;
      for I:=5 downto 0 do begin Draw(Times[I]); Need(Hash(B)=Hashes[I],'phrase reverse seek'); end;
      if Mode=1 then Need(Surface.LastUsedD2D,'phrase Direct2D');
      if (Size=0) and (Mode=1) then for I:=0 to 5 do begin
        Draw(Times[I]); Sheet.Canvas.StretchDraw(Rect((I mod 3)*480,(I div 3)*270,(I mod 3+1)*480,(I div 3+1)*270),B);
        Sheet.Canvas.Font.Name:='Yu Gothic UI'; Sheet.Canvas.Font.Size:=10; Sheet.Canvas.Font.Color:=RGB(50,54,58); Sheet.Canvas.Brush.Style:=bsClear;
        Sheet.Canvas.TextOut((I mod 3)*480+10,(I div 3)*270+8,Captions[I]);
        Sheet.Canvas.TextOut((I mod 3)*480+10,(I div 3)*270+28,Format('%.2fs / %.2fm/s',[Times[I],MelodyLength(P.Velocity(Times[I]))]));
        PNG(B,'phrase-'+IntToStr(I)+'.png');
        Rows.Add(Format('%s,%d,%d,%s,%d',[FloatToStr(Times[I],TFormatSettings.Invariant),P.SectionAt(Times[I]),
          Ord(P.Sections[P.SectionAt(Times[I])].Kind),FloatToStr(MelodyLength(P.Velocity(Times[I])),TFormatSettings.Invariant),
          P.Spans[P.SpanAt(Times[I])].Direction]));
      end;
    end;
    PNG(Sheet,'phrase-variety.png'); Rows.SaveToFile(TPath.Combine(Folder,'phrase-frames.csv'),TEncoding.UTF8);
    SlowAudio:=Audio(64,0.24); SlowPlan:=BuildMelodyPlan(SlowAudio);
    try
      B.SetSize(960,540); Surface.UseD2D:=True; F.Time:=12; F.Width:=960; F.Height:=540;
      S:=SlowPlan.Spans[SlowPlan.SpanAt(12)]; MelodyTravel(S,12-S.Start,D,V); Angle:=S.Theta+S.Curvature*D;
      Need((S.Motion=mmRolling) and MelodyHasRail(S.Kind) and (Abs(Angle)<0.12),'slow gentle preview');
      Surface.BeginFrame(B); DrawMelodyBall(Surface,SlowPlan,F); Need(Surface.EndFrame,'slow gentle surface'); Inc(Frames);
      PNG(B,'slow-gentle.png');
      TFile.WriteAllText(TPath.Combine(Folder,'slow-gentle.csv'),Format('time,speed,angleDegrees%s12,%s,%s%s',
        [sLineBreak,FloatToStr(V,TFormatSettings.Invariant),FloatToStr(Angle*180/Pi,TFormatSettings.Invariant),sLineBreak]),TEncoding.UTF8);
    finally SlowPlan.Free; SlowAudio.Free; end;
  finally Rows.Free; Surface.Free; Sheet.Free; B.Free; P.Free; A.Free; end;
end;

begin
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'PhrasesEvidence'); ForceDirectories(Folder);
    if ParamStr(1)='LongDenseOnly' then begin
      Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'TempoLongEvidence'); ForceDirectories(Folder);
      if ParamStr(2)='35ms' then begin
        Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'TempoLong35Evidence'); ForceDirectories(Folder);
      end;
    end;
    SourceFile:=TPath.Combine(Folder,'synthetic-source.identity'); TFile.WriteAllText(SourceFile,'No audio playback.',TEncoding.UTF8);
    if ParamStr(1)='LongDenseOnly' then begin CheckLongDense; Exit; end;
    if ParamStr(1)='TempoOnly' then begin CheckTempo; CheckZoom; WriteLn('Tempo and zoom PASS'); Exit; end;
    if ParamStr(1)='PhrasesOnly' then begin CheckPhrases; WriteLn('Phrases PASS'); Exit; end;
    if (ParamCount=0) or (ParamStr(1)<>'RenderOnly') then begin CheckPlans; CheckCamera; CheckTempo; CheckPhrases; CheckZoom; end;
    CheckDrawing; CheckTempoDrawing; CheckPhraseDrawing;
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"frames":%d,"strikes":%d,"falls":%d,"springs":%d,"laterRails":%d,"hammers":%d,"steps":%d,"leftDownSpans":%d,"turns":%d,"maxForceError":%s,"maxEnergyGain":%s,"maxSpeed":%s,"cameraNewResidual":%s,"cameraOldResidual":%s,"denseFastSpeed":%s,"denseSlowSpeed":%s,"denseMinCoverage":%s,"zoomMaximum":%s,"zoomCloseTransitions":%d,"phraseChanges":%d,"estimatedMeterCases":%d,"maxWoodRun":%s,"maxWoodFraction":%s,"stableSlowSamples":%d,"stableSlowAngle":%s}',
      [Checks,Frames,Impacts,Falls,Springs,RecurringRails,Hammers,Steps,LeftRuns,Turns,FloatToStr(MaxForceError,TFormatSettings.Invariant),
       FloatToStr(MaxEnergyGain,TFormatSettings.Invariant),FloatToStr(MaxSpeed,TFormatSettings.Invariant),
       FloatToStr(CameraNewResidual,TFormatSettings.Invariant),FloatToStr(CameraOldResidual,TFormatSettings.Invariant),
       FloatToStr(DenseFastSpeed,TFormatSettings.Invariant),FloatToStr(DenseSlowSpeed,TFormatSettings.Invariant),
       FloatToStr(DenseMinCoverage,TFormatSettings.Invariant),FloatToStr(ZoomMaximum,TFormatSettings.Invariant),ZoomCloseTransitions,
       PhraseChanges,EstimatedMeters,FloatToStr(MaxWoodRun,TFormatSettings.Invariant),FloatToStr(MaxWoodFraction,TFormatSettings.Invariant),
       StableSlowSamples,FloatToStr(StableSlowAngle,TFormatSettings.Invariant)]),TEncoding.UTF8);
    WriteLn('Melody mechanisms PASS: ',Checks,' checks, ',Frames,' frames; strikes=',Impacts,' falls=',Falls);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message); ExitCode:=1; end; end;
end.
