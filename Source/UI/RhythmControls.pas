unit RhythmControls;

interface

uses System.Classes, Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Forms;

const
  RhythmBackground = TColor($00201B18);
  RhythmSurface = TColor($002B2420);
  RhythmInput = TColor($00201A16);
  RhythmRaised = TColor($0039302B);
  RhythmBorder = TColor($0052463F);
  RhythmText = TColor($00EEE6E0);
  RhythmMuted = TColor($00AD9B8E);
  RhythmAccent = TColor($00DDA041);

type
  TRhythmButton = class(TButton)
  private
    FSelected, FPrimary, FHover: Boolean;
    procedure SetSelected(Value: Boolean);
    procedure CNDrawItem(var Message: TWMDrawItem); message CN_DRAWITEM;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure SetButtonStyle(ADefault: Boolean); override;
  public
    property Selected: Boolean read FSelected write SetSelected;
    property Primary: Boolean read FPrimary write FPrimary;
  end;

  TRhythmComboBox = class(TComboBox)
  protected
    procedure CreateWnd; override;
    procedure DrawItem(Index: Integer; Rect: TRect; State: TOwnerDrawState); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TRhythmTrackBar = class(TTrackBar)
  private
    procedure CNNotify(var Message: TWMNotify); message CN_NOTIFY;
  end;

  TRhythmPreviewSurface = class(TCustomControl)
  private
    FOnPaint: TNotifyEvent;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Canvas;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
  end;

procedure ApplyRhythmColors(Control: TWinControl);
procedure ApplyRhythmTitleBar(Form: TForm);

implementation

uses System.Types, System.Math, Winapi.CommCtrl, Winapi.Dwmapi, Winapi.UxTheme,
  Vcl.ExtCtrls;

type
  TWindowAccess = class(TWinControl);
  TGraphicAccess = class(TControl);

procedure TRhythmButton.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := (Params.Style and not $000F) or BS_OWNERDRAW;
end;

procedure TRhythmButton.SetButtonStyle(ADefault: Boolean);
begin
  // ネイティブのキー操作を保ち、既定ボタン変更で所有者描画を解除しない。
  Invalidate;
end;

procedure TRhythmButton.SetSelected(Value: Boolean);
begin FSelected := Value; Invalidate; end;

procedure TRhythmButton.CMMouseEnter(var Message: TMessage);
begin inherited; FHover := True; Invalidate; end;

procedure TRhythmButton.CMMouseLeave(var Message: TMessage);
begin inherited; FHover := False; Invalidate; end;

