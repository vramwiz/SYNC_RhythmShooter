unit SYNC_RhythmShooter_FilterPlugin;
// AviUtl2パラメータ／映像連携。音源を照合し、未解析時は透明出力する。
interface
uses Winapi.Windows, AviUtl2FilterTypes;
function InitializeRhythmShooterPlugin(Version:DWORD):Byte;
procedure FinalizeRhythmShooterPlugin;
function GetRhythmShooterFilterTable:PFILTER_PLUGIN_TABLE;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, RhythmPaths, System.Math, System.UITypes, System.Generics.Collections, Vcl.Forms, Vcl.Dialogs, Vcl.Graphics,
PluginFilterTable, RhythmAudio, RhythmStyleRegistry, RhythmScene, RhythmSettings,RhythmDesignTypes,RhythmStyles,RhythmProduct,RhythmTiming, SYNC_RhythmShooter_SettingsForm;
const
  MUSIC_NAME:PWideChar=#$97F3#$697D#$30D5#$30A1#$30A4#$30EB;
type
  // Additive local ABI from the installed 2.1.15 SDK. Shared SDK stays intact.
  TRhythmHideRule=record
    ItemType,Name,ConditionName:PWideChar;
    ConditionOperator,ConditionValue:Integer;
  end;
var
  GEffectTitle,GEffectInformation:string;
  EFFECT_NAME:PWideChar;
  MusicItem:TFILTER_ITEM_FILE;
  OffsetItem:TFILTER_ITEM_TRACK;
  SettingsButton:TFILTER_ITEM_BUTTON;
  AllItems:array[0..12] of Pointer;
  JsonHideRule:TRhythmHideRule;
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
  GRequest,GError,GFailedBallRevision,GColdRetryKey:string;
  GBallProbeAt:UInt64;

function StoredSettings:TRhythmSettings;
var
  Text:string;
begin
  Text:='';
  if JsonItem.Value<>nil then Text:=string(JsonItem.Value);
  if not TRhythmSettings.TryJSON(Text,Result) then
  begin Result:=TRhythmSettings.Defaults;
    if not StyleHas(ProductDefaultStyle,sfDefaultBoss50) then Result.BossFrequency:=100;
    if MusicItem.Value<>nil then Result.Music:=string(MusicItem.Value);
    // 削除した旧track/selectからは読まない。JSONなしの旧物件は初期値から明示的に再準備する。
  end;
  // ホストが現在フレームの値へ更新するtrackを正とし、JSONのPreview用コピーで上書きしない。
  Result.OffsetSeconds:=NormalizeRenderOffset(OffsetItem.Value);
  Result.Zoom:=ZoomItem.Value;
  Result.X:=XItem.Value;
  Result.Y:=YItem.Value;
end;

function HostMusicPath:string;
begin Result:='';
  if MusicItem.Value<>nil then Result:=Trim(string(MusicItem.Value));
end;

function CurrentSettings:TRhythmSettings;
begin Result:=StoredSettings;
  Result.BindHostMusic(HostMusicPath);
end;

function RendererFor(const Settings:TRhythmSettings):TRhythmRenderer;
var
  Key:string;
  Created:TRhythmRenderer;
begin
  if (Settings.Style=rsShooting) and (ProductDefaultStyle=rsShooting) and (DesignKey(Settings.Designs)='') and (Settings.Plan.Variant=0) and (Settings.BossFrequency=100) then Exit(GRenderer);
  Key:=StyleId(Settings.Style)+'|'+DesignKey(Settings.Designs)+'|'+Settings.Plan.Key+'|'+Settings.Plan.Digest;
  if StyleHas(Settings.Style,sfBoss) then Key:=Key+'|boss='+IntToStr(Settings.BossFrequency);
  if GDesignRenderers.TryGetValue(Key,Result) then Exit;
  Created:=TRhythmRenderer.Create;
  try
    Created.ConfigureStyle(Settings.Style,Settings.Plan,Settings.BossFrequency,Settings.EqualizerMode);
    Created.ApplyDesigns(Settings.Designs);
    if GDesignRenderers.Count>=4 then GDesignRenderers.Clear;
    GDesignRenderers.Add(Key,Created);
    Result:=Created;
    Created:=nil;
  finally Created.Free;
  end;
