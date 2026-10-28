unit SYNC_RhythmShooter_FilterPlugin;
interface
uses Winapi.Windows, AviUtl2FilterTypes;
function InitializeRhythmShooterPlugin(Version:DWORD):Byte;
procedure FinalizeRhythmShooterPlugin;
function GetRhythmShooterFilterTable:PFILTER_PLUGIN_TABLE;
implementation
uses System.SysUtils, System.Math, System.UITypes, System.Generics.Collections, Vcl.Forms, Vcl.Dialogs, Vcl.Graphics,
  PluginFilterTable, RhythmAudio, RhythmScene, RhythmSettings,RhythmDesignTypes, SYNC_RhythmShooter_SettingsForm;
const
  EFFECT_NAME:PWideChar=#$30EA#$30BA#$30E0#$30B7#$30E5#$30FC#$30C6#$30A3#$30F3#$30B0;
  MUSIC_NAME:PWideChar=#$97F3#$697D#$30D5#$30A1#$30A4#$30EB;
  DIRECTION_NAME:PWideChar=#$30B9#$30AF#$30ED#$30FC#$30EB#$65B9#$5411;
  SENSITIVITY_NAME:PWideChar=#$89E3#$6790#$611F#$5EA6;
type
  // Additive local ABI from the installed 2.1.15 SDK. Shared SDK stays intact.
  TRhythmHideRule=record
    ItemType,Name,ConditionName:PWideChar;
    ConditionOperator,ConditionValue:Integer;
  end;
var
  MusicItem:TFILTER_ITEM_FILE;
  DirectionItem:TFILTER_ITEM_SELECT;
  Directions:array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  SensitivityItem:TFILTER_ITEM_TRACK;
  SettingsButton:TFILTER_ITEM_BUTTON;
  AllItems:array[0..12] of Pointer;
  HideRules:array[0..3] of TRhythmHideRule;
  GHostVersion:DWORD;
  JsonItem:TFILTER_ITEM_STRING;
  InternalGroup:TFILTER_ITEM_GROUP;
  ZoomItem,XItem,YItem:TFILTER_ITEM_TRACK;
  GLastWidth,GLastHeight:Integer;
  GInitialized:Boolean;
  GLock:TRTLCriticalSection;
  GRenderer:TRhythmRenderer;
  GDesignRenderers:TObjectDictionary<string,TRhythmRenderer>;
  GBitmap:TBitmap;
  GRgba:TBytes;
  GAudio:TRhythmAudio;
  GCache:TObjectDictionary<string,TRhythmAudio>;
  GCacheBytes:Int64;
  GRequest,GError:string;

function CurrentSettings:TRhythmSettings;
var Text:string;
begin
  Text:='';if JsonItem.Value<>nil then Text:=string(JsonItem.Value);
  if not TRhythmSettings.TryJSON(Text,Result) then
  begin Result:=TRhythmSettings.Defaults;if MusicItem.Value<>nil then Result.Music:=string(MusicItem.Value);Result.Direction:=DirectionItem.Value;Result.Sensitivity:=Round(SensitivityItem.Value);end;
  Result.Zoom:=ZoomItem.Value;Result.X:=XItem.Value;Result.Y:=YItem.Value;
end;
function RendererFor(const Settings:TRhythmSettings):TRhythmRenderer;
var Key:string;Created:TRhythmRenderer;
begin
  Key:=DesignKey(Settings.Designs);if Key='' then Exit(GRenderer);
  if GDesignRenderers.TryGetValue(Key,Result) then Exit;
  Created:=TRhythmRenderer.Create;
  try
    Created.ApplyDesigns(Settings.Designs);
    if GDesignRenderers.Count>=4 then GDesignRenderers.Clear;
    GDesignRenderers.Add(Key,Created);Result:=Created;Created:=nil;
  finally Created.Free;end;
end;
procedure PollAudio(const Source:string;Sensitivity:Integer);
var Key:string;Loaded:TRhythmAudio;
begin
  Key:=Source+'|'+IntToStr(Sensitivity);
  if GRequest<>Key then
  begin
    GRequest:=Key;GAudio:=nil;GError:='';
    if Source='' then Exit;
    if GCache.TryGetValue(Key,GAudio) then Exit;
    // Only prepared disk data is loaded here; decoding/analysis belongs to the
    // dedicated editor. Failed requests are remembered until settings are applied.
    try
      Loaded:=LoadCachedRhythmAudio(Source,Sensitivity);
      if Loaded=nil then begin GError:='設定画面で音楽を解析して適用してください（解析キャッシュ未準備）。';Exit;end;
      if (GCache.Count>=4) or (GCacheBytes+Length(Loaded.PCM)>512*Int64(1024)*1024) then
      begin GCache.Clear;GCacheBytes:=0;end;
      GCache.Add(Key,Loaded);Inc(GCacheBytes,Length(Loaded.PCM));GAudio:=Loaded;
    except on E:Exception do GError:=E.Message;end;
  end;
