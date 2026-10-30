unit RhythmFireworksPlan;
// 音時刻を保持する開花計画と絶対時刻の軌道。描画側は解析や乱数更新を行わない。
interface
uses System.SysUtils,RhythmAudio,RhythmPlanRef,RhythmStyles;
type
  TFireworkKind=(fwPeony,fwWillow,fwRings,fwStar,fwHeart,fwPalm);
  TFireworkPoint=record X,Y:Double;end;
  TFireworkBurst=record
    Time,LaunchTime,X,Y,GroundX,Size,Strength,Lifetime:Double;
    Kind:TFireworkKind;
    Hue,Rays,AccentIndex,Member:Integer;
    Seed:Cardinal;
  end;
  TFireworksPlan=class
  private
    FBursts:TArray<TFireworkBurst>;
    FEndTime:Double;
    FExcluded,FSourceEvents,FRichness:Integer;
    function GetCount:Integer;
    function GetBurst(Index:Integer):TFireworkBurst;
  public
    class function Build(Audio:TRhythmAudio;Direction:Integer;Richness:Integer=FIREWORKS_DEFAULT_RICHNESS;const Cancel:TFunc<Boolean> = nil):TFireworksPlan;static;
    procedure Save(var Ref:TRhythmPlanRef;const Cancel:TFunc<Boolean> = nil);
    class function Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TFireworksPlan;static;
    function BurstBefore(Time:Double):Integer;
    procedure VisibleRange(Time:Double;out First,Last:Integer);
    property Count:Integer read GetCount;
    property Burst[Index:Integer]:TFireworkBurst read GetBurst;
    property EndTime:Double read FEndTime;
    property ExcludedCount:Integer read FExcluded;
    property SourceEventCount:Integer read FSourceEvents;
    property Richness:Integer read FRichness;
  end;
// 打ち上げ位置は正規化座標、火花は短辺基準の相対位置を返す。
// どちらも絶対時刻だけで求め、プレビューと本番で同じ式を使う。
function FireworkRocketAt(const B:TFireworkBurst;Time:Double):TFireworkPoint;
function FireworkSparkOffset(const B:TFireworkBurst;Index:Integer;Age:Double):TFireworkPoint;
function FireworkVolleyCount(Richness:Integer):Integer;
implementation
uses System.Math,System.Classes,System.Generics.Collections,System.JSON,System.IOUtils,System.Hash,
  Winapi.Windows,RhythmPaths;
procedure CheckCancel(const Cancel:TFunc<Boolean>);
begin if Assigned(Cancel) and Cancel() then Abort;end;
function Finite(Value:Double):Boolean;
begin Result:=not IsNan(Value) and not IsInfinite(Value);end;
function PlanPath(const Key:string):string;
begin if not ValidDigest(Key) then raise Exception.Create('Invalid fireworks plan key.');Result:=TPath.Combine(PlanFolder,Key+'.json');end;
function FireworkVolleyCount(Richness:Integer):Integer;
begin
  Result:=1;if Richness>=35 then Inc(Result);if Richness>=70 then Inc(Result);if Richness>=95 then Inc(Result);
end;
function FireworkRocketAt(const B:TFireworkBurst;Time:Double):TFireworkPoint;
var U:Double;
begin
  if B.Time<=B.LaunchTime then begin Result.X:=B.X;Result.Y:=B.Y;Exit;end;
  U:=EnsureRange((Time-B.LaunchTime)/(B.Time-B.LaunchTime),0.0,1.0);
  U:=U*(2-U); // Decreasing rise speed, with the same progress on both axes.
  Result.X:=B.GroundX+(B.X-B.GroundX)*U;
  Result.Y:=0.88+(B.Y-0.88)*U;
end;
function SparkNoise(Index,Salt:Cardinal):Double;
var V:Cardinal;
begin
  V:=Cardinal(((UInt64(Index)+1)*747796405+UInt64(Salt)*2891336453) and $FFFFFFFF);
  V:=Cardinal((UInt64(V xor (V shr 16))*2246822519) and $FFFFFFFF);
  Result:=((V xor (V shr 13)) shr 8)/16777216.0;
