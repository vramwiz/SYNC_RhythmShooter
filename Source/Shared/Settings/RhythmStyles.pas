unit RhythmStyles;
interface
type TRhythmStyle=(rsShooting,rsBall,rsFireworks);
function StyleId(Style:TRhythmStyle):string;
function StyleTitle(Style:TRhythmStyle):string;
function TryStyle(const Id:string;out Style:TRhythmStyle):Boolean;
function StylePlanVersion(Style:TRhythmStyle):Integer;
function CompatiblePlanVersion(Style:TRhythmStyle;Version:Integer):Boolean;
function StyleVariant(Style:TRhythmStyle;FireworksRichness:Integer):Integer;
const FIREWORKS_DEFAULT_RICHNESS=50;
implementation
function StyleId(Style:TRhythmStyle):string;
begin case Style of rsBall:Result:='ball';rsFireworks:Result:='fireworks';else Result:='shooting';end;end;
function StyleTitle(Style:TRhythmStyle):string;
begin case Style of rsBall:Result:='ボール（ピンボール）';rsFireworks:Result:='花火';else Result:='シューティング';end;end;
function TryStyle(const Id:string;out Style:TRhythmStyle):Boolean;
begin Style:=rsShooting;Result:=True;if Id='shooting' then Exit;if Id='ball' then begin Style:=rsBall;Exit;end;if Id='fireworks' then begin Style:=rsFireworks;Exit;end;Result:=False;end;
function StylePlanVersion(Style:TRhythmStyle):Integer;
begin case Style of rsBall:Result:=5;rsFireworks:Result:=2;else Result:=1;end;end;
function CompatiblePlanVersion(Style:TRhythmStyle;Version:Integer):Boolean;
begin Result:=(Version=StylePlanVersion(Style)) or ((Style=rsBall) and (Version=4));end;
function StyleVariant(Style:TRhythmStyle;FireworksRichness:Integer):Integer;
begin Result:=0;if Style=rsFireworks then begin Result:=FireworksRichness;if Result<0 then Result:=0;if Result>100 then Result:=100;end;end;
end.
