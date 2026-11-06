unit RhythmCannonScene;
// 破壊・砲弾・回避・カメラを絶対時刻から描く。フレーム間の状態を積まない。
interface

uses RhythmAnimation,RhythmRenderSurface,RhythmAudio,RhythmPlanRef,RhythmCannonPlan,RhythmEqualizer;

type
  TCannonAnimation=class(TAnimationScene)
  private
    FAudio:TRhythmAudio; // 共通Rendererから借用
    FRef:TRhythmPlanRef;
    FPlan:TCannonPlan;
    FAttempt,FError:string;
  public
    destructor Destroy;override;
    procedure SetReference(const Ref:TRhythmPlanRef);
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
    function Notice:string;override;
    function GoalTime:Double;override;
    function Activity(Time:Double;out Value:TEqualizerActivity):Boolean;
    property Audio:TRhythmAudio read FAudio write FAudio;
  end;

implementation

uses System.Types,System.Math,System.SysUtils,Vcl.Graphics,RhythmCannonTargets,
  RhythmCannonCodec,RhythmCannonArt;

type
  TCannonCameraMotion=record
    Kick,Zoom,Focus:Double;
  end;
  TCannonPainter=record
    Art:TCannonArt;
    Plan:TCannonPlan;
    Stage:TCannonStage;
    Time:Double;
    StageIndex:Integer;
    FinalStage:Boolean;
    function CameraMotion(From:TCannonStage):TCannonCameraMotion;
    procedure Camera(const Frame:TAnimationFrame);
    procedure Background;
    procedure OutgoingField(AfterGuns:Boolean);
    procedure Connections;
    procedure Targets(Broken:Boolean);
    procedure FallingOnCargo;
    procedure Gun(Barrel:Integer);
    procedure Shells;
    procedure SupportShot(Index,Barrel:Integer;const Muzzle:TPointF);
    procedure Enemy(Index:Integer);
    procedure SmokeEffects;
    procedure Destruction;
    procedure Draw(const Frame:TAnimationFrame);
  end;

function TCannonPainter.CameraMotion(From:TCannonStage):TCannonCameraMotion;
var Cue:TCannonCue; Part:TCannonPart; I:Integer; Age,Kick,Zoom,Focus,Impact,Finish:Double;
begin
  Kick:=0;
  Focus:=0;
  Finish:=From.Finish;
  for Cue in From.Cues do begin
    Age:=Time-Cue.Time;
    if (Age>=0) and (Age<0.31) then begin
      Impact:=Max(0.0,(Cue.Power-0.47)*2);
      Kick:=Max(Kick,Impact*Sqr(1-Age/0.31));
      if Cue.Enemy=ceNone then Focus:=Max(Focus,Impact*Sin(Pi*Age/0.31)*0.038);
    end;
  end;
  for Part in From.Parts do
    if (Part.Attack>=0) and (Time>=Part.LandAt) and (Time<Part.LandAt+0.28) then
      Kick:=Max(Kick,Min(1.0,Part.W*Part.H*0.10)*(1-(Time-Part.LandAt)/0.28));
  for I:=0 to High(From.Parts) do begin
    Age:=Time-From.AssemblyTime(I);
    if (Age>=0) and (Age<0.13) then Kick:=Max(Kick,0.16*(1-Age/0.13));
  end;
  Zoom:=1+Focus;
  if CannonBoss(From.Kind) and (Length(From.Cues)>0) then begin
    Zoom:=Zoom+0.052*CannonEase((Time-Finish+1.7)/1.15)*(1-CannonEase((Time-Finish+0.18)/0.26));
    Zoom:=Zoom-0.115*CannonEase((Time-Finish)/0.35);
  end;
  Result.Kick:=Kick;
  Result.Zoom:=Zoom;
  Result.Focus:=Focus;
end;