end;

function PreparedRestorationRevision(const Settings:TRhythmSettings):string;
  function Stamp(const Path:string):string;
  var
    Info:TWin32FileAttributeData;
  begin
    Result:='missing';
    if GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Info) then
    Result:=IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+'-'+
    IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8);
  end;
begin
  Result:=Stamp(Settings.Music);
  try
    if Length(Settings.Plan.Key)=64 then Result:=Result+'|'+Stamp(TPath.Combine(PlanFolder,Settings.Plan.Key+'.json'));
    if Length(Settings.Plan.SourceKey)=64 then begin
      Result:=Result+'|'+Stamp(TPath.Combine(CacheFolder,Settings.Plan.SourceKey+'-s'+IntToStr(Settings.Sensitivity)+'-events-v1.json'));
      Result:=Result+'|'+Stamp(TPath.Combine(CacheFolder,THashSHA2.GetHashString(LowerCase(ExpandFileName(Settings.Music)))+'-s'+IntToStr(Settings.Sensitivity)+'-index.json'));
    end;
  except Result:=Result+'|unavailable';
  end;
end;

procedure PollAudio(const Settings:TRhythmSettings);
var
  Key,Source,Revision:string;
  Sensitivity:Integer;
  Loaded:TRhythmAudio;
begin
  Source:=Settings.Music;
  Sensitivity:=Settings.Sensitivity;
  Key:=Source+'|'+IntToStr(Sensitivity);
  // A host path alone cannot authorize an old file's plan or start analysis.
  if (Source='') or (Settings.Plan.Key='') then begin GAudio:=nil;
    GRequest:='';
    Exit;
  end;
  if (GAudio<>nil) and not AudioSourceUnchanged(GAudio) then begin
    GAudio:=nil;
    GRequest:='';
    GCache.Clear;
    GCacheBytes:=0;
  end;
  if Settings.Style=rsShooting then Key:=Key+'|boss='+IntToStr(Settings.BossFrequency)+'|plan='+Settings.Plan.Key;
  if (Settings.Style=rsShooting) and (Settings.BossFrequency<>100) and (Settings.Plan.Key='') then begin GAudio:=nil;
    GError:='ボス頻度を変更しました。設定画面で再準備・適用してください。';
    Exit;
  end;
  if StyleHas(Settings.Style,sfPrepared) then Key:='prepared-'+StyleId(Settings.Style)+'|'+Key+'|'+Settings.Plan.Key+'|'+Settings.Plan.Digest+'|'+Settings.Plan.SourceRevision+'|'+IntToStr(Settings.Direction);
  if (GRequest=Key) and (StyleHas(Settings.Style,sfPrepared)) and (GAudio=nil) and (GError<>'') and (GetTickCount64>=GBallProbeAt) then begin
    GBallProbeAt:=GetTickCount64+1000;
    Revision:=PreparedRestorationRevision(Settings);
    if Revision<>GFailedBallRevision then begin GRequest:='';
      GColdRetryKey:='';
    end
    else if GColdRetryKey<>Key then begin GColdRetryKey:=Key;
      GRequest:='';
    end;
  end;
  if GRequest<>Key then
  begin
    GRequest:=Key;
    GAudio:=nil;
    GError:='';
    if Source='' then Exit;
    if GCache.TryGetValue(Key,GAudio) then begin
      if AudioSourceUnchanged(GAudio) then Exit;
      GAudio:=nil;
      GCache.Clear;
      GCacheBytes:=0;
    end;
    // Only prepared disk data is loaded here; decoding/analysis belongs to the
    // dedicated editor. One retry covers a transient startup failure. Further
    // attempts require a file revision change, never per-frame preparation.
    Loaded:=nil;
    try
      Loaded:=LoadStyleAudio(Settings.Style,Settings.Plan,Source,Settings.Direction);
      if Loaded=nil then begin GError:='設定画面で音楽を解析して適用してください（解析キャッシュ未準備）。';
        Exit;
      end;
      if (Loaded.Key<>Settings.Plan.SourceKey) or
      ((Settings.Plan.SourceRevision<>'') and (Loaded.SourceRevision<>Settings.Plan.SourceRevision)) then
      raise Exception.Create('音楽ファイルが解析時と異なります。設定画面で準備・解析してください。');
      if (GCache.Count>=4) or (GCacheBytes+Length(Loaded.PCM)>512*Int64(1024)*1024) then
      begin GCache.Clear;
        GCacheBytes:=0;
      end;
      GCache.Add(Key,Loaded);
      Inc(GCacheBytes,Length(Loaded.PCM));
      GAudio:=Loaded;
      Loaded:=nil;
      GColdRetryKey:='';
    except on E:Exception do begin
        Loaded.Free;
        GError:=E.Message;
        if StyleHas(Settings.Style,sfPrepared) then begin GFailedBallRevision:=PreparedRestorationRevision(Settings);
          GBallProbeAt:=GetTickCount64+1000;
        end;
      end;
    end;
  end;
