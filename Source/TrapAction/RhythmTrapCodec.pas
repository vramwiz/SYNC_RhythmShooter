unit RhythmTrapCodec;
// 全曲の動作と罠をbinary64で保持。復元時の再解析・物理積分は行わない。
interface
uses RhythmTrapPlan, RhythmAudio, RhythmPlanRef;
procedure SaveTrapPlan(Plan:TTrapPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
function LoadTrapPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TTrapPlan;
function LoadTrapAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
implementation
uses System.SysUtils,System.JSON,System.Math,System.Generics.Collections,RhythmPreparedData,RhythmStyles,RhythmTrapBuild;
procedure Check(B:Boolean);
begin if not B then raise EConvertError.Create('初見殺しアクションの保存計画が不正です');end;
procedure SaveTrapPlan(Plan:TTrapPlan;Audio:TRhythmAudio;var Ref:TRhythmPlanRef);
var O:TJSONObject;A,R:TJSONArray;M:TTrapMove;T:TTrapObstacle;P:TTrapPlatform;
  procedure D(V:Double);begin R.AddElement(PreparedExact(V));end;
begin
  O:=TJSONObject.Create;
  try
    O.AddPair('schema',TJSONNumber.Create(1));O.AddPair('style',StyleId(rsTrapAction));
    O.AddPair('version',TJSONNumber.Create(Ref.Version));O.AddPair('key',Ref.Key);O.AddPair('source',Ref.SourceKey);
    O.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));O.AddPair('direction',TJSONNumber.Create(Ref.Direction));
    AddPreparedAudio(O,Audio);O.AddPair('duration',PreparedExact(Plan.Duration));
    O.AddPair('goalTime',PreparedExact(Plan.GoalTime));O.AddPair('goalX',PreparedExact(Plan.GoalX));
    O.AddPair('theme',TJSONNumber.Create(Ord(Plan.Theme)));
    A:=TJSONArray.Create;O.AddPair('moves',A);
    for M in Plan.Moves do begin R:=TJSONArray.Create;A.AddElement(R);
      D(M.Start);D(M.Cue);D(M.Finish);D(M.Origin.X);D(M.Origin.Y);D(M.Target.X);D(M.Target.Y);D(M.Arc);
      R.Add(Ord(M.Kind));R.Add(M.Section);R.Add(M.Pattern);R.Add(Ord(M.Landing));R.Add(Ord(M.CueSynced));R.Add(Ord(M.LandSynced));R.Add(Ord(M.Avoidance));end;
    A:=TJSONArray.Create;O.AddPair('traps',A);
    for T in Plan.Obstacles do begin R:=TJSONArray.Create;A.AddElement(R);R.Add(Ord(T.Kind));
      D(T.Reveal);D(T.Fire);D(T.Cue);D(T.Finish);D(T.X);D(T.Y);D(T.W);D(T.H);D(T.Travel);D(T.Power);
      R.Add(T.Move);R.Add(Ord(T.Synced));D(T.Embed);end;
    A:=TJSONArray.Create;O.AddPair('platforms',A);
    for P in Plan.Platforms do begin R:=TJSONArray.Create;A.AddElement(R);
      D(P.Left);D(P.Right);D(P.Y);D(P.EndY);D(P.Start);D(P.Finish);R.Add(P.Move);R.Add(Ord(P.Kind));
      R.Add(Ord(P.Motion));D(P.Reveal);D(P.Trigger);D(P.Settle);D(P.DX);D(P.DY);D(P.Release);D(P.Recover);end;
    A:=TJSONArray.Create;O.AddPair('ceilings',A);
    for P in Plan.Ceilings do begin R:=TJSONArray.Create;A.AddElement(R);
      D(P.Left);D(P.Right);D(P.Y);D(P.EndY);D(P.Start);D(P.Finish);R.Add(P.Move);R.Add(Ord(P.Kind));
      R.Add(Ord(P.Motion));D(P.Reveal);D(P.Trigger);D(P.Settle);D(P.DX);D(P.DY);D(P.Release);D(P.Recover);end;
    WritePreparedData(O,Ref);
  finally O.Free;end;