end;

function ProcessVideo(Video:PFILTER_PROC_VIDEO):Byte;cdecl;
var W,H,X,Y,Sensitivity:Integer;Time:Double;Row,Dest:PByte;Source,MessageText:string;Settings:TRhythmSettings;Renderer:TRhythmRenderer;
begin
  Result:=0;
  try
    if not GInitialized or (Video=nil) or not Assigned(Video^.SetImageData) then Exit;
    if Video^.Object_<>nil then begin W:=Video^.Object_.Width;H:=Video^.Object_.Height;Time:=Video^.Object_.Time;end
    else begin W:=0;H:=0;Time:=0;end;
    if ((W<=0) or (H<=0)) and (Video^.Scene<>nil) then begin W:=Video^.Scene.Width;H:=Video^.Scene.Height;end;
    if (W<=0) or (H<=0) or (W>8192) or (H>8192) then Exit;
    Settings:=CurrentSettings;Source:=Settings.Music;Sensitivity:=Settings.Sensitivity;
    EnterCriticalSection(GLock);
    try
      PollAudio(Source,Sensitivity);
      GLastWidth:=W;GLastHeight:=H;
      if GError<>'' then MessageText:=GError else MessageText:='設定から WAV / MP3 を選択';
      if (GBitmap.Width<>W) or (GBitmap.Height<>H) then GBitmap.SetSize(W,H);
      Renderer:=RendererFor(Settings);Renderer.Render(GBitmap,GAudio,Time,Settings.Direction,MessageText,Settings.Zoom/100,Settings.X,Settings.Y);
      if Length(GRgba)<>W*H*4 then SetLength(GRgba,W*H*4);
      Dest:=@GRgba[0];
      for Y:=0 to H-1 do
      begin
        // VCL exposes logical top-down rows even when its internal DIB is bottom-up.
        Row:=GBitmap.ScanLine[Y];
        for X:=0 to W-1 do begin Dest[0]:=Row[2];Dest[1]:=Row[1];Dest[2]:=Row[0];Dest[3]:=255;Inc(Row,4);Inc(Dest,4);end;
      end;
      Video^.SetImageData(@GRgba[0],W,H);Result:=1;
    finally LeaveCriticalSection(GLock);end;
  except on E:Exception do begin OutputDebugString(PChar('SYNC_RhythmShooter: '+E.Message));Result:=0;end;end;
end;

procedure SettingsButtonCallback(Edit:PEDIT_SECTION);cdecl;
var Form:TFormRhythmShooterSettings;Obj:OBJECT_HANDLE;Text:UTF8String;Settings:TRhythmSettings;
  function SetItem(Name:PWideChar;const Value:string):Boolean;
  begin Text:=UTF8String(Value);Result:=Edit^.SetObjectItemValue(Obj,EFFECT_NAME,Name,PAnsiChar(Text));end;
begin
  try
    Form:=TFormRhythmShooterSettings.Create(nil);
    try
      Settings:=CurrentSettings;
      if (GLastWidth>0) and (GLastHeight>0) then Form.ConfigureState(Settings,GLastWidth,GLastHeight)
      else Form.ConfigureState(Settings);
      if Form.ShowModal<>mrOk then Exit;
      Obj:=nil;if (Edit<>nil) and Assigned(Edit^.GetFocusObject) then Obj:=Edit^.GetFocusObject();
      if (Edit=nil) or (Obj=nil) or not Assigned(Edit^.SetObjectItemValue) then
      begin MessageDlg('プレビュー設定は保存しました。AviUtl2の選択オブジェクトへ適用できませんでした。',mtWarning,[mbOK],0);Exit;end;
      if not SetItem('設定JSON',Form.Snapshot.ToJSON) then
        MessageDlg('設定の一部を適用できませんでした。AviUtl2側の設定を確認してください。',mtWarning,[mbOK],0);
      if GInitialized then
      begin
        EnterCriticalSection(GLock);
        try GRequest:='';GAudio:=nil;GCache.Clear;GCacheBytes:=0;GDesignRenderers.Clear;
        finally LeaveCriticalSection(GLock);end;
      end;
    finally Form.Free;end;
  except on E:Exception do MessageDlg('設定画面: '+E.Message,mtError,[mbOK],0);end;
end;