procedure TRhythmButton.CNDrawItem(var Message: TWMDrawItem);
var C: TCanvas; R: TRect; Radius: Integer; Highlighted: Boolean;
begin
  if (Message.DrawItemStruct=nil) or (Message.DrawItemStruct.hDC=0) then
  begin Message.Result:=1;Exit;end;
  C := TCanvas.Create;
  try
    C.Handle := Message.DrawItemStruct.hDC;
    R := Message.DrawItemStruct.rcItem;
    C.Brush.Color := RhythmSurface; C.FillRect(R);
    Highlighted := (FPrimary or FSelected) and Enabled;
    if Highlighted then C.Brush.Color := TColor($00895121)
    else if FHover and Enabled then C.Brush.Color := TColor($004B4036)
    else C.Brush.Color := RhythmRaised;
    if Highlighted or Focused then C.Pen.Color := RhythmAccent else C.Pen.Color := RhythmBorder;
    Radius := MulDiv(6, CurrentPPI, 96);
    InflateRect(R, -1, -1); C.RoundRect(R, Radius, Radius);
    C.Font.Assign(Font);
    if Enabled then C.Font.Color := RhythmText else C.Font.Color := RhythmMuted;
    C.Brush.Style := bsClear;
    if Message.DrawItemStruct.itemState and ODS_SELECTED <> 0 then OffsetRect(R, 1, 1);
    DrawText(C.Handle, PChar(Caption), Length(Caption), R,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
    if Focused then begin InflateRect(R, -MulDiv(4,CurrentPPI,96), -MulDiv(4,CurrentPPI,96)); C.DrawFocusRect(R); end;
  finally
    C.Handle := 0; C.Free;
  end;
  Message.Result := 1;
end;

constructor TRhythmComboBox.Create(AOwner: TComponent);
begin inherited; Style := csOwnerDrawFixed; Color := RhythmInput; Font.Color := RhythmText; end;

procedure TRhythmComboBox.CreateWnd;
var H: Integer;
begin
  inherited;
  H := Max(MulDiv(20,Abs(Font.Height),13),Abs(Font.Height)+MulDiv(6,Abs(Font.Height),13));
  // ItemHeightのsetterはRecreateWndを呼ぶため、生成中はネイティブへ直接反映する。
  SendMessage(Handle,CB_SETITEMHEIGHT,0,H);
  SendMessage(Handle,CB_SETITEMHEIGHT,WPARAM(-1),H);
  SetWindowTheme(Handle,'DarkMode_CFD',nil);
end;

procedure TRhythmComboBox.DrawItem(Index: Integer; Rect: TRect; State: TOwnerDrawState);
begin
  if odSelected in State then Canvas.Brush.Color := RhythmRaised else Canvas.Brush.Color := RhythmInput;
  Canvas.FillRect(Rect); Canvas.Font.Assign(Font);
  if Enabled then Canvas.Font.Color := RhythmText else Canvas.Font.Color := RhythmMuted;
  Inc(Rect.Left,MulDiv(8,CurrentPPI,96));
  if (Index>=0) and (Index<Items.Count) then
    DrawText(Canvas.Handle,PChar(Items[Index]),Length(Items[Index]),Rect,DT_LEFT or DT_VCENTER or DT_SINGLELINE);
end;

procedure TRhythmTrackBar.CNNotify(var Message: TWMNotify);
var Draw: PNMCustomDraw; C: TCanvas; Channel, Thumb, R: TRect; Y, H: Integer;
begin
  if Message.NMHdr.code <> NM_CUSTOMDRAW then begin inherited; Exit; end;
  Draw := PNMCustomDraw(Message.NMHdr);
  if Draw.dwDrawStage <> CDDS_PREPAINT then begin inherited; Exit; end;
  if Draw.hdc = 0 then begin Message.Result := CDRF_SKIPDEFAULT; Exit; end;
  C := TCanvas.Create;
  try
    C.Handle := Draw.hdc; C.Brush.Color := RhythmSurface; C.FillRect(ClientRect);
    SendMessage(Handle,TBM_GETCHANNELRECT,0,LPARAM(@Channel));
    SendMessage(Handle,TBM_GETTHUMBRECT,0,LPARAM(@Thumb));
    Y := (Thumb.Top+Thumb.Bottom) div 2; H := System.Math.Max(2,MulDiv(3,CurrentPPI,96));
    R := Rect(Channel.Left,Y-H div 2,Channel.Right,Y+(H+1) div 2);
    C.Brush.Color := RhythmBorder; C.Pen.Color := RhythmBorder; C.RoundRect(R,H,H);
    R.Right := (Thumb.Left+Thumb.Right) div 2;
    C.Brush.Color := RhythmAccent; C.Pen.Color := RhythmAccent; C.RoundRect(R,H,H);
    R := Rect(R.Right-MulDiv(5,CurrentPPI,96),Y-MulDiv(7,CurrentPPI,96),
      R.Right+MulDiv(5,CurrentPPI,96),Y+MulDiv(7,CurrentPPI,96));
    if not Enabled then begin C.Brush.Color := RhythmMuted; C.Pen.Color := RhythmMuted; end;
    C.RoundRect(R,H,H);
  finally
    C.Handle := 0; C.Free;
  end;
  Message.Result := CDRF_SKIPDEFAULT;
end;

constructor TRhythmPreviewSurface.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle+[csOpaque];
  ParentBackground := False; DoubleBuffered := True;
end;

procedure TRhythmPreviewSurface.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin Message.Result := 1; end;

procedure TRhythmPreviewSurface.Paint;
begin
  if Assigned(FOnPaint) then FOnPaint(Self)
  else begin Canvas.Brush.Color := RhythmBackground; Canvas.FillRect(ClientRect); end;
end;

procedure ApplyRhythmColors(Control: TWinControl);
var I: Integer;
begin
  TWindowAccess(Control).ParentBackground := False;
  TWindowAccess(Control).Color := RhythmSurface;
  TWindowAccess(Control).Font.Color := RhythmText;
  if (Control is TCustomEdit) or (Control is TComboBox) then
    TWindowAccess(Control).Color := RhythmInput;
  if Control is TEdit then TEdit(Control).BorderStyle := bsNone;
  if Control is TMemo then TMemo(Control).BorderStyle := bsNone;
  if Control is TPanel then TPanel(Control).BevelOuter := bvNone;
  if Control is TScrollBox then TScrollBox(Control).BorderStyle := bsNone;
  for I:=0 to Control.ControlCount-1 do
    if Control.Controls[I] is TWinControl then ApplyRhythmColors(TWinControl(Control.Controls[I]))
    else TGraphicAccess(Control.Controls[I]).Font.Color := RhythmText;
end;

procedure ApplyRhythmTitleBar(Form: TForm);
var Enabled: BOOL;
begin
  Enabled := True;
  if DwmSetWindowAttribute(Form.Handle,20,@Enabled,SizeOf(Enabled))<>S_OK then
    DwmSetWindowAttribute(Form.Handle,19,@Enabled,SizeOf(Enabled));
end;

end.
