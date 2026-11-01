program RunnerPlanSmoke;
{$APPTYPE CONSOLE}
uses
  RhythmBombPlan in '..\Source\BombAction\RhythmBombPlan.pas',
  RhythmBombScene in '..\Source\BombAction\RhythmBombScene.pas',
  RhythmRacePlan in '..\Source\Race\RhythmRacePlan.pas',
  RhythmRaceScene in '..\Source\Race\RhythmRaceScene.pas',
  Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,Vcl.Graphics,
  RhythmAudio,RhythmRunnerPlan,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmSettings,RhythmScene,RhythmPaths;
var Audio,Meta:TRhythmAudio;Plan,Again:TRunnerPlan;Ref:TRhythmPlanRef;State,Cold:TRhythmSettings;
  Renderer:TRhythmRenderer;Image:TBitmap;I,J,C:Integer;S:TRunnerStep;Pad:TRunnerPlatform;P,Q:TRunnerPoint;
  Found,Rejected:Boolean;Gap,T,D:Double;Path,Hash:string;Id:TGUID;Info:TWin32FileAttributeData;
  Piece,Other:TRunnerSetPiece;SavedPieceCount:Integer;PieceSignature,SavedPieceSignature:string;L,R,Y,ContactDistance:Double;Cut:TRunnerCut;Grip,Tip:TRunnerPoint;SavedCuts,SavedRuns:Integer;
