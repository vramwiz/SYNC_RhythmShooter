program TrapGimmickSmoke;
{$APPTYPE CONSOLE}
// 実在するU字のくぼみ・片壁・頭上接触・可動足場・保存復元を確認する。再生やGUI操作はしない。
uses System.SysUtils,System.Math,System.IOUtils,System.Hash,System.Generics.Collections,System.Generics.Defaults,
  RhythmAudio,RhythmAudioCache,RhythmTrapPlan,RhythmTrapGimmicks,RhythmTrapBuild,RhythmTrapCodec,
  RhythmPlanRef,RhythmStyles;
var Audio,Cold:TRhythmAudio;Plan,Restored:TTrapPlan;G:TTrapGimmick;Kind:TTrapAvoidance;
  Beats:TArray<Double>;Floors:TList<TTrapPlatform>;M:TTrapMove;F:TTrapPlatform;Q:TTrapObstacle;
  Ref:TRhythmPlanRef;I,J,K,CaseIndex,Checks,SafeSlots,ExpectedSlots,RoofRouteIndex,SafeIndex,RetreatEntries,WaitingEntries:Integer;
  Tempo,Base,Start,At,EndX,Step,Gap,PreviousFall,FloorY,HighestLow,ExitY:Double;
  Origin,A,B:TTrapPoint;Wall,Before,After,Body:TTrapBox;Folder,Source:string;
  UsedSlots:set of 0..2;Threatened:Boolean;Corners:TTrapCorners;Machines,Backsteps:Integer;
procedure Need(Valid:Boolean;const Why:string);
begin if not Valid then raise Exception.Create(Why);Inc(Checks);end;
procedure SameBox(const A,B:TTrapBox);
begin Need((A.Left=B.Left) and (A.Right=B.Right) and (A.Bottom=B.Bottom) and (A.Top=B.Top),
  'Saved machinery or platform changed its physical shape');end;
