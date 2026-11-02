unit RhythmBreakoutPlan;
// このスタイルの全曲事前計画と保存互換を担当し、描画からの再解析を行わない。
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmBreakoutGeometry,RhythmBreakoutScore,RhythmBreakoutCampaign;
type
  TBreakCandidate=record
    Time,Strength:Double;
    Source:Integer;
  end;
  TBreakoutPlan=class
  private
    FCandidates:TArray<TBreakCandidate>;
    FBlocks:TArray<TBreakBlock>;
    FSegments:TArray<TBreakSegment>;
    FPaddles:TArray<TBreakPaddle>;
    FDuration,FSoundEnd,FBaseSpeed,FLaunch,FGoal,FEnd:Double;
    FSourceCount,FAttempts:Integer;
    FScore:TBreakScorePlan;
    FCampaign:TBreakCampaign;
    function GetSyncCount:Integer;
    function GetBallEnd:Double;
    function GetEnd:Double;
    function GetPaddleHalf:Double;
    function GetBossCount:Integer;
    function GetExitStart:Double;
    function GetPrimaryCount:Integer;
    function GetItemCount:Integer;
    function GetExtraCount:Integer;
    function GetAuxCount:Integer;
    function GetCatchCount:Integer;
    procedure Validate(const Cancel:TFunc<Boolean> = nil);
    function GetCount:Integer;
    function GetBlock(I:Integer):TBreakBlock;
  public
    destructor Destroy; override;
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TBreakoutPlan; static;
    procedure Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TBreakoutPlan; static;
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio; static;
    function PositionAt(Time:Double):TBreakPoint;
    function PaddleAt(Time:Double):Double;
    function BlockBefore(Time:Double):Integer;
    function BlockAt(Index:Integer;Time:Double):TBreakBlock;
    function BlockRow(Index:Integer):Integer;
    function HeldAt(Time:Double):Boolean;
    function BlockVisible(Index:Integer;Time:Double):Boolean;
    function MainAt(Time:Double;out P:TBreakPoint;out Opacity:Double):Boolean;
    function RadiusAt(Time:Double):Double;
    function Item(Index:Integer):TScoreItem;
    function ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Opacity:Double):Boolean;
    property PrimaryCount:Integer read GetPrimaryCount;
    property ItemCount:Integer read GetItemCount;
    property ExtraCount:Integer read GetExtraCount;
    property PaddleHalf:Double read GetPaddleHalf;
    property Campaign:TBreakCampaign read FCampaign;
    property BossCount:Integer read GetBossCount;
    property ExitStart:Double read GetExitStart;
    property Count:Integer read GetCount;
    property Block[I:Integer]:TBreakBlock read GetBlock;
    property GoalTime:Double read FGoal;
    property EndTime:Double read GetEnd;
    property LaunchTime:Double read FLaunch;
    property ReflectionCount:Integer read GetSyncCount;
    property BallEndTime:Double read GetBallEnd;
    property AuxiliaryCount:Integer read GetAuxCount;
    property CatchCount:Integer read GetCatchCount;
    property SourceCount:Integer read FSourceCount;
    property Attempts:Integer read FAttempts;
  end;
implementation
uses System.Math,System.JSON,System.Generics.Collections,RhythmStyles,RhythmPreparedData;

function TBreakoutPlan.RadiusAt(Time:Double):Double;
begin Result:=BREAK_RADIUS;
  if FCampaign<>nil then Result:=FCampaign.RadiusAt(Time) else if FScore<>nil then Result:=FScore.RadiusAt(Time);
end;

function Finite(V:Double):Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V);
end;

destructor TBreakoutPlan.Destroy;
begin FCampaign.Free;
  FScore.Free;
  inherited;
end;

class function TBreakoutPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TBreakoutPlan;
begin
  Result:=TBreakoutPlan.Create;
  try
    Result.FCampaign:=TBreakCampaign.Build(Audio,Cancel);
    Result.FSourceCount:=Length(Audio.Hits);
    Result.FDuration:=Audio.Duration;
    Result.FSoundEnd:=Audio.SoundEnd;
    Result.FGoal:=Result.FCampaign.GoalTime;
    Result.FLaunch:=Result.FCampaign.LaunchTime;
    Result.FEnd:=Result.FCampaign.EndTime;
    Result.FAttempts:=Result.FCampaign.Trials;
  except Result.Free;
    raise;
  end;
end;

procedure TBreakoutPlan.Validate(const Cancel:TFunc<Boolean>);
var
  I,J:Integer;
  C:TBreakCandidate;
  B:TBreakBlock;
