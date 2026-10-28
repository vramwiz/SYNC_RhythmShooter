program DesignSmoke;
{$APPTYPE CONSOLE}
{$POINTERMATH ON}
uses Winapi.Windows,System.SysUtils,System.Classes,System.IOUtils,System.JSON,System.Hash,System.Math,System.Diagnostics,
  Vcl.Graphics,RhythmPaths,RhythmAudio,RhythmScene,RhythmSettings,RhythmDesignTypes,RhythmDesignImages,
  RhythmDesignRequest,RhythmCodexClient;
var Folder,SpritePath,BackgroundPath,OriginalHash,DefaultHash,CustomHash,ErrorText,OldExe:string;
  Root,Results:TJSONObject;State,Loaded,Saved:TRhythmSettings;Bitmap,Decoded,Frame:Vcl.Graphics.TBitmap;
  Renderer:TRhythmRenderer;Audio:TRhythmAudio;P:PByte;I,X,Y,Direction,Checks:Integer;Info:TRhythmDesignInfo;
  Request:TRhythmDesignRequest;Imported:TRhythmDesign;
procedure Require(Value:Boolean;const Text:string);
begin Inc(Checks);if not Value then raise Exception.Create(Text);end;
function FrameHash:string;
var S:TMemoryStream;Bytes:TBytes;Hash:THashSHA2;
begin S:=TMemoryStream.Create;try Frame.SaveToStream(S);SetLength(Bytes,S.Size);S.Position:=0;S.ReadBuffer(Bytes[0],Length(Bytes));Hash:=THashSHA2.Create;Hash.Update(Bytes);Result:=Hash.HashAsString;finally S.Free;end;end;
procedure Transport(const Mode:string;Expected:Boolean);
var Job:TRhythmCodexJob;Watch:TStopwatch;Req:TRhythmDesignRequest;Candidate:TRhythmDesign;Unchanged:string;
begin
  Req:=NewDesignRequest(6,State.Designs[6]);Unchanged:=State.ToJSON;
  SetEnvironmentVariable('RHYTHM_MOCK_CASE',PChar(Mode));SetEnvironmentVariable('RHYTHM_MOCK_IMAGE',PChar(BackgroundPath));
  Job:=TRhythmCodexJob.CreateImage(Req.Prompt,[],Req.Directory);
  try
    Job.BeginRun;Watch:=TStopwatch.StartNew;
    while not Job.Finished do begin
      if (Mode='cancel') and (Watch.ElapsedMilliseconds>120) then Job.Cancel;
      if Watch.ElapsedMilliseconds>5000 then begin Job.Cancel;Job.WaitFor;raise Exception.Create('Mock transport exceeded 5 seconds');end;Sleep(5);
    end;
    Job.WaitFor;Require(Job.Success=Expected,'Unexpected transport result '+Mode+': '+Job.ErrorText);
    if Expected then begin
      Require(Job.Answer='画像を受信','UTF-8 answer text changed');
      Require(FileExists(Job.ImagePath),'Received image missing');Candidate:=ImportDesignImage(Job.ImagePath,6);
      Require(Candidate.SHA256<>'','Received image was not validated');
      Require(DesignRequestCurrent(Req,Req.Id,State.Designs[6]),'Fresh request rejected');
      Require(not DesignRequestCurrent(Req,'cancelled',State.Designs[6]),'Cancelled request accepted');
      Require(not ApplyDesignCandidate(State.Designs,Req,'cancelled',Candidate),'Cancelled candidate adopted');Require(State.ToJSON=Unchanged,'Cancelled adoption changed settings');
      Require(Candidate.SHA256<>State.Designs[6].SHA256,'Mock did not produce a different design');
      Require(ApplyDesignCandidate(State.Designs,Req,Req.Id,Candidate),'Fresh candidate adoption failed');Require(State.Designs[6].SHA256=Candidate.SHA256,'Adoption did not select received image');Require(State.Designs[8].SHA256=Saved.Designs[8].SHA256,'Adoption changed another design');State:=Saved;
      State.Designs[6].Memo:=State.Designs[6].Memo+' changed';Require(not DesignRequestCurrent(Req,Req.Id,State.Designs[6]),'Old context accepted');Require(not ApplyDesignCandidate(State.Designs,Req,Req.Id,Candidate),'Old candidate adopted');State:=Saved;
    end;
    Require(State.ToJSON=Unchanged,'Transport changed settings before adoption');Results.AddPair(Mode,'passed');
  finally Job.Free;end;
