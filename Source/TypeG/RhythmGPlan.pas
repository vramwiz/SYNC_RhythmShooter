unit RhythmGPlan;
// Type.Gの全曲シーン・音時刻と編集契約。秒は原音声の絶対時刻、拍は推定4拍子。
interface
uses System.SysUtils, RhythmAudio;
type
  TGEnding = (gePose, geSuccess, geContinue);
  TGScene = record
    Start, Finish, ActionStart, ActionEnd: Double;
    Game, Transition: Integer;
  end;
  TGCue = record
    Time, Lead, Recover, Power: Double;
    Scene, Action, Source: Integer;
  end;
  TGPlan = class
  public
    Duration, Beat, Origin: Double;
    Transitions: Boolean;
    Scenes: TArray<TGScene>;
    Cues: TArray<TGCue>;
    function SceneAt(Time: Double): Integer;
    function CueAt(Time: Double): Integer;
    function Clone: TGPlan;
    procedure Validate;
    // 編集は連続した全曲区間を保つ。拒否時は元の構成を変更しない。
    procedure Bounds(Index: Integer; AStart, AFinish: Double);
    procedure Split(Index: Integer; Time: Double);
    procedure Merge(Index: Integer);
    procedure Delete(Index: Integer);
    // 4拍子x4小節を1区間にする。既存のゲーム順を保持し、余りを削除・不足を補充する。
    procedure Regrid(BPM: Double; Audio: TRhythmAudio);
    procedure RebuildCues(Audio: TRhythmAudio; const Cancel: TFunc<Boolean> = nil);
  end;
const
  GNames: array[0..31] of string = (
    'ハンコ職人','洗濯物キャッチ','目覚まし大作戦','料理長のフライパン',
    '回転寿司の達人','歯車時計の修理屋','宅配仕分け名人','床屋のチョキチョキ',
    'ペンギンの氷渡り','カエルの合唱団','モグラの引っ越し','タコの太鼓叩き',
    'カニの横歩き競争','ヒヨコの行進','クラゲの電気ダンス','ハチの花粉集め',
    '卓球ロボット','縄跳び名人','ボクシング人形','空中ブランコ',
    'サッカーの壁','忍者の手裏剣修行','バランス一輪車','風船バレー',
    'ロボット組立工場','宇宙人の交信','おばけのかくれんぼ','魔法使いの変身術',
    'ゼリーの大行進','工事現場の鉄球','巨大ロボの足踏み','ピタゴラ装置の連鎖');
function GActionCount(Game: Integer): Integer;
function GEnding(Game: Integer): TGEnding;
function BuildGPlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean> = nil): TGPlan;
implementation
uses System.Math, System.Generics.Collections;

function GActionCount(Game: Integer): Integer;
begin
  if Game=5 then Result:=1 else if Game=18 then Result:=3 else Result:=2;
end;

function GEnding(Game: Integer): TGEnding;
begin
  case Game of
    0,5,6,7,15,24,27,29,31: Result:=geSuccess;
    8,12,13,17,19,22,28,30: Result:=geContinue;
    else Result:=gePose;
  end;
end;

function TGPlan.SceneAt(Time: Double): Integer;
var L,R,M: Integer;
begin
  L:=0; R:=Length(Scenes);
  while L<R do begin M:=(L+R) div 2; if Scenes[M].Finish<=Time then L:=M+1 else R:=M; end;
  Result:=Min(L,High(Scenes));
end;

function TGPlan.CueAt(Time: Double): Integer;
var L,R,M: Integer;
begin
  L:=0; R:=Length(Cues);
  while L<R do begin M:=(L+R) div 2; if Cues[M].Time<=Time then L:=M+1 else R:=M; end;
  Result:=L-1;
end;

function TGPlan.Clone: TGPlan;
begin
  Result:=TGPlan.Create; Result.Duration:=Duration; Result.Beat:=Beat; Result.Origin:=Origin;
  Result.Transitions:=Transitions; Result.Scenes:=Copy(Scenes); Result.Cues:=Copy(Cues);
end;

procedure Require(B: Boolean; const Why: string);
begin if not B then raise EConvertError.Create('Type.G: '+Why); end;

function Finite(V: Double): Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V); end;