begin
  if not Finite(FDuration) or not Finite(FSoundEnd) or (FDuration<=0) or (FSoundEnd<0) or (FSoundEnd>FDuration) or
  (FSourceCount<0) or (FSourceCount>100000) or (Length(FCandidates)>FSourceCount) or (FAttempts<0) or (FAttempts>288) then raise Exception.Create('Invalid breakout metadata');
  for I:=0 to High(FCandidates) do begin
    C:=FCandidates[I];
    if not Finite(C.Time) or not Finite(C.Strength) or (C.Time<=1E-5) or (C.Time>FSoundEnd+1E-8) or (C.Strength<0) or (C.Strength>1) or
    (C.Source<0) or (C.Source>=FSourceCount) then raise Exception.Create('Invalid breakout candidate');
    if I>0 then if (C.Time<FCandidates[I-1].Time) or (C.Source<=FCandidates[I-1].Source) then raise Exception.Create('Invalid breakout candidate order');
  end;
  J:=0;
  for B in FBlocks do begin
    while (J<Length(FCandidates)) and (FCandidates[J].Source<B.Source) do Inc(J);
    if (J>=Length(FCandidates)) then raise Exception.Create('Missing adopted breakout accent');
    C:=FCandidates[J];
    if (C.Source<>B.Source) or (C.Time<>B.Time) or (C.Strength<>B.Strength) then raise Exception.Create('Breakout changed the audio event');
  end;
  if Length(FCandidates)>0 then begin
    if (Length(FBlocks)=0) or (FGoal<>FCandidates[High(FCandidates)].Time) then raise Exception.Create('Breakout final accent missing');
  end else if (Length(FBlocks)<>0) or (FEnd<>FDuration) or (FAttempts<>0) then raise Exception.Create('Breakout without accents');
  ValidateBreakout(FBlocks,FSegments,FPaddles,FBaseSpeed,FLaunch,FGoal,FEnd,Cancel);
end;

function TBreakoutPlan.GetCount:Integer;
begin if FCampaign<>nil then Result:=FCampaign.Count else if FScore<>nil then Result:=FScore.BlockCount else Result:=Length(FBlocks);
end;

function TBreakoutPlan.GetPrimaryCount:Integer;
begin if FCampaign<>nil then Result:=FCampaign.Count else if FScore<>nil then Result:=FScore.Count else Result:=Length(FBlocks);
end;

function TBreakoutPlan.GetPaddleHalf:Double;
begin Result:=BREAK_PADDLE_HALF;
  if FCampaign<>nil then Result:=FCampaign.PaddleHalf else if FScore<>nil then Result:=FScore.PaddleHalf;
end;

function TBreakoutPlan.GetBossCount:Integer;
begin Result:=0;
  if FCampaign<>nil then Result:=FCampaign.BossCount;
end;

function TBreakoutPlan.GetExitStart:Double;
begin Result:=FGoal+0.55;
  if FCampaign<>nil then Result:=FCampaign.ExitStart;
end;

function TBreakoutPlan.GetItemCount:Integer;
begin Result:=0;
  if FScore<>nil then Result:=FScore.ItemCount;
end;

function TBreakoutPlan.GetExtraCount:Integer;
begin Result:=0;
  if FCampaign<>nil then Result:=FCampaign.ExtraCount else if FScore<>nil then Result:=FScore.ExtraCount;
end;

function TBreakoutPlan.Item(Index:Integer):TScoreItem;
begin Result:=FScore.Item(Index);
end;

function TBreakoutPlan.ExtraAt(Index:Integer;Time:Double;out P:TBreakPoint;out Opacity:Double):Boolean;
begin Result:=False;
  Opacity:=0;
  P:=BreakPoint(0,0);
  if FCampaign<>nil then Result:=FCampaign.ExtraAt(Index,Time,P,Opacity) else if FScore<>nil then Result:=FScore.ExtraAt(Index,Time,P,Opacity);
end;

function TBreakoutPlan.GetBlock(I:Integer):TBreakBlock;
begin if FCampaign<>nil then Result:=FCampaign.BrickAt(I,FGoal) else if FScore<>nil then Result:=FScore.BrickAt(I,FGoal) else Result:=FBlocks[I];
end;

function TBreakoutPlan.BlockBefore(Time:Double):Integer;
var
  A,B,M:Integer;
  R:TBreakBlock;
begin if FCampaign=nil then Exit(-1);
  A:=0;
  B:=Count;
  while A<B do begin M:=(A+B) div 2;
    R:=GetBlock(M);
    if R.Time<=Time then A:=M+1 else B:=M;
  end;
  Result:=A-1;