procedure TCannonPainter.Camera(const Frame:TAnimationFrame);
var NowMotion,PreviousMotion:TCannonCameraMotion; U,Span:Double;
begin
  NowMotion:=CameraMotion(Stage);
  if StageIndex>0 then begin
    Span:=Min(0.79,(Stage.Stop-Stage.Start)*0.44);
    U:=CannonEase((Time-Stage.Start)/Span);
    if U<1 then begin
      PreviousMotion:=CameraMotion(Plan.Stages[StageIndex-1]);
      NowMotion.Kick:=CannonMix(PreviousMotion.Kick,NowMotion.Kick,U);
      NowMotion.Zoom:=CannonMix(PreviousMotion.Zoom,NowMotion.Zoom,U);
      NowMotion.Focus:=CannonMix(PreviousMotion.Focus,NowMotion.Focus,U);
    end;
  end;
  Art.W:=Frame.Width;
  Art.H:=Frame.Height;
  Art.Scale:=Min(Art.W/CannonWidth,Art.H/CannonHeight)*NowMotion.Zoom;
  Art.Left:=(Art.W-CannonWidth*Art.Scale)*0.5-NowMotion.Focus*Art.Scale*3.1+
    Sin(Time*94)*Art.Scale*NowMotion.Kick*0.16;
  Art.Top:=(Art.H+CannonHeight*Art.Scale)*0.5+Cos(Time*78)*Art.Scale*NowMotion.Kick*0.12;
end;

procedure TCannonPainter.Background;
var FromIndex,ToIndex:Integer; Span,U:Double; Neighbor:TCannonStage;
begin
  FromIndex:=StageIndex;
  ToIndex:=StageIndex;
  U:=0;
  // 隣り合う区間の長さに合わせ、境界の前後で同じ色の曲線を評価する。
  if StageIndex>0 then begin
    Neighbor:=Plan.Stages[StageIndex-1];
    Span:=Min(0.87,Min(Stage.Stop-Stage.Start,Neighbor.Stop-Neighbor.Start)*0.44);
    if Time<Stage.Start+Span then begin
      FromIndex:=StageIndex-1;
      U:=CannonEase((Time-Stage.Start+Span)/(2*Span));
    end;
  end;
  if (FromIndex=StageIndex) and not FinalStage then begin
    Neighbor:=Plan.Stages[StageIndex+1];
    Span:=Min(0.87,Min(Stage.Stop-Stage.Start,Neighbor.Stop-Neighbor.Start)*0.44);
    if Time>=Neighbor.Start-Span then begin
      ToIndex:=StageIndex+1;
      U:=CannonEase((Time-Neighbor.Start+Span)/(2*Span));
    end;
  end;
  Art.Background(Plan.Stages[FromIndex].Kind,Plan.Stages[ToIndex].Kind,FromIndex,ToIndex,Time,U);
end;

procedure TCannonPainter.OutgoingField(AfterGuns:Boolean);
var Previous:TCannonPainter; U:Double; I:Integer;
begin
  if StageIndex=0 then Exit;
  U:=(Time-Stage.Start)/Min(0.96,(Stage.Stop-Stage.Start)*0.48);
  if U>=1 then Exit;
  Previous:=Self;
  Dec(Previous.StageIndex);
  Previous.Stage:=Plan.Stages[Previous.StageIndex];
  Previous.FinalStage:=False;
  Previous.Art.Alpha:=1-CannonEase((U-0.08)/0.92);
  if AfterGuns then begin
    Previous.Targets(True);
    for I:=0 to High(Previous.Stage.Cues) do
      if Previous.Stage.Cues[I].Enemy<>ceNone then Previous.Enemy(I);
    Previous.Destruction;
  end else begin
    Previous.SmokeEffects;
    Previous.FallingOnCargo;
    Previous.Connections;
    Previous.Targets(False);
  end;
end;

procedure TCannonPainter.Connections;

  procedure Joint(A,B:Integer;Width:Double);
  var P,Q:TCannonPose; C:TColor;
  begin
    if (Time<Max(Stage.AssemblyTime(A),Stage.AssemblyTime(B))) or
      ((Stage.Parts[A].Attack>=0) and (Time>=Stage.Parts[A].BreakAt)) or
      ((Stage.Parts[B].Attack>=0) and (Time>=Stage.Parts[B].BreakAt)) then Exit;
    P:=Stage.PartPose(A,Time);
    Q:=Stage.PartPose(B,Time);
    C:=$0083889A;
    if Stage.Kind=ctRobot then C:=$009772B5;
    if Stage.Kind=ctAirship then C:=$00A0785E;
    Art.Line(P.X,P.Y,Q.X,Q.Y,Width,CannonInk);
    Art.Line(P.X,P.Y,Q.X,Q.Y,Width*0.73,C);
    Art.Line(P.X-0.08,P.Y+0.09,Q.X-0.08,Q.Y+0.09,Width*0.24,CannonTint(C,CannonIvory,0.63));
  end;

