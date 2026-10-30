program SettingsLayoutSmoke;
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RhythmSettings, RhythmStyles, RhythmAudio, RhythmWaveView, RhythmDesignFrame, RhythmControls, SYNC_RhythmShooter_SettingsForm;

type
  TControlAccess = class(TControl);

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
          not (Control is TLabel) then Continue;
        if (Control.Parent = nil) or not Control.Visible then Continue;
        if (Control.Left < 0) or (Control.Top < 0) or
          (Control.BoundsRect.Right > Control.Parent.ClientWidth) or
          (Control.BoundsRect.Bottom > Control.Parent.ClientHeight) then
          raise Exception.Create(Format('Control outside parent: %s %s bounds=%d,%d,%d,%d parent=%d,%d',
            [Control.Name,Control.ClassName,Control.Left,Control.Top,Control.Width,Control.Height,
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
            if (Other.Parent <> Control.Parent) or not Other.Visible then Continue;
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
var Wave:TRhythmWaveView;Audio:TRhythmAudio;
begin
  Wave:=TRhythmWaveView.Create(nil);Audio:=TRhythmAudio.Create;
  try
    Audio.Duration:=10;Wave.SetBounds(0,0,101,42);Wave.SetAudio(Audio);
    if (Wave.TimeAt(-20)<>0) or (Wave.TimeAt(0)<>0) or (Abs(Wave.TimeAt(50)-5)>1E-9) or
      (Wave.TimeAt(100)<>10) or (Wave.TimeAt(150)<>10) then raise Exception.Create('Waveform hit test does not reach/clamp its endpoints');
    Wave.Width:=1;if Wave.TimeAt(0)<>0 then raise Exception.Create('Single-pixel waveform hit test failed');
    Wave.Width:=101;Audio.Duration:=0;if Wave.TimeAt(50)<>0 then raise Exception.Create('Zero-duration waveform hit test failed');
    Wave.SetAudio(nil);if Wave.TimeAt(50)<>0 then raise Exception.Create('Unprepared waveform hit test failed');
  finally Wave.Free;Audio.Free;end;
end;

const DPIs: array[0..3] of Integer = (96, 144, 192, 96);
var
  Form: TFormRhythmShooterSettings;
  Settings: TRhythmSettings;
  Bitmap: TBitmap;
  PNG: TPngImage;
  Pages: TPageControl;
  Folder, ImagePath: string;
  I, D, Tab, WidthIndex, LogicalWidth: Integer;
begin
  try
    SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    Application.Initialize;
    Application.ShowMainForm := False;
    CheckWaveHitTest;
    Folder := TPath.Combine(ExtractFileDir(ParamStr(0)), 'LayoutVerification');
    ForceDirectories(Folder);
    Form := TFormRhythmShooterSettings.Create(nil);
    try
      Settings := TRhythmSettings.Defaults;
      Form.ConfigureState(Settings, 320, 180);
      Form.Position := poDesigned;
      Form.Left := -32000;
      Form.Top := -32000;
      Form.Show;
      Writeln('INITIAL_PPI=', Form.CurrentPPI, ' FONT_HEIGHT=', Form.Font.Height);
      CheckLayout(Form);
      if Form.FindComponent('PreviewPause')<>nil then raise Exception.Create('Separate pause button still exists');
      if TButton(Form.FindComponent('PreviewPlay')).Caption<>'再生' then raise Exception.Create('Idle toggle caption is wrong');
      Bitmap:=Form.GetFormImage;PNG:=TPngImage.Create;
      try PNG.Assign(Bitmap);PNG.SaveToFile(TPath.Combine(Folder,'initial.png'));
      finally PNG.Free;Bitmap.Free;end;
      CheckLayout(Form);
      Pages := nil;
      for I := 0 to Form.ComponentCount - 1 do
        if Form.Components[I] is TPageControl then Pages := TPageControl(Form.Components[I]);
      if Pages = nil then raise Exception.Create('Missing settings tabs');
      for D := Low(DPIs) to High(DPIs) do
      begin
        Form.ScaleForPPI(DPIs[D]);
        Writeln('DPI_STEP=',DPIs[D],' actual=',Form.CurrentPPI);
        for WidthIndex := 0 to 1 do
        begin
          if WidthIndex = 0 then LogicalWidth := 1100 else LogicalWidth := 850;
          Form.ClientWidth := MulDiv(LogicalWidth, DPIs[D], 96);
          Form.ClientHeight := MulDiv(760, DPIs[D], 96);
          for Tab := 0 to Pages.PageCount - 1 do
          begin
            if Tab=0 then TButton(Form.FindComponent('AnimationTab')).Click
            else TButton(Form.FindComponent('DesignTab')).Click;
            if Pages.ActivePageIndex<>Tab then raise Exception.Create('Navigation button did not switch pages');
            if TRhythmButton(Form.FindComponent('DesignTab')).Selected<>(Tab=1) then
              raise Exception.Create('Navigation selection was not updated');
            Form.Repaint;
            Application.ProcessMessages;
            CheckLayout(Form);
            Bitmap := Form.GetFormImage;
            PNG := TPngImage.Create;
            try
              PNG.Assign(Bitmap);
              ImagePath := TPath.Combine(Folder, Format('settings-%d-%d-tab%d-step%d.png',
                [DPIs[D], LogicalWidth, Tab, D]));
              PNG.SaveToFile(ImagePath);
            finally
              PNG.Free;
              Bitmap.Free;
            end;
          end;
        end;
      end;
      Settings.Style:=rsFireworks;Settings.FireworksRichness:=100;
      Settings.Designs[8].Memo:='keep design while changing fireworks';
      Form.ConfigureState(Settings,320,180);
      for D:=Low(DPIs) to High(DPIs) do begin
        Form.ScaleForPPI(DPIs[D]);
        Form.ClientWidth:=MulDiv(850,DPIs[D],96);Form.ClientHeight:=MulDiv(760,DPIs[D],96);
        Form.Repaint;Application.ProcessMessages;CheckLayout(Form);
        CheckOptionCaption(Form,'StyleCaption','AnimationStyle');CheckOptionCaption(Form,'DirectionCaption','ScrollDirection');
        CheckOptionCaption(Form,'SensitivityCaption','Sensitivity');CheckOptionCaption(Form,'RichnessCaption','FireworksRichness');
        if TControl(Form.FindComponent('AnimationOptions')).Height>MulDiv(44,Form.CurrentPPI,96) then
          raise Exception.Create('Normal-width options did not fit on one row');
        if not TTrackBar(Form.FindComponent('FireworksRichness')).Parent.Visible then
          raise Exception.Create('Fireworks richness row is hidden');
        if Form.Snapshot.FireworksRichness<>100 then raise Exception.Create('Richness was not restored');
      end;
      Form.Constraints.MinWidth:=0;Form.ClientWidth:=MulDiv(600,Form.CurrentPPI,96);
      Form.Repaint;Application.ProcessMessages;CheckLayout(Form);
      if TControl(Form.FindComponent('AnimationOptions')).Height<=MulDiv(44,Form.CurrentPPI,96) then
        raise Exception.Create('Narrow options did not wrap safely');
      Settings.Style:=rsBall;Form.ConfigureState(Settings,320,180);
      if TTrackBar(Form.FindComponent('FireworksRichness')).Parent.Visible then
        raise Exception.Create('Fireworks richness row is shown for pinball');
      if Form.Snapshot.Designs[8].Memo<>Settings.Designs[8].Memo then
        raise Exception.Create('Style switching erased shooting design memo');
      Form.Close;
    finally
      Form.Free;
    end;
    Writeln('SETTINGS_LAYOUT_DPI_OK');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