end;

function TBreakoutPlan.BlockAt(Index:Integer;Time:Double):TBreakBlock;
begin if FCampaign<>nil then Result:=FCampaign.BrickAt(Index,Time) else if FScore<>nil then Result:=FScore.BrickAt(Index,Time) else Result:=FBlocks[Index];
end;

function TBreakoutPlan.BlockRow(Index:Integer):Integer;
begin if FCampaign<>nil then Result:=FCampaign.BrickRow(Index) else if FScore<>nil then Result:=FScore.BrickRow(Index) else Result:=Round(FBlocks[Index].Top/0.08);
end;

function TBreakoutPlan.GetEnd:Double;
begin if FCampaign<>nil then Exit(FCampaign.EndTime);
  Result:=FEnd;
  if Count>0 then Result:=Max(Result,FGoal+1.65);
end;

function TBreakoutPlan.GetSyncCount:Integer;
begin if FCampaign<>nil then Result:=FCampaign.Reflections else if FScore<>nil then Result:=FScore.SyncCount else Result:=Length(FBlocks);
end;

function TBreakoutPlan.GetBallEnd:Double;
begin if FCampaign<>nil then Result:=FCampaign.BallEnd else if FScore<>nil then Result:=FScore.BallEnd else Result:=FEnd;
end;

function TBreakoutPlan.GetAuxCount:Integer;
begin Result:=0;
  if FCampaign<>nil then Result:=FCampaign.Auxiliary else if FScore<>nil then Result:=FScore.AuxiliaryCount;
end;

function TBreakoutPlan.GetCatchCount:Integer;
begin Result:=0;
  if FCampaign<>nil then Result:=FCampaign.Catches else if FScore<>nil then Result:=FScore.CatchCount;
end;

function TBreakoutPlan.HeldAt(Time:Double):Boolean;
begin if FCampaign<>nil then Result:=FCampaign.HeldAt(Time) else if FScore<>nil then Result:=FScore.HeldAt(Time) else Result:=Time<FLaunch;
end;

function TBreakoutPlan.PaddleAt(Time:Double):Double;
begin if FCampaign<>nil then Result:=FCampaign.PaddleAt(Time) else if FScore<>nil then Result:=FScore.PaddleAt(Time) else Result:=BreakPaddleAt(FPaddles,Time);
end;

function TBreakoutPlan.BlockVisible(Index:Integer;Time:Double):Boolean;
begin Result:=True;
  if FCampaign<>nil then Result:=FCampaign.BlockVisible(Index,Time);
end;

function TBreakoutPlan.MainAt(Time:Double;out P:TBreakPoint;out Opacity:Double):Boolean;
begin
  if FCampaign<>nil then Exit(FCampaign.MainAt(Time,P,Opacity));
  P:=PositionAt(Time);
  Opacity:=1;
  if Time>=FGoal then Opacity:=EnsureRange(1-(Time-FGoal)/Max(1E-6,GetBallEnd-FGoal),0.0,1.0);
  Result:=(Count>0) and (Opacity>0);
end;

function TBreakoutPlan.PositionAt(Time:Double):TBreakPoint;
var
  A,B,M:Integer;
  Opacity:Double;
begin
  if FCampaign<>nil then begin FCampaign.MainAt(Time,Result,Opacity);
    Exit;
  end;
  if FScore<>nil then Exit(FScore.PositionAt(Time));
  Result:=BreakPoint(PaddleAt(Time),BREAK_PADDLE_Y);
  if Length(FSegments)=0 then Exit;
  if Time<FLaunch then begin Result.X:=FSegments[0].A.X;
    Exit;
  end;
  A:=0;
  B:=Length(FSegments);
  while A<B do begin M:=(A+B) div 2;
    if FSegments[M].Last<Time then A:=M+1 else B:=M;
  end;
  Result:=BreakSegmentPoint(FSegments[Min(A,High(FSegments))],Time);
end;

procedure TBreakoutPlan.Save(var Ref:TRhythmPlanRef;Audio:TRhythmAudio);
var
  Root,J:TJSONObject;
  Items:TJSONArray;
  C:TBreakCandidate;
  B:TBreakBlock;
  S:TBreakSegment;
  P:TBreakPaddle;
