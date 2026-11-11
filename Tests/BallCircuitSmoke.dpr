program BallCircuitSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Classes,System.Hash,System.IOUtils,Vcl.Graphics,Vcl.Imaging.pngimage,
  RhythmAudio,RhythmBallCircuitPlan,RhythmBallCircuitScene,RhythmBallGeometry,RhythmStyles,RhythmProduct,RhythmPlanRef,RhythmPaths,
  RhythmAnimation,RhythmRenderSurface,RhythmImageBank,RhythmBallPlan,RhythmBallScene;
var Audio,Meta:TRhythmAudio;Plan,Again,Cold:TBallCircuitPlan;Wrap,RestoredWrap:TRhythmBallPlan;Animation:TBallAnimation;Ref:TRhythmPlanRef;I,K,C,Backend:Integer;
  Gap,Goal,Clock,MinX,MaxX,MinY,MaxY,Travel,Longest,Fastest,ArmDegrees,LoopDegrees,Held:Double;P,Q:TBallPoint;F:TAnimationFrame;Surface:TAnimationRenderSurface;Image:TBitmap;PNG:TPngImage;Rejected:Boolean;
  Counts:array[TCircuitMotion] of Integer;O:TCircuitObject;R:TCircuitSegment;SourceFile,Hash,OutFolder:string;Id:TGUID;Info:TWin32FileAttributeData;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
function ImageHash:string;
var M:TMemoryStream;B:TBytes;H:THashSHA2;
begin M:=TMemoryStream.Create;try Image.SaveToStream(M);SetLength(B,M.Size);M.Position:=0;M.ReadBuffer(B[0],Length(B));H:=THashSHA2.Create;H.Update(B);Result:=H.HashAsString;finally M.Free;end;end;
procedure Render(Time:Double;Direction:Integer;const Name:string='');
begin
  F.Time:=Time;F.Width:=1280;F.Height:=720;F.Direction:=Direction;if Direction=1 then begin F.Width:=720;F.Height:=1280;end;Image.SetSize(F.Width,F.Height);
  Surface.BeginFrame(Image);DrawBallCircuit(Plan,Surface,F);Surface.EndFrame;
  if Name<>'' then begin PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(OutFolder,Name+'.png'));end;
