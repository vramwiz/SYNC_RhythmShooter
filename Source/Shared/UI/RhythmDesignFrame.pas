unit RhythmDesignFrame;
interface
uses System.Classes,Vcl.Forms,Vcl.Controls,Vcl.ExtCtrls,Vcl.StdCtrls,
  RhythmDesignTypes,RhythmCodexClient,RhythmDesignRequest,RhythmScene,RhythmStyles,RhythmPlanRef;
type
  TRhythmDesignFrame=class(TFrame)
  private
    FScroll:TScrollBox;
    FInitial,FCurrent:array[0..RHYTHM_DESIGN_COUNT-1] of TImage;
    FCurrentLabels,FStatus:array[0..RHYTHM_DESIGN_COUNT-1] of TLabel;
    FMemos:array[0..RHYTHM_DESIGN_COUNT-1] of TMemo;
    FCancel,FAdopt:array[0..RHYTHM_DESIGN_COUNT-1] of TButton;
    FDesigns:TRhythmDesigns;
    FRenderer:TRhythmRenderer;
    FWorker:TRhythmCodexJob;
    FRequest:TRhythmDesignRequest;
    FActiveId:string;
    FCandidate:TRhythmDesign;
    FCandidateIndex:Integer;
    FTimer:TTimer;
    FUpdating,FBusy:Boolean;
    FOnChange,FOnBusyChange:TNotifyEvent;
    procedure Browse(Sender:TObject);
    procedure Reset(Sender:TObject);
    procedure MemoChange(Sender:TObject);
    procedure Generate(Sender:TObject);
    procedure Cancel(Sender:TObject);
    procedure Adopt(Sender:TObject);
    procedure Tick(Sender:TObject);
    procedure SetBusy(Value:Boolean);
    procedure Refresh(Index:Integer);
    procedure Changed;
    procedure SetDesigns(const Value:TRhythmDesigns);
    procedure BuildControls;
  protected
    procedure SetParent(AParent:TWinControl);override;
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    property Designs:TRhythmDesigns read FDesigns write SetDesigns;
    property Busy:Boolean read FBusy;
    property OnChange:TNotifyEvent read FOnChange write FOnChange;
    property OnBusyChange:TNotifyEvent read FOnBusyChange write FOnBusyChange;
  end;
implementation
{$R *.dfm}
uses Winapi.Windows,System.SysUtils,System.IOUtils,System.Types,System.Math,Vcl.Graphics,
  RhythmPaths,RhythmDesignImages,Vcl.Dialogs,RhythmControls;
function InitialBitmap(Index:Integer;Renderer:TRhythmRenderer):TBitmap;
var Info:TRhythmDesignInfo;X,Y:Integer;P:PByte;
begin
  Info:=DesignInfo(Index);
  if Info.Background then begin
    Result:=TBitmap.Create;Result.PixelFormat:=pf32bit;Result.SetSize(256,192);Renderer.StandardBackgroundPreview(Result,Index div 3,Index mod 3);
  end else begin
    if not FileExists(TPath.Combine(AssetFolder,Info.Id+'.bmp')) then begin
      Result:=TBitmap.Create;Result.PixelFormat:=pf32bit;Result.SetSize(128,96);
      Result.Canvas.Brush.Color:=RGB(7,13,29);Result.Canvas.FillRect(Rect(0,0,128,96));
      Result.Canvas.Font.Color:=clGray;Result.Canvas.TextOut(12,38,'標準画像なし');Exit;
    end;
    Result:=ReadDesignBitmap(TPath.Combine(AssetFolder,Info.Id+'.bmp'));
    for Y:=0 to Result.Height-1 do begin P:=Result.ScanLine[Y];for X:=0 to Result.Width-1 do begin
      if (P[0]=255) and (P[1]=0) and (P[2]=255) then begin P[0]:=0;P[1]:=0;P[2]:=0;P[3]:=0;end;Inc(P,4);
    end;end;
  end;
end;
constructor TRhythmDesignFrame.Create(AOwner:TComponent);
begin
  inherited;Width:=MulDiv(1060,CurrentPPI,96);Height:=MulDiv(600,CurrentPPI,96);DoubleBuffered:=True;FUpdating:=True;FCandidateIndex:=-1;
  FRenderer:=TRhythmRenderer.Create;FRenderer.ConfigureStyle(rsShooting,Default(TRhythmPlanRef));
  if Parent<>nil then BuildControls;
