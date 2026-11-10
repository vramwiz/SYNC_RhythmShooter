program ParkourSmoke;
{$APPTYPE CONSOLE}
// 実WAVの検出時刻・接触軌道・保存復元を検証し、必要なら試写用の連番を出力する。
uses System.SysUtils, System.Classes, System.Math, System.IOUtils, System.Hash,
  Vcl.Graphics, Vcl.Imaging.pngimage, RhythmAudio, RhythmStyles, RhythmPrepare,
  RhythmPlanRef, RhythmParkourPlan, RhythmScene;

const DemoSeconds = 18;
      FrameRate = 30;

procedure Need(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure WriteDemoWave(const Path: string);
const SamplesPerBeat = RHYTHM_RATE div 2;
      Notes: array[0..7] of Double = (130.81, 130.81, 155.56, 130.81, 116.54, 116.54, 155.56, 103.83);
type TWaveHeader = packed record
       Riff, RiffSize, Wave, Fmt, FmtSize: Cardinal;
       Format, Channels: Word;
       Rate, ByteRate: Cardinal;
       Align, Bits: Word;
       Data, DataSize: Cardinal;
     end;
var Header: TWaveHeader; Samples: TArray<SmallInt>; FileStream: TFileStream; Existing: TBytes;
  I, Beat: Integer; T, Note, Kick, Snare, Hat, Level: Double;
begin
  SetLength(Samples, DemoSeconds * RHYTHM_RATE);
  for I := RHYTHM_RATE div 4 to High(Samples) - RHYTHM_RATE div 4 do
  begin
    Beat := (I - RHYTHM_RATE div 4) div SamplesPerBeat;
    T := ((I - RHYTHM_RATE div 4) mod SamplesPerBeat) / RHYTHM_RATE;
    Note := Notes[Beat mod Length(Notes)];
    Kick := Sin(2 * Pi * (51 * T + 2.4 * (1 - Exp(-T * 44)))) * Exp(-T * 31);
    Snare := Sin(2 * Pi * 183 * T) * Sin(2 * Pi * 2741 * T) * Exp(-T * 52);
    Hat := Sin(2 * Pi * 3710 * T) * Sin(2 * Pi * 6581 * T) * Exp(-T * 76);
    Level := 0.44 * Kick + 0.11 * Hat;
    if Odd(Beat) then Level := 0.22 * Kick + 0.37 * Snare + 0.15 * Hat;
    Level := Level + 0.23 * Sin(2 * Pi * Note * T) * Exp(-T * 8) +
      0.06 * Sin(2 * Pi * Note * 3 * T) * Exp(-T * 15);
    Samples[I] := Round(32000 * Level * Min(1.0, T * 1300));
  end;
  Header.Riff := $46464952;
  Header.Wave := $45564157;
  Header.Fmt := $20746D66;
  Header.FmtSize := 16;
  Header.Format := 1;
  Header.Channels := 1;
  Header.Rate := RHYTHM_RATE;
  Header.Align := 2;
  Header.ByteRate := Header.Rate * Header.Align;
  Header.Bits := 16;
  Header.Data := $61746164;
  Header.DataSize := Length(Samples) * SizeOf(SmallInt);
  Header.RiffSize := SizeOf(Header) + Header.DataSize - 8;
  if FileExists(Path) and (TFile.GetSize(Path) = Header.RiffSize + 8) then
  begin
    Existing := TFile.ReadAllBytes(Path);
    if CompareMem(@Existing[0], @Header, SizeOf(Header)) and
      CompareMem(@Existing[SizeOf(Header)], @Samples[0], Header.DataSize) then Exit;
  end;
  FileStream := TFileStream.Create(Path, fmCreate);
  try
    FileStream.WriteBuffer(Header, SizeOf(Header));
    FileStream.WriteBuffer(Samples[0], Header.DataSize);
  finally
    FileStream.Free;
  end;
end;

function OriginalHit(Audio: TRhythmAudio; Time: Double): Boolean;
var Hit: TRhythmHit;
begin
  for Hit in Audio.Hits do
    if Hit.Time = Time then Exit(True);
  Result := False;
end;

function Distance(const A, B: TParkourPoint): Double;
begin
  Result := Hypot(A.X - B.X, A.Y - B.Y);
end;

procedure VerifyMoves(Plan: TParkourPlan; Audio: TRhythmAudio);
var Seen: set of TParkourKind; Move: TParkourMove; P, A, B: TParkourPoint;
  I, J, Landings, Releases, ExtraSteps, StepGroups, WallRuns, WallGrips: Integer; T, Radius: Double;
begin
  Seen := [];
  Landings := 0;
  Releases := 0;
  ExtraSteps := 0;
  StepGroups := 0;
  WallRuns := 0;
  WallGrips := 0;
  for Move in Plan.Moves do
  begin
    Include(Seen, Move.Kind);
    Need(OriginalHit(Audio, Move.Cue), 'Action moved away from the detected onset');
    Need(Distance(Plan.Position(Move.Cue), Move.Contact) < 1E-9, 'Contact position');
    Need(Distance(Plan.Position(Move.Finish), Move.Landing) < 1E-9, 'Landing position');
    for T in TArray<Double>.Create(Move.Start, Move.Cue, Move.Release, Move.Finish) do
    begin
      A := Plan.Position(T - 1E-6);
      B := Plan.Position(T + 1E-6);
      Need(Distance(A, B) < 0.002, 'Discontinuity at a motion boundary');
    end;
    if Move.LandSynced then
    begin
      Need(OriginalHit(Audio, Move.Finish), 'Landing moved away from the detected onset');
      Inc(Landings);
    end;
    if Move.Kind = pkWire then
    begin
      Need(OriginalHit(Audio, Move.Release), 'Wire release is off beat');
      Inc(Releases);
      A := Move.Contact;
      A.X := A.X + ParkourHandOffset;
      A.Y := A.Y + ParkourHandHeight;
      Radius := Distance(A, Move.Anchor);
      for I := 0 to 40 do
      begin
        P := Move.Position(Move.Cue + (Move.Release - Move.Cue) * I / 40);
        P.X := P.X + ParkourHandOffset;
        P.Y := P.Y + ParkourHandHeight;
        Need(Abs(Distance(P, Move.Anchor) - Radius) < 1E-9, 'Wire length changes during swing');
      end;
    end;
    if Move.Kind in [pkWall, pkWallRun] then
      for I := 1 to 99 do
      begin
        P := Move.Position(Move.Release + (Move.Finish - Move.Release) * I / 100);
        Need((P.X < Move.RoofLeft) or (P.Y >= Move.Landing.Y), 'Runner crosses inside wall');
      end;
    if Move.Kind = pkStride then
    begin
      Inc(StepGroups);
      for J := 0 to 120 do
      begin
        P := Move.Position(Move.Start + (Move.Finish - Move.Start) * J / 120);
        for I := 0 to High(Move.Steps) do
        begin
          A := Move.StepPoint(I);
          if InRange(P.X, A.X - 0.22, A.X + 0.28) then Need(P.Y >= A.Y - 1E-9, 'Path clips step platform');
        end;
      end;
    end;
    if Move.Kind = pkWallRun then Inc(WallRuns);
    for I := 0 to High(Move.Steps) do
    begin
      T := Move.Steps[I];
      Need(OriginalHit(Audio, T), 'Step is off beat');
      Need(Move.StepAt(T) = I, 'Step changes sides off beat');
      Need(Distance(Plan.Position(T), Move.StepPoint(I)) < 1E-9, 'Step misses surface position');
      Need(Distance(Plan.Position(T - 1E-6), Plan.Position(T + 1E-6)) < 0.002, 'Step path jumps');
      if Move.Kind = pkWallRun then
      begin
        A := Move.WallGripPoint(I);
        P := Move.StepPoint(I);
        Need(InRange(A.X, Move.RoofLeft - 0.05, Move.RoofLeft + 0.06) and
          InRange(A.Y - P.Y, 0.74, 0.90), 'Hand misses the wall or climbs out of reach');
        Need(Abs(Move.WallGripWeight(I, T) - 1) < 1E-9, 'Hand is not planted at foot contact');
        if I < High(Move.Steps) then
        begin
          T := Move.Steps[I + 1] - 0.04;
          Need((Move.WallGripWeight(I, T) > 0.999) and (Move.WallGripWeight(I + 1, T) > 0.999),
            'Hand releases before the next grip');
        end
        else
          Need((A.Y = Move.Landing.Y) and
            (Move.WallGripWeight(I, Move.Release + (Move.Finish - Move.Release) * 0.19) = 1),
            'Rim grip is missing during the pull-up');
        Inc(WallGrips);
      end;
      if I > 0 then Inc(ExtraSteps);
    end;
  end;
  Need([pkStride, pkWallRun, pkWire, pkDrop] <= Seen, 'Demo misses a key movement');
  Need(Length(Plan.Moves) + ExtraSteps + Releases + Landings >= 26, 'Same demo has too few synchronized contacts');
  WriteLn('Parkour contacts: ', Length(Plan.Moves) + ExtraSteps + Releases + Landings,
    ' total, ', StepGroups, ' stride chains, ', WallRuns, ' wall runs, ', ExtraSteps, ' extra steps, ',
    WallGrips, ' wall grips.');
end;

procedure VerifySparse;
var Audio: TRhythmAudio; Plan: TParkourPlan;
begin
  Audio := TRhythmAudio.Create;
  try
    Audio.Duration := 0.12;
    Plan := BuildParkourPlan(Audio, nil);
    try
      Need((Length(Plan.Moves) = 0) and (Plan.Position(10).X = 0), 'Silent short input');
    finally
      Plan.Free;
    end;
    Audio.Duration := 28;
    SetLength(Audio.Hits, 4);
    Audio.Hits[0].Time := 1;
    Audio.Hits[1].Time := 8;
    Audio.Hits[2].Time := 15;
    Audio.Hits[3].Time := 22;
    Plan := BuildParkourPlan(Audio, nil);
    try
      Need((Length(Plan.Moves) = 4) and (Plan.Moves[2].Kind = pkVault) and
        not Plan.Moves[2].LandSynced, 'Sparse input invented a synchronized landing or release');
    finally
      Plan.Free;
    end;
  finally
    Audio.Free;
  end;
end;

procedure VerifyRapid;
var Audio: TRhythmAudio; Plan: TParkourPlan; I, Chains, WallRuns: Integer; Move: TParkourMove;
begin
  Audio := TRhythmAudio.Create;
  try
    Audio.Duration := 20;
    SetLength(Audio.Hits, 81);
    for I := 0 to High(Audio.Hits) do Audio.Hits[I].Time := 0.25 + 0.23 * I;
    Plan := BuildParkourPlan(Audio, nil);
    try
      Chains := 0;
      WallRuns := 0;
      for Move in Plan.Moves do
      begin
        Need(Move.Kind <> pkWire, 'Rapid section uses a slow wire swing');
        if (Move.Kind = pkStride) and (Length(Move.Steps) = 4) then Inc(Chains);
        if (Move.Kind = pkWallRun) and (Length(Move.Steps) = 4) then Inc(WallRuns);
      end;
      Need((Chains >= 2) and (WallRuns >= 2), 'Rapid section did not sustain multi-step movement');
      WriteLn('Rapid fixture: ', Chains, ' four-beat stride chains, ', WallRuns, ' four-beat wall runs.');
    finally
      Plan.Free;
    end;
  finally
    Audio.Free;
  end;
end;

procedure VerifyV1(Audio: TRhythmAudio);
var Original, Restored: TParkourPlan; Ref: TRhythmPlanRef;
begin
  Original := TParkourPlan.Create;
  try
    Original.Duration := Audio.Duration;
    SetLength(Original.Moves, 1);
    Original.Moves[0].Kind := pkVault;
    Original.Moves[0].Start := 0.25;
    Original.Moves[0].Cue := 0.25;
    Original.Moves[0].Release := 0.25;
    Original.Moves[0].Finish := 0.75;
    Ref := NewPlanRef(Audio.Key, Audio.Sensitivity, 0, rsParkour);
    Ref.Version := 1;
    Ref.Key := THashSHA2.GetHashString('parkour-v1|' + Audio.Key + '|' + IntToStr(Audio.Sensitivity) + '|0');
    Ref.SourceRevision := Audio.SourceRevision;
    SaveParkourPlan(Original, Audio, Ref);
    Restored := LoadParkourPlan(Ref, Audio, 0);
    try
      Need((Length(Restored.Moves) = 1) and (Length(Restored.Moves[0].Steps) = 0) and
        (Restored.Position(0.50).Y > 0.50), 'Version-one vault cannot be restored');
    finally
      Restored.Free;
    end;
  finally
    Original.Free;
  end;
end;

function ImageHash(Image: TBitmap): string;
var Hasher: THashSHA2; I: Integer;
begin
  Hasher := THashSHA2.Create;
  for I := 0 to Image.Height - 1 do Hasher.Update(Image.ScanLine[I]^, Image.Width * 4);
  Result := Hasher.HashAsString;
end;

procedure RenderEvidence(const Folder: string; const Ref: TRhythmPlanRef;
  Plan: TParkourPlan; Live, Cold: TRhythmAudio);
var Renderer: TRhythmRenderer; Image: TBitmap; PNG: TPngImage; Move: TParkourMove;
  T: Double; Digest, Frames: string; Backend, I: Integer; Seen: set of TParkourKind;
begin
  Renderer := TRhythmRenderer.Create;
  Image := TBitmap.Create;
  PNG := TPngImage.Create;
  try
    Renderer.ConfigureStyle(rsParkour, Ref, 0, 0);
    Image.PixelFormat := pf32bit;
    Image.SetSize(960, 540);
    for Backend := 0 to 1 do
    begin
      Renderer.UseD2D := Backend = 1;
      for I := High(Plan.Moves) downto 0 do
      begin
        T := Plan.Moves[I].Cue;
        Renderer.Render(Image, Live, T, 0);
        Digest := ImageHash(Image);
        Renderer.Render(Image, Cold, Plan.Duration - T, 0);
        Renderer.Render(Image, Cold, T + 0.25, 0, '', 1, 0, 0, 0.25);
        Need(ImageHash(Image) = Digest, 'Cold seek or offset changed the frame');
      end;
      if Backend = 1 then Need(Renderer.LastUsedD2D, 'Direct2D fallback');
    end;
    Seen := [];
    for Move in Plan.Moves do
    begin
      if Move.Kind in Seen then Continue;
      Include(Seen, Move.Kind);
      T := Move.Cue;
      if Move.Kind = pkWire then T := (T + Move.Release) / 2;
      if Length(Move.Steps) > 1 then T := Move.Steps[1];
      Renderer.Render(Image, Cold, T, 0);
      PNG.Assign(Image);
      PNG.SaveToFile(TPath.Combine(Folder, Format('parkour-%d.png', [Ord(Move.Kind)])));
      if Move.Kind = pkWallRun then
      begin
        Renderer.Render(Image, Cold, Move.Release + (Move.Finish - Move.Release) * 0.20, 0);
        PNG.Assign(Image);
        PNG.SaveToFile(TPath.Combine(Folder, 'parkour-wall-mantle.png'));
      end;
    end;
    if SameText(ParamStr(1), 'demo') then
    begin
      Frames := TPath.Combine(Folder, 'Frames');
      ForceDirectories(Frames);
      for I := 0 to Round(Plan.Duration * FrameRate) - 1 do
      begin
        Renderer.Render(Image, Cold, I / FrameRate, 0);
        PNG.Assign(Image);
        PNG.SaveToFile(TPath.Combine(Frames, Format('frame%.4d.png', [I])));
      end;
    end;
  finally
    PNG.Free;
    Image.Free;
    Renderer.Free;
  end;
end;

var Folder, Source: string; Worker: TRhythmPrepareThread; Audio, Cold: TRhythmAudio;
  Plan: TParkourPlan; Ref: TRhythmPlanRef;
begin
  Worker := nil;
  Audio := nil;
  Cold := nil;
  Plan := nil;
  try
    VerifySparse;
    VerifyRapid;
    Folder := TPath.Combine(ExtractFileDir(ParamStr(0)), 'Evidence');
    ForceDirectories(Folder);
    Source := TPath.Combine(Folder, 'ParkourBeat.wav');
    WriteDemoWave(Source);
    Worker := TRhythmPrepareThread.Create(Source, 50, 0, rsParkour, True, nil, 1);
    Worker.Start;
    Worker.WaitFor;
    Need(Worker.Error = '', Worker.Error);
    Ref := Worker.Plan;
    Audio := Worker.TakeAudio;
    Cold := LoadParkourAudio(Ref, Source, 0);
    Need(Length(Cold.PCM) = 0, 'Cold audio has PCM');
    Plan := LoadParkourPlan(Ref, Cold, 0);
    VerifyV1(Audio);
    VerifyMoves(Plan, Audio);
    RenderEvidence(Folder, Ref, Plan, Audio, Cold);
    WriteLn('Parkour PASS, ', Length(Audio.Hits), ' detected WAV onsets; GDI/Direct2D, cold seek and offset.');
  except
    on E: Exception do
    begin
      WriteLn(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
  Plan.Free;
  Cold.Free;
  Audio.Free;
  Worker.Free;
end.