procedure TGPlan.Validate;
var I: Integer; S: TGScene; C: TGCue; Last,LastFinish: Double;
begin
  Require(Finite(Duration) and (Duration>0) and (Duration<=7200),'音声長');
  Require(Finite(Beat) and InRange(Beat,0.25,1.0) and Finite(Origin) and InRange(Origin,0.0,Beat),'拍');
  Require(InRange(Length(Scenes),1,2048),'シーン数'); Last:=0;
  for S in Scenes do begin
    Require(Finite(S.Start) and Finite(S.Finish) and Finite(S.ActionStart) and Finite(S.ActionEnd),'時刻');
    Require((S.Start=Last) and (S.Finish>S.Start) and (S.Finish<=Duration),'区間の連続性');
    Require((S.ActionStart>S.Start) and (S.ActionEnd>=S.ActionStart) and (S.ActionEnd<S.Finish),'導入・終了期間');
    Require(InRange(S.Game,0,31) and InRange(S.Transition,0,5),'ゲーム・切替'); Last:=S.Finish;
  end;
  Require(Last=Duration,'曲終端'); Require(Length(Cues)<=100000,'イベント数');
  Last:=-1; LastFinish:=-1;
  for I:=0 to High(Cues) do begin
    C:=Cues[I]; Require(InRange(C.Scene,0,High(Scenes)),'イベントのシーン'); S:=Scenes[C.Scene];
    Require(Finite(C.Time) and Finite(C.Lead) and Finite(C.Recover) and Finite(C.Power),'動作時刻');
    Require((C.Time>Last) and InRange(C.Lead,0.04,0.65) and InRange(C.Recover,0.04,0.65) and
      (C.Time-C.Lead>=S.ActionStart-1E-8) and (C.Time+C.Recover<=S.ActionEnd+1E-8),'動作の収容');
    Require((C.Time-C.Lead>=LastFinish-1E-8) and InRange(C.Power,0.0,1.0) and
      InRange(C.Action,0,GActionCount(S.Game)-1) and (C.Source>=0),'動作重複・種類');
    Last:=C.Time; LastFinish:=C.Time+C.Recover;
  end;
end;

procedure TGPlan.Bounds(Index: Integer; AStart, AFinish: Double);
begin
  Require(InRange(Index,0,High(Scenes)),'選択');
  Require(Finite(AStart) and Finite(AFinish),'編集時刻');
  if Index=0 then Require(AStart=0,'先頭は0秒')
  else Require(AStart>=Scenes[Index-1].Start+0.25,'前のシーンは0.25秒以上');
  if Index=High(Scenes) then Require(AFinish=Duration,'最後は曲終端')
  else Require(AFinish<=Scenes[Index+1].Finish-0.25,'次のシーンは0.25秒以上');
  Require((AFinish-AStart>=0.25) and (AStart>=0) and (AFinish<=Duration),'シーンは0.25秒以上');
  Scenes[Index].Start:=AStart; Scenes[Index].Finish:=AFinish;
  if Index>0 then Scenes[Index-1].Finish:=AStart;
  if Index<High(Scenes) then Scenes[Index+1].Start:=AFinish;
end;

procedure TGPlan.Split(Index: Integer; Time: Double);
var I,N: Integer;
begin
  Require(InRange(Index,0,High(Scenes)) and Finite(Time),'分割位置');
  Require(Length(Scenes)<2048,'シーン数上限');
  Require((Time>=Scenes[Index].Start+0.25) and (Time<=Scenes[Index].Finish-0.25),'分割後は各0.25秒以上');
  N:=Length(Scenes); SetLength(Scenes,N+1);
  for I:=N downto Index+2 do Scenes[I]:=Scenes[I-1];
  Scenes[Index+1]:=Scenes[Index]; Scenes[Index+1].Start:=Time;
  Scenes[Index+1].Game:=(Scenes[Index].Game+11) mod 32;
  Scenes[Index+1].Transition:=(Scenes[Index].Transition+1) mod 6;
  Scenes[Index].Finish:=Time;
end;

procedure TGPlan.Merge(Index: Integer);
var I: Integer;
begin
  Require(InRange(Index,0,High(Scenes)-1),'次のシーンがありません');
  Scenes[Index].Finish:=Scenes[Index+1].Finish;
  for I:=Index+1 to High(Scenes)-1 do Scenes[I]:=Scenes[I+1];
  SetLength(Scenes,Length(Scenes)-1);