end;
procedure TRhythmDesignFrame.SetParent(AParent:TWinControl);
begin
  inherited;
  // 子コントロールの生成は親ウィンドウへ接続した後に行う。
  if (AParent<>nil) and (FRenderer<>nil) and (FScroll=nil) then BuildControls;
end;
procedure TRhythmDesignFrame.BuildControls;
const Order:array[0..14] of Integer=(6,7,8,13,14,9,10,11,12,0,1,2,3,4,5);
var Row,Pane:TPanel;I,K:Integer;Info:TRhythmDesignInfo;L:TLabel;B:TButton;Bitmap:TBitmap;
  function S(Value:Integer):Integer;
  begin Result:=MulDiv(Value,CurrentPPI,96);end;
  function LabelAt(const Text:string;X,Y,W:Integer):TLabel;
  begin Result:=TLabel.Create(Self);Result.Parent:=Row;Result.AutoSize:=False;Result.SetBounds(S(X),S(Y),S(W),S(22));Result.Caption:=Text;end;
  function ImageAt(X:Integer):TImage;
  begin
    Pane:=TPanel.Create(Self);Pane.Parent:=Row;Pane.Color:=RGB(7,13,29);Pane.ParentBackground:=False;Pane.BevelOuter:=bvNone;Pane.SetBounds(S(X),S(46),S(128),S(96));
    Result:=TImage.Create(Self);Result.Parent:=Pane;Result.Align:=alClient;Result.Proportional:=True;Result.Center:=True;Result.Stretch:=True;
  end;
  function ButtonAt(const Text:string;X,W:Integer;Click:TNotifyEvent):TButton;
  begin Result:=TRhythmButton.Create(Self);Result.Parent:=Row;Result.SetBounds(S(X),S(45),S(W),S(30));Result.Caption:=Text;Result.Tag:=I;Result.OnClick:=Click;end;
begin
  FUpdating:=True;
  FScroll:=TScrollBox.Create(Self);FScroll.Parent:=Self;FScroll.Align:=alClient;FScroll.HorzScrollBar.Visible:=True;FScroll.VertScrollBar.Tracking:=True;FScroll.BorderStyle:=bsNone;FScroll.DoubleBuffered:=True;
  for K:=High(Order) downto 0 do begin
    I:=Order[K];Info:=RhythmDesignTypes.DesignInfo(I);Row:=TPanel.Create(Self);Row.Parent:=FScroll;Row.Constraints.MinWidth:=S(820);Row.SetBounds(0,0,Max(S(820),FScroll.ClientWidth),S(208));Row.Align:=alTop;Row.BevelOuter:=bvNone;
    L:=LabelAt(Info.Title+'  '+IntToStr(Info.Width)+' × '+IntToStr(Info.Height),12,5,760);L.Font.Style:=[fsBold];
    LabelAt('初期',12,25,120);FCurrentLabels[I]:=LabelAt('現在',152,25,120);
    FInitial[I]:=ImageAt(12);FCurrent[I]:=ImageAt(152);
    Bitmap:=InitialBitmap(I,FRenderer);try FInitial[I].Picture.Assign(Bitmap);finally Bitmap.Free;end;
    B:=ButtonAt('参照...',300,86,Browse);B.Name:='DesignBrowse'+IntToStr(I);
    B:=ButtonAt('AI作成',394,100,Generate);B.Name:='DesignGenerate'+IntToStr(I);
    FCancel[I]:=ButtonAt('取消',502,75,Cancel);FAdopt[I]:=ButtonAt('候補を採用',585,100,Adopt);
    B:=ButtonAt('初期に戻す',693,100,Reset);B.Name:='DesignReset'+IntToStr(I);
    L:=LabelAt('AI画像の希望（空欄でも解像度・向き・透過を自動指定）',300,82,470);L.Width:=Max(S(470),Row.ClientWidth-S(312));L.Anchors:=[akLeft,akTop,akRight];
    FMemos[I]:=TMemo.Create(Self);FMemos[I].Parent:=Row;FMemos[I].SetBounds(S(300),S(105),Max(S(470),Row.ClientWidth-S(312)),S(63));FMemos[I].Anchors:=[akLeft,akTop,akRight];FMemos[I].MaxLength:=2000;FMemos[I].ScrollBars:=ssVertical;FMemos[I].Tag:=I;FMemos[I].Text:=FDesigns[I].Memo;FMemos[I].OnChange:=MemoChange;
    FStatus[I]:=LabelAt('標準素材',12,178,760);FStatus[I].Width:=Row.ClientWidth-S(24);FStatus[I].Anchors:=[akLeft,akTop,akRight];
    Refresh(I);
  end;
  FUpdating:=False;FTimer:=TTimer.Create(Self);FTimer.Interval:=100;FTimer.OnTimer:=Tick;
  ApplyRhythmColors(Self);
