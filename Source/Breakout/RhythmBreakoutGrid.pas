unit RhythmBreakoutGrid;
// Complete, fixed brick grids and a single precomputed ball path driven by original onsets.
interface

uses System.SysUtils, System.JSON, RhythmAudio, RhythmBreakoutGeometry;

const GRID_SCORE_VERSION = 6;

type
  TGridBrick = record
    Bounds: TBreakBlock;
    Wave, Row, Column: Integer;
  end;
  TGridWave = record
    Appear: Double;
    First, Columns, Rows: Integer;
  end;
  TBreakGrid = class
  private
    FBricks: TArray<TGridBrick>;
    FWaves: TArray<TGridWave>;
    FFlights: TArray<TBreakSegment>;
    FPaddles: TArray<TBreakPaddle>;
    FLaunch, FGoal, FBallEnd, FEnd: Double;
    FStrikes, FAuxiliary, FCatches: Integer;
    procedure Check(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>);
    function FlightAt(Time: Double): Integer;
    function GetCount: Integer;
  public
    class function Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TBreakGrid; static;
    class function Load(Data: TJSONObject; Audio: TRhythmAudio): TBreakGrid; static;
    function ExportData: TJSONObject;
    function BrickAt(Index: Integer): TBreakBlock;
    function BrickRow(Index: Integer): Integer;
    function BrickVisible(Index: Integer; Time: Double): Boolean;
    function PositionAt(Time: Double): TBreakPoint;
    function PaddleAt(Time: Double): Double;
    function HeldAt(Time: Double): Boolean;
    property Count: Integer read GetCount;
    property StrikeCount: Integer read FStrikes;
    property LaunchTime: Double read FLaunch;
    property GoalTime: Double read FGoal;
    property BallEnd: Double read FBallEnd;
    property EndTime: Double read FEnd;
    property AuxiliaryCount: Integer read FAuxiliary;
    property CatchCount: Integer read FCatches;
  end;

implementation

uses System.Math, System.Generics.Collections, RhythmBreakoutScoreTypes;

const
  MaxCells = 48;
  MaxBricks = 9500;
  MinHitGap = 0.36;
  MinFirstHit = 0.16;
  ColumnPitch = 0.144;
  GridTop = 0.205;
  LeftWall = BREAK_RADIUS;
  RightWall = BREAK_WIDTH - BREAK_RADIUS;
  GeometryTolerance = 1E-7;

type
  TLeg = record
    Start, Bounce, Finish: TBreakPoint;
    Length, WallFraction, FinishDX: Double;
  end;

function Finite(X: Double): Boolean;
begin
  Result := not IsNan(X) and not IsInfinite(X);
end;

function SamePoint(const A,B: TBreakPoint): Boolean;
begin
  Result := Hypot(A.X-B.X,A.Y-B.Y) <= GeometryTolerance;
end;

function MakeLeg(const Start: TBreakPoint; DeltaX, EndY: Double): TLeg;
var
  EndX, Wall: Double;
begin
  Result.Start := Start;
  EndX := Start.X + DeltaX;
  Result.Length := Hypot(DeltaX, EndY-Start.Y);
  Result.WallFraction := 0;
  Result.FinishDX := DeltaX;
  if (EndX < LeftWall) or (EndX > RightWall) then begin
    if EndX < LeftWall then Wall := LeftWall else Wall := RightWall;
    Result.WallFraction := (Wall-Start.X)/DeltaX;
    Result.Bounce := BreakPoint(Wall, Start.Y+(EndY-Start.Y)*Result.WallFraction);
    EndX := 2*Wall-EndX;
    Result.FinishDX := -DeltaX;
  end;
  Result.Finish := BreakPoint(EndX, EndY);
end;

function CellBounds(Columns, Row, Column: Integer): TBreakBlock;
var
  X: Double;
begin
  Result := Default(TBreakBlock);
  X := BREAK_WIDTH/2+(Column-(Columns-1)*0.5)*ColumnPitch;
  Result.Left := X-SCORE_BRICK_W/2;
  Result.Right := X+SCORE_BRICK_W/2;
  Result.Top := GridTop+Row*SCORE_PITCH;
  Result.Bottom := Result.Top+SCORE_BRICK_H;
end;