end;

function ProcessVideo(Video:PFILTER_PROC_VIDEO):Byte; cdecl;
var
  W,H,X,Y:Integer;
  Time:Double;
  Row,Dest:PByte;
  MessageText:string;
  Settings:TRhythmSettings;
  Renderer:TRhythmRenderer;
begin
  Result:=0;
  try
    if not GInitialized or (Video=nil) or not Assigned(Video^.SetImageData) then Exit;
    if Video^.Object_<>nil then begin W:=Video^.Object_.Width;
      H:=Video^.Object_.Height;
      Time:=Video^.Object_.Time;
    end
    else begin W:=0;
      H:=0;
      Time:=0;
    end;
    if ((W<=0) or (H<=0)) and (Video^.Scene<>nil) then begin W:=Video^.Scene.Width;
      H:=Video^.Scene.Height;
    end;
    if (W<=0) or (H<=0) or (W>8192) or (H>8192) then Exit;
    Settings:=CurrentSettings;
    EnterCriticalSection(GLock);
    try
      PollAudio(Settings);
      GLastWidth:=W;
      GLastHeight:=H;
      if GAudio=nil then begin
        // Explicit transparent output also clears the previously prepared frame.
        if Length(GRgba)<>W*H*4 then SetLength(GRgba,W*H*4);
        FillChar(GRgba[0],Length(GRgba),0);
        Video^.SetImageData(@GRgba[0],W,H);
        Exit(1);
      end;
      if GError<>'' then MessageText:=GError else MessageText:='設定から WAV / MP3 を選択';
      if (GBitmap.Width<>W) or (GBitmap.Height<>H) then GBitmap.SetSize(W,H);
      Renderer:=RendererFor(Settings);
      Renderer.ConfigureStyle(Settings.Style,Settings.Plan,Settings.BossFrequency,Settings.EqualizerMode);
      Renderer.Render(GBitmap,GAudio,Time,Settings.Direction,MessageText,Settings.Zoom/100,Settings.X,Settings.Y,Settings.OffsetSeconds);
      if Length(GRgba)<>W*H*4 then SetLength(GRgba,W*H*4);
      Dest:=@GRgba[0];
      for Y:=0 to H-1 do
      begin
        // VCL exposes logical top-down rows even when its internal DIB is bottom-up.
        Row:=GBitmap.ScanLine[Y];
        for X:=0 to W-1 do begin Dest[0]:=Row[2];
          Dest[1]:=Row[1];
          Dest[2]:=Row[0];
          if Renderer.OutputHasAlpha then Dest[3]:=Row[3] else Dest[3]:=255;
          Inc(Row,4);
          Inc(Dest,4);
        end;
      end;
      Video^.SetImageData(@GRgba[0],W,H);
      Result:=1;
    finally LeaveCriticalSection(GLock);
    end;
  except on E:Exception do begin OutputDebugString(PChar(ProductId+': '+E.Message));
      Result:=0;
    end;
  end;
