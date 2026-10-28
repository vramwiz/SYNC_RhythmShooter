program PreviewRenderSmoke;
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Types, System.Classes,
  Vcl.Forms, Vcl.Graphics, Vcl.Controls,
  RhythmAudio, RhythmScene, RhythmControls;

type
  TPaintCapture = class
    Count: Integer;
    LastColor: TColor;
    procedure Paint(Sender: TObject);
  end;

procedure TPaintCapture.Paint(Sender: TObject);
begin
  Inc(Count);
  LastColor := RGB(24 + Count mod 80, 42, 64);
  with TRhythmPreviewSurface(Sender).Canvas do
  begin
    Brush.Color := LastColor;
    FillRect(TRhythmPreviewSurface(Sender).ClientRect);
  end;
end;

function SameHeader(A, B: TBitmap): Boolean;
var X, Y: Integer;
begin
  for Y := 4 to 64 do
    for X := 4 to 460 do
      if A.Canvas.Pixels[X,Y] <> B.Canvas.Pixels[X,Y] then Exit(False);
  Result := True;
end;

var
  Renderer: TRhythmRenderer;
  Audio: TRhythmAudio;
  Expected, Actual, Shot: TBitmap;
  Host: TForm;
  Surface: TRhythmPreviewSurface;
  Capture: TPaintCapture;
  Direction, Backend, Frame, I: Integer;
  Time: Double;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    Renderer := TRhythmRenderer.Create;
    Audio := TRhythmAudio.Create;
    Expected := TBitmap.Create;
    Actual := TBitmap.Create;
    try
      Audio.Duration := 20;
      Audio.UpdateSoundBounds;
      Expected.SetSize(640,360);
      Actual.SetSize(640,360);
      for Backend := 0 to 1 do
      begin
        Renderer.UseD2D := Backend = 1;
        for Direction := 0 to 1 do
          for Frame := 0 to 1 do
          begin
            if Frame = 0 then Time := 0.5 else Time := 30;
            Renderer.Render(Expected,nil,Time,Direction,'');
            Renderer.Render(Actual,Audio,Time,Direction,'');
            if not SameHeader(Expected,Actual) then
              raise Exception.Create('Prepared or completed scene contains a status overlay');
            Renderer.Render(Actual,nil,Time,Direction,'Missing music warning');
            if SameHeader(Expected,Actual) then
              raise Exception.Create('Warning overlay disappeared');
          end;
      end;
      Writeln('NORMAL_OVERLAY_HIDDEN_WARNING_RETAINED');
    finally
      Actual.Free;Expected.Free;Audio.Free;Renderer.Free;
    end;
    Host := TForm.CreateNew(nil);
    Capture := TPaintCapture.Create;
    Shot := TBitmap.Create;
    try
      Host.Position := poDesigned;
      Host.SetBounds(-32000,-32000,320,180);
      Surface := TRhythmPreviewSurface.Create(Host);
      Surface.Parent := Host;
      Surface.Align := alClient;
      Surface.OnPaint := Capture.Paint;
      Host.Show;
      if not Surface.DoubleBuffered then raise Exception.Create('Preview is not double buffered');
      Shot.SetSize(Surface.Width,Surface.Height);
      Shot.Canvas.Brush.Color := clFuchsia;
      Shot.Canvas.FillRect(Rect(0,0,Shot.Width,Shot.Height));
      Surface.Perform(WM_ERASEBKGND,WPARAM(Shot.Canvas.Handle),0);
      if Shot.Canvas.Pixels[10,10] <> clFuchsia then
        raise Exception.Create('Preview erased the background between frames');
      for I := 1 to 120 do
      begin
        Surface.Invalidate;
        Surface.Update;
        Surface.PaintTo(Shot.Canvas.Handle,0,0);
        if Shot.Canvas.Pixels[10,10] <> Capture.LastColor then
          raise Exception.Create('Preview did not publish a completed frame');
      end;
      if Capture.Count < 120 then raise Exception.Create('Continuous repaint did not run');
      Host.Close;
      Writeln('BUFFERED_PREVIEW_120_FRAMES_NO_BACKGROUND_ERASE');
    finally
      Shot.Free;Host.Free;Capture.Free;
    end;
  except
    on E: Exception do
    begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
end.