procedure GridSize(Limit: Integer; out Columns, Rows: Integer);
var
  C,R,Rank,Best: Integer;
begin
  Columns := 6;
  Rows := 2;
  Best := -1;
  for R := 2 to 6 do
    for C := 6 to 10 do
      if C*R <= Limit then begin
        Rank := C*R*10-Abs(C-8);
        if Rank > Best then begin
          Best := Rank;
          Columns := C;
          Rows := R;
        end;
      end;
end;

class function TBreakGrid.Build(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TBreakGrid;
var
  Hits: TList<Integer>;
  Bricks: TList<TGridBrick>;
  Waves: TList<TGridWave>;
  Flights: TList<TBreakSegment>;
  Paddles: TList<TBreakPaddle>;
  Wave: TGridWave;
  Brick: TGridBrick;
  Cells: array[0..MaxCells-1] of TBreakBlock;
  Bounds: TBreakBlock;
  Down, Up, TryUp, TryDown: TLeg;
  Paddle: TBreakPoint;
  Used: set of Byte;
  I, W, K, First, Limit, StrikeLimit, Source, Cell, Aim, Bank, BestCell, LastSource, Terminal, WaveCount: Integer;
  LastHit, Hit, Gap, Serve, CatchTime, TargetX, TargetY, DeltaX: Double;
  Cost, BestCost, Speed, LastSpeed, Want, PaddleSpeed, LastPaddleTime: Double;
  procedure AddFlight(const A,B: TBreakPoint; Start, Finish: Double; Kind: TBreakEnd; Index: Integer);
  var
    Flight: TBreakSegment;
  begin
    Flight.First := Start;
    Flight.Last := Finish;
    Flight.A := A;
    Flight.B := B;
    Flight.Kind := Kind;
    Flight.Block := Index;
    Flights.Add(Flight);
  end;
  procedure AddLeg(const Leg: TLeg; Start, Finish: Double; Kind: TBreakEnd; Index: Integer = -1);
  var
    WallTime: Double;
  begin
    if Leg.WallFraction > 0 then begin
      WallTime := Start+(Finish-Start)*Leg.WallFraction;
      AddFlight(Leg.Start,Leg.Bounce,Start,WallTime,beWallX,-1);
      AddFlight(Leg.Bounce,Leg.Finish,WallTime,Finish,Kind,Index);
    end else
      AddFlight(Leg.Start,Leg.Finish,Start,Finish,Kind,Index);
  end;
  procedure AddPaddle(Time, X: Double);
  var
    Key: TBreakPaddle;
  begin
    Key.Time := Time;
    Key.X := EnsureRange(X,BREAK_PADDLE_HALF_NEW,BREAK_WIDTH-BREAK_PADDLE_HALF_NEW);
    Paddles.Add(Key);
  end;
  function Touches(const A,B: TBreakPoint; const Box: TBreakBlock): Boolean;
  begin
    Result := (Min(A.X,B.X)<=Box.Right+BREAK_RADIUS) and (Max(A.X,B.X)>=Box.Left-BREAK_RADIUS) and
      (Min(A.Y,B.Y)<=Box.Bottom+BREAK_RADIUS) and (Max(A.Y,B.Y)>=Box.Top-BREAK_RADIUS) and
      (BreakRectDistance(A,B,Box)<=BREAK_RADIUS+GeometryTolerance);
  end;
  function ClearBesides(const Leg: TLeg; Target: Integer): Boolean;
  var
    J: Integer;
  begin
    for J := 0 to K-1 do begin
      if (J=Target) or (J in Used) then Continue;
      if Leg.WallFraction>0 then begin
        if Touches(Leg.Start,Leg.Bounce,Cells[J]) or Touches(Leg.Bounce,Leg.Finish,Cells[J]) then Exit(False);
      end else if Touches(Leg.Start,Leg.Finish,Cells[J]) then Exit(False);
    end;
    Result := True;
  end;
begin
  Result := TBreakGrid.Create;
  Hits := nil;
  Bricks := nil;
  Waves := nil;
  Flights := nil;
  Paddles := nil;
  try
    try
      Hits := TList<Integer>.Create;
      Bricks := TList<TGridBrick>.Create;
      Waves := TList<TGridWave>.Create;
      Flights := TList<TBreakSegment>.Create;
      Paddles := TList<TBreakPaddle>.Create;
      LastHit := -MinHitGap;
      Terminal := -1;
      for I := 0 to High(Audio.Hits) do begin
        if Assigned(Cancel) and Cancel() then Abort;
        Hit := Audio.Hits[I].Time;
        if (Hit < MinFirstHit) or (Hit > Audio.SoundEnd) then Continue;
        Terminal := I;
        if (Hit-LastHit >= MinHitGap) and (Hits.Count < MaxBricks) then begin
          Hits.Add(I);
          LastHit := Hit;
        end;
      end;
      // Use the last available onset without compressing the preceding round trip.
      if (Hits.Count > 0) and (Terminal > Hits.Last) then Hits[Hits.Count-1] := Terminal;
      Down := Default(TLeg);
      LastHit := 0;
      LastSource := -1;
      LastSpeed := 1.9;
      LastPaddleTime := 0;
      Paddle := BreakPoint(BREAK_WIDTH/2,BREAK_PADDLE_Y);
      AddPaddle(0,Paddle.X);
      WaveCount := Max(1,(Hits.Count+MaxCells-1) div MaxCells);
      for W := 0 to WaveCount-1 do begin
        First := W*Hits.Count div WaveCount;
        Limit := (W+1)*Hits.Count div WaveCount-First;
        GridSize(Limit,Wave.Columns,Wave.Rows);
        Wave.First := Bricks.Count;
        Wave.Appear := 0;
        K := Wave.Columns*Wave.Rows;
        StrikeLimit := Min(K,Limit);
        Waves.Add(Wave);
        Used := [];
        for Cell := 0 to K-1 do Cells[Cell] := CellBounds(Wave.Columns,Cell div Wave.Columns,Cell mod Wave.Columns);
        for I := 0 to StrikeLimit-1 do begin
          if Assigned(Cancel) and Cancel() then Abort;
          if StrikeLimit=1 then Source := Hits[First+Limit-1]
          else Source := Hits[First+I*(Limit-1) div (StrikeLimit-1)];
          Hit := Audio.Hits[Source].Time;
          Gap := Hit-LastHit;
          if LastSource>=0 then Paddle := Down.Finish;
          Brick.Wave := W;
          BestCost := 1E30;
          BestCell := -1;
          Want := 0.22+0.12*Sin(Bricks.Count*2.39996);
          for Cell := K-1 downto 0 do begin
            if Cell in Used then Continue;
            Bounds := Cells[Cell];
            TargetY := Bounds.Bottom+BREAK_RADIUS;
            for Aim := -1 to 1 do begin
              TargetX := (Bounds.Left+Bounds.Right)/2+Aim*SCORE_BRICK_W*0.19;
              for Bank := -1 to 1 do begin
                case Bank of
                  -1: DeltaX := 2*LeftWall-TargetX-Paddle.X;
                  1: DeltaX := 2*RightWall-TargetX-Paddle.X;
                else DeltaX := TargetX-Paddle.X;
                end;
                if Abs(DeltaX)>RightWall-LeftWall then Continue;
                TryUp := MakeLeg(Paddle,DeltaX,TargetY);
                Speed := (Down.Length+TryUp.Length)/Gap;
                if LastSource<0 then Speed := Max(1.9,TryUp.Length/Gap)
                else if Gap>1.5 then Speed := Max(1.6,Speed);
                Cost := Abs(Ln(Speed/1.9))*0.45+Abs(Ln(Speed/LastSpeed))*0.32+
                  Abs(Abs(DeltaX)-Want)*0.65+Abs(Bank)*0.12+(Wave.Rows-1-Cell div Wave.Columns)*0.035;
                TryDown := MakeLeg(TryUp.Finish,TryUp.FinishDX,BREAK_PADDLE_Y);
                Cost := Cost+Abs(TryDown.Finish.X-Paddle.X)*0.33;
                if (Cost<BestCost) and ClearBesides(TryUp,Cell) and ClearBesides(TryDown,Cell) then begin
                  BestCost := Cost;
                  BestCell := Cell;
                  Up := TryUp;
                end;
              end;
            end;
          end;
          if BestCell<0 then raise EInvalidOp.Create('Unreachable grid cell');
          Include(Used,BestCell);
          Brick.Row := BestCell div Wave.Columns;
          Brick.Column := BestCell mod Wave.Columns;
          Brick.Bounds := Cells[BestCell];
          Brick.Bounds.Time := Hit;
          Brick.Bounds.Source := Source;
          Brick.Bounds.Strength := EnsureRange(Audio.Hits[Source].Strength,0.0,1.0);
          Speed := (Down.Length+Up.Length)/Gap;
          if LastSource<0 then begin
            LastSpeed := Max(1.9,Speed);
            Serve := Max(0.0,Hit-Up.Length/LastSpeed);
            Result.FLaunch := Serve;
            if Serve>1E-8 then AddPaddle(Serve,Paddle.X);
          end else begin
            if (Gap>1.5) and (Speed<1.6) then Speed := 1.6;
            CatchTime := LastHit+Down.Length/Speed;
            if I=0 then begin
              // Reveal the next complete grid when the ball is back below it at the paddle.
              Wave.Appear := CatchTime;
              Waves[W] := Wave;
            end;
            // Hold at the visible paddle during silence instead of crawling across the board.
            Serve := Max(CatchTime,Hit-Up.Length/Speed);
            AddLeg(Down,LastHit,CatchTime,bePaddle);
            AddPaddle(CatchTime,Paddle.X);
            if Serve-CatchTime>1E-8 then begin
              AddFlight(Paddle,Paddle,CatchTime,Serve,beHold,-1);
              AddPaddle(Serve,Paddle.X);
            end
            else Serve := CatchTime;
            LastPaddleTime := CatchTime;
            LastSpeed := Speed;
          end;
          AddLeg(Up,Serve,Hit,beBlock,Bricks.Count);
          Bricks.Add(Brick);
          LastHit := Hit;
          LastSource := Source;
          Down := MakeLeg(Up.Finish,Up.FinishDX,BREAK_PADDLE_Y);
        end;
        Inc(Result.FStrikes,StrikeLimit);
        // A short or silent track still opens on a complete playable grid.
        for Cell := 0 to K-1 do if not (Cell in Used) then begin
          Brick.Wave := W;
          Brick.Row := Cell div Wave.Columns;
          Brick.Column := Cell mod Wave.Columns;
          Brick.Bounds := Cells[Cell];
          Brick.Bounds.Source := -1;
          Brick.Bounds.Time := Max(Audio.Duration,LastHit+0.55)+1;
          Bricks.Add(Brick);
        end;
      end;
      Result.FGoal := LastHit;
      if Result.FStrikes=0 then begin
        Result.FLaunch := Audio.Duration;
        Result.FBallEnd := Audio.Duration;
      end else begin
        Result.FBallEnd := LastHit+Min(0.50,Down.Length/Max(0.9,LastSpeed));
        PaddleSpeed := 1.5*Abs(Down.Finish.X-Paddles.Last.X)/(Result.FBallEnd-LastPaddleTime);
        if PaddleSpeed>3.8 then Result.FBallEnd := LastHit+0.50;
        AddLeg(Down,LastHit,Result.FBallEnd,beFinish);
        AddPaddle(Result.FBallEnd,Down.Finish.X);
      end;
      if Result.FStrikes=Bricks.Count then Result.FEnd := LastHit+0.55
      else Result.FEnd := Max(Audio.Duration,Result.FBallEnd);
      Result.FBricks := Bricks.ToArray;
      Result.FWaves := Waves.ToArray;
      Result.FFlights := Flights.ToArray;
      Result.FPaddles := Paddles.ToArray;
      Result.Check(Audio,Cancel);
    except
      Result.Free;
      raise;
    end;
  finally
    Paddles.Free;
    Flights.Free;
    Waves.Free;
    Bricks.Free;
    Hits.Free;
  end;
end;

procedure TBreakGrid.Check(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>);
var
  I,J,K,Offset,Hits,Owner: Integer;
  B: TGridBrick;
  W: TGridWave;
  R: TBreakBlock;
  S,Previous: TBreakSegment;
  P,V,Reflected,ActiveStart: TBreakPoint;
  Distance: Double;
  Cells: set of Byte;
  procedure Need(Condition: Boolean; const Why: string);
  begin
    if not Condition then raise EConvertError.Create('Fixed breakout grid: '+Why);
  end;
  function InBoard(const X: TBreakPoint): Boolean;
  begin
    Result := Finite(X.X) and Finite(X.Y) and (X.X>=LeftWall-GeometryTolerance) and
      (X.X<=RightWall+GeometryTolerance) and (X.Y>=BREAK_RADIUS-GeometryTolerance) and
      (X.Y<=BREAK_PADDLE_Y+GeometryTolerance);
  end;
  function Direction(const A,C: TBreakPoint): TBreakPoint;
  var
    L: Double;
  begin
    L := Hypot(C.X-A.X,C.Y-A.Y);
    Need(L>1E-8,'zero-length flight');
    Result := BreakPoint((C.X-A.X)/L,(C.Y-A.Y)/L);
  end;
begin
  Need(Finite(FLaunch) and Finite(FGoal) and Finite(FBallEnd) and Finite(FEnd),'time metadata');
  Need((Count>=12) and (Count<=MaxBricks) and (FStrikes>=0) and (FStrikes<=Count) and (Length(FWaves)>0),'limits');
  if FStrikes=0 then
    Need((Length(FFlights)=0) and (Length(FPaddles)=1) and (FLaunch=Audio.Duration) and (FGoal=0) and
      (FBallEnd=Audio.Duration) and (FEnd=Audio.Duration),'silent board')
  else begin
    Need((Length(FFlights)>0) and (Length(FFlights)<=FStrikes*6+2) and
      (Length(FPaddles)>=2) and (Length(FPaddles)<=FStrikes*2+1),'flight limits');
    Need((FLaunch>=0) and (FLaunch<FGoal) and (FGoal=FBricks[FStrikes-1].Bounds.Time) and
      (FBallEnd>FGoal) and (FBallEnd<=FEnd),'finish');
  end;
  if FStrikes=Count then Need(Abs(FEnd-FGoal-0.55)<=GeometryTolerance,'clear tail')
  else Need((Length(FWaves)=1) and (FEnd>=Audio.Duration),'partial board');
  Offset := 0;
  for I := 0 to High(FWaves) do begin
    W := FWaves[I];
    K := W.Columns*W.Rows;
    Need((W.First=Offset) and (W.Columns in [1..10]) and (W.Rows in [1..6]) and
      (K<=MaxCells) and (Offset+K<=Count) and Finite(W.Appear),'wave bounds');
    if I=0 then Need(W.Appear=0,'first grid appears late')
    else Need(W.Appear>FBricks[Offset-1].Bounds.Time,'overlapping waves');
    Need(W.Appear<FBricks[Offset].Bounds.Time,'invisible first contact');
    Cells := [];
    for J := 0 to K-1 do begin
      B := FBricks[Offset+J];
      Need((B.Wave=I) and (B.Row>=0) and (B.Row<W.Rows) and
        (B.Column>=0) and (B.Column<W.Columns),'brick outside fixed grid');
      Owner := B.Row*W.Columns+B.Column;
      Need(not (Owner in Cells),'duplicate brick cell');
      Include(Cells,Owner);
      if Offset+J>=FStrikes then begin
        Need((B.Bounds.Source=-1) and Finite(B.Bounds.Time) and (B.Bounds.Time>FEnd),'unbroken brick');
        Continue;
      end;
      Need((B.Bounds.Source>=0) and (B.Bounds.Source<Length(Audio.Hits)) and
        Finite(B.Bounds.Time) and (B.Bounds.Time>0) and (B.Bounds.Time<=Audio.SoundEnd+GeometryTolerance) and
        (Abs(B.Bounds.Time-Audio.Hits[B.Bounds.Source].Time)<=1E-10) and Finite(B.Bounds.Strength) and
        (Abs(B.Bounds.Strength-EnsureRange(Audio.Hits[B.Bounds.Source].Strength,0.0,1.0))<=1E-12),'changed source onset');
      if Offset+J>0 then Need(B.Bounds.Time>FBricks[Offset+J-1].Bounds.Time,'hit order');
    end;
    Inc(Offset,K);
  end;
  Need(Offset=Count,'unowned bricks');
  if FStrikes=0 then Exit;
  Need((FPaddles[0].Time=0) and (FPaddles[High(FPaddles)].Time=FBallEnd),'paddle endpoints');
  for I := 0 to High(FPaddles) do begin
    Need(Finite(FPaddles[I].Time) and Finite(FPaddles[I].X) and (FPaddles[I].X>=BREAK_PADDLE_HALF_NEW) and
      (FPaddles[I].X<=BREAK_WIDTH-BREAK_PADDLE_HALF_NEW),'paddle bounds');
    if I>0 then Need(FPaddles[I].Time>FPaddles[I-1].Time,'paddle order');
  end;
  Need((FFlights[0].First=FLaunch) and (FFlights[High(FFlights)].Last=FBallEnd) and
    (FFlights[High(FFlights)].Kind=beFinish),'flight endpoints');
  Need(SamePoint(FFlights[0].A,BreakPoint(PaddleAt(0),BREAK_PADDLE_Y)) and
    (FFlights[0].B.Y<BREAK_PADDLE_Y),'initial serve');
  Hits := 0;
  FAuxiliary := 0;
  FCatches := 0;
  Previous := Default(TBreakSegment);
  for I := 0 to High(FFlights) do begin
    if Assigned(Cancel) and Cancel() then Abort;
    S := FFlights[I];
    Need(InBoard(S.A) and InBoard(S.B) and Finite(S.First) and Finite(S.Last) and
      (S.Last-S.First>1E-9),'flight bounds');
    if I>0 then Need((Abs(Previous.Last-S.First)<=GeometryTolerance) and SamePoint(Previous.B,S.A),'flight continuity');
    if S.Kind=beHold then begin
      Need((Previous.Kind=bePaddle) and SamePoint(S.A,S.B) and (I<High(FFlights)) and
        (FFlights[I+1].B.Y<S.B.Y),'hold must serve from the paddle');
      Need((Abs(S.B.X-PaddleAt(S.First))<=BREAK_PADDLE_HALF_NEW+GeometryTolerance) and
        (PaddleAt(S.First)=PaddleAt(S.Last)),'paddle moved during hold');
      Inc(FCatches);
    end else begin
      V := Direction(S.A,S.B);
      if (I>0) and (Previous.Kind=beBlock) then begin
        Reflected := Direction(Previous.A,Previous.B);
        Reflected.Y := -Reflected.Y;
        Need(SamePoint(V,Reflected),'brick reflection');
      end else if Previous.Kind=beWallX then begin
        Reflected := Direction(Previous.A,Previous.B);
        Reflected.X := -Reflected.X;
        Need(SamePoint(V,Reflected),'side reflection');
      end;
      if (I>0) and (Previous.Kind in [bePaddle,beHold]) then Need(V.Y<0,'paddle direction');
      case S.Kind of
        beBlock: begin
          Need((Hits<FStrikes) and (S.Block=Hits),'strike order');
          R := FBricks[Hits].Bounds;
          Need((S.Last=R.Time) and (Abs(S.B.Y-R.Bottom-BREAK_RADIUS)<=GeometryTolerance) and
            (S.B.X>=R.Left) and (S.B.X<=R.Right) and (V.Y<0),'strike misses physical brick');
        end;
        beWallX: begin
          Need(((V.X<0) and (Abs(S.B.X-LeftWall)<=GeometryTolerance)) or
            ((V.X>0) and (Abs(S.B.X-RightWall)<=GeometryTolerance)),'side wall contact');
          Inc(FAuxiliary);
        end;
        bePaddle,beFinish: begin
          P := BreakPoint(PaddleAt(S.Last),BREAK_PADDLE_Y);
          Need((V.Y>0) and (Abs(S.B.Y-P.Y)<=GeometryTolerance) and
            (Abs(S.B.X-P.X)<=BREAK_PADDLE_HALF_NEW+GeometryTolerance),'paddle contact');
          if S.Kind=bePaddle then Inc(FAuxiliary)
          else Need(I=High(FFlights),'early finish');
        end;
      else
        Need(False,'unknown flight type');
      end;
    end;
    if S.Kind<>beBlock then Need(S.Block=-1,'non-brick flight has a target');
    if S.Kind<>beHold then for J := Hits to High(FBricks) do begin
      B := FBricks[J];
      if FWaves[B.Wave].Appear>S.Last then Break;
      ActiveStart := BreakSegmentPoint(S,Max(S.First,FWaves[B.Wave].Appear));
      Distance := BreakRectDistance(ActiveStart,S.B,B.Bounds);
      if (S.Kind=beBlock) and (S.Block=J) then
        Need(Abs(Distance-BREAK_RADIUS)<=GeometryTolerance,'brick penetration')
      else if Distance<=BREAK_RADIUS+GeometryTolerance then
        Need(False,Format('earlier collision on flight %d at %.6f-%.6f with cell %d',[I,S.First,S.Last,J]));
    end;
    if S.Kind=beBlock then Inc(Hits);
    Previous := S;
  end;
  Need(Hits=FStrikes,'missing planned destruction');
end;

function TBreakGrid.GetCount: Integer;
begin
  Result := Length(FBricks);
end;

function TBreakGrid.BrickAt(Index: Integer): TBreakBlock;
begin
  Result := FBricks[Index].Bounds;
end;

function TBreakGrid.BrickRow(Index: Integer): Integer;
begin
  Result := FBricks[Index].Row;
end;

function TBreakGrid.BrickVisible(Index: Integer; Time: Double): Boolean;
begin
  Result := Time >= FWaves[FBricks[Index].Wave].Appear;
end;

function TBreakGrid.FlightAt(Time: Double): Integer;
var
  Lo,Hi,Mid: Integer;
begin
  Lo := 0;
  Hi := High(FFlights);
  while Lo<Hi do begin
    Mid := (Lo+Hi) div 2;
    if FFlights[Mid].Last<Time then Lo := Mid+1 else Hi := Mid;
  end;
  Result := Lo;
end;

function TBreakGrid.PositionAt(Time: Double): TBreakPoint;
begin
  if Length(FFlights)=0 then Exit(BreakPoint(BREAK_WIDTH/2,BREAK_PADDLE_Y));
  Result := BreakSegmentPoint(FFlights[FlightAt(Time)],Time);
end;

function TBreakGrid.PaddleAt(Time: Double): Double;
begin
  Result := BreakPaddleAt(FPaddles,Time);
end;

function TBreakGrid.HeldAt(Time: Double): Boolean;
begin
  Result := (FStrikes<Count) and ((FStrikes=0) or (Time>=FBallEnd));
  if Result then Exit;
  Result := (Length(FFlights)>0) and ((Time<FLaunch) or (FFlights[FlightAt(Time)].Kind=beHold));
end;

function TBreakGrid.ExportData: TJSONObject;
var
  Items, Row: TJSONArray;
  W: TGridWave;
  B: TGridBrick;
  S: TBreakSegment;
  K: TBreakPaddle;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('schema',1);
    Result.AddPair('style','breakout');
    Result.AddPair('version',GRID_SCORE_VERSION);
    Result.AddPair('layout','fixed-grid');
    Result.AddPair('launch',FLaunch);
    Result.AddPair('strikes',FStrikes);
    Result.AddPair('goal',FGoal);
    Result.AddPair('ballEnd',FBallEnd);
    Result.AddPair('end',FEnd);
    Items := TJSONArray.Create;
    Result.AddPair('waves',Items);
    for W in FWaves do begin
      Row := TJSONArray.Create;
      Items.AddElement(Row);
      Row.Add(W.Appear).Add(W.First).Add(W.Columns).Add(W.Rows);
    end;
    Items := TJSONArray.Create;
    Result.AddPair('bricks',Items);
    for B in FBricks do begin
      Row := TJSONArray.Create;
      Items.AddElement(Row);
      Row.Add(B.Wave).Add(B.Row).Add(B.Column).Add(B.Bounds.Source).Add(B.Bounds.Time).Add(B.Bounds.Strength);
    end;
    Items := TJSONArray.Create;
    Result.AddPair('flights',Items);
    for S in FFlights do begin
      Row := TJSONArray.Create;
      Items.AddElement(Row);
      Row.Add(S.First).Add(S.Last).Add(S.A.X).Add(S.A.Y).Add(S.B.X).Add(S.B.Y).Add(Ord(S.Kind)).Add(S.Block);
    end;
    Items := TJSONArray.Create;
    Result.AddPair('paddles',Items);
    for K in FPaddles do begin
      Row := TJSONArray.Create;
      Items.AddElement(Row);
      Row.Add(K.Time).Add(K.X);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TBreakGrid.Load(Data: TJSONObject; Audio: TRhythmAudio): TBreakGrid;
var
  Items, Row: TJSONArray;
  I, W, R, C, K: Integer;
  function ReadArray(const Name: string; MaxCount: Integer): TJSONArray;
  begin
    Result := Data.GetValue<TJSONArray>(Name);
    if (Result=nil) or (Result.Count>MaxCount) then raise EConvertError.Create('Fixed grid array: '+Name);
  end;
  function ReadRow(Index, Columns: Integer): TJSONArray;
  begin
    if not (Items.Items[Index] is TJSONArray) then raise EConvertError.Create('Fixed grid row');
    Result := TJSONArray(Items.Items[Index]);
    if Result.Count<>Columns then raise EConvertError.Create('Fixed grid row width');
  end;
begin
  if Data.GetValue<string>('layout','')<>'fixed-grid' then raise EConvertError.Create('Fixed grid layout');
  Result := TBreakGrid.Create;
  try
    Result.FLaunch := Data.GetValue<Double>('launch');
    Result.FStrikes := Data.GetValue<Integer>('strikes');
    Result.FGoal := Data.GetValue<Double>('goal');
    Result.FBallEnd := Data.GetValue<Double>('ballEnd');
    Result.FEnd := Data.GetValue<Double>('end');
    Items := ReadArray('waves',MaxBricks div MaxCells+1);
    SetLength(Result.FWaves,Items.Count);
    for I := 0 to Items.Count-1 do begin
      Row := ReadRow(I,4);
      Result.FWaves[I].Appear := Row.Items[0].GetValue<Double>;
      Result.FWaves[I].First := Row.Items[1].GetValue<Integer>;
      Result.FWaves[I].Columns := Row.Items[2].GetValue<Integer>;
      Result.FWaves[I].Rows := Row.Items[3].GetValue<Integer>;
    end;
    Items := ReadArray('bricks',MaxBricks);
    SetLength(Result.FBricks,Items.Count);
    for I := 0 to Items.Count-1 do begin
      Row := ReadRow(I,6);
      W := Row.Items[0].GetValue<Integer>;
      R := Row.Items[1].GetValue<Integer>;
      C := Row.Items[2].GetValue<Integer>;
      if (W<0) or (W>=Length(Result.FWaves)) then raise EConvertError.Create('Fixed grid wave index');
      Result.FBricks[I].Wave := W;
      Result.FBricks[I].Row := R;
      Result.FBricks[I].Column := C;
      Result.FBricks[I].Bounds := CellBounds(Result.FWaves[W].Columns,R,C);
      Result.FBricks[I].Bounds.Source := Row.Items[3].GetValue<Integer>;
      Result.FBricks[I].Bounds.Time := Row.Items[4].GetValue<Double>;
      Result.FBricks[I].Bounds.Strength := Row.Items[5].GetValue<Double>;
    end;
    Items := ReadArray('flights',MaxBricks*6+2);
    SetLength(Result.FFlights,Items.Count);
    for I := 0 to Items.Count-1 do begin
      Row := ReadRow(I,8);
      K := Row.Items[6].GetValue<Integer>;
      if (K<Ord(Low(TBreakEnd))) or (K>Ord(High(TBreakEnd))) then raise EConvertError.Create('Fixed grid flight type');
      Result.FFlights[I].First := Row.Items[0].GetValue<Double>;
      Result.FFlights[I].Last := Row.Items[1].GetValue<Double>;
      Result.FFlights[I].A := BreakPoint(Row.Items[2].GetValue<Double>,Row.Items[3].GetValue<Double>);
      Result.FFlights[I].B := BreakPoint(Row.Items[4].GetValue<Double>,Row.Items[5].GetValue<Double>);
      Result.FFlights[I].Kind := TBreakEnd(K);
      Result.FFlights[I].Block := Row.Items[7].GetValue<Integer>;
    end;
    Items := ReadArray('paddles',MaxBricks*2+1);
    SetLength(Result.FPaddles,Items.Count);
    for I := 0 to Items.Count-1 do begin
      Row := ReadRow(I,2);
      Result.FPaddles[I].Time := Row.Items[0].GetValue<Double>;
      Result.FPaddles[I].X := Row.Items[1].GetValue<Double>;
    end;
    Result.Check(Audio,nil);
  except
    Result.Free;
    raise;
  end;
end;

end.