begin
  if FCampaign<>nil then begin FCampaign.Save(Ref,Audio);
    Exit;
  end;
  if FScore<>nil then begin FScore.Save(Ref,Audio);
    Exit;
  end;
  if (Ref.Version<>1) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Ref.Direction,rsBreakout,Ref.Variant) then raise Exception.Create('Invalid breakout reference');
  Root:=TJSONObject.Create;
  try
    Root.AddPair('schema',TJSONNumber.Create(1));
    Root.AddPair('style','breakout');
    Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);
    Root.AddPair('source',Ref.SourceKey);
    Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(Root,Audio);
    Root.AddPair('launch',TJSONNumber.Create(FLaunch));
    Root.AddPair('goal',TJSONNumber.Create(FGoal));
    Root.AddPair('end',TJSONNumber.Create(FEnd));
    Root.AddPair('speed',TJSONNumber.Create(FBaseSpeed));
    Root.AddPair('attempts',TJSONNumber.Create(FAttempts));
    Items:=TJSONArray.Create;
    Root.AddPair('candidates',Items);
    for C in FCandidates do begin J:=TJSONObject.Create;
      Items.AddElement(J);
      J.AddPair('time',TJSONNumber.Create(C.Time));
      J.AddPair('strength',TJSONNumber.Create(C.Strength));
      J.AddPair('source',TJSONNumber.Create(C.Source));
    end;
    Items:=TJSONArray.Create;
    Root.AddPair('blocks',Items);
    for B in FBlocks do begin J:=TJSONObject.Create;
      Items.AddElement(J);
      J.AddPair('left',TJSONNumber.Create(B.Left));
      J.AddPair('right',TJSONNumber.Create(B.Right));
      J.AddPair('top',TJSONNumber.Create(B.Top));
      J.AddPair('bottom',TJSONNumber.Create(B.Bottom));
      J.AddPair('time',TJSONNumber.Create(B.Time));
      J.AddPair('strength',TJSONNumber.Create(B.Strength));
      J.AddPair('source',TJSONNumber.Create(B.Source));
    end;
    Items:=TJSONArray.Create;
    Root.AddPair('segments',Items);
    for S in FSegments do begin J:=TJSONObject.Create;
      Items.AddElement(J);
      J.AddPair('first',TJSONNumber.Create(S.First));
      J.AddPair('last',TJSONNumber.Create(S.Last));
      J.AddPair('ax',TJSONNumber.Create(S.A.X));
      J.AddPair('ay',TJSONNumber.Create(S.A.Y));
      J.AddPair('bx',TJSONNumber.Create(S.B.X));
      J.AddPair('by',TJSONNumber.Create(S.B.Y));
      J.AddPair('kind',TJSONNumber.Create(Ord(S.Kind)));
      J.AddPair('block',TJSONNumber.Create(S.Block));
    end;
    Items:=TJSONArray.Create;
    Root.AddPair('paddles',Items);
    for P in FPaddles do begin J:=TJSONObject.Create;
      Items.AddElement(J);
      J.AddPair('time',TJSONNumber.Create(P.Time));
      J.AddPair('x',TJSONNumber.Create(P.X));
    end;
    WritePreparedData(Root,Ref);
  finally Root.Free;
  end;
end;

class function TBreakoutPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var
  Root:TJSONObject;
begin Root:=ReadPreparedData(Ref,rsBreakout,Direction);
  try Result:=PreparedAudio(Root,Ref,Source);
  finally Root.Free;
  end;
end;

class function TBreakoutPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TBreakoutPlan;
var
  Root,J,Info:TJSONObject;
  Items:TJSONArray;
  I,K:Integer;
  function ArrayOf(const Name:string;Limit:Integer):TJSONArray;
  begin Result:=Root.GetValue<TJSONArray>(Name);
    if (Result=nil) or (Result.Count>Limit) then raise Exception.Create('Invalid breakout array: '+Name);
  end;
  function Item(Index:Integer):TJSONObject;
  begin if not (Items.Items[Index] is TJSONObject) then raise Exception.Create('Invalid breakout item');
    Result:=TJSONObject(Items.Items[Index]);
  end;
