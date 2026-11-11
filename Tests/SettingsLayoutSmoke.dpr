program SettingsLayoutSmoke;
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RhythmSettings, RhythmStyles, RhythmAudio, RhythmWaveView, RhythmDesignFrame, RhythmControls, SYNC_RhythmShooter_SettingsForm;

type
  TControlAccess = class(TControl);
  TWindowAccess = class(TWinControl);

function VisibleHierarchy(Control:TControl):Boolean;
begin Result:=Control.Visible;if Control is TWinControl then Result:=Result and TWindowAccess(Control).Showing else if Control.Parent<>nil then Result:=Result and TWindowAccess(Control.Parent).Showing;end;
procedure ScaleTestForm(Form:TFormRhythmShooterSettings;PPI:Integer);
begin
  // A synthetic DPI has no matching OS monitor. After VCL scaling, ask
  // CurrentPPI for the stored VCL PPI rather than GetDpiForWindow's real PPI.
  Form.Scaled:=True;Form.ScaleForPPI(PPI);Form.Scaled:=False;
  if Assigned(TWindowAccess(Form.FindComponent('AnimationOptions')).OnResize) then TWindowAccess(Form.FindComponent('AnimationOptions')).OnResize(Form);
end;
procedure CheckLayout(Owner: TComponent);
var I, J, Gap: Integer; Control, Other: TControl; Measure: TBitmap; Overlap: TRect;
begin
  Gap := MulDiv(4, Abs(TControlAccess(Owner).Font.Height), 13);
  Measure := TBitmap.Create;
  try
    for I := 0 to Owner.ComponentCount - 1 do
      if Owner.Components[I] is TControl then
      begin
        Control := TControl(Owner.Components[I]);
        if Control is TRhythmDesignFrame then CheckLayout(Control);
        if not (Control is TButton) and not (Control is TEdit) and
          not (Control is TComboBox) and not (Control is TTrackBar) and
          not (Control is TLabel) and not (Control is TCheckBox) then Continue;
        if (Control.Parent = nil) or not VisibleHierarchy(Control) then Continue;
        if (Control.Left < 0) or (Control.Top < 0) or
          (Control.BoundsRect.Right > Control.Parent.ClientWidth) or
          (Control.BoundsRect.Bottom > Control.Parent.ClientHeight) then
          raise Exception.Create(Format('Control outside parent: %s %s bounds=%d,%d,%d,%d parent=%d,%d',
            [Control.Name+' / '+Control.Parent.ClassName+' / '+Control.Parent.Name,Control.ClassName,Control.Left,Control.Top,Control.Width,Control.Height,
             Control.Parent.ClientWidth,Control.Parent.ClientHeight]));
        Measure.Canvas.Font.Assign(TControlAccess(Control).Font);
        if Control is TButton then
        begin
          if Measure.Canvas.TextWidth(TButton(Control).Caption) + 2 * Gap > Control.Width then
            raise Exception.Create('Button caption clipped: ' + TButton(Control).Caption);
          if Measure.Canvas.TextHeight('Ag') + 2 * Gap > Control.Height then
            raise Exception.Create(Format('Button height too small: %s height=%d font=%d text=%d ppi=%d',
              [TButton(Control).Caption,Control.Height,TControlAccess(Control).Font.Height,
               Measure.Canvas.TextHeight('Ag'),Control.CurrentPPI]));
        end;
        for J := I + 1 to Owner.ComponentCount - 1 do
          if Owner.Components[J] is TControl then
          begin
            Other := TControl(Owner.Components[J]);
            if (Other.Parent <> Control.Parent) or not VisibleHierarchy(Other) then Continue;
            if IntersectRect(Overlap, Control.BoundsRect, Other.BoundsRect) and
              (Overlap.Width > Gap) and (Overlap.Height > Gap) then
              raise Exception.Create('Overlapping controls: ' + Control.ClassName + ' / ' + Other.ClassName);
          end;
      end;
  finally
    Measure.Free;
  end;
end;

procedure CheckOptionCaption(Form:TFormRhythmShooterSettings;const LabelName,ControlName:string);
var L,C:TControl;
begin
  L:=TControl(Form.FindComponent(LabelName));C:=TControl(Form.FindComponent(ControlName));
  if (L=nil) or (C=nil) or (L.Parent<>C.Parent) or (L.BoundsRect.Right>C.Left) then
    raise Exception.Create('Caption is not to the left of its control: '+LabelName);