procedure Require(Value:Boolean;const Text:string);begin if not Value then raise Exception.Create(Text);end;
function ImageHash:string;
var M:TMemoryStream;Bytes:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(Bytes,M.Size);M.Position:=0;M.ReadBuffer(Bytes[0],Length(Bytes));H:=THashSHA2.Create;H.Update(Bytes);Result:=H.HashAsString;finally M.Free;end;end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Again:=nil;Renderer:=nil;Image:=nil;
  try
    ConfigureRhythmProduct('SYNC_RhythmRunner','リズムランナー',rsRunner);
    Require((Ord(rsRunner)=3) and (Ord(rsFireworks)=2) and (StylePlanVersion(rsBall)=6),'Existing style contract changed');
    Require(TRhythmSettings.Defaults.Style=rsRunner,'Runner default missing');
    Require((StylePlanVersion(rsRunner)=5) and CompatiblePlanVersion(rsRunner,1) and CompatiblePlanVersion(rsRunner,2) and CompatiblePlanVersion(rsRunner,3) and CompatiblePlanVersion(rsRunner,4) and
      not CompatiblePlanVersion(rsRunner,0) and (StylePlanVersion(rsShooting)=1) and
      (StylePlanVersion(rsFireworks)=3),'Runner version compatibility changed');
    Require(TRhythmSettings.TryJSON('{"schema":1,"music":"old.wav"}',State) and (State.Style=rsShooting),'Legacy JSON changed style');
    for C:=0 to 5 do begin
      case C of 0:Gap:=0.18;1:Gap:=0.7;2:Gap:=3;3:Gap:=0.09;4:Gap:=0.50;else Gap:=1.10;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=22;Audio.Sensitivity:=50;SetLength(Audio.Envelope,2200);
      if C>=4 then begin Audio.Duration:=68;SetLength(Audio.Envelope,6800);end;
      for I:=0 to 1999 do Audio.Envelope[I]:=0.5;SetLength(Audio.Hits,Floor(19/Gap)+1);
      if C>=4 then begin for I:=2000 to 6399 do Audio.Envelope[I]:=0.5;SetLength(Audio.Hits,Floor(63/Gap)+1);end;
      for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.5+I*Gap;Audio.Hits[I].Strength:=0.3+(I mod 5)*0.175;end;
      if C>=4 then for I:=0 to High(Audio.Hits) do Audio.Hits[I].Strength:=0.8;
      if C=3 then begin Audio.Hits[0].Time:=0;Audio.Hits[1].Time:=0;end;
      Audio.UpdateSoundBounds;CreateGUID(Id);Path:=TPath.Combine(CacheFolder,GUIDToString(Id)+'.identity');
      TFile.WriteAllText(Path,GUIDToString(Id),TEncoding.UTF8);Audio.Source:=Path;Audio.Key:=THashSHA2.GetHashString(GUIDToString(Id));
      if not GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Info) then RaiseLastOSError;
      Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
      Plan:=TRunnerPlan.Build(Audio);Again:=TRunnerPlan.Build(Audio);
      Require(Plan.PulseCount=Length(Audio.Hits),'Runner discarded valid accents');
      SavedPieceCount:=Plan.SetPieceCount;SavedCuts:=Plan.CutCount;SavedRuns:=Plan.SwordRunCount;SavedPieceSignature:='';
      if C=5 then Require(SavedPieceCount>=3,'Long sparse song has no repeated vaults');
      if C=4 then Require((Plan.SwordRunCount>0) and (Plan.CutCount>0) and (SavedPieceCount=0),'Continuous accents should become flat sword runs');
      if C<4 then Require(SavedPieceCount=0,'Short song forces set pieces');
      for I:=0 to Plan.SetPieceCount-1 do begin
        Piece:=Plan.SetPiece[I];Other:=Again.SetPiece[I];
        Require((Piece.Kind=Other.Kind) and (Piece.FirstStep=Other.FirstStep) and (Piece.LastStep=Other.LastStep),'Set-piece choice is not deterministic');
        Require((Plan.Step[Piece.FirstStep].Takeoff>=5) and (Plan.Step[Piece.LastStep].Time<=Plan.GoalTime-5),'Set piece hides entry or goal');
        if I>0 then Require(Plan.Step[Piece.FirstStep].Takeoff>=Plan.Step[Plan.SetPiece[I-1].LastStep].Time+10-1E-7,'Set pieces have no quiet interval');
        Require(Piece.Kind<>rkBounce,'New plans retain bounce chains');
        if C=5 then Require(Piece.Kind=rkVault,'Long gaps should form vaults');
        SavedPieceSignature:=SavedPieceSignature+Format('%d:%d:%d;',[Ord(Piece.Kind),Piece.FirstStep,Piece.LastStep]);
        if Piece.Kind=rkBounce then for J:=Piece.FirstStep to Piece.LastStep do
          Require(Abs(Plan.Step[J].Takeoff-Plan.Step[J-1].Time)<1E-7,'Bounce does not launch on the previous contact')
        else begin
          S:=Plan.Step[Piece.FirstStep];RunnerVaultBounds(S,L,R,Y);
          for J:=0 to 100 do begin
            T:=(L-0.085+(R-L+0.17)*J/100)/RUN_SPEED;P:=Plan.PositionAt(T);
            Require(P.Y+0.023<=Y+1E-7,'Vault silhouette intersects the obstacle');
          end;
        end;
      end;
      for I:=0 to Plan.CutCount-1 do begin
        Cut:=Plan.Cut[I];Require(Cut.Time=Plan.Step[Cut.Step].Time,'Sword clock drift');P:=Plan.PositionAt(Cut.Time);Require(not P.Airborne,'Sword cut is airborne');
        Require(Plan.SwordAt(Cut.Time,Grip,Tip),'Sword missing');ContactDistance:=Hypot(Cut.X-Tip.X,Cut.Y-Tip.Y);
        Require((Abs(Tip.X-(Cut.X-0.020-RUN_SWORD_HALF))<1E-7) and (Abs(Tip.Y-Cut.Y)<=0.026+1E-7),'Blade does not touch armor');
        Require(Cut.Radius>=0.020,'Tiny enemy fallback');
      end;
      Require((Plan.GoalTime=Audio.SoundEnd) and (Plan.EndTime=Plan.GoalTime+RUN_EXIT),'Goal/ending is not based on whole-song sound end');
      for I:=0 to Plan.PulseCount-1 do Require(Plan.Pulse[I].Time=Audio.Hits[I].Time,'Contact time drifted');
      for I:=0 to Plan.Count-1 do begin
        S:=Plan.Step[I];P:=Plan.PositionAt(S.Time);Q:=Again.PositionAt(S.Time);
        Require((Abs(P.X-RUN_SPEED*S.Time)<1E-8) and (Abs(P.Y-S.Y)<1E-8),'Runner misses its landing');
        Require((P.X=Q.X) and (P.Y=Q.Y),'Runner is not deterministic');
        Found:=False;for J:=0 to Plan.PlatformCount-1 do begin Pad:=Plan.Platform[J];if (P.X>=Pad.Left-1E-8) and (P.X<=Pad.Right+1E-8) and (Abs(P.Y-Pad.Y)<1E-8) then Found:=True;end;
        Require(Found,'Landing has no platform');
        D:=S.Time-S.Takeoff;
        if D>0 then for J:=1 to 9 do begin
          T:=D*J/10;P:=Plan.PositionAt(S.Takeoff+T);
          Require(Abs(P.X-RUN_SPEED*(S.Takeoff+T))<1E-8,'Airborne horizontal motion changes direction');
          Require(Abs(P.Y-(S.StartY+S.Velocity*T+0.5*RUN_GRAVITY*T*T))<1E-8,'Jump is not ballistic');
        end;
      end;
      P:=Plan.PositionAt(Plan.GoalTime);Q:=Plan.PositionAt(Plan.GoalTime+1.3);Require(Q.X>P.X+1,'Runner does not leave toward the right');
      Ref:=NewPlanRef(Audio.Key,50,0,rsRunner);Ref.SourceRevision:=Audio.SourceRevision;Plan.Save(Ref,Audio);
      State:=TRhythmSettings.Defaults;State.Music:=Path;State.Plan:=Ref;State.Designs[8].Memo:='keep existing design';
      TFile.WriteAllText(Path+'.json',State.ToJSON,TEncoding.UTF8);
      Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Renderer.ConfigureStyle(rsRunner,Ref);Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);
      T:=2.75;if SavedPieceCount>0 then T:=(Plan.Step[Plan.SetPiece[0].FirstStep].Takeoff+Plan.Step[Plan.SetPiece[0].LastStep].Time)/2;
      Renderer.Render(Image,Audio,T,0);Hash:=ImageHash;
      FreeAndNil(Renderer);FreeAndNil(Plan);FreeAndNil(Again);FreeAndNil(Audio);
      Require(TRhythmSettings.TryJSON(TFile.ReadAllText(Path+'.json',TEncoding.UTF8),Cold) and (Cold.Plan.SourceRevision=Ref.SourceRevision),'Runner object settings were not restored');
      Meta:=TRunnerPlan.LoadAudioMetadata(Cold.Plan,Cold.Music,0);Require(Length(Meta.PCM)=0,'Cold runner restoration reads PCM');
      Plan:=TRunnerPlan.Load(Cold.Plan,Meta,0);Renderer:=TRhythmRenderer.Create;Renderer.UseD2D:=False;Renderer.ConfigureStyle(Cold.Style,Cold.Plan);
      Require((Plan.CutCount=SavedCuts) and (Plan.SwordRunCount=SavedRuns),'Cold load discarded sword score');
      Require(Plan.SetPieceCount=SavedPieceCount,'Cold load discarded set pieces');PieceSignature:='';
      for I:=0 to Plan.SetPieceCount-1 do begin Piece:=Plan.SetPiece[I];PieceSignature:=PieceSignature+Format('%d:%d:%d;',[Ord(Piece.Kind),Piece.FirstStep,Piece.LastStep]);end;
      Require(PieceSignature=SavedPieceSignature,'Cold load changed set-piece identity');
      Renderer.Render(Image,Meta,T,0);Require(ImageHash=Hash,'New instance changed the restored frame');
      Renderer.Render(Image,Meta,Plan.EndTime+1,0);Hash:=ImageHash;Renderer.Render(Image,Meta,Plan.EndTime+20,0);Require(ImageHash=Hash,'Runner moves after exit');
      Ref:=Cold.Plan;Ref.Digest:=StringOfChar('0',64);Rejected:=False;
      try Again:=TRunnerPlan.Load(Ref,Meta,0);except Rejected:=True;end;Require(Rejected,'Invalid content digest accepted');
      FreeAndNil(Renderer);FreeAndNil(Image);FreeAndNil(Plan);FreeAndNil(Meta);
    end;
    Audio:=TRhythmAudio.Create;Audio.Duration:=1;Audio.SoundEnd:=0;
    Plan:=TRunnerPlan.Build(Audio);Require((Plan.PulseCount=0) and (Plan.EndTime=0),'Silence generates running');FreeAndNil(Plan);
    Rejected:=False;try Plan:=TRunnerPlan.Build(Audio,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;
    Require(Rejected,'Cancellation ignored');
    Writeln('RunnerPlanSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Image.Free;Renderer.Free;Again.Free;Plan.Free;Meta.Free;Audio.Free;
end.
