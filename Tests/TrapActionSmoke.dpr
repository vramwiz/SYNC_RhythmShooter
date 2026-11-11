program TrapActionSmoke;
{$APPTYPE CONSOLE}
// 全8テーマの停止・左後退・針の回避、床支持、固定背景と任意時刻の保存復元を確認する。
uses System.SysUtils,System.Classes,System.Math,System.IOUtils,System.Hash,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmStyles,RhythmTrapPlan,
  RhythmTrapBuild,RhythmTrapCodec,RhythmTrapArt,RhythmAnimation,RhythmRenderSurface,
  RhythmImageBank,RhythmPlanRef,RhythmSettings,RhythmPrepare;
const DemoSeconds=180;
  AvoidTitles:array[0..15] of string=('後退して跳ぶ','引き込みを待つ','落下を止まって越す','落下を誘い後退',
    '連続落下を駆け抜ける','落下の間で待つ','低い天井で小ジャンプ','長い針列を越す',
    '段差を上る','段差を下る','高い足場へ穴越え','低い足場へ穴越え',
    '崩れる床から上る','消える床から下る','後ろへ跳んで誘う','小ジャンプを三連続');
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
procedure VerifySync(Plan:TTrapPlan;Audio:TRhythmAudio);
var M:TTrapMove;Q:TTrapObstacle;Hit:TRhythmHit;Time,StopSeconds,WalkMin:Double;
  Contacts,Matched,Total:Integer;Found:Boolean;
begin
  Contacts:=0;StopSeconds:=0;WalkMin:=1000;Matched:=0;Total:=0;
  for M in Plan.Moves do begin
    if M.Kind=tmStop then begin
      StopSeconds:=StopSeconds+M.Finish-M.Start;
      Need((M.Cue=M.Start) and (M.Finish-M.Start<=0.55+1E-8),'Stop timing or duration');
    end else begin
      Need(M.Cue=M.Finish,'Sound marker is detached from actual contact');
      if M.Kind=tmRun then WalkMin:=Min(WalkMin,Abs(M.Target.X-M.Origin.X)/(M.Finish-M.Start));
    end;
    if M.LandSynced then begin
      Need((M.Position(M.Finish).Y=M.Target.Y) and (M.FootLift(M.Finish,0)=0) and
        (M.FootLift(M.Finish,1)=0),'Feet are not planted on the sound');Inc(Contacts);
      if M.Kind=tmJump then Need((M.Finish-M.Start>=0.30) and
        (M.Finish-M.Start<=0.65+1E-8) and (M.Position(M.Finish-0.001).Y>M.Target.Y),'Jump timing');
    end;
  end;
  Need(WalkMin>=5.4,'Walking or retreat is too slow');
  for Hit in Audio.Hits do if (Hit.Time>=0.12) and (Hit.Time<=Plan.GoalTime) then begin
    Inc(Total);Found:=False;Time:=Hit.Time;
    for M in Plan.Moves do if (M.LandSynced and (M.Finish=Time)) or
      (M.CueSynced and (M.Cue=Time)) then begin Found:=True;Break;end;
    if not Found then for Q in Plan.Obstacles do if Q.Synced and
      ((Q.Cue=Time) or (Q.Finish=Time)) then begin Found:=True;Break;end;
    if Found then Inc(Matched);
  end;
  Writeln('SYNC source=',Total,' matched=',Matched,' contacts=',Contacts,
    ' walk_min=',WalkMin:0:2,' stop_seconds=',StopSeconds:0:2);
  if Total>0 then Need(Matched>=Total*0.60,'Too many sound onsets have no physical result');
end;
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
              VerifySync(Plan,Audio);
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
  Folder,Source,H,BackgroundHash:string;I,J,K,Count,RightMoves,LeftMoves,Stops,Reasons,Ups,Downs,RoofSteps,Patterns:Integer;
  T,Minimum,First,Last,Speed:Double;Trap,SavedTrap:TTrapObstacle;M:TTrapMove;
  Tile:TTrapPlatform;Supported,Rejected,Found:Boolean;
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
  var Floor:TTrapPlatform;
  begin
    Result:=False;
    for Floor in Plan.Platforms do if (Floor.Move=-1) and (X>=Floor.Left-1E-9) and
      (X<=Floor.Right+1E-9) and (Abs(Floor.TopAt(X)-Y)<1E-9) and (Time>=Floor.Start) and
      ((Time<Floor.Finish) or (Floor.Finish=Plan.Duration)) then Exit(True);
  end;
