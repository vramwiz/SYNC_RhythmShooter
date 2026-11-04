unit RhythmGameScene;
// 宇宙v2描画と保存済みv1描画を切り替える薄い窓口。他スタイルは変更しない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmOrbitScene,RhythmGameLegacyScene,RhythmEqualizer;
type
  TGameAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio;FTransparentBackground:Boolean;
    FRef:TRhythmPlanRef;
    FOrbit:TOrbitAnimation;
    FLegacy:TLegacyGameAnimation;
  public
    constructor Create;
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    function TryActivity(Time:Double;out Activity:TEqualizerActivity):Boolean;
    property TransparentBackground:Boolean read FTransparentBackground write FTransparentBackground;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;
implementation
constructor TGameAnimation.Create;
begin inherited;FOrbit:=TOrbitAnimation.Create;FLegacy:=TLegacyGameAnimation.Create;end;
destructor TGameAnimation.Destroy;
begin FOrbit.Free;FLegacy.Free;inherited;end;
procedure TGameAnimation.SetReference(const Ref:TRhythmPlanRef);
begin FRef:=Ref;FOrbit.SetReference(Ref);FLegacy.SetReference(Ref);end;
procedure TGameAnimation.Prepare(const Frame:TAnimationFrame);
begin if FRef.Version=1 then begin FLegacy.Audio:=FAudio;FLegacy.Prepare(Frame);end
  else begin FOrbit.Audio:=FAudio;FOrbit.Prepare(Frame);end;
end;
procedure TGameAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
begin if FRef.Version=1 then begin FLegacy.TransparentBackground:=TransparentBackground;FLegacy.Draw(Surface,Frame);end else begin FOrbit.TransparentBackground:=TransparentBackground;FOrbit.Draw(Surface,Frame);end;end;
function TGameAnimation.TryActivity(Time:Double;out Activity:TEqualizerActivity):Boolean;
begin Result:=False;Activity:=Default(TEqualizerActivity);if FRef.Version<>1 then Result:=FOrbit.TryActivity(Time,Activity);end;
function TGameAnimation.Notice:string;
begin if FRef.Version=1 then Result:=FLegacy.Notice else Result:=FOrbit.Notice;end;
end.