begin
  case Stage.Kind of
    ctBridge:begin Joint(6,9,0.35); Joint(7,9,0.35); Joint(4,5,0.24); end;
    ctFactory:begin Joint(0,2,0.33); Joint(1,5,0.29); Joint(3,4,0.32); Joint(5,7,0.33); end;
    ctTower:begin Joint(4,11,0.37); Joint(2,11,0.61); Joint(6,10,0.38); end;
    ctRobot:begin
      Joint(0,6,0.62); Joint(1,7,0.62); Joint(6,9,0.82); Joint(7,9,0.82);
      Joint(8,9,0.72); Joint(3,10,0.69); Joint(4,10,0.69); Joint(10,9,0.92);
    end;
    ctAirship:begin
      Joint(0,8,0.54); Joint(1,9,0.53); Joint(2,5,0.74); Joint(2,8,0.56); Joint(3,8,0.52);
      Joint(4,7,0.78); Joint(4,9,0.81); Joint(5,7,0.80); Joint(7,9,0.95);
    end;
  end;
end;

procedure TCannonPainter.Targets(Broken:Boolean);
var Layer,I,J,DrawLayer:Integer; Part:TCannonPart; P:TCannonPose;
  Age,U,Wear,Alpha,Drop,Size,Shatter,X,Y:Double;
begin
  for Layer:=0 to 2 do begin
    if Broken<>(Layer=2) then Continue;
    for I:=0 to High(Stage.Parts) do begin
      Part:=Stage.Parts[I];
      Age:=Time-Part.BreakAt;
      DrawLayer:=1;
      if Part.Shape=cpCore then DrawLayer:=0;
      if (Part.Attack>=0) and (Age>=0) then DrawLayer:=2;
      if Layer<>DrawLayer then Continue;
      Shatter:=Stage.ShatterTime(I);
      if Time>=Shatter then begin
        P:=Stage.PartPose(I,Shatter);
        Size:=Sqrt(Part.W*Part.H);
        Art.Wreckage(P.X,P.Y,Time-Shatter,Size,I*157+StageIndex*43);
        Continue;
      end;
      P:=Stage.PartPose(I,Time);
      Wear:=Stage.Wear(I,Time);
      Alpha:=1;
      if Layer=2 then begin
        Wear:=Min(1.0,0.24+Age*1.45);
        if Time>Part.LandAt then
          Alpha:=CannonMix(1.0,0.84,CannonEase((Time-Part.LandAt)/0.45));
      end else begin
        Drop:=Stage.AssemblyDrop(I,Time);
        // 縦長のプレビューでも、パーツは上端より外から入る。
        P.Y:=P.Y+Drop*Max(0.0,Art.Top/Art.Scale-CannonHeight);
        if Art.Screen(P.X,P.Y-(Part.W+Part.H)*0.5).Y<0 then Continue;
        if (Drop>0.04) and (Drop<0.68) then
          for J:=-1 to 1 do begin
            X:=P.X+J*Min(0.31,Part.W*0.30);
            Y:=P.Y+Part.H*0.44;
            Art.Line(X,Y,X+J*0.12,Y+(1-Drop)*(0.51+0.31*Abs(J)),
              0.034,CannonIvory,(1-Drop)*0.69);
          end;
      end;
      Art.Part(Stage.Kind,Part.Shape,P,Part.W,Part.H,Time,Wear,Alpha);
      U:=(Time-Stage.AssemblyTime(I))/0.15;
      if (U>=0) and (U<1) then begin
        Y:=Max(0.03,P.Y-Part.H*0.39);
        Art.Line(P.X-0.48-U*0.51,Y,P.X+0.48+U*0.51,Y,0.068,CannonIvory,1-U);
        Art.Disk(P.X,Y,0.24*(1-U),CannonGold);
      end;
    end;
  end;
end;