end;

procedure TGPlan.Delete(Index: Integer);
var I: Integer;
begin
  Require((Length(Scenes)>1) and InRange(Index,0,High(Scenes)),'最後の1シーンは削除できません');
  if Index>0 then Merge(Index-1)
  else begin
    Scenes[1].Start:=0;
    for I:=0 to High(Scenes)-1 do Scenes[I]:=Scenes[I+1];
    SetLength(Scenes,Length(Scenes)-1);
  end;
end;

procedure TGPlan.RebuildCues(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>);
var List: TList<TGCue>; I,J,K,N,A: Integer; S: TGScene; C: TGCue;
  Span,Intro,Outro,LastFinish,Lead,Recover: Double;
begin
  Require(Audio<>nil,'解析情報がありません');
  List:=TList<TGCue>.Create;
  try
    J:=0; LastFinish:=-1;
    for I:=0 to High(Scenes) do begin
      if Assigned(Cancel) and Cancel() then Abort;
      S:=Scenes[I]; Span:=S.Finish-S.Start;
      // 標準2小節。短区間は拍単位で縮め、最後に回復動作と終了の余白を残す。
      N:=8; if Span<12*Beat then N:=4; if Span<7*Beat then N:=2;
      Intro:=Min(N*Beat,Span*0.50); Outro:=Min(Beat*1.5,Span*0.18);
      S.ActionStart:=S.Start+Intro; S.ActionEnd:=S.Finish-Outro; Scenes[I]:=S;
      Lead:=Min(0.34,Beat*0.50); Recover:=Min(0.30,Beat*0.44); N:=0;
      while (J<Length(Audio.Hits)) and (Audio.Hits[J].Time<S.ActionStart) do Inc(J);
      K:=J;
      while (K<Length(Audio.Hits)) and (Audio.Hits[K].Time<=S.ActionEnd) do begin
        C.Time:=Audio.Hits[K].Time;
        C.Lead:=Lead; C.Recover:=Recover; C.Scene:=I; C.Source:=K;
        C.Power:=EnsureRange(Audio.Hits[K].Strength,0.0,1.0);
        // 強弱とフレーズの順を合わせる。長い声・信号・連打は回復尺も延ばす。
        A:=N mod GActionCount(S.Game);
        if (GActionCount(S.Game)=2) and (N mod 4=3) then A:=Ord(C.Power>=0.65);
        C.Action:=A;
        if (S.Game=16) and (A=1) then C.Lead:=Lead*0.70;
        if (S.Game in [9,11,14,25]) and (A=1) then C.Recover:=Min(0.65,Beat*0.9);
        if (C.Time-C.Lead>=S.ActionStart) and (C.Time+C.Recover<=S.ActionEnd) and
          (C.Time-C.Lead>=LastFinish+Beat*0.12) then begin
          List.Add(C); Inc(N); LastFinish:=C.Time+C.Recover;
        end;
        Inc(K);
      end;
      J:=K;
    end;
    Cues:=List.ToArray; Validate;
  finally List.Free; end;
end;

procedure TGPlan.Regrid(BPM: Double; Audio: TRhythmAudio);
var Old: TArray<TGScene>; S: TGScene; T,Grid: Double; I,N,J,Game: Integer; Used: array[0..31] of Integer;
begin
  Require(Finite(BPM) and InRange(BPM,60.0,240.0),'BPMは60〜240で入力してください');
  Old:=Copy(Scenes); Beat:=60/BPM; Origin:=0; Grid:=16*Beat;
  N:=Max(1,Ceil(Duration/Grid-1E-10)); Require(N<=2048,'シーン数上限');
  // 数十msだけ別のゲームが点滅しないよう、ごく短い曲末端数は直前の場面に含める。
  if (N>1) and (Duration-(N-1)*Grid<Min(1.0,2*Beat)) then Dec(N);
  SetLength(Scenes,N); for J:=0 to 31 do Used[J]:=-100; T:=0;
  for I:=0 to N-1 do begin
    S:=Default(TGScene); S.Start:=T; S.Finish:=Min(Duration,(I+1)*Grid);
    if I=High(Scenes) then S.Finish:=Duration;
    if I<Length(Old) then begin S.Game:=Old[I].Game; S.Transition:=Old[I].Transition; end
    else begin
      Game:=-1;
      for J:=0 to 31 do if ((I=0) or (J<>Scenes[I-1].Game)) and
        ((Game<0) or (Used[J]<Used[Game])) then Game:=J;
      S.Game:=Game; S.Transition:=I mod 6;
    end;
    Used[S.Game]:=I; Scenes[I]:=S; T:=S.Finish;
  end;
  RebuildCues(Audio);
