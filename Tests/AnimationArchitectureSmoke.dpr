program AnimationArchitectureSmoke;
{$APPTYPE CONSOLE}
{$POINTERMATH ON}
uses System.SysUtils,System.Types,System.Classes,System.Hash,System.Math,Vcl.Graphics,
  RhythmAnimation,RhythmImageBank,RhythmRenderSurface,RhythmAudioAnalysis,RhythmAudio,RhythmMotion;
type
  TProbeScene=class(TAnimationScene)
  public
    Prepared,Drawn:TAnimationFrame;
    procedure Prepare(const Frame:TAnimationFrame);override;
    procedure Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);override;
  end;
var Probe:TProbeScene;Renderer:TAnimationRenderer;Image:TBitmap;Audio:TRhythmAudio;
  Analysis:TRhythmAnalysis;PCM:TBytes;Samples:PSmallInt;I,J,Amplitude:Integer;Hash:string;
procedure Require(Value:Boolean;const MessageText:string);
begin if not Value then raise Exception.Create(MessageText);end;
procedure TProbeScene.Prepare(const Frame:TAnimationFrame);
begin Prepared:=Frame;end;
procedure TProbeScene.Draw(Surface:TAnimationRenderSurface;const Frame:TAnimationFrame);
var X:Integer;
begin
  Drawn:=Frame;X:=Round(Frame.Time*17) mod 100;
  Surface.Canvas.Brush.Color:=clAqua;Surface.Canvas.FillRect(Rect(X,20,X+10,30));
end;
function ImageHash:string;
var Stream:TMemoryStream;Bytes:TBytes;Digest:THashSHA2;
begin
  Stream:=TMemoryStream.Create;try Image.SaveToStream(Stream);SetLength(Bytes,Stream.Size);
    Stream.Position:=0;Stream.ReadBuffer(Bytes[0],Length(Bytes));Digest:=THashSHA2.Create;Digest.Update(Bytes);Result:=Digest.HashAsString;
  finally Stream.Free;end;
end;
begin
  Renderer:=nil;Image:=nil;Audio:=nil;
  try
    // A source-free probe proves that the core can be composed without a
    // shooting scene, enemy image catalog or music decoder.
    Probe:=TProbeScene.Create;Renderer:=TAnimationRenderer.Create(Probe,TAnimationImageBank.Create([],0));
    Renderer.UseD2D:=False;Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(320,180);
    Renderer.Render(Image,1.25,0);Hash:=ImageHash;
    Renderer.Render(Image,8.5,1);Renderer.Render(Image,1.25,0);
    Require(Hash=ImageHash,'Absolute-time probe changed after a seek');
    Require((Probe.Prepared.Time=1.25) and (Probe.Drawn.Time=1.25),'Scene did not receive the requested absolute time');
    Renderer.Render(Image,-2,9);
    Require((Probe.Drawn.Time=0) and (Probe.Drawn.Direction=1),'Frame normalization changed');
    Require((Probe.Drawn.Width=320) and (Probe.Drawn.Height=180),'Scene has incorrect viewport');
    Renderer.Render(Image,1.25,0,'',1.5,8,-4);Hash:=ImageHash;
    Renderer.Render(Image,2.5,1);Renderer.Render(Image,1.25,0,'',1.5,8,-4);
    Require(Hash=ImageHash,'Transformed probe changed after a seek');
    FreeAndNil(Renderer);

    // Known PCM onsets check the shared detector and the retained legacy lane
    // and flight adapter. No decoder, file cache, speaker or GUI is used.
    SetLength(PCM,2*RHYTHM_ANALYSIS_RATE*4);Samples:=PSmallInt(PCM);
    for I:=0 to 2*RHYTHM_ANALYSIS_RATE-1 do begin
      Amplitude:=0;
      if ((I>=22050) and (I<24255)) or ((I>=39690) and (I<41895)) or ((I>=57330) and (I<59535)) then Amplitude:=16000;
      Samples[I*2]:=Amplitude;Samples[I*2+1]:=Amplitude;
    end;
    Analysis:=AnalyzeRhythmPCM(PCM,50);Require(Length(Analysis.Accents)=3,'Known PCM did not yield three onsets');
    Require((Abs(Analysis.Accents[0].Time-0.5)<0.011) and (Abs(Analysis.Accents[1].Time-0.9)<0.011) and
      (Abs(Analysis.Accents[2].Time-1.3)<0.011),'Known onset timing changed');
    Audio:=TRhythmAudio.Create;Audio.PCM:=PCM;Audio.Sensitivity:=50;Audio.Detect;
    Require((Audio.Duration=Analysis.Duration) and (Length(Audio.Hits)=Length(Analysis.Accents)),'Legacy analysis shape changed');
    for I:=0 to High(Audio.Hits) do begin
      Require((Audio.Hits[I].Time=Analysis.Accents[I].Time) and (Audio.Hits[I].Strength=Analysis.Accents[I].Strength),'Legacy accents changed');
      J:=(Analysis.Accents[I].HopIndex*73+(Analysis.Accents[I].HopIndex mod 17)*131) mod 997;
      Require(Abs(Audio.Hits[I].Lane-(0.14+J/996.0*0.72))<1E-12,'Legacy lane metadata changed');
      Require(Audio.Hits[I].Flight=ShotFlightTime(Audio.Hits[I].Time,Audio.Hits[I].Lane,Audio.Hits[I].Strength),'Legacy flight metadata changed');
    end;
    Writeln('AnimationArchitectureSmoke passed');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
  Audio.Free;Image.Free;Renderer.Free;
end.
