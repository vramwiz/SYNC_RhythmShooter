program PinballTableSmoke;
{$APPTYPE CONSOLE}
// Exercise the v7 preparation and draw entry point with a real song, or synthetic timing extremes.
uses
  Winapi.Windows, System.SysUtils, System.Math, System.IOUtils, System.Hash, System.Classes,
  Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  RhythmAudio, RhythmAudioDecode, RhythmProduct, RhythmStyles, RhythmPlanRef, RhythmBallPlan,
  RhythmBallGeometry, RhythmPinballPlan, RhythmPinballScene, RhythmScene;

const
  ClipSeconds = 26;
  Rate = 60;

var
  Evidence: string;
  Checks: Integer;

procedure Need(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
  Inc(Checks);
end;

function SampleAudio(const Name: string; Gap, Duration: Double; Number: Integer): TRhythmAudio;
var
  I: Integer;
  Stamp: TWin32FileAttributeData;
begin
  Result := TRhythmAudio.Create;
  try
    Result.Source := TPath.Combine(Evidence,Name+'.identity');
    TFile.WriteAllText(Result.Source,Name);
    Need(GetFileAttributesEx(PChar(Result.Source),GetFileExInfoStandard,@Stamp),'Fixture stamp');
    Result.SourceRevision := IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+
      IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    Result.Key := THashSHA2.GetHashString(Name);
    Result.Duration := Duration;
    Result.SoundEnd := Duration;
    Result.Sensitivity := 50;
    SetLength(Result.Hits,Number);
    for I := 0 to Number-1 do begin
      Result.Hits[I].Time := 0.1+I*Gap;
      Result.Hits[I].Strength := 0.35+0.55*(I mod 4)/3;
    end;
  except Result.Free;raise;end;
end;

function FrameHash(Image: TBitmap): string;
var
  Stream: TMemoryStream;
  Bytes: TBytes;
  Hasher: THashSHA2;
begin
  Stream := TMemoryStream.Create;
  try
    Image.SaveToStream(Stream);
    SetLength(Bytes,Stream.Size);
    Stream.Position := 0;
    Stream.ReadBuffer(Bytes[0],Length(Bytes));
    Hasher := THashSHA2.Create;
    Hasher.Update(Bytes);
    Result := Hasher.HashAsString;
  finally Stream.Free;end;
end;

procedure CheckCamera(Plan, Cold: TPinballPlan; const Name: string; CheckMotion: Boolean);
const
  Widths: array[0..3] of Integer = (960,1280,1024,2560);
  Heights: array[0..3] of Integer = (540,720,768,1080);
var
  Camera, Restored: TPinballCamera;
  I,J,N: Integer;
  W,H: Integer;
  T,Y,Margin,Smallest,Speed,Peak,Parked,LowTop,HighTop,PreviousTop,FixedScale: Double;
  View, Other: TPinballView;
begin
  Camera := TPinballCamera.Create(Plan);
  Restored := TPinballCamera.Create(Cold);
  try
    View := Camera.ViewAt(0,540,960);
    Other := Camera.ViewAt(Plan.EndTime*0.5,540,960);
    Need((View.Top=Other.Top) and (View.Scale=Other.Scale),'Portrait camera should hold the whole table');
    N := Floor(Min(Plan.EndTime,ClipSeconds)*120);
    for J := 0 to High(Widths) do begin
      W := Widths[J];
      H := Heights[J];
      View := Camera.ViewAt(0,W,H);
      FixedScale := View.Scale;
      LowTop := View.Top;
      HighTop := View.Top;
      PreviousTop := View.Top;
      Peak := 0;
      Parked := 0;
      Smallest := H;
      for I := 0 to N do begin
        T := I/120;
        View := Camera.ViewAt(T,W,H);
        Y := View.Top+Plan.PositionAt(T).Y*View.Scale;
        Margin := Min(Y,H-Y)-PIN_RADIUS*View.Scale;
        Smallest := Min(Smallest,Margin);
        Need(Margin>=0,'Ball moved outside the landscape view');
        Need(View.Scale=FixedScale,'Tracking changes magnification');
        if I>0 then begin
          Speed := Abs(View.Top-PreviousTop)*120/H;
          Peak := Max(Peak,Speed);
          if Speed<0.002 then Parked:=Parked+1/120;
        end;
        LowTop := Min(LowTop,View.Top);
        HighTop := Max(HighTop,View.Top);
        PreviousTop := View.Top;
      end;
      if Plan.Count=0 then Need(Abs(LowTop-HighTop)<1E-7,'Still ball causes camera movement');
      if CheckMotion and (J=0) then begin
        Need((View.Scale*1.076/W>=0.90) and (View.Scale*1.076/W<1),'Landscape cabinet does not use the frame width');
        Need(HighTop-LowTop>=H*0.50,'Camera does not follow movement between regions');
        Need(Parked>=2,'Camera never settles');
      end;
      if J=0 then Writeln(Format('%s camera %dx%d: %.1f%% width / %.1fpx least edge / %.3f screens/s peak / %.2fs parked',
        [Name,W,H,100*FixedScale*1.076/W,Smallest,Peak,Parked],TFormatSettings.Invariant));
      for I := 0 to 99 do begin
        T := Min(Plan.EndTime,ClipSeconds)*((I*71) mod 101)/100;
        View := Camera.ViewAt(T,W,H);
        Other := Restored.ViewAt(T,W,H);
        Need(Abs(View.Top-Other.Top)<1E-7,'Camera position depends on playback history');
      end;
    end;
  finally
    Restored.Free;
    Camera.Free;
  end;
end;

procedure Test(Audio: TRhythmAudio; const Name: string; RenderFrames, ExportClip, WideClip: Boolean);
var
  Plan, ColdPlan: TRhythmBallPlan;
  Cold: TRhythmAudio;
  Ref, PortraitRef: TRhythmPlanRef;
  Contact: TPinContact;
  Shot: TPinFlight;
  Actual, Other: TBallPoint;
  I,J,N,Flippers,Bumpers,Kickers,Walls,LeftHits,RightHits: Integer;
  Seconds, Speed, MaxSpeed, FirstFlip, FirstBump, Gap, MaxPause: Double;
  TurnError: Double;
  Renderer: TRhythmRenderer;
  Canvas: TBitmap;
  PNG: TPngImage;
  JPEG: TJPEGImage;
  Report: TStringList;
  Frames, Hash: string;
  FS: TFormatSettings;
  procedure Draw(Time: Double; Kind: Integer; const Screenshot: string);
  begin
    Renderer.Render(Canvas,Cold,Time,Kind);
    Need(Renderer.Notice='','Render warning: '+Renderer.Notice);
    if Screenshot<>'' then begin
      PNG.Assign(Canvas);
      PNG.SaveToFile(TPath.Combine(Evidence,Name+'-'+Screenshot+'.png'));
    end;
  end;
begin
  Plan:=nil; ColdPlan:=nil; Cold:=nil; Renderer:=nil; Canvas:=nil; PNG:=nil; JPEG:=nil; Report:=nil;
  try
    Writeln('Preparing ',Name);
    Plan := TRhythmBallPlan.Build(Audio);
    Need(Plan.Pinball<>nil,'Current plan is not fixed pinball');
    if Audio.Duration>=6 then Need(Plan.Pinball.Count>0,'Ball never launched');
    Ref := NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsBall);
    Ref.SourceRevision := Audio.SourceRevision;
    Plan.Save(Ref,nil,Audio);
    Cold := TRhythmBallPlan.LoadAudioMetadata(Ref,Audio.Source,0);
    Need((Length(Cold.PCM)=0) and Cold.HasHitDetails,'Cold restoration does not preserve source accents');
    ColdPlan := TRhythmBallPlan.Load(Ref,Cold,0);
    Need(ColdPlan.Pinball.Synced=Plan.Pinball.Synced,'Cold restoration loses synchrony');
    CheckCamera(Plan.Pinball,ColdPlan.Pinball,Name,RenderFrames);
    for I := 0 to 199 do begin
      Seconds := Plan.EndTime*((I*71) mod 199)/198;
      Actual := Plan.PositionAt(Seconds);
      Other := ColdPlan.PositionAt(Seconds);
      Need(BallLength(BallSub(Actual,Other))<1E-10,'Random seek changed ball position');
    end;
    FS := TFormatSettings.Invariant;
    Report := TStringList.Create;
    Report.Add('time_s,body,source_index,strength,x,y,start_speed_us,arrival_speed_us,side_rail,kicker_hold_s');
    Flippers:=0; Bumpers:=0; Kickers:=0; Walls:=0; LeftHits:=0; RightHits:=0;
    FirstFlip:=-1; FirstBump:=-1; MaxSpeed:=0; MaxPause:=0; N:=0;
    for I := 0 to Plan.Pinball.Count-1 do begin
      Contact := Plan.Pinball.Contact[I];
      Shot := Plan.Pinball.Flight[I];
      Actual := Plan.PositionAt(Contact.Time);
      Need(BallLength(BallSub(Actual,Contact.P))<1E-7,'Playback misses collision point');
      if Contact.Time>ClipSeconds then Continue;
      Inc(N);
      if Shot.Bank<>0 then Inc(Walls);
      Gap := 0;
      if I>0 then Gap:=Shot.First-Plan.Pinball.Contact[I-1].Time;
      MaxPause := Max(MaxPause,Gap);
      Speed := BallLength(PinVelocity(Shot,Contact.Time));
      MaxSpeed := Max(MaxSpeed,Max(Speed,BallLength(Shot.Velocity)));
      TurnError := 0;
      if Contact.Source>=0 then begin
        TurnError := Audio.Hits[Contact.Source].Strength;
        Need(Contact.Time=Audio.Hits[Contact.Source].Time,'Source accent was retimed');
        if Contact.Body<PIN_BUMPERS then begin
          Inc(Bumpers);
          if (FirstBump<0) and (Contact.Time>1.4) then FirstBump:=Contact.Time;
        end else if Contact.Body<PIN_KICKER then begin
          Inc(Flippers);
          if Contact.Body=PIN_LEFT_FLIPPER then Inc(LeftHits) else Inc(RightHits);
          if FirstFlip<0 then FirstFlip:=Contact.Time;
        end else Inc(Kickers);
      end;
      Report.Add(Format('%.9f,%d,%d,%.4f,%.6f,%.6f,%.4f,%.4f,%d,%.6f',
        [Contact.Time,Contact.Body,Contact.Source,TurnError,Contact.P.X,Contact.P.Y,
        BallLength(Shot.Velocity),Speed,Shot.Bank,Gap],FS));
    end;
    Report.SaveToFile(TPath.Combine(Evidence,Name+'-contacts.csv'),TEncoding.UTF8);
    Writeln(Format('%s: %d accents (threshold %d eligible full track), first %ds %d contacts, synced left/right %d/%d bumpers %d kicker %d, banks %d / peak speed %.3f / longest hold %.3f / total contacts %d',
      [Name,Length(Audio.Hits),Plan.Pinball.StrongCandidates,ClipSeconds,N,LeftHits,RightHits,Bumpers,Kickers,Walls,MaxSpeed,MaxPause,Plan.Pinball.Count],FS));
    if RenderFrames then begin
      Need((Audio.Duration>=ClipSeconds) and (Plan.Pinball.Contact[Plan.Pinball.Count-1].Time>=ClipSeconds),'Real song stopped before the end of the clip');
      Need((Flippers>=3) and (Bumpers>=4),'Real song has too few distinct synced contacts');
      Renderer := TRhythmRenderer.Create;
      PortraitRef := NewPlanRef(Audio.Key,Audio.Sensitivity,1,rsBall);
      PortraitRef.SourceRevision := Audio.SourceRevision;
      Plan.Save(PortraitRef,nil,Audio);
      Renderer.ConfigureStyle(rsBall,PortraitRef);
      Canvas := TBitmap.Create;
      Canvas.PixelFormat := pf32bit;
      PNG := TPngImage.Create;
      for J := 0 to 1 do begin
        Renderer.UseD2D := J=1;
        Renderer.ConfigureStyle(rsBall,PortraitRef);
        Canvas.SetSize(540,960);
        Draw(FirstFlip,1,'');
        if J=1 then Need(Renderer.LastUsedD2D,'Direct2D unavailable');
        Hash := FrameHash(Canvas);
        Draw(ClipSeconds,1,'');
        Draw(FirstFlip,1,'');
        Need(Hash=FrameHash(Canvas),'Rendering depends on seek order');
        Renderer.ConfigureStyle(rsBall,Ref);
        Canvas.SetSize(1280,720);
        Draw(FirstFlip,0,'');
        if J=1 then Need(Renderer.LastUsedD2D,'Landscape Direct2D unavailable');
        Hash := FrameHash(Canvas);
        Draw(ClipSeconds,0,'');
        Draw(FirstFlip,0,'');
        Need(Hash=FrameHash(Canvas),'Landscape pixels depend on seek order');
      end;
      Canvas.SetSize(540,960);
      Renderer.ConfigureStyle(rsBall,PortraitRef);
      Draw(0,1,'opening');
      Draw(FirstFlip-0.052,1,'flip-approach');
      Draw(FirstFlip,1,'flip-contact');
      Draw(FirstFlip+0.080,1,'flip-departure');
      Draw(FirstBump,1,'bumper-contact');
      Canvas.SetSize(1280,720);
      Renderer.ConfigureStyle(rsBall,Ref);
      Draw(0,0,'landscape');
      Draw(FirstFlip,0,'landscape-flip');
      Draw(FirstBump,0,'landscape-bumper');
      if ExportClip then begin
        Frames := TPath.Combine(Evidence,Name+'-frames');
        ForceDirectories(Frames);
        Need(Length(Audio.PCM)>=ClipSeconds*RHYTHM_RATE*4,'Clip source PCM is too short');
        TFile.WriteAllBytes(TPath.Combine(Evidence,Name+'-audio.pcm'),
          Copy(Audio.PCM,0,ClipSeconds*RHYTHM_RATE*4));
        if WideClip then Canvas.SetSize(960,540)
        else begin
          Canvas.SetSize(540,960);
          Renderer.ConfigureStyle(rsBall,PortraitRef);
        end;
        JPEG := TJPEGImage.Create;
        JPEG.CompressionQuality := 85;
        for I := 0 to ClipSeconds*Rate-1 do begin
          Draw(I/Rate,Ord(not WideClip),'');
          JPEG.Assign(Canvas);
          JPEG.SaveToFile(TPath.Combine(Frames,Format('frame-%.5d.jpg',[I])));
        end;
      end;
    end;
  finally
    Report.Free; JPEG.Free; PNG.Free; Canvas.Free; Renderer.Free; ColdPlan.Free; Cold.Free; Plan.Free;
  end;
