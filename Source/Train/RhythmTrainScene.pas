unit RhythmTrainScene;
// 平坦な線路、屋根上の人物、編成の接触を同じ座標で描く。外部画像を使わない試作。
interface

uses
  RhythmAnimation, RhythmRenderSurface, RhythmAudio, RhythmPlanRef, RhythmTrainPlan;

type
  TTrainAnimation = class(TAnimationScene)
  private
    FAudio: TRhythmAudio;
    FRef: TRhythmPlanRef;
    FPlan: TTrainPlan;
    FAttempt, FError: string;
  public
    destructor Destroy; override;
    procedure SetReference(const Ref: TRhythmPlanRef);
    procedure Prepare(const Frame: TAnimationFrame); override;
    procedure Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame); override;
    function Notice: string; override;
    property Audio: TRhythmAudio read FAudio write FAudio;
  end;

implementation

uses
  System.SysUtils, System.Math, System.Types, Winapi.Windows, Vcl.Graphics;

const
  RailY = 3.68;
  Ink = $30241C;
  HeroColor = $50CEF9;
  EnemyColor = $6377E7;
  BossColor = $BC7ECD;
  MainColor = $A76A38;
  NextColor = $767A2C;

function MixColor(A,B: TColor; U: Double): TColor;
begin
  Result := RGB(Round(GetRValue(A)+(GetRValue(B)-GetRValue(A))*U),
    Round(GetGValue(A)+(GetGValue(B)-GetGValue(A))*U),
    Round(GetBValue(A)+(GetBValue(B)-GetBValue(A))*U));
end;

destructor TTrainAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TTrainAnimation.SetReference(const Ref: TRhythmPlanRef);
begin
  FRef := Ref;
end;

function TTrainAnimation.Notice: string;
begin
  Result := FError;
end;

procedure TTrainAnimation.Prepare(const Frame: TAnimationFrame);
var
  Key: string;
begin
  Key := FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key := Key+'|'+FAudio.Key+'|'+IntToStr(FAudio.Sensitivity)
  else Key := Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt := Key;
  FreeAndNil(FPlan);
  FError := '';
  if FAudio=nil then Exit;
  try
    FPlan := TTrainPlan.Load(FRef,FAudio,Frame.Direction);
  except
    on E: Exception do FError := E.Message;
  end;
end;

