unit RhythmProduct;
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
  if (Id<>'SYNC_RhythmShooter') and (Id<>'SYNC_RhythmBall') and (Id<>'SYNC_RhythmFireworks') then raise EArgumentException.Create('Unknown product identity.');
  GId:=Id;GTitle:=Title;GStyle:=InitialStyle;
end;
function ProductId:string;begin Result:=GId;end;
function ProductTitle:string;begin Result:=GTitle;end;
function ProductDefaultStyle:TRhythmStyle;begin Result:=GStyle;end;
end.
