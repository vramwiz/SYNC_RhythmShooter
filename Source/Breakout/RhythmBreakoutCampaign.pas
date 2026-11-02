unit RhythmBreakoutCampaign;
// Prepared normal-stage / boss-stage score. Rendering never plans or analyses.
interface
uses System.SysUtils,System.JSON,System.Generics.Collections,RhythmAudio,RhythmPlanRef,
RhythmBreakoutGeometry,RhythmBreakoutScore,RhythmBarrage;
type
  TBreakBoard=class
  public
    Appear,Ready,Cut:Double;
    Sources:TArray<Integer>;
    Plan:TBreakScorePlan;
    destructor Destroy; override;
  end;
  TBreakBoss=record
    Start,Quiet,Kill,Finish:Double;
    KillSource,HP:Integer;
    Paddles:TArray<TScoreKey>;
  end;
  TBreakAttack=record
    Path:TScoreExtraBall;
    Boss,Source:Integer;
  end;
  TBreakBossBullet=record
    Motion:TRhythmEnemyBullet;
    Shield:Boolean;
  end;
  TBreakNormalExtra=record
    Board,Index:Integer;
    Launch:Double;
  end;
  TBreakCampaign=class
  private
    FBoards:TObjectList<TBreakBoard>;
    FBosses:TArray<TBreakBoss>;
    FAttacks:TArray<TBreakAttack>;
    FBullets:TArray<TBreakBossBullet>;
    FEvents:TArray<TScoreEvent>;
    FOffsets,FExtras,FHits,FPrimary:TArray<Integer>;
    FBodyContacts:Boolean;
    FNormalExtras:TArray<TBreakNormalExtra>;
    FCandidateCount,FBossFrequency:Integer;
    FPaddleHalf,FDuration,FSoundEnd,FGoal,FLaunch,FBallEnd,FExit,FEnd:Double;
    FCount,FReflections,FAuxiliary,FCatches,FTrials:Integer;
    function ChildAudio(Board:TBreakBoard):TRhythmAudio;
    function MakeBoard(Appear,Ready,Cut:Double;const Cancel:TFunc<Boolean>;AllowEmpty:Boolean;ClearWave:Boolean=False):TBreakBoard;
    function MakeBoss(var Boss:TBreakBoss;Index:Integer;out Attacks:TArray<TBreakAttack>;out Bullets:TArray<TBreakBossBullet>;const Cancel:TFunc<Boolean>):Boolean;
    procedure Reindex;
    procedure Verify(const Cancel:TFunc<Boolean> = nil);
    function FindBoard(Index:Integer):Integer;
    function PrimaryBefore(Time:Double):Integer;
    function GetBossCount:Integer;
    function GetExtraCount:Integer;
    function GetBulletCount:Integer;
    function GetBossExtraCount:Integer;
    function AttackAt(const Attack:TBreakAttack;Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TBreakCampaign; static;
    class function Load(Root:TJSONObject;Audio:TRhythmAudio):TBreakCampaign; static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    function HitBefore(Time:Double):Integer;
    function ExtraBefore(Time:Double):Integer;
    function BulletBefore(Time:Double):Integer;
    function NormalExtraBefore(Time:Double):Integer;
    function RadiusAt(Time:Double):Double;
    function Hit(Index:Integer):TBreakAttack;
    function BrickAt(Index:Integer;Time:Double):TBreakBlock;
    function BrickRow(Index:Integer):Integer;
    function BlockVisible(Index:Integer;Time:Double):Boolean;
    function PaddleAt(Time:Double):Double;
    function MainAt(Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
    function ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
    function HeldAt(Time:Double):Boolean;
    function Boss(Index:Integer):TBreakBoss;
    function Bullet(Index:Integer):TBreakBossBullet;
    function HealthAt(Index:Integer;Time:Double):Double;
    function FlashAt(Index:Integer;Time:Double):Double;
    property BossFrequency:Integer read FBossFrequency;
    property BossExtraCount:Integer read GetBossExtraCount;
    property CandidateCount:Integer read FCandidateCount;
    property BodyContacts:Boolean read FBodyContacts;
    property PaddleHalf:Double read FPaddleHalf;
    property Count:Integer read FCount;
    property BossCount:Integer read GetBossCount;
    property ExtraCount:Integer read GetExtraCount;
    property BulletCount:Integer read GetBulletCount;
    property GoalTime:Double read FGoal;
    property LaunchTime:Double read FLaunch;
    property BallEnd:Double read FBallEnd;
    property ExitStart:Double read FExit;
    property EndTime:Double read FEnd;
    property Reflections:Integer read FReflections;
    property Auxiliary:Integer read FAuxiliary;
    property Catches:Integer read FCatches;
    property Trials:Integer read FTrials;
  end;
function BreakBossContact(Index,Sample:Integer):TBreakPoint;
function BreakBossRect(const Boss:TBreakBoss;Time:Double):TBreakBlock;
implementation
uses System.Math,System.Generics.Defaults,RhythmSections,RhythmStyles,RhythmPreparedData,RhythmMotion;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

function Near(A,B:Double):Boolean;
begin Result:=Abs(A-B)<1E-7;
end;

function Smooth(U:Double):Double;
begin U:=EnsureRange(U,0.0,1.0);
  Result:=U*U*(3-2*U);
end;

function BreakOrder(A,B:Double):Integer;
begin Result:=0;
  if A<B then Exit(-1);
  if A>B then Exit(1);
end;

function Fold(X:Double):Double;
var
  W,U:Double;
begin W:=BREAK_WIDTH-2*BREAK_RADIUS;
  U:=X-BREAK_RADIUS;
  U:=U-Floor(U/(2*W))*2*W;
  if U>W then U:=2*W-U;
  Result:=BREAK_RADIUS+U;
end;

function KeyAt(const Keys:TArray<TScoreKey>;Time:Double):Double;
var
  A,B,M:Integer;
  U:Double;
begin
  if Length(Keys)=0 then Exit(BREAK_WIDTH/2);
  A:=0;
  B:=Length(Keys);
  while A<B do begin M:=(A+B) div 2;
    if Keys[M].Time<=Time then A:=M+1 else B:=M;
  end;
  A:=Max(0,A-1);
  if A=High(Keys) then Exit(Keys[A].Value);
  U:=Smooth((Time-Keys[A].Time)/(Keys[A+1].Time-Keys[A].Time));
  Result:=Keys[A].Value+(Keys[A+1].Value-Keys[A].Value)*U;
end;

function SelectBoss(Audio:TRhythmAudio;Index:Integer;Ready:Double;out Boss:TBreakBoss):Boolean;
forward;
  class function TBreakCampaign.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TBreakCampaign;
  var
    I,J,N:Integer;
    Ready,Appear,Last:Double;
    Board:TBreakBoard;
    BossData:TBreakBoss;
    Attacks:TArray<TBreakAttack>;
    Bullets:TArray<TBreakBossBullet>;
  begin
    Result:=nil;
    if Audio=nil then raise EArgumentNilException.Create('Audio');
    if not Finite(Audio.Duration) or not Finite(Audio.SoundEnd) or (Audio.Duration<=0) or (Audio.SoundEnd<0) or (Audio.SoundEnd>Audio.Duration) or (Length(Audio.Hits)>100000) then raise Exception.Create('Invalid campaign audio');
    Result:=TBreakCampaign.Create;
    try
      Result.FPaddleHalf:=BREAK_PADDLE_HALF_NEW;
      Result.FBodyContacts:=True;
      Result.FCandidateCount:=Audio.BossCount;
      Result.FBossFrequency:=Audio.BossFrequency;
      Result.FDuration:=Audio.Duration;
      Result.FSoundEnd:=Audio.SoundEnd;
      SetLength(Result.FEvents,Length(Audio.Hits));
      Last:=-1;
      for I:=0 to High(Audio.Hits) do begin
        if Assigned(Cancel) and Cancel() then Abort;
        if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or (Audio.Hits[I].Time<Last) or (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('Invalid campaign accents');
        Result.FEvents[I].Time:=Audio.Hits[I].Time;
        Result.FEvents[I].Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);
        Result.FEvents[I].Source:=I;
        Last:=Audio.Hits[I].Time;
      end;
      Ready:=0;
      Appear:=0;
      for I:=0 to Audio.BossCount-1 do begin
        if Assigned(Cancel) and Cancel() then Abort;
        if Length(Result.FBosses)>=64 then Break;
        if not SelectBoss(Audio,I,Ready,BossData) then Continue;
        Board:=nil;
        try
          Board:=Result.MakeBoard(Appear,Ready,BossData.Start-0.65,Cancel,False,True);
          if (Board=nil) or (Board.Plan.Count<2) then begin Board.Free;
            Continue;
          end;
          SetLength(BossData.Paddles,1);
          BossData.Paddles[0].Time:=BossData.Start;
          BossData.Paddles[0].Value:=Board.Plan.PaddleAt(Board.Plan.EndTime);
          if not Result.MakeBoss(BossData,Length(Result.FBosses),Attacks,Bullets,Cancel) then begin Board.Free;
            Continue;
          end;
          if (Length(Result.FAttacks)+Length(Attacks)>20000) or (Length(Result.FBullets)+Length(Bullets)>80000) then begin Board.Free;
            Break;
          end;
          Result.FBoards.Add(Board);
          Board:=nil;
          N:=Length(Result.FBosses);
          SetLength(Result.FBosses,N+1);
          Result.FBosses[N]:=BossData;
          N:=Length(Result.FAttacks);
          SetLength(Result.FAttacks,N+Length(Attacks));
          for J:=0 to High(Attacks) do Result.FAttacks[N+J]:=Attacks[J];
          N:=Length(Result.FBullets);
          SetLength(Result.FBullets,N+Length(Bullets));
          for J:=0 to High(Bullets) do Result.FBullets[N+J]:=Bullets[J];
          Appear:=BossData.Kill+0.95;
          Ready:=BossData.Kill+1.85;
        except on E:EAbort do begin Board.Free;
            raise;
          end;
          on E:Exception do begin
            {$IFDEF BREAKOUT_TRACE}Writeln('Breakout stage rejected: ',E.Message);
            {$ENDIF}Board.Free;
          end;
        end;
      end;
      Last:=0;
      N:=0;
      for I:=0 to High(Result.FEvents) do if (Result.FEvents[I].Time>Ready+1E-5) and (Result.FEvents[I].Time<=Audio.SoundEnd) then begin Last:=Result.FEvents[I].Time;
        Inc(N);
      end;
      if Result.FBoards.Count=0 then begin
        Board:=Result.MakeBoard(0,0,Max(0.001,Max(Audio.SoundEnd,Audio.Duration)),Cancel,True);
        Result.FBoards.Add(Board);
      end else if (Last-Ready>=6) and (N>=4) then begin
        Board:=Result.MakeBoard(Appear,Ready,Audio.SoundEnd,Cancel,False);
        if Board<>nil then Result.FBoards.Add(Board);
      end;
      Result.Reindex;
      Result.Verify(Cancel);
    except Result.Free;
      Result:=nil;
      raise;
    end;
  end;
  procedure TBreakCampaign.Reindex;
  var
    I,J,N:Integer;
    Board:TBreakBoard;
  begin
    FCount:=0;
    FGoal:=0;
    FLaunch:=0;
    FBallEnd:=0;
    FReflections:=0;
    FAuxiliary:=0;
    FCatches:=0;
    FTrials:=0;
    SetLength(FOffsets,FBoards.Count);
    for I:=0 to FBoards.Count-1 do begin
      Board:=FBoards[I];
      FOffsets[I]:=FCount;
      Inc(FCount,Board.Plan.Count);
      Inc(FReflections,Board.Plan.SyncCount);
      Inc(FAuxiliary,Board.Plan.AuxiliaryCount);
      Inc(FCatches,Board.Plan.CatchCount);
      FTrials:=Max(FTrials,Board.Plan.Trials);
      if (I=0) and (Board.Plan.Count>0) then FLaunch:=Board.Ready+Board.Plan.LaunchTime;
      if Board.Plan.Count>0 then begin FGoal:=FEvents[Board.Sources[Board.Plan.BrickAt(Board.Plan.Count-1,Board.Plan.GoalTime).Source]].Time;
        FBallEnd:=Board.Ready+Board.Plan.BallEnd;
      end;
    end;
    SetLength(FExtras,0);
    N:=0;
    for I:=0 to High(FAttacks) do begin
      if FAttacks[I].Source<0 then Inc(N) else Inc(FReflections);
    end;
    SetLength(FExtras,N);
    J:=0;
    for I:=0 to High(FAttacks) do if FAttacks[I].Source<0 then begin FExtras[J]:=I;
      Inc(J);
    end;

    SetLength(FPrimary,Length(FAttacks)-Length(FExtras));
    J:=0;
    SetLength(FHits,Length(FAttacks));
    for I:=0 to High(FAttacks) do begin FHits[I]:=I;
      if FAttacks[I].Source>=0 then begin FPrimary[J]:=I;
        Inc(J);
      end;
    end;
    TArray.Sort<Integer>(FPrimary,TComparer<Integer>.Construct(function(const A,B:Integer):Integer begin Result:=BreakOrder(FAttacks[A].Path.Launch,FAttacks[B].Path.Launch);if Result=0 then Result:=BreakOrder(A,B);end));
    TArray.Sort<Integer>(FHits,TComparer<Integer>.Construct(function(const A,B:Integer):Integer begin Result:=BreakOrder(FAttacks[A].Path.Hit,FAttacks[B].Path.Hit);if Result=0 then Result:=BreakOrder(A,B);end));
    TArray.Sort<Integer>(FExtras,TComparer<Integer>.Construct(function(const A,B:Integer):Integer begin Result:=BreakOrder(FAttacks[A].Path.Launch,FAttacks[B].Path.Launch);if Result=0 then Result:=BreakOrder(A,B);end));
    SetLength(FNormalExtras,0);
    for I:=0 to FBoards.Count-1 do begin Board:=FBoards[I];
      N:=Length(FNormalExtras);
      SetLength(FNormalExtras,N+Board.Plan.ExtraCount);
      for J:=0 to Board.Plan.ExtraCount-1 do begin FNormalExtras[N+J].Board:=I;
        FNormalExtras[N+J].Index:=J;
        FNormalExtras[N+J].Launch:=Board.Ready+Board.Plan.ExtraLaunch(J);
      end;
    end;
    TArray.Sort<TBreakNormalExtra>(FNormalExtras,TComparer<TBreakNormalExtra>.Construct(function(const A,B:TBreakNormalExtra):Integer
    begin Result:=0;if A.Launch<B.Launch then Exit(-1);if A.Launch>B.Launch then Exit(1);if A.Board<B.Board then Exit(-1);if A.Board>B.Board then Exit(1);if A.Index<B.Index then Exit(-1);if A.Index>B.Index then Exit(1);end));
    TArray.Sort<TBreakBossBullet>(FBullets,TComparer<TBreakBossBullet>.Construct(function(const A,B:TBreakBossBullet):Integer
    begin Result:=BreakOrder(A.Motion.Launch,B.Motion.Launch);if Result=0 then Result:=BreakOrder(A.Motion.Velocity.X,B.Motion.Velocity.X);if Result=0 then Result:=BreakOrder(A.Motion.Velocity.Y,B.Motion.Velocity.Y);if Result=0 then Result:=BreakOrder(A.Motion.Finish,B.Motion.Finish);end));
    if Length(FBosses)>0 then if FBosses[High(FBosses)].Kill>FGoal then begin FGoal:=FBosses[High(FBosses)].Kill;
      FBallEnd:=FBosses[High(FBosses)].Finish;
    end;
    FExit:=FGoal+0.55;
    if FBoards.Count=Length(FBosses) then FExit:=Max(FGoal+0.85,FSoundEnd+0.12);
    FEnd:=FExit+1.1;
    if (FCount=0) and (Length(FBosses)=0) then begin FEnd:=FDuration;
      FExit:=FEnd;
      FBallEnd:=FEnd;
    end;
  end;
  function TBreakCampaign.FindBoard(Index:Integer):Integer;
  var
    A,B,M:Integer;
  begin
    if (Index<0) or (Index>=FCount) then raise ERangeError.Create('Campaign block index');
    A:=0;
    B:=Length(FOffsets);
    while A<B do begin M:=(A+B) div 2;
      if FOffsets[M]<=Index then A:=M+1 else B:=M;
    end;
    Result:=Max(0,A-1);
  end;
  function TBreakCampaign.BrickAt(Index:Integer;Time:Double):TBreakBlock;
  var
    I:Integer;
    Board:TBreakBoard;
  begin
    I:=FindBoard(Index);
    Board:=FBoards[I];
    Result:=Board.Plan.BrickAt(Index-FOffsets[I],Max(0.0,Time-Board.Ready));
    if Result.Source>=0 then begin Result.Source:=Board.Sources[Result.Source];
      Result.Time:=FEvents[Result.Source].Time;
    end else Result.Time:=Result.Time+Board.Ready;
    if (Time<Board.Ready) and (Board.Ready>Board.Appear) then begin Result.Top:=Result.Top-1.1*(1-Smooth((Time-Board.Appear)/(Board.Ready-Board.Appear)));
      Result.Bottom:=Result.Bottom-1.1*(1-Smooth((Time-Board.Appear)/(Board.Ready-Board.Appear)));
    end;
  end;
  function TBreakCampaign.BrickRow(Index:Integer):Integer;
  var
    I:Integer;
  begin I:=FindBoard(Index);
    Result:=FBoards[I].Plan.BrickRow(Index-FOffsets[I]);
  end;
  function TBreakCampaign.BlockVisible(Index:Integer;Time:Double):Boolean;
  var
    I:Integer;
  begin I:=FindBoard(Index);
    Result:=(Time>=FBoards[I].Appear) and FBoards[I].Plan.BrickVisible(Index-FOffsets[I],Max(0.0,Time-FBoards[I].Ready));
    if I<Length(FBosses) then Result:=Result and (Time<FBosses[I].Start);
  end;
  function TBreakCampaign.PaddleAt(Time:Double):Double;
  var
    I:Integer;
    BossData:TBreakBoss;
    Board:TBreakBoard;
    U:Double;
  begin
    Time:=EnsureRange(Time,0.0,FExit);
    Result:=BREAK_WIDTH/2;
    for I:=0 to High(FBosses) do begin BossData:=FBosses[I];
      if (Time>=BossData.Start) and (Time<=BossData.Finish) then Exit(KeyAt(BossData.Paddles,Time));
    end;
    for I:=0 to FBoards.Count-1 do begin Board:=FBoards[I];
      if (Time>=Board.Ready) and ((I>=Length(FBosses)) or (Time<FBosses[I].Start)) then Exit(Board.Plan.PaddleAt(Time-Board.Ready));
    end;
    for I:=0 to High(FBosses) do if Time>FBosses[I].Finish then begin
      Result:=KeyAt(FBosses[I].Paddles,FBosses[I].Finish);
      if I+1<FBoards.Count then begin Board:=FBoards[I+1];
        if Time<Board.Ready then begin U:=Smooth((Time-FBosses[I].Finish)/(Board.Ready-FBosses[I].Finish));
          Exit(Result+(Board.Plan.PaddleAt(0)-Result)*U);
        end;
      end;
    end;
  end;
  function TBreakCampaign.AttackAt(const Attack:TBreakAttack;Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
  var
    Path:TScoreExtraBall;
    U:Double;
  begin
    Path:=Attack.Path;
    P:=Path.A;
    Alpha:=0;
    Result:=False;
    if (Time<Path.Launch) or (Time>=Path.Catch+0.2) then Exit;
    Alpha:=1;
    if Attack.Source<0 then Alpha:=Min(1.0,(Time-Path.Launch)/0.05);
    if Time>=Path.Catch then begin U:=(Time-Path.Catch)/0.2;
      P:=BreakPoint(EnsureRange(PaddleAt(Time)+(Path.C.X-PaddleAt(Path.Catch))*(1-Smooth(U)),BREAK_RADIUS,BREAK_WIDTH-BREAK_RADIUS),BREAK_PADDLE_Y);
      if Attack.Source<0 then Alpha:=1-U;
    end else if Time<=Path.Hit then begin U:=(Time-Path.Launch)/(Path.Hit-Path.Launch);
      P:=BreakPoint(Path.A.X+(Path.B.X-Path.A.X)*U,Path.A.Y+(Path.B.Y-Path.A.Y)*U);
    end
    else begin U:=(Time-Path.Hit)/(Path.Catch-Path.Hit);
      P:=BreakPoint(Fold(Path.B.X+(Path.B.X-Path.A.X)*U),Path.B.Y+(BREAK_PADDLE_Y-Path.B.Y)*U);
    end;
    Result:=True;
  end;
  function TBreakCampaign.MainAt(Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
  var
    I,J:Integer;
    Board:TBreakBoard;
    T,U:Double;
  begin
    Time:=Max(0.0,Time);
    P:=BreakPoint(PaddleAt(Time),BREAK_PADDLE_Y);
    Alpha:=0;
    Result:=False;
    for I:=0 to High(FBosses) do if (Time>=FBosses[I].Start) and (Time<=FBosses[I].Finish) then begin
      for J:=Max(0,PrimaryBefore(Time-2.2)+1) to PrimaryBefore(Time) do if FAttacks[FPrimary[J]].Boss=I then if AttackAt(FAttacks[FPrimary[J]],Time,P,Alpha) then Exit(True);
      P:=BreakPoint(PaddleAt(Time),BREAK_PADDLE_Y);
      Alpha:=Smooth((Time-FBosses[I].Start)/0.25);
      Exit(True);
    end;
    for I:=0 to FBoards.Count-1 do begin
      Board:=FBoards[I];
      if (Time>=Board.Ready) and ((I>=Length(FBosses)) or (Time<FBosses[I].Start)) then begin
        if Board.Plan.Count=0 then Exit;
        T:=Time-Board.Ready;
        P:=Board.Plan.PositionAt(T);
        Alpha:=1;
        if T>=Board.Plan.GoalTime then Alpha:=EnsureRange(1-(T-Board.Plan.GoalTime)/Max(1E-6,Board.Plan.BallEnd-Board.Plan.GoalTime),0.0,1.0);
        Exit(Alpha>0);
      end;
    end;
    if Length(FBosses)>0 then begin
      Alpha:=1;
      P:=BreakPoint(PaddleAt(Time),BREAK_PADDLE_Y);
      for I:=1 to FBoards.Count-1 do if (Time>FBosses[I-1].Finish) and (Time<FBoards[I].Ready) then begin
        U:=Smooth((Time-FBosses[I-1].Finish)/(FBoards[I].Ready-FBosses[I-1].Finish));
        P.X:=P.X+(FBoards[I].Plan.PositionAt(0).X-FBoards[I].Plan.PaddleAt(0))*U;
      end;
      if Time>=FExit then begin U:=Smooth((Time-FExit)/1.1);
        P.X:=P.X+(0.8-P.X)*U;
        P.Y:=P.Y-1.05*U;
      end;
      Result:=True;
    end;
  end;
  function TBreakCampaign.ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Alpha:Double):Boolean;
  var
    N:TBreakNormalExtra;
  begin if Index<Length(FExtras) then Exit(AttackAt(FAttacks[FExtras[Index]],Time,P,Alpha));
    N:=FNormalExtras[Index-Length(FExtras)];
    Result:=FBoards[N.Board].Plan.ExtraAt(N.Index,Time-FBoards[N.Board].Ready,P,Alpha);
  end;
  function TBreakCampaign.HeldAt(Time:Double):Boolean;
  var
    I:Integer;
    P:TBreakPoint;
    Alpha:Double;
  begin
    for I:=Max(0,PrimaryBefore(Time-2.2)+1) to PrimaryBefore(Time) do if Time<FAttacks[FPrimary[I]].Path.Catch then Exit(False);
    for I:=0 to FBoards.Count-1 do if (Time>=FBoards[I].Ready) and ((I>=Length(FBosses)) or (Time<FBosses[I].Start)) then Exit(FBoards[I].Plan.HeldAt(Time-FBoards[I].Ready));
    Result:=MainAt(Time,P,Alpha);
  end;
  function TBreakCampaign.GetBossCount:Integer;
  begin Result:=Length(FBosses);
  end;
  function TBreakCampaign.GetExtraCount:Integer;
  begin Result:=Length(FExtras)+Length(FNormalExtras);
  end;
  function TBreakCampaign.GetBossExtraCount:Integer;
  begin Result:=Length(FExtras);
  end;
  function TBreakCampaign.NormalExtraBefore(Time:Double):Integer;
  var
    A,B,M:Integer;
  begin A:=0;
    B:=Length(FNormalExtras);
    while A<B do begin M:=(A+B) div 2;
      if FNormalExtras[M].Launch<=Time then A:=M+1 else B:=M;
    end;
    Result:=Length(FExtras)+A-1;
  end;
  function TBreakCampaign.RadiusAt(Time:Double):Double;
  var
    I:Integer;
    Board:TBreakBoard;
  begin Result:=BREAK_RADIUS;
    for I:=0 to FBoards.Count-1 do begin Board:=FBoards[I];
      if (Time>=Board.Ready) and (Time<=Board.Ready+Board.Plan.GoalTime) then Exit(Board.Plan.RadiusAt(Time-Board.Ready));
    end;
  end;
  function TBreakCampaign.GetBulletCount:Integer;
  begin Result:=Length(FBullets);
  end;
  function TBreakCampaign.Boss(Index:Integer):TBreakBoss;
  begin Result:=FBosses[Index];
  end;
  function TBreakCampaign.Bullet(Index:Integer):TBreakBossBullet;
  begin Result:=FBullets[Index];
  end;
  function TBreakCampaign.PrimaryBefore(Time:Double):Integer;
  var
    A,B,M:Integer;
  begin A:=0;
    B:=Length(FPrimary);
    while A<B do begin M:=(A+B) div 2;
      if FAttacks[FPrimary[M]].Path.Launch<=Time then A:=M+1 else B:=M;
    end;
    Result:=A-1;
  end;
  function TBreakCampaign.ExtraBefore(Time:Double):Integer;
  var
    A,B,M:Integer;
  begin A:=0;
    B:=Length(FExtras);
    while A<B do begin M:=(A+B) div 2;
      if FAttacks[FExtras[M]].Path.Launch<=Time then A:=M+1 else B:=M;
    end;
    Result:=A-1;
  end;
  function TBreakCampaign.HitBefore(Time:Double):Integer;
  var
    A,B,M:Integer;
  begin A:=0;
    B:=Length(FHits);
    while A<B do begin M:=(A+B) div 2;
      if FAttacks[FHits[M]].Path.Hit<=Time then A:=M+1 else B:=M;
    end;
    Result:=A-1;
  end;
  function TBreakCampaign.BulletBefore(Time:Double):Integer;
  var
    A,B,M:Integer;
  begin A:=0;
    B:=Length(FBullets);
    while A<B do begin M:=(A+B) div 2;
      if FBullets[M].Motion.Launch<=Time then A:=M+1 else B:=M;
    end;
    Result:=A-1;
  end;
  function TBreakCampaign.Hit(Index:Integer):TBreakAttack;
  begin Result:=FAttacks[FHits[Index]];
  end;

  function TBreakCampaign.HealthAt(Index:Integer;Time:Double):Double;
  var
    Damage:Integer;
  begin
    if Time>=FBosses[Index].Kill then Exit(0);
    Damage:=Max(0,HitBefore(Time)-HitBefore(FBosses[Index].Start));
    Result:=Max(0.0,(FBosses[Index].HP-Damage)/Max(1,FBosses[Index].HP));
  end;
  function TBreakCampaign.FlashAt(Index:Integer;Time:Double):Double;
  var
    A:TBreakAttack;
    I:Integer;
    Age:Double;
  begin Result:=0;
    for I:=Max(0,HitBefore(Time-0.10)+1) to HitBefore(Time) do begin A:=FAttacks[FHits[I]];
      if A.Boss<>Index then Continue;
      Age:=Time-A.Path.Hit;
      if (Age>=0) and (Age<0.10) then Result:=Max(Result,1-Age/0.10);
    end;
  end;
  function BreakBossContact(Index,Sample:Integer):TBreakPoint;
  begin
    // Bottom opaque hull pixels of the original 256x160 boss sprites: row 151/157.
    // These are body contacts, not a shield spanning the transparent sprite bounds.
    if Index mod 2=0 then Result:=BreakPoint(0.62+0.36*(112+2*EnsureRange(Sample,0,16))/256,0.12+0.152+BREAK_RADIUS)
    else Result:=BreakPoint(0.8,0.12+0.158+BREAK_RADIUS);
  end;
  function BreakBossRect(const Boss:TBreakBoss;Time:Double):TBreakBlock;
  var
    Y:Double;
  begin
    Y:=-0.22+0.42*Smooth((Time-Boss.Start)/1.2);
    Result:=Default(TBreakBlock);
    Result.Left:=0.62;
    Result.Right:=0.98;
    Result.Top:=Y-0.08;
    Result.Bottom:=Y+0.08;
    Result.Time:=Boss.Kill;
  end;
  destructor TBreakBoard.Destroy;
  begin Plan.Free;
    inherited;
  end;
  constructor TBreakCampaign.Create;
  begin inherited;
    FBoards:=TObjectList<TBreakBoard>.Create(True);
  end;
  destructor TBreakCampaign.Destroy;
  begin FBoards.Free;
    inherited;
  end;
  function TBreakCampaign.ChildAudio(Board:TBreakBoard):TRhythmAudio;
  var
    I,K:Integer;
  begin
    Result:=TRhythmAudio.Create;
    try
      Result.Duration:=Board.Cut-Board.Ready;
      Result.SoundEnd:=EnsureRange(FSoundEnd-Board.Ready,0.0,Result.Duration);
      SetLength(Result.Hits,Length(Board.Sources));
      for I:=0 to High(Board.Sources) do begin K:=Board.Sources[I];
        if (K<0) or (K>=Length(FEvents)) then raise Exception.Create('Invalid normal-stage source');
        Result.Hits[I].Time:=FEvents[K].Time-Board.Ready;
        Result.Hits[I].Strength:=FEvents[K].Strength;
      end;
    except Result.Free;
      raise;
    end;
  end;
  function TBreakCampaign.MakeBoard(Appear,Ready,Cut:Double;const Cancel:TFunc<Boolean>;AllowEmpty:Boolean;ClearWave:Boolean):TBreakBoard;
  var
    Sources:TList<Integer>;
    I:Integer;
    Audio:TRhythmAudio;
  begin
    Result:=nil;
    if Cut<=Ready then Exit;
    Sources:=TList<Integer>.Create;
    Audio:=nil;
    try
      for I:=0 to High(FEvents) do begin if Assigned(Cancel) and Cancel() then Abort;
        if (FEvents[I].Time>Ready+1E-5) and (FEvents[I].Time<=Cut) and (FEvents[I].Time<=FSoundEnd+1E-8) then Sources.Add(I);
      end;
      if (Sources.Count=0) and not AllowEmpty then Exit;
      Result:=TBreakBoard.Create;
      Result.Appear:=Appear;
      Result.Ready:=Ready;
      Result.Cut:=Cut;
      Result.Sources:=Sources.ToArray;
      try Audio:=ChildAudio(Result);
        Result.Plan:=TBreakScorePlan.Build(Audio,Cancel,False,FPaddleHalf);
        Result.Plan.Enhance(Audio,ClearWave,Cancel);
      except Result.Free;
        Result:=nil;
        raise;
      end;
    finally Audio.Free;
      Sources.Free;
    end;
  end;
  function SelectBoss(Audio:TRhythmAudio;Index:Integer;Ready:Double;out Boss:TBreakBoss):Boolean;
  var
    Cue:TRhythmBossCue;
    Prefix:TArray<Double>;
    I,K,First,Last:Integer;
    Peak,Mean,Quiet,Best,Drop,T,Start,Before,After,Span,Window,SlotLow,SlotHigh,Spacing:Double;
    function Energy(A,B:Double):Double;
    var
      L,H:Integer;
    begin L:=EnsureRange(Floor(A*100),0,Length(Audio.Envelope));
      H:=EnsureRange(Ceil(B*100),L,Length(Audio.Envelope));
      if H=L then Exit(0);
      Result:=(Prefix[H]-Prefix[L])/(H-L);
    end;
  begin
    Result:=False;
    Boss:=Default(TBreakBoss);
    if (Audio.SoundEnd<28) or (Length(Audio.Envelope)<100) then Exit;
    // Use exactly the Shooter candidate cadence. Only the stage feasibility is local.
    Spacing:=Audio.SoundEnd/Max(1,Audio.BossCount);
    SlotLow:=Max(0.0,Spacing*(Index+0.25));
    SlotHigh:=Min(Audio.SoundEnd,Spacing*(Index+1.25));
    Cue:=Audio.BossCue(Index);
    SetLength(Prefix,Length(Audio.Envelope)+1);
    Peak:=0;
    for I:=0 to High(Audio.Envelope) do begin Prefix[I+1]:=Prefix[I]+Audio.Envelope[I];
      Peak:=Max(Peak,Audio.Envelope[I]);
    end;
    Mean:=Prefix[High(Prefix)]/Length(Audio.Envelope);
    Best:=0;
    Quiet:=Cue.KillTime;
    Window:=0.35;
    if not Cue.QuietBoundary then Window:=Min(8.0,(Cue.KillTime-Cue.StartTime)*0.4);
    First:=Max(20,Ceil(Max(SlotLow,Max(Ready+12,Cue.KillTime-Window))*100));
    Last:=Min(Length(Audio.Envelope)-20,Floor(Min(SlotHigh,Cue.KillTime+Window)*100));
    for K:=First to Last do begin T:=K/100;
      Before:=Energy(T-0.2,T);
      After:=Energy(T,T+0.2);
      Drop:=Before-After;
      if (Before>=Max(Peak*0.2,Mean*0.85)) and (After<=Before*0.7) and (Drop>Best) then begin Best:=Drop;
        Quiet:=T;
      end;
    end;
    // A gradual quiet transition already accepted by the shared two-second detector
    // must not be rejected merely because it lacks a sharp 0.2-second drop.
    if (Best<=0) and Cue.QuietBoundary and (Cue.KillTime>=SlotLow) and (Cue.KillTime<=SlotHigh) then begin
      Best:=1;
      Quiet:=Cue.KillTime;
    end;
    if Best<=0 then begin
      // A known audible end is a quiet boundary too, but a flat/unknown song is not a peak.
      if (Index<>Audio.BossCount-1) or (Peak<Mean*1.15) or (Energy(Audio.SoundEnd-2,Audio.SoundEnd-0.15)<Max(Peak*0.2,Mean*0.8)) then Exit;
      Quiet:=Audio.SoundEnd;
    end;
    Boss.KillSource:=-1;
    for I:=0 to High(Audio.Hits) do if (Audio.Hits[I].Time>=Quiet-0.65) and (Audio.Hits[I].Time<=Quiet-0.015) and (Audio.Hits[I].Time<=Audio.SoundEnd) then Boss.KillSource:=I;
    if Boss.KillSource<0 then Exit;
    Boss.Kill:=Audio.Hits[Boss.KillSource].Time;
    // Work back from the immutable final accent. Include up to four seconds of build-up.
    Span:=EnsureRange(Boss.Kill-SlotLow,18.0,30.0);
    Start:=Max(Ready+6,Boss.Kill-Span);
    First:=Ceil(Start*10);
    Last:=Floor((Boss.Kill-1.2)*10);
    for K:=Last downto First do begin T:=K/10;
      if Energy(T,T+1.2)<Max(Peak*0.15,Mean*0.55) then begin Start:=Max(Start,T-4.0);
        Break;
      end;
    end;
    Boss.Start:=Start;
    Boss.Quiet:=Quiet;
    Boss.Finish:=Boss.Kill+0.75;
    Result:=(Boss.Start-Ready>=6) and (Boss.Kill-Boss.Start>=8) and (Boss.Kill-Boss.Start<=30.0+1E-8);
  end;
  function TBreakCampaign.MakeBoss(var Boss:TBreakBoss;Index:Integer;out Attacks:TArray<TBreakAttack>;out Bullets:TArray<TBreakBossBullet>;const Cancel:TFunc<Boolean>):Boolean;
  var
    List:TList<TBreakAttack>;
    Shots:TList<TBreakBossBullet>;
    A:TBreakAttack;
    B:TBreakBossBullet;
    I,J,K,VI,Sequence,N,Budget:Integer;
    Amplitude,ShieldY,StartX,Time,Interval,Flight,Old,Speed,D,Deadline,Angle,Progress,Hit,ExitTime,V,Level:Double;
    Found:Boolean;
    procedure Check;
    begin if Assigned(Cancel) and Cancel() then Abort;
    end;
    function Primary(Source:Integer;Limit:Double;out Attack:TBreakAttack):Boolean;
    var
      X,V,Iteration:Integer;
      H:TScoreEvent;
      P:TScoreExtraBall;
      F,Next,Velocity:Double;
    begin
      Result:=False;
      H:=FEvents[Source];
      for X:=0 to 16 do for V:=0 to 20 do begin
        Velocity:=1.8+V*0.06;
        P:=Default(TScoreExtraBall);
        P.B:=BreakPoint(0.64+X*0.02,0.294);
        if FBodyContacts then P.B:=BreakBossContact(Index,X);
        F:=0.4;
        for Iteration:=0 to 31 do begin Next:=Hypot(P.B.X-KeyAt(Boss.Paddles,H.Time-F),BREAK_PADDLE_Y-P.B.Y)/Velocity;
          F:=Next;
        end;
        P.Launch:=H.Time-F;
        P.Hit:=H.Time;
        P.Catch:=H.Time+F;
        P.A:=BreakPoint(KeyAt(Boss.Paddles,P.Launch),BREAK_PADDLE_Y);
        P.C:=BreakPoint(Fold(2*P.B.X-P.A.X),BREAK_PADDLE_Y);
        if (P.Launch<Boss.Start+1.25) or (P.Catch+0.2>Limit) or (Abs(P.C.X-KeyAt(Boss.Paddles,P.Catch))>FPaddleHalf-0.006) then Continue;
        P.Target:=Index;
        P.Item:=-1;
        Attack.Path:=P;
        Attack.Boss:=Index;
        Attack.Source:=Source;
        Exit(True);
      end;
    end;
  begin
    Result:=False;
    Attacks:=nil;
    Bullets:=nil;
    List:=TList<TBreakAttack>.Create;
    Shots:=TList<TBreakBossBullet>.Create;
    try
      Amplitude:=0.18;
      ShieldY:=BREAK_PADDLE_Y;
      if FBodyContacts then begin if Index mod 2=0 then Amplitude:=0.06 else Amplitude:=0.03;
        ShieldY:=BREAK_PADDLE_Y+BREAK_RADIUS-0.008;
      end;
      StartX:=Boss.Paddles[0].Value;
      N:=Ceil((Boss.Finish-Boss.Start)/0.2);
      SetLength(Boss.Paddles,N+1);
      for I:=0 to N do begin Time:=Min(Boss.Finish,Boss.Start+I*0.2);
        Boss.Paddles[I].Time:=Time;
        Boss.Paddles[I].Value:=StartX+(0.8+Amplitude*Sin((Time-Boss.Start)*1.3+Index*0.7)-StartX)*Smooth((Time-Boss.Start)/1.0);
      end;
      Deadline:=Boss.Finish;
      for I:=Boss.KillSource downto 0 do begin Check;
        if FEvents[I].Time<Boss.Start+1.6 then Break;
        if Primary(I,Deadline,A) then begin List.Add(A);
          Deadline:=A.Path.Launch-0.2;
        end else if I=Boss.KillSource then Exit;
      end;
      if List.Count=0 then Exit;
      Budget:=Min(1024,Max(64,16000 div Max(1,FCandidateCount)));
      Interval:=Max(0.018,(Boss.Kill-Boss.Start-1.5)/Budget);
      Time:=Boss.Start+1.4;
      Sequence:=0;
      K:=0;
      while (Time<Boss.Kill-0.3) and (K<Budget) do begin
        Check;
        Found:=False;
        for J:=0 to 16 do begin
          A:=Default(TBreakAttack);
          A.Source:=-1;
          A.Boss:=Index;
          A.Path.Target:=Index;
          A.Path.Item:=-1;
          A.Path.Launch:=Time;
          A.Path.A:=BreakPoint(KeyAt(Boss.Paddles,Time),BREAK_PADDLE_Y);
          A.Path.B:=BreakPoint(0.64+((Sequence*7+J*3) mod 17)*0.02,0.294);
          if FBodyContacts then A.Path.B:=BreakBossContact(Index,(Sequence*7+J*3) mod 17);
          D:=Hypot(A.Path.B.X-A.Path.A.X,A.Path.B.Y-A.Path.A.Y);
          for VI:=0 to 6 do begin
            Speed:=2.0+VI*0.1;
            Flight:=D/Speed;
            A.Path.Hit:=Time+Flight;
            A.Path.Catch:=Time+2*Flight;
            A.Path.C:=BreakPoint(Fold(2*A.Path.B.X-A.Path.A.X),BREAK_PADDLE_Y);
            if (A.Path.Hit>Boss.Kill-0.12) or (A.Path.Catch+0.2>Boss.Finish) or (Abs(A.Path.C.X-KeyAt(Boss.Paddles,A.Path.Catch))>FPaddleHalf-0.006) then Continue;
            List.Add(A);
            Inc(K);
            Found:=True;
            Break;
          end;
          if Found then Break;
        end;
        Time:=Time+Interval;
        Inc(Sequence);
      end;
      if K<24 then Exit;
      Boss.HP:=List.Count;
      Attacks:=List.ToArray;
      Time:=Boss.Start+1.4;
      Sequence:=0;
      while Time<Boss.Kill-0.15 do begin
        Check;
        Progress:=(Time-Boss.Start)/(Boss.Kill-Boss.Start);
        N:=48+(Index mod 4)*8;
        for J:=0 to N-1 do begin
          B:=Default(TBreakBossBullet);
          B.Motion.Launch:=Time;
          B.Motion.Boss:=Index;
          B.Motion.Pattern:=TRhythmBarragePattern(Index mod 4);
          B.Motion.Origin.X:=0.8;
          B.Motion.Origin.Y:=0.28;
          Level:=0.35+0.65*Progress;
          B.Motion.Intensity:=Level;
          case B.Motion.Pattern of
            bpPetals:begin Angle:=J*2*Pi/N+Sequence*0.13;
              Speed:=0.27+0.18*Level+0.06*Sqr(Sin(Angle*5));
            end;
            bpSpiral:begin Angle:=J*2*Pi/N+Sequence*0.43;
              Speed:=0.30+Level*0.22+(J mod 3)*0.025;
            end;
            bpFans:begin Angle:=Pi/2+0.6*Sin(Sequence*0.27)+(J/(N-1)-0.5)*2.2;
              Speed:=0.30+Level*0.28;
            end;
            else Angle:=Pi/2+(2*(J mod 2)-1)*0.55+0.20*Sin(Sequence*0.21)+((J div 2)-(N div 4))*0.015;
            Speed:=0.33+Level*0.25;
          end;
          B.Motion.Velocity.X:=Cos(Angle)*Speed;
          B.Motion.Velocity.Y:=Sin(Angle)*Speed;
          ExitTime:=Min(Time+3.6,Boss.Kill+0.35);
          V:=B.Motion.Velocity.X;
          if V>1E-9 then ExitTime:=Min(ExitTime,Time+(1.63-B.Motion.Origin.X)/V) else if V< -1E-9 then ExitTime:=Min(ExitTime,Time+(-0.03-B.Motion.Origin.X)/V);
          V:=B.Motion.Velocity.Y;
          if V>1E-9 then ExitTime:=Min(ExitTime,Time+(1.03-B.Motion.Origin.Y)/V) else if V< -1E-9 then ExitTime:=Min(ExitTime,Time+(-0.03-B.Motion.Origin.Y)/V);
          if B.Motion.Velocity.Y>1E-9 then begin
            Hit:=Time+(ShieldY-B.Motion.Origin.Y)/B.Motion.Velocity.Y;
            Old:=B.Motion.Origin.X+B.Motion.Velocity.X*(Hit-Time);
            if (Hit<ExitTime) and (Abs(Old-KeyAt(Boss.Paddles,Hit))<=FPaddleHalf+0.008) then begin ExitTime:=Hit;
              B.Shield:=True;
            end;
          end;
          B.Motion.Finish:=ExitTime;
          Shots.Add(B);
        end;
        Time:=Time+Max(0.30,(Boss.Kill-Boss.Start)*N*Max(1,FCandidateCount)/72000);
        Inc(Sequence);
      end;
      Bullets:=Shots.ToArray;
      Result:=True;
    finally List.Free;
      Shots.Free;
    end;
  end;
  procedure TBreakCampaign.Verify(const Cancel:TFunc<Boolean>);
  var
    I,J,K,S:Integer;
    Board:TBreakBoard;
    BossData:TBreakBoss;
    A,Other:TBreakAttack;
    BulletData:TBreakBossBullet;
    Counts,Finals,Extras:TArray<Integer>;
    Used:TDictionary<Integer,Boolean>;
    Audio:TRhythmAudio;
    Data:TJSONObject;
    Nodes:TJSONArray;
    Node:TJSONObject;
    R:TBreakBlock;
    P:RhythmMotion.TRhythmPoint;
    Aim:TBreakPoint;
    T,D,Speed,X,ShieldY:Double;
    procedure Need(Value:Boolean;const Msg:string);
    begin if not Value then raise Exception.Create('Breakout boss stages: '+Msg);
    end;
    procedure Check;
    begin if Assigned(Cancel) and Cancel() then Abort;
    end;
    procedure Accent(Index:Integer;Time:Double);
    begin Need((Index>=0) and (Index<Length(FEvents)),'source index');
      Need(Near(FEvents[Index].Time,Time),'changed accent time');
      Need(not Used.ContainsKey(Index),'accent reused');
      Used.Add(Index,True);
    end;
  begin
    Need((FBossFrequency>=0) and (FBossFrequency<=100) and ((FBossFrequency<>0) or ((Length(FBosses)=0) and (FCandidateCount=0))),'boss frequency');
    Need((FCandidateCount>=Length(FBosses)) and (FCandidateCount<=1024),'candidate count');
    Need(Finite(FPaddleHalf) and ((FPaddleHalf=BREAK_PADDLE_HALF) or (FPaddleHalf=BREAK_PADDLE_HALF_V6) or (FPaddleHalf=BREAK_PADDLE_HALF_NEW)),'paddle width');
    Need(Finite(FDuration) and Finite(FSoundEnd) and (FDuration>0) and (FSoundEnd>=0) and (FSoundEnd<=FDuration),'audio');
    Need((Length(FEvents)<=100000) and (FBoards.Count>0) and (FBoards.Count<=65) and (Length(FBosses)<=64) and (FCount<=12000) and (Length(FAttacks)<=20000) and (Length(FBullets)<=80000),'limits');
    Need((FBoards.Count=Length(FBosses)) or (FBoards.Count=Length(FBosses)+1),'stage order');
    for I:=0 to High(FEvents) do begin
      Need((FEvents[I].Source=I) and Finite(FEvents[I].Time) and Finite(FEvents[I].Strength) and (FEvents[I].Time>=0) and
      (FEvents[I].Time<=FDuration+0.011) and (FEvents[I].Strength>=0) and (FEvents[I].Strength<=1),'events');
      if I>0 then Need(FEvents[I].Time>=FEvents[I-1].Time,'event order');
    end;
    ShieldY:=BREAK_PADDLE_Y;
    if FBodyContacts then ShieldY:=BREAK_PADDLE_Y+BREAK_RADIUS-0.008;
    Used:=TDictionary<Integer,Boolean>.Create;
    try
      for I:=0 to FBoards.Count-1 do begin
        Check;
        Board:=FBoards[I];
        Need(Finite(Board.Appear) and Finite(Board.Ready) and Finite(Board.Cut) and (Board.Cut>Board.Ready) and (Board.Cut<=FDuration+1E-8),'normal interval');
        Need(Board.Plan.PaddleHalf=FPaddleHalf,'normal paddle width');
        Need((Board.Plan.ItemCount=0) and (Board.Plan.ExtraCount<=24) and (Board.Plan.Count=Board.Plan.BlockCount),'old item show in boss stages');
        if I=0 then Need((Board.Appear=0) and (Board.Ready=0),'initial board')
        else Need(Near(Board.Appear,FBosses[I-1].Kill+0.95) and Near(Board.Ready,FBosses[I-1].Kill+1.85),'new board descent');
        if I<Length(FBosses) then Need((Board.Plan.Count>=2) and Near(Board.Cut,FBosses[I].Start-0.65) and (Board.Ready+Board.Plan.GoalTime<=FBosses[I].Start-0.65+1E-8),'clear before boss');
        for J:=0 to High(Board.Sources) do begin
          S:=Board.Sources[J];
          Need((S>=0) and (S<Length(FEvents)),'normal source');
          if J>0 then Need(S>Board.Sources[J-1],'normal sources order');
          Need((FEvents[S].Time>Board.Ready+1E-5) and (FEvents[S].Time<=Board.Cut+1E-8) and (FEvents[S].Time<=FSoundEnd+1E-8),'normal source interval');
        end;
        Audio:=ChildAudio(Board);
        try Data:=Board.Plan.ExportData(Audio);
        finally Audio.Free;
        end;
        try
          Nodes:=Data.GetValue<TJSONArray>('events');
          for J:=0 to Nodes.Count-1 do begin Node:=TJSONObject(Nodes.Items[J]);
            K:=Node.GetValue<Integer>('source');
            Need((K>=0) and (K<Length(Board.Sources)),'normal candidate mapping');
            Need(Near(Node.GetValue<Double>('time')+Board.Ready,FEvents[Board.Sources[K]].Time) and (Abs(Node.GetValue<Double>('strength')-FEvents[Board.Sources[K]].Strength)<1E-12),'normal original candidate');
          end;
          Nodes:=Data.GetValue<TJSONArray>('nodes');
          for J:=0 to Nodes.Count-1 do begin Node:=TJSONObject(Nodes.Items[J]);
            K:=Node.GetValue<Integer>('source',-1);
            if (K>=0) and (Node.GetValue<Integer>('kind') in [Ord(snBlock),Ord(snWall),Ord(snPaddle),Ord(snCorner)]) then begin Need(K<Length(Board.Sources),'normal reflection source');
              Accent(Board.Sources[K],Node.GetValue<Double>('time')+Board.Ready);
            end;
          end;
        finally Data.Free;
        end;
      end;
      SetLength(Counts,Length(FBosses));
      SetLength(Finals,Length(FBosses));
      SetLength(Extras,Length(FBosses));
      for I:=0 to High(FBosses) do begin
        Check;
        BossData:=FBosses[I];
        Need(Finite(BossData.Start) and Finite(BossData.Quiet) and Finite(BossData.Kill) and Finite(BossData.Finish),'boss numbers');
        Need((BossData.Start-FBoards[I].Ready>=6-1E-8) and (BossData.Kill-BossData.Start>=6) and (BossData.Kill-BossData.Start<=30.0+1E-8) and
        (BossData.Quiet-BossData.Kill>=0.015-1E-8) and (BossData.Quiet-BossData.Kill<=0.65+1E-8) and (BossData.Quiet<=FSoundEnd+0.5) and Near(BossData.Finish,BossData.Kill+0.75),'boss boundary');
        Need((BossData.KillSource>=0) and (BossData.KillSource<Length(FEvents)),'kill source');
        Need(BossData.Kill=FEvents[BossData.KillSource].Time,'kill cue');
        Need((Length(BossData.Paddles)>=2) and (Length(BossData.Paddles)<=155) and Near(BossData.Paddles[0].Time,BossData.Start) and Near(BossData.Paddles[High(BossData.Paddles)].Time,BossData.Finish),'boss paddle keys');
        Need(Near(BossData.Paddles[0].Value,FBoards[I].Plan.PaddleAt(FBoards[I].Plan.EndTime)),'boss paddle entry');
        for J:=0 to High(BossData.Paddles) do begin
          Need(Finite(BossData.Paddles[J].Time) and Finite(BossData.Paddles[J].Value) and (BossData.Paddles[J].Value>=FPaddleHalf) and (BossData.Paddles[J].Value<=BREAK_WIDTH-FPaddleHalf),'boss paddle bounds');
          if J>0 then begin D:=BossData.Paddles[J].Time-BossData.Paddles[J-1].Time;
            Need(D>1E-9,'paddle key order');
            Need(1.5*Abs(BossData.Paddles[J].Value-BossData.Paddles[J-1].Value)/D<=2.1,'paddle speed');
          end;
        end;
        for J:=0 to FCount-1 do if BlockVisible(J,BossData.Start) then Need(BrickAt(J,BossData.Start).Time<=BossData.Start,'live block in boss interval');
      end;
      for I:=0 to High(FAttacks) do begin
        Check;
        A:=FAttacks[I];
        Need((A.Boss>=0) and (A.Boss<Length(FBosses)) and (A.Path.Target=A.Boss) and (A.Path.Item=-1),'attack owner');
        BossData:=FBosses[A.Boss];
        Inc(Counts[A.Boss]);
        Need(Finite(A.Path.Launch) and Finite(A.Path.Hit) and Finite(A.Path.Catch) and Finite(A.Path.A.X) and Finite(A.Path.A.Y) and Finite(A.Path.B.X) and Finite(A.Path.B.Y) and Finite(A.Path.C.X) and Finite(A.Path.C.Y),'attack numbers');
        D:=A.Path.Hit-A.Path.Launch;
        Need((D>1E-9) and Near(A.Path.Catch-A.Path.Hit,D) and (A.Path.Launch>=BossData.Start+1.25) and (A.Path.Hit<=BossData.Kill) and (A.Path.Catch+0.2<=BossData.Finish+1E-8),'attack time');
        Speed:=Hypot(A.Path.B.X-A.Path.A.X,A.Path.B.Y-A.Path.A.Y)/D;
        Need((Speed>=1.8-1E-7) and (Speed<=3.0+1E-7),'friendly speed');
        R:=BreakBossRect(BossData,A.Path.Hit);
        if FBodyContacts then begin
          Aim:=BreakBossContact(A.Boss,0);
          Need(Near(A.Path.B.Y,Aim.Y),'body contact height');
          if A.Boss mod 2=0 then Need((A.Path.B.X>=Aim.X-1E-8) and (A.Path.B.X<=BreakBossContact(A.Boss,16).X+1E-8),'hull face')
          else Need(Near(A.Path.B.X,Aim.X),'keel contact');
        end else Need(Near(A.Path.B.Y,R.Bottom+BREAK_RADIUS),'legacy boss contact');
        Need((A.Path.Hit>=BossData.Start+1.2) and (A.Path.B.X>=R.Left) and (A.Path.B.X<=R.Right),'boss contact');
        Need(Near(A.Path.A.X,KeyAt(BossData.Paddles,A.Path.Launch)) and Near(A.Path.A.Y,BREAK_PADDLE_Y) and Near(A.Path.C.Y,BREAK_PADDLE_Y) and
        Near(A.Path.C.X,Fold(2*A.Path.B.X-A.Path.A.X)) and (Abs(A.Path.C.X-KeyAt(BossData.Paddles,A.Path.Catch))<=FPaddleHalf-0.006+1E-8),'friendly reflection/return');
        if A.Source>=0 then begin
          Accent(A.Source,A.Path.Hit);
          if A.Path.Hit=BossData.Kill then begin Need(A.Source=BossData.KillSource,'last blow');
            Inc(Finals[A.Boss]);
          end;
          for J:=0 to I-1 do begin Other:=FAttacks[J];
            if (Other.Source>=0) and (Other.Boss=A.Boss) then Need((A.Path.Launch>=Other.Path.Catch+0.2-1E-8) or (Other.Path.Launch>=A.Path.Catch+0.2-1E-8),'two main balls');
          end;
        end else begin Need((A.Source=-1) and (A.Path.Hit<=BossData.Kill-0.12+1E-8),'extra after boss death');
          Inc(Extras[A.Boss]);
        end;
      end;
      for I:=0 to High(FBosses) do Need((Counts[I]=FBosses[I].HP) and (Finals[I]=1) and (Extras[I]>=24) and (Extras[I]<=1024) and (HealthAt(I,FBosses[I].Kill-1E-6)>0) and (HealthAt(I,FBosses[I].Kill)=0),'boss HP timing');
      for BulletData in FBullets do begin
        Check;
        I:=BulletData.Motion.Boss;
        Need((I>=0) and (I<Length(FBosses)),'bullet boss');
        BossData:=FBosses[I];
        Need(Finite(BulletData.Motion.Launch) and Finite(BulletData.Motion.Finish) and Finite(BulletData.Motion.Origin.X) and Finite(BulletData.Motion.Origin.Y) and Finite(BulletData.Motion.Velocity.X) and Finite(BulletData.Motion.Velocity.Y) and Finite(BulletData.Motion.Intensity),'bullet numbers');
        Speed:=Hypot(BulletData.Motion.Velocity.X,BulletData.Motion.Velocity.Y);
        Need((BulletData.Motion.Launch>=BossData.Start+1.4-1E-8) and (BulletData.Motion.Launch<BossData.Kill-0.15+1E-8) and (BulletData.Motion.Finish>BulletData.Motion.Launch) and
        (BulletData.Motion.Finish<=BossData.Kill+0.35+1E-8) and (BulletData.Motion.Finish<=BulletData.Motion.Launch+3.6+1E-8) and Near(BulletData.Motion.Origin.X,0.8) and Near(BulletData.Motion.Origin.Y,0.28) and
        (Ord(BulletData.Motion.Pattern)=I mod 4) and (Speed>=0.2) and (Speed<=0.8) and (BulletData.Motion.Intensity>=0) and (BulletData.Motion.Intensity<=1),'barrage');
        if BulletData.Motion.Velocity.Y>1E-9 then begin
          T:=BulletData.Motion.Launch+(ShieldY-BulletData.Motion.Origin.Y)/BulletData.Motion.Velocity.Y;
          X:=BulletData.Motion.Origin.X+BulletData.Motion.Velocity.X*(T-BulletData.Motion.Launch);
          if BulletData.Shield then Need(Near(T,BulletData.Motion.Finish) and (Abs(X-KeyAt(BossData.Paddles,T))<=FPaddleHalf+0.008+1E-8),'shield contact')
          else if (T>BulletData.Motion.Launch) and (T<BulletData.Motion.Finish-1E-8) then Need(Abs(X-KeyAt(BossData.Paddles,T))>FPaddleHalf+0.008,'unreported shield');
        end else Need(not BulletData.Shield,'shield direction');
        P:=EnemyBulletAt(BulletData.Motion,BulletData.Motion.Finish);
        Need((P.X>=-0.031) and (P.X<=1.631) and (P.Y>=-0.031) and (P.Y<=1.031),'bullet boundary');
      end;
      Need(Finite(FGoal) and Finite(FLaunch) and Finite(FExit) and Finite(FEnd) and (((FCount=0) and (Length(FBosses)=0)) or (FExit>=FGoal+0.55-1E-8)) and (FEnd>=FExit),'finish');
    finally Used.Free;
    end;
  end;
  procedure TBreakCampaign.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
  var
    Root,J,Score:TJSONObject;
    Items,Values:TJSONArray;
    I:Integer;
    E:TScoreEvent;
    Board:TBreakBoard;
    BossData:TBreakBoss;
    A:TBreakAttack;
    B:TBreakBossBullet;
    Key:TScoreKey;
    Child:TRhythmAudio;
  begin
    if not (Ref.Version in [5,6,7,8,9,10]) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsBreakout,Ref.Variant) then raise Exception.Create('Invalid boss-stage reference');
    if ((Ref.Version=5) and (FPaddleHalf<>BREAK_PADDLE_HALF)) or ((Ref.Version=6) and (FPaddleHalf<>BREAK_PADDLE_HALF_V6)) or ((Ref.Version in [7,8,9,10]) and (FPaddleHalf<>BREAK_PADDLE_HALF_NEW)) then raise Exception.Create('Campaign version/paddle mismatch');
    if (Ref.Version>=8) and (FBossFrequency<>BossFrequencyFromVariant(Ref.Variant)) then raise Exception.Create('Campaign frequency mismatch');
    Root:=TJSONObject.Create;
    try
      Root.AddPair('schema',TJSONNumber.Create(1));
      Root.AddPair('style','breakout');
      Root.AddPair('version',TJSONNumber.Create(Ref.Version));
      Root.AddPair('layout','boss-stages-v1');
      Root.AddPair('bossFrequency',TJSONNumber.Create(FBossFrequency));
      Root.AddPair('paddleHalf',TJSONNumber.Create(FPaddleHalf));
      Root.AddPair('bossCandidates',TJSONNumber.Create(FCandidateCount));
      if Ref.Version=6 then Root.AddPair('bossPolicy','reverse-long-v2');
      if Ref.Version=7 then Root.AddPair('bossPolicy','periodic-body-v3');
      if Ref.Version=8 then Root.AddPair('bossPolicy','controlled-body-v4');
      if Ref.Version=9 then Root.AddPair('bossPolicy','impact-density-v5');
      if Ref.Version=10 then Root.AddPair('bossPolicy','rush-pierce-v6');
      Root.AddPair('key',Ref.Key);
      Root.AddPair('source',Ref.SourceKey);
      Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
      Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
      AddPreparedAudio(Root,Audio);
      Root.AddPair('goal',TJSONNumber.Create(FGoal));
      Root.AddPair('launch',TJSONNumber.Create(FLaunch));
      Root.AddPair('exit',TJSONNumber.Create(FExit));
      Root.AddPair('end',TJSONNumber.Create(FEnd));
      Items:=TJSONArray.Create;
      Root.AddPair('events',Items);
      for E in FEvents do begin J:=TJSONObject.Create;
        Items.AddElement(J);
        J.AddPair('time',TJSONNumber.Create(E.Time));
        J.AddPair('strength',TJSONNumber.Create(E.Strength));
        J.AddPair('source',TJSONNumber.Create(E.Source));
      end;
      Items:=TJSONArray.Create;
      Root.AddPair('boards',Items);
      for Board in FBoards do begin
        J:=TJSONObject.Create;
        Items.AddElement(J);
        J.AddPair('appear',TJSONNumber.Create(Board.Appear));
        J.AddPair('ready',TJSONNumber.Create(Board.Ready));
        J.AddPair('cut',TJSONNumber.Create(Board.Cut));
        Values:=TJSONArray.Create;
        J.AddPair('sources',Values);
        for I in Board.Sources do Values.Add(I);
        Child:=ChildAudio(Board);
        try Score:=Board.Plan.ExportData(Child);
        finally Child.Free;
        end;
        if ((Ref.Version>=10)<>(Score.GetValue<Integer>('version')=5)) then begin Score.Free;
          raise Exception.Create('Campaign action version mismatch');
        end;
        J.AddPair('score',Score);
      end;
      Items:=TJSONArray.Create;
      Root.AddPair('bosses',Items);
      for BossData in FBosses do begin
        J:=TJSONObject.Create;
        Items.AddElement(J);
        J.AddPair('start',TJSONNumber.Create(BossData.Start));
        J.AddPair('quiet',TJSONNumber.Create(BossData.Quiet));
        J.AddPair('kill',TJSONNumber.Create(BossData.Kill));
        J.AddPair('finish',TJSONNumber.Create(BossData.Finish));
        J.AddPair('killSource',TJSONNumber.Create(BossData.KillSource));
        J.AddPair('hp',TJSONNumber.Create(BossData.HP));
        Values:=TJSONArray.Create;
        J.AddPair('paddles',Values);
        for Key in BossData.Paddles do begin Score:=TJSONObject.Create;
          Values.AddElement(Score);
          Score.AddPair('time',TJSONNumber.Create(Key.Time));
          Score.AddPair('value',TJSONNumber.Create(Key.Value));
        end;
      end;
      Items:=TJSONArray.Create;
      Root.AddPair('attacks',Items);
      for A in FAttacks do begin
        J:=TJSONObject.Create;
        Items.AddElement(J);
        J.AddPair('boss',TJSONNumber.Create(A.Boss));
        J.AddPair('source',TJSONNumber.Create(A.Source));
        J.AddPair('launch',TJSONNumber.Create(A.Path.Launch));
        J.AddPair('hit',TJSONNumber.Create(A.Path.Hit));
        J.AddPair('catch',TJSONNumber.Create(A.Path.Catch));
        J.AddPair('ax',TJSONNumber.Create(A.Path.A.X));
        J.AddPair('ay',TJSONNumber.Create(A.Path.A.Y));
        J.AddPair('bx',TJSONNumber.Create(A.Path.B.X));
        J.AddPair('by',TJSONNumber.Create(A.Path.B.Y));
        J.AddPair('cx',TJSONNumber.Create(A.Path.C.X));
        J.AddPair('cy',TJSONNumber.Create(A.Path.C.Y));
      end;
      Items:=TJSONArray.Create;
      Root.AddPair('bullets',Items);
      for B in FBullets do begin
        J:=TJSONObject.Create;
        Items.AddElement(J);
        J.AddPair('boss',TJSONNumber.Create(B.Motion.Boss));
        J.AddPair('pattern',TJSONNumber.Create(Ord(B.Motion.Pattern)));
        J.AddPair('intensity',TJSONNumber.Create(B.Motion.Intensity));
        J.AddPair('launch',TJSONNumber.Create(B.Motion.Launch));
        J.AddPair('finish',TJSONNumber.Create(B.Motion.Finish));
        J.AddPair('ox',TJSONNumber.Create(B.Motion.Origin.X));
        J.AddPair('oy',TJSONNumber.Create(B.Motion.Origin.Y));
        J.AddPair('vx',TJSONNumber.Create(B.Motion.Velocity.X));
        J.AddPair('vy',TJSONNumber.Create(B.Motion.Velocity.Y));
        J.AddPair('shield',TJSONBool.Create(B.Shield));
      end;
      WritePreparedData(Root,Ref);
    finally Root.Free;
    end;
  end;
  class function TBreakCampaign.Load(Root:TJSONObject;Audio:TRhythmAudio):TBreakCampaign;
  var
    Items,Values:TJSONArray;
    J,Data,Info:TJSONObject;
    I,K,N:Integer;
    Board:TBreakBoard;
    Child:TRhythmAudio;
    function ArrayOf(const Name:string;Limit:Integer):TJSONArray;
    begin Result:=Root.GetValue<TJSONArray>(Name);
      if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Invalid campaign array '+Name);
    end;
    function ObjectAt(A:TJSONArray;Index:Integer):TJSONObject;
    begin if not (A.Items[Index] is TJSONObject) then raise Exception.Create('Invalid campaign object');
      Result:=TJSONObject(A.Items[Index]);
    end;
  begin
    Result:=nil;
    if (Audio=nil) or (Root.GetValue<string>('layout','')<>'boss-stages-v1') then raise Exception.Create('Invalid boss-stage layout');
    Info:=Root.GetValue<TJSONObject>('audio');
    if (Info=nil) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or
    not Near(Info.GetValue<Double>('duration'),Audio.Duration) or not Near(Info.GetValue<Double>('soundEnd'),Audio.SoundEnd) then raise Exception.Create('Campaign audio identity mismatch');
    Result:=TBreakCampaign.Create;
    try
      Result.FPaddleHalf:=BREAK_PADDLE_HALF;
      Result.FBossFrequency:=100;
      if Root.GetValue<Integer>('version',0)=6 then begin
        if Root.GetValue<string>('bossPolicy','')<>'reverse-long-v2' then raise Exception.Create('Invalid boss-stage policy');
        Result.FPaddleHalf:=Root.GetValue<Double>('paddleHalf');
        if Result.FPaddleHalf<>BREAK_PADDLE_HALF_V6 then raise Exception.Create('Invalid version-six paddle');
      end;
      if Root.GetValue<Integer>('version',0)=7 then begin
        if Root.GetValue<string>('bossPolicy','')<>'periodic-body-v3' then raise Exception.Create('Invalid body-contact policy');
        Result.FPaddleHalf:=Root.GetValue<Double>('paddleHalf');
        Result.FBodyContacts:=True;
        if Result.FPaddleHalf<>BREAK_PADDLE_HALF_NEW then raise Exception.Create('Invalid body-contact paddle');
      end;
      if Root.GetValue<Integer>('version',0) in [8,9,10] then begin
        if ((Root.GetValue<Integer>('version')=8) and (Root.GetValue<string>('bossPolicy','')<>'controlled-body-v4')) or ((Root.GetValue<Integer>('version')=9) and (Root.GetValue<string>('bossPolicy','')<>'impact-density-v5')) or ((Root.GetValue<Integer>('version')=10) and (Root.GetValue<string>('bossPolicy','')<>'rush-pierce-v6')) then raise Exception.Create('Invalid frequency policy');
        Result.FPaddleHalf:=Root.GetValue<Double>('paddleHalf');
        Result.FBodyContacts:=True;
        Result.FBossFrequency:=Root.GetValue<Integer>('bossFrequency',-1);
        if Result.FPaddleHalf<>BREAK_PADDLE_HALF_NEW then raise Exception.Create('Invalid controlled paddle');
      end;
      Result.FDuration:=Audio.Duration;
      Result.FSoundEnd:=Audio.SoundEnd;
      Items:=ArrayOf('events',100000);
      if Items.Count<>Length(Audio.Hits) then raise Exception.Create('Campaign source count');
      SetLength(Result.FEvents,Items.Count);
      for I:=0 to Items.Count-1 do begin J:=ObjectAt(Items,I);
        Result.FEvents[I].Time:=J.GetValue<Double>('time');
        Result.FEvents[I].Strength:=J.GetValue<Double>('strength');
        Result.FEvents[I].Source:=J.GetValue<Integer>('source',-1);
      end;
      Items:=ArrayOf('boards',65);
      for I:=0 to Items.Count-1 do begin
        J:=ObjectAt(Items,I);
        Board:=TBreakBoard.Create;
        Result.FBoards.Add(Board);
        Board.Appear:=J.GetValue<Double>('appear');
        Board.Ready:=J.GetValue<Double>('ready');
        Board.Cut:=J.GetValue<Double>('cut');
        Values:=J.GetValue<TJSONArray>('sources');
        if (Values=nil) or (Values.Count>100000) then raise Exception.Create('Invalid stage sources');
        SetLength(Board.Sources,Values.Count);
        for K:=0 to Values.Count-1 do Board.Sources[K]:=Values.Items[K].GetValue<Integer>;
        Data:=J.GetValue<TJSONObject>('score');
        if (Data=nil) or (Data.GetValue<Integer>('schema',0)<>1) or not (Data.GetValue<Integer>('version',0) in [4,5]) or (Data.GetValue<string>('style','')<>'breakout') then raise Exception.Create('Invalid embedded score');
        if ((Root.GetValue<Integer>('version')>=10)<>(Data.GetValue<Integer>('version')=5)) then raise Exception.Create('Embedded action version mismatch');
        Child:=Result.ChildAudio(Board);
        try Board.Plan:=TBreakScorePlan.Load(Data,Child);
        finally Child.Free;
        end;
      end;
      Items:=ArrayOf('bosses',64);
      SetLength(Result.FBosses,Items.Count);
      for I:=0 to Items.Count-1 do begin
        J:=ObjectAt(Items,I);
        Result.FBosses[I].Start:=J.GetValue<Double>('start');
        Result.FBosses[I].Quiet:=J.GetValue<Double>('quiet');
        Result.FBosses[I].Kill:=J.GetValue<Double>('kill');
        Result.FBosses[I].Finish:=J.GetValue<Double>('finish');
        Result.FBosses[I].KillSource:=J.GetValue<Integer>('killSource',-1);
        Result.FBosses[I].HP:=J.GetValue<Integer>('hp',-1);
        Values:=J.GetValue<TJSONArray>('paddles');
        if (Values=nil) or (Values.Count>155) then raise Exception.Create('Invalid boss paddle');
        SetLength(Result.FBosses[I].Paddles,Values.Count);
        for K:=0 to Values.Count-1 do begin Data:=ObjectAt(Values,K);
          Result.FBosses[I].Paddles[K].Time:=Data.GetValue<Double>('time');
          Result.FBosses[I].Paddles[K].Value:=Data.GetValue<Double>('value');
        end;
      end;
      Items:=ArrayOf('attacks',20000);
      SetLength(Result.FAttacks,Items.Count);
      for I:=0 to Items.Count-1 do begin
        J:=ObjectAt(Items,I);
        Result.FAttacks[I].Boss:=J.GetValue<Integer>('boss',-1);
        Result.FAttacks[I].Source:=J.GetValue<Integer>('source',-2);
        Result.FAttacks[I].Path.Launch:=J.GetValue<Double>('launch');
        Result.FAttacks[I].Path.Hit:=J.GetValue<Double>('hit');
        Result.FAttacks[I].Path.Catch:=J.GetValue<Double>('catch');
        Result.FAttacks[I].Path.A:=BreakPoint(J.GetValue<Double>('ax'),J.GetValue<Double>('ay'));
        Result.FAttacks[I].Path.B:=BreakPoint(J.GetValue<Double>('bx'),J.GetValue<Double>('by'));
        Result.FAttacks[I].Path.C:=BreakPoint(J.GetValue<Double>('cx'),J.GetValue<Double>('cy'));
        Result.FAttacks[I].Path.Target:=Result.FAttacks[I].Boss;
        Result.FAttacks[I].Path.Item:=-1;
      end;
      Items:=ArrayOf('bullets',80000);
      SetLength(Result.FBullets,Items.Count);
      for I:=0 to Items.Count-1 do begin
        J:=ObjectAt(Items,I);
        Result.FBullets[I].Motion.Boss:=J.GetValue<Integer>('boss',-1);
        N:=J.GetValue<Integer>('pattern',-1);
        if (N<0) or (N>3) then raise Exception.Create('Invalid barrage pattern');
        Result.FBullets[I].Motion.Pattern:=TRhythmBarragePattern(N);
        Result.FBullets[I].Motion.Intensity:=J.GetValue<Double>('intensity');
        Result.FBullets[I].Motion.Launch:=J.GetValue<Double>('launch');
        Result.FBullets[I].Motion.Finish:=J.GetValue<Double>('finish');
        Result.FBullets[I].Motion.Origin.X:=J.GetValue<Double>('ox');
        Result.FBullets[I].Motion.Origin.Y:=J.GetValue<Double>('oy');
        Result.FBullets[I].Motion.Velocity.X:=J.GetValue<Double>('vx');
        Result.FBullets[I].Motion.Velocity.Y:=J.GetValue<Double>('vy');
        Result.FBullets[I].Shield:=J.GetValue<Boolean>('shield',False);
      end;
      Result.FCandidateCount:=Root.GetValue<Integer>('bossCandidates',Length(Result.FBosses));
      Result.Reindex;
      Result.Verify;
      if not Near(Result.FGoal,Root.GetValue<Double>('goal')) or not Near(Result.FLaunch,Root.GetValue<Double>('launch')) or not Near(Result.FExit,Root.GetValue<Double>('exit')) or not Near(Result.FEnd,Root.GetValue<Double>('end')) then raise Exception.Create('Campaign timing metadata mismatch');
    except Result.Free;
      Result:=nil;
      raise;
    end;
  end;
end.