begin
  try
    if ParamCount>0 then begin VerifySource(ParamStr(1));Exit;end;
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Source:=TPath.Combine(Folder,'TrapAction180.wav');WriteDemoWave(Source);Audio:=LoadRhythmAudio(Source,50);
    Need(Audio.Duration<>Trunc(Audio.Duration),'Regression needs a fractional duration');
    Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create(0));Bitmap:=TBitmap.Create;Sheet:=TBitmap.Create;Montage:=TBitmap.Create;
    try
      Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(960,540);Sheet.SetSize(1920,2160);Montage.SetSize(3840,2160);
      Frame:=Default(TAnimationFrame);Frame.Width:=960;Frame.Height:=540;Minimum:=1000;Seen:=[];Moves:=[];Count:=0;Variations:=[];
      for Theme:=Low(TTrapStage) to High(TTrapStage) do begin
        Plan:=BuildTrapPlan(Audio,Theme,nil);
        try
          RightMoves:=0;LeftMoves:=0;Stops:=0;Reasons:=0;Ups:=0;Downs:=0;RoofSteps:=0;
          VerifySync(Plan,Audio);
          RepeatPlan:=BuildTrapPlan(Audio,Theme,nil);
          try Need((Length(Plan.Moves)=Length(RepeatPlan.Moves)) and (Plan.GoalX=RepeatPlan.GoalX),'Deterministic build');finally RepeatPlan.Free;end;
          for M in Plan.Moves do begin
            Include(Moves,M.Kind);
            if M.Pattern<>18 then Include(Variations,M.Avoidance);
            Need(M.Kind in [tmRun,tmJump,tmStop],'Forbidden player action');
            Need(M.Landing,'Jump must start and finish on the floor');
            if M.Target.Y>M.Origin.Y then Inc(Ups);if M.Target.Y<M.Origin.Y then Inc(Downs);
            Speed:=(M.Target.X-M.Origin.X)/(M.Finish-M.Start);
            Need(Abs(Speed)<18,'Unnatural horizontal speed');
            if Speed>0 then Inc(RightMoves);
            if Speed<0 then begin
              Inc(LeftMoves);Need(Plan.Facing((M.Start+M.Finish)*0.5)=-1,'Retreat does not face left');
              Need((Plan.ForwardX(M.Start)=Plan.ForwardX(M.Cue)) and
                (Plan.ForwardX(M.Cue)=Plan.ForwardX(M.Finish)),'Camera follows retreat');
              Standing.Left:=M.Origin.X-TrapHalfWidth;Standing.Right:=M.Origin.X+TrapHalfWidth;
              Standing.Bottom:=M.Origin.Y+0.035;Standing.Top:=M.Origin.Y+TrapStandingHeight;
              for Trap in Plan.Obstacles do if (Trap.Cue=M.Finish) and
                TrapOverlap(Standing,Trap.BoundsAt(Trap.Cue)) then begin Inc(Reasons);Break;end;
            end;
            if M.Kind=tmStop then begin
              Inc(Stops);Need((M.Origin.X=M.Target.X) and (Speed=0),'Stop keeps moving');
              Need((Plan.Position(M.Start).X=Plan.Position(M.Cue).X) and
                (Plan.Position(M.Cue).X=Plan.Position(M.Finish).X),'Stop trajectory drifts');
            end;
            for J:=0 to Ceil((M.Finish-M.Start)*200) do begin
              T:=Min(M.Finish,M.Start+J/200);A:=M.Position(T);
              Body:=Plan.PlayerBounds(T);
              for Tile in Plan.Platforms do if (Body.Right>Tile.Left+1E-8) and (Body.Left<Tile.Right-1E-8) and
                ((T<Tile.Finish) or (Tile.Finish=Plan.Duration)) then Need(Body.Bottom>=Tile.Y-1E-7,'Player crossed a solid floor/step');
              for Tile in Plan.Ceilings do if (Body.Right>Tile.Left+1E-8) and (Body.Left<Tile.Right-1E-8) then
                Need(Body.Top<=Tile.Y-0.119,'Player crossed a solid ceiling/step');
              Need(M.HeightAt(T)=TrapStandingHeight,'Player crouched');
              if (M.Kind in [tmRun,tmStop]) or (T=M.Start) or (T=M.Finish) then
                Need(GroundAt(A.X-TrapHalfWidth,A.Y,T) and GroundAt(A.X,A.Y,T) and
                  GroundAt(A.X+TrapHalfWidth,A.Y,T),'Unsupported walking/takeoff/landing');
            end;
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
            Need((Trap.Kind in [tkSpikes,tkHiddenSpikes,tkCeiling]) and (Trap.W<=0.8) and
              (Trap.H<=TrapStandingHeight),'Expected floor spikes, not enemies');
            for J:=0 to 100 do begin
              T:=Plan.Duration*J/100;
              Obstacle:=Trap.BoundsAt(T);
              Need(Obstacle.Bottom>=Trap.Y,'Spike passed through the floor');
              Need(GroundAt(Obstacle.Left,Trap.Y,T) and GroundAt(Obstacle.Right,Trap.Y,T),'Spikes have no supporting floor');
            end;
            if Trap.Kind=tkCeiling then begin
              Obstacle:=Trap.BoundsAt(Trap.Fire);
              Need(Plan.CeilingSupports(Obstacle.Left,Obstacle.Right,Obstacle.Top),'Falling spike did not start at the ceiling');
              Need((Trap.BoundsAt(Trap.Cue).Bottom=Trap.Y) and (Trap.BoundsAt(Trap.Finish).Bottom=Trap.Y),'Falling spike does not stop on the floor');
              Need(Abs(Trap.Travel-24*Sqr(Trap.Cue-Trap.Fire))<1E-8,'Falling spike is not accelerated by gravity');
            end;
            // 全寿命を独立に照合し、停止・後退中や、後で戻って来る区間も省かない。
            First:=Trap.Fire;Last:=Trap.Finish;
            for J:=0 to Ceil((Last-First)*1000) do begin
              T:=Min(Last,First+J/1000);Minimum:=Min(Minimum,Plan.Clearance(Trap,T));
              Need(not TrapOverlap(Plan.PlayerBounds(T),Trap.BoundsAt(T)),'Actual collision');Inc(Count);end;
          end;
          Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsTrapAction,Ord(Theme)+1);Ref.SourceRevision:=Audio.SourceRevision;
          SaveTrapPlan(Plan,Audio,Ref);Restored:=LoadTrapAudio(Ref,Source,0);
          try Again:=LoadTrapPlan(Ref,Restored,0);
            try Need(Length(Again.Ceilings)=Length(Plan.Ceilings),'Ceilings were not saved');
              for I:=0 to High(Plan.Ceilings) do Need((Again.Ceilings[I].Y=Plan.Ceilings[I].Y) and
                (Again.Ceilings[I].Left=Plan.Ceilings[I].Left),'Saved ceiling changed');
              for I:=0 to 200 do begin T:=I*Plan.Duration/200;A:=Plan.Position(T);B:=Again.Position(T);
              Need((A.X=B.X) and (A.Y=B.Y) and (Plan.ForwardX(T)=Again.ForwardX(T)) and
                (Plan.Facing(T)=Again.Facing(T)),'Saved trajectory/camera/facing differs');end;
            finally Again.Free;end;
          finally Restored.Free;end;
          Settings:=TRhythmSettings.Defaults;Settings.Style:=rsTrapAction;Settings.TrapStage:=Theme;Settings.Music:=Source;Settings.Plan:=Ref;
          Need(TRhythmSettings.TryJSON(Settings.ToJSON,Loaded) and (Loaded.TrapStage=Theme) and (Loaded.Plan.Key=Ref.Key),'Theme settings round trip');
          RenderBackdrop(0);BackgroundHash:=Hash(Bitmap);
          for T in TArray<Double>.Create(0.25,3,12.75,84.5,137.125,Plan.Duration) do begin
            RenderBackdrop(T);Need(Hash(Bitmap)=BackgroundHash,'Background moves or zooms');
          end;
          Render(137.125);H:=Hash(Bitmap);Render(3);Render(137.125);Need(Hash(Bitmap)=H,'Reverse seek changes pixels');
          Render(84.5);Sheet.Canvas.Draw((Ord(Theme) mod 2)*960,(Ord(Theme) div 2)*540,Bitmap);
          if Theme=tsCave then begin
            for I:=0 to 15 do begin
              T:=0;Found:=False;
              for Trap in Plan.Obstacles do if (Trap.Kind=tkCeiling) and
                (Ord(Plan.Moves[Trap.Move].Avoidance)=I) then begin
                T:=Trap.Fire+(Trap.Cue-Trap.Fire)*0.75;Found:=True;Break;
              end;
              if not Found then for M in Plan.Moves do if (Ord(M.Avoidance)=I) and (M.Pattern<>18) then begin
                if M.Kind=tmJump then T:=M.Start+(M.Finish-M.Start)*0.70
                else if (M.Kind=tmStop) and M.LandSynced then T:=M.Finish-0.03 else T:=M.Cue;
                Found:=True;Break;
              end;
              Need(Found,'Missing visual example');
              Render(T);Montage.Canvas.Draw((I mod 4)*960,(I div 4)*540,Bitmap);
              Montage.Canvas.Font.Name:='Segoe UI';Montage.Canvas.Font.Size:=16;Montage.Canvas.Font.Color:=clWhite;
              Montage.Canvas.Brush.Style:=bsClear;
              Montage.Canvas.TextOut((I mod 4)*960+12,(I div 4)*540+12,IntToStr(I+1)+' '+AvoidTitles[I]);
            end;
            PNG(Montage,TPath.Combine(Folder,'TrapActionTraps.png'));
            PNG(Montage,TPath.Combine(Folder,'TrapActionSixteenPatterns.png'));
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
            Trap:=Default(TTrapObstacle);Trap.Kind:=tkSpikes;Trap.Move:=0;
            Trap.Fire:=M.Start+0.01;Trap.Cue:=(M.Start+M.Finish)*0.5;Trap.Finish:=M.Finish-0.01;
            Trap.X:=M.Position(Trap.Cue).X;Trap.Y:=M.Origin.Y;Trap.W:=0.62;Trap.H:=0.5;
            Plan.Obstacles[0]:=Trap;Rejected:=False;
            try ValidateTrapPlan(Plan,nil);except on E:EConvertError do Rejected:=True;end;
            Plan.Obstacles[0]:=SavedTrap;Need(Rejected,'Collision during leftward retreat accepted');Break;
          end;
        finally Plan.Free;end;
      end;
      PNG(Sheet,TPath.Combine(Folder,'TrapActionThemes.png'));
      I:=0;for K:=0 to Ord(High(TTrapKind)) do if TTrapKind(K) in Seen then Inc(I);
      Need(Seen=[tkSpikes,tkHiddenSpikes,tkCeiling,tkPit,tkCrumble,tkVanish],'Trap coverage');
      Patterns:=0;for K:=0 to Ord(taTravel)-1 do if TTrapAvoidance(K) in Variations then Inc(Patterns);
      Need(Patterns=16,'Missing avoidance patterns');
      Need(Moves=[tmRun,tmJump,tmStop],'Only walking, jumping and standing are allowed');
      Writeln('PASS ',Count,' subframe collision checks; ',I,' trap kinds; ',Patterns,' avoidance patterns; minimum clearance ',Minimum:0:4);
      Audio.Hits:=nil;Audio.Envelope:=nil;Audio.SoundEnd:=0;
      for T in TArray<Double>.Create(0.05,1,8,180) do begin
        Audio.Duration:=T;Plan:=BuildTrapPlan(Audio,tsCave,nil);
        try Need(Length(Plan.Obstacles)=0,'Silence generated unrelated hazards');
          for M in Plan.Moves do Need(M.Kind=tmRun,'Silence generated unnecessary jumps');
          Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsTrapAction,1);Ref.SourceRevision:=Audio.SourceRevision;
          SaveTrapPlan(Plan,Audio,Ref);Restored:=LoadTrapAudio(Ref,Source,0);
          try Again:=LoadTrapPlan(Ref,Restored,0);Again.Free;finally Restored.Free;end;
        finally Plan.Free;end;
      end;
    finally Audio.Free;Surface.Free;Bitmap.Free;Sheet.Free;Montage.Free;end;
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);Halt(1);end;end;
end.
