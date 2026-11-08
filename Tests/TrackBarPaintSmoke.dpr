program TrackBarPaintSmoke;
{$APPTYPE CONSOLE}
// 実trackbarの部分更新をメモリへ描き、全体更新との画素一致を検証する。
uses
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, System.SysUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.Graphics, RhythmControls;

type
  TPaintTrackBar = class(TRhythmTrackBar)
  private
    FImage: TBitmap;
  public
    procedure DefaultHandler(var Message); override;
    property Image: TBitmap read FImage write FImage;
  end;

procedure TPaintTrackBar.DefaultHandler(var Message);
var
  Msg: TMessage absolute Message;
  Draw: TNMCustomDraw;
  Dirty: TRect;
  Saved: Integer;
begin
  if (Msg.Msg <> WM_PAINT) or (Msg.WParam <> 0) or (FImage = nil) then
  begin
    inherited;
    Exit;
  end;
  // 実画面のBeginPaintと同じ更新領域で、画面外のDIBをクリップする。
  if not GetUpdateRect(Handle, Dirty, False) then Exit;
  Saved := SaveDC(FImage.Canvas.Handle);
  try
    IntersectClipRect(FImage.Canvas.Handle, Dirty.Left, Dirty.Top, Dirty.Right, Dirty.Bottom);
    FillChar(Draw, SizeOf(Draw), 0);
    Draw.hdr.hwndFrom := Handle;
    Draw.hdr.code := NM_CUSTOMDRAW;
    Draw.dwDrawStage := CDDS_PREPAINT;
    Draw.hdc := FImage.Canvas.Handle;
    Draw.rc := ClientRect;
    Msg.Result := Perform(CN_NOTIFY, 0, LPARAM(@Draw));
  finally
    RestoreDC(FImage.Canvas.Handle, Saved);
    ValidateRect(Handle, nil);
  end;
end;

procedure Need(Condition: Boolean; const Text: string);
begin
  if not Condition then raise Exception.Create(Text);
end;

procedure CheckRepaint(Slider: TPaintTrackBar; Partial, Full: TBitmap; Position: Integer;
  const Dirty: TRect; var Checks: Integer);
var
  X, Y: Integer;
  OldThumb: TRect;
begin
  SendMessage(Slider.Handle, TBM_GETTHUMBRECT, 0, LPARAM(@OldThumb));
  // 標準つまみの更新範囲からはみ出した、独自つまみの青い端を再現する。
  Partial.Canvas.Pixels[OldThumb.Left - 1, (OldThumb.Top + OldThumb.Bottom) div 2] := RhythmAccent;
  Slider.Image := nil;
  SendMessage(Slider.Handle, TBM_SETPOS, 1, Position);
  // CDRF_SKIPDEFAULTで省略するネイティブ描画に依存せず、移動後の矩形を更新する。
  SendMessage(Slider.Handle, WM_SIZE, SIZE_RESTORED, MakeLParam(Slider.Width, Slider.Height));
  ValidateRect(Slider.Handle, nil);
  InvalidateRect(Slider.Handle, @Dirty, False);
  Slider.Image := Partial;
  Slider.Perform(WM_PAINT, 0, 0);
  Slider.Image := Full;
  InvalidateRect(Slider.Handle, nil, False);
  Slider.Perform(WM_PAINT, 0, 0);
  for Y := 0 to Partial.Height - 1 do
    if not CompareMem(Partial.ScanLine[Y], Full.ScanLine[Y], Partial.Width * 4) then
      for X := 0 to Partial.Width - 1 do
        Need(Partial.Canvas.Pixels[X, Y] = Full.Canvas.Pixels[X, Y],
          Format('Stale slider pixel at %d,%d position=%d ppi=%d', [X, Y, Position, Slider.CurrentPPI]));
  Inc(Checks);
end;

const
  PPIs: array[0..3] of Integer = (96, 120, 144, 192);
  Positions: array[0..8] of Integer = (50, 51, 75, 99, 100, 20, 19, 0, 50);
var
  Form: TForm;
  Slider: TPaintTrackBar;
  Partial, Full: TBitmap;
  Thumb, Dirty: TRect;
  PPI, Position, Checks: Integer;
begin
  Form := nil;
  Partial := nil;
  Full := nil;
  Checks := 0;
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    Partial := TBitmap.Create;
    Full := TBitmap.Create;
    Partial.PixelFormat := pf32bit;
    Full.PixelFormat := pf32bit;
    for PPI in PPIs do
    begin
      Form := TForm.CreateNew(nil);
      try
        Slider := TPaintTrackBar.Create(Form);
        Slider.Parent := Form;
        Slider.SetBounds(0, 0, 300, 32);
        Slider.TickStyle := tsNone;
        Slider.Max := 100;
        Form.ScaleForPPI(PPI);
        Form.Scaled := False;
        Form.Show;
        Partial.SetSize(Slider.Width, Slider.Height);
        Full.SetSize(Slider.Width, Slider.Height);
        Slider.Image := Partial;
        InvalidateRect(Slider.Handle, nil, False);
        Slider.Perform(WM_PAINT, 0, 0);
        Need(Partial.Canvas.Pixels[Slider.Width - 1, 0] = ColorToRGB(RhythmSurface),
          'Native trackbar did not paint into the test bitmap');
        for Position in Positions do
        begin
          SendMessage(Slider.Handle, TBM_GETTHUMBRECT, 0, LPARAM(@Thumb));
          CheckRepaint(Slider, Partial, Full, Position, Thumb, Checks);
          Dirty := Rect(Slider.Width div 2, 0, Slider.Width div 2 + 1, Slider.Height);
          CheckRepaint(Slider, Partial, Full, Position, Dirty, Checks);
        end;
      finally
        FreeAndNil(Form);
      end;
    end;
    WriteLn('Trackbar repaint PASS comparisons=', Checks);
  except
    on E: Exception do
    begin
      WriteLn(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
  Form.Free;
  Full.Free;
  Partial.Free;
end.