end;
destructor TRhythmDesignFrame.Destroy;
begin
  FUpdating:=True;FOnChange:=nil;FOnBusyChange:=nil;
  if FTimer<>nil then FTimer.Enabled:=False;
  if FWorker<>nil then begin FWorker.Cancel;FWorker.WaitFor;FreeAndNil(FWorker);end;
  FRenderer.Free;inherited;
end;
procedure TRhythmDesignFrame.SetDesigns(const Value:TRhythmDesigns);
var I:Integer;
begin
  if FWorker<>nil then begin FActiveId:='';FWorker.Cancel;end;
  FDesigns:=Value;FCandidateIndex:=-1;FUpdating:=True;
  // 親が未設定でも設定値を保持し、接続時に各行へ反映する。
  if FScroll=nil then Exit;
  try for I:=0 to High(FDesigns) do begin FMemos[I].Text:=FDesigns[I].Memo;Refresh(I);end;
  finally FUpdating:=False;end;
end;
procedure TRhythmDesignFrame.Refresh(Index:Integer);
var Selected:TRhythmDesign;Bitmap:TBitmap;
begin
  Selected:=FDesigns[Index];FCurrentLabels[Index].Caption:='現在';FStatus[Index].Caption:='標準素材';
  if FCandidateIndex=Index then begin Selected:=FCandidate;FCurrentLabels[Index].Caption:='候補（未採用）';FStatus[Index].Caption:='生成候補を確認し「候補を採用」または「取消」を選んでください。';end;
  try
    if Selected.Path='' then FCurrent[Index].Picture.Assign(FInitial[Index].Picture)
    else begin
      Bitmap:=ReadDesignBitmap(ResolveDesignImage(Selected),128,96,True);try FCurrent[Index].Picture.Assign(Bitmap);finally Bitmap.Free;end;
      if FCandidateIndex<>Index then FStatus[Index].Caption:='カスタム素材を使用中（初期素材は保持）';
    end;
  except on E:Exception do begin FCurrent[Index].Picture.Assign(FInitial[Index].Picture);FStatus[Index].Caption:=E.Message;end;end;
  FAdopt[Index].Enabled:=not FBusy and (FCandidateIndex=Index);
  FCancel[Index].Enabled:=(FCandidateIndex=Index) or (FBusy and (FRequest.Index=Index));
end;
procedure TRhythmDesignFrame.Changed;
begin if Assigned(FOnChange) then FOnChange(Self);end;
procedure TRhythmDesignFrame.Browse(Sender:TObject);
var Dialog:TOpenDialog;Index:Integer;Imported:TRhythmDesign;
begin
  if FBusy then Exit;Index:=TControl(Sender).Tag;Dialog:=TOpenDialog.Create(Self);
  try
    Dialog.Filter:='画像 (*.png;*.bmp;*.jpg;*.jpeg)|*.png;*.bmp;*.jpg;*.jpeg';Dialog.Options:=[ofFileMustExist,ofPathMustExist,ofEnableSizing];
    if Dialog.Execute then try
      Imported:=ImportDesignImage(Dialog.FileName,Index);Imported.Memo:=FDesigns[Index].Memo;FDesigns[Index]:=Imported;
      if FCandidateIndex=Index then begin FCandidateIndex:=-1;FActiveId:='';end;Refresh(Index);Changed;
    except on E:Exception do FStatus[Index].Caption:=E.Message;end;
  finally Dialog.Free;end;
end;
procedure TRhythmDesignFrame.Reset(Sender:TObject);
var Index:Integer;
begin
  if FBusy then Exit;Index:=TControl(Sender).Tag;FDesigns[Index].Path:='';FDesigns[Index].SHA256:='';
  if FCandidateIndex=Index then begin FCandidateIndex:=-1;FActiveId:='';end;Refresh(Index);Changed;
