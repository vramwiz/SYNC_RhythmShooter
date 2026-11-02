unit RhythmRunnerLegacyScene;
// 旧保存版の描画専用。現行バリエーションの計画や音時刻を変更しない。
interface
uses RhythmAnimation,RhythmRenderSurface,RhythmRunnerPlan;
// 旧プランを絶対時刻で描く。準備・音解析・保存は行わない。
procedure DrawRunnerLegacy(Plan:TRunnerPlan;Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
implementation
uses System.SysUtils,System.Math,Winapi.Windows,Vcl.Graphics;

procedure DrawRunnerLegacy(Plan:TRunnerPlan;Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
type
  TRunnerFoot=record
    X,Y:Double;
  end;
  TRunnerFeet=array[0..1] of TRunnerFoot;
  TRunnerArm=record
    ShoulderX,ShoulderY,ElbowX,ElbowY,HandX,HandY:Double;
  end;
var
  Scale,Left,Top,Camera,Clock,GoalX,GoalY,Age,T,Thickness:Double;
  I,J,First,Last:Integer;
  Pad:TRunnerPlatform;
  Pulse:TRunnerPulse;
  Tint:TColor;
  procedure Line(X1,Y1,X2,Y2:Double;Color:TColor;Width:Double);
  begin Surface.Line(Left+(X1-Camera)*Scale,Top+Y1*Scale,Left+(X2-Camera)*Scale,Top+Y2*Scale,Color,Max(1,Width*Scale));
  end;
  procedure Circle(X,Y,R:Double;Color:TColor;Filled:Boolean=True);
  begin Surface.Circle(Left+(X-Camera)*Scale,Top+Y*Scale,R*Scale,Color,Filled,Max(1,Scale*0.002));
  end;
  procedure Background;
  var
    N,Base:Integer;
    X,Y,Parallax:Double;
  begin
    for N:=0 to 31 do Surface.Line(0,(N+0.5)*Frame.Height/32,Frame.Width,(N+0.5)*Frame.Height/32,
    RGB(112+N*3,181+N*2,226+N div 2),Frame.Height/32+1);
    Circle(Camera+1.43,0.18,0.08,RGB(255,239,170));
    Parallax:=Camera*0.12/0.26;
    Base:=Floor(Parallax);
    for N:=-2 to 10 do begin
      X:=Camera+N*0.26-(Parallax-Base)*0.26;
      Y:=0.52+0.035*Sin((N+Base)*1.7);
      Circle(X,Y,0.25,RGB(160,199,176));
    end;
    Parallax:=Camera*0.27/0.20;
    Base:=Floor(Parallax);
    for N:=-2 to 12 do begin
      X:=Camera+N*0.20-(Parallax-Base)*0.20;
      Y:=0.76+0.045*Sin((N+Base)*2.1);
      Circle(X,Y,0.23,RGB(115,171,128));
    end;
  end;
  function Smooth(Value:Double):Double;
  begin Result:=Value*Value*(3-2*Value);
  end;
  function RunnerAt(Time:Double):TRunnerPoint;
  var
    Entry,U:Double;
  begin
    Result:=Plan.PositionAt(Time);
    Entry:=Plan.EntryDuration;
    if (Entry>0) and (Time<Entry) then begin
      U:=Time/Entry;
      Result.X:=Result.X-0.64*(1-Smooth(U));
    end;
  end;
  procedure GroundFeet(Time:Double;out Feet:TRunnerFeet;out Bob:Double);

  var

    Q,Start:TRunnerPoint;
    Ground:TRunnerPlatform;
    Index,Anchor,K,Side:Integer;
    Stride,Cycle,U,Contact,NextContact,Phase:Double;
  begin
    Stride:=RUN_SPEED*0.40;
    if Plan.RecipeVersion>=5 then Stride:=RUN_SPEED*0.34;
    Q:=RunnerAt(Time);
    Index:=Plan.StepBefore(Min(Time,Plan.GoalTime));
    Anchor:=Plan.GroundAnchor(Index);
    // Prepared anchor lookup keeps a long flat combo on the same running cycle.
    Start:=RunnerAt(Plan.Step[Anchor].Time);
    Phase:=0.25+(Q.X-Start.X)/Stride;
    Bob:=0.001*Cos(4*Pi*(Phase-0.25));
    K:=Plan.FirstPlatform(Q.X);
    if K<Plan.PlatformCount then Ground:=Plan.Platform[K]
    else Ground:=Plan.Platform[Plan.PlatformCount-1];
    for Side:=0 to 1 do begin
      // Alternate the landing leg; the other leg is half a stride ahead.
      Cycle:=Phase+0.5*((Side+Anchor) mod 2);
      U:=Frac(Cycle);
      Contact:=Start.X+Stride*(Floor(Cycle)-0.5*((Side+Anchor) mod 2));
      // Clamp the planted shoe to this stone, including short edge run-ups.
      NextContact:=EnsureRange(Contact+Stride,Ground.Left+0.004,Ground.Right-0.010);
      Contact:=EnsureRange(Contact,Ground.Left+0.004,Ground.Right-0.010);
      Feet[Side].X:=Contact;
      Feet[Side].Y:=Q.Y-0.004;
      if U>=0.5 then begin
        U:=(U-0.5)*2;
        Feet[Side].X:=Contact+(NextContact-Contact)*Smooth(U);
        Feet[Side].Y:=Feet[Side].Y-0.027*Sqr(Sin(Pi*U));
      end;
    end;
  end;
  procedure SetPieceScenery;
  var
    N,K,Index,A,B,Segment:Integer;
    Piece:TRunnerSetPiece;
    S:TRunnerStep;
    Ground:TRunnerPlatform;
    X,Y,L,R,Ridge,Base,Mid,Age,U,Press,CoilTop,PX,PY,QX,QY:Double;
    Color:TColor;
  begin
    A:=Max(0,Plan.SetPieceBefore(Clock-2.8));
    B:=Plan.SetPieceBefore(Clock+3.6);
    for N:=A to B do begin
      Piece:=Plan.SetPiece[N];
      if Piece.Kind=rkVault then begin
        S:=Plan.Step[Piece.FirstStep];
        RunnerVaultBounds(S,L,R,Ridge);
        if (R<Camera-0.08) or (L>Camera+1.88) then Continue;
        Mid:=(L+R)/2;
        Base:=Max(S.StartY,S.Y)+0.13;
        // A tall, solid landmark under the extended jump. Its top remains below
        // every shoe/body point throughout the whole horizontal overlap.
        Line(Mid,Ridge+0.018,Mid,Base,RGB(109,117,143),R-L);
        Line(Mid-0.020,Ridge+0.035,Mid-0.020,Base,RGB(160,168,183),0.024);
        Line(L+0.004,Ridge+0.006,R-0.004,Ridge+0.006,RGB(78,98,119),0.012);
        for K:=0 to 3 do begin
          Y:=Ridge+0.055+K*(Base-Ridge-0.075)/4;
          Line(L+0.008,Y,R-0.008,Y,RGB(223,200,134),0.008);
        end;
        Circle(Mid,Ridge+0.052,0.014,RGB(245,206,93));
        Line(Mid-0.006,Ridge+0.052,Mid+0.006,Ridge+0.052,RGB(255,246,194),0.004);
        // Four fixed aerial markers make the special arc readable in advance.
        for K:=1 to 4 do begin
          U:=K/5;
          Age:=(S.Time-S.Takeoff)*U;
          X:=RUN_SPEED*(S.Takeoff+Age);
          Y:=S.StartY+S.Velocity*Age+0.5*RUN_GRAVITY*Age*Age-0.060;
          Circle(X,Y,0.014,RGB(229,177,61),False);
        end;
        Age:=Clock-S.Time;
        if (Age>=0) and (Age<0.45) then begin
          Circle(RUN_SPEED*S.Time,S.Y,0.028+Age*0.24,RGB(235,160,51),False);
          for K:=0 to 5 do begin
            U:=K*Pi/3;
            Circle(RUN_SPEED*S.Time+Cos(U)*Age*0.21,S.Y-Sin(U)*Age*0.20-Age*0.10,0.004,RGB(235,160,51));
          end;
        end;
      end else begin
        for Index:=Piece.FirstStep to Piece.LastStep do begin
          S:=Plan.Step[Index];
          X:=RUN_SPEED*S.Time;
          Y:=S.Y;
          if (X<Camera-0.12) or (X>Camera+1.92) then Continue;
          K:=Plan.FirstPlatform(X);
          if K>=Plan.PlatformCount then Continue;
          Ground:=Plan.Platform[K];
          L:=Max(Ground.Left,X-0.065);
          R:=Min(Ground.Right,X+0.028);
          Mid:=(L+R)/2;
          Age:=Clock-S.Time;
          Press:=0;
          if (Age>=0) and (Age<0.24) then Press:=Sin(Pi*Age/0.24);
          CoilTop:=Y+0.025+0.018*Press;
          Color:=RGB(103,120,180);
          if (Age>=0) and (Age<0.30) then Color:=RGB(228,153,64);
          Line(L,Y+0.105,R,Y+0.105,RGB(79,101,128),0.010);
          Line(Mid,Y+0.013,Mid,CoilTop,RGB(178,193,207),0.006);
          PX:=Mid;
          PY:=CoilTop;
          for Segment:=1 to 6 do begin
            QX:=Mid;
            if Segment<6 then QX:=Mid+(Segment mod 2*2-1)*Min(0.012,(R-L)*0.25);
            QY:=CoilTop+(Y+0.10-CoilTop)*Segment/6;
            Line(PX,PY,QX,QY,Color,0.004);
            PX:=QX;
            PY:=QY;
          end;
          // The cap never sinks: planted feet keep their accepted contact Y.
          Line(L+0.004,Y+0.006,R-0.004,Y+0.006,RGB(61,101,127),0.012);
          Line(L+0.006,Y+0.003,R-0.006,Y+0.003,RGB(143,210,209),0.006);
          Circle(Mid,Y+0.031,0.004,RGB(255,220,111));
          // A dashed preview follows the same saved parabola as the character.
          if Clock<S.Time then for Segment:=0 to 5 do begin
            U:=(Segment+0.15)/6;
            Age:=(S.Time-S.Takeoff)*U;
            PX:=RUN_SPEED*(S.Takeoff+Age);
            PY:=S.StartY+S.Velocity*Age+0.5*RUN_GRAVITY*Age*Age-0.012;
            U:=(Segment+0.55)/6;
            Age:=(S.Time-S.Takeoff)*U;
            QX:=RUN_SPEED*(S.Takeoff+Age);
            QY:=S.StartY+S.Velocity*Age+0.5*RUN_GRAVITY*Age*Age-0.012;
            Line(PX,PY,QX,QY,RGB(147,179,159),0.002);
          end;
        end;
      end;
    end;
  end;
  procedure EncounterScenery;
  var
    A,B,N,K,Part,Drawn:Integer;
    E:TRunnerEncounter;
    P:TRunnerPoint;
    Age,U,Angle,R,X,Y,Kick,Lift,Spin,Strength,Size:Double;
    Color:TColor;
    procedure Body(CX,CY,Size,Turn:Double;Crate:Boolean);
      procedure Bar(AX,AY,BX,BY,Width:Double;Tint:TColor);
      var
        C,S:Double;
      begin C:=Cos(Turn);
        S:=Sin(Turn);
        Line(CX+(AX*C-AY*S)*Size,CY+(AX*S+AY*C)*Size,
        CX+(BX*C-BY*S)*Size,CY+(BX*S+BY*C)*Size,Tint,Width*Size);
      end;
    begin
      if Crate then begin Bar(-0.014,-0.009,0.014,-0.009,0.014,Color);
        Bar(-0.014,0.009,0.014,0.009,0.014,Color);
      end
      else begin Circle(CX,CY,0.024*Size,Color);
        Bar(-0.014,-0.003,0.014,-0.003,0.006,RGB(255,221,140));
      end;
      Circle(CX+(0.007*Cos(Turn)+0.003*Sin(Turn))*Size,CY+(0.007*Sin(Turn)-0.003*Cos(Turn))*Size,0.003*Size,RGB(48,66,96));
    end;
  begin
    A:=Plan.EncounterBefore(Clock-0.56)+1;
    B:=Plan.EncounterBefore(Clock+1.55+1E-8);
    Drawn:=0;
    for N:=A to B do begin E:=Plan.Encounter[N];
      if Clock<E.Show then Continue;
      Age:=Clock-E.Time;
      if (E.X+E.Radius+Max(0.0,Age)<Camera-0.08) or (E.X>Camera+1.88) then Continue;
      Strength:=Plan.Step[E.Step].Strength;
      if (Age>=0) and (Age<0.22) then begin U:=Age/0.22;
        Line(E.X,E.Y-0.013,E.X+E.Radius,E.Y-0.013,RGB(230,159,60),0.008*(1-U));
        Line(E.X,E.Y-0.008,E.X+E.Radius*0.8,E.Y-0.055*(1-U),RGB(255,216,120),0.003);
        Circle(E.X,E.Y-0.008,0.025+0.12*U,RGB(226,152,52),False);
      end;
      for K:=0 to E.Count-1 do begin
        if Drawn>=64 then Exit;
        Inc(Drawn);
        P:=Plan.EncounterTarget(N,K,Min(Clock,E.Time));
        Color:=RGB(128,117,174);
        if (N+K) mod 3=1 then Color:=RGB(184,133,99);
        if Age<0 then begin U:=EnsureRange((Clock-E.Show)/0.10,0.0,1.0);
          Body(P.X,P.Y,U,0,(N+K) mod 3=1);
        end
        else if Age<0.56 then begin
          // A defeated body is thrown away from the runner, not replaced by dots.
          U:=Age/0.56;
          Kick:=0.80+0.55*Strength+0.12*(K mod 2);
          Lift:=0.32+0.16*Strength;
          X:=P.X+Kick*Age;
          Y:=P.Y-Lift*Age+0.62*Age*Age;
          Spin:=(K mod 2*2-1)*(8+E.Count)*Age;
          Size:=1-Sqr(U);
          Body(X,Y,Size,Spin,(N+K) mod 3=1);
          for Part:=0 to 1 do begin Angle:=Spin+Part*Pi;
            R:=Age*(0.12+0.08*Strength);
            Line(X+Cos(Angle)*R-0.004*(1-U),Y+Sin(Angle)*R,X+Cos(Angle)*R+0.004*(1-U),Y+Sin(Angle)*R,Color,0.006*(1-U));
          end;
          if Age<0.055 then Circle(P.X,P.Y,0.027*(1-Age/0.055),RGB(255,228,149));
        end;
      end;
    end;
  end;

  procedure RapidScenery;
  var
    I,J,A,B,H,Total:Integer;
    V:TRunnerStrike;
    C:TRunnerCut;
    Grip,Tip:TRunnerPoint;
    Age,U,X,Y,Turn,Strength:Double;
    Tint:TColor;
  begin
    A:=Max(0,Plan.StrikeBefore(Clock-0.71));
    B:=Min(Plan.StrikeBefore(Clock+0.90+1E-8),A+63);
    for I:=A to B do begin V:=Plan.Strike[I];
      if Clock<V.Show then Continue;
      C:=Plan.Cut[V.LastCut];
      Age:=Clock-C.Time;
      if Age>=0.56 then Continue;
      Tint:=RGB(128,117,174);
      if I mod 3=1 then Tint:=RGB(184,133,99);
      X:=V.X;
      Y:=V.Y;
      if Age<0 then begin
        Surface.FillRect(Left+(X-0.020-Camera)*Scale,Top+(Y-0.032)*Scale,Left+(X+0.020-Camera)*Scale,Top+(Y+0.032)*Scale,Tint);
        H:=Max(0,Plan.CutBefore(Clock)-V.FirstCut+1);
        Total:=V.LastCut-V.FirstCut+1;
        Surface.FillRect(Left+(X-0.015-Camera)*Scale,Top+(Y-0.025)*Scale,Left+(X+0.015-Camera)*Scale,Top+(Y-0.007)*Scale,RGB(43,56,77));
        Circle(X-0.007,Y-0.016,0.003,RGB(255,146,118));
        Circle(X+0.007,Y-0.016,0.003,RGB(255,146,118));
        for J:=0 to 3 do begin U:=(J+0.5)/4;
          Strength:=1;
          if U<H/Max(1,Total) then Strength:=0.25;
          Line(X-0.013,Y+0.001+J*0.008,X+0.013,Y+0.001+J*0.008,RGB(Round(255*Strength),Round(218*Strength),Round(139*Strength)),0.004);
        end;
      end else begin U:=Age/0.56;
        Strength:=Plan.Step[C.Step].Strength;
        X:=X+(0.8+0.55*Strength)*Age;
        Y:=Y-(0.32+0.16*Strength)*Age+0.62*Age*Age;
        Turn:=(I mod 2*2-1)*11*Age;
        Line(X-Cos(Turn)*0.018*(1-U*U),Y-Sin(Turn)*0.018*(1-U*U),X+Cos(Turn)*0.018*(1-U*U),Y+Sin(Turn)*0.018*(1-U*U),Tint,0.054*(1-U*U));
      end;
    end;
    B:=Plan.CutBefore(Clock);
    A:=Max(Plan.CutBefore(Clock-0.065)+1,B-63);
    for I:=A to B do begin C:=Plan.Cut[I];
      Age:=Clock-C.Time;
      U:=1-Age/0.065;
      Plan.SwordAt(C.Time,Grip,Tip);
      Line(Tip.X-0.008,Tip.Y-0.012,Tip.X+0.008,Tip.Y+0.012,RGB(255,231,171),0.003*U);
      Line(Tip.X-0.010,Tip.Y+0.006,Tip.X+0.010,Tip.Y-0.006,RGB(245,249,219),0.002*U);
    end;
  end;

  procedure SwordScenery;
  var
    A,B,N,Current,Drawn:Integer;
    C:TRunnerCut;
    G,Tip:TRunnerPoint;
    Age,U,R,X,Y,Turn,Kick,Lift,Strength:Double;
    Tint:TColor;
  begin
    if Plan.RecipeVersion>=5 then begin RapidScenery;
      Exit;
    end;
    Current:=Plan.CutBefore(Clock);
    A:=Max(Plan.CutBefore(Clock-0.56)+1,Current-95);
    B:=Min(Plan.CutBefore(Clock+0.90+1E-8),A+191);
    Drawn:=0;
    for N:=A to B do begin C:=Plan.Cut[N];
      if Clock<C.Show then Continue;
      Age:=Clock-C.Time;
      if (C.X+Max(0.0,Age)*1.5<Camera-0.06) or (C.X>Camera+1.88) then Continue;
      if Drawn>=192 then Break;
      Inc(Drawn);
      Strength:=Plan.Step[C.Step].Strength;
      R:=C.Radius;
      X:=C.X;
      Y:=C.Y;
      Turn:=0;
      U:=1;
      Tint:=RGB(128,117,174);
      if N mod 3=1 then Tint:=RGB(184,133,99);
      if Age<0 then begin
        if C.Time>C.Show then U:=EnsureRange((Clock-C.Show)/Min(0.06,C.Time-C.Show),0.0,1.0);
      end else begin
        U:=Age/0.56;
        Kick:=0.80+0.55*Strength+0.12*(N mod 2);
        Lift:=0.32+0.16*Strength;
        X:=X+Kick*Age;
        Y:=Y-Lift*Age+0.62*Age*Age;
        Turn:=(N mod 2*2-1)*11*Age;
        U:=1-Sqr(U);
      end;
      R:=R*U;
      // The saved radius is the real visible body, including dense small targets.
      Circle(X,Y,R,Tint);
      if R>=0.006 then begin
        Line(X-Cos(Turn)*R*0.65,Y-Sin(Turn)*R*0.65,X+Cos(Turn)*R*0.65,Y+Sin(Turn)*R*0.65,RGB(255,221,140),R*0.22);
        Circle(X+Cos(Turn)*R*0.30,Y+Sin(Turn)*R*0.30,R*0.13,RGB(48,66,96));
      end;
      if (Age>=0) and (Age<0.065) then begin
        Plan.SwordAt(C.Time,G,Tip);
        U:=1-Age/0.065;
        Line(Tip.X-0.008,Tip.Y-0.012,Tip.X+0.008,Tip.Y+0.012,RGB(255,230,158),0.003*U);
        Line(Tip.X-0.010,Tip.Y+0.006,Tip.X+0.010,Tip.Y-0.006,RGB(245,249,219),0.002*U);
      end;
    end;
  end;

  procedure DrawLeg(HipX,HipY:Double;const Foot:TRunnerFoot;Rear:Boolean);
  var
    Thigh,Shin,DX,DY,D,A,H,KneeX,KneeY:Double;
    Upper,Lower,Shoe:TColor;
  begin
    Thigh:=0.033;
    Shin:=0.035;
    if Plan.RecipeVersion>=5 then begin Thigh:=0.028;
      Shin:=0.030;
    end;
    DX:=Foot.X-HipX;
    DY:=Foot.Y-HipY;
    D:=Max(0.0001,Sqrt(DX*DX+DY*DY));
    A:=(Sqr(Thigh)-Sqr(Shin)+D*D)/(2*D);
    H:=Sqrt(Max(0.0,Sqr(Thigh)-A*A));
    // Use the forward knee solution on both legs, never a reversed knee.
    KneeX:=HipX+(DX*A+DY*H)/D;
    KneeY:=HipY+(DY*A-DX*H)/D;
    if Rear then begin Upper:=RGB(74,111,142);
      Lower:=RGB(114,148,168);
      Shoe:=RGB(197,128,125);
    end
    else begin Upper:=RGB(99,141,170);
      Lower:=RGB(147,180,191);
      Shoe:=RGB(244,161,144);
    end;
    Line(HipX,HipY,KneeX,KneeY,Upper,0.010);
    Line(KneeX,KneeY,Foot.X,Foot.Y,Lower,0.010);
    // Keep the sole at the existing contact height; round only the upper shoe.
    Line(Foot.X-0.004,Foot.Y,Foot.X+0.010,Foot.Y,RGB(65,96,113),0.008);
    if Scale>=300 then begin
      Line(Foot.X-0.001,Foot.Y-0.002,Foot.X+0.007,Foot.Y-0.002,Shoe,0.006);
      Circle(Foot.X-0.001,Foot.Y-0.002,0.003,Shoe);
      Circle(Foot.X+0.007,Foot.Y-0.002,0.003,Shoe);
      Line(Foot.X-0.003,Foot.Y-0.001,Foot.X+0.009,Foot.Y-0.001,RGB(255,240,212),0.002);
    end;
  end;
  procedure Character;
  var
    Feet,Departure,Landing:TRunnerFeet;
    P,Q0,Q1:TRunnerPoint;
    S:TRunnerStep;
    Index,Side:Integer;
    U,Blend,Tuck,Bob,Bob0,Bob1,HipX,HipY,DX,AirLiftLimit:Double;
    Lean,ChestX,ChestY,HeadX,HeadY,Swing,ArmAngle,AirBlend:Double;
    Arms:array[0..1] of TRunnerArm;
    SwordGrip,SwordTip:TRunnerPoint;
    HasSword:Boolean;
    SwordDX,SwordDY,SwordD,ReachA,ReachH,LegReach,HipHeight,Torso,HeadGap:Double;
    procedure DrawArm(const Arm:TRunnerArm;Rear:Boolean);
    var
      Sleeve,Skin:TColor;
    begin
      if Rear then begin Sleeve:=RGB(72,132,132);
        Skin:=RGB(220,183,151);
      end
      else begin Sleeve:=RGB(82,165,150);
        Skin:=RGB(255,223,190);
      end;
      Line(Arm.ShoulderX,Arm.ShoulderY,Arm.ElbowX,Arm.ElbowY,Sleeve,0.009);
      Circle(Arm.ElbowX,Arm.ElbowY,0.0035,Skin);
      Line(Arm.ElbowX,Arm.ElbowY,Arm.HandX,Arm.HandY,Skin,0.007);
      Circle(Arm.HandX,Arm.HandY,0.0038,Skin);
      if Scale>=300 then Circle(Arm.HandX+0.0007,Arm.HandY-0.0008,0.0010,RGB(255,241,216));
    end;
    procedure DrawFace(X,Y:Double);
    var
      EyeRadius,FaceScale:Double;
      procedure FaceCircle(AX,AY,R:Double;Tint:TColor);
      begin Circle(X+(AX-X)*FaceScale,Y+(AY-Y)*FaceScale,R*FaceScale,Tint);
      end;
      procedure FaceLine(AX,AY,BX,BY:Double;Tint:TColor;Width:Double);
      begin Line(X+(AX-X)*FaceScale,Y+(AY-Y)*FaceScale,X+(BX-X)*FaceScale,Y+(BY-Y)*FaceScale,Tint,Width*FaceScale);
      end;
    begin
      FaceScale:=1;
      if Plan.RecipeVersion>=5 then FaceScale:=1.25;
      // The short ponytail stays above the collar and clear of the running arms.
      FaceCircle(X-0.037,Y-0.003,0.011,RGB(104,81,76));
      FaceCircle(X-0.042,Y+0.009,0.010,RGB(104,81,76));
      FaceCircle(X-0.043,Y+0.017,0.007,RGB(139,104,83));
      FaceCircle(X,Y-0.0015,0.0325,RGB(104,81,76));
      FaceCircle(X,Y,0.031,RGB(255,223,190));
      FaceCircle(X-0.029,Y+0.005,0.0055,RGB(255,223,190));
      FaceCircle(X-0.015,Y-0.021,0.0125,RGB(139,104,83));
      FaceCircle(X+0.003,Y-0.022,0.0115,RGB(139,104,83));
      FaceCircle(X+0.017,Y-0.020,0.010,RGB(139,104,83));
      FaceCircle(X-0.025,Y+0.009,0.008,RGB(139,104,83));
      FaceCircle(X-0.0315,Y-0.0045,0.0042,RGB(226,139,158));
      FaceCircle(X+0.027,Y+0.004,0.0035,RGB(255,223,190));
      if Scale>=300 then begin
        FaceCircle(X-0.006,Y+0.009,0.0037,RGB(244,181,170));
        FaceCircle(X+0.018,Y+0.008,0.0045,RGB(244,181,170));
        FaceCircle(X-0.001,Y-0.0025,0.0033,RGB(73,64,67));
      end;
      // A single clear eye survives small output sizes without enlarging the rig.
      EyeRadius:=Max(0.0038,Min(0.0075,0.7/Max(1.0,Scale)));
      FaceCircle(X+0.013,Y-0.0025,EyeRadius,RGB(73,64,67));
      if Scale>=450 then FaceCircle(X+0.0142,Y-0.0038,0.0011,RGB(255,250,229));
      FaceLine(X+0.004,Y+0.013,X+0.009,Y+0.015,RGB(136,83,80),0.0022);
      FaceLine(X+0.009,Y+0.015,X+0.015,Y+0.012,RGB(136,83,80),0.0022);
    end;
  begin
    HipHeight:=0.068;
    LegReach:=0.066;
    Torso:=0.034;
    HeadGap:=0.047;
    if Plan.RecipeVersion>=5 then begin HipHeight:=0.058;
      LegReach:=0.056;
      Torso:=0.030;
      HeadGap:=0.042;
    end;
    P:=RunnerAt(Clock);
    Tuck:=0;
    if P.Airborne then begin
      Index:=Plan.StepBefore(Clock);
      S:=Plan.Step[Index+1];
      U:=(Clock-S.Takeoff)/(S.Time-S.Takeoff);
      Blend:=Smooth(U);
      Tuck:=Sqr(Sin(Pi*U));
      Q0:=RunnerAt(S.Takeoff);
      Q1:=RunnerAt(S.Time);
      GroundFeet(S.Takeoff,Departure,Bob0);
      GroundFeet(S.Time,Landing,Bob1);
      Bob:=Bob0+(Bob1-Bob0)*Blend;
      // Shorter legs need less lift at the apex, with identical endpoint poses.
      AirLiftLimit:=0.034-0.006*Tuck;
      for Side:=0 to 1 do begin
        Feet[Side].X:=P.X+(Departure[Side].X-Q0.X)*(1-Blend)+(Landing[Side].X-Q1.X)*Blend;
        Feet[Side].Y:=P.Y+(Departure[Side].Y-Q0.Y)*(1-Blend)+(Landing[Side].Y-Q1.Y)*Blend;
        Feet[Side].X:=Feet[Side].X+(Side*2-1)*0.012*Tuck;
        Feet[Side].Y:=Feet[Side].Y-(0.015+Side*0.006)*Tuck;
        // Leave clearance between ankle and hip instead of folding the leg flat.
        Feet[Side].Y:=Max(Feet[Side].Y,P.Y-AirLiftLimit);
      end;
    end else GroundFeet(Clock,Feet,Bob);
    // Let the pelvis follow the feet slightly, especially at a short stone's
    // edge. Keep the head on the planned path and avoid crouching over one foot.
    HipX:=EnsureRange((Feet[0].X+Feet[1].X)/2,P.X-0.024,P.X+0.024);
    // Match the pelvis height to the 0.068 chibi legs. Lower it only as needed
    // to reach either ankle; the continuous maximum also spans foot switches.
    HipY:=P.Y-HipHeight+Bob;
    for Side:=0 to 1 do begin
      DX:=Feet[Side].X-HipX;
      HipY:=Max(HipY,Feet[Side].Y-Sqrt(Max(0.0,Sqr(LegReach)-DX*DX)));
    end;
    // The torso has its own length above the pelvis; it never moves the feet.
    Lean:=0.28-0.06*Tuck;
    ChestX:=HipX+Sin(Lean)*Torso;
    ChestY:=HipY-Cos(Lean)*Torso;
    HeadX:=ChestX+0.005;
    HeadY:=ChestY-HeadGap;
    AirBlend:=0.8*Tuck;
    for Side:=0 to 1 do begin
      // Drive each arm from the opposite foot, then blend to a bent airborne pose.
      Swing:=EnsureRange((Feet[1-Side].X-Feet[Side].X)/0.065,-1.0,1.0);
      ArmAngle:=0.8*Swing*(1-AirBlend)+(0.8+Side*0.1)*AirBlend;
      Arms[Side].ShoulderX:=ChestX+(Side*2-1)*0.0035;
      Arms[Side].ShoulderY:=ChestY+(1-Side)*0.001;
      Arms[Side].ElbowX:=Arms[Side].ShoulderX+Sin(ArmAngle)*0.018;
      Arms[Side].ElbowY:=Arms[Side].ShoulderY+Cos(ArmAngle)*0.018;
      Arms[Side].HandX:=Arms[Side].ElbowX+Sin(ArmAngle+1.65)*0.017;
      Arms[Side].HandY:=Arms[Side].ElbowY+Cos(ArmAngle+1.65)*0.017;
    end;
    HasSword:=Plan.SwordAt(Clock,SwordGrip,SwordTip);
    if HasSword then begin
      // Entry translation affects hero and weapon together, never the hit clocks.
      Q0:=Plan.PositionAt(Clock);
      SwordGrip.X:=SwordGrip.X+P.X-Q0.X;
      SwordTip.X:=SwordTip.X+P.X-Q0.X;
      Arms[1].HandX:=SwordGrip.X;
      Arms[1].HandY:=SwordGrip.Y;
      SwordDX:=SwordGrip.X-Arms[1].ShoulderX;
      SwordDY:=SwordGrip.Y-Arms[1].ShoulderY;
      SwordD:=Max(1E-8,Hypot(SwordDX,SwordDY));
      ReachA:=(Sqr(0.026)-Sqr(0.027)+Sqr(SwordD))/(2*SwordD);
      ReachH:=Sqrt(Max(0.0,Sqr(0.026)-Sqr(ReachA)));
      Arms[1].ElbowX:=Arms[1].ShoulderX+(SwordDX*ReachA-SwordDY*ReachH)/SwordD;
      Arms[1].ElbowY:=Arms[1].ShoulderY+(SwordDY*ReachA+SwordDX*ReachH)/SwordD;
    end;
    // Far limbs, shirt, near limbs, belt and head form separate depth layers.
    DrawLeg(HipX,HipY,Feet[0],True);
    DrawArm(Arms[0],True);
    Line(HipX,HipY-0.002,ChestX,ChestY,RGB(63,118,113),0.026);
    Circle(ChestX,ChestY,0.013,RGB(63,118,113));
    Line(HipX,HipY-0.002,ChestX,ChestY,RGB(120,204,178),0.022);
    Circle(ChestX,ChestY,0.011,RGB(120,204,178));
    Circle(ChestX-0.002,ChestY+0.013,0.0028,RGB(255,238,186));
    DrawLeg(HipX,HipY,Feet[1],False);
    // A short A-line tunic over opaque leggings; the knees remain visible.
    Line(HipX-0.008,HipY-0.001,HipX+0.008,HipY-0.001,RGB(63,118,113),0.008);
    Line(HipX-0.010,HipY+0.003,HipX+0.010,HipY+0.003,RGB(120,204,178),0.007);
    Line(HipX-0.013,HipY+0.007,HipX+0.013,HipY+0.007,RGB(120,204,178),0.007);
    Line(HipX-0.014,HipY+0.010,HipX+0.014,HipY+0.010,RGB(63,118,113),0.003);
    Line(HipX-0.011,HipY-0.002,HipX+0.011,HipY-0.002,RGB(70,119,129),0.007);
    Line(ChestX,ChestY-0.004,HeadX,HeadY+0.023,RGB(255,223,190),0.008);
    DrawArm(Arms[1],False);
    if HasSword then begin
      SwordD:=Max(1E-8,Hypot(SwordTip.X-SwordGrip.X,SwordTip.Y-SwordGrip.Y));
      SwordDX:=(SwordTip.X-SwordGrip.X)/SwordD;
      SwordDY:=(SwordTip.Y-SwordGrip.Y)/SwordD;
      Line(SwordGrip.X-SwordDX*0.012,SwordGrip.Y-SwordDY*0.012,SwordGrip.X,SwordGrip.Y,RGB(112,77,67),0.007);
      Line(SwordGrip.X-SwordDY*0.011,SwordGrip.Y+SwordDX*0.011,SwordGrip.X+SwordDY*0.011,SwordGrip.Y-SwordDX*0.011,RGB(226,188,101),0.004);
      Line(SwordGrip.X,SwordGrip.Y,SwordTip.X,SwordTip.Y,RGB(64,98,117),RUN_SWORD_HALF*2);
      Circle(SwordTip.X,SwordTip.Y,RUN_SWORD_HALF,RGB(64,98,117));
      Line(SwordGrip.X,SwordGrip.Y,SwordTip.X,SwordTip.Y,RGB(227,246,239),0.003);
      Circle(SwordTip.X,SwordTip.Y,0.0015,RGB(227,246,239));
    end;
    DrawFace(HeadX,HeadY);
  end;
begin

  Scale:=Min(Frame.Width/1.8,Frame.Height/1.0);
  Left:=(Frame.Width-1.8*Scale)/2;
  Top:=(Frame.Height-Scale)/2;
  Clock:=0;
  if Plan<>nil then Clock:=Min(Frame.Time,Plan.EndTime);
  Camera:=RUN_SPEED*Clock-0.42;
  if Plan<>nil then Camera:=RUN_SPEED*Min(Clock,Plan.GoalTime)-0.42;
  Background;
  if Plan<>nil then begin
    First:=Plan.FirstPlatform(Camera-0.08);
    for I:=First to Min(Plan.PlatformCount-1,First+255) do begin
      Pad:=Plan.Platform[I];
      if Pad.Left>Camera+1.86 then Break;
      Thickness:=Min(0.055,(Pad.Right-Pad.Left)*0.65);
      Tint:=RGB(53,113,70);
      Line(Max(Pad.Left,Camera-0.03)+Thickness/2,Pad.Y+Thickness/2,Min(Pad.Right,Camera+1.83)-Thickness/2,Pad.Y+Thickness/2,RGB(116,132,112),Thickness);
      Line(Max(Pad.Left,Camera),Pad.Y,Min(Pad.Right,Camera+1.8),Pad.Y,Tint,0.006);
      if Pad.Right-Pad.Left>0.11 then begin
        Line(Max(Pad.Left+0.015,Camera),Pad.Y+0.014,Min(Pad.Right-0.015,Camera+1.8),Pad.Y+0.014,RGB(206,229,156),0.003);
      end;
    end;
    SetPieceScenery;
    EncounterScenery;
    SwordScenery;
    GoalX:=RUN_SPEED*Plan.GoalTime;
    GoalY:=Plan.Step[Plan.Count-1].Y;
    if Plan.GoalTime>0 then begin
      Line(GoalX,GoalY,GoalX,GoalY-0.23,RGB(74,106,102),0.008);
      Line(GoalX,GoalY-0.23,GoalX+0.10,GoalY-0.19,RGB(255,184,91),0.025);
      Line(GoalX+0.10,GoalY-0.19,GoalX,GoalY-0.15,RGB(255,184,91),0.025);
      Age:=Clock-Plan.GoalTime;
      if (Age>=0) and (Age<0.70) then for J:=0 to 15 do begin
        T:=J*2.39996;
        Circle(GoalX+Cos(T)*Age*0.3,GoalY-0.12+Sin(T)*Age*0.25+Age*Age*0.2,0.004,RGB(225,138,66));
      end;
    end;
    Last:=Plan.PulseBefore(Clock);
    First:=Max(0,Last-47);
    for I:=Last downto First do begin
      Pulse:=Plan.Pulse[I];
      Age:=Clock-Pulse.Time;
      if Age>0.30 then Break;
      if (Age>=0) and not Plan.SwordStep(Pulse.Step) then begin
        Circle(RUN_SPEED*Pulse.Time,Plan.Step[Pulse.Step].Y,0.012+Age*0.22,RGB(190,117,40),False);
        for J:=0 to 3 do Circle(RUN_SPEED*Pulse.Time+(J-1.5)*Age*0.12,Plan.Step[Pulse.Step].Y-Age*0.22+Age*Age*0.45,0.003,RGB(64,119,86));
      end;
    end;
    if (Plan.GoalTime>0) and (Frame.Time<Plan.EndTime) then begin
      Character;
    end;
  end;
  // Fixed horizontal stage, letterboxed for portrait/extreme aspect frames.
  if Left>0 then begin
    Surface.Line(Left/2,0,Left/2,Frame.Height,RGB(210,231,228),Left+1);
    Surface.Line(Frame.Width-Left/2,0,Frame.Width-Left/2,Frame.Height,RGB(210,231,228),Left+1);
  end;
  if Top>0 then begin
    Surface.Line(0,Top/2,Frame.Width,Top/2,RGB(210,231,228),Top+1);
    Surface.Line(0,Frame.Height-Top/2,Frame.Width,Frame.Height-Top/2,RGB(210,231,228),Top+1);
  end;
end;
end.
