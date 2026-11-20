program TrainPlanSmoke;
{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.Math, System.Classes, System.Hash, System.IOUtils,
  System.TypInfo, Vcl.Graphics, Vcl.Imaging.jpeg, Vcl.Imaging.pngimage,
  RhythmTrainPlan in '..\Source\Train\RhythmTrainPlan.pas',
  RhythmTrainScene in '..\Source\Train\RhythmTrainScene.pas',
  RhythmAudio, RhythmStyles, RhythmPlanRef, RhythmProduct, RhythmPaths, RhythmAnimation, RhythmImageBank;

var
  Checks: Integer;
  Evidence: string;

procedure Need(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
  Inc(Checks);
end;

function SyntheticAudio(const Name: string; Duration, Interval: Double): TRhythmAudio;
var
  I: Integer;
  Info: TWin32FileAttributeData;
begin
  Result := TRhythmAudio.Create;
  try
    Result.Source := TPath.Combine(Evidence,Name+'.identity');
    TFile.WriteAllText(Result.Source,Name,TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Result.Source),GetFileExInfoStandard,@Info),'Synthetic source stamp');
    Result.SourceRevision := IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+
      IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
    Result.Key := THashSHA2.GetHashString(Name);
    Result.Duration := Duration;
    Result.Sensitivity := 50;
    Result.HasHitDetails := True;
    if Interval>0 then begin
      Result.SoundEnd := Duration;
      SetLength(Result.Hits,Ceil(Duration/Interval));
      for I := 0 to High(Result.Hits) do begin
        Result.Hits[I].Time := I*Interval;
        Result.Hits[I].Strength := 0.24+0.07*(I mod 11);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function PixelHash(Image: TBitmap): string;
var
  Hash: THashSHA2;
  Y: Integer;
begin
  Hash := THashSHA2.Create;
  for Y := 0 to Image.Height-1 do
    Hash.Update(Image.ScanLine[Y]^,Image.Width*4);
  Result := Hash.HashAsString;
end;

function NewRenderer(Audio: TRhythmAudio; const Ref: TRhythmPlanRef): TAnimationRenderer;
var
  Scene: TTrainAnimation;
begin
  Scene := TTrainAnimation.Create;
  Scene.Audio := Audio;
  Scene.SetReference(Ref);
  Result := TAnimationRenderer.Create(Scene,TAnimationImageBank.Create(0));
end;

procedure CheckMotion(Plan,Cold: TTrainPlan; Audio: TRhythmAudio);
var
  C: TTrainCue;
  P,Q: TTrainPose;
  T,LastX,RoofStart,CameraX,CameraWidth,Blend,Reach,Joint,RoofX,ScreenX: Double;
  Block: TTrainObstacle;
  CarMin,CarMax: TArray<Double>;
  I,J,JumpCount,ObstacleCount,HitsBefore,HitsAfter,Runs,RunFrames,CarIndex,Traversed: Integer;