procedure TTrainAnimation.Draw(Surface: TAnimationRenderSurface; const Frame: TAnimationFrame);
var
  T, Travel, CenterX, CenterY, ViewWidth, Scale, X, Y, StationX,
    RearOffset, RightRear, RightOffset, CrashX, CrashWidth, CrashBlend,
    Shake, Age, BossX, BossY, BossRoll, U: Double;
  I, J, FirstCar, LastCar: Integer;
  C, Board, LeftImpact, RightImpact, Couple, LastCue, BossFirst, BossFinal: TTrainCue;
  P, N, Ahead: TTrainPose;
  FarEdge, NearEdge: Double;
  Color: TColor;

  function Screen(AX,AY: Double): TPointF;
  begin
    Result := PointF(Frame.Width*0.5+(AX-CenterX)*Scale,
      Frame.Height*0.5+(AY-CenterY+Shake)*Scale);
  end;

  procedure Box(X1,Y1,X2,Y2: Double; Tint: TColor);
  var A,B: TPointF;
  begin
    A := Screen(X1,Y1);
    B := Screen(X2,Y2);
    Surface.FillRect(A.X,A.Y,B.X,B.Y,Tint);
  end;

  procedure Line(X1,Y1,X2,Y2,Stroke: Double; Tint: TColor);
  var A,B: TPointF;
  begin
    A := Screen(X1,Y1);
    B := Screen(X2,Y2);
    Surface.Line(A.X,A.Y,B.X,B.Y,Tint,Max(1.0,Stroke*Scale));
  end;

  procedure Circle(X,Y,R: Double; Tint: TColor);
  var A: TPointF;
  begin
    A := Screen(X,Y);
    Surface.Circle(A.X,A.Y,Max(0.7,R*Scale),Tint,True);
  end;

  procedure Quad(X1,Y1,X2,Y2,X3,Y3,X4,Y4: Double; Tint: TColor);
  begin
    Surface.FillQuad(Screen(X1,Y1),Screen(X2,Y2),Screen(X3,Y3),Screen(X4,Y4),Tint);
  end;

  procedure Wheel(WX: Double);
  var
    A: Double;
  begin
    A := Travel/0.40;
    Circle(WX,RailY-0.39,0.41,Ink);
    Circle(WX,RailY-0.39,0.25,RGB(112,139,151));
    Line(WX-0.22*Cos(A),RailY-0.39-0.22*Sin(A),
      WX+0.22*Cos(A),RailY-0.39+0.22*Sin(A),0.067,Ink);
  end;

  procedure Car(CarX,Roof: Double; Tint: TColor; Cab, Bent: Boolean);
  var
    K: Integer;
    WindowX, RightX: Double;
    WindowColor: TColor;
  begin
    RightX := CarX+TrainCarWidth;
    if (RightX+0.3<FarEdge) or (CarX-0.3>NearEdge) then Exit;
    // 車体前後の連結器は接触時刻に同じ世界座標へ届く。
    Box(CarX-0.5*TrainGap,RailY-0.71,CarX+0.15,RailY-0.57,Ink);
    Box(RightX-0.15,RailY-0.71,RightX+0.5*TrainGap,RailY-0.57,Ink);
    Wheel(CarX+1.16);
    Wheel(CarX+2.03);
    Wheel(RightX-2.03);
    Wheel(RightX-1.16);
    Quad(CarX,Roof,RightX-0.18,Roof,RightX,RailY-0.52,CarX,RailY-0.52,Tint);
    Box(CarX,Roof-0.045,RightX,Roof+0.12,MixColor(Tint,clWhite,0.46));
    for K := 0 to 7 do begin
      WindowX := CarX+0.57+1.44*K;
      Box(WindowX,Roof+0.008,WindowX+0.055,Roof+0.118,MixColor(Tint,Ink,0.15));
    end;
    Box(CarX+0.14,RailY-0.79,RightX-0.12,RailY-0.67,MixColor(Tint,clWhite,0.35));
    WindowColor := RGB(36,55,77);
    if Cab then WindowColor := RGB(99,165,186);
    for K := 0 to 5 do begin
      WindowX := CarX+0.68+1.83*K;
      Box(WindowX,Roof+0.64,WindowX+1.38,Roof+1.48,WindowColor);
      Box(WindowX+0.10,Roof+0.69,WindowX+1.27,Roof+0.78,MixColor(WindowColor,clWhite,0.29));
    end;
    Box(CarX+0.08,Roof+1.86,RightX-0.08,Roof+2.00,RGB(220,232,214));
    if Cab then Box(RightX-0.47,Roof+1.67,RightX-0.09,Roof+1.92,RGB(255,244,179));
    if Bent then begin
      Line(CarX+0.12,Roof+0.14,CarX+0.44,Roof+0.45,0.06,Ink);
      Line(CarX+0.44,Roof+0.45,CarX+0.63,Roof+0.37,0.06,Ink);
    end;
  end;

  procedure Platform(StartX,Width,Top: Double; Canopy: Boolean);
  begin
    if (StartX+Width<FarEdge) or (StartX>NearEdge) then Exit;
    Box(StartX,Top,StartX+Width,RailY+0.36,RGB(95,113,128));
    Box(StartX,Top,StartX+Width,Top+0.075,RGB(231,206,129));
    if Canopy then begin
      Box(StartX+2.0,-1.11,StartX+Width-1.3,-0.91,RGB(51,78,99));
      Box(StartX+2.8,-0.91,StartX+2.91,Top,RGB(61,87,104));
      Box(StartX+9.0,-0.91,StartX+9.11,Top,RGB(61,87,104));
      Box(StartX+4.0,-0.92,StartX+6.75,-0.49,RGB(73,127,144));
      Box(StartX+4.18,-0.78,StartX+6.57,-0.66,RGB(206,230,225));
    end;
  end;

  procedure DrawTrack;
  var
    Left, Right, Tie: Double;
    K: Integer;
  begin
    // ホームの前を通る線路。両端を画面外に取り、枕木まで同じ座標で流す。
    Left := FarEdge-1.8;
    Right := NearEdge+1.8;
    Box(Left,RailY-0.025,Right,RailY+0.51,RGB(153,149,130));
    for K := Floor((Left+Travel)/0.89) to Ceil((Right+Travel)/0.89) do begin
      Tie := K*0.89-Travel;
      Quad(Tie,RailY+0.02,Tie+0.33,RailY+0.02,Tie+0.45,RailY+0.48,
        Tie-0.08,RailY+0.48,RGB(92,77,61));
    end;
    Box(Left,RailY-0.022,Right,RailY+0.052,RGB(71,79,82));
    Box(Left,RailY-0.024,Right,RailY+0.004,RGB(237,245,247));
    Box(Left,RailY+0.244,Right,RailY+0.334,RGB(61,66,69));
    Box(Left,RailY+0.24,Right,RailY+0.27,RGB(227,239,239));
  end;

  procedure RoofEquipment(const Move: TTrainCue);
  var Block: TTrainObstacle; Offset,Roof,Top,Mid: Double; K,CarIndex: Integer;
  begin
    if not TrainObstacle(Move,Block) then Exit;
    CarIndex := Floor(Move.FromX/TrainPitch);
    Offset := 0;
    if CarIndex<FPlan.InitialCars-1 then Offset := RearOffset
    else if CarIndex>=FPlan.InitialCars then begin
      if T<FPlan.Cue[FPlan.ImpactIndex-1].Finish then Exit;
      Offset := RightOffset;
    end;
    Block.Left := Block.Left+Offset;
    Block.Right := Block.Right+Offset;
    if (Block.Right<FarEdge) or (Block.Left>NearEdge) then Exit;
    Roof := FPlan.RoofY(Move.FromX);
    Top := Roof-Block.Height;
    Mid := (Block.Left+Block.Right)*0.5;
    Box(Block.Left,Top,Block.Right,Roof,RGB(60,68,76));
    Box(Block.Left-0.06,Top-0.01,Block.Right+0.06,Top+0.13,RGB(255,185,64));
    case Block.Variant of
      0: for K := 1 to 3 do
           Box(Block.Left+0.12,Top+0.14+K*0.15,Block.Right-0.12,Top+0.21+K*0.15,RGB(174,195,202));
      1: begin
           Box(Block.Left+0.12,Top+0.24,Block.Right-0.12,Roof-0.12,RGB(128,151,162));
           Line(Block.Left+0.19,Roof-0.18,Block.Right-0.19,Top+0.28,0.07,RGB(250,207,108));
         end;
      2: begin
           Circle(Mid-0.20,Top+0.50,0.16,RGB(195,219,221));
           Circle(Mid+0.20,Top+0.50,0.16,RGB(195,219,221));
         end;
    end;
  end;

  procedure Figure(const Pose: TTrainPose; Tint: TColor; Size: Double; Facing: Integer;
    Roll: Double=0; Armored: Boolean=False);
  var
    HipX,HipY,ShoulderX,ShoulderY,HeadX,HeadY,Stride,Lift,Lean,ArmReach,AngleS,AngleC: Double;
    Foot, RearFoot, FrontFoot: TPointF;

    function Rotate(LX,LY: Double): TPointF;
    var OffsetY: Double;
    begin
      OffsetY := LY+0.57;
      Result := PointF(Pose.X+Size*(LX*AngleC-OffsetY*AngleS),
        Pose.Y+Size*(-0.57+LX*AngleS+OffsetY*AngleC));
    end;

    procedure Bone(X1,Y1,X2,Y2,Stroke: Double; BoneColor: TColor);
    var A,B: TPointF;
    begin
      A := Rotate(X1,Y1);
      B := Rotate(X2,Y2);
      Line(A.X,A.Y,B.X,B.Y,Stroke*Size,BoneColor);
    end;

    procedure Joint(X1,Y1,TX,TY,L1,L2,Bend,Stroke: Double; BoneColor: TColor);
    var DX,DY,LengthTo,Along,Side,JX,JY: Double;
    begin
      DX := TX-X1;
      DY := TY-Y1;
      LengthTo := Max(0.001,Hypot(DX,DY));
      DX := DX/LengthTo;
      DY := DY/LengthTo;
      LengthTo := EnsureRange(LengthTo,Abs(L1-L2)+0.001,L1+L2-0.001);
      Along := (Sqr(L1)-Sqr(L2)+Sqr(LengthTo))/(2*LengthTo);
      Side := Bend*Sqrt(Max(0.0,Sqr(L1)-Sqr(Along)));
      JX := X1+DX*Along-DY*Side;
      JY := Y1+DY*Along+DX*Side;
      Bone(X1,Y1,JX,JY,Stroke,BoneColor);
      Bone(JX,JY,X1+DX*LengthTo,Y1+DY*LengthTo,Stroke*0.84,BoneColor);
    end;

    function FootAt(Shift, DefaultX: Double): TPointF;
    var Phase, Advance, LX, LY: Double;
    begin
      Phase := Facing*Pose.X/(1.05*Size)+Shift;
      Phase := Phase-Floor(Phase);
      LY := 0;
      if Phase<0.58 then LX := 0.305-Phase*1.05
      else begin
        Advance := (Phase-0.58)/0.42;
        LX := -0.304+0.609*TrainEase(Advance);
        LY := -0.25*Sin(Pi*Advance);
      end;
      Result := PointF(DefaultX*(1-Pose.Run)+Facing*LX*Pose.Run,LY*Pose.Run);
    end;

  begin
    AngleS := Sin(Roll);
    AngleC := Cos(Roll);
    Stride := Pose.Run*Sin(Facing*Pose.X*6.0);
    RearFoot := FootAt(0,-0.13);
    FrontFoot := FootAt(0.5,0.14);
    Lean := Facing*(Pose.Run*0.25+Pose.Reach*0.15);
    HipX := -0.05*Facing;
    HipY := -0.54+0.23*Pose.Crouch;
    ShoulderX := HipX+Lean;
    ShoulderY := HipY-0.35+0.14*Pose.Crouch;
    HeadX := ShoulderX+0.04*Facing;
    HeadY := ShoulderY-0.21;
    Lift := 0;
    if Pose.Airborne then begin
      Stride := 0.75;
      Lift := 0.16;
      RearFoot := PointF(-0.41,-0.09);
      FrontFoot := PointF(0.41,-0.16);
    end;
    Joint(HipX,HipY,RearFoot.X,RearFoot.Y-Lift,0.30,0.30,Facing,0.122,Ink);
    Joint(HipX,HipY,FrontFoot.X+0.42*Pose.Kick,
      FrontFoot.Y-Lift-0.49*Pose.Kick,0.30,0.30,Facing,0.122,Ink);
    Joint(ShoulderX,ShoulderY,-Facing*(0.23+0.25*Stride),HipY+0.07,0.27,0.29,-Facing,0.11,Ink);
    Bone(HipX,HipY,ShoulderX,ShoulderY,0.36,Ink);
    Bone(HipX,HipY,ShoulderX,ShoulderY,0.27,Tint);
    if Armored then Bone(ShoulderX-0.18,ShoulderY-0.04,ShoulderX+0.18,ShoulderY-0.04,0.16,Ink);
    Foot := Rotate(HeadX,HeadY);
    Circle(Foot.X,Foot.Y,0.219*Size,Ink);
    Circle(Foot.X,Foot.Y-0.019*Size,0.169*Size,Tint);
    Bone(HeadX+Facing*0.04,HeadY-0.036,HeadX+Facing*0.14,HeadY-0.036,0.055,Ink);
    ArmReach := 0.23+0.38*Pose.Reach*(1-Pose.Kick);
    Joint(ShoulderX,ShoulderY,ShoulderX+Facing*ArmReach,ShoulderY+0.22*(1-Pose.Reach),
      0.29,0.33,Facing,0.106,Tint);
  end;

  procedure Burst(BX,BY,Elapsed,Size: Double; Tint: TColor);
  var
    K: Integer;
    A,R: Double;
  begin
    if (Elapsed<0) or (Elapsed>0.26) then Exit;
    for K := 0 to 7 do begin
      A := K*Pi/4+0.18;
      R := (0.43+Elapsed*4.8)*Size;
      Line(BX+Cos(A)*R*0.4,BY+Sin(A)*R*0.4,
        BX+Cos(A)*R,BY+Sin(A)*R,(0.067-Elapsed*0.18)*Size,Tint);
    end;
    Circle(BX,BY,0.25*Size*Max(0.0,1-Elapsed/0.145),clWhite);
  end;

  procedure Bolt(StartX, EndX, BY, Progress: Double; Tint: TColor);
  var Head, Tail: Double;
  begin
    if (Progress<0) or (Progress>1) then Exit;
    Head := StartX+(EndX-StartX)*Progress;
    Tail := Head-Sign(EndX-StartX)*0.29;
    Line(Tail,BY,Head,BY,0.105,Tint);
    Circle(Head,BY,0.084,clWhite);
  end;

  procedure Sweep(const Move: TTrainCue; TargetX, BaseY: Double; LowSweep: Boolean);
  var AtTime, Height, Dur: Double;
  begin
    if (T<Move.Start) or (T>=Move.Time) then Exit;
    AtTime := TrainThreatTime(Move);
    Height := BaseY-1.02;
    if LowSweep then Height := BaseY-0.27;
    if T<AtTime then begin
      Line(TargetX-0.20,Height,TargetX+0.02,Height-0.31,0.12,RGB(201,48,53));
      Exit;
    end;
    Dur := Max(0.045,Min(0.14,(Move.Time-Move.Start)*0.19));
    Bolt(TargetX-0.24,Move.FromX-0.34,Height,(T-AtTime)/Dur,RGB(223,56,43));
  end;

  procedure Enemy(const Move: TTrainCue);
  var
    Pose, FiringPose: TTrainPose;
    Elapsed, Roof, TargetX, Offset, CarStart, StepRoof, U, Approach, EntryX, LandingX, Roll, ReadyAt, Flight: Double;
    FromNextCar: Boolean;
    CarIndex, Facing: Integer;
    Block: TTrainObstacle;
    Patrol, Phase: Double;
  begin
    TargetX := Move.ToX+TrainReach;
    if Move.Kind=tmShot then TargetX := Move.ToX+TrainShotReach;
    CarIndex := Floor(TargetX/TrainPitch);
    CarStart := CarIndex*TrainPitch;
    Offset := 0;
    if CarIndex<FPlan.InitialCars-1 then Offset := RearOffset;
    if TargetX>=FPlan.InitialCars*TrainPitch then begin
      if T<FPlan.Cue[FPlan.ImpactIndex-1].Finish then Exit;
      Offset := RightOffset;
    end;
    Roof := FPlan.RoofY(TargetX);
    Elapsed := T-Move.Time;
    if Elapsed>0.60 then Exit;
    FromNextCar := (Move.Kind=tmVaultHit) and
      (Abs(CarStart+TrainPitch-FPlan.InitialCars*TrainPitch)>0.01) and
      (CarStart+TrainPitch<FPlan.TrainLength);
    LandingX := Min(CarStart+TrainCarWidth-0.36,TargetX+1.35);
    if FPlan.RoofObstacle(CarIndex,Block) and (TargetX<Block.Left) then
      LandingX := Min(LandingX,Block.Left-0.24);
    EntryX := LandingX;
    if FromNextCar then EntryX := CarStart+TrainPitch+0.53;
    if (TargetX+Offset<FarEdge-2.5) or (EntryX+Offset>NearEdge+6) then Exit;
    Pose := Default(TTrainPose);
    Pose.X := TargetX;
    Pose.Y := Roof;
    Roll := 0;
    Facing := -1;
    ReadyAt := -0.67;
    if FromNextCar then ReadyAt := -1.05;
    if Elapsed<0 then begin
      if Elapsed<ReadyAt then begin
        U := TrainEase((ReadyAt-Elapsed)/0.22);
        Phase := T*(4.15+0.28*(CarIndex mod 3))+TargetX;
        Patrol := Min(1.12,Max(0.30,EntryX-TargetX+0.18));
        Pose.X := EntryX-Patrol*U*(0.5+0.5*Sin(Phase));
        Pose.Y := FPlan.RoofY(EntryX);
        Pose.Run := (0.50+0.39*Abs(Cos(Phase)))*U;
        if Cos(Phase)<0 then Facing := 1;
      end
      else if FromNextCar and (Elapsed<-0.47) then begin
        U := EnsureRange((Elapsed+1.05)/0.58,0.0,1.0);
        Pose.X := EntryX+(LandingX-EntryX)*U;
        StepRoof := FPlan.RoofY(EntryX);
        Pose.Y := StepRoof+(Roof-StepRoof)*U-4*1.28*U*(1-U);
        Pose.Airborne := (U>0) and (U<1);
      end
      else begin
        if FromNextCar then Approach := TrainEase((Elapsed+0.47)/0.47)
        else Approach := TrainEase((Elapsed+0.67)/0.67);
        Pose.X := LandingX+(TargetX-LandingX)*Approach;
        Pose.Run := 1-TrainEase((Approach-0.72)/0.28);
        if Move.Kind in [tmVaultHit,tmDuckHit,tmHurdleHit] then
          Pose.Reach := Max(0.0,1-Abs(T-TrainThreatTime(Move))/0.14);
      end;
    end
    else begin
      U := 0.78;
      if Move.Kind in [tmVaultHit,tmHurdleHit] then U := 0.53;
      Burst(TargetX+Offset,Roof-U,Elapsed,1.58,RGB(239,111,30));
      Pose.X := TargetX+Elapsed*4.4;
      Pose.Y := Roof-Elapsed*(4.9-7.5*Elapsed);
      Pose.Airborne := True;
      Roll := Min(1.70,0.32+Elapsed*6.0);
    end;
    Pose.X := Pose.X+Offset;
    Figure(Pose,EnemyColor,0.99,Facing,Roll,Move.Kind in [tmDuckHit,tmHurdleHit]);
    if Move.Kind in [tmVaultHit,tmDuckHit,tmHurdleHit] then
      Sweep(Move,Pose.X,Roof,Move.Kind<>tmDuckHit);
    if Move.Kind=tmShot then begin
      Flight := Min(0.125,(Move.Time-Move.Start)*0.64);
      FiringPose := FPlan.PoseAt(Move.Time-Flight);
      Bolt(FiringPose.X+0.55,TargetX,Roof-0.78,(T-Move.Time+Flight)/Flight,RGB(8,126,212));
    end;
  end;