end;

procedure EstimateBeat(Audio: TRhythmAudio; out Beat,Origin: Double);
var B,I,N,Best: Integer; Dt,Score,BestScore,Phase,Peak: Double;
begin
  Beat:=0.5; Origin:=0; BestScore:=-1; Best:=120;
  // 元の解析の実音時刻を60〜180 BPMの格子へ照合。無音は120 BPMの常時動作だけを使う。
  N:=Min(Length(Audio.Hits),2400);
  if N<2 then Exit;
  for B:=60 to 180 do begin
    Dt:=60/B; Score:=0;
    for I:=1 to N-1 do begin
      Phase:=(Audio.Hits[I].Time-Audio.Hits[I-1].Time)/Dt;
      Score:=Score+Max(0.0,1-Abs(Phase-Round(Phase))*5)*(0.2+Audio.Hits[I].Strength);
    end;
    Score:=Score*(1-Abs(B-120)*0.0008);
    if Score>BestScore then begin BestScore:=Score; Best:=B; end;
  end;
  Beat:=60/Best; Peak:=-1;
  for B:=0 to 31 do begin
    Score:=0;
    for I:=0 to N-1 do begin
      Phase:=(Audio.Hits[I].Time-B*Beat/32)/Beat;
      Score:=Score+Max(0.0,1-Abs(Phase-Round(Phase))*8)*Audio.Hits[I].Strength;
    end;
    if Score>Peak then begin Peak:=Score; Origin:=B*Beat/32; end;
  end;
end;

function BuildGPlan(Audio: TRhythmAudio; const Cancel: TFunc<Boolean>): TGPlan;
var L: TList<TGScene>; S: TGScene; I,J,Count,Game,Previous: Integer;
  T,Cost,BestCost,Grid: Double;
  Used: array[0..31] of Integer;
begin
  Require((Audio<>nil) and Finite(Audio.Duration) and (Audio.Duration>0),'音源');
  Result:=TGPlan.Create; L:=TList<TGScene>.Create;
  try
    try
      Result.Duration:=Audio.Duration; Result.Transitions:=True;
      EstimateBeat(Audio,Result.Beat,Result.Origin); Grid:=16*Result.Beat;
      // 4拍子の4小節を1グリッドにする。最初の拍の位相は常時動作に使い、区間は0秒起点。
      Count:=Max(1,Ceil(Audio.Duration/Grid-1E-10)); T:=0; Previous:=-1;
      if (Count>1) and (Audio.Duration-(Count-1)*Grid<Min(1.0,2*Result.Beat)) then Dec(Count);
      for I:=0 to 31 do Used[I]:=-100;
      for I:=0 to Count-1 do begin
        if Assigned(Cancel) and Cancel() then Abort;
        S:=Default(TGScene); S.Start:=T;
        S.Finish:=Min(Audio.Duration,(I+1)*Grid);
        if I=Count-1 then S.Finish:=Audio.Duration;
        Game:=-1; BestCost:=1E99;
        for J:=0 to 31 do begin
          if J=Previous then Continue;
          // 未登場を最優先にし、同じ分類・主動作が隣り合う候補へ小さなペナルティを付ける。
          Cost:=Used[J]*1000+((J-I*11+1024) mod 32);
          if Previous>=0 then begin
            if J div 8=Previous div 8 then Cost:=Cost+100;
            if J mod 4=Previous mod 4 then Cost:=Cost+60;
          end;
          if Cost<BestCost then begin BestCost:=Cost; Game:=J; end;
        end;
        if Game<0 then Game:=(Previous+11) mod 32;
        S.Game:=Game; Used[Game]:=I; Previous:=Game; S.Transition:=I mod 6;
        L.Add(S); T:=S.Finish;
      end;
      Result.Scenes:=L.ToArray; Result.RebuildCues(Audio,Cancel);
    except Result.Free; raise; end;
  finally L.Free; end;
end;
end.
