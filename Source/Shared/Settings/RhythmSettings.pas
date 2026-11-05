unit RhythmSettings;
// schema1設定と旧保存互換。ホスト音源の変更時は保存プランの取り違えを防ぐ。
interface
uses RhythmDesignTypes,RhythmStyles,RhythmPlanRef;
type
  TRhythmSettings=record
    Music:string;
    HostMusic:Boolean;
    Style:TRhythmStyle;
    Plan:TRhythmPlanRef;
    Direction,Sensitivity,FireworksRichness,BossFrequency,GameThreshold:Integer; // GameThresholdは全種類の音要素設定
    Zoom,X,Y:Double;
    OffsetSeconds:Double; // 描画専用。ホストではtrackが正、JSONはPreviewへの受渡し用。
    EqualizerMode:Integer; // -1=旧版移行の初期値、0=非表示、1=表示。解析計画とは独立。
    Designs:TRhythmDesigns;
    class function Defaults:TRhythmSettings; static;
    procedure BindHostMusic(const FileName:string);
    function ToJSON:string;
    class function TryJSON(const Text:string;out Value:TRhythmSettings):Boolean; static;
  end;
function EqualizerEnabled(Mode:Integer;Style:TRhythmStyle;PlanVersion:Integer):Boolean;
implementation
uses System.SysUtils,System.JSON,System.Math,RhythmProduct,RhythmTiming;

function EqualizerEnabled(Mode:Integer;Style:TRhythmStyle;PlanVersion:Integer):Boolean;
begin if Mode<0 then Result:=(Style=rsRhythmGame) and (PlanVersion<>1) else Result:=Mode>0;end;
class function TRhythmSettings.Defaults:TRhythmSettings;
begin Result:=Default(TRhythmSettings);
  Result.Music:='';
  Result.Style:=ProductDefaultStyle;
  Result.Direction:=0;
  Result.Sensitivity:=50;
  Result.BossFrequency:=BOSS_DEFAULT_FREQUENCY;
  Result.FireworksRichness:=FIREWORKS_DEFAULT_RICHNESS;
  Result.GameThreshold:=AUDIO_DEFAULT_DENSITY;
  Result.Zoom:=100;
  Result.OffsetSeconds:=0;
  Result.EqualizerMode:=-1;
  Result.X:=0;
  Result.Y:=0;
end;

procedure TRhythmSettings.BindHostMusic(const FileName:string);
var
  SameSource:Boolean;
  Source:string;
begin
  Source:=Trim(FileName);
  SameSource:=False;
  if (Music<>'') and (Source<>'') then
  try SameSource:=SameFileName(ExpandFileName(Music),ExpandFileName(Source));
  except SameSource:=False;
  end;
  if not SameSource then Plan:=Default(TRhythmPlanRef);
  Music:=Source;
  HostMusic:=True;
end;

function TRhythmSettings.ToJSON:string;
var
  J,Item,PlanObject:TJSONObject;
  Assets:TJSONArray;
  I:Integer;
