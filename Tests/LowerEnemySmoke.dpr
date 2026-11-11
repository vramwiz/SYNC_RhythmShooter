program LowerEnemySmoke;
{$APPTYPE CONSOLE}
uses
  RhythmBombPlan in '..\Source\BombAction\RhythmBombPlan.pas',
  RhythmBombScene in '..\Source\BombAction\RhythmBombScene.pas',
  System.SysUtils,System.Math,System.Classes,System.IOUtils,System.JSON,System.Types,System.Hash,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmBarrage,RhythmMotion,RhythmStage,RhythmScene;
var Audio:TRhythmAudio;Plan,RepeatPlan:TArray<TRhythmFlyby>;Enemy:TRhythmFlyby;Schedule:TRhythmStageSchedule;
  P,Q,Again:TRhythmPoint;I,J,Backend,Kind:Integer;Duration,Time,Minimum,Distance:Double;Counts:array[0..2] of Integer;
  LeftCount,RightCount:Integer;Root:TJSONObject;Renderer:TRhythmRenderer;Image:TBitmap;PNG:TPngImage;Folder,ErrorText,Hash:string;
const SampleTimes:array[0..3] of Double=(3.3,8.7,10.5,16.6);
procedure Require(Value:Boolean;const MessageText:string);
begin if not Value then raise Exception.Create(MessageText);end;
function ImageHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Digest:THashSHA2;
begin Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);Stream.Position:=0;Stream.ReadBuffer(Bytes[0],Length(Bytes));Digest:=THashSHA2.Create;Digest.Update(Bytes);Result:=Digest.HashAsString;finally Stream.Free;end;end;
function Synthetic(Seconds:Double):TRhythmAudio;
var N:Integer;
begin
  Result:=TRhythmAudio.Create;Result.Duration:=Seconds;Result.Sensitivity:=50;
  SetLength(Result.Envelope,Ceil(Seconds*100));for N:=0 to High(Result.Envelope) do Result.Envelope[N]:=0.6;
  SetLength(Result.Hits,Max(0,Floor((Seconds-0.5)/0.42)));
  for N:=0 to High(Result.Hits) do begin Result.Hits[N].Time:=0.4+N*0.42;Result.Hits[N].Lane:=0.15+(N mod 7)*0.1;Result.Hits[N].Strength:=0.7;Result.Hits[N].Flight:=ShotFlightTime(Result.Hits[N].Time,Result.Hits[N].Lane,0.7);end;
  Result.UpdateSoundBounds;
