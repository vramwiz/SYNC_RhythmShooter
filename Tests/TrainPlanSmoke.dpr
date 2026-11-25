program TrainPlanSmoke;
{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.Math, System.Classes, System.Hash, System.IOUtils,
  System.TypInfo, System.Types, Vcl.Graphics, Vcl.Imaging.jpeg, Vcl.Imaging.pngimage,
  RhythmTrainPlan in '..\Source\Train\RhythmTrainPlan.pas',
  RhythmTrainScene in '..\Source\Train\RhythmTrainScene.pas',
  RhythmAudio, RhythmOrbitAudio, RhythmStyles, RhythmSettings, RhythmPlanRef, RhythmProduct, RhythmPaths,
  RhythmAnimation, RhythmImageBank, RhythmTrainArt;

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

procedure LogRoofMotion(Plan: TTrainPlan; const Name: string);
const
  Rate = 60;
  VisibleStep = 0.015;
var
  Csv: TStringList;
  I, FirstFrame, LastFrame, Still, Idle, Longest, LongestEnd: Integer;
  T, Distance: Double;
  Pose, Prior: TTrainPose;
begin
  if Plan.Count=0 then Exit;
  FirstFrame := Ceil(Plan.Cue[0].Time*Rate);
  LastFrame := Floor(Plan.Cue[Plan.Count-1].Start*Rate);
  Csv := TStringList.Create;
  try
    Csv.Add('frame,time,roof_x,roof_y,distance,run,crouch,reach,slide,airborne');
    Prior := Plan.PoseAt((FirstFrame-1)/Rate);
    Still := 0;
    Idle := 0;
    Longest := 0;
    LongestEnd := 0;
    for I := FirstFrame to LastFrame do begin
      T := I/Rate;
      Pose := Plan.PoseAt(T);
      Distance := Hypot(Pose.X-Prior.X,Pose.Y-Prior.Y);
      Csv.Add(Format('%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d',
        [I,T,Pose.X,Pose.Y,Distance,Pose.Run,Pose.Crouch,Pose.Reach,Pose.Slide,Ord(Pose.Airborne)],
        TFormatSettings.Invariant));
      if Distance<VisibleStep then begin
        Inc(Still);
        Inc(Idle);
        if Idle>Longest then begin
          Longest := Idle;
          LongestEnd := I;
        end;
      end else Idle := 0;
      Prior := Pose;
    end;
    Csv.SaveToFile(TPath.Combine(Evidence,Name+'-motion.csv'),TEncoding.UTF8);
    Writeln(Format('%s roof at 60 fps: moving %.1f%% (%d/%d), longest near-still %.3fs at %.3f-%.3fs',
      [Name,100*(1-Still/(LastFrame-FirstFrame+1)),LastFrame-FirstFrame+1-Still,LastFrame-FirstFrame+1,
       Longest/Rate,(LongestEnd-Longest)/Rate,LongestEnd/Rate],TFormatSettings.Invariant));
  finally
    Csv.Free;
  end;
end;

procedure RenderSavedExcerpt(Meta: TRhythmAudio; const Ref: TRhythmPlanRef;
  const Name: string; Start, Duration: Double);
const
  Rate = 30;
  HeroRGB = $F9CE50;
var
  Renderer: TAnimationRenderer;
  Image: TBitmap;
  JPEG: TJPEGImage;
  Csv: TStringList;
  Folder: string;
  I,X,Y,Pixels,SumX,SumY,MinY,MaxY: Integer;
  Pixel: PCardinal;
  Time: Double;
begin
  Need((Ref.Direction=0) and (Start>=0) and (Duration>0) and (Duration<=12),'Invalid excerpt range');
  Folder := TPath.Combine(Evidence,Name+'-frames');
  ForceDirectories(Folder);
  Renderer := NewRenderer(Meta,Ref);
  Image := TBitmap.Create;
  JPEG := TJPEGImage.Create;
  Csv := TStringList.Create;
  try
    Renderer.UseD2D := True;
    Image.PixelFormat := pf32bit;
    Image.SetSize(960,540);
    JPEG.CompressionQuality := 88;
    Csv.Add('time,hero_center_x,hero_center_y,hero_pixels');
    for I := 0 to Round(Duration*Rate)-1 do begin
      Time := Start+I/Rate;
      Renderer.Render(Image,Time,Ref.Direction);
      Need((Renderer.Notice='') and Renderer.LastUsedD2D,'Saved plan render failed');
      Pixels := 0;
      SumX := 0;
      SumY := 0;
      MinY := Image.Height;
      MaxY := -1;
      for Y := 0 to Image.Height-1 do begin
        Pixel := Image.ScanLine[Y];
        for X := 0 to Image.Width-1 do begin
          if Pixel^ and $FFFFFF=HeroRGB then begin
            Inc(Pixels);
            Inc(SumX,X);
            Inc(SumY,Y);
            MinY := Min(MinY,Y);
            MaxY := Max(MaxY,Y);
          end;
          Inc(Pixel);
        end;
      end;
      Need(Pixels>30,'Hero color missing from rendered frame');
      Need((MinY>1) and (MaxY<Image.Height-2),'Hero is cut off vertically in the preview');
      Csv.Add(Format('%.6f,%.3f,%.3f,%d',[Time,SumX/Pixels,SumY/Pixels,Pixels],TFormatSettings.Invariant));
      JPEG.Assign(Image);
      JPEG.SaveToFile(TPath.Combine(Folder,Format('frame-%.5d.jpg',[I])));
    end;
    Csv.SaveToFile(TPath.Combine(Evidence,Name+'-hero-pixels.csv'),TEncoding.UTF8);
  finally
    Csv.Free;
    JPEG.Free;
    Image.Free;
    Renderer.Free;
  end;
end;

function TrainProjectSettings(const ProjectPath: string): TRhythmSettings;
var
  Line: string;
begin
  for Line in TFile.ReadAllLines(ProjectPath,TEncoding.UTF8) do
    if Line.StartsWith('設定JSON=') and TRhythmSettings.TryJSON(Line.Substring(7),Result) and
       (Result.Style=rsTrain) then Exit;
  raise Exception.Create('No train object in '+ProjectPath);
end;

procedure LogSavedProject(const ProjectPath: string);
var
  Settings: TRhythmSettings;
  Meta: TRhythmAudio;
  Plan: TTrainPlan;
begin
  Settings := TrainProjectSettings(ProjectPath);
  ConfigureRhythmProduct('SYNC_RhythmShooter','Train motion test',rsTrain);
  Meta := TTrainPlan.LoadAudioMetadata(Settings.Plan,Settings.Music,Settings.Direction);
  try
    Plan := TTrainPlan.Load(Settings.Plan,Meta,Settings.Direction);
    try
      LogRoofMotion(Plan,TPath.GetFileNameWithoutExtension(ProjectPath));
    finally
      Plan.Free;
    end;
  finally
    Meta.Free;
  end;
end;

procedure CheckMotion(Plan,Cold: TTrainPlan; Audio: TRhythmAudio);
var
  C, Prior: TTrainCue;
  P,Q: TTrainPose;
  T,RoofStart,CameraX,CameraWidth,Blend,Reach,Joint,Dock,RoofX,ScreenX,LastX,Incoming: Double;
  Block: TTrainObstacle;
  E: TTrainExchange;
  CarMin,CarMax: TArray<Double>;
  I,J,JumpCount,ObstacleCount,CarIndex,Traversed,First,Last,Enemies,Equipment,CourseHazards: Integer;
  ClearCars,SingleCars,TwinCars,EarlyHurdles,LateHurdles: Integer;
begin
  Need(Plan.Count=Cold.Count,'Cold cue count');
  Need(Plan.Synced=Cold.Synced,'Cold sync count');
  if Plan.Count=0 then Exit;
  Need(Plan.Cue[0].Time<0.82,'Boarding too late');
  Need((Plan.Cue[Plan.Count-4].Kind=tmBossJump) and
    (Plan.Cue[Plan.Count-3].Kind=tmBossDuck) and (Plan.Cue[Plan.Count-2].Kind=tmBossFinish),
    'Finale needs dodge, armor hit, and finishing hit');
  Need(Plan.Cue[Plan.Count-2].Start>Plan.Cue[Plan.Count-3].Time,
    'The armor-hit stagger plays before the finishing attack');
  Need(Plan.EndTime>Plan.Cue[Plan.Count-2].Time+0.55,'The finale must have a visible defeat');
  JumpCount := 0;
  ObstacleCount := 0;
  for I := 0 to Plan.Count-1 do begin
    C := Plan.Cue[I];
    Need(C.Time=Cold.Cue[I].Time,'Cold time changed');
    if I>0 then begin
      Prior := Plan.Cue[I-1];
      if C.FromX-Prior.ToX>0.02 then begin
        P := Plan.PoseAt((Prior.Finish+C.Start)*0.5);
        Need((Abs(P.X-(Prior.ToX+C.FromX)*0.5)<1E-8) and (P.Run>0),'Hero misses approach to the next contact');
        Need(Abs(Plan.PoseAt(C.Start).X-C.FromX)<1E-8,'Hero misses takeoff position');
      end;
    end;
    if C.Source>=0 then begin
      Need(Abs(C.Time-Audio.Hits[C.Source].Time)<0.065,'Contact left the original onset neighborhood');
      if Length(Audio.PCM)=0 then Need(C.Time=Audio.Hits[C.Source].Time,'Synthetic onset shifted');
    end;
    P := Plan.PoseAt(C.Time);
    Need(Abs(P.X-C.ToX)<1E-8,'Contact position');
    if TrainRegularEnemy(C.Kind) or (C.Kind in [tmBossDuck,tmBossFinish]) then begin
      Need(Abs(P.Reach-1)<1E-8,'Strike lacks contact reach');
      Need(P.Gesture<>tgNone,'Strike has no distinct pose at contact');
      Q := Plan.PoseAt((C.Start+C.Time)*0.5);
      Need((Q.Gesture=P.Gesture) and (Q.Reach<1) and (Q.Windup>0),
        'Strike misses the anticipation pose');
      Q := Plan.PoseAt((C.Time+C.Finish)*0.5);
      Need((Q.Gesture=P.Gesture) and (Q.Reach<1) and (Q.FollowThrough>0),
        'Strike misses the follow-through pose');
      if C.Kind in [tmDuckHit,tmBossDuck] then
        Need(Plan.PoseAt(TrainThreatTime(C)).Crouch>0.86,'Duck misses the threat');
      if C.Kind in [tmVaultHit,tmHurdleHit] then
        Need((P.Gesture=tgAirKick) and (P.Kick=1),'No jumping kick at contact');
      Need(Plan.PoseAt(Ceil(C.Time*60)/60).Reach>0,'Strike reaction misses first display frame');
      Reach := TrainReach;
      if C.Kind=tmShot then Reach := TrainShotReach;
      Need(Abs(P.Y-Plan.RoofY(P.X+Reach))<1E-8,'Strike target on a different roof');
    end;
    if TrainObstacle(C,Block) then begin
      Inc(ObstacleCount);
      Need(C.Time-C.Start<=0.37+1E-8,'Obstacle jump hangs in midair');
      Need(Plan.PoseAt(Ceil(C.Time*60)/60).Land>0,'Obstacle landing misses first display frame');
      T := C.Start+(C.Time-C.Start)*(Block.Left-C.FromX)/(C.ToX-C.FromX);
      Q := Plan.PoseAt(T);
      Need(Q.Airborne and (Q.Y<Plan.RoofY(Q.X)-Block.Height-0.1),'Hero does not climb above the obstacle');
      T := C.Start+(C.Time-C.Start)*(Block.Right-C.FromX)/(C.ToX-C.FromX);
      Q := Plan.PoseAt(T);
      Need(Q.Airborne and (Q.Y<Plan.RoofY(Q.X)-Block.Height-0.1),'Hero lands on the obstacle');
    end;
    if TrainRouteHazard(C,Block) then begin
      Inc(ObstacleCount);
      case C.Kind of
        tmSlide: for J := 0 to 16 do begin
          T := C.Start+(C.Time-C.Start)*(Block.Left-0.64+(Block.Right-Block.Left+1.28)*J/16-C.FromX)/
            (C.ToX-C.FromX);
          Q := Plan.PoseAt(T);
          Need((Q.Slide>0.98) and not Q.Airborne,'Slide exposes hero to the overhead beam');
        end;
        tmRoofGap: begin
          for J := 0 to 8 do begin
            T := C.Start+(C.Time-C.Start)*(Block.Left+(Block.Right-Block.Left)*J/8-C.FromX)/(C.ToX-C.FromX);
            Q := Plan.PoseAt(T);
            Need(Q.Airborne and (Q.Y<Plan.RoofY(Q.X)-0.65),'Hero crosses an open roof gap on foot');
          end;
          Need(Plan.PoseAt(Ceil(C.Time*60)/60).Land>0,'Gap landing misses first display frame');
        end;
        tmGateRun: begin
          Prior := Plan.Cue[I-1];
          Need((Prior.Kind=tmLever) and (Plan.PoseAt(Prior.Time).Reach=1),'Gate has no lever strike');
          Need(TrainGateOpening(Prior,C,Prior.Time-0.001)=0,'Gate opens before the lever strike');
          Need(TrainGateOpening(Prior,C,C.Start)=1,'Closed gate intersects the route');
          T := (Prior.Time+Min(Prior.Time+0.19,C.Start))*0.5;
          Q := Plan.PoseAt(T);
          Need((Q.X+0.50<Block.Left) and (TrainGateOpening(Prior,C,T)>0),'Hero reaches the gate too soon');
        end;
      end;
    end;
    if C.Kind in [tmJump,tmTransfer,tmBossJump] then begin
      Inc(JumpCount);
      Need(C.Time-C.Start<=0.34+1E-8,'Car jump hangs in midair');
      Need(Floor(C.ToX/TrainPitch)=Floor(C.FromX/TrainPitch)+1,'Jump did not cross a gap');
      Need(Abs(P.Y-Plan.RoofY(C.ToX))<1E-8,'Landing misses roof');
      Need(Plan.PoseAt((C.Start+C.Time)*0.5).Airborne,'Crossing is not a jump');
    end;
  end;
  Need(JumpCount=Plan.Cars-1,'Missing car crossings');
  Need(ObstacleCount>0,'Missing roof obstacles');
  ClearCars := 0; SingleCars := 0; TwinCars := 0;
  EarlyHurdles := 0; LateHurdles := 0;
  for CarIndex := 0 to Plan.Cars-2 do begin
    Plan.CarCues(CarIndex,CarIndex,First,Last);
    Enemies := 0;
    Equipment := 0;
    CourseHazards := 0;
    for I := First to Last do begin
      if TrainRegularEnemy(Plan.Cue[I].Kind) then Inc(Enemies);
      if TrainObstacle(Plan.Cue[I],Block) then begin
        Inc(Equipment);
        T := (Block.Left+Block.Right)*0.5-CarIndex*TrainPitch;
        if T<3.05 then Inc(EarlyHurdles);
        if T>7.1 then Inc(LateHurdles);
      end;
      if TrainRouteHazard(Plan.Cue[I],Block) then Inc(CourseHazards);
    end;
    if CourseHazards>0 then Need((Enemies=0) and (CourseHazards>=2),'An obstacle car still depends on fighting')
    else begin
      Need(Enemies>=2,'A combat car has no encounter sequence');
      case Equipment of
        0: Inc(ClearCars);
        1: Inc(SingleCars);
        2: Inc(TwinCars);
      end;
    end;
  end;
  Need((ClearCars>0) and (SingleCars>0),'The route needs both clear and single-obstacle combat cars');
  if Plan.Cars>=24 then
    Need((TwinCars>0) and (EarlyHurdles>0) and (LateHurdles>0),
      'A long route needs twin, forward, and rearward hurdles');
  Need(Plan.ExchangeCount>0,'Train never meets another formation');
  Need(Plan.Cue[Plan.Exchange[0].StartIndex].Time<10.02,'First collision is too late');
  if (Audio.SoundEnd>=60) and (Length(Audio.Hits)>Audio.SoundEnd) then
    Need(Plan.ExchangeCount>=3,'Long song stays in one formation');
  for I := 0 to Plan.ExchangeCount-1 do begin
    E := Plan.Exchange[I];
    Joint := E.LeadCar*TrainPitch-TrainGap;
    Dock := (E.LeadCar+1)*TrainPitch;
    if E.LeftIndex>=0 then begin
      C := Plan.Cue[E.LeftIndex];
      Need(Abs(Plan.LeftNoseAt(I,C.Time)-Joint)<1E-8,'Left couplers miss');
      Need(Abs(Plan.LeftNoseAt(I,Ceil(C.Time*30)/30)-Joint)<1E-8,
        'Left couplers rebound before the first display frame');
      T := C.Time-0.19;
      Incoming := Plan.LeftNoseAt(I,T);
      Plan.CollisionCamera(I,T,CameraX,CameraWidth,Blend);
      Need((Blend>0.99) and (Incoming<Joint-1.0) and
        (Incoming-1.0>CameraX-CameraWidth*0.5),'Left incoming car outside the shot');
      Need(Plan.LeftNoseAt(I,C.Time+0.17)<Joint-2.6,'Left car does not visibly rebound');
      Plan.CollisionCamera(I,C.Time,CameraX,CameraWidth,Blend);
      Need((Abs(CameraX-(Joint+TrainGap*0.5))<CameraWidth*0.5-0.45) and
        (Abs(CameraX-C.ToX)<CameraWidth*0.5-0.45),'Left coupling or hero left the shot');
    end;
    if E.RightIndex>=0 then begin
      C := Plan.Cue[E.RightIndex];
      Need(Abs(Plan.RightRearAt(I,C.Time)-Dock)<1E-8,'Right couplers miss');
      Need(Abs(Plan.RightRearAt(I,Ceil(C.Time*30)/30)-Dock)<1E-8,
        'Right couplers rebound before the first display frame');
      P := Plan.PoseAt((C.Start+C.Time)*0.5);
      Need(P.Airborne and (Plan.PoseAt(C.Time).Land>0),'Hero misses the right collision landing');
      T := C.Time-Min(0.19,(C.Time-Plan.Cue[E.RightIndex-1].Time)*0.22);
      Plan.CollisionCamera(I,T,CameraX,CameraWidth,Blend);
      Incoming := Plan.RightRearAt(I,T);
      Need((Blend>0.99) and (Incoming>Dock+1) and
        (Incoming+1.0<CameraX+CameraWidth*0.5),'Right incoming car outside the shot');
      Need(Plan.RightRearAt(I,(C.Time+Plan.Cue[E.CoupleIndex].Time)*0.5)>Dock+1.9,
        'Right car does not visibly rebound');
    end;
    C := Plan.Cue[E.CoupleIndex];
    Need(Abs(Plan.RightRearAt(I,C.Time+0.01)-Dock)<1E-8,'Right cars did not latch');
    C := Plan.Cue[E.TransferIndex];
    Plan.CollisionCamera(I,C.Time,CameraX,CameraWidth,Blend);
    Need(Blend<0.22,'Roof framing not restored during transfer');
    Need(Plan.ExchangeAt(C.Time-0.01)=I,'Formation switched before transfer');
    Need(Plan.ExchangeAt(C.Time+0.14)=I+1,'Formation failed to switch after transfer');
    Need(Plan.CarPosition(E.LeadCar+1,I+1,C.Time+0.14,Incoming) and (Abs(Incoming)<1E-8),
      'Landing car moves when changing formations');
    Need(Plan.CarPosition(E.LeadCar,I+1,C.Time+0.14,Incoming) and (Incoming<0) and (Incoming>-0.2),
      'Outgoing cab jumps or disappears at transfer');
  end;
  Need(Plan.TravelAt(Plan.Cue[0].Time)=0,'Wheels moved during boarding');
  Need(Plan.TravelAt(Plan.Cue[0].Time+0.16)>0,'Train did not leave departure platform');
  Need(Plan.PoseAt(Plan.Arrival).Y=TrainPlatformY,'Station landing missing');
  Need(Plan.TravelAt(Plan.EndTime)=Plan.TravelAt(Plan.Arrival),'Train did not stop at station');

  SetLength(CarMin,Plan.Cars-1);
  SetLength(CarMax,Length(CarMin));
  for I := 0 to High(CarMin) do CarMin[I] := 1;
  LastX := Plan.PoseAt(0).X;
  for I := 0 to 2000 do begin
    T := I*Plan.EndTime/2000;
    P := Plan.PoseAt(T);
    Need(P.X>=LastX-1E-8,'Hero wanders back along the roof');
    LastX := P.X;
    if (T>Plan.Cue[0].Time+0.09) and (T<Plan.Cue[Plan.Count-2].Time) then begin
      CarIndex := Floor(P.X/TrainPitch);
      RoofX := P.X-CarIndex*TrainPitch;
      if (CarIndex>=0) and (CarIndex<Length(CarMin)) and (RoofX>1.8) and (RoofX<10.35) then begin
        ScreenX := 0.5+(P.X-Plan.RoofCameraX(T))/TrainRoofViewWidth;
        CarMin[CarIndex] := Min(CarMin[CarIndex],ScreenX);
        CarMax[CarIndex] := Max(CarMax[CarIndex],ScreenX);
      end;
    end;
    if (T>Plan.Cue[0].Time) and (T<Plan.Cue[Plan.Count-1].Start) then begin
      RoofStart := Floor(P.X/TrainPitch)*TrainPitch;
      if not P.Airborne then begin
        Need(P.X-RoofStart<=TrainCarWidth+1E-8,'Hero stood in a gap');
        Need(Abs(P.Y-Plan.RoofY(P.X))<1E-8,'Grounded hero above or below roof');
        if Plan.NextRoofObstacle(Floor(P.X/TrainPitch),P.X,Block) then
          Need(P.X<Block.Left,'Grounded hero crossed roof equipment');
      end;
      if P.X-RoofStart<=TrainCarWidth then
        Need(P.Y<=Plan.RoofY(P.X)+1E-8,'Hero arc clips a roof');
    end;
    J := (I*733) mod 2001;
    T := J*Plan.EndTime/2000;
    P := Plan.PoseAt(T);
    Q := Cold.PoseAt(T);
    Need((P.X=Q.X) and (P.Y=Q.Y) and (P.Reach=Q.Reach) and (P.Crouch=Q.Crouch) and (P.Run=Q.Run) and
      (P.Slide=Q.Slide) and
      (Plan.RoofCameraX(T)=Cold.RoofCameraX(T)) and (Plan.TravelAt(T)=Cold.TravelAt(T)),'Cold seek state changed');
  end;
  if (Audio.Duration>=15) and (Audio.Duration<=100) then begin
    Traversed := 0;
    for I := 0 to High(CarMin) do
      if CarMax[I]-CarMin[I]>0.49 then Inc(Traversed);
    Need(Traversed>=Length(CarMin)-Plan.ExchangeCount-1,'Hero does not travel across the screen');
  end;
end;

// Exercise the real art bank in the actual Delphi renderer, in addition to procedural fallback.
procedure CheckEmbeddedArt(Audio,Meta: TRhythmAudio; const Ref: TRhythmPlanRef; Plan: TTrainPlan);
var
  Bank: TAnimationImageBank;
  Warm,Cold,Fallback: TAnimationRenderer;
  Im: TBitmap;
  Png: TPngImage;
  X,I,J: Integer;
  B: TBitmap;
  T,Hit,Phase,At: Double;
  RootA,RootB,TailA,TailB: TPointF;
  C: TTrainCue;
  Pose: TTrainPose;
  PrevPhase,Flow,Offset,PeakFlow: Double;
  Shot,FrameN,DestCar,Owner,WalkSample: Integer;
  Xchg: TTrainExchange;
  S: string;

  function RendererFor(ForAudio: TRhythmAudio; Images: TAnimationImageBank): TAnimationRenderer;
  var A: TTrainAnimation;
  begin
    A := TTrainAnimation.Create;
    A.Audio := ForAudio;
    A.SetReference(Ref);
    Result := TAnimationRenderer.Create(A,Images);
  end;

begin
  Need(TrainArtLowPhase(0.88,0,True,Phase) and
    (TrainArtSample(taDuck,Phase)=6),'Full crouch uses authored contact frame');
  Need(TrainArtLowPhase(0,1,True,Phase) and
    (TrainArtSample(taDuck,Phase)=6),'Slide uses authored low frame');
  Need(TrainArtLowPhase(0.42,0,True,Phase) and
    (TrainArtSample(taDuck,Phase)<6),'Partial crouch is represented');
  Need(not TrainArtLowPhase(1,1,False,Phase),'Airborne motion is not a grounded duck');
  RootA := TrainScarfPoint(0,12.0,0.3);
  RootB := TrainScarfPoint(0,12.2,0.9);
  Need((RootA.X=RootB.X) and (RootA.Y=RootB.Y),'Scarf root stays fixed');
  RootA := TrainScarfRoot(taIdle,6); RootB := TrainScarfRoot(taDuck,6);
  Need((RootB.Y>RootA.Y) and (RootB.X>0),'Scarf follows crouching collar');
  TailA := TrainScarfPoint(1,12.0,0); TailB := TrainScarfPoint(1,12.2,0);
  Need((TailA.X=TailB.X) and (TailA.Y=TailB.Y),'A stopped scarf must not flutter');
  Need((TailA.Y>40) and (Abs(TailA.X)<0.15*TailA.Y),'A stopped scarf hangs close to the torso');
  for I := 0 to 120 do begin
    TailB := TrainScarfPoint(1,12.0+I/60,1);
    Need((TailB.X<-30) and (Abs(TailB.Y+TailB.X)<4),'Moving scarf trails downward at about 45 degrees');
  end;
  Pose := Plan.PoseAt(Plan.Arrival+0.40);
  Need(Plan.ScarfMotionAt(Plan.Arrival+0.40,Pose.X)=0,'No relative motion after arriving');
  PeakFlow := 0;
  for I := 0 to Plan.Count-1 do begin
    C := Plan.Cue[I];
    for X := 0 to 11 do begin
      At := C.Start+(C.Time-C.Start)*X/12;
      Pose := Plan.PoseAt(At);
      Flow := Plan.ScarfMotionAt(At,Pose.X);
      Need((Flow>=0) and (Flow<=1),'Scarf drive normalized');
      PeakFlow := Max(PeakFlow,Flow);
    end;
  end;
  Need(PeakFlow>=0.95,'Planned motion fully extends scarf');
  for I := 0 to Plan.ExchangeCount-1 do begin
    Xchg := Plan.Exchange[I];
    DestCar := Xchg.LeadCar+1;
    Owner := Plan.FormationOf(DestCar);
    C := Plan.Cue[Xchg.TransferIndex];
    for X := -24 to 24 do begin
      At := C.Time+X/60;
      Need(Plan.CarPosition(DestCar,Plan.ExchangeAt(At),At,Offset),'Destination remains visible through landing');
      Need(Plan.FormationOf(DestCar)=Owner,'Destination keeps its physical formation');
    end;
  end;
  Bank := CreateTrainArtImages;
  try
    Bank.EnsurePrepared;
    Need(TrainArtAvailable(Bank),'Embedded train art bank unavailable');
    for I := 0 to TrainArtRoutes-1 do begin
      B := Bank.Image[TrainArtBackground(I,0)];
      Need((B.Width=960) and (B.Height=540),'Background resampling dimensions');
    end;
    B := Bank.Image[TrainArtAtlas(0,taWalk)];
    Need((B.Width=960) and (B.Height=1280) and (B.AlphaFormat=afPremultiplied),
      'Train actor atlas dimensions and premultiplied alpha');
    for I := 0 to TrainArtRoles-1 do begin
      Need(TrainArtStride(I)>0,'Positive stride calibration');
      for X := Ord(taPunch) to Ord(taLand) do begin
        Need(TrainArtSample(TTrainArtClip(X),0.499)<6,'One-shot anticipation sample');
        Need(TrainArtSample(TTrainArtClip(X),0.5)=6,'One-shot impact sample');
        Need(TrainArtSample(TTrainArtClip(X),0.55)=7,'One-shot recovery sample');
      end;
    end;
  finally Bank.Free;end;

  Warm := nil; Cold := nil; Fallback := nil; Im := nil; Png := nil;
  try
    Warm := RendererFor(Audio,CreateTrainArtImages);
    Cold := RendererFor(Meta,CreateTrainArtImages);
    Fallback := NewRenderer(Meta,Ref);
    Im := TBitmap.Create; Im.PixelFormat := pf32bit;
    Png := TPngImage.Create;
    if Ref.Direction=0 then Im.SetSize(960,540) else Im.SetSize(540,960);
    Hit := Plan.Cue[1].Time;
    for J := 0 to 1 do begin
      Warm.UseD2D := J=1; Cold.UseD2D := J=1; Fallback.UseD2D := J=1;
      for I := 0 to 6 do begin
        T := Hit+(I-3)/60;
        Warm.Render(Im,T,Ref.Direction);
        Need((Warm.Notice='') and ((J=0) or Warm.LastUsedD2D),'Embedded render backend');
        S := PixelHash(Im);
        Fallback.Render(Im,T,Ref.Direction);
        Need(S<>PixelHash(Im),'Embedded art must visibly differ from procedural fallback');
        Cold.Render(Im,T,Ref.Direction);
        Need(S=PixelHash(Im),'Embedded cold/seek render mismatch');
        Warm.Render(Im,Plan.EndTime-T,Ref.Direction);
        Warm.Render(Im,T,Ref.Direction);
        Need(S=PixelHash(Im),'Embedded shuffled seek changed frame');
        if (J=1) and (I in [1,3,5]) then begin
          Png.Assign(Im);
          Png.SaveToFile(TPath.Combine(Evidence,Format('art-hit-%d-%d.png',[Ref.Direction,I])));
        end;
      end;
      if J=1 then begin
        At := -1;
        for I := 1 to Plan.Count-2 do begin
          C := Plan.Cue[I];
          if Plan.Cue[I+1].FromX-C.ToX<0.35 then Continue;
          if Plan.Cue[I+1].Start-C.Finish<0.36 then Continue;
          T := (Plan.Cue[I+1].Start+C.Finish)*0.5;
          Pose := Plan.PoseAt(T);
          if (Pose.Run>0.17) and not Pose.Airborne and (Pose.Gesture=tgNone) then begin
            At := T-10/60;
            Break;
          end;
        end;
        Need(At>=0,'Expected an uninterrupted guard walk');
        for WalkSample := 0 to 20 do begin
          T := At+WalkSample/60;
          Warm.Render(Im,T,Ref.Direction);
          Need((Warm.Notice='') and Warm.LastUsedD2D,'Guard walk renders in D2D');
          S := PixelHash(Im);
          Cold.Render(Im,T,Ref.Direction);
          Need(S=PixelHash(Im),'Guard walk matches after seek');
          if (WalkSample mod 4)=0 then begin
            Png.Assign(Im);
            Png.SaveToFile(TPath.Combine(Evidence,Format('guard-%d-%d.png',[Ref.Direction,WalkSample])));
          end;
        end;
      end;
      if (J=1) and (Ref.Direction=0) then begin
        for Shot := 0 to 7 do begin
          case Shot of
            0: At := 0;
            1,3: At := Plan.Cue[1].Time-0.35;
            2: At := Plan.Arrival-0.27;
            4: At := Plan.Cue[Plan.Exchange[0].RightIndex].Time-0.32;
            5: At := Plan.Cue[Plan.Exchange[0].TransferIndex].Time-0.35;
            6: At := Plan.Cue[Plan.Count-4].Start-0.20;
          else At := Plan.Cue[Plan.Count-2].Time-0.31;
          end;
          for I := 1 to Plan.Count-2 do begin
            if (Shot=0) and (Plan.Cue[I+1].Start-Plan.Cue[I].Finish>0.82) and
               (Plan.Cue[I+1].FromX-Plan.Cue[I].ToX>1.5) then begin
              At := Plan.Cue[I].Finish;
              Break;
            end;
            if ((Shot=1) and (Plan.Cue[I].Kind=tmDuckHit)) or
               ((Shot=3) and (Plan.Cue[I].Kind=tmHit)) then begin
              At := Plan.Cue[I].Time-0.35;
              Break;
            end;
          end;
          for FrameN := 0 to 47 do begin
            T := At+FrameN/60;
            Warm.Render(Im,T,Ref.Direction);
            Need((Warm.Notice='') and Warm.LastUsedD2D,'Sequential D2D footage');
            Png.Assign(Im);
            Png.SaveToFile(TPath.Combine(Evidence,Format('motion-%d-%.3d.png',[Shot,FrameN])));
          end;
        end;
        At := Plan.Cue[Plan.Count-4].Start-0.18;
        for FrameN := 0 to Ceil((Plan.Cue[Plan.Count-2].Time+1.0-At)*30) do begin
          T := At+FrameN/30;
          Warm.Render(Im,T,Ref.Direction);
          Need((Warm.Notice='') and Warm.LastUsedD2D,'Finale sequence uses native D2D');
          if FrameN mod 5=0 then begin
            S := PixelHash(Im);
            Cold.Render(Im,T,Ref.Direction);
            Need(S=PixelHash(Im),'Finale sparks and smoke must be seek deterministic');
          end;
          Png.Assign(Im);
          Png.SaveToFile(TPath.Combine(Evidence,Format('finale-proof-%.3d.png',[FrameN])));
        end;
        for I := 0 to Plan.Count-1 do begin
          C := Plan.Cue[I];
          if C.Kind<>tmHit then Continue;
          PrevPhase := 0;
          for FrameN := 0 to 100 do begin
            T := C.Start+(C.Finish-C.Start)*FrameN/100;
            Pose := Plan.PoseAt(T);
            Need(Pose.ArtGesturePhase+1E-7>=PrevPhase,'Gesture phase cannot reverse');
            PrevPhase := Pose.ArtGesturePhase;
          end;
          Pose := Plan.PoseAt(C.Time);
          Need(Abs(Pose.ArtGesturePhase-0.5)<1E-8,'Gesture contact cell on beat');
        end;
      end;
      if J=1 then begin
        for X := 0 to 1 do begin
          for I := 0 to Plan.Count-1 do begin
            C := Plan.Cue[I];
            if ((X=0) and (C.Kind<>tmDuckHit)) or ((X=1) and (C.Kind<>tmSlide)) then Continue;
            if X=0 then T := TrainThreatTime(C) else T := (C.Start+C.Time)*0.5;
            Warm.Render(Im,T,Ref.Direction);
            Png.Assign(Im);
            Png.SaveToFile(TPath.Combine(Evidence,Format('art-low-%d-%d.png',[Ref.Direction,X])));
            S := PixelHash(Im);
            Warm.Render(Im,T+0.15,Ref.Direction);
            Need(S<>PixelHash(Im),'Actor animation advances near crouch');
            Cold.Render(Im,T,Ref.Direction);
            Need(S=PixelHash(Im),'Crouch and scarf deterministic after seek');
            Break;
          end;
          Need(I<Plan.Count,'Expected crouch or slide in native test plan');
        end;
        for I := 1 to TrainArtRoutes-1 do begin
          At := Plan.Arrival*I/TrainArtRoutes;
          for X := -1 to 1 do begin
            if X<0 then T := At-1/60 else if X=0 then T := At+1/60 else T := At+0.575;
            Warm.Render(Im,T,Ref.Direction);
            Need(Warm.Notice='','Art route test render');
            S := PixelHash(Im);
            Cold.Render(Im,T,Ref.Direction);
            Need(S=PixelHash(Im),'Faded route deterministic');
            Png.Assign(Im);
            Png.SaveToFile(TPath.Combine(Evidence,Format('art-fade-%d-%d-%d.png',[Ref.Direction,I,X+1])));
          end;
        end;
      end;
      for I := 0 to Min(Plan.ExchangeCount-1,3) do begin
        T := Plan.Cue[Plan.Exchange[I].CoupleIndex].Time+0.15;
        Warm.Render(Im,T,Ref.Direction);
        if J=1 then begin
          Png.Assign(Im);
          Png.SaveToFile(TPath.Combine(Evidence,Format('art-route-%d-%d.png',[Ref.Direction,I])));
        end;
        S := PixelHash(Im);
        Cold.Render(Im,T,Ref.Direction);
        Need(S=PixelHash(Im),'Embedded route after cold load');
      end;
    end;
  finally
    Png.Free; Im.Free; Fallback.Free; Cold.Free; Warm.Free;
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
  E: TTrainExchange;
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
  if Name.StartsWith('mixed-density-') then CheckEmbeddedArt(Audio,Meta,Ref,Plan);
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
    E := Plan.Exchange[0];
    C := Plan.Cue[E.LeftIndex];
    Snapshot('detached',C.Time-0.44);
    Snapshot('left-incoming',C.Time-0.19);
    Snapshot('impact-left',Ceil(C.Time*30)/30);
    Snapshot('left-rebound',C.Time+0.19);
    C := Plan.Cue[E.RightIndex];
    Snapshot('right-incoming',C.Time-0.19);
    Snapshot('impact-right',Ceil(C.Time*30)/30);
    Snapshot('right-rebound',C.Time+0.22);
    C := Plan.Cue[E.CoupleIndex];
    Snapshot('couple',C.Time+0.055);
    C := Plan.Cue[E.TransferIndex];
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

procedure Exercise(Audio: TRhythmAudio; const Name: string; Render,ExportFrames: Boolean;
  DensityKey: Integer=0; ExcerptStart: Double=-1; ExcerptDuration: Double=0);
var
  Plan,Cold: TTrainPlan;
  Meta: TRhythmAudio;
  Ref: TRhythmPlanRef;
  Csv: TStringList;
  C: TTrainCue;
  Block: TTrainObstacle;
  I,Direction,Enemies,Obstacles,EnemySync,ObstacleSync: Integer;
  Detector, SourceKind: string;
  E: TTrainExchange;
  CourseKinds: set of TTrainMove;

  procedure RenderCourse(Kind: TTrainMove; const LabelText: string);
  var Index, Car, First, Last: Integer; Start: Double; Move: TTrainCue;
  begin
    for Index := 0 to Plan.Count-1 do begin
      Move := Plan.Cue[Index];
      if Move.Kind<>Kind then Continue;
      Car := Floor(Move.FromX/TrainPitch);
      Plan.CarCues(Car,Car,First,Last);
      Start := Max(0,Floor(Move.Start-0.58));
      RenderSavedExcerpt(Meta,Ref,LabelText,Start,Min(9,Ceil(Plan.Cue[Last].Time-Start+0.25)));
      Exit;
    end;
  end;
begin
  Plan := nil;
  Cold := nil;
  Meta := nil;
  Csv := TStringList.Create;
  try
    Plan := TTrainPlan.Build(Audio);
    if Audio.SoundEnd=0 then Need(Plan.Count=0,'Silent source added a battle');
    if Render and (Length(Audio.PCM)>0) then LogRoofMotion(Plan,Name);
    Enemies := 0;
    EnemySync := 0;
    Obstacles := 0;
    ObstacleSync := 0;
    CourseKinds := [];
    Csv.Add('event,start,contact,end,source,source_type,detector_time,first_frame_60fps,first_frame_30fps,from_x,to_x');
    for I := 0 to Plan.Count-1 do begin
      C := Plan.Cue[I];
      Detector := '';
      SourceKind := 'visual';
      if C.Source>=0 then begin
        Detector := Format('%.6f',[Audio.Hits[C.Source].Time],TFormatSettings.Invariant);
        SourceKind := 'detector';
      end
      else if C.Source<-1 then SourceKind := 'opening_pcm';
      if TrainRegularEnemy(C.Kind) then begin
        Inc(Enemies);
        if C.Source>=0 then Inc(EnemySync);
      end;
      if TrainObstacle(C,Block) or TrainRouteHazard(C,Block) then begin
        Inc(Obstacles);
        if C.Source>=0 then Inc(ObstacleSync);
      end;
      if C.Kind in [tmSlide,tmRoofGap,tmLever,tmGateRun] then Include(CourseKinds,C.Kind);
      Csv.Add(Format('%s,%.6f,%.6f,%.6f,%d,%s,%s,%d,%d,%.3f,%.3f',
        [GetEnumName(TypeInfo(TTrainMove),Ord(C.Kind)),C.Start,C.Time,C.Finish,C.Source,
        SourceKind,Detector,Ceil(C.Time*60),Ceil(C.Time*30),C.FromX,C.ToX],TFormatSettings.Invariant));
    end;
    Csv.SaveToFile(TPath.Combine(Evidence,Name+'.csv'),TEncoding.UTF8);
    if Name='strong-pulse' then begin
      Need((EnemySync>=25) and (ObstacleSync>=12),'Dense audio lacks enemy hits and obstacle landings');
      Need(Plan.Synced>=Plan.Count-4,Format('Dense audio matched %d/%d actions',[Plan.Synced,Plan.Count]));
      Need(Plan.ExchangeCount>=2,'Thirty-second track stays in the same situation after the opening');
      Need(CourseKinds=[tmSlide,tmRoofGap,tmLever,tmGateRun],'Thirty-second track lacks distinct obstacle routes');
    end;
    Need((Plan.Enemies=Enemies) and (Plan.Obstacles=Obstacles),'Prepared summary counts differ from the route');
    Csv.Clear;
    Csv.Add('formation,first_collision,collision_side,coupling,transfer');
    for I := 0 to Plan.ExchangeCount-1 do begin
      E := Plan.Exchange[I];
      SourceKind := 'both';
      if E.LeftIndex<0 then SourceKind := 'front';
      if E.RightIndex<0 then SourceKind := 'rear';
      Csv.Add(Format('%d,%.6f,%s,%.6f,%.6f',[I+1,Plan.Cue[E.StartIndex].Time,SourceKind,
        Plan.Cue[E.CoupleIndex].Time,Plan.Cue[E.TransferIndex].Time],TFormatSettings.Invariant));
    end;
    Csv.SaveToFile(TPath.Combine(Evidence,Name+'-exchanges.csv'),TEncoding.UTF8);
    for Direction := 0 to Ord(Render and not ExportFrames) do begin
      Ref := NewPlanRef(Audio.Key,Audio.Sensitivity,Direction,rsTrain,0,DensityKey);
      Ref.SourceRevision := Audio.SourceRevision;
      Plan.Save(Ref,Audio);
      Meta := TTrainPlan.LoadAudioMetadata(Ref,Audio.Source,Direction);
      Need((Length(Meta.PCM)=0) and (Length(Meta.Envelope)=0),'Cold restored decoded audio');
      Cold := TTrainPlan.Load(Ref,Meta,Direction);
      CheckMotion(Plan,Cold,Audio);
      if Render then CheckRender(Audio,Meta,Ref,Plan,Name+'-'+IntToStr(Direction),ExportFrames);
      if (Direction=0) and (ExcerptStart>=0) then
        RenderSavedExcerpt(Meta,Ref,'saved',ExcerptStart,ExcerptDuration);
      if (Direction=0) and (ExcerptStart=-2) and (Plan.Count>0) then begin
        RenderCourse(tmSlide,'slides');
        RenderCourse(tmRoofGap,'gaps');
        RenderCourse(tmLever,'gates');
      end;
      FreeAndNil(Cold);
      FreeAndNil(Meta);
    end;
    Writeln(Format('%s: %d cars, %d exchanges, %d/%d actions, %d/%d enemies, %d/%d obstacles synchronized; %d onsets, %.3fs',
      [Name,Plan.Cars,Plan.ExchangeCount,Plan.Synced,Plan.Count,EnemySync,Enemies,ObstacleSync,
       Obstacles,Length(Audio.Hits),Plan.EndTime],TFormatSettings.Invariant));
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

procedure PrepareTrainProject(const ProjectPath: string);
var
  Audio: TRhythmAudio;
  Settings: TRhythmSettings;
  Key: Integer;
  ExcerptStart, ExcerptDuration: Double;
begin
  Settings := TrainProjectSettings(ProjectPath);
  Key := AudioDensityKey(rsTrain,Settings.GameThreshold);
  ExcerptStart := -1;
  ExcerptDuration := 0;
  if ParamStr(3)='--review' then ExcerptStart := -2
  else if ParamCount>=4 then begin
    ExcerptStart := StrToFloat(ParamStr(3),TFormatSettings.Invariant);
    ExcerptDuration := StrToFloat(ParamStr(4),TFormatSettings.Invariant);
  end;
  Audio := LoadRhythmAudio(Settings.Music,Settings.Sensitivity);
  try
    if Key<>0 then Audio.SetSelectedHits(SelectAnimationHits(Audio,Settings.GameThreshold,nil));
    Exercise(Audio,TPath.GetFileNameWithoutExtension(ProjectPath),True,False,Key,ExcerptStart,ExcerptDuration);
  finally
    Audio.Free;
  end;
end;

var
  Audio: TRhythmAudio;
  Cancelled: Boolean;
  MixIndex,MixNext: Integer;
begin
  try
    ConfigureRhythmProduct('SYNC_RhythmTrain','Train test',rsTrain);
    Evidence := TPath.Combine(ExtractFileDir(ParamStr(0)),'TrainEvidence');
    ForceDirectories(Evidence);
    Need((StyleId(rsTrain)='train') and (StylePlanVersion(rsTrain)=10) and
      not CompatiblePlanVersion(rsTrain,1) and not CompatiblePlanVersion(rsTrain,2) and
      not CompatiblePlanVersion(rsTrain,3) and not CompatiblePlanVersion(rsTrain,4) and
      not CompatiblePlanVersion(rsTrain,5) and not CompatiblePlanVersion(rsTrain,6) and
      not CompatiblePlanVersion(rsTrain,7) and not CompatiblePlanVersion(rsTrain,8) and
      not CompatiblePlanVersion(rsTrain,9) and
      (StyleInfo(rsTrain).Group=sgAction),'Replacement registry');
    if ParamStr(1)='--saved-project' then
      LogSavedProject(ParamStr(2))
    else if ParamStr(1)='--prepare-project' then
      PrepareTrainProject(ParamStr(2))
    else if ParamCount>0 then begin
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
      Audio := SyntheticAudio('mixed-density',90.0,0.16);
      try
        // Keep the first half dense; leave only every ninth candidate in the sparse half.
        for MixIndex := High(Audio.Hits) downto 0 do
          if (Audio.Hits[MixIndex].Time>=45) and (MixIndex mod 9<>0) then begin
            for MixNext := MixIndex to High(Audio.Hits)-1 do
              Audio.Hits[MixNext] := Audio.Hits[MixNext+1];
            SetLength(Audio.Hits,Length(Audio.Hits)-1);
          end;
        Exercise(Audio,'mixed-density',True,False);
      finally Audio.Free;end;
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