end;
function LoadTrapAudio(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var O:TJSONObject;
begin O:=ReadPreparedData(Ref,rsTrapAction,Direction);try Result:=PreparedAudio(O,Ref,Source);finally O.Free;end;end;
function LoadTrapPlan(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TTrapPlan;
var O:TJSONObject;A,R:TJSONArray;I:Integer;M:TTrapMove;T:TTrapObstacle;P:TTrapPlatform;
  function D(N:Integer):Double;
  begin Result:=ReadPreparedExact(R.Items[N]);Check(Abs(Result)<1E8);end;
  function N(Index,Lo,Hi:Integer):Integer;
  begin Check((R.Items[Index] is TJSONNumber) and TryStrToInt(R.Items[Index].Value,Result));Check(InRange(Result,Lo,Hi));end;
  procedure Rows(const Name:string;Limit:Integer;AllowEmpty:Boolean=False);
  begin Check(O.GetValue(Name) is TJSONArray);A:=TJSONArray(O.GetValue(Name));Check((AllowEmpty or (A.Count>0)) and (A.Count<=Limit));end;
  procedure Row(Index,Count:Integer);
  begin Check(A.Items[Index] is TJSONArray);R:=TJSONArray(A.Items[Index]);Check(R.Count=Count);end;
begin
  Check((Audio<>nil) and InRange(Ref.Variant,1,8) and Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsTrapAction,Ref.Variant));
  O:=ReadPreparedData(Ref,rsTrapAction,Direction);
  try
    Result:=TTrapPlan.Create;
    try
      Result.Theme:=TTrapStage(Ref.Variant-1);Check(O.GetValue<Integer>('theme',-1)=Ord(Result.Theme));
      // 計画はbinary64、共通音声情報はJSONの十進表記。読戻しの丸め差だけを許容する。
      Result.Duration:=ReadPreparedExact(O.GetValue('duration'));Check((Result.Duration>0) and (Abs(Result.Duration-Audio.Duration)<1E-8));
      Result.GoalTime:=ReadPreparedExact(O.GetValue('goalTime'));Result.GoalX:=ReadPreparedExact(O.GetValue('goalX'));
      Rows('moves',50000);SetLength(Result.Moves,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,15);M:=Default(TTrapMove);
        M.Start:=D(0);M.Cue:=D(1);M.Finish:=D(2);M.Origin:=TrapPoint(D(3),D(4));M.Target:=TrapPoint(D(5),D(6));M.Arc:=D(7);
        M.Kind:=TTrapMotion(N(8,0,Ord(High(TTrapMotion))));M.Section:=N(9,0,10000);M.Pattern:=N(10,0,63);
        M.Landing:=N(11,0,1)=1;M.CueSynced:=N(12,0,1)=1;M.LandSynced:=N(13,0,1)=1;
        M.Avoidance:=TTrapAvoidance(N(14,0,Ord(High(TTrapAvoidance))));
        Check((Abs(M.Target.X-M.Origin.X)<=20) and (M.Arc>=0) and (M.Arc<=10));Result.Moves[I]:=M;end;
      Rows('traps',40000,True);SetLength(Result.Obstacles,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,14);T:=Default(TTrapObstacle);
        T.Kind:=TTrapKind(N(0,0,Ord(High(TTrapKind))));T.Reveal:=D(1);T.Fire:=D(2);T.Cue:=D(3);T.Finish:=D(4);
        T.X:=D(5);T.Y:=D(6);T.W:=D(7);T.H:=D(8);T.Travel:=D(9);T.Power:=D(10);T.Move:=N(11,0,High(Result.Moves));T.Synced:=N(12,0,1)=1;
        T.Embed:=D(13);
        Check((T.Reveal>=0) and (T.Reveal<=T.Fire) and (T.Fire<T.Cue) and (T.Cue<T.Finish) and
          (T.Finish<=Result.Duration) and (T.W>0) and (T.W<40) and (T.H>0) and (T.H<40) and InRange(T.Travel,0.0,20.0));
        Result.Obstacles[I]:=T;end;
      Rows('platforms',30000);SetLength(Result.Platforms,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,16);P:=Default(TTrapPlatform);
        P.Left:=D(0);P.Right:=D(1);P.Y:=D(2);P.EndY:=D(3);P.Start:=D(4);P.Finish:=D(5);
        P.Move:=N(6,-1,High(Result.Moves));P.Kind:=TTrapKind(N(7,0,Ord(High(TTrapKind))));
        P.Motion:=TTrapPlatformMotion(N(8,0,Ord(High(TTrapPlatformMotion))));
        P.Reveal:=D(9);P.Trigger:=D(10);P.Settle:=D(11);P.DX:=D(12);P.DY:=D(13);P.Release:=D(14);P.Recover:=D(15);
        Check(P.Right>P.Left);Result.Platforms[I]:=P;end;
      Rows('ceilings',60000);SetLength(Result.Ceilings,A.Count);
      for I:=0 to A.Count-1 do begin Row(I,16);P:=Default(TTrapPlatform);
        P.Left:=D(0);P.Right:=D(1);P.Y:=D(2);P.EndY:=D(3);P.Start:=D(4);P.Finish:=D(5);
        P.Move:=N(6,-1,High(Result.Moves));P.Kind:=TTrapKind(N(7,0,Ord(High(TTrapKind))));
        P.Motion:=TTrapPlatformMotion(N(8,0,Ord(High(TTrapPlatformMotion))));
        P.Reveal:=D(9);P.Trigger:=D(10);P.Settle:=D(11);P.DX:=D(12);P.DY:=D(13);P.Release:=D(14);P.Recover:=D(15);
        Check(P.Right>P.Left);Result.Ceilings[I]:=P;end;
      Check((Result.Moves[0].Start=0) and (Result.GoalTime=Result.Moves[High(Result.Moves)].Finish) and
        (Result.GoalTime<=Result.Duration) and (Result.GoalX=Result.Moves[High(Result.Moves)].Target.X));
      ValidateTrapPlan(Result,nil);
    except Result.Free;raise;end;
  finally O.Free;end;
end;
end.