end;
procedure CheckWaveHitTest;
var Wave:TRhythmWaveView;Audio:TRhythmAudio;ParentForm:TForm;
begin
  ParentForm:=TForm.CreateNew(nil);Wave:=TRhythmWaveView.Create(nil);Wave.Parent:=ParentForm;Audio:=TRhythmAudio.Create;
  try
    Audio.Duration:=10;Wave.SetBounds(0,0,101,42);Wave.SetAudio(Audio);
    if (Wave.TimeAt(-20)<>0) or (Wave.TimeAt(0)<>0) or (Abs(Wave.TimeAt(50)-5)>1E-9) or
      (Wave.TimeAt(100)<>10) or (Wave.TimeAt(150)<>10) then raise Exception.Create('Waveform hit test does not reach/clamp its endpoints');
    Wave.Width:=1;if Wave.TimeAt(0)<>0 then raise Exception.Create('Single-pixel waveform hit test failed');
    Wave.Width:=101;Audio.Duration:=0;if Wave.TimeAt(50)<>0 then raise Exception.Create('Zero-duration waveform hit test failed');
    Wave.SetAudio(nil);if Wave.TimeAt(50)<>0 then raise Exception.Create('Unprepared waveform hit test failed');
  finally Wave.Free;ParentForm.Free;Audio.Free;end;
end;

const DPIs:array[0..3] of Integer=(96,120,144,192);
var Form:TFormRhythmShooterSettings;Settings:TRhythmSettings;Bitmap:TBitmap;PNG:TPngImage;
 Style,OnlyStyle:TRhythmStyle;Combo,Ball,Stage:TComboBox;Folder:string;D,W,LogicalWidth,K:Integer;
