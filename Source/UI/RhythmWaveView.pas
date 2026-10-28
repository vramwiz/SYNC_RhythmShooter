unit RhythmWaveView;
interface
uses System.Classes, Vcl.Controls, Vcl.Graphics, RhythmAudio, Winapi.Messages;
type
  TRhythmWaveView=class(TCustomControl)
  private
    FAudio:TRhythmAudio;
    FStatic:TBitmap;
    FDirty:Boolean;
    FCursor:Integer;
    procedure Rebuild;
    procedure WMEraseBkgnd(var Message:TWMEraseBkgnd);message WM_ERASEBKGND;
  protected
    procedure Paint;override;
    procedure Resize;override;
  public
    constructor Create(Owner:TComponent);override;
    destructor Destroy;override;
    procedure SetAudio(Audio:TRhythmAudio);
    procedure SetTime(Time:Double);
    property OnMouseDown;
  end;
implementation
uses Winapi.Windows, System.Math, System.Types;
constructor TRhythmWaveView.Create(Owner:TComponent);
begin inherited;ControlStyle:=ControlStyle+[csOpaque];DoubleBuffered:=True;FStatic:=Vcl.Graphics.TBitmap.Create;FDirty:=True;FCursor:=0;end;
destructor TRhythmWaveView.Destroy;
begin FStatic.Free;inherited;end;
procedure TRhythmWaveView.WMEraseBkgnd(var Message:TWMEraseBkgnd);
begin Message.Result:=1;end;
procedure TRhythmWaveView.Resize;
begin inherited;FDirty:=True;Invalidate;end;
procedure TRhythmWaveView.SetAudio(Audio:TRhythmAudio);
begin FAudio:=Audio;FDirty:=True;FCursor:=0;Invalidate;end;
procedure TRhythmWaveView.SetTime(Time:Double);
var Next:Integer;R:TRect;
begin
  Next:=0;if (FAudio<>nil) and (FAudio.Duration>0) then Next:=EnsureRange(Round(Time/FAudio.Duration*ClientWidth),0,Max(0,ClientWidth-1));
  if Next=FCursor then Exit;
  if HandleAllocated then begin R:=Rect(FCursor-2,0,FCursor+3,ClientHeight);InvalidateRect(Handle,@R,False);end;
  FCursor:=Next;
  if HandleAllocated then begin R:=Rect(FCursor-2,0,FCursor+3,ClientHeight);InvalidateRect(Handle,@R,False);end else Invalidate;
end;
procedure TRhythmWaveView.Rebuild;
var X,Y,I,J,First,Last:Integer;Peak:Single;H:TRhythmHit;C:TCanvas;
begin
  FStatic.SetSize(Max(1,ClientWidth),Max(1,ClientHeight));C:=FStatic.Canvas;
  C.Brush.Color:=RGB(16,25,42);C.FillRect(Rect(0,0,FStatic.Width,FStatic.Height));
  if FAudio<>nil then
  begin
    C.Pen.Color:=RGB(64,156,178);
    for X:=0 to FStatic.Width-1 do
    begin
      First:=X*Length(FAudio.Envelope) div FStatic.Width;Last:=(X+1)*Length(FAudio.Envelope) div FStatic.Width-1;Peak:=0;
      for J:=First to Min(High(FAudio.Envelope),Last) do Peak:=Max(Peak,FAudio.Envelope[J]);
      Y:=Round(Peak*FStatic.Height*0.8);C.MoveTo(X,FStatic.Height div 2-Y);C.LineTo(X,FStatic.Height div 2+Y+1);
    end;
    C.Pen.Color:=RGB(240,165,74);
    for H in FAudio.Hits do begin I:=Round(H.Time/FAudio.Duration*FStatic.Width);C.MoveTo(I,0);C.LineTo(I,6);end;
  end;
  FDirty:=False;
end;
procedure TRhythmWaveView.Paint;
begin
  if FDirty then Rebuild;
  Canvas.Draw(0,0,FStatic);if FAudio<>nil then begin Canvas.Pen.Color:=clWhite;Canvas.MoveTo(FCursor,0);Canvas.LineTo(FCursor,ClientHeight);end;
end;
end.