procedure TCannonPainter.FallingOnCargo;
var I,Index:Integer; Part:TCannonPart; Pose,Debris:TCannonPose; Size,Age,X,Opacity:Double;
begin
  if Length(Stage.Cues)=0 then Exit;
  Index:=-1;
  Size:=1.35;
  for I:=0 to High(Stage.Parts) do begin
    Part:=Stage.Parts[I];
    if (Part.Attack<>High(Stage.Cues)) or (Part.Y<1.7) or (Part.W*Part.H<=Size) then Continue;
    Size:=Part.W*Part.H;
    Index:=I;
  end;
  if Index<0 then Exit;
  Part:=Stage.Parts[Index];
  Pose:=Stage.PartPose(Index,Part.LandAt);
  X:=Pose.X+0.68;
  if X>23 then X:=Pose.X-0.68;
  Age:=Time-Part.LandAt;
  Opacity:=CannonEase((Time-Stage.Start)/0.27);
  Debris:=Default(TCannonPose);
  Debris.X:=X;
  Debris.Y:=0.36;
  if Age>=0 then begin
    Debris.X:=X+0.59*CannonEase(Age*2);
    Debris.Angle:=CannonEase(Age*5)*1.42;
    Debris.Y:=0.30+0.58*Sin(Pi*Min(1.0,Age*1.8));
  end;
  if CannonBoss(Stage.Kind) and (Age>=0.08) then
    Art.Wreckage(X,0.30,Age-0.08,0.72,197+StageIndex)
  else
    Art.Part(Stage.Kind,cpCrate,Debris,0.72,0.72,Time,0.95*Ord(Age>=0),Opacity);
  Art.Blast(X,0.15,Age-0.04,0.65,871+StageIndex,CannonGold,True);
end;

procedure TCannonPainter.Gun(Barrel:Integer);
var Selected,Latest:Integer; Closest,Recoil,Angle,Age,Enter:Double;
  Base,Origin,Aim:TPointF; Life:TCannonSupportLife; Wreck:TCannonPose;
  AimStage,LastStage:TCannonStage;

  procedure Scan(From:TCannonStage);
  var I:Integer; T,Distance:Double;
  begin
    for I:=0 to High(From.Cues) do begin
      if not Plan.Fires(From,I,Barrel) then Continue;
      T:=From.Launch(I,Barrel);
      if (Barrel>0) and ((T<Life.Ready) or (T>=Life.Lost)) then Continue;
      Distance:=Abs(T-Time);
      if Distance<Closest then begin
        Selected:=I;
        AimStage:=From;
        Closest:=Distance;
      end;
      if (T<=Time) and (Time-T<Age) then begin
        Latest:=I;
        LastStage:=From;
        Age:=Time-T;
      end;
    end;
  end;

begin
  Base:=Stage.Pivot(Barrel,Time);
  if Barrel>0 then begin
    if not Plan.SupportAt(Barrel,Time,Life) then Exit;
    if Time>=Life.Lost then begin
      Age:=Time-Life.Lost;
      if Age<0.26 then begin
        Wreck.X:=Base.X-2.2*Age;
        Wreck.Y:=CannonMix(Base.Y,0.36,Sqr(Age/0.26));
        Wreck.Angle:=Age*8.0;
        Art.Part(ctTower,cpTurret,Wreck,1.02,0.53,Time,1,1);
      end else
        Art.Wreckage(Base.X-0.57,0.36,Age-0.26,1.08,Barrel*193);
      Art.Blast(Base.X,Base.Y,Age,1.04,Barrel*103,CannonOrange,False);
      Art.Blast(Base.X-0.57,0.22,Age-0.26,0.55,Barrel*127,CannonGold,True);
      Exit;
    end;
  end;
  Closest:=1E9;
  Selected:=-1;
  Latest:=-1;
  Age:=10;
  AimStage:=Stage;
  LastStage:=Stage;
  if (StageIndex>0) and (Time-Stage.Start<1) then Scan(Plan.Stages[StageIndex-1]);
  Scan(Stage);
  if not FinalStage and (Plan.Stages[StageIndex+1].Start-Time<1) then
    Scan(Plan.Stages[StageIndex+1]);
  Angle:=0.20+0.07*Sin(Time*1.9);
  if Selected>=0 then begin
    Origin:=AimStage.Muzzle(Selected,Barrel);
    Aim:=AimStage.Pivot(Barrel,AimStage.Launch(Selected,Barrel));
    Enter:=1-CannonEase((Closest-0.17)/0.55);
    Angle:=CannonMix(Angle,ArcTan2(Origin.Y-Aim.Y,Origin.X-Aim.X),Enter);
  end;
  Recoil:=0;
  if Age<0.22 then Recoil:=0.26*Sqr(1-Age/0.22);
  if Barrel>0 then begin
    Recoil:=Recoil*0.72;
    if Time<Life.Ready then
      Base.Y:=Base.Y-1.26*(1-CannonEase((Time-Life.Arrival)/Max(0.000001,Life.Ready-Life.Arrival)));
  end else begin
    Art.Box(Base.X-1.08,-0.07,2.16,0.13,CannonInk,0.54);
    if Abs(Stage.HeroX(Time+0.04)-Base.X)>0.045 then
      Art.Smoke(Base.X-0.61,0.16,0.19,0.64,77);
  end;
  Art.Cannon(Base,Angle,Recoil,Base.X*2.8,Barrel>0);
  if (Latest>=0) and (Age<0.68) then begin
    Origin:=LastStage.Muzzle(Latest,Barrel);
    Art.Smoke(Origin.X,Origin.Y,Age,0.48,41+Latest*7+Barrel);
    if Age<0.12 then begin
      Enter:=1-Age/0.12;
      Art.Line(Origin.X-0.22,Origin.Y,Origin.X+0.68*Cos(Angle),Origin.Y+0.68*Sin(Angle),
        0.29*Enter,CannonGold,Enter);
      Art.Disk(Origin.X,Origin.Y,0.27*Enter,CannonIvory);
    end;
  end;
