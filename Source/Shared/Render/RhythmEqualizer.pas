unit RhythmEqualizer;
// 全スタイル共通の音反応バー。保存済みイベントだけを読み、FFTやPCM解析は描画で行わない。
interface
uses RhythmAudio,RhythmRenderSurface;
type
  TEqualizerActivity=record
    Valid:Boolean;
    Pulse,Energy:Double;
    Hit,Hue:Integer;
  end;
function EqualizerActivity(Audio:TRhythmAudio;Time:Double):TEqualizerActivity;
// 正規化された反応から最大32本を描画。再生履歴やシーク順を保持しない。
procedure DrawEqualizer(Surface:TAnimationRenderSurface;W,H:Integer;const Activity:TEqualizerActivity;FullHeight:Boolean=False);
implementation
uses System.Math,Winapi.Windows,Vcl.Graphics;
function EqualizerActivity(Audio:TRhythmAudio;Time:Double):TEqualizerActivity;
var L,R,M,I:Integer;NowTick,HitTick:Int64;Delta,Strength:Double;
begin
  Result:=Default(TEqualizerActivity);
  if (Audio=nil) or not Audio.HasHitDetails or (Length(Audio.Hits)=0) or (Time<0) or (Time>Audio.Duration) then Exit;
  // 古い十進JSON由来の微小差を表示メーターだけ1usに揃える。計画の命中時刻は変更しない。
  NowTick:=Round(Time*1000000);L:=0;R:=Length(Audio.Hits);
  while L<R do begin M:=L+(R-L) div 2;
    if Round(Audio.Hits[M].Time*1000000)<=NowTick then L:=M+1 else R:=M;
  end;
  Result.Valid:=True;Result.Hit:=L-1;Result.Hue:=Max(0,Result.Hit) div 12 mod 8;
  for I:=Result.Hit downto Max(0,Result.Hit-12) do begin
    HitTick:=Round(Audio.Hits[I].Time*1000000);Delta:=(NowTick-HitTick)/1000000;
    if Delta>0.8 then Break;Strength:=EnsureRange(Round(Audio.Hits[I].Strength*1000000)/1000000,0.0,1.0);
    if Delta>=0 then Result.Pulse:=Result.Pulse+Exp(-Delta*9)*(0.25+Strength*0.75);
    Result.Energy:=Max(Result.Energy,Strength*Exp(-Delta*3));
  end;
  Result.Pulse:=EnsureRange(Result.Pulse,0.0,1.4);
end;
function Noise(Index,Salt:Cardinal):Double;
var V:Cardinal;
begin V:=Cardinal((UInt64(Index+1)*747796405+UInt64(Salt)*2891336453) and $FFFFFFFF);
  V:=Cardinal((UInt64(V xor (V shr 16))*2246822519) and $FFFFFFFF);Result:=((V xor (V shr 13)) shr 8)/16777216.0;
end;
function Tint(Position:Double):TColor;
const Colors:array[0..6] of TColor=($004F5AFF,$0044AAFF,$0060E8FA,$007CEB71,$00E6D34B,$00FF9867,$00E66EE9);
var I:Integer;U:Double;A,B:Cardinal;
begin U:=EnsureRange(Position,0.0,1.0)*6;I:=Min(5,Floor(U));U:=U-I;A:=Colors[I];B:=Colors[I+1];
  Result:=RGB(Round(GetRValue(A)*(1-U)+GetRValue(B)*U),Round(GetGValue(A)*(1-U)+GetGValue(B)*U),Round(GetBValue(A)*(1-U)+GetBValue(B)*U));
end;
procedure DrawEqualizer(Surface:TAnimationRenderSurface;W,H:Integer;const Activity:TEqualizerActivity;FullHeight:Boolean);
var I:Integer;X,Bar,Pulse,Base,Height:Double;
begin
  if not Activity.Valid or (W<1) or (H<1) then Exit;Pulse:=Min(1.0,Activity.Pulse);
  // 下端の約5%だけを使い、主役や共通進行バーを隠す大きなパネルは置かない。
  Base:=0.004;Height:=0.044;if FullHeight then begin Base:=0.015;Height:=0.80;end;
  for I:=0 to 31 do begin X:=W*(0.07+I*0.027);
    Bar:=H*(Base+Height*Pulse)*(0.25+Noise(I,Cardinal(Max(0,Activity.Hit)))*0.75);
    Surface.FillRect(X,H*0.948-Bar,X+W*0.012,H*0.948,Tint(I/31),0.20+0.25*Pulse);
  end;
end;
end.
