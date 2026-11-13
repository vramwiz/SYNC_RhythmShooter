program TrapActionSmoke;
{$APPTYPE CONSOLE}
// 全8テーマの停止・左後退・針の回避、床支持、固定背景と任意時刻の保存復元を確認する。
uses System.SysUtils,System.Classes,System.Math,System.IOUtils,System.Hash,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmStyles,RhythmTrapPlan,
  RhythmTrapBuild,RhythmTrapCodec,RhythmTrapArt,RhythmAnimation,RhythmRenderSurface,
  RhythmImageBank,RhythmPlanRef,RhythmSettings,RhythmPrepare,RhythmFireworksScene;
const DemoSeconds=180;
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


function Hash(Bitmap:TBitmap;Rows:Integer=0):string;
var Bytes:TBytes;I:Integer;Digest:THashSHA2;
begin if Rows=0 then Rows:=Bitmap.Height;SetLength(Bytes,Bitmap.Width*Rows*4);
  for I:=0 to Rows-1 do Move(Bitmap.ScanLine[Bitmap.Height-1-I]^,Bytes[I*Bitmap.Width*4],Bitmap.Width*4);
  Digest:=THashSHA2.Create;Digest.Update(Bytes);Result:=Digest.HashAsString;
end;
procedure PNG(Bitmap:TBitmap;const Path:string);
var Image:TPNGImage;
begin Image:=TPNGImage.Create;try Image.Assign(Bitmap);Image.SaveToFile(Path);finally Image.Free;end;end;
// 同じ位置の地面を通常・落下へ変えても、作動前に見分けられないことを画素で照合する。
procedure VerifyGroundCamouflage;
const Widths:array[0..3] of Integer=(960,1280,800,720);
      Heights:array[0..3] of Integer=(540,720,800,1280);
      GroundY:array[0..2] of Double=(-0.55,0.0,0.70);
var Plan:TTrapPlan;Surface:TAnimationRenderSurface;Bitmap:TBitmap;Frame:TAnimationFrame;
  Tile,Roof:TTrapPlatform;M:TTrapMove;View,Level,Backend,Kind,Tick,I:Integer;Reference,Changed:string;
  function Picture(Time:Double):string;
  begin Frame.Time:=Time;Surface.BeginFrame(Bitmap);DrawTrapAction(Surface,Plan,Frame);Surface.EndFrame;Result:=Hash(Bitmap);end;
begin
  Plan:=TTrapPlan.Create;Surface:=nil;Bitmap:=nil;
  try
    Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0));Bitmap:=TBitmap.Create;
    Bitmap.PixelFormat:=pf32bit;Frame:=Default(TAnimationFrame);Frame.BackgroundOnly:=True;
    Plan.Duration:=10;Plan.GoalTime:=10;Plan.GoalX:=0;Plan.Theme:=tsCave;
    SetLength(Plan.Moves,1);SetLength(Plan.Platforms,3);SetLength(Plan.Ceilings,1);
    for Level:=0 to High(GroundY) do begin
      M:=Default(TTrapMove);M.Kind:=tmStop;M.Finish:=10;M.Origin:=TrapPoint(0,GroundY[Level]);M.Target:=M.Origin;
      Plan.Moves[0]:=M;
      Tile:=Default(TTrapPlatform);Tile.Move:=-1;Tile.Y:=GroundY[Level];Tile.EndY:=Tile.Y;Tile.Finish:=10;
      Tile.Left:=-8;Tile.Right:=-1;Plan.Platforms[0]:=Tile;
      Tile.Left:=-1;Tile.Right:=8;Tile.Trigger:=3;Tile.Settle:=3.5;Tile.DY:=0.18;Plan.Platforms[1]:=Tile;
      Tile.Left:=8;Tile.Right:=80;Plan.Platforms[2]:=Tile;
      Tile.Left:=-8;Tile.Y:=5.4;Tile.EndY:=Tile.Y;Plan.Ceilings[0]:=Tile;
      for View:=0 to High(Widths) do begin
        Bitmap.SetSize(Widths[View],Heights[View]);Frame.Width:=Bitmap.Width;Frame.Height:=Bitmap.Height;
        for Backend:=0 to 1 do begin
          Surface.UseD2D:=Backend=1;
          for Tick:=0 to 2 do begin
            Tile:=Plan.Platforms[1];Tile.Motion:=pmStatic;Tile.Kind:=tkMoving;Plan.Platforms[1]:=Tile;
            Reference:=Picture(Tick*1.4);
            for Kind:=0 to 1 do begin
              Tile.Motion:=pmDrop;Tile.Kind:=tkCrumble;
              if Kind=1 then Tile.Kind:=tkVanish;
              Plan.Platforms[1]:=Tile;
              Need(Picture(Tick*1.4)=Reference,'Trap floor exposes its type before activation');
              Need(Tile.BoundsAt(Tick*1.4).Bottom<Tile.Y-6,'Trap floor is only one thin row');
            end;
          end;
          Tile.Motion:=pmStatic;Tile.Kind:=tkMoving;Plan.Platforms[1]:=Tile;Reference:=Picture(3.12);
          Tile.Motion:=pmDrop;Tile.Kind:=tkCrumble;Plan.Platforms[1]:=Tile;Changed:=Picture(3.12);
          Need(Changed<>Reference,'Whole ground chunk did not visibly fall');
          Picture(0);Need(Picture(3.12)=Changed,'Collapse appearance depends on playback order');
          Tile.Motion:=pmStatic;Tile.Kind:=tkMoving;Plan.Platforms[1]:=Tile;Reference:=Picture(2.8);
          Roof:=Plan.Ceilings[0];Roof.Motion:=pmRoofDrop;Roof.Trigger:=3;Roof.Settle:=4.8;
          Roof.Release:=5.2;Roof.Recover:=6.1;Roof.DY:=3.2;Plan.Ceilings[0]:=Roof;
          Need(Picture(2.8)=Reference,'Falling roof reveals its type before activation');
          Roof.Motion:=pmStatic;Plan.Ceilings[0]:=Roof;
        end;
      end;
    end;
    I:=Length(Widths)*Length(GroundY)*2;Writeln('CAMOUFLAGE cases=',I,' normal/drop/vanish/roof, before/after/reverse seek');
  finally Bitmap.Free;Surface.Free;Plan.Free;end;
