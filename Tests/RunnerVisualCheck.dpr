program RunnerVisualCheck;
// Isolated native viewer. No playback, project files, user settings or deployment.
uses RhythmRunnerPixels, Winapi.Windows,System.SysUtils,System.Math,System.Classes,Vcl.Forms,Vcl.Controls,Vcl.ExtCtrls,
  Vcl.StdCtrls,Vcl.ComCtrls,Vcl.Graphics,RhythmAudio,RhythmRunnerAction,
  RhythmRenderSurface,RhythmImageBank;
type TReview=class(TForm)
  private
    FPlan:TRunnerActionPlan;FSurface:TAnimationRenderSurface;FImage:TBitmap;
    FTimer:TTimer;FSeek:TTrackBar;FClock:TLabel;FPlay:TButton;FTime:Double;
    procedure PaintScene(Sender:TObject);
    procedure Tick(Sender:TObject);
    procedure Seek(Sender:TObject);
    procedure Choose(Sender:TObject);
    procedure Play(Sender:TObject);
  public
    constructor Create(Owner:TComponent);override;
    destructor Destroy;override;
  end;
constructor TReview.Create(Owner:TComponent);
var Audio:TRhythmAudio;I,N:Integer;T,Gap:Double;Panel:TPanel;Button:TButton;
begin
  inherited CreateNew(Owner);Caption:='Runner ABC visual check';Width:=1120;Height:=760;Position:=poScreenCenter;DoubleBuffered:=True;
  Audio:=TRhythmAudio.Create;
  try Audio.Duration:=96;Audio.Sensitivity:=50;SetLength(Audio.Envelope,9600);for I:=0 to 9599 do Audio.Envelope[I]:=0.5;
    SetLength(Audio.Hits,1000);T:=0.18;N:=0;while T<95.8 do begin Audio.Hits[N].Time:=T;Audio.Hits[N].Strength:=0.3+0.14*(N mod 6);Inc(N);Gap:=0.7;if (Trunc(T/12) mod 2)=1 then Gap:=0.2;T:=T+Gap;end;SetLength(Audio.Hits,N);Audio.UpdateSoundBounds;Audio.SetBossFrequency(100);FPlan:=TRunnerActionPlan.Build(Audio,nil);
  finally Audio.Free;end;
  FSurface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create([],0));FImage:=TBitmap.Create;FImage.PixelFormat:=pf32bit;
  Panel:=TPanel.Create(Self);Panel.Parent:=Self;Panel.Align:=alTop;Panel.Height:=44;Panel.Caption:='';
  for I:=0 to 2 do begin Button:=TButton.Create(Self);Button.Parent:=Panel;Button.SetBounds(8+I*104,8,96,28);Button.Caption:=Char(Ord('A')+I);Button.Tag:=I;Button.OnClick:=Choose;end;
  FPlay:=TButton.Create(Self);FPlay.Parent:=Panel;FPlay.SetBounds(328,8,96,28);FPlay.Caption:='Play';FPlay.OnClick:=Play;
  FClock:=TLabel.Create(Self);FClock.Parent:=Panel;FClock.SetBounds(440,12,550,24);FClock.Caption:='Synthetic source accents / visual check / no audio';
  FSeek:=TTrackBar.Create(Self);FSeek.Parent:=Self;FSeek.Align:=alBottom;FSeek.Height:=42;FSeek.Max:=9760;FSeek.OnChange:=Seek;
  FTimer:=TTimer.Create(Self);FTimer.Enabled:=False;FTimer.Interval:=50;FTimer.OnTimer:=Tick;OnPaint:=PaintScene;
  FTime:=3;FSeek.Position:=300;
end;
destructor TReview.Destroy;
begin FTimer.Enabled:=False;FImage.Free;FSurface.Free;FPlan.Free;inherited;end;
procedure TReview.PaintScene(Sender:TObject);
begin FImage.SetSize(ClientWidth,Max(1,ClientHeight-86));FSurface.BeginFrame(FImage);RenderRunnerPixels(FPlan,FSurface,FTime,FImage.Width,FImage.Height);FSurface.EndFrame;Canvas.Draw(0,44,FImage);end;
procedure TReview.Seek(Sender:TObject);
begin FTime:=FSeek.Position/100;FClock.Caption:=Format('%.2f s / synthetic source accents / no audio',[FTime]);Invalidate;end;
procedure TReview.Tick(Sender:TObject);
begin FSeek.Position:=(FSeek.Position+5) mod FSeek.Max;end;
procedure TReview.Play(Sender:TObject);
begin FTimer.Enabled:=not FTimer.Enabled;if FTimer.Enabled then FPlay.Caption:='Pause' else FPlay.Caption:='Play';end;
procedure TReview.Choose(Sender:TObject);
var S:TRunSection;H:TRunHit;
begin FTimer.Enabled:=False;FPlay.Caption:='Play';for S in FPlan.Sections do if Ord(S.Mode)=TButton(Sender).Tag then begin FTime:=S.Start+0.5;
    if S.Mode=rmJump then begin if Length(FPlan.Jumps)>0 then FTime:=FPlan.Jumps[0].Time-0.20;end
    else for H in FPlan.Hits do if (H.Section=FPlan.SectionAt(S.Start)) and (H.Kind in [rhSword,rhBossCut]) then begin FTime:=H.Time;Break;end;
    FSeek.Position:=Round(FTime*100);Break;end;Invalidate;
end;
var Review:TReview;
begin Application.Initialize;Application.MainFormOnTaskbar:=True;Application.CreateForm(TReview,Review);Application.Run;end.