begin
  J:=TJSONObject.Create;
  try J.AddPair('schema',TJSONNumber.Create(1));
    J.AddPair('presentationVersion',TJSONNumber.Create(3));
    J.AddPair('music',Music);
    J.AddPair('direction',TJSONNumber.Create(Direction));
    J.AddPair('sensitivity',TJSONNumber.Create(Sensitivity));
    J.AddPair('zoom',TJSONNumber.Create(Zoom));
    J.AddPair('offsetSeconds',TJSONNumber.Create(NormalizeRenderOffset(OffsetSeconds)));
    J.AddPair('x',TJSONNumber.Create(X));
    J.AddPair('y',TJSONNumber.Create(Y));
    if HostMusic then J.AddPair('musicSource','host');
    J.AddPair('bossFrequency',TJSONNumber.Create(EnsureRange(BossFrequency,0,100)));
    J.AddPair('style',StyleId(Style));
    J.AddPair('audioDensity',TJSONNumber.Create(EnsureRange(GameThreshold,-100,100)));
    J.AddPair('gameThreshold',TJSONNumber.Create(EnsureRange(GameThreshold,-100,100))); // 旧音ゲー版で読むため保持
    if EqualizerMode>=0 then J.AddPair('equalizer',TJSONBool.Create(EqualizerMode>0));
    J.AddPair('fireworksRichness',TJSONNumber.Create(EnsureRange(FireworksRichness,0,100)));
    if Plan.Key<>'' then begin
      PlanObject:=TJSONObject.Create;
      J.AddPair('plan',PlanObject);
      PlanObject.AddPair('key',Plan.Key);
      PlanObject.AddPair('source',Plan.SourceKey);
      PlanObject.AddPair('digest',Plan.Digest);
      if Plan.SourceRevision<>'' then PlanObject.AddPair('sourceStamp',Plan.SourceRevision);
      PlanObject.AddPair('style',StyleId(Plan.Style));
      PlanObject.AddPair('version',TJSONNumber.Create(Plan.Version));
      PlanObject.AddPair('sensitivity',TJSONNumber.Create(Plan.Sensitivity));
      PlanObject.AddPair('direction',TJSONNumber.Create(Plan.Direction));
      PlanObject.AddPair('variant',TJSONNumber.Create(Plan.Variant));
      if Plan.AudioDensity<>0 then PlanObject.AddPair('density',TJSONNumber.Create(Plan.AudioDensity));
      if Plan.Generation<>'' then PlanObject.AddPair('generation',Plan.Generation);
    end;
    Assets:=TJSONArray.Create;
    J.AddPair('designs',Assets);
    for I:=0 to High(Designs) do if (Designs[I].Path<>'') or (Designs[I].Memo<>'') then begin
      Item:=TJSONObject.Create;
      Item.AddPair('id',DesignInfo(I).Id);
      Item.AddPair('path',Designs[I].Path);
      Item.AddPair('sha256',Designs[I].SHA256);
      Item.AddPair('memo',Designs[I].Memo);
      Assets.AddElement(Item);
    end;
    Result:=J.ToJSON;
  finally J.Free;
  end;
end;

class function TRhythmSettings.TryJSON(const Text:string;out Value:TRhythmSettings):Boolean;
var
  J,V:TJSONValue;
  O,Item,PlanObject,Layers,Movie:TJSONObject;
  Assets:TJSONArray;
  I,ExpectedVariant:Integer;LegacyPlan:TRhythmPlanRef;LegacyStyle:TRhythmStyle;
  LegacyMovie,LegacyForeground:Boolean;
  Seen:array[0..RHYTHM_DESIGN_COUNT-1] of Boolean;

  function TrySavedSelection(const Id:string;out Style:TRhythmStyle):Boolean;
  begin
    // 廃止した種類は選択を後継へ移し、旧計画は従来のID照合で破棄する。
    if Id='race' then begin Style:=rsSideRace;Exit(True);end;
    if Id='fighting' then begin Style:=rsFightingRush;Exit(True);end;
    Result:=TryStyle(Id,Style);
  end;

