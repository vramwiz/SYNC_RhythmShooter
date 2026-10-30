unit RhythmPlanRef;
// A small saved reference identifies prepared animation data, never decoded PCM.
interface
uses RhythmStyles;
type TRhythmPlanRef=record
  Key,SourceKey,Digest,SourceRevision:string;
  Style:TRhythmStyle;
  Version,Sensitivity,Direction,Variant:Integer;
  function Matches(const AudioKey:string;ASensitivity,ADirection:Integer;
    AStyle:TRhythmStyle;AVariant:Integer=0):Boolean;
end;
function ValidDigest(const Value:string):Boolean;
function AnimationPlanKey(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant:Integer=0):string;
function NewPlanRef(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant:Integer=0):TRhythmPlanRef;
implementation
uses System.SysUtils,System.Hash;
function ValidDigest(const Value:string):Boolean;
var I:Integer;
begin Result:=False;if Length(Value)<>64 then Exit;for I:=1 to 64 do if not CharInSet(Value[I],['0'..'9','a'..'f','A'..'F']) then Exit;Result:=True;end;
function PlanKeyForVersion(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant,Version:Integer):string;
var Recipe:string;
begin
  Recipe:=StyleId(Style)+'-v'+IntToStr(Version)+'|'+SourceKey+'|'+IntToStr(Sensitivity)+'|'+IntToStr(Direction);
  // Variant zero preserves the accepted Shooting cache recipe byte for byte.
  if Variant<>0 then Recipe:=Recipe+'|variant='+IntToStr(Variant);
  Result:=THashSHA2.GetHashString(Recipe);
end;
function AnimationPlanKey(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant:Integer):string;
begin Result:=PlanKeyForVersion(SourceKey,Sensitivity,Direction,Style,Variant,StylePlanVersion(Style));end;
function NewPlanRef(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant:Integer):TRhythmPlanRef;
begin
  Result:=Default(TRhythmPlanRef);Result.SourceKey:=SourceKey;Result.Style:=Style;
  Result.Version:=StylePlanVersion(Style);Result.Sensitivity:=Sensitivity;
  Result.Direction:=Direction;Result.Variant:=Variant;
  Result.Key:=AnimationPlanKey(SourceKey,Sensitivity,Direction,Style,Variant);
end;
function TRhythmPlanRef.Matches(const AudioKey:string;ASensitivity,ADirection:Integer;
  AStyle:TRhythmStyle;AVariant:Integer):Boolean;
begin
  Result:=ValidDigest(Key) and (SourceKey=AudioKey) and (Sensitivity=ASensitivity) and
    (Direction=ADirection) and (Style=AStyle) and CompatiblePlanVersion(AStyle,Version) and
    (Variant=AVariant) and (Key=PlanKeyForVersion(AudioKey,ASensitivity,ADirection,AStyle,AVariant,Version));
end;
end.
