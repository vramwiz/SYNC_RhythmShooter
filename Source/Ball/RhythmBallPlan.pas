unit RhythmBallPlan;
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmBallGeometry;
type
  TBallContactKind=(bcStart,bcBumper,bcBreakable);
  TBallContact=record
    Time,Strength:Double;
    Kind:TBallContactKind;
    Position,Incoming,Outgoing,Normal,Control1,Control2:TBallPoint;
  end;
  TBallPulse=record Time,Strength:Double;ContactIndex:Integer;end;
  TRhythmBallPlan=class
  private
    FContacts:TArray<TBallContact>;
    FObstacles:TArray<TBallObstacle>;
    FPulses:TArray<TBallPulse>;
    FExcludedCount:Integer;
    FTail:TBallFlight;
    FEndTime,FAudioDuration,FSoundEnd:Double;
    FAudioEvents:Integer;
    function GetCount:Integer;
    function GetObstacleCount:Integer;
    function GetPulseCount:Integer;
    function GetPulse(Index:Integer):TBallPulse;
    function GetContact(Index:Integer):TBallContact;
    function GetObstacle(Index:Integer):TBallObstacle;
    function GetFlight(Index:Integer):TBallFlight;
  public
    class function Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean> = nil):TRhythmBallPlan;static;
    procedure Save(var Ref:TRhythmPlanRef;const Cancel:TFunc<Boolean> = nil);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRhythmBallPlan;static;
    // Restore the prepared plan identity without PCM or running analysis.
    // Old v4 files use read-only event metadata when no embedded header exists.
    class function LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;static;
    function ContactBefore(Time:Double):Integer;
    function PulseBefore(Time:Double):Integer;
    function PositionAt(Time:Double):TBallPoint;
    procedure VisibleObstacles(Time:Double;out First,Last:Integer);
    property Count:Integer read GetCount;
    property Contact[Index:Integer]:TBallContact read GetContact;
    property PulseCount:Integer read GetPulseCount;
    property Pulse[Index:Integer]:TBallPulse read GetPulse;
    property ExcludedCount:Integer read FExcludedCount;
    property ObstacleCount:Integer read GetObstacleCount;
    property Obstacle[Index:Integer]:TBallObstacle read GetObstacle;
    // Flight i ends at contact i. Flight 0 is unused; Tail follows the last hit.
    property Flight[Index:Integer]:TBallFlight read GetFlight;
    property Tail:TBallFlight read FTail;
    property EndTime:Double read FEndTime;
  end;
implementation
uses System.Math,System.Classes,System.Generics.Collections,System.JSON,System.IOUtils,System.Hash,
  Winapi.Windows,RhythmStyles,RhythmPaths;
procedure CheckCancel(const Cancel:TFunc<Boolean>);
begin if Assigned(Cancel) and Cancel() then Abort;end;
function PlanPath(const Key:string):string;
begin if not ValidDigest(Key) then raise EArgumentException.Create('Invalid plan key.');Result:=TPath.Combine(PlanFolder,Key+'.json');end;
function Rotate(const P:TBallPoint;Angle:Double):TBallPoint;
begin Result:=BallPoint(P.X*Cos(Angle)-P.Y*Sin(Angle),P.X*Sin(Angle)+P.Y*Cos(Angle));end;
function Inside(const P:TBallPoint;Margin:Double):Boolean;
begin Result:=(P.X>=Margin) and (P.X<=BALL_BOARD_WIDTH-Margin) and (P.Y>=Margin) and (P.Y<=BALL_BOARD_HEIGHT-Margin);end;
function MakeFlight(const A,B:TBallContact):TBallFlight;
begin Result.StartTime:=A.Time;Result.EndTime:=B.Time;Result.A:=A.Position;Result.B:=B.Control1;Result.C:=B.Control2;Result.D:=B.Position;end;
class function TRhythmBallPlan.Build(Audio:TRhythmAudio;const Cancel:TFunc<Boolean>):TRhythmBallPlan;
type TAccent=record Time,Strength:Double;SourceIndex:Integer;end;
  TGroup=record Time,LastTime,Strength:Double;SourceIndex,FirstEvent,LastEvent:Integer;end;
