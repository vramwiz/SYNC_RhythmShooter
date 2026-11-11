program TrapActionSmoke;
{$APPTYPE CONSOLE}
// 3分の実WAV解析、全8テーマの衝突距離、着地支持、保存復元と逆シークを確認する。
uses System.SysUtils,System.Classes,System.Math,System.IOUtils,System.Hash,
  Vcl.Graphics,Vcl.Forms,Vcl.StdCtrls,Vcl.Imaging.pngimage,SYNC_RhythmShooter_SettingsForm,RhythmAudio,RhythmStyles,RhythmTrapPlan,
  RhythmTrapBuild,RhythmTrapCodec,RhythmTrapArt,RhythmAnimation,RhythmRenderSurface,
  RhythmImageBank,RhythmPlanRef,RhythmSettings,RhythmPrepare;
const DemoSeconds=180;
  Shots:array[0..7] of TTrapKind=(tkHiddenSpikes,tkCeiling,tkBoulder,tkLaser,tkWall,tkBackground,tkDoor,tkCollapse);
procedure Need(B:Boolean;const Why:string);
begin if not B then raise Exception.Create(Why);end;
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
  // 整数秒だけでは、JSON音声情報とbinary64計画の丸め差を検出できない。
  SetLength(Samples, DemoSeconds * RHYTHM_RATE + 1523);
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


function Hash(Bitmap:TBitmap):string;
var Bytes:TBytes;I:Integer;Digest:THashSHA2;
begin SetLength(Bytes,Bitmap.Width*Bitmap.Height*4);
  for I:=0 to Bitmap.Height-1 do Move(Bitmap.ScanLine[I]^,Bytes[I*Bitmap.Width*4],Bitmap.Width*4);
  Digest:=THashSHA2.Create;Digest.Update(Bytes);Result:=Digest.HashAsString;
end;
procedure PNG(Bitmap:TBitmap;const Path:string);
var Image:TPNGImage;
begin Image:=TPNGImage.Create;try Image.Assign(Bitmap);Image.SaveToFile(Path);finally Image.Free;end;end;
procedure VerifySource(const Source:string);
var Worker:TRhythmPrepareThread;Audio,Cold:TRhythmAudio;Plan:TTrapPlan;
  Sensitivity,Density:Integer;Rejected:Boolean;
begin
  for Sensitivity in TArray<Integer>.Create(50,100) do
    for Density in TArray<Integer>.Create(-100,20,100) do begin
      Worker:=TRhythmPrepareThread.Create(Source,Sensitivity,0,rsTrapAction,False,nil,1,1,Density);
      try
        Worker.Start;Worker.WaitFor;Need(Worker.Error='','Real source prepare: '+Worker.Error);
        Audio:=Worker.TakeAudio;
        try
          Cold:=LoadTrapAudio(Worker.Plan,Source,0);
          try
            Need(Length(Cold.PCM)=0,'Real source cold restore uses PCM');
            Plan:=LoadTrapPlan(Worker.Plan,Cold,0);
            try Need((Plan.Duration=Audio.Duration) and (Plan.GoalTime<=Plan.Duration),'Real source duration');
              Writeln('REAL_SOURCE PASS sensitivity=',Sensitivity,' density=',Density,
                ' moves=',Length(Plan.Moves),' traps=',Length(Plan.Obstacles));
            finally Plan.Free;end;
            if (Sensitivity=50) and (Density=-100) then begin
              // 丸め差の許容によって、実際に異なる曲長まで受け入れないことを確認する。
              Cold.Duration:=Audio.Duration+0.01;Rejected:=False;
              try Plan:=LoadTrapPlan(Worker.Plan,Cold,0);Plan.Free;
              except on E:EConvertError do Rejected:=True;end;
              Need(Rejected,'Mismatching duration was accepted');
            end;
          finally Cold.Free;end;
        finally Audio.Free;end;
      finally Worker.Free;end;
    end;