end;

procedure TCannonPainter.Shells;
var I,J,K:Integer; Cue:TCannonCue; Origin,P,Q:TPointF; T,Age,Width:Double;
begin
  for I:=0 to High(Stage.Cues) do begin
    Cue:=Stage.Cues[I];
    if (Cue.Time<Time) or (Cue.Time-Time>0.90) then Continue;
    for J:=0 to Cue.Volley-1 do begin
      if not Plan.Fires(Stage,I,J) then Continue;
      T:=Stage.Launch(I,J);
      Age:=Time-T;
      if Age<0 then Continue;
      Width:=0.11+0.07*Cue.Power;
      if J>0 then Width:=Width*0.72;
      P:=Stage.Shell(I,J,Time);
      for K:=1 to 6 do begin
        Q:=Stage.Shell(I,J,Max(T,Time-K*0.024));
        Art.Line(Q.X,Q.Y,P.X,P.Y,Width*(1.62-K*0.16),CannonGold,0.88-K*0.115);
        P:=Q;
      end;
      P:=Stage.Shell(I,J,Time);
      Origin:=Stage.Shell(I,J,Max(T,Time-0.016));
      Art.Line(Origin.X,Origin.Y,P.X,P.Y,Width*2.05,CannonInk);
      Art.Line(Origin.X,Origin.Y,P.X,P.Y,Width*1.43,CannonOrange);
      Art.Disk(P.X,P.Y,Width*0.64,CannonIvory);
    end;
  end;
end;

procedure TCannonPainter.SupportShot(Index,Barrel:Integer;const Muzzle:TPointF);
var Cue:TCannonCue; Target,P,Q:TPointF; U,Trail,Age:Double;
begin
  Cue:=Stage.Cues[Index];
  Age:=Time-Cue.Time;
  U:=1+Age/Cue.Lead;
  if (U<0) or (U>=1) then Exit;
  Target:=Stage.Pivot(Barrel,Cue.Time);
  Trail:=Max(0.0,U-0.13);
  // 上から砲台へ落ちる弾道で、手前にある別の砲台の上を通す。
  P:=PointF(CannonMix(Muzzle.X,Target.X,U),CannonMix(Muzzle.Y,Target.Y,U)+11.4*U*(1-U));
  Q:=PointF(CannonMix(Muzzle.X,Target.X,Trail),
    CannonMix(Muzzle.Y,Target.Y,Trail)+11.4*Trail*(1-Trail));
  Art.Line(P.X,P.Y,Q.X,Q.Y,0.22,CannonRed,0.76);
  Art.Line(P.X,P.Y,Q.X,Q.Y,0.069,CannonOrange);
  Art.Disk(P.X,P.Y,0.18,CannonInk);
  Art.Disk(P.X,P.Y,0.14,CannonRed);
  Art.Disk(P.X-0.038,P.Y+0.032,0.074,CannonIvory);
end;

procedure TCannonPainter.Enemy(Index:Integer);
var Cue:TCannonCue; P,Q,Muzzle:TPointF; Age,X,Y,R,U,Travel,Target,Lead,Spread:Double; I,J,Count,Barrel:Integer;
  Tint:TColor;
