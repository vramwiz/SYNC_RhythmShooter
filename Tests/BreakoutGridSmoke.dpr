program BreakoutGridSmoke;
{$APPTYPE CONSOLE}
// Check complete openings, original onsets, and read-only preview frames for the fixed-grid plan.
uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.Math, System.Hash, System.Classes,
  Vcl.Graphics, Vcl.Imaging.pngimage, RhythmAudio, RhythmAudioDecode, RhythmBreakoutPlan,
  RhythmBreakoutGeometry, RhythmPlanRef, RhythmProduct, RhythmStyles, RhythmScene;

var
  Evidence: string;
  Checks: Integer;

procedure Need(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
  Inc(Checks);
end;

function Synthetic(Duration, Gap: Double; Mode: Integer): TRhythmAudio;
var
  Index: Integer;
  NextTime: Double;
  Stamp: TWin32FileAttributeData;
begin
  Result := TRhythmAudio.Create;
  try
    Result.Duration := Duration;
    Result.SoundEnd := Duration;
    Result.Sensitivity := 50;
    Result.Source := TPath.Combine(Evidence,'fixture-'+IntToStr(Mode)+'.identity');
    TFile.WriteAllText(Result.Source,IntToStr(Mode));
    Result.Key := THashSHA2.GetHashString('fixed-grid-test-'+IntToStr(Mode));
    Need(GetFileAttributesEx(PChar(Result.Source),GetFileExInfoStandard,@Stamp),'Fixture stamp');
    Result.SourceRevision := IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+
      IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    NextTime := 0.2;
    SetLength(Result.Hits,Ceil(Duration/Gap)*2+1);
    Index := 0;
    while NextTime<Duration do begin
      Result.Hits[Index].Time := NextTime;
      Result.Hits[Index].Strength := 0.35+0.13*(Index mod 5);
      if Mode=2 then NextTime := NextTime+Gap*(0.58+(Index mod 7)*0.15)
      else NextTime := NextTime+Gap;
      Inc(Index);
    end;
    if Mode=0 then Index := 0;
    SetLength(Result.Hits,Index);
    if Mode=4 then begin
      SetLength(Result.Envelope,Round(Duration*100));
      for Index := 0 to High(Result.Envelope) do
        if ((Index>=2000) and (Index<3200)) or ((Index>=6000) and (Index<7200)) then
          Result.Envelope[Index] := 0.75
        else Result.Envelope[Index] := 0.03125;
      Result.UpdateSoundBounds;
    end;
  except
    Result.Free;
    raise;
  end;
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
  finally
    Stream.Free;
  end;
end;

procedure CheckPlan(Audio: TRhythmAudio; const Name: string; SaveFrames: Boolean; OpeningMin: Integer);
var
  Plan, ColdPlan: TBreakoutPlan;
  Cold: TRhythmAudio;
  Ref: TRhythmPlanRef;
  Brick, Initial: TBreakBlock;
  A,B: TBreakPoint;
  X,Y,I,J,Opening,Cols,Rows,Matches,UpperHits: Integer;
  Left,Right,Top,Bottom,Seconds,Impact,Alpha,NearEnd: Double;
  Image: TBitmap;
  PNG: TPngImage;
  Renderer: TRhythmRenderer;
  Before: string;
begin
  Plan := nil;
  ColdPlan := nil;
  Cold := nil;
  Image := nil;
  PNG := nil;
  Renderer := nil;
  try
    Writeln('Checking ',Name);
    Plan := TBreakoutPlan.Build(Audio);
    Need(Plan.FixedGrid,'Wrong current plan');
    Left := BREAK_WIDTH;
    Right := 0;
    Top := 1;
    Bottom := 0;
    Opening := 0;
    Matches := 0;
    UpperHits := 0;
    for I := 0 to Plan.Count-1 do begin
      Brick := Plan.Block[I];
      if Plan.BlockVisible(I,0) then begin
        Inc(Opening);
        Left := Min(Left,Brick.Left);
        Right := Max(Right,Brick.Right);
        Top := Min(Top,Brick.Top);
        Bottom := Max(Bottom,Brick.Bottom);
        Initial := Plan.BlockAt(I,0);
        Need((Initial.Left=Brick.Left) and (Initial.Top=Brick.Top),'Brick moves before impact');
      end;
      if Brick.Source<0 then begin
        Need(Brick.Time>Plan.EndTime,'An unhit brick disappeared');
        Continue;
      end;
      Need(Brick.Time=Audio.Hits[Brick.Source].Time,'Lost original onset');
      if Plan.BlockVisible(I,0) then for J := I+1 to Plan.Count-1 do
        if Plan.BlockVisible(J,0) and (Plan.Block[J].Top>Brick.Top+1E-7) then begin
          Inc(UpperHits);
          Break;
        end;
      A := Plan.PositionAt(Brick.Time);
      Need((A.X>=Brick.Left-1E-7) and (A.X<=Brick.Right+1E-7) and
        (Abs(A.Y-Brick.Bottom-BREAK_RADIUS)<1E-7),'Ball misses the brick');
      Inc(Matches);
    end;
    Need(Opening>=OpeningMin,'Opening too sparse');
    Cols := 0;
    Rows := 0;
    if Opening>0 then begin
      Cols := Round((Right-Left-0.126)/0.144)+1;
      Rows := Round((Bottom-Top-0.028)/0.041)+1;
      Need(Opening=Cols*Rows,'Opening holes');
      for Y := 0 to Rows-1 do for X := 0 to Cols-1 do begin
        J := 0;
        for I := 0 to Opening-1 do begin
          Brick := Plan.BlockAt(I,0);
          if (Abs(Brick.Left-Left-X*0.144)<1E-7) and (Abs(Brick.Top-Top-Y*0.041)<1E-7) then Inc(J);
        end;
        Need(J=1,'Cell is missing or duplicated');
      end;
      A := Plan.PositionAt(0);
      Need((Abs(A.X-Plan.PaddleAt(0))<=Plan.PaddleHalf) and (Abs(A.Y-BREAK_PADDLE_Y)<1E-7),'Incomplete launch position');
    end;
    if Name='dense' then Need(UpperHits>0,'No shots through openings in lower rows');
    if Name='boss' then Need(Plan.BossCount>=2,'Lost boss sequences');
    if Name='sparse' then Need(Plan.CatchCount>0,'No hold for sparse onsets');
    Ref := NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsBreakout,StyleVariant(rsBreakout,50,Audio.BossFrequency));
    Ref.SourceRevision := Audio.SourceRevision;
    Plan.Save(Ref,Audio);
    Cold := TBreakoutPlan.LoadAudioMetadata(Ref,Audio.Source,0);
    Need(Length(Cold.PCM)=0,'Cold loaded PCM');
    ColdPlan := TBreakoutPlan.Load(Ref,Cold,0);
    Need(ColdPlan.FixedGrid and (Plan.Count=ColdPlan.Count),'Cold plan changed');
    for I := 0 to 99 do begin
      Seconds := Plan.EndTime*((I*73) mod 101)/100;
      A := Plan.PositionAt(Seconds);
      B := ColdPlan.PositionAt(Seconds);
      Need((Hypot(A.X-B.X,A.Y-B.Y)<1E-9) and (Abs(Plan.PaddleAt(Seconds)-ColdPlan.PaddleAt(Seconds))<1E-9),
        'Cold random seek changed path');
    end;
    if SaveFrames then begin
      Renderer := TRhythmRenderer.Create;
      Renderer.ConfigureStyle(rsBreakout,Ref);
      Image := TBitmap.Create;
      Image.PixelFormat := pf32bit;
      Image.SetSize(1280,720);
      PNG := TPngImage.Create;
      Impact := Plan.Block[0].Time;
      NearEnd := Plan.Block[Opening-1].Time;
      for J := 0 to 1 do begin
        Renderer.UseD2D := J=1;
        for I := 0 to 4 do begin
          case I of
            0: Seconds := 0;
            1: Seconds := Max(Plan.LaunchTime,Impact-0.045);
            2: Seconds := Impact+0.055;
            3: Seconds := (Impact+NearEnd)*0.5;
          else Seconds := Max(Impact,NearEnd-0.06);
          end;
          Renderer.Render(Image,Cold,Seconds,0);
          if J=1 then Need(Renderer.LastUsedD2D,'Direct2D unavailable');
          Before := FrameHash(Image);
          Renderer.Render(Image,Cold,Plan.EndTime,0);
          Renderer.Render(Image,Cold,Seconds,0);
          Need(Before=FrameHash(Image),'Rendered seek changed frame');
          if J=0 then begin
            PNG.Assign(Image);
            PNG.SaveToFile(TPath.Combine(Evidence,Name+'-'+IntToStr(I)+'.png'));
          end;
        end;
      end;
      Need(Plan.MainAt(Impact,A,Alpha) and (Alpha>0),'First impact hidden');
    end;
    Writeln(Name,': ',Cols,'x',Rows,' opening; ',Matches,' synced bricks / ',Length(Audio.Hits),
      ' candidates; ',UpperHits,' shots through openings; ',Plan.BossCount,' bosses; ',Plan.CatchCount,' holds; key ',Ref.Key);
  finally
    PNG.Free;
    Image.Free;
    Renderer.Free;
    ColdPlan.Free;
    Cold.Free;
    Plan.Free;
  end;
