program SettingsLayoutSmoke;
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RhythmSettings, RhythmDesignFrame, RhythmControls, SYNC_RhythmShooter_SettingsForm;

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
