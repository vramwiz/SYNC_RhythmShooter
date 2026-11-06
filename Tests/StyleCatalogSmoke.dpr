program StyleCatalogSmoke;
{$APPTYPE CONSOLE}
// 分類はUIの投影だけ。既存ID/enum/recipe/方向と専用実装の接続をフォームなしで検証する。
uses System.SysUtils,System.Classes,System.Hash,System.IOUtils,System.JSON,
  RhythmStyles,RhythmStyleSelection,RhythmSettings,RhythmPlanRef,RhythmStyleOps,RhythmStyleRegistry,
  RhythmAudio,RhythmAnimation,RhythmImageBank;
const Ids:array[TRhythmStyle] of string=('shooting','ball','jump-adventure','breakout','side-race','bomb-action','fighting-rush','mining','train','rhythm-game','prism-step','mine-cart');
  Versions:array[TRhythmStyle] of Integer=(1,6,3,10,1,2,1,1,1,4,3,4);
  Groups:array[TRhythmStyle] of TRhythmStyleGroup=(sgShooting,sgBall,sgAction,sgBall,sgRace,sgAction,sgAction,sgAction,sgShooting,sgMusic,sgMusic,sgAction);
  Scenes:array[TRhythmStyle] of string=('TShootingAnimation','TBallAnimation','TJumpAnimation','TBreakoutAnimation','TSideRaceAnimation','TBombActionAnimation','TRushAnimation','TMiningAnimation','TTrainAnimation','TGameAnimation','TStepAnimation','TCartAnimation');
  GroupCounts:array[TRhythmStyleGroup] of Integer=(2,2,5,1,2);
  Levels:array[0..4] of Integer=(-100,-1,0,50,100);
var S,Other,ParsedStyle:TRhythmStyle;G:TRhythmStyleGroup;D,I,J,K,V,Expected,Checks,Stage,Combinations:Integer;
  Sel,Restored:TStyleSelection;Saved,Loaded:TRhythmSettings;Ref:TRhythmPlanRef;Ops:TStyleOperations;
  Scene:TAnimationScene;Images:TAnimationImageBank;Names:TStringList;Context:TStylePrepareContext;
  Key,Recipe,Folder:string;ExpectedCompatible,Failed:Boolean;
procedure Need(OK:Boolean;const Why:string);
begin if not OK then raise Exception.Create(Why);Inc(Checks);end;
function WasCompatible(Style:TRhythmStyle;Version:Integer):Boolean;
begin Result:=Version=Versions[Style];case Style of
  rsBall:Result:=Version in [4,5,6];
  rsBreakout:Result:=Version in [1,2,3,4,5,6,7,8,9,10];
  rsBombAction:Result:=Version in [1,2];rsRhythmGame,rsMineCart:Result:=Version in [1,2,3,4];rsStepGame,rsJumpAdventure:Result:=Version in [1,2,3];