end;
begin
  Audio:=nil;Renderer:=nil;Image:=nil;Root:=TJSONObject.Create;
  Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'LowerReview');ForceDirectories(Folder);
  try
    try
      for Kind:=0 to 2 do begin
        case Kind of 0:Duration:=3;1:Duration:=90;else Duration:=175;end;
        Audio:=Synthetic(Duration);Schedule:=StageSchedule(Audio);Plan:=BuildLowerFlybys(Audio);RepeatPlan:=BuildLowerFlybys(Audio);
        Require(Length(Plan)=Length(RepeatPlan),'Plan length is not deterministic');FillChar(Counts,SizeOf(Counts),0);LeftCount:=0;RightCount:=0;Minimum:=100;
        if Kind=0 then Require(Length(Plan)=0,'Very short song spawned unfinished lower traffic');
        for I:=0 to High(Plan) do begin
          Enemy:=Plan[I];Inc(Counts[Ord(Enemy.Route)]);if Enemy.FromLeft then Inc(LeftCount) else Inc(RightCount);
          Require((Enemy.Finish<=Audio.SoundEnd-0.349) and (Enemy.Finish<Schedule.ClearTime),'Lower traffic survives song clear');
          Require((Enemy.Launch=RepeatPlan[I].Launch) and (Enemy.Finish=RepeatPlan[I].Finish) and (Enemy.FromLeft=RepeatPlan[I].FromLeft) and (Enemy.Route=RepeatPlan[I].Route) and (Enemy.Lane=RepeatPlan[I].Lane) and (Enemy.Phase=RepeatPlan[I].Phase) and (Enemy.Variant=RepeatPlan[I].Variant) and (Enemy.Size=RepeatPlan[I].Size),'Plan contents changed');
          Require(FlybyAt(Enemy,Enemy.Launch).Y>1,'Traffic does not enter from below');Require(FlybyAt(Enemy,Enemy.Finish).Y<0,'Traffic never exits the front');
          P:=FlybyAt(Enemy,Enemy.Launch);
          for J:=0 to Ceil((Enemy.Finish-Enemy.Launch)*240) do begin
            Time:=Min(Enemy.Finish,Enemy.Launch+J/240);Q:=FlybyAt(Enemy,Time);Again:=FlybyAt(Enemy,Time);
            Require((Q.X=Again.X) and (Q.Y=Again.Y),'Random access position changed');Require(Hypot(Q.X-P.X,Q.Y-P.Y)<0.015,'Traffic teleported');
            Require(Q.Y<=P.Y+1E-12,'Lower traffic reverses unexpectedly');P:=Q;
            Again:=StagePoint(Time,Schedule.EntryEnd,Schedule.ExitStart,Schedule.ExitEnd,Schedule.HoldTime);
            Distance:=Hypot(Q.X-Again.X,Q.Y-Again.Y);Minimum:=Min(Minimum,Distance);
          end;
        end;
        if Kind>0 then begin Require((Counts[1]>10) and (Counts[2]>5) and (LeftCount>10) and (RightCount>10),'Routes or side order lack variety');Require(Minimum>0.105,'Lower traffic intersects the player corridor');end;
        Root.AddPair('count_'+IntToStr(Kind),TJSONNumber.Create(Length(Plan)));Root.AddPair('edgeCount_'+IntToStr(Kind),TJSONNumber.Create(Counts[1]));Root.AddPair('sweepCount_'+IntToStr(Kind),TJSONNumber.Create(Counts[2]));Root.AddPair('minimumNormalizedDistance_'+IntToStr(Kind),TJSONNumber.Create(Minimum));FreeAndNil(Audio);
      end;
      Audio:=Synthetic(90);for I:=2000 to High(Audio.Envelope) do Audio.Envelope[I]:=0;SetLength(Audio.Hits,40);Audio.UpdateSoundBounds;
      for Enemy in BuildLowerFlybys(Audio) do Require(Enemy.Finish<Audio.SoundEnd,'Silent tail contains lower traffic');
      FreeAndNil(Audio);Audio:=TRhythmAudio.Create;Audio.Duration:=90;Audio.UpdateSoundBounds;Require(Length(BuildLowerFlybys(Audio))=0,'Silent song has lower traffic');FreeAndNil(Audio);
      Audio:=Synthetic(90);Renderer:=TRhythmRenderer.Create;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(1280,720);
      for Backend:=0 to 1 do begin
        Renderer.UseD2D:=Backend=1;
        for I:=0 to High(SampleTimes) do begin
          Renderer.Render(Image,Audio,SampleTimes[I],0);Require(Renderer.LastUsedD2D=(Backend=1),'Requested render backend unavailable');Hash:=ImageHash;
          PNG:=TPngImage.Create;try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Format('lower-%d-backend%d.png',[I,Backend])));finally PNG.Free;end;
          Renderer.Render(Image,Audio,Audio.SoundEnd+2,0);Renderer.Render(Image,Audio,SampleTimes[I],1);Renderer.Render(Image,Audio,SampleTimes[I],0);
          Require(Hash=ImageHash,'Lower traffic changed after clear seek or direction switch');
        end;
      end;
      Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    TFile.WriteAllText(TPath.Combine(Folder,'lower-enemy-smoke.json'),Root.ToJSON,TEncoding.UTF8);Writeln(Root.ToJSON);
  finally Audio.Free;Image.Free;Renderer.Free;Root.Free;end;
  if ErrorText<>'' then Halt(1);
end.
