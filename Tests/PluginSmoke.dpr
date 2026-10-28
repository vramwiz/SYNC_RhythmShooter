program PluginSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows, System.SysUtils, System.Classes, System.Math, System.IOUtils,
  System.JSON, System.Diagnostics, System.Hash, Vcl.Graphics,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas';
type
  TInitialize=function(Version:DWORD):Byte;cdecl;
  TFinalize=procedure;cdecl;
  TGetTable=function:PFILTER_PLUGIN_TABLE;cdecl;
var Lib:HMODULE;Init:TInitialize;Done:TFinalize;GetTable:TGetTable;Table:PFILTER_PLUGIN_TABLE;
  Root,Item:TJSONObject;Items:TJSONArray;Index,Width,Height,I,Direction:Integer;
  Ptr:Pointer;Kind,Name,Source,Destination,ErrorText,FirstHash:string;
  FileItem:PFILTER_ITEM_FILE;SelectItem:PFILTER_ITEM_SELECT;JsonItem:PFILTER_ITEM_STRING;JsonObject:TJSONObject;JsonText,HorizontalHash:string;
  Scene:TSCENE_INFO;Obj:TOBJECT_INFO;Video:TFILTER_PROC_VIDEO;Captured:TBytes;
  Watch:TStopwatch;Initialized:Boolean;ModernCount:Integer;MissingJsonText,MissingHash:string;
procedure Require(Value:Boolean;const Text:string);
begin if not Value then raise Exception.Create(Text);end;
function VerificationFolder:string;
begin
  if ParamCount>=3 then Result:=ParamStr(3)
  else Result:=TPath.Combine(ExtractFileDir(ParamStr(1)),'Verification');
end;
function PixelHash:string;
var Hash:THashSHA2;
begin Hash:=THashSHA2.Create;Hash.Update(Captured);Result:=Hash.HashAsString;end;
procedure Capture(Buffer:PPIXEL_RGBA;W,H:Integer);cdecl;
begin
  Width:=W;Height:=H;SetLength(Captured,W*H*4);Move(Buffer^,Captured[0],Length(Captured));
end;
function ItemPointer(Index:Integer):Pointer;
begin Result:=PPointer(NativeUInt(Table.Items)+NativeUInt(Index*SizeOf(Pointer)))^;end;
procedure SaveCaptured(const FileName:string);
var Bitmap:TBitmap;X,Y:Integer;Source,Destination:PByte;
begin
  Bitmap:=TBitmap.Create;
  try
    Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(Width,Height);Source:=@Captured[0];
    for Y:=0 to Height-1 do
    begin Destination:=Bitmap.ScanLine[Y];
      for X:=0 to Width-1 do begin Destination[0]:=Source[2];Destination[1]:=Source[1];Destination[2]:=Source[0];Destination[3]:=255;Inc(Source,4);Inc(Destination,4);end;
    end;
    Bitmap.SaveToFile(FileName);
  finally Bitmap.Free;end;