begin
  Audio:=nil;Cold:=nil;Plan:=nil;Restored:=nil;Floors:=nil;Checks:=0;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Source:=TPath.Combine(Folder,'gimmicks.identity');TFile.WriteAllText(Source,'Gimmick geometry, no playback.',TEncoding.UTF8);
    Audio:=TRhythmAudio.Create;Audio.Source:=Source;Audio.SourceRevision:=AudioSourceStamp(Source);
    Audio.Duration:=60.25;Audio.SoundEnd:=60;Audio.Sensitivity:=50;Floors:=TList<TTrapPlatform>.Create;
    for CaseIndex:=0 to 5 do begin
      Tempo:=0.4;if Odd(CaseIndex) then Tempo:=0.5;Base:=0;
      if CaseIndex in [2,3] then Base:=0.7 else if CaseIndex>=4 then Base:=-0.55;
      SetLength(Beats,Floor(60/Tempo));SetLength(Audio.Hits,Length(Beats));
      for I:=0 to High(Beats) do begin Beats[I]:=(I+1)*Tempo;Audio.Hits[I].Time:=Beats[I];Audio.Hits[I].Strength:=0.7;end;
      Start:=Beats[3];Origin:=TrapPoint(Start*TrapWalkSpeed,Base);
      UsedSlots:=[];RetreatEntries:=0;WaitingEntries:=0;
      for RoofRouteIndex:=0 to 7 do begin
      PreviousFall:=1E6;
      for Kind:=taFeintFloor to High(TTrapAvoidance) do begin
        if (RoofRouteIndex>0) and not (Kind in [taRoofShelters,taRoofNarrow,taRoofLastGap]) then Continue;
        if not TrapPatternEnabled(Kind) then begin
          Need(not MakeTrapGimmick(Kind,Beats,Start,55,Audio.Duration,Origin,CaseIndex mod 3,G),
            'Removed floor-bobbing gimmick was generated');Continue;
        end;
        Need(TrapGimmickFits(Kind,Beats,Start,55,CaseIndex mod 3,RoofRouteIndex),'Feasible gimmick schedule did not fit');
        Need(MakeTrapGimmick(Kind,Beats,Start,55,Audio.Duration,Origin,CaseIndex mod 3,G,RoofRouteIndex),'Feasible gimmick did not build');
        Plan:=TTrapPlan.Create;Plan.Duration:=Audio.Duration;Plan.Theme:=tsCave;
        SetLength(Plan.Moves,Length(G.Moves)+2);M:=Default(TTrapMove);M.Start:=0;M.Finish:=Start;M.Cue:=Start;
        M.Origin:=TrapPoint(0,Base);M.Target:=Origin;M.Kind:=tmRun;M.Landing:=True;M.LandSynced:=True;M.CueSynced:=True;M.Pattern:=18;
        Plan.Moves[0]:=M;for I:=0 to High(G.Moves) do Plan.Moves[I+1]:=G.Moves[I];
        M:=Default(TTrapMove);M.Start:=G.Moves[High(G.Moves)].Finish;M.Finish:=M.Start+1;M.Cue:=M.Finish;
        M.Origin:=G.Moves[High(G.Moves)].Target;M.Target:=TrapPoint(M.Origin.X+TrapWalkSpeed,Base);
        M.Kind:=tmRun;M.Landing:=True;M.Pattern:=18;Plan.Moves[High(Plan.Moves)]:=M;
        Plan.GoalTime:=M.Finish;Plan.GoalX:=M.Target.X;EndX:=M.Origin.X;
        Floors.Clear;F:=Default(TTrapPlatform);F.Left:=-8;F.Right:=Origin.X;F.Y:=Base;F.EndY:=Base;F.Move:=-1;F.Finish:=Audio.Duration;
        for I:=0 to High(G.Floors) do if G.Floors[I].Motion=pmFeint then F.Right:=G.Floors[I].Left;
        Floors.Add(F);Floors.AddRange(G.Floors);F.Left:=EndX;F.Right:=Plan.GoalX+8;Floors.Add(F);
        Floors.Sort(TComparer<TTrapPlatform>.Construct(function(const A,B:TTrapPlatform):Integer
          begin Result:=CompareValue(A.Left,B.Left);if Result=0 then Result:=CompareValue(A.Y,B.Y);end));
        Plan.Platforms:=Floors.ToArray;Floors.Clear;F:=Default(TTrapPlatform);
        F.Left:=-8;F.Right:=Plan.GoalX+8;F.Y:=6.6;F.EndY:=6.6;F.Move:=-1;F.Finish:=Audio.Duration;
        if Length(G.Roofs)=0 then Floors.Add(F)
        else begin
          F.Right:=G.Roofs[0].Left;Floors.Add(F);Floors.AddRange(G.Roofs);
          F.Left:=G.Roofs[High(G.Roofs)].Right;F.Right:=Plan.GoalX+8;Floors.Add(F);
        end;
        Plan.Ceilings:=Floors.ToArray;
        Plan.Obstacles:=Copy(G.Traps);for I:=0 to High(Plan.Obstacles) do Inc(Plan.Obstacles[I].Move);
        ValidateTrapPlan(Plan,nil);
        case Kind of
          taSideSpears:begin
            Machines:=0;
            for Q in G.Traps do if Q.Kind=tkSideSpear then begin
              Inc(Machines);Before:=Q.BoundsAt(Q.Fire);After:=Q.BoundsAt(Q.Finish);
              Need((Before.Left=Before.Right) and (After.Left=After.Right),'Spear does not retract into its wall');
              Wall:=Q.BoundsAt(Q.Cue);Need(Abs(Wall.Right-Wall.Left-Q.W)<1E-8,'Spear does not reach its full length');
              Need(((Machines=1) and (Q.Power=1)) or ((Machines=2) and (Q.Power=-1)),'Spears do not alternate from opposite walls');
            end;
            Need(Machines=2,'Missing paired side spears');
          end;
          taAlternatingPresses:begin
            Machines:=0;At:=-1;
            for Q in G.Traps do if Q.Kind=tkPress then begin
              Inc(Machines);Need(Q.Cue>At,'Presses do not strike in sequence');At:=Q.Cue;
              Need(Abs(Q.BoundsAt(Q.Cue).Bottom-Base)<1E-8,'Press fails to strike the floor');
              Need(Q.BoundsAt(0).Bottom>Base+TrapStandingHeight+0.1,'Raised press blocks the passage');
              SameBox(Q.BoundsAt(0),Q.BoundsAt(Q.Finish));
            end;
            Need(Machines=3,'Missing large alternating presses');
          end;
          taFlipPit:begin
            Machines:=0;
            for F in G.Floors do if F.Motion=pmHinge then begin
              Inc(Machines);Corners:=F.CornersAt(F.Settle);
              Need((Abs(Corners[1].X-Corners[0].X)<1E-8) and (Corners[1].Y-Corners[0].Y>2.9),'Floor does not rotate into a wall');
              Need(F.Solid(F.Settle,Audio.Duration),'Flipped wall vanishes');
              Need(G.Moves[1].Start<F.Trigger,'Floor flips before the escape jump starts');
            end;
            Need((Machines=1) and (Length(G.Traps)>=4),'Rotating floor has no spike pit');
          end;
          taCeilingLift:begin
            Machines:=0;Backsteps:=0;ExitY:=-1000;At:=-1;
            for F in G.Floors do begin
              if F.Motion=pmNeedleLift then begin
                Inc(Machines);Need(F.Right-F.Left>9.0,'Needle lift floor is too narrow');
                Need(F.Start>=At,'Lift stage lifetimes overlap');At:=F.Finish;
                if F.DX=0 then Need(Abs(F.BoundsAt(F.Recover).Top-Base)<1E-8,'Lift does not descend between shelters')
                else Need(Abs(F.BoundsAt(F.Recover).Top-Base-TrapNeedleLiftHeight)<1E-8,'Final lift does not hold the exit height');
                for Q in G.Traps do if Q.Kind=tkCeilingNeedles then
                  Need(F.BoundsAt(F.Settle).Top+TrapStandingHeight>Q.Y,'Standing outside a ceiling gap is harmless');
              end;
              if Abs(F.Left-Origin.X-10.5)<1E-8 then ExitY:=F.Y;
            end;
            Need((Machines=4) and (ExitY-Base>2.1),'Exit does not require riding the floor');
            Need(Length(G.Traps)=4,'Ceiling needles are not divided by shelter gaps');
            for F in G.Roofs do if F.Y>Base+4.0 then Inc(Backsteps);
            Need(Backsteps=4,'Three ceiling refuges and the clear final section are missing');
            for M in G.Moves do begin
              if M.Kind=tmRide then for J:=0 to 40 do begin
                At:=M.Start+(M.Finish-M.Start)*J/40;A:=M.Position(At);
                Need(Plan.FloorSupports(A.X-TrapHalfWidth,A.X+TrapHalfWidth,A.Y,At),'Player slips through the oscillating ground');
                for Q in G.Traps do Need(Plan.Clearance(Q,At)>=0.10-1E-8,'Lift carries player into ceiling needles');
              end;
              if M.Kind=tmStop then Need(M.Origin.X<Origin.X+10.5,'Player idles after reaching the exit');
            end;
            M:=G.Moves[High(G.Moves)-1];Need((M.Kind=tmJump) and (M.Origin.Y>Base+1.5),'Exit jump does not start on the raised floor');
            Body:=Plan.PlayerBounds(M.Start);
            for Q in G.Traps do Need((Q.X+Q.W*0.5<Body.Left) or (Q.X-Q.W*0.5>Body.Right),'Exit jump starts beneath a ceiling needle');
          end;
          taClosingDoors:begin
            Machines:=0;At:=-1;
            for Q in G.Traps do if Q.Kind=tkClosingDoor then begin
              Inc(Machines);Need(Q.Cue>At,'Doors do not close in sequence');At:=Q.Cue;
              Need(Abs(Q.BoundsAt(Q.Cue).Bottom-Base)<1E-8,'Door does not reach the floor');
              SameBox(Q.BoundsAt(Q.Cue),Q.BoundsAt(Audio.Duration));
              A:=Plan.Position(Q.Cue);Need(A.X-TrapHalfWidth>Q.X+Q.W*0.5,'Door closes before the player passes');
            end;
            Need(Machines=3,'Missing closing doors');
          end;
          taFireChase:begin
            Machines:=0;Backsteps:=0;
            for Q in G.Traps do if Q.Kind=tkFireJet then begin
              Inc(Machines);Need(not Q.Dangerous(Q.Finish),'Extinguished fire is still dangerous');
              Need(Q.BoundsAt(Q.Cue).Top>Base+2.0,'Fire does not rise into a column');
            end;
            for M in G.Moves do if M.Target.X<M.Origin.X then begin
              Inc(Backsteps);Need(M.Finish=G.Traps[High(G.Traps)].Cue,'Retreat is not timed to the last fire column');
            end;
            Need((Machines=3) and (Backsteps=1),'Fire chase lacks its final retreat');
          end;
        end;
        if Kind in [taRoofShelters,taRoofNarrow,taRoofLastGap] then begin
          HighestLow:=-1000;ExitY:=-1000;Machines:=0;
          for F in G.Floors do begin
            if F.Motion=pmRoofRise then begin
              Inc(Machines);HighestLow:=Max(HighestLow,F.BoundsAt(0).Top);
              Need(Abs(F.BoundsAt(F.Settle).Top-F.Y-TrapRoofBedRise)<1E-8,'Basin floor does not rise after sheltering');
              Need(F.Trigger=G.Roofs[0].Release,'Floor starts rising before the roof opens');
            end;
            if Abs(F.Left-Origin.X-10.35)<1E-8 then ExitY:=F.Y;
          end;
          Need((Machines=6) and (ExitY-HighestLow>2.1+0.20),'Player can bypass the shelter through the right exit');
          Need(Abs(G.Moves[High(G.Moves)].Target.Y-Base)<1E-8,'Basin leaves the following course raised');
          for M in G.Moves do begin
            if M.Finish<=G.Roofs[0].Recover then
              Need(Max(M.Origin.X,M.Target.X)+TrapHalfWidth<Origin.X+10.35,'Player escapes before sheltering and rising');
            if M.Kind=tmRide then for J:=0 to 30 do begin
              At:=M.Start+(M.Finish-M.Start)*J/30;A:=M.Position(At);
              Need(Plan.FloorSupports(A.X-TrapHalfWidth,A.X+TrapHalfWidth,A.Y,At),'Sheltering player does not rise with the floor');
            end;
          end;
          ExpectedSlots:=3-Ord(Kind)+Ord(taRoofShelters);SafeSlots:=0;
          Need(G.Roofs[0].Settle-G.Roofs[0].Trigger<PreviousFall,'Late roof does not descend faster');
          PreviousFall:=G.Roofs[0].Settle-G.Roofs[0].Trigger;
          for I:=0 to High(G.Roofs) do begin
            F:=G.Roofs[I];Need((F.Reveal=0) and F.Solid(0,Audio.Duration),'Roof does not exist before activation');
            Before:=F.CeilingBoundsAt(0);After:=F.CeilingBoundsAt(F.Recover+0.1);
            Need((Before.Left=After.Left) and (Before.Right=After.Right) and
              (Abs(After.Bottom-Before.Bottom-TrapRoofBedRise)<1E-8),'Roof recovery does not clear the raised ground');
            Wall:=F.CeilingBoundsAt(F.Settle);FloorY:=-1000;
            for K:=0 to High(G.Floors) do if (G.Floors[K].Left<=(Wall.Left+Wall.Right)*0.5) and
              (G.Floors[K].Right>=(Wall.Left+Wall.Right)*0.5) then FloorY:=G.Floors[K].Y;
            Need(FloorY>-100,'Roof tooth has no matching floor step');Gap:=Wall.Bottom-FloorY;
            if Gap>=TrapStandingHeight+0.12 then begin
              Inc(SafeSlots);Need(Wall.Right-Wall.Left>=TrapHalfWidth*2+0.20,'Refuge is too narrow for a body');
              if Kind=taRoofLastGap then Need(Wall.Right-Wall.Left<=1.0,'Last refuge is not narrow');
            end else Need(Abs(Gap-0.10)<1E-8,'Roof and floor steps fail to mesh');
          end;
          Need(SafeSlots=ExpectedSlots,'Wrong number of surviving refuges');
          Body:=Plan.PlayerBounds(G.Roofs[0].Settle);
          SafeIndex:=Round(((Body.Left+Body.Right)*0.5-Origin.X-3.15)/3.2);
          Need(InRange(SafeIndex,0,2),'Player did not enter a refuge');Include(UsedSlots,SafeIndex);
          for M in G.Moves do if M.Start=G.Roofs[0].Trigger then begin
            if M.Target.X<M.Origin.X then begin
              Inc(RetreatEntries);Threatened:=False;
              Before.Left:=M.Origin.X-TrapHalfWidth;Before.Right:=M.Origin.X+TrapHalfWidth;
              Before.Bottom:=M.Origin.Y+0.035;Before.Top:=M.Origin.Y+TrapStandingHeight;
              for F in G.Roofs do if TrapOverlap(Before,F.CeilingBoundsAt(F.Settle)) then Threatened:=True;
              Need(Threatened,'Retreat starts outside the approaching roof instead of escaping it');
            end;
            if M.Kind=tmStop then Inc(WaitingEntries);
          end;
          for F in G.Roofs do begin
            Wall:=F.CeilingBoundsAt(F.Settle);
            Need(not TrapOverlap(Body,Wall),'Player is crushed in the designated refuge');
          end;
        end;
        if Kind in [taCrushSlot,taCrushReverse,taCrushHop,taCrushFeint] then begin
          Need(Length(Plan.Obstacles)=1,'More than one side of the U is moving');Q:=Plan.Obstacles[0];
          Need((Q.Reveal=0) and (Q.Fire=G.Moves[0].Finish) and (Q.Fire>Start),'Wall starts before entering the U');
          Before:=Q.BoundsAt(0);After:=Q.BoundsAt(Audio.Duration);SameBox(Before,After);
          Need((Abs(Before.Top-Before.Bottom-Q.H)<1E-8) and Q.Dangerous(0) and Q.Dangerous(Audio.Duration),
            'Wall vanishes before or after activation');
          Need(Plan.FloorSupports(Origin.X+0.5,Origin.X+6.8,Base-0.8,0) and
            Plan.FloorSupports(Origin.X-3.5,Origin.X+0.5,Base,0) and
            Plan.FloorSupports(Origin.X+6.8,Origin.X+9.0,Base,0),'U-shaped terrain does not exist beforehand');
          Wall:=Q.BoundsAt(Q.Cue);
          SameBox(Wall,Q.BoundsAt(Q.Cue+Min(0.05,(Q.Finish-Q.Cue)*0.10)));
          if Kind=taCrushSlot then Need(Abs(Origin.X+6.8-Wall.Right-0.86)<1E-8,'Right refuge is not one-person wide');
          if Kind=taCrushReverse then Need(Abs(Wall.Left-Origin.X-0.5-0.86)<1E-8,'Left refuge is not one-person wide');
          if Kind=taCrushHop then begin
            At:=(Q.Fire+Q.Cue)*0.5;Wall:=Q.BoundsAt(At);Body:=Plan.PlayerBounds(At);
            Need((Body.Left<Wall.Right) and (Body.Right>Wall.Left) and (Body.Bottom>Wall.Top+0.10),
              'Jump avoidance did not pass above the approaching wall');
          end;
          if Kind=taCrushFeint then begin
            Body:=Plan.PlayerBounds(Q.Cue);Need(Abs(Wall.Left-Body.Right-0.11)<1E-8,'Wall feint does not stop just short');
            A:=Plan.Position(Q.Fire);B:=Plan.Position(Q.Finish);Need((A.X=B.X) and (A.Y=B.Y),'Wall feint unnecessarily moves the player');
          end;
        end;
        for F in Plan.Platforms do begin
          if F.Motion=pmDrop then begin
            Need(F.BoundsAt(F.Trigger+0.12).Top<F.Y-0.65,'Collapse happens too late');
            Need((F.Right-F.Left>2.9) and (F.BoundsAt(0).Bottom<F.Y-6),'Collapse is a thin, isolated warning tile');
          end;
          Need(F.Motion<>pmFeint,'Removed sinking-and-returning floor is still present');
          if (F.Motion=pmReveal) and (F.Reveal>0) then Need(not F.Solid(F.Reveal-0.001,Plan.Duration),'Hidden slab appeared early');
        end;
        for M in Plan.Moves do begin
          if M.Kind=tmHeadBump then begin
            A:=M.Position(M.Cue);B:=M.Position(M.Cue+0.03);Need(B.Y<A.Y,'Head impact did not reverse the jump');
          end;
          Step:=(M.Finish-M.Start)/10000;
          for J:=0 to 30 do begin
            At:=M.Start+(M.Finish-M.Start-Step)*J/30;A:=M.Position(At);B:=M.Position(At+Step);
            Need(Abs(B.X-A.X)/Step<=TrapWalkSpeed+1E-7,'Instantaneous horizontal speed exceeds normal walking');
          end;
        end;
        Audio.Key:=THashSHA2.GetHashString('gimmick-'+IntToStr(CaseIndex)+'-'+IntToStr(Ord(Kind))+'-'+IntToStr(RoofRouteIndex));
        Ref:=NewPlanRef(Audio.Key,50,0,rsTrapAction,1);Ref.SourceRevision:=Audio.SourceRevision;
        SaveTrapPlan(Plan,Audio,Ref);Cold:=LoadTrapAudio(Ref,Source,0);Restored:=LoadTrapPlan(Ref,Cold,0);
        Need(Length(Cold.PCM)=0,'Gimmick restore used PCM');
        for J:=0 to 79 do begin At:=Plan.GoalTime*((J*37) mod 80)/80;A:=Plan.Position(At);B:=Restored.Position(At);
          Need((A.X=B.X) and (A.Y=B.Y),'Saved moving-platform or head-impact position changed');
          for I:=0 to High(Plan.Obstacles) do SameBox(Plan.Obstacles[I].BoundsAt(At),Restored.Obstacles[I].BoundsAt(At));
          for I:=0 to High(Plan.Platforms) do SameBox(Plan.Platforms[I].BoundsAt(At),Restored.Platforms[I].BoundsAt(At));
          for I:=0 to High(Plan.Ceilings) do SameBox(Plan.Ceilings[I].CeilingBoundsAt(At),Restored.Ceilings[I].CeilingBoundsAt(At));
        end;
        Writeln('GIMMICK PASS case=',CaseIndex,' kind=',Ord(Kind),' route=',RoofRouteIndex,' moves=',Length(G.Moves));
        FreeAndNil(Restored);FreeAndNil(Cold);FreeAndNil(Plan);
      end;
      end;
      Need(UsedSlots=[0,1,2],'Roof refuges are biased toward one side');
      Need((RetreatEntries>0) and (WaitingEntries>0),'Roof lacks backward or stationary avoidance');
    end;
    Writeln('GIMMICKS PASS checks=',Checks,' no GUI, no audio playback');
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  Restored.Free;Cold.Free;Plan.Free;Floors.Free;Audio.Free;
end.