var Contacts:TList<TBallContact>;Obstacles:TList<TBallObstacle>;Events:TList<TGroup>;Raw:TList<TAccent>;Accent:TAccent;Group:TGroup;Pulse:TBallPulse;
  Attempts:TArray<Integer>;Step,WorkCount,WorkLimit,Backtracks,Pass,N:Integer;LastTime,GroupGap,GroupWindow:Double;Failed:Boolean;
  Previous,P:TBallContact;O,Other:TBallObstacle;F:TBallFlight;
  I,J,K,Attempt,Sequence:Integer;Seed:Cardinal;Gap,Distance,Lead,LengthScale:Double;
  Target:TBallPoint;Found,Clear:Boolean;
  function Next:Double;
  begin Seed:=Cardinal((UInt64(Seed)*1664525+1013904223) and $FFFFFFFF);Result:=(Seed shr 8)/16777216.0;end;
  function HasNextDirection:Boolean;
  var D:Double;NextPoint:TBallPoint;
  begin
    Result:=True;if Sequence>=Events.Count then Exit;
    if Events[Sequence].Time-P.Time<0.32 then D:=0.105 else D:=0.1755;
    // A reflection fixes the whole next flight direction. Do not bend that
    // flight to rescue a target near the rail; backtrack this contact instead.
    NextPoint:=BallAdd(P.Position,BallScale(P.Outgoing,D));
    Result:=Inside(NextPoint,0.16);
  end;
  function Candidate:Boolean;
  var N,Sample:Integer;Time,BeginTime,EndTime:Double;
  begin
    Result:=False;
    // Restrict dense clusters to nearby targets; sparse phrases can cross the table.
    if Gap<0.32 then Distance:=0.13+Next*0.12 else Distance:=0.27+Next*0.39;
    if Attempt>=192 then Distance:=Max(0.105,Distance*0.65);
    P.Incoming:=BallUnit(Previous.Outgoing);
    P.Position:=BallAdd(Previous.Position,BallScale(P.Incoming,Distance));
    if not Inside(P.Position,0.16) then Exit;
    P.Normal:=Rotate(BallScale(P.Incoming,-1),(Next-0.5)*2.0);
    P.Outgoing:=BallSub(P.Incoming,BallScale(P.Normal,2*BallDot(P.Incoming,P.Normal)));
    // Leave room for a visible departure along the reflected direction.
    if not Inside(BallAdd(P.Position,BallScale(P.Outgoing,0.09)),0.10) or not HasNextDirection then Exit;
    // Keep the existing flight representation, with collinear thirds. This
    // evaluates to a constant-speed straight segment, then reflects at contact.
    P.Control1:=BallMix(Previous.Position,P.Position,1/3);
    P.Control2:=BallMix(Previous.Position,P.Position,2/3);
    if not Inside(P.Control1,0.08) or not Inside(P.Control2,0.08) then Exit;
    O:=Default(TBallObstacle);O.Kind:=boBumper;
    if (Sequence mod 3=0) or ((P.Strength>0.82) and (Sequence mod 2=0)) then O.Kind:=boBreakable;
    if O.Kind=boBumper then P.Kind:=bcBumper else P.Kind:=bcBreakable;
    LengthScale:=1;if Attempt>=128 then LengthScale:=0.78;
    O.Radius:=(0.040+P.Strength*0.024)*LengthScale;if Gap<0.32 then O.Radius:=Min(O.Radius,0.043);
    O.Normal:=P.Normal;O.Center:=BallSub(P.Position,BallScale(P.Normal,O.Radius+BALL_RADIUS));
    if not Inside(O.Center,O.Radius+0.055) then Exit;
    O.Strength:=P.Strength;O.Hit:=P.Time;
    Lead:=Min(2.4,Max(0.85,Gap+0.55));O.Spawn:=Max(0.0,O.Hit-Lead);O.Origin:=O.Center;O.Arrive:=O.Spawn;
    if (Sequence mod 4=1) and (O.Hit>0.85) then begin
      O.Arrive:=O.Hit-Min(0.30,Gap*0.35);
      if O.Center.X<0.5 then O.Origin.X:=-2.5 else O.Origin.X:=3.5;
      O.Origin.Y:=EnsureRange(O.Center.Y+(Next-0.5)*0.26,0.12,1.28);
    end;
    if O.Kind=boBumper then O.Retire:=Events[Step].LastTime+0.28 else O.Retire:=Events[Step].LastTime+0.65;
    F:=MakeFlight(Previous,P);
    if (Sequence=1) and (P.Time=0) then begin F.A:=P.Position;F.B:=P.Position;F.C:=P.Position;end;
    if not FlightClearsObstacle(F,O) then Exit;
    // New obstacles are also checked against already planned motion during their
    // entire visible lead-in, including movement from outside the table.
    for N:=Contacts.Count-1 downto 1 do begin
      if Contacts[N].Time<O.Spawn then Break;
      if not FlightClearsObstacle(MakeFlight(Contacts[N-1],Contacts[N]),O) then Exit;
    end;
    for N:=Obstacles.Count-1 downto 0 do begin
      Other:=Obstacles[N];if Other.Hit+1.40<Min(F.StartTime,O.Spawn)-0.01 then Break;
      if not FlightClearsObstacle(F,Other) then Exit;
      BeginTime:=Max(O.Spawn,Other.Spawn);EndTime:=Min(O.Hit,ObstacleSolidEnd(Other));
      if EndTime>=BeginTime then for Sample:=0 to 4 do begin
        Time:=BeginTime+(EndTime-BeginTime)*Sample/4;
        if BallLength(BallSub(ObstaclePoint(O,Time),ObstaclePoint(Other,Time)))<O.Radius+Other.Radius+0.008 then Exit;
      end;
    end;
    Result:=True;
  end;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');
  CheckCancel(Cancel);
  Result:=TRhythmBallPlan.Create;Result.FAudioDuration:=Audio.Duration;Result.FSoundEnd:=Audio.SoundEnd;
  Result.FAudioEvents:=Length(Audio.Hits);Contacts:=nil;Obstacles:=nil;Events:=nil;Raw:=nil;
  try
    Contacts:=TList<TBallContact>.Create;Obstacles:=TList<TBallObstacle>.Create;
    Events:=TList<TGroup>.Create;Raw:=TList<TAccent>.Create;Result.FEndTime:=Audio.SoundEnd;LastTime:=-1;
    for I:=0 to High(Audio.Hits) do begin
      CheckCancel(Cancel);
      if IsNan(Audio.Hits[I].Time) or IsInfinite(Audio.Hits[I].Time) or IsNan(Audio.Hits[I].Strength) or IsInfinite(Audio.Hits[I].Strength) or
        (Audio.Hits[I].Time<0) or (Audio.Hits[I].Time<LastTime) or (Audio.Hits[I].Time>Audio.Duration+0.011) then
        raise Exception.Create('解析イベントの時刻または強度が不正です。音楽を再解析してください。');
      LastTime:=Audio.Hits[I].Time;
      if Audio.Hits[I].Time>Audio.SoundEnd+0.011 then begin Inc(Result.FExcludedCount);Continue;end;
      if Raw.Count>=100000 then raise Exception.Create('音イベント数が上限を超えました。設定は保存できます。');
      Accent.Time:=Audio.Hits[I].Time;Accent.Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);Accent.SourceIndex:=I;Raw.Add(Accent);
      Result.FEndTime:=Max(Result.FEndTime,Accent.Time);
    end;
    for Pass:=0 to 2 do begin
      case Pass of 0:begin GroupGap:=0.26;GroupWindow:=0.24;end;
        1:begin GroupGap:=0.34;GroupWindow:=0.48;end;
      else begin GroupGap:=0.45;GroupWindow:=0.72;end;end;
      Events.Clear;
      for I:=0 to Raw.Count-1 do begin
        CheckCancel(Cancel);Accent:=Raw[I];
        if Events.Count>0 then begin
          Group:=Events[Events.Count-1];
          if (Accent.Time-Group.LastTime<=GroupGap) and (Accent.Time-Group.Time<=GroupWindow) then begin
            Group.LastTime:=Accent.Time;Group.LastEvent:=I;Group.Strength:=Max(Group.Strength,Accent.Strength);
            Events[Events.Count-1]:=Group;Continue;
          end;
        end;
        Group.Time:=Accent.Time;Group.LastTime:=Accent.Time;Group.Strength:=Accent.Strength;
        Group.SourceIndex:=Accent.SourceIndex;Group.FirstEvent:=I;Group.LastEvent:=I;Events.Add(Group);
      end;
      if Events.Count>=20000 then raise Exception.Create('衝突数が上限を超えました。設定は保存できます。');
      Contacts.Clear;Obstacles.Clear;
      Previous:=Default(TBallContact);Previous.Position:=BallPoint(0.5,1.10);Previous.Outgoing:=BallPoint(0,-1);
      Previous.Kind:=bcStart;Contacts.Add(Previous);SetLength(Attempts,0);SetLength(Attempts,Events.Count);
      Step:=0;WorkCount:=0;Backtracks:=0;WorkLimit:=Max(8192,Events.Count*256);Failed:=False;
      while Step<Events.Count do begin
        CheckCancel(Cancel);Sequence:=Step+1;Group:=Events[Step];Previous:=Contacts[Contacts.Count-1];
        P:=Default(TBallContact);P.Time:=Group.Time;P.Strength:=Group.Strength;Gap:=P.Time-Previous.Time;Found:=False;
        while Attempts[Step]<256 do begin
          CheckCancel(Cancel);Attempt:=Attempts[Step];Inc(Attempts[Step]);Inc(WorkCount);
          if WorkCount>WorkLimit then begin Failed:=True;Break;end;
          Seed:=Cardinal((UInt64(Group.SourceIndex+1)*747796405+UInt64(Attempt+1)*277803737+2891336453) and $FFFFFFFF);
          if Candidate then begin Found:=True;Break;end;
        end;
        if Failed then Break;
        if Found then begin
          if (Step=0) and (P.Time=0) then begin
            Previous.Position:=P.Position;Previous.Outgoing:=P.Incoming;Contacts[0]:=Previous;
            P.Control1:=P.Position;P.Control2:=P.Position;
          end;
          Contacts.Add(P);Obstacles.Add(O);Inc(Step);if Step<Events.Count then Attempts[Step]:=0;
        end else begin
          if (Step=0) or (Backtracks>=Max(512,Events.Count*16)) then begin Failed:=True;Break;end;
          Attempts[Step]:=0;Dec(Step);Inc(Backtracks);Contacts.Delete(Contacts.Count-1);Obstacles.Delete(Obstacles.Count-1);
        end;
      end;
      if not Failed then Break;
    end;
    if Failed then raise Exception.CreateFmt('ピンボール配置を作成できません（%.3f 秒、%d候補）。元の設定は保存できます。準備ログを確認してください。',[P.Time,WorkCount]);
    // Every valid audio event is retained, including simultaneous accents.
    // Close accents share one physical collision and produce resonance pulses.
    SetLength(Result.FPulses,Raw.Count);
    for I:=0 to Events.Count-1 do begin
      Group:=Events[I];
      for N:=Group.FirstEvent to Group.LastEvent do begin
        Pulse.Time:=Raw[N].Time;Pulse.Strength:=Raw[N].Strength;Pulse.ContactIndex:=I+1;Result.FPulses[N]:=Pulse;
      end;
    end;
    Previous:=Contacts[Contacts.Count-1];
    Result.FContacts:=Contacts.ToArray;Result.FObstacles:=Obstacles.ToArray;
    F:=Default(TBallFlight);F.StartTime:=Previous.Time;F.EndTime:=Min(Result.FEndTime,Previous.Time+0.65);F.A:=Previous.Position;F.D:=F.A;
    for J:=0 to 4 do begin
      Distance:=0.16/(J+1);Target:=BallAdd(F.A,BallScale(Previous.Outgoing,Distance));
      if not Inside(Target,0.08) then Continue;
      F.B:=BallMix(F.A,Target,0.65);F.C:=Target;F.D:=Target;Clear:=True;
      for K:=Obstacles.Count-1 downto 0 do begin
        if Obstacles[K].Hit+1.40<F.StartTime then Break;
        if not FlightClearsObstacle(F,Obstacles[K]) then begin Clear:=False;Break;end;
      end;
      if Clear then Break;
      F.D:=F.A;
    end;
    if (F.D.X=F.A.X) and (F.D.Y=F.A.Y) then begin F.B:=F.A;F.C:=F.A;end;
    Result.FTail:=F;
  except Result.Free;Contacts.Free;Obstacles.Free;Events.Free;Raw.Free;raise;end;
  Contacts.Free;Obstacles.Free;Events.Free;Raw.Free;