end;
begin
  Root:=TJSONObject.Create;Lib:=0;Initialized:=False;
  try
    try
      Require(ParamCount>=2,'Pass the DLL path and sample MP3');Source:=ParamStr(2);
      Lib:=LoadLibraryEx(PChar(ParamStr(1)),0,LOAD_WITH_ALTERED_SEARCH_PATH);if Lib=0 then RaiseLastOSError;
      @Init:=GetProcAddress(Lib,'InitializePlugin');@Done:=GetProcAddress(Lib,'UninitializePlugin');@GetTable:=GetProcAddress(Lib,'GetFilterPluginTable');
      Require(Assigned(Init) and Assigned(Done) and Assigned(GetTable),'Required export missing');
      Require(Init(0)=1,'InitializePlugin failed');Initialized:=True;Table:=GetTable();
      Require(Table<>nil,'Missing filter table');Root.AddPair('name',string(Table.Name));Root.AddPair('group',string(Table.Label_));Root.AddPair('description',string(Table.Information));
      Require(string(Table.Name)=string(#$30EA#$30BA#$30E0#$30B7#$30E5#$30FC#$30C6#$30A3#$30F3#$30B0),'Unexpected filter name');
      Require(string(Table.Label_)='SYNC','Unexpected group');Require(Assigned(Table.Func_Proc_Video),'Video callback missing');
      Items:=TJSONArray.Create;Root.AddPair('items',Items);Index:=0;FileItem:=nil;SelectItem:=nil;JsonItem:=nil;
      repeat
        Ptr:=ItemPointer(Index);if Ptr=nil then Break;
        Kind:=string(PWideChar(PPointer(Ptr)^));Name:=string(PWideChar(PPointer(NativeUInt(Ptr)+8)^));
        Item:=TJSONObject.Create;Item.AddPair('type',Kind);Item.AddPair('name',Name);Items.AddElement(Item);
        if Kind='file' then FileItem:=PFILTER_ITEM_FILE(Ptr);
        if Kind='select' then SelectItem:=PFILTER_ITEM_SELECT(Ptr);
        if Kind='string' then JsonItem:=PFILTER_ITEM_STRING(Ptr);
        Inc(Index);Require(Index<20,'Items are not nil terminated');
      until False;
      Require((Index=9) and (FileItem<>nil) and (SelectItem<>nil),'Unexpected item layout');
      FileItem.Value:=PWideChar(Source);
      FillChar(Scene,SizeOf(Scene),0);Scene.Width:=1280;Scene.Height:=720;Scene.Rate:=60;Scene.Scale:=1;
      FillChar(Obj,SizeOf(Obj),0);Obj.Width:=1280;Obj.Height:=720;Obj.Time:=8.69;
      FillChar(Video,SizeOf(Video),0);Video.Scene:=@Scene;Video.Object_:=@Obj;Video.SetImageData:=Capture;
      Require(Table.Func_Proc_Video(nil)=0,'Nil-video boundary not guarded');
      Watch:=TStopwatch.StartNew;Require(Table.Func_Proc_Video(@Video)=1,'First video frame failed');
      Root.AddPair('firstFrameLoadAndDrawMs',TJSONNumber.Create(Watch.Elapsed.TotalMilliseconds));FirstHash:=PixelHash;
      Sleep(30);Require(Table.Func_Proc_Video(@Video)=1,'Warm video frame failed');
      Require(FirstHash=PixelHash,'First export frame was a transient loading frame');
      Root.AddPair('firstFrameStable',TJSONBool.Create(True));
      Root.AddPair('width',TJSONNumber.Create(Width));Root.AddPair('height',TJSONNumber.Create(Height));
      Require((Width=1280) and (Height=720),'Unexpected output size');
      Destination:=VerificationFolder;ForceDirectories(Destination);
      for Direction:=0 to 1 do
      begin
        SelectItem.Value:=Direction;Obj.Time:=8.69;Require(Table.Func_Proc_Video(@Video)=1,'Frame A failed');FirstHash:=PixelHash;
        Obj.Time:=24;Require(Table.Func_Proc_Video(@Video)=1,'Frame B failed');
        Obj.Time:=8.69;Require(Table.Func_Proc_Video(@Video)=1,'Repeat frame A failed');Require(FirstHash=PixelHash,'Seek changed same-time frame');
        Root.AddPair('rgbaSHA256_'+IntToStr(Direction),FirstHash);
        SaveCaptured(TPath.Combine(Destination,'native-direction'+IntToStr(Direction)+'.bmp'));
      end;
      HorizontalHash:=PixelHash;
      JsonObject:=TJSONObject.Create;
      try JsonObject.AddPair('schema',TJSONNumber.Create(1));JsonObject.AddPair('music',Source);JsonObject.AddPair('direction',TJSONNumber.Create(1));JsonObject.AddPair('sensitivity',TJSONNumber.Create(50));JsonText:=JsonObject.ToJSON;finally JsonObject.Free;end;
      Require(JsonItem<>nil,'JSON state item missing');JsonItem.Value:=PWideChar(JsonText);SelectItem.Value:=0;
      Require(Table.Func_Proc_Video(@Video)=1,'JSON state frame failed');Require(PixelHash=HorizontalHash,'JSON direction did not override legacy direction');Root.AddPair('objectJsonState','passed');
      PFILTER_ITEM_TRACK(ItemPointer(0)).Value:=125;PFILTER_ITEM_TRACK(ItemPointer(1)).Value:=27;PFILTER_ITEM_TRACK(ItemPointer(2)).Value:=-15;
      Require(Table.Func_Proc_Video(@Video)=1,'Transform frame failed');Require(PixelHash<>HorizontalHash,'Scale/XY had no effect');Root.AddPair('scaleXY','passed');
      PFILTER_ITEM_TRACK(ItemPointer(0)).Value:=100;PFILTER_ITEM_TRACK(ItemPointer(1)).Value:=0;PFILTER_ITEM_TRACK(ItemPointer(2)).Value:=0;
      MissingJsonText:=StringReplace(JsonText,Source,Source+'.missing.mp3',[rfReplaceAll]);
      // JSON escapes backslashes, so construct the missing-path object explicitly.
      JsonObject:=TJSONObject.Create;
      try JsonObject.AddPair('schema',TJSONNumber.Create(1));JsonObject.AddPair('music',Source+'.missing.mp3');MissingJsonText:=JsonObject.ToJSON;finally JsonObject.Free;end;
      JsonItem.Value:=PWideChar(MissingJsonText);Watch:=TStopwatch.StartNew;
      Require(Table.Func_Proc_Video(@Video)=1,'Missing-cache frame failed');MissingHash:=PixelHash;
      Require(Table.Func_Proc_Video(@Video)=1,'Repeated missing-cache frame failed');Require(MissingHash=PixelHash,'Missing cache started transient analysis');
      Root.AddPair('missingCacheTwoFramesMs',TJSONNumber.Create(Watch.Elapsed.TotalMilliseconds));Root.AddPair('missingCacheStable','passed');
      JsonItem.Value:=PWideChar(JsonText);Require(Table.Func_Proc_Video(@Video)=1,'Prepared cache did not resume');Require(PixelHash=HorizontalHash,'Prepared data changed after missing-cache request');
      for I:=0 to Length(Captured) div 4-1 do Require(Captured[I*4+3]=255,'Nonopaque output alpha');
      Obj.Width:=1920;Obj.Height:=1080;SelectItem.Value:=0;Watch:=TStopwatch.StartNew;
      for I:=0 to 59 do begin Obj.Time:=I*0.5;Require(Table.Func_Proc_Video(@Video)=1,'Performance frame failed');end;
      Root.AddPair('callback1920x1080MeanMs',TJSONNumber.Create(Watch.Elapsed.TotalMilliseconds/60));
      Done();Initialized:=False;Require(Init(0)=1,'Second initialize failed');Initialized:=True;Done();Initialized:=False;
      Require(Init(2011500)=1,'Modern initialize failed');Initialized:=True;Table:=GetTable();ModernCount:=0;
      while ItemPointer(ModernCount)<>nil do begin
        Ptr:=ItemPointer(ModernCount);Kind:=string(PWideChar(PPointer(Ptr)^));
        if ModernCount>=8 then begin Require(Kind='hiderule','Internal item has no hide rule');Require(PPointer(NativeUInt(Ptr)+16)^=nil,'Hide rule is conditional');end;
        Inc(ModernCount);Require(ModernCount<20,'Modern table not terminated');
      end;
      Require(ModernCount=12,'Modern hidden item count wrong');Done();Initialized:=False;
      Root.AddPair('modernUnconditionalHideRules',TJSONNumber.Create(4));Root.AddPair('legacyCompatibilityItems','preserved collapsed on unsupported hosts');
      Root.AddPair('initializeAndCleanup','passed three times');Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.ClassName+': '+E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    Destination:=VerificationFolder;ForceDirectories(Destination);
    TFile.WriteAllText(TPath.Combine(Destination,'plugin-smoke.json'),Root.ToJSON,TEncoding.UTF8);Writeln(Root.ToJSON);
  finally if Initialized then Done();if Lib<>0 then FreeLibrary(Lib);Root.Free;end;
  if ErrorText<>'' then Halt(1);
end.