begin
  Need(Plan.Count=Cold.Count,'Cold cue count');
  Need(Plan.Synced=Cold.Synced,'Cold sync count');
  if Plan.Count=0 then Exit;
  Need(Plan.Cue[0].Time<0.82,'Boarding too late');
  JumpCount := 0;
  ObstacleCount := 0;
  HitsBefore := 0;
  HitsAfter := 0;
  for I := 0 to Plan.Count-1 do begin
    C := Plan.Cue[I];
    Need(C.Time=Cold.Cue[I].Time,'Cold time changed');
    if C.Source>=0 then begin
      Need(Abs(C.Time-Audio.Hits[C.Source].Time)<0.065,'Contact left the original onset neighborhood');
      if Length(Audio.PCM)=0 then Need(C.Time=Audio.Hits[C.Source].Time,'Synthetic onset shifted');
    end;
    P := Plan.PoseAt(C.Time);
    Need(Abs(P.X-C.ToX)<1E-8,'Contact position');
    if TrainRegularEnemy(C.Kind) or (C.Kind in [tmBossDuck,tmBossFinish]) then begin
      Need(Abs(P.Reach-1)<1E-8,'Strike lacks contact reach');
      Reach := TrainReach;
      if C.Kind=tmShot then Reach := TrainShotReach;
      Need(Abs(P.Y-Plan.RoofY(P.X+Reach))<1E-8,'Strike target on a different roof');
      if I<Plan.ImpactIndex then Inc(HitsBefore) else Inc(HitsAfter);
    end;
    if TrainObstacle(C,Block) then begin
      Inc(ObstacleCount);
      T := C.Start+(C.Time-C.Start)*(Block.Left-C.FromX)/(C.ToX-C.FromX);
      Q := Plan.PoseAt(T);
      Need(Q.Airborne and (Q.Y<Plan.RoofY(Q.X)-Block.Height-0.1),'Hero does not climb above the obstacle');
      T := C.Start+(C.Time-C.Start)*(Block.Right-C.FromX)/(C.ToX-C.FromX);
      Q := Plan.PoseAt(T);
      Need(Q.Airborne and (Q.Y<Plan.RoofY(Q.X)-Block.Height-0.1),'Hero lands on the obstacle');
    end;
    if C.Kind in [tmJump,tmTransfer,tmBossJump] then begin
      Inc(JumpCount);
      Need(Floor(C.ToX/TrainPitch)=Floor(C.FromX/TrainPitch)+1,'Jump did not cross a gap');
      Need(Abs(P.Y-Plan.RoofY(C.ToX))<1E-8,'Landing misses roof');
      Need(Plan.PoseAt((C.Start+C.Time)*0.5).Airborne,'Crossing is not a jump');
    end;
  end;
  Need((HitsBefore>=2*Plan.InitialCars) and (HitsAfter>=2*Plan.NextCars) and (JumpCount>=3),'Missing fight progression');
  Need(ObstacleCount=Plan.InitialCars+Plan.NextCars-1,'Missing roof obstacles');
  C := Plan.Cue[Plan.ImpactIndex];
  Joint := (Plan.InitialCars-1)*TrainPitch-TrainGap;
  Need(Abs(Plan.LeftNoseAt(C.Time)-Joint)<1E-8,'Left couplers miss');
  T := Plan.Cue[Plan.ImpactIndex-1].Finish;
  Need(Plan.LeftNoseAt(T+(C.Time-T)*0.43)<Joint-4.7,'Hero car did not separate');
  Plan.CollisionCamera(C.Time,CameraX,CameraWidth,Blend);
  Need(Blend>0.99,'Left camera was late');
  Need((Abs(CameraX-(Joint+TrainGap*0.5))<CameraWidth*0.5-0.45) and
    (Abs(CameraX-C.ToX)<CameraWidth*0.5-0.45),'Left coupling or hero left the shot');
  C := Plan.Cue[Plan.ImpactIndex+1];
  Need(Abs(Plan.RightRearAt(C.Time)-Plan.InitialCars*TrainPitch)<1E-8,'Right couplers miss');
  T := C.Time-Min(0.13,(C.Time-Plan.Cue[Plan.ImpactIndex].Time)*0.22);
  Plan.CollisionCamera(T,CameraX,CameraWidth,Blend);
  Need(Blend>0.99,'Right camera was late');
  Need((Abs(CameraX-(Plan.InitialCars*TrainPitch-TrainGap*0.5))<CameraWidth*0.5-0.45) and
    (Abs(CameraX-C.ToX)<CameraWidth*0.5-0.45),'Right coupling or hero left the shot');
  C := Plan.Cue[Plan.ImpactIndex+2];
  Need(Abs(Plan.RightRearAt(C.Time+0.01)-Plan.InitialCars*TrainPitch)<1E-8,'Right cars did not latch');
  C := Plan.Cue[Plan.ImpactIndex+3];
  Plan.CollisionCamera(C.Time,CameraX,CameraWidth,Blend);
  Need(Blend<0.22,'Roof framing not restored during transfer');
  Need(Plan.TravelAt(Plan.Cue[0].Time)=0,'Wheels moved during boarding');
  Need(Plan.TravelAt(Plan.Cue[0].Time+0.16)>0,'Train did not leave departure platform');
  Need(Plan.PoseAt(Plan.Arrival).Y=TrainPlatformY,'Station landing missing');
  Need(Plan.TravelAt(Plan.EndTime)=Plan.TravelAt(Plan.Arrival),'Train did not stop at station');

  LastX := Plan.PoseAt(0).X;
  Runs := 0;
  RunFrames := 0;
  SetLength(CarMin,Plan.InitialCars+Plan.NextCars-1);
  SetLength(CarMax,Length(CarMin));
  for I := 0 to High(CarMin) do CarMin[I] := 1;
  for I := 0 to 2000 do begin
    T := I*Plan.EndTime/2000;
    P := Plan.PoseAt(T);
    Need(P.X>=LastX-1E-8,'Hero moved backward');
    if ((T>Plan.Cue[0].Time+0.09) and (T<Plan.Cue[Plan.ImpactIndex-1].Time)) or
       ((T>Plan.Cue[Plan.ImpactIndex+3].Time+0.09) and (T<Plan.Cue[Plan.Count-2].Time)) then begin
      Inc(RunFrames);
      if P.X-LastX>1E-5 then Inc(Runs);
      CarIndex := Floor(P.X/TrainPitch);
      RoofX := P.X-CarIndex*TrainPitch;
      if (CarIndex>=0) and (CarIndex<Length(CarMin)) and (RoofX>1.8) and (RoofX<10.35) then begin
        ScreenX := 0.5+(P.X-Plan.RoofCameraX(T))/TrainRoofViewWidth;
        CarMin[CarIndex] := Min(CarMin[CarIndex],ScreenX);
        CarMax[CarIndex] := Max(CarMax[CarIndex],ScreenX);
      end;
    end;
    LastX := P.X;
    if (T>Plan.Cue[0].Time) and (T<Plan.Cue[Plan.Count-1].Start) then begin
      RoofStart := Floor(P.X/TrainPitch)*TrainPitch;
      if not P.Airborne then begin
        Need(P.X-RoofStart<=TrainCarWidth+1E-8,'Hero stood in a gap');
        Need(Abs(P.Y-Plan.RoofY(P.X))<1E-8,'Grounded hero above or below roof');
      end;
      if P.X-RoofStart<=TrainCarWidth then
        Need(P.Y<=Plan.RoofY(P.X)+1E-8,'Hero arc clips a roof');
    end;
    J := (I*733) mod 2001;
    T := J*Plan.EndTime/2000;
    P := Plan.PoseAt(T);
    Q := Cold.PoseAt(T);
    Need((P.X=Q.X) and (P.Y=Q.Y) and (P.Reach=Q.Reach) and (P.Crouch=Q.Crouch) and
      (Plan.RoofCameraX(T)=Cold.RoofCameraX(T)) and (Plan.TravelAt(T)=Cold.TravelAt(T)),'Cold seek state changed');
  end;
  if (Audio.Duration>=15) and (Audio.Duration<=100) then begin
    Need((RunFrames>0) and (Runs/RunFrames>0.84),'Too much idle time on the roofs');
    Traversed := 0;
    for I := 0 to High(CarMin) do
      if CarMax[I]-CarMin[I]>0.49 then Inc(Traversed);
    Need(Traversed>=Length(CarMin)-1,'Hero does not travel across the screen');
  end;