end;
procedure VerifySync(Plan:TTrapPlan;Audio:TRhythmAudio);
var M:TTrapMove;Q:TTrapObstacle;Roof:TTrapPlatform;Hit:TRhythmHit;Time,StopSeconds,WalkMin,Speed,Limit:Double;
  Contacts,Matched,Total:Integer;Found:Boolean;
begin
  Contacts:=0;StopSeconds:=0;WalkMin:=1000;Matched:=0;Total:=0;
  for M in Plan.Moves do begin
    Speed:=Abs(M.Target.X-M.Origin.X)/(M.Finish-M.Start);
    if M.Kind=tmVault then Speed:=Speed*2 else if M.Kind=tmRide then Speed:=Speed*Pi*0.5;
    Need(Speed<=TrapWalkSpeed+1E-8,'Dash exceeds walking speed');
    if M.Kind=tmStop then begin
      StopSeconds:=StopSeconds+M.Finish-M.Start;
      Limit:=0.55;if M.Avoidance in [taCrushSlot,taCrushReverse,taCrushFeint] then Limit:=0.90;
      if M.Avoidance in [taRoofShelters,taRoofNarrow,taRoofLastGap] then Limit:=5.0;
      if M.Avoidance in [taSideSpears,taAlternatingPresses,taFireChase] then Limit:=2.10;
      if M.Avoidance=taCeilingLift then Limit:=1.20;
      Need((M.Cue=M.Start) and (M.Finish-M.Start<=Limit+1E-8),'Stop timing or duration');
    end else begin
      if M.Kind=tmHeadBump then Need((M.Cue>M.Start) and (M.Cue<M.Finish),'Head impact timing')
      else Need(M.Cue=M.Finish,'Sound marker is detached from actual contact');
      if (M.Kind=tmRun) and (M.Pattern<>30) and (M.Target.X>M.Origin.X) then
        WalkMin:=Min(WalkMin,(M.Target.X-M.Origin.X)/(M.Finish-M.Start));
    end;
    if M.LandSynced then begin
      Need((M.Position(M.Finish).Y=M.Target.Y) and (M.FootLift(M.Finish,0)=0) and
        (M.FootLift(M.Finish,1)=0),'Feet are not planted on the sound');Inc(Contacts);
      if M.Kind in [tmJump,tmVault] then begin
        Limit:=0.90;if M.Pattern=30 then Limit:=1.40;
        Need((M.Finish-M.Start>=0.30) and (M.Finish-M.Start<=Limit+1E-8) and
          (M.Position(M.Finish-0.001).Y>M.Target.Y),'Jump timing');
      end;
    end;
  end;
  Need(WalkMin>=TrapWalkSpeed-1E-8,'Forward walking speed changed');
  for Hit in Audio.Hits do if (Hit.Time>=0.12) and (Hit.Time<=Plan.GoalTime) then begin
    Inc(Total);Found:=False;Time:=Hit.Time;
    for M in Plan.Moves do if (M.LandSynced and (M.Finish=Time)) or
      (M.CueSynced and (M.Cue=Time)) then begin Found:=True;Break;end;
    if not Found then for Q in Plan.Obstacles do if Q.Synced and
      ((Q.Cue=Time) or (Q.Finish=Time)) then begin Found:=True;Break;end;
    if not Found then for Roof in Plan.Ceilings do if (Roof.Motion=pmRoofDrop) and
      (Roof.Settle=Time) then begin Found:=True;Break;end;
    if Found then Inc(Matched);
  end;
  Writeln('SYNC source=',Total,' matched=',Matched,' contacts=',Contacts,
    ' walk_min=',WalkMin:0:2,' stop_seconds=',StopSeconds:0:2);
  if Total>0 then Need(Matched>=Total*0.60,'Too many sound onsets have no physical result');
end;
// 動作名ではなく実際に出た区間・跳躍・罠の数を集計し、後半の連鎖と後退の偏りを検査する。
procedure VerifyDiversity(Plan:TTrapPlan;Strict:Boolean);
var M:TTrapMove;Q:TTrapObstacle;Seen:set of TTrapAvoidance;
  Sections,Jumps,Traps:array[0..3] of Integer;
  LastSection,LastRetreat,Retreats,Total,I,Tier,Patterns:Integer;