end;
begin
  Audio:=nil;Meta:=nil;Plan:=nil;Again:=nil;Cold:=nil;Surface:=nil;Image:=nil;PNG:=nil;Wrap:=nil;RestoredWrap:=nil;Animation:=nil;
  try
    ConfigureRhythmProduct('SYNC_RhythmBall','Circuit native test',rsBall);Need((StylePlanVersion(rsBall)=6) and CompatiblePlanVersion(rsBall,4) and CompatiblePlanVersion(rsBall,5),'Style compatibility');
    OutFolder:=TPath.Combine(ExtractFilePath(ParamStr(0)),'Frames');ForceDirectories(OutFolder);Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0));Surface.UseD2D:=False;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;PNG:=TPngImage.Create;
    for C:=0 to 9 do begin
      Goal:=20;Gap:=0.16;case C of 1:begin Goal:=40;Gap:=0.60;end;2:begin Goal:=8;Gap:=0.008;end;3:begin Goal:=0.1;Gap:=0.001;end;4:begin Goal:=3000;Gap:=0.72;end;5:begin Goal:=60;Gap:=2.4;end;6:begin Goal:=0;Gap:=1;end;7:begin Goal:=3000;Gap:=0.030001;end;end;
      Audio:=TRhythmAudio.Create;Audio.Duration:=Max(0.1,Goal+0.8);Audio.SoundEnd:=Goal;Audio.Sensitivity:=50;CreateGUID(Id);Audio.Key:=THashSHA2.GetHashString(GUIDToString(Id));
      SourceFile:=TPath.Combine(CacheFolder,GUIDToString(Id)+'.identity');TFile.WriteAllText(SourceFile,'circuit native fixture',TEncoding.UTF8);Audio.Source:=SourceFile;
      if not GetFileAttributesEx(PChar(SourceFile),GetFileExInfoStandard,@Info) then RaiseLastOSError;
      Audio.SourceRevision:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
      if Goal>0 then begin SetLength(Audio.Hits,Floor((Goal-0.05)/Gap)+1);for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=0.05+I*Gap;Audio.Hits[I].Strength:=0.85;end;end;
      if C=8 then for I:=0 to High(Audio.Hits) do begin Audio.Hits[I].Time:=(I div 3)*0.16;Audio.Hits[I].Strength:=(I mod 11)/10;end;
      if C=9 then for I:=0 to High(Audio.Hits) do Audio.Hits[I].Strength:=(I mod 11)/10;
      Plan:=TBallCircuitPlan.Build(Audio,nil);Again:=TBallCircuitPlan.Build(Audio,nil);Need(Plan.PulseCount=Length(Audio.Hits),'Lost source accents');Need((Plan.NodeCount=Again.NodeCount) and (Plan.ObjectCount=Again.ObjectCount),'Planning determinism');
      FillChar(Counts,SizeOf(Counts),0);for I:=0 to Plan.SegmentCount-1 do begin R:=Plan.Segment[I];Inc(Counts[R.Kind]);if R.Kind=cmLoop then begin Need(Abs(Abs(R.Sweep)-2*Pi)<1E-8,'Incomplete loop');Need(BallLength(BallSub(CircuitPoint(R,R.First),CircuitPoint(R,R.Last)))<1E-8,'Loop discontinuity');end;end;
      if C in [0,1,4,5] then begin for K:=Ord(Low(TCircuitMotion)) to Ord(High(TCircuitMotion)) do Need(Counts[TCircuitMotion(K)]>0,'Missing real gimmick '+IntToStr(K));end;
      MinX:=10;MinY:=10;MaxX:=-10;MaxY:=-10;
      for I:=0 to 400 do begin Clock:=Plan.EndTime*I/400;P:=Plan.PositionAt(Clock);MinX:=Min(MinX,P.X);MaxX:=Max(MaxX,P.X);MinY:=Min(MinY,P.Y);MaxY:=Max(MaxY,P.Y);end;
      if Goal>=20 then Need((MaxX-MinX>1.2) and (MaxY-MinY>0.55),'Movement still confined to narrow table');
      for I:=0 to Plan.PulseCount-1 do begin Need(Plan.Pulse[I].Time=Audio.Hits[I].Time,'Pulse timing drift');O:=Plan.Obj[Plan.Pulse[I].ObjectIndex];P:=Plan.PositionAt(O.Time);Need(Abs(BallLength(BallSub(P,O.Point))-CIRCUIT_RADIUS)<1E-7,'Contact point does not touch ball');end;
      Ref:=NewPlanRef(Audio.Key,50,0,rsBall);Ref.SourceRevision:=Audio.SourceRevision;Plan.Save(Ref);Meta:=TBallCircuitPlan.LoadAudioMetadata(Ref,SourceFile,0);Need(Length(Meta.PCM)=0,'PCM required');Cold:=TBallCircuitPlan.Load(Ref,Meta,0);
      for I:=0 to 127 do begin Clock:=(Goal+2)*((I*73) mod 131)/131;P:=Plan.PositionAt(Clock);Q:=Cold.PositionAt(Clock);Need(BallLength(BallSub(P,Q))<1E-8,'Cold random seek changed path');end;
      if C=0 then begin
        Longest:=0;Fastest:=0;ArmDegrees:=0;LoopDegrees:=0;Held:=0;
        for I:=0 to Plan.SegmentCount-1 do begin R:=Plan.Segment[I];Travel:=BallLength(BallSub(R.D,R.A));if R.Kind in [cmLine,cmLaunch] then begin Longest:=Max(Longest,Travel);Fastest:=Max(Fastest,Travel/Max(1E-8,R.Last-R.First));end;
          if R.Kind=cmArm then ArmDegrees:=Max(ArmDegrees,Abs(R.Sweep)*180/Pi);if R.Kind=cmLoop then LoopDegrees:=Max(LoopDegrees,Abs(R.Sweep)*180/Pi);
          if R.Kind=cmHold then begin P:=CircuitPoint(R,R.First+(R.Last-R.First)*0.25);Q:=CircuitPoint(R,R.First+(R.Last-R.First)*0.75);Need(BallLength(BallSub(P,Q))<1E-12,'Charge cup did not catch');Held:=Max(Held,R.Last-R.First);end;
          if R.Kind=cmLaunch then begin P:=CircuitPoint(R,R.First+(R.Last-R.First)*0.25);Q:=CircuitPoint(R,R.First+(R.Last-R.First)*0.75);Need(Abs(BallLength(BallSub(P,R.A))-Travel*0.0625)<1E-9,'Launch failed to accelerate');Need(Abs(BallLength(BallSub(Q,R.A))-Travel*0.5625)<1E-9,'Launch acceleration changed');end;
        end;
        Writeln(Format('motion: longest straight %.1fpx mean speed %.1fpx/s arm %.0fdeg loop %.0fdeg hold %.3fs',[Longest*720,Fastest*720,ArmDegrees,LoopDegrees,Held]));
        for Backend:=0 to 1 do begin Surface.UseD2D:=Backend=1;Render(2.1,0);Hash:=ImageHash;Render(Plan.EndTime+10,0);Render(2.1,0);Need(ImageHash=Hash,'Frame depends on seek order');Writeln('backend='+IntToStr(Backend)+' d2d='+BoolToStr(Surface.LastUsedD2D,True));end;
        Surface.UseD2D:=False;
        for I:=0 to Plan.SegmentCount-1 do begin R:=Plan.Segment[I];if I>10 then Break;Clock:=(R.First+R.Last)/2;Render(Clock,0,'route-'+IntToStr(I)+'-'+IntToStr(Ord(R.Kind)));end;
        for I:=1 to Plan.NodeCount-1 do if Plan.Node[I].Kind=cnBumper then begin Render(Plan.Node[I].Time-0.02,0,'bumper-before');Render(Plan.Node[I].Time+0.10,0,'bumper-after');Break;end;
        Render(3.2,1,'portrait');
        Wrap:=TRhythmBallPlan.Build(Audio);Need(Wrap.Circuit<>nil,'Public Ball plan still uses narrow board');Wrap.Save(Ref);RestoredWrap:=TRhythmBallPlan.Load(Ref,Meta,0);
        Need((RestoredWrap.Circuit<>nil) and (RestoredWrap.PulseCount=Plan.PulseCount),'Public cold Ball wrapper lost Circuit');
        Animation:=TBallAnimation.Create;Animation.Audio:=Meta;Animation.SetReference(Ref);F.Time:=2.1;F.Width:=1280;F.Height:=720;F.Direction:=0;Animation.Prepare(F);Need(Animation.Notice='','Ball scene did not load version6');
        Image.SetSize(1280,720);Surface.BeginFrame(Image);Animation.Draw(Surface,F);Surface.EndFrame;Hash:=ImageHash;Render(2.1,0);Need(ImageHash=Hash,'Public Ball scene differs from direct circuit');
        FreeAndNil(Animation);FreeAndNil(RestoredWrap);FreeAndNil(Wrap);
      end;
      Writeln(Format('case=%d events=%d nodes=%d objects=%d routes=%d bounds=%.3f..%.3f/%.3f..%.3f',[C,Plan.PulseCount,Plan.NodeCount,Plan.ObjectCount,Plan.SegmentCount,MinX,MaxX,MinY,MaxY]));
      FreeAndNil(Cold);FreeAndNil(Meta);FreeAndNil(Again);FreeAndNil(Plan);FreeAndNil(Audio);
    end;
    Audio:=TRhythmAudio.Create;Audio.Duration:=1;Audio.SoundEnd:=1;Rejected:=False;
    try Plan:=TBallCircuitPlan.Build(Audio,function:Boolean begin Result:=True;end);except on E:EAbort do Rejected:=True;end;Need(Rejected,'Cancellation ignored');
    SetLength(Audio.Hits,2);Audio.Hits[0].Time:=0.5;Audio.Hits[1].Time:=0.2;Rejected:=False;
    try Plan:=TBallCircuitPlan.Build(Audio,nil);except on E:Exception do Rejected:=True;end;Need(Rejected,'Unsorted audio accepted');FreeAndNil(Audio);
    Writeln('BallCircuitSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Animation.Free;RestoredWrap.Free;Wrap.Free;PNG.Free;Image.Free;Surface.Free;Cold.Free;Again.Free;Plan.Free;Meta.Free;Audio.Free;
end.