end;

procedure RunSynthetic(Duration, Gap: Double; Mode, OpeningMin: Integer; const Name: string);
var
  Audio: TRhythmAudio;
begin
  Audio := Synthetic(Duration,Gap,Mode);
  try CheckPlan(Audio,Name,False,OpeningMin); finally Audio.Free; end;
end;

procedure RunTrack(const Filename, Name: string);
var
  Audio: TRhythmAudio;
begin
  Audio := DecodeRhythmAudio(Filename,50);
  try CheckPlan(Audio,Name,True,12); finally Audio.Free; end;
end;

var
  I: Integer;
begin
  try
    ConfigureRhythmProduct('SYNC_RhythmBreakout','Breakout validation',rsBreakout);
    Evidence := TPath.Combine(ExtractFileDir(ParamStr(0)),'GridEvidence');
    ForceDirectories(Evidence);
    if ParamCount=0 then begin
      RunSynthetic(2,0.36,0,12,'silent');
      RunSynthetic(0.5,0.25,6,12,'short');
      RunSynthetic(64,0.042,1,24,'dense');
      RunSynthetic(115,0.37,2,24,'mixed');
      RunSynthetic(95,4.1,3,12,'sparse');
      RunSynthetic(90,0.18,4,12,'boss');
      RunSynthetic(1800,0.43,5,24,'long');
    end else for I := 1 to ParamCount do RunTrack(ParamStr(I),'track-'+IntToStr(I));
    Writeln('Breakout grid PASS ',Checks);
  except
    on E: Exception do begin
      Writeln(E.ClassName,': ',E.Message);
      ExitCode := 1;
    end;
  end;
end.
