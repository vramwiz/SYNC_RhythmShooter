unit RhythmPlanRef;
// A small saved reference identifies prepared animation data, never decoded PCM.
interface
uses RhythmStyles;
type TRhythmPlanRef=record
  Key,SourceKey,Digest,SourceRevision,Generation:string;
  Style:TRhythmStyle;
  Version,Sensitivity,Direction,Variant,AudioDensity:Integer;
  function Matches(const AudioKey:string;ASensitivity,ADirection:Integer;
    AStyle:TRhythmStyle;AVariant:Integer=0):Boolean;
end;
function ValidDigest(const Value:string):Boolean;
function AnimationPlanKey(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant:Integer=0;Density:Integer=0;const Generation:string=''):string;
function NewPlanRef(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant:Integer=0;Density:Integer=0;const Generation:string=''):TRhythmPlanRef;
implementation
uses System.SysUtils,System.Hash;
function ValidDigest(const Value:string):Boolean;
var I:Integer;
begin Result:=False;if Length(Value)<>64 then Exit;for I:=1 to 64 do if not CharInSet(Value[I],['0'..'9','a'..'f','A'..'F']) then Exit;Result:=True;end;
function PlanKeyForVersion(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant,Version,Density:Integer;const Generation:string):string;
var Recipe:string;
begin
  Recipe:=StyleId(Style)+'-v'+IntToStr(Version)+'|'+SourceKey+'|'+IntToStr(Sensitivity)+'|'+IntToStr(Direction);
  // Variant zero preserves the accepted Shooting cache recipe byte for byte.
  if Variant<>0 then Recipe:=Recipe+'|variant='+IntToStr(Variant);
  if Density<>0 then Recipe:=Recipe+'|density='+IntToStr(Density);
  if Generation<>'' then Recipe:=Recipe+'|generation='+Generation;
  Result:=THashSHA2.GetHashString(Recipe);
end;
function AnimationPlanKey(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant,Density:Integer;const Generation:string):string;
begin Result:=PlanKeyForVersion(SourceKey,Sensitivity,Direction,Style,Variant,StylePlanVersion(Style),Density,Generation);end;
function NewPlanRef(const SourceKey:string;Sensitivity,Direction:Integer;
  Style:TRhythmStyle;Variant,Density:Integer;const Generation:string):TRhythmPlanRef;
begin
  Result:=Default(TRhythmPlanRef);Result.SourceKey:=SourceKey;Result.Style:=Style;
  Result.Version:=StylePlanVersion(Style);Result.Sensitivity:=Sensitivity;
  Result.Direction:=Direction;Result.Variant:=Variant;Result.AudioDensity:=Density;
  Result.Generation:=Generation;
  Result.Key:=AnimationPlanKey(SourceKey,Sensitivity,Direction,Style,Variant,Density,Generation);
end;
function TRhythmPlanRef.Matches(const AudioKey:string;ASensitivity,ADirection:Integer;
  AStyle:TRhythmStyle;AVariant:Integer):Boolean;
begin
  Result:=ValidDigest(Key) and (SourceKey=AudioKey) and (Sensitivity=ASensitivity) and
    (Direction=ADirection) and (Style=AStyle) and CompatiblePlanVersion(AStyle,Version) and
    (Variant=AVariant) and ((AudioDensity=0) or ((AudioDensity>=1) and (AudioDensity<=201) and
      (AudioDensityKey(AStyle,AudioDensity-101)=AudioDensity))) and
    ((Generation='') or ((AStyle=rsJumpAdventure) and ValidDigest(Generation))) and
    (Key=PlanKeyForVersion(AudioKey,ASensitivity,ADirection,AStyle,AVariant,Version,AudioDensity,Generation));
end;
end.