begin
  Cue:=Stage.Cues[Index];
  Age:=Time-Cue.Time;
  if (Age< -0.82) or (Age>0.97) then Exit;
  X:=Stage.Threat(Cue.Time);
  R:=CannonHazardRadius(Cue.Enemy);
  Muzzle:=Stage.EnemyOrigin(Cue.Time-Cue.Lead);
  Barrel:=Stage.SupportHit(Index);
  if Barrel>0 then SupportShot(Index,Barrel,Muzzle);
  Tint:=CannonRed;
  if Cue.Enemy=ceLaser then Tint:=$00FE5DDD;
  if Age<0 then begin
    // 危険範囲は地面に置く。砲台の移動や敵弾の飛行に追従させない。
    Art.Box(X-R,0.015,2*R,0.12,Tint,0.40+0.28*Sqr(Sin(Age*23)));
    for I:=0 to 4 do begin
      Target:=X-R+I*R*0.40;
      Art.Line(Target,0.03,Target+R*0.27,0.34,0.052,Tint,0.80);
    end;
    if Cue.Enemy=ceLaser then
      Art.Line(X,Max(5.2,Muzzle.Y),X,0.1,0.042,Tint,0.42);
  end;
  if Cue.Enemy in [ceShell,ceBurst,ceSpread,ceHeavy] then begin
    Count:=1;
    if Cue.Enemy in [ceBurst,ceSpread] then Count:=3;
    for I:=0 to Count-1 do begin
      Spread:=0;
      if Cue.Enemy=ceSpread then Spread:=(I-1)*0.64;
      Target:=X+Spread;
      Lead:=Cue.Lead-I*0.065;
      U:=(Age+Lead)/Lead;
      if (U<0) or (U>1) then Continue;
      P:=PointF(CannonMix(Muzzle.X,Target,U),CannonMix(Muzzle.Y,0.13,U)+9.4*U*(1-U));
      Travel:=Max(0.0,U-0.13);
      Q:=PointF(CannonMix(Muzzle.X,Target,Travel),CannonMix(Muzzle.Y,0.13,Travel)+9.4*Travel*(1-Travel));
      Art.Line(P.X,P.Y,Q.X,Q.Y,0.16,Tint,0.62);
      Y:=0.15+Ord(Cue.Enemy=ceHeavy)*0.22;
      Art.Disk(P.X,P.Y,Y,CannonInk);
      Art.Disk(P.X,P.Y,Y*0.76,Tint);
      Art.Disk(P.X-0.045,P.Y+0.055,Y*0.39,CannonIvory);
    end;
    Art.Blast(Muzzle.X,Muzzle.Y,Age+Cue.Lead,0.47,Index*17,Tint,False);
    Art.Blast(X,0.17,Age,0.74+Ord(Cue.Enemy=ceHeavy)*0.65,Index*31,Tint,True);
    if Cue.Enemy=ceSpread then
      for J:=-1 to 1 do Art.Blast(X+J*0.65,0.15,Age-Abs(J)*0.045,0.43,Index*31+J,Tint,True);
  end else begin
    if (Age<0) and (Age>=-Cue.Lead) then
      Art.Disk(Muzzle.X,Muzzle.Y,0.16+0.22*Sin(Pi*Age/-Cue.Lead),Tint,0.8);
    if (Age<0) or (Age>0.52) then Exit;
    U:=Age/0.52;
    case Cue.Enemy of
      ceQuake:begin
        Target:=X+R*(U-0.5);
        for I:=0 to 6 do begin
          Y:=Target+(I-3)*0.24;
          Art.Line(Y-0.19,0.05,Y,0.46*Sin(Pi*U)+0.17,0.08,CannonGold,1-U);
          Art.Line(Y,0.46*Sin(Pi*U)+0.17,Y+0.22,0.06,0.10,Tint,1-U);
        end;
      end;
      ceFire:for I:=0 to 6 do begin
        Target:=X+(I-3)*0.27;
        Y:=0.55+0.50*Sin(Pi*U)*CannonNoise(I+Index);
        Art.Line(Target,0.05,Target+0.16*Sin(Time*30+I),Y,0.31,Tint,1-U);
        Art.Line(Target,0.05,Target,Y*0.71,0.14,CannonGold,1-U);
      end;
      ceLaser:begin
        Target:=Max(5.2,Muzzle.Y);
        Art.Line(Muzzle.X,Muzzle.Y,X,Target,0.32,Tint,1-U);
        Art.Disk(X,Target,0.24,CannonIvory,1-U);
        Art.Line(X,Target,X,0.11,0.58,Tint,1-U);
        Art.Line(X,Target,X,0.11,0.16,CannonIvory,1-U);
      end;
    end;
    Art.Blast(X,0.16,Age,0.88,Index*43,Tint,True);
  end;
