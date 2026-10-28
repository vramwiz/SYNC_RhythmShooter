unit RhythmSettings;
interface
type
  TRhythmSettings=record
    Music:string;
    Direction,Sensitivity:Integer;
    Zoom,X,Y:Double;
    class function Defaults:TRhythmSettings;static;
    function ToJSON:string;
    class function TryJSON(const Text:string;out Value:TRhythmSettings):Boolean;static;
  end;
implementation
uses System.SysUtils,System.JSON,System.Math;
class function TRhythmSettings.Defaults:TRhythmSettings;
begin Result.Music:='';Result.Direction:=0;Result.Sensitivity:=50;Result.Zoom:=100;Result.X:=0;Result.Y:=0;end;
function TRhythmSettings.ToJSON:string;
var J:TJSONObject;
begin
  J:=TJSONObject.Create;try J.AddPair('schema',TJSONNumber.Create(1));J.AddPair('music',Music);J.AddPair('direction',TJSONNumber.Create(Direction));J.AddPair('sensitivity',TJSONNumber.Create(Sensitivity));J.AddPair('zoom',TJSONNumber.Create(Zoom));J.AddPair('x',TJSONNumber.Create(X));J.AddPair('y',TJSONNumber.Create(Y));Result:=J.ToJSON;finally J.Free;end;
end;
class function TRhythmSettings.TryJSON(const Text:string;out Value:TRhythmSettings):Boolean;
var J:TJSONValue;O:TJSONObject;
begin
  Value:=Defaults;Result:=False;J:=nil;
  try
    try J:=TJSONObject.ParseJSONValue(Text);if not (J is TJSONObject) then Exit;O:=TJSONObject(J);
      if O.GetValue<Integer>('schema',0)<>1 then Exit;
      Value.Music:=O.GetValue<string>('music','');Value.Direction:=EnsureRange(O.GetValue<Integer>('direction',0),0,1);Value.Sensitivity:=EnsureRange(O.GetValue<Integer>('sensitivity',50),1,100);
      Value.Zoom:=O.GetValue<Double>('zoom',100);Value.X:=O.GetValue<Double>('x',0);Value.Y:=O.GetValue<Double>('y',0);
      if IsNan(Value.Zoom) or IsInfinite(Value.Zoom) or IsNan(Value.X) or IsInfinite(Value.X) or IsNan(Value.Y) or IsInfinite(Value.Y) then Exit;
      Value.Zoom:=EnsureRange(Value.Zoom,1.0,400.0);Result:=True;
    except Result:=False;end;
  finally J.Free;if not Result then Value:=Defaults;end;
end;
end.
