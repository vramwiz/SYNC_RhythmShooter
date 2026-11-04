program CheckboxThemeSmoke;
{$APPTYPE CONSOLE}
// 本番と同じ描画関数・CN_DRAWITEMをメモリへ描き、テーマに依存しない文字色とToggleを検証する。
uses Winapi.Windows,Winapi.Messages,System.SysUtils,System.Classes,System.Math,System.IOUtils,
  Vcl.Graphics,Vcl.StdCtrls,Vcl.Controls,Vcl.Imaging.pngimage,RhythmControls;
type
  TCheckAccess=class(TRhythmCheckBox)
    procedure BuildParams(out Params:TCreateParams);
  end;
  TEvents=class
    Count:Integer;
    procedure Changed(Sender:TObject);
  end;
const PPIs:array[0..3] of Integer=(96,120,144,192);
  Captions:array[0..2] of string=('背面：イコライザー','中層：ムービー','前面：リズムゲーム');
var Image:TBitmap;PNG:TPngImage;Check:TCheckAccess;Events:TEvents;Params:TCreateParams;
  Item:TDrawItemStruct;Folder:string;D,E,S,F,C,X,Y,Left,Count,Checks,Frames:Integer;
  Expected,Color:TColor;Backgrounds:array[0..2] of TColor;MinContrast:Double;
procedure Need(OK:Boolean;const Message:string);
begin if not OK then raise Exception.Create(Message);Inc(Checks);end;
procedure TCheckAccess.BuildParams(out Params:TCreateParams);
begin CreateParams(Params);end;
procedure TEvents.Changed(Sender:TObject);
begin Inc(Count);end;
function Luminance(Color:TColor):Double;
  function Linear(V:Integer):Double;
  begin Result:=V/255;if Result<=0.04045 then Result:=Result/12.92 else Result:=Power((Result+0.055)/1.055,2.4);end;
var RGB:Cardinal;
begin RGB:=ColorToRGB(Color);Result:=0.2126*Linear(GetRValue(RGB))+0.7152*Linear(GetGValue(RGB))+0.0722*Linear(GetBValue(RGB));end;
function Contrast(A,B:TColor):Double;
begin Result:=(Max(Luminance(A),Luminance(B))+0.05)/(Min(Luminance(A),Luminance(B))+0.05);end;
begin Image:=nil;PNG:=nil;Check:=nil;Events:=nil;Checks:=0;Frames:=0;MinContrast:=100;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.Canvas.Font.Name:='Segoe UI';
    Backgrounds[0]:=RhythmSurface;Backgrounds[1]:=RhythmBackground;Backgrounds[2]:=RhythmInput;
    for E:=0 to 1 do begin if E=1 then Expected:=RhythmText else Expected:=RhythmMuted;
      for C:=0 to 2 do begin MinContrast:=Min(MinContrast,Contrast(Expected,Backgrounds[C]));Need(Contrast(Expected,Backgrounds[C])>=4.5,'Caption contrast below 4.5:1');end;
    end;
    for D:=0 to High(PPIs) do for E:=0 to 1 do for S:=0 to 2 do for F:=0 to 1 do for C:=0 to High(Captions) do begin
      Image.SetSize(MulDiv(250,PPIs[D],96),MulDiv(32,PPIs[D],96));Image.Canvas.Font.Height:=-MulDiv(13,PPIs[D],96);
      DrawRhythmCheckBox(Image.Canvas,Rect(0,0,Image.Width,Image.Height),Captions[C],Image.Canvas.Font,
        TCheckBoxState(S),E=1,F=1,False,PPIs[D],RhythmSurface);
      if E=1 then Expected:=RhythmText else Expected:=RhythmMuted;
      Need(ColorToRGB(Image.Canvas.Font.Color)=ColorToRGB(Expected),'Wrong caption color');
      Left:=MulDiv(25,PPIs[D],96);Count:=0;
      for Y:=0 to Image.Height-1 do for X:=Left to Image.Width-1 do begin Color:=ColorToRGB(Image.Canvas.Pixels[X,Y]);if Color=ColorToRGB(Expected) then Inc(Count);end;
      Need(Count>=8,'Caption missing from actual pixels');
      if (D in [0,3]) and (S=1) and (F=0) then begin PNG:=TPngImage.Create;
        try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Format('ppi%d-enabled%d-caption%d.png',[PPIs[D],E,C])));finally FreeAndNil(PNG);end;Inc(Frames);
      end;
    end;
    Check:=TCheckAccess.Create(nil);Events:=TEvents.Create;Check.Caption:=Captions[0];Check.OnClick:=Events.Changed;
    Check.BuildParams(Params);Need((Params.Style and $000F)=BS_OWNERDRAW,'Native theme still owns drawing');
    Check.Perform(CN_COMMAND,WPARAM(BN_CLICKED shl 16),0);Need(Check.Checked and (Events.Count=1),'First native click must toggle once');
    Check.Perform(CN_COMMAND,WPARAM(BN_CLICKED shl 16),0);Need(not Check.Checked and (Events.Count=2),'Second native click must toggle once');
    Check.AllowGrayed:=True;Check.Perform(CN_COMMAND,WPARAM(BN_CLICKED shl 16),0);Need(Check.State=cbGrayed,'Mixed state lifecycle');
    Check.Perform(CN_COMMAND,WPARAM(BN_CLICKED shl 16),0);Need(Check.Checked,'Mixed state to checked');
    Image.SetSize(250,32);Check.Font.Name:='Segoe UI';Check.Font.Height:=-13;
    FillChar(Item,SizeOf(Item),0);Item.hDC:=Image.Canvas.Handle;Item.rcItem:=Rect(0,0,250,32);Item.itemState:=ODS_FOCUS;
    Check.Perform(CN_DRAWITEM,0,LPARAM(@Item));Need(not Check.HandleAllocated,'Headless test created a window');
    Need(Events.Count=4,'Painting triggered click event');
    Need(ColorToRGB(Image.Canvas.Pixels[249,0])=ColorToRGB(RhythmSurface),'Native draw handler did not paint');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"checks":%d,"renderCases":144,"frames":%d,"minContrast":%.4f,"windowCreated":false,"nativeToggle":true}',[Checks,Frames,MinContrast]),TEncoding.UTF8);
    WriteLn('Checkbox theme PASS checks=',Checks,' cases=144 frames=',Frames,' minContrast=',MinContrast:0:4,' no windows');
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  Events.Free;Check.Free;PNG.Free;Image.Free;
end.