end;
function TRhythmBallPlan.GetCount:Integer;begin Result:=Length(FContacts);end;
function TRhythmBallPlan.GetObstacleCount:Integer;begin Result:=Length(FObstacles);end;
function TRhythmBallPlan.GetPulseCount:Integer;begin Result:=Length(FPulses);end;
function TRhythmBallPlan.GetPulse(Index:Integer):TBallPulse;begin Result:=FPulses[Index];end;
function TRhythmBallPlan.GetContact(Index:Integer):TBallContact;begin Result:=FContacts[Index];end;
function TRhythmBallPlan.GetObstacle(Index:Integer):TBallObstacle;begin Result:=FObstacles[Index];end;
function TRhythmBallPlan.GetFlight(Index:Integer):TBallFlight;begin Result:=MakeFlight(FContacts[Index-1],FContacts[Index]);end;
function TRhythmBallPlan.ContactBefore(Time:Double):Integer;
var A,B,M:Integer;
begin A:=0;B:=Length(FContacts);while A<B do begin M:=(A+B) div 2;if FContacts[M].Time<=Time then A:=M+1 else B:=M;end;Result:=Max(0,A-1);end;
function TRhythmBallPlan.PositionAt(Time:Double):TBallPoint;
var I:Integer;
begin
  Time:=EnsureRange(Time,0.0,FEndTime);I:=ContactBefore(Time);
  if I<High(FContacts) then Result:=FlightPoint(GetFlight(I+1),Time) else Result:=FlightPoint(FTail,Time);