end;

procedure SettingsButtonCallback(Edit:PEDIT_SECTION); cdecl;
var
  Form:TFormRhythmShooterSettings;
  Obj:OBJECT_HANDLE;
  Text:UTF8String;
  Settings,Applied:TRhythmSettings;
  PinnedPath,HostPathAtOpen:string;
  function SetItem(Name:PWideChar;const Value:string):Boolean;
  begin Text:=UTF8String(Value);
    Result:=Edit^.SetObjectItemValue(Obj,EFFECT_NAME,Name,PAnsiChar(Text));
  end;
begin
  try
    Form:=TFormRhythmShooterSettings.Create(nil);
    try
      Obj:=nil;
      if (Edit<>nil) and Assigned(Edit^.GetFocusObject) then Obj:=Edit^.GetFocusObject();
      HostPathAtOpen:=HostMusicPath;
      Settings:=StoredSettings;
      // Old AUP2 projects kept the selected file only in settings JSON. Migrate
      // through the host editor API when settings opens, never while rendering.
      if not Settings.HostMusic and (HostMusicPath='') and (Settings.Music<>'') then begin
        if (Edit=nil) or (Obj=nil) or not Assigned(Edit^.SetObjectItemValue) then Exit;
        if not SetItem(MUSIC_NAME,Settings.Music) then begin
          MessageDlg('旧設定の音楽ファイルを移行できません。AviUtl2側で音楽ファイルを指定してください。',mtWarning,[mbOK],0);
          Exit;
        end;
        Settings.HostMusic:=True;
        if not SetItem(JsonItem.Name,Settings.ToJSON) then Exit;
        PinnedPath:=Settings.Music;
      end else PinnedPath:=HostMusicPath;
      Settings.BindHostMusic(PinnedPath);
      if (GLastWidth>0) and (GLastHeight>0) then Form.ConfigureState(Settings,GLastWidth,GLastHeight,True)
      else Form.ConfigureState(Settings,1280,720,True);
      if Form.ShowModal<>mrOk then Exit;
      Obj:=nil;
      if (Edit<>nil) and Assigned(Edit^.GetFocusObject) then Obj:=Edit^.GetFocusObject();
      if (Edit=nil) or (Obj=nil) or not Assigned(Edit^.SetObjectItemValue) then
      begin MessageDlg('プレビュー設定は保存しました。AviUtl2の選択オブジェクトへ適用できませんでした。',mtWarning,[mbOK],0);
        Exit;
      end;
      Applied:=Form.Snapshot;
      if (HostMusicPath<>HostPathAtOpen) and (HostMusicPath<>PinnedPath) then begin
        MessageDlg('AviUtl2の音楽ファイルが変更されました。設定を開き直してください。',mtWarning,[mbOK],0);
        Exit;
      end;
      if not SetItem(JsonItem.Name,Applied.ToJSON) then
      MessageDlg('設定の一部を適用できませんでした。AviUtl2側の設定を確認してください。',mtWarning,[mbOK],0);
      if GInitialized then
      begin
        EnterCriticalSection(GLock);
        try GRequest:='';
          GColdRetryKey:='';
          GAudio:=nil;
          GCache.Clear;
          GCacheBytes:=0;
          GDesignRenderers.Clear;
        finally LeaveCriticalSection(GLock);
        end;
      end;
    finally Form.Free;
    end;
  except on E:Exception do MessageDlg('設定画面: '+E.Message,mtError,[mbOK],0);
  end;
end;

function InitializeRhythmShooterPlugin(Version:DWORD):Byte;
begin
  Result:=0;
  try
    if GInitialized then Exit(1);
    GHostVersion:=Version;
    InitializeCriticalSection(GLock);
    GInitialized:=True;
    GCache:=TObjectDictionary<string,TRhythmAudio>.Create([doOwnsValues]);
    GDesignRenderers:=TObjectDictionary<string,TRhythmRenderer>.Create([doOwnsValues]);
    GRenderer:=TRhythmRenderer.Create;
    GBitmap:=TBitmap.Create;
    GBitmap.PixelFormat:=pf32bit;
    Result:=1;
  except FinalizeRhythmShooterPlugin;
  end;