end;
procedure TRhythmDesignFrame.MemoChange(Sender:TObject);
var Index:Integer;
begin
  if FUpdating then Exit;Index:=TControl(Sender).Tag;FDesigns[Index].Memo:=FMemos[Index].Text;
  if FCandidateIndex=Index then begin FCandidateIndex:=-1;FActiveId:='';Refresh(Index);end;
end;
procedure TRhythmDesignFrame.SetBusy(Value:Boolean);
var I:Integer;
begin
  FBusy:=Value;if Assigned(FOnBusyChange) then FOnBusyChange(Self);
  for I:=0 to ComponentCount-1 do if (Components[I] is TButton) or (Components[I] is TMemo) then TControl(Components[I]).Enabled:=not Value;
  for I:=0 to High(FDesigns) do begin FAdopt[I].Enabled:=not Value and (FCandidateIndex=I);FCancel[I].Enabled:=(FCandidateIndex=I) or (Value and (FRequest.Index=I));end;
end;
procedure TRhythmDesignFrame.Generate(Sender:TObject);
var Index,Previous:Integer;Reference:string;Bitmap:TBitmap;
begin
  if FBusy then Exit;Index:=TControl(Sender).Tag;Previous:=FCandidateIndex;FCandidateIndex:=-1;if Previous>=0 then Refresh(Previous);
  try
    FRequest:=NewDesignRequest(Index,FDesigns[Index]);FActiveId:=FRequest.Id;
    Reference:=TPath.Combine(FRequest.Directory,'reference.png');
    if FDesigns[Index].Path<>'' then TFile.Copy(ResolveDesignImage(FDesigns[Index]),Reference,False)
    else begin Bitmap:=InitialBitmap(Index,FRenderer);try WriteDesignPNG(Bitmap,Reference);finally Bitmap.Free;end;end;
    FWorker:=TRhythmCodexJob.CreateImage(FRequest.Prompt,[Reference],FRequest.Directory);
    SetBusy(True);FStatus[Index].Caption:='専用Codexへ画像を依頼しています...';FWorker.BeginRun;
  except on E:Exception do begin FreeAndNil(FWorker);SetBusy(False);FStatus[Index].Caption:=E.Message;end;end;
end;
procedure TRhythmDesignFrame.Cancel(Sender:TObject);
var Index:Integer;
begin
  Index:=TControl(Sender).Tag;FActiveId:='';
  if FWorker<>nil then begin FWorker.Cancel;FStatus[Index].Caption:='AI作成を中止しています...';FCancel[Index].Enabled:=False;end
  else begin FCandidateIndex:=-1;Refresh(Index);end;
end;
procedure TRhythmDesignFrame.Adopt(Sender:TObject);
var Index:Integer;
begin
  Index:=TControl(Sender).Tag;if FBusy or (FCandidateIndex<>Index) then Exit;
  if not DesignRequestCurrent(FRequest,FActiveId,FDesigns[Index]) then begin FCandidateIndex:=-1;Refresh(Index);FStatus[Index].Caption:='素材または希望が変更されたため古い候補を破棄しました。';Exit;end;
  try
    if not ApplyDesignCandidate(FDesigns,FRequest,FActiveId,FCandidate) then raise Exception.Create('この候補は現在の素材設定に適用できません。');
    FCandidateIndex:=-1;FActiveId:='';Refresh(Index);Changed;
  except on E:Exception do FStatus[Index].Caption:=E.Message;end;
end;
procedure TRhythmDesignFrame.Tick(Sender:TObject);
var Index:Integer;ErrorText,Stage:string;
begin
  if FWorker=nil then Exit;Index:=FRequest.Index;
  if not FWorker.Finished then begin Stage:=FWorker.Stage;if FActiveId='' then Stage:='AI作成を中止しています...';if FStatus[Index].Caption<>Stage then FStatus[Index].Caption:=Stage;Exit;end;
  FWorker.WaitFor;
  try
    ErrorText:=FWorker.ErrorText;
    if not DesignRequestCurrent(FRequest,FActiveId,FDesigns[Index]) then ErrorText:='中止または設定変更により、受信結果は採用していません。'
    else if FWorker.Success then try FCandidate:=ImportDesignImage(FWorker.ImagePath,Index);FCandidateIndex:=Index;
      except on E:Exception do ErrorText:=E.Message;end
    else if ErrorText='' then ErrorText:='画像生成が完了しませんでした。';
  finally FreeAndNil(FWorker);SetBusy(False);end;
  Refresh(Index);if ErrorText<>'' then FStatus[Index].Caption:=ErrorText;
end;
end.