end;
function TRhythmBallPlan.PulseBefore(Time:Double):Integer;
var A,B,M:Integer;
begin A:=0;B:=Length(FPulses);while A<B do begin M:=(A+B) div 2;if FPulses[M].Time<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
procedure TRhythmBallPlan.VisibleObstacles(Time:Double;out First,Last:Integer);
begin First:=Max(0,ContactBefore(Time-1.40)-1);Last:=Min(High(FObstacles),ContactBefore(Time+2.45));end;
procedure AddPoint(J:TJSONObject;const Name:string;const P:TBallPoint);
var A:TJSONArray;
begin A:=TJSONArray.Create;A.AddElement(TJSONNumber.Create(P.X));A.AddElement(TJSONNumber.Create(P.Y));J.AddPair(Name,A);end;
function ReadPoint(J:TJSONObject;const Name:string):TBallPoint;
var A:TJSONArray;
begin
  A:=J.GetValue<TJSONArray>(Name);if (A=nil) or (A.Count<>2) then raise Exception.Create('Invalid pinball point.');
  Result.X:=A.Items[0].GetValue<Double>;Result.Y:=A.Items[1].GetValue<Double>;
  if IsNan(Result.X) or IsInfinite(Result.X) or IsNan(Result.Y) or IsInfinite(Result.Y) or (Abs(Result.X)>4) or (Abs(Result.Y)>4) then raise Exception.Create('Invalid pinball coordinate.');
