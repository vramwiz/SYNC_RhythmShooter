unit RhythmProduct;
// 製品識別と既定スタイル・設定名を管理し、製品間の保存先を分ける。
interface
uses RhythmStyles;
procedure ConfigureRhythmProduct(const Id,Title:string;InitialStyle:TRhythmStyle);
function ProductId:string;
function ProductTitle:string;
function ProductDefaultStyle:TRhythmStyle;
implementation
uses System.SysUtils;
var GId:string='SYNC_RhythmShooter';GTitle:string='リズムシューティング';GStyle:TRhythmStyle=rsShooting;
procedure ConfigureRhythmProduct(const Id,Title:string;InitialStyle:TRhythmStyle);
begin
  if (Id<>'SYNC_RhythmShooter') and (Id<>'SYNC_RhythmBall') and (Id<>'SYNC_RhythmFireworks') and (Id<>'SYNC_RhythmRunner') and (Id<>'SYNC_RhythmBreakout') and (Id<>'SYNC_RhythmBombAction') and (Id<>'SYNC_RhythmMining') and (Id<>'SYNC_RhythmTrain') and (Id<>'SYNC_RhythmNaval') and (Id<>'SYNC_RhythmGame') then raise EArgumentException.Create('Unknown product identity.');
  GId:=Id;GTitle:=Title;GStyle:=InitialStyle;
end;
function ProductId:string;begin Result:=GId;end;
function ProductTitle:string;begin Result:=GTitle;end;
function ProductDefaultStyle:TRhythmStyle;begin Result:=GStyle;end;
end.