begin
  Value:=Defaults;
  Result:=False;
  J:=nil;
  try
    try J:=TJSONObject.ParseJSONValue(Text);
      if not (J is TJSONObject) then Exit;
      O:=TJSONObject(J);
      if O.GetValue<Integer>('schema',0)<>1 then Exit;
      if not TrySavedSelection(O.GetValue<string>('style','shooting'),Value.Style) then Exit;
      Value.HostMusic:=O.GetValue<string>('musicSource','')='host';
      Value.Music:=O.GetValue<string>('music','');
      Value.Direction:=EnsureRange(O.GetValue<Integer>('direction',0),0,1);
      Value.Sensitivity:=EnsureRange(O.GetValue<Integer>('sensitivity',50),1,100);
      Value.BossFrequency:=EnsureRange(O.GetValue<Integer>('bossFrequency',100),0,100);
      Value.FireworksRichness:=EnsureRange(O.GetValue<Integer>('fireworksRichness',FIREWORKS_DEFAULT_RICHNESS),0,100);
      V:=O.GetValue('audioDensity');
      if V<>nil then begin
        if not (V is TJSONNumber) or not TryStrToInt(V.Value,I) then Exit;
        Value.GameThreshold:=EnsureRange(I,-100,100);
      end else if StyleHas(Value.Style,sfThreshold) then
        Value.GameThreshold:=EnsureRange(O.GetValue<Integer>('gameThreshold',AUDIO_DEFAULT_DENSITY),-100,100);
      V:=O.GetValue('equalizer');if V<>nil then begin if not (V is TJSONBool) then Exit;Value.EqualizerMode:=Ord(O.GetValue<Boolean>('equalizer'));end;
      V:=O.GetValue('offsetSeconds');if (V<>nil) and not (V is TJSONNumber) then Exit;
      Value.OffsetSeconds:=O.GetValue<Double>('offsetSeconds',0);
      if IsNan(Value.OffsetSeconds) or IsInfinite(Value.OffsetSeconds) then Exit;
      Value.OffsetSeconds:=NormalizeRenderOffset(Value.OffsetSeconds);
      Value.Zoom:=O.GetValue<Double>('zoom',100);
      Value.X:=O.GetValue<Double>('x',0);
      Value.Y:=O.GetValue<Double>('y',0);
      if IsNan(Value.Zoom) or IsInfinite(Value.Zoom) or IsNan(Value.X) or IsInfinite(Value.X) or IsNan(Value.Y) or IsInfinite(Value.Y) then Exit;
      Value.Zoom:=EnsureRange(Value.Zoom,1.0,400.0);
      Assets:=nil;
      V:=O.GetValue('designs');
      if V<>nil then begin if not (V is TJSONArray) then Exit;
        Assets:=TJSONArray(V);
      end;
      FillChar(Seen,SizeOf(Seen),0);
      if Assets<>nil then begin
        if Assets.Count>RHYTHM_DESIGN_COUNT then Exit;
        for V in Assets do begin
          if not (V is TJSONObject) then Exit;
          Item:=TJSONObject(V);
          I:=DesignIndex(Item.GetValue<string>('id',''));
          if I<0 then Continue;
          if Seen[I] then Exit;
          Seen[I]:=True;
          Value.Designs[I].Path:=Item.GetValue<string>('path','');
          Value.Designs[I].SHA256:=Item.GetValue<string>('sha256','');
          Value.Designs[I].Memo:=Item.GetValue<string>('memo','');
          if (Length(Value.Designs[I].Memo)>2000) or not ValidDesignReference(Value.Designs[I].Path,Value.Designs[I].SHA256) then Exit;
        end;
      end;
      V:=O.GetValue('plan');
      if V is TJSONObject then begin
        PlanObject:=TJSONObject(V);
        Value.Plan.Key:=PlanObject.GetValue<string>('key','');
        Value.Plan.SourceKey:=PlanObject.GetValue<string>('source','');
        Value.Plan.Digest:=PlanObject.GetValue<string>('digest','');
        Value.Plan.SourceRevision:=PlanObject.GetValue<string>('sourceStamp','');
        if not TryStyle(PlanObject.GetValue<string>('style',''),Value.Plan.Style) then Value.Plan:=Default(TRhythmPlanRef)
        else begin
          Value.Plan.Version:=PlanObject.GetValue<Integer>('version',0);
          Value.Plan.Sensitivity:=PlanObject.GetValue<Integer>('sensitivity',0);
          Value.Plan.Direction:=PlanObject.GetValue<Integer>('direction',-1);
          Value.Plan.Variant:=PlanObject.GetValue<Integer>('variant',0);
          if Value.Plan.Style=rsJumpAdventure then Value.Plan.Generation:=PlanObject.GetValue<string>('generation','');
          V:=PlanObject.GetValue('density');
          if (V<>nil) and ((not (V is TJSONNumber)) or not TryStrToInt(V.Value,Value.Plan.AudioDensity)) then Exit;
          ExpectedVariant:=StyleVariant(Value.Style,Value.FireworksRichness,Value.BossFrequency,Value.GameThreshold);
          if (Value.Style=rsRhythmGame) and (Value.Plan.Version=1) then ExpectedVariant:=0;
          if (Value.Style=rsRhythmGame) and (Value.Plan.Version=2) then ExpectedVariant:=Value.GameThreshold+1;
          if (Value.Style=rsRunner) and (Value.Plan.Version<=5) then ExpectedVariant:=0;
          if (Value.Style=rsRunner) and (Value.Plan.Variant=0) and (Value.BossFrequency=100) then ExpectedVariant:=0;
          if (Value.Style in [rsShooting,rsBreakout]) and (Value.Plan.Variant=0) and (Value.BossFrequency=100) then ExpectedVariant:=0;
          if (Value.Plan.AudioDensity<>AudioDensityKey(Value.Style,Value.GameThreshold)) or
            not Value.Plan.Matches(Value.Plan.SourceKey,Value.Sensitivity,Value.Direction,Value.Style,ExpectedVariant) or not ValidDigest(Value.Plan.SourceKey) or
            (((Value.Style<>rsShooting) or (Value.Plan.AudioDensity<>0)) and not ValidDigest(Value.Plan.Digest)) then Value.Plan:=Default(TRhythmPlanRef);
        end;
      end;
      V:=O.GetValue('layers');
      if V<>nil then begin
        // 旧三層は読込時だけ一種類へ移行する。表示中の前面を優先し、前面OFF/中層ONならその計画を採用。
        if not (V is TJSONObject) then Exit;Layers:=TJSONObject(V);LegacyPlan:=Default(TRhythmPlanRef);
        if not TrySavedSelection(Layers.GetValue<string>('style','shooting'),LegacyStyle) or StyleHas(LegacyStyle,sfThreshold) then Exit;
        LegacyMovie:=Layers.GetValue<Boolean>('movie',False);LegacyForeground:=Layers.GetValue<Boolean>('foreground',True);
        V:=Layers.GetValue('plan');
        if V<>nil then begin if not (V is TJSONObject) then Exit;Movie:=TJSONObject(V);
          LegacyPlan.Key:=Movie.GetValue<string>('key','');LegacyPlan.SourceKey:=Movie.GetValue<string>('source','');
          LegacyPlan.Digest:=Movie.GetValue<string>('digest','');LegacyPlan.SourceRevision:=Movie.GetValue<string>('sourceStamp','');
          if not TryStyle(Movie.GetValue<string>('style',''),LegacyPlan.Style) then LegacyPlan:=Default(TRhythmPlanRef)
          else begin LegacyPlan.Version:=Movie.GetValue<Integer>('version',0);LegacyPlan.Sensitivity:=Movie.GetValue<Integer>('sensitivity',0);
            LegacyPlan.Direction:=Movie.GetValue<Integer>('direction',-1);LegacyPlan.Variant:=Movie.GetValue<Integer>('variant',0);
          end;
        end;
        if (Value.Style=rsRhythmGame) and not LegacyForeground and LegacyMovie then begin
          if (LegacyPlan.Version<>StylePlanVersion(LegacyStyle)) or
            not LegacyPlan.Matches(LegacyPlan.SourceKey,Value.Sensitivity,Value.Direction,LegacyStyle,StyleVariant(LegacyStyle,Value.FireworksRichness,Value.BossFrequency)) or
            not ValidDigest(LegacyPlan.SourceKey) or ((LegacyStyle<>rsShooting) and not ValidDigest(LegacyPlan.Digest)) or
            ((Value.Plan.SourceKey<>'') and (LegacyPlan.SourceKey<>Value.Plan.SourceKey)) or
            ((Value.Plan.SourceRevision<>'') and (LegacyPlan.SourceRevision<>Value.Plan.SourceRevision)) then LegacyPlan:=Default(TRhythmPlanRef);
          // 自動初期値だったEQも、旧音ゲーで実際に有効だった状態を維持する。
          if Value.EqualizerMode<0 then Value.EqualizerMode:=Ord(EqualizerEnabled(Value.EqualizerMode,Value.Style,Value.Plan.Version));
          Value.Style:=LegacyStyle;Value.Plan:=LegacyPlan;Value.GameThreshold:=AUDIO_DEFAULT_DENSITY;
        end;
        // 中層の破損・欠落は、選択中の音ゲーの有効な主計画を無効化しない。
      end;
      Result:=True;
    except Result:=False;
    end;
  finally J.Free;
    if not Result then Value:=Defaults;
  end;
end;
end.
