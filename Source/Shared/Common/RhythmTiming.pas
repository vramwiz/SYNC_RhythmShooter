unit RhythmTiming;
// 描画だけの秒オフセット。解析/保存Plan/音声時計はずらさず、毎フレーム絶対時刻から求める。
interface
function NormalizeRenderOffset(Seconds:Double):Double;
// 負値のoffsetは未来の絵を先行表示し、正値は遅延。負の戻り時刻は開始前の透明フレーム。
function AnimationTime(ObjectTime,OffsetSeconds:Double):Double;
implementation
uses System.Math;
function NormalizeRenderOffset(Seconds:Double):Double;
begin if IsNan(Seconds) or IsInfinite(Seconds) then Exit(0);Result:=EnsureRange(Seconds,-1.0,1.0);end;
function AnimationTime(ObjectTime,OffsetSeconds:Double):Double;
begin if IsNan(ObjectTime) or IsInfinite(ObjectTime) then Exit(-1);Result:=ObjectTime-NormalizeRenderOffset(OffsetSeconds);end;
end.
