unit RhythmGWave;
// Type.Gの波形・4小節グリッド・シーン帯。音声と計画を借用し、編集結果は所有側へ通知する。
interface
uses System.Classes, Vcl.Controls, Vcl.Graphics, RhythmAudio, RhythmGPlan;
type
  TGTimeEvent = procedure(Sender: TObject; Time: Double) of object;
  TGBoundaryEvent = procedure(Sender: TObject; Index: Integer; Time: Double) of object;
  TGWave = class(TCustomControl)
  private
    FAudio: TRhythmAudio;
    FPlan: TGPlan;
    FStatic: TBitmap;
    FDirty: Boolean;
    FViewStart,FViewSpan,FTime,FDragTime: Double;
    FSelected,FDrag: Integer;
    FOnSelect: TNotifyEvent;
    FOnSeek: TGTimeEvent;
    FOnBoundary: TGBoundaryEvent;
    function XAt(Time: Double): Integer;
    procedure Rebuild;
    procedure SetSelected(Value: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;
    procedure Bind(Audio: TRhythmAudio; Plan: TGPlan);
    procedure View(Start,Span: Double);
    procedure SetTime(Value: Double);
    procedure Render(Target: TCanvas); // 表示と見本出力で同じ描画を使う。Targetは借用する。
    function TimeAt(X: Integer): Double;
    property Selected: Integer read FSelected write SetSelected;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnSeek: TGTimeEvent read FOnSeek write FOnSeek;
    property OnBoundary: TGBoundaryEvent read FOnBoundary write FOnBoundary;
  end;
implementation
uses System.SysUtils, System.Math, System.Types, Winapi.Windows, RhythmControls;
constructor TGWave.Create(Owner: TComponent);
begin
  inherited; ControlStyle:=ControlStyle+[csOpaque]; DoubleBuffered:=True;
  FStatic:=Vcl.Graphics.TBitmap.Create; FDirty:=True; FDrag:=-1; FSelected:=-1; FViewSpan:=1;
  Height:=100; TabStop:=True;
end;
destructor TGWave.Destroy;
begin FStatic.Free; inherited; end;
procedure TGWave.Bind(Audio: TRhythmAudio; Plan: TGPlan);
begin FAudio:=Audio; FPlan:=Plan; FDrag:=-1; FDirty:=True; Invalidate; end;
procedure TGWave.View(Start,Span: Double);
begin
  FViewStart:=Max(0.0,Start); FViewSpan:=Max(0.001,Span); FDirty:=True; Invalidate;
end;
procedure TGWave.SetTime(Value: Double);
begin if Value=FTime then Exit; FTime:=Value; Invalidate; end;
procedure TGWave.Resize;
begin inherited; FDirty:=True; Invalidate; end;
function TGWave.TimeAt(X: Integer): Double;
begin
  Result:=0; if (FPlan=nil) or (ClientWidth<2) then Exit;
  Result:=EnsureRange(FViewStart+EnsureRange(X/(ClientWidth-1),0.0,1.0)*FViewSpan,0.0,FPlan.Duration);
end;
function TGWave.XAt(Time: Double): Integer;
begin Result:=Round((Time-FViewStart)/FViewSpan*Max(1,ClientWidth-1)); end;
procedure TGWave.SetSelected(Value: Integer);
begin FSelected:=Value; Invalidate; end;
procedure TGWave.Rebuild;
var X,I,J,A,B,Y: Integer; Peak,Level: Double; C: TCanvas; T,Step: Double;
begin
  FStatic.SetSize(Max(1,ClientWidth),Max(1,ClientHeight)); C:=FStatic.Canvas;
  C.Brush.Color:=RhythmInput; C.FillRect(Rect(0,0,FStatic.Width,FStatic.Height));
  if (FPlan<>nil) and (FAudio<>nil) then begin
    Level:=0.001; for I:=0 to High(FAudio.Envelope) do Level:=Max(Level,FAudio.Envelope[I]);
    C.Pen.Color:=RGB(93,182,197);
    for X:=0 to ClientWidth-1 do begin
      A:=Max(0,Floor((FViewStart+X/Max(1,ClientWidth)*FViewSpan)*100));
      B:=Min(High(FAudio.Envelope),Ceil((FViewStart+(X+1)/Max(1,ClientWidth)*FViewSpan)*100));
      Peak:=0; for J:=A to B do Peak:=Max(Peak,FAudio.Envelope[J]);
      Y:=Round(Peak/Level*ClientHeight*0.21);
      C.MoveTo(X,ClientHeight div 3-Y); C.LineTo(X,ClientHeight div 3+Y+1);
    end;
    Step:=FPlan.Beat*4; T:=Floor(FViewStart/Step)*Step;
    C.Font.Assign(Font); C.Font.Height:=-MulDiv(11,CurrentPPI,96); C.Font.Color:=RhythmMuted;
    while T<=FViewStart+FViewSpan do begin
      X:=XAt(T); I:=Round(T/Step);
      if I mod 4=0 then begin C.Pen.Color:=RhythmAccent; C.TextOut(X+3,1,Format('%d小節 / %.1fs',[I+1,T])); end
      else C.Pen.Color:=RhythmBorder;
      C.MoveTo(X,0); C.LineTo(X,ClientHeight); T:=T+Step;
    end;
  end;
  FDirty:=False;
end;
procedure TGWave.Paint;
begin Render(Canvas); end;
procedure TGWave.Render(Target: TCanvas);
const Colors: array[0..7] of TColor=($005A788E,$0078906C,$00927083,$00758A9A,$00867C60,$00916F67,$006E8895,$0088798D);
var I,L,R,Y,X: Integer; S: TGScene; Bounds: TRect; Text: string;
begin
  if FDirty then Rebuild; Target.Draw(0,0,FStatic);
  if FPlan=nil then Exit;
  Y:=Round(ClientHeight*0.64); Target.Font.Assign(Font); Target.Font.Height:=-MulDiv(12,CurrentPPI,96);
  Target.Font.Color:=clWhite;
  for I:=0 to High(FPlan.Scenes) do begin
    S:=FPlan.Scenes[I]; L:=XAt(S.Start); R:=XAt(S.Finish);
    if (R<0) or (L>=ClientWidth) then Continue;
    L:=Max(0,L); R:=Min(ClientWidth,R); Bounds:=Rect(L+1,Y+1,R-1,ClientHeight-2);
    if I=FSelected then Target.Brush.Color:=RhythmAccent else Target.Brush.Color:=Colors[S.Game mod 8];
    Target.FillRect(Bounds); Text:=Format('%d %s',[I+1,GNames[S.Game]]);
    InflateRect(Bounds,-4,0); Target.Brush.Style:=bsClear;
    DrawText(Target.Handle,PChar(Text),Length(Text),Bounds,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS);
    Target.Brush.Style:=bsSolid; Target.Pen.Color:=clWhite;
    Target.MoveTo(XAt(S.Start),Y); Target.LineTo(XAt(S.Start),ClientHeight);
  end;
  X:=XAt(FTime); Target.Pen.Color:=clWhite; Target.Pen.Width:=2;
  Target.MoveTo(X,0); Target.LineTo(X,ClientHeight); Target.Pen.Width:=1;
  if FDrag>=0 then begin
    X:=XAt(FDragTime); Target.Pen.Color:=clYellow;
    Target.MoveTo(X,0); Target.LineTo(X,ClientHeight);
  end;
end;
procedure TGWave.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var I: Integer; Time: Double;
begin
  inherited; if (Button<>mbLeft) or (FPlan=nil) then Exit; if CanFocus then SetFocus; Time:=TimeAt(X);
  if Y<Round(ClientHeight*0.64) then begin if Assigned(FOnSeek) then FOnSeek(Self,Time); Exit; end;
  for I:=1 to High(FPlan.Scenes) do if Abs(X-XAt(FPlan.Scenes[I].Start))<=MulDiv(6,CurrentPPI,96) then begin
    FDrag:=I; FDragTime:=FPlan.Scenes[I].Start; MouseCapture:=True; Exit;
  end;
  Selected:=FPlan.SceneAt(Time); if Assigned(FOnSelect) then FOnSelect(Self);
end;
procedure TGWave.MouseMove(Shift: TShiftState; X,Y: Integer);
var Time,Step: Double;
begin
  inherited; if FPlan=nil then Exit;
  if FDrag>=0 then begin
    Time:=TimeAt(X); Step:=4*FPlan.Beat;
    if not (ssShift in Shift) then Time:=Round(Time/Step)*Step;
    FDragTime:=EnsureRange(Time,FPlan.Scenes[FDrag-1].Start+0.25,FPlan.Scenes[FDrag].Finish-0.25);
    Invalidate;
  end else if Y>=Round(ClientHeight*0.64) then Cursor:=crHandPoint else Cursor:=crDefault;
end;
procedure TGWave.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var Index: Integer;
begin
  inherited; if (Button<>mbLeft) or (FDrag<0) then Exit;
  Index:=FDrag; FDrag:=-1; MouseCapture:=False; Invalidate;
  if Assigned(FOnBoundary) then FOnBoundary(Self,Index,FDragTime);
end;
procedure TGWave.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key=VK_ESCAPE) and (FDrag>=0) then begin
    FDrag:=-1; MouseCapture:=False; Invalidate; Key:=0;
  end;
  inherited;
end;
end.
