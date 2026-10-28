program SettingsFormSmoke;
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.Graphics, Vcl.StdCtrls, Vcl.ExtCtrls,
  RhythmSettings, RhythmDesignFrame, AviUtl2FilterTypes,
  SYNC_RhythmShooter_SettingsForm, SYNC_RhythmShooter_FilterPlugin;

type
  TExceptionCapture = class
    ErrorText: string;
    SettingsSeen: Boolean;
    procedure HandleException(Sender: TObject; E: Exception);
    procedure CloseSettings(Sender: TObject);
  end;

procedure TExceptionCapture.HandleException(Sender: TObject; E: Exception);
begin
  ErrorText := E.ClassName + ': ' + E.Message;
end;

procedure TExceptionCapture.CloseSettings(Sender: TObject);
var I: Integer;
begin
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I].Visible then
    begin
      if Screen.Forms[I] is TFormRhythmShooterSettings then
        SettingsSeen := True
      else
        ErrorText := 'Unexpected modal window: ' + Screen.Forms[I].Caption;
      Screen.Forms[I].ModalResult := mrCancel;
    end;
end;

var
  Form: TFormRhythmShooterSettings;
  Host: TForm;
  Editor: TRhythmDesignFrame;
  Capture: TExceptionCapture;
  Settings: TRhythmSettings;
  Image: TBitmap;
  Pages: TPageControl;
  CloseTimer: TTimer;
  Table: PFILTER_PLUGIN_TABLE;
  SettingsButton: PFILTER_ITEM_BUTTON;
  Phase: string;
  Iteration, I: Integer;
begin
  Capture := TExceptionCapture.Create;
  try
    try
      Application.Initialize;
      Application.ShowMainForm := False;
      Application.OnException := Capture.HandleException;
      Phase := 'create unparented design frame';
      Editor := TRhythmDesignFrame.Create(nil);
      Editor.Free;
      Phase := 'parent design frame after assigning settings';
      Host := TForm.CreateNew(nil);
      try
        Editor := TRhythmDesignFrame.Create(Host);
        Settings := TRhythmSettings.Defaults;
        Settings.Designs[6].Memo := 'Retained before parenting';
        Editor.Designs := Settings.Designs;
        Editor.Parent := Host;
        for I := 0 to Editor.ComponentCount - 1 do
          if (Editor.Components[I] is TMemo) and (Editor.Components[I].Tag = 6) then
            if TMemo(Editor.Components[I]).Text <> Settings.Designs[6].Memo then
              raise Exception.Create('Pre-parenting memo was not restored');
      finally
        Host.Free;
      end;
      for Iteration := 1 to 2 do
      begin
        Phase := 'create settings form';
        Form := TFormRhythmShooterSettings.Create(nil);
        try
          Phase := 'configure settings form';
          Settings := TRhythmSettings.Defaults;
          Settings.Direction := Iteration - 1;
          Form.ConfigureState(Settings, 320, 180);
          Form.Position := poDesigned;
          Form.SetBounds(-32000, -32000, 1100, 760);
          Phase := 'show and paint settings form';
          Form.Show;
          Pages := nil;
          for I := 0 to Form.ComponentCount - 1 do
            if Form.Components[I] is TPageControl then
              Pages := TPageControl(Form.Components[I]);
          if (Pages = nil) or (Pages.PageCount <> 2) then
            raise Exception.Create('Animation and custom design pages are required');
          Image := TBitmap.Create;
          try
            Image.SetSize(Form.ClientWidth, Form.ClientHeight);
            for I := 0 to Pages.PageCount - 1 do
            begin
              Pages.ActivePageIndex := I;
              Form.Repaint;
              Application.ProcessMessages;
              Form.PaintTo(Image.Canvas.Handle, 0, 0);
              if Capture.ErrorText <> '' then
                raise Exception.Create(Capture.ErrorText);
            end;
          finally
            Image.Free;
          end;
          if Form.Snapshot.Direction <> Settings.Direction then
            raise Exception.Create('Configured direction was not retained');
          Form.Close;
        finally
          Phase := 'destroy settings form';
          Form.Free;
        end;
      end;
      Phase := 'invoke plugin settings button';
      if InitializeRhythmShooterPlugin(0) <> 1 then
        raise Exception.Create('Plugin initialization failed');
      try
        Table := GetRhythmShooterFilterTable;
        SettingsButton := PFILTER_ITEM_BUTTON(PPointer(NativeUInt(Table.Items) + 3 * SizeOf(Pointer))^);
        if string(SettingsButton.ItemType) <> 'button' then
          raise Exception.Create('Settings button is missing');
        CloseTimer := TTimer.Create(nil);
        try
          CloseTimer.Interval := 100;
          CloseTimer.OnTimer := Capture.CloseSettings;
          for Iteration := 1 to 2 do
          begin
            Capture.SettingsSeen := False;
            SettingsButton.Callback(nil);
            if not Capture.SettingsSeen then
              raise Exception.Create('Settings callback did not display the settings form');
            if Capture.ErrorText <> '' then
              raise Exception.Create(Capture.ErrorText);
          end;
        finally
          CloseTimer.Free;
        end;
      finally
        FinalizeRhythmShooterPlugin;
      end;
      Writeln('SETTINGS_FORM_LIFECYCLE_OK');
    except
      on E: Exception do
      begin
        Writeln(Phase + ': ' + E.ClassName + ': ' + E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Application.OnException := nil;
    Capture.Free;
  end;
end.