end;

procedure TCannonPainter.SmokeEffects;
var I:Integer; Cue:TCannonCue; Part:TCannonPart; P:TCannonPose; Aim:TPointF; Age:Double;
begin
  for I:=0 to High(Stage.Cues) do begin
    Cue:=Stage.Cues[I];
    Age:=Time-Cue.Time;
    if (Cue.Enemy<>ceNone) or (Age<0.31) or (Age>1.55) then Continue;
    Aim:=Stage.Aim(I);
    Art.Smoke(Aim.X,Aim.Y,Age-0.31,0.49+Cue.Power*0.25,I*67+StageIndex*121);
  end;
  for I:=0 to High(Stage.Parts) do begin
    Part:=Stage.Parts[I];
    Age:=Time-Part.LandAt;
    if (Part.Attack<0) or (Age<0.24) or (Age>1.50) then Continue;
    P:=Stage.PartPose(I,Part.LandAt);
    Art.Smoke(P.X,0.12,Age-0.24,0.45+Min(0.49,Part.W*Part.H*0.085),I*97+StageIndex*23);
  end;
end;

procedure TCannonPainter.Destruction;
var I,J,Seed:Integer; Cue:TCannonCue; Part:TCannonPart; P:TCannonPose; Aim,Support:TPointF;
  Age,Power,Offset,BlastAge,Finish,Flash,Size:Double;
begin
  Finish:=Stage.Finish;
  Flash:=0;
  for I:=0 to High(Stage.Cues) do begin
    Cue:=Stage.Cues[I];
    Age:=Time-Cue.Time;
    if (Cue.Enemy<>ceNone) or (Age<0) or (Age>2.2) then Continue;
    Aim:=Stage.Aim(I);
    Seed:=67*I+121*StageIndex;
    Power:=0.38+Cue.Power*0.89;
    if I=High(Stage.Cues) then begin
      Offset:=Max(0.05,Stage.Stop-Finish);
      BlastAge:=Age*Max(1.0,1.22/Offset);
      if CannonBoss(Stage.Kind) then begin
        Power:=Power+0.77+0.39*Ord(FinalStage);
        for J:=0 to 4 do
          Art.Blast(Aim.X+(J-0.7)*1.17,Max(0.21,Aim.Y+(CannonNoise(Seed+J)-0.37)*2.16),
            BlastAge-J*0.081,Power*0.72,Seed+J*17,CannonGold,False);
        Art.Ring(Aim.X,Aim.Y,0.5+BlastAge*(21+8*Ord(FinalStage)),0.11,CannonIvory,
          Max(0.0,0.68-BlastAge*1.27));
        Flash:=0.47*Max(0.0,1-BlastAge/0.12);
      end else Power:=Power+0.39;
    end else BlastAge:=Age;
    Art.Blast(Aim.X,Aim.Y,BlastAge,Power,Seed,CannonGold,False);
    for J:=1 to Cue.Volley-1 do begin
      if not Plan.Fires(Stage,I,J) then Continue;
      Support:=Stage.Aim(I,J);
      if Sqr(Aim.X-Support.X)+Sqr(Aim.Y-Support.Y)>0.22 then
        Art.Blast(Support.X,Support.Y,BlastAge,Power*0.44,Seed+J*51,CannonOrange,False);
    end;
  end;
  for I:=0 to High(Stage.Parts) do begin
    Part:=Stage.Parts[I];
    if (Part.Attack<0) or (Time<Part.BreakAt) then Continue;
    Seed:=97*I+23*StageIndex;
    P:=Stage.PartPose(I,Time);
    Age:=Time-Part.BreakAt;
    Power:=Min(1.26,0.20+Part.W*Part.H*0.18);
    if (Part.Shape in [cpBarrel,cpTank,cpEngine,cpCore]) then Power:=Power+0.29;
    if (Age<0.75) and (Part.BreakAt>Stage.Cues[Part.Attack].Time) then
      Art.Blast(P.X,P.Y,Age,Power*0.64,Seed,CannonOrange,False);
    Age:=Time-Part.LandAt;
    if (Age<0) or (Age>2.10) then Continue;
    Size:=Power;
    P:=Stage.PartPose(I,Part.LandAt);
    if CannonBoss(Stage.Kind) then begin
      Size:=Size+0.19;
      if (Part.Attack=High(Stage.Cues)) and (Part.W*Part.H>2.0) then
        Size:=Size+0.37+0.32*Ord(FinalStage);
    end;
    if (Size>0.5) or (Part.Shape in [cpBarrel,cpWheel]) then
      Art.Blast(P.X,0.18,Age,Size,Seed,CannonOrange,True);
    if (Size>1.39) and (Age<0.44) then begin
      Art.Blast(P.X-1.09,0.15,Age-0.076,Size*0.67,Seed+11,CannonGold,True);
      Art.Blast(P.X+1.29,0.15,Age-0.15,Size*0.60,Seed+22,CannonGold,True);
    end;
  end;
  if Flash>0 then Art.Surface.FillRect(0,0,Art.W,Art.H,CannonIvory,Flash*Art.Alpha);
