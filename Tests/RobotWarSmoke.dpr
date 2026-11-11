program RobotWarSmoke;
{$APPTYPE CONSOLE}
// 共通の解析・準備・保存・描画を通し、変形/合体の境界とシークを実行して確認する。
uses Winapi.Windows, System.SysUtils, System.Classes, System.Math, System.IOUtils, System.Hash,
  Vcl.Graphics, Vcl.Imaging.pngimage, RhythmAudio, RhythmStyles, RhythmPrepare, RhythmPlanRef,
  RhythmScene, RhythmRobotPlan, RhythmRobotPose, RhythmRobotCodec, RhythmSettings;

const DemoSeconds = 96; VideoRate = 24;
var Folder, Source: string; Audio, Cold: TRhythmAudio; Plan, Restored: TRobotPlan;
  Renderer: TRhythmRenderer; Image, Sheet: TBitmap; Ref: TRhythmPlanRef; Checks: Integer;

procedure Need(Value: Boolean; const MessageText: string);
begin
  Inc(Checks);
  if not Value then raise Exception.Create(MessageText);
end;

procedure WriteDemoWave(const Path: string);
type THeader = packed record
  Riff, RiffSize, Wave, Fmt, FmtSize: Cardinal;
  Format, Channels: Word;
  Rate, ByteRate: Cardinal;
  Align, Bits: Word;
  Data, DataSize: Cardinal;
end;
var Header: THeader; Samples: TArray<SmallInt>; Stream: TFileStream;
  I, Beat: Integer; T, Level, Note: Double;