end;
var Audio,Restored:TRhythmAudio;Plan,Again,RepeatPlan:TTrapPlan;Theme:TTrapStage;Ref:TRhythmPlanRef;
  Settings,Loaded:TRhythmSettings;Surface:TAnimationRenderSurface;Bitmap,Sheet,Montage:TBitmap;Frame:TAnimationFrame;
  Folder,Source,H:string;I,J,K,Count:Integer;T,Minimum:Double;Trap:TTrapObstacle;M:TTrapMove;
  Form:TFormRhythmShooterSettings;Combo:TComboBox;Tile:TTrapPlatform;Supported:Boolean;
  A,B:TTrapPoint;Seen:set of TTrapKind;Moves:set of TTrapMotion;
  procedure Render(Time:Double);
  begin Frame.Time:=Time;Surface.BeginFrame(Bitmap);DrawTrapAction(Surface,Plan,Frame);Surface.EndFrame;end;
  function Original(Time:Double):Boolean;
  var Hit:TRhythmHit;
  begin for Hit in Audio.Hits do if Hit.Time=Time then Exit(True);Result:=False;end;
begin
  try
    if ParamCount>0 then begin VerifySource(ParamStr(1));Exit;end;
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Source:=TPath.Combine(Folder,'TrapAction180.wav');WriteDemoWave(Source);Audio:=LoadRhythmAudio(Source,50);
    Need(Audio.Duration<>Trunc(Audio.Duration),'Regression needs a fractional duration');
    Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0));Bitmap:=TBitmap.Create;Sheet:=TBitmap.Create;Montage:=TBitmap.Create;
    try
      Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(960,540);Sheet.SetSize(1920,2160);Montage.SetSize(1920,2160);
      Frame:=Default(TAnimationFrame);Frame.Width:=960;Frame.Height:=540;Minimum:=1000;Seen:=[];Moves:=[];Count:=0;
      for Theme:=Low(TTrapStage) to High(TTrapStage) do begin
        Plan:=BuildTrapPlan(Audio,Theme,nil);
        try
          RepeatPlan:=BuildTrapPlan(Audio,Theme,nil);
          try Need((Length(Plan.Moves)=Length(RepeatPlan.Moves)) and (Plan.GoalX=RepeatPlan.GoalX),'Deterministic build');finally RepeatPlan.Free;end;
          for M in Plan.Moves do begin
            Include(Moves,M.Kind);
            if M.Landing then begin
              Supported:=False;
              for Tile in Plan.Platforms do if (Tile.Move<0) and (M.Target.X>=Tile.Left) and (M.Target.X<=Tile.Right) and
                (Abs(Tile.TopAt(M.Target.X)-M.Target.Y)<1E-7) and (M.Finish<=Tile.Finish) then Supported:=True;
              Need(Supported,'Landing without supporting platform');
            end;if M.CueSynced then Need(Original(M.Cue),'Cue shifted from onset');
            if M.LandSynced then Need(Original(M.Finish),'Landing shifted from onset');
            for T in TArray<Double>.Create(M.Start,M.Cue,M.Finish) do begin
              A:=Plan.Position(T-1E-7);B:=Plan.Position(T+1E-7);
              Need(Hypot(A.X-B.X,A.Y-B.Y)<0.001,'Position discontinuity');end;
          end;
          for Trap in Plan.Obstacles do begin
            Include(Seen,Trap.Kind);if Trap.Synced then Need(Original(Trap.Cue),'Trap shifted from onset');
            if TrapHarmless(Trap.Kind) then Continue;
            for J:=0 to Ceil((Trap.Finish-Trap.Fire)*1000) do begin
              T:=Min(Trap.Finish,Trap.Fire+J/1000);Minimum:=Min(Minimum,Plan.Clearance(Trap,T));
              Need(not TrapOverlap(Plan.PlayerBounds(T),Trap.BoundsAt(T)),'Actual collision');Inc(Count);end;
          end;
          Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsTrapAction,Ord(Theme)+1);Ref.SourceRevision:=Audio.SourceRevision;
          SaveTrapPlan(Plan,Audio,Ref);Restored:=LoadTrapAudio(Ref,Source,0);
          try Again:=LoadTrapPlan(Ref,Restored,0);
            try for I:=0 to 200 do begin T:=I*Plan.Duration/200;A:=Plan.Position(T);B:=Again.Position(T);
              Need((A.X=B.X) and (A.Y=B.Y),'Saved trajectory differs');end;
            finally Again.Free;end;
          finally Restored.Free;end;
          Settings:=TRhythmSettings.Defaults;Settings.Style:=rsTrapAction;Settings.TrapStage:=Theme;Settings.Music:=Source;Settings.Plan:=Ref;
          Need(TRhythmSettings.TryJSON(Settings.ToJSON,Loaded) and (Loaded.TrapStage=Theme) and (Loaded.Plan.Key=Ref.Key),'Theme settings round trip');
          Render(137.125);H:=Hash(Bitmap);Render(3);Render(137.125);Need(Hash(Bitmap)=H,'Reverse seek changes pixels');
          Render(84.5);Sheet.Canvas.Draw((Ord(Theme) mod 2)*960,(Ord(Theme) div 2)*540,Bitmap);
          if Theme=tsCave then begin
            for I:=0 to High(Shots) do for J:=High(Plan.Obstacles) downto 0 do if Plan.Obstacles[J].Kind=Shots[I] then begin
              Render(Plan.Obstacles[J].Cue);Montage.Canvas.Draw((I mod 2)*960,(I div 2)*540,Bitmap);Break;
            end;
            PNG(Montage,TPath.Combine(Folder,'TrapActionTraps.png'));
            for I:=0 to 4 do begin Render(Plan.Duration*I/4);PNG(Bitmap,TPath.Combine(Folder,Format('cave-%d.png',[I])));end;
          end;
          Writeln(TrapStageIds[Theme],': ',Length(Plan.Moves),' motions, ',Length(Plan.Obstacles),' traps');
        finally Plan.Free;end;
      end;
      PNG(Sheet,TPath.Combine(Folder,'TrapActionThemes.png'));
      I:=0;for K:=0 to Ord(High(TTrapKind)) do if TTrapKind(K) in Seen then Inc(I);Need(I>=20,'Too few trap types');
      Writeln('PASS ',Count,' subframe collision checks; ',I,' trap kinds; minimum clearance ',Minimum:0:4);
      Application.Initialize;Application.ShowMainForm:=False;
      Form:=TFormRhythmShooterSettings.Create(nil);
      try
        Settings:=TRhythmSettings.Defaults;Settings.Style:=rsTrapAction;Settings.TrapStage:=tsIceCave;
        Form.ConfigureState(Settings);Form.Show;Application.ProcessMessages;
        Combo:=TComboBox(Form.FindComponent('TrapStage'));
        Need((Combo<>nil) and Combo.Parent.Visible and (Combo.Items.Count=8) and (Combo.ItemIndex=6),'Stage selector');
        Combo.ItemIndex:=5;Combo.OnChange(Combo);Need(Form.Snapshot.TrapStage=tsVolcano,'Stage selection not applied');
        with Form.GetFormImage do try SaveToFile(TPath.Combine(Folder,'TrapActionSettings.bmp'));finally Free;end;
      finally Form.Free;end;
      Audio.Hits:=nil;
      for T in TArray<Double>.Create(0.05,1,8,180) do begin Audio.Duration:=T;Plan:=BuildTrapPlan(Audio,tsCave,nil);Plan.Free;end;
    finally Audio.Free;Surface.Free;Bitmap.Free;Sheet.Free;Montage.Free;end;
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);Halt(1);end;end;
end.
