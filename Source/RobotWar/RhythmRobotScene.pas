unit RhythmRobotScene;
// 保存済みロボット譜面の所有窓口。音声は借用し、描画中の解析・計画生成を行わない。
interface

uses RhythmAnimation, RhythmAudio, RhythmPlanRef, RhythmRobotPlan, RhythmRenderSurface, RhythmEqualizer;

type
  TRobotAnimation = class(TAnimationScene)
  private
    FPlan: TRobotPlan;
    FReference: TRhythmPlanRef;
    FAttempt, FError: string;
  public
    Audio: TRhythmAudio;
    destructor Destroy; override;
    procedure SetReference(const Reference: TRhythmPlanRef);
    procedure Prepare(const Frame: TAnimationFrame); override;
    procedure Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame); override;
    function Notice: string; override;
    function GoalTime: Double; override;
    function Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
  end;

implementation

uses System.SysUtils, System.Math, RhythmRobotCodec, RhythmRobotArt;

destructor TRobotAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TRobotAnimation.SetReference(const Reference: TRhythmPlanRef);
begin
  FReference := Reference;
end;

procedure TRobotAnimation.Prepare(const Frame: TAnimationFrame);
var Key: string;
begin
  Key := FReference.Key + '|' + FReference.Digest + '|' + IntToStr(Frame.Direction);
  if Audio <> nil then Key := Key + '|' + Audio.Key else Key := Key + '|none';
  if Key = FAttempt then Exit;
  FAttempt := Key;
  FreeAndNil(FPlan);
  FError := '';
  if Audio = nil then Exit;
  try
    FPlan := LoadRobotPlan(FReference, Audio, Frame.Direction);
  except
    on E: Exception do FError := E.Message;
  end;
end;

procedure TRobotAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
begin
  if FPlan <> nil then DrawRobotWar(Surface, FPlan, Frame);
end;

function TRobotAnimation.Notice: string;
begin
  Result := FError;
end;

function TRobotAnimation.GoalTime: Double;
begin
  Result := 0;
end;

function TRobotAnimation.Activity(Time: Double; out Value: TEqualizerActivity): Boolean;
var I, J: Integer; Stage: TRobotStage; Age: Double;
  procedure Pulse(CueTime, Power: Double);
  begin
    Age := Time - CueTime;
    if (Age < 0) or (Age > 0.65) then Exit;
    Value.Valid := True;
    Value.Pulse := Max(Value.Pulse, Exp(-Age * 10) * Power);
    Value.Energy := Max(Value.Energy, Exp(-Age * 5) * Power);
  end;
begin
  Result := True;
  Value := Default(TEqualizerActivity);
  if FPlan = nil then Exit;
  I := FPlan.CueAt(Time);
  if I >= 0 then
  begin
    Value.Hit := I;
    Pulse(FPlan.Cues[I].Time, FPlan.Cues[I].Power);
  end;
  Stage := FPlan.Stages[FPlan.StageAt(Time)];
  if Stage.Kind in [rkTransform, rkCombine] then
    for J := 0 to High(Stage.Locks) do
      if Stage.Synced[J] then Pulse(Stage.Locks[J], 0.8);
end;

end.