end;end;
begin Scene:=nil;Images:=nil;Names:=nil;Checks:=0;Combinations:=0;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);Names:=TStringList.Create;Key:=StringOfChar('a',64);
    Need((GroupStyleCount(sgRace)=1) and (GroupStyleAt(sgRace,0)=rsSideRace),'Only 2D race is selectable');
    Need(not TryStyle('race',ParsedStyle),'Retired 3D ID is still registered');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"race","music":"old-race.wav","sensitivity":73,'+
      '"offsetSeconds":0.21,"plan":{"style":"race","version":11,"key":"'+Key+'"}}',Loaded) and
      (Loaded.Style=rsSideRace) and (Loaded.Plan.Key='') and (Loaded.Music='old-race.wav') and
      (Loaded.Sensitivity=73) and (Abs(Loaded.OffsetSeconds-0.21)<1E-9),'Retired race settings migration');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","layers":'+
      '{"style":"race","movie":true,"foreground":false,"plan":{"style":"race"}}}',Loaded) and
      (Loaded.Style=rsSideRace) and (Loaded.Plan.Key=''),'Retired race layer migration');
    Need(not TryStyle('fighting',ParsedStyle),'Retired fighting ID is still registered');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"fighting","music":"old-fight.wav","bossFrequency":67,'+
      '"offsetSeconds":-0.18,"plan":{"style":"fighting","version":2,"key":"'+Key+'"}}',Loaded) and
      (Loaded.Style=rsFightingRush) and (Loaded.Plan.Key='') and (Loaded.Music='old-fight.wav') and
      (Loaded.BossFrequency=67) and (Abs(Loaded.OffsetSeconds+0.18)<1E-9),'Retired fighting settings migration');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","layers":'+
      '{"style":"fighting","movie":true,"foreground":false,"plan":{"style":"fighting"}}}',Loaded) and
      (Loaded.Style=rsFightingRush) and (Loaded.Plan.Key=''),'Retired fighting layer migration');
    Need(GroupStyleCount(sgBall)=2,'Ball family count');Need(StyleInfo(rsBall).Group=StyleInfo(rsBreakout).Group,'Pinball and breakout separated');
    Need((StyleInfo(rsRhythmGame).MiddleTitle='Type.V') and (StyleTitle(rsRhythmGame)='Type.V'),'Type.V label');
    Need((StyleInfo(rsStepGame).MiddleTitle='Type.D') and (StyleTitle(rsStepGame)='Type.D') and
      (StyleSmallTitle(rsStepGame,0)='縦'),'Type.D label');
    Need(not TryStyle('fireworks',ParsedStyle),'Fireworks is still selectable');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"fireworks","music":"old-fireworks.wav",'+
      '"plan":{"style":"fireworks","version":3,"key":"'+Key+'"}}',Loaded) and
      (Loaded.Style=rsShooting) and (Loaded.Plan.Key='') and (Loaded.Music='old-fireworks.wav'),'Retired fireworks settings');
    Need(not TryStyle('runner',ParsedStyle),'Retired runner is still selectable');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"runner","music":"old-runner.wav","bossFrequency":65,'+
      '"offsetSeconds":0.27,"plan":{"style":"runner","version":7,"key":"'+Key+'"}}',Loaded) and
      (Loaded.Style=rsJumpAdventure) and (Loaded.Plan.Key='') and (Loaded.Music='old-runner.wav') and
      (Loaded.BossFrequency=65) and (Abs(Loaded.OffsetSeconds-0.27)<1E-9),'Retired runner settings');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","layers":'+
      '{"style":"runner","movie":true,"foreground":false,"plan":{"style":"runner"}}}',Loaded) and
      (Loaded.Style=rsJumpAdventure) and (Loaded.Plan.Key=''),'Retired runner layer migration');
    Need(not TryStyle('naval',ParsedStyle),'Retired naval style is still selectable');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"naval","music":"old-naval.wav","musicSource":"host",'+
      '"bossFrequency":62,"offsetSeconds":0.14,"audioDensity":-26,"plan":{"style":"naval","version":1,"key":"'+Key+'"}}',Loaded) and
      (Loaded.Style=rsMineCart) and (Loaded.Plan.Key='') and (Loaded.Music='old-naval.wav') and Loaded.HostMusic and
      (Loaded.BossFrequency=62) and (Loaded.GameThreshold=-26) and (Abs(Loaded.OffsetSeconds-0.14)<1E-9),'Retired naval settings migration');
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"rhythm-game","layers":'+
      '{"style":"naval","movie":true,"foreground":false,"plan":{"style":"naval"}}}',Loaded) and
      (Loaded.Style=rsMineCart) and (Loaded.Plan.Key=''),'Retired naval layer migration');
    for G:=Low(TRhythmStyleGroup) to High(TRhythmStyleGroup) do begin
      Need(GroupStyleCount(G)=GroupCounts[G],'Group population');
      for I:=0 to GroupStyleCount(G)-1 do begin S:=GroupStyleAt(G,I);Need((StyleInfo(S).Group=G) and (GroupStyleIndex(S)=I),'Group order/index not bijective');end;
    end;
    for S:=Low(TRhythmStyle) to High(TRhythmStyle) do begin
      Need(StyleId(S)=Ids[S],'Saved style ID changed');Need(StylePlanVersion(S)=Versions[S],'Plan version changed');
      Need(TryStyle(Ids[S],ParsedStyle) and (ParsedStyle=S),'Style ID roundtrip');Need(StyleInfo(S).Group=Groups[S],'Classification');
      Need(StyleSmallCount(S)=1+Ord(S in [rsShooting,rsBall]),'Small mode count');
      for V:=0 to 12 do begin ExpectedCompatible:=WasCompatible(S,V);Need(CompatiblePlanVersion(S,V)=ExpectedCompatible,'Old plan compatibility changed');end;
      Need(not CompatiblePlanVersion(S,-1) and not CompatiblePlanVersion(S,256),'Invalid version accepted');
      for I:=0 to High(Levels) do for J:=0 to High(Levels) do for K:=0 to High(Levels) do begin
        Expected:=0;
        if S in [rsRhythmGame,rsStepGame] then Expected:=Levels[K]+101
        else if (S in [rsShooting,rsBreakout,rsBombAction,rsMining,rsTrain,rsJumpAdventure,rsFightingRush,rsSideRace,rsMineCart]) and (Levels[J]>=0) then Expected:=Levels[J]+1;
        Need(StyleVariant(S,Levels[I],Levels[J],Levels[K])=Expected,'Variant recipe changed');
      end;
      Ops:=StyleOperations(S);Need(Names.IndexOf(Ops.UnitName)<0,'Two variants share an adapter unit');Names.Add(Ops.UnitName);
      Need(Assigned(Ops.Transparency)=StyleHas(S,sfTransparent),'Transparent capability/adapter mismatch');
      Scene:=Ops.CreateScene;Need(Scene.ClassName=Scenes[S],'Wrong scene factory');Ops.SetReference(Scene,Default(TRhythmPlanRef));Ops.SetAudio(Scene,nil,100);
      Images:=Ops.CreateImages;Need(Images<>nil,'Image factory');FreeAndNil(Images);FreeAndNil(Scene);
      for D:=0 to 1 do begin
        Sel:=TStyleSelection.FromSaved(S,D);Need((Sel.Style=S) and (Sel.Direction=D) and (Sel.Group=Groups[S]),'Saved choice altered');
        Need(GroupStyleAt(Sel.Group,Sel.MiddleIndex)=S,'Middle list restore');
        Need(Sel.SmallIndex=Ord(StyleSmallCount(S)>1)*D,'Small list restore');
        Saved:=TRhythmSettings.Defaults;Saved.Style:=Sel.Style;Saved.Direction:=Sel.Direction;Saved.BossFrequency:=100;
        V:=StyleVariant(S,50,100);Ref:=NewPlanRef(Key,50,D,S,V);Ref.Digest:=StringOfChar('b',64);Saved.Plan:=Ref;
        Recipe:=Ids[S]+'-v'+IntToStr(Versions[S])+'|'+Key+'|50|'+IntToStr(D);if V<>0 then Recipe:=Recipe+'|variant='+IntToStr(V);
        Need(Ref.Key=THashSHA2.GetHashString(Recipe),'Prepared cache key changed');
        Need(TRhythmSettings.TryJSON(Saved.ToJSON,Loaded) and (Loaded.Style=S) and (Loaded.Direction=D) and (Loaded.Plan.Key=Ref.Key),'Old settings/plan restore');
        Need(not Saved.ToJSON.Contains('category') and not Saved.ToJSON.Contains('subcategory'),'UI grouping leaked into settings');
        Restored:=TStyleSelection.FromSaved(Loaded.Style,Loaded.Direction);Need((Restored.Group=Sel.Group) and (Restored.MiddleIndex=Sel.MiddleIndex) and (Restored.SmallIndex=Sel.SmallIndex),'Restored hierarchy');
        Sel.ChooseGroup(Sel.Group);Sel.ChooseMiddle(Sel.MiddleIndex);Need((Sel.Style=S) and (Sel.Direction=D),'Reselect reset existing direction');
        for G:=Low(TRhythmStyleGroup) to High(TRhythmStyleGroup) do begin Sel:=TStyleSelection.FromSaved(S,D);Sel.ChooseGroup(G);
          for I:=0 to GroupStyleCount(G)-1 do begin Other:=GroupStyleAt(G,I);Sel.ChooseMiddle(I);Need(Sel.Style=Other,'Middle choice maps to wrong ID');
            for J:=0 to StyleSmallCount(Other)-1 do begin Expected:=Sel.Direction;Sel.ChooseSmall(J);if StyleSmallCount(Other)>1 then Expected:=J;Need((Sel.Style=Other) and (Sel.Direction=Expected),'Small choice maps to wrong direction');Inc(Combinations);end;
          end;
        end;
      end;
    end;
    Need(not TryStyle('unknown',ParsedStyle) and (ParsedStyle=rsShooting),'Unknown ID handling');
    Stage:=0;Context.Progress:=procedure(Value:Integer) begin Stage:=Value;end;Context.SetStage(4);Need(Stage=4,'Progress callback');
    Context.Cancel:=function:Boolean begin Result:=True;end;Failed:=False;try Context.CheckCancel;except on E:EAbort do Failed:=True;end;Need(Failed,'Cancellation callback');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"groups":5,"styles":12,"smallChoices":14,"selectionTransitions":%d,"adapters":12,"gui":false}',[Checks,Combinations]),TEncoding.UTF8);
    WriteLn('Style catalog PASS checks=',Checks,' groups=5 styles=12 transitions=',Combinations,' no GUI');
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  Scene.Free;Images.Free;Names.Free;
end.