end;
function FireworkSparkOffset(const B:TFireworkBurst;Index:Integer;Age:Double):TFireworkPoint;
var Phase,A,D,G,R,V,T,AX,AY,BX,BY:Double;Vertex:Integer;
begin
  Age:=Max(0.0,Age);Phase:=Frac(Index*0.618033988749895+SparkNoise(B.Seed,113));
  A:=Pi*2*Phase;V:=0.82+SparkNoise(Index,B.Seed)*0.18;
  D:=B.Size*(1-Exp(-2.3*Age))*1.22;G:=0.055;
  Result.X:=Cos(A)*V;Result.Y:=Sin(A)*V;
  case B.Kind of
    fwWillow:begin D:=D*0.80;G:=0.095;end;
    fwRings:begin if Index mod 2=0 then D:=D*0.62;G:=0;Result.X:=Cos(A);Result.Y:=Sin(A);end;
    fwStar:begin
      T:=Phase*10;Vertex:=Floor(T);T:=Frac(T);
      R:=1;if Vertex mod 2=1 then R:=0.44;
      AX:=Cos(-Pi/2+Vertex*Pi/5)*R;AY:=Sin(-Pi/2+Vertex*Pi/5)*R;
      R:=1;if (Vertex+1) mod 2=1 then R:=0.44;
      BX:=Cos(-Pi/2+(Vertex+1)*Pi/5)*R;BY:=Sin(-Pi/2+(Vertex+1)*Pi/5)*R;
      Result.X:=AX+(BX-AX)*T;Result.Y:=AY+(BY-AY)*T;G:=0.012;
    end;
    fwHeart:begin
      T:=Sin(A);Result.X:=T*T*T;
      Result.Y:=-(13*Cos(A)-5*Cos(2*A)-2*Cos(3*A)-Cos(4*A))/17;
      G:=0.012;
    end;
    fwPalm:begin
      A:=Pi+(0.12+(Index mod 7)/6*0.76)*Pi+(SparkNoise(Index,B.Seed)-0.5)*0.07;
      Result.X:=Cos(A)*V;Result.Y:=Sin(A)*V;D:=D*1.05;G:=0.13;
    end;
  end;
  Result.X:=Result.X*D;Result.Y:=Result.Y*D+G*Age*Age;
end;
class function TFireworksPlan.Build(Audio:TRhythmAudio;Direction,Richness:Integer;const Cancel:TFunc<Boolean>):TFireworksPlan;
var List:TList<TFireworkBurst>;B:TFireworkBurst;I,M,Volley:Integer;Seed:Cardinal;
  Gap,Density,LastTime,CenterX,CenterY,Energy,Spread:Double;
  function Next:Double;
  begin Seed:=Cardinal((UInt64(Seed)*1664525+1013904223) and $FFFFFFFF);Result:=(Seed shr 8)/16777216.0;end;