begin
  Seen:=[];FillChar(Sections,SizeOf(Sections),0);FillChar(Jumps,SizeOf(Jumps),0);
  FillChar(Traps,SizeOf(Traps),0);LastSection:=-1;LastRetreat:=-100;Retreats:=0;Total:=0;
  for M in Plan.Moves do begin
    if (M.Pattern=18) or (M.Avoidance=taTravel) then Continue;
    Tier:=Min(3,Trunc(M.Start/Max(0.01,Plan.GoalTime)*4));Include(Seen,M.Avoidance);
    Need(TrapPatternTier(M.Avoidance)<=Tier,'A late combination appeared before its difficulty tier');
    if M.Kind in [tmJump,tmVault] then Inc(Jumps[Tier]);
    if M.Section=LastSection then Continue;
    LastSection:=M.Section;Inc(Sections[Tier]);Inc(Total);
    if TrapPatternFamily(M.Avoidance)=5 then begin
      Need(M.Section-LastRetreat>=8,'Retreat patterns repeat too closely');
      LastRetreat:=M.Section;Inc(Retreats);
    end;
  end;
  for Q in Plan.Obstacles do begin
    Tier:=Min(3,Trunc(Plan.Moves[Q.Move].Start/Max(0.01,Plan.GoalTime)*4));Inc(Traps[Tier]);
  end;
  Patterns:=0;for I:=0 to Ord(High(TTrapAvoidance)) do if TTrapAvoidance(I) in Seen then Inc(Patterns);
  Need(Retreats<=Max(1,Ceil(Total*0.13)),'Retreat avoidance dominates the course');
  Writeln('VARIETY patterns=',Patterns,' sections=',Total,' retreat_sections=',Retreats);
  for I:=0 to 3 do Writeln('TIER ',I,' sections=',Sections[I],' jumps=',Jumps[I],
    ' traps=',Traps[I],' jumps_per_section=',Jumps[I]/Max(1,Sections[I]):0:2);
  if Strict then begin
    Need(Patterns>=40,'Too few avoidance patterns in the long course');
    Need(Jumps[3]/Max(1,Sections[3])>Jumps[0]/Max(1,Sections[0])+0.50,'Late course does not intensify');
  end else if Plan.Duration>100 then Need(Patterns>=30,'Too few patterns survived the real sound timings');
end;
// リフト直前にカメラが逆走せず、足が掛かる前に横の構図が固定されることを確認する。
procedure VerifyLiftCamera(Plan:TTrapPlan);
var Lift:TTrapPlatform;View,At,First,Left,Previous,Forward,PreviousForward,StopLeft,Touch:Double;I:Integer;
begin
  Need(Plan.GoalLift(Lift),'Camera fixture has no exit lift');
  First:=Max(0.0,Plan.GoalTime-2.0);
  Touch:=Plan.GoalTime+(Lift.Left-TrapHalfWidth-Plan.GoalX)/TrapWalkSpeed;
  for View in TArray<Double>.Create(18,24,32,64) do begin
    StopLeft:=(Lift.Left+Lift.Right)*0.5-View*0.5;
    Previous:=Plan.CameraLeft(First,View);PreviousForward:=Plan.ForwardX(First);
    for I:=1 to 600 do begin
      At:=First+(Lift.Recover-First)*I/600;Left:=Plan.CameraLeft(At,View);Forward:=Plan.ForwardX(At);
      Need(Left>=Previous-1E-8,'Lift camera reverses direction');
      Need(Left-Previous<=Forward-PreviousForward+1E-8,'Lift camera accelerates beyond forward tracking');
      Previous:=Left;PreviousForward:=Forward;
    end;
    for At in TArray<Double>.Create(Touch,Lift.Trigger,Lift.Settle,Lift.Recover) do
      Need(Abs(Plan.CameraLeft(At,View)-StopLeft)<1E-8,'Horizontal camera moves while boarding or riding');
    for At in TArray<Double>.Create(Plan.GoalTime,Lift.Trigger,Lift.Settle) do
      Need(Abs(Plan.CameraLeft(At+1E-6,View)-Plan.CameraLeft(At-1E-6,View))<2E-5,
        'Lift camera jumps at a phase boundary');
  end;
end;
// 短曲でも乗り込みから花火終了まで切れず、板の上に足幅全体が残ることを調べる。
procedure VerifySurfaceFinale(Plan:TTrapPlan);
var Lift,Wall:TTrapPlatform;P,Q:TTrapPoint;Body:TTrapBox;I:Integer;At:Double;
begin
  Need(Plan.GoalLift(Lift),'Surface exit lift is missing');
  VerifyLiftCamera(Plan);
  Need((Plan.GoalTime=Plan.Moves[High(Plan.Moves)].Finish) and
    (Plan.GoalX=Plan.Moves[High(Plan.Moves)].Target.X),'Finale changed the sound-synced course endpoint');
  Need(Plan.EndTime>=Plan.SurfaceTime+GoalFireworksDuration,'Fireworks are cut short');
  P:=Plan.Position(Plan.GoalTime);Q:=Plan.Position(Lift.Trigger);
  Need((Abs(P.Y-Q.Y)<1E-8) and (Q.X>P.X) and
    (Abs((Q.X-P.X)/(Lift.Trigger-Plan.GoalTime)-TrapWalkSpeed)<1E-8),'Boarding is not a level walk');
  Q:=Plan.Position(Lift.Settle);
  Need((Q.Y-P.Y>=7.5) and (Lift.Settle-Lift.Trigger<1.0),'Exit does not rise rapidly to the surface');
  for I:=0 to 600 do begin
    At:=Plan.GoalTime+(Lift.Recover-Plan.GoalTime)*I/600;
    P:=Plan.Position(At);Body:=Plan.PlayerBounds(At);
    Need(Plan.FloorSupports(Body.Left,Body.Right,P.Y,At),'Finale leaves part of the feet unsupported');
    for Wall in Plan.Ceilings do Need(not TrapOverlap(Body,Wall.CeilingBoundsAt(At)),
      'Finale crosses a solid shaft wall or roof');
  end;
end;
procedure VerifySource(const Source:string);
var Worker:TRhythmPrepareThread;Audio,Cold:TRhythmAudio;Plan:TTrapPlan;
  Sensitivity,Density,Stage,LastStage:Integer;Rejected:Boolean;