end;
function Finite(Value:Double):Boolean;
begin Result:=not IsNan(Value) and not IsInfinite(Value);end;
procedure TRhythmBallPlan.Save(var Ref:TRhythmPlanRef;const Cancel:TFunc<Boolean>);
var Root,Item:TJSONObject;Items:TJSONArray;P:TBallContact;O:TBallObstacle;Pulse:TBallPulse;Path,Temp:string;Id:TGUID;
begin
  if (Ref.Style<>rsBall) or (Ref.Version<>StylePlanVersion(rsBall)) then raise Exception.Create('Invalid pinball plan reference.');
  Root:=TJSONObject.Create;Temp:='';
  try
    Root.AddPair('schema',TJSONNumber.Create(3));Root.AddPair('style','ball');Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);Root.AddPair('source',Ref.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));Root.AddPair('end',TJSONNumber.Create(FEndTime));
    Root.AddPair('excluded',TJSONNumber.Create(FExcludedCount));
    Item:=TJSONObject.Create;Root.AddPair('audio',Item);Item.AddPair('schema',TJSONNumber.Create(1));
    Item.AddPair('duration',TJSONNumber.Create(FAudioDuration));Item.AddPair('soundEnd',TJSONNumber.Create(FSoundEnd));
    Item.AddPair('events',TJSONNumber.Create(FAudioEvents));
    Items:=TJSONArray.Create;Root.AddPair('contacts',Items);
    for P in FContacts do begin CheckCancel(Cancel);Item:=TJSONObject.Create;
      Item.AddPair('time',TJSONNumber.Create(P.Time));Item.AddPair('strength',TJSONNumber.Create(P.Strength));Item.AddPair('kind',TJSONNumber.Create(Ord(P.Kind)));
      AddPoint(Item,'position',P.Position);AddPoint(Item,'incoming',P.Incoming);AddPoint(Item,'outgoing',P.Outgoing);AddPoint(Item,'normal',P.Normal);
      AddPoint(Item,'control1',P.Control1);AddPoint(Item,'control2',P.Control2);Items.AddElement(Item);
    end;
    Items:=TJSONArray.Create;Root.AddPair('obstacles',Items);
    for O in FObstacles do begin CheckCancel(Cancel);Item:=TJSONObject.Create;
      Item.AddPair('kind',TJSONNumber.Create(Ord(O.Kind)));Item.AddPair('spawn',TJSONNumber.Create(O.Spawn));Item.AddPair('arrive',TJSONNumber.Create(O.Arrive));
      Item.AddPair('hit',TJSONNumber.Create(O.Hit));Item.AddPair('retire',TJSONNumber.Create(O.Retire));Item.AddPair('radius',TJSONNumber.Create(O.Radius));Item.AddPair('strength',TJSONNumber.Create(O.Strength));
      AddPoint(Item,'origin',O.Origin);AddPoint(Item,'center',O.Center);AddPoint(Item,'normal',O.Normal);Items.AddElement(Item);
    end;
    Items:=TJSONArray.Create;Root.AddPair('pulses',Items);
    for Pulse in FPulses do begin CheckCancel(Cancel);Item:=TJSONObject.Create;
      Item.AddPair('time',TJSONNumber.Create(Pulse.Time));Item.AddPair('strength',TJSONNumber.Create(Pulse.Strength));
      Item.AddPair('contact',TJSONNumber.Create(Pulse.ContactIndex));Items.AddElement(Item);
    end;
    Item:=TJSONObject.Create;Root.AddPair('tail',Item);Item.AddPair('start',TJSONNumber.Create(FTail.StartTime));Item.AddPair('end',TJSONNumber.Create(FTail.EndTime));
    AddPoint(Item,'a',FTail.A);AddPoint(Item,'b',FTail.B);AddPoint(Item,'c',FTail.C);AddPoint(Item,'d',FTail.D);
    CheckCancel(Cancel);Path:=PlanPath(Ref.Key);ForceDirectories(ExtractFileDir(Path));CreateGUID(Id);Temp:=Path+'.'+GUIDToString(Id)+'.tmp';
    TFile.WriteAllText(Temp,Root.ToJSON,TEncoding.UTF8);CheckCancel(Cancel);
    if not MoveFileEx(PChar(Temp),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    Temp:='';Ref.Digest:=THashSHA2.GetHashStringFromFile(Path);
  finally if (Temp<>'') and FileExists(Temp) then TFile.Delete(Temp);Root.Free;end;
end;
class function TRhythmBallPlan.LoadAudioMetadata(const Ref:TRhythmPlanRef;const Source:string;Direction:Integer):TRhythmAudio;
var Root,Info:TJSONObject;V:TJSONValue;Path,Failure:string;EventCount:Integer;
begin
  Result:=nil;Root:=nil;
  if not Ref.Matches(Ref.SourceKey,Ref.Sensitivity,Direction,rsBall) or
    not ValidDigest(Ref.SourceKey) or not ValidDigest(Ref.Digest) or
    (Ref.Sensitivity<1) or (Ref.Sensitivity>100) then
    raise Exception.Create('ボール計画が未準備か旧版です。設定画面で再準備して適用してください。');
  Path:=PlanPath(Ref.Key);
  if not FileExists(Path) then raise Exception.Create('保存済みボール計画がありません: '+Path+'。設定画面で再準備してください。');
  if TFile.GetSize(Path)>32*1024*1024 then raise Exception.Create('ボール計画のファイルサイズが不正です。');
  if not SameText(THashSHA2.GetHashStringFromFile(Path),Ref.Digest) then
    raise Exception.Create('保存済みボール計画の内容ハッシュが一致しません。設定画面で再準備してください。');
  try
    try
      V:=TJSONObject.ParseJSONValue(TFile.ReadAllText(Path,TEncoding.UTF8));
      if not (V is TJSONObject) then begin V.Free;raise Exception.Create('ボール計画JSONを読めません。');end;
      Root:=TJSONObject(V);
      if (Root.GetValue<Integer>('schema',0)<>3) or (Root.GetValue<string>('style','')<>'ball') or
        (Root.GetValue<Integer>('version',0)<>Ref.Version) or (Root.GetValue<string>('key','')<>Ref.Key) or
        (Root.GetValue<string>('source','')<>Ref.SourceKey) or (Root.GetValue<Integer>('sensitivity',0)<>Ref.Sensitivity) or
        (Root.GetValue<Integer>('direction',-1)<>Direction) then raise Exception.Create('ボール計画の保存条件が設定と一致しません。');
      V:=Root.GetValue('audio');
      if V=nil then begin
        if Ref.Version<>4 then raise Exception.Create('保存済みボール計画に復元情報がありません。設定画面で再準備してください。');
        // Legacy v4: its events JSON contains the required bounds. Missing PCM
        // must not turn an otherwise complete, valid saved plan into an error.
        Result:=LoadCachedRhythmAudio(Source,Ref.Sensitivity,False,Failure);
        if Result=nil then
          raise Exception.Create('旧ボール計画の復元用メタデータを読めません。設定画面で一度再準備し、適用・作品保存してください。 原因: '+Failure);
        if Result.Key<>Ref.SourceKey then raise Exception.Create('旧ボール計画と保存済み音声イベントのキーが一致しません。再準備してください。');
      end else begin
        if not (V is TJSONObject) then raise Exception.Create('ボール計画の音声情報が不正です。');
        Info:=TJSONObject(V);
        if Info.GetValue<Integer>('schema',0)<>1 then raise Exception.Create('ボール計画の音声情報が旧形式です。');
        Result:=TRhythmAudio.Create;Result.Source:=ExpandFileName(Source);Result.Key:=Ref.SourceKey;
        Result.Sensitivity:=Ref.Sensitivity;Result.CacheReused:=True;
        Result.Duration:=Info.GetValue<Double>('duration');Result.SoundEnd:=Info.GetValue<Double>('soundEnd');
        Result.SourceRevision:=Ref.SourceRevision;EventCount:=Info.GetValue<Integer>('events',-1);
        if not Finite(Result.Duration) or not Finite(Result.SoundEnd) or (Result.Duration<=0) or
          (Result.Duration>512*Int64(1024)*1024/4/RHYTHM_RATE) or (Result.SoundEnd<0) or
          (Result.SoundEnd>Result.Duration) or (EventCount<0) or (EventCount>100000) then
          raise Exception.Create('ボール計画の音声情報が範囲外です。');
        if (Source='') or not FileExists(Source) then raise Exception.Create('準備時の音楽ファイルがありません。参照先を確認してください: '+Source);
        if Result.SourceRevision='' then raise Exception.Create('オブジェクトの復元情報が不足しています。一度再準備・適用して作品を保存してください。');
        if not AudioSourceUnchanged(Result) then raise Exception.Create('音楽ファイルが準備時から変更されています。再準備してください。');
        SetLength(Result.Hits,EventCount);
      end;
      // The scene still calls Load with this descriptor. That retains all
      // timing/count/geometry/reflection checks; metadata never means "ready".
    except FreeAndNil(Result);raise;end;
  finally Root.Free;end;
end;
class function TRhythmBallPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TRhythmBallPlan;
var Root,Item,Info:TJSONObject;V:TJSONValue;Items:TJSONArray;I,Kind:Integer;Path:string;P:TBallContact;O:TBallObstacle;Reflected:TBallPoint;Pulse:TBallPulse;LastPulse,MaxStrength:TArray<Double>;PulseCounts:TArray<Integer>;PreviousIndex:Integer;
begin
  Result:=nil;Root:=nil;
  if Audio=nil then raise Exception.Create('音声キャッシュが未準備です。設定画面で音楽を準備してください。');
  if Ref.Key='' then raise Exception.Create('動作計画が未準備です（旧計画は無効）。設定画面の準備ボタンで完了を待ち、適用してください。');
  if not CompatiblePlanVersion(rsBall,Ref.Version) then raise Exception.Create('旧版のボール計画です。設定画面で再準備し、適用してください。');
  if not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsBall) then raise Exception.Create('動作計画の音楽・感度・方向が一致しません。設定画面で再準備してください。');
  if not ValidDigest(Ref.Digest) then raise Exception.Create('動作計画の検証情報がありません。設定画面で再準備してください。');
  Path:=PlanPath(Ref.Key);
  if not FileExists(Path) or (TFile.GetSize(Path)>32*1024*1024) then raise Exception.Create('ピンボール計画が見つからないか、サイズが不正です。設定画面で再準備してください。');
  if not SameText(THashSHA2.GetHashStringFromFile(Path),Ref.Digest) then raise Exception.Create('ピンボール計画の検証に失敗しました。設定画面で再準備してください。');
  try
    V:=TJSONObject.ParseJSONValue(TFile.ReadAllText(Path,TEncoding.UTF8));if not (V is TJSONObject) then begin V.Free;raise Exception.Create('Invalid pinball JSON.');end;Root:=TJSONObject(V);
    if (Root.GetValue<Integer>('schema',0)<>3) or (Root.GetValue<string>('style','')<>'ball') or (Root.GetValue<Integer>('version',0)<>Ref.Version) or
      (Root.GetValue<string>('key','')<>Ref.Key) or (Root.GetValue<string>('source','')<>Audio.Key) or
      (Root.GetValue<Integer>('sensitivity',0)<>Audio.Sensitivity) or (Root.GetValue<Integer>('direction',-1)<>Direction) then raise Exception.Create('Pinball plan identity mismatch.');
    V:=Root.GetValue('audio');
    if (Ref.Version=5) and not (V is TJSONObject) then raise Exception.Create('Ball restoration metadata missing.');
    if V<>nil then begin
      if not (V is TJSONObject) then raise Exception.Create('Invalid ball audio metadata.');
      Info:=TJSONObject(V);
      if (Info.GetValue<Integer>('schema',0)<>1) or
        not Finite(Info.GetValue<Double>('duration')) or not Finite(Info.GetValue<Double>('soundEnd')) or
        (Abs(Info.GetValue<Double>('duration')-Audio.Duration)>1E-6) or
        (Abs(Info.GetValue<Double>('soundEnd')-Audio.SoundEnd)>1E-6) or
        (Info.GetValue<Integer>('events',-1)<>Length(Audio.Hits)) then raise Exception.Create('Ball audio metadata mismatch.');
    end;
    Items:=Root.GetValue<TJSONArray>('contacts');if (Items=nil) or (Items.Count=0) or (Items.Count>20000) then raise Exception.Create('Invalid pinball contact count.');
    Result:=TRhythmBallPlan.Create;Result.FAudioDuration:=Audio.Duration;Result.FSoundEnd:=Audio.SoundEnd;
    Result.FAudioEvents:=Length(Audio.Hits);Result.FEndTime:=Root.GetValue<Double>('end');
    if not Finite(Result.FEndTime) or (Result.FEndTime<Audio.SoundEnd) or (Result.FEndTime>Audio.Duration+0.011) then raise Exception.Create('Invalid pinball end time.');
    Result.FExcludedCount:=Root.GetValue<Integer>('excluded',0);
    if (Result.FExcludedCount<0) or (Result.FExcludedCount>Length(Audio.Hits)) then raise Exception.Create('Invalid excluded event count.');
    SetLength(Result.FContacts,Items.Count);
    for I:=0 to Items.Count-1 do begin
      if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid pinball contact.');Item:=TJSONObject(Items.Items[I]);
      P.Time:=Item.GetValue<Double>('time');P.Strength:=Item.GetValue<Double>('strength');Kind:=Item.GetValue<Integer>('kind');
      if not Finite(P.Time) or not Finite(P.Strength) or (P.Time<0) or (P.Time>Result.FEndTime) or (P.Strength<0) or (P.Strength>1) or (Kind<0) or (Kind>2) then raise Exception.Create('Pinball contact out of bounds.');
      P.Kind:=TBallContactKind(Kind);P.Position:=ReadPoint(Item,'position');P.Incoming:=ReadPoint(Item,'incoming');P.Outgoing:=ReadPoint(Item,'outgoing');
      P.Normal:=ReadPoint(Item,'normal');P.Control1:=ReadPoint(Item,'control1');P.Control2:=ReadPoint(Item,'control2');
      if not Inside(P.Position,0.08) or (Abs(BallLength(P.Outgoing)-1)>1E-7) then raise Exception.Create('Invalid pinball direction.');
      if I=0 then begin if (P.Time<>0) or (P.Kind<>bcStart) then raise Exception.Create('Invalid pinball start.');end
      else begin
        if ((P.Time<Result.FContacts[I-1].Time) or ((I>1) and (P.Time=Result.FContacts[I-1].Time))) or (P.Kind=bcStart) or not Inside(P.Control1,0.08) or not Inside(P.Control2,0.08) or
          (Abs(BallLength(P.Incoming)-1)>1E-7) or (Abs(BallLength(P.Normal)-1)>1E-7) or (BallDot(P.Incoming,P.Normal)>=-0.5) then raise Exception.Create('Invalid pinball contact geometry.');
        if (BallLength(BallSub(P.Incoming,Result.FContacts[I-1].Outgoing))>1E-7) or
          (BallLength(BallSub(P.Control1,BallMix(Result.FContacts[I-1].Position,P.Position,1/3)))>1E-7) or
          (BallLength(BallSub(P.Control2,BallMix(Result.FContacts[I-1].Position,P.Position,2/3)))>1E-7) then
          raise Exception.Create('Curved pinball flight; prepare the straight-flight plan again.');
        if (P.Time>Result.FContacts[I-1].Time) and
          (BallLength(BallSub(BallUnit(BallSub(P.Position,Result.FContacts[I-1].Position)),P.Incoming))>1E-7) then
          raise Exception.Create('Pinball flight does not follow the reflection.');
        Reflected:=BallSub(P.Incoming,BallScale(P.Normal,2*BallDot(P.Incoming,P.Normal)));
        if BallLength(BallSub(Reflected,P.Outgoing))>1E-7 then raise Exception.Create('Invalid pinball reflection.');
      end;Result.FContacts[I]:=P;
    end;
    Items:=Root.GetValue<TJSONArray>('pulses');
    if (Items=nil) or (Items.Count>100000) or (Items.Count+Result.FExcludedCount<>Length(Audio.Hits)) then raise Exception.Create('Invalid pulse count.');
    SetLength(Result.FPulses,Items.Count);SetLength(LastPulse,Result.Count);SetLength(MaxStrength,Result.Count);SetLength(PulseCounts,Result.Count);PreviousIndex:=0;
    for I:=0 to Items.Count-1 do begin
      if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid pulse.');Item:=TJSONObject(Items.Items[I]);
      Pulse.Time:=Item.GetValue<Double>('time');Pulse.Strength:=Item.GetValue<Double>('strength');Pulse.ContactIndex:=Item.GetValue<Integer>('contact');
      if not Finite(Pulse.Time) or not Finite(Pulse.Strength) or (Pulse.Time<0) or (Pulse.Time>Result.FEndTime) or
        (Pulse.Strength<0) or (Pulse.Strength>1) or (Pulse.ContactIndex<1) or (Pulse.ContactIndex>=Result.Count) then raise Exception.Create('Invalid pulse range.');
      if (Pulse.ContactIndex<PreviousIndex) or (Pulse.ContactIndex>PreviousIndex+1) or
        ((I>0) and (Pulse.Time<Result.FPulses[I-1].Time)) then raise Exception.Create('Invalid pulse order.');
      P:=Result.FContacts[Pulse.ContactIndex];
      if (Pulse.Time<P.Time) or (Pulse.Time>P.Time+0.721) or ((PulseCounts[Pulse.ContactIndex]=0) and (Pulse.Time<>P.Time)) then raise Exception.Create('Invalid pulse contact link.');
      Inc(PulseCounts[Pulse.ContactIndex]);LastPulse[Pulse.ContactIndex]:=Pulse.Time;
      MaxStrength[Pulse.ContactIndex]:=Max(MaxStrength[Pulse.ContactIndex],Pulse.Strength);
      Result.FPulses[I]:=Pulse;PreviousIndex:=Pulse.ContactIndex;
    end;
    for I:=1 to Result.Count-1 do if (PulseCounts[I]=0) or (MaxStrength[I]<>Result.FContacts[I].Strength) then raise Exception.Create('Missing collision pulses.');
    Items:=Root.GetValue<TJSONArray>('obstacles');if (Items=nil) or (Items.Count<>Result.Count-1) then raise Exception.Create('Invalid pinball obstacle count.');
    SetLength(Result.FObstacles,Items.Count);
    for I:=0 to Items.Count-1 do begin
      if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid pinball obstacle.');Item:=TJSONObject(Items.Items[I]);
      Kind:=Item.GetValue<Integer>('kind');if (Kind<0) or (Kind>1) then raise Exception.Create('Invalid pinball obstacle kind.');O.Kind:=TBallObstacleKind(Kind);
      O.Spawn:=Item.GetValue<Double>('spawn');O.Arrive:=Item.GetValue<Double>('arrive');O.Hit:=Item.GetValue<Double>('hit');O.Retire:=Item.GetValue<Double>('retire');
      O.Radius:=Item.GetValue<Double>('radius');O.Strength:=Item.GetValue<Double>('strength');O.Origin:=ReadPoint(Item,'origin');O.Center:=ReadPoint(Item,'center');O.Normal:=ReadPoint(Item,'normal');P:=Result.FContacts[I+1];
      if not Finite(O.Spawn) or not Finite(O.Arrive) or not Finite(O.Hit) or not Finite(O.Retire) or not Finite(O.Radius) or not Finite(O.Strength) or
        (O.Spawn<0) or (O.Arrive<O.Spawn) or (O.Arrive>O.Hit) or (O.Hit<>P.Time) or (O.Retire<O.Hit) or (O.Retire>O.Hit+1.40) or
        (O.Hit-O.Spawn>2.401) or (O.Radius<0.025) or (O.Radius>0.07) or (O.Strength<>P.Strength) or not Inside(O.Center,O.Radius+0.05) or
        (BallLength(BallSub(O.Normal,P.Normal))>1E-7) or
        (BallLength(BallSub(P.Position,BallAdd(O.Center,BallScale(O.Normal,O.Radius+BALL_RADIUS))))>1E-7) or
        ((P.Kind=bcBreakable)<>(O.Kind=boBreakable)) then raise Exception.Create('Invalid pinball obstacle geometry.');
      if O.Kind=boBumper then begin
        if Abs(O.Retire-LastPulse[I+1]-0.28)>1E-7 then raise Exception.Create('Invalid bumper lifetime.');
      end else if Abs(O.Retire-LastPulse[I+1]-0.65)>1E-7 then raise Exception.Create('Invalid destruction lifetime.');
      Result.FObstacles[I]:=O;
    end;
    Item:=Root.GetValue<TJSONObject>('tail');if Item=nil then raise Exception.Create('Pinball tail missing.');
    Result.FTail.StartTime:=Item.GetValue<Double>('start');Result.FTail.EndTime:=Item.GetValue<Double>('end');
    Result.FTail.A:=ReadPoint(Item,'a');Result.FTail.B:=ReadPoint(Item,'b');Result.FTail.C:=ReadPoint(Item,'c');Result.FTail.D:=ReadPoint(Item,'d');
    if not Finite(Result.FTail.StartTime) or not Finite(Result.FTail.EndTime) or (Result.FTail.StartTime<>Result.FContacts[Result.Count-1].Time) or
      (Result.FTail.EndTime<Result.FTail.StartTime) or (Result.FTail.EndTime>Result.FEndTime) or
      (BallLength(BallSub(Result.FTail.A,Result.FContacts[Result.Count-1].Position))>1E-7) or not Inside(Result.FTail.B,0.08) or
      not Inside(Result.FTail.C,0.08) or not Inside(Result.FTail.D,0.08) then raise Exception.Create('Invalid pinball tail.');
    if (BallLength(BallSub(Result.FTail.B,BallMix(Result.FTail.A,Result.FTail.D,0.65)))>1E-7) or
      (BallLength(BallSub(Result.FTail.C,Result.FTail.D))>1E-7) then raise Exception.Create('Curved pinball tail.');
    if (BallLength(BallSub(Result.FTail.D,Result.FTail.A))>1E-8) and
      (BallLength(BallSub(BallUnit(BallSub(Result.FTail.D,Result.FTail.A)),Result.FContacts[Result.Count-1].Outgoing))>1E-7) then
      raise Exception.Create('Pinball tail does not follow the last reflection.');
  except FreeAndNil(Result);Root.Free;raise;end;
  Root.Free;
end;
end.