begin
  if Audio=nil then raise EArgumentNilException.Create('Audio');CheckCancel(Cancel);
  if (Direction<0) or (Direction>1) or (Richness<0) or (Richness>100) then raise EArgumentException.Create('Invalid fireworks options.');
  Result:=TFireworksPlan.Create;List:=nil;
  try
    List:=TList<TFireworkBurst>.Create;Result.FEndTime:=Audio.SoundEnd;Result.FRichness:=Richness;LastTime:=-1;
    Volley:=FireworkVolleyCount(Richness);Energy:=Richness/100;
    for I:=0 to High(Audio.Hits) do begin
      CheckCancel(Cancel);
      if not Finite(Audio.Hits[I].Time) or not Finite(Audio.Hits[I].Strength) or (Audio.Hits[I].Time<0) or
        (Audio.Hits[I].Time<LastTime) or (Audio.Hits[I].Time>Audio.Duration+0.011) then raise Exception.Create('Invalid audio accent for fireworks.');
      LastTime:=Audio.Hits[I].Time;
      if (Audio.SoundEnd<=0) or (Audio.Hits[I].Time>Audio.SoundEnd+0.011) then begin Inc(Result.FExcluded);Continue;end;
      if Result.FSourceEvents>=20000 then raise Exception.Create('花火イベント数が上限です。設定は保存できます。');
      Inc(Result.FSourceEvents);
      Seed:=Cardinal((UInt64(I+1)*747796405+UInt64(Direction)*2891336453+277803737) and $FFFFFFFF);
      CenterX:=0.23+Next*0.54;CenterY:=0.17+Next*0.29;if Direction=1 then CenterY:=0.15+Next*0.36;
      Gap:=2;if I>0 then Gap:=Min(Gap,LastTime-Audio.Hits[I-1].Time);
      if I<High(Audio.Hits) then Gap:=Min(Gap,Audio.Hits[I+1].Time-LastTime);
      Density:=EnsureRange(Gap/0.50,0.35,1.0);Spread:=0.10+Energy*0.22;
      for M:=0 to Volley-1 do begin
        CheckCancel(Cancel);
        B:=Default(TFireworkBurst);B.Time:=LastTime;B.AccentIndex:=I;B.Member:=M;
        B.Strength:=EnsureRange(Audio.Hits[I].Strength,0.0,1.0);B.Seed:=Seed;
        B.Kind:=TFireworkKind((I+M*2) mod 6);B.Hue:=Trunc(Next*8);
        B.X:=EnsureRange(CenterX+(M-(Volley-1)/2)*Spread,0.10,0.90);
        B.Y:=EnsureRange(CenterY+(Next-0.5)*0.06,0.13,0.56);
        // Vertical launches are easy to track. A fixed flight duration preserves
        // consecutive accent order even when the bloom spacing is very small.
        B.GroundX:=B.X;B.LaunchTime:=Max(0.0,B.Time-1.05);
        B.Size:=(0.09+B.Strength*0.105)*(0.78+Energy*0.44)*(0.72+Density*0.28);
        B.Rays:=EnsureRange(Round((32+B.Strength*60)*(0.65+Energy*0.70)*(0.58+Density*0.42)),16,128);
        case B.Kind of
          fwWillow:begin B.Lifetime:=2.85+B.Strength*0.35;B.Hue:=0;end;
          fwRings:B.Lifetime:=1.95+B.Strength*0.30;
          fwStar,fwHeart:B.Lifetime:=2.15+B.Strength*0.25;
          fwPalm:begin B.Lifetime:=2.60+B.Strength*0.35;B.Hue:=0;end;
        else B.Lifetime:=2.15+B.Strength*0.35;end;
        List.Add(B);Result.FEndTime:=Max(Result.FEndTime,B.Time+B.Lifetime);
      end;
    end;
    Result.FBursts:=List.ToArray;
  except Result.Free;List.Free;raise;end;List.Free;