begin
  Result:=nil;
  if (Audio=nil) then raise Exception.Create('Breakout audio metadata missing');
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsBreakout,Ref.Variant) then raise Exception.Create('Breakout settings mismatch');
  Root:=ReadPreparedData(Ref,rsBreakout,Direction);
  try
    try
      if Ref.Version in [5,6,7,8,9,10] then begin
        Result:=TBreakoutPlan.Create;
        Result.FCampaign:=TBreakCampaign.Load(Root,Audio);
        if (Ref.Version>=8) and (Result.FCampaign.BossFrequency<>BossFrequencyFromVariant(Ref.Variant)) then raise Exception.Create('Boss frequency reference mismatch');
        Result.FSourceCount:=Length(Audio.Hits);
        Result.FDuration:=Audio.Duration;
        Result.FSoundEnd:=Audio.SoundEnd;
        Result.FGoal:=Result.FCampaign.GoalTime;
        Result.FLaunch:=Result.FCampaign.LaunchTime;
        Result.FEnd:=Result.FCampaign.EndTime;
        Result.FAttempts:=Result.FCampaign.Trials;
        Exit;
      end;
      if Ref.Version in [2,3,4] then begin
        Result:=TBreakoutPlan.Create;
        Result.FScore:=TBreakScorePlan.Load(Root,Audio);
        Result.FSourceCount:=Length(Audio.Hits);
        Result.FDuration:=Audio.Duration;
        Result.FSoundEnd:=Audio.SoundEnd;
        Result.FGoal:=Result.FScore.GoalTime;
        Result.FLaunch:=Result.FScore.LaunchTime;
        Result.FEnd:=Result.FScore.EndTime;
        Result.FAttempts:=Result.FScore.Trials;
        Exit;
      end;
      Info:=Root.GetValue<TJSONObject>('audio');
      if (Info=nil) or (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) or
      not Finite(Info.GetValue<Double>('duration')) or not Finite(Info.GetValue<Double>('soundEnd')) or
      (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-6) or (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-6) then raise Exception.Create('Breakout audio identity mismatch');
      Result:=TBreakoutPlan.Create;
      Result.FDuration:=Audio.Duration;
      Result.FSoundEnd:=Audio.SoundEnd;
      Result.FSourceCount:=Length(Audio.Hits);
      Result.FLaunch:=Root.GetValue<Double>('launch');
      Result.FGoal:=Root.GetValue<Double>('goal');
      Result.FEnd:=Root.GetValue<Double>('end');
      Result.FBaseSpeed:=Root.GetValue<Double>('speed');
      Result.FAttempts:=Root.GetValue<Integer>('attempts',-1);
      Items:=ArrayOf('candidates',100000);
      SetLength(Result.FCandidates,Items.Count);
      for I:=0 to Items.Count-1 do begin J:=Item(I);
        Result.FCandidates[I].Time:=J.GetValue<Double>('time');
        Result.FCandidates[I].Strength:=J.GetValue<Double>('strength');
        Result.FCandidates[I].Source:=J.GetValue<Integer>('source',-1);
      end;
      Items:=ArrayOf('blocks',24);
      SetLength(Result.FBlocks,Items.Count);
      for I:=0 to Items.Count-1 do begin J:=Item(I);
        Result.FBlocks[I].Left:=J.GetValue<Double>('left');
        Result.FBlocks[I].Right:=J.GetValue<Double>('right');
        Result.FBlocks[I].Top:=J.GetValue<Double>('top');
        Result.FBlocks[I].Bottom:=J.GetValue<Double>('bottom');
        Result.FBlocks[I].Time:=J.GetValue<Double>('time');
        Result.FBlocks[I].Strength:=J.GetValue<Double>('strength');
        Result.FBlocks[I].Source:=J.GetValue<Integer>('source',-1);
      end;
      Items:=ArrayOf('segments',BREAK_MAX_SEGMENTS);
      SetLength(Result.FSegments,Items.Count);
      for I:=0 to Items.Count-1 do begin
        J:=Item(I);
        Result.FSegments[I].First:=J.GetValue<Double>('first');
        Result.FSegments[I].Last:=J.GetValue<Double>('last');
        Result.FSegments[I].A:=BreakPoint(J.GetValue<Double>('ax'),J.GetValue<Double>('ay'));
        Result.FSegments[I].B:=BreakPoint(J.GetValue<Double>('bx'),J.GetValue<Double>('by'));
        K:=J.GetValue<Integer>('kind',-1);
        if (K<Ord(Low(TBreakEnd))) or (K>Ord(High(TBreakEnd))) then raise Exception.Create('Invalid breakout reflection kind');
        Result.FSegments[I].Kind:=TBreakEnd(K);
        Result.FSegments[I].Block:=J.GetValue<Integer>('block',-1);
      end;
      Items:=ArrayOf('paddles',BREAK_MAX_SEGMENTS+2);
      SetLength(Result.FPaddles,Items.Count);
      for I:=0 to Items.Count-1 do begin J:=Item(I);
        Result.FPaddles[I].Time:=J.GetValue<Double>('time');
        Result.FPaddles[I].X:=J.GetValue<Double>('x');
      end;
      Result.Validate;
    except Result.Free;
      Result:=nil;
      raise;
    end;
  finally Root.Free;
  end;
end;
end.