begin
  T := Frame.Time;
  Travel := 0;
  Scale := 1;
  CenterX := 4.3;
  CenterY := -0.36;
  ViewWidth := 15.0;
  Shake := 0;
  RearOffset := 0;
  RightRear := 0;
  RightOffset := 0;
  CrashBlend := 0;
  if FPlan<>nil then begin
    T := Min(T,FPlan.EndTime);
    Travel := FPlan.TravelAt(T);
    if FPlan.Count>0 then begin
      P := FPlan.PoseAt(T);
      LeftImpact := FPlan.Cue[FPlan.ImpactIndex];
      RightImpact := FPlan.Cue[FPlan.ImpactIndex+1];
      Couple := FPlan.Cue[FPlan.ImpactIndex+2];
      LastCue := FPlan.Cue[FPlan.Count-1];
      RearOffset := FPlan.LeftNoseAt(T)-((FPlan.InitialCars-1)*TrainPitch-TrainGap);
      RightRear := FPlan.RightRearAt(T);
      RightOffset := RightRear-FPlan.InitialCars*TrainPitch;
      ViewWidth := TrainRoofViewWidth;
      CenterX := FPlan.RoofCameraX(T);
      CenterY := -0.72;
      FPlan.CollisionCamera(T,CrashX,CrashWidth,CrashBlend);
      if CrashBlend>0 then begin
        CenterX := CenterX+(CrashX-CenterX)*CrashBlend;
        CenterY := CenterY+(1.17-CenterY)*CrashBlend;
        ViewWidth := ViewWidth+(CrashWidth-ViewWidth)*CrashBlend;
      end;
      Board := FPlan.Cue[0];
      if T<Board.Time+0.30 then begin
        U := 1-TrainEase((T-Board.Start)/(Board.Time+0.30-Board.Start));
        ViewWidth := ViewWidth+7.4*U;
        CenterX := CenterX+(P.X+4.1-CenterX)*U;
        CenterY := CenterY+1.88*U;
      end;
      if T>=LastCue.Start then begin
        U := TrainEase((T-LastCue.Start)/0.48);
        ViewWidth := ViewWidth+7.0*U;
        CenterX := CenterX+(P.X+1.22-CenterX)*U;
        CenterY := CenterY+2.1*U;
      end;
      for I := FPlan.ImpactIndex to FPlan.ImpactIndex+1 do begin
        Age := T-FPlan.Cue[I].Time;
        if (Age>=0) and (Age<0.30) then
          Shake := Shake+0.30*(1-Age/0.30)*Sin(84*Age);
      end;
    end;
  end;
  Scale := Min(Frame.Width/ViewWidth,Frame.Height/(ViewWidth*0.56));
  FarEdge := CenterX-Frame.Width/(2*Scale)-0.1;
  NearEdge := CenterX+Frame.Width/(2*Scale)+0.1;

  for I := 0 to 21 do begin
    Color := MixColor(RGB(102,188,242),RGB(225,245,249),Min(1.0,I/21));
    Surface.FillRect(0,I*Frame.Height/22,Frame.Width,(I+1)*Frame.Height/22+1,Color);
  end;
  // 複数の距離に置いた形と枕木で、一定の高さの線路でも走行が読める。
  Surface.Circle(Frame.Width*0.77,Frame.Height*0.24,Min(Frame.Width,Frame.Height)*0.068,RGB(255,249,194),True);
  for J := 0 to 1 do begin
    Y := -2.68+J*1.10;
    U := Travel*(0.15+J*0.09);
    Color := MixColor(RGB(139,191,158),RGB(88,159,113),J);
    for I := Floor((FarEdge+U)/8.7)-1 to Ceil((NearEdge+U)/8.7) do begin
      X := I*8.7-U;
      Quad(X-1.4,Y+2.6,X+2.1,Y-1.25-0.65*Sin(I*2.2),X+7.0,Y+0.46,X+10.9,Y+2.6,Color);
    end;
  end;
  Box(FarEdge,RailY+0.03,NearEdge,RailY+Frame.Height/Scale,RGB(127,164,96));

  if (FPlan=nil) or (FPlan.Count=0) then begin
    DrawTrack;
    if not Frame.BackgroundOnly then begin
      Car(0,0,MainColor,False,False);
      Car(TrainPitch,0,MainColor,True,False);
    end;
    Exit;
  end;
  if T<FPlan.Cue[0].Time+0.65 then
    Platform(-10.6-Travel,13.00,TrainPlatformY,True);
  StationX := FPlan.TrainLength-1.5+FPlan.TravelAt(FPlan.Arrival)-Travel;
  Platform(StationX,14.0,TrainPlatformY,True);
  DrawTrack;

  if Frame.BackgroundOnly then Exit;
  FirstCar := Max(0,Floor((FarEdge-RearOffset)/TrainPitch));
  LastCar := FPlan.InitialCars-1;
  for I := FirstCar to LastCar-1 do
    Car(I*TrainPitch+RearOffset,0,MainColor,False,False);
  Car(LastCar*TrainPitch,0,MainColor,True,False);
  if T>=FPlan.Cue[FPlan.ImpactIndex-1].Finish then
    for I := 0 to FPlan.NextCars-1 do
      Car(RightRear+I*TrainPitch,FPlan.RoofY((FPlan.InitialCars+I)*TrainPitch+0.4),
        NextColor,I=FPlan.NextCars-1,(T>=RightImpact.Time) and (I=0));
  for I := 1 to FPlan.Count-4 do RoofEquipment(FPlan.Cue[I]);
  Burst((FPlan.InitialCars-1)*TrainPitch-TrainGap*0.5,RailY-0.65,T-LeftImpact.Time,2.65,RGB(232,69,33));
  Burst(FPlan.InitialCars*TrainPitch-TrainGap*0.5,RailY-0.65,T-RightImpact.Time,2.65,RGB(232,69,33));
  Burst(FPlan.InitialCars*TrainPitch-TrainGap*0.5,RailY-0.64,T-Couple.Time,1.65,RGB(18,115,205));

  for I := 1 to FPlan.Count-4 do begin
    C := FPlan.Cue[I];
    if TrainRegularEnemy(C.Kind) then Enemy(C);
  end;
  BossFirst := FPlan.Cue[FPlan.Count-3];
  BossFinal := FPlan.Cue[FPlan.Count-2];
  BossX := BossFirst.ToX+TrainReach;
  N := Default(TTrainPose);
  if T<BossFirst.Time then begin
    U := TrainEase((T-BossFirst.Start+0.29)/Max(0.02,BossFirst.Time-BossFirst.Start+0.29));
    BossX := BossX+3.6*(1-U)+0.28*(1-U)*Sin(T*6);
    N.Run := 1-0.65*U;
    N.Reach := Max(0.0,1-Abs(T-TrainThreatTime(BossFirst))/0.13);
  end
  else begin
    U := TrainEase((T-BossFirst.Time)/Max(0.14,BossFinal.Start-BossFirst.Time));
    BossX := BossX+(BossFinal.ToX-BossFirst.ToX)*U;
    N.Run := Sin(Pi*U);
    N.Crouch := 0.56*Max(0.0,1-(T-BossFirst.Time)/0.23);
  end;
  BossY := FPlan.RoofY(BossX);
  BossX := BossX+RightOffset;
  if (T>=FPlan.Cue[FPlan.ImpactIndex-1].Finish) and (BossX>=FarEdge-1.8) and (BossX<=NearEdge+7.4) then begin
    N.X := BossX;
    N.Y := BossY;
    Age := T-BossFinal.Time;
    BossRoll := 0;
    if Age>=0 then begin
      N.X := N.X+Min(0.52,Age)*3.1;
      N.Y := N.Y-Max(0.0,2.3*Age-5.4*Sqr(Age));
      N.Airborne := Age<0.43;
      BossRoll := Min(1.68,0.24+Age*4.6);
    end
    else if T>=BossFinal.Start then
      N.Reach := Max(0.0,1-Abs(T-TrainThreatTime(BossFinal))/0.12);
    Figure(N,BossColor,1.08,-1,BossRoll,True);
    C := FPlan.Cue[FPlan.Count-4];
    if (T>=C.Start) and (T<C.Time) then
      Bolt(BossX-0.31,C.FromX-0.61,BossY-0.24,(T-TrainThreatTime(C))/0.18,RGB(229,52,57));
    Sweep(BossFirst,BossX,BossY-0.10,False);
    if T>=BossFinal.Start then begin
      U := Min(0.10,(BossFinal.Time-BossFinal.Start)*0.60);
      Ahead := FPlan.PoseAt(BossFinal.Time-U);
      Bolt(Ahead.X+0.49,BossFinal.ToX+TrainReach,BossY-0.77,(Age+U)/U,RGB(19,132,242));
    end;
    Burst(BossFirst.ToX+TrainReach,BossY-0.79,T-BossFirst.Time,1.75,RGB(226,68,132));
    Burst(BossFinal.ToX+TrainReach,BossY-0.77,Age,2.25,RGB(236,102,32));
  end;
  if P.Run>0.8 then begin
    Line(P.X-1.24,P.Y-0.25,P.X-0.39,P.Y-0.25,0.028,RGB(241,247,239));
    Line(P.X-1.83,P.Y-0.57,P.X-0.70,P.Y-0.57,0.033,RGB(241,247,239));
  end;
  if P.Land>0 then begin
    Age := (1-P.Land)*0.12;
    Burst(P.X,P.Y-0.055,Age,0.72,RGB(144,80,32));
  end;
  Figure(P,HeroColor,1.0,1);
end;

end.