end;

procedure CheckRender(Audio,Meta: TRhythmAudio; const Ref: TRhythmPlanRef; Plan: TTrainPlan; const Name: string; ExportFrames: Boolean);
const
  Rate = 60;
var
  Renderer,Cold: TAnimationRenderer;
  Image: TBitmap;
  PNG: TPngImage;
  JPEG: TJPEGImage;
  C: TTrainCue;
  I,J,K: Integer;
  H,Frames: string;
  T,FrameTime: Double;
  Block: TTrainObstacle;
  procedure Snapshot(const Suffix: string; Time: Double);
  begin
    Renderer.Render(Image,Time,Ref.Direction);
    Need(Renderer.Notice='','Renderer plan load failed');
    PNG.Assign(Image);
    PNG.SaveToFile(TPath.Combine(Evidence,Name+'-'+Suffix+'.png'));
  end;

  procedure CheckTrackEdges(Time: Double);
  var Y: Integer;

    function RailSide(Color: TColor): Boolean;
    var C: COLORREF;
    begin
      C := COLORREF(ColorToRGB(Color));
      Result := Abs(Integer(GetRValue(C))-61)+Abs(Integer(GetGValue(C))-66)+
        Abs(Integer(GetBValue(C))-69)<34;
    end;

  begin
    Renderer.Render(Image,Time,Ref.Direction);
    for Y := 0 to Image.Height-1 do
      if RailSide(Image.Canvas.Pixels[1,Y]) and
         RailSide(Image.Canvas.Pixels[Image.Width-2,Y]) then Exit;
    Need(False,'Rail does not extend beyond both sides of the frame');
  end;