begin
  if FileExists(Path) then Exit;
  Header := Default(THeader);
  SetLength(Samples, DemoSeconds * RHYTHM_RATE);
  for I := RHYTHM_RATE div 4 to High(Samples) - RHYTHM_RATE div 4 do
  begin
    Beat := (I - RHYTHM_RATE div 4) div (RHYTHM_RATE div 3);
    T := ((I - RHYTHM_RATE div 4) mod (RHYTHM_RATE div 3)) / RHYTHM_RATE;
    Note := 110 * Power(2, ((Beat div 8) mod 4) / 12);
    Level := 0.40 * Sin(2 * Pi * (49 * T + 2.4 * (1 - Exp(-T * 42)))) * Exp(-T * 28);
    if Odd(Beat) then Level := Level + 0.22 * Sin(2 * Pi * 181 * T) * Sin(2 * Pi * 2741 * T) * Exp(-T * 48);
    Level := Level + 0.13 * Sin(2 * Pi * Note * T) * Exp(-T * 8) +
      0.07 * Sin(2 * Pi * 3710 * T) * Sin(2 * Pi * 6581 * T) * Exp(-T * 66);
    Samples[I] := Round(30000 * Level * Min(1.0, T * 1200));
  end;
  Header.Riff := $46464952; Header.Wave := $45564157;
  Header.Fmt := $20746D66; Header.FmtSize := 16;
  Header.Format := 1; Header.Channels := 1;
  Header.Rate := RHYTHM_RATE; Header.ByteRate := RHYTHM_RATE * 2;
  Header.Align := 2; Header.Bits := 16; Header.Data := $61746164;
  Header.DataSize := Length(Samples) * 2;
  Header.RiffSize := SizeOf(Header) + Header.DataSize - 8;
  Stream := TFileStream.Create(Path, fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
    Stream.WriteBuffer(Samples[0], Header.DataSize);
  finally
    Stream.Free;
  end;
end;

function OriginalTime(Time: Double): Boolean;
var Hit: TRhythmHit;
begin
  for Hit in Audio.Hits do if Hit.Time = Time then Exit(True);
  Result := False;
end;

function ImageHash: string;
var Hash: THashSHA2; Y: Integer;
begin
  Hash := THashSHA2.Create;
  for Y := 0 to Image.Height - 1 do Hash.Update(Image.ScanLine[Y]^, Image.Width * 4);
  Result := Hash.HashAsString;
end;

procedure SaveImage(Bitmap: TBitmap; const Name: string);
var PNG: TPngImage;
begin
  PNG := TPngImage.Create;
  try
    PNG.Assign(Bitmap);
    PNG.SaveToFile(TPath.Combine(Folder, Name + '.png'));
  finally
    PNG.Free;
  end;
end;

procedure VerifyPlan;
var I, J, K, Combinations, Locks: Integer; Stage: TRobotStage; Cue: TRobotCue;
  A, B: TRobotView; Kind: TRobotPartKind; P, Q: TRobotPart; Aspect, T: Double;
  Settings, Saved: TRhythmSettings; Seen: set of TRobotAttack;
begin
  Seen := [];
  Combinations := 0;
  Locks := 0;
  for I := 0 to High(Plan.Stages) do
  begin
    Stage := Plan.Stages[I];
    if Stage.Kind = rkCombine then Inc(Combinations);
    for J := 0 to 7 do
      if Stage.Synced[J] then
      begin
        Need(OriginalTime(Stage.Locks[J]), 'Mechanism lock is off the source onset');
        if Stage.Kind in [rkTransform, rkCombine] then Inc(Locks);
      end;
    for Aspect in TArray<Double>.Create(16 / 9, 1, 9 / 16) do
      for J := 0 to 100 do
      begin
        T := Stage.Start + (Stage.Finish - Stage.Start) * J / 100;
        A := EvaluateRobotView(Plan, T, Aspect);
        for K := 0 to A.Count - 1 do
          for Kind := Low(TRobotPartKind) to High(TRobotPartKind) do
          begin
            P := A.Bodies[K].Parts[Kind];
            Need(not IsNan(P.X) and not IsInfinite(P.Y) and (P.W > 0) and (P.H > 0), 'Invalid part geometry');
            if (Stage.Kind = rkCombine) and (J > 0) and (J < 100) then
              Need((P.X - Hypot(P.W, P.H) * 0.5 >= A.CenterX - A.Width * 0.5 - 0.02) and
                (P.X + Hypot(P.W, P.H) * 0.5 <= A.CenterX + A.Width * 0.5 + 0.02) and
                (P.Y + Hypot(P.W, P.H) * 0.5 <= A.CenterY + A.Height * 0.5 + 0.02),
                'Combination cropped at stage ' + IntToStr(I));
          end;
      end;
    if I = 0 then Continue;
    A := EvaluateRobotView(Plan, Stage.Start - 1E-7, 16 / 9);
    B := EvaluateRobotView(Plan, Stage.Start + 1E-7, 16 / 9);
    Need(Abs(A.CenterX - B.CenterX) + Abs(A.Width - B.Width) < 0.001, 'Camera cut');
    for J := 0 to Min(A.Count, B.Count) - 1 do
      for K := 0 to B.Count - 1 do
        if (A.Bodies[J].Team = B.Bodies[K].Team) and (A.Bodies[J].Member = B.Bodies[K].Member) then
          for Kind := Low(TRobotPartKind) to High(TRobotPartKind) do
          begin
            P := A.Bodies[J].Parts[Kind];
            Q := B.Bodies[K].Parts[Kind];
            Need(Hypot(P.X - Q.X, P.Y - Q.Y) + Abs(P.Angle - Q.Angle) < 0.001,
              'Part teleports across stage ' + IntToStr(I) + '/' + IntToStr(Ord(Kind)));
          end;
  end;
  Need(Combinations = 4, 'Both teams require two- and three-unit combinations');
  for Cue in Plan.Cues do
  begin
    Include(Seen, Cue.Attack);
    Need(OriginalTime(Cue.Time), 'Combat moved off beat');
    Need(RobotCueWeight(Cue, Cue.Time) = 1, 'Contact pose is not on beat');
    A := EvaluateRobotView(Plan, Cue.Time - 1E-7, 16 / 9);
    B := EvaluateRobotView(Plan, Cue.Time + 1E-7, 16 / 9);
    Need(Abs(A.CenterX - B.CenterX) + Abs(A.CenterY - B.CenterY) < 0.001, 'Impact camera jump');
  end;
  Need(Seen = [raPunch, raKick, raSlash, raShot, raMissile, raBeam, raSpecial], 'Demo misses an attack class');
  Need(Length(Cold.PCM) = 0, 'Host restoration requires PCM');
  Settings := TRhythmSettings.Defaults;
  Settings.Style := rsRobotWar; Settings.Music := Source; Settings.Plan := Ref;
  Need(TRhythmSettings.TryJSON(Settings.ToJSON, Saved) and (Saved.Style = rsRobotWar) and
    (Saved.Plan.Digest = Ref.Digest), 'Settings persistence');
  WriteLn('Robot plan PASS ', Length(Plan.Cues), ' combat onsets, ', Locks, ' mechanism locks, ', Combinations, ' combinations.');
end;

procedure VerifyInputs;
var Duration, T: Double; TestAudio: TRhythmAudio; TestPlan: TRobotPlan;
  I, Mode: Integer; V: TRobotView; Cancelled: Boolean;
begin
  TestAudio := TRhythmAudio.Create;
  try
    for Duration in TArray<Double>.Create(0.05, 0.5, 2.0, 8.0, 18.0, 180.0) do
      for Mode := 0 to 2 do
      begin
        TestAudio.Duration := Duration;
        SetLength(TestAudio.Hits, 0);
        if Mode > 0 then
        begin
          SetLength(TestAudio.Hits, Floor(Duration / (0.07 + Mode * 0.15)));
          for I := 0 to High(TestAudio.Hits) do
          begin
            TestAudio.Hits[I].Time := (I + 0.5) * Duration / Length(TestAudio.Hits);
            TestAudio.Hits[I].Strength := 0.6;
          end;
        end;
        TestPlan := BuildRobotPlan(TestAudio, nil);
        try
          Need((Length(TestPlan.Stages) = 28) and (TestPlan.Stages[27].Kind = rkVictory), 'Short/silent finale');
          for I := 0 to 100 do
          begin
            T := Duration * I / 100;
            V := EvaluateRobotView(TestPlan, T, 16 / 9);
            Need((V.Count > 0) and (V.Count <= 6) and not IsNan(V.CenterX), 'Short/sparse/dense state');
          end;
        finally
          TestPlan.Free;
        end;
      end;
    Cancelled := False;
    try
      TestPlan := BuildRobotPlan(TestAudio, function: Boolean begin Result := True; end);
      TestPlan.Free;
    except
      on E: EAbort do Cancelled := True;
    end;
    Need(Cancelled, 'Preparation cancellation');
  finally
    TestAudio.Free;
  end;
end;

procedure VerifyRender;
const Scenes: array[0..11] of Integer = (1, 2, 2, 8, 8, 9, 13, 18, 18, 23, 25, 27);
      Progress: array[0..11] of Double = (0.9, 0.36, 0.92, 0.38, 0.97, 0.45, 0.97, 0.42, 0.97, 0.97, 0.63, 0.70);
var I, Backend: Integer; Time: Double; Expected: string; Stage: TRobotStage;
begin
  Image.SetSize(960, 540);
  Sheet.SetSize(1280, 540);
  for Backend := 0 to 1 do
  begin
    Renderer.UseD2D := Backend = 1;
    for I := 0 to High(Scenes) do
    begin
      Stage := Plan.Stages[Scenes[I]];
      Time := Stage.Start + (Stage.Finish - Stage.Start) * Progress[I];
      Renderer.Render(Image, Cold, Time, 0);
      Expected := ImageHash;
      Renderer.Render(Image, Cold, Plan.Duration * 0.94 - I, 0);
      Renderer.Render(Image, Cold, Time, 0);
      Need(ImageHash = Expected, 'Reverse seek changes frame');
      if Backend = 1 then
      begin
        SaveImage(Image, Format('Robot-%2.2d', [I]));
        Sheet.Canvas.StretchDraw(Rect((I mod 4) * 320, (I div 4) * 180,
          (I mod 4 + 1) * 320, (I div 4 + 1) * 180), Image);
      end;
    end;
  end;
  SaveImage(Sheet, 'RobotWarStoryboard');
  Renderer.Render(Image, Cold, 32, 0, '', 1.2, 25, -12, 0.17);
  Image.SetSize(540, 960);
  Renderer.Render(Image, Cold, Plan.Stages[18].Finish - 0.1, 0);
  SaveImage(Image, 'RobotWarPortrait');
end;

procedure RenderVideo;
var I, Y, Written: Integer; Bytes: TBytes; Count: DWORD; Output: THandle;
begin
  Renderer.UseD2D := True;
  Image.SetSize(960, 540);
  SetLength(Bytes, Image.Width * Image.Height * 4);
  Output := GetStdHandle(STD_OUTPUT_HANDLE);
  for I := 0 to DemoSeconds * VideoRate - 1 do
  begin
    Renderer.Render(Image, Cold, I / VideoRate, 0);
    for Y := 0 to Image.Height - 1 do Move(Image.ScanLine[Image.Height - 1 - Y]^,
      Bytes[Y * Image.Width * 4], Image.Width * 4);
    Written := 0;
    while Written < Length(Bytes) do
    begin
      if not WriteFile(Output, Bytes[Written], Length(Bytes) - Written, Count, nil) then RaiseLastOSError;
      if Count = 0 then raise Exception.Create('Video pipe closed');
      Inc(Written, Count);
    end;
  end;
end;

var Worker: TRhythmPrepareThread;
begin
  Restored := nil;
  try
    Folder := TPath.Combine(ExtractFileDir(ParamStr(0)), 'Evidence');
    ForceDirectories(Folder);
    Source := TPath.Combine(Folder, 'RobotBeat.wav');
    WriteDemoWave(Source);
    Worker := TRhythmPrepareThread.Create(Source, 50, 0, rsRobotWar, False, nil, 1);
    try
      Worker.Start;
      Worker.WaitFor;
      if Worker.Error <> '' then raise Exception.Create(Worker.Error);
      Ref := Worker.Plan;
      Audio := Worker.TakeAudio;
    finally
      Worker.Free;
    end;
    Cold := LoadRobotAudio(Ref, Source, 0);
    Plan := LoadRobotPlan(Ref, Cold, 0);
    Restored := BuildRobotPlan(Audio, nil);
    Renderer := TRhythmRenderer.Create;
    Renderer.ConfigureStyle(rsRobotWar, Ref, 0, 0);
    Image := TBitmap.Create; Image.PixelFormat := pf32bit;
    Sheet := TBitmap.Create; Sheet.PixelFormat := pf32bit;
    if SameText(ParamStr(1), 'Video') then RenderVideo
    else
    begin
      Need((Plan.Duration = Restored.Duration) and (Length(Plan.Cues) = Length(Restored.Cues)), 'Plan roundtrip');
      VerifyInputs;
      VerifyPlan;
      VerifyRender;
      TFile.WriteAllText(TPath.Combine(Folder, 'result.json'), Format(
        '{"checks":%d,"combatCues":%d,"stages":28,"maxCombination":3,"teams":2,"sourceEvents":%d}',
        [Checks, Length(Plan.Cues), Length(Audio.Hits)]), TEncoding.UTF8);
      WriteLn('RobotWar PASS checks=', Checks);
    end;
  except
    on E: Exception do begin WriteLn(ErrOutput, E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
  Sheet.Free; Image.Free; Renderer.Free; Restored.Free; Plan.Free; Cold.Free; Audio.Free;
end.