function InitializeRhythmShooterPlugin(Version:DWORD):Byte;
begin
  Result:=0;
  try
    if GInitialized then Exit(1);
    GHostVersion:=Version;
    InitializeCriticalSection(GLock);GInitialized:=True;
    GCache:=TObjectDictionary<string,TRhythmAudio>.Create([doOwnsValues]);
    GDesignRenderers:=TObjectDictionary<string,TRhythmRenderer>.Create([doOwnsValues]);
    GRenderer:=TRhythmRenderer.Create;GBitmap:=TBitmap.Create;GBitmap.PixelFormat:=pf32bit;Result:=1;
  except FinalizeRhythmShooterPlugin;end;
end;
procedure FinalizeRhythmShooterPlugin;
begin
  if not GInitialized then Exit;
  GAudio:=nil;FreeAndNil(GCache);GCacheBytes:=0;FreeAndNil(GDesignRenderers);FreeAndNil(GBitmap);FreeAndNil(GRenderer);GRgba:=nil;
  GRequest:='';GError:='';DeleteCriticalSection(GLock);GInitialized:=False;
end;
function GetRhythmShooterFilterTable:PFILTER_PLUGIN_TABLE;
var I:Integer;
begin
  if GTable.Name=nil then
  begin
    MusicItem.ItemType:='file';MusicItem.Name:=MUSIC_NAME;MusicItem.Value:='';
    MusicItem.FileFilter:='WAV / MP3 (*.wav;*.mp3)'#0'*.wav;*.mp3'#0;
    Directions[0].Name:=#$7E26;Directions[0].Value:=0;Directions[1].Name:=#$6A2A;Directions[1].Value:=1;
    DirectionItem.ItemType:='select';DirectionItem.Name:=DIRECTION_NAME;DirectionItem.Value:=0;DirectionItem.List:=@Directions[0];
    SensitivityItem.ItemType:='track';SensitivityItem.Name:=SENSITIVITY_NAME;SensitivityItem.Value:=50;
    SensitivityItem.S:=1;SensitivityItem.E:=100;SensitivityItem.Step:=1;
    SettingsButton.ItemType:='button';SettingsButton.Name:=#$8A2D#$5B9A;SettingsButton.Callback:=SettingsButtonCallback;
    ZoomItem.ItemType:='track';ZoomItem.Name:='拡大';ZoomItem.Value:=100;ZoomItem.S:=1;ZoomItem.E:=400;ZoomItem.Step:=0.1;
    XItem.ItemType:='track';XItem.Name:='X';XItem.Value:=0;XItem.S:=-8192;XItem.E:=8192;XItem.Step:=1;
    YItem.ItemType:='track';YItem.Name:='Y';YItem.Value:=0;YItem.S:=-8192;YItem.E:=8192;YItem.Step:=1;
    InternalGroup.ItemType:='group';InternalGroup.Name:='内部設定・旧版互換';InternalGroup.DefaultVisible:=0;
    JsonItem.ItemType:='string';JsonItem.Name:='設定JSON';JsonItem.Value:='';
    AllItems[0]:=@ZoomItem;AllItems[1]:=@XItem;AllItems[2]:=@YItem;AllItems[3]:=@SettingsButton;
    for I:=0 to 3 do HideRules[I].ItemType:='hiderule';
    HideRules[0].Name:='設定JSON';HideRules[1].Name:=MUSIC_NAME;
    HideRules[2].Name:=DIRECTION_NAME;HideRules[3].Name:=SENSITIVITY_NAME;
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER,EFFECT_NAME,'SYNC',
      #$30EA#$30BA#$30E0#$30B7#$30E5#$30FC#$30C6#$30A3#$30F3#$30B0#$30D5#$30A3#$30EB#$30BF#$30FC#$30D7#$30E9#$30B0#$30A4#$30F3,
      ProcessVideo,nil);
  end;
  for I:=4 to High(AllItems) do AllItems[I]:=nil;
  if GHostVersion>=2011500 then
  begin
    AllItems[4]:=@JsonItem;AllItems[5]:=@MusicItem;AllItems[6]:=@DirectionItem;AllItems[7]:=@SensitivityItem;
    // Rules follow every value item (the SDK documents an older ordering bug).
    for I:=0 to 3 do AllItems[8+I]:=@HideRules[I];
  end else
  begin
    // Old hosts cannot hide values without changing their storage type. Keep
    // old object data intact, collapsed, rather than silently discarding it.
    AllItems[4]:=@InternalGroup;AllItems[5]:=@JsonItem;AllItems[6]:=@MusicItem;AllItems[7]:=@DirectionItem;AllItems[8]:=@SensitivityItem;
  end;
  GTable.Items:=@AllItems[0];
  Result:=@GTable;
end;
end.