begin
 try
  // Real monitor DPI is fixed. This verifies VCL scale/layout at each requested
  // PPI using fresh forms, avoiding fake WM_DPICHANGED and OS settings changes.
  SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE);Application.Initialize;Application.ShowMainForm:=False;CheckWaveHitTest;
  Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'LayoutVerification');ForceDirectories(Folder);
  if (ParamCount>0) and not TryStyle(ParamStr(1),OnlyStyle) then raise Exception.Create('Unknown layout style');
  for Style:=Low(TRhythmStyle) to High(TRhythmStyle) do for D:=Low(DPIs) to High(DPIs) do begin
   if (ParamCount>0) and (Style<>OnlyStyle) then Continue;
   Form:=TFormRhythmShooterSettings.Create(nil);
   try
    Settings:=TRhythmSettings.Defaults;Settings.Style:=Style;Settings.BossFrequency:=50;Settings.FireworksRichness:=100;
    Settings.MarbleBall:=mbWood;Settings.MarbleStage:=msClearAcrylic;Form.ConfigureState(Settings,320,180);
    Form.Position:=poDesigned;Form.Left:=-32000;Form.Top:=-32000;Form.Show;ScaleTestForm(Form,DPIs[D]);
    for K:=0 to Form.ComponentCount-1 do if Form.Components[K] is TPanel then if TPanel(Form.Components[K]).Caption<>'' then raise Exception.Create('Internal panel caption visible');
    Combo:=TComboBox(Form.FindComponent('AnimationStyle'));if (Combo.Items.Count<>GroupStyleCount(StyleInfo(Style).Group)) or (Combo.ItemIndex<>GroupStyleIndex(Style)) or (Form.Snapshot.Style<>Style) then raise Exception.Create('Classified style registration/restore');
    if TComboBox(Form.FindComponent('AnimationCategory')).ItemIndex<>Ord(StyleInfo(Style).Group) then raise Exception.Create('Major category restore');
    if TComboBox(Form.FindComponent('ScrollDirection')).Items.Count<>StyleSmallCount(Style) then raise Exception.Create('Small category restore');
    if Form.FindComponent('MovieLayerStyle')<>nil then raise Exception.Create('Duplicate middle selection');
    if (Form.FindComponent('RhythmLayerVisible')<>nil) or (Form.FindComponent('MovieLayerVisible')<>nil) then raise Exception.Create('Obsolete layer controls');
    if TTrackBar(Form.FindComponent('BossFrequency')).Parent.Visible<>(Style in [rsShooting,rsBreakout,rsBombAction,rsMining,rsTrain,rsJumpAdventure,rsFightingRush,rsSideRace,rsMineCart]) then raise Exception.Create('Boss frequency visibility');
    if not TTrackBar(Form.FindComponent('GameThreshold')).Parent.Visible then raise Exception.Create('Audio density visibility');
    CheckOptionCaption(Form,'GameThresholdCaption','GameThreshold');
    if (Form.FindComponent('EqualizerVisible')=nil) or not TCheckBox(Form.FindComponent('EqualizerVisible')).Visible then raise Exception.Create('Equalizer option missing');
    if TCheckBox(Form.FindComponent('EqualizerVisible')).Checked<>EqualizerEnabled(-1,Style,0) then raise Exception.Create('Equalizer migration default');
    Ball:=TComboBox(Form.FindComponent('MarbleBall'));Stage:=TComboBox(Form.FindComponent('MarbleStage'));
    if (Ball=nil) or (Stage=nil) or (Ball.Parent.Visible<>(Style=rsMarbleRelay)) or
      (Stage.Parent.Visible<>(Style=rsMarbleRelay)) then raise Exception.Create('Marble appearance visibility');
    if (Ball.Items.Count<>4) or (Stage.Items.Count<>7) or (Ball.ItemIndex<>Ord(mbWood)) or
      (Stage.ItemIndex<>Ord(msClearAcrylic)) then raise Exception.Create('Marble appearance restore');
    if Style=rsMarbleRelay then begin
      Ball.ItemIndex:=Ord(mbGlass);Ball.OnChange(Ball);
      Stage.ItemIndex:=Ord(msDeskCraft);Stage.OnChange(Stage);
      Settings:=Form.Snapshot;
      if (Settings.MarbleBall<>mbGlass) or (Settings.MarbleStage<>msDeskCraft) then raise Exception.Create('Marble appearance change');
    end;
    if Form.FindComponent('PreviewPause')<>nil then raise Exception.Create('Separate pause button');
    if TButton(Form.FindComponent('PreviewPlay')).Caption<>'再生' then raise Exception.Create('Idle play toggle');
    for W:=0 to 2 do begin
     case W of 0:LogicalWidth:=1100;1:LogicalWidth:=850;else LogicalWidth:=600;end;
     Form.Constraints.MinWidth:=0;Form.ClientWidth:=MulDiv(LogicalWidth,DPIs[D],96);Form.ClientHeight:=MulDiv(760,DPIs[D],96);
     Form.Repaint;Application.ProcessMessages;CheckLayout(Form);
     CheckOptionCaption(Form,'CategoryCaption','AnimationCategory');CheckOptionCaption(Form,'StyleCaption','AnimationStyle');CheckOptionCaption(Form,'DirectionCaption','ScrollDirection');CheckOptionCaption(Form,'SensitivityCaption','Sensitivity');
     if Style=rsMarbleRelay then begin
       CheckOptionCaption(Form,'MarbleBallCaption','MarbleBall');
       CheckOptionCaption(Form,'MarbleStageCaption','MarbleStage');
       if (W=1) and (Ball.Parent.Top<>Stage.Parent.Top) then raise Exception.Create('Marble options split unnecessarily');
     end;
     if W=1 then begin Bitmap:=Form.GetFormImage;PNG:=TPngImage.Create;try PNG.Assign(Bitmap);PNG.SaveToFile(TPath.Combine(Folder,StyleId(Style)+'-'+IntToStr(DPIs[D])+'.png'));finally PNG.Free;Bitmap.Free;end;end;
     if (W=2) and (Style=rsShooting) and (TControl(Form.FindComponent('AnimationOptions')).Height<=MulDiv(44,DPIs[D],96)) then raise Exception.Create('Narrow option rows did not wrap');
    end;
    // Custom-design lifecycle is covered at real monitor DPI by SettingsFormSmoke.
    if (Style=rsShooting) and (DPIs[D]=96) then begin Form.ClientWidth:=MulDiv(850,DPIs[D],96);TButton(Form.FindComponent('DesignTab')).Click;Form.Repaint;Application.ProcessMessages;CheckLayout(Form);end;
    WriteLn('LAYOUT ',StyleId(Style),' requested=',DPIs[D],' actual=',Form.CurrentPPI,' PASS');
   finally Form.Free;end;
  end;
  if ParamCount=0 then WriteLn('SETTINGS_LAYOUT_OK: 15 animation choices x 4 PPIs x 3 widths')
  else WriteLn('SETTINGS_LAYOUT_OK: ',StyleId(OnlyStyle),' x 4 PPIs x 3 widths');
 except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
end.
