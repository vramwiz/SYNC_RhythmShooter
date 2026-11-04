unit RhythmStyleSelection;
// 大中小の選択状態。フォームやホストに依存せず、最終値は既存のStyle/Directionだけに戻す。
interface
uses RhythmStyles;
type TStyleSelection=record
  Style:TRhythmStyle;
  Direction:Integer;
  class function FromSaved(AStyle:TRhythmStyle;ADirection:Integer):TStyleSelection;static;
  function Group:TRhythmStyleGroup;
  function MiddleIndex:Integer;
  function SmallIndex:Integer;
  procedure ChooseGroup(Value:TRhythmStyleGroup);
  procedure ChooseMiddle(Index:Integer);
  procedure ChooseSmall(Index:Integer);
end;
implementation
uses System.Math;
class function TStyleSelection.FromSaved(AStyle:TRhythmStyle;ADirection:Integer):TStyleSelection;
begin Result.Style:=AStyle;Result.Direction:=EnsureRange(ADirection,0,1);end;
function TStyleSelection.Group:TRhythmStyleGroup;
begin Result:=StyleInfo(Style).Group;end;
function TStyleSelection.MiddleIndex:Integer;
begin Result:=GroupStyleIndex(Style);end;
function TStyleSelection.SmallIndex:Integer;
begin Result:=0;if StyleSmallCount(Style)>1 then Result:=Direction;end;
procedure TStyleSelection.ChooseGroup(Value:TRhythmStyleGroup);
begin if Value<>Group then begin Style:=GroupStyleAt(Value,0);Direction:=0;end;end;
procedure TStyleSelection.ChooseMiddle(Index:Integer);
var Chosen:TRhythmStyle;
begin Chosen:=GroupStyleAt(Group,Index);if Chosen<>Style then begin Style:=Chosen;Direction:=0;end;end;
procedure TStyleSelection.ChooseSmall(Index:Integer);
begin
  // 固定視点は説明だけで、新たなdirection値を作らない。旧保存の隠れた0/1は復元時に保持する。
  if (StyleSmallCount(Style)>1) and (Index>=0) and (Index<StyleSmallCount(Style)) then Direction:=Index;
end;
end.
