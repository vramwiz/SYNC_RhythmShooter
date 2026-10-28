unit RhythmDesignTypes;
interface
const RHYTHM_DESIGN_COUNT=15;
type
  TRhythmDesign=record
    Path,SHA256,Memo:string;
  end;
  TRhythmDesigns=array[0..RHYTHM_DESIGN_COUNT-1] of TRhythmDesign;
  TRhythmDesignInfo=record
    Id,Title,Brief,Orientation:string;
    Width,Height:Integer;
    Background:Boolean;
  end;
function DesignInfo(Index:Integer):TRhythmDesignInfo;
function DesignIndex(const Id:string):Integer;
function DesignKey(const Designs:TRhythmDesigns):string;
function DesignContext(Index:Integer;const Design:TRhythmDesign):string;
function ValidDesignReference(const Path,Digest:string):Boolean;
implementation
uses System.SysUtils,System.Hash;
function DesignInfo(Index:Integer):TRhythmDesignInfo;
const Names:array[0..14] of string=('vertical_layer0','vertical_layer1','vertical_layer2','horizontal_layer0','horizontal_layer1','horizontal_layer2','player_vertical','player_horizontal','enemy','boss0','boss1','bullet','explosion','enemy1','enemy2');
  Titles:array[0..14] of string=('縦・遠景','縦・中景','縦・近景','横・遠景','横・中景','横・近景','自機（縦）','自機（横）','通常敵 A','中ボス','大ボス','弾丸・弾幕','爆発','通常敵 B','通常敵 C');
begin
  if (Index<0) or (Index>=RHYTHM_DESIGN_COUNT) then raise EArgumentOutOfRangeException.Create('素材の番号が範囲外です。');
  Result:=Default(TRhythmDesignInfo);Result.Id:=Names[Index];Result.Title:=Titles[Index];Result.Background:=Index<6;
  Result.Width:=256;Result.Height:=256;Result.Orientation:='上が前方。中心を描画原点とし、十分な透明余白を付ける。';
  if Index<6 then begin
    Result.Width:=1024;Result.Height:=1024;
    if Index<3 then Result.Orientation:='上下の端が自然につながる縦スクロール用シームレス画像。'
    else Result.Orientation:='左右の端が自然につながる横スクロール用シームレス画像。';
    if Index mod 3=0 then Result.Brief:='暗い宇宙の遠景。背景は不透明。小さな星や淡い星雲。'
    else Result.Brief:='透過背景の疎らな宇宙の光点。下の層と弾幕が見える密度。';
  end else case Index of
    6:Result.Brief:='独自デザインの青いプレイヤー宇宙機。真上を向いた上面図。';
    7:begin Result.Brief:='独自デザインの青いプレイヤー宇宙機。';Result.Orientation:='右が前方。横スクロール用。中心を描画原点とする。';end;
    8:Result.Brief:='独自デザインの赤い通常敵宇宙機。下向き。';
    9,10:begin Result.Width:=512;Result.Height:=320;Result.Brief:='独自デザインの大きな敵宇宙機。下向き。左右に広い機体。';if Index=10 then Result.Brief:=Result.Brief+' 最終ボスにふさわしい力強い外観。';end;
    11:begin Result.Width:=64;Result.Height:=96;Result.Brief:='緑がかったシアンの見やすい発光弾。背景の青い星と区別できる形。';end;
    12:begin Result.Width:=256;Result.Height:=256;Result.Brief:='オレンジ色の爆発・閃光を1枚。中心から広がる独自エフェクト。';Result.Orientation:='正方形、中央原点。';end;
    13:Result.Brief:='独自デザインの紫の六角形に近い通常敵宇宙機。下向き。';
    14:Result.Brief:='独自デザインの金色の鋭い通常敵宇宙機。下向き。';
  end;
  if Index in [8,9,10,11,13,14] then Result.Orientation:='縦では下向き（弾丸は縦長）。横モードではアプリが90度回転するので、横向き版を混在させない。中心原点。';
end;
function DesignIndex(const Id:string):Integer;
begin for Result:=0 to RHYTHM_DESIGN_COUNT-1 do if DesignInfo(Result).Id=Id then Exit;Result:=-1;end;
function DesignKey(const Designs:TRhythmDesigns):string;
var I:Integer;Text:string;
begin Text:='';for I:=0 to High(Designs) do if Designs[I].Path<>'' then Text:=Text+IntToStr(I)+':'+Designs[I].Path+'|'+Designs[I].SHA256+';';Result:='';if Text<>'' then Result:=THashSHA2.GetHashString(Text);end;
function DesignContext(Index:Integer;const Design:TRhythmDesign):string;
begin Result:=THashSHA2.GetHashString(IntToStr(Index)+'|'+Design.Path+'|'+Design.SHA256+'|'+Design.Memo);end;
function ValidDesignReference(const Path,Digest:string):Boolean;
var I:Integer;
begin
  Result:=False;if (Path='') and (Digest='') then Exit(True);
  if Length(Digest)<>64 then Exit;for I:=1 to 64 do if not CharInSet(Digest[I],['0'..'9','a'..'f','A'..'F']) then Exit;
  Result:=SameText(Path,'DesignAssets\'+Digest+'.png');
end;
end.