begin
  Renderer := nil;
  Cold := nil;
  Image := nil;
  PNG := nil;
  JPEG := nil;
  try
    Renderer := NewRenderer(Audio,Ref);
    Cold := NewRenderer(Meta,Ref);
    Image := TBitmap.Create;
    Image.PixelFormat := pf32bit;
    PNG := TPngImage.Create;
    if Ref.Direction=0 then Image.SetSize(960,540) else Image.SetSize(540,960);
    for J := 0 to 1 do begin
      Renderer.UseD2D := J=1;
      Cold.UseD2D := J=1;
      for K := 0 to 11 do begin
        T := Plan.EndTime*((K*7) mod 13)/13;
        Renderer.Render(Image,T,Ref.Direction);
        Need(Renderer.Notice='','Renderer plan load failed');
        if J=1 then Need(Renderer.LastUsedD2D,'Expected Direct2D frame');
        H := PixelHash(Image);
        Renderer.Render(Image,Plan.EndTime-T,Ref.Direction);
        Renderer.Render(Image,T,Ref.Direction);
        Need(H=PixelHash(Image),'Shuffled render changed');
        Cold.Render(Image,T,Ref.Direction);
        Need(H=PixelHash(Image),'PCM-less render changed');
      end;
    end;
    Snapshot('opening',0);
    CheckTrackEdges(0);
    Snapshot('board',Plan.Cue[0].Time-0.10);
    Snapshot('first-hit',Plan.Cue[1].Time);
    Snapshot('roof-run',(Plan.Cue[0].Finish+Plan.Cue[1].Start)*0.5);
    for I := 0 to Plan.Count-1 do
      if TrainObstacle(Plan.Cue[I],Block) then begin
        C := Plan.Cue[I];
        Snapshot('roof-obstacle',(C.Start+C.Time)*0.5);
        Break;
      end;
    for I := 0 to Plan.Count-1 do
      if Plan.Cue[I].Kind=tmShot then begin
        C := Plan.Cue[I];
        FrameTime := Min(0.125,(C.Time-C.Start)*0.64)/2;
        Snapshot('projectile',C.Time-FrameTime);
        Break;
      end;
    C := Plan.Cue[Plan.ImpactIndex];
    Snapshot('detached',C.Time-0.44);
    Snapshot('impact-left',C.Time+0.065);
    C := Plan.Cue[Plan.ImpactIndex+1];
    Snapshot('impact-right',C.Time+0.065);
    C := Plan.Cue[Plan.ImpactIndex+2];
    Snapshot('couple',C.Time+0.055);
    C := Plan.Cue[Plan.ImpactIndex+3];
    Snapshot('transfer',(C.Start+C.Time)*0.5);
    C := Plan.Cue[Plan.Count-4];
    Snapshot('boss-jump',TrainThreatTime(C)+0.14);
    C := Plan.Cue[Plan.Count-3];
    Snapshot('boss-duck',TrainThreatTime(C)+0.07);
    Snapshot('boss-hit',Plan.Cue[Plan.Count-2].Time+0.043);
    Snapshot('station',Plan.EndTime);
    CheckTrackEdges(Plan.EndTime);
    if ExportFrames then begin
      Frames := TPath.Combine(Evidence,'frames');
      ForceDirectories(Frames);
      TFile.WriteAllBytes(TPath.Combine(Evidence,'audio.pcm'),Audio.PCM);
      JPEG := TJPEGImage.Create;
      JPEG.CompressionQuality := 87;
      for I := 0 to Ceil(Max(Plan.EndTime,Audio.Duration)*Rate)-1 do begin
        Renderer.Render(Image,I/Rate,Ref.Direction);
        JPEG.Assign(Image);
        JPEG.SaveToFile(TPath.Combine(Frames,Format('frame-%.5d.jpg',[I])));
      end;
    end;
  finally
    JPEG.Free;
    PNG.Free;
    Image.Free;
    Cold.Free;
    Renderer.Free;
  end;
end;

procedure Exercise(Audio: TRhythmAudio; const Name: string; Render,ExportFrames: Boolean);
var
  Plan,Cold: TTrainPlan;
  Meta: TRhythmAudio;
  Ref: TRhythmPlanRef;
  Csv: TStringList;
  C: TTrainCue;
  I,Direction: Integer;
  Detector, SourceKind: string;