begin
  LastStage:=1;if (ParamCount>1) and (ParamStr(2)='--stages') then LastStage:=8;
  for Sensitivity in TArray<Integer>.Create(50,100) do
    for Density in TArray<Integer>.Create(-100,20,100) do for Stage:=1 to LastStage do begin
      Worker:=TRhythmPrepareThread.Create(Source,Sensitivity,0,rsTrapAction,False,nil,1,Stage,Density);
      try
        Worker.Start;Worker.WaitFor;Need(Worker.Error='','Real source prepare: '+Worker.Error);
        Audio:=Worker.TakeAudio;
        try
          Cold:=LoadTrapAudio(Worker.Plan,Source,0);
          try
            Need(Length(Cold.PCM)=0,'Real source cold restore uses PCM');
            Plan:=LoadTrapPlan(Worker.Plan,Cold,0);
            try Need((Plan.Duration=Audio.Duration) and (Plan.GoalTime<=Plan.Duration),'Real source duration');
              VerifySync(Plan,Audio);
              VerifyDiversity(Plan,False);
              VerifySurfaceFinale(Plan);
              Need(Worker.PreviewEnd=Plan.EndTime,'Preview cuts off the surface exit');
              Writeln('REAL_SOURCE PASS sensitivity=',Sensitivity,' density=',Density,' stage=',Stage,
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
procedure VerifyBackHopDrop;
var Plan:TTrapPlan;Move:TTrapMove;Trap:TTrapObstacle;I:Integer;At,Minimum:Double;Reproduced:Boolean;
begin
  Plan:=TTrapPlan.Create;
  try
    Plan.Duration:=142;SetLength(Plan.Moves,1);
    Move:=Default(TTrapMove);Move.Kind:=tmJump;Move.Start:=141;Move.Finish:=141.30;
    Move.Origin:=TrapPoint(0,0.6);Move.Target:=TrapPoint(-1.30,0.6);Move.Arc:=0.80;
    Plan.Moves[0]:=Move;
    Trap:=Default(TTrapObstacle);Trap.Kind:=tkCeiling;Trap.X:=0;Trap.Y:=0.6;
    Trap.W:=0.46;Trap.H:=0.80;Trap.Travel:=2.6;Trap.Cue:=141.30;
    Trap.Fire:=Trap.Cue-Sqrt(Trap.Travel/24);Trap.Finish:=142;Reproduced:=False;
    for I:=0 to 3000 do begin
      At:=Move.Start+(Move.Finish-Move.Start)*I/3000;
      if Plan.Clearance(Trap,At)<0.10 then Reproduced:=True;
    end;
    Need(Reproduced,'Reported backward-hop regression did not reproduce with the old arc');
    Plan.Moves[0].Arc:=TrapBackHopArc;Minimum:=1000;
    for I:=0 to 3000 do begin
      At:=Move.Start+(Move.Finish-Move.Start)*I/3000;
      Minimum:=Min(Minimum,Plan.Clearance(Trap,At));
    end;
    Need(Minimum>=0.10,'Short backward hop intersects the falling spike');
    Writeln('BACKHOP reported 141.300s geometry PASS minimum=',Minimum:0:4);
  finally Plan.Free;end;
end;

procedure VerifyTimingRanges;
const Gaps:array[0..10] of Double=(0.12,0.16,0.21,0.27,0.32,0.40,0.50,0.64,0.72,0.95,1.20);
      BackHopGaps:array[0..2] of Double=(0.37,0.18,0.20);
var Audio:TRhythmAudio;Plan:TTrapPlan;CaseIndex,I,Count:Integer;At,Gap:Double;
begin
  Audio:=TRhythmAudio.Create;
  try
    Audio.Duration:=70.125;
    for CaseIndex:=0 to 33 do begin
      SetLength(Audio.Hits,1200);I:=0;At:=0.25;
      while At<Audio.Duration-0.4 do begin
        Audio.Hits[I].Time:=At;Audio.Hits[I].Strength:=0.30+(I mod 7)*0.09;Inc(I);
        Gap:=Gaps[CaseIndex mod Length(Gaps)];
        // 実曲141.300秒の後方ジャンプが、0.30秒の短い退避中に落下針へ触れた条件。
        if CaseIndex=33 then Gap:=BackHopGaps[(I-1) mod Length(BackHopGaps)];
        if CaseIndex div Length(Gaps)=1 then Gap:=Max(0.12,Gap+((I mod 3)-1)*0.025);
        if CaseIndex div Length(Gaps)=2 then Gap:=Gaps[(I*7+CaseIndex) mod Length(Gaps)];
        At:=At+Gap;
      end;
      SetLength(Audio.Hits,I);
      try
        Plan:=BuildTrapPlan(Audio,TTrapStage(CaseIndex mod 8),nil);
        try
          Need((Plan.Moves[0].Start=0) and (Plan.GoalTime<=Audio.Duration),'Timing fixture endpoints');
          Count:=Length(Plan.Obstacles);
          Need(Count>0,'Detected sparse sounds produced only walking');
          Writeln('TIMING PASS case=',CaseIndex,' gap=',Gaps[CaseIndex mod Length(Gaps)]:0:3,
            ' moves=',Length(Plan.Moves),' traps=',Count);
        finally Plan.Free;end;
      except on E:Exception do raise Exception.CreateFmt('Timing case=%d: %s',[CaseIndex,E.Message]);end;
    end;
  finally Audio.Free;end;
end;
var Audio,Restored:TRhythmAudio;Plan,Again,RepeatPlan:TTrapPlan;Theme:TTrapStage;Ref:TRhythmPlanRef;
  Settings,Loaded:TRhythmSettings;Surface:TAnimationRenderSurface;Bitmap,Sheet,Montage:TBitmap;Frame:TAnimationFrame;
  Folder,Source,H,BackgroundHash:string;I,J,K,Count,RightMoves,LeftMoves,Stops,Reasons,Ups,Downs,RoofSteps,Patterns,Cell,WideDrops:Integer;
  T,Minimum,First,Last,Speed,SupportY:Double;Trap,SavedTrap:TTrapObstacle;M:TTrapMove;
  Tile,OtherTile:TTrapPlatform;Supported,Rejected,Found:Boolean;
  A,B:TTrapPoint;Standing,Body,Obstacle:TTrapBox;Seen:set of TTrapKind;Moves:set of TTrapMotion;
  Variations:set of TTrapAvoidance;SavedRoof:Double;
  procedure Render(Time:Double);
  begin Frame.Time:=Time;Surface.BeginFrame(Bitmap);DrawTrapAction(Surface,Plan,Frame);Surface.EndFrame;end;
  function Original(Time:Double):Boolean;
  var Hit:TRhythmHit;
  begin for Hit in Audio.Hits do if Hit.Time=Time then Exit(True);Result:=False;end;
  procedure RenderBackdrop(Time:Double);
  begin Frame.Time:=Time;Surface.BeginFrame(Bitmap);DrawTrapBackdrop(Surface,Plan,Frame);Surface.EndFrame;end;
  function GroundAt(X,Y,Time:Double):Boolean;
  var Floor:TTrapPlatform;Bounds:TTrapBox;
  begin
    Result:=False;
    for Floor in Plan.Platforms do begin Bounds:=Floor.BoundsAt(Time);
      if Floor.Solid(Time,Plan.Duration) and (X>=Bounds.Left-1E-9) and
        (X<=Bounds.Right+1E-9) and (Abs(Floor.TopAt(X,Time)-Y)<1E-9) then Exit(True);
    end;
  end;
begin
  try
    if ParamCount>0 then begin
      if ParamStr(1)='--camouflage' then VerifyGroundCamouflage
      else if ParamStr(1)='--timing' then begin VerifyBackHopDrop;VerifyTimingRanges;end
      else VerifySource(ParamStr(1));Exit;
    end;
    VerifyBackHopDrop;
    VerifyGroundCamouflage;
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Source:=TPath.Combine(Folder,'TrapAction180.wav');WriteDemoWave(Source);Audio:=LoadRhythmAudio(Source,50);
    Need(Audio.Duration<>Trunc(Audio.Duration),'Regression needs a fractional duration');
    Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0));Bitmap:=TBitmap.Create;Sheet:=TBitmap.Create;Montage:=TBitmap.Create;
    try
      Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(960,540);Sheet.SetSize(1920,2160);Montage.SetSize(4800,6480);
      Frame:=Default(TAnimationFrame);Frame.Width:=960;Frame.Height:=540;Minimum:=1000;Seen:=[];Moves:=[];Count:=0;Variations:=[];
      for Theme:=Low(TTrapStage) to High(TTrapStage) do begin
        Plan:=BuildTrapPlan(Audio,Theme,nil);
        try
          RightMoves:=0;LeftMoves:=0;Stops:=0;Reasons:=0;Ups:=0;Downs:=0;RoofSteps:=0;
          VerifySync(Plan,Audio);
          VerifyDiversity(Plan,True);
          VerifySurfaceFinale(Plan);
          WideDrops:=0;
          for Tile in Plan.Platforms do begin
            Need(Tile.Motion<>pmFeint,'Removed sinking-and-returning floor was generated');
            if Tile.Motion=pmGrate then Need(Abs(Tile.BoundsAt(0).Top-Tile.BoundsAt(0).Bottom-0.10)<1E-8,
              'Needle-pit walking grate is not thin');
          end;
          for Tile in Plan.Platforms do if Tile.Motion=pmDrop then begin
            Need(Tile.BoundsAt(0).Bottom<Tile.Y-6,'Crumbling ground is a thin warning tile');
            if Tile.Right-Tile.Left>=2.9 then Inc(WideDrops);
            for OtherTile in Plan.Platforms do if (OtherTile.Motion=pmStatic) and (Abs(OtherTile.Y-Tile.Y)<1E-8) then
              Need((OtherTile.Right<=Tile.Left+1E-8) or (OtherTile.Left>=Tile.Right-1E-8),
                'Stationary ground covers part of the collapsing chunk');
          end;
          Need(WideDrops>0,'No whole-ground collapse was generated');
          RepeatPlan:=BuildTrapPlan(Audio,Theme,nil);
          try Need((Length(Plan.Moves)=Length(RepeatPlan.Moves)) and (Plan.GoalX=RepeatPlan.GoalX),'Deterministic build');finally RepeatPlan.Free;end;
          for M in Plan.Moves do begin
            if M.Pattern<>18 then Need(TrapPatternEnabled(M.Avoidance),'Removed floor-bobbing pattern was selected');
            Include(Moves,M.Kind);
            if M.Pattern<>18 then Include(Variations,M.Avoidance);
            Need(M.Kind in [tmRun,tmJump,tmStop,tmRide,tmHeadBump,tmVault],'Forbidden player action');
            Need(M.Landing,'Jump must start and finish on the floor');
            if M.Target.Y>M.Origin.Y then Inc(Ups);if M.Target.Y<M.Origin.Y then Inc(Downs);
            Speed:=(M.Target.X-M.Origin.X)/(M.Finish-M.Start);
            if M.Kind=tmVault then Speed:=Speed*2 else if M.Kind=tmRide then Speed:=Speed*Pi*0.5;
            Need(Abs(Speed)<=TrapWalkSpeed+1E-7,'Dash exceeds walking speed');
            if Speed>0 then Inc(RightMoves);
            if Speed<0 then begin
              Inc(LeftMoves);Need(Plan.Facing((M.Start+M.Finish)*0.5)=-1,'Retreat does not face left');
              Need((Plan.ForwardX(M.Start)=Plan.ForwardX(M.Cue)) and
                (Plan.ForwardX(M.Cue)=Plan.ForwardX(M.Finish)),'Camera follows retreat');
              Standing.Left:=M.Origin.X-TrapHalfWidth;Standing.Right:=M.Origin.X+TrapHalfWidth;
              Standing.Bottom:=M.Origin.Y+0.035;Standing.Top:=M.Origin.Y+TrapStandingHeight;
              Found:=M.Avoidance in [taHiddenStairs,taHiddenSwitchback,taCrushReverse];
              if not Found and (M.Avoidance in [taRoofShelters,taRoofNarrow,taRoofLastGap]) then
                for Tile in Plan.Ceilings do if (Tile.Motion=pmRoofDrop) and (Tile.Trigger=M.Start) and
                  TrapOverlap(Standing,Tile.CeilingBoundsAt(Tile.Settle)) then begin Found:=True;Break;end;
              if not Found then for Trap in Plan.Obstacles do if (Trap.Cue=M.Finish) and
                TrapOverlap(Standing,Trap.BoundsAt(Trap.Cue)) then begin Found:=True;Break;end;
              if Found then Inc(Reasons);
            end;
            if M.Kind=tmStop then begin
              Inc(Stops);Need((M.Origin.X=M.Target.X) and (Speed=0),'Stop keeps moving');
              Need((Plan.Position(M.Start).X=Plan.Position(M.Cue).X) and
                (Plan.Position(M.Cue).X=Plan.Position(M.Finish).X),'Stop trajectory drifts');
            end;
            for J:=0 to Ceil((M.Finish-M.Start)*200) do begin
              T:=Min(M.Finish,M.Start+J/200);A:=M.Position(T);
              Body:=Plan.PlayerBounds(T);
              for Tile in Plan.Platforms do if Tile.Solid(T,Plan.Duration) then begin
                Obstacle:=Tile.BoundsAt(T);
                if Tile.Motion=pmHinge then Need(not Tile.Intersects(Body,T),'Player crossed the rotating floor')
                else Need((Body.Right<=Obstacle.Left+1E-7) or (Body.Left>=Obstacle.Right-1E-7) or
                  (Body.Bottom>=Obstacle.Top-1E-7) or (Body.Top<=Obstacle.Bottom+1E-7),'Player crossed a solid platform');
              end;
              for Tile in Plan.Ceilings do if (Body.Right>Tile.Left+1E-8) and (Body.Left<Tile.Right-1E-8) then
                Need(Body.Top<=Tile.CeilingBoundsAt(T).Bottom-0.119,'Player crossed a solid ceiling/step');
              Need(M.HeightAt(T)=TrapStandingHeight,'Player crouched');
              if (M.Kind in [tmRun,tmStop,tmRide]) or (T=M.Start) or (T=M.Finish) then
                Need(GroundAt(A.X-TrapHalfWidth,A.Y,T) and GroundAt(A.X,A.Y,T) and
                  GroundAt(A.X+TrapHalfWidth,A.Y,T),'Unsupported walking/takeoff/landing');
            end;
            if M.Landing then begin
              Supported:=GroundAt(M.Target.X,M.Target.Y,M.Finish);
              Need(Supported,'Landing without supporting platform');
            end;if M.CueSynced then Need(Original(M.Cue),'Cue shifted from onset');
            if M.LandSynced then Need(Original(M.Finish),'Landing shifted from onset');
            for T in TArray<Double>.Create(M.Start,M.Cue,M.Finish) do begin
              A:=Plan.Position(T-1E-7);B:=Plan.Position(T+1E-7);
              Need(Hypot(A.X-B.X,A.Y-B.Y)<0.001,'Position discontinuity');end;
          end;
          Need((RightMoves>0) and (LeftMoves>0) and (Stops>0),'Missing bidirectional walking or stops');
          Need(Reasons=LeftMoves,'Retreat has no spike to avoid');
          for I:=1 to High(Plan.Ceilings) do if Plan.Ceilings[I].Y<>Plan.Ceilings[I-1].Y then Inc(RoofSteps);
          Need((Ups>0) and (Downs>0) and (RoofSteps>0),'Missing floor or ceiling steps');
          for M in Plan.Moves do if (M.Kind=tmRun) and (M.Finish-M.Start>=0.4) then begin
            Need(M.StepPhase(M.Finish)>=4*Pi,'Foot cadence is too slow');Break;
          end;
          for Trap in Plan.Obstacles do begin
            Include(Seen,Trap.Kind);if Trap.Synced then Need(Original(Trap.Cue),'Trap shifted from onset');
            if TrapHarmless(Trap.Kind) then Continue;
            if Trap.Kind<tkSideSpear then begin
            SupportY:=Trap.Y;if TrapFloorSpikes(Trap.Kind) then SupportY:=SupportY-TrapSpikePitDepth;
            Need((Trap.Kind in [tkSpikes,tkHiddenSpikes,tkCeiling,tkRock,tkBlade,tkWall]) and
              (((Trap.Kind=tkWall) and (Trap.W<=1.5) and (Trap.H<=3)) or
               ((Trap.W<=0.9) and (Trap.H<=TrapStandingHeight))),'Unexpected danger geometry');
            for J:=0 to 100 do begin
              T:=Plan.Duration*J/100;
              Obstacle:=Trap.BoundsAt(T);
              if TrapFloorSpikes(Trap.Kind) then begin
                Need(Abs(Obstacle.Bottom-SupportY)<1E-8,'Lowered needle has no pit-bottom support');
                Need(Obstacle.Top-Obstacle.Bottom>=1.0-1E-8,'Only the needle tip is visible');
                if Trap.Kind<>tkHiddenSpikes then Need(Abs(Obstacle.Top-(Trap.Y-TrapSpikeTipDrop))<1E-8,'Fixed needle tip meets the walking floor')
                else if (T<=Trap.Fire) or (T>=Trap.Finish) then
                  Need(Abs(Obstacle.Top-(Trap.Y-TrapSpikeTipDrop))<1E-8,'Retracted needle tip meets the floor');
              end else Need(Obstacle.Bottom>=Trap.Y,'Spike passed through the floor');
              if (T<=Trap.Finish) or (Trap.Kind<>tkBlade) then
                Need(GroundAt(Obstacle.Left,SupportY,T) and GroundAt(Obstacle.Right,SupportY,T),'Hazard has no supporting floor');
            end;
            if Trap.Kind=tkHiddenSpikes then
              Need(Abs(Trap.BoundsAt(Trap.Cue).Top-(Trap.Y+Trap.H-TrapSpikeLowering))<1E-8,'Active needle reach changed');
            if Trap.Kind in [tkCeiling,tkRock] then begin
              Obstacle:=Trap.BoundsAt(Trap.Fire);
              Need(Plan.CeilingSupports(Obstacle.Left,Obstacle.Right,Obstacle.Top-Trap.H*Trap.Embed),'Falling trap did not start inside its ceiling');
              Need(Trap.Reveal=0,'Ceiling trap suddenly appears instead of being visible beforehand');
              if Trap.Cue>Plan.Duration*0.75 then Need(Trap.Embed>=0.5,'Late ceiling trap is not concealed');
              Need((Trap.BoundsAt(Trap.Cue).Bottom=Trap.Y) and (Trap.BoundsAt(Trap.Finish).Bottom=Trap.Y),'Falling spike does not stop on the floor');
              Need(Abs(Trap.Travel-24*Sqr(Trap.Cue-Trap.Fire))<1E-8,'Falling spike is not accelerated by gravity');
            end;
            end;
            // 全寿命を独立に照合し、停止・後退中や、後で戻って来る区間も省かない。
            First:=Trap.Fire;Last:=Trap.Finish;
            if Trap.Kind in [tkWall,tkBlade,tkPress,tkClosingDoor,tkCeilingNeedles,tkSpearMount] then begin First:=0;Last:=Plan.Duration;end;
            for J:=0 to Ceil((Last-First)*1000) do begin
              T:=Min(Last,First+J/1000);Minimum:=Min(Minimum,Plan.Clearance(Trap,T));
              Need(not Trap.Dangerous(T) or not TrapOverlap(Plan.PlayerBounds(T),Trap.BoundsAt(T)),'Actual collision');Inc(Count);end;
          end;
          Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsTrapAction,Ord(Theme)+1);Ref.SourceRevision:=Audio.SourceRevision;
          SaveTrapPlan(Plan,Audio,Ref);Restored:=LoadTrapAudio(Ref,Source,0);
          try Again:=LoadTrapPlan(Ref,Restored,0);
            try Need(Length(Again.Ceilings)=Length(Plan.Ceilings),'Ceilings were not saved');
              for I:=0 to High(Plan.Ceilings) do Need((Again.Ceilings[I].Y=Plan.Ceilings[I].Y) and
                (Again.Ceilings[I].Left=Plan.Ceilings[I].Left),'Saved ceiling changed');
              Need((Again.EndTime=Plan.EndTime) and (Again.SurfaceTime=Plan.SurfaceTime),'Saved finale timing differs');
              VerifySurfaceFinale(Again);
              for I:=0 to 200 do begin T:=I*Plan.EndTime/200;A:=Plan.Position(T);B:=Again.Position(T);
              Need((A.X=B.X) and (A.Y=B.Y) and (Plan.ForwardX(T)=Again.ForwardX(T)) and
                (Plan.CameraLeft(T,18)=Again.CameraLeft(T,18)) and
                (Plan.CameraLeft(T,32)=Again.CameraLeft(T,32)) and
                (Plan.Facing(T)=Again.Facing(T)),'Saved trajectory/camera/facing differs');end;
            finally Again.Free;end;
          finally Restored.Free;end;
          Settings:=TRhythmSettings.Defaults;Settings.Style:=rsTrapAction;Settings.TrapStage:=Theme;Settings.Music:=Source;Settings.Plan:=Ref;
          Need(TRhythmSettings.TryJSON(Settings.ToJSON,Loaded) and (Loaded.TrapStage=Theme) and (Loaded.Plan.Key=Ref.Key),'Theme settings round trip');
          RenderBackdrop(0);BackgroundHash:=Hash(Bitmap);
          for T in TArray<Double>.Create(0.25,3,12.75,84.5,137.125,Plan.GoalTime-0.001) do begin
            RenderBackdrop(T);Need(Hash(Bitmap)=BackgroundHash,'Background moves or zooms');
          end;
          Render(137.125);H:=Hash(Bitmap);Render(3);Render(137.125);Need(Hash(Bitmap)=H,'Reverse seek changes pixels');
          Render(Plan.SurfaceTime+0.35);H:=Hash(Bitmap);Render(3);Render(Plan.SurfaceTime+0.35);
          Need(Hash(Bitmap)=H,'Surface/fireworks reverse seek changes pixels');
          Render(84.5);Sheet.Canvas.Draw((Ord(Theme) mod 2)*960,(Ord(Theme) div 2)*540,Bitmap);
          if Theme=tsCave then begin
            Cell:=0;
            for I:=0 to Ord(High(TTrapAvoidance)) do begin
              if not TrapPatternEnabled(TTrapAvoidance(I)) then Continue;
              T:=0;Found:=False;
              for Trap in Plan.Obstacles do if (Trap.Kind=tkCeiling) and
                (Ord(Plan.Moves[Trap.Move].Avoidance)=I) then begin
                T:=Trap.Fire+(Trap.Cue-Trap.Fire)*0.75;Found:=True;Break;
              end;
              if not Found then for M in Plan.Moves do if (Ord(M.Avoidance)=I) and (M.Pattern<>18) then begin
                if M.Kind in [tmJump,tmVault] then T:=M.Start+(M.Finish-M.Start)*0.70
                else if (M.Kind=tmStop) and M.LandSynced then T:=M.Finish-0.03 else T:=M.Cue;
                Found:=True;Break;
              end;
              if not Found then begin Inc(Cell);Continue;end;
              Render(T);Montage.Canvas.Draw((Cell mod 5)*960,(Cell div 5)*540,Bitmap);
              Montage.Canvas.Font.Name:='Segoe UI';Montage.Canvas.Font.Size:=16;Montage.Canvas.Font.Color:=clWhite;
              Montage.Canvas.Brush.Style:=bsClear;
              Montage.Canvas.TextOut((Cell mod 5)*960+12,(Cell div 5)*540+12,
                IntToStr(Cell+1)+' '+TrapPatternTitle(TTrapAvoidance(I)));Inc(Cell);
            end;
            PNG(Montage,TPath.Combine(Folder,'TrapActionTraps.png'));
            PNG(Montage,TPath.Combine(Folder,'TrapActionGimmicks57.png'));
            for I:=0 to 4 do begin Render(Plan.Duration*I/4);PNG(Bitmap,TPath.Combine(Folder,Format('cave-%d.png',[I])));end;
          end;
          Writeln(TrapStageIds[Theme],': ',Length(Plan.Moves),' motions, ',Length(Plan.Obstacles),
            ' traps, right=',RightMoves,' left=',LeftMoves,' stops=',Stops,
            ' up=',Ups,' down=',Downs,' roofSteps=',RoofSteps);
          // 保存データの改変で、禁止動作や敵を復活させない。
          M:=Plan.Moves[0];Plan.Moves[0].Kind:=tmSlide;Rejected:=False;
          try ValidateTrapPlan(Plan,nil);except on E:EConvertError do Rejected:=True;end;
          Plan.Moves[0]:=M;Need(Rejected,'Saved crouch accepted');
          SavedRoof:=Plan.Ceilings[0].Y;Plan.Ceilings[0].Y:=-1;Plan.Ceilings[0].EndY:=-1;Rejected:=False;
          try ValidateTrapPlan(Plan,nil);except on E:EConvertError do Rejected:=True;end;
          Plan.Ceilings[0].Y:=SavedRoof;Plan.Ceilings[0].EndY:=SavedRoof;Need(Rejected,'Head collision accepted');
          SavedTrap:=Plan.Obstacles[0];Plan.Obstacles[0].Kind:=tkHunter;Rejected:=False;
          try ValidateTrapPlan(Plan,nil);except on E:EConvertError do Rejected:=True;end;
          Plan.Obstacles[0]:=SavedTrap;Need(Rejected,'Stationary enemy accepted');
          // 左向きの区間だけで発動する針も拒否する。右進行の矩形判定では見落とす入力。
          for M in Plan.Moves do if (M.Kind=tmRun) and (M.Target.X<M.Origin.X) then begin
            Trap:=Default(TTrapObstacle);Trap.Kind:=tkHiddenSpikes;Trap.Move:=0;
            Trap.Fire:=M.Start+0.01;Trap.Cue:=(M.Start+M.Finish)*0.5;Trap.Finish:=M.Finish-0.01;
            Trap.X:=M.Position(Trap.Cue).X;Trap.Y:=M.Origin.Y;Trap.W:=0.62;Trap.H:=0.5;
            Need(Plan.Clearance(Trap,Trap.Cue)<0,'Leftward collision fixture does not actually hit the player');
            Plan.Obstacles[0]:=Trap;Rejected:=False;
            try ValidateTrapPlan(Plan,nil);except on E:EConvertError do Rejected:=True;end;
            Plan.Obstacles[0]:=SavedTrap;Need(Rejected,'Collision during leftward retreat accepted');Break;
          end;
        finally Plan.Free;end;
      end;
      PNG(Sheet,TPath.Combine(Folder,'TrapActionThemes.png'));
      I:=0;for K:=0 to Ord(High(TTrapKind)) do if TTrapKind(K) in Seen then Inc(I);
      Need(Seen=[tkSpikes,tkHiddenSpikes,tkCeiling,tkRock,tkBlade,tkWall,tkPit,tkCrumble,tkVanish,
        tkSideSpear,tkPress,tkCeilingNeedles,tkClosingDoor,tkFireJet,tkSpearMount],'Trap coverage');
      Patterns:=0;for K:=0 to Ord(High(TTrapAvoidance)) do if (TTrapAvoidance(K)<>taTravel) and
        (TTrapAvoidance(K) in Variations) then Inc(Patterns);
      Need(Patterns=TrapPatternCount,'Missing avoidance patterns');
      Need(Moves=[tmRun,tmJump,tmStop,tmRide,tmHeadBump,tmVault],'Missing walking, jump, ride, vault or head impact');
      Writeln('PASS ',Count,' subframe collision checks; ',I,' trap kinds; ',Patterns,' avoidance patterns; minimum clearance ',Minimum:0:4);
      Audio.Hits:=nil;Audio.Envelope:=nil;Audio.SoundEnd:=0;
      for T in TArray<Double>.Create(0.05,1,8,180) do begin
        Audio.Duration:=T;Plan:=BuildTrapPlan(Audio,tsCave,nil);
        try Need(Length(Plan.Obstacles)=0,'Silence generated unrelated hazards');
          VerifySurfaceFinale(Plan);
          for M in Plan.Moves do Need(M.Kind=tmRun,'Silence generated unnecessary jumps');
          Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsTrapAction,1);Ref.SourceRevision:=Audio.SourceRevision;
          SaveTrapPlan(Plan,Audio,Ref);Restored:=LoadTrapAudio(Ref,Source,0);
          try Again:=LoadTrapPlan(Ref,Restored,0);Again.Free;finally Restored.Free;end;
        finally Plan.Free;end;
      end;
    finally Audio.Free;Surface.Free;Bitmap.Free;Sheet.Free;Montage.Free;end;
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);Halt(1);end;end;
end.
