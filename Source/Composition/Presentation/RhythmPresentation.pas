unit RhythmPresentation;
// スタイルの上へ共通表示を合成する所有ラッパー。計画・カメラ・各スタイル本体を変更しない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmEqualizer,RhythmStyleOps;
type
  TRhythmPresentationScene=class(TAnimationScene)
  private
    FInner:TAnimationScene;FActivity:TStyleActivity;
  public
    Audio:TRhythmAudio;IncludeEqualizer:Boolean;
    function Activity(Time:Double):TEqualizerActivity;
    // Innerを所有する。Audioは借用し、共通Rendererと同じ寿命でのみ参照する。
    constructor Create(Inner:TAnimationScene;ActivityFunction:TStyleActivity=nil);
    destructor Destroy;override;
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
  end;
implementation
uses RhythmFireworksScene;
constructor TRhythmPresentationScene.Create(Inner:TAnimationScene;ActivityFunction:TStyleActivity);
begin inherited Create;FInner:=Inner;FActivity:=ActivityFunction;end;
destructor TRhythmPresentationScene.Destroy;
begin FInner.Free;inherited;end;
procedure TRhythmPresentationScene.Prepare(const Frame:TAnimationFrame);
begin FInner.Prepare(Frame);end;
function TRhythmPresentationScene.Activity(Time:Double):TEqualizerActivity;
begin Result:=Default(TEqualizerActivity);
  if Audio=nil then Exit;
  if Assigned(FActivity) then begin if not FActivity(FInner,Time,Result) then Result:=EqualizerActivity(Audio,Time);end
  else Result:=EqualizerActivity(Audio,Time);
end;
procedure TRhythmPresentationScene.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Goal:Double;
begin
  if IncludeEqualizer then DrawEqualizer(Surface,Frame.Width,Frame.Height,Activity(Frame.Time),True);
  FInner.Draw(Surface,Frame);
  if (Audio=nil) or Frame.BackgroundOnly or (FInner.Notice<>'') then Exit;
  Goal:=FInner.GoalTime;
  if Goal<0 then Goal:=Audio.SoundEnd;
  if Goal>0 then DrawGoalFireworks(Surface,Frame.Width,Frame.Height,Frame.Time-Goal);
end;
function TRhythmPresentationScene.Notice:string;
begin Result:=FInner.Notice;end;
end.