begin
  Plan := nil;
  Cold := nil;
  Meta := nil;
  Csv := TStringList.Create;
  try
    Plan := TTrainPlan.Build(Audio);
    if Audio.SoundEnd=0 then Need(Plan.Count=0,'Silent source added a battle');
    Csv.Add('event,start,contact,end,source,source_type,detector_time,first_frame_60fps,from_x,to_x');
    for I := 0 to Plan.Count-1 do begin
      C := Plan.Cue[I];
      Detector := '';
      SourceKind := 'visual';
      if C.Source>=0 then begin
        Detector := Format('%.6f',[Audio.Hits[C.Source].Time],TFormatSettings.Invariant);
        SourceKind := 'detector';
      end
      else if C.Source<-1 then SourceKind := 'opening_pcm';
      Csv.Add(Format('%s,%.6f,%.6f,%.6f,%d,%s,%s,%d,%.3f,%.3f',
        [GetEnumName(TypeInfo(TTrainMove),Ord(C.Kind)),C.Start,C.Time,C.Finish,C.Source,
        SourceKind,Detector,Ceil(C.Time*60),C.FromX,C.ToX],TFormatSettings.Invariant));
    end;
    Csv.SaveToFile(TPath.Combine(Evidence,Name+'.csv'),TEncoding.UTF8);
    for Direction := 0 to Ord(Render and not ExportFrames) do begin
      Ref := NewPlanRef(Audio.Key,Audio.Sensitivity,Direction,rsTrain);
      Ref.SourceRevision := Audio.SourceRevision;
      Plan.Save(Ref,Audio);
      Meta := TTrainPlan.LoadAudioMetadata(Ref,Audio.Source,Direction);
      Need((Length(Meta.PCM)=0) and (Length(Meta.Envelope)=0),'Cold restored decoded audio');
      Cold := TTrainPlan.Load(Ref,Meta,Direction);
      CheckMotion(Plan,Cold,Audio);
      if Render then CheckRender(Audio,Meta,Ref,Plan,Name+'-'+IntToStr(Direction),ExportFrames);
      FreeAndNil(Cold);
      FreeAndNil(Meta);
    end;
    Writeln(Format('%s: %d cars + %d cars, %d/%d moves synchronized, %.3fs',[Name,Plan.InitialCars,
      Plan.NextCars,Plan.Synced,Plan.Count,Plan.EndTime],TFormatSettings.Invariant));
  finally
    Csv.Free;
    Cold.Free;
    Meta.Free;
    Plan.Free;
  end;
end;

procedure SyntheticCase(const Name: string; Duration, Interval: Double; Render: Boolean=False);
var
  Audio: TRhythmAudio;
begin
  Audio := SyntheticAudio(Name,Duration,Interval);
  try
    Exercise(Audio,Name,Render,False);
  finally
    Audio.Free;
  end;
end;

var
  Audio: TRhythmAudio;
  Cancelled: Boolean;
begin
  try
    ConfigureRhythmProduct('SYNC_RhythmTrain','Train test',rsTrain);
    Evidence := TPath.Combine(ExtractFileDir(ParamStr(0)),'TrainEvidence');
    ForceDirectories(Evidence);
    Need((StyleId(rsTrain)='train') and (StylePlanVersion(rsTrain)=5) and
      not CompatiblePlanVersion(rsTrain,1) and not CompatiblePlanVersion(rsTrain,2) and
      not CompatiblePlanVersion(rsTrain,3) and not CompatiblePlanVersion(rsTrain,4) and (StyleInfo(rsTrain).Group=sgAction),'Replacement registry');
    if ParamCount>0 then begin
      Audio := LoadRhythmAudio(ParamStr(1),50);
      try
        Exercise(Audio,'real-track',True,ParamStr(2)='clip');
      finally
        Audio.Free;
      end;
    end
    else begin
      SyntheticCase('silent',2.0,0);
      SyntheticCase('very-short',0.10,0.05);
      SyntheticCase('short',1.2,0.13);
      SyntheticCase('strong-pulse',30.0,0.25,True);
      SyntheticCase('sparse',43.0,2.6);
      SyntheticCase('dense',71.0,0.007);
      SyntheticCase('long',1200.0,0.13);
      Audio := SyntheticAudio('cancel',1,0.2);
      try
        Cancelled := False;
        try
          TTrainPlan.Build(Audio,function: Boolean begin Result := True; end).Free;
        except
          on E: EAbort do Cancelled := True;
        end;
        Need(Cancelled,'Cancellation ignored');
      finally
        Audio.Free;
      end;
    end;
    Writeln('Train roof action PASS ',Checks);
  except
    on E: Exception do begin
      Writeln(E.ClassName,': ',E.Message);
      ExitCode := 1;
    end;
  end;
end.