end;

procedure TCannonPainter.Draw(const Frame:TAnimationFrame);
var I:Integer;
begin
  Camera(Frame);
  Background;
  if Frame.BackgroundOnly then Exit;
  OutgoingField(False);
  SmokeEffects;
  FallingOnCargo;
  Connections;
  Targets(False);
  for I:=3 downto 0 do Gun(I);
  Shells;
  OutgoingField(True);
  Targets(True);
  for I:=0 to High(Stage.Cues) do
    if Stage.Cues[I].Enemy<>ceNone then Enemy(I);
  Destruction;
end;

destructor TCannonAnimation.Destroy;
begin
  FPlan.Free;
  inherited;
end;

procedure TCannonAnimation.SetReference(const Ref:TRhythmPlanRef);
begin
  FRef:=Ref;
end;

procedure TCannonAnimation.Prepare(const Frame:TAnimationFrame);
var Key:string;
begin
  Key:=FRef.Key+'|'+FRef.Digest+'|'+IntToStr(Frame.Direction);
  if FAudio<>nil then Key:=Key+'|'+FAudio.Key else Key:=Key+'|none';
  if Key=FAttempt then Exit;
  FAttempt:=Key;
  FreeAndNil(FPlan);
  FError:='';
  if FAudio=nil then Exit;
  try
    FPlan:=LoadCannonPlan(FRef,FAudio,Frame.Direction);
  except on E:Exception do FError:=E.Message;end;
end;

procedure TCannonAnimation.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var Painter:TCannonPainter;
begin
  if FPlan=nil then Exit;
  Painter.Art.Surface:=Surface;
  Painter.Art.Alpha:=1;
  Painter.Plan:=FPlan;
  Painter.Time:=EnsureRange(Frame.Time,0.0,FPlan.Duration);
  Painter.StageIndex:=FPlan.StageAt(Painter.Time);
  Painter.Stage:=FPlan.Stages[Painter.StageIndex];
  Painter.FinalStage:=Painter.StageIndex=High(FPlan.Stages);
  Painter.Draw(Frame);
end;

function TCannonAnimation.Notice:string;
begin
  Result:=FError;
end;

function TCannonAnimation.GoalTime:Double;
begin
  // 決着は専用の崩落で完結する。0は共通花火を描かない指定。
  Result:=0;
end;

function TCannonAnimation.Activity(Time:Double;out Value:TEqualizerActivity):Boolean;
var Stage:TCannonStage; Current,S,I:Integer; Age:Double; Cue:TCannonCue;
begin
  Value:=Default(TEqualizerActivity);
  Result:=True;
  if FPlan=nil then Exit;
  Current:=FPlan.StageAt(Time);
  for S:=Max(0,Current-1) to Current do begin
    Stage:=FPlan.Stages[S];
    for I:=0 to High(Stage.Cues) do begin
      Cue:=Stage.Cues[I];
      Age:=Time-Cue.Time;
      if (Age<0) or (Age>0.8) then Continue;
      Value.Valid:=True;
      Value.Hit:=I;
      Value.Pulse:=Min(1.4,Value.Pulse+Exp(-Age*8)*(0.25+0.75*Cue.Power));
      Value.Energy:=Max(Value.Energy,Cue.Power*Exp(-Age*3));
    end;
  end;
end;
end.
