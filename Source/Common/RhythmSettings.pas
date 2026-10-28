unit RhythmSettings;
interface
uses RhythmDesignTypes;
type
  TRhythmSettings=record
    Music:string;
    Direction,Sensitivity:Integer;
    Zoom,X,Y:Double;
    Designs:TRhythmDesigns;
    class function Defaults:TRhythmSettings;static;
    function ToJSON:string;
    class function TryJSON(const Text:string;out Value:TRhythmSettings):Boolean;static;
  end;
implementation
uses System.SysUtils,System.JSON,System.Math;
class function TRhythmSettings.Defaults:TRhythmSettings;
begin Result:=Default(TRhythmSettings);Result.Music:='';Result.Direction:=0;Result.Sensitivity:=50;Result.Zoom:=100;Result.X:=0;Result.Y:=0;end;
function TRhythmSettings.ToJSON:string;
var J,Item:TJSONObject;Assets:TJSONArray;I:Integer;
begin
  J:=TJSONObject.Create;try J.AddPair('schema',TJSONNumber.Create(1));J.AddPair('music',Music);J.AddPair('direction',TJSONNumber.Create(Direction));J.AddPair('sensitivity',TJSONNumber.Create(Sensitivity));J.AddPair('zoom',TJSONNumber.Create(Zoom));J.AddPair('x',TJSONNumber.Create(X));J.AddPair('y',TJSONNumber.Create(Y));
    Assets:=TJSONArray.Create;J.AddPair('designs',Assets);
    for I:=0 to High(Designs) do if (Designs[I].Path<>'') or (Designs[I].Memo<>'') then begin
      Item:=TJSONObject.Create;Item.AddPair('id',DesignInfo(I).Id);Item.AddPair('path',Designs[I].Path);Item.AddPair('sha256',Designs[I].SHA256);Item.AddPair('memo',Designs[I].Memo);Assets.AddElement(Item);
    end;
    Result:=J.ToJSON;finally J.Free;end;
end;
class function TRhythmSettings.TryJSON(const Text:string;out Value:TRhythmSettings):Boolean;
var J,V:TJSONValue;O,Item:TJSONObject;Assets:TJSONArray;I:Integer;Seen:array[0..RHYTHM_DESIGN_COUNT-1] of Boolean;
begin
  Value:=Defaults;Result:=False;J:=nil;
  try
    try J:=TJSONObject.ParseJSONValue(Text);if not (J is TJSONObject) then Exit;O:=TJSONObject(J);
      if O.GetValue<Integer>('schema',0)<>1 then Exit;
      Value.Music:=O.GetValue<string>('music','');Value.Direction:=EnsureRange(O.GetValue<Integer>('direction',0),0,1);Value.Sensitivity:=EnsureRange(O.GetValue<Integer>('sensitivity',50),1,100);
      Value.Zoom:=O.GetValue<Double>('zoom',100);Value.X:=O.GetValue<Double>('x',0);Value.Y:=O.GetValue<Double>('y',0);
      if IsNan(Value.Zoom) or IsInfinite(Value.Zoom) or IsNan(Value.X) or IsInfinite(Value.X) or IsNan(Value.Y) or IsInfinite(Value.Y) then Exit;
      Value.Zoom:=EnsureRange(Value.Zoom,1.0,400.0);
      Assets:=nil;V:=O.GetValue('designs');if V<>nil then begin if not (V is TJSONArray) then Exit;Assets:=TJSONArray(V);end;FillChar(Seen,SizeOf(Seen),0);
      if Assets<>nil then begin
        if Assets.Count>RHYTHM_DESIGN_COUNT then Exit;
        for V in Assets do begin
          if not (V is TJSONObject) then Exit;Item:=TJSONObject(V);I:=DesignIndex(Item.GetValue<string>('id',''));if I<0 then Continue;
          if Seen[I] then Exit;Seen[I]:=True;
          Value.Designs[I].Path:=Item.GetValue<string>('path','');Value.Designs[I].SHA256:=Item.GetValue<string>('sha256','');Value.Designs[I].Memo:=Item.GetValue<string>('memo','');
          if (Length(Value.Designs[I].Memo)>2000) or not ValidDesignReference(Value.Designs[I].Path,Value.Designs[I].SHA256) then Exit;
        end;
      end;
      Result:=True;
    except Result:=False;end;
  finally J.Free;if not Result then Value:=Defaults;end;
end;
end.