end;
function TFireworksPlan.GetCount:Integer;begin Result:=Length(FBursts);end;
function TFireworksPlan.GetBurst(Index:Integer):TFireworkBurst;begin Result:=FBursts[Index];end;
function TFireworksPlan.BurstBefore(Time:Double):Integer;
var A,B,M:Integer;
begin A:=0;B:=Count;while A<B do begin M:=(A+B) div 2;if FBursts[M].Time<=Time then A:=M+1 else B:=M;end;Result:=A-1;end;
procedure TFireworksPlan.VisibleRange(Time:Double;out First,Last:Integer);
begin First:=Max(0,BurstBefore(Time-3.21));Last:=Min(Count-1,BurstBefore(Time+1.26)+1);end;
procedure TFireworksPlan.Save(var Ref:TRhythmPlanRef;const Cancel:TFunc<Boolean>);
var Root,Item:TJSONObject;Items:TJSONArray;B:TFireworkBurst;Path,Temp:string;Id:TGUID;
begin
  if (Ref.Style<>rsFireworks) or (Ref.Version<>StylePlanVersion(rsFireworks)) or (Ref.Variant<>FRichness) then raise Exception.Create('Invalid fireworks reference.');
  Root:=TJSONObject.Create;Temp:='';
  try
    Root.AddPair('schema',TJSONNumber.Create(2));Root.AddPair('style','fireworks');Root.AddPair('version',TJSONNumber.Create(Ref.Version));
    Root.AddPair('key',Ref.Key);Root.AddPair('source',Ref.SourceKey);Root.AddPair('sensitivity',TJSONNumber.Create(Ref.Sensitivity));
    Root.AddPair('richness',TJSONNumber.Create(FRichness));Root.AddPair('events',TJSONNumber.Create(FSourceEvents));
    Root.AddPair('direction',TJSONNumber.Create(Ref.Direction));Root.AddPair('end',TJSONNumber.Create(FEndTime));Root.AddPair('excluded',TJSONNumber.Create(FExcluded));
    Items:=TJSONArray.Create;Root.AddPair('bursts',Items);
    for B in FBursts do begin
      CheckCancel(Cancel);Item:=TJSONObject.Create;Items.AddElement(Item);
      Item.AddPair('accent',TJSONNumber.Create(B.AccentIndex));Item.AddPair('member',TJSONNumber.Create(B.Member));
      Item.AddPair('time',TJSONNumber.Create(B.Time));Item.AddPair('launch',TJSONNumber.Create(B.LaunchTime));
      Item.AddPair('x',TJSONNumber.Create(B.X));Item.AddPair('y',TJSONNumber.Create(B.Y));Item.AddPair('ground',TJSONNumber.Create(B.GroundX));
      Item.AddPair('size',TJSONNumber.Create(B.Size));Item.AddPair('strength',TJSONNumber.Create(B.Strength));Item.AddPair('life',TJSONNumber.Create(B.Lifetime));
      Item.AddPair('kind',TJSONNumber.Create(Ord(B.Kind)));Item.AddPair('hue',TJSONNumber.Create(B.Hue));Item.AddPair('rays',TJSONNumber.Create(B.Rays));Item.AddPair('seed',TJSONNumber.Create(Int64(B.Seed)));
    end;
    CheckCancel(Cancel);Path:=PlanPath(Ref.Key);ForceDirectories(ExtractFileDir(Path));CreateGUID(Id);Temp:=Path+'.'+GUIDToString(Id)+'.tmp';
    TFile.WriteAllText(Temp,Root.ToJSON,TEncoding.UTF8);CheckCancel(Cancel);
    if not MoveFileEx(PChar(Temp),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    Temp:='';Ref.Digest:=THashSHA2.GetHashStringFromFile(Path);
  finally if (Temp<>'') and FileExists(Temp) then TFile.Delete(Temp);Root.Free;end;
end;
class function TFireworksPlan.Load(const Ref:TRhythmPlanRef;Audio:TRhythmAudio;Direction:Integer):TFireworksPlan;
var Root,Item:TJSONObject;V:TJSONValue;Items:TJSONArray;B:TFireworkBurst;I,Kind,Volley,EventCount,PreviousAccent,PreviousMember:Integer;Seed:Int64;Path:string;ComputedEnd:Double;
begin
  Result:=nil;Root:=nil;
  if Audio=nil then raise Exception.Create('音声が未準備です。設定画面で準備してください。');
  if (Ref.Variant<0) or (Ref.Variant>100) or not Ref.Matches(Audio.Key,Audio.Sensitivity,Direction,rsFireworks,Ref.Variant) or not ValidDigest(Ref.Digest) then
    raise Exception.Create('花火計画を更新したか設定が変わっています。設定画面で花火・華やかさを再準備し、適用してください。');
  Path:=PlanPath(Ref.Key);
  if not FileExists(Path) or (TFile.GetSize(Path)>64*1024*1024) then raise Exception.Create('花火計画がありません。設定画面で再準備してください。');
  if not SameText(THashSHA2.GetHashStringFromFile(Path),Ref.Digest) then raise Exception.Create('花火計画の内容検証に失敗しました。再準備してください。');
  try
    V:=TJSONObject.ParseJSONValue(TFile.ReadAllText(Path,TEncoding.UTF8));if not (V is TJSONObject) then begin V.Free;raise Exception.Create('Invalid fireworks JSON.');end;Root:=TJSONObject(V);
    if (Root.GetValue<Integer>('schema',0)<>2) or (Root.GetValue<string>('style','')<>'fireworks') or (Root.GetValue<Integer>('version',0)<>Ref.Version) or
      (Root.GetValue<string>('key','')<>Ref.Key) or (Root.GetValue<string>('source','')<>Audio.Key) or (Root.GetValue<Integer>('sensitivity',0)<>Audio.Sensitivity) or
      (Root.GetValue<Integer>('direction',-1)<>Direction) or (Root.GetValue<Integer>('richness',-1)<>Ref.Variant) then raise Exception.Create('Fireworks identity mismatch.');
    Items:=Root.GetValue<TJSONArray>('bursts');if (Items=nil) or (Items.Count>80000) then raise Exception.Create('Invalid fireworks count.');
    Result:=TFireworksPlan.Create;Result.FEndTime:=Root.GetValue<Double>('end');Result.FExcluded:=Root.GetValue<Integer>('excluded',0);
    Result.FRichness:=Ref.Variant;Result.FSourceEvents:=Root.GetValue<Integer>('events',-1);Volley:=FireworkVolleyCount(Ref.Variant);
    if not Finite(Result.FEndTime) or (Result.FEndTime<Audio.SoundEnd) or (Result.FEndTime>Audio.Duration+3.22) or
      (Result.FExcluded<0) or (Result.FSourceEvents<0) or (Result.FSourceEvents>20000) or
      (Result.FSourceEvents+Result.FExcluded<>Length(Audio.Hits)) or (Items.Count<>Result.FSourceEvents*Volley) or ((Audio.SoundEnd<=0) and (Items.Count>0)) then raise Exception.Create('Invalid fireworks bounds.');
    SetLength(Result.FBursts,Items.Count);ComputedEnd:=Audio.SoundEnd;EventCount:=0;PreviousAccent:=-1;PreviousMember:=-1;
    for I:=0 to Items.Count-1 do begin
      if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Invalid firework.');Item:=TJSONObject(Items.Items[I]);
      B.AccentIndex:=Item.GetValue<Integer>('accent');B.Member:=Item.GetValue<Integer>('member');
      B.Time:=Item.GetValue<Double>('time');B.LaunchTime:=Item.GetValue<Double>('launch');B.X:=Item.GetValue<Double>('x');B.Y:=Item.GetValue<Double>('y');B.GroundX:=Item.GetValue<Double>('ground');
      B.Size:=Item.GetValue<Double>('size');B.Strength:=Item.GetValue<Double>('strength');B.Lifetime:=Item.GetValue<Double>('life');Kind:=Item.GetValue<Integer>('kind');
      B.Hue:=Item.GetValue<Integer>('hue');B.Rays:=Item.GetValue<Integer>('rays');Seed:=Item.GetValue<Int64>('seed');
      if not Finite(B.Time) or not Finite(B.LaunchTime) or not Finite(B.X) or not Finite(B.Y) or not Finite(B.GroundX) or not Finite(B.Size) or not Finite(B.Strength) or not Finite(B.Lifetime) or
        (B.Time<0) or (B.Time>Audio.SoundEnd+0.011) or (B.LaunchTime<0) or (B.LaunchTime>B.Time) or (Abs(B.LaunchTime-Max(0.0,B.Time-1.05))>1E-8) or
        (B.X<0.08) or (B.X>0.92) or (B.Y<0.12) or (B.Y>0.58) or (B.GroundX<0.08) or (B.GroundX>0.92) or (B.Size<0.05) or (B.Size>0.25) or
        (B.Strength<0) or (B.Strength>1) or (B.Lifetime<1.9) or (B.Lifetime>3.201) or (Kind<0) or (Kind>Ord(High(TFireworkKind))) or (B.Hue<0) or (B.Hue>7) or (B.Rays<16) or (B.Rays>128) or (Seed<0) or (Seed>High(Cardinal)) then raise Exception.Create('Firework out of range.');
      if (B.AccentIndex<0) or (B.AccentIndex>=Length(Audio.Hits)) or (B.Member<0) or (B.Member>=Volley) then
        raise Exception.Create('Invalid firework accent link.');
      if (B.AccentIndex<>PreviousAccent) then begin
        if (PreviousAccent>=0) and (PreviousMember<>Volley-1) then raise Exception.Create('Incomplete firework volley.');
        if (B.AccentIndex<>PreviousAccent+1) or (B.Member<>0) then raise Exception.Create('Missing firework accent.');
        Inc(EventCount);
      end else if B.Member<>PreviousMember+1 then raise Exception.Create('Invalid volley order.');
      if (B.Time<>Audio.Hits[B.AccentIndex].Time) or
        (B.Strength<>EnsureRange(Audio.Hits[B.AccentIndex].Strength,0.0,1.0)) or
        (Abs(B.GroundX-B.X)>1E-8) then raise Exception.Create('Firework accent or launch mismatch.');
      PreviousAccent:=B.AccentIndex;PreviousMember:=B.Member;
      if (I>0) and (B.Time<Result.FBursts[I-1].Time) then raise Exception.Create('Firework times are not ordered.');
      B.Kind:=TFireworkKind(Kind);B.Seed:=Cardinal(Seed);Result.FBursts[I]:=B;ComputedEnd:=Max(ComputedEnd,B.Time+B.Lifetime);
    end;
    if (EventCount<>Result.FSourceEvents) or ((EventCount>0) and (PreviousMember<>Volley-1)) then raise Exception.Create('Incomplete firework events.');
    if Abs(Result.FEndTime-ComputedEnd)>1E-6 then raise Exception.Create('Invalid fireworks tail.');
  except FreeAndNil(Result);Root.Free;raise;end;Root.Free;
end;
end.
