program TypeGTimelineSmoke;
{$APPTYPE CONSOLE}
// 波形内での4小節配置と編集トランザクションを、ユーザーの設定と音楽を使わず確認する。
uses System.SysUtils, System.Classes, System.Math, System.IOUtils, System.Hash,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RhythmAudio, RhythmAudioCache, RhythmStyles, RhythmPlanRef, RhythmGPlan, RhythmGCodec,
  RhythmGTimeline, RhythmGWave, SYNC_RhythmShooter_SettingsForm, RhythmSettings, RhythmPrepare;
type
  TWaveAccess = class(TGWave);
var A: TRhythmAudio; P,Q: TGPlan; Timeline: TGTimeline; ParentForm: TForm;
  SettingsForm: TFormRhythmShooterSettings; Ref,Original: TRhythmPlanRef;
  Tempo: TEdit; Game: TComboBox; B: TBitmap; PNG: TPngImage;
  Folder,SourceFile: string; I,J,N,Checks: Integer; Settings: TRhythmSettings; C,SeekControl,PlayPanel: TControl;
procedure Need(V: Boolean; const Why: string);
begin if not V then raise Exception.Create(Why); Inc(Checks); end;
procedure Click(const Name: string);
var C: TComponent;
begin C:=Timeline.FindComponent(Name); Need(C is TButton,'button '+Name); TButton(C).Click; end;
procedure SaveImage;
begin
  B:=TBitmap.Create;
  try
    B.PixelFormat:=pf32bit; B.SetSize(Timeline.Wave.Width,Timeline.Wave.Height);
    Timeline.Wave.Render(B.Canvas); PNG:=TPngImage.Create;
    try PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Folder,'wave-scenes.png')); finally FreeAndNil(PNG); end;
  finally FreeAndNil(B); end;
end;
procedure VerifyWAV;
type THeader = packed record
  Riff,RiffSize,Wave,Fmt,FmtSize: Cardinal; Format,Channels: Word;
  Rate,ByteRate: Cardinal; Align,Bits: Word; Data,DataSize: Cardinal;
end;
var H: THeader; Samples: TArray<SmallInt>; I: Integer; Phase: Double; F: TFileStream;
  Worker: TRhythmPrepareThread; Audio: TRhythmAudio; Plan: TGPlan; Path: string;
begin
  Path:=TPath.Combine(Folder,'tempo120.wav'); SetLength(Samples,Round(48.037*22050));
  for I:=0 to High(Samples) do begin
    Phase:=Frac(I/22050*2)*0.5;
    Samples[I]:=Round(23000*(Sin(2*Pi*90*Phase)*Exp(-Phase*28)+0.22*Sin(2*Pi*2200*Phase)*Exp(-Phase*65))*Min(1.0,Phase*1500));
  end;
  H:=Default(THeader); H.Riff:=$46464952; H.Wave:=$45564157; H.Fmt:=$20746D66;
  H.FmtSize:=16; H.Format:=1; H.Channels:=1; H.Rate:=22050; H.ByteRate:=44100;
  H.Align:=2; H.Bits:=16; H.Data:=$61746164; H.DataSize:=Length(Samples)*2; H.RiffSize:=36+H.DataSize;
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(H,SizeOf(H)); F.WriteBuffer(Samples[0],Length(Samples)*2); finally F.Free; end;
  Worker:=TRhythmPrepareThread.Create(Path,50,0,rsTypeG,False,nil,1); Audio:=nil; Plan:=nil;
  try
    Worker.Start; Worker.WaitFor; Need(Worker.Error='',Worker.Error); Audio:=Worker.TakeAudio;
    Need((Audio<>nil) and (Length(Audio.Hits)>40),'real WAV hit analysis');
    Plan:=LoadGPlan(Worker.Plan,Audio,0); Need(Abs(60/Plan.Beat-120)<3,'real WAV tempo');
    Need(Plan.Scenes[High(Plan.Scenes)].Finish-Plan.Scenes[High(Plan.Scenes)].Start>Plan.Beat*4,'tiny ending scene');
  finally Plan.Free; Audio.Free; Worker.Free; end;
