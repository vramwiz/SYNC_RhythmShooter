program TrapGimmickSmoke;
{$APPTYPE CONSOLE}
// 実在するU字のくぼみ・片壁・頭上接触・可動足場・保存復元を確認する。再生やGUI操作はしない。
uses System.SysUtils,System.Math,System.IOUtils,System.Hash,System.Generics.Collections,System.Generics.Defaults,
  RhythmAudio,RhythmAudioCache,RhythmTrapPlan,RhythmTrapGimmicks,RhythmTrapBuild,RhythmTrapCodec,
  RhythmPlanRef,RhythmStyles;
var Audio,Cold:TRhythmAudio;Plan,Restored:TTrapPlan;G:TTrapGimmick;Kind:TTrapAvoidance;
  Beats:TArray<Double>;Floors:TList<TTrapPlatform>;M:TTrapMove;F:TTrapPlatform;Q:TTrapObstacle;
  Ref:TRhythmPlanRef;I,J,K,CaseIndex,Checks,SafeSlots,ExpectedSlots:Integer;
  Tempo,Base,Start,At,EndX,Step,Gap,PreviousFall,FloorY:Double;
  Origin,A,B:TTrapPoint;Wall,Before,After,Body:TTrapBox;Folder,Source:string;
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
      PreviousFall:=1E6;
      for I:=0 to High(Beats) do begin Beats[I]:=(I+1)*Tempo;Audio.Hits[I].Time:=Beats[I];Audio.Hits[I].Strength:=0.7;end;
      Start:=Beats[3];Origin:=TrapPoint(Start*TrapWalkSpeed,Base);
      for Kind:=taFeintFloor to High(TTrapAvoidance) do begin
        if not TrapPatternEnabled(Kind) then begin
          Need(not MakeTrapGimmick(Kind,Beats,Start,55,Audio.Duration,Origin,CaseIndex mod 3,G),
            'Removed floor-bobbing gimmick was generated');Continue;
        end;
        Need(MakeTrapGimmick(Kind,Beats,Start,55,Audio.Duration,Origin,CaseIndex mod 3,G),'Feasible gimmick did not build');
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
        if Kind in [taRoofShelters,taRoofNarrow,taRoofLastGap] then begin
          ExpectedSlots:=3-Ord(Kind)+Ord(taRoofShelters);SafeSlots:=0;
          Need(G.Roofs[0].Settle-G.Roofs[0].Trigger<PreviousFall,'Late roof does not descend faster');
          PreviousFall:=G.Roofs[0].Settle-G.Roofs[0].Trigger;
          for I:=0 to High(G.Roofs) do begin
            F:=G.Roofs[I];Need((F.Reveal=0) and F.Solid(0,Audio.Duration),'Roof does not exist before activation');
            SameBox(F.CeilingBoundsAt(0),F.CeilingBoundsAt(F.Recover+0.1));
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
        Audio.Key:=THashSHA2.GetHashString('gimmick-'+IntToStr(CaseIndex)+'-'+IntToStr(Ord(Kind)));
        Ref:=NewPlanRef(Audio.Key,50,0,rsTrapAction,1);Ref.SourceRevision:=Audio.SourceRevision;
        SaveTrapPlan(Plan,Audio,Ref);Cold:=LoadTrapAudio(Ref,Source,0);Restored:=LoadTrapPlan(Ref,Cold,0);
        Need(Length(Cold.PCM)=0,'Gimmick restore used PCM');
        for J:=0 to 79 do begin At:=Plan.GoalTime*((J*37) mod 80)/80;A:=Plan.Position(At);B:=Restored.Position(At);
          Need((A.X=B.X) and (A.Y=B.Y),'Saved moving-platform or head-impact position changed');
          for I:=0 to High(Plan.Obstacles) do SameBox(Plan.Obstacles[I].BoundsAt(At),Restored.Obstacles[I].BoundsAt(At));
          for I:=0 to High(Plan.Platforms) do SameBox(Plan.Platforms[I].BoundsAt(At),Restored.Platforms[I].BoundsAt(At));
          for I:=0 to High(Plan.Ceilings) do SameBox(Plan.Ceilings[I].CeilingBoundsAt(At),Restored.Ceilings[I].CeilingBoundsAt(At));
        end;
        Writeln('GIMMICK PASS case=',CaseIndex,' kind=',Ord(Kind),' moves=',Length(G.Moves));
        FreeAndNil(Restored);FreeAndNil(Cold);FreeAndNil(Plan);
      end;
    end;
    Writeln('GIMMICKS PASS checks=',Checks,' no GUI, no audio playback');
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  Restored.Free;Cold.Free;Plan.Free;Floors.Free;Audio.Free;
end.