end;
begin
  Root:=TJSONObject.Create;Bitmap:=nil;Decoded:=nil;Frame:=nil;Renderer:=nil;Audio:=nil;
  OldExe:=GetEnvironmentVariable('CODEX_PIPE_EXE');
  try
    try
      Folder:=TPath.Combine(ModuleFolder,'Verification\Design');ForceDirectories(Folder);
      SpritePath:=TPath.Combine(Folder,'source-sprite.png');BackgroundPath:=TPath.Combine(Folder,'source-background.png');
      Bitmap:=Vcl.Graphics.TBitmap.Create;Bitmap.PixelFormat:=pf32bit;Bitmap.SetSize(64,64);Bitmap.AlphaFormat:=afPremultiplied;
      for Y:=0 to 63 do begin P:=Bitmap.ScanLine[Y];for X:=0 to 63 do begin
        P[0]:=0;P[1]:=0;P[2]:=0;P[3]:=0;
        if (Y>5) and (Y<55) and (Abs(X-32)<(55-Y)/2) then begin P[0]:=30;P[1]:=80;P[2]:=230;P[3]:=255;end;
        if (Y=32) and (X=32) then begin P[0]:=0;P[1]:=0;P[2]:=128;P[3]:=128;end;Inc(P,4);
      end;end;
      WriteDesignPNG(Bitmap,SpritePath);Decoded:=ReadDesignBitmap(SpritePath);P:=Decoded.ScanLine[32];Inc(P,32*4);
      Require((Abs(Integer(P[2])-128)<=1) and (P[3]=128),'PNG alpha/premultiplied round trip is wrong');FreeAndNil(Decoded);
      for Y:=0 to 63 do begin P:=Bitmap.ScanLine[Y];for X:=0 to 63 do begin P[0]:=60+Y;P[1]:=10+X;P[2]:=5;P[3]:=255;Inc(P,4);end;end;WriteDesignPNG(Bitmap,BackgroundPath);
      OriginalHash:=THashSHA2.GetHashStringFromFile(SpritePath);State:=TRhythmSettings.Defaults;State.Music:=ParamStr(1);State.Direction:=1;
      Require(TRhythmSettings.TryJSON('{"schema":1,"music":"legacy.wav","direction":1,"sensitivity":72}',Loaded),'Old JSON rejected');Require((Loaded.Music='legacy.wav') and (Loaded.Sensitivity=72) and (DesignKey(Loaded.Designs)=''),'Old settings changed');
      for I:=0 to RHYTHM_DESIGN_COUNT-1 do begin
        Info:=DesignInfo(I);if Info.Background then Imported:=ImportDesignImage(BackgroundPath,I) else Imported:=ImportDesignImage(SpritePath,I);
        State.Designs[I]:=Imported;State.Designs[I].Memo:='希望 '+Info.Title;
        Decoded:=ReadDesignBitmap(ResolveDesignImage(Imported));try Require((Decoded.Width=Info.Width) and (Decoded.Height=Info.Height),'Canonical resolution mismatch');finally FreeAndNil(Decoded);end;
      end;
      Require(THashSHA2.GetHashStringFromFile(SpritePath)=OriginalHash,'Source image modified');
      Require(TRhythmSettings.TryJSON(State.ToJSON,Loaded),'Custom JSON rejected');Require(Loaded.ToJSON=State.ToJSON,'Custom settings round trip changed values');
      Saved:=State;State.Designs[6].Memo:='changed locally';Require(Saved.Designs[6].Memo<>State.Designs[6].Memo,'Object settings share mutable design storage');State:=Saved;
      Request:=NewDesignRequest(6,Default(TRhythmDesign));Require((Pos('256',Request.Prompt)>0) and (Pos('transparent alpha PNG',Request.Prompt)>0) and (Pos('orientation',Request.Prompt)>0),'Empty memo lacks mandatory prompt requirements');
      Audio:=LoadCachedRhythmAudio(ParamStr(1),50);Require(Audio<>nil,'Prepare sample analysis first');Renderer:=TRhythmRenderer.Create;Frame:=Vcl.Graphics.TBitmap.Create;Frame.PixelFormat:=pf32bit;Frame.SetSize(1280,720);
      Renderer.Render(Frame,Audio,14.48,0);DefaultHash:=FrameHash;Renderer.ApplyDesigns(State.Designs);Renderer.Render(Frame,Audio,14.48,0);CustomHash:=FrameHash;Require(CustomHash<>DefaultHash,'Custom images do not affect rendering');
      for Direction:=0 to 1 do begin Renderer.Render(Frame,Audio,14.48,Direction);CustomHash:=FrameHash;Frame.SaveToFile(TPath.Combine(Folder,'custom-direction'+IntToStr(Direction)+'.bmp'));Renderer.Render(Frame,Audio,29.8,Direction);Renderer.Render(Frame,Audio,14.48,Direction);Require(CustomHash=FrameHash,'Custom seek is nondeterministic');end;
      Renderer.UseD2D:=False;Renderer.Render(Frame,Audio,14.48,0);Frame.SaveToFile(TPath.Combine(Folder,'custom-gdi.bmp'));Renderer.UseD2D:=True;
      Loaded:=TRhythmSettings.Defaults;Renderer.ApplyDesigns(Loaded.Designs);Renderer.Render(Frame,Audio,14.48,0);Require(FrameHash=DefaultHash,'Reset did not restore accepted default render');
      Loaded:=State;Loaded.Designs[6].Path:='';Loaded.Designs[6].SHA256:='';Require(Loaded.Designs[8].SHA256=State.Designs[8].SHA256,'Individual reset changed another asset');
      Loaded:=State;Loaded.Designs[6].SHA256[1]:='x';Require(not TRhythmSettings.TryJSON(Loaded.ToJSON,Saved),'Invalid custom asset reference accepted');Saved:=State;
      TFile.WriteAllText(TPath.Combine(Folder,'custom-state.json'),State.ToJSON,TEncoding.UTF8);
      Results:=TJSONObject.Create;Root.AddPair('mockTransport',Results);SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(TPath.Combine(ModuleFolder,'MockCodex.exe')));
      if ParamCount>=2 then Transport(ParamStr(2),True) else begin
        Transport('success',True);Transport('base64',True);Transport('fragmented',True);Transport('early',True);
        Transport('failed',False);Transport('bad-json',False);Transport('missing-image',False);Transport('duplicate',False);Transport('cancel',False);
      end;
      Root.AddPair('checks',TJSONNumber.Create(Checks));Root.AddPair('sourceImageUnchanged',TJSONBool.Create(True));Root.AddPair('defaultRenderRestored',TJSONBool.Create(True));Root.AddPair('realAIGenerationExecuted',TJSONBool.Create(False));Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.ClassName+': '+E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    if Folder<>'' then begin
      if ParamCount>=2 then TFile.WriteAllText(TPath.Combine(Folder,'design-utf8-fragmented.json'),Root.ToJSON,TEncoding.UTF8)
      else TFile.WriteAllText(TPath.Combine(Folder,'design-smoke.json'),Root.ToJSON,TEncoding.UTF8);
    end;Writeln(Root.ToJSON);
  finally SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(OldExe));Audio.Free;Renderer.Free;Frame.Free;Decoded.Free;Bitmap.Free;Root.Free;end;
  if ErrorText<>'' then Halt(1);
end.