end;
begin
  A:=nil; P:=nil; Q:=nil; Timeline:=nil; ParentForm:=nil; SettingsForm:=nil; B:=nil; PNG:=nil;
  try
    SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE);
    Application.Initialize; Application.ShowMainForm:=False;
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence'); ForceDirectories(Folder);
    VerifyWAV;
    SourceFile:=TPath.Combine(Folder,'timeline.source'); TFile.WriteAllText(SourceFile,'Type.G timeline fixture');
    A:=TRhythmAudio.Create; A.Source:=SourceFile; A.Key:=THashSHA2.GetHashString(SourceFile);
    A.SourceRevision:=AudioSourceStamp(SourceFile); A.Duration:=300.037; A.Sensitivity:=50; A.SoundEnd:=A.Duration;
    SetLength(A.Hits,600); SetLength(A.Envelope,30004);
    for I:=0 to High(A.Hits) do begin A.Hits[I].Time:=0.25+I*0.5; A.Hits[I].Strength:=0.5+0.1*(I mod 5); end;
    for I:=0 to High(A.Envelope) do A.Envelope[I]:=0.1+0.8*Exp(-(I mod 50)*0.12);
    P:=BuildGPlan(A); Ref:=NewPlanRef(A.Key,50,0,rsTypeG); Ref.SourceRevision:=A.SourceRevision; SaveGPlan(P,A,Ref);
    FreeAndNil(P); Original:=Ref; ParentForm:=TForm.CreateNew(nil);
    ParentForm.ClientWidth:=1100; ParentForm.ClientHeight:=400;
    Timeline:=TGTimeline.Create(ParentForm); Timeline.Parent:=ParentForm; Timeline.Width:=1080; Timeline.Bind(A,Ref);
    Tempo:=TEdit(Timeline.FindComponent('GTempo')); Game:=TComboBox(Timeline.FindComponent('GGame'));
    Need((Tempo<>nil) and (Game<>nil),'wave toolbar'); Need(Length(Timeline.Plan.Scenes)=38,'initial grid');
    Tempo.Text:='90'; Click('GRegrid'); Need(Length(Timeline.Plan.Scenes)=29,'slower BPM trims scenes');
    Tempo.Text:='180'; Click('GRegrid'); Need(Length(Timeline.Plan.Scenes)=57,'faster BPM adds scenes');
    Need(Timeline.Reference.Key<>Original.Key,'timeline edits overwrite old reference');
    Q:=LoadGPlan(Original,A,0); Need(Length(Q.Scenes)=38,'original timeline mutated'); FreeAndNil(Q);
    Timeline.Wave.Selected:=0; Game.ItemIndex:=18; Game.OnChange(Game);
    Need(Timeline.Plan.Scenes[0].Game=18,'wave game change');
    N:=Length(Timeline.Plan.Scenes); Timeline.SetTime(2); Click('GSplit'); Need(Length(Timeline.Plan.Scenes)=N+1,'wave split');
    Timeline.Wave.Selected:=0; Click('GMerge'); Need(Length(Timeline.Plan.Scenes)=N,'wave merge');
    Timeline.SetTime(2); Click('GAdd'); Need(Length(Timeline.Plan.Scenes)=N+1,'wave add');
    Click('GDelete'); Need(Length(Timeline.Plan.Scenes)=N,'wave delete');
    // 境界を1小節単位で移動し、両シーンの連続性と保存結果を検査する。
    Timeline.Wave.OnBoundary(Timeline.Wave,1,4); Need(Timeline.Plan.Scenes[0].Finish=4,'wave drag previous end');
    Need(Timeline.Plan.Scenes[1].Start=4,'wave drag next start');
    Tempo.Text:='0'; Ref:=Timeline.Reference; Click('GRegrid');
    Need(Timeline.Reference.Digest=Ref.Digest,'invalid BPM altered saved timeline'); Timeline.Plan.Validate;
    Tempo.Text:='120'; Click('GRegrid');
    for I:=0 to High(Timeline.Plan.Scenes) do Need(Abs(Timeline.Plan.Scenes[I].Start-I*8)<1E-8,'wave grid realign');
    Timeline.SetTime(23.5); SaveImage;
    // 同じ通常DPIで幅だけを変え、ツールが折り返されることを調べる。
    for J:=0 to 1 do begin
      Timeline.Width:=1080-J*580;
      for I:=0 to Timeline.ControlCount-1 do with Timeline.Controls[I] do
        Need((Left>=0) and (Top>=0) and (Left+Width<=Timeline.ClientWidth+1) and
          (Top+Height<=Timeline.ClientHeight+1),'wave control outside panel '+Name);
    end;
    Timeline.Width:=1080; Need(Abs(Timeline.Wave.TimeAt(0))<1E-10,'wave first pixel');
    Need(Timeline.Wave.TimeAt(Timeline.Wave.Width-1)>0,'wave last pixel');
    Ref:=Timeline.Reference; Q:=LoadGPlan(Ref,A,0); Need(Length(Q.Scenes)=38,'wave saved restore'); FreeAndNil(Q);
    // 共通フォームではType.Gだけ専用の波形編集が表示される。旧スタイルは通常波形を使う。
    SettingsForm:=TFormRhythmShooterSettings.Create(nil);
    Settings:=TRhythmSettings.Defaults; Settings.Style:=rsTypeG; SettingsForm.ConfigureState(Settings);
    C:=TControl(SettingsForm.FindComponent('TypeGTimeline'));
    Need(C.Visible,'Type.G waveform editor not integrated');
    SeekControl:=TControl(SettingsForm.FindComponent('Timeline'));
    PlayPanel:=TControl(SettingsForm.FindComponent('PreviewPlay')).Parent;
    Need(C.Top+C.Height<=SeekControl.Top,'wave editor overlaps seek');
    Need(SeekControl.Top+SeekControl.Height<=PlayPanel.Top,'wave editor overlaps transport');
    Settings.Style:=rsShooting; SettingsForm.ConfigureState(Settings);
    Need(not TControl(SettingsForm.FindComponent('TypeGTimeline')).Visible,'legacy style shows Type.G controls');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"waveformUI":true,"gridBars":4,"invalidEditRollback":true,"guiShown":false}',[Checks]),TEncoding.UTF8);
    WriteLn('Type.G waveform timeline PASS checks=',Checks);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message); ExitCode:=1; end; end;
  PNG.Free; B.Free; SettingsForm.Free; Timeline.Free; ParentForm.Free; Q.Free; P.Free; A.Free;
end.
