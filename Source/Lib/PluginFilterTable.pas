unit PluginFilterTable;

interface

uses
  AviUtl2FilterTypes;

procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);
procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFILTER_ITEM_BUTTON_CALLBACK);

var
  GTable: TFILTER_PLUGIN_TABLE;

implementation

const
  MAX_GUI_ITEMS = 100;

var
  ItemIndex: Integer;
  Items: array[0..MAX_GUI_ITEMS - 1] of Pointer;

procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);
begin
  GTable.Flag := Flag;
  GTable.Name := Name;
  GTable.Label_ := Label_;
  GTable.Information := Information;
  GTable.Items := @Items[0];
  GTable.Func_Proc_Video := VideoProc;
  GTable.Func_Proc_Audio := AudioProc;
end;

procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFILTER_ITEM_BUTTON_CALLBACK);
begin
  if ItemIndex >= MAX_GUI_ITEMS - 1 then
    Exit;
  Items[ItemIndex] := @Item;
  Item.ItemType := 'button';
  Item.Name := Name;
  Item.Callback := Callback;
  Inc(ItemIndex);
  Items[ItemIndex] := nil;
end;

end.