end;

procedure FinalizeRhythmShooterPlugin;
begin
  if not GInitialized then Exit;
  GAudio:=nil;
  FreeAndNil(GCache);
  GCacheBytes:=0;
  FreeAndNil(GDesignRenderers);
  FreeAndNil(GBitmap);
  FreeAndNil(GRenderer);
  GRgba:=nil;
  GRequest:='';
  GError:='';
  GFailedBallRevision:='';
  GColdRetryKey:='';
  GBallProbeAt:=0;
  DeleteCriticalSection(GLock);
  GInitialized:=False;
end;

function GetRhythmShooterFilterTable:PFILTER_PLUGIN_TABLE;
var
  I:Integer;
begin
  if GTable.Name=nil then
  begin
    GEffectTitle:=ProductTitle;
    GEffectInformation:=ProductTitle+' フィルタープラグイン';
    EFFECT_NAME:=PWideChar(GEffectTitle);
    MusicItem.ItemType:='file';
    MusicItem.Name:=MUSIC_NAME;
    MusicItem.Value:='';
    MusicItem.FileFilter:='WAV / MP3 (*.wav;*.mp3)'#0'*.wav;*.mp3'#0;
    OffsetItem.ItemType:='track';
    OffsetItem.Name:='オフセット';
    OffsetItem.Value:=0;
    OffsetItem.S:=-1;
    OffsetItem.E:=1;
    OffsetItem.Step:=0.01;
    SettingsButton.ItemType:='button';
    SettingsButton.Name:=#$8A2D#$5B9A;
    SettingsButton.Callback:=SettingsButtonCallback;
    ZoomItem.ItemType:='track';
    ZoomItem.Name:='拡大';
    ZoomItem.Value:=100;
    ZoomItem.S:=1;
    ZoomItem.E:=400;
    ZoomItem.Step:=0.1;
    XItem.ItemType:='track';
    XItem.Name:='X';
    XItem.Value:=0;
    XItem.S:=-8192;
    XItem.E:=8192;
    XItem.Step:=1;
    YItem.ItemType:='track';
    YItem.Name:='Y';
    YItem.Value:=0;
    YItem.S:=-8192;
    YItem.E:=8192;
    YItem.Step:=1;
    InternalGroup.ItemType:='group';
    InternalGroup.Name:='内部設定・旧版互換';
    InternalGroup.DefaultVisible:=0;
    JsonItem.ItemType:='string';
    JsonItem.Name:='設定JSON';
    JsonItem.Value:='';
    AllItems[0]:=@ZoomItem;
    AllItems[1]:=@XItem;
    AllItems[2]:=@YItem;
    AllItems[3]:=@MusicItem;
    AllItems[4]:=@SettingsButton;
    JsonHideRule.ItemType:='hiderule';
    JsonHideRule.Name:='設定JSON';
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER,EFFECT_NAME,'SYNC',
    PWideChar(GEffectInformation),
    ProcessVideo,nil);
  end;
  for I:=5 to High(AllItems) do AllItems[I]:=nil;
  if GHostVersion>=2011500 then
  begin
    AllItems[5]:=@JsonItem;
    AllItems[6]:=@OffsetItem;
    // 既存JSONの名前/型を保ち、値の後へ無条件の非表示規則を置く。
    AllItems[7]:=@JsonHideRule;
  end else
  begin
    // 非対応ホストでもオフセットは通常表示。内部JSONだけを閉じたグループへ置く。
    // 小分類/感度の旧ホスト項目は再登録せず、設定画面のJSONを唯一の入力にする。
    AllItems[5]:=@OffsetItem;
    AllItems[6]:=@InternalGroup;
    AllItems[7]:=@JsonItem;
  end;
  GTable.Items:=@AllItems[0];
  Result:=@GTable;
end;
end.