end;

procedure RunSynthetic(const Name: string; Gap,Duration: Double; Number: Integer);
var Audio: TRhythmAudio;
begin
  Audio := SampleAudio(Name,Gap,Duration,Number);
  try Test(Audio,Name,False,False,False);finally Audio.Free;end;
end;

procedure RunTrack(const Filename: string; ExportClip, WideClip: Boolean);
var Audio: TRhythmAudio;
begin
  Audio := DecodeRhythmAudio(Filename,50);
  try Test(Audio,'real-track',True,ExportClip,WideClip);finally Audio.Free;end;
end;

begin
  try
    ConfigureRhythmProduct('SYNC_RhythmBall','Pinball table test',rsBall);
    Evidence := TPath.Combine(ExtractFileDir(ParamStr(0)),'PinballEvidence');
    ForceDirectories(Evidence);
    if ParamCount>0 then RunTrack(ParamStr(1),(ParamStr(2)='clip') or (ParamStr(2)='clip-wide'),ParamStr(2)='clip-wide') else begin
      RunSynthetic('silent',1,0.8,0);
      RunSynthetic('short',0.2,0.6,2);
      RunSynthetic('dense',0.12,29,230);
      RunSynthetic('sparse',2.8,29,10);
    end;
    Writeln('Pinball table PASS ',Checks);
  except on E: Exception do begin
    Writeln(E.ClassName,': ',E.Message);
    ExitCode := 1;
  end;end;
end.
